#import "YTAGLiteMode.h"
#import "YTAGUserDefaults.h"
#import <objc/message.h>
#import <objc/runtime.h>

extern UIColor *themeColor(NSString *key);

NSString *const YTAGLiteModeEnabledKey = @"liteModeEnabled";
NSString *const YTAGLiteModeDefaultThemeAppliedKey = @"liteModeDefaultThemeApplied";
NSString *const YTAGLiteModeDefaultThemeVersionKey = @"liteModeDefaultThemeVersion";
NSString *const YTAGThemeFontModeKey = @"theme_fontMode";
NSString *const YTAGThemeTabLabelSizeModeKey = @"theme_tabLabelSizeMode";
static NSString *const YTAGLiteThemeBackupValuesKey = @"liteModeThemeBackupValues";
static NSString *const YTAGLiteThemeBackupMissingKeysKey = @"liteModeThemeBackupMissingKeys";
static const NSInteger YTAGLiteModeCurrentThemeVersion = 2;
static const void *YTAGLiteCommentSurfaceTokenKey = &YTAGLiteCommentSurfaceTokenKey;
static const void *YTAGLiteCommentSurfaceResultKey = &YTAGLiteCommentSurfaceResultKey;
static const void *YTAGLiteCommentChromeTokenKey = &YTAGLiteCommentChromeTokenKey;
static const void *YTAGLiteCollectionCleanResultKey = &YTAGLiteCollectionCleanResultKey;
static const void *YTAGLiteViewCleanupTokenKey = &YTAGLiteViewCleanupTokenKey;
static const void *YTAGLiteLabelStyleTokenKey = &YTAGLiteLabelStyleTokenKey;

typedef NS_ENUM(NSInteger, YTAGThemeFontMode) {
    YTAGThemeFontModeAuto = 0,
    YTAGThemeFontModeSystem,
    YTAGThemeFontModeRounded,
    YTAGThemeFontModeNewYork,
    YTAGThemeFontModeSFMono,
    YTAGThemeFontModeCourierNew,
    YTAGThemeFontModeCourier,
    YTAGThemeFontModeMenlo,
    YTAGThemeFontModeAvenirNext,
    YTAGThemeFontModeHelveticaNeue,
    YTAGThemeFontModeArial,
    YTAGThemeFontModeGeorgia,
    YTAGThemeFontModeTimesNewRoman,
    YTAGThemeFontModePalatino,
    YTAGThemeFontModeDidot,
    YTAGThemeFontModeBaskerville,
    YTAGThemeFontModeAmericanTypewriter,
    YTAGThemeFontModeHoeflerText,
    YTAGThemeFontModeGillSans,
    YTAGThemeFontModeFutura,
    YTAGThemeFontModeMarkerFelt,
    YTAGThemeFontModeNoteworthy,
};

typedef NS_ENUM(NSInteger, YTAGThemeTabLabelSizeMode) {
    YTAGThemeTabLabelSizeModeAuto = 0,
    YTAGThemeTabLabelSizeModeCompact,
    YTAGThemeTabLabelSizeModeTiny,
};

static NSData *YTAGLiteArchiveColor(UIColor *color) {
    return [NSKeyedArchiver archivedDataWithRootObject:color requiringSecureCoding:NO error:nil];
}

static void YTAGLiteSaveColor(YTAGUserDefaults *defaults, NSString *key, UIColor *color) {
    NSData *data = YTAGLiteArchiveColor(color);
    if (data) [defaults setObject:data forKey:key];
}

static BOOL YTAGLiteStoredColorMatches(YTAGUserDefaults *defaults, NSString *key, UIColor *color) {
    NSData *stored = [defaults objectForKey:key];
    NSData *expected = YTAGLiteArchiveColor(color);
    return stored && expected && [stored isEqualToData:expected];
}

static BOOL YTAGLiteThemeLooksLikeV1BlackPreset(YTAGUserDefaults *defaults) {
    return
        YTAGLiteStoredColorMatches(defaults, @"theme_background", [UIColor colorWithWhite:0.015 alpha:1.0]) &&
        YTAGLiteStoredColorMatches(defaults, @"theme_navBar", [UIColor colorWithWhite:0.055 alpha:1.0]) &&
        YTAGLiteStoredColorMatches(defaults, @"theme_accent", [UIColor colorWithWhite:1.0 alpha:1.0]);
}

static NSArray<NSString *> *YTAGLiteThemeKeys(void) {
    return @[
        @"theme_overlayButtons", @"theme_tabBarIcons",
        @"theme_seekBar", @"theme_seekBarLive",
        @"theme_seekBarScrubber", @"theme_seekBarScrubberLive",
        @"theme_background", @"theme_textPrimary", @"theme_textSecondary",
        @"theme_navBar", @"theme_accent",
        @"theme_gradientStart", @"theme_gradientEnd",
        @"theme_glowEnabled", @"theme_glowPivot", @"theme_glowOverlay",
        @"theme_glowScrubber", @"theme_glowSeekBar",
        @"theme_glowStrength", @"theme_glowStrengthMode",
        @"theme_glowStrengthCustom", @"theme_glowOpacity",
        @"theme_glowRadius", @"theme_glowLayers", @"theme_glowColor",
        @"seekBarGradient", YTAGThemeFontModeKey, YTAGThemeTabLabelSizeModeKey
    ];
}

static void YTAGLiteModeSaveThemeBackupIfNeeded(YTAGUserDefaults *defaults) {
    if ([defaults objectForKey:YTAGLiteThemeBackupValuesKey] ||
        [defaults objectForKey:YTAGLiteThemeBackupMissingKeysKey]) {
        return;
    }

    NSMutableDictionary<NSString *, id> *values = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *missingKeys = [NSMutableArray array];

    for (NSString *key in YTAGLiteThemeKeys()) {
        id value = [defaults objectForKey:key];
        if (value) {
            values[key] = value;
        } else {
            [missingKeys addObject:key];
        }
    }

    [defaults setObject:values forKey:YTAGLiteThemeBackupValuesKey];
    [defaults setObject:missingKeys forKey:YTAGLiteThemeBackupMissingKeysKey];
}

static void YTAGLiteModeRestoreThemeBackupIfNeeded(YTAGUserDefaults *defaults) {
    NSDictionary<NSString *, id> *values = [defaults objectForKey:YTAGLiteThemeBackupValuesKey];
    NSArray<NSString *> *missingKeys = [defaults objectForKey:YTAGLiteThemeBackupMissingKeysKey];
    if (![values isKindOfClass:[NSDictionary class]] && ![missingKeys isKindOfClass:[NSArray class]]) return;

    for (NSString *key in YTAGLiteThemeKeys()) {
        [defaults removeObjectForKey:key];
    }

    if ([missingKeys isKindOfClass:[NSArray class]]) {
        for (NSString *key in missingKeys) {
            if ([key isKindOfClass:[NSString class]]) [defaults removeObjectForKey:key];
        }
    }

    if ([values isKindOfClass:[NSDictionary class]]) {
        [values enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
            if ([key isKindOfClass:[NSString class]] && value) [defaults setObject:value forKey:key];
        }];
    }

    [defaults removeObjectForKey:YTAGLiteThemeBackupValuesKey];
    [defaults removeObjectForKey:YTAGLiteThemeBackupMissingKeysKey];
    [defaults removeObjectForKey:YTAGLiteModeDefaultThemeAppliedKey];
    [defaults removeObjectForKey:YTAGLiteModeDefaultThemeVersionKey];
}

static NSSet<NSString *> *YTAGLiteForcedTrueKeys(void) {
    static NSSet<NSString *> *keys = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = [NSSet setWithArray:@[
            @"noAds", @"noPromotionCards", @"noSearchHistory", @"noLinkTracking", @"noShareChunk",
            @"noCast", @"noNotifsButton", @"noVoiceSearchButton", @"noSubbar", @"noYTLogo",
            @"removeLabels", @"removeIndicators",
            @"hideEndScreenCards", @"noRelatedVids", @"noContinueWatching", @"noContinueWatchingPrompt", @"noRelatedWatchNexts",
            @"hidePrevNext", @"noHUDMsgs", @"noDarkBg", @"noFullscreenActions", @"noWatermarks", @"disableAmbientMode",
            @"noPlayerShareButton", @"noPlayerSaveButton", @"noPlayerRemixButton", @"noPlayerClipButton",
            @"removeShareMenu", @"removePlayNext", @"removeWatchLaterMenu", @"removeSaveToPlaylistMenu",
            @"removeNotInterestedMenu", @"removeDontRecommendMenu", @"removeReportMenu",
            @"shortsToRegular", @"resumeShorts", @"hideShorts", @"shortsProgress",
            @"hideShortsLogo", @"hideShortsSearch", @"hideShortsCamera", @"hideShortsMore", @"hideShortsSubscriptions",
            @"hideShortsLike", @"hideShortsDislike", @"hideShortsComments", @"hideShortsRemix", @"hideShortsShare",
            @"hideShortsAvatars", @"hideShortsThanks", @"hideShortsSource", @"hideShortsChannelName",
            @"hideShortsDescription", @"hideShortsAudioTrack", @"hideShortsPromoCards"
        ]];
    });
    return keys;
}

static NSSet<NSString *> *YTAGLiteForcedFalseKeys(void) {
    static NSSet<NSString *> *keys = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = [NSSet setWithArray:@[
            @"noSearchButton", @"shortsOnlyMode", @"noPlayerDownloadButton", @"removeDownloadMenu"
        ]];
    });
    return keys;
}

BOOL YTAGLiteModeEnabled(void) {
    return [[YTAGUserDefaults standardUserDefaults] boolForKey:YTAGLiteModeEnabledKey];
}

BOOL YTAGEffectiveBool(NSString *key) {
    if (key.length == 0) return NO;
    if (YTAGLiteModeEnabled()) {
        if ([YTAGLiteForcedFalseKeys() containsObject:key]) return NO;
        if ([YTAGLiteForcedTrueKeys() containsObject:key]) return YES;
    }
    return [[YTAGUserDefaults standardUserDefaults] boolForKey:key];
}

void YTAGLiteModeApplyDefaultThemeIfNeeded(void) {
    YTAGUserDefaults *defaults = [YTAGUserDefaults standardUserDefaults];
    NSInteger themeVersion = [defaults integerForKey:YTAGLiteModeDefaultThemeVersionKey];
    if (themeVersion >= YTAGLiteModeCurrentThemeVersion) return;
    if ([defaults boolForKey:YTAGLiteModeDefaultThemeAppliedKey] && !YTAGLiteThemeLooksLikeV1BlackPreset(defaults)) {
        [defaults setInteger:YTAGLiteModeCurrentThemeVersion forKey:YTAGLiteModeDefaultThemeVersionKey];
        return;
    }

    UIColor *white = [UIColor colorWithWhite:1.0 alpha:1.0];
    UIColor *softWhite = [UIColor colorWithWhite:0.96 alpha:1.0];
    UIColor *secondary = [UIColor colorWithWhite:0.78 alpha:1.0];
    UIColor *background = [UIColor colorWithWhite:0.18 alpha:1.0];
    UIColor *surface = [UIColor colorWithWhite:0.24 alpha:1.0];

    YTAGLiteSaveColor(defaults, @"theme_overlayButtons", white);
    YTAGLiteSaveColor(defaults, @"theme_tabBarIcons", white);
    YTAGLiteSaveColor(defaults, @"theme_seekBar", white);
    YTAGLiteSaveColor(defaults, @"theme_seekBarLive", white);
    YTAGLiteSaveColor(defaults, @"theme_seekBarScrubber", white);
    YTAGLiteSaveColor(defaults, @"theme_seekBarScrubberLive", white);
    YTAGLiteSaveColor(defaults, @"theme_background", background);
    YTAGLiteSaveColor(defaults, @"theme_textPrimary", softWhite);
    YTAGLiteSaveColor(defaults, @"theme_textSecondary", secondary);
    YTAGLiteSaveColor(defaults, @"theme_navBar", surface);
    YTAGLiteSaveColor(defaults, @"theme_accent", white);
    [defaults removeObjectForKey:@"theme_gradientStart"];
    [defaults removeObjectForKey:@"theme_gradientEnd"];
    [defaults setBool:YES forKey:@"theme_glowEnabled"];
    [defaults setBool:YES forKey:@"theme_glowPivot"];
    [defaults setBool:YES forKey:@"theme_glowOverlay"];
    [defaults setBool:YES forKey:@"theme_glowScrubber"];
    [defaults setBool:YES forKey:@"theme_glowSeekBar"];
    [defaults setInteger:2 forKey:@"theme_glowStrength"];
    [defaults setInteger:2 forKey:@"theme_glowStrengthMode"];
    [defaults setBool:NO forKey:@"seekBarGradient"];
    [defaults setBool:YES forKey:YTAGLiteModeDefaultThemeAppliedKey];
    [defaults setInteger:YTAGLiteModeCurrentThemeVersion forKey:YTAGLiteModeDefaultThemeVersionKey];
    [defaults synchronize];
}

void YTAGSetLiteModeEnabled(BOOL enabled) {
    YTAGUserDefaults *defaults = [YTAGUserDefaults standardUserDefaults];
    BOOL wasEnabled = [defaults boolForKey:YTAGLiteModeEnabledKey];

    if (enabled && !wasEnabled) {
        YTAGLiteModeSaveThemeBackupIfNeeded(defaults);
        [defaults removeObjectForKey:YTAGLiteModeDefaultThemeAppliedKey];
        [defaults removeObjectForKey:YTAGLiteModeDefaultThemeVersionKey];
    }

    [defaults setBool:enabled forKey:YTAGLiteModeEnabledKey];

    if (enabled) {
        YTAGLiteModeApplyDefaultThemeIfNeeded();
    } else if (wasEnabled) {
        YTAGLiteModeRestoreThemeBackupIfNeeded(defaults);
    }

    [defaults synchronize];
}

NSArray<NSString *> *YTAGLiteModeActiveTabs(void) {
    return @[@"FEwhat_to_watch", @"FEsubscriptions", @"FElibrary"];
}

NSString *YTAGLiteModeStartupTab(void) {
    return @"FEwhat_to_watch";
}

static UIFontWeight YTAGLiteModeWeightForFont(UIFont *font) {
    if (!font) return UIFontWeightRegular;
    NSDictionary *traits = [font.fontDescriptor objectForKey:UIFontDescriptorTraitsAttribute];
    NSNumber *weight = traits[UIFontWeightTrait];
    if (weight) return (UIFontWeight)weight.doubleValue;

    NSString *name = font.fontName.lowercaseString;
    if ([name containsString:@"bold"] || [name containsString:@"heavy"] || [name containsString:@"black"]) {
        return UIFontWeightBold;
    }
    if ([name containsString:@"medium"] || [name containsString:@"semibold"] || [name containsString:@"demi"]) {
        return UIFontWeightSemibold;
    }
    if ([name containsString:@"light"] || [name containsString:@"thin"]) {
        return UIFontWeightLight;
    }
    return UIFontWeightRegular;
}

NSArray<NSString *> *YTAGThemeFontModeDisplayNames(void) {
    return @[
        @"Auto",
        @"System / SF Pro",
        @"Rounded",
        @"New York",
        @"SF Mono",
        @"Courier New",
        @"Courier",
        @"Menlo",
        @"Avenir Next",
        @"Helvetica Neue",
        @"Arial",
        @"Georgia",
        @"Times New Roman",
        @"Palatino",
        @"Didot",
        @"Baskerville",
        @"American Typewriter",
        @"Hoefler Text",
        @"Gill Sans",
        @"Futura",
        @"Marker Felt",
        @"Noteworthy"
    ];
}

NSString *YTAGThemeFontModeDisplayName(NSInteger mode) {
    NSArray<NSString *> *names = YTAGThemeFontModeDisplayNames();
    NSInteger index = MIN(MAX(mode, 0), (NSInteger)names.count - 1);
    return names[index];
}

NSArray<NSString *> *YTAGThemeTabLabelSizeModeDisplayNames(void) {
    return @[@"Auto", @"Compact", @"Tiny"];
}

NSString *YTAGThemeTabLabelSizeModeDisplayName(NSInteger mode) {
    NSArray<NSString *> *names = YTAGThemeTabLabelSizeModeDisplayNames();
    NSInteger index = MIN(MAX(mode, 0), (NSInteger)names.count - 1);
    return names[index];
}

static NSInteger YTAGThemeRequestedFontMode(void) {
    NSInteger mode = [[YTAGUserDefaults standardUserDefaults] integerForKey:YTAGThemeFontModeKey];
    NSInteger maxMode = (NSInteger)YTAGThemeFontModeDisplayNames().count - 1;
    return MIN(MAX(mode, 0), maxMode);
}

static NSInteger YTAGThemeEffectiveFontMode(void) {
    NSInteger requestedMode = YTAGThemeRequestedFontMode();
    if (requestedMode != YTAGThemeFontModeAuto) return requestedMode;
    return YTAGLiteModeEnabled() ? YTAGThemeFontModeCourierNew : YTAGThemeFontModeAuto;
}

BOOL YTAGThemeFontOverrideEnabled(void) {
    return YTAGThemeEffectiveFontMode() != YTAGThemeFontModeAuto;
}

static NSInteger YTAGThemeTabLabelSizeModeValue(void) {
    NSInteger mode = [[YTAGUserDefaults standardUserDefaults] integerForKey:YTAGThemeTabLabelSizeModeKey];
    NSInteger maxMode = (NSInteger)YTAGThemeTabLabelSizeModeDisplayNames().count - 1;
    return MIN(MAX(mode, 0), maxMode);
}

static UIFont *YTAGFontWithNames(NSArray<NSString *> *regularNames, NSArray<NSString *> *boldNames, CGFloat size, UIFontWeight weight) {
    NSArray<NSString *> *names = weight >= UIFontWeightSemibold ? boldNames : regularNames;
    for (NSString *name in names) {
        UIFont *font = [UIFont fontWithName:name size:size];
        if (font) return font;
    }
    for (NSString *name in regularNames) {
        UIFont *font = [UIFont fontWithName:name size:size];
        if (font) return font;
    }
    return nil;
}

static UIFont *YTAGSystemDesignedFont(UIFontDescriptorSystemDesign design, CGFloat size, UIFontWeight weight) {
    UIFont *base = [UIFont systemFontOfSize:size weight:weight];
    UIFontDescriptor *descriptor = [base.fontDescriptor fontDescriptorWithDesign:design];
    return descriptor ? [UIFont fontWithDescriptor:descriptor size:size] : base;
}

static UIFont *YTAGThemeFontForMode(NSInteger mode, CGFloat size, UIFontWeight weight) {
    CGFloat pointSize = MAX(9.0, size);
    switch (mode) {
        case YTAGThemeFontModeSystem:
            return [UIFont systemFontOfSize:pointSize weight:weight];
        case YTAGThemeFontModeRounded:
            return YTAGSystemDesignedFont(UIFontDescriptorSystemDesignRounded, pointSize, weight);
        case YTAGThemeFontModeNewYork:
            return YTAGSystemDesignedFont(UIFontDescriptorSystemDesignSerif, pointSize, weight);
        case YTAGThemeFontModeSFMono:
            return [UIFont monospacedSystemFontOfSize:pointSize weight:weight];
        case YTAGThemeFontModeCourierNew:
            return YTAGFontWithNames(@[@"CourierNewPSMT"], @[@"CourierNewPS-BoldMT"], pointSize, weight);
        case YTAGThemeFontModeCourier:
            return YTAGFontWithNames(@[@"Courier"], @[@"Courier-Bold"], pointSize, weight);
        case YTAGThemeFontModeMenlo:
            return YTAGFontWithNames(@[@"Menlo-Regular"], @[@"Menlo-Bold"], pointSize, weight);
        case YTAGThemeFontModeAvenirNext:
            return YTAGFontWithNames(@[@"AvenirNext-Regular"], @[@"AvenirNext-DemiBold", @"AvenirNext-Bold"], pointSize, weight);
        case YTAGThemeFontModeHelveticaNeue:
            return YTAGFontWithNames(@[@"HelveticaNeue"], @[@"HelveticaNeue-Bold"], pointSize, weight);
        case YTAGThemeFontModeArial:
            return YTAGFontWithNames(@[@"ArialMT"], @[@"Arial-BoldMT"], pointSize, weight);
        case YTAGThemeFontModeGeorgia:
            return YTAGFontWithNames(@[@"Georgia"], @[@"Georgia-Bold"], pointSize, weight);
        case YTAGThemeFontModeTimesNewRoman:
            return YTAGFontWithNames(@[@"TimesNewRomanPSMT"], @[@"TimesNewRomanPS-BoldMT"], pointSize, weight);
        case YTAGThemeFontModePalatino:
            return YTAGFontWithNames(@[@"Palatino-Roman"], @[@"Palatino-Bold"], pointSize, weight);
        case YTAGThemeFontModeDidot:
            return YTAGFontWithNames(@[@"Didot"], @[@"Didot-Bold"], pointSize, weight);
        case YTAGThemeFontModeBaskerville:
            return YTAGFontWithNames(@[@"Baskerville"], @[@"Baskerville-Bold"], pointSize, weight);
        case YTAGThemeFontModeAmericanTypewriter:
            return YTAGFontWithNames(@[@"AmericanTypewriter"], @[@"AmericanTypewriter-Bold"], pointSize, weight);
        case YTAGThemeFontModeHoeflerText:
            return YTAGFontWithNames(@[@"HoeflerText-Regular"], @[@"HoeflerText-Black"], pointSize, weight);
        case YTAGThemeFontModeGillSans:
            return YTAGFontWithNames(@[@"GillSans"], @[@"GillSans-Bold"], pointSize, weight);
        case YTAGThemeFontModeFutura:
            return YTAGFontWithNames(@[@"Futura-Medium"], @[@"Futura-CondensedExtraBold", @"Futura-Medium"], pointSize, weight);
        case YTAGThemeFontModeMarkerFelt:
            return YTAGFontWithNames(@[@"MarkerFelt-Thin"], @[@"MarkerFelt-Wide"], pointSize, weight);
        case YTAGThemeFontModeNoteworthy:
            return YTAGFontWithNames(@[@"Noteworthy-Light"], @[@"Noteworthy-Bold"], pointSize, weight);
        default:
            return nil;
    }
}

UIFont *YTAGLiteModeFont(CGFloat size, UIFontWeight weight) {
    NSInteger mode = YTAGThemeEffectiveFontMode();
    UIFont *font = YTAGThemeFontForMode(mode, size, weight);
    return font ?: [UIFont systemFontOfSize:MAX(9.0, size) weight:weight];
}

UIFont *YTAGLiteModeFontMatchingFont(UIFont *font) {
    CGFloat pointSize = font.pointSize > 0 ? font.pointSize : 13.0;
    return YTAGLiteModeFont(pointSize, YTAGLiteModeWeightForFont(font));
}

UIFont *YTAGThemeTabLabelFontMatchingFont(UIFont *font) {
    if (!font) return nil;

    CGFloat pointSize = font.pointSize > 0 ? font.pointSize : 10.0;
    NSInteger sizeMode = YTAGThemeTabLabelSizeModeValue();
    if (sizeMode == YTAGThemeTabLabelSizeModeCompact) pointSize -= 1.0;
    else if (sizeMode == YTAGThemeTabLabelSizeModeTiny) pointSize -= 2.0;
    pointSize = MAX(7.0, pointSize);

    if (YTAGThemeFontOverrideEnabled()) {
        return YTAGLiteModeFont(pointSize, YTAGLiteModeWeightForFont(font));
    }
    return [font fontWithSize:pointSize];
}

static BOOL YTAGLiteFontsMatch(UIFont *lhs, UIFont *rhs) {
    if (!lhs || !rhs) return lhs == rhs;
    CGFloat delta = lhs.pointSize > rhs.pointSize ? lhs.pointSize - rhs.pointSize : rhs.pointSize - lhs.pointSize;
    return delta < 0.1 && [lhs.fontName isEqualToString:rhs.fontName];
}

static NSString *YTAGLiteLabelStyleToken(UILabel *label) {
    if (!label) return @"";
    UIFont *font = label.font;
    return [NSString stringWithFormat:@"%ld|%@|%.1f|%ld|%@|%@",
            (long)YTAGThemeEffectiveFontMode(),
            font.fontName ?: @"",
            font.pointSize,
            (long)label.numberOfLines,
            label.text ?: @"",
            label.attributedText.string ?: @""];
}

void YTAGLiteModeStyleLabel(UILabel *label) {
    if (!label) return;
    NSString *token = YTAGLiteLabelStyleToken(label);
    NSString *cachedToken = objc_getAssociatedObject(label, YTAGLiteLabelStyleTokenKey);
    if ([cachedToken isEqualToString:token]) return;

    UIFont *font = YTAGLiteModeFontMatchingFont(label.font);
    if (!YTAGLiteFontsMatch(label.font, font)) {
        label.font = font;
    }

    if (label.attributedText.length > 0) {
        NSAttributedString *styled = YTAGLiteModeStyleAttributedString(label.attributedText);
        if (styled && styled != label.attributedText) {
            label.attributedText = styled;
        }
    }

    if (label.numberOfLines != 0) {
        label.numberOfLines = 0;
    }

    objc_setAssociatedObject(label, YTAGLiteLabelStyleTokenKey, YTAGLiteLabelStyleToken(label), OBJC_ASSOCIATION_COPY_NONATOMIC);
}

NSAttributedString *YTAGLiteModeStyleAttributedString(NSAttributedString *attributedString) {
    if (!attributedString) return nil;
    if (attributedString.length == 0) return attributedString;

    __block BOOL needsChange = NO;
    NSMutableArray<NSDictionary<NSString *, id> *> *updates = [NSMutableArray array];
    NSRange fullRange = NSMakeRange(0, attributedString.length);

    [attributedString enumerateAttribute:NSFontAttributeName inRange:fullRange options:0 usingBlock:^(id value, NSRange range, __unused BOOL *stop) {
        UIFont *sourceFont = [value isKindOfClass:[UIFont class]] ? value : [UIFont systemFontOfSize:13.0];
        UIFont *liteFont = YTAGLiteModeFontMatchingFont(sourceFont);
        if (!liteFont || range.length == 0) return;
        if (![value isKindOfClass:[UIFont class]] || !YTAGLiteFontsMatch(sourceFont, liteFont)) {
            needsChange = YES;
            [updates addObject:@{@"font": liteFont, @"range": [NSValue valueWithRange:range]}];
        }
    }];

    if (!needsChange) return attributedString;

    NSMutableAttributedString *styled = [attributedString mutableCopy];

    for (NSDictionary<NSString *, id> *update in updates) {
        UIFont *font = update[@"font"];
        NSRange range = [update[@"range"] rangeValue];
        [styled addAttribute:NSFontAttributeName value:font range:range];
    }
    return styled;
}

static NSString *YTAGLiteNormalizedString(NSString *string) {
    if (string.length == 0) return @"";
    NSMutableString *normalized = [NSMutableString stringWithCapacity:string.length];
    NSCharacterSet *allowed = [NSCharacterSet alphanumericCharacterSet];
    NSString *lower = string.lowercaseString;
    for (NSUInteger i = 0; i < lower.length; i++) {
        unichar ch = [lower characterAtIndex:i];
        if ([allowed characterIsMember:ch]) [normalized appendFormat:@"%C", ch];
    }
    return normalized;
}

static NSString *YTAGLiteViewSignature(UIView *view) {
    if (!view) return @"";
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithObject:NSStringFromClass(view.class)];
    if (view.accessibilityIdentifier.length > 0) [parts addObject:view.accessibilityIdentifier];
    if (view.accessibilityLabel.length > 0) [parts addObject:view.accessibilityLabel];
    if (view.accessibilityValue.length > 0) [parts addObject:view.accessibilityValue];
    if (view.accessibilityHint.length > 0) [parts addObject:view.accessibilityHint];

    if ([view isKindOfClass:[UILabel class]]) {
        NSString *text = ((UILabel *)view).text;
        if (text.length > 0) [parts addObject:text];
    }

    if ([view respondsToSelector:@selector(titleLabel)]) {
        @try {
            UILabel *label = ((UILabel *(*)(id, SEL))objc_msgSend)(view, @selector(titleLabel));
            if ([label isKindOfClass:[UILabel class]] && label.text.length > 0) [parts addObject:label.text];
        } @catch (__unused id ex) {}
    }

    return YTAGLiteNormalizedString([parts componentsJoinedByString:@" "]);
}

static BOOL YTAGLiteSignatureContainsAny(NSString *signature, NSArray<NSString *> *markers) {
    for (NSString *marker in markers) {
        if ([signature containsString:YTAGLiteNormalizedString(marker)]) return YES;
    }
    return NO;
}

static NSString *YTAGLiteViewStructureToken(UIView *view) {
    if (!view) return @"";

    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithObject:NSStringFromClass(view.class)];
    if (view.accessibilityIdentifier.length > 0) [parts addObject:view.accessibilityIdentifier];
    if (view.accessibilityLabel.length > 0) [parts addObject:view.accessibilityLabel];
    if (view.accessibilityValue.length > 0) [parts addObject:view.accessibilityValue];

    CGRect bounds = view.bounds;
    [parts addObject:[NSString stringWithFormat:@"%.0fx%.0f:%lu",
                      round(CGRectGetWidth(bounds)),
                      round(CGRectGetHeight(bounds)),
                      (unsigned long)view.subviews.count]];

    NSUInteger index = 0;
    for (UIView *subview in view.subviews) {
        if (index >= 10) break;
        NSMutableString *subpart = [NSMutableString stringWithFormat:@"%@:%lu:%d",
                                    NSStringFromClass(subview.class),
                                    (unsigned long)subview.subviews.count,
                                    subview.hidden ? 1 : 0];
        if (subview.accessibilityIdentifier.length > 0) {
            [subpart appendFormat:@":%@", subview.accessibilityIdentifier];
        }
        CGRect frame = subview.frame;
        CGRect bounds = subview.bounds;
        [subpart appendFormat:@":%.0fx%.0f@%.0f,%.0f:%.0fx%.0f",
         round(CGRectGetWidth(frame)),
         round(CGRectGetHeight(frame)),
         round(CGRectGetMinX(frame)),
         round(CGRectGetMinY(frame)),
         round(CGRectGetWidth(bounds)),
         round(CGRectGetHeight(bounds))];
        [parts addObject:subpart];
        index++;
    }

    return [parts componentsJoinedByString:@"|"];
}

static NSString *YTAGLiteObjectSignature(id object) {
    if (!object) return @"";
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithObject:NSStringFromClass([object class])];
    NSString *description = [object description];
    if (description.length > 0) [parts addObject:description];

    NSArray<NSString *> *keys = @[
        @"accessibilityIdentifier", @"_accessibilityIdentifier", @"accessibilityLabel",
        @"accessibilityValue", @"title", @"text", @"name", @"identifier",
        @"rendererIdentifier", @"pivotIdentifier", @"targetId", @"browseId"
    ];
    for (NSString *key in keys) {
        @try {
            id value = [object valueForKey:key];
            if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
                [parts addObject:value];
            } else if ([value respondsToSelector:@selector(description)]) {
                NSString *valueDescription = [value description];
                if (valueDescription.length > 0 && valueDescription.length < 300) [parts addObject:valueDescription];
            }
        } @catch (__unused id ex) {}
    }

    return YTAGLiteNormalizedString([parts componentsJoinedByString:@" "]);
}

BOOL YTAGLiteModeShouldPruneFeedObject(id object) {
    if (!YTAGLiteModeEnabled() || !object) return NO;
    NSString *signature = YTAGLiteObjectSignature(object);
    if (signature.length == 0) return NO;

    if (YTAGLiteSignatureContainsAny(signature, @[
        @"settings", @"setting", @"accountmenu", @"accountswitcher", @"signin", @"login",
        @"toast", @"alert", @"dialog", @"comment", @"comments", @"reply", @"composer",
        @"commententrypoint", @"commentsentrypoint", @"commentsection", @"commentssection",
        @"viewcomments", @"showcomments", @"opencomments", @"engagementpanelcomment",
        @"search", @"download", @"pip", @"caption", @"quality", @"fullscreen"
    ])) {
        return NO;
    }

    return YTAGLiteSignatureContainsAny(signature, @[
        @"shorts", @"reel", @"emlshortsgrid", @"emlshortsshelf", @"shortsshelf",
        @"promoted", @"promotion", @"sponsor", @"sponsored", @"commerce", @"shoppingrenderer",
        @"shoppingpanel", @"productcarousel", @"productengagementpanel", @"productitem",
        @"productlist", @"productshelf", @"productsinvideo", @"shoppingitem", @"shoppingitemlist",
        @"shoppingcompanion", @"shoppingdrawer", @"merch", @"merchandise", @"merchandiseshelf",
        @"merchandiseitem", @"channelstore", @"shoppingstore", @"storefront", @"storeshelf",
        @"storebutton", @"storeitem", @"brandpromo", @"feedad", @"adrenderer", @"adslot",
        @"community", @"backstage", @"backstagepost", @"postrenderer", @"pollrenderer", @"storyrenderer",
        @"breakingnews", @"breakingnewsshelf", @"newsshelf", @"trendingrenderer", @"hype",
        @"suggestedvideo", @"watchnext", @"upnext", @"autoplayrenderer", @"relatedvideo",
        @"mixplaylist", @"radio", @"playlistmix",
        @"chipcloud", @"filterchip", @"chipbar", @"filterbar",
        @"shortsshelf", @"richshelf", @"horizontalcardlist"
    ]);
}

BOOL YTAGLiteModeShouldRemoveFeedView(UIView *view) {
    if (!YTAGLiteModeEnabled() || !view) return NO;
    NSString *signature = YTAGLiteViewSignature(view);
    return YTAGLiteModeShouldPruneFeedObject(view) || YTAGLiteSignatureContainsAny(signature, @[
        @"shorts", @"reel", @"promoted", @"adrenderer", @"advert",
        @"backstagepost", @"postrenderer", @"community", @"pollrenderer", @"storyrenderer",
        @"chipcloud", @"filterchip", @"productcarousel", @"shoppingrenderer",
        @"shoppingitem", @"shoppingitemlist", @"shoppingcompanion", @"shoppingdrawer",
        @"merchandise", @"merchandiseshelf", @"merchandiseitem", @"channelstore",
        @"shoppingstore", @"storefront", @"storeshelf", @"storebutton", @"storeitem",
        @"breakingnews", @"trendingrenderer", @"mixplaylist", @"radio"
    ]);
}

static NSString *YTAGLiteCollectionContextSignature(UIView *view) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (UIView *candidate = view; candidate; candidate = candidate.superview) {
        [parts addObject:YTAGLiteViewSignature(candidate)];
        [parts addObject:NSStringFromClass(candidate.class)];
    }

    for (UIResponder *responder = view.nextResponder; responder; responder = responder.nextResponder) {
        [parts addObject:NSStringFromClass(responder.class)];
        if ([responder isKindOfClass:[UIViewController class]]) {
            NSString *title = ((UIViewController *)responder).title;
            if (title.length > 0) [parts addObject:title];
        }
    }

    return YTAGLiteNormalizedString([parts componentsJoinedByString:@" "]);
}

BOOL YTAGLiteModeShouldCleanCollectionView(UIView *collectionView) {
    if (!YTAGLiteModeEnabled() || !collectionView) return NO;
    NSNumber *cachedResult = objc_getAssociatedObject(collectionView, YTAGLiteCollectionCleanResultKey);
    if (cachedResult) return cachedResult.boolValue;

    NSString *context = YTAGLiteCollectionContextSignature(collectionView);
    BOOL result = YES;
    if (YTAGLiteSignatureContainsAny(context, @[
        @"settings", @"setting", @"picker", @"accountmenu", @"accountswitcher",
        @"signin", @"login", @"toast", @"alert", @"dialog"
    ])) {
        result = NO;
    }

    objc_setAssociatedObject(collectionView, YTAGLiteCollectionCleanResultKey, @(result), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return result;
}

static BOOL YTAGLiteModeViewTreeContainsAny(UIView *view, NSArray<NSString *> *markers, NSUInteger depth) {
    if (!view || depth == 0) return NO;
    if (YTAGLiteSignatureContainsAny(YTAGLiteViewSignature(view), markers)) return YES;
    for (UIView *subview in view.subviews) {
        if (YTAGLiteModeViewTreeContainsAny(subview, markers, depth - 1)) return YES;
    }
    return NO;
}

BOOL YTAGLiteModeShouldStyleCommentView(UIView *view) {
    if (!YTAGLiteModeEnabled() || !view) return NO;
    NSString *token = YTAGLiteViewStructureToken(view);
    NSString *cachedToken = objc_getAssociatedObject(view, YTAGLiteCommentSurfaceTokenKey);
    NSNumber *cachedResult = objc_getAssociatedObject(view, YTAGLiteCommentSurfaceResultKey);
    if (cachedResult && [cachedToken isEqualToString:token]) return cachedResult.boolValue;

    NSArray<NSString *> *markers = @[
        @"comment", @"comments", @"reply", @"replies", @"composer", @"commentthread", @"commentcell"
    ];
    BOOL result = YTAGLiteModeViewTreeContainsAny(view, markers, 4);
    objc_setAssociatedObject(view, YTAGLiteCommentSurfaceTokenKey, token, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(view, YTAGLiteCommentSurfaceResultKey, @(result), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return result;
}

static UIColor *YTAGLiteModeThemeBackgroundColor(void) {
    return themeColor(@"theme_background") ?: [UIColor colorWithWhite:0.18 alpha:1.0];
}

void YTAGLiteModeApplyBackgroundColor(UIView *view) {
    if (!YTAGLiteModeEnabled() || !view) return;
    UIColor *background = YTAGLiteModeThemeBackgroundColor();
    view.backgroundColor = background;
    view.opaque = YES;

    if ([view isKindOfClass:[UICollectionViewCell class]]) {
        UICollectionViewCell *cell = (UICollectionViewCell *)view;
        cell.contentView.backgroundColor = background;
        cell.contentView.opaque = YES;
    }
}

static BOOL YTAGLiteShouldHideSubview(UIView *view) {
    NSString *signature = YTAGLiteViewSignature(view);
    if (signature.length == 0) return NO;
    if (YTAGLiteSignatureContainsAny(signature, @[@"search", @"download", @"pip", @"caption", @"quality", @"fullscreen"])) return NO;
    if (YTAGLiteSignatureContainsAny(signature, @[
        @"commententrypoint", @"commentsentrypoint", @"commentsection", @"commentssection",
        @"viewcomments", @"showcomments", @"opencomments"
    ])) return NO;
    return YTAGLiteSignatureContainsAny(signature, @[
        @"like", @"dislike", @"share", @"save", @"remix", @"clip",
        @"badge", @"menu", @"more", @"overflow",
        @"chip", @"richshelf", @"shortsshelf", @"promo", @"productcarousel", @"shoppingrenderer",
        @"shoppingitem", @"shoppingitemlist", @"shoppingcompanion", @"shoppingdrawer",
        @"merchandise", @"merchandiseshelf", @"merchandiseitem", @"channelstore",
        @"shoppingstore", @"storefront", @"storeshelf", @"storebutton", @"storeitem"
    ]);
}

void YTAGLiteModeApplyViewCleanup(UIView *root) {
    if (!YTAGLiteModeEnabled() || !root) return;
    NSString *token = YTAGLiteViewStructureToken(root);
    NSString *cachedToken = objc_getAssociatedObject(root, YTAGLiteViewCleanupTokenKey);
    if ([cachedToken isEqualToString:token]) return;

    root.backgroundColor = root.backgroundColor ?: [UIColor clearColor];
    if ([root isKindOfClass:[UILabel class]]) {
        YTAGLiteModeStyleLabel((UILabel *)root);
    }

    for (UIView *subview in [root.subviews copy]) {
        if (YTAGLiteShouldHideSubview(subview)) {
            subview.hidden = YES;
            subview.alpha = 0.0;
            subview.userInteractionEnabled = NO;
            continue;
        }
        YTAGLiteModeApplyViewCleanup(subview);
    }

    objc_setAssociatedObject(root, YTAGLiteViewCleanupTokenKey, YTAGLiteViewStructureToken(root), OBJC_ASSOCIATION_COPY_NONATOMIC);
}

static BOOL YTAGLiteCommentShouldKeepControl(NSString *signature) {
    return YTAGLiteSignatureContainsAny(signature, @[
        @"reply", @"send", @"composer", @"commentbox", @"textfield", @"textview",
        @"commententrypoint", @"commentsentrypoint", @"commentsection", @"commentssection",
        @"viewcomments", @"showcomments", @"opencomments"
    ]);
}

void YTAGLiteModeApplyCommentChrome(UIView *root) {
    if (!YTAGLiteModeEnabled() || !root) return;
    NSString *token = YTAGLiteViewStructureToken(root);
    NSString *cachedToken = objc_getAssociatedObject(root, YTAGLiteCommentChromeTokenKey);
    if ([cachedToken isEqualToString:token]) return;

    root.backgroundColor = [UIColor clearColor];
    root.layer.cornerRadius = 0.0;
    root.layer.borderWidth = 0.0;

    for (UIView *subview in [root.subviews copy]) {
        NSString *signature = YTAGLiteViewSignature(subview);

        if ([subview isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)subview;
            YTAGLiteModeStyleLabel(label);
            label.textColor = label.textColor ?: [UIColor labelColor];
        }

        BOOL keepControl = YTAGLiteCommentShouldKeepControl(signature);
        if (keepControl) {
            subview.hidden = NO;
            subview.alpha = 1.0;
            subview.userInteractionEnabled = YES;
        }

        BOOL hide = YTAGLiteSignatureContainsAny(signature, @[
            @"avatar", @"like", @"dislike", @"heart", @"vote", @"badge", @"sponsor",
            @"thanks", @"guideline", @"sort", @"chip", @"menu", @"more", @"overflow"
        ]) && !keepControl;

        if (hide) {
            subview.hidden = YES;
            subview.alpha = 0.0;
            subview.userInteractionEnabled = NO;
            continue;
        }

        YTAGLiteModeApplyCommentChrome(subview);
    }

    objc_setAssociatedObject(root, YTAGLiteCommentChromeTokenKey, YTAGLiteViewStructureToken(root), OBJC_ASSOCIATION_COPY_NONATOMIC);
}
