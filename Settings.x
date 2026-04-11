#import "YTLite.h"
#import <objc/runtime.h>

extern void ytl_clearThemeCache(void);

@interface YTSettingsSectionItemManager (YTLite)
- (void)updateYTLiteSectionWithEntry:(id)entry;
- (NSString *)themeHexFromColor:(UIColor *)color;
- (UIColor *)themeLoadColorForKey:(NSString *)key;
- (void)themePresentPickerForKey:(NSString *)themeKey startColor:(UIColor *)startColor settingsVC:(YTSettingsViewController *)settingsVC;
- (void)themeAddColorRowWithTitle:(NSString *)title themeKey:(NSString *)themeKey toRows:(NSMutableArray *)rows settingsVC:(YTSettingsViewController *)settingsVC;
- (void)themeSaveColor:(UIColor *)color forKey:(NSString *)key;
- (void)themeApplyPresetOverlay:(UIColor *)overlay tabIcons:(UIColor *)tabIcons seekBar:(UIColor *)seekBar bg:(UIColor *)bg textP:(UIColor *)textP textS:(UIColor *)textS nav:(UIColor *)nav accent:(UIColor *)accent;
- (void)themeAddPresetRowWithName:(NSString *)name overlay:(UIColor *)overlay tabIcons:(UIColor *)tabIcons seekBar:(UIColor *)seekBar bg:(UIColor *)bg textP:(UIColor *)textP textS:(UIColor *)textS nav:(UIColor *)nav accent:(UIColor *)accent toRows:(NSMutableArray *)rows settingsVC:(YTSettingsViewController *)settingsVC;
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
            UIAlertController *saved = [UIAlertController alertControllerWithTitle:LOC(@"ColorSaved")
                message:LOC(@"ColorSavedDesc")
                preferredStyle:UIAlertControllerStyleAlert];
            [saved addAction:[UIAlertAction actionWithTitle:LOC(@"RestartNow") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
                exit(0);
            }]];
            [saved addAction:[UIAlertAction actionWithTitle:LOC(@"Later") style:UIAlertActionStyleCancel handler:nil]];
            UIViewController *presenter = weakVC.navigationController.topViewController ?: weakVC;
            [presenter presentViewController:saved animated:YES completion:nil];
        }
    });
}
@end

#pragma clang diagnostic pop

static const NSInteger YTLiteSection = 789;
static YTLColorPickerDelegate *_colorPickerDelegate = nil;

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
        feedback.feedbackColor = [UIColor colorWithRed:0.75 green:0.50 blue:0.90 alpha:1.0];
        abcSwitch.onTintColor = [UIColor colorWithRed:0.75 green:0.50 blue:0.90 alpha:1.0];
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

#pragma mark - Theme Helpers

%new
- (NSString *)themeHexFromColor:(UIColor *)color {
    CGFloat r, g, b, a;
    [color getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"#%02X%02X%02X", (int)(r*255), (int)(g*255), (int)(b*255)];
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
- (void)themeAddColorRowWithTitle:(NSString *)title themeKey:(NSString *)themeKey toRows:(NSMutableArray *)rows settingsVC:(YTSettingsViewController *)settingsVC {
    Class YTSettingsSectionItemClass = %c(YTSettingsSectionItem);

    YTSettingsSectionItem *item = [YTSettingsSectionItemClass itemWithTitle:LOC(title)
        accessibilityIdentifier:nil
        detailTextBlock:^NSString *() {
            UIColor *c = [self themeLoadColorForKey:themeKey];
            return c ? [self themeHexFromColor:c] : LOC(@"Default");
        }
        selectBlock:^BOOL(YTSettingsCell *c, NSUInteger a) {
            [self themePresentPickerForKey:themeKey startColor:[self themeLoadColorForKey:themeKey] settingsVC:settingsVC];
            return YES;
        }];
    [rows addObject:item];

    if ([self themeLoadColorForKey:themeKey]) {
        YTSettingsSectionItem *reset = [YTSettingsSectionItemClass itemWithTitle:[NSString stringWithFormat:@"    %@ %@", @"\u21BA", LOC(title)]
            accessibilityIdentifier:nil
            detailTextBlock:nil
            selectBlock:^BOOL(YTSettingsCell *c, NSUInteger a) {
                [[YTLUserDefaults standardUserDefaults] removeObjectForKey:themeKey];
                ytl_clearThemeCache();
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
- (void)themeAddPresetRowWithName:(NSString *)name overlay:(UIColor *)overlay tabIcons:(UIColor *)tabIcons seekBar:(UIColor *)seekBar bg:(UIColor *)bg textP:(UIColor *)textP textS:(UIColor *)textS nav:(UIColor *)nav accent:(UIColor *)accent toRows:(NSMutableArray *)rows settingsVC:(YTSettingsViewController *)settingsVC {
    Class YTSettingsSectionItemClass = %c(YTSettingsSectionItem);

    YTSettingsSectionItem *item = [YTSettingsSectionItemClass itemWithTitle:name
        accessibilityIdentifier:nil
        detailTextBlock:nil
        selectBlock:^BOOL(YTSettingsCell *c, NSUInteger a) {
            [self themeApplyPresetOverlay:overlay tabIcons:tabIcons seekBar:seekBar bg:bg textP:textP textS:textS nav:nav accent:accent];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:LOC(@"PresetApplied")
                message:[NSString stringWithFormat:@"%@ %@", name, LOC(@"ColorSavedDesc")]
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:LOC(@"RestartNow") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { exit(0); }]];
            [alert addAction:[UIAlertAction actionWithTitle:LOC(@"Later") style:UIAlertActionStyleCancel handler:nil]];
            UIViewController *presenter = settingsVC.navigationController.topViewController ?: settingsVC;
            [presenter presentViewController:alert animated:YES completion:nil];
            return YES;
        }];
    [rows addObject:item];
}

#pragma mark - Settings Section

%new(v@:@)
- (void)updateYTLiteSectionWithEntry:(id)entry {
    NSMutableArray *sectionItems = [NSMutableArray array];
    Class YTSettingsSectionItemClass = %c(YTSettingsSectionItem);
    YTSettingsViewController *settingsViewController = [self valueForKey:@"_settingsViewControllerDelegate"];

    YTSettingsSectionItem *space = [%c(YTSettingsSectionItem) itemWithTitle:nil accessibilityIdentifier:@"YTLiteSectionItem" detailTextBlock:nil selectBlock:nil];

    YTSettingsSectionItem *general = [YTSettingsSectionItemClass itemWithTitle:LOC(@"General")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() {
            return @"\u2023";
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSArray <YTSettingsSectionItem *> *rows = @[
                [self switchWithTitle:@"RemoveAds" key:@"noAds"],
                [self switchWithTitle:@"BackgroundPlayback" key:@"backgroundPlayback"]
            ];

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"General") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];

    [sectionItems addObject:general];

    YTSettingsSectionItem *navbar = [YTSettingsSectionItemClass itemWithTitle:LOC(@"Navbar")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() {
            return @"\u2023";
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSArray <YTSettingsSectionItem *> *rows = @[
                [self switchWithTitle:@"RemoveCast" key:@"noCast"],
                [self switchWithTitle:@"RemoveNotifications" key:@"noNotifsButton"],
                [self switchWithTitle:@"RemoveSearch" key:@"noSearchButton"],
                [self switchWithTitle:@"RemoveVoiceSearch" key:@"noVoiceSearchButton"]
            ];

            if (ytlBool(@"advancedMode")) {
                rows = [rows arrayByAddingObjectsFromArray:@[
                    [self switchWithTitle:@"StickyNavbar" key:@"stickyNavbar"],
                    [self switchWithTitle:@"NoSubbar" key:@"noSubbar"],
                    [self switchWithTitle:@"NoYTLogo" key:@"noYTLogo"],
                    [self switchWithTitle:@"PremiumYTLogo" key:@"premiumYTLogo"]
                ]];
            }

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Navbar") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];

    [sectionItems addObject:navbar];

    // Appearance section — organized into sub-pages
    YTSettingsSectionItem *appearance = [YTSettingsSectionItemClass itemWithTitle:LOC(@"Appearance")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() {
            return @"\u2023";
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray <YTSettingsSectionItem *> *rows = [NSMutableArray array];

            // Theme Presets sub-page
            YTSettingsSectionItem *presetsPage = [YTSettingsSectionItemClass itemWithTitle:LOC(@"Presets")
                accessibilityIdentifier:nil
                detailTextBlock:^NSString *() { return @"\u2023"; }
                selectBlock:^BOOL(YTSettingsCell *c, NSUInteger a) {
                    NSMutableArray <YTSettingsSectionItem *> *presetRows = [NSMutableArray array];

                    [self themeAddPresetRowWithName:@"OLED Dark"
                        overlay:[UIColor whiteColor]
                        tabIcons:[UIColor whiteColor]
                        seekBar:[UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:1.0]
                        bg:[UIColor blackColor]
                        textP:[UIColor whiteColor]
                        textS:[UIColor colorWithRed:0.65 green:0.65 blue:0.65 alpha:1.0]
                        nav:[UIColor blackColor]
                        accent:[UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:1.0]
                        toRows:presetRows settingsVC:settingsViewController];

                    [self themeAddPresetRowWithName:@"Midnight Blue"
                        overlay:[UIColor colorWithRed:0.6 green:0.8 blue:1.0 alpha:1.0]
                        tabIcons:[UIColor colorWithRed:0.4 green:0.7 blue:1.0 alpha:1.0]
                        seekBar:[UIColor colorWithRed:0.2 green:0.5 blue:1.0 alpha:1.0]
                        bg:[UIColor colorWithRed:0.05 green:0.05 blue:0.15 alpha:1.0]
                        textP:[UIColor colorWithRed:0.85 green:0.9 blue:1.0 alpha:1.0]
                        textS:[UIColor colorWithRed:0.5 green:0.6 blue:0.75 alpha:1.0]
                        nav:[UIColor colorWithRed:0.08 green:0.08 blue:0.2 alpha:1.0]
                        accent:[UIColor colorWithRed:0.2 green:0.5 blue:1.0 alpha:1.0]
                        toRows:presetRows settingsVC:settingsViewController];

                    [self themeAddPresetRowWithName:@"Solarized Dark"
                        overlay:[UIColor colorWithRed:0.51 green:0.58 blue:0.59 alpha:1.0]
                        tabIcons:[UIColor colorWithRed:0.51 green:0.58 blue:0.59 alpha:1.0]
                        seekBar:[UIColor colorWithRed:0.52 green:0.60 blue:0.0 alpha:1.0]
                        bg:[UIColor colorWithRed:0.0 green:0.17 blue:0.21 alpha:1.0]
                        textP:[UIColor colorWithRed:0.93 green:0.91 blue:0.84 alpha:1.0]
                        textS:[UIColor colorWithRed:0.51 green:0.58 blue:0.59 alpha:1.0]
                        nav:[UIColor colorWithRed:0.03 green:0.21 blue:0.26 alpha:1.0]
                        accent:[UIColor colorWithRed:0.15 green:0.55 blue:0.82 alpha:1.0]
                        toRows:presetRows settingsVC:settingsViewController];

                    [self themeAddPresetRowWithName:@"Monokai"
                        overlay:[UIColor colorWithRed:0.97 green:0.97 blue:0.95 alpha:1.0]
                        tabIcons:[UIColor colorWithRed:0.65 green:0.89 blue:0.18 alpha:1.0]
                        seekBar:[UIColor colorWithRed:0.98 green:0.15 blue:0.45 alpha:1.0]
                        bg:[UIColor colorWithRed:0.15 green:0.16 blue:0.13 alpha:1.0]
                        textP:[UIColor colorWithRed:0.97 green:0.97 blue:0.95 alpha:1.0]
                        textS:[UIColor colorWithRed:0.46 green:0.44 blue:0.37 alpha:1.0]
                        nav:[UIColor colorWithRed:0.2 green:0.2 blue:0.17 alpha:1.0]
                        accent:[UIColor colorWithRed:0.40 green:0.85 blue:0.94 alpha:1.0]
                        toRows:presetRows settingsVC:settingsViewController];

                    [self themeAddPresetRowWithName:@"Rose Gold"
                        overlay:[UIColor colorWithRed:0.6 green:0.35 blue:0.35 alpha:1.0]
                        tabIcons:[UIColor colorWithRed:0.7 green:0.4 blue:0.4 alpha:1.0]
                        seekBar:[UIColor colorWithRed:0.85 green:0.45 blue:0.5 alpha:1.0]
                        bg:[UIColor colorWithRed:1.0 green:0.95 blue:0.93 alpha:1.0]
                        textP:[UIColor colorWithRed:0.25 green:0.15 blue:0.15 alpha:1.0]
                        textS:[UIColor colorWithRed:0.55 green:0.4 blue:0.4 alpha:1.0]
                        nav:[UIColor colorWithRed:0.95 green:0.88 blue:0.86 alpha:1.0]
                        accent:[UIColor colorWithRed:0.85 green:0.45 blue:0.5 alpha:1.0]
                        toRows:presetRows settingsVC:settingsViewController];

                    [self themeAddPresetRowWithName:@"Clean White"
                        overlay:[UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1.0]
                        tabIcons:[UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:1.0]
                        seekBar:[UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0]
                        bg:[UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:1.0]
                        textP:[UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:1.0]
                        textS:[UIColor colorWithRed:0.45 green:0.45 blue:0.45 alpha:1.0]
                        nav:[UIColor colorWithRed:0.97 green:0.97 blue:0.97 alpha:1.0]
                        accent:[UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0]
                        toRows:presetRows settingsVC:settingsViewController];

                    [self themeAddPresetRowWithName:@"Warm Sand"
                        overlay:[UIColor colorWithRed:0.45 green:0.35 blue:0.25 alpha:1.0]
                        tabIcons:[UIColor colorWithRed:0.5 green:0.38 blue:0.25 alpha:1.0]
                        seekBar:[UIColor colorWithRed:0.85 green:0.55 blue:0.2 alpha:1.0]
                        bg:[UIColor colorWithRed:0.98 green:0.96 blue:0.91 alpha:1.0]
                        textP:[UIColor colorWithRed:0.2 green:0.15 blue:0.1 alpha:1.0]
                        textS:[UIColor colorWithRed:0.5 green:0.42 blue:0.35 alpha:1.0]
                        nav:[UIColor colorWithRed:0.95 green:0.92 blue:0.85 alpha:1.0]
                        accent:[UIColor colorWithRed:0.85 green:0.55 blue:0.2 alpha:1.0]
                        toRows:presetRows settingsVC:settingsViewController];

                    [self themeAddPresetRowWithName:@"Ocean Breeze"
                        overlay:[UIColor colorWithRed:0.15 green:0.4 blue:0.55 alpha:1.0]
                        tabIcons:[UIColor colorWithRed:0.1 green:0.45 blue:0.6 alpha:1.0]
                        seekBar:[UIColor colorWithRed:0.0 green:0.6 blue:0.7 alpha:1.0]
                        bg:[UIColor colorWithRed:0.94 green:0.97 blue:1.0 alpha:1.0]
                        textP:[UIColor colorWithRed:0.1 green:0.15 blue:0.2 alpha:1.0]
                        textS:[UIColor colorWithRed:0.35 green:0.45 blue:0.55 alpha:1.0]
                        nav:[UIColor colorWithRed:0.9 green:0.94 blue:0.98 alpha:1.0]
                        accent:[UIColor colorWithRed:0.0 green:0.55 blue:0.65 alpha:1.0]
                        toRows:presetRows settingsVC:settingsViewController];

                    [self themeAddPresetRowWithName:@"Forest"
                        overlay:[UIColor colorWithRed:0.8 green:0.93 blue:0.8 alpha:1.0]
                        tabIcons:[UIColor colorWithRed:0.4 green:0.75 blue:0.4 alpha:1.0]
                        seekBar:[UIColor colorWithRed:0.3 green:0.7 blue:0.3 alpha:1.0]
                        bg:[UIColor colorWithRed:0.06 green:0.1 blue:0.06 alpha:1.0]
                        textP:[UIColor colorWithRed:0.85 green:0.95 blue:0.85 alpha:1.0]
                        textS:[UIColor colorWithRed:0.5 green:0.65 blue:0.5 alpha:1.0]
                        nav:[UIColor colorWithRed:0.08 green:0.14 blue:0.08 alpha:1.0]
                        accent:[UIColor colorWithRed:0.3 green:0.7 blue:0.3 alpha:1.0]
                        toRows:presetRows settingsVC:settingsViewController];

                    [self themeAddPresetRowWithName:@"Afterglow"
                        overlay:[UIColor colorWithRed:1.0 green:0.55 blue:0.65 alpha:1.0]
                        tabIcons:[UIColor colorWithRed:0.95 green:0.45 blue:0.55 alpha:1.0]
                        seekBar:[UIColor colorWithRed:1.0 green:0.4 blue:0.5 alpha:1.0]
                        bg:[UIColor colorWithRed:0.1 green:0.05 blue:0.18 alpha:1.0]
                        textP:[UIColor colorWithRed:1.0 green:0.9 blue:0.92 alpha:1.0]
                        textS:[UIColor colorWithRed:0.65 green:0.5 blue:0.7 alpha:1.0]
                        nav:[UIColor colorWithRed:0.12 green:0.07 blue:0.22 alpha:1.0]
                        accent:[UIColor colorWithRed:0.95 green:0.4 blue:0.5 alpha:1.0]
                        toRows:presetRows settingsVC:settingsViewController];

                    [self themeAddPresetRowWithName:@"Afterglow Light"
                        overlay:[UIColor colorWithRed:0.75 green:0.3 blue:0.45 alpha:1.0]
                        tabIcons:[UIColor colorWithRed:0.7 green:0.3 blue:0.5 alpha:1.0]
                        seekBar:[UIColor colorWithRed:0.95 green:0.35 blue:0.45 alpha:1.0]
                        bg:[UIColor colorWithRed:1.0 green:0.95 blue:0.96 alpha:1.0]
                        textP:[UIColor colorWithRed:0.2 green:0.08 blue:0.15 alpha:1.0]
                        textS:[UIColor colorWithRed:0.5 green:0.32 blue:0.45 alpha:1.0]
                        nav:[UIColor colorWithRed:0.97 green:0.9 blue:0.93 alpha:1.0]
                        accent:[UIColor colorWithRed:0.85 green:0.3 blue:0.45 alpha:1.0]
                        toRows:presetRows settingsVC:settingsViewController];

                    YTSettingsPickerViewController *presetPicker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Presets") pickerSectionTitle:nil rows:presetRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                    [settingsViewController pushViewController:presetPicker];
                    return YES;
                }];
            [rows addObject:presetsPage];

            // Custom Colors sub-page
            YTSettingsSectionItem *colorsPage = [YTSettingsSectionItemClass itemWithTitle:LOC(@"CustomColors")
                accessibilityIdentifier:nil
                detailTextBlock:^NSString *() { return @"\u2023"; }
                selectBlock:^BOOL(YTSettingsCell *c, NSUInteger a) {
                    NSMutableArray <YTSettingsSectionItem *> *colorRows = [NSMutableArray array];

                    [self themeAddColorRowWithTitle:@"OverlayButtons" themeKey:@"theme_overlayButtons" toRows:colorRows settingsVC:settingsViewController];
                    [self themeAddColorRowWithTitle:@"TabBarIcons" themeKey:@"theme_tabBarIcons" toRows:colorRows settingsVC:settingsViewController];
                    [self themeAddColorRowWithTitle:@"SeekBar" themeKey:@"theme_seekBar" toRows:colorRows settingsVC:settingsViewController];
                    [self themeAddColorRowWithTitle:@"Background" themeKey:@"theme_background" toRows:colorRows settingsVC:settingsViewController];
                    [self themeAddColorRowWithTitle:@"PrimaryText" themeKey:@"theme_textPrimary" toRows:colorRows settingsVC:settingsViewController];
                    [self themeAddColorRowWithTitle:@"SecondaryText" themeKey:@"theme_textSecondary" toRows:colorRows settingsVC:settingsViewController];
                    [self themeAddColorRowWithTitle:@"NavigationBar" themeKey:@"theme_navBar" toRows:colorRows settingsVC:settingsViewController];
                    [self themeAddColorRowWithTitle:@"AccentColor" themeKey:@"theme_accent" toRows:colorRows settingsVC:settingsViewController];

                    YTSettingsPickerViewController *colorPicker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"CustomColors") pickerSectionTitle:nil rows:colorRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                    [settingsViewController pushViewController:colorPicker];
                    return YES;
                }];
            [rows addObject:colorsPage];

            // Gradient sub-page
            YTSettingsSectionItem *gradientPage = [YTSettingsSectionItemClass itemWithTitle:LOC(@"Gradient")
                accessibilityIdentifier:nil
                detailTextBlock:^NSString *() { return @"\u2023"; }
                selectBlock:^BOOL(YTSettingsCell *c, NSUInteger a) {
                    NSMutableArray <YTSettingsSectionItem *> *gradientRows = [NSMutableArray array];

                    [self themeAddColorRowWithTitle:@"GradientStart" themeKey:@"theme_gradientStart" toRows:gradientRows settingsVC:settingsViewController];
                    [self themeAddColorRowWithTitle:@"GradientEnd" themeKey:@"theme_gradientEnd" toRows:gradientRows settingsVC:settingsViewController];

                    YTSettingsPickerViewController *gradientPicker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Gradient") pickerSectionTitle:nil rows:gradientRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                    [settingsViewController pushViewController:gradientPicker];
                    return YES;
                }];
            [rows addObject:gradientPage];

            // Reset All Colors stays at the Appearance top level
            YTSettingsSectionItem *resetAll = [YTSettingsSectionItemClass itemWithTitle:LOC(@"ResetAllColors")
                accessibilityIdentifier:nil
                detailTextBlock:nil
                selectBlock:^BOOL(YTSettingsCell *c, NSUInteger a) {
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:LOC(@"ResetAllColors")
                        message:LOC(@"ResetAllColorsConfirm") preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:LOC(@"ResetAndRestart") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
                        NSArray *keys = @[@"theme_overlayButtons", @"theme_tabBarIcons", @"theme_seekBar",
                                          @"theme_background", @"theme_textPrimary", @"theme_textSecondary",
                                          @"theme_navBar", @"theme_accent",
                                          @"theme_gradientStart", @"theme_gradientEnd"];
                        for (NSString *key in keys) {
                            [[YTLUserDefaults standardUserDefaults] removeObjectForKey:key];
                        }
                        ytl_clearThemeCache();
                        exit(0);
                    }]];
                    [alert addAction:[UIAlertAction actionWithTitle:LOC(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
                    [settingsViewController presentViewController:alert animated:YES completion:nil];
                    return YES;
                }];
            [rows addObject:resetAll];

            YTSettingsPickerViewController *pickerVC = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Appearance") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:pickerVC];
            return YES;
        }];
    [sectionItems addObject:appearance];

    if (ytlBool(@"advancedMode")) {
        YTSettingsSectionItem *overlay = [YTSettingsSectionItemClass itemWithTitle:LOC(@"Overlay")
            accessibilityIdentifier:@"YTLiteSectionItem"
            detailTextBlock:^NSString *() {
                return @"\u2023";
            }
            selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
                NSArray <YTSettingsSectionItem *> *rows = @[
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
                    [self switchWithTitle:@"NoPromotionCards" key:@"noPromotionCards"],
                    [self switchWithTitle:@"NoWatermarks" key:@"noWatermarks"],
                    [self switchWithTitle:@"VideoEndTime" key:@"videoEndTime"],
                    [self switchWithTitle:@"24hrFormat" key:@"24hrFormat"]
                ];

                YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Overlay") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                [settingsViewController pushViewController:picker];
                return YES;
            }];

        [sectionItems addObject:overlay];

        YTSettingsSectionItem *player = [YTSettingsSectionItemClass itemWithTitle:LOC(@"Player")
            accessibilityIdentifier:@"YTLiteSectionItem"
            detailTextBlock:^NSString *() {
                return @"\u2023";
            }
            selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
                NSArray <YTSettingsSectionItem *> *rows = @[
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
                    [self switchWithTitle:@"NoPlayerDownloadButton" key:@"noPlayerDownloadButton"],
                    [self switchWithTitle:@"NoHints" key:@"noHints"],
                    [self switchWithTitle:@"NoFreeZoom" key:@"noFreeZoom"],
                    [self switchWithTitle:@"AutoFullscreen" key:@"autoFullscreen"],
                    [self switchWithTitle:@"ExitFullscreen" key:@"exitFullscreen"],
                    [self switchWithTitle:@"NoDoubleTap2Seek" key:@"noDoubleTapToSeek"]
                ];

                YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Player") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                [settingsViewController pushViewController:picker];
                return YES;
            }];

        [sectionItems addObject:player];

        YTSettingsSectionItem *shorts = [YTSettingsSectionItemClass itemWithTitle:LOC(@"Shorts")
            accessibilityIdentifier:@"YTLiteSectionItem"
            detailTextBlock:^NSString *() {
                return @"\u2023";
            }
            selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
                NSArray <YTSettingsSectionItem *> *rows = @[
                    [self switchWithTitle:@"ShortsOnlyMode" key:@"shortsOnlyMode"],
                    [self switchWithTitle:@"AutoSkipShorts" key:@"autoSkipShorts"],
                    [self switchWithTitle:@"HideShorts" key:@"hideShorts"],
                    [self switchWithTitle:@"ShortsProgress" key:@"shortsProgress"],
                    [self switchWithTitle:@"PinchToFullscreenShorts" key:@"pinchToFullscreenShorts"],
                    [self switchWithTitle:@"ShortsToRegular" key:@"shortsToRegular"],
                    [self switchWithTitle:@"ResumeShorts" key:@"resumeShorts"],
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

                YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Shorts") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                [settingsViewController pushViewController:picker];
                return YES;
            }];

        [sectionItems addObject:shorts];
    }

    YTSettingsSectionItem *tabbar = [YTSettingsSectionItemClass itemWithTitle:LOC(@"Tabbar")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() {
            return @"\u2023";
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
        NSMutableArray <YTSettingsSectionItem *> *rows = [NSMutableArray array];

        [rows addObject:[self switchWithTitle:@"OpaqueBar" key:@"frostedPivot"]];
        [rows addObject:[self switchWithTitle:@"RemoveLabels" key:@"removeLabels"]];
        [rows addObject:[self switchWithTitle:@"RemoveIndicators" key:@"removeIndicators"]];

        // Tab config
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
        NSMutableArray *activeTabs = [[[YTLUserDefaults standardUserDefaults] currentActiveTabs] mutableCopy];

        // YouTube icon types for tabs
        NSDictionary *tabIconTypes = @{
            @"FEwhat_to_watch": @(65),   // TAB_HOME
            @"FEshorts": @(772),         // YOUTUBE_SHORTS_FILL_24
            @"FEsubscriptions": @(66),   // TAB_SUBSCRIPTIONS
            @"FElibrary": @(68),         // TAB_LIBRARY
            @"FEexplore": @(67),         // TAB_TRENDING
            @"FEhistory": @(2),           // WATCH_HISTORY
            @"VLWL": @(3),               // WATCH_LATER
            @"FEpost_home": @(267),      // CHAT_BUBBLE
            @"FEuploads": @(1136)        // ADD_BOLD
        };

        // Active tabs header
        YTSettingsSectionItem *activeHeader = [%c(YTSettingsSectionItem) itemWithTitle:LOC(@"ActiveTabs") accessibilityIdentifier:@"YTLiteSectionItem" detailTextBlock:nil selectBlock:nil];
        activeHeader.enabled = NO;
        [rows addObject:activeHeader];

        for (NSString *tabId in activeTabs) {
            NSString *name = tabNames[tabId] ?: tabId;

            YTSettingsSectionItem *item = [%c(YTSettingsSectionItem) itemWithTitle:name accessibilityIdentifier:@"YTLiteSectionItem" detailTextBlock:nil selectBlock:^BOOL(YTSettingsCell *c, NSUInteger a) {
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

            [rows addObject:item];
        }

        // Inactive tabs header
        YTSettingsSectionItem *inactiveHeader = [%c(YTSettingsSectionItem) itemWithTitle:LOC(@"InactiveTabs") accessibilityIdentifier:@"YTLiteSectionItem" detailTextBlock:nil selectBlock:nil];
        inactiveHeader.enabled = NO;
        [rows addObject:inactiveHeader];

        for (NSUInteger i = 0; i < allTabs.count; i++) {
            NSString *tabId = allTabs[i];
            if ([activeTabs containsObject:tabId]) continue;
            NSString *name = tabNames[tabId] ?: tabId;

            YTSettingsSectionItem *item = [%c(YTSettingsSectionItem) itemWithTitle:name accessibilityIdentifier:@"YTLiteSectionItem" detailTextBlock:nil selectBlock:^BOOL(YTSettingsCell *c, NSUInteger a) {
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

            [rows addObject:item];
        }

        // Footer
        [rows addObject:[%c(YTSettingsSectionItem) itemWithTitle:nil titleDescription:LOC(@"HideLibraryFooter") accessibilityIdentifier:@"YTLiteSectionItem" detailTextBlock:nil selectBlock:nil]];

        YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Tabbar") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
        [settingsViewController pushViewController:picker];
        return YES;
    }];

    [sectionItems addObject:tabbar];

    if (ytlBool(@"advancedMode")) {
        YTSettingsSectionItem *other = [YTSettingsSectionItemClass itemWithTitle:LOC(@"Other")
            accessibilityIdentifier:@"YTLiteSectionItem"
            detailTextBlock:^NSString *() {
                return @"\u2023";
            }
            selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
                NSArray <YTSettingsSectionItem *> *rows = @[
                    [self switchWithTitle:@"CopyVideoInfo" key:@"copyVideoInfo"],
                    [self switchWithTitle:@"PostManager" key:@"postManager"],
                    [self switchWithTitle:@"SaveProfilePhoto" key:@"saveProfilePhoto"],
                    [self switchWithTitle:@"CommentManager" key:@"commentManager"],
                    [self switchWithTitle:@"FixAlbums" key:@"fixAlbums"],
                    [self switchWithTitle:@"NativeShare" key:@"nativeShare"],
                    [self switchWithTitle:@"RemovePlayNext" key:@"removePlayNext"],
                    [self switchWithTitle:@"RemoveDownloadMenu" key:@"removeDownloadMenu"],
                    [self switchWithTitle:@"RemoveWatchLaterMenu" key:@"removeWatchLaterMenu"],
                    [self switchWithTitle:@"RemoveSaveToPlaylistMenu" key:@"removeSaveToPlaylistMenu"],
                    [self switchWithTitle:@"RemoveShareMenu" key:@"removeShareMenu"],
                    [self switchWithTitle:@"RemoveNotInterestedMenu" key:@"removeNotInterestedMenu"],
                    [self switchWithTitle:@"RemoveDontRecommendMenu" key:@"removeDontRecommendMenu"],
                    [self switchWithTitle:@"RemoveReportMenu" key:@"removeReportMenu"],
                    [self switchWithTitle:@"NoContinueWatching" key:@"noContinueWatching"],
                    [self switchWithTitle:@"NoSearchHistory" key:@"noSearchHistory"],
                    [self switchWithTitle:@"NoRelatedWatchNexts" key:@"noRelatedWatchNexts"],
                    [self switchWithTitle:@"StickSortComments" key:@"stickSortComments"],
                    [self switchWithTitle:@"HideSortComments" key:@"hideSortComments"],
                    [self switchWithTitle:@"PlaylistOldMinibar" key:@"playlistOldMinibar"],
                    [self switchWithTitle:@"DisableRTL" key:@"disableRTL"]
                ];

                YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Other") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                [settingsViewController pushViewController:picker];
                return YES;
            }];

        [sectionItems addObject:other];

        [sectionItems addObject:space];

        YTSettingsSectionItem *speed = [YTSettingsSectionItemClass itemWithTitle:LOC(@"HoldToSpeed")
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
                YTSettingsSectionItem *item = [YTSettingsSectionItemClass checkmarkItemWithTitle:title titleDescription:nil selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
                    [settingsViewController reloadData];
                    ytlSetInt((int)arg1, @"speedIndex");
                    return YES;
                }];

                [rows addObject:item];
            }

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"HoldToSpeed") pickerSectionTitle:nil rows:rows selectedItemIndex:ytlInt(@"speedIndex") parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];

        [sectionItems addObject:speed];

        YTSettingsSectionItem *autoSpeed = [YTSettingsSectionItemClass itemWithTitle:LOC(@"DefaultPlaybackRate")
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
                YTSettingsSectionItem *item = [YTSettingsSectionItemClass checkmarkItemWithTitle:title titleDescription:nil selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
                    [settingsViewController reloadData];
                    ytlSetInt((int)arg1, @"autoSpeedIndex");
                    return YES;
                }];
                [rows addObject:item];
            }

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"DefaultPlaybackRate") pickerSectionTitle:nil rows:rows selectedItemIndex:ytlInt(@"autoSpeedIndex") parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];

        [sectionItems addObject:autoSpeed];

        YTSettingsSectionItem *wifiQuality = [YTSettingsSectionItemClass itemWithTitle:LOC(@"PlaybackQualityOnWiFi")
            accessibilityIdentifier:@"YTLiteSectionItem"
            detailTextBlock:^NSString *() {
            NSArray *qualityLabels = @[LOC(@"Default"), LOC(@"Best"), @"2160p60", @"2160p", @"1440p60", @"1440p", @"1080p60", @"1080p", @"720p60", @"720p", @"480p", @"360p"];
            return qualityLabels[ytlInt(@"wiFiQualityIndex")];
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray <YTSettingsSectionItem *> *rows = [NSMutableArray array];
            NSArray *qualityLabels = @[LOC(@"Default"), LOC(@"Best"), @"2160p60", @"2160p", @"1440p60", @"1440p", @"1080p60", @"1080p", @"720p60", @"720p", @"480p", @"360p"];

            for (NSUInteger i = 0; i < qualityLabels.count; i++) {
                NSString *title = qualityLabels[i];
                YTSettingsSectionItem *item = [YTSettingsSectionItemClass checkmarkItemWithTitle:title titleDescription:nil selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
                    [settingsViewController reloadData];
                    ytlSetInt((int)arg1, @"wiFiQualityIndex");
                    return YES;
                }];

                [rows addObject:item];
            }

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"SelectQuality") pickerSectionTitle:nil rows:rows selectedItemIndex:ytlInt(@"wiFiQualityIndex") parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];

        [sectionItems addObject:wifiQuality];

        YTSettingsSectionItem *cellQuality = [YTSettingsSectionItemClass itemWithTitle:LOC(@"PlaybackQualityOnCellular")
            accessibilityIdentifier:@"YTLiteSectionItem"
            detailTextBlock:^NSString *() {
            NSArray *qualityLabels = @[LOC(@"Default"), LOC(@"Best"), @"2160p60", @"2160p", @"1440p60", @"1440p", @"1080p60", @"1080p", @"720p60", @"720p", @"480p", @"360p"];
            return qualityLabels[ytlInt(@"cellQualityIndex")];
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray <YTSettingsSectionItem *> *rows = [NSMutableArray array];
            NSArray *qualityLabels = @[LOC(@"Default"), LOC(@"Best"), @"2160p60", @"2160p", @"1440p60", @"1440p", @"1080p60", @"1080p", @"720p60", @"720p", @"480p", @"360p"];

            for (NSUInteger i = 0; i < qualityLabels.count; i++) {
                NSString *title = qualityLabels[i];
                YTSettingsSectionItem *item = [YTSettingsSectionItemClass checkmarkItemWithTitle:title titleDescription:nil selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
                    [settingsViewController reloadData];
                    ytlSetInt((int)arg1, @"cellQualityIndex");
                    return YES;
                }];

                [rows addObject:item];
            }

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"SelectQuality") pickerSectionTitle:nil rows:rows selectedItemIndex:ytlInt(@"cellQualityIndex") parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];

        [sectionItems addObject:cellQuality];

        YTSettingsSectionItem *startup = [YTSettingsSectionItemClass itemWithTitle:LOC(@"Startup")
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

                YTSettingsSectionItem *item = [YTSettingsSectionItemClass checkmarkItemWithTitle:title titleDescription:nil selectBlock:^BOOL (YTSettingsCell *c, NSUInteger a) {
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

        [sectionItems addObject:startup];
    }
    
    [sectionItems addObject:space];

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

    YTSettingsSectionItem *thanks = [YTSettingsSectionItemClass itemWithTitle:LOC(@"Contributors")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() {
            return @"\u2023";
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

    YTSettingsSectionItem *sources = [YTSettingsSectionItemClass itemWithTitle:LOC(@"OpenSourceLibs")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() {
            return @"\u2023";
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

    YTSettingsSectionItem *version = [YTSettingsSectionItemClass itemWithTitle:LOC(@"Version")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() {
            return @(OS_STRINGIFY(TWEAK_VERSION));
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSArray <YTSettingsSectionItem *> *rows = @[
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
            ];

        YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"About") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
        [settingsViewController pushViewController:picker];
        return YES;
    }];

    [sectionItems addObject:thanks];

    [sectionItems addObject:sources];

    [sectionItems addObject:support];

    [sectionItems addObject:version];

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
