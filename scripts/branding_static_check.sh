#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(pwd)}"
STRINGS_DIR="$ROOT/layout/Library/Application Support/YTAfterglow.bundle"
EN_STRINGS="$STRINGS_DIR/en.lproj/Localizable.strings"

if rg -n 'YTPlus|YTPus' "$STRINGS_DIR"; then
  echo "FAIL: shipped localization strings must not mention YTPlus/YTPus" >&2
  exit 1
fi

if ! rg -q 'This action will reset YouTube Afterglow.s settings to default and close YouTube' "$EN_STRINGS"; then
  echo "FAIL: English reset warning must name YouTube Afterglow's settings" >&2
  exit 1
fi

echo "branding static check passed"
