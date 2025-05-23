#ifndef ALBUMARTIMAGEPROVIDER_H
#define ALBUMARTIMAGEPROVIDER_H

#include <QQuickImageProvider>
#include <QPixmapCache>
#include "../database/databasemanager.h"

namespace Mtoc {

class AlbumArtImageProvider : public QQuickImageProvider
{
public:
    AlbumArtImageProvider(DatabaseManager* dbManager);
    
    QPixmap requestPixmap(const QString &id, QSize *size, const QSize &requestedSize) override;
    
private:
    DatabaseManager* m_databaseManager;
};

} // namespace Mtoc

#endif // ALBUMARTIMAGEPROVIDER_H