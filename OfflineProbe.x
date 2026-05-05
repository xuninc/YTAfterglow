// OfflineProbe.x — offline-download compatibility diagnostics and native
// Download button routing.
//
// Two things in one file:
//
// (1) Compatibility diagnostics for the `YTOfflineVideoStreams*` /
//     `YTAppOffline*` class family. When enabled, this records selector metadata
//     for version checks after YouTube updates.
//
// (2) Native Download routing:
//     hook `-[ELMTouchCommandPropertiesHandler handleTap]` and, if the tapped
//     node's `_accessibilityIdentifier` equals `"id.ui.add_to.offline.button"`
//     (YT's stock Download button), intercept and route to our own download
//     sheet. Guarded by a native-routing pref so it's toggleable.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Utils/YTAGLog.h"
#import "Utils/YTAGUserDefaults.h"

// Classes covered by the optional compatibility diagnostics. Ordered
// rough-priority for log readability.
static NSString *const kProbedClassNames[] = {
    // Player-side: these are where our live-read walks, so diagnostics can
    // confirm accessor names after version changes.
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

// ----- Native Download button routing -----------------------------------------
//
// ELMTouchCommandPropertiesHandler is the tap dispatcher for YT's async layout
// nodes. Every tap on a native UI element flows through its `handleTap`. We
// check the receiver's controller.node._accessibilityIdentifier — if it's the
// native Download button, we route to our own sheet with a live-read
// from the enclosing YTPlayerViewController. Otherwise we %orig.

@interface ELMTouchCommandPropertiesHandler : NSObject
@end

// External trigger class from YTAGDownload.x. Forward-declared so this file
// compiles without importing that whole header.
@interface YTAGDownloadTrigger : NSObject
+ (void)routeFromPlayerVC:(id)playerVC fromView:(UIView *)sourceView;
@end

%hook ELMTouchCommandPropertiesHandler

- (void)handleTap {
    // Guard on user toggle — defaults to YES so native routing is on out-of-the-box.
    if (![[YTAGUserDefaults standardUserDefaults] boolForKey:@"nativeDownloadRouting"]) {
        %orig;
        return;
    }

    @try {
        // Touch handler path: [self valueForKey:@"_controller"] -> .node -> accessibilityIdentifier
        id controller = [self valueForKey:@"_controller"];
        id node = [controller valueForKey:@"node"];
        id aid = [node valueForKey:@"_accessibilityIdentifier"];
        if ([aid isKindOfClass:[NSString class]] &&
            [(NSString *)aid isEqualToString:@"id.ui.add_to.offline.button"])
        {
            if ([[YTAGUserDefaults standardUserDefaults] boolForKey:@"noPlayerDownloadButton"]) {
                YTAGLog(@"offline-route", @"native Download button hidden - suppressing tap");
                return;
            }

            // Walk: node.closestViewController._metadataPanelStateProvider._watchViewController._playerViewController
            id closestVC = [node performSelector:@selector(closestViewController)];
            id panelProvider = [closestVC valueForKey:@"_metadataPanelStateProvider"];
            id watchVC = [panelProvider valueForKey:@"_watchViewController"];
            id playerVC = [watchVC valueForKey:@"_playerViewController"];
            UIView *anchor = [node performSelector:@selector(view)];
            if (playerVC) {
                YTAGLog(@"offline-route", @"native Download button tapped — routing to YTAG sheet");
                if ([YTAGDownloadTrigger respondsToSelector:@selector(routeFromPlayerVC:fromView:)]) {
                    [YTAGDownloadTrigger routeFromPlayerVC:playerVC fromView:anchor];
                }
                return;  // suppress the native action
            }
            YTAGLog(@"offline-route", @"couldn't resolve playerVC — falling through to native");
        }
    } @catch (id ex) {
        YTAGLog(@"offline-route", @"exception in handleTap hook: %@ — falling through", ex);
    }
    %orig;
}

%end

%ctor {
    // Register the native routing pref default — ON unless user disables.
    // `offlineProbeDump` defaults OFF; enable it only when we need fresh
    // compatibility diagnostics after a YouTube version bump.
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        @"nativeDownloadRouting": @YES,
        @"offlineProbeDump": @NO,
    }];

    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"offlineProbeDump"]) {
        return;  // native routing is still installed; diagnostics are off.
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        YTAGLog(@"offline-probe", @"=== Premium offline-download diagnostics ===");
        NSUInteger found = 0;
        for (NSUInteger i = 0; i < kProbedClassCount; i++) {
            if (NSClassFromString(kProbedClassNames[i])) found++;
            YTAGDumpClassMethods(kProbedClassNames[i]);
        }
        YTAGLog(@"offline-probe", @"=== diagnostics complete: %lu/%lu classes found ===",
                (unsigned long)found, (unsigned long)kProbedClassCount);
    });
}
