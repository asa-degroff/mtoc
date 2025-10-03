import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Effects
import Mtoc.Backend 1.0

Item {
    id: root

    property string lyricsText: ""
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
        width: parent.width * 0.8
        height: parent.height * 0.85
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
            spacing: 0

            // Header
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                color: Theme.panelBackground
                radius: 8

                // Bottom corners square to connect with lyrics view
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

                    Label {
                        text: "Lyrics"
                        font.pixelSize: 14
                        font.bold: true
                        color: Theme.primaryText
                    }

                    Item { Layout.fillWidth: true }

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

            // Lyrics view container with background
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

                // Embed LyricsView component
                LyricsView {
                    anchors.fill: parent
                    lyricsText: root.lyricsText
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
