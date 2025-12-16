import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import Mtoc.Backend 1.0
import "Views/"
import "Components/"

ApplicationWindow {
    id: window
    width: SettingsManager.windowWidth
    height: SettingsManager.windowHeight
    x: SettingsManager.windowX >= 0 ? SettingsManager.windowX : Screen.width / 2 - width / 2
    y: SettingsManager.windowY >= 0 ? SettingsManager.windowY : Screen.height / 2 - height / 2
    minimumWidth: effectiveLayoutMode === SettingsManager.Compact ? 700 : 1050
    minimumHeight: 700
    visible: true
    title: MediaPlayer.currentTrack
        ? MediaPlayer.currentTrack.title + " - " + MediaPlayer.currentTrack.artist
        : SystemInfo.appName

    // Save state when window is closing
    onClosing: function(close) {
        console.log("Main.qml: Window closing event received");

        // Check if minimize to tray is enabled
        if (SettingsManager.minimizeToTray) {
            console.log("Main.qml: Minimize to tray is enabled, hiding window instead of closing");
            close.accepted = false;  // Prevent the window from actually closing
            window.hide();  // Just hide the window
            return;  // Don't execute the rest of the close logic
        }

        console.log("Main.qml: Closing application, saving playback state");

        // Close mini player window if it exists
        if (miniPlayerWindow) {
            miniPlayerWindow.close();
        }

        // Close all child windows first
        if (libraryPaneWide && libraryPaneWide.closeAllWindows) {
            libraryPaneWide.closeAllWindows();
        }
        if (libraryPaneCompact && libraryPaneCompact.closeAllWindows) {
            libraryPaneCompact.closeAllWindows();
        }

        if (MediaPlayer) {
            MediaPlayer.saveState();
        }

        // Explicitly quit the application to ensure it exits even when a system
        // tray icon is present (fixes Flatpak builds where tray keeps app alive)
        Qt.quit();
    }

    // Property to hold the current track metadata
    property var currentTrack: ({})

    // Mini player window instance
    property var miniPlayerWindow: null

    // Changelog popup visibility
    property bool showChangelogPopup: false
    
    // Functions to show/hide mini player
    function showMiniPlayer() {
        if (!miniPlayerWindow) {
            var component = Qt.createComponent("Views/MiniPlayerWindow.qml")
            if (component.status === Component.Ready) {
                // Create as a separate window, not a child of main window
                miniPlayerWindow = component.createObject(null)
                miniPlayerWindow.maximizeRequested.connect(hideMiniPlayer)
                console.log("Mini player window created and connected")
            } else if (component.status === Component.Error) {
                console.error("Error loading MiniPlayerWindow:", component.errorString())
                return
            }
        }
        
        if (miniPlayerWindow) {
            console.log("Showing mini player window")
            if (SettingsManager.miniPlayerHidesMainWindow) {
                window.hide()
            }
            miniPlayerWindow.show()
            miniPlayerWindow.raise()
            miniPlayerWindow.requestActivate()
        }
    }
    
    function hideMiniPlayer() {
        console.log("Hiding mini player and showing main window")
        if (miniPlayerWindow) {
            miniPlayerWindow.hide()
        }
        // Only show the main window if it was hidden (when miniPlayerHidesMainWindow is true)
        // or always show it if the setting is false
        if (!window.visible || !SettingsManager.miniPlayerHidesMainWindow) {
            window.show()
            window.raise()
            window.requestActivate()
        }
    }
    
    // Responsive layout properties
    property real libraryPaneRatio: mainContent.width < 1250 ? 0.55 : 0.45
    property real nowPlayingPaneRatio: 1.0 - libraryPaneRatio
    
    // Effective layout mode (considering automatic mode)
    property int effectiveLayoutMode: {
        if (SettingsManager.layoutMode === SettingsManager.Automatic) {
            return window.width < 1200 ? SettingsManager.Compact : SettingsManager.Wide
        }
        return SettingsManager.layoutMode
    }
    
    // Close popups and sync album position when layout mode changes
    onEffectiveLayoutModeChanged: {
        // Save current album position from the previously active browser
        var currentAlbum = null
        if (effectiveLayoutMode === SettingsManager.Wide) {
            // Switching TO wide, so compact was active before
            if (libraryPaneCompact) {
                currentAlbum = libraryPaneCompact.getCurrentAlbum()
            }
        } else {
            // Switching TO compact, so wide was active before
            if (libraryPaneWide) {
                currentAlbum = libraryPaneWide.getCurrentAlbum()
            }
        }
        
        // Save the album position if we found one
        if (currentAlbum && currentAlbum.id && LibraryManager) {
            LibraryManager.saveCarouselPosition(currentAlbum.id)
        }
        
        // Close popups
        if (compactNowPlayingBar) {
            compactNowPlayingBar.queuePopupVisible = false
            compactNowPlayingBar.albumArtPopupVisible = false
        }
        
        // Restore position in the new layout after a short delay
        Qt.callLater(function() {
            if (effectiveLayoutMode === SettingsManager.Wide) {
                if (libraryPaneWide) {
                    libraryPaneWide.restoreAlbumPosition()
                }
            } else {
                if (libraryPaneCompact) {
                    libraryPaneCompact.restoreAlbumPosition()
                }
            }
        })
    }
    
    // Timer to debounce window geometry changes
    Timer {
        id: saveGeometryTimer
        interval: 500  // Wait 500ms after resize/move stops
        onTriggered: {
            SettingsManager.windowWidth = window.width
            SettingsManager.windowHeight = window.height
            SettingsManager.windowX = window.x
            SettingsManager.windowY = window.y
            //console.log("Main.qml: Saved window geometry - " + window.width + "x" + window.height + " at " + window.x + "," + window.y)
        }
    }
    
    // Save window dimensions when they change
    onWidthChanged: saveGeometryTimer.restart()
    onHeightChanged: saveGeometryTimer.restart()
    onXChanged: saveGeometryTimer.restart()
    onYChanged: saveGeometryTimer.restart()
    
    // Resize handler for deferred resizing
    ResizeHandler {
        id: resizeHandler
        resizeDelay: 250  // Wait 250ms after resize stops
        
        onResizeStarted: {
            // During resize, we just clip/letterbox the content
            // No need to hide anything
        }
        
        onResizeCompleted: function(newWidth, newHeight) {
            // Apply new dimensions to content
            mainContent.width = newWidth
            mainContent.height = newHeight
            
            // Force garbage collection after resize
            gc()
        }
    }
    
    // Black background for letterboxing effect
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        z: -1
    }
    
    // Viewport container that clips or letterboxes content
    Item {
        id: viewportContainer
        anchors.fill: parent
        clip: true  // Clip content when window is smaller
        
        // Main content container - stays at deferred size
        Item {
            id: mainContent
            width: resizeHandler.deferredWidth
            height: resizeHandler.deferredHeight
            
            // Center content when window is larger (letterbox)
            x: parent.width > width ? (parent.width - width) / 2 : 0
            y: parent.height > height ? (parent.height - height) / 2 : 0
        
        // Layout based on mode
        Item {
            anchors.fill: parent
            
            // Wide layout (default)
            RowLayout {
                anchors.fill: parent
                spacing: 0
                visible: effectiveLayoutMode === SettingsManager.Wide

                // Library Pane
                LibraryPane {
                    id: libraryPaneWide
                    Layout.fillWidth: true
                    Layout.preferredWidth: mainContent.width * libraryPaneRatio
                    Layout.fillHeight: true
                }

                // Now Playing Pane
                NowPlayingPane {
                    id: nowPlayingPane
                    Layout.fillWidth: true
                    Layout.preferredWidth: mainContent.width * nowPlayingPaneRatio
                    Layout.fillHeight: true

                    // Pass reference to library pane for navigation
                    libraryPane: libraryPaneWide

                    Component.onCompleted: {
                        console.log("NowPlayingPane added to Main.qml");
                    }

                    // Changelog popup for wide mode - parented to now playing pane
                    ChangelogPopup {
                        id: changelogPopupWide
                        parent: nowPlayingPane
                        isOpen: window.showChangelogPopup && effectiveLayoutMode === SettingsManager.Wide
                        onClosed: {
                            window.showChangelogPopup = false
                            SettingsManager.lastSeenChangelogVersion = SystemInfo.appVersion
                        }
                    }
                }
            }
            
            // Compact layout
            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                visible: effectiveLayoutMode === SettingsManager.Compact
                
                // Library Pane (full width)
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    
                    LibraryPane {
                        id: libraryPaneCompact
                        anchors.fill: parent
                    }
                    
                    // Queue popup for compact mode - parented to library pane container
                    QueuePopup {
                        id: queuePopup
                        parent: parent
                        queueModel: MediaPlayer.queue
                        currentPlayingIndex: MediaPlayer.currentQueueIndex
                        isOpen: compactNowPlayingBar.queuePopupVisible
                        onClosed: compactNowPlayingBar.queuePopupVisible = false
                    }
                    
                    // Album art popup for compact mode - parented to library pane container
                    AlbumArtPopup {
                        id: albumArtPopup
                        parent: parent
                        albumArtUrl: compactNowPlayingBar.albumArtUrl
                        isOpen: compactNowPlayingBar.albumArtPopupVisible
                        onClosed: compactNowPlayingBar.albumArtPopupVisible = false
                    }

                    // Lyrics popup for compact mode - parented to library pane container
                    LyricsPopup {
                        id: lyricsPopup
                        parent: parent
                        lyricsText: MediaPlayer.currentTrackLyrics
                        isOpen: compactNowPlayingBar.lyricsPopupVisible
                        onClosed: compactNowPlayingBar.lyricsPopupVisible = false
                    }

                    // Changelog popup - parented to library pane container
                    ChangelogPopup {
                        id: changelogPopupCompact
                        parent: parent
                        isOpen: window.showChangelogPopup && effectiveLayoutMode === SettingsManager.Compact
                        onClosed: {
                            window.showChangelogPopup = false
                            SettingsManager.lastSeenChangelogVersion = SystemInfo.appVersion
                        }
                    }
                }
                
                // Compact Now Playing Bar
                CompactNowPlayingBar {
                    id: compactNowPlayingBar
                    Layout.fillWidth: true
                    Layout.preferredHeight: 90
                    
                    onAlbumTitleClicked: function(artistName, albumTitle) {
                        libraryPaneCompact.jumpToAlbum(artistName, albumTitle)
                    }
                    
                    onArtistClicked: function(artistName) {
                        libraryPaneCompact.jumpToArtist(artistName)
                    }
                }
            }
        }
        }  // mainContent
    }  // viewportContainer

    // Function to format duration in seconds to MM:SS format
    function formatDuration(seconds) {
        var minutes = Math.floor(seconds / 60);
        var remainingSeconds = seconds % 60;
        return minutes + ":" + (remainingSeconds < 10 ? "0" : "") + remainingSeconds;
    }

    // Function to compare semantic version strings
    // Returns: 1 if v1 > v2, -1 if v1 < v2, 0 if equal
    function compareVersions(v1, v2) {
        if (!v1) return -1;  // Empty/null v1 is less than anything
        if (!v2) return 1;   // Empty/null v2 means v1 is greater

        var parts1 = v1.split('.').map(function(p) { return parseInt(p) || 0; });
        var parts2 = v2.split('.').map(function(p) { return parseInt(p) || 0; });

        for (var i = 0; i < Math.max(parts1.length, parts2.length); i++) {
            var a = i < parts1.length ? parts1[i] : 0;
            var b = i < parts2.length ? parts2[i] : 0;

            if (a > b) return 1;
            if (a < b) return -1;
        }

        return 0;  // Versions are equal
    }

    // Function to check if minor version has changed (major.minor)
    // Returns true if major or minor version changed, false if only patch changed
    // Examples:
    //   - 2.2.0 -> 2.3.1 returns true (minor changed)
    //   - 2.3.0 -> 2.3.1 returns false (only patch changed)
    //   - 2.3.0 -> 3.0.0 returns true (major changed)
    function hasMinorVersionChanged(oldVersion, newVersion) {
        if (!oldVersion) return true;  // First launch, show changelog
        if (!newVersion) return false;  // No new version, don't show

        var oldParts = oldVersion.split('.').map(function(p) { return parseInt(p) || 0; });
        var newParts = newVersion.split('.').map(function(p) { return parseInt(p) || 0; });

        // Check major version (index 0)
        var oldMajor = oldParts.length > 0 ? oldParts[0] : 0;
        var newMajor = newParts.length > 0 ? newParts[0] : 0;
        if (oldMajor !== newMajor) return true;

        // Check minor version (index 1)
        var oldMinor = oldParts.length > 1 ? oldParts[1] : 0;
        var newMinor = newParts.length > 1 ? newParts[1] : 0;
        if (oldMinor !== newMinor) return true;

        // Only patch version changed (or no change at all)
        return false;
    }

    // Timer to show changelog popup after a delay on first launch
    Timer {
        id: changelogTimer
        interval: 500  // 500ms delay for smooth startup
        running: false
        repeat: false
        onTriggered: {
            console.log("Main.qml: Showing changelog popup");
            window.showChangelogPopup = true;
        }
    }

    // Timer to check rendering info after window is ready
    Timer {
        id: renderInfoTimer
        interval: 100
        running: true
        repeat: false
    }
    
    // Function to ensure window is visible on screen
    function ensureWindowVisible() {
        // Check if window position is valid and visible
        var screenGeometry = Qt.application.screens[0];
        var screenWidth = screenGeometry.width;
        var screenHeight = screenGeometry.height;
        
        // Ensure at least 100 pixels of the window are visible
        var minVisible = 100;
        
        // Check horizontal bounds
        if (window.x + minVisible > screenWidth) {
            window.x = screenWidth - window.width / 2;
        } else if (window.x + window.width < minVisible) {
            window.x = minVisible - window.width / 2;
        }
        
        // Check vertical bounds
        if (window.y + minVisible > screenHeight) {
            window.y = screenHeight - window.height / 2;
        } else if (window.y < 0) {
            window.y = 0;
        }
        
        // Ensure window fits on screen
        if (window.width > screenWidth) {
            window.width = screenWidth - 50;
        }
        if (window.height > screenHeight) {
            window.height = screenHeight - 50;
        }
    }
    
    // Restore playback state when application is fully loaded
    Component.onCompleted: {
        //console.log("Main.qml: Window loaded");

        // Ensure window is visible on screen
        ensureWindowVisible();

        // Give focus to library pane for keyboard navigation
        if (effectiveLayoutMode === SettingsManager.Wide) {
            libraryPaneWide.forceActiveFocus();
        } else {
            libraryPaneCompact.forceActiveFocus();
        }

        // Wait for MediaPlayer to be ready before restoring state
        if (MediaPlayer.isReady) {
            console.log("Main.qml: MediaPlayer is ready, restoring playback state");
            MediaPlayer.restoreState();
        } else {
            console.log("Main.qml: MediaPlayer not ready yet, waiting...");
            // MediaPlayer will handle restoration when it becomes ready
            MediaPlayer.restoreState();
        }

        // Check if we should show the changelog popup
        var lastSeenVersion = SettingsManager.lastSeenChangelogVersion;
        var currentVersion = SystemInfo.appVersion;

        console.log("Main.qml: Version check - Last seen:", lastSeenVersion, "Current:", currentVersion);

        // Show changelog if:
        // 1. --show-changelog or --changelog flag is present (for testing)
        // 2. Major or minor version changed (not just patch)
        // 3. First launch (no version recorded)
        if (SystemInfo.forceShowChangelog) {
            console.log("Main.qml: --show-changelog flag detected, forcing changelog display");
            changelogTimer.start();
        } else if (hasMinorVersionChanged(lastSeenVersion, currentVersion)) {
            console.log("Main.qml: Minor version changed, will show changelog");
            changelogTimer.start();
        } else {
            console.log("Main.qml: Patch-only update or same version, not showing changelog");
        }
    }
    
    // Global keyboard shortcut for search
    Shortcut {
        sequence: StandardKey.Find  // Ctrl+F on Linux, Cmd+F on macOS
        onActivated: {
            if (effectiveLayoutMode === SettingsManager.Wide) {
                libraryPaneWide.focusSearchBar()
            } else {
                libraryPaneCompact.focusSearchBar()
            }
        }
    }
    
}
