#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-release}"
VERSION="${VERSION:-1.0.22}"
BUILD_NUMBER="${BUILD_NUMBER:-23}"

echo "==> Building IPWidget ($CONFIG)"
swift build -c "$CONFIG" --product IPWidgetApp
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

CONFIG="$CONFIG" VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" "$ROOT/scripts/build-widget.sh"

echo "==> Generating app icon"
ICONSET="$ROOT/build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ROOT/build"
swift "$ROOT/scripts/make-icon.swift" "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$ROOT/build/AppIcon.icns"

APP="$ROOT/build/IPWidget.app"
echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/PlugIns"

install -m 755 "$BIN_DIR/IPWidgetApp" "$APP/Contents/MacOS/IPWidget"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/build/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Sources/IPWidgetCore/Resources/"* "$APP/Contents/Resources/"
for RESOURCE_BUNDLE in "$BIN_DIR/"*.bundle; do
    [ -d "$RESOURCE_BUNDLE" ] || continue
    ditto "$RESOURCE_BUNDLE" "$APP/Contents/Resources/$(basename "$RESOURCE_BUNDLE")"
done
printf 'APPL????' > "$APP/Contents/PkgInfo"

ditto "$ROOT/build/IPWidgetWidget.appex" "$APP/Contents/PlugIns/IPWidgetWidget.appex"

plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"

echo "==> Signing (ad-hoc)"
codesign --force --sign - --entitlements "$ROOT/Resources/Widget.entitlements" --timestamp=none "$APP/Contents/PlugIns/IPWidgetWidget.appex"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"

echo "==> Done: $APP"
du -sh "$APP"
