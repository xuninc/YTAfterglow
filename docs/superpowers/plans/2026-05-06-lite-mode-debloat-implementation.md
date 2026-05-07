# Lite Mode Debloat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Lite Mode into a restart-gated startup debloat profile with Courier-styled Lite surfaces and stronger feed/tab pruning.

**Architecture:** Add focused helpers to `Utils/YTAGLiteMode` for effective tabs, startup tab, feed pruning, and Courier fonts. Wire those helpers into settings, pivot startup/tab filtering, feed/cell pruning, and comment styling while keeping stored user preferences unchanged.

**Tech Stack:** Objective-C/Logos, Theos, Cyan, static shell checks.

---

### Task 1: Static Regression Coverage

**Files:**
- Modify: `scripts/lite_mode_static_check.sh`

- [ ] Add checks requiring `YTAGLiteModeActiveTabs`, `YTAGLiteModeStartupTab`, `YTAGLiteModeShouldPruneFeedObject`, `YTAGLiteModeFont`, `CourierNewPSMT`, restart prompt text, and feed markers for `community`, `shopping`, `breakingnews`, `mixplaylist`, `radio`, `chipcloud`, and `filterchip`.
- [ ] Run `bash scripts/lite_mode_static_check.sh` and confirm it fails before production code changes.

### Task 2: Lite Profile Helpers

**Files:**
- Modify: `Utils/YTAGLiteMode.h`
- Modify: `Utils/YTAGLiteMode.m`

- [ ] Add exported helper declarations.
- [ ] Implement Lite active tabs as `FEwhat_to_watch`, `FEsubscriptions`, `FElibrary`.
- [ ] Implement Lite startup tab as `FEwhat_to_watch`.
- [ ] Add feed pruning helpers that inspect descriptions, identifiers, labels, and common KVC renderer names.
- [ ] Add `YTAGLiteModeFont` using `CourierNewPSMT`, then `Courier`, then monospaced system fallback.
- [ ] Add `YTAGLiteModeStyleLabel` for Courier label styling.
- [ ] Update effective forced keys so Lite keeps search/download essentials and disables Shorts-only startup while forcing Shorts-to-regular.
- [ ] Run `bash scripts/lite_mode_static_check.sh` and confirm it passes this task's helper checks.

### Task 3: Restart-Gated Lite Toggle

**Files:**
- Modify: `Settings.x`

- [ ] Add `ytag_presentLiteModeRestartAlert(YTSettingsCell *cell, BOOL enabled)`.
- [ ] Change the Lite Mode switch path to persist the value, clear theme cache, refresh settings, and show `Restart Now` / `Later`.
- [ ] Remove the live pivot refresh from the Lite Mode switch path so it does not imply full live application.
- [ ] Run `bash scripts/lite_mode_static_check.sh`.

### Task 4: Startup Tabs And Feed Pruning

**Files:**
- Modify: `YTAfterglow.x`

- [ ] Use `YTAGLiteModeActiveTabs()` inside `YTPivotBarView.setRenderer:` when Lite Mode is active.
- [ ] Use `YTAGLiteModeStartupTab()` inside `YTPivotBarViewController.viewDidAppear:`.
- [ ] Prevent the Shorts-only startup branch from running while Lite Mode is active.
- [ ] Call `YTAGLiteModeShouldPruneFeedObject` in `YTIElementRenderer.elementData`, `YTSectionListViewController.loadWithModel:`, `ASCollectionView.sizeForElement:`, and `YTAsyncCollectionView.cellForItemAtIndexPath:`.
- [ ] Run `bash scripts/lite_mode_static_check.sh`.

### Task 5: Courier Comments

**Files:**
- Modify: `Utils/YTAGLiteMode.m`

- [ ] Update Lite comment labels to use `YTAGLiteModeStyleLabel`.
- [ ] Preserve comment entry, composer, and reply controls.
- [ ] Run `bash scripts/lite_mode_static_check.sh`.

### Task 6: Build And IPA

**Files:**
- Build metadata under `/home/corey/ytafterglow-build/builds/011_2026-05-06_yt21.17.3_lite-debloat-courier/`

- [ ] Run `bash scripts/failsafe_settings_static_check.sh`.
- [ ] Run `bash scripts/lite_mode_static_check.sh`.
- [ ] Run `bash scripts/seekbar_glow_static_check.sh`.
- [ ] Run `make clean package DEBUG=0 FINALPACKAGE=1`.
- [ ] Create numbered build folder `011_2026-05-06_yt21.17.3_lite-debloat-courier`.
- [ ] Run Cyan with the full tweak set, bundle id `i.am.kain.afterglow`, and app name `YouTube AG`.
- [ ] Inspect the IPA for identity, dylibs, frameworks, and marker strings.
