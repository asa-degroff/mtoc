import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Qt.labs.platform 1.1
import Mtoc.Backend 1.0

Item {
    id: root
    width: parent.width
    height: parent.height
    
    // Reference to the file dialog for selecting music folders
    FolderDialog {
        id: folderDialog
        title: "Select Music Folder"
        currentFolder: StandardPaths.standardLocations(StandardPaths.MusicLocation)[0]
        
        onAccepted: {
            // Extract the local file path
            var path = folderDialog.selectedFolder.toString();
            path = path.replace(/^(file:\/{2})/,"");
            
            // Add the folder to LibraryManager
            LibraryManager.addMusicFolder(path);
        }
    }
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 16
        
        // Header section
        Rectangle {
            Layout.fillWidth: true
            height: 60
            color: "#2a2a2a"
            radius: 4
            
            RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 12
                
                Label {
                    text: "Music Library"
                    font.pixelSize: 20
                    font.bold: true
                    color: "white"
                }
                
                Item { Layout.fillWidth: true } // Spacer
                
                Button {
                    text: "Add Folder"
                    onClicked: folderDialog.open()
                }
                
                Button {
                    text: LibraryManager.scanning ? "Cancel Scan" : "Scan Library"
                    enabled: true // Always enabled - LibraryManager handles cancel state internally
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
        
        // Library statistics section
        Rectangle {
            Layout.fillWidth: true
            height: 100
            color: "#2a2a2a"
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
                        value: LibraryManager.scanProgress
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
            Layout.preferredHeight: 150
            color: "#2a2a2a"
            radius: 4
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8
                
                Label {
                    text: "Music Folders"
                    font.pixelSize: 16
                    font.bold: true
                    color: "white"
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
                                Layout.fillWidth: true
                                text: modelData
                                elide: Text.ElideMiddle
                                color: "white"
                            }
                            
                            Button {
                                text: "Remove"
                                onClicked: LibraryManager.removeMusicFolder(modelData)
                            }
                        }
                    }
                }
            }
        }
        
        // Albums/artists view
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#2a2a2a"
            radius: 4
            
            TabBar {
                id: libraryTabBar
                width: parent.width
                
                TabButton { text: "Artists" }
                TabButton { text: "Albums" }
            }
            
            StackLayout {
                anchors.top: libraryTabBar.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 8
                currentIndex: libraryTabBar.currentIndex
                
                // Artists view
                GridView {
                    clip: true
                    cellWidth: 160
                    cellHeight: 200
                    model: LibraryManager.artistModel
                    
                    delegate: Rectangle {
                        width: 150
                        height: 190
                        color: "#3a3a3a"
                        radius: 4
                        
                        Column {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8
                            
                            Rectangle {
                                width: parent.width
                                height: width
                                color: "#555555"
                                
                                Image {
                                    anchors.fill: parent
                                    source: image ? image : ""
                                    fillMode: Image.PreserveAspectCrop
                                }
                            }
                            
                            Label {
                                width: parent.width
                                text: name
                                elide: Text.ElideRight
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                horizontalAlignment: Text.AlignHCenter
                                color: "white"
                                font.pixelSize: 14
                            }
                            
                            Label {
                                width: parent.width
                                text: albumCount + " album" + (albumCount !== 1 ? "s" : "")
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                                color: "#aaaaaa"
                                font.pixelSize: 12
                            }
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                // TODO: Show albums by this artist
                            }
                        }
                    }
                }
                
                // Albums view
                GridView {
                    clip: true
                    cellWidth: 160
                    cellHeight: 200
                    model: LibraryManager.albumModel
                    
                    delegate: Rectangle {
                        width: 150
                        height: 190
                        color: "#3a3a3a"
                        radius: 4
                        
                        Column {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8
                            
                            Rectangle {
                                width: parent.width
                                height: width
                                color: "#555555"
                                
                                Image {
                                    anchors.fill: parent
                                    source: image ? image : ""
                                    fillMode: Image.PreserveAspectCrop
                                }
                            }
                            
                            Label {
                                width: parent.width
                                text: title
                                elide: Text.ElideRight
                                wrapMode: Text.Wrap
                                maximumLineCount: 1
                                horizontalAlignment: Text.AlignHCenter
                                color: "white"
                                font.pixelSize: 14
                            }
                            
                            Label {
                                width: parent.width
                                text: artist
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                                color: "#aaaaaa"
                                font.pixelSize: 12
                            }
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                // TODO: Show tracks for this album
                            }
                        }
                    }
                }
            }
        }
    }
}