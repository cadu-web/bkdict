#!/bin/bash
# Builds BKDict.app into ./dist. Pass --install to copy it to /Applications,
# or --release to build for Intel + Apple Silicon and package it as .zip and .dmg.
set -euo pipefail
cd "$(dirname "$0")"

APP=dist/BKDict.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ "${1:-}" == "--release" ]]; then
    # Universal: each architecture on its own and joined with lipo. `swift build --arch arm64 --arch x86_64`
    # does it in one go, but needs the full Xcode (xcbuild); this works with the Command Line Tools too.
    SLICES=()
    for arch in arm64 x86_64; do
        swift build -c release --triple "$arch-apple-macosx14.0"
        SLICES+=("$(swift build -c release --triple "$arch-apple-macosx14.0" --show-bin-path)/Bkdict")
    done
    lipo -create "${SLICES[@]}" -output "$APP/Contents/MacOS/Bkdict"
else
    swift build -c release
    cp "$(swift build -c release --show-bin-path)/Bkdict" "$APP/Contents/MacOS/Bkdict"
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/ProviderIcons "$APP/Contents/Resources/ProviderIcons"
# Fontes da marca (IBM Plex, Zilla Slab), registradas pelo ATSApplicationFontsPath do Info.plist.
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"
cp Resources/MenuBarIcon.png Resources/MenuBarIcon@2x.png "$APP/Contents/Resources/"
# Sparkle (atualização automática), achado pelo rpath @executable_path/../Frameworks do Package.swift.
mkdir -p "$APP/Contents/Frameworks"
# The framework is already universal, so either build has the same one.
cp -R "$(swift build -c release --show-bin-path)/Sparkle.framework" "$APP/Contents/Frameworks/"

ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) Resources/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
# Nested code is signed first, inside out, then the app itself.
codesign --force --deep --sign - "$APP/Contents/Frameworks/Sparkle.framework"
# Pin the designated requirement to the bundle id so macOS keeps the
# Accessibility/Microphone grants across rebuilds (ad-hoc defaults to the cdhash).
codesign --force --sign - -r='designated => identifier "co.bkdg.bkdict"' "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/BKDict.app
    cp -R "$APP" /Applications/
    echo "Installed /Applications/BKDict.app"
fi

if [[ "${1:-}" == "--release" ]]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
    ZIP="dist/BKDict-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Packaged $ZIP"

    # Drag-to-Applications disk image. create-dmg drives Finder via AppleScript,
    # so it needs a logged-in session (not a headless CI runner).
    command -v create-dmg >/dev/null || { echo "create-dmg not found: brew install create-dmg" >&2; exit 1; }
    DMG="dist/BKDict-$VERSION.dmg"
    STAGE="$(mktemp -d)"
    cp -R "$APP" "$STAGE/"
    rm -f "$DMG"
    create-dmg \
        --volname "BKDict" \
        --volicon "$APP/Contents/Resources/AppIcon.icns" \
        --background Resources/dmg-background.tiff \
        --window-size 660 400 \
        --icon-size 112 \
        --icon "BKDict.app" 180 190 \
        --hide-extension "BKDict.app" \
        --app-drop-link 480 190 \
        "$DMG" "$STAGE" >/dev/null
    rm -rf "$STAGE"
    echo "Packaged $DMG"
fi
