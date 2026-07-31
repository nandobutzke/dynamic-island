#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
BIN="$BIN_DIR/DynamicIsland"
APP="$ROOT/build/DynamicIsland.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/DynamicIsland"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/DynamicIsland"

# SPM resource bundle (logos, etc.)
if [[ -d "$BIN_DIR/DynamicIsland_DynamicIsland.bundle" ]]; then
  cp -R "$BIN_DIR/DynamicIsland_DynamicIsland.bundle" "$APP/Contents/MacOS/"
fi

# Also copy raw assets into Resources for Bundle.main lookups.
if [[ -d "$ROOT/Sources/DynamicIsland/Resources" ]]; then
  cp -R "$ROOT/Sources/DynamicIsland/Resources/"* "$APP/Contents/Resources/" 2>/dev/null || true
fi

echo "Built: $APP"
