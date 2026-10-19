include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AtriaPrefs

AtriaPrefs_FILES = $(wildcard src/*.m)
AtriaPrefs_INSTALL_PATH = /Library/PreferenceBundles
AtriaPrefs_FRAMEWORKS = UIKit
AtriaPrefs_PRIVATE_FRAMEWORKS = Preferences
AtriaPrefs_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

# Version shown in the settings header, taken from control
ATRIA_VERSION := $(shell sed -n 's/^Version: //p' $(THEOS_PROJECT_DIR)/layout/DEBIAN/control)
ifeq ($(ATRIA_VERSION),)
$(error no Version line in $(THEOS_PROJECT_DIR)/layout/DEBIAN/control)
endif
AtriaPrefs_CFLAGS += -DPACKAGE_VERSION='"$(ATRIA_VERSION)"'

ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
AtriaPrefs_LDFLAGS += -lroothide
endif

include $(THEOS_MAKE_PATH)/bundle.mk
