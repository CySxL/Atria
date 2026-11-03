//
// Created by ren7995 on 2023-05-25 21:52:05
// Copyright (c) 2023 ren7995. All rights reserved.
//

#import "ARIChildListController.h"

// Rows that only act while one of their switches is on, by plist. A row is shown
// while every gate it belongs to has a switch on.
static NSArray<NSDictionary *> *ARIGatesForPlist(NSString *name) {
    static NSDictionary<NSString *, NSArray<NSDictionary *> *> *gates;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        NSArray *labels = @[ @"showWelcome", @"showPageLabels" ];
        gates = @{
            @"General" : @[
                @{ @"switches" : @[ @"floatingDockAppLibrary" ], @"rows" : @[ @"floatingDockPodBeforeRecents" ] },
                @{ @"switches" : @[ @"floatingDockRecents" ], @"rows" : @[ @"maxFloatingDockRecents" ] },
            ],
            @"Customization" : @[
                @{ @"switches" : @[ @"showBackground" ], @"rows" : @[ @"blurTintGroup", @"blurTintEnabled", @"blurTintColor" ] },
                @{ @"switches" : @[ @"blurTintEnabled" ], @"rows" : @[ @"blurTintColor" ] },
            ],
            @"PageLabels" : @[
                @{ @"switches" : labels, @"rows" : @[ @"showWeatherIcon", @"weatherRefreshInterval", @"weatherFooter" ] },
                @{ @"switches" : labels, @"rows" : @[ @"pageLabelShadow", @"lockPageLabels", @"lockFooter", @"textColorGroup", @"labelTextColor" ] },
            ],
        };
    });
    return gates[name];
}

static NSString *ARIGateName(PSSpecifier *specifier) {
    NSString *key = [specifier propertyForKey:@"key"];
    return [key isKindOfClass:[NSString class]] ? key : specifier.identifier;
}

@implementation ARIChildListController {
    NSString *_childName;
    NSArray<PSSpecifier *> *_allSpecifiers;
    NSArray<NSDictionary *> *_gates;
}

- (BOOL)_isSwitchOn:(NSString *)key changed:(PSSpecifier *)changed value:(id)value {
    id current = value;
    if(![ARIGateName(changed) isEqualToString:key]) {
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];
        current = [defaults objectForKey:key];
        if(!current) {
            for(PSSpecifier *specifier in _allSpecifiers)
                if([ARIGateName(specifier) isEqualToString:key]) current = [specifier propertyForKey:@"default"];
        }
    }
    return [current isKindOfClass:[NSNumber class]] && [current boolValue];
}

// The rows to show, in plist order, with one switch read from the value being set
- (NSArray<PSSpecifier *> *)_visibleSpecifiersWithChanged:(PSSpecifier *)changed value:(id)value {
    NSMutableSet<NSString *> *hidden = [NSMutableSet set];
    for(NSDictionary *gate in _gates) {
        BOOL on = NO;
        for(NSString *key in gate[@"switches"])
            on = on || [self _isSwitchOn:key changed:changed value:value];
        if(!on) [hidden addObjectsFromArray:gate[@"rows"]];
    }

    NSMutableArray<PSSpecifier *> *visible = [NSMutableArray array];
    for(PSSpecifier *specifier in _allSpecifiers) {
        NSString *name = ARIGateName(specifier);
        if(!name || ![hidden containsObject:name]) [visible addObject:specifier];
    }
    return visible;
}

- (NSArray *)specifiers {
    if(!_specifiers && _childName) {
        _allSpecifiers = [self loadSpecifiersFromPlistName:_childName target:self];
        _gates = ARIGatesForPlist(_childName);
        _specifiers = _gates ? [[self _visibleSpecifiersWithChanged:nil value:nil] mutableCopy] : [_allSpecifiers mutableCopy];
    }

    return _specifiers;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];

    NSString *name = ARIGateName(specifier);
    BOOL isSwitch = NO;
    for(NSDictionary *gate in _gates)
        isSwitch = isSwitch || [gate[@"switches"] containsObject:name];
    if(!isSwitch) return;

    NSArray<PSSpecifier *> *visible = [self _visibleSpecifiersWithChanged:specifier value:value];
    for(PSSpecifier *row in [_specifiers copy]) {
        if(![visible containsObject:row]) [self removeSpecifier:row animated:YES];
    }
    PSSpecifier *previous = nil;
    for(PSSpecifier *row in visible) {
        if(![_specifiers containsObject:row]) {
            if(previous) [self insertSpecifier:row afterSpecifier:previous animated:YES];
            else [self insertSpecifier:row atIndex:0 animated:YES];
        }
        previous = row;
    }
}

- (void)setSpecifier:(PSSpecifier *)specifier {
    _childName = [specifier propertyForKey:@"child"];
    [self specifiers];
}

- (BOOL)shouldReloadSpecifiersOnResume {
    return NO;
}

@end
