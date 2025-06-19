# Flatpak Changes for mtoc

This document describes the changes made to prepare mtoc for Flatpak distribution while maintaining compatibility with other package managers.

## Code Changes

### 1. Fixed Hardcoded Debug Log Paths

**File**: `src/backend/playback/mediaplayer.cpp`

**Issue**: The file contained hardcoded paths to `"debug_log.txt"` which would write to the current working directory. In a Flatpak sandbox, this could fail or write to unexpected locations.

**Solution**: 
- Added `#include <QStandardPaths>` and `#include <QDir>`
- Created a static helper function `getDebugLogPath()` that uses `QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)`
- Replaced all instances of `QFile debugFile("debug_log.txt")` with `QFile debugFile(getDebugLogPath())`
- Added the helper function declaration to `mediaplayer.h`

**Note**: The main.cpp file already used the correct XDG-compliant path for debug logging.

## Path Locations

### Native Installation
- Config: `~/.config/mtoc/`
- Data/Database: `~/.local/share/mtoc/`
- Cache: `~/.cache/mtoc/`

### Flatpak Installation
- Config: `~/.var/app/org._3fz.mtoc/config/mtoc/`
- Data/Database: `~/.var/app/org._3fz.mtoc/data/mtoc/`
- Cache: `~/.var/app/org._3fz.mtoc/cache/mtoc/`

## Flatpak Manifest

Created `org._3fz.mtoc.yml` with:

### Runtime
- KDE Platform 6.7 (for Qt6 support)
- KDE SDK 6.7

### Permissions
- `--socket=wayland` and `--socket=fallback-x11` - Display access
- `--socket=pulseaudio` - Audio playback
- `--filesystem=xdg-music:ro` - Read-only access to Music directory
- `--filesystem=host` - Full filesystem access for file chooser portal
- `--talk-name=org.mpris.MediaPlayer2.mtoc` - MPRIS integration
- `--own-name=org.mpris.MediaPlayer2.mtoc` - MPRIS service name
- `--talk-name=org.freedesktop.portal.FileChooser` - File dialog portal

### Dependencies
- TagLib 2.0.2 - Built from source within Flatpak

## Build Script

Created `build-flatpak.sh` for easy building and testing:
```bash
./build-flatpak.sh
```

This script:
1. Builds the Flatpak
2. Installs it locally for testing
3. Provides instructions for running and distribution

## Testing

To test the Flatpak build:

1. Install Flatpak and the KDE runtime:
   ```bash
   flatpak install flathub org.kde.Platform//6.7 org.kde.Sdk//6.7
   ```

2. Build and install:
   ```bash
   # For minimal build (no desktop integration):
   ./build-flatpak-minimal.sh
   
   # For full build with desktop integration (works around appstream issues):
   ./build-flatpak-nocompose.sh
   ```

3. Run the application:
   ```bash
   flatpak run org._3fz.mtoc
   # or use the helper script:
   ./run-flatpak.sh
   ```

4. Verify functionality:
   - Database creation in sandboxed location
   - Music directory access via file chooser
   - Audio playback
   - MPRIS integration

## Additional Files Created

1. **org._3fz.mtoc.metainfo.xml** - AppStream metadata file required for Flatpak distribution
   - Provides application description, screenshots placeholder, and release information
   - Uses the Flatpak app-id naming convention

## Notes

- The application already used Qt's standard file dialogs which automatically integrate with the portal system
- File access uses the portal system, so users can grant access to any directory they choose
- The `--filesystem=host` permission allows the file chooser to see the entire filesystem, but actual access is still controlled by the portal
- Debug logs are now properly written to the XDG data directory within the sandbox
- The executable name is `mtoc_app` as defined in CMakeLists.txt
- Desktop and icon files are installed with the Flatpak app-id prefix (org._3fz.mtoc)