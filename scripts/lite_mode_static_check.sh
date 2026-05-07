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

require 'YTAGEffectiveBool' 'Utils/YTAGLiteMode.h' 'effective bool helper must be declared'
require 'liteModeEnabled' 'Utils/YTAGLiteMode.m' 'liteModeEnabled preference must exist in helper'
require 'liteModeDefaultThemeVersion' 'Utils/YTAGLiteMode.m' 'Lite theme defaults must use a versioned migration'
require 'YTAGSetLiteModeEnabled' 'Settings.x' 'settings toggle must use shared setter'
require 'YTAGSetLiteModeEnabled' 'UI/YTAGPremiumControls.m' 'premium controls toggle must use shared setter'
require 'YTAGLiteModeShouldCleanCollectionView' 'Utils/YTAGLiteMode.h' 'Lite cleanup must be scoped away from Settings collections'
require 'YTAGLiteModeActiveTabs' 'Utils/YTAGLiteMode.h' 'Lite Mode must expose startup-safe active tabs'
require 'YTAGLiteModeStartupTab' 'Utils/YTAGLiteMode.h' 'Lite Mode must expose a startup-safe Home tab'
require 'YTAGLiteModeShouldPruneFeedObject' 'Utils/YTAGLiteMode.h' 'Lite Mode must expose renderer/feed pruning helper'
require 'YTAGLiteModeFont' 'Utils/YTAGLiteMode.h' 'Lite Mode must expose a Courier font helper'
require 'YTAGLiteModeStyleLabel' 'Utils/YTAGLiteMode.h' 'Lite Mode must expose label styling helper'
require 'settings' 'Utils/YTAGLiteMode.m' 'Lite collection scope must explicitly exclude Settings surfaces'
require 'CourierNewPSMT' 'Utils/YTAGLiteMode.m' 'Lite Mode Courier Classic font must prefer Courier New'
require 'FEwhat_to_watch.*FEsubscriptions.*FElibrary' 'Utils/YTAGLiteMode.m' 'Lite Mode active tabs must reduce to Home, Subscriptions, and You/Library'
require 'return @"FEwhat_to_watch"' 'Utils/YTAGLiteMode.m' 'Lite Mode startup tab must be Home'
require 'YTAGLiteModeShouldPruneFeedObject' 'YTAfterglow.x' 'main tweak must use Lite renderer/feed pruning helper'
require 'YTAGLiteModeActiveTabs\(\)' 'YTAfterglow.x' 'pivot tabs must use Lite active tabs without overwriting stored tabs'
require 'YTAGLiteModeStartupTab\(\)' 'YTAfterglow.x' 'startup tab must use Lite Home helper'
require 'Restart Now|RestartNow' 'Settings.x' 'Lite Mode toggle must offer a restart action'
require 'Lite Mode needs a restart|restart' 'Settings.x' 'Lite Mode toggle must tell users restart is required'
require 'YTAGLiteModeShouldCleanCollectionView\(self\)' 'YTAfterglow.x' 'collection cleanup must use scoped Lite guard'
require 'YTAGLiteModeApplyViewCleanup' 'YTAfterglow.x' 'main tweak must apply Lite view cleanup'
require 'YTAGLiteModeApplyCommentChrome' 'YTAfterglow.x' 'main tweak must apply Lite comment cleanup'
require 'LiteMode' 'layout/Library/Application Support/YTAfterglow.bundle/en.lproj/Localizable.strings' 'Lite Mode strings must be localized'
require '#define ytagBool\(key\) YTAGEffectiveBool\(key\)' 'YTAfterglow.h' 'ytagBool must route through effective helper'
for marker in commententrypoint commentsentrypoint viewcomments showcomments opencomments; do
  require "$marker" 'Utils/YTAGLiteMode.m' "Lite comment cleanup must preserve $marker controls"
done
for marker in community shopping breakingnews mixplaylist radio chipcloud filterchip promoted sponsor commerce reel shortsshelf richshelf suggestedvideo watchnext; do
  require "$marker" 'Utils/YTAGLiteMode.m' "Lite feed pruning must include $marker surfaces"
done

for broad_marker in '@"post"' '@"news"' '@"mix"' '@"shelf"' '@"horizontal"' '@"carousel"' '@"sparkles"'; do
  if rg -q "$broad_marker" "$ROOT/Utils/YTAGLiteMode.m"; then
    echo "FAIL: Lite feed pruning must not use broad marker $broad_marker because it can remove normal video/comment internals" >&2
    exit 1
  fi
done

if perl -0ne 'exit(/%hook ASCollectionView.*YTAGLiteModeShouldPruneFeedObject.*CGSizeZero/s ? 0 : 1)' "$ROOT/YTAfterglow.x"; then
  echo "FAIL: Lite Mode must not hide already-created ASCollectionView items with CGSizeZero; prune upstream before layout" >&2
  exit 1
fi

if perl -0ne 'exit(/cellForItemAtIndexPath:.*YTAGLiteModeShouldPruneFeedObject.*removeCellsAtIndexPath/s ? 0 : 1)' "$ROOT/YTAfterglow.x"; then
  echo "FAIL: Lite Mode must not delete cells from cellForItemAtIndexPath; prune upstream before cells exist" >&2
  exit 1
fi

if perl -0ne 'exit(/%hook YTIElementRenderer(?:(?!%end).)*YTAGLiteModeShouldPruneFeedObject/s ? 0 : 1)' "$ROOT/YTAfterglow.x"; then
  echo "FAIL: Lite Mode must not nil low-level YTIElementRenderer data; prune whole feed sections instead" >&2
  exit 1
fi

if ! perl -0ne 'exit(/BOOL isCommentSurface = YTAGLiteModeShouldStyleCommentView\(cell\);\s*if \(!isCommentSurface\) \{\s*YTAGLiteModeApplyViewCleanup\(cell\);\s*\}\s*if \(isCommentSurface\) \{\s*YTAGLiteModeApplyCommentChrome\(cell\);/ ? 0 : 1)' "$ROOT/YTAfterglow.x"; then
  echo "FAIL: Lite comment cells must skip generic cleanup before comment-specific styling" >&2
  exit 1
fi

if rg -q '@"metadata"|@"viewcount"' "$ROOT/Utils/YTAGLiteMode.m"; then
  echo "FAIL: Lite cleanup must not hide video metadata containers or view-count text under videos" >&2
  exit 1
fi

if rg -q 'UIColor \*background = \[UIColor colorWithWhite:0\.015|UIColor \*surface = \[UIColor colorWithWhite:0\.055' "$ROOT/Utils/YTAGLiteMode.m"; then
  echo "FAIL: Lite monochrome theme must not use the old near-black preset" >&2
  exit 1
fi

echo "lite-mode static check passed"
