#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-1.0.22}"
BUILD_NUMBER="${BUILD_NUMBER:-23}"
# Keep the verified WidgetKit SDK; callers can explicitly select another SDK.
SDK="${SDK:-$(xcrun --sdk macosx26.5 --show-sdk-path)}"
# Darwin clang also needs SDKROOT when Swift invokes the linker.
export SDKROOT="$SDK"

OUT="$ROOT/build/IPWidgetWidget.appex"
echo "==> Building WidgetKit extension"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources/ru.lproj" "$OUT/Contents/Resources/en.lproj"

swiftc \
    -parse-as-library \
    -application-extension \
    -swift-version 5 \
    -target arm64-apple-macos26.0 \
    -sdk "$SDK" \
    -module-name IPWidgetWidget \
    -O \
    "$ROOT/Sources/IPWidgetCore/IPv4Address.swift" \
    "$ROOT/Sources/IPWidgetCore/Country.swift" \
    "$ROOT/Sources/IPWidgetCore/GeoInfo.swift" \
    "$ROOT/Sources/IPWidgetCore/TwoIPClient.swift" \
    "$ROOT/Sources/IPWidgetCore/MultiIPClient.swift" \
    "$ROOT/Sources/IPWidgetCore/LocalGeoIP.swift" \
    "$ROOT/Sources/IPWidgetCore/WidgetStatus.swift" \
    "$ROOT/Sources/IPWidgetCore/WidgetSnapshotLoader.swift" \
    "$ROOT/Sources/IPWidgetCore/IPWidgetConstants.swift" \
    "$ROOT/Sources/IPWidgetUI/L10n.swift" \
    "$ROOT/Sources/IPWidgetUI/WidgetCard.swift" \
    "$ROOT/Sources/IPWidgetUI/FlagImage.swift" \
    "$ROOT/Sources/IPWidgetWidget/IPWidgetWidget.swift" \
    -framework WidgetKit \
    -framework SwiftUI \
    -framework AppKit \
    -framework CoreImage \
    -Xlinker -e -Xlinker _NSExtensionMain \
    -o "$OUT/Contents/MacOS/IPWidgetWidget"

cp "$ROOT/Resources/WidgetInfo.plist" "$OUT/Contents/Info.plist"
cp "$ROOT/Resources/ru.lproj/Localizable.strings" "$OUT/Contents/Resources/ru.lproj/Localizable.strings"
cp "$ROOT/Resources/en.lproj/Localizable.strings" "$OUT/Contents/Resources/en.lproj/Localizable.strings"
cp "$ROOT/Resources/Flags/"*.png "$OUT/Contents/Resources/"

cp "$ROOT/Sources/IPWidgetCore/Resources/"* "$OUT/Contents/Resources/"

printf 'XPC!????' > "$OUT/Contents/PkgInfo"

plutil -replace CFBundleShortVersionString -string "$VERSION" "$OUT/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$OUT/Contents/Info.plist"
plutil -lint "$OUT/Contents/Info.plist"

codesign --force --sign - --entitlements "$ROOT/Resources/Widget.entitlements" --timestamp=none "$OUT"
codesign --verify --strict "$OUT"

echo "==> Done: $OUT"
