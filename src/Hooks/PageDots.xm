//
// Created by ren7995 on 2021-07-06 14:59:57
// Copyright (c) 2021 ren7995. All rights reserved.
//

#import "Shared.h"
#import "../Manager/ARITweakManager.h"
#import "../Manager/ARIEditManager.h"

// Long enough to read as a move rather than a jump, short enough to have
// finished before a swipe to the next page can start
static const NSTimeInterval kARIDotSettleDuration = 0.25;

@interface SBRootFolderView (ARIPageDotMetrics)
@property (nonatomic, assign) SBRootFolderViewMetrics _atriaCachedMetrics;
@property (nonatomic, assign) BOOL _atriaHasCachedMetrics;
@property (nonatomic, assign) CGPoint _atriaLastDotOffset;
@end

// Instead of hooking the page dots directly, we hijack the layout method
// on the root folder view for optimal performance. Works on iOS 13-15
%hook SBRootFolderView
%property (nonatomic, assign) SBRootFolderViewMetrics _atriaCachedMetrics;
%property (nonatomic, assign) BOOL _atriaHasCachedMetrics;
%property (nonatomic, assign) CGPoint _atriaLastDotOffset;

- (void)layoutPageControlWithMetrics:(const struct SBRootFolderViewMetrics *)metrics {
    // The editor calls this with NULL to reapply an offset. Per instance, since
    // a second root folder view would otherwise be laid out to the first one's
    // geometry, and a zeroed struct is not something to hand back to SpringBoard.
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
	// One control serves every page, so it follows whichever page is showing.
	// This only runs when the control is laid out, so a per-page offset arrives
	// as the page settles rather than tracking the swipe.
	SBIconListView *current = [manager currentListView];
	CGPoint offset = CGPointMake([manager floatValueForKey:@"pagedot_offsetX" forListView:current],
	                             [manager floatValueForKey:@"pagedot_offsetY" forListView:current]);
	CGPoint last = self._atriaLastDotOffset;
	if(CGPointEqualToPoint(offset, CGPointZero) && CGPointEqualToPoint(last, CGPointZero)) return;

	UIView *pageControl = [manager firmwareVersion] >= 16 ? self.scrollAccessoryView : self.pageControl;
    CGRect newFrame = pageControl.frame;
	newFrame.origin.x += offset.x;
    newFrame.origin.y += offset.y;

	// %orig has just put the control back at its unshifted place, but nothing has
	// been drawn since, so animating from the presentation value slides it from
	// where the previous page left it. Dragging the slider is its own continuous
	// motion and must not have a quarter second added to each step.
	BOOL dragging = [[ARIEditManager sharedInstance].editingLocation isEqualToString:@"pagedot"];
	if(dragging || CGPointEqualToPoint(offset, last)) {
		self._atriaLastDotOffset = offset;
		pageControl.frame = newFrame;
		return;
	}

	self._atriaLastDotOffset = offset;
	[UIView animateWithDuration:kARIDotSettleDuration
	                      delay:0.0
	                    options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
	                 animations:^{ pageControl.frame = newFrame; }
	                 completion:nil];
}

%end

%ctor {
	if([[ARITweakManager sharedInstance] isEnabled]) {
		ARILog(@"Loading hooks from %s", __FILE__);
        %init();
	}
}

