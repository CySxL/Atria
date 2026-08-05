TARGET := iphone:clang:16.5:13.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Atria

Atria_FILES = $(wildcard src/Hooks/*.xm) \
              $(wildcard src/Manager/*.m) \
              $(wildcard src/Options/*.m) \
              $(wildcard src/Editor/*.m) \
              $(wildcard src/UI/*.m) \
              $(wildcard src/UI/Effect/*.m) \
              $(wildcard src/UI/Label/*.m) \
              $(wildcard src/UI/Splash/*.m)
Atria_FRAMEWORKS = UIKit CoreGraphics QuartzCore CoreText
Atria_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
Atria_LDFLAGS += -lroothide
endif

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
