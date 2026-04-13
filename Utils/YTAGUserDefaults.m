#import "YTAGUserDefaults.h"

@implementation YTAGUserDefaults

static NSString *const kDefaultsSuiteName = @"com.dvntm.ytafterglow";
static NSString *const kActiveTabsKey = @"activeTabs";
static NSString *const kStartupTabKey = @"startupTab";
static const NSUInteger kMinimumActiveTabsCount = 2;
static const NSUInteger kMaximumActiveTabsCount = 6;

static NSArray<NSString *> *YTAGAllowedTabs(void) {
    return @[@"FEwhat_to_watch", @"FEshorts", @"FEsubscriptions", @"FElibrary", @"FEexplore", @"FEhistory", @"VLWL", @"FEpost_home", @"FEuploads"];
}

+ (YTAGUserDefaults *)standardUserDefaults {
    static dispatch_once_t onceToken;
    static YTAGUserDefaults *defaults = nil;

    dispatch_once(&onceToken, ^{
        defaults = [[self alloc] initWithSuiteName:kDefaultsSuiteName];
        [defaults registerDefaults];
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

+ (NSArray<NSString *> *)defaultActiveTabs {
    return @[@"FEwhat_to_watch", @"FEshorts", @"FEsubscriptions", @"FElibrary"];
}

+ (void)resetUserDefaults {
    [[self standardUserDefaults] reset];
}

@end
