#!/bin/sh
# Builds TaskETA.app from source with swiftc (Xcode or the Command Line Tools, no Xcode project).
#
#   ./build.sh                  build widget/build/TaskETA.app
#   ./build.sh --run            build, then (re)start that copy
#
# install.py copies the app to ~/Applications and can turn on open at login.
# The app is signed ad hoc on this Mac, has no network code and no sandbox entitlements.
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
codesign --force --sign - "$APP.tmp" >/dev/null 2>&1
rm -rf "$APP"
mv "$APP.tmp" "$APP"
echo "Built: $(pwd)/$APP"

if [ "$run" = 1 ]; then
  pkill -x TaskETA 2>/dev/null && sleep 1 || true
  open "$APP"
fi
