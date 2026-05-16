#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(pwd)}"

reject() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  if rg -q "$pattern" "$ROOT/$file"; then
    echo "FAIL: $message" >&2
    exit 1
  fi
}

require() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  if ! rg -q "$pattern" "$ROOT/$file"; then
    echo "FAIL: $message" >&2
    exit 1
  fi
}

file_present() {
  local file="$1"
  local message="$2"
  if [ ! -f "$ROOT/$file" ]; then
    echo "FAIL: $message" >&2
    exit 1
  fi
}

file_present 'UI/YTAGAfterglowFeedModels.h' 'compact feed model header must exist'
file_present 'UI/YTAGAfterglowFeedModels.m' 'compact feed model implementation must exist'
file_present 'UI/YTAGAfterglowFeedStore.h' 'compact feed store header must exist'
file_present 'UI/YTAGAfterglowFeedStore.m' 'compact feed store implementation must exist'
file_present 'UI/YTAGAfterglowFeedViewController.h' 'compact feed controller header must exist'
file_present 'UI/YTAGAfterglowFeedViewController.m' 'compact feed controller implementation must exist'

require 'FEafterglow' 'Utils/YTAGUserDefaults.m' 'Afterglow tab must be allowed and defaultable'
require 'FEafterglow' 'Settings.x' 'Afterglow tab must be exposed in Manage Tabs'
require 'FEafterglow' 'YTAfterglow.x' 'Afterglow tab must be synthesized/routed'
require 'YTAGOpenAfterglowFeedFromView' 'YTAfterglow.x' 'Afterglow tab must open the custom compact feed'
require 'recordSectionListModel' 'YTAfterglow.x' 'Afterglow feed must capture native section-list models'
require 'missingSourceIdentifiersForSourceIdentifiers' 'UI/YTAGAfterglowFeedStore.h' 'Afterglow feed store must expose missing source detection for priming'
require 'ytagPrimeAfterglowFeedSourcesFromController' 'YTAfterglow.x' 'Afterglow tab must prime missing native sources'
require 'sYTAGAfterglowFeedPrimeInProgress' 'YTAfterglow.x' 'Afterglow source priming must be guarded against recursion'
require 'YTAGAfterglowPrimeSourcePivotId' 'YTAfterglow.x' 'Afterglow source priming must map store sources to native pivot ids'
require 'FEsubscriptions' 'YTAfterglow.x' 'Afterglow feed must prime the native Subscriptions source'
require 'FEshorts' 'YTAfterglow.x' 'Afterglow feed must prime the native Shorts source'
require 'FEhype_leaderboard' 'YTAfterglow.x' 'Afterglow feed should prime the Hype source when available'
require 'Recommended' 'UI/YTAGAfterglowFeedStore.m' 'Afterglow feed must expose a Recommended rail'
require 'Subscriptions' 'UI/YTAGAfterglowFeedStore.m' 'Afterglow feed must expose a Subscriptions rail when data exists'
require 'Shorts' 'UI/YTAGAfterglowFeedStore.m' 'Afterglow feed must expose a Shorts rail when data exists'
require 'YTAGFeedRendererIsPlaylistLike' 'UI/YTAGAfterglowFeedStore.m' 'Playlist-like renderers must be rejected at source'
require 'YTAGFeedCommandLooksPlayable' 'UI/YTAGAfterglowFeedStore.m' 'Feed items must require playable watch/reel commands'
require 'videoID.length == 0 && !YTAGFeedCommandLooksPlayable\(command\)' 'UI/YTAGAfterglowFeedStore.m' 'Title-only shelf rows must not become tappable feed tiles'
require 'playlistmix|mixplaylist|radio' 'UI/YTAGAfterglowFeedStore.m' 'Mix/radio playlist renderers must be rejected at source'
require 'watchlater|queue' 'UI/YTAGAfterglowFeedStore.m' 'Watch Later and queue renderers must be rejected at source'
require 'reelWatchEndpoint|shortsWatchEndpoint' 'UI/YTAGAfterglowFeedStore.m' 'Shorts commands must be accepted without allowing playlist browse commands'
require 'afterglowFeedDensity' 'Utils/YTAGUserDefaults.m' 'feed density preference must be registered'
require 'AfterglowFeed' 'layout/Library/Application Support/YTAfterglow.bundle/en.lproj/Localizable.strings' 'feed strings must be localized'

reject 'YTAGAfterglowFeedContentKindPlaylist' 'UI/YTAGAfterglowFeedModels.h' 'playlist content kind must not enter the compact video feed'
reject 'playlistRenderer|gridPlaylistRenderer' 'UI/YTAGAfterglowFeedStore.m' 'playlist renderers must not be traversed as playable feed items'
reject 'Playlists / Watch Later / History' 'UI/YTAGAfterglowFeedViewController.m' 'feed must not ship the old playlist/library rail'
reject 'Latest uploads|Home picks|Streams, queues, and saved paths' 'UI/YTAGAfterglowFeedViewController.m' 'feed must not ship seeded dashboard cards'
reject 'CGSizeZero|removeCellsAtIndexPath|YTAGLiteModeApplyCompactFeedLayout' 'UI/YTAGAfterglowFeedViewController.m' 'feed must not compact by mutating native feed cells'
reject 'AIza' 'UI/YTAGAfterglowFeedStore.m' 'feed must not embed a public YouTube Data API key'

echo "afterglow compact feed static check passed"
