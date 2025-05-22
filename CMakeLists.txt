cmake_minimum_required(VERSION 3.16)

project(mtoc VERSION 0.1 LANGUAGES CXX)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 COMPONENTS Core Quick Qml Multimedia DBus Concurrent Widgets REQUIRED)
# find_package(TagLib REQUIRED) # This failed, reverting to pkg-config

find_package(PkgConfig REQUIRED) # Ensure PkgConfig is found
# Use pkg-config for TagLib. This will define TAGLIB_LIBRARIES, TAGLIB_INCLUDE_DIRS, etc.
pkg_check_modules(TAGLIB REQUIRED taglib)

# Set Qt policies to suppress warnings and define behavior
qt_policy(SET QTP0001 OLD) # Keep qrc:/ as the base for module resources unless overridden by URI
qt_policy(SET QTP0004 OLD) # Do not require qmldir for subdirs not acting as modules

set(CMAKE_AUTOUIC ON)

set(PROJECT_SOURCES
        src/main.cpp
        src/backend/systeminfo.h
        src/backend/systeminfo.cpp
        src/backend/library/librarymanager.h
        src/backend/library/librarymanager.cpp
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
        src/backend/playback/mediaplayer.h
        src/backend/playback/mediaplayer.cpp
        src/backend/playback/playlist.h
        src/backend/playback/playlist.cpp
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
)

target_link_libraries(mtoc_app
    PRIVATE
    Qt6::Core
    Qt6::Quick
    Qt6::Qml
    Qt6::Multimedia
    Qt6::DBus
    Qt6::Concurrent
    Qt6::Widgets
    ${TAGLIB_LIBRARIES} # Link against TagLib libraries
)

qt_add_qml_module(mtoc
    URI mtoc
    VERSION 1.0
    QML_FILES
        src/qml/Main.qml
        src/qml/Components/AlbumArtView.qml
        src/qml/Components/BlurredBackground.qml
        src/qml/Components/PlaybackControls.qml
        src/qml/Components/ThumbnailGridDelegate.qml
        src/qml/Views/LibraryPane.qml
        src/qml/Views/NowPlayingPane.qml
        src/qml/Views/PlaylistView.qml
        src/qml/Constants.qml
        src/qml/Styles.qml
)

install(TARGETS mtoc_app
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)