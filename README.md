<div align="center">
  <img src="https://raw.githubusercontent.com/wailsapp/wails/master/website/static/img/wails-logo.svg" width="100"/>
  <br/>
  <h1>🚀 PALT</h1>
  <p><b>P</b>eer <b>A</b>nd <b>L</b>ocal <b>T</b>ransfer</p>
  <p><i>A frictionless, high-speed local network file transfer app for Linux Desktop and Android.</i></p>

  [![CI/CD](https://github.com/h200137j/palt/actions/workflows/release.yml/badge.svg)](https://github.com/h200137j/palt/actions/workflows/release.yml)
</div>

---

PALT bridges the gap between Desktop workspaces and Mobile environments over raw TCP. Forget messy USB cables or uploading sensitive files to cloud drives just to download them to your phone — PALT detects sibling devices dynamically over the local network via `mDNS` and funnels massive files point-to-point instantly. 

Powered by **Go** and **Wails** on the Desktop, and **Flutter** on Mobile.

![Showcase Demo]() <!-- You can add your screenshot links here! -->

## ✨ Features

- **Blazing Fast TCP Streaming:** Bypass the cloud. Core transfer architecture operates strictly over local interfaces for unthrottled maximum network speeds. 
- **Zero-Config Discovery:** True auto-discovery logic powered by ZeroConf / mDNS (`_palt._tcp.local.`). Your devices see each other the second they open the app.
- **Cross-Platform DNA:** First-class citizenship across Linux Desktop (Wails + React + MUI) and Android (Flutter + Material Design 3 + Riverpod).
- **Public Sandbox Safety:** Built-in handshake negotiations require manual acceptance of inbound files.
- **Native Android Bridging:** Delivered binaries dump directly into the native public `Downloads` directory ensuring seamless Gallery integration.

---

## 🏗️ Technical Architecture

PALT is developed as a dual-monorepo. 

```bash
palt/
├── .github/workflows/         # CI/CD Release Automation (.apk and .deb)
├── desktop/                   # Wails Linux App (Go Server + React Client)
│   ├── main.go                # Wails Entrypoint
│   ├── app.go                 # Native Wails Bindings
│   ├── internal/              
│   │   ├── discovery/         # Go mDNS advertiser + browser logic
│   │   └── transfer/          # High-speed raw TCP chunked streamer
│   └── frontend/              # Vite / React UI
│
└── mobile/                    # Flutter Android App
    ├── lib/
    │   ├── ui/                # Beautiful Material 3 Screens & Widgets
    │   ├── services/          # Android NSD (mDNS) & Socket streaming
    │   └── providers/         # Riverpod Async Notifiers & UI State
```

---

## 💻 Building from Source

### Prerequisites

| Platform | Tools Needed |
|------|---------|
| **Global** | Git |
| **Desktop** | Go ≥ 1.21, Node.js ≥ 18, [Wails v2 CLI](https://wails.io/docs/gettingstarted/installation/) |
| **Linux Deps** | `sudo apt install libgtk-3-dev libwebkit2gtk-4.1-dev build-essential` |
| **Mobile** | Flutter SDK ≥ 3.19, Android Studio (or CLI tools) |

### 1. The Desktop Application (Linux)

```bash
cd desktop

# Download core Go dependencies
go mod tidy

# Run in watch development mode (Live frontend reloading)
wails dev -tags webkit2_41

# Compile a static deployment binary
wails build -platform linux/amd64 -tags webkit2_41
```

### 2. The Mobile Application (Android)

```bash
cd mobile

# Install Dart package dependencies
flutter pub get

# Boot directly to connected physical device or emulator
flutter run
```

---

## 🔒 Under the Hood: Telemetry & State 

### Native Android Workarounds
Due to aggressive privacy changes introduced in modern Android builds, standard SDK properties like `Platform.localHostname` evaluate down to generic values like `localhost`, destroying dynamic discovery mappings if two Androids join the same network. 
PALT counters this by actively querying the HAL via `device_info_plus` to extract tangible model designations (e.g., *SM-S938B*) and bypassing typical string-based network deduplication with physical **IP Address binding**.

### Discovery Lifecycle
All peers broadcast on the `9876` networking channel. The service advertises TXT records that carry specific OS signatures (`linux`, `android`) to inject dynamic platform-specific icons into the host UI. Dead devices map onto a TTL reaper (Go) or trigger direct `removeWhere` events upon dropping out of multicast. 

---

<div align="center">
  <sub>Built by <a href="https://github.com/h200137j">uriel</a></sub>
</div>
