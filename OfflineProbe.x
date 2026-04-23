// OfflineProbe.x — logs all methods on YouTube Premium's offline-download class
// family, and hijacks YT's native Download button.
//
// Two things in one file:
//
// (1) Method-map discovery for the `YTOfflineVideoStreams*` / `YTAppOffline*`
//     class family. At %ctor we enumerate each class's instance methods and log
//     the selector + type encoding to `offline-probe`. When the user taps YT's
//     native Download (Premium-only) and then the actual download kicks off,
//     the invoked methods are already in our dump. Use the dump to decide
//     which specific methods to hook for capturing stream URLs.
//
// (2) Native-button hijack — mirrors YTLite's sub_179C4 (decomp line 343775):
//     hook `-[ELMTouchCommandPropertiesHandler handleTap]` and, if the tapped
//     node's `_accessibilityIdentifier` equals `"id.ui.add_to.offline.button"`
//     (YT's stock Download button), intercept and route to our own download
//     sheet. Guarded by `hijackYTDownload` pref so it's toggleable.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Utils/YTAGLog.h"
#import "Utils/YTAGUserDefaults.h"

// Classes we introspect at launch. List expanded from YT 21.16.2 header dump
// (C:\Users\Corey\youtube_21.16.2\YouTube_Headers.h) — covers the full
// Offline / Download class family. Ordered rough-priority for log readability.
static NSString *const kProbedClassNames[] = {
    // Player-side: these are where our live-read walks, so we dump them to
    // confirm the exact accessor names for playerResponse / streamingData /
    // adaptiveFormats in this YT version.
    @"YTPlayerViewController",
    @"YTPlayerResponse",
    @"YTIPlayerResponse",
    @"YTIStreamingData",
    @"YTIFormatStream",
    @"YTSingleVideoController",

    // Top-priority: format models (hold URLs + itags + sizes)
    @"YTDownloadFormatModel",
    @"YTDownloadQualityPickerEntityModel",
    @"YTDownloadStatusEntityModel",

    // Download orchestration
    @"YTOfflineVideoDownloader",
    @"YTOfflineVideoStreamsDownloadController",
    @"YTOfflineVideoStreamsDownloadRequest",
    @"YTOfflineVideoCaptionsDownloadController",
    @"YTDownloadOptionsPickerController",

    // Entity / store layer
    @"YTOfflineVideoStreamsEntityProvider",
    @"YTOfflineVideoStreamsEntityModel",
    @"YTOfflineVideoStore",
    @"YTOfflineVideoEntity",
    @"YTDownloadedVideoWithContextEntityModel",
    @"YTDownloadedPlaylistModelDataSource",
    @"YTDownloadedVideoDataControllerImpl",
    @"YTDownloadedVideoModelDataSource",
    @"YTMainDownloadedVideoEntityShimControllerImpl",

    // App-level coordinators
    @"YTAppOfflineVideoController",
    @"YTAppOfflineServiceController",
    @"YTAppOfflineResumeControllerImpl",
    @"YTAppOfflineUnifiedResumeControllerImpl",
    @"YTAppOfflineMenuItemControllerImpl",
    @"YTOfflineWatchNavigationCommandHandler",

    // Auto-offline / prefetch
    @"YTAutoOfflineController",
    @"YTAutoOfflineService",
    @"YTDownloadRecommendationsInStore",
    @"YTDownloadRecommendationsServiceImpl",
};
static const NSUInteger kProbedClassCount = sizeof(kProbedClassNames) / sizeof(kProbedClassNames[0]);

static void YTAGDumpClassMethods(NSString *clsName) {
    Class cls = NSClassFromString(clsName);
    if (!cls) {
        YTAGLog(@"offline-probe", @"class not found: %@", clsName);
        return;
    }
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    if (!methods) {
        YTAGLog(@"offline-probe", @"no methods on %@", clsName);
        return;
    }
    for (unsigned int i = 0; i < count; i++) {
        Method m = methods[i];
        SEL sel = method_getName(m);
        const char *typeEncoding = method_getTypeEncoding(m);
        const char *name = sel_getName(sel);
        // Skip internal/private methods that don't give us useful signal.
        if (name[0] == '.') continue;
        if (strncmp(name, "_", 1) == 0) continue;
        YTAGLog(@"offline-probe", @"-[%@ %s] %s", clsName, name, typeEncoding ?: "?");
    }
    free(methods);
    YTAGLog(@"offline-probe", @"---- %@ : %u methods ----", clsName, count);
}

// ----- Native Download button hijack ------------------------------------------
//
// ELMTouchCommandPropertiesHandler is the tap dispatcher for YT's async layout
// nodes. Every tap on a native UI element flows through its `handleTap`. We
// check the receiver's controller.node._accessibilityIdentifier — if it's the
// native Download button, we short-circuit to our own sheet with a live-read
// from the enclosing YTPlayerViewController. Otherwise we %orig.

@interface ELMTouchCommandPropertiesHandler : NSObject
@end

// External trigger class from YTAGDownload.x. Forward-declared so this file
// compiles without importing that whole header.
@interface YTAGDownloadTrigger : NSObject
+ (void)hijackFromPlayerVC:(id)playerVC fromView:(UIView *)sourceView;
@end

%hook ELMTouchCommandPropertiesHandler

- (void)handleTap {
    // Guard on user toggle — defaults to YES so hijack is on out-of-the-box.
    if (![[YTAGUserDefaults standardUserDefaults] boolForKey:@"hijackYTDownload"]) {
        %orig;
        return;
    }

    @try {
        // sub_179C4 pattern: [self valueForKey:@"_controller"] -> .node -> accessibilityIdentifier
        id controller = [self valueForKey:@"_controller"];
        id node = [controller valueForKey:@"node"];
        id aid = [node valueForKey:@"_accessibilityIdentifier"];
        if ([aid isKindOfClass:[NSString class]] &&
            [(NSString *)aid isEqualToString:@"id.ui.add_to.offline.button"])
        {
            // Walk: node.closestViewController._metadataPanelStateProvider._watchViewController._playerViewController
            id closestVC = [node performSelector:@selector(closestViewController)];
            id panelProvider = [closestVC valueForKey:@"_metadataPanelStateProvider"];
            id watchVC = [panelProvider valueForKey:@"_watchViewController"];
            id playerVC = [watchVC valueForKey:@"_playerViewController"];
            UIView *anchor = [node performSelector:@selector(view)];
            if (playerVC) {
                YTAGLog(@"offline-hijack", @"native Download button tapped — routing to YTAG sheet");
                if ([YTAGDownloadTrigger respondsToSelector:@selector(hijackFromPlayerVC:fromView:)]) {
                    [YTAGDownloadTrigger hijackFromPlayerVC:playerVC fromView:anchor];
                }
                return;  // suppress the native action
            }
            YTAGLog(@"offline-hijack", @"couldn't resolve playerVC — falling through to native");
        }
    } @catch (id ex) {
        YTAGLog(@"offline-hijack", @"exception in handleTap hook: %@ — falling through", ex);
    }
    %orig;
}

%end

%ctor {
    // Register the hijack pref default — ON unless user disables.
    // `offlineProbeDump` defaults OFF — enable it only when we need a fresh
    // method-map dump after a YT version bump. Each dump is ~10k log lines.
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        @"hijackYTDownload": @YES,
        @"offlineProbeDump": @NO,
    }];

    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"offlineProbeDump"]) {
        return;  // hijack hook is still installed; just no method dump.
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        YTAGLog(@"offline-probe", @"=== Premium offline-download class scan ===");
        NSUInteger found = 0;
        for (NSUInteger i = 0; i < kProbedClassCount; i++) {
            if (NSClassFromString(kProbedClassNames[i])) found++;
            YTAGDumpClassMethods(kProbedClassNames[i]);
        }
        YTAGLog(@"offline-probe", @"=== scan complete: %lu/%lu classes found ===",
                (unsigned long)found, (unsigned long)kProbedClassCount);
    });
}
