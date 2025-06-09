# mtoc - Modern Touch-Optimized Music Collection Browser

mtoc is a visually-rich music player and library browser for Linux that emphasizes smooth, continuous browsing experiences with album artwork at the forefront. Built with modern C++, Qt6, and QML, it combines high performance with an engaging visual interface.

![mtoc Music Player](resources/icons/mtoc-icon-256.png)

## Features

### 🎨 Visual Album Browsing
- **Carousel-style horizontal browser** with 3D perspective effects
- Albums tilt and overlap smoothly as you browse
- High-resolution album artwork support with intelligent caching
- Reflection effects and gradients enhance the visual experience

### 🚀 High Performance
- Hardware-accelerated rendering using OpenGL/Qt RHI
- Efficient memory management with QML delegate recycling
- Asynchronous metadata extraction and image loading
- Optimized for smooth scrolling even with thousands of albums

### 📚 Library Management
- Automatic library scanning with incremental updates
- Support for MP3, MP4/M4A, FLAC, OGG/Vorbis formats
- Metadata extraction using TagLib 2.0
- Smart organization by artist, album, and year
- Embedded album artwork extraction

### 🎵 Playback Features
- GStreamer-based audio engine for reliable playback
- Gapless audio support for seamless album listening
- Standard controls: play/pause, previous/next, seek, volume
- Queue management with Now Playing view

### 🖥️ Desktop Integration
- Full MPRIS support for media keys and system controls
- Works with GNOME, KDE, and other desktop environments
- Desktop notifications for track changes
- Flatpak packaging for easy installation

## Installation

### Flatpak (Coming Soon)

```bash
# Install from Flathub (when available)
flatpak install flathub org._3fz.mtoc

# Or build locally
./build-flatpak.sh
flatpak install org._3fz.mtoc.flatpak
```

### Building from Source

#### Dependencies

- Qt6 (>= 6.2) with modules: Core, Quick, QML, Multimedia, DBus, Concurrent, SQL
- CMake (>= 3.16)
- TagLib (>= 2.0)
- GStreamer 1.0 with base plugins
- C++17 compatible compiler

#### Build Instructions

```bash
# Clone the repository
git clone https://github.com/asa-degroff/mtoc.git
cd mtoc

# Create build directory
mkdir build && cd build

# Configure
cmake ..

# Build
cmake --build .

# Run
./mtoc_app
```

## Usage

### First Run

On first launch, mtoc will feature an empty library. Click "Edit Library" and add the folder containing your music. mtoc will then scan and index your music collection, extracting metadata and album artwork.

### Navigation

- **Mouse/Touch**: Click and drag to browse albums horizontally
- **Keyboard**: Arrow keys to navigate, Enter to play
- **Media Keys**: Standard play/pause, previous/next keys work system-wide

### Library Management

Access the library editor through the settings to:
- Add or remove music directories
- Trigger manual library rescans
- Clear the library when needed

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

1. **GPU Acceleration**: Ensure your GPU drivers are properly installed
2. **For NVIDIA GPUs**: Use the provided `run_mtoc_nvidia.sh` script
3. **Force Software Rendering**: If you experience issues, use `run_mtoc_force_gl.sh`

## License

This project is licensed under the GPL v3 License - see the LICENSE file for details.

## Acknowledgments

- Built with [Qt](https://www.qt.io/) and [QML](https://doc.qt.io/qt-6/qmlapplications.html)
- Audio metadata extraction powered by [TagLib](https://taglib.org/)
- Audio playback powered by [GStreamer](https://gstreamer.freedesktop.org/)

## Contact

Project Link: [https://github.com/asa-degroff/mtoc](https://github.com/asa-degroff/mtoc)

---

*mtoc - modern visual music library*