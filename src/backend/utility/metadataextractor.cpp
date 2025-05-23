#include "metadataextractor.h"
#include <QDebug>
#include <QFileInfo>

// TagLib format-specific includes
#include <taglib/mp4file.h>
#include <taglib/mpegfile.h>
#include <taglib/id3v2tag.h>
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
    
    // Special case for MP3 files with ID3v2 tags
    if (fileExt == "mp3") {
        qDebug() << "MetadataExtractor: Using MP3-specific handling for" << filePath;
        TagLib::MPEG::File mpegFile(filePathCStr);
        
        if (mpegFile.isValid()) {
            // Get the basic metadata first using the generic tag interface
            if (mpegFile.tag()) {
                TagLib::Tag* tag = mpegFile.tag();
                meta.title = QString::fromStdString(tag->title().to8Bit(true));
                meta.artist = QString::fromStdString(tag->artist().to8Bit(true));
                meta.album = QString::fromStdString(tag->album().to8Bit(true));
                meta.genre = QString::fromStdString(tag->genre().to8Bit(true));
                meta.year = tag->year();
                meta.trackNumber = tag->track();
            }
            
            // Now try to get album artist from ID3v2 tag specifically
            if (mpegFile.hasID3v2Tag()) {
                TagLib::ID3v2::Tag* id3v2Tag = mpegFile.ID3v2Tag();
                
                // Debug all ID3v2 frames
                qDebug() << "MetadataExtractor: ID3v2 frames in" << filePath;
                TagLib::ID3v2::FrameList allFrames = id3v2Tag->frameList();
                for (TagLib::ID3v2::FrameList::ConstIterator it = allFrames.begin(); it != allFrames.end(); ++it) {
                    qDebug() << "  ID3v2 Frame:" << (*it)->frameID().data() << "=" << ((*it)->toString().isEmpty() ? "[Empty]" : QString::fromStdString((*it)->toString().to8Bit(true)));
                }
                
                // Look for TPE2 frame (Album Artist in ID3v2)
                TagLib::ID3v2::FrameList TPE2Frames = id3v2Tag->frameListMap()["TPE2"];
                if (!TPE2Frames.isEmpty() && !TPE2Frames.front()->toString().isEmpty()) {
                    meta.albumArtist = QString::fromStdString(TPE2Frames.front()->toString().to8Bit(true));
                    qDebug() << "MetadataExtractor: Found ID3v2 album artist (TPE2):" << meta.albumArtist;
                } else {
                    qDebug() << "MetadataExtractor: No ID3v2 album artist (TPE2) found";
                }
            }
            
            // Get audio properties
            if (mpegFile.audioProperties()) {
                meta.duration = mpegFile.audioProperties()->lengthInSeconds();
            }
            
            // If album artist still empty, check the standard properties too
            if (meta.albumArtist.isEmpty()) {
                TagLib::PropertyMap properties = mpegFile.properties();
                
                qDebug() << "MetadataExtractor: Also checking standard properties for" << filePath;
                for (TagLib::PropertyMap::ConstIterator it = properties.begin(); it != properties.end(); ++it) {
                    QString key = QString::fromStdString(it->first.to8Bit(true));
                    QString value = "Empty";
                    if (!it->second.isEmpty()) {
                        value = QString::fromStdString(it->second.front().to8Bit(true));
                    }
                    qDebug() << "  Standard Property:" << key << "Values:" << value;
                }
                
                // Check standard album artist tags
                if (properties.contains("ALBUMARTIST") && !properties["ALBUMARTIST"].isEmpty()) {
                    meta.albumArtist = QString::fromStdString(properties["ALBUMARTIST"].front().to8Bit(true));
                    qDebug() << "MetadataExtractor: Found ALBUMARTIST property:" << meta.albumArtist;
                } else if (properties.contains("ALBUM ARTIST") && !properties["ALBUM ARTIST"].isEmpty()) {
                    meta.albumArtist = QString::fromStdString(properties["ALBUM ARTIST"].front().to8Bit(true));
                    qDebug() << "MetadataExtractor: Found 'ALBUM ARTIST' property:" << meta.albumArtist;
                }
            }
            
            qDebug() << "MetadataExtractor: Final MP3 meta.albumArtist:" << meta.albumArtist;
            return meta;
        }
    }
    
    // Special case for M4A/MP4 files (iTunes format)
    if (fileExt == "m4a" || fileExt == "m4p" || fileExt == "mp4") {
        qDebug() << "MetadataExtractor: Using MP4-specific handling for" << filePath;
        TagLib::MP4::File mp4File(filePathCStr);
        
        if (mp4File.isValid() && mp4File.tag()) {
            TagLib::MP4::Tag* mp4Tag = mp4File.tag();
            TagLib::MP4::ItemMap items = mp4Tag->itemMap();
            
            // Dump all MP4 items
            qDebug() << "MetadataExtractor: MP4 tags found in" << filePath;
            for (TagLib::MP4::ItemMap::ConstIterator it = items.begin(); it != items.end(); ++it) {
                QString key = QString::fromLatin1(it->first.toCString());
                QString value = "[Complex value]";
                
                // For MP4::Item, we need to check what type it might be by trying to convert
                // MP4 items can be StringList, IntPair, etc. without explicit type checking
                try {
                    // Try as a string list first (most common for text tags)
                    TagLib::StringList stringList = it->second.toStringList();
                    if (!stringList.isEmpty()) {
                        value = QString::fromStdString(stringList.front().to8Bit(true));
                    }
                } catch (...) {
                    // Not a string list, try other types or just leave as [Complex value]
                }
                
                qDebug() << "  MP4 Item:" << key << "=" << value;
            }
            
            // Extract standard iTunes tags
            // Standard iTunes tag mapping:
            // ©nam = title
            // ©ART = artist
            // aART = album artist
            // ©alb = album
            // ©gen = genre
            // ©day = year/date
            // trkn = track number
            
            // Use a helper function to safely extract string values
            auto getStringValue = [&](const char* key) -> QString {
                if (items.contains(key)) {
                    try {
                        TagLib::StringList values = items[key].toStringList();
                        if (!values.isEmpty()) {
                            return QString::fromStdString(values.front().to8Bit(true));
                        }
                    } catch (...) {
                        // Not a string list
                    }
                }
                return QString();
            };
            
            // Also check the standard PropertyMap
            TagLib::PropertyMap properties = mp4Tag->properties();
            qDebug() << "MetadataExtractor: Also checking standard properties for" << filePath;
            for (TagLib::PropertyMap::ConstIterator it = properties.begin(); it != properties.end(); ++it) {
                QString key = QString::fromStdString(it->first.to8Bit(true));
                QString value = "Empty";
                if (!it->second.isEmpty()) {
                    value = QString::fromStdString(it->second.front().to8Bit(true));
                }
                qDebug() << "  Standard Property:" << key << "Values:" << value;
            }
            
            // TITLE - try iTunes tag first, then standard tag
            meta.title = getStringValue("©nam");
            if (meta.title.isEmpty() && properties.contains("TITLE") && !properties["TITLE"].isEmpty()) {
                meta.title = QString::fromStdString(properties["TITLE"].front().to8Bit(true));
                qDebug() << "MetadataExtractor: Using standard TITLE tag:" << meta.title;
            }
            
            // ARTIST - try iTunes tag first, then standard tag
            meta.artist = getStringValue("©ART");
            if (meta.artist.isEmpty() && properties.contains("ARTIST") && !properties["ARTIST"].isEmpty()) {
                meta.artist = QString::fromStdString(properties["ARTIST"].front().to8Bit(true));
                qDebug() << "MetadataExtractor: Using standard ARTIST tag:" << meta.artist;
            }
            
            // ALBUM - try iTunes tag first, then standard tag
            meta.album = getStringValue("©alb");
            if (meta.album.isEmpty() && properties.contains("ALBUM") && !properties["ALBUM"].isEmpty()) {
                meta.album = QString::fromStdString(properties["ALBUM"].front().to8Bit(true));
                qDebug() << "MetadataExtractor: Using standard ALBUM tag:" << meta.album;
            }
            
            // GENRE - try iTunes tag first, then standard tag
            meta.genre = getStringValue("©gen");
            if (meta.genre.isEmpty() && properties.contains("GENRE") && !properties["GENRE"].isEmpty()) {
                meta.genre = QString::fromStdString(properties["GENRE"].front().to8Bit(true));
                qDebug() << "MetadataExtractor: Using standard GENRE tag:" << meta.genre;
            }
            
            // YEAR - try iTunes tag first, then standard tag
            QString yearStr = getStringValue("©day");
            if (yearStr.isEmpty() && properties.contains("DATE") && !properties["DATE"].isEmpty()) {
                yearStr = QString::fromStdString(properties["DATE"].front().to8Bit(true));
                qDebug() << "MetadataExtractor: Using standard DATE tag for year:" << yearStr;
            }
            if (!yearStr.isEmpty()) {
                // Often the year is in format YYYY or YYYY-MM-DD
                meta.year = yearStr.left(4).toUInt();
            }
            
            // Track number
            if (items.contains("trkn")) {
                try {
                    // Track number is usually stored as a pair (track, total)
                    TagLib::MP4::Item::IntPair trackPair = items["trkn"].toIntPair();
                    meta.trackNumber = trackPair.first;
                } catch (...) {
                    // Failed to get track number
                }
            }
            
            // Album Artist - this is the key part for our issue
            meta.albumArtist = getStringValue("aART");
            if (!meta.albumArtist.isEmpty()) {
                qDebug() << "MetadataExtractor: Found MP4 album artist tag (aART):" << meta.albumArtist;
            } else {
                qDebug() << "MetadataExtractor: No MP4 album artist tag (aART) found";
                
                // Try alternative custom tag
                meta.albumArtist = getStringValue("----:com.apple.iTunes:ALBUMARTIST");
                if (!meta.albumArtist.isEmpty()) {
                    qDebug() << "MetadataExtractor: Found iTunes custom album artist tag:" << meta.albumArtist;
                }
            }
            
            // Audio properties from the MP4 file
            if (mp4File.audioProperties()) {
                meta.duration = mp4File.audioProperties()->lengthInSeconds();
            }
            
            // Return here since we've handled everything MP4-specific
            qDebug() << "MetadataExtractor: Final MP4 meta.albumArtist:" << meta.albumArtist;
            return meta;
        }
    }
    
    // Standard handling for non-MP4 files
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