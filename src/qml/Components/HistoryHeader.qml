import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Mtoc.Backend 1.0

RowLayout {
    id: root

    property bool forceLightText: false
    property int historyCount: 0
    property bool showCloseButton: false

    signal clearHistoryRequested()
    signal closeRequested()

    // Fixed "History" label
    Label {
        Layout.alignment: Qt.AlignVCenter
        text: "History"
        font.pixelSize: 14
        font.weight: Font.DemiBold
        color: forceLightText ? "#ffffff" : Theme.primaryText
    }

    Item {
        Layout.fillWidth: true
    }

    // Track count label
    Label {
        Layout.alignment: Qt.AlignVCenter
        text: historyCount + " track" + (historyCount !== 1 ? "s" : "") + " played"
        font.pixelSize: 12
        color: forceLightText ? "#808080" : Theme.secondaryText
    }

    // Clear history button
    Rectangle {
        Layout.preferredWidth: 30
        Layout.preferredHeight: 30
        radius: 4
        color: clearHistoryMouseArea.containsMouse ? Qt.rgba(1, 0, 0, 0.2) :
               (forceLightText ? Qt.rgba(1, 1, 1, 0.05) : (Theme.isDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(254, 254, 254, 0.5)))
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, forceLightText ? 0.3 : 0.15)
        visible: historyCount > 0

        Behavior on color {
            ColorAnimation { duration: 150 }
        }

        Image {
            anchors.centerIn: parent
            width: 18
            height: 18
            source: (forceLightText || Theme.isDark) ? "qrc:/resources/icons/bomb.svg" : "qrc:/resources/icons/bomb-dark.svg"
            sourceSize.width: 40
            sourceSize.height: 40
            opacity: clearHistoryMouseArea.containsMouse ? 0.7 : 1.0

            Behavior on opacity {
                NumberAnimation { duration: 150 }
            }
        }

        MouseArea {
            id: clearHistoryMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.clearHistoryRequested()
            }
        }

        ToolTip {
            id: clearHistoryTooltip
            visible: clearHistoryMouseArea.containsMouse
            text: "Clear history"
            delay: 500
            timeout: 5000
            background: Rectangle {
                color: Theme.isDark ? "#2b2b2b" : "#f0f0f0"
                border.color: Theme.borderColor
                radius: 4
            }
            contentItem: Text {
                text: clearHistoryTooltip.text
                font.pixelSize: 12
                color: Theme.primaryText
            }
        }
    }

    // Close button (for popup mode)
    Rectangle {
        Layout.preferredWidth: 30
        Layout.preferredHeight: 30
        radius: 4
        color: closeMouseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.15) :
               (forceLightText ? Qt.rgba(1, 1, 1, 0.05) : (Theme.isDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(254, 254, 254, 0.5)))
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, forceLightText ? 0.3 : 0.15)
        visible: showCloseButton

        Behavior on color {
            ColorAnimation { duration: 150 }
        }

        Image {
            anchors.centerIn: parent
            width: 18
            height: 18
            source: (forceLightText || Theme.isDark) ? "qrc:/resources/icons/close-button.svg" : "qrc:/resources/icons/close-button-dark.svg"
            sourceSize.width: 40
            sourceSize.height: 40
            opacity: closeMouseArea.containsMouse ? 0.7 : 1.0

            Behavior on opacity {
                NumberAnimation { duration: 150 }
            }
        }

        MouseArea {
            id: closeMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.closeRequested()
            }
        }
    }
}
