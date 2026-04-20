ifeq ($(ROOTLESS),1)
THEOS_PACKAGE_SCHEME=rootless
else ifeq ($(ROOTHIDE),1)
THEOS_PACKAGE_SCHEME=roothide
endif

ARCHS = arm64
TARGET := iphone:clang:16.5:13.0
PACKAGE_VERSION = 1.0.0
INSTALL_TARGET_PROCESSES = YouTube

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AfterglowOverlay

$(TWEAK_NAME)_FILES = \
    YTVideoOverlay/Tweak.x \
    YouGroupSettings/Tweak.x \
    YouPiP/Tweak.x \
    YouPiP/Settings.x \
    YouPiP/LegacyPiPCompat.x \
    YouMute/Tweak.x \
    YouQuality/Tweak.x \
    ../Utils/YTAGLog.m

$(TWEAK_NAME)_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation AVFoundation AVKit

include $(THEOS_MAKE_PATH)/tweak.mk
