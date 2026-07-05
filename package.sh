#!/bin/bash
set -e

# Defaults
SIGN_IDENTITY=""
NOTARY_PROFILE=""
KEYCHAIN_PROFILE=""
APP_BUNDLE="Orivo.app"
DMG_NAME="Orivo.dmg"

usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --sign <identity>          The Developer ID Application codesigning identity (e.g. \"Developer ID Application: Company (ID)\")"
    echo "  --notary-profile <name>    The keychain profile name stored via 'xcrun notarytool store-credentials'"
    echo "  --help                     Show this help message"
    exit 1
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --sign)
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        --notary-profile)
            NOTARY_PROFILE="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

echo "=== Step 1: Running build.sh to compile & bundle Orivo ==="
./build.sh

# Ensure entitlements file exists
if [ ! -f "entitlements.plist" ]; then
    echo "Error: entitlements.plist not found. Please run this script from the project root."
    exit 1
fi

if [ -n "$SIGN_IDENTITY" ]; then
    echo "=== Step 2: Code-signing Orivo.app with Developer ID Application and Hardened Runtime ==="
    
    # 1. Sign all dynamic libraries bundled in Frameworks (deepest first)
    if [ -d "$APP_BUNDLE/Contents/Frameworks" ]; then
        echo "Signing bundled Frameworks/libraries..."
        for dylib in "$APP_BUNDLE/Contents/Frameworks"/*.dylib; do
            if [ -f "$dylib" ]; then
                echo "Signing $(basename "$dylib")..."
                codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$dylib"
            fi
        done
    fi
    
    # 2. Sign main executable
    echo "Signing main executable..."
    codesign --force --timestamp --options runtime --entitlements entitlements.plist --sign "$SIGN_IDENTITY" "$APP_BUNDLE/Contents/MacOS/Orivo"
    
    # 3. Sign app bundle itself
    echo "Signing app bundle..."
    codesign --force --timestamp --options runtime --entitlements entitlements.plist --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
    
    echo "Verifying app bundle signature..."
    codesign --verify --deep --strict --verbose=4 "$APP_BUNDLE"
    
    echo "Checking gatekeeper assessment..."
    spctl --assess --type execute --verbose "$APP_BUNDLE"
else
    echo "=== Step 2: Skipping signing (No identity provided, run with --sign) ==="
fi

echo "=== Step 3: Packaging Orivo.app into DMG ==="
rm -f "$DMG_NAME"

# Create a temporary directory for DMG packaging
TMP_DMG_DIR="tmp_dmg_pkg"
rm -rf "$TMP_DMG_DIR"
mkdir -p "$TMP_DMG_DIR"

# Copy the app bundle
cp -R "$APP_BUNDLE" "$TMP_DMG_DIR/"

# Create background link to /Applications
ln -s /Applications "$TMP_DMG_DIR/Applications"

echo "Creating DMG container..."
hdiutil create -volname "Orivo" -srcfolder "$TMP_DMG_DIR" -ov -format UDZO "$DMG_NAME"
rm -rf "$TMP_DMG_DIR"

if [ -n "$SIGN_IDENTITY" ]; then
    echo "=== Step 4: Signing DMG container ==="
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_NAME"
    codesign --verify --verbose=4 "$DMG_NAME"
fi

if [ -n "$NOTARY_PROFILE" ] && [ -n "$SIGN_IDENTITY" ]; then
    echo "=== Step 5: Submitting DMG for Apple Notarization ==="
    echo "Submitting $DMG_NAME using profile '$NOTARY_PROFILE'..."
    
    # Submit to Apple
    xcrun notarytool submit "$DMG_NAME" --keychain-profile "$NOTARY_PROFILE" --wait
    
    echo "=== Step 6: Stapling Notarization Ticket to DMG ==="
    xcrun notarytool staple "$DMG_NAME"
    
    echo "Verifying stapling result..."
    spctl --assess -a -t open --context context:primary-signature --verbose "$DMG_NAME"
else
    echo "=== Step 5: Skipping Notarization (Run with --sign and --notary-profile to notarize) ==="
    echo "To notarize, first store credentials in keychain:"
    echo "  xcrun notarytool store-credentials \"profile_name\" --apple-id \"your_apple_id\" --team-id \"your_team_id\" --password \"app_specific_password\""
    echo "Then run packaging with:"
    echo "  ./package.sh --sign \"Developer ID Application: Your Company (TEAMID)\" --notary-profile \"profile_name\""
fi

echo "=== Packaging completed! Output: $DMG_NAME ==="
