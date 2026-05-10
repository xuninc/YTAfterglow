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
require 'YTAGLiteModeStyleAttributedString' 'Utils/YTAGLiteMode.h' 'Lite Mode must expose attributed text styling for Texture comment text'
require 'YTAGLiteModeCompactFeedVideoWidthKey' 'Utils/YTAGLiteMode.h' 'Lite compact feed video width key must be public'
require 'YTAGLiteModeCompactFeedVideoScale' 'Utils/YTAGLiteMode.h' 'Lite compact feed video scale helper must be public'
require 'YTAGLiteModeApplyCompactFeedLayout' 'Utils/YTAGLiteMode.h' 'Lite compact feed layout helper must be public'
require 'YTAGLiteModeApplyCompactFeedPlaybackLayout' 'Utils/YTAGLiteMode.h' 'Lite compact feed layout must cover inline playback surfaces'
require 'YTAGLiteModeApplyBackgroundColor' 'Utils/YTAGLiteMode.h' 'Lite themed background helper must be public'
require 'settings' 'Utils/YTAGLiteMode.m' 'Lite collection scope must explicitly exclude Settings surfaces'
require 'CourierNewPSMT' 'Utils/YTAGLiteMode.m' 'Lite Mode Courier Classic font must prefer Courier New'
require 'YTAGLiteModeCompactFeedVideoWidthKey' 'Utils/YTAGLiteMode.m' 'Lite compact feed video width key must exist in helper'
require 'YTAGLiteModeCompactFeedVideoScale' 'Utils/YTAGLiteMode.m' 'Lite compact feed video scale helper must exist in helper'
require 'YTAGLiteDefaultCompactFeedVideoWidth = 33' 'Utils/YTAGLiteMode.m' 'Lite compact feed video default must be roughly one-third width'
require 'YTAGLiteMinimumCompactFeedVideoWidth = 25' 'Utils/YTAGLiteMode.m' 'Lite compact feed video width must allow much smaller thumbnails'
require 'YTAGLiteModeApplyCompactFeedLayout' 'Utils/YTAGLiteMode.m' 'Lite compact feed layout helper must exist in helper'
require 'YTAGLiteModeApplyCompactFeedPlaybackLayout' 'Utils/YTAGLiteMode.m' 'Lite compact feed playback helper must exist in helper'
require 'YTElementsInlineMutedPlaybackView' 'Utils/YTAGLiteMode.m' 'Lite compact feed playback helper must recognize YouTube inline muted playback views'
require 'YTAGLiteCompactFeedCandidateScore' 'Utils/YTAGLiteMode.m' 'Lite compact feed layout must score candidates instead of stopping at the first marker hit'
require 'YTAGLiteBestCompactFeedThumbnailCandidate' 'Utils/YTAGLiteMode.m' 'Lite compact feed layout must search for the best thumbnail candidate'
require 'YTAGLiteModeApplyBackgroundColor' 'Utils/YTAGLiteMode.m' 'Lite background helper must exist in helper'
require 'YTAGLiteCommentSurfaceTokenKey' 'Utils/YTAGLiteMode.m' 'Lite comment surface detection must cache by view structure token'
require 'YTAGLiteCommentChromeTokenKey' 'Utils/YTAGLiteMode.m' 'Lite comment chrome styling must be idempotent by view structure token'
require 'YTAGLiteCollectionCleanResultKey' 'Utils/YTAGLiteMode.m' 'Lite collection cleanup scope must be cached per collection view'
require 'YTAGLiteViewCleanupTokenKey' 'Utils/YTAGLiteMode.m' 'Lite generic view cleanup must be idempotent by view structure token'
require 'YTAGLiteCompactFeedLayoutTokenKey' 'Utils/YTAGLiteMode.m' 'Lite compact feed layout must be idempotent by view structure token'
require 'YTAGLiteLabelStyleTokenKey' 'Utils/YTAGLiteMode.m' 'Lite label styling must be idempotent while scrolling'
require 'objc_getAssociatedObject\(view, YTAGLiteCommentSurfaceTokenKey\)' 'Utils/YTAGLiteMode.m' 'Lite comment surface detection must reuse cached results while scrolling'
require 'objc_setAssociatedObject\(root, YTAGLiteCommentChromeTokenKey' 'Utils/YTAGLiteMode.m' 'Lite comment chrome styling must mark styled roots while scrolling'
require 'objc_getAssociatedObject\(collectionView, YTAGLiteCollectionCleanResultKey\)' 'Utils/YTAGLiteMode.m' 'Lite collection scope checks must reuse cached results while scrolling'
require 'objc_getAssociatedObject\(root, YTAGLiteViewCleanupTokenKey\)' 'Utils/YTAGLiteMode.m' 'Lite generic cleanup must skip unchanged roots while scrolling'
require 'objc_getAssociatedObject\(root, YTAGLiteCompactFeedLayoutTokenKey\)' 'Utils/YTAGLiteMode.m' 'Lite compact feed layout must skip unchanged roots while scrolling'
require 'CGRectGetWidth\(frame\)' 'Utils/YTAGLiteMode.m' 'Lite compact feed layout token must include subview frame geometry so late layout is reprocessed'
require 'CGRectGetWidth\(bounds\)' 'Utils/YTAGLiteMode.m' 'Lite compact feed layout token must include subview bounds geometry so late layout is reprocessed'
require 'return attributedString' 'Utils/YTAGLiteMode.m' 'Lite attributed text styling must return original strings when fonts already match'
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
require 'YTAGLiteModeApplyCompactFeedLayout' 'YTAfterglow.x' 'main tweak must apply compact Lite feed video layout'
require '%hook YTElementsInlineMutedPlaybackView' 'YTAfterglow.x' 'main tweak must reapply compact Lite feed sizing when inline playback lays out'
require 'YTAGLiteModeApplyCompactFeedPlaybackLayout' 'YTAfterglow.x' 'main tweak must compact inline playback surfaces after YouTube swaps them in'
require 'YTAGLiteModeApplyBackgroundColor' 'YTAfterglow.x' 'main tweak must keep Lite watch surfaces on the theme background'
require 'YTAGLiteModeStyleAttributedString' 'YTAfterglow.x' 'main tweak must apply Courier to ASTextNode attributed text'
require '%hook UILabel' 'YTAfterglow.x' 'Lite Mode must force Courier onto UIKit labels globally'
require 'setFont:' 'YTAfterglow.x' 'Lite Mode UILabel hook must override font assignments'
require '%hook YTEngagementPanelHeaderView' 'YTAfterglow.x' 'Lite Mode must style expanded comments engagement panel header text'
require 'titleLabel' 'YTAfterglow.x' 'Lite engagement panel header hook must target the title label'
require 'LiteCompactFeedVideoWidth' 'Settings.x' 'Feed settings must expose the Lite compact feed video width control'
require 'YTAGLiteModeCompactFeedVideoWidthKey min:25 max:100 fallback:33' 'Settings.x' 'Lite compact feed video setting must allow one-third width'
require 'YTAGLiteModeCompactFeedVideoWidthKey' 'Utils/YTAGUserDefaults.m' 'Lite compact feed video width must have a registered default'
require 'LiteMode' 'layout/Library/Application Support/YTAfterglow.bundle/en.lproj/Localizable.strings' 'Lite Mode strings must be localized'
require 'LiteCompactFeedVideoWidth' 'layout/Library/Application Support/YTAfterglow.bundle/en.lproj/Localizable.strings' 'Lite compact feed video strings must be localized'
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

if perl -0ne 'exit(/layoutSubviews(?:(?!%end).)*YTAGLiteModeShouldRemoveFeedView\(cell\)/s ? 0 : 1)' "$ROOT/YTAfterglow.x"; then
  echo "FAIL: Lite Mode must not rescan feed-removal signatures from layoutSubviews while scrolling" >&2
  exit 1
fi

if perl -0ne 'exit(/%hook YTIElementRenderer(?:(?!%end).)*YTAGLiteModeShouldPruneFeedObject/s ? 0 : 1)' "$ROOT/YTAfterglow.x"; then
  echo "FAIL: Lite Mode must not nil low-level YTIElementRenderer data; prune whole feed sections instead" >&2
  exit 1
fi

if ! perl -0ne 'exit(/BOOL isCommentSurface = YTAGLiteModeShouldStyleCommentView\(cell\);\s*if \(!isCommentSurface\) \{(?:(?!if \(isCommentSurface\)).)*YTAGLiteModeApplyViewCleanup\(cell\);\s*\}\s*if \(isCommentSurface\) \{\s*YTAGLiteModeApplyCommentChrome\(cell\);/s ? 0 : 1)' "$ROOT/YTAfterglow.x"; then
  echo "FAIL: Lite comment cells must skip generic cleanup before comment-specific styling" >&2
  exit 1
fi

if ! perl -0ne 'exit(/%hook ASTextNode(?:(?!%end).)*setAttributedText:(?:(?!%end).)*YTAGLiteModeStyleAttributedString/s ? 0 : 1)' "$ROOT/YTAfterglow.x"; then
  echo "FAIL: Lite Mode must hook ASTextNode attributed text so Texture text uses Courier New globally" >&2
  exit 1
fi

if ! perl -0ne 'exit(/%hook UILabel(?:(?!%end).)*setFont:(?:(?!%end).)*YTAGLiteModeFont(?:(?!%end).)*setAttributedText:(?:(?!%end).)*YTAGLiteModeStyleAttributedString/s ? 0 : 1)' "$ROOT/YTAfterglow.x"; then
  echo "FAIL: Lite Mode must hook UILabel font and attributed text so UIKit text uses Courier New globally" >&2
  exit 1
fi

if rg -q '@"metadata"|@"viewcount"' "$ROOT/Utils/YTAGLiteMode.m"; then
  echo "FAIL: Lite cleanup must not hide video metadata containers or view-count text under videos" >&2
  exit 1
fi

if rg -q 'width = MIN\(MAX\(width > 0 \? width : 88, 80\), 100\)' "$ROOT/Utils/YTAGLiteMode.m"; then
  echo "FAIL: Lite compact feed width must not be limited to the old 80-100 percent range" >&2
  exit 1
fi

if rg -q 'UIColor \*background = \[UIColor colorWithWhite:0\.015|UIColor \*surface = \[UIColor colorWithWhite:0\.055' "$ROOT/Utils/YTAGLiteMode.m"; then
  echo "FAIL: Lite monochrome theme must not use the old near-black preset" >&2
  exit 1
fi

echo "lite-mode static check passed"
