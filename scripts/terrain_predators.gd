class_name TerrainPredators
extends RefCounted
## EVERY PREDATOR THE WORLD SPAWNS — the crocodiles a chunk carries, the Danube's
## own, the GD-SURVEY hunters, the guards a platform is built with and the boss
## that stands on a road station — lifted whole out of endless_terrain.gd by bead
## godot-test1-ftn.6.
##
## MECHANICAL EXTRACTION. Not one number, draw, order or comment changed: the
## bodies below are byte-identical to the ones that were in the world engine bar
## the `terrain.` the reference costs, and the 625-chunk A/B in the PR is what
## says so. A bug found on the way out was a separate bead, not a fix here.
##
## THE SHAPE IS `landmark_builders.gd`'s (the ftn epic's FRAMEWORK): a static
## library that RECEIVES the terrain and calls `terrain.biome_at` /
## `terrain.is_river_at` / `terrain.chunk_to_world` back through it. The terrain
## keeps the POLICY it always kept — `create_chunk`'s one call-order list is
## still the only place that says when a predator is spawned relative to the
## props, the coins and the city — and this file keeps the POPULATION: how many,
## where, of what species, and off which hash stream.
##
## ITS OWN SALTS AND ITS OWN COORDINATE PRIMES LIVE HERE, which is the half of
## the seam that matters. `HUNTER_SALT`, `DANUBE_SALT` and `CROC_ROLL_SALT` are
## part of the WORLD — change one and every hunter, Danube crocodile and boss in
## every run moves — so they belong beside the loop that spends them rather than
## in a constant block a hundred screens from it. `endless_terrain.gd` aliases
## each one back (`const HUNTER_SALT := TerrainPredators.HUNTER_SALT`), so every
## reader that asks the terrain's `get_script_constant_map()` — which is most of
## `enemy_spawn_selfcheck` — is untouched.
##
## TWO THINGS DELIBERATELY STAYED BEHIND, and both for the same reason:
##
##   * `BIOME_SPECIES` and `BIOME_BOSS` are const Dictionaries KEYED BY the
##     terrain's own `Biome` enum, and a `const` in this file cannot reach an
##     enum in another script — moving them would mean moving the enum, which is
##     `biome_at`'s return type, the ground shader's parity partner and no part
##     of this bead. They are read here as `terrain.BIOME_SPECIES`, which changes
##     nothing about the dispatch: it is still a table lookup on a pure function
##     with zero RNG draws behind it.
##   * `SPAWN_SAFE_RADIUS` is the spawn bubble every spawner in the world honours
##     and `player_controller` mirrors, not a predator number.
##
## THE PUBLIC ENTRY POINTS ARE STILL CALLABLE ON THE TERRAIN. `endless_terrain.gd`
## keeps a one-line forwarder for each (`create_box`'s precedent, bead
## godot-test1-ftn.1): ninety-odd call sites across the shipped AI, the tower
## guards, `budapest_plan` and a dozen self-checks are written against
## `terrain.spawn_crocodiles_in_chunk(...)`, and rewriting them all is the
## opposite of a mechanical move. `create_chunk` calls this class directly.


## The SPECIES row these bodies resolve to, and the scene they wear. Named consts
## rather than literals at the spawn site because enemy_spawn_selfcheck reads them:
## the reachability gate in check 4 unions BIOME_SPECIES and BIOME_BOSS, and this
## is the third door into the world — a row reachable only from here would
## otherwise be reported as one nothing can spawn.
const HUNTER_SPECIES: String = "hunter_robot"
const HUNTER_SCENE := preload("res://scenes/characters/hunter_robot.tscn")

## Chance that a chunk gets a hunter at all — ~1 in 12.5 chunks, dropping to ~1 in
## 13 once the placement loop's rejections are counted.
##
## 0.30 -> 0.15: the predator-density call this const was left provisional for
## (owner pacing ruling, 2026-08-29), made across the species at once. The hunter
## carries the widest detection radius in the table (25 m), so at 1-in-3 its discs
## did more to erase standable ground than its body count suggested. Halved with
## the ground density, it stays an order of magnitude commoner than the reward
## family two sections down (chest ~1 in 13, artifact ~1 in 23, landmark ~1 in 40)
## — it is a THREAT, and a threat you meet once an hour teaches nothing — while
## leaving whole stretches of walking with no encounter in them.
##
## 0.15 -> 0.08 IS THE OWNER'S FIELD CAP, AND IT IS THE HALF THAT DOES THE WORK
## (bead godot-test1-fhu, owner 2026-09-02: "limit hunters on field with total
## number 10 (inside HQ doesn't count)"). THE ARITHMETIC, stated here because a
## number tuned against a residency is meaningless without the residency:
##
##   desktop residency = (2 * render_distance + 1)^2 = (2*5 + 1)^2 = 121 chunks
##   expected hunters  = 121 * 0.08                  = 9.68 bodies
##   ...minus the placement loop's rejections (river / bubble / stone / tower),
##      which only ever REMOVE a hunter                <= 9.68 < HUNTER_FIELD_CAP
##
## Web (render_distance 3) is 49 chunks, so ~3.9. So the EXPECTED field is under
## the cap on both platforms without the cap ever having to fire — which is the
## point: the chance is a pure function of (chunk, run_seed) and the hard cap
## below is not. `enemy_spawn_selfcheck` check 13a asserts that inequality off
## these two consts, so a retune that breaks it fails the build.
const HUNTER_CHANCE: float = 0.08

## The HARD ceiling on hunters standing in the FIELD at once — the owner's ten.
##
## WHY THIS IS THE SECOND HALF AND NOT THE ONLY HALF. A live "count the bodies,
## skip the spawn" cap is NOT a pure function of (chunk, run_seed): it depends on
## the order chunks happened to load, which is where the player walked. And
## crocodiles are master-simulated but never network-spawned (CLAUDE.md), so a
## hunter one peer spawned and the master did not is a local ghost that can still
## bite you. So the retuned chance above is what actually holds the number down,
## everywhere and for everybody; this is the backstop for the tail — the walk that
## happens to cross a dozen lucky chunks.
##
## THREE RULES, all of them load-bearing:
##
##   * IT IS A POST-DRAW SKIP (CLAUDE.md's rule), placed below every draw in
##     spawn_hunters_in_chunk, so a capped chunk consumes exactly the stream a
##     spawning one does and nothing else in the world slides.
##   * IT COUNTS BY PARENT, NOT BY GROUP. The HQ's guards are in group
##     "crocodile" like everything else and are parented to the BUILDING, so they
##     are excluded by asking `tower_shell()` whether it is their ancestor —
##     "inside HQ doesn't count" is the owner's own clause.
##   * IT IS OFF IN A ROOM. In a room the retuned chance is the WHOLE cap, and
##     that ceiling is deliberate: two peers who have walked different routes hold
##     different body counts, so a live cap would have them disagree about which
##     hunters exist — the ghost above. Documented, not fixed.
const HUNTER_FIELD_CAP: int = 10

## Salt for the hunter's independent hash stream, in the ARTIFACT_SALT /
## CAMP_SALT / CHEST_SALT / LANDMARK_SALT / BIOME_SALT / BOSS_SEED family: an
## arbitrary fixed constant XORed into run_seed so this stream can never collide
## with (or perturb) any other deterministic site.
const HUNTER_SALT: int = 0x40_7E5  # "HUNTER"-ish; arbitrary fixed constant

## Coordinate multiplier primes for the hunter stream, deliberately DIFFERENT from
## every other stream in this file — object/artifact (73856093 / 19349663), camp
## (40960001 / 26463089), biome (83492791 / 15485863), croc-roll (179424673 /
## 32452843), chest (86028121 / 50331653) — so no two streams can correlate on a
## shared lattice. (These two are the 7,000,000th and 6,000,000th primes.)
const HUNTER_HASH_PRIME_X: int = 122949829
const HUNTER_HASH_PRIME_Y: int = 104395301

## Candidate spots tried before giving up on this chunk's hunter. Every try
## failing means NO hunter — a unit fused into a mountain massif is worse than an
## empty chunk, and the chance above already absorbs the loss.
const HUNTER_PLACE_TRIES: int = 6

## Keep candidate spots this far inside the chunk, so a 1.35 m chassis never
## straddles a seam. A metre more than the crocodile spawner's 3.0, and the reason
## is the retry budget rather than the body: a crocodile chunk makes up to five
## attempts PER crocodile and simply finds another spot, while a hunter gets
## HUNTER_PLACE_TRIES for its single unit and a rejection near a seam costs it one
## of six. Buying the margin up front is cheaper than spending tries on it.
const HUNTER_EDGE_MARGIN: float = 4.0

## Spawn height above the flat y = 0 ground, like the crocodile's. The capsule's
## bottom sits on the body origin (radius == centre y in hunter_robot.tscn), so
## gravity settles the chassis onto the plane from here.
const HUNTER_SPAWN_HEIGHT: float = 0.5

## Which slice of _croc_roll_seed's index space a hunter takes. Ground crocodiles
## use 0, 1, 2, …; platform guards use -1, -2, …; a hunter is the only one of its
## kind in a chunk and takes this single far-away index, so no two bodies in the
## same chunk can ever be handed the same size/speed roll seed. (The seed mixes
## `chunk_pos.x * 179424673 + index`, and 179424673 dwarfs this, so it cannot
## alias into a neighbouring chunk's slice either.)
const HUNTER_ROLL_INDEX: int = 100000

## How far ABOVE a platform's `top` (its tallest stone, NOT the surface it paces)
## a patrol guard is dropped in, so gravity settles it onto the structure.
##
## THIS IS THE PENETRATION DEPTH WHEN THE DROP-IN HEIGHT IS WRONG, which is why
## it is a named constant rather than a literal at the one call site: a guard
## dropped from a height that some stone in its own footprint reaches ends up
## this far INSIDE that stone. See the platform "top" note in spawn_wall.
const PLATFORM_SPAWN_HEIGHT: float = 0.6

## How far in from a platform's edge the guard's spawn point is drawn, so it
## lands cleanly on the surface rather than half off it. Read by
## enemy_spawn_selfcheck.gd, which walks the same inset ellipse at every angle.
const PLATFORM_SPAWN_EDGE_INSET: float = 1.0

# ----------------------------------------------------------------------------
# BOSS CROCODILES (deterministic, station-indexed placement along the coin road)
# ----------------------------------------------------------------------------
## A boss crocodile stands on the road every BOSS_INTERVAL_STATIONS stations —
## at 6 m/station that's one boss roughly every 300 m of road. Boss index `i`
## (1, 2, 3, ...) owns station k = i * BOSS_INTERVAL_STATIONS; station 0 is the
## player spawn and the road trends +X, so only forward stations get bosses.
const BOSS_INTERVAL_STATIONS: int = 50

## Size schedule: boss `i` scales the whole croc body by
## min(BOSS_BASE_SCALE * (1 + (i-1) * BOSS_GROWTH), BOSS_MAX_SCALE)
## → 3.75, 5.0625, 6.375, 7.6875, 9.0, 9.0, ... Each boss is visibly bigger than the
## last until the cap. BOSS_BASE_SCALE (3.75x) is clearly bigger than the biggest
## regular croc's random +25% size roll, so a boss always reads as "not a normal one".
const BOSS_BASE_SCALE: float = 3.75
const BOSS_GROWTH: float = 0.35
const BOSS_MAX_SCALE: float = 9.0

## A small deterministic lateral offset off the centerline (±this, in meters), so
## bosses don't all stand dead-center on the road like a row of toll booths.
##
## WIDENED 4.0 -> 9.0 WITH THE 1.5x SIZE BUMP (bead godot-test1-9k7), and it is
## the half of that bump that actually cost something. The candidate walk in
## spawn_bosses_in_chunk rejects any spot within BOSS_FOOTPRINT_RADIUS_PER_SCALE
## * scale of an obstacle — 6.3 m at the new 9x cap where it was 4.2 m at 6x — so
## at the old ±4 m every candidate a boss had lay inside one 8 m-wide window and
## a single mound near the station killed all of them. MEASURED over 25 seeds /
## 126 road stations: 105 bosses reached the world at the old scales, 91 at the
## new ones with this still at 4.0, and 106 with 9.0 + BOSS_PLACE_TRIES 8. More
## tries alone bought 1 (92) — the band, not the draw count, was the bound.
##
## THE CEILING ON THIS NUMBER IS THE CAMP/LANDMARK EXCLUSION, which is one
## inequality per feature and is stated at CAMP_ROAD_CLEARANCE and
## LANDMARK_ROAD_CLEARANCE (landmark_selfcheck re-checks its half from the live
## constants). With BOSS_FORWARD_OFFSET 8.0 the boss's reach off a station centre
## is hypot(8, 9) = 12.04 m, and the tightest of the two bounds allows
## 22.0 - 9.5 = 12.5 — i.e. 0.46 m of slack. Raising this further means raising
## those clearances first.
const BOSS_LATERAL_MAX: float = 9.0

## Spawn a bit AHEAD of the owning station along the road tangent, so the player
## sees the boss looming up the road rather than materializing beside them.
const BOSS_FORWARD_OFFSET: float = 8.0

## How much ground a boss actually occupies, per unit of body scale. The
## crocodile's collision capsule LIES DOWN (piglet_crocodile.tscn rotates the
## 1.4 m capsule onto its side), so its widest horizontal reach is half that
## length — 0.7 m at body scale 1. Multiplying by the boss's scale is the whole
## point: a 9x boss (BOSS_MAX_SCALE) needs ~6.3 m of clearance from a block where
## a normal crocodile needs ~0.7, so the fixed min_object_clearance that the
## ordinary crocodile spawner uses would be far too small here.
const BOSS_FOOTPRINT_RADIUS_PER_SCALE: float = 0.7

## How many deterministic lateral candidates a boss tries before it is skipped
## entirely (the same "try a few spots, else give up" shape as artifacts). Every
## candidate comes from the SAME BOSS_SEED stream and the FIRST one is exactly
## the draw that existed before this list did, so the boss schedule (which
## station, what size) and the placement of every unobstructed boss are
## byte-for-byte what they were.
##
## 4 -> 8 with the 1.5x size bump, and the honest measurement is that this is the
## SMALLER half of that fix: at ±4 m lateral, 8 tries bought one extra boss over
## 126 stations. It is worth having beside the widened BOSS_LATERAL_MAX (which
## bought 8 more) because the two multiply — a wider band with too few draws
## samples it too sparsely — but 12 tries bought only one further boss (107), so
## this is where the curve flattens.
const BOSS_PLACE_TRIES: int = 8

## Fixed seed for the boss placement RNG — its OWN independent hash stream (like
## ROAD_COIN_SEED), mixed with the boss index and run_seed as
## hash(Vector3i(i, BOSS_SEED, run_seed)). It never consumes a draw from any
## existing chunk/coin/croc RNG sequence, so adding bosses regenerates the rest
## of the procedural world byte-for-byte identically.
const BOSS_SEED: int = 0xB0_55  # "BOSS"-ish; arbitrary fixed constant

## Fixed salt for the per-crocodile SIZE/SPEED roll seed — its OWN independent
## hash stream (the BOSS_SEED / ARTIFACT_SALT / CAMP_SALT pattern). See
## _croc_roll_seed() below: it consumes ZERO draws from the crocodile spawner's
## RNG, so every crocodile's POSITION is byte-for-byte what it was before the
## rolls were determinized — only the size/speed a crocodile rolls for itself
## changed, from "randomize() per instance" to "a pure function of chunk coords,
## croc index and run_seed".
const CROC_ROLL_SALT: int = 0xC20_C  # "CROC"-ish; arbitrary fixed constant

## THE DANUBE'S CROCODILES — the one predator the city rect does NOT turn off,
## and the whole reason the spawner policy is per-system instead of one
## tower_excludes() disc (DEC-9). Pest gets no cacti, no camps and no biome
## predators; the river gets crocodiles, because the owner's standing rule is
## "river -> crocodile" (it is what _boss_row_at already answers on a wet
## station) and a 240 m band of empty water reads as scenery rather than as a
## crossing you have to think about.
##
## ITS OWN HASH STREAM, for the reason stated five times in this file already:
## the chunk's crocodile RNG is one shared sequence, and a single extra draw
## taken from it slides every crocodile in the world. Own salt, own coordinate
## primes, the ARTIFACT_SALT / CAMP_SALT / HUNTER_SALT family — and
## budapest_selfcheck's A/B measures it the way enemy_spawn_selfcheck check 12
## measures the hunter's.
const DANUBE_SALT: int = 0xDA_11BE  # "DANUBE"-ish; arbitrary fixed constant

## Coordinate multiplier primes for the Danube stream, DIFFERENT from every other
## stream in this file — object/artifact (73856093 / 19349663), camp (40960001 /
## 26463089), biome (83492791 / 15485863), croc-roll (179424673 / 32452843),
## chest (86028121 / 50331653), hunter (122949829 / 104395301) — so no two
## streams can correlate on a shared lattice.
const DANUBE_HASH_PRIME_X: int = 141650939
const DANUBE_HASH_PRIME_Y: int = 175961107

## Chance a wet chunk gets crocodiles at all, and how many it may hold. Higher
## than any land rarity roll on purpose: the river is a THREAT LINE across the
## middle of the city, and one you can wade through unopposed half the time is
## not one.
const DANUBE_CROC_CHANCE: float = 0.55
const DANUBE_CROC_MAX: int = 2

## How far off a DRY RECT a Danube crocodile has to stand, and it is the ONE
## obstacle test this spawner has.
##
## A bridge's STONE OVERHANGS ITS DECK. The Margaret Bridge's cutwaters are 10 m
## boxes turned 45 degrees at z = +/-13 off a deck rect only 32 m deep, so their
## corners reach 20.07 m out on Z against the rect's 16 — 4.07 m of solid, colliding
## stone standing in open water. The Chain Bridge's tower piers overhang by 0.5 m
## the same way. `danube_wet()` answers true there (it is off the rect), so the
## per-body re-test that keeps a crocodile off the DECK does not keep it out of the
## PIER, and it is reachable: chunk (2425, -675) is wet and its candidate square
## covers the western cutwater's overhang.
##
## Every sibling spawner rejects a candidate standing in stone against `obstacles`;
## this one cannot, because a city landmark's footprint is ONE disc up to 156 m
## across and passing the list would empty the whole reach of the river. So the
## test is the deck rect grown by the widest measured overhang plus a body's width
## instead — bounded, allocation-free, and in WORLD space, which matters because
## the box in the way may be owned by the neighbouring chunk (the centre rule homes
## a landmark box by its own centre, not by where it reaches).
const DANUBE_CROC_DECK_MARGIN: float = 8.0

## Which slice of the spawn-slot index space the Danube takes — for BOTH the
## node name and _croc_roll_seed, one number because they are one identity.
##
## The name keeps the "Crocodile_" prefix (croc_id_for hashes it; the four
## prefixes are the whole naming scheme enemy_spawn_selfcheck classifies by), and
## the two spawners are mutually exclusive by construction anyway —
## spawn_crocodiles_in_chunk returns before drawing anything inside the rect. The
## index base is belt-and-braces on top of that exclusion, so re-enabling ground
## crocodiles here could never claim a name twice.
const DANUBE_SLOT_BASE: int = 500

## CITY — the crocodile TARGET is divided by this in the city band. Owner call
## (2026-08-26): a city is not croc-free, it is quieter. This is a DESIGN number
## exactly like DESERT_BLOCK_KEEP_EVERY and the distance gradient, not a perf
## trim, so the "entity counts are never reduced as an optimization" convention is
## intact. Like the desert's, it lowers a TARGET and inserts NO RNG DRAW anywhere:
## the surviving crocodiles are byte-for-byte the FIRST target/N of the undivided
## stream, in the same positions, with the tail simply not spawned.
const CITY_CROC_DIVISOR: float = 2.5


static func spawn_crocodiles_in_chunk(terrain: Node3D, chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array = []) -> void:
	"""
	Spawns crocodile NPCs within a terrain chunk.

	@param chunk_pos: Chunk coordinates for seeded random generation
	@param parent_chunk: The chunk mesh to attach crocodiles to
	@param obstacles: Block footprints to keep crocodiles out of, so they don't
	                  spawn partially buried inside a block (see spawn_objects_in_chunk)

	EDUCATIONAL NOTE:
	- Crocodiles are spawned dynamically with the terrain
	- They are parented to the chunk so they're removed when chunk is removed
	- This creates an endless stream of enemies as you explore
	"""

	if not terrain.crocodile_scene:
		return

	# BUDAPEST — biome predators are OFF inside the city rect (bead
	# godot-test1-8gw.3, DEC-9), and this is the early return the whole per-system
	# policy exists for: the rect forces the CITY band, so without it Pest would
	# get alley hounds wandering the Parliament's steps while the RIVER — the one
	# place the city DOES want predators — got the same treatment as the streets.
	# The Danube's own spawner below is the yes half of that split, on its own
	# stream. NOT tower_excludes(), which has exactly one answer for everybody.
	#
	# BEFORE the seed is even mixed, because there is no stream to advance: a city
	# chunk never consults this sequence at all, so nothing outside the rect can
	# shift by one draw.
	var croc_center := terrain.chunk_to_world(chunk_pos)
	if terrain.in_budapest(croc_center.x, croc_center.z):
		return

	# Use chunk coordinates (+ this run's seed) to create a unique but consistent seed.
	# Different multipliers than the object seed give different positions than objects;
	# run_seed makes crocodile placement differ run-to-run (constant within a run).
	var seed_value := hash(Vector3i(chunk_pos.x * 83492791, chunk_pos.y * 28411639, terrain.run_seed))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	# Calculate the world position of this chunk's corner
	var chunk_world_pos := terrain.chunk_to_world(chunk_pos)
	var half_chunk := terrain.chunk_size / 2.0

	# Store positions of spawned crocodiles to check spacing
	var spawned_positions: Array[Vector3] = []

	# Difficulty gradient: chunks farther from origin (along the road's +X axis) hold
	# MORE crocodiles — +1 per 10 chunks of |x| distance, capped at +4 over the base,
	# so the undivided target runs 3..7; after the halving below the field really
	# holds 1..2 near the origin and 3..4 far out. Rescaled with the base
	# count (owner pacing ruling, 2026-08-29): the gradient must stay a slope you
	# feel, not one that restores the wall-to-wall density further out.
	# A pure function of chunk coords, so within-run determinism is untouched (the
	# same chunk always regenerates the same count). The LOD manager keeps the extra
	# distant crocodiles cheap: they are slept (frozen, monitoring off), never removed.
	#
	# HALVED (owner pacing ruling, 2026-09-02, bead godot-test1-7ed: "reduce
	# predator amount in half"). This is a TARGET, not a roll — the same
	# discipline as CITY_CROC_DIVISOR right below and DESERT_BLOCK_KEEP_EVERY:
	# the halving costs the chunk RNG ZERO draws, so the surviving crocodiles are
	# byte-for-byte the FIRST half of the undivided stream, standing exactly where
	# they always stood, with the tail simply never spawned.
	#
	# WHY THE `posmod(chunk_pos.y, 2)`: the undivided targets are 3..7, whose
	# halves are 1.5..3.5. Rounding every one of them the same way gives 57% (up)
	# or 43% (down), not half — and the base band, where the player spends most of
	# the run, would sit at 2/3. Adding the chunk ROW's parity before the integer
	# divide rounds odd targets up on every other row of chunks and down on the
	# rest, so the field averages EXACTLY half at every distance while staying a
	# pure function of chunk coordinates. A target of 3 therefore yields 1 or 2 —
	# "1 stays possible", and a base of 0 still yields 0.
	var chunk_croc_target := (terrain.crocodiles_per_chunk
			+ mini(4, absi(chunk_pos.x) / 10)
			+ posmod(chunk_pos.y, 2)) / 2

	# CITY — the one band whose croc target is divided (owner call, 2026-08-26: a
	# city is not croc-free, it is QUIETER; the roofs are the real safety).
	#
	# A TARGET, NOT A ROLL, exactly like DESERT_BLOCK_KEEP_EVERY: the biome is a
	# pure function of chunk coords, so the branch costs no RNG draw and inserts
	# none. The consequence is worth stating precisely — the surviving crocodiles
	# are byte-for-byte the FIRST target/N of the undivided stream, standing in the
	# same positions, with the tail simply never spawned. Nothing shifts.
	#
	# This is a DESIGN number (the difficulty gradient's sibling), not a perf trim,
	# so the "entity counts are never reduced as an optimization" convention holds.
	var chunk_biome: terrain.Biome = terrain.biome_at(chunk_world_pos.x, chunk_world_pos.z)
	if chunk_biome == terrain.Biome.CITY:
		chunk_croc_target = maxi(1, int(roundf(float(chunk_croc_target) / CITY_CROC_DIVISOR)))

	# WHICH PREDATOR THIS CHUNK GETS — one table lookup on the biome already
	# resolved above, and NOT ONE RNG DRAW (see BIOME_SPECIES for why that is a
	# constraint rather than a preference). The whole chunk gets one species,
	# because the biome field is what varies and it varies at the ~8-chunk scale
	# of BIOME_CELL_SIZE; picking per crocodile would need a draw, and a draw is
	# exactly what is not allowed here.
	#
	# `rng` is untouched by any of this, so a PLAINS chunk generates the identical
	# crocodiles it always did, down to the last float.
	#
	# The crocodile stays the default, and a biome with no BIOME_SPECIES entry
	# never even reaches the load: PLAINS takes the `crocodile_scene` it always
	# took. A species whose scene fails to load also falls back rather than
	# spawning nothing — same degrade-don't-crash rule as the AI's own unknown-
	# species warning, and a visibly wrong animal beats an invisibly empty chunk.
	var chunk_species: String = "crocodile"
	var species_scene: PackedScene = terrain.crocodile_scene
	if terrain.BIOME_SPECIES.has(chunk_biome):
		var row: Dictionary = terrain.BIOME_SPECIES[chunk_biome]
		if not terrain._species_scenes.has(chunk_biome):
			terrain._species_scenes[chunk_biome] = load(row["scene"])
			if not terrain._species_scenes[chunk_biome]:
				push_warning("endless_terrain: failed to load %s, using the crocodile"
						% row["scene"])
		var scene: PackedScene = terrain._species_scenes[chunk_biome]
		if scene:
			chunk_species = row["species"]
			species_scene = scene

	# Try to spawn crocodiles with proper spacing
	var attempts := 0
	var max_attempts := chunk_croc_target * 5  # Allow multiple attempts per crocodile

	while spawned_positions.size() < chunk_croc_target and attempts < max_attempts:
		attempts += 1

		# Generate random position within chunk bounds
		var margin := 3.0  # Keep away from edges
		var random_x := rng.randf_range(-half_chunk + margin, half_chunk - margin)
		var random_z := rng.randf_range(-half_chunk + margin, half_chunk - margin)
		var crocodile_pos := Vector3(random_x, 0.5, random_z)  # Y=0.5 to spawn above ground

		# Check if this position is far enough from existing crocodiles
		var valid_position := true
		for existing_pos in spawned_positions:
			if crocodile_pos.distance_to(existing_pos) < terrain.min_crocodile_spacing:
				valid_position = false
				break

		# Also reject positions that overlap a block, so crocodiles never spawn
		# partially inside one. We compare horizontal distance against the block's
		# footprint radius plus a clearance margin.
		if valid_position:
			for ob in obstacles:
				var horizontal := Vector2(crocodile_pos.x - ob.pos.x, crocodile_pos.z - ob.pos.z).length()
				if horizontal < ob.radius + terrain.min_object_clearance:
					valid_position = false
					break

		# Crocodiles don't stand in rivers — the water is the player's, and a river
		# reads as a small safe(r) crossing. Rejected AFTER the position draws, so
		# the candidate itself costs the stream nothing extra — but a rejection
		# still skips the successful spawn's `rotation.y` draw below, so the rest
		# of this chunk's crocodile positions shift. Deterministic within a run
		# (is_river_at is pure), just not identical to a river-free chunk.
		#
		# chunk_croc_target is deliberately NOT reduced: density is a DESIGN number
		# (the difficulty gradient), never trimmed for a biome. The while loop's
		# generous retry budget (5 tries per crocodile) simply finds dry spots
		# instead, so a chunk merely grazed by a river keeps its full count; only a
		# chunk almost entirely under water ends up with fewer.
		if valid_position and terrain.is_river_at(chunk_world_pos + crocodile_pos):
			valid_position = false

		# Keep the spawn point clear (see SPAWN_SAFE_RADIUS). Same post-draw `continue`
		# discipline as the river skip directly above — the candidate's own draws are
		# already spent, so nothing upstream shifts; only the handful of chunks touching
		# the origin bubble are affected, and identically on every run.
		var croc_world := chunk_world_pos + crocodile_pos
		if valid_position and Vector2(croc_world.x, croc_world.z).length() < terrain.SPAWN_SAFE_RADIUS:
			valid_position = false

		# Keep the tower's site clear too — the same rule as the spawn bubble above
		# (a fixed disc nothing procedural may stand in), enforced with the same
		# post-draw `continue`. min_object_clearance is the margin the block test
		# already uses for "a crocodile is not a point".
		if valid_position and terrain.tower_excludes(croc_world.x, croc_world.z, terrain.min_object_clearance):
			valid_position = false

		if not valid_position:
			continue

		# ...and a FIELD BRIDGE is a floor, not an obstacle: a spot on a deck
		# keeps its XZ and is lifted onto the stone (see field_bridge_stand_y).
		crocodile_pos.y = terrain.field_bridge_stand_y(croc_world.x, croc_world.z,
				crocodile_pos.y)

		# Instantiate this chunk's predator (crocodile everywhere but the desert)
		var crocodile_instance = species_scene.instantiate()
		# NAMED "Crocodile_…" WHATEVER THE SPECIES, deliberately. The name is this
		# spawn SLOT's identity, not a label: piglet_crocodile_ai.croc_id_for()
		# hashes it into the room-wide id multiplayer syncs on, and
		# enemy_spawn_selfcheck classifies ground spawns by the prefix. Species is
		# a pure function of position, so every peer already agrees on it — a
		# per-species prefix would only churn every id for nothing.
		crocodile_instance.name = "Crocodile_%d_%d_%d" % [chunk_pos.x, chunk_pos.y, spawned_positions.size()]

		# Position relative to chunk
		crocodile_instance.position = crocodile_pos

		# Random initial rotation for variety
		crocodile_instance.rotation.y = rng.randf_range(0, TAU)

		# CALL-ORDER CONTRACT (the setup_as_boss shape): hand over the deterministic
		# size/speed roll seed BEFORE add_child, so the croc's _ready() sees it and
		# seeds its own rng from it instead of randomize()ing. Non-negative index =
		# the ground crocodile stream (see _croc_roll_seed).
		crocodile_instance.setup_roll_seed(_croc_roll_seed(terrain, chunk_pos, spawned_positions.size()))
		# SAME CALL-ORDER CONTRACT, and it is the reason `species` is a plain
		# public field: _ready() is where it is resolved into `spec` and where the
		# size/speed rolls that READ that spec happen, so assigning it after
		# add_child() would roll a crocodile's numbers onto a viper's body.
		crocodile_instance.species = chunk_species

		# Add to chunk (so it gets removed when chunk is removed)
		parent_chunk.add_child(crocodile_instance)
		spawned_positions.append(crocodile_pos)

static func spawn_danube_crocodiles_in_chunk(terrain: Node3D, chunk_pos: Vector2i, parent_chunk: MeshInstance3D) -> void:
	"""
	Put crocodiles in the Danube — the city rect's ONE yes in a policy of noes.

	@param chunk_pos: Chunk coordinates — the only spatial input, so placement is a
	                  pure function of (chunk, run_seed)
	@param parent_chunk: The chunk mesh they parent to, so they are freed when the
	                     chunk unloads (the per-chunk parenting rule everything follows)

	WHY THIS FUNCTION EXISTS SEPARATELY, and it is the same answer the hunter's
	spawner gives: its OWN hash stream. DANUBE_SALT plus DANUBE_HASH_PRIME_X/Y
	give a private RNG that touches no other sequence, so every crocodile OUTSIDE
	the city stands byte-for-byte where it stood before the city existed. Folding
	this into spawn_crocodiles_in_chunk as a branch would have been fewer lines and
	would have slid the whole world by one draw.

	WHY CROCODILES and not one of the six biome rows: the owner's standing rule is
	"river -> crocodile", the same one _boss_row_at applies to a station standing
	in water. The city forces the CITY band, so BIOME_SPECIES would have answered
	"alley hound" — a dog treading water.

	EVERY REJECTION IS A POST-DRAW SKIP, the discipline the whole file runs on:
	both position draws and the facing draw are spent before the first test, so a
	candidate costs this stream exactly three draws whether it is taken or thrown
	away, and a bridge deck can never slide a later candidate.
	"""
	if not terrain.crocodile_scene:
		return

	# The rect first, and it is not redundant with danube_wet below: the polyline
	# runs to the rect's north and south edges, so a chunk 40 m outside the city
	# can still sit inside the 120 m band. is_river_at() already asks the two
	# questions in this order; so does this.
	var chunk_world_pos := terrain.chunk_to_world(chunk_pos)
	if not terrain.in_budapest(chunk_world_pos.x, chunk_world_pos.z):
		return
	if not BudapestPlan.danube_wet(chunk_world_pos.x, chunk_world_pos.z):
		return

	# Chunk coords + run_seed ^ DANUBE_SALT, with this stream's own primes.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(
		chunk_pos.x * DANUBE_HASH_PRIME_X,
		chunk_pos.y * DANUBE_HASH_PRIME_Y,
		terrain.run_seed ^ DANUBE_SALT
	))

	# The rarity roll, first draw of the stream and taken before anything else so
	# geometry can never perturb it — the _chest_at / spawn_hunters_in_chunk shape.
	if rng.randf() > DANUBE_CROC_CHANCE:
		return

	var half_span := terrain.chunk_size / 2.0 - 3.0
	var spawned := 0
	for _try in DANUBE_CROC_MAX * 3:
		if spawned >= DANUBE_CROC_MAX:
			break

		# THE THREE DRAWS. All of them, unconditionally, before any test below.
		var local := Vector3(
			rng.randf_range(-half_span, half_span),
			0.5,
			rng.randf_range(-half_span, half_span))
		var facing := rng.randf_range(0.0, TAU)
		var world := chunk_world_pos + local

		# Re-asked AT THE BODY, not just at the chunk centre: a chunk on the bank
		# is half dry land, and the bridge decks and Margaret Island are dry rects
		# INSIDE the band. This is what keeps a crocodile off the Chain Bridge.
		if not BudapestPlan.danube_wet(world.x, world.z):
			continue

		# ...and off the stone that HANGS OFF the deck it stands on, which the test
		# above cannot see. See DANUBE_CROC_DECK_MARGIN.
		if _near_dry_rect(terrain, world.x, world.z, DANUBE_CROC_DECK_MARGIN):
			continue

		var croc := terrain.crocodile_scene.instantiate()
		# "Crocodile_<cx>_<cy>_<i>", the ground spawner's own prefix and namespace
		# — croc_id_for() hashes the name into the room-wide id, and the four
		# prefixes are the whole scheme every peer and every self-check reads. The
		# two spawners cannot both run in a chunk (the one above returns inside the
		# rect), and DANUBE_SLOT_BASE puts the indices out of reach anyway.
		croc.name = "Crocodile_%d_%d_%d" % [chunk_pos.x, chunk_pos.y, DANUBE_SLOT_BASE + spawned]
		croc.position = local
		croc.rotation.y = facing
		# CALL-ORDER CONTRACT (the setup_as_boss / spawn_crocodiles_in_chunk
		# shape): both of these BEFORE add_child, because _ready() is where
		# `species` is resolved into `spec` and where the size/speed rolls that
		# READ that spec happen.
		croc.setup_roll_seed(_croc_roll_seed(terrain, chunk_pos, DANUBE_SLOT_BASE + spawned))
		croc.species = "crocodile"
		parent_chunk.add_child(croc)
		spawned += 1


static func _near_dry_rect(terrain: Node3D, x: float, z: float, margin: float) -> bool:
	"""
	Is this world XZ within `margin` of a Danube DRY RECT (a bridge deck, or the
	island)?

	@param x, z: world XZ
	@param margin: how far outside a rect still counts as "near"
	@return: whether any DRY_RECTS row, grown by `margin` on all four sides,
	         contains the point

	`BudapestPlan.is_dry` asks the same question with margin 0 and cannot be given
	one: it is half of the wading contract and is mirrored in `ground.gdshader`, so
	a margin there would move the shoreline. This is a SPAWNER-side clearance test
	over the same table and touches neither language of that contract.
	"""
	for i in range(BudapestPlan.DRY_RECTS.size()):
		var r: Rect2 = BudapestPlan.DRY_RECTS[i]
		if x >= r.position.x - margin and x <= r.position.x + r.size.x + margin \
				and z >= r.position.y - margin and z <= r.position.y + r.size.y + margin:
			return true
	return false


static func adopt_wanderer(terrain: Node3D, unit: Node3D) -> void:
	"""
	Re-parent a body that has walked off its birth chunk to the chunk under it.

	@param unit: the wandering body — today only a scent-tracking hunter, which is
	             the only thing in this game that moves while the LOD manager has
	             it asleep

	EVERYTHING SPAWNED PER CHUNK IS PARENTED TO THAT CHUNK so unloading frees it,
	and that rule is exactly right for a body that stays where it was put. A
	tracker does not: it follows a trail toward the player, so its birth chunk
	falls out of `render_distance` behind it and takes it with it — deleting the
	unit for doing the one thing the feature exists to make it do. Re-parenting
	restores the rule instead of exempting the unit from it: the body still dies
	when the ground it is ACTUALLY standing on unloads, which is still the correct
	streaming lifetime, just measured against the right chunk.

	THE NAME IS NOT TOUCHED, because the name IS the room-wide crocodile id
	(`croc_id_for` hashes it) and every peer derives it from the birth chunk. What
	the move does create is the possibility of that birth chunk regenerating while
	this body is still alive, which would build a second unit with the same id —
	so the slot is recorded in `_migrated_units` and `spawn_hunters_in_chunk`
	refuses to fill a slot that is already standing somewhere.

	Silently does nothing when the destination chunk is not loaded (leaving the
	unit parented where it is, which is the pre-existing behaviour) or when it is
	already parented correctly — so this is safe to call every scan, which is what
	`advance_tracking` does.
	"""
	if not is_instance_valid(unit) or not unit.is_inside_tree():
		return
	var chunk_pos := terrain.world_to_chunk(unit.global_position)
	if not terrain.active_chunks.has(chunk_pos):
		return
	var host: Node = terrain.active_chunks[chunk_pos]
	if unit.get_parent() == host:
		return
	terrain._migrated_units[unit.name] = unit
	unit.reparent(host, true)


static func spawn_hunters_in_chunk(terrain: Node3D, chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array = []) -> void:
	"""
	Place this chunk's GD-SURVEY hunter robot, if it gets one.

	@param chunk_pos: Chunk coordinates — the only spatial input, so placement is a
	                  pure function of (chunk, run_seed)
	@param parent_chunk: The chunk mesh the unit parents to, so it is freed when the
	                     chunk unloads (the per-chunk parenting rule everything follows)
	@param obstacles: Block footprints already built in this chunk, so a hunter is
	                  never wedged inside one (see spawn_objects_in_chunk)

	ITS OWN HASH STREAM, AND THAT IS THE WHOLE POINT OF THIS FUNCTION EXISTING
	SEPARATELY. HUNTER_SALT plus HUNTER_HASH_PRIME_X/Y give a private RNG that
	touches no other stream, so spawn_crocodiles_in_chunk's sequence — and
	therefore every crocodile POSITION in the world — is byte-for-byte what it was
	before hunters existed. The same discipline as _artifact_at / _camp_at /
	_chest_at / _landmark_at; enemy_spawn_selfcheck check 12 is the A/B that
	measures it.

	IT JOINS GROUP "crocodile", VIA ITS SCENE, AND THAT IS DELIBERATE — it is what
	gets it the LOD manager's sleep, the danger vignette, the multiplayer crocodile
	sync and the inherited `_on_player_collision` -> `player.hit_by_crocodile()` for
	free. The visible consequence: the F3 perf overlay's "active/total crocs"
	counters include hunters. That is correct rather than a mislabel — those
	counters measure the simulation load the LOD manager is managing, and a hunter
	is exactly one more body in it.

	AND EVERY REJECTION IS A POST-DRAW SKIP. Both position draws AND the facing
	draw are spent BEFORE the first test, so a candidate costs this stream exactly
	three draws whether it is accepted or thrown away. That is stricter than the
	crocodile spawner (which draws its rotation only on success, so a rejection
	there shifts the rest of its own chunk) and it is worth the one extra line: it
	makes "hunter 4 of 6 was rejected" cost the same as "hunter 1 of 6 was taken",
	so nothing about a chunk's river, blocks or distance from the origin can slide
	a LATER candidate to a different place than it would otherwise have had.
	"""
	if not terrain.spawn_hunters:
		return

	# Chunk coords + run_seed ^ HUNTER_SALT, with this stream's own primes.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(
		chunk_pos.x * HUNTER_HASH_PRIME_X,
		chunk_pos.y * HUNTER_HASH_PRIME_Y,
		terrain.run_seed ^ HUNTER_SALT
	))

	# The rarity roll, first draw of the stream and taken before anything else so
	# it can never be perturbed by geometry — the _chest_at / _landmark_at shape.
	# NO BIOME LOOKUP: the corporation hunts every band (see HUNTER_SPECIES).
	if rng.randf() > HUNTER_CHANCE:
		return

	var chunk_world_pos := terrain.chunk_to_world(chunk_pos)
	var half_span := terrain.chunk_size / 2.0 - HUNTER_EDGE_MARGIN

	for _try in HUNTER_PLACE_TRIES:
		# THE THREE DRAWS. All of them, unconditionally, before any test below.
		var local := Vector3(
			rng.randf_range(-half_span, half_span),
			HUNTER_SPAWN_HEIGHT,
			rng.randf_range(-half_span, half_span))
		var facing := rng.randf_range(0.0, TAU)
		var world := chunk_world_pos + local

		# Not inside a block. Horizontal distance against the footprint radius plus
		# the same clearance margin the crocodile spawner uses — a hunter is not a
		# point, and min_object_clearance (1.5) is the project's answer to that.
		var blocked := false
		for ob in obstacles:
			if Vector2(local.x - ob.pos.x, local.z - ob.pos.z).length() < ob.radius + terrain.min_object_clearance:
				blocked = true
				break
		if blocked:
			continue

		# Not standing in a river. Same reading as the crocodile's: the water is the
		# player's, and a crossing should read as safer ground.
		if terrain.is_river_at(world):
			continue

		# Not in the spawn bubble (SPAWN_SAFE_RADIUS) — a hunter's detection radius
		# is 25 m, the widest in the table, so one placed at the edge of the bubble
		# would be chasing on frame one of a fresh boot.
		if Vector2(world.x, world.z).length() < terrain.SPAWN_SAFE_RADIUS:
			continue

		# Not on the tower's site — the same fixed disc nothing procedural may stand
		# in that the crocodile spawner already respects.
		if terrain.tower_excludes(world.x, world.z, terrain.min_object_clearance):
			continue

		# ...and a FIELD BRIDGE is a floor: a spot on a deck keeps its XZ and is
		# lifted onto the stone (see field_bridge_stand_y).
		local.y = terrain.field_bridge_stand_y(world.x, world.z, local.y)

		# ONE SLOT, ONE BODY. A hunter that walked off this chunk while tracking is
		# re-parented to the ground under it (`adopt_wanderer`), so this chunk can
		# unload and regenerate while that unit is still alive — and filling the
		# slot again would build a second body carrying the same name, which is the
		# room-wide crocodile id. The registry is reaped here rather than watched:
		# a slot whose body has since been freed is simply forgotten and refilled.
		#
		# BELOW EVERY DRAW, like every other rejection in this function, so the
		# stream is identical whether or not the slot happens to be occupied.
		var slot := "Hunter_%d_%d_0" % [chunk_pos.x, chunk_pos.y]
		if terrain._migrated_units.has(slot):
			if is_instance_valid(terrain._migrated_units[slot]):
				return
			terrain._migrated_units.erase(slot)

		# THE OWNER'S TEN (HUNTER_FIELD_CAP). Last rejection in the function and
		# BELOW EVERY DRAW, like all the others: a capped chunk spends exactly the
		# stream a spawning one does, so turning the cap on slides nothing.
		if _field_hunters_full(terrain, parent_chunk):
			return

		var hunter := HUNTER_SCENE.instantiate()
		# "Hunter_<cx>_<cy>_<i>", its own namespace beside "Crocodile_" /
		# "PatrolCrocodile_" / "BossCrocodile_". The name IS the room-wide id
		# (piglet_crocodile_ai.croc_id_for hashes it), so it has to be derivable by
		# every peer — which it is, being a pure function of the chunk — and it has
		# to be collision-free with the other spawners' names, which is exactly why
		# this one does NOT reuse the "Crocodile_" prefix: the two index sequences
		# are independent, so "Crocodile_3_4_0" would be claimed twice in a chunk
		# that has both.
		# The trailing 0 is this chunk's hunter INDEX, kept in the name even though
		# a chunk gets at most one today: the three-part shape is what makes the
		# name a spawn SLOT rather than a label, the way the crocodile spawner's is.
		hunter.name = slot
		hunter.position = local
		hunter.rotation.y = facing
		# CALL-ORDER CONTRACT (the setup_as_boss / spawn_crocodiles_in_chunk shape):
		# BOTH of these go in BEFORE add_child, because _ready() is where `species`
		# is resolved into `spec` and where the size/speed rolls that READ that spec
		# happen. Assigned after, a hunter would roll a crocodile's numbers onto its
		# body and every per-frame path would read the wrong row.
		hunter.setup_roll_seed(_croc_roll_seed(terrain, chunk_pos, HUNTER_ROLL_INDEX))
		hunter.species = HUNTER_SPECIES
		parent_chunk.add_child(hunter)
		return


static func _field_hunters_full(terrain: Node3D, parent_chunk: Node) -> bool:
	"""
	Are there already HUNTER_FIELD_CAP hunters standing in the FIELD?

	@param parent_chunk: the chunk the caller is filling — it is what supplies the
	                     SceneTree, because this node is driven DETACHED by several
	                     self-checks while the chunk parent they hand it is real
	@return true when spawn_hunters_in_chunk must skip (post-draw) this hunter

	THREE THINGS IT IS CAREFUL ABOUT, and each is a way to get this wrong:

	  * THE HQ DOESN'T COUNT, and the exclusion is BY PARENT — `tower_shell()` is
	    asked whether it is the body's ancestor. Not by group (a guard is in
	    "crocodile" like everything else), and not by position either: a guard
	    chasing you onto the doorstep is still the building's.
	  * OFF IN A ROOM. `is_online()` is "a room exists", the window in which every
	    peer must agree about which bodies the world holds; a live body count
	    differs per peer by where they walked, so in a room HUNTER_CHANCE is the
	    whole cap (see the const).
	  * A DETACHED / TREE-LESS CALLER COUNTS NOTHING, so the cap simply does not
	    fire — the degrade every group lookup in this project takes.

	The species field rather than the "Hunter_" name prefix, because the name is a
	spawn SLOT and the row is what makes a body a retrieval unit; the tower guard
	is a different row and would be excluded by this line too, which is belt to the
	parent test's braces.
	"""
	var tree := parent_chunk.get_tree()
	if tree == null:
		return false
	var mp: Node = tree.get_first_node_in_group("mp")
	if mp != null and mp.has_method("is_online") and bool(mp.is_online()):
		return false
	var shell: Node = terrain.tower_shell()
	var count := 0
	for body: Node in tree.get_nodes_in_group("crocodile"):
		if String(body.get("species")) != HUNTER_SPECIES:
			continue
		if shell != null and shell.is_ancestor_of(body):
			continue
		count += 1
		if count >= HUNTER_FIELD_CAP:
			return true
	return false


static func spawn_platform_crocodiles(terrain: Node3D, chunk_pos: Vector2i, parent_chunk: MeshInstance3D, platforms: Array) -> void:
	"""
	Place rare crocodiles that patrol an elevated structure top (a terraced mound's
	summit, a wall ridge or a forest log bridge). They can't jump or climb, so each is confined to its platform —
	it paces around but never walks off the edge (see set_confinement in the AI).

	@param chunk_pos: Chunk coordinates for seeded random generation
	@param parent_chunk: The chunk mesh to attach the crocodiles to
	@param platforms: Walkable-top descriptors
	                  ({ "center": Vector3, "half": Vector2, "top": float }) —
	                  `center.y` is the surface the guard paces, `top` is the
	                  TALLEST stone inside the footprint, which is what the guard
	                  is dropped in from (see the note in spawn_wall).
	"""
	if not terrain.crocodile_scene or platforms.is_empty():
		return

	# Chunk coords + run_seed, like every other seed site (see the run_seed doc block).
	var seed_value := hash(Vector3i(chunk_pos.x * 40499, chunk_pos.y * 86969, terrain.run_seed))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var count := 0
	for platform in platforms:
		# Only some platforms get a guard, so they stay a rare surprise.
		if rng.randf() > terrain.platform_crocodile_chance:
			continue

		var center: Vector3 = platform.center
		var half: Vector2 = platform.half

		# Start a little in from the edges so it lands cleanly on the surface.
		var ang := rng.randf_range(0.0, TAU)
		var sx := maxf(0.0, half.x - PLATFORM_SPAWN_EDGE_INSET) * cos(ang)
		var sz := maxf(0.0, half.y - PLATFORM_SPAWN_EDGE_INSET) * sin(ang)

		var crocodile := terrain.crocodile_scene.instantiate()
		crocodile.name = "PatrolCrocodile_%d_%d_%d" % [chunk_pos.x, chunk_pos.y, count]
		# Spawn just above the TALLEST stone in the platform's footprint, not above
		# the paced surface, so gravity settles it onto the ridge or onto a hump
		# instead of dropping it INSIDE one. `sx`/`sz` above pick a random angle
		# along the platform and nothing here knows which sections are doubled, so
		# the maximum is the only height that is clear at every angle — see the
		# platform "top" note in spawn_wall for the measurement.
		crocodile.position = Vector3(center.x + sx, platform.top + PLATFORM_SPAWN_HEIGHT, center.z + sz)
		crocodile.rotation.y = rng.randf_range(0.0, TAU)
		# Same BEFORE-add_child contract as the ground spawner above. NEGATIVE indices
		# (-1, -2, …) keep the platform guards on their own slice of the roll stream,
		# so platform guard #0 and ground crocodile #0 in the same chunk don't roll
		# the identical size and speed.
		crocodile.setup_roll_seed(_croc_roll_seed(terrain, chunk_pos, -1 - count))
		parent_chunk.add_child(crocodile)

		# Confine it to this platform (in world space) so it can never wander off.
		if crocodile.has_method("set_confinement"):
			var center_global: Vector3 = parent_chunk.global_position + center
			crocodile.set_confinement(center_global, half)

		count += 1

static func _croc_roll_seed(terrain: Node3D, chunk_pos: Vector2i, index: int) -> int:
	"""
	Deterministic seed for one crocodile's per-instance SIZE/SPEED rolls.

	@param chunk_pos: Chunk that spawns the crocodile
	@param index: Which crocodile in that chunk. Ground crocodiles pass their
	              spawn slot (0, 1, 2, …); platform guards pass -1 - count, so the
	              two spawners can never hand the same seed to two crocodiles in
	              the same chunk.
	@return: Seed to hand the instance via setup_roll_seed()

	This is its OWN independent hash stream — the _boss_at / _artifact_at /
	_camp_at pattern — mixing chunk coords, the croc index and run_seed with
	coordinate primes distinct from the object (73856093 / 19349663), biome
	(83492791 / 15485863) and camp (40960001 / 26463089) streams. It draws from NO
	RandomNumberGenerator at all, so the crocodile spawner's own sequence — and
	therefore every crocodile POSITION — is byte-for-byte unchanged.

	WHY it exists: multiplayer needs every peer to compute identical crocodile
	spawn state from the shared run_seed. Everything else in world generation was
	already a pure function of chunk coords + run_seed; the crocodile's size/speed
	rolls were the one single-player-era exception (a randomize()d per-instance
	RNG), and this is what closes it.
	"""
	return hash(Vector3i(
		chunk_pos.x * 179424673 + index,
		chunk_pos.y * 32452843,
		terrain.run_seed ^ CROC_ROLL_SALT
	))

static func _boss_at(terrain: Node3D, i: int) -> Dictionary:
	"""
	Deterministic placement + size for boss index `i` (>= 1). Pure function of
	`i` + run_seed via the independent BOSS_SEED hash stream — no shared RNG is
	touched, so the rest of the world regenerates byte-identically.

	@param i: Boss index (1-based). Owns station k = i * BOSS_INTERVAL_STATIONS.
	          ASSUMES the station cache already covers `k` (callers
	          _road_extend_to_x first, like _road_coins_at).
	@return: { "positions": Array[Vector3] (world-space candidates, best first),
	           "scale": float (body scale) }.

	EDUCATIONAL NOTE:
	- The RNG draws ONLY lateral offsets (BOSS_PLACE_TRIES draws, fixed order),
	  so boss placement is stable within a run: revisiting a chunk regenerates
	  the identical boss. Across runs, run_seed changes BOTH the road and this
	  stream, so bosses land elsewhere.
	- positions[0] is the ONE draw this function used to make, and it is drawn
	  FIRST, so it is bit-identical to the pre-obstacle-check behaviour. The
	  extra candidates are appended AFTER it and only ever consulted when the
	  spawner rejects an earlier one for standing in a block footprint — nothing
	  in the schedule (station, size, rarity) moves.
	- Y sits a little above ground; gravity settles the body (the croc's capsule
	  bottom is at its origin, so this works at any scale).
	"""
	var k := i * BOSS_INTERVAL_STATIONS
	var st: Dictionary = terrain._road_station(k)
	var heading: float = st.heading
	# Same tangent/perp construction as _road_coins_at (XZ plane; Vector2.x ->
	# world X, Vector2.y -> world Z).
	var tangent := Vector2(cos(heading), sin(heading))
	var perp := Vector2(-sin(heading), cos(heading))

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(i, BOSS_SEED, terrain.run_seed))
	# Candidate lateral offsets, drawn in one fixed order. The first draw is the
	# original (and overwhelmingly the used) one; the rest are fallbacks for a
	# boss whose primary spot happens to sit inside a block/tree/mountain
	# footprint — see spawn_bosses_in_chunk.
	var positions: Array[Vector3] = []
	for _try in BOSS_PLACE_TRIES:
		var lateral := rng.randf_range(-1.0, 1.0) * BOSS_LATERAL_MAX
		var p: Vector2 = st.center + tangent * BOSS_FORWARD_OFFSET + perp * lateral
		positions.append(Vector3(p.x, 0.6, p.y))

	# Size schedule: boss 1 is exactly BOSS_BASE_SCALE, each successive boss is
	# BOSS_GROWTH of base bigger, capped at BOSS_MAX_SCALE (see the consts above).
	var body_scale := minf(BOSS_BASE_SCALE * (1.0 + float(i - 1) * BOSS_GROWTH), BOSS_MAX_SCALE)
	return { "positions": positions, "scale": body_scale }

static func _boss_row_at(terrain: Node3D, station_centre: Vector2) -> Dictionary:
	"""
	Which animal guards the boss station whose centreline point is `station_centre`.

	@param station_centre: The OWNING STATION's centre in world coordinates,
	                       packed the way the road cache packs it (Vector2.x is
	                       world X, Vector2.y is world Z). Pure in the boss index
	                       + run_seed, which is what makes this answer pure in the
	                       boss index too — see BIOME_BOSS for why it must be.
	@return: { "species": String, "scene": PackedScene }. Never empty: the
	         crocodile is the fallback for a river station, for a band with no
	         BIOME_BOSS row, and for a row whose scene fails to load.

	NOT ONE RNG DRAW, and that is a constraint rather than a preference (CLAUDE.md's
	determinism section; the same rule BIOME_SPECIES and CITY_CROC_DIVISOR are held
	to). biome_at() and is_river_at() are the pure, allocation-free public API — one
	noise evaluation each, no shared stream touched — so inserting this call left
	_boss_at's BOSS_SEED stream consuming byte-identical draws in the same order.

	With BIOME_BOSS empty every path here returns the crocodile, which is the seam
	landing with zero behaviour change.
	"""
	var fallback := { "species": "crocodile", "scene": terrain.crocodile_scene }
	# Rivers first, and unconditionally: the owner's rule is that water is the
	# crocodile's, whichever band the noise field says the station stands in.
	if terrain.is_river_at(Vector3(station_centre.x, 0.0, station_centre.y)):
		return fallback
	var biome: terrain.Biome = terrain.biome_at(station_centre.x, station_centre.y)
	if not terrain.BIOME_BOSS.has(biome):
		return fallback
	var row: Dictionary = terrain.BIOME_BOSS[biome]
	# Lazily loaded and cached per band, exactly like _species_scenes: a run may
	# never walk far enough to meet a snow boss, and the one that does should not
	# re-load() the scene at every station.
	if not terrain._boss_scenes.has(biome):
		terrain._boss_scenes[biome] = load(row["scene"])
		if not terrain._boss_scenes[biome]:
			push_warning("endless_terrain: boss scene %s failed to load, using the crocodile"
					% row["scene"])
	var scene: PackedScene = terrain._boss_scenes[biome]
	if not scene:
		return fallback
	return { "species": String(row["species"]), "scene": scene }


static func spawn_bosses_in_chunk(terrain: Node3D, chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array = []) -> void:
	"""
	Spawn this chunk's boss crocodiles — the rare road-guarding giants placed every
	BOSS_INTERVAL_STATIONS stations along the coin road (see the BOSS CROCODILES
	config section near the top).

	Follows spawn_coins_in_chunk's seam-claim pattern exactly: extend the shared
	station cache over this chunk's padded X-window, walk the boss indices whose
	stations fall inside it, and spawn ONLY the bosses whose FINAL world position
	lands in THIS chunk (world_to_chunk(pos) == chunk_pos) — each boss is claimed
	by exactly one chunk, so there are no seam gaps or duplicates.

	A boss is 3.75x–9x the size of a normal crocodile and stands ON the road, so a
	boss wedged into a wall/mound/tree/mountain sits right on the player's path.
	Each boss therefore walks its deterministic candidate list (see _boss_at) and
	takes the first spot clear of every footprint in `obstacles`, exactly like the
	sibling spawners — and is skipped entirely if none is clear.

	THE CLAIM RULE (why the candidate walk stops early): `obstacles` only
	describes THIS chunk, so a chunk can only judge candidates that land inside
	itself. The loop therefore stops at the first candidate outside this chunk —
	from there on, another chunk owns the decision. That makes duplicates
	impossible: a chunk can only spawn a boss whose FIRST candidate already lies
	inside it, and only one chunk can contain that first candidate. The price is
	that a boss whose first candidate is blocked and whose next clear candidate
	falls in a NEIGHBOURING chunk is skipped rather than moved — a rare
	no-boss-here, which is an outcome the design already allows.

	@param chunk_pos: Chunk coordinates this call is generating bosses for.
	@param parent_chunk: The chunk mesh to attach bosses to. Chunk parenting is a
	                     FEATURE here: outrunning a boss far enough unloads its
	                     chunk and frees the boss with it — which reads to the
	                     player as "you escaped it".
	@param obstacles: This chunk's block footprints ({ pos (chunk-LOCAL), radius,
	                  top, climbable }), as built by spawn_objects_in_chunk and
	                  extended by the artifact/biome builders.
	"""
	if not terrain.crocodile_scene:
		return

	# Padded chunk X-window, same shape as the coin scan: a boss's world X can
	# differ from its station's centerline X by at most the forward offset plus
	# the lateral offset (each projection is bounded by its magnitude), so this
	# pad guarantees no boss near a seam is ever missed by the chunk that owns it.
	var center := terrain.chunk_to_world(chunk_pos)
	var half_chunk := terrain.chunk_size / 2.0
	var x0 := center.x - half_chunk
	var x1 := center.x + half_chunk
	var pad := BOSS_LATERAL_MAX + BOSS_FORWARD_OFFSET + 2.0

	terrain._road_extend_to_x(x0 - pad, x1 + pad)

	# Smallest boss index whose station could fall at/after the window start:
	# round the first in-window station up to the next interval multiple. Bosses
	# start at index 1 — station 0 is the player spawn, no boss there.
	var k_start := terrain._road_first_k_at_or_after_x(x0 - pad)
	var i := maxi(1, ceili(float(k_start) / float(BOSS_INTERVAL_STATIONS)))
	while true:
		var cur_i := i
		i += 1
		var k := cur_i * BOSS_INTERVAL_STATIONS
		# Past the cache = past this chunk's padded window (the cache spans it and
		# centerline X is strictly increasing in k), so we're done either way.
		if k > terrain.road_k_max:
			break
		# CAP 3 OF 5 — no boss stands past the road's terminal station (bead
		# godot-test1-8gw.3). Bosses GUARD the coin road; east of T there is no road
		# to guard, and the city's own predator policy is Budapest's to decide.
		#
		# It sits ABOVE _boss_row_at below, deliberately: the BIOME_BOSS dispatch
		# must never fire for a station the road does not reach, or the city would
		# be picking boss kinds for bosses that are never placed. `break`, not
		# `continue` — k = cur_i * BOSS_INTERVAL_STATIONS is strictly increasing in
		# `i`, so once one index is past T every later one is too. No RNG has been
		# drawn at this point (_boss_at is a pure hash stream), so leaving early
		# consumes nothing and slides nothing.
		#
		# The cap is on this CONSUMER and not on _road_extend_to_x, whose forward
		# loop hangs when the cache stops growing (see _road_terminal_k) and whose
		# binary-search callers — the k_start above is one — assume it spans any X.
		if k > terrain._road_terminal_k():
			break
		# The station's centreline point, read ONCE: it bounds the window scan
		# below AND it is what this boss's species is dispatched on (see
		# _boss_row_at) — the only coordinate a boss has that is pure in `cur_i`.
		var station_centre: Vector2 = terrain._road_station(k).center
		if station_centre.x > x1 + pad:
			break

		# WHICH BOSS THIS STATION GETS, decided HERE — above the candidate walk,
		# and that position in the function is the point. Dispatching on the
		# station centre is what makes the boss KIND a pure function of `cur_i`;
		# the walk below only decides WHERE the animal stands (or whether it fits
		# at all), by testing BOSS_PLACE_TRIES offsets against this chunk's
		# geometry. Compute the kind before `local_pos` exists and keying on the
		# placed candidate — which is neither pure in `cur_i` nor guaranteed to be
		# in the same biome band — is not a mistake that can be made by accident.
		# Pure function calls, no RNG draw, so the stream below is untouched.
		var boss_row: Dictionary = _boss_row_at(terrain, station_centre)

		var boss: Dictionary = _boss_at(terrain, cur_i)
		var boss_scale: float = boss.scale
		# Clearance this boss needs, SCALED BY ITS SIZE — a 9x boss reaches ~6.3 m
		# where a normal crocodile reaches ~0.7, so the crocodile spawner's fixed
		# min_object_clearance would be nowhere near enough (see the constant).
		var footprint: float = BOSS_FOOTPRINT_RADIUS_PER_SCALE * boss_scale

		# Walk the deterministic candidates: take the first one that is both ours
		# (the claim rule in the docstring) and clear of every footprint.
		var local_pos := Vector3.ZERO
		var placed := false
		for candidate in boss.positions:
			# Exactly-one-chunk claim: the moment a candidate lands elsewhere, that
			# chunk owns the rest of this boss's decision — stop, don't skip ahead.
			if terrain.world_to_chunk(candidate) != chunk_pos:
				break
			# Obstacle footprints are stored chunk-LOCAL, so compare in that space.
			var local := Vector3(candidate.x - center.x, candidate.y, candidate.z - center.z)
			var clear := true
			for ob in obstacles:
				var horizontal := Vector2(local.x - ob.pos.x, local.z - ob.pos.z).length()
				if horizontal < ob.radius + footprint:
					clear = false
					break
			# The tower's site is one more thing a boss may not stand in — its own
			# scaled footprint again, so a 9x boss cannot lean into the doorway.
			# Post-draw by construction: _boss_at already computed this whole
			# candidate list on its own hash stream, so skipping one costs nothing.
			if clear and terrain.tower_excludes(candidate.x, candidate.z, footprint):
				clear = false
			if clear:
				local_pos = local
				placed = true
				break
		# Not ours, or every candidate of ours was buried in geometry: no boss here.
		if not placed:
			continue

		var croc = boss_row["scene"].instantiate()
		# THE NAME IS "BossCrocodile_%d" FOR EVERY SPECIES, deliberately. croc_id
		# derives from the deterministic node name, so it is this body's
		# multiplayer identity, and enemy_spawn_selfcheck's sweep classifies
		# bodies by exactly these three prefixes. A per-species name would buy
		# nothing and churn both.
		# A FIELD BRIDGE IS A FLOOR: a boss whose spot is on a deck stands ON it
		# rather than inside the slab (see field_bridge_stand_y). A river station
		# dispatches the crocodile, and a river station is exactly where a deck
		# is, so this is the common case and not a corner of one.
		local_pos.y = terrain.field_bridge_stand_y(
				terrain.chunk_to_world(chunk_pos).x + local_pos.x,
				terrain.chunk_to_world(chunk_pos).z + local_pos.z, local_pos.y)

		croc.name = "BossCrocodile_%d" % cur_i
		# Chunk-LOCAL position (relative to the chunk center), like every other
		# chunk-parented node. Default rotation — the wander AI turns it within a
		# second anyway, and drawing a rotation would add an RNG draw for nothing.
		croc.position = local_pos
		# CALL-ORDER CONTRACT, one line longer than it used to be: `species`
		# BEFORE setup_as_boss BEFORE add_child. _ready() runs on add_child
		# (terrain-parented) and it is where BOTH halves are read — it resolves
		# `spec` from `species` exactly once, and it sees the boss flags and skips
		# the random speed/size rolls in favour of the schedule. Assign either one
		# after add_child and the body keeps a crocodile's spec, or takes rolls a
		# boss must not have, with no error anywhere. This is the same contract
		# the ground spawner's `species` assignment has, for the same reason.
		croc.species = boss_row["species"]
		croc.setup_as_boss(boss.scale)
		parent_chunk.add_child(croc)

		# THE BOSS IS A THING BUILT, SO IT PAYS THE SHARED CURRENCY (bead
		# godot-test1-6op, found by the 9k7 review of PR #187 — a coin sitting at
		# the crocodile's flank in the PR's own screenshot). Every other spawner
		# appends its footprint to `obstacles` and the later ones read it; a boss
		# appended nothing, so `spawn_coins_in_chunk` — which runs AFTER this
		# function in create_chunk, so no reordering was needed — laid its road
		# coins straight through a body up to 6.3 m across (~125 m² swallowed per
		# boss at 9x scale).
		#
		# `top: 0.0, climbable: false` is the whole point and not a placeholder: a
		# non-climbable footprint makes `_settle_coin_y` SKIP the coin rather than
		# perch it, which is the right answer for a body — the cactus / camp /
		# canopy call, one home for the rule. The radius is the same scaled
		# clearance the candidate walk above judged this boss's own spot by, so the
		# stone a boss is kept out of and the coins kept out of a boss are one
		# number.
		#
		# COSTS NO DRAW and appends AFTER placement, so it perturbs nothing on this
		# boss's own stream. It IS visible to the spawners below this one in
		# create_chunk (a later boss in the same chunk, and the hunter), which is
		# correct in exactly the same way: neither should be standing inside it.
		obstacles.append({
			"pos": Vector3(local_pos.x, 0.0, local_pos.z),
			"radius": footprint,
			"top": 0.0,
			"climbable": false,
		})
