#import "YTAfterglow.h"
#import <QuartzCore/QuartzCore.h>

// Theme color keys
static NSString *const kThemeOverlayButtons = @"theme_overlayButtons";
static NSString *const kThemeTabBarIcons    = @"theme_tabBarIcons";
static NSString *const kThemeSeekBar        = @"theme_seekBar";
static NSString *const kThemeBackground     = @"theme_background";
static NSString *const kThemeTextPrimary    = @"theme_textPrimary";
static NSString *const kThemeTextSecondary  = @"theme_textSecondary";
static NSString *const kThemeNavBar         = @"theme_navBar";
static NSString *const kThemeAccent         = @"theme_accent";
static NSString *const kThemeGradientStart  = @"theme_gradientStart";
static NSString *const kThemeGradientEnd    = @"theme_gradientEnd";
static NSString *const kThemeGlowEnabled    = @"theme_glowEnabled";

// Thread-safe color cache
static NSMutableDictionary *colorCache = nil;
static dispatch_queue_t cacheQueue = nil;

__attribute__((constructor)) static void initCacheQueue() {
    cacheQueue = dispatch_queue_create("com.ytafterglow.colorcache", DISPATCH_QUEUE_CONCURRENT);
    colorCache = [NSMutableDictionary dictionary];
}

static UIColor *themeColor(NSString *key) {
    if (!cacheQueue || !colorCache) return nil;

    __block id cached = nil;
    __block BOOL found = NO;
    dispatch_sync(cacheQueue, ^{
        cached = colorCache[key];
        found = (cached != nil);
    });
    if (found) return (cached == [NSNull null]) ? nil : (UIColor *)cached;

    // Cache miss — decode from user defaults
    NSData *data = [[YTAGUserDefaults standardUserDefaults] objectForKey:key];
    if (!data) {
        dispatch_barrier_async(cacheQueue, ^{ colorCache[key] = [NSNull null]; });
        return nil;
    }
    NSKeyedUnarchiver *u = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:nil];
    [u setRequiresSecureCoding:NO];
    UIColor *color = [u decodeObjectForKey:NSKeyedArchiveRootObjectKey];

    dispatch_barrier_async(cacheQueue, ^{ colorCache[key] = color ?: [NSNull null]; });
    return color;
}

void ytag_clearThemeCache(void) {
    if (cacheQueue && colorCache)
        dispatch_barrier_async(cacheQueue, ^{ [colorCache removeAllObjects]; });
}

// Helper: return custom color with alpha variant, or original
static inline UIColor *themed(NSString *key, CGFloat alpha) {
    UIColor *c = themeColor(key);
    if (!c) return nil;
    return alpha < 1.0 ? [c colorWithAlphaComponent:alpha] : c;
}

static inline BOOL ytag_themeGlowEnabled(void) {
    return [[YTAGUserDefaults standardUserDefaults] boolForKey:kThemeGlowEnabled];
}

static inline BOOL ytag_themeGradientEnabled(void) {
    return themeColor(kThemeGradientStart) && themeColor(kThemeGradientEnd);
}

static UIColor *ytag_surfaceBackgroundColor(CGFloat fallbackAlpha) {
    UIColor *background = themeColor(kThemeBackground);
    if (!background) return nil;
    if (!ytag_themeGradientEnabled()) return background;
    return [background colorWithAlphaComponent:fallbackAlpha];
}

static void ytag_applyGlowToLayer(CALayer *layer, UIColor *color, CGFloat opacity, CGFloat radius) {
    if (!layer) return;

    if (!ytag_themeGlowEnabled() || !color) {
        layer.shadowOpacity = 0.0;
        layer.shadowRadius = 0.0;
        return;
    }

    layer.masksToBounds = NO;
    layer.shadowColor = color.CGColor;
    layer.shadowOffset = CGSizeZero;
    layer.shadowOpacity = opacity;
    layer.shadowRadius = radius;
    layer.shouldRasterize = YES;
    layer.rasterizationScale = UIScreen.mainScreen.scale;
}

#pragma mark - YTCommonColorPalette

%hook YTCommonColorPalette

// --- Text ---
- (UIColor *)textPrimary          { return themed(kThemeTextPrimary, 1.0) ?: %orig; }
- (UIColor *)textSecondary        { return themed(kThemeTextSecondary, 1.0) ?: %orig; }
- (UIColor *)textDisabled         { return themed(kThemeTextSecondary, 0.4) ?: %orig; }
- (UIColor *)textPrimaryInverse   { return themed(kThemeTextPrimary, 1.0) ?: %orig; }

// --- Overlay (player controls) ---
- (UIColor *)overlayTextPrimary      { return themed(kThemeOverlayButtons, 1.0) ?: %orig; }
- (UIColor *)overlayTextSecondary    { return themed(kThemeOverlayButtons, 0.8) ?: %orig; }
- (UIColor *)overlayIconActiveOther  { return themed(kThemeOverlayButtons, 1.0) ?: %orig; }
- (UIColor *)overlayIconInactive     { return themed(kThemeOverlayButtons, 0.7) ?: %orig; }
- (UIColor *)overlayIconDisabled     { return themed(kThemeOverlayButtons, 0.3) ?: %orig; }
- (UIColor *)overlayFilledButtonActive { return themed(kThemeOverlayButtons, 0.2) ?: %orig; }

// --- Icons (tab bar + general) ---
- (UIColor *)iconActive          { return themed(kThemeTabBarIcons, 1.0) ?: %orig; }
- (UIColor *)iconActiveOther     { return themed(kThemeTabBarIcons, 1.0) ?: %orig; }
- (UIColor *)iconInactive        { return themed(kThemeTabBarIcons, 0.5) ?: %orig; }
- (UIColor *)iconDisabled        { return themed(kThemeTabBarIcons, 0.3) ?: %orig; }
- (UIColor *)brandIconActive     { return themed(kThemeTabBarIcons, 1.0) ?: %orig; }
- (UIColor *)brandIconInactive   { return themed(kThemeTabBarIcons, 0.5) ?: %orig; }

// --- Backgrounds ---
- (UIColor *)background1             { return ytag_surfaceBackgroundColor(0.82) ?: %orig; }
- (UIColor *)background2             { return ytag_surfaceBackgroundColor(0.80) ?: %orig; }
- (UIColor *)background3             { return ytag_surfaceBackgroundColor(0.78) ?: %orig; }
- (UIColor *)baseBackground          { return ytag_surfaceBackgroundColor(0.86) ?: %orig; }
- (UIColor *)raisedBackground        { return ytag_surfaceBackgroundColor(0.88) ?: %orig; }
- (UIColor *)menuBackground          { return ytag_surfaceBackgroundColor(0.90) ?: %orig; }
- (UIColor *)generalBackgroundA      { return ytag_surfaceBackgroundColor(0.84) ?: %orig; }
- (UIColor *)generalBackgroundB      { return ytag_surfaceBackgroundColor(0.80) ?: %orig; }
- (UIColor *)brandBackgroundSolid    { return ytag_surfaceBackgroundColor(0.92) ?: %orig; }
- (UIColor *)brandBackgroundPrimary  { return ytag_surfaceBackgroundColor(0.86) ?: %orig; }
- (UIColor *)brandBackgroundSecondary { return ytag_surfaceBackgroundColor(0.82) ?: %orig; }

// --- Accent ---
- (UIColor *)callToAction        { return themed(kThemeAccent, 1.0) ?: %orig; }
- (UIColor *)callToActionInverse { return themed(kThemeAccent, 1.0) ?: %orig; }

// Force dark page style when a dark background is set
// This makes YouTube use light text/icons everywhere
- (NSInteger)pageStyle {
    // Check gradient start color first, then flat background
    UIColor *bg = themeColor(kThemeGradientStart) ?: themeColor(kThemeBackground);
    if (bg) {
        CGFloat r, g, b;
        [bg getRed:&r green:&g blue:&b alpha:nil];
        CGFloat luminance = 0.299 * r + 0.587 * g + 0.114 * b;
        if (luminance < 0.5) return 1; // dark
    }
    return %orig;
}

%end

#pragma mark - Seek/Progress Bar

%hook YTInlinePlayerBarContainerView
- (id)quietProgressBarColor {
    UIColor *c = themeColor(kThemeSeekBar);
    if (c) return c;
    if (ytagBool(@"redProgressBar")) return [UIColor redColor];
    return %orig;
}
%end

%hook YTSegmentableInlinePlayerBarView
- (void)setPlayedProgressBarColor:(id)color {
    UIColor *c = themeColor(kThemeSeekBar);
    %orig(c ?: color);
}
- (void)setBufferedProgressBarColor:(id)color {
    if (themeColor(kThemeSeekBar) || ytagBool(@"redProgressBar"))
        %orig([UIColor colorWithRed:0.65 green:0.65 blue:0.65 alpha:0.60]);
    else %orig(color);
}

- (void)layoutSubviews {
    %orig;
    UIColor *glowColor = themeColor(kThemeSeekBar) ?: themeColor(kThemeAccent);
    ytag_applyGlowToLayer(self.layer, glowColor, 0.85, 8.0);
}
%end

#pragma mark - Navigation Bar

%hook YTNavigationBar
- (void)setBackgroundColor:(UIColor *)color {
    UIColor *c = themeColor(kThemeNavBar);
    %orig(c ?: color);
}
- (void)setBarTintColor:(UIColor *)color {
    UIColor *c = themeColor(kThemeNavBar);
    %orig(c ?: color);
}
%end

#pragma mark - Material Design

%hook QTMColorGroup
- (UIColor *)accentColor          { return themed(kThemeAccent, 1.0) ?: %orig; }
- (UIColor *)brightAccentColor    { return themed(kThemeAccent, 1.0) ?: %orig; }
- (UIColor *)buttonBackgroundColor { return themed(kThemeAccent, 0.15) ?: %orig; }
- (UIColor *)bodyTextColor        { return themed(kThemeTextPrimary, 1.0) ?: %orig; }
- (UIColor *)lightBodyTextColor   { return themed(kThemeTextSecondary, 1.0) ?: %orig; }
%end

#pragma mark - Gradient Background

static CAGradientLayer *ytag_createGradient(CGRect bounds) {
    UIColor *start = themeColor(kThemeGradientStart);
    UIColor *end = themeColor(kThemeGradientEnd);
    if (!start || !end) return nil;

    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = bounds;
    gradient.colors = @[(id)start.CGColor, (id)end.CGColor];
    gradient.startPoint = CGPointMake(0.5, 0.0);
    gradient.endPoint = CGPointMake(0.5, 1.0);
    gradient.name = @"ytag_gradient";
    return gradient;
}

static void ytag_applyGradient(UIView *view) {
    if (!ytag_themeGradientEnabled()) return;

    // Remove existing gradient
    for (CALayer *layer in [view.layer.sublayers copy]) {
        if ([layer.name isEqualToString:@"ytag_gradient"]) [layer removeFromSuperlayer];
    }

    view.backgroundColor = [UIColor clearColor];
    view.opaque = NO;

    CAGradientLayer *gradient = ytag_createGradient(view.bounds);
    if (gradient) [view.layer insertSublayer:gradient atIndex:0];
}

// Apply gradient to the main app view
%hook YTAppView
- (void)layoutSubviews {
    %orig;
    ytag_applyGradient((UIView *)self);
}
%end

// Make collection views transparent so gradient shows through
%hook YTAsyncCollectionView
- (void)layoutSubviews {
    %orig;
    if (ytag_themeGradientEnabled()) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
    }
}
%end

%hook UIScrollView
- (void)didMoveToWindow {
    %orig;
    if (!ytag_themeGradientEnabled()) return;
    if ([self isKindOfClass:[UITableView class]] || [self isKindOfClass:[UICollectionView class]]) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
    }
}
%end

%hook YTPivotBarItemView
- (void)layoutSubviews {
    %orig;

    UIColor *glowColor = themeColor(kThemeAccent) ?: themeColor(kThemeTabBarIcons);
    CALayer *targetLayer = self.navigationButton ? self.navigationButton.layer : self.layer;
    CGFloat opacity = self.navigationButton.alpha > 0.9 ? 0.40 : 0.16;
    ytag_applyGlowToLayer(targetLayer, glowColor, opacity, 7.0);
}
%end

static void ytag_applyGlowToButtonsInView(UIView *view, UIColor *color) {
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:%c(YTQTMButton)] || [subview isKindOfClass:[UIButton class]]) {
            ytag_applyGlowToLayer(subview.layer, color, 0.32, 6.0);
        }
        if (subview.subviews.count > 0) ytag_applyGlowToButtonsInView(subview, color);
    }
}

%hook YTMainAppVideoPlayerOverlayView
- (void)layoutSubviews {
    %orig;
    ytag_applyGlowToButtonsInView(self, themeColor(kThemeAccent) ?: themeColor(kThemeOverlayButtons));
}
%end
