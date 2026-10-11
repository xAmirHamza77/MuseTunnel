#!/bin/bash
# Build script for Muse Tunnel
set -e

APP_NAME="Muse Tunnel"
APP_DIR="${APP_NAME}.app"

echo "==> Building ${APP_NAME}..."

# Ensure directories exist
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# Compile Swift code
echo "==> Compiling Swift source..."
swiftc -O src/main.swift -o "${APP_DIR}/Contents/MacOS/MuseTunnel"

# Make helper scripts executable
chmod +x "${APP_DIR}/Contents/Resources/tunnel-ctl"
chmod +x "${APP_DIR}/Contents/Resources/install-daemon.sh"
chmod +x "${APP_DIR}/Contents/Resources/uninstall-daemon.sh"

# Copy sing-box if available from Homebrew and not present
if [ ! -f "${APP_DIR}/Contents/Resources/sing-box" ]; then
    if [ -x "/opt/homebrew/bin/sing-box" ]; then
        echo "==> Bundling sing-box from /opt/homebrew/bin/sing-box..."
        cp "/opt/homebrew/bin/sing-box" "${APP_DIR}/Contents/Resources/sing-box"
        chmod +x "${APP_DIR}/Contents/Resources/sing-box"
    elif [ -x "/usr/local/bin/sing-box" ]; then
        echo "==> Bundling sing-box from /usr/local/bin/sing-box..."
        cp "/usr/local/bin/sing-box" "${APP_DIR}/Contents/Resources/sing-box"
        chmod +x "${APP_DIR}/Contents/Resources/sing-box"
    else
        echo "Notice: sing-box binary not found. Install it with: brew install sing-box"
    fi
fi

echo "==> Build complete: ${APP_DIR}"
