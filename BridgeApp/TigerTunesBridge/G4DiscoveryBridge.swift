//
//  G4DiscoveryBridge.swift
//  Tiger Tunes Bridge
//
//  Created by Danny Herrmann on 2/26/26.
//

import Foundation
import Network

class G4DiscoveryBridge: NSObject, NetServiceDelegate {
    private var netService: NetService?
    private var listener: NWListener?
    private var metadataListener: NWListener?
    private var httpProxyListener: NWListener?
    private var activeConnections: [NWConnection] = []
    private var metadataWebSocket: NWConnection?
    private var metadataClients: [NWConnection] = [] // Port 5003 clients
    var spotifyAPI: SpotifyAPIController?
    
    func start(port: Int32 = 5001, api: SpotifyAPIController, mode: TigerTunesEngine.BridgeMode) {
        self.spotifyAPI = api
        
        let serviceType = (mode == .spotifyOnly) ? "_spotify-tt._tcp." : "_airplay-tt._tcp."
        
        do {
            let nwPort = NWEndpoint.Port(rawValue: UInt16(port))!
            let parameters = NWParameters.tcp

            if let tcpOptions = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
                tcpOptions.noDelay = true
            }

            parameters.allowLocalEndpointReuse = true
            
            listener = try NWListener(using: parameters, on: nwPort)

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            
            listener?.start(queue: .main)
            print("🔊 TCP Audio Server listening on port \(port) (Low Latency Mode)")
            
            // Announce via Bonjour
            netService = NetService(domain: "local.", type: serviceType, name: Host.current().localizedName ?? "TigerTunes-Swift", port: port)
            netService?.delegate = self
            
            let record = ["api_port": "5002"]
            netService?.setTXTRecord(NetService.data(fromTXTRecord: record.mapValues { $0.data(using: .utf8)! }))
            netService?.publish()
            
            if mode == .spotifyOnly {
                startMetadataBridge()
            } else {
                print("ℹ️ AirPlay Mode: Skipping Spotify Metadata WebSocket (Port 8888)")
            }
            
            startLegacyMetadataServer()
            startAlbumArtProxy()
            
        } catch {
            print("❌ Failed to start G4 Discovery: \(error)")
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("⚡️ iMac G4 connected for audio!")
                DispatchQueue.main.async {
                    self.activeConnections.append(connection)
                }
            case .failed, .cancelled:
                DispatchQueue.main.async {
                    self.activeConnections.removeAll(where: { $0 === connection })
                }
            default: break
            }
        }
        
        // 🔥 CHANGE: Use .global(qos: .userInteractive) instead of .main
        connection.start(queue: .global(qos: .userInteractive))
    }

    // Change the signature to include a completion block
    func broadcastAudio(_ data: Data, completion: @escaping () -> Void) {
        let connections = self.activeConnections
        if connections.isEmpty {
            completion() // No one to send to, keep the engine moving
            return
        }

        let group = DispatchGroup()
        
        for connection in connections {
            guard connection.state == .ready else { continue }
            group.enter()
            
            connection.send(content: data, completion: .contentProcessed({ _ in
                group.leave()
            }))
        }

        group.notify(queue: .global()) {
            completion()
        }
    }
    
    private func cleanupConnection(_ connection: NWConnection) {
        connection.cancel()
        if let index = activeConnections.firstIndex(where: { $0 === connection }) {
            activeConnections.remove(at: index)
        }
    }
    
    func startMetadataBridge() {
        let options = NWProtocolWebSocket.Options()
        options.autoReplyPing = true
        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        
        let url = URL(string: "ws://127.0.0.1:8888/events")!
        metadataWebSocket = NWConnection(to: .url(url), using: parameters)
        
        metadataWebSocket?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("✅ Connected to go-librespot Metadata (8888)")
                self?.receiveMetadata()
            case .waiting(let error):
                print("⏳ WebSocket waiting: \(error). Resetting...")
                self?.metadataWebSocket?.cancel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.startMetadataBridge() }
            case .failed(let error):
                print("❌ WebSocket failed: \(error)")
                self?.metadataWebSocket?.cancel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.startMetadataBridge() }
            default: break
            }
        }
        metadataWebSocket?.start(queue: .main)
    }

    private func receiveMetadata() {
        metadataWebSocket?.receiveMessage { [weak self] (data, context, isComplete, error) in
            if let error = error {
                print("❌ WebSocket Receive Error: \(error)")
                return
            }
            if let data = data {
                var payload = data
                payload.append("\n".data(using: .utf8)!)
                self?.broadcastMetadataToLegacyClients(payload)
            }
            self?.receiveMetadata()
        }
    }
    
    func startLegacyMetadataServer(port: Int32 = 5003) {
        do {
            let nwPort = NWEndpoint.Port(rawValue: UInt16(port))!
            metadataListener = try NWListener(using: .tcp, on: nwPort)
            metadataListener?.newConnectionHandler = { [weak self] connection in
                connection.stateUpdateHandler = { state in
                    if state == .ready {
                        print("📱 Legacy G4 Metadata Client Connected!")
                        self?.metadataClients.append(connection)
                    } else if case .failed = state {
                        self?.metadataClients.removeAll(where: { $0 === connection })
                    }
                }
                connection.start(queue: .main)
            }
            metadataListener?.start(queue: .main)
        } catch { print("❌ Metadata Server failed") }
    }

    func broadcastMetadataToLegacyClients(_ data: Data) {
        for client in metadataClients {
            client.send(content: data, completion: .contentProcessed({ error in
                if error != nil { client.cancel() }
            }))
        }
    }
    
    func startAlbumArtProxy(port: Int32 = 5002) {
        do {
            let nwPort = NWEndpoint.Port(rawValue: UInt16(port))!
            httpProxyListener = try NWListener(using: .tcp, on: nwPort)
            httpProxyListener?.newConnectionHandler = { connection in
                connection.start(queue: .main)
                self.handleProxyRequest(connection)
            }
            httpProxyListener?.start(queue: .main)
            print("🖼 Album Art Proxy listening on port \(port)")
        } catch { print("❌ Proxy Server failed") }
    }

    private func handleProxyRequest(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, isComplete, error in
            guard let data = data, let request = String(data: data, encoding: .utf8) else { return }
            
            // --- ROUTE: RESOLVE CONTEXT ---
            if request.contains("/resolve_context"), let range = request.range(of: "uri=") {
                // Extract the URI from the GET parameters
                let start = range.upperBound
                let end = request.range(of: " HTTP/1.1")?.lowerBound ?? request.endIndex
                let encodedUri = String(request[start..<end])
                
                guard let uri = encodedUri.removingPercentEncoding else { return }
                print("🔍 G4 Request: Resolve Name for \(uri)")

                Task {
                    let contextName = await self.spotifyAPI?.resolveSpotifyContext(uri: uri)
                    
                    // Construct JSON to match CJSONDeserializer requirements
                    let responseDict: [String: Any?] = ["name": contextName]
                    if let jsonData = try? JSONSerialization.data(withJSONObject: responseDict, options: []) {
                        self.sendHTTPResponse(to: connection, contentType: "application/json", body: jsonData)
                    }
                }
                return
            }
            
            if request.contains("album_art_proxy"),
               let range = request.range(of: "url="),
               let endRange = request.range(of: " HTTP/1.1") {
                
                let encodedUrl = String(request[range.upperBound..<endRange.lowerBound])
                if let decodedUrl = encodedUrl.removingPercentEncoding, let url = URL(string: decodedUrl) {
                    URLSession.shared.dataTask(with: url) { imageData, _, _ in
                        guard let imageData = imageData else { return }
                        self.sendHTTPResponse(to: connection, contentType: "image/jpeg", body: imageData)
                    }.resume()
                }
            }
            
            // --- ROUTE: PROFILE IMAGE PROXY ---
            if request.contains("/profile_image_proxy") {
                print("👤 G4 Request: Profile Image")
                
                Task {
                    // 1. Get the actual Spotify image URL from the API
                    guard let imageUrl = await self.spotifyAPI?.fetchProfileImageUrl() else {
                        print("⚠️ No profile image URL found.")
                        return
                    }
                    
                    // 2. Download the image data
                    do {
                        let (imageData, _) = try await URLSession.shared.data(from: imageUrl)
                        
                        // 3. Send to G4
                        self.sendHTTPResponse(to: connection, contentType: "image/jpeg", body: imageData)
                        print("📤 Sent Profile Image to G4")
                    } catch {
                        print("❌ Error downloading profile image: \(error)")
                    }
                }
                return
            }
            
            // --- ROUTE: CONNECT (HIJACK) ---
            if request.contains("/connect") {
                print("🔌 G4 Request: Triggering Spotify Connect (Hijack)")
                
                Task {
                    // 1. Trigger the logic in the Controller
                    await self.spotifyAPI?.hijackPlayback()
                    
                    // 2. Respond to the G4 so its NSURLConnection finishes cleanly
                    let responseDict = ["status": "success", "message": "Transfer initiated"]
                    if let jsonData = try? JSONSerialization.data(withJSONObject: responseDict) {
                        self.sendHTTPResponse(to: connection, contentType: "application/json", body: jsonData)
                        print("📤 Sent Hijack Success response to G4")
                    }
                }
                return
            }
            
            // --- ROUTE: AIRPLAY ART PROXY ---
            if request.contains("/airplay_art") {
                guard let stateDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("engine_state") else { return }
                let artURL = stateDir.appendingPathComponent("current_airplay.jpg")
                
                if let imageData = try? Data(contentsOf: artURL) {
                    self.sendHTTPResponse(to: connection, contentType: "image/jpeg", body: imageData)
                    print("📤 Sent AirPlay Art to G4")
                }
                return
            }
        }
    }

    nonisolated func sendHTTPResponse(to connection: NWConnection, contentType: String, body: Data) {
        var header = "HTTP/1.1 200 OK\r\nContent-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var responseData = header.data(using: .utf8)!
        responseData.append(body)
        connection.send(content: responseData, completion: .contentProcessed({ _ in connection.cancel() }))
    }
    
    func stop() {
        netService?.stop()
        listener?.cancel()
        metadataListener?.cancel()
        metadataWebSocket?.cancel()
        httpProxyListener?.cancel()
        for conn in activeConnections { conn.cancel() }
        for conn in metadataClients { conn.cancel() }
        activeConnections.removeAll()
        metadataClients.removeAll()
    }
}
