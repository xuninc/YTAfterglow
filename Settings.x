#import "YTAfterglow.h"
#import <objc/runtime.h>

extern void ytag_clearThemeCache(void);
static UIViewController *ytag_viewControllerForResponder(UIResponder *responder);
static void ytag_reloadSettingsController(UIViewController *controller);
static void ytag_refreshSettingsHierarchy(UIViewController *controller);
static void ytag_refreshSettingsFromCell(YTSettingsCell *cell);
static void ytag_presentThemeRefreshAlert(UIViewController *presenter, NSString *title, NSString *message);
static NSString *ytag_localizedStringOrFallback(NSString *key, NSString *fallback);
static NSString *ytag_settingDescriptionForKey(NSString *key);
static NSArray<YTSettingsSectionItem *> *ytag_pickerRowsForController(UIViewController *controller);
static UICollectionView *ytag_findCollectionViewInView(UIView *view);
static YTSettingsSectionItem *ytag_firstItemWithTitle(NSArray<YTSettingsSectionItem *> *items, NSString *title);
static NSInteger ytag_indexOfItemWithTitle(NSArray<YTSettingsSectionItem *> *items, NSString *title);
static void ytag_highlightPickerRowIfNeeded(UIViewController *controller, NSInteger attempt);

@class YTAGSettingsSearchEntry;
static BOOL ytag_openSettingsSearchEntry(YTSettingsViewController *settingsViewController, YTAGSettingsSearchEntry *entry);

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
- (YTAGSettingsSearchEntry *)ytag_searchEntryWithTitle:(NSString *)title description:(NSString *)description path:(NSArray<NSString *> *)path targetTitle:(NSString *)targetTitle aliases:(NSArray<NSString *> *)aliases;
- (YTAGSettingsSearchEntry *)ytag_searchPageEntryWithTitle:(NSString *)title description:(NSString *)description path:(NSArray<NSString *> *)path aliases:(NSArray<NSString *> *)aliases;
- (void)ytag_addSearchEntries:(NSMutableArray<YTAGSettingsSearchEntry *> *)entries forSettingKeys:(NSArray<NSString *> *)keys path:(NSArray<NSString *> *)path aliasesByKey:(NSDictionary<NSString *, NSArray<NSString *> *> *)aliasesByKey;
- (void)ytag_addSearchEntries:(NSMutableArray<YTAGSettingsSearchEntry *> *)entries forLiteralTitles:(NSArray<NSString *> *)titles path:(NSArray<NSString *> *)path descriptionsByTitle:(NSDictionary<NSString *, NSString *> *)descriptionsByTitle aliasesByTitle:(NSDictionary<NSString *, NSArray<NSString *> *> *)aliasesByTitle;
- (NSArray<YTAGSettingsSearchEntry *> *)ytag_settingsSearchEntriesForAdvancedMode:(BOOL)isAdvanced;
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
static char kYTAGPickerRowsAssociationKey;
static char kYTAGPickerHighlightIndexAssociationKey;

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

static NSString *ytag_localizedStringOrFallback(NSString *key, NSString *fallback) {
    if (!key.length) return fallback ?: @"";

    NSString *localized = LOC(key);
    if (localized.length == 0 || [localized isEqualToString:key]) {
        return fallback ?: key;
    }

    return localized;
}

static NSString *ytag_settingDescriptionForKey(NSString *key) {
    if (!key.length) return nil;

    NSString *descriptionKey = [NSString stringWithFormat:@"%@Desc", key];
    NSString *description = LOC(descriptionKey);
    if (description.length == 0 || [description isEqualToString:descriptionKey]) {
        return nil;
    }

    return description;
}

static NSArray<YTSettingsSectionItem *> *ytag_pickerRowsForController(UIViewController *controller) {
    return objc_getAssociatedObject(controller, &kYTAGPickerRowsAssociationKey);
}

static UICollectionView *ytag_findCollectionViewInView(UIView *view) {
    if (!view) return nil;
    if ([view isKindOfClass:[UICollectionView class]]) {
        return (UICollectionView *)view;
    }

    for (UIView *subview in view.subviews) {
        UICollectionView *collectionView = ytag_findCollectionViewInView(subview);
        if (collectionView) return collectionView;
    }

    return nil;
}

static YTSettingsSectionItem *ytag_firstItemWithTitle(NSArray<YTSettingsSectionItem *> *items, NSString *title) {
    if (!title.length) return nil;

    for (YTSettingsSectionItem *item in items) {
        if ([item.title isEqualToString:title]) {
            return item;
        }
    }

    return nil;
}

static NSInteger ytag_indexOfItemWithTitle(NSArray<YTSettingsSectionItem *> *items, NSString *title) {
    if (!title.length) return NSNotFound;

    for (NSUInteger index = 0; index < items.count; index++) {
        if ([items[index].title isEqualToString:title]) {
            return (NSInteger)index;
        }
    }

    return NSNotFound;
}

static void ytag_flashSettingsCell(UICollectionViewCell *cell) {
    if (!cell) return;

    UIColor *tintColor = [YTAGAfterglowTintColor() colorWithAlphaComponent:0.16];
    UIColor *borderColor = YTAGAfterglowTintColor();
    UIView *targetView = cell.contentView ?: cell;
    UIColor *originalBackgroundColor = targetView.backgroundColor;
    CGFloat originalBorderWidth = cell.layer.borderWidth;
    CGColorRef originalBorderColor = cell.layer.borderColor;
    CGFloat originalCornerRadius = cell.layer.cornerRadius;

    cell.layer.cornerRadius = 12.0;
    cell.layer.borderWidth = 1.5;
    cell.layer.borderColor = borderColor.CGColor;

    [UIView animateWithDuration:0.18 animations:^{
        targetView.backgroundColor = tintColor;
    } completion:^(__unused BOOL finished) {
        [UIView animateWithDuration:0.45 delay:0.85 options:UIViewAnimationOptionCurveEaseOut animations:^{
            targetView.backgroundColor = originalBackgroundColor;
            cell.layer.borderWidth = originalBorderWidth;
            cell.layer.borderColor = originalBorderColor;
            cell.layer.cornerRadius = originalCornerRadius;
        } completion:nil];
    }];
}

static void ytag_highlightPickerRowIfNeeded(UIViewController *controller, NSInteger attempt) {
    NSNumber *highlightIndex = objc_getAssociatedObject(controller, &kYTAGPickerHighlightIndexAssociationKey);
    if (!highlightIndex) return;

    UICollectionView *collectionView = ytag_findCollectionViewInView(controller.view);
    if (!collectionView) {
        if (attempt < 6) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                ytag_highlightPickerRowIfNeeded(controller, attempt + 1);
            });
        }
        return;
    }

    NSInteger row = highlightIndex.integerValue;
    if (row < 0 || row >= [collectionView numberOfItemsInSection:0]) {
        if (attempt < 6) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                ytag_highlightPickerRowIfNeeded(controller, attempt + 1);
            });
        }
        return;
    }

    NSIndexPath *indexPath = [NSIndexPath indexPathForItem:row inSection:0];
    [collectionView layoutIfNeeded];
    [collectionView scrollToItemAtIndexPath:indexPath atScrollPosition:UICollectionViewScrollPositionCenteredVertically animated:NO];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UICollectionViewCell *cell = [collectionView cellForItemAtIndexPath:indexPath];
        if (!cell && attempt < 6) {
            ytag_highlightPickerRowIfNeeded(controller, attempt + 1);
            return;
        }

        ytag_flashSettingsCell(cell);
        objc_setAssociatedObject(controller, &kYTAGPickerHighlightIndexAssociationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
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

@interface YTAGSettingsSearchEntry : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *entryDescription;
@property (nonatomic, copy) NSString *breadcrumb;
@property (nonatomic, copy) NSString *searchText;
@property (nonatomic, copy) NSArray<NSString *> *pathTitles;
@property (nonatomic, copy) NSString *targetTitle;
- (instancetype)initWithTitle:(NSString *)title description:(NSString *)description breadcrumb:(NSString *)breadcrumb searchText:(NSString *)searchText pathTitles:(NSArray<NSString *> *)pathTitles targetTitle:(NSString *)targetTitle;
@end

@implementation YTAGSettingsSearchEntry

- (instancetype)initWithTitle:(NSString *)title description:(NSString *)description breadcrumb:(NSString *)breadcrumb searchText:(NSString *)searchText pathTitles:(NSArray<NSString *> *)pathTitles targetTitle:(NSString *)targetTitle {
    self = [super init];
    if (self) {
        _title = [title copy];
        _entryDescription = [description copy];
        _breadcrumb = [breadcrumb copy];
        _searchText = [[searchText lowercaseString] copy];
        _pathTitles = [pathTitles copy] ?: @[];
        _targetTitle = [targetTitle copy];
    }
    return self;
}

@end

@interface YTAGSettingsSearchController : UITableViewController <UISearchResultsUpdating>
@property (nonatomic, weak) YTSettingsViewController *settingsViewController;
@property (nonatomic, copy) NSArray<YTAGSettingsSearchEntry *> *allEntries;
@property (nonatomic, copy) NSArray<YTAGSettingsSearchEntry *> *filteredEntries;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, assign) BOOL didFocusSearchBar;
- (instancetype)initWithSettingsViewController:(YTSettingsViewController *)settingsViewController entries:(NSArray<YTAGSettingsSearchEntry *> *)entries;
@end

@implementation YTAGSettingsSearchController

- (instancetype)initWithSettingsViewController:(YTSettingsViewController *)settingsViewController entries:(NSArray<YTAGSettingsSearchEntry *> *)entries {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _settingsViewController = settingsViewController;
        _allEntries = [entries copy] ?: @[];
        _filteredEntries = _allEntries;
        self.title = ytag_localizedStringOrFallback(@"SearchSettings", @"Search Settings");
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.tableView.tintColor = YTAGAfterglowTintColor();
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    UISearchController *searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    searchController.obscuresBackgroundDuringPresentation = NO;
    searchController.searchResultsUpdater = self;
    searchController.searchBar.placeholder = ytag_localizedStringOrFallback(@"SearchSettingsPlaceholder", @"Find a setting or category");
    self.navigationItem.searchController = searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    self.searchController = searchController;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    if (!self.didFocusSearchBar) {
        self.didFocusSearchBar = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.searchController.searchBar becomeFirstResponder];
        });
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredEntries.count == 0 ? 1 : self.filteredEntries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"YTAGSettingsSearchCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    }

    if (self.filteredEntries.count == 0) {
        cell.textLabel.text = ytag_localizedStringOrFallback(@"SearchSettingsNoResults", @"No matching settings");
        cell.detailTextLabel.text = ytag_localizedStringOrFallback(@"SearchSettingsNoResultsDesc", @"Try a broader word like player, overlay, or comments.");
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.detailTextLabel.textColor = [UIColor tertiaryLabelColor];
        return cell;
    }

    YTAGSettingsSearchEntry *entry = self.filteredEntries[indexPath.row];
    cell.textLabel.text = entry.title;
    cell.textLabel.textColor = [UIColor labelColor];

    NSMutableArray<NSString *> *detailParts = [NSMutableArray array];
    if (entry.breadcrumb.length) [detailParts addObject:entry.breadcrumb];
    if (entry.entryDescription.length) [detailParts addObject:entry.entryDescription];
    cell.detailTextLabel.text = [detailParts componentsJoinedByString:@" • "];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.filteredEntries.count == 0) return;

    YTAGSettingsSearchEntry *entry = self.filteredEntries[indexPath.row];
    [self.searchController setActive:NO];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (ytag_openSettingsSearchEntry(self.settingsViewController, entry)) return;

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:ytag_localizedStringOrFallback(@"Warning", @"Warning")
                                                                       message:ytag_localizedStringOrFallback(@"SearchSettingsOpenFailed", @"That setting could not be opened right now.")
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = [[[searchController.searchBar.text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString] copy];
    if (query.length == 0) {
        self.filteredEntries = self.allEntries;
        [self.tableView reloadData];
        return;
    }

    NSArray<NSString *> *tokens = [[query componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *value, __unused NSDictionary *bindings) {
        return value.length > 0;
    }]];

    NSMutableArray<YTAGSettingsSearchEntry *> *matches = [NSMutableArray array];
    for (YTAGSettingsSearchEntry *entry in self.allEntries) {
        BOOL matchesAllTokens = YES;
        for (NSString *token in tokens) {
            if ([entry.searchText rangeOfString:token].location == NSNotFound) {
                matchesAllTokens = NO;
                break;
            }
        }

        if (matchesAllTokens) {
            [matches addObject:entry];
        }
    }

    self.filteredEntries = matches;
    [self.tableView reloadData];
}

@end

static BOOL ytag_openSettingsSearchEntry(YTSettingsViewController *settingsViewController, YTAGSettingsSearchEntry *entry) {
    if (!settingsViewController || !entry) return NO;

    UINavigationController *navigationController = settingsViewController.navigationController;
    if (!navigationController) return NO;

    [navigationController popToViewController:settingsViewController animated:NO];
    [settingsViewController reloadData];

    NSArray<YTSettingsSectionItem *> *currentItems = [settingsViewController settingsSectionControllers][@(YTAfterglowSection)].items;
    UIViewController *currentController = settingsViewController;

    for (NSString *pathTitle in entry.pathTitles) {
        YTSettingsSectionItem *item = ytag_firstItemWithTitle(currentItems, pathTitle);
        if (!item || !item.selectBlock) return NO;

        item.selectBlock(nil, 0);
        currentController = navigationController.topViewController;
        currentItems = ytag_pickerRowsForController(currentController);
    }

    if (entry.targetTitle.length > 0) {
        NSInteger row = ytag_indexOfItemWithTitle(currentItems, entry.targetTitle);
        if (row == NSNotFound) return NO;

        objc_setAssociatedObject(currentController, &kYTAGPickerHighlightIndexAssociationKey, @(row), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        ytag_highlightPickerRowIfNeeded(currentController, 0);
    }

    return YES;
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

%hook YTSettingsPickerViewController
- (instancetype)initWithNavTitle:(NSString *)navTitle pickerSectionTitle:(NSString *)pickerSectionTitle rows:(NSArray *)rows selectedItemIndex:(NSUInteger)selectedItemIndex parentResponder:(id)parentResponder {
    YTSettingsPickerViewController *controller = %orig;
    objc_setAssociatedObject(controller, &kYTAGPickerRowsAssociationKey, rows, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return controller;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    ytag_highlightPickerRowIfNeeded(self, 0);
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

#pragma mark - Search Helpers

%new
- (YTAGSettingsSearchEntry *)ytag_searchEntryWithTitle:(NSString *)title description:(NSString *)description path:(NSArray<NSString *> *)path targetTitle:(NSString *)targetTitle aliases:(NSArray<NSString *> *)aliases {
    NSArray<NSString *> *breadcrumbParts = path ?: @[];
    if (!targetTitle.length && breadcrumbParts.count > 0) {
        breadcrumbParts = [breadcrumbParts subarrayWithRange:NSMakeRange(0, breadcrumbParts.count - 1)];
    }

    NSString *breadcrumb = breadcrumbParts.count > 0 ? [breadcrumbParts componentsJoinedByString:@" > "] : @"YouTube Afterglow";

    NSMutableArray<NSString *> *searchParts = [NSMutableArray array];
    if (title.length) [searchParts addObject:title];
    if (description.length) [searchParts addObject:description];
    if (breadcrumb.length) [searchParts addObject:breadcrumb];
    if (aliases.count > 0) [searchParts addObjectsFromArray:aliases];

    return [[YTAGSettingsSearchEntry alloc] initWithTitle:title
                                              description:description
                                               breadcrumb:breadcrumb
                                               searchText:[searchParts componentsJoinedByString:@" "]
                                                pathTitles:path
                                               targetTitle:targetTitle];
}

%new
- (YTAGSettingsSearchEntry *)ytag_searchPageEntryWithTitle:(NSString *)title description:(NSString *)description path:(NSArray<NSString *> *)path aliases:(NSArray<NSString *> *)aliases {
    return [self ytag_searchEntryWithTitle:title description:description path:path targetTitle:nil aliases:aliases];
}

%new
- (void)ytag_addSearchEntries:(NSMutableArray<YTAGSettingsSearchEntry *> *)entries forSettingKeys:(NSArray<NSString *> *)keys path:(NSArray<NSString *> *)path aliasesByKey:(NSDictionary<NSString *,NSArray<NSString *> *> *)aliasesByKey {
    for (NSString *key in keys) {
        NSString *title = ytag_localizedStringOrFallback(key, key);
        NSString *description = ytag_settingDescriptionForKey(key);

        NSMutableArray<NSString *> *aliases = [NSMutableArray arrayWithObject:key];
        NSArray<NSString *> *extraAliases = aliasesByKey[key];
        if (extraAliases.count > 0) [aliases addObjectsFromArray:extraAliases];

        [entries addObject:[self ytag_searchEntryWithTitle:title
                                               description:description
                                                      path:path
                                               targetTitle:title
                                                   aliases:aliases]];
    }
}

%new
- (void)ytag_addSearchEntries:(NSMutableArray<YTAGSettingsSearchEntry *> *)entries forLiteralTitles:(NSArray<NSString *> *)titles path:(NSArray<NSString *> *)path descriptionsByTitle:(NSDictionary<NSString *,NSString *> *)descriptionsByTitle aliasesByTitle:(NSDictionary<NSString *,NSArray<NSString *> *> *)aliasesByTitle {
    for (NSString *title in titles) {
        [entries addObject:[self ytag_searchEntryWithTitle:title
                                               description:descriptionsByTitle[title]
                                                      path:path
                                               targetTitle:title
                                                   aliases:aliasesByTitle[title]]];
    }
}

%new
- (NSArray<YTAGSettingsSearchEntry *> *)ytag_settingsSearchEntriesForAdvancedMode:(BOOL)isAdvanced {
    NSMutableArray<YTAGSettingsSearchEntry *> *entries = [NSMutableArray array];

    NSString *adsTitle = LOC(@"Ads");
    NSString *interfaceTitle = LOC(@"Interface");
    NSString *privacyTitle = ytag_localizedStringOrFallback(@"Privacy", @"Privacy");
    NSString *navbarTitle = LOC(@"Navbar");
    NSString *tabbarTitle = LOC(@"Tabbar");
    NSString *legacyTitle = @"Legacy";
    NSString *themesTitle = @"Themes";
    NSString *presetsTitle = LOC(@"Presets");
    NSString *customColorsTitle = LOC(@"CustomColors");
    NSString *gradientTitle = LOC(@"Gradient");
    NSString *playerTitle = LOC(@"Player");
    NSString *playbackTitle = @"Playback";
    NSString *controlsTitle = @"Controls";
    NSString *actionBarTitle = @"Action Bar";
    NSString *menusTitle = @"Menus";
    NSString *miniplayerTitle = @"Miniplayer";
    NSString *overlayTitle = LOC(@"Overlay");
    NSString *shortsTitle = LOC(@"Shorts");
    NSString *layoutButtonsTitle = @"Layout & Buttons";
    NSString *downloadsTitle = LOC(@"Downloads");
    NSString *extrasTitle = @"Extras";
    NSString *feedTitle = @"Feed";
    NSString *commentsTitle = @"Comments";
    NSString *aboutTitle = LOC(@"About");
    NSString *creditsTitle = LOC(@"Credits");

    [entries addObject:[self ytag_searchPageEntryWithTitle:adsTitle description:@"Remove ads and promotional clutter." path:@[adsTitle] aliases:@[@"sponsored", @"promotions"]]];
    [entries addObject:[self ytag_searchPageEntryWithTitle:interfaceTitle description:@"App chrome, tabs, startup, and input behavior." path:@[interfaceTitle] aliases:@[@"navigation", @"tab bar", @"keyboard"]]];
    [entries addObject:[self ytag_searchPageEntryWithTitle:privacyTitle description:@"Search privacy, redirect cleanup, and cleaner shared links." path:@[privacyTitle] aliases:@[@"privacy", @"tracking", @"search history", @"shared links"]]];
    [entries addObject:[self ytag_searchPageEntryWithTitle:navbarTitle description:@"Top bar buttons and header presentation." path:@[interfaceTitle, navbarTitle] aliases:@[@"top bar", @"header"]]];
    [entries addObject:[self ytag_searchPageEntryWithTitle:tabbarTitle description:@"Visible tabs, labels, indicators, and bar styling." path:@[interfaceTitle, tabbarTitle] aliases:@[@"tabs", @"pivot bar"]]];
    if (isAdvanced) {
        [entries addObject:[self ytag_searchPageEntryWithTitle:legacyTitle description:@"Experimental fallbacks for older YouTube UI behavior." path:@[interfaceTitle, legacyTitle] aliases:@[@"old youtube", @"compatibility"]]];
    }

    [entries addObject:[self ytag_searchPageEntryWithTitle:themesTitle description:@"Curated themes, custom colors, gradients, and polish." path:@[themesTitle] aliases:@[@"appearance", @"colors"]]];
    [entries addObject:[self ytag_searchPageEntryWithTitle:presetsTitle description:@"Complete looks for the whole app, grouped into dark and light palettes." path:@[themesTitle, presetsTitle] aliases:@[@"theme presets", @"afterglow themes"]]];
    [entries addObject:[self ytag_searchPageEntryWithTitle:customColorsTitle description:@"Fine-tune the exact surfaces and text colors the theme engine touches." path:@[themesTitle, customColorsTitle] aliases:@[@"theme colors", @"color overrides"]]];
    [entries addObject:[self ytag_searchPageEntryWithTitle:gradientTitle description:@"Optional background wash with a dedicated on or off workflow." path:@[themesTitle, gradientTitle] aliases:@[@"background gradient"]]];

    [entries addObject:[self ytag_searchPageEntryWithTitle:playerTitle description:@"Playback controls, defaults, quality, and on-video UI." path:@[playerTitle] aliases:@[@"video player"]]];
    [entries addObject:[self ytag_searchPageEntryWithTitle:playbackTitle description:@"Playback defaults, autoplay behavior, and watch-next cleanup." path:@[playerTitle, playbackTitle] aliases:@[@"autoplay", @"speed", @"quality"]]];
    [entries addObject:[self ytag_searchPageEntryWithTitle:controlsTitle description:@"Gestures, fullscreen behavior, and direct player interactions." path:@[playerTitle, controlsTitle] aliases:@[@"gestures", @"fullscreen"]]];
    [entries addObject:[self ytag_searchPageEntryWithTitle:actionBarTitle description:@"Buttons shown directly under the player." path:@[playerTitle, actionBarTitle] aliases:@[@"under player buttons", @"player buttons"]]];
    [entries addObject:[self ytag_searchPageEntryWithTitle:menusTitle description:@"Hide player menu actions you never use." path:@[playerTitle, menusTitle] aliases:@[@"player menu", @"overflow menu"]]];
    [entries addObject:[self ytag_searchPageEntryWithTitle:miniplayerTitle description:@"Mini player behavior and queue fallback options." path:@[playerTitle, miniplayerTitle] aliases:@[@"mini player", @"picture in picture"]]];
    if (isAdvanced) {
        [entries addObject:[self ytag_searchPageEntryWithTitle:overlayTitle description:@"HUD, autoplay, end-screen cards, and player chrome." path:@[playerTitle, overlayTitle] aliases:@[@"hud", @"overlay buttons"]]];
    }

    [entries addObject:[self ytag_searchPageEntryWithTitle:shortsTitle description:@"Behavior, conversion, and optional UI cleanup for Shorts." path:@[shortsTitle] aliases:@[@"reels"]]];
    if (isAdvanced) {
        [entries addObject:[self ytag_searchPageEntryWithTitle:layoutButtonsTitle description:@"Hide specific Shorts UI elements and action buttons." path:@[shortsTitle, layoutButtonsTitle] aliases:@[@"shorts layout", @"shorts buttons"]]];
    }

    [entries addObject:[self ytag_searchPageEntryWithTitle:downloadsTitle description:@"Download features and offline tools will live here." path:@[downloadsTitle] aliases:@[@"offline"]]];

    [entries addObject:[self ytag_searchPageEntryWithTitle:extrasTitle description:@"Extra tools, browse cleanup, and smaller utility tweaks." path:@[extrasTitle] aliases:@[@"misc", @"utilities"]]];
    [entries addObject:[self ytag_searchPageEntryWithTitle:feedTitle description:@"Trim browse-surface menus you never use." path:@[extrasTitle, feedTitle] aliases:@[@"browse", @"video menus"]]];
    [entries addObject:[self ytag_searchPageEntryWithTitle:commentsTitle description:@"Comment sorting and comment-surface cleanup." path:@[extrasTitle, commentsTitle] aliases:@[@"comment sorting"]]];

    [entries addObject:[self ytag_searchPageEntryWithTitle:aboutTitle description:@"Maintenance tools, advanced mode, and credits." path:@[aboutTitle] aliases:@[@"settings info", @"maintenance"]]];
    [entries addObject:[self ytag_searchPageEntryWithTitle:creditsTitle description:@"The people, projects, and libraries behind Afterglow." path:@[aboutTitle, creditsTitle] aliases:@[@"about", @"acknowledgements"]]];

    [self ytag_addSearchEntries:entries forSettingKeys:@[@"RemoveAds", @"NoPromotionCards"] path:@[adsTitle] aliasesByKey:nil];

    [self ytag_addSearchEntries:entries forSettingKeys:@[@"RemoveCast", @"RemoveNotifications", @"RemoveSearch", @"RemoveVoiceSearch"] path:@[interfaceTitle, navbarTitle] aliasesByKey:nil];
    if (isAdvanced) {
        [self ytag_addSearchEntries:entries forSettingKeys:@[@"StickyNavbar", @"NoSubbar", @"NoYTLogo", @"PremiumYTLogo"] path:@[interfaceTitle, navbarTitle] aliasesByKey:nil];
    }

    [self ytag_addSearchEntries:entries forSettingKeys:@[@"OpaqueBar", @"RemoveLabels", @"RemoveIndicators"] path:@[interfaceTitle, tabbarTitle] aliasesByKey:nil];
    [entries addObject:[self ytag_searchEntryWithTitle:@"Manage Tabs" description:@"Drag tabs between active and inactive sections, or tap a row to toggle it." path:@[interfaceTitle, tabbarTitle] targetTitle:@"Manage Tabs" aliases:@[@"tab editor", @"reorder tabs"]]];

    [entries addObject:[self ytag_searchEntryWithTitle:LOC(@"Startup") description:@"Choose which active tab opens first." path:@[interfaceTitle] targetTitle:LOC(@"Startup") aliases:@[@"startup tab", @"launch tab"]]];
    [self ytag_addSearchEntries:entries forSettingKeys:@[@"StartupAnimation", @"FloatingKeyboard"] path:@[interfaceTitle] aliasesByKey:@{
        @"FloatingKeyboard": @[@"ipad keyboard"]
    }];
    if (isAdvanced) {
        [self ytag_addSearchEntries:entries forSettingKeys:@[@"DisableRTL"] path:@[interfaceTitle] aliasesByKey:@{ @"DisableRTL": @[@"right to left", @"ltr"] }];
        [self ytag_addSearchEntries:entries forSettingKeys:@[@"OldYTUI"] path:@[interfaceTitle, legacyTitle] aliasesByKey:@{ @"OldYTUI": @[@"legacy ui"] }];
    }
    [self ytag_addSearchEntries:entries forSettingKeys:@[@"NoSearchHistory", @"NoLinkTracking", @"NoShareChunk"] path:@[privacyTitle] aliasesByKey:@{
        @"NoSearchHistory": @[@"search suggestions", @"recent searches"],
        @"NoLinkTracking": @[@"tracking links", @"redirects"],
        @"NoShareChunk": @[@"clean links", @"shared links"]
    }];

    [entries addObject:[self ytag_searchEntryWithTitle:LOC(@"ResetAllColors") description:@"Clear every theme override and go back to stock colors." path:@[themesTitle] targetTitle:LOC(@"ResetAllColors") aliases:@[@"reset theme", @"default theme"]]];
    [self ytag_addSearchEntries:entries forLiteralTitles:@[
        @"OLED Dark", @"Midnight Blue", @"Forest Green", @"Afterglow 1", @"Afterglow 2", @"Afterglow 3", @"Afterglow 4",
        @"Clean White", @"Warm Sand", @"Ocean Breeze", @"Rose Gold", @"Afterglow Light 1", @"Afterglow Light 2", @"Afterglow Light 3", @"Afterglow Light 4"
    ] path:@[themesTitle, presetsTitle] descriptionsByTitle:nil aliasesByTitle:@{
        @"OLED Dark": @[@"black theme"],
        @"Afterglow 1": @[@"vaporwave"],
        @"Afterglow 4": @[@"green neon"],
        @"Afterglow Light 4": @[@"light sky"]
    }];
    [self ytag_addSearchEntries:entries forSettingKeys:@[@"Background", @"NavigationBar", @"TabBarIcons", @"OverlayButtons", @"SeekBar", @"PrimaryText", @"SecondaryText", @"AccentColor"] path:@[themesTitle, customColorsTitle] aliasesByKey:@{
        @"NavigationBar": @[@"nav bar color"],
        @"TabBarIcons": @[@"tab bar color"],
        @"OverlayButtons": @[@"player overlay color"],
        @"SeekBar": @[@"progress bar color"]
    }];
    [self ytag_addSearchEntries:entries forSettingKeys:@[@"GradientStart", @"GradientEnd"] path:@[themesTitle, gradientTitle] aliasesByKey:nil];

    [self ytag_addSearchEntries:entries forSettingKeys:@[@"BackgroundPlayback", @"HoldToSpeed", @"DefaultPlaybackRate", @"PlaybackQualityOnWiFi", @"PlaybackQualityOnCellular", @"DisableAutoplay", @"DisableAutoCaptions", @"RememberCaptionState", @"RememberLoopMode", @"ClassicQuality", @"NoContentWarning", @"NoContinueWatching", @"NoRelatedWatchNexts"] path:@[playerTitle, playbackTitle] aliasesByKey:@{
        @"HoldToSpeed": @[@"long press speed", @"2x"],
        @"NoContinueWatching": @[@"continue watching"],
        @"NoRelatedWatchNexts": @[@"watch next", @"videos under player"]
    }];
    if (isAdvanced) {
        [self ytag_addSearchEntries:entries forSettingKeys:@[@"HideAutoplay", @"NoEndScreenCards", @"NoRelatedVids", @"NoContinueWatchingPrompt"] path:@[playerTitle, playbackTitle] aliasesByKey:@{
            @"NoContinueWatchingPrompt": @[@"are you still watching"],
            @"NoRelatedVids": @[@"related videos"]
        }];
    }

    [self ytag_addSearchEntries:entries forSettingKeys:@[@"PortraitFullscreen", @"AutoFullscreen", @"ExitFullscreen", @"TapToSeek", @"DontSnap2Chapter", @"NoTwoFingerSnapToChapter", @"NoDoubleTap2Seek", @"PauseOnOverlay", @"NoFreeZoom", @"CopyWithTimestamp"] path:@[playerTitle, controlsTitle] aliasesByKey:@{
        @"TapToSeek": @[@"tap seek"],
        @"DontSnap2Chapter": @[@"chapter snap"],
        @"NoDoubleTap2Seek": @[@"double tap seek"]
    }];
    [self ytag_addSearchEntries:entries forSettingKeys:@[@"NoPlayerDownloadButton", @"PlayerNoShare", @"PlayerNoSave", @"NoPlayerRemixButton", @"NoPlayerClipButton"] path:@[playerTitle, actionBarTitle] aliasesByKey:nil];
    [self ytag_addSearchEntries:entries forSettingKeys:@[@"RemoveDownloadMenu", @"RemoveShareMenu"] path:@[playerTitle, menusTitle] aliasesByKey:nil];
    [self ytag_addSearchEntries:entries forSettingKeys:@[@"Miniplayer"] path:@[playerTitle, miniplayerTitle] aliasesByKey:@{ @"Miniplayer": @[@"mini player"] }];
    if (isAdvanced) {
        [self ytag_addSearchEntries:entries forSettingKeys:@[@"PlaylistOldMinibar"] path:@[playerTitle, miniplayerTitle] aliasesByKey:@{ @"PlaylistOldMinibar": @[@"playlist panel"] }];
        [self ytag_addSearchEntries:entries forSettingKeys:@[@"HideSubs", @"ShowPlayerShareButton", @"ShowPlayerSaveButton", @"NoHUDMsgs", @"HidePrevNext", @"ReplacePrevNext", @"NoDarkBg", @"NoFullscreenActions", @"PersistentProgressBar", @"StockVolumeHUD", @"NoWatermarks", @"DisableAmbientMode", @"VideoEndTime", @"24hrFormat", @"HideHeatwaves", @"RedProgressBar"] path:@[playerTitle, overlayTitle] aliasesByKey:@{
            @"ShowPlayerShareButton": @[@"always show share"],
            @"ShowPlayerSaveButton": @[@"always show save"],
            @"RedProgressBar": @[@"classic progress bar"]
        }];
    }

    [self ytag_addSearchEntries:entries forSettingKeys:@[@"ShortsOnlyMode", @"AutoSkipShorts", @"HideShorts", @"ShortsProgress", @"PinchToFullscreenShorts", @"ShortsToRegular", @"ResumeShorts"] path:@[shortsTitle] aliasesByKey:@{
        @"ShortsToRegular": @[@"convert shorts"],
        @"PinchToFullscreenShorts": @[@"pinch fullscreen"]
    }];
    if (isAdvanced) {
        [self ytag_addSearchEntries:entries forSettingKeys:@[@"HideShortsLogo", @"HideShortsSearch", @"HideShortsCamera", @"HideShortsMore", @"HideShortsSubscriptions", @"HideShortsLike", @"HideShortsDislike", @"HideShortsComments", @"HideShortsRemix", @"HideShortsShare", @"HideShortsAvatars", @"HideShortsThanks", @"HideShortsSource", @"HideShortsChannelName", @"HideShortsDescription", @"HideShortsAudioTrack", @"HideShortsPromoCards"] path:@[shortsTitle, layoutButtonsTitle] aliasesByKey:nil];
    }

    [self ytag_addSearchEntries:entries forSettingKeys:@[@"RemovePlayNext", @"RemoveWatchLaterMenu", @"RemoveSaveToPlaylistMenu", @"RemoveNotInterestedMenu", @"RemoveDontRecommendMenu", @"RemoveReportMenu"] path:@[extrasTitle, feedTitle] aliasesByKey:@{
        @"RemoveDontRecommendMenu": @[@"don't recommend channel"]
    }];
    [self ytag_addSearchEntries:entries forSettingKeys:@[@"StickSortComments", @"HideSortComments"] path:@[extrasTitle, commentsTitle] aliasesByKey:nil];

    [self ytag_addSearchEntries:entries forSettingKeys:@[@"CopyVideoInfo", @"SaveProfilePhoto", @"PostManager", @"CommentManager", @"NativeShare", @"FixAlbums"] path:@[extrasTitle] aliasesByKey:@{
        @"CopyVideoInfo": @[@"copy info", @"video details"],
        @"SaveProfilePhoto": @[@"avatar"],
        @"PostManager": @[@"community posts"],
        @"CommentManager": @[@"long press comments"],
        @"NativeShare": @[@"share sheet"]
    }];

    [self ytag_addSearchEntries:entries forSettingKeys:@[@"Advanced", @"ClearCache", @"ResetSettings"] path:@[aboutTitle] aliasesByKey:@{
        @"Advanced": @[@"advanced mode"],
        @"ClearCache": @[@"cache"],
        @"ResetSettings": @[@"reset tweak"]
    }];

    return entries;
}

#pragma mark - Settings Section

%new(v@:@)
- (void)updateYTAfterglowSectionWithEntry:(id)entry {
    NSMutableArray *sectionItems = [NSMutableArray array];
    YTSettingsViewController *settingsViewController = [self valueForKey:@"_settingsViewControllerDelegate"];
    BOOL isAdvanced = ytagBool(@"advancedMode");
    NSArray<YTAGSettingsSearchEntry *> *searchEntries = [self ytag_settingsSearchEntriesForAdvancedMode:isAdvanced];

    YTSettingsSectionItem *space = [%c(YTSettingsSectionItem) itemWithTitle:nil accessibilityIdentifier:@"YTAfterglowSectionItem" detailTextBlock:nil selectBlock:nil];
    NSArray *adsKeys = @[@"noAds", @"noPromotionCards"];
    NSArray *navbarKeys = @[@"noCast", @"noNotifsButton", @"noSearchButton", @"noVoiceSearchButton", @"stickyNavbar", @"noSubbar", @"noYTLogo", @"premiumYTLogo"];
    NSArray *tabbarKeys = @[@"frostedPivot", @"removeLabels", @"removeIndicators"];
    NSArray *legacyKeys = @[@"oldYTUI"];
    NSArray *interfaceKeys = [[[tabbarKeys arrayByAddingObject:@"startupAnimation"] arrayByAddingObject:@"floatingKeyboard"] arrayByAddingObjectsFromArray:[@[@"disableRTL"] arrayByAddingObjectsFromArray:legacyKeys]];
    NSArray *privacyKeys = @[@"noSearchHistory", @"noLinkTracking", @"noShareChunk"];
    NSArray *playerPlaybackKeys = @[@"backgroundPlayback", @"disableAutoplay", @"hideAutoplay", @"disableAutoCaptions", @"rememberCaptionState", @"rememberLoop", @"noContentWarning", @"classicQuality", @"endScreenCards", @"noRelatedVids", @"noContinueWatching", @"noContinueWatchingPrompt", @"noRelatedWatchNexts"];
    NSArray *playerControlKeys = @[@"portraitFullscreen", @"copyWithTimestamp", @"tapToSeek", @"dontSnapToChapter", @"noTwoFingerSnapToChapter", @"pauseOnOverlay", @"noFreeZoom", @"autoFullscreen", @"exitFullscreen", @"noDoubleTapToSeek"];
    NSArray *playerOverlayKeys = @[@"hideSubs", @"showPlayerShareButton", @"showPlayerSaveButton", @"noHUDMsgs", @"hidePrevNext", @"replacePrevNext", @"noDarkBg", @"noFullscreenActions", @"persistentProgressBar", @"stockVolumeHUD", @"noWatermarks", @"disableAmbientMode", @"videoEndTime", @"24hrFormat", @"hideHeatwaves", @"redProgressBar"];
    NSArray *playerActionBarKeys = @[@"noPlayerDownloadButton", @"playerNoShare", @"playerNoSave", @"noPlayerRemixButton", @"noPlayerClipButton"];
    NSArray *playerMenuKeys = @[@"removeDownloadMenu", @"removeShareMenu"];
    NSArray *playerMiniplayerKeys = @[@"miniplayer", @"playlistOldMinibar"];
    NSArray *playerKeys = [[[[[playerPlaybackKeys arrayByAddingObjectsFromArray:playerControlKeys] arrayByAddingObjectsFromArray:playerOverlayKeys] arrayByAddingObjectsFromArray:playerActionBarKeys] arrayByAddingObjectsFromArray:playerMenuKeys] arrayByAddingObjectsFromArray:playerMiniplayerKeys];
    NSArray *shortsBehaviorKeys = @[@"shortsOnlyMode", @"autoSkipShorts", @"hideShorts", @"shortsProgress", @"pinchToFullscreenShorts", @"shortsToRegular", @"resumeShorts"];
    NSArray *shortsUIKeys = @[@"hideShortsLogo", @"hideShortsSearch", @"hideShortsCamera", @"hideShortsMore", @"hideShortsSubscriptions", @"hideShortsLike", @"hideShortsDislike", @"hideShortsComments", @"hideShortsRemix", @"hideShortsShare", @"hideShortsAvatars", @"hideShortsThanks", @"hideShortsSource", @"hideShortsChannelName", @"hideShortsDescription", @"hideShortsAudioTrack", @"hideShortsPromoCards"];
    NSArray *feedKeys = @[@"removePlayNext", @"removeWatchLaterMenu", @"removeSaveToPlaylistMenu", @"removeNotInterestedMenu", @"removeDontRecommendMenu", @"removeReportMenu"];
    NSArray *commentKeys = @[@"stickSortComments", @"hideSortComments"];
    NSArray *extraToolKeys = @[@"copyVideoInfo", @"postManager", @"saveProfilePhoto", @"commentManager", @"fixAlbums", @"nativeShare"];
    NSArray *extrasKeys = [[[feedKeys arrayByAddingObjectsFromArray:commentKeys] arrayByAddingObjectsFromArray:extraToolKeys] copy];

    YTSettingsSectionItem *searchSettings = [self pageItemWithTitle:ytag_localizedStringOrFallback(@"SearchSettings", @"Search Settings")
        titleDescription:ytag_localizedStringOrFallback(@"SearchSettingsDesc", @"Find a setting or category and jump straight to it.")
        summary:^NSString *() {
            return ytag_localizedStringOrFallback(@"SearchSettingsSummary", @"Jump to any setting");
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            YTAGSettingsSearchController *controller = [[YTAGSettingsSearchController alloc] initWithSettingsViewController:settingsViewController entries:searchEntries];
            [settingsViewController pushViewController:controller];
            return YES;
        }];
    [sectionItems addObject:searchSettings];

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
        titleDescription:@"App chrome, tabs, startup, and input behavior."
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
                [rows addObject:[self switchWithTitle:@"DisableRTL" key:@"disableRTL"]];
            }

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

    YTSettingsSectionItem *privacy = [self pageItemWithTitle:ytag_localizedStringOrFallback(@"Privacy", @"Privacy")
        titleDescription:@"Search history, redirects, and shared-link cleanup."
        summary:^NSString *() {
            return [self enabledSummaryForKeys:privacyKeys];
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSArray <YTSettingsSectionItem *> *rows = @[
                [self switchWithTitle:@"NoSearchHistory" key:@"noSearchHistory"],
                [self switchWithTitle:@"NoLinkTracking" key:@"noLinkTracking"],
                [self switchWithTitle:@"NoShareChunk" key:@"noShareChunk"]
            ];

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:ytag_localizedStringOrFallback(@"Privacy", @"Privacy") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:privacy];

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
                titleDescription:@"Playback defaults, autoplay behavior, and watch-next cleanup."
                summary:^NSString *() {
                    return [self enabledSummaryForKeys:playerPlaybackKeys];
                }
                selectBlock:^BOOL (YTSettingsCell *defaultsCell, NSUInteger defaultsArg1) {
                    NSMutableArray <YTSettingsSectionItem *> *defaultRows = [@[
                        [self switchWithTitle:@"BackgroundPlayback" key:@"backgroundPlayback"],
                        [self holdToSpeedItemWithSettingsVC:settingsViewController],
                        [self defaultPlaybackRateItemWithSettingsVC:settingsViewController],
                        [self playbackQualityItemWithTitle:@"PlaybackQualityOnWiFi" key:@"wiFiQualityIndex" settingsVC:settingsViewController],
                        [self playbackQualityItemWithTitle:@"PlaybackQualityOnCellular" key:@"cellQualityIndex" settingsVC:settingsViewController],
                        [self switchWithTitle:@"DisableAutoplay" key:@"disableAutoplay"],
                        [self switchWithTitle:@"DisableAutoCaptions" key:@"disableAutoCaptions"],
                        [self switchWithTitle:@"RememberCaptionState" key:@"rememberCaptionState"],
                        [self switchWithTitle:@"RememberLoopMode" key:@"rememberLoop"],
                        [self switchWithTitle:@"ClassicQuality" key:@"classicQuality"],
                        [self switchWithTitle:@"NoContentWarning" key:@"noContentWarning"],
                        [self switchWithTitle:@"NoContinueWatching" key:@"noContinueWatching"],
                        [self switchWithTitle:@"NoRelatedWatchNexts" key:@"noRelatedWatchNexts"]
                    ] mutableCopy];

                    if (isAdvanced) {
                        [defaultRows addObjectsFromArray:@[
                            [self switchWithTitle:@"HideAutoplay" key:@"hideAutoplay"],
                            [self switchWithTitle:@"NoEndScreenCards" key:@"endScreenCards"],
                            [self switchWithTitle:@"NoRelatedVids" key:@"noRelatedVids"],
                            [self switchWithTitle:@"NoContinueWatchingPrompt" key:@"noContinueWatchingPrompt"]
                        ]];
                    }

                    YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Playback") pickerSectionTitle:nil rows:defaultRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                    [settingsViewController pushViewController:picker];
                    return YES;
                }]];

            [rows addObject:[self pageItemWithTitle:@"Controls"
                titleDescription:@"Gestures, fullscreen behavior, and direct player interactions."
                summary:^NSString *() {
                    return [self enabledSummaryForKeys:playerControlKeys];
                }
                selectBlock:^BOOL (YTSettingsCell *controlsCell, NSUInteger controlsArg1) {
                    NSArray <YTSettingsSectionItem *> *controlRows = @[
                        [self switchWithTitle:@"PortraitFullscreen" key:@"portraitFullscreen"],
                        [self switchWithTitle:@"AutoFullscreen" key:@"autoFullscreen"],
                        [self switchWithTitle:@"ExitFullscreen" key:@"exitFullscreen"],
                        [self switchWithTitle:@"TapToSeek" key:@"tapToSeek"],
                        [self switchWithTitle:@"DontSnap2Chapter" key:@"dontSnapToChapter"],
                        [self switchWithTitle:@"NoTwoFingerSnapToChapter" key:@"noTwoFingerSnapToChapter"],
                        [self switchWithTitle:@"NoDoubleTap2Seek" key:@"noDoubleTapToSeek"],
                        [self switchWithTitle:@"PauseOnOverlay" key:@"pauseOnOverlay"],
                        [self switchWithTitle:@"NoFreeZoom" key:@"noFreeZoom"],
                        [self switchWithTitle:@"CopyWithTimestamp" key:@"copyWithTimestamp"]
                    ];

                    YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Controls") pickerSectionTitle:nil rows:controlRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                    [settingsViewController pushViewController:picker];
                    return YES;
                }]];

            [rows addObject:[self pageItemWithTitle:@"Action Bar"
                titleDescription:@"Buttons shown directly under the player."
                summary:^NSString *() {
                    return [self enabledSummaryForKeys:playerActionBarKeys];
                }
                selectBlock:^BOOL (YTSettingsCell *barCell, NSUInteger barArg1) {
                    NSArray <YTSettingsSectionItem *> *barRows = @[
                        [self switchWithTitle:@"NoPlayerDownloadButton" key:@"noPlayerDownloadButton"],
                        [self switchWithTitle:@"PlayerNoShare" key:@"playerNoShare"],
                        [self switchWithTitle:@"PlayerNoSave" key:@"playerNoSave"],
                        [self switchWithTitle:@"NoPlayerRemixButton" key:@"noPlayerRemixButton"],
                        [self switchWithTitle:@"NoPlayerClipButton" key:@"noPlayerClipButton"]
                    ];

                    YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:@"Action Bar" pickerSectionTitle:nil rows:barRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                    [settingsViewController pushViewController:picker];
                    return YES;
                }]];

            [rows addObject:[self pageItemWithTitle:@"Menus"
                titleDescription:@"Hide player menu actions you never use."
                summary:^NSString *() {
                    return [self enabledSummaryForKeys:playerMenuKeys];
                }
                selectBlock:^BOOL (YTSettingsCell *menuCell, NSUInteger menuArg1) {
                    NSArray <YTSettingsSectionItem *> *menuRows = @[
                        [self switchWithTitle:@"RemoveDownloadMenu" key:@"removeDownloadMenu"],
                        [self switchWithTitle:@"RemoveShareMenu" key:@"removeShareMenu"]
                    ];

                    YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:@"Menus" pickerSectionTitle:nil rows:menuRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                    [settingsViewController pushViewController:picker];
                    return YES;
                }]];

            [rows addObject:[self pageItemWithTitle:@"Miniplayer"
                titleDescription:@"Mini player behavior and queue fallback options."
                summary:^NSString *() {
                    return [self enabledSummaryForKeys:playerMiniplayerKeys];
                }
                selectBlock:^BOOL (YTSettingsCell *miniCell, NSUInteger miniArg1) {
                    NSMutableArray <YTSettingsSectionItem *> *miniRows = [@[
                        [self switchWithTitle:@"Miniplayer" key:@"miniplayer"]
                    ] mutableCopy];

                    if (isAdvanced) {
                        [miniRows addObject:[self switchWithTitle:@"PlaylistOldMinibar" key:@"playlistOldMinibar"]];
                    }

                    YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:@"Miniplayer" pickerSectionTitle:nil rows:miniRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                    [settingsViewController pushViewController:picker];
                    return YES;
                }]];

            if (isAdvanced) {
                [rows addObject:[self pageItemWithTitle:LOC(@"Overlay")
                    titleDescription:@"HUD, autoplay, end-screen cards, and player chrome."
                    summary:^NSString *() {
                        return [self enabledSummaryForKeys:playerOverlayKeys];
                    }
                    selectBlock:^BOOL (YTSettingsCell *overlayCell, NSUInteger overlayArg1) {
                        NSArray <YTSettingsSectionItem *> *overlayRows = @[
                            [self switchWithTitle:@"HideSubs" key:@"hideSubs"],
                            [self switchWithTitle:@"ShowPlayerShareButton" key:@"showPlayerShareButton"],
                            [self switchWithTitle:@"ShowPlayerSaveButton" key:@"showPlayerSaveButton"],
                            [self switchWithTitle:@"NoHUDMsgs" key:@"noHUDMsgs"],
                            [self switchWithTitle:@"HidePrevNext" key:@"hidePrevNext"],
                            [self switchWithTitle:@"ReplacePrevNext" key:@"replacePrevNext"],
                            [self switchWithTitle:@"NoDarkBg" key:@"noDarkBg"],
                            [self switchWithTitle:@"NoFullscreenActions" key:@"noFullscreenActions"],
                            [self switchWithTitle:@"PersistentProgressBar" key:@"persistentProgressBar"],
                            [self switchWithTitle:@"StockVolumeHUD" key:@"stockVolumeHUD"],
                            [self switchWithTitle:@"NoWatermarks" key:@"noWatermarks"],
                            [self switchWithTitle:@"DisableAmbientMode" key:@"disableAmbientMode"],
                            [self switchWithTitle:@"VideoEndTime" key:@"videoEndTime"],
                            [self switchWithTitle:@"24hrFormat" key:@"24hrFormat"],
                            [self switchWithTitle:@"HideHeatwaves" key:@"hideHeatwaves"],
                            [self switchWithTitle:@"RedProgressBar" key:@"redProgressBar"]
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

            [rows addObjectsFromArray:@[
                [self switchWithTitle:@"ShortsOnlyMode" key:@"shortsOnlyMode"],
                [self switchWithTitle:@"AutoSkipShorts" key:@"autoSkipShorts"],
                [self switchWithTitle:@"HideShorts" key:@"hideShorts"],
                [self switchWithTitle:@"ShortsProgress" key:@"shortsProgress"],
                [self switchWithTitle:@"PinchToFullscreenShorts" key:@"pinchToFullscreenShorts"],
                [self switchWithTitle:@"ShortsToRegular" key:@"shortsToRegular"],
                [self switchWithTitle:@"ResumeShorts" key:@"resumeShorts"]
            ]];

            if (isAdvanced) {
                [rows addObject:space];
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
                            [self switchWithTitle:@"HideShortsPromoCards" key:@"hideShortsPromoCards"]
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
        titleDescription:@"Download features and offline tools will live here."
        summary:^NSString *() {
            return @"Coming soon";
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSArray <YTSettingsSectionItem *> *rows = @[
                [self themeSectionHeaderWithTitle:@"Coming Soon" description:@"New download features and offline tools will be added here."]
            ];

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Downloads") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:downloads];

    YTSettingsSectionItem *extras = [self pageItemWithTitle:@"Extras"
        titleDescription:@"Extra tools, browse cleanup, and smaller utility tweaks."
        summary:^NSString *() {
            return [self enabledSummaryForKeys:extrasKeys];
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray <YTSettingsSectionItem *> *rows = [NSMutableArray array];

            [rows addObject:[self pageItemWithTitle:@"Feed"
                titleDescription:@"Trim browse-surface menus you never use."
                summary:^NSString *() {
                    return [self enabledSummaryForKeys:feedKeys];
                }
                selectBlock:^BOOL (YTSettingsCell *feedCell, NSUInteger feedArg1) {
                    NSArray <YTSettingsSectionItem *> *feedRows = @[
                        [self switchWithTitle:@"RemovePlayNext" key:@"removePlayNext"],
                        [self switchWithTitle:@"RemoveWatchLaterMenu" key:@"removeWatchLaterMenu"],
                        [self switchWithTitle:@"RemoveSaveToPlaylistMenu" key:@"removeSaveToPlaylistMenu"],
                        [self switchWithTitle:@"RemoveNotInterestedMenu" key:@"removeNotInterestedMenu"],
                        [self switchWithTitle:@"RemoveDontRecommendMenu" key:@"removeDontRecommendMenu"],
                        [self switchWithTitle:@"RemoveReportMenu" key:@"removeReportMenu"]
                    ];

                    YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:@"Feed" pickerSectionTitle:nil rows:feedRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                    [settingsViewController pushViewController:picker];
                    return YES;
                }]];

            [rows addObject:[self pageItemWithTitle:@"Comments"
                titleDescription:@"Comment sorting and comment-surface cleanup."
                summary:^NSString *() {
                    return [self enabledSummaryForKeys:commentKeys];
                }
                selectBlock:^BOOL (YTSettingsCell *commentCell, NSUInteger commentArg1) {
                    NSArray <YTSettingsSectionItem *> *commentRows = @[
                        [self switchWithTitle:@"StickSortComments" key:@"stickSortComments"],
                        [self switchWithTitle:@"HideSortComments" key:@"hideSortComments"]
                    ];

                    YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:@"Comments" pickerSectionTitle:nil rows:commentRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                    [settingsViewController pushViewController:picker];
                    return YES;
                }]];

            [rows addObject:space];
            [rows addObject:[self themeSectionHeaderWithTitle:@"Tools" description:@"Extra utility actions that do not belong to one primary surface."]];
            [rows addObject:[self switchWithTitle:@"CopyVideoInfo" key:@"copyVideoInfo"]];
            [rows addObject:[self switchWithTitle:@"SaveProfilePhoto" key:@"saveProfilePhoto"]];
            [rows addObject:[self switchWithTitle:@"PostManager" key:@"postManager"]];
            [rows addObject:[self switchWithTitle:@"CommentManager" key:@"commentManager"]];
            [rows addObject:[self switchWithTitle:@"NativeShare" key:@"nativeShare"]];
            [rows addObject:[self switchWithTitle:@"FixAlbums" key:@"fixAlbums"]];

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:@"Extras" pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:extras];

    YTSettingsSectionItem *credits = [self pageItemWithTitle:LOC(@"Credits")
        titleDescription:@"The team behind YouTube Afterglow, the foundation it's built on, and the open-source projects it depends on."
        summary:^NSString *() {
            return @"Team, Foundation & Libraries";
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSArray <YTSettingsSectionItem *> *rows = @[
                [self themeSectionHeaderWithTitle:@"Development Team" description:@"The humans and AIs who built and continue to maintain this tweak."],
                [self linkWithTitle:@"Corey Hamilton" description:@"Maintainer" link:@"https://github.com/xuninc"],
                [self linkWithTitle:@"Claude Opus 4.6" description:@"AI Collaborator" link:@"https://claude.com/claude"],
                [self linkWithTitle:@"Codex" description:@"AI Collaborator" link:@"https://openai.com/codex"],
                space,
                [self themeSectionHeaderWithTitle:@"Foundation" description:@"Afterglow is built on the last open-source state of YTLite before it went closed-source at version 4.0."],
                [self linkWithTitle:@"dayanch96" description:@"YTLite — last open-source source files (pre-4.0)" link:@"https://github.com/dayanch96/YTLite"],
                space,
                [self themeSectionHeaderWithTitle:@"Bundled Tweaks" description:@"The community-built tweaks packaged inside Afterglow."],
                [self linkWithTitle:@"PoomSmart" description:@"YouPiP, YouQuality, Return-YouTube-Dislikes, YTABConfig, YTVideoOverlay, YouGroupSettings, YTIcons, YouTubeHeader" link:@"https://github.com/PoomSmart"],
                [self linkWithTitle:@"splaser" description:@"YTUHD" link:@"https://github.com/splaser/YTUHD"],
                [self linkWithTitle:@"therealFoxster" description:@"DontEatMyContent" link:@"https://github.com/therealFoxster/DontEatMyContent"],
                [self linkWithTitle:@"BillyCurtis" description:@"Open in YouTube Safari Extension" link:@"https://github.com/BillyCurtis/OpenYouTubeSafariExtension"],
                space,
                [self themeSectionHeaderWithTitle:@"Libraries" description:@"Open-source libraries used by the tweak."],
                [self linkWithTitle:@"jkhsjdhjs" description:@"YouTube Native Share" link:@"https://github.com/jkhsjdhjs/youtube-native-share"],
                [self linkWithTitle:@"Tony Million" description:@"Reachability" link:@"https://github.com/tonymillion/Reachability"]
            ];

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"About") pickerSectionTitle:LOC(@"Credits") rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];

    YTSettingsSectionItem *about = [self pageItemWithTitle:LOC(@"About")
        titleDescription:@"Maintenance tools, advanced mode, and credits."
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
            [rows addObject:credits];

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
