#include "FavoritesVirtualPlaylist.h"
#include "../database/databasemanager.h"
#include "VirtualTrackData.h"
#include <QDebug>
#include <QtConcurrent>
#include <QThread>
#include <QSqlDatabase>

namespace Mtoc {

FavoritesVirtualPlaylist::FavoritesVirtualPlaylist(DatabaseManager* dbManager, QObject *parent)
    : VirtualPlaylist(dbManager, parent)
{
}

FavoritesVirtualPlaylist::~FavoritesVirtualPlaylist()
{
}

void FavoritesVirtualPlaylist::loadAllTracks()
{
    if (m_isLoading) {
        qDebug() << "[FavoritesVirtualPlaylist] Already loading, skipping request";
        return;
    }

    m_isLoading = true;
    emit loadingStarted();

    // Get total count of favorites
    m_totalTrackCount = m_dbManager->getFavoriteTracksCount();

    if (m_totalTrackCount == 0) {
        m_isLoading = false;
        emit loadingFinished();
        return;
    }

    // Pre-allocate vector with nullptrs
    {
        QMutexLocker locker(&m_trackMutex);
        // Delete existing tracks
        for (auto* track : m_tracks) {
            delete track;
        }
        m_tracks.clear();
        m_tracks.resize(m_totalTrackCount, nullptr);
        m_loadedRanges.clear();
        m_totalDuration = 0;
    }

    // Start loading the first chunk immediately
    loadRange(0, m_bufferSize);
}

void FavoritesVirtualPlaylist::refresh()
{
    qDebug() << "[FavoritesVirtualPlaylist] Refreshing favorites playlist";
    loadAllTracks();
}

void FavoritesVirtualPlaylist::loadRange(int startIndex, int count)
{
    if (m_loadFuture.isRunning()) {
        // Cancel previous load if still running
        m_loadFuture.cancel();
        m_loadFuture.waitForFinished();
    }

    // Load favorite tracks in background
    m_loadFuture = QtConcurrent::run([this, startIndex, count]() {
        // Store thread ID for cleanup
        QString connectionName = QString("MtocThread_%1").arg(quintptr(QThread::currentThreadId()));

        // Use getFavoriteTracks instead of getAllTracks
        QVariantList tracks = m_dbManager->getFavoriteTracks(count, startIndex);

        // Clean up thread connection
        if (QSqlDatabase::contains(connectionName)) {
            QSqlDatabase::removeDatabase(connectionName);
        }

        if (tracks.isEmpty()) {
            qWarning() << "[FavoritesVirtualPlaylist] Failed to load favorite tracks at range" << startIndex << "count" << count;
            return;
        }

        {
            QMutexLocker locker(&m_trackMutex);

            int index = startIndex;
            for (const QVariant& trackVariant : tracks) {
                if (index >= m_tracks.size()) {
                    break;
                }

                QVariantMap trackMap = trackVariant.toMap();
                auto* trackData = new VirtualTrackData(VirtualTrackData::fromVariantMap(trackMap));

                // Delete existing track if any
                delete m_tracks[index];
                m_tracks[index] = trackData;
                m_totalDuration += trackData->duration;

                ++index;
            }

            updateLoadedRanges(startIndex, startIndex + tracks.size() - 1);
        }

        emit rangeLoaded(startIndex, startIndex + tracks.size() - 1);
        emit loadingProgress(loadedTrackCount(), m_totalTrackCount);

        if (isFullyLoaded()) {
            m_isLoading = false;
            emit loadingFinished();
        }
    });
}

} // namespace Mtoc
