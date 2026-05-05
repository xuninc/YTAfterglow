#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(pwd)}"

require_pattern() {
  local file="$1"
  local pattern="$2"
  local message="$3"

  if ! rg -q "$pattern" "$ROOT/$file"; then
    printf 'FAIL: %s\n' "$message" >&2
    printf '  expected %s in %s\n' "$pattern" "$file" >&2
    exit 1
  fi
}

require_pattern "Settings.x" "void YTAGOpenAfterglowSettingsFromView\\(UIView \\*sourceView\\)" \
  "Settings.x must export a direct Afterglow settings opener."
require_pattern "YTAGDownload.x" "extern void YTAGOpenAfterglowSettingsFromView\\(UIView \\*sourceView\\)" \
  "Overlay code must link to the direct settings opener."
require_pattern "YTAGDownload.x" "handleSettingsTap:" \
  "Overlay trigger must expose a settings tap handler."
require_pattern "YTAGDownload.x" "YTAGOpenAfterglowSettingsFromView\\(sender\\)" \
  "Settings tap handler must route through the direct settings opener."
require_pattern "YTAGDownload.x" "kYTAGOverlaySettingsButtonTag" \
  "Settings button must have its own tag."
require_pattern "YTAGDownload.x" "view.tag == kYTAGOverlaySettingsButtonTag" \
  "Declutter must not hide the failsafe settings button."
require_pattern "YTAGDownload.x" "Afterglow Settings" \
  "Overlay gear must be identifiable to accessibility and diagnostics."
require_pattern "YTAGDownload.x" "gearshape.fill" \
  "Overlay gear should use the settings symbol."

printf 'PASS: failsafe settings static check\n'
