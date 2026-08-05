include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AtriaPrefs

AtriaPrefs_FILES = $(wildcard src/*.m)
AtriaPrefs_INSTALL_PATH = /Library/PreferenceBundles
AtriaPrefs_FRAMEWORKS = UIKit
AtriaPrefs_PRIVATE_FRAMEWORKS = Preferences
AtriaPrefs_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

# Version shown in the prefs header, taken from the control file
ATRIA_VERSION = $(shell grep -i "^Version:" $(THEOS_PROJECT_DIR)/layout/DEBIAN/control | cut -d' ' -f2-)
AtriaPrefs_CFLAGS += -DPACKAGE_VERSION='"$(ATRIA_VERSION)"'
AtriaPrefs_CFLAGS += -DPACKAGE_TYPE='"$(or $(THEOS_PACKAGE_SCHEME),rootful)"'

ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
AtriaPrefs_LDFLAGS += -lroothide
endif

include $(THEOS_MAKE_PATH)/bundle.mk
