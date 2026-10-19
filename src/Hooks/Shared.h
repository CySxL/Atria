//
// Created by ren7995 on 2021-04-25 12:49:18
// Copyright (c) 2021 ren7995. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define ARI_CACHED_CLASS(fn, name)                        \
	static Class fn(void) {                               \
		static Class cls;                                 \
		static dispatch_once_t token;                     \
		dispatch_once(&token, ^{                          \
			cls = objc_getClass(name);                    \
		});                                               \
		return cls;                                       \
	}

#ifdef DEBUG
#define ARILog(fmt, ...) NSLog(@"[Atria]: " fmt, ##__VA_ARGS__)
#else
#define ARILog(fmt, ...)
#endif

// AppLibrary = SBIconLocationAppLibrary
// Root = SBIconLocationRoot OR SBIconLocationRootWithWidgets
// Dock = SBIconLocationDock OR SBIconLocationFloatingDock
// AppLibraryPod = SBIconLocationAppLibraryCategoryPod OR SBIconLocationAppLibraryCategoryPodExpanded
// TodayView = SBIconLocationTodayView
// Folder = SBIconLocationFolder

#define IsLocationRoot(x) [x hasPrefix:@"SBIconLocationRoot"]
#define IsLocationFloatingDock(x) [x isEqualToString:@"SBIconLocationFloatingDock"]
#define IsLocationDock(x) ([x isEqualToString:@"SBIconLocationDock"] || IsLocationFloatingDock(x))
#define IsLocationAppLibrary(x) [x isEqualToString:@"SBIconLocationAppLibrary"]
#define IsLocationAppLibraryPod(x) [x hasPrefix:@"SBIconLocationAppLibraryCategoryPod"]
#define IsLocationFolder(x) [x isEqualToString:@"SBIconLocationFolder"]

#define IconListIsRoot(x) IsLocationRoot(x.iconLocation)
#define IconListIsDock(x) IsLocationDock(x.iconLocation)
#define IconListIsFloatingDock(x) IsLocationFloatingDock(x.iconLocation)
#define IconListIsAppLibrary(x) IsLocationAppLibrary(x.iconLocation)
#define IconListIsAppLibraryPod(x) IsLocationAppLibraryPod(x.iconLocation)
#define IconListIsFolder(x) IsLocationFolder(x.iconLocation)

#define IsLocationFloatingDockSuggestions(x) [x isEqualToString:@"SBIconLocationFloatingDockSuggestions"]

#define IsLocationAnyDock(x) (IsLocationDock(x) || [x hasPrefix:@"SBIconLocationFloating"])

#define IconIsInRoot(x) IsLocationRoot(x.location)
#define IconIsInDock(x) IsLocationDock(x.location)
#define IconIsInAnyDock(x) IsLocationAnyDock(x.location)
#define IconIsInFloatingDock(x) IsLocationFloatingDock(x.location)
#define IconIsInAppLibrary(x) IsLocationAppLibrary(x.location)
#define IconIsInAppLibraryPod(x) IsLocationAppLibraryPod(x.location)
#define IconIsInFolder(x) IsLocationFolder(x.location)
