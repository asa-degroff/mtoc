import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Effects
import Mtoc.Backend 1.0

Item {
    id: root
    
    property url albumArtUrl: ""
    property alias currentTrack: trackInfoColumn.currentTrack
    property bool isOpen: false
    
    signal closed()
    
    anchors.fill: parent
    z: 1000
    visible: isOpen || closeAnimationTimer.running
    
    // Only show when open
    opacity: isOpen ? 1.0 : 0.0
    enabled: isOpen
    
    Behavior on opacity {
        NumberAnimation {
            duration: 200
            easing.type: Easing.InOutQuad
        }
    }
    
    // Semi-transparent background overlay
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.7)
        opacity: root.isOpen ? 1.0 : 0.0
        
        Behavior on opacity {
            NumberAnimation {
                duration: 200
                easing.type: Easing.InOutQuad
            }
        }
        
        MouseArea {
            anchors.fill: parent
            onClicked: root.closed()
        }
    }
    
    // Popup content container
    Item {
        id: popupContainer
        
        // Calculate maximum album art size that fits with header and track info
        property real maxAvailableHeight: parent.height * 0.9
        property real headerHeight: 50
        property real trackInfoHeight: 120  // Approximate height for track info section
        property real maxAlbumSize: Math.min(parent.width * 0.9, maxAvailableHeight - headerHeight - trackInfoHeight)
        
        width: Math.min(parent.width * 0.9, maxAlbumSize)
        height: headerHeight + width + trackInfoHeight
        x: (parent.width - width) / 2
        
        // Animate position
        y: root.isOpen ? (parent.height - height) / 2 : parent.height
        
        Behavior on y {
            NumberAnimation {
                duration: 200
                easing.type: Easing.InOutQuad
            }
        }
        
        // Background with shadow
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            radius: 8
            
            // Drop shadow
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 8
                shadowBlur: 1.0
                shadowColor: "#A0000000"
            }
        }
        
        // Content
        ColumnLayout {
            anchors.fill: parent
            spacing: 0
            
            // Header with close button
            Rectangle {
                id: headerRect
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                color: Theme.panelBackground
                radius: 8
                
                // Bottom corners square to connect with album art
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 8
                    color: parent.color
                }
                
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    
                    Label {
                        text: "Album Artwork"
                        font.pixelSize: 16
                        font.bold: true
                        color: Theme.primaryText
                    }
                    
                    Item { Layout.fillWidth: true }
                    
                    // Close button
                    ToolButton {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        icon.source: Theme.isDark ? "qrc:/resources/icons/close-button.svg" : "qrc:/resources/icons/close-button-dark.svg"
                        icon.width: 18
                        icon.height: 18
                        onClicked: root.closed()
                        
                        background: Rectangle {
                            color: parent.hovered ? Theme.inputBackgroundHover : Theme.inputBackground
                            radius: 4
                        }
                    }
                }
            }
            
            // Album art container with background
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: popupContainer.width
                color: Theme.backgroundColor
                
                Image {
                    id: albumArt
                    anchors.fill: parent
                    source: root.albumArtUrl
                    fillMode: Image.PreserveAspectFit
                    
                    // Drop shadow effect
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowHorizontalOffset: 0
                        shadowVerticalOffset: 4
                        shadowBlur: 0.5
                        shadowColor: "#60000000"
                    }
                    
                    // Placeholder when no album art
                    Rectangle {
                        anchors.fill: parent
                        color: Theme.panelBackground
                        visible: parent.status !== Image.Ready || parent.source == ""
                        
                        Text {
                            anchors.centerIn: parent
                            text: "♪"
                            font.pixelSize: parent.width * 0.3
                            color: Theme.inputBackgroundHover
                        }
                    }
                }
            }
            
            // Track info with background
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 100
                Layout.maximumHeight: 150
                color: Theme.backgroundColor
                radius: 8
                
                // Top corners square to connect with album art
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 8
                    color: parent.color
                }
                
                ColumnLayout {
                    id: trackInfoColumn
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 8
                    
                    property var currentTrack: MediaPlayer.currentTrack
                    
                    Label {
                        Layout.fillWidth: true
                        text: currentTrack ? currentTrack.title : ""
                        font.pixelSize: 18
                        font.bold: true
                        color: Theme.primaryText
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                    
                    Label {
                        Layout.fillWidth: true
                        text: currentTrack ? currentTrack.artist : ""
                        font.pixelSize: 16
                        color: Theme.secondaryText
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                    
                    Label {
                        Layout.fillWidth: true
                        text: currentTrack ? currentTrack.album : ""
                        font.pixelSize: 14
                        color: Theme.tertiaryText
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
    
    // Handle escape key
    Keys.onEscapePressed: root.closed()
    
    // Grab focus when open
    onIsOpenChanged: {
        if (isOpen) {
            root.forceActiveFocus()
        } else {
            // Start timer to hide after animation completes
            closeAnimationTimer.start()
        }
    }
    
    // Timer to keep item visible during close animation
    Timer {
        id: closeAnimationTimer
        interval: 350  // Slightly longer than animation duration
        repeat: false
    }
}