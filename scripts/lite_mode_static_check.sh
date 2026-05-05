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

require 'YTAGEffectiveBool' 'Utils/YTAGLiteMode.h' 'effective bool helper must be declared'
require 'liteModeEnabled' 'Utils/YTAGLiteMode.m' 'liteModeEnabled preference must exist in helper'
require 'liteModeDefaultThemeVersion' 'Utils/YTAGLiteMode.m' 'Lite theme defaults must use a versioned migration'
require 'YTAGSetLiteModeEnabled' 'Settings.x' 'settings toggle must use shared setter'
require 'YTAGSetLiteModeEnabled' 'UI/YTAGPremiumControls.m' 'premium controls toggle must use shared setter'
require 'YTAGLiteModeShouldCleanCollectionView' 'Utils/YTAGLiteMode.h' 'Lite cleanup must be scoped away from Settings collections'
require 'settings' 'Utils/YTAGLiteMode.m' 'Lite collection scope must explicitly exclude Settings surfaces'
require 'YTAGLiteModeShouldCleanCollectionView\(self\)' 'YTAfterglow.x' 'collection cleanup must use scoped Lite guard'
require 'YTAGLiteModeApplyViewCleanup' 'YTAfterglow.x' 'main tweak must apply Lite view cleanup'
require 'YTAGLiteModeApplyCommentChrome' 'YTAfterglow.x' 'main tweak must apply Lite comment cleanup'
require 'LiteMode' 'layout/Library/Application Support/YTAfterglow.bundle/en.lproj/Localizable.strings' 'Lite Mode strings must be localized'
require '#define ytagBool\(key\) YTAGEffectiveBool\(key\)' 'YTAfterglow.h' 'ytagBool must route through effective helper'

if rg -q '@"metadata"|@"viewcount"' "$ROOT/Utils/YTAGLiteMode.m"; then
  echo "FAIL: Lite cleanup must not hide video metadata containers or view-count text under videos" >&2
  exit 1
fi

if rg -q 'UIColor \*background = \[UIColor colorWithWhite:0\.015|UIColor \*surface = \[UIColor colorWithWhite:0\.055' "$ROOT/Utils/YTAGLiteMode.m"; then
  echo "FAIL: Lite monochrome theme must not use the old near-black preset" >&2
  exit 1
fi

echo "lite-mode static check passed"
