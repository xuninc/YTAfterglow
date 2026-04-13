#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/App.app" >&2
  exit 1
fi

APP_DIR=$1

if [[ ! -d "$APP_DIR" ]]; then
  echo "app bundle not found: $APP_DIR" >&2
  exit 1
fi

removed_any=0

while IFS= read -r dir; do
  echo "Removing signing artifact directory: $dir"
  rm -rf "$dir"
  removed_any=1
done < <(find "$APP_DIR" -type d \( -name "_CodeSignature" -o -name "SC_Info" \) | sort)

while IFS= read -r file; do
  echo "Removing signing artifact file: $file"
  rm -f "$file"
  removed_any=1
done < <(find "$APP_DIR" -type f \( -name "embedded.mobileprovision" -o -name "*.sinf" -o -name "*.supf" -o -name "archived-expanded-entitlements.xcent" \) | sort)

if [[ $removed_any -eq 0 ]]; then
  echo "No signing artifacts found under $APP_DIR"
fi
