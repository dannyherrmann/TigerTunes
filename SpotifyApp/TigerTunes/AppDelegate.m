#import "AppDelegate.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <QuartzCore/QuartzCore.h>
#import "CJSONDeserializer.h"

// --- TIGER PERFORMANCE MACRO ---
#define TIGER_RELEASE 1

#if TIGER_RELEASE
    #define NSLog(...)
#endif

@implementation AppDelegate

- (void)awakeFromNib {
    // Set the window to a dark "Spotify Gray" (around #121212)
    NSColor *spotifyDark = [NSColor colorWithCalibratedRed:0.16 green:0.16 blue:0.16 alpha:1.0];
    [window setBackgroundColor:spotifyDark];
    if ([albumArtView respondsToSelector:@selector(setWantsLayer:)]) {
        [albumArtView setWantsLayer:YES];
        CALayer *layer = [albumArtView layer];
        
        // 1. Subtle Bezel (Hairline)
        // Instead of a dark border, use a light one at very low opacity.
        // This looks like a highlight on the edge of the "physical" record.
        layer.borderColor = [[NSColor colorWithCalibratedWhite:1.0 alpha:0.15] CGColor];
        layer.borderWidth = 0.5; // Hairline looks much more premium on PPC
        
        // 2. Focused Tiger Shadow
        // Reducing radius from 8.0 to 4.0 makes it look "closer" to the window.
        layer.shadowColor = [[NSColor blackColor] CGColor];
        layer.shadowOpacity = 0.7;
        layer.shadowOffset = CGSizeMake(0, -2); // Tighter offset
        layer.shadowRadius = 4.0;
        
        // 3. Vintage Corner Radius
        // 6.0 is a bit modern; 4.0 is that classic "Apple Gadget" roundness.
        layer.cornerRadius = 4.0;
        layer.masksToBounds = NO;
        
        // Performance optimization for G4
        layer.edgeAntialiasingMask = kCALayerLeftEdge | kCALayerRightEdge | kCALayerBottomEdge | kCALayerTopEdge;
        
    } else {
        // Fallback for very old Tiger builds
        [albumArtView setImageFrameStyle:NSImageFrameNone];
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [window setOpaque:YES];
    [window display];
    currentTrackDurationMs = 0;
    currentTrackPositionMs = 0;
    isPlaying = NO;
    [statusLabel setStringValue:@"Looking for server..."];
    [playPauseButton setEnabled:NO];
    [nextButton setEnabled:NO];
    [previousButton setEnabled:NO];
    
    // Start looking for Spotify-lite server
    [self startServerDiscovery];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    if (apiBaseURL) {
        NSString *pauseURL = [NSString stringWithFormat:@"%@/player/pause", apiBaseURL];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:pauseURL]];
        [request setHTTPMethod:@"POST"];
        [request setTimeoutInterval:1.0];
        
        [NSURLConnection sendSynchronousRequest:request returningResponse:nil error:nil];
        NSLog(@"Paused playback on quit");
    }
    
    // Give it a moment to process
    [NSThread sleepForTimeInterval:0.5];
    // Kill audio client when app quits
    if (audioClientTask && [audioClientTask isRunning]) {
        NSLog(@"Stopping audio client...");
        [audioClientTask terminate];
    }
}

- (void)startServerDiscovery {
    serviceBrowser = [[NSNetServiceBrowser alloc] init];
    [serviceBrowser setDelegate:self];
    [serviceBrowser searchForServicesOfType:@"_spotify-tt._tcp." inDomain:@"local."];
    
    NSLog(@"🔍 Searching for TigerTunes Spotify service...");
}

#pragma mark - NSNetServiceBrowser Delegate

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
           didFindService:(NSNetService *)service
               moreComing:(BOOL)moreComing {
    
    NSLog(@"✓ Found service: %@", [service name]);
    
    // Resolve the service to get IP address
    if (currentService) {
        [currentService release];
    }
    currentService = [service retain];
    [currentService setDelegate:self];
    [currentService resolveWithTimeout:5.0];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
         didRemoveService:(NSNetService *)service
               moreComing:(BOOL)moreComing {
    
    NSLog(@"⚠️ Server disappeared: %@", [service name]);
    [statusLabel setStringValue:@"Server disconnected"];
    [playPauseButton setEnabled:NO];
    [nextButton setEnabled:NO];
    [previousButton setEnabled:NO];
}

#pragma mark - NSNetService Delegate

- (void)netServiceDidResolveAddress:(NSNetService *)service {
    NSArray *addresses = [service addresses];
    if ([addresses count] == 0) return;
    
    // 1. Get the IP Address only
    NSData *addressData = [addresses objectAtIndex:0];
    struct sockaddr_in *socketAddress = (struct sockaddr_in *)[addressData bytes];
    
    if (serverIP) [serverIP release];
    serverIP = [[NSString stringWithFormat:@"%s", inet_ntoa(socketAddress->sin_addr)] retain];
    
    // 2. Hardcode ports back to the Spotify defaults
    // Metadata remains 5003, API remains 5002
    if (apiBaseURL) [apiBaseURL release];
    apiBaseURL = [[NSString stringWithFormat:@"http://%@:8888", serverIP] retain];
    
    NSLog(@"✓ Connected to Spotify Bridge at %@", serverIP);
    
    [statusLED setTextColor:[NSColor greenColor]];
    [statusLabel setStringValue:[NSString stringWithFormat:@"Connected to %@", [service name]]];
    
    [serviceBrowser stop];
    
    // 3. Setup Listeners with fixed Spotify ports
    [self displayProfileImage:serverIP];
    [self setupMetadataListener:serverIP port:5003]; // Spotify Metadata is 5003
    
    [self performSelector:@selector(startAudioClient) withObject:nil afterDelay:1.0];
    [self performSelector:@selector(triggerSpotifyConnect:) withObject:serverIP afterDelay:5.0];
}

- (void)netService:(NSNetService *)service didNotResolve:(NSDictionary *)errorDict {
    NSLog(@"❌ Could not resolve service: %@", errorDict);
    [statusLabel setStringValue:@"Could not connect to server"];
}

#pragma mark - Audio Client

- (void)startAudioClient {
    // 1. SAFETY CHECK: Ensure we have a valid IP string.
    // This prevents the "attempt to insert nil object" crash in [NSArray arrayWithObject:]
    if (serverIP == nil || [serverIP length] == 0) {
        NSLog(@"⚠️ Audio Client aborted: serverIP is nil or empty.");
        [statusLabel setStringValue:@"Connection error - retrying..."];
        return;
    }

    NSLog(@"🚀 Starting audio client with IP: %@", serverIP);
    
    // 2. PATH SETUP
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSString *macosPath = [bundlePath stringByAppendingPathComponent:@"Contents/MacOS"];
    NSString *clientPath = [macosPath stringByAppendingPathComponent:@"TigerTunesClient"];
    
    // 3. FILE VERIFICATION
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:clientPath];
    if (!exists) {
        NSLog(@"❌ Audio client binary not found at: %@", clientPath);
        [statusLabel setStringValue:@"Error: Audio client missing"];
        return;
    }
    
    // 4. TASK INITIALIZATION
    // If a task is already running (e.g., from a previous fast-reconnect), terminate it
    if (audioClientTask && [audioClientTask isRunning]) {
        [audioClientTask terminate];
        [audioClientTask release];
        audioClientTask = nil;
    }

    audioClientTask = [[NSTask alloc] init];
    [audioClientTask setLaunchPath:clientPath];
    
    // We already verified serverIP isn't nil, so this is now safe
    NSArray *args = [NSArray arrayWithObject:serverIP];
    [audioClientTask setArguments:args];
    
    // 5. LAUNCH
    @try {
        [audioClientTask launch];
        NSLog(@"✓ TigerTunesClient successfully launched.");
    } @catch (NSException *exception) {
        NSLog(@"❌ Failed to launch task: %@", [exception reason]);
        [statusLabel setStringValue:@"Failed to start audio engine"];
    }
}

- (void)setupMetadataListener:(NSString *)ip port:(int)port {
    if (!ip || port <= 0) {
        NSLog(@"⚠️ Cannot setup metadata listener: invalid IP or Port");
        return;
    }

    // Close existing stream if reconnecting
    if (metadataInputStream) {
        [metadataInputStream close];
        [metadataInputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [metadataInputStream release];
        metadataInputStream = nil;
    }

    NSInputStream *tempIn;
    // Connect to the actual port resolved via Bonjour
    [NSStream getStreamsToHost:[NSHost hostWithAddress:ip]
                          port:port
                   inputStream:&tempIn
                  outputStream:nil];
    
    metadataInputStream = [tempIn retain];
    [metadataInputStream setDelegate:self];
    [metadataInputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [metadataInputStream open];
    
    NSLog(@"📡 Metadata stream opened on %@:%d", ip, port);
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
    switch (eventCode) {
        case NSStreamEventHasBytesAvailable: {
            uint8_t buffer[8192];
            int len = [(NSInputStream *)aStream read:buffer maxLength:sizeof(buffer)];
            
            if (len > 0) {
                NSString *rawContent = [[[NSString alloc] initWithBytes:buffer
                                                                 length:len
                                                               encoding:NSUTF8StringEncoding] autorelease];
                
                NSArray *packets = [rawContent componentsSeparatedByString:@"\n"];
                
                int i;
                for (i = 0; i < [packets count]; i++) {
                    NSString *singlePacket = [packets objectAtIndex:i];
                    if ([singlePacket rangeOfString:@"{\"type\":"].location != NSNotFound) {
                        [self handleRemoteEvent:singlePacket];
                    }
                }
                [[statusLabel window] displayIfNeeded];
            }
            break;
        }

        case NSStreamEventEndEncountered:
        case NSStreamEventErrorOccurred: {
            NSLog(@"⚠️ Metadata Stream Lost (Server Dropped)");
            [self handleServerDisconnect];
            break;
        }
            
        case NSStreamEventOpenCompleted:
            NSLog(@"📡 Metadata Stream Connected and Ready");
            break;

        default:
            break;
    }
}

- (void)handleServerDisconnect {
    NSString *lostServiceName = @"Server"; // Fallback
    if (currentService) {
        lostServiceName = [currentService name];
    }
    // 1. Stop the local drift timer immediately
    [self stopDriftTimer];
    
    [statusLED setTextColor:[NSColor redColor]];
    [statusLabel setStringValue:[NSString stringWithFormat:@"Disconnected from %@", lostServiceName]];
    
    // 2. Clear the UI so the user knows what happened
    //[statusLabel setStringValue:@"Disconnected from Spotify Bridge"];
    //[trackNameLabel setStringValue:@"Server Lost"];
    //[artistLabel setStringValue:@"Check MacBook Air"];
    
    // 3. Disable the controls
    [playPauseButton setEnabled:NO];
    [nextButton setEnabled:NO];
    [previousButton setEnabled:NO];

    if (audioClientTask && [audioClientTask isRunning]) {
        NSLog(@"Stopping audio client task...");
        [audioClientTask terminate];
        [audioClientTask release];
        audioClientTask = nil;
    }

    system("killall TigerTunesClient");

    // 4. RESET DISCOVERY (The new part)
    if (serviceBrowser) {
        [serviceBrowser stop];
        [serviceBrowser release];
        serviceBrowser = nil;
    }
    
    if (currentService) {
        [currentService release];
        currentService = nil;
    }
    
    if (serverIP) {
        [serverIP release];
        serverIP = nil;
    }

    // 4. Close and nullify the broken stream
    if (metadataInputStream) {
        [metadataInputStream close];
        [metadataInputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [metadataInputStream release];
        metadataInputStream = nil;
    }

    isConnectTriggered = NO;

    // 5. Trigger a fresh search for the server
    [self startServerDiscovery];
}

- (BOOL)isPlaying {
    return isPlaying;
}

- (void)triggerSpotifyConnect:(NSString *)serverIP {
    if (isConnectTriggered) {
        return;
    }

    isConnectTriggered = YES;
    
    NSString *urlPath = [NSString stringWithFormat:@"http://%@:5002/connect", serverIP];
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:urlPath]];
    
    // Start the connection; the delegate methods (or lack thereof) will handle it.
    // If you don't care about the response body, you can just fire and forget:
    [NSURLConnection connectionWithRequest:request delegate:nil];
}

- (void)loadUserProfile {
    NSString *urlStr = [NSString stringWithFormat:@"http://%@:5002/connect", serverIP];
}

- (void)handleRemoteEvent:(NSString *)json {
    NSData *jsonData = [json dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSDictionary *fullDict = [[CJSONDeserializer deserializer] deserializeAsDictionary:jsonData error:&error];
    
    if (error || !fullDict) {
        NSLog(@"❌ JSON Parse Error: %@", error);
        return;
    }

    NSString *type = [fullDict objectForKey:@"type"];
    NSDictionary *data = [fullDict objectForKey:@"data"];

    // --- CASE 5: INACTIVE (Playback Transferred Away) ---
    // We check this FIRST to lock the UI down before any other processing
    if ([type isEqualToString:@"inactive"]) {
        NSLog(@"🔄 Playback Transferred Away - Entering Passive Mode");
        [self performSelectorOnMainThread:@selector(stopDriftTimer) withObject:nil waitUntilDone:NO];
        [self performSelectorOnMainThread:@selector(resetUIForInactiveState) withObject:nil waitUntilDone:NO];
        return; // EXIT EARLY: Do not re-enable buttons
    }

    // --- CASE 1: METADATA RECEIVED ---
    if ([type isEqualToString:@"metadata"]) {
        NSLog(@"🎵 New Metadata Received");
        
        // RE-ENABLE CONTROLS: Now that we have fresh track data, it's safe to use buttons again
        [self performSelectorOnMainThread:@selector(enableControls) withObject:nil waitUntilDone:NO];

        currentTrackPositionMs = 0;
        NSString *trackName = [data objectForKey:@"name"];
        NSArray *artistNames = [data objectForKey:@"artist_names"];
        NSString *artistName = (artistNames && [artistNames count] > 0) ? [artistNames objectAtIndex:0] : @"Unknown Artist";
        NSString *artURL = [data objectForKey:@"album_cover_url"];
        
        NSNumber *durationNum = [data objectForKey:@"duration"];
        if (durationNum) currentTrackDurationMs = [durationNum longLongValue];

        NSNumber *posNum = [data objectForKey:@"position"];
        if (posNum) currentTrackPositionMs = [posNum longValue];

        if (trackName) {
            [trackNameLabel performSelectorOnMainThread:@selector(setStringValue:) withObject:trackName waitUntilDone:NO];
            [trackNameLabel performSelectorOnMainThread:@selector(startScrolling) withObject:nil waitUntilDone:NO];
        }
        if (artistName) [artistLabel performSelectorOnMainThread:@selector(setStringValue:) withObject:artistName waitUntilDone:NO];
        if (artURL && [artURL length] > 0) {
            [self performSelectorOnMainThread:@selector(downloadAndDisplayAlbumArt:) withObject:artURL waitUntilDone:NO];
        }
    }
    
    // --- CASE 2: PLAYING ---
    else if ([type isEqualToString:@"playing"]) {
        isPlaying = YES;
        NSString *ctxURI = [data objectForKey:@"context_uri"];
        if (ctxURI && ![ctxURI isEqualToString:@"null"]) {
            [self fetchEnrichedStatus:ctxURI];
        }
        [self performSelectorOnMainThread:@selector(startDriftTimer) withObject:nil waitUntilDone:NO];
        [playPauseButton performSelectorOnMainThread:@selector(setTitle:) withObject:@"⏸" waitUntilDone:NO];
    }
    
    // --- CASE 3: PAUSED / NOT PLAYING ---
    else if ([type isEqualToString:@"paused"] || [type isEqualToString:@"not_playing"]) {
        isPlaying = NO;
        [self performSelectorOnMainThread:@selector(stopDriftTimer) withObject:nil waitUntilDone:NO];
        [playPauseButton performSelectorOnMainThread:@selector(setTitle:) withObject:@"▶︎" waitUntilDone:NO];
    }
    
    // --- CASE 4: SEEK ---
    else if ([type isEqualToString:@"seek"]) {
        NSNumber *posNum = [data objectForKey:@"position"];
        if (posNum) currentTrackPositionMs = [posNum longValue];
        [self performSelectorOnMainThread:@selector(updateProgressBarUI) withObject:nil waitUntilDone:NO];
    }
    
    // --- CASE 6: STOPPED ---
    else if ([type isEqualToString:@"stopped"]) {
        isPlaying = NO;
        [self performSelectorOnMainThread:@selector(stopDriftTimer) withObject:nil waitUntilDone:NO];
        [playPauseButton performSelectorOnMainThread:@selector(setTitle:) withObject:@"▶︎" waitUntilDone:NO];
        [progressBar performSelectorOnMainThread:@selector(setProgress:) withObject:[NSNumber numberWithDouble:0.0] waitUntilDone:NO];
    }
}

// Helper: Cleans the UI and locks the buttons to prevent go-librespot crashes
- (void)resetUIForInactiveState {
    [trackNameLabel setStringValue:@""];
    [artistLabel setStringValue:@""];
    [contextLabel setStringValue:@"Playback Transferred"];
    [contextLabel setHidden:NO];
    [startLabel setStringValue:@""];
    [endLabel setStringValue:@""];
    [progressBar setProgress:0.0];
    [albumArtView setImage:nil];
    
    [playPauseButton setEnabled:NO];
    [nextButton setEnabled:NO];
    [previousButton setEnabled:NO];
}

// Helper: Re-unlocks the UI when a valid local track is loaded
- (void)enableControls {
    [playPauseButton setEnabled:YES];
    [nextButton setEnabled:YES];
    [previousButton setEnabled:YES];
}

- (void)fetchEnrichedStatus:(NSString *)uri {
    if (!uri || [uri isEqualToString:@"null"]) return;

    NSString *encodedURI = [uri stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString *urlStr = [NSString stringWithFormat:@"http://%@:5002/resolve_context?uri=%@", serverIP, encodedURI];
    
    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:urlStr] 
                                         cachePolicy:NSURLRequestReloadIgnoringLocalCacheData 
                                     timeoutInterval:2.0];
    
    NSData *data = [NSURLConnection sendSynchronousRequest:req returningResponse:nil error:nil];
    
    if (data && [data length] > 0) {
        NSError *error = nil;
        // USE THE NEW LIBRARY HERE
        NSDictionary *dict = [[CJSONDeserializer deserializer] deserializeAsDictionary:data error:&error];
        
        if (!error && dict) {
            NSString *contextName = [dict objectForKey:@"name"];
            NSLog(@"✅ Cleaned Context Name: %@", contextName);
            
            if (contextName && (id)contextName != [NSNull null]) {
                // Update UI on Main Thread
                [contextLabel performSelectorOnMainThread:@selector(setStringValue:) 
                                               withObject:contextName 
                                            waitUntilDone:NO];
                [contextLabel setHidden:NO];
                
                // If context name is long, start the ping-pong scroll!
                if ([contextLabel respondsToSelector:@selector(startScrolling)]) {
                    [contextLabel performSelectorOnMainThread:@selector(startScrolling) 
                                                   withObject:nil 
                                                waitUntilDone:NO];
                }
            } else {
                [contextLabel setHidden:YES];
            }
        }
    }
}

- (void)startDriftTimer {
    // Kill any existing timer first to avoid multiple timers running
    [self stopDriftTimer];
    
    // Create a timer that ticks every 1 second locally
    driftTimer = [[NSTimer scheduledTimerWithTimeInterval:1.0
                                                   target:self
                                                 selector:@selector(driftTick)
                                                 userInfo:nil
                                                  repeats:YES] retain];
    NSLog(@"⏰ Drift Timer Started");
}

- (void)stopDriftTimer {
    if (driftTimer) {
        [driftTimer invalidate];
        [driftTimer release];
        driftTimer = nil;
        NSLog(@"🛑 Drift Timer Stopped");
    }
}

- (void)driftTick {
    if (isPlaying) {
        // Increment our local knowledge of the position
        currentTrackPositionMs += 1000;
        
        // Update the UI (Progress bar and labels)
        [self updateProgressBarUI];
    }
}

- (void)updateProgressBarUI {
    if (currentTrackDurationMs > 0) {
        double ratio = (double)currentTrackPositionMs / (double)currentTrackDurationMs;
        [progressBar setProgress:ratio];
        [startLabel setStringValue:[self formatTime:currentTrackPositionMs / 1000]];
        [endLabel setStringValue:[NSString stringWithFormat:@"-%@", [self formatTime:(currentTrackDurationMs - currentTrackPositionMs) / 1000]]];
    }
}

#pragma mark - Seek Logic

#pragma mark - Seek Logic

- (void)userDidSeekToPercentage:(double)pct {
    if (!apiBaseURL || currentTrackDurationMs <= 0) return;
    
    // 1. Store the target for the background thread
    lastSeekTargetMs = (long)(pct * currentTrackDurationMs);
    
    NSLog(@"--- SEEK ATTEMPT ---");
    NSLog(@"Target Ms: %ld", lastSeekTargetMs);
    
    // 2. Launch the network request in a background thread
    // This keeps the UI (4% CPU) from freezing while waiting for the server
    [NSThread detachNewThreadSelector:@selector(performSeekRequest) toTarget:self withObject:nil];
}

- (void)performSeekRequest {
    // Every background thread in Cocoa needs its own Autorelease Pool
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    NSString *seekURL = [NSString stringWithFormat:@"%@/player/seek", apiBaseURL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:seekURL]];
    
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setTimeoutInterval:5.0];

    // 3. Manually construct the JSON body string as per the API spec
    NSString *jsonBody = [NSString stringWithFormat:@"{\"position\": %ld}", lastSeekTargetMs];
    NSData *bodyData = [jsonBody dataUsingEncoding:NSUTF8StringEncoding];
    [request setHTTPBody:bodyData];
    
    NSLog(@"Sending JSON to %@: %@", seekURL, jsonBody);

    // 4. Perform the request
    NSError *error = nil;
    NSURLResponse *response = nil;
    [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    
    if (error) {
        NSLog(@"❌ Seek Error: %@", [error localizedDescription]);
    } else {
        NSLog(@"✓ Seek Accepted by Server");
    }
    
    [pool release];
}

- (void)downloadAndDisplayAlbumArt:(NSString *)urlString {
    NSLog(@"downloadAndDisplayAlbumArt called with URL: %@", urlString);
    
    if (!urlString || [urlString length] == 0) {
        NSLog(@"❌ Album art URL is empty or nil");
        return;
    }
    
    NSString *encodedURL = [urlString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString *proxyURL = [NSString stringWithFormat:@"http://%@:5002/album_art_proxy?url=%@", serverIP, encodedURL];
    
    NSLog(@"📥 Downloading via proxy: %@", proxyURL);
    
    NSURL *url = [NSURL URLWithString:proxyURL];
    if (!url) {
        NSLog(@"❌ Failed to create NSURL");
        return;
    }

    [[NSURLCache sharedURLCache] removeCachedResponseForRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:urlString]]];

    NSURLRequest *request = [NSURLRequest requestWithURL:url
                                             cachePolicy:NSURLRequestReturnCacheDataElseLoad
                                         timeoutInterval:10.0];
    
    NSURLResponse *response = nil;
    NSError *error = nil;
    NSData *imageData = [NSURLConnection sendSynchronousRequest:request
                                              returningResponse:&response
                                                          error:&error];
    
    if (error || !imageData) {
        NSLog(@"❌ Failed to download: %@", error);
        return;
    }
    
    NSLog(@"✓ Downloaded %lu bytes", (unsigned long)[imageData length]);
    
    NSImage *image = [[NSImage alloc] initWithData:imageData];
    if (!image) {
        NSLog(@"❌ Failed to create NSImage");
        return;
    }
    
    NSLog(@"✓ Original size: %.0fx%.0f", [image size].width, [image size].height);
    
    // FORCE the image size to match the view size
    NSSize viewSize = [albumArtView bounds].size;
    [image setSize:viewSize];
    
    NSLog(@"✓ Resized to: %.0fx%.0f", viewSize.width, viewSize.height);
    
    // Now set it
    [albumArtView setImage:image];
    
    NSLog(@"✓ Album art displayed!");
    
    [image release];
}

- (void)displayProfileImage:(NSString *)sIP {
    // 1. Setup the Proxy URL
    NSString *proxyURL = [NSString stringWithFormat:@"http://%@:5002/profile_image_proxy", sIP];
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:proxyURL]
                                             cachePolicy:NSURLRequestReturnCacheDataElseLoad
                                         timeoutInterval:5.0];
    
    // 2. Synchronous download (The pattern you prefer)
    NSData *imageData = [NSURLConnection sendSynchronousRequest:request returningResponse:nil error:nil];
    
    if (imageData) {
        NSImage *rawImage = [[NSImage alloc] initWithData:imageData];
        if (rawImage) {
            // 3. Get the size of your UI element from the .xib
            NSSize viewSize = [userProfileImageView frame].size;
            
            // 4. Transform the square into the Dosdude1 Circle
            NSImage *finalCircle = [self processProfileImage:rawImage newSize:viewSize];
            
            // 5. Update UI
            [userProfileImageView setImage:finalCircle];
            
            [rawImage release];
            NSLog(@"✓ Profile circle rendered at %.0fx%.0f", viewSize.width, viewSize.height);
        }
    } else {
        NSLog(@"❌ Failed to fetch profile image data");
    }
}

- (NSImage *)processProfileImage:(NSImage *)anImage newSize:(NSSize)newSize {
    [anImage setScalesWhenResized:YES];
    
    // 1. Force a perfect square canvas
    float dimension = MIN(newSize.width, newSize.height);
    NSSize squareSize = NSMakeSize(dimension, dimension);
    NSImage *smallImage = [[[NSImage alloc] initWithSize:squareSize] autorelease];
    
    // 2. ASPECT RATIO FIX: Calculate the center square of the original photo
    NSSize origSize = [anImage size];
    float minDim = MIN(origSize.width, origSize.height);
    
    // This creates a square starting from the middle of your wide photo
    NSRect srcRect = NSMakeRect((origSize.width - minDim) / 2.0,
                                (origSize.height - minDim) / 2.0,
                                minDim, minDim);
    
    [smallImage lockFocus];
    [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
    
    // 3. DOSDUDE1 ARC MATH (The "Circle Window")
    float radius = dimension / 2.0;
    NSRect destRect = NSMakeRect(0, 0, dimension, dimension);
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(radius / 2.0, 0)];
    [path lineToPoint:NSMakePoint(destRect.size.width - (radius / 2.0), 0)];
    [path appendBezierPathWithArcFromPoint:NSMakePoint(destRect.size.width, 0) toPoint:NSMakePoint(destRect.size.width, radius / 2.0) radius:radius];
    [path lineToPoint:NSMakePoint(destRect.size.width, destRect.size.height - (radius / 2.0))];
    [path appendBezierPathWithArcFromPoint:NSMakePoint(destRect.size.width, destRect.size.height) toPoint:NSMakePoint(destRect.size.width - (radius / 2.0), destRect.size.height) radius:radius];
    [path lineToPoint:NSMakePoint(radius / 2.0, destRect.size.height)];
    [path appendBezierPathWithArcFromPoint:NSMakePoint(0, destRect.size.height) toPoint:NSMakePoint(0, destRect.size.height - (radius / 2.0)) radius:radius];
    [path lineToPoint:NSMakePoint(0, radius / 2.0)];
    [path appendBezierPathWithArcFromPoint:NSMakePoint(0, 0) toPoint:NSMakePoint(radius / 2.0, 0) radius:radius];
    
    [path setWindingRule:NSEvenOddWindingRule];
    [path addClip];
    
    // 4. DRAW: We draw the 'srcRect' (center square) into 'destRect' (the circle)
    // We use a -1.0 inset to ensure no gaps at the edges
    [anImage drawInRect:NSInsetRect(destRect, -1.0, -1.0)
               fromRect:srcRect
              operation:NSCompositeSourceOver
               fraction:1.0];
    
    [smallImage unlockFocus];
    return smallImage;
}

#pragma mark - Button Actions

- (IBAction)playPausePressed:(id)sender {
    NSLog(@"🖱️ Play/Pause Clicked!");
    if (!apiBaseURL) return;
    
    NSString *endpoint = isPlaying ? @"/player/pause" : @"/player/resume";
    NSString *url = [NSString stringWithFormat:@"%@%@", apiBaseURL, endpoint];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    [request setHTTPMethod:@"POST"];
    [request setTimeoutInterval:2.0];
    
    NSURLResponse *response = nil;
    NSError *error = nil;
    [NSURLConnection sendSynchronousRequest:request
                          returningResponse:&response
                                      error:&error];
    
    if (!error) {
        NSLog(@"✓ Play/Pause toggled");
    }
}

- (IBAction)nextPressed:(id)sender {
    NSLog(@"🖱️ Next Clicked!");
    if (!apiBaseURL) return;
    
    NSString *url = [NSString stringWithFormat:@"%@/player/next", apiBaseURL];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    [request setHTTPMethod:@"POST"];
    [request setTimeoutInterval:2.0];
    
    NSURLResponse *response = nil;
    NSError *error = nil;
    [NSURLConnection sendSynchronousRequest:request
                          returningResponse:&response
                                      error:&error];
    
    if (!error) {
        NSLog(@"✓ Skipped to next track");
    }
}

- (IBAction)previousPressed:(id)sender {
    if (!apiBaseURL) return;
    
    NSString *url = [NSString stringWithFormat:@"%@/player/prev", apiBaseURL];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    [request setHTTPMethod:@"POST"];
    [request setTimeoutInterval:2.0];
    
    NSURLResponse *response = nil;
    NSError *error = nil;
    [NSURLConnection sendSynchronousRequest:request
                          returningResponse:&response
                                      error:&error];
    
    if (!error) {
        NSLog(@"✓ Went to previous track");
    }
}

- (NSString *)formatTime:(int)seconds {
    int hrs = seconds / 3600;
    int mins = (seconds % 3600) / 60;
    int secs = seconds % 60;

    if (hrs > 0) {
        // For Podcasts/Long Content: H:MM:SS
        return [NSString stringWithFormat:@"%d:%02d:%02d", hrs, mins, secs];
    } else {
        // For Standard Songs: M:SS
        return [NSString stringWithFormat:@"%d:%02d", mins, secs];
    }
}

- (void)dealloc {
    // 1. Stop active processes and timers FIRST
    if (audioClientTask) {
        if ([audioClientTask isRunning]) {
            [audioClientTask terminate];
            [audioClientTask waitUntilExit];
        }
        [audioClientTask release];
        audioClientTask = nil;
    }
    
    if (driftTimer) {
        [driftTimer invalidate];
        [driftTimer release];
        driftTimer = nil;
    }
    
    // 2. Tear down network services
    if (serviceBrowser) {
        [serviceBrowser stop];
        [serviceBrowser setDelegate:nil]; // Safety: don't call delegate on a dead object
        [serviceBrowser release];
    }
    
    if (metadataInputStream) {
        [metadataInputStream close];
        [metadataInputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [metadataInputStream setDelegate:nil];
        [metadataInputStream release];
    }
    
    // 3. Release retained strings and arrays
    [currentService release];
    [serverIP release];
    [apiBaseURL release];
    
    // 4. ALWAYS call super last
    [super dealloc];
}

@end