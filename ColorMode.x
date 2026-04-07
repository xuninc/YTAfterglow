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

// Cache for decoded colors
static NSMutableDictionary *colorCache = nil;

static UIColor *themeColor(NSString *key) {
    if (!colorCache) colorCache = [NSMutableDictionary dictionary];

    // Check cache first
    id cached = colorCache[key];
    if (cached == [NSNull null]) return nil;
    if (cached) return cached;

    // Decode from user defaults
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

// Call this when a theme color changes to clear the cache
void ytl_clearThemeCache(void) {
    [colorCache removeAllObjects];
}

#pragma mark - Text Colors

%hook YTCommonColorPalette
- (UIColor *)textPrimary {
    UIColor *c = themeColor(kThemeTextPrimary);
    return c ?: %orig;
}
- (UIColor *)textSecondary {
    UIColor *c = themeColor(kThemeTextSecondary);
    return c ?: %orig;
}

#pragma mark - Overlay Button Colors
- (UIColor *)overlayTextPrimary {
    UIColor *c = themeColor(kThemeOverlayButtons);
    return c ?: %orig;
}
- (UIColor *)overlayTextSecondary {
    UIColor *c = themeColor(kThemeOverlayButtons);
    return c ?: %orig;
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

#pragma mark - Icon Colors (Tab Bar + General)
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
- (UIColor *)brandIconActive {
    UIColor *c = themeColor(kThemeTabBarIcons);
    return c ?: %orig;
}

#pragma mark - Background Colors
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

#pragma mark - Accent Colors
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
    return c ?: %orig;
}
%end

%hook YTSegmentableInlinePlayerBarView
- (void)setPlayedProgressBarColor:(id)color {
    UIColor *c = themeColor(kThemeSeekBar);
    %orig(c ?: color);
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

#pragma mark - Accent on QTM Material Buttons

%hook QTMColorGroup
- (UIColor *)accentColor {
    UIColor *c = themeColor(kThemeAccent);
    return c ?: %orig;
}
- (UIColor *)brightAccentColor {
    UIColor *c = themeColor(kThemeAccent);
    return c ?: %orig;
}
%end
