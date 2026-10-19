//
// Created by ren7995 on 2021-04-25 12:49:37
// Copyright (c) 2021 ren7995. All rights reserved.
//

#import "Shared.h"
#import "../Manager/ARITweakManager.h"
#import "../Manager/ARIEditManager.h"

#include <objc/runtime.h>

@interface SBIconLegibilityLabelView : UIView
@property (nonatomic, assign) CGRect _atriaNaturalFrame;
@end

@interface SBIconLabelAccessoryView : UIView
@property (nonatomic, assign) CGRect _atriaNaturalFrame;
@end

@interface UIView (ARILabelOffset)
- (void)_atriaReapplyLabelOffset;
@end

@interface SBFolderBackgroundView : UIView
- (BOOL)_atriaIsOpenFolderBackground;
@end

@interface SBSApplicationShortcutIcon : NSObject
@end

@interface SBSApplicationShortcutItem : NSObject
@property (nonatomic, retain) NSString *type;
@property (nonatomic, copy) NSString *localizedTitle;
@property (nonatomic, copy) SBSApplicationShortcutIcon *icon;
@property (nonatomic, copy) NSString *bundleIdentifierToLaunch;
- (void)setIcon:(SBSApplicationShortcutIcon *)arg1;
@end

@interface SBSApplicationShortcutCustomImageIcon : SBSApplicationShortcutIcon
@property (nonatomic, readwrite) BOOL isTemplate;
- (id)initWithImagePNGData:(id)arg1;
- (BOOL)isTemplate;
@end

@interface ARIWeakRef : NSObject
@property (nonatomic, weak) id object;
@end

@implementation ARIWeakRef
@end

@interface SBIconView (ARIListViewRef)
@property (nonatomic, strong) ARIWeakRef *_atriaListViewRef;
@property (nonatomic, assign) CGRect _atriaShadowRect;
@property (nonatomic, assign) CGFloat _atriaShadowScale;
@end

#define ARI_CACHED_CLASS(fn, name)                        \
	static Class fn(void) {                               \
		static Class cls;                                 \
		static dispatch_once_t token;                     \
		dispatch_once(&token, ^{                          \
			cls = objc_getClass(name);                    \
		});                                               \
		return cls;                                       \
	}

static void ARIReapplyOffsets(UIView *view, NSInteger depth) {
	if(!view || depth > 3) return;
	for(UIView *subview in view.subviews) {
		if([subview respondsToSelector:@selector(_atriaReapplyLabelOffset)])
			[subview _atriaReapplyLabelOffset];
		else
			ARIReapplyOffsets(subview, depth + 1);
	}
}

ARI_CACHED_CLASS(ARIWidgetIconClass, "SBWidgetIcon")
ARI_CACHED_CLASS(ARIBookmarkIconClass, "SBBookmarkIcon")
ARI_CACHED_CLASS(ARIIconListViewClass, "SBIconListView")
ARI_CACHED_CLASS(ARIIconViewClass, "SBIconView")
ARI_CACHED_CLASS(ARIIconControllerClass, "SBIconController")
ARI_CACHED_CLASS(ARILibraryPodIconClass, "SBHLibraryPodIndicatorIcon")

static CGFloat ARILabelOffsetForLabel(UIView *label) {
	ARITweakManager *manager = [ARITweakManager sharedInstance];
	if(!manager.usesLabelOffset) return 0;

	UIView *view = label.superview;
	for(NSInteger depth = 0; depth < 3 && view; depth++, view = view.superview) {
		if(![view isKindOfClass:ARIIconViewClass()]) continue;

		SBIconView *iconView = (SBIconView *)view;
		if(IconIsInAnyDock(iconView))
			return manager.usesDockLabelOffset ? [manager floatValueForKey:@"dock_label_offset"] : 0;
		if(IconIsInRoot(iconView))
			return manager.usesHsLabelOffset
				? [manager floatValueForKey:@"hs_label_offset" forListView:iconView._atriaLastIconListView]
				: 0;
		return 0;
	}
	return 0;
}

%hook SBIconView
%property (nonatomic, strong) ARIWeakRef *_atriaListViewRef;
%property (nonatomic, assign) CGRect _atriaShadowRect;
%property (nonatomic, assign) CGFloat _atriaShadowScale;

%new
- (SBIconListView *)_atriaLastIconListView {
	return self._atriaListViewRef.object;
}

%new
- (void)set_atriaLastIconListView:(SBIconListView *)listView {
	ARIWeakRef *ref = self._atriaListViewRef;
	if(!ref) {
		ref = [ARIWeakRef new];
		self._atriaListViewRef = ref;
	}
	ref.object = listView;
}

- (CGFloat)iconContentScale {
	ARITweakManager *manager = [ARITweakManager sharedInstance];
	// Fixes folder icon bug on open
	CGFloat orig = %orig;
	if([self isFolderIcon]) {
		if(IconIsInRoot(self)) {
			return [manager floatValueForKey:@"hs_iconScale" forListView:self._atriaLastIconListView];
		} else if(IconIsInDock(self)) {
			return [manager floatValueForKey:@"dock_iconScale"];
		}
	}

	return orig;
}

%new
- (BOOL)_atriaEffectiveAllowsLabelArea:(BOOL)allows {
	ARITweakManager *manager = [ARITweakManager sharedInstance];
	if([manager isShyLabelsInstalled]) return allows;

	if(IconIsInRoot(self)) {
		if([manager boolValueForKey:@"hideLabels"]) return NO;
	} else if(IconIsInAppLibrary(self) || IconIsInAppLibraryPod(self)) {
		if([manager boolValueForKey:@"hideLabelsAppLibrary"]) return NO;
	} else if(IconIsInFolder(self)) {
		if([manager boolValueForKey:@"hideLabelsFolders"]) return NO;
	} else if(IconIsInAnyDock(self)) {
		return [manager boolValueForKey:@"showDockLabels"];
	}
	return allows;
}

- (void)setAllowsLabelArea:(BOOL)allows {
	%orig([self _atriaEffectiveAllowsLabelArea:allows]);
}

- (void)_updateIconImageViewAnimated:(BOOL)arg1 {
	%orig(arg1);
	[self _atriaUpdateIconContentScale];
}

- (void)setIconContentScale:(CGFloat)scale {
	%orig(scale);
	[self _atriaUpdateIconContentScale];
}

%new
- (void)_atriaUpdateIconContentScale {
	// Reset icon content scale
	ARITweakManager *manager = [ARITweakManager sharedInstance];
	CATransform3D old = self.layer.sublayerTransform;

	BOOL inDock = IconIsInAnyDock(self);
	if(!(inDock || IconIsInRoot(self) || (IconIsInFolder(self) && [manager boolValueForKey:@"scaleInsideFolders"]))) {
		if(old.m11 != 1 || old.m22 != 1) self.layer.sublayerTransform = CATransform3DMakeScale(1, 1, 1);
		return;
	}

	CGFloat customScale = 1;
	BOOL isWidget = [self.icon isKindOfClass:ARIWidgetIconClass()];
	if(isWidget) {
		customScale = [manager floatValueForKey:@"hs_widgetIconScale" forListView:self._atriaLastIconListView];
	} else {
		if(IconIsInRoot(self) || (IconIsInFolder(self) && [manager boolValueForKey:@"scaleInsideFolders"])) {
			customScale = [manager floatValueForKey:@"hs_iconScale" forListView:self._atriaLastIconListView];
		} else if(inDock) {
			customScale = [manager floatValueForKey:@"dock_iconScale" forListView:self._atriaLastIconListView];
		}
	}

	// "Returns a transform that scales by (sx, sy, sz)."
	// By doing this, we essentially make sure that any icon animations
	// also respect our scaling (since sublayerTransform is set for our icon layer)
	if(old.m11 == customScale && old.m22 == customScale) return;

	void (^resize)() = ^void() {
		self.layer.sublayerTransform = CATransform3DMakeScale(
			customScale,
			customScale,
			1);
	};

	// Animate if in edit mode
	if([ARIEditManager sharedInstance].isEditing) {
		// Stupid Core Animation
		[CATransaction begin];
		[CATransaction setAnimationDuration:0.2f];
		// Setup animation to and from
		CATransform3D from = self.layer.sublayerTransform;
		CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"sublayerTransform"];
		animation.fromValue = [NSValue value:&from withObjCType:@encode(CATransform3D)];
		resize();
		CATransform3D to = self.layer.sublayerTransform;
		animation.toValue = [NSValue value:&to withObjCType:@encode(CATransform3D)];
		// Add completion handler (must be done before adding animation to layer)
		[CATransaction setCompletionBlock:^{ [self _atriaGenerateDropShadow:self.bounds]; }];
		// Add animation to layer and commit
		[self.layer addAnimation:animation forKey:animation.keyPath];
		[CATransaction commit];
	} else {
		// Resize and update drop shadow immediately
		resize();
		[self _atriaGenerateDropShadow:self.bounds];
	}
}

- (void)didMoveToSuperview {
	%orig;
	if(self.superview && [self.superview isKindOfClass:ARIIconListViewClass()]) {
		self._atriaLastIconListView = (SBIconListView *)self.superview;
		// Update allowsLabelArea
		[self setAllowsLabelArea:self.allowsLabelArea];
	} else if(self.superview && [self.icon isKindOfClass:ARILibraryPodIconClass()]) {
		// The floating dock's library pod is not in a list view, so nothing else asks it for a label
		BOOL allows = [self _atriaEffectiveAllowsLabelArea:self.allowsLabelArea];
		if(allows != self.allowsLabelArea) [self setAllowsLabelArea:allows];
	}
	[self _atriaSetupDropShadow:[[[ARIIconControllerClass() sharedInstance] iconManager] isEditing]];
	[self _atriaUpdateIconContentScale];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
	[self _atriaSetupDropShadow:editing];
	%orig(editing, animated);
}

%new
- (void)_atriaGenerateDropShadow:(CGRect)rect {
	if(self.layer.shadowRadius <= 0.0F) return;

	float scale = self.layer.sublayerTransform.m11;
	if(scale == self._atriaShadowScale && CGRectEqualToRect(rect, self._atriaShadowRect)) return;
	self._atriaShadowRect = rect;
	self._atriaShadowScale = scale;

	CGFloat width = rect.size.width;
	CGFloat height = rect.size.height;
	CGRect scaledRect = CGRectInset(rect,
		(width - sqrt(width * width * scale)) / 2.0F,
		(height - sqrt(height * height * scale)) / 2.0F);
	self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:scaledRect cornerRadius:[self iconImageCornerRadius]].CGPath;
}

%new
- (void)_atriaSetupDropShadow:(BOOL)isEditing {
	BOOL enabled = [[ARITweakManager sharedInstance] boolValueForKey:@"dropShadow"];
	SBIcon *icon = [self icon];
	BOOL widgetOrAppIcon = [icon application] || [icon isKindOfClass:ARIWidgetIconClass()] || [icon isKindOfClass:ARIBookmarkIconClass()];
	// Don't apply shadows in floating dock, because dynamic scaling of the app icons gets weird
	// Use containsString instead of the macro because we need to check for the suggestions location too
	if(enabled && !isEditing && widgetOrAppIcon && ![self.location containsString:@"Floating"]) {
		if(self.layer.shadowRadius > 0.0F) return;
		self.layer.masksToBounds = NO;
		self.layer.shadowOpacity = 0.4F;
		self.layer.shadowRadius = 5.0F;
		self.layer.shadowColor = [UIColor blackColor].CGColor;
		self._atriaShadowRect = CGRectNull;
		[self _atriaGenerateDropShadow:self.bounds];
	} else {
		self.layer.shadowOpacity = 0.0F;
		self.layer.shadowRadius = 0.0F;
	}
}

- (void)setBounds:(CGRect)arg1 {
	%orig(arg1);
	[self _atriaGenerateDropShadow:arg1];
}

%new
- (void)_atriaApplyDockLabelOffset {
	ARIReapplyOffsets(self, 0);
}

%new
- (SBSApplicationShortcutItem *)_atriaGenerateItemWithTitle:(NSString *)title type:(NSString *)type {
	SBSApplicationShortcutItem *item = [[objc_getClass("SBSApplicationShortcutItem") alloc] init];
	item.localizedTitle = title;
	item.type = type;

	// SFSymbols
	UIImage *image = [UIImage systemImageNamed:@"gear"];

	// Tint our image
	image = [image imageWithTintColor:[UIColor labelColor]];

	// Get data respresentation of the image
	NSData *iconData = UIImagePNGRepresentation(image);
	SBSApplicationShortcutCustomImageIcon *icon = [[objc_getClass("SBSApplicationShortcutCustomImageIcon") alloc] initWithImagePNGData:iconData];
	[item setIcon:icon];

	return item;
}

- (NSArray *)applicationShortcutItems {
	if([[ARITweakManager sharedInstance] boolValueForKey:@"hide3DTouchActions"] || [self isFolderIcon]) return %orig;

	// Add shortcut item to activate editor
	// I found this really cool gist to allow me to do this, tyvm to the author <3
	// Link: https://gist.github.com/MTACS/8e26c4f430b27d6a1d2a11f0a828f250
	NSMutableArray *items = [%orig mutableCopy];
	if(!(IconIsInRoot(self) || IconIsInDock(self))) return items;
	if(!items) items = [NSMutableArray new];

	if(IconIsInRoot(self)) {
		[items addObject:[self _atriaGenerateItemWithTitle:@"Edit Layout" type:@"me.lau.atria.edit.hs"]];
		[items addObject:[self _atriaGenerateItemWithTitle:@"Edit Page Dots" type:@"me.lau.atria.edit.pagedot"]];
		[items addObject:[self _atriaGenerateItemWithTitle:@"Edit Page Labels" type:@"me.lau.atria.edit.label"]];
		if([[ARITweakManager sharedInstance] boolValueForKey:@"showBackground"]) {
			[items addObject:[self _atriaGenerateItemWithTitle:@"Edit Background Blur" type:@"me.lau.atria.edit.blur"]];
		}
	} else if(IconIsInDock(self)) {
		[items addObject:[self _atriaGenerateItemWithTitle:@"Edit Dock" type:@"me.lau.atria.edit.dock"]];
	}

	return items;
}

+ (void)activateShortcut:(SBSApplicationShortcutItem *)item withBundleIdentifier:(NSString *)bundleID forIconView:(SBIconView *)iconView {
	NSString *prefix = @"me.lau.atria.edit.";
	if([[item type] containsString:prefix]) {
		NSString *loc = [[item type] stringByReplacingOccurrencesOfString:prefix withString:@""];
		[[ARIEditManager sharedInstance] toggleEditView:YES withTargetLocation:loc];
	} else {
		%orig;
	}
}

%end

// I don't think this needs explaining
%hook SBIconBadgeView

- (CGFloat)alpha {
	CGFloat orig = %orig;
	return orig == 1 ? ![[ARITweakManager sharedInstance] boolValueForKey:@"hideBadges"] : orig;
}

- (void)setAlpha:(CGFloat)arg1 {
	%orig(arg1 == 1 ? ![[ARITweakManager sharedInstance] boolValueForKey:@"hideBadges"] : arg1);
}

%end

%hook SBFolderIconImageView

- (void)setBackgroundView:(id)arg1 {
	if([[ARITweakManager sharedInstance] boolValueForKey:@"hideFolderIconBG"]) {
		// By setting a fresh UIView, it doesn't bug out, and it fades instead of glitching when closing the folder
		%orig([UIView new]);
		return;
	}

	%orig(arg1);
}

%end

%group FloatyFolderBackground
%hook SBFolderBackgroundView

%new
- (BOOL)_atriaIsOpenFolderBackground {
	UIView *clip = self.superview;
	if(![clip isKindOfClass:objc_getClass("SBFloatyFolderBackgroundClipView")]) return NO;
	for(UIView *sibling in clip.subviews)
		if([sibling isKindOfClass:objc_getClass("SBFloatyFolderScrollView")]) return YES;
	return NO;
}

- (void)layoutSubviews {
	%orig;
	if([[ARITweakManager sharedInstance] boolValueForKey:@"hideFolderBackground"] && [self _atriaIsOpenFolderBackground])
		self.hidden = YES;
}

- (void)setHidden:(BOOL)hidden {
	if(!hidden && [[ARITweakManager sharedInstance] boolValueForKey:@"hideFolderBackground"] && [self _atriaIsOpenFolderBackground]) {
		%orig(YES);
		return;
	}
	%orig(hidden);
}

%end
%end

%group LabelOffset
%hook SBIconLegibilityLabelView
%property (nonatomic, assign) CGRect _atriaNaturalFrame;

- (void)setFrame:(CGRect)frame {
	self._atriaNaturalFrame = frame;

	CGFloat offset = ARILabelOffsetForLabel(self);
	if(offset != 0) frame.origin.y -= offset;
	%orig(frame);
}

%new
- (void)_atriaReapplyLabelOffset {
	if(CGRectIsEmpty(self._atriaNaturalFrame)) self._atriaNaturalFrame = self.frame;
	if(!CGRectIsEmpty(self._atriaNaturalFrame)) [self setFrame:self._atriaNaturalFrame];
}

%end

%hook SBIconLabelAccessoryView
%property (nonatomic, assign) CGRect _atriaNaturalFrame;

- (void)setFrame:(CGRect)frame {
	self._atriaNaturalFrame = frame;

	CGFloat offset = ARILabelOffsetForLabel(self);
	if(offset != 0) frame.origin.y -= offset;
	%orig(frame);
}

%new
- (void)_atriaReapplyLabelOffset {
	if(!CGRectIsEmpty(self._atriaNaturalFrame)) [self setFrame:self._atriaNaturalFrame];
}

%end
%end

// The label is built from displayNameForLocation:, which is nil for the pod
%group LibraryPodLabel
%hook SBHLibraryPodIndicatorIcon

- (NSString *)displayNameForLocation:(NSString *)location {
	NSString *orig = %orig;
	if(orig || ![[ARITweakManager sharedInstance] boolValueForKey:@"showDockLabels"]) return orig;
	return @"Library";
}

%end
%end

%ctor {
	if([[ARITweakManager sharedInstance] isEnabled]) {
		ARILog(@"Loading hooks from %s", __FILE__);
		%init();

		if(objc_getClass("SBIconLabelAccessoryView")) %init(LabelOffset);
		if(ARILibraryPodIconClass()) %init(LibraryPodLabel);
		if(objc_getClass("SBFolderBackgroundView") && objc_getClass("SBFloatyFolderBackgroundClipView")
		   && objc_getClass("SBFloatyFolderScrollView"))
			%init(FloatyFolderBackground);
	}
}
