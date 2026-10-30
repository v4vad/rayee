#!/bin/bash
#
# Rayee Release Script
#
# Builds Rayee into a distributable .dmg file.
# Pure native app — no Python server, no PyInstaller.
#
# Prerequisites:
#   - Xcode and command line tools
#   - Developer ID Application certificate (Xcode > Settings > Accounts)
#   - Notary credentials saved once: xcrun notarytool store-credentials rayee-notary
#
# Usage:
#   ./publish_release.sh
#
# Output:
#   Rayee.dmg (in the current directory)
#

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

APP_NAME="Rayee"
SWIFT_DIR="$SCRIPT_DIR/swift/Rayee"
BUILD_DIR="$SCRIPT_DIR/build"
DMG_NAME="${APP_NAME}.dmg"

echo ""
echo "=========================================="
echo "  Building Rayee for Distribution"
echo "=========================================="
echo ""

# Check prerequisites
info "Checking prerequisites..."
if ! command -v xcodebuild &> /dev/null; then
    error "Xcode command line tools not found. Install with: xcode-select --install"
fi
success "Prerequisites check passed"
echo ""

# ==========================================
# Step 1: Build Swift App with Xcode
# ==========================================
info "Step 1: Building Swift app with Xcode..."

cd "$SWIFT_DIR"

xcodebuild clean -project Rayee.xcodeproj -scheme Rayee -configuration Release 2>/dev/null || true

info "Building Rayee.app (Release configuration)..."
xcodebuild build \
    -project Rayee.xcodeproj \
    -scheme Rayee \
    -configuration Release \
    -derivedDataPath build \
    CODE_SIGN_IDENTITY="-" \
    ONLY_ACTIVE_ARCH=NO

APP_PATH="$SWIFT_DIR/build/Build/Products/Release/Rayee.app"
if [ ! -d "$APP_PATH" ]; then
    error "Xcode build failed - Rayee.app not found at $APP_PATH"
fi

success "Swift app built successfully"
echo ""

# ==========================================
# Step 1b: Sign app bundle with Developer ID
# ==========================================
# Apps shared outside the App Store need a Developer ID Application cert,
# hardened runtime (-o runtime) and a secure timestamp, or Gatekeeper rejects
# them. Sign inside-out (Sparkle's helpers first, the app last) instead of
# --deep, which drops hardened runtime and the XPC services' entitlements.
# A stable Team ID (VXYPQ995EU) also keeps macOS permissions across updates.
info "Step 1b: Signing app bundle with Developer ID..."
ENTITLEMENTS="$SWIFT_DIR/Rayee/Rayee.entitlements"
SIGN_IDENTITY=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*(VXYPQ995EU)"' | head -1 | tr -d '"')
if [ -z "$SIGN_IDENTITY" ]; then
    error "No Developer ID Application certificate found. Create one in Xcode > Settings > Accounts > Manage Certificates."
fi
info "Using: $SIGN_IDENTITY"
sign() { codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$@"; }

SPARKLE="$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$SPARKLE/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/Updater.app"
sign "$APP_PATH/Contents/Frameworks/Sparkle.framework"
for DYLIB in "$APP_PATH"/Contents/Frameworks/*.dylib; do
    [ -e "$DYLIB" ] && sign "$DYLIB"
done
sign --entitlements "$ENTITLEMENTS" "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
success "App signed"
echo ""

# ==========================================
# Step 2: Create DMG
# ==========================================
info "Step 2: Creating DMG..."

cd "$SCRIPT_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

rm -f "$DMG_NAME"

STAGING_DIR="$BUILD_DIR/staging"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_NAME"

APP_SIZE=$(du -sh "$APP_PATH" | cut -f1)
DMG_SIZE=$(du -sh "$DMG_NAME" | cut -f1)

rm -rf "$BUILD_DIR"

# ==========================================
# Step 2b: Sign, notarize and staple the DMG
# ==========================================
# Notarization: Apple scans the DMG and issues a ticket; stapling attaches the
# ticket so Gatekeeper accepts it even offline. Must run before Sparkle's
# signature, because stapling changes the file.
# One-time setup: xcrun notarytool store-credentials rayee-notary
info "Step 2b: Notarizing DMG (usually a few minutes)..."
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_NAME"
NOTARY_OUTPUT=$(xcrun notarytool submit "$DMG_NAME" --keychain-profile rayee-notary --wait 2>&1) || true
echo "$NOTARY_OUTPUT"
if ! echo "$NOTARY_OUTPUT" | grep -q "status: Accepted"; then
    error "Notarization failed. See details with: xcrun notarytool log <submission id> --keychain-profile rayee-notary"
fi
xcrun stapler staple "$DMG_NAME"
spctl -a -vv -t open --context context:primary-signature "$DMG_NAME"
success "DMG notarized and stapled"
echo ""

# ==========================================
# Step 3: Sign DMG for Sparkle Updates
# ==========================================
info "Step 3: Signing DMG for Sparkle auto-updates..."

SIGN_UPDATE=""
DERIVED_SIGN=$(find "$SWIFT_DIR/build" -name "sign_update" -type f 2>/dev/null | head -1)
if [ -n "$DERIVED_SIGN" ]; then
    SIGN_UPDATE="$DERIVED_SIGN"
fi

if [ -n "$SIGN_UPDATE" ] && [ -f "$SIGN_UPDATE" ]; then
    info "Found sign_update at: $SIGN_UPDATE"
    SIGNATURE_OUTPUT=$("$SIGN_UPDATE" "$SCRIPT_DIR/$DMG_NAME" 2>&1) || true
    if [ -n "$SIGNATURE_OUTPUT" ]; then
        echo ""
        echo "=========================================="
        echo "  Sparkle Signature Info"
        echo "=========================================="
        echo "$SIGNATURE_OUTPUT"
        echo ""
    fi
else
    warn "Sparkle sign_update tool not found. Sign the DMG manually or after resolving Sparkle packages in Xcode."
fi

DMG_BYTES=$(stat -f%z "$SCRIPT_DIR/$DMG_NAME" 2>/dev/null || stat --printf="%s" "$SCRIPT_DIR/$DMG_NAME" 2>/dev/null || echo "unknown")

echo ""
echo "=========================================="
success "Build Complete!"
echo "=========================================="
echo ""
echo "  Output: $SCRIPT_DIR/$DMG_NAME"
echo "  App size: $APP_SIZE"
echo "  DMG size: $DMG_SIZE"
echo "  DMG size (bytes): $DMG_BYTES"
echo ""
echo "To release an update:"
echo "  1. Update appcast.xml with the new version, signature, and file size"
echo "  2. Create a GitHub Release tagged vX.X and upload $DMG_NAME"
echo "  3. Commit and push appcast.xml"
echo ""
