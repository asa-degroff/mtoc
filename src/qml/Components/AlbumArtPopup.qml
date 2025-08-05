import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Effects
import Mtoc.Backend 1.0

Popup {
    id: root
    
    property url albumArtUrl: ""
    property alias currentTrack: trackInfoColumn.currentTrack
    
    width: Math.min(parent.width * 0.9, 800)
    height: Math.min(parent.height * 0.9, 800)
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    
    // Slide up animation on enter
    enter: Transition {
        NumberAnimation {
            property: "y"
            from: parent.height
            to: (parent.height - height) / 2
            duration: 300
            easing.type: Easing.OutCubic
        }
    }
    
    // Slide down animation on exit
    exit: Transition {
        NumberAnimation {
            property: "y"
            from: (parent.height - height) / 2
            to: parent.height
            duration: 300
            easing.type: Easing.InCubic
        }
    }
    
    // Semi-transparent background overlay with fade animation
    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.7)
        opacity: root.visible ? 1.0 : 0.0
        
        Behavior on opacity {
            NumberAnimation {
                duration: 300
                easing.type: Easing.InOutCubic
            }
        }
    }
    
    background: Rectangle {
        color: Theme.backgroundColor
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
    
    contentItem: ColumnLayout {
        spacing: 0
        
        // Header with close button
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 50
            color: Theme.panelBackground
            radius: 8
            
            // Bottom corners square
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
                    icon.source: "qrc:/resources/icons/close.svg"
                    icon.width: 18
                    icon.height: 18
                    onClicked: root.close()
                    
                    background: Rectangle {
                        color: parent.hovered ? Theme.inputBackgroundHover : Theme.inputBackground
                        radius: 4
                    }
                }
            }
        }
        
        // Album art container
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 20
            
            Image {
                id: albumArt
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height)
                height: width
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
        
        // Track info
        ColumnLayout {
            id: trackInfoColumn
            Layout.fillWidth: true
            Layout.margins: 20
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