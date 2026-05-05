#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(pwd)}"
SEEK="$ROOT/SeekBar.x"
SETTINGS="$ROOT/Settings.x"
COLOR="$ROOT/ColorMode.x"

require_pattern() {
  local file="${3:-$SEEK}"
  local pattern="$1"
  local message="$2"

  if ! rg -q "$pattern" "$file"; then
    printf 'FAIL: %s\n' "$message" >&2
    printf '  expected %s in %s\n' "$pattern" "$(basename "$file")" >&2
    exit 1
  fi
}

reject_pattern() {
  local pattern="$1"
  local message="$2"

  if rg -q "$pattern" "$SEEK"; then
    printf 'FAIL: %s\n' "$message" >&2
    printf '  rejected %s in SeekBar.x\n' "$pattern" >&2
    exit 1
  fi
}

require_pattern 'kThemeGlowScrubber' \
  'SeekBar.x must read the in-app Glow Scrubber setting.'
require_pattern 'kThemeGlowSeekBar' \
  'SeekBar.x must read the in-app Glow Seek Bar setting.'
require_pattern 'kThemeGlowStrength' \
  'SeekBar.x must scale glow from the in-app Glow Strength setting.'
require_pattern 'seekBarApplyScrubberGlow' \
  'Scrubber glow must have a dedicated helper that can be called even when color/size are unchanged.'
require_pattern 'seekBarApplyTrackGlow' \
  'Seek bar track glow must have a dedicated helper controlled by Glow Seek Bar.'
require_pattern 'seekBarUpdateScrubberColorAndPosition\(self, YES, center\)' \
  'Layout passes must reapply scrubber glow, not only preserve position.'
reject_pattern 'if \(scale == -1\) return;' \
  'Default scrubber size must not skip color/glow application.'
require_pattern 'Custom Glow Strength' \
  'Settings must keep presets while adding a custom strength input.' "$SETTINGS"
require_pattern 'themePresentGlowNumberInputWithTitle' \
  'Settings must use an explicit custom numeric input box for glow values.' "$SETTINGS"
require_pattern 'theme_glowOpacity' \
  'Settings must expose glow opacity as a custom value.' "$SETTINGS"
require_pattern 'theme_glowRadius' \
  'Settings must expose glow radius as a custom value.' "$SETTINGS"
require_pattern 'theme_glowLayers' \
  'Settings must expose glow layer count as a custom value.' "$SETTINGS"
require_pattern 'kThemeGlowLayers' \
  'Renderer must read the configured glow layer count.' "$COLOR"
require_pattern 'YTAGGlowLayer' \
  'Renderer must support stacked glow layers.' "$COLOR"

printf 'PASS: seekbar glow static check\n'
