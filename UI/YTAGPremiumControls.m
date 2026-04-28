// YTAGPremiumControls.m — bottom sheet that rebuilds YT Premium's "Premium
// controls" panel for free users. Server-gated on Premium: the engagement
// overlay renderer isn't sent in /player responses for non-Premium accounts,
// so a %hook on isEngagementOverlayAvailable can't unlock it (the tiles live
// in that missing renderer). We rebuild the sheet in UIKit and wire the tiles
// to YT controllers we already reach (YTPlayerViewController, YTSingleVideoController).
//
// Shape matches the native sheet from screenshot:
//   - "🅿 Premium controls" pill + close X
//   - Large video title + channel name
//   - Playback row: restart / back-10 / play-pause / forward-10 / next
//   - Utility tiles: Download / Speed / Stable volume / Mute / Copy link / Lock

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import "../Utils/YTAGLog.h"
#import "../Utils/YTAGUserDefaults.h"

extern UIColor *themeColor(NSString *key);

// --- YT classes we touch ---

@class YTIPlayerResponse, YTIVideoDetails;

@interface YTSingleVideoController : NSObject
- (BOOL)isMuted;
- (void)setMuted:(BOOL)muted;
@end

@interface YTPlayerViewController : UIViewController
@property (nonatomic, readonly) NSString *contentVideoID;
- (id)activeVideo;
- (id)contentPlayerResponse;
- (void)didTogglePlayPause;
- (void)didPressRewindWithTimeInterval:(double)interval;
- (void)didPressFastForwardWithTimeInterval:(double)interval;
- (void)replayWithSeekSource:(int)source;
- (void)skipToUpcomingPlayback;
- (void)setPlaybackRate:(float)rate;
- (void)setAudioDRCEnabled:(BOOL)enabled;
@end

// Reuse the trigger from YTAGDownload.x for the Save tile.
@interface YTAGDownloadTrigger : NSObject
+ (void)handleDownloadTap:(UIButton *)sender;
@end

// --- Sheet view controller ---

@interface YTAGPremiumControlsSheet : UIViewController
@property (nonatomic, weak) id playerVC;
@property (nonatomic, weak) UIView *anchorView;
@property (nonatomic, assign) BOOL stableVolumeEnabled;
@property (nonatomic, assign) float currentPlaybackRate;
@property (nonatomic, strong) UIButton *playPauseButton;
@property (nonatomic, strong) UIButton *speedTile;
@property (nonatomic, strong) UIButton *stableVolumeTile;
@property (nonatomic, strong) UIButton *muteTile;
@property (nonatomic, strong) UIButton *lockTile;
@property (nonatomic, assign) BOOL muted;
@property (nonatomic, assign) BOOL locked;
- (instancetype)initWithPlayerVC:(id)playerVC anchorView:(UIView *)anchorView;
@end

// --- Helpers ---

static UIImage *YTAGPCSymbol(NSString *name, CGFloat pointSize, UIImageSymbolWeight weight) {
    UIImage *img = [UIImage systemImageNamed:name];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:weight];
    return [img imageByApplyingSymbolConfiguration:cfg] ?: img;
}

static UIButton *YTAGPCMakeIconButton(NSString *symbolName,
                                       CGFloat pointSize,
                                       id target,
                                       SEL action,
                                       NSString *a11yLabel) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    b.accessibilityLabel = a11yLabel;
    UIImage *img = YTAGPCSymbol(symbolName, pointSize, UIImageSymbolWeightRegular);
    [b setImage:[img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
    b.tintColor = [UIColor whiteColor];
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

// Each tile: circle icon on top, label below.
static UIButton *YTAGPCMakeTile(NSString *symbolName,
                                 NSString *label,
                                 id target,
                                 SEL action) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    b.accessibilityLabel = label;
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];

    UIView *circle = [[UIView alloc] init];
    circle.translatesAutoresizingMaskIntoConstraints = NO;
    circle.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    circle.layer.cornerRadius = 22.0;
    circle.userInteractionEnabled = NO;
    [b addSubview:circle];

    UIImageView *iv = [[UIImageView alloc] init];
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    iv.image = [YTAGPCSymbol(symbolName, 20.0, UIImageSymbolWeightRegular) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    iv.tintColor = [UIColor whiteColor];
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.userInteractionEnabled = NO;
    [circle addSubview:iv];

    UILabel *txt = [[UILabel alloc] init];
    txt.translatesAutoresizingMaskIntoConstraints = NO;
    txt.text = label;
    txt.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    txt.textColor = [UIColor whiteColor];
    txt.textAlignment = NSTextAlignmentCenter;
    txt.numberOfLines = 2;
    txt.userInteractionEnabled = NO;
    [b addSubview:txt];

    // Identify subviews by tag so refresh can find them.
    circle.tag = 1001;
    iv.tag = 1002;
    txt.tag = 1003;

    [NSLayoutConstraint activateConstraints:@[
        [circle.topAnchor      constraintEqualToAnchor:b.topAnchor],
        [circle.centerXAnchor  constraintEqualToAnchor:b.centerXAnchor],
        [circle.widthAnchor    constraintEqualToConstant:44.0],
        [circle.heightAnchor   constraintEqualToConstant:44.0],

        [iv.centerXAnchor      constraintEqualToAnchor:circle.centerXAnchor],
        [iv.centerYAnchor      constraintEqualToAnchor:circle.centerYAnchor],
        [iv.widthAnchor        constraintEqualToConstant:22.0],
        [iv.heightAnchor       constraintEqualToConstant:22.0],

        [txt.topAnchor         constraintEqualToAnchor:circle.bottomAnchor constant:6],
        [txt.leadingAnchor     constraintEqualToAnchor:b.leadingAnchor],
        [txt.trailingAnchor    constraintEqualToAnchor:b.trailingAnchor],
        [txt.bottomAnchor      constraintLessThanOrEqualToAnchor:b.bottomAnchor],
    ]];
    return b;
}

static void YTAGPCUpdateTile(UIButton *tile, NSString *symbolName, NSString *label, BOOL selected) {
    UIView *circle = [tile viewWithTag:1001];
    UIImageView *iv = (UIImageView *)[tile viewWithTag:1002];
    UILabel *txt = (UILabel *)[tile viewWithTag:1003];
    tile.accessibilityLabel = label;
    tile.selected = selected;
    if ([iv isKindOfClass:[UIImageView class]]) {
        iv.image = [YTAGPCSymbol(symbolName, 20.0, UIImageSymbolWeightRegular) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    if ([txt isKindOfClass:[UILabel class]]) txt.text = label;
    if ([circle isKindOfClass:[UIView class]]) {
        if (selected) {
            circle.backgroundColor = (themeColor(@"theme_accent") ?: [UIColor colorWithRed:0.95 green:0.25 blue:0.25 alpha:1.0]);
        } else {
            circle.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
        }
    }
}

static id YTAGPCOverlayVCFromAnchor(UIView *anchor) {
    Class controlsClass = NSClassFromString(@"YTMainAppControlsOverlayView");
    UIView *view = anchor;
    while (view) {
        if (controlsClass && [view isKindOfClass:controlsClass]) {
            id vc = nil;
            @try { vc = [view valueForKey:@"_eventsDelegate"]; } @catch (id ex) {}
            if (!vc) {
                @try { vc = [view valueForKey:@"eventsDelegate"]; } @catch (id ex) {}
            }
            return vc;
        }
        view = view.superview;
    }
    return nil;
}

static UIViewController *YTAGPCTopPresenter(void) {
    UIWindow *keyWindow = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) {
                keyWindow = window;
                break;
            }
        }
        if (keyWindow) break;
    }

    UIViewController *top = keyWindow.rootViewController;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) {
        top = top.presentedViewController;
    }
    return top;
}

// --- Implementation ---

@implementation YTAGPremiumControlsSheet

- (instancetype)initWithPlayerVC:(id)playerVC anchorView:(UIView *)anchorView {
    self = [super init];
    if (self) {
        _playerVC = playerVC;
        _anchorView = anchorView;
        _currentPlaybackRate = 1.0f;
        if (@available(iOS 15.0, *)) {
            self.modalPresentationStyle = UIModalPresentationPageSheet;
            UISheetPresentationController *sheet = self.sheetPresentationController;
            sheet.detents = @[[UISheetPresentationControllerDetent mediumDetent],
                              [UISheetPresentationControllerDetent largeDetent]];
            sheet.prefersGrabberVisible = YES;
            sheet.preferredCornerRadius = 16.0;
        } else {
            self.modalPresentationStyle = UIModalPresentationFormSheet;
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.09 alpha:1.0];

    // Pull current playback rate + audio DRC state so the tile labels start correct.
    @try {
        id pvc = self.playerVC;
        if ([pvc respondsToSelector:@selector(activePlaybackRateModel)]) {
            id model = [pvc performSelector:@selector(activePlaybackRateModel)];
            if ([model respondsToSelector:@selector(rate)]) {
                _currentPlaybackRate = ((float (*)(id, SEL))objc_msgSend)(model, @selector(rate));
            }
        }
    } @catch (id ex) {}

    [self buildUI];
}

- (void)buildUI {
    // Pull title + channel. YTPlayerViewController.contentPlayerResponse returns a
    // YTPlayerResponse (Obj-C wrapper); the protobuf payload with videoDetails lives
    // on .playerData (the YTIPlayerResponse). v30 skipped that hop and ended up with
    // details=nil — sheet showed literal "Video" / empty channel. Walk through both
    // layers and stop at whichever path first yields a non-empty string.
    NSString *videoTitle = @"Video";
    NSString *channel = @"";
    @try {
        id pvc = self.playerVC;
        if ([pvc respondsToSelector:@selector(contentPlayerResponse)]) {
            id resp = [pvc performSelector:@selector(contentPlayerResponse)];
            // Candidate objects that might carry a videoDetails: the wrapper itself
            // (older builds exposed it directly) AND the protobuf root at .playerData.
            NSMutableArray *candidates = [NSMutableArray array];
            if (resp) [candidates addObject:resp];
            @try {
                id pd = [resp valueForKey:@"playerData"];
                if (pd) [candidates addObject:pd];
            } @catch (id ex) {}

            for (id obj in candidates) {
                id details = nil;
                @try { details = [obj valueForKey:@"videoDetails"]; } @catch (id ex) {}
                if (!details) continue;
                @try {
                    id t = [details valueForKey:@"title"];
                    if ([t isKindOfClass:[NSString class]] && [(NSString *)t length] > 0) videoTitle = t;
                } @catch (id ex) {}
                @try {
                    id a = [details valueForKey:@"author"];
                    if ([a isKindOfClass:[NSString class]] && [(NSString *)a length] > 0) channel = a;
                } @catch (id ex) {}
                if (videoTitle.length > 0 && ![videoTitle isEqualToString:@"Video"]) break;
            }
        }
    } @catch (id ex) {}
    YTAGLog(@"premium-ctrl", @"metadata: title=%@ channel=%@", videoTitle, channel);

    // Header pill + close
    UIView *pill = [[UIView alloc] init];
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    pill.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
    pill.layer.cornerRadius = 14.0;

    UILabel *pillBadge = [[UILabel alloc] init];
    pillBadge.translatesAutoresizingMaskIntoConstraints = NO;
    pillBadge.text = @"P";
    pillBadge.textColor = [UIColor whiteColor];
    pillBadge.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    pillBadge.textAlignment = NSTextAlignmentCenter;
    pillBadge.backgroundColor = themeColor(@"theme_accent") ?: [UIColor colorWithRed:0.95 green:0.25 blue:0.25 alpha:1.0];
    pillBadge.layer.cornerRadius = 4.0;
    pillBadge.layer.masksToBounds = YES;
    [pill addSubview:pillBadge];

    UILabel *pillText = [[UILabel alloc] init];
    pillText.translatesAutoresizingMaskIntoConstraints = NO;
    pillText.text = @"Premium controls";
    pillText.textColor = [UIColor whiteColor];
    pillText.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [pill addSubview:pillText];

    UIButton *closeBtn = YTAGPCMakeIconButton(@"xmark", 18.0, self, @selector(closeTapped), @"Close");

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = videoTitle;
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    titleLabel.numberOfLines = 2;
    titleLabel.textAlignment = NSTextAlignmentCenter;

    UILabel *channelLabel = [[UILabel alloc] init];
    channelLabel.translatesAutoresizingMaskIntoConstraints = NO;
    channelLabel.text = channel;
    channelLabel.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    channelLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
    channelLabel.textAlignment = NSTextAlignmentCenter;

    // Playback row
    UIButton *prev     = YTAGPCMakeIconButton(@"backward.end.fill", 24.0, self, @selector(prevTapped), @"Restart");
    UIButton *back10   = YTAGPCMakeIconButton(@"gobackward.10",     30.0, self, @selector(back10Tapped), @"Back 10 seconds");
    UIButton *playPause= YTAGPCMakeIconButton(@"play.fill",         42.0, self, @selector(playPauseTapped), @"Play/Pause");
    UIButton *fwd10    = YTAGPCMakeIconButton(@"goforward.10",      30.0, self, @selector(fwd10Tapped), @"Forward 10 seconds");
    UIButton *next     = YTAGPCMakeIconButton(@"forward.end.fill",  24.0, self, @selector(nextTapped), @"Next video");
    self.playPauseButton = playPause;
    [self refreshPlayPauseIcon];

    UIStackView *playbackRow = [[UIStackView alloc] initWithArrangedSubviews:@[prev, back10, playPause, fwd10, next]];
    playbackRow.translatesAutoresizingMaskIntoConstraints = NO;
    playbackRow.axis = UILayoutConstraintAxisHorizontal;
    playbackRow.distribution = UIStackViewDistributionEqualSpacing;
    playbackRow.alignment = UIStackViewAlignmentCenter;
    playbackRow.spacing = 24.0;

    // Tile row
    NSString *speedLabel = [NSString stringWithFormat:@"%@x", [self rateString:_currentPlaybackRate]];
    UIButton *speedTile  = YTAGPCMakeTile(@"gauge",         speedLabel, self, @selector(speedTapped));
    UIButton *stableTile = YTAGPCMakeTile(@"waveform",      @"Stable volume", self, @selector(stableVolumeTapped));
    UIButton *downloadTile = YTAGPCMakeTile(@"arrow.down.to.line", @"Download", self, @selector(downloadTapped));
    UIButton *muteTile = YTAGPCMakeTile(@"speaker.wave.2", @"Mute", self, @selector(muteTapped));
    UIButton *copyTile = YTAGPCMakeTile(@"link", @"Copy link", self, @selector(copyLinkTapped));
    UIButton *lockTile = YTAGPCMakeTile(@"lock.open", @"Lock", self, @selector(lockTapped));
    self.speedTile = speedTile;
    self.stableVolumeTile = stableTile;
    self.muteTile = muteTile;
    self.lockTile = lockTile;

    @try {
        id video = [self.playerVC respondsToSelector:@selector(activeVideo)]
            ? ((id (*)(id, SEL))objc_msgSend)(self.playerVC, @selector(activeVideo))
            : nil;
        if ([video respondsToSelector:@selector(isMuted)]) {
            self.muted = ((BOOL (*)(id, SEL))objc_msgSend)(video, @selector(isMuted));
        }
    } @catch (id ex) {}
    id overlayVC = YTAGPCOverlayVCFromAnchor(self.anchorView);
    @try {
        if ([overlayVC respondsToSelector:@selector(lockModeStateEntityController)]) {
            id lc = ((id (*)(id, SEL))objc_msgSend)(overlayVC, @selector(lockModeStateEntityController));
            if ([lc respondsToSelector:@selector(isLockModeActive)]) {
                self.locked = ((BOOL (*)(id, SEL))objc_msgSend)(lc, @selector(isLockModeActive));
            } else {
                NSNumber *v = [lc valueForKey:@"lockModeActive"];
                if ([v respondsToSelector:@selector(boolValue)]) self.locked = v.boolValue;
            }
        }
    } @catch (id ex) {}
    YTAGPCUpdateTile(self.muteTile,
                     self.muted ? @"speaker.slash" : @"speaker.wave.2",
                     self.muted ? @"Unmute" : @"Mute",
                     self.muted);
    YTAGPCUpdateTile(self.lockTile,
                     self.locked ? @"lock.fill" : @"lock.open",
                     self.locked ? @"Unlock" : @"Lock",
                     self.locked);

    UIStackView *tileRow1 = [[UIStackView alloc] initWithArrangedSubviews:@[downloadTile, speedTile, stableTile]];
    tileRow1.axis = UILayoutConstraintAxisHorizontal;
    tileRow1.distribution = UIStackViewDistributionFillEqually;
    tileRow1.alignment = UIStackViewAlignmentTop;
    tileRow1.spacing = 12.0;

    UIStackView *tileRow2 = [[UIStackView alloc] initWithArrangedSubviews:@[muteTile, copyTile, lockTile]];
    tileRow2.axis = UILayoutConstraintAxisHorizontal;
    tileRow2.distribution = UIStackViewDistributionFillEqually;
    tileRow2.alignment = UIStackViewAlignmentTop;
    tileRow2.spacing = 12.0;

    UIStackView *tileGrid = [[UIStackView alloc] initWithArrangedSubviews:@[tileRow1, tileRow2]];
    tileGrid.translatesAutoresizingMaskIntoConstraints = NO;
    tileGrid.axis = UILayoutConstraintAxisVertical;
    tileGrid.spacing = 18.0;

    // Parent
    [self.view addSubview:pill];
    [self.view addSubview:closeBtn];
    [self.view addSubview:titleLabel];
    [self.view addSubview:channelLabel];
    [self.view addSubview:playbackRow];
    [self.view addSubview:tileGrid];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [pill.topAnchor         constraintEqualToAnchor:g.topAnchor constant:16],
        [pill.leadingAnchor     constraintEqualToAnchor:g.leadingAnchor constant:16],
        [pill.heightAnchor      constraintEqualToConstant:28],

        [pillBadge.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:6],
        [pillBadge.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],
        [pillBadge.widthAnchor   constraintEqualToConstant:18],
        [pillBadge.heightAnchor  constraintEqualToConstant:18],

        [pillText.leadingAnchor  constraintEqualToAnchor:pillBadge.trailingAnchor constant:6],
        [pillText.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-10],
        [pillText.centerYAnchor  constraintEqualToAnchor:pill.centerYAnchor],

        [closeBtn.centerYAnchor  constraintEqualToAnchor:pill.centerYAnchor],
        [closeBtn.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16],
        [closeBtn.widthAnchor    constraintEqualToConstant:32],
        [closeBtn.heightAnchor   constraintEqualToConstant:32],

        [titleLabel.topAnchor      constraintEqualToAnchor:pill.bottomAnchor constant:24],
        [titleLabel.leadingAnchor  constraintEqualToAnchor:g.leadingAnchor constant:20],
        [titleLabel.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-20],

        [channelLabel.topAnchor      constraintEqualToAnchor:titleLabel.bottomAnchor constant:6],
        [channelLabel.leadingAnchor  constraintEqualToAnchor:titleLabel.leadingAnchor],
        [channelLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],

        [playbackRow.topAnchor      constraintEqualToAnchor:channelLabel.bottomAnchor constant:36],
        [playbackRow.leadingAnchor  constraintEqualToAnchor:g.leadingAnchor constant:20],
        [playbackRow.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-20],

        [tileGrid.topAnchor      constraintEqualToAnchor:playbackRow.bottomAnchor constant:34],
        [tileGrid.leadingAnchor  constraintEqualToAnchor:g.leadingAnchor constant:12],
        [tileGrid.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12],
        [tileGrid.bottomAnchor constraintLessThanOrEqualToAnchor:g.bottomAnchor constant:-18],
    ]];
}

- (NSString *)rateString:(float)r {
    // Trim trailing zeros: 1.00 -> 1, 0.25 -> 0.25, 1.50 -> 1.5.
    if (fabsf(r - roundf(r)) < 0.001f) return [NSString stringWithFormat:@"%.0f", r];
    if (fabsf(r * 10.0f - roundf(r * 10.0f)) < 0.01f) return [NSString stringWithFormat:@"%.1f", r];
    return [NSString stringWithFormat:@"%.2f", r];
}

- (void)refreshPlayPauseIcon {
    BOOL playing = NO;
    @try {
        id pvc = self.playerVC;
        if ([pvc respondsToSelector:@selector(playerState)]) {
            long state = ((long (*)(id, SEL))objc_msgSend)(pvc, @selector(playerState));
            // YT playerState: 2/3 = playing variants, 4 = paused. Heuristic.
            playing = (state == 2 || state == 3);
        }
    } @catch (id ex) {}
    UIImage *img = YTAGPCSymbol(playing ? @"pause.fill" : @"play.fill", 42.0, UIImageSymbolWeightRegular);
    [self.playPauseButton setImage:[img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                          forState:UIControlStateNormal];
}

- (void)refreshSpeedTile {
    UILabel *txt = (UILabel *)[self.speedTile viewWithTag:1003];
    if ([txt isKindOfClass:[UILabel class]]) {
        txt.text = [NSString stringWithFormat:@"%@x", [self rateString:_currentPlaybackRate]];
    }
}

- (void)refreshStableVolumeTile {
    UIView *circle = [self.stableVolumeTile viewWithTag:1001];
    UIImageView *iv = (UIImageView *)[self.stableVolumeTile viewWithTag:1002];
    if (self.stableVolumeEnabled) {
        circle.backgroundColor = (themeColor(@"theme_accent") ?: [UIColor colorWithRed:0.95 green:0.25 blue:0.25 alpha:1.0]);
        iv.tintColor = [UIColor whiteColor];
    } else {
        circle.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
        iv.tintColor = [UIColor whiteColor];
    }
}

// --- Handlers ---

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)prevTapped {
    id pvc = self.playerVC;
    if ([pvc respondsToSelector:@selector(replayWithSeekSource:)]) {
        // seekSource 0 = user.
        ((void (*)(id, SEL, int))objc_msgSend)(pvc, @selector(replayWithSeekSource:), 0);
        YTAGLog(@"premium-ctrl", @"restart tapped");
    }
}

- (void)back10Tapped {
    id pvc = self.playerVC;
    if ([pvc respondsToSelector:@selector(didPressRewindWithTimeInterval:)]) {
        ((void (*)(id, SEL, double))objc_msgSend)(pvc, @selector(didPressRewindWithTimeInterval:), 10.0);
        YTAGLog(@"premium-ctrl", @"-10s tapped");
    }
}

- (void)playPauseTapped {
    id pvc = self.playerVC;
    if ([pvc respondsToSelector:@selector(didTogglePlayPause)]) {
        [pvc performSelector:@selector(didTogglePlayPause)];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self refreshPlayPauseIcon];
    });
    YTAGLog(@"premium-ctrl", @"play/pause tapped");
}

- (void)fwd10Tapped {
    id pvc = self.playerVC;
    if ([pvc respondsToSelector:@selector(didPressFastForwardWithTimeInterval:)]) {
        ((void (*)(id, SEL, double))objc_msgSend)(pvc, @selector(didPressFastForwardWithTimeInterval:), 10.0);
        YTAGLog(@"premium-ctrl", @"+10s tapped");
    }
}

- (void)nextTapped {
    id pvc = self.playerVC;
    if ([pvc respondsToSelector:@selector(skipToUpcomingPlayback)]) {
        [pvc performSelector:@selector(skipToUpcomingPlayback)];
        YTAGLog(@"premium-ctrl", @"next-video tapped");
    }
}

- (void)downloadTapped {
    // Dismiss this sheet, then surface the existing YTAG download action sheet.
    UIView *anchor = self.anchorView;
    [self dismissViewControllerAnimated:YES completion:^{
        if ([anchor isKindOfClass:[UIButton class]]) {
            // Trigger download flow via a synthetic tap on the anchor we remembered.
            [YTAGDownloadTrigger handleDownloadTap:(UIButton *)anchor];
        }
    }];
    YTAGLog(@"premium-ctrl", @"download tapped");
}

- (void)speedTapped {
    NSArray *rates = @[@0.25, @0.5, @0.75, @1.0, @1.25, @1.5, @1.75, @2.0, @2.25, @2.5, @3.0, @3.5, @4.0, @4.5, @5.0];
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Playback speed"
                                                                message:nil
                                                         preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSNumber *r in rates) {
        float rate = r.floatValue;
        NSString *label = [NSString stringWithFormat:@"%@x", [self rateString:rate]];
        if (fabsf(rate - _currentPlaybackRate) < 0.01f) label = [label stringByAppendingString:@"  ✓"];
        [ac addAction:[UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
            id pvc = self.playerVC;
            if ([pvc respondsToSelector:@selector(setPlaybackRate:)]) {
                ((void (*)(id, SEL, float))objc_msgSend)(pvc, @selector(setPlaybackRate:), rate);
            }
            self.currentPlaybackRate = rate;
            [self refreshSpeedTile];
            YTAGLog(@"premium-ctrl", @"speed -> %@", label);
        }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    ac.popoverPresentationController.sourceView = self.speedTile;
    ac.popoverPresentationController.sourceRect = self.speedTile.bounds;
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)stableVolumeTapped {
    id pvc = self.playerVC;
    BOOL newVal = !self.stableVolumeEnabled;
    if ([pvc respondsToSelector:@selector(setAudioDRCEnabled:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(pvc, @selector(setAudioDRCEnabled:), newVal);
    }
    self.stableVolumeEnabled = newVal;
    [self refreshStableVolumeTile];
    YTAGLog(@"premium-ctrl", @"stable volume -> %@", newVal ? @"ON" : @"OFF");
}

- (void)muteTapped {
    id pvc = self.playerVC;
    id video = nil;
    if ([pvc respondsToSelector:@selector(activeVideo)]) {
        video = ((id (*)(id, SEL))objc_msgSend)(pvc, @selector(activeVideo));
    }
    if (![video respondsToSelector:@selector(setMuted:)]) {
        [self showHUD:@"Mute is unavailable right now"];
        return;
    }
    BOOL newMuted = !self.muted;
    [[NSUserDefaults standardUserDefaults] setBool:newMuted forKey:@"YouMuteKeepMuted"];
    ((void (*)(id, SEL, BOOL))objc_msgSend)(video, @selector(setMuted:), newMuted);
    self.muted = newMuted;
    YTAGPCUpdateTile(self.muteTile,
                     newMuted ? @"speaker.slash" : @"speaker.wave.2",
                     newMuted ? @"Unmute" : @"Mute",
                     newMuted);
    YTAGLog(@"premium-ctrl", @"mute -> %@", newMuted ? @"ON" : @"OFF");
}

- (void)copyLinkTapped {
    NSString *videoID = nil;
    id pvc = self.playerVC;
    if ([pvc respondsToSelector:@selector(contentVideoID)]) {
        videoID = [pvc performSelector:@selector(contentVideoID)];
    }
    if (videoID.length == 0) {
        [self showHUD:@"No video link available"];
        return;
    }
    [UIPasteboard generalPasteboard].string = [NSString stringWithFormat:@"https://youtu.be/%@", videoID];
    [self showHUD:@"Copied link"];
    YTAGLog(@"premium-ctrl", @"copied link %@", videoID);
}

- (void)lockTapped {
    id overlayVC = YTAGPCOverlayVCFromAnchor(self.anchorView);
    if (![overlayVC respondsToSelector:@selector(lockModeStateEntityController)]) {
        [self showHUD:@"Lock is unavailable right now"];
        return;
    }
    id lockCtl = ((id (*)(id, SEL))objc_msgSend)(overlayVC, @selector(lockModeStateEntityController));
    if (!lockCtl || ![lockCtl respondsToSelector:@selector(setLockModeActive:)]) {
        [self showHUD:@"Lock is unavailable right now"];
        return;
    }

    BOOL newLocked = !self.locked;
    if (newLocked && [overlayVC respondsToSelector:@selector(lockModeDidRequestShowFullscreen)]) {
        ((void (*)(id, SEL))objc_msgSend)(overlayVC, @selector(lockModeDidRequestShowFullscreen));
        lockCtl = ((id (*)(id, SEL))objc_msgSend)(overlayVC, @selector(lockModeStateEntityController));
    }
    if ([lockCtl respondsToSelector:@selector(setLockModeActive:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(lockCtl, @selector(setLockModeActive:), newLocked);
    }
    self.locked = newLocked;
    YTAGPCUpdateTile(self.lockTile,
                     newLocked ? @"lock.fill" : @"lock.open",
                     newLocked ? @"Unlock" : @"Lock",
                     newLocked);
    YTAGLog(@"premium-ctrl", @"lock -> %@", newLocked ? @"ON" : @"OFF");
}

- (void)showHUD:(NSString *)message {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:ac animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [ac dismissViewControllerAnimated:YES completion:nil];
        });
    }];
}

@end

// --- Public trigger (called from the overlay row's "Controls" button) ---

@interface YTAGPremiumControlsTrigger : NSObject
+ (void)handleControlsTap:(UIButton *)sender playerVC:(id)playerVC anchorDownloadButton:(UIView *)anchor;
@end

@implementation YTAGPremiumControlsTrigger

+ (void)handleControlsTap:(UIButton *)sender playerVC:(id)playerVC anchorDownloadButton:(UIView *)anchor {
    if (!playerVC) {
        YTAGLog(@"premium-ctrl", @"no player VC — aborting");
        return;
    }
    UIResponder *r = sender.nextResponder;
    UIViewController *presenter = nil;
    while (r) {
        if ([r isKindOfClass:[UIViewController class]]) { presenter = (UIViewController *)r; break; }
        r = r.nextResponder;
    }
    // Walk up past the overlay VC to find a presenter that won't be yanked out from
    // under us when YT toggles the overlay hidden.
    while (presenter.presentingViewController == nil && presenter.parentViewController) {
        presenter = presenter.parentViewController;
    }
    if (!presenter) presenter = YTAGPCTopPresenter();
    if (!presenter) {
        YTAGLog(@"premium-ctrl", @"no presenting VC from sender");
        return;
    }
    YTAGPremiumControlsSheet *sheet = [[YTAGPremiumControlsSheet alloc] initWithPlayerVC:playerVC anchorView:anchor];
    [presenter presentViewController:sheet animated:YES completion:nil];
    YTAGLog(@"premium-ctrl", @"sheet presented from %@", NSStringFromClass([presenter class]));
}

@end
