//
// Created by ren7995 on 2021-07-06 14:59:57
// Copyright (c) 2021 ren7995. All rights reserved.
//

#import "Shared.h"
#import "../Manager/ARITweakManager.h"
#import "../Manager/ARIEditManager.h"

static const NSTimeInterval kARIDotSettleDuration = 0.35;
static const CGFloat kARIDotSettleDamping = 0.86;

@interface SBRootFolderView (ARIPageDotMetrics)
@property (nonatomic, assign) SBRootFolderViewMetrics _atriaCachedMetrics;
@property (nonatomic, assign) BOOL _atriaHasCachedMetrics;
@property (nonatomic, assign) CGPoint _atriaLastDotOffset;
@end

// Instead of hooking the page dots directly, we hijack the layout method
// on the root folder view for optimal performance. On iOS 16 the dots sit in the scroll accessory
%hook SBRootFolderView
%property (nonatomic, assign) SBRootFolderViewMetrics _atriaCachedMetrics;
%property (nonatomic, assign) BOOL _atriaHasCachedMetrics;
%property (nonatomic, assign) CGPoint _atriaLastDotOffset;

- (void)layoutPageControlWithMetrics:(const struct SBRootFolderViewMetrics *)metrics {
    SBRootFolderViewMetrics cached;
    if(metrics) {
        self._atriaCachedMetrics = *metrics;
        self._atriaHasCachedMetrics = YES;
    } else {
        if(!self._atriaHasCachedMetrics) return;
        cached = self._atriaCachedMetrics;
        metrics = &cached;
    }

    %orig(metrics);

    ARITweakManager *manager = [ARITweakManager sharedInstance];
    [manager applyPageDotVisibility];

	SBIconListView *current = [manager currentListView];
	CGPoint offset = CGPointMake([manager floatValueForKey:@"pagedot_offsetX" forListView:current],
	                             [manager floatValueForKey:@"pagedot_offsetY" forListView:current]);
	CGPoint last = self._atriaLastDotOffset;
	if(CGPointEqualToPoint(offset, CGPointZero) && CGPointEqualToPoint(last, CGPointZero)) return;

	UIView *pageControl = [manager firmwareVersion] >= 16 ? self.scrollAccessoryView : self.pageControl;
    CGRect newFrame = pageControl.frame;
	newFrame.origin.x += offset.x;
    newFrame.origin.y += offset.y;

	BOOL dragging = [[ARIEditManager sharedInstance].editingLocation isEqualToString:@"pagedot"];
	if(dragging || CGPointEqualToPoint(offset, last)) {
		self._atriaLastDotOffset = offset;
		pageControl.frame = newFrame;
		return;
	}

	self._atriaLastDotOffset = offset;
	[UIView animateWithDuration:kARIDotSettleDuration
	                      delay:0.0
	     usingSpringWithDamping:kARIDotSettleDamping
	      initialSpringVelocity:0.0
	                    options:UIViewAnimationOptionBeginFromCurrentState
	                 animations:^{ pageControl.frame = newFrame; }
	                 completion:nil];
}

%end

%hook SBIconListPageControl

- (void)setHidden:(BOOL)hidden {
	%orig(hidden || [[ARITweakManager sharedInstance] boolValueForKey:@"hidePageDots"]);
}

- (void)setAlpha:(CGFloat)alpha {
	%orig([[ARITweakManager sharedInstance] boolValueForKey:@"hidePageDots"] ? 0 : alpha);
}

%end

%ctor {
	if([[ARITweakManager sharedInstance] isEnabled]) {
		ARILog(@"Loading hooks from %s", __FILE__);
        %init();
	}
}
