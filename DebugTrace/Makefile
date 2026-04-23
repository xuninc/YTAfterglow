DEBUG=0
FINALPACKAGE=1
ARCHS = arm64
PACKAGE_VERSION = 1.0.0
TARGET := iphone:clang:16.5:13.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AfterglowDebugTrace
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation AVKit AVFoundation OSLog
$(TWEAK_NAME)_CFLAGS = -fobjc-arc -I..
$(TWEAK_NAME)_FILES = DebugTrace.x ../Utils/YTAGLog.m ../Utils/YTAGDebugHUD.m

include $(THEOS_MAKE_PATH)/tweak.mk
