#import <version.h>
#import <PSHeader/Misc.h>
#import <YouTubeHeader/ASCollectionView.h>
#import <YouTubeHeader/ELMCellNode.h>
#import <YouTubeHeader/ELMContainerNode.h>
#import <YouTubeHeader/MLDefaultPlayerViewFactory.h>
#import <YouTubeHeader/MLPIPController.h>
#import <YouTubeHeader/QTMIcon.h>
#import <YouTubeHeader/YTAppDelegate.h>
#import <YouTubeHeader/YTAppViewControllerImpl.h>
#import <YouTubeHeader/YTBackgroundabilityPolicy.h>
#import <YouTubeHeader/YTColor.h>
#import <YouTubeHeader/YTColorPalette.h>
#import <YouTubeHeader/YTCommonColorPalette.h>
#import <YouTubeHeader/YTIIcon.h>
#import <YouTubeHeader/YTLocalPlaybackController.h>
#import <YouTubeHeader/YTMainAppControlsOverlayView.h>
#import <YouTubeHeader/YTMainAppVideoPlayerOverlayViewController.h>
#import <YouTubeHeader/YTPageStyleController.h>
#import <YouTubeHeader/YTPlaybackStrippedWatchController.h>
#import <YouTubeHeader/YTPlayerPIPController.h>
#import <YouTubeHeader/YTPlayerStatus.h>
#import <YouTubeHeader/YTSettingsSectionItemManager.h>
#import <YouTubeHeader/YTSystemNotifications.h>
#import <YouTubeHeader/YTTouchFeedbackController.h>
#import <YouTubeHeader/YTUIResources.h>
#import <YouTubeHeader/YTWatchViewController.h>
#import "Header.h"
#import "../YTVideoOverlay/Header.h"
#import "../YTVideoOverlay/Init.x"
#import "../../Utils/YTAGLog.h"

@interface YTMainAppControlsOverlayView (YouPiP)
- (void)didPressPiP:(id)arg;
@end

@interface YTInlinePlayerBarContainerView (YouPiP)
- (void)didPressPiP:(id)arg;
@end

@interface ASCollectionView (YP)
@property (retain, nonatomic) UIButton *pipButton;
@property (retain, nonatomic) YTTouchFeedbackController *pipTouchController;
- (void)didPressPiP:(UIButton *)button event:(UIEvent *)event;
@end

BOOL FromUser = NO;
BOOL PiPDisabled = NO;

extern BOOL LegacyPiP();

BOOL TweakEnabled() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:EnabledKey];
}

BOOL UsePiPButton() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:PiPActivationMethodKey];
}

BOOL UseTabBarPiPButton() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:PiPActivationMethod2Key];
}

BOOL UseAllPiPMethod() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:PiPAllActivationMethodKey];
}

BOOL NoMiniPlayerPiP() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:NoMiniPlayerPiPKey];
}

BOOL NonBackgroundable() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:NonBackgroundableKey];
}

BOOL isPictureInPictureActive(MLPIPController *pip) {
    return [pip respondsToSelector:@selector(pictureInPictureActive)] ? [pip pictureInPictureActive] : [pip isPictureInPictureActive];
}

static NSString *PiPIconPath;
static NSString *TabBarPiPIconPath;

static void activatePiPBase(YTPlayerPIPController *controller) {
    YTAGLog(@"pip", @"activatePiPBase controller=%@ class=%@", controller, NSStringFromClass([controller class]));
    if (!controller) { YTAGLog(@"pip", @"  controller nil, abort"); return; }
    YTBackgroundabilityPolicy *backgroundabilityPolicy = [controller valueForKey:@"_backgroundabilityPolicy"];
    BOOL allowed = backgroundabilityPolicy.playableInPiPByUserSettings;
    YTAGLog(@"pip", @"  backgroundabilityPolicy=%@ playableInPiPByUserSettings=%@", backgroundabilityPolicy, allowed ? @"YES" : @"NO");
    if (!allowed) { YTAGLog(@"pip", @"  early-return (user-settings says no)"); return; }
    MLPIPController *pip = [controller valueForKey:@"_pipController"];
    YTAGLog(@"pip", @"  _pipController=%@ class=%@", pip, NSStringFromClass([pip class]));
    if ([controller respondsToSelector:@selector(maybeEnablePictureInPicture)]) {
        YTAGLog(@"pip", @"  -> maybeEnablePictureInPicture");
        [controller maybeEnablePictureInPicture];
    } else if ([controller respondsToSelector:@selector(maybeInvokePictureInPicture)]) {
        YTAGLog(@"pip", @"  -> maybeInvokePictureInPicture");
        [controller maybeInvokePictureInPicture];
    } else {
        BOOL canPiP = [controller respondsToSelector:@selector(canEnablePictureInPicture)] && [controller canEnablePictureInPicture];
        if (!canPiP)
            canPiP = [controller respondsToSelector:@selector(canInvokePictureInPicture)] && [controller canInvokePictureInPicture];
        YTAGLog(@"pip", @"  canPiP=%@", canPiP ? @"YES" : @"NO");
        if (canPiP) {
            if ([pip respondsToSelector:@selector(activatePiPController)]) {
                YTAGLog(@"pip", @"  -> pip activatePiPController");
                [pip activatePiPController];
            } else {
                YTAGLog(@"pip", @"  -> pip startPictureInPicture");
                [pip startPictureInPicture];
            }
        }
    }
    AVPictureInPictureController *avpip = [pip valueForKey:@"_pictureInPictureController"];
    YTAGLog(@"pip", @"  AVPiP=%@ possible=%@", avpip, avpip.pictureInPicturePossible ? @"YES" : @"NO");
    if (avpip.pictureInPicturePossible) {
        YTAGLog(@"pip", @"  -> avpip startPictureInPicture");
        [avpip startPictureInPicture];
    }
}

static void activatePiP(YTLocalPlaybackController *local) {
    YTAGLog(@"pip", @"activatePiP local=%@ class=%@", local, NSStringFromClass([local class]));
    if (![local isKindOfClass:%c(YTLocalPlaybackController)]) {
        YTAGLog(@"pip", @"  local is not YTLocalPlaybackController, abort");
        return;
    }
    YTPlayerPIPController *controller = nil;
    @try {
        controller = [local valueForKey:@"_playerPIPController"];
    } @catch (id ex) {
        YTAGLog(@"pip", @"  _playerPIPController KVC failed: %@", ex);
    }
    activatePiPBase(controller);
}

static void bootstrapPiP(YTPlayerViewController *self) {
    YTAGLog(@"pip", @"bootstrapPiP self=%@", self);
    YTLocalPlaybackController *local = nil;
    @try {
        local = [self valueForKey:@"_playbackController"];
    } @catch (id ex) {
        YTAGLog(@"pip", @"  _playbackController KVC failed: %@", ex);
    }
    activatePiP(local);
}

static YTCommonColorPalette *currentColorPalette() {
    Class YTPageStyleControllerClass = %c(YTPageStyleController);
    if (YTPageStyleControllerClass)
        return [YTPageStyleControllerClass currentColorPalette];
    YTAppDelegate *delegate = (YTAppDelegate *)[UIApplication sharedApplication].delegate;
    YTAppViewControllerImpl *appViewController = [delegate valueForKey:@"_appViewController"];
    NSInteger pageStyle = [appViewController pageStyle];
    Class YTCommonColorPaletteClass = %c(YTCommonColorPalette);
    if (YTCommonColorPaletteClass)
        return pageStyle == 1 ? [YTCommonColorPaletteClass darkPalette] : [YTCommonColorPaletteClass lightPalette];
    return [%c(YTColorPalette) colorPaletteForPageStyle:pageStyle];
}

%group Icon

BOOL shouldUseNewSettingIcon = NO;

%hook YTIIcon

- (UIImage *)iconImageWithColor:(UIColor *)color {
    if (self.iconType == YT_PICTURE_IN_PICTURE) {
        UIColor *color = [currentColorPalette() textPrimary];
        NSString *iconPath = shouldUseNewSettingIcon ? PiPIconPath : TabBarPiPIconPath;
        UIImage *image = [%c(QTMIcon) tintImage:[UIImage imageWithContentsOfFile:iconPath] color:color];
        if ([image respondsToSelector:@selector(imageFlippedForRightToLeftLayoutDirection)])
            image = [image imageFlippedForRightToLeftLayoutDirection];
        return image;
    }
    return %orig;
}

%end

%hook YTAppDelegate

- (void)performPostCriticalInitializationWithApplication:(UIApplication *)application withOptions:(NSDictionary *)launchOptions {
    %orig;
    Class YTUIResourcesClass = %c(YTUIResources);
    shouldUseNewSettingIcon = [YTUIResourcesClass respondsToSelector:@selector(delhiIconsEnabled)] ? [YTUIResourcesClass delhiIconsEnabled] : NO;
}

%end

%end

#pragma mark - Video tab bar PiP Button (17.01.4 and up)

static UIButton *makeUnderNewPlayerButton(ELMCellNode *node, NSString *title, NSString *accessibilityLabel) {
    YTCommonColorPalette *palette = currentColorPalette();
    UIColor *textColor = [palette textPrimary];

    ELMContainerNode *containerNode = (ELMContainerNode *)[[[[node yogaChildren] firstObject] yogaChildren] firstObject]; // To get node container properties
    UIButton *buttonView = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 64, containerNode.calculatedSize.height)];
    buttonView.center = CGPointMake(CGRectGetMaxX([node.layoutAttributes frame]) + 65 / 2, CGRectGetMidY([node.layoutAttributes frame]));
    buttonView.backgroundColor = containerNode.backgroundColor;
    buttonView.accessibilityLabel = accessibilityLabel;
    buttonView.layer.cornerRadius = 16;

    UIImageView *buttonImage = [[UIImageView alloc] initWithFrame:CGRectMake(12, ([buttonView frame].size.height - 15) / 2, 15, 15)];
    buttonImage.image = [%c(QTMIcon) tintImage:[UIImage imageWithContentsOfFile:TabBarPiPIconPath] color:textColor];

    UIFontMetrics *metrics = [UIFontMetrics metricsForTextStyle:UIFontTextStyleBody];
    UIFont *font = [metrics scaledFontForFont:[UIFont boldSystemFontOfSize:12]];
    CGFloat fontSize = font.pointSize;
    UILabel *buttonTitle = [[UILabel alloc] initWithFrame:CGRectMake(33, ([buttonView frame].size.height - fontSize - 1) / 2, 20, fontSize)];
    buttonTitle.font = font;
    buttonTitle.textColor = textColor;
    buttonTitle.text = title;
    [buttonTitle sizeToFit];

    [buttonView addSubview:buttonImage];
    [buttonView addSubview:buttonTitle];
    return buttonView;
}

%hook ASCollectionView

%property (retain, nonatomic) UIButton *pipButton;
%property (retain, nonatomic) YTTouchFeedbackController *pipTouchController;

- (ELMCellNode *)nodeForItemAtIndexPath:(NSIndexPath *)indexPath {
    ELMCellNode *node = %orig;
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.scrollable_action_bar"] && UseTabBarPiPButton() && !self.pipButton) {
        self.contentInset = UIEdgeInsetsMake(0, 0, 0, 73);
        if ([self collectionView:self numberOfItemsInSection:0] - 1 == indexPath.row) {
            self.pipButton = makeUnderNewPlayerButton(node, @"PiP", @"Play in PiP");
            [self addSubview:self.pipButton];

            [self.pipButton addTarget:self action:@selector(didPressPiP:event:) forControlEvents:UIControlEventTouchUpInside];
            YTTouchFeedbackController *controller = [[%c(YTTouchFeedbackController) alloc] initWithView:self.pipButton];
            controller.touchFeedbackView.customCornerRadius = 16;
            self.pipTouchController = controller;
        }
    }
    return %orig;
}

- (void)nodesDidRelayout:(NSArray <ELMCellNode *> *)nodes {
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.scrollable_action_bar"] && UseTabBarPiPButton() && [nodes count] == 1) {
        CGFloat offset = nodes[0].calculatedSize.width - [nodes[0].layoutAttributes frame].size.width;
        [UIView animateWithDuration:0.3 animations:^{
            self.pipButton.center = CGPointMake(self.pipButton.center.x + offset, self.pipButton.center.y);
        }];
    }
    %orig;
}

%new(v@:@@)
- (void)didPressPiP:(UIButton *)button event:(UIEvent *)event {
    YTAGLog(@"pip", @"ASCollectionView.didPressPiP: tab-bar button");
    CGPoint location = [[[event allTouches] anyObject] locationInView:button];
    if (CGRectContainsPoint(button.bounds, location)) {
        UIViewController *controller = [self.collectionNode closestViewController];
        YTAGLog(@"pip", @"  closestViewController=%@", NSStringFromClass([controller class]));
        YTPlaybackStrippedWatchController *provider = nil;
        @try {
            provider = [controller valueForKey:@"_metadataPanelStateProvider"];
        } @catch (id ex) {
            YTAGLog(@"pip", @"  _metadataPanelStateProvider failed, trying _ngw: %@", ex);
            @try { provider = [controller valueForKey:@"_ngwMetadataPanelStateProvider"]; }
            @catch (id ex2) { YTAGLog(@"pip", @"  both providers failed: %@", ex2); }
        }
        YTWatchViewController *watchViewController = nil;
        @try { watchViewController = [provider valueForKey:@"_watchViewController"]; }
        @catch (id ex) { YTAGLog(@"pip", @"  _watchViewController failed: %@", ex); }
        YTPlayerViewController *playerViewController = nil;
        @try { playerViewController = [watchViewController valueForKey:@"_playerViewController"]; }
        @catch (id ex) { YTAGLog(@"pip", @"  _playerViewController failed: %@", ex); }
        YTAGLog(@"pip", @"  playerViewController=%@ watchVC=%@ provider=%@", playerViewController, watchViewController, provider);
        FromUser = YES;
        bootstrapPiP(playerViewController);
    } else {
        YTAGLog(@"pip", @"  tap outside button bounds, ignoring");
    }
}

- (void)dealloc {
    self.pipButton = nil;
    self.pipTouchController = nil;
    %orig;
}

%end

#pragma mark - Overlay PiP Button

static UIImage *pipImage() {
    static UIImage *image = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UIColor *color = [%c(YTColor) white1];
        image = [%c(QTMIcon) tintImage:[UIImage imageWithContentsOfFile:PiPIconPath] color:color];
        if ([image respondsToSelector:@selector(imageFlippedForRightToLeftLayoutDirection)])
            image = [image imageFlippedForRightToLeftLayoutDirection];
    });
    return image;
}

%hook YTMainAppControlsOverlayView

- (UIImage *)buttonImage:(NSString *)tweakId {
    return [tweakId isEqualToString:TweakName] ? pipImage() : %orig;
}

%new(v@:@)
- (void)didPressPiP:(id)arg {
    YTAGLog(@"pip", @"YTMainAppControlsOverlayView.didPressPiP: overlay button");
    YTMainAppVideoPlayerOverlayViewController *c = nil;
    @try { c = [self valueForKey:@"_eventsDelegate"]; }
    @catch (id ex) { YTAGLog(@"pip", @"  _eventsDelegate KVC failed: %@", ex); }
    if (!c) {
        YTAGLog(@"pip", @"  _eventsDelegate nil, walking responder chain");
        UIResponder *r = self.nextResponder;
        while (r) {
            if ([r isKindOfClass:%c(YTMainAppVideoPlayerOverlayViewController)]) {
                c = (YTMainAppVideoPlayerOverlayViewController *)r;
                break;
            }
            r = r.nextResponder;
        }
    }
    YTAGLog(@"pip", @"  overlay VC=%@", c);
    YTPlayerViewController *pvc = c ? (YTPlayerViewController *)c.parentViewController : nil;
    YTAGLog(@"pip", @"  parent pvc=%@ class=%@", pvc, NSStringFromClass([pvc class]));
    if (!pvc) { YTAGLog(@"pip", @"  no pvc, abort"); return; }
    FromUser = YES;
    bootstrapPiP(pvc);
}

%end

%hook YTInlinePlayerBarContainerView

- (UIImage *)buttonImage:(NSString *)tweakId {
    return [tweakId isEqualToString:TweakName] ? pipImage() : %orig;
}

%new(v@:@)
- (void)didPressPiP:(id)arg {
    YTAGLog(@"pip", @"YTInlinePlayerBarContainerView.didPressPiP: inline bar button");
    YTMainAppVideoPlayerOverlayViewController *c = nil;
    @try { c = [self.delegate valueForKey:@"_delegate"]; }
    @catch (id ex) { YTAGLog(@"pip", @"  self.delegate._delegate KVC failed: %@", ex); }
    if (!c) {
        YTAGLog(@"pip", @"  delegate nil, walking responder chain");
        UIResponder *r = self.nextResponder;
        while (r) {
            if ([r isKindOfClass:%c(YTMainAppVideoPlayerOverlayViewController)]) {
                c = (YTMainAppVideoPlayerOverlayViewController *)r;
                break;
            }
            r = r.nextResponder;
        }
    }
    YTAGLog(@"pip", @"  overlay VC=%@", c);
    YTPlayerViewController *pvc = c ? (YTPlayerViewController *)c.parentViewController : nil;
    YTAGLog(@"pip", @"  parent pvc=%@ class=%@", pvc, NSStringFromClass([pvc class]));
    if (!pvc) { YTAGLog(@"pip", @"  no pvc, abort"); return; }
    FromUser = YES;
    bootstrapPiP(pvc);
}

%end

#pragma mark - PiP Support

%hook MLPIPController

- (void)activatePiPController {
    %orig;
    BOOL blockPiP = !UseAllPiPMethod() && (UsePiPButton() || UseTabBarPiPButton());
    AVPictureInPictureController *avpip = [self valueForKey:@"_pictureInPictureController"];
    if (blockPiP && [avpip respondsToSelector:@selector(canStartPictureInPictureAutomaticallyFromInline)])
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
        avpip.canStartPictureInPictureAutomaticallyFromInline = NO;
    if ([avpip respondsToSelector:@selector(canStartAutomaticallyWhenEnteringBackground)])
        avpip.canStartAutomaticallyWhenEnteringBackground = !blockPiP;
#pragma clang diagnostic pop
    if (IS_IOS_OR_NEWER(iOS_15_0) || LegacyPiP()) return;
    MLHAMSBDLSampleBufferRenderingView *view = [self valueForKey:@"_HAMPlayerView"];
    CGSize size = [self renderSizeForView:view];
    [avpip sampleBufferDisplayLayerRenderSizeDidChangeToSize:size];
    [avpip sampleBufferDisplayLayerDidAppear];
}

%new(B@:@)
- (BOOL)pictureInPictureControllerPlaybackPaused:(AVPictureInPictureController *)pictureInPictureController {
    return [self pictureInPictureControllerIsPlaybackPaused:pictureInPictureController];
}

%new(v@:@)
- (void)pictureInPictureControllerStartPlayback:(id)arg1 {
    [self pictureInPictureControllerStartPlayback];
}

%new(v@:@)
- (void)pictureInPictureControllerStopPlayback:(id)arg1 {
    [self pictureInPictureControllerStopPlayback];
}

%new(v@:{CGSize=dd})
- (void)renderingViewSampleBufferFrameSizeDidChange:(CGSize)size {
    if (IS_IOS_OR_NEWER(iOS_15_0) || !size.width || !size.height) return;
    AVPictureInPictureController *avpip = [self valueForKey:@"_pictureInPictureController"];
    [avpip sampleBufferDisplayLayerRenderSizeDidChangeToSize:size];
}

%new(v@:@)
- (void)appWillEnterForeground:(id)arg1 {
    if (IS_IOS_OR_NEWER(iOS_15_0) || LegacyPiP()) return;
    AVPictureInPictureController *avpip = [self valueForKey:@"_pictureInPictureController"];
    [avpip sampleBufferDisplayLayerDidAppear];
}

%new(v@:@)
- (void)appWillEnterBackground:(id)arg1 {
    if (IS_IOS_OR_NEWER(iOS_15_0) || LegacyPiP()) return;
    AVPictureInPictureController *avpip = [self valueForKey:@"_pictureInPictureController"];
    [avpip sampleBufferDisplayLayerDidDisappear];
}

%end

%hook YTIIosMediaHotConfig

%new(B@:)
- (BOOL)enablePictureInPicture {
    return YES;
}

%new(B@:)
- (BOOL)enablePipForNonBackgroundableContent {
    return NonBackgroundable();
}

%new(B@:)
- (BOOL)enablePipForNonPremiumUsers {
    return YES;
}

%end

#pragma mark - Hacks

BOOL YTSingleVideo_isLivePlayback_override = NO;

%hook YTSingleVideo

- (BOOL)isLivePlayback {
    return YTSingleVideo_isLivePlayback_override ? NO : %orig;
}

%end

%hook YTPlayerPIPController

- (BOOL)canInvokePictureInPicture {
    YTSingleVideo_isLivePlayback_override = YES;
    BOOL value = %orig;
    YTSingleVideo_isLivePlayback_override = NO;
    return value;
}

- (BOOL)canEnablePictureInPicture {
    YTSingleVideo_isLivePlayback_override = YES;
    BOOL value = %orig;
    YTSingleVideo_isLivePlayback_override = NO;
    return value;
}

- (void)didStopPictureInPicture {
    FromUser = NO;
    %orig;
}

- (void)appWillResignActive:(id)arg1 {
    if (!UseAllPiPMethod()) {
        // If PiP button on, PiP doesn't activate on app resign unless it's from user
        BOOL hasPiPButton = UsePiPButton() || UseTabBarPiPButton();
        BOOL disablePiP = hasPiPButton && !FromUser;
        if (disablePiP) return;
    }
    if (LegacyPiP())
        activatePiPBase(self);
    %orig;
}

%end

%hook YTSingleVideoController

- (void)playerStatusDidChange:(YTPlayerStatus *)playerStatus {
    %orig;
    PiPDisabled = NoMiniPlayerPiP() && playerStatus.visibility == 1;
}

%end

%hook AVPictureInPicturePlatformAdapter

- (BOOL)isSystemPictureInPicturePossible {
    return PiPDisabled ? NO : %orig;
}

%end

%hook YTIPlayabilityStatus

- (BOOL)isPlayableInPictureInPicture {
    return YES;
}

- (BOOL)hasPictureInPicture {
    return YES;
}

%end

%hook YTHotConfig

- (BOOL)iosPlayerClientSharedConfigSkipPipToggleOnStateChange {
    return NO;
}

- (BOOL)iosPlayerClientSharedConfigOffsetPipControllerTimeRangeWithSbdlCurrentTime {
    return NO;
}

%end

#pragma mark - App background event

@protocol YTSystemNotificationsObserverExtended <YTSystemNotificationsObserver>
- (void)appWillEnterBackground:(UIApplication *)application;
@end

%hook YTSystemNotifications

- (void)registerForNotifications {
    %orig;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
}

%new(v@:@)
- (void)appWillEnterBackground:(id)arg {
    [self callBlockForEveryObserver:^(id <YTSystemNotificationsObserver> observer) {
        id <YTSystemNotificationsObserverExtended> observerExtended = (id <YTSystemNotificationsObserverExtended>)observer;
        if ([observerExtended respondsToSelector:@selector(appWillEnterBackground:)])
            [observerExtended appWillEnterBackground:UIApplication.sharedApplication];
    }];
}

%end

NSBundle *YouPiPBundle() {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *tweakBundlePath = [[NSBundle mainBundle] pathForResource:@"YouPiP" ofType:@"bundle"];
        bundle = [NSBundle bundleWithPath:tweakBundlePath ?: PS_ROOT_PATH_NS(@"/Library/Application Support/" TweakName ".bundle")];
    });
    return bundle;
}

%ctor {
    YTAGLog(@"pip", @"YouPiP ctor starting");
    NSBundle *tweakBundle = YouPiPBundle();
    TabBarPiPIconPath = [tweakBundle pathForResource:@"yt-pip-tabbar" ofType:@"png"];
    %init(Icon);
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        EnabledKey: @YES,
    }];
    if (!TweakEnabled()) { YTAGLog(@"pip", @"YouPiP disabled via user setting"); return; }
    YTAGLog(@"pip", @"YouPiP enabled. Class checks:");
    YTAGLog(@"pip", @"  YTPlayerViewController=%@", NSClassFromString(@"YTPlayerViewController") ? @"YES" : @"NO");
    YTAGLog(@"pip", @"  YTLocalPlaybackController=%@", NSClassFromString(@"YTLocalPlaybackController") ? @"YES" : @"NO");
    YTAGLog(@"pip", @"  YTPlayerPIPController=%@", NSClassFromString(@"YTPlayerPIPController") ? @"YES" : @"NO");
    YTAGLog(@"pip", @"  MLPIPController=%@", NSClassFromString(@"MLPIPController") ? @"YES" : @"NO");
    YTAGLog(@"pip", @"  YTBackgroundabilityPolicy=%@", NSClassFromString(@"YTBackgroundabilityPolicy") ? @"YES" : @"NO");
    PiPIconPath = [tweakBundle pathForResource:@"yt-pip-overlay" ofType:@"png"];
    initYTVideoOverlay(TweakName, @{
        AccessibilityLabelKey: @"PiP",
        SelectorKey: @"didPressPiP:",
        ToggleKey: PiPActivationMethodKey
    });
    %init;
    YTAGLog(@"pip", @"YouPiP ctor done");
}
