#import "YTAGUserDefaults.h"
#import <UIKit/UIKit.h>

@implementation YTAGUserDefaults

static NSString *const kDefaultsSuiteName = @"i.am.kain.afterglow";
static NSString *const kActiveTabsKey = @"activeTabs";
static NSString *const kStartupTabKey = @"startupTab";
static NSString *const kThemeMigrationVersionKey = @"themePresetMigrationVersion";
static const NSUInteger kMinimumActiveTabsCount = 2;
static const NSUInteger kMaximumActiveTabsCount = 6;
static const NSInteger kCurrentThemeMigrationVersion = 1;

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

static NSArray<NSString *> *YTAGAllowedTabs(void) {
    return @[@"FEwhat_to_watch", @"FEshorts", @"FEsubscriptions", @"FElibrary", @"FEexplore", @"FEhistory", @"VLWL", @"FEpost_home", @"FEuploads"];
}

+ (YTAGUserDefaults *)standardUserDefaults {
    static dispatch_once_t onceToken;
    static YTAGUserDefaults *defaults = nil;

    dispatch_once(&onceToken, ^{
        defaults = [[self alloc] initWithSuiteName:kDefaultsSuiteName];
        [defaults registerDefaults];
        [defaults migrateThemePresetsIfNeeded];
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

        NSString *tabId = (NSString *)item;
        if (![allowedTabs containsObject:tabId] || [sanitizedTabs containsObject:tabId]) continue;

        [sanitizedTabs addObject:tabId];
        if (sanitizedTabs.count >= kMaximumActiveTabsCount) break;
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
        @"frostedPivot": @YES
    }];
}

- (void)migrateThemePresetsIfNeeded {
    NSInteger recordedVersion = [self integerForKey:kThemeMigrationVersionKey];
    if (recordedVersion >= kCurrentThemeMigrationVersion) return;

    if (YTAGThemeMatchesLegacyAfterglowPreset(self)) {
        YTAGApplyUpdatedAfterglowPreset(self);
    }

    [self setInteger:kCurrentThemeMigrationVersion forKey:kThemeMigrationVersionKey];
}

+ (NSArray<NSString *> *)defaultActiveTabs {
    return @[@"FEwhat_to_watch", @"FEshorts", @"FEsubscriptions", @"FElibrary"];
}

+ (void)resetUserDefaults {
    [[self standardUserDefaults] reset];
}

@end
