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
# The fetch target below runs before compilation, so wire the flags unconditionally:
# a clean checkout should either fetch ffmpeg-kit and build correctly, or fail loudly
# instead of producing a download button whose mux path crashes at runtime.
FFMPEGKIT_XCFRAMEWORK := $(PWD)/Frameworks/ffmpegkit.xcframework
FFMPEGKIT_RUNTIME_FRAMEWORKS := ffmpegkit libavcodec libavformat libavutil libavdevice libavfilter libswresample libswscale

# Wire direct slice lookup for Theos/L1ghtmann, which does not fully understand
# xcframework wrappers. The runtime frameworks are manually staged in after-stage.
$(TWEAK_NAME)_CFLAGS += -F$(FFMPEGKIT_XCFRAMEWORK)/ios-arm64
$(TWEAK_NAME)_LDFLAGS += -F$(PWD)/Frameworks -F$(FFMPEGKIT_XCFRAMEWORK)/ios-arm64 -framework ffmpegkit

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
	    $(INSTALL_NAME_TOOL) -add_rpath @loader_path "$$DYLIB" 2>/dev/null || true; \
	    $(INSTALL_NAME_TOOL) -add_rpath /Library/Frameworks "$$DYLIB" 2>/dev/null || true; \
	    if command -v $(TARGET_CODESIGN) >/dev/null 2>&1; then \
	      CODESIGN_ALLOCATE="$(TARGET_CODESIGN_ALLOCATE)" $(TARGET_CODESIGN) $(TARGET_CODESIGN_FLAGS) "$$DYLIB" >/dev/null 2>&1 || true; \
	    fi; \
	  fi; \
	else \
	  echo "  install_name_tool not found — skipping Substrate path rewrite (will need post-cyan fix)"; \
	fi

after-stage::
	@FW_DST="$(THEOS_STAGING_DIR)/Library/Frameworks"; \
	mkdir -p "$$FW_DST"; \
	for fw in $(FFMPEGKIT_RUNTIME_FRAMEWORKS); do \
	  src="$(PWD)/Frameworks/$$fw.xcframework/ios-arm64/$$fw.framework"; \
	  dst="$$FW_DST/$$fw.framework"; \
	  if [ ! -d "$$src" ]; then \
	    echo "  ERROR: missing ffmpeg-kit runtime framework: $$src"; \
	    exit 1; \
	  fi; \
	  rm -rf "$$dst"; \
	  cp -R "$$src" "$$dst"; \
	  find "$$dst" -name .DS_Store -delete; \
	  echo "  Staged $$fw.framework"; \
	done; \
	if [ -n "$(INSTALL_NAME_TOOL)" ]; then \
	  for fw in $(FFMPEGKIT_RUNTIME_FRAMEWORKS); do \
	    bin="$$FW_DST/$$fw.framework/$$fw"; \
	    if [ -f "$$bin" ]; then \
	      $(INSTALL_NAME_TOOL) -id "@rpath/$$fw.framework/$$fw" "$$bin" 2>/dev/null || true; \
	      $(INSTALL_NAME_TOOL) -add_rpath @loader_path/.. "$$bin" 2>/dev/null || true; \
	      $(INSTALL_NAME_TOOL) -add_rpath /Library/Frameworks "$$bin" 2>/dev/null || true; \
	      if command -v $(TARGET_CODESIGN) >/dev/null 2>&1; then \
	        CODESIGN_ALLOCATE="$(TARGET_CODESIGN_ALLOCATE)" $(TARGET_CODESIGN) $(TARGET_CODESIGN_FLAGS) "$$bin" >/dev/null 2>&1 || true; \
	      fi; \
	    fi; \
	  done; \
	else \
	  echo "  install_name_tool not found — ffmpeg-kit framework rpaths were not normalized"; \
	fi
