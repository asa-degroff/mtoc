import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Mtoc.Backend 1.0
import ".."

ListView {
    id: root
    focus: true

    property var historyModel: []
    property bool forceLightText: false

    // Keyboard navigation state
    property int keyboardSelectedIndex: -1

    signal trackClicked(var historyItem, int clickedIndex)
    signal goToAlbumRequested(string albumName, string artistName)
    signal goToArtistRequested(string artistName)
    signal addToQueueRequested(int trackId)

    // Keyboard shortcuts
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Down) {
            if (keyboardSelectedIndex === -1 && count > 0) {
                keyboardSelectedIndex = 0
                ensureKeyboardSelectedVisible()
            } else if (keyboardSelectedIndex < count - 1) {
                keyboardSelectedIndex++
                ensureKeyboardSelectedVisible()
            }
            event.accepted = true
        } else if (event.key === Qt.Key_Up) {
            if (keyboardSelectedIndex > 0) {
                keyboardSelectedIndex--
                ensureKeyboardSelectedVisible()
            }
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (keyboardSelectedIndex >= 0 && keyboardSelectedIndex < count) {
                trackClicked(historyModel[keyboardSelectedIndex], keyboardSelectedIndex)
            }
            event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
            keyboardSelectedIndex = -1
            event.accepted = true
        }
    }

    function ensureKeyboardSelectedVisible() {
        if (keyboardSelectedIndex < 0 || keyboardSelectedIndex >= count) {
            return
        }

        var itemY = keyboardSelectedIndex * (45 + spacing)
        var visibleHeight = height
        var currentY = contentY

        var itemTop = itemY
        var itemBottom = itemY + 45
        var viewTop = currentY
        var viewBottom = currentY + visibleHeight

        var targetY = -1

        if (itemTop < viewTop) {
            targetY = Math.max(0, itemTop - 10)
        } else if (itemBottom > viewBottom) {
            targetY = itemBottom - visibleHeight + 10
        }

        if (targetY >= 0) {
            scrollAnimation.to = targetY
            scrollAnimation.start()
        }
    }

    // Format duration from seconds
    function formatDuration(seconds) {
        if (isNaN(seconds) || seconds < 0) {
            return "0:00"
        }

        var minutes = Math.floor(seconds / 60)
        var secs = seconds % 60

        return minutes + ":" + (secs < 10 ? "0" : "") + secs
    }

    // Format relative timestamp
    function formatRelativeTime(unixTimestamp) {
        var now = Math.floor(Date.now() / 1000)
        var diff = now - unixTimestamp

        if (diff < 60) {
            return "just now"
        } else if (diff < 3600) {
            var mins = Math.floor(diff / 60)
            return mins + " min" + (mins !== 1 ? "s" : "") + " ago"
        } else if (diff < 86400) {
            var hours = Math.floor(diff / 3600)
            return hours + " hour" + (hours !== 1 ? "s" : "") + " ago"
        } else if (diff < 604800) {
            var days = Math.floor(diff / 86400)
            return days + " day" + (days !== 1 ? "s" : "") + " ago"
        } else {
            var date = new Date(unixTimestamp * 1000)
            return date.toLocaleDateString()
        }
    }

    NumberAnimation {
        id: scrollAnimation
        target: root
        property: "contentY"
        duration: 300
        easing.type: Easing.InOutQuad
    }

    onModelChanged: {
        keyboardSelectedIndex = -1
    }

    clip: true
    spacing: 2

    model: historyModel

    delegate: Rectangle {
        id: historyItemDelegate
        width: root.width
        height: 45
        color: {
            if (index === root.keyboardSelectedIndex) {
                return Theme.selectedBackgroundLowOpacity
            } else if (historyItemMouseArea.containsMouse) {
                return Qt.rgba(1, 1, 1, 0.04)
            } else {
                return Qt.rgba(1, 1, 1, 0.02)
            }
        }
        radius: 4
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.04)

        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 10

            // Track info column
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                // Track title
                Label {
                    text: modelData.track_name || "Unknown Track"
                    color: root.forceLightText ? "#ffffff" : Theme.primaryText
                    font.pixelSize: 13
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                // Artist name
                Label {
                    text: modelData.artist_name || "Unknown Artist"
                    color: root.forceLightText ? "#aaaaaa" : Theme.secondaryText
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            // Timestamp
            Label {
                text: formatRelativeTime(modelData.listened_at)
                color: root.forceLightText ? "#808080" : Theme.secondaryText
                font.pixelSize: 11
                Layout.preferredWidth: 80
                Layout.fillHeight: true
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
            }
        }

        MouseArea {
            id: historyItemMouseArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton

            onClicked: function(mouse) {
                root.forceActiveFocus()
                if (mouse.button === Qt.LeftButton) {
                    root.keyboardSelectedIndex = index
                    if (SettingsManager.singleClickToPlay) {
                        root.trackClicked(modelData, index)
                    }
                } else if (mouse.button === Qt.RightButton) {
                    contextMenu.popup()
                }
            }

            onDoubleClicked: function(mouse) {
                if (!SettingsManager.singleClickToPlay && mouse.button === Qt.LeftButton) {
                    root.trackClicked(modelData, index)
                }
            }
        }

        // Context menu
        StyledMenu {
            id: contextMenu

            StyledMenuItem {
                text: "Play"
                onTriggered: root.trackClicked(modelData, index)
            }

            StyledMenuItem {
                text: "Add to Queue"
                onTriggered: root.addToQueueRequested(modelData.track_id)
            }

            StyledMenuSeparator { }

            StyledMenuItem {
                text: "Go to Album"
                onTriggered: root.goToAlbumRequested(modelData.album_name, modelData.artist_name)
            }

            StyledMenuItem {
                text: "Go to Artist"
                onTriggered: root.goToArtistRequested(modelData.artist_name)
            }
        }

        Behavior on color {
            ColorAnimation { duration: 150 }
        }
    }

    ScrollIndicator.vertical: ScrollIndicator { }

    // Empty state
    Label {
        anchors.centerIn: parent
        text: "No playback history yet"
        color: "#666666"
        font.pixelSize: 14
        visible: root.count === 0
    }

    // Background mouse area to capture clicks and set focus
    MouseArea {
        anchors.fill: parent
        z: -1
        onPressed: function(mouse) {
            root.forceActiveFocus()
            mouse.accepted = false
        }
    }
}
