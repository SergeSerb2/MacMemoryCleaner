#!/bin/bash
# Builds "Mac Memory Cleaner.app" into ./build, plus a .zip and a .dmg.
#
#   scripts/build.sh            build and sign
#   scripts/build.sh --install  also copy the app to /Applications and open it
#
# Environment variables, all optional:
#   VERSION         Marketing version, e.g. 1.2.0 or v1.2.0. Default: Resources/Info.plist.
#   BUILD_NUMBER    CFBundleVersion. Default: the number of commits on HEAD.
#   SIGN_IDENTITY   codesign identity. Default: the first "Developer ID Application" or
#                   "Apple Development" certificate in your keychain, else "-" (ad-hoc).
#   Notarization needs a "Developer ID Application" identity (the build fails without
#   one) and one of:
#   NOTARY_PROFILE                              a profile saved with
#                                               `xcrun notarytool store-credentials`
#   NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER   an App Store Connect API key
set -euo pipefail
cd "$(dirname "$0")/.."

INSTALL=false
for argument in "$@"; do
  case "$argument" in
    --install) INSTALL=true ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "error: unknown argument: $argument (try --help)" >&2; exit 64 ;;
  esac
done

APP_NAME="Mac Memory Cleaner"
APP="build/$APP_NAME.app"
ZIP="build/MacMemoryCleaner.zip"
DMG="build/MacMemoryCleaner.dmg"

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/MacMemoryCleaner"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacMemoryCleaner"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

PLIST="$APP/Contents/Info.plist"
if [[ -n "${VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION#v}" "$PLIST"
fi
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
echo "Version $(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST") ($BUILD_NUMBER)"

# --- Signing ---------------------------------------------------------------------------
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  IDENTITIES=$(security find-identity -v -p codesigning 2>/dev/null || true)
  # Prefer Developer ID, which is the only kind that can be notarized.
  for KIND in "Developer ID Application" "Apple Development"; do
    SIGN_IDENTITY=$(grep -Eo "\"$KIND: [^\"]+\"" <<< "$IDENTITIES" | head -1 | tr -d '"' || true)
    [[ -n "$SIGN_IDENTITY" ]] && break
  done
fi
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
DEVELOPER_ID=false
[[ "$SIGN_IDENTITY" == "Developer ID Application"* ]] && DEVELOPER_ID=true
# Notarization needs a secure timestamp. Other identities skip it, so offline builds work.
if $DEVELOPER_ID; then TIMESTAMP=--timestamp; else TIMESTAMP=--timestamp=none; fi

codesign --force --options runtime "$TIMESTAMP" --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "Signed with: $SIGN_IDENTITY"

# --- Notarization (optional) -----------------------------------------------------------
NOTARIZE=false
if [[ -n "${NOTARY_PROFILE:-}" || -n "${NOTARY_KEY_PATH:-}" ]]; then
  if ! $DEVELOPER_ID; then
    echo "error: notarization needs a \"Developer ID Application\" signing identity" >&2
    exit 1
  fi
  NOTARIZE=true
fi

notarize() {
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
  else
    xcrun notarytool submit "$1" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait
  fi
}

if $NOTARIZE; then
  # Staple the app itself, so it also passes Gatekeeper offline after leaving the DMG.
  ditto -c -k --keepParent "$APP" "$ZIP"
  notarize "$ZIP"
  xcrun stapler staple "$APP"
fi

# --- Packages --------------------------------------------------------------------------
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# Disk image with the usual "drag to Applications" layout.
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGING" -fs APFS -format UDZO "$DMG"
codesign --force "$TIMESTAMP" --sign "$SIGN_IDENTITY" "$DMG"

if $NOTARIZE; then
  notarize "$DMG"
  xcrun stapler staple "$DMG"
fi

echo "Built $APP, $ZIP, and $DMG"

if $INSTALL; then
  TARGET="/Applications/$APP_NAME.app"
  # Copy first, then swap, so a failed copy never leaves you without the app.
  rm -rf "$TARGET.new"
  ditto "$APP" "$TARGET.new"
  codesign --verify --strict "$TARGET.new"
  pkill -x MacMemoryCleaner && sleep 1 || true
  rm -rf "$TARGET"
  mv "$TARGET.new" "$TARGET"
  open "$TARGET"
  echo "Installed to $TARGET"
fi
