#import "YTLite.h"

// Theme color keys
static NSString *const kThemeOverlayButtons = @"theme_overlayButtons";
static NSString *const kThemeTabBarIcons    = @"theme_tabBarIcons";
static NSString *const kThemeSeekBar        = @"theme_seekBar";
static NSString *const kThemeBackground     = @"theme_background";
static NSString *const kThemeTextPrimary    = @"theme_textPrimary";
static NSString *const kThemeTextSecondary  = @"theme_textSecondary";
static NSString *const kThemeNavBar         = @"theme_navBar";
static NSString *const kThemeAccent         = @"theme_accent";

// Cache for decoded colors — avoids NSKeyedUnarchiver on every hook call
static NSMutableDictionary *colorCache = nil;

static UIColor *themeColor(NSString *key) {
    if (!colorCache) colorCache = [NSMutableDictionary dictionary];

    id cached = colorCache[key];
    if (cached == [NSNull null]) return nil;
    if (cached) return cached;

    NSData *data = [[YTLUserDefaults standardUserDefaults] objectForKey:key];
    if (!data) {
        colorCache[key] = [NSNull null];
        return nil;
    }
    NSKeyedUnarchiver *u = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:nil];
    [u setRequiresSecureCoding:NO];
    UIColor *color = [u decodeObjectForKey:NSKeyedArchiveRootObjectKey];
    colorCache[key] = color ?: [NSNull null];
    return color;
}

void ytl_clearThemeCache(void) {
    [colorCache removeAllObjects];
}

#pragma mark - YTCommonColorPalette: text, icons, overlays, backgrounds, accents

%hook YTCommonColorPalette

// Primary text
- (UIColor *)textPrimary {
    UIColor *c = themeColor(kThemeTextPrimary);
    return c ?: %orig;
}
- (UIColor *)textSecondary {
    UIColor *c = themeColor(kThemeTextSecondary);
    return c ?: %orig;
}
- (UIColor *)textDisabled {
    UIColor *c = themeColor(kThemeTextSecondary);
    return c ? [c colorWithAlphaComponent:0.4] : %orig;
}

// Overlay (player controls)
- (UIColor *)overlayTextPrimary {
    UIColor *c = themeColor(kThemeOverlayButtons);
    return c ?: %orig;
}
- (UIColor *)overlayTextSecondary {
    UIColor *c = themeColor(kThemeOverlayButtons);
    return c ? [c colorWithAlphaComponent:0.8] : %orig;
}
- (UIColor *)overlayIconActiveOther {
    UIColor *c = themeColor(kThemeOverlayButtons);
    return c ?: %orig;
}
- (UIColor *)overlayIconInactive {
    UIColor *c = themeColor(kThemeOverlayButtons);
    return c ? [c colorWithAlphaComponent:0.7] : %orig;
}
- (UIColor *)overlayIconDisabled {
    UIColor *c = themeColor(kThemeOverlayButtons);
    return c ? [c colorWithAlphaComponent:0.3] : %orig;
}
- (UIColor *)overlayFilledButtonActive {
    UIColor *c = themeColor(kThemeOverlayButtons);
    return c ? [c colorWithAlphaComponent:0.2] : %orig;
}

// Tab bar / general icons
- (UIColor *)iconActive {
    UIColor *c = themeColor(kThemeTabBarIcons);
    return c ?: %orig;
}
- (UIColor *)iconActiveOther {
    UIColor *c = themeColor(kThemeTabBarIcons);
    return c ?: %orig;
}
- (UIColor *)iconInactive {
    UIColor *c = themeColor(kThemeTabBarIcons);
    return c ? [c colorWithAlphaComponent:0.5] : %orig;
}
- (UIColor *)iconDisabled {
    UIColor *c = themeColor(kThemeTabBarIcons);
    return c ? [c colorWithAlphaComponent:0.3] : %orig;
}
- (UIColor *)brandIconActive {
    UIColor *c = themeColor(kThemeTabBarIcons);
    return c ?: %orig;
}
- (UIColor *)brandIconInactive {
    UIColor *c = themeColor(kThemeTabBarIcons);
    return c ? [c colorWithAlphaComponent:0.5] : %orig;
}

// Backgrounds
- (UIColor *)background1 {
    UIColor *c = themeColor(kThemeBackground);
    return c ?: %orig;
}
- (UIColor *)background2 {
    UIColor *c = themeColor(kThemeBackground);
    return c ?: %orig;
}
- (UIColor *)background3 {
    UIColor *c = themeColor(kThemeBackground);
    return c ?: %orig;
}
- (UIColor *)baseBackground {
    UIColor *c = themeColor(kThemeBackground);
    return c ?: %orig;
}
- (UIColor *)raisedBackground {
    UIColor *c = themeColor(kThemeBackground);
    return c ?: %orig;
}
- (UIColor *)menuBackground {
    UIColor *c = themeColor(kThemeBackground);
    return c ?: %orig;
}
- (UIColor *)generalBackgroundA {
    UIColor *c = themeColor(kThemeBackground);
    return c ?: %orig;
}
- (UIColor *)generalBackgroundB {
    UIColor *c = themeColor(kThemeBackground);
    return c ?: %orig;
}
- (UIColor *)brandBackgroundSolid {
    UIColor *c = themeColor(kThemeBackground);
    return c ?: %orig;
}
- (UIColor *)brandBackgroundPrimary {
    UIColor *c = themeColor(kThemeBackground);
    return c ?: %orig;
}
- (UIColor *)brandBackgroundSecondary {
    UIColor *c = themeColor(kThemeBackground);
    return c ?: %orig;
}

// Accent
- (UIColor *)callToAction {
    UIColor *c = themeColor(kThemeAccent);
    return c ?: %orig;
}
- (UIColor *)callToActionInverse {
    UIColor *c = themeColor(kThemeAccent);
    return c ?: %orig;
}
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
    if (ytlBool(@"redProgressBar") || themeColor(kThemeSeekBar))
        %orig([UIColor colorWithRed:0.65 green:0.65 blue:0.65 alpha:0.60]);
    else %orig;
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

#pragma mark - Tab Bar Background

%hook YTPivotBarView
- (void)setBackgroundColor:(UIColor *)color {
    UIColor *c = themeColor(kThemeBackground);
    %orig(c ?: color);
}
%end

#pragma mark - Accent on Material Design buttons

%hook QTMColorGroup
- (UIColor *)accentColor {
    UIColor *c = themeColor(kThemeAccent);
    return c ?: %orig;
}
- (UIColor *)brightAccentColor {
    UIColor *c = themeColor(kThemeAccent);
    return c ?: %orig;
}
- (UIColor *)buttonBackgroundColor {
    UIColor *c = themeColor(kThemeAccent);
    return c ? [c colorWithAlphaComponent:0.15] : %orig;
}
%end

#pragma mark - Background on key view classes

%hook YTAsyncCollectionView
- (void)setBackgroundColor:(UIColor *)color {
    UIColor *c = themeColor(kThemeBackground);
    %orig(c ?: color);
}
%end

%hook YTSearchView
- (void)setBackgroundColor:(UIColor *)color {
    UIColor *c = themeColor(kThemeBackground);
    %orig(c ?: color);
}
%end

%hook YTSearchBoxView
- (void)setBackgroundColor:(UIColor *)color {
    UIColor *c = themeColor(kThemeBackground);
    %orig(c ?: color);
}
%end
