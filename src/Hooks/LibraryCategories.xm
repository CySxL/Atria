//
// App Library categories chosen per app, and renamed categories.
//

#import "Shared.h"
#import "../Manager/ARITweakManager.h"
#import "../ARIPaths.h"

@interface SBHLibraryCategoryIdentifier : NSObject <NSCopying>
- (instancetype)initWithPredictionCategoryID:(NSUInteger)categoryID categoryIndex:(NSUInteger)index localizedDisplayName:(NSString *)name localizedDisplayNameKey:(NSString *)key;
- (NSUInteger)predictionCategoryID;
- (NSUInteger)predictionCategoryIndex;
- (NSString *)localizedDisplayName;
- (NSString *)localizedDisplayNameKey;
@end

@interface SBHLibraryCategoryMap : NSObject <NSCopying>
- (NSArray *)categoryIdentifiers;
- (NSDictionary *)sortedApplicationIdentifiersByCategoryIdentifier;
- (NSDictionary *)localizedCategoryNameByCategoryIdentifier;
- (void)setCategoryIdentifiers:(NSArray *)identifiers;
- (void)setSortedApplicationIdentifiersByCategoryIdentifier:(NSDictionary *)apps;
- (void)setLocalizedCategoryNameByCategoryIdentifier:(NSDictionary *)names;
@end

@interface SBHLibraryCategoriesFolderDataSource : NSObject
- (void)reloadDataWithCategoryMap:(SBHLibraryCategoryMap *)map;
- (id)categoryForIdentifier:(SBHLibraryCategoryIdentifier *)identifier;
- (NSArray *)categoryIdentifiers;
@end

// The dock's App Library icon, an observer of the data source
@interface SBHLibraryIconViewController : UIViewController
- (void)_reloadCategoryViewsForDataSourceChangeAnimated:(BOOL)animated;
@end

@interface SBHLibraryCategoryStackView : UIView
- (NSArray *)innerIcons;
- (void)_updateIconImageViewAtIndex:(NSUInteger)index animated:(BOOL)animated;
@end

struct ARIIconImageInfo {
	CGSize size;
	CGFloat scale;
	CGFloat continuousCornerRadius;
};

@interface NSObject (ARIDockTile)
- (BOOL)isAdditionalItemsIndicatorIcon;
- (id)category;
- (id)compactPodAdditionalItemsFolder;
- (NSArray *)icons;
- (UIImage *)imageForIcon:(id)icon;
- (id)layoutForIconLocation:(NSString *)location;
- (id)layoutConfiguration;
- (id)folderIconVisualConfiguration;
- (CGSize)gridCellSize;
- (CGSize)gridCellSpacing;
- (struct ARIIconImageInfo)iconImageInfo;
@end

ARI_CACHED_CLASS(ARICategoryIdentifierClass, "SBHLibraryCategoryIdentifier")
ARI_CACHED_CLASS(ARILibraryIconViewControllerClass, "SBHLibraryIconViewController")
ARI_CACHED_CLASS(ARICategoryStackViewClass, "SBHLibraryCategoryStackView")
ARI_CACHED_CLASS(ARICategoryMapClass, "SBHLibraryCategoryMap")
ARI_CACHED_CLASS(ARICategoriesDataSourceClass, "SBHLibraryCategoriesFolderDataSource")

static BOOL categoriesEnabled;
static NSDictionary<NSString *, NSNumber *> *appOverrides;
static NSDictionary<NSString *, NSString *> *nameOverrides;
static NSArray<NSString *> *categoryOrder;
static NSDictionary<NSString *, NSArray<NSString *> *> *appOrder;
static NSArray<NSDictionary *> *customCategories;
static BOOL hideSuggestions;
static BOOL hideRecent;
// 0 when the dock icon shows the first category, as stock does
static NSUInteger dockCategoryID;

static __weak SBHLibraryCategoriesFolderDataSource *liveDataSource;
static SBHLibraryCategoryMap *stockMap;
static SBHLibraryCategoryMap *effectiveMap;
static __weak SBHLibraryCategoryMap *producedMap;
static __weak SBHLibraryCategoryMap *lastSeenMap;
// nil until the first write in this SpringBoard, so a fresh process always writes once
static NSDictionary *publishedCategories;

static BOOL ARIIsSystemCategory(NSUInteger categoryID) {
	return categoryID == ARISuggestedCategoryID || categoryID == ARIRecentCategoryID;
}

static BOOL ARIIsHiddenCategory(NSUInteger categoryID) {
	return (categoryID == ARISuggestedCategoryID && hideSuggestions) || (categoryID == ARIRecentCategoryID && hideRecent);
}

static NSUInteger ARIDockCategory(void) {
	return categoriesEnabled ? dockCategoryID : 0;
}

// The dock icon shows something other than Suggestions, the only category without an
// additional items tile
static BOOL ARIDockIconCustomized(void) {
	return categoriesEnabled && (dockCategoryID || hideSuggestions);
}

static NSArray<NSString *> *ARIStringArray(id raw) {
	if(![raw isKindOfClass:[NSArray class]]) return nil;
	NSMutableArray *result = [NSMutableArray new];
	for(id value in (NSArray *)raw)
		if([value isKindOfClass:[NSString class]] && [value length]) [result addObject:value];
	return result;
}

static void ARILoadCategoryPrefs(void) {
	ARITweakManager *manager = [ARITweakManager sharedInstance];
	categoriesEnabled = [manager boolValueForKey:@"libraryCategories"];

	NSMutableDictionary *apps = [NSMutableDictionary new];
	id raw = [manager rawValueForKey:ARILibraryCategoryAppsKey];
	if([raw isKindOfClass:[NSDictionary class]]) {
		for(id key in (NSDictionary *)raw) {
			id value = ((NSDictionary *)raw)[key];
			if([key isKindOfClass:[NSString class]] && [value isKindOfClass:[NSNumber class]]) apps[key] = value;
		}
	}

	NSMutableDictionary *names = [NSMutableDictionary new];
	raw = [manager rawValueForKey:ARILibraryCategoryNamesKey];
	if([raw isKindOfClass:[NSDictionary class]]) {
		for(id key in (NSDictionary *)raw) {
			id value = ((NSDictionary *)raw)[key];
			if([key isKindOfClass:[NSString class]] && [value isKindOfClass:[NSString class]] && [value length]) names[key] = value;
		}
	}

	NSMutableDictionary *orders = [NSMutableDictionary new];
	raw = [manager rawValueForKey:ARILibraryCategoryAppOrderKey];
	if([raw isKindOfClass:[NSDictionary class]]) {
		for(id key in (NSDictionary *)raw) {
			NSArray *order = ARIStringArray(((NSDictionary *)raw)[key]);
			if([key isKindOfClass:[NSString class]] && [order count]) orders[key] = order;
		}
	}

	NSMutableArray *customs = [NSMutableArray new];
	NSMutableSet *customIDs = [NSMutableSet new];
	raw = [manager rawValueForKey:ARILibraryCustomCategoriesKey];
	if([raw isKindOfClass:[NSArray class]]) {
		for(id entry in (NSArray *)raw) {
			if(![entry isKindOfClass:[NSDictionary class]]) continue;
			id categoryID = ((NSDictionary *)entry)[@"id"];
			id name = ((NSDictionary *)entry)[@"name"];
			if(![categoryID isKindOfClass:[NSNumber class]] || ![name isKindOfClass:[NSString class]] || ![name length]) continue;
			if([categoryID unsignedIntegerValue] < ARIFirstCustomCategoryID || [customIDs containsObject:categoryID]) continue;
			[customIDs addObject:categoryID];
			[customs addObject:@{ @"id" : categoryID, @"name" : name }];
		}
	}

	appOverrides = [apps copy];
	nameOverrides = [names copy];
	categoryOrder = ARIStringArray([manager rawValueForKey:ARILibraryCategoryOrderKey]);
	appOrder = [orders copy];
	customCategories = [customs copy];

	hideSuggestions = [manager boolValueForKey:ARILibraryHideSuggestionsKey];
	hideRecent = [manager boolValueForKey:ARILibraryHideRecentKey];
	raw = [manager rawValueForKey:ARILibraryDockCategoryKey];
	NSUInteger dock = [raw isKindOfClass:[NSNumber class]] ? [raw unsignedIntegerValue] : 0;
	dockCategoryID = ARIIsSystemCategory(dock) ? 0 : dock;
}

static BOOL ARIHasCategoryOverrides(void) {
	return categoriesEnabled && (hideSuggestions || hideRecent || [appOverrides count] || [nameOverrides count] || [categoryOrder count] || [appOrder count] || [customCategories count]);
}

static NSArray *ARIOrderedList(NSArray *list, NSArray *order) {
	NSSet *present = [NSSet setWithArray:list];
	NSMutableOrderedSet *result = [NSMutableOrderedSet new];
	for(NSString *bundleID in order)
		if([present containsObject:bundleID]) [result addObject:bundleID];
	[result addObjectsFromArray:list];
	return [result array];
}

static SBHLibraryCategoryMap *ARIApplyCategoryOverrides(SBHLibraryCategoryMap *map) {
	if(!map || !ARIHasCategoryOverrides()) return map;

	SBHLibraryCategoryMap *result = [map copy];
	NSMutableArray *identifiers = [[result categoryIdentifiers] mutableCopy];
	NSMutableDictionary *apps = [[result sortedApplicationIdentifiersByCategoryIdentifier] mutableCopy];
	NSMutableDictionary *names = [[result localizedCategoryNameByCategoryIdentifier] mutableCopy];
	if(![identifiers isKindOfClass:[NSMutableArray class]] || ![apps isKindOfClass:[NSMutableDictionary class]]) return map;
	if(![names isKindOfClass:[NSMutableDictionary class]]) names = [NSMutableDictionary new];

	NSMutableDictionary<NSNumber *, SBHLibraryCategoryIdentifier *> *byID = [NSMutableDictionary new];
	NSUInteger nextIndex = 0;
	for(SBHLibraryCategoryIdentifier *identifier in identifiers) {
		byID[@([identifier predictionCategoryID])] = identifier;
		if(!ARIIsSystemCategory([identifier predictionCategoryID])) nextIndex = MAX(nextIndex, [identifier predictionCategoryIndex] + 1);
	}

	// Added before the moves below, each with an empty list, so a move into one has somewhere to land
	NSMutableSet<NSNumber *> *customIDs = [NSMutableSet new];
	for(NSDictionary *custom in customCategories) {
		if(byID[custom[@"id"]]) continue;
		SBHLibraryCategoryIdentifier *identifier = [[ARICategoryIdentifierClass() alloc]
			initWithPredictionCategoryID:[custom[@"id"] unsignedIntegerValue]
						   categoryIndex:nextIndex++
					localizedDisplayName:custom[@"name"]
				 localizedDisplayNameKey:nil];
		if(!identifier) continue;
		[identifiers addObject:identifier];
		apps[identifier] = @[];
		names[identifier] = custom[@"name"];
		byID[custom[@"id"]] = identifier;
		[customIDs addObject:custom[@"id"]];
	}

	[appOverrides enumerateKeysAndObjectsUsingBlock:^(NSString *bundleID, NSNumber *target, BOOL *stop) {
		SBHLibraryCategoryIdentifier *targetKey = byID[target];
		if(!targetKey || ARIIsSystemCategory([target unsignedIntegerValue])) return;

		// An app the map does not list is not installed, so it is not added anywhere
		BOOL found = NO;
		for(SBHLibraryCategoryIdentifier *key in [apps allKeys]) {
			if(ARIIsSystemCategory([key predictionCategoryID])) continue;
			NSArray *list = apps[key];
			if(![list isKindOfClass:[NSArray class]] || ![list containsObject:bundleID]) continue;
			found = YES;
			if([key isEqual:targetKey]) continue;
			NSMutableArray *trimmed = [list mutableCopy];
			[trimmed removeObject:bundleID];
			apps[key] = trimmed;
		}
		if(!found) return;

		NSArray *list = apps[targetKey];
		if([list isKindOfClass:[NSArray class]] && ![list containsObject:bundleID])
			apps[targetKey] = [list arrayByAddingObject:bundleID];
	}];

	// Only reorders what the category holds, so an app no longer installed is skipped
	[appOrder enumerateKeysAndObjectsUsingBlock:^(NSString *idString, NSArray *order, BOOL *stop) {
		NSUInteger categoryID = (NSUInteger)[idString integerValue];
		SBHLibraryCategoryIdentifier *key = byID[@(categoryID)];
		NSArray *list = key ? apps[key] : nil;
		if(ARIIsSystemCategory(categoryID) || ![list isKindOfClass:[NSArray class]]) return;
		apps[key] = ARIOrderedList(list, order);
	}];

	// The pod label reads the identifier's own name, and the name is part of its equality,
	// so a renamed category takes a new identifier under every key it was used as
	[nameOverrides enumerateKeysAndObjectsUsingBlock:^(NSString *idString, NSString *name, BOOL *stop) {
		NSUInteger categoryID = (NSUInteger)[idString integerValue];
		SBHLibraryCategoryIdentifier *old = byID[@(categoryID)];
		if(!old || ARIIsSystemCategory(categoryID)) return;

		SBHLibraryCategoryIdentifier *renamed = [[ARICategoryIdentifierClass() alloc]
			initWithPredictionCategoryID:categoryID
						   categoryIndex:[old predictionCategoryIndex]
					localizedDisplayName:name
				 localizedDisplayNameKey:[old localizedDisplayNameKey]];
		if(!renamed) return;

		NSUInteger index = [identifiers indexOfObjectIdenticalTo:old];
		if(index != NSNotFound) [identifiers replaceObjectAtIndex:index withObject:renamed];
		id list = apps[old];
		[apps removeObjectForKey:old];
		if(list) apps[renamed] = list;
		[names removeObjectForKey:old];
		names[renamed] = name;
	}];

	// Pods follow this array, not predictionCategoryIndex. Suggestions and Recently Added
	// stay first, listed categories follow in the stored order, the rest keep theirs.
	NSMutableArray *system = [NSMutableArray new];
	NSMutableArray *ranked = [NSMutableArray new];
	NSMutableArray *rest = [NSMutableArray new];
	NSMutableDictionary<NSNumber *, NSNumber *> *rank = [NSMutableDictionary new];
	for(NSString *idString in categoryOrder) {
		NSNumber *categoryID = @((NSUInteger)[idString integerValue]);
		if(!rank[categoryID]) rank[categoryID] = @([rank count]);
	}
	for(SBHLibraryCategoryIdentifier *identifier in identifiers) {
		NSUInteger categoryID = [identifier predictionCategoryID];
		// A custom category nothing was moved into gets no pod
		if([customIDs containsObject:@(categoryID)] && ![apps[identifier] count]) {
			[apps removeObjectForKey:identifier];
			[names removeObjectForKey:identifier];
			continue;
		}
		if(ARIIsHiddenCategory(categoryID)) {
			[apps removeObjectForKey:identifier];
			[names removeObjectForKey:identifier];
			continue;
		}
		if(ARIIsSystemCategory(categoryID)) [system addObject:identifier];
		else if(rank[@(categoryID)]) [ranked addObject:identifier];
		else [rest addObject:identifier];
	}
	[ranked sortUsingComparator:^NSComparisonResult(SBHLibraryCategoryIdentifier *a, SBHLibraryCategoryIdentifier *b) {
		return [rank[@([a predictionCategoryID])] compare:rank[@([b predictionCategoryID])]];
	}];
	[system addObjectsFromArray:ranked];
	[system addObjectsFromArray:rest];

	[result setCategoryIdentifiers:system];
	[result setSortedApplicationIdentifiersByCategoryIdentifier:apps];
	[result setLocalizedCategoryNameByCategoryIdentifier:names];
	producedMap = result;
	return result;
}

static NSArray<NSDictionary *> *ARIDescribeCategoryMap(SBHLibraryCategoryMap *map) {
	NSMutableArray *result = [NSMutableArray new];
	NSDictionary *apps = [map sortedApplicationIdentifiersByCategoryIdentifier];
	for(SBHLibraryCategoryIdentifier *identifier in [map categoryIdentifiers]) {
		if(ARIIsSystemCategory([identifier predictionCategoryID])) continue;
		NSArray *list = ARIStringArray(apps[identifier]) ?: @[];
		NSString *name = [identifier localizedDisplayName];
		[result addObject:@{
			@"id" : @([identifier predictionCategoryID]),
			@"name" : [name isKindOfClass:[NSString class]] ? name : @"",
			@"apps" : list,
		}];
	}
	return result;
}

// The settings page reads the stock map to know where an app goes back to, and the
// effective one to show what is on screen. Only while the switch is on.
static void ARIPublishCategories(SBHLibraryCategoryMap *stock, SBHLibraryCategoryMap *effective) {
	if(!categoriesEnabled || !stock || !effective) return;
	NSDictionary *categories = @{
		@"stock" : ARIDescribeCategoryMap(stock),
		@"effective" : ARIDescribeCategoryMap(effective),
	};
	if([categories isEqual:publishedCategories]) return;
	if([categories writeToURL:[NSURL fileURLWithPath:ARILibraryCategoriesPath] error:nil]) publishedCategories = categories;
}

static void ARIRedrawDockIcons(void);

static void ARIReapplyCategories(void) {
	SBHLibraryCategoriesFolderDataSource *dataSource = liveDataSource;
	if(dataSource && stockMap) [dataSource reloadDataWithCategoryMap:stockMap];
}

%group LibraryCategories

%hook SBHLibraryCategoriesFolderDataSource

- (void)reloadDataWithCategoryMap:(SBHLibraryCategoryMap *)map {
	liveDataSource = self;
	if(map && map != producedMap) stockMap = map;
	SBHLibraryCategoryMap *effective = ARIApplyCategoryOverrides(map);
	effectiveMap = effective;
	%orig(effective);
	ARIPublishCategories(stockMap, effective);
	// Whether Apple redraws the dock icon for a change outside its first category is not known, so it is asked
	if(ARIDockIconCustomized()) ARIRedrawDockIcons();
}

// Runs about once a second while idle. A map arriving here that did not come through
// reloadDataWithCategoryMap: (the one loaded from disk at launch) gets the overrides once.
- (void)reloadDataSourceUsingIcons:(id)icons categoryMap:(SBHLibraryCategoryMap *)map {
	%orig;
	if(!map || map == lastSeenMap) return;
	lastSeenMap = map;
	liveDataSource = self;
	if(map == producedMap) return;
	stockMap = map;
	if(ARIHasCategoryOverrides()) {
		dispatch_async(dispatch_get_main_queue(), ^{
			ARIReapplyCategories();
		});
	} else {
		effectiveMap = map;
		ARIPublishCategories(map, map);
	}
}

%end

%end

// The dock icon draws the first category it is handed during its reload. Only that lookup is
// redirected, so the App Library's own pods never change.
static NSUInteger dockReloadDepth;

static id ARIObjectIvar(id object, const char *name) {
	Ivar ivar = object ? class_getInstanceVariable(object_getClass(object), name) : NULL;
	const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
	if(!type || type[0] != '@') return nil;
	return object_getIvar(object, ivar);
}

// The additional items tile's small icons and the gap between them, as fractions of the tile,
// from the layout Apple draws that tile with. 0 until read.
static CGFloat tileCellFraction;
static CGFloat tileGapFraction;

static void ARIReadTileFigures(SBHLibraryIconViewController *controller) {
	id provider = ARIObjectIvar(controller, "_listLayoutProvider");
	if(![provider respondsToSelector:@selector(layoutForIconLocation:)]) return;
	id layout = [provider layoutForIconLocation:@"SBIconLocationAppLibraryCategoryPodAdditionalItems"];
	if(![layout respondsToSelector:@selector(layoutConfiguration)] || ![layout respondsToSelector:@selector(iconImageInfo)]) return;
	id configuration = [layout layoutConfiguration];
	if(![configuration respondsToSelector:@selector(folderIconVisualConfiguration)]) return;
	id visual = [configuration folderIconVisualConfiguration];
	if(![visual respondsToSelector:@selector(gridCellSize)] || ![visual respondsToSelector:@selector(gridCellSpacing)]) return;
	CGFloat tile = [layout iconImageInfo].size.width;
	CGFloat cell = [visual gridCellSize].width;
	CGFloat gap = [visual gridCellSpacing].width;
	if(tile <= 0 || cell <= 0 || gap < 0 || 2 * cell + gap > tile) return;
	tileCellFraction = cell / tile;
	tileGapFraction = gap / tile;
}

%group LibraryDockCategory

%hook SBHLibraryIconViewController

- (void)_reloadCategoryViewsForDataSourceChangeAnimated:(BOOL)animated {
	if(ARIDockIconCustomized()) ARIReadTileFigures(self);
	dockReloadDepth++;
	%orig;
	dockReloadDepth--;
}

%end

%hook SBHLibraryCategoriesFolderDataSource

- (id)categoryForIdentifier:(SBHLibraryCategoryIdentifier *)identifier {
	NSUInteger chosen = ARIDockCategory();
	if(!dockReloadDepth || !chosen || ![identifier respondsToSelector:@selector(predictionCategoryID)]) return %orig;
	// The data source's own identifiers, since a renamed one is not equal to the copy in any other map
	NSArray *identifiers = [self categoryIdentifiers];
	SBHLibraryCategoryIdentifier *first = [identifiers firstObject];
	if(![first respondsToSelector:@selector(predictionCategoryID)] || [first predictionCategoryID] != [identifier predictionCategoryID]) return %orig;
	// A chosen category that was deleted, hidden or left empty is not in the map, and stock is kept
	for(SBHLibraryCategoryIdentifier *candidate in identifiers)
		if([candidate predictionCategoryID] == chosen) return %orig(candidate);
	return %orig;
}

%end

%end

// The dock icon's stack view draws each inner icon as one image, and the additional items
// tile has none, so its slot would stay empty. It gets the tile's first four apps instead,
// laid out as the App Library draws them.
%group LibraryDockTile

%hook SBHLibraryCategoryStackView

- (void)_updateIconImageViewAtIndex:(NSUInteger)index animated:(BOOL)animated {
	%orig;
	if(!ARIDockIconCustomized()) return;
	// Unknown until a reload has read them, so the first draw asks the controller itself
	if(tileCellFraction <= 0) {
		UIResponder *responder = self;
		while(responder && ![responder isKindOfClass:ARILibraryIconViewControllerClass()]) responder = [responder nextResponder];
		if(responder) ARIReadTileFigures((SBHLibraryIconViewController *)responder);
		if(tileCellFraction <= 0) return;
	}

	NSArray *innerIcons = [self innerIcons];
	if(![innerIcons isKindOfClass:[NSArray class]] || index >= [innerIcons count]) return;
	id tile = innerIcons[index];
	if(![tile respondsToSelector:@selector(isAdditionalItemsIndicatorIcon)] || ![tile isAdditionalItemsIndicatorIcon] || ![tile respondsToSelector:@selector(category)]) return;
	id category = [tile category];
	id folder = [category respondsToSelector:@selector(compactPodAdditionalItemsFolder)] ? [category compactPodAdditionalItemsFolder] : nil;
	NSArray *apps = [folder respondsToSelector:@selector(icons)] ? [folder icons] : nil;
	NSArray *imageViews = ARIObjectIvar(self, "_iconImageViews");
	id cache = ARIObjectIvar(self, "_iconImageCache");
	if(![apps isKindOfClass:[NSArray class]] || ![imageViews isKindOfClass:[NSArray class]] || index >= [imageViews count] || ![cache respondsToSelector:@selector(imageForIcon:)]) return;
	UIImageView *slot = imageViews[index];
	if(![slot isKindOfClass:[UIImageView class]]) return;

	CGFloat side = MIN(slot.bounds.size.width, slot.bounds.size.height);
	if(side <= 0) return;
	CGFloat cell = side * tileCellFraction;
	CGFloat gap = side * tileGapFraction;
	CGFloat inset = (side - 2 * cell - gap) / 2;

	NSMutableArray<UIImage *> *images = [NSMutableArray new];
	for(id app in apps) {
		if([images count] == 4) break;
		UIImage *image = [cache imageForIcon:app];
		if([image isKindOfClass:[UIImage class]]) [images addObject:image];
	}
	if(![images count]) return;

	UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side) format:[UIGraphicsImageRendererFormat preferredFormat]];
	slot.image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
		[images enumerateObjectsUsingBlock:^(UIImage *image, NSUInteger i, BOOL *stop) {
			[image drawInRect:CGRectMake(inset + (i % 2) * (cell + gap), inset + (i / 2) * (cell + gap), cell, cell)];
		}];
	}];
}

%end

%end

static BOOL hooksInstalled;
// The firmware lacks something the overrides send, decided once per SpringBoard
static BOOL hooksRefused;
static BOOL dockHooksInstalled;

static BOOL ARIRespondsToAll(Class cls, NSArray<NSString *> *selectors) {
	if(!cls) return NO;
	for(NSString *name in selectors)
		if(![cls instancesRespondToSelector:NSSelectorFromString(name)]) return NO;
	return YES;
}

// The IDs are read as NSUInteger, so a getter returning an object or anything narrower is refused
static BOOL ARIReturnsInteger(Class cls, SEL selector) {
	Method method = class_getInstanceMethod(cls, selector);
	char type[8] = {0};
	if(method) method_getReturnType(method, type, sizeof(type));
	return strchr("QqLl", type[0]) && type[0];
}

static BOOL ARICategoryClassesSupported(void) {
	Class identifier = ARICategoryIdentifierClass();
	return ARIRespondsToAll(identifier, @[ @"initWithPredictionCategoryID:categoryIndex:localizedDisplayName:localizedDisplayNameKey:",
										   @"predictionCategoryID", @"predictionCategoryIndex", @"localizedDisplayName", @"localizedDisplayNameKey" ])
		&& ARIReturnsInteger(identifier, @selector(predictionCategoryID))
		&& ARIReturnsInteger(identifier, @selector(predictionCategoryIndex))
		&& ARIRespondsToAll(ARICategoryMapClass(), @[ @"copyWithZone:", @"categoryIdentifiers", @"sortedApplicationIdentifiersByCategoryIdentifier",
													  @"localizedCategoryNameByCategoryIdentifier", @"setCategoryIdentifiers:",
													  @"setSortedApplicationIdentifiersByCategoryIdentifier:", @"setLocalizedCategoryNameByCategoryIdentifier:" ])
		&& ARIRespondsToAll(ARICategoriesDataSourceClass(), @[ @"reloadDataWithCategoryMap:", @"reloadDataSourceUsingIcons:categoryMap:" ]);
}

static void ARIInstallCategoryHooks(void) {
	if(hooksInstalled || hooksRefused) return;
	if(!ARICategoryClassesSupported()) {
		hooksRefused = YES;
		return;
	}
	hooksInstalled = YES;
	%init(LibraryCategories);
}

// Only once the dock icon shows something other than Suggestions, and only where the methods exist
static void ARIInstallDockHooks(void) {
	static BOOL refused;
	if(dockHooksInstalled || refused || !hooksInstalled || !ARIDockIconCustomized()) return;
	if(!ARIRespondsToAll(ARILibraryIconViewControllerClass(), @[ @"_reloadCategoryViewsForDataSourceChangeAnimated:" ])
	   || !ARIRespondsToAll(ARICategoriesDataSourceClass(), @[ @"categoryForIdentifier:", @"categoryIdentifiers" ])) {
		refused = YES;
		return;
	}
	dockHooksInstalled = YES;
	%init(LibraryDockCategory);

	Class stackClass = ARICategoryStackViewClass();
	if([stackClass instancesRespondToSelector:@selector(_updateIconImageViewAtIndex:animated:)] && [stackClass instancesRespondToSelector:@selector(innerIcons)])
		%init(LibraryDockTile);
}

static BOOL dockRedrawPending;

// A reload of the data source with unchanged content does not redraw the dock icon, so a
// change of the dock category alone asks each icon controller observing it directly. Calls
// in the same run loop turn share one redraw, made after the data source has finished.
static void ARIRedrawDockIcons(void) {
	if(!dockHooksInstalled || dockRedrawPending) return;
	dockRedrawPending = YES;
	dispatch_async(dispatch_get_main_queue(), ^{
		dockRedrawPending = NO;
		NSHashTable *observers = ARIObjectIvar(liveDataSource, "_observers");
		if(![observers isKindOfClass:[NSHashTable class]]) return;
		Class controllerClass = ARILibraryIconViewControllerClass();
		for(id observer in [observers allObjects])
			if([observer isKindOfClass:controllerClass]) [observer _reloadCategoryViewsForDataSourceChangeAnimated:NO];
	});
}

// What the App Library is built from. The dock category is left out: it changes only the dock icon.
static NSArray *ARICategorySnapshot(void) {
	return @[ @(categoriesEnabled), @(hideSuggestions), @(hideRecent), appOverrides ?: @{}, nameOverrides ?: @{}, categoryOrder ?: @[], appOrder ?: @{}, customCategories ?: @[] ];
}

// Called on every preference write, so the App Library is rebuilt only when a category setting changed
void ARICategoryPreferencesChanged(void) {
	BOOL wasEnabled = categoriesEnabled;
	BOOL wasActive = ARIHasCategoryOverrides();
	NSArray *before = ARICategorySnapshot();
	NSUInteger dockBefore = ARIDockCategory();
	BOOL customizedBefore = ARIDockIconCustomized();
	ARILoadCategoryPrefs();
	if(categoriesEnabled) ARIInstallCategoryHooks();
	ARIInstallDockHooks();
	BOOL changed = ![before isEqual:ARICategorySnapshot()];
	if(hooksInstalled && changed && (wasActive || ARIHasCategoryOverrides())) ARIReapplyCategories();
	else if(categoriesEnabled && !wasEnabled && stockMap) ARIPublishCategories(stockMap, stockMap);
	if(dockBefore != ARIDockCategory() || customizedBefore != ARIDockIconCustomized()) ARIRedrawDockIcons();

	// Nothing reads the file with the switch off, and a stale one must not outlive it
	if(wasEnabled && !categoriesEnabled) {
		[[NSFileManager defaultManager] removeItemAtPath:ARILibraryCategoriesPath error:nil];
		publishedCategories = nil;
	}
}

static NSString *const ARICategoryMoveType = @"me.lau.atria.category.move";
static NSString *const ARICategoryRenameType = @"me.lau.atria.category.rename";

NSArray *ARILibraryCategoryShortcutItems(SBIconView *iconView, NSArray *items) {
	if(!categoriesEnabled || !hooksInstalled || !stockMap) return items;
	NSMutableArray *result = [items mutableCopy] ?: [NSMutableArray new];
	[result addObject:[iconView _atriaGenerateItemWithTitle:@"Move to Category" type:ARICategoryMoveType]];
	[result addObject:[iconView _atriaGenerateItemWithTitle:@"Rename Category" type:ARICategoryRenameType]];
	return result;
}

BOOL ARIIsLibraryCategoryShortcut(NSString *type) {
	return [type isEqualToString:ARICategoryMoveType] || [type isEqualToString:ARICategoryRenameType];
}

// In the order the App Library shows them, then custom categories nothing was moved into yet
static NSArray<NSNumber *> *ARIUserCategories(void) {
	NSMutableOrderedSet *result = [NSMutableOrderedSet new];
	for(SBHLibraryCategoryIdentifier *identifier in [(effectiveMap ?: stockMap) categoryIdentifiers])
		if(!ARIIsSystemCategory([identifier predictionCategoryID])) [result addObject:@([identifier predictionCategoryID])];
	for(SBHLibraryCategoryIdentifier *identifier in [stockMap categoryIdentifiers])
		if(!ARIIsSystemCategory([identifier predictionCategoryID])) [result addObject:@([identifier predictionCategoryID])];
	for(NSDictionary *custom in customCategories) [result addObject:custom[@"id"]];
	return [result array];
}

// The name before any rename: Apple's for a stock category, the one it was created with for a custom one
static NSString *ARIBaseName(NSNumber *categoryID) {
	for(SBHLibraryCategoryIdentifier *identifier in [stockMap categoryIdentifiers])
		if([identifier predictionCategoryID] == [categoryID unsignedIntegerValue]) return [identifier localizedDisplayName];
	for(NSDictionary *custom in customCategories)
		if([custom[@"id"] isEqual:categoryID]) return custom[@"name"];
	return [categoryID stringValue];
}

static NSString *ARIDisplayName(NSNumber *categoryID) {
	return nameOverrides[[categoryID stringValue]] ?: ARIBaseName(categoryID);
}

static void ARIStoreOverride(NSString *key, NSDictionary *current, id dictKey, id value) {
	NSMutableDictionary *updated = [current mutableCopy] ?: [NSMutableDictionary new];
	if(value) updated[dictKey] = value;
	else [updated removeObjectForKey:dictKey];

	ARITweakManager *manager = [ARITweakManager sharedInstance];
	if([updated count]) [manager setRawValue:updated forKey:key];
	else [manager resetValueForKey:key];
	ARILoadCategoryPrefs();
	ARIReapplyCategories();
}

static UIViewController *ARIPresenterForView(UIView *view) {
	UIViewController *controller = view.window.rootViewController;
	while(controller.presentedViewController && !controller.presentedViewController.isBeingDismissed)
		controller = controller.presentedViewController;
	return controller;
}

static void ARIPresentSheet(UIAlertController *alert, UIView *source) {
	UIViewController *presenter = ARIPresenterForView(source);
	if(!presenter) return;
	alert.popoverPresentationController.sourceView = source;
	alert.popoverPresentationController.sourceRect = source.bounds;
	[presenter presentViewController:alert animated:YES completion:nil];
}

static void ARIShowMoveSheet(NSString *bundleID, UIView *source) {
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Move to Category"
																   message:nil
															preferredStyle:UIAlertControllerStyleActionSheet];
	for(NSNumber *target in ARIUserCategories()) {
		[sheet addAction:[UIAlertAction actionWithTitle:ARIDisplayName(target)
												  style:UIAlertActionStyleDefault
												handler:^(UIAlertAction *action) {
													ARIStoreOverride(ARILibraryCategoryAppsKey, appOverrides, bundleID, target);
												}]];
	}
	if(appOverrides[bundleID]) {
		[sheet addAction:[UIAlertAction actionWithTitle:@"Restore Automatic"
												  style:UIAlertActionStyleDestructive
												handler:^(UIAlertAction *action) {
													ARIStoreOverride(ARILibraryCategoryAppsKey, appOverrides, bundleID, nil);
												}]];
	}
	[sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
	ARIPresentSheet(sheet, source);
}

static void ARIShowRenameAlert(NSNumber *categoryID, UIView *source) {
	NSString *idString = [categoryID stringValue];
	NSString *baseName = ARIBaseName(categoryID);
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rename Category"
																   message:nil
															preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.text = ARIDisplayName(categoryID);
		field.placeholder = baseName;
		field.clearButtonMode = UITextFieldViewModeWhileEditing;
		field.returnKeyType = UIReturnKeyDone;
	}];
	__weak UIAlertController *weakAlert = alert;
	[alert addAction:[UIAlertAction actionWithTitle:@"Rename"
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *action) {
												NSString *text = [weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
												if(![text length]) return;
												id value = [text isEqualToString:baseName] ? nil : text;
												ARIStoreOverride(ARILibraryCategoryNamesKey, nameOverrides, idString, value);
											}]];
	if(nameOverrides[idString]) {
		[alert addAction:[UIAlertAction actionWithTitle:@"Restore Name"
												  style:UIAlertActionStyleDestructive
												handler:^(UIAlertAction *action) {
													ARIStoreOverride(ARILibraryCategoryNamesKey, nameOverrides, idString, nil);
												}]];
	}
	[alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
	ARIPresentSheet(alert, source);
}

static void ARIShowRenameSheet(UIView *source) {
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Rename Category"
																   message:nil
															preferredStyle:UIAlertControllerStyleActionSheet];
	for(NSNumber *categoryID in ARIUserCategories()) {
		[sheet addAction:[UIAlertAction actionWithTitle:ARIDisplayName(categoryID)
												  style:UIAlertActionStyleDefault
												handler:^(UIAlertAction *action) {
													dispatch_async(dispatch_get_main_queue(), ^{
														ARIShowRenameAlert(categoryID, source);
													});
												}]];
	}
	[sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
	ARIPresentSheet(sheet, source);
}

void ARIHandleLibraryCategoryShortcut(NSString *type, NSString *bundleID, UIView *iconView) {
	if(!stockMap || !iconView.window) return;
	// The menu is still dismissing when the shortcut fires
	dispatch_async(dispatch_get_main_queue(), ^{
		if([type isEqualToString:ARICategoryMoveType]) {
			if([bundleID isKindOfClass:[NSString class]] && [bundleID length]) ARIShowMoveSheet(bundleID, iconView);
		} else {
			ARIShowRenameSheet(iconView);
		}
	});
}

%ctor {
	ARITweakManager *manager = [ARITweakManager sharedInstance];
	if(![manager isEnabled]) return;

	ARILoadCategoryPrefs();
	if(categoriesEnabled) ARIInstallCategoryHooks();
	ARIInstallDockHooks();
}
