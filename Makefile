ifeq ($(ROOTLESS),1)
THEOS_PACKAGE_SCHEME=rootless
else ifeq ($(ROOTHIDE),1)
THEOS_PACKAGE_SCHEME=roothide
endif

DEBUG=0
FINALPACKAGE=1
ARCHS = arm64
PACKAGE_VERSION = 1.0.0
TARGET := iphone:clang:16.5:13.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YTAfterglow
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation SystemConfiguration AVKit AVFoundation OSLog
# ffmpeg-kit links against these iOS system frameworks/libs at runtime.
$(TWEAK_NAME)_FRAMEWORKS += VideoToolbox AudioToolbox CoreMedia CoreVideo CoreAudio Security
$(TWEAK_NAME)_LIBRARIES += z bz2 iconv
$(TWEAK_NAME)_CFLAGS = -fobjc-arc -DTWEAK_VERSION=$(PACKAGE_VERSION)
$(TWEAK_NAME)_FILES = $(wildcard *.x Utils/*.m UI/*.m)

# ffmpeg-kit xcframework integration.
#
# The xcframework is NOT checked into git (~40 MB for the "min" variant, ~500 MB+ for
# the full "ios" variant). See Frameworks/README.md for drop-in instructions.
#
# When the xcframework is present Theos links against it and embeds it in the .dylib's
# bundle (cyan then propagates it into the final IPA's Frameworks/). When it's absent
# the build still compiles — FFMpegHelper.m uses __has_include to fall back to stub
# forward declarations — but the mux will crash at runtime if actually invoked.
FFMPEGKIT_XCFRAMEWORK := $(PWD)/Frameworks/ffmpegkit.xcframework
ifneq ($(wildcard $(FFMPEGKIT_XCFRAMEWORK)/Info.plist),)
# xcframework present — wire it in for both linking (Theos+Xcode on macOS) and
# direct slice lookup (Theos+L1ghtmann on Linux, which doesn't grok xcframeworks).
$(TWEAK_NAME)_LDFLAGS += -F$(PWD)/Frameworks -F$(FFMPEGKIT_XCFRAMEWORK)/ios-arm64 -framework ffmpegkit
$(TWEAK_NAME)_EMBED_FRAMEWORKS += Frameworks/ffmpegkit.xcframework
endif

include $(THEOS_MAKE_PATH)/tweak.mk
