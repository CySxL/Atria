//
// Created by ren7995 on 2021-04-25 12:49:32
// Copyright (c) 2021 ren7995. All rights reserved.
//

#import "Shared.h"
#import "../Manager/ARITweakManager.h"
#import "../Manager/ARIEditManager.h"
#import "../UI/Label/ARILabelView.h"
#import "../UI/Label/ARIPageLabelView.h"
#import "../UI/Label/ARIWelcomeLabelView.h"
#import "../UI/ARIBackgroundView.h"

static BOOL didLaunchSB = NO;

ARI_CACHED_CLASS(ARIAppLibraryProviderClass, "ARIAppLibraryIconListLayoutProvider")
ARI_CACHED_CLASS(ARIFlowExtendedLayoutClass, "SBIconListFlowExtendedLayout")
ARI_CACHED_CLASS(ARIFlowLayoutClass, "SBIconListFlowLayout")

@interface SBHDefaultIconListLayoutProvider : NSObject
- (SBIconListFlowExtendedLayout *)layoutForIconLocation:(NSString *)location;
@end

typedef struct {
	BOOL valid;
	NSUInteger prefGeneration;
	BOOL isFirstIconList;
	BOOL showPageLabel;
	BOOL showBackground;
	BOOL disableTapGesture;
	NSUInteger cols;
	NSUInteger rows;
	CGSize bounds;
	CGFloat topOffset;
	CGFloat leftOffset;
	CGFloat topInset;
	CGFloat bottomInset;
	CGFloat leftInset;
	CGFloat rightInset;
	CGFloat spaceX;
	CGFloat spaceY;
	CGFloat textSize;
	UIEdgeInsets origPortrait;
	UIEdgeInsets origLandscape;
} ARIRootLayoutInputs;

// Everything -layout reads per call sits behind one associated object
@interface ARIListLayoutState : NSObject
@property (nonatomic, weak) SBIconListModel *model;
@property (nonatomic, strong) SBIconListFlowExtendedLayout *originalLayout;
@property (nonatomic, strong) SBIconListFlowExtendedLayout *cachedLayout;
@property (nonatomic, assign) BOOL needsLayout;
@property (nonatomic, assign) BOOL modelTagged;
@property (nonatomic, assign) ARIRootLayoutInputs inputs;
@end

@implementation ARIListLayoutState
@end

@interface SBIconListView (ARIRootLayout)
@property (nonatomic, strong) ARIListLayoutState *_atriaLayoutState;
@end

static ARIListLayoutState *ARILayoutState(SBIconListView *listView) {
	ARIListLayoutState *state = listView._atriaLayoutState;
	if(!state) {
		state = [ARIListLayoutState new];
		listView._atriaLayoutState = state;
	}
	return state;
}

static BOOL ARIRootLayoutInputsUnchanged(SBIconListView *listView, ARIListLayoutState *state, ARIRootLayoutInputs inputs) {
	ARIRootLayoutInputs previous = state.inputs;
	if(!previous.valid || memcmp(&previous, &inputs, sizeof(inputs)) != 0) return NO;
	if(!state.cachedLayout) return NO;
	if(inputs.showBackground != (listView._atriaBackground.superview != nil)) return NO;
	if(inputs.showPageLabel != (listView._atriaPageLabel.superview != nil)) return NO;
	if(inputs.disableTapGesture == (listView._atriaTap != nil)) return NO;
	return YES;
}

%hook SBIconListView
%property (nonatomic, strong) ARILabelView *_atriaPageLabel;
%property (nonatomic, strong) ARIBackgroundView *_atriaBackground;
%property (nonatomic, strong) UITapGestureRecognizer *_atriaTap;
%property (nonatomic, strong) ARIListLayoutState *_atriaLayoutState;

%new
- (void)_atriaBeginEditing {
	[[ARIEditManager sharedInstance] presentEditAlert];
}

- (SBIconListFlowExtendedLayout *)layout {
	SBIconListFlowExtendedLayout *orig = %orig;

	ARIListLayoutState *state = ARILayoutState(self);
	SBIconListModel *model = [self model];
	if(state.model != model) {
		state.model = model;
		state.modelTagged = NO;
		if(model) [[ARITweakManager sharedInstance].listViewModelMap setObject:self forKey:model];
	}
	// Retried until the location exists, which may be after the first layout
	if(!state.modelTagged && model) {
		if(!model._atriaLocation) model._atriaLocation = self.iconLocation;
		state.modelTagged = model._atriaLocation != nil;
	}

	if(state.originalLayout != orig || state.needsLayout) {
		state.originalLayout = orig;
		[self _atriaUpdateLayoutCache];
		[model _atriaUpdateModelGridSizes];
		state.needsLayout = NO;
	}

	return state.cachedLayout ?: orig;
}

- (void)layoutIconsNow {
	ARILayoutState(self).needsLayout = YES;
	%orig;
}

- (void)didAddIconView:(id)arg1 {
	%orig(arg1);
	// Once an icon has been added, update layout
	if(IconListIsRoot(self) && [self.icons count] == 1) ARILayoutState(self).needsLayout = YES;
}

%new
- (void)_atriaUpdateLayoutCache {
	ARITweakManager *manager = [ARITweakManager sharedInstance];
	ARIListLayoutState *state = ARILayoutState(self);
	SBIconListFlowExtendedLayout *orig = state.originalLayout;

	// Update layout
	if(IconListIsRoot(self)) {
		// Don't update layout if there are 0 icons
		// This helps prevent unnecessary work, and additionally prevents issues related to the page reordering view
		if([self.icons count] == 0) return;

		// Checks if the icon list is actually in the root views
		BOOL isInRootViews = [[manager allRootListViews] containsObject:self];
		BOOL isFirstIconList = [manager firstIconListView] == self;

		ARIRootLayoutInputs inputs;
		memset(&inputs, 0, sizeof(inputs));
		inputs.valid = YES;
		inputs.prefGeneration = manager.preferenceGeneration;
		inputs.isFirstIconList = isFirstIconList;
		inputs.showPageLabel = (isFirstIconList && [manager boolValueForKey:@"showWelcome"]) || (isInRootViews && [manager boolValueForKey:@"showPageLabels"]);
		inputs.showBackground = isInRootViews && [manager boolValueForKey:@"showBackground"];
		inputs.disableTapGesture = [manager boolValueForKey:@"disableTapGesture"];
		inputs.bounds = self.bounds.size;
		inputs.cols = [manager gridValueForKey:@"hs_columns" forListView:self];
		inputs.rows = [manager gridValueForKey:@"hs_rows" forListView:self];
		// Offset moves the whole page
		inputs.topOffset = [manager floatValueForKey:@"hs_offset_top" forListView:self];
		inputs.leftOffset = [manager floatValueForKey:@"hs_offset_left" forListView:self];
		// Insets
		inputs.topInset = [manager floatValueForKey:@"hs_inset_top" forListView:self];
		inputs.bottomInset = [manager floatValueForKey:@"hs_inset_bottom" forListView:self];
		inputs.leftInset = [manager floatValueForKey:@"hs_inset_left" forListView:self];
		inputs.rightInset = [manager floatValueForKey:@"hs_inset_right" forListView:self];
		// Spacing is actually just inset adjustments that give the use the illusion of change
		inputs.spaceX = [manager floatValueForKey:@"hs_spacing_x" forListView:self];
		inputs.spaceY = [manager floatValueForKey:@"hs_spacing_y" forListView:self];
		inputs.textSize = [manager floatValueForKey:@"label_textSize" forListView:self];
		inputs.origPortrait = orig.layoutConfiguration.portraitLayoutInsets;
		inputs.origLandscape = orig.layoutConfiguration.landscapeLayoutInsets;

		if(ARIRootLayoutInputsUnchanged(self, state, inputs)) return;
		state.inputs = inputs;

		// Add spacing for page label
		CGFloat topInset = inputs.topInset;
		if(inputs.showPageLabel) topInset += ARIPageLabelReservedSpaceForTextSize(inputs.textSize);

		// Add tap gesture if we didn't already. Do this here to enable/disable dynamically
		if(!self._atriaTap && !inputs.disableTapGesture) {
			self._atriaTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_atriaBeginEditing)];
			[self._atriaTap setNumberOfTapsRequired:3];
			[self addGestureRecognizer:self._atriaTap];
		} else if(self._atriaTap && inputs.disableTapGesture) {
			[self removeGestureRecognizer:self._atriaTap];
			self._atriaTap = nil;
		}

		// Per-page layout requires copying this object
		SBIconListGridLayoutConfiguration *config = [orig.layoutConfiguration copy];

		// Set number of columns/rows, inverting for landscape
		[config setNumberOfPortraitColumns:inputs.cols];
		[config setNumberOfPortraitRows:inputs.rows];
		[config setNumberOfLandscapeColumns:inputs.rows];
		[config setNumberOfLandscapeRows:inputs.cols];

		// Set layout insets
		UIEdgeInsets origPortrait = config.portraitLayoutInsets;
		UIEdgeInsets portraitInsets = UIEdgeInsetsMake(
			origPortrait.top + topInset + inputs.topOffset,
			origPortrait.left + inputs.leftInset + inputs.leftOffset,
			origPortrait.bottom + inputs.bottomInset - inputs.topOffset,
			origPortrait.right + inputs.rightInset - inputs.leftOffset
		);
		// Make final insets with adjustments for icon spacing
		[config setPortraitLayoutInsets:UIEdgeInsetsMake(
			portraitInsets.top - inputs.spaceY / 2,
			portraitInsets.left - inputs.spaceX / 2,
			portraitInsets.bottom - inputs.spaceY / 2,
			portraitInsets.right - inputs.spaceX / 2
		)];

		// Landscape insets
		UIEdgeInsets origLandscape = config.landscapeLayoutInsets;
		UIEdgeInsets landscapeInsets = UIEdgeInsetsMake(
			origLandscape.top + topInset + inputs.topOffset,
			origLandscape.left + inputs.leftInset + inputs.leftOffset,
			origLandscape.bottom + inputs.bottomInset - inputs.topOffset,
			origLandscape.right + inputs.rightInset - inputs.leftOffset
		);
		[config setLandscapeLayoutInsets:UIEdgeInsetsMake(
			landscapeInsets.top - inputs.spaceY / 2,
			landscapeInsets.left - inputs.spaceX / 2,
			landscapeInsets.bottom - inputs.spaceY / 2,
			landscapeInsets.right - inputs.spaceX / 2
		)];

		// Update background
		if(!inputs.showBackground) {
			// Remove background if not needed
			if(self._atriaBackground) {
				[self._atriaBackground removeFromSuperview];
				self._atriaBackground = nil;
			}
		} else {
			// Create background
			if(!self._atriaBackground) self._atriaBackground = [[ARIBackgroundView alloc] init];
			// Insert subview at index 0
			if(!self._atriaBackground.superview) [self insertSubview:self._atriaBackground atIndex:0];
			else [self sendSubviewToBack:self._atriaBackground];

			self._atriaBackground.portraitLayoutGuide = portraitInsets;
			self._atriaBackground.landscapeLayoutGuide = landscapeInsets;
			[self._atriaBackground updateView];
		}

		// Update page label
		if(!inputs.showPageLabel) {
			// Remove page label if not needed
			if(self._atriaPageLabel) {
				[self._atriaPageLabel removeFromSuperview];
				self._atriaPageLabel = nil;
			}
		} else {
			// A reorder can move this list view in or out of first place
			Class labelClass = isFirstIconList ? [ARIWelcomeLabelView class] : [ARIPageLabelView class];
			if(self._atriaPageLabel && ![self._atriaPageLabel isMemberOfClass:labelClass]) {
				[self._atriaPageLabel removeFromSuperview];
				self._atriaPageLabel = nil;
			}
			if(!self._atriaPageLabel) self._atriaPageLabel = [[labelClass alloc] init];
			// Add to superview and add inital anchors
			// The dynamic label will constrain itself
			if(!self._atriaPageLabel.superview) [self addSubview:self._atriaPageLabel];

			self._atriaPageLabel.portraitOrigin = CGPointMake(portraitInsets.left, origPortrait.top);
			self._atriaPageLabel.landscapeOrigin = CGPointMake(landscapeInsets.left, origLandscape.top);;
			[self._atriaPageLabel updateView];
		}

		// Create a new flow layout with our modified (and copied) configuration
		// layoutConfiguration is readonly on SBIconListFlowExtendedLayout
		if([manager firmwareVersion] >= 14) {
			state.cachedLayout = [[ARIFlowExtendedLayoutClass() alloc] initWithLayoutConfiguration:config];
		} else {
			// SBIconListFlowExtendedLayout does not exist on 13
			state.cachedLayout = [[ARIFlowLayoutClass() alloc] initWithLayoutConfiguration:config];
		}
	} else if(IconListIsDock(self)) {
		SBIconListGridLayoutConfiguration *config = orig.layoutConfiguration;

		NSUInteger cols = [manager gridValueForKey:@"dock_columns" forListView:nil];
		NSUInteger rows = [manager gridValueForKey:@"dock_rows" forListView:nil];

		// Disable dock
		if([manager boolValueForKey:@"disableDock"]) cols = rows = 0;

		[config setNumberOfPortraitColumns:cols];
		[config setNumberOfPortraitRows:rows];
		// Flip for landscape
		[config setNumberOfLandscapeColumns:rows];
		[config setNumberOfLandscapeRows:cols];

		if([manager firmwareVersion] >= 14) {
			self.additionalLayoutInsets = UIEdgeInsetsMake(
				[manager floatValueForKey:@"dock_inset_top"],
				[manager floatValueForKey:@"dock_inset_left"],
				[manager floatValueForKey:@"dock_inset_bottom"],
				[manager floatValueForKey:@"dock_inset_right"]
			);
		} else {
			CGFloat spaceX = [manager floatValueForKey:@"dock_spacing_x"];
			CGFloat spaceY = [manager floatValueForKey:@"dock_spacing_y"];

			self.layoutInsets = UIEdgeInsetsMake(
				[manager floatValueForKey:@"dock_inset_top"] - spaceY / 2,
				[manager floatValueForKey:@"dock_inset_left"] - spaceX / 2,
				[manager floatValueForKey:@"dock_inset_bottom"] - spaceY / 2,
				[manager floatValueForKey:@"dock_inset_right"] - spaceX / 2
			);
		}

		// We don't need to copy our grid config for dock, so set it
		// to the original object now that we've modified the layout.
		state.cachedLayout = orig;
	}
}

- (CGSize)iconSpacing {
	CGSize spacing = %orig;
	// This doesn't work on iOS 13
	ARITweakManager *manager = [ARITweakManager sharedInstance];
	if([manager firmwareVersion] >= 14 && IconListIsDock(self)) {
		CGFloat spaceX = [manager floatValueForKey:@"dock_spacing_x"];
		CGFloat spaceY = [manager floatValueForKey:@"dock_spacing_y"];
		// I divide by 2 to keep it consistent with behavior of root
		// Root icon spacing is managed by adjusting insets, since that is what works
		return CGSizeMake(spacing.width + spaceX / 2, spacing.height + spaceY / 2);
	}
	return spacing;
}

- (BOOL)automaticallyAdjustsLayoutMetricsToFit {
	// automaticallyAdjustsLayoutMetricsToFit makes the icons auto scale
	// and automatically lay themselves out. We don't want this.

	if(IconListIsRoot(self) || IconListIsDock(self)) return NO;
	return %orig;
}

%end

%hook SBIconController

- (void)viewWillAppear:(BOOL)animated {
	%orig;
	didLaunchSB = YES;
}

%end

// Layout provider hook
%hook SBHDefaultIconListLayoutProvider

- (SBIconListFlowExtendedLayout *)layoutForIconLocation:(NSString *)location {
	SBIconListFlowExtendedLayout *orig = %orig;
	// We override the original class for root, unless we are the subclass
	ARITweakManager *manager = [ARITweakManager sharedInstance];
	if(IsLocationRoot(location) && ![self isMemberOfClass:ARIAppLibraryProviderClass()]) {
		NSUInteger cols = [manager gridValueForKey:@"hs_columns" forListView:nil];
		NSUInteger rows = [manager gridValueForKey:@"hs_rows" forListView:nil];

		// Once launched, the widest grid stops icons vanishing before they scroll offscreen
		if (didLaunchSB) cols = rows = ARIMaxGridCount;

		[orig.layoutConfiguration setNumberOfPortraitColumns:cols];
		[orig.layoutConfiguration setNumberOfPortraitRows:rows];
		[orig.layoutConfiguration setNumberOfLandscapeColumns:rows];
		[orig.layoutConfiguration setNumberOfLandscapeRows:cols];
	} else if(IsLocationDock(location)) {
		// Fix dock layout. This is needed, do not remove!
		NSUInteger cols = [manager gridValueForKey:@"dock_columns" forListView:nil];
		NSUInteger rows = [manager gridValueForKey:@"dock_rows" forListView:nil];
		[orig.layoutConfiguration setNumberOfPortraitColumns:cols];
		[orig.layoutConfiguration setNumberOfPortraitRows:rows];
		[orig.layoutConfiguration setNumberOfLandscapeColumns:rows];
		[orig.layoutConfiguration setNumberOfLandscapeRows:cols];
	} else if(IsLocationFloatingDockSuggestions(location)) {
		NSUInteger recents = [manager gridValueForKey:@"maxFloatingDockRecents" forListView:nil];
		[orig.layoutConfiguration setNumberOfPortraitColumns:recents];
		[orig.layoutConfiguration setNumberOfPortraitRows:1];
		[orig.layoutConfiguration setNumberOfLandscapeColumns:1];
		[orig.layoutConfiguration setNumberOfLandscapeRows:recents];
	}
	return orig;
}

%end

static BOOL layoutHooksInstalled = NO;

static void applyPreferencesChanged() {
	ARITweakManager *manager = [ARITweakManager sharedInstance];
	[manager reloadPreferenceState];
	if(layoutHooksInstalled)
		[manager updateLayoutForRoot:YES forDock:YES animated:YES];
	else
		[manager refreshPreferenceDependentViews];
	[manager applyPageDotVisibility];
	ARICategoryPreferencesChanged();
}

static void preferencesChanged() {
	static BOOL queued = NO;
	if(queued) return;
	queued = YES;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
		queued = NO;
		applyPreferencesChanged();
	});
}

%ctor {
	ARITweakManager *manager = [ARITweakManager sharedInstance];
	if(![manager isEnabled]) return;

	if([manager boolValueForKey:@"layoutEnabled"]) {
		ARILog(@"Loading hooks from %s", __FILE__);
		%init();
		layoutHooksInstalled = YES;
	}

	CFNotificationCenterAddObserver(
		CFNotificationCenterGetDarwinNotifyCenter(),
		NULL,
		(CFNotificationCallback)preferencesChanged,
		(CFStringRef)@"me.lau.Atria/ReloadPrefs",
		NULL,
		CFNotificationSuspensionBehaviorDeliverImmediately
	);
}
