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

                        // Intro text
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: introText.height + 32
                            Layout.topMargin: 24
                        }

                        // Lyrics support section
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: lyricsSection.height

                            ColumnLayout {
                                id: lyricsSection
                                width: parent.width - 64
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 12

                                Label {
                                    text: "Lyrics Support"
                                    font.pixelSize: 16
                                    font.bold: true
                                    color: Theme.primaryText
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: "• Synchronized and unsynchronized lyrics display\n• Synced lyrics with real-time line highlighting\n• Click any line to seek to that position in the track\n• External .lrc and .txt file support\n• Automatic lyrics file detection with fuzzy matching"
                                    wrapMode: Text.WordWrap
                                    font.pixelSize: 14
                                    color: Theme.secondaryText
                                    lineHeight: 1.4
                                }
                            }
                        }

                        // Automatic library updates section
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: librarySection.height

                            ColumnLayout {
                                id: librarySection
                                width: parent.width - 64
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 12

                                Label {
                                    text: "Automatic Library Updates"
                                    font.pixelSize: 16
                                    font.bold: true
                                    color: Theme.primaryText
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: "• File watcher monitors your music directory for changes\n• Automatic detection of added and removed music and lyrics\n• Library management options for update behavior\n• Choose between auto-update, startup refresh, or manual updates\n• Improved album carousel stability during library changes"
                                    wrapMode: Text.WordWrap
                                    font.pixelSize: 14
                                    color: Theme.secondaryText
                                    lineHeight: 1.4
                                }
                            }
                        }

                        // UI enhancements section
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: uiSection.height

                            ColumnLayout {
                                id: uiSection
                                width: parent.width - 64
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 12

                                Label {
                                    text: "UI Enhancements"
                                    font.pixelSize: 16
                                    font.bold: true
                                    color: Theme.primaryText
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: "• Minimize to tray option when closing the main window\n• Single-click to play tracks option in settings"
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
                        color: "#FFFFFF"  // White text on accent color background
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        implicitWidth: 120
                        implicitHeight: 40
                        color: parent.hovered ? Qt.lighter(Theme.accentColor, 1.1) : Theme.accentColor
                        radius: 6

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
