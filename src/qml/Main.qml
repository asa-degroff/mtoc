import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Mtoc.Backend 1.0

ApplicationWindow {
    id: window
    width: 1280
    height: 720
    visible: true
    title: SystemInfo.appName + " - " + SystemInfo.appVersion

    // Basic two-pane layout (placeholders)
    RowLayout {
        anchors.fill: parent

        // Library Pane (Placeholder)
        Rectangle {
            id: libraryPanePlaceholder
            Layout.fillWidth: true // Ensure it participates in filling
            Layout.preferredWidth: window.width * 0.35 // 35% of window width
            Layout.fillHeight: true
            color: "lightgrey"
            Text {
                anchors.centerIn: parent
                text: qsTr("Library Pane")
            }
        }

        // Now Playing Pane (Placeholder)
        Rectangle {
            id: nowPlayingPanePlaceholder
            Layout.fillWidth: true // Ensure it participates in filling
            Layout.preferredWidth: window.width * 0.65 // 65% of window width
            Layout.fillHeight: true
            color: "whitesmoke"
            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10 
                Text {
                    text: "Now Playing Pane Placeholder" 
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
                Text {
                    text: "App Name: " + SystemInfo.appName
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
                Text {
                    text: "App Version: " + SystemInfo.appVersion
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    // Connections to backend (will be added later)
    // Component.onCompleted: {
    //     console.log("Main.qml loaded");
    //     // Example: appEngine.someMethod();
    // }
}
