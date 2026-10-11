#!/bin/bash
# Install Muse Tunnel as a background LaunchDaemon
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo ./install-daemon.sh)"
  exit 1
fi

PLIST_PATH="/Library/LaunchDaemons/com.local.musetunnel.plist"
SINGBOX_BIN="/opt/homebrew/bin/sing-box"
if [ ! -f "$SINGBOX_BIN" ]; then
    SINGBOX_BIN="/Applications/Muse Tunnel.app/Contents/Resources/sing-box"
fi

CONFIG_PATH="/Applications/Muse Tunnel.app/Contents/Resources/config.json"
if [ ! -f "$CONFIG_PATH" ]; then
    CONFIG_PATH="/Users/amir/Documents/antigravity/friendly-bose/Muse Tunnel.app/Contents/Resources/config.json"
fi

cat << EOF > "$PLIST_PATH"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.local.musetunnel</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SINGBOX_BIN</string>
        <string>run</string>
        <string>-c</string>
        <string>$CONFIG_PATH</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/musetunnel_daemon.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/musetunnel_daemon.err</string>
</dict>
</plist>
EOF

chmod 644 "$PLIST_PATH"
chown root:wheel "$PLIST_PATH"

launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"

echo "Muse Tunnel LaunchDaemon successfully installed and running!"
