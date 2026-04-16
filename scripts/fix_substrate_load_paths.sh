#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/App.app" >&2
  exit 1
fi

APP_DIR=$1
ABS_SUBSTRATE="/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate"
RPATH_SUBSTRATE="@rpath/CydiaSubstrate.framework/CydiaSubstrate"

if [[ ! -d "$APP_DIR" ]]; then
  echo "app bundle not found: $APP_DIR" >&2
  exit 1
fi

patched_any=0

while IFS= read -r binary; do
  if ! file "$binary" | grep -q "Mach-O"; then
    continue
  fi

  if otool -L "$binary" | grep -q "$ABS_SUBSTRATE"; then
    echo "Patching Substrate load path in $binary"
    codesign --remove-signature "$binary" 2>/dev/null || true
    install_name_tool -change "$ABS_SUBSTRATE" "$RPATH_SUBSTRATE" "$binary"
    patched_any=1
  fi
done < <(find "$APP_DIR" -type f)

if [[ $patched_any -eq 0 ]]; then
  echo "No absolute Substrate load paths found under $APP_DIR"
fi
