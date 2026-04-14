#import "YTAfterglow.h"
#import <objc/runtime.h>

extern void ytag_clearThemeCache(void);
static UIViewController *ytag_viewControllerForResponder(UIResponder *responder);
static void ytag_reloadSettingsController(UIViewController *controller);
static void ytag_refreshSettingsHierarchy(UIViewController *controller);
static void ytag_refreshSettingsFromCell(YTSettingsCell *cell);
static void ytag_presentThemeRefreshAlert(UIViewController *presenter, NSString *title, NSString *message);

@interface YTSettingsSectionItemManager (YTAfterglow)
- (void)updateYTAfterglowSectionWithEntry:(id)entry;
- (YTSettingsSectionItem *)pageItemWithTitle:(NSString *)title titleDescription:(NSString *)titleDescription summary:(NSString *(^)(void))summaryBlock selectBlock:(BOOL (^)(YTSettingsCell *cell, NSUInteger arg1))selectBlock;
- (NSString *)enabledSummaryForKeys:(NSArray<NSString *> *)keys;
- (NSString *)customizationSummaryForKeys:(NSArray<NSString *> *)keys;
- (NSArray<NSString *> *)ytag_allTabs;
- (NSDictionary<NSString *, NSString *> *)ytag_tabNames;
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
- (void)themeApplyPresetOverlay:(UIColor *)overlay tabIcons:(UIColor *)tabIcons seekBar:(UIColor *)seekBar bg:(UIColor *)bg textP:(UIColor *)textP textS:(UIColor *)textS nav:(UIColor *)nav accent:(UIColor *)accent gradientStart:(UIColor *)gradientStart gradientEnd:(UIColor *)gradientEnd;
- (void)themeAddPresetRowWithName:(NSString *)name titleDescription:(NSString *)titleDescription overlay:(UIColor *)overlay tabIcons:(UIColor *)tabIcons seekBar:(UIColor *)seekBar bg:(UIColor *)bg textP:(UIColor *)textP textS:(UIColor *)textS nav:(UIColor *)nav accent:(UIColor *)accent gradientStart:(UIColor *)gradientStart gradientEnd:(UIColor *)gradientEnd toRows:(NSMutableArray *)rows settingsVC:(YTSettingsViewController *)settingsVC;
- (YTSettingsSectionItem *)themeSectionHeaderWithTitle:(NSString *)title description:(NSString *)description;
@end

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

// Color picker delegate — guarded by @available(iOS 14.0, *) at call sites
@interface YTAGColorPickerDelegate : NSObject <UIColorPickerViewControllerDelegate>
@property (nonatomic, copy) NSString *themeKey;
@property (nonatomic, weak) YTSettingsViewController *settingsVC;
@property (nonatomic, assign) BOOL didSelect;
@property (nonatomic, assign) CFAbsoluteTime lastSave;
@end

@implementation YTAGColorPickerDelegate
- (void)colorPickerViewController:(UIColorPickerViewController *)vc didSelectColor:(UIColor *)color continuously:(BOOL)continuously {
    if (!color || !self.themeKey) return;
    self.didSelect = YES;

    // Throttle: save at most every 0.25s during continuous drag
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (continuously && (now - self.lastSave) < 0.25) return;
    self.lastSave = now;

    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:color requiringSecureCoding:NO error:nil];
    [[YTAGUserDefaults standardUserDefaults] setObject:data forKey:self.themeKey];
    ytag_clearThemeCache();
}
- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)vc {
    // Final save on dismiss
    UIColor *color = vc.selectedColor;
    if (color && self.themeKey) {
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:color requiringSecureCoding:NO error:nil];
        [[YTAGUserDefaults standardUserDefaults] setObject:data forKey:self.themeKey];
        ytag_clearThemeCache();
    }

    // Reload settings + show alert
    __weak YTSettingsViewController *weakVC = self.settingsVC;
    BOOL selected = self.didSelect;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ytag_refreshSettingsHierarchy(weakVC);
        if (selected && weakVC) {
            UIViewController *presenter = weakVC.navigationController.topViewController ?: weakVC;
            ytag_presentThemeRefreshAlert(presenter, LOC(@"ColorSaved"), @"Some surfaces refresh immediately. Restart YouTube for a full theme refresh across the app.");
        }
    });
}
@end

#pragma clang diagnostic pop

static const NSInteger YTAfterglowSection = 789;
static YTAGColorPickerDelegate *_colorPickerDelegate = nil;

static UIColor *YTAGAfterglowTintColor(void) {
    return [UIColor colorWithRed:0.95 green:0.41 blue:0.50 alpha:1.0];
}

static UIViewController *ytag_viewControllerForResponder(UIResponder *responder) {
    UIResponder *currentResponder = responder;
    while (currentResponder && ![currentResponder isKindOfClass:[UIViewController class]]) {
        currentResponder = currentResponder.nextResponder;
    }
    return (UIViewController *)currentResponder;
}

static void ytag_reloadSettingsController(UIViewController *controller) {
    if (!controller || ![controller respondsToSelector:@selector(reloadData)]) return;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [controller performSelector:@selector(reloadData)];
#pragma clang diagnostic pop
}

static void ytag_refreshSettingsHierarchy(UIViewController *controller) {
    if (!controller) return;

    NSMutableOrderedSet<UIViewController *> *controllers = [NSMutableOrderedSet orderedSet];
    if (controller.navigationController.viewControllers.count > 0) {
        [controllers addObjectsFromArray:controller.navigationController.viewControllers];
    }
    [controllers addObject:controller];

    for (UIViewController *viewController in controllers) {
        ytag_reloadSettingsController(viewController);
    }
}

static void ytag_refreshSettingsFromCell(YTSettingsCell *cell) {
    ytag_refreshSettingsHierarchy(ytag_viewControllerForResponder(cell));
}

static void ytag_presentThemeRefreshAlert(UIViewController *presenter, NSString *title, NSString *message) {
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

@interface YTAGTabBarEditorController : UITableViewController
@property (nonatomic, weak) YTSettingsViewController *settingsViewController;
@property (nonatomic, strong) NSMutableArray<NSString *> *activeTabs;
@property (nonatomic, strong) NSMutableArray<NSString *> *inactiveTabs;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *tabNames;
- (instancetype)initWithSettingsViewController:(YTSettingsViewController *)settingsViewController activeTabs:(NSArray<NSString *> *)activeTabs allTabs:(NSArray<NSString *> *)allTabs tabNames:(NSDictionary<NSString *, NSString *> *)tabNames;
@end

@implementation YTAGTabBarEditorController

- (instancetype)initWithSettingsViewController:(YTSettingsViewController *)settingsViewController activeTabs:(NSArray<NSString *> *)activeTabs allTabs:(NSArray<NSString *> *)allTabs tabNames:(NSDictionary<NSString *,NSString *> *)tabNames {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _settingsViewController = settingsViewController;
        _activeTabs = [activeTabs mutableCopy];
        _tabNames = [tabNames copy];

        NSMutableArray<NSString *> *inactive = [NSMutableArray array];
        for (NSString *tabId in allTabs) {
            if (![_activeTabs containsObject:tabId]) [inactive addObject:tabId];
        }
        _inactiveTabs = inactive;
        self.title = LOC(@"Tabbar");
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.tableView.tintColor = YTAGAfterglowTintColor();
    self.tableView.editing = YES;
    self.tableView.allowsSelectionDuringEditing = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 0.0;
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    ytag_refreshSettingsHierarchy(self.settingsViewController ?: self);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? self.activeTabs.count : self.inactiveTabs.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? LOC(@"ActiveTabs") : LOC(@"InactiveTabs");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"Drag to reorder your active tabs or move them down to disable them. Keep between 2 and 6 active tabs.";
    }
    return @"Drag a tab into Active Tabs to enable it, or tap a row to add it to the end.";
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (UIImage *)ytag_imageForTabId:(NSString *)tabId {
    NSString *symbolName = nil;

    if ([tabId isEqualToString:@"FEwhat_to_watch"]) symbolName = @"house.fill";
    else if ([tabId isEqualToString:@"FEshorts"]) symbolName = @"play.square.fill";
    else if ([tabId isEqualToString:@"FEsubscriptions"]) symbolName = @"play.rectangle.on.rectangle.fill";
    else if ([tabId isEqualToString:@"FElibrary"]) symbolName = @"books.vertical.fill";
    else if ([tabId isEqualToString:@"FEexplore"]) symbolName = @"safari.fill";
    else if ([tabId isEqualToString:@"FEhistory"]) symbolName = @"clock.fill";
    else if ([tabId isEqualToString:@"VLWL"]) symbolName = @"bookmark.fill";
    else if ([tabId isEqualToString:@"FEpost_home"]) symbolName = @"text.bubble.fill";
    else if ([tabId isEqualToString:@"FEuploads"]) symbolName = @"plus.app.fill";

    if (!symbolName) return nil;

    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold];
    return [[UIImage systemImageNamed:symbolName withConfiguration:config] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

- (void)ytag_showLimitAlertWithMessage:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:LOC(@"Warning")
        message:message
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)ytag_persistTabsAndRefresh {
    [[YTAGUserDefaults standardUserDefaults] setActiveTabs:self.activeTabs];
    [[[%c(YTHeaderContentComboViewController) alloc] init] refreshPivotBar];
    ytag_refreshSettingsHierarchy(self.settingsViewController ?: self);
}

- (void)ytag_moveTabFromIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    NSMutableArray<NSString *> *sourceArray = sourceIndexPath.section == 0 ? self.activeTabs : self.inactiveTabs;
    NSMutableArray<NSString *> *destinationArray = destinationIndexPath.section == 0 ? self.activeTabs : self.inactiveTabs;
    NSString *tabId = sourceArray[sourceIndexPath.row];

    [sourceArray removeObjectAtIndex:sourceIndexPath.row];
    NSInteger destinationRow = MIN((NSInteger)destinationIndexPath.row, (NSInteger)destinationArray.count);
    [destinationArray insertObject:tabId atIndex:destinationRow];

    [self ytag_persistTabsAndRefresh];
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath {
    BOOL movingFromActive = sourceIndexPath.section == 0;
    BOOL movingToActive = proposedDestinationIndexPath.section == 0;

    if (movingFromActive && !movingToActive && self.activeTabs.count <= 2) {
        return sourceIndexPath;
    }

    if (!movingFromActive && movingToActive && self.activeTabs.count >= 6) {
        return sourceIndexPath;
    }

    NSInteger maxRow = [self tableView:tableView numberOfRowsInSection:proposedDestinationIndexPath.section];
    NSInteger clampedRow = MIN((NSInteger)proposedDestinationIndexPath.row, maxRow);
    return [NSIndexPath indexPathForRow:clampedRow inSection:proposedDestinationIndexPath.section];
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    [self ytag_moveTabFromIndexPath:sourceIndexPath toIndexPath:destinationIndexPath];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        if (self.activeTabs.count <= 2) {
            [self ytag_showLimitAlertWithMessage:LOC(@"AtLeastOneTab")];
            return;
        }

        NSString *tabId = self.activeTabs[indexPath.row];
        [self.activeTabs removeObjectAtIndex:indexPath.row];
        [self.inactiveTabs insertObject:tabId atIndex:0];
        [self ytag_persistTabsAndRefresh];
        [tableView reloadData];
        return;
    }

    if (self.activeTabs.count >= 6) {
        [self ytag_showLimitAlertWithMessage:LOC(@"TabsCountRestricted")];
        return;
    }

    NSString *tabId = self.inactiveTabs[indexPath.row];
    [self.inactiveTabs removeObjectAtIndex:indexPath.row];
    [self.activeTabs addObject:tabId];
    [self ytag_persistTabsAndRefresh];
    [tableView reloadData];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"YTAGTabEditorCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    }

    NSString *tabId = indexPath.section == 0 ? self.activeTabs[indexPath.row] : self.inactiveTabs[indexPath.row];
    cell.textLabel.text = self.tabNames[tabId] ?: tabId;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.text = indexPath.section == 0 ? @"Visible in the pivot bar" : @"Drag into Active Tabs to enable";
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.imageView.image = [self ytag_imageForTabId:tabId];
    cell.imageView.tintColor = YTAGAfterglowTintColor();
    cell.showsReorderControl = YES;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessoryType = UITableViewCellAccessoryNone;

    return cell;
}

@end

// Settings
%hook YTSettingsSectionController
- (void)setSelectedItem:(NSUInteger)selectedItem {
    if (selectedItem != NSNotFound) %orig;
}
%end

%hook YTSettingsCell
- (void)layoutSubviews {
    %orig;

    BOOL isYTAfterglow = [self.accessibilityIdentifier isEqualToString:@"YTAfterglowSectionItem"];
    YTTouchFeedbackController *feedback = [self valueForKey:@"_touchFeedbackController"];
    ABCSwitch *abcSwitch = [self valueForKey:@"_switch"];

    if (isYTAfterglow) {
        feedback.feedbackColor = YTAGAfterglowTintColor();
        abcSwitch.onTintColor = YTAGAfterglowTintColor();
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
    accessibilityIdentifier:@"YTAfterglowSectionItem"
    switchOn:ytagBool(key)
    switchBlock:^BOOL(YTSettingsCell *cell, BOOL enabled) {
        if ([key isEqualToString:@"shortsOnlyMode"]) {
            YTAlertView *alertView = [YTAlertViewClass confirmationDialogWithAction:^{
                ytagSetBool(enabled, @"shortsOnlyMode");
                ytag_refreshSettingsFromCell(cell);
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
            ytagSetBool(enabled, key);

            NSArray *keys = @[@"removeLabels", @"removeIndicators", @"frostedPivot",
                @"theme_overlayButtons", @"theme_tabBarIcons", @"theme_seekBar",
                @"theme_background", @"theme_textPrimary", @"theme_textSecondary",
                @"theme_navBar", @"theme_accent",
                @"theme_gradientStart", @"theme_gradientEnd", @"theme_glowEnabled"];
            if ([keys containsObject:key]) {
                [[[%c(YTHeaderContentComboViewController) alloc] init] refreshPivotBar];
            }

            ytag_refreshSettingsFromCell(cell);
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
    accessibilityIdentifier:@"YTAfterglowSectionItem"
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
        accessibilityIdentifier:@"YTAfterglowSectionItem"
        detailTextBlock:^NSString *() {
            return summaryBlock ? summaryBlock() : @"\u2023";
        }
        selectBlock:selectBlock];
}

%new
- (NSString *)enabledSummaryForKeys:(NSArray<NSString *> *)keys {
    NSUInteger enabledCount = 0;
    for (NSString *key in keys) {
        if (ytagBool(key)) enabledCount++;
    }

    if (enabledCount == 0) return LOC(@"Disabled");
    if (enabledCount == 1) return @"1 on";
    return [NSString stringWithFormat:@"%lu on", (unsigned long)enabledCount];
}

%new
- (NSString *)customizationSummaryForKeys:(NSArray<NSString *> *)keys {
    NSUInteger customizedCount = 0;

    for (NSString *key in keys) {
        if ([[YTAGUserDefaults standardUserDefaults] objectForKey:key] != nil) customizedCount++;
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
                      @"theme_gradientStart", @"theme_gradientEnd", @"theme_glowEnabled"];
    return [self customizationSummaryForKeys:keys];
}

%new
- (YTSettingsSectionItem *)holdToSpeedItemWithSettingsVC:(YTSettingsViewController *)settingsViewController {
    Class YTSettingsSectionItemClass = %c(YTSettingsSectionItem);
    NSArray *speedLabels = @[
        LOC(@"Disabled"),
        LOC(@"Default"),
        @"1.25×",
        @"1.5×",
        @"1.75×",
        @"2.0×",
        @"2.25×",
        @"2.5×",
        @"2.75×",
        @"3.0×",
        @"3.25×",
        @"3.5×",
        @"3.75×",
        @"4.0×",
        @"4.25×",
        @"4.5×",
        @"4.75×",
        @"5.0×"
    ];

    return [YTSettingsSectionItemClass itemWithTitle:LOC(@"HoldToSpeed")
        accessibilityIdentifier:@"YTAfterglowSectionItem"
        detailTextBlock:^NSString *() {
            NSInteger speedIndex = MIN(MAX(ytagInt(@"speedIndex"), 0), (int)speedLabels.count - 1);
            return speedLabels[speedIndex];
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray <YTSettingsSectionItem *> *rows = [NSMutableArray array];
            NSInteger selectedSpeedIndex = MIN(MAX(ytagInt(@"speedIndex"), 0), (int)speedLabels.count - 1);

            for (NSUInteger i = 0; i < speedLabels.count; i++) {
                NSString *title = speedLabels[i];
                YTSettingsSectionItem *item = [YTSettingsSectionItemClass checkmarkItemWithTitle:title titleDescription:nil selectBlock:^BOOL (YTSettingsCell *innerCell, NSUInteger innerArg1) {
                    ytagSetInt((int)innerArg1, @"speedIndex");
                    ytag_refreshSettingsHierarchy(settingsViewController);
                    return YES;
                }];

                [rows addObject:item];
            }

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"HoldToSpeed") pickerSectionTitle:nil rows:rows selectedItemIndex:selectedSpeedIndex parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];
}

%new
- (YTSettingsSectionItem *)defaultPlaybackRateItemWithSettingsVC:(YTSettingsViewController *)settingsViewController {
    Class YTSettingsSectionItemClass = %c(YTSettingsSectionItem);

    return [YTSettingsSectionItemClass itemWithTitle:LOC(@"DefaultPlaybackRate")
        accessibilityIdentifier:@"YTAfterglowSectionItem"
        detailTextBlock:^NSString *() {
            NSArray *speedLabels = @[@"0.25×", @"0.5×", @"0.75×", @"1.0×", @"1.25×", @"1.5×", @"1.75×", @"2.0×", @"3.0×", @"4.0×", @"5.0×"];
            return speedLabels[ytagInt(@"autoSpeedIndex")];
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray <YTSettingsSectionItem *> *rows = [NSMutableArray array];
            NSArray *speedLabels = @[@"0.25×", @"0.5×", @"0.75×", @"1.0×", @"1.25×", @"1.5×", @"1.75×", @"2.0×", @"3.0×", @"4.0×", @"5.0×"];

            for (NSUInteger i = 0; i < speedLabels.count; i++) {
                NSString *title = speedLabels[i];
                YTSettingsSectionItem *item = [YTSettingsSectionItemClass checkmarkItemWithTitle:title titleDescription:nil selectBlock:^BOOL (YTSettingsCell *innerCell, NSUInteger innerArg1) {
                    ytagSetInt((int)innerArg1, @"autoSpeedIndex");
                    ytag_refreshSettingsHierarchy(settingsViewController);
                    return YES;
                }];
                [rows addObject:item];
            }

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"DefaultPlaybackRate") pickerSectionTitle:nil rows:rows selectedItemIndex:ytagInt(@"autoSpeedIndex") parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];
}

%new
- (YTSettingsSectionItem *)playbackQualityItemWithTitle:(NSString *)title key:(NSString *)key settingsVC:(YTSettingsViewController *)settingsViewController {
    Class YTSettingsSectionItemClass = %c(YTSettingsSectionItem);

    return [YTSettingsSectionItemClass itemWithTitle:LOC(title)
        accessibilityIdentifier:@"YTAfterglowSectionItem"
        detailTextBlock:^NSString *() {
            NSArray *qualityLabels = @[LOC(@"Default"), LOC(@"Best"), @"2160p60", @"2160p", @"1440p60", @"1440p", @"1080p60", @"1080p", @"720p60", @"720p", @"480p", @"360p"];
            return qualityLabels[ytagInt(key)];
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray <YTSettingsSectionItem *> *rows = [NSMutableArray array];
            NSArray *qualityLabels = @[LOC(@"Default"), LOC(@"Best"), @"2160p60", @"2160p", @"1440p60", @"1440p", @"1080p60", @"1080p", @"720p60", @"720p", @"480p", @"360p"];

            for (NSUInteger i = 0; i < qualityLabels.count; i++) {
                NSString *qualityTitle = qualityLabels[i];
                YTSettingsSectionItem *item = [YTSettingsSectionItemClass checkmarkItemWithTitle:qualityTitle titleDescription:nil selectBlock:^BOOL (YTSettingsCell *innerCell, NSUInteger innerArg1) {
                    ytagSetInt((int)innerArg1, key);
                    ytag_refreshSettingsHierarchy(settingsViewController);
                    return YES;
                }];

                [rows addObject:item];
            }

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"SelectQuality") pickerSectionTitle:nil rows:rows selectedItemIndex:ytagInt(key) parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];
}

%new
- (YTSettingsSectionItem *)startupTabItemWithSettingsVC:(YTSettingsViewController *)settingsViewController {
    Class YTSettingsSectionItemClass = %c(YTSettingsSectionItem);

    return [YTSettingsSectionItemClass itemWithTitle:LOC(@"Startup")
        accessibilityIdentifier:@"YTAfterglowSectionItem"
        detailTextBlock:^NSString *() {
            NSString *tab = [[YTAGUserDefaults standardUserDefaults] currentStartupTab];
            NSDictionary *names = [self ytag_tabNames];
            return names[tab] ?: tab;
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSArray *activeTabs = [[YTAGUserDefaults standardUserDefaults] currentActiveTabs];
            NSDictionary *names = [self ytag_tabNames];
            NSString *currentTab = [[YTAGUserDefaults standardUserDefaults] currentStartupTab];

            NSMutableArray <YTSettingsSectionItem *> *rows = [NSMutableArray array];
            NSInteger selectedIdx = 0;

            for (NSUInteger i = 0; i < activeTabs.count; i++) {
                NSString *tabId = activeTabs[i];
                NSString *title = names[tabId] ?: tabId;
                if ([tabId isEqualToString:currentTab]) selectedIdx = i;

                YTSettingsSectionItem *item = [YTSettingsSectionItemClass checkmarkItemWithTitle:title titleDescription:nil selectBlock:^BOOL (YTSettingsCell *innerCell, NSUInteger innerArg1) {
                    [[YTAGUserDefaults standardUserDefaults] setObject:tabId forKey:@"startupTab"];
                    ytag_refreshSettingsHierarchy(settingsViewController);
                    return YES;
                }];
                [rows addObject:item];
            }

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Startup") pickerSectionTitle:nil rows:rows selectedItemIndex:selectedIdx parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];
}

#pragma mark - Tab Helpers

%new
- (NSArray<NSString *> *)ytag_allTabs {
    return @[@"FEwhat_to_watch", @"FEshorts", @"FEsubscriptions", @"FElibrary", @"FEexplore", @"FEhistory", @"VLWL", @"FEpost_home", @"FEuploads"];
}

%new
- (NSDictionary<NSString *, NSString *> *)ytag_tabNames {
    return @{
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
        if ([[YTAGUserDefaults standardUserDefaults] objectForKey:key] != nil) customizedCount++;
    }

    BOOL hasGradientStart = [[YTAGUserDefaults standardUserDefaults] objectForKey:@"theme_gradientStart"] != nil;
    BOOL hasGradientEnd = [[YTAGUserDefaults standardUserDefaults] objectForKey:@"theme_gradientEnd"] != nil;
    BOOL hasGradient = hasGradientStart || hasGradientEnd;
    BOOL hasGlow = ytagBool(@"theme_glowEnabled");

    if (customizedCount == 0 && !hasGradient && !hasGlow) return LOC(@"Default");
    if (customizedCount == 0 && hasGradient && !hasGlow) return [NSString stringWithFormat:@"Gradient %@", [self themeGradientSummary]];
    if (customizedCount == 0 && hasGlow) return hasGradient ? @"Glow + gradient" : @"Brand glow";
    if (!hasGradient && !hasGlow) return customizedCount == 1 ? @"1 color override" : [NSString stringWithFormat:@"%lu color overrides", (unsigned long)customizedCount];
    if (hasGradient && hasGlow) return [NSString stringWithFormat:@"%lu colors + glow", (unsigned long)customizedCount];
    if (hasGradient) return [NSString stringWithFormat:@"%lu colors + gradient", (unsigned long)customizedCount];
    return [NSString stringWithFormat:@"%lu colors + glow", (unsigned long)customizedCount];
}

%new
- (UIColor *)themeLoadColorForKey:(NSString *)key {
    NSData *data = [[YTAGUserDefaults standardUserDefaults] objectForKey:key];
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
        YTAGColorPickerDelegate *delegate = [[YTAGColorPickerDelegate alloc] init];
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
        accessibilityIdentifier:@"YTAfterglowSectionItem"
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
            accessibilityIdentifier:@"YTAfterglowSectionItem"
            detailTextBlock:^NSString *() {
                return [NSString stringWithFormat:@"Clears %@", [self themeColorDetailForKey:themeKey]];
            }
            selectBlock:^BOOL(YTSettingsCell *c, NSUInteger a) {
                [[YTAGUserDefaults standardUserDefaults] removeObjectForKey:themeKey];
                ytag_clearThemeCache();
                ytag_refreshSettingsHierarchy(settingsVC);
                [(UINavigationController *)settingsVC.navigationController popViewControllerAnimated:YES];
                return YES;
            }];
        [rows addObject:reset];
    }
}

%new
- (void)themeSaveColor:(UIColor *)color forKey:(NSString *)key {
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:color requiringSecureCoding:NO error:nil];
    [[YTAGUserDefaults standardUserDefaults] setObject:data forKey:key];
}

%new
- (void)themeApplyPresetOverlay:(UIColor *)overlay tabIcons:(UIColor *)tabIcons seekBar:(UIColor *)seekBar bg:(UIColor *)bg textP:(UIColor *)textP textS:(UIColor *)textS nav:(UIColor *)nav accent:(UIColor *)accent gradientStart:(UIColor *)gradientStart gradientEnd:(UIColor *)gradientEnd {
    [self themeSaveColor:overlay forKey:@"theme_overlayButtons"];
    [self themeSaveColor:tabIcons forKey:@"theme_tabBarIcons"];
    [self themeSaveColor:seekBar forKey:@"theme_seekBar"];
    [self themeSaveColor:bg forKey:@"theme_background"];
    [self themeSaveColor:textP forKey:@"theme_textPrimary"];
    [self themeSaveColor:textS forKey:@"theme_textSecondary"];
    [self themeSaveColor:nav forKey:@"theme_navBar"];
    [self themeSaveColor:accent forKey:@"theme_accent"];
    if (gradientStart && gradientEnd) {
        [self themeSaveColor:gradientStart forKey:@"theme_gradientStart"];
        [self themeSaveColor:gradientEnd forKey:@"theme_gradientEnd"];
    } else {
        [[YTAGUserDefaults standardUserDefaults] removeObjectForKey:@"theme_gradientStart"];
        [[YTAGUserDefaults standardUserDefaults] removeObjectForKey:@"theme_gradientEnd"];
    }
    ytag_clearThemeCache();
}

%new
- (void)themeAddPresetRowWithName:(NSString *)name titleDescription:(NSString *)titleDescription overlay:(UIColor *)overlay tabIcons:(UIColor *)tabIcons seekBar:(UIColor *)seekBar bg:(UIColor *)bg textP:(UIColor *)textP textS:(UIColor *)textS nav:(UIColor *)nav accent:(UIColor *)accent gradientStart:(UIColor *)gradientStart gradientEnd:(UIColor *)gradientEnd toRows:(NSMutableArray *)rows settingsVC:(YTSettingsViewController *)settingsVC {
    Class YTSettingsSectionItemClass = %c(YTSettingsSectionItem);

    YTSettingsSectionItem *item = [YTSettingsSectionItemClass itemWithTitle:name
        titleDescription:titleDescription
        accessibilityIdentifier:@"YTAfterglowSectionItem"
        detailTextBlock:^NSString *() {
            return @"Apply";
        }
        selectBlock:^BOOL(YTSettingsCell *c, NSUInteger a) {
            [[YTAGUserDefaults standardUserDefaults] setBool:[name hasPrefix:@"Afterglow"] forKey:@"theme_glowEnabled"];
            [self themeApplyPresetOverlay:overlay tabIcons:tabIcons seekBar:seekBar bg:bg textP:textP textS:textS nav:nav accent:accent gradientStart:gradientStart gradientEnd:gradientEnd];
            ytag_refreshSettingsHierarchy(settingsVC);
            UIViewController *presenter = settingsVC.navigationController.topViewController ?: settingsVC;
            ytag_presentThemeRefreshAlert(presenter, LOC(@"PresetApplied"), [NSString stringWithFormat:@"%@ is ready. Restart YouTube for the full look across every surface.", name]);
            return YES;
        }];
    [rows addObject:item];
}

%new
- (YTSettingsSectionItem *)themeSectionHeaderWithTitle:(NSString *)title description:(NSString *)description {
    YTSettingsSectionItem *item = [%c(YTSettingsSectionItem) itemWithTitle:title
        titleDescription:description
        accessibilityIdentifier:@"YTAfterglowSectionItem"
        detailTextBlock:nil
        selectBlock:nil];
    item.enabled = NO;
    return item;
}

#pragma mark - Settings Section

%new(v@:@)
- (void)updateYTAfterglowSectionWithEntry:(id)entry {
    NSMutableArray *sectionItems = [NSMutableArray array];
    YTSettingsViewController *settingsViewController = [self valueForKey:@"_settingsViewControllerDelegate"];
    BOOL isAdvanced = ytagBool(@"advancedMode");

    YTSettingsSectionItem *space = [%c(YTSettingsSectionItem) itemWithTitle:nil accessibilityIdentifier:@"YTAfterglowSectionItem" detailTextBlock:nil selectBlock:nil];
    NSArray *adsKeys = @[@"noAds", @"noPromotionCards"];
    NSArray *navbarKeys = @[@"noCast", @"noNotifsButton", @"noSearchButton", @"noVoiceSearchButton", @"stickyNavbar", @"noSubbar", @"noYTLogo", @"premiumYTLogo"];
    NSArray *tabbarKeys = @[@"frostedPivot", @"removeLabels", @"removeIndicators"];
    NSArray *legacyKeys = @[@"oldYTUI"];
    NSArray *interfaceKeys = [[[tabbarKeys arrayByAddingObject:@"startupAnimation"] arrayByAddingObject:@"floatingKeyboard"] arrayByAddingObjectsFromArray:legacyKeys];
    NSArray *overlayKeys = @[@"hideAutoplay", @"hideSubs", @"showPlayerShareButton", @"showPlayerSaveButton", @"noHUDMsgs", @"hidePrevNext", @"replacePrevNext", @"noDarkBg", @"endScreenCards", @"noFullscreenActions", @"persistentProgressBar", @"stockVolumeHUD", @"noRelatedVids", @"noWatermarks", @"disableAmbientMode", @"videoEndTime", @"24hrFormat", @"hideHeatwaves", @"noContinueWatchingPrompt"];
    NSArray *playerKeys = @[@"backgroundPlayback", @"miniplayer", @"portraitFullscreen", @"copyWithTimestamp", @"disableAutoplay", @"disableAutoCaptions", @"rememberCaptionState", @"rememberLoop", @"noContentWarning", @"classicQuality", @"tapToSeek", @"dontSnapToChapter", @"noTwoFingerSnapToChapter", @"pauseOnOverlay", @"redProgressBar", @"noPlayerRemixButton", @"noPlayerClipButton", @"noFreeZoom", @"autoFullscreen", @"exitFullscreen", @"noDoubleTapToSeek"];
    NSArray *shortsBehaviorKeys = @[@"shortsOnlyMode", @"autoSkipShorts", @"hideShorts", @"shortsProgress", @"pinchToFullscreenShorts", @"shortsToRegular", @"resumeShorts"];
    NSArray *shortsUIKeys = @[@"hideShortsLogo", @"hideShortsSearch", @"hideShortsCamera", @"hideShortsMore", @"hideShortsSubscriptions", @"hideShortsLike", @"hideShortsDislike", @"hideShortsComments", @"hideShortsRemix", @"hideShortsShare", @"hideShortsAvatars", @"hideShortsThanks", @"hideShortsSource", @"hideShortsChannelName", @"hideShortsDescription", @"hideShortsAudioTrack", @"hideShortsPromoCards"];
    NSArray *downloadUIKeys = @[@"removeDownloadMenu", @"noPlayerDownloadButton", @"playerNoShare", @"playerNoSave", @"removeShareMenu"];
    NSArray *downloadToolKeys = @[@"copyVideoInfo", @"postManager", @"saveProfilePhoto", @"commentManager", @"fixAlbums", @"nativeShare"];
    NSArray *downloadKeys = [downloadUIKeys arrayByAddingObjectsFromArray:downloadToolKeys];
    NSArray *menuKeys = @[@"removePlayNext", @"removeWatchLaterMenu", @"removeSaveToPlaylistMenu", @"removeNotInterestedMenu", @"removeDontRecommendMenu", @"removeReportMenu"];
    NSArray *feedKeys = @[@"noContinueWatching", @"noSearchHistory", @"noRelatedWatchNexts"];
    NSArray *linkKeys = @[@"noLinkTracking", @"noShareChunk"];
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
            NSArray *controlKeys = [navbarKeys arrayByAddingObjectsFromArray:interfaceKeys];
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
                    return [NSString stringWithFormat:@"%lu tabs", (unsigned long)[[YTAGUserDefaults standardUserDefaults] currentActiveTabs].count];
                }
                selectBlock:^BOOL (YTSettingsCell *innerCell, NSUInteger innerArg1) {
                    NSMutableArray <YTSettingsSectionItem *> *tabRows = [NSMutableArray array];
                    [tabRows addObject:[self switchWithTitle:@"OpaqueBar" key:@"frostedPivot"]];
                    [tabRows addObject:[self switchWithTitle:@"RemoveLabels" key:@"removeLabels"]];
                    [tabRows addObject:[self switchWithTitle:@"RemoveIndicators" key:@"removeIndicators"]];
                    [tabRows addObject:[self pageItemWithTitle:@"Manage Tabs"
                        titleDescription:@"Drag tabs between active and inactive sections, or tap a row to toggle it."
                        summary:^NSString *() {
                            return [NSString stringWithFormat:@"%lu active", (unsigned long)[[YTAGUserDefaults standardUserDefaults] currentActiveTabs].count];
                        }
                        selectBlock:^BOOL (YTSettingsCell *manageCell, NSUInteger manageArg1) {
                            YTAGTabBarEditorController *editor = [[YTAGTabBarEditorController alloc] initWithSettingsViewController:settingsViewController
                                activeTabs:[[YTAGUserDefaults standardUserDefaults] currentActiveTabs]
                                allTabs:[self ytag_allTabs]
                                tabNames:[self ytag_tabNames]];
                            [settingsViewController pushViewController:editor];
                            return YES;
                        }]];
                    [tabRows addObject:[%c(YTSettingsSectionItem) itemWithTitle:nil titleDescription:LOC(@"HideLibraryFooter") accessibilityIdentifier:@"YTAfterglowSectionItem" detailTextBlock:nil selectBlock:nil]];

                    YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Tabbar") pickerSectionTitle:nil rows:tabRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                    [settingsViewController pushViewController:picker];
                    return YES;
                }]];

            [rows addObject:[self startupTabItemWithSettingsVC:settingsViewController]];
            [rows addObject:[self switchWithTitle:@"StartupAnimation" key:@"startupAnimation"]];
            [rows addObject:[self switchWithTitle:@"FloatingKeyboard" key:@"floatingKeyboard"]];

            if (isAdvanced) {
                [rows addObject:[self pageItemWithTitle:@"Legacy"
                    titleDescription:@"Experimental fallbacks for older YouTube UI behavior."
                    summary:^NSString *() {
                        return [self enabledSummaryForKeys:legacyKeys];
                    }
                    selectBlock:^BOOL (YTSettingsCell *legacyCell, NSUInteger legacyArg1) {
                        NSArray <YTSettingsSectionItem *> *legacyRows = @[
                            [self switchWithTitle:@"OldYTUI" key:@"oldYTUI"]
                        ];

                        YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:@"Legacy" pickerSectionTitle:nil rows:legacyRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                        [settingsViewController pushViewController:picker];
                        return YES;
                    }]];
            }

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
                    return @"17 curated";
                }
                selectBlock:^BOOL(YTSettingsCell *presetCell, NSUInteger presetArg1) {
                    NSMutableArray <YTSettingsSectionItem *> *presetRows = [NSMutableArray array];
                    [presetRows addObject:[self themeSectionHeaderWithTitle:@"Dark Themes" description:@"Richer palettes with more contrast and depth."]];
                    [self themeAddPresetRowWithName:@"OLED Dark" titleDescription:@"Pure black with sharp red accents." overlay:[UIColor whiteColor] tabIcons:[UIColor whiteColor] seekBar:[UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:1.0] bg:[UIColor blackColor] textP:[UIColor whiteColor] textS:[UIColor colorWithRed:0.65 green:0.65 blue:0.65 alpha:1.0] nav:[UIColor blackColor] accent:[UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:1.0] gradientStart:nil gradientEnd:nil toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Midnight Blue" titleDescription:@"Cool navy with bright blue controls." overlay:[UIColor colorWithRed:0.6 green:0.8 blue:1.0 alpha:1.0] tabIcons:[UIColor colorWithRed:0.4 green:0.7 blue:1.0 alpha:1.0] seekBar:[UIColor colorWithRed:0.2 green:0.5 blue:1.0 alpha:1.0] bg:[UIColor colorWithRed:0.05 green:0.05 blue:0.15 alpha:1.0] textP:[UIColor colorWithRed:0.85 green:0.9 blue:1.0 alpha:1.0] textS:[UIColor colorWithRed:0.5 green:0.6 blue:0.75 alpha:1.0] nav:[UIColor colorWithRed:0.08 green:0.08 blue:0.2 alpha:1.0] accent:[UIColor colorWithRed:0.2 green:0.5 blue:1.0 alpha:1.0] gradientStart:nil gradientEnd:nil toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Solarized Dark" titleDescription:@"Muted solarized tones with teal and gold." overlay:[UIColor colorWithRed:0.51 green:0.58 blue:0.59 alpha:1.0] tabIcons:[UIColor colorWithRed:0.51 green:0.58 blue:0.59 alpha:1.0] seekBar:[UIColor colorWithRed:0.52 green:0.60 blue:0.0 alpha:1.0] bg:[UIColor colorWithRed:0.0 green:0.17 blue:0.21 alpha:1.0] textP:[UIColor colorWithRed:0.93 green:0.91 blue:0.84 alpha:1.0] textS:[UIColor colorWithRed:0.51 green:0.58 blue:0.59 alpha:1.0] nav:[UIColor colorWithRed:0.03 green:0.21 blue:0.26 alpha:1.0] accent:[UIColor colorWithRed:0.15 green:0.55 blue:0.82 alpha:1.0] gradientStart:nil gradientEnd:nil toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Monokai" titleDescription:@"High-contrast editor greens and pinks." overlay:[UIColor colorWithRed:0.97 green:0.97 blue:0.95 alpha:1.0] tabIcons:[UIColor colorWithRed:0.65 green:0.89 blue:0.18 alpha:1.0] seekBar:[UIColor colorWithRed:0.98 green:0.15 blue:0.45 alpha:1.0] bg:[UIColor colorWithRed:0.15 green:0.16 blue:0.13 alpha:1.0] textP:[UIColor colorWithRed:0.97 green:0.97 blue:0.95 alpha:1.0] textS:[UIColor colorWithRed:0.46 green:0.44 blue:0.37 alpha:1.0] nav:[UIColor colorWithRed:0.2 green:0.2 blue:0.17 alpha:1.0] accent:[UIColor colorWithRed:0.40 green:0.85 blue:0.94 alpha:1.0] gradientStart:nil gradientEnd:nil toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Forest" titleDescription:@"Deep green with a calm natural feel." overlay:[UIColor colorWithRed:0.8 green:0.93 blue:0.8 alpha:1.0] tabIcons:[UIColor colorWithRed:0.4 green:0.75 blue:0.4 alpha:1.0] seekBar:[UIColor colorWithRed:0.3 green:0.7 blue:0.3 alpha:1.0] bg:[UIColor colorWithRed:0.06 green:0.1 blue:0.06 alpha:1.0] textP:[UIColor colorWithRed:0.85 green:0.95 blue:0.85 alpha:1.0] textS:[UIColor colorWithRed:0.5 green:0.65 blue:0.5 alpha:1.0] nav:[UIColor colorWithRed:0.08 green:0.14 blue:0.08 alpha:1.0] accent:[UIColor colorWithRed:0.3 green:0.7 blue:0.3 alpha:1.0] gradientStart:nil gradientEnd:nil toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Afterglow 1" titleDescription:@"Hot magenta and cyan vaporwave with loud neon bloom." overlay:[UIColor colorWithRed:1.00 green:0.72 blue:0.90 alpha:1.0] tabIcons:[UIColor colorWithRed:0.28 green:0.95 blue:1.00 alpha:1.0] seekBar:[UIColor colorWithRed:1.00 green:0.27 blue:0.75 alpha:1.0] bg:[UIColor colorWithRed:0.09 green:0.03 blue:0.16 alpha:1.0] textP:[UIColor colorWithRed:0.98 green:0.90 blue:0.99 alpha:1.0] textS:[UIColor colorWithRed:0.72 green:0.61 blue:0.82 alpha:1.0] nav:[UIColor colorWithRed:0.13 green:0.05 blue:0.20 alpha:1.0] accent:[UIColor colorWithRed:0.30 green:0.91 blue:1.00 alpha:1.0] gradientStart:[UIColor colorWithRed:0.18 green:0.03 blue:0.29 alpha:1.0] gradientEnd:[UIColor colorWithRed:0.94 green:0.27 blue:0.58 alpha:1.0] toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Afterglow 2" titleDescription:@"Sunset vapor tones with peach fire over electric violet." overlay:[UIColor colorWithRed:1.00 green:0.82 blue:0.71 alpha:1.0] tabIcons:[UIColor colorWithRed:1.00 green:0.55 blue:0.42 alpha:1.0] seekBar:[UIColor colorWithRed:1.00 green:0.48 blue:0.66 alpha:1.0] bg:[UIColor colorWithRed:0.11 green:0.05 blue:0.13 alpha:1.0] textP:[UIColor colorWithRed:1.00 green:0.94 blue:0.90 alpha:1.0] textS:[UIColor colorWithRed:0.79 green:0.67 blue:0.72 alpha:1.0] nav:[UIColor colorWithRed:0.17 green:0.08 blue:0.19 alpha:1.0] accent:[UIColor colorWithRed:0.41 green:0.89 blue:1.00 alpha:1.0] gradientStart:[UIColor colorWithRed:0.24 green:0.06 blue:0.24 alpha:1.0] gradientEnd:[UIColor colorWithRed:1.00 green:0.46 blue:0.28 alpha:1.0] toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Afterglow 3" titleDescription:@"Cyber dusk with deep indigo, laser cyan, and glossy pink chrome." overlay:[UIColor colorWithRed:0.89 green:0.79 blue:1.00 alpha:1.0] tabIcons:[UIColor colorWithRed:0.34 green:0.90 blue:1.00 alpha:1.0] seekBar:[UIColor colorWithRed:0.92 green:0.31 blue:1.00 alpha:1.0] bg:[UIColor colorWithRed:0.04 green:0.06 blue:0.16 alpha:1.0] textP:[UIColor colorWithRed:0.93 green:0.95 blue:1.00 alpha:1.0] textS:[UIColor colorWithRed:0.62 green:0.70 blue:0.89 alpha:1.0] nav:[UIColor colorWithRed:0.07 green:0.09 blue:0.20 alpha:1.0] accent:[UIColor colorWithRed:1.00 green:0.54 blue:0.72 alpha:1.0] gradientStart:[UIColor colorWithRed:0.07 green:0.08 blue:0.25 alpha:1.0] gradientEnd:[UIColor colorWithRed:0.62 green:0.12 blue:0.64 alpha:1.0] toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Afterglow 4" titleDescription:@"Jet-black cybergrid with neon green bloom, hot magenta sparks, and electric violet chrome." overlay:[UIColor colorWithRed:0.98 green:0.86 blue:0.95 alpha:1.0] tabIcons:[UIColor colorWithRed:0.20 green:1.00 blue:0.47 alpha:1.0] seekBar:[UIColor colorWithRed:1.00 green:0.20 blue:0.70 alpha:1.0] bg:[UIColor colorWithRed:0.02 green:0.02 blue:0.05 alpha:1.0] textP:[UIColor colorWithRed:0.96 green:0.96 blue:1.00 alpha:1.0] textS:[UIColor colorWithRed:0.67 green:0.64 blue:0.83 alpha:1.0] nav:[UIColor colorWithRed:0.05 green:0.05 blue:0.09 alpha:1.0] accent:[UIColor colorWithRed:0.55 green:0.27 blue:1.00 alpha:1.0] gradientStart:[UIColor colorWithRed:0.00 green:0.95 blue:0.40 alpha:1.0] gradientEnd:[UIColor colorWithRed:0.46 green:0.10 blue:0.96 alpha:1.0] toRows:presetRows settingsVC:settingsViewController];
                    [presetRows addObject:space];
                    [presetRows addObject:[self themeSectionHeaderWithTitle:@"Light Themes" description:@"Brighter looks that still feel deliberate and themed."]];
                    [self themeAddPresetRowWithName:@"Clean White" titleDescription:@"Minimal white surfaces with blue accents." overlay:[UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1.0] tabIcons:[UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:1.0] seekBar:[UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0] bg:[UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:1.0] textP:[UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:1.0] textS:[UIColor colorWithRed:0.45 green:0.45 blue:0.45 alpha:1.0] nav:[UIColor colorWithRed:0.97 green:0.97 blue:0.97 alpha:1.0] accent:[UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0] gradientStart:nil gradientEnd:nil toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Warm Sand" titleDescription:@"Cream tones with soft amber highlights." overlay:[UIColor colorWithRed:0.45 green:0.35 blue:0.25 alpha:1.0] tabIcons:[UIColor colorWithRed:0.5 green:0.38 blue:0.25 alpha:1.0] seekBar:[UIColor colorWithRed:0.85 green:0.55 blue:0.2 alpha:1.0] bg:[UIColor colorWithRed:0.98 green:0.96 blue:0.91 alpha:1.0] textP:[UIColor colorWithRed:0.2 green:0.15 blue:0.1 alpha:1.0] textS:[UIColor colorWithRed:0.5 green:0.42 blue:0.35 alpha:1.0] nav:[UIColor colorWithRed:0.95 green:0.92 blue:0.85 alpha:1.0] accent:[UIColor colorWithRed:0.85 green:0.55 blue:0.2 alpha:1.0] gradientStart:nil gradientEnd:nil toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Ocean Breeze" titleDescription:@"Light blue surfaces with teal energy." overlay:[UIColor colorWithRed:0.15 green:0.4 blue:0.55 alpha:1.0] tabIcons:[UIColor colorWithRed:0.1 green:0.45 blue:0.6 alpha:1.0] seekBar:[UIColor colorWithRed:0.0 green:0.6 blue:0.7 alpha:1.0] bg:[UIColor colorWithRed:0.94 green:0.97 blue:1.0 alpha:1.0] textP:[UIColor colorWithRed:0.1 green:0.15 blue:0.2 alpha:1.0] textS:[UIColor colorWithRed:0.35 green:0.45 blue:0.55 alpha:1.0] nav:[UIColor colorWithRed:0.9 green:0.94 blue:0.98 alpha:1.0] accent:[UIColor colorWithRed:0.0 green:0.55 blue:0.65 alpha:1.0] gradientStart:nil gradientEnd:nil toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Rose Gold" titleDescription:@"Soft blush tones with warm chrome." overlay:[UIColor colorWithRed:0.6 green:0.35 blue:0.35 alpha:1.0] tabIcons:[UIColor colorWithRed:0.7 green:0.4 blue:0.4 alpha:1.0] seekBar:[UIColor colorWithRed:0.85 green:0.45 blue:0.5 alpha:1.0] bg:[UIColor colorWithRed:1.0 green:0.95 blue:0.93 alpha:1.0] textP:[UIColor colorWithRed:0.25 green:0.15 blue:0.15 alpha:1.0] textS:[UIColor colorWithRed:0.55 green:0.4 blue:0.4 alpha:1.0] nav:[UIColor colorWithRed:0.95 green:0.88 blue:0.86 alpha:1.0] accent:[UIColor colorWithRed:0.85 green:0.45 blue:0.5 alpha:1.0] gradientStart:nil gradientEnd:nil toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Afterglow Light 1" titleDescription:@"Candyglass daylight with a real lilac body color and aqua chrome." overlay:[UIColor colorWithRed:0.55 green:0.19 blue:0.54 alpha:1.0] tabIcons:[UIColor colorWithRed:0.03 green:0.72 blue:0.82 alpha:1.0] seekBar:[UIColor colorWithRed:0.98 green:0.33 blue:0.69 alpha:1.0] bg:[UIColor colorWithRed:0.97 green:0.84 blue:1.00 alpha:1.0] textP:[UIColor colorWithRed:0.24 green:0.08 blue:0.33 alpha:1.0] textS:[UIColor colorWithRed:0.46 green:0.27 blue:0.58 alpha:1.0] nav:[UIColor colorWithRed:0.93 green:0.76 blue:1.00 alpha:1.0] accent:[UIColor colorWithRed:0.08 green:0.80 blue:0.84 alpha:1.0] gradientStart:[UIColor colorWithRed:1.00 green:0.84 blue:0.93 alpha:1.0] gradientEnd:[UIColor colorWithRed:0.73 green:0.95 blue:1.00 alpha:1.0] toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Afterglow Light 2" titleDescription:@"Apricot sunset with coral punch, hot pink sparks, and blue contrast." overlay:[UIColor colorWithRed:0.60 green:0.24 blue:0.14 alpha:1.0] tabIcons:[UIColor colorWithRed:0.97 green:0.44 blue:0.12 alpha:1.0] seekBar:[UIColor colorWithRed:1.00 green:0.31 blue:0.44 alpha:1.0] bg:[UIColor colorWithRed:1.00 green:0.86 blue:0.72 alpha:1.0] textP:[UIColor colorWithRed:0.30 green:0.12 blue:0.09 alpha:1.0] textS:[UIColor colorWithRed:0.58 green:0.30 blue:0.28 alpha:1.0] nav:[UIColor colorWithRed:1.00 green:0.79 blue:0.64 alpha:1.0] accent:[UIColor colorWithRed:0.28 green:0.67 blue:1.00 alpha:1.0] gradientStart:[UIColor colorWithRed:1.00 green:0.90 blue:0.69 alpha:1.0] gradientEnd:[UIColor colorWithRed:1.00 green:0.68 blue:0.73 alpha:1.0] toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Afterglow Light 3" titleDescription:@"Mint arcade glass with louder teal, berry pink, and violet energy." overlay:[UIColor colorWithRed:0.13 green:0.40 blue:0.40 alpha:1.0] tabIcons:[UIColor colorWithRed:0.00 green:0.68 blue:0.61 alpha:1.0] seekBar:[UIColor colorWithRed:0.98 green:0.37 blue:0.58 alpha:1.0] bg:[UIColor colorWithRed:0.80 green:1.00 blue:0.91 alpha:1.0] textP:[UIColor colorWithRed:0.08 green:0.22 blue:0.24 alpha:1.0] textS:[UIColor colorWithRed:0.28 green:0.47 blue:0.49 alpha:1.0] nav:[UIColor colorWithRed:0.72 green:0.98 blue:0.89 alpha:1.0] accent:[UIColor colorWithRed:0.41 green:0.30 blue:0.95 alpha:1.0] gradientStart:[UIColor colorWithRed:0.82 green:1.00 blue:0.94 alpha:1.0] gradientEnd:[UIColor colorWithRed:0.93 green:0.84 blue:1.00 alpha:1.0] toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Afterglow Light 4" titleDescription:@"Sky chrome with icy blue glass, coral sparks, and violet-pop contrast." overlay:[UIColor colorWithRed:0.21 green:0.31 blue:0.66 alpha:1.0] tabIcons:[UIColor colorWithRed:0.17 green:0.50 blue:1.00 alpha:1.0] seekBar:[UIColor colorWithRed:1.00 green:0.40 blue:0.47 alpha:1.0] bg:[UIColor colorWithRed:0.82 green:0.91 blue:1.00 alpha:1.0] textP:[UIColor colorWithRed:0.11 green:0.18 blue:0.39 alpha:1.0] textS:[UIColor colorWithRed:0.29 green:0.39 blue:0.63 alpha:1.0] nav:[UIColor colorWithRed:0.74 green:0.84 blue:1.00 alpha:1.0] accent:[UIColor colorWithRed:0.84 green:0.31 blue:0.68 alpha:1.0] gradientStart:[UIColor colorWithRed:0.82 green:0.93 blue:1.00 alpha:1.0] gradientEnd:[UIColor colorWithRed:0.92 green:0.84 blue:1.00 alpha:1.0] toRows:presetRows settingsVC:settingsViewController];

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
                    if ([[YTAGUserDefaults standardUserDefaults] objectForKey:@"theme_gradientStart"] || [[YTAGUserDefaults standardUserDefaults] objectForKey:@"theme_gradientEnd"]) {
                        [gradientRows addObject:space];
                        [gradientRows addObject:[%c(YTSettingsSectionItem) itemWithTitle:@"Turn Off Gradient"
                            titleDescription:@"Remove both gradient colors and go back to a flat background."
                            accessibilityIdentifier:@"YTAfterglowSectionItem"
                            detailTextBlock:^NSString *() {
                                return [self themeGradientSummary];
                            }
                            selectBlock:^BOOL(YTSettingsCell *resetCell, NSUInteger resetArg1) {
                                [[YTAGUserDefaults standardUserDefaults] removeObjectForKey:@"theme_gradientStart"];
                                [[YTAGUserDefaults standardUserDefaults] removeObjectForKey:@"theme_gradientEnd"];
                                ytag_clearThemeCache();
                                ytag_refreshSettingsHierarchy(settingsViewController);
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
                accessibilityIdentifier:@"YTAfterglowSectionItem"
                detailTextBlock:^NSString *() {
                    return @"Restart required";
                }
                selectBlock:^BOOL(YTSettingsCell *resetCell, NSUInteger resetArg1) {
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:LOC(@"ResetAllColors") message:@"This removes every preset, custom color, and gradient value in Themes. Restart YouTube to fully return to the default look." preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:LOC(@"ResetAndRestart") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
                        NSArray *keys = @[@"theme_overlayButtons", @"theme_tabBarIcons", @"theme_seekBar", @"theme_background", @"theme_textPrimary", @"theme_textSecondary", @"theme_navBar", @"theme_accent", @"theme_gradientStart", @"theme_gradientEnd", @"theme_glowEnabled"];
                        for (NSString *key in keys) {
                            [[YTAGUserDefaults standardUserDefaults] removeObjectForKey:key];
                        }
                        ytag_clearThemeCache();
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
                        [self switchWithTitle:@"RememberCaptionState" key:@"rememberCaptionState"],
                        [self switchWithTitle:@"RememberLoopMode" key:@"rememberLoop"],
                        [self switchWithTitle:@"NoContentWarning" key:@"noContentWarning"],
                        [self switchWithTitle:@"ClassicQuality" key:@"classicQuality"],
                        [self switchWithTitle:@"TapToSeek" key:@"tapToSeek"],
                        [self switchWithTitle:@"DontSnap2Chapter" key:@"dontSnapToChapter"],
                        [self switchWithTitle:@"NoTwoFingerSnapToChapter" key:@"noTwoFingerSnapToChapter"],
                        [self switchWithTitle:@"PauseOnOverlay" key:@"pauseOnOverlay"],
                        [self switchWithTitle:@"RedProgressBar" key:@"redProgressBar"],
                        [self switchWithTitle:@"NoPlayerRemixButton" key:@"noPlayerRemixButton"],
                        [self switchWithTitle:@"NoPlayerClipButton" key:@"noPlayerClipButton"],
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
                            [self switchWithTitle:@"ShowPlayerShareButton" key:@"showPlayerShareButton"],
                            [self switchWithTitle:@"ShowPlayerSaveButton" key:@"showPlayerSaveButton"],
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
                            [self switchWithTitle:@"DisableAmbientMode" key:@"disableAmbientMode"],
                            [self switchWithTitle:@"VideoEndTime" key:@"videoEndTime"],
                            [self switchWithTitle:@"24hrFormat" key:@"24hrFormat"],
                            [self switchWithTitle:@"HideHeatwaves" key:@"hideHeatwaves"],
                            [self switchWithTitle:@"NoContinueWatchingPrompt" key:@"noContinueWatchingPrompt"]
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
            [rows addObject:[self switchWithTitle:@"PlayerNoShare" key:@"playerNoShare"]];
            [rows addObject:[self switchWithTitle:@"PlayerNoSave" key:@"playerNoSave"]];
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
            NSArray *feedContentKeys = [[[feedKeys arrayByAddingObjectsFromArray:linkKeys] arrayByAddingObjectsFromArray:menuKeys] arrayByAddingObjectsFromArray:commentKeys];
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

            [rows addObject:[self pageItemWithTitle:@"Links"
                titleDescription:@"Open cleaner links and strip YouTube's extra share parameters."
                summary:^NSString *() {
                    return [self enabledSummaryForKeys:linkKeys];
                }
                selectBlock:^BOOL (YTSettingsCell *linksCell, NSUInteger linksArg1) {
                    NSArray <YTSettingsSectionItem *> *linkRows = @[
                        [self switchWithTitle:@"NoLinkTracking" key:@"noLinkTracking"],
                        [self switchWithTitle:@"NoShareChunk" key:@"noShareChunk"]
                    ];

                    YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:@"Links" pickerSectionTitle:nil rows:linkRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
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

    YTSettingsSectionItem *support = [%c(YTSettingsSectionItem) itemWithTitle:LOC(@"SupportDevelopment") accessibilityIdentifier:@"YTAfterglowSectionItem" detailTextBlock:^NSString *() { return @"♡"; } selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
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
                [%c(YTSettingsSectionItem) itemWithTitle:LOC(@"ClearCache") titleDescription:nil accessibilityIdentifier:@"YTAfterglowSectionItem" detailTextBlock:^NSString *() { return GetCacheSize(); } selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        NSString *cachePath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
                        [[NSFileManager defaultManager] removeItemAtPath:cachePath error:nil];
                    });

                    [[%c(YTToastResponderEvent) eventWithMessage:LOC(@"Done") firstResponder:[self parentResponder]] send];

                    return YES;
                }],

                [%c(YTSettingsSectionItem) itemWithTitle:LOC(@"ResetSettings") titleDescription:nil accessibilityIdentifier:@"YTAfterglowSectionItem" detailTextBlock:nil selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
                    YTAlertView *alertView = [%c(YTAlertView) confirmationDialogWithAction:^{
                        [YTAGUserDefaults resetUserDefaults];

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
    isNew ? [settingsViewController setSectionItems:sectionItems forCategory:YTAfterglowSection title:@"YouTube Afterglow" icon:nil titleDescription:nil headerHidden:NO]
          : [settingsViewController setSectionItems:sectionItems forCategory:YTAfterglowSection title:@"YouTube Afterglow" titleDescription:nil headerHidden:NO];

}

- (void)updateSectionForCategory:(NSUInteger)category withEntry:(id)entry {
    if (category == YTAfterglowSection) {
        [self updateYTAfterglowSectionWithEntry:entry];
        return;
    } %orig;
}

%new
- (UIImage *)resizedImageNamed:(NSString *)iconName {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(32, 32)];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
        UIView *imageView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 32, 32)];
        UIImageView *iconImageView = [[UIImageView alloc] initWithImage:[UIImage imageWithContentsOfFile:[NSBundle.ytag_defaultBundle pathForResource:iconName ofType:@"png"]]];
        iconImageView.contentMode = UIViewContentModeScaleAspectFit;
        iconImageView.clipsToBounds = YES;
        iconImageView.frame = imageView.bounds;

        [imageView addSubview:iconImageView];
        [imageView.layer renderInContext:rendererContext.CGContext];
    }];

    return image;
}
%end
