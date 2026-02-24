#import <Cocoa/Cocoa.h>
#import "ITunesLCDView.h"
#import "WinampButton.h"

@interface AppDelegate : NSObject {
    // UI Elements
    IBOutlet NSTextField *statusLabel;
    IBOutlet NSTextField *trackNameLabel;
    IBOutlet NSTextField *artistLabel;
    IBOutlet NSTextField *startLabel;
    IBOutlet NSTextField *endLabel;
    IBOutlet NSTextField *contextLabel;
    IBOutlet NSImageView *albumArtView;
    IBOutlet NSImageView *userProfileImageView;
    IBOutlet ITunesLCDView *progressBar;
    IBOutlet WinampButton *playPauseButton;
    IBOutlet WinampButton *nextButton;
    IBOutlet WinampButton *previousButton;
    IBOutlet NSTextField *statusLED;
    IBOutlet NSWindow *window;
    
    // Networking
    NSNetServiceBrowser *serviceBrowser;
    NSNetService *currentService;
    NSString *serverIP;
    NSString *apiBaseURL;
    
    // Audio client
    NSTask *audioClientTask;
    
    // State
    BOOL isPlaying;
    BOOL isConnectTriggered;
    long currentTrackPositionMs;
    long currentTrackDurationMs;
    long lastSeekTargetMs;
    NSInputStream *metadataInputStream;
    NSTimer *driftTimer; // For smooth progress bar movement
}

// Button actions
- (IBAction)playPausePressed:(id)sender;
- (IBAction)nextPressed:(id)sender;
- (IBAction)previousPressed:(id)sender;

// Internal methods
- (void)displayProfileImage:(NSString *)sIP;
- (NSImage *)processProfileImage:(NSImage *)anImage newSize:(NSSize)newSize;
- (void)startServerDiscovery;
- (void)startAudioClient;
- (void)updateNowPlaying;
- (void)downloadAndDisplayAlbumArt:(NSString *)urlString;
- (NSString *)formatTime:(int)seconds;

@end