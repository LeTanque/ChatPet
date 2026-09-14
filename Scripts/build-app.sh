#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${CONFIGURATION:-release}"
swift build -c "$configuration" --disable-sandbox
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
app="${OUTPUT_DIR:-dist}/DesktopPet.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/DesktopPet" "$app/Contents/MacOS/DesktopPet"
cp Resources/Info.plist "$app/Contents/Info.plist"
# PetLibrary checks app resources first, then SwiftPM's development bundle.
resource_bundle="DesktopPet_DesktopPet.bundle"
if [ -d "$app/Contents/Resources/$resource_bundle" ]; then
    rm -rf "$app/Contents/Resources/$resource_bundle"
fi
cp -R "$binary_dir/$resource_bundle" "$app/Contents/Resources/"
# Finder may add metadata when a previous build is opened. It is not bundle content.
xattr -r -d com.apple.FinderInfo "$app" 2>/dev/null || true
xattr -r -d com.apple.ResourceFork "$app" 2>/dev/null || true
codesign --force --sign "${SIGNING_IDENTITY:--}" "$app"
codesign --verify --strict "$app"
plutil -lint "$app/Contents/Info.plist"
echo "Built $app"
