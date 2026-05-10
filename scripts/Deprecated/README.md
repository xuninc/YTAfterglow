# Deprecated Scripts

This folder keeps retired maintenance scripts for reference only.

These scripts are not part of the normal YTAfterglow build or IPA packaging
pipeline. In particular, Cyan is expected to handle the normal packaging case,
and generic post-Cyan file removal should not be added back to CI or local build
steps without a new, verified signing problem that specifically requires it.

Keep this folder so we can recover old tooling if a future packaging issue
turns out to need it, but treat anything here as manual, last-resort tooling.
