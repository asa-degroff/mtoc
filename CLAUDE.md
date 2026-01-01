# CLAUDE.md - AI Assistant Guide for mtoc

This document provides comprehensive guidance for AI assistants working with the mtoc codebase.

## Project Overview

**mtoc** (music table of contents) is a visually-rich music player and library browser for Linux that emphasizes smooth, continuous browsing experiences with album artwork at the forefront.

- **Language**: C++17 with Qt6/QML
- **Version**: 2.4.1
- **License**: GPL v3
- **Platform**: Linux (X11/Wayland)
- **Repository**: https://github.com/asa-degroff/mtoc

### Core Technologies

- **UI Framework**: Qt6 (Core, Quick, Qml, Multimedia, DBus, Concurrent, Widgets, Sql)
- **Audio Engine**: GStreamer 1.0 (gapless playback, ReplayGain support)
- **Metadata**: TagLib 2.0
- **Database**: SQLite3
- **Build System**: CMake 3.16+
- **Packaging**: Flatpak (Flathub), RPM (Fedora COPR)

## Codebase Structure

```
mtoc/
├── src/
│   ├── main.cpp                      # Application entry point, QML registration
│   ├── backend/                      # C++ backend (38 files, 8 subsystems)
│   │   ├── library/                  # Music library management (8 files)
│   │   │   ├── librarymanager.{h,cpp}      # Main library controller
│   │   │   ├── albumartmanager.{h,cpp}     # Album art extraction/caching
│   │   │   ├── albumartimageprovider.{h,cpp} # QML image provider
│   │   │   ├── track.{h,cpp}               # Track data model
│   │   │   ├── album.{h,cpp}               # Album data model
│   │   │   ├── artist.{h,cpp}              # Artist data model
│   │   │   ├── trackmodel.{h,cpp}          # Track list model
│   │   │   └── albummodel.{h,cpp}          # Album list model
│   │   ├── database/                 # SQLite persistence (2 files)
│   │   │   └── databasemanager.{h,cpp}     # Database operations
│   │   ├── playback/                 # Audio playback (4 files)
│   │   │   ├── mediaplayer.{h,cpp}         # Playback controller
│   │   │   └── audioengine.{h,cpp}         # GStreamer integration
│   │   ├── playlist/                 # Playlist management (6 files)
│   │   │   ├── playlistmanager.{h,cpp}     # M3U playlist handling
│   │   │   ├── VirtualTrackData.h          # Lightweight track data
│   │   │   ├── VirtualPlaylist.{h,cpp}     # Core playlist with buffering
│   │   │   └── VirtualPlaylistModel.{h,cpp} # Paginated playlist model
│   │   ├── settings/                 # Configuration (2 files)
│   │   │   └── settingsmanager.{h,cpp}     # App settings persistence
│   │   ├── system/                   # OS integration (2 files)
│   │   │   └── mprismanager.{h,cpp}        # MPRIS2 D-Bus integration
│   │   ├── utility/                  # Metadata extraction (2 files)
│   │   │   └── metadataextractor.{h,cpp}   # TagLib wrapper
│   │   └── systeminfo.{h,cpp}        # App metadata provider
│   └── qml/                          # QML frontend (28 files)
│       ├── Main.qml                  # Main window entry point
│       ├── Theme.qml                 # Centralized theming singleton
│       ├── Constants.qml             # App-wide constants
│       ├── Styles.qml                # Style utilities
│       ├── Views/                    # Full-screen panes (6 files)
│       │   ├── LibraryPane.qml              # Artist/album browser
│       │   ├── NowPlayingPane.qml           # Current track display
│       │   ├── PlaylistView.qml             # Playlist management
│       │   ├── MiniPlayerWindow.qml         # Standalone mini player
│       │   ├── SettingsWindow.qml           # App settings
│       │   └── LibraryEditorWindow.qml      # Library configuration
│       └── Components/               # Reusable widgets (19 files)
│           ├── PlaybackControls.qml         # Play/pause/skip controls
│           ├── CompactNowPlayingBar.qml     # Compact playback bar
│           ├── QueueListView.qml            # Queue display
│           ├── QueuePopup.qml               # Queue popup window
│           ├── QueueActionDialog.qml        # Queue action dialogs
│           ├── HorizontalAlbumBrowser.qml   # Album carousel
│           ├── ThumbnailGridDelegate.qml    # Album thumbnail grid
│           ├── SearchBar.qml                # Search functionality
│           ├── BlurredBackground.qml        # Visual effects
│           ├── AlbumArtPopup.qml            # Enlarged album art
│           ├── LyricsView.qml               # Lyrics display
│           ├── LyricsPopup.qml              # Lyrics popup window
│           ├── ResizeHandler.qml            # Window resizing
│           ├── StyledMenu.qml               # Custom menu
│           ├── StyledMenuItem.qml           # Menu item
│           └── StyledMenuSeparator.qml      # Menu separator
├── resources/                        # Assets (66 files)
│   ├── icons/                        # SVG/PNG icons (~50 files)
│   └── banner/                       # Marketing materials
├── CMakeLists.txt                    # Build configuration
├── app.qrc                           # Qt resource file
├── mtoc.spec                         # RPM packaging spec
├── org._3fz.mtoc.yml                 # Flatpak manifest
├── org._3fz.mtoc.metainfo.xml        # AppStream metadata
├── README.md                         # User documentation
├── ARCHITECTURE.md                   # Architecture overview
└── CHANGELOG.md                      # Version history
```

## Architecture Overview

mtoc follows a **Model-View-Controller (MVC)** architecture with clear separation between C++ backend logic and QML frontend presentation.

### Design Patterns

1. **Singleton Pattern**: All manager classes (LibraryManager, MediaPlayer, PlaylistManager, SettingsManager) are singletons exposed to QML
2. **Model-View Pattern**: Qt's QAbstractListModel for efficient data display with automatic UI updates
3. **Observer Pattern**: Qt signals/slots for loose coupling between components
4. **Virtual Proxy Pattern**: VirtualPlaylistModel implements lazy loading for large playlists (thousands of tracks)
5. **Image Provider Pattern**: Custom AlbumArtImageProvider for efficient album art loading in QML

### Data Flow

**Library Scanning**:
```
User Action → LibraryManager → MetadataExtractor (TagLib) → DatabaseManager (SQLite) → Track/Album/Artist Models → QML UI
```

**Playback**:
```
User Action → QML UI → MediaPlayer → AudioEngine (GStreamer) → Audio Output
                     ↓
              Track/Album Models
```

**Search**:
```
SearchBar (QML) → LibraryManager → DatabaseManager → Filtered Models → UI Update
```

### QML/C++ Integration

C++ types and singletons are registered in `src/main.cpp`:

```cpp
// Singletons accessible in QML as "LibraryManager", "MediaPlayer", etc.
qmlRegisterSingletonInstance("Mtoc.Backend", 1, 0, "SystemInfo", systemInfo);
qmlRegisterSingletonInstance("Mtoc.Backend", 1, 0, "LibraryManager", libraryManager);
qmlRegisterSingletonInstance("Mtoc.Backend", 1, 0, "MediaPlayer", mediaPlayer);
qmlRegisterSingletonInstance("Mtoc.Backend", 1, 0, "PlaylistManager", playlistManager);
qmlRegisterSingletonInstance("Mtoc.Backend", 1, 0, "SettingsManager", settingsManager);

// Custom image provider for album art
engine.addImageProvider("albumart", new AlbumArtImageProvider(libraryManager));
```

**Usage in QML**:
```qml
import Mtoc.Backend 1.0

// Direct singleton access
LibraryManager.startScan()
MediaPlayer.play()

// Album art via image provider
Image { source: "image://albumart/artist/album/thumbnail" }
```

## Coding Conventions

### C++ Guidelines

1. **Namespace**: All backend code is in `namespace Mtoc {}`
2. **Header Guards**: Traditional `#ifndef CLASSNAME_H` / `#define CLASSNAME_H` / `#endif`
3. **Class Structure**:
   - Q_OBJECT macro for QObject-derived classes
   - Q_PROPERTY declarations for QML-exposed properties
   - Public, signals, public slots, private sections in that order
   - Q_INVOKABLE for methods callable from QML
4. **Naming Conventions**:
   - Classes: PascalCase (e.g., `LibraryManager`)
   - Methods: camelCase (e.g., `startScan()`)
   - Properties: camelCase (e.g., `musicFolders`)
   - Private members: m_ prefix (e.g., `m_scanning`)
   - Signals: past tense (e.g., `scanningChanged`)
5. **File Naming**: Lowercase with .h/.cpp extensions matching class name
6. **Include Order**:
   - Qt headers first (grouped by module)
   - Project headers second (relative paths from src/)
7. **Properties**:
   - Use Q_PROPERTY with READ, WRITE (optional), NOTIFY
   - Provide getter, setter (if writable), and changed signal

### QML Guidelines

1. **File Naming**: PascalCase matching component name
2. **Component Structure**:
   - Property declarations at top
   - Signal declarations
   - Component hierarchy
   - JavaScript functions at bottom
3. **Imports**:
   - Qt modules first
   - `import Mtoc.Backend 1.0` for C++ types
4. **Theme Usage**: Access `Theme` singleton for colors, fonts, spacing
5. **Styling**: Use Theme.qml for centralized theme management

### Performance Best Practices

1. **Caching Strategy**:
   - Cache data generously to reduce disk access
   - LibraryManager caches tracks, albums, artists in memory
   - AlbumArtManager uses adaptive QPixmapCache (5-10% of RAM, 128MB-1GB)
   - Cache scaling based on thumbnail size settings
2. **Lazy Loading**:
   - VirtualPlaylistModel loads tracks on-demand with configurable buffer sizes
   - Async image loading for album art
3. **Multi-threading**:
   - Use QtConcurrent for CPU-intensive tasks (library scanning, metadata extraction)
   - Background album art processing
   - Async playlist loading with progress reporting
4. **Database**:
   - Batch operations for efficiency
   - Proper indexing for fast searches
5. **Memory Management**:
   - Careful QML object lifecycle management
   - Proper parent-child relationships for automatic cleanup
   - Clear ownership semantics

## Build System

### CMake Configuration

- **CMAKE_AUTOMOC**: Enabled for Qt Meta-Object Compiler
- **CMAKE_AUTORCC**: Enabled for Qt Resource Compiler
- **CMAKE_CXX_STANDARD**: C++17 required
- **Debug Output**: qDebug enabled even in release builds (`-DQT_MESSAGELOGCONTEXT -DQT_DEBUG`)

### Dependencies (pkg-config)

- TagLib (taglib)
- GStreamer (gstreamer-1.0)

### Qt6 Modules

Qt6::Core, Qt6::Quick, Qt6::QuickEffects, Qt6::Qml, Qt6::Multimedia, Qt6::DBus, Qt6::Concurrent, Qt6::Widgets, Qt6::Sql

### Build Commands

```bash
# Configure
mkdir build && cd build
cmake ..

# Build
cmake --build .

# Run locally (without installation)
./mtoc_app

# Install system-wide
sudo cmake --build . --target install
```

### Install Targets

- Binary: `${CMAKE_INSTALL_BINDIR}/mtoc_app`
- Desktop file: `/share/applications/mtoc.desktop`
- Icons: Multiple sizes in `/share/icons/hicolor/` (48x48, 64x64, 128x128, 256x256, 512x512)
- Metainfo: `/share/metainfo/org._3fz.mtoc.metainfo.xml`

## Development Workflows

### Adding New Features

1. **Backend Changes**:
   - Add new classes in appropriate `src/backend/` subdirectory
   - Update `CMakeLists.txt` to include new .cpp files
   - Register types/singletons in `src/main.cpp` if needed for QML
   - Follow Q_PROPERTY pattern for QML-exposed properties
   - Emit signals for property changes to update UI

2. **Frontend Changes**:
   - Create new QML files in `src/qml/Views/` or `src/qml/Components/`
   - Update `CMakeLists.txt` QML_FILES section
   - Use Theme singleton for consistent styling
   - Follow existing component patterns

3. **Database Changes**:
   - Modify schema in DatabaseManager
   - Implement migration logic for existing databases
   - Update relevant data models

### Adding Dependencies

1. Update CMakeLists.txt with `find_package()` or `pkg_check_modules()`
2. Add to `target_link_libraries()`
3. Update README.md with installation instructions for all supported distros
4. Update Flatpak manifest (`org._3fz.mtoc.yml`)
5. Update RPM spec (`mtoc.spec`)

### Git Workflow

- **Main branch**: `main` (or `master`)
- **Feature branches**: Use descriptive names
- **Commit messages**: Follow conventional commit format, focus on "why" not "what"
- **Versioning**: Semantic versioning (MAJOR.MINOR.PATCH)
- **Changelog**: Update CHANGELOG.md for all user-facing changes
- **Release process**: Uses Tito for RPM packaging (`.tito/` directory)

### Testing

**Note**: No automated test suite currently exists. Testing is manual.

**Manual Testing Checklist**:
- Library scanning with various audio formats (MP3, FLAC, OGG, M4A, Opus)
- Playback controls (play, pause, skip, seek)
- Gapless playback transitions
- ReplayGain volume normalization
- Lyrics display (synced and unsynced)
- Queue management (add, remove, reorder)
- Playlist creation and editing
- Search functionality
- Mini player layouts
- State persistence across restarts
- MPRIS integration with desktop environment
- System tray functionality

## Key Components Reference

### LibraryManager (src/backend/library/librarymanager.h)

**Purpose**: Central controller for music library management

**Key Methods**:
- `startScan()`: Full library scan
- `refreshLibrary()`: Smart incremental scan
- `cancelScan()`: Cancel ongoing scan
- `resetLibrary()`: Clear all library data
- `allTracksModel()`: Get all tracks as TrackModel
- `allAlbumsModel()`: Get all albums as AlbumModel
- `tracksForAlbum()`: Get tracks for specific album
- `albumsForArtist()`: Get albums for specific artist
- `searchLibrary()`: Search tracks/albums/artists

**Key Properties**:
- `scanning` (bool): Scan in progress
- `scanProgress` (int): Scan completion percentage
- `trackCount`, `albumCount`, `artistCount`: Library statistics
- `musicFolders`: List of scanned directories
- `watchFileChanges`: File watcher enabled

**Caching Behavior**:
- Caches all tracks, albums, artists in memory
- Uses QMap for fast lookups
- Invalidates cache on library changes

### MediaPlayer (src/backend/playback/mediaplayer.h)

**Purpose**: Playback control and queue management

**Key Methods**:
- `play()`, `pause()`, `stop()`
- `next()`, `previous()`
- `seek(qint64 position)`
- `setVolume(int volume)`
- `enqueueTrack()`, `enqueueAlbum()`, `enqueuePlaylist()`
- `clearQueue()`, `removeFromQueue()`
- `setShuffleMode()`, `setRepeatMode()`

**Key Properties**:
- `playing` (bool): Playback state
- `currentTrack` (Track*): Current track
- `position` (qint64): Playback position in milliseconds
- `duration` (qint64): Track duration
- `queue` (QVariantList): Current queue
- `shuffleEnabled`, `repeatMode`

**Features**:
- Gapless playback with next track preloading
- ReplayGain support (album and track modes)
- State persistence and restoration
- Integration with AudioEngine for actual playback

### AudioEngine (src/backend/playback/audioengine.h)

**Purpose**: Low-level GStreamer integration

**Features**:
- Gapless playback pipeline
- ReplayGain volume normalization
- Preamplification and fallback gain
- Async track preloading
- Seamless transitions

### DatabaseManager (src/backend/database/databasemanager.h)

**Purpose**: SQLite database operations

**Schema** (approximate):
- `tracks`: Track metadata (path, title, artist, album, duration, lyrics, etc.)
- `albums`: Album metadata with album art references
- `artists`: Artist metadata
- `playlists`: M3U playlist metadata
- `lyrics`: External lyrics file associations

**Operations**:
- Batch insert/update for performance
- Efficient search queries with LIKE
- Transaction support for atomic operations

### PlaylistManager (src/backend/playlist/playlistmanager.h)

**Purpose**: M3U playlist file management

**Features**:
- Load/save M3U playlists
- Multi-directory playlist support
- Virtual "All Songs" playlist
- Playlist CRUD operations

### VirtualPlaylistModel (src/backend/playlist/VirtualPlaylistModel.h)

**Purpose**: Lazy-loading playlist model for large playlists

**Features**:
- Paginated loading (loads tracks on-demand)
- Configurable buffer sizes
- Shuffle support with efficient index mapping
- Async loading with progress reporting
- Handles playlists with thousands of tracks efficiently

### AlbumArtManager (src/backend/library/albumartmanager.h)

**Purpose**: Album art extraction and caching

**Features**:
- Extracts embedded artwork from audio files
- Dynamic QPixmapCache sizing (5-10% of RAM, 128MB-1GB)
- Cache scaling based on thumbnail size preferences
- Generates thumbnails at multiple sizes
- Async processing with Qt Concurrent

### MprisManager (src/backend/system/mprismanager.h)

**Purpose**: Linux desktop integration via MPRIS2 D-Bus

**Features**:
- Media keys support
- Desktop environment media controls
- System tray integration
- Now playing notifications

## Common Tasks

### Adding a New Property to a C++ Class

1. Add private member variable: `bool m_myProperty;`
2. Add Q_PROPERTY declaration:
   ```cpp
   Q_PROPERTY(bool myProperty READ myProperty WRITE setMyProperty NOTIFY myPropertyChanged)
   ```
3. Add getter: `bool myProperty() const { return m_myProperty; }`
4. Add setter:
   ```cpp
   void setMyProperty(bool value) {
       if (m_myProperty != value) {
           m_myProperty = value;
           emit myPropertyChanged();
       }
   }
   ```
5. Add signal: `void myPropertyChanged();`
6. Access in QML: `LibraryManager.myProperty`

### Adding a New QML Component

1. Create file in `src/qml/Components/MyComponent.qml`
2. Add to `CMakeLists.txt` QML_FILES section
3. Import and use: `import "Components"; MyComponent {}`

### Adding a New Manager Class

1. Create header/source in appropriate `src/backend/` subdirectory
2. Inherit from QObject, add Q_OBJECT macro
3. Implement singleton pattern (static instance, getInstance() method)
4. Add files to `CMakeLists.txt` PROJECT_SOURCES
5. Register in `src/main.cpp`:
   ```cpp
   qmlRegisterSingletonInstance("Mtoc.Backend", 1, 0, "MyManager", MyManager::getInstance());
   ```

### Modifying Database Schema

1. Update DatabaseManager with new schema
2. Implement migration logic in DatabaseManager::openDatabase()
3. Test with existing database files
4. Update relevant models and data access methods

### Adding Support for New Audio Format

1. Verify TagLib supports the format
2. Add file extension to MetadataExtractor
3. Add to supported formats list in README.md
4. Test metadata extraction and playback

## Packaging & Release

### Version Bumping

1. Update `project(mtoc VERSION x.y.z ...)` in CMakeLists.txt
2. Update CHANGELOG.md with release notes
3. Update AppStream metadata in org._3fz.mtoc.metainfo.xml
4. Commit changes
5. Use Tito for RPM packaging: `tito tag && tito build --rpm`

### Flatpak

- Manifest: `org._3fz.mtoc.yml`
- Build script: `build-flatpak.sh`
- Published on Flathub as `org._3fz.mtoc`

### RPM (Fedora COPR)

- Spec file: `mtoc.spec`
- COPR repo: `3fz-asa/mtoc`
- Uses Tito for release management (`.tito/` directory)

## Important Notes for AI Assistants

### Design Philosophy

1. **Visual Appeal**: Prioritize smooth animations and visual continuity
2. **Performance**: Cache aggressively, load lazily, process asynchronously
3. **User Experience**: Continuous browsing, minimal interruptions
4. **Album-Centric**: Designed for well-organized album-based libraries

### Code Modification Guidelines

1. **Never break existing functionality**: Test thoroughly before committing
2. **Follow Qt best practices**: Use signals/slots, proper memory management
3. **Maintain QML/C++ separation**: Business logic in C++, presentation in QML
4. **Update documentation**: Modify README.md, ARCHITECTURE.md when adding features
5. **Consider performance**: mtoc must handle libraries with thousands of albums smoothly
6. **Respect singleton pattern**: Don't create multiple instances of manager classes
7. **Emit property change signals**: Always emit when property values change
8. **Use Qt Concurrent for heavy tasks**: Don't block the UI thread
9. **Handle errors gracefully**: Provide user feedback for failures
10. **Test with real music libraries**: Use various formats and library sizes

### Security Considerations

1. **Input validation**: Validate all file paths and user inputs
2. **SQL injection**: Use parameterized queries (DatabaseManager handles this)
3. **File system access**: Respect Flatpak sandbox restrictions
4. **D-Bus security**: MPRIS implementation follows spec

### Platform-Specific Notes

1. **Flatpak**: Use portal-friendly paths, handle XDG directories
2. **Wayland**: Always-on-top windows may not work (limitation of Wayland protocol)
3. **X11**: Full window management support including always-on-top
4. **Icon themes**: Support both light and dark system themes

### Performance Targets

- **Library size**: Should handle 10,000+ albums smoothly
- **Scan speed**: Metadata extraction should be multi-threaded
- **Memory usage**: Typical usage under ~350MB
- **Startup time**: Fast startup with state restoration
- **UI responsiveness**: 60 FPS animations, no blocking operations

### Testing Recommendations

Always test:
1. Large libraries (1000+ albums)
2. All supported audio formats
3. Both light and dark themes
4. Both wide and compact layouts
5. State persistence (restart the app)
6. MPRIS integration (media keys)
7. Gapless playback between tracks
8. ReplayGain with various gain values
9. Lyrics display (synced and unsynced)
10. File watcher functionality

### Common Pitfalls

1. **Forgetting to emit signals**: QML won't update without property change signals
2. **Blocking the UI thread**: Use QtConcurrent for slow operations
3. **Memory leaks**: Ensure proper parent-child relationships in Qt objects
4. **QML object lifetime**: Don't store raw pointers to QML-created objects in C++
5. **Database locking**: Use transactions properly, avoid long-running queries
6. **Cache invalidation**: Clear caches when underlying data changes
7. **File path encoding**: Handle Unicode paths correctly
8. **Gapless transitions**: Don't interrupt the audio pipeline unnecessarily

### Resources

- **Qt Documentation**: https://doc.qt.io/qt-6/
- **QML Documentation**: https://doc.qt.io/qt-6/qmlapplications.html
- **GStreamer Documentation**: https://gstreamer.freedesktop.org/documentation/
- **TagLib Documentation**: https://taglib.org/api/
- **MPRIS2 Specification**: https://specifications.freedesktop.org/mpris-spec/latest/

---

*Last Updated: 2025-12-31*
*mtoc Version: 2.5.2*
