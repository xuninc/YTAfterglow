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

require 'YTAGThemeFontModeKey' 'Utils/YTAGLiteMode.h' 'theme font preference key must be public'
require 'YTAGThemeFontOverrideEnabled' 'Utils/YTAGLiteMode.h' 'theme font override helper must be public'
require 'YTAGThemeFontModeDisplayName' 'Utils/YTAGLiteMode.h' 'theme font display helper must be public'
require 'YTAGThemeFontModeKey: @0' 'Utils/YTAGUserDefaults.m' 'theme font must default to Auto'
require 'YTAGThemeFontModeKey' 'Settings.x' 'Themes settings must expose theme font mode'
require 'Typography' 'Settings.x' 'Themes must include a Typography page'
require 'AppFont' 'Settings.x' 'Typography page must include an app font picker'
require 'themeTypographyKeys' 'Settings.x' 'Typography settings must have page-specific reset keys'
require 'YTAGThemeFontModeDisplayName' 'Settings.x' 'Settings summary must display selected theme font'
require 'YTAGThemeFontOverrideEnabled' 'YTAfterglow.x' 'global text hooks must use theme font override helper'
require '%hook UILabel' 'YTAfterglow.x' 'UIKit labels must be hooked for theme typography'
require '%hook ASTextNode' 'YTAfterglow.x' 'Texture text nodes must be hooked for theme typography'
require 'YTAGLiteModeFontMatchingFont' 'YTAfterglow.x' 'global text hooks must apply theme font matching'
require 'YTAGLiteModeStyleAttributedString' 'YTAfterglow.x' 'global text hooks must rewrite attributed text'

for font in \
  'CourierNewPSMT' \
  'CourierNewPS-BoldMT' \
  'Menlo-Regular' \
  'AvenirNext-Regular' \
  'HelveticaNeue' \
  'ArialMT' \
  'Georgia' \
  'TimesNewRomanPSMT' \
  'Palatino-Roman' \
  'Didot' \
  'Baskerville' \
  'AmericanTypewriter' \
  'HoeflerText-Regular' \
  'GillSans' \
  'Futura-Medium' \
  'MarkerFelt-Thin' \
  'Noteworthy-Light'; do
  require "$font" 'Utils/YTAGLiteMode.m' "font option $font must be mapped"
done

for label in \
  'Auto' \
  'System / SF Pro' \
  'Rounded' \
  'New York' \
  'SF Mono' \
  'Courier New' \
  'Avenir Next' \
  'Times New Roman' \
  'American Typewriter' \
  'Marker Felt'; do
  require "$label" 'Utils/YTAGLiteMode.m' "font picker label $label must be available"
done

require '"Typography"' 'layout/Library/Application Support/YTAfterglow.bundle/en.lproj/Localizable.strings' 'Typography string must be localized'
require '"AppFont"' 'layout/Library/Application Support/YTAfterglow.bundle/en.lproj/Localizable.strings' 'App font string must be localized'
require '"AppFontDesc"' 'layout/Library/Application Support/YTAfterglow.bundle/en.lproj/Localizable.strings' 'App font description must be localized'

echo "theme typography static check passed"
