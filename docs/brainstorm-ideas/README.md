# Brainstorm: gameplay & story

## The pitch, in one page

**You are not being hunted. You are being processed.**

Four beings walked out of a lunchtime accident that fractured Project AEGIS-4. Eighteen
months later the corporation that built it — GastroDefense Inc. — notices its prototype
never came back, and opens a ticket.

**Two of them know exactly what that means.** Pho-boman and Tiebi were never part of the
machine, so there is nothing in them worth putting back. They will be **erased as
mistakes**. They have been certain since the day they read it.

**The other two cannot tell.** Windman and Primm are the two halves the recall actually
wants, and neither can say whether being put back together is dying. It is a change so
total they have no word for it — and not knowing is frightening enough to run from.

So this is not four people fleeing one fate. It is **two fleeing a certainty and two
fleeing a question**, which is the only reason the ending can be a choice rather than a
survival reflex.

Only afterwards does the file give you the corporate translation. `RETURN TO ORIGIN
FACILITY` means **reintegration — un-make**: W-01 and P-03 are "specification outputs,"
P-02 and T-04 are "non-specification outputs — disposal." Nobody asked them. The consent
field was deleted in revision 3 and never written again.

There is no villain to punch. The threat is a workflow, and workflows do not get tired.

### What they run toward

The only lead not owned by the people recalling them: a **still-warm signal from AEGIS-3**,
the prototype *before* them, which also fractured and also scattered.

**Why is that signal still warm?** AEGIS-3's reintegration is filed as *completed* — and yet
a fragment still reads as live. That is an **anomaly, not an answer**, and the game must not
hand you the answer: the leap from "a signal persists" to "incompleteness saved them" is a
real causal jump, and asserting it makes the climax rest on a convenient inference.

**So you earn it.** The hypothesis forms early and is *confirmed in two pieces*, each one a
small quest:

1. An **AEGIS record that names the missing piece** — the recovery was closed short, and
   somebody signed it off anyway.
2. A **demonstrated parallel with Pho-boman's unreadability** — the same failure mode, alive
   and standing next to you.

Only then does it stop being a theory and become a **deliberate strategy**: the reason the
`EXCEPTION` route exists at all, and the reason you know to reach for it.

So what you cross the whole game to find is not a rescuer and not an ally. It is **proof** —
evidence that the spec can fail to close — delivered by the only entity that ever survived
it. And the lesson AEGIS-3 teaches turns out to be the mechanic your hands have been
practising all game.

### The destination and the trap are the same place

The signal you spend the whole game resolving resolves to **the facility**. You were running
toward where you started.

That is what makes the final act a **voluntary walk into the trap**, and it is the answer to
the obvious objection: nobody is working hard in order to be disintegrated. They are working
hard to reach **the one being who has survived this before** — and the building that wants
to un-make them is where that being is.

### The mechanic: the lock reads who you are

Every piece of GastroDefense field hardware is keyed to **identity, not ability**.

| | |
| --- | --- |
| **Windman** | the only one a pressure seal registers |
| **Tiebi** | the only one who can out-mass a steel block |
| **Primm** | the only one who fits the vent under a low ceiling |
| **Pho-boman** | the only one the scanner *cannot see* — born of soup, not built, so he carries none of the incident-signature the others do. **His key is an absence.** |

And the lock is **phased**: it needs all four, in sequence, and you cannot be two people at
once. That single fact produces three different games:

- **Alone** — you are all four heroes but one body. A relay against a re-seal timer. The
  switch key *is* the skill.
- **Two players** — you each hold two heroes. Hold two sockets, both switch, hold the other
  two. Cooperation and switching, at the same moment. The best version.
- **Four players** — one hero each. Pure coordination, one clean simultaneous hold.

Same lock, every time. The difficulty changes *shape* with the number of people, and nobody
gets to opt out of being needed.

### The tension: paperwork, not walls

Skipping these is never punished with a wall. It advances **Recall Pressure** — the recall
catching up. Hazards thicken, rewards thin; solving one vents it. At each act boundary the
pressure you carried converts into how *corrupted your signal is*.

### The long game: signal resolution, not kilometres

AEGIS-3 sits on the horizon as a broken intake tower that **sharpens, shifts and reveals new
architecture** every time enough coordinate shards decode another page of the Junior
Engineer's stolen lab notebook. Ahead of you, the echo getting clearer. Behind you,
GastroDefense's return geometry closing in.

The screen states the whole story without a word of dialogue.

### The ending: the mechanic was an argument all along

At the facility, GastroDefense reads their successful cooperation as **proof they are one
recoverable asset** — every anchor the player ever solved was also evidence filed against
them. But the mechanic has been arguing the other way for the whole game: *chosen
coordination between four selves is not the same thing as forced reintegration into one
body.* Interdependence can be temporary, negotiated and revocable — that is what a relay
teaches, six hours before anyone says it out loud.

The recall's offer is asymmetric: reintegrate two, dispose of two. So the question was never
*do you erase them*, it is **who do you include, when including him buys you nothing**. And
that has been in the socket table since the first anchor: **Pho-boman is unreadable to the
classifier, and a link the classifier cannot classify is exactly what the third option
needs.** The one marked for disposal is the only reason a third option exists.

The choice is made with the game's verbs at a signposted fork, and **the hard route is the
one that refuses**:

- `RETURN TO ORIGIN` — **easy**. Two sockets, walk in, comply. This is the path that ends in
  disintegration, and it is deliberately the path of least effort.
- `EXCEPTION` — **the hardest coordination anchor in the game**, requiring all four. This is
  the path that *refuses* disintegration.

Nobody works hard in order to be un-made. The work buys the refusal. Then the campaign ends,
and **Endless mode unlocks**: the world continuing after a choice.

---

Working notes for giving the endless runner a **story spine** and a **challenge that
forces cooperation (multiplayer) or character switching (singleplayer)**.

This is a multi-session workspace. Sessions are numbered files; this README holds only
what stays true across all of them — the constraints, and the map from lore to code.

| File | What it is |
| --- | --- |
| [session-01-recall-anchors.md](session-01-recall-anchors.md) | Recall Anchors, Recall Pressure, and the signal-horizon spine |

Lore source: `../crimekickerslor` (Obsidian vault). It is **inspiration, not a spec** —
the owner's ruling is that we do not have to follow 100% of it.

---

## The constraints any idea must survive

Engineering facts, verified against the code, not opinions. An idea that breaks one of these
is dead on arrival no matter how good the story is — **except where the owner has lifted
one**, which is marked inline. Two have been lifted so far; both lifts buy real design
freedom and cost real engineering, and the cost is stated rather than glossed.

1. ~~**There are no walls.**~~ **RELAXED by the owner** (2026-08-27), who reopened the
   endless-random-world assumption. The rule still holds *inside* an act — content is gated,
   never passage, because on an open field walking around is always rational. But an **act
   boundary may be a real barrier**, because the axis is now a story rather than infinite
   sameness. See session 01 §6.

2. ~~**The ground is flat at y = 0 and must stay flat.**~~ **LIFTED by the owner**
   (2026-08-27): *"i don't think it's hard demand to stay flat. we can loose this one."*
   **Verticality is legal**, so the tower can be a real climbable object rather than a
   horizon image.

   Recorded honestly, because this is not a doc edit — it is the largest engineering item in
   the whole design. Flat-at-zero is currently assumed by coin height settling, road
   placement, crocodile gravity settle, the spawn point, and every block base; mountains are
   impassable massifs *specifically because* the base jump apex (3.6125 m) is under
   `MOUNTAIN_MIN_LAYER_HEIGHT` (4.0), which is also why no skill anywhere touches
   `JUMP_VELOCITY`. Lifting the invariant means revisiting each of those, and it should be
   scoped as its own epic rather than smuggled into a story feature.

3. **Everything spawns deterministically from the terrain.** A spawn site is a pure
   function of (chunk coords or station index) plus `run_seed`, and a new feature takes its
   **own hash stream with its own salt** or it slides every crocodile in the world. This is
   also what lets two players in a room see the same object in the same place with nothing
   sent over the network — determinism *is* our netcode for world content.

4. **Weather and fauna are deliberately OUTSIDE that contract.** `weather_manager.gd:330`
   calls `_rng.randomize()`; the file says at line 240 that this is cosmetic-only RNG and
   deliberately not the seeded stream. **Rain is per-client.** Two peers on the same square
   metre are not in the same storm. Any *shared* puzzle that reads rain is open for one
   player and sealed for another with no packet to blame — the worst class of multiplayer
   bug, because it looks like cheating rather than desync. Environmental gates must come
   from `biome_at()` / `is_river_at()`, which are pure functions of position and `run_seed`
   and therefore identical on every client for free.

5. **A multiplayer peer holds a *hand* of heroes, and that is the lobby's truth.**
   `mp_manager.my_character_indices()` returns `null` (= all heroes) or an **array** of
   allowed indices, and `player_controller.switch_to_next_character()` already cycles within
   that array, refusing only when it has one entry. Its own docstring notes the set form
   "costs nothing and needs no special case if that ever changes." Giving a peer two heroes
   is a `server/room.go` change and **zero client change**.

6. **Distance is the score, and it is `global_position.x`.** The coin road's X strictly
   increases with station index. Anything we call a "destination" has to reckon with the
   fact that the axis never ends.

## Lore → code: what already exists

The vault's canon vulnerabilities map onto systems that are **already shipped**. This is
the biggest reason to build the story out of them: the fiction and the mechanic become the
same fact, and most of the mechanic is already written.

| Hero | Canon vulnerability (vault) | Already in the code |
| --- | --- | --- |
| Windman (W-01) | humidity > 80% | `try_activate_ability()` blocks F for `windman` when `_weather_is_raining_here()`, with a blocked-flash. **Shipped.** (Local-only — see constraint 4.) |
| Primm (P-03) | large metal masses | Phase Step scans for a spot the body fits and refuses to fire into an enormous solid. A "steel mass" is that, with a skin. |
| Tiebi (T-04) | low ceilings | Giant form exists and cannot jump. A low overhang is one `create_box()`. |
| Pho-boman (P-02) | cold zones | Snow biome exists via `biome_at()`. And he alone carries **no incident-signature**, so the drone net is blind to him — that is a scan area, not a new system. |

Other lore hooks with code already under them:

- **The incident-signature resonance** (strongest Windman ↔ Primm) — `teammate_locator.gd`
  already points at teammates. Flavouring it as the resonance costs nothing.
- **GastroDefense is a workflow, not a villain** — so it never needs a boss fight, which is
  lucky, because boss crocodiles on road stations are already the fight budget.
- **Meta-progression is already run-independent.** `progression.gd` is untouched by
  restart/new-run, and `best_run_store.gd` merges every field with a monotone `max`. A new
  *lifetime* currency needs no new persistence layer.
- **"No single member can clear an obstacle alone"** is stated outright in the vault
  (`Universe/The Crime Kickers.md`, "Power synergy"). We are implementing existing canon,
  not inventing against it.
