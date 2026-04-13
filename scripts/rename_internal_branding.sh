#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

rename_path() {
  local from="$1"
  local to="$2"

  if [[ ! -e "$from" || "$from" == "$to" ]]; then
    return 0
  fi

  mkdir -p "$(dirname "$to")"
  mv "$from" "$to"
  printf 'renamed: %s -> %s\n' "$from" "$to"
}

process_current_files() {
  while IFS= read -r -d '' file; do
    file="${file#./}"
    should_process "$file" || continue
    apply_replacements "$file"
  done < <(
    find . \
      \( -path './.git' -o -path './.theos' -o -path './packages' -o -path './sdks' \) -prune \
      -o -type f -print0
  )
}

should_process() {
  local path="$1"

  case "$path" in
    .github/workflows/*|layout/*|scripts/*|Utils/*|Makefile|control|*.x|*.h|*.m|*.plist)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

apply_replacements() {
  local file="$1"

  if ! grep -Iq . "$file"; then
    return 0
  fi

  perl -0pi -e '
    s/com\.dvntm\.ytafterglow/com.dvntm.ytafterglow/g;
    s/YTAfterglow\.bundle/YTAfterglow.bundle/g;
    s/ytplus\.deb/ytafterglow.deb/g;
    s/YTAfterglow RPC/YTAfterglow RPC/g;
    s/YTAfterglowRPC/YTAfterglowRPC/g;
    s/YTAfterglow/YTAfterglow/g;
    s/YTAfterglowSectionItem/YTAfterglowSectionItem/g;
    s/YTAfterglowSection/YTAfterglowSection/g;
    s/manageSpeedmasterYTAfterglow/manageSpeedmasterYTAfterglow/g;
    s/NSBundle\+YTAfterglow/NSBundle+YTAfterglow/g;
    s/\bYTLite\b/YTAfterglow/g;
    s/\bytlite\b/ytafterglow/g;
    s/\bYTL(?=[A-Z_])/YTAG/g;
    s/\bytl(?=[A-Z_])/ytag/g;
  ' "$file"
}

process_current_files

rename_path "layout/Library/Application Support/YTAfterglow.bundle" "layout/Library/Application Support/YTAfterglow.bundle"
rename_path "Utils/YTAGUserDefaults.h" "Utils/YTAGUserDefaults.h"
rename_path "Utils/YTAGUserDefaults.m" "Utils/YTAGUserDefaults.m"
rename_path "Utils/NSBundle+YTAfterglow.h" "Utils/NSBundle+YTAfterglow.h"
rename_path "Utils/NSBundle+YTAfterglow.m" "Utils/NSBundle+YTAfterglow.m"
rename_path "YTAfterglow.h" "YTAfterglow.h"
rename_path "YTAfterglow.x" "YTAfterglow.x"
rename_path "YTAfterglow.plist" "YTAfterglow.plist"

process_current_files

echo "internal branding migration complete"
