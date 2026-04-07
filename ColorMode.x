#import "YTLite.h"

// Color Configuration
static UIColor *customContrastColor = nil;
static UIColor *kLowContrastColor = nil;

__attribute__((constructor)) static void initColors() {
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
    return self.pageStyle == 1 ? [UIColor whiteColor] : %orig;
}
- (UIColor *)textSecondary {
    return self.pageStyle == 1 ? [UIColor whiteColor] : %orig;
}
- (UIColor *)overlayTextPrimary {
    return self.pageStyle == 1 ? [UIColor whiteColor] : %orig;
}
- (UIColor *)overlayTextSecondary {
    return self.pageStyle == 1 ? [UIColor whiteColor] : %orig;
}
- (UIColor *)iconActive {
    return self.pageStyle == 1 ? [UIColor whiteColor] : %orig;
}
- (UIColor *)iconActiveOther {
    return self.pageStyle == 1 ? [UIColor whiteColor] : %orig;
}
- (UIColor *)brandIconActive {
    return self.pageStyle == 1 ? [UIColor whiteColor] : %orig;
}
- (UIColor *)staticBrandWhite {
    return self.pageStyle == 1 ? [UIColor whiteColor] : %orig;
}
- (UIColor *)overlayIconActiveOther {
    return self.pageStyle == 1 ? [UIColor whiteColor] : %orig;
}
- (UIColor *)overlayIconInactive {
    return self.pageStyle == 1 ? [[UIColor whiteColor] colorWithAlphaComponent:0.7] : %orig;
}
- (UIColor *)overlayIconDisabled {
    return self.pageStyle == 1 ? [[UIColor whiteColor] colorWithAlphaComponent:0.3] : %orig;
}
- (UIColor *)overlayFilledButtonActive {
    return self.pageStyle == 1 ? [[UIColor whiteColor] colorWithAlphaComponent:0.2] : %orig;
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
        @"whiteColor", @"lightTextColor", @"lightGrayColor", @"ychGrey7",
        @"skt_chipBackgroundColor", @"placeholderTextColor", @"systemLightGrayColor",
        @"systemExtraLightGrayColor", @"labelColor", @"secondaryLabelColor",
        @"tertiaryLabelColor", @"quaternaryLabelColor"
    ];
    return [targetColors containsObject:name] ? activeContrastColor() : %orig;
}
+ (UIColor *)whiteColor { return activeContrastColor(); }
+ (UIColor *)lightTextColor { return activeContrastColor(); }
+ (UIColor *)lightGrayColor { return activeContrastColor(); }
%end

%hook QTMColorGroup
- (UIColor *)tint100 { return [UIColor whiteColor]; }
- (UIColor *)tint300 { return [UIColor whiteColor]; }
- (UIColor *)tint500 { return [UIColor whiteColor]; }
- (UIColor *)tint700 { return [UIColor whiteColor]; }
- (UIColor *)accentColor { return [UIColor whiteColor]; }
- (UIColor *)brightAccentColor { return [UIColor whiteColor]; }
- (UIColor *)regularColor { return [UIColor whiteColor]; }
- (UIColor *)darkerColor { return [UIColor whiteColor]; }
- (UIColor *)bodyTextColor { return [UIColor whiteColor]; }
- (UIColor *)lightBodyTextColor { return [UIColor whiteColor]; }
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
