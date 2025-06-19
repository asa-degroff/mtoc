#!/bin/bash
# Build script for mtoc Flatpak

set -e

echo "Building mtoc Flatpak..."

# Clean previous builds
rm -rf build-dir .flatpak-builder

# Build the Flatpak
echo "Building application..."
flatpak-builder --force-clean build-dir org._3fz.mtoc.yml || {
    echo "Build failed. Trying without installation..."
    exit 1
}

# Install it locally for testing
echo "Installing Flatpak locally for testing..."
flatpak-builder --user --install --force-clean build-dir org._3fz.mtoc.yml || {
    echo "Installation failed. The app was built but not installed."
    echo "You can try running from the build directory."
    exit 1
}

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