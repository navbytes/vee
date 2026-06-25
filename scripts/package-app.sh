#!/bin/bash
# Assemble Vee.app into ~/Applications from a SwiftPM build.
# Usage: scripts/package-app.sh [debug|release]   (default: debug, for fast iteration)
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="/tmp/vee-build/run"
APP="$HOME/Applications/Vee.app"

cd "$ROOT"
swift build -c "$CONFIG" --scratch-path "$SCRATCH" >/dev/null
BIN="$(find "$SCRATCH" -name vee -type f -path "*$CONFIG*" | head -1)"
[ -n "$BIN" ] || { echo "build produced no vee binary"; exit 1; }

# Stop any running instance so the relaunch picks up the new binary.
pkill -f 'Vee.app/Contents/MacOS/vee' 2>/dev/null || true
sleep 0.5

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/vee"
cp "$ROOT/packaging/Info.plist" "$APP/Contents/Info.plist"
# Bundle the built plugins (if present) so hot-reload/sample plugins resolve.
if [ -d "$ROOT/plugins/dist" ]; then
  mkdir -p "$APP/Contents/Resources/plugins"
  cp -R "$ROOT/plugins/dist" "$APP/Contents/Resources/plugins/" 2>/dev/null || true
fi
# Bundle the committed plugin fixtures the launcher loads at startup.
if ls "$ROOT"/plugins/fixtures/*.bundle.js >/dev/null 2>&1; then
  mkdir -p "$APP/Contents/Resources/vee-plugins"
  cp "$ROOT"/plugins/fixtures/*.bundle.js "$APP/Contents/Resources/vee-plugins/" 2>/dev/null || true
fi
# Optional icon
[ -f "$ROOT/packaging/Vee.icns" ] && cp "$ROOT/packaging/Vee.icns" "$APP/Contents/Resources/Vee.icns"

# Ad-hoc sign so the OS treats it as a stable app identity (no cert needed).
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "Packaged: $APP  (config=$CONFIG, binary=$BIN)"
