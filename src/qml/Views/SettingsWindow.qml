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
                    
                    Label {
                        text: "Default action for playing an album or playlist if queue has been modified:"
                        font.pixelSize: 14
                        color: "#cccccc"
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }
                    
                    ComboBox {
                        id: queueActionCombo
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
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
                            rightPadding: 30  // Leave space for indicator
                        }
                        
                        indicator: Canvas {
                            x: parent.width - width - 8
                            y: parent.height / 2 - height / 2
                            width: 12
                            height: 8
                            contextType: "2d"
                            
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.reset()
                                ctx.moveTo(0, 0)
                                ctx.lineTo(width, 0)
                                ctx.lineTo(width / 2, height)
                                ctx.closePath()
                                ctx.fillStyle = "#cccccc"
                                ctx.fill()
                            }
                        }
                        
                        popup: Popup {
                            y: parent.height + 2
                            width: parent.width
                            implicitHeight: contentItem.implicitHeight + 2
                            padding: 1
                            
                            contentItem: ListView {
                                clip: true
                                implicitHeight: contentHeight
                                model: parent.visible ? queueActionCombo.delegateModel : null
                                currentIndex: queueActionCombo.highlightedIndex
                                
                                ScrollIndicator.vertical: ScrollIndicator { }
                            }
                            
                            background: Rectangle {
                                color: "#2a2a2a"
                                border.color: "#505050"
                                border.width: 1
                                radius: 4
                            }
                        }
                        
                        delegate: ItemDelegate {
                            width: queueActionCombo.width
                            height: 36
                            
                            contentItem: Text {
                                text: modelData
                                color: parent.hovered ? "white" : "#cccccc"
                                font.pixelSize: 14
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 8
                            }
                            
                            background: Rectangle {
                                color: parent.hovered ? "#4a5fba" : "transparent"
                                radius: 2
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
                                    ctx.lineTo(width * 0.45, height * 0.75)
                                    ctx.lineTo(width * 0.8, height * 0.25)
                                    ctx.stroke()
                                }
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
                                    ctx.lineTo(width * 0.45, height * 0.75)
                                    ctx.lineTo(width * 0.8, height * 0.25)
                                    ctx.stroke()
                                }
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
                        text: "Version 2.0"
                        font.pixelSize: 12
                        color: "#999999"
                    }
                    
                    Label {
                        text: "© 2025 Asa DeGroff"
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

                    Label {
                        text: "License"
                        font.pixelSize: 14
                        font.bold: true
                        color: "#cccccc"
                    }

                    Text {
                        text: "mtoc is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. 
                        
mtoc is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with mtoc. If not, see: <a href=\"https://www.gnu.org/licenses/gpl-3.0.html\">https://www.gnu.org/licenses/gpl-3.0.html</a>"
                        font.pixelSize: 12
                        color: "#999999"
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                        textFormat: Text.RichText
                        
                        onLinkActivated: function(link) {
                            Qt.openUrlExternally(link)
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.NoButton
                            cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                        }
                    }
                }
            }
            
            Item { Layout.fillHeight: true }
        }
    }
}