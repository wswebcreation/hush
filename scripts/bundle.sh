#!/bin/zsh
# Builds Hush.app into build/. Usage: scripts/bundle.sh [debug|release]
# Set SIGN_IDENTITY="Developer ID Application: …" to sign for distribution (default: ad-hoc).
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG=${1:-release}
swift build -c "$CONFIG"
BIN=$(swift build -c "$CONFIG" --show-bin-path)/Hush
APP=build/Hush.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Hush"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --options runtime --entitlements Resources/Hush.entitlements \
  --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"
