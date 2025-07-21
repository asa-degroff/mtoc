import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Mtoc.Backend 1.0

ApplicationWindow {
    id: settingsWindow
    title: "Settings - mtoc"
    width: 600
    height: 800
    
    flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowMinimizeButtonHint | Qt.WindowMaximizeButtonHint | Qt.WindowCloseButtonHint
    
    color: "#2a2a2a"
    
    ScrollView {
        anchors.fill: parent
        contentWidth: width
        
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 24
            
            // Title
            Label {
                text: "Settings"
                font.pixelSize: 20
                font.bold: true
                color: "white"
                Layout.fillWidth: true
            }
            
            // Queue Behavior Section
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: queueBehaviorLayout.implicitHeight + 24
                color: "#333333"
                radius: 4
                
                ColumnLayout {
                    id: queueBehaviorLayout
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12
                    
                    Label {
                        text: "Queue Behavior"
                        font.pixelSize: 16
                        font.bold: true
                        color: "white"
                    }
                    
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        
                        Label {
                            text: "Default action when playing album if queue has been modified:"
                            font.pixelSize: 14
                            color: "#cccccc"
                            Layout.preferredWidth: 250
                        }
                        
                        ComboBox {
                            id: queueActionCombo
                            Layout.fillWidth: true
                            model: ["Replace queue", "Play next", "Play last", "Ask every time"]
                            currentIndex: SettingsManager.queueActionDefault
                            
                            onCurrentIndexChanged: {
                                SettingsManager.queueActionDefault = currentIndex
                            }
                            
                            background: Rectangle {
                                color: parent.hovered ? "#404040" : "#383838"
                                radius: 4
                                border.width: 1
                                border.color: "#505050"
                            }
                            
                            contentItem: Text {
                                text: parent.displayText
                                color: "white"
                                font.pixelSize: 14
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 8
                            }
                        }
                    }
                }
            }
            
            // Display Options Section
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: displayLayout.implicitHeight + 24
                color: "#333333"
                radius: 4
                
                ColumnLayout {
                    id: displayLayout
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12
                    
                    Label {
                        text: "Display Options"
                        font.pixelSize: 16
                        font.bold: true
                        color: "white"
                    }
                    
                    CheckBox {
                        id: showTrackInfoCheck
                        text: "Show track info panel by default"
                        checked: SettingsManager.showTrackInfoByDefault
                        
                        onToggled: {
                            SettingsManager.showTrackInfoByDefault = checked
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font.pixelSize: 14
                            color: "#cccccc"
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: parent.indicator.width + parent.spacing
                        }
                        
                        indicator: Rectangle {
                            implicitWidth: 20
                            implicitHeight: 20
                            x: parent.leftPadding
                            y: parent.height / 2 - height / 2
                            radius: 3
                            color: parent.checked ? "#4a5fba" : "#383838"
                            border.color: parent.checked ? "#5a6fca" : "#505050"
                            
                            Rectangle {
                                width: 12
                                height: 12
                                x: 4
                                y: 4
                                radius: 2
                                color: "white"
                                visible: parent.parent.checked
                            }
                        }
                    }
                }
            }
            
            // Playback Section
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: playbackLayout.implicitHeight + 24
                color: "#333333"
                radius: 4
                
                ColumnLayout {
                    id: playbackLayout
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12
                    
                    Label {
                        text: "Playback"
                        font.pixelSize: 16
                        font.bold: true
                        color: "white"
                    }
                    
                    CheckBox {
                        id: restorePositionCheck
                        text: "Restore playback position on restart"
                        checked: SettingsManager.restorePlaybackPosition
                        
                        onToggled: {
                            SettingsManager.restorePlaybackPosition = checked
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font.pixelSize: 14
                            color: "#cccccc"
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: parent.indicator.width + parent.spacing
                        }
                        
                        indicator: Rectangle {
                            implicitWidth: 20
                            implicitHeight: 20
                            x: parent.leftPadding
                            y: parent.height / 2 - height / 2
                            radius: 3
                            color: parent.checked ? "#4a5fba" : "#383838"
                            border.color: parent.checked ? "#5a6fca" : "#505050"
                            
                            Rectangle {
                                width: 12
                                height: 12
                                x: 4
                                y: 4
                                radius: 2
                                color: "white"
                                visible: parent.parent.checked
                            }
                        }
                    }
                }
            }
            
            // About Section
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: aboutLayout.implicitHeight + 24
                color: "#333333"
                radius: 4
                
                ColumnLayout {
                    id: aboutLayout
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8
                    
                    Label {
                        text: "About"
                        font.pixelSize: 16
                        font.bold: true
                        color: "white"
                    }
                    
                    Label {
                        text: "mtoc - Music Library and Player"
                        font.pixelSize: 14
                        color: "#cccccc"
                    }
                    
                    Label {
                        text: "Version 0.1"
                        font.pixelSize: 12
                        color: "#999999"
                    }
                    
                    Label {
                        text: "© 2024 mtoc contributors"
                        font.pixelSize: 12
                        color: "#999999"
                    }
                    
                    Item { height: 8 }
                    
                    Label {
                        text: "Acknowledgements"
                        font.pixelSize: 14
                        font.bold: true
                        color: "#cccccc"
                    }
                    
                    Label {
                        text: "Built with Qt, TagLib, and GStreamer"
                        font.pixelSize: 12
                        color: "#999999"
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                }
            }
            
            Item { Layout.fillHeight: true }
        }
    }
}