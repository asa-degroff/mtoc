#ifndef FAVORITESVIRTUALPLAYLIST_H
#define FAVORITESVIRTUALPLAYLIST_H

#include "VirtualPlaylist.h"

namespace Mtoc {

class DatabaseManager;

class FavoritesVirtualPlaylist : public VirtualPlaylist
{
    Q_OBJECT

public:
    explicit FavoritesVirtualPlaylist(DatabaseManager* dbManager, QObject *parent = nullptr);
    ~FavoritesVirtualPlaylist();

    // Override loadAllTracks to load only favorites
    void loadAllTracks() override;

    // Refresh when a track's favorite status changes
    Q_INVOKABLE void refresh();

protected:
    // Override loadRange to use getFavoriteTracks instead of getAllTracks
    void loadRange(int startIndex, int count) override;
};

} // namespace Mtoc

#endif // FAVORITESVIRTUALPLAYLIST_H
