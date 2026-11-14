#!/bin/bash
# Builds "K24 Screenshot Maker.app" into ./build
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/K24 Screenshot Maker.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/FramePlayer "$APP/Contents/MacOS/FramePlayer"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"

# ./build_app.sh --install  → copy to /Applications (quits a running copy first)
if [ "${1:-}" = "--install" ]; then
    pkill -x FramePlayer 2>/dev/null && sleep 1 || true
    DEST="/Applications/$(basename "$APP")"
    rm -rf "$DEST"
    mv "$APP" "$DEST"   # move, so only one copy shows up in Spotlight/Launchpad
    touch "$DEST"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" || true
    echo "Installed $DEST"
else
    echo "Run:  open \"$APP\"   (install with: ./build_app.sh --install)"
fi
