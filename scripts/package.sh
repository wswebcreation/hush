#!/bin/zsh
# Builds Hush and packages it as build/Hush-<version>.zip for sharing. No Apple notarization.
#
# Optional: SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   With it, the app has a stable signature, so colleagues keep their microphone and audio
#   permissions across updates. Without it the build is ad-hoc signed and macOS asks again
#   for permissions after every update.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
ZIP=build/Hush-$VERSION.zip

scripts/bundle.sh release
codesign --verify --deep --strict "build/Hush.app"

rm -f "$ZIP"
# ditto keeps the signature and extended attributes intact (plain `zip` can break them).
ditto -c -k --keepParent build/Hush.app "$ZIP"
echo "Done: $ZIP"
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  echo "Note: ad-hoc signed. Colleagues will be asked for permissions again after each update."
fi
