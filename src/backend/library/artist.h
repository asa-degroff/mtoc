#ifndef ARTIST_H
#define ARTIST_H

#include <QObject>
#include <QString>
#include <QList>
#include <QUrl>

#include "album.h"

namespace Mtoc {

class Artist : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString name READ name WRITE setName NOTIFY nameChanged)
    Q_PROPERTY(int albumCount READ albumCount NOTIFY albumCountChanged)
    Q_PROPERTY(int trackCount READ trackCount NOTIFY trackCountChanged)
    Q_PROPERTY(QUrl imageUrl READ imageUrl WRITE setImageUrl NOTIFY imageUrlChanged)

public:
    explicit Artist(QObject *parent = nullptr);
    explicit Artist(const QString &name, QObject *parent = nullptr);
    
    // Property getters
    QString name() const;
    int albumCount() const;
    int trackCount() const;
    QUrl imageUrl() const;
    
    // Property setters
    void setName(const QString &name);
    void setImageUrl(const QUrl &url);
    
    // Album management methods
    Q_INVOKABLE QList<Album*> albums() const;
    Q_INVOKABLE void addAlbum(Album *album);
    Q_INVOKABLE bool removeAlbum(Album *album);
    Q_INVOKABLE Album* albumAt(int index) const;
    Q_INVOKABLE Album* findAlbumByTitle(const QString &title) const;
    
    // Utility methods
    Q_INVOKABLE QString formattedDuration() const; // Total artist duration
    Q_INVOKABLE void sortAlbums(); // Sort albums by year, then title
    
signals:
    void nameChanged();
    void albumCountChanged();
    void trackCountChanged();
    void imageUrlChanged();
    void albumAdded(Album *album);
    void albumRemoved(Album *album);
    void albumsReordered();
    
    // Track-related signals (proxied from albums)
    void trackAdded(Track *track, Album *album);
    void trackRemoved(Track *track, Album *album);
    
private slots:
    void onAlbumTrackAdded(Track *track);
    void onAlbumTrackRemoved(Track *track);
    void onAlbumTrackCountChanged();
    
private:
    QString m_name;
    QUrl m_imageUrl;
    QList<Album*> m_albums;
};

} // namespace Mtoc

#endif // ARTIST_H