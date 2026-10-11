#!/bin/bash
# Uninstall Muse Tunnel LaunchDaemon
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo ./uninstall-daemon.sh)"
  exit 1
fi

PLIST_PATH="/Library/LaunchDaemons/com.local.musetunnel.plist"
if [ -f "$PLIST_PATH" ]; then
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    rm -f "$PLIST_PATH"
    echo "LaunchDaemon removed."
else
    echo "LaunchDaemon was not installed."
fi
pkill -f "sing-box.*musetunnel" 2>/dev/null || true
