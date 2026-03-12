//
//  Tiger_Tunes_BridgeApp.swift
//  Tiger Tunes Bridge
//
//  Created by Danny Herrmann on 2/26/26.
//

import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    // We hold a weak reference so we don't interfere with the
    // StateObject's lifecycle
    var engine: TigerTunesEngine?
    
    func applicationWillTerminate(_ notification: Notification) {
        print("🚩 App is quitting. Cleaning up engine...")
        engine?.stopEngine()
    }
}

@main
struct Tiger_Tunes_BridgeApp: App {
    // 1. This lives for the life of the app
    @StateObject private var engine = TigerTunesEngine()
    @StateObject private var spotifyAPI = SpotifyAPIController()
    
    // 2. This listens to system-level 'Quit' events
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .environmentObject(spotifyAPI)
                .onAppear {
                    // 3. Link the two so the Delegate knows which engine to kill
                    appDelegate.engine = engine
                }
        }
    }
}
