#ifndef ALBUM_H
#define ALBUM_H

#include <QObject>
#include <QString>
#include <QList>
#include <QUrl>
#include <QImage>

#include "track.h"

namespace Mtoc {

class Album : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString title READ title WRITE setTitle NOTIFY titleChanged)
    Q_PROPERTY(QString artist READ artist WRITE setArtist NOTIFY artistChanged)
    Q_PROPERTY(int year READ year WRITE setYear NOTIFY yearChanged)
    Q_PROPERTY(int trackCount READ trackCount NOTIFY trackCountChanged)
    Q_PROPERTY(QString genre READ genre WRITE setGenre NOTIFY genreChanged)
    Q_PROPERTY(QUrl coverArtUrl READ coverArtUrl WRITE setCoverArtUrl NOTIFY coverArtUrlChanged)

public:
    explicit Album(QObject *parent = nullptr);
    explicit Album(const QString &title, const QString &artist, QObject *parent = nullptr);
    
    // Property getters
    QString title() const;
    QString artist() const;
    int year() const;
    int trackCount() const;
    QString genre() const;
    QUrl coverArtUrl() const;
    
    // Property setters
    void setTitle(const QString &title);
    void setArtist(const QString &artist);
    void setYear(int year);
    void setGenre(const QString &genre);
    void setCoverArtUrl(const QUrl &url);
    
    // Track management methods
    Q_INVOKABLE QList<Track*> tracks() const;
    Q_INVOKABLE void addTrack(Track *track);
    Q_INVOKABLE bool removeTrack(Track *track);
    Q_INVOKABLE Track* trackAt(int index) const;
    Q_INVOKABLE void sortTracks(); // Sort by track number
    
    // Utility methods
    Q_INVOKABLE QString formattedDuration() const; // Total album duration
    Q_INVOKABLE bool containsTrack(const Track *track) const;
    
signals:
    void titleChanged();
    void artistChanged();
    void yearChanged();
    void trackCountChanged();
    void genreChanged();
    void coverArtUrlChanged();
    void trackAdded(Track *track);
    void trackRemoved(Track *track);
    void tracksReordered();
    
private:
    QString m_title;
    QString m_artist;
    int m_year = 0;
    QString m_genre;
    QUrl m_coverArtUrl;
    QList<Track*> m_tracks;
};

} // namespace Mtoc

#endif // ALBUM_H