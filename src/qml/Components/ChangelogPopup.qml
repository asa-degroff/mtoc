import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Effects
import Mtoc.Backend 1.0

Item {
    id: root

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
                // Consume wheel events to prevent propagation to underlying content
                wheel.accepted = true
            }
        }
    }

    // Popup content container
    Item {
        id: popupContainer
        width: parent.width * 0.7
        height: parent.height * 0.8
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
            color: Theme.backgroundColor
            radius: 8

            // Drop shadow
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
            anchors.margins: 0
            spacing: 0

            // Header
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                color: Theme.panelBackground
                radius: 8

                // Bottom corners square to connect with content
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 8
                    color: parent.color
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 16
                    spacing: 12

                    // Title
                    Label {
                        text: "What's New in mtoc " + SystemInfo.appVersion
                        font.pixelSize: 16
                        font.bold: true
                        color: Theme.primaryText
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
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

            // Content area with scrollable changelog
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.backgroundColor
                radius: 8

                // Top corners square to connect with header
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 8
                    color: parent.color
                }

                ScrollView {
                    id: scrollView
                    anchors.fill: parent
                    anchors.margins: 0
                    clip: true

                    ScrollBar.vertical.policy: ScrollBar.AsNeeded
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                    ColumnLayout {
                        width: scrollView.width
                        spacing: 24

                        // Top spacing
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 8
                        }

                        // Favorites section
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: favoritesSection.height

                            ColumnLayout {
                                id: favoritesSection
                                width: parent.width - 64
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 12

                                Label {
                                    text: "Favorites"
                                    font.pixelSize: 16
                                    font.bold: true
                                    color: Theme.primaryText
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: "• Added a toggleable favorite button and dynamic favorites playlist\n• Mark your favorite tracks and access them instantly from the playlists tab"
                                    wrapMode: Text.WordWrap
                                    font.pixelSize: 14
                                    color: Theme.secondaryText
                                    lineHeight: 1.4
                                }
                            }
                        }

                        // Playlist creation section
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: playlistSection.height

                            ColumnLayout {
                                id: playlistSection
                                width: parent.width - 64
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 12

                                Label {
                                    text: "Expanded Playlist Options"
                                    font.pixelSize: 16
                                    font.bold: true
                                    color: Theme.primaryText
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: "• Albums and tracks can now be added to a new or existing playlist through the right-click context menus in the library\n• Creating a new playlist now reveals it in the list and enables immediate renaming"
                                    wrapMode: Text.WordWrap
                                    font.pixelSize: 14
                                    color: Theme.secondaryText
                                    lineHeight: 1.4
                                }
                            }
                        }

                        // Drag-and-drop section
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: dragDropSection.height

                            ColumnLayout {
                                id: dragDropSection
                                width: parent.width - 64
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 12

                                Label {
                                    text: "Improved Drag-and-Drop"
                                    font.pixelSize: 16
                                    font.bold: true
                                    color: Theme.primaryText
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: "• Drag-and-drop list reordering in the queue and playlist editor has been rewritten with auto-scroll and improved stability"
                                    wrapMode: Text.WordWrap
                                    font.pixelSize: 14
                                    color: Theme.secondaryText
                                    lineHeight: 1.4
                                }
                            }
                        }

                        // Shuffle options section
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: shuffleSection.height

                            ColumnLayout {
                                id: shuffleSection
                                width: parent.width - 64
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 12

                                Label {
                                    text: "New Shuffle Options"
                                    font.pixelSize: 16
                                    font.bold: true
                                    color: Theme.primaryText
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: "• New context menu option to play an entire artist discography\n• Shuffle option in album, artist, and playlist context menus\n• New option to auto-disable shuffle after queue replacement"
                                    wrapMode: Text.WordWrap
                                    font.pixelSize: 14
                                    color: Theme.secondaryText
                                    lineHeight: 1.4
                                }
                            }
                        }

                        // Bottom spacing
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 24
                        }
                    }
                }
            }

            // Footer with button
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 72
                color: Theme.panelBackground
                radius: 8

                // Top corners square to connect with content
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 8
                    color: parent.color
                }

                Button {
                    anchors.centerIn: parent
                    text: "Got it!"
                    font.pixelSize: 14
                    font.bold: true

                    contentItem: Text {
                        text: parent.text
                        font: parent.font
                        color: Theme.primaryText
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        implicitWidth: 120
                        implicitHeight: 40
                        color: parent.hovered ? Theme.inputBackgroundHover : Theme.inputBackground
                        radius: 6
                        border.width: 1
                        border.color: Theme.borderColor

                        Behavior on color {
                            ColorAnimation { duration: 100 }
                        }
                    }

                    onClicked: root.closed()
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
