cmake_minimum_required(VERSION 3.16)

project(mtoc VERSION 2.2.4 LANGUAGES CXX)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(GNUInstallDirs)

# Enable qDebug output even in release builds
add_definitions(-DQT_MESSAGELOGCONTEXT -DQT_DEBUG)

find_package(Qt6 COMPONENTS Core Quick QuickEffects Qml Multimedia DBus Concurrent Widgets Sql REQUIRED)
# find_package(TagLib REQUIRED) # This failed, reverting to pkg-config

find_package(PkgConfig REQUIRED) # Ensure PkgConfig is found
# Use pkg-config for TagLib. This will define TAGLIB_LIBRARIES, TAGLIB_INCLUDE_DIRS, etc.
pkg_check_modules(TAGLIB REQUIRED taglib)
# Use pkg-config for GStreamer
pkg_check_modules(GSTREAMER REQUIRED gstreamer-1.0)

# Set Qt policies to suppress warnings and define behavior (Qt 6.5+)
if(Qt6_VERSION VERSION_GREATER_EQUAL "6.5.0")
    qt_policy(SET QTP0001 OLD) # Keep qrc:/ as the base for module resources unless overridden by URI
    # QTP0004 is only available in Qt 6.8+
    if(Qt6_VERSION VERSION_GREATER_EQUAL "6.8.0")
        qt_policy(SET QTP0004 OLD) # Do not require qmldir for subdirs not acting as modules
    endif()
endif()

set(CMAKE_AUTOUIC ON)

set(PROJECT_SOURCES
        src/main.cpp
        src/backend/systeminfo.h
        src/backend/systeminfo.cpp
        src/backend/library/librarymanager.h
        src/backend/library/librarymanager.cpp
        src/backend/library/albumartmanager.h
        src/backend/library/albumartmanager.cpp
        src/backend/library/albumartimageprovider.h
        src/backend/library/albumartimageprovider.cpp
        src/backend/library/track.h
        src/backend/library/track.cpp
        src/backend/library/album.h
        src/backend/library/album.cpp
        src/backend/library/artist.h
        src/backend/library/artist.cpp
        src/backend/library/albummodel.h
        src/backend/library/albummodel.cpp
        src/backend/library/trackmodel.h
        src/backend/library/trackmodel.cpp
        src/backend/database/databasemanager.h
        src/backend/database/databasemanager.cpp
        src/backend/playback/audioengine.h
        src/backend/playback/audioengine.cpp
        src/backend/playback/mediaplayer.h
        src/backend/playback/mediaplayer.cpp
        src/backend/playlist/playlistmanager.h
        src/backend/playlist/playlistmanager.cpp
        src/backend/playlist/VirtualTrackData.h
        src/backend/playlist/VirtualPlaylist.h
        src/backend/playlist/VirtualPlaylist.cpp
        src/backend/playlist/VirtualPlaylistModel.h
        src/backend/playlist/VirtualPlaylistModel.cpp
        src/backend/settings/settingsmanager.h
        src/backend/settings/settingsmanager.cpp
        src/backend/system/mprismanager.h
        src/backend/system/mprismanager.cpp
        src/backend/utility/metadataextractor.h
        src/backend/utility/metadataextractor.cpp
        app.qrc
)

qt_add_executable(mtoc_app
    ${PROJECT_SOURCES}
)

target_include_directories(mtoc_app PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src # For our own headers
    ${TAGLIB_INCLUDE_DIRS} # Add TagLib include directories
    ${GSTREAMER_INCLUDE_DIRS} # Add GStreamer include directories
)

target_link_libraries(mtoc_app
    PRIVATE
    Qt6::Core
    Qt6::Quick
    Qt6::QuickEffects
    Qt6::Qml
    Qt6::Multimedia
    Qt6::DBus
    Qt6::Concurrent
    Qt6::Widgets
    Qt6::Sql
    ${TAGLIB_LIBRARIES} # Link against TagLib libraries
    ${GSTREAMER_LIBRARIES} # Link against GStreamer libraries
)

qt_add_qml_module(mtoc
    URI mtoc
    VERSION 1.0
    QML_FILES
        src/qml/Main.qml
        src/qml/Components/AlbumArtPopup.qml
        src/qml/Components/BlurredBackground.qml
        src/qml/Components/CompactNowPlayingBar.qml
        src/qml/Components/HorizontalAlbumBrowser.qml
        src/qml/Components/LyricsPopup.qml
        src/qml/Components/LyricsView.qml
        src/qml/Components/PlaybackControls.qml
        src/qml/Components/QueueActionDialog.qml
        src/qml/Components/QueueListView.qml
        src/qml/Components/QueuePopup.qml
        src/qml/Components/ResizeHandler.qml
        src/qml/Components/SearchBar.qml
        src/qml/Components/StyledMenu.qml
        src/qml/Components/StyledMenuItem.qml
        src/qml/Components/StyledMenuSeparator.qml
        src/qml/Components/ThumbnailGridDelegate.qml
        src/qml/Views/LibraryPane.qml
        src/qml/Views/NowPlayingPane.qml
        src/qml/Views/PlaylistView.qml
        src/qml/Views/SettingsWindow.qml
        src/qml/Theme.qml
)

install(TARGETS mtoc_app
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

# Install desktop file for Linux desktop integration
if(UNIX AND NOT APPLE)
    install(FILES mtoc.desktop
        DESTINATION ${CMAKE_INSTALL_PREFIX}/share/applications
    )
    
    # Install PNG icons in multiple sizes
    install(FILES resources/icons/mtoc-icon-48.png
        DESTINATION ${CMAKE_INSTALL_PREFIX}/share/icons/hicolor/48x48/apps
        RENAME org._3fz.mtoc.png
    )

    install(FILES resources/icons/mtoc-icon-64.png
        DESTINATION ${CMAKE_INSTALL_PREFIX}/share/icons/hicolor/64x64/apps
        RENAME org._3fz.mtoc.png
    )
    
    install(FILES resources/icons/mtoc-icon-128.png
        DESTINATION ${CMAKE_INSTALL_PREFIX}/share/icons/hicolor/128x128/apps
        RENAME org._3fz.mtoc.png
    )
    
    install(FILES resources/icons/mtoc-icon-256.png
        DESTINATION ${CMAKE_INSTALL_PREFIX}/share/icons/hicolor/256x256/apps
        RENAME org._3fz.mtoc.png
    )
    
    install(FILES resources/icons/mtoc-icon-512.png
        DESTINATION ${CMAKE_INSTALL_PREFIX}/share/icons/hicolor/512x512/apps
        RENAME org._3fz.mtoc.png
    )

    # Install 128x128 PNG in pixmaps for legacy support
    install(FILES resources/icons/mtoc-icon-128.png
        DESTINATION ${CMAKE_INSTALL_PREFIX}/share/pixmaps
        RENAME mtoc.png
    )
    
    # Install metainfo file
    install(FILES org._3fz.mtoc.metainfo.xml
        DESTINATION ${CMAKE_INSTALL_PREFIX}/share/metainfo
    )
endif()