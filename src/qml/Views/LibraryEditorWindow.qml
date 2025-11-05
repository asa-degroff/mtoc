import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Dialogs
import Mtoc.Backend 1.0

ApplicationWindow {
    id: libraryEditorWindow
    title: "Edit Library - mtoc"
    width: 600
    height: 800

    flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowMinimizeButtonHint | Qt.WindowMaximizeButtonHint | Qt.WindowCloseButtonHint

    color: Theme.backgroundColor

    // Track whether we're extracting metadata (vs. regular scan)
    property bool isExtractingMetadata: false

    // Folder dialog for adding music folders
    FolderDialog {
        id: folderDialog
        title: "Select Music Folder"
        acceptLabel: "Add Folder"
        rejectLabel: "Cancel"
        
        property string displayPath: ""
        
        onAccepted: {
            console.log("FolderDialog accepted");
            console.log("selectedFolder:", selectedFolder);
            console.log("selectedFolder.toString():", selectedFolder.toString());
            console.log("currentFolder:", currentFolder);
            console.log("currentFolder.toString():", currentFolder.toString());
            
            var path = selectedFolder.toString();
            // Remove the file:// prefix if present
            if (path.startsWith("file://")) {
                path = path.substring(7);
            }
            
            console.log("Path after processing:", path);
            
            // Try to get the display name from the folder dialog
            // In Flatpak, the selectedFolder might be a portal path
            // but the dialog should know what the user actually selected
            var displayName = path;
            
            // Check if this looks like a portal path
            if (path.startsWith("/run/flatpak/doc/") || path.startsWith("/run/user/")) {
                // Try to extract a more meaningful display name
                // Portal paths often contain a hash followed by the original folder name
                var parts = path.split("/");
                if (parts.length > 0) {
                    // Get the last part as a fallback display name
                    displayName = parts[parts.length - 1];
                    // If it looks like a hash, try the second to last
                    if (displayName.match(/^[a-f0-9]{8,}$/)) {
                        displayName = parts[parts.length - 2] || displayName;
                    }
                }
                console.log("Detected portal path, using display name:", displayName);
            }
            
            if (path.length > 0) {
                // Add the folder to LibraryManager
                LibraryManager.addMusicFolder(path);
            } else {
                console.error("Could not determine selected folder path");
            }
        }
    }
    
    // Folder dialog for adding playlist folders
    FolderDialog {
        id: playlistFolderDialog
        title: "Select Playlist Folder"
        acceptLabel: "Add Folder"
        rejectLabel: "Cancel"
        
        onAccepted: {
            var path = selectedFolder.toString();
            // Remove the file:// prefix if present
            if (path.startsWith("file://")) {
                path = path.substring(7);
            }
            
            if (path.length > 0) {
                PlaylistManager.addPlaylistFolder(path);
            }
        }
    }

    // Handle scan completion to reset extraction flag
    Connections {
        target: LibraryManager

        function onScanCompleted() {
            isExtractingMetadata = false;
        }

        function onScanCancelled() {
            isExtractingMetadata = false;
        }
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth

        ColumnLayout {
            width: parent.availableWidth
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            anchors.topMargin: 20
            anchors.bottomMargin: 20
            spacing: 16
            
            // Title
            Label {
                text: "Library Management"
                font.pixelSize: 20
                font.bold: true
                color: Theme.primaryText
                Layout.fillWidth: true
            }
            
            // Library statistics section
            Rectangle {
                Layout.fillWidth: true
                height: 100
                color: Theme.panelBackground
                radius: 4
                
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 24

                    // Album Artist count
                    Column {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 4

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: LibraryManager.albumArtistCount
                            font.pixelSize: 32
                            font.bold: true
                            color: Theme.primaryText
                        }

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Album Artists"
                            font.pixelSize: 14
                            color: Theme.secondaryText
                        }
                    }
                    
                    // Artists count
                    Column {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 4
                        
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: LibraryManager.artistCount
                            font.pixelSize: 32
                            font.bold: true
                            color: Theme.primaryText
                        }
                        
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Artists"
                            font.pixelSize: 14
                            color: Theme.secondaryText
                        }
                    }
                    
                    // Albums count
                    Column {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 4
                        
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: LibraryManager.albumCount
                            font.pixelSize: 32
                            font.bold: true
                            color: Theme.primaryText
                        }
                        
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Albums"
                            font.pixelSize: 14
                            color: Theme.secondaryText
                        }
                    }
                    
                    // Tracks count
                    Column {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 4
                        
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: LibraryManager.trackCount
                            font.pixelSize: 32
                            font.bold: true
                            color: Theme.primaryText
                        }
                        
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Tracks"
                            font.pixelSize: 14
                            color: Theme.secondaryText
                        }
                    }
                    
                    // Scan progress
                    Column {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 150
                        Layout.maximumWidth: 200
                        spacing: 4
                        visible: LibraryManager.scanning
                        
                        ProgressBar {
                            width: parent.width
                            value: LibraryManager.scanProgress / 100.0
                            from: 0
                            to: 1
                        }
                        
                        Label {
                            width: parent.width
                            text: "Scanning: " + LibraryManager.scanProgressText
                            font.pixelSize: 12
                            color: Theme.secondaryText
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }
            
            // Music folders section
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: musicFoldersLayout.implicitHeight + 24
                color: Theme.panelBackground
                radius: 4

                ColumnLayout {
                    id: musicFoldersLayout
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8
                    
                    RowLayout {
                        Layout.fillWidth: true
                        
                        Label {
                            text: "Music Folders"
                            font.pixelSize: 16
                            font.bold: true
                            color: Theme.primaryText
                        }
                        
                        Item { Layout.fillWidth: true }
                        
                        Button {
                            text: "Add Folder"
                            implicitHeight: 32
                            implicitWidth: 100
                            
                            background: Rectangle {
                                color: parent.down ? Theme.linkColor : parent.hovered ? Theme.selectedBackground : Theme.inputBackground
                                border.color: parent.hovered ? Theme.linkColor : Theme.borderColor
                                border.width: 1
                                radius: 4
                                
                                Behavior on color {
                                    ColorAnimation { duration: 150 }
                                }
                            }
                            
                            contentItem: Text {
                                text: parent.text
                                color: parent.hovered ? Theme.primaryText : Theme.secondaryText
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                font.pixelSize: 13
                            }
                            
                            onClicked: folderDialog.open()
                        }
                    }
                    
                    // Container with rounded corners for the ListView
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 150
                        
                        Rectangle {
                            id: listBackground
                            anchors.fill: parent
                            color: Theme.backgroundColor
                            radius: 4
                        }
                        
                        ListView {
                            anchors.fill: parent
                            anchors.margins: 1  // Small margin to show the rounded corners
                            clip: true
                            model: LibraryManager.musicFoldersDisplay
                            
                            delegate: Rectangle {
                                width: ListView.view.width
                                height: 48  // Increased height for better spacing
                                color: index % 2 === 0 ? Theme.inputBackground : Theme.inputBackgroundHover
                                radius: index === 0 ? 3 : 0  // Round top corners for first item
                                
                                // Special handling for first and last items
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: parent.radius
                                    color: parent.color
                                    visible: index === 0  // Only for first item to fill the corner gap
                                }
                            
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                anchors.topMargin: 0
                                anchors.bottomMargin: 0
                                spacing: 12
                                
                                Label {
                                    text: modelData
                                    color: Theme.primaryText
                                    elide: Text.ElideLeft
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter  // Ensure vertical centering
                                }
                                
                                Button {
                                    text: "Remove"
                                    Layout.alignment: Qt.AlignVCenter  // Ensure vertical centering
                                    implicitHeight: 32
                                    implicitWidth: 80
                                    
                                    background: Rectangle {
                                        color: parent.down ? Theme.errorText : parent.hovered ? Qt.darker(Theme.errorText, 1.2) : Theme.inputBackground
                                        border.color: parent.hovered ? Theme.errorText : Theme.borderColor
                                        border.width: 1
                                        radius: 4
                                        
                                        Behavior on color {
                                            ColorAnimation { duration: 150 }
                                        }
                                    }
                                    
                                    contentItem: Text {
                                        text: parent.text
                                        color: parent.hovered ? Theme.primaryText : Theme.secondaryText
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        font.pixelSize: 13
                                    }
                                    
                                    onClicked: {
                                        // Remove using the display path - it will be converted to canonical path internally
                                        LibraryManager.removeMusicFolder(modelData);
                                    }
                                }
                            }
                        }
                        
                        ScrollIndicator.vertical: ScrollIndicator { }
                    }
                }
                }
            }
            
            // Playlist folders section
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: playlistFoldersLayout.implicitHeight + 24
                color: Theme.panelBackground
                radius: 4

                ColumnLayout {
                    id: playlistFoldersLayout
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8
                    
                    RowLayout {
                        Layout.fillWidth: true
                        
                        Label {
                            text: "Playlist Folders"
                            font.pixelSize: 16
                            font.bold: true
                            color: Theme.primaryText
                        }
                        
                        Item { Layout.fillWidth: true }
                        
                        Button {
                            text: "Add Folder"
                            implicitHeight: 32
                            implicitWidth: 100
                            
                            background: Rectangle {
                                color: parent.down ? Theme.linkColor : parent.hovered ? Theme.selectedBackground : Theme.inputBackground
                                border.color: parent.hovered ? Theme.linkColor : Theme.borderColor
                                border.width: 1
                                radius: 4
                                
                                Behavior on color {
                                    ColorAnimation { duration: 150 }
                                }
                            }
                            
                            contentItem: Text {
                                text: parent.text
                                color: parent.hovered ? Theme.primaryText : Theme.secondaryText
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                font.pixelSize: 13
                            }
                            
                            onClicked: playlistFolderDialog.open()
                        }
                    }
                    
                    // Container with rounded corners for the ListView
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 150
                        
                        Rectangle {
                            id: playlistListBackground
                            anchors.fill: parent
                            color: Theme.backgroundColor
                            radius: 4
                        }
                        
                        ListView {
                            anchors.fill: parent
                            anchors.margins: 1  // Small margin to show the rounded corners
                            clip: true
                            model: PlaylistManager.playlistFoldersDisplay
                            
                            delegate: Rectangle {
                                width: ListView.view.width
                                height: 48  // Increased height for better spacing
                                color: index % 2 === 0 ? Theme.inputBackground : Theme.inputBackgroundHover
                                radius: index === 0 ? 3 : 0  // Round top corners for first item
                                
                                // Special handling for first and last items
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: parent.radius
                                    color: parent.color
                                    visible: index === 0  // Only for first item to fill the corner gap
                                }
                            
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                anchors.topMargin: 0
                                anchors.bottomMargin: 0
                                spacing: 12
                                
                                // Radio button / star to indicate default
                                Rectangle {
                                    width: 20
                                    height: 20
                                    radius: 10
                                    color: PlaylistManager.playlistFolders[index] === PlaylistManager.defaultPlaylistFolder ? Theme.selectedBackground : Theme.inputBackground
                                    border.color: PlaylistManager.playlistFolders[index] === PlaylistManager.defaultPlaylistFolder ? Theme.linkColor : Theme.borderColor
                                    border.width: 1
                                    Layout.alignment: Qt.AlignVCenter
                                    
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 8
                                        height: 8
                                        radius: 4
                                        color: Theme.primaryText
                                        visible: PlaylistManager.playlistFolders[index] === PlaylistManager.defaultPlaylistFolder
                                    }
                                    
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            PlaylistManager.setDefaultPlaylistFolder(PlaylistManager.playlistFolders[index])
                                        }
                                    }
                                }
                                
                                Label {
                                    text: modelData
                                    color: Theme.primaryText
                                    elide: Text.ElideLeft
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter  // Ensure vertical centering
                                }
                                
                                Label {
                                    text: PlaylistManager.playlistFolders[index] === PlaylistManager.defaultPlaylistFolder ? "Default" : ""
                                    color: Theme.selectedBackground
                                    font.pixelSize: 12
                                    font.italic: true
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                
                                Button {
                                    text: "Remove"
                                    Layout.alignment: Qt.AlignVCenter  // Ensure vertical centering
                                    implicitHeight: 32
                                    implicitWidth: 80
                                    enabled: PlaylistManager.playlistFolders[index] !== PlaylistManager.defaultPlaylistFolder
                                    opacity: enabled ? 1.0 : 0.5
                                    
                                    background: Rectangle {
                                        color: parent.enabled ? (parent.down ? Theme.errorText : parent.hovered ? Qt.darker(Theme.errorText, 1.2) : Theme.inputBackground) : Theme.inputBackground
                                        border.color: parent.enabled ? (parent.hovered ? Theme.errorText : Theme.borderColor) : Theme.borderColor
                                        border.width: 1
                                        radius: 4
                                        
                                        Behavior on color {
                                            ColorAnimation { duration: 150 }
                                        }
                                    }
                                    
                                    contentItem: Text {
                                        text: parent.text
                                        color: parent.enabled ? (parent.hovered ? Theme.primaryText : Theme.secondaryText) : Theme.tertiaryText
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        font.pixelSize: 13
                                    }
                                    
                                    onClicked: {
                                        PlaylistManager.removePlaylistFolder(PlaylistManager.playlistFolders[index]);
                                    }
                                }
                            }
                        }
                        
                        ScrollIndicator.vertical: ScrollIndicator { }
                    }
                }
                }
            }
            
            // Info text and action buttons
            Rectangle {
                Layout.fillWidth: true
                color: Theme.panelBackground
                radius: 4
                Layout.preferredHeight: scanButtonsLayout.implicitHeight + 24

                ColumnLayout {
                    id: scanButtonsLayout
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8
                    
                    Label {
                        text: "Scan your library to update the database with any new or deleted files.\nExtract metadata if you have made changes to tags or artwork, to update the library with your changes.\nAudio files are treated as read-only; changes made here only affect the database."
                        color: Theme.secondaryText
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Button {
                            text: "Reset Library"
                            implicitHeight: 32
                            implicitWidth: 110
                            enabled: !LibraryManager.scanning

                            background: Rectangle {
                                color: parent.enabled ? (parent.down ? "#cc0000" : parent.hovered ? "#aa0000" : Theme.inputBackground) : Theme.inputBackground
                                border.color: parent.enabled && parent.hovered ? "#cc0000" : Theme.borderColor
                                border.width: 1
                                radius: 4

                                Behavior on color {
                                    ColorAnimation { duration: 150 }
                                }
                            }

                            contentItem: Text {
                                text: parent.text
                                color: parent.enabled ? (parent.hovered ? "#ff6666" : Theme.secondaryText) : Theme.disabledText
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                font.pixelSize: 13
                            }

                            ToolTip.text: "Clear library database"
                            ToolTip.visible: hovered
                            ToolTip.delay: 500

                            onClicked: {
                                // TODO: Add confirmation dialog
                                LibraryManager.resetLibrary();
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Button {
                            id: extractMetadataButton
                            text: isExtractingMetadata && LibraryManager.scanning ? "Cancel Extraction" : "Extract Metadata"
                            implicitHeight: 32
                            implicitWidth: 150
                            enabled: !LibraryManager.scanning || isExtractingMetadata

                            background: Rectangle {
                                color: parent.down ? "#00cc66" : parent.hovered ? "#00aa55" : "#00994d"
                                border.color: parent.hovered ? "#00ff80" : "#00cc66"
                                border.width: 1
                                radius: 4
                                opacity: parent.enabled ? 1.0 : 0.5

                                Behavior on color {
                                    ColorAnimation { duration: 150 }
                                }
                            }

                            contentItem: Text {
                                text: parent.text
                                color: Theme.primaryText
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                font.pixelSize: 13
                                font.bold: true
                            }

                            ToolTip.text: isExtractingMetadata && LibraryManager.scanning
                                ? "Cancel metadata extraction"
                                : "Re-extract metadata from all audio files"
                            ToolTip.visible: hovered
                            ToolTip.delay: 500

                            onClicked: {
                                if (LibraryManager.scanning && isExtractingMetadata) {
                                    // Cancel the extraction
                                    LibraryManager.cancelScan();
                                    isExtractingMetadata = false;
                                } else {
                                    // Start metadata extraction
                                    isExtractingMetadata = true;
                                    LibraryManager.setForceMetadataUpdate(true);
                                    LibraryManager.startScan();
                                }
                            }
                        }

                        Button {
                            id: scanLibraryButton
                            text: !isExtractingMetadata && LibraryManager.scanning ? "Cancel Scan" : "Scan Library"
                            implicitHeight: 32
                            implicitWidth: 120
                            enabled: !LibraryManager.scanning || !isExtractingMetadata

                            background: Rectangle {
                                color: parent.down ? "#00cc66" : parent.hovered ? "#00aa55" : "#00994d"
                                border.color: parent.hovered ? "#00ff80" : "#00cc66"
                                border.width: 1
                                radius: 4
                                
                                Behavior on color {
                                    ColorAnimation { duration: 150 }
                                }
                            }
                            
                            contentItem: Text {
                                text: parent.text
                                color: Theme.primaryText
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                font.pixelSize: 13
                                font.bold: true
                            }
                            
                            onClicked: {
                                if (LibraryManager.scanning && !isExtractingMetadata) {
                                    LibraryManager.cancelScan();
                                } else {
                                    isExtractingMetadata = false;  // Ensure flag is cleared for regular scan
                                    LibraryManager.startScan();
                                }
                            }
                        }
                    }

                    // Auto-refresh and file watching settings
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 16
                        spacing: 8

                        Label {
                            text: "Automatic Library Updates"
                            color: Theme.primaryText
                            font.pixelSize: 14
                            font.bold: true
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            CheckBox {
                                id: autoRefreshCheckbox
                                text: "Auto-refresh on startup"
                                checked: LibraryManager.autoRefreshOnStartup

                                onToggled: {
                                    LibraryManager.autoRefreshOnStartup = checked
                                }

                                contentItem: Text {
                                    text: parent.text
                                    font.pixelSize: 14
                                    color: Theme.secondaryText
                                    verticalAlignment: Text.AlignVCenter
                                    leftPadding: parent.indicator.width + parent.spacing
                                }

                                indicator: Rectangle {
                                    implicitWidth: 20
                                    implicitHeight: 20
                                    x: parent.leftPadding
                                    y: parent.height / 2 - height / 2
                                    radius: 3
                                    color: parent.checked ? Theme.selectedBackground : Theme.inputBackground
                                    border.color: parent.checked ? Theme.linkColor : Theme.borderColor

                                    Canvas {
                                        anchors.fill: parent
                                        anchors.margins: 4
                                        visible: parent.parent.checked

                                        onPaint: {
                                            var ctx = getContext("2d")
                                            ctx.reset()
                                            ctx.strokeStyle = "white"
                                            ctx.lineWidth = 2
                                            ctx.lineCap = "round"
                                            ctx.lineJoin = "round"
                                            ctx.beginPath()
                                            ctx.moveTo(width * 0.2, height * 0.5)
                                            ctx.lineTo(width * 0.4, height * 0.7)
                                            ctx.lineTo(width * 0.8, height * 0.3)
                                            ctx.stroke()
                                        }
                                    }
                                }
                            }

                            Image {
                                source: Theme.isDark ? "qrc:/resources/icons/info.svg" : "qrc:/resources/icons/info-dark.svg"
                                Layout.preferredWidth: 16
                                Layout.preferredHeight: 16
                                sourceSize.width: 16
                                sourceSize.height: 16

                                MouseArea {
                                    anchors.centerIn: parent
                                    width: 24
                                    height: 24
                                    hoverEnabled: true

                                    ToolTip {
                                        id: startupRefreshTooltip
                                        visible: parent.containsMouse
                                        text: "When enabled, the scanner will run after each launch to update your library with files \nadded or removed since you last launched mtoc."
                                        delay: 200
                                        timeout: 12000
                                        background: Rectangle {
                                            color: Theme.isDark ? "#2b2b2b" : "#f0f0f0"
                                            border.color: Theme.borderColor
                                            radius: 4
                                        }
                                        contentItem: Text {
                                            text: startupRefreshTooltip.text
                                            font.pixelSize: 12
                                            color: Theme.primaryText
                                        }
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            CheckBox {
                                id: watchFileChangesCheckbox
                                text: "Watch for file changes (requires restart)"
                                checked: LibraryManager.watchFileChanges

                                onToggled: {
                                    LibraryManager.watchFileChanges = checked
                                }

                                contentItem: Text {
                                    text: parent.text
                                    font.pixelSize: 14
                                    color: Theme.secondaryText
                                    verticalAlignment: Text.AlignVCenter
                                    leftPadding: parent.indicator.width + parent.spacing
                                }

                                indicator: Rectangle {
                                    implicitWidth: 20
                                    implicitHeight: 20
                                    x: parent.leftPadding
                                    y: parent.height / 2 - height / 2
                                    radius: 3
                                    color: parent.checked ? Theme.selectedBackground : Theme.inputBackground
                                    border.color: parent.checked ? Theme.linkColor : Theme.borderColor

                                    Canvas {
                                        anchors.fill: parent
                                        anchors.margins: 4
                                        visible: parent.parent.checked

                                        onPaint: {
                                            var ctx = getContext("2d")
                                            ctx.reset()
                                            ctx.strokeStyle = "white"
                                            ctx.lineWidth = 2
                                            ctx.lineCap = "round"
                                            ctx.lineJoin = "round"
                                            ctx.beginPath()
                                            ctx.moveTo(width * 0.2, height * 0.5)
                                            ctx.lineTo(width * 0.4, height * 0.7)
                                            ctx.lineTo(width * 0.8, height * 0.3)
                                            ctx.stroke()
                                        }
                                    }
                                }
                            }

                            Image {
                                source: Theme.isDark ? "qrc:/resources/icons/info.svg" : "qrc:/resources/icons/info-dark.svg"
                                Layout.preferredWidth: 16
                                Layout.preferredHeight: 16
                                sourceSize.width: 16
                                sourceSize.height: 16

                                MouseArea {
                                    anchors.centerIn: parent
                                    width: 24
                                    height: 24
                                    hoverEnabled: true

                                    ToolTip {
                                        id: fileWatcherTooltip
                                        visible: parent.containsMouse
                                        text: "When enabled, the file watcher will automatically add music to your library when you add files \nto monitored folders while mtoc is running, and remove music when files are deleted."
                                        delay: 200
                                        timeout: 12000
                                        background: Rectangle {
                                            color: Theme.isDark ? "#2b2b2b" : "#f0f0f0"
                                            border.color: Theme.borderColor
                                            radius: 4
                                        }
                                        contentItem: Text {
                                            text: fileWatcherTooltip.text
                                            font.pixelSize: 12
                                            color: Theme.primaryText
                                        }
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }
                        }

                        Label {
                            text: "Note: For very large libraries (>5000 subdirectories), 'Auto-refresh on startup' is recommended over 'Watch for changes' for better performance."
                            color: Theme.secondaryText
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            // Bottom spacer to ensure last item is visible
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 20
            }
        }
    }

    // Window closing behavior
    onClosing: function(close) {
        // Allow the window to close normally
        close.accepted = true;
    }
}