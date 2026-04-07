#import "YTLite.h"

// Capture real UIColor values BEFORE hooks override them
static UIColor *kRealWhite = nil;
static UIColor *kLowContrastColor = nil;
static UIColor *customContrastColor = nil;

__attribute__((constructor)) static void initColors() {
    kRealWhite = [UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:1.0];
    kLowContrastColor = [UIColor colorWithRed:0.56 green:0.56 blue:0.56 alpha:1.0];
}

static inline NSInteger contrastMode() {
    return [[YTLUserDefaults standardUserDefaults] integerForKey:@"contrastMode"];
}

static inline UIColor *activeContrastColor() {
    if (contrastMode() == 2 && customContrastColor) return customContrastColor;
    return kLowContrastColor;
}

// 0 = off, 1 = low contrast (preset gray), 2 = custom color
%group gContrastMode

%hook YTCommonColorPalette
- (UIColor *)textPrimary {
    return self.pageStyle == 1 ? kRealWhite : %orig;
}
- (UIColor *)textSecondary {
    return self.pageStyle == 1 ? kRealWhite : %orig;
}
- (UIColor *)overlayTextPrimary {
    return self.pageStyle == 1 ? kRealWhite : %orig;
}
- (UIColor *)overlayTextSecondary {
    return self.pageStyle == 1 ? kRealWhite : %orig;
}
- (UIColor *)iconActive {
    return self.pageStyle == 1 ? kRealWhite : %orig;
}
- (UIColor *)iconActiveOther {
    return self.pageStyle == 1 ? kRealWhite : %orig;
}
- (UIColor *)brandIconActive {
    return self.pageStyle == 1 ? kRealWhite : %orig;
}
- (UIColor *)staticBrandWhite {
    return self.pageStyle == 1 ? kRealWhite : %orig;
}
- (UIColor *)overlayIconActiveOther {
    return self.pageStyle == 1 ? kRealWhite : %orig;
}
- (UIColor *)overlayIconInactive {
    return self.pageStyle == 1 ? [kRealWhite colorWithAlphaComponent:0.7] : %orig;
}
- (UIColor *)overlayIconDisabled {
    return self.pageStyle == 1 ? [kRealWhite colorWithAlphaComponent:0.3] : %orig;
}
- (UIColor *)overlayFilledButtonActive {
    return self.pageStyle == 1 ? [kRealWhite colorWithAlphaComponent:0.2] : %orig;
}
%end

%hook YTColor
+ (BOOL)darkerPaletteTextColorEnabled { return NO; }
+ (UIColor *)white1 { return activeContrastColor(); }
+ (UIColor *)white2 { return activeContrastColor(); }
+ (UIColor *)white3 { return activeContrastColor(); }
+ (UIColor *)white4 { return activeContrastColor(); }
+ (UIColor *)white5 { return activeContrastColor(); }
+ (UIColor *)grey1 { return activeContrastColor(); }
+ (UIColor *)grey2 { return activeContrastColor(); }
%end

%hook UIColor
+ (UIColor *)colorNamed:(NSString *)name {
    NSArray *targetColors = @[
        @"ychGrey7", @"skt_chipBackgroundColor", @"placeholderTextColor",
        @"systemLightGrayColor", @"systemExtraLightGrayColor",
        @"labelColor", @"secondaryLabelColor",
        @"tertiaryLabelColor", @"quaternaryLabelColor"
    ];
    return [targetColors containsObject:name] ? activeContrastColor() : %orig;
}
%end

%hook QTMColorGroup
- (UIColor *)tint100 { return kRealWhite; }
- (UIColor *)tint300 { return kRealWhite; }
- (UIColor *)tint500 { return kRealWhite; }
- (UIColor *)tint700 { return kRealWhite; }
- (UIColor *)accentColor { return kRealWhite; }
- (UIColor *)brightAccentColor { return kRealWhite; }
- (UIColor *)regularColor { return kRealWhite; }
- (UIColor *)darkerColor { return kRealWhite; }
- (UIColor *)bodyTextColor { return kRealWhite; }
- (UIColor *)lightBodyTextColor { return kRealWhite; }
%end

%end

%ctor {
    NSInteger mode = contrastMode();
    if (mode > 0) {
        if (mode == 2) {
            NSData *colorData = [[YTLUserDefaults standardUserDefaults] objectForKey:@"customContrastColor"];
            if (colorData) {
                NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:colorData error:nil];
                [unarchiver setRequiresSecureCoding:NO];
                customContrastColor = [unarchiver decodeObjectForKey:NSKeyedArchiveRootObjectKey];
            }
        }
        %init(gContrastMode);
    }
}
