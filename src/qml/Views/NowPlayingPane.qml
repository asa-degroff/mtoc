import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Mtoc.Backend 1.0
import "../Components"

Item {
    id: root
    
    property string currentAlbumId: ""
    property url albumArtUrl: ""
    property url thumbnailUrl: ""
    
    
    // Temporary debug rectangle
    Rectangle {
        anchors.fill: parent
        color: "#1a1a1a"
        z: -2
    }
    
    // Update album art when track changes (based on album of the track)
    Connections {
        target: MediaPlayer
        
        function onCurrentTrackChanged(track) {
            if (track && track.album && track.albumArtist) {
                var newAlbumId = track.albumArtist + "_" + track.album
                if (newAlbumId !== currentAlbumId) {
                    currentAlbumId = newAlbumId
                    // Use the album artist and album title from the track, URL-encoded
                    var encodedArtist = encodeURIComponent(track.albumArtist)
                    var encodedAlbum = encodeURIComponent(track.album)
                    albumArtUrl = "image://albumart/" + encodedArtist + "/" + encodedAlbum + "/full"
                    thumbnailUrl = "image://albumart/" + encodedArtist + "/" + encodedAlbum + "/thumbnail"
                }
            } else {
                currentAlbumId = ""
                albumArtUrl = ""
                thumbnailUrl = ""
            }
        }
    }
    
    // Blurred background using thumbnail for efficiency
    BlurredBackground {
        anchors.fill: parent
        source: thumbnailUrl
        blurRadius: 80
        backgroundOpacity: 0.4
    }
    
    // Dark overlay for better contrast
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.4
    }
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 40
        spacing: 20
        
        // Album art
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            
            Image {
                id: albumArt
                anchors.centerIn: parent
                width: parent.width * 0.9
                height: parent.height
                source: albumArtUrl
                fillMode: Image.PreserveAspectFit
                cache: true
                
                // Drop shadow effect
                layer.enabled: true
                layer.effect: DropShadow {
                    horizontalOffset: 0
                    verticalOffset: 4
                    radius: 16
                    samples: 32
                    color: "#80000000"
                }
                
                // Placeholder when no album art
                Rectangle {
                    anchors.fill: parent
                    color: "#202020"
                    visible: albumArt.status !== Image.Ready || !albumArtUrl
                    
                    Text {
                        anchors.centerIn: parent
                        text: "♪"
                        font.pixelSize: parent.width * 0.3
                        color: "#404040"
                    }
                }
            }
        }
        
        // Track information
        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            spacing: 4
            
            Label {
                id: titleLabel
                Layout.fillWidth: true
                text: MediaPlayer.currentTrack ? MediaPlayer.currentTrack.title : ""
                font.pixelSize: 24
                font.weight: Font.DemiBold
                color: "white"
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }
            
            Label {
                id: artistLabel
                Layout.fillWidth: true
                text: MediaPlayer.currentTrack ? MediaPlayer.currentTrack.artist : ""
                font.pixelSize: 18
                color: "#b0b0b0"
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }
            
            Label {
                id: albumLabel
                Layout.fillWidth: true
                text: MediaPlayer.currentTrack ? MediaPlayer.currentTrack.album : ""
                font.pixelSize: 16
                color: "#808080"
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }
        }
        
        // Playback controls
        PlaybackControls {
            Layout.fillWidth: true
            Layout.preferredHeight: 120
            
            onPlayPauseClicked: MediaPlayer.togglePlayPause()
            onPreviousClicked: MediaPlayer.previous()
            onNextClicked: MediaPlayer.next()
            onSeekRequested: function(position) {
                MediaPlayer.seek(position)
            }
        }
        
        Item {
            Layout.preferredHeight: 20
        }
    }
}