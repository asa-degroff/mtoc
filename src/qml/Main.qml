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
            Layout.fillWidth: true
            Layout.preferredWidth: 400 // Initial width, can be part of a SplitView later
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
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "whitesmoke"
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 10 
                Text {
                    text: "Now Playing Pane Placeholder" 
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: "App Name: " + SystemInfo.appName
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: "App Version: " + SystemInfo.appVersion
                    Layout.alignment: Qt.AlignHCenter
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
