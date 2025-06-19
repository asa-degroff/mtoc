#!/bin/bash
# Clean build script for mtoc Flatpak with better error handling

set -e

echo "Building mtoc Flatpak with clean environment..."

# Function to clean up on error
cleanup_on_error() {
    echo "Build failed. Cleaning up..."
    rm -rf build-dir .flatpak-builder
    exit 1
}

# Set trap for errors
trap cleanup_on_error ERR

# Check if flatpak is already installed
if flatpak list --app | grep -q "org._3fz.mtoc"; then
    echo "Warning: org._3fz.mtoc is already installed."
    echo "Uninstalling existing installation..."
    flatpak uninstall --user org._3fz.mtoc -y || true
fi

# Clean previous builds completely
echo "Cleaning previous build artifacts..."
rm -rf build-dir .flatpak-builder
rm -rf ~/.cache/flatpak-builder/build/mtoc*

# Ensure we have a clean state
flatpak repair --user 2>/dev/null || true

# Build the Flatpak with verbose output for debugging
echo "Building application..."
flatpak-builder --verbose --force-clean --disable-rofiles-fuse build-dir org._3fz.mtoc.yml

# Install it locally for testing
echo "Installing Flatpak locally for testing..."
flatpak-builder --user --install --force-clean build-dir org._3fz.mtoc.yml

echo "Build complete!"
echo ""
echo "To run the installed Flatpak:"
echo "  flatpak run org._3fz.mtoc"
echo ""
echo "To export to a repository:"
echo "  flatpak-builder --repo=repo --force-clean build-dir org._3fz.mtoc.yml"
echo ""
echo "To create a single-file bundle:"
echo "  flatpak build-bundle repo mtoc.flatpak org._3fz.mtoc"