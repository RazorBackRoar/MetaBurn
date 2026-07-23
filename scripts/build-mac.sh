#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."
APP_NAME="MetaBurn"
BUNDLE_ID="com.razorbackroar.metaburn"

# Resolve Swift Package version from version.json
VERSION="$(sed -n 's/.*"version".*"\([^"]*\)".*/\1/p' "$PROJECT_DIR/Sources/MetaBurn/Resources/version.json")"

RELEASE_DIR="$PROJECT_DIR/build/Release"
APP_PATH="$RELEASE_DIR/$APP_NAME.app"
DMG_PATH="$RELEASE_DIR/$APP_NAME.dmg"
EXEC_PATH="$PROJECT_DIR/.build/release/$APP_NAME"
RESOURCE_BUNDLE="$PROJECT_DIR/.build/release/${APP_NAME}_${APP_NAME}.bundle"

# Optional Developer ID + notarization (set in the environment to enable):
#   METABURN_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   NOTARYTOOL_KEYCHAIN_PROFILE="notarytool-profile"   # preferred
#   — or — APPLE_ID / APPLE_TEAM_ID / APPLE_APP_SPECIFIC_PASSWORD
SIGN_IDENTITY="${METABURN_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARYTOOL_KEYCHAIN_PROFILE:-}"

echo "Building MetaBurn release..."
cd "$PROJECT_DIR"
swift build -c release

echo "Packaging $APP_NAME.app..."
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

cp "$EXEC_PATH" "$APP_PATH/Contents/MacOS/$APP_NAME"
cp "$PROJECT_DIR/Sources/MetaBurn/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
cp "$PROJECT_DIR/Sources/MetaBurn/Resources/version.json" "$APP_PATH/Contents/Resources/version.json"

# Keep the SwiftPM resource bundle in Contents/Resources for the Resources resolver.
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_PATH/Contents/Resources/${APP_NAME}_${APP_NAME}.bundle"
fi

# Generate Info.plist
cat > "$APP_PATH/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © $(date +%Y) RazorBackRoar. All rights reserved.</string>
</dict>
</plist>
EOF

chmod +x "$APP_PATH/Contents/MacOS/$APP_NAME"

# Keep copyright year current via shared helper (does not touch DMG layout).
RAZORCORE_DIR="$(cd "$SCRIPT_DIR/../../.razorcore" && pwd)"
"$RAZORCORE_DIR/patch-app-branding.sh" "$APP_PATH"

if [ -n "$SIGN_IDENTITY" ]; then
    echo "Signing $APP_NAME.app with Developer ID ($SIGN_IDENTITY)..."
    codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP_PATH"
    codesign --verify --verbose=2 "$APP_PATH"
else
    echo "Ad-hoc signing $APP_NAME.app (set METABURN_SIGN_IDENTITY for Developer ID)..."
    codesign --force --deep --sign - "$APP_PATH"
fi

echo "Creating $APP_NAME.dmg with shared layout..."
mkdir -p "$RELEASE_DIR"
# Versioned volume name so Finder does not reuse a remembered (broken) window size
# from an older "MetaBurn" mount.
VOLUME_NAME="$APP_NAME $VERSION"
"$RAZORCORE_DIR/package-dmg.sh" \
  --app "$APP_PATH" \
  --dmg "$DMG_PATH" \
  --app-name "$APP_NAME" \
  --volname "$VOLUME_NAME"

if [ -n "$SIGN_IDENTITY" ]; then
    echo "Signing $APP_NAME.dmg..."
    codesign --force --sign "$SIGN_IDENTITY" "$DMG_PATH"
fi

if [ -n "$SIGN_IDENTITY" ] && { [ -n "$NOTARY_PROFILE" ] || { [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]; }; }; then
    echo "Submitting $APP_NAME.dmg for notarization..."
    if [ -n "$NOTARY_PROFILE" ]; then
        xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    else
        xcrun notarytool submit "$DMG_PATH" \
            --apple-id "$APPLE_ID" \
            --team-id "$APPLE_TEAM_ID" \
            --password "$APPLE_APP_SPECIFIC_PASSWORD" \
            --wait
    fi
    echo "Stapling notarization ticket..."
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
    echo "Notarization complete."
elif [ -n "$SIGN_IDENTITY" ]; then
    echo "Signed but not notarized (set NOTARYTOOL_KEYCHAIN_PROFILE or APPLE_ID/APPLE_TEAM_ID/APPLE_APP_SPECIFIC_PASSWORD)."
fi

# Package as a single DMG; do not leave the .app bundle in the app folder.
rm -rf "$APP_PATH"

echo "Build complete: $DMG_PATH"
