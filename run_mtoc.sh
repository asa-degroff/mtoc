#!/bin/bash

# Force Qt to use OpenGL for hardware acceleration
export QSG_RHI_BACKEND=opengl

# Optional: Force X11 platform if Wayland has issues with GPU acceleration
# Uncomment the line below if you still have performance issues
export QT_QPA_PLATFORM=xcb

# Optional: Enable threaded render loop for better performance
export QSG_RENDER_LOOP=threaded

# Optional: Disable vsync if you want maximum performance (may cause tearing)
# export QSG_RENDER_LOOP=basic

# Clear the debug log for fresh output
echo "" > debug_log.txt

# Run the application
./build/mtoc_app "$@"