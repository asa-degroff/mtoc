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
    
    // The id format is "albumId/type/size" or "artist/album/type/size" where type is "thumbnail" or "full" and size is optional
    QStringList parts = id.split('/');
    if (parts.isEmpty()) {
        qWarning() << "AlbumArtImageProvider: Invalid image id:" << id;
        return QPixmap();
    }
    
    int albumId = 0;
    QString type = "thumbnail";
    int targetSize = 0;  // 0 means use default or requested size
    
    // Try to parse as numeric album ID first
    bool ok;
    albumId = parts[0].toInt(&ok);
    if (ok && albumId > 0) {
        // Numeric ID format: "albumId" or "albumId/type" or "albumId/type/size"
        type = parts.size() > 1 ? parts[1] : "thumbnail";
        if (parts.size() > 2) {
            targetSize = parts[2].toInt(&ok);
            if (!ok) targetSize = 0;
        }
    } else {
        // String format: "artist/album/type" or "artist/album/type/size"
        if (parts.size() >= 2) {
            QString artist = QUrl::fromPercentEncoding(parts[0].toUtf8());
            QString album = QUrl::fromPercentEncoding(parts[1].toUtf8());
            type = parts.size() > 2 ? parts[2] : "thumbnail";
            if (parts.size() > 3) {
                targetSize = parts[3].toInt(&ok);
                if (!ok) targetSize = 0;
            }
            
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
    
    // Determine the actual size to use
    int actualSize = targetSize > 0 ? targetSize : (requestedSize.isValid() ? qMax(requestedSize.width(), requestedSize.height()) : 0);
    
    // Two-tier cache system: only cache thumbnail (256) and full size
    // For other sizes, we'll scale from the nearest cached version
    bool needsScaling = false;
    QString baseCacheKey;
    
    if (type == "thumbnail") {
        // Always use standard thumbnail size for caching
        baseCacheKey = QString("album_%1_thumbnail").arg(albumId);
        needsScaling = actualSize > 0 && actualSize != 256;
    } else {
        // Full size
        baseCacheKey = QString("album_%1_full").arg(albumId);
        needsScaling = actualSize > 0;
    }
    
    // For exact matches (thumbnail at 256 or full without specific size), check cache directly
    QString cacheKey = needsScaling ? QString() : baseCacheKey;
    
    QPixmap pixmap;
    if (!cacheKey.isEmpty() && QPixmapCache::find(cacheKey, &pixmap)) {
        if (size) {
            *size = pixmap.size();
        }
        return pixmap;
    }
    
    // Try to find base cached version for scaling
    if (needsScaling && QPixmapCache::find(baseCacheKey, &pixmap)) {
        // Scale from cached version
        pixmap = pixmap.scaled(actualSize, actualSize, Qt::KeepAspectRatio, 
                              type == "thumbnail" ? Qt::FastTransformation : Qt::SmoothTransformation);
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
                // Validate image before creating pixmap
                if (image.isNull() || image.width() <= 0 || image.height() <= 0) {
                    qWarning() << "AlbumArtImageProvider: Invalid image data for album:" << albumId;
                    if (size) {
                        *size = QSize(1, 1);
                    }
                    QPixmap emptyPixmap(1, 1);
                    emptyPixmap.fill(Qt::transparent);
                    return emptyPixmap;
                }
                
                pixmap = QPixmap::fromImage(image);
                
                // Validate pixmap
                if (pixmap.isNull()) {
                    qWarning() << "AlbumArtImageProvider: Failed to create pixmap for album:" << albumId;
                    if (size) {
                        *size = QSize(1, 1);
                    }
                    QPixmap emptyPixmap(1, 1);
                    emptyPixmap.fill(Qt::transparent);
                    return emptyPixmap;
                }
                
                // Cache the base pixmap first (at standard thumbnail size)
                QPixmapCache::insert(baseCacheKey, pixmap);
                
                // Scale if specific size is requested
                if (needsScaling) {
                    pixmap = pixmap.scaled(actualSize, actualSize, Qt::KeepAspectRatio, Qt::FastTransformation);
                }
                
                if (size) {
                    *size = pixmap.size();
                }
                return pixmap;
            } else {
                qWarning() << "AlbumArtImageProvider: Failed to load image data for album:" << albumId;
            }
        }
    } else if (type == "full") {
        // Load full image from file
        QString imagePath = databaseManager->getAlbumArtPath(albumId);
        if (!imagePath.isEmpty()) {
            pixmap.load(imagePath);
            
            if (!pixmap.isNull()) {
                // Cache the base full-size pixmap
                QPixmapCache::insert(baseCacheKey, pixmap);
                
                // Scale if specific size is requested
                if (needsScaling) {
                    pixmap = pixmap.scaled(actualSize, actualSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
                }
                
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