# Frameworks/

Drop-in location for third-party binary dependencies that Theos links against and
cyan embeds into the final IPA's `Payload/YouTube.app/Frameworks/`.

Nothing in this directory is checked into git except this README — the xcframeworks
are large (40 MB – 500 MB+) and properly belong in release assets rather than source
control. `.gitignore` is set to ignore `Frameworks/*.xcframework/`.

---

## ffmpeg-kit (required for HQ download manager mux)

`Utils/FFMpegHelper.m` calls into ffmpeg-kit for the audio/video mux step of the
HQ download pipeline. The build auto-fetches the xcframeworks via
`scripts/fetch-ffmpegkit.sh`; if that fetch fails, the package should fail loudly
instead of shipping a download button whose mux path crashes at runtime.

### 1. Status of upstream

`arthenica/ffmpeg-kit` **was archived by the maintainer in early 2025** (repo is
read-only; last push 2025-06-23). The final native iOS release is
**`v6.0.LTS`** (2023-09-18, tag
`https://github.com/arthenica/ffmpeg-kit/releases/tag/v6.0.LTS`).

Because the project is archived, release assets are no longer hosted on GitHub
Releases directly. Download links are now surfaced via the project homepage:

- Homepage: https://arthenica.github.io/ffmpeg-kit
- Releases page (tags only, no binaries since archive): https://github.com/arthenica/ffmpeg-kit/releases
- iOS binary archive: follow "iOS" on the homepage to the current hosted zip bundle
  (CDN / mirror). Afterglow currently fetches a pinned community mirror of the
  v6.0 full iOS bundle because the original release assets are no longer hosted
  directly on GitHub.

If the homepage link has rotted, community mirrors of v6.0.LTS are easy to find;
any SHA-verified copy of `ffmpeg-kit-ios-min-6.0.LTS.zip` from a reputable
mirror will do. We are pinning to this specific snapshot because it's the last
blessed release before archive.

### 2. Which variant to download

ffmpeg-kit ships several iOS variants at each release. For manual installs,
`min` is sufficient for our mux/transcode needs, but the current automated fetch
uses the available pinned `ios-full` mirror and copies its runtime framework set:

| Variant       | Size    | Contents                                           | Our use? |
| ------------- | ------- | -------------------------------------------------- | -------- |
| `min`         | ~40 MB  | Core ffmpeg + `-c copy` mux + jpg/png              | ✓ YES    |
| `min-gpl`     | ~45 MB  | `min` + x264 + x265                                | overkill |
| `https`       | ~45 MB  | `min` + HTTPS input support                        | no       |
| `audio`       | ~75 MB  | audio codec stack                                  | no       |
| `video`       | ~120 MB | `min` + x264/x265/VP9/libvpx                       | no       |
| `full`        | ~180 MB | everything                                         | no       |
| `full-gpl`    | ~200 MB | everything + GPL codecs                            | no       |

Our call sites only need:
- `-c:v copy -c:a copy` remux (no codec work, container-only)
- webp → jpg thumbnail transcode (needs `libwebp` and `mjpeg`, both in `min`)

So `min` is sufficient if you are installing manually. If a future feature needs
more codecs, keep using the broader automated bundle or update the fetch script.

### 3. Drop-in procedure

```bash
# From the project root, usually this is enough:
bash scripts/fetch-ffmpegkit.sh

# For manual drop-in with a zip already downloaded:
cd /home/corey/repos/xuninc/YTAfterglow/Frameworks/

# Unzip; the archive must contain ffmpegkit.xcframework and its sibling libav*.xcframeworks.
unzip -q ~/Downloads/ffmpeg-kit-ios-min-6.0.LTS.zip

# You should now have:
#   Frameworks/ffmpegkit.xcframework/
#   Frameworks/libavcodec.xcframework/
#   Frameworks/libavformat.xcframework/
#   Frameworks/libavutil.xcframework/
#   Frameworks/libavdevice.xcframework/
#   Frameworks/libavfilter.xcframework/
#   Frameworks/libswresample.xcframework/
#   Frameworks/libswscale.xcframework/
#   Frameworks/ffmpegkit.xcframework/Info.plist
#   Frameworks/ffmpegkit.xcframework/ios-arm64/
#   Frameworks/ffmpegkit.xcframework/ios-arm64/ffmpegkit.framework/
#   Frameworks/ffmpegkit.xcframework/ios-arm64_x86_64-simulator/ ...
ls Frameworks/ffmpegkit.xcframework/
```

Expected final path: `Frameworks/ffmpegkit.xcframework/`
Makefile condition: `scripts/fetch-ffmpegkit.sh` creates this path before compile.

### 4. Verify

The xcframework is correctly placed if **all** of these succeed:

```bash
# 1. Info.plist exists and lists iOS platforms.
plutil -p Frameworks/ffmpegkit.xcframework/Info.plist 2>/dev/null | grep -E '(SupportedPlatform|LibraryIdentifier)'
# Expected output includes: "ios", "ios-arm64", and possibly "ios-arm64_x86_64-simulator".

# 2. The arm64 device slice has the .framework bundle with Mach-O binary and headers.
ls Frameworks/ffmpegkit.xcframework/ios-arm64/ffmpegkit.framework/
# Expected files: Headers/  Info.plist  ffmpegkit (Mach-O binary)

# 3. The umbrella header exists.
ls Frameworks/ffmpegkit.xcframework/ios-arm64/ffmpegkit.framework/Headers/FFmpegKit.h
```

If `plutil` is unavailable (Linux), `file` and `ls` are enough:

```bash
file Frameworks/ffmpegkit.xcframework/ios-arm64/ffmpegkit.framework/ffmpegkit
# Expected: Mach-O 64-bit dynamically linked shared library arm64
```

### 5. Linux-Theos build notes

Theos on Linux (via L1ghtmann's toolchain) doesn't fully understand xcframeworks
the way Xcode does. The Makefile works around this by passing **both** search
paths explicitly:

```make
$(TWEAK_NAME)_LDFLAGS += -F$(PWD)/Frameworks \
                          -F$(FFMPEGKIT_XCFRAMEWORK)/ios-arm64 \
                          -framework ffmpegkit
```

The direct `-F` points the linker at the arm64 `.framework` slice so it can
resolve symbols. The Makefile then manually stages the required runtime
frameworks into the package under `/Library/Frameworks/` and normalizes rpaths
for both jailbreak and sideloaded IPA layouts.

If the link step fails with `library not found for -lffmpegkit` on Linux, verify
that `Frameworks/ffmpegkit.xcframework/ios-arm64/ffmpegkit.framework/ffmpegkit`
is a real Mach-O arm64 binary (see step 4 above) and not a symlink or
placeholder.

### 6. Commit (if/when we decide to vendor)

By default the xcframework is gitignored. If we ever want to vendor it (e.g.
to make GitHub Actions builds self-contained without a cache download step),
remove the pattern from `.gitignore` and:

```bash
cd /home/corey/repos/xuninc/YTAfterglow/
git add -f Frameworks/ffmpegkit.xcframework/
git commit -m "vendor: ffmpeg-kit v6.0.LTS ios-min xcframework

Pinned snapshot — upstream arthenica/ffmpeg-kit was archived early 2025.
~40 MB; needed for HQ download manager mux in Utils/FFMpegHelper.m."
```

Recommended alternative: host the xcframework as a release asset on the
YTAfterglow repo and fetch it in CI via a cache-keyed `actions/cache` step.
That keeps the git history clean.
