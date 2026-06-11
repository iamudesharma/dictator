#!/bin/bash
# Creates a DMG installer for Dictator
set -euo pipefail

APP_NAME="voice_to_text"
BUILD_DIR="build/macos/Build/Products/Release"
DMG_NAME="Dictator-v1.0.0.dmg"
DMG_OUTPUT="build/${DMG_NAME}"
TEMP_DIR="build/dmg_staging"

echo "🧹 Cleaning previous DMG staging..."
rm -rf "${TEMP_DIR}"
rm -f "${DMG_OUTPUT}"

echo "📦 Preparing DMG contents..."
mkdir -p "${TEMP_DIR}"
cp -R "${BUILD_DIR}/${APP_NAME}.app" "${TEMP_DIR}/"
ln -s /Applications "${TEMP_DIR}/Applications"

echo "💿 Creating DMG..."
hdiutil create \
  -volname "Dictator" \
  -srcfolder "${TEMP_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_OUTPUT}"

echo "🧹 Cleaning staging directory..."
rm -rf "${TEMP_DIR}"

echo ""
echo "✅ DMG created: ${DMG_OUTPUT}"
echo "📏 Size: $(du -h "${DMG_OUTPUT}" | cut -f1)"
echo ""
echo "To distribute:"
echo "  1. Upload ${DMG_OUTPUT} to GitHub Releases"
echo "  2. Users: Open DMG → Drag app to Applications → Right-click → Open"
