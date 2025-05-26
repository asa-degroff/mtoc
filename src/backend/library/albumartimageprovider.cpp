#include "albumartimageprovider.h"
#include <QDebug>
#include <QPixmap>
#include <QImage>
#include <QUrl>

namespace Mtoc {

AlbumArtImageProvider::AlbumArtImageProvider(DatabaseManager* dbManager)
    : QQuickImageProvider(QQuickImageProvider::Pixmap)
    , m_databaseManager(dbManager)
{
}

QPixmap AlbumArtImageProvider::requestPixmap(const QString &id, QSize *size, const QSize &requestedSize)
{
    // The id format is "albumId/type" or "artist/album/type" where type is "thumbnail" or "full"
    QStringList parts = id.split('/');
    if (parts.isEmpty()) {
        qWarning() << "AlbumArtImageProvider: Invalid image id:" << id;
        return QPixmap();
    }
    
    int albumId = 0;
    QString type = "thumbnail";
    
    // Try to parse as numeric album ID first
    bool ok;
    albumId = parts[0].toInt(&ok);
    if (ok && albumId > 0) {
        // Numeric ID format: "albumId" or "albumId/type"
        type = parts.size() > 1 ? parts[1] : "thumbnail";
    } else {
        // String format: "artist/album/type"
        if (parts.size() >= 2) {
            QString artist = QUrl::fromPercentEncoding(parts[0].toUtf8());
            QString album = QUrl::fromPercentEncoding(parts[1].toUtf8());
            type = parts.size() > 2 ? parts[2] : "thumbnail";
            
            // Look up album ID from artist and album name
            albumId = m_databaseManager->getAlbumIdByArtistAndTitle(artist, album);
            if (albumId <= 0) {
                qWarning() << "AlbumArtImageProvider: Album not found:" << artist << "-" << album;
                return QPixmap();
            }
        } else {
            qWarning() << "AlbumArtImageProvider: Invalid album id:" << parts[0];
            return QPixmap();
        }
    }
    
    // Check pixmap cache first
    QString cacheKey = QString("album_%1_%2").arg(albumId).arg(type);
    QPixmap pixmap;
    if (QPixmapCache::find(cacheKey, &pixmap)) {
        if (size) {
            *size = pixmap.size();
        }
        return pixmap;
    }
    
    // Load from database or file
    if (type == "thumbnail") {
        // Load thumbnail from database
        QByteArray thumbnailData = m_databaseManager->getAlbumArtThumbnail(albumId);
        if (!thumbnailData.isEmpty()) {
            QImage image;
            if (image.loadFromData(thumbnailData)) {
                pixmap = QPixmap::fromImage(image);
                
                // Scale if requested size is different
                if (requestedSize.isValid() && requestedSize != pixmap.size()) {
                    pixmap = pixmap.scaled(requestedSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
                }
                
                // Cache the pixmap
                QPixmapCache::insert(cacheKey, pixmap);
                
                if (size) {
                    *size = pixmap.size();
                }
                return pixmap;
            }
        }
    } else if (type == "full") {
        // Load full image from file
        QString imagePath = m_databaseManager->getAlbumArtPath(albumId);
        if (!imagePath.isEmpty()) {
            pixmap.load(imagePath);
            
            if (!pixmap.isNull()) {
                // Scale if requested size is different
                if (requestedSize.isValid() && 
                    (requestedSize.width() < pixmap.width() || requestedSize.height() < pixmap.height())) {
                    pixmap = pixmap.scaled(requestedSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
                }
                
                // Cache the pixmap
                QPixmapCache::insert(cacheKey, pixmap);
                
                if (size) {
                    *size = pixmap.size();
                }
                return pixmap;
            }
        }
    }
    
    // Return empty pixmap if no art found
    if (size) {
        *size = QSize(0, 0);
    }
    return QPixmap();
}

} // namespace Mtoc