#!/bin/bash

# Build script for mtoc Flatpak

set -e

echo "Building mtoc Flatpak..."

# Install Flatpak builder if not present
if ! command -v flatpak-builder &> /dev/null; then
    echo "flatpak-builder not found. Please install it with:"
    echo "  sudo apt install flatpak-builder  # Debian/Ubuntu"
    echo "  sudo dnf install flatpak-builder  # Fedora"
    exit 1
fi

# Add Flathub repository if not present
if ! flatpak remote-list | grep -q flathub; then
    echo "Adding Flathub repository..."
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
fi

# Install KDE runtime if not present
echo "Checking for KDE runtime..."
flatpak install -y flathub org.kde.Platform//6.9 org.kde.Sdk//6.9 || true

# Clean previous builds
rm -rf .flatpak-builder repo

# Build the Flatpak
echo "Building Flatpak..."
flatpak-builder --force-clean build-dir org._3fz.mtoc.yml

# Build a local repository
echo "Creating local repository..."
flatpak-builder --repo=repo --force-clean build-dir org._3fz.mtoc.yml

# Install the Flatpak locally for testing
echo "Installing Flatpak locally..."
flatpak --user remote-add --if-not-exists mtoc-local repo --no-gpg-verify
flatpak --user install -y mtoc-local org._3fz.mtoc || flatpak --user install -y --reinstall mtoc-local org._3fz.mtoc

echo "Build complete! You can run the app with:"
echo "  flatpak run org._3fz.mtoc"
echo ""
echo "To create a single-file bundle for distribution:"
echo "  flatpak build-bundle repo mtoc.flatpak org._3fz.mtoc"