//
//  AppDelegate.m
//  TigerTunesReceiver
//
//  Created by Danny Herrmann on 3/3/26.
//  Copyright (c) 2026 Danny Herrmann. All rights reserved.
//

#import "AppDelegate.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <QuartzCore/QuartzCore.h>

// --- TIGER PERFORMANCE MACRO ---
#define TIGER_RELEASE 1

#if TIGER_RELEASE
    #define NSLog(...)
#endif

@implementation AppDelegate

- (void)awakeFromNib {
    NSColor *spotifyDark = [NSColor colorWithCalibratedRed:0.16 green:0.16 blue:0.16 alpha:1.0];
    [window setBackgroundColor:spotifyDark];
    [albumArtView setImageScaling:NSImageScaleProportionallyDown];
    [albumArtView setImageAlignment:NSImageAlignCenter];
    // Setup basic Album Art appearance
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
    
    [statusLabel setStringValue:@"Searching for TigerTunes Bridge..."];
    [self startServerDiscovery];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    // Give it a moment to process
    [NSThread sleepForTimeInterval:0.5];
    // Kill audio client when app quits
    if (audioClientTask && [audioClientTask isRunning]) {
        NSLog(@"Stopping audio client...");
        [audioClientTask terminate];
    }
}

#pragma mark - Bonjour Discovery

- (void)startServerDiscovery {
    serviceBrowser = [[NSNetServiceBrowser alloc] init];
    [serviceBrowser setDelegate:self];
    // Listen for the same service type as the Bridge
    [serviceBrowser searchForServicesOfType:@"_airplay-tt._tcp." inDomain:@"local."];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didFindService:(NSNetService *)service moreComing:(BOOL)moreComing {
    if (currentService) [currentService release];
    currentService = [service retain];
    [currentService setDelegate:self];
    [currentService resolveWithTimeout:5.0];
}

- (void)netServiceDidResolveAddress:(NSNetService *)service {
    NSArray *addresses = [service addresses];
    if ([addresses count] == 0) return;
    
    NSData *addressData = [addresses objectAtIndex:0];
    struct sockaddr_in *socketAddress = (struct sockaddr_in *)[addressData bytes];
    
    if (serverIP) [serverIP release];
    serverIP = [[NSString stringWithFormat:@"%s", inet_ntoa(socketAddress->sin_addr)] retain];
    
    [statusLED setTextColor:[NSColor greenColor]];
    [statusLabel setStringValue:[NSString stringWithFormat:@"Connected to %@", [service name]]];
    
    [serviceBrowser stop];
    
    // Setup Audio and Metadata (Port 5003 for AirPlay strings)
    [self setupMetadataListener:serverIP port:5003];
    [self performSelector:@selector(startAudioClient) withObject:nil afterDelay:0.5];
}

#pragma mark - Audio & Metadata

- (void)startAudioClient {
    if (!serverIP) return;
    
    // Standard Tiger-compatible way to find the MacOS folder
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSString *macosPath = [bundlePath stringByAppendingPathComponent:@"Contents/MacOS"];
    NSString *clientPath = [macosPath stringByAppendingPathComponent:@"TigerTunesClient"];
    
    if (audioClientTask && [audioClientTask isRunning]) {
        [audioClientTask terminate];
        [audioClientTask release];
    }

    audioClientTask = [[NSTask alloc] init];
    [audioClientTask setLaunchPath:clientPath];
    [audioClientTask setArguments:[NSArray arrayWithObject:serverIP]];
    
    @try {
        [audioClientTask launch];
        NSLog(@"✓ Audio Engine Started");
    } @catch (NSException *e) {
        [statusLabel setStringValue:@"Audio Engine Error"];
    }
}

- (void)setupMetadataListener:(NSString *)ip port:(int)port {
    NSInputStream *tempIn;
    [NSStream getStreamsToHost:[NSHost hostWithAddress:ip] port:port inputStream:&tempIn outputStream:nil];
    
    metadataInputStream = [tempIn retain];
    [metadataInputStream setDelegate:self];
    [metadataInputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [metadataInputStream open];
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
    if (eventCode == NSStreamEventHasBytesAvailable) {
        uint8_t buffer[1024];
        int len = [(NSInputStream *)aStream read:buffer maxLength:sizeof(buffer)];
        if (len > 0) {
            NSString *raw = [[[NSString alloc] initWithBytes:buffer length:len encoding:NSUTF8StringEncoding] autorelease];
            NSLog(@"📡 BRIDGE DATA RECEIVED: [%@]", raw);
            [self parseAirPlayMetadata:raw];
        }
    } else if (eventCode == NSStreamEventEndEncountered || eventCode == NSStreamEventErrorOccurred) {
        [statusLED setTextColor:[NSColor grayColor]];
        [statusLabel setStringValue:@"Bridge Lost - Retrying..."];
        [self startServerDiscovery];
    }
}

- (void)parseAirPlayMetadata:(NSString *)metadata {
    NSArray *lines = [metadata componentsSeparatedByString:@"\n"];
    
    for (int i = 0; i < [lines count]; i++) {
        NSString *line = [lines objectAtIndex:i];
        if ([line length] < 5) continue;
        
        // --- 1. TITLE (The Master Trigger) ---
        if ([line hasPrefix:@"Title: "]) {
            NSString *val = [[line substringFromIndex:7] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            
            // Check if the title is ACTUALLY different from what we are currently showing
            if (![val isEqualToString:[trackNameLabel stringValue]]) {
                
                // A. Clear the UI for the fresh track
                [albumArtView setImage:nil];
                [trackNameLabel setStringValue:val];
                
                // B. Reset the "Art Lock" so we allow exactly ONE new download for this song
                [lastDownloadedArtTitle release];
                lastDownloadedArtTitle = nil;
                
                // C. Update the "Source of Truth" for the fetcher
                [currentActiveTitle release];
                currentActiveTitle = [val retain];
                
                NSLog(@"[LOG] 🆕 NEW TRACK DETECTED: %@. Resetting UI and Art Lock.", val);
                
            } else {
                // This handles the duplicate packets we saw in your logs (0.5s apart)
                NSLog(@"[LOG] ⏩ Duplicate/Seek title received for: %@. Ignoring reset.", val);
            }
        }
        
        // --- 2. ARTIST (Use 'if', not 'else if') ---
        if ([line hasPrefix:@"Artist: "]) {
            NSString *val = [[line substringFromIndex:8] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            [artistLabel setStringValue:val];
        }
        
        // --- 3. ALBUM (Use 'if') ---
//        if ([line hasPrefix:@"Album: "]) {
//            NSString *val = [[line substringFromIndex:7] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
//            [albumNameLabel setStringValue:val];
//        }
        
        // --- 4. ARTWORK (The Final Piece) ---
        if ([line hasPrefix:@"ArtUpdate: "]) {
            // 🔥 THE FIX: If we already have the art for this song, don't re-download it!
            if ([currentActiveTitle isEqualToString:lastDownloadedArtTitle]) {
                NSLog(@"[LOG] ✋ Ignoring redundant ArtUpdate. We already have art for: %@", currentActiveTitle);
            } else {
                NSLog(@"[LOG] 🖼 NEW ART SIGNAL: Downloading for %@", currentActiveTitle);
                [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(fetchAirPlayArtwork) object:nil];
                [self performSelector:@selector(fetchAirPlayArtwork) withObject:nil afterDelay:0.1];
            }
        }
    }
}

- (void)fetchAirPlayArtwork {
    if (!serverIP) return;
    
    // Capture the title at the EXACT moment the download starts
    NSString *fetchStartedForTitle = [currentActiveTitle retain];
    double startTime = [NSDate timeIntervalSinceReferenceDate];
    
    NSLog(@"[LOG] ⬇️ START DOWNLOAD for: %@ (Time: %f)", fetchStartedForTitle, startTime);
    
    NSString *urlPath = [NSString stringWithFormat:@"http://%@:5002/airplay_art", serverIP];
    NSURL *url = [NSURL URLWithString:urlPath];
    
    // 💡 IMPORTANT: Clear cache before every fetch to ensure we don't see the old song
    [[NSURLCache sharedURLCache] removeCachedResponseForRequest:[NSURLRequest requestWithURL:url]];
    
    NSURLRequest *request = [NSURLRequest requestWithURL:url
                                             cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                         timeoutInterval:5.0];
    
    NSURLResponse *response = nil;
    NSError *error = nil;
    NSData *imageData = [NSURLConnection sendSynchronousRequest:request
                                              returningResponse:&response
                                                          error:&error];
    
    double endTime = [NSDate timeIntervalSinceReferenceDate];
    
    // 🔥 THE GHOST DETECTOR
    if (![fetchStartedForTitle isEqualToString:currentActiveTitle]) {
        NSLog(@"[LOG] 👻 GHOST DETECTED! Download finished for '%@' but current song is now '%@'. ABORTING RENDER.",
              fetchStartedForTitle, currentActiveTitle);
        [fetchStartedForTitle release];
        return;
    }
    
    if (error || !imageData || [imageData length] == 0) {
        NSLog(@"❌ Art download failed. Keeping placeholder.");
        return;
    }
    
    NSLog(@"[LOG] ✅ DOWNLOAD COMPLETE for: %@ (Took %f seconds). Rendering...", fetchStartedForTitle, (endTime - startTime));
    [lastDownloadedArtTitle release];
    lastDownloadedArtTitle = [fetchStartedForTitle retain];
    // Render the new image
    [self displayHighQualityImage:imageData intoView:albumArtView];
    [fetchStartedForTitle release];
}

- (void)displayHighQualityImage:(NSData *)imageData intoView:(NSImageView *)imageView {
    NSImage *originalImage = [[NSImage alloc] initWithData:imageData];
    if (!originalImage) return;
    
    NSSize originalSize = [originalImage size];
    NSSize targetSize = [imageView bounds].size;
    
    // 1. Standard Tiger-safe scaling
    NSImage *scaledImage = [[[NSImage alloc] initWithSize:targetSize] autorelease];
    
    [scaledImage lockFocus];
    // This part is safe and makes it look great!
    [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
    
    [originalImage drawInRect:NSMakeRect(0, 0, targetSize.width, targetSize.height)
                     fromRect:NSMakeRect(0, 0, originalSize.width, originalSize.height)
                    operation:NSCompositeSourceOver
                     fraction:1.0];
    [scaledImage unlockFocus];
    
    // 2. Direct set (No Animation)
    // This is instant and won't crash the WindowServer on G4
    [imageView setImage:scaledImage];
    
    NSLog(@"🎨 Rendered High-Quality Artwork: %.0fx%.0f", targetSize.width, targetSize.height);
    
    [originalImage release];
}

- (void)dealloc {
    if (audioClientTask) [audioClientTask release];
    if (serverIP) [serverIP release];
    if (metadataInputStream) [metadataInputStream release];
    [super dealloc];
}

@end
