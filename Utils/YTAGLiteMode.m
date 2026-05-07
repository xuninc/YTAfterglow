#import "YTAGLiteMode.h"
#import "YTAGUserDefaults.h"
#import <objc/message.h>

NSString *const YTAGLiteModeEnabledKey = @"liteModeEnabled";
NSString *const YTAGLiteModeDefaultThemeAppliedKey = @"liteModeDefaultThemeApplied";
NSString *const YTAGLiteModeDefaultThemeVersionKey = @"liteModeDefaultThemeVersion";
static const NSInteger YTAGLiteModeCurrentThemeVersion = 2;

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
    [defaults setBool:enabled forKey:YTAGLiteModeEnabledKey];
    if (enabled) YTAGLiteModeApplyDefaultThemeIfNeeded();
    [defaults synchronize];
}

NSArray<NSString *> *YTAGLiteModeActiveTabs(void) {
    return @[@"FEwhat_to_watch", @"FEsubscriptions", @"FElibrary"];
}

NSString *YTAGLiteModeStartupTab(void) {
    return @"FEwhat_to_watch";
}

UIFont *YTAGLiteModeFont(CGFloat size, UIFontWeight weight) {
    CGFloat pointSize = MAX(9.0, size);
    UIFont *font = [UIFont fontWithName:@"CourierNewPSMT" size:pointSize];
    if (!font) font = [UIFont fontWithName:@"Courier" size:pointSize];
    if (!font) font = [UIFont monospacedSystemFontOfSize:pointSize weight:weight];
    return font;
}

void YTAGLiteModeStyleLabel(UILabel *label) {
    if (!label) return;
    CGFloat pointSize = label.font.pointSize > 0 ? label.font.pointSize : 13.0;
    label.font = YTAGLiteModeFont(MAX(10.0, MIN(pointSize, 15.0)), UIFontWeightRegular);
    label.numberOfLines = 0;
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
        @"merch", @"brandpromo", @"feedad", @"adrenderer", @"adslot",
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
    NSString *context = YTAGLiteCollectionContextSignature(collectionView);
    if (YTAGLiteSignatureContainsAny(context, @[
        @"settings", @"setting", @"picker", @"accountmenu", @"accountswitcher",
        @"signin", @"login", @"toast", @"alert", @"dialog"
    ])) {
        return NO;
    }
    return YES;
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
    NSArray<NSString *> *markers = @[
        @"comment", @"comments", @"reply", @"replies", @"composer", @"commentthread", @"commentcell"
    ];
    return YTAGLiteModeViewTreeContainsAny(view, markers, 4);
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
        @"chip", @"richshelf", @"shortsshelf", @"promo", @"productcarousel", @"shoppingrenderer"
    ]);
}

void YTAGLiteModeApplyViewCleanup(UIView *root) {
    if (!YTAGLiteModeEnabled() || !root) return;
    root.backgroundColor = root.backgroundColor ?: [UIColor clearColor];

    for (UIView *subview in [root.subviews copy]) {
        if (YTAGLiteShouldHideSubview(subview)) {
            subview.hidden = YES;
            subview.alpha = 0.0;
            subview.userInteractionEnabled = NO;
            continue;
        }
        YTAGLiteModeApplyViewCleanup(subview);
    }
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
}
