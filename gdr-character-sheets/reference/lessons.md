# Lessons from four one-shots

Everything below was learned the hard way on Rōnin ("Oni no Kizu", A5 landscape
sheet, no text layer), Kulthos ("Dimmi Nome Adesso", booklet with several sheet
pages), Blades in the Dark ("Requiem per un Avvocato", A4 landscape playbooks
made of Wingdings glyphs) and Rosewood Abbey ("Il gregge disperso", option grids
with circles). Read it once before writing a new `make_sheets.py`.

## Reading the sheet

1. **Look at the page first.** Render it at ~90 dpi and read the PNG. Name every
   box, track, list and rule you see and decide what goes in each *before* measuring.
2. **Let the PDF tell you where things are.** `sheet_geometry.py` (over
   `mutool trace`) gives the position of every printed word, symbol glyph, rule and
   small vector shape. Locate a field by the label printed next to it
   (`pg.find("alias")`), then take the dots/boxes on that line
   (`pg.symbols_near(baseline)`). A script written this way survives a different
   playbook page with the same layout (Blades: 4 playbooks, one script).
3. **Symbols are often glyphs, not drawings.** InDesign sheets draw dots, boxes,
   diamonds and triangles with Wingdings/ZapfDingbats. The empty and the
   pre-filled dot are the same glyph in a different colour (`0 0 0 .2` vs
   `0 0 0 1`). The visible mark sits *above* the baseline: centre ≈
   `(x + adv/2, baseline - 0.35 * size)`; a dot's diameter ≈ `0.55 * size`.
4. **Check with an overlay.** Draw what you think you found on a 144 dpi render
   and look. This caught a double y-flip (mutool's `transform` already maps to
   top-left coordinates; do not flip again) and told which glyph group was which.
5. **Ligatures.** Text extracted from the trace stores "fi"/"fl" as "if"/"lf"
   in some fonts ("terriifcato", "inlfuenza"). `Page.find_all` retries with the
   swap; when you search, prefer needles without fi/fl ("gancio elettri").
6. **The sheet has typos.** Match what is printed ("soggiocare", "gioelli",
   "divinitario", "strum. di precisione"), not what the manual says, and leave a
   comment saying why.
7. **No text layer** (scanned / outlined sheets like Rōnin's): render at 144 dpi,
   measure box corners on the PNG in pixels, convert with `pt = px * 72 / dpi`,
   keep the numbers in one clearly named block at the top of the script
   (`STATS = {"vigore": (314, 230), ...}`), verify with an overlay, adjust.
   Slanted rules: give the rule's y at two or three x positions and interpolate.

## Placing text

8. **Write on the rule, not under it.** Labels usually sit *under* their rule
   (NOME under the line). Baseline = `rule_y - 2`. When the label is *before* the
   rule on the same line (COVO ____), start the text at `label_x1 + 6`.
9. **Shrink, do not overflow.** Every text goes through a list of sizes and the
   first that fits wins (`fit_line`, `paragraphs`, `notes_block`). Fail loudly
   (`SystemExit`) when nothing fits: a silent overflow prints over the next box.
10. **Notes areas hold twice what the rules suggest.** Rules 20 pt apart with
    6–7 pt text: put one line on the rule and one midway (`rules_baselines(...,
    per_rule=2)`). Bold section header + body on the same line saves a line per
    section (`notes_block`).
11. **Go around printed text inside a writing area** (Sanguisuga's agents list in
    the NOTE box): collect the printed lines in the area, take their left edge as
    a straight block edge, give those baselines a shorter width (`widths=`).
12. **Aspetto / description lines.** A single printed rule for a 200-char
    description: one line on the rule, the rest in the gap between the label and
    the next rule at a smaller size, or move it to the notes.
13. **Digits in boxes** are centred with `centred(cx, cy, "3", 20, BOLD)`;
    digits are ~0.7 em tall, hence `cy + 0.35 * size` for the baseline. When the
    box already prints a default digit (Rosewood's abilities), hide it with a
    white `rect` first. Mark the *raised* stat in red so the player sees the choice.

## Marking choices

14. **Ring the printed word** for retaggio/background/vizio/dominio/operazione
    (`ring_around(pg.find(...))`): reads like a pen mark and nothing is
    re-typed. Circle lists (Rosewood): a small red `disc` in the printed circle;
    the "invent your own" slot gets the dot plus the value written on its rule.
15. **Dots for ratings** overwrite pre-filled dots harmlessly: fill dots
    `[:rating]` from the left, the playbook's defaults included in the rating.
16. **Triangles / checkboxes:** fill the printed triangle with a polygon a bit
    smaller than the outline (`triangle(..., margin=0.9)`); tick boxes with a
    `check`. An item with two boxes gets both ticked.
17. **Suggested load / equipment:** tick it, say in the reply that it is a
    suggestion the player can erase in Xournal++. A one-shot wants to start fast.
18. **Leave play-time tracks empty** (stress, harm, XP, conditions, money at 0).
    Fill only what is decided at creation.

## The data

19. **The user's per-character text files are richer than the one-shot PDF**
    (load suggestions, ties between characters, advice to the player). Read both;
    take the sheet fields from the txt.
20. **Keep the data as one `PLAYERS = [dict(...)]` block** at the top of the
    script in the sheet's own words, with the keys named after the printed
    labels, so the user can edit a value and rebuild. Random characters: write the
    rolled data there too (see random-characters.md), never only in memory.
21. **Notes go on the sheet** when there is room (role in the score, ties,
    beliefs, tips). When the sheet has no room (Rōnin's tiny description box,
    Rosewood's no-background sheet) build the **storie handout**: one A4 page,
    four A6 cards (cut lines), name in bold, subtitle in italic, story paragraphs
    with bold lead-ins, all shrinking to fit.

## Building and checking

22. **One `.xopp` per character + its PDF + one merged PDF** for printing. Add the
    pages the player needs at the table as extra background pages (item
    descriptions, the Sentiero page in Kulthos): they cost nothing.
23. **Support `--export FILE.xopp`** so a hand-edited file can be re-exported with
    the right fonts without rebuilding.
24. **Fonts:** the user's fontconfig maps everything to Cascadia Code; export and
    measure with an empty `XDG_CONFIG_HOME` (`xopp_lib` does). Liberation Sans is
    dense and legible at 6 pt on printed forms; Georgia suits story handouts.
25. **Always render and look** (`render_pages.sh`, then Read the PNG) at every
    page of every character before reporting. Check: text on its rule, nothing
    crossing a box edge, marks inside their circles, notes clear of printed text,
    the second/third character too (the first one always looks fine).
26. **Report what was filled and what is a suggestion**, the output paths, and
    that the .xopp files are editable in Xournal++.
27. **`fc-match` and style names.** `fc-match "Liberation Sans Bold"` silently
    returns the *default* font (the style words are read as part of the family),
    so text measured that way is wrong. The pattern is `Liberation Sans:bold`
    (`xopp_lib.fc_pattern` converts). Pango, which Xournal++ uses, accepts the
    plain "Liberation Sans Bold" in the element, so keep that spelling there.
28. **Vector sheets.** When a sheet draws its circles/boxes as paths instead of
    glyphs (Rosewood), `Page.small_shapes()` lists them with centres: the 5x5
    curved ones are the option circles, grouped by row and column. The same
    `find()` + "shapes on this line" approach works; no hand measuring.
