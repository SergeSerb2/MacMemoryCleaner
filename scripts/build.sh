#!/bin/bash
# Builds "Mac Memory Cleaner.app" into ./build, plus a .zip and a .dmg.
#
#   scripts/build.sh            build and sign
#   scripts/build.sh --install  also copy the app to /Applications and open it
#
# Signing uses SIGN_IDENTITY if set, else the first Developer ID or Apple Development
# certificate in your keychain, else an ad-hoc signature.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Mac Memory Cleaner"
APP="build/$APP_NAME.app"

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/MacMemoryCleaner"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacMemoryCleaner"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -Eo '"(Developer ID Application|Apple Development): [^"]+"' | head -1 | tr -d '"' || true)
fi
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
codesign --force --options runtime --timestamp=none --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "Signed with: $SIGN_IDENTITY"

rm -f build/MacMemoryCleaner.zip
ditto -c -k --keepParent "$APP" build/MacMemoryCleaner.zip

# Disk image with the usual "drag to Applications" layout.
DMG="build/MacMemoryCleaner.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGING" -fs APFS -format UDZO "$DMG"
codesign --force --timestamp=none --sign "$SIGN_IDENTITY" "$DMG"
echo "Built $APP, build/MacMemoryCleaner.zip, and $DMG"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x MacMemoryCleaner && sleep 1 || true
  rm -rf "/Applications/$APP_NAME.app"
  ditto "$APP" "/Applications/$APP_NAME.app"
  open "/Applications/$APP_NAME.app"
  echo "Installed to /Applications/$APP_NAME.app"
fi
