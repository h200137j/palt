// Package thumbs makes small JPEG previews of transferred pictures so the
// device thread can show them inline. Previews are cached on disk, keyed by
// the source path, size and modification time.
package thumbs

import (
	"bytes"
	"crypto/sha1"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"fmt"
	"image"
	"image/jpeg"
	"io"
	"os"
	"path/filepath"
	"strings"

	_ "image/gif"
	_ "image/png"

	"golang.org/x/image/draw"
	_ "golang.org/x/image/webp"
)

// MaxSide is the longest edge of a preview, in pixels.
const MaxSide = 480

// maxSourceBytes skips decoding absurdly large files.
const maxSourceBytes = 64 << 20

var ErrNotImage = errors.New("not a supported picture")

var imageExts = map[string]bool{".jpg": true, ".jpeg": true, ".png": true, ".gif": true, ".webp": true}

// IsImage reports whether name has a picture extension we can preview.
func IsImage(name string) bool {
	return imageExts[strings.ToLower(filepath.Ext(name))]
}

// Get returns a JPEG preview of the picture at path, using cacheDir when set.
func Get(path, cacheDir string) ([]byte, error) {
	if !IsImage(path) {
		return nil, ErrNotImage
	}
	st, err := os.Stat(path)
	if err != nil {
		return nil, err
	}
	if st.Size() > maxSourceBytes {
		return nil, fmt.Errorf("%s is too large to preview", filepath.Base(path))
	}

	var cachePath string
	if cacheDir != "" {
		h := sha1.Sum([]byte(fmt.Sprintf("%s|%d|%d|%d", path, st.Size(), st.ModTime().UnixNano(), MaxSide)))
		cachePath = filepath.Join(cacheDir, hex.EncodeToString(h[:])+".jpg")
		if b, err := os.ReadFile(cachePath); err == nil {
			return b, nil
		}
	}

	src, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	out, err := Make(src)
	if err != nil {
		return nil, err
	}
	if cachePath != "" {
		if os.MkdirAll(cacheDir, 0o700) == nil {
			_ = os.WriteFile(cachePath, out, 0o600)
		}
	}
	return out, nil
}

// Make decodes a picture, applies its EXIF orientation, scales it to fit
// MaxSide and encodes it as JPEG.
func Make(src []byte) ([]byte, error) { return MakeSize(src, MaxSide) }

// MakeSize is Make with a longest edge of maxSide pixels.
func MakeSize(src []byte, maxSide int) ([]byte, error) {
	img, _, err := image.Decode(bytes.NewReader(src))
	if err != nil {
		return nil, ErrNotImage
	}
	b := img.Bounds()
	w, h := b.Dx(), b.Dy()
	if w == 0 || h == 0 {
		return nil, ErrNotImage
	}
	scale := 1.0
	if w > maxSide || h > maxSide {
		if w >= h {
			scale = float64(maxSide) / float64(w)
		} else {
			scale = float64(maxSide) / float64(h)
		}
	}
	tw, th := max(1, int(float64(w)*scale)), max(1, int(float64(h)*scale))
	dst := image.NewRGBA(image.Rect(0, 0, tw, th))
	draw.ApproxBiLinear.Scale(dst, dst.Bounds(), img, b, draw.Src, nil)

	oriented := orient(dst, exifOrientation(src))
	var out bytes.Buffer
	if err := jpeg.Encode(&out, oriented, &jpeg.Options{Quality: 80}); err != nil {
		return nil, err
	}
	return out.Bytes(), nil
}

// orient applies EXIF orientation values 2–8 (1 or unknown = as stored).
func orient(src *image.RGBA, o int) image.Image {
	if o < 2 || o > 8 {
		return src
	}
	b := src.Bounds()
	w, h := b.Dx(), b.Dy()
	swap := o >= 5
	dw, dh := w, h
	if swap {
		dw, dh = h, w
	}
	dst := image.NewRGBA(image.Rect(0, 0, dw, dh))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			var dx, dy int
			switch o {
			case 2: // mirror horizontal
				dx, dy = w-1-x, y
			case 3: // rotate 180
				dx, dy = w-1-x, h-1-y
			case 4: // mirror vertical
				dx, dy = x, h-1-y
			case 5: // transpose
				dx, dy = y, x
			case 6: // rotate 90 clockwise
				dx, dy = h-1-y, x
			case 7: // transverse
				dx, dy = h-1-y, w-1-x
			case 8: // rotate 90 counter-clockwise
				dx, dy = y, w-1-x
			}
			dst.SetRGBA(dx, dy, src.RGBAAt(b.Min.X+x, b.Min.Y+y))
		}
	}
	return dst
}

// exifOrientation reads the EXIF Orientation tag from a JPEG, or returns 0.
func exifOrientation(src []byte) int {
	if len(src) < 4 || src[0] != 0xFF || src[1] != 0xD8 {
		return 0
	}
	r := bytes.NewReader(src[2:])
	for {
		var marker [2]byte
		if _, err := io.ReadFull(r, marker[:]); err != nil || marker[0] != 0xFF {
			return 0
		}
		if marker[1] == 0xDA || marker[1] == 0xD9 { // start of scan / end: no EXIF
			return 0
		}
		var lenBuf [2]byte
		if _, err := io.ReadFull(r, lenBuf[:]); err != nil {
			return 0
		}
		n := int(binary.BigEndian.Uint16(lenBuf[:])) - 2
		if n < 0 {
			return 0
		}
		seg := make([]byte, n)
		if _, err := io.ReadFull(r, seg); err != nil {
			return 0
		}
		if marker[1] == 0xE1 && len(seg) > 14 && string(seg[:6]) == "Exif\x00\x00" {
			return tiffOrientation(seg[6:])
		}
	}
}

func tiffOrientation(t []byte) int {
	if len(t) < 8 {
		return 0
	}
	var bo binary.ByteOrder
	switch string(t[:2]) {
	case "II":
		bo = binary.LittleEndian
	case "MM":
		bo = binary.BigEndian
	default:
		return 0
	}
	ifd := int(bo.Uint32(t[4:8]))
	if ifd+2 > len(t) {
		return 0
	}
	count := int(bo.Uint16(t[ifd : ifd+2]))
	for i := 0; i < count; i++ {
		e := ifd + 2 + i*12
		if e+12 > len(t) {
			return 0
		}
		if bo.Uint16(t[e:e+2]) == 0x0112 {
			return int(bo.Uint16(t[e+8 : e+10]))
		}
	}
	return 0
}
