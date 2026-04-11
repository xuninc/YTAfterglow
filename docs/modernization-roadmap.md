# YouTube Plus Modernization Roadmap

This plan is designed for exactly the goal of **cleaning up old code, pruning dead parts, and adding higher-value features inspired by uYou / legacy YouTube Plus tweaks** while keeping the project maintainable.

## 1) Stabilize before adding features

1. Run `scripts/maintenance_audit.sh` and fix every warning that is clearly valid.
2. Build on a currently supported Theos + SDK stack.
3. Smoke-test core flows:
   - Home feed loading
   - Video playback
   - Download flow
   - Settings load/save
4. Freeze feature work until crash regressions are gone.

## 2) Prune dead / unrepairable code safely

Use this decision rule per module:

- **Keep** if it compiles, works on latest target YouTube build, and has a clear owner.
- **Repair** if the feature is high impact and breakage is isolated.
- **Remove** if it is unstable, blocks releases, or duplicates better maintained functionality.

Recommended removal candidates usually include:

- Deprecated UI hooks tied to old YouTube class names.
- One-off experiments with no settings toggle.
- Duplicate implementations of the same feature path.

## 3) “Better features” to prioritize (uYou/Plus style)

Prioritize features that are visible, stable, and low-maintenance:

1. **Playback QoL**
   - Persistent default quality / playback speed
   - Better gesture controls (brightness/volume/seek)
2. **Content controls**
   - Shorts filtering modes (hide/limited-only tab)
   - Feed element filtering with per-surface toggles
3. **Download UX**
   - Unified queue view with retry / failure reasons
   - Better filename templates and metadata export
4. **Settings reliability**
   - Searchable settings
   - Import/export validation and migration checks

## 4) Compatibility strategy for new YouTube versions

- Introduce a compatibility layer by feature area (player, feed, comments, downloads).
- Guard fragile hooks behind version checks + runtime class existence checks.
- Fail soft: if a hook target is missing, disable only that feature.

## 5) Release gating checklist

Before every release:

- `scripts/maintenance_audit.sh`
- Build/package pass
- Manual smoke test on at least one recent YouTube version
- Update README “Supported YouTube Version” and “Date tested”
- Include a changelog section: Added / Fixed / Removed

## 6) Suggested next concrete steps

1. Add CI job to run the audit script on pull requests.
2. Build a feature inventory markdown table (`feature`, `owner`, `status`, `last validated`).
3. Remove or quarantine modules that have failed for 2+ release cycles.
4. Migrate high-risk hooks to wrappers with defensive runtime checks.
