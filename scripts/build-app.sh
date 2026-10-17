#!/bin/sh
# Builds build/SnailReborn.app (menu bar app, ad-hoc signed) and build/snailctl.
set -eu
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG" --product SnailApp
swift build -c "$CONFIG" --product snailctl
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

APP=build/SnailReborn.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/SnailApp" "$APP/Contents/MacOS/SnailReborn"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp "$BIN/snailctl" build/snailctl

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>SnailReborn</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>com.markhinojosa.SnailReborn</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Snail</string>
    <key>CFBundleDisplayName</key><string>Snail</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>2.0</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>Snail asks for your administrator password to change the Wi‑Fi speed limit.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null
echo "Built $APP and build/snailctl"
