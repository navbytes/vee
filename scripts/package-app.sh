#!/bin/bash
# Assemble Vee.app into ~/Applications from a SwiftPM build (local, ad-hoc signed).
# Usage: scripts/package-app.sh [debug|release]   (default: debug, for fast iteration)
#
# This is the LOCAL packager. Notarized distribution is handled by
# .github/workflows/release.yml (needs Apple Developer secrets). Ad-hoc +
# Hardened Runtime here means it runs locally with the JIT entitlements
# JavaScriptCore needs; it is not Gatekeeper-distributable without notarization.
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="/tmp/vee-build/run"
APP="$HOME/Applications/Vee.app"

cd "$ROOT"
swift build -c "$CONFIG" --scratch-path "$SCRATCH" >/dev/null
BIN_VEE="$(find "$SCRATCH" -name vee -type f -path "*$CONFIG*" -not -name '*.*' | head -1)"
BIN_HOST="$(find "$SCRATCH" -name vee-plugin-host -type f -path "*$CONFIG*" | head -1)"
[ -n "$BIN_VEE" ] || { echo "build produced no vee binary"; exit 1; }

# Stop any running instance so the relaunch picks up the new binary.
pkill -f 'Vee.app/Contents/MacOS/vee' 2>/dev/null || true
sleep 0.5

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_VEE" "$APP/Contents/MacOS/vee"
cp "$ROOT/packaging/Info.plist" "$APP/Contents/Info.plist"
# Bundle the out-of-process child host so the engine can spawn it.
[ -n "$BIN_HOST" ] && cp "$BIN_HOST" "$APP/Contents/MacOS/vee-plugin-host"

# Bundle each plugin as Resources/vee-plugins/<id>/{vee.json,bundle.js} (the layout
# the launcher discovers). <id> is read from the sample manifest; the IIFE comes
# from the committed fixture.
for manifest in "$ROOT"/plugins/samples/*/vee.json; do
  [ -f "$manifest" ] || continue
  id="$(/usr/bin/python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["id"])' "$manifest" 2>/dev/null)" || continue
  bundle="$ROOT/plugins/fixtures/$id.bundle.js"
  if [ -n "$id" ] && [ -f "$bundle" ]; then
    mkdir -p "$APP/Contents/Resources/vee-plugins/$id"
    cp "$manifest" "$APP/Contents/Resources/vee-plugins/$id/vee.json"
    cp "$bundle"   "$APP/Contents/Resources/vee-plugins/$id/bundle.js"
  fi
done

# Optional icon
[ -f "$ROOT/packaging/Vee.icns" ] && cp "$ROOT/packaging/Vee.icns" "$APP/Contents/Resources/Vee.icns"

# Ad-hoc sign with Hardened Runtime + the JIT entitlements JSC needs. Sign the
# nested child first, then the app bundle.
ENT="$ROOT/packaging/Vee.entitlements"
if [ -f "$APP/Contents/MacOS/vee-plugin-host" ]; then
  codesign --force --options runtime --entitlements "$ENT" --sign - \
    "$APP/Contents/MacOS/vee-plugin-host" >/dev/null 2>&1 || true
fi
codesign --force --options runtime --entitlements "$ENT" --sign - "$APP" >/dev/null 2>&1 || true

echo "Packaged: $APP  (config=$CONFIG)"
echo "  vee:           $BIN_VEE"
echo "  vee-plugin-host: ${BIN_HOST:-<none>}"
echo "  plugins:       $(ls "$APP/Contents/Resources/vee-plugins" 2>/dev/null | tr '\n' ' ')"
