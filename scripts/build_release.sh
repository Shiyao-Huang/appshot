#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.0}"
BUILD_DIR="$ROOT/.xcode-build"
DERIVED_DATA_DIR="$BUILD_DIR/DerivedData"
PRODUCTS_DIR="$BUILD_DIR/Products"
DIST_DIR="$ROOT/dist"
APP_NAME="AppShot"
APP_PATH="$PRODUCTS_DIR/Release/$APP_NAME.app"
ZIP_PATH="$DIST_DIR/AppShot-macOS-$VERSION.zip"
DMG_PATH="$DIST_DIR/AppShot-macOS-$VERSION.dmg"

cd "$ROOT"

swift scripts/generate_app_icon.swift
swift build
xcodebuild \
  -project AppShot.xcodeproj \
  -scheme AppShot \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  SYMROOT="$PRODUCTS_DIR" \
  build

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
ditto "$APP_PATH" "$DIST_DIR/$APP_NAME.app"

ditto -c -k --keepParent "$DIST_DIR/$APP_NAME.app" "$ZIP_PATH"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DIST_DIR/$APP_NAME.app" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

codesign --verify --deep --strict "$DIST_DIR/$APP_NAME.app"
spctl --assess --type execute "$DIST_DIR/$APP_NAME.app" || true

echo "$DIST_DIR/$APP_NAME.app"
echo "$ZIP_PATH"
echo "$DMG_PATH"
