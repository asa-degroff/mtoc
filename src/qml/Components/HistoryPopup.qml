import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Mtoc.Backend 1.0

Item {
    id: root

    property var historyModel: []
    property bool isOpen: false

    signal closed()
    signal playTrack(var historyItem, int clickedIndex)
    signal goToAlbum(string albumName, string artistName)
    signal goToArtist(string artistName)
    signal addToQueue(int trackId)

    anchors.fill: parent
    z: 1000
    visible: isOpen || closeAnimationTimer.running

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
        color: Qt.rgba(0, 0, 0, 0.5)
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
            onWheel: function(wheel) {
                wheel.accepted = true
            }
        }
    }

    // Popup content container - slides in from left
    Item {
        id: popupContainer
        width: parent.width * 0.8
        height: parent.height * 0.8
        y: (parent.height - height) / 2

        // Animate from left
        x: root.isOpen ? (parent.width - width) / 2 : -width

        Behavior on x {
            NumberAnimation {
                duration: 200
                easing.type: Easing.InOutQuad
            }
        }

        // Background with shadow
        Rectangle {
            anchors.fill: parent
            color: Theme.backgroundColor
            radius: 8

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 4
                shadowBlur: 0.5
                shadowColor: "#80000000"
            }
        }

        // Content
        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Header
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 48
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
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12

                    HistoryHeader {
                        Layout.fillWidth: true
                        historyCount: historyListView.count
                        showCloseButton: false
                        forceLightText: false

                        onClearHistoryRequested: {
                            ScrobbleManager.clearHistory()
                            refreshHistory()
                        }
                    }

                    // Close button
                    ToolButton {
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        onClicked: root.closed()

                        contentItem: Item {
                            anchors.fill: parent

                            Image {
                                anchors.centerIn: parent
                                width: Math.min(18, parent.width * 0.6)
                                height: Math.min(18, parent.height * 0.6)
                                source: Theme.isDark ? "qrc:/resources/icons/close-button.svg" : "qrc:/resources/icons/close-button-dark.svg"
                                sourceSize.width: 64
                                sourceSize.height: 64
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                opacity: Theme.isDark ? 1.0 : 0.8
                            }
                        }

                        background: Rectangle {
                            color: parent.hovered ? Theme.inputBackgroundHover : Theme.inputBackground
                            radius: 4
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.15)
                        }
                    }
                }
            }

            // History list
            HistoryListView {
                id: historyListView
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 8
                focus: true
                historyModel: root.historyModel

                onTrackClicked: function(historyItem, clickedIndex) {
                    root.playTrack(historyItem, clickedIndex)
                }

                onGoToAlbumRequested: function(albumName, artistName) {
                    root.goToAlbum(albumName, artistName)
                    root.closed()
                }

                onGoToArtistRequested: function(artistName) {
                    root.goToArtist(artistName)
                    root.closed()
                }

                onAddToQueueRequested: function(trackId) {
                    root.addToQueue(trackId)
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
            refreshHistory()
        } else {
            closeAnimationTimer.start()
        }
    }

    // Timer to keep item visible during close animation
    Timer {
        id: closeAnimationTimer
        interval: 350
        repeat: false
    }

    function refreshHistory() {
        historyModel = ScrobbleManager.getValidRecentListens(100)
    }

    // Refresh when a new listen is recorded
    Connections {
        target: ScrobbleManager
        function onListenRecorded() {
            if (root.isOpen) {
                refreshHistory()
            }
        }
        function onHistoryCleared() {
            historyModel = []
        }
    }

    Component.onCompleted: {
        refreshHistory()
    }
}
