//
// Package path resolution for rootful, rootless and roothide.
//

#import <Foundation/Foundation.h>

// Variadic so callers can pass a +stringWithFormat: expression without the
// commas splitting the macro arguments

#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
#import <roothide.h>
// jbroot() resolves the randomised jbroot at call time, so never cache the result
#define ARIRootPath(...) jbroot((__VA_ARGS__))
#else
#define ARIRootPath(...) [@THEOS_PACKAGE_INSTALL_PREFIX stringByAppendingString:(__VA_ARGS__)]
#endif

#define ARIPrefsBundlePath(...) ARIRootPath([@"/Library/PreferenceBundles/AtriaPrefs.bundle" stringByAppendingString:(__VA_ARGS__)])
#define ARIDylibPath(...) ARIRootPath([@"/Library/MobileSubstrate/DynamicLibraries/" stringByAppendingString:(__VA_ARGS__)])
