#!/usr/bin/env bash
# render_schermo.sh — render a "schermo del master" HTML to PDF and check it.
#
#   render_schermo.sh <schermo.html> [out.pdf] [--png DIR] [--dpi 70] [--no-check]
#
# 1. Prints the HTML with the Chromium already on the machine (Chrome, Chromium,
#    Brave, Edge). Nothing is installed. On Linux it uses a clean fontconfig so a
#    user-level font alias (e.g. "everything → a monospace font") cannot leak
#    into the PDF; the layout always resolves to Liberation Serif/Sans.
# 2. Checks that the PDF has exactly one page per <div class="page">.
# 3. Measures every page in the browser and prints, per page, the free space
#    above the footer and how much shorter each column is than its tallest
#    sibling — the numbers you need to balance the layout. Overflow (content
#    pushed past the page's bottom edge) fails the run.
# 4. With --png DIR, also renders each page to DIR/page-N.png for a look.
#
# Exit status: 0 fine, 2 overflow or page-count mismatch, 1 other error.
# Portable bash 3.2 — Linux and macOS.

set -euo pipefail
die() { printf 'render_schermo: %s\n' "$1" >&2; exit 1; }

IN=""; OUT=""; PNG=""; DPI=70; CHECK=1
while [ $# -gt 0 ]; do
  case "$1" in
    --png) PNG=${2:-}; shift 2 ;;
    --dpi) DPI=${2:-}; shift 2 ;;
    --no-check) CHECK=0; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) if [ -z "$IN" ]; then IN=$1; else OUT=$1; fi; shift ;;
  esac
done
[ -n "$IN" ] || die "usage: render_schermo.sh <schermo.html> [out.pdf] [--png DIR]"
[ -f "$IN" ] || die "no such file: $IN"

IN_DIR=$(CDPATH= cd -- "$(dirname -- "$IN")" && pwd)
IN_ABS="$IN_DIR/$(basename -- "$IN")"
[ -n "$OUT" ] || OUT="${IN_ABS%.html}.pdf"
case "$OUT" in /*) ;; *) OUT="$(CDPATH= cd -- "$(dirname -- "$OUT")" && pwd)/$(basename -- "$OUT")" ;; esac

# --- find a Chromium -------------------------------------------------------
find_chrome() {
  # Real binaries first: the names on PATH (google-chrome, brave-browser…) are
  # often shell wrappers, and a time limit that kills the wrapper leaves the
  # browser itself running and holding the profile — every later run then hangs.
  for c in /opt/google/chrome/chrome /opt/brave.com/brave/brave /opt/microsoft/msedge/msedge \
           /usr/lib/chromium/chromium /usr/lib/chromium-browser/chromium-browser \
           /snap/chromium/current/usr/lib/chromium-browser/chrome \
           "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
           "/Applications/Chromium.app/Contents/MacOS/Chromium" \
           "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" \
           "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"; do
    if [ -x "$c" ]; then printf '%s' "$c"; return 0; fi
  done
  for c in chromium chromium-browser google-chrome google-chrome-stable chrome \
           brave-browser brave microsoft-edge; do
    if command -v "$c" >/dev/null 2>&1; then command -v "$c"; return 0; fi
  done
  return 1
}
CHROME=${SCHERMO_CHROME:-$(find_chrome || true)}
[ -n "$CHROME" ] || die "no Chrome/Chromium/Brave found. Install one, or set SCHERMO_CHROME=/path/to/binary"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/schermo.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# --- clean fontconfig (Linux only) ----------------------------------------
FC_ENV=""
if [ "$(uname)" = "Linux" ] && [ -d /usr/share/fonts ]; then
  cat > "$TMP/fonts.conf" <<FC
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <dir>/usr/share/fonts</dir>
  <dir>/usr/local/share/fonts</dir>
  <cachedir>$TMP/fc-cache</cachedir>
  <alias><family>serif</family><prefer><family>Liberation Serif</family></prefer></alias>
  <alias><family>sans-serif</family><prefer><family>Liberation Sans</family></prefer></alias>
</fontconfig>
FC
  FC_ENV="$TMP/fonts.conf"
fi

SANDBOX=""
[ "$(id -u)" = "0" ] && SANDBOX="--no-sandbox"

# --- a persistent browser profile ------------------------------------------
# Brave (and Chrome) hang on the very first headless run with a brand-new
# profile: they spend it downloading components and never get to the page.
# Once a profile exists, every run takes about a second. So the profile lives
# in the cache dir and is warmed up once, with a time limit. Override with
# SCHERMO_PROFILE=/path if you want it elsewhere. Runs are sequential: two
# renders at the same time would fight over the profile lock.
PROFILE=${SCHERMO_PROFILE:-${XDG_CACHE_HOME:-$HOME/.cache}/gdr-gm-screen/profile}
mkdir -p "$PROFILE"

# A tiny wrapper script, so that the time limit below can run it (timeout/perl
# need a real program, not a shell function).
{
  printf '#!/bin/sh\n'
  [ -n "$FC_ENV" ] && printf 'FONTCONFIG_FILE=%s; export FONTCONFIG_FILE\n' "$FC_ENV"
  printf 'exec "%s" --headless --disable-gpu %s --no-first-run --user-data-dir="%s" "$@"\n' "$CHROME" "$SANDBOX" "$PROFILE"
} > "$TMP/chrome.sh"
chmod +x "$TMP/chrome.sh"

# run the wrapper with a time limit: coreutils timeout, gtimeout (brew), or perl
run_limited() {
  secs=$1; shift
  rc=0
  if command -v timeout >/dev/null 2>&1; then timeout "$secs" "$TMP/chrome.sh" "$@" || rc=$?
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$secs" "$TMP/chrome.sh" "$@" || rc=$?
  else perl -e 'alarm shift; exec @ARGV' "$secs" "$TMP/chrome.sh" "$@" || rc=$?
  fi
  # whatever happened, no browser process may keep our profile open
  pkill -f -- "--user-data-dir=$PROFILE" >/dev/null 2>&1 || true
  return $rc
}
# --run-all-compositor-stages-before-draw + --virtual-time-budget are required:
# without them Brave's headless --print-to-pdf never returns.
run_chrome() {
  run_limited 90 --run-all-compositor-stages-before-draw --virtual-time-budget=10000 "$@"
}
probe_profile() {
  # print a real (tiny) local page: about:blank never finishes under a virtual-time budget
  rm -f "$TMP/probe.pdf"
  printf '<!DOCTYPE html><html><body><p>probe</p></body></html>\n' > "$TMP/probe.html"
  run_limited 20 --run-all-compositor-stages-before-draw --virtual-time-budget=10000 \
    --no-pdf-header-footer --print-to-pdf="$TMP/probe.pdf" "file://$TMP/probe.html" >/dev/null 2>&1 || true
  [ -s "$TMP/probe.pdf" ]
}
ensure_profile() {
  [ -f "$PROFILE/.schermo-ready" ] && return 0
  n=0
  while [ $n -lt 2 ]; do
    n=$((n + 1))
    printf 'render_schermo: first run — preparing the browser profile in %s (up to 45 s, only once)\n' "$PROFILE" >&2
    run_limited 45 --dump-dom about:blank >/dev/null 2>&1 || true
    if probe_profile; then touch "$PROFILE/.schermo-ready"; return 0; fi
  done
  die "the browser never finished its first run. Try again, or delete $PROFILE"
}
ensure_profile

# --- 1. print ---------------------------------------------------------------
run_chrome --no-pdf-header-footer --print-to-pdf="$OUT" "file://$IN_ABS" >/dev/null 2>&1 || true
[ -s "$OUT" ] || die "Chromium produced no PDF ($CHROME)"

PAGES_HTML=$(grep -c '<div class="page"' "$IN_ABS" || true)
PAGES_PDF=""
command -v pdfinfo >/dev/null 2>&1 && PAGES_PDF=$(pdfinfo "$OUT" 2>/dev/null | awk '/^Pages:/{print $2}')
printf '%s  (%s pages, expected %s)\n' "$OUT" "${PAGES_PDF:-?}" "$PAGES_HTML"

STATUS=0
if [ -n "$PAGES_PDF" ] && [ "$PAGES_PDF" != "$PAGES_HTML" ]; then
  printf 'render_schermo: PAGE COUNT MISMATCH — something overflows or a page is missing\n' >&2
  STATUS=2
fi

# --- 2. measure -------------------------------------------------------------
if [ "$CHECK" = 1 ]; then
  cat > "$TMP/measure.js" <<'JS'
(function () {
  var mm = function (px) { return Math.round(px / 96 * 25.4 * 10) / 10; };
  var out = [];
  var pages = document.querySelectorAll('.page');
  for (var i = 0; i < pages.length; i++) {
    var pg = pages[i], pr = pg.getBoundingClientRect();
    var foot = pg.querySelector('.foot');
    var bottom = pr.top, kids = pg.children;
    for (var k = 0; k < kids.length; k++) {
      if (kids[k] === foot) continue;
      var r = kids[k].getBoundingClientRect();
      if (r.bottom > bottom) bottom = r.bottom;
    }
    var footTop = foot ? foot.getBoundingClientRect().top : pr.bottom;
    var over = pg.scrollHeight - pg.clientHeight;
    var cols = [];
    var groups = pg.querySelectorAll('.cols');
    for (var g = 0; g < groups.length; g++) {
      var cs = groups[g].children, hs = [];
      for (var c = 0; c < cs.length; c++) {
        var col = cs[c], last = col.lastElementChild;
        hs.push(last ? last.getBoundingClientRect().bottom - col.getBoundingClientRect().top : 0);
      }
      var max = Math.max.apply(null, hs);
      cols.push(hs.map(function (h) { return mm(max - h); }));
    }
    var sub = pg.querySelector('.head .sub'), h2s = [], hh = pg.querySelectorAll('h2, h3, .box .bt, th');
    for (var q = 0; q < hh.length; q++) h2s.push(hh[q].textContent);
    out.push({ page: i + 1, free: mm(footTop - bottom), over: mm(over), cols: cols,
               sub: sub ? sub.textContent : '', h2s: h2s });
  }
  document.title = 'SCHERMO_MEASURE ' + JSON.stringify(out);
})();
JS
  # inject the script into a copy of the file, next to the original so relative links keep working
  PROBE="$IN_DIR/.schermo-probe-$$.html"
  { sed '$!b; s#</body>#PROBE_SCRIPT</body>#' "$IN_ABS"; } > "$PROBE"
  if ! grep -q PROBE_SCRIPT "$PROBE"; then
    # </body> was not on the last line: append the script instead
    cp "$IN_ABS" "$PROBE"; printf '<script>\n%s\n</script>\n' "$(cat "$TMP/measure.js")" >> "$PROBE"
  else
    python3 - "$PROBE" "$TMP/measure.js" <<'PY'
import sys
p, js = sys.argv[1], open(sys.argv[2], encoding="utf-8").read()
h = open(p, encoding="utf-8").read().replace("PROBE_SCRIPT", "<script>\n" + js + "\n</script>")
open(p, "w", encoding="utf-8").write(h)
PY
  fi
  trap 'rm -rf "$TMP" "$PROBE"' EXIT
  DOM=$(run_chrome --dump-dom "file://$PROBE" 2>/dev/null || true)
  rm -f "$PROBE"
  JSON=$(printf '%s' "$DOM" | tr -d '\n' | sed -n 's#.*<title>SCHERMO_MEASURE \(.*\)</title>.*#\1#p' | sed 's/&quot;/"/g')
  if [ -z "$JSON" ]; then
    printf 'render_schermo: could not measure the pages (no DOM dump)\n' >&2
  else
    printf '%s' "$JSON" | python3 -c '
import json, sys
import re, unicodedata
data = json.load(sys.stdin)
bad = False
def norm(t):
    t = unicodedata.normalize("NFKD", t).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", " ", t).strip()
for p in data:
    cols = "  ".join("[" + " / ".join(("%.1f" % h) for h in g) + "]" for g in p["cols"])
    if p["over"] > 0.3:
        print("page %d: OVERFLOW by %.1fmm   cols short by mm: %s" % (p["page"], p["over"], cols)); bad = True
    else:
        note = "  <- a lot of free space" if p["free"] > 25 else ("  (full, ok)" if p["free"] < 0.5 else "")
        print("page %d: free %.1fmm above the footer   cols short by mm: %s%s" % (p["page"], p["free"], cols, note))
    # the .sub line should index the page: warn on items that match no h2, h3, box title or table header
    items = [norm(x) for x in p["sub"].split("\u00b7") if norm(x)]
    h2s = [norm(x) for x in p["h2s"]]
    lost = [x for x in items if not any(x in h or h in x or x.split()[0] in h for h in h2s)]
    if lost:
        print("   sub-line items that match no h2/h3/box title on this page: " + " · ".join(lost))
print("cols: per .cols group, how much shorter each column is than the tallest (0 = tallest); a 2nd bracket = a 2nd .cols block.")
sys.exit(2 if bad else 0)
' || STATUS=2
  fi
fi

# --- 3. previews --------------------------------------------------------------
if [ -n "$PNG" ]; then
  command -v pdftoppm >/dev/null 2>&1 || die "pdftoppm not found (poppler-utils) — needed for --png"
  mkdir -p "$PNG"
  pdftoppm -r "$DPI" -png "$OUT" "$PNG/page"
  printf 'previews: %s/page-*.png\n' "$PNG"
fi

exit $STATUS
