# mtoc - Visual Music Library

mtoc is a music player and library browser for Linux that emphasizes smooth, continuous browsing experiences with album artwork at the forefront. Built with modern C++, Qt6, and QML, it combines high performance with an engaging visual interface. 

![mtoc Music Player](resources/banner/mtoc-banner.png)

## Features

### 🎨 Visual Album Browsing
- **Carousel-style horizontal browser** with 3D perspective effects
- Albums tilt and overlap smoothly as you browse
- Uses efficient thumbnail artwork with intelligent caching

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

## Installation

#### Dependencies

#### Build Instructions

```bash
# Clone the repository
git clone https://github.com/asa-degroff/mtoc.git
cd mtoc

# Create build directory
mkdir build && cd build

# Configure
cmake ..

# Build and install
cmake --build . --target install

# Run
./mtoc_app 
# or run from your desktop environment's app launcher
```

## Usage

### First Run

On first launch, mtoc will feature an empty library. Click "Edit Library" and add the folder containing your music. mtoc will then scan and index your music collection, extracting metadata and album artwork.

### Navigation

- **Mouse/Touch**: The carousel and all scrollable lists support both click + drag and mouse wheel scrolling
- **Keyboard**: Arrow keys to navigate, Enter to play
- **Media Keys**: Standard play/pause, previous/next keys work system-wide
- **Search**: The search bar quickly brings up artists, albums, and tracks

### Library Management

Access the library editor through the settings to:
- Add or remove music directories
- Trigger library rescans
- Clear the library when needed
Rescan the library after adding, removing, or editing the files in your chosen directory to have the current versions populate the library. 

## Architecture

mtoc uses a modern, modular architecture:

- **Backend (C++)**
  - `LibraryManager`: Music collection scanning and organization
  - `DatabaseManager`: SQLite persistence layer
  - `MediaPlayer`: Playback control and queue management
  - `AudioEngine`: GStreamer integration
  - `MetadataExtractor`: TagLib wrapper for file analysis
  - `AlbumArtManager`: Intelligent album art caching

- **Frontend (QML)**
  - Custom components for smooth animations
  - Hardware-accelerated rendering
  - Responsive two-pane layout

## Performance Tips

For the best experience:

**GPU Acceleration**: Ensure your GPU drivers are properly installed

## License

This project is licensed under the GPL v3 License - see the LICENSE file for details.

## Acknowledgments

- Built with [Qt](https://www.qt.io/) and [QML](https://doc.qt.io/qt-6/qmlapplications.html)
- Audio metadata extraction powered by [TagLib](https://taglib.org/)
- Audio playback powered by [GStreamer](https://gstreamer.freedesktop.org/)

## Contact

Project Link: [https://github.com/asa-degroff/mtoc](https://github.com/asa-degroff/mtoc)

email: asa@3fz.org

---

*mtoc - modern visual music library*

## Roadmap

### 1.x
- Touchscreen, small screen, and Steam Deck controller optimization
- Additional list sort options
- M3U playlist support including playback and editing

### >= 2.0
- Metadata editor
- Integrated CD ripper
- Integrated library sync utility
- Rich podcast library with RSS support, streaming, and downloading
