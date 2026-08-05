#!/usr/bin/env bash
# refresh_toc.sh — rebuild a document's table of contents from its own headings.
#
# Scans the <main> element for <h2>/<h3>, gives any heading that lacks one a
# stable id, and rewrites whatever sits between <!--TOC:START--> and
# <!--TOC:END-->. Idempotent: running it twice produces the same file.
#
# Called automatically by new_doc.sh and html2pdf.sh, so a heading you add by
# hand shows up in the TOC on the next conversion without any extra step.
#
# Usage: refresh_toc.sh <file.html>

set -euo pipefail

FILE=${1:-}
[ -n "$FILE" ] || { echo "refresh_toc: usage: refresh_toc.sh <file.html>" >&2; exit 1; }
[ -f "$FILE" ] || { echo "refresh_toc: no such file: $FILE" >&2; exit 1; }

# Nothing to do if the document has no TOC markers (--no-toc documents).
if ! grep -q '<!--TOC:START-->' "$FILE" || ! grep -q '<!--TOC:END-->' "$FILE"; then
  printf '%s\n' "$FILE"
  exit 0
fi

TMP="${FILE}.toc.$$"
trap 'rm -f "$TMP" "$TMP.n"' EXIT

awk '
function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }

{ line[++nl] = $0 }

END {
  # Pass 1 — reserve every id already written by hand, so a generated one can
  # never collide with it (two headings sharing an id would give the TOC two
  # entries pointing at the same place).
  inmain = 0
  for (i = 1; i <= nl; i++) {
    l = line[i]
    if (!inmain) { if (l ~ /<main[ >]/) inmain = 1; continue }
    if (l ~ /<\/main>/) { inmain = 0; continue }

    lvl = 0
    if (index(l, "<h2") > 0) lvl = 2
    else if (index(l, "<h3") > 0) lvl = 3
    if (lvl == 0) continue

    rest = substr(l, index(l, "<h" lvl))
    gt = index(rest, ">")
    if (gt == 0) continue
    tag = substr(rest, 1, gt)
    if (match(tag, /id[ ]*=[ ]*"[^"]*"/)) {
      hid = substr(tag, RSTART, RLENGTH)
      sub(/^id[ ]*=[ ]*"/, "", hid)
      sub(/"$/, "", hid)
      used[hid] = 1
    }
  }

  inmain = 0
  ord = 0
  n = 0

  # Pass 2 — walk <main>, harvest headings, assign missing ids in place.
  for (i = 1; i <= nl; i++) {
    l = line[i]

    if (!inmain) {
      if (l ~ /<main[ >]/) inmain = 1
      continue
    }
    if (l ~ /<\/main>/) { inmain = 0; continue }

    lvl = 0
    if (index(l, "<h2") > 0) lvl = 2
    else if (index(l, "<h3") > 0) lvl = 3
    if (lvl == 0) continue

    p = index(l, "<h" lvl)
    rest = substr(l, p)
    gt = index(rest, ">")
    if (gt == 0) continue            # heading tag spans lines — skip it
    tag = substr(rest, 1, gt)

    ord++
    if (match(tag, /id[ ]*=[ ]*"[^"]*"/)) {
      hid = substr(tag, RSTART, RLENGTH)
      sub(/^id[ ]*=[ ]*"/, "", hid)
      sub(/"$/, "", hid)
    } else {
      hid = "sec-" ord
      while (hid in used) { ord++; hid = "sec-" ord }
      used[hid] = 1
      # Insert the id straight after "<hN" (3 characters).
      line[i] = substr(l, 1, p + 2) " id=\"" hid "\"" substr(l, p + 3)
    }

    after = substr(rest, gt + 1)
    e = index(after, "</h" lvl)
    txt = (e > 0) ? substr(after, 1, e - 1) : after
    gsub(/<[^>]*>/, "", txt)         # drop inline markup from the TOC entry
    txt = trim(txt)
    if (txt == "") continue

    n++
    hlvl[n] = lvl; hids[n] = hid; htxt[n] = txt
  }

  # Build the TOC markup.
  toc = "  <ol>\n"
  item = 0; sub_open = 0
  for (k = 1; k <= n; k++) {
    if (hlvl[k] == 2 || item == 0) {
      if (sub_open) { toc = toc "      </ol>\n"; sub_open = 0 }
      if (item) toc = toc "    </li>\n"
      toc = toc "    <li><a href=\"#" hids[k] "\">" htxt[k] "</a>\n"
      item = 1
    } else {
      if (!sub_open) { toc = toc "      <ol>\n"; sub_open = 1 }
      toc = toc "        <li><a href=\"#" hids[k] "\">" htxt[k] "</a></li>\n"
    }
  }
  if (sub_open) toc = toc "      </ol>\n"
  if (item)     toc = toc "    </li>\n"
  toc = toc "  </ol>"

  # Pass 3 — emit, replacing the marked region.
  skip = 0
  for (i = 1; i <= nl; i++) {
    if (skip) {
      if (line[i] ~ /<!--TOC:END-->/) { print line[i]; skip = 0 }
      continue
    }
    print line[i]
    if (line[i] ~ /<!--TOC:START-->/) {
      if (n > 0) print toc
      skip = 1
    }
  }
  printf "%d\n", n > COUNT
}
' COUNT="$TMP.n" "$FILE" > "$TMP"

# Only replace the original once awk has written a complete file.
[ -s "$TMP" ] || { echo "refresh_toc: refused to write an empty file" >&2; exit 1; }
cat "$TMP" > "$FILE"

printf '%s (%s headings)\n' "$FILE" "$(cat "$TMP.n" 2>/dev/null || echo 0)"
