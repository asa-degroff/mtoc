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
    
    QFileInfo fileInfo(filePath);
    QString fileExt = fileInfo.suffix().toLower();
    
    TagLib::FileRef f(filePathCStr);

    if (!f.isNull() && f.tag()) {
        // Log file type
        qDebug() << "MetadataExtractor: File type:" << fileExt;
        
        // Dump all available property keys for this file
        TagLib::PropertyMap properties = f.tag()->properties();
        qDebug() << "MetadataExtractor: Available properties for" << filePath;
        for (TagLib::PropertyMap::ConstIterator it = properties.begin(); it != properties.end(); ++it) {
            QString key = QString::fromStdString(it->first.to8Bit(true));
            QString value = "Empty";
            if (!it->second.isEmpty()) {
                value = QString::fromStdString(it->second.front().to8Bit(true));
            }
            qDebug() << "  Property:" << key << "Values:" << value;
        }
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
        // properties is already declared above
        qDebug() << "MetadataExtractor: --- Checking Album Artist --- Path:" << filePath;
        if (properties.contains("ALBUMARTIST")) {
            qDebug() << "MetadataExtractor: Found 'ALBUMARTIST'. IsEmpty:" << properties["ALBUMARTIST"].isEmpty() << "Value(s):" << (properties["ALBUMARTIST"].isEmpty() ? "N/A" : QString::fromStdString(properties["ALBUMARTIST"].front().to8Bit(true)));
            if (!properties["ALBUMARTIST"].isEmpty()) {
                meta.albumArtist = QString::fromStdString(properties["ALBUMARTIST"].front().to8Bit(true));
                qDebug() << "MetadataExtractor: Set albumArtist from ALBUMARTIST:" << meta.albumArtist;
            }
        } else {
            qDebug() << "MetadataExtractor: 'ALBUMARTIST' key not found.";
        }

        if (meta.albumArtist.isEmpty() && properties.contains("ALBUM ARTIST")) { // Some taggers use a space
            qDebug() << "MetadataExtractor: Found 'ALBUM ARTIST'. IsEmpty:" << properties["ALBUM ARTIST"].isEmpty() << "Value(s):" << (properties["ALBUM ARTIST"].isEmpty() ? "N/A" : QString::fromStdString(properties["ALBUM ARTIST"].front().to8Bit(true)));
            if (!properties["ALBUM ARTIST"].isEmpty()) {
                meta.albumArtist = QString::fromStdString(properties["ALBUM ARTIST"].front().to8Bit(true));
                qDebug() << "MetadataExtractor: Set albumArtist from ALBUM ARTIST:" << meta.albumArtist;
            }
        } else if (meta.albumArtist.isEmpty()) {
            qDebug() << "MetadataExtractor: 'ALBUM ARTIST' key not found or albumArtist already set.";
        }

        if (meta.albumArtist.isEmpty() && properties.contains("TPE2")) { // ID3v2 TPE2 frame
            qDebug() << "MetadataExtractor: Found 'TPE2'. IsEmpty:" << properties["TPE2"].isEmpty() << "Value(s):" << (properties["TPE2"].isEmpty() ? "N/A" : QString::fromStdString(properties["TPE2"].front().to8Bit(true)));
            if (!properties["TPE2"].isEmpty()) {
                 meta.albumArtist = QString::fromStdString(properties["TPE2"].front().to8Bit(true));
                 qDebug() << "MetadataExtractor: Set albumArtist from TPE2:" << meta.albumArtist;
            }
        } else if (meta.albumArtist.isEmpty()) {
            qDebug() << "MetadataExtractor: 'TPE2' key not found or albumArtist already set.";
        }

        // iTunes/M4A specific album artist tag
        if (meta.albumArtist.isEmpty() && properties.contains("aART")) {
            qDebug() << "MetadataExtractor: Found 'aART' (iTunes/M4A). IsEmpty:" << properties["aART"].isEmpty() << "Value(s):" << (properties["aART"].isEmpty() ? "N/A" : QString::fromStdString(properties["aART"].front().to8Bit(true)));
            if (!properties["aART"].isEmpty()) {
                 meta.albumArtist = QString::fromStdString(properties["aART"].front().to8Bit(true));
                 qDebug() << "MetadataExtractor: Set albumArtist from aART:" << meta.albumArtist;
            }
        } else if (meta.albumArtist.isEmpty()) {
            qDebug() << "MetadataExtractor: 'aART' key not found or albumArtist already set.";
        }
        
        qDebug() << "MetadataExtractor: Final meta.albumArtist before return:" << meta.albumArtist;

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
    map.insert("albumArtist", details.albumArtist);
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