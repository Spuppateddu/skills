#!/usr/bin/env bash
# new_doc.sh — build a self-contained, brand-styled HTML document.
#
# The generated file inlines the canonical stylesheet and base64-embeds the
# logo, so it is a single portable file: move it, mail it, edit it in any
# editor, then re-run html2pdf.sh on it.
#
# Usage:
#   new_doc.sh --title "Quarterly Report" \
#              [--subtitle "..."] [--eyebrow "..."] \
#              [--color "#1F4E79"] [--color2 "#E8833A"] \
#              [--logo path/to/logo.png] [--logo-invert] \
#              [--lang it] [--toc-title "Indice"] [--no-toc] [--numbered] \
#              [--compact-header]   (masthead + TOC on page 1, no cover page) \
#              [--meta "Label|Value"]...  (repeatable, cover metadata rows) \
#              [--content body.html] [-o out.html]
#
# Portable bash 3.2 / POSIX awk — works on Linux and macOS.

set -euo pipefail

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CSS_FILE="$SELF_DIR/../assets/doc.css"

die() { printf 'new_doc: %s\n' "$1" >&2; exit 1; }

# --- defaults --------------------------------------------------------------

TITLE=""
SUBTITLE=""
EYEBROW=""
COLOR="#1F4E79"
COLOR2=""
LOGO=""
LOGO_INVERT=0
LANG_CODE="en"
TOC_TITLE=""
WANT_TOC=1
NUMBERED=0
COMPACT_HEADER=0
CONTENT_FILE=""
OUT=""
META_LABELS=""   # newline-separated "Label|Value" pairs
HAS_META=0

# --- argument parsing ------------------------------------------------------

while [ $# -gt 0 ]; do
  case "$1" in
    --title)       TITLE=${2:-}; shift 2 ;;
    --subtitle)    SUBTITLE=${2:-}; shift 2 ;;
    --eyebrow)     EYEBROW=${2:-}; shift 2 ;;
    --color)       COLOR=${2:-}; shift 2 ;;
    --color2)      COLOR2=${2:-}; shift 2 ;;
    --logo)        LOGO=${2:-}; shift 2 ;;
    --logo-invert) LOGO_INVERT=1; shift ;;
    --lang)        LANG_CODE=${2:-}; shift 2 ;;
    --toc-title)   TOC_TITLE=${2:-}; shift 2 ;;
    --no-toc)      WANT_TOC=0; shift ;;
    --numbered)    NUMBERED=1; shift ;;
    --compact-header) COMPACT_HEADER=1; shift ;;
    --content)     CONTENT_FILE=${2:-}; shift 2 ;;
    --meta)        META_LABELS="$META_LABELS
${2:-}"; HAS_META=1; shift 2 ;;
    -o|--out)      OUT=${2:-}; shift 2 ;;
    -h|--help)     sed -n '2,20p' "$0"; exit 0 ;;
    *)             die "unknown option: $1" ;;
  esac
done

[ -n "$TITLE" ] || die "--title is required"
[ -f "$CSS_FILE" ] || die "stylesheet not found: $CSS_FILE"
[ -z "$CONTENT_FILE" ] || [ -f "$CONTENT_FILE" ] || die "content file not found: $CONTENT_FILE"

if [ "$COMPACT_HEADER" = "1" ]; then
  # The banner variant leaves the first page at zero margin so the band can
  # bleed to the edges; the TOC underneath is what restores that page's margin.
  [ "$WANT_TOC" = "1" ] || die "--compact-header needs the table of contents: drop --no-toc"
  # A masthead has no room for the metadata rows, and dropping them silently
  # would lose the client/date/version off the document.
  [ "$HAS_META" = "0" ] || die "--compact-header has no metadata block: drop --meta or the flag"
fi

# --- colour maths ----------------------------------------------------------
# Every derived shade is computed here and written as a literal hex value, so
# the stylesheet needs no colour functions and renders identically in any
# HTML-to-PDF engine.

AWK_HEX='
function h2d(s,   i, c, n, d) {
  n = 0; s = tolower(s)
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1); d = index("0123456789abcdef", c) - 1
    if (d < 0) d = 0
    n = n * 16 + d
  }
  return n
}
function lin(c) {
  c = c / 255
  return (c <= 0.03928) ? c / 12.92 : ((c + 0.055) / 1.055) ^ 2.4
}
function luma(hex) {
  return 0.2126 * lin(h2d(substr(hex, 2, 2))) \
       + 0.7152 * lin(h2d(substr(hex, 4, 2))) \
       + 0.0722 * lin(h2d(substr(hex, 6, 2)))
}
'

# norm_hex "#abc" -> "#aabbcc"
norm_hex() {
  awk -v s="$1" 'BEGIN{
    gsub(/^#/, "", s); s = tolower(s)
    if (s !~ /^[0-9a-f]+$/) exit 1
    if (length(s) == 3) s = substr(s,1,1) substr(s,1,1) substr(s,2,1) substr(s,2,1) substr(s,3,1) substr(s,3,1)
    if (length(s) != 6) exit 1
    printf "#%s", s
  }' || die "invalid colour: $1 (use #rrggbb or #rgb)"
}

# mix BASE TARGET WEIGHT% -> hex
mix() {
  awk -v a="$1" -v b="$2" -v w="$3" "$AWK_HEX"'
  BEGIN{
    w = w / 100
    ar=h2d(substr(a,2,2)); ag=h2d(substr(a,4,2)); ab=h2d(substr(a,6,2))
    br=h2d(substr(b,2,2)); bg=h2d(substr(b,4,2)); bb=h2d(substr(b,6,2))
    printf "#%02x%02x%02x", int(ar+(br-ar)*w+0.5), int(ag+(bg-ag)*w+0.5), int(ab+(bb-ab)*w+0.5)
  }'
}

# Is the colour light enough that white text on it would be unreadable?
is_light() {
  awk -v a="$1" "$AWK_HEX"'BEGIN{ print (luma(a) >= 0.30) ? "yes" : "no" }'
}

COLOR=$(norm_hex "$COLOR")
[ -n "$COLOR2" ] && COLOR2=$(norm_hex "$COLOR2") || COLOR2="$COLOR"

# Text-safe variants: a pale brand colour is unreadable as heading text on
# white, so darken it until it carries enough contrast.
if [ "$(is_light "$COLOR")" = "yes" ]; then
  BRAND_INK=$(mix "$COLOR" "#000000" 52)
else
  BRAND_INK="$COLOR"
fi
if [ "$(is_light "$COLOR2")" = "yes" ]; then
  ACCENT_INK=$(mix "$COLOR2" "#000000" 52)
else
  ACCENT_INK="$COLOR2"
fi

BRAND_TINT=$(mix "$COLOR" "#ffffff" 90)
ACCENT_TINT=$(mix "$COLOR2" "#ffffff" 90)
ZEBRA=$(mix "$COLOR" "#ffffff" 96)
CODE_BG=$(mix "$COLOR" "#ffffff" 95)

# Cover band text colour follows the band's own luminance.
if [ "$(is_light "$COLOR")" = "yes" ]; then
  ON_BRAND="#14161a"
else
  ON_BRAND="#ffffff"
fi

LOGO_FILTER="none"
[ "$LOGO_INVERT" = "1" ] && LOGO_FILTER="brightness(0) invert(1)"

# --- logo embedding --------------------------------------------------------

LOGO_TAG=""
if [ -n "$LOGO" ]; then
  [ -f "$LOGO" ] || die "logo not found: $LOGO"
  case "$(printf '%s' "$LOGO" | tr 'A-Z' 'a-z')" in
    *.png)        MIME="image/png" ;;
    *.jpg|*.jpeg) MIME="image/jpeg" ;;
    *.svg)        MIME="image/svg+xml" ;;
    *.webp)       MIME="image/webp" ;;
    *.gif)        MIME="image/gif" ;;
    *) die "unsupported logo format: $LOGO (png, jpg, svg, webp, gif)" ;;
  esac
  B64=$(base64 < "$LOGO" | tr -d '\n')
  LOGO_TAG="<img class=\"cover__logo\" alt=\"\" src=\"data:$MIME;base64,$B64\">"
fi

# --- helpers ---------------------------------------------------------------

esc() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'
}

slug() {
  printf '%s' "$1" | tr 'A-Z' 'a-z' | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-//' -e 's/-$//' | cut -c1-60
}

if [ -z "$OUT" ]; then
  OUT="$(slug "$TITLE")"
  [ -n "$OUT" ] || OUT="document"
  OUT="$OUT.html"
fi

# Default the TOC heading to the document language when not given explicitly.
if [ -z "$TOC_TITLE" ]; then
  case "$LANG_CODE" in
    it*) TOC_TITLE="Indice" ;;
    es*) TOC_TITLE="Índice" ;;
    fr*) TOC_TITLE="Sommaire" ;;
    de*) TOC_TITLE="Inhalt" ;;
    pt*) TOC_TITLE="Índice" ;;
    nl*) TOC_TITLE="Inhoud" ;;
    *)   TOC_TITLE="Contents" ;;
  esac
fi

BODY_CLASS=""
if [ "$NUMBERED" = "1" ]; then BODY_CLASS=' class="numbered"'; fi

COVER_CLASS="cover"
if [ "$COMPACT_HEADER" = "1" ]; then COVER_CLASS="cover cover--banner"; fi

# --- emit ------------------------------------------------------------------

{
cat <<HTML
<!doctype html>
<html lang="$(esc "$LANG_CODE")">
<head>
<meta charset="utf-8">
<meta name="generator" content="pdf-doc">
<title>$(esc "$TITLE")</title>

<!-- Brand tokens for this document. Change a value here and re-run
     html2pdf.sh to restyle the whole file. -->
<style id="doc-tokens">
:root {
  --brand:        $COLOR;
  --brand-ink:    $BRAND_INK;
  --brand-tint:   $BRAND_TINT;
  --accent:       $COLOR2;
  --accent-ink:   $ACCENT_INK;
  --accent-tint:  $ACCENT_TINT;
  --on-brand:     $ON_BRAND;
  --logo-filter:  $LOGO_FILTER;

  --ink:          #1f2328;
  --ink-strong:   #0d1013;
  --ink-soft:     #5c6370;
  --rule:         #e3e4e8;
  --rule-strong:  #c8cad0;
  --zebra:        $ZEBRA;
  --code-bg:      $CODE_BG;

  /* DocSans/DocMono are defined by @font-face over local() in the stylesheet
     below; the trailing families are a safety net if none resolve. */
  --font-body: DocSans, Arial, "Liberation Sans", sans-serif;
  --font-head: DocSans, Arial, "Liberation Sans", sans-serif;
  --font-mono: DocMono, "DejaVu Sans Mono", monospace;
}
</style>

<style id="doc-style">
HTML

cat "$CSS_FILE"

cat <<HTML

/* Page numbers are off by default. Uncomment to print "3 / 12" centred at the
   foot of every page except the cover. */
/*
@page { @bottom-center { content: counter(page) " / " counter(pages);
        font-family: var(--font-body); font-size: 8.5pt; color: #5c6370; } }
@page :first { @bottom-center { content: ""; } }
*/
</style>
</head>

<body$BODY_CLASS>

<section class="$COVER_CLASS">
  <div class="cover__band">
    $LOGO_TAG
HTML

[ -n "$EYEBROW" ]  && printf '    <p class="cover__eyebrow">%s</p>\n' "$(esc "$EYEBROW")"
printf '    <h1 class="cover__title">%s</h1>\n' "$(esc "$TITLE")"
[ -n "$SUBTITLE" ] && printf '    <p class="cover__subtitle">%s</p>\n' "$(esc "$SUBTITLE")"

cat <<'HTML'
  </div>
  <div class="cover__rule"></div>
HTML

# The banner variant ends at the rule: no metadata block, and none was accepted.
if [ "$COMPACT_HEADER" = "0" ]; then
  printf '  <div class="cover__meta">\n'

  if [ "$HAS_META" = "1" ]; then
    printf '    <dl>\n'
    printf '%s\n' "$META_LABELS" | while IFS= read -r row; do
      [ -n "$row" ] || continue
      label=${row%%|*}
      value=${row#*|}
      printf '      <dt>%s</dt><dd>%s</dd>\n' "$(esc "$label")" "$(esc "$value")"
    done
    printf '    </dl>\n'
  fi

  printf '  </div>\n'
fi

cat <<'HTML'
</section>
HTML

if [ "$WANT_TOC" = "1" ]; then
  cat <<HTML

<nav class="toc">
  <h2 class="toc__title">$(esc "$TOC_TITLE")</h2>
  <!--TOC:START-->
  <!--TOC:END-->
</nav>
HTML
fi

printf '\n<main>\n'
if [ -n "$CONTENT_FILE" ]; then
  cat "$CONTENT_FILE"
else
  cat <<'HTML'
<h2>First section</h2>
<p class="lead">Replace this content. Every h2 becomes a top-level entry in the
table of contents, every h3 a sub-entry — the TOC is rebuilt automatically each
time you convert.</p>
HTML
fi
printf '</main>\n'

cat <<'HTML'

<!-- Per-document tweaks go here so they survive a restyle of the shared
     stylesheet above. Keep it empty unless this document genuinely needs
     something the standard components do not cover. -->
<style id="doc-overrides"></style>

</body>
</html>
HTML
} > "$OUT"

# Populate the table of contents right away, so the file is complete even
# before the first conversion.
if [ "$WANT_TOC" = "1" ]; then
  "$SELF_DIR/refresh_toc.sh" "$OUT" >/dev/null
fi

printf '%s\n' "$OUT"
