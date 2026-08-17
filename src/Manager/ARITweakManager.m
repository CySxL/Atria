//
// Created by ren7995 on 2021-04-25 12:49:07
// Copyright (c) 2021 ren7995. All rights reserved.
//

#import "ARITweakManager.h"
#import "ARIEditManager.h"

#import "../ARIPaths.h"
#import "../Hooks/Shared.h"

#import <objc/runtime.h>

// How long a value that has stopped moving takes to settle into place
static const NSTimeInterval kARISettledDuration = 0.6;

// The dock list view is found by walking the hierarchy, so hold it weakly
// rather than repeating the walk, and never keep it alive
@interface ARIWeakBox : NSObject
@property (nonatomic, weak) id object;
@end

@implementation ARIWeakBox
@end

@implementation ARITweakManager {
    ARIWeakBox *_dockListViewRef;
    BOOL _enabled;
    NSUserDefaults *_preferences;
    NSMutableOrderedSet<NSString *> *_orderedSettingKeys;
    NSMutableDictionary<NSString *, ARIOption *> *_optionsRegistry;
    NSMapTable *_listViewModelMap;
    NSMutableDictionary<NSNumber *, NSString *> *_prefixCache;
    NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSString *> *> *_pageKeyCache;
    NSMutableDictionary<NSString *, id> *_valueCache;
    BOOL _hasPerPageLayouts;
    BOOL _hasPageScopedKeys;
    BOOL _labelOffsetStateValid;
    BOOL _usesDockLabelOffset;
    BOOL _usesHsLabelOffset;
    NSUInteger _firmwareVersion;
    BOOL _deviceIPad;
    BOOL _shyLabelsInstalled;
}

@synthesize enabled = _enabled;
@synthesize preferences = _preferences;
@synthesize firmwareVersion = _firmwareVersion;
@synthesize deviceIPad = _deviceIPad;
@synthesize shyLabelsInstalled = _shyLabelsInstalled;
@synthesize listViewModelMap = _listViewModelMap;

// Shared instance and init methods

- (instancetype)init {
    self = [super init];
    if(self) {
        // Detect iOS version and model
        UIDevice *device = [UIDevice currentDevice];
        _firmwareVersion = [[[device systemVersion] componentsSeparatedByString:@"."][0] integerValue];
        _deviceIPad = [[device model] hasPrefix:@"iPad"];
        // ShyLabels compatibility
        _shyLabelsInstalled = [[NSFileManager defaultManager] fileExistsAtPath:ARIDylibPath(@"ShyLabels.dylib")];
        // NSUserDefaults to get what values the user set
        _preferences = [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];
        _enabled = [_preferences objectForKey:@"enabled"] ? [[_preferences objectForKey:@"enabled"] boolValue] : YES;
        _listViewModelMap = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory valueOptions:NSPointerFunctionsWeakMemory];
        _prefixCache = [NSMutableDictionary new];
        _pageKeyCache = [NSMutableDictionary new];
        _valueCache = [NSMutableDictionary new];

        // Create settings
        _orderedSettingKeys = [[NSMutableOrderedSet alloc] initWithCapacity:50];
        _optionsRegistry = [[NSMutableDictionary alloc] init];

        [self _registerOption:@"showWelcome"
                  translation:nil
                 defaultValue:@(YES)
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"showWeatherIcon"
                  translation:nil
                 defaultValue:@(YES)
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"weatherRefreshInterval"
                  translation:nil
                 defaultValue:@(0)
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"showTooltips"
                  translation:nil
                 defaultValue:@(YES)
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"labelText"
                  translation:nil
                 defaultValue:@"\%GREETING\%, user"
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"labelTextColor"
                  translation:nil
                 defaultValue:@"#FFFFFF"
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"blurTintColor"
                  translation:nil
                 defaultValue:@"#FFFFFF"
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"layoutEnabled"
                  translation:nil
                 defaultValue:@(YES)
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"enableAppLibrary"
                  translation:nil
                 defaultValue:@(YES)
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"saveIconState"
                  translation:nil
                 defaultValue:@(YES)
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"hideLabelsAppLibrary"
                  translation:nil
                 defaultValue:@(YES)
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"hideLabels"
                  translation:nil
                 defaultValue:@(YES)
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"hideLabelsFolders"
                  translation:nil
                 defaultValue:@(YES)
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"scaleInsideFolders"
                  translation:nil
                 defaultValue:@(YES)
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"dynamicWidgetSizing"
                  translation:nil
                 defaultValue:@(YES)
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"floatingDockAppLibrary"
                  translation:nil
                 defaultValue:@(YES)
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"floatingDockRecents"
                  translation:nil
                 defaultValue:@(YES)
                   lowerLimit:0
                   upperLimit:0];
        [self _registerOption:@"maxFloatingDockRecents"
                  translation:nil
                 defaultValue:@(3)
                   lowerLimit:0
                   upperLimit:0];

        // Homescreen
        [self _registerOption:@"hs_rows"
                  translation:@"Rows"
                 defaultValue:@(6)
                   lowerLimit:2.0F
                   upperLimit:20.0F];
        [self _registerOption:@"hs_columns"
                  translation:@"Columns"
                 defaultValue:@(4)
                   lowerLimit:2.0F
                   upperLimit:20.0F];
        [self _registerOption:@"hs_iconScale"
                  translation:@"Icon Scale"
                 defaultValue:@(1.0)
                   lowerLimit:0.01F
                   upperLimit:2.0F];
        [self _registerOption:@"hs_widgetIconScale"
                  translation:@"Widget Scale"
                 defaultValue:@(1.0)
                   lowerLimit:0.01F
                   upperLimit:3.0F];
        [self _registerOption:@"hs_spacing_x"
                  translation:@"Icon Spacing X"
                 defaultValue:@(0)
                   lowerLimit:-100.0F
                   upperLimit:100.0F];
        [self _registerOption:@"hs_spacing_y"
                  translation:@"Icon Spacing Y"
                 defaultValue:@(0)
                   lowerLimit:-100.0F
                   upperLimit:100.0F];
        [self _registerOption:@"hs_inset_top"
                  translation:@"Top Inset"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];
        [self _registerOption:@"hs_inset_left"
                  translation:@"Left Inset"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];
        [self _registerOption:@"hs_inset_bottom"
                  translation:@"Bottom Inset"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];
        [self _registerOption:@"hs_inset_right"
                  translation:@"Right Inset"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];
        [self _registerOption:@"hs_offset_top"
                  translation:@"Page Top Offset"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];
        [self _registerOption:@"hs_offset_left"
                  translation:@"Page Left Offset"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];
        [self _registerOption:@"hs_label_offset"
                  translation:@"Label Y Offset"
                 defaultValue:@(0)
                   lowerLimit:-40.0F
                   upperLimit:40.0F];
        [self _registerOption:@"hs_widgetXOffset"
                  translation:@"Widget X Offset"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];
        [self _registerOption:@"hs_widgetYOffset"
                  translation:@"Widget Y Offset"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];

        // Dock options
        // For some reason, on iOS 15 only (not 13-14 or 16+), calling +isFloatingDockSupported leads to a respring loop.
        // Once SpringBoard launches, this option will be re-registered to adjust the default value if floating dock is enabled.
        [self _registerOption:@"dock_columns"
                  translation:@"Columns"
                 defaultValue:@(4)
                   lowerLimit:2.0F
                   upperLimit:20.0F];
        [self _registerOption:@"dock_rows"
                  translation:@"Rows"
                 defaultValue:@(1)
                   lowerLimit:1.0F
                   upperLimit:5.0F];
        [self _registerOption:@"dock_iconScale"
                  translation:@"Icon Scale"
                 defaultValue:@(1)
                   lowerLimit:0.01F
                   upperLimit:2.0F];
        [self _registerOption:@"dock_bg"
                  translation:@"Background Alpha"
                 defaultValue:@(1)
                   lowerLimit:0.0F
                   upperLimit:1.0F];
        [self _registerOption:@"dock_spacing_x"
                  translation:@"Icon Spacing X"
                 defaultValue:@(0)
                   lowerLimit:-100.0F
                   upperLimit:100.0F];
        [self _registerOption:@"dock_spacing_y"
                  translation:@"Icon Spacing Y"
                 defaultValue:@(0)
                   lowerLimit:-100.0F
                   upperLimit:100.0F];
        [self _registerOption:@"dock_label_offset"
                  translation:@"Label Offset"
                 defaultValue:@(0)
                   lowerLimit:-40.0F
                   upperLimit:40.0F];
        [self _registerOption:@"dock_inset_top"
                  translation:@"Top Inset"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];
        [self _registerOption:@"dock_inset_left"
                  translation:@"Left Inset"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];
        [self _registerOption:@"dock_inset_bottom"
                  translation:@"Bottom Inset"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];
        [self _registerOption:@"dock_inset_right"
                  translation:@"Right Inset"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];

        // Page labels
        [self _registerOption:@"label_textSize"
                  translation:@"Text Size"
                 defaultValue:@(27)
                   lowerLimit:1.0F
                   upperLimit:60.0F];
        [self _registerOption:@"label_inset_left"
                  translation:@"Side Inset"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];
        [self _registerOption:@"label_inset_top"
                  translation:@"Vertical Inset"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];

        // Blur background
        [self _registerOption:@"blur_alpha"
                  translation:@"Background Alpha"
                 defaultValue:@(1)
                   lowerLimit:0.0F
                   upperLimit:1.0F];
        [self _registerOption:@"blur_corner_radius"
                  translation:@"Corner Radius"
                 defaultValue:@(14)
                   lowerLimit:0.0F
                   upperLimit:100.0F];
        [self _registerOption:@"blur_intensity"
                  translation:@"Tint Intensity"
                 defaultValue:@(0.5F)
                   lowerLimit:0.0F
                   upperLimit:1.0F];

        [self _registerOption:@"blur_inset_top"
                  translation:@"Top Position"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];
        [self _registerOption:@"blur_inset_left"
                  translation:@"Left Position"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];
        [self _registerOption:@"blur_inset_bottom"
                  translation:@"Bottom Position"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];
        [self _registerOption:@"blur_inset_right"
                  translation:@"Right Position"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];

        // Page dots
        [self _registerOption:@"pagedot_offsetX"
                  translation:@"Dot X Offset"
                 defaultValue:@(0)
                   lowerLimit:-150.0F
                   upperLimit:150.0F];
        [self _registerOption:@"pagedot_offsetY"
                  translation:@"Dot Y Offset"
                 defaultValue:@(0)
                   lowerLimit:-200.0F
                   upperLimit:200.0F];

        // After registration: migration reads and writes through the same
        // accessors, and those fall back to the registered defaults
        [self _migrateSettings];
        [self reloadPreferenceState];
    }
    return self;
}

+ (instancetype)sharedInstance {
    static dispatch_once_t token;
    static ARITweakManager *manager;
    dispatch_once(&token, ^{
        manager = [[self alloc] init];
    });
    return manager;
}

- (void)_migrateSettings {
    // Horrible code but I just need it to work, this only runs once ever
    if([self intValueForKey:@"_settingsMigrationVersion"] >= 1) {
        return;
    }

    // Save state
    [self _migrateSettingFromKey:@"saveState" toKey:@"_saveState"];

    // Update list of per-page layout enabled list views
    NSMutableArray *perPage = [(NSArray *)[self rawValueForKey:ARIPerPageListViewsKey] mutableCopy];
    NSUInteger itemCount = [perPage count];
    if(itemCount > 0) {
        for(NSUInteger i = 0; i < itemCount; i++) {
            NSString *newValue = [NSString stringWithFormat:@"Page%@_", [perPage[i] stringByReplacingOccurrencesOfString:@"_" withString:@""]];
            [perPage replaceObjectAtIndex:i withObject:newValue];
        }
        [self setValue:perPage forKey:ARIPerPageListViewsKey];
    }

    // Our own domain only. -dictionaryRepresentation merges in NSGlobalDomain
    // and the system defaults, which the rewrites below would happily match.
    NSDictionary *dict = [_preferences persistentDomainForName:ARIPreferenceDomain];
    for(NSString *key in [dict allKeys]) {
        // Welcome is now renamed to label
        if([key hasPrefix:@"welcome"]) {
            NSString *newKey = [key stringByReplacingCharactersInRange:NSMakeRange(0, 7) withString:@"label"];
            [self _migrateSettingFromKey:key toKey:newKey];
            continue;
        }

        if([key length] <= 3) continue;
        // Previous per-page layout prefix was formatted as _%d_ and now is Page%d_
        NSString *sub = [key substringToIndex:3];
        if([sub hasPrefix:@"_"] && [sub hasSuffix:@"_"]) {
            NSString *newKey = [NSString
                stringWithFormat:@"Page%@_%@",
                                 [sub stringByReplacingOccurrencesOfString:@"_"
                                                                withString:@""],
                                 [key stringByReplacingOccurrencesOfString:sub
                                                                withString:@""]];
            [self _migrateSettingFromKey:key toKey:newKey];
            continue;
        }
    }

    // Set migration Version
    [self setValue:@(1) forKey:@"_settingsMigrationVersion"];
}

- (void)_migrateSettingFromKey:(NSString *)oldKey toKey:(NSString *)newKey {
    [_preferences setObject:[self rawValueForKey:oldKey] forKey:newKey];
    [_preferences removeObjectForKey:oldKey];
    [self _didWritePreferencesForKey:newKey];
}

- (void)_registerOption:(NSString *)key
            translation:(NSString *)translation
           defaultValue:(id)defaultValue
             lowerLimit:(float)lower
             upperLimit:(float)upper {
    float range[] = {lower, upper};
    ARIOption *option = [[ARIOption alloc] initWithKey:key
                                           translation:translation
                                          defaultValue:defaultValue
                                                 range:range];
    if(option.accessibleWithEditor)
        [_orderedSettingKeys addObject:option.settingKey];
    [_optionsRegistry setObject:option forKey:option.settingKey];
}

// Runtime manager methods

- (void)updateLayoutForEditing:(BOOL)animated {
    [self updateLayoutForEditingWithDuration:animated ? kARISettledDuration : 0];
}

- (void)updateLayoutForEditingWithDuration:(NSTimeInterval)duration {
    NSString *editingLocation = [ARIEditManager sharedInstance].editingLocation;
    if(!editingLocation) return;

    if([editingLocation isEqualToString:@"pagedot"]) {
        // Will use cached metrics (see hook in PageDots.xm)
        [[self rootFolderView] layoutPageControlWithMetrics:NULL];
        return;
    }

    BOOL updateRoot = [editingLocation isEqualToString:@"hs"] || [editingLocation isEqualToString:@"label"] || [editingLocation isEqualToString:@"blur"];
    [self updateLayoutForRoot:updateRoot forDock:[editingLocation isEqualToString:@"dock"] duration:duration];
}

// Updates all layout

- (void)updateLayoutForRoot:(BOOL)forRoot forDock:(BOOL)forDock animated:(BOOL)animated {
    [self updateLayoutForRoot:forRoot forDock:forDock duration:animated ? kARISettledDuration : 0];
}

- (void)updateLayoutForRoot:(BOOL)forRoot forDock:(BOOL)forDock duration:(NSTimeInterval)duration {
    SBRootFolderView *rootFolderView = [self rootFolderView];

    void (^updateVisibleIcons)(BOOL finished) = ^void(BOOL finished) {
        SBIconListView *current = [self currentListView];
        // Update visible columns and rows for current list view. Otherwise, SB doesn't
        // update this until we start scrolling
        if([current respondsToSelector:@selector(setVisibleColumnRange:)])
            [current setVisibleColumnRange:NSMakeRange(0, [self gridValueForKey:@"hs_columns" forListView:current])];
        if([current respondsToSelector:@selector(setVisibleRowRange:)])
            [current setVisibleRowRange:NSMakeRange(0, [self gridValueForKey:@"hs_rows" forListView:current])];
    };

    void (^applyLayout)() = ^void() {
        if(forDock) {
            // Layout dock icons and set alpha
            // Which branch holds the dock's icons, not which views are safe to
            // touch. With the dock forced on, they live under the controller.
            if(![[self class] isUsingFloatingDock]) {
                SBIconListView *listView = [self _dockListView];
                [[rootFolderView dockView] _atriaUpdateDockForSettingsChanged];
                [self _refreshIconViewsInListView:listView];
                [listView layoutIconsNow];
            } else {
                SBFloatingDockController *fdController = [objc_getClass("SBFloatingDockController") _atriaSharedInstance];
                // Icon list and suggestions
                [self _refreshIconViewsInListView:[fdController userIconListView]];
                [self _refreshIconViewsInListView:[fdController suggestionsIconListView]];
                [[fdController userIconListView] layoutIconsNow];
                [[fdController suggestionsIconListView] layoutIconsNow];
                // Fix for library pod icon. This one alone writes a transform onto
                // the pod the App Library zooms from, so it stays on iPads.
                if([[self class] shouldTouchFloatingDockViews]) {
                    SBFloatingDockViewController *fdvc = [fdController floatingDockViewController];
                    if([fdvc respondsToSelector:@selector(libraryPodIconView)])
                        [[fdvc libraryPodIconView] _atriaUpdateIconContentScale];
                }
            }
            // The background alpha is a plain opacity write, so a forced dock on
            // iPhone gets it too. Only reached once SpringBoard has built one.
            [self _updateFloatingDockBackground];
        }

        if(forRoot) {
            // -layoutIconsNow repositions icon views without changing their
            // bounds, so it never reaches -layoutSubviews. Only the page on
            // screen needs refreshing now, the rest catch up when laid out.
            [self _refreshIconViewsInListView:[self currentListView]];
            // Enumerate list views in root and lay them out as well
            for(SBIconListView *listView in rootFolderView.iconListViews) {
                [listView layoutIconsNow];
            }
        }
    };

    if(duration <= 0) {
        applyLayout();
        updateVisibleIcons(YES);
        return;
    }

    // A drag step has to run straight into the next one, so it interpolates
    // linearly. A settled value eases.
    UIViewAnimationOptions curve = duration <= ARIDragApplyInterval
                                       ? UIViewAnimationOptionCurveLinear
                                       : UIViewAnimationOptionCurveEaseInOut;
    [UIView animateWithDuration:duration
                          delay:0.0f
                        options:curve
                     animations:applyLayout
                     completion:updateVisibleIcons];
}

static SBIconListView *ARIFindDockListView(UIView *view, NSInteger depth) {
    static Class listViewClass;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        listViewClass = objc_getClass("SBIconListView");
    });

    if(!view || depth > 4) return nil;
    for(UIView *subview in view.subviews) {
        if([subview isKindOfClass:listViewClass]) {
            SBIconListView *candidate = (SBIconListView *)subview;
            if(IconListIsDock(candidate)) return candidate;
        }
        SBIconListView *found = ARIFindDockListView(subview, depth + 1);
        if(found) return found;
    }
    return nil;
}

// The _dockListView ivar the original code read is empty from iOS 16 on, and
// nothing said so: the dock kept working because everything else reaches it by
// another route, and only the label offset went through here. Find the list by
// the location it reports instead of by an ivar name.
- (SBIconListView *)_dockListView {
    SBIconListView *cached = _dockListViewRef.object;
    if(cached.superview && IconListIsDock(cached)) return cached;

    SBRootFolderView *rootFolderView = [self rootFolderView];
    SBIconListView *listView = ARIFindDockListView([rootFolderView dockView], 0)
                                   ?: ARIFindDockListView(rootFolderView, 0);
    if(!_dockListViewRef) _dockListViewRef = [ARIWeakBox new];
    _dockListViewRef.object = listView;
    return listView;
}

// A plain opacity write, so a forced dock on iPhone gets it too. Goes through
// the view SpringBoard already presented rather than the controller, which
// would build one where none belongs.
- (void)_updateFloatingDockBackground {
    [[objc_getClass("SBFloatingDockView") _atriaPresentedDockView] _atriaUpdateDockForSettingsChanged];
}

// Icon views only consult the label setting when they are added to a list, so
// nudge the existing ones when the dock label switch is toggled
- (void)_refreshIconView:(SBIconView *)iconView {
    if(!iconView) return;
    // Setting this rebuilds the label, and a rebuilt label has no frame for the
    // offset to move until the next layout pass. Only drive it when the answer
    // has actually changed; SpringBoard's own calls are untouched.
    BOOL allows = [iconView _atriaEffectiveAllowsLabelArea:iconView.allowsLabelArea];
    if(allows != iconView.allowsLabelArea) [iconView setAllowsLabelArea:allows];
    [iconView _atriaApplyDockLabelOffset];
}

- (void)_refreshIconViewsInListView:(SBIconListView *)listView {
    [self _refreshIconViewsInListView:listView updatingDropShadow:NO];
}

- (void)_refreshIconViewsInListView:(SBIconListView *)listView updatingDropShadow:(BOOL)dropShadow {
    static Class iconViewClass;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        iconViewClass = objc_getClass("SBIconView");
    });

    BOOL editing = dropShadow && [[[objc_getClass("SBIconController") sharedInstance] iconManager] isEditing];

    // -icons hands back the model's icons rather than the views showing them,
    // so walk the hierarchy instead of messaging whatever that array holds
    for(UIView *subview in listView.subviews) {
        if(![subview isKindOfClass:iconViewClass]) continue;
        [self _refreshIconView:(SBIconView *)subview];
        if(dropShadow) [(SBIconView *)subview _atriaSetupDropShadow:editing];
    }
}

// What a settings change can touch without going near the grid. The layout
// hooks are optional, and forcing a visible range against row and column counts
// they aren't applying would hide icons.
- (void)refreshPreferenceDependentViews {
    for(SBIconListView *listView in [self allRootListViews])
        [self _refreshIconViewsInListView:listView updatingDropShadow:YES];

    if(![[self class] isUsingFloatingDock]) {
        [self _refreshIconViewsInListView:[self _dockListView] updatingDropShadow:YES];
        [[[self rootFolderView] dockView] _atriaUpdateDockForSettingsChanged];
    } else {
        SBFloatingDockController *fdController = [objc_getClass("SBFloatingDockController") _atriaSharedInstance];
        [self _refreshIconViewsInListView:[fdController userIconListView] updatingDropShadow:YES];
    }
    [self _updateFloatingDockBackground];
}

// This lags the device somewhat, so limit this as much as possible!
- (void)relayoutEntireIconModel {
    // This will cause the entire icon model to re-layout
    [[[[objc_getClass("SBIconController") sharedInstance] iconManager] iconModel] layout];
    // In order to fix the custom widget sizing, we need to call this
    [self updateLayoutForRoot:YES forDock:NO animated:NO];
}

// Util

- (void)feedbackForButton {
    // Create a generator (just like in AppStore apps) and make it give feedback
    static UIImpactFeedbackGenerator *generator = nil;
    if(!generator) generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleSoft];
    [generator impactOccurred];
}

- (void)onSpringboardLaunched {

    // If floating dock is enabled, default to 6 dock columns. See explanation in init method for why this is done here.
    if([self boolValueForKey:@"forceFloatingDock"] || [[self class] isUsingFloatingDock]) {
        [self _registerOption:@"dock_columns"
                  translation:@"Columns"
                 defaultValue:@(15) // iPad Pro dock icon limit
                   lowerLimit:2.0F
                   upperLimit:20.0F];
        [self relayoutEntireIconModel];
    }

    // Fixes the floating dock background alpha on iOS 14
    [self _updateFloatingDockBackground];
}

- (SBRootFolderView *)rootFolderView {
    return [[[objc_getClass("SBIconController") sharedInstance] _rootFolderController] rootFolderView];
}

- (NSArray<SBIconListView *> *)allRootListViews {
    return [self rootFolderView].iconListViews;
}

- (NSUInteger)indexOfListView:(SBIconListView *)target {
    return [[self allRootListViews] indexOfObject:target];
}

- (SBIconListView *)firstIconListView {
    return [[self rootFolderView] firstIconListView];
}

- (SBIconListView *)currentListView {
    return [self rootFolderView].currentIconListView;
}

// Returns a string which serves as a prefix for per-page layout settings

- (NSString *)prefixForListView:(SBIconListView *)target {
    if(!target || !IconListIsRoot(target)) return @"";
    return [self _prefixForIndex:[self indexOfListView:target]];
}

// Both of these are pure functions of their inputs, and the layout path asks
// for them once per icon per pass, so build each string only once. The index
// itself is still looked up every time, since page order can change.

- (NSString *)_prefixForIndex:(NSUInteger)index {
    NSNumber *boxed = @(index);
    NSString *prefix = _prefixCache[boxed];
    if(!prefix) {
        prefix = [NSString stringWithFormat:@"Page%d_", (int)index];
        _prefixCache[boxed] = prefix;
    }
    return prefix;
}

- (NSString *)_pageKeyForPrefix:(NSString *)prefix key:(NSString *)key {
    NSMutableDictionary<NSString *, NSString *> *keys = _pageKeyCache[prefix];
    if(!keys) {
        keys = [NSMutableDictionary new];
        _pageKeyCache[prefix] = keys;
    }

    NSString *pageKey = keys[key];
    if(!pageKey) {
        pageKey = [prefix stringByAppendingString:key];
        keys[key] = pageKey;
    }
    return pageKey;
}

// Obtain information about available settings

- (NSOrderedSet<NSString *> *)editorSettingsKeys {
    return _orderedSettingKeys;
}

- (ARIOption *)getSettingByKey:(NSString *)key {
    return _optionsRegistry[key];
}

// Get/set preference values

- (int)intValueForKey:(NSString *)key {
    return (int)[[self rawValueForKey:key] integerValue];
}

- (BOOL)boolValueForKey:(NSString *)key {
    return [[self rawValueForKey:key] boolValue];
}

- (float)floatValueForKey:(NSString *)key {
    return [[self rawValueForKey:key] floatValue];
}

// Every typed accessor comes through here, and -[SBIconBadgeView alpha], the
// label offsets and the shadow hooks ask on every render pass, where a defaults
// lookup is far dearer than a dictionary hit. A key with nothing stored and no
// registered default is remembered as NSNull so it is not asked for twice.
- (id)rawValueForKey:(NSString *)key {
    id cached = _valueCache[key];
    if(cached) return cached == [NSNull null] ? nil : cached;

    id value = [_preferences objectForKey:key] ?: [_optionsRegistry objectForKey:key].defaultValue;
    _valueCache[key] = value ?: [NSNull null];
    return value;
}

// The flags below are sticky, so they only ever need to notice an offset
// switching on. Anything else a write touches would not change the answer.
- (void)_didWritePreferencesForKey:(NSString *)key {
    if(!key || [key hasSuffix:@"label_offset"]) _labelOffsetStateValid = NO;
    // A page label saved just now has to be readable before the next reload
    if([key hasPrefix:@"Page"]) _hasPageScopedKeys = YES;
}

// The layout path asks this for every icon, so it has to be cheap. Sticky on
// purpose: were it allowed back to NO, setting an offset to zero would return
// early and leave the last offset stuck on the label instead of clearing it.
- (void)_ensureLabelOffsetState {
    if(_labelOffsetStateValid) return;
    _labelOffsetStateValid = YES;

    _usesDockLabelOffset |= [self floatValueForKey:@"dock_label_offset"] != 0;
    _usesHsLabelOffset |= [self floatValueForKey:@"hs_label_offset"] != 0;
    if(_usesHsLabelOffset || !_hasPerPageLayouts) return;

    // A page may set one while the global value is still zero. The prefixes are
    // already known, so ask for those keys rather than dumping the whole domain,
    // which would carry the saved icon state with it.
    for(NSString *prefix in (NSArray *)[_preferences objectForKey:ARIPerPageListViewsKey]) {
        if(![prefix isKindOfClass:[NSString class]]) continue;
        NSString *key = [self _pageKeyForPrefix:prefix key:@"hs_label_offset"];
        if([[_preferences objectForKey:key] floatValue] == 0) continue;
        _usesHsLabelOffset = YES;
        return;
    }
}

- (BOOL)usesLabelOffset {
    [self _ensureLabelOffsetState];
    return _usesDockLabelOffset || _usesHsLabelOffset;
}

- (BOOL)usesDockLabelOffset {
    [self _ensureLabelOffsetState];
    return _usesDockLabelOffset;
}

- (BOOL)usesHsLabelOffset {
    [self _ensureLabelOffsetState];
    return _usesHsLabelOffset;
}

// Callers pass these straight to NSString methods. A stored value of the wrong
// type would be an unrecognised selector inside SpringBoard, so fall back to
// the default instead of trusting whatever is on disk.
- (NSString *)stringValueForKey:(NSString *)key {
    id value = [_preferences objectForKey:key];
    if([value isKindOfClass:[NSString class]]) return value;

    id fallback = [_optionsRegistry objectForKey:key].defaultValue;
    return [fallback isKindOfClass:[NSString class]] ? fallback : nil;
}

- (void)setValue:(id)val forKey:(NSString *)key {
    if([val isEqual:_optionsRegistry[key].defaultValue]) {
        // Matches default value, remove from preferences
        [self resetValueForKey:key];
    } else {
        if(![val isEqual:[_preferences objectForKey:key]])
            [_preferences setObject:val forKey:key];
        [_valueCache removeObjectForKey:key];
        [self _didWritePreferencesForKey:key];
    }
}

// -setValue:forKey: compares against the stored value to avoid a needless
// write. For the saved icon state that comparison walks every icon on every
// page, which costs more than the write it is trying to avoid.
- (void)setRawValue:(id)val forKey:(NSString *)key {
    [_preferences setObject:val forKey:key];
    [_valueCache removeObjectForKey:key];
    [self _didWritePreferencesForKey:key];
}

- (void)resetValueForKey:(NSString *)key {
    [_preferences removeObjectForKey:key];
    [_valueCache removeObjectForKey:key];
    [self _didWritePreferencesForKey:key];
}

// Get/set preference values by icon list view
// We try to locate value for the current list view, if it exists

// These run for every icon on every layout pass, so avoid building the page
// key at all unless the list view actually has a per-page prefix.

- (id)_pageValueForKey:(NSString *)key forListView:(SBIconListView *)list {
    // Skip the list view index lookup when nothing is stored per page. Keyed on
    // the presence of Page%d_ keys and not on the per-page layout list, because
    // a page label writes one without registering a layout. Read path only:
    // -createCustomForListView: needs a real prefix before the page is added.
    if(!_hasPageScopedKeys) return nil;

    NSString *prefix = [self prefixForListView:list];
    if(![prefix length]) return nil;
    // Page keys are not registered, so the registry fallback in there is nil and
    // this keeps the stored value only, which is what the callers below expect
    return [self rawValueForKey:[self _pageKeyForPrefix:prefix key:key]];
}

- (int)intValueForKey:(NSString *)key forListView:(SBIconListView *)list {
    id value = [self _pageValueForKey:key forListView:list];
    return value ? (int)[value integerValue] : [self intValueForKey:key];
}

// Row and column counts are typed freely in the editor. Anything below one
// reaches UIKit either as a division by zero or, once the signed value is
// assigned to NSUInteger, as a count near NSUIntegerMax. The value is saved to
// preferences, so an unusable homescreen would survive the respring too.
- (NSUInteger)gridValueForKey:(NSString *)key forListView:(SBIconListView *)list {
    int value = [self intValueForKey:key forListView:list];
    return value < 1 ? 1 : (NSUInteger)value;
}

- (BOOL)boolValueForKey:(NSString *)key forListView:(SBIconListView *)list {
    id value = [self _pageValueForKey:key forListView:list];
    return value ? [value boolValue] : [self boolValueForKey:key];
}

- (id)rawValueForKey:(NSString *)key forListView:(SBIconListView *)list {
    return [self _pageValueForKey:key forListView:list] ?: [self rawValueForKey:key];
}

- (NSString *)stringValueForKey:(NSString *)key forListView:(SBIconListView *)list {
    id value = [self _pageValueForKey:key forListView:list];
    if([value isKindOfClass:[NSString class]]) return value;
    return [self stringValueForKey:key];
}

- (float)floatValueForKey:(NSString *)key forListView:(SBIconListView *)list {
    id value = [self _pageValueForKey:key forListView:list];
    return value ? [value floatValue] : [self floatValueForKey:key];
}

- (void)setValue:(id)val forKey:(NSString *)key forListView:(SBIconListView *)listView {
    if(!listView)
        [self setValue:val forKey:key];
    else
        [self setValue:val forKey:[self _pageKeyForPrefix:[self prefixForListView:listView] key:key]];
}

- (void)resetValueForKey:(NSString *)key forListView:(SBIconListView *)listView {
    if(!listView)
        [self resetValueForKey:key];
    else
        [self resetValueForKey:[self _pageKeyForPrefix:[self prefixForListView:listView] key:key]];
}

// Per-page layout creation/deletion and management

// Called on launch and whenever preferences change underneath us, so anything
// derived from defaults and held in memory gets rebuilt here
- (void)reloadPreferenceState {
    _hasPerPageLayouts = [(NSArray *)[_preferences objectForKey:ARIPerPageListViewsKey] count] > 0;

    // Page labels write a Page%d_ key without registering a layout, so the read
    // path cannot go by the layout list alone. Settings changes are rare enough
    // to afford the scan; the read path itself only sees the flag.
    _hasPageScopedKeys = _hasPerPageLayouts;
    if(!_hasPageScopedKeys) {
        for(NSString *key in [_preferences persistentDomainForName:ARIPreferenceDomain]) {
            if(![key hasPrefix:@"Page"]) continue;
            _hasPageScopedKeys = YES;
            break;
        }
    }

    [_valueCache removeAllObjects];
    [self _didWritePreferencesForKey:nil];
}

- (void)deleteCustomForListView:(SBIconListView *)listView {
    // Delete any keys for that list view
    NSString *prefix = [self prefixForListView:listView];
    NSDictionary *preferences = [_preferences persistentDomainForName:ARIPreferenceDomain];
    for(NSString *key in [preferences allKeys]) {
        if([key hasPrefix:prefix]) [self resetValueForKey:key];
    }

    NSMutableArray *perPage = [(NSArray *)[self rawValueForKey:ARIPerPageListViewsKey] mutableCopy] ?: [NSMutableArray new];
    [perPage removeObject:prefix];
    [self setValue:perPage forKey:ARIPerPageListViewsKey];
    [self reloadPreferenceState];

    [self updateLayoutForEditing:YES];
}

- (void)createCustomForListView:(SBIconListView *)listView {
    // Freeze list view settings to what the current global config is
    NSString *prefix = [self prefixForListView:listView];

    NSMutableArray *perPage = [(NSArray *)[self rawValueForKey:ARIPerPageListViewsKey] mutableCopy] ?: [NSMutableArray new];
    [perPage addObject:prefix];
    [self setValue:perPage forKey:ARIPerPageListViewsKey];

    // These go straight into the domain, so the reload that clears the read
    // cache has to come after them, not before
    for(NSString *key in _orderedSettingKeys) {
        [_preferences setObject:[self rawValueForKey:key]
                         forKey:[NSString stringWithFormat:@"%@%@", prefix, key]];
    }
    [self reloadPreferenceState];
    [self updateLayoutForEditing:YES];
}

- (BOOL)doesCustomConfigForListViewExist:(SBIconListView *)listView {
    NSArray *perPage = [self rawValueForKey:ARIPerPageListViewsKey];
    if(!perPage) return NO;
    return [perPage containsObject:[self prefixForListView:listView]];
}

+ (UIInterfaceOrientation)currentDeviceOrientation {
    return [[[UIApplication sharedApplication] windows] firstObject].windowScene.interfaceOrientation;
}

+ (BOOL)isUsingFloatingDock {
    return [objc_getClass("SBFloatingDockController") isFloatingDockSupported];
}

// Guards the one call that was measured to cause harm: scaling the library pod
// writes a transform onto the view the App Library zooms from, and with the dock
// forced on an iPhone that left every transition collapsing into the top corner
// until the next respring. Everything else about the forced dock is real and
// must not be withheld, since that is where its icons live.
+ (BOOL)shouldTouchFloatingDockViews {
    return [self isUsingFloatingDock] && [[self sharedInstance] isDeviceIPad];
}

// These two only act on a dock SpringBoard has already built, so they follow
// the forced answer. Withholding them left the keyboard fighting a floating
// dock nothing was allowed to put away.

+ (void)dismissFloatingDockIfPossible {
    if([self isUsingFloatingDock]) {
        [[objc_getClass("SBFloatingDockController") _atriaSharedInstance] _dismissFloatingDockIfPresentedAnimated:YES completionHandler:nil];
    }
}

+ (void)presentFloatingDockIfPossible {
    if([self isUsingFloatingDock]) {
        [[objc_getClass("SBFloatingDockController") _atriaSharedInstance] _presentFloatingDockIfDismissedAnimated:YES completionHandler:nil];
    }
}

@end
