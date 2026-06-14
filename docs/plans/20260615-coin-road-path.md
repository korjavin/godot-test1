# Coin Road Path

## Overview
Replace the current per-chunk random coin scatter with a single continuous **coin
road**: a meandering parametric path that runs across the infinite world and
carries all the coins. The road weaves with broad curves, zig-zags, and strong
left/right turns (but always makes net forward progress along a primary axis),
is 20–30 m wide (varying), and places coins closely enough that each is in clear
sight of the previous one. Off-road areas get **no coins**, so the road becomes a
strong incentive to follow.

- **Problem it solves:** today coins are scattered randomly per chunk
  (`spawn_coins_in_chunk` in `scripts/endless_terrain.gd`), giving no direction
  or sense of journey. We want coins to pull the player along a route.
- **Key benefit:** a readable "go this way" trail that we can later decorate with
  fights/quests at points along the road.
- **Integration:** the road centerline is a *deterministic global function of a
  station index* (seeded from a fixed world seed, **not** per-chunk RNG), so the
  trail lines up seamlessly across chunk seams. Each chunk, during its existing
  independent generation, spawns exactly the coins that fall inside it.

## Context (from discovery)
- **Files/components involved:**
  - `scripts/endless_terrain.gd` — the world engine. Coins are spawned in
    `spawn_coins_in_chunk(chunk_pos, parent_chunk, obstacles)` (≈ line 1254),
    called once per chunk from `create_chunk` → `spawn_objects_in_chunk` (≈ line
    560). `chunk_size = 50.0`. `world_to_chunk()` / `chunk_to_world()` (≈ line
    381–409) map world ↔ chunk. `_point_over_block()` (≈ line 1331) tests block
    footprints.
  - `scenes/collectibles/coin.tscn` + `scripts/coin.gd` — **no change needed**;
    collection is event-driven (`body_entered`) and the coin is chunk-parented so
    it unloads with its chunk. Coin uses `randf()` only for a visual bob phase.
- **Related patterns found:**
  - Everything procedural is **seeded deterministically** so a chunk regenerates
    byte-for-byte identically. The road must follow this rule.
  - Spawned objects are **parented to the chunk MeshInstance3D** so they free with
    the chunk; coins must keep doing this.
  - Positions are stored **chunk-local** (relative to chunk center) on
    chunk-parented nodes.
- **Dependencies identified:** none external. `main.tscn` does **not** override
  `coins_per_chunk` / `min_coin_spacing` / `spawn_coins`, so the script defaults
  are authoritative and safe to repurpose.
- **No automated test framework** exists (pure editor-driven Godot 4.5 project).
  Verification is **in-editor / manual** (user's choice).

## Development Approach
- **Verification approach:** in-editor / manual (no test harness exists in this
  project). Each task ends with a concrete visual/behavioral check run from the
  Godot editor (`godot --path . scenes/main.tscn`), treated with the same rigor a
  test would be: the check must pass before starting the next task.
- Complete each task fully before moving to the next; make small, focused changes.
- **CRITICAL: keep determinism.** All road geometry must derive from the station
  index `k` and a fixed world seed — never from per-chunk RNG or per-frame state —
  so chunks line up at seams and regenerate identically on revisit.
- **CRITICAL: update this plan file if scope changes during implementation.**
- Maintain backward compatibility for desktop and web builds (visual-only change;
  no web gating needed since coins look/play the same on every platform — it is an
  entity-placement change, not a render-quality change).

## Testing Strategy
- **Automated unit/e2e tests:** not applicable — the project has no test
  framework, runner, or CI test step (only a web-export build job). Do **not**
  fabricate a framework.
- **Manual in-editor verification** stands in for tests. Per task, the relevant
  checks from the "Manual verification checklist" (Task 4) are exercised. The
  full pass lives in Task 4.
- Because the road math is pure and deterministic, the highest-value checks are:
  (a) road is continuous across chunk seams, (b) revisiting a chunk reproduces the
  same coins, (c) off-road is empty.

## Progress Tracking
- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document issues/blockers with ⚠️ prefix
- update plan if implementation deviates from original scope

## Solution Overview

**The road is a parametric, heading-integrated path** sampled at integer station
indices `k` (one coin candidate per station):

- Station 0 sits at world origin `(x=0, z=0)` with heading `0` (pointing along
  +X), so the player — who spawns at origin — is on the road immediately.
- `heading[k+1] = clamp( heading[k] * (1 - RESTORE) + turn_noise(k),
  -MAX_HEADING, +MAX_HEADING )`, where `turn_noise(k)` is a deterministic
  per-station angle from `hash(k)`. The `RESTORE` term gently pulls heading back
  toward the +X axis; the clamp keeps it within `MAX_HEADING` (< 90°).
- `center[k+1] = center[k] + STEP * Vector2(cos heading, sin heading)`.
  Station index `k` can be negative (road extends both ways from origin); the
  backward recurrence mirrors the forward one.

**Why a forward bias / heading cap (key design decision):**
- A *truly* unbounded random-walk path (full U-turns / loops) is recurrent in 2D
  — it can wander inside a finite region arbitrarily long, so we could never bound
  "how much path to generate to cover this chunk." That breaks the engine's
  seamless, bounded, deterministic per-chunk generation.
- Keeping `|heading| < 90°` makes the centerline's **X strictly increasing in
  `k`**, so a chunk's X-range maps to a *contiguous* `k`-range — coverage is
  bounded, ordering-independent, and seam-correct.
- The result still reads as a real road with genuine turns (heading can swing to
  near-90°, i.e. steep diagonals that feel like sharp bends), curves, and
  zig-zags — it just always trends forward, which is exactly "encourage the
  character to move a certain direction."
- *Excluded:* literal loops / switchbacks that reverse net direction. If those are
  ever wanted, they require a heavier **spatial-bucket** scheme (bucket every
  station into a `chunk → stations` dictionary and extend the path until all
  active chunks are covered) plus a guaranteed drift to terminate — noted here as
  a future option, intentionally not built now.

**Coin placement per station `k`:**
- Lateral offset `lateral(k) = smooth_noise(k) * road_width(k) / 2`, applied
  **perpendicular** to the heading. `smooth_noise(k)` is low-frequency so the
  coin line *weaves smoothly* across the corridor rather than jumping side to
  side — consecutive coins stay close ⇒ always in sight of the previous one.
- `road_width(k)` varies smoothly between `ROAD_WIDTH_MIN` (20 m) and
  `ROAD_WIDTH_MAX` (30 m).
- Coins sit at ground height (`COIN_GROUND_HEIGHT`). If a coin would land inside a
  block footprint, it perches on that block's top if climbable, else it is
  skipped (rare; structures are sparse, so the visible chain is preserved).

**Per-chunk integration (deterministic, seamless, no duplicates):**
1. Compute the chunk's world X-range, widened by `ROAD_WIDTH_MAX/2 + margin`.
2. Extend the cached station array (member state on `EndlessTerrain`) until it
   covers that widened X-range in both directions. The cache grows contiguously
   from station 0 and is a pure function of `k`, so load order doesn't matter and
   it is computed once then reused.
3. Scan the covered `k`-range; for each station compute the coin's world
   position; if `world_to_chunk(coin_world) == chunk_pos`, spawn it (converted to
   chunk-local) and parent it to the chunk. Bucketing by the coin's **final**
   chunk guarantees no coin is dropped twice or missed at a seam.

## Technical Details

**New tunables on `EndlessTerrain` (replace the old scatter tunables):**
- `@export var spawn_coins: bool = true` — kept.
- `@export var road_coin_spacing: float = 7.0` — world-meters of `STEP` between
  stations; small enough that each coin is in sight of the last.
- `@export var road_width_min: float = 20.0`
- `@export var road_width_max: float = 30.0`
- `@export var road_turn_rate_deg: float = 18.0` — max per-station heading jitter
  magnitude (controls curviness / zig-zag tightness).
- `@export var road_max_heading_deg: float = 78.0` — heading cap from +X
  (controls how hard the road can turn; must stay < 90° to keep X monotonic).
- `const ROAD_RESTORE: float = 0.06` — heading restoring pull toward +X.
- `const ROAD_WORLD_SEED: int = ...` — fixed seed mixed into `hash(k)` so the road
  is stable but distinct from object/croc seeds.
- Keep `COIN_GROUND_HEIGHT` and `COIN_BLOCK_OFFSET` (perch fallback). **Remove**
  `coins_per_chunk`, `min_coin_spacing`, and `COIN_AIR_HEIGHT` (road coins are
  ground-level; no random spacing budget; no random air coins).

**New internal state on `EndlessTerrain`:**
- Cached stations covering `[road_k_min, road_k_max]`, e.g.
  `var road_stations: Array = []` (each entry `{ center: Vector2, heading: float }`)
  plus the index bounds, **or** two growable arrays for `k >= 0` and `k < 0`.
  Cache only grows; never invalidated (the road is static & infinite).

**New helper functions on `EndlessTerrain`:**
- `_road_hash01(k: int) -> float` — deterministic `[0,1)` from `k` + seed.
- `_road_turn(k: int) -> float` — signed angle from `_road_hash01`.
- `_road_extend_to_x(x_min: float, x_max: float) -> void` — grow the station cache
  forward/back until it spans the X-range.
- `_road_width(k: int) -> float` — smooth 20→30 m width at station `k`.
- `_road_lateral_unit(k: int) -> float` — smooth `[-1,1]` weave factor.
- `_road_coin_world(k: int) -> Vector3` — final world coin position (center +
  perpendicular lateral, at ground height).

**Processing flow (rewritten `spawn_coins_in_chunk`):**
```
if not spawn_coins or coin_scene == null: return
center = chunk_to_world(chunk_pos)
x0 = center.x - chunk_size/2 ; x1 = center.x + chunk_size/2
pad = road_width_max/2 + margin
_road_extend_to_x(x0 - pad, x1 + pad)
for k in covered station range:
    cw = _road_coin_world(k)
    if world_to_chunk(cw) != chunk_pos: continue
    local = Vector3(cw.x - center.x, cw.y, cw.z - center.z)
    if _point_over_block(local.x, local.z, obstacles):
        # perch on climbable block top, else skip
        ...
    spawn coin at local under parent_chunk
```

## What Goes Where
- **Implementation Steps** (`[ ]`): all code changes in `endless_terrain.gd`, the
  doc updates, and the in-editor verification checks.
- **Post-Completion** (no checkboxes): subjective feel/tuning passes and the web
  export smoke check that need a human at the controls.

## Implementation Steps

### Task 1: Add deterministic road-path math + station cache

**Files:**
- Modify: `scripts/endless_terrain.gd`

- [x] Add the new road tunables (`road_coin_spacing`, `road_width_min/max`,
  `road_turn_rate_deg`, `road_max_heading_deg`) and consts (`ROAD_RESTORE`,
  `ROAD_WORLD_SEED`) in the coin config section, with teaching-style comments
  matching the file's density.
- [x] Add the station cache state (`road_stations` + index bounds) in the
  internal-state section.
- [x] Implement `_road_hash01(k)` and `_road_turn(k)` (deterministic, seed-mixed).
- [x] Implement the forward+backward station recurrence and
  `_road_extend_to_x(x_min, x_max)` that grows the cache contiguously from
  station 0 until it spans the requested X-range (assert `road_max_heading_deg <
  90` so X stays monotonic).
- [x] Implement `_road_width(k)`, `_road_lateral_unit(k)`, and
  `_road_coin_world(k)` (center + perpendicular weave at `COIN_GROUND_HEIGHT`).
- [x] **Verify (in-editor):** temporarily call the helpers in `_ready()` to
  print station 0..40 world positions; confirm X is strictly increasing, the path
  visibly meanders (z changes sign), and width stays in [20,30]. Remove the temp
  prints before finishing the task. Must pass before Task 2.
  Verified via `godot --headless --quit-after 5 --path . scenes/main.tscn`:
  stations -10..40 dumped; X strictly increasing in both directions
  (-71.46 → 268.71), centerline z changed sign 5 times (meanders), width stayed
  in [20.00, 30.00]; temp prints removed and re-run confirmed clean (no errors).

### Task 2: Rewrite `spawn_coins_in_chunk` to lay coins along the road

**Files:**
- Modify: `scripts/endless_terrain.gd`

- [x] Replace the random-scatter body with the road flow: widen the chunk X-range,
  call `_road_extend_to_x`, scan the covered `k`-range, and spawn only coins whose
  `world_to_chunk(coin_world) == chunk_pos`, converted to chunk-local and parented
  to `parent_chunk`.
- [x] Handle block overlap via `_point_over_block`: perch on a climbable block top
  (`COIN_BLOCK_OFFSET`) when the coin lands on one, else skip.
- [x] Keep the `spawn_coins` toggle and `coin_scene` null-guard; update the
  function docstring to describe the road behavior.
- [x] **Verify (in-editor):** headless parse/run passed
  (`godot --headless --quit-after 5 --path . scenes/main.tscn`): no script/parse
  errors and the world initialized. Temporary per-chunk coin-count prints confirmed
  the road behavior: station 0's coin lands in chunk (0,0) (player spawns on the
  road); the on-road chunks form a single CONTIGUOUS chain with no gaps and no
  duplicates at seams (forward +X through (0,0)→(1,0)→…→(5,0); backward through
  (-1,-1)→(-2,-1)→…→(-5,-5)); every far-from-road chunk spawned 0 coins (off-road
  empty). Temp prints removed and re-run confirmed clean. Full visual confirmation
  (line-of-sight feel, walking seams in the running game) is deferred to the manual
  Task 4 — it requires a human at the controls.

### Task 3: Remove obsolete coin scatter config and dead references

**Files:**
- Modify: `scripts/endless_terrain.gd`

- [x] Remove `coins_per_chunk`, `min_coin_spacing`, and `COIN_AIR_HEIGHT` and any
  now-dead local logic (random kind roll, air-coin branch, per-chunk `placed`
  spacing list) left over from the old scatter.
  Removed the three declarations; the Task 2 rewrite had already removed all the
  dead local scatter logic (no `placed` list, no random kind roll, no air-coin
  branch remained), so nothing further to strip.
- [x] Grep the file (and project) for the removed identifiers to confirm no
  remaining references; update neighboring comments/the file header note about
  coins so they describe the road.
  Project-wide grep of `scripts/ scenes/ project.godot` returned ZERO matches for
  all three identifiers. Updated comments: the coin-height block, the
  spawn_coins call-site comment, the `_point_over_block` docstring, and the
  `ROAD_WORLD_SEED` comment (dropped its stale "coin-scatter seeds" mention) — all
  now describe the deterministic station-indexed parametric road.
- [x] **Verify (in-editor):** project loads with no parser errors/warnings about
  missing identifiers; game still runs and the road still spawns. Must pass before
  Task 4.
  Headless parse/run clean: `godot --headless --quit-after 5 --path . scenes/main.tscn`
  showed no script/parse/missing-identifier errors and the world fully initialized
  (chunks + crocodiles spawned). Only the pre-existing "material is null"
  dummy-renderer noise appeared (unrelated/expected in headless). Full visual
  confirmation that the road still spawns in the running game is in Task 4.

### Task 4: Manual verification & tuning pass

**Files:**
- Modify: `scripts/endless_terrain.gd` (tuning constants only, if needed)

- [x] **Continuity / visibility:** verified headlessly — consecutive coin world
  positions (`_road_coin_world(k)`→`(k+1)`) stay close: over 600 pairs in k∈[-300,300]
  the max gap was 11.06 m (avg = 7.00 m = `road_coin_spacing` exactly), well under the
  sight-friendly ceiling of `road_coin_spacing*2.5` = 17.5 m. Width stayed in [20,30] m
  with the full 10 m span observed (genuinely varies). No tuning needed.
  (Subjective on-screen line-of-sight "feel" deferred to human — Post-Completion.)
- [x] **Turns & shape:** verified headlessly — over k∈[-200,200] the integrated
  heading spans 136.6° (not a straight line), the centerline z crosses zero 7 times
  (meanders left/right), and the heading's discrete curvature spans 68.3° (not a single
  pure sine — broad and finer variation present). X stays strictly increasing (forward
  bias intact). No tuning needed. (Subjective "does it look like a good road" feel
  deferred to human — Post-Completion.)
- [x] **Seam correctness:** verified headlessly by replicating the real spawn rule
  (`world_to_chunk(_road_coin_world(k)) == chunk_pos`) across a band of chunks the road
  passes through (cx∈[-5,10], cz∈[-8,8]). All 151 in-region stations were claimed by
  EXACTLY ONE chunk (no duplicates), the claimed set equaled the ground-truth set (no
  gaps, no extras), and the on-road station indices were contiguous (max consecutive-k
  gap = 1). (Walking the seams in-game deferred to human — Post-Completion.)
- [x] **Determinism:** verified headlessly — two fresh `EndlessTerrain` instances
  produce byte-identical `_road_coin_world(k)` for all k∈[-200,200]; and extending the
  cache directly to x=±3500 vs staged (±700 then ±3500) yields identical station values
  for all shared k. Load-order-independent and reproducible, as required for chunk
  unload/revisit. (In-game far-walk-and-return confirmation deferred to human —
  Post-Completion.)
- [x] **Off-road incentive:** verified headlessly — for 5 sample cx values, picking a
  chunk 6 rows (300 m) in cz away from the road's occupied band, the real bucket rule
  spawned 0 coins in every off-road chunk. Off-road is genuinely empty. (Subjective
  "feels empty, pulls you back" deferred to human — Post-Completion.)
- [x] **Performance (F3 overlay):** FPS/draw-call/node-count "feel" requires a human
  at the controls with the F3 overlay — deferred to human (Post-Completion). Headless
  reasoning supports no regression: coins are still one chunk-parented node each and the
  road places fewer, more concentrated coins than the old per-chunk scatter, so the
  node/draw-call count for coins is no worse than before. Web smoke check is in
  Post-Completion.

### Task 5: Verify acceptance criteria
- [x] Coins form a road, not a scatter (Overview goal 1).
  Confirmed by read-through: `spawn_coins_in_chunk` (endless_terrain.gd ~L1511)
  iterates station indices `range(road_k_min, road_k_max+1)`, placing one coin per
  station via `_road_coin_world(k)` — no `randf`/random scatter remains. Project-wide
  grep for the old scatter identifiers (`coins_per_chunk`, `min_coin_spacing`,
  `COIN_AIR_HEIGHT`) = 0 matches. Backed by Task 4 invariant 1.
- [x] Road meanders with curves/zig-zags/turns, always trending forward (goal 2).
  `_road_extend_to_x` (~L1370) integrates the heading recurrence
  `heading[k+1] = clamp(heading[k]*(1-ROAD_RESTORE) + _road_turn(k), ±max_heading)`
  (L1415-1417) — restoring pull + per-station turn give genuine curves/zig-zags;
  `assert(road_max_heading_deg < 90)` keeps `cos(heading)>0` so X is strictly
  increasing (forward bias). Backed by Task 4 invariants 3 (heading spans 136.6°,
  z sign-changes 7×, curvature spread 68.3°) and 4 (X strictly increasing).
- [x] Corridor is ~20–30 m wide and varies (goal 3).
  `_road_width(k)` (~L1453) lerps `road_width_min`(20)→`road_width_max`(30) via a
  low-frequency cosine of `k`, so the corridor smoothly breathes wide/narrow.
  Backed by Task 4 invariant 2 (width stayed in [20,30] m; full 10 m span observed).
- [x] Coins are dense enough to each be in sight of the previous (goal 4).
  `road_coin_spacing = 7.0` m `STEP` between stations plus a deliberately
  low-frequency `_road_lateral_unit` weave (~L1469) so consecutive coins barely
  shift sideways. Backed by Task 4 invariant 1 (max consecutive gap 11.06 m, avg
  7.00 m, under the sight ceiling of 17.5 m). On-screen line-of-sight "feel" is
  visual feel deferred to human - Post-Completion.
- [x] Off-road has no coins (goal 5).
  `spawn_coins_in_chunk` buckets each coin to the chunk its FINAL world position
  lands in: `if world_to_chunk(cw) != chunk_pos: continue` (L1576), so a chunk the
  road never enters spawns nothing. Backed by Task 4 invariant 7 (off-road sample
  chunks spawned 0 coins each). "Pulls you back" feel is deferred to human -
  Post-Completion.
- [x] Generation is deterministic and seamless across chunk seams.
  Everything below the "COIN ROAD MATH" header is a pure function of `k` +
  `ROAD_WORLD_SEED` (no per-chunk RNG, no per-frame state); the `road_stations`
  cache is contiguous, grows from station 0 outward, and is never invalidated, so
  load order can't change it. Seam-correctness comes from the same final-chunk
  bucket rule (L1576) — each coin spawned by exactly one chunk. Backed by Task 4
  invariants 5 (seam: 151 stations each claimed by exactly one chunk, no gaps/dupes)
  and 6 (two fresh instances byte-identical; direct vs staged extension identical).

  Read-through outcome: all six criteria genuinely met by the code; no gaps or bugs
  found, so `endless_terrain.gd` was NOT changed. Final headless smoke check
  (`godot --headless --quit-after 5 --path . scenes/main.tscn`) ran clean — only the
  expected/ignored "material is null" dummy-renderer noise, no script/parse errors.

### Task 6: [Final] Update documentation
- [ ] Update `CLAUDE.md` — replace the coin description (under "Everything in the
  world is spawned procedurally" / performance conventions) with the road model:
  deterministic station-indexed parametric path, forward-biased, chunk coverage by
  X-range, off-road empty. Note the no-loops design decision and the spatial-bucket
  alternative.
- [ ] Update `README.md` / `QUICKSTART.md` only if they describe coin behavior
  (skip if they don't).
- [ ] Move this plan to `docs/plans/completed/`.

## Post-Completion
*Items requiring a human at the controls — no checkboxes, informational only.*

**Manual verification / feel:**
- Subjective "does this make me want to follow it?" tuning of spacing, width, and
  turn rate — best judged by playing, not by code review.
- Confirm crocodiles spawning on/near the road feel like an intentional gauntlet
  (they spawn per-chunk independently and may sit on the road; this is fine and is
  where future "fights" attach).

**Web build smoke check:**
- Export the Web preset (`godot --headless --export-release "Web"
  build/web/index.html`) and serve it (`./serve.sh`); confirm the road renders
  and performs the same in-browser (coins are a placement change, not a
  render-quality one, so no `.web` gating is involved).

**Future options (not in scope):**
- True loops / switchbacks via the spatial-bucket coverage scheme (see Solution
  Overview).
- Occasional jump/air coins or small coin clusters at waypoints once
  fights/quests are added along the road.
