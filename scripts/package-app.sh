#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build"
RELEASE_DIR="$BUILD_DIR/arm64-apple-macosx/release"
APP_NAME="VoxTV"
APP_BUNDLE="$APP_NAME.app"
DMG_NAME="VoxTV-Installer"
STAGING="$BUILD_DIR/staging"

echo "=== 1. Building release binary ==="
cd "$PROJECT_DIR"
swift build -c release

echo "=== 2. Assembling .app bundle ==="
rm -rf "$STAGING" "$BUILD_DIR/$DMG_NAME.dmg"
mkdir -p "$STAGING/$APP_BUNDLE/Contents/MacOS"
mkdir -p "$STAGING/$APP_BUNDLE/Contents/Resources"

# Binary
cp "$RELEASE_DIR/Voxtv" "$STAGING/$APP_BUNDLE/Contents/MacOS/"

# Info.plist
cp "$PROJECT_DIR/Sources/Voxtv/Info.plist" "$STAGING/$APP_BUNDLE/Contents/"

# Inject version from git tag into Info.plist (for CI builds)
if [ -n "${GITHUB_REF_NAME:-}" ] && [[ "$GITHUB_REF_NAME" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    VERSION="${GITHUB_REF_NAME#v}"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$STAGING/$APP_BUNDLE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion 1" "$STAGING/$APP_BUNDLE/Contents/Info.plist"
    echo "  Version set to $VERSION from git tag"
fi

# Resource bundle (SPM output)
cp -R "$RELEASE_DIR/Voxtv_Voxtv.bundle" "$STAGING/$APP_BUNDLE/Contents/Resources/"

# Generate AppIcon.icns from the asset catalog PNGs
APPSET="$RELEASE_DIR/Voxtv_Voxtv.bundle/Assets.xcassets/AppIcon.appiconset"
if [ -d "$APPSET" ]; then
    ICONSET_DIR="$BUILD_DIR/app.iconset"
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"
    cp "$APPSET"/icon_*.png "$ICONSET_DIR/"
    iconutil -c icns "$ICONSET_DIR" -o "$STAGING/$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET_DIR"
    echo "  AppIcon.icns generated"
fi

# KWS + VAD models
mkdir -p "$STAGING/$APP_BUNDLE/Contents/Resources/Resources"
cp -R "$PROJECT_DIR/Resources/kws" "$STAGING/$APP_BUNDLE/Contents/Resources/Resources/"
cp -R "$PROJECT_DIR/Resources/vad" "$STAGING/$APP_BUNDLE/Contents/Resources/Resources/"

# onnxruntime dylib (put next to binary — @loader_path rpath already set)
cp "$PROJECT_DIR/Libraries/COnnxRuntime/libonnxruntime.1.24.4.dylib" "$STAGING/$APP_BUNDLE/Contents/MacOS/"

# Fix dylib install name in the binary: change absolute path to @loader_path
install_name_tool -change \
  "$PROJECT_DIR/Libraries/COnnxRuntime/libonnxruntime.1.24.4.dylib" \
  "@loader_path/libonnxruntime.1.24.4.dylib" \
  "$STAGING/$APP_BUNDLE/Contents/MacOS/Voxtv"

# Strip the binary (reduce size)
strip "$STAGING/$APP_BUNDLE/Contents/MacOS/Voxtv"

# Ad-hoc sign the binary (required for SMAppService to work)
codesign --force --sign - "$STAGING/$APP_BUNDLE/Contents/MacOS/Voxtv"

echo "=== 3. Creating DMG ==="
DMG_TEMP="$BUILD_DIR/tmp.dmg"
DMG_FINAL="$BUILD_DIR/$DMG_NAME.dmg"
rm -f "$DMG_TEMP" "$DMG_FINAL"

# Create empty read-write DMG
hdiutil create -size 100m -fs HFS+ -volname "$APP_NAME" -ov "$DMG_TEMP"

# Mount and copy .app + Applications symlink
hdiutil attach "$DMG_TEMP" -readwrite -noverify -noautoopen -mountpoint /tmp/vox_dmg_mount

cp -R "$STAGING/$APP_BUNDLE" "/tmp/vox_dmg_mount/"
ln -s /Applications "/tmp/vox_dmg_mount/Applications"

# Unmount
hdiutil detach /tmp/vox_dmg_mount

# Convert to compressed read-only DMG
hdiutil convert "$DMG_TEMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_FINAL"
rm -f "$DMG_TEMP"

echo "=== Done ==="
echo "DMG: $DMG_FINAL"
echo "App bundle: $STAGING/$APP_BUNDLE"
