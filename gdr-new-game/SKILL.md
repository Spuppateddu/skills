---
name: gdr-new-game
description: Add a new tabletop RPG system to the gdr-companion app, starting from its character sheet (PDF or image) and, when available, its rulebook PDF. Reads the sheet, maps every box on it to a panel the app ALREADY has (relabelling a tab instead of building a new one), keeps rules text out of the code for copyright reasons by storing it as free text the player types, seeds the game and its config idempotently so `migrate:fresh --seed` gives a fresh server every game, and writes a `<game_slug>-character-sheet-plan.md` that the plan-execute skill then builds. Use when the user says e.g. "add this game to gdr companion", "implement this character sheet", "new game system", or hands over a character sheet plus a manual.
---

# gdr-new-game

You are the **project manager**. You read the sheet, you decide what the app must show,
you write the plan. `plan-execute` is the **software engineer** — it writes the code.
Never write app code yourself in this skill. Your deliverable is one markdown file.

This skill only works inside `/home/ale/code/gdr-companion`. If the working folder is
something else, say so and stop.

**`<skill-dir>` in the commands below means the folder holding this `SKILL.md`** —
`reference/`, `templates/` and `scripts/` sit next to it. Substitute the real path; do not
run the commands with the placeholder still in them.

## What you must produce

`plan/to-start/<game_slug>-character-sheet-plan.md` (the gitignored plan folder the
`plan-write` and `plan-execute` skills share), in the exact format `plan-execute`
parses, then hand it to `plan-execute` right away.

---

## Step 1 — collect the inputs

You need, at minimum, **the character sheet** as a PDF or an image. The **rulebook** PDF
is optional but read it whenever it is there — it names the attributes, the tracks and
the tabs far better than the sheet alone.

Ask the user for anything missing:

1. The character sheet file path.
2. The rulebook file path, or "no manual".
3. The **game name** as it must appear in the UI (Italian, with accents: `Rōnin`,
   `Sineréquie`).
4. Whether the game ships **enabled** (visible to players) or disabled.

**The slug is always lowercase with underscores, never hyphens:** `rosewood_abbey`,
`ultima_torcia`, `blades_in_the_dark`. Derive it from the name and show it to the user.
Hyphens break the panel-field slug parser in `CharacterSheet.tsx` — see
`reference/ARCHITECTURE.md`.

Check the slug is free before anything else:

```bash
bash <skill-dir>/scripts/check_games.sh
```

It prints every slug the repo knows and where each one is wired. If your slug is already
there, stop and ask the user whether this is a rename or a mistake.

**It exits 1 today**, and that is expected — it is reporting the seeder drift described in
Step 5, not a failure of yours. Keep its list of broken slugs: Phase 1 of the plan fixes
them.

## Step 2 — read the PDFs

Do not push whole rulebooks into context. Pull the text out first:

```bash
bash <skill-dir>/scripts/extract_pdf.sh <out-dir> <sheet.pdf> [manual.pdf]
```

It writes one `.txt` per PDF and tells you the page count and whether the file has a text
layer. Three cases:

- **Text layer** → read the `.txt`. For a long book, grep it; never read all of it.
- **Scanned sheet** (a few pages, no text) → the script renders them to PNG. Read the
  PNGs with the Read tool and look at the boxes.
- **Scanned book** (many pages, no text) → the script stops and tells you to narrow it
  down. Ask the user which pages describe the character sheet and the attributes, then
  re-run with `PAGES=<first>-<last>` (max 20 pages at a time). Rulebooks in this repo are
  often scans — `Ronin.pdf` is 128 scanned pages.
- **An image sheet** (PNG/JPG) → read it directly with the Read tool.

Then read, in this order:

1. **The character sheet.** This is the contract. Every box, track, line and checkbox on
   it is something the app must show. Write the list down.
2. **The manual, only where it explains the sheet.** Search it for the attribute list,
   the track lengths, the names of the sections. Skip the setting chapters, the GM
   advice and the adventure — none of it reaches the app.

## Step 3 — decide the copyright line

**This rule is fixed. Apply it the same way every time.**

| Goes in the repo (static data) | Never goes in the repo (free text) |
|--------------------------------|------------------------------------|
| Attribute and skill **names** | Any description of what they do |
| Tab and field **labels** | Rules paragraphs, procedures, examples |
| Name / nickname / birthplace lists | Move and spell **effects** |
| Item, trade and role **names** | Outcome tables, "on a 7-9…" text |
| Track **length** as a number (7 boxes) | Anything you would call prose |

A move called *Confessare* is a label — seed it. What *Confessare* does is rules text —
the panel renders an **empty text field** and the player types it in from their own copy
of the book. When in doubt, it is free text.

Say this out loud in the plan's *Goal* so the executing agent cannot drift.

## Step 4 — map the sheet onto panels that already exist

This is the whole job, and the thing the user cares about most: **reuse a tab, change its
label. Do not build a new panel because the game uses a different word.**

Read `<skill-dir>/reference/PANEL_CATALOG.md`. For every section of the sheet, walk this ladder and
stop at the first rung that fits:

1. **An existing `Default*` panel with its label changed.** The game calls spells
   *Divinazioni*? That is `DefaultSpells` with `entityName="Divinazione"`. Objects are
   *Reliquie*, money is *Ryo*? `DefaultObjects` with `entityName` and `moneyLabel`.
   This is the answer far more often than it looks.
2. **An existing `Default*` panel that needs one new optional label prop.** Add the prop
   with a default equal to today's hardcoded string, so every other game is untouched.
   `DefaultSpells.entityName` and `DefaultObjects.moneyLabel` were both added this way.
3. **A config-driven panel** — `DefaultStatistiche` and `DefaultSkills` render whatever
   `attributes` / `skills` the database holds for the game. A game with plain numeric
   stats needs **no component at all**, only rows in `character-config.json`.
4. **A new panel component**, and only now. Justify it in the plan in one sentence: what
   the sheet does that no existing panel can render.

A new panel is only justified by a **different shape**, never a different word. A track
of 7 checkboxes each with a memory line next to it is a new shape. A list of named things
with a description is not — that is `EntityList`.

**Keep the logic out of the component.** Game data lives in
`gdr-companion-frontend/constants/<game_slug>/*.ts` as frozen exported arrays. The panel
reads the array and renders it. A panel that hardcodes a list, a length or a rule is
wrong — the plan must say which constants file holds it.

## Step 5 — decide what is seeded

Everything the database needs is seeded from code committed to the repo, so
`migrate:fresh --seed` on a new server or in a test gives every game. Two files, always
both:

- `database/seeders/GameSeeder.php` — the `games` row. It uses `firstOrCreate` keyed on
  `slug`, so re-running never duplicates.
- `database/seeders/data/character-config.json` — attributes, skills, races, classes,
  alignments. `CharacterConfigSeeder` upserts them keyed on (game, slug). Attribute and
  skill slugs are **prefixed with the game slug**: `rosewood_abbey-vigore`.

**The trap:** `CharacterConfigSeeder` looks the game up by slug and silently skips rows
whose game it cannot find. A game added to the JSON but not to `GameSeeder` loses its
whole config on a fresh database, with no error. `kulthos`, `ronin` and
`blades_in_the_dark` are all in that state right now.

So **every plan this skill writes ends Phase 1 with the guard tasks**: add any slug found
in `character-config.json` but missing from `GameSeeder.php`, and make
`CharacterConfigSeeder` warn loudly instead of skipping in silence. The template already
carries them — fill in whatever `scripts/check_games.sh` reports as missing, and keep the
tasks even when it reports nothing (they then just confirm it).

## Step 6 — ask the user what the sheet does not say

Batch the questions, ask them once. Always ask:

1. Any box on the sheet you could not name or could not tell apart from another.
2. Attributes: what is the range (min / max), and what does a character start at?
3. Tracks: how many boxes, and does ticking one do anything the app must show?
4. Which tabs the game does **not** want at all (most story games have no armours).
5. Whether the game needs a bespoke creation form (`GAME_FORMS` in
   `components/character/gameForms.ts`) or the generic `DefaultCharacterForm` is fine.
   The generic one is fine unless creation itself has steps.
6. Anything the manual states two ways.

Everything still open after that goes under **Open questions** in the plan, and you tell
the user the executing agent is instructed to stop when it reaches one.

## Step 7 — write the plan

Create the plan folder first (safe to re-run; it makes `plan/to-start/`,
`plan/in-progress/`, `plan/done/` at the repo root and gitignores them):

```bash
bash <skills-repo>/plan-execute/scripts/plan_context.sh init
```

Copy `<skill-dir>/templates/GAME_PLAN_TEMPLATE.md` to
`plan/to-start/<game_slug>-character-sheet-plan.md` and fill it in. Keep every heading
and the task format exactly — `plan-execute` parses the checkboxes.

The template already holds the phases every game needs, the filled-in Projects table, the
gdr-companion repository conventions, and the seeder guard tasks. Your work is the
content of the tasks.

Task-writing rules, for a reader that cannot ask you anything:

- One task = one change one command can prove. Split anything bigger.
- Exact paths, exact strings, exact numbers. No "appropriate", no "as needed", no "etc.".
- Name a thing the same way every time. Never a pronoun pointing at an earlier task.
- A backend task and a frontend task are never the same task.
- Every task carries `files:`, `do:`, `done-when:`, `verify:`. Add `depends-on:` when
  order matters.
- Seeder tasks get **no test** — verify them with a `php artisan tinker --execute=…`
  count instead. Which files do get tests is written in the template's conventions
  section; follow it exactly and mark each task with what it must write.

If a plan with that name already exists in any of `plan/to-start/`, `plan/in-progress/`
or `plan/done/` (`plan_context.sh list` shows them), show the user and ask before
overwriting — it may be half-executed.

## Step 8 — prove it parses, then build it

```bash
bash <skills-repo>/plan-execute/scripts/plan_context.sh status plan/to-start/<game_slug>-character-sheet-plan.md
```

The task count must be right and `NEXT:` must point at the first task. `PLAN_CHECKLIST:
none` means the checkbox format is broken — fix it before going on.

Then tell the user, in a few lines: the file path, the phases, the task count, which
panels you are reusing versus building, and every Open question.

Then **invoke the `plan-execute` skill on that file straight away** — the user has asked
for the handoff to be automatic. Do not wait for a go-ahead, and do not start coding by
hand instead.

## Reference

- `<skill-dir>/reference/ARCHITECTURE.md` — where a game lives in gdr-companion: the seeders, the
  panel-field slug format, the wiring in `CharacterSheet.tsx`, i18n, tests.
- `<skill-dir>/reference/PANEL_CATALOG.md` — every panel that already exists, what it renders, and
  which label props it takes.
