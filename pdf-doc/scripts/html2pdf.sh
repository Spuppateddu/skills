#!/usr/bin/env bash
# html2pdf.sh — render a pdf-doc HTML file to PDF.
#
# Installs nothing: it uses a Chrome/Chromium that is almost certainly already
# on the machine, falling back to WeasyPrint or wkhtmltopdf if one is present.
# The table of contents is rebuilt from the document's own headings first, so
# editing the HTML and re-running this script is the whole update loop.
#
# Usage: html2pdf.sh <file.html> [out.pdf] [--engine chrome|weasyprint|wkhtmltopdf]
#
# Portable bash 3.2 — works on Linux and macOS.

set -euo pipefail

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

die() { printf 'html2pdf: %s\n' "$1" >&2; exit 1; }

IN=""
OUT=""
ENGINE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --engine) ENGINE=${2:-}; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) if [ -z "$IN" ]; then IN=$1; else OUT=$1; fi; shift ;;
  esac
done

[ -n "$IN" ] || die "usage: html2pdf.sh <file.html> [out.pdf]"
[ -f "$IN" ] || die "no such file: $IN"

# Absolute paths: browsers resolve relative to their own working directory.
IN_DIR=$(CDPATH= cd -- "$(dirname -- "$IN")" && pwd)
IN_ABS="$IN_DIR/$(basename -- "$IN")"
[ -n "$OUT" ] || OUT="${IN_ABS%.html}.pdf"
case "$OUT" in
  /*) ;;
  *) OUT="$(CDPATH= cd -- "$(dirname -- "$OUT")" && pwd)/$(basename -- "$OUT")" ;;
esac

# --- keep the TOC in sync with the headings --------------------------------

if [ -x "$SELF_DIR/refresh_toc.sh" ]; then
  "$SELF_DIR/refresh_toc.sh" "$IN_ABS" >/dev/null
fi

# --- find an engine --------------------------------------------------------

find_chrome() {
  for c in google-chrome google-chrome-stable chromium chromium-browser chrome \
           brave-browser microsoft-edge; do
    if command -v "$c" >/dev/null 2>&1; then command -v "$c"; return 0; fi
  done
  for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
           "/Applications/Chromium.app/Contents/MacOS/Chromium" \
           "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" \
           "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"; do
    if [ -x "$c" ]; then printf '%s' "$c"; return 0; fi
  done
  return 1
}

CHROME=""
if [ -z "$ENGINE" ] || [ "$ENGINE" = "chrome" ]; then
  CHROME=$(find_chrome || true)
fi

if [ -z "$ENGINE" ]; then
  if   [ -n "$CHROME" ];                            then ENGINE="chrome"
  elif command -v weasyprint  >/dev/null 2>&1;      then ENGINE="weasyprint"
  elif command -v wkhtmltopdf >/dev/null 2>&1;      then ENGINE="wkhtmltopdf"
  else
    die "no HTML-to-PDF engine found. Install Chrome/Chromium (recommended),
     or WeasyPrint (pip install weasyprint), or wkhtmltopdf."
  fi
fi

# --- convert ---------------------------------------------------------------

case "$ENGINE" in
  chrome)
    [ -n "$CHROME" ] || CHROME=$(find_chrome) || die "Chrome/Chromium not found"

    # A throwaway profile keeps this from colliding with a Chrome the user
    # already has open, which would otherwise make the headless run exit early.
    PROFILE=$(mktemp -d "${TMPDIR:-/tmp}/pdfdoc.XXXXXX")
    trap 'rm -rf "$PROFILE"' EXIT

    SANDBOX=""
    [ "$(id -u)" = "0" ] && SANDBOX="--no-sandbox"

    # --no-pdf-header-footer suppresses Chrome's own date/URL furniture; without
    # it every page gets a timestamp header and a file:// footer.
    set -- --headless --disable-gpu $SANDBOX \
           --user-data-dir="$PROFILE" \
           --no-pdf-header-footer \
           --run-all-compositor-stages-before-draw \
           --virtual-time-budget=10000 \
           --print-to-pdf="$OUT" "$IN_ABS"

    if ! "$CHROME" "$@" >/dev/null 2>&1 || [ ! -s "$OUT" ]; then
      # Chrome before ~118 spells the flag differently.
      "$CHROME" --headless --disable-gpu $SANDBOX \
                --user-data-dir="$PROFILE" \
                --print-to-pdf-no-header \
                --print-to-pdf="$OUT" "$IN_ABS" >/dev/null 2>&1 || true
    fi
    ;;

  weasyprint)
    command -v weasyprint >/dev/null 2>&1 || die "weasyprint not found"
    weasyprint "$IN_ABS" "$OUT"
    ;;

  wkhtmltopdf)
    command -v wkhtmltopdf >/dev/null 2>&1 || die "wkhtmltopdf not found"
    # wkhtmltopdf uses an old WebKit: flexbox and CSS variables degrade badly.
    printf 'html2pdf: warning — wkhtmltopdf renders this layout poorly; prefer Chrome.\n' >&2
    wkhtmltopdf --enable-local-file-access --print-media-type "$IN_ABS" "$OUT"
    ;;

  *)
    die "unknown engine: $ENGINE"
    ;;
esac

[ -s "$OUT" ] || die "conversion produced no output ($ENGINE)"

PAGES=""
if command -v pdfinfo >/dev/null 2>&1; then
  PAGES=$(pdfinfo "$OUT" 2>/dev/null | awk '/^Pages:/{print $2}')
fi

if [ -n "$PAGES" ]; then
  printf '%s (%s pages, %s)\n' "$OUT" "$PAGES" "$ENGINE"
else
  printf '%s (%s)\n' "$OUT" "$ENGINE"
fi
