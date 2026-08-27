# Session 04 — The tower: GastroDefense HQ as a place on the map

**Date:** 2026-08-27 · Architect pass over the owner's two-layer structure.
**Status:** design fiction plus filed beads. Nothing built.

Read [session 03](session-03-the-loop.md) for the loop this building serves, and
[session 02](session-02-the-hunt.md) for the abduction it must survive. Every code claim
below was checked against the actual file before being asserted; the citations are the
receipts.

---

## What is being placed

The tower is the **campaign half** of the two-layer game: few guards, mostly puzzles and
quests, entered and left freely, never farmable. The field already exists and already works.
So the whole job here is to put **one authored, persistent, multi-floor building** into a
world whose engine is an infinite chunk streamer that frees everything it made — and to do
it without breaking determinism, the web perf budget, or multiplayer.

Six questions, answered in order of how much they constrain each other.

## 1. Where the tower sits

### The spawn is the answer the story already gave

`player_controller.gd:872` records it plainly: *"Spawn is world (0,0) on the XZ plane"*, and
the coin road's station 0 **is** the player spawn, with the road trending +X from there
(`endless_terrain.gd:562-563`). Meanwhile the README's story spine says *"the destination and
the trap are the same place — you were running toward where you started."*

Those two facts want to be the same fact. **Put the tower a short, fixed walk from the world
origin, on the −X side** — opposite the road. Then:

- The **coin road is diegetically the escape route**: it leads *away* from the tower, and
  farming means literally running from the building. Nothing needs to explain this; the
  geometry says it.
- The **loop has a short commute.** *Go in, find the wall, go out, grow, come back* dies if
  the commute is ten minutes. With the tower a few hundred metres from spawn and the field
  endless in every other direction, withdrawal and return are both under a minute.
- Session 02's *"the endless runner gets a reason to turn around"* becomes literal: outbound
  is flight, inbound is return, and the radial high-water distance
  (`player_controller.gd:879`, `maxi` over displacement from origin) never punished the
  return leg anyway — and is deleted regardless.

### Fixed offset, not a seed-derived bearing — with one deterministic nudge

A random bearing per `run_seed` buys nothing: the interior is **authored**, so its position
adds no variety, and New Game re-rolls the *field* around it anyway. A constant is trivially
a pure function of seed — identical on every client, zero packets, zero new hash stream.
Fixed wins on every axis but one:

**The one real problem is water.** `is_river_at()` ignores Y by contract — its own docstring
says *"Y is ignored — the world is flat"* (`endless_terrain.gd:7503-7507`) — and the player's
wading check is `is_on_floor() and _terrain_is_river_here()` (`player_controller.gd:933`).
The river field varies per seed, so a fixed site will, on some seeds, sit on a river band —
and then **every floor of the tower wades**, because a tower floor is a floor and the river
test is XZ-only. A y-guard does not fix it: the ground floor is at y ≈ 0.

So the site is **fixed-with-a-nudge**: `tower_site()` starts at the constant offset and scans
deterministically (say, 25 m steps along −X, then lateral) until the footprint is clear of
`is_river_at`. Pure function of `run_seed` (the river field is), no RNG draw, memoized once,
same answer on every client. This is the entire concession to proceduralism the tower makes.

### Minimap and horizon — be honest about the fog

- **Minimap:** the geo-landmark plumbing already draws off-disc markers *"clamped to the rim"*
  precisely because *"at the default zoom most loaded landmarks are past the disc"*
  (`minimap_hud.gd:22-25`). The tower marker rides the same pattern with a unique glyph. Cheap.
- **Horizon:** on web the render distance is 3 chunks = 150 m (`endless_terrain.gd:44`) and
  the fog density is 0.005 (`endless_terrain.gd:71`). At a 300 m site the tower is **inside
  the fog**, not on the horizon. A permanent fog-piercing silhouette is possible (an impostor
  mesh with a fog-exempt material, always loaded, parented to main) but it is **polish, not
  wayfinding** — the minimap marker and Windman's towerward scar (session 02) already carry
  navigation. Filed as a polish bead, deliberately last.

## 2. How an authored building coexists with the chunk streamer

This is the hard question, and the honest answer starts from a fact about the scene tree:
**this project has no autoloads.** `progression`, the sound manager, the minimap, the MP
manager — all of them are children of `main.tscn` (`scenes/main.tscn:81` for Progression),
discovered by group. That fact prices the options.

### Option A — a separate interior scene, transitioned into

The classic answer: the door is a load boundary, `change_scene`, the interior is its own
world.

- **Buys:** total authoring freedom; total isolation from every field system; the field is
  unloaded while inside — the cleanest possible web perf story.
- **Costs, and they are not small:**
  - With no autoloads, a scene swap **loses progression, sound, HUD and the MP manager** —
    either they all become autoloads (a real refactor with group-discovery fallout) or the
    swap keeps `main.tscn` and swaps a world subtree, which is Option B wearing a trench coat.
  - **Multiplayer splits.** Presence is a 15 Hz Vector3 position per peer
    (`mp_manager.gd:12`); with two peers in different scenes, position stops meaning anything
    shared. Every avatar, locator and shared-total system needs a "layer" concept that does
    not exist today.
  - *"You can always leave"* becomes a loading screen. The hunters cannot chase you to the
    door. The tower stops being a **place** and becomes a **menu**.

### Option B — an in-world building plus a streamer exclusion (recommended)

The tower is **one instanced `PackedScene`, parented to the terrain manager, not to any
chunk** — exactly the fauna precedent: the fauna manager already parents persistent world
content to itself rather than to chunks, precisely so chunk unloading cannot free it. The
shell is instanced when its chunk ring first loads and simply never freed (its footprint is
a bounded, known cost).

The streamer's side of the deal is an **exclusion, not an interaction**: nothing chunk-
generated may place inside the footprint. The repo already has both halves of this idiom:

- `_biome_spot_ok()` (`endless_terrain.gd:6412`) is *"the single home of the river /
  road-clearance / overlap rule"* — one more clause (`_tower_clearance`) covers every
  candidate loop that already routes through it.
- The crocodile-free spawn bubble (`SPAWN_SAFE_RADIUS`, `endless_terrain.gd:420`) is the
  exact precedent for keeping spawns out of a disc — same rule, second disc.
- Features that roll on their own hash streams (chest, camp, artifact, landmark, boss
  stations) reject inside the footprint **after their draws**, per the post-draw-skip law,
  so the streams stay aligned.

What Option B gets for free is everything Option A pays for: multiplayer needs **zero
change** (presence bounds are 1e7, `mp_manager.gd:71`; a peer in the tower is just a peer
with a y), the minimap keeps working, the hunters chase you to the door, and *"always
leave"* means walking out of it.

**What it costs, stated rather than glossed:**

- The interior is real draw calls on the web renderer whenever the player is near. The
  budget answer is **per-floor visibility gating** — only the current floor ± 1 visible —
  which is a hand-rolled interior LOD nothing in the repo does yet. The landmark budget
  discipline (`landmark_selfcheck` asserting declared radii and box budgets) is the model:
  declare the budget, self-check it.
- The `SpringArm3D` camera in tight interiors will collide constantly. First-person already
  exists on C and is the honest interior view; third-person interiors need generous ceilings
  or the camera fight begins. **Interior rooms should be authored around the camera**, not
  patched after.

### Option C — the interior as a pocket at altitude, teleport at the door

Instance the interior at the same XZ but y = +400; the door teleports. It keeps one scene
tree (so MP and groups survive) and isolates the interior by altitude instead of by walls.
Weighed and set aside: **it buys almost nothing Option B's walls don't already buy**, since
the footprint exclusion is needed for the facade in both cases — and it costs teleport
seams, windows that lie, and a minimap that shows you standing in the yard. It is the
fallback **if the interior ever outgrows the shell** (a TARDIS problem we do not have: a
tower stacks floors vertically inside its own footprint).

**Recommendation: B.** And note the escape hatch honestly: if interior scope explodes, the
door can become a load boundary *later* without wasting the field-side work — the site
function, the exclusion, the minimap marker and the shell all survive a move to Option A.

## 3. Verticality — the lifted invariant is not actually needed

The owner lifted flat-world-at-y=0 so the tower could be a real climbable object, and the
README records the price: coin settling, road placement, crocodile gravity settle, spawn
point, block bases, and the mountain-impassability chain (jump apex 3.6125 m under
`MOUNTAIN_MIN_LAYER_HEIGHT` 4.0, which is why no skill touches `JUMP_VELOCITY` —
`player_controller.gd:2952-2953`, `endless_terrain.gd:1457`).

**Here is the thing: under Option B, none of those consumers ever sees the tower's
verticality.** Coin settling and the road are chunk content — excluded from the footprint.
Crocodile gravity settle applies to chunk-spawned crocodiles — excluded. The spawn point and
block bases are untouched. The interior's floors are geometry inside one authored scene that
the flat-world systems simply never visit. Verticality is **interior-local**, and the field
stays flat at y = 0 in fact even if no longer by law.

Only two places where the flat-world assumption genuinely leaks into the tower, both found
by reading, both cheap:

1. **Wading is XZ-only** (`endless_terrain.gd:7503`, `player_controller.gd:933`) — solved by
   the dry-site nudge in §1, at the site, once, rather than by teaching the river about Y.
2. **The jump apex is a level-design constant.** Interior traversal must use stairs, lifts
   and gates — never ledges that tempt anyone to buff jump height, because the 3.6125 < 4.0
   chain is what keeps every mountain in the field impassable.

**So the plain recommendation, and it is a challenge to the lift:** re-instate the
flat-field invariant as written and scope the tower's verticality as *interior-only*. The
lift as a **global** rule buys this feature nothing and leaves the door open to exactly the
"largest engineering item in the whole design" the README warns about. If some later feature
wants field verticality, lift it then, for that feature, as its own epic. **Owner decision
— we should not quietly un-lift what he explicitly lifted, but he should know the tower
does not spend that budget.**

## 4. Interior structure — rooms, gates, and one graph to rule them

### The obstacle vocabulary is already settled; the job is making it data

Session 03 fixed the two classes — **challenge spaces** invite an attempt, **demand gates**
invite inspection, and consistent silhouette/material/lighting is what keeps a player from
farming for a jump or grinding on a lock. **Identity gates** are the third thing: passable
by one specific hero, and passing is a **permanent route transformation for everyone** —
no holds, no timers (session 02's hard-won rule).

The structural insight that makes all three cheap to persist: **an identity gate's opened
state is a monotone set.** Gates only ever open; opened-gate ids only ever accumulate. A
set that only grows merges by **union** — the same shape as the MP join snapshot's
collected-coin id set (bounded by `MAX_STATE_IDS`, `mp_manager.gd:81`) and the same
monotonicity that constraint 7 demands of everything that touches the save layers. The tower's
permanent state is *born* merge-safe if we store it as `opened_gate_ids: Set[int]` and
nothing else. Room population, alarms, loose objects — everything that *resets* — is simply
never persisted, which is the cheapest possible implementation of session 03's
"structure persists; population resets" table.

### The gate graph is a const dict, like everything else here

Rooms, gates, gate class, required identity or capability, connections: one const dict of
plain dicts, the `SPECIES` / `SKILL_TREES` idiom, no custom `Resource`. Two reasons beyond
house style:

1. **A graph as data can be audited headlessly.** This repo guards correctness with
   selfchecks (twelve of them today), and the tower needs one badly — see §6.
2. **Quests are an open set, in any order.** With the graph as data, "which quests are
   reachable at capability level X" is a query, not a playtest. The Metroidvania ordering
   the owner wants *emerges* from the graph; the graph being data is what lets us verify it
   emerges rather than hope.

### Guards

Few, per the owner's ruling. Do **not** invent a guard AI: the predator system is data rows
(`SPECIES` in `piglet_crocodile_ai.gd`), and the hunter epic (godot-test1-9rm) is already
building the retrieval behaviour arm. A tower guard is at most a species row with a patrol
arm, parented to the tower scene, walking a flat floor — every storey is flat *within
itself*, so the gravity settle a species expects still holds locally. Guards **reset on
re-entry** (they are never persisted, see above), and losing to one costs what losing to
anything costs: the 7% setback, no death, no game over. One arithmetic everywhere.

## 5. Entry, exit, checkpoints

- **One ground-floor door**, an `Area3D` trigger — the coin's pickup idiom
  (`coin.gd:1`, `extends Area3D`). No menu, no prompt: walking through the doorway *is*
  entering, because the tower is a place.
- **A visible checkpoint after each permanent route change** (session 03's rule). With no
  lives, a checkpoint means exactly two things: where a setback inside the tower returns you
  to, and where re-entry can resume. The diegetic dressing writes itself — a **service lift**
  whose stops are the checkpoints you have unlocked; unlocked stops persist (they are
  monotone: stops only accumulate — same union-merge set as the gates).
- **Leaving is walking out** — or riding the lift down. Because opened routes persist and
  ordinary guards are the only thing that comes back, the walk out through cleared floors
  is fast but never empty.
- Whether re-entry offers the lift menu (pick any unlocked stop) or always starts at the
  door is an **owner call**; the lazy v1 is door-only, with the lift as the first polish
  item, and nothing in the persistence design changes either way.

## 6. What the abduction does to the building

Session 02's audit rule is absolute: once Primm is taken, **no mandatory Primm gate may
remain reachable, or the game softlocks.** With the gate graph as data this stops being a
level-design prayer and becomes an assertion:

**`tower_selfcheck.gd`** (headless, `SELFCHECK OK`, like the other twelve) walks the graph
and asserts:

1. With the full roster, every quest room is reachable.
2. With the roster minus Primm, every room marked `needed_during_captivity` — **including
   the entire rescue route to the containment block** — is reachable.
3. The rescue route contains no Primm identity gate (trivially implied by 2, asserted
   separately anyway, because it is the one that softlocks the campaign).
4. Every demand gate's requirement is expressible by the skill tree — no gate demands a
   capability no amount of farming provides (the "forecastable" half of session 03's
   legibility rule, mechanically checked).

The captured-Primm co-op role (session 02's bounded cell block: mark patrols, work two or
three interior systems) lives in the same authored scene as ordinary rooms — it is a wing of
the building, not a second level. Windman's post-capture substitute routes are **route-state
overlays keyed on the story flag**, in the same graph, covered by the same selfcheck run
twice (pre- and post-capture roster).

## What was verified in code this session

- Spawn is world (0,0); road station 0 is the spawn; road trends +X
  (`player_controller.gd:872`, `endless_terrain.gd:562-563`).
- Distance is a radial monotone high-water mark, not `global_position.x`
  (`player_controller.gd:879`) — CLAUDE.md is stale on this.
- `is_river_at` ignores Y by documented contract (`endless_terrain.gd:7503-7507`), and
  wading is `is_on_floor() and _terrain_is_river_here()` (`player_controller.gd:933`) — the
  tower-over-a-river landmine is real.
- No autoloads: progression, sound, minimap, MP all live in `main.tscn`
  (`scenes/main.tscn:81` among others) — this is what prices the scene-swap option.
- MP presence is a Vector3 with sanity bounds at 1e7 (`mp_manager.gd:12,71`), so interior
  height and any tower site cost multiplayer nothing under Option B.
- `_biome_spot_ok` is the one home of placement legality (`endless_terrain.gd:6412`);
  `SPAWN_SAFE_RADIUS` is the existing spawn-exclusion disc (`endless_terrain.gd:420`).
- Web render distance 3 chunks / fog 0.005 (`endless_terrain.gd:44,71`) — "on the horizon"
  needs a fog-exempt impostor or it is a minimap feature.
- Minimap already rim-clamps off-disc landmark markers (`minimap_hud.gd:22-25`).
- Jump apex 3.6125 m < `MOUNTAIN_MIN_LAYER_HEIGHT` 4.0, and no skill touches
  `JUMP_VELOCITY` (`player_controller.gd:2952-2953`, `endless_terrain.gd:1457`).
- Coin pickup is an `Area3D` (`coin.gd:1`) — the door-trigger idiom exists.
- LOD sleep radius is a 3D distance check (`crocodile_lod_manager.gd:288`), `SIM_RADIUS`
  45 (`crocodile_lod_manager.gd:63`) — near-tower field simulation behaves normally.

## Owner decisions needed

1. **The commute: how far is the tower from spawn?** Recommendation: 250–400 m on −X —
   outside the spawn bubble and the initial render ring, under a minute's walk. This is a
   feel constant; it should be picked once and early because the site function hard-codes it.
2. **Re-instate the flat-field invariant?** The tower does not need the global lift (§3).
   Recommendation: yes, re-instate for the field; verticality stays interior-only. This
   reverses an explicit owner ruling, so it is his call, not ours.
3. **Setback inside the tower** — does a guard catch cost the same 7% as a predator, with
   knockback to the last checkpoint? Recommendation: yes; one arithmetic everywhere.
4. **Re-entry point** — door-only v1, or the lift menu from the start?
5. **The horizon impostor** — worth building at all, given fog and the minimap marker, or
   is the tower's far presence carried entirely by the marker and Windman's scar?

## Beads filed

See the epic **The Tower — GastroDefense HQ as a place on the map** and its children:
site + streamer exclusion (keystone), shell + minimap marker, interior v1 with the three
gate classes and a checkpoint, gate graph + `tower_selfcheck`, persistence of the opened-set,
guards + population reset, and the polish tail (horizon impostor, lift stops, more floors).
Nothing here is built; the beads are the contract for whoever builds it.
