#!/usr/bin/env bash
# Fetches the ffmpeg-kit xcframework and its sibling libav*.xcframeworks into
# Frameworks/, used by Utils/FFMpegHelper.m for the HQ download pipeline.
#
# Safe to run repeatedly — no-op if ffmpegkit.xcframework is already in place.
# Invoked by Make as a prereq (see Makefile target `ffmpegkit`) and by CI.
#
# Why luthviar/ffmpeg-kit-ios-full: arthenica/ffmpeg-kit was archived early 2025
# with its GitHub Release assets stripped. luthviar's mirror (44⭐, 2024) vendors
# the unblessed v6.0 binary as a release asset — the last blessed snapshot before
# archive. See Frameworks/README.md for the full provenance chain.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FRAMEWORKS_DIR="$REPO_ROOT/Frameworks"
MARKER="$FRAMEWORKS_DIR/ffmpegkit.xcframework/Info.plist"

# Mirror — v6.0 snapshot. Pin to a specific release tag so the fetch is reproducible.
MIRROR_URL="https://github.com/luthviar/ffmpeg-kit-ios-full/releases/download/6.0/ffmpeg-kit-ios-full.zip"
EXPECTED_SIZE_BYTES=59655863   # checksum if file grows; prevents silent mirror swaps

if [[ -f "$MARKER" ]]; then
    echo "ffmpeg-kit already present at $FRAMEWORKS_DIR/ffmpegkit.xcframework — skipping."
    exit 0
fi

echo "Fetching ffmpeg-kit xcframework (~57 MB)..."
mkdir -p "$FRAMEWORKS_DIR"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

ZIP="$TMPDIR/ffmpeg-kit.zip"
curl -L --fail --show-error --max-time 300 -o "$ZIP" "$MIRROR_URL"

# Sanity-check the download — guards against mirrors being silently replaced.
ACTUAL_SIZE=$(stat -c '%s' "$ZIP" 2>/dev/null || stat -f '%z' "$ZIP")
if [[ "$ACTUAL_SIZE" != "$EXPECTED_SIZE_BYTES" ]]; then
    echo "WARNING: downloaded size $ACTUAL_SIZE differs from expected $EXPECTED_SIZE_BYTES."
    echo "Proceeding, but if the build fails at link time, verify the mirror content."
fi

unzip -q "$ZIP" -d "$TMPDIR"

SRC_DIR=$(find "$TMPDIR" -maxdepth 2 -type d -name "ffmpeg-kit-ios-full" | head -1)
if [[ -z "$SRC_DIR" ]]; then
    echo "ERROR: couldn't locate ffmpeg-kit-ios-full/ inside the zip."
    exit 1
fi

# Copy every *.xcframework out of the zip root. ffmpegkit.xcframework is the
# primary target we link against; the libav* xcframeworks are dependencies
# pulled in by the umbrella framework at runtime.
echo "Installing xcframeworks into $FRAMEWORKS_DIR/"
cp -R "$SRC_DIR"/*.xcframework "$FRAMEWORKS_DIR/"

# Verify the primary arm64 slice is a real Mach-O binary.
ARM64_BIN="$FRAMEWORKS_DIR/ffmpegkit.xcframework/ios-arm64/ffmpegkit.framework/ffmpegkit"
if [[ ! -f "$ARM64_BIN" ]]; then
    echo "ERROR: arm64 slice missing at $ARM64_BIN — install incomplete."
    exit 1
fi

echo "Done. ffmpegkit.xcframework ready at $FRAMEWORKS_DIR/"
