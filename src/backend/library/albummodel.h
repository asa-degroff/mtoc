#ifndef ALBUMMODEL_H
#define ALBUMMODEL_H

#include <QAbstractListModel>
#include <QList>
#include <QObject>

#include "album.h" // Forward declaration is used in the implementation file

namespace Mtoc {

class AlbumModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum AlbumRoles {
        TitleRole = Qt::UserRole + 1,
        ArtistRole,
        YearRole,
        TrackCountRole,
        GenreRole,
        CoverArtUrlRole,
        AlbumObjectRole // For accessing the full Album object
    };
    Q_ENUM(AlbumRoles)

    explicit AlbumModel(QObject *parent = nullptr);

    // QAbstractListModel implementation
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    // Add/remove albums
    Q_INVOKABLE void addAlbum(Album *album);
    Q_INVOKABLE bool removeAlbum(Album *album);
    Q_INVOKABLE void removeAlbumAt(int index);
    Q_INVOKABLE void clear();
    
    // Access albums
    Q_INVOKABLE QList<Album*> albums() const;
    Q_INVOKABLE Album* albumAt(int index) const;
    Q_INVOKABLE int indexOf(Album *album) const;
    Q_INVOKABLE Album* findAlbumByTitle(const QString &title) const;
    
    // Sort albums
    Q_INVOKABLE void sortByTitle(); // Sort alphabetically by title
    Q_INVOKABLE void sortByArtist(); // Sort alphabetically by artist, then title
    Q_INVOKABLE void sortByYear(); // Sort by year (newer first), then title

signals:
    void countChanged();

private:
    QList<Album*> m_albums;
};

} // namespace Mtoc

#endif // ALBUMMODEL_H