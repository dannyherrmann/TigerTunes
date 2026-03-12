//
//  TTScrollingTextField.h
//  TigerTunes
//
//  Created by Danny Herrmann on 2/19/26.
//  Copyright (c) 2026 Danny Herrmann. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface TTScrollingTextField : NSTextField {
    NSTimer *scrollerTimer;
    float scrollPoint;
    float stringWidth;
    BOOL movingLeft; // Track Ping-Pong direction
    int waitTimer;   // To pause at the ends
}
- (void)startScrolling;
- (void)stopScrolling;
@end
