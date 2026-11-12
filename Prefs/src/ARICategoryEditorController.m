#import "ARICategoryEditorController.h"
#import "ARIListController.h"
#import "../../src/ARIPaths.h"

@interface UIImage (ARIPrivate)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

@interface LSApplicationProxy : NSObject
+ (instancetype)applicationProxyForIdentifier:(NSString *)identifier;
- (NSString *)localizedName;
@end

static NSArray<NSString *> *ARIStrings(id raw) {
    if(![raw isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray *result = [NSMutableArray new];
    for(id value in (NSArray *)raw)
        if([value isKindOfClass:[NSString class]] && [value length]) [result addObject:value];
    return result;
}

static NSMutableDictionary *ARIDictionary(id raw, Class valueClass) {
    NSMutableDictionary *result = [NSMutableDictionary new];
    if(![raw isKindOfClass:[NSDictionary class]]) return result;
    for(id key in (NSDictionary *)raw) {
        id value = ((NSDictionary *)raw)[key];
        if([key isKindOfClass:[NSString class]] && [value isKindOfClass:valueClass]) result[key] = value;
    }
    return result;
}

// Same rule as SpringBoard: an ID below 9001 is Apple's and never a custom category
static NSMutableArray<NSDictionary *> *ARICustoms(id raw) {
    NSMutableArray *result = [NSMutableArray new];
    if(![raw isKindOfClass:[NSArray class]]) return result;
    NSMutableSet *seen = [NSMutableSet new];
    for(id entry in (NSArray *)raw) {
        if(![entry isKindOfClass:[NSDictionary class]]) continue;
        id categoryID = ((NSDictionary *)entry)[@"id"];
        id name = ((NSDictionary *)entry)[@"name"];
        if(![categoryID isKindOfClass:[NSNumber class]] || ![name isKindOfClass:[NSString class]] || ![name length]) continue;
        if([categoryID unsignedIntegerValue] < ARIFirstCustomCategoryID || [seen containsObject:categoryID]) continue;
        [seen addObject:categoryID];
        [result addObject:@{ @"id" : categoryID, @"name" : name }];
    }
    return result;
}

@implementation ARICategoryEditorController {
    ARICategoryEditorMode _mode;
    BOOL _loaded;
    BOOL _dirty;
    // Each: id, name, apps (mutable), custom
    NSMutableArray<NSMutableDictionary *> *_categories;
    NSDictionary<NSString *, NSNumber *> *_stockCategoryForApp;
    NSDictionary<NSNumber *, NSString *> *_stockNames;
    NSMutableDictionary *_appOverrides;
    NSMutableDictionary *_nameOverrides;
    NSMutableDictionary *_appOrder;
    NSMutableArray<NSDictionary *> *_customs;
    // What this page changed, merged into the stored settings on save so a change made
    // meanwhile from the App Library menu is kept
    NSMutableSet<NSNumber *> *_touched;
    NSMutableSet<NSString *> *_movedApps;
    NSMutableSet<NSNumber *> *_renamed;
    NSMutableSet<NSNumber *> *_deleted;
    BOOL _reordered;
    // The category the dock's App Library icon shows, nil for the first one
    NSNumber *_dockCategory;
    BOOL _dockChanged;
    NSCache *_appNames;
    NSCache *_appIcons;
    id _backgroundObserver;
}

- (instancetype)initWithMode:(ARICategoryEditorMode)mode {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if(self) {
        _mode = mode;
        _touched = [NSMutableSet new];
        _movedApps = [NSMutableSet new];
        _renamed = [NSMutableSet new];
        _deleted = [NSMutableSet new];
        _appNames = [NSCache new];
        _appIcons = [NSCache new];
        self.title = mode == ARICategoryEditorModeApps ? @"Edit Categories" : @"Category Order";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self _load];
    self.tableView.editing = _loaded;
    self.tableView.allowsSelectionDuringEditing = YES;
    if(_mode == ARICategoryEditorModeOrder && _loaded) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                                               target:self
                                                                                               action:@selector(_addCategory)];
    }

    // Settings can be killed from the switcher without the page ever disappearing
    __weak typeof(self) weakSelf = self;
    _backgroundObserver = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification
                                                                            object:nil
                                                                             queue:[NSOperationQueue mainQueue]
                                                                        usingBlock:^(NSNotification *note) {
                                                                            [weakSelf _saveIfDirty];
                                                                        }];
}

- (void)dealloc {
    if(_backgroundObserver) [[NSNotificationCenter defaultCenter] removeObserver:_backgroundObserver];
}

// Each save rebuilds the home screen, so it waits for leaving the page or the app
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self _saveIfDirty];
}

- (void)_saveIfDirty {
    if(_dirty) [self _save];
}

- (void)_load {
    NSDictionary *file = [NSDictionary dictionaryWithContentsOfFile:ARILibraryCategoriesPath];
    NSArray *effective = [file isKindOfClass:[NSDictionary class]] ? file[@"effective"] : nil;
    NSArray *stock = [file isKindOfClass:[NSDictionary class]] ? file[@"stock"] : nil;
    if(![effective isKindOfClass:[NSArray class]] || ![stock isKindOfClass:[NSArray class]]) return;

    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];
    _appOverrides = ARIDictionary([defaults objectForKey:ARILibraryCategoryAppsKey], [NSNumber class]);
    _nameOverrides = ARIDictionary([defaults objectForKey:ARILibraryCategoryNamesKey], [NSString class]);
    _appOrder = ARIDictionary([defaults objectForKey:ARILibraryCategoryAppOrderKey], [NSArray class]);
    _customs = ARICustoms([defaults objectForKey:ARILibraryCustomCategoriesKey]);
    id dock = [defaults objectForKey:ARILibraryDockCategoryKey];
    _dockCategory = [dock isKindOfClass:[NSNumber class]] ? dock : nil;

    NSMutableDictionary *stockCategoryForApp = [NSMutableDictionary new];
    NSMutableDictionary *stockNames = [NSMutableDictionary new];
    for(NSDictionary *entry in stock) {
        if(![entry isKindOfClass:[NSDictionary class]] || ![entry[@"id"] isKindOfClass:[NSNumber class]]) continue;
        if([entry[@"name"] isKindOfClass:[NSString class]]) stockNames[entry[@"id"]] = entry[@"name"];
        for(NSString *bundleID in ARIStrings(entry[@"apps"]))
            if(!stockCategoryForApp[bundleID]) stockCategoryForApp[bundleID] = entry[@"id"];
    }
    _stockCategoryForApp = stockCategoryForApp;
    _stockNames = stockNames;

    _categories = [NSMutableArray new];
    NSMutableSet *seen = [NSMutableSet new];
    for(NSDictionary *entry in effective) {
        if(![entry isKindOfClass:[NSDictionary class]] || ![entry[@"id"] isKindOfClass:[NSNumber class]]) continue;
        if([seen containsObject:entry[@"id"]]) continue;
        [seen addObject:entry[@"id"]];
        [_categories addObject:[@{
            @"id" : entry[@"id"],
            @"apps" : [ARIStrings(entry[@"apps"]) mutableCopy],
            @"custom" : @([self _customIndexForID:entry[@"id"]] != NSNotFound),
        } mutableCopy]];
    }
    // A custom category nothing has been moved into has no pod, so it is not in the file
    for(NSDictionary *custom in _customs) {
        if([seen containsObject:custom[@"id"]]) continue;
        [seen addObject:custom[@"id"]];
        [_categories addObject:[@{ @"id" : custom[@"id"], @"apps" : [NSMutableArray new], @"custom" : @YES } mutableCopy]];
    }
    _loaded = YES;
}

- (NSUInteger)_customIndexForID:(NSNumber *)categoryID {
    for(NSUInteger i = 0; i < [_customs count]; i++)
        if([_customs[i][@"id"] isEqual:categoryID]) return i;
    return NSNotFound;
}

- (NSString *)_baseNameForID:(NSNumber *)categoryID {
    NSUInteger index = [self _customIndexForID:categoryID];
    if(index != NSNotFound) return _customs[index][@"name"];
    return _stockNames[categoryID] ?: [categoryID stringValue];
}

- (NSString *)_nameForID:(NSNumber *)categoryID {
    return _nameOverrides[[categoryID stringValue]] ?: [self _baseNameForID:categoryID];
}

// Never hands out an ID any stored setting still mentions, so a deleted category's leftovers stay orphaned
- (NSNumber *)_nextCategoryID {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];
    id stored = [defaults objectForKey:ARILibraryCategoryNextIDKey];
    NSUInteger next = MAX(ARIFirstCustomCategoryID, [stored isKindOfClass:[NSNumber class]] ? [stored unsignedIntegerValue] : 0);
    for(NSDictionary *category in _categories) next = MAX(next, [category[@"id"] unsignedIntegerValue] + 1);
    for(NSNumber *target in [_appOverrides allValues]) next = MAX(next, [target unsignedIntegerValue] + 1);
    for(NSString *key in [_nameOverrides allKeys]) next = MAX(next, (NSUInteger)[key integerValue] + 1);
    for(NSString *key in [_appOrder allKeys]) next = MAX(next, (NSUInteger)[key integerValue] + 1);
    [defaults setObject:@(next + 1) forKey:ARILibraryCategoryNextIDKey];
    return @(next);
}

- (void)_save {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];
    NSMutableDictionary *apps = ARIDictionary([defaults objectForKey:ARILibraryCategoryAppsKey], [NSNumber class]);
    NSMutableDictionary *names = ARIDictionary([defaults objectForKey:ARILibraryCategoryNamesKey], [NSString class]);
    NSMutableDictionary *orders = ARIDictionary([defaults objectForKey:ARILibraryCategoryAppOrderKey], [NSArray class]);
    NSMutableArray<NSDictionary *> *customs = ARICustoms([defaults objectForKey:ARILibraryCustomCategoriesKey]);

    if(_mode == ARICategoryEditorModeApps) {
        for(NSDictionary *category in _categories) {
            for(NSString *bundleID in category[@"apps"]) {
                if(![_movedApps containsObject:bundleID]) continue;
                if([_stockCategoryForApp[bundleID] isEqual:category[@"id"]]) [apps removeObjectForKey:bundleID];
                else apps[bundleID] = category[@"id"];
            }
            if([_touched containsObject:category[@"id"]]) {
                NSString *key = [category[@"id"] stringValue];
                if([category[@"apps"] count]) orders[key] = [category[@"apps"] copy];
                else [orders removeObjectForKey:key];
            }
        }
    } else {
        // Its apps go back to the category they came from
        for(NSNumber *categoryID in _deleted) {
            NSString *key = [categoryID stringValue];
            for(NSString *bundleID in [apps allKeys])
                if([apps[bundleID] isEqual:categoryID]) [apps removeObjectForKey:bundleID];
            [orders removeObjectForKey:key];
            [names removeObjectForKey:key];
            [customs filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *custom, NSDictionary *bindings) {
                return ![custom[@"id"] isEqual:categoryID];
            }]];
        }
        // Added and renamed custom categories take this page's entry
        for(NSDictionary *mine in _customs) {
            NSUInteger index = [customs indexOfObjectPassingTest:^BOOL(NSDictionary *custom, NSUInteger i, BOOL *stop) {
                return [custom[@"id"] isEqual:mine[@"id"]];
            }];
            if(index == NSNotFound) [customs addObject:mine];
            else if([_renamed containsObject:mine[@"id"]]) customs[index] = mine;
        }
        for(NSNumber *categoryID in _renamed) {
            if([_deleted containsObject:categoryID]) continue;
            NSString *key = [categoryID stringValue];
            if(_nameOverrides[key]) names[key] = _nameOverrides[key];
            else [names removeObjectForKey:key];
        }
        if(_dockChanged) {
            if(_dockCategory) [defaults setObject:_dockCategory forKey:ARILibraryDockCategoryKey];
            else [defaults removeObjectForKey:ARILibraryDockCategoryKey];
        } else if([_deleted containsObject:[defaults objectForKey:ARILibraryDockCategoryKey]]) {
            [defaults removeObjectForKey:ARILibraryDockCategoryKey];
        }
        if(_reordered || [_deleted count]) {
            NSMutableArray *order = [NSMutableArray new];
            for(NSDictionary *category in _categories) [order addObject:[category[@"id"] stringValue]];
            if([order count]) [defaults setObject:order forKey:ARILibraryCategoryOrderKey];
        }
    }

    void (^store)(id, NSString *) = ^(id value, NSString *key) {
        if([value count]) [defaults setObject:value forKey:key];
        else [defaults removeObjectForKey:key];
    };
    store(apps, ARILibraryCategoryAppsKey);
    store(names, ARILibraryCategoryNamesKey);
    store(orders, ARILibraryCategoryAppOrderKey);
    store(customs, ARILibraryCustomCategoriesKey);
    [defaults synchronize];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("me.lau.Atria/ReloadPrefs"), NULL, NULL, YES);

    // Saved now, so a later save must not replay these over a long-press change made in between
    [_touched removeAllObjects];
    [_movedApps removeAllObjects];
    [_renamed removeAllObjects];
    [_deleted removeAllObjects];
    _reordered = NO;
    _dockChanged = NO;
    _dirty = NO;
}

- (NSString *)_appName:(NSString *)bundleID {
    NSString *name = [_appNames objectForKey:bundleID];
    if(name) return name;
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    if([proxyClass respondsToSelector:@selector(applicationProxyForIdentifier:)]) {
        id proxy = [proxyClass applicationProxyForIdentifier:bundleID];
        if([proxy respondsToSelector:@selector(localizedName)]) {
            id localized = [proxy localizedName];
            if([localized isKindOfClass:[NSString class]] && [localized length]) name = localized;
        }
    }
    name = name ?: bundleID;
    [_appNames setObject:name forKey:bundleID];
    return name;
}

- (UIImage *)_appIcon:(NSString *)bundleID {
    UIImage *icon = [_appIcons objectForKey:bundleID];
    if(icon || ![UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) return icon;
    icon = [UIImage _applicationIconImageForBundleIdentifier:bundleID format:0 scale:[UIScreen mainScreen].scale];
    if(icon) [_appIcons setObject:icon forKey:bundleID];
    return icon;
}

- (void)_addCategory {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"New Category"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Name";
        field.autocapitalizationType = UITextAutocapitalizationTypeWords;
    }];
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Add"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
                                                NSString *name = [weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                                                if(![name length]) return;
                                                NSNumber *categoryID = [self _nextCategoryID];
                                                [_customs addObject:@{ @"id" : categoryID, @"name" : name }];
                                                [_categories addObject:[@{ @"id" : categoryID, @"apps" : [NSMutableArray new], @"custom" : @YES } mutableCopy]];
                                                _reordered = YES;
                                                _dirty = YES;
                                                [self.tableView reloadData];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)_renameCategoryAtIndex:(NSUInteger)index {
    NSNumber *categoryID = _categories[index][@"id"];
    NSString *baseName = [self _baseNameForID:categoryID];
    BOOL custom = [_categories[index][@"custom"] boolValue];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Rename Category"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = [self _nameForID:categoryID];
        field.placeholder = baseName;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Rename"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
                                                NSString *name = [weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                                                NSString *key = [categoryID stringValue];
                                                if(custom && [name length]) {
                                                    NSUInteger customIndex = [self _customIndexForID:categoryID];
                                                    if(customIndex != NSNotFound) _customs[customIndex] = @{ @"id" : categoryID, @"name" : name };
                                                    [_nameOverrides removeObjectForKey:key];
                                                } else if(![name length] || [name isEqualToString:baseName]) {
                                                    [_nameOverrides removeObjectForKey:key];
                                                } else {
                                                    _nameOverrides[key] = name;
                                                }
                                                [_renamed addObject:categoryID];
                                                _dirty = YES;
                                                [self.tableView reloadRowsAtIndexPaths:@[ [NSIndexPath indexPathForRow:index inSection:0] ] withRowAnimation:UITableViewRowAnimationNone];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

// Its apps go back to the category they came from
- (void)_deleteCategoryAtIndex:(NSUInteger)index {
    NSNumber *categoryID = _categories[index][@"id"];
    NSString *key = [categoryID stringValue];
    for(NSString *bundleID in [_appOverrides allKeys])
        if([_appOverrides[bundleID] isEqual:categoryID]) [_appOverrides removeObjectForKey:bundleID];
    [_appOrder removeObjectForKey:key];
    [_nameOverrides removeObjectForKey:key];
    NSUInteger customIndex = [self _customIndexForID:categoryID];
    if(customIndex != NSNotFound) [_customs removeObjectAtIndex:customIndex];
    [_categories removeObjectAtIndex:index];
    [_deleted addObject:categoryID];
    if([_dockCategory isEqual:categoryID]) {
        _dockCategory = nil;
        _dockChanged = YES;
    }
    _dirty = YES;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if(!_loaded) return 1;
    return _mode == ARICategoryEditorModeApps ? [_categories count] : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if(!_loaded) return 0;
    return _mode == ARICategoryEditorModeApps ? [_categories[section][@"apps"] count] : [_categories count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if(!_loaded || _mode != ARICategoryEditorModeApps) return nil;
    return [self _nameForID:_categories[section][@"id"]];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if(!_loaded) return @"Open the App Library once with Custom Categories on, then come back.";
    if(_mode == ARICategoryEditorModeOrder) return @"Tap a category to rename it or show it on the dock's App Library icon. A new category shows in the App Library once an app is moved into it.";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if(!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"Cell"];
    if(_mode == ARICategoryEditorModeApps) {
        NSString *bundleID = _categories[indexPath.section][@"apps"][indexPath.row];
        cell.textLabel.text = [self _appName:bundleID];
        cell.imageView.image = [self _appIcon:bundleID];
        cell.detailTextLabel.text = nil;
    } else {
        NSDictionary *category = _categories[indexPath.row];
        cell.textLabel.text = [self _nameForID:category[@"id"]];
        cell.imageView.image = [_dockCategory isEqual:category[@"id"]] ? [UIImage systemImageNamed:@"dock.rectangle"] : nil;
        cell.detailTextLabel.text = [@([category[@"apps"] count]) stringValue];
    }
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    if(_mode == ARICategoryEditorModeOrder && [_categories[indexPath.row][@"custom"] boolValue]) return UITableViewCellEditingStyleDelete;
    return UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath {
    if(style != UITableViewCellEditingStyleDelete || _mode != ARICategoryEditorModeOrder) return;
    [self _deleteCategoryAtIndex:indexPath.row];
    [tableView deleteRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    if(_mode == ARICategoryEditorModeApps) {
        NSMutableArray *source = _categories[from.section][@"apps"];
        NSMutableArray *destination = _categories[to.section][@"apps"];
        NSString *bundleID = source[from.row];
        [source removeObjectAtIndex:from.row];
        [destination insertObject:bundleID atIndex:MIN((NSUInteger)to.row, [destination count])];
        [_touched addObject:_categories[from.section][@"id"]];
        [_touched addObject:_categories[to.section][@"id"]];
        [_movedApps addObject:bundleID];
    } else {
        NSMutableDictionary *category = _categories[from.row];
        [_categories removeObjectAtIndex:from.row];
        [_categories insertObject:category atIndex:to.row];
        _reordered = YES;
    }
    _dirty = YES;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if(_mode == ARICategoryEditorModeOrder) [self _showActionsForCategoryAtIndexPath:indexPath];
}

- (void)_showActionsForCategoryAtIndexPath:(NSIndexPath *)indexPath {
    NSUInteger index = indexPath.row;
    NSNumber *categoryID = _categories[index][@"id"];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:[self _nameForID:categoryID]
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Rename"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
                                                [self _renameCategoryAtIndex:index];
                                            }]];
    // An empty category has no pod for the dock to show
    if(![_dockCategory isEqual:categoryID] && [_categories[index][@"apps"] count]) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Show in Dock"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
                                                    [self _setDockCategory:categoryID];
                                                }]];
    }
    if(_dockCategory) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Use First Category"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
                                                    [self _setDockCategory:nil];
                                                }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    sheet.popoverPresentationController.sourceView = cell ?: self.view;
    sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)_setDockCategory:(NSNumber *)categoryID {
    _dockCategory = categoryID;
    _dockChanged = YES;
    _dirty = YES;
    [self.tableView reloadData];
}

@end
