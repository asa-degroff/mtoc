#ifndef ALBUMARTIMAGEPROVIDER_H
#define ALBUMARTIMAGEPROVIDER_H

#include <QQuickAsyncImageProvider>
#include <QPixmapCache>
#include <QPointer>
#include <QThreadPool>
#include <QRunnable>

namespace Mtoc {

class LibraryManager;

class AlbumArtImageResponse : public QQuickImageResponse, public QRunnable
{
    Q_OBJECT
public:
    AlbumArtImageResponse(const QString &id, const QSize &requestedSize, LibraryManager* libraryManager);
    ~AlbumArtImageResponse() override;
    
    QQuickTextureFactory *textureFactory() const override;
    void run() override;
    
private:
    QString m_id;
    QSize m_requestedSize;
    QPointer<LibraryManager> m_libraryManager;
    QImage m_image;
    bool m_cancelled = false;
    
    void loadImage();
};

class AlbumArtImageProvider : public QQuickAsyncImageProvider
{
public:
    AlbumArtImageProvider(LibraryManager* libraryManager);
    
    QQuickImageResponse *requestImageResponse(const QString &id, const QSize &requestedSize) override;
    
private:
    QPointer<LibraryManager> m_libraryManager;
    QThreadPool* m_threadPool;
};

} // namespace Mtoc

#endif // ALBUMARTIMAGEPROVIDER_H