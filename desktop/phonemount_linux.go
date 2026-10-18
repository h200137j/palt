// phonemount_linux.go shows each linked phone's storage as a folder,
// ~/PALT/<phone>, through FUSE. Nautilus lists it in the sidebar (a mount
// in the home folder) with an eject button. Every file operation becomes
// a files.* request on the link (desktop/phonefiles_app.go,
// mobile/lib/features/phone_files.dart); reads go in 512 KiB blocks with
// one block read ahead, writes are gathered into 512 KiB pieces.
package main

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/hanwen/go-fuse/v2/fs"
	"github.com/hanwen/go-fuse/v2/fuse"

	"palt/internal/link"
)

const (
	mountBlock     = 512 * 1024
	mountBlocks    = 8 // blocks cached per open file
	mountDirTTL    = 4 * time.Second
	mountLinger    = 2 * time.Minute // keep the folder this long after the phone goes
	mountIORequest = 30 * time.Second
)

// phoneFS is one mounted phone.
type phoneFS struct {
	app    *App
	device string
	root   string // the phone's storage path, e.g. /storage/emulated/0

	mu   sync.Mutex
	dirs map[string]*mountDir // listings by phone path
}

type mountDir struct {
	at      time.Time
	entries map[string]PhoneFile
}

func (p *phoneFS) link() (*link.Link, syscall.Errno) {
	l := p.app.links.GetByName(p.device)
	if l == nil {
		return nil, syscall.EHOSTDOWN
	}
	return l, 0
}

// request sends one files.* request and maps the phone's errors to errnos.
func (p *phoneFS) request(t string, body, out any) syscall.Errno {
	l, errno := p.link()
	if errno != 0 {
		return errno
	}
	pk, err := l.Request(t, body, mountIORequest)
	if err == nil {
		if out == nil {
			out = &struct{}{}
		}
		err = smsReply(pk, out)
	}
	if err == nil {
		return 0
	}
	msg := strings.ToLower(err.Error())
	switch {
	case strings.Contains(msg, "no such file"), strings.Contains(msg, "gone"), strings.Contains(msg, "cannot find"):
		return syscall.ENOENT
	case strings.Contains(msg, "not allowed"), strings.Contains(msg, "permission denied"):
		return syscall.EACCES
	case strings.Contains(msg, "not empty"):
		return syscall.ENOTEMPTY
	case strings.Contains(msg, "exists"):
		return syscall.EEXIST
	case strings.Contains(msg, "no space"):
		return syscall.ENOSPC
	case strings.Contains(msg, "didn't answer"), strings.Contains(msg, "link closed"):
		return syscall.EHOSTDOWN
	}
	log.Printf("[mount] %s %s: %v", p.device, t, err)
	return syscall.EIO
}

// list returns a phone folder's entries, from a short-lived cache.
func (p *phoneFS) list(dir string) (map[string]PhoneFile, syscall.Errno) {
	p.mu.Lock()
	if d, ok := p.dirs[dir]; ok && time.Since(d.at) < mountDirTTL {
		p.mu.Unlock()
		return d.entries, 0
	}
	p.mu.Unlock()
	var f PhoneFolder
	if errno := p.request("files.list", map[string]string{"path": dir}, &f); errno != 0 {
		return nil, errno
	}
	if !f.Access {
		return nil, syscall.EACCES
	}
	entries := make(map[string]PhoneFile, len(f.Entries))
	for _, e := range f.Entries {
		entries[e.Name] = e
	}
	p.mu.Lock()
	p.dirs[dir] = &mountDir{at: time.Now(), entries: entries}
	p.mu.Unlock()
	return entries, 0
}

// forget drops cached listings of the folders holding these paths.
func (p *phoneFS) forget(paths ...string) {
	p.mu.Lock()
	for _, x := range paths {
		delete(p.dirs, path.Dir(x))
		delete(p.dirs, x)
	}
	p.mu.Unlock()
}

func fillAttr(out *fuse.Attr, f PhoneFile) {
	if f.Dir {
		out.Mode = fuse.S_IFDIR | 0o755
		out.Size = 4096
	} else {
		out.Mode = fuse.S_IFREG | 0o644
		out.Size = uint64(f.Size)
	}
	out.Nlink = 1
	out.Blocks = (out.Size + 511) / 512
	t := time.UnixMilli(f.Modified)
	out.SetTimes(&t, &t, &t)
	out.Uid = uint32(os.Getuid())
	out.Gid = uint32(os.Getgid())
}

// ─── Nodes ───────────────────────────────────────────────────────────────────

// phoneNode is a file or folder; its phone path follows from its place in
// the tree, so renames need no bookkeeping.
type phoneNode struct {
	fs.Inode
	fsys *phoneFS
}

var (
	_ fs.NodeLookuper  = (*phoneNode)(nil)
	_ fs.NodeReaddirer = (*phoneNode)(nil)
	_ fs.NodeGetattrer = (*phoneNode)(nil)
	_ fs.NodeSetattrer = (*phoneNode)(nil)
	_ fs.NodeOpener    = (*phoneNode)(nil)
	_ fs.NodeCreater   = (*phoneNode)(nil)
	_ fs.NodeMkdirer   = (*phoneNode)(nil)
	_ fs.NodeUnlinker  = (*phoneNode)(nil)
	_ fs.NodeRmdirer   = (*phoneNode)(nil)
	_ fs.NodeRenamer   = (*phoneNode)(nil)
	_ fs.NodeStatfser  = (*phoneNode)(nil)
)

func (n *phoneNode) phonePath() string {
	if rel := n.Path(nil); rel != "" {
		return n.fsys.root + "/" + rel
	}
	return n.fsys.root
}

func (n *phoneNode) child(name string) string { return n.phonePath() + "/" + name }

func (n *phoneNode) newChild(ctx context.Context, f PhoneFile) *fs.Inode {
	mode := uint32(fuse.S_IFREG)
	if f.Dir {
		mode = fuse.S_IFDIR
	}
	return n.NewInode(ctx, &phoneNode{fsys: n.fsys}, fs.StableAttr{Mode: mode})
}

func (n *phoneNode) Lookup(ctx context.Context, name string, out *fuse.EntryOut) (*fs.Inode, syscall.Errno) {
	entries, errno := n.fsys.list(n.phonePath())
	if errno != 0 {
		return nil, errno
	}
	f, ok := entries[name]
	if !ok {
		return nil, syscall.ENOENT
	}
	fillAttr(&out.Attr, f)
	return n.newChild(ctx, f), 0
}

func (n *phoneNode) Readdir(ctx context.Context) (fs.DirStream, syscall.Errno) {
	entries, errno := n.fsys.list(n.phonePath())
	if errno != 0 {
		return nil, errno
	}
	list := make([]fuse.DirEntry, 0, len(entries))
	for name, f := range entries {
		mode := uint32(fuse.S_IFREG)
		if f.Dir {
			mode = fuse.S_IFDIR
		}
		list = append(list, fuse.DirEntry{Name: name, Mode: mode})
	}
	return fs.NewListDirStream(list), 0
}

// stat reads this node's entry from its folder's listing.
func (n *phoneNode) stat() (PhoneFile, syscall.Errno) {
	if n.IsRoot() {
		return PhoneFile{Dir: true, Modified: time.Now().UnixMilli()}, 0
	}
	p := n.phonePath()
	entries, errno := n.fsys.list(path.Dir(p))
	if errno != 0 {
		return PhoneFile{}, errno
	}
	f, ok := entries[path.Base(p)]
	if !ok {
		return PhoneFile{}, syscall.ENOENT
	}
	return f, 0
}

func (n *phoneNode) Getattr(ctx context.Context, fh fs.FileHandle, out *fuse.AttrOut) syscall.Errno {
	f, errno := n.stat()
	if h, ok := fh.(*phoneHandle); ok {
		// An open file knows its size better than a cached listing.
		f.Size = h.currentSize()
		errno = 0
	}
	if errno != 0 {
		return errno
	}
	fillAttr(&out.Attr, f)
	out.SetTimeout(time.Second)
	return 0
}

func (n *phoneNode) Setattr(ctx context.Context, fh fs.FileHandle, in *fuse.SetAttrIn, out *fuse.AttrOut) syscall.Errno {
	if size, ok := in.GetSize(); ok {
		if h, ok := fh.(*phoneHandle); ok {
			if errno := h.flush(); errno != 0 {
				return errno
			}
		}
		p := n.phonePath()
		if errno := n.fsys.request("files.truncate", map[string]any{"path": p, "size": size}, nil); errno != 0 {
			return errno
		}
		n.fsys.forget(p)
		if h, ok := fh.(*phoneHandle); ok {
			h.truncated(int64(size))
		}
	}
	// Times and modes can't be set on the phone; accept them quietly so
	// copies don't fail.
	return n.Getattr(ctx, fh, out)
}

func (n *phoneNode) Open(ctx context.Context, flags uint32) (fs.FileHandle, uint32, syscall.Errno) {
	f, errno := n.stat()
	if errno != 0 {
		return nil, 0, errno
	}
	p := n.phonePath()
	if flags&syscall.O_TRUNC != 0 {
		if errno := n.fsys.request("files.truncate", map[string]any{"path": p, "size": 0}, nil); errno != 0 {
			return nil, 0, errno
		}
		n.fsys.forget(p)
		f.Size = 0
	}
	return newPhoneHandle(n.fsys, p, f.Size), 0, 0
}

func (n *phoneNode) Create(ctx context.Context, name string, flags, mode uint32, out *fuse.EntryOut) (*fs.Inode, fs.FileHandle, uint32, syscall.Errno) {
	p := n.child(name)
	if errno := n.fsys.request("files.write", map[string]any{"path": p, "offset": 0, "data": "", "create": true}, nil); errno != 0 {
		return nil, nil, 0, errno
	}
	n.fsys.forget(p)
	f := PhoneFile{Name: name, Modified: time.Now().UnixMilli()}
	fillAttr(&out.Attr, f)
	return n.newChild(ctx, f), newPhoneHandle(n.fsys, p, 0), 0, 0
}

func (n *phoneNode) Mkdir(ctx context.Context, name string, mode uint32, out *fuse.EntryOut) (*fs.Inode, syscall.Errno) {
	p := n.child(name)
	if errno := n.fsys.request("files.mkdir", map[string]string{"path": p}, nil); errno != 0 {
		return nil, errno
	}
	n.fsys.forget(p)
	f := PhoneFile{Name: name, Dir: true, Modified: time.Now().UnixMilli()}
	fillAttr(&out.Attr, f)
	return n.newChild(ctx, f), 0
}

func (n *phoneNode) remove(name string) syscall.Errno {
	p := n.child(name)
	errno := n.fsys.request("files.delete", map[string]any{"paths": []string{p}}, nil)
	n.fsys.forget(p)
	return errno
}

func (n *phoneNode) Unlink(ctx context.Context, name string) syscall.Errno { return n.remove(name) }

func (n *phoneNode) Rmdir(ctx context.Context, name string) syscall.Errno {
	// The phone deletes folders with everything in them; rmdir must not.
	if entries, errno := n.fsys.list(n.child(name)); errno == 0 && len(entries) > 0 {
		return syscall.ENOTEMPTY
	}
	return n.remove(name)
}

func (n *phoneNode) Rename(ctx context.Context, name string, newParent fs.InodeEmbedder, newName string, flags uint32) syscall.Errno {
	np, ok := newParent.(*phoneNode)
	if !ok {
		return syscall.EXDEV
	}
	if flags != 0 {
		return syscall.EINVAL // no RENAME_EXCHANGE / NOREPLACE
	}
	from, to := n.child(name), np.child(newName)
	errno := n.fsys.request("files.rename", map[string]string{"from": from, "to": to}, nil)
	n.fsys.forget(from, to)
	return errno
}

func (n *phoneNode) Statfs(ctx context.Context, out *fuse.StatfsOut) syscall.Errno {
	var s struct{ Total, Free int64 }
	if n.fsys.request("files.space", map[string]any{}, &s) != 0 || s.Total == 0 {
		// Older phone app: say there's room rather than block copies.
		s.Total, s.Free = 1<<40, 1<<39
	}
	const bs = 4096
	out.Bsize, out.Frsize = bs, bs
	out.Blocks = uint64(s.Total / bs)
	out.Bfree = uint64(s.Free / bs)
	out.Bavail = out.Bfree
	out.NameLen = 255
	return 0
}

// ─── Open files ──────────────────────────────────────────────────────────────

type phoneHandle struct {
	fsys *phoneFS
	path string

	mu       sync.Mutex
	size     int64
	blocks   map[int64][]byte
	order    []int64 // cached block indexes, oldest first
	inflight map[int64]chan struct{}
	wbuf     []byte // writes not yet sent, starting at woff
	woff     int64
	wrote    bool
}

var (
	_ fs.FileReader   = (*phoneHandle)(nil)
	_ fs.FileWriter   = (*phoneHandle)(nil)
	_ fs.FileFlusher  = (*phoneHandle)(nil)
	_ fs.FileReleaser = (*phoneHandle)(nil)
	_ fs.FileFsyncer  = (*phoneHandle)(nil)
)

func newPhoneHandle(p *phoneFS, path string, size int64) *phoneHandle {
	return &phoneHandle{fsys: p, path: path, size: size, blocks: map[int64][]byte{}, inflight: map[int64]chan struct{}{}}
}

func (h *phoneHandle) currentSize() int64 {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.size
}

func (h *phoneHandle) truncated(size int64) {
	h.mu.Lock()
	h.size = size
	h.dropBlocksLocked()
	h.mu.Unlock()
}

func (h *phoneHandle) dropBlocksLocked() {
	h.blocks = map[int64][]byte{}
	h.order = nil
}

// block returns block i, fetching it once even when asked for twice.
func (h *phoneHandle) block(i int64) ([]byte, syscall.Errno) {
	for {
		h.mu.Lock()
		if b, ok := h.blocks[i]; ok {
			h.mu.Unlock()
			return b, 0
		}
		if ch, ok := h.inflight[i]; ok {
			h.mu.Unlock()
			<-ch
			continue
		}
		ch := make(chan struct{})
		h.inflight[i] = ch
		h.mu.Unlock()

		var r struct{ Data string }
		errno := h.fsys.request("files.read", map[string]any{"path": h.path, "offset": i * mountBlock, "length": mountBlock}, &r)
		var data []byte
		if errno == 0 {
			var err error
			if data, err = base64.StdEncoding.DecodeString(r.Data); err != nil {
				errno = syscall.EIO
			}
		}

		h.mu.Lock()
		delete(h.inflight, i)
		if errno == 0 {
			h.blocks[i] = data
			h.order = append(h.order, i)
			if len(h.order) > mountBlocks {
				delete(h.blocks, h.order[0])
				h.order = h.order[1:]
			}
		}
		close(ch)
		h.mu.Unlock()
		return data, errno
	}
}

func (h *phoneHandle) Read(ctx context.Context, dest []byte, off int64) (fuse.ReadResult, syscall.Errno) {
	if errno := h.flush(); errno != 0 {
		return nil, errno
	}
	n := 0
	for n < len(dest) {
		at := off + int64(n)
		i := at / mountBlock
		b, errno := h.block(i)
		if errno != 0 {
			return nil, errno
		}
		start := int(at - i*mountBlock)
		if start >= len(b) {
			break // end of file
		}
		n += copy(dest[n:], b[start:])
		if len(b) < mountBlock {
			break
		}
		// Reading forward: fetch the next block while this one is used.
		h.mu.Lock()
		_, have := h.blocks[i+1]
		_, busy := h.inflight[i+1]
		h.mu.Unlock()
		if !have && !busy {
			go h.block(i + 1)
		}
	}
	return fuse.ReadResultData(dest[:n]), 0
}

func (h *phoneHandle) Write(ctx context.Context, data []byte, off int64) (uint32, syscall.Errno) {
	h.mu.Lock()
	contiguous := len(h.wbuf) > 0 && off == h.woff+int64(len(h.wbuf))
	h.mu.Unlock()
	if len(h.wbuf) > 0 && !contiguous {
		if errno := h.flush(); errno != 0 {
			return 0, errno
		}
	}
	h.mu.Lock()
	if len(h.wbuf) == 0 {
		h.woff = off
	}
	h.wbuf = append(h.wbuf, data...)
	h.size = max(h.size, off+int64(len(data)))
	h.dropBlocksLocked()
	full := len(h.wbuf) >= mountBlock
	h.mu.Unlock()
	if full {
		if errno := h.flush(); errno != 0 {
			return 0, errno
		}
	}
	return uint32(len(data)), 0
}

// flush sends gathered writes to the phone.
func (h *phoneHandle) flush() syscall.Errno {
	h.mu.Lock()
	buf, off := h.wbuf, h.woff
	h.wbuf = nil
	h.mu.Unlock()
	for len(buf) > 0 {
		chunk := buf[:min(len(buf), mountBlock)]
		errno := h.fsys.request("files.write", map[string]any{
			"path": h.path, "offset": off, "data": base64.StdEncoding.EncodeToString(chunk),
		}, nil)
		if errno != 0 {
			return errno
		}
		h.mu.Lock()
		h.wrote = true
		h.mu.Unlock()
		buf, off = buf[len(chunk):], off+int64(len(chunk))
	}
	return 0
}

func (h *phoneHandle) Flush(ctx context.Context) syscall.Errno {
	errno := h.flush()
	h.mu.Lock()
	wrote := h.wrote
	h.mu.Unlock()
	if wrote {
		h.fsys.forget(h.path)
	}
	return errno
}

func (h *phoneHandle) Fsync(ctx context.Context, flags uint32) syscall.Errno { return h.flush() }

func (h *phoneHandle) Release(ctx context.Context) syscall.Errno { return h.flush() }

// ─── Mounting ────────────────────────────────────────────────────────────────

type phoneMount struct {
	server  *fuse.Server
	dir     string
	lostAt  time.Time // when the phone's link went, zero while linked
	ejected bool      // the user unmounted it; wait for the next link
	since   time.Time // the link it was mounted for
}

var mounts struct {
	sync.Mutex
	byDevice map[string]*phoneMount
}

func mountDirFor(device string) (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	name := strings.NewReplacer("/", "-", "\x00", "").Replace(device)
	return filepath.Join(home, "PALT", name), nil
}

func (a *App) mountPhone(l *link.Link) (*phoneMount, error) {
	dir, err := mountDirFor(l.Peer.Name)
	if err != nil {
		return nil, err
	}
	// A mount left behind by a crash blocks the folder; clear it.
	exec.Command("fusermount3", "-uz", dir).Run()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	var root PhoneFolder
	pk, err := l.Request("files.list", map[string]string{"path": ""}, filesTimeout)
	if err == nil {
		err = smsReply(pk, &root)
	}
	if err != nil {
		return nil, err
	}
	if root.Path == "" {
		return nil, errors.New("phone gave no storage path")
	}
	pfs := &phoneFS{app: a, device: l.Peer.Name, root: root.Path, dirs: map[string]*mountDir{}}
	sec := time.Second
	server, err := fs.Mount(dir, &phoneNode{fsys: pfs}, &fs.Options{
		EntryTimeout: &sec,
		AttrTimeout:  &sec,
		MountOptions: fuse.MountOptions{
			FsName:        "palt",
			Name:          "palt",
			DisableXAttrs: true,
			MaxReadAhead:  mountBlock,
		},
	})
	if err != nil {
		return nil, fmt.Errorf("mount %s: %w", dir, err)
	}
	log.Printf("[mount] %s at %s", l.Peer.Name, dir)
	return &phoneMount{server: server, dir: dir, since: l.Since()}, nil
}

// setupPhoneMounts keeps a folder mounted for every linked phone that has
// "mountFiles" on, and takes it away a while after the phone goes.
func (a *App) setupPhoneMounts() {
	mounts.byDevice = map[string]*phoneMount{}
	go func() {
		for ; ; time.Sleep(3 * time.Second) {
			linked := map[string]*link.Link{}
			for _, l := range a.links.Links() {
				if l.Peer.OS == "android" && l.Supports("files.read") && a.setting(l.Peer.Name, "mountFiles") {
					linked[l.Peer.Name] = l
				}
			}
			mounts.Lock()
			for name, m := range mounts.byDevice {
				l := linked[name]
				switch {
				case m.ejected:
					// Mount again only for a new link, not the one the user ejected on.
					if l == nil || !l.Since().Equal(m.since) {
						delete(mounts.byDevice, name)
					}
				case l != nil:
					m.lostAt = time.Time{}
				case m.lostAt.IsZero():
					m.lostAt = time.Now()
				case time.Since(m.lostAt) > mountLinger || !a.setting(name, "mountFiles"):
					m.server.Unmount()
					delete(mounts.byDevice, name)
				}
			}
			for name, l := range linked {
				if _, ok := mounts.byDevice[name]; ok {
					continue
				}
				m, err := a.mountPhone(l)
				if err != nil {
					log.Printf("[mount] %s: %v", name, err)
					// Don't retry every 3 s; wait for the next link.
					mounts.byDevice[name] = &phoneMount{ejected: true, since: l.Since()}
					continue
				}
				mounts.byDevice[name] = m
				go func(m *phoneMount) {
					m.server.Wait()
					mounts.Lock()
					m.ejected = true // unmounted from Nautilus or by us
					mounts.Unlock()
				}(m)
			}
			mounts.Unlock()
		}
	}()
}

// unmountPhones takes every phone folder away, when PALT quits.
func unmountPhones() {
	mounts.Lock()
	defer mounts.Unlock()
	for _, m := range mounts.byDevice {
		if m.server != nil && !m.ejected {
			m.server.Unmount()
		}
	}
}
