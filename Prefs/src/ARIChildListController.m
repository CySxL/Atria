//
// Created by ren7995 on 2023-05-25 21:52:05
// Copyright (c) 2023 ren7995. All rights reserved.
//

#import "ARIChildListController.h"
#import "ARICategoryEditorController.h"

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
            @"LibraryCategories" : @[
                @{ @"switches" : @[ @"libraryCategories" ], @"rows" : @[ @"libraryHideSuggestions", @"libraryHideRecent", @"editLibraryCategoryApps", @"orderLibraryCategories", @"resetLibraryCategories" ] },
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

// Colour rows carry colorKey instead of key, so Preferences never reads or writes
// them itself. Stored as "#RRGGBB".
static NSString *ARIColorKey(PSSpecifier *specifier) {
    NSString *key = [specifier propertyForKey:@"colorKey"];
    return [key isKindOfClass:[NSString class]] ? key : nil;
}

static NSString *ARIStoredHex(PSSpecifier *specifier) {
    id value = [[[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain] objectForKey:ARIColorKey(specifier)];
    if(!value) value = [specifier propertyForKey:@"default"];
    if([value isKindOfClass:[NSString class]] && [value length] == 7 && [value hasPrefix:@"#"]) {
        NSScanner *scanner = [NSScanner scannerWithString:[value substringFromIndex:1]];
        unsigned int rgb = 0;
        if([scanner scanHexInt:&rgb] && scanner.isAtEnd) return [value uppercaseString];
    }
    return @"#FFFFFF";
}

static UIColor *ARIColorFromHex(NSString *hex) {
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:[hex substringFromIndex:1]] scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0 green:((rgb >> 8) & 0xff) / 255.0 blue:(rgb & 0xff) / 255.0 alpha:1.0];
}

static NSString *ARIHexFromColor(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [color getRed:&r green:&g blue:&b alpha:&a];
    int (^channel)(CGFloat) = ^int(CGFloat c) { return (int)lround(fmin(fmax(c, 0.0), 1.0) * 255.0); };
    return [NSString stringWithFormat:@"#%02X%02X%02X", channel(r), channel(g), channel(b)];
}

static UIImage *ARISwatch(UIColor *color) {
    CGFloat side = 29.0;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        UIBezierPath *shape = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.5, 0.5, side - 1.0, side - 1.0) cornerRadius:side * 0.225];
        [color setFill];
        [shape fill];
        [[UIColor colorWithWhite:0.5 alpha:0.35] setStroke];
        [shape stroke];
    }];
}

@interface ARIChildListController () <UIColorPickerViewControllerDelegate>
@end

@implementation ARIChildListController {
    NSString *_childName;
    NSArray<PSSpecifier *> *_allSpecifiers;
    NSArray<NSDictionary *> *_gates;
    PSSpecifier *_picking;
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
        // On every row, not only the visible ones, since a gated row comes back from here
        for(PSSpecifier *specifier in _allSpecifiers)
            if(ARIColorKey(specifier)) [specifier setProperty:ARISwatch(ARIColorFromHex(ARIStoredHex(specifier))) forKey:@"iconImage"];
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

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if(ARIColorKey([self specifierAtIndexPath:indexPath])) return indexPath;
    if([PSListController instancesRespondToSelector:_cmd]) return [super tableView:tableView willSelectRowAtIndexPath:indexPath];
    return indexPath;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    if(!ARIColorKey(specifier)) {
        [super tableView:tableView didSelectRowAtIndexPath:indexPath];
        return;
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if(@available(iOS 14.0, *)) {
        _picking = specifier;
        UIColorPickerViewController *picker = [[UIColorPickerViewController alloc] init];
        picker.title = specifier.name;
        picker.supportsAlpha = NO;
        picker.selectedColor = ARIColorFromHex(ARIStoredHex(specifier));
        picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
    }
}

- (void)_savePickedColor:(UIColor *)color {
    NSString *key = ARIColorKey(_picking);
    if(!key || !color) return;
    NSString *hex = ARIHexFromColor(color);
    if([hex isEqualToString:ARIStoredHex(_picking)]) return;

    [[[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain] setObject:hex forKey:key];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("me.lau.Atria/ReloadPrefs"), NULL, NULL, YES);
    [_picking setProperty:ARISwatch(ARIColorFromHex(hex)) forKey:@"iconImage"];
    [self reloadSpecifier:_picking animated:NO];
}

- (void)colorPickerViewController:(UIColorPickerViewController *)picker didSelectColor:(UIColor *)color continuously:(BOOL)continuously API_AVAILABLE(ios(14.0)) {
    if(!continuously) [self _savePickedColor:color];
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)picker API_AVAILABLE(ios(14.0)) {
    [self _savePickedColor:picker.selectedColor];
    _picking = nil;
}

- (void)editLibraryCategoryApps:(PSSpecifier *)specifier {
    [self.navigationController pushViewController:[[ARICategoryEditorController alloc] initWithMode:ARICategoryEditorModeApps] animated:YES];
}

- (void)orderLibraryCategories:(PSSpecifier *)specifier {
    [self.navigationController pushViewController:[[ARICategoryEditorController alloc] initWithMode:ARICategoryEditorModeOrder] animated:YES];
}

- (void)resetLibraryCategories:(PSSpecifier *)specifier {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset Categories"
                                                                   message:@"The App Library and dock return to how iOS arranges them, and added categories are removed."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
                                                NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];
                                                for(NSString *key in ARILibraryCategoryKeys)
                                                    [defaults removeObjectForKey:key];
                                                [defaults synchronize];
                                                CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("me.lau.Atria/ReloadPrefs"), NULL, NULL, YES);
                                                [self reloadSpecifiers];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)setSpecifier:(PSSpecifier *)specifier {
    _childName = [specifier propertyForKey:@"child"];
    [self specifiers];
}

- (BOOL)shouldReloadSpecifiersOnResume {
    return NO;
}

@end
