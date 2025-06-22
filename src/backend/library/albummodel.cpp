#include "albummodel.h"
#include <algorithm> // For std::sort

namespace Mtoc {

AlbumModel::AlbumModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int AlbumModel::rowCount(const QModelIndex &parent) const
{
    // For list models, the root node (only valid parent) shouldn't have children
    if (parent.isValid())
        return 0;

    return m_albums.count();
}

QVariant AlbumModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_albums.count())
        return QVariant();

    Album *album = m_albums.at(index.row());
    
    switch (role) {
    case TitleRole:
        return album->title();
    case ArtistRole:
        return album->artist();
    case YearRole:
        return album->year();
    case TrackCountRole:
        return album->trackCount();
    case GenreRole:
        return album->genre();
    case CoverArtUrlRole:
        return album->coverArtUrl();
    case AlbumObjectRole:
        return QVariant::fromValue(album);
    }

    return QVariant();
}

QHash<int, QByteArray> AlbumModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[TitleRole] = "title";
    roles[ArtistRole] = "artist";
    roles[YearRole] = "year";
    roles[TrackCountRole] = "trackCount";
    roles[GenreRole] = "genre";
    roles[CoverArtUrlRole] = "coverArtUrl";
    roles[AlbumObjectRole] = "albumObject";
    return roles;
}

void AlbumModel::addAlbum(Album *album)
{
    if (!album || m_albums.contains(album))
        return;
    
    beginInsertRows(QModelIndex(), m_albums.count(), m_albums.count());
    m_albums.append(album);
    endInsertRows();
    
    emit countChanged();
}

bool AlbumModel::removeAlbum(Album *album)
{
    if (!album || !m_albums.contains(album))
        return false;
    
    int index = m_albums.indexOf(album);
    if (index >= 0) {
        beginRemoveRows(QModelIndex(), index, index);
        m_albums.removeAt(index);
        endRemoveRows();
        
        emit countChanged();
        return true;
    }
    
    return false;
}

void AlbumModel::removeAlbumAt(int index)
{
    if (index < 0 || index >= m_albums.count())
        return;
    
    beginRemoveRows(QModelIndex(), index, index);
    m_albums.removeAt(index);
    endRemoveRows();
    
    emit countChanged();
}

void AlbumModel::clear()
{
    if (m_albums.isEmpty())
        return;
    
    beginResetModel();
    m_albums.clear();
    endResetModel();
    
    emit countChanged();
}

QList<Album*> AlbumModel::albums() const
{
    return m_albums;
}

Album* AlbumModel::albumAt(int index) const
{
    return (index >= 0 && index < m_albums.count()) ? m_albums.at(index) : nullptr;
}

int AlbumModel::indexOf(Album *album) const
{
    return m_albums.indexOf(album);
}

Album* AlbumModel::findAlbumByTitle(const QString &title) const
{
    for (Album *album : m_albums) {
        if (album->title().localeAwareCompare(title) == 0) {
            return album;
        }
    }
    return nullptr;
}

void AlbumModel::sortByTitle()
{
    if (m_albums.count() <= 1)
        return;
    
    beginResetModel();
    
    std::sort(m_albums.begin(), m_albums.end(), [](Album *a, Album *b) {
        return a->title().localeAwareCompare(b->title()) < 0;
    });
    
    endResetModel();
}

void AlbumModel::sortByArtist()
{
    if (m_albums.count() <= 1)
        return;
    
    beginResetModel();
    
    std::sort(m_albums.begin(), m_albums.end(), [](Album *a, Album *b) {
        // Get artist names, removing "The " prefix for sorting
        QString artistA = a->artist();
        QString artistB = b->artist();
        
        // Remove "The " prefix (case-insensitive) for sorting purposes
        if (artistA.startsWith("The ", Qt::CaseInsensitive)) {
            artistA = artistA.mid(4);
        }
        if (artistB.startsWith("The ", Qt::CaseInsensitive)) {
            artistB = artistB.mid(4);
        }
        
        // First sort by artist (without "The " prefix)
        int artistCompare = artistA.localeAwareCompare(artistB);
        if (artistCompare != 0)
            return artistCompare < 0;
            
        // Then by title
        return a->title().localeAwareCompare(b->title()) < 0;
    });
    
    endResetModel();
}

void AlbumModel::sortByYear()
{
    if (m_albums.count() <= 1)
        return;
    
    beginResetModel();
    
    std::sort(m_albums.begin(), m_albums.end(), [](Album *a, Album *b) {
        // Sort by year (newer first)
        if (a->year() != b->year()) {
            // Albums with no year go to the end
            if (a->year() == 0) return false;
            if (b->year() == 0) return true;
            
            // Newer albums first
            return a->year() > b->year();
        }
        
        // If same year, sort by title
        return a->title().localeAwareCompare(b->title()) < 0;
    });
    
    endResetModel();
}

} // namespace Mtoc