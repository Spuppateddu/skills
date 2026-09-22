# Page plan — what goes on a 4-page GM screen

A GM screen is not a summary of the book. It is the set of things the GM
looks up **during play**, when a player has just said "I try to…" and
everybody is waiting. Everything else stays in the manual.

## The test for every line

Keep a rule on the screen only if it passes at least one of these:

1. **It is looked up mid-scene.** The resolution procedure, the results
   table, modifiers, what a success and a failure mean, damage, healing,
   conditions, the price of pushing a roll.
2. **It is a list the GM must not get wrong.** Skills and what they cover,
   the moves and their triggers, the consequence menu, the GM's principles.
3. **It is a number.** Difficulty ladders, ranges, costs, durations, how many
   boxes a track has, how much XP a thing gives.
4. **It is a random table the GM rolls at the table.** Weather, encounters,
   complications, names, loot, reactions.

Leave out: setting lore, the introduction, examples of play, advice
paragraphs, character creation (players do that with the book, not the GM
mid-scene — the exception is a one-line summary of classes/playbooks when the
GM needs it to judge what a character can do), the designer's notes, anything
that appears once per campaign.

## The four pages

The four screens this skill comes from settle on one arrangement. Follow it
unless the game clearly has a different shape (then say why in the report).

| Page | Title pattern | Content |
|---|---|---|
| 1 | *Tiri & Basi* / *Le Prove* / *Prove & Personaggio* | The **core resolution**: how to roll, read the die, modifiers, advantage, success ladder, what the GM chooses on a failure, help, pushing, the resource that fuels it (stress, fortune, luck). Plus the quick lists a GM checks constantly: attributes/skills with one-line meanings, conditions. |
| 2 | *Combattimento* / *Conseguenze & Colpo* / *Le Mosse* | The game's **conflict subsystem**: initiative, attack and defence, damage, armour, critical hits, harm and death, healing, morale, chases. In move-based games this page is the moves themselves (triggers + results). |
| 3 | *Downtime* / *Ferite, Morte & …* / *Provvidenza & …* | The game's **second subsystem**: downtime, recovery, the economy (money, resources, reputation), the haven, travel, the campaign clock, magic if it is a small system, the game's signature mechanic if it did not fit on page 1. |
| 4 | *Il GM* / *Tabelle Rapide* / *Banda, Fazioni & GM* | **GM procedures**: session structure, GM principles and moves, challenge ladder, NPC quick stats, threat/creature summary, the random tables, prices, the game loop as a box. |

Every page has 2 columns (`.cols` with two `.col`); a full-width block below
the columns works for a wide table (the 12 actions, the class summary).
Three columns are fine for a page that is all short tables.

## How much fits

Measured on the four finished screens (Liberation Serif 7.3–7.9 pt):

| Per page | Low | High |
|---|---|---|
| text characters | 4 500 | 6 700 |
| words | 900 | 1 270 |
| `<h2>` sections | 6 | 11 |

Aim for 5 000–6 500 characters of text per page. Under 4 000 the page looks
empty and you left something useful out; over 7 000 nothing fits at a readable
size, unless most of the page is tables (The Walking Dead's wounds page holds
7 150 at 7.4 pt). A screen at 7.3 pt holds about 8 % more than one at 7.9 pt:
the font size is a fine adjustment, not a way to fit a whole extra section.

## Worked examples: the section outlines of the existing screens

Use them to pattern-match a new game against one with the same shape.

**Blades in the Dark** (Forged in the Dark — dice pool, position/effect):
1. *Tiri & Basi* — Tiro azione (6 steps + position/result table) · Efficacia · Dadi bonus · Stress & Trauma · Tiro resistenza · Armatura · Tiro sorte · Raccogliere informazioni · Orologi · Le 12 azioni (full-width table).
2. *Conseguenze & Colpo* — Le 5 conseguenze · Danno · Morte · Carico & equipaggiamento · Lavoro di squadra · Flashback · Il colpo (plan + detail) · Tiro di ingaggio.
3. *Downtime* — Ricompensa · Sospetto · Incarcerazione · Coinvolgimenti · Attività di downtime · Downtime di PNG e fazioni · Cricche.
4. *Banda, Fazioni & GM* — Rango e dominio · Status · Denaro · Avanzamento · Magnitudine · Rituali · Obiettivi / Azioni / Principi del GM · Buone pratiche · Ciclo di gioco (box).

**Rōnin** (OSR-style d20, classes, honour):
1. *Prove & Personaggio* — Le Prove · Caratteristiche · Capacità di trasporto · Riposo · Meditazione & Haiku · Onore · Faida · Virtù · Migliorare · Addestrarsi · Le 10 Classi (full-width summary).
2. *Tatakai — Combattimento* — Iniziativa & Round · I quattro tiri · Critici (20 / 1) · Armature · Veleno · Duellare · Morale · Reazione delle creature · Armi (table).
3. *Ferite, Morte & Yomi* — Punti Ferita · Ferite debilitanti (d10 table) · Seppuku · Resurrezione · Demoni dello Yomi · Trappole · Creature & Yokai (stat table).
4. *Testi & Tabelle Rapide* — Magia · two spell lists (d10 tables) · Clima (d10) · Richieste dello Shogun (d10 hooks) · Santuari (d12) · Prezzi · Da assoldare.

**Rosewood Abbey** (Powered by the Apocalypse — moves, 2d6):
1. *Le Basi & i Confratelli* — Tirare i dadi · Vantaggio e Svantaggio · Condizioni · Gioia nelle Piccole Cose · Creazione del Confratello · Esperienza · Spine (in breve) · Routine dell'abbazia · Vignette · Premessa e tono · Materiali.
2. *Le Mosse* — every basic move and every Confratello move: trigger in italics (`.trig`), results as `.res` rows (`7-9` / `10+` / `12+`).
3. *Provvidenza & Giro di Voci* — the game's investigation/rumour engine, step by step, with the two tribunal outcomes.
4. *Il Cantore* — Principi · Condurre i Misteri · Scheda del Mistero · Reazioni · Preparazione · Struttura della sessione (4 numbered steps) · Finali sospesi.

**Kulthos** (single die, d4–d12, fortune/misfortune economy):
1. *La Prova* — Sequenza della prova (13 numbered steps in a box, before/after the roll) · Il risultato del dado (1 / 2 / 3–4 / 5+ strip) · Regole d'oro · Vantaggio & Svantaggio · Gli Approcci (table) · Cosa può fare una prova (limits) · Niente prova per… · Le Conseguenze (menu) · Conseguenze letali · Prove contro un'altra Dormiente.
2. *Fortuna, Sciagura, Ferite* — the two currencies (gain / spend tables) · Ferite & Afflizioni · Promemoria.
3. *Gioco libero* — space and distance · Dissonanza (the horror-reveal mechanic) · scene procedures.
4. *Elenco dei Talenti* — the talent list as a table · how to build a talent.

**The Walking Dead Universe RPG** (Year Zero Engine — d6 pool, stress dice, walkers):
1. *Tiri & Stress* — Tiro abilità + Difficoltà · Tiri contrapposti · Forzare il tiro · Dadi stress & fare un casino (box: fattori di stress) · Punti esperienza · Modificatori & aiuto · Probabilità di successo (table) · Altri tiri di dado · Alleviare lo stress + Ancore · Gestire la paura (Sopraffatto table) · Le 12 abilità (full-width table).
2. *Combattimento* — Duelli · Distanza & copertura · Altre regole · Fare un casino in combattimento (D6) · Armatura · Esplosioni · Risse (box + 6 phases + Comando) · Armi a distanza · Armi corpo a corpo · Veicoli (full-width h2 + a second `.cols` block).
3. *Ferite & Vaganti* — Punti Vita & Spezzato · Ferite gravi (rules + full D66 table) · Altri pericoli · Livello di Minaccia 0–6 + Dimensione Sciame · Evitare i vaganti & attacco singolo · Combattere uno sciame (box with the round's steps).
4. *Rifugio, Viaggio & GM* — Il rifugio (Capacità, Difesa, Irruzione) · Progetti (table) · PNG & animali · Spedizione · Incontri · Vaganti nell'edificio · Meteo · Oggetti · Sfide & Necessità · La sessione (inizio / fine boxes).

## Choosing the page titles

Title = 2–4 words, uppercase by CSS, an ampersand to join two topics
(`Tiri &amp; Basi`). Subtitle = the page's sections in order, joined by ` · `,
so the GM can find a rule by scanning the top edge of the four sheets.
