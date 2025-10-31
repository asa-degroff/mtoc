#include "album.h"
#include <algorithm> // For std::sort

namespace Mtoc {

Album::Album(QObject *parent)
    : QObject(parent)
{
}

Album::Album(const QString &title, const QString &artist, QObject *parent)
    : QObject(parent)
    , m_title(title)
    , m_artist(artist)
{
}

// Property getters
QString Album::title() const
{
    return m_title;
}

QString Album::artist() const
{
    return m_artist;
}

int Album::year() const
{
    return m_year;
}

int Album::trackCount() const
{
    return m_tracks.count();
}

QString Album::genre() const
{
    return m_genre;
}

QUrl Album::coverArtUrl() const
{
    return m_coverArtUrl;
}

// Property setters
void Album::setTitle(const QString &title)
{
    if (m_title != title) {
        m_title = title;
        emit titleChanged();
    }
}

void Album::setArtist(const QString &artist)
{
    if (m_artist != artist) {
        m_artist = artist;
        emit artistChanged();
    }
}

QStringList Album::artists() const
{
    return m_artists;
}

void Album::setArtists(const QStringList &artists)
{
    if (m_artists != artists) {
        m_artists = artists;
        emit artistsChanged();
    }
}

void Album::setYear(int year)
{
    if (m_year != year) {
        m_year = year;
        emit yearChanged();
    }
}

void Album::setGenre(const QString &genre)
{
    if (m_genre != genre) {
        m_genre = genre;
        emit genreChanged();
    }
}

void Album::setCoverArtUrl(const QUrl &url)
{
    if (m_coverArtUrl != url) {
        m_coverArtUrl = url;
        emit coverArtUrlChanged();
    }
}

// Track management methods
QList<Track*> Album::tracks() const
{
    return m_tracks;
}

void Album::addTrack(Track *track)
{
    // Don't add if already in album or null
    if (!track || m_tracks.contains(track))
        return;
        
    // Set the track's album if different
    if (track->album() != m_title) {
        track->setAlbum(m_title);
    }
    
    // Set the track's album artist if different
    if (track->albumArtist() != m_artist) {
        track->setAlbumArtist(m_artist);
    }
    
    // If this is the first track, set album metadata from track
    if (m_tracks.isEmpty()) {
        if (m_title.isEmpty())
            setTitle(track->album());
            
        if (m_artist.isEmpty())
            setArtist(track->albumArtist());
            
        if (m_year == 0)
            setYear(track->year());
            
        if (m_genre.isEmpty())
            setGenre(track->genre());
    }
    
    // Add the track
    m_tracks.append(track);
    emit trackAdded(track);
    emit trackCountChanged();
}

bool Album::removeTrack(Track *track)
{
    if (!track || !m_tracks.contains(track))
        return false;
        
    if (m_tracks.removeOne(track)) {
        emit trackRemoved(track);
        emit trackCountChanged();
        return true;
    }
    
    return false;
}

Track* Album::trackAt(int index) const
{
    return (index >= 0 && index < m_tracks.count()) ? m_tracks.at(index) : nullptr;
}

void Album::sortTracks()
{
    // Sort by track number
    std::sort(m_tracks.begin(), m_tracks.end(), [](Track *a, Track *b) {
        // First sort by disc number
        if (a->discNumber() != b->discNumber())
            return a->discNumber() < b->discNumber();
            
        // Then by track number
        return a->trackNumber() < b->trackNumber();
    });
    
    emit tracksReordered();
}

// Utility methods
QString Album::formattedDuration() const
{
    // Sum up the duration of all tracks
    int totalSeconds = 0;
    for (Track *track : m_tracks) {
        totalSeconds += track->duration();
    }
    
    // Format as HH:MM:SS if the album is long or MM:SS if it's short
    int hours = totalSeconds / 3600;
    int minutes = (totalSeconds % 3600) / 60;
    int seconds = totalSeconds % 60;
    
    if (hours > 0) {
        return QString("%1:%2:%3")
                .arg(hours)
                .arg(minutes, 2, 10, QChar('0'))
                .arg(seconds, 2, 10, QChar('0'));
    } else {
        return QString("%1:%2")
                .arg(minutes)
                .arg(seconds, 2, 10, QChar('0'));
    }
}

bool Album::containsTrack(const Track *track) const
{
    return m_tracks.contains(const_cast<Track*>(track));
}

} // namespace Mtoc