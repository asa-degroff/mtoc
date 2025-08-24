#include "albumartimageprovider.h"
#include "librarymanager.h"
#include "../settings/settingsmanager.h"
#include <QDebug>
#include <QPixmap>
#include <QImage>
#include <QUrl>
#include <QMutex>
#include <QMutexLocker>
#include <QThread>

namespace Mtoc {

// AlbumArtImageResponse implementation
AlbumArtImageResponse::AlbumArtImageResponse(const QString &id, const QSize &requestedSize, LibraryManager* libraryManager)
    : m_id(id)
    , m_requestedSize(requestedSize)
    , m_libraryManager(libraryManager)
{
    setAutoDelete(false);
}

AlbumArtImageResponse::~AlbumArtImageResponse()
{
}

QQuickTextureFactory *AlbumArtImageResponse::textureFactory() const
{
    return QQuickTextureFactory::textureFactoryForImage(m_image);
}

void AlbumArtImageResponse::run()
{
    if (m_cancelled) {
        emit finished();
        return;
    }
    
    loadImage();
    
    if (!m_cancelled) {
        emit finished();
    }
}

void AlbumArtImageResponse::loadImage()
{
    // Check if LibraryManager is still valid
    if (m_libraryManager.isNull()) {
        qWarning() << "AlbumArtImageProvider: LibraryManager is null, cannot load album art for:" << m_id;
        m_image = QImage(1, 1, QImage::Format_ARGB32);
        m_image.fill(Qt::transparent);
        return;
    }
    
    // Get database manager through LibraryManager
    DatabaseManager* databaseManager = m_libraryManager->databaseManager();
    if (!databaseManager) {
        qWarning() << "AlbumArtImageProvider: DatabaseManager is null, cannot load album art for:" << m_id;
        m_image = QImage(1, 1, QImage::Format_ARGB32);
        m_image.fill(Qt::transparent);
        return;
    }
    
    // The id format is "albumId/type/size" or "artist/album/type/size" where type is "thumbnail" or "full" and size is optional
    QStringList parts = m_id.split('/');
    if (parts.isEmpty()) {
        qWarning() << "AlbumArtImageProvider: Invalid image id:" << m_id;
        m_image = QImage(1, 1, QImage::Format_ARGB32);
        m_image.fill(Qt::transparent);
        return;
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
                m_image = QImage(1, 1, QImage::Format_ARGB32);
                m_image.fill(Qt::transparent);
                return;
            }
        } else {
            qWarning() << "AlbumArtImageProvider: Invalid album id:" << parts[0];
            m_image = QImage(1, 1, QImage::Format_ARGB32);
            m_image.fill(Qt::transparent);
            return;
        }
    }
    
    // Determine the actual size to use
    int actualSize = targetSize > 0 ? targetSize : (m_requestedSize.isValid() ? qMax(m_requestedSize.width(), m_requestedSize.height()) : 0);

    // Two-tier cache system: only cache thumbnail and full size
    // For other sizes, we'll scale from the nearest cached version
    bool needsScaling = false;
    QString baseCacheKey;
    
    if (type == "thumbnail") {
        // Use configured thumbnail size from settings
        int configuredSize = SettingsManager::instance()->thumbnailScale() * 2; // Convert to pixels
        baseCacheKey = QString("album_%1_thumbnail_%2").arg(albumId).arg(configuredSize);
        needsScaling = actualSize > 0 && actualSize != configuredSize;
    } else {
        // Full size
        baseCacheKey = QString("album_%1_full").arg(albumId);
        needsScaling = actualSize > 0;
    }
    
    // For exact matches (thumbnail at 256 or full without specific size), check cache directly
    QString cacheKey = needsScaling ? QString("%1_%2").arg(baseCacheKey).arg(actualSize) : baseCacheKey;
    
    QPixmap pixmap;
    // First check if we have the exact size cached
    if (QPixmapCache::find(cacheKey, &pixmap)) {
        m_image = pixmap.toImage();
        return;
    }
    
    // Try to find base cached version for scaling
    if (needsScaling && QPixmapCache::find(baseCacheKey, &pixmap)) {
        // Scale from cached version
        m_image = pixmap.scaled(actualSize, actualSize, Qt::KeepAspectRatio, 
                              type == "thumbnail" ? Qt::FastTransformation : Qt::SmoothTransformation).toImage();
        // Cache the scaled version too
        QPixmapCache::insert(cacheKey, QPixmap::fromImage(m_image));
        return;
    }
    
    // Load from database or file
    if (type == "thumbnail") {
        // Load thumbnail from database
        QByteArray thumbnailData = databaseManager->getAlbumArtThumbnail(albumId);
        if (!thumbnailData.isEmpty()) {
            if (m_image.loadFromData(thumbnailData)) {
                // Validate image
                if (m_image.isNull() || m_image.width() <= 0 || m_image.height() <= 0) {
                    qWarning() << "AlbumArtImageProvider: Invalid image data for album:" << albumId;
                    m_image = QImage(1, 1, QImage::Format_ARGB32);
                    m_image.fill(Qt::transparent);
                    return;
                }
                
                // Cache the base pixmap first (at standard thumbnail size)
                QPixmapCache::insert(baseCacheKey, QPixmap::fromImage(m_image));
                
                // Convert to more efficient format for thumbnails
                if (m_image.format() != QImage::Format_RGB888 && m_image.format() != QImage::Format_RGB32) {
                    // Convert to RGB format for better performance (no alpha channel needed for album art)
                    m_image = m_image.convertToFormat(QImage::Format_RGB888);
                }
                
                // Scale if specific size is requested
                if (needsScaling) {
                    m_image = m_image.scaled(actualSize, actualSize, Qt::KeepAspectRatio, Qt::FastTransformation);
                }
                
                return;
            } else {
                qWarning() << "AlbumArtImageProvider: Failed to load image data for album:" << albumId;
            }
        }
    } else if (type == "full") {
        // Load full image from file
        QString imagePath = databaseManager->getAlbumArtPath(albumId);
        if (!imagePath.isEmpty()) {
            if (m_image.load(imagePath)) {
                // Cache the base full-size pixmap
                QPixmapCache::insert(baseCacheKey, QPixmap::fromImage(m_image));
                
                // Scale if specific size is requested
                if (needsScaling) {
                    m_image = m_image.scaled(actualSize, actualSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
                }
                
                return;
            }
        }
    }
    
    // Return empty image if no art found
    m_image = QImage(1, 1, QImage::Format_ARGB32);
    m_image.fill(Qt::transparent);
}

// AlbumArtImageProvider implementation
AlbumArtImageProvider::AlbumArtImageProvider(LibraryManager* libraryManager)
    : QQuickAsyncImageProvider()
    , m_libraryManager(libraryManager)
{
    m_threadPool = new QThreadPool(this);
    // Set thread pool size based on CPU cores with better scaling
    int idealThreadCount = QThread::idealThreadCount();
    // Use more threads for better parallel loading, especially during fast scrolling
    int threadCount = qBound(4, idealThreadCount, 8);  // Increased from 2-4 to 4-8
    m_threadPool->setMaxThreadCount(threadCount);
    m_threadPool->setExpiryTimeout(30000); // 30 seconds
    
    // Connect to thumbnail scale changes to clear cache
    connect(SettingsManager::instance(), &SettingsManager::thumbnailScaleChanged,
            this, []() {
                // Clear pixmap cache when thumbnail size changes
                QPixmapCache::clear();
                qDebug() << "Cleared pixmap cache due to thumbnail scale change";
            });
    
    // Set higher priority for image loading threads
    m_threadPool->setThreadPriority(QThread::HighPriority);
}

QQuickImageResponse *AlbumArtImageProvider::requestImageResponse(const QString &id, const QSize &requestedSize)
{
    AlbumArtImageResponse *response = new AlbumArtImageResponse(id, requestedSize, m_libraryManager);
    m_threadPool->start(response);
    return response;
}

} // namespace Mtoc