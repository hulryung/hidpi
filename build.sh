#!/bin/bash

# Build, sign, notarize, and package HiDPI for distribution
# Prerequisites:
#   - Developer ID Application certificate in Keychain
#   - Notarytool credentials stored: xcrun notarytool store-credentials "HangulCommandApp" --apple-id <email> --team-id XGJ87M8ZZR

set -euo pipefail

APP_NAME="HiDPI"
BUNDLE_ID="com.huconn.hidpi"
TEAM_ID="XGJ87M8ZZR"
SIGNING_IDENTITY="Developer ID Application: HUCONN Co.,Ltd. (XGJ87M8ZZR)"
KEYCHAIN_PROFILE="HangulCommandApp"
VERSION="1.0.0"

BUILD_DIR="$(pwd)/build"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"

echo "=== Building ${APP_NAME} v${VERSION} ==="

# Clean
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Step 1: Build release binaries
echo ""
echo "--- Step 1/7: Build ---"
cd HiDPIApp && swift build -c release 2>&1 | tail -3
HIDPI_APP_BIN="$(pwd)/.build/release/HiDPIApp"
cd ..

cd HiDPITool && swift build -c release 2>&1 | tail -3
HIDPI_TOOL_BIN="$(pwd)/.build/release/HiDPITool"
cd ..

echo "Binaries built"

# Step 2: Create .app bundle
echo ""
echo "--- Step 2/7: Create .app bundle ---"
mkdir -p "${APP_PATH}/Contents/MacOS"
mkdir -p "${APP_PATH}/Contents/Resources"

cp "$HIDPI_APP_BIN" "${APP_PATH}/Contents/MacOS/${APP_NAME}"
cp "$HIDPI_TOOL_BIN" "${APP_PATH}/Contents/MacOS/hidpi-cli"
cp "HiDPIApp/Resources/AppIcon.icns" "${APP_PATH}/Contents/Resources/AppIcon.icns"

# Info.plist
cat > "${APP_PATH}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
PLIST

echo ".app bundle created: ${APP_PATH}"

# Step 3: Create entitlements
echo ""
echo "--- Step 3/7: Entitlements ---"
ENTITLEMENTS="${BUILD_DIR}/entitlements.plist"
cat > "$ENTITLEMENTS" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
PLIST
echo "Entitlements created"

# Step 4: Code sign
echo ""
echo "--- Step 4/7: Code sign ---"
codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGNING_IDENTITY" \
    "${APP_PATH}/Contents/MacOS/hidpi-cli"

codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGNING_IDENTITY" \
    "$APP_PATH"

codesign --verify --deep --strict "$APP_PATH"
echo "Code signing verified"

# Step 5: Notarize
echo ""
echo "--- Step 5/7: Notarize ---"
NOTARIZE_ZIP="${BUILD_DIR}/${APP_NAME}-notarize.zip"
ditto -c -k --sequesterRsrc "$APP_PATH" "$NOTARIZE_ZIP"

xcrun notarytool submit "$NOTARIZE_ZIP" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait

rm -f "$NOTARIZE_ZIP"
echo "Notarization completed"

# Step 6: Staple
echo ""
echo "--- Step 6/7: Staple ---"
xcrun stapler staple "$APP_PATH"
echo "Stapling completed"

# Step 7: Package
echo ""
echo "--- Step 7/7: Package ---"

# Create DMG
DMG_PATH="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"
DMG_TEMP="${BUILD_DIR}/dmg_temp"
mkdir -p "$DMG_TEMP"
cp -R "$APP_PATH" "$DMG_TEMP/"
ln -s /Applications "$DMG_TEMP/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_TEMP" -ov -format UDZO "$DMG_PATH"
rm -rf "$DMG_TEMP"

# Notarize and staple DMG
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait
xcrun stapler staple "$DMG_PATH"

echo ""
echo "=== Build complete ==="
echo "  DMG: ${DMG_PATH}"
echo "  SHA256: $(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
ls -lh "$DMG_PATH"
