# CrimeKickers — the story bible

The one place the narrative lives. Code comments and CLAUDE.md say how the
mechanics work; bd beads say what to build next; **this file says what is
true in the world**, what the player is told, and when each ruling was made.
A story bead cites this file and updates it in the same PR.

Owner rulings are quoted as given. Where a design document said something
else, the ruling wins and the older text is marked as such.

## 1. The premise, in one paragraph

Four heroes — Windman, Primm, Teibi and Phoboman, the CrimeKickers — walked
out of **GastroDefense Inc.**'s headquarters. The corporation noticed at once
and, because a loose prototype is a reputational emergency, sent its
**GD-SURVEY retrieval units** ("hunters") to bring them back. The heroes run.
The road east of the HQ leads to **Budapest**, the nearest big city, where
four figures can vanish into a crowd that already looks like them and start a
new life. Getting there and knowing the city well enough to disappear is the
win. Being caught, all four, is the end.

## 2. The world

- **The HQ.** GastroDefense's tower stands at a fixed site west of the spawn.
  Inside: offices, an operations floor, a labyrinth, and under the sealed roof
  the **cell block** with one cell per hero. The building is a stealth
  problem: at most one guard per storey, gates that read *who* you are, not
  what you can do, and the paperwork that says what the company thinks of the
  four (the evidence dossiers, and four portraits in the hall captioned
  "employee of the month, all four, every month").
- **The field.** An endless procedural land of plains, desert, forest,
  mountain, snow and city bands, crossed by rivers, dotted with the world's
  famous landmarks, nomad camps and lost-civilisation ruins. Predators live in
  it by biome; hunters roam all of it. This is where the heroes gain
  experience: coins, skill points, abilities.
- **The road.** A trail of coins runs east from the spawn, away from the HQ.
  It is the escape route made visible. Six territorial bosses hold its
  stations by biome — the plains hydra, the desert naga, the forest green
  dragon, the mountain roc, the snow titan with its thunder arrow, the city's
  ice-cream-throwing clown, and the crocodile on any station standing in a
  river. None can be killed; each hunts inside its ground and never leaves it.
- **Budapest.** About two kilometres east of the HQ the road bends into the
  city gate. Budapest's centre is built from the real map: the Danube with
  its four bridges, Castle Hill and Gellért Hill as ramped heights, Parliament,
  the Basilica, the Market Hall, the baths, Heroes' Square. Twenty-two
  landmarks, and crowds of citizens who look uncannily like the four heroes.

## 3. The heroes

Visual sheets: [Windman](characters/windman.md), [Primm](characters/primm.md),
[Teibi](characters/tiebi.md), [Phoboman](characters/phoboman.md). Canon
spellings in-game: **Windman, Primm, Teibi, Phoboman** (the sheets' "Tiebe"
and "Pho-boman" are older spellings of the same people).

| Hero | Power | Story role |
|---|---|---|
| Windman | Air Rush in the field; Air Sight indoors (sees patrols through walls) | The scout |
| Primm | Phase Step — blinks through walls, never lands inside geometry | The one the HQ caught first; his rescue is the authored first beat |
| Teibi | Resize — small or giant; giant crushes predators, small fits the crawl | The one who fits where nobody else does |
| Phoboman | Stink Wave — predators flee; machines do not | The one machines cannot smell |

**The heroes are the lives.** There are no hearts. A bite is a tax — a moment
frozen and a slice of the run's coins. What a hunter takes is a *hero*: the
one you were playing goes to a cell in the HQ and you carry on as the next.
The first capture the game stages itself: Primm, in the HQ, so that the rule
is taught in the building where it can be undone.

## 4. The antagonist

GastroDefense is not cruel; it is a procedure running at emergency speed.
Its hunters capture, catalogue and transport — they do not taunt. Its guards
patrol a floor and never leave it. Its paperwork is the villain's monologue:
*"Retrieval order 7: subject is fond of the four. Collect all four."*

The dossiers in the HQ are the only backstory the game shows today. A fuller
lore — the four as a fractured prototype the company wants to "reintegrate" —
exists in the unmerged brainstorm sessions of 2026-08-27
(`docs/brainstorm-ideas/` on branch `worktree-story-brainstorm`). It is
**backstory, not canon**, until the owner puts it on screen; and its
destination — "the signal resolves to the facility, you were running toward
where you started" — is **superseded**: the destination is Budapest.

## 5. The arc

1. **Out.** The intro film (web) shows the escape. The player starts at the
   spawn with the HQ behind them and the road ahead.
2. **The field.** Run, collect, level up, switch heroes as the terrain and
   the predators demand. Hunters shadow the party; the hunt director keeps
   the pressure fair — a cap on pursuers, a lull after a grab, always an open
   sector to run into.
3. **The first loss.** Primm is taken in the HQ, and the rescue teaches the
   cell block: every hero has a spine door only they can open, and freeing a
   captive is walking into their cell.
4. **The road.** Six bosses, one per biome, each a territory to cross or go
   around.
5. **Budapest.** The road ends at the gate. Inside, the hunt continues, the
   Danube belongs to crocodiles, the bridges are the dry way across, and every
   landmark visited is one more street the four know. **Eighteen of
   twenty-two and they can vanish.**
6. **Endings.** *Captured:* the fourth hero goes into a cell and the run ends
   at once — the film on web, the panel on desktop; the world is archived
   and Continue reopens the ending. *Won:* the heroes disappear into the
   crowd and start a new life. The owner will film their next adventure later
   and it will play in that slot; until then the win panel documents it.

## 6. Things the story does not say (deliberately)

- **No break-out scene.** There was a full-custody protocol with a recall
  clock; the owner vetoed it on 2026-09-01: *"I never asked for this."* All
  four caught is the ending, immediately.
- **No pre-beat game over.** Before Primm's rescue nothing can end a run.
- **No health, no killing bosses.** Contact is a tax; bosses are avoided.
- **No distance score.** Distance meant something when the road was endless.
  It is being retired (epic `godot-test1-8gw`, child .1); the headline is
  coins, and the countdown to Budapest.
- **Crowds are story, not mechanics — yet.** Citizens look like the heroes
  because that is how the four hide. Whether hunters lose you in a crowd is a
  later ruling.

## 7. Rulings log

| Date | Ruling (owner, verbatim where quoted) | Where it lives |
|---|---|---|
| 2026-08-27 | Hunters start immediately; the motive is the company's reputation. A hero is captured and the others go back in for them. The game loops: farm the field, return to the tower. | brainstorm sessions 01–04 |
| 2026-08-27 | "Sequential gating, not simultaneous holding" — you must switch heroes, never hold two places at once. | session 02, the tower graph's identity gates |
| 2026-08-29 | The HQ site is a constant, hand-planned once and forever. | `endless_terrain.gd` tower section |
| 2026-08-30 | At most one guard per storey; the building is a stealth problem. | `tower_interior.gd` |
| 2026-08-31 | "Forget hearts. Game over is when all four are jailed; everything else is fewer coins / a freeze." | bead `godot-test1-0bc`, `docs/plans/20260831-heroes-are-the-lives.md` |
| 2026-09-01 | Losing to an HQ guard is an arrest, same as a field grab. | bead `godot-test1-3iy.19` |
| 2026-09-01 | "I never asked for this" — the break-out scene is removed; the fourth capture ends the run. | bead `godot-test1-ueg` |
| 2026-09-02 | Distance leaves the HUD and the records. The road ends at Budapest ~2 km from HQ, built from the real centre map; exploring 80% of its landmarks wins. | epic `godot-test1-8gw` |
| 2026-09-02 | "Budapest is the nearest big city to GastroDefense HQ; our heroes can get lost there and start a new life. We will film their next adventure later and show it in the game; for now the win just documents it." | epic `godot-test1-8gw`, child .2 |
| 2026-09-02 | "The city has many people, and our heroes hid because those people look like our heroes — super-similar figures walking the city in big masses." | epic `godot-test1-8gw`, child .8 |
| 2026-09-02 | Boss models must look unique — not a hero recoloured. | bead `godot-test1-lce.8` |

## 8. Names and spellings

| Canon | Also seen | Note |
|---|---|---|
| GastroDefense Inc. | Gastro HQ, GD | The corporation; its HQ is "the tower" in code |
| GD-SURVEY | hunter robot, retrieval unit | The corporation's field units; `captures_hero` in the species table |
| Teibi | Tiebi, Tiebe | Code, HUD and README say Teibi |
| Phoboman | Pho-boman | Code and README say Phoboman |
| The road / the coin road | — | Ends at the Budapest gate once 8gw lands |
| The cell block | the prison, the block | Storey 10 of the HQ |
