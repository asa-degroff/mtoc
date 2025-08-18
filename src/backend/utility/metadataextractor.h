#ifndef METADATAEXTRACTOR_H
#define METADATAEXTRACTOR_H

#include <QObject>
#include <QString>
#include <QVariantMap>

// TagLib forward declarations (prefer includes in .cpp if possible to reduce compile times)
// However, for Fileref, it's common to include directly.
#include <taglib/fileref.h>
#include <taglib/tag.h>

namespace Mtoc {

class MetadataExtractor : public QObject
{
    Q_OBJECT
public:
    explicit MetadataExtractor(QObject *parent = nullptr);

    struct TrackMetadata {
        QString title;
        QString artist;
        QString albumArtist;
        QString album;
        QString genre;
        int year = 0;
        int trackNumber = 0;
        int discNumber = 0;
        int duration = 0; // in seconds
        // Album art data
        QByteArray albumArtData;
        QString albumArtMimeType;
        // Replay gain data
        double replayGainTrackGain = 0.0;
        double replayGainTrackPeak = 0.0;
        double replayGainAlbumGain = 0.0;
        double replayGainAlbumPeak = 0.0;
        bool hasReplayGainTrackGain = false;
        bool hasReplayGainTrackPeak = false;
        bool hasReplayGainAlbumGain = false;
        bool hasReplayGainAlbumPeak = false;
    };

    Q_INVOKABLE TrackMetadata extract(const QString &filePath);
    TrackMetadata extract(const QString &filePath, bool extractAlbumArt);
    // For QML, returning a QVariantMap might be more direct
    Q_INVOKABLE QVariantMap extractAsVariantMap(const QString &filePath);
    QVariantMap extractAsVariantMap(const QString &filePath, bool extractAlbumArt);
    
    // Extract album art specifically
    Q_INVOKABLE QByteArray extractAlbumArt(const QString &filePath);
    Q_INVOKABLE bool hasAlbumArt(const QString &filePath);

};

} // namespace Mtoc

#endif // METADATAEXTRACTOR_H