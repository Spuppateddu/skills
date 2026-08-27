# Panel catalog — reuse before you build

Walk this file before you plan a single new component. The rule the user cares about:
**a different word is a label change, not a new panel. Only a different shape earns a new
component.**

Paths are under `gdr-companion-frontend/components/`.

---

## The generic tabs — `character/panels/default/`

A game that returns nothing from the tab chain in `CharacterSheet.tsx` gets all of these
automatically. Reuse one by returning it from the game's own tab list with a different
tab `name`.

| Component | Renders | Props you can relabel |
|-----------|---------|-----------------------|
| `DefaultGeneral` | name, age, avatar | — |
| `DefaultStatistiche` | one row per **attribute in the database** for this game | none needed — driven by `attributes` |
| `DefaultSkills` | one row per **skill in the database** for this game | none needed — driven by `skills` |
| `DefaultWeapons` | list of name + description | — |
| `DefaultArmors` | list of name + description | — |
| `DefaultSpells` | list of name + description | **`entityName`** (default `'Incantesimo'`) |
| `DefaultObjects` | list of objects + a money field | **`moneyLabel`** (default `'Denaro'`) |
| `DefaultBackground` | one long free-text box | — |
| `DefaultNotes` | one long free-text box | — |

`DefaultStatistiche` and `DefaultSkills` are **config-driven**: they render whatever
`character-config.json` holds for the game. A game whose stats are plain numbers needs
**no component work at all** — only seeded rows.

### The relabel pattern

When a `Default*` panel has a hardcoded Italian string the new game needs to change, add
one optional prop whose default is today's string. Nothing else moves, so every other
game renders exactly as before:

```tsx
interface PanelProps {
  spells: Spell[];
  setSpells: (spells: Spell[]) => void;
  readOnly?: boolean;
  entityName?: string;          // added
}

export const DefaultSpells = ({ spells, setSpells, readOnly = false,
                               entityName = 'Incantesimo' }: PanelProps) => (
  <EntityList items={spells} setItems={setSpells}
              entityName={entityName} readOnly={readOnly} />
);
```

`entityName` and `moneyLabel` were both added this way. Ultima Torcia calls spells
*Testi* with `entityName="Testo"` and nothing else. Do that.

---

## Shared building blocks — `character/panels/Shared/`

| Component | Renders | Key props |
|-----------|---------|-----------|
| `EntityList<T>` | add / edit / delete list of `{ name, description }` | `entityName`, `placeholder`, `externalAddTrigger`, `renderAddButton` |
| `WeaponList` | weapon list with optional columns | `showDamage`, `showRange`, `showNotes` |
| `TalentsPanel` | titled list of talents | `title`, `entityName`, `placeholder` |

`EntityList` is the answer to almost every "the game has a list of named things with a
description" section — moves, powers, gifts, relics, rituals. Give it the game's word and
leave the description empty for the player to fill in.

Anything in `Shared/` **always gets a test file** when changed.

---

## UI primitives — `components/ui/`

Build a new panel out of these. A panel that reimplements one of them is wrong.

| Component | Use it for | Key props |
|-----------|-----------|-----------|
| `TrackCheckboxes` | a track of N boxes filled left to right (stress, harm, corruption) | `value`, `onChange`, `max`, `darkFrom`, `showNumbers` |
| `PaperCheckbox` | a single tick box | `checked`, `onChange`, `label`, `size` |
| `CheckboxStringList` | a list where each row is a tick box plus a text line | `label`, `items`, `onChange` |
| `StringList` | add/remove list of plain strings | `label`, `items`, `onChange` |
| `TitleDescriptionList` | add/remove list of title + description | `titlePlaceholder`, `descriptionPlaceholder`, `emptyMessage` |
| `AttributeModifierInput` | a −N…+N stepper | `value`, `onChange`, `min`, `max` |
| `ClickToEditInput` | a labelled value that turns into an input when clicked | `label`, `value`, `onChange`, `type` |
| `CreatableSelect` | pick from a list **or** type your own | `options`, `onChange(value, isCustom)`, `createLabel` |
| `SearchableSelect` | pick from a long list | `options`, `value`, `onChange`, `allowClear` |
| `CollapsibleSection` | a foldable block inside a tab | `title`, `defaultOpen`, `flush` |
| `Input`, `Select`, `Button`, `Card`, `Badge`, `Alert`, `Tooltip` | the basics | — |

`components/ui/*` **always gets a test file** when changed.

---

## What existing per-game panels prove

Read one before planning a new panel of the same shape.

| Game | Panel | Shape worth copying |
|------|-------|---------------------|
| `rosewood_abbey` | `RosewoodAbbeySpine` | fixed list from constants, each row a `PaperCheckbox` + a free-text memory line, counter above |
| `rosewood_abbey` | `RosewoodAbbeyMosse` | list of moves whose **names come from constants** and whose **effect text is left empty** for the player |
| `kulthos` | `KulthosAbilitaRisvegliataList` | list stored as JSON in one panel field |
| `ronin` | `RoninOnore`, `RoninStato` | small trackers with a real decision branch — these two have tests, the other two Ronin panels do not |
| `ultima_torcia` | `UltimaTorciaStatistiche` | per-attribute extra flags stored as `<game>-statistiche-<attr>_<flag>` |

**How they stay dumb.** The list of Spine lives in
`constants/rosewood_abbey/thorns.ts` as a frozen array; the panel maps over it. The panel
holds no list, no length and no rule. Plan the constants file first, then the panel that
reads it.

---

## The decision, in order

1. Is it a plain number per stat? → seed `attributes`, use `DefaultStatistiche`. **No code.**
2. Is it a list of named things with a description? → `EntityList` / a `Default*` panel,
   with the game's word passed as `entityName`.
3. Does an existing `Default*` panel fit but show the wrong Italian word? → add one
   optional label prop with today's string as its default.
4. Is the **shape** genuinely different — a track with a line per box, a grid, a
   two-state toggle driving other fields? → new panel, built from
   `components/ui/*`, reading its data from `constants/<game_slug>/`.

Write which rung you landed on, per sheet section, into the plan's Goal.
