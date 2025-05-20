# Created by and for Qt Creator This file was created for editing the project sources only.
# You may attempt to use it for building too, by modifying this file here.

#TARGET = mtoc

QT = core gui widgets

HEADERS = \
   $$PWD/src/backend/library/album.h \
   $$PWD/src/backend/library/albummodel.h \
   $$PWD/src/backend/library/artist.h \
   $$PWD/src/backend/library/librarymanager.h \
   $$PWD/src/backend/library/track.h \
   $$PWD/src/backend/library/trackmodel.h \
   $$PWD/src/backend/playback/mediaplayer.h \
   $$PWD/src/backend/playback/playlist.h \
   $$PWD/src/backend/system/mprismanager.h \
   $$PWD/src/backend/utility/metadataextractor.h

SOURCES = \
   $$PWD/src/backend/library/album.cpp \
   $$PWD/src/backend/library/albummodel.cpp \
   $$PWD/src/backend/library/artist.cpp \
   $$PWD/src/backend/library/librarymanager.cpp \
   $$PWD/src/backend/library/track.cpp \
   $$PWD/src/backend/library/trackmodel.cpp \
   $$PWD/src/backend/playback/mediaplayer.cpp \
   $$PWD/src/backend/playback/playlist.cpp \
   $$PWD/src/backend/system/mprismanager.cpp \
   $$PWD/src/backend/utility/metadataextractor.cpp \
   $$PWD/src/main.cpp

INCLUDEPATH = \
    $$PWD/src/backend/library \
    $$PWD/src/backend/playback \
    $$PWD/src/backend/system \
    $$PWD/src/backend/utility

#DEFINES = 

