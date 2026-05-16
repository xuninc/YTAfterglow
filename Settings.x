#import "YTAfterglow.h"
#import <objc/runtime.h>
#import <objc/message.h>

@interface YTAGAfterglowSettingsDismisser : NSObject
@property (nonatomic, weak) UINavigationController *nav;
- (void)closeTap;
@end

@implementation YTAGAfterglowSettingsDismisser
- (void)closeTap { [self.nav dismissViewControllerAnimated:YES completion:nil]; }
@end

extern void ytag_clearThemeCache(void);
void YTAGOpenAfterglowSettingsFromView(UIView *sourceView);
static UIViewController *ytag_viewControllerForResponder(UIResponder *responder);
static UIViewController *ytag_topPresenterForView(UIView *sourceView);
static void ytag_reloadSettingsController(UIViewController *controller);
static void ytag_refreshSettingsHierarchy(UIViewController *controller);
static void ytag_refreshSettingsFromCell(YTSettingsCell *cell);
static void ytag_presentThemeRefreshAlert(UIViewController *presenter, NSString *title, NSString *message);
static NSString *ytag_localizedStringOrFallback(NSString *key, NSString *fallback);
static NSString *ytag_settingDescriptionForKey(NSString *key);
static UIViewController *ytag_presenterForSettingsCell(YTSettingsCell *cell, UIViewController *fallback);
static void ytag_showToast(NSString *message, id parentResponder);
static NSURL *ytag_writeTemporaryFile(NSString *filename, NSData *data, NSError **error);
static BOOL ytag_presentActivityItems(NSArray *items, UIViewController *presenter, UIView *sourceView);
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
- (YTSettingsSectionItem *)resetDefaultsItemWithKeys:(NSArray<NSString *> *)keys settingsVC:(YTSettingsViewController *)settingsViewController;
- (void)addResetDefaultsItemForKeys:(NSArray<NSString *> *)keys toRows:(NSMutableArray<YTSettingsSectionItem *> *)rows settingsVC:(YTSettingsViewController *)settingsViewController;
- (void)presentPreferencesExportFromCell:(YTSettingsCell *)cell settingsVC:(YTSettingsViewController *)settingsViewController;
- (void)presentPreferencesImportFromCell:(YTSettingsCell *)cell settingsVC:(YTSettingsViewController *)settingsViewController;
- (void)presentDebugLogShareFromCell:(YTSettingsCell *)cell body:(NSString *)body settingsVC:(YTSettingsViewController *)settingsViewController;
- (NSString *)enabledSummaryForKeys:(NSArray<NSString *> *)keys;
- (NSString *)customizationSummaryForKeys:(NSArray<NSString *> *)keys;
- (NSArray<NSString *> *)ytag_allTabs;
- (NSDictionary<NSString *, NSString *> *)ytag_tabNames;
- (NSString *)themeCustomizationSummary;
- (YTSettingsSectionItem *)holdToSpeedItemWithSettingsVC:(YTSettingsViewController *)settingsViewController;
- (YTSettingsSectionItem *)defaultPlaybackRateItemWithSettingsVC:(YTSettingsViewController *)settingsViewController;
- (YTSettingsSectionItem *)playbackQualityItemWithTitle:(NSString *)title key:(NSString *)key settingsVC:(YTSettingsViewController *)settingsViewController;
- (YTSettingsSectionItem *)ytagPickerItemWithTitle:(NSString *)title description:(NSString *)description key:(NSString *)key labels:(NSArray<NSString *> *)labels settingsVC:(YTSettingsViewController *)settingsViewController;
- (YTSettingsSectionItem *)startupTabItemWithSettingsVC:(YTSettingsViewController *)settingsViewController;
- (NSString *)themeHexFromColor:(UIColor *)color;
- (NSString *)themeColorDetailForKey:(NSString *)key;
- (NSString *)themeCustomColorsSummary;
- (NSString *)themeTypographySummary;
- (NSString *)themeSeekBarSummary;
- (NSString *)themeGradientSummary;
- (NSString *)themeAppearanceSummary;
- (NSInteger)themeGlowStrengthMode;
- (NSString *)themeGlowStrengthDetail;
- (NSString *)themeGlowNumberDetailForKey:(NSString *)key fallback:(NSInteger)fallback suffix:(NSString *)suffix;
- (void)themePresentGlowNumberInputWithTitle:(NSString *)title titleDescription:(NSString *)titleDescription key:(NSString *)key min:(NSInteger)min max:(NSInteger)max fallback:(NSInteger)fallback suffix:(NSString *)suffix cell:(YTSettingsCell *)cell settingsVC:(YTSettingsViewController *)settingsVC afterSave:(void (^)(NSInteger value))afterSave;
- (YTSettingsSectionItem *)themeGlowNumberItemWithTitle:(NSString *)title titleDescription:(NSString *)titleDescription key:(NSString *)key min:(NSInteger)min max:(NSInteger)max fallback:(NSInteger)fallback suffix:(NSString *)suffix settingsVC:(YTSettingsViewController *)settingsVC;
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

@interface YTAGImagePickerDelegate : NSObject <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, copy) NSString *prefKey;
@property (nonatomic, weak) YTSettingsViewController *settingsVC;
@end

@implementation YTAGImagePickerDelegate
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    UIImage *image = info[UIImagePickerControllerEditedImage];
    if (!image) image = info[UIImagePickerControllerOriginalImage];
    if (image && self.prefKey.length) {
        CGFloat maxSide = 60.0;
        CGFloat scale = MIN(maxSide / image.size.width, maxSide / image.size.height);
        if (scale < 1.0) {
            CGSize newSize = CGSizeMake(image.size.width * scale, image.size.height * scale);
            UIGraphicsBeginImageContextWithOptions(newSize, NO, 0.0);
            [image drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
            image = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
        }
        NSData *data = UIImagePNGRepresentation(image);
        if (data) [[YTAGUserDefaults standardUserDefaults] setObject:data forKey:self.prefKey];
    }
    __weak YTSettingsViewController *weakVC = self.settingsVC;
    [picker dismissViewControllerAnimated:YES completion:^{
        ytag_refreshSettingsHierarchy(weakVC);
    }];
}
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}
@end

static char kYTAGPreferencesDocumentPickerDelegateAssociationKey;

@interface YTAGPreferencesDocumentPickerDelegate : NSObject <UIDocumentPickerDelegate>
@property (nonatomic, weak) YTSettingsViewController *settingsVC;
@property (nonatomic, weak) id parentResponder;
@end

@implementation YTAGPreferencesDocumentPickerDelegate
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    NSError *readError = nil;
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSData *data = url ? [NSData dataWithContentsOfURL:url options:0 error:&readError] : nil;
    if (scoped) [url stopAccessingSecurityScopedResource];

    NSError *importError = nil;
    BOOL imported = data && [[YTAGUserDefaults standardUserDefaults] importPreferencesData:data error:&importError];
    if (imported) {
        ytag_clearThemeCache();
        [[[objc_lookUpClass("YTHeaderContentComboViewController") alloc] init] refreshPivotBar];
        ytag_refreshSettingsHierarchy(self.settingsVC);
        ytag_showToast(LOC(@"Done"), self.parentResponder);
    } else {
        NSString *message = importError.localizedDescription ?: readError.localizedDescription ?: LOC(@"Error.FailedToImport");
        ytag_showToast(message, self.parentResponder);
    }

    objc_setAssociatedObject(controller, &kYTAGPreferencesDocumentPickerDelegateAssociationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    objc_setAssociatedObject(controller, &kYTAGPreferencesDocumentPickerDelegateAssociationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@end

static const NSInteger YTAfterglowSection = 789;
static YTAGColorPickerDelegate *_colorPickerDelegate = nil;
static YTAGImagePickerDelegate *_imagePickerDelegate = nil;
static char kYTAGPickerRowsAssociationKey;
static char kYTAGPickerHighlightIndexAssociationKey;

static UIColor *YTAGAfterglowTintColor(void) {
    return [UIColor colorWithRed:0.95 green:0.41 blue:0.50 alpha:1.0];
}

static NSArray<NSString *> *ytag_allTabIds(void) {
    return @[@"FEwhat_to_watch", @"FEshorts", @"FEsubscriptions", @"FElibrary", @"FEhype_leaderboard", @"FEhistory", @"VLWL", @"FEpost_home", @"FEuploads"];
}

static NSUInteger ytag_maxActiveTabCount(void) {
    return ytagBool(@"twoRowTabBar") ? ytag_allTabIds().count : 6;
}

static UIViewController *ytag_viewControllerForResponder(UIResponder *responder) {
    UIResponder *currentResponder = responder;
    while (currentResponder && ![currentResponder isKindOfClass:[UIViewController class]]) {
        currentResponder = currentResponder.nextResponder;
    }
    return (UIViewController *)currentResponder;
}

static UIViewController *ytag_keyWindowRootViewController(void) {
    UIWindow *keyWindow = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive ||
                ![scene isKindOfClass:[UIWindowScene class]]) {
                continue;
            }
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window.isKeyWindow) {
                    keyWindow = window;
                    break;
                }
            }
            if (keyWindow) break;
        }
    }
    if (!keyWindow) {
        @try {
            NSArray<UIWindow *> *windows = [UIApplication.sharedApplication valueForKey:@"windows"];
            for (UIWindow *window in windows) {
                if (window.isKeyWindow) {
                    keyWindow = window;
                    break;
                }
            }
        } @catch (NSException *exception) {}
    }
    return keyWindow.rootViewController;
}

static UIViewController *ytag_topPresenterForView(UIView *sourceView) {
    UIViewController *presenter = ytag_viewControllerForResponder(sourceView);
    if (!presenter) presenter = ytag_keyWindowRootViewController();
    while (presenter.presentedViewController) {
        presenter = presenter.presentedViewController;
    }
    return presenter.navigationController.topViewController ?: presenter;
}

static id ytag_parentResponderForSettingsOpen(UIView *sourceView, UIViewController *presenter) {
    UIViewController *sourceController = ytag_viewControllerForResponder(sourceView);
    if (sourceController) {
        return sourceController.navigationController.topViewController ?: sourceController;
    }
    return presenter.navigationController.topViewController ?: presenter;
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

static void ytag_presentLiteModeRestartAlert(YTSettingsCell *cell, BOOL enabled) {
    UIViewController *presenter = ytag_presenterForSettingsCell(cell, nil);
    if (!presenter) {
        ytag_showToast(@"Lite Mode needs a restart", cell);
        return;
    }

    NSString *title = enabled ? @"Lite Mode Enabled" : @"Lite Mode Disabled";
    NSString *message = @"Lite Mode needs a restart before the startup debloat profile fully applies.";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
        message:message
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Restart Now" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        exit(0);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

static UIViewController *ytag_presenterForSettingsCell(YTSettingsCell *cell, UIViewController *fallback) {
    UIViewController *presenter = fallback ?: ytag_viewControllerForResponder(cell);
    presenter = presenter.navigationController.topViewController ?: presenter;
    while (presenter.presentedViewController) {
        presenter = presenter.presentedViewController;
    }
    return presenter;
}

static void ytag_showToast(NSString *message, id parentResponder) {
    if (message.length == 0) return;
    Class toastClass = objc_lookUpClass("YTToastResponderEvent");
    if (!toastClass || ![toastClass respondsToSelector:@selector(eventWithMessage:firstResponder:)]) return;
    id event = [(id)toastClass eventWithMessage:message firstResponder:parentResponder];
    if ([event respondsToSelector:@selector(send)]) [event send];
}

static NSURL *ytag_writeTemporaryFile(NSString *filename, NSData *data, NSError **error) {
    if (filename.length == 0 || data.length == 0) return nil;
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"YTAfterglowExports"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path = [dir stringByAppendingPathComponent:filename];
    NSURL *url = [NSURL fileURLWithPath:path];
    [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
    return [data writeToURL:url options:NSDataWritingAtomic error:error] ? url : nil;
}

static BOOL ytag_presentActivityItems(NSArray *items, UIViewController *presenter, UIView *sourceView) {
    if (items.count == 0 || !presenter) return NO;
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
    UIPopoverPresentationController *popover = activity.popoverPresentationController;
    popover.sourceView = sourceView ?: presenter.view;
    popover.sourceRect = sourceView ? sourceView.bounds : presenter.view.bounds;
    [presenter presentViewController:activity animated:YES completion:nil];
    return YES;
}

static NSString *ytag_localizedStringOrFallback(NSString *key, NSString *fallback) {
    if (!key.length) return fallback ?: @"";

    NSString *localized = LOC(key);
    if (localized.length == 0 || [localized isEqualToString:key]) {
        return fallback ?: key;
    }

    return localized;
}

void YTAGOpenAfterglowSettingsFromView(UIView *sourceView) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = ytag_topPresenterForView(sourceView);
        if (!presenter) {
            ytag_showToast(@"Afterglow settings unavailable", sourceView);
            return;
        }

        id parentResponder = ytag_parentResponderForSettingsOpen(sourceView, presenter);
        @try {
            Class settingsClass = objc_lookUpClass("YTSettingsViewController");
            if (!settingsClass) {
                ytag_showToast(@"Afterglow settings unavailable", parentResponder ?: presenter);
                return;
            }

            id settingsObject = nil;
            SEL initWithAccount = @selector(initWithAccountID:parentResponder:);
            SEL initWithParent = @selector(initWithParentResponder:);
            if ([settingsClass instancesRespondToSelector:initWithAccount]) {
                settingsObject = ((id (*)(id, SEL, id, id))objc_msgSend)([settingsClass alloc], initWithAccount, nil, parentResponder);
            } else if ([settingsClass instancesRespondToSelector:initWithParent]) {
                settingsObject = ((id (*)(id, SEL, id))objc_msgSend)([settingsClass alloc], initWithParent, parentResponder);
            } else {
                settingsObject = [[settingsClass alloc] init];
            }

            if (![settingsObject isKindOfClass:[UIViewController class]]) {
                ytag_showToast(@"Afterglow settings unavailable", parentResponder);
                return;
            }

            UIViewController *settingsVC = (UIViewController *)settingsObject;
            settingsVC.title = @"YouTube Afterglow";
            @try {
                [settingsObject setValue:@(YTAfterglowSection) forKey:@"_categoryToScrollTo"];
            } @catch (NSException *exception) {}

            [settingsVC loadViewIfNeeded];
            SEL updateSection = @selector(updateSectionForCategory:withEntry:);
            if ([settingsObject respondsToSelector:updateSection]) {
                ((void (*)(id, SEL, NSUInteger, id))objc_msgSend)(settingsObject, updateSection, (NSUInteger)YTAfterglowSection, nil);
            }
            ytag_reloadSettingsController(settingsVC);

            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
            nav.modalPresentationStyle = UIModalPresentationFullScreen;

            // The settings VC is the root of this modal nav stack — there's
            // no back arrow because there's nothing to go back to. Without an
            // explicit close button the user has no way out (full-screen
            // modals don't get swipe-to-dismiss either).
            if (!settingsVC.navigationItem.leftBarButtonItem) {
                YTAGAfterglowSettingsDismisser *dismisser = [YTAGAfterglowSettingsDismisser new];
                dismisser.nav = nav;
                // Keep the helper alive for the lifetime of the nav controller.
                static const void *kYTAGSettingsDismisserKey = &kYTAGSettingsDismisserKey;
                objc_setAssociatedObject(nav, kYTAGSettingsDismisserKey, dismisser, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                UIBarButtonItem *closeButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                                                             target:dismisser
                                                                                             action:@selector(closeTap)];
                settingsVC.navigationItem.leftBarButtonItem = closeButton;
            }

            [presenter presentViewController:nav animated:YES completion:nil];
        } @catch (NSException *exception) {
            YTAGLog(@"overlay", @"Afterglow Settings open failed: %@ %@", exception.name ?: @"<unknown>", exception.reason ?: @"<none>");
            ytag_showToast(@"Afterglow settings unavailable", parentResponder ?: presenter ?: sourceView);
        }
    });
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
        return [NSString stringWithFormat:@"Drag to reorder. Move a tab to Hidden Tabs to remove it from the bar. Keep 2 to %lu tabs shown.", (unsigned long)ytag_maxActiveTabCount()];
    }
    return @"Drag a tab into Shown Tabs, or tap it to add it to the end.";
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
    else if ([tabId isEqualToString:@"FEhype_leaderboard"]) symbolName = @"bolt.fill";
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

    if (!movingFromActive && movingToActive && self.activeTabs.count >= ytag_maxActiveTabCount()) {
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

    if (self.activeTabs.count >= ytag_maxActiveTabCount()) {
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
    cell.detailTextLabel.text = indexPath.section == 0 ? @"Shown in the tab bar" : @"Hidden from the tab bar";
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
        if ([key isEqualToString:YTAGLiteModeEnabledKey]) {
            YTAGSetLiteModeEnabled(enabled);
            ytag_clearThemeCache();
            ytag_refreshSettingsFromCell(cell);
            ytag_presentLiteModeRestartAlert(cell, enabled);
        } else if ([key isEqualToString:@"shortsOnlyMode"]) {
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
            if ([key isEqualToString:@"debugLogFirehose"] && enabled) {
                ytagSetBool(YES, @"debugLogEnabled");
            } else if ([key isEqualToString:@"debugLogEnabled"] && !enabled) {
                ytagSetBool(NO, @"debugLogFirehose");
                ytagSetBool(NO, @"debugHUDEnabled");
                [[YTAGDebugHUD sharedHUD] hide];
            }

            NSArray *keys = @[@"removeLabels", @"removeIndicators", @"frostedPivot", @"twoRowTabBar",
                @"theme_overlayButtons", @"theme_tabBarIcons", @"theme_seekBar",
                @"theme_background", @"theme_textPrimary", @"theme_textSecondary",
                @"theme_navBar", @"theme_accent",
                @"theme_gradientStart", @"theme_gradientEnd", @"theme_glowEnabled",
                @"theme_glowPivot", @"theme_glowSeekBar", @"theme_glowScrubber",
                @"theme_glowOverlay", @"theme_glowStrength", @"theme_glowStrengthMode",
                @"theme_glowStrengthCustom", @"theme_glowOpacity", @"theme_glowRadius",
                @"theme_glowLayers", @"theme_glowColor"];
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
- (YTSettingsSectionItem *)resetDefaultsItemWithKeys:(NSArray<NSString *> *)keys settingsVC:(YTSettingsViewController *)settingsViewController {
    NSArray<NSString *> *uniqueKeys = [[NSOrderedSet orderedSetWithArray:keys ?: @[]] array];
    return [%c(YTSettingsSectionItem) itemWithTitle:@"Reset to Defaults"
        titleDescription:@"Restore only the settings on this page."
        accessibilityIdentifier:@"YTAfterglowSectionItem"
        detailTextBlock:nil
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            YTAGUserDefaults *defaults = [YTAGUserDefaults standardUserDefaults];
            for (NSString *key in uniqueKeys) {
                [defaults removeObjectForKey:key];
            }
            ytag_clearThemeCache();
            [[[%c(YTHeaderContentComboViewController) alloc] init] refreshPivotBar];
            ytag_refreshSettingsHierarchy(settingsViewController ?: ytag_viewControllerForResponder(cell));
            [[%c(YTToastResponderEvent) eventWithMessage:LOC(@"Done") firstResponder:[self parentResponder]] send];
            return YES;
        }];
}

%new
- (void)addResetDefaultsItemForKeys:(NSArray<NSString *> *)keys toRows:(NSMutableArray<YTSettingsSectionItem *> *)rows settingsVC:(YTSettingsViewController *)settingsViewController {
    if (keys.count == 0 || !rows) return;
    [rows addObject:[%c(YTSettingsSectionItem) itemWithTitle:nil accessibilityIdentifier:@"YTAfterglowSectionItem" detailTextBlock:nil selectBlock:nil]];
    [rows addObject:[self themeSectionHeaderWithTitle:@"Reset" description:@"Restore this page to its default state."]];
    [rows addObject:[self resetDefaultsItemWithKeys:keys settingsVC:settingsViewController]];
}

%new
- (void)presentPreferencesExportFromCell:(YTSettingsCell *)cell settingsVC:(YTSettingsViewController *)settingsViewController {
    NSError *error = nil;
    NSData *data = [[YTAGUserDefaults standardUserDefaults] exportPreferencesDataWithError:&error];
    NSURL *url = data ? ytag_writeTemporaryFile(@"YTAfterglow-preferences.ytagprefs", data, &error) : nil;
    UIViewController *presenter = ytag_presenterForSettingsCell(cell, settingsViewController);
    if (url && ytag_presentActivityItems(@[url], presenter, cell)) return;

    NSString *message = error.localizedDescription ?: LOC(@"Error.FailedToExport");
    ytag_showToast(message, [self parentResponder]);
}

%new
- (void)presentPreferencesImportFromCell:(YTSettingsCell *)cell settingsVC:(YTSettingsViewController *)settingsViewController {
    UIViewController *presenter = ytag_presenterForSettingsCell(cell, settingsViewController);
    YTAlertView *alertView = [%c(YTAlertView) confirmationDialogWithAction:^{
        NSArray *types = @[@"public.xml-property-list", @"com.apple.property-list", @"public.data", @"public.item"];
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:types inMode:UIDocumentPickerModeImport];
        picker.allowsMultipleSelection = NO;
        YTAGPreferencesDocumentPickerDelegate *delegate = [YTAGPreferencesDocumentPickerDelegate new];
        delegate.settingsVC = settingsViewController;
        delegate.parentResponder = [self parentResponder];
        picker.delegate = delegate;
        objc_setAssociatedObject(picker, &kYTAGPreferencesDocumentPickerDelegateAssociationKey, delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [presenter presentViewController:picker animated:YES completion:nil];
    }
    actionTitle:LOC(@"Yes")
    cancelTitle:LOC(@"No")];
    alertView.title = LOC(@"ImportPreferences");
    alertView.subtitle = LOC(@"PreImportMessage");
    [alertView show];
}

%new
- (void)presentDebugLogShareFromCell:(YTSettingsCell *)cell body:(NSString *)body settingsVC:(YTSettingsViewController *)settingsViewController {
    NSData *data = [body dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSURL *url = ytag_writeTemporaryFile(@"YTAfterglow-debug-log.txt", data, &error);
    UIViewController *presenter = ytag_presenterForSettingsCell(cell, settingsViewController);
    if (url && ytag_presentActivityItems(@[url], presenter, cell)) return;

    [UIPasteboard generalPasteboard].string = body;
    ytag_showToast(LOC(@"LogCopied"), [self parentResponder]);
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
                      @"theme_seekBarLive", @"theme_seekBarScrubber", @"theme_seekBarScrubberLive",
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
- (YTSettingsSectionItem *)ytagPickerItemWithTitle:(NSString *)title description:(NSString *)description key:(NSString *)key labels:(NSArray<NSString *> *)labels settingsVC:(YTSettingsViewController *)settingsViewController {
    Class YTSettingsSectionItemClass = %c(YTSettingsSectionItem);
    return [YTSettingsSectionItemClass itemWithTitle:title
        titleDescription:description
        accessibilityIdentifier:@"YTAfterglowSectionItem"
        detailTextBlock:^NSString *() {
            NSInteger index = MIN(MAX(ytagInt(key), 0), (NSInteger)labels.count - 1);
            return labels[index];
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray <YTSettingsSectionItem *> *rows = [NSMutableArray array];
            for (NSUInteger i = 0; i < labels.count; i++) {
                NSString *rowTitle = labels[i];
                [rows addObject:[YTSettingsSectionItemClass checkmarkItemWithTitle:rowTitle titleDescription:nil selectBlock:^BOOL (YTSettingsCell *innerCell, NSUInteger innerArg1) {
                    ytagSetInt((int)innerArg1, key);
                    ytag_refreshSettingsHierarchy(settingsViewController);
                    return YES;
                }]];
            }
            NSInteger selected = MIN(MAX(ytagInt(key), 0), (NSInteger)labels.count - 1);
            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:title pickerSectionTitle:nil rows:rows selectedItemIndex:selected parentResponder:[self parentResponder]];
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
    return ytag_allTabIds();
}

%new
- (NSDictionary<NSString *, NSString *> *)ytag_tabNames {
    return @{
        @"FEwhat_to_watch": LOC(@"FEwhat_to_watch"),
        @"FEshorts": LOC(@"FEshorts"),
        @"FEsubscriptions": LOC(@"FEsubscriptions"),
        @"FElibrary": LOC(@"FElibrary"),
        @"FEhype_leaderboard": LOC(@"FEhype_leaderboard"),
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
                      @"theme_seekBarLive", @"theme_seekBarScrubber", @"theme_seekBarScrubberLive",
                      @"theme_background", @"theme_textPrimary", @"theme_textSecondary",
                      @"theme_navBar", @"theme_accent"];
    return [self customizationSummaryForKeys:keys];
}

%new
- (NSString *)themeTypographySummary {
    NSInteger mode = ytagInt(YTAGThemeFontModeKey);
    NSInteger tabLabelSizeMode = ytagInt(YTAGThemeTabLabelSizeModeKey);
    NSString *fontName = YTAGThemeFontModeDisplayName(mode);
    if (tabLabelSizeMode == 0) return fontName;
    return [NSString stringWithFormat:@"%@, %@ tab labels", fontName, YTAGThemeTabLabelSizeModeDisplayName(tabLabelSizeMode).lowercaseString];
}

%new
- (NSString *)themeSeekBarSummary {
    NSArray *keys = @[@"theme_seekBar", @"theme_seekBarLive",
                      @"theme_seekBarScrubber", @"theme_seekBarScrubberLive",
                      @"seekBarScrubberImage", @"seekBarScrubberSize",
                      @"persistentProgressBar", @"hideHeatwaves"];
    NSUInteger customizedCount = 0;
    for (NSString *key in keys) {
        if ([[YTAGUserDefaults standardUserDefaults] objectForKey:key] != nil) customizedCount++;
    }
    if (customizedCount == 0) return LOC(@"Default");
    if (customizedCount == 1) return @"1 custom";
    return [NSString stringWithFormat:@"%lu custom", (unsigned long)customizedCount];
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
                           @"theme_seekBarLive", @"theme_seekBarScrubber", @"theme_seekBarScrubberLive",
                           @"theme_background", @"theme_textPrimary", @"theme_textSecondary",
                           @"theme_navBar", @"theme_accent"];
    for (NSString *key in colorKeys) {
        if ([[YTAGUserDefaults standardUserDefaults] objectForKey:key] != nil) customizedCount++;
    }

    BOOL hasGradientStart = [[YTAGUserDefaults standardUserDefaults] objectForKey:@"theme_gradientStart"] != nil;
    BOOL hasGradientEnd = [[YTAGUserDefaults standardUserDefaults] objectForKey:@"theme_gradientEnd"] != nil;
    BOOL hasGradient = hasGradientStart || hasGradientEnd;
    BOOL hasGlow = ytagBool(@"theme_glowEnabled");
    BOOL hasFont = ytagInt(YTAGThemeFontModeKey) != 0;

    if (customizedCount == 0 && !hasGradient && !hasGlow && !hasFont) return LOC(@"Default");
    if (customizedCount == 0 && !hasGradient && !hasGlow && hasFont) return [self themeTypographySummary];
    if (customizedCount == 0 && hasGradient && !hasGlow) return [NSString stringWithFormat:@"Gradient %@", [self themeGradientSummary]];
    if (customizedCount == 0 && hasGlow) return hasGradient ? @"Glow + gradient" : @"Brand glow";
    if (!hasGradient && !hasGlow) return customizedCount == 1 ? @"1 color override" : [NSString stringWithFormat:@"%lu color overrides", (unsigned long)customizedCount];
    if (hasGradient && hasGlow) return [NSString stringWithFormat:@"%lu colors + glow", (unsigned long)customizedCount];
    if (hasGradient) return [NSString stringWithFormat:@"%lu colors + gradient", (unsigned long)customizedCount];
    return [NSString stringWithFormat:@"%lu colors + glow", (unsigned long)customizedCount];
}

%new
- (NSInteger)themeGlowStrengthMode {
    id raw = [[YTAGUserDefaults standardUserDefaults] objectForKey:@"theme_glowStrengthMode"];
    if ([raw respondsToSelector:@selector(integerValue)]) return MIN(MAX([raw integerValue], 0), 3);
    return MIN(MAX(ytagInt(@"theme_glowStrength"), 0), 2);
}

%new
- (NSString *)themeGlowStrengthDetail {
    NSInteger mode = [self themeGlowStrengthMode];
    if (mode == 3) {
        NSInteger custom = MIN(MAX(ytagInt(@"theme_glowStrengthCustom"), 0), 100);
        return [NSString stringWithFormat:@"Custom %ld/100", (long)custom];
    }
    NSArray *labels = @[@"Subtle", @"Normal", @"Strong"];
    return labels[MIN(MAX(mode, 0), (NSInteger)labels.count - 1)];
}

%new
- (NSString *)themeGlowNumberDetailForKey:(NSString *)key fallback:(NSInteger)fallback suffix:(NSString *)suffix {
    id raw = [[YTAGUserDefaults standardUserDefaults] objectForKey:key];
    NSInteger value = [raw respondsToSelector:@selector(integerValue)] ? [raw integerValue] : fallback;
    return [NSString stringWithFormat:@"%ld%@", (long)value, suffix ?: @""];
}

%new
- (void)themePresentGlowNumberInputWithTitle:(NSString *)title titleDescription:(NSString *)titleDescription key:(NSString *)key min:(NSInteger)min max:(NSInteger)max fallback:(NSInteger)fallback suffix:(NSString *)suffix cell:(YTSettingsCell *)cell settingsVC:(YTSettingsViewController *)settingsVC afterSave:(void (^)(NSInteger value))afterSave {
    NSInteger current = fallback;
    id raw = [[YTAGUserDefaults standardUserDefaults] objectForKey:key];
    if ([raw respondsToSelector:@selector(integerValue)]) current = [raw integerValue];
    current = MIN(MAX(current, min), max);

    NSString *message = [NSString stringWithFormat:@"%@\nRange: %ld-%ld%@", titleDescription ?: @"", (long)min, (long)max, suffix ?: @""];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.keyboardType = UIKeyboardTypeNumberPad;
        textField.text = [NSString stringWithFormat:@"%ld", (long)current];
        textField.placeholder = [NSString stringWithFormat:@"%ld", (long)fallback];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:LOC(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:LOC(@"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *text = alert.textFields.firstObject.text ?: @"";
        NSInteger value = MIN(MAX(text.integerValue, min), max);
        [[YTAGUserDefaults standardUserDefaults] setInteger:value forKey:key];
        if (afterSave) afterSave(value);
        ytag_clearThemeCache();
        ytag_refreshSettingsHierarchy(settingsVC ?: ytag_viewControllerForResponder(cell));
    }]];

    UIViewController *presenter = ytag_presenterForSettingsCell(cell, settingsVC);
    [presenter presentViewController:alert animated:YES completion:nil];
}

%new
- (YTSettingsSectionItem *)themeGlowNumberItemWithTitle:(NSString *)title titleDescription:(NSString *)titleDescription key:(NSString *)key min:(NSInteger)min max:(NSInteger)max fallback:(NSInteger)fallback suffix:(NSString *)suffix settingsVC:(YTSettingsViewController *)settingsVC {
    return [%c(YTSettingsSectionItem) itemWithTitle:title
        titleDescription:titleDescription
        accessibilityIdentifier:@"YTAfterglowSectionItem"
        detailTextBlock:^NSString *() {
            return [self themeGlowNumberDetailForKey:key fallback:fallback suffix:suffix];
        }
        selectBlock:^BOOL(YTSettingsCell *cell, NSUInteger arg1) {
            [self themePresentGlowNumberInputWithTitle:title titleDescription:titleDescription key:key min:min max:max fallback:fallback suffix:suffix cell:cell settingsVC:settingsVC afterSave:nil];
            return YES;
        }];
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
    [self themeSaveColor:seekBar forKey:@"theme_seekBarLive"];
    [self themeSaveColor:seekBar forKey:@"theme_seekBarScrubber"];
    [self themeSaveColor:seekBar forKey:@"theme_seekBarScrubberLive"];
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

    NSString *privacyAdsTitle = @"Privacy & Ads";
    NSString *interfaceTitle = LOC(@"Interface");
    NSString *navbarTitle = LOC(@"Navbar");
    NSString *tabbarTitle = LOC(@"Tabbar");
    NSString *legacyTitle = @"Legacy";
    NSString *themesTitle = @"Themes";
    NSString *presetsTitle = LOC(@"Presets");
    NSString *customColorsTitle = LOC(@"CustomColors");
    NSString *effectsTitle = @"Effects";
    NSString *gradientTitle = LOC(@"Gradient");
    NSString *playerTitle = LOC(@"Player");
    NSString *playbackTitle = @"Playback";
    NSString *controlsTitle = @"Controls";
    NSString *buttonsMenusTitle = @"Buttons & Menus";
    NSString *overlayTitle = LOC(@"Overlay");
    NSString *shortsTitle = LOC(@"Shorts");
    NSString *layoutButtonsTitle = @"Layout & Buttons";
    NSString *downloadsTitle = LOC(@"Downloads");
    NSString *feedTitle = @"Feed";
    NSString *toolsTitle = @"Tools";
    NSString *commentsTitle = @"Comments";
    NSString *aboutTitle = LOC(@"About");
    NSString *creditsTitle = LOC(@"Credits");

    [entries addObject:[self ytag_searchPageEntryWithTitle:privacyAdsTitle description:@"Remove ads and tighten privacy defaults in one place." path:@[privacyAdsTitle] aliases:@[@"sponsored", @"promotions", @"privacy", @"tracking"]]];
    [entries addObject:[self ytag_searchPageEntryWithTitle:interfaceTitle description:@"App chrome, tabs, startup, and input behavior." path:@[interfaceTitle] aliases:@[@"navigation", @"tab bar", @"keyboard"]]];
    [entries addObject:[self ytag_searchPageEntryWithTitle:navbarTitle description:@"Top bar buttons and header presentation." path:@[interfaceTitle, navbarTitle] aliases:@[@"top bar", @"header"]]];
    [entries addObject:[self ytag_searchPageEntryWithTitle:tabbarTitle description:@"Visible tabs, labels, indicators, and bar styling." path:@[interfaceTitle, tabbarTitle] aliases:@[@"tabs", @"pivot bar"]]];
    if (isAdvanced) {
        [entries addObject:[self ytag_searchPageEntryWithTitle:legacyTitle description:@"Experimental fallbacks for older YouTube UI behavior." path:@[interfaceTitle, legacyTitle] aliases:@[@"old youtube", @"compatibility"]]];
    }

    [entries addObject:[self ytag_searchPageEntryWithTitle:themesTitle description:@"Curated themes, custom colors, gradients, and polish." path:@[themesTitle] aliases:@[@"appearance", @"colors"]]];
    [entries addObject:[self ytag_searchPageEntryWithTitle:presetsTitle description:@"Complete looks for the whole app, grouped into dark and light palettes." path:@[themesTitle, presetsTitle] aliases:@[@"theme presets", @"afterglow themes"]]];
    [entries addObject:[self ytag_searchPageEntryWithTitle:customColorsTitle description:@"Fine-tune the exact surfaces and text colors the theme engine touches." path:@[themesTitle, customColorsTitle] aliases:@[@"theme colors", @"color overrides"]]];
    [entries addObject:[self ytag_searchPageEntryWithTitle:LOC(@"Typography") description:@"Choose the app-wide font face and tab label fit." path:@[themesTitle, LOC(@"Typography")] aliases:@[@"font", @"courier", @"typeface", @"tab label size"]]];
    [entries addObject:[self ytag_searchPageEntryWithTitle:effectsTitle description:@"Glow, ambient mode, seek animation, and gradient toggles." path:@[themesTitle, effectsTitle] aliases:@[@"glow", @"effects"]]];
    [entries addObject:[self ytag_searchPageEntryWithTitle:gradientTitle description:@"Optional background wash with a dedicated on or off workflow." path:@[themesTitle, gradientTitle] aliases:@[@"background gradient"]]];

    [entries addObject:[self ytag_searchPageEntryWithTitle:playerTitle description:@"Playback controls, defaults, quality, and on-video UI." path:@[playerTitle] aliases:@[@"video player"]]];
    [entries addObject:[self ytag_searchPageEntryWithTitle:playbackTitle description:@"Playback defaults, autoplay behavior, and watch-next cleanup." path:@[playerTitle, playbackTitle] aliases:@[@"autoplay", @"speed", @"quality"]]];
    [entries addObject:[self ytag_searchPageEntryWithTitle:controlsTitle description:@"Gestures, fullscreen behavior, and direct player interactions." path:@[playerTitle, controlsTitle] aliases:@[@"gestures", @"fullscreen"]]];
    [entries addObject:[self ytag_searchPageEntryWithTitle:buttonsMenusTitle description:@"Buttons shown directly under the player and overflow menu actions." path:@[playerTitle, buttonsMenusTitle] aliases:@[@"under player buttons", @"player menu", @"overflow menu"]]];
    if (isAdvanced) {
        [entries addObject:[self ytag_searchPageEntryWithTitle:overlayTitle description:@"HUD, autoplay, end-screen cards, and player chrome." path:@[playerTitle, overlayTitle] aliases:@[@"hud", @"overlay buttons"]]];
    }

    [entries addObject:[self ytag_searchPageEntryWithTitle:shortsTitle description:@"Behavior, conversion, and optional UI cleanup for Shorts." path:@[shortsTitle] aliases:@[@"reels"]]];
    if (isAdvanced) {
        [entries addObject:[self ytag_searchPageEntryWithTitle:layoutButtonsTitle description:@"Hide specific Shorts UI elements and action buttons." path:@[shortsTitle, layoutButtonsTitle] aliases:@[@"shorts layout", @"shorts buttons"]]];
    }

    [entries addObject:[self ytag_searchPageEntryWithTitle:downloadsTitle description:@"Download behavior, audio tracks, captions, and save handling." path:@[downloadsTitle] aliases:@[@"offline", @"save video", @"camera roll"]]];

    [entries addObject:[self ytag_searchPageEntryWithTitle:feedTitle description:@"Clean up the home feed and menu items." path:@[feedTitle] aliases:@[@"browse", @"video menus"]]];
    [entries addObject:[self ytag_searchPageEntryWithTitle:toolsTitle description:@"Extra utility actions that do not belong to one primary surface." path:@[toolsTitle] aliases:@[@"misc", @"utilities"]]];
    [entries addObject:[self ytag_searchPageEntryWithTitle:commentsTitle description:@"Comment header mode in one picker." path:@[commentsTitle] aliases:@[@"comment sorting"]]];

    [entries addObject:[self ytag_searchPageEntryWithTitle:aboutTitle description:@"Maintenance tools, advanced mode, and project credits." path:@[aboutTitle] aliases:@[@"settings info", @"maintenance"]]];
    [entries addObject:[self ytag_searchPageEntryWithTitle:creditsTitle description:@"Project stewardship, AI co-development, and open-source acknowledgements." path:@[aboutTitle, creditsTitle] aliases:@[@"about", @"acknowledgements"]]];

    [self ytag_addSearchEntries:entries forSettingKeys:@[@"LiteMode"] path:@[LOC(@"Main")] aliasesByKey:@{
        @"LiteMode": @[@"minimal", @"distraction free", @"bare bones", @"monochrome"]
    }];

    [self ytag_addSearchEntries:entries forSettingKeys:@[@"RemoveAds", @"NoPromotionCards", @"NoSearchHistory", @"NoLinkTracking", @"NoShareChunk"] path:@[privacyAdsTitle] aliasesByKey:@{
        @"NoSearchHistory": @[@"search suggestions", @"recent searches"],
        @"NoLinkTracking": @[@"tracking links", @"redirects"],
        @"NoShareChunk": @[@"clean links", @"shared links"]
    }];

    [self ytag_addSearchEntries:entries forSettingKeys:@[@"RemoveCast", @"RemoveNotifications", @"RemoveSearch", @"RemoveVoiceSearch"] path:@[interfaceTitle, navbarTitle] aliasesByKey:nil];
    if (isAdvanced) {
        [self ytag_addSearchEntries:entries forSettingKeys:@[@"StickyNavbar", @"NoSubbar", @"NoYTLogo", @"PremiumYTLogo"] path:@[interfaceTitle, navbarTitle] aliasesByKey:nil];
    }

    [self ytag_addSearchEntries:entries forSettingKeys:@[@"OpaqueBar", @"RemoveLabels", @"RemoveIndicators", @"TwoRowTabBar"] path:@[interfaceTitle, tabbarTitle] aliasesByKey:@{
        @"TwoRowTabBar": @[@"bonus row", @"two row", @"second row", @"all tabs", @"pivot overflow"]
    }];
    [entries addObject:[self ytag_searchEntryWithTitle:@"Customize Tabs" description:@"Choose which tabs are shown and drag them into the order you want." path:@[interfaceTitle, tabbarTitle] targetTitle:@"Customize Tabs" aliases:@[@"manage tabs", @"tab editor", @"reorder tabs"]]];

    [entries addObject:[self ytag_searchEntryWithTitle:LOC(@"Startup") description:@"Choose which active tab opens first." path:@[interfaceTitle] targetTitle:LOC(@"Startup") aliases:@[@"startup tab", @"launch tab"]]];
    [self ytag_addSearchEntries:entries forSettingKeys:@[@"StartupAnimation", @"FloatingKeyboard"] path:@[interfaceTitle] aliasesByKey:@{
        @"FloatingKeyboard": @[@"ipad keyboard"]
    }];
    if (isAdvanced) {
        [self ytag_addSearchEntries:entries forSettingKeys:@[@"DisableRTL"] path:@[interfaceTitle] aliasesByKey:@{ @"DisableRTL": @[@"right to left", @"ltr"] }];
        [self ytag_addSearchEntries:entries forSettingKeys:@[@"OldYTUI"] path:@[interfaceTitle, legacyTitle] aliasesByKey:@{ @"OldYTUI": @[@"legacy ui"] }];
    }
    [entries addObject:[self ytag_searchEntryWithTitle:LOC(@"ResetAllColors") description:@"Clear every theme override and go back to stock colors." path:@[themesTitle] targetTitle:LOC(@"ResetAllColors") aliases:@[@"reset theme", @"default theme"]]];
    [self ytag_addSearchEntries:entries forLiteralTitles:@[
        @"OLED Dark", @"Midnight Blue", @"Forest Green", @"Afterglow Gray Dark", @"Afterglow 1", @"Afterglow 2", @"Afterglow 3", @"Afterglow 4",
        @"Clean White", @"Warm Sand", @"Ocean Breeze", @"Rose Gold", @"Afterglow Gray Light", @"Afterglow Light 1", @"Afterglow Light 2", @"Afterglow Light 3", @"Afterglow Light 4"
    ] path:@[themesTitle, presetsTitle] descriptionsByTitle:nil aliasesByTitle:@{
        @"OLED Dark": @[@"black theme"],
        @"Afterglow Gray Dark": @[@"lite gray", @"monochrome", @"charcoal"],
        @"Afterglow Gray Light": @[@"lite gray", @"monochrome", @"pale gray"],
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
    [self ytag_addSearchEntries:entries forSettingKeys:@[@"AppFont", @"TabLabelSize"] path:@[themesTitle, LOC(@"Typography")] aliasesByKey:@{
        @"AppFont": @[@"font", @"courier", @"typography"],
        @"TabLabelSize": @[@"tab font size", @"tab label", @"subscriptions wrapping"]
    }];
    [self ytag_addSearchEntries:entries forSettingKeys:@[@"EnableGlow", @"GlowStrength", @"GlowPivot", @"GlowOverlay", @"GlowScrubber", @"GlowSeekBar", @"AnimateSeek", @"DisableAmbientMode", @"SeekBarGradient"] path:@[themesTitle, effectsTitle] aliasesByKey:nil];
    [self ytag_addSearchEntries:entries forSettingKeys:@[@"PersistentProgressBar", @"HideHeatwaves"] path:@[themesTitle, @"Seek Bar"] aliasesByKey:nil];
    [self ytag_addSearchEntries:entries forSettingKeys:@[@"GradientStart", @"GradientEnd"] path:@[themesTitle, gradientTitle] aliasesByKey:nil];

    [self ytag_addSearchEntries:entries forSettingKeys:@[@"BackgroundPlayback", @"HoldToSpeed", @"DefaultPlaybackRate", @"PlaybackQualityOnWiFi", @"PlaybackQualityOnCellular", @"Autoplay", @"DisableAutoCaptions", @"RememberCaptionState", @"RememberLoopMode", @"ClassicQuality", @"NoContentWarning", @"NoContinueWatching", @"NoRelatedWatchNexts", @"Miniplayer"] path:@[playerTitle, playbackTitle] aliasesByKey:@{
        @"HoldToSpeed": @[@"long press speed", @"2x"],
        @"NoContinueWatching": @[@"continue watching"],
        @"NoRelatedWatchNexts": @[@"watch next", @"videos under player"]
    }];
    if (isAdvanced) {
        [self ytag_addSearchEntries:entries forSettingKeys:@[@"NoEndScreenCards", @"NoRelatedVids", @"NoContinueWatchingPrompt", @"PlaylistOldMinibar"] path:@[playerTitle, playbackTitle] aliasesByKey:@{
            @"NoContinueWatchingPrompt": @[@"are you still watching"],
            @"NoRelatedVids": @[@"related videos"]
        }];
    }

    [self ytag_addSearchEntries:entries forSettingKeys:@[@"PortraitFullscreen", @"AutoFullscreen", @"ExitFullscreen", @"TapToSeek", @"NoDoubleTap2Seek", @"NoTwoFingerSnapToChapter", @"DontSnap2Chapter", @"NoFreeZoom"] path:@[playerTitle, controlsTitle] aliasesByKey:@{
        @"TapToSeek": @[@"tap seek"],
        @"DontSnap2Chapter": @[@"chapter snap"],
        @"NoDoubleTap2Seek": @[@"double tap seek"]
    }];
    [self ytag_addSearchEntries:entries forSettingKeys:@[@"NoPlayerDownloadButton", @"PlayerNoShare", @"PlayerNoSave", @"NoPlayerRemixButton", @"NoPlayerClipButton", @"RemoveDownloadMenu", @"RemoveShareMenu"] path:@[playerTitle, buttonsMenusTitle] aliasesByKey:nil];
    if (isAdvanced) {
        [self ytag_addSearchEntries:entries forSettingKeys:@[@"MuteButton", @"LockButton", @"DownloadButton", @"ControlsSheetButton", @"OverlayDeclutterButton", @"PauseOnOverlay", @"HideSubs", @"NoHUDMsgs", @"HidePrevNext", @"ReplacePrevNext", @"NoDarkBg", @"NoFullscreenActions", @"StockVolumeHUD", @"NoWatermarks", @"VideoEndTime", @"24hrFormat"] path:@[playerTitle, overlayTitle] aliasesByKey:@{
            @"DownloadButton": @[@"overlay download", @"download overlay"],
            @"ControlsSheetButton": @[@"premium controls", @"speed tile", @"stable volume", @"playback sheet"],
            @"OverlayDeclutterButton": @[@"hide overlay buttons", @"clean overlay", @"declutter overlay"]
        }];
    }

    [self ytag_addSearchEntries:entries forSettingKeys:@[@"ShortsOnlyMode", @"AutoSkipShorts", @"HideShorts", @"ShortsProgress", @"PinchToFullscreenShorts", @"ShortsToRegular", @"ResumeShorts"] path:@[shortsTitle] aliasesByKey:@{
        @"ShortsToRegular": @[@"convert shorts"],
        @"PinchToFullscreenShorts": @[@"pinch fullscreen"]
    }];
    if (isAdvanced) {
        [self ytag_addSearchEntries:entries forSettingKeys:@[@"HideShortsLogo", @"HideShortsSearch", @"HideShortsCamera", @"HideShortsMore", @"HideShortsSubscriptions", @"HideShortsLike", @"HideShortsDislike", @"HideShortsComments", @"HideShortsRemix", @"HideShortsShare", @"HideShortsAvatars", @"HideShortsThanks", @"HideShortsSource", @"HideShortsChannelName", @"HideShortsDescription", @"HideShortsAudioTrack", @"HideShortsPromoCards"] path:@[shortsTitle, layoutButtonsTitle] aliasesByKey:nil];
    }

    [self ytag_addSearchEntries:entries forSettingKeys:@[@"DownloadPostAction", @"DownloadRefreshMetadata", @"DownloadAudioTrack", @"DownloadAudioQuality", @"DownloadPreferStableAudio", @"DownloadIncludeAutoCaptions", @"DownloadOfferTranslatedCaptions", @"DownloadPickerTextSize", @"DownloadPickerFont"] path:@[downloadsTitle] aliasesByKey:@{
        @"DownloadPostAction": @[@"save to photos", @"share sheet", @"camera roll"],
        @"DownloadRefreshMetadata": @[@"captions fallback", @"metadata"],
        @"DownloadAudioTrack": @[@"audio language", @"dubbed audio", @"language tracks"],
        @"DownloadAudioQuality": @[@"high audio", @"premium audio"],
        @"DownloadPreferStableAudio": @[@"drc", @"stable volume"],
        @"DownloadIncludeAutoCaptions": @[@"auto captions", @"generated captions"],
        @"DownloadOfferTranslatedCaptions": @[@"translated subtitles", @"caption translation"],
        @"DownloadPickerTextSize": @[@"download font size", @"quality picker text"],
        @"DownloadPickerFont": @[@"download font face", @"quality picker font"]
    }];

    [self ytag_addSearchEntries:entries forSettingKeys:@[@"RemovePlayNext", @"RemoveWatchLaterMenu", @"RemoveSaveToPlaylistMenu", @"RemoveNotInterestedMenu", @"RemoveDontRecommendMenu", @"RemoveReportMenu"] path:@[feedTitle] aliasesByKey:@{
        @"RemoveDontRecommendMenu": @[@"don't recommend channel"]
    }];
    [self ytag_addSearchEntries:entries forSettingKeys:@[@"CommentsHeader"] path:@[commentsTitle] aliasesByKey:nil];

    [self ytag_addSearchEntries:entries forSettingKeys:@[@"CopyVideoInfo", @"SaveProfilePhoto", @"PostManager", @"CommentManager", @"NativeShare", @"FixAlbums", @"CopyWithTimestamp"] path:@[toolsTitle] aliasesByKey:@{
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
    NSArray *privacyAdsKeys = @[@"noAds", @"noPromotionCards", @"noSearchHistory", @"noLinkTracking", @"noShareChunk"];
    NSArray *navbarKeys = @[@"noCast", @"noNotifsButton", @"noSearchButton", @"noVoiceSearchButton", @"stickyNavbar", @"noSubbar", @"noYTLogo", @"premiumYTLogo"];
    NSArray *tabbarKeys = @[@"frostedPivot", @"removeLabels", @"removeIndicators", @"twoRowTabBar"];
    NSArray *legacyKeys = @[@"oldYTUI"];
    NSArray *interfaceKeys = [[[tabbarKeys arrayByAddingObject:@"startupAnimation"] arrayByAddingObject:@"floatingKeyboard"] arrayByAddingObjectsFromArray:[@[@"disableRTL"] arrayByAddingObjectsFromArray:legacyKeys]];
    NSArray *themeCustomColorKeys = @[@"theme_background", @"theme_navBar", @"theme_tabBarIcons", @"theme_overlayButtons", @"theme_seekBar", @"theme_textPrimary", @"theme_textSecondary", @"theme_accent"];
    NSArray *themeTypographyKeys = @[YTAGThemeFontModeKey, YTAGThemeTabLabelSizeModeKey];
    NSArray *themeSeekBarKeys = @[@"theme_seekBar", @"theme_seekBarLive", @"theme_seekBarScrubber", @"theme_seekBarScrubberLive", @"seekBarScrubberImage", @"seekBarScrubberSize", @"persistentProgressBar", @"hideHeatwaves"];
    NSArray *themeEffectKeys = @[@"theme_glowEnabled", @"theme_glowStrength", @"theme_glowStrengthMode", @"theme_glowStrengthCustom", @"theme_glowOpacity", @"theme_glowRadius", @"theme_glowLayers", @"theme_glowColor", @"theme_glowPivot", @"theme_glowOverlay", @"theme_glowScrubber", @"theme_glowSeekBar", @"seekBarAnimated", @"disableAmbientMode", @"seekBarGradient"];
    NSArray *themeGradientKeys = @[@"theme_gradientStart", @"theme_gradientEnd"];
    NSArray *themeKeys = [[[themeCustomColorKeys arrayByAddingObjectsFromArray:themeTypographyKeys] arrayByAddingObjectsFromArray:themeSeekBarKeys] arrayByAddingObjectsFromArray:[themeEffectKeys arrayByAddingObjectsFromArray:themeGradientKeys]];
    NSArray *playerPlaybackKeys = @[@"backgroundPlayback", @"speedIndex", @"autoSpeedIndex", @"wiFiQualityIndex", @"cellQualityIndex", @"disableAutoCaptions", @"rememberCaptionState", @"rememberLoop", @"noContentWarning", @"classicQuality", @"hideEndScreenCards", @"noRelatedVids", @"noContinueWatching", @"noContinueWatchingPrompt", @"noRelatedWatchNexts", @"miniplayer", @"playlistOldMinibar", @"autoplayMode"];
    NSArray *playerControlKeys = @[@"portraitFullscreen", @"tapToSeek", @"dontSnapToChapter", @"noTwoFingerSnapToChapter", @"noFreeZoom", @"autoFullscreen", @"exitFullscreen", @"noDoubleTapToSeek"];
    NSArray *playerOverlayKeys = @[@"muteButton", @"lockButton", @"downloadButton", @"controlsSheetButton", @"overlayDeclutterButton", @"hideSubs", @"noHUDMsgs", @"hidePrevNext", @"replacePrevNext", @"noDarkBg", @"noFullscreenActions", @"pauseOnOverlay", @"stockVolumeHUD", @"noWatermarks", @"videoEndTime", @"24hrFormat"];
    NSArray *playerActionBarKeys = @[@"noPlayerDownloadButton", @"noPlayerShareButton", @"noPlayerSaveButton", @"noPlayerRemixButton", @"noPlayerClipButton"];
    NSArray *playerMenuKeys = @[@"removeDownloadMenu", @"removeShareMenu"];
    NSArray *playerKeys = [[[[playerPlaybackKeys arrayByAddingObjectsFromArray:playerControlKeys] arrayByAddingObjectsFromArray:playerOverlayKeys] arrayByAddingObjectsFromArray:playerActionBarKeys] arrayByAddingObjectsFromArray:playerMenuKeys];
    NSArray *shortsBehaviorKeys = @[@"shortsOnlyMode", @"autoSkipShorts", @"hideShorts", @"shortsProgress", @"pinchToFullscreenShorts", @"shortsToRegular", @"resumeShorts"];
    NSArray *shortsUIKeys = @[@"hideShortsLogo", @"hideShortsSearch", @"hideShortsCamera", @"hideShortsMore", @"hideShortsSubscriptions", @"hideShortsLike", @"hideShortsDislike", @"hideShortsComments", @"hideShortsRemix", @"hideShortsShare", @"hideShortsAvatars", @"hideShortsThanks", @"hideShortsSource", @"hideShortsChannelName", @"hideShortsDescription", @"hideShortsAudioTrack", @"hideShortsPromoCards"];
    NSArray *downloadKeys = @[@"downloadPostActionMode", @"downloadRefreshMetadata", @"downloadAudioTrackMode", @"downloadAudioQualityMode", @"downloadPreferStableAudio", @"downloadIncludeAutoCaptions", @"downloadOfferTranslatedCaptions", @"downloadPickerFontScaleMode", @"downloadPickerFontFaceMode"];
    NSArray *feedToggleKeys = @[@"removePlayNext", @"removeWatchLaterMenu", @"removeSaveToPlaylistMenu", @"removeNotInterestedMenu", @"removeDontRecommendMenu", @"removeReportMenu"];
    NSArray *feedKeys = feedToggleKeys;
    NSArray *toolKeys = @[@"copyVideoInfo", @"postManager", @"saveProfilePhoto", @"commentManager", @"fixAlbums", @"nativeShare", @"copyWithTimestamp"];

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
    [sectionItems addObject:[self switchWithTitle:@"LiteMode" key:YTAGLiteModeEnabledKey]];

    YTSettingsSectionItem *privacyAds = [self pageItemWithTitle:@"Privacy & Ads"
        titleDescription:@"Remove ads and tighten privacy defaults in one place."
        summary:^NSString *() {
            return [self enabledSummaryForKeys:privacyAdsKeys];
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray <YTSettingsSectionItem *> *rows = [@[
                [self switchWithTitle:@"RemoveAds" key:@"noAds"],
                [self switchWithTitle:@"NoPromotionCards" key:@"noPromotionCards"],
                space,
                [self themeSectionHeaderWithTitle:@"Privacy" description:@"Search privacy, redirects, and shared-link cleanup."],
                [self switchWithTitle:@"NoSearchHistory" key:@"noSearchHistory"],
                [self switchWithTitle:@"NoLinkTracking" key:@"noLinkTracking"],
                [self switchWithTitle:@"NoShareChunk" key:@"noShareChunk"]
            ] mutableCopy];
            [self addResetDefaultsItemForKeys:privacyAdsKeys toRows:rows settingsVC:settingsViewController];

            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:@"Privacy & Ads" pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:privacyAds];

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
	                    NSArray *visibleNavbarKeys = isAdvanced ? navbarKeys : @[@"noCast", @"noNotifsButton", @"noSearchButton", @"noVoiceSearchButton"];
	                    [self addResetDefaultsItemForKeys:visibleNavbarKeys toRows:navbarRows settingsVC:settingsViewController];

	                    YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Navbar") pickerSectionTitle:nil rows:navbarRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                    [settingsViewController pushViewController:picker];
                    return YES;
                }]];

            [rows addObject:[self pageItemWithTitle:LOC(@"Tabbar")
                titleDescription:@"Choose your tabs and tune how the bottom bar looks."
                summary:^NSString *() {
                    return [NSString stringWithFormat:@"%lu tabs", (unsigned long)[[YTAGUserDefaults standardUserDefaults] currentActiveTabs].count];
                }
                selectBlock:^BOOL (YTSettingsCell *innerCell, NSUInteger innerArg1) {
                    NSMutableArray <YTSettingsSectionItem *> *tabRows = [NSMutableArray array];
                    [tabRows addObject:[self switchWithTitle:@"OpaqueBar" key:@"frostedPivot"]];
                    [tabRows addObject:[self switchWithTitle:@"RemoveLabels" key:@"removeLabels"]];
                    [tabRows addObject:[self switchWithTitle:@"RemoveIndicators" key:@"removeIndicators"]];
                    [tabRows addObject:[self switchWithTitle:@"TwoRowTabBar" key:@"twoRowTabBar"]];
	                    [tabRows addObject:[self pageItemWithTitle:@"Customize Tabs"
                        titleDescription:@"Choose which tabs are shown and drag them into the order you want."
                        summary:^NSString *() {
                            return [NSString stringWithFormat:@"%lu shown", (unsigned long)[[YTAGUserDefaults standardUserDefaults] currentActiveTabs].count];
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
	                    [self addResetDefaultsItemForKeys:[tabbarKeys arrayByAddingObject:@"activeTabs"] toRows:tabRows settingsVC:settingsViewController];

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
	                        NSMutableArray <YTSettingsSectionItem *> *legacyRows = [@[
	                            [self switchWithTitle:@"OldYTUI" key:@"oldYTUI"]
	                        ] mutableCopy];
	                        [self addResetDefaultsItemForKeys:legacyKeys toRows:legacyRows settingsVC:settingsViewController];

	                        YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:@"Legacy" pickerSectionTitle:nil rows:legacyRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
	                        [settingsViewController pushViewController:picker];
	                        return YES;
	                    }]];
	            }
	            NSArray *interfacePageKeys = isAdvanced ? @[@"startupTab", @"startupAnimation", @"floatingKeyboard", @"disableRTL"] : @[@"startupTab", @"startupAnimation", @"floatingKeyboard"];
	            [self addResetDefaultsItemForKeys:interfacePageKeys toRows:rows settingsVC:settingsViewController];

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
                    return @"19 curated";
                }
                selectBlock:^BOOL(YTSettingsCell *presetCell, NSUInteger presetArg1) {
                    NSMutableArray <YTSettingsSectionItem *> *presetRows = [NSMutableArray array];
                    [presetRows addObject:[self themeSectionHeaderWithTitle:@"Dark Themes" description:@"Richer palettes with more contrast and depth."]];
                    [self themeAddPresetRowWithName:@"OLED Dark" titleDescription:@"Pure black with sharp red accents." overlay:[UIColor whiteColor] tabIcons:[UIColor whiteColor] seekBar:[UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:1.0] bg:[UIColor blackColor] textP:[UIColor whiteColor] textS:[UIColor colorWithRed:0.65 green:0.65 blue:0.65 alpha:1.0] nav:[UIColor blackColor] accent:[UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:1.0] gradientStart:nil gradientEnd:nil toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Midnight Blue" titleDescription:@"Cool navy with bright blue controls." overlay:[UIColor colorWithRed:0.6 green:0.8 blue:1.0 alpha:1.0] tabIcons:[UIColor colorWithRed:0.4 green:0.7 blue:1.0 alpha:1.0] seekBar:[UIColor colorWithRed:0.2 green:0.5 blue:1.0 alpha:1.0] bg:[UIColor colorWithRed:0.05 green:0.05 blue:0.15 alpha:1.0] textP:[UIColor colorWithRed:0.85 green:0.9 blue:1.0 alpha:1.0] textS:[UIColor colorWithRed:0.5 green:0.6 blue:0.75 alpha:1.0] nav:[UIColor colorWithRed:0.08 green:0.08 blue:0.2 alpha:1.0] accent:[UIColor colorWithRed:0.2 green:0.5 blue:1.0 alpha:1.0] gradientStart:nil gradientEnd:nil toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Solarized Dark" titleDescription:@"Muted solarized tones with teal and gold." overlay:[UIColor colorWithRed:0.51 green:0.58 blue:0.59 alpha:1.0] tabIcons:[UIColor colorWithRed:0.51 green:0.58 blue:0.59 alpha:1.0] seekBar:[UIColor colorWithRed:0.52 green:0.60 blue:0.0 alpha:1.0] bg:[UIColor colorWithRed:0.0 green:0.17 blue:0.21 alpha:1.0] textP:[UIColor colorWithRed:0.93 green:0.91 blue:0.84 alpha:1.0] textS:[UIColor colorWithRed:0.51 green:0.58 blue:0.59 alpha:1.0] nav:[UIColor colorWithRed:0.03 green:0.21 blue:0.26 alpha:1.0] accent:[UIColor colorWithRed:0.15 green:0.55 blue:0.82 alpha:1.0] gradientStart:nil gradientEnd:nil toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Monokai" titleDescription:@"High-contrast editor greens and pinks." overlay:[UIColor colorWithRed:0.97 green:0.97 blue:0.95 alpha:1.0] tabIcons:[UIColor colorWithRed:0.65 green:0.89 blue:0.18 alpha:1.0] seekBar:[UIColor colorWithRed:0.98 green:0.15 blue:0.45 alpha:1.0] bg:[UIColor colorWithRed:0.15 green:0.16 blue:0.13 alpha:1.0] textP:[UIColor colorWithRed:0.97 green:0.97 blue:0.95 alpha:1.0] textS:[UIColor colorWithRed:0.46 green:0.44 blue:0.37 alpha:1.0] nav:[UIColor colorWithRed:0.2 green:0.2 blue:0.17 alpha:1.0] accent:[UIColor colorWithRed:0.40 green:0.85 blue:0.94 alpha:1.0] gradientStart:nil gradientEnd:nil toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Forest" titleDescription:@"Deep green with a calm natural feel." overlay:[UIColor colorWithRed:0.8 green:0.93 blue:0.8 alpha:1.0] tabIcons:[UIColor colorWithRed:0.4 green:0.75 blue:0.4 alpha:1.0] seekBar:[UIColor colorWithRed:0.3 green:0.7 blue:0.3 alpha:1.0] bg:[UIColor colorWithRed:0.06 green:0.1 blue:0.06 alpha:1.0] textP:[UIColor colorWithRed:0.85 green:0.95 blue:0.85 alpha:1.0] textS:[UIColor colorWithRed:0.5 green:0.65 blue:0.5 alpha:1.0] nav:[UIColor colorWithRed:0.08 green:0.14 blue:0.08 alpha:1.0] accent:[UIColor colorWithRed:0.3 green:0.7 blue:0.3 alpha:1.0] gradientStart:nil gradientEnd:nil toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Afterglow Gray Dark" titleDescription:@"Lite-inspired charcoal monochrome with soft white controls." overlay:[UIColor colorWithWhite:0.98 alpha:1.0] tabIcons:[UIColor colorWithWhite:0.96 alpha:1.0] seekBar:[UIColor colorWithWhite:0.92 alpha:1.0] bg:[UIColor colorWithWhite:0.18 alpha:1.0] textP:[UIColor colorWithWhite:0.96 alpha:1.0] textS:[UIColor colorWithWhite:0.78 alpha:1.0] nav:[UIColor colorWithWhite:0.24 alpha:1.0] accent:[UIColor colorWithWhite:1.0 alpha:1.0] gradientStart:nil gradientEnd:nil toRows:presetRows settingsVC:settingsViewController];
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
                    [self themeAddPresetRowWithName:@"Afterglow Gray Light" titleDescription:@"Lite-inspired pale monochrome with crisp dark controls." overlay:[UIColor colorWithWhite:0.12 alpha:1.0] tabIcons:[UIColor colorWithWhite:0.16 alpha:1.0] seekBar:[UIColor colorWithWhite:0.28 alpha:1.0] bg:[UIColor colorWithWhite:0.90 alpha:1.0] textP:[UIColor colorWithWhite:0.10 alpha:1.0] textS:[UIColor colorWithWhite:0.40 alpha:1.0] nav:[UIColor colorWithWhite:0.96 alpha:1.0] accent:[UIColor colorWithWhite:0.20 alpha:1.0] gradientStart:nil gradientEnd:nil toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Afterglow Light 1" titleDescription:@"Candyglass daylight with a real lilac body color and aqua chrome." overlay:[UIColor colorWithRed:0.55 green:0.19 blue:0.54 alpha:1.0] tabIcons:[UIColor colorWithRed:0.03 green:0.72 blue:0.82 alpha:1.0] seekBar:[UIColor colorWithRed:0.98 green:0.33 blue:0.69 alpha:1.0] bg:[UIColor colorWithRed:0.97 green:0.84 blue:1.00 alpha:1.0] textP:[UIColor colorWithRed:0.24 green:0.08 blue:0.33 alpha:1.0] textS:[UIColor colorWithRed:0.46 green:0.27 blue:0.58 alpha:1.0] nav:[UIColor colorWithRed:0.93 green:0.76 blue:1.00 alpha:1.0] accent:[UIColor colorWithRed:0.08 green:0.80 blue:0.84 alpha:1.0] gradientStart:[UIColor colorWithRed:1.00 green:0.84 blue:0.93 alpha:1.0] gradientEnd:[UIColor colorWithRed:0.73 green:0.95 blue:1.00 alpha:1.0] toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Afterglow Light 2" titleDescription:@"Apricot sunset with coral punch, hot pink sparks, and blue contrast." overlay:[UIColor colorWithRed:0.60 green:0.24 blue:0.14 alpha:1.0] tabIcons:[UIColor colorWithRed:0.97 green:0.44 blue:0.12 alpha:1.0] seekBar:[UIColor colorWithRed:1.00 green:0.31 blue:0.44 alpha:1.0] bg:[UIColor colorWithRed:1.00 green:0.86 blue:0.72 alpha:1.0] textP:[UIColor colorWithRed:0.30 green:0.12 blue:0.09 alpha:1.0] textS:[UIColor colorWithRed:0.58 green:0.30 blue:0.28 alpha:1.0] nav:[UIColor colorWithRed:1.00 green:0.79 blue:0.64 alpha:1.0] accent:[UIColor colorWithRed:0.28 green:0.67 blue:1.00 alpha:1.0] gradientStart:[UIColor colorWithRed:1.00 green:0.90 blue:0.69 alpha:1.0] gradientEnd:[UIColor colorWithRed:1.00 green:0.68 blue:0.73 alpha:1.0] toRows:presetRows settingsVC:settingsViewController];
                    [self themeAddPresetRowWithName:@"Afterglow Light 3" titleDescription:@"Mint arcade glass with louder teal, berry pink, and violet energy." overlay:[UIColor colorWithRed:0.13 green:0.40 blue:0.40 alpha:1.0] tabIcons:[UIColor colorWithRed:0.00 green:0.68 blue:0.61 alpha:1.0] seekBar:[UIColor colorWithRed:0.98 green:0.37 blue:0.58 alpha:1.0] bg:[UIColor colorWithRed:0.80 green:1.00 blue:0.91 alpha:1.0] textP:[UIColor colorWithRed:0.08 green:0.22 blue:0.24 alpha:1.0] textS:[UIColor colorWithRed:0.28 green:0.47 blue:0.49 alpha:1.0] nav:[UIColor colorWithRed:0.72 green:0.98 blue:0.89 alpha:1.0] accent:[UIColor colorWithRed:0.41 green:0.30 blue:0.95 alpha:1.0] gradientStart:[UIColor colorWithRed:0.82 green:1.00 blue:0.94 alpha:1.0] gradientEnd:[UIColor colorWithRed:0.93 green:0.84 blue:1.00 alpha:1.0] toRows:presetRows settingsVC:settingsViewController];
	                    [self themeAddPresetRowWithName:@"Afterglow Light 4" titleDescription:@"Sky chrome with icy blue glass, coral sparks, and violet-pop contrast." overlay:[UIColor colorWithRed:0.21 green:0.31 blue:0.66 alpha:1.0] tabIcons:[UIColor colorWithRed:0.17 green:0.50 blue:1.00 alpha:1.0] seekBar:[UIColor colorWithRed:1.00 green:0.40 blue:0.47 alpha:1.0] bg:[UIColor colorWithRed:0.82 green:0.91 blue:1.00 alpha:1.0] textP:[UIColor colorWithRed:0.11 green:0.18 blue:0.39 alpha:1.0] textS:[UIColor colorWithRed:0.29 green:0.39 blue:0.63 alpha:1.0] nav:[UIColor colorWithRed:0.74 green:0.84 blue:1.00 alpha:1.0] accent:[UIColor colorWithRed:0.84 green:0.31 blue:0.68 alpha:1.0] gradientStart:[UIColor colorWithRed:0.82 green:0.93 blue:1.00 alpha:1.0] gradientEnd:[UIColor colorWithRed:0.92 green:0.84 blue:1.00 alpha:1.0] toRows:presetRows settingsVC:settingsViewController];
	                    [self addResetDefaultsItemForKeys:themeKeys toRows:presetRows settingsVC:settingsViewController];

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
	                    [self addResetDefaultsItemForKeys:themeCustomColorKeys toRows:colorRows settingsVC:settingsViewController];

	                    YTSettingsPickerViewController *colorPicker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"CustomColors") pickerSectionTitle:nil rows:colorRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                    [settingsViewController pushViewController:colorPicker];
                    return YES;
                }]];

            [appearanceRows addObject:[self pageItemWithTitle:LOC(@"Typography")
                titleDescription:@"Choose the font Afterglow applies to YouTube text and tab labels."
                summary:^NSString *() {
                    return [self themeTypographySummary];
                }
                selectBlock:^BOOL(YTSettingsCell *typographyCell, NSUInteger typographyArg1) {
                    NSMutableArray <YTSettingsSectionItem *> *typographyRows = [NSMutableArray array];
                    [typographyRows addObject:[self themeSectionHeaderWithTitle:LOC(@"Typography") description:@"Auto uses Courier New while Lite Mode is enabled and stock system text otherwise. Tab labels stay on one line and shrink when needed."]];
                    [typographyRows addObject:[self ytagPickerItemWithTitle:LOC(@"AppFont")
                                                               description:LOC(@"AppFontDesc")
                                                                       key:YTAGThemeFontModeKey
                                                                    labels:YTAGThemeFontModeDisplayNames()
                                                                settingsVC:settingsViewController]];
                    [typographyRows addObject:[self ytagPickerItemWithTitle:LOC(@"TabLabelSize")
                                                               description:LOC(@"TabLabelSizeDesc")
                                                                       key:YTAGThemeTabLabelSizeModeKey
                                                                    labels:YTAGThemeTabLabelSizeModeDisplayNames()
                                                                settingsVC:settingsViewController]];
                    [self addResetDefaultsItemForKeys:themeTypographyKeys toRows:typographyRows settingsVC:settingsViewController];

                    YTSettingsPickerViewController *typographyPicker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Typography") pickerSectionTitle:nil rows:typographyRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                    [settingsViewController pushViewController:typographyPicker];
                    return YES;
                }]];

            [appearanceRows addObject:[self pageItemWithTitle:@"Seek Bar"
                titleDescription:@"Color, scrubber dot, custom icon, size, and animations for the progress bar."
                summary:^NSString *() {
                    return [self themeSeekBarSummary];
                }
                selectBlock:^BOOL(YTSettingsCell *seekCell, NSUInteger seekArg1) {
                    NSMutableArray <YTSettingsSectionItem *> *seekRows = [NSMutableArray array];
                    [seekRows addObject:[self themeSectionHeaderWithTitle:@"Track" description:@"Recolor the entire played portion across every surface."]];
                    [self themeAddColorRowWithTitle:@"SeekBar" titleDescription:@"Color of the played progress track." themeKey:@"theme_seekBar" toRows:seekRows settingsVC:settingsViewController];
                    [self themeAddColorRowWithTitle:@"SeekBarLive" titleDescription:@"Track color while watching live streams." themeKey:@"theme_seekBarLive" toRows:seekRows settingsVC:settingsViewController];
                    [seekRows addObject:space];
                    [seekRows addObject:[self themeSectionHeaderWithTitle:@"Scrubber Dot" description:@"The ball users drag to scrub. Set a color or replace with a custom image."]];
                    [self themeAddColorRowWithTitle:@"SeekBarScrubber" titleDescription:@"Color of the scrubber ball." themeKey:@"theme_seekBarScrubber" toRows:seekRows settingsVC:settingsViewController];
                    [self themeAddColorRowWithTitle:@"SeekBarScrubberLive" titleDescription:@"Scrubber ball color for live streams." themeKey:@"theme_seekBarScrubberLive" toRows:seekRows settingsVC:settingsViewController];

                    // Custom scrubber image
                    BOOL hasImage = [[YTAGUserDefaults standardUserDefaults] objectForKey:@"seekBarScrubberImage"] != nil;
                    [seekRows addObject:[%c(YTSettingsSectionItem) itemWithTitle:@"Custom Scrubber Image"
                        titleDescription:@"Replace the scrubber ball with a PNG from your photos library. Images are auto-scaled to 60pt."
                        accessibilityIdentifier:@"YTAfterglowSectionItem"
                        detailTextBlock:^NSString *() {
                            return [[YTAGUserDefaults standardUserDefaults] objectForKey:@"seekBarScrubberImage"] != nil ? @"Set" : LOC(@"None");
                        }
                        selectBlock:^BOOL(YTSettingsCell *imgCell, NSUInteger imgArg1) {
                            if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) return YES;
                            UIImagePickerController *picker = [[UIImagePickerController alloc] init];
                            picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
                            picker.allowsEditing = NO;
                            YTAGImagePickerDelegate *delegate = [[YTAGImagePickerDelegate alloc] init];
                            delegate.prefKey = @"seekBarScrubberImage";
                            delegate.settingsVC = settingsViewController;
                            picker.delegate = delegate;
                            _imagePickerDelegate = delegate;
                            UIViewController *presenter = settingsViewController.navigationController.topViewController ?: settingsViewController;
                            while (presenter.presentedViewController) presenter = presenter.presentedViewController;
                            [presenter presentViewController:picker animated:YES completion:nil];
                            return YES;
                        }]];
                    if (hasImage) {
                        [seekRows addObject:[%c(YTSettingsSectionItem) itemWithTitle:@"Remove Custom Image"
                            titleDescription:@"Go back to the stock scrubber ball."
                            accessibilityIdentifier:@"YTAfterglowSectionItem"
                            detailTextBlock:^NSString *() { return @"Clear"; }
                            selectBlock:^BOOL(YTSettingsCell *clearCell, NSUInteger clearArg1) {
                                [[YTAGUserDefaults standardUserDefaults] removeObjectForKey:@"seekBarScrubberImage"];
                                ytag_refreshSettingsHierarchy(settingsViewController);
                                return YES;
                            }]];
                    }

                    [seekRows addObject:space];
                    [seekRows addObject:[self themeSectionHeaderWithTitle:@"Size & Motion" description:@"Make the scrubber ball bigger or add animated transitions on seek."]];

                    // Scrubber size — picker of 0, 25, 50, 75, 100
                    NSArray *sizeLabels = @[LOC(@"Default"), @"25%", @"50%", @"75%", @"100%"];
                    NSArray *sizeValues = @[@0, @25, @50, @75, @100];
                    NSInteger currentSize = ytagInt(@"seekBarScrubberSize");
                    NSUInteger selectedIndex = 0;
                    for (NSUInteger i = 0; i < sizeValues.count; i++) {
                        if ([sizeValues[i] integerValue] == currentSize) { selectedIndex = i; break; }
                    }
                    [seekRows addObject:[%c(YTSettingsSectionItem) itemWithTitle:@"Scrubber Size"
                        titleDescription:@"Scale the scrubber ball (and custom image if set)."
                        accessibilityIdentifier:@"YTAfterglowSectionItem"
                        detailTextBlock:^NSString *() {
                            NSInteger size = ytagInt(@"seekBarScrubberSize");
                            if (size == 0) return LOC(@"Default");
                            return [NSString stringWithFormat:@"+%ld%%", (long)size];
                        }
                        selectBlock:^BOOL(YTSettingsCell *sizeCell, NSUInteger sizeArg1) {
                            NSMutableArray *sizeRows = [NSMutableArray array];
                            for (NSUInteger i = 0; i < sizeLabels.count; i++) {
                                NSNumber *value = sizeValues[i];
                                NSString *label = sizeLabels[i];
                                [sizeRows addObject:[%c(YTSettingsSectionItem) checkmarkItemWithTitle:label
                                    selectBlock:^BOOL(YTSettingsCell *c, NSUInteger a) {
                                        ytagSetInt([value integerValue], @"seekBarScrubberSize");
                                        ytag_refreshSettingsHierarchy(settingsViewController);
                                        [(UINavigationController *)settingsViewController.navigationController popViewControllerAnimated:YES];
                                        return YES;
                                    }]];
                            }
                            YTSettingsPickerViewController *sizePicker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:@"Scrubber Size" pickerSectionTitle:nil rows:sizeRows selectedItemIndex:selectedIndex parentResponder:[self parentResponder]];
                            [settingsViewController pushViewController:sizePicker];
                            return YES;
                        }]];

                    [seekRows addObject:[self switchWithTitle:@"PersistentProgressBar" key:@"persistentProgressBar"]];
                    [seekRows addObject:[self switchWithTitle:@"HideHeatwaves" key:@"hideHeatwaves"]];

	                    [self addResetDefaultsItemForKeys:themeSeekBarKeys toRows:seekRows settingsVC:settingsViewController];

	                    YTSettingsPickerViewController *seekPicker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:@"Seek Bar" pickerSectionTitle:nil rows:seekRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                    [settingsViewController pushViewController:seekPicker];
                    return YES;
                }]];

            [appearanceRows addObject:[self pageItemWithTitle:@"Effects"
                titleDescription:@"Glow, ambient mode, seek animation, and gradient toggles."
                summary:^NSString *() {
                    return [self enabledSummaryForKeys:@[@"theme_glowEnabled", @"theme_glowPivot", @"theme_glowOverlay", @"theme_glowScrubber", @"theme_glowSeekBar", @"seekBarAnimated", @"disableAmbientMode", @"seekBarGradient"]];
                }
                selectBlock:^BOOL(YTSettingsCell *effectsCell, NSUInteger effectsArg1) {
                    Class YTSettingsSectionItemClass = %c(YTSettingsSectionItem);
                    NSArray *glowStrengthLabels = @[@"Subtle", @"Normal", @"Strong", @"Custom..."];
                    NSInteger selectedGlowStrength = [self themeGlowStrengthMode];
                    NSMutableArray <YTSettingsSectionItem *> *effectRows = [NSMutableArray array];
                    [effectRows addObject:[self switchWithTitle:@"EnableGlow" key:@"theme_glowEnabled"]];
                    [effectRows addObject:[YTSettingsSectionItemClass itemWithTitle:LOC(@"GlowStrength")
                        accessibilityIdentifier:@"YTAfterglowSectionItem"
                        detailTextBlock:^NSString *() {
                            return [self themeGlowStrengthDetail];
                        }
                        selectBlock:^BOOL (YTSettingsCell *glowCell, NSUInteger glowArg1) {
                            NSMutableArray <YTSettingsSectionItem *> *rows = [NSMutableArray array];
                            for (NSUInteger i = 0; i < glowStrengthLabels.count; i++) {
                                NSString *title = glowStrengthLabels[i];
                                [rows addObject:[YTSettingsSectionItemClass checkmarkItemWithTitle:title titleDescription:nil selectBlock:^BOOL (YTSettingsCell *innerCell, NSUInteger innerArg1) {
                                    if (innerArg1 == 3) {
                                        [self themePresentGlowNumberInputWithTitle:@"Custom Glow Strength"
                                                                 titleDescription:@"Enter an exact glow strength value."
                                                                               key:@"theme_glowStrengthCustom"
                                                                               min:0
                                                                               max:100
                                                                          fallback:50
                                                                            suffix:@"/100"
                                                                              cell:innerCell
                                                                        settingsVC:settingsViewController
                                                                         afterSave:^(NSInteger value) {
                                            ytagSetInt(3, @"theme_glowStrengthMode");
                                            ytagSetInt((int)value, @"theme_glowStrength");
                                        }];
                                    } else {
                                        ytagSetInt((int)innerArg1, @"theme_glowStrengthMode");
                                        ytagSetInt((int)innerArg1, @"theme_glowStrength");
                                        ytag_refreshSettingsHierarchy(settingsViewController);
                                    }
                                    return YES;
                                }]];
                            }
                            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"GlowStrength") pickerSectionTitle:nil rows:rows selectedItemIndex:selectedGlowStrength parentResponder:[self parentResponder]];
                            [settingsViewController pushViewController:picker];
                            return YES;
                        }]];
                    [effectRows addObject:space];
                    [effectRows addObject:[self themeSectionHeaderWithTitle:@"Custom Glow" description:@"Exact values override the preset feel without removing the preset shortcuts."]];
                    [self themeAddColorRowWithTitle:@"Glow Color" titleDescription:@"Optional global glow color. Default uses the surface color being glowed." themeKey:@"theme_glowColor" toRows:effectRows settingsVC:settingsViewController];
                    [effectRows addObject:[self themeGlowNumberItemWithTitle:@"Glow Opacity" titleDescription:@"Maximum shadow opacity as a percentage." key:@"theme_glowOpacity" min:0 max:100 fallback:100 suffix:@"%" settingsVC:settingsViewController]];
                    [effectRows addObject:[self themeGlowNumberItemWithTitle:@"Glow Radius" titleDescription:@"Radius multiplier where 50 is normal and 100 is double." key:@"theme_glowRadius" min:0 max:100 fallback:50 suffix:@"/100" settingsVC:settingsViewController]];
                    [effectRows addObject:[self themeGlowNumberItemWithTitle:@"Glow Layers" titleDescription:@"Number of stacked glow passes. Higher values are louder and heavier." key:@"theme_glowLayers" min:1 max:12 fallback:1 suffix:@"" settingsVC:settingsViewController]];
                    [effectRows addObject:space];
                    [effectRows addObject:[self themeSectionHeaderWithTitle:@"Surfaces" description:@"Choose where glow is allowed to render."]];
                    [effectRows addObject:[self switchWithTitle:@"GlowPivot" key:@"theme_glowPivot"]];
                    [effectRows addObject:[self switchWithTitle:@"GlowOverlay" key:@"theme_glowOverlay"]];
                    [effectRows addObject:[self switchWithTitle:@"GlowScrubber" key:@"theme_glowScrubber"]];
                    [effectRows addObject:[self switchWithTitle:@"GlowSeekBar" key:@"theme_glowSeekBar"]];
	                    [effectRows addObject:[self switchWithTitle:@"AnimateSeek" key:@"seekBarAnimated"]];
	                    [effectRows addObject:[self switchWithTitle:@"DisableAmbientMode" key:@"disableAmbientMode"]];
	                    [effectRows addObject:[self switchWithTitle:@"SeekBarGradient" key:@"seekBarGradient"]];
	                    [self addResetDefaultsItemForKeys:themeEffectKeys toRows:effectRows settingsVC:settingsViewController];

	                    YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:@"Effects" pickerSectionTitle:nil rows:effectRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                    [settingsViewController pushViewController:picker];
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
	                    [self addResetDefaultsItemForKeys:themeGradientKeys toRows:gradientRows settingsVC:settingsViewController];

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
                        NSArray *keys = @[@"theme_overlayButtons", @"theme_tabBarIcons", @"theme_seekBar", @"theme_seekBarLive", @"theme_seekBarScrubber", @"theme_seekBarScrubberLive", @"theme_background", @"theme_textPrimary", @"theme_textSecondary", @"theme_navBar", @"theme_accent", @"theme_gradientStart", @"theme_gradientEnd", @"theme_glowEnabled"];
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
                        [%c(YTSettingsSectionItem) itemWithTitle:LOC(@"Autoplay")
                        accessibilityIdentifier:@"YTAfterglowSectionItem"
                        detailTextBlock:^NSString *() {
                            NSArray *labels = @[LOC(@"Default"), @"Off", @"Off + hidden"];
                            NSInteger idx = MIN(MAX(ytagInt(@"autoplayMode"), 0), 2);
                            return labels[idx];
                        }
                        selectBlock:^BOOL (YTSettingsCell *autoCell, NSUInteger autoArg1) {
                            NSArray *labels = @[LOC(@"Default"), @"Off", @"Off + hidden"];
                            NSMutableArray <YTSettingsSectionItem *> *rows = [NSMutableArray array];
                            for (NSUInteger i = 0; i < labels.count; i++) {
                                [rows addObject:[%c(YTSettingsSectionItem) checkmarkItemWithTitle:labels[i] titleDescription:nil selectBlock:^BOOL (YTSettingsCell *innerCell, NSUInteger innerArg1) {
                                    ytagSetInt((int)innerArg1, @"autoplayMode");
                                    ytag_refreshSettingsHierarchy(settingsViewController);
                                    return YES;
                                }]];
                            }
                            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Autoplay") pickerSectionTitle:nil rows:rows selectedItemIndex:MIN(MAX(ytagInt(@"autoplayMode"), 0), 2) parentResponder:[self parentResponder]];
                            [settingsViewController pushViewController:picker];
                            return YES;
                        }],
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
                            [self switchWithTitle:@"NoEndScreenCards" key:@"hideEndScreenCards"],
                            [self switchWithTitle:@"NoRelatedVids" key:@"noRelatedVids"],
                            [self switchWithTitle:@"NoContinueWatchingPrompt" key:@"noContinueWatchingPrompt"]
                        ]];
                    }

                    [defaultRows addObject:space];
                    [defaultRows addObject:[self switchWithTitle:@"Miniplayer" key:@"miniplayer"]];
	                    if (isAdvanced) {
	                        [defaultRows addObject:[self switchWithTitle:@"PlaylistOldMinibar" key:@"playlistOldMinibar"]];
	                    }
	                    [self addResetDefaultsItemForKeys:playerPlaybackKeys toRows:defaultRows settingsVC:settingsViewController];

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
	                    NSMutableArray <YTSettingsSectionItem *> *controlRows = [@[
	                        [self switchWithTitle:@"PortraitFullscreen" key:@"portraitFullscreen"],
	                        [self switchWithTitle:@"AutoFullscreen" key:@"autoFullscreen"],
	                        [self switchWithTitle:@"ExitFullscreen" key:@"exitFullscreen"],
                        space,
                        [self switchWithTitle:@"TapToSeek" key:@"tapToSeek"],
                        [self switchWithTitle:@"NoDoubleTap2Seek" key:@"noDoubleTapToSeek"],
                        [self switchWithTitle:@"NoTwoFingerSnapToChapter" key:@"noTwoFingerSnapToChapter"],
	                        space,
	                        [self switchWithTitle:@"DontSnap2Chapter" key:@"dontSnapToChapter"],
	                        [self switchWithTitle:@"NoFreeZoom" key:@"noFreeZoom"]
	                    ] mutableCopy];
	                    [self addResetDefaultsItemForKeys:playerControlKeys toRows:controlRows settingsVC:settingsViewController];

	                    YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Controls") pickerSectionTitle:nil rows:controlRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                    [settingsViewController pushViewController:picker];
                    return YES;
                }]];

            [rows addObject:[self pageItemWithTitle:@"Buttons & Menus"
                titleDescription:@"Buttons shown directly under the player and overflow menu actions."
                summary:^NSString *() {
	                    return [self enabledSummaryForKeys:[playerActionBarKeys arrayByAddingObjectsFromArray:playerMenuKeys]];
	                }
	                selectBlock:^BOOL (YTSettingsCell *barCell, NSUInteger barArg1) {
	                    NSMutableArray <YTSettingsSectionItem *> *barRows = [@[
	                        [self switchWithTitle:@"NoPlayerDownloadButton" key:@"noPlayerDownloadButton"],
	                        [self switchWithTitle:@"PlayerNoShare" key:@"noPlayerShareButton"],
	                        [self switchWithTitle:@"PlayerNoSave" key:@"noPlayerSaveButton"],
	                        [self switchWithTitle:@"NoPlayerRemixButton" key:@"noPlayerRemixButton"],
	                        [self switchWithTitle:@"NoPlayerClipButton" key:@"noPlayerClipButton"],
	                        space,
	                        [self themeSectionHeaderWithTitle:@"Menus" description:@"Hide player menu actions you never use."],
	                        [self switchWithTitle:@"RemoveDownloadMenu" key:@"removeDownloadMenu"],
	                        [self switchWithTitle:@"RemoveShareMenu" key:@"removeShareMenu"]
	                    ] mutableCopy];
	                    NSArray *buttonMenuKeys = [playerActionBarKeys arrayByAddingObjectsFromArray:playerMenuKeys];
	                    [self addResetDefaultsItemForKeys:buttonMenuKeys toRows:barRows settingsVC:settingsViewController];

	                    YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:@"Buttons & Menus" pickerSectionTitle:nil rows:barRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
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
	                        NSMutableArray <YTSettingsSectionItem *> *overlayRows = [@[
	                            [self switchWithTitle:@"MuteButton" key:@"muteButton"],
	                            [self switchWithTitle:@"LockButton" key:@"lockButton"],
	                            [self switchWithTitle:@"DownloadButton" key:@"downloadButton"],
                            [self switchWithTitle:@"ControlsSheetButton" key:@"controlsSheetButton"],
                            [self switchWithTitle:@"OverlayDeclutterButton" key:@"overlayDeclutterButton"],
                            [self switchWithTitle:@"HideSubs" key:@"hideSubs"],
                            [self switchWithTitle:@"NoHUDMsgs" key:@"noHUDMsgs"],
                            [self switchWithTitle:@"HidePrevNext" key:@"hidePrevNext"],
                            [self switchWithTitle:@"ReplacePrevNext" key:@"replacePrevNext"],
                            [self switchWithTitle:@"NoDarkBg" key:@"noDarkBg"],
                            [self switchWithTitle:@"NoFullscreenActions" key:@"noFullscreenActions"],
                            [self switchWithTitle:@"StockVolumeHUD" key:@"stockVolumeHUD"],
                            [self switchWithTitle:@"NoWatermarks" key:@"noWatermarks"],
	                            [self switchWithTitle:@"VideoEndTime" key:@"videoEndTime"],
	                            [self switchWithTitle:@"24hrFormat" key:@"24hrFormat"],
	                            [self switchWithTitle:@"PauseOnOverlay" key:@"pauseOnOverlay"]
	                        ] mutableCopy];
	                        [self addResetDefaultsItemForKeys:playerOverlayKeys toRows:overlayRows settingsVC:settingsViewController];

	                        YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Overlay") pickerSectionTitle:nil rows:overlayRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                        [settingsViewController pushViewController:picker];
                        return YES;
	                    }]];
	            }
	            [self addResetDefaultsItemForKeys:playerKeys toRows:rows settingsVC:settingsViewController];

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
	                        NSMutableArray <YTSettingsSectionItem *> *uiRows = [@[
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
	                        ] mutableCopy];
	                        [self addResetDefaultsItemForKeys:shortsUIKeys toRows:uiRows settingsVC:settingsViewController];

	                        YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:@"Shorts Layout" pickerSectionTitle:nil rows:uiRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
                        [settingsViewController pushViewController:picker];
                        return YES;
	                    }]];
	            }
	            [self addResetDefaultsItemForKeys:shortsBehaviorKeys toRows:rows settingsVC:settingsViewController];

	            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Shorts") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:shorts];

    YTSettingsSectionItem *downloads = [self pageItemWithTitle:LOC(@"Downloads")
        titleDescription:@"Download behavior, audio tracks, captions, and save handling."
        summary:^NSString *() {
            return [self enabledSummaryForKeys:downloadKeys];
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray <YTSettingsSectionItem *> *rows = [NSMutableArray array];
            [rows addObject:[self themeSectionHeaderWithTitle:@"Behavior" description:@"Choose what happens after a download and whether Afterglow should refresh missing metadata before showing actions."]];
            [rows addObject:[self ytagPickerItemWithTitle:LOC(@"DownloadPostAction")
                                               description:LOC(@"DownloadPostActionDesc")
                                                       key:@"downloadPostActionMode"
                                                    labels:@[LOC(@"AskEveryTime"), LOC(@"SaveToPhotos"), LOC(@"ShareSheet")]
                                                settingsVC:settingsViewController]];
            [rows addObject:[self switchWithTitle:@"DownloadRefreshMetadata" key:@"downloadRefreshMetadata"]];
            [rows addObject:space];
            [rows addObject:[self themeSectionHeaderWithTitle:@"Audio" description:@"Control audio quality and whether multilingual or dubbed tracks are offered before downloading."]];
            [rows addObject:[self ytagPickerItemWithTitle:LOC(@"DownloadAudioTrack")
                                               description:LOC(@"DownloadAudioTrackDesc")
                                                       key:@"downloadAudioTrackMode"
                                                    labels:@[LOC(@"DefaultAudioTrack"), LOC(@"AskForAudioTrack")]
                                                settingsVC:settingsViewController]];
            [rows addObject:[self ytagPickerItemWithTitle:LOC(@"DownloadAudioQuality")
                                               description:LOC(@"DownloadAudioQualityDesc")
                                                       key:@"downloadAudioQualityMode"
                                                    labels:@[LOC(@"StandardAudioQuality"), LOC(@"HighAudioQuality")]
                                                settingsVC:settingsViewController]];
            [rows addObject:[self switchWithTitle:@"DownloadPreferStableAudio" key:@"downloadPreferStableAudio"]];
            [rows addObject:space];
            [rows addObject:[self themeSectionHeaderWithTitle:@"Captions" description:@"Control which caption tracks are shown in the download sheet."]];
            [rows addObject:[self switchWithTitle:@"DownloadIncludeAutoCaptions" key:@"downloadIncludeAutoCaptions"]];
            [rows addObject:[self switchWithTitle:@"DownloadOfferTranslatedCaptions" key:@"downloadOfferTranslatedCaptions"]];
            [rows addObject:space];
            [rows addObject:[self themeSectionHeaderWithTitle:@"Picker" description:@"Tune the compact quality/audio list shown before downloads start."]];
            [rows addObject:[self ytagPickerItemWithTitle:LOC(@"DownloadPickerTextSize")
                                               description:LOC(@"DownloadPickerTextSizeDesc")
                                                       key:@"downloadPickerFontScaleMode"
                                                    labels:@[LOC(@"Compact"), LOC(@"Standard"), LOC(@"Large")]
                                                settingsVC:settingsViewController]];
	            [rows addObject:[self ytagPickerItemWithTitle:LOC(@"DownloadPickerFont")
	                                               description:LOC(@"DownloadPickerFontDesc")
	                                                       key:@"downloadPickerFontFaceMode"
	                                                    labels:@[LOC(@"SystemFont"), LOC(@"RoundedFont"), LOC(@"SerifFont"), LOC(@"MonoFont")]
	                                                settingsVC:settingsViewController]];
	            [self addResetDefaultsItemForKeys:downloadKeys toRows:rows settingsVC:settingsViewController];

	            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"Downloads") pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:downloads];

    YTSettingsSectionItem *feed = [self pageItemWithTitle:@"Feed"
        titleDescription:@"Clean up the home feed and menu items."
        summary:^NSString *() {
            return [self enabledSummaryForKeys:feedToggleKeys];
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
	            NSMutableArray <YTSettingsSectionItem *> *feedRows = [@[
	                [self switchWithTitle:@"RemovePlayNext" key:@"removePlayNext"],
	                [self switchWithTitle:@"RemoveWatchLaterMenu" key:@"removeWatchLaterMenu"],
	                [self switchWithTitle:@"RemoveSaveToPlaylistMenu" key:@"removeSaveToPlaylistMenu"],
	                [self switchWithTitle:@"RemoveNotInterestedMenu" key:@"removeNotInterestedMenu"],
	                [self switchWithTitle:@"RemoveDontRecommendMenu" key:@"removeDontRecommendMenu"],
	                [self switchWithTitle:@"RemoveReportMenu" key:@"removeReportMenu"]
	            ] mutableCopy];
	            [self addResetDefaultsItemForKeys:feedKeys toRows:feedRows settingsVC:settingsViewController];

	            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:@"Feed" pickerSectionTitle:nil rows:feedRows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:feed];

    YTSettingsSectionItem *tools = [self pageItemWithTitle:@"Tools"
        titleDescription:@"Extra utility actions that do not belong to one primary surface."
        summary:^NSString *() {
            return [self enabledSummaryForKeys:toolKeys];
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
	            NSMutableArray <YTSettingsSectionItem *> *rows = [@[
	                [self switchWithTitle:@"CopyVideoInfo" key:@"copyVideoInfo"],
	                [self switchWithTitle:@"SaveProfilePhoto" key:@"saveProfilePhoto"],
	                [self switchWithTitle:@"PostManager" key:@"postManager"],
	                [self switchWithTitle:@"CommentManager" key:@"commentManager"],
	                [self switchWithTitle:@"NativeShare" key:@"nativeShare"],
	                [self switchWithTitle:@"FixAlbums" key:@"fixAlbums"],
	                [self switchWithTitle:@"CopyWithTimestamp" key:@"copyWithTimestamp"]
	            ] mutableCopy];
	            [self addResetDefaultsItemForKeys:toolKeys toRows:rows settingsVC:settingsViewController];

	            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:@"Tools" pickerSectionTitle:nil rows:rows selectedItemIndex:NSNotFound parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:tools];

    YTSettingsSectionItem *comments = [self pageItemWithTitle:@"Comments"
        titleDescription:@"Comment header mode in one picker."
        summary:^NSString *() {
            NSArray *labels = @[LOC(@"Default"), LOC(@"Pinned"), LOC(@"Hidden")];
            return labels[MIN(MAX(ytagInt(@"commentsHeaderMode"), 0), 2)];
        }
        selectBlock:^BOOL (YTSettingsCell *commentCell, NSUInteger commentArg1) {
            NSArray *labels = @[LOC(@"Default"), LOC(@"Pinned"), LOC(@"Hidden")];
            NSMutableArray <YTSettingsSectionItem *> *rows = [NSMutableArray array];
            for (NSUInteger i = 0; i < labels.count; i++) {
                [rows addObject:[%c(YTSettingsSectionItem) checkmarkItemWithTitle:labels[i] titleDescription:nil selectBlock:^BOOL (YTSettingsCell *innerCell, NSUInteger innerArg1) {
                    ytagSetInt((int)innerArg1, @"commentsHeaderMode");
                    ytag_refreshSettingsHierarchy(settingsViewController);
                    return YES;
	                }]];
	            }
	            [self addResetDefaultsItemForKeys:@[@"commentsHeaderMode"] toRows:rows settingsVC:settingsViewController];

	            YTSettingsPickerViewController *picker = [[%c(YTSettingsPickerViewController) alloc] initWithNavTitle:LOC(@"CommentsHeader") pickerSectionTitle:nil rows:rows selectedItemIndex:MIN(MAX(ytagInt(@"commentsHeaderMode"), 0), 2) parentResponder:[self parentResponder]];
            [settingsViewController pushViewController:picker];
            return YES;
        }];
    [sectionItems addObject:comments];

    YTSettingsSectionItem *credits = [self pageItemWithTitle:LOC(@"Credits")
        titleDescription:@"Project stewardship, AI co-development, open-source base, and bundled acknowledgements."
        summary:^NSString *() {
            return @"Team, AI & Open Source";
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSArray <YTSettingsSectionItem *> *rows = @[
                [self themeSectionHeaderWithTitle:@"Project Stewardship" description:@"Current maintainership and senior development for YouTube Afterglow."],
                [self linkWithTitle:@"Corey Hamilton" description:@"Maintainer / Senior Developer" link:@"https://github.com/xuninc"],
                space,
                [self themeSectionHeaderWithTitle:@"AI Co-Development Team" description:@"AI collaborators supporting implementation, review, and release polish."],
                [self linkWithTitle:@"Claude Opus 4.6 / 4.7" description:@"Architecture, implementation, and product polish" link:@"https://claude.com/claude"],
                [self linkWithTitle:@"OpenAI Codex" description:@"Code implementation, cleanup, and review support" link:@"https://openai.com/codex"],
                space,
                [self themeSectionHeaderWithTitle:@"Acknowledgements" description:@"Open-source base note."],
                [self linkWithTitle:@"YTLite" description:@"Open-source base, pre-4.0" link:@"https://github.com/dayanch96/YTLite"],
                space,
                [self themeSectionHeaderWithTitle:@"Open-Source Maintainers" description:@"Thanks to maintainers who keep useful YouTube tweak repositories open for everyone."],
                [self linkWithTitle:@"PoomSmart" description:@"Keeps YouPiP, YouQuality, Return-YouTube-Dislikes, YTABConfig, YTVideoOverlay, YouGroupSettings, YTIcons, and YouTubeHeader open and maintained for the community" link:@"https://github.com/PoomSmart"],
                [self themeSectionHeaderWithTitle:@"Bundled Tweaks" description:@"Additional community-built tweaks packaged inside Afterglow."],
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
        titleDescription:@"Maintenance tools, advanced mode, and project credits."
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

                [%c(YTSettingsSectionItem) itemWithTitle:nil accessibilityIdentifier:@"YTAfterglowSectionItem" detailTextBlock:nil selectBlock:nil],
                [self themeSectionHeaderWithTitle:LOC(@"ManagePreferences") description:LOC(@"ManagePreferencesDesc")],
                [%c(YTSettingsSectionItem) itemWithTitle:LOC(@"ExportPreferences") titleDescription:LOC(@"ExportPreferencesDesc") accessibilityIdentifier:@"YTAfterglowSectionItem" detailTextBlock:nil selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
                    [self presentPreferencesExportFromCell:cell settingsVC:settingsViewController];
                    return YES;
                }],
                [%c(YTSettingsSectionItem) itemWithTitle:LOC(@"ImportPreferences") titleDescription:LOC(@"ImportPreferencesDesc") accessibilityIdentifier:@"YTAfterglowSectionItem" detailTextBlock:nil selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
                    [self presentPreferencesImportFromCell:cell settingsVC:settingsViewController];
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
            [rows addObject:[self themeSectionHeaderWithTitle:LOC(@"DebugLogging") description:LOC(@"DebugLoggingDesc")]];
            [rows addObject:[self switchWithTitle:@"DebugLogging" key:@"debugLogEnabled"]];
            [rows addObject:[self switchWithTitle:@"DebugLogFirehose" key:@"debugLogFirehose"]];
            [rows addObject:[self themeSectionHeaderWithTitle:LOC(@"DebugLogCategories") description:LOC(@"DebugLogCategoriesDesc")]];
            [rows addObject:[self switchWithTitle:@"DebugLogDownloads" key:@"debugLogDownloads"]];
            [rows addObject:[self switchWithTitle:@"DebugLogPlayerUI" key:@"debugLogPlayerUI"]];
            [rows addObject:[self switchWithTitle:@"DebugLogPremiumControls" key:@"debugLogPremiumControls"]];
            [rows addObject:[self switchWithTitle:@"DebugLogPiP" key:@"debugLogPiP"]];
            [rows addObject:[self switchWithTitle:@"DebugLogProbes" key:@"debugLogProbes"]];
            [rows addObject:[%c(YTSettingsSectionItem) switchItemWithTitle:LOC(@"ShowDebugHUD") titleDescription:LOC(@"ShowDebugHUDDesc") accessibilityIdentifier:@"YTAfterglowSectionItem" switchOn:ytagBool(@"debugHUDEnabled") switchBlock:^BOOL (YTSettingsCell *cell, BOOL enabled) {
                ytagSetBool(enabled, @"debugHUDEnabled");
                if (enabled) {
                    ytagSetBool(YES, @"debugLogEnabled");
                    [[YTAGDebugHUD sharedHUD] show];
                } else {
                    [[YTAGDebugHUD sharedHUD] hide];
                }
                ytag_refreshSettingsFromCell(cell);
                return YES;
            } settingItemId:0]];
            [rows addObject:[%c(YTSettingsSectionItem) itemWithTitle:LOC(@"ShareDebugLog") titleDescription:nil accessibilityIdentifier:@"YTAfterglowSectionItem" detailTextBlock:nil selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
                NSString *logPath = YTAGLogFilePath();
                NSString *body = nil;
                @try {
                    if ([[NSFileManager defaultManager] fileExistsAtPath:logPath]) {
                        body = [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:nil];
                    }
                    if (!body || body.length == 0) {
                        NSArray *entries = YTAGLogRecentEntries();
                        body = entries.count ? [entries componentsJoinedByString:@"\n"] : @"";
                    }
                } @catch (id ex) {
                    body = [NSString stringWithFormat:@"(read failed: %@)", ex];
                }
                if (!body || body.length == 0) {
                    [[%c(YTToastResponderEvent) eventWithMessage:LOC(@"NoDebugLog") firstResponder:[self parentResponder]] send];
                    return YES;
                }
                [self presentDebugLogShareFromCell:cell body:body settingsVC:settingsViewController];
                return YES;
            }]];
	            [rows addObject:[%c(YTSettingsSectionItem) itemWithTitle:LOC(@"ClearDebugLog") titleDescription:nil accessibilityIdentifier:@"YTAfterglowSectionItem" detailTextBlock:nil selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
	                YTAGLogClear();
	                [[%c(YTToastResponderEvent) eventWithMessage:LOC(@"Done") firstResponder:[self parentResponder]] send];
	                return YES;
	            }]];
	            [self addResetDefaultsItemForKeys:@[@"advancedMode", @"debugLogEnabled", @"debugLogFirehose", @"debugLogDownloads", @"debugLogPlayerUI", @"debugLogPremiumControls", @"debugLogPiP", @"debugLogProbes", @"debugHUDEnabled"] toRows:rows settingsVC:settingsViewController];

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
