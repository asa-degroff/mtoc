Name:           mtoc
Version:        2.5.1
Release:        1%{?dist}
Summary:        Music player and library browsing application

License:        GPL-3.0
URL:            https://github.com/asa-degroff/mtoc
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  cmake >= 3.16
BuildRequires:  gcc-c++
BuildRequires:  qt6-qtbase-devel
BuildRequires:  qt6-qtdeclarative-devel
BuildRequires:  qt6-qtmultimedia-devel
BuildRequires:  qt6-qttools-devel
BuildRequires:  taglib-devel
BuildRequires:  gstreamer1-devel
BuildRequires:  pkgconfig
BuildRequires:  desktop-file-utils

Requires:       qt6-qtbase
Requires:       qt6-qtdeclarative
Requires:       qt6-qtmultimedia
Requires:       qt6-qtquickcontrols2
Requires:       taglib
Requires:       gstreamer1
Requires:       gstreamer1-plugins-base
Requires:       gstreamer1-plugins-good

%description
mtoc is a music player and library browser for Linux that emphasizes smooth, continuous browsing experiences with album artwork at the forefront.

%prep
%autosetup -n %{name}-%{version}

%build
%cmake
%cmake_build

%install
%cmake_install

# Validate desktop file
desktop-file-validate %{buildroot}%{_datadir}/applications/*.desktop

%files
%license LICENSE
%doc README.md CHANGELOG.md
%{_bindir}/mtoc_app
%{_datadir}/applications/*.desktop
%{_datadir}/icons/hicolor/*/apps/org._3fz.mtoc.png
%{_datadir}/pixmaps/mtoc.png
%{_datadir}/metainfo/org._3fz.mtoc.metainfo.xml

%changelog
* Mon Dec 15 2025 Asa DeGroff <asa@3fz.org> 2.5.1-1
- version bump and changelog (asa@3fz.org)
- ensure application quits properly on close to fix Flatpak build issues
  (asa@3fz.org)

* Tue Dec 09 2025 Asa DeGroff <asa@3fz.org> 2.5-1
- bump version to 2.5 and update changelog (asa@3fz.org)
- update changelog with favorites feature (asa@3fz.org)
- reduce cacheBuffer in library pane (asa@3fz.org)
- fixed scroll bar hover effect in artists list to extend over scroll bar
  itself (asa@3fz.org)
- thread-safe database access (asa@3fz.org)
- enable immediate reload on favorites change when favorites list is visible
  (asa@3fz.org)
- lazy reload favorites playlist to prevent race conditions (asa@3fz.org)
- heart icon styling: fixed drop shadow crop and tweaked tint opacity
  (asa@3fz.org)
- use system accent color for filled heart (asa@3fz.org)
- reloadPlaylist method in virtual playlist model for memory safe playlist
  updates (asa@3fz.org)
- favorites playlist tracks display, click handlers (asa@3fz.org)
- auto-update track count for favorites list (asa@3fz.org)
- Favorites Implementaion   Summary: (asa@3fz.org)
- refactor button positioning to enable fluid animation upon show/hide lyrics
  button (asa@3fz.org)
- add favorites button, svg icons, adjust button layout to accomodate favorites
  (asa@3fz.org)
- new option to auto-disable shuffle after queue replacement (asa@3fz.org)
- update changelog (asa@3fz.org)
- sync playlist title between components upon edit in either, surpress new
  playlist animation upon playlist rename (asa@3fz.org)
- select playlist title text upon entering editor (asa@3fz.org)
- activate playlist title editing upon playlist creation (asa@3fz.org)
- use styled menu in playlist context menu, update styled menu items to use
  accent color (asa@3fz.org)
- add context menu for artists in artist list with Play All and Shuffle All
  options (asa@3fz.org)
- add Shuffle option to context menu for albums and playlists (asa@3fz.org)
- add checkmark icon and use it for playlist renaming confirmation
  (asa@3fz.org)
- button layout consistency for playlist renaming (asa@3fz.org)
- refactor playlist renaming: remove popup in favor on inline title editor
  (asa@3fz.org)
- default playlist title now features the first three track titles
  (asa@3fz.org)
- refactor playlist view with intermediate ListModel that syncs incrementally
  with playlist manager, add animations for add/delete playlists (asa@3fz.org)
- navigate to and highlight new playlist upon creation from context menu
  (asa@3fz.org)
- option for playlist creation from context menu (asa@3fz.org)
- feat: "add to playlist" submenu in track and album context menu (asa@3fz.org)
- save contentY before model update upon queue item deletion to stabilize list
  position (asa@3fz.org)
- don't auto-scroll upon queue item deletion (asa@3fz.org)
- stabilized queue deletion animation (asa@3fz.org)
- ensure delete button on queue list item has full hit area (asa@3fz.org)
- hidden artist and wider title when hovering track in playlist editor
  (asa@3fz.org)
- use arrow cursor in track list, use drag handle cursor for drag handle
  (asa@3fz.org)
- fix: reset drag state on focus loss in queue list (asa@3fz.org)
- fix: also reset visibility of reordered item after regaining focus
  (asa@3fz.org)
- new drag and drop implementation with drag proxy for playlist editor
  (asa@3fz.org)
- minimum drag distance for auto-scroll start (asa@3fz.org)
- feat: adjustable auto-scroll velocity depending on cursor position
  (asa@3fz.org)
- cleanup unused delegate recycling code in queue list (asa@3fz.org)
- scrolling queue list fixes, dragged item position compensation (asa@3fz.org)
- skip auto-scroll upon list change during playlist reordering, fix targetY
  calculation to account for column structure (asa@3fz.org)
- fix Y-position calculation for dragging playlist items (asa@3fz.org)
- refactored playlist editor (asa@3fz.org)
- feat: add auto-scroll during drag and drop queue reordering and refactor
  animations to work with list scrolling (asa@3fz.org)
- feat: state persistence for queue and lyrics visibility status in now playing
  pane (asa@3fz.org)
- increase height of drag handle on draggable list items to full height
  (asa@3fz.org)
- add selectPlaylist function for selecting playlists by name in playlist view
  (asa@3fz.org)
- clear selction highlights after reordering tracks in playlist editor
  (asa@3fz.org)
- fix for now playing track and selection highlight colors snapping upon list
  reorder (asa@3fz.org)
- fix: disable hover effect during drop finalization in QueueListView and
  LibraryPane to eliminate hover effect snapping upon list reordering
  (asa@3fz.org)
- fix: improve drag-and-drop animation for track reordering in QueueListView
  and LibraryPane to eliminate the visual snap effect (asa@3fz.org)
- update Qt policies for resource prefix and qmldir generation; set output
  directory for QML module (asa@3fz.org)
- update screenshot for readme (asa@3fz.org)

* Mon Nov 17 2025 Asa DeGroff <asa@3fz.org> 2.4.2-1
- version bump to 2.4.2 and update changelog with new features (asa@3fz.org)
- feat: enhance multi-artist navigation link support in the compact now playing
  interface (asa@3fz.org)
- fix lyrics icon in light mode in compact now playing bar (asa@3fz.org)
- perf: refactor albumByTitle to return QVariantMap instead of Album pointer;
  add caching for album artists in Track class (asa@3fz.org)
- layout fix (asa@3fz.org)
- cleanup (asa@3fz.org)
- Add album retrieval by title and artist, enhance artist parsing in
  NowPlayingPane (asa@3fz.org)
- commented out verbose logging (asa@3fz.org)
- refactor external album art extraction to handle all file types (asa@3fz.org)
- debug logging for external art extraction (asa@3fz.org)
- improved external album art processing and related debug logging
  (asa@3fz.org)
- Add comprehensive CLAUDE.md documentation for AI assistants
  (noreply@anthropic.com)

* Wed Nov 12 2025 Asa DeGroff <asa@3fz.org> 2.4.1-1
- version bump and changelog (asa@3fz.org)
- Implement enhanced LRC format parsing for embedded plaintext lyrics with
  timestamps (asa@3fz.org)
- Enhance track loading logic to prevent dangling pointers during gapless
  transitions (asa@3fz.org)

* Sun Nov 09 2025 Asa DeGroff <asa@3fz.org> 2.4-1
- version bump and changelog (asa@3fz.org)
- new tooltips for library scanner options, formatting tweaks (asa@3fz.org)
- update reminder text int library editor (asa@3fz.org)
- update reminder text in libray editor (asa@3fz.org)
- Performance and memory usage improvements for library scanning and album art
  processing: - added calculateImageHash() method in album art manager -
  changed image hash calculation in library manger to use QByteArray instead of
  full image - added explicit cleanup for QImage assignments in album art
  manager and library manager - process albums in batches of 20, garbage
  collect after each batch - convert album art to RGB888 to reduce memory usage
  - generate and encode thumbnails in a scoped block to be freed after creation
  - memory monitoring debug output (asa@3fz.org)
- add heaptrack files to gitignore (asa@3fz.org)
- Add current track and artist to window title (asa@3fz.org)
- add metadata extraction button in library editor window and wire it up to the
  metadata extractor backend (asa@3fz.org)
- update default delimiters and clarify reminder text in UI (asa@3fz.org)
- moved reminder text to tooltip and changed default delimiters (asa@3fz.org)
- debug logging cleanup (asa@3fz.org)
- feat: enhance metadata update process by cleaning up orphaned records for
  albums, album artists, and artists (asa@3fz.org)
- feat: add force metadata update functionality in LibraryManager and connect
  to settings changes (asa@3fz.org)
- feat: add toggle for using album artist delimiters in SettingsWindow and
  update SettingsManager to handle new setting (asa@3fz.org)
- feat: implement local delimiter management for album artist settings in
  SettingsWindow (asa@3fz.org)
- fix: update border color for input field focus state in SettingsWindow
  (asa@3fz.org)
- update styling for multi-artist album toggle in SettingsWindow with improved
  layout and visual feedback (asa@3fz.org)
- feat: refactor delimiter configuration handling in SettingsWindow to directly
  use SettingsManager for album artist delimiters (asa@3fz.org)
- feat: enhance artist handling by adding support for user-defined delimiters
  in settings and improving multi-artist detection logic, add unsplit fallback
  logic to support single artist names that contain delimiter characters
  (asa@3fz.org)
- feat: implement smart navigation for artist and album handling in
  NowPlayingPane and CompactNowPlayingBar, where unique track artists are
  prioritized over the primary album artist (asa@3fz.org)
- feat: improve handling of multi-artist names in jumpToArtist and jumpToAlbum
  functions (asa@3fz.org)
- feat: enhance track retrieval by implementing multi-artist support and
  resolve multiple artists in programmatic library navigation (asa@3fz.org)
- feat: enhance album retrieval with junction table support and improved query
  handling (asa@3fz.org)
- feat: update album retrieval to support junction table and add debug logging
  (asa@3fz.org)
- feat: enhance album artist handling with multi-artist support for
  multithreded batch insertion (asa@3fz.org)
- feat: update album artist delimiters to support both semicolon formats in
  settings (asa@3fz.org)
- feat: add library & metadata settings with multi-artist toggle and delimiter
  configuration (asa@3fz.org)
- feat: enhance album artist linking with junction table checks and fallback
  queries (asa@3fz.org)
- feat: implement multi-artist support with junction table and settings for
  album artists (asa@3fz.org)
- update gitigore (asa@3fz.org)

* Mon Oct 27 2025 Asa DeGroff <asa@3fz.org> 2.3.3-1
- changelog and version bump (asa@3fz.org)
- fix: enhance system theme detection using Qt 6.5+ color scheme API for
  switching without a restart (asa@3fz.org)
- update metainfo for clarity and brevity (asa@3fz.org)
- fix: implement case-insensitive search for artists and albums (asa@3fz.org)
- fix: prevent race condition in artist list scrolling (asa@3fz.org)
- fix: update album art cache directory for flatpak compatibility (asa@3fz.org)
- fixed typo (asa@3fz.org)
- Automatic commit of package [mtoc] release [2.3.2-1]. (asa@3fz.org)

* Mon Oct 20 2025 Asa DeGroff <asa@3fz.org> 2.3.2-1
- version bump and changelog (asa@3fz.org)
- fix: integrate library manager for special playlists support in system tray
  context menu (asa@3fz.org)
- Add context menu actions for media playback control and playlist selection in
  system tray (asa@3fz.org)
- Add connections block for position change handling in LyricsView to enable
  bidirectional synchronization of lyrics highlighting and seek position during
  paused state (asa@3fz.org)
- fixed typo (asa@3fz.org)

* Tue Oct 14 2025 Asa DeGroff <asa@3fz.org> 2.3.1-1
- update description in metainfo (asa@3fz.org)
- Bump version to 2.3.1, update changelog, and refine version check logic
  (asa@3fz.org)
- second dot separator visibility depends on isSpecialPlylist (asa@3fz.org)
- Add library invalidation signal and improve cache management and memory
  safety in LibraryManager and MediaPlayer (asa@3fz.org)
- fix lyrics update handling by moving logic from LyricsView to MediaPlayer
  (asa@3fz.org)

* Mon Oct 13 2025 Asa DeGroff <asa@3fz.org> 2.3-1
- updated changelog popup contents (asa@3fz.org)
- Add changelog popup and version tracking in settings (asa@3fz.org)
- updated metainfo and changelog (asa@3fz.org)
- add lyric view screenshot (asa@3fz.org)
- Add trackLyricsUpdated signal and update LyricsView for real-time lyric
  updates after adding external lyric files (asa@3fz.org)
- version bump and changelog (asa@3fz.org)
- Enable seeking on clicking synced lyric lines (s20n@ters.dev)
- update readme (asa@3fz.org)
- update readme (asa@3fz.org)
- Update architecture documentation (asa@3fz.org)
- Emit signal to notify UI of track data changes after updating lyrics
  (asa@3fz.org)
- Refactor lyrics file handling to support both .lrc and .txt formats and
  update related debug messages (asa@3fz.org)
- simplify library editor options to accurately reflect unique functionality
  and remove redundancy (asa@3fz.org)
- maintain carousel position during library changes (asa@3fz.org)
- Add functionality to automatically update lyrics from LRC files and process
  changes in directories using file watcher (asa@3fz.org)
- Add minimize to tray functionality and related settings (asa@3fz.org)
- cleanup duplicate declaration (asa@3fz.org)
- Add support for SYLT synchronized lyrics for MP3 files (s20n@ters.dev)
- Optimize longest common substring search and improve LRC file matching
  efficiency (asa@3fz.org)
- Add LRC file fuzzy matching and substring search functionality (asa@3fz.org)
- Add support for SYLT synchronized lyrics for MP3 files (s20n@ters.dev)
- Add support for synchronized lyrics and sidecar (lrc) files (s20n@ters.dev)
- Implement cache invalidation for updated album art in
  processAlbumArtInBackground (asa@3fz.org)
- library editor layout updates (asa@3fz.org)
- Implement file watcher and auto-refresh settings in LibraryManager
  (asa@3fz.org)
- Revert "add heart icon" (asa@3fz.org)
- add heart icon (asa@3fz.org)
- Add LyricsPopup component and integrate with CompactNowPlayingBar
  (asa@3fz.org)
- update lyrics button theme for consistency (asa@3fz.org)
- animation timing tweaked (asa@3fz.org)
- Auto-hide lyrics or queue when toggling their visibility in NowPlayingPane
  (asa@3fz.org)
- Add animated transition for album art and lyrics visibility in NowPlayingPane
  (asa@3fz.org)
- Add null safe ternary operator for placeholder reflection effect origin
  calculation (asa@3fz.org)
- Auto-hide lyrics display when current track has no lyrics (asa@3fz.org)
- Add single-click-to-play feature and related settings (asa@3fz.org)
- Calculate preferred height for album art and queue container in
  NowPlayingPane (asa@3fz.org)
- Refactor queue button positioning and add animation when showing lyrics
  button (asa@3fz.org)
- Add hasCurrentTrackLyrics property and update PlaybackControls for
  conditional lyrics button visibility (asa@3fz.org)
- Fix getStringValue bug when using non-ascii keys (s20n@ters.dev)
- Add MP4/M4A lyrics tag support (s20n@ters.dev)
- Integrate new lyrics icon (s20n@ters.dev)
- add lyrics icons (asa@3fz.org)
- Implement lyrics display and refactor track metadata initialization
  (s20n@ters.dev)

* Mon Sep 08 2025 Asa DeGroff <asa@3fz.org> 2.2.4-1
- fixed closing tag (asa@3fz.org)
- bump version to 2.2.4 and update changelog (asa@3fz.org)
- enhance album reflection logic with placeholder support for albums without
  art (asa@3fz.org)
- refactor album sorting by prioritizing letters over non-letters in artist
  names (asa@3fz.org)
- refactor cache management with more effective fixed sizes for artist and
  track caches (asa@3fz.org)
- implement memory-aware cache management for artist and track caches
  (asa@3fz.org)
- remove 1000 album limit for model cache, optimize album model caching and
  memory management for large libraries (asa@3fz.org)
- update description in metainfo (asa@3fz.org)
- update screenshot references in metainfo (asa@3fz.org)
- typo in filename (asa@3fz.org)
- typo in filename (asa@3fz.org)
- updated screenshots (asa@3fz.org)

* Wed Aug 27 2025 Asa DeGroff <asa@3fz.org> 2.2.3-1
- version bump in settings window (asa@3fz.org)
- changelog and version bump (asa@3fz.org)
- Add library split ratio management: implement getter, setter, and UI
  integration for adjustable split ratio in LibraryPane. (asa@3fz.org)
- Center align album-related labels in LibraryEditorWindow for improved visual
  consistency. (asa@3fz.org)
- Revert "Enhance image caching mechanism: increment cache version on library
  scan completion, album art processing, and thumbnail rebuilds to ensure
  updated album images are displayed." (asa@3fz.org)
- Enhance image caching mechanism: increment cache version on library scan
  completion, album art processing, and thumbnail rebuilds to ensure updated
  album images are displayed. (asa@3fz.org)
- Enhance selection indicator dimensions: adjust outline size and add padding
  to ensure proper coverage of album images, improving visual consistency.
  (asa@3fz.org)
- Enhance visibility checks for album grid loading: ensure GridView is created
  only when the container is visible and has data, improving performance and
  user experience. (asa@3fz.org)
- Improve album grid loading logic: ensure GridView is created only when
  visible and has data, and safely pass current artist name to enhance
  performance and memory safety (asa@3fz.org)
- Enhance HorizontalAlbumBrowser position calculations and click handling:
  optimize position updates with index checks and stabilize content position
  after scrolling to resolve 1px click shift bug (asa@3fz.org)
- Add expand/collapse all functionality for artists in LibraryPane
  (asa@3fz.org)
- fixed slider handle alignment in settings (asa@3fz.org)
- enabled positive gain and clarified settings tooltips (asa@3fz.org)
- settings window text (asa@3fz.org)
- simplify grid view loading to remove ineffective visibility calculations
  (asa@3fz.org)
- Enhance GridView to trigger viewport updates on load and improve visibility
  detection for lazy loading (asa@3fz.org)
- Add album container height caching and optimize GridView loading for
  performance (asa@3fz.org)
- Add deferred viewport update timer to optimize scrolling performance
  (asa@3fz.org)
- Increase cache buffers for album grid and viewport checks, enable image
  caching during scrolling (asa@3fz.org)
- Add delay timer for deferred operations and enhance jumpToArtist
  functionality (asa@3fz.org)
- Add jumpToAlbum functionality to skip browser navigation when selecting an
  album (asa@3fz.org)
- Add scroll position and expanded artists state management to SettingsManager
  and LibraryPane (asa@3fz.org)
- Add progress bar for thumbnail rebuilding (asa@3fz.org)
- Implement dynamic thumbnail cache resizing and image clearing on scale change
  (asa@3fz.org)
- Enhance thumbnail caching mechanism by stripping query parameters and adding
  generation counter for refresh (asa@3fz.org)
- Add thumbnail size selection features and settings integration (asa@3fz.org)
- typo (asa@3fz.org)
- typo (asa@3fz.org)
- update readme (asa@3fz.org)
- Revert "content" (asa@3fz.org)
- content (asa@3fz.org)

* Fri Aug 22 2025 Asa DeGroff <asa@3fz.org> 2.2.2-1
- version bump and changelog (asa@3fz.org)
- feat: implement accent-insensitive search functionality in DatabaseManager
  (asa@3fz.org)
- feat: add option to control main window visibility on show mini player
  (asa@3fz.org)
- feat: enhance slider handle design and increase preferred height in
  SettingsWindow (asa@3fz.org)
- fix: consume wheel events in QueuePopup to prevent propagation (asa@3fz.org)
- feat: add combo box styling for replay gain mode selection in SettingsWindow
  (asa@3fz.org)
- fix: improve handling of portal paths in display name generation
  (asa@3fz.org)
- fix: enhance makeRelativePath to handle empty and portal paths correctly
  (asa@3fz.org)
- fixed typo in metainfo (asa@3fz.org)

* Tue Aug 19 2025 Asa DeGroff <asa@3fz.org> 2.2.1-1
- version bump and changelog (asa@3fz.org)
- fix: bind currentTab property to SettingsManager for state persistence
  (asa@3fz.org)
- use system accent color for selections (asa@3fz.org)
- cleanup excessive debug logging of replaygain values during library scan
  (asa@3fz.org)
- fix: adjust layout properties for scan progress display in
  LibraryEditorWindow (asa@3fz.org)
- fix: add AAC file handling special case that disables gapless playback to
  prevent playback delays (asa@3fz.org)
- fix release date in metainfo (asa@3fz.org)

* Mon Aug 18 2025 Asa DeGroff <asa@3fz.org> 2.2-1
- update metainfo with mini player screenshot (asa@3fz.org)
- added mini player screenshot (asa@3fz.org)
- feat: add system accent color support and update theme properties
  (asa@3fz.org)
- fix: improve item display in mini player layout combo box (asa@3fz.org)
- fix: adjust progress slider positioning for better alignment (asa@3fz.org)
- cleaned up debug logging (asa@3fz.org)
- refactor minimize button to rectangle with hover effects and tooltip
  (asa@3fz.org)
- closing tag in metainfo (asa@3fz.org)
- version bump (asa@3fz.org)
- changelog (asa@3fz.org)
- tooltip styling (asa@3fz.org)
- Add tooltips for layout options in SettingsWindow and MiniPlayer
  (asa@3fz.org)
- miniplayer theme tweaks for light mode (asa@3fz.org)
- Add CompactBar layout option to MiniPlayer and update settings UI
  (asa@3fz.org)
- settings window layout tweaks (asa@3fz.org)
- Add light mode icons for minimize and maximize buttons in the mini player
  (asa@3fz.org)
- miniplayer layout tweaks (asa@3fz.org)
- Refine MiniPlayerWindow interaction and layout: improve drag area behavior,
  adjust spacing, and enhance slider functionality for better user experience
  (asa@3fz.org)
- Memory safety: enhance transition monitoring in AudioEngine and validate
  track pointers in MediaPlayer and MPRISManager (asa@3fz.org)
- miniplayer button size and spacing (asa@3fz.org)
- simplify application display name and mini player title for consistency
  (asa@3fz.org)
- miniplayer layout adjustments (asa@3fz.org)
- Update MiniPlayerWindow colors for better visibility on dark backgrounds
  (asa@3fz.org)
- Refactor MiniPlayerWindow dimensions and improve layout handling for dynamic
  resizing (asa@3fz.org)
- Add Mini Player feature with layout options and integration in SettingsWindow
  (asa@3fz.org)
- Add minimize and maximize icons, add minimize button to LibraryPane header
  (asa@3fz.org)
- clean up unused text scrolling pause duration references (asa@3fz.org)
- Add info icons with tooltips for Replay Gain and fallback gain settings in
  SettingsWindow (asa@3fz.org)
- Enhance gapless playback support when shuffling All Songs by preloading
  neighboring tracks in virtual playlists and improving shuffle index handling
  in MediaPlayer. (asa@3fz.org)
- Cleanup: refactor gapless playback handling in AudioEngine by streamlining
  transition detection and improving fallback mechanisms for enhanced track
  transitions. (asa@3fz.org)
- Enhance transition detection in AudioEngine with proactive monitoring and
  improved fallback handling for gapless playback (asa@3fz.org)
- Refactor transition handling in AudioEngine to improve gapless playback
  transition detection with duration change monitoring (asa@3fz.org)
- Restrict playlist edit options to non-special playlists in LibraryPane
  (asa@3fz.org)
- Implement delayed transition notifications in AudioEngine for smoother track
  changes and improved consistency in progress bar updates during gapless
  transitions (asa@3fz.org)
- gapless playback tracking and transition handling in AudioEngine and
  MediaPlayer (asa@3fz.org)
- Enhance UI updates during gapless playback by improving track transition
  handling and state updates (asa@3fz.org)
- Improved gapless playback support by preloading the next track and handling
  transitions (asa@3fz.org)
- rearrange settings (asa@3fz.org)
- Manage audio filter bin references in replay gain functionality to prevent
  premature deallocation (asa@3fz.org)
- Refactor replay gain settings in settings window, add pre-amplification
  slider and improve layout (asa@3fz.org)
- add audio filter bin containing audioconvert for replay gain functionality
  (asa@3fz.org)
- Add detailed logging for Replay Gain features across components (asa@3fz.org)
- Implement Replay Gain feature with settings and metadata extraction
  (asa@3fz.org)
- update readme (asa@3fz.org)
- update readme (asa@3fz.org)
- Add missing closing tag for release 2.1.1 in metainfo.xml (asa@3fz.org)

* Sat Aug 09 2025 Asa DeGroff <asa@3fz.org> 2.1.1-1
- version bump and release notes (asa@3fz.org)
- bug fix for close button visibility in album art popup (asa@3fz.org)
- Implement hover-based scrolling animations for title and file path text in
  LibraryPane (asa@3fz.org)
- Add hover-based scrolling animation for context text in QueueHeader
  (asa@3fz.org)
- fixed background GPU usage in context text scrolling behavior by adding
  visibility checks and cleanup on destruction (asa@3fz.org)

* Thu Aug 07 2025 Asa DeGroff <asa@3fz.org> 2.1-1
- Refactor combo box interaction to use onActivated for better handling of user
  selections (asa@3fz.org)
- Refactor combo box item delegates for improved visibility and interaction;
  update model binding logic (asa@3fz.org)
- Improve close button size and responsiveness in QueuePopup (asa@3fz.org)
- update close icon in queue popup header to use proper size (asa@3fz.org)
- Refactor SettingsWindow layout and improve theme selection handling; ensure
  proper content width and remove unnecessary bindings (asa@3fz.org)
- Improve display text handling in SettingsWindow; ensure initial update on
  component completion (asa@3fz.org)
- Refactor theme detection and event handling in SettingsManager; update QML
  indicators for better clarity (asa@3fz.org)
- escape ampersands in metainfo (asa@3fz.org)
- metainfo updates (asa@3fz.org)
- metainfo updates (asa@3fz.org)
- add library editor screenshot (asa@3fz.org)
- update screenshots (asa@3fz.org)
- adjust preferred widths for ComboBox labels in SettingsWindow for better
  layout consistency (asa@3fz.org)
- version bump in settings window (asa@3fz.org)
- bump version to 2.1 and update changelog (asa@3fz.org)
- feat: switch to Artists tab when jumping to an artist from Playlists
  (asa@3fz.org)
- feat: refine QueueHeader layout by adjusting font size and enhancing
  scrolling animation for improved user experience (asa@3fz.org)
- feat: ensure black background is displayed when source is empty by clearing
  image sources (asa@3fz.org)
- feat: improve QueueHeader layout by enhancing context text visibility and
  removing redundant modified indicator (asa@3fz.org)
- feat: enhance queue management with undo functionality for source album and
  playlist info (asa@3fz.org)
- feat: enhance QueueHeader with seamless scrolling context text and improved
  display logic (asa@3fz.org)
- feat: add QueueHeader component and integrate it into NowPlayingPane and
  QueuePopup for improved queue display with contextual information
  (asa@3fz.org)
- feat: implement locale-aware sorting for artist retrieval in database manager
  (asa@3fz.org)
- feat: add file size retrieval for tracks in playlist manager from database
  and properly display all tags when viewing track info from a playlist
  (asa@3fz.org)
- style tweaks for buttons and headers in popup views, theme tweaks
  (asa@3fz.org)
- adjust margins for horizontal album browser to prevent corner overlap, tweak
  gradient stops (asa@3fz.org)
- feat: enhance layout mode change handling by saving and restoring album
  position (asa@3fz.org)
- feat: add automatic layout mode and update settings UI for layout selection
  (asa@3fz.org)
- fix: update drag handle icon source based on theme and text color
  (asa@3fz.org)
- button theming (asa@3fz.org)
- reduce animation duration of popup visibility for responsiveness
  (asa@3fz.org)
- fix: toggle visibility of album art and queue popups on click (asa@3fz.org)
- refactor: improve AlbumArtPopup layout for better responsiveness and sizing
  (asa@3fz.org)
- easing (asa@3fz.org)
- icon theming (asa@3fz.org)
- refactor: update QueuePopup structure for compact mode integration and
  improve visibility handling (asa@3fz.org)
- fix: toggle album art popup visibility on click (asa@3fz.org)
- refactor AlbumArtPopup to improve structure and integrate into LibraryPane
  for compact mode (asa@3fz.org)
- fix: improve layout and styling of AlbumArtPopup, update close button icon,
  and enhance album art container (asa@3fz.org)
- reduce horizontal album browser height by 20px (asa@3fz.org)
- fix: ensure consistent image smoothing and preserve aspect ratio for album
  images (asa@3fz.org)
- fix: enhance resource cleanup during component destruction and delegate
  recycling, implement GPU resource pooling and cleanup (asa@3fz.org)
- fix: prevent operations during component destruction and improve memory
  management (asa@3fz.org)
- feat: update album image loading to support higher resolution and improve
  rendering quality (asa@3fz.org)
- feat: removed special case snapping for smoother animation (asa@3fz.org)
- feat: add pixel alignment helper functions and improved pixel snapping for
  improved rendering (asa@3fz.org)
- cleanup removed property (asa@3fz.org)
- feat: simplify touchpad scrolling logic (asa@3fz.org)
- feat: enhance album jumping behavior with initialization handling and
  animation control (asa@3fz.org)
- feat: reduce thumbnail size to 256 for improved performance and caching
  (asa@3fz.org)
- feat: update thumbnail size to 256 for improved caching efficiency
  (asa@3fz.org)
- feat: enhance touchpad scrolling with visual center tracking and smooth index
  updates (asa@3fz.org)
- feat: optimize touchpad scrolling behavior by refining index updates and
  highlight range restoration (asa@3fz.org)
- feat: implement hysteresis for touchpad input in album selection to improve
  scrolling stability and reduce rapid switching (asa@3fz.org)
- moved the layer multisampling configuration from visualContainer to
  delegateItem so it's properly applied to the delegate and all children with
  transforms (asa@3fz.org)
- feat: enhance rendering quality with multisampling and improved antialiasing
  for album reflections (asa@3fz.org)
- feat: adjust reflection container size and source rectangle for improved
  visual quality in HorizontalAlbumBrowser (asa@3fz.org)
- feat: enhance image rendering quality by enabling smoothing and antialiasing
  for album items, simplify effects to remove redundancy (asa@3fz.org)
- feat: improve scaling and rendering quality for album items in
  HorizontalAlbumBrowser fpr razor sharp pixel alignment (asa@3fz.org)
- feat: update thumbnail size to 400 for improved image quality and adjust
  related caching logic (asa@3fz.org)
- feat: enhance album scaling effects for improved visual sharpness
  (asa@3fz.org)
- feat: implement scrolling track title with seamless wrap-around effect in
  LibraryPane (asa@3fz.org)
- feat: add dark mode support for undo icon and update QueuePopup and
  NowPlayingPane to use the new icon (asa@3fz.org)
- use light icons and add shadow effect to light icon buttons for improved
  visibility in light mode (asa@3fz.org)
- feat: add slide animations and fade effects for AlbumArtPopup and QueuePopup
  (asa@3fz.org)
- feat: update icon sources for repeat, shuffle, and queue buttons with
  consistent appearance and shadow effect (asa@3fz.org)
- feat: implement forceLightText property for consistent text color in dark
  backgrounds (asa@3fz.org)
- feat: add dark mode icons for close button and bomb, and implement playlist
  saved message in QueuePopup (asa@3fz.org)
- fix: update queue duration reference and improve icon handling in QueuePopup
  (asa@3fz.org)
- decrease opacity of compact now playing bar top border (asa@3fz.org)
- update styling of repeat and shuffle buttons in compact now playing bar with
  pill-shaped container and activated indicators to match now playing pane
  (asa@3fz.org)
- feat: add drop shadow to icon buttons for better contrast in light mode
  (asa@3fz.org)
- feat: add blurred background to compact now playing bar (asa@3fz.org)
- fix: adjust progress slider positioning for better alignment (asa@3fz.org)
- layout changes in CompactNowPlayingBar (asa@3fz.org)
- use custom buttons in compact mode and update minium width (asa@3fz.org)
- implement compact view components and add new layout mode (asa@3fz.org)
- implement system theme detection and update theme settings UI (asa@3fz.org)
- add dark mode icons and update references in LibraryPane (asa@3fz.org)
- theme tweaks for improved contrast in library (asa@3fz.org)
- enhance hover effects and icon animations in LibraryPane and PlaylistView
  (asa@3fz.org)
- add dark mode icons and update references in LibraryPane and PlaylistView
  (asa@3fz.org)
- refactor QueueActionDialog with theming and styling (asa@3fz.org)
- remove redundant MenuItem delegate from StyledMenu (asa@3fz.org)
- add StyledMenu and StyledMenuItem components for improved menu styling
  (asa@3fz.org)
- update theming for StyledMenu and StyledMenuSeparator components
  (asa@3fz.org)
- theming for text in queue list (asa@3fz.org)
- color tweaks (asa@3fz.org)
- theming for library editor window (asa@3fz.org)
- color tweaks (asa@3fz.org)
- svg tweaks (asa@3fz.org)
- style updates (asa@3fz.org)
- feat: add light mode icons for shuffle, repeat, and queue buttons
  (asa@3fz.org)
- feat: add clickable album title to jump to artist in LibraryPane
  (asa@3fz.org)
- fix for gradient overlay gap at edges (asa@3fz.org)
- refactor: optimize reflection and visibility calculations based on viewport
  width (asa@3fz.org)
- improve reflection rendering (asa@3fz.org)
- reduced horizontal album browser margins (asa@3fz.org)
- track info theme (asa@3fz.org)
- playlist view theme (asa@3fz.org)
- search bar light theme (asa@3fz.org)
- theme tweaks for carousel gradient (asa@3fz.org)
- light theme tweaks for improved contrast (asa@3fz.org)
- Implement light mode (asa@3fz.org)
- update changelog (asa@3fz.org)

* Thu Jul 31 2025 Asa DeGroff <asa@3fz.org> 2.0.2.1.1-1
- add pixpap icon to cmakelists (asa@3fz.org)

* Thu Jul 31 2025 Asa DeGroff <asa@3fz.org> 2.0.2.1-1
- 

* Thu Jul 31 2025 Asa DeGroff <asa@3fz.org> 2.0.2-1
- update icon renames for installation and adjust metainfo configuration
  (asa@3fz.org)
- undo icon rename (asa@3fz.org)
- update cmake lists (asa@3fz.org)
- add new esktop file and update icon renames for flatpak builds (asa@3fz.org)
- fixed typo (asa@3fz.org)
- update metainfo with new screenshots (asa@3fz.org)
- cleanup flatpak manifeset for local build (asa@3fz.org)
- version bump (asa@3fz.org)
- updated screenshots (asa@3fz.org)
- cleanup title info and console logging (asa@3fz.org)
- Updated metainfo for shorter description (asa@3fz.org)
- Update readme (asa@3fz.org)
- Set a minimum window width to fit all panes (asa@3fz.org)
- Refactor album grid layout to ensure minimum cell width and responsive column
  calculation (asa@3fz.org)
- minimum artists list width for 2 album covers (asa@3fz.org)
- updated icons (asa@3fz.org)
- layout changes for tiny window size (asa@3fz.org)
- Add window geometry settings and persistence to SettingsManager (asa@3fz.org)
- playlist view clipping fix (asa@3fz.org)
- capitalization in metainfo summary (asa@3fz.org)
- New icons (asa@3fz.org)

* Wed Jul 30 2025 Asa DeGroff <asa@3fz.org> 2.0.1.4-1
- Update MprisManager service name to conform to flatpak standard (asa@3fz.org)
- Update changelog (asa@3fz.org)

* Wed Jul 30 2025 Asa DeGroff <asa@3fz.org> 2.0.1.3-1
- update spec for rpm build (asa@3fz.org)

* Wed Jul 30 2025 Asa DeGroff <asa@3fz.org> 2.0.1.2-1
- manifest for local flatpak build (asa@3fz.org)
- skip installation of removed SVG icon (asa@3fz.org)
- added 64x64 icon and fixed typo (asa@3fz.org)
- add installation of metainfo file to CMakeLists (asa@3fz.org)
- fixes for metainfo and manifest (asa@3fz.org)
- update metainfo and manifest (asa@3fz.org)
- release notes in metainfo (asa@3fz.org)

* Tue Jul 29 2025 Asa DeGroff <asa@3fz.org> 2.0.1.1-1
- bump version in systeminfo (asa@3fz.org)

* Tue Jul 29 2025 Asa DeGroff <asa@3fz.org> 2.0.1-1
- Code cleanup for HorizontalAlbumBrowser: removed redundant reflection update
  logic, simplified reflection bindings, and simplified visibility check
  (asa@3fz.org)
- Improve reflection handling during scrolling in HorizontalAlbumBrowser
  (asa@3fz.org)
- Enhance reflection handling during recycling in HorizontalAlbumBrowser
  (asa@3fz.org)
- Improve album index retrieval and delegate recycling in
  HorizontalAlbumBrowser (asa@3fz.org)
- HorizontalAlbumBrowser memory management fixes: shared context menu instance
  outside of delegate revove Qt.Binding closure refactored ShaderEffectsSource
  cleanup Component.onDestruction cleaup ListVew.onRemove handler (asa@3fz.org)
- Enhance memory management during destruction in HorizontalAlbumBrowser by
  stopping timers and preventing operations when isDestroying (asa@3fz.org)
- Improve null checks and safety for album model access in
  HorizontalAlbumBrowser (asa@3fz.org)
- Enhance album art loading performance with dynamic cache sizing and improved
  memory management (asa@3fz.org)
- Refactor album art image provider to use asynchronous image responses and
  improve cache size for better performance (asa@3fz.org)
- prepare manifest for flathub and updated readme (asa@3fz.org)
- update flatpak manifest and metainfo (asa@3fz.org)
- remove unneeded debug logging (asa@3fz.org)
- Document Fedora 42+ requirement (asa@3fz.org)

* Mon Jul 28 2025 Asa DeGroff <asa@3fz.org> 2.0.0.1-1
- version bump for tito (asa@3fz.org)
- version for desktop file (asa@3fz.org)

* Mon Jul 28 2025 Asa DeGroff <asa@3fz.org>
- version bump for tito (asa@3fz.org)
- version for desktop file (asa@3fz.org)

* Mon Jul 28 2025 Asa DeGroff <asa@3fz.org>
- version for desktop file (asa@3fz.org)

* Mon Jul 28 2025 Asa DeGroff <asa@3fz.org>
- version for desktop file (asa@3fz.org)

* Mon Jul 28 2025 Asa DeGroff <asa@3fz.org> 2.0-1
- 

* Mon Jul 28 2025 Asa DeGroff <asa@3fz.org> 1.2.2-1
- metainfo (asa@3fz.org)
- add functionality to restore last selected playlist and update settings
  handling (asa@3fz.org)
- refactor restoreState logic to prioritize modified queue handling
  (asa@3fz.org)
- docs (asa@3fz.org)
- fixed typos (asa@3fz.org)
- docs (asa@3fz.org)
- updated icons with padding (asa@3fz.org)
- docs (asa@3fz.org)
- docs (asa@3fz.org)
- readme (asa@3fz.org)
- updated animation (asa@3fz.org)
- animation (asa@3fz.org)
- animation in readme (asa@3fz.org)
- docs (asa@3fz.org)
- docs (asa@3fz.org)
- Add playlist info handling to playback state management (asa@3fz.org)
- Refactor layout properties in LibraryPane and NowPlayingPane to prevent
  recursive rearrangement (asa@3fz.org)
- Resolve deprecation warnings related to event handling by adding mouse
  parameter to onResizeCompleted, onClicked, and onDoubleClicked functions
  (asa@3fz.org)
- Refactor database connection handling in scanInBackground and
  processAlbumArtInBackground for improved resource management (asa@3fz.org)
- Add playlist saved message functionality with timer and visual feedback
  (asa@3fz.org)
- docs (asa@3fz.org)
- Add album ID mapping and enhance track selection with O(1) lookups
  (asa@3fz.org)
- Optimize artist and track selection with O(1) lookups using index maps
  (asa@3fz.org)
- docs (asa@3fz.org)
- Enhance album and track caching with index maps for O(1) lookups and improve
  cleanup logic (asa@3fz.org)
- Refactor playlist refresh logic with a map to track unique playlists by
  modification time and sort them accordingly (asa@3fz.org)
- Improve layout and alignment for track list header and playlist buttons
  (asa@3fz.org)
- Add layout stabilization timer and improve track selector animations
  (asa@3fz.org)
- button styling (asa@3fz.org)
- Update SVG for improved compatibility (asa@3fz.org)
- Update playlist track addition dialog button styling (asa@3fz.org)
- Refactor playlist track layout for improved title and artist display
  (asa@3fz.org)
- Refactor track title display in LibraryPane for improved album and playlist
  differentiation (asa@3fz.org)
- Update track title display format for playlists and albums in LibraryPane
  (asa@3fz.org)
- Fix track item width calculation in LibraryPane to resolve null property
  errors (asa@3fz.org)
- Display artist and album names together in track labels with middle elision
  (asa@3fz.org)
- Improve playlist editing experience by auto-scrolling to newly added tracks
  (asa@3fz.org)
- Enhance track addition process by updating view immediately and allowing
  continuous selection (asa@3fz.org)
- layout tweaks for add track UI (asa@3fz.org)
- New interface for adding tracks in the playlist editor with responsive search
  (asa@3fz.org)
- readme updates (asa@3fz.org)
- Add library editor functionality and empty library placeholder (asa@3fz.org)
- Close settings and library editor windows when closing the main window
  (asa@3fz.org)
- Single digit track numbers are formatted without a leading zero in
  TrackListView (asa@3fz.org)
- Refine track filtering in getAllTracks, getTrackCount, and getTotalDuration
  to exclude empty titles and ensure artist names are valid. (asa@3fz.org)
- Fixed the root cause of segmentation faults on exit (it was delegate
  recycling in the carousel) (asa@3fz.org)
- Enhance destruction handling in HorizontalAlbumBrowser to prevent operations
  during cleanup, ensuring safe component destruction and avoiding potential
  crashes. (asa@3fz.org)
- Improve cleanup handling in main function and HorizontalAlbumBrowser to
  ensure safe destruction of components and prevent potential crashes.
  (asa@3fz.org)
- Refactor destruction handling in HorizontalAlbumBrowser and LibraryPane to
  improve cleanup logic and prevent potential crashes during component
  destruction. (asa@3fz.org)
- Enhance destruction handling in HorizontalAlbumBrowser to stop timers and
  animations, preventing updates during cleanup. (asa@3fz.org)
- Prevent operations during destruction in HorizontalAlbumBrowser, ensuring
  safe cleanup and avoiding potential crashes. (asa@3fz.org)
- Save playback state before application cleanup in main function (asa@3fz.org)
- Enhance cleanup logic in LibraryManager and AudioEngine, ensuring proper
  cancellation of album art processing and stopping playback before cleanup.
  Update MediaPlayer to use QPointer for safer object handling during delayed
  operations. (asa@3fz.org)
- Enhance DatabaseManager and LibraryManager with improved database connection
  handling and cleanup logic, fixes a bug where new tracks near the end of a
  logical batch were not inserted in the library (asa@3fz.org)
- Enhance DatabaseManager and LibraryManager with improved database connection
  handling and cleanup logic (asa@3fz.org)
- playback controls styling (asa@3fz.org)
- Enhance SettingsWindow.qml with custom Canvas indicators and improved popup
  handling for queue actions (asa@3fz.org)
- Refactor object creation in main.cpp to use QML engine parenting for
  automatic cleanup and enhance timer creation in LibraryPane.qml with proper
  parent handling (asa@3fz.org)
- Enhance destructors in AudioEngine, MediaPlayer, PlaylistManager, and
  SettingsManager for improved cleanup and logging (asa@3fz.org)
- Refactor content area in LibraryPane to improve layout structure and remove
  unnecessary scroll functionality (asa@3fz.org)
- Temporary commit for flatpak build testing (asa@3fz.org)
- Set preferred height for buttons in QueueActionDialog for consistent UI
  spacing in flatpak build (asa@3fz.org)
- Enhance playlist playback handling in PlaylistView and LibraryPane for
  improved keyboard navigation (asa@3fz.org)
- Enhance keyboard navigation in Library and Playlist views to support playlist
  selection and track navigation (asa@3fz.org)
- Add keyboard navigation for track selection in QueueListView (asa@3fz.org)
- easing (asa@3fz.org)
- Improve album art container positioning animations when toggling queue
  visibility for a smooth, continuous movement (asa@3fz.org)
- Refactor NowPlayingPane layout to use manual positioning and improve
  animation handling (asa@3fz.org)
- Update playPlaylistNext and playPlaylistLast to refresh shuffle order when
  enabled (asa@3fz.org)
- correctly implement random selection for initial start index for playlists
  (asa@3fz.org)
- remove broken flatpak mesa extensions (asa@3fz.org)
- Add QuickEffects component to Qt6 package requirements (asa@3fz.org)
- Update runtime version to 6.9 and enhance GPU support with Mesa extensions
  (asa@3fz.org)
- Update version to 2.0 and improve flatpak compatibility with library paths
  (asa@3fz.org)
- Fix playlist loading in flatpak with improved path resolution (asa@3fz.org)
- Add playlist folder management to PlaylistManager and UI (asa@3fz.org)
- refactor settings window (asa@3fz.org)
- Add album artist count functionality to LibraryManager and UI (asa@3fz.org)
- adjust gradient at carousel bottom to clear the album covers (asa@3fz.org)
- Add ctrl+z keyboard shortcut for undo functionality in NowPlayingPane
  (asa@3fz.org)
- Enhance QueueActionDialog with keyboard navigation and dynamic button focus
  management (asa@3fz.org)
- Add playPlaylist method to MediaPlayer and update LibraryPane for improved
  playlist handling (asa@3fz.org)
- Implement random track selection on shuffle enable in MediaPlayer
  (asa@3fz.org)
- Add context menu actions for playlist management in PlaylistView
  (asa@3fz.org)
- Implement sliding animation for tab transitions between Artists and Playlists
  in LibraryPane (asa@3fz.org)
- animated tab selector in LibraryPane (asa@3fz.org)
- Expose total duration calculation for "All Songs" virtual playlist to
  NowPlayingPane and add visibility conditions for queue actions (asa@3fz.org)
- Enhance virtual playlist support by adding name handling and updating UI
  messages in QueueListView (asa@3fz.org)
- Improve shuffle handling with bounds checking and update logic in MediaPlayer
  (asa@3fz.org)
- Refactor layout handling in NowPlayingPane for improved queue visibility
  animations (asa@3fz.org)
- Enhance queue action dialog handling for "All Songs" playlist and adjust
  visibility of play options (asa@3fz.org)
- Add playlist management features and enhance UI interactions (asa@3fz.org)
- Add playlist name validation and status messaging in edit mode (asa@3fz.org)
- Add library tab state management and restore selected album functionality
  (asa@3fz.org)
- Implement track selection after scrolling to artist or album in search
  results (asa@3fz.org)
- decrease save interval for lower latency carousel position saving
  (asa@3fz.org)
- spped up timer for updating selection and background image source on mouse
  wheel/keybaord navigation in carousel for responsiveness (asa@3fz.org)
- sort playlists newest first and update UI after editing to refresh timestamps
  (asa@3fz.org)
- Fix playlist filename handling to ensure proper extension for .m3u and .m3u8
  formats, fixes bug where a period in the title would cause a playlist not to
  load (asa@3fz.org)
- album title in tracklist header is clickable for carousel navigation
  (asa@3fz.org)
- Fix background image updating for mouse wheel and keybaord navigation by
  adding a timer to emit centerAlbumChanged signal after currentIndex updates
  (asa@3fz.org)
- update album thumbnail on carousel center change (asa@3fz.org)
- Enable shuffle mode to start playback from a random track on album play
  (asa@3fz.org)
- Add album navigation glow effect and improve opacity transitions in
  LibraryPane (asa@3fz.org)
- maintain list position when changing focus to search bar (asa@3fz.org)
- Expose repeat and shuffle modes to MPRIS (asa@3fz.org)
- further enhancements to track selection UX (asa@3fz.org)
- improve track selection experience (asa@3fz.org)
- Ensure focus management in QueueListView and NowPlayingPane for improved
  keyboard shortcut accessibility (asa@3fz.org)
- Add multi-track removal functionality in MediaPlayer and update UI components
  (asa@3fz.org)
- Implement track reordering functionality in MediaPlayer with drag-and-drop
  support in QueueListView (asa@3fz.org)
- Updated playlist veiw to correctly parse time from m3u files (asa@3fz.org)
- Add rename functionality for playlists with validation and UI updates
  (asa@3fz.org)
- Enhance memory management by implementing cache monitoring and adjustments in
  MediaPlayer, and optimize image handling in QML components to reduce memory
  usage. (asa@3fz.org)
- Memory management improvements for virtual track loading in MediaPlayer with
  connection handling (asa@3fz.org)
- Add track loading wait state management to MediaPlayer (asa@3fz.org)
- Add virtual playlist state management to playback system (asa@3fz.org)
- cleanup unnecessary logging (asa@3fz.org)
- Implement shuffle support for virtual playlist (asa@3fz.org)
- Enhance database thread safety and improve virtual playlist handling with
  detailed logging (asa@3fz.org)
- Implement Virtual Playlist Management and UI Integration (asa@3fz.org)
- Implement playlist deletion with confirmation dialog (asa@3fz.org)
- button styling (asa@3fz.org)
- Refactor track removal logic to capture and restore scroll position using
  Qt.callLater for improved timing (asa@3fz.org)
- Enhance UI responsiveness with hover animations and updated styling for trash
  can buttons in PlaybackControls, QueueListView, LibraryPane, and PlaylistView
  (asa@3fz.org)
- Improve scroll position handling during track reordering and removal in
  LibraryPane (asa@3fz.org)
- Preserve scroll position during track reordering and removal in LibraryPane
  (asa@3fz.org)
- Add updateShuffleOrder method and integrate it into playlist playback logic
  (asa@3fz.org)
- layout tweak (asa@3fz.org)
- Implement shuffle order generation in restore state and track loading
  functions (asa@3fz.org)
- Add StyledMenu and StyledMenuSeparator components; update context menus in
  LibraryPane and HorizontalAlbumBrowser (asa@3fz.org)
- Implement multi-selection functionality for track management with Ctrl and
  Shift modifiers (asa@3fz.org)
- reset edit button state on album switch (asa@3fz.org)
- update icons for white on dark (asa@3fz.org)
- Refactor drag-and-drop logic for track reordering to improve visual feedback
  and ensure proper state management (asa@3fz.org)
- Implement drag-and-drop functionality for track reordering in playlists
  (asa@3fz.org)
- Add playlist editing functionality with update, save, and cancel options
  (asa@3fz.org)
- Enhance playlist name generation to include track titles and handle empty
  cases (asa@3fz.org)
- enforce tab switch to Artists during search (asa@3fz.org)
- Enhance track retrieval for playlist compatibility in LibraryManager and
  MediaPlayer (asa@3fz.org)
- Fix duration handling in MediaPlayer and PlaylistManager to ensure
  consistency in seconds (asa@3fz.org)
- Fix duration handling in M3U file writing and reading to use seconds directly
  (asa@3fz.org)
- Refactor LibraryPane layout with custom tab selector for artists/playlists
  tabs inline with search bar (asa@3fz.org)
- Add PlaylistManager and integrate playlist functionality (asa@3fz.org)
- Fix shuffle to update shuffle index correctly (asa@3fz.org)
- Implement repeat and shuffle functionality (asa@3fz.org)
- Implement rapid skipping detection and debounce for queue list scrolling and
  album cover updates (asa@3fz.org)
- only show album art for current and upcoming tracks in vertical stack beside
  queue (asa@3fz.org)
- Refactor width calculation for queue display and simplify album art shrinking
  animation (asa@3fz.org)
- animation tweaks (asa@3fz.org)
- Triple stacked album cover display for queue list (asa@3fz.org)
- Refactor album play action handling to consistently respect user settings for
  queue modifications (asa@3fz.org)
- Add undo functionality for queue management in MediaPlayer (asa@3fz.org)
- Implement fixed cascading removal animation for queue items in QueueListView
  (asa@3fz.org)
- Enhance keyboard navigation by initializing focus on library pane and adding
  a timer for navigation readiness (asa@3fz.org)
- Add context menu and mouse button handling for album interactions in
  HorizontalAlbumBrowser (asa@3fz.org)
- Save and restore modified queues between restarts (asa@3fz.org)
- Add MouseArea to toggle queue visibility in NowPlayingPane (asa@3fz.org)
- Add SettingsManager and integrate settings into MediaPlayer and LibraryPane
  (asa@3fz.org)
- Enhance QueueActionDialog appearance with improved overlay, background, and
  button styles for better visual contrast (asa@3fz.org)
- Refactor QueueActionDialog positioning and enhance bounds checking for better
  user experience (asa@3fz.org)
- Add QueueActionDialog and integrate queue modification checks in album
  playback (asa@3fz.org)
- Adjust MediaPlayer track loading behavior to maintain paused state
  (asa@3fz.org)
- Enhance clear queue button appearance with updated hover color and border
  (asa@3fz.org)
- Fix for a clear queue bug: update MediaPlayer stop method to properly clear
  current track and queue (asa@3fz.org)
- Add clear queue functionality with animation and UI updates (asa@3fz.org)
- Implement track removal animation in QueueListView (asa@3fz.org)
- Implement track removal and playback at specific indices in MediaPlayer
  (asa@3fz.org)
- Add trash can icons and update QueueListView with remove button functionality
  (asa@3fz.org)
- Implement smooth scrolling for current track in QueueListView (asa@3fz.org)
- Add queueing options for tracks and albums with next/last options
  (asa@3fz.org)
- Add queue management features and update NowPlayingPane to display track
  information (asa@3fz.org)
- playback controls layout tweaks for centering and visual balance
  (asa@3fz.org)
- fix now playing pane layout to keep album art centered when queue is hidden
  (asa@3fz.org)
- building blocks of queue list UI (asa@3fz.org)
- icons (asa@3fz.org)
- Add Ctrl+I shortcut to toggle track info panel in LibraryPane (asa@3fz.org)
- Implement auto-selection of currently playing track in LibraryPane
  (asa@3fz.org)
- Replaced fixed stabilization timer with dynamic layout stabilization for
  programmatic scrolling in LibraryPane (asa@3fz.org)
- Improve scrolling behavior in LibraryPane with enhanced animation stability
  and position correction (asa@3fz.org)
- Implement crossfade effect for background images in BlurredBackground
  component (asa@3fz.org)
- Refactor keyboard event handling in HorizontalAlbumBrowser and sync selected
  album data in LibraryPane (asa@3fz.org)
- animate show/hide track info panel (asa@3fz.org)
- Enhance file path scrolling in LibraryPane with seamless wrap-around and
  improved animation timing (asa@3fz.org)
- Refactor track info panel layout for increased density (asa@3fz.org)
- Add file size retrieval and formatting in LibraryPane.qml (asa@3fz.org)
- Add close button icon and enhance file path scrolling in track info panel
  (asa@3fz.org)
- Added track info panel; implement context menu for track actions, and update
  track information display based on user interactions. (asa@3fz.org)
- cleanup (asa@3fz.org)
- simplified animation logic (asa@3fz.org)
- Enhance scrolling behavior in LibraryPane.qml; improve artist scrolling logic
  by ensuring layout updates before animations, and refine handling of negative
  positions to prevent errors during navigation. (asa@3fz.org)
- Enhance scrolling behavior in LibraryPane.qml; introduce
  isProgrammaticScrolling flag to manage animations during artist expansion and
  scrolling, ensuring smoother user experience and preventing conflicts during
  state changes. (asa@3fz.org)
- Refactor message handler in main.cpp for improved QML logging; streamline
  output and remove unnecessary file logging. Enhance LibraryPane.qml with
  additional logging for artist navigation and index mapping functions to aid
  debugging. (asa@3fz.org)
- Refactor artist expansion handling; remove expandedArtistsCache and
  streamline state updates for improved performance and responsiveness.
  (asa@3fz.org)
- Enhance state management during track restoration; prevent resetting to
  StoppedState when AudioEngine is Ready and adjust state based on playback
  status. (asa@3fz.org)
- Implement seek tracking in AudioEngine to improve accuracy of seek position
  during paused state (asa@3fz.org)
- Update artist navigation to use album artist for consistency in library pane
  (asa@3fz.org)
- Artist list navigation improvements 1. Refactored ensureArtistVisible:     -
  Now first ensures currentIndex is synchronized     - Uses ListView's
  positionViewAtIndex when possible     - Falls back to manual calculation only
  when necessary     - Properly checks if scrolling is actually needed before
  animating     - Lowered animation threshold from 1 to 0.5 pixels for smoother
  behavior   2. Improved position calculation:     - Fixed spacing calculations
  to match actual delegate layout     - Accounts for the exact container
  heights matching the delegate structure     - Removed unnecessary margins
  that could cause position drift   3. Enhanced startArtistNavigation:     -
  Now preserves existing currentIndex if valid     - Only resets to position 0
  when necessary     - Better synchronization with ListView state   4. Added
  delegate position tracking:     - Delegates now track their Y position for
  potential future use     - This can be leveraged for even more accurate
  positioning if needed (asa@3fz.org)
- Implement artist position calculation and synchronize ListView index during
  navigation; enhance scrolling accuracy and performance in LibraryPane.
  (asa@3fz.org)
- Enhance scroll handling in LibraryPane; track scroll bar dragging state to
  improve interaction and prevent conflicts during scrolling. Adjust flick
  deceleration and maximum velocity based on drag state for smoother user
  experience. (asa@3fz.org)
- Fix for snapping bug including refactoring artist scrolling logic in
  LibraryPane for improved accuracy and performance; calculate item positions
  based on expanded states and optimize viewport handling. (asa@3fz.org)
- Refactor visibility handling for album items in LibraryPane; remove buggy
  visibility timer and improve opacity change handling for better performance.
  (asa@3fz.org)
- Enhance album art image provider to support optional size in ID format and
  improve caching logic; update pixmap cache size to 256MB. Adjust
  HorizontalAlbumBrowser and LibraryPane for better scrolling performance and
  visibility management. Implement lazy image loading in LibraryPane.
  (asa@3fz.org)
- remove resolved todos (asa@3fz.org)
- Implement smooth scrolling for artist navigation with arrow keys
  (asa@3fz.org)
- Visibility helper and smooth scrolling refinement for track list navigation
  (asa@3fz.org)
- Enhance artist navigation by preventing expansion disruption and entering
  album navigation after search (asa@3fz.org)
- Refactor artist scrolling logic in handleSearchResult to ensure proper
  expansion before scrolling (asa@3fz.org)
- Implement smooth scrolling animation for artist list navigation (asa@3fz.org)
- Refactor artist scrolling logic in LibraryPane for improved layout handling
  (asa@3fz.org)
- Add special case for Opus file support in MetadataExtractor to properly
  support Opus album art (asa@3fz.org)
- Animate the scrolling for scrollToArtist (asa@3fz.org)
- Scroll to the selected artist when navigating to albums in LibraryPane
  (asa@3fz.org)
- Add keyboard navigation support for transferring focus between
  HorizontalAlbumBrowser and LibraryPane (asa@3fz.org)
- Enhance keyboard navigation and focus handling in LibraryPane and
  HorizontalAlbumBrowser (asa@3fz.org)
- Clear track selection on album change in LibraryPane (asa@3fz.org)
- Fix MPRIS play/pause functionality by pausing audio engine on track restore
  (asa@3fz.org)
- Refine album navigation logic to prevent unnecessary selection when no album
  is selected (asa@3fz.org)
- Add global keyboard shortcut for search and focus function in LibraryPane
  (asa@3fz.org)
- Improve MouseArea behavior in SearchBar for better focus handling
  (asa@3fz.org)
- desktop entry version bump (asa@3fz.org)
- update changelog (asa@3fz.org)

* Thu Jul 10 2025 Asa DeGroff <asa@3fz.org> 1.2.1-1
- Enhance canGoPrevious logic to allow restarting the first track when playing
  or paused when using MPRIS controls (asa@3fz.org)

* Tue Jul 08 2025 Asa DeGroff <asa@3fz.org> 1.2.0.1-1
- Revert "Automatic commit of package [mtoc] release [1.3-1]." (asa@3fz.org)
- Automatic commit of package [mtoc] release [1.3-1]. (asa@3fz.org)
- version bump, banner, and docs (asa@3fz.org)

* Tue Jul 08 2025 Asa DeGroff <asa@3fz.org>
- Revert "Automatic commit of package [mtoc] release [1.3-1]." (asa@3fz.org)
- Automatic commit of package [mtoc] release [1.3-1]. (asa@3fz.org)
- version bump, banner, and docs (asa@3fz.org)

* Tue Jul 08 2025 Asa DeGroff <asa@3fz.org> 1.2-1
- changelog and version bump (asa@3fz.org)
- cleanup (asa@3fz.org)
- Re-emit saved position to update progress bar during track loading and
  restoration (asa@3fz.org)
- Add duration handling to playback state saving and restoration (asa@3fz.org)
- Clear restoration state and saved position when loading tracks and albums
  (asa@3fz.org)
- Clear saved position when loading a new track, unless restoring state
  (asa@3fz.org)
- Refactor playback restoration logic and improve saved position handling
  (asa@3fz.org)
- Fix playback state restoration crashes on startup (asa@3fz.org)
- Enhance playback state restoration and improve progress slider behavior
  during seeking (asa@3fz.org)
- fix for playback resumption bug (asa@3fz.org)
- progress bar reflects restored state after restart (asa@3fz.org)
- Implement playback state persistence with save and restore functionality
  (asa@3fz.org)
- code cleanup and improved behavior of carousel at the edges of max width
  (asa@3fz.org)
- Optimize HorizontalAlbumBrowser for performance and clarity by caching view
  center and simplifying distance calculations (asa@3fz.org)
- cleaned up excessive debug output (asa@3fz.org)
- Fix for background album art processing and incremental database insertion
  (asa@3fz.org)
- Optimize memory management during scanning and add background processing for
  album art (asa@3fz.org)
- update changelog (asa@3fz.org)

* Sun Jun 29 2025 Asa DeGroff <asa@3fz.org> 1.1.6-1
- fix for buggy delegate recycling with memory cleanup and debounce for artist
  expansion in LibraryPane (asa@3fz.org)

* Sat Jun 28 2025 Asa DeGroff <asa@3fz.org> 1.1.5-1
- fix: remove layer effect to improve performance in LibraryPane (asa@3fz.org)
- fix: reset track list index on album change and remove layer effect to
  address rendering artifacts (asa@3fz.org)
- feat: enhance artist sorting by removing "The " prefix for better
  alphabetical order (asa@3fz.org)
- update changelog (asa@3fz.org)

* Sat Jun 21 2025 Asa DeGroff <asa@3fz.org> 1.1.4-1
- feat: add caching for artist albums to improve lookup performance in
  LibraryPane (asa@3fz.org)
- perf: optimize image handling and caching in BlurredBackground and
  LibraryPane components (asa@3fz.org)
- feat: improve keyboard navigation handling for album and track lists
  (asa@3fz.org)
- feat: enhance search functionality with enter key handling and improved
  keyboard navigation (asa@3fz.org)
- fix: search results now move to the top of the view (asa@3fz.org)
- feat: add layer effects to maintain rounded corners during scrolling in
  artist and track lists (asa@3fz.org)
- Automatic commit of package [mtoc] release [1.1.3-1]. (asa@3fz.org)
- feat: implement carousel position persistence between restarts in
  HorizontalAlbumBrowser (asa@3fz.org)
- cleanup (asa@3fz.org)
- Automatic commit of package [mtoc] release [1.1.2-1]. (asa@3fz.org)

* Thu Jun 19 2025 Asa DeGroff <asa@3fz.org> 1.1.3-1
- perf: improved performance in LibraryManager by replacing linear search with
  constant time lookup for artists and albums (asa@3fz.org)
- perf: implement parallelized metadata extraction and batch insertion in
  LibraryManager (asa@3fz.org)
- feat: add pagination and caching for album retrieval in LibraryManager
  (asa@3fz.org)
- fix: ensure proper memory management by setting LibraryManager as parent for
  TrackModel and AlbumModel instances (asa@3fz.org)
- Pruned librarymanager (asa@3fz.org)
- feat: implement carousel position persistence between restarts in
  HorizontalAlbumBrowser (asa@3fz.org)
- cleanup (asa@3fz.org)
- fix: enhance icon handling for Flatpak integration (asa@3fz.org)
- fix: add  proper display path mapping in UI for music folders when using
  flatpak (asa@3fz.org)
- Flatpak distribution preparation (asa@3fz.org)

* Wed Jun 18 2025 Asa DeGroff <asa@3fz.org> 1.1.2-1
- fix: adjust progress slider positioning and dimensions for better alignment
  (asa@3fz.org)

* Wed Jun 18 2025 Asa DeGroff <asa@3fz.org>
- fix: adjust progress slider positioning and dimensions for better alignment
  (asa@3fz.org)

* Tue Jun 17 2025 Asa DeGroff <asa@3fz.org> 1.1.1-1
- bump version and update readme (asa@3fz.org)

* Mon Jun 16 2025 Asa DeGroff <asa@3fz.org> 1.1-1
- This update includes new touchpad-specific navigation for the carousel that directly manipulates content with inertial flicking and snapping. 
* Sun Jun 15 2025 Asa DeGroff <asa@3fz.org> 1.0.9-1
- style: centered position of media control button icons (asa@3fz.org)
- now playing layout tweaks (asa@3fz.org)
- layout tweaks for higher density in the library pane (asa@3fz.org)
- refactor: simplify library header with minimal design and reduced dimensions
  (asa@3fz.org)
- cangelog (asa@3fz.org)
- update gitignore (asa@3fz.org)

* Sat Jun 14 2025 Asa DeGroff <asa@3fz.org> 1.0.8-1
- 

* Sat Jun 14 2025 Asa DeGroff <asa@3fz.org> 1.0.7-1
- Initial package

