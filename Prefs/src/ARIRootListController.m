//
// Created by ren7995 on 2021-04-17 13:45:45
// Copyright (c) 2021 ren7995. All rights reserved.
//

#import "ARIRootListController.h"
#import "../../src/ARIPaths.h"
#import "../../src/UI/Splash/ARISplashViewController.h"

#import <Preferences/PSTableCell.h>

#if defined(THEOS_PACKAGE_SCHEME_ROOTHIDE)
#define PACKAGE_SCHEME "roothide"
#elif defined(THEOS_PACKAGE_SCHEME_ROOTLESS)
#define PACKAGE_SCHEME "rootless"
#elif defined(THEOS_PACKAGE_SCHEME_ROOTFUL)
#define PACKAGE_SCHEME "rootful"
#else
#error theos defined no package scheme
#endif

static const CGFloat kARIIconSide = 80.0;

@interface ARIHeaderCell : PSTableCell
@end

@implementation ARIHeaderCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:identifier specifier:specifier];
    if(!self) return nil;

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage imageWithContentsOfFile:ARIPrefsBundlePath(@"/full.png")]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.clipsToBounds = YES;
    icon.layer.cornerCurve = kCACornerCurveContinuous;
    icon.layer.cornerRadius = kARIIconSide * 0.225;
    [self.contentView addSubview:icon];

    UILabel *version = [[UILabel alloc] init];
    version.text = @"Version " PACKAGE_VERSION "\n" PACKAGE_SCHEME;
    version.numberOfLines = 2;
    version.font = [UIFont systemFontOfSize:14.0];
    version.textColor = [UIColor systemGrayColor];
    version.textAlignment = NSTextAlignmentCenter;
    version.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:version];

    [NSLayoutConstraint activateConstraints:@[
        [icon.widthAnchor constraintEqualToConstant:kARIIconSide],
        [icon.heightAnchor constraintEqualToConstant:kARIIconSide],
        [icon.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [icon.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10.0],
        [version.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:8.0],
        [version.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [version.widthAnchor constraintEqualToAnchor:self.contentView.widthAnchor]
    ]];

    return self;
}

- (void)setSeparatorStyle:(UITableViewCellSeparatorStyle)style {
    [super setSeparatorStyle:UITableViewCellSeparatorStyleNone];
}

- (void)setBackgroundColor:(UIColor *)color {
    [super setBackgroundColor:[UIColor clearColor]];
}

- (UITableViewCellSelectionStyle)selectionStyle {
    return UITableViewCellSelectionStyleNone;
}

@end

@implementation ARIRootListController

- (NSArray *)specifiers {
    if(!_specifiers) {
        NSMutableArray *specifiers = [NSMutableArray array];

        PSSpecifier *header = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:NULL get:NULL detail:nil cell:PSStaticTextCell edit:nil];
        [header setProperty:[ARIHeaderCell class] forKey:@"cellClass"];
        [header setProperty:@142 forKey:@"height"];
        [specifiers addObject:header];

        PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
        [group setProperty:@"In order to edit layout, 3D touch a homescreen icon, or triple tap behind them (on your wallpaper)" forKey:@"footerText"];
        [specifiers addObject:group];

        [specifiers addObjectsFromArray:[self loadSpecifiersFromPlistName:@"Root" target:self]];
        _specifiers = specifiers;
    }

    return _specifiers;
}

- (void)resetPrefs:(id)sender {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Reset Preferences"
                         message:@"Are you sure you want to reset preferences? Your device will respring."
                  preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *defaultAction = [UIAlertAction
        actionWithTitle:@"No"
                  style:UIAlertActionStyleCancel
                handler:nil];
    UIAlertAction *yes = [UIAlertAction
        actionWithTitle:@"Yes"
                  style:UIAlertActionStyleDestructive
                handler:^(UIAlertAction *action) {
                    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];
                    [prefs removePersistentDomainForName:ARIPreferenceDomain];
                    [prefs synchronize];
                    [self respringWithAnimation];
                }];

    [alert addAction:defaultAction];
    [alert addAction:yes];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)resetSaveState:(id)sender {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Reset Save State"
                         message:@"Are you sure you want to reset save state? Your device will respring."
                  preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *defaultAction = [UIAlertAction
        actionWithTitle:@"No"
                  style:UIAlertActionStyleCancel
                handler:nil];
    UIAlertAction *yes = [UIAlertAction
        actionWithTitle:@"Yes"
                  style:UIAlertActionStyleDestructive
                handler:^(UIAlertAction *action) {
                    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];
                    [prefs removeObjectForKey:@"_saveState"];
                    [prefs synchronize];
                    [self respringWithAnimation];
                }];

    [alert addAction:defaultAction];
    [alert addAction:yes];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)exportSettingsString {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];
    [defaults synchronize];
    NSMutableDictionary *dict = [[defaults persistentDomainForName:ARIPreferenceDomain] mutableCopy]
                                    ?: [NSMutableDictionary new];

    for(NSString *key in [dict allKeys])
        if([key hasPrefix:@"_"] && ![key isEqualToString:ARIPerPageListViewsKey])
            [dict removeObjectForKey:key];

    // Easier to make it json imho
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict
                                                       options:0
                                                         error:&error];
    if(error) {
        [self displayAlert:@"Failed to export" message:[NSString stringWithFormat:@"Error: %@", error.localizedDescription]];
        return;
    }

    NSString *encoded = [jsonData base64EncodedStringWithOptions:0];
    [UIPasteboard generalPasteboard].string = encoded;
    [self displayAlert:@"Success" message:@"Settings exported and copied to clipboard"];
}

- (void)importSettingsString {
    NSString *pasteboardString = [UIPasteboard generalPasteboard].string;
    if(!pasteboardString) {
        [self displayAlert:@"Failed to import" message:@"No string was found in your clipboard."];
        return;
    }
    NSData *decodeData = [[NSData alloc] initWithBase64EncodedString:pasteboardString options:0];
    if(!decodeData) {
        [self displayAlert:@"Failed to import" message:@"Failed to decode. Perhaps the settings string in your clipboard is invalid?"];
        return;
    }

    NSError *error;
    id decoded = [NSJSONSerialization JSONObjectWithData:decodeData options:kNilOptions error:&error];

    if(![decoded isKindOfClass:[NSDictionary class]]) {
        [self displayAlert:@"Failed to import" message:[NSString stringWithFormat:@"Perhaps the settings string in your clipboard is invalid?\n\nError: %@", error.localizedDescription]];
        return;
    }
    NSDictionary *settingsDictionary = decoded;

    NSMutableDictionary *accepted = [NSMutableDictionary new];
    for(NSString *key in settingsDictionary) {
        if(![key isKindOfClass:[NSString class]]) continue;

        id value = settingsDictionary[key];
        if([key isEqualToString:ARIPerPageListViewsKey]) {
            if(![value isKindOfClass:[NSArray class]]) continue;
            BOOL allStrings = YES;
            for(id prefix in (NSArray *)value)
                if(![prefix isKindOfClass:[NSString class]]) allStrings = NO;
            if(allStrings) accepted[key] = value;
            continue;
        }

        // The underscore prefix means it's an internal setting, not meant to be shared
        if([key hasPrefix:@"_"]) continue;
        if(![value isKindOfClass:[NSString class]] && ![value isKindOfClass:[NSNumber class]]) continue;
        accepted[key] = value;
    }

    if([accepted count] == 0) {
        [self displayAlert:@"Failed to import" message:@"No usable settings were found in that string."];
        return;
    }

    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];
    [defaults removePersistentDomainForName:ARIPreferenceDomain];
    defaults = [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];
    [defaults synchronize];

    // Set ARIDidSplashPreferenceKey, since they are in preferences already
    [defaults setObject:@(YES) forKey:ARIDidSplashPreferenceKey];

    for(NSString *key in accepted) {
        [defaults setObject:accepted[key] forKey:key];
    }
    [defaults synchronize];

    NSUInteger skipped = [settingsDictionary count] - [accepted count];
    NSString *message = skipped > 0
                            ? [NSString stringWithFormat:@"Settings imported. You may now respring to apply completely.\n\n%lu imported, %lu skipped.", (unsigned long)[accepted count], (unsigned long)skipped]
                            : [NSString stringWithFormat:@"Settings imported. You may now respring to apply completely.\n\n%lu imported.", (unsigned long)[accepted count]];

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Success"
                         message:message
                  preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *defaultAction = [UIAlertAction
        actionWithTitle:@"Respring"
                  style:UIAlertActionStyleDestructive
                handler:^(UIAlertAction *action) {
                    [self respringWithAnimation];
                }];
    [alert addAction:defaultAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)displayAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:title
                         message:message
                  preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *defaultAction = [UIAlertAction
        actionWithTitle:@"OK"
                  style:UIAlertActionStyleCancel
                handler:nil];

    [alert addAction:defaultAction];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
