//
//  ITunesLCDView.m
//  TigerTunes
//
//  Created by Danny Herrmann on 2/2/26.
//  Copyright (c) 2026 Danny Herrmann. All rights reserved.
//

#import "ITunesLCDView.h"
#import "AppDelegate.h"

@implementation ITunesLCDView

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent {
    return YES;
}

- (void)setProgress:(double)p {
    if (p != progress) {
        progress = p;
        [self setNeedsDisplay:YES];
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = [self bounds];
    
    // 1. Background LCD Tray (Darkened for the black UI)
    [[NSColor colorWithDeviceWhite:0.1 alpha:1.0] set];
    NSRectFill(bounds);
    
    // 2. Bezel (Subtle gray border)
    [[NSColor colorWithDeviceWhite:0.2 alpha:1.0] set];
    NSFrameRect(bounds);
    
    // 3. Progress Fill Area
    NSRect progressRect = NSInsetRect(bounds, 1.0, 1.0);
    progressRect.size.width *= progress;
    
    // 4. Spotify Green Pattern Creation
    static NSColor *pinstripeColor = nil;
    if (pinstripeColor == nil) {
        NSImage *tile = [[NSImage alloc] initWithSize:NSMakeSize(8, 8)];
        [tile lockFocus];
        
        // Background: Spotify Green (#1DB954)
        [[NSColor colorWithCalibratedRed:0.11 green:0.73 blue:0.33 alpha:1.0] set];
        NSRectFill(NSMakeRect(0, 0, 8, 8));
        
        // Stripe: Slightly darker green for texture
        [[NSColor colorWithCalibratedRed:0.08 green:0.60 blue:0.26 alpha:1.0] set];
        NSBezierPath *path = [NSBezierPath bezierPath];
        [path setLineWidth:1.5]; // Slightly thicker for visibility
        [path moveToPoint:NSMakePoint(0, 0)];
        [path lineToPoint:NSMakePoint(8, 8)];
        [path stroke];
        
        [tile unlockFocus];
        pinstripeColor = [[NSColor colorWithPatternImage:tile] retain];
        [tile release];
    }
    
    // 5. Fill the bar
    if (progress > 0) {
        [pinstripeColor set];
        NSRectFill(progressRect);
    }
}

- (void)mouseDown:(NSEvent *)theEvent {
    NSPoint clickPoint = [self convertPoint:[theEvent locationInWindow] fromView:nil];
    
    // Calculate percentage (0.0 to 1.0)
    double newProgress = clickPoint.x / [self bounds].size.width;
    
    // Tell the AppDelegate to seek
    // We'll assume your AppDelegate is the 'target' or you can use a notification
    [[NSApp delegate] userDidSeekToPercentage:newProgress];
}

- (void)keyDown:(NSEvent *)theEvent {
    NSString *characters = [theEvent characters];
    if ([characters length] > 0) {
        unichar charCode = [characters characterAtIndex:0];
        AppDelegate *ad = (AppDelegate *)[NSApp delegate];
        if (charCode == ' ') { // Space bar
            [ad playPausePressed:self];
            return;
        }
        
        if (charCode == NSRightArrowFunctionKey) {
            [ad nextPressed:self];
            return;
        }
        
        if (charCode == NSLeftArrowFunctionKey) {
            [ad previousPressed:self];
            return;
        }
    }
    [super keyDown:theEvent];
}

// This is crucial: it tells the system this view can accept keyboard focus
- (BOOL)acceptsFirstResponder {
    return YES;
}

@end
