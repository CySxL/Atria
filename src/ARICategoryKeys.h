#import <Foundation/Foundation.h>

// App Library category settings, shared by SpringBoard and the settings page

static NSString *const ARILibraryCategoryAppsKey = @"libraryCategoryApps";
static NSString *const ARILibraryCategoryNamesKey = @"libraryCategoryNames";
static NSString *const ARILibraryCategoryOrderKey = @"libraryCategoryOrder";
static NSString *const ARILibraryCategoryAppOrderKey = @"libraryCategoryAppOrder";
static NSString *const ARILibraryCustomCategoriesKey = @"libraryCustomCategories";
static NSString *const ARILibraryCategoryNextIDKey = @"libraryCategoryNextID";
static NSString *const ARILibraryHideSuggestionsKey = @"libraryHideSuggestions";
static NSString *const ARILibraryHideRecentKey = @"libraryHideRecent";
static NSString *const ARILibraryDockCategoryKey = @"libraryDockCategory";

// Every key Reset Categories clears
#define ARILibraryCategoryKeys @[ ARILibraryCategoryAppsKey, ARILibraryCategoryNamesKey, ARILibraryCategoryOrderKey, \
	ARILibraryCategoryAppOrderKey, ARILibraryCustomCategoriesKey, ARILibraryCategoryNextIDKey, \
	ARILibraryHideSuggestionsKey, ARILibraryHideRecentKey, ARILibraryDockCategoryKey ]

// The ones naming installed apps or typed names, and those meaningless without custom categories
#define ARILibraryCategoryPersonalKeys @[ ARILibraryCategoryAppsKey, ARILibraryCategoryAppOrderKey, \
	ARILibraryCategoryNamesKey, ARILibraryCustomCategoriesKey, ARILibraryCategoryOrderKey, \
	ARILibraryCategoryNextIDKey, ARILibraryDockCategoryKey ]

// Suggestions and Recently Added, rebuilt by the system on their own schedule
static const NSUInteger ARISuggestedCategoryID = 3;
static const NSUInteger ARIRecentCategoryID = 4;
// Custom categories take IDs from here up, clear of Apple's 1xxx and 6xxx
static const NSUInteger ARIFirstCustomCategoryID = 9001;
