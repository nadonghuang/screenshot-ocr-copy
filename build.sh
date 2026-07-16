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
    -o "$SCRIPT_DIR/build/ScreenshotOCR" \
    -target arm64-apple-macosx14.0

echo "==> Assembling .app bundle..."
APP_DIR="$SCRIPT_DIR/build/${APP_NAME}.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$SCRIPT_DIR/build/ScreenshotOCR" "$APP_DIR/Contents/MacOS/ScreenshotOCR"
cp "$SCRIPT_DIR/src/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$SCRIPT_DIR/build/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
echo "APPL????" > "$APP_DIR/Contents/PkgInfo"
chmod +x "$APP_DIR/Contents/MacOS/ScreenshotOCR"

echo "==> Code signing..."
codesign -s - --force --deep "$APP_DIR"

echo "==> Done! App at: $APP_DIR"
echo "==> To install: cp -R \"$APP_DIR\" /Applications/"
