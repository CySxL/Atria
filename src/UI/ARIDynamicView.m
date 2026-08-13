//
// Created by ren7995 on 2023-01-05 14:55:49
// Copyright (c) 2023 ren7995. All rights reserved.
//

#import "ARIDynamicView.h"

// https://stackoverflow.com/questions/1560081/how-can-i-create-a-uicolor-from-a-hex-string
#define UIColorFromHexValue(r, a) [UIColor               \
    colorWithRed:((float)((r & 0xFF0000) >> 16)) / 255.0 \
           green:((float)((r & 0xFF00) >> 8)) / 255.0    \
            blue:((float)(r & 0xFF)) / 255.0             \
           alpha:a]

@implementation ARIDynamicView

- (instancetype)init {
    self = [super init];
    if(self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
    }
    return self;
}

- (void)updateView {
}

- (void)updateAnchors {
}

+ (UIColor *)colorFromHexString:(NSString *)str withAlpha:(CGFloat)alpha {
    if(!str) return [UIColor colorWithWhite:1.0 alpha:alpha];
    str = [str stringByReplacingOccurrencesOfString:@"#" withString:@"0x"];
    NSScanner *scanner = [NSScanner scannerWithString:str];
    // Left uninitialised this reads the stack when the string isn't hex, and an
    // imported settings string can put anything in the colour keys
    unsigned int hexCode = 0xFFFFFF;
    if(![scanner scanHexInt:&hexCode]) return [UIColor colorWithWhite:1.0 alpha:alpha];
    return UIColorFromHexValue(hexCode, alpha);
}

@end