#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd -P)"
APP="$ROOT/dist/QuotaBar.app"
ICONSET="$ROOT/.build/QuotaBar.iconset"

for tool in swift sips iconutil codesign plutil; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "error: required tool '$tool' was not found" >&2
        exit 1
    fi
done

cd "$ROOT"
echo "Building QuotaBar (release)…"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

if [[ "$APP" != "$ROOT/dist/QuotaBar.app" || "$ICONSET" != "$ROOT/.build/QuotaBar.iconset" ]]; then
    echo "error: refusing to clean unexpected build paths" >&2
    exit 1
fi

rm -rf "$APP" "$ICONSET"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"
cp "$BIN_DIR/QuotaBar" "$APP/Contents/MacOS/QuotaBar"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# The real provider marks live in the SwiftPM resource bundle. Without this the
# app launches with no menu bar mark at all, so treat a missing bundle as fatal.
RESOURCE_BUNDLE="$BIN_DIR/QuotaBar_QuotaBar.bundle"
if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
    echo "error: provider mark resources were not built at $RESOURCE_BUNDLE" >&2
    exit 1
fi
cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/QuotaBar_QuotaBar.bundle"

swift "$ROOT/Scripts/MakeIcon.swift" "$ICONSET/icon_512x512@2x.png"
for entry in \
    "16 icon_16x16.png" \
    "32 icon_16x16@2x.png" \
    "32 icon_32x32.png" \
    "64 icon_32x32@2x.png" \
    "128 icon_128x128.png" \
    "256 icon_128x128@2x.png" \
    "256 icon_256x256.png" \
    "512 icon_256x256@2x.png" \
    "512 icon_512x512.png"; do
    read -r pixels filename <<< "$entry"
    sips -z "$pixels" "$pixels" "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/$filename" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

plutil -lint "$APP/Contents/Info.plist" >/dev/null
codesign --force --sign - "$APP" >/dev/null
codesign --verify --deep --strict "$APP"

echo "Built and signed: $APP"
