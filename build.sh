#!/bin/bash
set -euo pipefail

APP_NAME="OctoClip"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCES_DIR="$PROJECT_DIR/Sources"
BUILD_DIR="${OCTOCLIP_BUILD_DIR:-$PROJECT_DIR/dist}"
SDK_PATH="${OCTOCLIP_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"
SWIFTC="${OCTOCLIP_SWIFTC:-$(xcrun --find swiftc)}"
SDK_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :Version' "$SDK_PATH/SDKSettings.plist")"
SWIFT_FLAGS=(-target arm64-apple-macos12.0 -sdk "$SDK_PATH"
    -Xclang-linker -isysroot -Xclang-linker "$SDK_PATH")

mkdir -p "$BUILD_DIR"
STAGING="$(mktemp -d "$BUILD_DIR/.octoclip.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP_BUNDLE="$STAGING/$APP_NAME.app"
mkdir -p "$APP_BUNDLE/Contents/"{MacOS,Resources,Helpers}

echo "=== 编译 OctoClip · macOS SDK $SDK_VERSION ==="
if (( ${SDK_VERSION%%.*} >= 26 )); then
    echo "原生 Liquid Glass"
    set -- -D OCTOCLIP_LIQUID_GLASS
else
    echo "兼容材质构建"
    set --
fi

"$SWIFTC" -O "${SWIFT_FLAGS[@]}" "$@" \
    -framework AppKit -framework SwiftUI -framework Carbon \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
    "$SOURCES_DIR/main.swift" "$SOURCES_DIR/AppDelegate.swift" \
    "$SOURCES_DIR"/Models/*.swift "$SOURCES_DIR"/Services/*.swift "$SOURCES_DIR"/UI/*.swift

"$SWIFTC" -O "${SWIFT_FLAGS[@]}" \
    -o "$APP_BUNDLE/Contents/Helpers/octoclip" "$PROJECT_DIR/CLI/main.swift" \
    "$SOURCES_DIR"/Models/{ClipboardItem,ClipboardLibrary,ClipboardSettings,ClipDocument}.swift \
    "$SOURCES_DIR"/Services/{ClipboardPasteboard,ImageTextIndex}.swift

cp "$PROJECT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp -R "$PROJECT_DIR/Resources/Lucide" "$APP_BUNDLE/Contents/Resources/"

echo "=== 生成图标并签名 ==="
"$SWIFTC" "${SWIFT_FLAGS[@]}" \
    "$PROJECT_DIR/svg2icns.swift" -o "$STAGING/svg2icns"
"$STAGING/svg2icns" "$PROJECT_DIR/AppIcon.svg" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP_BUNDLE/Contents/Helpers/octoclip"
codesign --force --sign - "$APP_BUNDLE"

DESTINATION="$BUILD_DIR/$APP_NAME.app"
if [ -e "$DESTINATION" ]; then
    mv "$DESTINATION" "$STAGING/previous.app"
fi
if ! mv "$APP_BUNDLE" "$DESTINATION"; then
    if [ -e "$STAGING/previous.app" ]; then
        mv "$STAGING/previous.app" "$DESTINATION"
    fi
    exit 1
fi

echo "=== 构建完成 · $DESTINATION ==="
