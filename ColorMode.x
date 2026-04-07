#import "YTLite.h"
#import <objc/runtime.h>
#import <substrate.h>

// Theme color keys
static NSString *const kThemeOverlayButtons = @"theme_overlayButtons";
static NSString *const kThemeTabBarIcons    = @"theme_tabBarIcons";
static NSString *const kThemeSeekBar        = @"theme_seekBar";
static NSString *const kThemeBackground     = @"theme_background";
static NSString *const kThemeTextPrimary    = @"theme_textPrimary";
static NSString *const kThemeTextSecondary  = @"theme_textSecondary";
static NSString *const kThemeNavBar         = @"theme_navBar";
static NSString *const kThemeAccent         = @"theme_accent";

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
    NSData *data = [[YTLUserDefaults standardUserDefaults] objectForKey:key];
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

void ytl_clearThemeCache(void) {
    if (cacheQueue && colorCache)
        dispatch_barrier_async(cacheQueue, ^{ [colorCache removeAllObjects]; });
}

// Helper: return custom color with alpha variant, or original
static inline UIColor *themed(NSString *key, CGFloat alpha) {
    UIColor *c = themeColor(key);
    if (!c) return nil;
    return alpha < 1.0 ? [c colorWithAlphaComponent:alpha] : c;
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
- (UIColor *)background1             { return themed(kThemeBackground, 1.0) ?: %orig; }
- (UIColor *)background2             { return themed(kThemeBackground, 1.0) ?: %orig; }
- (UIColor *)background3             { return themed(kThemeBackground, 1.0) ?: %orig; }
- (UIColor *)baseBackground          { return themed(kThemeBackground, 1.0) ?: %orig; }
- (UIColor *)raisedBackground        { return themed(kThemeBackground, 1.0) ?: %orig; }
- (UIColor *)menuBackground          { return themed(kThemeBackground, 1.0) ?: %orig; }
- (UIColor *)generalBackgroundA      { return themed(kThemeBackground, 1.0) ?: %orig; }
- (UIColor *)generalBackgroundB      { return themed(kThemeBackground, 1.0) ?: %orig; }
- (UIColor *)brandBackgroundSolid    { return themed(kThemeBackground, 1.0) ?: %orig; }
- (UIColor *)brandBackgroundPrimary  { return themed(kThemeBackground, 1.0) ?: %orig; }
- (UIColor *)brandBackgroundSecondary { return themed(kThemeBackground, 1.0) ?: %orig; }

// --- Accent ---
- (UIColor *)callToAction        { return themed(kThemeAccent, 1.0) ?: %orig; }
- (UIColor *)callToActionInverse { return themed(kThemeAccent, 1.0) ?: %orig; }

%end

#pragma mark - Seek/Progress Bar

%hook YTInlinePlayerBarContainerView
- (id)quietProgressBarColor {
    UIColor *c = themeColor(kThemeSeekBar);
    if (c) return c;
    if (ytlBool(@"redProgressBar")) return [UIColor redColor];
    return %orig;
}
%end

%hook YTSegmentableInlinePlayerBarView
- (void)setPlayedProgressBarColor:(id)color {
    UIColor *c = themeColor(kThemeSeekBar);
    %orig(c ?: color);
}
- (void)setBufferedProgressBarColor:(id)color {
    if (themeColor(kThemeSeekBar) || ytlBool(@"redProgressBar"))
        %orig([UIColor colorWithRed:0.65 green:0.65 blue:0.65 alpha:0.60]);
    else %orig(color);
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

#pragma mark - View background overrides

// Use MSHookMessageEx directly for views not in YouTubeHeader
static void (*orig_setBackgroundColor)(id, SEL, UIColor *);
static void hook_setBackgroundColor(id self, SEL _cmd, UIColor *color) {
    UIColor *c = themeColor(kThemeBackground);
    orig_setBackgroundColor(self, _cmd, c ?: color);
}

%ctor {
    NSArray *bgClasses = @[
        @"YTAsyncCollectionView", @"YTSearchView", @"YTSearchBoxView",
        @"YTHeaderView", @"YTSubheaderContainerView", @"YTAppView",
        @"YTCollectionView", @"YTCommentView", @"YTCreateCommentTextView",
        @"YTCreateCommentAccessoryView", @"YTEngagementPanelView"
    ];
    SEL bgSel = @selector(setBackgroundColor:);
    for (NSString *name in bgClasses) {
        Class cls = objc_getClass(name.UTF8String);
        if (cls) {
            MSHookMessageEx(cls, bgSel, (IMP)hook_setBackgroundColor, (IMP *)&orig_setBackgroundColor);
        }
    }
}
