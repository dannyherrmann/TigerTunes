//
//  TigerTunesEngine.swift
//  Tiger Tunes Bridge
//
//  Created by Danny Herrmann on 2/26/26.
//

import Foundation
import Network
import Combine

class TigerTunesEngine: ObservableObject {
    
    enum BridgeMode {
        case airplayOnly
        case spotifyOnly
    }
    
    enum AudioSource {
        case spotify
        case airplay
    }

    @Published var activeSource: AudioSource = .spotify
    @Published var isRunning = false
    @Published var isAuthenticated = false
    @Published var logMessages: [String] = []
    @Published var selectedMode: BridgeMode? = nil
    @Published var deviceName: String = UserDefaults.standard.string(forKey: "legacy_device_name") ?? "Legacy Mac" {
        didSet {
            UserDefaults.standard.set(deviceName, forKey: "legacy_device_name")
        }
    }
    
    private var goProcess: Process?
    private var shairportProcess: Process?
    private let queue = DispatchQueue(label: "com.tigertunes.engine", attributes: .concurrent)
    private var engineStateDir: URL?
    private var metadataPipeURL: URL?
    private var spotifyConfigURL: URL?
    private var airplayConfigURL: URL?
    private var imageAccumulator = Data()
    
    // --- The G4 Bridge ---
    private let g4Bridge = G4DiscoveryBridge()
    
    // Helper function to resolve binary paths across both Resources and Executables
    private func resolveBinaryPath(named name: String) -> String? {
        if let path = Bundle.main.path(forAuxiliaryExecutable: name) {
            return path
        }
        if let path = Bundle.main.path(forResource: name, ofType: nil) {
            return path
        }
        return nil
    }

    func startEngine(api: SpotifyAPIController, mode: BridgeMode) {
        self.selectedMode = mode
        self.isAuthenticated = false
        
        // 1. Locate binaries using fallback resolver
        guard let goPath = resolveBinaryPath(named: "go-librespot-universal"),
              let ffmpegPath = resolveBinaryPath(named: "ffmpeg"),
              let bundleSpotifyConfig = Bundle.main.path(forResource: "config", ofType: "yml"),
              let bundleAirPlayConfig = Bundle.main.path(forResource: "shairport", ofType: "conf") else { // Matches "shairport.conf"
            self.appendLog("❌ Error: Binaries missing in bundle.")
            return
        }

        // 2. Prepare Directory & Paths
        let fileManager = FileManager.default
        guard let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let stateDir = appSupportDir.appendingPathComponent("engine_state")
        self.engineStateDir = stateDir
        self.spotifyConfigURL = stateDir.appendingPathComponent("config.yml")
        self.metadataPipeURL = stateDir.appendingPathComponent("shairport-metadata-pipe")
        self.airplayConfigURL = stateDir.appendingPathComponent("shairport-sync.conf")

        do {
            try fileManager.createDirectory(at: stateDir, withIntermediateDirectories: true)
            if !fileManager.fileExists(atPath: spotifyConfigURL!.path) {
                try fileManager.copyItem(at: URL(fileURLWithPath: bundleSpotifyConfig), to: spotifyConfigURL!)
            }
            if !fileManager.fileExists(atPath: airplayConfigURL!.path) {
                try fileManager.copyItem(at: URL(fileURLWithPath: bundleAirPlayConfig), to: airplayConfigURL!)
            }
            if !fileManager.fileExists(atPath: metadataPipeURL!.path) {
                mkfifo(metadataPipeURL!.path, 0o666)
            }
        } catch {
            self.appendLog("❌ File Error: \(error.localizedDescription)")
            return
        }

        // --- ROUTE BRANCHING START ---
        
        if mode == .airplayOnly {
            // 🚀 AIRPLAY ROUTE: Just start Discovery and Shairport
            self.isRunning = true
            self.activeSource = .airplay
            
            g4Bridge.start(port: 5001, api: api, mode: mode)
            startAirPlay() // This handles its own process and thread
            
            appendLog("📡 Bridge Started: AirPlay Mode")
            
        } else {
            // 🚀 SPOTIFY ROUTE: Start the Go/FFMPEG Pipeline
            self.activeSource = .spotify
            
            g4Bridge.start(port: 5001, api: api, mode: mode)
            appendLog("📡 Bridge Started: Spotify Mode")
            
            chmod(goPath, 0o755)
            chmod(ffmpegPath, 0o755)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.currentDirectoryURL = stateDir
            
            let pipeline = "\"\(goPath)\" --config_dir \"\(stateDir.path)\" | \"\(ffmpegPath)\" -re -f s16le -ar 44100 -ac 2 -i pipe:0 -fflags nobuffer+flush_packets -flags low_delay -f s16be -ac 2 -ar 44100 pipe:1"

            process.arguments = ["-c", pipeline]
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            // Handle Logs (Spotify Auth Detection)
            errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if let line = String(data: data, encoding: .utf8), !line.isEmpty {
                    Task { @MainActor in
                        self?.appendLog(line)
                        if line.contains("authenticated AP") { self?.isAuthenticated = true }
                    }
                }
            }

            do {
                try process.run()
                self.goProcess = process
                self.isRunning = true
                
                // Audio Drain Thread (Spotify)
                let audioHandle = outputPipe.fileHandleForReading
                Thread.detachNewThread { [weak self] in
                    while let self = self, self.isRunning {
                        let data = audioHandle.readData(ofLength: 8192)
                        
                        if data.isEmpty {
                            usleep(10000); // 10ms nap
                            continue
                        }
                        
                        let semaphore = DispatchSemaphore(value: 0)
                        self.g4Bridge.broadcastAudio(data) { semaphore.signal() }
                        semaphore.wait()
                    }
                }
                
            } catch {
                appendLog("❌ Failed to start Spotify: \(error.localizedDescription)")
            }
        }
    }
    
    func updateConfigIfNeeded() {
        let fileManager = FileManager.default
        guard let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let configPath = appSupportDir.appendingPathComponent("engine_state/config.yml")
        
        do {
            let currentContent = try String(contentsOf: configPath, encoding: .utf8)
            let expectedLine = "device_name: \"\(deviceName)\""
            
            if !currentContent.contains(expectedLine) {
                var updatedContent = currentContent
                if let range = updatedContent.range(of: "device_name: \".*\"", options: .regularExpression) {
                    updatedContent.replaceSubrange(range, with: expectedLine)
                    try updatedContent.write(to: configPath, atomically: true, encoding: .utf8)
                    print("📝 YAML Updated: \(deviceName)")
                }
            }
        } catch {
            print("❌ Config Sync Error: \(error)")
        }
    }
    
    func startAirPlay() {
        let killTask = Process()
        killTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killTask.arguments = ["-9", "shairport-sync"]
        try? killTask.run()
        killTask.waitUntilExit() // Wait for it to finish so the OS releases resources
        
        guard let pipeURL = metadataPipeURL else { return }
        let fileManager = FileManager.default
        
        // 1. Locate the config file in Application Support
        guard let stateDir = self.engineStateDir else { return }
        let airplayConfigURL = stateDir.appendingPathComponent("shairport-sync.conf")
        
        do {
            var content = try String(contentsOf: airplayConfigURL, encoding: .utf8)
            
            // 1. Update/Inject the 'name'
            let newNameLine = "name = \"\(self.deviceName)\";"
            if let nameRange = content.range(of: #"name\s*=\s*".*";"#, options: .regularExpression) {
                content.replaceSubrange(nameRange, with: newNameLine)
            } else if let generalRange = content.range(of: "general = {") {
                content.insert(contentsOf: "\n    \(newNameLine)", at: generalRange.upperBound)
            }
            
            // 2. Update/Inject the 'pipe_name'
            let newPipeLine = "pipe_name = \"\(pipeURL.path)\";"
            if let pipeRange = content.range(of: #"pipe_name\s*=\s*".*";"#, options: .regularExpression) {
                content.replaceSubrange(pipeRange, with: newPipeLine)
            } else if let metadataRange = content.range(of: "metadata = {") {
                content.insert(contentsOf: "\n    \(newPipeLine)", at: metadataRange.upperBound)
            }
            
            try content.write(to: airplayConfigURL, atomically: true, encoding: .utf8)
            print("✅ Shairport Config synchronized (clean version).")
        } catch {
            appendLog("⚠️ AirPlay Config Sync Warning: \(error.localizedDescription)")
        }

        // 3. Ensure the pipe is fresh and clean
        if fileManager.fileExists(atPath: pipeURL.path) {
            try? fileManager.removeItem(atPath: pipeURL.path)
        }
        mkfifo(pipeURL.path, 0o666)

        // 4. Setup the Process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.currentDirectoryURL = stateDir

        // Updated binary resolution fallback
        guard let shairportPath = resolveBinaryPath(named: "shairport-sync"),
              let ffmpegPath = resolveBinaryPath(named: "ffmpeg") else {
            appendLog("❌ AirPlay Error: Binaries missing in bundle.")
            return
        }

        chmod(shairportPath, 0o755)
        chmod(ffmpegPath, 0o755)

        // THE PIPELINE:
        // 1. Run shairport-sync outputting raw s16le to stdout
        // 2. Pipe to ffmpeg
        // 3. Ffmpeg converts s16le (input) to s16be (output) for the G4
        let pipeline = "\"\(shairportPath)\" -p 5004 -c \"\(airplayConfigURL.path)\" -o stdout | \"\(ffmpegPath)\" -f s16le -ar 44100 -ac 2 -i - -f s16be -ac 2 -ar 44100 -"

        process.arguments = ["-c", pipeline]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Monitor Shairport Logs
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let line = String(data: data, encoding: .utf8), !line.isEmpty {
                Task { @MainActor in self?.appendLog("[AirPlay Log] \(line)") }
            }
        }

        do {
            try process.run()
            self.shairportProcess = process
            let pathForThread = pipeURL.path

            // --- METADATA THREAD ---
            Thread.detachNewThread { [weak self] in
                let fd = open(pathForThread, O_RDONLY)
                if fd < 0 { return }
                
                var streamBuffer = ""
                let bufferSize = 16384
                var buffer = [UInt8](repeating: 0, count: bufferSize)
                
                while let self = self, self.isRunning {
                    let bytesRead = read(fd, &buffer, bufferSize)
                    
                    if bytesRead > 0 {
                        if let newString = String(data: Data(bytes: buffer, count: bytesRead), encoding: .utf8) {
                            streamBuffer += newString
                            
                            while streamBuffer.contains("</item>") {
                                guard let startRange = streamBuffer.range(of: "<item>"),
                                      let endRange = streamBuffer.range(of: "</item>"),
                                      startRange.lowerBound < endRange.upperBound else {
                                    
                                    if let junkEnd = streamBuffer.range(of: "</item>") {
                                        streamBuffer.removeSubrange(streamBuffer.startIndex..<junkEnd.upperBound)
                                    }
                                    break
                                }
                                
                                let itemContent = String(streamBuffer[startRange.lowerBound..<endRange.upperBound])
                                
                                if itemContent.contains("50494354") { // 50494354 = PICT
                                    print("📡 RAW ATOM: [Album Art Data - Truncated]")
                                } else {
                                    print("📡 RAW ATOM: \(itemContent)")
                                }
                                
                                streamBuffer.removeSubrange(streamBuffer.startIndex..<endRange.upperBound)
                                self.parseShairportItem(itemContent)
                            }
                        }
                    } else if bytesRead == 0 {
                        break
                    }
                    
                    if streamBuffer.count > 1000000 { streamBuffer = "" }
                    usleep(100000)
                }
                close(fd)
            }

            // --- AUDIO DRAIN THREAD ---
            let audioHandle = outputPipe.fileHandleForReading
            Thread.detachNewThread { [weak self] in
                while let self = self, self.isRunning {
                    let data = audioHandle.readData(ofLength: 16384)
                    if data.isEmpty { usleep(5000); continue }
                    
                    Task { @MainActor in self.activeSource = .airplay }

                    let semaphore = DispatchSemaphore(value: 0)
                    self.g4Bridge.broadcastAudio(data) {
                        semaphore.signal()
                    }
                    semaphore.wait()
                }
            }
            
        } catch {
            appendLog("❌ Failed to start AirPlay: \(error.localizedDescription)")
        }
    }
    
    private func parseShairportItem(_ xml: String) {
        guard let code = xml.slice(from: "<code>", to: "</code>"),
              let type = xml.slice(from: "<type>", to: "</type>") else { return }
        
        // ----------------------------------------------------------------
        // 1. SESSION & CONTROL LOGIC (ssnc: 73736e63)
        // ----------------------------------------------------------------
        if type == "73736e63" {
            switch code {
            case "70637374": // 'pcst' - Picture Start
                print("📸 [AirPlay] Picture Start: Clearing buffer")
                imageAccumulator = Data()
                
            case "50494354": // 'PICT' - Picture Data Chunk
                if let rawB64 = xml.slice(from: "base64\">", to: "</data>") {
                    let cleanedB64 = rawB64.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let chunkData = Data(base64Encoded: cleanedB64) {
                        imageAccumulator.append(chunkData)
                    }
                }
                
            case "7063656e": // 'pcen' - Picture End
                print("🏁 [AirPlay] Picture End: Final Size \(imageAccumulator.count) bytes")
                if !imageAccumulator.isEmpty {
                    self.saveAirPlayArtwork(imageAccumulator)
                    
                    let payloadString = "ArtUpdate: \(Int(Date().timeIntervalSince1970))\n"
                    if let payloadData = payloadString.data(using: .utf8) {
                        logWithTime("🚀 SENDING TO G4: \(payloadString.trimmingCharacters(in: .whitespacesAndNewlines))")
                        self.g4Bridge.broadcastMetadataToLegacyClients(payloadData)
                    }
                }
                
            case "70666c73": // 'pfls' - Flush (Pause)
                self.broadcastSimpleState("State: Paused")
                
            case "7072736d": // 'prsm' - Resume (Play)
                self.broadcastSimpleState("State: Playing")

            default:
                break
            }
            return
        }
        
        // ----------------------------------------------------------------
        // 2. SONG DATA LOGIC (core: 636f7265)
        // ----------------------------------------------------------------
        if type == "636f7265" {
            let labels: [String: String] = [
                "6d696e6d": "title",
                "61736172": "artist",
                "6173616c": "album"
            ]
            
            guard let tag = labels[code] else { return }
            
            if let rawB64 = xml.slice(from: "base64\">", to: "</data>") {
                let cleanedB64 = rawB64.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if let decodedData = Data(base64Encoded: cleanedB64),
                   let value = String(data: decodedData, encoding: .utf8) {
                    
                    if Double(value) != nil { return }
                    
                    let prefixes: [String: String] = [
                        "title": "Title: ",
                        "artist": "Artist: ",
                        "album": "Album: "
                    ]
                    
                    let prefix = prefixes[tag] ?? "Artist: "
                    let payloadString = "\(prefix)\(value)\n"
                    
                    if let payloadData = payloadString.data(using: .utf8) {
                        logWithTime("🚀 SENDING TO G4: \(payloadString.trimmingCharacters(in: .whitespacesAndNewlines))")
                        self.g4Bridge.broadcastMetadataToLegacyClients(payloadData)
                    }
                }
            }
        }
    }

    private func broadcastSimpleState(_ stateMessage: String) {
        let formatted = "\(stateMessage)\n"
        if let payloadData = formatted.data(using: .utf8) {
            logWithTime("🚀 SENDING TO G4: \(stateMessage)")
            self.g4Bridge.broadcastMetadataToLegacyClients(payloadData)
        }
    }
    
    private func saveAirPlayArtwork(_ data: Data) {
        guard let stateDir = self.engineStateDir else { return }
        let artURL = stateDir.appendingPathComponent("current_airplay.jpg")
        
        do {
            try data.write(to: artURL)
            print("🖼 Saved AirPlay Artwork (\(data.count) bytes)")
        } catch {
            print("❌ Failed to save artwork: \(error)")
        }
    }
    
    private func extractMetadata(from xml: String) -> String? {
        let parts = xml.components(separatedBy: "<data encoding=\"base64\">")
        guard parts.count > 1 else { return nil }
        
        let base64String = parts[1].components(separatedBy: "</data>")[0]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if base64String.count < 4 { return nil }

        if let decodedData = Data(base64Encoded: base64String),
           let decodedString = String(data: decodedData, encoding: .utf8) {
            if Int(decodedString) != nil { return nil }
            return decodedString
        }
        return nil
    }
    
    func stopAirPlay() {
        shairportProcess?.terminate()
        shairportProcess = nil
        appendLog("🛑 AirPlay receiver stopped")
    }
    
    func logoutEngine() {
        stopEngine()
        
        let fileManager = FileManager.default
        guard let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let stateFile = appSupportDir.appendingPathComponent("engine_state/state.json")
        
        try? fileManager.removeItem(at: stateFile)
        self.isAuthenticated = false
        appendLog("🗑 Audio Engine credentials deleted.")
    }
    
    func stopEngine() {
        self.isRunning = false

        if let spotifyProcess = goProcess, spotifyProcess.isRunning {
            let pid = spotifyProcess.processIdentifier
            print("🛑 Terminating Spotify Process Group (PID: \(pid))")
            kill(-pid, SIGTERM)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if spotifyProcess.isRunning {
                    kill(-pid, SIGKILL)
                }
            }
        }
        self.goProcess = nil

        stopAirPlay()
        g4Bridge.stop()

        Task { @MainActor in
            self.isAuthenticated = false
            self.selectedMode = nil
            self.appendLog("🛑 Engine Cleaned Up Successfully")
        }
    }

    private func appendLog(_ message: String) {
        logMessages.append(message)
        if logMessages.count > 50 { logMessages.removeFirst() }
    }
    
    private func logWithTime(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timeString = formatter.string(from: Date())
        print("[\(timeString)] \(message)")
    }
}

extension String {
    func slice(from: String, to: String) -> String? {
        guard let startRange = self.range(of: from) else { return nil }
        guard let endRange = self.range(of: to, range: startRange.upperBound..<self.endIndex) else {
            return nil
        }
        if startRange.upperBound <= endRange.lowerBound {
            return String(self[startRange.upperBound..<endRange.lowerBound])
        }
        return nil
    }
}
