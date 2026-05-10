# Afterglow Dashboard Tab Design

Date: 2026-05-10

## Goal

Add a dedicated `Afterglow` tab that provides a cleaner, better-designed way to
browse YouTube content than the native one-video-at-a-time infinite feed.

This is not a Lite Mode feature. Lite Mode remains the stripped-down,
low-distraction mode. The Afterglow tab is a feature-rich browsing dashboard:
organized, visual, fast to scan, and designed around access to content instead
of an endless vertical feed.

## Product Shape

The Afterglow tab should be an Afterglow-owned browsing surface. YouTube remains
responsible for account state, content data, and playback navigation where
possible, but Afterglow owns the page layout.

The first version should be a full dashboard, not a narrow proof of concept.
It should support multiple content sources from the start, while allowing any
individual module to disappear cleanly if that source is unavailable.

Downloads are intentionally excluded from v1. YouTube offline/download internals
and Afterglow's own download pipeline are not yet a reliable dashboard content
source.

## Layout Model

The dashboard is a vertically scrolling page made of modules. Modules can render
as horizontal carousels, compact multi-row carousels, grid blocks, queue strips,
or playlist cards.

Important principle:

`Content source != layout section.`

A single source can produce multiple dashboard modules, and each module can use
the layout that best fits that content. For example, Playlists should not be
limited to one row. It can show playlist cards, smaller tile grids, grouped
playlist rows, or videos pulled from playlists.

## Initial Modules

The first implementation should support these module families:

- Continue Watching: unfinished videos with progress where available.
- New From Subscriptions: recent uploads from subscribed channels.
- Recommended: a cleaner recommended row or rows that do not dominate the page.
- Watch Later: queue-like access to saved videos.
- History: recent watched videos and possible rewatch/continue modules.
- Playlists: playlist cards plus optional smaller rows for playlist content.

Future modules can include:

- Long Videos
- Short Videos
- Recently Watched Channels
- Saved Channels
- Downloads, only after there is a reliable local library source

## Navigation

The app should expose a user-facing `Afterglow` tab in the pivot/tab bar.

The tab can reuse existing YouTube pivot infrastructure, but it should not load
or depend on the old Trending backend as a content source. Legacy tab IDs such
as Trending or Explore may be useful only as routing shells if that proves safer
than creating a new pivot route.

Selecting the Afterglow tab should present the custom dashboard. Tapping a video
tile should hand off to YouTube's normal navigation/player path so playback,
history, comments, and account behavior remain native.

## Data Strategy

The primary risk is data sourcing, not layout. The implementation should isolate
data adapters from UI modules so each content source can be developed and
replaced independently.

Preferred first strategy:

- Capture or reuse video renderer/model data from existing YouTube surfaces when
  stable.
- Extract only the fields needed by the dashboard: title, channel, thumbnail,
  duration, progress, metadata, and navigation endpoint.
- Store those fields in a small Afterglow dashboard item model.
- Render dashboard modules from the Afterglow model instead of directly binding
  UI to raw YouTube renderer objects.

Fallback behavior:

- If a module has no data, hide that module.
- If all modules are empty, show a simple empty state with access to Search,
  Home, Subscriptions, and Settings.
- A broken or unavailable source must not make the dashboard look half-rendered.

## Visual Direction

The dashboard should feel more like a polished media browsing surface than the
native YouTube phone feed.

Baseline visual rules:

- Fixed tile sizes per module type.
- Predictable row heights.
- Visible page background around content.
- Clear section headings.
- Dense enough to scan several videos at once.
- Not a giant full-width card feed.
- Theme and font choices should respect Afterglow theme settings where practical.
- Lite Mode may influence theme/density if enabled, but the tab exists
  independently of Lite Mode.

## Technical Boundaries

Do not implement this by shrinking native Home or Subscriptions feed cells.
Previous work showed that visual transforms inside YouTube's native feed can
leave blank space and cause layout fights because YouTube already measured those
cells.

Avoid these patterns for dashboard layout:

- Returning `CGSizeZero` for dashboard pruning.
- Deleting collection cells after `cellForItemAtIndexPath:`.
- Nil-ing low-level renderer data to force content disappearance.
- Depending on the old Trending backend for the dashboard's actual content.

The dashboard should own its layout so fixed tile sizes, horizontal scrolling
rows, and multi-row playlist modules do not fight YouTube's native feed
measurements.

## Implementation Units

The implementation should be split into these boundaries:

- Tab routing: adds/selects the Afterglow tab and presents the dashboard.
- Dashboard controller/view: owns the vertical module page.
- Module layout layer: reusable tile row, compact grid, playlist card, and queue
  strip layouts.
- Data model: small Afterglow item/module structs or Objective-C model classes.
- Data adapters: source-specific extractors for subscriptions, recommendations,
  watch later, history, and playlists.
- Navigation bridge: opens selected dashboard items through YouTube's native
  endpoint/player path.

## Verification

Static verification should check that:

- The Afterglow tab is present in default/all tab lists.
- The dashboard code does not call the Lite compact-feed transform helpers.
- Dashboard layout does not rely on collection-cell deletion or zero-size feed
  pruning.
- Downloads are not included as a v1 dashboard module.

Manual/runtime verification should cover:

- Afterglow tab appears and can be selected.
- Dashboard renders without native Home feed cells.
- Multiple module layouts can coexist on the same page.
- Empty modules disappear cleanly.
- Tapping a video opens native playback.
- Returning from playback preserves dashboard scroll position where practical.
- Home, Subscriptions, and Lite Mode behavior remain unchanged.
