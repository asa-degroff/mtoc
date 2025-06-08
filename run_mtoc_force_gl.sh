#!/bin/bash

echo "=== Forcing hardware OpenGL for mtoc ==="

# Method 1: Force NVIDIA libraries
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json

# Method 2: Force Qt to use desktop OpenGL
export QT_OPENGL=desktop

# Method 3: Disable Qt's OpenGL buglist (which might force software rendering)
export QT_OPENGL_BUGLIST=0

# Method 4: Force specific Qt rendering
export QSG_RHI_BACKEND=opengl
export QSG_RHI_PREFER_SOFTWARE_RENDERER=0

# Method 5: Use native graphics system
export QT_XCB_NATIVE_PAINTING=1

# Clear debug log
echo "" > debug_log.txt

# Run with all optimizations
./build/mtoc_app "$@"