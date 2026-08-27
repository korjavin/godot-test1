# Brainstorm: gameplay & story

## The pitch, in one page

**You are not being hunted. You are being processed.**

Four beings walked out of a lunchtime accident that fractured Project AEGIS-4. Eighteen
months later, the corporation that built it — GastroDefense Inc. — notices its prototype
never came back, and opens a ticket. `RETURN TO ORIGIN FACILITY` decodes to
**reintegration: un-make.** Windman and Primm get melted back into one machine.
Pho-boman and Tiebi are "non-specification outputs" — disposal. Nobody asked them. The
consent field was deleted from the spec in revision 3 and never written again.

There is no villain to punch. The threat is a workflow, and workflows do not get tired.

So you run — toward the only lead not owned by the people recalling you: a **still-warm
signal from AEGIS-3**, the prototype *before* them, which also fractured and also
scattered. Somebody else survived this. Find them.

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

The choice is made with the game's verbs at a signposted fork — an easy `RETURN TO ORIGIN`
lane, or an unstable `EXCEPTION` route that requires all four. Then the campaign ends, and
**Endless mode unlocks**: the world continuing after a choice.

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

## The six constraints any idea must survive

Engineering facts, verified against the code, not opinions. An idea that breaks one of
these is dead on arrival no matter how good the story is.

1. **There are no walls.** The field is infinite and flat, and the player can always walk
   around anything. So we gate **content, never passage**. Anything shaped like a locked
   door is the wrong shape for this game.

2. **The ground is flat at y = 0 and must stay flat.** Coin heights, road placement,
   crocodile gravity settle and every block base assume it. Mountains are massifs you walk
   *around*; rivers are tinted wading bands, not water. A beat that needs a pit, a chasm or
   a raised platform needs a different beat.

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
