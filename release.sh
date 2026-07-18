#!/bin/bash
set -e

# 打包可分发的 .app 产物（.zip + .dmg），供 GitHub Release 上传。
# 用法：
#   ./release.sh              # 当前版本号
#   ./release.sh v1.1.0       # 指定版本

APP_NAME="截图OCR复制"
EN_NAME="ScreenshotOCR"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASE_DIR="$SCRIPT_DIR/release"
TAG="${1:-}"

echo "==> Building app..."
bash "$SCRIPT_DIR/build.sh" >/dev/null

echo "==> Preparing release artifacts..."
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

# 版本号：优先命令行参数，否则从 git tag 推断
if [ -z "$TAG" ]; then
    TAG="v$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SCRIPT_DIR/src/Info.plist")"
fi

# 1) .zip —— 最通用，双击解压即用
STAGING="$RELEASE_DIR/$APP_NAME.app"
cp -R "$SCRIPT_DIR/build/${APP_NAME}.app" "$STAGING"
# 重新 ad-hoc 签名（确保 zip 内签名有效）
codesign -s - --force --deep "$STAGING"
ZIP="$RELEASE_DIR/${EN_NAME}-${TAG}.zip"
ditto -c -k --keepParent "$STAGING" "$ZIP"
rm -rf "$STAGING"

echo "   ✓ $ZIP"

# 2) .dmg —— 更专业，双击挂载拖拽安装（可选，需要 create-dmg 或 hdiutil）
DMG="$RELEASE_DIR/${EN_NAME}-${TAG}.dmg"
if command -v create-dmg >/dev/null 2>&1; then
    echo "==> Creating DMG with create-dmg..."
    create-dmg \
        --volname "$APP_NAME" \
        --window-pos 200 120 \
        --window-size 520 320 \
        --icon-size 80 \
        --app-drop-link 360 160 \
        --no-internet-enable \
        "$DMG" "$SCRIPT_DIR/build/${APP_NAME}.app" >/dev/null 2>&1 || true
    [ -f "$DMG" ] && echo "   ✓ $DMG" || echo "   (DMG 跳过：create-dmg 失败)"
else
    # hdiutil 兜底（无美化，但能生成）
    echo "==> Creating DMG with hdiutil..."
    hdiutil create -volname "$APP_NAME" -srcfolder "$SCRIPT_DIR/build/${APP_NAME}.app" \
        -ov -format UDZO "$DMG" >/dev/null 2>&1 && echo "   ✓ $DMG" || echo "   (DMG 跳过：hdiutil 失败)"
fi

# 3) 校验和
CHECKSUM="$RELEASE_DIR/checksums-${TAG}.txt"
( cd "$RELEASE_DIR" && shasum -a 256 *.zip *.dmg 2>/dev/null ) > "$CHECKSUM" || true
[ -s "$CHECKSUM" ] && echo "   ✓ $CHECKSUM"

echo ""
echo "==> 🎉 Release artifacts ready in: $RELEASE_DIR/"
ls -lh "$RELEASE_DIR"/

echo ""
echo "==> 上传到 GitHub Release："
echo "    gh release create $TAG $ZIP $DMG --title \"$TAG\" --generate-notes"
echo "    # 或附加到已有 release："
echo "    gh release upload $TAG $ZIP $DMG --clobber"
