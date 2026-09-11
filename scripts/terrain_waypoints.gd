class_name TerrainWaypoints
extends RefCounted
## ============================================================================
## THE WAYPOINTS — eleven indexed circles, and the ring you stand on
## ============================================================================
## Epic `godot-test1-sc6`, child .1. Owner, 2026-09-12, verbatim: *"teleports
## system like in diablo 2. we have here and there teleport circles. when found -
## get's active for the whole crew. allow to teleports between open one (chose on
## the teleport map)"*.
##
## This bead ships the PLACES and the GEOMETRY and nothing else: eleven rings
## stand in the world, their beams are built and hidden, and no hero has any way
## to notice. Discovery (.2), travel (.3), the panel (.4) and the polish (.5)
## each land on top of what is written here.
##
## It is a `class_name`d library of STATIC functions that RECEIVES the terrain as
## its first argument and calls `terrain.create_box` / `terrain._road_station`
## back through the reference — the `terrain_landmarks.gd` / `coin_road.gd`
## idiom, and the eighth family to be written in it. Read that file's banner
## first; everything below is a departure from it or a copy of it.
##
## ----------------------------------------------------------------------------
## THE INDEX IS THE CONTRACT
## ----------------------------------------------------------------------------
## `waypoint_sites()` returns a FIXED-LENGTH, FIXED-ORDER array, and the INDEX of
## a row — not its `id`, not its position — is the bit `.2` will set in
## `waypoint_mask` and send over the wire as one int, the way `explored_mask`
## already travels. So the order is a wire format:
##
##      0  "hq"          just outside the HQ door
##      1  "approach"    half way down the road between the HQ and the spawn
##      2  "spawn"       the first station of the road east of the origin
##      3  "road_1"  \
##      4  "road_2"   >  one per WAYPOINT_SPACING metres of road X
##      5  "road_3"  /
##      6  "gate"      \
##      7  "pest"       |
##      8  "parliament" >  BudapestPlan.WAYPOINTS, authored
##      9  "market"     |
##     10  "heroes"    /
##
## ELEVEN, AND THAT IS AN OWNER RULING (2026-09-12): the HQ door plus two more
## along its approach, the road every ~450 m, and five authored places in
## Budapest. The first draft had eight and the owner asked for 10-12 — the extra
## three are the approach circle, the Parliament's forecourt and the Market Hall
## crossing, which is what turns "three stops in a 2.2 km city" into a map you
## would actually travel on.
##
## THE COUNT IS CONSTANT ACROSS SEEDS, and that is what makes a fixed-width mask
## possible at all. Sites 0 and 6-10 are constants; 1-5 are looked up from the
## road's station cache at authored X targets, and the number of road slots is
## `int(ROAD_TERMINAL_X / WAYPOINT_SPACING)` = 3 — arithmetic over two constants,
## with no seed anywhere in it. A run cannot have ten waypoints or twelve.
##
## ----------------------------------------------------------------------------
## NOT ONE DRAW, NOT ONE NEW SALT, NOT ONE MEMO
## ----------------------------------------------------------------------------
## Every site is PURE ARITHMETIC over state that is already seeded. The road's
## station cache is a pure function of `run_seed` (`coin_road.gd`), `tower_site()`
## is a constant, and `BudapestPlan.WAYPOINTS` is authored — so this family needs
## no stream of its own, and CLAUDE.md's "never add or remove an RNG draw"
## applies to it by having nothing to add. `spawn_waypoint_in_chunk` is likewise
## a REVERSE LOOKUP (`_landmark_at`'s shape): it costs the chunk stream nothing,
## and `waypoint_selfcheck` check 2 proves it twice — once by reading this file
## as text, once by building a site-free chunk with the feature on and off and
## demanding the two be byte-identical down to the crocodile positions.
##
## A WET STATION IS RESOLVED BY A DETERMINISTIC RE-WALK, never by a draw: step
## `WAYPOINT_RIVER_STEP` stations further east and ask again, up to
## `WAYPOINT_RIVER_TRIES` times. That is `_build_landmark_sites`'s re-hash with
## the hash taken out, because here there is nothing to re-hash — the road is the
## only axis a road waypoint can move along.
##
## AND THERE IS NO MEMO. The table is rebuilt on every ask, which is one warm
## `_road_extend_to_x` (O(1) once any other road consumer has run), five binary
## searches and eleven small dictionaries. A memo would have to live on the
## terrain NODE and be named in `_drop_seeded_memos()` — `chunk_stream_selfcheck`
## check 6 audits exactly that — and a table that outlived a re-seed would string
## this run's waypoints along the LAST run's road.
## `ponytail:` the ceiling is one array per chunk generated. If `\fo` ever shows
## it, the upgrade is a `_waypoint_sites_cache` / `_built` pair on the terrain
## beside `_landmark_sites_cache`, dropped in the same function — not a static
## memo here, which check 6 bans outright.
##
## ----------------------------------------------------------------------------
## THE RING APPENDS NO FOOTPRINT, AND THAT IS THE ONE PLACE THIS FAMILY DEPARTS
## FROM EVERY SIBLING SPAWNER
## ----------------------------------------------------------------------------
## Artifacts, camps, landmarks and chests all append `{pos, radius, top,
## climbable}` to `obstacles` — the shared currency that keeps coins off their
## stone and crocodiles out of their middle. A waypoint appends NOTHING, and
## takes no collision either (`collide = false` on all thirteen boxes):
##
##   * It is 8 cm tall and flat. You WALK ONTO it — that is the whole interaction
##     `.2` is built on — so a collider would be a kerb to trip over and a
##     footprint would be an invisible wall for the crocodile chasing you.
##   * Road coins must SETTLE THROUGH IT. `_settle_coin_y` skips a coin whose
##     column crosses a non-climbable footprint, so a footprint here would punch
##     a 5 m hole in the coin road at five of the eleven sites.
##   * Crocodiles must ignore it. A footprint is the crocodile spawner's
##     exclusion test; a calm pocket round every waypoint would be a gameplay
##     change nobody asked for, and it would move every crocodile in the chunk.
##
## The consequence is that a waypoint can share ground with a block, a tree or a
## chest. That is FINE and it is deliberate: the circle is paint. It cannot be
## fine at the HQ door or on a street, and it is not — see the site notes below.
##
## ----------------------------------------------------------------------------
## THE ONE PER-OBJECT MESH THIS FEATURE SPENDS
## ----------------------------------------------------------------------------
## The thirteen ring boxes go through `create_box` into the chunk's ONE batch, so
## the circle costs ZERO extra draw calls beyond the CYLINDER bucket the disc
## adds to a chunk that had none (11 chunks in the world, at most a couple loaded
## at once). The BEAM cannot: it is emissive, and the block batch has one shared
## non-emissive material. So it is a real `MeshInstance3D`, exactly as
## `_spawn_artifact_accent` spends one for a glowing rune — the shared unit cube,
## the SHARED glow material (never a per-instance one), no shadow, and
## `visible = false` until `.2` lights it. ELEVEN IN THE WORLD, AT MOST TWO
## LOADED, and while this bead ships every one of them is hidden: the owner
## judges that cost by eye on the PR's screenshots.

## Metres of road X between one road waypoint and the next. 450 puts three of
## them on the 1450 m of centreline every road consumer acknowledges — far
## enough apart that walking between two is a journey, close enough that the run
## is never more than ~4 minutes of walking from one.
const WAYPOINT_SPACING: float = 450.0


## Where the "spawn" circle stands: the first station at or after this X. The
## hero spawns at (0, 2, 0), so 15 m east is in plain sight down the road on
## frame one without being the ground under their feet.
const WAYPOINT_SPAWN_X: float = 15.0

## Where the "approach" circle stands, on the 400 m of road between the HQ and
## the spawn — the owner's second HQ-area waypoint (2026-09-12).
##
## IT IS A CONSTANT AND NOT `tower_site().x * 0.5`, which is the one thing that
## matters here. `tower_site_selfcheck` check 5 moves the tower and demands that
## a chunk its disc does not reach come out byte-identical; a site derived from
## the tower's X would move with it, and with it the chunk this circle is built
## in. Half way down the shipped approach is -200, so -200 is what is written.
const WAYPOINT_APPROACH_X: float = -200.0

## How far OUTSIDE the shell's outer wall the HQ circle stands, on the door axis.
## `TowerShell.OUTER_HALF` is where the wall face is and the doorway is cut
## through it (see `door_trigger_box`), so the circle's centre is
## `OUTER_HALF + this` east of the tower's site — 8 m of yard, which clears the
## 2.6 m disc and the doorway's own trigger depth with room to walk round.
const WAYPOINT_DOOR_STANDOFF: float = 8.0

## THE WET RE-WALK. A road waypoint whose station sits in a river band would be a
## circle under a field bridge's deck (or in the water beside it), so it steps
## this many stations east and asks again, at most this many times. Both numbers
## are deterministic and neither is a draw: the re-walk is the same table read
## with a different index.
const WAYPOINT_RIVER_STEP: int = 10
const WAYPOINT_RIVER_TRIES: int = 12

## THE RING, in metres. A 5.2 m disc 8 cm proud of the ground with twelve studs
## just inside its rim — small enough to fit a 16 m city street with 5 m to spare
## either side, big enough that you cannot cross it without standing on it, which
## is what `.2`'s enter-edge scan needs.
const RING_RADIUS: float = 2.6
const RING_THICKNESS: float = 0.08
const STUD_COUNT: int = 12
const STUD_RING_RADIUS: float = 2.5
const STUD_SIZE := Vector3(0.5, 0.14, 0.5)

## Boxes one ring costs the chunk's batch: the disc plus its studs.
## `waypoint_selfcheck` check 4 asserts the batch grows by exactly this.
const RING_BOX_COUNT: int = 1 + STUD_COUNT

## COLD INDIGO, and it lives here rather than in `hud_theme.gd`: this is world
## paint, not a HUD skin, and `hero_hud_selfcheck` greps the six palette hexes to
## keep them the theme's alone. Chosen against the field's earthy ramps and the
## city's plaster — nothing procedural in this game is blue, so a ring reads as
## made-by-somebody at a hundred metres even while it is inert.
const RING_COLOR := Color(0.24, 0.27, 0.62)
const STUD_COLOR := Color(0.38, 0.44, 0.86)

## THE BEAM: a 9 m column of the shared artifact glow, 30 cm square. Hidden by
## this bead; `.2` shows it on the circle the room has found.
##
## FIVE TIMES A HERO, AND THAT IS AN OWNER RULING (2026-09-12) against the 14 m
## the first draft carried: *"the found-state beam is 5x hero height, not a sky
## beam"*. A hero's eye is at `PlayerController.FIRST_PERSON_EYE_HEIGHT` (1.65),
## so five of them is ~9 m — a marker you read from across a field or over a
## street wall, and NOT a pillar into the clouds that would make eleven circles
## the loudest thing in an otherwise low, flat world.
const BEAM_SIZE := Vector3(0.3, 9.0, 0.3)

## The group and the meta the later beads find a built circle by — group-based
## discovery, never a reference (CLAUDE.md). `index` is the wire bit.
const WAYPOINT_GROUP: String = "waypoint"
const WAYPOINT_MARKER_NAME: String = "WaypointMarker"


# ============================================================================
# THE SITES
# ============================================================================

static func road_slots(terrain: Node3D) -> int:
	"""
	How many road waypoints a run has: 1450 / 450 = 3, floored.

	@return: The slot count, and therefore three of the eleven mask bits.

	A FUNCTION RATHER THAN A CONSTANT for one reason — `ROAD_TERMINAL_X` is read
	off the TERRAIN, the way every other consumer of the road reads it
	(`terrain_landmarks.gd`), rather than reached for in `coin_road.gd` directly.
	It is still pure arithmetic over two constants with no seed in it, which is
	what makes the mask width the same in every world; see the banner.
	"""
	return int(terrain.ROAD_TERMINAL_X / WAYPOINT_SPACING)


static func waypoint_sites(terrain: Node3D) -> Array[Dictionary]:
	"""
	WHERE THE ELEVEN CIRCLES STAND THIS RUN, AT STABLE INDICES.

	@param terrain: The `EndlessTerrain`, for `tower_site()` and the road cache.
	@return: Exactly `road_slots() + 2 + BudapestPlan.WAYPOINTS.size()` rows of
	         `{ id: String, pos: Vector3 }`, in the order the banner's table fixes.
	         `pos.y` is always 0 — the world is flat and every one of these sites
	         is off the plateaus.

	THE ORDER IS A WIRE FORMAT. Index 0 is "hq", 1-2 are the approach and the
	spawn, 3-5 are the road, 6-10 are the city, and a row inserted in the middle
	renumbers every peer's `waypoint_mask` mid-room. Append, never insert.

	Costs no draw. See the banner: the road cache and `tower_site()` are already
	pure in `run_seed`, and the city's five are authored constants.
	"""
	var sites: Array[Dictionary] = []

	# --- 0: the HQ door. The tower is one building at one constant site and its
	# doorway is cut through the +X wall (`TowerShell.door_trigger_box`), so the
	# circle stands on that axis, `WAYPOINT_DOOR_STANDOFF` clear of the wall face.
	# The shell's constants are READ, never retyped — a retuned OUTER_HALF moves
	# the wall and this circle together.
	var tower: Vector3 = terrain.tower_site()
	sites.append({
		"id": "hq",
		"pos": Vector3(tower.x + TowerShell.OUTER_HALF + WAYPOINT_DOOR_STANDOFF, 0.0, tower.z),
	})

	# --- 1..5: the road. ONE `_road_extend_to_x` for all five and then a binary
	# search per target X. The span is the approach's west end to the terminal —
	# the corridor `terrain_landmarks.gd` walks, plus the HQ's approach, which that
	# file deliberately leaves out because its own corridor may not depend on where
	# the tower is. THE SPAN IS A CONSTANT HERE TOO (see WAYPOINT_APPROACH_X), and
	# extending the cache further west moves no station: every one of them is a
	# pure function of its index `k`, whichever direction the cache grew from.
	#
	# THE CENTRELINE IS CLEAR OF BLOCKS BY CONSTRUCTION: every field spawner keeps
	# a road clearance (`_biome_spot_ok`'s road half), so a circle on the station
	# centre never lands inside somebody's stone — which is what lets a road ring
	# get away with appending no footprint.
	terrain._road_extend_to_x(WAYPOINT_APPROACH_X, terrain.ROAD_TERMINAL_X)
	sites.append(_road_site(terrain, "approach", WAYPOINT_APPROACH_X))
	sites.append(_road_site(terrain, "spawn", WAYPOINT_SPAWN_X))
	for slot in range(1, road_slots(terrain) + 1):
		sites.append(_road_site(terrain, "road_%d" % slot, float(slot) * WAYPOINT_SPACING))

	# --- 6..10: Budapest, authored. The plan owns its own five spots for the same
	# reason it owns its landmark slots: the city is not seeded, and a site chosen
	# here would be a second opinion about where its streets are.
	for row: Dictionary in BudapestPlan.WAYPOINTS:
		sites.append({ "id": String(row["id"]), "pos": row["pos"] as Vector3 })

	return sites


static func _road_site(terrain: Node3D, id: String, target_x: float) -> Dictionary:
	"""
	One road waypoint: the first station at or after `target_x`, walked east out of
	the water if it landed in a river band.

	@param target_x: Metres of world X the slot aims at.
	@return: `{ id, pos }` with `pos` on the centreline at y = 0.

	THE RE-WALK IS NOT A DRAW. A station in a river band would put the circle
	under a field bridge's deck, so we step `WAYPOINT_RIVER_STEP` stations east and
	ask `is_river_at` again — the same deterministic table, a different index, and
	the only axis a road waypoint is allowed to move along. `k` is clamped to the
	cached range so a re-walk can never index a station `_road_extend_to_x` has
	not built (`_road_station` is a bare Dictionary lookup and would error).

	Callers must have extended the cache over `[WAYPOINT_APPROACH_X,
	ROAD_TERMINAL_X]` first — the one extend is shared by all five road sites,
	which is why it is not in here.
	"""
	var k: int = terrain._road_first_k_at_or_after_x(target_x)
	var tries: int = 0
	while tries < WAYPOINT_RIVER_TRIES:
		k = mini(k, terrain.road_k_max)
		var station: Dictionary = terrain._road_station(k)
		var centre: Vector2 = station.center
		if not terrain.is_river_at(Vector3(centre.x, 0.0, centre.y)):
			return { "id": id, "pos": Vector3(centre.x, 0.0, centre.y) }
		tries += 1
		k += WAYPOINT_RIVER_STEP
	# Every try was wet — the honest degrade. The site stays where the last one
	# looked, which `waypoint_selfcheck` check 3 would fail loudly rather than
	# shipping a circle in a river.
	k = mini(k, terrain.road_k_max)
	var last: Vector2 = terrain._road_station(k).center
	return { "id": id, "pos": Vector3(last.x, 0.0, last.y) }


# ============================================================================
# THE GEOMETRY
# ============================================================================

static func spawn_waypoint_in_chunk(terrain: Node3D, chunk_pos: Vector2i,
		parent_chunk: MeshInstance3D, obstacles: Array,
		block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Build every waypoint circle whose site falls in this chunk.

	Called from `create_chunk` after the chest and before the city slice, so the
	ring's boxes join the chunk's ONE MultiMesh batch and its ONE collision body
	(where they take no shape at all — see `collide = false` below). CITY CHUNKS
	INCLUDED: the five Budapest sites are ordinary chunk content, and a 5.2 m
	circle fits inside one 50 m chunk, so nothing here is sliced.

	@param obstacles: ACCEPTED AND NEVER APPENDED TO. The family signature is the
	                  shared one, and the banner's "no footprint, and why" is the
	                  one place this spawner departs from all four of its
	                  siblings. Read nothing, write nothing: a waypoint is paint.
	@param block_batch / block_body: The chunk's visual batch and collision body.

	A REVERSE LOOKUP, exactly like `_landmark_at`: it asks the site table which of
	the eleven (if any) live here and costs the chunk's streams nothing.
	"""
	if not terrain.spawn_waypoints:
		return
	var sites: Array[Dictionary] = waypoint_sites(terrain)
	var chunk_origin: Vector3 = terrain.chunk_to_world(chunk_pos)
	for i in sites.size():
		var pos: Vector3 = sites[i]["pos"]
		if terrain.world_to_chunk(pos) != chunk_pos:
			continue
		_build_ring(terrain, pos - chunk_origin, i, parent_chunk, block_batch, block_body)


static func _build_ring(terrain: Node3D, local_pos: Vector3, index: int,
		parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	One circle: `RING_BOX_COUNT` batched boxes, one hidden beam, one bare marker.

	@param local_pos: The site, CHUNK-LOCAL (the convention `create_box` and every
	                  per-chunk node in this project speak).
	@param index: The site's index in `waypoint_sites()` — the wire bit, carried
	              on the marker's `index` meta so `.2` never has to re-derive it
	              from a position.
	"""
	# A PRIVATE generator with a FIXED seed. `create_box` always draws its colour
	# ramp and its roughness from whatever generator it is handed (that is how it
	# keeps the shared chunk stream's sequence intact for everybody else), and
	# every one of those values is discarded here because `color_override` is set.
	# Passing our own means those draws land nowhere near the chunk's stream;
	# fixing the seed means the batch entry is byte-stable across runs, which is
	# what check 2's A/B compares.
	var rng := RandomNumberGenerator.new()
	rng.seed = 0

	# --- The disc: one flat CYLINDER, 8 cm proud of the ground, NOT COLLIDING.
	terrain.create_box(
			local_pos + Vector3(0.0, RING_THICKNESS * 0.5, 0.0),
			Vector3(RING_RADIUS * 2.0, RING_THICKNESS, RING_RADIUS * 2.0),
			0.0, rng, block_batch, block_body, 0.0, RING_COLOR, false,
			ChunkBatch.BoxKind.CYLINDER)

	# --- The studs: twelve small cubes just inside the rim, each turned to face
	# the centre so the ring reads as a made thing rather than a scatter. The yaw
	# is arithmetic over the stud index — no draw here either.
	for s in STUD_COUNT:
		var angle: float = TAU * float(s) / float(STUD_COUNT)
		terrain.create_box(
				local_pos + Vector3(cos(angle) * STUD_RING_RADIUS,
						STUD_SIZE.y * 0.5, sin(angle) * STUD_RING_RADIUS),
				STUD_SIZE, -angle, rng, block_batch, block_body,
				0.0, STUD_COLOR, false, ChunkBatch.BoxKind.CUBE)

	# --- The marker: a bare Node3D with no mesh, no script and no physics, found
	# BY GROUP the way every system in this project finds things, and parented to
	# the chunk so it is freed when the chunk unloads (the landmark marker
	# precedent — no registry to keep in step and nothing to leak).
	var marker := Node3D.new()
	marker.name = WAYPOINT_MARKER_NAME
	marker.position = local_pos
	marker.add_to_group(WAYPOINT_GROUP)
	marker.set_meta("index", index)
	parent_chunk.add_child(marker)

	# --- The beam: the feature's ONE per-object mesh (see the banner). The shared
	# unit cube carrying the size in its transform, the SHARED glow material (a
	# per-instance one here would be eleven materials and eleven pipeline states),
	# no shadow — a column of light does not shade — and HIDDEN: nothing in this
	# bead ever shows it, `.2` does when the room finds the circle.
	var beam := MeshInstance3D.new()
	beam.name = "WaypointBeam"
	beam.mesh = ChunkBatch._get_shared_unit_box_mesh()
	beam.transform = Transform3D(Basis().scaled(BEAM_SIZE), Vector3(0.0, BEAM_SIZE.y * 0.5, 0.0))
	beam.material_override = terrain._get_artifact_glow_material()
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.visible = false
	marker.add_child(beam)
