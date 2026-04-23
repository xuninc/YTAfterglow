// YTAGDownload.x — overlay action-row integration for YouTube's player.
//
// Captures the currently-playing videoID via a hook on YTIPlayerResponse, and
// adds a horizontal stack of small YTQTMButtons (download / mute / lock) just
// below YouTube's own top controls (cast / CC / settings). The stack is a child
// of YTMainAppVideoPlayerOverlayView so it inherits the overlay's fade-in/out
// with all the other player controls.
//
// Pattern mirrors YTLite's `ytlButtons` stack (decompiled from YTLite.dylib.c
// lines 342470–342870, helper `+[YTLHelper createOverlayButton:...]` at
// line 390826). Each button is a `[YTQTMButton iconButton]` sized 24×36 with
// circular touch feedback — that's what makes them match YT's native buttons.
//
// Download tap -> presents YTAGDownloadActionSheetViewController (tile grid).
// Mute tap   -> toggles YTSingleVideoController.setMuted: on the player's active video.
// Lock tap   -> activates YouTube's native lock-mode via lockModeStateEntityController.
// All three are individually toggleable from YTAfterglow's Player → Overlay settings.

#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Utils/YTAGLog.h"
#import "Utils/YTAGURLExtractor.h"
#import "Utils/YTAGFormatSelector.h"
#import "Utils/YTAGDownloadManager.h"
#import "Utils/YTAGUserDefaults.h"
#import "UI/YTAGDownloadActionSheetViewController.h"

// Exposed from ColorMode.x. Returns the decoded UIColor for one of the
// `theme_*` user-default keys, or nil if unset. Used for overlay-button tint.
extern UIColor *themeColor(NSString *key);

// --- YT classes we touch, forward-declared so this file compiles without full headers ---

@class YTIVideoDetails;
@interface YTIPlayerResponse : NSObject
@property (nonatomic, strong, readwrite) YTIVideoDetails *videoDetails;
@end
@interface YTIVideoDetails : NSObject
@property (nonatomic, copy, readwrite) NSString *videoId;
@end

// `YTMainAppControlsOverlayView` is the overlay container for cast/CC/settings —
// and it's the view that fades in/out with player chrome. Attach our button stack
// here so it inherits the auto-hide/show behavior of the other top-row buttons.
// `topControlsAccessibilityContainerView` is the hidden inner container holding
// cast/CC/settings themselves; not in the public header, forward-declared here.
@interface YTMainAppControlsOverlayView : UIView
- (UIView *)topControlsAccessibilityContainerView;
@end
@class YTPlayerViewController;
@interface YTSingleVideoController : NSObject
- (BOOL)isMuted;
- (void)setMuted:(BOOL)muted;
@end
@interface YTPlayerViewController : UIViewController
@property (nonatomic, readonly) NSString *contentVideoID;
- (YTSingleVideoController *)activeVideo;
@end
// YouTube's button class — gives us correct size/haptic/tint out of the box.
@interface YTQTMButton : UIControl
+ (instancetype)iconButton;
- (void)enableNewTouchFeedback;
- (void)setImage:(UIImage *)image forState:(UIControlState)state;
- (UIView *)touchFeedbackView;
@end
@interface YTQTMTouchFeedbackView : UIView
- (void)setForceCircularTouchFeedback:(BOOL)v;
- (void)setTouchFeedbackInsets:(UIEdgeInsets)insets;
- (void)setCustomTouchFeedbackColor:(UIColor *)color;
@end

// Responder-chain helper category added via %hook below.
@interface UIView (YTAGResponderChain)
- (UIViewController *)ytag_closestViewController;
@end

// --- Trigger action class (standard ObjC, no Logos directives) ---

@interface YTAGDownloadTrigger : NSObject
+ (void)handleDownloadTap:(UIButton *)sender;
+ (void)handleMuteTap:(UIButton *)sender;
+ (void)handleLockTap:(UIButton *)sender;
// Entry point for OfflineProbe.x's native-Download-button hijack. Resolves
// formats via live-read off playerVC and presents our action sheet.
+ (void)hijackFromPlayerVC:(id)playerVC fromView:(UIView *)sourceView;
@end

// --- State: current videoID cache ---

static NSString *gCurrentVideoID = nil;

static NSString *YTAGCurrentVideoID(void) {
    return gCurrentVideoID;
}

static const NSInteger kYTAGButtonStackTag = 998877;  // stack view tag
static void *kYTAGStackKey = &kYTAGStackKey;           // assoc object key

// --- File-scope helper: format a byte count for the chip ("2.4 MB" / "780 KB") ---

static NSString *YTAGFormatBytesShort(long long bytes) {
    if (bytes <= 0) return nil;
    double mb = (double)bytes / (1024.0 * 1024.0);
    if (mb >= 1.0) return [NSString stringWithFormat:@"%.1f MB", mb];
    double kb = (double)bytes / 1024.0;
    return [NSString stringWithFormat:@"%.0f KB", kb];
}

// Factory: 36×36 YTQTMButton iconButton, white tint. No forced-circular touch
// feedback — the {0,-6,0,-6} insets we used before expanded the feedback circle
// beyond the button bounds and made each icon look 36pt wide instead of 24,
// overlapping its neighbors. Matches the visual size of YT's own cast / CC /
// settings buttons in the same row.
//
// `iconType` (when > 0): populate YT's buttonRenderer so the button renders the
// matching YTIIcon asset (e.g. 594 = native download icon). Falls back to the
// supplied `fallbackImage` if the renderer path doesn't produce visible art.
static YTQTMButton *YTAGMakeOverlayButton(NSString *accessibilityLabel,
                                           NSInteger iconType,
                                           UIImage *fallbackImage,
                                           id target,
                                           SEL selector) {
    Class cls = NSClassFromString(@"YTQTMButton");
    YTQTMButton *btn = cls ? [cls performSelector:@selector(iconButton)] : nil;
    if (!btn) return nil;
    btn.accessibilityLabel = accessibilityLabel;
    // Honor the user's Afterglow theme. `theme_overlayButtons` is the key that
    // covers the rest of the player overlay's top-row button tint — keeping ours
    // on the same key means our buttons match cast/CC/settings under any preset.
    // Falls back to white when the user hasn't picked a preset.
    btn.tintColor = themeColor(@"theme_overlayButtons") ?: [UIColor whiteColor];
    btn.translatesAutoresizingMaskIntoConstraints = NO;

    // Preferred path: wire up a native YT icon via iconType. YT's button rendering
    // machinery converts icon.iconType -> image at layout time.
    BOOL wiredNativeIcon = NO;
    if (iconType > 0) {
        Class iconCls = NSClassFromString(@"YTIIcon");
        Class rendererCls = NSClassFromString(@"YTIButtonRenderer");
        if (iconCls && rendererCls) {
            @try {
                id icon = [[iconCls alloc] init];
                [icon setValue:@(iconType) forKey:@"iconType"];
                id renderer = [[rendererCls alloc] init];
                [renderer setValue:icon forKey:@"icon"];
                [btn setValue:renderer forKey:@"buttonRenderer"];
                wiredNativeIcon = YES;
            } @catch (id ex) {
                YTAGLog(@"icon", @"renderer-set failed for iconType=%ld: %@", (long)iconType, ex);
            }
        }
    }

    // Always install the fallback image — if the renderer path fails or YT doesn't
    // render it at layout time (invisible), the SF Symbol shows instead.
    if (fallbackImage) {
        [btn setImage:[fallbackImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
             forState:UIControlStateNormal];
    }

    [btn addTarget:target action:selector forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [btn.widthAnchor  constraintEqualToConstant:36.0],
        [btn.heightAnchor constraintEqualToConstant:36.0],
    ]];
    if (wiredNativeIcon) {
        YTAGLog(@"icon", @"wired iconType=%ld", (long)iconType);
    }
    return btn;
}

static UIImage *YTAGSymbol(NSString *name, CGFloat pointSize) {
    if (@available(iOS 13.0, *)) {
        UIImage *img = [UIImage systemImageNamed:name];
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:UIImageSymbolWeightRegular];
        return [img imageByApplyingSymbolConfiguration:cfg] ?: img;
    }
    return nil;
}

// --- Hooks ---

%hook YTIPlayerResponse

- (void)setVideoDetails:(YTIVideoDetails *)details {
    %orig;
    if ([details respondsToSelector:@selector(videoId)] && details.videoId.length > 0) {
        gCurrentVideoID = [details.videoId copy];
        YTAGLog(@"dl-trigger", @"captured videoID=%@", gCurrentVideoID);
    }
}

%end

%hook UIView

%new(@@:)
- (UIViewController *)ytag_closestViewController {
    UIResponder *r = self.nextResponder;
    while (r) {
        if ([r isKindOfClass:[UIViewController class]]) return (UIViewController *)r;
        r = r.nextResponder;
    }
    return nil;
}

%end

%hook YTMainAppControlsOverlayView

- (void)layoutSubviews {
    %orig;

    // Install once per overlay. Tag-check prevents re-add on each layout pass.
    if ([self viewWithTag:kYTAGButtonStackTag]) return;

    YTAGUserDefaults *prefs = [YTAGUserDefaults standardUserDefaults];
    BOOL showMute     = [prefs boolForKey:@"muteButton"];
    BOOL showLock     = [prefs boolForKey:@"lockButton"];
    BOOL showDownload = [prefs boolForKey:@"downloadButton"];
    if (!showMute && !showLock && !showDownload) return;

    UIView *topContainer = nil;
    if ([self respondsToSelector:@selector(topControlsAccessibilityContainerView)]) {
        topContainer = [self topControlsAccessibilityContainerView];
    }
    // KVC fallback — the ivar name doesn't always match the getter.
    if (!topContainer) {
        @try { topContainer = [self valueForKey:@"_topControlsAccessibilityContainerView"]; }
        @catch (id ex) {}
    }
    if (!topContainer) return;  // retry next layout pass when the hierarchy is ready

    // Stack layout — exact copy of YTLite's `ytlButtons` config from decomp (lines 342457-342476):
    //   setAxis:0             (NSLayoutConstraintAxisHorizontal)
    //   setDistribution:1     (UIStackViewDistributionFillEqually)
    //   setAlignment:3        (UIStackViewAlignmentCenter)
    //   setSpacing:10.0
    //   setTranslatesAutoresizingMaskIntoConstraints:0
    //   setTag:998
    //
    // Parented to `self` (YTMainAppControlsOverlayView) — YTLite adds to self too
    // (decomp line 342768). Parenting to `_topControlsAccessibilityContainerView`
    // breaks hit-testing: the container only hit-tests within its own bounds, so
    // a stack rendered below the container (via clipsToBounds=NO) is visible but
    // not tappable — taps fall through to the video. Anchor to topContainer's
    // bottomAnchor for position but keep self as the actual parent.
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 10.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.tag = kYTAGButtonStackTag;
    [self addSubview:stack];

    // Read initial mute / lock state off the player so the icons start in sync.
    // Use KVC on the overlay's _eventsDelegate to reach the YTMainAppVideoPlayerOverlayViewController,
    // mirroring YouMute's approach (Overlay/YouMute/Tweak.x:20-22).
    BOOL startMuted = NO;
    BOOL startLocked = NO;
    @try {
        id events = [self valueForKey:@"_eventsDelegate"];
        id video = [events valueForKey:@"_currentSingleVideoObservable"];
        if ([video respondsToSelector:@selector(isMuted)]) {
            startMuted = ((BOOL (*)(id, SEL))objc_msgSend)(video, @selector(isMuted));
        }
        if ([events respondsToSelector:@selector(lockModeStateEntityController)]) {
            id lc = ((id (*)(id, SEL))objc_msgSend)(events, @selector(lockModeStateEntityController));
            NSNumber *v = [lc valueForKey:@"lockModeActive"];
            if ([v respondsToSelector:@selector(boolValue)]) startLocked = [v boolValue];
        }
    } @catch (NSException *e) {}

    if (showMute) {
        YTQTMButton *mute = YTAGMakeOverlayButton(
            startMuted ? @"Unmute" : @"Mute",
            572,  // YT iconType 572 — native mute/volume icon
            YTAGSymbol(startMuted ? @"speaker.slash.fill" : @"speaker.wave.2.fill", 22.0),
            [YTAGDownloadTrigger class],
            @selector(handleMuteTap:));
        if (mute) [stack addArrangedSubview:mute];
    }
    if (showLock) {
        YTQTMButton *lock = YTAGMakeOverlayButton(
            startLocked ? @"Unlock controls" : @"Lock controls",
            81,  // YT iconType 81 — native lock icon
            YTAGSymbol(startLocked ? @"lock.fill" : @"lock.open.fill", 22.0),
            [YTAGDownloadTrigger class],
            @selector(handleLockTap:));
        if (lock) [stack addArrangedSubview:lock];
    }
    if (showDownload) {
        YTQTMButton *download = YTAGMakeOverlayButton(
            @"Download",
            594,  // YT iconType 594 — native download icon
            YTAGSymbol(@"arrow.down.to.line", 22.0),
            [YTAGDownloadTrigger class],
            @selector(handleDownloadTap:));
        if (download) [stack addArrangedSubview:download];
    }

    // Position the stack as a second row immediately below topContainer's own
    // layout, right-aligned. topContainer has clipsToBounds=NO so the overflow
    // row is visible.
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor      constraintEqualToAnchor:topContainer.bottomAnchor constant:4],
        [stack.trailingAnchor constraintEqualToAnchor:topContainer.trailingAnchor],
    ]];

    // Keep a strong reference so the stack doesn't get released as topContainer
    // rebuilds its children. Associated on `self` because topContainer may be
    // recreated but `self` (YTMainAppControlsOverlayView) persists for the
    // lifetime of the player session.
    objc_setAssociatedObject(self, kYTAGStackKey, stack, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    YTAGLog(@"overlay", @"installed stack w=%@ in topContainer<%@>",
            @(stack.arrangedSubviews.count), NSStringFromClass([topContainer class]));
}

// Belt-and-suspenders for fade: the stack is already parented to topContainer
// so its alpha *should* cascade automatically, but some YT builds manipulate
// the inner controls' alpha directly instead of the container's. Explicitly
// mirror visibility here. Matches YTVideoOverlay/Tweak.x:243 exactly.
- (void)setTopOverlayVisible:(BOOL)visible isAutonavCanceledState:(BOOL)canceledState {
    UIStackView *stack = (UIStackView *)objc_getAssociatedObject(self, kYTAGStackKey);
    if (stack) {
        stack.alpha = (canceledState || !visible) ? 0.0 : 1.0;
    }
    YTAGLog(@"overlay", @"setTopOverlayVisible:%d canceled:%d stack=%d",
            visible, canceledState, stack != nil);
    %orig;
}

%end

// --- Fallback videoID capture ---
// The YTIPlayerResponse hook above is our primary path, but on some builds the
// setter name has drifted. Second capture path: hook YTPlayerViewController's
// video-load point. Whichever fires first wins; the most recent value sticks.
%hook YTPlayerViewController

- (void)loadWithPlayerTransition:(id)transition playbackConfig:(id)config {
    %orig;
    if ([self respondsToSelector:@selector(contentVideoID)]) {
        NSString *vid = [self contentVideoID];
        if (vid.length > 0) {
            gCurrentVideoID = [vid copy];
            YTAGLog(@"dl-trigger", @"captured videoID via YTPlayerViewController.contentVideoID=%@", vid);
        }
    }
}

%end

// --- Trigger logic (standard ObjC @implementation outside any %hook) ---

@interface YTAGDownloadTrigger ()
+ (void)presentActionSheetWithResult:(YTAGExtractionResult *)result
                            videoID:(NSString *)videoID
                      presentingVC:(UIViewController *)presentingVC
                         fromView:(UIView *)sourceView;
+ (void)presentQualityPickerWithResult:(YTAGExtractionResult *)result
                              videoID:(NSString *)videoID
                         presentingVC:(UIViewController *)presentingVC
                             fromView:(UIView *)sourceView;
+ (void)startDownloadWithVideoID:(NSString *)videoID
                            pair:(YTAGFormatPair *)pair
                     resultTitle:(NSString *)title
                        fromView:(UIView *)sourceView;
+ (void)showComingSoon:(NSString *)feature on:(UIViewController *)presentingVC;
+ (void)showAlertWithTitle:(NSString *)title message:(NSString *)message on:(UIViewController *)vc;
+ (void)copyInfoForResult:(YTAGExtractionResult *)result on:(UIViewController *)presentingVC;
+ (void)saveThumbnailForResult:(YTAGExtractionResult *)result on:(UIViewController *)presentingVC;
+ (void)openInExternalPlayerForResult:(YTAGExtractionResult *)result
                        presentingVC:(UIViewController *)presentingVC
                            fromView:(UIView *)sourceView;
+ (void)downloadCaptionsForResult:(YTAGExtractionResult *)result
                     presentingVC:(UIViewController *)presentingVC
                         fromView:(UIView *)sourceView;
@end

@implementation YTAGDownloadTrigger

// Find YTMainAppControlsOverlayView ancestor in the view hierarchy.
static UIView *YTAGControlsOverlayViewFor(UIView *sender) {
    Class controlsClass = NSClassFromString(@"YTMainAppControlsOverlayView");
    UIView *v = sender;
    while (v) {
        if (controlsClass && [v isKindOfClass:controlsClass]) return v;
        v = v.superview;
    }
    return nil;
}

// Resolve YTMainAppVideoPlayerOverlayViewController. We parent our buttons inside
// `_topControlsAccessibilityContainerView`, whose superview is YTMainAppControlsOverlayView.
// YTMainAppControlsOverlayView exposes `_eventsDelegate` (the overlay VC).
static id YTAGOverlayVCFromSender(UIView *sender) {
    UIView *controls = YTAGControlsOverlayViewFor(sender);
    if (!controls) {
        YTAGLog(@"vc-resolve", @"no YTMainAppControlsOverlayView in view hierarchy from %@",
                NSStringFromClass([sender class]));
        return nil;
    }
    id vc = nil;
    @try { vc = [controls valueForKey:@"_eventsDelegate"]; }
    @catch (id ex) { YTAGLog(@"vc-resolve", @"_eventsDelegate KVC threw: %@", ex); }
    if (!vc) {
        @try { vc = [controls valueForKey:@"eventsDelegate"]; }
        @catch (id ex) {}
    }
    YTAGLog(@"vc-resolve", @"overlay VC = %@", NSStringFromClass([vc class]) ?: @"<nil>");
    return vc;
}

// Resolve YTPlayerViewController — `parentViewController` on the overlay VC.
static id YTAGPlayerVCFromSender(UIView *sender) {
    id overlayVC = YTAGOverlayVCFromSender(sender);
    if (!overlayVC) return nil;
    id pvc = nil;
    if ([overlayVC respondsToSelector:@selector(parentViewController)]) {
        pvc = [overlayVC performSelector:@selector(parentViewController)];
    }
    YTAGLog(@"vc-resolve", @"player VC = %@", NSStringFromClass([pvc class]) ?: @"<nil>");
    return pvc;
}

+ (void)handleMuteTap:(UIButton *)sender {
    // Mirrors YTLite's sub_16A60 at line 343126-343189.
    id pvc = YTAGPlayerVCFromSender(sender);
    if (!pvc || ![pvc respondsToSelector:@selector(activeVideo)]) {
        YTAGLog(@"overlay-mute", @"no player VC from sender");
        return;
    }
    id video = ((id (*)(id, SEL))objc_msgSend)(pvc, @selector(activeVideo));
    if (!video || ![video respondsToSelector:@selector(setMuted:)]) {
        YTAGLog(@"overlay-mute", @"activeVideo missing setMuted:");
        return;
    }
    BOOL wasMuted = [video respondsToSelector:@selector(isMuted)]
        ? ((BOOL (*)(id, SEL))objc_msgSend)(video, @selector(isMuted))
        : NO;
    BOOL newMuted = !wasMuted;
    // YouMute (if integrated) hooks -[YTSingleVideoController setMuted:] and substitutes
    // the YouMuteKeepMuted default. Write that FIRST so YouMute's hook passes through the
    // intended value. Harmless if YouMute isn't loaded.
    [[NSUserDefaults standardUserDefaults] setBool:newMuted forKey:@"YouMuteKeepMuted"];
    ((void (*)(id, SEL, BOOL))objc_msgSend)(video, @selector(setMuted:), newMuted);

    UIImage *icon = YTAGSymbol(newMuted ? @"speaker.slash.fill" : @"speaker.wave.2.fill", 22.0);
    if (icon) {
        [sender setImage:[icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                forState:UIControlStateNormal];
    }
    sender.accessibilityLabel = newMuted ? @"Unmute" : @"Mute";
    YTAGLog(@"overlay-mute", @"muted %@ -> %@", wasMuted ? @"YES" : @"NO", newMuted ? @"YES" : @"NO");
}

+ (void)handleLockTap:(UIButton *)sender {
    // Mirrors YTLite's sub_16C18 at line 343196-343228 verbatim.
    // YTLite doesn't toggle — it only engages lock. YT's own lock-mode UI dismisses
    // via gesture/timeout. We follow that behavior.
    id overlayVC = YTAGOverlayVCFromSender(sender);
    if (!overlayVC) {
        YTAGLog(@"overlay-lock", @"no overlay VC from sender");
        return;
    }
    if (![overlayVC respondsToSelector:@selector(lockModeStateEntityController)]) {
        YTAGLog(@"overlay-lock", @"overlay VC (%@) has no lockModeStateEntityController",
                NSStringFromClass([overlayVC class]));
        return;
    }
    id lockCtl = ((id (*)(id, SEL))objc_msgSend)(overlayVC, @selector(lockModeStateEntityController));
    if (!lockCtl) {
        YTAGLog(@"overlay-lock", @"lockModeStateEntityController returned nil");
        return;
    }
    // Exact YTLite sequence:
    //   objc_msgSend(v2, "lockModeDidRequestShowFullscreen");
    //   v6 = objc_msgSend(v2, "lockModeStateEntityController");
    //   objc_msgSend(v6, "setLockModeActive:", 1);
    if ([overlayVC respondsToSelector:@selector(lockModeDidRequestShowFullscreen)]) {
        ((void (*)(id, SEL))objc_msgSend)(overlayVC, @selector(lockModeDidRequestShowFullscreen));
    }
    // Re-fetch exactly like the decomp (could be a fresh instance after the fullscreen trigger).
    lockCtl = ((id (*)(id, SEL))objc_msgSend)(overlayVC, @selector(lockModeStateEntityController));
    if (lockCtl && [lockCtl respondsToSelector:@selector(setLockModeActive:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(lockCtl, @selector(setLockModeActive:), YES);
    }
    YTAGLog(@"overlay-lock", @"lock mode engaged (YT dismisses via gesture)");
}

+ (void)handleDownloadTap:(UIButton *)sender {
    UIViewController *presentingVC = [sender.superview ytag_closestViewController];
    NSString *videoID = YTAGCurrentVideoID();

    // Dump the superview chain + responder chain for diagnostics so we can see
    // exactly where the button lives when the videoID resolution fails.
    YTAGLog(@"dl-trigger", @"=== download tap diagnostic ===");
    YTAGLog(@"dl-trigger", @"cached videoID=%@", videoID ?: @"<nil>");
    YTAGLog(@"dl-trigger", @"sender class=%@", NSStringFromClass([sender class]));
    UIView *walk = sender;
    int depth = 0;
    while (walk && depth < 12) {
        YTAGLog(@"dl-trigger", @"  superview[%d] = %@", depth, NSStringFromClass([walk class]));
        walk = walk.superview;
        depth++;
    }
    UIResponder *r = sender.nextResponder;
    int rd = 0;
    while (r && rd < 12) {
        YTAGLog(@"dl-trigger", @"  nextResponder[%d] = %@", rd, NSStringFromClass([r class]));
        r = r.nextResponder;
        rd++;
    }

    // Primary live-read path: reach YTPlayerViewController and read contentVideoID.
    // Doesn't require any prior hook to have fired.
    if (videoID.length == 0) {
        id pvc = YTAGPlayerVCFromSender(sender);
        if (pvc && [pvc respondsToSelector:@selector(contentVideoID)]) {
            NSString *vid = [pvc performSelector:@selector(contentVideoID)];
            YTAGLog(@"dl-trigger", @"contentVideoID live-read = %@", vid ?: @"<nil>");
            if (vid.length > 0) {
                videoID = vid;
                gCurrentVideoID = [vid copy];
            }
        } else {
            YTAGLog(@"dl-trigger", @"pvc=%@ responds_contentVideoID=%d",
                    NSStringFromClass([pvc class]) ?: @"<nil>",
                    [pvc respondsToSelector:@selector(contentVideoID)]);
        }
    }

    // Last-ditch: walk the button's responder chain for anything exposing contentVideoID.
    if (videoID.length == 0) {
        UIResponder *r = sender;
        while (r && videoID.length == 0) {
            if ([r respondsToSelector:@selector(contentVideoID)]) {
                NSString *vid = [(id)r performSelector:@selector(contentVideoID)];
                if (vid.length > 0) {
                    videoID = vid;
                    gCurrentVideoID = [vid copy];
                    YTAGLog(@"dl-trigger", @"captured videoID via responder chain=%@", vid);
                }
            }
            r = r.nextResponder;
        }
    }

    if (videoID.length == 0) {
        [self showAlertWithTitle:@"No video"
                         message:@"Couldn't identify the current video. Try tapping the player first, then Download."
                              on:presentingVC];
        return;
    }
    if (!presentingVC) {
        YTAGLog(@"dl-trigger", @"no presenting VC found");
        return;
    }

    YTAGLog(@"dl-trigger", @"button tap, videoID=%@", videoID);

    // PRIMARY: live-read from the YTPlayerViewController's own in-memory
    // `playerResponse.playerData.streamingData.adaptiveFormatsArray`. No network,
    // no client spoofing — YT has already resolved these URLs to play the video.
    // Exactly what YTLite does in sub_361536 at decomp line 361570-361573.
    id pvcForLiveRead = YTAGPlayerVCFromSender(sender);
    YTAGExtractionResult *liveResult = [YTAGURLExtractor extractFromPlayerVC:pvcForLiveRead];
    if (liveResult && liveResult.formats.count > 0) {
        YTAGLog(@"dl-trigger", @"using live-read result (%lu formats)",
                (unsigned long)liveResult.formats.count);
        [self presentActionSheetWithResult:liveResult
                                   videoID:videoID
                              presentingVC:presentingVC
                                  fromView:sender];
        return;
    }

    // FALLBACK: InnerTube network fetch — only if live-read found nothing (rare,
    // would mean the video hasn't finished loading). Shows a transient "Loading…"
    // because this takes a full round trip.
    YTAGLog(@"dl-trigger", @"live-read empty, falling back to InnerTube");
    UIAlertController *loading = [UIAlertController
        alertControllerWithTitle:nil
                         message:@"Loading…"
                  preferredStyle:UIAlertControllerStyleAlert];
    [presentingVC presentViewController:loading animated:YES completion:nil];

    [YTAGURLExtractor extractVideoID:videoID
                            clientID:YTAGClientIDiOS
                          completion:^(YTAGExtractionResult *result, NSError *error) {
        [loading dismissViewControllerAnimated:YES completion:^{
            if (error || !result) {
                [self showAlertWithTitle:@"Couldn't load video"
                                 message:error.localizedDescription ?: @"Unknown error"
                                      on:presentingVC];
                return;
            }
            [self presentActionSheetWithResult:result
                                       videoID:videoID
                                  presentingVC:presentingVC
                                      fromView:sender];
        }];
    }];
}

+ (void)presentActionSheetWithResult:(YTAGExtractionResult *)result
                             videoID:(NSString *)videoID
                        presentingVC:(UIViewController *)presentingVC
                            fromView:(UIView *)sourceView
{
    YTAGDownloadActionSheetViewController *sheet = [YTAGDownloadActionSheetViewController new];
    sheet.channelName = result.author;
    sheet.videoTitle = result.title;

    // Audio size chip: compute from the preferred audio format.
    YTAGFormatPair *audioPair = [YTAGFormatSelector
        selectAudioPairFromResult:result
                     audioQuality:YTAGAudioQualityStandard];
    sheet.audioSizeChip = audioPair ? YTAGFormatBytesShort(audioPair.audioFormat.contentLength) : nil;

    __weak UIViewController *weakPresenting = presentingVC;
    sheet.onAction = ^(YTAGDownloadAction action) {
        UIViewController *p = weakPresenting;
        if (!p) return;

        switch (action) {
            case YTAGDownloadActionDownloadVideo:
                [YTAGDownloadTrigger presentQualityPickerWithResult:result
                                                            videoID:videoID
                                                       presentingVC:p
                                                           fromView:sourceView];
                break;

            case YTAGDownloadActionDownloadAudio:
                if (audioPair) {
                    YTAGFormatPair *pair = [YTAGFormatPair new];
                    pair.audioFormat = audioPair.audioFormat;   // videoFormat nil = audio-only
                    [YTAGDownloadTrigger startDownloadWithVideoID:videoID
                                                             pair:pair
                                                      resultTitle:result.title
                                                         fromView:sourceView];
                } else {
                    [YTAGDownloadTrigger showAlertWithTitle:@"No audio available"
                                                    message:@"This video doesn't expose a downloadable audio track."
                                                         on:p];
                }
                break;

            case YTAGDownloadActionDownloadCaptions:
                [YTAGDownloadTrigger downloadCaptionsForResult:result
                                                  presentingVC:p
                                                      fromView:sourceView];
                break;

            case YTAGDownloadActionSaveImage:
                [YTAGDownloadTrigger saveThumbnailForResult:result on:p];
                break;

            case YTAGDownloadActionCopyInformation:
                [YTAGDownloadTrigger copyInfoForResult:result on:p];
                break;

            case YTAGDownloadActionPlayInExternalPlayer:
                [YTAGDownloadTrigger openInExternalPlayerForResult:result
                                                      presentingVC:p
                                                          fromView:sourceView];
                break;
        }
    };

    [presentingVC presentViewController:sheet animated:YES completion:nil];
}

+ (void)presentQualityPickerWithResult:(YTAGExtractionResult *)result
                               videoID:(NSString *)videoID
                          presentingVC:(UIViewController *)presentingVC
                              fromView:(UIView *)sourceView
{
    NSArray<YTAGFormatPair *> *pairs = [YTAGFormatSelector
        allOfferablePairsFromResult:result
                       audioQuality:YTAGAudioQualityStandard];

    // Filter to video entries only (the "all offerable" includes an audio-only
    // trailer). We already have a dedicated Audio tile for that case.
    NSMutableArray<YTAGFormatPair *> *videoPairs = [NSMutableArray array];
    for (YTAGFormatPair *p in pairs) {
        if (p.videoFormat != nil) [videoPairs addObject:p];
    }

    if (videoPairs.count == 0) {
        [self showAlertWithTitle:@"No downloadable formats"
                         message:@"This video has no streams we can download."
                              on:presentingVC];
        return;
    }

    UIAlertController *picker = [UIAlertController
        alertControllerWithTitle:result.title
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];

    for (YTAGFormatPair *pair in videoPairs) {
        [picker addAction:[UIAlertAction
            actionWithTitle:pair.descriptorString
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *_) {
            [YTAGDownloadTrigger startDownloadWithVideoID:videoID
                                                     pair:pair
                                              resultTitle:result.title
                                                 fromView:sourceView];
        }]];
    }
    [picker addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    picker.popoverPresentationController.sourceView = sourceView;
    picker.popoverPresentationController.sourceRect = sourceView.bounds;

    [presentingVC presentViewController:picker animated:YES completion:nil];
}

+ (void)startDownloadWithVideoID:(NSString *)videoID
                            pair:(YTAGFormatPair *)pair
                     resultTitle:(NSString *)title
                        fromView:(UIView *)sourceView
{
    UIViewController *presentingVC = [sourceView ytag_closestViewController];
    if (!presentingVC) return;

    YTAGDownloadRequest *req = [YTAGDownloadRequest new];
    req.videoID = videoID;
    req.titleOverride = title;
    req.pair = pair;
    req.postAction = YTAGPostDownloadActionAsk;

    [[YTAGDownloadManager sharedManager]
          startDownload:req
         presentingFrom:presentingVC
             completion:^(NSURL *outputFileURL, NSError *error) {
        if (error) {
            YTAGLog(@"dl-trigger", @"download error: %@", error.localizedDescription);
        } else {
            YTAGLog(@"dl-trigger", @"download ok: %@", outputFileURL.lastPathComponent);
        }
    }];
}

+ (void)showComingSoon:(NSString *)feature on:(UIViewController *)presentingVC {
    [self showAlertWithTitle:feature
                     message:@"Coming soon."
                          on:presentingVC];
}

+ (void)hijackFromPlayerVC:(id)playerVC fromView:(UIView *)sourceView {
    UIViewController *presentingVC = [sourceView ytag_closestViewController];
    if (!presentingVC) {
        YTAGLog(@"dl-hijack", @"no presenting VC — cannot show sheet");
        return;
    }
    YTAGExtractionResult *liveResult = [YTAGURLExtractor extractFromPlayerVC:playerVC];
    if (liveResult && liveResult.formats.count > 0) {
        YTAGLog(@"dl-hijack", @"live-read OK (%lu formats), videoID=%@",
                (unsigned long)liveResult.formats.count, liveResult.videoID);
        [self presentActionSheetWithResult:liveResult
                                   videoID:liveResult.videoID
                              presentingVC:presentingVC
                                  fromView:sourceView];
        return;
    }
    NSString *vid = nil;
    if ([playerVC respondsToSelector:@selector(contentVideoID)]) {
        vid = [playerVC performSelector:@selector(contentVideoID)];
    }
    if (vid.length == 0) {
        [self showAlertWithTitle:@"No video"
                         message:@"Couldn't identify the current video."
                              on:presentingVC];
        return;
    }
    YTAGLog(@"dl-hijack", @"live-read empty — falling back to InnerTube for videoID=%@", vid);
    UIAlertController *loading = [UIAlertController
        alertControllerWithTitle:nil
                         message:@"Loading…"
                  preferredStyle:UIAlertControllerStyleAlert];
    [presentingVC presentViewController:loading animated:YES completion:nil];
    [YTAGURLExtractor extractVideoID:vid
                            clientID:YTAGClientIDiOS
                          completion:^(YTAGExtractionResult *result, NSError *error) {
        [loading dismissViewControllerAnimated:YES completion:^{
            if (error || !result) {
                [self showAlertWithTitle:@"Couldn't load video"
                                 message:error.localizedDescription ?: @"Unknown error"
                                      on:presentingVC];
                return;
            }
            [self presentActionSheetWithResult:result
                                       videoID:vid
                                  presentingVC:presentingVC
                                      fromView:sourceView];
        }];
    }];
}

+ (void)showAlertWithTitle:(NSString *)title message:(NSString *)message on:(UIViewController *)vc {
    if (!vc) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                               message:message
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [vc presentViewController:a animated:YES completion:nil];
}

#pragma mark - Action handlers (M2)

+ (void)copyInfoForResult:(YTAGExtractionResult *)result on:(UIViewController *)presentingVC {
    NSMutableString *info = [NSMutableString string];
    if (result.title.length > 0)  [info appendFormat:@"%@\n", result.title];
    if (result.author.length > 0) [info appendFormat:@"Channel: %@\n", result.author];
    [info appendFormat:@"URL: https://youtu.be/%@\n", result.videoID];
    if (result.duration > 0) {
        NSInteger total = (NSInteger)result.duration;
        NSInteger h = total / 3600;
        NSInteger m = (total % 3600) / 60;
        NSInteger s = total % 60;
        if (h > 0) {
            [info appendFormat:@"Duration: %ld:%02ld:%02ld\n", (long)h, (long)m, (long)s];
        } else {
            [info appendFormat:@"Duration: %ld:%02ld\n", (long)m, (long)s];
        }
    }
    if (result.shortDescription.length > 0) {
        // Cap description at 500 chars so we don't paste hashtag walls / chapter dumps.
        NSString *desc = result.shortDescription;
        if (desc.length > 500) {
            desc = [[desc substringToIndex:500] stringByAppendingString:@"…"];
        }
        [info appendFormat:@"\n%@", desc];
    }

    [UIPasteboard generalPasteboard].string = info;

    // Light HUD — same "Copied" vibe as YT's own copy-link.
    UIAlertController *hud = [UIAlertController
        alertControllerWithTitle:nil
                         message:@"Copied to clipboard"
                  preferredStyle:UIAlertControllerStyleAlert];
    [presentingVC presentViewController:hud animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [hud dismissViewControllerAnimated:YES completion:nil];
        });
    }];
    YTAGLog(@"dl-trigger", @"copied info for videoID=%@", result.videoID);
}

+ (void)saveThumbnailForResult:(YTAGExtractionResult *)result on:(UIViewController *)presentingVC {
    NSString *urlStr = result.thumbnailURL;
    if (urlStr.length == 0) {
        [self showAlertWithTitle:@"No thumbnail" message:@"This video doesn't expose a thumbnail." on:presentingVC];
        return;
    }
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) {
        [self showAlertWithTitle:@"Bad thumbnail URL" message:urlStr on:presentingVC];
        return;
    }

    UIAlertController *loading = [UIAlertController
        alertControllerWithTitle:nil
                         message:@"Saving…"
                  preferredStyle:UIAlertControllerStyleAlert];
    [presentingVC presentViewController:loading animated:YES completion:nil];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
                                                             completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [loading dismissViewControllerAnimated:YES completion:^{
                if (error || data.length == 0) {
                    [self showAlertWithTitle:@"Couldn't download thumbnail"
                                     message:error.localizedDescription ?: @"Empty response"
                                          on:presentingVC];
                    return;
                }
                UIImage *image = [UIImage imageWithData:data];
                if (!image) {
                    [self showAlertWithTitle:@"Couldn't decode thumbnail"
                                     message:@"The thumbnail data wasn't an image."
                                          on:presentingVC];
                    return;
                }
                [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                    [PHAssetChangeRequest creationRequestForAssetFromImage:image];
                } completionHandler:^(BOOL success, NSError * _Nullable saveError) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (success) {
                            UIAlertController *hud = [UIAlertController
                                alertControllerWithTitle:nil
                                                 message:@"Thumbnail saved to Photos"
                                          preferredStyle:UIAlertControllerStyleAlert];
                            [presentingVC presentViewController:hud animated:YES completion:^{
                                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                    [hud dismissViewControllerAnimated:YES completion:nil];
                                });
                            }];
                        } else {
                            [self showAlertWithTitle:@"Couldn't save thumbnail"
                                             message:saveError.localizedDescription ?: @"Photos refused the image."
                                                  on:presentingVC];
                        }
                    });
                }];
            }];
        });
    }];
    [task resume];
}

+ (void)openInExternalPlayerForResult:(YTAGExtractionResult *)result
                        presentingVC:(UIViewController *)presentingVC
                            fromView:(UIView *)sourceView
{
    // Pick the best muxed (video+audio) URL. If YT returns only adaptive streams,
    // fall back to the highest-resolution video-only URL — VLC/Infuse will still
    // play it even without audio muxed, and the user can use the download feature
    // for a proper combined file.
    NSString *streamURL = nil;
    NSInteger bestScore = -1;
    for (YTAGFormat *f in result.formats) {
        if (f.url.length == 0) continue;
        // Progressive formats are not marked video-only and not marked audio-only.
        BOOL isProgressive = !f.isVideoOnly && !f.isAudioOnly;
        NSInteger score = (isProgressive ? 1000000 : 0) + f.height * 1000 + f.fps;
        if (score > bestScore) {
            bestScore = score;
            streamURL = f.url;
        }
    }
    if (streamURL.length == 0) {
        [self showAlertWithTitle:@"No stream URL"
                         message:@"This video didn't expose any direct playback URLs."
                              on:presentingVC];
        return;
    }

    NSURL *url = [NSURL URLWithString:streamURL];
    if (!url) {
        [self showAlertWithTitle:@"Bad stream URL" message:streamURL on:presentingVC];
        return;
    }

    NSMutableArray *items = [NSMutableArray arrayWithObject:url];
    if (result.title.length > 0) [items addObject:result.title];

    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
    share.popoverPresentationController.sourceView = sourceView;
    share.popoverPresentationController.sourceRect = sourceView.bounds;
    [presentingVC presentViewController:share animated:YES completion:nil];
    YTAGLog(@"dl-trigger", @"external player share for videoID=%@", result.videoID);
}

+ (void)downloadCaptionsForResult:(YTAGExtractionResult *)result
                     presentingVC:(UIViewController *)presentingVC
                         fromView:(UIView *)sourceView
{
    NSArray<YTAGCaptionTrack *> *tracks = result.captionTracks;
    if (tracks.count == 0) {
        [self showAlertWithTitle:@"No captions" message:@"This video doesn't have captions." on:presentingVC];
        return;
    }

    void (^fetchAndSave)(YTAGCaptionTrack *) = ^(YTAGCaptionTrack *track) {
        // Request VTT so we can cleanly convert to SRT.
        NSString *base = track.baseURL;
        NSString *separator = [base rangeOfString:@"?"].location != NSNotFound ? @"&" : @"?";
        NSString *vttURLString = [NSString stringWithFormat:@"%@%@fmt=vtt", base, separator];
        NSURL *vttURL = [NSURL URLWithString:vttURLString];
        if (!vttURL) {
            [self showAlertWithTitle:@"Bad caption URL" message:vttURLString on:presentingVC];
            return;
        }

        UIAlertController *loading = [UIAlertController
            alertControllerWithTitle:nil
                             message:@"Fetching captions…"
                      preferredStyle:UIAlertControllerStyleAlert];
        [presentingVC presentViewController:loading animated:YES completion:nil];

        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:vttURL
                                                                 completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [loading dismissViewControllerAnimated:YES completion:^{
                    if (error || data.length == 0) {
                        [self showAlertWithTitle:@"Couldn't fetch captions"
                                         message:error.localizedDescription ?: @"Empty response"
                                              on:presentingVC];
                        return;
                    }
                    NSString *vtt = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    if (vtt.length == 0) {
                        [self showAlertWithTitle:@"Empty caption data"
                                         message:@"The server returned no caption content."
                                              on:presentingVC];
                        return;
                    }

                    // VTT -> SRT conversion.
                    // 1. Drop WEBVTT header + NOTE / Kind / Language metadata lines.
                    // 2. In timing lines: replace '.' with ',' and ensure HH: prefix (SRT requires it).
                    //    Also strip VTT position/align hints after the end-timestamp.
                    // 3. In cue text: strip inline VTT tags (<c>, <c.colorXXXX>, <i>, <v Speaker>,
                    //    <00:00:00.000>). YT auto-generated captions use these heavily.
                    // 4. Add 1-based cue indices before each cue.
                    static NSRegularExpression *kVTTTagStripper = nil;
                    static NSRegularExpression *kVTTTimingValidator = nil;
                    static dispatch_once_t once;
                    dispatch_once(&once, ^{
                        kVTTTagStripper = [NSRegularExpression regularExpressionWithPattern:@"<[^>]+>"
                                                                                    options:0
                                                                                      error:nil];
                        // SRT timing shape: HH:MM:SS,mmm
                        kVTTTimingValidator = [NSRegularExpression regularExpressionWithPattern:@"^\\d{2}:\\d{2}:\\d{2}[,.]\\d{3}$"
                                                                                        options:0
                                                                                          error:nil];
                    });

                    NSString * (^normalizeTiming)(NSString *) = ^NSString *(NSString *ts) {
                        // Strip surrounding whitespace
                        NSString *clean = [ts stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                        // Convert '.' -> ',' at the fractional boundary (last dot before digits)
                        clean = [clean stringByReplacingOccurrencesOfString:@"." withString:@","];
                        // Prepend 00: if missing HH component (MM:SS,mmm form)
                        NSUInteger colons = [[clean componentsSeparatedByString:@":"] count] - 1;
                        if (colons < 2) clean = [@"00:" stringByAppendingString:clean];
                        return clean;
                    };

                    NSArray<NSString *> *lines = [vtt componentsSeparatedByString:@"\n"];
                    NSMutableArray<NSString *> *cues = [NSMutableArray array];
                    NSMutableArray<NSString *> *currentCue = nil;
                    BOOL sawTiming = NO;
                    for (NSString *raw in lines) {
                        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\r"]];
                        if ([line hasPrefix:@"WEBVTT"]) continue;
                        if ([line hasPrefix:@"NOTE"]) continue;
                        if ([line hasPrefix:@"Kind:"] || [line hasPrefix:@"Language:"]) continue;
                        NSRange arrow = [line rangeOfString:@"-->"];
                        if (arrow.location != NSNotFound) {
                            if (currentCue) [cues addObject:[currentCue componentsJoinedByString:@"\n"]];
                            NSString *startTS = [line substringToIndex:arrow.location];
                            NSString *afterArrow = [line substringFromIndex:NSMaxRange(arrow)];
                            // Trim trailing position/align hints from the end timestamp
                            NSRange space = [afterArrow rangeOfString:@" " options:0 range:NSMakeRange(1, afterArrow.length - 1)];
                            NSString *endTS = (space.location != NSNotFound)
                                ? [afterArrow substringToIndex:space.location]
                                : afterArrow;
                            NSString *timing = [NSString stringWithFormat:@"%@ --> %@",
                                                normalizeTiming(startTS), normalizeTiming(endTS)];
                            currentCue = [NSMutableArray arrayWithObject:timing];
                            sawTiming = YES;
                        } else if (sawTiming && line.length == 0 && currentCue) {
                            [cues addObject:[currentCue componentsJoinedByString:@"\n"]];
                            currentCue = nil;
                        } else if (sawTiming && currentCue) {
                            NSString *stripped = [kVTTTagStripper stringByReplacingMatchesInString:line
                                                                                           options:0
                                                                                             range:NSMakeRange(0, line.length)
                                                                                      withTemplate:@""];
                            if (stripped.length > 0) [currentCue addObject:stripped];
                        }
                    }
                    if (currentCue) [cues addObject:[currentCue componentsJoinedByString:@"\n"]];

                    // Drop any cues that collapsed to timing-only (no visible text after stripping).
                    NSMutableArray<NSString *> *cleanCues = [NSMutableArray arrayWithCapacity:cues.count];
                    for (NSString *cue in cues) {
                        NSArray<NSString *> *parts = [cue componentsSeparatedByString:@"\n"];
                        if (parts.count >= 2) [cleanCues addObject:cue];
                    }

                    NSMutableString *srt = [NSMutableString string];
                    for (NSUInteger i = 0; i < cleanCues.count; i++) {
                        [srt appendFormat:@"%lu\n%@\n\n", (unsigned long)(i + 1), cleanCues[i]];
                    }

                    if (srt.length == 0) {
                        [self showAlertWithTitle:@"Empty captions"
                                         message:@"The caption track contained no cues."
                                              on:presentingVC];
                        return;
                    }

                    // Write to a temp file and present a share sheet so the user can pick Files / any destination.
                    NSString *safeTitle = result.title.length > 0 ? result.title : result.videoID;
                    NSCharacterSet *disallowed = [NSCharacterSet characterSetWithCharactersInString:@"/\\?%*|\"<>:"];
                    NSString *cleanTitle = [[safeTitle componentsSeparatedByCharactersInSet:disallowed] componentsJoinedByString:@"_"];
                    NSString *fileName = [NSString stringWithFormat:@"%@.%@.srt", cleanTitle, track.languageCode.length > 0 ? track.languageCode : @"en"];
                    NSURL *tmpURL = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:fileName];
                    NSError *writeErr = nil;
                    [srt writeToURL:tmpURL atomically:YES encoding:NSUTF8StringEncoding error:&writeErr];
                    if (writeErr) {
                        [self showAlertWithTitle:@"Couldn't write SRT"
                                         message:writeErr.localizedDescription
                                              on:presentingVC];
                        return;
                    }

                    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[tmpURL] applicationActivities:nil];
                    share.popoverPresentationController.sourceView = sourceView;
                    share.popoverPresentationController.sourceRect = sourceView.bounds;
                    [presentingVC presentViewController:share animated:YES completion:nil];
                    YTAGLog(@"dl-trigger", @"captions ready at %@ (%lu cues)", tmpURL.path, (unsigned long)cues.count);
                }];
            });
        }];
        [task resume];
    };

    if (tracks.count == 1) {
        fetchAndSave(tracks.firstObject);
        return;
    }

    // Present a picker.
    UIAlertController *picker = [UIAlertController
        alertControllerWithTitle:@"Caption language"
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];
    for (YTAGCaptionTrack *track in tracks) {
        NSString *label = track.displayName.length > 0 ? track.displayName : track.languageCode;
        if (track.isAutoGenerated) label = [NSString stringWithFormat:@"%@ (auto)", label];
        [picker addAction:[UIAlertAction actionWithTitle:label
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *_) {
            fetchAndSave(track);
        }]];
    }
    [picker addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    picker.popoverPresentationController.sourceView = sourceView;
    picker.popoverPresentationController.sourceRect = sourceView.bounds;
    [presentingVC presentViewController:picker animated:YES completion:nil];
}

@end

// --- Ctor (outside any %hook) ---

%ctor {
    YTAGLog(@"dl-trigger", @"YTAGDownload hook installed");
}
