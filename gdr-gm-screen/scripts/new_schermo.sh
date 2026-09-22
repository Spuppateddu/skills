#!/usr/bin/env bash
# new_schermo.sh — create the HTML of a new "schermo del master", or re-inline
# the shared stylesheet into an existing one.
#
#   new_schermo.sh --game "Blades in the Dark" [--screen "Schermo del GM"] \
#                  [--lang it] [--pages 4] -o path/to/blades-schermo.html
#   new_schermo.sh --refresh-css path/to/blades-schermo.html
#
# The stylesheet assets/schermo.css is copied INTO the file (between the
# <style id="schermo-css"> markers), so the HTML is self-contained and renders
# anywhere. --refresh-css replaces that block with the current stylesheet and
# touches nothing else, so a style change can be pushed to every screen.
#
# Needs bash 3.2+ and python3. Never overwrites an existing file unless --force.

set -euo pipefail
SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SKILL_DIR=$(dirname "$SELF_DIR")
CSS="$SKILL_DIR/assets/schermo.css"
TPL="$SKILL_DIR/templates/schermo-template.html"
PTPL="$SKILL_DIR/templates/page-template.html"

die() { printf 'new_schermo: %s\n' "$1" >&2; exit 1; }
usage() { sed -n '2,15p' "$0"; exit 0; }

GAME=""; SCREEN="Schermo del GM"; LANG_CODE="it"; PAGES=4; OUT=""; REFRESH=""; FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --game)    GAME=${2:-}; shift 2 ;;
    --screen)  SCREEN=${2:-}; shift 2 ;;
    --lang)    LANG_CODE=${2:-}; shift 2 ;;
    --pages)   PAGES=${2:-}; shift 2 ;;
    --refresh-css) REFRESH=${2:-}; shift 2 ;;
    --force)   FORCE=1; shift ;;
    -o)        OUT=${2:-}; shift 2 ;;
    -h|--help) usage ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -f "$CSS" ] || die "stylesheet not found: $CSS"

if [ -n "$REFRESH" ]; then
  [ -f "$REFRESH" ] || die "no such file: $REFRESH"
  python3 - "$REFRESH" "$CSS" <<'PY'
import re, sys
path, css = sys.argv[1], sys.argv[2]
html = open(path, encoding="utf-8").read()
style = open(css, encoding="utf-8").read().rstrip("\n")
new, n = re.subn(r'(<style id="schermo-css">\n).*?(\n</style>)',
                 lambda m: m.group(1) + style + m.group(2), html, count=1, flags=re.S)
if n != 1:
    sys.exit("new_schermo: no <style id=\"schermo-css\"> block in " + path)
open(path, "w", encoding="utf-8").write(new)
print("refreshed stylesheet in", path)
PY
  exit 0
fi

[ -n "$GAME" ] || die "--game is required (the game's title, as printed in the footer)"
[ -n "$OUT" ] || die "-o is required (e.g. -o Ronin/ronin-schermo.html)"
case "$PAGES" in ''|*[!0-9]*) die "--pages must be a number" ;; esac
if [ -e "$OUT" ] && [ "$FORCE" != 1 ]; then
  die "$OUT exists — edit it, or pass --force to overwrite"
fi

python3 - "$TPL" "$PTPL" "$CSS" "$OUT" "$GAME" "$SCREEN" "$LANG_CODE" "$PAGES" <<'PY'
import sys, html as H
tpl, ptpl, css, out, game, screen, lang, pages = sys.argv[1:9]
pages = int(pages)
T = open(tpl, encoding="utf-8").read()
P = open(ptpl, encoding="utf-8").read()
style = open(css, encoding="utf-8").read().rstrip("\n")
g, s = H.escape(game, quote=False), H.escape(screen, quote=False)
blocks = []
for n in range(1, pages + 1):
    blocks.append(P.replace("{{N}}", str(n)).replace("{{TOTAL}}", str(pages))
                   .replace("{{GAME}}", g).replace("{{SCREEN}}", s)
                   .replace("{{TITLE}}", f"Titolo pagina {n}")
                   .replace("{{SUB}}", "argomento · argomento · argomento"))
doc = (T.replace("{{LANG}}", lang).replace("{{GAME}}", g).replace("{{SCREEN}}", s)
        .replace("{{CSS}}", style).replace("{{PAGES}}", "\n".join(blocks)))
open(out, "w", encoding="utf-8").write(doc)
print(f"created {out} ({pages} pages) — fill the pages, then render with render_schermo.sh")
PY
