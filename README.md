# mtoc - Visual Music Library

mtoc is a music player and library browser for Linux that emphasizes smooth, continuous browsing experiences with album artwork at the forefront. Built with modern C++, Qt6, and QML, it combines high performance with an engaging visual interface. 

![mtoc Music Player](resources/banner/mtoc-banner.png)

## Features

### 🎨 Album Browsing
- **Carousel-style horizontal browser** with 3D perspective effects
- Albums tilt and overlap smoothly as you browse
- Mouse wheel, click + drag, and touchpad are all supported with smooth, intuitive tracking
- Uses efficient thumbnail artwork with intelligent caching
- Responsive search finds artists, albums, and tracks

### 🚀 High Performance
- Hardware-accelerated rendering using OpenGL/Qt RHI
- Efficient memory management with QML delegates
- Asynchronous metadata extraction and image loading
- Optimized for smooth scrolling and searching even with thousands of albums

### 📚 Library Management
- Automatic library scanning
- Supported formats: MP3, MP4/M4A (including iTunes-encoded AAC and ALAC), FLAC, OGG Vorbis, Opus
- Metadata extraction using TagLib 2.0
- Smart organization by artist, album, and year
- Embedded album artwork extraction
- SQLite database for fast library access

### 🎵 Playback Features
- GStreamer-based audio engine
- Gapless audio support for seamless album listening
- Standard controls: play/pause, previous/next, seek
- Playback state persistence: saves your playback state between restarts so you can pick up where you left off

### 🖥️ Desktop Integration
- Full MPRIS support for media keys and system controls

### System Requirements
- Linux with X11/Wayland
- OpenGL/GPU acceleration recommended
- 4GB RAM and solid state storage recommended

## Getting Started

Note: mtoc is currently developed and tested on Fedora 42. Support for other distributions is experiemental and may require additional configuration not detailed here.

#### Dependencies
- Qt6 >= 6.2 (Core, Quick, Qml, Multimedia, DBus, Concurrent, Widgets, Sql)
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

# Arch Linux/SteamOS:
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

On first launch, mtoc will feature an empty library. Click "Edit Library" and add the folder containing your music. The default folder is ~/Music. You can add or remove any directories you want to scan. Press scan, and mtoc will then scan and index your music collection, extracting metadata and album artwork.


### Library Management

Access the library editor through the settings to:
- Add or remove music directories
- Trigger library rescans
- Clear the library when needed
- Rescan the library after adding, removing, or editing the files in your chosen directory to have the current versions populate the library. 

### Usage Tips
- mtoc works best with music that contains embedded artwork and is tagged by album artist. In this absence of the album artist tag, the artist tag will be used, potentially resulting in albums being broken up. 

## Architecture

mtoc uses a modern, modular MVC architecture:

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

## Performance Tips

For the best experience:

**GPU Acceleration**: Ensure your GPU drivers are properly installed

## Roadmap

### 1.x
- Touchscreen, small screen, and Steam Deck controller support
- Keybaord navigation
- Additional list sort options
- M3U playlist support including playback and editing
- Settings window with additional options

### >= 2.0
- Metadata editor
- Integrated CD ripper
- Integrated library sync utility
- Rich podcast library with RSS support, streaming, and downloading

## License

This project is licensed under the GPL v3 License - see the LICENSE file for details.

## Acknowledgments

- Built with [Qt](https://www.qt.io/) and [QML](https://doc.qt.io/qt-6/qmlapplications.html)
- Audio metadata extraction powered by [TagLib](https://taglib.org/)
- Audio playback powered by [GStreamer](https://gstreamer.freedesktop.org/)

## Contact

Project Link: [https://github.com/asa-degroff/mtoc](https://github.com/asa-degroff/mtoc)

email: asa@3fz.org
