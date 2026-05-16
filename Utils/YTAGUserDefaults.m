#import "YTAGUserDefaults.h"
#import "YTAGLiteMode.h"
#import <UIKit/UIKit.h>

@implementation YTAGUserDefaults

static NSString *const kDefaultsSuiteName = @"afterglow.vault";
static NSString *const kActiveTabsKey = @"activeTabs";
static NSString *const kStartupTabKey = @"startupTab";
static NSString *const kThemeMigrationVersionKey = @"themePresetMigrationVersion";
static NSString *const kSettingsMigrationVersionKey = @"settingsMigrationVersion";
static NSString *const kPreferencesExportFormat = @"YTAfterglowPreferences";
static NSString *const kPreferencesExportErrorDomain = @"YTAfterglowPreferencesError";
static const NSUInteger kMinimumActiveTabsCount = 2;
static const NSUInteger kSingleRowMaximumActiveTabsCount = 6;
static const NSInteger kCurrentThemeMigrationVersion = 2;
static const NSInteger kCurrentSettingsMigrationVersion = 6;
static const NSInteger kPreferencesExportVersion = 1;

static NSData *YTAGArchiveColor(UIColor *color) {
    return [NSKeyedArchiver archivedDataWithRootObject:color requiringSecureCoding:NO error:nil];
}

static BOOL YTAGThemeKeyMatchesColor(NSUserDefaults *defaults, NSString *key, UIColor *expectedColor) {
    NSData *stored = [defaults objectForKey:key];
    NSData *expected = YTAGArchiveColor(expectedColor);
    return (stored && expected && [stored isEqualToData:expected]);
}

static BOOL YTAGThemeMatchesLegacyAfterglowPreset(NSUserDefaults *defaults) {
    return
        YTAGThemeKeyMatchesColor(defaults, @"theme_overlayButtons", [UIColor colorWithRed:0.99 green:0.86 blue:0.78 alpha:1.0]) &&
        YTAGThemeKeyMatchesColor(defaults, @"theme_tabBarIcons", [UIColor colorWithRed:0.99 green:0.57 blue:0.39 alpha:1.0]) &&
        YTAGThemeKeyMatchesColor(defaults, @"theme_seekBar", [UIColor colorWithRed:0.96 green:0.42 blue:0.28 alpha:1.0]) &&
        YTAGThemeKeyMatchesColor(defaults, @"theme_background", [UIColor colorWithRed:0.11 green:0.06 blue:0.10 alpha:1.0]) &&
        YTAGThemeKeyMatchesColor(defaults, @"theme_textPrimary", [UIColor colorWithRed:0.99 green:0.94 blue:0.90 alpha:1.0]) &&
        YTAGThemeKeyMatchesColor(defaults, @"theme_textSecondary", [UIColor colorWithRed:0.72 green:0.61 blue:0.65 alpha:1.0]) &&
        YTAGThemeKeyMatchesColor(defaults, @"theme_navBar", [UIColor colorWithRed:0.17 green:0.08 blue:0.12 alpha:1.0]) &&
        YTAGThemeKeyMatchesColor(defaults, @"theme_accent", [UIColor colorWithRed:0.93 green:0.36 blue:0.26 alpha:1.0]) &&
        YTAGThemeKeyMatchesColor(defaults, @"theme_gradientStart", [UIColor colorWithRed:0.18 green:0.07 blue:0.12 alpha:1.0]) &&
        YTAGThemeKeyMatchesColor(defaults, @"theme_gradientEnd", [UIColor colorWithRed:0.39 green:0.12 blue:0.15 alpha:1.0]) &&
        [defaults boolForKey:@"theme_glowEnabled"];
}

static void YTAGApplyUpdatedAfterglowPreset(NSUserDefaults *defaults) {
    [defaults setObject:YTAGArchiveColor([UIColor colorWithRed:1.00 green:0.90 blue:0.78 alpha:1.0]) forKey:@"theme_overlayButtons"];
    [defaults setObject:YTAGArchiveColor([UIColor colorWithRed:0.99 green:0.63 blue:0.32 alpha:1.0]) forKey:@"theme_tabBarIcons"];
    [defaults setObject:YTAGArchiveColor([UIColor colorWithRed:0.97 green:0.49 blue:0.21 alpha:1.0]) forKey:@"theme_seekBar"];
    [defaults setObject:YTAGArchiveColor([UIColor colorWithRed:0.07 green:0.07 blue:0.09 alpha:1.0]) forKey:@"theme_background"];
    [defaults setObject:YTAGArchiveColor([UIColor colorWithRed:0.98 green:0.95 blue:0.90 alpha:1.0]) forKey:@"theme_textPrimary"];
    [defaults setObject:YTAGArchiveColor([UIColor colorWithRed:0.70 green:0.62 blue:0.54 alpha:1.0]) forKey:@"theme_textSecondary"];
    [defaults setObject:YTAGArchiveColor([UIColor colorWithRed:0.12 green:0.11 blue:0.12 alpha:1.0]) forKey:@"theme_navBar"];
    [defaults setObject:YTAGArchiveColor([UIColor colorWithRed:0.94 green:0.44 blue:0.18 alpha:1.0]) forKey:@"theme_accent"];
    [defaults setObject:YTAGArchiveColor([UIColor colorWithRed:0.16 green:0.15 blue:0.17 alpha:1.0]) forKey:@"theme_gradientStart"];
    [defaults setObject:YTAGArchiveColor([UIColor colorWithRed:0.34 green:0.19 blue:0.11 alpha:1.0]) forKey:@"theme_gradientEnd"];
    [defaults setBool:YES forKey:@"theme_glowEnabled"];
}

static NSArray<NSString *> *YTAGThemePresetKeys(void) {
    return @[
        @"theme_overlayButtons", @"theme_tabBarIcons", @"theme_seekBar",
        @"theme_seekBarLive", @"theme_seekBarScrubber", @"theme_seekBarScrubberLive",
        @"theme_background", @"theme_textPrimary", @"theme_textSecondary",
        @"theme_navBar", @"theme_accent",
        @"theme_gradientStart", @"theme_gradientEnd", @"theme_glowEnabled"
    ];
}

static BOOL YTAGHasStoredThemePreset(NSUserDefaults *defaults) {
    for (NSString *key in YTAGThemePresetKeys()) {
        if ([defaults objectForKey:key] != nil) return YES;
    }
    return NO;
}

static NSError *YTAGPreferencesError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:kPreferencesExportErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Preference import/export failed."}];
}

static BOOL YTAGValueIsPropertyListSafe(id value) {
    if (!value) return NO;
    if ([value isKindOfClass:[NSString class]] ||
        [value isKindOfClass:[NSNumber class]] ||
        [value isKindOfClass:[NSData class]] ||
        [value isKindOfClass:[NSDate class]]) {
        return YES;
    }

    if ([value isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)value) {
            if (!YTAGValueIsPropertyListSafe(item)) return NO;
        }
        return YES;
    }

    if ([value isKindOfClass:[NSDictionary class]]) {
        for (id key in (NSDictionary *)value) {
            if (![key isKindOfClass:[NSString class]]) return NO;
            if (!YTAGValueIsPropertyListSafe([(NSDictionary *)value objectForKey:key])) return NO;
        }
        return YES;
    }

    return NO;
}

static NSDictionary *YTAGSanitizedPreferencesDictionary(NSDictionary *preferences) {
    NSMutableDictionary *sanitized = [NSMutableDictionary dictionary];
    for (id key in preferences) {
        id value = preferences[key];
        if (![key isKindOfClass:[NSString class]] || !YTAGValueIsPropertyListSafe(value)) continue;
        sanitized[key] = value;
    }
    return [sanitized copy];
}

static void YTAGApplyAfterglow2ThemePreset(NSUserDefaults *defaults) {
    NSData *seekBar = YTAGArchiveColor([UIColor colorWithRed:1.00 green:0.48 blue:0.66 alpha:1.0]);
    [defaults setObject:YTAGArchiveColor([UIColor colorWithRed:1.00 green:0.82 blue:0.71 alpha:1.0]) forKey:@"theme_overlayButtons"];
    [defaults setObject:YTAGArchiveColor([UIColor colorWithRed:1.00 green:0.55 blue:0.42 alpha:1.0]) forKey:@"theme_tabBarIcons"];
    [defaults setObject:seekBar forKey:@"theme_seekBar"];
    [defaults setObject:seekBar forKey:@"theme_seekBarLive"];
    [defaults setObject:seekBar forKey:@"theme_seekBarScrubber"];
    [defaults setObject:seekBar forKey:@"theme_seekBarScrubberLive"];
    [defaults setObject:YTAGArchiveColor([UIColor colorWithRed:0.11 green:0.05 blue:0.13 alpha:1.0]) forKey:@"theme_background"];
    [defaults setObject:YTAGArchiveColor([UIColor colorWithRed:1.00 green:0.94 blue:0.90 alpha:1.0]) forKey:@"theme_textPrimary"];
    [defaults setObject:YTAGArchiveColor([UIColor colorWithRed:0.79 green:0.67 blue:0.72 alpha:1.0]) forKey:@"theme_textSecondary"];
    [defaults setObject:YTAGArchiveColor([UIColor colorWithRed:0.17 green:0.08 blue:0.19 alpha:1.0]) forKey:@"theme_navBar"];
    [defaults setObject:YTAGArchiveColor([UIColor colorWithRed:0.41 green:0.89 blue:1.00 alpha:1.0]) forKey:@"theme_accent"];
    [defaults setObject:YTAGArchiveColor([UIColor colorWithRed:0.24 green:0.06 blue:0.24 alpha:1.0]) forKey:@"theme_gradientStart"];
    [defaults setObject:YTAGArchiveColor([UIColor colorWithRed:1.00 green:0.46 blue:0.28 alpha:1.0]) forKey:@"theme_gradientEnd"];
    [defaults setBool:YES forKey:@"theme_glowEnabled"];
}

static NSString *YTAGCanonicalTabId(NSString *tabId) {
    if ([tabId isEqualToString:@"FEexplore"] || [tabId isEqualToString:@"FEtrending"]) return @"FEhype_leaderboard";
    return tabId;
}

static NSArray<NSString *> *YTAGAllowedTabs(void) {
    return @[@"FEwhat_to_watch", @"FEshorts", @"FEsubscriptions", @"FElibrary", @"FEhype_leaderboard", @"FEhistory", @"VLWL", @"FEpost_home", @"FEuploads"];
}

static NSUInteger YTAGMaximumActiveTabsCount(NSUserDefaults *defaults) {
    return [defaults boolForKey:@"twoRowTabBar"] ? YTAGAllowedTabs().count : kSingleRowMaximumActiveTabsCount;
}

static void YTAGResetBundledStandardUserDefaults(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray<NSString *> *explicitKeys = @[
        @"YouPiPEnabled",
        @"CompatibilityModeKey",
        @"PiPActivationMethodKey",
        @"PiPActivationMethod2Key",
        @"PiPAllActivationMethodKey",
        @"NoMiniPlayerPiPKey",
        @"NonBackgroundableKey",
        @"YouMuteKeepMuted",
        @"offlineProbeDump"
    ];

    for (NSString *key in explicitKeys) {
        [defaults removeObjectForKey:key];
    }

    NSString *appDomain = [NSBundle mainBundle].bundleIdentifier;
    NSDictionary *domain = appDomain.length > 0 ? [defaults persistentDomainForName:appDomain] : nil;
    for (NSString *key in domain) {
        if ([key hasPrefix:@"YTVideoOverlay-"]) {
            [defaults removeObjectForKey:key];
        }
    }

    [defaults synchronize];
}

+ (YTAGUserDefaults *)standardUserDefaults {
    static dispatch_once_t onceToken;
    static YTAGUserDefaults *defaults = nil;

    dispatch_once(&onceToken, ^{
        defaults = [[self alloc] initWithSuiteName:kDefaultsSuiteName];
        [defaults registerDefaults];
        [defaults migrateThemePresetsIfNeeded];
        [defaults migrateSettingsIfNeeded];
    });

    return defaults;
}

- (NSArray<NSString *> *)sanitizedActiveTabsFromValue:(id)value {
    if (![value isKindOfClass:[NSArray class]]) {
        return [YTAGUserDefaults defaultActiveTabs];
    }

    NSMutableArray<NSString *> *sanitizedTabs = [NSMutableArray array];
    NSArray<NSString *> *allowedTabs = YTAGAllowedTabs();

    for (id item in (NSArray *)value) {
        if (![item isKindOfClass:[NSString class]]) continue;

        NSString *tabId = YTAGCanonicalTabId((NSString *)item);
        if (![allowedTabs containsObject:tabId] || [sanitizedTabs containsObject:tabId]) continue;

        [sanitizedTabs addObject:tabId];
        if (sanitizedTabs.count >= YTAGMaximumActiveTabsCount(self)) break;
    }

    if (sanitizedTabs.count < kMinimumActiveTabsCount) {
        return [YTAGUserDefaults defaultActiveTabs];
    }

    return [sanitizedTabs copy];
}

- (NSArray<NSString *> *)currentActiveTabs {
    id storedTabs = [self objectForKey:kActiveTabsKey];
    NSArray<NSString *> *sanitizedTabs = [self sanitizedActiveTabsFromValue:storedTabs];

    if (![storedTabs isKindOfClass:[NSArray class]] || ![(NSArray *)storedTabs isEqualToArray:sanitizedTabs]) {
        [super setObject:sanitizedTabs forKey:kActiveTabsKey];
    }

    return sanitizedTabs;
}

- (void)setActiveTabs:(NSArray<NSString *> *)tabs {
    NSArray<NSString *> *sanitizedTabs = [self sanitizedActiveTabsFromValue:tabs];
    [super setObject:sanitizedTabs forKey:kActiveTabsKey];

    NSString *startupTab = [self objectForKey:kStartupTabKey];
    if (![startupTab isKindOfClass:[NSString class]] || ![sanitizedTabs containsObject:startupTab]) {
        [super setObject:sanitizedTabs.firstObject forKey:kStartupTabKey];
    }
}

- (NSString *)currentStartupTab {
    NSArray<NSString *> *activeTabs = [self currentActiveTabs];
    NSString *startupTab = [self objectForKey:kStartupTabKey];

    if (![startupTab isKindOfClass:[NSString class]] || ![activeTabs containsObject:startupTab]) {
        startupTab = activeTabs.firstObject ?: [YTAGUserDefaults defaultActiveTabs].firstObject;
        [super setObject:startupTab forKey:kStartupTabKey];
    }

    return startupTab;
}

- (void)reset {
    [self removePersistentDomainForName:kDefaultsSuiteName];
    [self registerDefaults];
    [self synchronize];
    YTAGResetBundledStandardUserDefaults();
}

- (NSData *)exportPreferencesDataWithError:(NSError **)error {
    NSDictionary *domain = [self persistentDomainForName:kDefaultsSuiteName] ?: @{};
    NSDictionary *payload = @{
        @"format": kPreferencesExportFormat,
        @"version": @(kPreferencesExportVersion),
        @"exportedAt": @([[NSDate date] timeIntervalSince1970]),
        @"preferences": YTAGSanitizedPreferencesDictionary(domain)
    };

    return [NSPropertyListSerialization dataWithPropertyList:payload
                                                      format:NSPropertyListXMLFormat_v1_0
                                                     options:0
                                                       error:error];
}

- (BOOL)importPreferencesData:(NSData *)data error:(NSError **)error {
    if (data.length == 0) {
        if (error) *error = YTAGPreferencesError(1, @"The selected preferences file is empty.");
        return NO;
    }

    NSPropertyListFormat format = NSPropertyListXMLFormat_v1_0;
    id plist = [NSPropertyListSerialization propertyListWithData:data
                                                         options:NSPropertyListImmutable
                                                          format:&format
                                                           error:error];
    if (![plist isKindOfClass:[NSDictionary class]]) {
        if (error && !*error) *error = YTAGPreferencesError(2, @"The selected file is not a preferences plist.");
        return NO;
    }

    NSDictionary *root = (NSDictionary *)plist;
    id preferences = root[@"preferences"];
    if (!preferences && root[@"format"] == nil) preferences = root;

    if (![preferences isKindOfClass:[NSDictionary class]]) {
        if (error) *error = YTAGPreferencesError(3, @"The selected file does not contain YTAfterglow preferences.");
        return NO;
    }

    NSDictionary *sanitized = YTAGSanitizedPreferencesDictionary((NSDictionary *)preferences);
    [self removePersistentDomainForName:kDefaultsSuiteName];
    [self setPersistentDomain:sanitized forName:kDefaultsSuiteName];
    [self registerDefaults];
    [self migrateThemePresetsIfNeeded];
    [self migrateSettingsIfNeeded];
    [self synchronize];
    return YES;
}

- (void)registerDefaults {
    [self registerDefaults:@{
        @"noAds": @YES,
        @"backgroundPlayback": @YES,
        @"speedIndex": @1,
        @"autoSpeedIndex": @3,
        @"wiFiQualityIndex": @0,
        @"cellQualityIndex": @0,
        kActiveTabsKey: [YTAGUserDefaults defaultActiveTabs],
        kStartupTabKey: @"FEwhat_to_watch",
        @"frostedPivot": @YES,
        @"twoRowTabBar": @YES,
        @"theme_glowPivot": @YES,
        @"theme_glowOverlay": @YES,
        @"theme_glowScrubber": @YES,
        @"theme_glowSeekBar": @NO,
        @"theme_glowStrength": @1,
        @"theme_glowStrengthMode": @1,
        @"theme_glowStrengthCustom": @50,
        @"theme_glowOpacity": @100,
        @"theme_glowRadius": @50,
        @"theme_glowLayers": @1,
        YTAGThemeFontModeKey: @0,
        @"autoplayMode": @0,
        @"noPlayerShareButton": @NO,
        @"noPlayerSaveButton": @NO,
        YTAGLiteModeEnabledKey: @NO,
        YTAGLiteModeDefaultThemeAppliedKey: @NO,
        YTAGLiteModeDefaultThemeVersionKey: @0,
        @"commentsHeaderMode": @0,
        @"muteButton": @YES,
        @"lockButton": @YES,
        @"downloadButton": @YES,
        @"overlayDeclutterButton": @YES,
        @"downloadPostActionMode": @1,
        @"downloadAudioTrackMode": @1,
        @"downloadAudioQualityMode": @0,
        @"downloadPreferStableAudio": @YES,
        @"downloadRefreshMetadata": @YES,
        @"downloadIncludeAutoCaptions": @YES,
        @"downloadOfferTranslatedCaptions": @YES,
        @"downloadPickerFontScaleMode": @0,
        @"downloadPickerFontFaceMode": @1,
        @"controlsSheetButton": @YES,
        @"debugLogEnabled": @NO,
        @"debugLogFirehose": @NO,
        @"debugLogDownloads": @YES,
        @"debugLogPlayerUI": @YES,
        @"debugLogPremiumControls": @YES,
        @"debugLogPiP": @NO,
        @"debugLogProbes": @NO,
        @"debugHUDEnabled": @NO
    }];
}

- (void)migrateThemePresetsIfNeeded {
    NSInteger recordedVersion = [self integerForKey:kThemeMigrationVersionKey];
    if (recordedVersion >= kCurrentThemeMigrationVersion) return;

    if (recordedVersion < 1 && YTAGThemeMatchesLegacyAfterglowPreset(self)) {
        YTAGApplyUpdatedAfterglowPreset(self);
    }

    if (recordedVersion < 2 && !YTAGHasStoredThemePreset(self)) {
        YTAGApplyAfterglow2ThemePreset(self);
    }

    [self setInteger:kCurrentThemeMigrationVersion forKey:kThemeMigrationVersionKey];
}

- (void)migrateSettingsIfNeeded {
    NSInteger recordedVersion = [self integerForKey:kSettingsMigrationVersionKey];
    if (recordedVersion >= kCurrentSettingsMigrationVersion) return;

    NSDictionary *storedSettings = [self persistentDomainForName:kDefaultsSuiteName] ?: @{};
    if (recordedVersion < 4 && storedSettings[@"noPlayerShareButton"] == nil) {
        id mode = storedSettings[@"playerShareButtonMode"];
        BOOL alwaysHide = [storedSettings[@"playerNoShare"] boolValue] ||
                          ([mode respondsToSelector:@selector(integerValue)] && [mode integerValue] == 2);
        [self setBool:alwaysHide forKey:@"noPlayerShareButton"];
    }
    [self removeObjectForKey:@"playerShareButtonMode"];
    [self removeObjectForKey:@"showPlayerShareButton"];
    [self removeObjectForKey:@"playerNoShare"];

    if (recordedVersion < 4 && storedSettings[@"noPlayerSaveButton"] == nil) {
        id mode = storedSettings[@"playerSaveButtonMode"];
        BOOL alwaysHide = [storedSettings[@"playerNoSave"] boolValue] ||
                          ([mode respondsToSelector:@selector(integerValue)] && [mode integerValue] == 2);
        [self setBool:alwaysHide forKey:@"noPlayerSaveButton"];
    }
    [self removeObjectForKey:@"playerSaveButtonMode"];
    [self removeObjectForKey:@"showPlayerSaveButton"];
    [self removeObjectForKey:@"playerNoSave"];

    if ([self objectForKey:@"commentsHeaderMode"] == nil) {
        BOOL pinned = [self boolForKey:@"stickSortComments"];
        BOOL hidden = [self boolForKey:@"hideSortComments"];
        NSInteger mode = hidden ? 2 : (pinned ? 1 : 0);
        [self setInteger:mode forKey:@"commentsHeaderMode"];
    }
    [self removeObjectForKey:@"stickSortComments"];
    [self removeObjectForKey:@"hideSortComments"];

    if ([self objectForKey:@"autoplayMode"] == nil) {
        BOOL disableAutoplay = [self boolForKey:@"disableAutoplay"];
        BOOL hideAutoplay = [self boolForKey:@"hideAutoplay"];
        NSInteger mode = hideAutoplay ? 2 : (disableAutoplay ? 1 : 0);
        [self setInteger:mode forKey:@"autoplayMode"];
    }
    [self removeObjectForKey:@"disableAutoplay"];
    [self removeObjectForKey:@"hideAutoplay"];

    if ([self objectForKey:@"hideEndScreenCards"] == nil && [self objectForKey:@"endScreenCards"] != nil) {
        [self setBool:[self boolForKey:@"endScreenCards"] forKey:@"hideEndScreenCards"];
    }
    [self removeObjectForKey:@"endScreenCards"];

    if (recordedVersion < 2) {
        [self setActiveTabs:[self currentActiveTabs]];

        NSString *startupTab = [self objectForKey:kStartupTabKey];
        if ([startupTab isKindOfClass:[NSString class]] && [startupTab isEqualToString:@"FEexplore"]) {
            [self setObject:@"FEtrending" forKey:kStartupTabKey];
        }
    }

    if (recordedVersion < 3) {
        [self setActiveTabs:[self currentActiveTabs]];

        NSString *startupTab = [self objectForKey:kStartupTabKey];
        if ([startupTab isKindOfClass:[NSString class]] &&
            ([startupTab isEqualToString:@"FEexplore"] || [startupTab isEqualToString:@"FEtrending"])) {
            [self setObject:@"FEhype_leaderboard" forKey:kStartupTabKey];
        }
    }

    [self setInteger:kCurrentSettingsMigrationVersion forKey:kSettingsMigrationVersionKey];
}

+ (NSArray<NSString *> *)defaultActiveTabs {
    return @[@"FEwhat_to_watch", @"FEshorts", @"FEsubscriptions", @"FElibrary"];
}

+ (void)resetUserDefaults {
    [[self standardUserDefaults] reset];
}

@end
