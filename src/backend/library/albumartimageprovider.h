#ifndef ALBUMARTIMAGEPROVIDER_H
#define ALBUMARTIMAGEPROVIDER_H

#include <QQuickImageProvider>
#include <QPixmapCache>
#include <QPointer>

namespace Mtoc {

class LibraryManager;

class AlbumArtImageProvider : public QQuickImageProvider
{
public:
    AlbumArtImageProvider(LibraryManager* libraryManager);
    
    QPixmap requestPixmap(const QString &id, QSize *size, const QSize &requestedSize) override;
    
private:
    QPointer<LibraryManager> m_libraryManager;
};

} // namespace Mtoc

#endif // ALBUMARTIMAGEPROVIDER_H