#!/bin/bash
# Builds MacMemMan in Release configuration and packages it into a distributable .dmg —
# the classic "drag the app into Applications" installer image.
#
# Usage:
#   ./scripts/build-dmg.sh
#
# Output:
#   ./dist/MacMemMan.dmg
#
# Important — read before sending this to someone else:
# This project has no Apple Developer Team configured (see DEVELOPMENT_TEAM in project.yml), so
# the app is only ad-hoc signed here, not signed with a real Developer ID and not notarized.
# Gatekeeper will refuse to open an ad-hoc/unsigned app downloaded from the internet with a plain
# double-click. The person installing it needs to either:
#   - right-click (or Control-click) the app in Applications and choose "Open", then confirm in
#     the dialog that appears (only needed the first time), or
#   - go to System Settings -> Privacy & Security and click "Open Anyway" after the first blocked
#     attempt.
# To get rid of that prompt entirely for real distribution, you'd need an Apple Developer Program
# membership ($99/year), a "Developer ID Application" signing certificate, and to notarize the
# built app/DMG with `notarytool` before shipping it — that's a separate, deliberate step, not
# something this script does automatically.

set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="MacMemMan"
SCHEME="MacMemMan"
DERIVED_DATA_DIR="$(pwd)/build"
DIST_DIR="$(pwd)/dist"
STAGING_DIR="$(pwd)/dmg-staging"
DMG_PATH="$DIST_DIR/${APP_NAME}.dmg"

echo "==> Regenerating Xcode project from project.yml"
xcodegen generate

echo "==> Building $SCHEME (Release)"
xcodebuild \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  clean build

APP_PATH="$DERIVED_DATA_DIR/Build/Products/Release/${APP_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
  echo "error: build succeeded but $APP_PATH is missing" >&2
  exit 1
fi

echo "==> Staging DMG contents"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Creating $DMG_PATH"
mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG_PATH"

rm -rf "$STAGING_DIR"

echo ""
echo "Done: $DMG_PATH"
echo "Reminder: this build is ad-hoc signed, not notarized — see the notes at the top of this script."
