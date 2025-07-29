# mtoc Architecture Overview

## Introduction

mtoc is a modern music player and library management application built with Qt/QML, following a well-structured Model-View-Controller (MVC) architecture. The application uses C++ for the backend logic and QML for the user interface, providing a clean separation of concerns and efficient performance.

## Architecture Layers

### 1. Model Layer (Data Models)

The Model layer handles data representation and storage, located in `src/backend/`:

#### Core Data Models
- **Track** (`library/track.h`): Represents individual music tracks with metadata properties (title, artist, album, duration, etc.)
- **Album** (`library/album.h`): Represents music albums with aggregated track information
- **Artist** (`library/artist.h`): Represents artists with associated albums and tracks
- **VirtualTrackData** (`playlist/VirtualTrackData.h`): Lightweight track representation for virtual playlists

#### List Models (Qt's QAbstractListModel)
- **TrackModel** (`library/trackmodel.h`): Manages collections of tracks with sorting capabilities
- **AlbumModel** (`library/albummodel.h`): Manages album collections with custom roles for QML binding
- **VirtualPlaylistModel** (`playlist/VirtualPlaylistModel.h`): Provides paginated loading for large playlists with lazy loading support

### 2. View Layer (User Interface)

The View layer is implemented entirely in QML, located in `src/qml/`:

#### Main Views (`Views/`)
- **LibraryPane**: Browse music library by artists and albums
- **NowPlayingPane**: Display current track with album art and controls
- **PlaylistView**: Manage and play saved playlists
- **SettingsWindow**: Configure application settings
- **LibraryEditorWindow**: Edit library metadata

#### Reusable Components (`Components/`)
- **PlaybackControls**: Transport controls (play/pause/skip)
- **QueueListView**: Display and manage playback queue
- **HorizontalAlbumBrowser**: Browse albums in a horizontal carousel
- **SearchBar**: Search functionality
- **BlurredBackground**: Visual effects for album art backgrounds

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

The application registers C++ types and singletons with the QML engine:

```cpp
// Type registration in main.cpp
qmlRegisterType<Track>("Mtoc.Backend", 1, 0, "Track");
qmlRegisterSingletonInstance("Mtoc.Backend", 1, 0, "LibraryManager", libraryManager);
```

QML components import and use these types:
```qml
import Mtoc.Backend 1.0

// Direct access to C++ singletons
LibraryManager.startScan()
MediaPlayer.play()
```

## Key Features Implementation

### Virtual Playlists
- Supports extremely large playlists through pagination
- Loads tracks on-demand to minimize memory usage
- Seamless integration with playback system

### Album Art Management
- Extracts embedded artwork from audio files
- Caches processed images for performance
- Custom QML image provider for efficient loading

### State Persistence
- Saves playback position and queue
- Remembers UI state (carousel position)
- Restores state on application restart

### Multi-threaded Operations
- Background library scanning
- Concurrent metadata extraction
- Asynchronous album art processing

## Performance Considerations

1. **Lazy Loading**: Virtual playlists load data on-demand
2. **Caching**: Multiple levels of caching for tracks, albums, and artwork
3. **Batch Operations**: Database operations are batched for efficiency
4. **Memory Management**: Careful management of QML object lifecycle
5. **Concurrent Processing**: Uses Qt Concurrent for CPU-intensive tasks

## Platform Integration

- **Linux**: MPRIS D-Bus interface for desktop integration
- **File Systems**: Handles various path formats and encodings
- **Audio Formats**: Supports formats via TagLib (MP3, FLAC, OGG, etc.)

## Future Extensibility

The architecture supports easy extension through:
- Plugin system for audio formats
- Additional view types
- Network streaming capabilities
- Cloud synchronization
- Mobile platform support