#include "albumartmanager.h"
#include "../settings/settingsmanager.h"
#include <QCryptographicHash>
#include <QDir>
#include <QStandardPaths>
#include <QImageReader>
#include <QImageWriter>
#include <QBuffer>
#include <QDebug>
#include <QRegularExpression>

namespace Mtoc {

AlbumArtManager::AlbumArtManager(QObject *parent)
    : QObject(parent)
{
}

AlbumArtManager::ProcessedAlbumArt AlbumArtManager::processAlbumArt(
    const QByteArray& rawData, 
    const QString& albumName, 
    const QString& artistName,
    const QString& mimeType)
{
    ProcessedAlbumArt result;
    result.success = false;
    
    if (rawData.isEmpty()) {
        result.error = "Empty album art data";
        return result;
    }
    
    // Calculate hash for deduplication
    result.hash = calculateHash(rawData);
    
    // Detect image format
    QString format = mimeType;
    if (format.isEmpty()) {
        format = detectImageFormat(rawData);
    }
    
    // Extract format name from MIME type
    QString formatName = "jpeg"; // default
    if (format.contains("png", Qt::CaseInsensitive)) {
        formatName = "png";
    } else if (format.contains("jpeg", Qt::CaseInsensitive) || 
               format.contains("jpg", Qt::CaseInsensitive)) {
        formatName = "jpeg";
    }
    
    // Load image from raw data
    QImage fullImage;
    if (!fullImage.loadFromData(rawData)) {
        result.error = "Failed to load image from data";
        return result;
    }
    
    result.originalSize = fullImage.size();
    result.format = formatName;
    result.fileSize = rawData.size();
    
    // Scale down if too large
    if (fullImage.width() > MAX_FULL_SIZE || fullImage.height() > MAX_FULL_SIZE) {
        fullImage = fullImage.scaled(MAX_FULL_SIZE, MAX_FULL_SIZE, 
                                     Qt::KeepAspectRatio, 
                                     Qt::SmoothTransformation);
    }
    
    // Create thumbnail
    QImage thumbnail = createThumbnail(fullImage);
    
    // Convert thumbnail to byte array
    QBuffer buffer;
    buffer.open(QIODevice::WriteOnly);
    if (!thumbnail.save(&buffer, formatName.toUtf8().constData(), 85)) {
        result.error = "Failed to create thumbnail";
        return result;
    }
    result.thumbnailData = buffer.buffer();
    
    // Generate filename and save full image
    QString filename = generateAlbumArtFilename(albumName, artistName, result.hash);
    QString fullPath = getAlbumArtDirectory() + "/" + filename;
    
    // Ensure directory exists
    QDir dir(getAlbumArtDirectory());
    if (!dir.exists()) {
        dir.mkpath(".");
    }
    
    // Save full image
    if (!saveFullImage(fullImage, fullPath, formatName)) {
        result.error = "Failed to save full image";
        return result;
    }
    
    result.fullImagePath = fullPath;
    result.success = true;
    
    emit albumArtProcessed(albumName, true);
    return result;
}

QString AlbumArtManager::getAlbumArtDirectory() const
{
    QString dataPath = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    return dataPath + "/albumart";
}

QString AlbumArtManager::generateAlbumArtFilename(const QString& albumName, 
                                                 const QString& artistName, 
                                                 const QString& hash) const
{
    QString safeName = sanitizeFilename(artistName + "_" + albumName);
    if (safeName.length() > 50) {
        safeName = safeName.left(50);
    }
    return QString("%1_%2.jpg").arg(safeName).arg(hash.left(8));
}

QString AlbumArtManager::calculateHash(const QByteArray& data) const
{
    QCryptographicHash hash(QCryptographicHash::Sha1);
    hash.addData(data);
    return hash.result().toHex();
}

int AlbumArtManager::getThumbnailSize() const
{
    // Get the thumbnail scale from settings (100, 150, or 200)
    int scale = SettingsManager::instance()->thumbnailScale();
    // Convert percentage to pixel size
    return scale * 2;  // 100% = 200px, 150% = 300px, 200% = 400px
}

QImage AlbumArtManager::createThumbnail(const QImage& source) const
{
    return createThumbnail(source, getThumbnailSize());
}

QImage AlbumArtManager::createThumbnail(const QImage& source, int size) const
{
    return source.scaled(size, size, 
                        Qt::KeepAspectRatio, 
                        Qt::SmoothTransformation);
}

bool AlbumArtManager::saveFullImage(const QImage& image, const QString& path, const QString& format) const
{
    // Check if file already exists (deduplication)
    if (QFile::exists(path)) {
        return true;
    }
    
    QImageWriter writer(path);
    writer.setFormat(format.toUtf8());
    writer.setQuality(90);
    
    if (!writer.write(image)) {
        qWarning() << "Failed to save album art:" << writer.errorString();
        return false;
    }
    
    return true;
}

QString AlbumArtManager::sanitizeFilename(const QString& name) const
{
    QString safe = name;
    // Remove invalid filename characters
    safe.replace(QRegularExpression("[<>:\"/\\\\|?*]"), "_");
    // Replace spaces with underscores
    safe.replace(" ", "_");
    // Remove consecutive underscores
    safe.replace(QRegularExpression("_+"), "_");
    return safe;
}

QString AlbumArtManager::detectImageFormat(const QByteArray& data) const
{
    QBuffer buffer;
    buffer.setData(data);
    buffer.open(QIODevice::ReadOnly);
    
    QImageReader reader(&buffer);
    QString format = reader.format();
    
    if (format == "jpeg" || format == "jpg") {
        return "image/jpeg";
    } else if (format == "png") {
        return "image/png";
    } else if (format == "gif") {
        return "image/gif";
    } else if (format == "bmp") {
        return "image/bmp";
    }
    
    // Default to JPEG if unknown
    return "image/jpeg";
}

} // namespace Mtoc