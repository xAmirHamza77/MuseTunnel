# Muse Tunnel (SOCKS5 Proxy for Meta Muse)

A dedicated macOS proxy tunneling application built specifically for **Meta Muse** (`/Applications/Muse.app`, bundle ID `com.meta.endo`).

---

### **How It Works (Strict Per-App Isolation)**
* **Only Muse is proxied**: Routes all TCP and UDP traffic from `Muse.app` and its helper processes (`EndoCrashpadHandler`, `Autoupdate`) through your configured SOCKS5 proxy tunnel.
* **All other apps bypass the proxy**: Web browsers (Safari, Chrome), Terminal, Slack, and macOS system services connect **directly** to the internet with zero interference or slowdowns.
* **DNS Protection**: Domain queries made by Muse are resolved remotely through the proxy to prevent DNS leaks.

---

### **Configuration**
You can configure your SOCKS5 proxy directly in the **Muse Tunnel** app interface or by editing `config.json`:
* **Host**: `YOUR_PROXY_HOST`
* **Port**: `1080`
* **Protocol**: SOCKS5 (with TCP & UDP ASSOCIATE support)
* **Username**: `YOUR_USERNAME` (optional)
* **Password**: `YOUR_PASSWORD` (optional)

---

### **How to Use**

#### Option 1: Native macOS App (GUI)
1. Open **Muse Tunnel.app** from Spotlight, Finder, or `/Applications/Muse Tunnel.app`.
2. Enter your SOCKS5 proxy details and click **Save Settings**.
3. Click **"Start Tunnel & Route Muse"**.
4. macOS will ask for Touch ID or password once to initialize the isolated virtual network interface (`utun88`).
5. Click **"Relaunch Muse"** to reconnect any existing sockets through the proxy.
6. The dashboard displays live latency and connection status.

#### Option 2: Automatic Background Service (No Passwords Required)
To keep the tunnel running silently in the background so Muse always routes through the proxy without ever needing to open the app or enter a password:
```bash
sudo "/Applications/Muse Tunnel.app/Contents/Resources/install-daemon.sh"
```
To remove the background service anytime:
```bash
sudo "/Applications/Muse Tunnel.app/Contents/Resources/uninstall-daemon.sh"
```

#### Option 3: Terminal Command Line
A `muse-tunnel` command is available in `~/.local/bin/muse-tunnel`:
```bash
# Check status
muse-tunnel status

# Test proxy server connectivity
muse-tunnel test-proxy

# Relaunch Muse
muse-tunnel relaunch-muse
```
