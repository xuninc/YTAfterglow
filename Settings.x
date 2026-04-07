#import "YTLite.h"
#import <objc/runtime.h>

@interface YTSettingsSectionItemManager (YTLite)
- (void)updateYTLiteSectionWithEntry:(id)entry;
@end

static const NSInteger YTLiteSection = 789;

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
        }

        else {
            ytlSetBool(enabled, key);

            NSArray *keys = @[@"removeLabels", @"removeIndicators", @"frostedPivot",
                @"theme_overlayButtons", @"theme_tabBarIcons", @"theme_seekBar",
                @"theme_background", @"theme_textPrimary", @"theme_textSecondary",
                @"theme_navBar", @"theme_accent"];
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

%new(v@:@)
- (void)updateYTLiteSectionWithEntry:(id)entry {
    NSMutableArray *sectionItems = [NSMutableArray array];
    Class YTSettingsSectionItemClass = %c(YTSettingsSectionItem);
    YTSettingsViewController *settingsViewController = [self valueForKey:@"_settingsViewControllerDelegate"];

    YTSettingsSectionItem *space = [%c(YTSettingsSectionItem) itemWithTitle:nil accessibilityIdentifier:@"YTLiteSectionItem" detailTextBlock:nil selectBlock:nil];

    YTSettingsSectionItem *general = [YTSettingsSectionItemClass itemWithTitle:LOC(@"General")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() {
            return @"‣";
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
        return @"‣";
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

    // Appearance section — per-element color customization
    YTSettingsSectionItem *appearance = [YTSettingsSectionItemClass itemWithTitle:LOC(@"Appearance")
        accessibilityIdentifier:@"YTLiteSectionItem"
        detailTextBlock:^NSString *() {
            return @"‣";
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSMutableArray <YTSettingsSectionItem *> *rows = [NSMutableArray array];

            extern void ytl_clearThemeCache(void);

            // Helper: hex string from UIColor
            NSString *(^hexFromColor)(UIColor *) = ^NSString *(UIColor *color) {
                CGFloat r, g, b, a;
                [color getRed:&r green:&g blue:&b alpha:&a];
                return [NSString stringWithFormat:@"#%02X%02X%02X", (int)(r*255), (int)(g*255), (int)(b*255)];
            };

            // Helper: load saved color for a key
            UIColor *(^loadColor)(NSString *) = ^UIColor *(NSString *key) {
                NSData *data = [[YTLUserDefaults standardUserDefaults] objectForKey:key];
                if (!data) return nil;
                NSKeyedUnarchiver *u = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:nil];
                [u setRequiresSecureCoding:NO];
                return [u decodeObjectForKey:NSKeyedArchiveRootObjectKey];
            };

            // Helper: create a color picker row for a theme element
            void (^addColorRow)(NSString *, NSString *) = ^(NSString *title, NSString *themeKey) {
                YTSettingsSectionItem *item = [YTSettingsSectionItemClass itemWithTitle:LOC(title)
                    accessibilityIdentifier:nil
                    detailTextBlock:^NSString *() {
                        UIColor *c = loadColor(themeKey);
                        return c ? hexFromColor(c) : LOC(@"Default");
                    }
                    selectBlock:^BOOL(YTSettingsCell *c, NSUInteger a) {
                        UIColor *existing = loadColor(themeKey);

                        if (existing) {
                            // Color already set — show options
                            UIAlertController *alert = [UIAlertController alertControllerWithTitle:LOC(title)
                                message:nil preferredStyle:UIAlertControllerStyleActionSheet];
                            [alert addAction:[UIAlertAction actionWithTitle:LOC(@"ChangeColor") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                                if (@available(iOS 14.0, *)) {
                                    UIColorPickerViewController *picker = [[UIColorPickerViewController alloc] init];
                                    picker.supportsAlpha = NO;
                                    picker.selectedColor = existing;
                                    id delegate = [[NSObject alloc] init];
                                    static id _held = nil;
                                    class_addMethod([NSObject class], @selector(colorPickerViewControllerDidFinish:),
                                        imp_implementationWithBlock(^(id self, UIColorPickerViewController *vc) {
                                            NSData *data = [NSKeyedArchiver archivedDataWithRootObject:vc.selectedColor requiringSecureCoding:NO error:nil];
                                            [[YTLUserDefaults standardUserDefaults] setObject:data forKey:themeKey];
                                            ytl_clearThemeCache();
                                            [settingsViewController reloadData];
                                            _held = nil;
                                        }), "v@:@");
                                    picker.delegate = (id)delegate;
                                    _held = delegate;
                                    [settingsViewController presentViewController:picker animated:YES completion:nil];
                                }
                            }]];
                            [alert addAction:[UIAlertAction actionWithTitle:LOC(@"ResetDefault") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
                                [[YTLUserDefaults standardUserDefaults] removeObjectForKey:themeKey];
                                ytl_clearThemeCache();
                                [settingsViewController reloadData];
                            }]];
                            [alert addAction:[UIAlertAction actionWithTitle:LOC(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
                            [settingsViewController presentViewController:alert animated:YES completion:nil];
                        } else {
                            // No color set — go straight to picker
                            if (@available(iOS 14.0, *)) {
                                UIColorPickerViewController *picker = [[UIColorPickerViewController alloc] init];
                                picker.supportsAlpha = NO;
                                id delegate = [[NSObject alloc] init];
                                static id _held2 = nil;
                                class_addMethod([NSObject class], @selector(colorPickerViewControllerDidFinish:),
                                    imp_implementationWithBlock(^(id self, UIColorPickerViewController *vc) {
                                        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:vc.selectedColor requiringSecureCoding:NO error:nil];
                                        [[YTLUserDefaults standardUserDefaults] setObject:data forKey:themeKey];
                                        ytl_clearThemeCache();
                                        [settingsViewController reloadData];
                                        _held2 = nil;
                                    }), "v@:@");
                                picker.delegate = (id)delegate;
                                _held2 = delegate;
                                [settingsViewController presentViewController:picker animated:YES completion:nil];
                            }
                        }
                        return YES;
                    }];
                [rows addObject:item];
            };

            addColorRow(@"OverlayButtons", @"theme_overlayButtons");
            addColorRow(@"TabBarIcons", @"theme_tabBarIcons");
            addColorRow(@"SeekBar", @"theme_seekBar");
            addColorRow(@"Background", @"theme_background");
            addColorRow(@"PrimaryText", @"theme_textPrimary");
            addColorRow(@"SecondaryText", @"theme_textSecondary");
            addColorRow(@"NavigationBar", @"theme_navBar");
            addColorRow(@"AccentColor", @"theme_accent");

            // Reset All button
            YTSettingsSectionItem *resetAll = [YTSettingsSectionItemClass itemWithTitle:LOC(@"ResetAllColors")
                accessibilityIdentifier:nil
                detailTextBlock:nil
                selectBlock:^BOOL(YTSettingsCell *c, NSUInteger a) {
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:LOC(@"ResetAllColors")
                        message:LOC(@"ResetAllColorsConfirm") preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:LOC(@"Reset") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
                        NSArray *keys = @[@"theme_overlayButtons", @"theme_tabBarIcons", @"theme_seekBar",
                                          @"theme_background", @"theme_textPrimary", @"theme_textSecondary",
                                          @"theme_navBar", @"theme_accent"];
                        for (NSString *key in keys) {
                            [[YTLUserDefaults standardUserDefaults] removeObjectForKey:key];
                        }
                        ytl_clearThemeCache();
                        [settingsViewController reloadData];
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
            return @"‣";
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
            return @"‣";
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
            return @"‣";
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
        return @"‣";
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
        NSMutableArray *activeTabs = [[[YTLUserDefaults standardUserDefaults] objectForKey:@"activeTabs"] mutableCopy];
        if (!activeTabs) activeTabs = [@[@"FEwhat_to_watch", @"FEshorts", @"FEsubscriptions", @"FElibrary"] mutableCopy];

        // Icon types for tabs
        // YouTube icon types for tabs (from YTIcons browser)
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
                NSMutableArray *current = [[[YTLUserDefaults standardUserDefaults] objectForKey:@"activeTabs"] mutableCopy];
                if (!current) current = [@[@"FEwhat_to_watch", @"FEshorts", @"FEsubscriptions", @"FElibrary"] mutableCopy];
                if (current.count <= 2) {
                    YTAlertView *alert = [%c(YTAlertView) infoDialog];
                    alert.title = LOC(@"Warning");
                    alert.subtitle = LOC(@"AtLeastOneTab");
                    [alert show];
                    return NO;
                }
                [current removeObject:tabId];
                [[YTLUserDefaults standardUserDefaults] setObject:current forKey:@"activeTabs"];
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
                NSMutableArray *current = [[[YTLUserDefaults standardUserDefaults] objectForKey:@"activeTabs"] mutableCopy];
                if (!current) current = [@[@"FEwhat_to_watch", @"FEshorts", @"FEsubscriptions", @"FElibrary"] mutableCopy];
                if ([current containsObject:tabId]) return NO;
                if (current.count >= 6) {
                    YTAlertView *alert = [%c(YTAlertView) infoDialog];
                    alert.title = LOC(@"Warning");
                    alert.subtitle = LOC(@"TabsCountRestricted");
                    [alert show];
                    return NO;
                }
                [current addObject:tabId];
                [[YTLUserDefaults standardUserDefaults] setObject:current forKey:@"activeTabs"];
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
            return @"‣";
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
            NSString *tab = [[YTLUserDefaults standardUserDefaults] objectForKey:@"startupTab"];
            if (!tab) tab = @"FEwhat_to_watch";
            NSDictionary *names = @{@"FEwhat_to_watch": LOC(@"FEwhat_to_watch"), @"FEshorts": LOC(@"FEshorts"), @"FEsubscriptions": LOC(@"FEsubscriptions"), @"FElibrary": LOC(@"FElibrary"), @"FEexplore": LOC(@"FEexplore"), @"FEhistory": LOC(@"FEhistory"), @"VLWL": LOC(@"VLWL")};
            return names[tab] ?: tab;
        }
        selectBlock:^BOOL (YTSettingsCell *cell, NSUInteger arg1) {
            NSArray *activeTabs = [[YTLUserDefaults standardUserDefaults] objectForKey:@"activeTabs"];
            if (!activeTabs) activeTabs = @[@"FEwhat_to_watch", @"FEshorts", @"FEsubscriptions", @"FElibrary"];
            NSDictionary *names = @{@"FEwhat_to_watch": LOC(@"FEwhat_to_watch"), @"FEshorts": LOC(@"FEshorts"), @"FEsubscriptions": LOC(@"FEsubscriptions"), @"FElibrary": LOC(@"FElibrary"), @"FEexplore": LOC(@"FEexplore"), @"FEhistory": LOC(@"FEhistory"), @"VLWL": LOC(@"VLWL")};
            NSString *currentTab = [[YTLUserDefaults standardUserDefaults] objectForKey:@"startupTab"];
            if (!currentTab) currentTab = @"FEwhat_to_watch";

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
        return @"‣";
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
        return @"‣";
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
