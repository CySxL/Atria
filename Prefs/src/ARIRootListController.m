//
// Created by ren7995 on 2021-04-17 13:45:45
// Copyright (c) 2021 ren7995. All rights reserved.
//

#import "ARIRootListController.h"
#import "../../src/ARIPaths.h"
#import "../../src/UI/Splash/ARISplashViewController.h"

#import <Preferences/PSTableCell.h>

#if defined(THEOS_PACKAGE_SCHEME_ROOTHIDE)
#define PACKAGE_SCHEME "roothide"
#elif defined(THEOS_PACKAGE_SCHEME_ROOTLESS)
#define PACKAGE_SCHEME "rootless"
#elif defined(THEOS_PACKAGE_SCHEME_ROOTFUL)
#define PACKAGE_SCHEME "rootful"
#else
#error theos defined no package scheme
#endif

static const CGFloat kARIIconSide = 80.0;
static const CGFloat kARIHeaderGap = 16.0;
static const CGFloat kARINameSize = 34.0;
static const CGFloat kARIVersionSize = 15.0;
static const CGFloat kARISchemeSize = 13.0;
static const CGFloat kARINameToVersion = 24.0;
static const CGFloat kARIVersionToScheme = 19.0;
static const CGFloat kARIAvatarSide = 38.0;

// The row indents its text by the width of the image it carries, so a symbol
// takes the same square an avatar does or the two titles do not line up.
static UIImage *ARISymbol(NSString *name, CGFloat side) {
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:20.0 weight:UIImageSymbolWeightMedium];
    UIImage *symbol = [UIImage systemImageNamed:name withConfiguration:configuration] ?: [UIImage systemImageNamed:@"link" withConfiguration:configuration];
    if(!symbol) return nil;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    UIImage *padded = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [symbol drawInRect:CGRectMake((side - symbol.size.width) / 2.0, (side - symbol.size.height) / 2.0, symbol.size.width, symbol.size.height)];
    }];
    return [padded imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

@interface ARIHeaderCell : PSTableCell
@end

@implementation ARIHeaderCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:identifier specifier:specifier];
    if(!self) return nil;

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage imageWithContentsOfFile:ARIPrefsBundlePath(@"/full.png")]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.clipsToBounds = YES;
    icon.layer.cornerCurve = kCACornerCurveContinuous;
    icon.layer.cornerRadius = kARIIconSide * 0.225;
    [self.contentView addSubview:icon];

    UIFontDescriptor *bold = [[UIFontDescriptor preferredFontDescriptorWithTextStyle:UIFontTextStyleLargeTitle]
        fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold];
    UIFont *nameFont = [UIFont fontWithDescriptor:bold size:kARINameSize];
    UIFont *schemeFont = [UIFont systemFontOfSize:kARISchemeSize];

    UILabel *name = [[UILabel alloc] init];
    name.text = @"Atria";
    name.font = nameFont;
    // The star's cream is unreadable on a light page, so light mode takes the
    // icon's own background instead.
    name.textColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        if(traits.userInterfaceStyle == UIUserInterfaceStyleDark)
            return [UIColor colorWithRed:0xff / 255.0 green:0xff / 255.0 blue:0xc0 / 255.0 alpha:1.0];
        return [UIColor colorWithRed:0x4c / 255.0 green:0x47 / 255.0 blue:0x46 / 255.0 alpha:1.0];
    }];

    UILabel *version = [[UILabel alloc] init];
    version.text = @"Version " PACKAGE_VERSION;
    version.font = [UIFont systemFontOfSize:kARIVersionSize];
    version.textColor = [UIColor systemGrayColor];

    UILabel *scheme = [[UILabel alloc] init];
    scheme.text = @PACKAGE_SCHEME.capitalizedString;
    scheme.font = schemeFont;
    scheme.textColor = [UIColor systemGrayColor];

    // Baseline to baseline, so the large name's leading does not push the two
    // lines under it apart.
    UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[ name, version, scheme ]];
    text.axis = UILayoutConstraintAxisVertical;
    text.alignment = UIStackViewAlignmentLeading;
    text.baselineRelativeArrangement = YES;
    [text setCustomSpacing:kARINameToVersion afterView:name];
    [text setCustomSpacing:kARIVersionToScheme afterView:version];
    text.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:text];

    // The name's baseline sits where it centres the whole block on the icon.
    CGFloat blockHeight = nameFont.ascender + kARINameToVersion + kARIVersionToScheme - schemeFont.descender;

    // Icon and text centred as one block, never past the leading margin.
    UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
    UILayoutGuide *block = [[UILayoutGuide alloc] init];
    [self.contentView addLayoutGuide:block];
    NSLayoutConstraint *centred = [block.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor];
    centred.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [icon.widthAnchor constraintEqualToConstant:kARIIconSide],
        [icon.heightAnchor constraintEqualToConstant:kARIIconSide],
        [block.leadingAnchor constraintEqualToAnchor:icon.leadingAnchor],
        [block.trailingAnchor constraintEqualToAnchor:text.trailingAnchor],
        [icon.leadingAnchor constraintGreaterThanOrEqualToAnchor:margins.leadingAnchor],
        centred,
        [icon.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [text.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:kARIHeaderGap],
        [name.firstBaselineAnchor constraintEqualToAnchor:icon.centerYAnchor constant:nameFont.ascender - blockHeight / 2.0]
    ]];

    return self;
}

- (void)setSeparatorStyle:(UITableViewCellSeparatorStyle)style {
    [super setSeparatorStyle:UITableViewCellSeparatorStyleNone];
}

- (void)setBackgroundColor:(UIColor *)color {
    [super setBackgroundColor:[UIColor clearColor]];
}

- (UITableViewCellSelectionStyle)selectionStyle {
    return UITableViewCellSelectionStyleNone;
}

@end

@interface ARICreditCell : PSTableCell
@end

@implementation ARICreditCell {
    UIImageView *_avatarView;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier specifier:specifier];
    if(!self) return nil;

    self.detailTextLabel.text = [specifier propertyForKey:@"subtitle"] ?: @"";
    self.detailTextLabel.textColor = [UIColor systemGrayColor];
    self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    UIImage *avatar = [specifier propertyForKey:@"ariAvatar"];
    if(![avatar isKindOfClass:[UIImage class]]) {
        self.imageView.tintColor = [UIColor secondaryLabelColor];
        return self;
    }

    // An empty image of the right size, so the row lays out before the avatar is drawn into it
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(kARIAvatarSide, kARIAvatarSide), NO, [UIScreen mainScreen].scale);
    [specifier setProperty:UIGraphicsGetImageFromCurrentImageContext() forKey:@"iconImage"];
    UIGraphicsEndImageContext();

    _avatarView = [[UIImageView alloc] initWithFrame:self.imageView.bounds];
    _avatarView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _avatarView.contentMode = UIViewContentModeScaleAspectFill;
    _avatarView.clipsToBounds = YES;
    _avatarView.layer.cornerRadius = kARIAvatarSide * 0.5;
    _avatarView.layer.minificationFilter = kCAFilterTrilinear;
    _avatarView.image = avatar;
    [self.imageView addSubview:_avatarView];

    return self;
}

@end

@implementation ARIRootListController

- (NSArray *)specifiers {
    if(!_specifiers) {
        NSMutableArray *specifiers = [NSMutableArray array];

        PSSpecifier *header = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:NULL get:NULL detail:nil cell:PSStaticTextCell edit:nil];
        [header setProperty:[ARIHeaderCell class] forKey:@"cellClass"];
        [header setProperty:@142 forKey:@"height"];
        [specifiers addObject:header];

        PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
        [group setProperty:@"In order to edit layout, 3D touch a homescreen icon, or triple tap behind them (on your wallpaper)" forKey:@"footerText"];
        [specifiers addObject:group];

        NSArray *rootSpecifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        NSMutableArray *developerRows = [NSMutableArray array];

        PSSpecifier *credits = [PSSpecifier emptyGroupSpecifier];
        [credits setProperty:@"Credits" forKey:@"label"];
        [credits setProperty:@"© CySxL 2026" forKey:@"footerText"];
        [developerRows addObject:credits];

        PSSpecifier *original = [PSSpecifier preferenceSpecifierNamed:@"ren7995" target:self set:NULL get:NULL detail:nil cell:PSLinkCell edit:nil];
        [original setProperty:[ARICreditCell class] forKey:@"cellClass"];
        [original setProperty:@"Original Developer" forKey:@"subtitle"];
        [original setProperty:ARISymbol(@"chevron.left.forwardslash.chevron.right", kARIAvatarSide) forKey:@"iconImage"];
        original->action = @selector(openOriginal);
        [developerRows addObject:original];

        PSSpecifier *credit = [PSSpecifier preferenceSpecifierNamed:@"CySxL" target:self set:NULL get:NULL detail:nil cell:PSLinkCell edit:nil];
        [credit setProperty:[ARICreditCell class] forKey:@"cellClass"];
        [credit setProperty:@"Roothide Port" forKey:@"subtitle"];
        [credit setProperty:[UIImage imageNamed:@"avatar" inBundle:[NSBundle bundleForClass:[self class]] withConfiguration:nil] forKey:@"ariAvatar"];
        credit->action = @selector(openGitHub);
        [developerRows addObject:credit];

        // The developers come before the upstream thanks group
        NSUInteger thanks = [rootSpecifiers indexOfObjectPassingTest:^BOOL(PSSpecifier *specifier, NSUInteger index, BOOL *stop) {
            return [specifier.identifier isEqualToString:@"thanksGroup"];
        }];
        if(thanks == NSNotFound) thanks = rootSpecifiers.count;
        [specifiers addObjectsFromArray:[rootSpecifiers subarrayWithRange:NSMakeRange(0, thanks)]];
        [specifiers addObjectsFromArray:developerRows];
        [specifiers addObjectsFromArray:[rootSpecifiers subarrayWithRange:NSMakeRange(thanks, rootSpecifiers.count - thanks)]];

        _specifiers = specifiers;
    }

    return _specifiers;
}

- (void)resetPrefs:(id)sender {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Reset Preferences"
                         message:@"Are you sure you want to reset preferences? Your device will respring."
                  preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *defaultAction = [UIAlertAction
        actionWithTitle:@"No"
                  style:UIAlertActionStyleCancel
                handler:nil];
    UIAlertAction *yes = [UIAlertAction
        actionWithTitle:@"Yes"
                  style:UIAlertActionStyleDestructive
                handler:^(UIAlertAction *action) {
                    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];
                    [prefs removePersistentDomainForName:ARIPreferenceDomain];
                    [prefs synchronize];
                    [self respringWithAnimation];
                }];

    [alert addAction:defaultAction];
    [alert addAction:yes];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)resetSaveState:(id)sender {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Reset Save State"
                         message:@"Are you sure you want to reset save state? Your device will respring."
                  preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *defaultAction = [UIAlertAction
        actionWithTitle:@"No"
                  style:UIAlertActionStyleCancel
                handler:nil];
    UIAlertAction *yes = [UIAlertAction
        actionWithTitle:@"Yes"
                  style:UIAlertActionStyleDestructive
                handler:^(UIAlertAction *action) {
                    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];
                    [prefs removeObjectForKey:@"_saveState"];
                    [prefs synchronize];
                    [self respringWithAnimation];
                }];

    [alert addAction:defaultAction];
    [alert addAction:yes];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)exportSettingsString {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];
    [defaults synchronize];
    NSMutableDictionary *dict = [[defaults persistentDomainForName:ARIPreferenceDomain] mutableCopy]
                                    ?: [NSMutableDictionary new];

    for(NSString *key in [dict allKeys])
        if([key hasPrefix:@"_"] && ![key isEqualToString:ARIPerPageListViewsKey])
            [dict removeObjectForKey:key];

    // Easier to make it json imho
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict
                                                       options:0
                                                         error:&error];
    if(error) {
        [self displayAlert:@"Failed to export" message:[NSString stringWithFormat:@"Error: %@", error.localizedDescription]];
        return;
    }

    NSString *encoded = [jsonData base64EncodedStringWithOptions:0];
    [UIPasteboard generalPasteboard].string = encoded;
    [self displayAlert:@"Success" message:@"Settings exported and copied to clipboard"];
}

- (void)importSettingsString {
    NSString *pasteboardString = [UIPasteboard generalPasteboard].string;
    if(!pasteboardString) {
        [self displayAlert:@"Failed to import" message:@"No string was found in your clipboard."];
        return;
    }
    NSData *decodeData = [[NSData alloc] initWithBase64EncodedString:pasteboardString options:0];
    if(!decodeData) {
        [self displayAlert:@"Failed to import" message:@"Failed to decode. Perhaps the settings string in your clipboard is invalid?"];
        return;
    }

    NSError *error;
    id decoded = [NSJSONSerialization JSONObjectWithData:decodeData options:kNilOptions error:&error];

    if(![decoded isKindOfClass:[NSDictionary class]]) {
        [self displayAlert:@"Failed to import" message:[NSString stringWithFormat:@"Perhaps the settings string in your clipboard is invalid?\n\nError: %@", error.localizedDescription]];
        return;
    }
    NSDictionary *settingsDictionary = decoded;

    NSMutableDictionary *accepted = [NSMutableDictionary new];
    for(NSString *key in settingsDictionary) {
        if(![key isKindOfClass:[NSString class]]) continue;

        id value = settingsDictionary[key];
        if([key isEqualToString:ARIPerPageListViewsKey]) {
            if(![value isKindOfClass:[NSArray class]]) continue;
            BOOL allStrings = YES;
            for(id prefix in (NSArray *)value)
                if(![prefix isKindOfClass:[NSString class]]) allStrings = NO;
            if(allStrings) accepted[key] = value;
            continue;
        }

        // The underscore prefix means it's an internal setting, not meant to be shared
        if([key hasPrefix:@"_"]) continue;
        if(![value isKindOfClass:[NSString class]] && ![value isKindOfClass:[NSNumber class]]) continue;
        accepted[key] = value;
    }

    if([accepted count] == 0) {
        [self displayAlert:@"Failed to import" message:@"No usable settings were found in that string."];
        return;
    }

    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];
    [defaults removePersistentDomainForName:ARIPreferenceDomain];
    defaults = [[NSUserDefaults alloc] initWithSuiteName:ARIPreferenceDomain];
    [defaults synchronize];

    // Set ARIDidSplashPreferenceKey, since they are in preferences already
    [defaults setObject:@(YES) forKey:ARIDidSplashPreferenceKey];

    for(NSString *key in accepted) {
        [defaults setObject:accepted[key] forKey:key];
    }
    [defaults synchronize];

    NSUInteger skipped = [settingsDictionary count] - [accepted count];
    NSString *message = skipped > 0
                            ? [NSString stringWithFormat:@"Settings imported. You may now respring to apply completely.\n\n%lu imported, %lu skipped.", (unsigned long)[accepted count], (unsigned long)skipped]
                            : [NSString stringWithFormat:@"Settings imported. You may now respring to apply completely.\n\n%lu imported.", (unsigned long)[accepted count]];

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Success"
                         message:message
                  preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *defaultAction = [UIAlertAction
        actionWithTitle:@"Respring"
                  style:UIAlertActionStyleDestructive
                handler:^(UIAlertAction *action) {
                    [self respringWithAnimation];
                }];
    [alert addAction:defaultAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)openOriginal {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/ren7995/Atria"] options:@{} completionHandler:nil];
}

- (void)openGitHub {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/CySxL"] options:@{} completionHandler:nil];
}

- (void)displayAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:title
                         message:message
                  preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *defaultAction = [UIAlertAction
        actionWithTitle:@"OK"
                  style:UIAlertActionStyleCancel
                handler:nil];

    [alert addAction:defaultAction];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
