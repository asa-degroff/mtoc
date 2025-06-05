#include "albumartimageprovider.h"
#include "librarymanager.h"
#include <QDebug>
#include <QPixmap>
#include <QImage>
#include <QUrl>
#include <QMutex>
#include <QMutexLocker>

namespace Mtoc {

AlbumArtImageProvider::AlbumArtImageProvider(LibraryManager* libraryManager)
    : QQuickImageProvider(QQuickImageProvider::Pixmap)
    , m_libraryManager(libraryManager)
{
}

QPixmap AlbumArtImageProvider::requestPixmap(const QString &id, QSize *size, const QSize &requestedSize)
{
    // Add protection against concurrent access and invalid requests
    static QMutex requestMutex;
    QMutexLocker locker(&requestMutex);
    
    // qDebug() << "[AlbumArtImageProvider::requestPixmap] Request for id:" << id;
    
    // Check if LibraryManager is still valid
    if (m_libraryManager.isNull()) {
        qWarning() << "AlbumArtImageProvider: LibraryManager is null, cannot load album art for:" << id;
        if (size) {
            *size = QSize(1, 1);
        }
        QPixmap emptyPixmap(1, 1);
        emptyPixmap.fill(Qt::transparent);
        return emptyPixmap;
    }
    
    // Get database manager through LibraryManager
    DatabaseManager* databaseManager = m_libraryManager->databaseManager();
    if (!databaseManager) {
        qWarning() << "AlbumArtImageProvider: DatabaseManager is null, cannot load album art for:" << id;
        if (size) {
            *size = QSize(0, 0);
        }
        return QPixmap();
    }
    
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
            albumId = databaseManager->getAlbumIdByArtistAndTitle(artist, album);
            if (albumId <= 0) {
                qWarning() << "AlbumArtImageProvider: Album not found:" << artist << "-" << album;
                // Return a valid empty pixmap instead of default constructed one
                if (size) {
                    *size = QSize(1, 1);
                }
                QPixmap emptyPixmap(1, 1);
                emptyPixmap.fill(Qt::transparent);
                return emptyPixmap;
            }
        } else {
            qWarning() << "AlbumArtImageProvider: Invalid album id:" << parts[0];
            if (size) {
                *size = QSize(1, 1);
            }
            QPixmap emptyPixmap(1, 1);
            emptyPixmap.fill(Qt::transparent);
            return emptyPixmap;
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
        QByteArray thumbnailData = databaseManager->getAlbumArtThumbnail(albumId);
        if (!thumbnailData.isEmpty()) {
            QImage image;
            if (image.loadFromData(thumbnailData)) {
                pixmap = QPixmap::fromImage(image);
                
                // Scale if requested size is different - use faster transformation
                if (requestedSize.isValid() && requestedSize != pixmap.size()) {
                    pixmap = pixmap.scaled(requestedSize, Qt::KeepAspectRatio, Qt::FastTransformation);
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
        QString imagePath = databaseManager->getAlbumArtPath(albumId);
        if (!imagePath.isEmpty()) {
            pixmap.load(imagePath);
            
            if (!pixmap.isNull()) {
                // Scale if requested size is different - use faster transformation
                if (requestedSize.isValid() && 
                    (requestedSize.width() < pixmap.width() || requestedSize.height() < pixmap.height())) {
                    pixmap = pixmap.scaled(requestedSize, Qt::KeepAspectRatio, Qt::FastTransformation);
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
    // qDebug() << "[AlbumArtImageProvider::requestPixmap] No art found for id:" << id;
    if (size) {
        *size = QSize(1, 1);
    }
    QPixmap emptyPixmap(1, 1);
    emptyPixmap.fill(Qt::transparent);
    // qDebug() << "[AlbumArtImageProvider::requestPixmap] Returning empty pixmap for id:" << id;
    return emptyPixmap;
}

} // namespace Mtoc