#!/bin/bash

# This script is disabled since we're now loading the dylib directly from lib/native
# Exit successfully without doing anything
echo "This script is disabled. Library is now loaded directly from lib/native directory."
exit 0

# Exit on error
set -e

# Get the absolute path to the project root (parent of current directory)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"

# Set paths
APP_BUNDLE_DIR="$PROJECT_ROOT/build/macos/Build/Products/Debug/spikerbox_architecture.app"
FRAMEWORKS_DIR="$APP_BUNDLE_DIR/Contents/Frameworks"
FRAMEWORK_NAME="processing_plugin.framework"
FRAMEWORK_DIR="$FRAMEWORKS_DIR/$FRAMEWORK_NAME"

echo "Creating framework at: $FRAMEWORK_DIR"

# Create the framework directory structure
mkdir -p "$FRAMEWORK_DIR/Versions/A"
mkdir -p "$FRAMEWORK_DIR/Headers"
mkdir -p "$FRAMEWORK_DIR/Resources"

# Copy the dylib to the framework
cp "build/libprocessing.dylib" "$FRAMEWORK_DIR/Versions/A/processing_plugin"

# Create symbolic links
cd "$FRAMEWORK_DIR"
ln -sf "Versions/A/processing_plugin" "processing_plugin"
ln -sf "Versions/A" "Headers"
ln -sf "Versions/A" "Resources"
cd "Versions"
ln -sf "A" "Current"

echo "Library copied to Flutter app bundle at: $FRAMEWORK_DIR/processing_plugin"

# Set the correct install name
install_name_tool -id "@rpath/$FRAMEWORK_NAME/processing_plugin" "$FRAMEWORK_DIR/processing_plugin"

# Verify the library exists and show its details
if [ -f "$FRAMEWORK_DIR/processing_plugin" ]; then
    echo "Library exists at target location"
    echo "Library details:"
    otool -L "$FRAMEWORK_DIR/processing_plugin"
else
    echo "Error: Library was not copied correctly"
    exit 1
fi 