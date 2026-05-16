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

require 'YTAGResetBundledStandardUserDefaults' 'Utils/YTAGUserDefaults.m' 'global reset must clear bundled tweak keys outside the Afterglow suite'
require 'YTVideoOverlay-' 'Utils/YTAGUserDefaults.m' 'global reset must clear YTVideoOverlay button settings'
require 'YouPiPEnabled' 'Utils/YTAGUserDefaults.m' 'global reset must clear YouPiP settings'
require 'YouMuteKeepMuted' 'Utils/YTAGUserDefaults.m' 'global reset must clear YouMute state'
require 'resetUserDefaults' 'Settings.x' 'About reset must call the global reset entrypoint'
require 'ResetMessage' 'layout/Library/Application Support/YTAfterglow.bundle/en.lproj/Localizable.strings' 'global reset copy must identify YouTube Afterglow'

echo "settings reset static check passed"
