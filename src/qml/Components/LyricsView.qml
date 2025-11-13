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

    // Handle position changes when paused (timer only runs when playing)
    Connections {
        target: MediaPlayer
        function onPositionChanged() {
            // Only update when timer is not running (i.e., when paused or stopped)
            if (!updateTimer.running && root.lyricsModel.length > 0 && root.lyricsModel[0].time >= 0) {
                root.updateCurrentLineIndex(MediaPlayer.position)
            }
        }
    }

    onLyricsTextChanged: {
        parseLyrics()
    }

    function parseLrcFormat(text) {
        // Parse raw LRC format lyrics with timestamps like [mm:ss.xx]
        // Returns array of {time: milliseconds, text: "lyrics"} or null if not LRC format

        var lines = text.split('\n')
        var lrcData = []
        var hasAnyTimestamp = false

        // Regex to match LRC timestamps: [mm:ss.xx] or [mm:ss.xxx]
        var timestampRegex = /\[(\d{1,2}):(\d{2})\.(\d{2,3})\]/g

        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (!line) continue

            // Find all timestamps in this line
            var timestamps = []
            var match
            timestampRegex.lastIndex = 0 // Reset regex state

            while ((match = timestampRegex.exec(line)) !== null) {
                var minutes = parseInt(match[1], 10)
                var seconds = parseInt(match[2], 10)
                var centiseconds = match[3]

                // Normalize centiseconds/milliseconds
                var ms
                if (centiseconds.length === 2) {
                    // Format: [mm:ss.xx] where xx is centiseconds
                    ms = parseInt(centiseconds, 10) * 10
                } else {
                    // Format: [mm:ss.xxx] where xxx is milliseconds
                    ms = parseInt(centiseconds, 10)
                }

                var totalMs = (minutes * 60 * 1000) + (seconds * 1000) + ms
                timestamps.push(totalMs)
                hasAnyTimestamp = true
            }

            // Extract lyrics text (everything after the last timestamp)
            var lyricsText = line.replace(/\[\d{1,2}:\d{2}\.\d{2,3}\]/g, '').trim()

            // Skip metadata lines like [ti:title], [ar:artist], [al:album]
            if (line.match(/^\[(?![\d]{1,2}:).*\]/) && !lyricsText) {
                continue
            }

            // If line has timestamps, create entries for each timestamp
            if (timestamps.length > 0) {
                for (var j = 0; j < timestamps.length; j++) {
                    lrcData.push({
                        time: timestamps[j],
                        text: lyricsText
                    })
                }
            } else if (lyricsText) {
                // Line has text but no timestamp - add as plain text
                lrcData.push({
                    time: -1,
                    text: lyricsText
                })
            }
        }

        // Only return parsed data if we found at least one timestamp
        if (!hasAnyTimestamp) {
            return null
        }

        // Sort by timestamp (important for syncing)
        lrcData.sort(function(a, b) {
            if (a.time < 0) return 1  // Put non-timestamped lines at end
            if (b.time < 0) return -1
            return a.time - b.time
        })

        return lrcData
    }

    function parseLyrics() {
        currentLineIndex = -1
        lyricsModel = []

        if (!lyricsText) {
            return;
        }

        var trimmedText = lyricsText.trim()

        // Try 1: Parse as JSON format (from SYLT frames or external .lrc files)
        if (trimmedText.startsWith('[') && trimmedText.endsWith(']')) {
            try {
                var parsed = JSON.parse(trimmedText)
                if (parsed && parsed.length > 0) {
                    lyricsModel = parsed
                    return // Success, we have a synchronized model
                }
            } catch (e) {
                // JSON parse failed, continue to try LRC format
            }
        }

        // Try 2: Parse as raw LRC format (embedded lyrics with timestamps)
        var lrcParsed = parseLrcFormat(trimmedText)
        if (lrcParsed !== null && lrcParsed.length > 0) {
            lyricsModel = lrcParsed
            return // Success, parsed LRC timestamps
        }

        // Fallback: Treat as plain text (no synchronization)
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
