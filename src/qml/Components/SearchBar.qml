import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Mtoc.Backend 1.0
import "../"

Rectangle {
    id: root
    height: 36
    color: Qt.rgba(0.1, 0.1, 0.1, 0.42)
    radius: 6
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.08)
    
    property alias text: textInput.text
    property string placeholderText: "Search library..."
    property bool hasFocus: textInput.activeFocus
    
    signal searchRequested(string searchTerm)
    signal clearRequested()
    signal focusRequested()
    
    // Inner shadow for depth
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: parent.radius - 1
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.25)
    }
    
    RowLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8
        
        // Search icon - monochromatic SVG-style icon
        Canvas {
            id: searchIcon
            Layout.preferredWidth: 16
            Layout.preferredHeight: 16
            antialiasing: true
            
            property color iconColor: textInput.activeFocus ? "white" : "#999999"
            
            Behavior on iconColor {
                ColorAnimation { duration: 150 }
            }
            
            onIconColorChanged: requestPaint()
            Component.onCompleted: requestPaint()
            
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                
                // Clear canvas
                ctx.clearRect(0, 0, width, height)
                
                // Set stroke style
                ctx.strokeStyle = iconColor
                ctx.lineWidth = 1.5
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                
                // Draw search circle (centered, with padding)
                var centerX = width * 0.4
                var centerY = height * 0.4
                var radius = width * 0.25
                
                ctx.beginPath()
                ctx.arc(centerX, centerY, radius, 0, 2 * Math.PI)
                ctx.stroke()
                
                // Draw search handle (diagonal line from bottom-right of circle)
                var handleStartX = centerX + radius * 0.7
                var handleStartY = centerY + radius * 0.7
                var handleEndX = width * 0.85
                var handleEndY = height * 0.85
                
                ctx.beginPath()
                ctx.moveTo(handleStartX, handleStartY)
                ctx.lineTo(handleEndX, handleEndY)
                ctx.stroke()
            }
        }
        
        // Text input
        TextInput {
            id: textInput
            Layout.fillWidth: true
            font.pixelSize: 13
            color: "white"
            selectByMouse: true
            selectionColor: Qt.rgba(0.25, 0.32, 0.71, 0.5)
            
            // Custom placeholder text rendering
            Text {
                anchors.fill: parent
                text: root.placeholderText
                font: textInput.font
                color: "#666666"
                visible: textInput.text.length === 0 && !textInput.activeFocus
                verticalAlignment: Text.AlignVCenter
            }
            
            onTextChanged: {
                searchTimer.restart()
            }
            
            onActiveFocusChanged: {
                if (activeFocus) {
                    root.focusRequested()
                }
            }
            
            Keys.onEscapePressed: {
                if (text.length > 0) {
                    clear()
                    root.clearRequested()
                } else {
                    focus = false
                }
            }
            
            Keys.onReturnPressed: {
                root.searchRequested(text)
            }
            
            Keys.onEnterPressed: {
                root.searchRequested(text)
            }
            
            function clear() {
                text = ""
            }
        }
        
        // Clear button
        Button {
            id: clearButton
            visible: textInput.text.length > 0
            flat: true
            text: "×"
            font.pixelSize: 16
            font.bold: true
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            
            background: Rectangle {
                color: parent.hovered ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                radius: 10
                
                Behavior on color {
                    ColorAnimation { duration: 150 }
                }
            }
            
            contentItem: Text {
                text: parent.text
                font: parent.font
                color: parent.hovered ? "white" : "#999999"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                
                Behavior on color {
                    ColorAnimation { duration: 150 }
                }
            }
            
            onClicked: {
                textInput.clear()
                root.clearRequested()
            }
        }
    }
    
    // Search timer to debounce rapid typing
    Timer {
        id: searchTimer
        interval: 300 // 300ms delay
        repeat: false
        onTriggered: {
            if (textInput.text.length > 0) {
                root.searchRequested(textInput.text)
            } else {
                root.clearRequested()
            }
        }
    }
    
    // Focus border effect
    states: State {
        when: textInput.activeFocus
        PropertyChanges {
            target: root
            border.color: Qt.rgba(0.37, 0.44, 0.84, 0.6)
            color: Qt.rgba(0.1, 0.1, 0.1, 0.5)
        }
    }
    
    transitions: Transition {
        ColorAnimation { duration: 200 }
    }
    
    // Allow clicking anywhere on the search bar to focus
    MouseArea {
        anchors.fill: parent
        onClicked: {
            textInput.forceActiveFocus()
        }
    }
}