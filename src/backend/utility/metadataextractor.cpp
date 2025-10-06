#include "metadataextractor.h"
#include <QDebug>
#include <QFileInfo>
#include <QFile>
#include <QDir>
#include <QTextStream>
#include <QRegularExpression>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
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
#include <taglib/vorbisfile.h>
#include <taglib/xiphcomment.h>
#include <taglib/opusfile.h>
#include <taglib/textidentificationframe.h>

#include <taglib/id3v2frame.h>

namespace Mtoc {

// Helper function to parse replay gain value from string (format: "+#.## dB" or "-#.## dB")
static double parseReplayGainValue(const QString& str) {
    QString trimmed = str.trimmed();
    
    // Remove "dB" suffix if present
    if (trimmed.endsWith(" dB", Qt::CaseInsensitive)) {
        trimmed = trimmed.left(trimmed.length() - 3).trimmed();
    }
    
    // Convert to double
    bool ok;
    double value = trimmed.toDouble(&ok);
    return ok ? value : 0.0;
}

MetadataExtractor::MetadataExtractor(QObject *parent)
    : QObject{parent}
{
}

std::pair<QString, QMap<qint64, QString>> MetadataExtractor::parseLrcFile(const QString &lrcFilePath)
{
    QString plainLyrics;
    QMap<qint64, QString> synchronizedLyrics;

    QFile lrcFile(lrcFilePath);
    if (!lrcFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        qWarning() << "MetadataExtractor: Could not open LRC file:" << lrcFilePath;
        return {};
    }

    QTextStream in(&lrcFile);
    // The regex to capture timestamps like [mm:ss.xx] or [mm:ss.xxx]
    QRegularExpression re("\\[(\\d{2}):(\\d{2})(?:\\.(\\d{2,3}))?\\]");

    while (!in.atEnd()) {
        QString line = in.readLine();
        QString text = line;
        QRegularExpressionMatchIterator i = re.globalMatch(line);
        
        QList<qint64> timestamps;
        int lastIndex = -1;

        while (i.hasNext()) {
            QRegularExpressionMatch match = i.next();
            lastIndex = match.capturedEnd();
            
            qint64 minutes = match.captured(1).toLongLong();
            qint64 seconds = match.captured(2).toLongLong();
            qint64 milliseconds = 0;
            if (match.hasMatch()) {
                QString msStr = match.captured(3);
                if (msStr.length() == 3) { // milliseconds
                    milliseconds = msStr.toLongLong();
                } else { // centiseconds
                    milliseconds = msStr.toLongLong() * 10;
                }
            }
            
            timestamps.append(minutes * 60000 + seconds * 1000 + milliseconds);
        }

        if (!timestamps.isEmpty() && lastIndex != -1) {
            text = line.mid(lastIndex).trimmed();
            if (!text.isEmpty()) {
                for (const qint64 &ts : timestamps) {
                    synchronizedLyrics.insert(ts, text);
                }
            }
        }
        
        // Only append the text part to plainLyrics if it's not empty
        if(!text.isEmpty()) {
            plainLyrics.append(text + "\n");
        }
    }

    if (synchronizedLyrics.isEmpty() && !plainLyrics.isEmpty()) {
        // If no timestamps were found, but we have text, return the concatenated text.
        synchronizedLyrics.clear();
    } else {
        // If we have sync'd lyrics, we don't need the concatenated plain text.
        plainLyrics.clear();
    }

    return {plainLyrics, synchronizedLyrics};
}

QMap<qint64, QString> MetadataExtractor::parseSyltFrame(const TagLib::ID3v2::SynchronizedLyricsFrame *syltFrame)
{
    QMap<qint64, QString> synchronizedLyrics;

    TagLib::ID3v2::SynchronizedLyricsFrame::SynchedTextList syltData = syltFrame->synchedText();

    for (const auto &line : syltData) {
        synchronizedLyrics.insert(line.time, QString::fromStdString(line.text.to8Bit(true)));
    }

    return synchronizedLyrics;
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
    bool lyricsFoundInLrc = false;
    bool syncLyricsFound = false;

    // LRC File Handling
    // Try to find a matching LRC file - supports both exact matches and fuzzy matching
    QString lrcFilePath = findMatchingLrcFile(filePath);
    if (!lrcFilePath.isEmpty()) {
        qDebug() << "MetadataExtractor: Found LRC file:" << lrcFilePath;
        auto lyricsData = parseLrcFile(lrcFilePath);
        
        // Check for synchronized lyrics first
        if (!lyricsData.second.isEmpty()) {
            QJsonArray syncLyricsArray;
            for (auto it = lyricsData.second.constBegin(); it != lyricsData.second.constEnd(); ++it) {
                QJsonObject lyricLine;
                lyricLine["time"] = it.key();
                lyricLine["text"] = it.value();
                syncLyricsArray.append(lyricLine);
            }
            meta.lyrics = QJsonDocument(syncLyricsArray).toJson(QJsonDocument::Compact);
            lyricsFoundInLrc = true;
            syncLyricsFound = true;
            qDebug() << "MetadataExtractor: Successfully parsed synchronized lyrics from LRC file.";
        } 
        // Fallback to plain text from LRC if no sync data found
        else if (!lyricsData.first.isEmpty()) {
            meta.lyrics = lyricsData.first;
            lyricsFoundInLrc = true;
            qDebug() << "MetadataExtractor: Successfully parsed plain lyrics from LRC file.";
        }
    }
    
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
                
                // Extract ReplayGain tags from TXXX frames
                TagLib::ID3v2::FrameList txxxFrames = id3v2Tag->frameList("TXXX");
                for (auto it = txxxFrames.begin(); it != txxxFrames.end(); ++it) {
                    auto* txtFrame = dynamic_cast<TagLib::ID3v2::UserTextIdentificationFrame*>(*it);
                    if (txtFrame) {
                        TagLib::String description = txtFrame->description();
                        TagLib::StringList values = txtFrame->fieldList();
                        
                        if (values.size() > 1) {
                            QString desc = QString::fromStdString(description.to8Bit(true)).toUpper();
                            QString value = QString::fromStdString(values[1].to8Bit(true));
                            
                            if (desc == "REPLAYGAIN_TRACK_GAIN") {
                                meta.replayGainTrackGain = parseReplayGainValue(value);
                                meta.hasReplayGainTrackGain = true;
                                //qDebug() << "[ReplayGain] Found TRACK_GAIN:" << value << "=" << meta.replayGainTrackGain << "dB";
                            } else if (desc == "REPLAYGAIN_TRACK_PEAK") {
                                meta.replayGainTrackPeak = value.toDouble();
                                meta.hasReplayGainTrackPeak = true;
                                //qDebug() << "[ReplayGain] Found TRACK_PEAK:" << value << "=" << meta.replayGainTrackPeak;
                            } else if (desc == "REPLAYGAIN_ALBUM_GAIN") {
                                meta.replayGainAlbumGain = parseReplayGainValue(value);
                                meta.hasReplayGainAlbumGain = true;
                                //qDebug() << "[ReplayGain] Found ALBUM_GAIN:" << value << "=" << meta.replayGainAlbumGain << "dB";
                            } else if (desc == "REPLAYGAIN_ALBUM_PEAK") {
                                meta.replayGainAlbumPeak = value.toDouble();
                                meta.hasReplayGainAlbumPeak = true;
                                //qDebug() << "[ReplayGain] Found ALBUM_PEAK:" << value << "=" << meta.replayGainAlbumPeak;
                            }
                        }
                    }
                }

                if (!syncLyricsFound) {
                    // Extract synchronized lyrics from SYLT frame
                    TagLib::ID3v2::FrameList syltFrames = id3v2Tag->frameList("SYLT");
                    if (!syltFrames.isEmpty()) {
                        qDebug() << "MetadataExtractor: Found SYLT frame(s).";
                        if (auto syltFrame = dynamic_cast<TagLib::ID3v2::SynchronizedLyricsFrame*>(syltFrames.front())) {
                            auto lyricsData = parseSyltFrame(syltFrame);
                            if (!lyricsData.isEmpty()) {
                                QJsonArray syncLyricsArray;
                                for (auto it = lyricsData.constBegin(); it != lyricsData.constEnd(); ++it) {
                                    QJsonObject lyricLine;
                                    lyricLine["time"] = it.key();
                                    lyricLine["text"] = it.value();
                                    syncLyricsArray.append(lyricLine);
                                }
                                meta.lyrics = QJsonDocument(syncLyricsArray).toJson(QJsonDocument::Compact);
                                syncLyricsFound = true;
                                qDebug() << "MetadataExtractor: Successfully parsed synchronized lyrics from SYLT frame.";
                            }
                        }
                    }
                }

                if (!lyricsFoundInLrc && !syncLyricsFound) {
                    // Extract lyrics from USLT frame
                    TagLib::ID3v2::FrameList usltFrames = id3v2Tag->frameList("USLT");
                    if (!usltFrames.isEmpty() && usltFrames.front()) {
                        // Use toString() for robustness, similar to other frame handling.
                        meta.lyrics = QString::fromStdString(usltFrames.front()->toString().to8Bit(true));
                        // qDebug() << "MetadataExtractor: Found lyrics (USLT)";
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
                // Create a UTF-8 TagLib::String from the c-style string key for comparison.
                TagLib::String searchKey(key, TagLib::String::UTF8);
                if (key && items.contains(searchKey)) {
                    try {
                        const TagLib::MP4::Item& item = items[searchKey];
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

            if (!lyricsFoundInLrc) {
                // Lyrics
                meta.lyrics = getStringValue("©lyr");
                if (meta.lyrics.isEmpty()) {
                    try {
                        TagLib::StringList lyricsList = properties.value("LYRICS");
                        if (!lyricsList.isEmpty() && lyricsList.size() > 0) {
                            meta.lyrics = QString::fromStdString(lyricsList.front().to8Bit(true));
                        }
                    } catch (const std::exception& e) {
                        qDebug() << "MetadataExtractor: Exception accessing LYRICS property:" << e.what();
                    } catch (...) {
                        qDebug() << "MetadataExtractor: Failed to access LYRICS property";
                    }
                }
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
    
    // Special case for Opus files
    if (fileExt == "opus") {
        qDebug() << "MetadataExtractor: Using Opus-specific handling for" << filePath;
        TagLib::Ogg::Opus::File opusFile(filePathCStr);
        
        if (opusFile.isValid()) {
            qDebug() << "MetadataExtractor: Opus file is valid";
            // Get basic metadata from the tag
            if (opusFile.tag()) {
                TagLib::Tag* tag = opusFile.tag();
                meta.title = QString::fromStdString(tag->title().to8Bit(true));
                meta.artist = QString::fromStdString(tag->artist().to8Bit(true));
                meta.album = QString::fromStdString(tag->album().to8Bit(true));
                meta.genre = QString::fromStdString(tag->genre().to8Bit(true));
                meta.year = tag->year();
                meta.trackNumber = tag->track();
            }
            
            // Get additional metadata from Xiph comment
            TagLib::Ogg::XiphComment* xiphComment = opusFile.tag();
            if (xiphComment) {
                // Get properties for album artist and disc number
                TagLib::PropertyMap properties = xiphComment->properties();
                
                // Album Artist
                try {
                    TagLib::StringList albumArtistList = properties.value("ALBUMARTIST");
                    if (!albumArtistList.isEmpty() && albumArtistList.size() > 0) {
                        meta.albumArtist = QString::fromStdString(albumArtistList.front().to8Bit(true));
                    }
                } catch (const std::exception& e) {
                    qDebug() << "MetadataExtractor: Exception accessing ALBUMARTIST property:" << e.what();
                } catch (...) {
                    qDebug() << "MetadataExtractor: Failed to access ALBUMARTIST property";
                }
                
                // Disc Number
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
                
                // Extract ReplayGain tags from Xiph comments
                try {
                    // Track gain
                    TagLib::StringList trackGainList = properties.value("REPLAYGAIN_TRACK_GAIN");
                    if (!trackGainList.isEmpty() && trackGainList.size() > 0) {
                        QString value = QString::fromStdString(trackGainList.front().to8Bit(true));
                        meta.replayGainTrackGain = parseReplayGainValue(value);
                        meta.hasReplayGainTrackGain = true;
                        qDebug() << "[ReplayGain] Found TRACK_GAIN (Xiph):" << value << "=" << meta.replayGainTrackGain << "dB";
                    }
                    
                    // Track peak
                    TagLib::StringList trackPeakList = properties.value("REPLAYGAIN_TRACK_PEAK");
                    if (!trackPeakList.isEmpty() && trackPeakList.size() > 0) {
                        QString value = QString::fromStdString(trackPeakList.front().to8Bit(true));
                        meta.replayGainTrackPeak = value.toDouble();
                        meta.hasReplayGainTrackPeak = true;
                        qDebug() << "[ReplayGain] Found TRACK_PEAK (Xiph):" << value << "=" << meta.replayGainTrackPeak;
                    }
                    
                    // Album gain
                    TagLib::StringList albumGainList = properties.value("REPLAYGAIN_ALBUM_GAIN");
                    if (!albumGainList.isEmpty() && albumGainList.size() > 0) {
                        QString value = QString::fromStdString(albumGainList.front().to8Bit(true));
                        meta.replayGainAlbumGain = parseReplayGainValue(value);
                        meta.hasReplayGainAlbumGain = true;
                        qDebug() << "[ReplayGain] Found ALBUM_GAIN (Xiph):" << value << "=" << meta.replayGainAlbumGain << "dB";
                    }
                    
                    // Album peak
                    TagLib::StringList albumPeakList = properties.value("REPLAYGAIN_ALBUM_PEAK");
                    if (!albumPeakList.isEmpty() && albumPeakList.size() > 0) {
                        QString value = QString::fromStdString(albumPeakList.front().to8Bit(true));
                        meta.replayGainAlbumPeak = value.toDouble();
                        meta.hasReplayGainAlbumPeak = true;
                        qDebug() << "[ReplayGain] Found ALBUM_PEAK (Xiph):" << value << "=" << meta.replayGainAlbumPeak;
                    }
                } catch (const std::exception& e) {
                    qDebug() << "MetadataExtractor: Exception accessing replay gain properties:" << e.what();
                } catch (...) {
                    qDebug() << "MetadataExtractor: Failed to access replay gain properties";
                }

                if (!lyricsFoundInLrc) {
                    // Lyrics
                    try {
                        TagLib::StringList lyricsList = properties.value("LYRICS");
                        if (!lyricsList.isEmpty() && lyricsList.size() > 0) {
                            meta.lyrics = QString::fromStdString(lyricsList.front().to8Bit(true));
                        }
                    } catch (const std::exception& e) {
                        qDebug() << "MetadataExtractor: Exception accessing LYRICS property:" << e.what();
                    } catch (...) {
                        qDebug() << "MetadataExtractor: Failed to access LYRICS property";
                    }
                }
                
                // Extract album art from Xiph comment
                if (extractAlbumArt) {
                    qDebug() << "MetadataExtractor: Attempting to extract album art from OGG file";
                    TagLib::List<TagLib::FLAC::Picture*> pictureList = xiphComment->pictureList();
                    qDebug() << "MetadataExtractor: OGG picture list size:" << pictureList.size();
                    if (!pictureList.isEmpty()) {
                        // Get the first picture
                        TagLib::FLAC::Picture* picture = pictureList.front();
                        if (picture) {
                            TagLib::ByteVector pictureData = picture->data();
                            qDebug() << "MetadataExtractor: OGG picture data size:" << pictureData.size();
                            if (!pictureData.isEmpty()) {
                                meta.albumArtData = QByteArray(pictureData.data(), pictureData.size());
                                
                                // Get MIME type
                                TagLib::String mimeType = picture->mimeType();
                                meta.albumArtMimeType = QString::fromStdString(mimeType.to8Bit(true));
                                qDebug() << "MetadataExtractor: OGG album art extracted, MIME type:" << meta.albumArtMimeType;
                            }
                        }
                    } else {
                        qDebug() << "MetadataExtractor: No pictures found in Opus file pictureList, checking METADATA_BLOCK_PICTURE";
                        
                        // Fallback: Check for METADATA_BLOCK_PICTURE field
                        if (properties.contains("METADATA_BLOCK_PICTURE")) {
                            TagLib::StringList pictureFieldList = properties["METADATA_BLOCK_PICTURE"];
                            if (!pictureFieldList.isEmpty()) {
                                // Get the first METADATA_BLOCK_PICTURE
                                TagLib::String base64Data = pictureFieldList.front();
                                QByteArray encodedData = QByteArray::fromStdString(base64Data.to8Bit(false));
                                QByteArray decodedData = QByteArray::fromBase64(encodedData);
                                
                                if (!decodedData.isEmpty()) {
                                    // Parse the FLAC picture block structure
                                    // The structure contains: picture type (4 bytes), MIME type length (4 bytes), 
                                    // MIME type, description length (4 bytes), description, 
                                    // width (4 bytes), height (4 bytes), color depth (4 bytes), 
                                    // used colors (4 bytes), picture data length (4 bytes), picture data
                                    
                                    if (decodedData.size() > 32) { // Minimum size for header
                                        const char* data = decodedData.constData();
                                        int pos = 0;
                                        
                                        // Skip picture type (4 bytes)
                                        pos += 4;
                                        
                                        // Read MIME type length (4 bytes, big-endian)
                                        uint32_t mimeLength = (static_cast<uint8_t>(data[pos]) << 24) |
                                                              (static_cast<uint8_t>(data[pos+1]) << 16) |
                                                              (static_cast<uint8_t>(data[pos+2]) << 8) |
                                                              static_cast<uint8_t>(data[pos+3]);
                                        pos += 4;
                                        
                                        if (pos + mimeLength <= decodedData.size()) {
                                            // Read MIME type
                                            meta.albumArtMimeType = QString::fromUtf8(data + pos, mimeLength);
                                            pos += mimeLength;
                                            
                                            // Read description length (4 bytes, big-endian)
                                            uint32_t descLength = (static_cast<uint8_t>(data[pos]) << 24) |
                                                                  (static_cast<uint8_t>(data[pos+1]) << 16) |
                                                                  (static_cast<uint8_t>(data[pos+2]) << 8) |
                                                                  static_cast<uint8_t>(data[pos+3]);
                                            pos += 4;
                                            
                                            // Skip description
                                            pos += descLength;
                                            
                                            // Skip width, height, color depth, used colors (16 bytes)
                                            pos += 16;
                                            
                                            if (pos + 4 <= decodedData.size()) {
                                                // Read picture data length (4 bytes, big-endian)
                                                uint32_t pictureLength = (static_cast<uint8_t>(data[pos]) << 24) |
                                                                         (static_cast<uint8_t>(data[pos+1]) << 16) |
                                                                         (static_cast<uint8_t>(data[pos+2]) << 8) |
                                                                         static_cast<uint8_t>(data[pos+3]);
                                                pos += 4;
                                                
                                                if (pos + pictureLength <= decodedData.size()) {
                                                    // Extract picture data
                                                    meta.albumArtData = QByteArray(data + pos, pictureLength);
                                                    qDebug() << "MetadataExtractor: Opus album art extracted from METADATA_BLOCK_PICTURE,"
                                                             << "size:" << pictureLength << "MIME type:" << meta.albumArtMimeType;
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // Get audio properties
            if (opusFile.audioProperties()) {
                meta.duration = opusFile.audioProperties()->lengthInSeconds();
            }
            
            // If album artist is still empty, fallback to artist
            if (meta.albumArtist.isEmpty()) {
                meta.albumArtist = meta.artist;
            }
            
            qDebug() << "MetadataExtractor: Returning Opus metadata, has album art:" << !meta.albumArtData.isEmpty();
            return meta;
        } else {
            qDebug() << "MetadataExtractor: Opus file is NOT valid";
        }
    }
    
    // Special case for OGG Vorbis files
    if (fileExt == "ogg" || fileExt == "oga") {
        qDebug() << "MetadataExtractor: Using OGG Vorbis-specific handling for" << filePath;
        TagLib::Vorbis::File vorbisFile(filePathCStr);
        
        if (vorbisFile.isValid()) {
            qDebug() << "MetadataExtractor: OGG Vorbis file is valid";
            // Get basic metadata from the tag
            if (vorbisFile.tag()) {
                TagLib::Tag* tag = vorbisFile.tag();
                meta.title = QString::fromStdString(tag->title().to8Bit(true));
                meta.artist = QString::fromStdString(tag->artist().to8Bit(true));
                meta.album = QString::fromStdString(tag->album().to8Bit(true));
                meta.genre = QString::fromStdString(tag->genre().to8Bit(true));
                meta.year = tag->year();
                meta.trackNumber = tag->track();
            }
            
            // Get additional metadata from Xiph comment
            TagLib::Ogg::XiphComment* xiphComment = vorbisFile.tag();
            if (xiphComment) {
                // Get properties for album artist and disc number
                TagLib::PropertyMap properties = xiphComment->properties();
                
                // Album Artist
                try {
                    TagLib::StringList albumArtistList = properties.value("ALBUMARTIST");
                    if (!albumArtistList.isEmpty() && albumArtistList.size() > 0) {
                        meta.albumArtist = QString::fromStdString(albumArtistList.front().to8Bit(true));
                    }
                } catch (const std::exception& e) {
                    qDebug() << "MetadataExtractor: Exception accessing ALBUMARTIST property:" << e.what();
                } catch (...) {
                    qDebug() << "MetadataExtractor: Failed to access ALBUMARTIST property";
                }
                
                // Disc Number
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
                
                // Extract ReplayGain tags from Xiph comments
                try {
                    // Track gain
                    TagLib::StringList trackGainList = properties.value("REPLAYGAIN_TRACK_GAIN");
                    if (!trackGainList.isEmpty() && trackGainList.size() > 0) {
                        QString value = QString::fromStdString(trackGainList.front().to8Bit(true));
                        meta.replayGainTrackGain = parseReplayGainValue(value);
                        meta.hasReplayGainTrackGain = true;
                        qDebug() << "[ReplayGain] Found TRACK_GAIN (Xiph):" << value << "=" << meta.replayGainTrackGain << "dB";
                    }
                    
                    // Track peak
                    TagLib::StringList trackPeakList = properties.value("REPLAYGAIN_TRACK_PEAK");
                    if (!trackPeakList.isEmpty() && trackPeakList.size() > 0) {
                        QString value = QString::fromStdString(trackPeakList.front().to8Bit(true));
                        meta.replayGainTrackPeak = value.toDouble();
                        meta.hasReplayGainTrackPeak = true;
                        qDebug() << "[ReplayGain] Found TRACK_PEAK (Xiph):" << value << "=" << meta.replayGainTrackPeak;
                    }
                    
                    // Album gain
                    TagLib::StringList albumGainList = properties.value("REPLAYGAIN_ALBUM_GAIN");
                    if (!albumGainList.isEmpty() && albumGainList.size() > 0) {
                        QString value = QString::fromStdString(albumGainList.front().to8Bit(true));
                        meta.replayGainAlbumGain = parseReplayGainValue(value);
                        meta.hasReplayGainAlbumGain = true;
                        qDebug() << "[ReplayGain] Found ALBUM_GAIN (Xiph):" << value << "=" << meta.replayGainAlbumGain << "dB";
                    }
                    
                    // Album peak
                    TagLib::StringList albumPeakList = properties.value("REPLAYGAIN_ALBUM_PEAK");
                    if (!albumPeakList.isEmpty() && albumPeakList.size() > 0) {
                        QString value = QString::fromStdString(albumPeakList.front().to8Bit(true));
                        meta.replayGainAlbumPeak = value.toDouble();
                        meta.hasReplayGainAlbumPeak = true;
                        qDebug() << "[ReplayGain] Found ALBUM_PEAK (Xiph):" << value << "=" << meta.replayGainAlbumPeak;
                    }
                } catch (const std::exception& e) {
                    qDebug() << "MetadataExtractor: Exception accessing replay gain properties:" << e.what();
                } catch (...) {
                    qDebug() << "MetadataExtractor: Failed to access replay gain properties";
                }

                if (!lyricsFoundInLrc) {
                    // Lyrics
                    try {
                        TagLib::StringList lyricsList = properties.value("LYRICS");
                        if (!lyricsList.isEmpty() && lyricsList.size() > 0) {
                            meta.lyrics = QString::fromStdString(lyricsList.front().to8Bit(true));
                        }
                    } catch (const std::exception& e) {
                        qDebug() << "MetadataExtractor: Exception accessing LYRICS property:" << e.what();
                    } catch (...) {
                        qDebug() << "MetadataExtractor: Failed to access LYRICS property";
                    }
                }
                
                // Extract album art from Xiph comment
                if (extractAlbumArt) {
                    qDebug() << "MetadataExtractor: Attempting to extract album art from OGG Vorbis file";
                    TagLib::List<TagLib::FLAC::Picture*> pictureList = xiphComment->pictureList();
                    qDebug() << "MetadataExtractor: OGG Vorbis picture list size:" << pictureList.size();
                    if (!pictureList.isEmpty()) {
                        // Get the first picture
                        TagLib::FLAC::Picture* picture = pictureList.front();
                        if (picture) {
                            TagLib::ByteVector pictureData = picture->data();
                            qDebug() << "MetadataExtractor: OGG Vorbis picture data size:" << pictureData.size();
                            if (!pictureData.isEmpty()) {
                                meta.albumArtData = QByteArray(pictureData.data(), pictureData.size());
                                
                                // Get MIME type
                                TagLib::String mimeType = picture->mimeType();
                                meta.albumArtMimeType = QString::fromStdString(mimeType.to8Bit(true));
                                qDebug() << "MetadataExtractor: OGG Vorbis album art extracted, MIME type:" << meta.albumArtMimeType;
                            }
                        }
                    } else {
                        qDebug() << "MetadataExtractor: No pictures found in OGG Vorbis file pictureList, checking METADATA_BLOCK_PICTURE";
                        
                        // Fallback: Check for METADATA_BLOCK_PICTURE field
                        if (properties.contains("METADATA_BLOCK_PICTURE")) {
                            TagLib::StringList pictureFieldList = properties["METADATA_BLOCK_PICTURE"];
                            if (!pictureFieldList.isEmpty()) {
                                // Get the first METADATA_BLOCK_PICTURE
                                TagLib::String base64Data = pictureFieldList.front();
                                QByteArray encodedData = QByteArray::fromStdString(base64Data.to8Bit(false));
                                QByteArray decodedData = QByteArray::fromBase64(encodedData);
                                
                                if (!decodedData.isEmpty()) {
                                    // Parse the FLAC picture block structure
                                    // The structure contains: picture type (4 bytes), MIME type length (4 bytes), 
                                    // MIME type, description length (4 bytes), description, 
                                    // width (4 bytes), height (4 bytes), color depth (4 bytes), 
                                    // used colors (4 bytes), picture data length (4 bytes), picture data
                                    
                                    if (decodedData.size() > 32) { // Minimum size for header
                                        const char* data = decodedData.constData();
                                        int pos = 0;
                                        
                                        // Skip picture type (4 bytes)
                                        pos += 4;
                                        
                                        // Read MIME type length (4 bytes, big-endian)
                                        uint32_t mimeLength = (static_cast<uint8_t>(data[pos]) << 24) |
                                                              (static_cast<uint8_t>(data[pos+1]) << 16) |
                                                              (static_cast<uint8_t>(data[pos+2]) << 8) |
                                                              static_cast<uint8_t>(data[pos+3]);
                                        pos += 4;
                                        
                                        if (pos + mimeLength <= decodedData.size()) {
                                            // Read MIME type
                                            meta.albumArtMimeType = QString::fromUtf8(data + pos, mimeLength);
                                            pos += mimeLength;
                                            
                                            // Read description length (4 bytes, big-endian)
                                            uint32_t descLength = (static_cast<uint8_t>(data[pos]) << 24) |
                                                                  (static_cast<uint8_t>(data[pos+1]) << 16) |
                                                                  (static_cast<uint8_t>(data[pos+2]) << 8) |
                                                                  static_cast<uint8_t>(data[pos+3]);
                                            pos += 4;
                                            
                                            // Skip description
                                            pos += descLength;
                                            
                                            // Skip width, height, color depth, used colors (16 bytes)
                                            pos += 16;
                                            
                                            if (pos + 4 <= decodedData.size()) {
                                                // Read picture data length (4 bytes, big-endian)
                                                uint32_t pictureLength = (static_cast<uint8_t>(data[pos]) << 24) |
                                                                         (static_cast<uint8_t>(data[pos+1]) << 16) |
                                                                         (static_cast<uint8_t>(data[pos+2]) << 8) |
                                                                         static_cast<uint8_t>(data[pos+3]);
                                                pos += 4;
                                                
                                                if (pos + pictureLength <= decodedData.size()) {
                                                    // Extract picture data
                                                    meta.albumArtData = QByteArray(data + pos, pictureLength);
                                                    qDebug() << "MetadataExtractor: OGG Vorbis album art extracted from METADATA_BLOCK_PICTURE,"
                                                             << "size:" << pictureLength << "MIME type:" << meta.albumArtMimeType;
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // Get audio properties
            if (vorbisFile.audioProperties()) {
                meta.duration = vorbisFile.audioProperties()->lengthInSeconds();
            }
            
            // If album artist is still empty, fallback to artist
            if (meta.albumArtist.isEmpty()) {
                meta.albumArtist = meta.artist;
            }
            
            qDebug() << "MetadataExtractor: Returning OGG Vorbis metadata, has album art:" << !meta.albumArtData.isEmpty();
            return meta;
        } else {
            qDebug() << "MetadataExtractor: OGG Vorbis file is NOT valid";
        }
    }
    
    // Special case for FLAC files
    if (fileExt == "flac") {
        // qDebug() << "MetadataExtractor: Using FLAC-specific handling for" << filePath;
        TagLib::FLAC::File flacFile(filePathCStr);
        
        if (flacFile.isValid()) {
            // Get basic metadata from the tag
            if (flacFile.tag()) {
                TagLib::Tag* tag = flacFile.tag();
                meta.title = QString::fromStdString(tag->title().to8Bit(true));
                meta.artist = QString::fromStdString(tag->artist().to8Bit(true));
                meta.album = QString::fromStdString(tag->album().to8Bit(true));
                meta.genre = QString::fromStdString(tag->genre().to8Bit(true));
                meta.year = tag->year();
                meta.trackNumber = tag->track();
            }
            
            // Get additional metadata from Xiph comment
            TagLib::Ogg::XiphComment* xiphComment = flacFile.xiphComment();
            if (xiphComment) {
                // Get properties for album artist and disc number
                TagLib::PropertyMap properties = xiphComment->properties();
                
                // Album Artist
                try {
                    TagLib::StringList albumArtistList = properties.value("ALBUMARTIST");
                    if (!albumArtistList.isEmpty() && albumArtistList.size() > 0) {
                        meta.albumArtist = QString::fromStdString(albumArtistList.front().to8Bit(true));
                    }
                } catch (const std::exception& e) {
                    qDebug() << "MetadataExtractor: Exception accessing ALBUMARTIST property:" << e.what();
                } catch (...) {
                    qDebug() << "MetadataExtractor: Failed to access ALBUMARTIST property";
                }
                
                // Disc Number
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

                if (!lyricsFoundInLrc) {
                    // Lyrics
                    try {
                        TagLib::StringList lyricsList = properties.value("LYRICS");
                        if (!lyricsList.isEmpty() && lyricsList.size() > 0) {
                            meta.lyrics = QString::fromStdString(lyricsList.front().to8Bit(true));
                        }
                    } catch (const std::exception& e) {
                        qDebug() << "MetadataExtractor: Exception accessing LYRICS property:" << e.what();
                    } catch (...) {
                        qDebug() << "MetadataExtractor: Failed to access LYRICS property";
                    }
                }
                
                // Extract album art from picture blocks
                if (extractAlbumArt) {
                    TagLib::List<TagLib::FLAC::Picture*> pictureList = flacFile.pictureList();
                    if (!pictureList.isEmpty()) {
                        // Get the first picture
                        TagLib::FLAC::Picture* picture = pictureList.front();
                        if (picture) {
                            TagLib::ByteVector pictureData = picture->data();
                            if (!pictureData.isEmpty()) {
                                meta.albumArtData = QByteArray(pictureData.data(), pictureData.size());
                                
                                // Get MIME type
                                TagLib::String mimeType = picture->mimeType();
                                meta.albumArtMimeType = QString::fromStdString(mimeType.to8Bit(true));
                            }
                        }
                    }
                }
            }
            
            // Get audio properties
            if (flacFile.audioProperties()) {
                meta.duration = flacFile.audioProperties()->lengthInSeconds();
            }
            
            // If album artist is still empty, fallback to artist
            if (meta.albumArtist.isEmpty()) {
                meta.albumArtist = meta.artist;
            }
            
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

        if (!lyricsFoundInLrc) {
            // Lyrics
            if (meta.lyrics.isEmpty()) {
                try {
                    TagLib::StringList lyricsList = properties.value("LYRICS");
                    if (!lyricsList.isEmpty() && lyricsList.size() > 0) {
                        meta.lyrics = QString::fromStdString(lyricsList.front().to8Bit(true));
                    }
                } catch (const std::exception& e) {
                    qDebug() << "MetadataExtractor: Exception accessing LYRICS property:" << e.what();
                } catch (...) {
                    qDebug() << "MetadataExtractor: Failed to access LYRICS property";
                }
            }
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
    map.insert("lyrics", details.lyrics);

    // Include replay gain data if present
    if (details.hasReplayGainTrackGain) {
        map.insert("replayGainTrackGain", details.replayGainTrackGain);
    }
    if (details.hasReplayGainTrackPeak) {
        map.insert("replayGainTrackPeak", details.replayGainTrackPeak);
    }
    if (details.hasReplayGainAlbumGain) {
        map.insert("replayGainAlbumGain", details.replayGainAlbumGain);
    }
    if (details.hasReplayGainAlbumPeak) {
        map.insert("replayGainAlbumPeak", details.replayGainAlbumPeak);
    }
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

QString MetadataExtractor::findLongestCommonSubstring(const QString &s1, const QString &s2, int minLength) const
{
    if (s1.isEmpty() || s2.isEmpty() || minLength < 1) {
        return QString();
    }

    QString longestMatch;
    int maxLength = 0;

    // Convert to lowercase for case-insensitive matching
    QString s1Lower = s1.toLower();
    QString s2Lower = s2.toLower();

    // Try all possible substrings of s1, starting with longest
    for (int len = s1.length(); len >= minLength && len > maxLength; --len) {
        for (int i = 0; i <= s1.length() - len; ++i) {
            QString substring = s1Lower.mid(i, len);

            // Check if this substring exists in s2
            if (s2Lower.contains(substring)) {
                if (len > maxLength) {
                    maxLength = len;
                    longestMatch = s1.mid(i, len);  // Return original case
                    break;  // Found longest at this length, move to next length
                }
            }
        }
    }

    return longestMatch;
}

QString MetadataExtractor::findMatchingLrcFile(const QString &audioFilePath) const
{
    QFileInfo audioFileInfo(audioFilePath);
    QString audioDir = audioFileInfo.path();
    QString audioBaseName = audioFileInfo.completeBaseName();

    // Pass 1: Try exact match (fast path - most common case)
    QString exactMatchPath = audioDir + "/" + audioBaseName + ".lrc";
    if (QFileInfo::exists(exactMatchPath)) {
        return exactMatchPath;
    }

    // Pass 2: Fuzzy matching - find all .lrc files in directory
    QDir dir(audioDir);
    QStringList lrcFiles = dir.entryList(QStringList() << "*.lrc" << "*.LRC", QDir::Files);

    if (lrcFiles.isEmpty()) {
        return QString();  // No LRC files in directory
    }

    // Find best match based on longest common substring
    QString bestMatch;
    int bestMatchLength = 0;
    bool bestMatchAtStart = false;

    for (const QString &lrcFileName : lrcFiles) {
        QString lrcBaseName = QFileInfo(lrcFileName).completeBaseName();

        // Find longest common substring between audio and LRC basenames
        QString commonSubstring = findLongestCommonSubstring(audioBaseName, lrcBaseName, 4);

        if (!commonSubstring.isEmpty()) {
            int matchLength = commonSubstring.length();

            // Check if match is at the start of LRC filename (higher priority)
            bool matchAtStart = lrcBaseName.toLower().startsWith(commonSubstring.toLower());

            // Prefer longer matches, or matches at the start if length is equal
            if (matchLength > bestMatchLength ||
                (matchLength == bestMatchLength && matchAtStart && !bestMatchAtStart)) {
                bestMatchLength = matchLength;
                bestMatch = audioDir + "/" + lrcFileName;
                bestMatchAtStart = matchAtStart;
            }
        }
    }

    if (!bestMatch.isEmpty()) {
        qDebug() << "MetadataExtractor: Fuzzy matched LRC file:" << bestMatch
                 << "for audio file:" << audioBaseName << "(match length:" << bestMatchLength << ")";
    }

    return bestMatch;
}

} // namespace Mtoc
