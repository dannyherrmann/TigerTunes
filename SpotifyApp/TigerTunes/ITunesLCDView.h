//
//  ITunesLCDView.h
//  TigerTunes
//
//  Created by Danny Herrmann on 2/2/26.
//  Copyright (c) 2026 Danny Herrmann. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface ITunesLCDView : NSView {
    double progress; // 0.0 to 1.0
}
- (void)setProgress:(double)p;
@end
