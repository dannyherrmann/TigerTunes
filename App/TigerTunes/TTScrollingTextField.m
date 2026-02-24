//
//  TTScrollingTextField.m
//  TigerTunes
//
//  Created by Danny Herrmann on 2/19/26.
//  Copyright (c) 2026 Danny Herrmann. All rights reserved.
//

#import "TTScrollingTextField.h"

@implementation TTScrollingTextField

- (void)startScrolling {
    [self stopScrolling];
    
    NSDictionary *attrs = [NSDictionary dictionaryWithObject:[self font] forKey:NSFontAttributeName];
    stringWidth = [[self stringValue] sizeWithAttributes:attrs].width;
    
    // Only scroll if the text is wider than the field
    if (stringWidth > [self bounds].size.width) {
        scrollPoint = 0;
        movingLeft = YES;
        waitTimer = 0;
        // Interval 0.05 is slower than 0.03
        scrollerTimer = [[NSTimer scheduledTimerWithTimeInterval:0.05 target:self selector:@selector(updateScroll:) userInfo:nil repeats:YES] retain];
    }
}

- (void)updateScroll:(NSTimer *)timer {
    if (waitTimer > 0) {
        waitTimer--;
        return;
    }
    
    float maxScroll = [self bounds].size.width - stringWidth;
    
    if (movingLeft) {
        scrollPoint -= 0.5; // Very smooth, slow movement
        if (scrollPoint <= maxScroll) {
            movingLeft = NO;
            waitTimer = 40; // Pause for 2 seconds at the end
        }
    } else {
        scrollPoint += 0.5;
        if (scrollPoint >= 0) {
            movingLeft = YES;
            waitTimer = 40; // Pause for 2 seconds at the start
        }
    }
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    // 1. Get the text color you set in Interface Builder
    NSColor *textColor = [self textColor];
    if (!textColor) textColor = [NSColor whiteColor];
    
    NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
                           [self font], NSFontAttributeName,
                           textColor, NSForegroundColorAttributeName, nil];
    
    if (scrollerTimer) {
        // Draw the sliding text with the correct attributes (color!)
        [[self stringValue] drawAtPoint:NSMakePoint(scrollPoint, 0) withAttributes:attrs];
    } else {
        // If not scrolling, let the system draw it (it will be white)
        [super drawRect:dirtyRect];
    }
}

- (void)stopScrolling {
    [scrollerTimer invalidate];
    [scrollerTimer release];
    scrollerTimer = nil;
    scrollPoint = 0;
    [self setNeedsDisplay:YES];
}

@end
