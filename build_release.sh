#!/bin/bash
#
# Rayee Build Script
#
# This script builds Rayee into a distributable .dmg file.
# It bundles both the Swift app and the Python transcription server.
#
# Prerequisites:
#   - Xcode and command line tools
#   - Python 3.11+ with virtual environment
#   - PyInstaller (pip install pyinstaller)
#
# Usage:
#   ./build_release.sh
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

# Print colored status messages
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Configuration
APP_NAME="Rayee"
PYTHON_DIR="$SCRIPT_DIR/python"
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

# Check for Xcode
if ! command -v xcodebuild &> /dev/null; then
    error "Xcode command line tools not found. Install with: xcode-select --install"
fi

# Check for Python
if ! command -v python3 &> /dev/null; then
    error "Python 3 not found. Install Python 3.11 or later."
fi

# Check Python version
PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
info "Found Python $PYTHON_VERSION"

success "Prerequisites check passed"
echo ""

# ==========================================
# Step 1: Build Python Server with PyInstaller
# ==========================================
info "Step 1: Building Python server with PyInstaller..."

cd "$PYTHON_DIR"

# Activate virtual environment if it exists
if [ -d "venv" ]; then
    info "Activating virtual environment..."
    source venv/bin/activate
else
    warn "No virtual environment found. Creating one..."
    python3 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip
    pip install -r requirements.txt
fi

# Install PyInstaller if not present
if ! python -c "import PyInstaller" &> /dev/null; then
    info "Installing PyInstaller..."
    pip install pyinstaller
fi

# Clean previous builds
rm -rf dist build

# Run PyInstaller
info "Running PyInstaller (this may take several minutes)..."
pyinstaller RayeeServer.spec --noconfirm

# Verify the build
if [ ! -f "dist/RayeeServer/RayeeServer" ]; then
    error "PyInstaller build failed - RayeeServer executable not found"
fi

success "Python server built successfully"
echo ""

# ==========================================
# Step 2: Build Swift App with Xcode
# ==========================================
info "Step 2: Building Swift app with Xcode..."

cd "$SWIFT_DIR"

# Clean previous builds
xcodebuild clean -project Rayee.xcodeproj -scheme Rayee -configuration Release 2>/dev/null || true

# Build the app
info "Building Rayee.app (Release configuration)..."
xcodebuild build \
    -project Rayee.xcodeproj \
    -scheme Rayee \
    -configuration Release \
    -derivedDataPath build \
    CODE_SIGN_IDENTITY="-" \
    ONLY_ACTIVE_ARCH=NO

# Find the built app
APP_PATH="$SWIFT_DIR/build/Build/Products/Release/Rayee.app"
if [ ! -d "$APP_PATH" ]; then
    error "Xcode build failed - Rayee.app not found at $APP_PATH"
fi

success "Swift app built successfully"
echo ""

# ==========================================
# Step 3: Bundle Python Server into App
# ==========================================
info "Step 3: Bundling Python server into app..."

# Create Resources directory if needed
RESOURCES_DIR="$APP_PATH/Contents/Resources"
mkdir -p "$RESOURCES_DIR"

# Copy the Python server
PYTHON_SERVER_SRC="$PYTHON_DIR/dist/RayeeServer"
PYTHON_SERVER_DST="$RESOURCES_DIR/RayeeServer"

info "Copying Python server (~600MB, please wait)..."
rm -rf "$PYTHON_SERVER_DST"
cp -R "$PYTHON_SERVER_SRC" "$PYTHON_SERVER_DST"

# Make the executable... executable
chmod +x "$PYTHON_SERVER_DST/RayeeServer"

# Verify the copy
if [ ! -f "$PYTHON_SERVER_DST/RayeeServer" ]; then
    error "Failed to copy Python server into app bundle"
fi

success "Python server bundled successfully"
echo ""

# Re-sign the app after modifying the bundle
# Adding the Python server invalidates Xcode's original signature
info "Re-signing app bundle..."
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
success "App re-signed successfully"
echo ""

# ==========================================
# Step 4: Create DMG
# ==========================================
info "Step 4: Creating DMG..."

cd "$SCRIPT_DIR"

# Clean up any existing build artifacts
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Copy the app to build directory
cp -R "$APP_PATH" "$BUILD_DIR/"

# Remove old DMG if exists
rm -f "$DMG_NAME"

# Create the DMG
info "Creating disk image..."

# Create a temporary DMG for packaging
TEMP_DMG="$BUILD_DIR/temp.dmg"

# Create a folder with the app and a symlink to Applications
STAGING_DIR="$BUILD_DIR/staging"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# Create the DMG
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_NAME"

# Calculate sizes
APP_SIZE=$(du -sh "$APP_PATH" | cut -f1)
DMG_SIZE=$(du -sh "$DMG_NAME" | cut -f1)

# Clean up
rm -rf "$BUILD_DIR"

echo ""
echo "=========================================="
success "Build Complete!"
echo "=========================================="
echo ""
echo "  Output: $SCRIPT_DIR/$DMG_NAME"
echo "  App size: $APP_SIZE"
echo "  DMG size: $DMG_SIZE"
echo ""
echo "To install:"
echo "  1. Open $DMG_NAME"
echo "  2. Drag Rayee to Applications"
echo "  3. Launch from Applications (first launch may ask for permissions)"
echo ""

# Deactivate virtual environment
deactivate 2>/dev/null || true
