#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.0}"
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
NOTARY_PROFILE="${APPSHOT_NOTARY_PROFILE:-}"

cd "$ROOT"

swift scripts/generate_app_icon.swift
swift build -c release --product appshot
xcodebuild \
  -project AppShot.xcodeproj \
  -scheme AppShot \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  SYMROOT="$PRODUCTS_DIR" \
  build

rm -rf "$DIST_DIR"
mkdir -p "$PACKAGE_DIR/bin" "$PACKAGE_DIR/mcp"
ditto "$APP_PATH" "$PACKAGE_DIR/$APP_NAME.app"
ditto "$CLI_PATH" "$PACKAGE_DIR/bin/appshot"
ditto "$ROOT/mcp/server.js" "$PACKAGE_DIR/mcp/server.js"
ditto "$ROOT/mcp/package.json" "$PACKAGE_DIR/mcp/package.json"
chmod +x "$PACKAGE_DIR/bin/appshot" "$PACKAGE_DIR/mcp/server.js"

if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$PACKAGE_DIR/bin/appshot"
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$PACKAGE_DIR/$APP_NAME.app"
fi

ditto -c -k --keepParent "$PACKAGE_DIR" "$ZIP_PATH"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$PACKAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
fi

codesign --verify --deep --strict "$PACKAGE_DIR/$APP_NAME.app"
codesign --verify --strict "$PACKAGE_DIR/bin/appshot"

if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
fi

spctl --assess --type execute "$PACKAGE_DIR/$APP_NAME.app" || true
spctl --assess --type open "$DMG_PATH" || true

echo "$PACKAGE_DIR/$APP_NAME.app"
echo "$PACKAGE_DIR/bin/appshot"
echo "$ZIP_PATH"
echo "$DMG_PATH"
