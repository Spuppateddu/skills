# Where a game lives in gdr-companion

Read this before writing the plan. Every path is relative to
`/home/ale/code/gdr-companion`.

The repo is a **multi-repo folder**, not a monorepo: `gdr-companion-backend/` (PHP 8.2 /
Laravel 12) and `gdr-companion-frontend/` (TypeScript / Next 15 / React 19) sit side by
side.

**Backend commands need Docker.** There is no local PHP. Run
`docker compose up -d mysql backend` from the repo root first. The repo-root `.env` sets
`BACKEND_PORT=8001`; if that port is taken, stop and ask the user rather than changing a
port, `.env` or `docker-compose.yml`. Production is Laravel Forge, a different server —
Docker here is development only.

---

## 1. The game row — `GameSeeder.php`

`gdr-companion-backend/database/seeders/GameSeeder.php` holds a flat `$games` array and
ends with:

```php
foreach ($games as $data) {
    Game::firstOrCreate(['slug' => $data['slug']], $data);
}
```

`firstOrCreate` keyed on `slug` is what makes re-seeding safe: running the seeder twice
never duplicates a game. A new game is one entry appended to `$games`:

```php
[
    'slug' => 'rosewood_abbey',
    'name' => 'Rosewood Abbey',
    'description' => 'Un gioco di ruolo monastico sulla verità e le sue conseguenze',
    'enabled' => true,
],
```

Optional columns: `resolution_mode` (`'cards'` for Sineréquie's tarot draw; leave it out
for dice games), `shared_sheet`.

Verify a seeded game with an observable fact, not a test:

```bash
docker compose exec -T backend php artisan tinker \
  --execute="echo \App\Models\Game::where('slug','rosewood_abbey')->where('enabled',true)->count();"
```

## 2. The game's config — `character-config.json`

`gdr-companion-backend/database/seeders/data/character-config.json` is one JSON object
with five arrays: `attributes`, `skills`, `races`, `classes`, `alignments`. Most games
only use `attributes`. `CharacterConfigSeeder` reads it and `updateOrCreate`s each row
keyed on (game_id, slug), so it is idempotent too.

**Slugs are prefixed with the game slug.** `rosewood_abbey-vigore`, `ronin-rapidita`. The
frontend strips that prefix back off (`attr.slug.replace(gameSlug + '-', '')`) to build
its `additionalData` keys, so a missing or wrong prefix silently breaks the panel.

An attribute row:

```json
{
  "game_slug": "rosewood_abbey",
  "slug": "rosewood_abbey-vigore",
  "name": "Vigore",
  "order": 1,
  "value_type": "number",
  "default_value": "0",
  "min_value": -3,
  "max_value": 3,
  "is_required": true,
  "has_value_total": false,
  "calculation_formula": null,
  "category": null,
  "short_name": null,
  "italian_suit": null
}
```

A skill row adds `primary_attribute_slug` (resolved to an id by the seeder, so it names
the attribute slug, not a number), `has_fail_tracking`, `has_grade`,
`has_advantage_disadvantage`, `allows_specialization`, `difficulty_multiplier`.

**The silent-skip trap.** `CharacterConfigSeeder` does:

```php
$gameId = $games[$row['game_slug']] ?? null;
if (! $gameId) {
    continue;   // <- no warning, no error
}
```

A game in the JSON but not in `GameSeeder` loses every config row on a fresh database and
nothing says so. `kulthos`, `ronin` and `blades_in_the_dark` are in that state today.
Every plan fixes this — see the guard tasks in the template.

`DatabaseSeeder` calls, in order: `PermissionSeeder`, `GameSeeder`, `CharacterConfigSeeder`.
A new game needs no change there.

## 3. Free-form fields — `character_panel_fields`

Anything that is not an attribute, skill, weapon, armour, spell or object is a row in
`character_panel_fields`: `character_id`, `slug`, `value`, `value_total`,
`instance_index`. The value is always a **string** — booleans are stored `'true'`/`'false'`,
lists are stored as `JSON.stringify(...)`.

The slug carries the game:

| Format | Used by | Parsed as |
|--------|---------|-----------|
| `<game_slug>-<field>` | `tenebrae`, `kulthos`, `ronin`, `rosewood_abbey` | key = everything after the first `-` |
| `<game_slug>-<panel>-<field>` | `ultima_torcia`, `dnd5e`, `cyberpunk` | key = everything after the second `-` |

Prefer the **two-part** format for a new game. Both parsers join the remaining parts with
`_` and turn any leftover `-` into `_`, which is exactly why **a game slug must never
contain a hyphen** — `blades-in-the-dark-fortuna` would parse as the field `in_the_dark`
of the game `blades`.

## 4. Wiring the sheet — `CharacterSheet.tsx`

`gdr-companion-frontend/components/character/CharacterSheet.tsx` (~2900 lines) is the
orchestrator. A new game touches it in exactly three places, and the plan should make
each one its own task:

1. **Imports** at the top — the new panel components.
2. **The load branch** (~line 460, "Load panel fields") — an
   `else if (parts[0] === '<game_slug>')` block turning stored strings back into
   `additionalData` values. Say in the plan exactly which keys are JSON-parsed, which are
   `=== 'true'` booleans and which stay strings.
3. **The save block** (~line 1440) — an `if (gameSlug === '<game_slug>')` block pushing
   `panelFields` entries. Plain fields are pushed only when not `undefined` and not `''`;
   JSON fields are pushed whenever not `undefined`, as `JSON.stringify(value ?? [])`.
4. **The tab list** (~line 2280 onward) — an `if (gameSlug === '<game_slug>') return [...]`
   returning `{ id, name, component }` objects. Falling off the end of that chain gives
   the generic default tabs, which is the right answer for a simple game.

The load and save blocks must name the same keys. A key saved but not loaded looks like
data loss to the player.

`CharacterSheet.tsx` **always gets tests** — it is the orchestrator.

## 5. Constants — `constants/<game_slug>/`

`gdr-companion-frontend/constants/<game_slug>/*.ts` holds the game's static data as
frozen exported arrays (`as const`), one file per subject: `identity.ts`, `moves.ts`,
`thorns.ts`, `progress.ts`. Panels import from here. **No logic in these files** and no
rules prose in them — names and labels only.

A constants file that only exports data gets **no test file**.

## 6. i18n — do not add dictionaries for a new game

`hooks/useGameTranslation.ts` hardcodes a `GameSlug` union that stops at
`sinerequie | dnd5e | dnd55e | cyberpunk | tenebrae`. Newer games are deliberately not in
it: `ultima_torcia`, `kulthos`, `ronin` and `rosewood_abbey` all call
`t('some.key', 'Testo Italiano')` and rely on the fallback string.

**Do the same. Never create `constants/<game_slug>/i18n/*.json`.** All user-visible text
is Italian, written as the fallback argument.

## 7. Character creation form

`components/character/gameForms.ts` maps a slug to a bespoke creation form; a game absent
from `GAME_FORMS` gets `DefaultCharacterForm`. Only add an entry when creation itself has
steps beyond name and avatar.

## 8. Commands and test policy

| Name | Directory | Run one test | Run all tests | Lint / format |
|------|-----------|--------------|---------------|---------------|
| backend | `gdr-companion-backend/` | `./backend-test.sh --filter=<TestName>` (from repo root) | `./backend-test.sh` (from repo root) | `docker compose exec -T backend vendor/bin/pint --test && docker compose exec -T backend vendor/bin/phpstan analyse --no-progress --memory-limit=1G` |
| frontend | `gdr-companion-frontend/` | `cd gdr-companion-frontend && npx vitest run <path/to/file.test.tsx>` | `cd gdr-companion-frontend && npm test` | `cd gdr-companion-frontend && npx eslint . && npx tsc --noEmit` |

**Which files get a test file:**

- **Always:** `components/ui/*`, `components/character/panels/Shared/*`,
  `components/character/CharacterSheet.tsx`.
- **Only when it has a real decision branch:** a per-game panel
  `components/character/panels/<game_slug>/*.tsx`. That is why `panels/kulthos/` has three
  test files and `panels/ronin/` two, while `panels/tenebrae/`, `panels/ultima_torcia/`,
  `panels/dnd/`, `panels/sinerequie/`, `panels/cyberpunk/` and `panels/default/` have
  none.
- **Never:** seeders, `character-config.json`, plain constants files. Verify those with a
  `tinker` count or `npx tsc --noEmit`.

## 9. House style

- Code and comments in English. Table, column and slug names in English.
- **Every string the player sees in the browser is Italian.**
- Backend PHP files start with `declare(strict_types=1);`.
- No CSS framework, ever. CSS Modules (`.root`, camelCase) or shared `gdr-` classes.
  Colours only as `var(--…)` tokens. State travels as `data-*` attributes, never class
  names. Full rules in `gdr-companion-frontend/AGENTS.MD` — read it before any frontend
  task.
- Components stay under ~600 lines; split if they grow past that.
- Never `git commit` or `git push`. The user commits by hand.
