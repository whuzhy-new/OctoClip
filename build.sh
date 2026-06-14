#!/bin/bash
set -e

APP_NAME="OctoClip"
BUILD_DIR="$(cd "$(dirname "$0")" && pwd)/build"
SOURCES_DIR="$(cd "$(dirname "$0")" && pwd)/Sources"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "=== 清理旧构建 ==="
rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

echo "=== 编译 Swift 源文件 ==="
swiftc \
    -O \
    -target arm64-apple-macos12.0 \
    -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk \
    -framework AppKit \
    -framework SwiftUI \
    -framework Carbon \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
    "$SOURCES_DIR/main.swift" \
    "$SOURCES_DIR/AppDelegate.swift" \
    "$SOURCES_DIR/Models/ClipboardItem.swift" \
    "$SOURCES_DIR/Models/ClipboardSettings.swift" \
    "$SOURCES_DIR/Models/ClipboardStore.swift" \
    "$SOURCES_DIR/Services/ClipboardMonitor.swift" \
    "$SOURCES_DIR/Services/HotkeyManager.swift" \
    "$SOURCES_DIR/Services/PasteService.swift" \
    "$SOURCES_DIR/UI/PopupView.swift" \
    "$SOURCES_DIR/UI/PopupWindowController.swift" \
    "$SOURCES_DIR/UI/SettingsView.swift"

echo "=== 复制 Info.plist ==="
cp "$(dirname "$0")/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

echo "=== 生成并复制图标 ==="
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
swift -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk -target arm64-apple-macos12.0 \
    "$SCRIPT_DIR/svg2icns.swift" "$SCRIPT_DIR/AppIcon.svg" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

echo "=== 签名 ==="
codesign --force --sign - "$APP_BUNDLE"
xattr -cr "$APP_BUNDLE"

echo "=== 构建完成: $APP_BUNDLE ==="
echo ""
echo "运行方式: open $APP_BUNDLE"
echo "或双击 Finder 中的 $APP_NAME.app"
