# YouTube Afterglow

A richly themed, deeply customizable YouTube experience for iOS.

Afterglow layers a full theme engine, gradient backgrounds, gesture controls, ad removal, and granular UI customization on top of YouTube — with 17 curated theme presets, per-element color pickers, and live visual refinement.

---

## Highlights

- **Theme engine** — 17 curated presets split into dark and light variants, plus per-element color control (primary/secondary text, icons, seek bar, backgrounds, navigation, accent).
- **Gradient backgrounds** — assign a top and bottom color and the whole app picks it up automatically.
- **Glow mode** — optional neon-style shadow accent that lights up icons and chrome in Afterglow themes.
- **Custom tab bar** — reorder tabs, swap their icons, choose a startup tab, and strip labels/indicators.
- **Ad & promo blocking** — the full set of opt-in blockers.
- **Player controls** — hold-to-speed, tap-to-seek, configurable speed ramps, default playback rate, background audio.
- **Shorts tools** — shorts-only mode, filter specific UI chrome, re-enable skipped gestures.
- **Download & share** — native share sheet integration and download menu preservation.
- **SponsorBlock** — built-in support.
- **Settings export/import** — carry your exact setup between installs.

Afterglow preferences live inside the YouTube app's own Settings screen.

---

## Project Maintenance

- Run `scripts/maintenance_audit.sh` before releases to catch stale metadata and potential dead modules.
- Run `scripts/scrub_signing_artifacts.sh <path-to-app>` to strip stale code signatures before re-signing.
- Run `scripts/fix_substrate_load_paths.sh <path-to-app>` to normalize Substrate load paths for sideloaded builds.

---

## Building

This project uses Theos + cyan to produce an unsigned IPA that you can re-sign with your own certificate (Feather, AltStore, Sideloadly, etc.).

### From GitHub Actions

1. Fork this repository.
2. Go to **Settings → Actions** on your fork and allow **Read and write permissions**.
3. Provide a direct-download URL to a decrypted YouTube IPA. *(We cannot distribute one due to legal reasons.)*
4. In the **Actions** tab, run the **Create YouTube Afterglow app** workflow:
   - Paste the IPA URL.
   - Pick which bundled tweaks to include.
   - Optionally override the Bundle ID and Display Name.
5. Download the unsigned IPA from the workflow's release artifact.
6. Sign and install it with Feather or any sideloading tool.

### Supported YouTube versions

Tested against recent YouTube releases; older versions may work but are not actively tracked.

---

## Credits

### Project Stewardship

| Role | Name |
| --- | --- |
| Maintainer / Senior Developer | [Corey Hamilton](https://github.com/xuninc) |

### AI Co-Development Team

AI collaborators supporting implementation, review, and release polish.

| Collaborator | Focus |
| --- | --- |
| [Claude Opus 4.6 / 4.7](https://claude.com/claude) | Architecture, implementation, and product polish |
| [OpenAI Codex](https://openai.com/codex) | Code implementation, cleanup, and review support |

---

## Acknowledgements

[YTLite](https://github.com/dayanch96/YTLite) - open-source base, pre-4.0.

---

## Bundled Tweaks

Special thanks to [PoomSmart](https://github.com/PoomSmart) for keeping widely used YouTube tweak repositories open and maintained for everyone.

Open-source tweaks packaged with Afterglow:

| Author | Project(s) |
| --- | --- |
| [PoomSmart](https://github.com/PoomSmart) | [YouPiP](https://github.com/PoomSmart/YouPiP), [YouQuality](https://github.com/PoomSmart/YouQuality), [Return-YouTube-Dislikes](https://github.com/PoomSmart/Return-YouTube-Dislikes), [YTABConfig](https://github.com/PoomSmart/YTABConfig), [YTVideoOverlay](https://github.com/PoomSmart/YTVideoOverlay), [YouGroupSettings](https://github.com/PoomSmart/YouGroupSettings), [YTIcons](https://github.com/PoomSmart/YTIcons), [YouTubeHeader](https://github.com/PoomSmart/YouTubeHeader) |
| [splaser](https://github.com/splaser) | [YTUHD](https://github.com/splaser/YTUHD) |
| [therealFoxster](https://github.com/therealFoxster) | [DontEatMyContent](https://github.com/therealFoxster/DontEatMyContent) |
| [BillyCurtis](https://github.com/BillyCurtis) | [OpenYouTubeSafariExtension](https://github.com/BillyCurtis/OpenYouTubeSafariExtension) |

---

## Libraries

| Author | Project |
| --- | --- |
| [jkhsjdhjs](https://github.com/jkhsjdhjs) | [youtube-native-share](https://github.com/jkhsjdhjs/youtube-native-share) |
| [Tony Million](https://github.com/tonymillion) | [Reachability](https://github.com/tonymillion/Reachability) |

---

## FAQ

- [English FAQ](FAQs/FAQ_EN.md)
