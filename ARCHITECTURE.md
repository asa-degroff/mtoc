# mtoc Architecture Overview

## Introduction

mtoc is a modern music player and library management application built with Qt/QML, following a well-structured Model-View-Controller (MVC) architecture. The application uses C++ for the backend logic and QML for the user interface, providing a clean separation of concerns and efficient performance.

## Architecture Layers

### 1. Model Layer (Data Models)

The Model layer handles data representation and storage, located in `src/backend/`:

#### Core Data Models
- **Track** (`library/track.h`): Represents individual music tracks with metadata properties (title, artist, album, duration, lyrics, etc.)
- **Album** (`library/album.h`): Represents music albums with aggregated track information
- **Artist** (`library/artist.h`): Represents artists with associated albums and tracks
- **VirtualTrackData** (`playlist/VirtualTrackData.h`): Lightweight track representation for virtual playlists

#### List Models (Qt's QAbstractListModel)
- **TrackModel** (`library/trackmodel.h`): Manages collections of tracks with sorting capabilities
- **AlbumModel** (`library/albummodel.h`): Manages album collections with custom roles for QML binding
- **VirtualPlaylist** (`playlist/VirtualPlaylist.h`): Core playlist data management with buffering, shuffle support, and asynchronous loading
- **VirtualPlaylistModel** (`playlist/VirtualPlaylistModel.h`): Provides paginated loading for large playlists with lazy loading support, built on top of VirtualPlaylist

### 2. View Layer (User Interface)

The View layer is implemented entirely in QML, located in `src/qml/`:

#### Main Views (`Views/`)
- **LibraryPane**: Browse music library by artists and albums
- **NowPlayingPane**: Display current track with album art and controls
- **PlaylistView**: Manage and play saved playlists
- **MiniPlayerWindow**: Standalone mini player with multiple layout modes (vertical, horizontal, compact bar)
- **SettingsWindow**: Configure application settings
- **LibraryEditorWindow**: Edit library metadata

#### Reusable Components (`Components/`)
- **PlaybackControls**: Transport controls (play/pause/skip)
- **CompactNowPlayingBar**: Compact now playing bar for minimal UI
- **QueueListView**: Display and manage playback queue
- **QueuePopup**: Popup window for queue display
- **QueueHeader**: Header component for queue view
- **QueueActionDialog**: Dialog for queue-related actions
- **HorizontalAlbumBrowser**: Browse albums in a horizontal carousel
- **ThumbnailGridDelegate**: Grid view delegate for album thumbnails
- **SearchBar**: Search functionality
- **BlurredBackground**: Visual effects for album art backgrounds
- **AlbumArtPopup**: Popup window for enlarged album artwork
- **LyricsView**: Display synchronized or plain text lyrics
- **LyricsPopup**: Popup window for lyrics display
- **ResizeHandler**: Handle window resizing operations
- **StyledMenu**, **StyledMenuItem**, **StyledMenuSeparator**: Custom styled menu components

#### Utility QML Files
- **Theme.qml**: Centralized theme management singleton (colors, fonts, spacing)
- **Constants.qml**: Application-wide constants
- **Styles.qml**: Style definitions and utilities

### 3. Controller Layer (Business Logic)

The Controller layer manages application logic and coordinates between models and views:

#### Core Managers
- **LibraryManager** (`library/librarymanager.h`): 
  - Manages music library scanning and indexing
  - Handles database operations through DatabaseManager
  - Provides data access methods for UI components
  - Implements caching for performance optimization

- **MediaPlayer** (`playback/mediaplayer.h`):
  - Controls playback state and queue management
  - Integrates with AudioEngine for actual audio output
  - Manages shuffle/repeat modes
  - Handles state persistence and restoration

- **PlaylistManager** (`playlist/playlistmanager.h`):
  - Manages M3U playlist files
  - Handles playlist CRUD operations
  - Supports multiple playlist directories

- **SettingsManager** (`settings/settingsmanager.h`):
  - Manages application configuration
  - Provides persistent storage for user preferences

#### Supporting Controllers
- **AlbumArtManager** (`library/albumartmanager.h`): Extracts and caches album artwork
- **DatabaseManager** (`database/databasemanager.h`): SQLite database operations
- **MetadataExtractor** (`utility/metadataextractor.h`): Extract metadata from audio files using TagLib
- **MprisManager** (`system/mprismanager.h`): Linux desktop integration for media controls
- **SystemInfo** (`systeminfo.h`): Provides application metadata (name, version) for display in UI

### 4. Infrastructure Layer

#### Audio Engine
- **AudioEngine** (`playback/audioengine.h`): Low-level audio playback using platform APIs

#### Database
- SQLite database for persistent storage of library metadata
- Efficient indexing for fast searches and queries

#### Image Provider
- **AlbumArtImageProvider** (`library/albumartimageprovider.h`): Custom QML image provider for album artwork

## Component Interactions

### Data Flow

1. **Library Scanning**:
   ```
   User → LibraryManager → MetadataExtractor → DatabaseManager → Models
   ```

2. **Playback Flow**:
   ```
   User → QML UI → MediaPlayer → AudioEngine
                 ↓
            Track/Album Models
   ```

3. **Search Operations**:
   ```
   SearchBar → LibraryManager → DatabaseManager → Filtered Models → UI
   ```

### Key Design Patterns

1. **Singleton Pattern**: Used for managers (LibraryManager, PlaylistManager, SettingsManager) to ensure single instances and global access

2. **Model-View Pattern**: Qt's model/view architecture for efficient data display with automatic UI updates

3. **Observer Pattern**: Qt's signal/slot mechanism for loose coupling between components

4. **Virtual Proxy Pattern**: VirtualPlaylistModel implements lazy loading for large datasets

### QML/C++ Integration

The application registers C++ types and singletons with the QML engine in `main.cpp`:

#### Registered Types
```cpp
// Instantiable types for QML
qmlRegisterType<Mtoc::Track>("Mtoc.Backend", 1, 0, "Track");
qmlRegisterType<Mtoc::Album>("Mtoc.Backend", 1, 0, "Album");
```

#### Registered Singletons
```cpp
// C++ singletons exposed to QML
qmlRegisterSingletonInstance("Mtoc.Backend", 1, 0, "SystemInfo", systemInfo);
qmlRegisterSingletonInstance("Mtoc.Backend", 1, 0, "LibraryManager", libraryManager);
qmlRegisterSingletonInstance("Mtoc.Backend", 1, 0, "MetadataExtractor", metadataExtractor);
qmlRegisterSingletonInstance("Mtoc.Backend", 1, 0, "SettingsManager", settingsManager);
qmlRegisterSingletonInstance("Mtoc.Backend", 1, 0, "MediaPlayer", mediaPlayer);
qmlRegisterSingletonInstance("Mtoc.Backend", 1, 0, "PlaylistManager", playlistManager);

// QML singletons
qmlRegisterSingletonType(QUrl("qrc:/src/qml/Theme.qml"), "Mtoc.Backend", 1, 0, "Theme");
```

#### Image Provider
```cpp
// Custom image provider for album artwork
engine.addImageProvider("albumart", new Mtoc::AlbumArtImageProvider(libraryManager));
```

QML components import and use these types:
```qml
import Mtoc.Backend 1.0

// Direct access to C++ singletons
LibraryManager.startScan()
MediaPlayer.play()

// Album art image provider usage
Image { source: "image://albumart/artist/album/thumbnail" }
```

## Key Features Implementation

### Lyrics Support
- **Synchronized Lyrics**: Supports LRC format with timestamp-synced lyrics that highlight in real-time during playback
- **Plain Text Lyrics**: Fallback support for plain text lyrics (.txt files)
- **Database Integration**: Lyrics stored in database and associated with tracks
- **UI Components**: Dedicated LyricsView and LyricsPopup for displaying lyrics
- **Automatic Detection**: Lyrics files automatically detected and loaded from track directories

### Mini Player
- **Multiple Layouts**: Three distinct layout modes (vertical, horizontal, compact bar)
- **Always-on-Top**: Frameless window that stays on top of other applications
- **Position Persistence**: Remembers window position between sessions
- **Full Playback Control**: Complete transport controls and progress bar in compact form
- **Album Art Display**: Clickable album art for quick access to main window

### Virtual Playlists
- Supports extremely large playlists through pagination
- Loads tracks on-demand to minimize memory usage
- Seamless integration with playback system
- Buffer management and preloading for smooth playback
- Shuffle support with efficient index mapping

### Album Art Management
- Extracts embedded artwork from audio files
- Caches processed images for performance
- Custom QML image provider for efficient loading
- Multiple size variants (full, thumbnail) for different UI contexts

### System Tray Integration
- System tray icon with context menu
- Show/hide main window from tray
- Quick access to playback controls
- Graceful background operation

### State Persistence
- Saves playback position and queue
- Remembers UI state (carousel position, window positions)
- Persists user preferences and settings
- Restores state on application restart

### Multi-threaded Operations
- Background library scanning
- Concurrent metadata extraction
- Asynchronous album art processing
- Async playlist loading with progress reporting

## Performance Considerations

1. **Lazy Loading**: Virtual playlists load data on-demand with configurable buffer sizes
2. **Dynamic Caching**:
   - Multiple levels of caching for tracks, albums, and artwork
   - Adaptive QPixmapCache sizing based on system memory (5-10% of RAM, 128MB-1GB range)
   - Cache scaling based on thumbnail size preferences
3. **Batch Operations**: Database operations are batched for efficiency
4. **Memory Management**:
   - Careful management of QML object lifecycle
   - Efficient cleanup on application exit
   - Proper parent-child relationships for automatic cleanup
5. **Concurrent Processing**:
   - Uses Qt Concurrent for CPU-intensive tasks
   - Background library scanning with progress reporting
   - Async album art extraction and processing

## Platform Integration

- **Linux Desktop**:
  - MPRIS D-Bus interface for media key and desktop environment integration
  - System tray integration for background operation
  - Theme icon support for consistent desktop appearance
- **Flatpak Support**:
  - Automatic detection and icon configuration for Flatpak environments
  - Desktop file integration for proper app identification
- **File Systems**: Handles various path formats and encodings
- **Audio Formats**: Supports multiple formats via TagLib (MP3, FLAC, OGG, M4A, etc.)
- **Locale Support**: Configurable locale for proper string sorting and comparison