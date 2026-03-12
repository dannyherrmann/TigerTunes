//
//  AppDelegate.h
//  TigerTunesReceiver
//
//  Created by Danny Herrmann on 3/3/26.
//  Copyright (c) 2026 Danny Herrmann. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject {
    // UI Elements
    IBOutlet NSTextField *statusLabel;
    IBOutlet NSTextField *trackNameLabel;
    IBOutlet NSTextField *artistLabel;
    IBOutlet NSTextField *albumNameLabel;
    IBOutlet NSImageView *albumArtView;
    IBOutlet NSTextField *statusLED;
    IBOutlet NSWindow *window;
    
    // Networking
    NSNetServiceBrowser *serviceBrowser;
    NSNetService *currentService;
    NSString *serverIP;
    
    // Audio client (TigerTunesClient binary)
    NSTask *audioClientTask;
    
    // Metadata Stream
    NSInputStream *metadataInputStream;
    
    NSString *currentActiveTitle;
    NSString *lastDownloadedArtTitle;
}

- (void)startServerDiscovery;
- (void)startAudioClient;
- (void)setupMetadataListener:(NSString *)ip port:(int)port;

@end

