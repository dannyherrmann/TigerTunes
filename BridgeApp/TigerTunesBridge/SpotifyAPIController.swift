//
//  SpotifyAPIController.swift
//  Tiger Tunes Bridge
//
//  Created by Danny Herrmann on 2/27/26.
//

import Foundation
import AuthenticationServices
import CryptoKit
import Combine

class SpotifyAPIController: ObservableObject {
    @Published var isAuthorized = false
    private let clientId = "4fcff2d4bf274756add64615260e5608"
    private let redirectUri = "tigertunes://callback"
    private var codeVerifier: String?
    private var accessToken: String?
    private var refreshToken: String?
    
    init() {
        Task {
            await self.tryAutoLogin()
        }
    }
    
    private func performSpotifyRequest<T: Codable>(
        url: URL,
        method: String = "GET",
        body: [String: Any]? = nil,
        retryCount: Int = 1
    ) async throws -> T {
        
        // 1. Prepare the Request
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(self.accessToken ?? "")", forHTTPHeaderField: "Authorization")
        
        if let body = body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        // 2. Execute
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "Network", code: 0)
        }

        // 3. Handle Token Expiry (401)
        if httpResponse.statusCode == 401 && retryCount > 0 {
            print("🔄 401 Detected. Refreshing token and retrying...")
            await self.refreshAccessToken()
            return try await performSpotifyRequest(url: url, method: method, body: body, retryCount: retryCount - 1)
        }

        // 4. Handle Success
        if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
            // --- 204 FIX START ---
            // If Spotify returns 204 (No Content), the data buffer is empty.
            // We provide a dummy empty JSON object so the decoder doesn't fail.
            let effectiveData = (httpResponse.statusCode == 204 || data.isEmpty)
                ? "{}".data(using: .utf8)!
                : data
            // --- 204 FIX END ---
            
            return try JSONDecoder().decode(T.self, from: effectiveData)
        } else {
            let errorBody = String(data: data, encoding: .utf8) ?? "No error body"
            print("❌ Spotify API Error (\(httpResponse.statusCode)): \(errorBody)")
            throw NSError(domain: "SpotifyAPI", code: httpResponse.statusCode)
        }
    }

    // 1. Generate PKCE Verifier and Challenge
    private func generatePKCE() -> (verifier: String, challenge: String) {
        let verifier = (0..<64).map { _ in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~".randomElement()! }
        let verifierString = String(verifier)
        
        let data = verifierString.data(using: .utf8)!
        let hashed = SHA256.hash(data: data)
        let challenge = Data(hashed).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        
        return (verifierString, challenge)
    }

    // 2. Launch the Web Authentication Session
    func login(presentationContext: ASWebAuthenticationPresentationContextProviding) {
        let (verifier, challenge) = generatePKCE()
        self.codeVerifier = verifier

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "scope", value: "user-read-playback-state user-modify-playback-state user-read-recently-played playlist-read-private playlist-read-collaborative"),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge)
        ]

        // Use "tigertunes" as the callbackURLScheme
        let session = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: "tigertunes") { [weak self] callbackURL, error in
            if let error = error {
                print("❌ Auth Error: \(error.localizedDescription)")
                return
            }

            guard let callbackURL = callbackURL else { return }
            print("🔗 Successfully intercepted: \(callbackURL.absoluteString)")

            if let code = URLComponents(string: callbackURL.absoluteString)?.queryItems?.first(where: { $0.name == "code" })?.value {
                self?.exchangeCodeForToken(code: code)
            }
        }
        
        session.presentationContextProvider = presentationContext
        session.prefersEphemeralWebBrowserSession = true // Forces a fresh login for testing
        session.start()
    }

    private func exchangeCodeForToken(code: String) {
        guard let verifier = self.codeVerifier else {
            print("❌ Error: Code verifier missing.")
            return
        }

        let url = URL(string: "https://accounts.spotify.com/api/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyComponents: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectUri,
            "client_id": clientId,
            "code_verifier": verifier
        ]
        
        request.httpBody = bodyComponents
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    print("❌ Token Exchange Failed: \(String(data: data, encoding: .utf8) ?? "Unknown Error")")
                    return
                }

                let tokenResponse = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
                
                await MainActor.run {
                    self.accessToken = tokenResponse.access_token
                    self.refreshToken = tokenResponse.refresh_token
                    self.isAuthorized = true
                    print("✅ TigerTunes Web API Authorized!")
                    Task {
                        await self.fetchProfile()
                    }
                    self.persistToken(tokenResponse)
                }
            } catch {
                print("❌ Network Error: \(error.localizedDescription)")
            }
        }
    }

    // --- ADDED: THE MISSING REFRESH LOGIC ---
    func refreshAccessToken() async {
        guard let savedRefreshToken = self.refreshToken else { return }

        let url = URL(string: "https://accounts.spotify.com/api/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "refresh_token",
            "refresh_token": savedRefreshToken,
            "client_id": clientId
        ]

        request.httpBody = body
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("❌ Refresh Failed: \(String(data: data, encoding: .utf8) ?? "Unknown Error")")
                return
            }
            
            let tokenResponse = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
            
            await MainActor.run {
                self.accessToken = tokenResponse.access_token
                // If Spotify provided a new refresh token, update it
                if let newRefreshToken = tokenResponse.refresh_token {
                    self.refreshToken = newRefreshToken
                    self.persistToken(tokenResponse)
                }
                print("🔄 Access Token Refreshed!")
            }
        } catch {
            print("❌ Refresh error: \(error.localizedDescription)")
        }
    }

    func persistToken(_ response: SpotifyTokenResponse) {
        // Only update UserDefaults if a refresh token was actually provided
        if let token = response.refresh_token {
            UserDefaults.standard.set(token, forKey: "tiger_tunes_refresh_token")
            print("💾 Refresh token persisted to UserDefaults.")
        }
    }

    func tryAutoLogin() async {
        if let savedRefreshToken = UserDefaults.standard.string(forKey: "tiger_tunes_refresh_token") {
            print("🔍 Found saved refresh token, attempting silent login...")
            self.refreshToken = savedRefreshToken
            
            // Now calling the method we just added
            await self.refreshAccessToken()
            
            if self.accessToken != nil {
                await MainActor.run {
                    self.isAuthorized = true
                }
            }
        }
    }
    
    func fetchProfile() async {
        guard let url = URL(string: "https://api.spotify.com/v1/me") else { return }
        
        do {
            let profile: SpotifyProfile = try await performSpotifyRequest(url: url)
            print("🎉 SUCCESS: Connected to \(profile.displayName)!")
        } catch {
            print("❌ Final failure fetching profile: \(error)")
        }
    }
    
    func logout() {
        // 1. Clear in-memory tokens
        self.accessToken = nil
        self.refreshToken = nil
        
        // 2. Remove from persistent storage
        UserDefaults.standard.removeObject(forKey: "tiger_tunes_refresh_token")
        
        // 3. Update UI
        DispatchQueue.main.async {
            self.isAuthorized = false
            print("🗑 TigerTunes API session cleared.")
        }
    }
    
    func fetchProfileImageUrl() async -> URL? {
        guard let url = URL(string: "https://api.spotify.com/v1/me") else { return nil }
        
        do {
            let profile: SpotifyProfile = try await performSpotifyRequest(url: url)
            if let firstImageUrl = profile.images.first?.url {
                return URL(string: firstImageUrl)
            }
        } catch {
            print("❌ Profile Image Fetch Error: \(error)")
        }
        return nil
    }

    struct SpotifyProfile: Codable {
        let displayName: String
        let images: [SpotifyImage]

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case images
        }
    }

    struct SpotifyImage: Codable {
        let url: String
    }
    
    struct SpotifyNameResponse: Codable {
        let name: String
    }
    
    func resolveSpotifyContext(uri: String) async -> String? {
        // 1. TRULY EMPTY: Match Python's check exactly
        if uri.isEmpty || uri == "None" {
            return nil
        }
        
        // 2. LIKED SONGS: Handle the :collection URI
        if uri.contains(":collection") {
            return "Liked Songs"
        }

        // 3. STATIONS: Python returns "Recommended Tracks" for stations
        if uri.contains(":station:") {
            return "Recommended Tracks"
        }
        
        // 4. API LOOKUP: Explicit branching per type to match Python logic
        do {
            if uri.contains(":album:") {
                return await fetchName(endpoint: "albums", uri: uri)
            } else if uri.contains(":playlist:") {
                return await fetchName(endpoint: "playlists", uri: uri)
            } else if uri.contains(":artist:") {
                return await fetchName(endpoint: "artists", uri: uri)
            } else if uri.contains(":show:") {
                return await fetchName(endpoint: "shows", uri: uri)
            } else {
                // For unknown types, return nil so G4 hides the label
                return nil
            }
        } catch {
            print("❌ Spotify API error: \(error)")
            return nil
        }
    }

    private func fetchName(endpoint: String, uri: String) async -> String? {
        // Extract the ID (the last part of spotify:type:ID)
        guard let id = uri.components(separatedBy: ":").last else { return nil }
        
        // Construct the standard Spotify API URL
        let urlString = "https://api.spotify.com/v1/\(endpoint)/\(id)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            // This assumes your performSpotifyRequest handles the Bearer Token
            // and decodes a JSON structure containing a "name" key.
            let response: SpotifyNameResponse = try await performSpotifyRequest(url: url)
            return response.name
        } catch {
            print("⚠️ Could not resolve \(endpoint) name for ID \(id)")
            return nil
        }
    }
    
    private var lastTransferTime: Date = .distantPast

    func hijackPlayback() async {
        // 1. Cooldown Guard
        let now = Date()
        if now.timeIntervalSince(lastTransferTime) < 10 {
            print("⏳ Hijack ignored: Too soon since last transfer.")
            return
        }

        // 2. Local Config Guard
        let targetName = getDeviceNameFromConfig()
        print("[API] Attempting to hijack playback to '\(targetName)'...")

        // 3. Network Call using the Helper
        guard let url = URL(string: "https://api.spotify.com/v1/me/player/devices") else { return }

        do {
            let response: SpotifyDeviceResponse? = try await performSpotifyRequest(url: url)
            
            // 4. Manual Device Match
            if let devices = response?.devices,
               let targetDevice = devices.first(where: { $0.name == targetName }) {
                
                print("🎯 Found Hijack Target: \(targetDevice.name) (ID: \(targetDevice.id))")
                
                // 5. Execute Transfer (Spotify Cloud)
                await performTransfer(to: targetDevice.id)
                
                try? await Task.sleep(nanoseconds: 1_500_000_000)

                await self.startLocalPlayback()
                
                self.lastTransferTime = Date()
                
            } else {
                print("❌ Hijack Error: Could not find '\(targetName)'")
            }
        } catch {
            print("❌ Hijack Discovery Error: \(error.localizedDescription)")
        }
    }
    
    private func startLocalPlayback() async {
        // Hits the local engine directly
        guard let url = URL(string: "http://localhost:8888/player/resume") else { return }
        
        do {
            let _: [String: String]? = try await performSpotifyRequest(url: url, method: "POST")
            print("▶️ Local Start: Syncing G4 and Spotify Cloud")
        } catch {
            print("⚠️ Local Start failed: \(error.localizedDescription)")
        }
    }
    
    private func performTransfer(to deviceId: String) async {
        guard let url = URL(string: "https://api.spotify.com/v1/me/player") else { return }
        let body: [String: Any] = ["device_ids": [deviceId], "play": false]
        
        do {
            // Use [String: String] as a generic 'catch-all' for the dummy {}
            let _: [String: String] = try await performSpotifyRequest(url: url, method: "PUT", body: body)
            print("✓ Playback successfully transferred to \(deviceId)")
        } catch {
            print("❌ Transfer failed: \(error.localizedDescription)")
        }
    }
    
    private func getDeviceNameFromConfig() -> String {
        let fileManager = FileManager.default
        guard let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return "TigerTunes" // Ultimate fallback
        }
        
        let configPath = appSupportDir.appendingPathComponent("engine_state/config.yml")
        
        do {
            let content = try String(contentsOf: configPath, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            
            // Find the line that looks like: device_name: "Your Name"
            for line in lines where line.contains("device_name:") {
                let parts = line.components(separatedBy: ":")
                if parts.count > 1 {
                    return parts[1]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "\"", with: "")
                        .replacingOccurrences(of: "'", with: "")
                }
            }
        } catch {
            print("⚠️ Warning: Could not read config.yml, using default name.")
        }
        
        return "TigerTunes"
    }
    
    
    struct SpotifyDeviceResponse: Codable {
        let devices: [SpotifyDevice]
    }

    struct SpotifyDevice: Codable {
        let id: String
        let name: String
    }
    
    // Updated: refresh_token is optional for refresh calls
    struct SpotifyTokenResponse: Codable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
    }
}
