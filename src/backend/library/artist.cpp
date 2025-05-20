#include "artist.h"
#include <algorithm> // For std::sort

namespace Mtoc {

Artist::Artist(QObject *parent)
    : QObject(parent)
{
}

Artist::Artist(const QString &name, QObject *parent)
    : QObject(parent)
    , m_name(name)
{
}

// Property getters
QString Artist::name() const
{
    return m_name;
}

int Artist::albumCount() const
{
    return m_albums.count();
}

int Artist::trackCount() const
{
    int count = 0;
    for (const Album *album : m_albums) {
        count += album->trackCount();
    }
    return count;
}

QUrl Artist::imageUrl() const
{
    return m_imageUrl;
}

// Property setters
void Artist::setName(const QString &name)
{
    if (m_name != name) {
        m_name = name;
        emit nameChanged();
    }
}

void Artist::setImageUrl(const QUrl &url)
{
    if (m_imageUrl != url) {
        m_imageUrl = url;
        emit imageUrlChanged();
    }
}

// Album management methods
QList<Album*> Artist::albums() const
{
    return m_albums;
}

void Artist::addAlbum(Album *album)
{
    // Don't add if already in artist collection or null
    if (!album || m_albums.contains(album))
        return;
        
    // Set the album's artist if different
    if (album->artist() != m_name) {
        album->setArtist(m_name);
    }
    
    // Connect to album signals
    connect(album, &Album::trackAdded, this, &Artist::onAlbumTrackAdded);
    connect(album, &Album::trackRemoved, this, &Artist::onAlbumTrackRemoved);
    connect(album, &Album::trackCountChanged, this, &Artist::onAlbumTrackCountChanged);
    
    // Add the album
    m_albums.append(album);
    emit albumAdded(album);
    emit albumCountChanged();
    emit trackCountChanged(); // As we added an album, track count may have changed
}

bool Artist::removeAlbum(Album *album)
{
    if (!album || !m_albums.contains(album))
        return false;
    
    // Disconnect from album signals
    disconnect(album, &Album::trackAdded, this, &Artist::onAlbumTrackAdded);
    disconnect(album, &Album::trackRemoved, this, &Artist::onAlbumTrackRemoved);
    disconnect(album, &Album::trackCountChanged, this, &Artist::onAlbumTrackCountChanged);
    
    if (m_albums.removeOne(album)) {
        emit albumRemoved(album);
        emit albumCountChanged();
        emit trackCountChanged(); // As we removed an album, track count may have changed
        return true;
    }
    
    return false;
}

Album* Artist::albumAt(int index) const
{
    return (index >= 0 && index < m_albums.count()) ? m_albums.at(index) : nullptr;
}

Album* Artist::findAlbumByTitle(const QString &title) const
{
    for (Album *album : m_albums) {
        if (album->title().compare(title, Qt::CaseInsensitive) == 0) {
            return album;
        }
    }
    return nullptr;
}

// Utility methods
QString Artist::formattedDuration() const
{
    // Sum up the duration of all albums
    int totalSeconds = 0;
    for (Album *album : m_albums) {
        for (Track *track : album->tracks()) {
            totalSeconds += track->duration();
        }
    }
    
    // Format as HH:MM:SS if long or MM:SS if short
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

void Artist::sortAlbums()
{
    // Sort by year (primary) and then title (secondary)
    std::sort(m_albums.begin(), m_albums.end(), [](Album *a, Album *b) {
        // First sort by year
        if (a->year() != b->year()) {
            // Newer albums first if year is available
            if (a->year() == 0) return false; // Put albums with no year at the end
            if (b->year() == 0) return true;  // Put albums with no year at the end
            return a->year() < b->year();
        }
        
        // Then by title
        return a->title().compare(b->title(), Qt::CaseInsensitive) < 0;
    });
    
    emit albumsReordered();
}

// Private slots
void Artist::onAlbumTrackAdded(Track *track)
{
    // Find which album this track was added to
    Album *album = qobject_cast<Album*>(sender());
    if (album) {
        emit trackAdded(track, album);
        emit trackCountChanged();
    }
}

void Artist::onAlbumTrackRemoved(Track *track)
{
    // Find which album this track was removed from
    Album *album = qobject_cast<Album*>(sender());
    if (album) {
        emit trackRemoved(track, album);
        emit trackCountChanged();
    }
}

void Artist::onAlbumTrackCountChanged()
{
    // Propagate the track count change signal
    emit trackCountChanged();
}

} // namespace Mtoc