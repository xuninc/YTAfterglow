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
require 'ytagApplyTwoRowPivotLayout' 'YTAfterglow.x' 'pivot hooks must lay out a compact centered overflow row'
require 'ytagRaisedTwoRowPivotFrame' 'YTAfterglow.x' 'tab bar container frame must grow upward for two-row overflow'
require 'ytagRaisedTwoRowPivotFrame\(self, frame\)' 'YTAfterglow.x' 'YTPivotBarView setFrame must raise the existing frame upward'
require 'ytagPinNativePivotRowToTop' 'YTAfterglow.x' 'native six-button row must be pinned to the top of the taller tab bar'
require 'ytagConfigureTwoRowOverflowButton' 'YTAfterglow.x' 'overflow row must use compact custom controls'
require 'didTapItemWithRenderer:' 'YTAfterglow.x' 'overflow buttons must dispatch through the native pivot delegate'
require 'ytagSyncTwoRowOverflowSelection' 'YTAfterglow.x' 'overflow item selection must stay synced'
require 'ytagTwoRowNormalTintColor' 'YTAfterglow.x' 'overflow buttons must use their standalone bonus-button tint helper'
require 'ytagTwoRowSelectedTintColor' 'YTAfterglow.x' 'overflow buttons must use their standalone selected tint helper'
require 'theme_tabBarIcons' 'YTAfterglow.x' 'overflow button tint must come from the tab-bar theme color'
require 'colorWithAlphaComponent:0\.78' 'YTAfterglow.x' 'normal overflow button tint must use the older muted alpha treatment'
require 'YTAGTwoRowPivotExtraHeight' 'YTAfterglow.x' 'pivot height increase must be compact and explicit'
require 'selectItemWithPivotIdentifier:' 'YTAfterglow.x' 'overflow selection sync must hook native pivot selection'
require 'pivotBarHeight' 'YTAfterglow.x' 'pivot class height must account for overflow'
require 'intrinsicContentSize' 'YTAfterglow.x' 'pivot intrinsic height must account for overflow'
reject 'YTAGTwoRowNativeTabLimit = 5' 'YTAfterglow.x' 'native first row must not be capped below six slots'
reject 'ytagConfigureTwoRowOverflowItem' 'YTAfterglow.x' 'overflow row must not squeeze native tab item views into a compact row'
reject 'ytagNativePivotItemTintColor' 'YTAfterglow.x' 'overflow buttons must not sample native pivot tab colors'
reject 'ytagTwoRowTintColor' 'YTAfterglow.x' 'overflow buttons must not mirror native selected/normal pivot tint'
reject 'frame\.size\.height = topHeight' 'YTAfterglow.x' 'native first row height must not be compressed for overflow space'
reject 'MIN\(extraHeight' 'YTAfterglow.x' 'overflow row height must use the explicit two-row extra height helper'
reject 'ytagSetPivotItemCGFloat\(nativeItemView' 'YTAfterglow.x' 'native first row tab height must not be rewritten'

echo "two-row tabbar static check passed"
