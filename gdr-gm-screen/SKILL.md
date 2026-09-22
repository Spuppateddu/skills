---
name: gdr-gm-screen
description: Build a tabletop RPG "schermo del master" (GM screen) as a 4-page A4 PDF from the game's rulebook — the rules the GM looks up mid-scene (resolution, conflict, damage, downtime, GM procedures, random tables), condensed into one fixed black-and-white layout shared by every game, so all the screens look like one set. Reads the manual PDF (or an existing manual-text/ folder), plans the four pages, writes a self-contained HTML with the shared stylesheet inlined, renders it with the Chromium on the machine, measures free space and overflow, and looks at the pages. Use whenever the user asks for a "schermo del master", "schermo del GM", "schermo della Guida/del Cantore/del Narratore", a GM screen, a rules cheat sheet, "riassunto delle regole per il master", "le regole principali in 4 pagine", or "like the screen we made for Blades/Ronin/Rosewood/Kulthos", even if they do not say PDF or HTML.
---

# gdr-gm-screen

The deliverable is two files in the game's folder that stay in sync:

- `<slug>-schermo.html` — the source, self-contained (the shared stylesheet
  is copied inside). The user edits the text here.
- `<slug>-schermo.pdf` — the render: 4 A4 pages, black and white, the same
  look as every other screen made with this skill.

After the first build the HTML is the source of truth: to change a rule, edit
the HTML and re-render. Never rebuild from scratch to apply an edit.

`<skill-dir>` is the folder holding this file; `scripts/`, `assets/`,
`templates/` and `reference/` sit next to it. Read `reference/page-plan.md`
(what belongs on which page, with the outlines of the four finished screens)
and `reference/lessons.md` (writing and rendering rules) before you start.

## Step 0 — inputs

Find these; ask only for what is missing.

1. **The rulebook.** A PDF, or a `manual-text/` folder already extracted
   (Blades and Rosewood have one: markdown per chapter with `<!-- p.N -->`
   markers — use it with grep, cite those page numbers). Never read a whole
   rulebook into context: extract, read the outline, then grep and read pages.
2. **The game folder** where the files go (the folder with the manual), the
   **game title** as it should print in the footer, and the **GM's name in
   this game** (GM, Guida, Cantore, Narratore, Custode, Master…) — take it
   from the manual, it goes in the footer and the title.
3. **The language**: the manual's, unless the user asks otherwise.
4. **An existing screen?** If `<slug>-schermo.html` exists, this is an edit:
   change that file and re-render. Do not create a second one.

Tools: `python3`, poppler-utils (`pdftotext`, `pdftohtml`, `pdfinfo`,
`pdftoppm`) and a Chromium (Chrome, Chromium, Brave or Edge). Nothing is
installed; `render_schermo.sh` finds the browser or says what to set.

## Step 1 — read the manual the cheap way

```bash
python3 <skill-dir>/scripts/manual.py extract "<game>/<manual>.pdf" "<game>/manual-text"
python3 <skill-dir>/scripts/manual.py toc "<game>/manual-text"        # chapters with PDF pages
python3 <skill-dir>/scripts/manual.py grep "<game>/manual-text" 'successo|fallimento' -i -C 2
python3 <skill-dir>/scripts/manual.py page "<game>/manual-text" 50-52  # read 2-3 pages per call
python3 <skill-dir>/scripts/manual.py page "<game>/manual-text" 63-86 -o /tmp/x/combat.txt  # a chapter: dump, then Read in chunks
```

`extract` writes `full-layout.txt` (every page, columns and tables kept),
`outline.md` (the PDF bookmarks with PDF page numbers) and a README. Page
numbers are PDF pages; cite them as `pdf p.N`. A page is 3-6 K characters:
`page` prints at most 2-3 per call, a whole chapter goes to a file with `-o`.

From the outline, pick the chapters that hold rules (the core mechanic, skills,
conflict, damage, downtime/haven/travel, running the game, appendix tables)
and read those pages, a few at a time. Skip setting, fiction, examples of play
and character creation. When the extracted text of a table is garbled, look
at the page: `pdftoppm -f N -l N -r 80 -png manual.pdf /tmp/x/p` and Read the PNG.

Then write the **page plan** as a short list in your scratch folder (not in
the game folder): four titles, each with its sections in order and the PDF
pages each section comes from. Compare it with the outlines in
`reference/page-plan.md`; the shape should match the closest game. This plan
is what you show the user in the report.

## Step 2 — create the HTML

```bash
bash <skill-dir>/scripts/new_schermo.sh --game "Ronin" --screen "Schermo del GM" \
     --lang it -o "Ronin/ronin-schermo.html"
```

It writes the file from `templates/`, with `assets/schermo.css` inlined and
four page skeletons (header, two columns, footer); it refuses to overwrite an
existing file unless you pass `--force`. Then fill the pages: either edit each
skeleton in place, or write the four `<div class="page">` blocks to a scratch
file and replace everything between `<body>` and `</body>` with them.

The components — use these and nothing else, they are what the stylesheet
covers:

```html
<div class="page">
  <div class="head"><h1>Tiri &amp; Basi</h1>
    <div class="sub">tiro azione · posizione · efficacia · stress</div>
    <div class="pgnum">1</div></div>
  <div class="cols">
    <div class="col">                       <!-- add class="wide" for a 1.35x column -->
      <h2>Tiro azione</h2>                  <!-- pdf p.20-24 -->
      <ul><li><b>Pool</b> = 1d per pallino · conta il <b>dado più alto</b>.</li></ul>
      <table><tr><th>Posizione</th><th class="c">6</th><th>4/5</th></tr>
             <tr><td><b>Rischiosa</b></td><td class="c die">ok</td><td>danno…</td></tr></table>
      <h3>Armatura</h3>                     <!-- underlined sub-heading -->
      <ol><li>Dichiara l'obiettivo.</li><li>Scegli l'azione.</li></ol>
      <div class="box"><div class="bt">Patti col diavolo</div>Danni collaterali · …</div>
      <p class="trig">Quando fai qualcosa di rischioso, tira.</p>   <!-- a move's trigger -->
      <div class="res"><div><span class="k">10+</span><span>Riesci.</span></div>
                       <div><span class="k bad">6-</span><span>Il GM fa una mossa.</span></div></div>
      <p class="small">Nota in corpo minore.</p>
      <table><tr><td class="nw">1 giorno</td><td>…</td></tr></table>   <!-- .nw: cell that must not wrap -->
    </div>
    <div class="col">…</div>
  </div>
  <h2>Le 12 azioni</h2>                     <!-- full-width block under the columns -->
  <table class="tiny grid">…</table>
  <h2>Veicoli</h2>                          <!-- or a second .cols block with 2-3 .col -->
  <div class="cols"><div class="col">…</div><div class="col">…</div></div>
  <div class="foot"><span>Blades in the Dark · Schermo del GM</span><span>1 / 4</span></div>
</div>
```

Rules while writing (the why is in `reference/lessons.md`):

- Language of the manual; imperative, addressed to the GM; the game's terms
  spelled as the book spells them.
- Bold the game term or the number once per line; join short alternatives
  with ` · `; a bullet is one rule plus its exception.
- Three or more value pairs → a table. A procedure → `<ol>` or a `.box`.
- Paraphrase; never paste paragraphs from the book. Put `<!-- pdf p.N -->`
  after every `<h2>` so the user can check the source.
- No rule you could not verify. List doubts in the report instead.
- Aim for 5 000–6 500 characters of text per page (up to ~7 000 when most
  of it is tables), 6–10 `<h2>` per page.
- The `.sub` line names the page's sections in order; page titles are 2–4
  words with `&amp;` between two topics.
- Per-screen size tweaks (`body { font-size: 7.3pt; }`) go in
  `<style id="schermo-overrides">`, within 7.2–8 pt. Never edit the
  `schermo-css` block: it is shared, and `--refresh-css` overwrites it.

## Step 3 — render, measure, look, fix

```bash
bash <skill-dir>/scripts/render_schermo.sh "Ronin/ronin-schermo.html" --png /tmp/x/ronin
```

It prints the PDF path and page count (must equal the number of pages in the
HTML), then one line per page:

```
page 1: free 4.2mm above the footer   cols short by mm: [0.0 / 7.5]
page 2: OVERFLOW by 12.4mm            cols short by mm: [0.0 / 31.0]  [0.0 / 3.0]
page 3: free 0.0mm above the footer   cols short by mm: [3.6 / 0.0]  (full, ok)
   sub-line items that match no h2/h3/box title on this page: veicoli
```

`free` is the gap between the content and the footer (0.0 without OVERFLOW is
the ideal: the page is full); `cols` says how much shorter each column is than
the tallest one in its group, one bracket per `.cols` block. The sub-line
warning means the `.sub` index no longer matches the page's `<h2>` sections:
re-sync it after moving a section. Exit status 2 means overflow or a
page-count mismatch. An overflowing page's tail is printed at the top of the
next page's PNG: that is page N's spill, not page N+1's content. The first run ever warms up a browser
profile (up to 45 s); after that a render takes about a second. Run renders
one at a time. `SCHERMO_CHROME=/path/to/binary` picks the browser by hand.

Fix by moving content, in this order: a section to the shorter column, a
section to the page with room, then cut, then only as a last resort the
font size override. Target: free ≤ 6 mm, columns within 8 mm. Two numbers to
plan the cuts: a column line is ~3.2 mm and ~85 characters, so a cut only
helps when it removes a whole line (merge two rows or two bullets; shaving
words changes nothing if the measure repeats); and 0.1 pt of font size is
worth ~3.5 mm per page, so the override closes the last 10 mm, never a 50 mm
overflow.

Then Read every PNG (`/tmp/x/ronin/page-1.png` …), all four: a table whose
column wraps every cell, a title that broke onto two lines, a box cut at the
foot of a column, a bullet that lost its bold — the numbers do not catch
those. Fix the HTML, re-render. Two or three rounds are normal.

## Step 4 — report

Give the two paths, the page plan (four titles with their sections), what was
left out on purpose and why, the rules you could not verify, and the loop for
edits: change the HTML, run `render_schermo.sh` again. If the shared style is
changed later, `new_schermo.sh --refresh-css <file.html>` re-inlines it into an
old screen.

## Files in this skill

- `assets/schermo.css` — the one stylesheet. Change it here, then
  `--refresh-css` every screen.
- `templates/schermo-template.html`, `templates/page-template.html` — the
  document and page skeletons `new_schermo.sh` fills.
- `scripts/new_schermo.sh` — create a screen's HTML / re-inline the stylesheet.
- `scripts/render_schermo.sh` — HTML → PDF with the local Chromium, page-count
  check, per-page free-space and column measure, PNG previews.
- `scripts/manual.py` — extract / toc / grep / page over a rulebook PDF.
- `reference/page-plan.md` — what goes on which page; the four finished
  screens' outlines as worked examples; density figures.
- `reference/lessons.md` — 22 lessons on writing, layout and rendering.
