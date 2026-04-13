#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "== YTAfterglow maintenance audit =="

if ! command -v rg >/dev/null 2>&1; then
  echo "[ERROR] ripgrep (rg) is required." >&2
  exit 1
fi

x_files=$(rg --files -g '*.x' | wc -l | tr -d ' ')
objc_files=$(rg --files -g '*.m' -g '*.h' | wc -l | tr -d ' ')
echo "[INFO] Logos files: $x_files"
echo "[INFO] Objective-C files: $objc_files"

echo
echo "-- Potentially dead utility files --"
dead_found=0
while IFS= read -r file; do
  base="$(basename "$file")"
  refs=$( (rg -n --fixed-strings "$base" --glob "*.x" --glob "*.m" --glob "*.h" . || true) | wc -l | tr -d " " )
  if rg -n --fixed-strings "$base" "$file" >/dev/null 2>&1; then
    refs=$((refs - 1))
  fi
  if [ "$refs" -le 0 ]; then
    dead_found=1
    echo "[WARN] No references to $file"
  fi
done < <(rg --files Utils -g '*.m' || true)

if [ "$dead_found" -eq 0 ]; then
  echo "[OK] Every Utils/*.m file has at least one textual reference."
fi

echo
echo "-- Possibly stale preference keys --"
rg -o 'kYTAG[^] ;]+' --glob '*.x' --glob '*.m' --glob '*.h' | \
  sed 's/:.*//' | sort | uniq -c | awk '$1==1 {print "[WARN] key appears once:", $2}' || true

if [ -f README.md ]; then
  echo
  echo "-- README support metadata --"
  python3 - <<'PY'
import datetime as dt
import re
from pathlib import Path

readme = Path("README.md").read_text(encoding="utf-8", errors="ignore")
m = re.search(r"Date tested:</strong>\s*<em>([^<]+)</em>", readme)
if not m:
    print("[WARN] Could not find 'Date tested' field in README.md")
    raise SystemExit(0)

date_str = m.group(1).strip()
formats = ["%b %d, %Y", "%B %d, %Y", "%Y-%m-%d"]
parsed = None
for fmt in formats:
    try:
        parsed = dt.datetime.strptime(date_str, fmt).date()
        break
    except ValueError:
        pass
if not parsed:
    print(f"[WARN] Unrecognized README date format: {date_str}")
    raise SystemExit(0)

age = (dt.date.today() - parsed).days
print(f"[INFO] README tested date: {parsed.isoformat()} ({age} days old)")
if age > 120:
    print("[WARN] README compatibility metadata is older than 120 days; validate against latest YouTube build.")
else:
    print("[OK] README compatibility metadata appears reasonably fresh.")
PY
fi

echo
echo "Audit complete."
