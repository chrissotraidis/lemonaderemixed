#!/bin/bash
# Build Lemonade Remixed.app: the Swift app plus everything it runs inside:
# Wine, the Windows Python helper and the in-game agent.
set -euo pipefail
cd "$(dirname "$0")"
CONFIG=${CONFIG:-debug}
WINE_SRC=${WINE_SRC:-"/Applications/Wine Stable.app/Contents/Resources/wine"}
PY_ZIP=python-3.12.8-embed-amd64.zip
PY_SHA=8d3f33be9eb810f23c102f08475af2854e50484b8e4e06275e937be61ce3d2fb

swift build -c "$CONFIG" --product LemonadeRemixed
../runtime/agent/build.sh >/dev/null

APP=build/"Lemonade Remixed.app"
RES="$APP/Contents/Resources"
mkdir -p "$APP/Contents/MacOS" "$RES" build/cache
cp ".build/$CONFIG/LemonadeRemixed" "$APP/Contents/MacOS/LemonadeRemixed"

# Wine (LGPL; Gcenx's macOS build). APFS clones keep this fast and small.
if [ ! -x "$RES/wine/bin/wine" ]; then
  [ -x "$WINE_SRC/bin/wine" ] || { echo "Wine not found at $WINE_SRC (brew install --cask wine-stable)"; exit 1; }
  cp -Rc "$WINE_SRC" "$RES/wine"
fi

# The helper: embeddable Windows Python plus our scripts.
if [ ! -f build/cache/$PY_ZIP ]; then
  curl -sSL -o build/cache/$PY_ZIP https://www.python.org/ftp/python/3.12.8/$PY_ZIP
fi
echo "$PY_SHA  build/cache/$PY_ZIP" | shasum -a 256 -c - >/dev/null
rm -rf "$RES/helper"
mkdir -p "$RES/helper/python"
unzip -q build/cache/$PY_ZIP -d "$RES/helper/python"
cp ../runtime/helper/winctl.py ../runtime/helper/bridge.py "$RES/helper/"

rm -rf "$RES/fmodproxy"
mkdir -p "$RES/agent"
cp ../runtime/agent/build/fmod.dll "$RES/agent/fmod.dll"

# App icon: every size from the 1024 master, sharp at each.
ICONSET=build/cache/AppIcon.iconset
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/icon/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) Resources/icon/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$RES/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.chrissotraidis.lemonaderemixed</string>
<key>CFBundleName</key><string>Lemonade Remixed</string>
<key>CFBundleExecutable</key><string>LemonadeRemixed</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP/Contents/MacOS/LemonadeRemixed" >/dev/null 2>&1
echo "$APP"
