# PALT Improvement Roadmap

PALT is a solid, well-architected local file transfer app. Below are prioritized improvements across every layer of the stack — from correctness bugs to major feature additions.

---

## 🔴 Priority 1 — Correctness & Reliability

### 1.1 `AutoAcceptOffer` is a no-op duplicate
**File:** `desktop/app.go` · Lines 161–171

`AutoAcceptOffer` and `AcceptOffer` are **identical**. The only meaningful difference should be that auto-accept skips the UI dialog entirely — but the current flow still waits on `OnOffer` first (which blocks even for auto-trusted peers). 

**Fix:** Short-circuit `OnOffer` in `app.go` before pushing to the UI by caching trusted devices **in Go** (not only in browser `localStorage`). This prevents any UI round-trip for trusted senders.

```go
// In startup(), before emitting the `transfer_offer` event:
if a.isTrusted(meta.SenderName) {
    return true // auto-accept immediately
}
wailsruntime.EventsEmit(a.ctx, "transfer_offer", meta)
```

### 1.2 Filename collision on receive — files silently overwritten
**File:** `desktop/internal/transfer/server.go` · Line 121

`os.Create(savePath)` unconditionally overwrites an existing file with the same name in `~/Downloads/PALT`. There is no deduplication logic.

**Fix:** Add an indexed suffix before the extension if the path already exists:
```go
// my_file.png → my_file (1).png → my_file (2).png
savePath = resolveUniqueFilePath(downloadDir, f.Name)
```

### 1.3 Directory sends silently skipped — no user feedback
**File:** `desktop/internal/transfer/client.go` · Line 31

When a user drag-selects a folder, `SendFiles` silently skips it (`continue`) with only a local log line. The caller never learns a folder was excluded, so the sent file count in the UI will mismatch what the user expected.

**Fix:** Either return a typed error listing skipped directories, or recursively walk them (future feature).

### 1.4 Self-discovery guard uses name comparison only
**File:** `desktop/internal/discovery/service.go` · Line 248

```go
if entry.Instance == s.deviceName && entry.Port == s.port {
```
If two machines on the network share a hostname (common in corporate environments), they will filter each other out. 

**Fix:** Generate a stable UUID at startup, embed it in the mDNS TXT record as `id=<uuid>`, and use that for self-exclusion instead of the device name.

### 1.5 Race condition: `s.running` flag is not atomic
**File:** `desktop/internal/transfer/server.go` · Lines 40, 57, 60

`s.running` is a plain `bool` accessed from multiple goroutines without a mutex or `atomic.Bool`. This is a data race.

**Fix:**
```go
import "sync/atomic"
// ...
var running atomic.Bool
```

---

## 🟠 Priority 2 — UX Improvements

### 2.1 Replace polling with Wails event push for peer updates
**File:** `desktop/frontend/src/App.tsx` · Line 49

The UI polls `GetPeers()` every **5 seconds**. This means a newly detected device can take up to 5 seconds to appear, and a disappeared device can stay shown for up to 5 seconds after it's gone.

**Fix:** Emit a `peers_changed` Wails event directly from `handleEntry()` and `evictStalePeers()` in `service.go`, and subscribe to it in the UI. The poll can remain as a watchdog at a longer interval (e.g., 30s).

### 2.2 No transfer history / completed transfer log
Currently, when `transfer_complete` fires, the progress snackbar just disappears. There is no record of what was transferred, when, and from/to whom.

**Fix:** Add a simple in-memory (and optionally persisted) `TransferHistory` log with entries shown in a drawer or separate tab:
- File names + sizes
- Sender/receiver
- Timestamp
- Transfer duration + effective speed (MB/s)

### 2.3 No speed/ETA display in the progress snackbar
**File:** `desktop/frontend/src/components/ProgressSnack.tsx`

The progress widget shows bytes transferred but no transfer **speed** nor estimated **ETA**. For large files this is a significant usability gap.

**Fix:** Track the start timestamp and compute:
```ts
const speed = written / ((Date.now() - startedAt) / 1000); // bytes/s
const eta = (total - written) / speed;
```

### 2.4 `TransferDialog` doesn't list individual filenames when batch > 1
**File:** `desktop/frontend/src/components/TransferDialog.tsx` · Line 56

When `fileCount > 1`, the dialog just says `"5 items"` with a total size. The recipient has no idea what they're about to accept.

**Fix:** Render a scrollable list (max-height capped) of the individual filenames + sizes, collapsed behind a "Show files" toggle for large batches.

### 2.5 No "Open folder" shortcut after receive completes
After accepting a transfer, the user has to manually navigate to `~/Downloads/PALT`. 

**Fix:** Add an `OpenReceiveFolder` Wails binding that calls `xdg-open` (or equivalent) on the download directory, triggered by a toast button after `transfer_complete`.

### 2.6 Empty state has no instructional value for first-time users
**File:** `desktop/frontend/src/components/EmptyState.tsx`

The empty state tells users no devices were found, but gives no guidance on **why** (e.g., "Make sure PALT is open on another device on the same Wi-Fi network").

---

## 🟡 Priority 3 — Feature Additions

### 3.1 Drag-and-drop file sending
Instead of clicking the peer card → opening a file dialog, users should be able to **drag files from the file manager directly onto a PeerCard** to initiate a send. This is the most natural gesture for a file transfer app.

**Implementation:** Add a `onDragOver` / `onDrop` handler to `PeerCard.tsx` that extracts `event.dataTransfer.files` and passes the file paths to `SendFile`.

> **Note:** Wails may need a bridge for native-path extraction from the drag event; worth testing first.

### 3.2 Clipboard / text sharing
Beyond files, allow peers to send a **text snippet** (a URL, a command, a password) directly to a peer's clipboard. This is a killer feature for developer workflows.

**Protocol change:** Add a new `ActionText` in `protocol.go` alongside `ActionOffer`. The receiver directly writes the payload to the system clipboard.

### 3.3 Peer nickname / alias system
Hostnames like `SM-S938B` or `uriel-dell` are opaque. Let users assign a friendly alias to a peer that's persisted in `localStorage` (desktop) and `SharedPreferences` (mobile).

### 3.4 macOS / Windows desktop support
The README explicitly says **"Linux Desktop"**. Wails natively supports macOS and Windows. The only blocker is the `webkit2gtk` build tags. Generalizing the build pipeline would dramatically expand reach.

### 3.5 Folder sending (recursive tree)
`client.go` currently skips directories. Adding recursive directory traversal with proper relative path reconstruction on the receiver side would be a significant capability upgrade.

**Approach:** Walk the directory tree, collect all files, reconstruct relative paths in `FileMeta.Name` (e.g., `subdir/image.png`), and create intermediate directories on the receiver.

### 3.6 Sending from mobile to desktop (reverse direction already works, strengthen UX)
Currently the "Send" action is surface-level on mobile. Consider a **share-sheet integration** on Android so PALT appears as a share target in any app's share menu — letting users send images from the Gallery, documents from Files, etc., without opening PALT directly.

---

## 🔵 Priority 4 — Security & Protocol Hardening

### 4.1 No authentication between peers
The handshake has no cryptographic identity layer. Any device on the same LAN that knows the format can initiate a transfer. The manual accept dialog is the only guard — and trusted devices bypass even that.

**Recommendation:** Add an optional **PIN pairing** flow (similar to AirDrop's one-time trust model). On first connection from a new device, exchange and verify a short ephemeral PIN before the offer is presented.

### 4.2 No transfer encryption
All data streams over raw, unencrypted TCP. On shared/corporate Wi-Fi, this data is sniffable by anyone on the same segment.

**Recommendation:** Wrap the TCP connection in TLS with self-signed certs generated at startup (one cert per device, verified via TOFU — Trust On First Use). The Go `crypto/tls` package makes this straightforward.

### 4.3 Trusted device list stored only in browser localStorage
**File:** `desktop/frontend/src/App.tsx` · Lines 116–128

The `palt_trusted_devices` list lives in the Wails WebView's localStorage. This means:
- It can be wiped by clearing browser storage.
- It's not accessible to the Go backend (so the `AutoAcceptOffer` race noted in 1.1 exists).

**Fix:** Expose `AddTrustedDevice` / `GetTrustedDevices` / `RemoveTrustedDevice` Go bindings that persist to a config file (e.g., `~/.config/palt/trusted.json`).

### 4.4 `MaxOfferSize` of 8KB may be too tight for large batch filenames
**File:** `desktop/internal/transfer/protocol.go` · Line 13

If sending 200+ files with long filenames (e.g., full paths accidentally included), the handshake JSON can exceed 8KB and be rejected with a generic `io.ErrShortBuffer`.

**Fix:** Increase to 64KB or make it configurable. Also return a clearer error message to the UI when this limit is hit.

---

## ⚪ Priority 5 — Architecture & Developer Experience

### 5.1 No unit or integration tests
Neither `desktop/` nor `mobile/` has any tests (`mobile/test/` contains only the default Flutter widget test stub). The Go `transfer` and `discovery` packages have zero test coverage.

**Recommended starting points:**
- `TestSendReceive`: spin up a real TCP server/client pair and verify file receipt.
- `TestReadWriteOffer`: round-trip marshal/unmarshal of `Metadata`.
- `TestEvictStalePeers`: advance a fake clock and verify TTL behavior.

### 5.2 Hardcoded port `9876` with no conflict handling
If port 9876 is already in use (e.g., another PALT instance or another app), `net.Listen` fails with a fatal error. 

**Fix:** Find a free port dynamically if 9876 is in use, and advertise that port in mDNS instead.

### 5.3 `log.Fatalf` in startup is too aggressive
**File:** `desktop/app.go` · Lines 70, 108

A failure to start the discovery service or TCP server causes the entire app to crash with no user-facing message. 

**Fix:** Surface these as app-level error states in the UI ("Could not start — port already in use?") rather than hard-crashing.

### 5.4 `go.mod` module path is just `palt`
**File:** `desktop/go.mod`

Using a bare name like `palt` is non-idiomatic and will clash if this ever becomes a Go module imported elsewhere.

**Fix:** Use a proper module path: `github.com/h200137j/palt/desktop`.

### 5.5 Missing `transfer_complete` event emission on the **receiver**
**File:** `desktop/internal/transfer/server.go`

The receiver finishes all file writes and logs success, but **never emits a `transfer_complete` Wails event**. The `OnProgress` callback reports progress, but the UI has no way to know the transfer actually finished on the incoming side (only the sender gets `transfer_complete`).

**Fix:** Add an `OnComplete func(transferID string)` callback to `Server` and wire it to a `transfer_complete` event, mirroring the sender side.

---

## Summary Table

| # | Area | Effort | Impact |
|---|------|--------|--------|
| 1.1 | Auto-accept race | Low | High |
| 1.2 | Filename collision | Low | High |
| 1.3 | Dir skip feedback | Low | Medium |
| 1.4 | Self-discovery UUID | Low | Medium |
| 1.5 | Atomic running flag | Low | High |
| 2.1 | Event-push peers | Medium | High |
| 2.2 | Transfer history | Medium | High |
| 2.3 | Speed/ETA display | Low | Medium |
| 2.4 | File list in dialog | Low | Medium |
| 2.5 | Open folder shortcut | Low | High |
| 3.1 | Drag-and-drop send | Medium | High |
| 3.2 | Text/clipboard share | Medium | High |
| 3.3 | Peer nicknames | Low | Medium |
| 3.4 | macOS/Windows | High | High |
| 3.5 | Folder sending | Medium | High |
| 4.1 | PIN pairing | High | High |
| 4.2 | TLS encryption | High | High |
| 4.3 | Go-persisted trust list | Low | High |
| 5.1 | Unit tests | High | High |
| 5.5 | Receiver complete event | Low | High |
