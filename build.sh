#!/bin/bash
set -e

APP_NAME="截图OCR复制"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Compiling Swift source..."
mkdir -p "$SCRIPT_DIR/build"
swiftc "$SCRIPT_DIR/src/main.swift" \
    -framework Cocoa \
    -framework Vision \
    -framework Carbon \
    -framework UserNotifications \
    -framework ServiceManagement \
    -framework ScreenCaptureKit \
    -framework ApplicationServices \
    -o "$SCRIPT_DIR/build/ScreenshotOCR" \
    -target arm64-apple-macosx26.0

echo "==> Assembling .app bundle..."
APP_DIR="$SCRIPT_DIR/build/${APP_NAME}.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Use cat redirect instead of cp (more reliable on macOS)
   cat "$SCRIPT_DIR/build/ScreenshotOCR" > "$APP_DIR/Contents/MacOS/ScreenshotOCR"
   cp "$SCRIPT_DIR/src/Info.plist" "$APP_DIR/Contents/Info.plist"
   # 从 assets/icon_1024.png 重新生成 icns，确保图标源与产物一致
   bash "$SCRIPT_DIR/tools/make_iconset.sh"
   cp "$SCRIPT_DIR/build/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
   echo "APPL????" > "$APP_DIR/Contents/PkgInfo"
chmod +x "$APP_DIR/Contents/MacOS/ScreenshotOCR"

echo "==> Code signing..."
codesign -s - --force --deep "$APP_DIR"

echo "==> Installing to /Applications..."
killall ScreenshotOCR 2>/dev/null || true
sleep 0.5
# Use cat for binary, ditto for bundle structure
cat "$SCRIPT_DIR/build/ScreenshotOCR" > "/Applications/${APP_NAME}.app/Contents/MacOS/ScreenshotOCR"
cp "$APP_DIR/Contents/Info.plist" "/Applications/${APP_NAME}.app/Contents/Info.plist"
cp "$APP_DIR/Contents/Resources/AppIcon.icns" "/Applications/${APP_NAME}.app/Contents/Resources/AppIcon.icns"
chmod +x "/Applications/${APP_NAME}.app/Contents/MacOS/ScreenshotOCR"
codesign -s - --force --deep "/Applications/${APP_NAME}.app"

echo "==> Done! App installed at: /Applications/${APP_NAME}.app"
echo "==> Starting..."
open "/Applications/${APP_NAME}.app"
