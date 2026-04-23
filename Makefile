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
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation SystemConfiguration AVKit AVFoundation OSLog Photos
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

# Auto-fetch ffmpeg-kit before compilation. Idempotent — exits immediately if
# Frameworks/ffmpegkit.xcframework/Info.plist already exists. See
# scripts/fetch-ffmpegkit.sh for the mirror + pin rationale.
#
# Theos exposes `before-all::` as a pre-build hook. We also register the marker
# file as the target so make knows to re-run the fetch if the framework is
# deleted out from under us.
before-all:: $(FFMPEGKIT_XCFRAMEWORK)/Info.plist

$(FFMPEGKIT_XCFRAMEWORK)/Info.plist:
	@bash scripts/fetch-ffmpegkit.sh

.PHONY: ffmpegkit
ffmpegkit:
	@bash scripts/fetch-ffmpegkit.sh

# Post-stage: rewrite the absolute /Library/Frameworks/CydiaSubstrate... load path
# to @rpath/... so the built .dylib is sideload-ready without any post-cyan fix step.
#
# Why this is needed: Theos on Linux links against CydiaSubstrate using the jailbreak
# absolute path, which dyld can't resolve inside a sideloaded app bundle. Cyan normally
# rewrites this during injection, but anyone who grabs the .dylib out of the .deb and
# hand-assembles an IPA (the exact mistake that took v11 two tries) skips that step.
# Doing it in the Makefile guarantees every consumer of the .deb gets a correct dylib.
#
# Locates install_name_tool in Theos's bundled toolchain first (Linux/L1ghtmann),
# then falls back to PATH (macOS CI). Silently skips if neither is available.
INSTALL_NAME_TOOL := $(firstword $(wildcard $(THEOS)/toolchain/linux/iphone/bin/install_name_tool) $(shell command -v install_name_tool 2>/dev/null))

after-stage::
	@if [ -n "$(INSTALL_NAME_TOOL)" ]; then \
	  DYLIB="$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/$(TWEAK_NAME).dylib"; \
	  if [ -f "$$DYLIB" ]; then \
	    echo "  Rewriting Substrate load path -> @rpath in $$DYLIB"; \
	    $(INSTALL_NAME_TOOL) -change \
	      /Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate \
	      @rpath/CydiaSubstrate.framework/CydiaSubstrate \
	      "$$DYLIB" 2>/dev/null || true; \
	  fi; \
	else \
	  echo "  install_name_tool not found — skipping Substrate path rewrite (will need post-cyan fix)"; \
	fi
