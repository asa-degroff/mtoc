import QtQuick
import QtQuick.Controls
import Mtoc.Backend 1.0

Item {
    id: root

    property string lyricsText: ""

    property var lyricsModel: []
    property int currentLineIndex: -1

    // Timer to avoid spamming index updates
    Timer {
        id: updateTimer
        interval: 100 // Check 10 times per second
        running: root.lyricsModel.length > 0 && lyricsModel[0].time >= 0 && MediaPlayer.state === MediaPlayer.PlayingState
        repeat: true
        onTriggered: root.updateCurrentLineIndex(MediaPlayer.position)
    }

    onLyricsTextChanged: {
        parseLyrics()
    }

    function parseLyrics() {
        currentLineIndex = -1
        lyricsModel = []

        if (!lyricsText) {
            return;
        }

        var trimmedText = lyricsText.trim()
        // Simple heuristic to check for our JSON format
        if (trimmedText.startsWith('[') && trimmedText.endsWith(']')) {
            try {
                var parsed = JSON.parse(trimmedText)
                if (parsed && parsed.length > 0) {
                    lyricsModel = parsed
                    return // Success, we have a synchronized model
                }
            } catch (e) {
                // It looked like JSON but wasn't. Fall through to treat as plain text.
                console.error("LyricsView: Failed to parse lyrics as JSON, falling back to plain text.", e)
            }
        }

        // Fallback for plain text (or failed JSON parse)
        lyricsModel = trimmedText.split('\n').map(function(line) {
            return { time: -1, text: line };
        });
    }

    function updateCurrentLineIndex(position) {
        if (lyricsModel.length === 0 || lyricsModel[0].time < 0) {
            currentLineIndex = -1
            return // Not synchronized
        }

        var newIndex = -1;
        for (var i = 0; i < lyricsModel.length; i++) {
            if (position >= lyricsModel[i].time) {
                newIndex = i;
            } else {
                break; // Timestamps are sorted
            }
        }

        if (newIndex !== -1 && newIndex !== currentLineIndex) {
            currentLineIndex = newIndex
            lyricsListView.positionViewAtIndex(currentLineIndex, ListView.Center)
        }
    }

    ListView {
        id: lyricsListView
        anchors.fill: parent
        model: lyricsModel
        clip: true
        spacing: 12
        
        // Add some padding at the top and bottom to center the text better
        topMargin: height / 2.5
        bottomMargin: height / 2

        delegate: MouseArea {
            width: lyricsListView.width
            height: lyricText.height

            // For synced lyrics, change cursor and allow seeking
            cursorShape: modelData.time >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor

            onClicked: {
                if (modelData.time >= 0) {
                    MediaPlayer.seek(modelData.time)
                }
            }

            Text {
                id: lyricText
                width: parent.width - 40 // Add some horizontal padding
                anchors.horizontalCenter: parent.horizontalCenter
                text: modelData.text
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 20
                color: Theme.primaryText

                // Set opacity and font style for the current line
                opacity: index === root.currentLineIndex ? 1.0 : 0.6
                font.bold: index === root.currentLineIndex

                Behavior on opacity { NumberAnimation { duration: 200 } }
            }
        }

        // Placeholder for when there are no lyrics
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            visible: !lyricsText

            Label {
                anchors.centerIn: parent
                text: "No lyrics available for this track."
                font.pixelSize: 16
                color: Theme.secondaryText
            }
        }
    }
}
