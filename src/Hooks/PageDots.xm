//
// Created by ren7995 on 2021-07-06 14:59:57
// Copyright (c) 2021 ren7995. All rights reserved.
//

#import "Shared.h"
#import "../Manager/ARITweakManager.h"

@interface SBRootFolderView (ARIPageDotMetrics)
@property (nonatomic, assign) SBRootFolderViewMetrics _atriaCachedMetrics;
@property (nonatomic, assign) BOOL _atriaHasCachedMetrics;
@end

// Instead of hooking the page dots directly, we hijack the layout method
// on the root folder view for optimal performance. Works on iOS 13-15
%hook SBRootFolderView
%property (nonatomic, assign) SBRootFolderViewMetrics _atriaCachedMetrics;
%property (nonatomic, assign) BOOL _atriaHasCachedMetrics;

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
	CGFloat offsetX = [manager floatValueForKey:@"pagedot_offsetX"];
	CGFloat offsetY = [manager floatValueForKey:@"pagedot_offsetY"];
	if(offsetX == 0 && offsetY == 0) return;

	UIView *pageControl = [manager firmwareVersion] >= 16 ? self.scrollAccessoryView : self.pageControl;
    CGRect newFrame = pageControl.frame;
	newFrame.origin.x += offsetX;
    newFrame.origin.y += offsetY;
	pageControl.frame = newFrame;
}

%end

%ctor {
	if([[ARITweakManager sharedInstance] isEnabled]) {
		ARILog(@"Loading hooks from %s", __FILE__);
        %init();
	}
}

