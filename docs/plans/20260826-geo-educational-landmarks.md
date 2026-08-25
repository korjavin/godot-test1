# Geo-educational landmarks — recognizable famous places in the world

## Overview

Bead `godot-test1-cz3`. Bring back the educational identity: **rare, recognizable
famous real places** scattered across the endless field — Stonehenge, the Moai of
Easter Island, the Pyramids of Giza, the Golden Gate Bridge, the Statue of Liberty,
the Plaza Mayor, the Eiffel Tower, the Taj Mahal. Blocky code-built sculpture in the
house style; the owner's bar is **"not necessarily ideal, but recognizable"**.

Two halves:

1. **World generation** (`scripts/endless_terrain.gd`) — a fourth member of the
   artifact / camp / chest landmark family, built on the *identical* recipe: its own
   salt hash stream with fresh coordinate primes, a candidate loop where `obstacles`
   exists, all stone through `create_box` into the chunk's ONE MultiMesh + ONE
   `BlockCollision` body, one footprint appended for crocodile exclusion and coin
   perching, a measured survival rate that tunes the rarity constant.
   **Registry-driven**: a `const LANDMARKS: Array` of
   `{ builder, name_key, fact_key, radius }`, one builder function each, so a later
   wave is one function + two CSV rows.

2. **The educational toast** (`scripts/landmark_toast.gd`, new) — walking within
   ~15 m of a landmark pops a small HUD card with its name and a one-line fact,
   localized en/de, once per approach, re-armed on leaving. The proximity check runs
   on the script's own throttled tick (the `minimap_hud.gd` / `crocodile_lod_manager.gd`
   pattern), never per frame.

Plus a permanent `scripts/landmark_selfcheck.gd` and a throwaway measurement sweep.

## Context (from discovery — READ THIS BEFORE WRITING CODE)

**Files involved:**
- `scripts/endless_terrain.gd` (4985 lines) — constants banner + registry + roll +
  spawner + 8 builders + one call in `create_chunk`.
- `scripts/landmark_toast.gd` — NEW.
- `scripts/landmark_selfcheck.gd` — NEW.
- `scenes/main.tscn` — **exactly one `[ext_resource]` line + one `[node]` block**.
  Two parallel branches are editing this file this cycle; keep the diff minimal.
- `assets/translations/ui.csv` — append rows only (never reorder existing rows).
- `CLAUDE.md` — a new subsection after the treasure-chest one, plus a Commands entry
  for the new self-check.

**DO NOT TOUCH `scripts/player_controller.gd`** — a parallel developer owns it this
cycle. Nothing in this bead needs it.

**Patterns to copy verbatim (read them first):**
- `_chest_at()` / `spawn_chest_in_chunk()` (`endless_terrain.gd:3639-3826`) — the
  closest template: rarity roll alone in `_x_at`, candidate loop in the spawner.
- `_artifact_at()` / `spawn_artifact_in_chunk()` (`:2869`, `:3107`) — the coin-ring
  reward and the **ordering gotcha** (settle reward coins through `_settle_coin_y`
  BEFORE appending the landmark's own footprint to `obstacles`).
- `_camp_at()` / `spawn_camp_in_chunk()` (`:3237`, `:3473`) — the road-clearance /
  boss-exclusion-by-construction arithmetic.
- `_biome_spot_ok(chunk_center, local_x, local_z, radius, road_clearance, obstacles)`
  (`:3889`) — the single home of the river + road-clearance + overlap rule.
  **Reuse it. Do not write a second copy.**
- `create_box(center, dimensions, yaw, rng, block_batch, block_body, tilt,
  color_override, collide)` (`:2267`) — the batched-geometry entry point. `tilt` and
  `color_override` and `collide` are optional and inert by default.
- `_spawn_artifact_accent(parent_chunk, local_pos, dimensions, yaw, tilt, material)`
  (`:1242`) + `_get_camp_ember_material()` (`:1224`) — the emissive-accent path.
- `scripts/minimap_hud.gd` — the throttled-tick HUD Control built entirely in code,
  found via groups with `has_method` guards.
- `scripts/minimap_selfcheck.gd` / `scripts/progression_selfcheck.gd` — the
  self-check house style (effect measurement + a negative control per check,
  mutation-tested, prints `SELFCHECK OK`, exits 0).

**Hard invariants that this work must not break (all documented in CLAUDE.md):**
- **Zero draws from the shared chunk RNG.** The roll runs on its own hash stream,
  so every block, crocodile and coin the generator produced before landmarks
  existed is still exactly where it was in chunks without a landmark.
- **One MultiMesh, one collision body per chunk.** Every solid box goes through
  `create_box`; the only non-batched nodes a landmark may add are ≤ 4 emissive
  accents and one script-free marker `Node3D`.
- **Nothing straddles a chunk seam:** `LANDMARK_EDGE_MARGIN > LANDMARK_RADIUS`.
- **Flat world:** the ground is `y = 0`; landmarks sit on it, they do not raise it.
- **Determinism within a run** is unconditional: everything is a pure function of
  chunk coords + `run_seed`.

**Multiplayer: ZERO work, and say so in the PR.** World generation is a pure
function of `run_seed`, which every peer in a room already shares, so every peer
sees the same landmarks in the same places by construction. The toast is a local
HUD read-out with no state anyone else needs. No packet, no claim, no sync.

## Development Approach
- **Testing approach**: no unit-test framework exists in this project. Verification
  is `godot --headless --path . --import`, a short headless boot, the existing
  self-checks, `bash scripts/mp_e2e.sh`, the NEW `landmark_selfcheck.gd`, and a
  throwaway headless generator sweep for the measured numbers.
- Complete each task fully before moving to the next.
- **Keep the teaching-density comments and explicit type hints** — this codebase is
  written to be read (CLAUDE.md "Conventions"). Match the density of the chest and
  camp code you are copying, including the *why*, the measured numbers and the
  `ponytail:` deferral notes.
- **CRITICAL: update this plan file when scope changes during implementation.**

## Testing Strategy
- **Unit tests**: none (no framework).
- **Self-check**: `scripts/landmark_selfcheck.gd`, new, permanent, mutation-tested.
- **Sweep**: throwaway, deleted before the PR; its numbers go into the PR body and
  into CLAUDE.md.

## Progress Tracking
- Mark completed items with `[x]` immediately when done
- Add newly discovered tasks with ➕ prefix
- Document issues/blockers with ⚠️ prefix
- Keep plan in sync with actual work done

---

## Implementation Steps

### Task 1: Constants banner + the registry + `_landmark_at`

- [x] Add a `GEO LANDMARKS (rare recognizable famous places)` constant banner in
      `scripts/endless_terrain.gd`, placed after the `TREASURE CHESTS` banner and
      written in the same heavily-commented style. Constants:
      - `@export var spawn_landmarks: bool = true` (the on/off switch the sweep needs)
      - `LANDMARK_CHANCE: float = 0.15` — **a placeholder to be retuned in Task 7**
        from the measured survival rate. Target: **1 built landmark per 40–60 chunks**
        (deliberately rarer than artifacts' 1-in-23 — these are destinations).
      - `LANDMARK_SALT: int` — a fresh arbitrary constant, distinct from
        `ARTIFACT_SALT` (0xA27_1FA), `CAMP_SALT` (0xCA_1117), `CHEST_SALT` (0xC4_E57),
        `BIOME_SALT` (0xB10_11E), `CROC_ROLL_SALT` (0xC20_C) and `BOSS_SEED` (0xB0_55).
        Suggested: `0x1A_D3A2C` ("LANDMARK"-ish).
      - `LANDMARK_HASH_PRIME_X: int = 32452867` and
        `LANDMARK_HASH_PRIME_Y: int = 49979687` — **fresh primes**, deliberately
        distinct from the object/artifact (73856093 / 19349663), camp
        (40960001 / 26463089), biome (83492791 / 15485863), chest
        (86028121 / 50331653) and croc-roll (179424673 / 32452843) pairs. Write that
        list into the comment, as the chest banner does.
      - `LANDMARK_PLACE_TRIES: int = 4`
      - `LANDMARK_RADIUS: float = 9.5` — the **widest** any registry entry may be;
        it is what the placement test is handed (the house rule: pass the widest the
        thing could be). Task 6's self-check asserts it is a true bound.
      - `LANDMARK_EDGE_MARGIN: float = 12.0` — **must exceed `LANDMARK_RADIUS`** so a
        whole landmark stays inside its own chunk. Write the inequality in the comment.
      - `LANDMARK_ROAD_CLEARANCE: float = 22.0` — write the arithmetic into the
        comment, exactly as the camp banner does: it **must** exceed
        `LANDMARK_RADIUS (9.5) + sqrt(BOSS_FORWARD_OFFSET² + BOSS_LATERAL_MAX²) (8.94)
        = 18.44`, which is what makes "a boss can never stand inside a landmark" true
        **by construction with zero edits to `spawn_bosses_in_chunk`**. It is also
        comfortably above `road_width_max / 2` (10), so the coin swath stays clear and
        a landmark reads as an off-road destination you detour to.
      - `LANDMARK_MAX_ACCENTS: int = 4` — the same budget rule as
        `ARTIFACT_MAX_ACCENTS`; an accent is a real extra draw call.
      - `LANDMARK_COIN_MIN: int = 3`, `LANDMARK_COIN_MAX: int = 5`,
        `LANDMARK_COIN_RING_PAD_MIN/MAX` (1.5 / 4.0) — the reward ring.
      - The palette, deliberately distinct from the warm `RAMP_*` block ramps, the
        artifacts' grey-green and the camps' bone-white:
        `LM_STONE_GREY`, `LM_BASALT`, `LM_SANDSTONE`, `LM_GRANITE`, `LM_ORANGE`
        (International Orange), `LM_COPPER` (oxidised green), `LM_OCHRE`, `LM_ROOF`,
        `LM_IRON`, `LM_MARBLE`.
- [x] **REWARD DECISION, write it into the banner:** a small coin ring
      (`LANDMARK_COIN_MIN..MAX`, 3–5 ordinary coins) and **deliberately NO GEM** — the
      guaranteed gem stays the artifacts' distinction, exactly the rule that kept gems
      out of camps and chests. Rationale to record: a landmark is 22 m off the coin
      road, so a destination with no reward at all is a trap; a ring without a gem
      pays the detour without flattening the reward hierarchy.
- [x] Add the registry as a `const`:
      ```gdscript
      const LANDMARKS: Array = [
          { "builder": "_landmark_stonehenge",   "name": "Stonehenge",              "fact": "...", "radius": 7.6 },
          ...
      ]
      ```
      `builder` is a **method-name String** called with `call(entry.builder, ...)`
      (a `const` array cannot hold `Callable`s; a String keeps the registry pure data
      and const-able). `name` / `fact` are the **English source strings**, because in
      this project the translation key IS the English source string (CLAUDE.md
      Localization RULE 1) — so the toast assigns them straight to a `Label.text` and
      gets translation *and* live locale-switching with no `tr()` call. `radius` is
      that shape's own footprint radius and **must be ≤ `LANDMARK_RADIUS`**.
      Eight entries, in this order (the index is the deterministic kind roll):
      Stonehenge, Moai of Easter Island, Pyramids of Giza, Golden Gate Bridge,
      Statue of Liberty, Plaza Mayor, Eiffel Tower, Taj Mahal.
- [x] Add `_landmark_at(chunk_pos: Vector2i) -> Dictionary`, modelled line-for-line on
      `_chest_at`: its own `RandomNumberGenerator` seeded
      `hash(Vector3i(chunk_pos.x * LANDMARK_HASH_PRIME_X, chunk_pos.y * LANDMARK_HASH_PRIME_Y, run_seed ^ LANDMARK_SALT))`;
      one `rng.randf()` rarity roll; returns `{}` or `{ "seed": int, "kind": int }`
      where `kind` is `rng.randi_range(0, LANDMARKS.size() - 1)`.
      **It holds NO candidate loop** — docstring *why*, restating (not
      cross-referencing) the landmine artifacts and camps were both dug out of: when
      this runs the chunk has no geometry, so the only available tests reject almost
      nothing and the real test (overlap) is unavailable, which lands the feature
      ~10× rarer than the constant says.
      Docstring the determinism contract exactly as `_chest_at` does: zero draws from
      the shared chunk RNG, identical within a run, different across runs.

### Task 2: The eight builders

Every builder has the signature
`_landmark_<name>(center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary`
and returns `{ "radius": float, "top": float }` (no `gem_offset` — there is no gem).
All of them:
- draw from the landmark's **private** RNG (seeded from `_landmark_at`'s `seed`), so
  they may draw as freely as they like;
- route **every solid box through `create_box`** with a `color_override`, so it lands
  in the chunk's one MultiMesh and one `BlockCollision` body;
- pass `collide = false` for pure trim that sits inside another box's collision volume
  (dark window/arch recesses, thin decorative bands) — the chest's brass band and the
  camp's fire stones are the precedent;
- keep the returned `radius` **≤ `LANDMARK_RADIUS` (9.5)** and honest: it must bound
  every box the builder actually emitted, measured as horizontal centre offset plus
  the box's rotated half-diagonal. Task 6's self-check measures exactly this, so a
  builder that overflows fails the check rather than silently straddling a seam;
- use **at most one** emissive accent, and only where a real light belongs — reuse
  `_spawn_artifact_accent(..., _get_camp_ember_material())` (warm) for flames/beacons.
  **Do not add a third glow material.**

- [x] `_landmark_stonehenge` — outer ring of 5 trilithons on a ~6 m radius: two
      uprights (≈1.0 × 4.2 × 1.0) plus a lintel (≈3.4 × 0.8 × 1.0) laid across their
      tops, each trilithon yawed to face the centre; an inner horseshoe of 4 shorter
      standing stones with a slight `tilt`. `LM_STONE_GREY`, per-stone colour jitter.
      Return radius ≈ 7.6. No accent.
- [x] `_landmark_moai` — a low ahu platform slab (≈11 × 0.7 × 3) with 5 statues
      standing in a row on it, all facing the same way: body (≈1.3 × 3.0 × 0.9),
      head (≈1.15 × 1.5 × 1.0) with the classic heavy brow as a small `collide = false`
      dark box, and a slight per-statue yaw wobble. `LM_BASALT`. Radius ≈ 6.6. No accent.
- [x] `_landmark_giza` — three stepped pyramids of different sizes (about 9, 7 and 5
      tapering layers) on a shallow diagonal, `LM_SANDSTONE`, plus ONE emissive
      capstone accent on the largest. Keep the triangle compact: radius ≈ 9.4.
- [x] `_landmark_golden_gate` — two towers ~11 m apart, each two vertical legs
      (≈0.9 × 11 × 0.9) tied by two horizontal crossbeams; a deck slab (≈17 × 0.6 × 3)
      spanning between them and overhanging both ends; and the main cable approximated
      by a chain of small boxes in a shallow catenary from tower top to tower top,
      dipping to the deck at mid-span. `LM_ORANGE`. Radius ≈ 9.4. No accent.
      Note in a comment that the deck is *solid* and climbable-looking on purpose —
      it registers as ordinary block stone downstream.
- [x] `_landmark_liberty` — a stepped pedestal (3 shrinking slabs), a tapering robe
      (3–4 stacked boxes narrowing upward), a head, a crown of ~7 small spiked boxes
      radiating with `tilt`, and a raised arm (two boxes at an angle) topped by ONE
      emissive torch accent. `LM_COPPER`. Radius ≈ 5.4, top ≈ 13.
- [x] `_landmark_plaza_mayor` — a square arcaded courtyard: four building rows
      (≈12 m outer side, 3 storeys) enclosing an open plaza, with an arched gap in one
      side; a row of small pillars along each inner face as the arcade; `LM_OCHRE`
      walls with an `LM_ROOF` cornice band; a small statue plinth at the centre.
      Radius ≈ 8.6. No accent.
- [x] `_landmark_eiffel` — four tilted legs converging inward, a first platform slab,
      a second smaller platform, a tapering shaft of 3–4 stacked boxes, and an antenna,
      `LM_IRON`; ONE emissive beacon accent at the top. Radius ≈ 6.2, top ≈ 18.
- [x] `_landmark_taj` — a white marble plinth (≈12 m), a main cube, a dome as a stack
      of 3 shrinking boxes plus a finial, four corner minarets (thin tall boxes with a
      small cap), and a dark `collide = false` iwan arch recess on the front face.
      `LM_MARBLE`. Radius ≈ 8.6. No accent.

### Task 3: `spawn_landmark_in_chunk` + wiring into `create_chunk`

- [x] Add
      `spawn_landmark_in_chunk(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void`,
      modelled on `spawn_chest_in_chunk`:
      - early-return on `not spawn_landmarks` / empty `_landmark_at`;
      - seed the private RNG from the roll's `seed`;
      - `half := chunk_size / 2.0 - LANDMARK_EDGE_MARGIN`;
      - up to `LANDMARK_PLACE_TRIES` candidates, accepting the FIRST that clears
        `_biome_spot_ok(chunk_center, local_x, local_z, LANDMARK_RADIUS, LANDMARK_ROAD_CLEARANCE, obstacles)`.
        **Every try failing means NO landmark** — the same call artifacts and camps
        make, and worth a comment: the Eiffel Tower sticking out of a mountain massif
        reads worse than a chunk without one.
      - dispatch the builder: `var footprint: Dictionary = call(LANDMARKS[kind].builder, center, rng, parent_chunk, block_batch, block_body)`.
- [x] **Reward, in this order (the ordering gotcha):** spawn
      `LANDMARK_COIN_MIN..MAX` ordinary coins on a ring at
      `footprint.radius + randf_range(pad_min, pad_max)`, each settled through
      `_settle_coin_y` and skipped when it returns `INF`, parented to `parent_chunk` —
      **all of this BEFORE the footprint is appended to `obstacles`**, or the coins
      perch on the footprint circle's top and float metres above a hollow shape
      (Stonehenge, the Plaza and the Golden Gate are all mostly hollow). **No gem.**
      Guard with `if spawn_coins and coin_scene != null`, like the artifact reward.
- [x] **The marker node** — the landmark's only other non-batched node, and it has no
      mesh, no script and no physics: a bare `Node3D` named `"LandmarkMarker"`, added
      to the group `"landmark"`, parented to `parent_chunk` at the landmark's centre,
      carrying three metas: `set_meta("name_key", entry.name)`,
      `set_meta("fact_key", entry.fact)`, `set_meta("radius", footprint.radius)`.
      Comment why it exists: the toast finds landmarks the way every other system in
      this project finds things — **by group, never by reference** — and per-chunk
      parenting means it is freed automatically when the chunk unloads, so there is no
      registry to keep in step and nothing to leak. A bare `Node3D` costs zero draw
      calls and zero physics.
- [x] Append ONE round footprint:
      `obstacles.append({ "pos": center, "radius": footprint.radius, "top": footprint.top, "climbable": false })`.
      **Non-climbable**, unlike a chest: these are 5–18 m tall, so a road coin perched
      on the "top" of the circle would float unreachably (the tree/canopy rule). This
      single footprint IS the crocodile exclusion — `spawn_crocodiles_in_chunk`
      already rejects candidates within `ob.radius + min_object_clearance`, so **no
      edit to the crocodile spawner**. Comment the known consequence exactly as camps
      do: the croc *count* is unchanged (the retry budget absorbs it) but the croc
      *positions* in a landmark chunk shift, because a rejected candidate skips the
      successful spawn's `rotation.y` draw.
- [x] Call it from `create_chunk` **AFTER `spawn_camp_in_chunk` and BEFORE
      `spawn_chest_in_chunk`**, with the same ordering comment its siblings carry.
      Two reasons to state there: (a) it must run before `_build_block_multimesh` and
      the `block_body` attach, so its stone joins the chunk's one MultiMesh and one
      collision body; (b) it must run before the chest so a chest is never placed
      inside a landmark — the chest keeps its "last of the family" position, and the
      only behavioural consequence is that in a landmark chunk the chest's candidate
      loop now also has to clear the landmark footprint.

### Task 4: The educational toast (`scripts/landmark_toast.gd`, new)

- [x] New `Control` script, built **entirely in code** in `_ready()` (the
      `touch_controls.gd` / `mobile_settings_panel.gd` precedent), so `main.tscn`
      needs only one node. Structure: a translucent rounded `PanelContainer` (or a
      `ColorRect` backing) holding a `VBoxContainer` with two `Label`s —
      **name** (larger font, e.g. 28) and **fact** (smaller, e.g. 18,
      `autowrap_mode = TextServer.AUTOWRAP_WORD_SMART`).
      `mouse_filter = MOUSE_FILTER_IGNORE` on everything.
      Anchored **bottom-centre**, width ≈ 640, sitting well above `CaptureHint`
      (which occupies `offset_top -80 .. -48`) — e.g. `offset_top -230`,
      `offset_bottom -110`. Verify against the existing HUD anchors in `main.tscn`
      that it collides with nothing else.
- [x] **Localization comes for free and must stay free:** assign the registry's
      English source strings **directly** to `Label.text` — no `tr()` call. Every
      `Control` runs its own `text` through the `TranslationServer` at draw time and
      re-runs it on `NOTIFICATION_TRANSLATION_CHANGED`, so the card is translated
      *and* live-switches with the locale with zero code (CLAUDE.md Localization
      RULE 1). Write that into the comment so nobody "fixes" it by adding `tr()` on a
      composed string later.
- [x] **Proximity on a throttled tick, never per frame.** `TICK_INTERVAL = 0.25`
      accumulated in `_process` (the `minimap_hud.gd` shape). Each tick:
      - find the player via `get_tree().get_first_node_in_group("player")`; bail
        (and clear state) when absent, so the script is inert in a scene without one;
      - walk `get_tree().get_nodes_in_group("landmark")` — typically 0–3 nodes, since
        landmarks are ~1 per 50 chunks over 49–121 active chunks — and pick the
        **nearest** whose XZ distance is under `marker.get_meta("radius") + APPROACH_PAD`
        (`APPROACH_PAD = 6.0`, so ~12–15 m depending on the landmark's size; deriving
        it from the marker's own radius is what makes a 9.4 m Giza and a 5.4 m Liberty
        both trigger at a sensible distance).
      - **Once per approach, re-armed on leaving:** hold `_active: Node3D`. Show the
        card when the nearest in-range marker is not `_active`; set `_active` to it.
        Clear `_active` (re-arming it) when it is no longer valid
        (`is_instance_valid`) or the player is beyond
        `radius + LEAVE_PAD` (`LEAVE_PAD = 14.0` — hysteresis, so standing on the
        trigger boundary cannot flicker the card, the same dead-band discipline
        `crocodile_lod_manager.gd` uses).
- [x] Display: `TOAST_DURATION = 6.0` s visible, then fade out over
      `FADE_DURATION = 0.5` s via `modulate.a` in `_process`; fade IN over the same
      time when shown. `visible = false` when fully faded, so a hidden card costs
      nothing. A new approach while a card is up **replaces** it (re-shows with the
      new text, timer reset) rather than queueing.
- [x] No group membership needed (nobody calls into it) and **no hard references** —
      player by group, landmarks by group, exactly the project's discovery convention.
- [x] Add the node to `scenes/main.tscn`: ONE `[ext_resource type="Script"
      path="res://scripts/landmark_toast.gd" id="..."]` line and ONE
      `[node name="LandmarkToast" type="Control" parent="HUD"]` block. Place it in the
      HUD stack **below `GameOver` / `MultiplayerUI` / `StartOverlay`** so those still
      draw on top. Nothing else in `main.tscn` may change.

### Task 5: Localization rows (`assets/translations/ui.csv`)

- [ ] Append the rows (never reorder existing ones). Write **real facts** and
      **native-quality German** — this is the educational payload, so a machine-shaped
      translation is a defect. Use the exact strings from the registry as keys.
- [ ] **CRITICAL RULE (`scripts/locale_selfcheck.gd` enforces it and will FAIL the
      build otherwise): a row whose `de` column is identical to its `en` column is a
      hard error.** A name that is the same word in German must therefore have **NO
      CSV ROW AT ALL** — it falls back to its own English text, which is exactly what
      the "keys are the English source strings" design is for. So:
      - **NO row** for: `Stonehenge`, `Plaza Mayor`, `Taj Mahal`,
        `Golden Gate Bridge`.
      - **Rows** for the four names that differ:
        `Moai of Easter Island` → `Moai der Osterinsel`;
        `Pyramids of Giza` → `Pyramiden von Gizeh`;
        `Statue of Liberty` → `Freiheitsstatue`;
        `Eiffel Tower` → `Eiffelturm`.
      - **Rows for all eight facts.** Suggested text (refine, but keep the facts
        accurate and the German idiomatic — note `v. Chr.`, the German thousands
        comma in `2,7 km`, and real German place names):
        - `A Neolithic stone circle on Salisbury Plain, England, raised around 2500 BC.`
          → `Ein neolithischer Steinkreis in der Ebene von Salisbury, England, errichtet um 2500 v. Chr.`
        - `Nearly 900 stone figures carved by the Rapa Nui on Easter Island, Chile, between 1250 and 1500.`
          → `Fast 900 Steinfiguren, die das Volk der Rapa Nui zwischen 1250 und 1500 auf der Osterinsel (Chile) schuf.`
        - `Three royal tombs near Cairo, Egypt, built around 2560 BC — the last surviving Wonder of the Ancient World.`
          → `Drei Königsgräber bei Kairo, Ägypten, um 2560 v. Chr. erbaut — das einzige erhaltene Weltwunder der Antike.`
        - `A 2.7 km suspension bridge over San Francisco Bay, USA, opened in 1937 and painted International Orange.`
          → `Eine 2,7 km lange Hängebrücke über die Bucht von San Francisco, USA, 1937 eröffnet und in International Orange gestrichen.`
        - `A 93 m copper statue in New York Harbor, USA — a gift from France, dedicated in 1886.`
          → `Eine 93 m hohe Kupferstatue im Hafen von New York, USA — ein Geschenk Frankreichs, eingeweiht 1886.`
        - `The arcaded central square of Madrid, Spain, completed in 1619 and ringed by 237 balconies.`
          → `Der von Arkaden gesäumte Hauptplatz von Madrid, Spanien, 1619 vollendet und von 237 Balkonen umgeben.`
        - `A 330 m iron tower in Paris, France, built for the 1889 World's Fair and meant to stand only 20 years.`
          → `Ein 330 m hoher Eisenturm in Paris, Frankreich, für die Weltausstellung 1889 erbaut und nur für 20 Jahre gedacht.`
        - `A white marble mausoleum in Agra, India, built by Shah Jahan for his wife Mumtaz Mahal in 1653.`
          → `Ein Mausoleum aus weißem Marmor in Agra, Indien, das Schah Jahan 1653 für seine Frau Mumtaz Mahal errichten ließ.`
- [ ] **No `WIDTH_BUDGETS` entry is needed and none may be added**: the card's labels
      autowrap inside a container that grows, which is the same structural exemption
      the start-overlay and game-over labels already have. Say so in a comment.
- [ ] Re-run `godot --headless --path . --import` **before** running
      `locale_selfcheck.gd` — the check reads the *imported* table and will otherwise
      report the stale one.

### Task 6: `scripts/landmark_selfcheck.gd` (new, permanent)

An `extends SceneTree` script, run with
`godot --headless --path . --script res://scripts/landmark_selfcheck.gd`, printing
`SELFCHECK OK` and exiting 0. House style: **every check is an effect measurement
with a negative control**, never a getter read-back, and the whole thing is
mutation-tested before it is called done.

- [ ] **Check 1 — the declared radius is a TRUE BOUND on the stone each builder
      emits.** For every registry entry: make a detached node with the terrain script,
      a throwaway `block_batch: Array`, a throwaway `StaticBody3D` and a detached
      `MeshInstance3D` as the accent parent; call the builder with a seeded RNG;
      then measure, over every batch entry, `origin.xz.length() + <the rotated box's
      half-diagonal>` and require it `<= entry.radius`. Repeat over several seeds per
      builder (e.g. 25) so a random-driven shape cannot pass by luck.
      **This is the check that keeps landmarks off chunk seams** — an overflowing
      builder is otherwise silent until a player finds half a bridge cut by a seam.
- [ ] **Check 2 — the constant chain holds:** every `entry.radius <= LANDMARK_RADIUS`,
      `LANDMARK_EDGE_MARGIN > LANDMARK_RADIUS`, and
      `LANDMARK_ROAD_CLEARANCE > LANDMARK_RADIUS + sqrt(BOSS_FORWARD_OFFSET^2 + BOSS_LATERAL_MAX^2)`
      (the boss-exclusion-by-construction inequality). Three lines, and they are the
      ones a future retune silently breaks.
- [ ] **Check 3 — every registry fact is actually translated.** Set the locale to
      `de` and require `tr(entry.fact) != entry.fact` for all eight. This is the drift
      that a new landmark introduces most easily (a builder added, the CSV rows
      forgotten) and it is invisible to `locale_selfcheck.gd`, which only validates
      rows that exist. Do **not** assert the same for `name` — four of the eight names
      are legitimately identical in German and therefore deliberately have no row.
      Restore the locale afterwards.
- [ ] **Check 4 — the toast fires once per approach and re-arms on leaving.** Drive
      the real `landmark_toast.gd` against a stub player node in the `"player"` group
      and a stub marker `Node3D` in the `"landmark"` group with the same three metas
      the spawner sets. Sequence, forcing the tick each step:
      1. player far away → card hidden (**negative control**);
      2. player inside the approach radius → card shown, and its two labels carry the
         marker's name and fact (assert the *text*, not just visibility — a card that
         shows the wrong landmark's fact is the failure that matters);
      3. tick again, still inside → **must NOT re-show** (the "once per approach" half;
         assert the internal state did not re-trigger, e.g. by clearing the labels and
         requiring them still clear, or by asserting the display timer keeps counting
         down rather than resetting);
      4. player moved beyond the leave radius, then back inside → card shown again
         (the re-arm half).
- [ ] **Mutation-test it and record the results in the script's header comment**, the
      house rule. At minimum: (a) inflate one registry radius → Check 1 fails;
      (b) drop the hysteresis so leave == approach → Check 4 step 3 or 4 fails;
      (c) delete one fact's CSV row → Check 3 fails; (d) break the boss inequality →
      Check 2 fails.
- [ ] Add the invocation to the `## Commands` block in `CLAUDE.md`, in the same
      commented shape as the other self-checks.

### Task 7: The measured sweep — rarity tuning + determinism (THROWAWAY)

Write a throwaway headless generator sweep (e.g. `scripts/_landmark_sweep.gd`), run
it, record the numbers, then **delete the file before committing** — this is the same
throwaway-sweep precedent the camp and chest work used. The numbers go into the PR
body and into CLAUDE.md.

- [ ] **Measurement A — rarity and survival.** Over a 41×41 = 1681 chunk field with
      every spawner on: how many chunks **rolled** a landmark, how many actually
      **built** one, the survival rate, and the resulting **chunks per built
      landmark**. Also report the per-kind distribution (all eight should appear).
- [ ] **Retune `LANDMARK_CHANCE`** from that survival rate so the built rate lands in
      **1 per 40–60 chunks**, re-run the sweep to confirm, and write both the measured
      survival and the final built rate into the constant's comment — the camp/chest
      precedent (`CAMP_CHANCE` 0.18 → 14% survival → 1 per 31;
      `CHEST_CHANCE` 0.08 → 98.5% → 1 per 12.5).
- [ ] **Measurement B — byte-identity on landmark-free chunks.** Generate the field
      twice, once with `spawn_landmarks = true` and once with `false`, and compare per
      chunk: the block MultiMesh instance transforms + colours, every crocodile
      position, every coin position. **Every chunk that did not build a landmark must
      be byte-identical on all three.** Report the counts (e.g. "N/N landmark-free
      chunks identical"). If any landmark-free chunk differs, that is a bug in the
      independent-stream claim — find it, do not paper over it.
- [ ] **Measurement C — within-run determinism.** Generate the same field twice with
      the same `run_seed` and require byte-identical blocks, crocodiles, coins and
      landmark spots/kinds. Report the counts.
- [ ] **Measurement D — the honest caveat, measured.** In chunks that DID build a
      landmark, report how many crocodiles moved (expected: some — the 9.5 m
      non-climbable footprint shifts the croc stream exactly as a camp's does) and how
      many coins changed. State the number rather than claiming "nothing moved".
- [ ] Delete the sweep script. Confirm `git status` shows no stray file.

### Task 8: Documentation

- [ ] Add a **`Geo-educational landmarks`** subsection to `CLAUDE.md`, immediately
      after the treasure-chest one, in the same density and voice as its three
      siblings. It must carry:
      - the family recipe restated for this member (own salt + fresh primes, roll-only
        `_landmark_at`, candidate loop in the spawner where `obstacles` exists,
        one MultiMesh + one collision body, footprint, edge margin);
      - **the measured numbers from Task 7** (survival %, chunks per built landmark,
        the byte-identity counts, the croc-shift caveat) — measured, never guessed;
      - the constant inequalities and *why* each one is load-bearing
        (`EDGE_MARGIN > RADIUS`; the boss-exclusion arithmetic);
      - the registry as the extension point: "a later wave is one builder function,
        one registry entry and two CSV rows";
      - the reward decision (small ring, **no gem**) and the reason;
      - the toast: group-discovered markers, throttled tick, once-per-approach with a
        hysteresis re-arm, and the **RULE 1 localization trick** (the English source
        string assigned straight to `Label.text`, so translation and live locale
        switching are free — do not "fix" it with `tr()`);
      - the CSV rule that four of the eight names deliberately have **no row**;
      - **multiplayer: zero work by construction** (pure `run_seed` world-gen, local
        HUD read-out);
      - any `ponytail:` deferrals, honestly (see Task 9).
- [ ] Add the `landmark_selfcheck.gd` line to the `## Commands` block.

### Task 9: Verify acceptance criteria

- [ ] `godot --headless --path . --import` runs clean.
- [ ] `godot --headless --path . scenes/main.tscn --quit-after 120` boots with no
      errors or warnings from the edited/added scripts.
- [ ] `godot --headless --path . --script res://scripts/landmark_selfcheck.gd` prints
      `SELFCHECK OK`, exit 0.
- [ ] All existing self-checks still pass:
      `fauna_selfcheck.gd`, `mp_selfcheck.gd`, `locale_selfcheck.gd`,
      `view_selfcheck.gd`, `progression_selfcheck.gd`, `minimap_selfcheck.gd`.
- [ ] `bash scripts/mp_e2e.sh` passes.
- [ ] `git status` is clean of throwaway files; `scripts/player_controller.gd` is
      **untouched**; `scenes/main.tscn` shows exactly one added `ext_resource` line
      and one added node block.
- [ ] Record every deliberate simplification as a `ponytail:` comment with its ceiling
      and upgrade path. Known ones to write down:
      - no per-landmark ambient audio (the sound manager's loop players are
        non-positional; a landmark hum needs a positional audio path — the same
        deferral the artifacts recorded);
      - the toast has no on-screen "you have already seen this one" memory across a
        run: re-approaching after leaving shows the card again, deliberately, because
        the card is the reward for the detour;
      - a mid-card locale switch re-renders the labels live (RULE 1) but the card's
        remaining display time is not extended — cosmetic;
      - the footprint is one circle, so a hollow landmark (Stonehenge, the Plaza, the
        Golden Gate) reserves ground its stone does not actually occupy — the same
        vocabulary limit the artifact footprint records.
