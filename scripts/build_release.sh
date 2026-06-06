#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.4}"
BUILD_DIR="$ROOT/.xcode-build"
DERIVED_DATA_DIR="$BUILD_DIR/DerivedData"
PRODUCTS_DIR="$BUILD_DIR/Products"
DIST_DIR="$ROOT/dist"
PACKAGE_DIR="$DIST_DIR/AppShot-macOS-$VERSION"
APP_NAME="AppShot"
APP_PATH="$PRODUCTS_DIR/Release/$APP_NAME.app"
CLI_PATH="$ROOT/.build/release/appshot"
ZIP_PATH="$DIST_DIR/AppShot-macOS-$VERSION.zip"
DMG_PATH="$DIST_DIR/AppShot-macOS-$VERSION.dmg"
SIGN_IDENTITY="${APPSHOT_CODESIGN_IDENTITY:-}"
DEVELOPMENT_TEAM="${APPSHOT_DEVELOPMENT_TEAM:-}"
NOTARY_PROFILE="${APPSHOT_NOTARY_PROFILE:-}"
PUBLIC_RELEASE="${APPSHOT_PUBLIC_RELEASE:-0}"
XCODEBUILD_SIGNING_ARGS=()

cd "$ROOT"

fail() {
  printf 'build_release: error: %s\n' "$*" >&2
  exit 1
}

resolve_identity_for_team() {
  local team="$1"
  security find-identity -v -p codesigning 2>/dev/null \
    | awk -v team="($team)" '
        /"Developer ID Application:/ && index($0, team) {
          sub(/^[^"]*"/, ""); sub(/".*$/, ""); print; exit
        }
        /"Apple Development:/ && index($0, team) && found == "" {
          line = $0
          sub(/^[^"]*"/, "", line); sub(/".*$/, "", line)
          found = line
        }
        END {
          if (found != "") print found
        }
      ' \
    | head -n 1
}

require_identity_available() {
  local identity="$1"
  security find-identity -v -p codesigning 2>/dev/null \
    | grep -Fq "\"$identity\"" \
    || fail "code signing identity not found in keychain: $identity"
}

require_developer_id_identity() {
  local identity="$1"
  [[ "$identity" == Developer\ ID\ Application:* ]] \
    || fail "public releases require a Developer ID Application identity; got: $identity"
}

require_non_adhoc_signature() {
  local path="$1"
  local label="$2"
  local details
  details="$(codesign -dv --verbose=4 "$path" 2>&1 || true)"
  printf '%s\n' "$details" | grep -q '^Signature=adhoc' \
    && fail "$label is ad-hoc signed: $path"
  printf '%s\n' "$details" | grep -q '^TeamIdentifier=' \
    || fail "$label has no TeamIdentifier: $path"
}

if [[ "$PUBLIC_RELEASE" == "1" ]]; then
  [[ -n "$NOTARY_PROFILE" ]] \
    || fail "public releases require APPSHOT_NOTARY_PROFILE for notarization"
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
  require_identity_available "$SIGN_IDENTITY"
  if [[ "$PUBLIC_RELEASE" == "1" ]]; then
    require_developer_id_identity "$SIGN_IDENTITY"
  fi
  XCODEBUILD_SIGNING_ARGS=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY"
    AD_HOC_CODE_SIGNING_ALLOWED=NO
  )
elif [[ -n "$DEVELOPMENT_TEAM" ]]; then
  SIGN_IDENTITY="$(resolve_identity_for_team "$DEVELOPMENT_TEAM")"
  if [[ "$PUBLIC_RELEASE" == "1" ]]; then
    [[ -n "$SIGN_IDENTITY" ]] || fail "no Developer ID Application identity found for team $DEVELOPMENT_TEAM"
    require_developer_id_identity "$SIGN_IDENTITY"
  fi
  XCODEBUILD_SIGNING_ARGS=(
    -allowProvisioningUpdates
    CODE_SIGN_STYLE=Automatic
    CODE_SIGN_IDENTITY="Apple Development"
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"
    AD_HOC_CODE_SIGNING_ALLOWED=NO
  )
else
  fail "release builds require APPSHOT_CODESIGN_IDENTITY or APPSHOT_DEVELOPMENT_TEAM; refusing to produce an ad-hoc release"
fi

swift scripts/generate_app_icon.swift
swift build -c release --product appshot
xcodebuild \
  -project AppShot.xcodeproj \
  -scheme AppShot \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  SYMROOT="$PRODUCTS_DIR" \
  "${XCODEBUILD_SIGNING_ARGS[@]}" \
  build

if [[ -z "$SIGN_IDENTITY" && -n "$DEVELOPMENT_TEAM" ]]; then
  SIGN_IDENTITY="$(resolve_identity_for_team "$DEVELOPMENT_TEAM")"
fi
[[ -n "$SIGN_IDENTITY" ]] || fail "no signing identity available after Xcode build; cannot sign release package"
require_identity_available "$SIGN_IDENTITY"
if [[ "$PUBLIC_RELEASE" == "1" ]]; then
  require_developer_id_identity "$SIGN_IDENTITY"
fi

rm -rf "$DIST_DIR"
mkdir -p "$PACKAGE_DIR/bin" "$PACKAGE_DIR/mcp"
ditto "$APP_PATH" "$PACKAGE_DIR/$APP_NAME.app"
ditto "$CLI_PATH" "$PACKAGE_DIR/bin/appshot"
ditto "$ROOT/mcp/server.js" "$PACKAGE_DIR/mcp/server.js"
ditto "$ROOT/mcp/package.json" "$PACKAGE_DIR/mcp/package.json"
chmod +x "$PACKAGE_DIR/bin/appshot" "$PACKAGE_DIR/mcp/server.js"

codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$PACKAGE_DIR/bin/appshot"
codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$PACKAGE_DIR/$APP_NAME.app"

ditto -c -k --keepParent "$PACKAGE_DIR" "$ZIP_PATH"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$PACKAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"

codesign --verify --deep --strict "$PACKAGE_DIR/$APP_NAME.app"
codesign --verify --strict "$PACKAGE_DIR/bin/appshot"
require_non_adhoc_signature "$PACKAGE_DIR/$APP_NAME.app" "AppShot.app"
require_non_adhoc_signature "$PACKAGE_DIR/bin/appshot" "appshot CLI"
require_non_adhoc_signature "$DMG_PATH" "DMG"

if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
fi

if [[ "$PUBLIC_RELEASE" == "1" ]]; then
  spctl --assess --type execute "$PACKAGE_DIR/$APP_NAME.app"
  spctl --assess --type open "$DMG_PATH"
else
  spctl --assess --type execute "$PACKAGE_DIR/$APP_NAME.app" || true
  spctl --assess --type open "$DMG_PATH" || true
fi

echo "$PACKAGE_DIR/$APP_NAME.app"
echo "$PACKAGE_DIR/bin/appshot"
echo "$ZIP_PATH"
echo "$DMG_PATH"
