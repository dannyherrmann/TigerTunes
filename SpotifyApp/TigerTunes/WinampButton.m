//
//  WinampButton.m
//  TigerTunes
//
//  Created by Danny Herrmann on 2/11/26.
//  Copyright (c) 2026 Danny Herrmann. All rights reserved.
//

#import "WinampButton.h"
#import "AppDelegate.h"

@interface NSObject (TigerSafety)
- (BOOL)isPlaying;
@end

@implementation WinampButton

// - (void)drawRect:(NSRect)dirtyRect {
//     NSRect b = [self bounds];
//     BOOL isDown = [[self cell] isHighlighted];
    
//     // 1. Draw Bezel
//     [[NSColor blackColor] set];
//     NSFrameRect(b);
//     [[NSColor colorWithDeviceWhite:(isDown ? 0.3 : 0.6) alpha:1.0] set];
//     NSRectFill(NSInsetRect(b, 1, 1));
    
//     // 2. Set Icon Color (Dark Slate)
//     [[NSColor colorWithDeviceWhite:0.2 alpha:1.0] set];
    
//     // 3. IDENTIFY BY TAG (The Fix)
//     NSInteger buttonTag = [self tag];
    
//     if (buttonTag == 101) { // Play/Pause
//         AppDelegate *ad = (AppDelegate *)[NSApp delegate];
//         if ([ad isPlaying]) {
//             [self drawPauseIcon:b];
//         } else {
//             [self drawPlayIcon:b];
//         }
//     }
//     else if (buttonTag == 102) { // Next
//         [self drawNextIcon:b];
//     }
//     else if (buttonTag == 103) {
//         [self drawPreviousIcon:b];
//     }
//     else {
//         // FALLBACK: If tags aren't set, draw a generic play icon so it's not blank
//         [self drawPlayIcon:b];
//     }
// }

// - (void)drawPlayIcon:(NSRect)rect {
//     NSBezierPath *path = [NSBezierPath bezierPath];
//     // Shifted slightly left to leave room for the bar in "Next"
//     CGFloat startX = rect.size.width * 0.35;
//     [path moveToPoint:NSMakePoint(startX, rect.size.height * 0.3)];
//     [path lineToPoint:NSMakePoint(startX, rect.size.height * 0.7)];
//     [path lineToPoint:NSMakePoint(rect.size.width * 0.65, rect.size.height * 0.5)];
//     [path closePath];
//     [path fill];
// }

// - (void)drawPauseIcon:(NSRect)rect {
//     NSRect leftBar = NSMakeRect(rect.size.width * 0.35, rect.size.height * 0.3, 4, rect.size.height * 0.4);
//     NSRect rightBar = NSMakeRect(rect.size.width * 0.55, rect.size.height * 0.3, 4, rect.size.height * 0.4);
//     NSRectFill(leftBar);
//     NSRectFill(rightBar);
// }

// - (void)drawNextIcon:(NSRect)rect {
//     // 1. Draw the Triangle (using the updated centered logic)
//     [self drawPlayIcon:rect];
    
//     // 2. Draw the vertical bar to the right of the triangle
//     // Positioned at 70% of the width
//     CGFloat barX = rect.size.width * 0.7;
//     NSRect barRect = NSMakeRect(barX, rect.size.height * 0.3, 3, rect.size.height * 0.4);
//     NSRectFill(barRect);
// }

//- (void)drawPreviousIcon:(NSRect)rect {
//    // 1. Draw a mirrored triangle (pointing left)
//    NSBezierPath *path = [NSBezierPath bezierPath];
//    CGFloat startX = rect.size.width * 0.65; // Start on the right
//    [path moveToPoint:NSMakePoint(startX, rect.size.height * 0.3)];
//    [path lineToPoint:NSMakePoint(startX, rect.size.height * 0.7)];
//    [path lineToPoint:NSMakePoint(rect.size.width * 0.35, rect.size.height * 0.5)]; // Point to left
//    [path closePath];
//    [path fill];
//    
//    // 2. Draw the vertical bar to the LEFT of the triangle
//    CGFloat barX = rect.size.width * 0.25;
//    NSRect barRect = NSMakeRect(barX, rect.size.height * 0.3, 3, rect.size.height * 0.4);
//    NSRectFill(barRect);
//}

//- (void)drawRect:(NSRect)dirtyRect {
//    NSRect b = [self bounds];
//    BOOL isDown = [[self cell] isHighlighted];
//    
//    // Force square for the drawing area
//    CGFloat side = MIN(b.size.width, b.size.height);
//    NSRect squareRect = NSMakeRect(NSMidX(b) - side/2, NSMidY(b) - side/2, side, side);
//    squareRect = NSInsetRect(squareRect, 1, 1);
//    
//    NSInteger buttonTag = [self tag];
//    
//    if (buttonTag == 101) { // PLAY / PAUSE
//        // 1. Draw the White Circle Background
//        NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:squareRect];
//        if (isDown) {
//            [[NSColor lightGrayColor] set];
//        } else {
//            [[NSColor whiteColor] set];
//        }
//        [circle fill];
//        
//        // 2. Draw Black Icons on top
//        [[NSColor blackColor] set];
//        AppDelegate *ad = (AppDelegate *)[NSApp delegate];
//        if ([ad isPlaying]) {
//            [self drawSpotifyPause:squareRect];
//        } else {
//            [self drawSpotifyPlay:squareRect];
//        }
//    }
//    else { // PREV or NEXT
//        // 1. No background circle - just the shapes
//        // 2. Set Icon color to White
//        [[NSColor whiteColor] set];
//        
//        if (buttonTag == 102) {
//            [self drawSpotifyNext:squareRect];
//        } else if (buttonTag == 103) {
//            [self drawSpotifyPrev:squareRect];
//        }
//    }
//}
//
//- (void)drawSpotifyPlay:(NSRect)rect {
//    NSBezierPath *path = [NSBezierPath bezierPath];
//    CGFloat midX = NSMidX(rect);
//    CGFloat midY = NSMidY(rect);
//    CGFloat size = rect.size.width * 0.25;
//    
//    // Centered black triangle
//    [path moveToPoint:NSMakePoint(midX - (size * 0.6), midY - size)];
//    [path lineToPoint:NSMakePoint(midX - (size * 0.6), midY + size)];
//    [path lineToPoint:NSMakePoint(midX + (size * 0.9), midY)];
//    [path closePath];
//    [path fill];
//}
//
//- (void)drawSpotifyPause:(NSRect)rect {
//    CGFloat midX = NSMidX(rect);
//    CGFloat midY = NSMidY(rect);
//    CGFloat barW = rect.size.width * 0.10;
//    CGFloat barH = rect.size.height * 0.40;
//    
//    // Two black stripes
//    NSRectFill(NSMakeRect(midX - (barW * 1.5), midY - barH/2, barW, barH));
//    NSRectFill(NSMakeRect(midX + (barW * 0.5), midY - barH/2, barW, barH));
//}
//
//- (void)drawSpotifyNext:(NSRect)rect {
//    CGFloat midX = NSMidX(rect);
//    CGFloat midY = NSMidY(rect);
//    CGFloat size = rect.size.width * 0.22;
//    CGFloat barWidth = 4.0;
//    
//    // Triangle + Bar (Touching)
//    NSBezierPath *path = [NSBezierPath bezierPath];
//    [path moveToPoint:NSMakePoint(midX - size, midY - size)];
//    [path lineToPoint:NSMakePoint(midX - size, midY + size)];
//    [path lineToPoint:NSMakePoint(midX + (size * 0.3), midY)];
//    [path closePath];
//    [path fill];
//    
//    NSRectFill(NSMakeRect(midX + (size * 0.3), midY - size, barWidth, size * 2));
//}
//
//- (void)drawSpotifyPrev:(NSRect)rect {
//    CGFloat midX = NSMidX(rect);
//    CGFloat midY = NSMidY(rect);
//    CGFloat size = rect.size.width * 0.22;
//    CGFloat barWidth = 4.0;
//    
//    // Triangle + Bar (Touching)
//    NSBezierPath *path = [NSBezierPath bezierPath];
//    [path moveToPoint:NSMakePoint(midX + size, midY - size)];
//    [path lineToPoint:NSMakePoint(midX + size, midY + size)];
//    [path lineToPoint:NSMakePoint(midX - (size * 0.3), midY)];
//    [path closePath];
//    [path fill];
//    
//    NSRectFill(NSMakeRect(midX - (size * 0.3) - barWidth, midY - size, barWidth, size * 2));
//}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect b = [self bounds];
    BOOL isDown = [[self cell] isHighlighted];
    NSInteger buttonTag = [self tag];
    
    // 1. DYNAMIC SIZING
    CGFloat side = MIN(b.size.width, b.size.height);
    NSRect drawRect = NSMakeRect(NSMidX(b) - side/2, NSMidY(b) - side/2, side, side);
    drawRect = NSInsetRect(drawRect, 8, 8);
    
    // 2. TIGER-COMPATIBLE DRAWING
    CGContextRef context = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    
    // Create circular path
    NSBezierPath *circlePath = [NSBezierPath bezierPathWithOvalInRect:drawRect];
    
    // Draw the "Metallic" background using a simple fill for now to stop the crash
    // We will use a solid color that looks like the middle of our gradient
    if (isDown) {
        [[NSColor colorWithCalibratedWhite:0.3 alpha:1.0] set];
    } else {
        [[NSColor colorWithCalibratedWhite:0.75 alpha:1.0] set];
    }
    [circlePath fill];
    
    // Add a 1px dark border to make it look like a real button
    [[NSColor colorWithCalibratedWhite:0.1 alpha:1.0] set];
    [circlePath setLineWidth:1.0];
    [circlePath stroke];
    
    // 3. DRAW THE ICON
    // Using a dark slate gray for the inset-stamped look
    [[NSColor colorWithCalibratedWhite:0.1 alpha:1.0] set];
    
    // Tactile Click: Shift icon down 1px if button is pressed
    if (isDown) {
        CGContextSaveGState(context);
        CGContextTranslateCTM(context, 0, -1);
    }
    
    if (buttonTag == 101) { // Play/Pause
        // We use a safe way to get the delegate
        id ad = [NSApp delegate];
        if ([ad isPlaying]) {
            [self drawClassicPause:drawRect];
        } else {
            [self drawClassicPlay:drawRect];
        }
    } else if (buttonTag == 102) { // Next
        [self drawClassicNext:drawRect];
    } else if (buttonTag == 103) { // Previous
        [self drawClassicPrev:drawRect];
    }
    
    if (isDown) {
        CGContextRestoreGState(context);
    }
}

- (void)drawClassicPlay:(NSRect)rect {
    NSBezierPath *path = [NSBezierPath bezierPath];
    CGFloat size = rect.size.width * 0.28;
    CGFloat midX = NSMidX(rect);
    CGFloat midY = NSMidY(rect);
    
    // Shift left by 3% of the button width to balance the triangle's point
    CGFloat xOffset = rect.size.width * 0.03;
    CGFloat startX = midX - (size / 2) - xOffset;
    
    [path moveToPoint:NSMakePoint(startX, midY - size)];
    [path lineToPoint:NSMakePoint(startX, midY + size)];
    [path lineToPoint:NSMakePoint(startX + (size * 1.5), midY)];
    [path closePath];
    [path fill];
}

- (void)drawClassicPause:(NSRect)rect {
    CGFloat midX = NSMidX(rect);
    CGFloat midY = NSMidY(rect);
    
    CGFloat barW = rect.size.width * 0.12;
    CGFloat barH = rect.size.height * 0.45;
    CGFloat gap = rect.size.width * 0.08;
    
    NSRectFill(NSMakeRect(midX - barW - gap/2, midY - barH/2, barW, barH));
    NSRectFill(NSMakeRect(midX + gap/2, midY - barH/2, barW, barH));
}

- (void)drawClassicNext:(NSRect)rect {
    CGFloat midX = NSMidX(rect);
    CGFloat midY = NSMidY(rect);
    CGFloat size = rect.size.width * 0.18;
    CGFloat barWidth = rect.size.width * 0.06;
    
    // Vertical Bar on the Right
    NSRect barRect = NSMakeRect(midX + (size * 1.2) - barWidth, midY - size, barWidth, size * 2);
    NSRectFill(barRect);
    
    // Double Triangles Pointing Right
    for (int i = 0; i < 2; i++) {
        CGFloat xOffset = (i == 0) ? (midX + size * 0.1) : (midX - size * 0.9);
        NSBezierPath *p = [NSBezierPath bezierPath];
        [p moveToPoint:NSMakePoint(xOffset, midY - size)];
        [p lineToPoint:NSMakePoint(xOffset, midY + size)];
        [p lineToPoint:NSMakePoint(xOffset + size, midY)];
        [p closePath];
        [p fill];
    }
}

- (void)drawClassicPrev:(NSRect)rect {
    CGFloat midX = NSMidX(rect);
    CGFloat midY = NSMidY(rect);
    CGFloat size = rect.size.width * 0.18;
    CGFloat barWidth = rect.size.width * 0.06;
    
    // Vertical Bar on the Left
    NSRect barRect = NSMakeRect(midX - (size * 1.2), midY - size, barWidth, size * 2);
    NSRectFill(barRect);
    
    // Double Triangles Pointing Left
    for (int i = 0; i < 2; i++) {
        CGFloat xOffset = (i == 0) ? (midX - size * 0.1) : (midX + size * 0.9);
        NSBezierPath *p = [NSBezierPath bezierPath];
        [p moveToPoint:NSMakePoint(xOffset, midY - size)];
        [p lineToPoint:NSMakePoint(xOffset, midY + size)];
        [p lineToPoint:NSMakePoint(xOffset - size, midY)];
        [p closePath];
        [p fill];
    }
}

@end
