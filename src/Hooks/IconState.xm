//
// Created by ren7995 on 2021-04-27 18:35:28
// Copyright (c) 2021 ren7995. All rights reserved.
//

#import "Shared.h"
#import "../Manager/ARITweakManager.h"

// This is handed straight to the icon model while SpringBoard is coming up, so
// anything but a populated dictionary would crash it before Settings can be
// reached to clear the value. Drop what we can't use and fall back to the store.
static BOOL ARIIconStateIsUsable(id state) {
    return [state isKindOfClass:[NSDictionary class]] && [(NSDictionary *)state count] > 0;
}

%hook SBDefaultIconModelStore

- (id)loadCurrentIconState:(NSError **)error {
    ARITweakManager *manager = [ARITweakManager sharedInstance];
    id lastKnownState = [manager rawValueForKey:@"_saveState"];
    if(ARIIconStateIsUsable(lastKnownState)) {
        return lastKnownState;
    }
    if(lastKnownState) [manager resetValueForKey:@"_saveState"];

    id orig = %orig;
    if(ARIIconStateIsUsable(orig)) [manager setRawValue:orig forKey:@"_saveState"];
    return orig;
}

- (BOOL)saveCurrentIconState:(id)state error:(NSError **)error {
    if(ARIIconStateIsUsable(state)) [[ARITweakManager sharedInstance] setRawValue:state forKey:@"_saveState"];
    return %orig;
}

%end

%ctor {
    ARITweakManager *manager = [ARITweakManager sharedInstance];
    if([manager isEnabled]) {
        // A user might want to disable this if they have a tweak like Velox Reloaded 2 which also saves icon state
        if([manager boolValueForKey:@"saveIconState"]) {
            ARILog(@"Loading hooks from %s", __FILE__);
		    %init();
        } else {
            // Clear the existing saved icon state so that the user's layout doesn't revert when re-enabling the option
            [[ARITweakManager sharedInstance] resetValueForKey:@"_saveState"];
        }
	}
}
