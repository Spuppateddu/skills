#!/usr/bin/env bash
# Render PDF pages to PNG so you can look at them with the Read tool.
#   bash render_pages.sh FILE.pdf OUT_PREFIX [DPI] [PAGES]
# e.g. bash render_pages.sh schede/1_holtz.pdf /tmp/x/holtz 110 1      -> /tmp/x/holtz_1.png
set -euo pipefail
pdf="$1"; out="$2"; dpi="${3:-110}"; pages="${4:-}"
mkdir -p "$(dirname "$out")"
if [ -n "$pages" ]; then mutool draw -r "$dpi" -o "${out}_%d.png" "$pdf" "$pages"
else mutool draw -r "$dpi" -o "${out}_%d.png" "$pdf"; fi 2>/dev/null
ls "${out}"_*.png
