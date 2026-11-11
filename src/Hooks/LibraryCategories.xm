//
// App Library categories chosen per app, and renamed categories.
//

#import "Shared.h"
#import "../Manager/ARITweakManager.h"

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
@end

// Suggestions and Recently Added are rebuilt by the system on their own schedule
static const NSUInteger ARISuggestedCategoryID = 3;
static const NSUInteger ARIRecentCategoryID = 4;

static BOOL categoriesEnabled;
static NSDictionary<NSString *, NSNumber *> *appOverrides;
static NSDictionary<NSString *, NSString *> *nameOverrides;

static __weak SBHLibraryCategoriesFolderDataSource *liveDataSource;
static SBHLibraryCategoryMap *stockMap;
static __weak SBHLibraryCategoryMap *producedMap;
static __weak SBHLibraryCategoryMap *lastSeenMap;

static BOOL ARIIsSystemCategory(NSUInteger categoryID) {
	return categoryID == ARISuggestedCategoryID || categoryID == ARIRecentCategoryID;
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

	appOverrides = [apps copy];
	nameOverrides = [names copy];
}

static BOOL ARIHasCategoryOverrides(void) {
	return categoriesEnabled && ([appOverrides count] || [nameOverrides count]);
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
	for(SBHLibraryCategoryIdentifier *identifier in identifiers)
		byID[@([identifier predictionCategoryID])] = identifier;

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

	// The pod label reads the identifier's own name, and the name is part of its equality,
	// so a renamed category takes a new identifier under every key it was used as
	[nameOverrides enumerateKeysAndObjectsUsingBlock:^(NSString *idString, NSString *name, BOOL *stop) {
		NSUInteger categoryID = (NSUInteger)[idString integerValue];
		SBHLibraryCategoryIdentifier *old = byID[@(categoryID)];
		if(!old || ARIIsSystemCategory(categoryID)) return;

		SBHLibraryCategoryIdentifier *renamed = [[objc_getClass("SBHLibraryCategoryIdentifier") alloc]
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

	[result setCategoryIdentifiers:identifiers];
	[result setSortedApplicationIdentifiersByCategoryIdentifier:apps];
	[result setLocalizedCategoryNameByCategoryIdentifier:names];
	producedMap = result;
	return result;
}

static void ARIReapplyCategories(void) {
	SBHLibraryCategoriesFolderDataSource *dataSource = liveDataSource;
	if(dataSource && stockMap) [dataSource reloadDataWithCategoryMap:stockMap];
}

%group LibraryCategories

%hook SBHLibraryCategoriesFolderDataSource

- (void)reloadDataWithCategoryMap:(SBHLibraryCategoryMap *)map {
	liveDataSource = self;
	if(map && map != producedMap) stockMap = map;
	%orig(ARIApplyCategoryOverrides(map));
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
	if(ARIHasCategoryOverrides()) dispatch_async(dispatch_get_main_queue(), ^{
		ARIReapplyCategories();
	});
}

%end

%end

static BOOL hooksInstalled;

static void ARIInstallCategoryHooks(void) {
	if(hooksInstalled || !objc_getClass("SBHLibraryCategoriesFolderDataSource")) return;
	hooksInstalled = YES;
	%init(LibraryCategories);
}

void ARICategoryPreferencesChanged(void) {
	BOOL wasActive = ARIHasCategoryOverrides();
	ARILoadCategoryPrefs();
	if(categoriesEnabled) ARIInstallCategoryHooks();
	if(hooksInstalled && (wasActive || ARIHasCategoryOverrides())) ARIReapplyCategories();
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

static NSArray<SBHLibraryCategoryIdentifier *> *ARIUserCategories(void) {
	NSMutableArray *result = [NSMutableArray new];
	for(SBHLibraryCategoryIdentifier *identifier in [stockMap categoryIdentifiers])
		if(!ARIIsSystemCategory([identifier predictionCategoryID])) [result addObject:identifier];
	return result;
}

static NSString *ARIDisplayName(SBHLibraryCategoryIdentifier *identifier) {
	NSString *custom = nameOverrides[[@([identifier predictionCategoryID]) stringValue]];
	return custom ?: [identifier localizedDisplayName];
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
	for(SBHLibraryCategoryIdentifier *identifier in ARIUserCategories()) {
		NSNumber *target = @([identifier predictionCategoryID]);
		[sheet addAction:[UIAlertAction actionWithTitle:ARIDisplayName(identifier)
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

static void ARIShowRenameAlert(SBHLibraryCategoryIdentifier *identifier, UIView *source) {
	NSString *idString = [@([identifier predictionCategoryID]) stringValue];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rename Category"
																   message:nil
															preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.text = ARIDisplayName(identifier);
		field.placeholder = [identifier localizedDisplayName];
		field.clearButtonMode = UITextFieldViewModeWhileEditing;
		field.returnKeyType = UIReturnKeyDone;
	}];
	__weak UIAlertController *weakAlert = alert;
	[alert addAction:[UIAlertAction actionWithTitle:@"Rename"
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *action) {
												NSString *text = [weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
												if(![text length]) return;
												id value = [text isEqualToString:[identifier localizedDisplayName]] ? nil : text;
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
	for(SBHLibraryCategoryIdentifier *identifier in ARIUserCategories()) {
		[sheet addAction:[UIAlertAction actionWithTitle:ARIDisplayName(identifier)
												  style:UIAlertActionStyleDefault
												handler:^(UIAlertAction *action) {
													dispatch_async(dispatch_get_main_queue(), ^{
														ARIShowRenameAlert(identifier, source);
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
}
