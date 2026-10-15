import SwiftUI
import AppKit

// MARK: - App State & Controller
class TunnelController: ObservableObject {
    @Published var isTunnelActive: Bool = false
    @Published var isMuseRunning: Bool = false
    @Published var musePID: Int32 = 0
    @Published var uploadSpeed: String = "0 B/s"
    @Published var downloadSpeed: String = "0 B/s"
    @Published var proxyStatusMessage: String = "Ready"
    @Published var latencyText: String = "-- ms"
    @Published var recentConnections: [String] = []
    @Published var logOutput: String = ""
    @Published var isTestingProxy: Bool = false
    @Published var isClearingData: Bool = false
    
    // Proxy Configuration Fields
    @Published var proxyServer: String = ""
    @Published var proxyPort: String = "1080"
    @Published var proxyUsername: String = ""
    @Published var proxyPassword: String = ""
    @Published var showSettings: Bool = false
    
    private var timer: Timer?
    
    var userConfigURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/muse-tunnel/config.json")
    }
    
    var scriptPath: String {
        if let res = Bundle.main.resourcePath {
            let path = "\(res)/tunnel-ctl"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        let fallback = "/Applications/Muse Tunnel.app/Contents/Resources/tunnel-ctl"
        if FileManager.default.isExecutableFile(atPath: fallback) {
            return fallback
        }
        return "./Muse Tunnel.app/Contents/Resources/tunnel-ctl"
    }
    
    init() {
        loadConfig()
        checkStatus()
        startMonitoring()
    }
    
    func loadConfig() {
        var sourceURL = userConfigURL
        if !FileManager.default.fileExists(atPath: sourceURL.path) {
            if let res = Bundle.main.resourcePath {
                let bundleConfig = URL(fileURLWithPath: "\(res)/config.json")
                if FileManager.default.fileExists(atPath: bundleConfig.path) {
                    sourceURL = bundleConfig
                }
            }
        }
        
        guard let data = try? Data(contentsOf: sourceURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let outbounds = json["outbounds"] as? [[String: Any]] else {
            return
        }
        
        for ob in outbounds {
            if (ob["type"] as? String) == "socks" {
                let server = ob["server"] as? String ?? ""
                let port = ob["server_port"] as? Int ?? 1080
                let user = ob["username"] as? String ?? ""
                let pass = ob["password"] as? String ?? ""
                
                if server != "YOUR_PROXY_HOST" {
                    self.proxyServer = server
                }
                self.proxyPort = "\(port)"
                if user != "YOUR_PROXY_USERNAME" {
                    self.proxyUsername = user
                }
                if pass != "YOUR_PROXY_PASSWORD" {
                    self.proxyPassword = pass
                }
                break
            }
        }
    }
    
    func saveConfig() {
        let dir = userConfigURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        // Load template
        var baseJson: [String: Any] = [:]
        var templateURL: URL? = nil
        if let res = Bundle.main.resourcePath {
            let bURL = URL(fileURLWithPath: "\(res)/config.json")
            if FileManager.default.fileExists(atPath: bURL.path) {
                templateURL = bURL
            }
        }
        if templateURL == nil && FileManager.default.fileExists(atPath: userConfigURL.path) {
            templateURL = userConfigURL
        }
        
        if let tURL = templateURL,
           let data = try? Data(contentsOf: tURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            baseJson = json
        }
        
        var outbounds = baseJson["outbounds"] as? [[String: Any]] ?? []
        for i in 0..<outbounds.count {
            if (outbounds[i]["type"] as? String) == "socks" {
                outbounds[i]["server"] = proxyServer.trimmingCharacters(in: .whitespacesAndNewlines)
                outbounds[i]["server_port"] = Int(proxyPort.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1080
                outbounds[i]["username"] = proxyUsername.trimmingCharacters(in: .whitespacesAndNewlines)
                outbounds[i]["password"] = proxyPassword.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        baseJson["outbounds"] = outbounds
        
        if let updatedData = try? JSONSerialization.data(withJSONObject: baseJson, options: [.prettyPrinted]) {
            try? updatedData.write(to: userConfigURL)
            proxyStatusMessage = "Configuration saved"
        }
    }
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkStatus()
            self?.fetchClashStats()
        }
    }
    
    func checkStatus() {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "Muse"]
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let pid = Int32(out) {
            DispatchQueue.main.async {
                self.isMuseRunning = true
                self.musePID = pid
            }
        } else {
            DispatchQueue.main.async {
                self.isMuseRunning = false
                self.musePID = 0
            }
        }
        
        let url = URL(string: "http://127.0.0.1:9990/version")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0
        let task = URLSession.shared.dataTask(with: request) { [weak self] _, response, _ in
            DispatchQueue.main.async {
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    self?.isTunnelActive = true
                } else {
                    self?.isTunnelActive = false
                }
            }
        }
        task.resume()
    }
    
    func fetchClashStats() {
        guard isTunnelActive else {
            DispatchQueue.main.async {
                self.recentConnections = []
            }
            return
        }
        
        if let connURL = URL(string: "http://127.0.0.1:9990/connections") {
            var req = URLRequest(url: connURL)
            req.timeoutInterval = 1.5
            URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let conns = json["connections"] as? [[String: Any]] else { return }
                
                var hosts: [String] = []
                for c in conns.suffix(6) {
                    if let meta = c["metadata"] as? [String: Any],
                       let host = meta["host"] as? String, !host.isEmpty {
                        let proto = meta["network"] as? String ?? "tcp"
                        hosts.append("\(proto.uppercased()): \(host)")
                    }
                }
                DispatchQueue.main.async {
                    self?.recentConnections = hosts
                }
            }.resume()
        }
    }
    
    func startTunnel() {
        saveConfig()
        let script = scriptPath
        let appleScript = "do shell script \"\\\"\(script)\\\" start\" with administrator privileges"
        
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: appleScript) {
                scriptObject.executeAndReturnError(&error)
                if error != nil {
                    DispatchQueue.main.async {
                        self.proxyStatusMessage = "Authorization cancelled"
                    }
                } else {
                    DispatchQueue.main.async {
                        self.isTunnelActive = true
                        self.proxyStatusMessage = "Tunnel Active via utun88"
                        self.checkStatus()
                    }
                }
            }
        }
    }
    
    func stopTunnel() {
        let script = scriptPath
        let appleScript = "do shell script \"\\\"\(script)\\\" stop\" with administrator privileges"
        
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: appleScript) {
                scriptObject.executeAndReturnError(&error)
            }
            DispatchQueue.main.async {
                self.isTunnelActive = false
                self.proxyStatusMessage = "Tunnel Stopped"
                self.checkStatus()
            }
        }
    }
    
    func relaunchMuse() {
        let script = scriptPath
        DispatchQueue.global(qos: .userInitiated).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: script)
            proc.arguments = ["relaunch-muse"]
            try? proc.run()
            proc.waitUntilExit()
            DispatchQueue.main.async {
                self.checkStatus()
            }
        }
    }
    
    func clearDataAndRelaunch() {
        isClearingData = true
        proxyStatusMessage = "Clearing Muse app data..."
        let script = scriptPath
        DispatchQueue.global(qos: .userInitiated).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: script)
            proc.arguments = ["clear-data-relaunch"]
            try? proc.run()
            proc.waitUntilExit()
            DispatchQueue.main.async {
                self.isClearingData = false
                self.proxyStatusMessage = "Muse app data cleared & relaunched"
                self.checkStatus()
            }
        }
    }
    
    func testProxy() {
        saveConfig()
        isTestingProxy = true
        latencyText = "Pinging..."
        let startTime = CFAbsoluteTimeGetCurrent()
        let script = scriptPath
        
        DispatchQueue.global(qos: .userInitiated).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: script)
            proc.arguments = ["test-proxy"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            try? proc.run()
            proc.waitUntilExit()
            
            let elapsed = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            DispatchQueue.main.async {
                self.isTestingProxy = false
                if output.starts(with: "OK") {
                    self.latencyText = "\(elapsed) ms"
                    self.proxyStatusMessage = "Proxy connected (\(elapsed)ms)"
                } else {
                    self.latencyText = "Error"
                    self.proxyStatusMessage = output.isEmpty ? "Connection failed" : output
                }
            }
        }
    }
}

// MARK: - Settings View
struct SettingsSheetView: View {
    @ObservedObject var controller: TunnelController
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 16) {
            Text("SOCKS5 Proxy Configuration")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Server Host:")
                        .frame(width: 90, alignment: .trailing)
                    TextField("e.g. 192.168.1.100", text: $controller.proxyServer)
                        .textFieldStyle(.roundedBorder)
                }
                
                HStack {
                    Text("Port:")
                        .frame(width: 90, alignment: .trailing)
                    TextField("1080", text: $controller.proxyPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                }
                
                HStack {
                    Text("Username:")
                        .frame(width: 90, alignment: .trailing)
                    TextField("Optional", text: $controller.proxyUsername)
                        .textFieldStyle(.roundedBorder)
                }
                
                HStack {
                    Text("Password:")
                        .frame(width: 90, alignment: .trailing)
                    SecureField("Optional", text: $controller.proxyPassword)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            HStack {
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                Spacer()
                Button("Save Settings") {
                    controller.saveConfig()
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

// MARK: - SwiftUI User Interface
struct MainDashboardView: View {
    @ObservedObject var controller: TunnelController
    @State private var showingClearConfirm: Bool = false
    
    var body: some View {
        VStack(spacing: 18) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.blue, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Muse Tunnel")
                        .font(.system(size: 19, weight: .bold))
                    Text("Isolated SOCKS5 Tunnel for Meta Muse")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(controller.isTunnelActive ? Color.green : Color.red)
                        .frame(width: 9, height: 9)
                    Text(controller.isTunnelActive ? "TUNNEL ACTIVE" : "TUNNEL OFF")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(controller.isTunnelActive ? .green : .red)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(controller.isTunnelActive ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
                .cornerRadius(20)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            Divider()
            
            // Info Box
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TARGET APPLICATION")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        HStack(spacing: 6) {
                            Image(systemName: "app.fill")
                                .foregroundColor(.blue)
                            Text("Muse.app (com.meta.endo)")
                                .font(.system(size: 13, weight: .medium))
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("APP STATUS")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(controller.isMuseRunning ? Color.green : Color.orange)
                                .frame(width: 7, height: 7)
                            Text(controller.isMuseRunning ? "Running (PID \(controller.musePID))" : "Not Running")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                }
                
                Divider()
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CONFIGURED SOCKS5 PROXY")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text(controller.proxyServer.isEmpty ? "Not configured (Click Edit)" : "\(controller.proxyServer):\(controller.proxyPort)")
                            .font(.system(size: 12, design: .monospaced))
                    }
                    Spacer()
                    Button("Edit Proxy") {
                        controller.showSettings = true
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                }
                
                HStack {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.green)
                    Text("Strict Isolation: Only Muse is routed. All other macOS apps bypass the proxy directly.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(6)
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .padding(.horizontal, 20)
            
            // Action Buttons
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    if !controller.isTunnelActive {
                        Button(action: {
                            controller.startTunnel()
                        }) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Start Tunnel & Route Muse")
                            }
                            .frame(maxWidth: .infinity, minHeight: 34)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(controller.proxyServer.isEmpty)
                    } else {
                        Button(action: {
                            controller.stopTunnel()
                        }) {
                            HStack {
                                Image(systemName: "stop.fill")
                                Text("Stop Tunnel")
                            }
                            .frame(maxWidth: .infinity, minHeight: 34)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                    
                    Button(action: {
                        controller.testProxy()
                    }) {
                        HStack {
                            Image(systemName: "network")
                            Text(controller.latencyText.contains("ms") ? controller.latencyText : "Test Ping")
                        }
                        .frame(minHeight: 34)
                    }
                    .buttonStyle(.bordered)
                    .disabled(controller.isTestingProxy || controller.proxyServer.isEmpty)
                }
                
                HStack(spacing: 12) {
                    Button(action: {
                        controller.relaunchMuse()
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Relaunch Muse")
                        }
                        .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: {
                        showingClearConfirm = true
                    }) {
                        HStack {
                            Image(systemName: "trash.circle")
                            Text(controller.isClearingData ? "Clearing..." : "Clear Data & Relaunch")
                        }
                        .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .disabled(controller.isClearingData)
                }
            }
            .padding(.horizontal, 20)
            
            // Active Connections
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("ACTIVE TUNNEL CONNECTIONS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    if controller.isTunnelActive {
                        Text("Live routing via utun88")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                    }
                }
                
                if controller.recentConnections.isEmpty {
                    Text(controller.isTunnelActive ? "Waiting for Muse traffic..." : "Tunnel inactive. Configure proxy and click Start Tunnel.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(controller.recentConnections, id: \.self) { host in
                            HStack {
                                Circle().fill(Color.blue).frame(width: 5, height: 5)
                                Text(host)
                                    .font(.system(size: 11, design: .monospaced))
                            }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 520, height: 450)
        .sheet(isPresented: $controller.showSettings) {
            SettingsSheetView(controller: controller)
        }
        .alert("Clear Muse App Data?", isPresented: $showingClearConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Clear & Relaunch", role: .destructive) {
                controller.clearDataAndRelaunch()
            }
        } message: {
            Text("This will completely wipe all data, cache, login sessions, and preferences for the Muse app only (com.meta.endo) and relaunch it fresh. Muse Tunnel settings will not be affected.")
        }
    }
}

// MARK: - App Delegate & Menu Bar Extra
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var statusItem: NSStatusItem!
    let controller = TunnelController()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 450),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Muse Tunnel"
        window.contentView = NSHostingView(rootView: MainDashboardView(controller: controller))
        window.isReleasedWhenClosed = false
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bolt.shield", accessibilityDescription: "Muse Tunnel")
        }
        setupMenu()
    }
    
    func setupMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Muse Tunnel Dashboard", action: #selector(openDashboard), keyEquivalent: "d"))
        menu.addItem(NSMenuItem(title: "Proxy Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Relaunch Muse", action: #selector(relaunchMuse), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Clear Data & Relaunch Muse", action: #selector(clearDataAndRelaunch), keyEquivalent: "c"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }
    
    @objc func clearDataAndRelaunch() {
        controller.clearDataAndRelaunch()
    }
    
    @objc func openDashboard() {
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func openSettings() {
        controller.showSettings = true
        openDashboard()
    }
    
    @objc func relaunchMuse() {
        controller.relaunchMuse()
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
