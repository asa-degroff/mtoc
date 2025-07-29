#include "VirtualPlaylistModel.h"
#include "VirtualPlaylist.h"
#include <QDebug>

namespace Mtoc {

VirtualPlaylistModel::VirtualPlaylistModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

VirtualPlaylistModel::~VirtualPlaylistModel()
{
    disconnectPlaylistSignals();
}

int VirtualPlaylistModel::rowCount(const QModelIndex &parent) const
{
    Q_UNUSED(parent)
    return m_playlist ? m_playlist->trackCount() : 0;
}

QVariant VirtualPlaylistModel::data(const QModelIndex &index, int role) const
{
    if (!m_playlist || !index.isValid() || index.row() < 0 || index.row() >= m_playlist->trackCount()) {
        return QVariant();
    }
    
    int row = index.row();
    
    // Check if track is loaded
    if (!m_playlist->isTrackLoaded(row)) {
        if (role == IsLoadedRole) {
            return false;
        }
        
        // Trigger loading for this track
        const_cast<VirtualPlaylistModel*>(this)->preloadAround(row);
        
        // Return placeholder data
        switch (role) {
        case TitleRole:
            return tr("Loading...");
        case ArtistRole:
        case AlbumRole:
        case AlbumArtistRole:
        case GenreRole:
            return QString();
        case DurationRole:
        case TrackNumberRole:
        case DiscNumberRole:
        case YearRole:
        case PlayCountRole:
        case RatingRole:
        case FileSizeRole:
            return 0;
        default:
            return QVariant();
        }
    }
    
    // Get track data
    VirtualTrackData track = m_playlist->getTrack(row);
    
    switch (role) {
    case IdRole:
        return track.id;
    case FilePathRole:
        return track.filePath;
    case TitleRole:
        return track.title.isEmpty() ? tr("Unknown") : track.title;
    case ArtistRole:
        return track.artist.isEmpty() ? tr("Unknown Artist") : track.artist;
    case AlbumRole:
        return track.album.isEmpty() ? tr("Unknown Album") : track.album;
    case AlbumArtistRole:
        return track.albumArtist;
    case GenreRole:
        return track.genre;
    case YearRole:
        return track.year;
    case TrackNumberRole:
        return track.trackNumber;
    case DiscNumberRole:
        return track.discNumber;
    case DurationRole:
        return track.duration;
    case FileSizeRole:
        return track.fileSize;
    case PlayCountRole:
        return track.playCount;
    case RatingRole:
        return track.rating;
    case LastPlayedRole:
        return track.lastPlayed;
    case IsLoadedRole:
        return true;
    default:
        return QVariant();
    }
}

QHash<int, QByteArray> VirtualPlaylistModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[IdRole] = "trackId";
    roles[FilePathRole] = "filePath";
    roles[TitleRole] = "title";
    roles[ArtistRole] = "artist";
    roles[AlbumRole] = "album";
    roles[AlbumArtistRole] = "albumArtist";
    roles[GenreRole] = "genre";
    roles[YearRole] = "year";
    roles[TrackNumberRole] = "trackNumber";
    roles[DiscNumberRole] = "discNumber";
    roles[DurationRole] = "duration";
    roles[FileSizeRole] = "fileSize";
    roles[PlayCountRole] = "playCount";
    roles[RatingRole] = "rating";
    roles[LastPlayedRole] = "lastPlayed";
    roles[IsLoadedRole] = "isLoaded";
    return roles;
}

bool VirtualPlaylistModel::canFetchMore(const QModelIndex &parent) const
{
    Q_UNUSED(parent)
    
    if (!m_playlist) {
        return false;
    }
    
    // Can fetch more if not all tracks are loaded
    return !m_playlist->isFullyLoaded();
}

void VirtualPlaylistModel::fetchMore(const QModelIndex &parent)
{
    Q_UNUSED(parent)
    
    if (!m_playlist) {
        return;
    }
    
    // Load next batch starting from last fetch position
    m_playlist->preloadRange(m_lastFetchIndex, m_fetchBatchSize / 2);
    m_lastFetchIndex += m_fetchBatchSize;
    
    if (m_lastFetchIndex >= m_playlist->trackCount()) {
        m_lastFetchIndex = 0;
    }
}

void VirtualPlaylistModel::setVirtualPlaylist(VirtualPlaylist* playlist)
{
    if (m_playlist == playlist) {
        return;
    }
    
    beginResetModel();
    
    disconnectPlaylistSignals();
    m_playlist = playlist;
    m_lastFetchIndex = 0;
    
    if (m_playlist) {
        connectPlaylistSignals();
    }
    
    endResetModel();
    
    emit countChanged();
    emit loadingChanged();
    emit loadedCountChanged();
    emit totalDurationChanged();
}

int VirtualPlaylistModel::count() const
{
    return m_playlist ? m_playlist->trackCount() : 0;
}

bool VirtualPlaylistModel::isLoading() const
{
    return m_playlist ? m_playlist->isLoading() : false;
}

int VirtualPlaylistModel::loadedCount() const
{
    return m_playlist ? m_playlist->loadedTrackCount() : 0;
}

int VirtualPlaylistModel::totalDuration() const
{
    return m_playlist ? m_playlist->totalDuration() : 0;
}

QVariantMap VirtualPlaylistModel::getTrack(int index) const
{
    if (!m_playlist || index < 0 || index >= m_playlist->trackCount()) {
        return QVariantMap();
    }
    
    return m_playlist->getTrackVariant(index);
}

void VirtualPlaylistModel::preloadAround(int index, int radius)
{
    if (!m_playlist) {
        return;
    }
    
    m_playlist->preloadRange(index, radius);
}

bool VirtualPlaylistModel::isTrackLoaded(int index) const
{
    if (!m_playlist || index < 0 || index >= m_playlist->trackCount()) {
        return false;
    }
    
    return m_playlist->isTrackLoaded(index);
}

QVariantList VirtualPlaylistModel::getTracksForPlayback(int startIndex, int count) const
{
    QVariantList result;
    
    if (!m_playlist || startIndex < 0 || count <= 0) {
        return result;
    }
    
    int endIndex = qMin(startIndex + count, m_playlist->trackCount());
    
    for (int i = startIndex; i < endIndex; ++i) {
        QVariantMap track = getTrack(i);
        if (!track.isEmpty()) {
            result.append(track);
        }
    }
    
    return result;
}

void VirtualPlaylistModel::onLoadingStarted()
{
    emit loadingChanged();
}

void VirtualPlaylistModel::onLoadingFinished()
{
    emit loadingChanged();
    emit loadedCountChanged();
    emit totalDurationChanged();
}

void VirtualPlaylistModel::onRangeLoaded(int startIndex, int endIndex)
{
    // Emit dataChanged for the loaded range
    QModelIndex topLeft = index(startIndex);
    QModelIndex bottomRight = index(endIndex);
    emit dataChanged(topLeft, bottomRight);
    
    emit loadedCountChanged();
    emit totalDurationChanged();
}

void VirtualPlaylistModel::onLoadingProgress(int loaded, int total)
{
    emit loadingProgress(loaded, total);
    emit loadedCountChanged();
}

void VirtualPlaylistModel::connectPlaylistSignals()
{
    if (!m_playlist) {
        return;
    }
    
    connect(m_playlist, &VirtualPlaylist::loadingStarted,
            this, &VirtualPlaylistModel::onLoadingStarted);
    connect(m_playlist, &VirtualPlaylist::loadingFinished,
            this, &VirtualPlaylistModel::onLoadingFinished);
    connect(m_playlist, &VirtualPlaylist::rangeLoaded,
            this, &VirtualPlaylistModel::onRangeLoaded);
    connect(m_playlist, &VirtualPlaylist::loadingProgress,
            this, &VirtualPlaylistModel::onLoadingProgress);
}

void VirtualPlaylistModel::disconnectPlaylistSignals()
{
    if (!m_playlist) {
        return;
    }
    
    disconnect(m_playlist, nullptr, this, nullptr);
}

} // namespace Mtoc