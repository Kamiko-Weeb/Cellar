#!/bin/bash
# Builds Cellar.app into build/. Pass --install to copy it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

# Map this folder to "." so no absolute build paths (your username) end up in the binary.
swift build -c release -Xswiftc -file-prefix-map -Xswiftc "$PWD=." -Xswiftc -debug-prefix-map -Xswiftc "$PWD=."

if [ ! -f build/AppIcon.icns ]; then
    swift scripts/make-icon.swift build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi

APP=build/Cellar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Cellar "$APP/Contents/MacOS/Cellar"
# Drop the debug map, which lists each object file's absolute build path.
strip -S -x "$APP/Contents/MacOS/Cellar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

if [ "${1:-}" = "--install" ]; then
    rm -rf "/Applications/Cellar.app"
    cp -R "$APP" "/Applications/Cellar.app"
    echo "Installed to /Applications/Cellar.app"
fi
