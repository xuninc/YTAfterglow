#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(pwd)}"
MANAGER="$ROOT/Utils/YTAGDownloadManager.m"
FFMPEG="$ROOT/Utils/FFMpegHelper.m"

require_pattern() {
  local pattern="$1"
  local message="$2"

  if ! rg -q "$pattern" "$MANAGER"; then
    printf 'FAIL: %s\n' "$message" >&2
    printf '  expected %s in Utils/YTAGDownloadManager.m\n' "$pattern" >&2
    exit 1
  fi
}

reject_pattern() {
  local pattern="$1"
  local message="$2"

  if rg -q "$pattern" "$MANAGER"; then
    printf 'FAIL: %s\n' "$message" >&2
    printf '  rejected %s in Utils/YTAGDownloadManager.m\n' "$pattern" >&2
    exit 1
  fi
}

require_ffmpeg_pattern() {
  local pattern="$1"
  local message="$2"

  if ! rg -q "$pattern" "$FFMPEG"; then
    printf 'FAIL: %s\n' "$message" >&2
    printf '  expected %s in Utils/FFMpegHelper.m\n' "$pattern" >&2
    exit 1
  fi
}

require_pattern 'shareCompletionHandled' \
  'Share delivery must track whether UIActivityViewController completion has fired.'
require_pattern 'finalizeShareDeliveryForSession:.*reason:' \
  'Share delivery must finalize through an idempotent helper instead of directly from one callback.'
require_pattern 'watchShareDismissalForSession:.*activityViewController:.*attempt:' \
  'Share delivery must watch for dismissal when iOS skips completionWithItemsHandler.'
require_pattern 'share dismissal observed without completion' \
  'Fallback finalization must log when it unlocked a stuck share sheet session.'
require_pattern 'completionFired=%d' \
  'Concurrent-download rejection logs must include stale active-session diagnostics.'
require_pattern 'presentPhotosSaveFailureForSession:.*error:' \
  'Photos save failures must present a visible explanation before falling back to sharing.'
require_pattern "Photos couldn.*t save this video" \
  'Photos rejection copy must explain the format could not be saved.'
require_pattern 'Share File' \
  'Photos rejection alert must give the user an explicit share/export action.'
require_pattern 'YTAGDLStateTranscodingHEVC' \
  'Download state machine must represent the HEVC transcode step.'
require_pattern 'needsHEVCTranscodeForSession' \
  'VP9/AV1/WebM-style downloads must be detected before delivery.'
require_pattern 'beginHEVCTranscodeForSession' \
  'Non-native video downloads must transcode to HEVC before Save/Share delivery.'
require_pattern 'state → hevc' \
  'HEVC transcode transition must be visible in logs for field debugging.'
require_pattern 'HEVC transcode done' \
  'HEVC transcode success must be visible in logs for field debugging.'

require_ffmpeg_pattern 'transcodeVideoToHEVCForPhotos' \
  'FFmpeg helper must expose a Photos-compatible HEVC transcode path.'
require_ffmpeg_pattern 'hevc_videotoolbox' \
  'Photos transcode must use the iOS hardware HEVC encoder.'
require_ffmpeg_pattern 'tag:v hvc1' \
  'HEVC output must use hvc1 tagging for Photos/iOS compatibility.'

reject_pattern 'share completion: activity=%@ completed=%d"[^\\n]*\\n[[:space:]]*\\[innerSelf finalizeSuccessForSession:innerSession\\]' \
  'Share completion must not be the only direct finalize path.'

printf 'PASS: download manager static check\n'
