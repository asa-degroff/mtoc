import QtQuick
import QtQuick.Controls
import Mtoc.Backend 1.0

ScrollView {
    id: scrollView
    width: parent.width
    height: parent.height

    property string lyricsText: ""

    Label {
        id: lyricsLabel
        width: scrollView.width - 20
        padding: 10
        wrapMode: Text.WordWrap
        font.pixelSize: 16
        horizontalAlignment: Text.AlignHCenter

        text: lyricsText.trim().length > 0 ? lyricsText : "No lyrics available for this track."
        color: lyricsText.trim().length > 0 ? Theme.primaryText : Theme.secondaryText
    }
}
