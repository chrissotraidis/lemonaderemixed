#!/bin/bash
# Build Lemonade Remixed.app from the Swift package.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c ${CONFIG:-debug}
APP=build/"Lemonade Remixed.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/${CONFIG:-debug}/LemonadeRemixed "$APP/Contents/MacOS/LemonadeRemixed"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.chrissotraidis.lemonaderemixed</string>
<key>CFBundleName</key><string>Lemonade Remixed</string>
<key>CFBundleExecutable</key><string>LemonadeRemixed</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null
echo "$APP"
