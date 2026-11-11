#import <Foundation/Foundation.h>

#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
#import <roothide.h>
#define ARIRootPath(...) jbroot((__VA_ARGS__))
#else
#define ARIRootPath(...) [@THEOS_PACKAGE_INSTALL_PREFIX stringByAppendingString:(__VA_ARGS__)]
#endif

#define ARIPrefsBundlePath(...) ARIRootPath([@"/Library/PreferenceBundles/AtriaPrefs.bundle" stringByAppendingString:(__VA_ARGS__)])
#define ARIDylibPath(...) ARIRootPath([@"/Library/MobileSubstrate/DynamicLibraries/" stringByAppendingString:(__VA_ARGS__)])

// Written by SpringBoard while Custom Categories is on, read by the settings page
#define ARILibraryCategoriesPath ARIRootPath(@"/var/mobile/Library/Preferences/com.cysxl.atria.categories.plist")
