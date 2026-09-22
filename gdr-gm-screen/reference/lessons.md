# Lessons — writing and rendering, learned on Blades, Rōnin, Rosewood, Kulthos, The Walking Dead

## Writing

1. **Write for the GM mid-scene, in the manual's language.** Imperative and
   second person ("tira", "scegli una", "segna"), never "the player may
   choose to". Italian manual → Italian screen, English → English; the game's
   own terms stay exactly as the book spells them (capitalised if the book
   does).
2. **Bold is for the game term or the number, once per line.** `<b>Rischiosa</b>`,
   `<b>2 stress</b>`, `<b>+1d</b>`. A line where everything is bold has nothing
   bold. Italic only for move triggers (`.trig`) and asides.
3. **Compress with ` · `.** A list of short alternatives is one line joined by
   middle dots, not five bullets. A bullet holds one rule and its exception.
4. **Tables for anything with three or more value pairs.** Success ladders,
   difficulty numbers, weapons, prices, random tables (`<td class="c die">`
   for the die result). Zebra rows come free.
5. **Numbered `<ol>` or a `.box` for a procedure** the GM walks through in
   order (the action roll's steps, the session's phases, the downtime
   sequence). The `.box` title (`.bt`) is the name the GM will say aloud.
6. **Paraphrase, do not copy.** The screen condenses the rules in your words;
   do not lift paragraphs from the book. Short official phrasings that *are*
   the rule (a move's trigger, a result name) are fine.
7. **Cite the page in a comment** after each `<h2>`: `<!-- pdf p.52-54 -->`.
   The user checks the screen against the book; the comment says where.
8. **No rule you are not sure of.** When two passages disagree or the
   extracted text is garbled, read the page image (`pdftoppm -f N -l N -r 80`)
   or leave the rule out and list it in the report as unverified.
9. **The sub-heading line lists the sections in order.** It is the index the
   GM reads on the top edge of the screen.
10. **Density check before polishing.** Count characters per page
    (`render_schermo.sh` prints the free space). Fill to within ~6 mm of the
    footer; columns within ~8 mm of each other. Move a section across the
    column or the page before shrinking the font.

## Layout

11. `.page` is 296 mm tall, not 297: at 297 Chromium rounds up and emits a
    blank fifth page.
12. Never `overflow: hidden` on `.page`: overflow must show up as a fifth
    page and in the measure, not be silently clipped.
13. Per-screen font size lives in `<style id="schermo-overrides">`
    (`body { font-size: 7.3pt; }`). Stay between 7.2 and 8 pt. Do not touch
    the inlined `schermo-css` block: `new_schermo.sh --refresh-css` overwrites
    it.
14. `&` in HTML text is `&amp;` — a bare `&` in a title renders but breaks the
    checker's grep of `<h1>`.
15. A full-width table under the columns (`<h2>` + `<table class="tiny grid">`
    directly in `.page`) is the place for the wide list (actions, classes,
    skills): three or four columns of short cells.
16. A column that ends 20 mm early is fixed by moving one section, not by
    padding: pick the section on the other column whose height matches the gap.

## Rendering

17. **Chromium only, and the real binary.** Chrome, Chromium, Brave, Edge all
    work (same engine). `render_schermo.sh` looks first for the actual
    executables (`/opt/google/chrome/chrome`, `/opt/brave.com/brave/brave`, the
    macOS app bundles), then for names on PATH; `SCHERMO_CHROME=/path`
    overrides. The names on PATH (`google-chrome`, `brave-browser`) are bash
    wrappers: a time limit that kills the wrapper leaves the browser itself
    alive, holding the profile, and every later run hangs. That cost an hour.
18. **The first headless run on a new profile hangs** (Brave 1.94 spends it
    downloading components and never prints; `about:blank` under a
    virtual-time budget never finishes either). The script keeps a profile in
    `~/.cache/gdr-gm-screen/profile`, warms it once with a 45 s limit, probes
    it by printing a tiny local page, then every render takes about a second.
    After every limited run it kills whatever still holds that profile. Two
    renders at the same time would fight over the profile: run them one after
    another.
19. **A user fontconfig can hijack the fonts** (the author's machine aliases
    every family to a monospace font). The script renders with a clean
    fontconfig that maps serif → Liberation Serif and sans → Liberation Sans;
    check with `pdffonts out.pdf` if a PDF looks wrong.
20. `--run-all-compositor-stages-before-draw --virtual-time-budget=10000` make
    the old headless mode wait for layout; `--no-pdf-header-footer` removes
    Chromium's date/URL furniture.
21. The measure step injects a script into a temporary copy of the HTML
    (`.schermo-probe-*.html`, next to the file so relative links resolve) and
    reads the numbers back from `--dump-dom`. Screen and print layout are the
    same because `.page` has a fixed size.
22. Always look at the PNGs (`--png DIR`), every page: the numbers catch
    overflow and imbalance, not a table whose column is too narrow, a header
    wrapped to two lines, or a `.box` split awkwardly at a column's foot.

## From The Walking Dead (first screen built with this skill, 11 rounds)

23. **A cut helps only if it drops a whole line.** A column line is ~3.2 mm and
    ~85 characters at 7.4 pt. Three rounds of word trimming left the measure at
    exactly the same numbers. Merge two table rows or two bullets instead; if
    the numbers repeat, the trim did nothing.
24. **The font-size override is a fine adjustment, not a lever.** 0.1 pt is
    worth ~3.5 mm per page; 7.6 → 7.4 pt bought 7 mm on a page that was 70 mm
    over. Cut and move first, then use the override for the last 10 mm.
25. **An overflowing page's tail prints at the top of the next PNG.** When
    page 3's preview starts with a table that belongs to page 2, page 2
    overflows; the measure says so too.
26. **Short cells wrap.** "1 giorno", "B ore", "Min. · ore" break onto two
    lines in a narrow column: `class="nw"` on the cell.
27. **Keep the `.sub` index in sync.** Every time a section moves, the
    subtitle drifts; `render_schermo.sh` now warns about sub-line items that
    match no `<h2>` on the page.
28. **Read the manual in small bites.** `manual.py page` over more than three
    pages overflows the tool output; dump a chapter with `-o FILE` and Read
    it in chunks.
