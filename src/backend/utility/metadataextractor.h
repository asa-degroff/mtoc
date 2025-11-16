#ifndef METADATAEXTRACTOR_H
#define METADATAEXTRACTOR_H

#include <QObject>
#include <QString>
#include <QVariantMap>
#include <QMap>

// TagLib forward declarations (prefer includes in .cpp if possible to reduce compile times)
// However, for Fileref, it's common to include directly.
#include <taglib/fileref.h>
#include <taglib/tag.h>
#include <taglib/id3v2frame.h>
#include <taglib/synchronizedlyricsframe.h>

namespace Mtoc {

class MetadataExtractor : public QObject
{
    Q_OBJECT
public:
    explicit MetadataExtractor(QObject *parent = nullptr);

    struct TrackMetadata {
        QString title;
        QString artist;
        QStringList albumArtists;  // Changed from QString to QStringList for multi-artist support
        QString originalAlbumArtistString;  // Original combined string for display
        QString album;
        QString genre;
        int year = 0;
        int trackNumber = 0;
        int discNumber = 0;
        int duration = 0; // in seconds
        QString lyrics;
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

private:
    std::pair<QString, QMap<qint64, QString>> parseLrcFile(const QString &lrcFilePath);
    QMap<qint64, QString> parseSyltFrame(const TagLib::ID3v2::SynchronizedLyricsFrame *frame);
    QString findMatchingLrcFile(const QString &audioFilePath) const;
    QString findExternalAlbumArt(const QString &audioFilePath) const;
    void checkExternalAlbumArt(const QString &filePath, TrackMetadata &meta, bool extractAlbumArt) const;
    QString findLongestCommonSubstring(const QString &s1, const QString &s2, int minLength) const;

    // Helper to parse album artists from TagLib StringList with multi-line and delimiter support
    QStringList parseAlbumArtists(const TagLib::StringList& tagLibList, QString& outOriginalString) const;
    // Overload for single QString values (e.g., from M4A or single TPE2 frames)
    QStringList parseAlbumArtists(const QString& singleValue, QString& outOriginalString) const;
};

} // namespace Mtoc

#endif // METADATAEXTRACTOR_H
