#include "metadataextractor.h"

#include <taglib/tag.h>
#include <taglib/fileref.h>
#include <taglib/tpropertymap.h> // For audioProperties
#include <taglib/audioproperties.h>

#include <QFileInfo>
#include <QDebug>

namespace Mtoc {

MetadataExtractor::MetadataExtractor(QObject *parent)
    : QObject{parent}
{
}

MetadataExtractor::TrackMetadata MetadataExtractor::extract(const QString &filePath)
{
    qDebug() << "MetadataExtractor: Extracting metadata from" << filePath;
    TrackMetadata meta;
    // TagLib uses C-style strings or std::wstring. Convert QString appropriately.
    // For UTF-8 paths, toWString() might not be needed if underlying system uses UTF-8 for char*
    // However, TagLib's FileRef constructor can take a wchar_t* or a char*.
    // Using .toStdString().c_str() is generally problematic with paths containing non-ASCII if not handled correctly.
    // .toLocal8Bit().constData() is often safer for file paths on Linux/macOS.
    // On Windows, toStdWString().c_str() would be preferred.
    // Let's try with toLocal8Bit first, as it's common for Linux.

    // Convert QString to char* for TagLib
    QByteArray filePathBA = filePath.toLocal8Bit();
    const char* filePathCStr = filePathBA.constData();
    qDebug() << "MetadataExtractor: Converted path:" << filePathCStr;
    
    TagLib::FileRef f(filePathCStr);

    if (!f.isNull() && f.tag()) {
        qDebug() << "MetadataExtractor: FileRef is valid and has tags";
        TagLib::Tag *tag = f.tag();

        meta.title = QString::fromStdString(tag->title().to8Bit(true));
        meta.artist = QString::fromStdString(tag->artist().to8Bit(true));
        meta.album = QString::fromStdString(tag->album().to8Bit(true));
        meta.genre = QString::fromStdString(tag->genre().to8Bit(true));
        meta.year = tag->year();
        meta.trackNumber = tag->track();
        // discNumber is not a standard TagLib tag property, often stored in custom ways or TXXX frames.
        // We'll leave it 0 for now or look into specific frame parsing later if needed.

        // Album Artist (often in TPE2 frame for ID3, or ALBUMARTIST for Vorbis/FLAC)
        // TagLib::PropertyMap properties = f.tag()->properties();
        // if (properties.contains("ALBUMARTIST")) {
        //     meta.albumArtist = QString::fromStdString(properties["ALBUMARTIST"].toStringList().front().to8Bit(true));
        // } else if (properties.contains("ALBUM ARTIST")) {
        //     meta.albumArtist = QString::fromStdString(properties["ALBUM ARTIST"].toStringList().front().to8Bit(true));
        // }
        // For simplicity, if album artist is empty, fallback to artist
        if (meta.albumArtist.isEmpty()) {
            meta.albumArtist = meta.artist;
        }

        if (f.audioProperties()) {
            meta.duration = f.audioProperties()->lengthInSeconds();
        }
    } else {
        qWarning() << "Could not read metadata for:" << filePath;
    }
    return meta;
}

QVariantMap MetadataExtractor::extractAsVariantMap(const QString &filePath)
{
    TrackMetadata details = extract(filePath);
    QVariantMap map;
    map.insert("title", details.title);
    map.insert("artist", details.artist);
    map.insert("albumArtist", details.albumArtist.isEmpty() ? details.artist : details.albumArtist);
    map.insert("album", details.album);
    map.insert("genre", details.genre);
    map.insert("year", details.year);
    map.insert("trackNumber", details.trackNumber);
    map.insert("discNumber", details.discNumber);
    map.insert("duration", details.duration);
    map.insert("filePath", filePath); // Also include the original file path
    return map;
}

} // namespace Mtoc