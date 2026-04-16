#import "YTAfterglow.h"
#import <UIKit/UIImage+Private.h>
#import <UIKit/UIImageAsset+Private.h>
#import <YouTubeHeader/ASImageNodeDrawParameters.h>
#import <YouTubeHeader/_ASDisplayView.h>
#import <YouTubeHeader/ELMContainerNode.h>
#import <YouTubeHeader/ELMNodeController.h>
#import <YouTubeHeader/UIColor+YouTube.h>
#import <YouTubeHeader/UIImage+YouTube.h>
#import <YouTubeHeader/YTInlineMutedPlaybackScrubberView.h>
#import <YouTubeHeader/YTInlineMutedPlaybackScrubbingSlider.h>
#import <YouTubeHeader/YTIPlayerBarDecorationModel.h>
#import <YouTubeHeader/YTMainAppVideoPlayerOverlayViewController.h>
#import <YouTubeHeader/YTPlayerBarController.h>
#import <YouTubeHeader/YTPlayerBarRectangleDecorationView.h>
#import <YouTubeHeader/YTPlayerBarScrubberDotDecorationController.h>
#import <YouTubeHeader/YTPlayerBarScrubberDotDecorationView.h>
#import <YouTubeHeader/YTPlayerBarSegmentView.h>
#import <YouTubeHeader/YTSegmentableInlinePlayerBarView.h>

// Additional keys owned by SeekBar
static NSString *const kThemeSeekBar              = @"theme_seekBar";
static NSString *const kThemeSeekBarLive          = @"theme_seekBarLive";
static NSString *const kThemeSeekBarScrubber      = @"theme_seekBarScrubber";
static NSString *const kThemeSeekBarScrubberLive  = @"theme_seekBarScrubberLive";
static NSString *const kSeekBarScrubberImage      = @"seekBarScrubberImage";    // NSData (PNG)
static NSString *const kSeekBarScrubberSize       = @"seekBarScrubberSize";     // integer 0-100
static NSString *const kSeekBarAnimated           = @"seekBarAnimated";         // bool

#define YTAG_DEFAULT_SCRUBBER_SIZE   12
#define YTAG_YOUTUBE_SCRUBBER_SCALE  6

#define YTAG_PLAYER_BAR_MODE_LIVE     4
#define YTAG_PLAYER_BAR_MODE_LIVE_VDR 5
#define YTAG_PLAYER_BAR_OVERLAY_MODE_DEFAULT 0

@interface YTModularPlayerBarView : UIView
@property (retain, nonatomic) UIImageView *ytagScrubberImageView;
@end

@interface YTSegmentableInlinePlayerBarView (YTAG)
@property (retain, nonatomic) UIImageView *ytagScrubberImageView;
- (BOOL)isVideoModeLive;
@end

@interface YTInlinePlayerBarView : UIView
@property (retain, nonatomic) UIImageView *ytagScrubberImageView;
@end

@interface YTColor : NSObject
+ (BOOL)cairoRefreshSignatureMomentsEnabled;
@end

@interface YTProgressView : UIView
@end

@interface YTBrandGradientImageProcessor : NSObject
@end

@interface YTModularPlayerBarController : NSObject
@property (nonatomic, readonly) UIView *view;
@end

@interface YTInlinePlayerBarContainerView (YTAG)
@property (nonatomic, readonly) id modularPlayerBar;
@property (nonatomic, readonly) id segmentablePlayerBar;
@property (nonatomic, readonly) UIView *playerBar;
@end

#pragma mark - Helpers

static UIImage *seekBarCustomScrubberImage(void) {
    id raw = [[YTAGUserDefaults standardUserDefaults] objectForKey:kSeekBarScrubberImage];
    if (![raw isKindOfClass:[NSData class]]) return nil;
    NSData *data = (NSData *)raw;
    if (data.length == 0) return nil;
    return [UIImage imageWithData:data];
}

static BOOL seekBarCustomImageEnabled(void) {
    return seekBarCustomScrubberImage() != nil;
}

static BOOL seekBarAnimationsEnabled(void) {
    return ytagBool(kSeekBarAnimated);
}

static BOOL seekBarHasColor(void) {
    return themeColor(kThemeSeekBar) != nil || ytagBool(@"redProgressBar");
}

static UIColor *seekBarSliderColor(BOOL live) {
    if (live) {
        UIColor *c = themeColor(kThemeSeekBarLive);
        if (c) return c;
    }
    UIColor *base = themeColor(kThemeSeekBar);
    if (base) return base;
    if (ytagBool(@"redProgressBar")) return [UIColor redColor];
    return nil;
}

static UIColor *seekBarScrubberColor(BOOL live) {
    if (live) {
        UIColor *c = themeColor(kThemeSeekBarScrubberLive);
        if (c) return c;
    }
    UIColor *base = themeColor(kThemeSeekBarScrubber);
    if (base) return base;
    // If user hasn't set a scrubber-specific color, fall back to slider color.
    return seekBarSliderColor(live);
}

static BOOL seekBarIsLiveMode(NSInteger mode) {
    return mode == YTAG_PLAYER_BAR_MODE_LIVE || mode == YTAG_PLAYER_BAR_MODE_LIVE_VDR;
}

static CGFloat seekBarBaseScrubberScale(void) {
    int scrubberSize = (int)ytagInt(kSeekBarScrubberSize);
    if (scrubberSize == 0 && !seekBarCustomImageEnabled()) return -1;
    return 1 + (scrubberSize / 100.0);
}

static void seekBarUpdateScrubberSize(UIView *scrubberCircle, CGFloat scale) {
    if (scrubberCircle == nil) return;
    CGRect frame = scrubberCircle.frame;
    CGFloat size = YTAG_DEFAULT_SCRUBBER_SIZE * scale;
    if (!seekBarCustomImageEnabled())
        size /= YTAG_YOUTUBE_SCRUBBER_SCALE;
    scrubberCircle.frame = CGRectMake(frame.origin.x, frame.origin.y, size, size);
    if (!seekBarCustomImageEnabled())
        scrubberCircle.layer.cornerRadius = size / 2.0;
}

static UIView *seekBarScrubberCircle(UIView *view) {
    @try {
        UIView *c = [view valueForKey:@"_scrubberCircle"];
        if (c) return c;
    } @catch (id ex) {}
    @try {
        NSMutableDictionary *decorationCollections = [view valueForKey:@"_decorationCollections"];
        id scrubberDotCollection = decorationCollections[@"modular_player_bar_scrubber_dot_collection_key"];
        id scrubberDotView = [scrubberDotCollection firstObject];
        return [scrubberDotView valueForKey:@"scrubberDot"];
    } @catch (id ex) {}
    return nil;
}

static BOOL seekBarViewIsLive(UIView *view) {
    if ([view respondsToSelector:@selector(isVideoModeLive)]) {
        return ((BOOL (*)(id, SEL))objc_msgSend)(view, @selector(isVideoModeLive));
    }
    return NO;
}

static void seekBarInitScrubberCircleBase(UIView *scrubberCircle, BOOL setColor) {
    if (scrubberCircle == nil) return;
    CGFloat scale = seekBarBaseScrubberScale();
    if (scale == -1) return;
    seekBarUpdateScrubberSize(scrubberCircle, scale);
    if (!setColor) return;
    if (seekBarCustomImageEnabled()) {
        scrubberCircle.backgroundColor = nil;
        return;
    }
    UIColor *color = seekBarScrubberColor(NO);
    if (color) scrubberCircle.backgroundColor = color;
}

static void seekBarInitScrubberCircle(UIView *view, BOOL setColor) {
    seekBarInitScrubberCircleBase(seekBarScrubberCircle(view), setColor);
}

static CGPoint seekBarScrubberCenter(UIView *view) {
    UIView *c = seekBarScrubberCircle(view);
    return c ? c.center : CGPointZero;
}

static void seekBarUpdateScrubberColorAndPosition(UIView *view, BOOL alterScrubber, CGPoint originalCenter) {
    UIView *scrubberCircle = seekBarScrubberCircle(view);
    if (scrubberCircle == nil) return;
    if (alterScrubber) {
        if (seekBarCustomImageEnabled()) {
            scrubberCircle.backgroundColor = nil;
        } else {
            UIColor *color = seekBarScrubberColor(seekBarViewIsLive(view));
            if (color) scrubberCircle.backgroundColor = color;
        }
    }
    if (!seekBarAnimationsEnabled() || CGPointEqualToPoint(originalCenter, CGPointZero)) return;
    CGPoint newCenter = scrubberCircle.center;
    scrubberCircle.center = originalCenter;
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveLinear animations:^{
        scrubberCircle.center = newCenter;
    } completion:nil];
}

static CGFloat seekBarScrubberScaleValue(CGFloat scale) {
    if (!seekBarCustomImageEnabled()) return scale;
    return scale / YTAG_YOUTUBE_SCRUBBER_SCALE + 0.00001;
}

static void seekBarApplyCustomScrubberIcon(id bar, UIView *scrubberCircle) {
    UIImageView *imageView = [bar valueForKey:@"ytagScrubberImageView"];
    if (scrubberCircle == nil) {
        @try {
            scrubberCircle = [bar valueForKey:@"_scrubberCircle"];
        } @catch (id ex) {}
    }
    if (seekBarCustomImageEnabled()) {
        UIImage *image = seekBarCustomScrubberImage();
        if (!image) return;
        [imageView removeFromSuperview];
        UIImageView *newImageView = [[UIImageView alloc] initWithImage:image];
        newImageView.contentMode = UIViewContentModeScaleAspectFit;
        CGFloat scale = seekBarBaseScrubberScale();
        CGFloat size = YTAG_DEFAULT_SCRUBBER_SIZE * scale;
        newImageView.frame = CGRectMake(0, 0, size, size);
        [bar setValue:newImageView forKey:@"ytagScrubberImageView"];
        if (scrubberCircle) {
            scrubberCircle.backgroundColor = [UIColor clearColor];
            [scrubberCircle addSubview:newImageView];
        }
    } else {
        [imageView removeFromSuperview];
        [bar setValue:nil forKey:@"ytagScrubberImageView"];
        seekBarUpdateScrubberColorAndPosition(bar, YES, CGPointZero);
    }
}

static void seekBarFindViewAndSetScrubberIcon(YTMainAppVideoPlayerOverlayViewController *self) {
    YTInlinePlayerBarContainerView *playerBar = nil;
    @try {
        playerBar = [[self playerBarController] playerBar];
    } @catch (id ex) {}
    if (playerBar == nil) return;

    id view = nil;
    if ([playerBar respondsToSelector:@selector(modularPlayerBar)]) {
        id modular = [playerBar modularPlayerBar];
        view = [modular valueForKey:@"view"];
        @try {
            id scrubberDotController = [playerBar valueForKey:@"_scrubberDotDecorationController"];
            if (scrubberDotController) {
                id scrubberDotView = [scrubberDotController valueForKey:@"scrubberDot"];
                UIView *scrubberCircle = [scrubberDotView valueForKey:@"scrubberDot"];
                if (view && scrubberCircle) {
                    seekBarApplyCustomScrubberIcon(view, scrubberCircle);
                    return;
                }
            }
        } @catch (id ex) {}
    } else if ([playerBar respondsToSelector:@selector(segmentablePlayerBar)]) {
        id seg = [playerBar segmentablePlayerBar];
        if (seg) {
            if ([seg isKindOfClass:%c(YTModularPlayerBarController)])
                view = [(YTModularPlayerBarController *)seg view];
            else
                view = seg;
        } else {
            view = [playerBar playerBar];
        }
    } else {
        view = [playerBar playerBar];
    }
    if (view) seekBarApplyCustomScrubberIcon(view, nil);
}

#pragma mark - Modern modular player bar

%hook YTModularPlayerBarView

%property (retain, nonatomic) UIImageView *ytagScrubberImageView;

- (id)initWithModel:(id)model delegate:(id)delegate {
    self = %orig;
    if (self) seekBarInitScrubberCircle(self, NO);
    return self;
}

- (void)transformScrubberScale:(CGFloat)scale {
    %orig(seekBarScrubberScaleValue(scale));
}

- (void)setCustomScrubberIcon:(UIImage *)image {
    if (seekBarCustomImageEnabled()) return;
    %orig;
}

- (void)maybeSetDefaultScrubberBackgroundColor {
    %orig;
    UIView *scrubberCircle = seekBarScrubberCircle(self);
    if (scrubberCircle == nil) return;
    if (seekBarCustomImageEnabled()) {
        scrubberCircle.backgroundColor = [UIColor clearColor];
        return;
    }
    UIColor *color = seekBarScrubberColor(NO);
    if (color) scrubberCircle.backgroundColor = color;
}

- (void)layoutSubviews {
    CGPoint center = seekBarScrubberCenter(self);
    %orig;
    seekBarUpdateScrubberColorAndPosition(self, NO, center);
}

%end

#pragma mark - Legacy segmentable player bar

%hook YTSegmentableInlinePlayerBarView

%property (retain, nonatomic) UIImageView *ytagScrubberImageView;

- (id)init {
    self = %orig;
    if (self) seekBarInitScrubberCircle(self, NO);
    return self;
}

- (void)transformScrubberScale:(CGFloat)scale {
    %orig(seekBarScrubberScaleValue(scale));
}

- (void)setMode:(int)mode {
    %orig;
    seekBarUpdateScrubberColorAndPosition(self, YES, CGPointZero);
}

- (void)resetPlayerBarModeColors {
    %orig;
    UIColor *color = seekBarSliderColor([self isVideoModeLive]);
    if (color) {
        [self setValue:color forKey:@"_progressBarColor"];
        [self setValue:color forKey:@"_userIsScrubbingProgressBarColor"];
    }
    seekBarUpdateScrubberColorAndPosition(self, YES, CGPointZero);
}

- (void)setPlayedProgressBarColor:(id)color {
    UIColor *c = seekBarSliderColor([self isVideoModeLive]);
    %orig(c ?: color);
}

- (void)setBufferedProgressBarColor:(id)color {
    if (seekBarHasColor())
        %orig([UIColor colorWithRed:0.65 green:0.65 blue:0.65 alpha:0.60]);
    else
        %orig(color);
}

- (void)layoutSubviews {
    CGPoint center = seekBarScrubberCenter(self);
    %orig;
    seekBarUpdateScrubberColorAndPosition(self, NO, center);
}

%end

#pragma mark - Older inline player bar

%hook YTInlinePlayerBarView

%property (retain, nonatomic) UIImageView *ytagScrubberImageView;

- (id)init {
    self = %orig;
    if (self) seekBarInitScrubberCircle(self, YES);
    return self;
}

- (void)transformScrubberScale:(CGFloat)scale {
    %orig(seekBarScrubberScaleValue(scale));
}

- (void)setMode:(int)mode {
    %orig;
    seekBarUpdateScrubberColorAndPosition(self, YES, CGPointZero);
    UIColor *color = seekBarSliderColor(seekBarIsLiveMode(mode));
    if (color) {
        @try {
            UIView *playing = [self valueForKey:@"_playingProgress"];
            if ([playing isKindOfClass:[UIView class]]) playing.backgroundColor = color;
        } @catch (id ex) {}
    }
}

- (void)layoutSubviews {
    CGPoint center = seekBarScrubberCenter(self);
    %orig;
    seekBarUpdateScrubberColorAndPosition(self, NO, center);
}

%end

#pragma mark - Chapter segments

%hook YTPlayerBarSegmentView

- (void)drawHighlightedChapter:(CGRect)rect {
    void (^animated)(void) = ^{
        %orig;
        UIColor *color = seekBarSliderColor(NO);
        if (!color) return;
        CGFloat playingProgress = 0.0;
        @try {
            playingProgress = [[self valueForKey:@"_playingProgress"] doubleValue];
        } @catch (id ex) {}
        CGRect fillRect = CGRectMake(0, 0, rect.size.width * playingProgress, rect.size.height);
        [color setFill];
        UIRectFill(fillRect);
    };
    if (seekBarAnimationsEnabled()) {
        [UIView transitionWithView:self duration:0.2
            options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionCurveLinear
            animations:animated completion:nil];
    } else {
        animated();
    }
}

- (void)drawUnhighlightedChapter:(CGRect)rect {
    void (^animated)(void) = ^{
        %orig;
        UIColor *color = seekBarSliderColor(NO);
        if (!color) return;
        CGFloat playingProgress = 0.0;
        @try {
            playingProgress = [[self valueForKey:@"_playingProgress"] doubleValue];
        } @catch (id ex) {}
        CGRect fillRect = CGRectMake(0, 0, rect.size.width * playingProgress, rect.size.height);
        [color setFill];
        UIRectFill(fillRect);
    };
    if (seekBarAnimationsEnabled()) {
        [UIView transitionWithView:self duration:0.2
            options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionCurveLinear
            animations:animated completion:nil];
    } else {
        animated();
    }
}

%end

#pragma mark - YouTube color refresh suppression

%hook YTColor

+ (BOOL)cairoRefreshSignatureMomentsEnabled {
    return seekBarHasColor() ? NO : %orig;
}

%end

#pragma mark - Modular decoration rectangle (the played-portion painter)

%hook YTPlayerBarRectangleDecorationView

- (void)drawRectangleDecorationWithSideMasks:(CGRect)rect {
    if (!seekBarHasColor()) {
        %orig;
        return;
    }
    @try {
        YTIPlayerBarDecorationModel *model = [self valueForKey:@"_model"];
        NSInteger originalOverlayMode = model.playingState.overlayMode;
        model.playingState.overlayMode = YTAG_PLAYER_BAR_OVERLAY_MODE_DEFAULT;
        if ([model respondsToSelector:@selector(style)] && [[model valueForKey:@"style"] respondsToSelector:@selector(setGradientColor:)])
            [[model valueForKey:@"style"] setValue:nil forKey:@"gradientColor"];
        %orig;
        model.playingState.overlayMode = originalOverlayMode;
    } @catch (id ex) {
        %orig;
    }
}

- (void)drawProgressRect:(CGRect)rect withColor:(UIColor *)color {
    UIColor *targetColor = color;
    @try {
        YTIPlayerBarDecorationModel *model = [self valueForKey:@"_model"];
        BOOL isLive = seekBarIsLiveMode(model.playingState.mode);
        UIColor *override = seekBarSliderColor(isLive);
        if (override) targetColor = override;
    } @catch (id ex) {}
    if (seekBarAnimationsEnabled()) {
        [UIView transitionWithView:self duration:0.2
            options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionCurveLinear
            animations:^{ %orig(rect, targetColor); } completion:nil];
    } else {
        %orig(rect, targetColor);
    }
}

%end

#pragma mark - Overlay container: suppress default scrubber icon, drive custom-image install

%hook YTInlinePlayerBarContainerView

- (void)setCustomScrubberIcon:(UIImage *)image {
    if (seekBarCustomImageEnabled()) return;
    %orig;
}

%end

#pragma mark - Scrubber dot decoration (modular)

%hook YTPlayerBarScrubberDotDecorationView

- (id)initWithModel:(id)model {
    self = %orig;
    if (self) {
        @try {
            UIView *scrubberCircle = [self valueForKey:@"_defaultScrubberDot"];
            seekBarInitScrubberCircleBase(scrubberCircle, YES);
        } @catch (id ex) {}
    }
    return self;
}

- (UIView *)expectedScrubberDot {
    UIView *scrubberCircle = nil;
    @try {
        scrubberCircle = [self valueForKey:@"_defaultScrubberDot"];
    } @catch (id ex) {}
    if (!scrubberCircle) return %orig;
    if (!seekBarCustomImageEnabled()) {
        UIColor *color = seekBarScrubberColor(NO);
        if (color) scrubberCircle.backgroundColor = color;
    }
    return scrubberCircle;
}

- (void)transformScrubberScale:(CGFloat)scale {
    %orig(seekBarScrubberScaleValue(scale));
}

- (void)setCustomImageScrubberIcon:(UIImage *)image {
    if (seekBarCustomImageEnabled()) return;
    %orig;
}

- (void)updateFrameWithPlayerBarFrame:(CGRect)frame {
    if (seekBarAnimationsEnabled()) {
        [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveLinear
            animations:^{ %orig; } completion:nil];
    } else {
        %orig;
    }
}

%end

#pragma mark - Miniplayer / generic progress view

%hook YTProgressView

- (void)layoutSubviews {
    if (seekBarAnimationsEnabled()) {
        [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveLinear
            animations:^{ %orig; } completion:nil];
    } else {
        %orig;
    }
}

- (void)setProgressBarColor:(UIColor *)color {
    UIColor *c = seekBarSliderColor(NO);
    %orig(c ?: color);
}

- (void)setBrandGradientEnabled:(BOOL)enabled {
    %orig(seekBarHasColor() ? NO : enabled);
}

%end

#pragma mark - Muted playback (home feed auto-play)

%hook YTInlineMutedPlaybackScrubberView

- (void)addGradient {
    if (seekBarHasColor()) return;
    %orig;
}

- (void)initScrubberWithMode:(int)mode {
    %orig;
    if (mode == 0) return;
    @try {
        YTInlineMutedPlaybackScrubbingSlider *slider = [self valueForKey:@"_playingProgress"];
        UIColor *color = seekBarSliderColor(seekBarIsLiveMode(mode));
        if (color) {
            UIImage *tracked = slider.currentMinimumTrackImage;
            if (tracked) {
                UIImage *tinted = [tracked _flatImageWithColor:color];
                if (tinted) [slider setMinimumTrackImage:tinted forState:UIControlStateNormal];
            }
        }
    } @catch (id ex) {}
}

%end

%hook YTInlineMutedPlaybackScrubbingSlider

- (void)setThumbImage:(UIImage *)image forState:(UIControlState)state {
    NSString *accID = self.accessibilityIdentifier ?: @"";
    NSString *assetName = image.imageAsset.assetName ?: @"";
    if (![accID isEqualToString:@"id.player.scrubber.slider"] || [assetName isEqualToString:@"transparent"]) {
        %orig;
        return;
    }
    CGSize originalSize = image.size;
    if (seekBarCustomImageEnabled()) {
        UIImage *custom = seekBarCustomScrubberImage();
        if (custom) {
            originalSize = CGSizeMake(YTAG_DEFAULT_SCRUBBER_SIZE, YTAG_DEFAULT_SCRUBBER_SIZE);
            image = custom;
        }
    } else {
        UIColor *scrubberColor = seekBarScrubberColor(NO);
        if (scrubberColor) {
            UIImage *tinted = [image _flatImageWithColor:scrubberColor];
            if (tinted) image = tinted;
        }
    }
    CGFloat scale = seekBarBaseScrubberScale();
    if (scale != -1) {
        UIImage *scaled = [image yt_imageScaledToSize:CGSizeMake(originalSize.width * scale, originalSize.height * scale)];
        if (scaled) image = scaled;
    }
    %orig(image, state);
}

%end

#pragma mark - Driver: re-apply custom icon on watch-next response

%hook YTMainAppVideoPlayerOverlayViewController

- (void)setWatchNextResponse:(id)response loading:(BOOL)loading {
    seekBarFindViewAndSetScrubberIcon(self);
    %orig;
}

- (void)setWatchNextResponse:(id)response {
    seekBarFindViewAndSetScrubberIcon(self);
    %orig;
}

%end

#pragma mark - Brand gradient suppression

%hook YTBrandGradientImageProcessor

- (void)willDrawInContext:(CGContextRef)ctx drawParameters:(ASImageNodeDrawParameters *)drawParameters {
    if (seekBarHasColor()) {
        UIColor *color = seekBarSliderColor(NO);
        if (color) {
            CGRect totalRect = CGContextGetClipBoundingBox(ctx);
            CGRect progressRect = CGRectIntersection([drawParameters drawRect], totalRect);
            CGContextSetFillColorWithColor(ctx, color.CGColor);
            CGContextFillRect(ctx, progressRect);
            return;
        }
    }
    %orig;
}

%end
