# mtoc - Visual Music Library

mtoc is a visually-rich music player and library browser for Linux that emphasizes smooth, continuous browsing experiences with album artwork at the forefront. 

![mtoc Music Player](resources/banner/mtoc-banner.avif)

# Features

### Album Browsing
Album browsing is core to the experience. mtoc is made for the music fan who likes to flip through CDs or records and look at the pictures before deciding what to listen to. The album carousel interface presents your album covers on a slick reflective shelf, with responsive, satisfying animations as you flip through them in a linear fashion. Mouse wheel, click + drag, and touchpad are all supported, with direct content manipulation for a smooth touchpad experience. 

![carousel animation](resources/banner/carousel-animation.webm)

### Layout and Navigation
mtoc features a user-friendly "bento box" layout that places the album art, playback and queue in the largest section, with the carousel, artists/playlists column, and tracklist column on the left. 

The artists list features album artists sorted alphabetically. An artist can be expanded to reveal their albums, represented in a thumbnail grid, and sorted by year. The tracklist for the current album selection occupies the right column. Continuous navigation is enabled between interface elements by links that animate scrolling to and revealing the selection in its relevant list. 

Keyboard navigation is featured in all lists, jumping between lists, and for search. You can perform the essential functions of searching for and playing music without lifting a hand. 

### Library Features
A responsive search function finds artists, albums, and tracks, jumping to and selecting the relevant item in the list. 

### Library Management
The library editor lets you select one or multiple directories to scan for music, and optionally specify additional directories for .m3u playlist files. 
- Supported formats: MP3, MP4/M4A (including iTunes-encoded AAC and ALAC), FLAC, OGG Vorbis, Opus
- Metadata extraction using TagLib 2.0
- Embedded album artwork extraction
- SQLite database for fast library access

### Queueing features
Tracks, albums, and playlists can be enqueued from the library, either added up next, or appended to the end of the queue, through the right-click context menu. Multi-selection of tracks for queueing is supported. The queue supports modification: delete, multi-select and delete, reorder through drag-and-drop. 

### Playlists
Playlist creation in mtoc starts out with creating a queue. When you have a queue that you like, the save button writes its contents to a new .m3u playlist in your default playlist directory. The playlist editor can be used to add, remove, and reorder tracks in playlists. 

The provided All Songs virtual playlist is automatically updated and can be used to play your entire library sequentially or on shuffle. 

### Playback Modes
mtoc features shuffle and repeat modes. Shuffle uses a modified Fisher-Yates algorithm that incorporates newly enqueued tracks as you go. 

### Playback Features
- GStreamer-based audio engine
- Gapless audio support for seamless album listening
- Standard controls: play/pause, previous/next, seek

### State Persistence
mtoc saves your position in the interface as well playback state including your queue, current track, and position, so that you can pick up where you left off after restarting the app. 

### Desktop Integration
- Full MPRIS 2 support for media keys and system controls

### High Performance
Performance is a core design principle. mtoc aims for visual appeal and and continuity in browsing. 
- Hardware-accelerated rendering
- MVC architecture fine-tuned for efficiency
- Asynchronous metadata extraction and image loading
- Optimized for smooth scrolling and searching even with thousands of albums
#### Implementation Guidelines
Frequent reads and minimal writes makes this an application that benefits from extensive caching at the controller and view layers. 
- Cache data generously to reduce disk access frequency
- Use constant time cache lookups instead of sequential data access whenever possible

### System Requirements
- Linux with X11/Wayland
- OpenGL/GPU acceleration recommended
- Solid state storage recommended
- 4GB system RAM recommended. Typical usage for mtoc remains under ~350MB, but may go as high as 1GB if you push it by loading all tracks in a large library and skipping through them quickly. 

## Getting Started

#### Note
Official packages are currently only maintained for Fedora 41+. 

#### Dependencies
- Qt6 >= 6.7 (Core, Quick, Qml, Multimedia, DBus, Concurrent, Widgets, Sql)
- CMake >= 3.16
- TagLib >= 2.0
- GStreamer >= 1.0
- pkg-config
- C++17 compatible compiler

#### Package Installation (Fedora 41+)

```bash
# Add the copr repository:
sudo dnf copr enable 3fz-asa/mtoc

# Install:
sudo dnf install mtoc
```


#### Build From Source

```bash
# Install dependencies

# Ubuntu/Debian:
sudo apt install qt6-base-dev qt6-multimedia-dev qt6-declarative-dev \
                 libtag1-dev libgstreamer1.0-dev pkg-config cmake

# Fedora:
sudo dnf install qt6-qtbase-devel qt6-qtmultimedia-devel qt6-qtdeclarative-devel \
                 taglib-devel gstreamer1-devel pkgconfig cmake gcc-c++

# Arch Linux:
sudo pacman -S qt6-base qt6-multimedia qt6-declarative qt6-svg qt6-tools \
               taglib gstreamer cmake pkgconf base-devel

# Clone the repository
git clone https://github.com/asa-degroff/mtoc.git
cd mtoc

# Create build directory
mkdir build && cd build

# Configure
cmake ..

# Build
cmake --build .

# Run locally (without installation)
./mtoc_app

# Or install system-wide (optional)
sudo cmake --build . --target install
mtoc_app  # Now available in system PATH
```

## Usage

### First Run
On first launch, mtoc will feature an empty library. Click "Edit Library" (or the link provided in the placeholder) and add the folder containing your music. The default folder is ~/Music. You can add or remove any directories you want to scan. Press scan, and mtoc will then scan and index your music collection, extracting metadata and album artwork.

### Usage Tips
- mtoc works best with well-tagged music libraries. At a minimum, all tracks should have a title, artist, and album artist to be properly displayed and sorted. 
- mtoc may not suit libraries that contain a lot of singles. Tracks are grouped by album, and libraries with a high track:album ratio may make the interface feel cluttered. 

### Out of Scope
- mtoc is not a tag editor and will not fix broken metadata. 
- mtoc treats all music files as read-only. As such, writing tags like rating and play count is not supported. 
- mtoc does not have any online features. 

## Architecture

- **Backend (C++)**
  - `LibraryManager`: Music collection scanning and organization
  - `DatabaseManager`: SQLite persistence layer
  - `MediaPlayer`: Playback control and queue management
  - `AudioEngine`: GStreamer integration
  - `MetadataExtractor`: TagLib wrapper for file analysis
  - `AlbumArtManager`: Intelligent album art caching
  - `DatabaseManager`: SQLite persistence layer


- **Frontend (QML)**
  - Library and Now Playing panes
  - Horizontal album browser
  - Responsive search bar
  - Responsive playback controls
  - Custom UI animations
  - Hardware-accelerated rendering
  - Responsive two-pane layout
  - Deferred window reloading for efficiency

  See [ARCHITECTURE.md](/ARCHITECTURE.md) for details. 

## Roadmap
The following features are in development or planned for a future release: 

- Gamepad input support for steam deck and similar devices
- Podcast library with streaming and online search

## License

This project is licensed under the GPL v3 License - see the LICENSE file for details.

## Acknowledgments

- Built with [Qt](https://www.qt.io/) and [QML](https://doc.qt.io/qt-6/qmlapplications.html)
- Audio metadata extraction powered by [TagLib](https://taglib.org/)
- Audio playback powered by [GStreamer](https://gstreamer.freedesktop.org/)

## Contact

Project Link: [https://github.com/asa-degroff/mtoc](https://github.com/asa-degroff/mtoc)

email: asa@3fz.org
