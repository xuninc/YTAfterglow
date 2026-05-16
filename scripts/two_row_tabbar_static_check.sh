#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(pwd)}"

require() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  if ! rg -q "$pattern" "$ROOT/$file"; then
    echo "FAIL: $message" >&2
    exit 1
  fi
}

reject() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  if rg -q "$pattern" "$ROOT/$file"; then
    echo "FAIL: $message" >&2
    exit 1
  fi
}

require 'twoRowTabBar' 'Utils/YTAGUserDefaults.m' 'two-row tab bar preference must be registered'
require 'YTAGMaximumActiveTabsCount' 'Utils/YTAGUserDefaults.m' 'active tab sanitizer must use dynamic maximum'
require 'twoRowTabBar' 'Settings.x' 'Tabbar settings must expose the two-row toggle'
require 'ytag_maxActiveTabCount' 'Settings.x' 'Manage Tabs must enforce the dynamic active tab cap'
require 'TwoRowTabBar' 'layout/Library/Application Support/YTAfterglow.bundle/en.lproj/Localizable.strings' 'two-row tab bar strings must be localized'
require 'ytagTwoRowTabBarEnabled' 'YTAfterglow.x' 'pivot hooks must use a shared two-row helper'
require 'YTAGTwoRowNativeTabLimit = 6' 'YTAfterglow.x' 'native first row must keep YouTube'\''s six-slot capacity'
require 'ytagTwoRowOverflowTabIds' 'YTAfterglow.x' 'pivot hooks must compute overflow tab ids'
require 'ytagApplyTwoRowPivotLayout' 'YTAfterglow.x' 'pivot hooks must lay out a compact overflow row'
require 'ytagRaisedTwoRowPivotFrame' 'YTAfterglow.x' 'tab bar container frame must grow upward for two-row overflow'
require 'ytagRaisedTwoRowPivotFrame\(self, frame\)' 'YTAfterglow.x' 'YTPivotBarView setFrame must raise the existing frame upward'
require 'ytagPinNativePivotRowToTop' 'YTAfterglow.x' 'native six-button row must be pinned to the top of the taller tab bar'
require 'ytagConfigureTwoRowOverflowButton' 'YTAfterglow.x' 'overflow row must use compact custom controls'
require 'ytagTwoRowOverflowTitleLabel' 'YTAfterglow.x' 'overflow row must own labels so it can respect removeLabels'
require 'ytagConfigureTwoRowOverflowSelectionChrome' 'YTAfterglow.x' 'overflow row must show selected state/indicator consistently'
require 'ytagTwoRowTintColor' 'YTAfterglow.x' 'overflow row must classify normal and selected tab colors separately'
require 'theme_textPrimary' 'YTAfterglow.x' 'overflow normal tab tint must not force every button through the selected/accent color'
require 'ytagConfigureTwoRowOverflowSelectionChrome\(button, pivotBar, selected\)' 'YTAfterglow.x' 'overflow tint updates must receive pivot bar context'
require 'normalIconColor' 'ColorMode.x' 'native pivot tab theming must classify inactive tab color separately'
require 'setTitleColor:normalIconColor forState:UIControlStateNormal' 'ColorMode.x' 'native pivot normal state must not use the selected tab color'
require 'setTitleColor:selectedIconColor forState:UIControlStateSelected' 'ColorMode.x' 'native pivot selected state must keep the selected tab color'
require 'ytagBool\(@"removeLabels"\)' 'YTAfterglow.x' 'overflow row labels must respect Remove tab labels'
require 'ytagBool\(@"removeIndicators"\)' 'YTAfterglow.x' 'overflow row selection indicators must respect Remove tab indicators'
require 'label.textColor = selected \? selectedColor : normalColor' 'YTAfterglow.x' 'overflow labels must use the active theme color'
require 'indicator.backgroundColor = selectedColor' 'YTAfterglow.x' 'overflow selected indicator must use the active theme color'
require 'kYTAGTwoRowNativeRendererMapKey' 'YTAfterglow.x' 'overflow row must retain native tab renderers before filtering'
require 'didTapItemWithIconOnlyItemRenderer:' 'YTAfterglow.x' 'overflow row must dispatch native icon-only tabs such as Create'
require 'ytagCanSynthesizePivotTab' 'YTAfterglow.x' 'synthetic tab creation must be explicitly gated'
require '!\[tabId isEqualToString:@"FEuploads"\]' 'YTAfterglow.x' 'Create must be treated as native-only, not a browse tab'
require 'YTAGTwoRowSettingsTabId' 'YTAfterglow.x' 'overflow row must add a fourth settings button for symmetry'
require 'ytagTwoRowOverflowDisplayIds' 'YTAfterglow.x' 'overflow row must append non-tab display buttons separately from native overflow ids'
require 'YTAGOpenAfterglowSettingsFromView' 'YTAfterglow.x' 'settings overflow button must open Afterglow settings directly'
require 'YTAGTwoRowOverflowLeadingEmptySlots' 'YTAfterglow.x' 'overflow row must leave one empty leading slot before left-aligned buttons'
require 'ytagTwoRowOverflowButtonFrame' 'YTAfterglow.x' 'overflow buttons must use a left-aligned bottom-row frame helper'
require 'configurationWithPointSize:14\.0' 'YTAfterglow.x' 'overflow icons must be smaller than the native row icons'
require 'didTapItemWithRenderer:' 'YTAfterglow.x' 'overflow buttons must dispatch through the native pivot delegate'
require 'ytagSyncTwoRowOverflowSelection' 'YTAfterglow.x' 'overflow item selection must stay synced'
require 'YTAGTwoRowPivotExtraHeight' 'YTAfterglow.x' 'pivot height increase must be compact and explicit'
require 'return 32\.0' 'YTAfterglow.x' 'two-row tab bar must reserve a taller second-row band'
require 'YTAGTwoRowNativeRowLift' 'YTAfterglow.x' 'native first row must be lifted upward when overflow is present'
require 'YTAGTwoRowOverflowVisualButtonSize' 'YTAfterglow.x' 'overflow controls must use a larger explicit visual/touch size'
reject 'return 34\.0' 'YTAfterglow.x' 'overflow buttons must fit the 32pt reserved two-row band'
require 'YTAGTwoRowOverflowBottomInset' 'YTAfterglow.x' 'overflow row must be lifted above the home-indicator zone'
require 'nativeSlotWidth' 'YTAfterglow.x' 'overflow row leading gap must be based on native tab slot width'
require 'kYTAGTwoRowBottomFillViewKey' 'YTAfterglow.x' 'two-row mode must own the bottom safe-area fill view'
require 'ytagTwoRowEnsureBottomFill' 'YTAfterglow.x' 'two-row mode must paint the bottom safe-area gap'
require 'superview.backgroundColor = ytagTwoRowTabBarBackgroundColor' 'YTAfterglow.x' 'pivot parent must not expose themed page background below the tab bar'
require 'selectItemWithPivotIdentifier:' 'YTAfterglow.x' 'overflow selection sync must hook native pivot selection'
require 'pivotBarHeight' 'YTAfterglow.x' 'pivot class height must account for overflow'
require 'intrinsicContentSize' 'YTAfterglow.x' 'pivot intrinsic height must account for overflow'
reject 'YTAGTwoRowNativeTabLimit = 5' 'YTAfterglow.x' 'native first row must not be capped below six slots'
reject 'return 20\.0' 'YTAfterglow.x' 'two-row overflow height must not stay at the cramped original value'
reject 'ytagConfigureTwoRowOverflowItem' 'YTAfterglow.x' 'overflow row must not squeeze native tab item views into a compact row'
reject 'frame\.size\.height = topHeight' 'YTAfterglow.x' 'native first row height must not be compressed for overflow space'
reject 'MIN\(extraHeight' 'YTAfterglow.x' 'overflow row height must use the explicit two-row extra height helper'
reject 'ytagSetPivotItemCGFloat\(nativeItemView' 'YTAfterglow.x' 'native first row tab height must not be rewritten'
reject 'frame\.origin\.y -= delta' 'YTAfterglow.x' 'pivot frame must not be lifted away from the bottom edge'
reject 'YTAGTwoRowOverflowCenterGap' 'YTAfterglow.x' 'overflow buttons must no longer be split around the home indicator'
reject 'CGRectGetHeight\(bounds\) - rowHeight\);' 'YTAfterglow.x' 'overflow row must not sit on the absolute bottom edge'
reject 'startX = floor\(\(CGRectGetWidth\(bounds\) - totalWidth\) / 2\.0\)' 'YTAfterglow.x' 'overflow buttons must not be centered over the home indicator area'
reject '@\[@"FEhype_leaderboard", @"FEhistory", @"VLWL", @"FEpost_home", @"FEuploads"\]' 'YTAfterglow.x' 'Create must not be synthesized as a regular browse tab'

echo "two-row tabbar static check passed"
