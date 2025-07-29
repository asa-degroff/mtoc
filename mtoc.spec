Name:           mtoc
Version:        1.2.2
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
desktop-file-validate %{buildroot}%{_datadir}/applications/%{name}.desktop

%files
%license LICENSE
%doc README.md CHANGELOG.md
%{_bindir}/mtoc_app
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.*
%{_datadir}/pixmaps/%{name}.png

%changelog
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

