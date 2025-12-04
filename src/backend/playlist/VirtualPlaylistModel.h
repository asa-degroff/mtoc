#ifndef VIRTUALPLAYLISTMODEL_H
#define VIRTUALPLAYLISTMODEL_H

#include <QAbstractListModel>
#include <memory>

namespace Mtoc {

class VirtualPlaylist;

class VirtualPlaylistModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(bool loading READ isLoading NOTIFY loadingChanged)
    Q_PROPERTY(int loadedCount READ loadedCount NOTIFY loadedCountChanged)
    Q_PROPERTY(int totalDuration READ totalDuration NOTIFY totalDurationChanged)
    
public:
    enum TrackRoles {
        IdRole = Qt::UserRole + 1,
        FilePathRole,
        TitleRole,
        ArtistRole,
        AlbumRole,
        AlbumArtistRole,
        GenreRole,
        YearRole,
        TrackNumberRole,
        DiscNumberRole,
        DurationRole,
        FileSizeRole,
        PlayCountRole,
        RatingRole,
        LastPlayedRole,
        IsLoadedRole
    };
    
    explicit VirtualPlaylistModel(QObject *parent = nullptr);
    ~VirtualPlaylistModel();
    
    // QAbstractListModel interface
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;
    
    // Pagination support
    bool canFetchMore(const QModelIndex &parent) const override;
    void fetchMore(const QModelIndex &parent) override;
    
    // Model management
    void setVirtualPlaylist(VirtualPlaylist* playlist);
    VirtualPlaylist* virtualPlaylist() const { return m_playlist; }
    
    // Properties
    int count() const;
    bool isLoading() const;
    int loadedCount() const;
    int totalDuration() const;
    
    // Track access
    Q_INVOKABLE QVariantMap getTrack(int index) const;
    Q_INVOKABLE void preloadAround(int index, int radius = -1);
    Q_INVOKABLE bool isTrackLoaded(int index) const;
    
    // Playback support
    Q_INVOKABLE QVariantList getTracksForPlayback(int startIndex, int count) const;

    // Safe reload (wraps clear/load in beginResetModel/endResetModel)
    Q_INVOKABLE void reloadPlaylist();

    // Lazy reload support - mark as needing refresh without immediate reload
    void markNeedsReload();
    void reloadIfNeeded();

signals:
    void countChanged();
    void loadingChanged();
    void loadedCountChanged();
    void totalDurationChanged();
    void loadingProgress(int loaded, int total);
    
private slots:
    void onLoadingStarted();
    void onLoadingFinished();
    void onRangeLoaded(int startIndex, int endIndex);
    void onLoadingProgress(int loaded, int total);
    
private:
    void connectPlaylistSignals();
    void disconnectPlaylistSignals();
    
    VirtualPlaylist* m_playlist = nullptr;
    mutable int m_lastFetchIndex = 0;
    int m_fetchBatchSize = 50;
    bool m_needsReload = false;
};

} // namespace Mtoc

#endif // VIRTUALPLAYLISTMODEL_H