//
//  ContentView.swift
//  Tiger Tunes Bridge
//
//  Created by Danny Herrmann on 2/26/26.
//

//
//  ContentView.swift
//  Tiger Tunes Bridge
//
//  Created by Danny Herrmann on 2/26/26.
//

import SwiftUI
import AuthenticationServices

struct ContentView: View {
    @EnvironmentObject var engine: TigerTunesEngine
    @EnvironmentObject var spotifyAPI: SpotifyAPIController
    
    @State private var showLogs = false

    var body: some View {
        VStack(spacing: 0) {
            // --- STATUS HEADER ---
            HStack {
                Circle()
                    .fill(engine.isRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                
                Text(engine.isRunning ? "BRIDGE ACTIVE" : "BRIDGE OFFLINE")
                    .font(.system(size: 10, weight: .black))
                    .tracking(2)
            }
            .padding(.vertical, 15)

            // --- MAIN CONTENT AREA ---
            VStack {
                if !engine.isRunning {
                    // 1. SETUP & MODE SELECTION (Engine Offline)
                    VStack(spacing: 30) {
                        VStack(spacing: 8) {
                            Text("TigerTunes Setup")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                            Text("Configure your bridge settings below.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        // LEGACY MAC NAMING
                        VStack(alignment: .leading, spacing: 8) {
                            Text("LEGACY MAC NAME")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(.secondary)
                                .tracking(1)

                            TextField("e.g. iMac G4", text: $engine.deviceName)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .background(Color.black.opacity(0.05))
                                .cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.2)))
                        }
                        .padding(.horizontal, 50)
                        
                        HStack(spacing: 20) {
                            ModeButton(
                                title: "AirPlay Device",
                                subtitle: "Receiver Mode",
                                icon: "airplayaudio",
                                color: .blue
                            ) {
                                engine.updateConfigIfNeeded() // Sync name to YAML
                                engine.startEngine(api: spotifyAPI, mode: .airplayOnly)
                            }
                            
                            ModeButton(
                                title: "Spotify Connect",
                                subtitle: "Controller Mode",
                                icon: "antenna.radiowaves.left.and.right",
                                color: .green
                            ) {
                                engine.updateConfigIfNeeded() // Sync name to YAML
                                engine.startEngine(api: spotifyAPI, mode: .spotifyOnly)
                            }
                        }
                    }
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    
                } else {
                    // 2. ACTIVE ENGINE VIEW (Engine Online)
                    VStack(spacing: 25) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 30)
                                .fill(Color.black.opacity(0.05))
                                .frame(width: 180, height: 180)
                            
                            Image(systemName: engine.selectedMode == .airplayOnly ? "airplayaudio" : "antenna.radiowaves.left.and.right")
                                .font(.system(size: 70))
                                .symbolEffect(.variableColor.iterative, isActive: engine.isRunning)
                                .foregroundColor(engine.selectedMode == .airplayOnly ? .blue : .green)
                        }
                        
                        VStack(spacing: 12) {
                            Text(engine.selectedMode == .airplayOnly ? "AIRPLAY BRIDGE ACTIVE" : "SPOTIFY CONNECT ACTIVE")
                                .font(.headline)
                            
                            // DYNAMIC INSTRUCTION
                            Text(engine.selectedMode == .airplayOnly ?
                                 "Now open the TigerTunes Receiver app on your legacy Mac" :
                                 "Now open the TigerTunes Controller app on your legacy Mac")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        Button(action: { engine.stopEngine() }) {
                            Text("Stop Bridge")
                                .fontWeight(.bold)
                                .frame(width: 140, height: 35)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // --- FOOTER: AUTH & UTILS ---
            VStack(spacing: 12) {
                if engine.selectedMode == .spotifyOnly && !engine.isAuthenticated {
                    AuthButtonSection()
                }

                HStack {
                    Menu {
                        Section("Session Management") {
                            Button(role: .destructive) { spotifyAPI.logout() } label: {
                                Label("Sign out of API", systemImage: "person.badge.minus")
                            }
                            Button(role: .destructive) { engine.logoutEngine() } label: {
                                Label("Reset Audio Engine", systemImage: "speaker.minus")
                            }
                        }
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 20)

                    Spacer()

                    Button(action: openDataFolder) {
                        Label("Data Folder", systemImage: "folder.badge.gearshape")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 25)
                .padding(.bottom, 10)
            }

            // --- DEBUG LOGS ---
            DisclosureGroup("Technical Logs", isExpanded: $showLogs) {
                LogView()
            }
            .padding(.horizontal)
            .padding(.bottom, 15)
        }
        .frame(width: 420, height: 620)
        .animation(.spring(), value: engine.isRunning)
    }

    // --- Sub-Components ---
    
    @ViewBuilder
    func AuthButtonSection() -> some View {
        VStack(spacing: 12) {
            if !spotifyAPI.isAuthorized {
                VStack(spacing: 8) {
                    Text("Step 1: Link your Spotify Account")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        spotifyAPI.login(presentationContext: AuthWindowProvider())
                    }) {
                        Label("Authorize TigerTunes API", systemImage: "key.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
            }
            else if !engine.isAuthenticated {
                VStack(spacing: 8) {
                    Text("Step 2: Link the Audio Engine")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let authLine = engine.logMessages.first(where: { $0.contains("http") }),
                       let url = extractURL(from: authLine) {
                        Button(action: { NSWorkspace.shared.open(url) }) {
                            Label("Authorize Audio Engine", systemImage: "music.note.house")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    } else {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Waiting for Engine logs...")
                                .font(.caption2)
                                .italic()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 40)
        .transition(.opacity)
    }

    @ViewBuilder
    func LogView() -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(engine.logMessages, id: \.self) { msg in
                        Text(msg)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: 80)
            .onChange(of: engine.logMessages) { _ in
                proxy.scrollTo(engine.logMessages.last, anchor: .bottom)
            }
        }
    }

    func extractURL(from text: String) -> URL? {
        let pattern = "https?://[^\"\\s]+"
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return URL(string: String(text[range]))
    }
    
    func openDataFolder() {
        if let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let engineStateDir = appSupportDir.appendingPathComponent("engine_state")
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: engineStateDir.path)
        }
    }
}

// --- MODE BUTTON UI COMPONENT ---
struct ModeButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 30))
                    .foregroundColor(color)
                
                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(width: 160, height: 130)
            .background(Color.white.opacity(0.05))
            .background(isHovering ? color.opacity(0.1) : Color.clear)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isHovering ? color : Color.gray.opacity(0.2), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .onHover { over in isHovering = over }
    }
}

class AuthWindowProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApplication.shared.windows.first { $0.isKeyWindow } ?? NSWindow()
    }
}
