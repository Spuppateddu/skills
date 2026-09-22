---
name: gdr-character-sheets
description: Fill a tabletop RPG character sheet (and crew/party sheet) as Xournal++ files (.xopp) over the game's blank PDF sheet, exported to PDF, from a file with the characters' data or from characters rolled at random with the game's manual. Reads the printed sheet's geometry from the PDF itself (words, dots, checkboxes, rules), writes text on the printed lines, fills dots, ticks boxes, rings the chosen options, adds notes and a story handout, renders the result and looks at it. Use whenever the user wants pregenerated characters, "schede compilate", "personaggi pregenerati", a one-shot's PCs on the official sheet, a crew/banda/party sheet, or says "compila la scheda", "fill the sheet", "make the sheets with Xournal++", "like we did for Ronin/Kulthos/Blades/Rosewood", even if they do not name Xournal++ or a PDF.
---

# gdr-character-sheets

The deliverable is a folder of **editable** sheets: one `.xopp` per character (the
blank official sheet as background, your text and marks on top), the exported
`.pdf` of each, one merged PDF for printing, and the `make_sheets.py` that built
them so a changed value is one edit and one rerun. The user opens the `.xopp` in
Xournal++ to nudge anything by hand.

`<skill-dir>` below is the folder holding this `SKILL.md`; `scripts/`,
`reference/` and `templates/` sit next to it.

Read `reference/lessons.md` before you start: it is the list of things that went
wrong (or right) on the four one-shots this skill comes from, and every point
there saves a rebuild.

## Step 0 — inputs

Find these before anything else; ask only for what is missing.

1. **The blank sheet PDF** (required). Often a kit with many pages: playbooks,
   crew sheet, reference pages. Map the pages first (`pdfinfo`, then one
   `pdftotext -f N -l N` per page to see what each is).
2. **The manual**: prefer a `manual-text/` folder (one markdown per chapter with
   `<!-- p.N -->` page markers and a README listing chapters); else the PDF,
   extracted per page range with `pdftotext -layout`. Never read a whole rulebook.
3. **The character data**: a text/markdown/JSON file per character or for the
   party (the user's own `personaggi/*.txt` files are usually richer than the
   one-shot PDF: read both). If there is no data, roll characters from the manual
   following `reference/random-characters.md` and **save the rolled data to a file
   first**, so the user can audit and edit it.
4. **The one-shot** (`oneshot.txt`, `*.pdf`), if any, for hooks, ties, the crew's
   patron and the like.
5. **Where to write**: the one-shot's folder; the script `make_sheets.py` beside
   the data, sheets in `schede/`. Output names `N_name_alias.xopp/.pdf`, the crew
   `0_banda_<name>`, the merged file `<oneshot>-schede-tutte.pdf`.

Run `bash <skill-dir>/scripts/check_tools.sh` once: it needs `xournalpp`,
`mutool`, `pdftotext`, `qpdf` (or `pdfunite`), Python with Pillow, and prints how
the fonts resolve.

## Step 1 — understand the sheet

Render each page you will fill and **look at it** (`bash
<skill-dir>/scripts/render_pages.sh sheet.pdf /tmp/x/p 90 15`, then Read the PNG).
Write down every box, list, track and rule and what of the data goes into it,
and what stays empty (play-time tracks: stress, harm, XP, conditions).

Then get the geometry from the PDF instead of measuring by hand:

```bash
python3 <skill-dir>/scripts/sheet_geometry.py sheet.pdf --page 15 --overlay /tmp/x/ov15.png
python3 <skill-dir>/scripts/sheet_geometry.py sheet.pdf --page 15 --find "schermire" --find "alias"
```

It prints the printed lines with baselines, the symbol-glyph groups (InDesign
sheets draw dots, checkboxes, diamonds and triangles with Wingdings; the empty and
the pre-filled dot are the same glyph in a different colour), the horizontal
rules, and the small vector shapes. Look at the overlay: each group has an id and
a colour, so you can tell "g3 = the action dots, g5 = item boxes, g7 = the
friend triangles" and check the centres land on the ink. Locate fields by the
label printed next to them (`Page.find`), then the symbols on that line
(`Page.symbols_near`): a script written that way also works on the other
playbook pages of the same kit.

A page with no text layer (scan, outlined fonts) gets a warning: render it at
144 dpi, measure box corners in pixels, convert with `pt = px * 72 / dpi`, and
keep the numbers in one named block at the top of the script. Verify with an
overlay before writing any text.

## Step 2 — write `make_sheets.py`

Copy `scripts/xopp_lib.py` next to the script (the one-shot folder must stay
self-contained; the user rebuilds months later without this skill) and start
from `templates/make_sheets_template.py`. Shape of the script:

- a docstring saying what it builds, from which files, and how to rerun
  (`python3 make_sheets.py`, `--export file.xopp` for a hand-edited file);
- constants: blank PDF path, page size, fonts;
- `PLAYERS = [dict(...)]` — all the data, keys named after the printed labels,
  values in the sheet's language. The user edits this block; make it readable;
- one function per area of the sheet (`header`, `actions`, `abilities`,
  `friends`, `load`, `notes`) returning element strings, and a `sheet_layer(p)`
  that assembles them;
- `main()` that writes every `.xopp`, exports each to PDF, merges them.

What the library gives you (see the docstrings in `xopp_lib.py`):

| Need | Call |
|---|---|
| text on a printed rule | `X.text(x, rule_y - 2, s, size, font)`; shrink to fit with `X.fit_line` |
| a paragraph in a box | `X.paragraphs(paras, x, first_baseline, last_baseline, width)` |
| notes on ruled lines, bold headers, two lines per rule | `X.rules_baselines(first, step, n, per_rule=2)` + `X.notes_block(sections, x0, width, baselines)` |
| flow around printed text inside the notes area | `notes_block(..., widths=[...])` |
| a number centred in a box | `X.centred(cx, cy, "3", 20, BOLD)`; hide a printed default first with `X.rect(...)` (white) |
| fill a rating dot / a printed circle | `X.dot(cx, cy, d)` / `X.disc(cx, cy, r, RED)` |
| ring the chosen printed option | `X.ring_around(pg.find("akoros", xr=..., yr=...))` |
| tick a checkbox | `X.check(*X.sym_center(box_glyph))` |
| fill a printed triangle (friend / rival) | `X.triangle(cx, cy, 0.3 * size, "up")` |
| text on a slanted rule, portrait | `X.text_image(...)` + `X.image(img, left, top, width)` |
| pages | `X.page_pdf(pageno, els, BG_PDF, first, size)`, `X.page_blank(els, size)`, `X.xopp_xml(pages)`, `X.write_xopp`, `X.export_pdf`, `X.merge_pdfs` |

Rules that keep the result readable (the why is in `reference/lessons.md`):

- Write **on** the rule (baseline = rule − 2), labels sit under it. When the label
  precedes the rule on the same line, start after the label.
- Every text shrinks through a list of sizes and **fails loudly** when nothing
  fits. Overflow onto the next box is worse than an error.
- Fill only what creation decides. Tick the suggested load, and say so.
- Marks look like pen: black ink for text and dots, a red disc or a red number
  where the sheet wants a chosen option to stand out.
- Add the pages the player needs at the table as extra background pages of the
  same `.xopp` (item descriptions, the playbook's special page): they cost nothing.
- When the sheet has no room for the character's story, build the **storie
  handout**: an A4 page with four A6 cards (name, subtitle, story with bold
  lead-ins), cut lines, everything shrinking to fit. The older builders in
  `Ronin/oni-no-kizu/make_sheets.py` and `Kulthos/dimmi-nome-adesso/storie/`
  show the card layout.

## Step 3 — build, look, fix

```bash
python3 make_sheets.py
bash <skill-dir>/scripts/render_pages.sh schede/1_name.pdf /tmp/x/name 110 1
```

Read the PNG of **every page of every character**, not only the first: the
second playbook has different ability lengths, the fourth has a printed list
inside its notes box. Check that text sits on its rule, no line crosses a box
edge, dots and ticks are inside their symbols, rings enclose the whole word, and
notes stay clear of printed text. Fix the script, not the `.xopp`, and rebuild.
Two or three rounds are normal.

Typical fixes: the sheet's typo differs from the manual (match the sheet, leave a
comment), a needle contains "fi"/"fl" (ligatures come out swapped; use a shorter
needle), a label is on the rule rather than under it, the notes need
`per_rule=2` or a smaller first size.

## Step 4 — report

Say what is on each sheet and what is a suggestion (load, notes), where the
files are, that the `.xopp` files are editable in Xournal++, and how to rebuild
(`python3 make_sheets.py`) or re-export a hand-edited file. If characters were
rolled, say which choices were dice and which were judgement, with the seed.

## Files in this skill

- `scripts/xopp_lib.py` — the library (copy it next to `make_sheets.py`).
- `scripts/sheet_geometry.py` — what is printed where, with overlay and `--find`.
- `scripts/render_pages.sh` — PDF pages to PNG for the look-at-it step.
- `scripts/check_tools.sh` — dependencies and font resolution.
- `templates/make_sheets_template.py` — the starter script.
- `reference/lessons.md` — the 26 lessons from Rōnin, Kulthos, Blades, Rosewood.
- `reference/xopp-format.md` — the file format, units, text/stroke/image details.
- `reference/random-characters.md` — rolling a legal, varied party from the manual.
