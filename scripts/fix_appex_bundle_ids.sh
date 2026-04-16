#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 /path/to/App.app new.bundle.prefix" >&2
  exit 1
fi

APP_DIR=$1
NEW_PREFIX=$2
OLD_PARENT_PREFIX="com.google.ios.youtube"

PLUGINS_DIR="$APP_DIR/PlugIns"
if [[ ! -d "$PLUGINS_DIR" ]]; then
  echo "No PlugIns directory at $PLUGINS_DIR — nothing to rewrite."
  exit 0
fi

shopt -s nullglob
patched_any=0

for appex in "$PLUGINS_DIR"/*.appex; do
  [[ -d "$appex" ]] || continue
  plist="$appex/Info.plist"
  [[ -f "$plist" ]] || continue

  current=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist" 2>/dev/null || echo "")
  if [[ -z "$current" ]]; then
    echo "skip: no CFBundleIdentifier in $plist"
    continue
  fi

  if [[ "$current" == "$OLD_PARENT_PREFIX."* ]]; then
    suffix="${current#${OLD_PARENT_PREFIX}.}"
    new_id="${NEW_PREFIX}.${suffix}"
  elif [[ "$current" == "$NEW_PREFIX."* ]]; then
    echo "skip: $appex already uses new prefix ($current)"
    continue
  else
    # Bundle ID doesn't match the expected YouTube prefix — fall back to suffixing
    # the last two components (e.g. "OpenYouTube.Extension") onto NEW_PREFIX.
    tail2=$(echo "$current" | awk -F. '{ print $(NF-1) "." $NF }')
    new_id="${NEW_PREFIX}.${tail2}"
  fi

  echo "Rewriting $appex bundle ID: $current -> $new_id"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $new_id" "$plist"
  patched_any=1
done

if [[ $patched_any -eq 0 ]]; then
  echo "No .appex bundles needed rewriting under $PLUGINS_DIR"
fi
