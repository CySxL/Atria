//
// Created by ren7995 on 2021-04-25 12:49:45
// Copyright (c) 2021 ren7995. All rights reserved.
//

#import "Shared.h"
#import "../Manager/ARITweakManager.h"

@interface SBFloatingDockPlatterView : UIView
@property (nonatomic, strong) UIView *backgroundView;
@end

@interface SBDockView (ARIBackgroundAlpha)
@property (nonatomic, strong) NSNumber *_atriaSystemBackgroundAlpha;
@end

@interface SBFloatingDockView (ARIBackgroundAlpha)
@property (nonatomic, assign) BOOL _atriaWroteBackgroundOpacity;
@property (nonatomic, assign) BOOL _atriaMovedPod;
- (UIView *)dividerView;
- (UIView *)recentIconListView;
@end

ARI_CACHED_CLASS(ARIDockIconViewClass, "SBIconView")
ARI_CACHED_CLASS(ARIDockPodIconClass, "SBHLibraryPodIndicatorIcon")

// Puts the library pod in the first recents slot and moves the recents along by one icon
static BOOL ARIMovePodBeforeRecents(SBFloatingDockView *dock) {
    if(![dock respondsToSelector:@selector(dividerView)] || ![dock respondsToSelector:@selector(recentIconListView)])
        return NO;
    UIView *divider = [dock dividerView];
    UIView *recents = [dock recentIconListView];
    UIView *platter = divider.superview;
    if(!platter || divider.hidden || recents.superview != platter) return NO;

    Class iconViewClass = ARIDockIconViewClass();
    Class podClass = ARIDockPodIconClass();
    if(!iconViewClass || !podClass) return NO;

    UIView *pod = nil;
    for(UIView *view in platter.subviews) {
        if([view isKindOfClass:iconViewClass] && [((SBIconView *)view).icon isKindOfClass:podClass]) {
            pod = view;
            break;
        }
    }
    if(!pod || pod.hidden) return NO;

    // Slots come from the list's layout, not its subviews: an icon view being removed
    // (a recent replaced by Handoff) stays among them at a stale x.
    if(![recents respondsToSelector:@selector(icons)] || ![recents respondsToSelector:@selector(centerForIconAtIndex:)])
        return NO;
    SBIconListView *list = (SBIconListView *)recents;
    NSUInteger count = [list icons].count;
    if(count == 0) return NO;
    CGFloat first = [list centerForIconAtIndex:0].x;
    CGFloat last = [list centerForIconAtIndex:count - 1].x;

    // The stock gap between the last recent and the pod
    CGFloat pitch = pod.center.x - (CGRectGetMinX(recents.frame) + last);
    if(pitch <= 0) return NO;

    pod.center = CGPointMake(CGRectGetMinX(recents.frame) + first, pod.center.y);
    recents.frame = CGRectOffset(recents.frame, pitch, 0);
    return YES;
}

static SBFloatingDockController *fdController;

static NSUInteger ARIMaxRecents() {
    int recents = [[ARITweakManager sharedInstance] intValueForKey:@"maxFloatingDockRecents"];
    return recents < 0 ? 0 : MIN((NSUInteger)recents, ARIMaxGridCount);
}

%hook SBDockView
%property (nonatomic, strong) NSNumber *_atriaSystemBackgroundAlpha;

%new
- (void)_atriaUpdateDockForSettingsChanged {
    NSNumber *system = self._atriaSystemBackgroundAlpha;
    [self setBackgroundAlpha:system ? [system doubleValue] : 1];
}

- (CGFloat)dockHeight {
    if([[ARITweakManager sharedInstance] boolValueForKey:@"disableDock"])
        return 0;
    return %orig;
}

// Scale whatever SpringBoard asks for, so its own fades still happen
- (void)setBackgroundAlpha:(CGFloat)alpha {
    self._atriaSystemBackgroundAlpha = @(alpha);
    ARITweakManager *manager = [ARITweakManager sharedInstance];
    if([manager boolValueForKey:@"disableDock"]) {
        %orig(0);
        return;
    }
    %orig(alpha * [manager floatValueForKey:@"dock_bg"]);
}

- (void)traitCollectionDidChange:(UITraitCollection *)old {
    %orig(old);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _atriaUpdateDockForSettingsChanged];
    });
}

%end

%hook SBFloatingDockController

// iOS 13-15
- (id)initWithIconController:(id)arg1 {
    id orig = %orig;
    fdController = orig;
    return orig;
}

// iOS 16+
- (id)initWithWindowScene:(id)arg1 iconController:(id)arg2 {
    id orig = %orig;
    fdController = orig;
    return orig;
}

- (BOOL)isGesturePossible {
    if([[ARITweakManager sharedInstance] boolValueForKey:@"disableFloatingDockGestures"]) return NO;
    return %orig;
}

// handlePresentFloatingDockGesture:

%new
+ (SBFloatingDockController *)_atriaSharedInstance {
    return fdController;
}

+ (BOOL)isFloatingDockSupported {
    ARITweakManager *manager = [ARITweakManager sharedInstance];
    return ([manager boolValueForKey:@"forceFloatingDock"] && ![manager boolValueForKey:@"disableDock"]) || %orig;
}

%end

// iPadOS keeps its own switches for these, so leave them alone until Atria's are set
static BOOL ARIOverridesFloatingDockDefault(NSString *key) {
    ARITweakManager *manager = [ARITweakManager sharedInstance];
    return [manager boolValueForKey:@"forceFloatingDock"] || [manager.preferences objectForKey:key];
}

%hook SBFloatingDockDefaults

- (BOOL)recentsEnabled {
    if(!ARIOverridesFloatingDockDefault(@"floatingDockRecents")) return %orig;
    return [[ARITweakManager sharedInstance] boolValueForKey:@"floatingDockRecents"];
}

- (BOOL)appLibraryEnabled {
    if(!ARIOverridesFloatingDockDefault(@"floatingDockAppLibrary")) return %orig;
    return [[ARITweakManager sharedInstance] boolValueForKey:@"floatingDockAppLibrary"];
}

%end

%hook SBFloatingDockSuggestionsModel

// iOS 13-15
- (id)initWithMaximumNumberOfSuggestions:(unsigned long long)arg1
                          iconController:(id)arg2
                       recentsController:(id)arg3
                        recentsDataStore:(id)arg4
                         recentsDefaults:(id)arg5
                    floatingDockDefaults:(id)arg6
                    appSuggestionManager:(id)arg7
                         analyticsClient:(id)arg8
                   applicationController:(id)arg9 {
    NSUInteger maxRecents = ARIMaxRecents();
    return %orig(maxRecents, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9);
}

// iOS 16
- (id)initWithMaximumNumberOfSuggestions:(unsigned long long)arg1 
                          iconController:(id)arg2 
                       recentsController:(id)arg3 
                        recentsDataStore:(id)arg4 
                         recentsDefaults:(id)arg5 
                    floatingDockDefaults:(id)arg6 
                    appSuggestionManager:(id)arg7 
                   applicationController:(id)arg8 {
    NSUInteger maxRecents = ARIMaxRecents();
    return %orig(maxRecents, arg2, arg3, arg4, arg5, arg6, arg7, arg8);
}

%end

static __weak SBFloatingDockView *presentedFloatingDockView;

%hook SBFloatingDockView
%property (nonatomic, assign) BOOL _atriaWroteBackgroundOpacity;
%property (nonatomic, assign) BOOL _atriaMovedPod;

%new
+ (SBFloatingDockView *)_atriaPresentedDockView {
    return presentedFloatingDockView;
}

- (void)layoutSubviews {
    %orig;
    // Frames are rewritten on every pass, so the move is never applied twice
    if([[ARITweakManager sharedInstance] boolValueForKey:@"floatingDockPodBeforeRecents"])
        self._atriaMovedPod = ARIMovePodBeforeRecents(self);
    else if(self._atriaMovedPod)
        self._atriaMovedPod = NO;
}

%new
- (void)_atriaUpdateDockForSettingsChanged {
    if([[ARITweakManager sharedInstance] boolValueForKey:@"floatingDockPodBeforeRecents"] != self._atriaMovedPod)
        [self setNeedsLayout];

    float alpha = [[ARITweakManager sharedInstance] floatValueForKey:@"dock_bg"];
    if(alpha == 1 && !self._atriaWroteBackgroundOpacity) return;
    self._atriaWroteBackgroundOpacity = alpha != 1;
    self.backgroundView.layer.opacity = alpha;
}

- (void)didMoveToSuperview {
    %orig;
    if(self.superview) presentedFloatingDockView = self;
    [self _atriaUpdateDockForSettingsChanged];
}

- (void)traitCollectionDidChange:(UITraitCollection *)old {
    %orig(old);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _atriaUpdateDockForSettingsChanged];
    });
}

%end

%hook SBFloatingDockPlatterView

- (void)setBackgroundView:(UIView *)arg1 {
    float alpha = [[ARITweakManager sharedInstance] floatValueForKey:@"dock_bg"];
    if(alpha != 1) arg1.layer.opacity = alpha;
    %orig(arg1);
}

%end

%ctor {
	if([[ARITweakManager sharedInstance] isEnabled]) {
		ARILog(@"Loading hooks from %s", __FILE__);
		%init();
	}
}
