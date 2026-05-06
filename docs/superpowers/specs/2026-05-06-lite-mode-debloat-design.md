# Lite Mode Debloat Design

Date: 2026-05-06
Repo: `/home/corey/repos/xuninc/YTAfterglow`

## Purpose

Lite Mode should become a startup debloat profile for YouTube Afterglow, not just a visual theme. The main success criteria are speed, snappiness, and reduced addictive surfaces while keeping YouTube useful for intentional watching.

The user approved an aggressive default: Lite Mode may remove or disable whole YouTube surfaces when they are noisy or expensive. The UI must still look intentional. It should not feel like a normal YouTube screen with random missing pieces.

## User Experience

Lite Mode remains controlled by the stored `liteModeEnabled` preference. Turning it on or off requires an app restart because the mode affects startup-only tab selection, feed loading, renderer pruning, and surface initialization.

When the user changes the Lite Mode toggle:

- Store the requested mode.
- Apply the default Lite theme only when enabling and only when needed.
- Show a restart confirmation with `Restart Now` and `Later`.
- Do not pretend the current session has fully switched modes.

On next launch, Lite Mode becomes active from startup and applies the full debloat profile before YouTube builds as many expensive surfaces as possible.

## Visual Direction

Lite Mode uses a terminal-inspired, monochrome style by default.

Approved font direction:

- Use Courier / Courier New as the Lite-owned terminal style.
- Apply it to Lite comments, Lite empty states, Lite-safe placeholder rows, and any Lite-owned labels.
- Do not force Courier globally across stock YouTube views if that causes layout breakage or excessive UIKit churn.

The default Lite theme should be grayscale and white:

- Dark gray or near-black surfaces.
- White primary text.
- Gray secondary text.
- White seek bar and scrubber.
- Optional white glow where the existing theme system supports it.
- No default gradients.

User theme colors should still be respected where they do not hurt readability. The default Lite theme is a starting point, not a permanent lock.

## Debloat Strategy

Lite Mode should use layered blocking from earliest to latest:

1. Startup preference overrides for existing Afterglow behavior.
2. Tab pruning before pivot tabs render.
3. YouTube renderer/model pruning before collection cells are created.
4. Zero-size or delete collection cells that slip through.
5. Recursive view cleanup only as a fallback.

The implementation should avoid relying only on hiding subviews after YouTube has already paid the cost to create them.

## Tabs And Startup

Lite Mode should keep a small intentional tab set:

- Home.
- Subscriptions.
- You / Library.

Search must remain available from the top bar even if the normal user preference hides search. Shorts should not be an active tab in Lite Mode.

Startup should land on Home. Home can be stock Home only if it is successfully debloated into a quiet feed. If stock Home remains too noisy or expensive, the design allows a Lite-owned replacement Home surface in a later step.

## Home And Feed

Home should be reduced to plain, useful video content. Preferred content order:

1. New videos from subscriptions.
2. Recent subscription videos.
3. Plain video rows that survive the Lite-safe filter.
4. A compact Lite empty state if no useful rows remain.

Lite Mode should block or remove:

- Shorts shelves, Shorts grids, and reel renderers.
- Explore, Trending, and hype surfaces.
- Ads, promoted, sponsor, and commerce renderers.
- Community posts, polls, stories, and posts.
- Shopping, product, merch, and promo cards.
- News, breaking-news, mix, radio, and playlist recommendation shelves.
- Chip clouds, filter chips, rich carousels, and other heavy feed chrome.
- Engagement bait, badges, action menus, and decorative metadata where safely removable.

If a section becomes empty after pruning, collapse it. Only show a compact Courier Lite placeholder when collapsing would leave an obviously broken screen.

## Watch Page

Keep the watch page focused on playback.

Keep:

- Video playback.
- Title.
- Channel identity.
- Basic playback controls.
- Seek bar.
- Fullscreen.
- Captions.
- Quality.
- PiP.
- Download controls where available.
- Afterglow settings failsafe access.

Remove or suppress:

- Watch-next recommendations.
- Autoplay prompts and end-screen clutter.
- Like, dislike, share, save, remix, clip, and other action-row clutter.
- Promo panels, product cards, and rich engagement panels.
- Decorative badges and engagement chips.

## Shorts

Lite Mode should remove Shorts as an endless-scroll experience.

Required behavior:

- Force effective `shortsToRegular` while Lite Mode is active.
- Prevent startup from resuming directly into Shorts.
- Remove the Shorts tab from the Lite tab set.
- Remove Shorts shelves from Home and subscriptions feeds.
- If a Shorts view still appears, convert it to regular video playback or strip its overlay as a fallback.

Lite Mode must not overwrite the user's stored `shortsToRegular` value. It should only make the effective behavior active while Lite Mode is on.

## Comments

Comments remain available and reply-capable.

Default state:

- Collapsed under the video.
- A compact row such as `COMMENTS 24`.
- No full comment stream until the user taps.

Expanded state:

- Render inline below the video.
- Use Courier / Courier New.
- Look closer to IRC or terminal logs than social cards.
- Keep author, timestamp, body, replies, reply action, and composer.
- Hide avatars, hearts, votes, badges, sponsor marks, chips, sort chrome, and decorative actions when safe.

This must preserve posting and replying. If a cleanup rule risks breaking reply/composer controls, keep the control.

## Settings

Lite Mode settings behavior should be explicit:

- Lite Mode toggle shows that restart is required.
- Turning Lite Mode on/off offers `Restart Now` and `Later`.
- Existing individual settings remain editable and stored.
- Lite Mode overrides are effective at runtime and should not destructively set every individual preference.
- Settings rows can mention `forced by Lite Mode` later, but that label is not required for the first debloat pass.

## Implementation Units

### Lite Profile Helpers

Add helpers in `Utils/YTAGLiteMode` for:

- Whether Lite Mode is enabled.
- Whether Lite Mode is active for startup behavior.
- Forced true and false preference keys.
- Lite-safe active tabs.
- Lite-safe startup tab.
- Renderer/cell signatures that should be pruned.
- Courier font selection for Lite-owned UI.

### Restart-Gated Toggle

Update the Lite Mode settings switch path so it:

- Persists the new value.
- Applies the default Lite theme when enabling.
- Shows a restart confirmation.
- Avoids live pivot refresh that implies the full mode applied immediately.

### Tab Pruning

Route pivot tab selection through Lite helpers:

- Active tabs become Home, Subscriptions, and You / Library while Lite Mode is active.
- Startup tab becomes Home.
- User's stored `activeTabs` and `startupTab` stay unchanged.

### Feed Pruning

Expand the current Lite feed filters:

- Add stronger renderer/cell signature markers for heavy surfaces.
- Prefer model or renderer-level pruning where current hooks expose mutable renderer arrays.
- Keep collection deletion and zero-size fallback for cells that slip through.
- Preserve settings, sign-in, account, dialog, toast, and comments surfaces.

### Watch Cleanup

Use existing effective bool overrides for watch-page clutter and extend them only where needed.

### Comment Chrome

Keep the current comment preservation fix and extend styling to Courier. Preserve comment entry points and composer/reply controls.

## Verification

Static checks should prove:

- Lite Mode toggle path mentions restart behavior.
- Lite tab helper does not overwrite stored active tabs.
- Lite startup helper returns Home.
- Lite effective prefs force Shorts-to-regular without changing stored `shortsToRegular`.
- Lite comment cleanup preserves comment entry, reply, and composer controls.
- Lite feed pruning includes heavy surfaces such as Shorts, promoted, community, shopping, news, mixes, radio, carousel, and chip clouds.
- Courier is present in the Lite font path.

Build verification:

- `bash scripts/lite_mode_static_check.sh`
- Existing related static checks.
- `make clean package DEBUG=0 FINALPACKAGE=1`

Runtime verification on sideloaded IPA:

- Toggle Lite Mode on and choose Later: setting persists, current session does not claim full live switch.
- Relaunch: Lite startup tab is Home and tab set is reduced.
- Home no longer shows Shorts shelves, promo shelves, community posts, or chip-heavy sections.
- Watch page keeps playback, title, channel, captions, quality, PiP, download, and settings access.
- Shorts opens as regular video or is blocked from endless-scroll mode.
- Comments show collapsed entry and expand with reply ability intact.
- Toggle Lite Mode off, restart, and normal saved tabs/settings return.

## Risks

YouTube feed and renderer names may vary by version. The first implementation should use conservative signature pruning and keep static checks broad enough to catch accidental removal of essential controls.

Fully replacing Home would be cleaner but riskier. The first implementation should deepen startup, tab, renderer, and collection pruning before attempting a custom Home surface.

Aggressive pruning can remove useful controls if markers are too broad. Search, settings access, watch title, channel info, comments entry, composer/reply controls, captions, quality, PiP, and downloads are explicitly essential.
