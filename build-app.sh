#!/bin/bash
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/SwishLite.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/SwishLite "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/" 2>/dev/null || true
# ad-hoc sign so macOS tracks the bundle's Accessibility grant
codesign --force --deep --sign - "$APP" 2>/dev/null || true
echo "Built: $APP"
echo "Run:   open $APP"
