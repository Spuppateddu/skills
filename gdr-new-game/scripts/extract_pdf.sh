#!/usr/bin/env bash
# Pull the text out of a character sheet / rulebook PDF so the model can read it
# without swallowing the whole file, and render pages to PNG when the PDF is a
# scan with no text layer.
#
# Usage:  extract_pdf.sh <out-dir> <file.pdf|file.png> [more files...]
#         PAGES=12-18 extract_pdf.sh <out-dir> <scanned-book.pdf>
#
# For each PDF it writes <out-dir>/<name>.txt and reports the page count and how
# much text came out. Under ~100 characters per page means there is no text
# layer: it then renders pages to <out-dir>/<name>-NN.png for you to read with
# the Read tool. Image inputs are just reported — read them directly.
#
# PAGES=<first>-<last> renders exactly that range instead of the first few. Use
# it for a scanned rulebook, where only the pages describing the character sheet
# matter: ask the user which pages those are, then re-run with PAGES set.
set -eu

if [ "$#" -lt 2 ]; then
    echo "usage: extract_pdf.sh <out-dir> <file.pdf|file.png> [more files...]" >&2
    exit 2
fi

OUT="$1"; shift
mkdir -p "$OUT"

command -v pdftotext >/dev/null 2>&1 || {
    echo "pdftotext not found. Install poppler-utils (apt install poppler-utils)." >&2
    exit 2
}

# How many pages of a scanned PDF to render when PAGES is not set. A character
# sheet is 1-4 pages; never render a whole rulebook.
MAX_RENDER=4

# PAGES=<first>-<last>, optional.
FIRST=""; LAST=""
if [ -n "${PAGES:-}" ]; then
    case "$PAGES" in
        [0-9]*-[0-9]*) FIRST="${PAGES%%-*}"; LAST="${PAGES##*-}" ;;
        [0-9]*)        FIRST="$PAGES";       LAST="$PAGES" ;;
        *) echo "PAGES must look like 12-18 or 12, got: $PAGES" >&2; exit 2 ;;
    esac
    if [ $(( LAST - FIRST )) -ge 20 ]; then
        echo "PAGES range is $(( LAST - FIRST + 1 )) pages. Render at most 20 at a time." >&2
        exit 2
    fi
fi

for src in "$@"; do
    if [ ! -f "$src" ]; then
        echo "MISSING: $src" >&2
        continue
    fi

    base="$(basename "$src")"
    name="${base%.*}"
    ext="$(printf '%s' "${base##*.}" | tr 'A-Z' 'a-z')"

    if [ "$ext" != "pdf" ]; then
        echo "IMAGE  $src"
        echo "       read it directly with the Read tool."
        echo
        continue
    fi

    txt="$OUT/$name.txt"
    pdftotext -layout "$src" "$txt"

    pages="$(pdfinfo "$src" 2>/dev/null | awk '/^Pages:/ {print $2}')"
    [ -n "${pages:-}" ] || pages=1
    chars="$(wc -c < "$txt" | tr -d ' ')"
    per_page=$(( chars / pages ))

    echo "PDF    $src"
    echo "       pages: $pages   text: $chars chars (~$per_page per page)"
    echo "       text:  $txt"

    if [ "$per_page" -lt 100 ]; then
        echo "       NO TEXT LAYER — this is a scan, so the .txt above is empty."
        if [ -n "$FIRST" ]; then
            first="$FIRST"; last="$LAST"
            [ "$last" -gt "$pages" ] && last="$pages"
        elif [ "$pages" -gt "$MAX_RENDER" ]; then
            echo "       $pages scanned pages is a whole book — too many to read."
            echo "       Ask the user which pages describe the character sheet and the"
            echo "       attributes, then re-run:  PAGES=<first>-<last> extract_pdf.sh ..."
            echo "       (Or read the PDF directly with the Read tool, up to 20 pages a time.)"
            echo
            continue
        else
            first=1; last="$pages"
        fi
        echo "       Rendering pages $first-$last to PNG:"
        pdftoppm -png -r 150 -f "$first" -l "$last" "$src" "$OUT/$name"
        ls "$OUT/$name"-*.png 2>/dev/null | sed 's/^/         /'
        echo "       read those PNGs with the Read tool."
    elif [ "$pages" -gt 20 ]; then
        echo "       Large document with a text layer. Do not read it all: grep the .txt"
        echo "       for the attribute list, the track lengths and the section names only."
    fi
    echo
done
