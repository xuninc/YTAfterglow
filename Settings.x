#import "YTLite.h"
#import <objc/runtime.h>

extern void ytl_clearThemeCache(void);
static void ytl_presentThemeRefreshAlert(UIViewController *presenter, NSString *title, NSString *message);

@interface YTSettingsSectionItemManager (YTLite)
- (void)updateYTLiteSectionWithEntry:(id)entry;
- (YTSettingsSectionItem *)pageItemWithTitle:(NSString *)title titleDescription:(NSString *)titleDescription summary:(NSString *(^)(void))summaryBlock selectBlock:(BOOL (^)(YTSettingsCell *cell, NSUInteger arg1))selectBlock;
- (NSString *)enabledSummaryForKeys:(NSArray<NSString *> *)keys;
- (NSString *)customizationSummaryForKeys:(NSArray<NSString *> *)keys;
- (NSString *)themeCustomizationSummary;
- (YTSettingsSectionItem *)holdToSpeedItemWithSettingsVC:(YTSettingsViewController *)settingsViewController;
- (YTSettingsSectionItem *)defaultPlaybackRateItemWithSettingsVC:(YTSettingsViewController *)settingsViewController;
- (YTSettingsSectionItem *)playbackQualityItemWithTitle:(NSString *)title key:(NSString *)key settingsVC:(YTSettingsViewController *)settingsViewController;
- (YTSettingsSectionItem *)startupTabItemWithSettingsVC:(YTSettingsViewController *)settingsViewController;
- (NSString *)themeHexFromColor:(UIColor *)color;
- (NSString *)themeColorDetailForKey:(NSString *)key;
- (NSString *)themeCustomColorsSummary;
- (NSString *)themeGradientSummary;
- (NSString *)themeAppearanceSummary;
- (UIColor *)themeLoadColorForKey:(NSString *)key;
- (void)themePresentPickerForKey:(NSString *)themeKey startColor:(UIColor *)startColor settingsVC:(YTSettingsViewController *)settingsVC;
- (void)themeAddColorRowWithTitle:(NSString *)title titleDescription:(NSString *)titleDescription themeKey:(NSString *)themeKey toRows:(NSMutableArray *)rows settingsVC:(YTSettingsViewController *)settingsVC;
- (void)themeSaveColor:(UIColor *)color forKey:(NSString *)key;
- (void)themeApplyPresetOverlay:(UIColor *)overlay tabIcons:(UIColor *)tabIcons seekBar:(UIColor *)seekBar bg:(UIColor *)bg textP:(UIColor *)textP textS:(UIColor *)textS nav:(UIColor *)nav accent:(UIColor *)accent;
- (void)themeAddPresetRowWithName:(NSString *)name titleDescription:(NSString *)titleDescription overlay:(UIColor *)overlay tabIcons:(UIColor *)tabIcons seekBar:(UIColor *)seekBar bg:(UIColor *)bg textP:(UIColor *)textP textS:(UIColor *)textS nav:(UIColor *)nav accent:(UIColor *)accent toRows:(NSMutableArray *)rows settingsVC:(YTSettingsViewController *)settingsVC;
- (YTSettingsSectionItem *)themeSectionHeaderWithTitle:(NSString *)title description:(NSString *)description;
@end

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

// Color picker delegate — guarded by @available(iOS 14.0, *) at call sites
@interface YTLColorPickerDelegate : NSObject <UIColorPickerViewControllerDelegate>
@property (nonatomic, copy) NSString *themeKey;
@property (nonatomic, weak) YTSettingsViewController *settingsVC;
@property (nonatomic, assign) BOOL didSelect;
@property (nonatomic, assign) CFAbsoluteTime lastSave;
@end

@implementation YTLColorPickerDelegate
- (void)colorPickerViewController:(UIColorPickerViewController *)vc didSelectColor:(UIColor *)color continuously:(BOOL)continuously {
    if (!color || !self.themeKey) return;
    self.didSelect = YES;

    // Throttle: save at most every 0.25s during continuous drag
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (continuously && (now - self.lastSave) < 0.25) return;
    self.lastSave = now;

    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:color requiringSecureCoding:NO error:nil];
    [[YTLUserDefaults standardUserDefaults] setObject:data forKey:self.themeKey];
    ytl_clearThemeCache();
}
- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)vc {
    // Final save on dismiss
    UIColor *color = vc.selectedColor;
    if (color && self.themeKey) {
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:color requiringSecureCoding:NO error:nil];
        [[YTLUserDefaults standardUserDefaults] setObject:data forKey:self.themeKey];
        ytl_clearThemeCache();
    }

    // Reload settings + show alert
    __weak YTSettingsViewController *weakVC = self.settingsVC;
    BOOL selected = self.didSelect;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakVC reloadData];
        if (selected && weakVC) {
            UIViewController *presenter = weakVC.navigationController.topViewController ?: weakVC;
            ytl_presentThemeRefreshAlert(presenter, LOC(@"ColorSaved"), @"Some surfaces refresh immediately. Restart YouTube for a full theme refresh across the app.");
        }
    });
}
@end

#pragma clang diagnostic pop

static const NSInteger YTLiteSection = 789;
static YTLColorPickerDelegate *_colorPickerDelegate = nil;

static UIColor *YTLAfterglowTintColor(void) {
    return [UIColor colorWithRed:0.95 green:0.41 blue:0.50 alpha:1.0];
}

static void ytl_presentThemeRefreshAlert(UIViewController *presenter, NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
        message:message
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:LOC(@"RestartNow") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        exit(0);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:LOC(@"Later") style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

static NSString *GetCacheSize() {
    NSString *cachePath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    NSArray *filesArray = [[NSFileManager defaultManager] subpathsOfDirectoryAtPath:cachePath error:nil];

    unsigned long long int folderSize = 0;
    for (NSString *fileName in filesArray) {
        NSString *filePath = [cachePath stringByAppendingPathComponent:fileName];
        NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
        folderSize += [fileAttributes fileSize];
    }

    NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
    formatter.countStyle = NSByteCountFormatterCountStyleFile;

    return [formatter stringFromByteCount:folderSize];
}

// Settings
%hook YTSettingsSectionController
- (void)setSelectedItem:(NSUInteger)selectedItem {
    if (selectedItem != NSNotFound) %orig;
}
%end

%hook YTSettingsCell
- (void)layoutSubviews {
    %orig;

    BOOL isYTLite = [self.accessibilityIdentifier isEqualToString:@"YTLiteSectionItem"];
    YTTouchFeedbackController *feedback = [self valueForKey:@"_touchFeedbackController"];
    ABCSwitch *abcSwitch = [self valueForKey:@"_switch"];

    if (isYTLite) {
        feedback.feedbackColor = YTLAfterglowTintColor();
        abcSwitch.onTintColor = YTLAfterglowTintColor();
    }
}
%end

%hook YTSettingsSectionItemManager
%new
- (YTSettingsSectionItem *)switchWithTitle:(NSString *)title key:(NSString *)key {
    Class YTSettingsSectionItemClass = %c(YTSettingsSectionItem);
    Class YTAlertViewClass = %c(YTAlertView);
    NSString *titleDesc = [NSString stringWithFormat:@"%@Desc", title];

    YTSettingsSectionItem *item = [YTSettingsSectionItemClass switchItemWithTitle:LOC(title)
    titleDescription:LOC(titleDesc)
    accessibilityIdentifier:@"YTLiteSectionItem"
    switchOn:ytlBool(key)
    switchBlock:^BOOL(YTSettingsCell *cell, BOOL enabled) {
        if ([key isEqualToString:@"shortsOnlyMode"]) {
            YTAlertView *alertView = [YTAlertViewClass confirmationDialogWithAction:^{
                ytlSetBool(enabled, @"shortsOnlyMode");
            }
            actionTitle:LOC(@"Yes")
            cancelAction:^{
                [cell setSwitchOn:!enabled animated:YES];
            }
            cancelTitle:LOC(@"No")];
            alertView.title = LOC(@"Warning");
            alertView.subtitle = LOC(@"ShortsOnlyWarning");
            [alertView show];
        } else {
            ytlSetBool(enabled, key);

            NSArray *keys = @[@"removeLabels", @"removeIndicators", @"frostedPivot",
                @"theme_overlayButtons", @"theme_tabBarIcons", @"theme_seekBar",
                @"theme_background", @"theme_textPrimary", @"theme_textSecondary",
                @"theme_navBar", @"theme_accent",
                @"theme_gradientStart", @"theme_gradientEnd"];
            if ([keys containsObject:key]) {
                [[[%c(YTHeaderContentComboViewController) alloc] init] refreshPivotBar];
            }
        }

        return YES;
    }
    settingItemId:0];

    return item;
}

%new
- (YTSettingsSectionItem *)linkWithTitle:(NSString *)title description:(NSString *)description link:(NSString *)link {
    return [%c(YTSettingsSectionItem) itemWithTitle:title
    titleDescription:description
    accessibilityIdentifier:@"YTLiteSectionItem"
    detailTextBlock:nil
    selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
        return [%c(YTUIUtils) openURL:[NSURL URLWithString:link]];
    }];
}

%new
- (YTSettingsSectionItem *)pageItemWithTitle:(NSString *)title titleDescription:(NSString *)titleDescription summary:(NSString *(^)(void))summaryBlock selectBlock:(BOOL (^)(YTSettingsCell *cell, NSUInteger arg1))selectBlock {
    Class YTSettingsSectionItemClass = %c(YTSettingsSectionItem);

    return [YTSettingsSectionItemClass itemWithTitle:title
        titleDescription:titleDescription
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() {
            return summaryBlock ? summaryBlock() : @"\u2023";
        }
        selectBlock:selectBlock];
}

%new
- (NSString *)enabledSummaryForKeys:(NSArray<NSString *> *)keys {
    NSUInteger enabledCount = 0;
    for (NSString *key in keys) {
        if (ytlBool(key)) enabledCount++;
    }

    if (enabledCount == 0) return LOC(@"Disabled");
    if (enabledCount == 1) return @"1 on";
    return [NSString stringWithFormat:@"%lu on", (unsigned long)enabledCount];
}

%new
- (NSString *)customizationSummaryForKeys:(NSArray<NSString *> *)keys {
    NSUInteger customizedCount = 0;

    for (NSString *key in keys) {
        if ([[YTLUserDefaults standardUserDefaults] objectForKey:key] != nil) customizedCount++;
    }

    if (customizedCount == 0) return LOC(@"Default");
    if (customizedCount == 1) return @"1 custom";
    return [NSString stringWithFormat:@"%lu custom", (unsigned long)customizedCount];
}

%new
- (NSString *)themeCustomizationSummary {
    NSArray *keys = @[@"theme_overlayButtons", @"theme_tabBarIcons", @"theme_seekBar",
                      @"theme_background", @"theme_textPrimary", @"theme_textSecondary",
                      @"theme_navBar", @"theme_accent",
                      @"theme_gradientStart", @"theme_gradientEnd"];
    return [self customizationSummaryForKeys:keys];
}

%new
- (YTSettingsSectionItem *)holdToSpeedItemWithSettingsVC:(YTSettingsViewController *)settingsViewController {
    Class YTSettingsSectionItemClass = %c(YTSettingsSectionItem);

    return [YTSettingsSectionItemClass itemWithTitle:LOC(@"HoldToSpeed")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() {
            NSArray *speedLabels = @[LOC(@"Disabled"), LOC(@"Default"), @"0.25×", @"0.5×", @"0.75×", @"1.0×", @"1.25×", @"1.5×", @"1.75×", @"2.0×", @"3.0×", @"4.0×", @"5.0×"];
            return speedLabels[ytlInt(@"speedIndex")];
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray <YTSettingsSectionItem *> *rows = [NSMutableArray array];
            NSArray *speedLabels = @[LOC(@"Disable"), LOC(@"Default"), @"0.25×", @"0.5×", @"0.75×", @"1.0×", @"1.25×", @"1.5×", @"1.75×", @"2.0×", @"3.0×", @"4.0×", @"5.0×"];

            for (NSUInteger i = 0; i < speedLabels.count; i++) {
                NSString *title = speedLabels[i];
                YTSettingsSectionItem *item = [YTSettingsSectionItemClass checkmarkItemWithTitle:title titleDescription:nil selectBlock:^BOOL (YTSettingsCell *innerCell, NSUInteger innerArg1) {
                    [settingsViewController reloadData];
                    ytlSetInt((int)innerArg1, @"speedIndex");
                    return YES;
                }];

                [rows addObject:item];
            }

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"HoldToSpeed") pickerSectionTitle:nil rows:rows selectedItemIndex:ytlInt(@"speedIndex") parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];
}

%new
- (YTSettingsSectionItem *)defaultPlaybackRateItemWithSettingsVC:(YTSettingsViewController *)settingsViewController {
    Class YTSettingsSectionItemClass = %c(YTSettingsSectionItem);

    return [YTSettingsSectionItemClass itemWithTitle:LOC(@"DefaultPlaybackRate")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() {
            NSArray *speedLabels = @[@"0.25×", @"0.5×", @"0.75×", @"1.0×", @"1.25×", @"1.5×", @"1.75×", @"2.0×", @"3.0×", @"4.0×", @"5.0×"];
            return speedLabels[ytlInt(@"autoSpeedIndex")];
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray <YTSettingsSectionItem *> *rows = [NSMutableArray array];
            NSArray *speedLabels = @[@"0.25×", @"0.5×", @"0.75×", @"1.0×", @"1.25×", @"1.5×", @"1.75×", @"2.0×", @"3.0×", @"4.0×", @"5.0×"];

            for (NSUInteger i = 0; i < speedLabels.count; i++) {
                NSString *title = speedLabels[i];
                YTSettingsSectionItem *item = [YTSettingsSectionItemClass checkmarkItemWithTitle:title titleDescription:nil selectBlock:^BOOL (YTSettingsCell *innerCell, NSUInteger innerArg1) {
                    [settingsViewController reloadData];
                    ytlSetInt((int)innerArg1, @"autoSpeedIndex");
                    return YES;
                }];
                [rows addObject:item];
            }

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"DefaultPlaybackRate") pickerSectionTitle:nil rows:rows selectedItemIndex:ytlInt(@"autoSpeedIndex") parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];
}

%new
- (YTSettingsSectionItem *)playbackQualityItemWithTitle:(NSString *)title key:(NSString *)key settingsVC:(YTSettingsViewController *)settingsViewController {
    Class YTSettingsSectionItemClass = %c(YTSettingsSectionItem);

    return [YTSettingsSectionItemClass itemWithTitle:LOC(title)
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() {
            NSArray *qualityLabels = @[LOC(@"Default"), LOC(@"Best"), @"2160p60", @"2160p", @"1440p60", @"1440p", @"1080p60", @"1080p", @"720p60", @"720p", @"480p", @"360p"];
            return qualityLabels[ytlInt(key)];
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray <YTSettingsSectionItem *> *rows = [NSMutableArray array];
            NSArray *qualityLabels = @[LOC(@"Default"), LOC(@"Best"), @"2160p60", @"2160p", @"1440p60", @"1440p", @"1080p60", @"1080p", @"720p60", @"720p", @"480p", @"360p"];

            for (NSUInteger i = 0; i < qualityLabels.count; i++) {
                NSString *qualityTitle = qualityLabels[i];
                YTSettingsSectionItem *item = [YTSettingsSectionItemClass checkmarkItemWithTitle:qualityTitle titleDescription:nil selectBlock:^BOOL (YTSettingsCell *innerCell, NSUInteger innerArg1) {
                    [settingsViewController reloadData];
                    ytlSetInt((int)innerArg1, key);
                    return YES;
                }];

                [rows addObject:item];
            }

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"SelectQuality") pickerSectionTitle:nil rows:rows selectedItemIndex:ytlInt(key) parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];
}

%new
- (YTSettingsSectionItem *)startupTabItemWithSettingsVC:(YTSettingsViewController *)settingsViewController {
    Class YTSettingsSectionItemClass = %c(YTSettingsSectionItem);

    return [YTSettingsSectionItemClass itemWithTitle:LOC(@"Startup")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() {
            NSString *tab = [[YTLUserDefaults standardUserDefaults] currentStartupTab];
            NSDictionary *names = @{@"FEwhat_to_watch": LOC(@"FEwhat_to_watch"), @"FEshorts": LOC(@"FEshorts"), @"FEsubscriptions": LOC(@"FEsubscriptions"), @"FElibrary": LOC(@"FElibrary"), @"FEexplore": LOC(@"FEexplore"), @"FEhistory": LOC(@"FEhistory"), @"VLWL": LOC(@"VLWL")};
            return names[tab] ?: tab;
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSArray *activeTabs = [[YTLUserDefaults standardUserDefaults] currentActiveTabs];
            NSDictionary *names = @{@"FEwhat_to_watch": LOC(@"FEwhat_to_watch"), @"FEshorts": LOC(@"FEshorts"), @"FEsubscriptions": LOC(@"FEsubscriptions"), @"FElibrary": LOC(@"FElibrary"), @"FEexplore": LOC(@"FEexplore"), @"FEhistory": LOC(@"FEhistory"), @"VLWL": LOC(@"VLWL")};
            NSString *currentTab = [[YTLUserDefaults standardUserDefaults] currentStartupTab];

            NSMutableArray <YTSettingsSectionItem *> *rows = [NSMutableArray array];
            NSInteger selectedIdx = 0;

            for (NSUInteger i = 0; i < activeTabs.count; i++) {
                NSString *tabId = activeTabs[i];
                NSString *title = names[tabId] ?: tabId;
                if ([tabId isEqualToString:currentTab]) selectedIdx = i;

                YTSettingsSectionItem *item = [YTSettingsSectionItemClass checkmarkItemWithTitle:title titleDescription:nil selectBlock:^BOOL (YTSettingsCell *innerCell, NSUInteger innerArg1) {
                    [[YTLUserDefaults standardUserDefaults] setObject:tabId forKey:@"startupTab"];
                    [settingsViewController reloadData];
                    return YES;
                }];
                [rows addObject:item];
            }

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Startup") pickerSectionTitle:nil rows:rows selectedItemIndex:selectedIdx parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];
}

#pragma mark - Theme Helpers

%new
- (NSString *)themeHexFromColor:(UIColor *)color {
    CGFloat r, g, b, a;
    [color getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"#%02X%02X%02X", (int)(r*255), (int)(g*255), (int)(b*255)];
}

%new
- (NSString *)themeColorDetailForKey:(NSString *)key {
    UIColor *color = [self themeLoadColorForKey:key];
    return color ? [self themeHexFromColor:color] : LOC(@"Default");
}

%new
- (NSString *)themeCustomColorsSummary {
    NSArray *keys = @[@"theme_overlayButtons", @"theme_tabBarIcons", @"theme_seekBar",
                      @"theme_background", @"theme_textPrimary", @"theme_textSecondary",
                      @"theme_navBar", @"theme_accent"];
    return [self customizationSummaryForKeys:keys];
}

%new
- (NSString *)themeGradientSummary {
    UIColor *start = [self themeLoadColorForKey:@"theme_gradientStart"];
    UIColor *end = [self themeLoadColorForKey:@"theme_gradientEnd"];

    if (!start && !end) return @"Off";
    if (!start || !end) return @"Incomplete";
    return [NSString stringWithFormat:@"%@ to %@", [self themeHexFromColor:start], [self themeHexFromColor:end]];
}

%new
- (NSString *)themeAppearanceSummary {
    NSUInteger customizedCount = 0;
    NSArray *colorKeys = @[@"theme_overlayButtons", @"theme_tabBarIcons", @"theme_seekBar",
                           @"theme_background", @"theme_textPrimary", @"theme_textSecondary",
                           @"theme_navBar", @"theme_accent"];
    for (NSString *key in colorKeys) {
        if ([[YTLUserDefaults standardUserDefaults] objectForKey:key] != nil) customizedCount++;
    }

    BOOL hasGradientStart = [[YTLUserDefaults standardUserDefaults] objectForKey:@"theme_gradientStart"] != nil;
    BOOL hasGradientEnd = [[YTLUserDefaults standardUserDefaults] objectForKey:@"theme_gradientEnd"] != nil;
    BOOL hasGradient = hasGradientStart || hasGradientEnd;

    if (customizedCount == 0 && !hasGradient) return LOC(@"Default");
    if (customizedCount == 0) return [NSString stringWithFormat:@"Gradient %@", [self themeGradientSummary]];
    if (!hasGradient) return customizedCount == 1 ? @"1 color override" : [NSString stringWithFormat:@"%lu color overrides", (unsigned long)customizedCount];
    return [NSString stringWithFormat:@"%lu colors + gradient", (unsigned long)customizedCount];
}

%new
- (UIColor *)themeLoadColorForKey:(NSString *)key {
    NSData *data = [[YTLUserDefaults standardUserDefaults] objectForKey:key];
    if (!data) return nil;
    NSKeyedUnarchiver *u = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:nil];
    [u setRequiresSecureCoding:NO];
    return [u decodeObjectForKey:NSKeyedArchiveRootObjectKey];
}

%new
- (void)themePresentPickerForKey:(NSString *)themeKey startColor:(UIColor *)startColor settingsVC:(YTSettingsViewController *)settingsVC {
    if (@available(iOS 14.0, *)) {
        UIColorPickerViewController *picker = [[UIColorPickerViewController alloc] init];
        picker.supportsAlpha = NO;
        if (startColor) picker.selectedColor = startColor;
        YTLColorPickerDelegate *delegate = [[YTLColorPickerDelegate alloc] init];
        delegate.themeKey = themeKey;
        delegate.settingsVC = settingsVC;
        delegate.didSelect = NO;
        picker.delegate = delegate;
        _colorPickerDelegate = delegate;
        UIViewController *presenter = settingsVC.navigationController.topViewController ?: settingsVC;
        while (presenter.presentedViewController) presenter = presenter.presentedViewController;
        [presenter presentViewController:picker animated:YES completion:nil];
    }
}

%new
- (void)themeAddColorRowWithTitle:(NSString *)title titleDescription:(NSString *)titleDescription themeKey:(NSString *)themeKey toRows:(NSMutableArray *)rows settingsVC:(YTSettingsViewController *)settingsVC {
    Class YTSettingsSectionItemClass = %c(YTSettingsSectionItem);

    YTSettingsSectionItem *item = [YTSettingsSectionItemClass itemWithTitle:LOC(title)
        titleDescription:titleDescription
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() {
            return [self themeColorDetailForKey:themeKey];
        }
        selectBlock:^BOOL(YTSettingsCell *c, NSUInteger a) {
            [self themePresentPickerForKey:themeKey startColor:[self themeLoadColorForKey:themeKey] settingsVC:settingsVC];
            return YES;
        }];
    [rows addObject:item];

    if ([self themeLoadColorForKey:themeKey]) {
        YTSettingsSectionItem *reset = [YTSettingsSectionItemClass itemWithTitle:[NSString stringWithFormat:@"Use Default %@", LOC(title)]
            titleDescription:@"Restore the default color."
            accessibilityIdentifier:@"YTLiteSectionItem"
            detailTextBlock:^NSString *() {
                return [NSString stringWithFormat:@"Clears %@", [self themeColorDetailForKey:themeKey]];
            }
            selectBlock:^BOOL(YTSettingsCell *c, NSUInteger a) {
                [[YTLUserDefaults standardUserDefaults] removeObjectForKey:themeKey];
                ytl_clearThemeCache();
                [settingsVC reloadData];
                [(UINavigationController *)settingsVC.navigationController popViewControllerAnimated:YES];
                return YES;
            }];
        [rows addObject:reset];
    }
}

%new
- (void)themeSaveColor:(UIColor *)color forKey:(NSString *)key {
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:color requiringSecureCoding:NO error:nil];
    [[YTLUserDefaults standardUserDefaults] setObject:data forKey:key];
}

%new
- (void)themeApplyPresetOverlay:(UIColor *)overlay tabIcons:(UIColor *)tabIcons seekBar:(UIColor *)seekBar bg:(UIColor *)bg textP:(UIColor *)textP textS:(UIColor *)textS nav:(UIColor *)nav accent:(UIColor *)accent {
    [self themeSaveColor:overlay forKey:@"theme_overlayButtons"];
    [self themeSaveColor:tabIcons forKey:@"theme_tabBarIcons"];
    [self themeSaveColor:seekBar forKey:@"theme_seekBar"];
    [self themeSaveColor:bg forKey:@"theme_background"];
    [self themeSaveColor:textP forKey:@"theme_textPrimary"];
    [self themeSaveColor:textS forKey:@"theme_textSecondary"];
    [self themeSaveColor:nav forKey:@"theme_navBar"];
    [self themeSaveColor:accent forKey:@"theme_accent"];
    ytl_clearThemeCache();
}

%new
- (void)themeAddPresetRowWithName:(NSString *)name titleDescription:(NSString *)titleDescription overlay:(UIColor *)overlay tabIcons:(UIColor *)tabIcons seekBar:(UIColor *)seekBar bg:(UIColor *)bg textP:(UIColor *)textP textS:(UIColor *)textS nav:(UIColor *)nav accent:(UIColor *)accent toRows:(NSMutableArray *)rows settingsVC:(YTSettingsViewController *)settingsVC {
    Class YTSettingsSectionItemClass = %c(YTSettingsSectionItem);

    YTSettingsSectionItem *item = [YTSettingsSectionItemClass itemWithTitle:name
        titleDescription:titleDescription
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() {
            return @"Apply";
        }
        selectBlock:^BOOL(YTSettingsCell *c, NSUInteger a) {
            [self themeApplyPresetOverlay:overlay tabIcons:tabIcons seekBar:seekBar bg:bg textP:textP textS:textS nav:nav accent:accent];
            UIViewController *presenter = settingsVC.navigationController.topViewController ?: settingsVC;
            ytl_presentThemeRefreshAlert(presenter, LOC(@"PresetApplied"), [NSString stringWithFormat:@"%@ is ready. Restart YouTube for the full look across every surface.", name]);
            return YES;
        }];
    [rows addObject:item];
}

%new
- (YTSettingsSectionItem *)themeSectionHeaderWithTitle:(NSString *)title description:(NSString *)description {
    YTSettingsSectionItem *item = [%c(YTSettingsSectionItem) itemWithTitle:title
        titleDescription:description
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:nil
        selectBlock:nil];
    item.enabled = NO;
    return item;
}

#pragma mark - Settings Section

%new(v@:@)
- (void)updateYTLiteSectionWithEntry:(id)entry {
    NSMutableArray *sectionItems = [NSMutableArray array];
    YTSettingsViewController *settingsViewController = [self valueForKey:@"_settingsViewControllerDelegate"];
    BOOL isAdvanced = ytlBool(@"advancedMode");

    YTSettingsSectionItem *space = [%c(YTSettingsSectionItem) itemWithTitle:nil accessibilityIdentifier:@"YTLiteSectionItem" detailTextBlock:nil selectBlock:nil];
    NSArray *adsKeys = @[@"noAds", @"noPromotionCards"];
    NSArray *navbarKeys = @[@"noCast", @"noNotifsButton", @"noSearchButton", @"noVoiceSearchButton", @"stickyNavbar", @"noSubbar", @"noYTLogo", @"premiumYTLogo"];
    NSArray *tabbarKeys = @[@"frostedPivot", @"removeLabels", @"removeIndicators"];
    NSArray *overlayKeys = @[@"hideAutoplay", @"hideSubs", @"noHUDMsgs", @"hidePrevNext", @"replacePrevNext", @"noDarkBg", @"endScreenCards", @"noFullscreenActions", @"persistentProgressBar", @"stockVolumeHUD", @"noRelatedVids", @"noWatermarks", @"videoEndTime", @"24hrFormat"];
    NSArray *playerKeys = @[@"backgroundPlayback", @"miniplayer", @"portraitFullscreen", @"copyWithTimestamp", @"disableAutoplay", @"disableAutoCaptions", @"noContentWarning", @"classicQuality", @"extraSpeedOptions", @"dontSnapToChapter", @"noTwoFingerSnapToChapter", @"pauseOnOverlay", @"redProgressBar", @"noPlayerRemixButton", @"noPlayerClipButton", @"noHints", @"noFreeZoom", @"autoFullscreen", @"exitFullscreen", @"noDoubleTapToSeek"];
    NSArray *shortsBehaviorKeys = @[@"shortsOnlyMode", @"autoSkipShorts", @"hideShorts", @"shortsProgress", @"pinchToFullscreenShorts", @"shortsToRegular", @"resumeShorts"];
    NSArray *shortsUIKeys = @[@"hideShortsLogo", @"hideShortsSearch", @"hideShortsCamera", @"hideShortsMore", @"hideShortsSubscriptions", @"hideShortsLike", @"hideShortsDislike", @"hideShortsComments", @"hideShortsRemix", @"hideShortsShare", @"hideShortsAvatars", @"hideShortsThanks", @"hideShortsSource", @"hideShortsChannelName", @"hideShortsDescription", @"hideShortsAudioTrack", @"hideShortsPromoCards"];
    NSArray *downloadUIKeys = @[@"removeDownloadMenu", @"noPlayerDownloadButton", @"removeShareMenu"];
    NSArray *downloadToolKeys = @[@"copyVideoInfo", @"postManager", @"saveProfilePhoto", @"commentManager", @"fixAlbums", @"nativeShare"];
    NSArray *downloadKeys = [downloadUIKeys arrayByAddingObjectsFromArray:downloadToolKeys];
    NSArray *menuKeys = @[@"removePlayNext", @"removeWatchLaterMenu", @"removeSaveToPlaylistMenu", @"removeNotInterestedMenu", @"removeDontRecommendMenu", @"removeReportMenu"];
    NSArray *feedKeys = @[@"noContinueWatching", @"noSearchHistory", @"noRelatedWatchNexts"];
    NSArray *commentKeys = @[@"stickSortComments", @"hideSortComments", @"playlistOldMinibar", @"disableRTL"];

    YTSettingsSectionItem *ads = [self pageItemWithTitle:LOC(@"Ads")
        titleDescription:@"Remove ads and promotional clutter."
        summary:^NSString *() {
            return [self enabledSummaryForKeys:adsKeys];
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSArray <YTSettingsSectionItem *> *rows = @[
                [self switchWithTitle:@"RemoveAds" key:@"noAds"],
                [self switchWithTitle:@"NoPromotionCards" key:@"noPromotionCards"]
            ];

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Ads") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:ads];

    YTSettingsSectionItem *interface = [self pageItemWithTitle:LOC(@"Interface")
        titleDescription:@"App chrome, tabs, and startup behavior."
        summary:^NSString *() {
            NSArray *controlKeys = [navbarKeys arrayByAddingObjectsFromArray:tabbarKeys];
            return [self enabledSummaryForKeys:controlKeys];
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray <YTSettingsSectionItem *> *rows = [NSMutableArray array];

            [rows addObject:[self pageItemWithTitle:LOC(@"Navbar")
                titleDescription:@"Top bar buttons and header presentation."
                summary:^NSString *() {
                    return [self enabledSummaryForKeys:navbarKeys];
                }
                selectBlock:^BOOL (YTSettingsCell *innerCell, NSUInteger innerArg1) {
                    NSMutableArray <YTSettingsSectionItem *> *navbarRows = [@[
                        [self switchWithTitle:@"RemoveCast" key:@"noCast"],
                        [self switchWithTitle:@"RemoveNotifications" key:@"noNotifsButton"],
                        [self switchWithTitle:@"RemoveSearch" key:@"noSearchButton"],
                        [self switchWithTitle:@"RemoveVoiceSearch" key:@"noVoiceSearchButton"]
                    ] mutableCopy];

                    if (isAdvanced) {
                        [navbarRows addObjectsFromArray:@[
                            [self switchWithTitle:@"StickyNavbar" key:@"stickyNavbar"],
                            [self switchWithTitle:@"NoSubbar" key:@"noSubbar"],
                            [self switchWithTitle:@"NoYTLogo" key:@"noYTLogo"],
                            [self switchWithTitle:@"PremiumYTLogo" key:@"premiumYTLogo"]
                        ]];
                    }

                    YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Navbar") pickerSectionTitle:nil rows:navbarRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                    [settingsViewController pushViewController:picker];
                    return YES;
                }]];

            [rows addObject:[self pageItemWithTitle:LOC(@"Tabbar")
                titleDescription:@"Visible tabs, labels, indicators, and bar styling."
                summary:^NSString *() {
                    return [NSString stringWithFormat:@"%lu tabs", (unsigned long)[[YTLUserDefaults standardUserDefaults] currentActiveTabs].count];
                }
                selectBlock:^BOOL (YTSettingsCell *innerCell, NSUInteger innerArg1) {
                    NSMutableArray <YTSettingsSectionItem *> *tabRows = [NSMutableArray array];
                    [tabRows addObject:[self switchWithTitle:@"OpaqueBar" key:@"frostedPivot"]];
                    [tabRows addObject:[self switchWithTitle:@"RemoveLabels" key:@"removeLabels"]];
                    [tabRows addObject:[self switchWithTitle:@"RemoveIndicators" key:@"removeIndicators"]];

                    NSArray *allTabs = @[@"FEwhat_to_watch", @"FEshorts", @"FEsubscriptions", @"FElibrary", @"FEexplore", @"FEhistory", @"VLWL", @"FEpost_home", @"FEuploads"];
                    NSDictionary *tabNames = @{
                        @"FEwhat_to_watch": LOC(@"FEwhat_to_watch"),
                        @"FEshorts": LOC(@"FEshorts"),
                        @"FEsubscriptions": LOC(@"FEsubscriptions"),
                        @"FElibrary": LOC(@"FElibrary"),
                        @"FEexplore": LOC(@"FEexplore"),
                        @"FEhistory": LOC(@"FEhistory"),
                        @"VLWL": LOC(@"VLWL"),
                        @"FEpost_home": @"Posts",
                        @"FEuploads": @"Create"
                    };
                    NSDictionary *tabIconTypes = @{
                        @"FEwhat_to_watch": @(65),
                        @"FEshorts": @(772),
                        @"FEsubscriptions": @(66),
                        @"FElibrary": @(68),
                        @"FEexplore": @(67),
                        @"FEhistory": @(2),
                        @"VLWL": @(3),
                        @"FEpost_home": @(267),
                        @"FEuploads": @(1136)
                    };
                    NSMutableArray *activeTabs = [[[YTLUserDefaults standardUserDefaults] currentActiveTabs] mutableCopy];

                    YTSettingsSectionItem *activeHeader = [%c(YTSettingsSectionItem) itemWithTitle:LOC(@"ActiveTabs") accessibilityIdentifier:@"YTLiteSectionItem" detailTextBlock:nil selectBlock:nil];
                    activeHeader.enabled = NO;
                    [tabRows addObject:activeHeader];

                    for (NSString *tabId in activeTabs) {
                        NSString *name = tabNames[tabId] ?: tabId;
                        YTSettingsSectionItem *item = [%c(YTSettingsSectionItem) itemWithTitle:name accessibilityIdentifier:@"YTLiteSectionItem" detailTextBlock:nil selectBlock:^BOOL(YTSettingsCell *tabCell, NSUInteger tabArg1) {
                            NSMutableArray *current = [[[YTLUserDefaults standardUserDefaults] currentActiveTabs] mutableCopy];
                            if (current.count <= 2) {
                                YTAlertView *alert = [%c(YTAlertView) infoDialog];
                                alert.title = LOC(@"Warning");
                                alert.subtitle = LOC(@"AtLeastOneTab");
                                [alert show];
                                return NO;
                            }
                            [current removeObject:tabId];
                            [[YTLUserDefaults standardUserDefaults] setActiveTabs:current];
                            [[[%c(YTHeaderContentComboViewController) alloc] init] refreshPivotBar];
                            [(UINavigationController *)settingsViewController.navigationController popViewControllerAnimated:YES];
                            return YES;
                        }];

                        NSNumber *iconType = tabIconTypes[tabId];
                        if (iconType) {
                            YTIIcon *icon = [%c(YTIIcon) new];
                            icon.iconType = [iconType intValue];
                            item.settingIcon = icon;
                        }
                        [tabRows addObject:item];
                    }

                    YTSettingsSectionItem *inactiveHeader = [%c(YTSettingsSectionItem) itemWithTitle:LOC(@"InactiveTabs") accessibilityIdentifier:@"YTLiteSectionItem" detailTextBlock:nil selectBlock:nil];
                    inactiveHeader.enabled = NO;
                    [tabRows addObject:inactiveHeader];

                    for (NSString *tabId in allTabs) {
                        if ([activeTabs containsObject:tabId]) continue;
                        NSString *name = tabNames[tabId] ?: tabId;
                        YTSettingsSectionItem *item = [%c(YTSettingsSectionItem) itemWithTitle:name accessibilityIdentifier:@"YTLiteSectionItem" detailTextBlock:nil selectBlock:^BOOL(YTSettingsCell *tabCell, NSUInteger tabArg1) {
                            NSMutableArray *current = [[[YTLUserDefaults standardUserDefaults] currentActiveTabs] mutableCopy];
                            if ([current containsObject:tabId]) return NO;
                            if (current.count >= 6) {
                                YTAlertView *alert = [%c(YTAlertView) infoDialog];
                                alert.title = LOC(@"Warning");
                                alert.subtitle = LOC(@"TabsCountRestricted");
                                [alert show];
                                return NO;
                            }
                            [current addObject:tabId];
                            [[YTLUserDefaults standardUserDefaults] setActiveTabs:current];
                            [[[%c(YTHeaderContentComboViewController) alloc] init] refreshPivotBar];
                            [(UINavigationController *)settingsViewController.navigationController popViewControllerAnimated:YES];
                            return YES;
                        }];

                        NSNumber *iconType = tabIconTypes[tabId];
                        if (iconType) {
                            YTIIcon *icon = [%c(YTIIcon) new];
                            icon.iconType = [iconType intValue];
                            item.settingIcon = icon;
                        }
                        [tabRows addObject:item];
                    }

                    [tabRows addObject:[%c(YTSettingsSectionItem) itemWithTitle:nil titleDescription:LOC(@"HideLibraryFooter") accessibilityIdentifier:@"YTLiteSectionItem" detailTextBlock:nil selectBlock:nil]];

                    YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Tabbar") pickerSectionTitle:nil rows:tabRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                    [settingsViewController pushViewController:picker];
                    return YES;
                }]];

            [rows addObject:[self startupTabItemWithSettingsVC:settingsViewController]];

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Interface") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:interface];

    YTSettingsSectionItem *appearance = [self pageItemWithTitle:@"Themes"
        titleDescription:@"Curated themes, custom colors, gradients, and polish."
        summary:^NSString *() {
            return [self themeAppearanceSummary];
        }
        selectBlock:^BOOL (YTSettingsCell *innerCell, NSUInteger innerArg1) {
            NSMutableArray <YTSettingsSectionItem *> *appearanceRows = [NSMutableArray array];
            [appearanceRows addObject:[self themeSectionHeaderWithTitle:@"Theme Studio" description:@"Start with a full preset, then fine-tune colors only if you want something personal."]];

            [appearanceRows addObject:[self pageItemWithTitle:LOC(@"Presets")
                titleDescription:@"Complete looks for the whole app, grouped into dark and light palettes."
                summary:^NSString *() {
                    return @"11 curated";
                }
                selectBlock:^BOOL(YTSettingsCell *presetCell, NSUInteger presetArg1) {
                    NSMutableArray <YTSettingsSectionItem *> *presetRows = [NSMutableArray array];
                    [presetRows addObject:[self themeSectionHeaderWithTitle:@"Dark Themes" description:@"Richer palettes with more contrast and depth."]];
                    [self themeAddPresetRowWithName:@"OLED Dark" titleDescription:@"Pure black with sharp red accents." overlay:[UIColor whiteColor] tabIcons:[UIColor whiteColor] seekBar:[UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:1.0] bg:[UIColor blackColor] textP:[UIColor whiteColor] textS:[UIColor colorWithRed:0.65 green:0.65 blue:0.65 alpha:1.0] nav:[UIColor blackColor] accent:[UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:1.0] toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Midnight Blue" titleDescription:@"Cool navy with bright blue controls." overlay:[UIColor colorWithRed:0.6 green:0.8 blue:1.0 alpha:1.0] tabIcons:[UIColor colorWithRed:0.4 green:0.7 blue:1.0 alpha:1.0] seekBar:[UIColor colorWithRed:0.2 green:0.5 blue:1.0 alpha:1.0] bg:[UIColor colorWithRed:0.05 green:0.05 blue:0.15 alpha:1.0] textP:[UIColor colorWithRed:0.85 green:0.9 blue:1.0 alpha:1.0] textS:[UIColor colorWithRed:0.5 green:0.6 blue:0.75 alpha:1.0] nav:[UIColor colorWithRed:0.08 green:0.08 blue:0.2 alpha:1.0] accent:[UIColor colorWithRed:0.2 green:0.5 blue:1.0 alpha:1.0] toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Solarized Dark" titleDescription:@"Muted solarized tones with teal and gold." overlay:[UIColor colorWithRed:0.51 green:0.58 blue:0.59 alpha:1.0] tabIcons:[UIColor colorWithRed:0.51 green:0.58 blue:0.59 alpha:1.0] seekBar:[UIColor colorWithRed:0.52 green:0.60 blue:0.0 alpha:1.0] bg:[UIColor colorWithRed:0.0 green:0.17 blue:0.21 alpha:1.0] textP:[UIColor colorWithRed:0.93 green:0.91 blue:0.84 alpha:1.0] textS:[UIColor colorWithRed:0.51 green:0.58 blue:0.59 alpha:1.0] nav:[UIColor colorWithRed:0.03 green:0.21 blue:0.26 alpha:1.0] accent:[UIColor colorWithRed:0.15 green:0.55 blue:0.82 alpha:1.0] toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Monokai" titleDescription:@"High-contrast editor greens and pinks." overlay:[UIColor colorWithRed:0.97 green:0.97 blue:0.95 alpha:1.0] tabIcons:[UIColor colorWithRed:0.65 green:0.89 blue:0.18 alpha:1.0] seekBar:[UIColor colorWithRed:0.98 green:0.15 blue:0.45 alpha:1.0] bg:[UIColor colorWithRed:0.15 green:0.16 blue:0.13 alpha:1.0] textP:[UIColor colorWithRed:0.97 green:0.97 blue:0.95 alpha:1.0] textS:[UIColor colorWithRed:0.46 green:0.44 blue:0.37 alpha:1.0] nav:[UIColor colorWithRed:0.2 green:0.2 blue:0.17 alpha:1.0] accent:[UIColor colorWithRed:0.40 green:0.85 blue:0.94 alpha:1.0] toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Forest" titleDescription:@"Deep green with a calm natural feel." overlay:[UIColor colorWithRed:0.8 green:0.93 blue:0.8 alpha:1.0] tabIcons:[UIColor colorWithRed:0.4 green:0.75 blue:0.4 alpha:1.0] seekBar:[UIColor colorWithRed:0.3 green:0.7 blue:0.3 alpha:1.0] bg:[UIColor colorWithRed:0.06 green:0.1 blue:0.06 alpha:1.0] textP:[UIColor colorWithRed:0.85 green:0.95 blue:0.85 alpha:1.0] textS:[UIColor colorWithRed:0.5 green:0.65 blue:0.5 alpha:1.0] nav:[UIColor colorWithRed:0.08 green:0.14 blue:0.08 alpha:1.0] accent:[UIColor colorWithRed:0.3 green:0.7 blue:0.3 alpha:1.0] toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Afterglow" titleDescription:@"The signature dark magenta palette." overlay:[UIColor colorWithRed:1.0 green:0.55 blue:0.65 alpha:1.0] tabIcons:[UIColor colorWithRed:0.95 green:0.45 blue:0.55 alpha:1.0] seekBar:[UIColor colorWithRed:1.0 green:0.4 blue:0.5 alpha:1.0] bg:[UIColor colorWithRed:0.1 green:0.05 blue:0.18 alpha:1.0] textP:[UIColor colorWithRed:1.0 green:0.9 blue:0.92 alpha:1.0] textS:[UIColor colorWithRed:0.65 green:0.5 blue:0.7 alpha:1.0] nav:[UIColor colorWithRed:0.12 green:0.07 blue:0.22 alpha:1.0] accent:[UIColor colorWithRed:0.95 green:0.4 blue:0.5 alpha:1.0] toRows:presetRows settingsVC:settingsViewController];
                    [presetRows addObject:space];
                    [presetRows addObject:[self themeSectionHeaderWithTitle:@"Light Themes" description:@"Brighter looks that still feel deliberate and themed."]];
                    [self themeAddPresetRowWithName:@"Clean White" titleDescription:@"Minimal white surfaces with blue accents." overlay:[UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1.0] tabIcons:[UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:1.0] seekBar:[UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0] bg:[UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:1.0] textP:[UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:1.0] textS:[UIColor colorWithRed:0.45 green:0.45 blue:0.45 alpha:1.0] nav:[UIColor colorWithRed:0.97 green:0.97 blue:0.97 alpha:1.0] accent:[UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0] toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Warm Sand" titleDescription:@"Cream tones with soft amber highlights." overlay:[UIColor colorWithRed:0.45 green:0.35 blue:0.25 alpha:1.0] tabIcons:[UIColor colorWithRed:0.5 green:0.38 blue:0.25 alpha:1.0] seekBar:[UIColor colorWithRed:0.85 green:0.55 blue:0.2 alpha:1.0] bg:[UIColor colorWithRed:0.98 green:0.96 blue:0.91 alpha:1.0] textP:[UIColor colorWithRed:0.2 green:0.15 blue:0.1 alpha:1.0] textS:[UIColor colorWithRed:0.5 green:0.42 blue:0.35 alpha:1.0] nav:[UIColor colorWithRed:0.95 green:0.92 blue:0.85 alpha:1.0] accent:[UIColor colorWithRed:0.85 green:0.55 blue:0.2 alpha:1.0] toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Ocean Breeze" titleDescription:@"Light blue surfaces with teal energy." overlay:[UIColor colorWithRed:0.15 green:0.4 blue:0.55 alpha:1.0] tabIcons:[UIColor colorWithRed:0.1 green:0.45 blue:0.6 alpha:1.0] seekBar:[UIColor colorWithRed:0.0 green:0.6 blue:0.7 alpha:1.0] bg:[UIColor colorWithRed:0.94 green:0.97 blue:1.0 alpha:1.0] textP:[UIColor colorWithRed:0.1 green:0.15 blue:0.2 alpha:1.0] textS:[UIColor colorWithRed:0.35 green:0.45 blue:0.55 alpha:1.0] nav:[UIColor colorWithRed:0.9 green:0.94 blue:0.98 alpha:1.0] accent:[UIColor colorWithRed:0.0 green:0.55 blue:0.65 alpha:1.0] toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Rose Gold" titleDescription:@"Soft blush tones with warm chrome." overlay:[UIColor colorWithRed:0.6 green:0.35 blue:0.35 alpha:1.0] tabIcons:[UIColor colorWithRed:0.7 green:0.4 blue:0.4 alpha:1.0] seekBar:[UIColor colorWithRed:0.85 green:0.45 blue:0.5 alpha:1.0] bg:[UIColor colorWithRed:1.0 green:0.95 blue:0.93 alpha:1.0] textP:[UIColor colorWithRed:0.25 green:0.15 blue:0.15 alpha:1.0] textS:[UIColor colorWithRed:0.55 green:0.4 blue:0.4 alpha:1.0] nav:[UIColor colorWithRed:0.95 green:0.88 blue:0.86 alpha:1.0] accent:[UIColor colorWithRed:0.85 green:0.45 blue:0.5 alpha:1.0] toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Afterglow Light" titleDescription:@"Afterglow translated into daylight." overlay:[UIColor colorWithRed:0.75 green:0.3 blue:0.45 alpha:1.0] tabIcons:[UIColor colorWithRed:0.7 green:0.3 blue:0.5 alpha:1.0] seekBar:[UIColor colorWithRed:0.95 green:0.35 blue:0.45 alpha:1.0] bg:[UIColor colorWithRed:1.0 green:0.95 blue:0.96 alpha:1.0] textP:[UIColor colorWithRed:0.2 green:0.08 blue:0.15 alpha:1.0] textS:[UIColor colorWithRed:0.5 green:0.32 blue:0.45 alpha:1.0] nav:[UIColor colorWithRed:0.97 green:0.9 blue:0.93 alpha:1.0] accent:[UIColor colorWithRed:0.85 green:0.3 blue:0.45 alpha:1.0] toRows:presetRows settingsVC:settingsViewController];

                    YTSettingsPickerViewController *presetPicker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Presets") pickerSectionTitle:nil rows:presetRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                    [settingsViewController pushViewController:presetPicker];
                    return YES;
                }]];

            [appearanceRows addObject:[self pageItemWithTitle:LOC(@"CustomColors")
                titleDescription:@"Fine-tune the exact surfaces and text colors the theme engine touches."
                summary:^NSString *() {
                    return [self themeCustomColorsSummary];
                }
                selectBlock:^BOOL(YTSettingsCell *colorCell, NSUInteger colorArg1) {
                    NSMutableArray <YTSettingsSectionItem *> *colorRows = [NSMutableArray array];
                    [colorRows addObject:[self themeSectionHeaderWithTitle:@"Background & Chrome" description:@"Surfaces, tab icons, navigation, overlay controls, and the seek bar."]];
                    [self themeAddColorRowWithTitle:@"Background" titleDescription:@"Main app surfaces and cards." themeKey:@"theme_background" toRows:colorRows settingsVC:settingsViewController];
                    [self themeAddColorRowWithTitle:@"NavigationBar" titleDescription:@"Top navigation and header chrome." themeKey:@"theme_navBar" toRows:colorRows settingsVC:settingsViewController];
                    [self themeAddColorRowWithTitle:@"TabBarIcons" titleDescription:@"Pivot tab icons and selected tab tint." themeKey:@"theme_tabBarIcons" toRows:colorRows settingsVC:settingsViewController];
                    [self themeAddColorRowWithTitle:@"OverlayButtons" titleDescription:@"On-video action buttons and player controls." themeKey:@"theme_overlayButtons" toRows:colorRows settingsVC:settingsViewController];
                    [self themeAddColorRowWithTitle:@"SeekBar" titleDescription:@"Played and buffered progress color." themeKey:@"theme_seekBar" toRows:colorRows settingsVC:settingsViewController];
                    [colorRows addObject:space];
                    [colorRows addObject:[self themeSectionHeaderWithTitle:@"Text & Accent" description:@"Titles, supporting copy, links, and primary action color."]];
                    [self themeAddColorRowWithTitle:@"PrimaryText" titleDescription:@"Main titles and prominent labels." themeKey:@"theme_textPrimary" toRows:colorRows settingsVC:settingsViewController];
                    [self themeAddColorRowWithTitle:@"SecondaryText" titleDescription:@"Supporting text and muted labels." themeKey:@"theme_textSecondary" toRows:colorRows settingsVC:settingsViewController];
                    [self themeAddColorRowWithTitle:@"AccentColor" titleDescription:@"Highlights, links, and action color." themeKey:@"theme_accent" toRows:colorRows settingsVC:settingsViewController];

                    YTSettingsPickerViewController *colorPicker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"CustomColors") pickerSectionTitle:nil rows:colorRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                    [settingsViewController pushViewController:colorPicker];
                    return YES;
                }]];

            [appearanceRows addObject:[self pageItemWithTitle:LOC(@"Gradient")
                titleDescription:@"Optional background wash with a dedicated on or off workflow."
                summary:^NSString *() {
                    return [self themeGradientSummary];
                }
                selectBlock:^BOOL(YTSettingsCell *gradientCell, NSUInteger gradientArg1) {
                    NSMutableArray <YTSettingsSectionItem *> *gradientRows = [NSMutableArray array];
                    [gradientRows addObject:[self themeSectionHeaderWithTitle:@"Gradient Status" description:@"Both colors must be set for the background gradient to appear everywhere."]];
                    [self themeAddColorRowWithTitle:@"GradientStart" titleDescription:@"Start of the background gradient." themeKey:@"theme_gradientStart" toRows:gradientRows settingsVC:settingsViewController];
                    [self themeAddColorRowWithTitle:@"GradientEnd" titleDescription:@"End of the background gradient." themeKey:@"theme_gradientEnd" toRows:gradientRows settingsVC:settingsViewController];
                    if ([[YTLUserDefaults standardUserDefaults] objectForKey:@"theme_gradientStart"] || [[YTLUserDefaults standardUserDefaults] objectForKey:@"theme_gradientEnd"]) {
                        [gradientRows addObject:space];
                        [gradientRows addObject:[%c(YTSettingsSectionItem) itemWithTitle:@"Turn Off Gradient"
                            titleDescription:@"Remove both gradient colors and go back to a flat background."
                            accessibilityIdentifier:@"YTLiteSectionItem"
                            detailTextBlock:^NSString *() {
                                return [self themeGradientSummary];
                            }
                            selectBlock:^BOOL(YTSettingsCell *resetCell, NSUInteger resetArg1) {
                                [[YTLUserDefaults standardUserDefaults] removeObjectForKey:@"theme_gradientStart"];
                                [[YTLUserDefaults standardUserDefaults] removeObjectForKey:@"theme_gradientEnd"];
                                ytl_clearThemeCache();
                                [settingsViewController reloadData];
                                [(UINavigationController *)settingsViewController.navigationController popViewControllerAnimated:YES];
                                return YES;
                            }]];
                    }

                    YTSettingsPickerViewController *gradientPicker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Gradient") pickerSectionTitle:nil rows:gradientRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                    [settingsViewController pushViewController:gradientPicker];
                    return YES;
                }]];

            [appearanceRows addObject:space];
            [appearanceRows addObject:[self themeSectionHeaderWithTitle:@"Reset" description:@"If the look gets messy, clear Themes without touching the rest of the tweak."]];
            [appearanceRows addObject:[%c(YTSettingsSectionItem) itemWithTitle:LOC(@"ResetAllColors")
                titleDescription:@"Clear every theme override and go back to stock colors."
                accessibilityIdentifier:@"YTLiteSectionItem"
                detailTextBlock:^NSString *() {
                    return @"Restart required";
                }
                selectBlock:^BOOL(YTSettingsCell *resetCell, NSUInteger resetArg1) {
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:LOC(@"ResetAllColors") message:@"This removes every preset, custom color, and gradient value in Themes. Restart YouTube to fully return to the default look." preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:LOC(@"ResetAndRestart") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
                        NSArray *keys = @[@"theme_overlayButtons", @"theme_tabBarIcons", @"theme_seekBar", @"theme_background", @"theme_textPrimary", @"theme_textSecondary", @"theme_navBar", @"theme_accent", @"theme_gradientStart", @"theme_gradientEnd"];
                        for (NSString *key in keys) {
                            [[YTLUserDefaults standardUserDefaults] removeObjectForKey:key];
                        }
                        ytl_clearThemeCache();
                        exit(0);
                    }]];
                    [alert addAction:[UIAlertAction actionWithTitle:LOC(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
                    [settingsViewController presentViewController:alert animated:YES completion:nil];
                    return YES;
                }]];

            YTSettingsPickerViewController *pickerVC = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:@"Themes" pickerSectionTitle:nil rows:appearanceRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:pickerVC];
            return YES;
        }];
    [sectionItems addObject:appearance];

    YTSettingsSectionItem *player = [self pageItemWithTitle:LOC(@"Player")
        titleDescription:@"Playback controls, defaults, quality, and on-video UI."
        summary:^NSString *() {
            return [self enabledSummaryForKeys:playerKeys];
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray <YTSettingsSectionItem *> *rows = [NSMutableArray array];

            [rows addObject:[self pageItemWithTitle:@"Playback"
                titleDescription:@"Background playback, default speed, and preferred quality."
                summary:^NSString *() {
                    return @"5 options";
                }
                selectBlock:^BOOL (YTSettingsCell *defaultsCell, NSUInteger defaultsArg1) {
                    NSArray <YTSettingsSectionItem *> *defaultRows = @[
                        [self switchWithTitle:@"BackgroundPlayback" key:@"backgroundPlayback"],
                        [self holdToSpeedItemWithSettingsVC:settingsViewController],
                        [self defaultPlaybackRateItemWithSettingsVC:settingsViewController],
                        [self playbackQualityItemWithTitle:@"PlaybackQualityOnWiFi" key:@"wiFiQualityIndex" settingsVC:settingsViewController],
                        [self playbackQualityItemWithTitle:@"PlaybackQualityOnCellular" key:@"cellQualityIndex" settingsVC:settingsViewController]
                    ];

                    YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Playback") pickerSectionTitle:nil rows:defaultRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                    [settingsViewController pushViewController:picker];
                    return YES;
                }]];

            [rows addObject:[self pageItemWithTitle:@"Controls"
                titleDescription:@"Gestures, fullscreen behavior, captions, and player buttons."
                summary:^NSString *() {
                    return [self enabledSummaryForKeys:playerKeys];
                }
                selectBlock:^BOOL (YTSettingsCell *controlsCell, NSUInteger controlsArg1) {
                    NSArray <YTSettingsSectionItem *> *controlRows = @[
                        [self switchWithTitle:@"Miniplayer" key:@"miniplayer"],
                        [self switchWithTitle:@"PortraitFullscreen" key:@"portraitFullscreen"],
                        [self switchWithTitle:@"CopyWithTimestamp" key:@"copyWithTimestamp"],
                        [self switchWithTitle:@"DisableAutoplay" key:@"disableAutoplay"],
                        [self switchWithTitle:@"DisableAutoCaptions" key:@"disableAutoCaptions"],
                        [self switchWithTitle:@"NoContentWarning" key:@"noContentWarning"],
                        [self switchWithTitle:@"ClassicQuality" key:@"classicQuality"],
                        [self switchWithTitle:@"ExtraSpeedOptions" key:@"extraSpeedOptions"],
                        [self switchWithTitle:@"DontSnap2Chapter" key:@"dontSnapToChapter"],
                        [self switchWithTitle:@"NoTwoFingerSnapToChapter" key:@"noTwoFingerSnapToChapter"],
                        [self switchWithTitle:@"PauseOnOverlay" key:@"pauseOnOverlay"],
                        [self switchWithTitle:@"RedProgressBar" key:@"redProgressBar"],
                        [self switchWithTitle:@"NoPlayerRemixButton" key:@"noPlayerRemixButton"],
                        [self switchWithTitle:@"NoPlayerClipButton" key:@"noPlayerClipButton"],
                        [self switchWithTitle:@"NoHints" key:@"noHints"],
                        [self switchWithTitle:@"NoFreeZoom" key:@"noFreeZoom"],
                        [self switchWithTitle:@"AutoFullscreen" key:@"autoFullscreen"],
                        [self switchWithTitle:@"ExitFullscreen" key:@"exitFullscreen"],
                        [self switchWithTitle:@"NoDoubleTap2Seek" key:@"noDoubleTapToSeek"]
                    ];

                    YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Controls") pickerSectionTitle:nil rows:controlRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                    [settingsViewController pushViewController:picker];
                    return YES;
                }]];

            if (isAdvanced) {
                [rows addObject:[self pageItemWithTitle:LOC(@"Overlay")
                    titleDescription:@"HUD, autoplay, end-screen cards, and player chrome."
                    summary:^NSString *() {
                        return [self enabledSummaryForKeys:overlayKeys];
                    }
                    selectBlock:^BOOL (YTSettingsCell *overlayCell, NSUInteger overlayArg1) {
                        NSArray <YTSettingsSectionItem *> *overlayRows = @[
                            [self switchWithTitle:@"HideAutoplay" key:@"hideAutoplay"],
                            [self switchWithTitle:@"HideSubs" key:@"hideSubs"],
                            [self switchWithTitle:@"NoHUDMsgs" key:@"noHUDMsgs"],
                            [self switchWithTitle:@"HidePrevNext" key:@"hidePrevNext"],
                            [self switchWithTitle:@"ReplacePrevNext" key:@"replacePrevNext"],
                            [self switchWithTitle:@"NoDarkBg" key:@"noDarkBg"],
                            [self switchWithTitle:@"NoEndScreenCards" key:@"endScreenCards"],
                            [self switchWithTitle:@"NoFullscreenActions" key:@"noFullscreenActions"],
                            [self switchWithTitle:@"PersistentProgressBar" key:@"persistentProgressBar"],
                            [self switchWithTitle:@"StockVolumeHUD" key:@"stockVolumeHUD"],
                            [self switchWithTitle:@"NoRelatedVids" key:@"noRelatedVids"],
                            [self switchWithTitle:@"NoWatermarks" key:@"noWatermarks"],
                            [self switchWithTitle:@"VideoEndTime" key:@"videoEndTime"],
                            [self switchWithTitle:@"24hrFormat" key:@"24hrFormat"]
                        ];

                        YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Overlay") pickerSectionTitle:nil rows:overlayRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                        [settingsViewController pushViewController:picker];
                        return YES;
                    }]];
            }

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Player") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:player];

    YTSettingsSectionItem *shorts = [self pageItemWithTitle:LOC(@"Shorts")
        titleDescription:@"Behavior, conversion, and optional UI cleanup for Shorts."
        summary:^NSString *() {
            return [self enabledSummaryForKeys:[shortsBehaviorKeys arrayByAddingObjectsFromArray:shortsUIKeys]];
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray <YTSettingsSectionItem *> *rows = [NSMutableArray array];

            [rows addObject:[self pageItemWithTitle:@"Behavior"
                titleDescription:@"Open, skip, resume, or convert Shorts."
                summary:^NSString *() {
                    return [self enabledSummaryForKeys:shortsBehaviorKeys];
                }
                selectBlock:^BOOL (YTSettingsCell *behaviorCell, NSUInteger behaviorArg1) {
                    NSArray <YTSettingsSectionItem *> *behaviorRows = @[
                        [self switchWithTitle:@"ShortsOnlyMode" key:@"shortsOnlyMode"],
                        [self switchWithTitle:@"AutoSkipShorts" key:@"autoSkipShorts"],
                        [self switchWithTitle:@"HideShorts" key:@"hideShorts"],
                        [self switchWithTitle:@"ShortsProgress" key:@"shortsProgress"],
                        [self switchWithTitle:@"PinchToFullscreenShorts" key:@"pinchToFullscreenShorts"],
                        [self switchWithTitle:@"ShortsToRegular" key:@"shortsToRegular"],
                        [self switchWithTitle:@"ResumeShorts" key:@"resumeShorts"]
                    ];

                    YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:@"Shorts Behavior" pickerSectionTitle:nil rows:behaviorRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                    [settingsViewController pushViewController:picker];
                    return YES;
                }]];

            if (isAdvanced) {
                [rows addObject:[self pageItemWithTitle:@"Layout & Buttons"
                    titleDescription:@"Hide specific Shorts UI elements and action buttons."
                    summary:^NSString *() {
                        return [self enabledSummaryForKeys:shortsUIKeys];
                    }
                    selectBlock:^BOOL (YTSettingsCell *uiCell, NSUInteger uiArg1) {
                        NSArray <YTSettingsSectionItem *> *uiRows = @[
                            [self switchWithTitle:@"HideShortsLogo" key:@"hideShortsLogo"],
                            [self switchWithTitle:@"HideShortsSearch" key:@"hideShortsSearch"],
                            [self switchWithTitle:@"HideShortsCamera" key:@"hideShortsCamera"],
                            [self switchWithTitle:@"HideShortsMore" key:@"hideShortsMore"],
                            [self switchWithTitle:@"HideShortsSubscriptions" key:@"hideShortsSubscriptions"],
                            [self switchWithTitle:@"HideShortsLike" key:@"hideShortsLike"],
                            [self switchWithTitle:@"HideShortsDislike" key:@"hideShortsDislike"],
                            [self switchWithTitle:@"HideShortsComments" key:@"hideShortsComments"],
                            [self switchWithTitle:@"HideShortsRemix" key:@"hideShortsRemix"],
                            [self switchWithTitle:@"HideShortsShare" key:@"hideShortsShare"],
                            [self switchWithTitle:@"HideShortsAvatars" key:@"hideShortsAvatars"],
                            [self switchWithTitle:@"HideShortsThanks" key:@"hideShortsThanks"],
                            [self switchWithTitle:@"HideShortsSource" key:@"hideShortsSource"],
                            [self switchWithTitle:@"HideShortsChannelName" key:@"hideShortsChannelName"],
                            [self switchWithTitle:@"HideShortsDescription" key:@"hideShortsDescription"],
                            [self switchWithTitle:@"HideShortsAudioTrack" key:@"hideShortsAudioTrack"],
                            [self switchWithTitle:@"NoPromotionCards" key:@"hideShortsPromoCards"]
                        ];

                        YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:@"Shorts Layout" pickerSectionTitle:nil rows:uiRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                        [settingsViewController pushViewController:picker];
                        return YES;
                    }]];
            }

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Shorts") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:shorts];

    YTSettingsSectionItem *downloads = [self pageItemWithTitle:LOC(@"Downloads")
        titleDescription:@"Download surfaces, sharing, and export tools."
        summary:^NSString *() {
            return [self enabledSummaryForKeys:downloadKeys];
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray <YTSettingsSectionItem *> *rows = [NSMutableArray array];
            [rows addObject:[self themeSectionHeaderWithTitle:@"Download UI" description:@"Hide the download and share entry points when you do not want them."]];
            [rows addObject:[self switchWithTitle:@"RemoveDownloadMenu" key:@"removeDownloadMenu"]];
            [rows addObject:[self switchWithTitle:@"NoPlayerDownloadButton" key:@"noPlayerDownloadButton"]];
            [rows addObject:[self switchWithTitle:@"RemoveShareMenu" key:@"removeShareMenu"]];
            [rows addObject:space];
            [rows addObject:[self themeSectionHeaderWithTitle:@"Save & Share" description:@"Copy, save, and replace content export actions."]];
            [rows addObject:[self switchWithTitle:@"CopyVideoInfo" key:@"copyVideoInfo"]];
            [rows addObject:[self switchWithTitle:@"PostManager" key:@"postManager"]];
            [rows addObject:[self switchWithTitle:@"SaveProfilePhoto" key:@"saveProfilePhoto"]];
            [rows addObject:[self switchWithTitle:@"CommentManager" key:@"commentManager"]];
            [rows addObject:[self switchWithTitle:@"FixAlbums" key:@"fixAlbums"]];
            [rows addObject:[self switchWithTitle:@"NativeShare" key:@"nativeShare"]];

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Downloads") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:downloads];

    YTSettingsSectionItem *feed = [self pageItemWithTitle:LOC(@"Feed")
        titleDescription:@"Home surfaces, menus, comments, and browse cleanup."
        summary:^NSString *() {
            NSArray *feedContentKeys = [[feedKeys arrayByAddingObjectsFromArray:menuKeys] arrayByAddingObjectsFromArray:commentKeys];
            return [self enabledSummaryForKeys:feedContentKeys];
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray <YTSettingsSectionItem *> *rows = [NSMutableArray array];

            [rows addObject:[self pageItemWithTitle:@"Home"
                titleDescription:@"Reduce interruptions and noisy feed behavior."
                summary:^NSString *() {
                    return [self enabledSummaryForKeys:feedKeys];
                }
                selectBlock:^BOOL (YTSettingsCell *feedCell, NSUInteger feedArg1) {
                    NSArray <YTSettingsSectionItem *> *feedRows = @[
                        [self switchWithTitle:@"NoContinueWatching" key:@"noContinueWatching"],
                        [self switchWithTitle:@"NoSearchHistory" key:@"noSearchHistory"],
                        [self switchWithTitle:@"NoRelatedWatchNexts" key:@"noRelatedWatchNexts"]
                    ];

                    YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:@"Home" pickerSectionTitle:nil rows:feedRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                    [settingsViewController pushViewController:picker];
                    return YES;
                }]];

            [rows addObject:[self pageItemWithTitle:@"Menus"
                titleDescription:@"Trim actions you never use from long-press and overflow menus."
                summary:^NSString *() {
                    return [self enabledSummaryForKeys:menuKeys];
                }
                selectBlock:^BOOL (YTSettingsCell *menuCell, NSUInteger menuArg1) {
                    NSArray <YTSettingsSectionItem *> *menuRows = @[
                        [self switchWithTitle:@"RemovePlayNext" key:@"removePlayNext"],
                        [self switchWithTitle:@"RemoveWatchLaterMenu" key:@"removeWatchLaterMenu"],
                        [self switchWithTitle:@"RemoveSaveToPlaylistMenu" key:@"removeSaveToPlaylistMenu"],
                        [self switchWithTitle:@"RemoveNotInterestedMenu" key:@"removeNotInterestedMenu"],
                        [self switchWithTitle:@"RemoveDontRecommendMenu" key:@"removeDontRecommendMenu"],
                        [self switchWithTitle:@"RemoveReportMenu" key:@"removeReportMenu"]
                    ];

                    YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:@"Menus" pickerSectionTitle:nil rows:menuRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                    [settingsViewController pushViewController:picker];
                    return YES;
                }]];

            if (isAdvanced) {
                [rows addObject:[self pageItemWithTitle:@"Comments"
                    titleDescription:@"Comment sorting, playlist behavior, and RTL direction."
                    summary:^NSString *() {
                        return [self enabledSummaryForKeys:commentKeys];
                    }
                    selectBlock:^BOOL (YTSettingsCell *commentCell, NSUInteger commentArg1) {
                        NSArray <YTSettingsSectionItem *> *commentRows = @[
                            [self switchWithTitle:@"StickSortComments" key:@"stickSortComments"],
                            [self switchWithTitle:@"HideSortComments" key:@"hideSortComments"],
                            [self switchWithTitle:@"PlaylistOldMinibar" key:@"playlistOldMinibar"],
                            [self switchWithTitle:@"DisableRTL" key:@"disableRTL"]
                        ];

                        YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:@"Comments" pickerSectionTitle:nil rows:commentRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                        [settingsViewController pushViewController:picker];
                        return YES;
                    }]];
            }

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Feed") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:feed];

    YTSettingsSectionItem *support = [%c(YTSettingsSectionItem) itemWithTitle:LOC(@"SupportDevelopment") accessibilityIdentifier:@"YTLiteSectionItem" detailTextBlock:^NSString *() { return @"♡"; } selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
        YTDefaultSheetController *sheetController = [%c(YTDefaultSheetController) sheetControllerWithMessage:LOC(@"SupportDevelopment") subMessage:LOC(@"SupportDevelopmentDesc") delegate:nil parentResponder:nil];
        YTActionSheetHeaderView *headerView = [sheetController valueForKey:@"_headerView"];
        YTFormattedStringLabel *subtitle = [headerView valueForKey:@"_subtitleLabel"];
        subtitle.numberOfLines = 0;
        [headerView showHeaderDivider];

        [sheetController addAction:[%c(YTActionSheetAction) actionWithTitle:@"PayPal" iconImage:[self resizedImageNamed:@"paypal"] secondaryIconImage:nil accessibilityIdentifier:nil handler:^ {
            [%c(YTUIUtils) openURL:[NSURL URLWithString:@"https://paypal.me/dayanch96"]];
        }]];

        [sheetController addAction:[%c(YTActionSheetAction) actionWithTitle:@"Github Sponsors" iconImage:[self resizedImageNamed:@"github"] secondaryIconImage:nil accessibilityIdentifier:nil handler:^ {
            [%c(YTUIUtils) openURL:[NSURL URLWithString:@"https://github.com/sponsors/dayanch96"]];
        }]];

        [sheetController addAction:[%c(YTActionSheetAction) actionWithTitle:@"Buy Me a Coffee" iconImage:[self resizedImageNamed:@"coffee"] secondaryIconImage:nil accessibilityIdentifier:nil handler:^ {
            [%c(YTUIUtils) openURL:[NSURL URLWithString:@"https://www.buymeacoffee.com/dayanch96"]];
        }]];

        [sheetController addAction:[%c(YTActionSheetAction) actionWithTitle:@"USDT (TRC20)" iconImage:[self resizedImageNamed:@"usdt"] secondaryIconImage:nil accessibilityIdentifier:nil handler:^ {
            [UIPasteboard generalPasteboard].string = @"TEdKJdKwc1Bbu8Py4um8qPQ6MbproEqNJw";
            [[%c(YTToastResponderEvent) eventWithMessage:LOC(@"Copied") firstResponder:[self parentResponder]] send];
        }]];

        [sheetController addAction:[%c(YTActionSheetAction) actionWithTitle:@"BNB Smart Chain (BEP20)" iconImage:[self resizedImageNamed:@"bnb"] secondaryIconImage:nil accessibilityIdentifier:nil handler:^ {
            [UIPasteboard generalPasteboard].string = @"0xc6f9fddb30ce10d70e6497950f44c8e10b72bcd6";
            [[%c(YTToastResponderEvent) eventWithMessage:LOC(@"Copied") firstResponder:[self parentResponder]] send];
        }]];

        [sheetController addAction:[%c(YTActionSheetAction) actionWithTitle:@"Boosty" iconImage:[self resizedImageNamed:@"boosty"] secondaryIconImage:nil accessibilityIdentifier:nil handler:^ {
            [%c(YTUIUtils) openURL:[NSURL URLWithString:@"https://boosty.to/dayanch96"]];
        }]];

        [sheetController presentFromViewController:[%c(YTUIUtils) topViewControllerForPresenting] animated:YES completion:nil];

        return YES;
    }];

    YTSettingsSectionItem *thanks = [self pageItemWithTitle:LOC(@"Contributors")
        titleDescription:@"People who built, translated, and improved the tweak."
        summary:^NSString *() {
            return @"9 people";
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
        NSArray <YTSettingsSectionItem *> *rows = @[
            [self linkWithTitle:@"Dayanch96" description:LOC(@"Developer") link:@"https://github.com/Dayanch96/"],
            [self linkWithTitle:@"Dan Pashin" description:LOC(@"SpecialThanks") link:@"https://github.com/danpashin/"],
            space,
            [self linkWithTitle:@"Stalker" description:LOC(@"ChineseSimplified") link:@"https://github.com/xiangfeidexiaohuo"],
            [self linkWithTitle:@"Clement" description:LOC(@"ChineseTraditional") link:@"https://twitter.com/a100900900"],
            [self linkWithTitle:@"Balackburn" description:LOC(@"French") link:@"https://github.com/Balackburn"],
            [self linkWithTitle:@"DeciBelioS" description:LOC(@"Spanish") link:@"https://github.com/Deci8BelioS"],
            [self linkWithTitle:@"SKEIDs" description:LOC(@"Japanese") link:@"https://github.com/SKEIDs"],
            [self linkWithTitle:@"Hiepvk" description:LOC(@"Vietnamese") link:@"https://github.com/hiepvk"]
        ];

        YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"About") pickerSectionTitle:LOC(@"Credits") rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
        [settingsViewController pushViewController:picker];
        return YES;
    }];

    YTSettingsSectionItem *sources = [self pageItemWithTitle:LOC(@"OpenSourceLibs")
        titleDescription:@"Core open-source projects this build depends on."
        summary:^NSString *() {
            return @"4 libs";
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
        NSArray <YTSettingsSectionItem *> *rows = @[
            [self linkWithTitle:@"PoomSmart" description:@"YouTube-X, YTNoPremium, YTClassicVideoQuality, YTShortsProgress, YTReExplore, SkipContentWarning, YTAutoFullscreen, YouTubeHeaders" link:@"https://github.com/PoomSmart/"],
            [self linkWithTitle:@"MiRO92" description:@"YTNoShorts" link:@"https://github.com/MiRO92/YTNoShorts"],
            [self linkWithTitle:@"Tony Million" description:@"Reachability" link:@"https://github.com/tonymillion/Reachability"],
            [self linkWithTitle:@"jkhsjdhjs" description:@"YouTube Native Share" link:@"https://github.com/jkhsjdhjs/youtube-native-share"]
        ];

        YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"About") pickerSectionTitle:LOC(@"Credits") rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
        [settingsViewController pushViewController:picker];
        return YES;
    }];

    YTSettingsSectionItem *about = [self pageItemWithTitle:LOC(@"About")
        titleDescription:@"Maintenance tools, advanced mode, credits, and support."
        summary:^NSString *() {
            return @(OS_STRINGIFY(TWEAK_VERSION));
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray <YTSettingsSectionItem *> *rows = [@[
                [self switchWithTitle:@"Advanced" key:@"advancedMode"],
                [%c(YTSettingsSectionItem) itemWithTitle:LOC(@"ClearCache") titleDescription:nil accessibilityIdentifier:@"YTLiteSectionItem" detailTextBlock:^NSString *() { return GetCacheSize(); } selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        NSString *cachePath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
                        [[NSFileManager defaultManager] removeItemAtPath:cachePath error:nil];
                    });

                    [[%c(YTToastResponderEvent) eventWithMessage:LOC(@"Done") firstResponder:[self parentResponder]] send];

                    return YES;
                }],

                [%c(YTSettingsSectionItem) itemWithTitle:LOC(@"ResetSettings") titleDescription:nil accessibilityIdentifier:@"YTLiteSectionItem" detailTextBlock:nil selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
                    YTAlertView *alertView = [%c(YTAlertView) confirmationDialogWithAction:^{
                        [YTLUserDefaults resetUserDefaults];

                        [[UIApplication sharedApplication] performSelector:@selector(suspend)];
                        [NSThread sleepForTimeInterval:1.0];
                        exit(0);
                    }
                    actionTitle:LOC(@"Yes")
                    cancelTitle:LOC(@"No")];
                    alertView.title = LOC(@"Warning");
                    alertView.subtitle = LOC(@"ResetMessage");
                    [alertView show];

                    return YES;
                }]
            ] mutableCopy];

            [rows addObject:space];
            [rows addObject:thanks];
            [rows addObject:sources];
            [rows addObject:support];

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"About") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:about];

    BOOL isNew = [settingsViewController respondsToSelector:@selector(setSectionItems:forCategory:title:icon:titleDescription:headerHidden:)];
    isNew ? [settingsViewController setSectionItems:sectionItems forCategory:YTLiteSection title:@"YouTube Afterglow" icon:nil titleDescription:nil headerHidden:NO]
          : [settingsViewController setSectionItems:sectionItems forCategory:YTLiteSection title:@"YouTube Afterglow" titleDescription:nil headerHidden:NO];

}

- (void)updateSectionForCategory:(NSUInteger)category withEntry:(id)entry {
    if (category == YTLiteSection) {
        [self updateYTLiteSectionWithEntry:entry];
        return;
    } %orig;
}

%new
- (UIImage *)resizedImageNamed:(NSString *)iconName {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(32, 32)];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
        UIView *imageView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 32, 32)];
        UIImageView *iconImageView = [[UIImageView alloc] initWithImage:[UIImage imageWithContentsOfFile:[NSBundle.ytl_defaultBundle pathForResource:iconName ofType:@"png"]]];
        iconImageView.contentMode = UIViewContentModeScaleAspectFit;
        iconImageView.clipsToBounds = YES;
        iconImageView.frame = imageView.bounds;

        [imageView addSubview:iconImageView];
        [imageView.layer renderInContext:rendererContext.CGContext];
    }];

    return image;
}
%end
