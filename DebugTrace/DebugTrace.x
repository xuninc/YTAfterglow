// AfterglowDebugTrace - debug logging companion.
//
// Ships only YTAGLog + YTAGDebugHUD + hooks that log via %orig.
// Adds a "DebugLog" button to the YT player overlay (via YTVideoOverlay) that
// copies the full log ring buffer to the pasteboard on tap. No settings section.
// Does not modify behavior; it only records selected events for compatibility
// testing.

#import <UIKit/UIKit.h>
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import "Utils/YTAGLog.h"
#import "Utils/YTAGDebugHUD.h"

static NSString *const kTweakID = @"DebugLog";

// --- Keychain / SSO tracing (passive — calls %orig, just logs the result) ----------------

%hook SSOKeychainHelper
+ (NSString *)accessGroup {
    NSString *g = %orig;
    YTAGLogForce(@"keychain", @"SSOKeychainHelper.accessGroup -> %@", g ?: @"(nil)");
    return g;
}
+ (NSString *)sharedAccessGroup {
    NSString *g = %orig;
    YTAGLogForce(@"keychain", @"SSOKeychainHelper.sharedAccessGroup -> %@", g ?: @"(nil)");
    return g;
}
%end

%hook SSOKeychainCore
+ (NSString *)accessGroup {
    NSString *g = %orig;
    YTAGLogForce(@"keychain", @"SSOKeychainCore.accessGroup -> %@", g ?: @"(nil)");
    return g;
}
+ (NSString *)sharedAccessGroup {
    NSString *g = %orig;
    YTAGLogForce(@"keychain", @"SSOKeychainCore.sharedAccessGroup -> %@", g ?: @"(nil)");
    return g;
}
%end

// --- AVPiP tracing ----------------------------------------------------------------------

@interface MLPIPController : NSObject
@end

%hook AVPictureInPictureController
- (instancetype)initWithPlayerLayer:(AVPlayerLayer *)playerLayer {
    AVPictureInPictureController *r = %orig;
    YTAGLogForce(@"avpip", @"init(PlayerLayer=%p) -> %p", playerLayer, r);
    return r;
}
- (instancetype)initWithContentSource:(id)contentSource {
    AVPictureInPictureController *r = %orig;
    YTAGLogForce(@"avpip", @"init(ContentSource=%p) -> %p", contentSource, r);
    return r;
}
- (void)startPictureInPicture {
    YTAGLogForce(@"avpip", @"startPictureInPicture self=%p active=%@ possible=%@",
                 self,
                 self.pictureInPictureActive ? @"YES" : @"NO",
                 [AVPictureInPictureController isPictureInPictureSupported] ? @"YES" : @"NO");
    %orig;
}
- (void)stopPictureInPicture {
    YTAGLogForce(@"avpip", @"stopPictureInPicture self=%p", self);
    %orig;
}
%end

%hook MLPIPController
- (void)setPictureInPictureController:(id)controller {
    YTAGLogForce(@"mlpip", @"setPictureInPictureController: self=%p avpip=%p", self, controller);
    %orig;
}
%end

// --- YTVideoOverlay button — "Copy Log" ---------------------------------------------------

@interface YTSettingsSectionItemManager : NSObject
+ (void)registerTweak:(NSString *)tweakId metadata:(NSDictionary *)metadata;
@end

@interface YTToastResponderEvent : NSObject
+ (instancetype)eventWithMessage:(NSString *)message firstResponder:(id)responder;
- (void)send;
@end

@class YTQTMButton;
@interface YTMainAppControlsOverlayView : UIView
@property (retain, nonatomic) NSMutableDictionary<NSString *, YTQTMButton *> *overlayButtons;
@end

@interface YTInlinePlayerBarContainerView : UIView
@property (retain, nonatomic) NSMutableDictionary<NSString *, YTQTMButton *> *overlayButtons;
@end

static UIImage *copyIcon(void) {
    static UIImage *img;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (@available(iOS 13.0, *)) {
            UIImage *base = [UIImage systemImageNamed:@"doc.on.clipboard"];
            // Scale to overlay-button standard ~24pt
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightRegular];
            img = [base imageByApplyingSymbolConfiguration:cfg] ?: base;
        }
    });
    return img;
}

static void copyLogToPasteboard(UIView *fromView) {
    NSArray<NSString *> *entries = YTAGLogRecentEntries();
    NSString *body = entries.count ? [entries componentsJoinedByString:@"\n"] : @"(empty log ring buffer)";
    [UIPasteboard generalPasteboard].string = body;
    YTAGLogForce(@"debugtrace", @"copied %lu log lines (%lu chars) to pasteboard",
                 (unsigned long)entries.count, (unsigned long)body.length);
    Class toast = NSClassFromString(@"YTToastResponderEvent");
    if (toast && fromView) {
        id event = [toast eventWithMessage:@"Debug log copied" firstResponder:fromView];
        [event send];
    }
}

%hook YTMainAppControlsOverlayView
- (UIImage *)buttonImage:(NSString *)tweakId {
    if ([tweakId isEqualToString:kTweakID]) return copyIcon();
    return %orig;
}
%new(v@:@)
- (void)didPressCopyLog:(id)arg {
    copyLogToPasteboard(self);
}
%end

%hook YTInlinePlayerBarContainerView
- (UIImage *)buttonImage:(NSString *)tweakId {
    if ([tweakId isEqualToString:kTweakID]) return copyIcon();
    return %orig;
}
%new(v@:@)
- (void)didPressCopyLog:(id)arg {
    copyLogToPasteboard(self);
}
%end

// --- Constructor -------------------------------------------------------------------------

%ctor {
    NSString *receiptPath = [[NSBundle mainBundle] appStoreReceiptURL].path;
    BOOL isAppStoreApp = [[NSFileManager defaultManager] fileExistsAtPath:receiptPath];
    YTAGLogForce(@"debugtrace", @"ctor: bundle=%@ exe=%@ isAppStore=%@",
                 [[NSBundle mainBundle] bundleIdentifier],
                 [[NSBundle mainBundle] executablePath].lastPathComponent,
                 isAppStoreApp ? @"YES" : @"NO");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // Show HUD always — debug tweak, you installed it to see logs on-device
        [[YTAGDebugHUD sharedHUD] show];

        // Register the "Copy Log" button with YTVideoOverlay
        Class mgr = NSClassFromString(@"YTSettingsSectionItemManager");
        if ([mgr respondsToSelector:@selector(registerTweak:metadata:)]) {
            [mgr registerTweak:kTweakID metadata:@{
                @"accessibilityLabel": @"Copy Log",
                @"selector": @"didPressCopyLog:",
            }];
            YTAGLogForce(@"debugtrace", @"registered overlay button via YTVideoOverlay");
        } else {
            YTAGLogForce(@"debugtrace", @"YTVideoOverlay not present — button unavailable, use Console.app to read logs");
        }
    });
}
