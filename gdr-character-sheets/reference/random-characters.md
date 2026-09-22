# Random characters from the manual

When the user gives no character data ("make 4 random characters"), roll them
from the manual's own creation procedure, then treat the result exactly like a
user-supplied data file. The point is a party that is legal by the rules,
varied, and playable in a one-shot without the player reading the book.

## Steps

1. **Find the creation chapter.** Prefer `manual-text/` (one markdown per chapter,
   `<!-- p.N -->` markers; see its README) and grep for "creazione", "creare il
   personaggio", "character creation", "libretto", "classe", "playbook". Fall back
   to `pdftotext -f A -l B -layout manual.pdf -` on the pages the index names.
   Do not read a whole rulebook into context: grep, then read around the hits.
2. **Write the procedure down as a checklist** with page numbers before rolling:
   every choice (class/playbook, heritage, background, vice, stats budget,
   skills, abilities, gear/load, contacts, name), its options table, and its
   constraints ("7 dots: 3 from the playbook + 4 chosen, max 2 per action at
   creation", "one special ability", "two Confratelli may not share a
   Competenza"). This checklist goes in the data file header so the user can
   audit the result against the book.
3. **Roll with `random`** in Python, print the seed, and record it in the data
   file so the party can be rebuilt. Use the book's tables where they exist
   (names, looks, backgrounds); otherwise pick from the setting's lists you found
   (districts, factions, NPC names) rather than inventing generic ones.
4. **Enforce party variety**: different classes/roles, different backgrounds,
   at least one social, one physical and one technical/arcane character when the
   game has such axes. Re-roll a duplicate.
5. **Give every character a one-paragraph hook** tied to the one-shot when there
   is one (`oneshot.txt` / the one-shot PDF): why they are here, one tie to
   another character, one thing they want. Keep it short and in the sheet's
   language. Do not add rules text from the book verbatim beyond names of
   abilities and one-line summaries (copyright and space).
6. **Save the data file** next to the script (`personaggi_random.txt` or
   `.json`) in the same shape the user's own files use in that folder (look for
   an existing `personaggi*/`, `*.txt` with "SCHEDA PERSONAGGIO" headers). Then
   build the sheets from it.
7. **Tell the user which choices were rolled and which were judgement calls**
   (e.g. "the load is a suggestion", "the name comes from the book's table on
   p. 61").

## Sanity checks before building

- Point budgets add up (stats, skills, dots).
- Every referenced ability/item/move exists on the sheet page you will fill:
  run `sheet_geometry.py --find` for each name; a miss means a typo in the book
  or on the sheet, match the sheet.
- No two characters share a name or a role.
