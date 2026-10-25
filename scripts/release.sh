#!/bin/zsh
# Builds, signs, notarizes and packages Hush into build/Hush-<version>.dmg.
#
# Required environment:
#   SIGN_IDENTITY   e.g. "Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE  name of a notarytool keychain profile (see README, "One-time setup")
set -euo pipefail
cd "$(dirname "$0")/.."

: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to your notarytool keychain profile name}"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
APP=build/Hush.app
ZIP=build/Hush-notarize.zip
DMG=build/Hush-$VERSION.dmg

scripts/bundle.sh release

echo "Verifying signature…"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "Submitting to Apple for notarization (this can take a few minutes)…"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
rm -f "$ZIP"

echo "Stapling ticket…"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "Creating DMG…"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Hush" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
codesign --force --sign "$SIGN_IDENTITY" "$DMG"

spctl --assess --type execute --verbose "$APP" || true
echo "Done: $DMG"
