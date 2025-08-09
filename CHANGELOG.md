# 2.1.1
### Bug fixes for elevated GPU usage and missing close button icon
- Scrolling text now scrolls on hover to prevent high GPU usage from nonstop scrolling animations
- Fixed a bug causing the icon in the close button in the album art popup to be invisible

# 2.1
### Compact layout mode and light theme
- Compact layout moves the playback controls to below the library, and the queue and full-size album art to their own popups; ideal for use on small screens and tiling setups
- Light theme brings a new white and and pastel-colored interface
- Options in settings for compact & wide layouts, light & dark modes, and automatic switching for both
- Contextual queue header labels the current queue source
- Performance and image quality improvements for the album carousel with better anti-aliasing, and a slightly compacted layout
- Improved sorting consistency for artists with locale-aware handling of accented characters

# 2.0.2
### New icon and layout tweaks for small screens
- New icon to match the updated branding
- Library pane is now wider at small window widths for improved usability

# 2.0.1
### Fixed laggy image loading during fast scrolling in the album carousel
- Improved performance in album carousel with delegate recycling and improved connection handling
- Implemented multithreaded asynchronous image response for higher performance thumbnail loading
- Improved thumbnail size efficiency
- Dynamic pixmap cache sizing based on available system memory for improved image loading performance

# 2.0
### Functional overhaul expanding library management, playback features, and interface       
- Support for queue management and context menus for queue actions
- M3U playlist support
- Playlist management with saving and editing playlists
- Shuffle and repeat modes
- All Songs virtual playlist for playback of the entire library
- Track info panel
- State persistence between sessions for queue, playback state, and interface selection
- New animations throughout the interface

# 1.2.1
- Fixed a bug that prevented the MPRIS previous control from restarting the first track in the queue.

# 1.2
- Added persistence to track selection and playback position that restores upon restart.
- Separated album art processing from the rest of the metadata extraction for improved scanning speed.
- Asynchronous album art population happens in the background after a library scan.
- Bug fixes and performance improvements

# 1.1.6
- Improved delegate recycling behavior in the artists column to resolve glitchy scrolling and a bug where albums would appear under the wrong artist. 

# 1.1.5
- This patch fixes visual bugs in the track list causing blurry text and erroneous highlighting.

# 1.1.4
- Improved keyboard input handling for library navigation, various performance improvements and bug fixes

# 1.1.3
- This release includes performance improvements for library scanning and fixes a bug that caused the carousel to lag while navigating a large library.

# 1.1.2
- This patch fixes the offset of the progress bar slider.

# 1.1.1
- This update includes new touchpad-specific navigation for the carousel that directly manipulates content with inertial flicking and snapping.

# 1.0.9
- mtoc 1.0.9 trims whitespace in certain areas of the UI making the layout work better on small screens. Also, this release fixes the off-center playback control buttons.

# 1.0
- Initial release