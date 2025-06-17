#include "trackmodel.h"
#include <algorithm> // For std::sort

namespace Mtoc {

TrackModel::TrackModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int TrackModel::rowCount(const QModelIndex &parent) const
{
    // For list models, the root node (only valid parent) shouldn't have children
    if (parent.isValid())
        return 0;

    return m_tracks.count();
}

QVariant TrackModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_tracks.count())
        return QVariant();

    Track *track = m_tracks.at(index.row());
    
    switch (role) {
    case TitleRole:
        return track->title();
    case ArtistRole:
        return track->artist();
    case AlbumArtistRole:
        return track->albumArtist();
    case AlbumRole:
        return track->album();
    case GenreRole:
        return track->genre();
    case YearRole:
        return track->year();
    case TrackNumberRole:
        return track->trackNumber();
    case DiscNumberRole:
        return track->discNumber();
    case DurationRole:
        return track->duration();
    case DurationFormattedRole:
        return track->formattedDuration();
    case FileUrlRole:
        return track->fileUrl();
    case FilePathRole:
        return track->filePath();
    case TrackObjectRole:
        return QVariant::fromValue(track);
    }

    return QVariant();
}

QHash<int, QByteArray> TrackModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[TitleRole] = "title";
    roles[ArtistRole] = "artist";
    roles[AlbumArtistRole] = "albumArtist";
    roles[AlbumRole] = "album";
    roles[GenreRole] = "genre";
    roles[YearRole] = "year";
    roles[TrackNumberRole] = "trackNumber";
    roles[DiscNumberRole] = "discNumber";
    roles[DurationRole] = "duration";
    roles[DurationFormattedRole] = "durationFormatted";
    roles[FileUrlRole] = "fileUrl";
    roles[FilePathRole] = "filePath";
    roles[TrackObjectRole] = "trackObject";
    return roles;
}

void TrackModel::addTrack(Track *track)
{
    if (!track || m_tracks.contains(track))
        return;
    
    beginInsertRows(QModelIndex(), m_tracks.count(), m_tracks.count());
    m_tracks.append(track);
    endInsertRows();
    
    emit countChanged();
}

bool TrackModel::removeTrack(Track *track)
{
    if (!track || !m_tracks.contains(track))
        return false;
    
    int index = m_tracks.indexOf(track);
    if (index >= 0) {
        beginRemoveRows(QModelIndex(), index, index);
        m_tracks.removeAt(index);
        endRemoveRows();
        
        emit countChanged();
        return true;
    }
    
    return false;
}

void TrackModel::removeTrackAt(int index)
{
    if (index < 0 || index >= m_tracks.count())
        return;
    
    beginRemoveRows(QModelIndex(), index, index);
    m_tracks.removeAt(index);
    endRemoveRows();
    
    emit countChanged();
}

void TrackModel::clear()
{
    if (m_tracks.isEmpty())
        return;
    
    beginResetModel();
    m_tracks.clear();
    endResetModel();
    
    emit countChanged();
}

QList<Track*> TrackModel::tracks() const
{
    return m_tracks;
}

Track* TrackModel::trackAt(int index) const
{
    return (index >= 0 && index < m_tracks.count()) ? m_tracks.at(index) : nullptr;
}

int TrackModel::indexOf(Track *track) const
{
    return m_tracks.indexOf(track);
}

void TrackModel::sortByTrackNumber()
{
    if (m_tracks.count() <= 1)
        return;
    
    beginResetModel();
    
    std::sort(m_tracks.begin(), m_tracks.end(), [](Track *a, Track *b) {
        // First sort by disc number
        if (a->discNumber() != b->discNumber())
            return a->discNumber() < b->discNumber();
            
        // Then by track number
        return a->trackNumber() < b->trackNumber();
    });
    
    endResetModel();
}

void TrackModel::sortByTitle()
{
    if (m_tracks.count() <= 1)
        return;
    
    beginResetModel();
    
    std::sort(m_tracks.begin(), m_tracks.end(), [](Track *a, Track *b) {
        return a->title().localeAwareCompare(b->title()) < 0;
    });
    
    endResetModel();
}

void TrackModel::sortByArtist()
{
    if (m_tracks.count() <= 1)
        return;
    
    beginResetModel();
    
    std::sort(m_tracks.begin(), m_tracks.end(), [](Track *a, Track *b) {
        // First sort by artist
        int artistCompare = a->artist().localeAwareCompare(b->artist());
        if (artistCompare != 0)
            return artistCompare < 0;
            
        // Then by title
        return a->title().localeAwareCompare(b->title()) < 0;
    });
    
    endResetModel();
}

void TrackModel::sortByAlbum()
{
    if (m_tracks.count() <= 1)
        return;
    
    beginResetModel();
    
    std::sort(m_tracks.begin(), m_tracks.end(), [](Track *a, Track *b) {
        // First sort by album
        int albumCompare = a->album().localeAwareCompare(b->album());
        if (albumCompare != 0)
            return albumCompare < 0;
            
        // Then by disc number
        if (a->discNumber() != b->discNumber())
            return a->discNumber() < b->discNumber();
            
        // Then by track number
        return a->trackNumber() < b->trackNumber();
    });
    
    endResetModel();
}

} // namespace Mtoc