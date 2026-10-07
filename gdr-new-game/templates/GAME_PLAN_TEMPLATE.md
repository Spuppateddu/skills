# <GAME NAME> character sheet — implementation plan

<!-- Written by the gdr-new-game skill. Executed by an AI agent, not a human. -->

## READ THIS FIRST

You are an AI agent. This file is your instructions. Read this whole file before you
write any code. Do exactly what this file says. Do not do anything this file does not say.

### Task states

Every task has ONE state. The bracket and the word always mean the same thing:

| Bracket | Word    | Meaning |
|---------|---------|---------|
| `[ ]`   | TODO    | Not started. |
| `[~]`   | DOING   | Started, not finished. |
| `[x]`   | DONE    | Finished, and its `verify:` command passed. |
| `[!]`   | BLOCKED | Cannot continue. A `blocked-by:` line says why. |

### Where do I start?

1. Read the `Progress:` line below.
2. Read the task list from the top. Find the FIRST task that is not `[x]` DONE.
3. If that task is `[~]` DOING, a previous agent stopped in the middle of it. Read the
   task. Look at the files it names. Work out what already exists. Continue from there.
4. If that task is `[!]` BLOCKED, read its `blocked-by:` line. If the blocker is now
   DONE, change the task back to `[ ]` TODO and start it. If the blocker is not DONE,
   stop and tell the user.
5. That task is your work now. Finish it, mark it DONE, then go back to step 2 and take
   the next task. Keep going until every task is DONE.

### How do I update this file?

- Before you start a task: change `[ ]` to `[~]`, and change `TODO` to `DOING`. Save the file.
- After the task's `verify:` command passes: change `[~]` to `[x]`, and change `DOING`
  to `DONE`. Save the file. Then update the `Progress:` line.
- Change the bracket AND the word every time. They must never disagree.
- This file lives in `plan/to-start/`, `plan/in-progress/` or `plan/done/`. Before you
  start the FIRST task, if this file is in `plan/to-start/`, move it to
  `plan/in-progress/`. When the LAST task is DONE, move it to `plan/done/`. Never move it
  to `plan/done/` while any task is not DONE. The `plan/` folder is gitignored: never
  commit this file.
- Never delete a task. Never reorder tasks. Never add a task.
- Never write `[x]` DONE unless you ran the task's `verify:` command and it passed.
- If you cannot finish a task, leave it `[~]` DOING and tell the user what stopped you.
  A wrong `[x]` makes the next agent skip unfinished work.

Progress: 0/<N> tasks done

---

## Rules you must follow

1. Do only what a task says. Do not add features, endpoints, options, or abstractions
   that no task asks for. Do not refactor code that no task mentions.
2. Do one task at a time: finish it, verify it, mark it DONE, write one line about it,
   then start the next task right away. Do the WHOLE plan in one run. Do not stop between
   tasks or phases, and do not ask "shall I continue?". Stop ONLY when:
   - the user told you to stop, or to do only some tasks;
   - you need a human: a task is unclear (rule 11), you reach an Open question, or you
     need a password, a login, a manual step, or the user's OK for an action;
   - you are stuck: a task is BLOCKED, its `verify:` still fails after you tried to fix
     the code, or a tool or service you need is broken.
   When you stop, say exactly what you need to continue.
3. Look at the Projects table. Find the row for the project this task belongs to. Then
   read "Which files get a test file" below — in this repository the test rule is per
   FILE, not only per project, and each task states what it must write.
4. When a task says to write a test: write the test FIRST. Run it. Watch it fail. Then
   write the code until it passes. A test that passes before you write the code tests
   nothing and must be rewritten.
5. When a task says to write no test file, write none. Do not add one anyway.
6. Run the task's `verify:` command before you mark the task DONE. It must pass.
7. Never make a test pass by weakening it. Do not delete assertions. Do not use `skip`,
   `xfail`, or `markTestSkipped`. Fix the code instead.
8. Run each command in the directory the task names. A passing backend test does not
   prove a frontend task works.
9. **Never run `git commit`, `git push`, or open a pull request.** The user commits by hand.
10. Write code in the same style as the code already in that project.
11. If a task is unclear, or the code does not match what the task says, STOP. Ask the
    user. Do not guess. The same applies to anything under **Open questions**.
12. If a task cannot work as written because the plan is missing something, add the
    smallest thing needed to make it work, and write what you added and why under
    **Deviations** at the bottom of this file.
13. **Copyright.** Names and labels may be written into the code. Rules text may not.
    Never copy a description, an effect, a procedure or an outcome table out of the
    manual into a file — those are empty free-text fields the player fills in. If a task
    seems to ask you to copy prose, it does not: leave the field empty and say so under
    **Deviations**.

---

## Projects

| Name | Directory | Language / framework | Run one test | Run all tests | Lint / format |
|------|-----------|----------------------|--------------|---------------|---------------|
| backend | `gdr-companion-backend/` | PHP 8.2+ / Laravel 12 | `./backend-test.sh --filter=<TestName>` (run from repo root) | `./backend-test.sh` (run from repo root) | `docker compose exec -T backend vendor/bin/pint --test && docker compose exec -T backend vendor/bin/phpstan analyse --no-progress --memory-limit=1G` (run from repo root) |
| frontend | `gdr-companion-frontend/` | TypeScript / Next 15 / React 19 | `cd gdr-companion-frontend && npx vitest run <path/to/file.test.tsx>` | `cd gdr-companion-frontend && npm test` | `cd gdr-companion-frontend && npx eslint . && npx tsc --noEmit` |

**Backend commands need Docker.** This repo has no local PHP — `php` and `vendor/bin/*`
only exist inside the `backend` container. Before any backend command, run
`docker compose up -d mysql backend` from the repo root
(`/home/ale/code/gdr-companion`) if `docker compose ps` shows nothing. All backend
commands in this plan run from the repo root, not from `gdr-companion-backend/`. The
repo-root `.env` sets `BACKEND_PORT=8001`. If `docker compose up -d backend` fails
because that port is taken, STOP and ask the user before changing any port, `.env` or
`docker-compose.yml`.

### Repository conventions

- Read `gdr-companion-frontend/AGENTS.MD` before every frontend task.
- Code and comments in English. Table, column and slug names in English.
  **Every string the player sees in the browser is Italian.**
- No CSS framework. CSS Modules (outer class `.root`, camelCase, no prefix) or the shared
  `gdr-` classes. Colour literals only in `styles/tokens.css`; everywhere else
  `var(--…)`. State and variant travel as `data-*` attributes, never as class names.
- Components stay under ~600 lines. Split if they grow past that.
- Backend PHP files start with `declare(strict_types=1);`.
- **No new i18n dictionary for this game.** `hooks/useGameTranslation.ts` has a hardcoded
  `GameSlug` union that stops at `tenebrae`; `ultima_torcia`, `kulthos`, `ronin` and
  `rosewood_abbey` are all deliberately absent and work by calling
  `t('characters.panels.<game_slug>.xxx', 'Testo Italiano')` and relying on the fallback.
  Do the same. Never create `constants/<game_slug>/i18n/*.json`.
- **The game slug uses underscores, never hyphens.** `CharacterSheet.tsx` splits panel
  field slugs on `-`; a hyphen in the game slug breaks the parse.

### Which files get a test file

- **Always:** `components/ui/*`, `components/character/panels/Shared/*`, and
  `components/character/CharacterSheet.tsx`.
- **Only when it holds a real decision branch:** a per-game panel in
  `components/character/panels/<game_slug>/*.tsx`. That is why `panels/kulthos/` has
  three test files and `panels/ronin/` two, while `panels/tenebrae/`,
  `panels/ultima_torcia/`, `panels/dnd/`, `panels/sinerequie/`, `panels/cyberpunk/` and
  `panels/default/` have none at all.
- **Never:** any seeder, `database/seeders/data/character-config.json`, and plain
  constants files that only export frozen arrays. There is no seeder test anywhere in
  `gdr-companion-backend/tests/`. Verify those tasks with an observable database fact
  (`php artisan tinker --execute=…`) or with `npx tsc --noEmit`.

**Each task below says whether it writes a test file. Do not add a test to a file no task
marks for one, and do not skip a test a task asks for.**

## Goal

<One paragraph. What must be true when every task is DONE: the game exists in the games
table, its config is seeded, its sheet renders these tabs, and a fresh
`migrate:fresh --seed` reproduces all of it.>

**Panels reused vs. built.** <One line per sheet section: which existing panel covers it
and under what Italian label, or — for the few that need one — why no existing panel can
render that shape.>

**Copyright.** Only names and labels are written into the repo. Every description,
effect and rules paragraph is an empty free-text field the player fills in from their own
copy of the book.

## Out of scope

- Any rules logic: dice rolling, roll outcomes, automatic advancement, derived values the
  sheet does not print.
- Copying any descriptive text out of the manual into the repo.
- New i18n dictionary files for this game.
- Changing how any other game renders. A new optional prop on a shared panel must default
  to the string that panel shows today.
- Committing or pushing anything.
- <anything else the user ruled out>

---

## Phase 1 — Backend: seed the game and its config

Goal: the `games` table has the `<game_slug>` row and the `attributes` (and `skills`, if
any) tables have this game's rows, all seeded idempotently from code in the repo, and no
game already in `character-config.json` is missing from `GameSeeder`.
Depends on: nothing

- [ ] T1.1 — TODO — backend: Add the `<game_slug>` row to `GameSeeder.php`
      files: `gdr-companion-backend/database/seeders/GameSeeder.php`
      do:
        1. From the repo root, run `docker compose up -d mysql backend`.
        2. Open `gdr-companion-backend/database/seeders/GameSeeder.php`. Inside the
           `$games` array, after the last existing entry, add this entry, keeping the
           surrounding formatting:
           ```php
           [
               'slug' => '<game_slug>',
               'name' => '<Game Name>',
               'description' => '<one Italian line, or null>',
               'enabled' => <true|false>,
           ],
           ```
        3. Do not change any other entry in `$games`. Do not change the `foreach` loop —
           its `Game::firstOrCreate(['slug' => ...])` is what stops duplicates.
        4. From the repo root, run
           `docker compose exec -T backend php artisan db:seed --class=GameSeeder`.
        5. Write no test file for this task. See "Which files get a test file".
      done-when: the `games` table has exactly one row whose slug is `<game_slug>`.
      verify: `docker compose exec -T backend php artisan tinker --execute="echo \App\Models\Game::where('slug','<game_slug>')->count();"` prints `1` (run from the repo root)

- [ ] T1.2 — TODO — backend: Add the `<game_slug>` attributes to `character-config.json`
      files: `gdr-companion-backend/database/seeders/data/character-config.json`
      depends-on: T1.1
      do:
        1. Open `gdr-companion-backend/database/seeders/data/character-config.json` and
           find the top-level `"attributes"` array. Read an existing object whose
           `"game_slug"` is `"rosewood_abbey"` to copy the exact key order and formatting.
        2. Append these objects to the `"attributes"` array. Every one uses
           `"game_slug": "<game_slug>"`, `"value_type": "<number|text>"`,
           `"default_value": "<value>"`, `"min_value": <n>`, `"max_value": <n>`,
           `"is_required": <true|false>`, `"has_value_total": false`, and `null` for
           `"calculation_formula"`, `"category"`, `"short_name"` and `"italian_suit"`:

           | slug | name | order |
           |------|------|-------|
           | `<game_slug>-<attr>` | `<Nome>` | 1 |

        3. <Say explicitly which of `"skills"`, `"races"`, `"classes"`, `"alignments"`
           get rows and which get none.>
        4. From the repo root, run
           `docker compose exec -T backend php artisan db:seed --class=CharacterConfigSeeder`.
        5. Write no test file for this task.
      done-when: the `attributes` table has exactly <N> rows joined to the game whose slug
      is `<game_slug>`.
      verify: `docker compose exec -T backend php artisan tinker --execute="echo \App\Models\Attribute::whereHas('game', fn(\$q) => \$q->where('slug','<game_slug>'))->count();"` prints `<N>` (run from the repo root)

- [ ] T1.3 — TODO — backend: Add every game missing from `GameSeeder.php` but present in `character-config.json`
      files: `gdr-companion-backend/database/seeders/GameSeeder.php`
      depends-on: T1.1
      do:
        1. `CharacterConfigSeeder` looks each row's game up by slug and skips the row when
           the game does not exist. These slugs have rows in `character-config.json` but
           no entry in `GameSeeder.php`, so a fresh database loses their whole config:
           <list from scripts/check_games.sh — today: kulthos, ronin, blades_in_the_dark>
        2. Add one entry to the `$games` array for each, keeping the existing formatting:
           <a table of slug / name / description / enabled, one row per missing game>
        3. Change nothing else in the file.
        4. From the repo root, run
           `docker compose exec -T backend php artisan db:seed --class=GameSeeder` and then
           `docker compose exec -T backend php artisan db:seed --class=CharacterConfigSeeder`.
        5. Write no test file for this task.
      done-when: every distinct `game_slug` in `character-config.json` has a matching row
      in the `games` table.
      verify: `docker compose exec -T backend php artisan tinker --execute="\$s=collect(json_decode(file_get_contents(database_path('seeders/data/character-config.json')),true))->flatten(1)->pluck('game_slug')->filter()->unique(); echo \$s->diff(\App\Models\Game::pluck('slug'))->count();"` prints `0` (run from the repo root)

- [ ] T1.4 — TODO — backend: Make `CharacterConfigSeeder` warn instead of skipping in silence
      files: `gdr-companion-backend/database/seeders/CharacterConfigSeeder.php`
      depends-on: T1.3
      do:
        1. Open `gdr-companion-backend/database/seeders/CharacterConfigSeeder.php`. It
           contains five copies of this guard, one per array it seeds:
           ```php
           $gameId = $games[$row['game_slug']] ?? null;
           if (! $gameId) {
               continue;
           }
           ```
        2. In every one of the five, add a warning before the `continue;` so the skipped
           slug is visible:
           ```php
           if (! $gameId) {
               $this->command?->warn("CharacterConfigSeeder: unknown game_slug '{$row['game_slug']}' — row skipped.");
               continue;
           }
           ```
        3. Change nothing else. Do not change the `updateOrCreate` calls.
        4. Write no test file for this task.
      done-when: running the seeder with a `game_slug` that has no game prints a warning
      naming that slug, and seeding with every game present prints none.
      verify: `docker compose exec -T backend php artisan db:seed --class=CharacterConfigSeeder` runs with no warning line, and `docker compose exec -T backend vendor/bin/pint --test` passes (run from the repo root)

---

## Phase 2 — Frontend: the <GAME NAME> constants

Goal: every list this game needs is a frozen exported array in
`gdr-companion-frontend/constants/<game_slug>/`, holding names and labels only — no rules
prose, no logic.
Depends on: nothing

<One task per constants file. Each one names the exact file, the exact exported const
names, and the exact entries. State in each task that the file exports data only and gets
no test file; verify with `cd gdr-companion-frontend && npx tsc --noEmit`.>

---

## Phase 3 — Frontend: relabel the shared panels this game reuses

Goal: the `Default*` panels this game reuses accept the Italian word this game uses, and
every other game keeps exactly the string it shows today.
Depends on: nothing

<One task per new optional label prop. Each one: add `<prop>?: string` to `PanelProps`,
default it in the destructured parameter list to the string the component hardcodes
today, pass it through instead of the hardcoded string, change nothing else.
`components/character/panels/default/*.tsx` has no test coverage in this repo — these
tasks write no test file and verify with `cd gdr-companion-frontend && npx tsc --noEmit`.

Delete this whole phase if the game reuses no panel that needs a new label.>

---

## Phase 4 — Frontend: the <GAME NAME> panel components

Goal: the sheet sections that no existing panel can render have their own component under
`components/character/panels/<game_slug>/`, each reading its data from Phase 2's constants
and holding no rules logic.
Depends on: Phase 2

<One task per component. Each one names: the file, the exact props interface (always
`additionalData` / `setAdditionalData` / `readOnly`, plus what else it needs), the
`additionalData` keys it reads and writes, which `components/ui/*` primitives it is built
from, and whether it gets a test file — a per-game panel gets one only when it holds a
real decision branch, and the task must say which branch. Every free-text field is empty
by default; no description text is written into the component.>

---

## Phase 5 — Frontend: wire <GAME NAME> into `CharacterSheet.tsx`

Goal: opening a `<game_slug>` character shows this game's tabs, every field survives a
save and a reload, and no other game's tabs change.
Depends on: Phase 3, Phase 4

`components/character/CharacterSheet.tsx` is the orchestrator and **always gets tests**.
Each task below writes its test first.

- [ ] T5.1 — TODO — frontend: Load `<game_slug>` panel fields into `additionalData`
      files: `gdr-companion-frontend/components/character/CharacterSheet.tsx`, `gdr-companion-frontend/components/character/CharacterSheet.test.tsx`
      do:
        1. <exact `else if (parts[0] === '<game_slug>')` branch, naming which keys are
           JSON-parsed, which are `=== 'true'` booleans, which stay strings>
      done-when: <observable fact>
      verify: `cd gdr-companion-frontend && npx vitest run components/character/CharacterSheet.test.tsx`

- [ ] T5.2 — TODO — frontend: Save `<game_slug>` panel fields
      files: `gdr-companion-frontend/components/character/CharacterSheet.tsx`, `gdr-companion-frontend/components/character/CharacterSheet.test.tsx`
      depends-on: T5.1
      do:
        1. <exact `if (gameSlug === '<game_slug>')` block. Plain fields push only when the
           value is not `undefined` and not `''`; JSON fields push whenever not
           `undefined`, as `JSON.stringify(value ?? [])`. The keys must match T5.1
           exactly — a key saved but not loaded looks like data loss to the player.>
      done-when: <observable fact>
      verify: `cd gdr-companion-frontend && npx vitest run components/character/CharacterSheet.test.tsx`

- [ ] T5.3 — TODO — frontend: Return the `<game_slug>` tab list
      files: `gdr-companion-frontend/components/character/CharacterSheet.tsx`, `gdr-companion-frontend/components/character/CharacterSheet.test.tsx`
      depends-on: T5.2
      do:
        1. <the imports to add, then the exact `if (gameSlug === '<game_slug>') return [...]`
           list of `{ id, name, component }`, with each tab's Italian label written as
           `t('panels.<id>', '<Italian>')` and the reused panels' relabel props filled in>
      done-when: a `<game_slug>` character shows exactly the tabs <list>, and no other
      game's tab list changes.
      verify: `cd gdr-companion-frontend && npx vitest run components/character/CharacterSheet.test.tsx`

---

## Final checks

Do these only when every task above is `[x]` DONE.

- [ ] F.1 — TODO — Run both full suites. All must pass.
      verify: `./backend-test.sh` (from the repo root) and `cd gdr-companion-frontend && npm test`
- [ ] F.2 — TODO — Lint and type-check both projects you changed.
      verify: `docker compose exec -T backend vendor/bin/pint --test && docker compose exec -T backend vendor/bin/phpstan analyse --no-progress --memory-limit=1G` (from the repo root) and `cd gdr-companion-frontend && npx eslint . && npx tsc --noEmit`
- [ ] F.3 — TODO — Prove a fresh database reproduces the game from seeders alone.
      verify: `docker compose exec -T backend php artisan migrate:fresh --seed` succeeds with no warning line, then `docker compose exec -T backend php artisan db:seed` a second time and confirm the `games` row count is unchanged (run from the repo root)
- [ ] F.4 — TODO — Confirm no rules prose was written into the repo: no description,
      effect or outcome text from the manual appears in any seeded row, constants file or
      component. Free-text fields are empty.
- [ ] F.5 — TODO — Report to the user: tasks done, tests added, every Deviations entry,
      and which repositories have uncommitted changes. Do not commit them.

---

## Open questions

<Anything unresolved. If you hit one of these while working, STOP and ask the user.
Delete a line here only when the user has answered it.>

- <question, or "none">

## Deviations

<Write here every time you do something the plan did not ask for, as allowed by rule 12.
One line each: what you added, and why the task could not work without it. If empty,
leave "none".>

- none
