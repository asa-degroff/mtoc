#ifndef ALBUMARTMANAGER_H
#define ALBUMARTMANAGER_H

#include <QObject>
#include <QString>
#include <QByteArray>
#include <QImage>
#include <QSize>

namespace Mtoc {

class AlbumArtManager : public QObject
{
    Q_OBJECT
public:
    explicit AlbumArtManager(QObject *parent = nullptr);
    
    // Process album art from raw data
    struct ProcessedAlbumArt {
        QByteArray thumbnailData;
        QString fullImagePath;
        QString hash;
        QSize originalSize;
        QString format;
        qint64 fileSize;
        bool success;
        QString error;
    };
    
    ProcessedAlbumArt processAlbumArt(const QByteArray& rawData, 
                                      const QString& albumName, 
                                      const QString& artistName,
                                      const QString& mimeType = QString());
    
    // Get album art storage path
    QString getAlbumArtDirectory() const;
    QString generateAlbumArtFilename(const QString& albumName, 
                                    const QString& artistName, 
                                    const QString& hash) const;
    
    // Thumbnail configuration
    int getThumbnailSize() const;
    static constexpr int MAX_FULL_SIZE = 1800;
    
signals:
    void albumArtProcessed(const QString& albumName, bool success);
    void error(const QString& message);
    
private:
    // Helper methods
    QString calculateHash(const QByteArray& data) const;
    QImage createThumbnail(const QImage& source) const;
    QImage createThumbnail(const QImage& source, int size) const;
    bool saveFullImage(const QImage& image, const QString& path, const QString& format) const;
    QString sanitizeFilename(const QString& name) const;
    QString detectImageFormat(const QByteArray& data) const;
};

} // namespace Mtoc

#endif // ALBUMARTMANAGER_H