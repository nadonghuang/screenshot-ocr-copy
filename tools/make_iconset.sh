#!/bin/bash
# 从 assets/icon_1024.png 生成完整 iconset + .icns
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$SCRIPT_DIR/assets/icon_1024.png"
ICONSET="$SCRIPT_DIR/build/icon.iconset"
OUT="$SCRIPT_DIR/build/AppIcon.icns"

[ -f "$SRC" ] || { echo "❌ 缺少 $SRC"; exit 1; }

mkdir -p "$SCRIPT_DIR/build"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
sips -z 16 16     "$SRC" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32     "$SRC" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32     "$SRC" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64     "$SRC" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128   "$SRC" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256   "$SRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$SRC" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512   "$SRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$SRC" --out "$ICONSET/icon_512x512.png" >/dev/null
cp "$SRC" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$OUT"
echo "✓ icns 生成: $(ls -lh "$OUT" | awk '{print $5}')"
