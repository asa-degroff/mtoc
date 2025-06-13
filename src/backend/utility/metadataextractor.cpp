#include "metadataextractor.h"
#include <QDebug>
#include <QFileInfo>
#include <cstring>

// TagLib format-specific includes
#include <taglib/mp4file.h>
#include <taglib/mpegfile.h>
#include <taglib/id3v2tag.h>
#include <taglib/fileref.h>
#include <taglib/tpropertymap.h>
#include <taglib/audioproperties.h>
#include <taglib/attachedpictureframe.h>
#include <taglib/mp4coverart.h>
#include <taglib/flacfile.h>
#include <taglib/flacpicture.h>

namespace Mtoc {

MetadataExtractor::MetadataExtractor(QObject *parent)
    : QObject{parent}
{
}

MetadataExtractor::TrackMetadata MetadataExtractor::extract(const QString &filePath)
{
    return extract(filePath, true);  // Default to extracting album art for backward compatibility
}

MetadataExtractor::TrackMetadata MetadataExtractor::extract(const QString &filePath, bool extractAlbumArt)
{
    // Reduce logging to prevent performance issues
    // qDebug() << "MetadataExtractor: Extracting metadata from" << filePath;
    TrackMetadata meta;
    
    // Check if file exists and is readable
    if (!QFileInfo::exists(filePath)) {
        qWarning() << "MetadataExtractor: File does not exist:" << filePath;
        return meta;
    }
    
    QFileInfo fileInfo(filePath);
    if (!fileInfo.isReadable()) {
        qWarning() << "MetadataExtractor: File is not readable:" << filePath;
        return meta;
    }
    
    try {
    // TagLib uses C-style strings or std::wstring. Convert QString appropriately.
    // For UTF-8 paths, toWString() might not be needed if underlying system uses UTF-8 for char*
    // However, TagLib's FileRef constructor can take a wchar_t* or a char*.
    // Using .toStdString().c_str() is generally problematic with paths containing non-ASCII if not handled correctly.
    // .toLocal8Bit().constData() is often safer for file paths on Linux.

    // Convert QString to char* for TagLib
    QByteArray filePathBA = filePath.toLocal8Bit();
    const char* filePathCStr = filePathBA.constData();
    if (!filePathCStr || strlen(filePathCStr) == 0) {
        qWarning() << "MetadataExtractor: Failed to convert file path to C string:" << filePath;
        return meta;
    }
    // qDebug() << "MetadataExtractor: Processing path:" << filePath;
    
    QString fileExt = fileInfo.suffix().toLower();
    
    // Special case for MP3 files with ID3v2 tags
    if (fileExt == "mp3") {
        // qDebug() << "MetadataExtractor: Using MP3-specific handling for" << filePath;
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
                
                // Debug logging removed - iterating frames can cause crashes with malformed files
                
                // Look for TPE2 frame (Album Artist in ID3v2)
                if (id3v2Tag->frameListMap().contains("TPE2")) {
                    TagLib::ID3v2::FrameList TPE2Frames = id3v2Tag->frameListMap()["TPE2"];
                    if (!TPE2Frames.isEmpty() && TPE2Frames.front()) {
                        TagLib::String albumArtistStr = TPE2Frames.front()->toString();
                        if (!albumArtistStr.isEmpty()) {
                            meta.albumArtist = QString::fromStdString(albumArtistStr.to8Bit(true));
                        }
                        // qDebug() << "MetadataExtractor: Found ID3v2 album artist (TPE2):" << meta.albumArtist;
                    }
                }
                // else qDebug() << "MetadataExtractor: No ID3v2 album artist (TPE2) found";
                
                // Look for TPOS frame (Disc Number in ID3v2)
                if (id3v2Tag->frameListMap().contains("TPOS")) {
                    TagLib::ID3v2::FrameList TPOSFrames = id3v2Tag->frameListMap()["TPOS"];
                    if (!TPOSFrames.isEmpty() && TPOSFrames.front()) {
                        TagLib::String discNumStr = TPOSFrames.front()->toString();
                        if (!discNumStr.isEmpty()) {
                            QString discStr = QString::fromStdString(discNumStr.to8Bit(true));
                            // Disc number might be in format "1" or "1/2"
                            bool ok;
                            meta.discNumber = discStr.split('/').first().toInt(&ok);
                            if (!ok) meta.discNumber = 0;
                            // qDebug() << "MetadataExtractor: Found ID3v2 disc number (TPOS):" << meta.discNumber;
                        }
                    }
                }
            }
            
            // Get audio properties
            if (mpegFile.audioProperties()) {
                meta.duration = mpegFile.audioProperties()->lengthInSeconds();
            }
            
            // If album artist still empty, check the standard properties too
            if (meta.albumArtist.isEmpty()) {
                TagLib::PropertyMap properties = mpegFile.properties();
                
                // Debug logging removed - iterating properties can cause issues
                
                // Check standard album artist tags using safer value() method
                try {
                    TagLib::StringList albumArtistList = properties.value("ALBUMARTIST");
                    if (!albumArtistList.isEmpty() && albumArtistList.size() > 0) {
                        meta.albumArtist = QString::fromStdString(albumArtistList.front().to8Bit(true));
                        qDebug() << "MetadataExtractor: Found ALBUMARTIST property:" << meta.albumArtist;
                    } else {
                        // Try alternate spelling
                        albumArtistList = properties.value("ALBUM ARTIST");
                        if (!albumArtistList.isEmpty() && albumArtistList.size() > 0) {
                            meta.albumArtist = QString::fromStdString(albumArtistList.front().to8Bit(true));
                            qDebug() << "MetadataExtractor: Found 'ALBUM ARTIST' property:" << meta.albumArtist;
                        }
                    }
                } catch (const std::exception& e) {
                    qDebug() << "MetadataExtractor: Exception accessing album artist property:" << e.what();
                } catch (...) {
                    qDebug() << "MetadataExtractor: Failed to access album artist property";
                }
            }
            
            // Extract album art from ID3v2 tag
            if (extractAlbumArt && mpegFile.hasID3v2Tag()) {
                TagLib::ID3v2::Tag* id3v2Tag = mpegFile.ID3v2Tag();
                TagLib::ID3v2::FrameList frameList = id3v2Tag->frameList("APIC");
                
                if (!frameList.isEmpty() && frameList.front()) {
                    // Get the first picture frame
                    TagLib::ID3v2::AttachedPictureFrame* pictureFrame = 
                        dynamic_cast<TagLib::ID3v2::AttachedPictureFrame*>(frameList.front());
                    
                    if (pictureFrame) {
                        // Get the picture data
                        TagLib::ByteVector pictureData = pictureFrame->picture();
                        if (!pictureData.isEmpty()) {
                            meta.albumArtData = QByteArray(pictureData.data(), pictureData.size());
                            
                            // Get MIME type
                            TagLib::String mimeType = pictureFrame->mimeType();
                            meta.albumArtMimeType = QString::fromStdString(mimeType.to8Bit(true));
                        }
                    }
                }
            }
            
            // qDebug() << "MetadataExtractor: Final MP3 meta.albumArtist:" << meta.albumArtist;
            return meta;
        }
    }
    
    // Special case for M4A/MP4 files (iTunes format)
    if (fileExt == "m4a" || fileExt == "m4p" || fileExt == "mp4") {
        // qDebug() << "MetadataExtractor: Using MP4-specific handling for" << filePath;
        TagLib::MP4::File mp4File(filePathCStr);
        
        if (mp4File.isValid() && mp4File.tag()) {
            TagLib::MP4::Tag* mp4Tag = mp4File.tag();
            TagLib::MP4::ItemMap items = mp4Tag->itemMap();
            
            // Use a helper function to safely extract string values
            auto getStringValue = [&](const char* key) -> QString {
                if (key && items.contains(key)) {
                    try {
                        const TagLib::MP4::Item& item = items[key];
                        if (item.isValid()) {
                            TagLib::StringList values = item.toStringList();
                            if (!values.isEmpty() && values.size() > 0) {
                                return QString::fromStdString(values.front().to8Bit(true));
                            }
                        }
                    } catch (const std::exception& e) {
                        qDebug() << "MetadataExtractor: Exception extracting string value for key:" << key << "-" << e.what();
                    } catch (...) {
                        qDebug() << "MetadataExtractor: Failed to extract string value for key:" << key;
                    }
                }
                return QString();
            };
            
            // Also check the standard PropertyMap
            TagLib::PropertyMap properties = mp4Tag->properties();
            
            // TITLE - try iTunes tag first, then standard tag
            meta.title = getStringValue("©nam");
            if (meta.title.isEmpty()) {
                try {
                    TagLib::StringList titleList = properties.value("TITLE");
                    if (!titleList.isEmpty() && titleList.size() > 0) {
                        meta.title = QString::fromStdString(titleList.front().to8Bit(true));
                        // qDebug() << "MetadataExtractor: Using standard TITLE tag:" << meta.title;
                    }
                } catch (const std::exception& e) {
                    qDebug() << "MetadataExtractor: Exception accessing TITLE property:" << e.what();
                } catch (...) {
                    qDebug() << "MetadataExtractor: Failed to access TITLE property";
                }
            }
            
            // ARTIST - try iTunes tag first, then standard tag
            meta.artist = getStringValue("©ART");
            if (meta.artist.isEmpty()) {
                try {
                    TagLib::StringList artistList = properties.value("ARTIST");
                    if (!artistList.isEmpty() && artistList.size() > 0) {
                        meta.artist = QString::fromStdString(artistList.front().to8Bit(true));
                        // qDebug() << "MetadataExtractor: Using standard ARTIST tag:" << meta.artist;
                    }
                } catch (const std::exception& e) {
                    qDebug() << "MetadataExtractor: Exception accessing ARTIST property:" << e.what();
                } catch (...) {
                    qDebug() << "MetadataExtractor: Failed to access ARTIST property";
                }
            }
            
            // ALBUM - try iTunes tag first, then standard tag
            meta.album = getStringValue("©alb");
            if (meta.album.isEmpty()) {
                try {
                    TagLib::StringList albumList = properties.value("ALBUM");
                    if (!albumList.isEmpty() && albumList.size() > 0) {
                        meta.album = QString::fromStdString(albumList.front().to8Bit(true));
                        // qDebug() << "MetadataExtractor: Using standard ALBUM tag:" << meta.album;
                    }
                } catch (const std::exception& e) {
                    qDebug() << "MetadataExtractor: Exception accessing ALBUM property:" << e.what();
                } catch (...) {
                    qDebug() << "MetadataExtractor: Failed to access ALBUM property";
                }
            }
            
            // GENRE - try iTunes tag first, then standard tag
            meta.genre = getStringValue("©gen");
            if (meta.genre.isEmpty()) {
                try {
                    TagLib::StringList genreList = properties.value("GENRE");
                    if (!genreList.isEmpty() && genreList.size() > 0) {
                        meta.genre = QString::fromStdString(genreList.front().to8Bit(true));
                        // qDebug() << "MetadataExtractor: Using standard GENRE tag:" << meta.genre;
                    }
                } catch (const std::exception& e) {
                    qDebug() << "MetadataExtractor: Exception accessing GENRE property:" << e.what();
                } catch (...) {
                    qDebug() << "MetadataExtractor: Failed to access GENRE property";
                }
            }
            
            // YEAR - try iTunes tag first, then standard tag
            QString yearStr = getStringValue("©day");
            if (yearStr.isEmpty()) {
                try {
                    TagLib::StringList dateList = properties.value("DATE");
                    if (!dateList.isEmpty() && dateList.size() > 0) {
                        yearStr = QString::fromStdString(dateList.front().to8Bit(true));
                        // qDebug() << "MetadataExtractor: Using standard DATE tag for year:" << yearStr;
                    }
                } catch (const std::exception& e) {
                    qDebug() << "MetadataExtractor: Exception accessing DATE property:" << e.what();
                } catch (...) {
                    qDebug() << "MetadataExtractor: Failed to access DATE property";
                }
            }
            if (!yearStr.isEmpty()) {
                // Often the year is in format YYYY or YYYY-MM-DD
                bool ok;
                meta.year = yearStr.left(4).toUInt(&ok);
                if (!ok) {
                    meta.year = 0;
                }
            }
            
            // Track number
            if (items.contains("trkn")) {
                const TagLib::MP4::Item& trackItem = items["trkn"];
                if (trackItem.isValid()) {
                    TagLib::MP4::Item::IntPair trackPair = trackItem.toIntPair();
                    meta.trackNumber = trackPair.first;
                }
            }
            
            // Disc number
            if (items.contains("disk")) {
                const TagLib::MP4::Item& discItem = items["disk"];
                if (discItem.isValid()) {
                    TagLib::MP4::Item::IntPair discPair = discItem.toIntPair();
                    meta.discNumber = discPair.first;
                }
            }
            
            // Album Artist - simplified to avoid crashes
            meta.albumArtist = getStringValue("aART");
            if (meta.albumArtist.isEmpty()) {
                // Fallback to artist if no album artist
                meta.albumArtist = meta.artist;
            }
            
            // Audio properties from the MP4 file
            if (mp4File.audioProperties()) {
                meta.duration = mp4File.audioProperties()->lengthInSeconds();
            }
            
            // Extract album art
            if (extractAlbumArt && items.contains("covr")) {
                const TagLib::MP4::Item& coverItem = items["covr"];
                if (coverItem.isValid()) {
                    TagLib::MP4::CoverArtList coverArtList = coverItem.toCoverArtList();
                    if (!coverArtList.isEmpty()) {
                        // Get the first cover art
                        const TagLib::MP4::CoverArt& coverArt = coverArtList.front();
                        TagLib::ByteVector coverData = coverArt.data();
                        
                        if (!coverData.isEmpty()) {
                            meta.albumArtData = QByteArray(coverData.data(), coverData.size());
                            
                            // Determine MIME type based on format
                            switch (coverArt.format()) {
                                case TagLib::MP4::CoverArt::JPEG:
                                    meta.albumArtMimeType = "image/jpeg";
                                    break;
                                case TagLib::MP4::CoverArt::PNG:
                                    meta.albumArtMimeType = "image/png";
                                    break;
                                default:
                                    meta.albumArtMimeType = "image/unknown";
                                    break;
                            }
                        }
                    }
                }
            }
            
            // Return here since we've handled everything MP4-specific
            // qDebug() << "MetadataExtractor: Final MP4 meta.albumArtist:" << meta.albumArtist;
            return meta;
        }
    }
    
    // Standard handling for non-MP4 files
    TagLib::FileRef f(filePathCStr);

    if (!f.isNull() && f.tag()) {
        // Log file type
        // qDebug() << "MetadataExtractor: File type:" << fileExt;
        
        // Get properties without debug logging to avoid crashes
        TagLib::PropertyMap properties = f.tag()->properties();
        // qDebug() << "MetadataExtractor: FileRef is valid and has tags";
        TagLib::Tag *tag = f.tag();

        meta.title = QString::fromStdString(tag->title().to8Bit(true));
        meta.artist = QString::fromStdString(tag->artist().to8Bit(true));
        meta.album = QString::fromStdString(tag->album().to8Bit(true));
        meta.genre = QString::fromStdString(tag->genre().to8Bit(true));
        meta.year = tag->year();
        meta.trackNumber = tag->track();
        // Check for disc number in standard properties
        try {
            TagLib::StringList discList = properties.value("DISCNUMBER");
            if (!discList.isEmpty() && discList.size() > 0) {
                QString discStr = QString::fromStdString(discList.front().to8Bit(true));
                bool ok;
                meta.discNumber = discStr.split('/').first().toInt(&ok);
                if (!ok) meta.discNumber = 0;
            }
        } catch (const std::exception& e) {
            qDebug() << "MetadataExtractor: Exception accessing DISCNUMBER property:" << e.what();
        } catch (...) {
            qDebug() << "MetadataExtractor: Failed to access DISCNUMBER property";
        }

        // Album Artist (often in TPE2 frame for ID3, or ALBUMARTIST for Vorbis/FLAC)
        // properties is already declared above
        try {
            // Try different album artist tag variants
            TagLib::StringList albumArtistList = properties.value("ALBUMARTIST");
            if (!albumArtistList.isEmpty() && albumArtistList.size() > 0) {
                meta.albumArtist = QString::fromStdString(albumArtistList.front().to8Bit(true));
            } else {
                // Try with space
                albumArtistList = properties.value("ALBUM ARTIST");
                if (!albumArtistList.isEmpty() && albumArtistList.size() > 0) {
                    meta.albumArtist = QString::fromStdString(albumArtistList.front().to8Bit(true));
                } else {
                    // Try ID3v2 TPE2 frame
                    albumArtistList = properties.value("TPE2");
                    if (!albumArtistList.isEmpty() && albumArtistList.size() > 0) {
                        meta.albumArtist = QString::fromStdString(albumArtistList.front().to8Bit(true));
                    } else {
                        // Try iTunes/M4A specific tag
                        albumArtistList = properties.value("aART");
                        if (!albumArtistList.isEmpty() && albumArtistList.size() > 0) {
                            meta.albumArtist = QString::fromStdString(albumArtistList.front().to8Bit(true));
                        }
                    }
                }
            }
        } catch (const std::exception& e) {
            qDebug() << "MetadataExtractor: Exception accessing album artist properties:" << e.what();
        } catch (...) {
            qDebug() << "MetadataExtractor: Failed to access album artist properties";
        }
        
        // qDebug() << "MetadataExtractor: Final meta.albumArtist before return:" << meta.albumArtist;

        if (f.audioProperties()) {
            meta.duration = f.audioProperties()->lengthInSeconds();
        }
    } else {
        qWarning() << "Could not read metadata for:" << filePath;
    }
    } catch (const std::exception& e) {
        qCritical() << "MetadataExtractor: Exception while extracting metadata from" << filePath << ":" << e.what();
    } catch (...) {
        qCritical() << "MetadataExtractor: Unknown exception while extracting metadata from" << filePath;
    }
    
    return meta;
}

QVariantMap MetadataExtractor::extractAsVariantMap(const QString &filePath)
{
    return extractAsVariantMap(filePath, true);
}

QVariantMap MetadataExtractor::extractAsVariantMap(const QString &filePath, bool extractAlbumArt)
{
    TrackMetadata details = extract(filePath, extractAlbumArt);
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
    map.insert("hasAlbumArt", !details.albumArtData.isEmpty());
    map.insert("albumArtData", details.albumArtData);
    map.insert("albumArtMimeType", details.albumArtMimeType);
    return map;
}

QByteArray MetadataExtractor::extractAlbumArt(const QString &filePath)
{
    TrackMetadata details = extract(filePath);
    return details.albumArtData;
}

bool MetadataExtractor::hasAlbumArt(const QString &filePath)
{
    TrackMetadata details = extract(filePath);
    return !details.albumArtData.isEmpty();
}

} // namespace Mtoc
