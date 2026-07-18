<div align="center">

# Screenshot OCR Copy 📸

[简体中文](README.zh.md) | **English** | [日本語](README.ja.md)

A lightweight macOS menu-bar screenshot OCR tool. Select any screen area, auto-recognize Chinese/English text, and copy to clipboard.

Pure native implementation, zero third-party dependencies, built on Apple Vision + ScreenCaptureKit.

</div>

## ✨ Features

- **One-shot capture & recognize** — Global hotkey (default `⌃⌘O`) to select area; releases to recognize
- **Chinese/English OCR** — Powered by Vision framework, accurate mode, supports Simplified/Traditional Chinese and English mixed text
- **Smart layout** — Auto-distinguishes paragraph breaks vs soft wraps, preserving original structure
- **Live preview** — See recognition results while dragging the selection
- **Auto copy** — Result is written to clipboard on completion
- **History** — Standalone panel search, supports any input method, grouped by date (Today / Yesterday / This Week / This Month / Earlier)
- **Liquid Glass toast** — macOS 26 native `glassEffect`, slide in/out animation + SF Symbols icons
- **Sound feedback** — Hero on success / Basso on failure
- **Launch at login** — Optional auto-start in background
- **Customizable** — Hotkey recording, toast/notification toggles, selection border width

## 📋 Requirements

- macOS 26.0 or later (Liquid Glass toast required)
- Apple Silicon (arm64)

## 🚀 Installation

### Option 1: Build from source (recommended)

```bash
git clone https://github.com/nadonghuang/screenshot-ocr-copy.git
cd screenshot-ocr-copy
./build.sh
```

`build.sh` compiles, packages, signs, and installs to `/Applications`, then launches the app.

### First-run permissions

After launch, grant the following in **System Settings → Privacy & Security**:

| Permission | Purpose | Required |
| --- | --- | --- |
| Screen Recording | Capture screen regions | ✅ Yes |
| Input Monitoring | Global hotkey listening | ✅ Yes |
| Accessibility | Interaction polish | ⭕ Optional |
| Notifications | OCR result alerts | ⭕ Optional |

Restart the app after granting permissions.

## ⌨️ Usage

1. Press the hotkey `⌃⌘O` (or click the menu-bar icon)
2. Drag to select the area you want to recognize
3. Release the mouse, wait a moment
4. The result is copied to the clipboard 🔔

**Menu-bar functions**:

- Start Screenshot OCR
- History… (search panel)
- Launch at Login toggle
- Settings (custom hotkey, toast/notification, selection border width)
- Quit

## ⚙️ Settings

Click **Settings** in the menu bar to customize:

- **Hotkey** — Click "Record", then press a new key combination
- **Toast** — Show Liquid Glass toast + sound on success
- **Notifications** — Show recognition result summary
- **Selection border width** — Adjust selection border thickness

## 🛠 Tech Stack

| Capability | Framework |
| --- | --- |
| UI / Menu bar | Cocoa (AppKit) |
| Liquid Glass toast | SwiftUI `glassEffect` |
| Screenshot | ScreenCaptureKit |
| Text recognition | Vision |
| Global hotkey | Carbon + CGEventTap |
| Launch at login | ServiceManagement |
| Notifications | UserNotifications |

### Triple-redundant Hotkey

To ensure the global hotkey triggers reliably in all scenarios, three layers are used:

1. **Carbon `RegisterEventHotKey`** — standard global hotkey
2. **CGEventTap** — system-level key event interception fallback
3. **Darwin Notification** — cross-process trigger fallback

### OCR Text Layout Algorithm

Based on the bounding box of each text block returned by Vision, clusters into lines by Y coordinate, then uses line spacing and indentation heuristics:

- Line gap > 1.8× line height → paragraph break (keep newline)
- Line start at left edge + previous line short → real line break
- Line indented → soft wrap (auto-join)

## 📂 Project Structure

```
src/
├── main.swift        # All source code
└── Info.plist        # Bundle & permission config
build.sh              # Build script
```

## 📄 License

MIT
