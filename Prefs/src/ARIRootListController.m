//
// Created by ren7995 on 2021-04-17 13:45:45
// Copyright (c) 2021 ren7995. All rights reserved.
//

#import "ARIRootListController.h"
#import "../../src/UI/Splash/ARISplashViewController.h"

@implementation ARIRootListController

- (NSArray *)specifiers {
    if(!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
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
    // Read the domain directly rather than the backing plist, so this works
    // regardless of where the jailbreak puts it
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];
    [defaults synchronize];
    NSMutableDictionary *dict = [[defaults persistentDomainForName:ARIPreferenceDomain] mutableCopy]
                                    ?: [NSMutableDictionary new];

    // The underscore prefix means it's an internal setting, not meant to be shared
    for(NSString *key in [dict allKeys])
        if([key hasPrefix:@"_"]) [dict removeObjectForKey:key];

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

    // SpringBoard reads these keys as numbers and strings without checking. A
    // settings string is something users paste from strangers, so anything of
    // an unexpected type here would be a respring loop on their device.
    NSMutableDictionary *accepted = [NSMutableDictionary new];
    for(NSString *key in settingsDictionary) {
        if(![key isKindOfClass:[NSString class]]) continue;
        // The underscore prefix means it's an internal setting, not meant to be shared
        if([key hasPrefix:@"_"]) continue;

        id value = settingsDictionary[key];
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
