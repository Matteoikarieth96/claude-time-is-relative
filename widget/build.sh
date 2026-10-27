#!/bin/sh
# Builds TaskETA.app from source with swiftc (Xcode or the Command Line Tools, no Xcode project).
#
#   ./build.sh                  build widget/build/TaskETA.app
#   ./build.sh --run            build, then (re)start that copy
#
# install.py copies the app to ~/Applications and can turn on open at login.
# The app is signed ad hoc on this Mac and has no sandbox entitlements. Its only network code is
# the iPhone widget's server (PhoneServer.swift): off by default, local network only, plain HTTP with a code.
set -eu
cd "$(dirname "$0")"

OUT="build"
APP="$OUT/TaskETA.app"
run=0
for arg in "$@"; do
  case "$arg" in
    --run) run=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

if ! xcrun --sdk macosx --show-sdk-path >/dev/null 2>&1; then
  echo "No macOS SDK found. Install the Command Line Tools with: xcode-select --install" >&2
  exit 1
fi
SDK="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$OUT"
rm -rf "$APP.tmp"
mkdir -p "$APP.tmp/Contents/MacOS" "$APP.tmp/Contents/Resources"
xcrun --sdk macosx swiftc -O -sdk "$SDK" -target "$(uname -m)-apple-macos14.0" \
  -o "$APP.tmp/Contents/MacOS/TaskETA" Sources/*.swift
cp Info.plist "$APP.tmp/Contents/Info.plist"
cp iphone/TaskETA.js "$APP.tmp/Contents/Resources/TaskETA.js" # the iPhone widget, filled in by the settings
cp -R campo "$APP.tmp/Contents/Resources/campo" # the game's map for the dashboard, with its Barlow fonts (OFL)
cp -R miniera "$APP.tmp/Contents/Resources/miniera" # the mine's fonts, Pixelify Sans and VT323 for the digits (OFL); Minecraft's icons stay in ~/.claude/task-eta/minerali
codesign --force --sign - "$APP.tmp" >/dev/null 2>&1
rm -rf "$APP"
mv "$APP.tmp" "$APP"
echo "Built: $(pwd)/$APP"

if [ "$run" = 1 ]; then
  # Quit only a TaskETA started from this build folder, found by the exact path of its executable.
  exe="$(pwd)/$APP/Contents/MacOS/TaskETA"
  ps -axo pid=,comm= | while read -r pid comm; do
    [ "$comm" = "$exe" ] && kill "$pid" 2>/dev/null
  done
  sleep 1
  open "$APP"
fi
