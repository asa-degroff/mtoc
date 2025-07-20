#ifndef VIRTUALTRACKDATA_H
#define VIRTUALTRACKDATA_H

#include <QString>
#include <QVariant>
#include <QDateTime>

namespace Mtoc {

// Lightweight structure to hold essential track data without QObject overhead
struct VirtualTrackData {
    int id = 0;
    QString filePath;
    QString title;
    QString artist;
    QString album;
    QString albumArtist;
    QString genre;
    int year = 0;
    int trackNumber = 0;
    int discNumber = 0;
    int duration = 0;  // in seconds
    qint64 fileSize = 0;
    int playCount = 0;
    int rating = 0;
    QDateTime lastPlayed;
    
    // Create from QVariantMap (database query result)
    static VirtualTrackData fromVariantMap(const QVariantMap& map) {
        VirtualTrackData data;
        data.id = map.value("id").toInt();
        data.filePath = map.value("filePath").toString();
        data.title = map.value("title").toString();
        data.artist = map.value("artist").toString();
        data.album = map.value("album").toString();
        data.albumArtist = map.value("albumArtist").toString();
        data.genre = map.value("genre").toString();
        data.year = map.value("year").toInt();
        data.trackNumber = map.value("trackNumber").toInt();
        data.discNumber = map.value("discNumber").toInt();
        data.duration = map.value("duration").toInt();
        data.fileSize = map.value("fileSize").toLongLong();
        data.playCount = map.value("playCount").toInt();
        data.rating = map.value("rating").toInt();
        data.lastPlayed = map.value("lastPlayed").toDateTime();
        return data;
    }
    
    // Convert to QVariantMap for QML or other uses
    QVariantMap toVariantMap() const {
        QVariantMap map;
        map["id"] = id;
        map["filePath"] = filePath;
        map["title"] = title;
        map["artist"] = artist;
        map["album"] = album;
        map["albumArtist"] = albumArtist;
        map["genre"] = genre;
        map["year"] = year;
        map["trackNumber"] = trackNumber;
        map["discNumber"] = discNumber;
        map["duration"] = duration;
        map["fileSize"] = fileSize;
        map["playCount"] = playCount;
        map["rating"] = rating;
        map["lastPlayed"] = lastPlayed;
        return map;
    }
    
    // Minimal memory footprint check
    bool isValid() const {
        return id > 0 && !filePath.isEmpty();
    }
};

} // namespace Mtoc

#endif // VIRTUALTRACKDATA_H