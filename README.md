# mtoc - Visual Music Library

mtoc is a music player and library browser for Linux that emphasizes smooth, continuous browsing experiences with album artwork at the forefront. Built with modern C++, Qt6, and QML, it combines high performance with an engaging visual interface. 

![mtoc Music Player](resources/banner/mtoc-banner.png)

## Features

### 🎨 Album Browsing
- **Carousel-style horizontal browser** with 3D perspective effects
- Albums tilt and overlap smoothly as you browse
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

### 🖥️ Desktop Integration
- Full MPRIS support for media keys and system controls

### System Requirements
- Linux with X11/Wayland
- OpenGL/GPU acceleration recommended
- 4GB RAM and solid state storage recommended

## Getting Started

#### Dependencies
- Qt6 (Core, Quick, Qml, Multimedia, DBus, Concurrent, Widgets, Sql)
- CMake >= 3.16
- TagLib >= 2.0
- GStreamer >= 1.0
- pkg-config
- C++17 compatible compiler

#### Build Instructions

```bash
  # Install dependencies (example for Ubuntu/Debian)
  sudo apt install qt6-base-dev qt6-multimedia-dev qt6-declarative-dev \
                   libtag1-dev libgstreamer1.0-dev pkg-config cmake

  # Clone and build
  git clone https://github.com/asa-degroff/mtoc.git
  cd mtoc
  mkdir build && cd build
  cmake ..
  cmake --build .

  # Install system-wide (requires sudo)
  sudo cmake --build . --target install

  # Run
  mtoc_app  # Now in system PATH

  # Or for local testing without install:
  # Run directly from build directory
  ./mtoc_app

```

## Usage

### First Run

On first launch, mtoc will feature an empty library. Click "Edit Library" and add the folder containing your music. mtoc will then scan and index your music collection, extracting metadata and album artwork.

### Library Management

Access the library editor through the settings to:
- Add or remove music directories
- Trigger library rescans
- Clear the library when needed
- Rescan the library after adding, removing, or editing the files in your chosen directory to have the current versions populate the library. 

### Usage Tips
- mtoc works best with music that contains embedded artwork and is tagged by album artist. In this absence of the album artist tag, the artist tag will be used, potentially resulting in albums being broken up. 

## Architecture

mtoc uses a modern, modular architecture:

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
