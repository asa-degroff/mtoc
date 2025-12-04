#ifndef TRACKMODEL_H
#define TRACKMODEL_H

#include <QAbstractListModel>
#include <QList>

#include "track.h"

namespace Mtoc {

class TrackModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum TrackRoles {
        TitleRole = Qt::UserRole + 1,
        ArtistRole,
        AlbumArtistRole,
        AlbumRole,
        GenreRole,
        YearRole,
        TrackNumberRole,
        DiscNumberRole,
        DurationRole,
        DurationFormattedRole,
        FileUrlRole,
        FilePathRole,
        TrackObjectRole, // For accessing the full Track object
        IdRole,
        IsFavoriteRole
    };
    Q_ENUM(TrackRoles)

    explicit TrackModel(QObject *parent = nullptr);

    // QAbstractListModel implementation
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    // Add/remove tracks
    Q_INVOKABLE void addTrack(Track *track);
    Q_INVOKABLE bool removeTrack(Track *track);
    Q_INVOKABLE void removeTrackAt(int index);
    Q_INVOKABLE void clear();
    
    // Access tracks
    Q_INVOKABLE QList<Track*> tracks() const;
    Q_INVOKABLE Track* trackAt(int index) const;
    Q_INVOKABLE int indexOf(Track *track) const;
    
    // Sort tracks
    Q_INVOKABLE void sortByTrackNumber(); // Sort by disc number, then track number
    Q_INVOKABLE void sortByTitle(); // Sort alphabetically by title
    Q_INVOKABLE void sortByArtist(); // Sort alphabetically by artist, then title
    Q_INVOKABLE void sortByAlbum(); // Sort alphabetically by album, then disc/track number

signals:
    void countChanged();

private:
    QList<Track*> m_tracks;
};

} // namespace Mtoc

#endif // TRACKMODEL_H