#import "YTAfterglow.h"
#import <objc/message.h>
#import <objc/runtime.h>

static UIImage *YTImageNamed(NSString *imageName) {
    return [UIImage imageNamed:imageName inBundle:[NSBundle mainBundle] compatibleWithTraitCollection:nil];
}

static NSString *const YTAGAdvancedModePromptChoiceKey = @"advancedModePromptChoiceMade";
static NSString *const YTAGLegacyAdvancedModeReminderKey = @"advancedModeReminder";
static const void *kYTAGPauseOnOverlayInternalChangeKey = &kYTAGPauseOnOverlayInternalChangeKey;
static const void *kYTAGShortsOriginalHiddenKey = &kYTAGShortsOriginalHiddenKey;
static const void *kYTAGShortsOriginalAlphaKey = &kYTAGShortsOriginalAlphaKey;
static const void *kYTAGShortsOriginalInteractionKey = &kYTAGShortsOriginalInteractionKey;
static BOOL ytagDidScheduleAdvancedModePrompt = NO;
static id ytagAdvancedModePromptObserver = nil;

static NSString *ytagNormalizedShortsString(NSString *string) {
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

static NSInteger ytagShortsButtonIconType(UIView *view) {
    if (![view respondsToSelector:@selector(buttonRenderer)]) return NSNotFound;
    @try {
        id renderer = ((id (*)(id, SEL))objc_msgSend)(view, @selector(buttonRenderer));
        id icon = [renderer valueForKey:@"icon"];
        id iconType = [icon valueForKey:@"iconType"];
        return [iconType respondsToSelector:@selector(integerValue)] ? [iconType integerValue] : NSNotFound;
    } @catch (__unused id ex) {
        return NSNotFound;
    }
}

static NSString *ytagShortsViewSignature(UIView *view) {
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

    NSInteger iconType = ytagShortsButtonIconType(view);
    if (iconType != NSNotFound) [parts addObject:[NSString stringWithFormat:@"icon%ld", (long)iconType]];
    return ytagNormalizedShortsString([parts componentsJoinedByString:@" "]);
}

static BOOL ytagShortsContainsAny(NSString *signature, NSArray<NSString *> *markers) {
    for (NSString *marker in markers) {
        if ([signature containsString:ytagNormalizedShortsString(marker)]) return YES;
    }
    return NO;
}

static void ytagShortsSetHiddenByAfterglow(UIView *view, BOOL hidden, NSString *reason) {
    if (!view) return;
    NSNumber *storedHidden = objc_getAssociatedObject(view, kYTAGShortsOriginalHiddenKey);
    NSNumber *storedAlpha = objc_getAssociatedObject(view, kYTAGShortsOriginalAlphaKey);
    NSNumber *storedInteraction = objc_getAssociatedObject(view, kYTAGShortsOriginalInteractionKey);

    if (hidden) {
        if (!storedHidden) {
            objc_setAssociatedObject(view, kYTAGShortsOriginalHiddenKey, @(view.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(view, kYTAGShortsOriginalAlphaKey, @(view.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(view, kYTAGShortsOriginalInteractionKey, @(view.userInteractionEnabled), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (!view.hidden || view.alpha > 0.0) {
            YTAGLog(@"shorts-ui", @"hide %@ %@", reason ?: @"view", NSStringFromClass(view.class));
        }
        view.hidden = YES;
        view.alpha = 0.0;
        view.userInteractionEnabled = NO;
    } else if (storedHidden || storedAlpha) {
        view.hidden = storedHidden ? storedHidden.boolValue : NO;
        view.alpha = storedAlpha ? storedAlpha.doubleValue : 1.0;
        view.userInteractionEnabled = storedInteraction ? storedInteraction.boolValue : YES;
        objc_setAssociatedObject(view, kYTAGShortsOriginalHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, kYTAGShortsOriginalAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, kYTAGShortsOriginalInteractionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static BOOL ytagShortsShouldHideActionSignature(NSString *signature, NSInteger iconType, NSString **reason) {
    if (ytagBool(@"hideShortsSearch") && (iconType == 1045 || ytagShortsContainsAny(signature, @[@"search"]))) {
        if (reason) *reason = @"search";
        return YES;
    }
    if (ytagBool(@"hideShortsCamera") && (iconType == 1046 || ytagShortsContainsAny(signature, @[@"camera", @"create"]))) {
        if (reason) *reason = @"camera";
        return YES;
    }
    if (ytagBool(@"hideShortsMore") && (iconType == 1047 || ytagShortsContainsAny(signature, @[@"more", @"overflow", @"menu"]))) {
        if (reason) *reason = @"more";
        return YES;
    }
    if (ytagBool(@"hideShortsDislike") && ytagShortsContainsAny(signature, @[@"dislike", @"thumbsdown"])) {
        if (reason) *reason = @"dislike";
        return YES;
    }
    if (ytagBool(@"hideShortsLike") && !ytagShortsContainsAny(signature, @[@"dislike", @"thumbsdown"]) && ytagShortsContainsAny(signature, @[@"like", @"thumbsup"])) {
        if (reason) *reason = @"like";
        return YES;
    }
    if (ytagBool(@"hideShortsComments") && ytagShortsContainsAny(signature, @[@"comment", @"comments"])) {
        if (reason) *reason = @"comments";
        return YES;
    }
    if (ytagBool(@"hideShortsRemix") && ytagShortsContainsAny(signature, @[@"remix"])) {
        if (reason) *reason = @"remix";
        return YES;
    }
    if (ytagBool(@"hideShortsShare") && ytagShortsContainsAny(signature, @[@"share"])) {
        if (reason) *reason = @"share";
        return YES;
    }
    if (ytagBool(@"hideShortsAvatars") && ytagShortsContainsAny(signature, @[@"avatar", @"nativepivot", @"pivotbutton", @"channelavatar"])) {
        if (reason) *reason = @"avatar";
        return YES;
    }
    return NO;
}

static void ytagShortsApplyActionButtonVisibility(UIView *view) {
    if (!view) return;
    NSString *className = NSStringFromClass(view.class);
    BOOL looksLikeButton = [view isKindOfClass:[UIControl class]] || [className rangeOfString:@"Button" options:NSCaseInsensitiveSearch].location != NSNotFound;
    if (!looksLikeButton) return;

    NSString *signature = ytagShortsViewSignature(view);
    NSString *reason = nil;
    BOOL shouldHide = ytagShortsShouldHideActionSignature(signature, ytagShortsButtonIconType(view), &reason);
    ytagShortsSetHiddenByAfterglow(view, shouldHide, reason);
}

static void ytagShortsApplyActionVisibilityRecursively(UIView *root) {
    for (UIView *subview in root.subviews) {
        ytagShortsApplyActionButtonVisibility(subview);
        if (!subview.hidden) ytagShortsApplyActionVisibilityRecursively(subview);
    }
}

static void ytagShortsApplyNamedViewRules(id object, NSDictionary<NSString *, NSArray<NSString *> *> *rules) {
    if (!object) return;
    for (Class cls = object_getClass(object); cls && cls != [NSObject class]; cls = class_getSuperclass(cls)) {
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(cls, &count);
        for (unsigned int i = 0; i < count; i++) {
            const char *type = ivar_getTypeEncoding(ivars[i]);
            if (!type || type[0] != '@') continue;

            id value = object_getIvar(object, ivars[i]);
            if (![value isKindOfClass:[UIView class]]) continue;

            NSString *name = ytagNormalizedShortsString([NSString stringWithUTF8String:ivar_getName(ivars[i])]);
            UIView *view = (UIView *)value;
            BOOL shouldHide = NO;
            NSString *reason = nil;
            for (NSString *key in rules) {
                if (!ytagBool(key)) continue;
                if (ytagShortsContainsAny(name, rules[key])) {
                    shouldHide = YES;
                    reason = key;
                    break;
                }
            }
            ytagShortsSetHiddenByAfterglow(view, shouldHide, reason);
        }
        free(ivars);
    }
}

static void ytagShortsApplySignatureRulesRecursively(id root, NSDictionary<NSString *, NSArray<NSString *> *> *rules) {
    if (![root isKindOfClass:[UIView class]]) return;

    for (UIView *subview in [(UIView *)root subviews]) {
        NSString *signature = ytagShortsViewSignature(subview);
        BOOL shouldHide = NO;
        NSString *reason = nil;

        for (NSString *key in rules) {
            if (!ytagBool(key)) continue;
            if (ytagShortsContainsAny(signature, [rules objectForKey:key])) {
                shouldHide = YES;
                reason = key;
                break;
            }
        }

        if (shouldHide || objc_getAssociatedObject(subview, kYTAGShortsOriginalHiddenKey)) {
            ytagShortsSetHiddenByAfterglow(subview, shouldHide, reason);
        }
        if (!shouldHide) ytagShortsApplySignatureRulesRecursively(subview, rules);
    }
}

static void ytagShortsApplyOverlayVisibility(UIView *overlay) {
    NSDictionary<NSString *, NSArray<NSString *> *> *rules = @{
        @"hideShortsLike": @[@"reellike", @"likebutton"],
        @"hideShortsDislike": @[@"dislike"],
        @"hideShortsComments": @[@"comment"],
        @"hideShortsRemix": @[@"remix"],
        @"hideShortsShare": @[@"share"],
        @"hideShortsAvatars": @[@"avatar", @"pivot", @"nativepivot"],
    };
    ytagShortsApplyNamedViewRules(overlay, rules);
    ytagShortsApplySignatureRulesRecursively(overlay, rules);
    ytagShortsApplyActionVisibilityRecursively(overlay);
}

static void ytagShortsApplyWatchHeaderVisibility(id header) {
    NSDictionary<NSString *, NSArray<NSString *> *> *rules = @{
        @"hideShortsChannelName": @[@"channelbar", @"channelname", @"username", @"handle", @"author", @"creator", @"byline", @"subscribe", @"follow", @"reelchannel"],
        @"hideShortsDescription": @[@"shortsvideotitle", @"videotitle", @"description", @"desc", @"title", @"expandabletext", @"attributedtitle", @"reelwatchtitle"],
        @"hideShortsAudioTrack": @[@"soundmetadata", @"audiotrack", @"audio", @"music", @"sound"],
        @"hideShortsPromoCards": @[@"actionelement", @"promo", @"promotion", @"suggestion", @"product", @"shopping", @"sticker", @"card"],
        @"hideShortsThanks": @[@"badge", @"thanks", @"superthanks"],
        @"hideShortsSource": @[@"multiformat", @"source", @"link", @"sourcebutton"],
    };
    ytagShortsApplyNamedViewRules(header, rules);
    ytagShortsApplySignatureRulesRecursively(header, rules);
}

static void ytagShortsScrubHeaderRenderer(id renderer) {
    if (!renderer || !ytagBool(@"hideShortsChannelName")) return;
    @try {
        if ([renderer respondsToSelector:@selector(setChannelTitleText:)]) {
            ((void (*)(id, SEL, id))objc_msgSend)(renderer, @selector(setChannelTitleText:), nil);
        } else {
            [renderer setValue:nil forKey:@"channelTitleText"];
        }
    } @catch (__unused id ex) {}
}

static BOOL ytag_commentsPinned(void) {
    return ytagInt(@"commentsHeaderMode") == 1;
}

static BOOL ytag_commentsHidden(void) {
    return ytagInt(@"commentsHeaderMode") == 2;
}

static UIViewController *ytagTopViewController(UIViewController *controller) {
    UIViewController *topController = controller;
    while (topController.presentedViewController) {
        topController = topController.presentedViewController;
    }
    return topController;
}

static void ytagPresentAdvancedModeReminderIfNeeded(void) {
    if (ytagDidScheduleAdvancedModePrompt) return;
    if (ytagBool(@"advancedMode") || ytagBool(YTAGAdvancedModePromptChoiceKey)) {
        if (ytagAdvancedModePromptObserver) {
            [[NSNotificationCenter defaultCenter] removeObserver:ytagAdvancedModePromptObserver];
            ytagAdvancedModePromptObserver = nil;
        }
        return;
    }

    UIApplication *application = UIApplication.sharedApplication;
    if (!application) return;

    UIWindow *window = application.delegate.window;
    if (!window) {
        for (UIScene *scene in application.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;

            for (UIWindow *sceneWindow in ((UIWindowScene *)scene).windows) {
                if (sceneWindow.isKeyWindow) {
                    window = sceneWindow;
                    break;
                }
            }

            if (window) break;
        }
    }

    UIViewController *rootController = window.rootViewController;
    if (!rootController) return;

    ytagDidScheduleAdvancedModePrompt = YES;
    if (ytagAdvancedModePromptObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:ytagAdvancedModePromptObserver];
        ytagAdvancedModePromptObserver = nil;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIViewController *presenter = ytagTopViewController(window.rootViewController);
        if (!presenter || !presenter.view.window || [presenter isKindOfClass:[UIAlertController class]]) {
            ytagDidScheduleAdvancedModePrompt = NO;
            return;
        }

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:LOC(@"AdvancedModePromptTitle")
                                                                       message:LOC(@"AdvancedModePromptMessage")
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:LOC(@"KeepStandardMode")
                                                  style:UIAlertActionStyleCancel
                                                handler:^(__unused UIAlertAction *action) {
            ytagSetBool(YES, YTAGAdvancedModePromptChoiceKey);
            ytagSetBool(YES, YTAGLegacyAdvancedModeReminderKey);
            [[YTAGUserDefaults standardUserDefaults] synchronize];
        }]];
        UIAlertAction *enableAction = [UIAlertAction actionWithTitle:LOC(@"EnableAdvancedMode")
                                                               style:UIAlertActionStyleDefault
                                                             handler:^(__unused UIAlertAction *action) {
            ytagSetBool(YES, @"advancedMode");
            ytagSetBool(YES, YTAGAdvancedModePromptChoiceKey);
            ytagSetBool(YES, YTAGLegacyAdvancedModeReminderKey);
            [[YTAGUserDefaults standardUserDefaults] synchronize];
        }];
        [alert addAction:enableAction];
        alert.preferredAction = enableAction;
        [presenter presentViewController:alert animated:YES completion:nil];
    });
}

static NSURL *ytagSanitizedOpenURL(NSURL *url) {
    if (!url) return nil;

    NSURL *candidate = url;
    NSURLComponents *components = [NSURLComponents componentsWithURL:candidate resolvingAgainstBaseURL:NO];
    NSString *host = components.host.lowercaseString ?: @"";

    if (ytagBool(@"noLinkTracking") && ([host isEqualToString:@"www.google.com"] || [host isEqualToString:@"google.com"])) {
        NSMutableDictionary<NSString *, NSString *> *queryValues = [NSMutableDictionary dictionary];
        for (NSURLQueryItem *item in components.queryItems ?: @[]) {
            if (item.name.length > 0 && item.value.length > 0) queryValues[item.name] = item.value;
        }

        NSString *redirectURLString = queryValues[@"q"] ?: queryValues[@"url"];
        NSURL *redirectURL = redirectURLString.length > 0 ? [NSURL URLWithString:redirectURLString] : nil;
        if (redirectURL) return ytagSanitizedOpenURL(redirectURL);
    }

    if (ytagBool(@"noShareChunk")) {
        BOOL isYouTubeURL = [host hasSuffix:@"youtube.com"] || [host isEqualToString:@"youtu.be"];
        if (isYouTubeURL && components.queryItems.count > 0) {
            NSMutableArray<NSURLQueryItem *> *filteredQueryItems = [NSMutableArray array];
            BOOL removedShareIdentifier = NO;

            for (NSURLQueryItem *item in components.queryItems) {
                if ([item.name isEqualToString:@"si"]) {
                    removedShareIdentifier = YES;
                    continue;
                }
                [filteredQueryItems addObject:item];
            }

            if (removedShareIdentifier) {
                components.queryItems = filteredQueryItems.count > 0 ? filteredQueryItems : nil;
                NSURL *cleanURL = components.URL;
                if (cleanURL) candidate = cleanURL;
            }
        }
    }

    return candidate;
}

%hook UIApplication
- (BOOL)openURL:(NSURL *)url {
    return %orig(ytagSanitizedOpenURL(url));
}

- (void)openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenExternalURLOptionsKey, id> *)options completionHandler:(void (^)(BOOL success))completion {
    %orig(ytagSanitizedOpenURL(url), options, completion);
}
%end

static BOOL canRememberLoopMode = NO;

// Floating Keyboard
%hook UIKeyboardImpl
- (BOOL)floatingForced { return ytagBool(@"floatingKeyboard") ? YES : %orig; }
%end

// YouTube-X (https://github.com/PoomSmart/YouTube-X/)
// Background Playback
%hook YTIPlayabilityStatus
- (BOOL)isPlayableInBackground { return ytagBool(@"backgroundPlayback") ? YES : NO; }
%end

%hook MLVideo
- (BOOL)playableInBackground { return ytagBool(@"backgroundPlayback") ? YES : NO; }
%end

// Disable Ads
%hook YTIPlayerResponse
- (BOOL)isMonetized { return ytagBool(@"noAds") ? NO : YES; }
- (id)playerAdsArray { return ytagBool(@"noAds") ? @[] : %orig; }
- (id)adSlotsArray { return ytagBool(@"noAds") ? @[] : %orig; }
%end

%hook YTLocalPlaybackController
- (id)createAdsPlaybackCoordinator { return ytagBool(@"noAds") ? nil : %orig; }
%end

%hook YTGlobalConfig
- (BOOL)shouldBlockUpgradeDialog { return ytagBool(@"noAds") ? YES : %orig; }
%end

%hook YTDataUtils
+ (id)spamSignalsDictionary { return ytagBool(@"noAds") ? @{} : %orig; }
+ (id)spamSignalsDictionaryWithoutIDFA { return ytagBool(@"noAds") ? @{} : %orig; }
%end

// Also hook YTAdShieldUtils (YouTube may have renamed YTDataUtils)
%hook YTAdShieldUtils
+ (id)spamSignalsDictionary { return ytagBool(@"noAds") ? @{} : %orig; }
+ (id)spamSignalsDictionaryWithoutIDFA { return ytagBool(@"noAds") ? @{} : %orig; }
%end

%hook YTAdsInnerTubeContextDecorator
- (void)decorateContext:(id)context { ytagBool(@"noAds") ? %orig(nil) : %orig; }
%end

%hook YTAccountScopedAdsInnerTubeContextDecorator
- (void)decorateContext:(id)context { ytagBool(@"noAds") ? %orig(nil) : %orig; }
%end

%hook MDXSession
- (void)adPlaying:(id)ad { if (!ytagBool(@"noAds")) %orig; }
%end

%hook YTIElementRenderer
- (NSData *)elementData {
    if (self.hasCompatibilityOptions && self.compatibilityOptions.hasAdLoggingData && ytagBool(@"noAds")) return nil;

    NSString *description = [self description];
    if (YTAGLiteModeShouldPruneFeedObject(self) || YTAGLiteModeShouldPruneFeedObject(description)) {
        return nil;
    }

    NSArray *ads = @[@"brand_promo", @"product_carousel", @"product_engagement_panel", @"product_item", @"text_search_ad", @"text_image_button_layout", @"carousel_headered_layout", @"carousel_footered_layout", @"square_image_layout", @"landscape_image_wide_button_layout", @"feed_ad_metadata"];
    if (ytagBool(@"noAds") && [ads containsObject:description]) {
        return [NSData data];
    }

    NSArray *shortsToRemove = @[@"shorts_shelf.eml", @"shorts_video_cell.eml", @"6Shorts"];
    for (NSString *shorts in shortsToRemove) {
        if (ytagBool(@"hideShorts") && [description containsString:shorts] && ![description containsString:@"history*"]) {
            return nil;
        }
    }

    return %orig;
}
%end

%hook YTSectionListViewController
- (void)loadWithModel:(YTISectionListRenderer *)model {
    if (ytagBool(@"noAds") || YTAGLiteModeEnabled()) {
        NSMutableArray <YTISectionListSupportedRenderers *> *contentsArray = model.contentsArray;
        NSIndexSet *removeIndexes = [contentsArray indexesOfObjectsPassingTest:^BOOL(YTISectionListSupportedRenderers *renderers, NSUInteger idx, BOOL *stop) {
            YTIItemSectionRenderer *sectionRenderer = renderers.itemSectionRenderer;
            YTIItemSectionSupportedRenderers *firstObject = [sectionRenderer.contentsArray firstObject];
            BOOL promoted = firstObject.hasPromotedVideoRenderer || firstObject.hasCompactPromotedVideoRenderer || firstObject.hasPromotedVideoInlineMutedRenderer;
            return promoted || YTAGLiteModeShouldPruneFeedObject(renderers) || YTAGLiteModeShouldPruneFeedObject(sectionRenderer) || YTAGLiteModeShouldPruneFeedObject(firstObject);
        }];
        [contentsArray removeObjectsAtIndexes:removeIndexes];
    } %orig;
}
%end

// NOYTPremium (https://github.com/PoomSmart/NoYTPremium)
// Alert
%hook YTCommerceEventGroupHandler
- (void)addEventHandlers {}
%end

// Full-screen
%hook YTInterstitialPromoEventGroupHandler
- (void)addEventHandlers {}
%end

%hook YTPromosheetEventGroupHandler
- (void)addEventHandlers {}
%end

%hook YTPromoThrottleController
- (BOOL)canShowThrottledPromo { return NO; }
- (BOOL)canShowThrottledPromoWithFrequencyCap:(id)arg1 { return NO; }
- (BOOL)canShowThrottledPromoWithFrequencyCaps:(id)arg1 { return NO; }
%end

%hook YTIShowFullscreenInterstitialCommand
- (BOOL)shouldThrottleInterstitial { return YES; }
%end

// "Try new features" in settings
%hook YTSettingsSectionItemManager
- (void)updatePremiumEarlyAccessSectionWithEntry:(id)arg1 {}
%end

// Survey
%hook YTSurveyController
- (void)showSurveyWithRenderer:(id)arg1 surveyParentResponder:(id)arg2 {}
%end

// Navbar Stuff
// Disable Cast
%hook MDXPlaybackRouteButtonController
- (BOOL)isPersistentCastIconEnabled { return ytagBool(@"noCast") ? NO : YES; }
- (void)updateRouteButton:(id)arg1 { if (!ytagBool(@"noCast")) %orig; }
- (void)updateAllRouteButtons { if (!ytagBool(@"noCast")) %orig; }
%end

%hook YTSettings
- (void)setDisableMDXDeviceDiscovery:(BOOL)arg1 { %orig(ytagBool(@"noCast")); }
%end

// Hide Navigation Bar Buttons
%hook YTRightNavigationButtons
- (void)layoutSubviews {
    %orig;

    if (ytagBool(@"noNotifsButton")) self.notificationButton.hidden = YES;
    if (ytagBool(@"noSearchButton")) self.searchButton.hidden = YES;
    if (YTAGLiteModeEnabled() && self.searchButton) {
        self.searchButton.hidden = NO;
        self.searchButton.alpha = 1.0;
        self.searchButton.userInteractionEnabled = YES;
    }

    for (UIView *subview in self.subviews) {
        if (ytagBool(@"noVoiceSearchButton") && [subview.accessibilityLabel isEqualToString:NSLocalizedString(@"search.voice.access", nil)]) subview.hidden = YES;
        if (ytagBool(@"noCast") && [subview.accessibilityIdentifier isEqualToString:@"id.mdx.playbackroute.button"]) subview.hidden = YES;
    }
}
%end

%hook YTSearchViewController
- (void)viewDidLoad {
    %orig;

    if (ytagBool(@"noVoiceSearchButton")) [self setValue:@(NO) forKey:@"_isVoiceSearchAllowed"];
}

- (void)setSuggestions:(id)arg1 { if (!ytagBool(@"noSearchHistory")) %orig; }
%end

%hook YTPersonalizedSuggestionsCacheProvider
- (id)activeCache { return ytagBool(@"noSearchHistory") ? nil : %orig; }
%end

// Remove Videos Section Under Player
%hook YTWatchNextResultsViewController
- (void)setVisibleSections:(NSInteger)arg1 {
    arg1 = (ytagBool(@"noRelatedWatchNexts")) ? 1 : arg1;
    %orig(arg1);
}
%end

%hook YTYouThereController
- (BOOL)shouldShowYouTherePrompt {
    return ytagBool(@"noContinueWatchingPrompt") ? NO : %orig;
}
%end

%hook YTHeaderView
// Stick Navigation bar
- (BOOL)stickyNavHeaderEnabled { return ytagBool(@"stickyNavbar") ? YES : %orig; }

// Hide YouTube Logo
- (void)setCustomTitleView:(UIView *)customTitleView { if (!ytagBool(@"noYTLogo")) %orig; }
- (void)setTitle:(NSString *)title { ytagBool(@"noYTLogo") ? %orig(@"") : %orig; }
%end

// Premium logo
%hook UIImageView
- (void)setImage:(UIImage *)image {
    if (!ytagBool(@"premiumYTLogo")) return %orig;

    NSString *resourcesPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Frameworks/Module_Framework.framework/Innertube_Resources.bundle"];
    NSBundle *frameworkBundle = [NSBundle bundleWithPath:resourcesPath];

    if ([[image description] containsString:@"Resources: youtube_logo)"]) {
        image = [UIImage imageNamed:@"youtube_premium_logo" inBundle:frameworkBundle compatibleWithTraitCollection:nil];
    }

    else if ([[image description] containsString:@"Resources: youtube_logo_dark)"]) {
        image = [UIImage imageNamed:@"youtube_premium_logo_white" inBundle:frameworkBundle compatibleWithTraitCollection:nil];
    }

    %orig(image);
}
%end

// Remove Subbar
%hook YTMySubsFilterHeaderView
- (void)setChipFilterView:(id)arg1 { if (!ytagBool(@"noSubbar")) %orig; }
%end

%hook YTHeaderContentComboView
- (void)enableSubheaderBarWithView:(id)arg1 { if (!ytagBool(@"noSubbar")) %orig; }
- (void)setFeedHeaderScrollMode:(int)arg1 { ytagBool(@"noSubbar") ? %orig(0) : %orig; }
%end

%hook YTChipCloudCell
- (void)layoutSubviews {
    if (self.superview && ytagBool(@"noSubbar")) {
        [self removeFromSuperview];
    } %orig;
}
%end

%hook YTMainAppControlsOverlayView
// Hide Autoplay Switch
- (void)setAutoplaySwitchButtonRenderer:(id)arg1 { if (ytagInt(@"autoplayMode") != 2) %orig; }

// Hide Subs Button
- (void)setClosedCaptionsOrSubtitlesButtonAvailable:(BOOL)arg1 { ytagBool(@"hideSubs") ? %orig(NO) : %orig; }

// Hide Share / Save buttons under the player when requested.
- (void)setShareButtonAvailable:(BOOL)arg1 { ytagBool(@"noPlayerShareButton") ? %orig(NO) : %orig; }
- (void)setAddToButtonAvailable:(BOOL)arg1 { ytagBool(@"noPlayerSaveButton") ? %orig(NO) : %orig; }

// Pause On Overlay
- (void)setOverlayVisible:(BOOL)visible {
    %orig;

    if (!ytagBool(@"pauseOnOverlay")) return;
    if ([objc_getAssociatedObject(self, kYTAGPauseOnOverlayInternalChangeKey) boolValue]) return;

    id playerController = self.playerViewController;
    SEL action = visible ? @selector(pause) : @selector(play);
    if (![playerController respondsToSelector:action]) return;

    objc_setAssociatedObject(self, kYTAGPauseOnOverlayInternalChangeKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    ((void (*)(id, SEL))objc_msgSend)(playerController, action);
    objc_setAssociatedObject(self, kYTAGPauseOnOverlayInternalChangeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%end

// Remove HUD Messages
%hook YTHUDMessageView
- (id)initWithMessage:(id)arg1 dismissHandler:(id)arg2 { return ytagBool(@"noHUDMsgs") ? nil : %orig; }
%end

%hook YTColdConfig
// Hide Next & Previous buttons
- (BOOL)removeNextPaddleForSingletonVideos { return ytagBool(@"hidePrevNext") ? YES : %orig; }
- (BOOL)removePreviousPaddleForSingletonVideos { return ytagBool(@"hidePrevNext") ? YES : %orig; }
// Replace Next & Previous with Fast Forward & Rewind buttons
- (BOOL)replaceNextPaddleWithFastForwardButtonForSingletonVods { return ytagBool(@"replacePrevNext") ? YES : %orig; }
- (BOOL)replacePreviousPaddleWithRewindButtonForSingletonVods { return ytagBool(@"replacePrevNext") ? YES : %orig; }
// Opaque Tab Bar
- (BOOL)mainAppCoreClientEnableModernIaFrostedBottomBar { return ytagBool(@"frostedPivot") ? NO : %orig; }
- (BOOL)mainAppCoreClientEnableModernIaFrostedPivotBar { return ytagBool(@"frostedPivot") ? NO : %orig; }
- (BOOL)mainAppCoreClientEnableModernIaFrostedPivotBarUpdatedBackdrop { return ytagBool(@"frostedPivot") ? NO : %orig; }
// Disable Free Zoom
- (BOOL)videoZoomFreeZoomEnabledGlobalConfig { return ytagBool(@"noFreeZoom") ? NO : %orig; }
// Stick Sort Buttons in Comments Section
- (BOOL)enableHideChipsInTheCommentsHeaderOnScrollIos { return ytag_commentsPinned() ? NO : %orig; }
// Hide Sort Buttons in Comments Section
- (BOOL)enableChipsInTheCommentsHeaderIos { return ytag_commentsHidden() ? NO : %orig; }
// Disable Ambient Mode
- (BOOL)disableCinematicForLowPowerMode { return ytagBool(@"disableAmbientMode") ? NO : %orig; }
- (BOOL)enableCinematicContainer { return ytagBool(@"disableAmbientMode") ? NO : %orig; }
- (BOOL)enableCinematicContainerOnClient { return ytagBool(@"disableAmbientMode") ? NO : %orig; }
- (BOOL)enableCinematicContainerOnTablet { return ytagBool(@"disableAmbientMode") ? NO : %orig; }
- (BOOL)enableTurnOffCinematicForFrameWithBlackBars { return ytagBool(@"disableAmbientMode") ? YES : %orig; }
- (BOOL)enableTurnOffCinematicForVideoWithBlackBars { return ytagBool(@"disableAmbientMode") ? YES : %orig; }
- (BOOL)iosCinematicContainerClientImprovement { return ytagBool(@"disableAmbientMode") ? NO : %orig; }
- (BOOL)iosEnableGhostCardInlineTitleCinematicContainerFix { return ytagBool(@"disableAmbientMode") ? NO : %orig; }
- (BOOL)iosUseFineScrubberMosaicStoreForCinematic { return ytagBool(@"disableAmbientMode") ? NO : %orig; }
- (BOOL)mainAppCoreClientEnableClientCinematicPlaylists { return ytagBool(@"disableAmbientMode") ? NO : %orig; }
- (BOOL)mainAppCoreClientEnableClientCinematicPlaylistsPostMvp { return ytagBool(@"disableAmbientMode") ? NO : %orig; }
- (BOOL)mainAppCoreClientEnableClientCinematicTablets { return ytagBool(@"disableAmbientMode") ? NO : %orig; }
- (BOOL)iosEnableFullScreenAmbientMode { return ytagBool(@"disableAmbientMode") ? NO : %orig; }
// Startup Animation
- (BOOL)mainAppCoreClientIosEnableStartupAnimation { return ytagBool(@"startupAnimation") ? YES : %orig; }
// Experimental Old UI fallback.
- (BOOL)creatorClientConfigEnableStudioModernizedMdeThumbnailPickerForClient { return ytagBool(@"oldYTUI") ? NO : %orig; }
- (BOOL)cxClientEnableModernizedActionSheet { return ytagBool(@"oldYTUI") ? NO : %orig; }
- (BOOL)enableClientShortsSheetsModernization { return ytagBool(@"oldYTUI") ? NO : %orig; }
- (BOOL)enableTimestampModernizationForNative { return ytagBool(@"oldYTUI") ? NO : %orig; }
- (BOOL)modernizeElementsTextColor { return ytagBool(@"oldYTUI") ? NO : %orig; }
- (BOOL)modernizeElementsBgColor { return ytagBool(@"oldYTUI") ? NO : %orig; }
- (BOOL)modernizeCollectionLockups { return ytagBool(@"oldYTUI") ? NO : %orig; }
- (BOOL)uiSystemsClientGlobalConfigEnableModernButtonsForNative { return ytagBool(@"oldYTUI") ? NO : %orig; }
- (BOOL)uiSystemsClientGlobalConfigIosEnableModernTabsForNative { return ytagBool(@"oldYTUI") ? NO : %orig; }
- (BOOL)uiSystemsClientGlobalConfigIosEnableEpUxUpdates { return ytagBool(@"oldYTUI") ? NO : %orig; }
- (BOOL)uiSystemsClientGlobalConfigIosEnableSheetsUxUpdates { return ytagBool(@"oldYTUI") ? NO : %orig; }
- (BOOL)uiSystemsClientGlobalConfigIosEnableSnackbarModernization { return ytagBool(@"oldYTUI") ? NO : %orig; }
- (BOOL)iosDownloadsPageRoundedThumbs { return ytagBool(@"oldYTUI") ? NO : %orig; }
- (BOOL)iosRoundedSearchBarSuggestZeroPadding { return ytagBool(@"oldYTUI") ? NO : %orig; }
- (BOOL)uiSystemsClientGlobalConfigEnableRoundedDialogForNative { return ytagBool(@"oldYTUI") ? NO : %orig; }
- (BOOL)uiSystemsClientGlobalConfigEnableRoundedThumbnailsForNative { return ytagBool(@"oldYTUI") ? NO : %orig; }
- (BOOL)uiSystemsClientGlobalConfigEnableRoundedThumbnailsForNativeLongTail { return ytagBool(@"oldYTUI") ? NO : %orig; }
- (BOOL)uiSystemsClientGlobalConfigEnableRoundedTimestampForNative { return ytagBool(@"oldYTUI") ? NO : %orig; }
- (BOOL)elementsClientIosElementsEnableLayoutUpdateForIob { return ytagBool(@"oldYTUI") ? NO : %orig; }
- (BOOL)supportElementsInMenuItemSupportedRenderers { return ytagBool(@"oldYTUI") ? NO : %orig; }
- (BOOL)isNewRadioButtonStyleEnabled { return ytagBool(@"oldYTUI") ? NO : %orig; }
- (BOOL)uiSystemsClientGlobalConfigEnableButtonSentenceCasingForNative { return ytagBool(@"oldYTUI") ? NO : %orig; }
- (BOOL)mainAppCoreClientEnableClientYouTab { return ytagBool(@"oldYTUI") ? NO : %orig; }
- (BOOL)mainAppCoreClientEnableClientYouLatency { return ytagBool(@"oldYTUI") ? NO : %orig; }
- (BOOL)mainAppCoreClientEnableClientYouTabTablet { return ytagBool(@"oldYTUI") ? NO : %orig; }
// Use System Theme
- (BOOL)shouldUseAppThemeSetting { return YES; }
// Dismiss Panel By Swiping in Fullscreen Mode
- (BOOL)isLandscapeEngagementPanelSwipeRightToDismissEnabled { return YES; }
// Remove Video in Playlist By Swiping To The Right
- (BOOL)enableSwipeToRemoveInPlaylistWatchEp { return YES; }
// Enable Old-style Minibar For Playlist Panel
- (BOOL)queueClientGlobalConfigEnableFloatingPlaylistMinibar { return ytagBool(@"playlistOldMinibar") ? NO : %orig; }
%end

// Remove Dark Background in Overlay
%hook YTMainAppVideoPlayerOverlayView
- (void)setBackgroundVisible:(BOOL)arg1 isGradientBackground:(BOOL)arg2 { ytagBool(@"noDarkBg") ? %orig(NO, arg2) : %orig; }
%end

%hook YTCinematicContainerView
- (BOOL)watchFullScreenCinematicSupported { return ytagBool(@"disableAmbientMode") ? NO : %orig; }
- (BOOL)watchFullScreenCinematicEnabled { return ytagBool(@"disableAmbientMode") ? NO : %orig; }
%end

// No Endscreen Cards
%hook YTCreatorEndscreenView
- (void)setHidden:(BOOL)arg1 { ytagBool(@"hideEndScreenCards") ? %orig(YES) : %orig; }
%end

// Disable Fullscreen Actions
%hook YTFullscreenActionsView
- (BOOL)enabled {
    BOOL on = ytagBool(@"noFullscreenActions");
    if (!on) return %orig;

    YTAGLog(@"fullscreen", @"YTFullscreenActionsView.enabled forced:NO toggle=ON");
    return NO;
}
- (void)setEnabled:(BOOL)arg1 {
    BOOL on = ytagBool(@"noFullscreenActions");
    if (!on) {
        %orig;
        return;
    }

    YTAGLog(@"fullscreen", @"YTFullscreenActionsView.setEnabled:%@ forced:NO toggle=ON", arg1 ? @"YES" : @"NO");
    %orig(NO);
}
%end

// Dont Show Related Videos on Finish
%hook YTFullscreenEngagementOverlayController
- (void)setRelatedVideosVisible:(BOOL)arg1 { ytagBool(@"noRelatedVids") ? %orig(NO) : %orig; }
%end

// Hide Paid Promotion Cards
%hook YTMainAppVideoPlayerOverlayViewController
- (void)setPaidContentWithPlayerData:(id)data { if (!ytagBool(@"noPromotionCards")) %orig; }
- (void)playerOverlayProvider:(YTPlayerOverlayProvider *)provider didInsertPlayerOverlay:(YTPlayerOverlay *)overlay {
    if ([[overlay overlayIdentifier] isEqualToString:@"player_overlay_paid_content"] && ytagBool(@"noPromotionCards")) return;
    %orig;
}
%end

%hook YTInlineMutedPlaybackPlayerOverlayViewController
- (void)setPaidContentWithPlayerData:(id)data { if (!ytagBool(@"noPromotionCards")) %orig; }
%end

%hook YTInlinePlayerBarContainerView
- (void)setPlayerBarAlpha:(CGFloat)alpha { ytagBool(@"persistentProgressBar") ? %orig(1.0) : %orig; }
%end

// Remove Watermarks
%hook YTAnnotationsViewController
- (void)loadFeaturedChannelWatermark { if (!ytagBool(@"noWatermarks")) %orig; }
%end

%hook YTMainAppVideoPlayerOverlayView
- (BOOL)isWatermarkEnabled { return ytagBool(@"noWatermarks") ? NO : %orig; }
%end

// Forcibly Enable Miniplayer
%hook YTWatchMiniBarViewController
- (void)updateMiniBarPlayerStateFromRenderer { if (!ytagBool(@"miniplayer")) %orig; }
%end

// Portrait Fullscreen
%hook YTWatchViewController
- (unsigned long long)allowedFullScreenOrientations { return ytagBool(@"portraitFullscreen") ? UIInterfaceOrientationMaskAllButUpsideDown : %orig; }
%end

// Disable Autoplay
%hook YTPlaybackConfig
- (void)setStartPlayback:(BOOL)arg1 { ytagInt(@"autoplayMode") >= 1 ? %orig(NO) : %orig; }
%end

// Skip Content Warning (https://github.com/qnblackcat/uYouPlus/blob/main/uYouPlus.xm#L452-L454)
%hook YTPlayabilityResolutionUserActionUIController
- (void)showConfirmAlert { ytagBool(@"noContentWarning") ? [self confirmAlertDidPressConfirm] : %orig; }
%end

// Classic Video Quality (https://github.com/PoomSmart/YTClassicVideoQuality)
%hook YTVideoQualitySwitchControllerFactory
- (id)videoQualitySwitchControllerWithParentResponder:(id)responder {
    Class originalClass = %c(YTVideoQualitySwitchOriginalController);
    return ytagBool(@"classicQuality") && originalClass ? [[originalClass alloc] initWithParentResponder:responder] : %orig;
}
%end

%hook YTColdConfig
- (BOOL)respectDeviceCaptionSetting { return ytagBool(@"rememberCaptionState") ? NO : %orig; }
- (BOOL)iosEnableVideoPlayerScrubber { return ytagBool(@"shortsProgress") ? YES : %orig; }
- (BOOL)mobileShortsTabInlined { return ytagBool(@"shortsProgress") ? YES : %orig; }
- (BOOL)iosUseSystemVolumeControlInFullscreen { return ytagBool(@"stockVolumeHUD") ? YES : %orig; }
%end

// Unlock higher playback speeds in the speed picker without adding another settings toggle.
%hook YTVarispeedSwitchController
- (void)setDelegate:(id)arg1 {
    %orig;

    Class optionClass = %c(YTVarispeedSwitchControllerOption);
    if (!optionClass) return;

    @try {
        id rawOptions = [self valueForKey:@"_options"];
        if (![rawOptions isKindOfClass:[NSArray class]]) return;

        NSMutableArray *optionsCopy = [(NSArray *)rawOptions mutableCopy];
        NSArray<NSNumber *> *speedOptions = @[@2.25f, @2.5f, @2.75f, @3.0f, @3.25f, @3.5f, @3.75f, @4.0f, @4.25f, @4.5f, @4.75f, @5.0f];
        NSMutableSet<NSNumber *> *existingRates = [NSMutableSet set];

        for (id option in optionsCopy) {
            NSNumber *existingRate = nil;
            @try {
                existingRate = [option valueForKey:@"rate"];
            } @catch (__unused NSException *innerException) {}

            if ([existingRate isKindOfClass:[NSNumber class]]) {
                [existingRates addObject:@(existingRate.floatValue)];
            }
        }

        for (NSNumber *rateNumber in speedOptions) {
            NSNumber *normalizedRate = @(rateNumber.floatValue);
            if ([existingRates containsObject:normalizedRate]) continue;

            NSString *title = [NSString stringWithFormat:@"%g×", rateNumber.floatValue];
            YTVarispeedSwitchControllerOption *option = [[optionClass alloc] initWithTitle:title rate:rateNumber.floatValue];
            if (!option) continue;

            [optionsCopy addObject:option];
            [existingRates addObject:normalizedRate];
        }

        [self setValue:[optionsCopy copy] forKey:@"_options"];
    } @catch (__unused NSException *exception) {
        return;
    }
}
%end

static const void *kYTAGStockSpeedmasterActiveKey = &kYTAGStockSpeedmasterActiveKey;
static const void *kYTAGStockSpeedmasterRestoreRateKey = &kYTAGStockSpeedmasterRestoreRateKey;

static NSArray<NSNumber *> *ytagStockSpeedmasterRates(void) {
    static NSArray<NSNumber *> *rates = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        rates = @[
            @0.0,
            @0.0,
            @1.25f,
            @1.5f,
            @1.75f,
            @2.0f,
            @2.25f,
            @2.5f,
            @2.75f,
            @3.0f,
            @3.25f,
            @3.5f,
            @3.75f,
            @4.0f,
            @4.25f,
            @4.5f,
            @4.75f,
            @5.0f
        ];
    });
    return rates;
}

static NSInteger ytagClampedStockSpeedmasterIndex(void) {
    NSInteger speedIndex = ytagInt(@"speedIndex");
    NSInteger maximumIndex = (NSInteger)ytagStockSpeedmasterRates().count - 1;

    if (speedIndex < 0) return 0;
    if (speedIndex > maximumIndex) {
        ytagSetInt((int)maximumIndex, @"speedIndex");
        return maximumIndex;
    }

    return speedIndex;
}

static NSString *ytagGestureStateName(UIGestureRecognizerState state) {
    switch (state) {
        case UIGestureRecognizerStatePossible: return @"possible";
        case UIGestureRecognizerStateBegan: return @"began";
        case UIGestureRecognizerStateChanged: return @"changed";
        case UIGestureRecognizerStateEnded: return @"ended";
        case UIGestureRecognizerStateCancelled: return @"cancelled";
        case UIGestureRecognizerStateFailed: return @"failed";
    }
}

static BOOL ytagShouldLogThrottled(CFAbsoluteTime *lastLogTime, CFTimeInterval interval) {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if ((now - *lastLogTime) < interval) return NO;
    *lastLogTime = now;
    return YES;
}

// Temporary fix for classic quality compatibility.
%hook YTVersionUtils
+ (NSString *)appVersion {
    NSString *originalVersion = %orig;
    NSString *qualityCompatibilityVersion = @"18.18.2";
    NSString *legacyUIVersion = @"17.38.10";

    if (ytagBool(@"oldYTUI")) return legacyUIVersion;
    if (ytagBool(@"classicQuality")) return qualityCompatibilityVersion;
    return originalVersion;
}
%end

// Show real version in YT Settings
%hook YTSettingsCell
- (void)setDetailText:(id)arg1 {
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *appVersion = infoDictionary[@"CFBundleShortVersionString"];

    if ([arg1 isEqualToString:@"18.18.2"] || [arg1 isEqualToString:@"17.38.10"]) {
        arg1 = appVersion;
    } %orig(arg1);
}
%end

%hook YTSpeedmasterController
- (void)speedmasterDidLongPressWithRecognizer:(UILongPressGestureRecognizer *)gesture {
    NSInteger speedIndex = ytagClampedStockSpeedmasterIndex();
    if (speedIndex == 0) return;
    if (speedIndex == 1) {
        NSLog(@"[YTAfterglow] Speedmaster forwarding to stock handler. state=%@ index=%ld", ytagGestureStateName(gesture.state), (long)speedIndex);
        return %orig;
    }

    YTMainAppVideoPlayerOverlayViewController *delegate = nil;
    @try {
        delegate = [self valueForKey:@"_delegate"];
    } @catch (__unused NSException *exception) {
        NSLog(@"[YTAfterglow] Speedmaster missing delegate via KVC. Falling back to stock handler. state=%@ index=%ld", ytagGestureStateName(gesture.state), (long)speedIndex);
        return %orig;
    }

    if (!delegate || ![delegate respondsToSelector:@selector(setPlaybackRate:)] || ![delegate respondsToSelector:@selector(currentPlaybackRate)]) {
        NSLog(@"[YTAfterglow] Speedmaster delegate is unusable. Falling back to stock handler. state=%@ index=%ld delegate=%@", ytagGestureStateName(gesture.state), (long)speedIndex, delegate);
        return %orig;
    }

    NSNumber *selectedRate = ytagStockSpeedmasterRates()[speedIndex];
    BOOL isActive = [objc_getAssociatedObject(self, kYTAGStockSpeedmasterActiveKey) boolValue];

    YTInlinePlayerScrubUserEducationView *edu = nil;
    if ([delegate respondsToSelector:@selector(videoPlayerOverlayView)]) {
        YTMainAppVideoPlayerOverlayView *overlayView = [delegate videoPlayerOverlayView];
        if ([overlayView respondsToSelector:@selector(scrubUserEducationView)]) {
            edu = overlayView.scrubUserEducationView;
        }
    }

    if (edu) {
        YTLabel *label = nil;
        if ([edu respondsToSelector:@selector(userEducationLabel)]) {
            label = [edu userEducationLabel];
        } else {
            @try {
                label = [edu valueForKey:@"_userEducationLabel"];
            } @catch (__unused NSException *exception) {}
        }

        edu.labelType = 1;
        label.text = [NSString stringWithFormat:@"%@: %@×", LOC(@"PlaybackSpeed"), selectedRate];
    }

    if (gesture.state == UIGestureRecognizerStateBegan) {
        if (isActive) return;

        NSLog(@"[YTAfterglow] Speedmaster override began. target=%@ current=%.2f", selectedRate, delegate.currentPlaybackRate);
        objc_setAssociatedObject(self, kYTAGStockSpeedmasterActiveKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kYTAGStockSpeedmasterRestoreRateKey, @(delegate.currentPlaybackRate), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [delegate setPlaybackRate:selectedRate.floatValue];
        [edu setVisible:YES];
        return;
    }

    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) {
        if (!isActive) return;

        NSNumber *restoreRate = objc_getAssociatedObject(self, kYTAGStockSpeedmasterRestoreRateKey);
        NSLog(@"[YTAfterglow] Speedmaster override ending. state=%@ restore=%@", ytagGestureStateName(gesture.state), restoreRate ?: @1.0f);
        [delegate setPlaybackRate:restoreRate ? restoreRate.floatValue : 1.0f];
        objc_setAssociatedObject(self, kYTAGStockSpeedmasterActiveKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kYTAGStockSpeedmasterRestoreRateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [edu setVisible:NO];
        return;
    }

    return;
}
%end

// Experimental legacy UI mode.
%hook YTQTMButton
+ (BOOL)buttonModernizationEnabled { return ytagBool(@"oldYTUI") ? NO : %orig; }
%end

%hook YTBubbleHintView
+ (BOOL)modernRoundedCornersEnabled { return ytagBool(@"oldYTUI") ? NO : %orig; }
%end

// Disable Snap To Chapter (https://github.com/qnblackcat/uYouPlus/blob/main/uYouPlus.xm#L457-464)
%hook YTSegmentableInlinePlayerBarView
- (void)didMoveToWindow { %orig; if (ytagBool(@"dontSnapToChapter")) self.enableSnapToChapter = NO; }
%end

// Progress bar colors now handled by ColorMode.x theme system

void addEndTime(YTPlayerViewController *self, YTSingleVideoController *video, YTSingleVideoTime *time) {
    if (!ytagBool(@"videoEndTime")) return;

    CGFloat rate = video.playbackRate != 0 ? video.playbackRate : 1.0;
    NSTimeInterval remainingTime = (lround(video.totalMediaTime) - lround(time.time)) / rate;

    NSDate *estimatedEndTime = [NSDate dateWithTimeIntervalSinceNow:remainingTime];

    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
    [dateFormatter setDateFormat:ytagBool(@"24hrFormat") ? @"HH:mm" : @"h:mm a"];

    NSString *formattedEndTime = [dateFormatter stringFromDate:estimatedEndTime];

    YTPlayerView *playerView = (YTPlayerView *)self.view;
    if (![playerView.overlayView isKindOfClass:%c(YTMainAppVideoPlayerOverlayView)]) return;

    YTMainAppVideoPlayerOverlayView *overlay = (YTMainAppVideoPlayerOverlayView*)playerView.overlayView;
    YTLabel *durationLabel = overlay.playerBar.durationLabel;
    overlay.playerBar.endTimeString = formattedEndTime;

    if (![durationLabel.text containsString:formattedEndTime]) {
        durationLabel.text = [durationLabel.text stringByAppendingString:[NSString stringWithFormat:@" • %@", formattedEndTime]];
        [durationLabel sizeToFit];
    }
}

void autoSkipShorts(YTPlayerViewController *self, YTSingleVideoController *video, YTSingleVideoTime *time) {
    if (!ytagBool(@"autoSkipShorts")) return;

    if (floor(time.time) >= floor(video.totalMediaTime)) {
        if ([self.parentViewController isKindOfClass:%c(YTShortsPlayerViewController)]) {
            YTShortsPlayerViewController *shortsVC = (YTShortsPlayerViewController *)self.parentViewController;

            if ([shortsVC respondsToSelector:@selector(reelContentViewRequestsAdvanceToNextVideo:)]) {
                [shortsVC performSelector:@selector(reelContentViewRequestsAdvanceToNextVideo:)];
            }
        }
    }
}

%hook YTPlayerViewController
- (void)loadWithPlayerTransition:(id)arg1 playbackConfig:(id)arg2 {
    %orig;

    if (ytagInt(@"wiFiQualityIndex") != 0 || ytagInt(@"cellQualityIndex") != 0) [self performSelector:@selector(autoQuality) withObject:nil afterDelay:1.0];
    if (ytagBool(@"autoFullscreen")) [self performSelector:@selector(autoFullscreen) withObject:nil afterDelay:0.75];
    if (ytagBool(@"shortsToRegular")) [self performSelector:@selector(shortsToRegular) withObject:nil afterDelay:0.75];
    if (ytagInt(@"autoSpeedIndex") != 3) [self performSelector:@selector(setAutoSpeed) withObject:nil afterDelay:0.75];
    if (ytagBool(@"disableAutoCaptions")) [self performSelector:@selector(turnOffCaptions) withObject:nil afterDelay:1.0];
}

- (void)playbackController:(id)arg1 didActivateVideo:(id)arg2 withPlaybackData:(id)arg3 {
    canRememberLoopMode = NO;
    %orig;

    if (ytagBool(@"rememberLoop")) [self performSelector:@selector(restoreLoopMode) withObject:nil afterDelay:3.0];
}

%new
- (void)autoFullscreen {
    YTWatchController *watchController = [self valueForKey:@"_UIDelegate"];
    [watchController showFullScreen];
}

%new
- (void)shortsToRegular {
    if (self.contentVideoID != nil && [self.parentViewController isKindOfClass:NSClassFromString(@"YTShortsPlayerViewController")]) {
        NSString *vidLink = [NSString stringWithFormat:@"vnd.youtube://%@", self.contentVideoID];
        if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:vidLink]]) {
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:vidLink] options:@{} completionHandler:nil];
        }
    }
}

%new
- (void)turnOffCaptions {
    if ([self.view.superview isKindOfClass:NSClassFromString(@"YTWatchView")]) {
        [self setActiveCaptionTrack:nil];
    }
}

%new
- (void)setAutoSpeed {
    if ([self.activeVideoPlayerOverlay isKindOfClass:NSClassFromString(@"YTMainAppVideoPlayerOverlayViewController")]
        && [self.view.superview isKindOfClass:NSClassFromString(@"YTWatchView")]) {
        YTMainAppVideoPlayerOverlayViewController *overlayVC = (YTMainAppVideoPlayerOverlayViewController *)self.activeVideoPlayerOverlay;

        NSArray *speedLabels = @[@0.25, @0.5, @0.75, @1.0, @1.25, @1.5, @1.75, @2.0, @3.0, @4.0, @5.0];
        [overlayVC setPlaybackRate:[speedLabels[ytagInt(@"autoSpeedIndex")] floatValue]];
    }
}

%new
- (void)restoreLoopMode {
    id overlay = self.activeVideoPlayerOverlay;
    if ([overlay isKindOfClass:NSClassFromString(@"YTMainAppVideoPlayerOverlayViewController")] &&
        [overlay respondsToSelector:@selector(loopMode)] &&
        [overlay respondsToSelector:@selector(setLoopMode:)]) {
        [overlay setLoopMode:ytagInt(@"loopMode")];
    }

    id activeVideo = [self activeVideo];
    id delegate = [activeVideo delegate];
    if ([delegate isKindOfClass:NSClassFromString(@"YTLocalPlaybackController")] &&
        [delegate respondsToSelector:@selector(loopingEnabled)] &&
        ytagInt(@"loopMode") != 0 &&
        [delegate respondsToSelector:@selector(setLoopingEnabled:)]) {
        [delegate setLoopingEnabled:YES];
    }

    canRememberLoopMode = YES;
}

%new
- (void)autoQuality {
    if (![self.view.superview isKindOfClass:NSClassFromString(@"YTWatchView")]) {
        return;
    }

    NetworkStatus status = [[Reachability reachabilityForInternetConnection] currentReachabilityStatus];
    NSInteger kQualityIndex = status == ReachableViaWiFi ? ytagInt(@"wiFiQualityIndex") : ytagInt(@"cellQualityIndex");

    NSString *bestQualityLabel;
    int highestResolution = 0;
    for (MLFormat *format in self.activeVideo.selectableVideoFormats) {
        int reso = format.singleDimensionResolution;
        if (reso > highestResolution) {
            highestResolution = reso;
            bestQualityLabel = format.qualityLabel;
        }
    }

    NSArray *qualityLabels = @[@"Default", bestQualityLabel, @"2160p60", @"2160p", @"1440p60", @"1440p", @"1080p60", @"1080p", @"720p60", @"720p", @"480p", @"360p"];
    NSString *qualityLabel = qualityLabels[kQualityIndex];

    if (![qualityLabel isEqualToString:bestQualityLabel]) {
        BOOL exactMatch = NO;
        NSString *closestQualityLabel = qualityLabel;

        for (MLFormat *format in self.activeVideo.selectableVideoFormats) {
            if ([format.qualityLabel isEqualToString:qualityLabel]) {
                exactMatch = YES;
                break;
            }
        }

        if (!exactMatch) {
            NSInteger bestQualityDifference = NSIntegerMax;

            for (MLFormat *format in self.activeVideo.selectableVideoFormats) {
                NSArray *formatСomponents = [format.qualityLabel componentsSeparatedByString:@"p"];
                NSArray *targetComponents = [qualityLabel componentsSeparatedByString:@"p"];
                if (formatСomponents.count == 2) {
                    NSInteger formatQuality = [formatСomponents.firstObject integerValue];
                    NSInteger targetQuality = [targetComponents.firstObject integerValue];
                    NSInteger difference = labs(formatQuality - targetQuality);
                    if (difference < bestQualityDifference) {
                        bestQualityDifference = difference;
                        closestQualityLabel = format.qualityLabel;
                    }
                }
            }

            qualityLabel = closestQualityLabel;
        }
    }

    MLQuickMenuVideoQualitySettingFormatConstraint *fc = [[%c(MLQuickMenuVideoQualitySettingFormatConstraint) alloc] init];
    if ([fc respondsToSelector:@selector(initWithVideoQualitySetting:formatSelectionReason:qualityLabel:)]) {
        [self.activeVideo setVideoFormatConstraint:[fc initWithVideoQualitySetting:3 formatSelectionReason:2 qualityLabel:qualityLabel]];
    }
}

- (void)singleVideo:(YTSingleVideoController *)video currentVideoTimeDidChange:(YTSingleVideoTime *)time {
    %orig;

    addEndTime(self, video, time);
    autoSkipShorts(self, video, time);
}

- (void)potentiallyMutatedSingleVideo:(YTSingleVideoController *)video currentVideoTimeDidChange:(YTSingleVideoTime *)time {
    %orig;

    addEndTime(self, video, time);
    autoSkipShorts(self, video, time);
}
%end

%hook YTInlinePlayerBarContainerView
%property (nonatomic, strong) NSString *endTimeString;
- (void)setPeekableViewVisible:(BOOL)visible {
    %orig;

    if (!ytagBool(@"videoEndTime")) return;

    if (self.endTimeString && ![self.durationLabel.text containsString:self.endTimeString]) {
        self.durationLabel.text = [self.durationLabel.text stringByAppendingString:[NSString stringWithFormat:@" • %@", self.endTimeString]];
        [self.durationLabel sizeToFit];
    }
}
%end

// Exit Fullscreen on Finish
%hook YTWatchFlowController
- (BOOL)shouldExitFullScreenOnFinish { return ytagBool(@"exitFullscreen") ? YES : NO; }
%end

%hook YTMainAppVideoPlayerOverlayViewController
// Disable Double Tap To Seek
- (BOOL)allowDoubleTapToSeekGestureRecognizer { return ytagBool(@"noDoubleTapToSeek") ? NO : %orig; }

// Disable Two Finger Double Tap
- (BOOL)allowTwoFingerDoubleTapGestureRecognizer { return ytagBool(@"noTwoFingerSnapToChapter") ? NO : %orig; }

// Copy Timestamped Link by Pressing On Pause
- (void)didPressPause:(id)arg1 {
    %orig;

    if (ytagBool(@"copyWithTimestamp")) {
        NSInteger mediaTimeInteger = (NSInteger)self.mediaTime;
        NSString *currentTimeLink = [NSString stringWithFormat:@"https://www.youtube.com/watch?v=%@&t=%lds", self.videoID, mediaTimeInteger];

        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        pasteboard.string = currentTimeLink;
    }
}

- (void)setLoopMode:(NSInteger)mode {
    %orig;

    if (canRememberLoopMode) [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:@"loopMode"];
}
%end

// Fit 'Play All' Buttons Text For Localizations
%hook YTQTMButton
- (UILabel *)titleLabel {
    UILabel *label = %orig;

    if ([self.accessibilityIdentifier isEqualToString:@"id.playlist.playall.button"]) {
        label.adjustsFontSizeToFitWidth = YES;
    }

    return label;
}
%end

// Fit Shorts Button Labels For Localizations
%hook YTReelPlayerButton
- (void)layoutSubviews {
    %orig;
    ytagShortsApplyActionButtonVisibility(self);
}

- (UILabel *)titleLabel {
    UILabel *label = %orig;
    label.adjustsFontSizeToFitWidth = YES;

    return label;
}
%end

// Fix Playlist Mini-bar Height For Small Screens
%hook YTPlaylistMiniBarView
- (void)setFrame:(CGRect)frame {
    if (frame.size.height < 54.0) frame.size.height = 54.0;
    %orig(frame);
}
%end

// Remove "Play next in queue" from the menu @PoomSmart (https://github.com/qnblackcat/uYouPlus/issues/1138#issuecomment-1606415080)
%hook YTMenuItemVisibilityHandler
- (BOOL)shouldShowServiceItemRenderer:(YTIMenuConditionalServiceItemRenderer *)renderer {
    if (ytagBool(@"removePlayNext") && renderer.icon.iconType == 251) {
        return NO;
    } return %orig;
}
%end

// Remove Download button from the menu
%hook YTDefaultSheetController
- (void)addAction:(YTActionSheetAction *)action {
    NSString *identifier = [action valueForKey:@"_accessibilityIdentifier"];

    NSDictionary *actionsToRemove = @{
        @"7": @(ytagBool(@"removeDownloadMenu")),
        @"1": @(ytagBool(@"removeWatchLaterMenu")),
        @"3": @(ytagBool(@"removeSaveToPlaylistMenu")),
        @"5": @(ytagBool(@"removeShareMenu")),
        @"12": @(ytagBool(@"removeNotInterestedMenu")),
        @"31": @(ytagBool(@"removeDontRecommendMenu")),
        @"58": @(ytagBool(@"removeReportMenu"))
    };

    if (![actionsToRemove[identifier] boolValue]) {
        %orig;
    }
}
%end

// Hide buttons under the video player (@PoomSmart)
static BOOL ytagObjectContainsActionBarMarkers(id object, NSArray<NSString *> *includeMarkers, NSArray<NSString *> *excludeMarkers) {
    if (!object || includeMarkers.count == 0) return NO;

    NSMutableArray<NSString *> *haystacks = [NSMutableArray array];
    if ([object isKindOfClass:[NSString class]]) {
        [haystacks addObject:(NSString *)object];
    } else {
        NSString *desc = [object description];
        if (desc.length > 0) [haystacks addObject:desc];
        for (NSString *key in @[@"accessibilityIdentifier", @"_accessibilityIdentifier", @"accessibilityLabel", @"title", @"text"]) {
            @try {
                id value = [object valueForKey:key];
                if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
                    [haystacks addObject:value];
                }
            } @catch (__unused id ex) {}
        }
    }

    NSString *combined = [[haystacks componentsJoinedByString:@" "] lowercaseString];
    if (combined.length == 0) return NO;
    for (NSString *excluded in excludeMarkers ?: @[]) {
        if ([combined containsString:excluded.lowercaseString]) return NO;
    }
    for (NSString *marker in includeMarkers) {
        if ([combined containsString:marker.lowercaseString]) return YES;
    }
    return NO;
}

static BOOL ytagPlayerActionBarMatches(ASNodeController *nodeController, NSArray<NSString *> *includeMarkers, NSArray<NSString *> *excludeMarkers) {
    for (id child in [nodeController children]) {
        if ([child isKindOfClass:%c(ELMNodeController)]) {
            NSArray <ELMComponent *> *elmChildren = [(ELMNodeController *)child children];
            for (ELMComponent *elmChild in elmChildren) {
                if (ytagObjectContainsActionBarMarkers(elmChild, includeMarkers, excludeMarkers)) return YES;
            }
        }

        if ([child isKindOfClass:%c(ASNodeController)]) {
            ASDisplayNode *childNode = ((ASNodeController *)child).node; // ELMContainerNode
            if (ytagObjectContainsActionBarMarkers(childNode, includeMarkers, excludeMarkers)) return YES;
            NSArray *yogaChildren = childNode.yogaChildren;
            for (ASDisplayNode *displayNode in yogaChildren) {
                if (ytagObjectContainsActionBarMarkers(displayNode, includeMarkers, excludeMarkers)) return YES;
            }

            if (ytagPlayerActionBarMatches((ASNodeController *)child, includeMarkers, excludeMarkers))
                return YES;
        }
    }
    return NO;
}

static BOOL ytagStringContainsMarkers(NSString *string, NSArray<NSString *> *markers) {
    if (![string isKindOfClass:[NSString class]] || string.length == 0) return NO;

    NSString *lowercased = string.lowercaseString;
    for (NSString *marker in markers) {
        if ([lowercased containsString:marker.lowercaseString]) {
            return YES;
        }
    }

    return NO;
}

static BOOL ytagCellLooksLikeContinueWatching(UICollectionViewCell *cell) {
    NSArray<NSString *> *continueWatchingMarkers = @[
        @"continue watching",
        @"continue_watching",
        @"watch history",
        @"resume watching",
        @"watching_history",
        @"watch_history",
        @"resume_history"
    ];

    if (ytagStringContainsMarkers(cell.accessibilityIdentifier, continueWatchingMarkers) ||
        ytagStringContainsMarkers([cell description], continueWatchingMarkers)) {
        return YES;
    }

    if ([cell isKindOfClass:objc_lookUpClass("_ASCollectionViewCell")]) {
        _ASCollectionViewCell *asCell = (_ASCollectionViewCell *)cell;
        if ([asCell respondsToSelector:@selector(node)]) {
            ASDisplayNode *node = [asCell node];
            if (ytagStringContainsMarkers(node.accessibilityIdentifier, continueWatchingMarkers) ||
                ytagStringContainsMarkers([node description], continueWatchingMarkers)) {
                return YES;
            }
        }
    }

    return NO;
}

%hook ASCollectionView
- (CGSize)sizeForElement:(ASCollectionElement *)element {
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.scrollable_action_bar"]) {
        ASCellNode *node = [element node];
        ASNodeController *nodeController = [node controller];

        if (ytagBool(@"noPlayerRemixButton") && ytagPlayerActionBarMatches(nodeController, @[@"id.video.remix.button", @"remix"], nil)) {
            return CGSizeZero;
        }

        if (ytagBool(@"noPlayerShareButton") && ytagPlayerActionBarMatches(nodeController, @[@"id.video.share.button", @"share"], nil)) {
            return CGSizeZero;
        }

        if (ytagBool(@"noPlayerClipButton") && ytagPlayerActionBarMatches(nodeController, @[@"clip_button.eml", @"clip"], nil)) {
            return CGSizeZero;
        }

        if (ytagBool(@"noPlayerDownloadButton") && ytagPlayerActionBarMatches(nodeController, @[@"id.ui.add_to.offline.button", @"offline.button", @"download"], nil)) {
            return CGSizeZero;
        }

        if (ytagBool(@"noPlayerSaveButton") && ytagPlayerActionBarMatches(nodeController, @[@"id.video.add_to.button", @"save", @"add_to.button", @"add to"], @[@"offline", @"download"])) {
            return CGSizeZero;
        }
    }

    if (YTAGLiteModeShouldCleanCollectionView(self)) {
        ASCellNode *node = [element node];
        if (YTAGLiteModeShouldPruneFeedObject(element) ||
            YTAGLiteModeShouldPruneFeedObject(node) ||
            YTAGLiteModeShouldPruneFeedObject([node controller])) {
            return CGSizeZero;
        }
    }

    return %orig;
}
%end

static void ytagLiteModeCleanupCollectionCell(UICollectionViewCell *cell) {
    if (!YTAGLiteModeEnabled() || !cell) return;
    BOOL isCommentSurface = YTAGLiteModeShouldStyleCommentView(cell);
    if (!isCommentSurface) {
        YTAGLiteModeApplyViewCleanup(cell);
    }
    if (isCommentSurface) {
        YTAGLiteModeApplyCommentChrome(cell);
    }
}

// Remove Premium Pop-up, Horizontal Video Carousel and Shorts (https://github.com/MiRO92/YTNoShorts)
%hook YTAsyncCollectionView
- (id)cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = %orig;

    if ([cell isKindOfClass:objc_lookUpClass("_ASCollectionViewCell")]) {
        _ASCollectionViewCell *asCell = (_ASCollectionViewCell *)cell;
        if ([asCell respondsToSelector:@selector(node)]) {
            NSString *idToRemove = [[asCell node] accessibilityIdentifier];
            if ([idToRemove isEqualToString:@"statement_banner.view"] ||
                (([idToRemove isEqualToString:@"eml.shorts-grid"] || [idToRemove isEqualToString:@"eml.shorts-shelf"]) && ytagBool(@"hideShorts"))) {
                [self removeCellsAtIndexPath:indexPath];
            }

            if (YTAGLiteModeShouldPruneFeedObject([asCell node])) {
                [self removeCellsAtIndexPath:indexPath];
            }
        }
    }

    if (ytagBool(@"noContinueWatching") && ytagCellLooksLikeContinueWatching(cell)) {
        [self removeCellsAtIndexPath:indexPath];
    } else if ([cell isKindOfClass:objc_lookUpClass("YTReelShelfCell")] && ytagBool(@"hideShorts")) {
        [self removeCellsAtIndexPath:indexPath];
    }

    if (YTAGLiteModeShouldCleanCollectionView(self)) {
        if (YTAGLiteModeShouldRemoveFeedView(cell) || YTAGLiteModeShouldPruneFeedObject(cell)) {
            [self removeCellsAtIndexPath:indexPath];
        } else {
            ytagLiteModeCleanupCollectionCell(cell);
        }
    }
    return cell;
}

- (void)layoutSubviews {
    %orig;

    if (!YTAGLiteModeShouldCleanCollectionView(self)) return;
    for (UICollectionViewCell *cell in [self.visibleCells copy]) {
        if (YTAGLiteModeShouldRemoveFeedView(cell)) continue;
        ytagLiteModeCleanupCollectionCell(cell);
    }
}

%new
- (void)removeCellsAtIndexPath:(NSIndexPath *)indexPath {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (indexPath.section >= [self numberOfSections]) return;
        if (indexPath.item >= [self numberOfItemsInSection:indexPath.section]) return;

        [self performBatchUpdates:^{
            [self deleteItemsAtIndexPaths:@[indexPath]];
        } completion:nil];
    });
}
%end

// Shorts Progress Bar (https://github.com/PoomSmart/YTShortsProgress)
%hook YTReelPlayerViewController
- (BOOL)shouldEnablePlayerBar { return ytagBool(@"shortsProgress") ? YES : NO; }
- (BOOL)shouldAlwaysEnablePlayerBar { return ytagBool(@"shortsProgress") ? YES : NO; }
- (BOOL)shouldEnablePlayerBarOnlyOnPause { return ytagBool(@"shortsProgress") ? NO : YES; }
%end

%hook YTReelPlayerViewControllerSub
- (BOOL)shouldEnablePlayerBar { return ytagBool(@"shortsProgress") ? YES : NO; }
- (BOOL)shouldAlwaysEnablePlayerBar { return ytagBool(@"shortsProgress") ? YES : NO; }
- (BOOL)shouldEnablePlayerBarOnlyOnPause { return ytagBool(@"shortsProgress") ? NO : YES; }
%end

%hook YTShortsPlayerViewController
- (BOOL)shouldAlwaysEnablePlayerBar { return ytagBool(@"shortsProgress") ? YES : NO; }
- (BOOL)shouldEnablePlayerBarOnlyOnPause { return ytagBool(@"shortsProgress") ? NO : YES; }
%end

%hook YTHotConfig
- (BOOL)enablePlayerBarForVerticalVideoWhenControlsHiddenInFullscreen { return ytagBool(@"shortsProgress") ? YES : NO; }
- (BOOL)liveChatIosUseModernRotationDetection { return ytagBool(@"oldYTUI") ? NO : %orig; }
- (BOOL)liveChatModernizeClassicElementizeTextMessage { return ytagBool(@"oldYTUI") ? NO : %orig; }
- (BOOL)iosShouldRepositionChannelBar { return ytagBool(@"oldYTUI") ? NO : %orig; }
- (BOOL)enableElementRendererOnChannelCreation { return ytagBool(@"oldYTUI") ? NO : %orig; }
%end

%hook YTInlinePlayerBarContainerView
- (BOOL)canShowHeatwave { return ytagBool(@"hideHeatwaves") ? NO : %orig; }
- (CGFloat)scrubRangeForScrubX:(CGFloat)x {
    CGFloat range = %orig;

    static CFAbsoluteTime lastScrubRangeLogTime = 0;
    if (ytagShouldLogThrottled(&lastScrubRangeLogTime, 0.4)) {
        NSLog(@"[YTAfterglow] Stock scrub range used. x=%.2f range=%.4f", x, range);
    }

    return range;
}

- (void)didPressScrubber:(id)gesture {
    UIGestureRecognizerState state = UIGestureRecognizerStatePossible;
    CGPoint location = CGPointZero;
    BOOL hasGestureState = [gesture respondsToSelector:@selector(state)];
    BOOL hasLocation = [gesture respondsToSelector:@selector(locationInView:)];

    if (hasGestureState) {
        state = ((UIGestureRecognizer *)gesture).state;
    }

    if (hasLocation) {
        location = [gesture locationInView:self];
    }

    NSLog(@"[YTAfterglow] Stock didPressScrubber fired. gesture=%@ state=%@ x=%.2f tapToSeek=%@", NSStringFromClass([gesture class]), ytagGestureStateName(state), location.x, ytagBool(@"tapToSeek") ? @"on" : @"off");

    %orig;

    if (!ytagBool(@"tapToSeek")) return;

    id ancestor = [self _viewControllerForAncestor];
    id parent = [ancestor parentViewController];
    if (![parent isKindOfClass:NSClassFromString(@"YTPlayerViewController")]) return;

    CGFloat scrubRange = [self scrubRangeForScrubX:location.x];
    CGFloat totalMediaTime = ((CGFloat (*)(id, SEL))objc_msgSend)(parent, @selector(currentVideoTotalMediaTime));
    NSLog(@"[YTAfterglow] Tap-to-seek override seeking. range=%.4f total=%.2f target=%.2f", scrubRange, totalMediaTime, scrubRange * totalMediaTime);
    ((void (*)(id, SEL, CGFloat))objc_msgSend)(parent, @selector(seekToTime:), scrubRange * totalMediaTime);
}
%end

// Dont Startup Shorts
%hook YTShortsStartupCoordinator
- (id)evaluateResumeToShorts { return ytagBool(@"resumeShorts") ? nil : %orig; }
%end

// Hide Shorts Elements
%hook YTReelPausedStateCarouselView
- (void)layoutSubviews {
    %orig;
    ytagShortsSetHiddenByAfterglow((UIView *)self, ytagBool(@"hideShortsSubscriptions"), @"subscriptions-carousel");
}

- (void)didMoveToWindow {
    %orig;
    ytagShortsSetHiddenByAfterglow((UIView *)self, ytagBool(@"hideShortsSubscriptions"), @"subscriptions-carousel");
}

- (void)setPausedStateCarouselVisible:(BOOL)arg1 animated:(BOOL)arg2 {
    BOOL visible = ytagBool(@"hideShortsSubscriptions") ? NO : arg1;
    %orig(visible, arg2);
    ytagShortsSetHiddenByAfterglow((UIView *)self, ytagBool(@"hideShortsSubscriptions"), @"subscriptions-carousel");
}
%end

%hook YTReelWatchPlaybackOverlayView
- (void)layoutSubviews {
    %orig;
    ytagShortsApplyOverlayVisibility(self);
}

- (void)didMoveToWindow {
    %orig;
    ytagShortsApplyOverlayVisibility(self);
}

- (void)setReelLikeButton:(id)arg1 { %orig; ytagShortsApplyOverlayVisibility(self); }
- (void)setReelDislikeButton:(id)arg1 { %orig; ytagShortsApplyOverlayVisibility(self); }
- (void)setViewCommentButton:(id)arg1 { %orig; ytagShortsApplyOverlayVisibility(self); }
- (void)setRemixButton:(id)arg1 { %orig; ytagShortsApplyOverlayVisibility(self); }
- (void)setShareButton:(id)arg1 { %orig; ytagShortsApplyOverlayVisibility(self); }
- (void)setNativePivotButton:(id)arg1 { %orig; ytagShortsApplyOverlayVisibility(self); }
- (void)setPivotButtonElementRenderer:(id)arg1 { %orig; ytagShortsApplyOverlayVisibility(self); }
%end

%hook YTReelHeaderView
- (void)layoutSubviews {
    %orig;
    NSDictionary *rules = @{@"hideShortsLogo": @[@"shortslogo", @"logo", @"title"]};
    ytagShortsApplyNamedViewRules(self, rules);
    ytagShortsApplySignatureRulesRecursively(self, rules);
}
- (void)setTitleLabelVisible:(BOOL)arg1 animated:(BOOL)arg2 { %orig(ytagBool(@"hideShortsLogo") ? NO : arg1, arg2); }
%end

%hook YTReelTransparentStackView
- (void)layoutSubviews {
    %orig;

    ytagShortsApplyActionVisibilityRecursively(self);
}
%end

%hook YTReelWatchHeaderView
- (void)layoutSubviews {
    %orig;
    ytagShortsApplyWatchHeaderVisibility(self);
}

- (void)didMoveToWindow {
    %orig;
    ytagShortsApplyWatchHeaderVisibility(self);
}

- (void)setChannelBarElementRenderer:(id)renderer {
    %orig(ytagBool(@"hideShortsChannelName") ? nil : renderer);
    ytagShortsApplyWatchHeaderVisibility(self);
}
- (void)setHeaderRenderer:(id)renderer {
    ytagShortsScrubHeaderRenderer(renderer);
    %orig(renderer);
    ytagShortsApplyWatchHeaderVisibility(self);
}
- (void)setShortsVideoTitleElementRenderer:(id)renderer {
    %orig(ytagBool(@"hideShortsDescription") ? nil : renderer);
    ytagShortsApplyWatchHeaderVisibility(self);
}
- (void)setSoundMetadataElementRenderer:(id)renderer { %orig; ytagShortsApplyWatchHeaderVisibility(self); }
- (void)setActionElement:(id)renderer { %orig; ytagShortsApplyWatchHeaderVisibility(self); }
- (void)setBadgeRenderer:(id)renderer { %orig; ytagShortsApplyWatchHeaderVisibility(self); }
- (void)setMultiFormatLinkElementRenderer:(id)renderer { %orig; ytagShortsApplyWatchHeaderVisibility(self); }
%end

%hook YTIReelPlayerHeaderRenderer
- (void)setChannelTitleText:(id)text {
    %orig(ytagBool(@"hideShortsChannelName") ? nil : text);
}
%end

static BOOL isOverlayShown = YES;

%hook YTPlayerView
- (void)didPinch:(UIPinchGestureRecognizer *)gesture {
    %orig;

    if (ytagBool(@"pinchToFullscreenShorts") && [self.playerViewDelegate.parentViewController isKindOfClass:NSClassFromString(@"YTShortsPlayerViewController")]) {
        YTShortsPlayerViewController *shortsPlayerVC = (YTShortsPlayerViewController *)self.playerViewDelegate.parentViewController;
        YTReelContentView *contentView = (YTReelContentView *)shortsPlayerVC.view;
        UIWindow *mainWindow = [[[UIApplication sharedApplication] delegate] window];
        YTAppViewController *appVC = (YTAppViewController *)mainWindow.rootViewController;

        if (gesture.scale > 1) {
            if (!ytagBool(@"shortsOnlyMode")) [appVC hidePivotBar];

            [UIView animateWithDuration:0.3 animations:^{
                contentView.playbackOverlay.alpha = 0;
                isOverlayShown = contentView.playbackOverlay.alpha;
            }];
        } else {
            if (!ytagBool(@"shortsOnlyMode")) [appVC showPivotBar];

            [UIView animateWithDuration:0.3 animations:^{
                contentView.playbackOverlay.alpha = 1;
                isOverlayShown = contentView.playbackOverlay.alpha;
            }];
        }
    }
}
%end

%hook YTReelContentView
- (void)setPlaybackView:(id)arg1 {
    %orig;

    self.playbackOverlay.alpha = isOverlayShown;

    if (ytagBool(@"shortsOnlyMode")) {
        UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(turnShortsOnlyModeOff:)];
        longPressGesture.numberOfTouchesRequired = 2;
        longPressGesture.minimumPressDuration = 0.5;

        [self addGestureRecognizer:longPressGesture];
    }
}

%new
- (void)turnShortsOnlyModeOff:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        ytagSetBool(NO, @"shortsOnlyMode");

        [[%c(YTToastResponderEvent) eventWithMessage:LOC(@"ShortsModeTurnedOff") firstResponder:[%c(YTUIUtils) topViewControllerForPresenting]] send];

        UIWindow *mainWindow = [[[UIApplication sharedApplication] delegate] window];
        YTAppViewController *appVC = (YTAppViewController *)mainWindow.rootViewController;
        [appVC performSelector:@selector(showPivotBar) withObject:nil afterDelay:1.0];
    }
}
%end

static void downloadImageFromURL(UIResponder *responder, NSURL *URL, BOOL download) {
    NSString *URLString = URL.absoluteString;

    if (ytagBool(@"fixAlbums") && [URLString hasPrefix:@"https://yt3."]) {
        URLString = [URLString stringByReplacingOccurrencesOfString:@"https://yt3." withString:@"https://yt4."];
    }

    NSURL *downloadURL = nil;
    if ([URLString containsString:@"c-fcrop"]) {
        NSRange croppedURL = [URLString rangeOfString:@"c-fcrop"];
        if (croppedURL.location != NSNotFound) {
            NSString *newURL = [URLString stringByReplacingOccurrencesOfString:[URLString substringFromIndex:croppedURL.location] withString:@"nd-v1"];
            downloadURL = [NSURL URLWithString:newURL];
        }
    } else {
        downloadURL = URL;
    }

    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithURL:downloadURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data) {
            if (download) {
                [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                    PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];
                    [request addResourceWithType:PHAssetResourceTypePhoto data:data options:nil];
                } completionHandler:^(BOOL success, NSError *error) {
                    [[%c(YTToastResponderEvent) eventWithMessage:success ? LOC(@"Saved") : [NSString stringWithFormat:LOC(@"%@: %@"), LOC(@"Error"), error.localizedDescription] firstResponder:responder] send];
                }];
            } else {
                [UIPasteboard generalPasteboard].image = [UIImage imageWithData:data];
                [[%c(YTToastResponderEvent) eventWithMessage:LOC(@"Copied") firstResponder:responder] send];
            }
        } else {
            [[%c(YTToastResponderEvent) eventWithMessage:[NSString stringWithFormat:LOC(@"%@: %@"), LOC(@"Error"), error.localizedDescription] firstResponder:responder] send];
        }
    }] resume];
}

static void genImageFromLayer(CALayer *layer, UIColor *backgroundColor, void (^completionHandler)(UIImage *)) {
    UIGraphicsBeginImageContextWithOptions(layer.frame.size, NO, 0.0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(context, backgroundColor.CGColor);
    CGContextFillRect(context, CGRectMake(0, 0, layer.frame.size.width, layer.frame.size.height));
    [layer renderInContext:context];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    if (completionHandler) {
        completionHandler(image);
    }
}

%hook ELMContainerNode
%property (nonatomic, strong) NSString *copiedComment;
%property (nonatomic, strong) NSURL *copiedURL;
%end

%hook ASDisplayNode
- (void)setFrame:(CGRect)frame {
    %orig;

    if (ytagBool(@"commentManager") && [[self valueForKey:@"_accessibilityIdentifier"] isEqualToString:@"id.comment.content.label"]) {
        if ([self isKindOfClass:NSClassFromString(@"ASTextNode")]) {
            ASTextNode *textNode = (ASTextNode *)self;

            NSString *comment;
            if ([textNode respondsToSelector:@selector(attributedText)]) {
                if (textNode.attributedText) comment = textNode.attributedText.string;
            }

            NSMutableArray *allObjects = self.supernodes.allObjects;
            for (ELMContainerNode *containerNode in allObjects) {
                if ([containerNode.description containsString:@"id.ui.comment_cell"] && comment) {
                    containerNode.copiedComment = comment;
                    break;
                }
            }
        }
    }

    if (ytagBool(@"postManager") && [self isKindOfClass:NSClassFromString(@"ELMExpandableTextNode")]) {
        ELMExpandableTextNode *expandableTextNode = (ELMExpandableTextNode *)self;

        if ([expandableTextNode.currentTextNode isKindOfClass:NSClassFromString(@"ASTextNode")]) {
            ASTextNode *textNode = (ASTextNode *)expandableTextNode.currentTextNode;

            NSString *text;
            if ([textNode respondsToSelector:@selector(attributedText)]) {
                if (textNode.attributedText) text = textNode.attributedText.string;
            }

            NSMutableArray *allObjects = self.supernodes.allObjects;
            for (ELMContainerNode *containerNode in allObjects) {
                if ([containerNode.description containsString:@"id.ui.backstage.original_post"] && text) {
                    containerNode.copiedComment = text;
                    break;
                }
            }
        }
    }
}
%end

%hook YTImageZoomNode
- (BOOL)gestureRecognizer:(id)arg1 shouldRecognizeSimultaneouslyWithGestureRecognizer:(id)arg2 {
    BOOL isImageLoaded = [self valueForKey:@"_didLoadImage"];
    if (ytagBool(@"postManager") && isImageLoaded) {
        ASDisplayNode *displayNode = (ASDisplayNode *)self;
        ASNetworkImageNode *imageNode = (ASNetworkImageNode *)self;
        NSURL *URL = imageNode.URL;

        NSMutableArray *allObjects = displayNode.supernodes.allObjects;
        for (ELMContainerNode *containerNode in allObjects) {
            if ([containerNode.description containsString:@"id.ui.backstage.original_post"]) {
                containerNode.copiedURL = URL;
                break;
            }
        }
    }

    return %orig;
}
%end

%hook _ASDisplayView
- (void)setKeepalive_node:(id)arg1 {
    %orig;

    NSArray *gesturesInfo = @[
        @{@"selector": @"postManager:", @"text": @"id.ui.backstage.original_post", @"key": @(ytagBool(@"postManager"))},
        @{@"selector": @"savePFP:", @"text": @"ELMImageNode-View", @"key": @(ytagBool(@"saveProfilePhoto"))},
        @{@"selector": @"commentManager:", @"text": @"id.ui.comment_cell", @"key": @(ytagBool(@"commentManager"))}
    ];

    for (NSDictionary *gestureInfo in gesturesInfo) {
        SEL selector = NSSelectorFromString(gestureInfo[@"selector"]);

        if ([gestureInfo[@"key"] boolValue] && [[self description] containsString:gestureInfo[@"text"]]) {
            UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:selector];
            longPress.minimumPressDuration = 0.3;
            [self addGestureRecognizer:longPress];
            break;
        }
    }
}

%new
- (void)savePFP:(UILongPressGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateBegan) {

        ASNetworkImageNode *imageNode = (ASNetworkImageNode *)self.keepalive_node;
        NSString *URLString = imageNode.URL.absoluteString;
        if (URLString) {
            NSRange sizeRange = [URLString rangeOfString:@"=s"];
            if (sizeRange.location != NSNotFound) {
                NSRange dashRange = [URLString rangeOfString:@"-" options:0 range:NSMakeRange(sizeRange.location, URLString.length - sizeRange.location)];
                if (dashRange.location != NSNotFound) {
                    NSString *newURLString = [URLString stringByReplacingCharactersInRange:NSMakeRange(sizeRange.location + 2, dashRange.location - sizeRange.location - 2) withString:@"1024"];
                    NSURL *PFPURL = [NSURL URLWithString:newURLString];

                    UIImage *image = [UIImage imageWithData:[NSData dataWithContentsOfURL:PFPURL]];
                    if (image) {
                        YTDefaultSheetController *sheetController = [%c(YTDefaultSheetController) sheetControllerWithParentResponder:nil];
    
                        [sheetController addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"SaveProfilePicture") iconImage:YTImageNamed(@"yt_outline_image_24pt") style:0 handler:^ {
                            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil);

                            [[%c(YTToastResponderEvent) eventWithMessage:LOC(@"Saved") firstResponder:self.keepalive_node.closestViewController] send];
                        }]];

                        [sheetController addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"CopyProfilePicture") iconImage:YTImageNamed(@"yt_outline_library_image_24pt") style:0 handler:^ {
                            [UIPasteboard generalPasteboard].image = image;
                            [[%c(YTToastResponderEvent) eventWithMessage:LOC(@"Copied") firstResponder:self.keepalive_node.closestViewController] send];
                        }]];

                        [sheetController presentFromViewController:self.keepalive_node.closestViewController animated:YES completion:nil];
                    }
                }
            }
        }
    }
}

%new
- (void)postManager:(UILongPressGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateBegan) {
        ELMContainerNode *nodeForLayer = (ELMContainerNode *)self.keepalive_node.yogaChildren[0];
        ELMContainerNode *containerNode = (ELMContainerNode *)self.keepalive_node;
        NSString *text = containerNode.copiedComment;
        NSURL *URL = containerNode.copiedURL;
        CALayer *layer = nodeForLayer.layer;
        UIColor *backgroundColor = containerNode.closestViewController.view.backgroundColor;

        YTDefaultSheetController *sheetController = [%c(YTDefaultSheetController) sheetControllerWithParentResponder:nil];
        
        [sheetController addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"CopyPostText") iconImage:YTImageNamed(@"yt_outline_message_bubble_right_24pt") style:0 handler:^ {
            if (text) {
                [UIPasteboard generalPasteboard].string = text;
                [[%c(YTToastResponderEvent) eventWithMessage:LOC(@"Copied") firstResponder:containerNode.closestViewController] send];
            }
        }]];

        if (URL) {
            [sheetController addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"SaveCurrentImage") iconImage:YTImageNamed(@"yt_outline_image_24pt") style:0 handler:^ {
                downloadImageFromURL(containerNode.closestViewController, URL, YES);
            }]];

            [sheetController addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"CopyCurrentImage") iconImage:YTImageNamed(@"yt_outline_library_image_24pt") style:0 handler:^ {
                downloadImageFromURL(containerNode.closestViewController, URL, NO);
            }]];
        }

        [sheetController addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"SavePostAsImage") titleColor:[UIColor colorWithRed:0.75 green:0.50 blue:0.90 alpha:1.0] iconImage:YTImageNamed(@"yt_outline_image_24pt") iconColor:[UIColor colorWithRed:0.75 green:0.50 blue:0.90 alpha:1.0] disableAutomaticButtonColor:YES accessibilityIdentifier:nil handler:^ {
            genImageFromLayer(layer, backgroundColor, ^(UIImage *image) {
                [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                    PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAssetFromImage:image];
                    request.creationDate = [NSDate date];
                } completionHandler:^(BOOL success, NSError *error) {
                    NSString *message = success ? LOC(@"Saved") : [NSString stringWithFormat:LOC(@"%@: %@"), LOC(@"Error"), error.localizedDescription];
                    [[%c(YTToastResponderEvent) eventWithMessage:message firstResponder:containerNode.closestViewController] send];
                }];
            });
        }]];

        [sheetController addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"CopyPostAsImage") titleColor:[UIColor colorWithRed:0.75 green:0.50 blue:0.90 alpha:1.0] iconImage:YTImageNamed(@"yt_outline_library_image_24pt") iconColor:[UIColor colorWithRed:0.75 green:0.50 blue:0.90 alpha:1.0] disableAutomaticButtonColor:YES accessibilityIdentifier:nil handler:^ {
            genImageFromLayer(layer, backgroundColor, ^(UIImage *image) {
                [UIPasteboard generalPasteboard].image = image;
                [[%c(YTToastResponderEvent) eventWithMessage:LOC(@"Copied") firstResponder:containerNode.closestViewController] send];
            });
        }]];

        [sheetController presentFromViewController:containerNode.closestViewController animated:YES completion:nil];
    }
}

%new
- (void)commentManager:(UILongPressGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateBegan) {
        ELMContainerNode *containerNode = (ELMContainerNode *)self.keepalive_node;
        NSString *comment = containerNode.copiedComment;

        CALayer *layer = self.layer;
        UIColor *backgroundColor = containerNode.closestViewController.view.backgroundColor;

        YTDefaultSheetController *sheetController = [%c(YTDefaultSheetController) sheetControllerWithParentResponder:nil];

        [sheetController addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"CopyCommentText") iconImage:YTImageNamed(@"yt_outline_message_bubble_right_24pt") style:0 handler:^ {
            if (comment) {
                [UIPasteboard generalPasteboard].string = comment;
                [[%c(YTToastResponderEvent) eventWithMessage:LOC(@"Copied") firstResponder:containerNode.closestViewController] send];
            }
        }]];

        [sheetController addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"SaveCommentAsImage") iconImage:YTImageNamed(@"yt_outline_image_24pt") style:0 handler:^ {
            genImageFromLayer(layer, backgroundColor, ^(UIImage *image) {
                [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                    PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAssetFromImage:image];
                    request.creationDate = [NSDate date];
                } completionHandler:^(BOOL success, NSError *error) {
                    NSString *message = success ? LOC(@"Saved") : [NSString stringWithFormat:LOC(@"%@: %@"), LOC(@"Error"), error.localizedDescription];
                    [[%c(YTToastResponderEvent) eventWithMessage:message firstResponder:containerNode.closestViewController] send];
                }];
            });
        }]];

        [sheetController addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"CopyCommentAsImage") iconImage:YTImageNamed(@"yt_outline_library_image_24pt") style:0 handler:^ {
            genImageFromLayer(layer, backgroundColor, ^(UIImage *image) {
                [UIPasteboard generalPasteboard].image = image;
                [[%c(YTToastResponderEvent) eventWithMessage:LOC(@"Copied") firstResponder:containerNode.closestViewController] send];
            });
        }]];

        [sheetController presentFromViewController:containerNode.closestViewController animated:YES completion:nil];
    }
}
%end

// Tab Management - Helper to get pivot identifier from a renderer
static NSString *ytagPivotId(YTIPivotBarSupportedRenderers *r) {
    NSString *pid = [[r pivotBarItemRenderer] pivotIdentifier];
    if (!pid) pid = [[r pivotBarIconOnlyItemRenderer] pivotIdentifier];
    return pid;
}

static NSString *ytagBrowseIdForTabId(NSString *tabId) {
    if ([tabId isEqualToString:@"FEtrending"] || [tabId isEqualToString:@"FEexplore"]) {
        return @"FEhype_leaderboard";
    }
    return tabId;
}

static NSString *ytagCanonicalPivotId(NSString *pivotId) {
    if (![pivotId isKindOfClass:[NSString class]] || pivotId.length == 0) return nil;

    NSString *trendingBrowseId = [%c(YTIBrowseRequest) browseIDForTrendingTab];
    if (trendingBrowseId.length > 0 && [pivotId isEqualToString:trendingBrowseId]) {
        return @"FEtrending";
    }

    NSString *exploreBrowseId = [%c(YTIBrowseRequest) browseIDForExploreTab];
    if (exploreBrowseId.length > 0 && [pivotId isEqualToString:exploreBrowseId]) {
        return @"FEexplore";
    }

    if ([pivotId isEqualToString:@"FEexplore"]) {
        return @"FEexplore";
    }

    return pivotId;
}

static int ytagIconTypeForTabId(NSString *tabId) {
    if ([tabId isEqualToString:@"FEhype_leaderboard"]) return 67;
    if ([tabId isEqualToString:@"FEhistory"]) return 876;
    if ([tabId isEqualToString:@"VLWL"]) return 877;
    if ([tabId isEqualToString:@"FEpost_home"]) return 878;
    if ([tabId isEqualToString:@"FEuploads"]) return 80;
    return 65;
}

static void ytagConfigurePivotTab(YTIPivotBarSupportedRenderers *tab, NSString *tabId) {
    YTIPivotBarItemRenderer *item = [tab pivotBarItemRenderer];
    if (!item) return;

    NSString *browseId = ytagBrowseIdForTabId(tabId);
    item.pivotIdentifier = tabId;
    item.targetId = browseId;

    @try {
        YTICommand *endpoint = [%c(YTICommand) browseNavigationEndpointWithBrowseID:browseId];
        if (endpoint) item.navigationEndpoint = endpoint;
        item.navigationEndpoint.browseEndpoint.browseId = browseId;
        if ([tabId isEqualToString:@"VLWL"]) {
            item.navigationEndpoint.browseEndpoint.canonicalBaseURL = @"/playlist?list=WL";
        } else if ([tabId isEqualToString:@"FEhistory"]) {
            item.navigationEndpoint.browseEndpoint.canonicalBaseURL = @"/feed/history";
        } else if ([tabId isEqualToString:@"FEpost_home"]) {
            item.navigationEndpoint.browseEndpoint.canonicalBaseURL = @"/posts";
        }
    } @catch (__unused id exception) {
    }
}

static YTIPivotBarSupportedRenderers *ytagCreatePivotTab(NSString *tabId) {
    YTIPivotBarSupportedRenderers *tab = [%c(YTIPivotBarRenderer) pivotSupportedRenderersWithBrowseId:ytagBrowseIdForTabId(tabId) title:LOC(tabId) iconType:ytagIconTypeForTabId(tabId)];
    ytagConfigurePivotTab(tab, tabId);
    return tab;
}

static BOOL ytagItemsContainTab(NSArray<YTIPivotBarSupportedRenderers *> *items, NSString *tabId) {
    for (YTIPivotBarSupportedRenderers *item in items) {
        NSString *pid = ytagCanonicalPivotId(ytagPivotId(item));
        if ([pid isEqualToString:tabId]) return YES;
    }
    return NO;
}

// Tab Management - Get default active tabs
static NSArray *ytagDefaultTabs() {
    return [YTAGUserDefaults defaultActiveTabs];
}

// Tab Management - Filter and reorder pivot bar items based on activeTabs
%hook YTPivotBarView
- (void)setRenderer:(YTIPivotBarRenderer *)renderer {
    NSMutableArray <YTIPivotBarSupportedRenderers *> *items = [renderer itemsArray];
    NSArray *activeTabs = YTAGLiteModeEnabled() ? YTAGLiteModeActiveTabs() : [[YTAGUserDefaults standardUserDefaults] currentActiveTabs];
    if (!activeTabs) activeTabs = ytagDefaultTabs();

    // Remove tabs not in activeTabs
    NSMutableArray *toRemove = [NSMutableArray array];
    for (YTIPivotBarSupportedRenderers *item in items) {
        NSString *pid = ytagCanonicalPivotId(ytagPivotId(item));
        if (pid && ![activeTabs containsObject:pid]) {
            [toRemove addObject:item];
        }
    }
    [items removeObjectsInArray:toRemove];

    // Add optional tabs only when YouTube did not supply them natively.
    for (NSString *tabId in @[@"FEhype_leaderboard", @"FEhistory", @"VLWL", @"FEpost_home", @"FEuploads"]) {
        if ([activeTabs containsObject:tabId] && !ytagItemsContainTab(items, tabId)) {
            YTIPivotBarSupportedRenderers *tab = ytagCreatePivotTab(tabId);
            if (tab) [items addObject:tab];
        }
    }

    // Reorder items to match activeTabs order
    NSMutableArray *ordered = [NSMutableArray array];
    for (NSString *tabId in activeTabs) {
        for (YTIPivotBarSupportedRenderers *item in items) {
            NSString *pid = ytagCanonicalPivotId(ytagPivotId(item));
            if ([pid isEqualToString:tabId]) {
                [ordered addObject:item];
                break;
            }
        }
    }

    if (ordered.count == 0 && items.count > 0) {
        %orig;
        return;
    }

    [items removeAllObjects];
    [items addObjectsFromArray:ordered];

    %orig;
}
%end

// Hide Tab Bar Indicators
%hook YTPivotBarIndicatorView
- (void)setFillColor:(id)arg1 { %orig(ytagBool(@"removeIndicators") ? [UIColor clearColor] : arg1); }
- (void)setBorderColor:(id)arg1 { %orig(ytagBool(@"removeIndicators") ? [UIColor clearColor] : arg1); }
%end

// Hide Tab Labels + Custom Tab Icons
%hook YTPivotBarItemView
- (void)setRenderer:(YTIPivotBarRenderer *)renderer {
    %orig;

    if (ytagBool(@"removeLabels")) {
        [self.navigationButton setTitle:@"" forState:UIControlStateNormal];
        [self.navigationButton setSizeWithPaddingAndInsets:NO];
    }

    // Load custom tab icons from bundle
    NSInteger iconType = self.renderer.icon.iconType;
    NSString *normalName = nil;
    NSString *selectedName = nil;

    if (iconType == 876) { normalName = @"FEhistory"; selectedName = @"FEhistory_selected"; }
    else if (iconType == 877) { normalName = @"VLWL"; selectedName = @"VLWL_selected"; }
    else if (iconType == 878) { normalName = @"FEpost_home"; selectedName = @"FEpost_home_selected"; }

    if (normalName) {
        NSBundle *bundle = [NSBundle ytag_defaultBundle];
        NSString *normalPath = [bundle pathForResource:[normalName stringByAppendingString:@"@3x"] ofType:@"png"]
                            ?: [bundle pathForResource:[normalName stringByAppendingString:@"@2x"] ofType:@"png"];
        NSString *selectedPath = [bundle pathForResource:[selectedName stringByAppendingString:@"@3x"] ofType:@"png"]
                              ?: [bundle pathForResource:[selectedName stringByAppendingString:@"@2x"] ofType:@"png"];

        UIImage *normal = normalPath ? [[UIImage imageWithContentsOfFile:normalPath] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] : nil;
        UIImage *selected = selectedPath ? [[UIImage imageWithContentsOfFile:selectedPath] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] : nil;

        YTQTMButton *button = self.navigationButton;
        if (normal) [button setImage:normal forState:UIControlStateNormal];
        if (selected) [button setImage:selected forState:UIControlStateSelected];
    }
}
%end

// Startup Tab
BOOL isTabSelected = NO;
%hook YTPivotBarViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;

    if (!isTabSelected && !ytagBool(@"shortsOnlyMode")) {
        NSString *startupTab = YTAGLiteModeEnabled() ? YTAGLiteModeStartupTab() : [[YTAGUserDefaults standardUserDefaults] currentStartupTab];
        [self selectItemWithPivotIdentifier:startupTab];
        isTabSelected = YES;
    }

    if (ytagBool(@"shortsOnlyMode")) {
        [self selectItemWithPivotIdentifier:@"FEshorts"];
        [self.parentViewController hidePivotBar];
    }
}
%end

%hook YTAppViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    ytagPresentAdvancedModeReminderIfNeeded();
}

- (void)showPivotBar {
    if (!ytagBool(@"shortsOnlyMode")) {
        %orig;

        isOverlayShown = YES;
    }
}
%end

%hook YTReelWatchRootViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;

    if (ytagBool(@"shortsOnlyMode")) {
        [self.navigationController.parentViewController hidePivotBar];
    }
}
%end

%hook YTEngagementPanelView
- (void)layoutSubviews {
    %orig;

    if (ytagBool(@"copyVideoInfo") && [self.panelIdentifier.identifierString isEqualToString:@"video-description-ep-identifier"]) {
        YTQTMButton *copyInfoButton = [%c(YTQTMButton) iconButton];
        copyInfoButton.accessibilityLabel = LOC(@"CopyVideoInfo");
        [copyInfoButton setTag:999];
        [copyInfoButton enableNewTouchFeedback];
        [copyInfoButton setImage:YTImageNamed(@"yt_outline_copy_24pt") forState:UIControlStateNormal];
        [copyInfoButton setTintColor:[UIColor labelColor]];
        [copyInfoButton setTranslatesAutoresizingMaskIntoConstraints:false];
        [copyInfoButton addTarget:self action:@selector(didTapCopyInfoButton:) forControlEvents:UIControlEventTouchUpInside];

        if (self.headerView && ![self.headerView viewWithTag:999]) {
            [self.headerView addSubview:copyInfoButton];

            [NSLayoutConstraint activateConstraints:@[
                [copyInfoButton.trailingAnchor constraintEqualToAnchor:self.headerView.trailingAnchor constant:-48],
                [copyInfoButton.centerYAnchor constraintEqualToAnchor:self.headerView.centerYAnchor],
                [copyInfoButton.widthAnchor constraintEqualToConstant:40.0],
                [copyInfoButton.heightAnchor constraintEqualToConstant:40.0],
            ]];
        }
    }
}

%new
- (void)didTapCopyInfoButton:(UIButton *)sender {
    YTPlayerViewController *playerVC = self.resizeDelegate.parentViewController.parentViewController.parentViewController.playerViewController;
    NSString *title = playerVC.playerResponse.playerData.videoDetails.title;
    NSString *shortDescription = playerVC.playerResponse.playerData.videoDetails.shortDescription;

    YTDefaultSheetController *sheetController = [%c(YTDefaultSheetController) sheetControllerWithParentResponder:nil];

    [sheetController addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"CopyTitle") iconImage:YTImageNamed(@"yt_outline_text_box_24pt") style:0 handler:^ {
        [UIPasteboard generalPasteboard].string = title;
        [[%c(YTToastResponderEvent) eventWithMessage:LOC(@"Copied") firstResponder:self.resizeDelegate] send];
    }]];

    [sheetController addAction:[%c(YTActionSheetAction) actionWithTitle:LOC(@"CopyDescription") iconImage:YTImageNamed(@"yt_outline_message_bubble_right_24pt") style:0 handler:^ {
        [UIPasteboard generalPasteboard].string = shortDescription;
        [[%c(YTToastResponderEvent) eventWithMessage:LOC(@"Copied") firstResponder:self.resizeDelegate] send];
    }]];

    [sheetController presentFromViewController:self.resizeDelegate animated:YES completion:nil];
}
%end

// Disable Right-To-Left Formatting
%hook NSParagraphStyle
+ (NSWritingDirection)defaultWritingDirectionForLanguage:(id)lang { return ytagBool(@"disableRTL") ? NSWritingDirectionLeftToRight : %orig; }
+ (NSWritingDirection)_defaultWritingDirection { return ytagBool(@"disableRTL") ? NSWritingDirectionLeftToRight : %orig; }
%end

// Fix Albums For Russian Users
static NSURL *newCoverURL(NSURL *originalURL) {
    NSDictionary <NSString *, NSString *> *hostsToReplace = @{
        @"yt3.ggpht.com": @"yt4.ggpht.com",
        @"yt3.googleusercontent.com": @"yt4.googleusercontent.com",
    };

    NSString *const replacement = hostsToReplace[originalURL.host];
    if (ytagBool(@"fixAlbums") && replacement) {
        NSURLComponents *components = [NSURLComponents componentsWithURL:originalURL resolvingAgainstBaseURL:NO];
        components.host = replacement;
        return components.URL;
    }
    return originalURL;
}

%hook YTImageSelectionStrategyImageURLs
- (id)initWithSelectedImageURL:(NSURL *)selectedImageURL updatedImageURL:(NSURL *)updatedImageURL {
    return %orig(newCoverURL(selectedImageURL), newCoverURL(updatedImageURL));
}
%end

%ctor {
    [YTAGDebugHUD applyPreferenceOnLaunch];
    YTAGLog(@"ctor", @"YTAfterglow main dylib loaded");
    YTAGLog(@"ctor", @"YTFullscreenActionsView class exists: %@", NSClassFromString(@"YTFullscreenActionsView") ? @"YES" : @"NO");

    // Ensure Shorts tab is active if shortsOnlyMode is enabled
    if (ytagBool(@"shortsOnlyMode")) {
        NSMutableArray *tabs = [[[YTAGUserDefaults standardUserDefaults] currentActiveTabs] mutableCopy];
        if (![tabs containsObject:@"FEshorts"]) {
            if (tabs.count >= 6) [tabs removeLastObject];
            [tabs addObject:@"FEshorts"];
            [[YTAGUserDefaults standardUserDefaults] setActiveTabs:tabs];
        }
    }

    ytagAdvancedModePromptObserver = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                                                       object:nil
                                                                                        queue:[NSOperationQueue mainQueue]
                                                                                   usingBlock:^(__unused NSNotification *note) {
        ytagPresentAdvancedModeReminderIfNeeded();
    }];
}
