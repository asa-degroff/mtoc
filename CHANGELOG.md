# 2.3.3
### Bug fixes for MPRIS album art, case-insensitive artist grouping, and theme switching
- Album art now appears in the MPRIS widget when using the Flatpak build
- Artists are now grouped case-insensitively in the artists list
- Tracks with case-mismatched album artists now appear in search results as expected
- Improved system theme detection for switching between light and dark modes without a restart

# 2.3.2
### Improved system tray context menu and synchronized lyrics during paused state
- System tray context menu now includes playback options and playlist picker
- Added Flatpak permissions for KDE system tray support
- Lyrics highlighting is now synchronized when playback is paused

# 2.3.1
### Bug fixes for lyrics refresh and file watcher
- Fixed a bug where newly added lyrics would cause the lyrics display not to update properly when changing tracks
- Fixed a bug where playing from the All Songs playlist after adding or removing tracks with the watcher enabled could cause a crash

# 2.3
### Lyrics support, file watcher, automatic library updates, minimize to tray
- Support for displaying unsynced and synced lyrics embedded in track metadata and external .lrc and .txt files
- Displays synced lyrics with line highlighting and reverse seeking by clicking a line in the lyrics
- External lyrics stored in the same directory as audio files are detected by the scanner and associated with the track with the best filename match
- New file watcher that updates your library to reflect added and removed music and lyrics files without manually triggering a scan
- Added library management options to choose between automatic library updates, refresh on startup, or manual updates
- Improved stability of the album carousel when albums are added and removed
- Added the option to minimize to tray when closing the main window
- Added the option to single-click to play tracks

# 2.2.4
### Bug fixed for album carousel with large libraries, album sorting consistency, and carousel reflection consistency
- Fixed a bug where the album carousel would not display albums when the library contained more than 1000 albums
- Improved sorting consistency for non-alphabetical characters in artist names
- Fixed a bug where the reflections for albums in the carousel using placeholder art were showing other albums' reflections

# 2.2.3
### Thumbnail size options, improved thumbnail loading performance, audio engine settings bug fixes, UI polish
- Added thumbnail size selector with options for 100%, 150%, and 200%, offering a choice between reduced memory usage or higher visual quality
- Added the option to rebuild thumbnails from the settings window
- Clicking an album  in the carousel now scrolls to and selects that album in the artists list for improved bidirectional continuity between the two album browsing interfaces
- Thumbnail cache optimizations for performance
- Improved programmatic scrolling in the artists list is now smoother and more predictable
- Asynchronous loading of grid views in the artists list loads thumbnails without blocking list height and position calculations for faster performance and smoother scrolling
- Option to expand or collapse all album grids in the artists list, accessible by right-clicking the artists list selector
- Fixed a bug where the carousel position could shift by 1px after clicking on an album
- Fixed a bug where positive gain values in preamplification and fallback gain settings were not being applied (positive gain now increases loudness and causes clipping distortion as expected)
- Fixed a bug where the slider handles in the settings appeared slightly misaligned from the slider position
- Album grid selection indicators are now 2px larger
- Relative width setting of the columns in the library pane now persists when resizing the window, changing layouts, and restarting the app

# 2.2.2
### Improved portal path handling, main window visibility option, region-aware search
- Library search is now region-aware, returns accent-insensitive results
- Added the option to keep the main window visible along with the mini player
- Fixed a bug where playlists containing tracks outside of the ~/Music directory didn't work in the Flatpak build of mtoc
- Fixed a bug were slider handles in the settings window were not recieving mouse input, and increased the size of the handles
- Miscellaneous layout and UI bug fixes

# 2.2.1
### Fix for AAC playback bug, system accent color integration
- Fixed a bug that caused a few seconds of silence between tracks when playing AAC audio
- Use system accent color for list selections
- Artists/Playlists tab selection is maintained when switching layouts

# 2.2
### Mini player, gapless playback, and ReplayGain support
- New mini player hides the main window and shows basic playback controls in a compact window, with three layout modes to choose from
- Precise gapless playback for supported files, with a continuous audio pipeline, next track preloading, and seamless transitions
- New audio engine features including ReplayGain support for volume normalization on supported tracks and albums, fallback gain setting, and preamplification slider

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