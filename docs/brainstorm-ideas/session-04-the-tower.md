# Session 04 — The tower: GastroDefense HQ as a place on the map

**Date:** 2026-08-27 · Architect pass over the owner's two-layer structure. Amended the
same day after the owner ruled on all five open questions — §7 (systemic capture) is the
material change; the others are settled inline where they were raised.
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

**The distance is settled: 400 m.** Owner: *"not too far away, 400m seems ok"* — outside the
spawn bubble and the initial render ring, under a minute's walk, and it **must be visible on
the minimap** (which the rim-clamped marker below guarantees from any distance).

So the site is **fixed-with-a-nudge**: `tower_site()` starts at the constant offset and scans
deterministically (say, 25 m steps along −X, then lateral) until the footprint is clear of
`is_river_at`. Pure function of `run_seed` (the river field is), no RNG draw, memoized once,
same answer on every client. This is the entire concession to proceduralism the tower makes.

### Minimap and impostor — both ruled in

- **Minimap:** the geo-landmark plumbing already draws off-disc markers *"clamped to the rim"*
  precisely because *"at the default zoom most loaded landmarks are past the disc"*
  (`minimap_hud.gd:22-25`). The tower marker rides the same pattern with a unique glyph.
  Cheap, and now **required**: the owner's site ruling includes "visible on the minimap".
- **Horizon impostor: in, as wayfinding, not polish.** The fog facts made this necessary —
  web render distance is 3 chunks = 150 m (`endless_terrain.gd:44`), fog density 0.005
  (`endless_terrain.gd:71`), so at 400 m the real shell simply does not render on web. An
  always-loaded fog-exempt silhouette (a billboard or a few boxes, parented to main,
  hidden when the real shell loads) is what makes the 400 m commute feel like approaching
  something rather than walking to a map pin. The minimap gives the bearing; the impostor
  gives the destination. It ships **with the shell phase**, not in the polish tail.

  *Recorded as a restored decision, not a reversal:* the owner's earlier "not needed"
  answered the unexplained word "impostor"; once told it is the stand-in that makes the
  tower visible at all under web fog, he ruled *"да, теперь вижу что импостор нужен"* —
  yes, it is needed. A communication failure on our side, not a change of mind on his.

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

I recommended re-instating the invariant, since the tower does not spend it. **The owner
has now ruled on this twice, and the ruling stands: the invariant stays lifted.**

> *"i honestly not worried of this invariant, we can forget about it, our world can be with
> altitudes."*

So the world at large is allowed real elevation, and that is a direction, not a doc edit.
Recorded honestly as **work now in scope rather than avoided** — the finding above still
holds (the *tower* needs none of it, and this epic spends none of it), but whenever
elevation actually enters the field, the full consumer list comes due: coin height settling,
road placement, crocodile gravity settle, the spawn point, block bases, the XZ-only river
test (`endless_terrain.gd:7503`), and the mountain-impassability chain (jump apex 3.6125 m
under `MOUNTAIN_MIN_LAYER_HEIGHT` 4.0, which is also why no skill touches `JUMP_VELOCITY`).
That is tracked as its own epic in the backlog, deliberately **outside** the tower epic, so
the tower cannot silently inherit the largest engineering item in the design. Interior
level design still respects the jump-apex constant regardless — stairs, lifts and gates,
never jump-height demands.

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
- Re-entry is **ruled: both.** Owner: *"there should be a couple of options"* — the door
  and the lift-stop menu. Door-only ships first; the lift menu is an explicit later phase,
  not a maybe. Nothing in the persistence design changes between them (unlocked stops are
  already a persisted monotone set).

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

**Amended the same day:** the owner's systemic-capture ruling (§7) makes this audit a
special case. The minus-Primm run above is still exactly right for the authored beat; §7
generalizes it to every roster subset — and shows the generalization collapses to four
singleton checks.

## 7. The capture is systemic — heroes are the lives

**Owner ruling, 2026-08-27, and it is the material change of this amendment:**

> *"it's that this type of character that was active on moment of hunter bot caught you now
> considered caught and prisoned in the hq, and player should play without it until
> liberated in hq. if all caught - game over."*

Read it plainly: **any** hero can be captured, **repeatedly** — whichever one was active
when a hunter completed a grab. The captive sits in the HQ until you walk in and free him.
**All four captive = game over.** We removed lives in session 03; the owner has
reintroduced them as **the roster itself** — four heroes are four lives, except each one is
*recoverable*, and the tower is where you recover it. That fuses the failure system with
the campaign: the tower stops being optional in a way no coin penalty could ever achieve.

### Two enemy classes, two real stakes — finally

Session 02 wanted this split and admitted it could not have it (*"a hunter costs a hero"
could not be literally true while abduction was once-only*). Now it is literally true:

| | Predators | Hunters |
| --- | --- | --- |
| A loss costs | **7% of coins** + knockback | **the active hero** — and no coins |
| Recovery | keep running | walk into the HQ and free him |

Tower guards are **predator-class** — 7% and a knockback to the last checkpoint, never a
capture. A guard that could capture would let the building game-over you *inside itself*
while you are there to undo a capture, which is a spiral with no exit. (Flagged for owner
confirmation, but it is hard to see the other answer surviving contact.)

### The mechanic is already half-built, verified

Capture = **removing an index from the allowed set the E-cycle already filters.**
`switch_to_next_character()` already consults `my_character_indices()` and cycles within
the returned array (`player_controller.gd:1279-1284`), and that function's own docstring
says the set form *"costs nothing and needs no special case if that ever changes"*
(`mp_manager.gd:1384`). Solo capture is the same shape: a local captured-set intersected
into the allowed indices. At the grab, auto-switch the player to the next free hero on the
spot while the hunter disengages carrying the body; if no hero remains, game over — and
`game_over_ui.gd` already exists, group-wired, waiting to be repurposed.

One save-model note, stated now so it is not discovered later: **the captured set is the
first prominent non-monotone world field** — captures add, liberations remove — so it can
never ride the union/max merge. It lives in the plain world snapshot (session 03's point 3),
which is single-writer per install today, so a plain overwrite is correct.

### The softlock answer is redundancy — owner ruling

Any subset of the roster can be captive at once, so the route to the cells must work for
**every possible surviving subset**. The catastrophe to design against: the only way to the
cells is a scanner field only Pho-boman passes, and Pho-boman is in the cell — the run is
dead with three heroes free and no game-over fired.

I proposed stripping the prison route of gates entirely. **The owner ruled the other way:**

> должно быть много путей, hq должен быть масштабен
> *(there should be many paths; the HQ should be large-scale)*

Not removal — **redundancy**. And it is the better answer: a gate-free corridor would have
made the most important route in the game the blandest one, and identity gates stay
meaningful everywhere, prison routes included. Formalized, the rule the building must obey:

> **For every non-empty subset S of free heroes, at least one route to the cells is
> traversable by S alone** — where the captives are precisely the heroes *not* in S, and a
> hero in a cell cannot open a gate on the way to his own cell.

Two things make this checkable instead of a prayer:

1. **A route's traversability-by-S must count every gate class.** An identity gate on a
   route is passable by S iff its hero is in S — and a **hero-specific demand gate is the
   same trap in a different silhouette**: a `primm_blink` receptacle is impassable without
   Primm at any rank. The graph rows already carry both fields, so the check reads what the
   rooms are built from.
2. **Gate passability is monotone in the roster** — every gate keys on the *presence* of an
   identity (even Pho-boman's "key is an absence" is *his* presence at the scanner), so
   adding a hero never closes a route. Promote that to a design law: **no gate may ever key
   on a hero's absence.** Under it, the 15 subsets collapse to the 4 singletons — if each
   hero alone has a route, every surviving subset does. `tower_selfcheck` should
   **enumerate all 15 anyway**: fifteen graph walks cost nothing, and the exhaustive check
   stays correct even if some future mechanic quietly breaks the monotonicity lemma. The
   lemma is the design insight; the enumeration is the guard.

The liberation action at a cell must itself be performable by any hero, obviously — assert
it in the same check. Corollary worth saying out loud: under this rule **a lone last hero
always has a route to attempt the rescue** — game over is genuinely "the hunters won four
times," never "the level design won."

With a large graph this audit is not something a human can eyeball, which is the real
change of status: **`tower_selfcheck` goes from nice-to-have to load-bearing.** Every new
wing ships against it or does not ship.

### "Large-scale, many paths" — the price, stated honestly

This ruling is the single biggest content commitment in these four sessions, and it
collides with three standing facts: every quest must be **solo-completable in any order**;
every subset must reach the cells (above); and this project has **no level-design
pipeline** — no hand-authored traversed geometry exists anywhere, no autoloads, and the
perf target is web `gl_compatibility`. Pretending a large authored interior is a normal
feature would be the quiet failure mode. So, plainly:

- **Build rooms from the graph, by code.** The house discipline is code-built geometry with
  a data row driving it — landmarks are *"blocky code-built sculpture in the house style"*
  built by `landmark_builders.gd`, species are `SPECIES` rows. The scalable version of a
  big HQ is the same shape: `TOWER_GRAPH` rows drive a floor/wing builder; hand-craft only
  the gate-mechanism set pieces. That keeps the graph as the single source of truth (what
  the selfcheck walks IS what the player walks), keeps content velocity at
  "a new wing = new rows", and avoids inventing a Godot-editor authoring pipeline this
  CI-driven project has never had. This is the one architectural bet that makes
  "масштабен" affordable; it is also reversible room-by-room (any single room can be a
  hand-authored `.tscn` dropped in where the builder is not enough).
- **The scale arrives in stages, and each stage is audit-green.** The minimum viable
  version that still *reads* as big: the entrance atrium with long sightlines up the
  building, the lift panel showing floors that exist but are not yet reachable, locked
  routes you can see through, plus **two genuinely parallel routes to the cell block** on
  day one — scale is felt through sightlines and denied doors, not through built volume.
  Do not build fifteen routes up front; build the graph idiom that makes the sixteenth
  cheap.
- **Per-wing/per-floor visibility gating is mandatory from the first storey**, and each
  wing declares a draw-call budget the selfcheck asserts (the `landmark_selfcheck`
  discipline). A large interior that renders all at once does not survive the web target.

**Floors, wings, or depth?** Asked directly, answered directly:

- **Wings (XZ spread) are where "many paths" lives.** Parallel routes want parallel
  corridors; the streamer exclusion is 2D on `Vector2i` chunks, so a wider footprint is
  just a larger excluded disc — no new machinery. Wings also read as "large-scale" from
  outside.
- **Floors (Y) are where the tower's identity and the lift live.** Vertical extent is
  invisible to the streamer (chunk keying is XZ-only, `endless_terrain.gd:2596-2597`) and
  costs nothing but its own geometry.
- **Depth (sub-levels below y = 0) is the expensive axis: skip it.** The ground is a
  per-chunk `MeshInstance3D` sharing one `PlaneMesh` resource plus a per-chunk ground
  `StaticBody3D` (`endless_terrain.gd:2141-2151` and the ground-collision block around
  `:2721`), so a basement means chunk-granularity holes — footprint chunks must skip both
  ground mesh and ground collision and the builder must author replacement ground. Possible,
  but it buys nothing wings and floors don't already provide. If the fiction ever demands a
  vault level, it is one authored floor whose *elevator says* B2 — nobody can tell.

So: **wings for routes, floors for scale, no digging.**

### The authored Primm beat survives — capture is taught, then armed

Recommendation, stated as the coordinator asked: **yes, the beat survives.** Primm's
capture stays the scripted story turn — the steel box, the floor-plus-beat encounter, the
Windman wound, all of session 02. Systemic capture **arms after the beat**: before it,
hunters cost the predator arithmetic (session 02's original rule), and the authored beat is
the moment the rule visibly changes, demonstrated on the hero it hurts most. Arming it from
minute one would let a random early grab pre-empt the authored scene and teach the
mechanic as a surprise. **Owner confirmation wanted, since it sequences his ruling rather
than restating it.**

The death-spiral risk also needs naming: each capture closes identity routes and weakens
the party, which invites more captures. The mitigation is already doctrine — session 02's
mercy lives in the encounter director, *before contact* — and the director simply gains
roster size as an input: fewer free heroes, gentler encounter geometry, invisibly. That
lands in the hunter epic's director bead, not here.

### Multiplayer — reassign first, imprison last (owner ruling)

> *"если игроку в мультиплеере не осталось героев, то он может только ходить своим героем
> внутри небольшой тюрьмы в замке. если же остались, например игрока два, а героев три, то
> достается свободный"*

The rule, in order: a player's active hero is captured → if **any free hero is unclaimed,
the player is given one** and keeps playing in the field → only when **no free hero is
available** does that player play as their captive **inside the prison**, in session 02's
bounded role (mark patrols, operate two or three interior systems; no phasing, no combat
loop, no solo escape).

**Verified: the reassignment is one existing lobby call, not a subsystem.**
`server/room.go:442` `SetHero` already atomically releases *all* of a member's hero claims
and claims the new one, under the process-wide lock (`room.go:273`), refusing a contested
claim with `errHeroTaken` (`room.go:73,458-460`) and re-broadcasting the `heroes` truth to
the room. So when two players lose heroes at once, the lock serializes their claims: the
first wins, the second gets the refusal plus the fresh truth and picks another free hero —
or, none remaining, falls to the prison role. **Deterministic, race-free, zero server
change.** What the lobby does *not* know is which heroes are captive — that is game state,
and the lobby's design law is no game state. So the captive set travels the mesh and the
join snapshot (absolute values, type-checked, rate-limited — the standard discipline), and
clients simply never offer a captive hero for claiming. If a hostile client claiming a
captive hero ever matters in practice, teaching the lobby a small captive set is the
hardening — noted, not built.

**Solo and co-op really are one rule.** A player's available heroes are
`hand ∩ free` — the hand filter already exists (`my_character_indices()`,
`player_controller.gd:1279-1284`), and the captive set is one more intersection. Solo, the
hand is all four, so capture just shrinks the free set; the prison role triggers when a
player's intersection is empty *while free heroes exist elsewhere* — impossible solo — and
**game over is the same condition in both modes: the free-hero set is empty.** Solo that
means all four caught (the owner's ruling verbatim); in a room it means every hero in the
room is captive and every player is in the prison — nobody left to rescue anyone, which is
exactly when the game should end. The roster is read as **shared, world-level** here (the
owner's phrasing implies it); flagged below rather than silently assumed.

Two consequences worth saying out loud rather than discovering in testing:

- **The capture penalty scales with party size in the player's favour.** A full room of
  four rarely benches anyone; a solo player feels every capture immediately. That is
  probably the right direction — co-op as the gentler experience — but it is a tuning fact
  the encounter director should know about, not an accident.
- **The prison is a play space, not a story location.** A captive player *stands in it*,
  so the cell block needs a playable interior (small, bounded, with its two or three
  operable systems) and it is simultaneously the destination of every rescue route — the
  many-paths requirement and the captive role meet in the same rooms. Design them once,
  for both jobs.

### What game over means — owner decision still open

The ruling names the trigger, not what is behind the screen. Two coherent options:

- **Hard:** the recall completes; the world is finished; the menu offers New Game only.
  Maximally literal, and brutal in a game whose save *is* the world.
- **Soft:** a game-over screen, then Continue reopens the world with **one hero freed by
  the Junior Engineer** — canon supports it (he returns running his own investigation), and
  it converts game over into a scripted bailout with a story cost rather than a deleted
  world.

Recommendation: the soft option, because "the game is the world" makes world deletion the
harshest possible punishment for what is ultimately hunter attrition. But this is a real
fork and it is the owner's, not ours.

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

Added by the same-day amendment (§7):

- `switch_to_next_character()` already cycles within an allowed-index set from
  `my_character_indices()` (`player_controller.gd:1279-1284`), whose docstring says the set
  form *"costs nothing and needs no special case if that ever changes"*
  (`mp_manager.gd:1384`) — systemic capture is one more intersection on that set.
- `game_over_ui.gd` exists, group-wired, built in code — the game-over surface is a
  repurpose, not a new screen.
- `server/room.go:442` `SetHero` atomically swaps a member's hero claims under the
  process-wide lock (`room.go:273`) and refuses contested claims with `errHeroTaken`
  (`room.go:73`) — capture reassignment is one existing lobby call.
- The ground is a per-chunk `MeshInstance3D` sharing one `PlaneMesh` resource plus a
  per-chunk ground `StaticBody3D` (`endless_terrain.gd:2141-2151`, ground-collision block
  near `:2721`) — sub-levels would mean chunk-granularity ground holes, which is why depth
  is the axis to skip.
- Chunk keying is XZ-only (`endless_terrain.gd:2596-2597`) — floors are invisible to the
  streamer.

## Owner decisions — settled and open

**Settled (2026-08-27, same-day rulings):**

1. **Commute: 400 m**, and the tower must be visible on the minimap. (§1)
2. **The flat-world invariant stays lifted** — ruled twice; the world may gain altitudes.
   The consumer list is tracked as its own backlog epic, outside this one. (§3)
3. **Capture is systemic** — the active hero is imprisoned in the HQ until liberated; all
   caught = game over. (§7, the material change of this amendment)
4. **Re-entry: both** — the door first, the lift-stop menu as an explicit later phase. (§5)
5. **The horizon impostor is in** — restored once the term was explained; it ships with the
   shell phase as wayfinding. (§1)
6. **Softlock by redundancy, not removal** — many paths, a large-scale HQ; every free
   subset keeps a route to the cells. (§7)
7. **Multiplayer: reassign first, imprison last** — a benched player gets an unclaimed free
   hero when one exists; the prison role is the last resort. (§7)

**Still open:**

1. **Guards are predator-class (7%), never capture** — recommended in §7 so the building
   cannot game-over you while you are inside undoing a capture; wants his yes.
2. **Systemic capture arms after the authored Primm beat** — recommended sequencing (§7)
   so the mechanic is taught before it is armed; it interprets his ruling rather than
   restating it.
3. **What is behind the game-over screen** — hard (world ends, New Game only) vs soft
   (Continue reopens the world with one hero freed by the Junior Engineer at a story
   cost). Recommendation: soft, because the save *is* the world. (§7)
4. **Game over in a room is world-level** — free-hero set empty across the whole room, not
   per player. Adopted as the reading of his phrasing; flagged rather than assumed. (§7)

## Beads filed

See the epic **The Tower — GastroDefense HQ as a place on the map** and its children:
site + streamer exclusion (keystone), shell + impostor + minimap marker + door, interior v1
with the three gate classes and a checkpoint, gate graph + the subset-reachability
`tower_selfcheck` (load-bearing under the many-paths ruling), persistence of the opened
sets, guards + population reset, the cell block + liberation + capture mechanic, the MP
capture sync + captive role, and the staged scale-out (wings, floors, lift stops). The
field-altitude consumer list is its own backlog epic, deliberately outside. Nothing here
is built; the beads are the contract for whoever builds it.
