#include "track.h"
#include <QFileInfo>

namespace Mtoc {

Track::Track(QObject *parent)
    : QObject(parent)
{
}

Track::Track(const QUrl &fileUrl, QObject *parent)
    : QObject(parent)
    , m_fileUrl(fileUrl)
{
}

// Property getters
QString Track::title() const
{
    return m_title;
}

QString Track::artist() const
{
    return m_artist;
}

QString Track::albumArtist() const
{
    return m_albumArtist;
}

QStringList Track::albumArtists() const
{
    // Parse album artist string using common delimiters
    if (m_albumArtist.isEmpty()) {
        return QStringList();
    }

    // Try common delimiters in order
    QStringList delimiters = {"; ", " | "};

    for (const QString &delimiter : delimiters) {
        if (m_albumArtist.contains(delimiter)) {
            QStringList artists = m_albumArtist.split(delimiter, Qt::SkipEmptyParts);
            // Trim whitespace from each artist
            for (QString &artist : artists) {
                artist = artist.trimmed();
            }
            return artists;
        }
    }

    // No delimiter found, return single artist
    return QStringList{m_albumArtist};
}

QString Track::album() const
{
    return m_album;
}

QString Track::genre() const
{
    return m_genre;
}

int Track::year() const
{
    return m_year;
}

int Track::trackNumber() const
{
    return m_trackNumber;
}

int Track::discNumber() const
{
    return m_discNumber;
}

int Track::duration() const
{
    return m_duration;
}

QUrl Track::fileUrl() const
{
    return m_fileUrl;
}

QString Track::filePath() const
{
    // For local files, get the local file path
    return m_fileUrl.isLocalFile() ? m_fileUrl.toLocalFile() : m_fileUrl.toString();
}

QString Track::lyrics() const
{
    return m_lyrics;
}

// Property setters
void Track::setTitle(const QString &title)
{
    if (m_title != title) {
        m_title = title;
        emit titleChanged();
    }
}

void Track::setArtist(const QString &artist)
{
    if (m_artist != artist) {
        m_artist = artist;
        emit artistChanged();
    }
}

void Track::setAlbumArtist(const QString &albumArtist)
{
    if (m_albumArtist != albumArtist) {
        m_albumArtist = albumArtist;
        emit albumArtistChanged();
    }
}

void Track::setAlbum(const QString &album)
{
    if (m_album != album) {
        m_album = album;
        emit albumChanged();
    }
}

void Track::setGenre(const QString &genre)
{
    if (m_genre != genre) {
        m_genre = genre;
        emit genreChanged();
    }
}

void Track::setYear(int year)
{
    if (m_year != year) {
        m_year = year;
        emit yearChanged();
    }
}

void Track::setTrackNumber(int trackNumber)
{
    if (m_trackNumber != trackNumber) {
        m_trackNumber = trackNumber;
        emit trackNumberChanged();
    }
}

void Track::setDiscNumber(int discNumber)
{
    if (m_discNumber != discNumber) {
        m_discNumber = discNumber;
        emit discNumberChanged();
    }
}

void Track::setDuration(int duration)
{
    if (m_duration != duration) {
        m_duration = duration;
        emit durationChanged();
    }
}

void Track::setFileUrl(const QUrl &url)
{
    if (m_fileUrl != url) {
        m_fileUrl = url;
        emit fileUrlChanged();
        emit filePathChanged(); // Path is derived from URL
    }
}

void Track::setLyrics(const QString &lyrics)
{
    if (m_lyrics != lyrics) {
        m_lyrics = lyrics;
        emit lyricsChanged();
    }
}

// Additional methods
QString Track::formattedDuration() const
{
    int minutes = m_duration / 60;
    int seconds = m_duration % 60;
    return QString("%1:%2").arg(minutes).arg(seconds, 2, 10, QChar('0'));
}

bool Track::isValid() const
{
    // A track is valid if it has at least a title and a file URL
    return !m_title.isEmpty() && !m_fileUrl.isEmpty();
}

// Utility functions
Track* Track::fromMetadata(const QVariantMap &metadata, QObject *parent)
{
    Track* track = new Track(parent);
    
    // Get file path and convert to URL
    if (metadata.contains("filePath")) {
        QString filePath = metadata.value("filePath").toString();
        track->setFileUrl(QUrl::fromLocalFile(filePath));
    }
    
    // Set other metadata properties
    if (metadata.contains("title"))
        track->setTitle(metadata.value("title").toString());
        
    if (metadata.contains("artist"))
        track->setArtist(metadata.value("artist").toString());
        
    if (metadata.contains("albumArtist"))
        track->setAlbumArtist(metadata.value("albumArtist").toString());
    else if (metadata.contains("artist")) // Fallback to artist if albumArtist is not available
        track->setAlbumArtist(metadata.value("artist").toString());
        
    if (metadata.contains("album"))
        track->setAlbum(metadata.value("album").toString());
        
    if (metadata.contains("genre"))
        track->setGenre(metadata.value("genre").toString());
        
    if (metadata.contains("year"))
        track->setYear(metadata.value("year").toInt());
        
    if (metadata.contains("trackNumber"))
        track->setTrackNumber(metadata.value("trackNumber").toInt());
        
    if (metadata.contains("discNumber"))
        track->setDiscNumber(metadata.value("discNumber").toInt());
        
    if (metadata.contains("duration"))
        track->setDuration(metadata.value("duration").toInt());

    if (metadata.contains("lyrics"))
        track->setLyrics(metadata.value("lyrics").toString());
    
    return track;
}

} // namespace Mtoc