#!/bin/bash

echo "=== Forcing NVIDIA GPU for mtoc ==="

# Force NVIDIA driver for OpenGL/EGL
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json

# Force Qt to use OpenGL backend
export QSG_RHI_BACKEND=opengl

# Use GLX integration for better NVIDIA compatibility
export QT_XCB_GL_INTEGRATION=xcb_glx

# Enable threaded render loop
export QSG_RENDER_LOOP=threaded

# Optional: Force X11 if Wayland issues persist
# export QT_QPA_PLATFORM=xcb

# Debug: Show which GPU is being used
echo "Checking GPU usage..."
glxinfo 2>/dev/null | grep "OpenGL renderer" || echo "glxinfo not available"

# Clear the debug log for fresh output
echo "" > debug_log.txt

# Run the application
echo "Starting mtoc with hardware acceleration..."
./build/mtoc_app "$@"