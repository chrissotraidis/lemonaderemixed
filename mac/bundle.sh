#!/bin/bash
# Build Lemonade Remixed.app: the Swift app plus everything it runs inside:
# Wine, the Windows Python helper and the in-game agent.
#
#   mac/bundle.sh                    build mac/build/Lemonade Remixed.app
#   mac/bundle.sh --output FILE.zip  also pack the app into FILE.zip (PadMint uses this)
#
# Needs only Xcode's command-line tools. Wine, the embeddable Python and the
# compiler for the in-game agent are pinned downloads, checked by SHA-256 and
# kept in mac/build/cache. Nothing from the game is included.
set -euo pipefail
cd "$(dirname "$0")"
OUTPUT=
while [ $# -gt 0 ]; do
  case $1 in
    --output) OUTPUT=$2; shift 2;;
    *) echo "usage: mac/bundle.sh [--output FILE.zip]"; exit 2;;
  esac
done
CONFIG=${CONFIG:-release}
CACHE=build/cache
mkdir -p "$CACHE"

xcrun --find swift >/dev/null 2>&1 || { echo "Xcode's command-line tools are needed: run xcode-select --install"; exit 1; }
if [ "$(uname -m)" = arm64 ] && ! /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then
  echo "Rosetta 2 is needed (Wine runs the game through it): run softwareupdate --install-rosetta --agree-to-license"
  exit 1
fi

# Wine 9.0 (LGPL), Gcenx's macOS build, the version the game is tested on (Wine 11 breaks
# its copy protection and frame capture). Gcenx no longer hosts 9.0, so Lemonade Remixed
# keeps an unchanged copy (minus the unused Mono and Gecko) as a release asset.
# Wine source: https://dl.winehq.org/wine/source/9.0/
WINE_VERSION=9.0_3
WINE_TAR=wine-$WINE_VERSION-osx64-lemonaderemixed.tar.xz
WINE_URL=https://github.com/chrissotraidis/lemonaderemixed/releases/download/runtime-wine-$WINE_VERSION/$WINE_TAR
WINE_SHA=b3710d29093b913426f6daa5ad2bf2f54c099455846b7925f6c862377ed82c91
# llvm-mingw, for the small 32-bit Windows agent the game loads.
MINGW_VERSION=20261104
MINGW_DIR=llvm-mingw-$MINGW_VERSION-ucrt-macos-universal
MINGW_URL=https://github.com/mstorsjo/llvm-mingw/releases/download/$MINGW_VERSION/$MINGW_DIR.tar.xz
MINGW_SHA=66cbd5178c4a71b0d473e68ede172f8eb7d15d023e67f39201d0a69e21f6bf3c
# The helper's Windows Python.
PY_ZIP=python-3.12.8-embed-amd64.zip
PY_URL=https://www.python.org/ftp/python/3.12.8/$PY_ZIP
PY_SHA=8d3f33be9eb810f23c102f08475af2854e50484b8e4e06275e937be61ce3d2fb

fetch() {  # fetch URL FILE SHA256: download once into the cache, always verify
  if [ ! -f "$CACHE/$2" ] || ! echo "$3  $CACHE/$2" | shasum -a 256 -c - >/dev/null 2>&1; then
    echo "Downloading $2"
    curl -fsSL --retry 3 -o "$CACHE/$2.part" "$1"
    mv "$CACHE/$2.part" "$CACHE/$2"
  fi
  echo "$3  $CACHE/$2" | shasum -a 256 -c - >/dev/null || { echo "$2: checksum mismatch"; exit 1; }
}

fetch "$MINGW_URL" "$MINGW_DIR.tar.xz" "$MINGW_SHA"
if [ ! -x "$CACHE/$MINGW_DIR/bin/clang" ]; then
  tar -xJf "$CACHE/$MINGW_DIR.tar.xz" -C "$CACHE"
fi

swift build -c "$CONFIG" --product LemonadeRemixed
LLVM="$PWD/$CACHE/$MINGW_DIR/bin" ../runtime/agent/build.sh >/dev/null

APP=build/"Lemonade Remixed.app"
RES="$APP/Contents/Resources"
mkdir -p "$APP/Contents/MacOS" "$RES"
cp ".build/$CONFIG/LemonadeRemixed" "$APP/Contents/MacOS/LemonadeRemixed"

# Wine, copied in once per version. APFS clones keep this fast and small.
if [ "$(cat "$RES/wine/.remix-version" 2>/dev/null)" != "$WINE_VERSION" ]; then
  fetch "$WINE_URL" "$WINE_TAR" "$WINE_SHA"
  if [ ! -x "$CACHE/wine-$WINE_VERSION/wine/bin/wine" ]; then
    mkdir -p "$CACHE/wine-$WINE_VERSION"
    tar -xJf "$CACHE/$WINE_TAR" -C "$CACHE/wine-$WINE_VERSION"
  fi
  if [ -d "$RES/wine" ]; then mv "$RES/wine" "$CACHE/old-wine-$$"; rm -rf "$CACHE/old-wine-$$"; fi
  cp -Rc "$CACHE/wine-$WINE_VERSION/wine" "$RES/wine"
  echo "$WINE_VERSION" > "$RES/wine/.remix-version"
fi

# The helper: embeddable Windows Python plus our scripts.
fetch "$PY_URL" "$PY_ZIP" "$PY_SHA"
rm -rf "$RES/helper"
mkdir -p "$RES/helper/python"
unzip -q "$CACHE/$PY_ZIP" -d "$RES/helper/python"
cp ../runtime/helper/*.py "$RES/helper/"

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

mkdir -p "$RES/fonts"
cp Resources/fonts/VT323-Regular.ttf Resources/fonts/VT323-OFL.txt "$RES/fonts/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.chrissotraidis.lemonaderemixed</string>
<key>CFBundleName</key><string>Lemonade Remixed</string>
<key>CFBundleExecutable</key><string>LemonadeRemixed</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP/Contents/MacOS/LemonadeRemixed" >/dev/null 2>&1
echo "$APP"

if [ -n "$OUTPUT" ]; then
  mkdir -p "$(dirname "$OUTPUT")"
  ditto -c -k --keepParent "$APP" "$OUTPUT"
  echo "$OUTPUT"
fi
