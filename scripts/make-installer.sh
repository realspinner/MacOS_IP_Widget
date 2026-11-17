#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-1.0.22}"
BUILD_NUMBER="${BUILD_NUMBER:-23}"
CONFIG="${CONFIG:-release}"
export CONFIG VERSION BUILD_NUMBER

"$ROOT/scripts/build-app.sh"

APP="$ROOT/build/IPWidget.app"
COMPONENT="$ROOT/build/IPWidget-component.pkg"
DISTRIBUTION="$ROOT/build/Distribution.xml"
OUTPUT="$ROOT/dist/IPWidget-$VERSION.pkg"

rm -f "$COMPONENT" "$OUTPUT"
mkdir -p "$ROOT/dist"

echo "==> Building component package"
pkgbuild \
    --component "$APP" \
    --install-location "/Applications" \
    --identifier "dev.spinner.ipwidget.pkg" \
    --version "$VERSION" \
    --ownership recommended \
    "$COMPONENT"

cat > "$DISTRIBUTION" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>IP Widget</title>
    <organization>dev.spinner</organization>
    <domains enable_localSystem="true" enable_currentUserHome="false" enable_anywhere="false"/>
    <options customize="never" require-scripts="false" rootVolumeOnly="true" hostArchitectures="arm64"/>
    <allowed-os-versions>
        <os-version min="26.0"/>
    </allowed-os-versions>
    <readme file="README.html"/>
    <choices-outline>
        <line choice="default">
            <line choice="dev.spinner.ipwidget.pkg"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="dev.spinner.ipwidget.pkg" visible="false">
        <pkg-ref id="dev.spinner.ipwidget.pkg"/>
    </choice>
    <pkg-ref id="dev.spinner.ipwidget.pkg" version="$VERSION" onConclusion="none">IPWidget-component.pkg</pkg-ref>
</installer-gui-script>
XML

echo "==> Building product archive"
productbuild \
    --distribution "$DISTRIBUTION" \
    --package-path "$ROOT/build" \
    --resources "$ROOT/scripts/installer-resources" \
    --identifier "dev.spinner.ipwidget.installer" \
    --version "$VERSION" \
    "$OUTPUT"

echo "==> Verifying package"
pkgutil --payload-files "$OUTPUT" | head -20
echo
echo "==> Done: $OUTPUT"
du -sh "$OUTPUT"
