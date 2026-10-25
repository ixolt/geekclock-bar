#!/usr/bin/env bash
# Builds GeekClock Bar, wraps it into an ad-hoc signed .app and installs it
# to ~/Applications (replacing and quitting any running copy).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/GeekClockBar"

APP=build/GeekClockBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/GeekClockBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --deep "$APP"

pkill -x GeekClockBar || true
mkdir -p ~/Applications
rm -rf ~/Applications/GeekClockBar.app
cp -R "$APP" ~/Applications/
echo "Installed ~/Applications/GeekClockBar.app"
