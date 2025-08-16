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
    
    color: Theme.backgroundColor
    
    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        
        ColumnLayout {
            width: parent.availableWidth
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            anchors.topMargin: 20
            anchors.bottomMargin: 20
            spacing: 24
            
            // Title
            Label {
                text: "Settings"
                font.pixelSize: 20
                font.bold: true
                color: Theme.primaryText
                Layout.fillWidth: true
            }
            
            // Queue Behavior Section
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: queueBehaviorLayout.implicitHeight + 24
                color: Theme.panelBackground
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
                        color: Theme.primaryText
                    }
                    
                    Label {
                        text: "Default action for playing an album or playlist if queue has been modified:"
                        font.pixelSize: 14
                        color: Theme.secondaryText
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }
                    
                    ComboBox {
                        id: queueActionCombo
                        Layout.preferredWidth: 200
                        Layout.preferredHeight: 36
                        model: ["Replace queue", "Play next", "Play last", "Ask every time"]
                        currentIndex: SettingsManager.queueActionDefault
                        
                        onActivated: function(index) {
                            SettingsManager.queueActionDefault = index
                        }
                        
                        background: Rectangle {
                            color: parent.hovered ? Theme.inputBackgroundHover : Theme.inputBackground
                            radius: 4
                            border.width: 1
                            border.color: Theme.borderColor
                        }
                        
                        contentItem: Text {
                            text: parent.displayText
                            color: Theme.primaryText
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
                                model: queueActionCombo.popup.visible ? queueActionCombo.model : null
                                currentIndex: queueActionCombo.highlightedIndex
                                
                                delegate: ItemDelegate {
                                    width: queueActionCombo.width
                                    height: 36
                                    
                                    contentItem: Text {
                                        text: modelData
                                        color: parent.hovered ? Theme.primaryText : Theme.secondaryText
                                        font.pixelSize: 14
                                        verticalAlignment: Text.AlignVCenter
                                        leftPadding: 8
                                    }
                                    
                                    background: Rectangle {
                                        color: parent.hovered ? Theme.selectedBackground : "transparent"
                                        radius: 2
                                    }
                                    
                                    onClicked: {
                                        queueActionCombo.currentIndex = index
                                        queueActionCombo.activated(index)
                                        queueActionCombo.popup.close()
                                    }
                                }
                                
                                ScrollIndicator.vertical: ScrollIndicator { }
                            }
                            
                            background: Rectangle {
                                color: Theme.backgroundColor
                                border.color: Theme.borderColor
                                border.width: 1
                                radius: 4
                            }
                        }
                    }
                }
            }
            
            // Display Options Section
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: displayLayout.implicitHeight + 24
                color: Theme.panelBackground
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
                        color: Theme.primaryText
                    }
                    
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        
                        Label {
                            text: "Theme:"
                            font.pixelSize: 14
                            color: Theme.secondaryText
                            Layout.preferredWidth: 100
                        }
                        
                        ComboBox {
                            id: themeComboBox
                            Layout.preferredWidth: 150
                            Layout.preferredHeight: 36
                            model: ["Dark", "Light", "System"]
                            editable: false
                            currentIndex: {
                                switch (SettingsManager.theme) {
                                    case SettingsManager.Dark: return 0
                                    case SettingsManager.Light: return 1
                                    case SettingsManager.System: return 2
                                    default: return 0
                                }
                            }
                            
                            onActivated: function(index) {
                                switch (index) {
                                    case 0: SettingsManager.theme = SettingsManager.Dark; break
                                    case 1: SettingsManager.theme = SettingsManager.Light; break
                                    case 2: SettingsManager.theme = SettingsManager.System; break
                                }
                            }
                            
                            background: Rectangle {
                                color: parent.hovered ? Theme.inputBackgroundHover : Theme.inputBackground
                                radius: 4
                                border.width: 1
                                border.color: Theme.borderColor
                            }
                            
                            contentItem: Text {
                                text: parent.displayText
                                color: Theme.primaryText
                                font.pixelSize: 14
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 8
                                rightPadding: 30  // Leave space for indicator
                            }
                            
                            indicator: Canvas {
                                id: themeIndicatorCanvas
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
                                
                                Connections {
                                    target: Theme
                                    function onIsDarkChanged() {
                                        themeIndicatorCanvas.requestPaint()
                                    }
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
                                    model: themeComboBox.popup.visible ? themeComboBox.model : null
                                    currentIndex: themeComboBox.highlightedIndex
                                    
                                    delegate: ItemDelegate {
                                        width: themeComboBox.width
                                        height: 36
                                        
                                        contentItem: Text {
                                            text: modelData
                                            color: parent.hovered ? Theme.primaryText : Theme.secondaryText
                                            font.pixelSize: 14
                                            verticalAlignment: Text.AlignVCenter
                                            leftPadding: 8
                                        }
                                        
                                        background: Rectangle {
                                            color: parent.hovered ? Theme.selectedBackground : "transparent"
                                            radius: 2
                                        }
                                        
                                        onClicked: {
                                            themeComboBox.currentIndex = index
                                            themeComboBox.activated(index)
                                            themeComboBox.popup.close()
                                        }
                                    }
                                    
                                    ScrollIndicator.vertical: ScrollIndicator { }
                                }
                                
                                background: Rectangle {
                                    color: Theme.backgroundColor
                                    border.color: Theme.borderColor
                                    border.width: 1
                                    radius: 4
                                }
                            }
                        }
                        
                        Item { Layout.fillWidth: true }
                    }
                    
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        
                        Label {
                            text: "Layout Mode:"
                            font.pixelSize: 14
                            color: Theme.secondaryText
                            Layout.preferredWidth: 100
                        }
                        
                        ComboBox {
                            id: layoutModeComboBox
                            Layout.preferredWidth: 150
                            Layout.preferredHeight: 36
                            model: ["Wide", "Compact", "Automatic"]
                            currentIndex: {
                                switch(SettingsManager.layoutMode) {
                                    case SettingsManager.Wide: return 0
                                    case SettingsManager.Compact: return 1
                                    case SettingsManager.Automatic: return 2
                                    default: return 2
                                }
                            }
                            
                            onActivated: function(index) {
                                switch(index) {
                                    case 0: SettingsManager.layoutMode = SettingsManager.Wide; break
                                    case 1: SettingsManager.layoutMode = SettingsManager.Compact; break
                                    case 2: SettingsManager.layoutMode = SettingsManager.Automatic; break
                                }
                            }
                            
                            background: Rectangle {
                                color: parent.hovered ? Theme.inputBackgroundHover : Theme.inputBackground
                                radius: 4
                                border.width: 1
                                border.color: Theme.borderColor
                            }
                            
                            contentItem: Text {
                                text: parent.displayText
                                color: Theme.primaryText
                                font.pixelSize: 14
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 8
                                rightPadding: 30  // Leave space for indicator
                            }
                            
                            indicator: Canvas {
                                id: layoutIndicatorCanvas
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
                                
                                Connections {
                                    target: Theme
                                    function onIsDarkChanged() {
                                        layoutIndicatorCanvas.requestPaint()
                                    }
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
                                    model: layoutModeComboBox.popup.visible ? layoutModeComboBox.model : null
                                    currentIndex: layoutModeComboBox.highlightedIndex
                                    
                                    delegate: ItemDelegate {
                                        width: layoutModeComboBox.width
                                        height: 36
                                        
                                        contentItem: Text {
                                            text: modelData
                                            color: parent.hovered ? Theme.primaryText : Theme.secondaryText
                                            font.pixelSize: 14
                                            verticalAlignment: Text.AlignVCenter
                                            leftPadding: 8
                                        }
                                        
                                        background: Rectangle {
                                            color: parent.hovered ? Theme.selectedBackground : "transparent"
                                            radius: 2
                                        }
                                        
                                        onClicked: {
                                            layoutModeComboBox.currentIndex = index
                                            layoutModeComboBox.activated(index)
                                            layoutModeComboBox.popup.close()
                                        }
                                    }
                                    
                                    ScrollIndicator.vertical: ScrollIndicator { }
                                }
                                
                                background: Rectangle {
                                    color: Theme.backgroundColor
                                    border.color: Theme.borderColor
                                    border.width: 1
                                    radius: 4
                                }
                            }
                        }
                        
                        Item { Layout.fillWidth: true }
                    }
                    
                    // Help text for automatic mode
                    Label {
                        Layout.fillWidth: true
                        Layout.leftMargin: 20
                        text: "Automatic mode switches to Compact when window width < 1200px"
                        font.pixelSize: 12
                        color: Theme.tertiaryText
                        visible: layoutModeComboBox.currentIndex === 2
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
                            color: Theme.secondaryText
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: parent.indicator.width + parent.spacing
                        }
                        
                        indicator: Rectangle {
                            implicitWidth: 20
                            implicitHeight: 20
                            x: parent.leftPadding
                            y: parent.height / 2 - height / 2
                            radius: 3
                            color: parent.checked ? Theme.selectedBackground : Theme.inputBackground
                            border.color: parent.checked ? Theme.linkColor : Theme.borderColor
                            
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
                color: Theme.panelBackground
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
                        color: Theme.primaryText
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
                            color: Theme.secondaryText
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: parent.indicator.width + parent.spacing
                        }
                        
                        indicator: Rectangle {
                            implicitWidth: 20
                            implicitHeight: 20
                            x: parent.leftPadding
                            y: parent.height / 2 - height / 2
                            radius: 3
                            color: parent.checked ? Theme.selectedBackground : Theme.inputBackground
                            border.color: parent.checked ? Theme.linkColor : Theme.borderColor
                            
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
            
            // Audio Engine Section
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: audioEngineLayout.implicitHeight + 24
                color: Theme.panelBackground
                radius: 4
                
                ColumnLayout {
                    id: audioEngineLayout
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12
                    
                    Label {
                        text: "Audio Engine"
                        font.pixelSize: 16
                        font.bold: true
                        color: Theme.primaryText
                    }
                    
                    // Pre-amplification (always available)
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        
                        RowLayout {
                            Layout.fillWidth: true
                            
                            Label {
                                text: "Pre-amplification:"
                                font.pixelSize: 14
                                color: Theme.secondaryText
                                Layout.preferredWidth: 120
                            }
                            
                            Slider {
                                id: preAmpSlider
                                Layout.fillWidth: true
                                from: -15.0
                                to: 15.0
                                value: SettingsManager.replayGainPreAmp
                                stepSize: 0.5
                                
                                onValueChanged: {
                                    SettingsManager.replayGainPreAmp = value
                                }
                                
                                background: Rectangle {
                                    x: preAmpSlider.leftPadding
                                    y: preAmpSlider.topPadding + preAmpSlider.availableHeight / 2 - height / 2
                                    implicitWidth: 200
                                    implicitHeight: 4
                                    width: preAmpSlider.availableWidth
                                    height: implicitHeight
                                    radius: 2
                                    color: Theme.inputBackground
                                    
                                    Rectangle {
                                        width: preAmpSlider.visualPosition * parent.width
                                        height: parent.height
                                        color: Theme.linkColor
                                        radius: 2
                                    }
                                }
                                
                                handle: Rectangle {
                                    x: preAmpSlider.leftPadding + preAmpSlider.visualPosition * (preAmpSlider.availableWidth - width)
                                    y: preAmpSlider.topPadding + preAmpSlider.availableHeight / 2 - height / 2
                                    implicitWidth: 16
                                    implicitHeight: 16
                                    radius: 8
                                    color: preAmpSlider.pressed ? Theme.selectedBackground : Theme.linkColor
                                }
                            }
                            
                            Label {
                                text: preAmpSlider.value.toFixed(1) + " dB"
                                font.pixelSize: 14
                                color: Theme.secondaryText
                                Layout.preferredWidth: 60
                            }
                        }
                        
                        Label {
                            Layout.fillWidth: true
                            Layout.leftMargin: 20
                            text: "Adjust overall volume level"
                            font.pixelSize: 12
                            color: Theme.tertiaryText
                            wrapMode: Text.WordWrap
                        }
                    }
                    
                    // Separator line
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: Theme.borderColor
                        opacity: 0.3
                    }
                    
                    Label {
                        text: "Replay Gain"
                        font.pixelSize: 14
                        font.bold: true
                        color: Theme.primaryText
                    }
                    
                    Label {
                        text: "Normalizes volume across tracks and albums"
                        font.pixelSize: 12
                        color: Theme.tertiaryText
                        Layout.fillWidth: true
                    }
                    
                    CheckBox {
                        id: replayGainEnabledCheck
                        text: "Enable Replay Gain"
                        checked: SettingsManager.replayGainEnabled
                        
                        onToggled: {
                            SettingsManager.replayGainEnabled = checked
                        }
                        
                        contentItem: Text {
                            text: parent.text
                            font.pixelSize: 14
                            color: Theme.secondaryText
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: parent.indicator.width + parent.spacing
                        }
                        
                        indicator: Rectangle {
                            implicitWidth: 20
                            implicitHeight: 20
                            x: parent.leftPadding
                            y: parent.height / 2 - height / 2
                            radius: 3
                            color: parent.checked ? Theme.selectedBackground : Theme.inputBackground
                            border.color: parent.checked ? Theme.linkColor : Theme.borderColor
                            
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
                    
                    // Mode selection (only visible when enabled)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        visible: replayGainEnabledCheck.checked
                        
                        Label {
                            text: "Mode:"
                            font.pixelSize: 14
                            color: Theme.secondaryText
                            Layout.preferredWidth: 100
                        }
                        
                        ComboBox {
                            id: replayGainModeCombo
                            Layout.preferredWidth: 150
                            Layout.preferredHeight: 36
                            model: ["Album", "Track"]
                            currentIndex: {
                                // Map SettingsManager mode to combo index (skip Off = 0)
                                var mode = SettingsManager.replayGainMode
                                if (mode === SettingsManager.Album) return 0
                                if (mode === SettingsManager.Track) return 1
                                return 0 // Default to Album
                            }
                            
                            onActivated: function(index) {
                                // Map combo index to SettingsManager mode
                                if (index === 0) SettingsManager.replayGainMode = SettingsManager.Album
                                else if (index === 1) SettingsManager.replayGainMode = SettingsManager.Track
                            }
                            
                            background: Rectangle {
                                color: parent.hovered ? Theme.inputBackgroundHover : Theme.inputBackground
                                radius: 4
                                border.width: 1
                                border.color: Theme.borderColor
                            }
                            
                            contentItem: Text {
                                text: parent.displayText
                                color: Theme.primaryText
                                font.pixelSize: 14
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 8
                                rightPadding: 30
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
                        }
                        
                        Item { Layout.fillWidth: true }
                    }
                    
                    Label {
                        Layout.fillWidth: true
                        Layout.leftMargin: 20
                        text: "Track: Apply gain per track • Album: Preserve relative volume within albums"
                        font.pixelSize: 12
                        color: Theme.tertiaryText
                        visible: replayGainEnabledCheck.checked
                        wrapMode: Text.WordWrap
                    }
                    
                    // Fallback gain (only visible when enabled)
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        visible: replayGainEnabledCheck.checked
                        
                        RowLayout {
                            Layout.fillWidth: true
                            
                            Label {
                                text: "Fallback gain:"
                                font.pixelSize: 14
                                color: Theme.secondaryText
                                Layout.preferredWidth: 120
                            }
                            
                            Slider {
                                id: fallbackGainSlider
                                Layout.fillWidth: true
                                from: -15.0
                                to: 15.0
                                value: SettingsManager.replayGainFallbackGain
                                stepSize: 0.5
                                
                                onValueChanged: {
                                    SettingsManager.replayGainFallbackGain = value
                                }
                                
                                background: Rectangle {
                                    x: fallbackGainSlider.leftPadding
                                    y: fallbackGainSlider.topPadding + fallbackGainSlider.availableHeight / 2 - height / 2
                                    implicitWidth: 200
                                    implicitHeight: 4
                                    width: fallbackGainSlider.availableWidth
                                    height: implicitHeight
                                    radius: 2
                                    color: Theme.inputBackground
                                    
                                    Rectangle {
                                        width: fallbackGainSlider.visualPosition * parent.width
                                        height: parent.height
                                        color: Theme.linkColor
                                        radius: 2
                                    }
                                }
                                
                                handle: Rectangle {
                                    x: fallbackGainSlider.leftPadding + fallbackGainSlider.visualPosition * (fallbackGainSlider.availableWidth - width)
                                    y: fallbackGainSlider.topPadding + fallbackGainSlider.availableHeight / 2 - height / 2
                                    implicitWidth: 16
                                    implicitHeight: 16
                                    radius: 8
                                    color: fallbackGainSlider.pressed ? Theme.selectedBackground : Theme.linkColor
                                }
                            }
                            
                            Label {
                                text: fallbackGainSlider.value.toFixed(1) + " dB"
                                font.pixelSize: 14
                                color: Theme.secondaryText
                                Layout.preferredWidth: 60
                            }
                        }
                        
                        Label {
                            Layout.fillWidth: true
                            Layout.leftMargin: 20
                            text: "Applied when tracks don't have replay gain metadata"
                            font.pixelSize: 12
                            color: Theme.tertiaryText
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
            
            // About Section
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: aboutLayout.implicitHeight + 24
                color: Theme.panelBackground
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
                        color: Theme.primaryText
                    }
                    
                    Label {
                        text: "mtoc - Music Library and Player"
                        font.pixelSize: 14
                        color: Theme.secondaryText
                    }
                    
                    Label {
                        text: "Version 2.1.1"
                        font.pixelSize: 12
                        color: Theme.tertiaryText
                    }
                    
                    Label {
                        text: "© 2025 Asa DeGroff"
                        font.pixelSize: 12
                        color: Theme.tertiaryText
                    }
                    
                    Item { height: 8 }
                    
                    Label {
                        text: "Acknowledgements"
                        font.pixelSize: 14
                        font.bold: true
                        color: Theme.secondaryText
                    }
                    
                    Label {
                        text: "Built with Qt, TagLib, and GStreamer"
                        font.pixelSize: 12
                        color: Theme.tertiaryText
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    Label {
                        text: "License"
                        font.pixelSize: 14
                        font.bold: true
                        color: Theme.secondaryText
                    }

                    Text {
                        text: "mtoc is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. 
                        
mtoc is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with mtoc. If not, see: <a href=\"https://www.gnu.org/licenses/gpl-3.0.html\">https://www.gnu.org/licenses/gpl-3.0.html</a>"
                        font.pixelSize: 12
                        color: Theme.tertiaryText
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