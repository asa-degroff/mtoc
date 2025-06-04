import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Dialogs
import Mtoc.Backend 1.0

ApplicationWindow {
    id: libraryEditorWindow
    title: "Edit Library - mtoc"
    width: 600
    height: 500
    
    flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowMinimizeButtonHint | Qt.WindowMaximizeButtonHint | Qt.WindowCloseButtonHint
    
    color: "#2a2a2a"
    
    // Folder dialog for adding music folders
    FolderDialog {
        id: folderDialog
        title: "Select Music Folder"
        acceptLabel: "Add Folder"
        rejectLabel: "Cancel"
        
        onAccepted: {
            var path = selectedFolder.toString();
            // Remove the file:// prefix if present
            if (path.startsWith("file://")) {
                path = path.substring(7);
            }
            
            if (path.length > 0) {
                // Add the folder to LibraryManager
                LibraryManager.addMusicFolder(path);
            } else {
                console.error("Could not determine selected folder path");
            }
        }
    }
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 16
            
            // Title
            Label {
                text: "Library Management"
                font.pixelSize: 20
                font.bold: true
                color: "white"
                Layout.fillWidth: true
            }
            
            // Library statistics section
            Rectangle {
                Layout.fillWidth: true
                height: 100
                color: "#333333"
                radius: 4
                
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 24
                    
                    // Artists count
                    Column {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 4
                        
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: LibraryManager.artistCount
                            font.pixelSize: 32
                            font.bold: true
                            color: "white"
                        }
                        
                        Label {
                            text: "Artists"
                            font.pixelSize: 14
                            color: "#cccccc"
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
                            color: "white"
                        }
                        
                        Label {
                            text: "Albums"
                            font.pixelSize: 14
                            color: "#cccccc"
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
                            color: "white"
                        }
                        
                        Label {
                            text: "Tracks"
                            font.pixelSize: 14
                            color: "#cccccc"
                        }
                    }
                    
                    // Scan progress
                    Column {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: true
                        spacing: 4
                        visible: LibraryManager.scanning
                        
                        ProgressBar {
                            width: parent.width
                            value: LibraryManager.scanProgress / 100.0
                            from: 0
                            to: 1
                        }
                        
                        Label {
                            text: "Scanning: " + LibraryManager.scanProgressText
                            font.pixelSize: 12
                            color: "#cccccc"
                        }
                    }
                }
            }
            
            // Music folders section
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#333333"
                radius: 4
                
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8
                    
                    RowLayout {
                        Layout.fillWidth: true
                        
                        Label {
                            text: "Music Folders"
                            font.pixelSize: 16
                            font.bold: true
                            color: "white"
                        }
                        
                        Item { Layout.fillWidth: true }
                        
                        Button {
                            text: "Add Folder"
                            onClicked: folderDialog.open()
                        }
                    }
                    
                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: LibraryManager.musicFolders
                        
                        delegate: Rectangle {
                            width: ListView.view.width
                            height: 40
                            color: index % 2 === 0 ? "#3a3a3a" : "#353535"
                            
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8
                                
                                Label {
                                    text: modelData
                                    color: "white"
                                    elide: Text.ElideLeft
                                    Layout.fillWidth: true
                                }
                                
                                Button {
                                    text: "Remove"
                                    flat: true
                                    onClicked: {
                                        LibraryManager.removeMusicFolder(modelData);
                                    }
                                }
                            }
                        }
                        
                        ScrollIndicator.vertical: ScrollIndicator { }
                    }
                }
            }
            
            // Info text and action buttons
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 80
                color: "#404040"
                radius: 4
                
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8
                    
                    Label {
                        text: "Scan your library to add files from the chosen folders to the music collection."
                        color: "#cccccc"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        
                        Button {
                            text: "Clear Library"
                            onClicked: {
                                LibraryManager.clearLibrary();
                            }
                        }
                        
                        Item { Layout.fillWidth: true }
                        
                        Button {
                            text: LibraryManager.scanning ? "Cancel Scan" : "Scan Library"
                            highlighted: true
                            enabled: true
                            onClicked: {
                                if (LibraryManager.scanning) {
                                    LibraryManager.cancelScan();
                                } else {
                                    LibraryManager.startScan();
                                }
                            }
                        }
                    }
                }
            }
        }
    
    // Window closing behavior
    onClosing: function(close) {
        // Allow the window to close normally
        close.accepted = true;
    }
}