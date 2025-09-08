#ifndef TRACK_H
#define TRACK_H

#include <QObject>
#include <QString>
#include <QUrl>
#include <QDateTime>

namespace Mtoc {

class Track : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString title READ title WRITE setTitle NOTIFY titleChanged)
    Q_PROPERTY(QString artist READ artist WRITE setArtist NOTIFY artistChanged)
    Q_PROPERTY(QString albumArtist READ albumArtist WRITE setAlbumArtist NOTIFY albumArtistChanged)
    Q_PROPERTY(QString album READ album WRITE setAlbum NOTIFY albumChanged)
    Q_PROPERTY(QString genre READ genre WRITE setGenre NOTIFY genreChanged)
    Q_PROPERTY(int year READ year WRITE setYear NOTIFY yearChanged)
    Q_PROPERTY(int trackNumber READ trackNumber WRITE setTrackNumber NOTIFY trackNumberChanged)
    Q_PROPERTY(int discNumber READ discNumber WRITE setDiscNumber NOTIFY discNumberChanged)
    Q_PROPERTY(int duration READ duration WRITE setDuration NOTIFY durationChanged)
    Q_PROPERTY(QUrl fileUrl READ fileUrl WRITE setFileUrl NOTIFY fileUrlChanged)
    Q_PROPERTY(QString filePath READ filePath NOTIFY filePathChanged)
    Q_PROPERTY(QString lyrics READ lyrics WRITE setLyrics NOTIFY lyricsChanged)

public:
    explicit Track(QObject *parent = nullptr);
    explicit Track(const QUrl &fileUrl, QObject *parent = nullptr);
    
    // Property getters
    QString title() const;
    QString artist() const;
    QString albumArtist() const;
    QString album() const;
    QString genre() const;
    int year() const;
    int trackNumber() const;
    int discNumber() const;
    int duration() const; // in seconds
    QUrl fileUrl() const;
    QString filePath() const;
    QString lyrics() const;
    
    // Property setters
    void setTitle(const QString &title);
    void setArtist(const QString &artist);
    void setAlbumArtist(const QString &albumArtist);
    void setAlbum(const QString &album);
    void setGenre(const QString &genre);
    void setYear(int year);
    void setTrackNumber(int trackNumber);
    void setDiscNumber(int discNumber);
    void setDuration(int duration);
    void setFileUrl(const QUrl &url);
    void setLyrics(const QString &lyrics);
    
    // Additional methods
    Q_INVOKABLE QString formattedDuration() const; // Returns MM:SS format
    Q_INVOKABLE bool isValid() const;
    
    // Utility functions
    static Track* fromMetadata(const QVariantMap &metadata, QObject *parent = nullptr);
    
signals:
    void titleChanged();
    void artistChanged();
    void albumArtistChanged();
    void albumChanged();
    void genreChanged();
    void yearChanged();
    void trackNumberChanged();
    void discNumberChanged();
    void durationChanged();
    void fileUrlChanged();
    void filePathChanged();
    void lyricsChanged();
    
private:
    QString m_title;
    QString m_artist;
    QString m_albumArtist;
    QString m_album;
    QString m_genre;
    int m_year = 0;
    int m_trackNumber = 0;
    int m_discNumber = 0;
    int m_duration = 0; // in seconds
    QUrl m_fileUrl;
    QString m_lyrics;
};

} // namespace Mtoc

#endif // TRACK_H