extends Node3D
## Ambient citizen crowds in Budapest: hero look-alike figures walking the streets.
##
## OWNER IDEA (2026-09-02): "the city has many people, and our heroes hid
## because those people look like our heroes. Super-similar figures walking the
## city in big masses."
##
## This manager (scripts/crowd_manager.gd, added once under Main in main.tscn,
## in group "crowd") is the ENTIRE feature — following the FAUNA precedent:
##   * Pure ambience, deliberately outside the run_seed determinism contract:
##     its own randomize()d RNG drives waypoint choices and walk speeds.
##   * Citizens join NO group and carry NO collision bodies or Area3Ds (a node in
##     "player" or "crocodile" would be grabbed by the Stink Wave, LOD, or chase).
##   * Solid anyway (bead 8gw.21): the MANAGER owns CITIZEN_PROXY_POOL colliders
##     that follow the nearest few citizens to the local player, on the fauna
##     layer that only the player masks. The citizens stay transforms in a
##     buffer; the pool joins no group and adds no draw call. See
##     scripts/ambience_proxies.gd for the isolation and the anti-trap rule.
##   * City defence (bead 8gw.16): nearest_citizen_to() is the seam the hunter
##     reads — the crowd confuses GD-SURVEY acquisitions inside the city.
##   * Budget: hard CROWD_MAX (60 on web, 120 on desktop) rendered via FOUR
##     MultiMeshInstance3D nodes (one per hero archetype: Windman, Primm, Teibi,
##     Phoboman), costing exactly 4 draw calls for the entire crowd (shadows off).
##   * Shared static resources: one shared composite mesh per archetype with
##     baked vertex colors derived from the hero specifications, and ONE shared
##     StandardMaterial3D across all archetypes (never duplicate() per citizen).
##   * Waypoint walk: citizens follow BudapestPlan.STREET_PITCH street grid, spread
##     across lateral street lanes, maintaining walking queues, never walking into
##     the Danube river, plateau cliffs, or solid landmark buildings.
##   * Feet rest at y = 0 by construction. Spawning occurs in a bubble around
##     the local player inside BudapestPlan.rect(), recycling when out of range.
##   * Transforms written in bulk via multimesh.buffer (never set_instance_transform).
##   * Budget (bead 8gw.22): a citizen the CAMERA cannot see is ticked COARSELY —
##     a few times a second, by the real elapsed time — never frozen. The rule and
##     its rate live in scripts/ambience_lod.gd; read that file's header for why a
##     freeze would look wrong and why the camera, not the player, is asked.
##     ONE decision per citizen per frame (`lod_step`), taken in
##     _update_crowd_spawns and spent by _update_walkers, so the walkability and
##     recycle checks are made on exactly the ticks the citizen takes.
##   * Traffic-aware (bead 8gw.23): a walker following an AVENUE stands on the
##     PAVEMENT rather than in a car lane (PAVEMENT_LANE_OFFSET), one crossing
##     holds at the kerb while a car is inside its braking distance
##     (traffic_manager.blocks_crossing), and one already in the road is BRAKED
##     FOR (blocking_citizen_distance, the seam the cars read). Group discovery
##     both ways, has_method-guarded: still no body, no group, 4 draw calls.
##   * Spread (same bead): _find_spawn_segment_near draws uniformly over the
##     STREET NETWORK in the bubble rather than uniformly in r off a snapped
##     intersection, MIN_WALKER_SPACING is enforced at spawn, and a recycle goes
##     to the far half of the bubble. Read that function for the measurement.

# ============================================================================
# CONSTANTS — budgets, distances, and grid
# ============================================================================

## Maximum live citizens: 60 on Web export for strict draw and CPU budgets,
## 120 on Desktop.
const CROWD_MAX_DESKTOP: int = 120
const CROWD_MAX_WEB: int = 60

## Active spawn and recycling radii around the local player (metres).
const SPAWN_RADIUS: float = 110.0
const DESPAWN_RADIUS: float = 145.0
const SPAWN_MIN_DIST: float = 15.0

## Walking speeds (m/s) — a natural pedestrian pace.
const WALK_SPEED_MIN: float = 1.8
const WALK_SPEED_MAX: float = 2.8

## Stride animation parameters: radians of phase per metre travelled.
const STRIDE_FREQUENCY: float = 4.2
const WALK_BOB_AMOUNT: float = 0.045
const WALK_SWAY_AMOUNT: float = 0.035
const WALK_PITCH_AMOUNT: float = 0.015

## Minimum distance between walkers in the same street lane (metres).
## ENFORCED AT SPAWN since bead 8gw.23 (it used to be a number nobody read, and
## two citizens could be placed on the same metre of street) — see
## `_too_close_to_walker`.
const MIN_WALKER_SPACING: float = 1.8

## Lateral lane offsets across the street corridor.
const LANE_OFFSETS: Array[float] = [-3.2, -1.6, 0.0, 1.6, 3.2]

## THE PAVEMENT LANE, for a citizen walking ALONG an avenue (bead 8gw.23).
##
## Every CITY_AVENUE_EVERY-th grid line carries traffic_manager's cars, in lanes
## at ±LANE_OFFSET (2.4 m) either side of the centreline. A citizen in one of the
## LANE_OFFSETS above is 0.8 m from a car lane — half a car's width (0.925) plus
## half a citizen's (0.3) is 1.225, so it stands IN the traffic and is driven
## through, every time, for the whole length of the avenue. That is the owner's
## "crowds still go through cars" far more than any crossing is.
##
## So an avenue walker goes on the PAVEMENT instead: outside AVENUE_HALF_WIDTH
## (8.0, the carriageway edge) and inside the block face, which BudapestPlan
## insets by AVENUE_HALF_WIDTH + BLOCK_PAVEMENT (9.2). 8.6 puts a 0.6 m-wide
## citizen at 8.3–8.9 — clear of both, and far outside the cars' own
## LATERAL_TOLERANCE, so no car ever brakes for somebody on the kerb.
const PAVEMENT_LANE_OFFSET: float = 8.6

## Where a RECYCLED walker reappears: the far half of the bubble (bead 8gw.23).
## A recycle used the same [SPAWN_MIN_DIST, SPAWN_RADIUS] draw as a first spawn,
## so a citizen leaving at 145 m could pop back 15 m from the hero's nose — and
## since the bubble is churning continuously as the player walks, that is a
## second, steady pump concentrating the crowd around him.
const RECYCLE_MIN_DIST: float = SPAWN_RADIUS * 0.6

## Hero archetype indices (order matches PlayerController.CHARACTERS).
const ARCHETYPE_WINDMAN: int = 0
const ARCHETYPE_PRIMM: int = 1
const ARCHETYPE_TEIBI: int = 2
const ARCHETYPE_PHOBOMAN: int = 3
const ARCHETYPE_COUNT: int = 4

const ARCHETYPE_NAMES: Array[String] = [
	"windman",
	"primm",
	"teibi",
	"phoboman",
]

# ============================================================================
# STATE
# ============================================================================

## Private randomize()d RNG — ambience outside determinism contract.
var _rng := RandomNumberGenerator.new()

## Active budget for the running platform.
var _crowd_max: int = CROWD_MAX_DESKTOP

## List of all citizen state dictionaries.
## Each record:
##   archetype: int (0..3)
##   pos: Vector3 (current intersection/grid position along street)
##   target: Vector3 (next target intersection along street)
##   lane_offset: float (lateral offset perpendicular to street direction)
##   speed: float (walking speed in m/s)
##   walk_phase: float (accumulated stride distance)
##   pause_timer: float (time remaining to wait at intersection)
##   facing_yaw: float (current facing angle in radians)
##   heading_dir: Vector2 (current direction vector on XZ)
##   active: bool (whether currently spawned and active)
##   lod_debt: float (seconds banked while out of view — ambience_lod.gd's)
##   lod_step: float (seconds to advance THIS frame; 0.0 = not this citizen's tick)
var _citizens: Array[Dictionary] = []

## Four MultiMeshInstance3D child nodes (one per archetype).
var _multimesh_nodes: Array[MultiMeshInstance3D] = []

## The pooled proxy colliders (CITIZEN_PROXY_POOL of them, the MANAGER's nodes —
## never a citizen's). See ambience_proxies.gd.
var _proxies: RefCounted = null

## Reusable Budapest plan reference (pure static calls).
const PLAN_SCRIPT := preload("res://scripts/budapest_plan.gd")

## The shared "coarse-tick what we cannot see" rule — see its header.
const AmbienceLod := preload("res://scripts/ambience_lod.gd")

## The shared pooled-proxy collider — read its header for why the citizens
## themselves stay bodiless and how the player is kept from being trapped.
const AmbienceProxies := preload("res://scripts/ambience_proxies.gd")

## HOW MANY CITIZENS CAN TOUCH THE HERO AT ONCE. MEASURED, not guessed: over six
## runs of 3,600 frames each, at four city locations, at the desktop cap of 120,
## the most citizens ever simultaneously inside CITIZEN_PROXY_REACH of the player
## was FOUR — and it was 0 or 1 on 85% of frames. MIN_WALKER_SPACING (1.8 m)
## bounds it anyway: a 3 m disc cannot hold many walkers that keep 1.8 m apart.
## Six is that measurement with room for a crossing crowding a corner, and it is
## a CONSTANT — it does not grow with CROWD_MAX, which is the whole point of a
## pool. Anything past the sixth nearest is a ghost, which is exactly the set the
## hero cannot reach.
const CITIZEN_PROXY_POOL: int = 6

## How near a citizen must be to be given a body. Contact happens at ~0.8 m
## (player radius 0.5 + citizen 0.3); 3 m is a quarter of a second of lead even
## at a sprinting hero closing on an oncoming walker, and the pool covers
## everything inside it.
const CITIZEN_PROXY_REACH: float = 3.0

## The citizen's footprint and height — a shoulders-wide box around the walker,
## deliberately slimmer than the mesh so a hero brushes past rather than snags.
const CITIZEN_PROXY_HALF := Vector2(0.30, 0.30)
const CITIZEN_PROXY_HEIGHT: float = 1.75

# ============================================================================
# SHARED RESOURCES (static — one per PROCESS, not per citizen/manager)
# ============================================================================

static var _shared_material: StandardMaterial3D = null
static var _archetype_meshes: Array = [null, null, null, null]
static var _box_cache: Dictionary = {}


static func _get_shared_material() -> StandardMaterial3D:
	## The ONE standard material with vertex colors and sRGB conversion enabled,
	## shared by all four crowd MultiMeshes across the entire session.
	if _shared_material == null:
		_shared_material = StandardMaterial3D.new()
		_shared_material.vertex_color_use_as_albedo = true
		_shared_material.vertex_color_is_srgb = true
		_shared_material.roughness = 0.85
		_shared_material.cull_mode = BaseMaterial3D.CULL_BACK
	return _shared_material


static func _box_mesh(size: Vector3) -> BoxMesh:
	## Cached BoxMesh generator to ensure engine-accurate standard normals,
	## vertex winding, and UVs.
	if not _box_cache.has(size):
		var bm := BoxMesh.new()
		bm.size = size
		_box_cache[size] = bm
	return _box_cache[size]


static func _add_box(st: SurfaceTool, center: Vector3, size: Vector3, col: Color) -> void:
	## Adds an engine-accurate 6-sided box with correct outward CCW winding
	## and vertex color to a SurfaceTool.
	var arrays: Array = _box_mesh(size).get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	for i: int in indices:
		st.set_color(col)
		st.set_normal(normals[i])
		st.add_vertex(center + verts[i])


static func _get_archetype_mesh(archetype: int) -> ArrayMesh:
	## Lazy getter for the composite Mesh of a given hero archetype.
	## Built once per archetype using SurfaceTool and shared across all instances.
	if _archetype_meshes[archetype] != null:
		return _archetype_meshes[archetype]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	match archetype:
		ARCHETYPE_WINDMAN:
			# Windman Look-Alike (~1.75 m): Moderately stout humanoid build.
			# Royal blue tee with single white 'W' chest monogram, blue-over-red eye bandage,
			# short messy brown hair, baggy brown shorts, black boots, pinwheel fan in hand.
			var skin := Color(0.93, 0.74, 0.62)
			var hair := Color(0.32, 0.20, 0.11)
			var shirt_blue := Color(0.18, 0.35, 0.62)
			var letter_white := Color(0.95, 0.95, 0.95)
			var bandage_blue := Color(0.20, 0.38, 0.75)
			var bandage_red := Color(0.72, 0.18, 0.15)
			var shorts_brown := Color(0.42, 0.30, 0.18)
			var boots_black := Color(0.08, 0.08, 0.09)
			var fan_blue := Color(0.16, 0.45, 0.85)
			var fan_red := Color(0.85, 0.20, 0.18)
			var fan_handle := Color(0.45, 0.30, 0.16)

			# Boots (left & right) — feet at y = 0 (0.14 - 0.28/2 = 0)
			_add_box(st, Vector3(-0.14, 0.14, 0.04), Vector3(0.16, 0.28, 0.28), boots_black)
			_add_box(st, Vector3(0.14, 0.14, 0.04), Vector3(0.16, 0.28, 0.28), boots_black)
			# Bare lower legs
			_add_box(st, Vector3(-0.14, 0.42, 0.0), Vector3(0.13, 0.30, 0.13), skin)
			_add_box(st, Vector3(0.14, 0.42, 0.0), Vector3(0.13, 0.30, 0.13), skin)
			# Brown knee-length baggy shorts
			_add_box(st, Vector3(-0.14, 0.68, 0.0), Vector3(0.18, 0.26, 0.20), shorts_brown)
			_add_box(st, Vector3(0.14, 0.68, 0.0), Vector3(0.18, 0.26, 0.20), shorts_brown)
			_add_box(st, Vector3(0.0, 0.82, 0.0), Vector3(0.44, 0.22, 0.26), shorts_brown)
			# Royal blue tee torso
			_add_box(st, Vector3(0.0, 1.15, 0.0), Vector3(0.46, 0.48, 0.26), shirt_blue)
			# White "W" chest band / monogram
			_add_box(st, Vector3(0.0, 1.20, -0.135), Vector3(0.32, 0.12, 0.02), letter_white)
			_add_box(st, Vector3(0.0, 1.12, -0.135), Vector3(0.10, 0.08, 0.02), letter_white)
			# Arms (short blue sleeves + bare skin forearms)
			_add_box(st, Vector3(-0.29, 1.26, 0.0), Vector3(0.13, 0.18, 0.13), shirt_blue)
			_add_box(st, Vector3(0.29, 1.26, 0.0), Vector3(0.13, 0.18, 0.13), shirt_blue)
			_add_box(st, Vector3(-0.29, 0.98, 0.0), Vector3(0.11, 0.38, 0.11), skin)
			_add_box(st, Vector3(0.29, 0.98, 0.0), Vector3(0.11, 0.38, 0.11), skin)
			# Pinwheel fan in right hand
			_add_box(st, Vector3(0.36, 0.92, -0.12), Vector3(0.03, 0.22, 0.03), fan_handle)
			_add_box(st, Vector3(0.36, 1.05, -0.12), Vector3(0.16, 0.08, 0.02), fan_blue)
			_add_box(st, Vector3(0.36, 1.05, -0.12), Vector3(0.08, 0.16, 0.02), fan_red)
			# Head & messy brown hair
			_add_box(st, Vector3(0.0, 1.54, 0.0), Vector3(0.30, 0.30, 0.30), skin)
			_add_box(st, Vector3(0.0, 1.68, 0.0), Vector3(0.32, 0.08, 0.32), hair)
			_add_box(st, Vector3(0.0, 1.58, 0.14), Vector3(0.32, 0.24, 0.06), hair)
			# Blue-over-red eye bandage wrapping head
			_add_box(st, Vector3(0.0, 1.58, 0.0), Vector3(0.32, 0.06, 0.32), bandage_blue)
			_add_box(st, Vector3(0.0, 1.52, 0.0), Vector3(0.32, 0.06, 0.32), bandage_red)

		ARCHETYPE_PRIMM:
			# Primm Look-Alike (~1.78 m): Slim, lean, athletic young man.
			# Long open purple trench coat with silver trim, black inner shirt with cyan circuit,
			# dark navy jeans, silver tech visor with pale blue lens, black boots with silver band.
			var skin := Color(0.91, 0.73, 0.62)
			var hair := Color(0.26, 0.16, 0.10)
			var coat_purple := Color(0.32, 0.16, 0.46)
			var silver_trim := Color(0.74, 0.76, 0.80)
			var cuff_grey := Color(0.62, 0.68, 0.74)
			var shirt_black := Color(0.07, 0.07, 0.10)
			var cyan_glow := Color(0.20, 0.85, 0.85)
			var jeans_navy := Color(0.10, 0.11, 0.17)
			var boots_black := Color(0.07, 0.07, 0.08)
			var boot_band := Color(0.86, 0.88, 0.90)
			var visor_frame := Color(0.70, 0.72, 0.76)
			var visor_lens := Color(0.66, 0.80, 0.90)

			# Black boots with silver band — feet at y = 0 (0.13 - 0.26/2 = 0)
			_add_box(st, Vector3(-0.11, 0.13, 0.03), Vector3(0.14, 0.26, 0.26), boots_black)
			_add_box(st, Vector3(0.11, 0.13, 0.03), Vector3(0.14, 0.26, 0.26), boots_black)
			_add_box(st, Vector3(-0.11, 0.26, 0.0), Vector3(0.15, 0.04, 0.16), boot_band)
			_add_box(st, Vector3(0.11, 0.26, 0.0), Vector3(0.15, 0.04, 0.16), boot_band)
			# Slim dark navy jeans
			_add_box(st, Vector3(-0.11, 0.52, 0.0), Vector3(0.13, 0.50, 0.14), jeans_navy)
			_add_box(st, Vector3(0.11, 0.52, 0.0), Vector3(0.13, 0.50, 0.14), jeans_navy)
			# Purple trench coat tails hanging past hips
			_add_box(st, Vector3(0.0, 0.78, 0.0), Vector3(0.38, 0.30, 0.22), coat_purple)
			# Black inner shirt with glowing cyan circuit line
			_add_box(st, Vector3(0.0, 1.15, 0.0), Vector3(0.36, 0.48, 0.22), shirt_black)
			_add_box(st, Vector3(0.0, 1.18, -0.115), Vector3(0.08, 0.32, 0.02), cyan_glow)
			# Open purple trench coat over torso + high collar & silver trim
			_add_box(st, Vector3(-0.16, 1.15, 0.0), Vector3(0.08, 0.48, 0.24), coat_purple)
			_add_box(st, Vector3(0.16, 1.15, 0.0), Vector3(0.08, 0.48, 0.24), coat_purple)
			_add_box(st, Vector3(0.0, 1.15, 0.10), Vector3(0.38, 0.48, 0.06), coat_purple)
			_add_box(st, Vector3(-0.18, 1.15, -0.11), Vector3(0.03, 0.48, 0.03), silver_trim)
			_add_box(st, Vector3(0.18, 1.15, -0.11), Vector3(0.03, 0.48, 0.03), silver_trim)
			_add_box(st, Vector3(0.0, 1.40, 0.06), Vector3(0.34, 0.10, 0.16), coat_purple)
			# Purple sleeves + grey cuffs + dark tech gloves
			_add_box(st, Vector3(-0.24, 1.18, 0.0), Vector3(0.10, 0.38, 0.10), coat_purple)
			_add_box(st, Vector3(0.24, 1.18, 0.0), Vector3(0.10, 0.38, 0.10), coat_purple)
			_add_box(st, Vector3(-0.24, 0.96, 0.0), Vector3(0.11, 0.06, 0.11), cuff_grey)
			_add_box(st, Vector3(0.24, 0.96, 0.0), Vector3(0.11, 0.06, 0.11), cuff_grey)
			_add_box(st, Vector3(-0.24, 0.86, 0.0), Vector3(0.09, 0.14, 0.09), boots_black)
			_add_box(st, Vector3(0.24, 0.86, 0.0), Vector3(0.09, 0.14, 0.09), boots_black)
			# Head + dark brown hair
			_add_box(st, Vector3(0.0, 1.54, 0.0), Vector3(0.26, 0.26, 0.26), skin)
			_add_box(st, Vector3(0.0, 1.66, 0.0), Vector3(0.28, 0.08, 0.28), hair)
			_add_box(st, Vector3(0.0, 1.56, 0.12), Vector3(0.28, 0.22, 0.06), hair)
			# Silver tech visor with pale blue lens
			_add_box(st, Vector3(0.0, 1.56, -0.12), Vector3(0.28, 0.07, 0.05), visor_frame)
			_add_box(st, Vector3(0.0, 1.56, -0.14), Vector3(0.20, 0.05, 0.02), visor_lens)

		ARCHETYPE_TEIBI:
			# Teibi Look-Alike (~1.75 m): Medium/lean build, natural human proportions.
			# Signature dark navy French beret with top nub, mustard long-sleeve polo,
			# dark charcoal-navy full-length trousers, dark brown shoes.
			var skin := Color(0.86, 0.66, 0.54)
			var hair := Color(0.17, 0.12, 0.09)
			var beret_navy := Color(0.07, 0.09, 0.20)
			var shirt_mustard := Color(0.88, 0.67, 0.18)
			var placket := Color(0.70, 0.52, 0.11)
			var trousers := Color(0.20, 0.22, 0.28)
			var belt := Color(0.11, 0.10, 0.11)
			var shoes := Color(0.16, 0.11, 0.08)

			# Dark shoes — feet at y = 0 (0.10 - 0.20/2 = 0)
			_add_box(st, Vector3(-0.12, 0.10, 0.03), Vector3(0.14, 0.20, 0.26), shoes)
			_add_box(st, Vector3(0.12, 0.10, 0.03), Vector3(0.14, 0.20, 0.26), shoes)
			# Straight charcoal-navy trousers (full length)
			_add_box(st, Vector3(-0.12, 0.48, 0.0), Vector3(0.14, 0.56, 0.15), trousers)
			_add_box(st, Vector3(0.12, 0.48, 0.0), Vector3(0.14, 0.56, 0.15), trousers)
			_add_box(st, Vector3(0.0, 0.78, 0.0), Vector3(0.40, 0.16, 0.24), trousers)
			_add_box(st, Vector3(0.0, 0.86, 0.0), Vector3(0.41, 0.06, 0.25), belt)
			# Mustard long-sleeve polo torso + collar & placket
			_add_box(st, Vector3(0.0, 1.14, 0.0), Vector3(0.40, 0.50, 0.24), shirt_mustard)
			_add_box(st, Vector3(0.0, 1.22, -0.125), Vector3(0.08, 0.22, 0.02), placket)
			_add_box(st, Vector3(0.0, 1.37, 0.0), Vector3(0.28, 0.06, 0.24), placket)
			# Long mustard sleeves (whole arm) + skin hands
			_add_box(st, Vector3(-0.26, 1.10, 0.0), Vector3(0.11, 0.48, 0.11), shirt_mustard)
			_add_box(st, Vector3(0.26, 1.10, 0.0), Vector3(0.11, 0.48, 0.11), shirt_mustard)
			_add_box(st, Vector3(-0.26, 0.80, 0.0), Vector3(0.09, 0.12, 0.09), skin)
			_add_box(st, Vector3(0.26, 0.80, 0.0), Vector3(0.09, 0.12, 0.09), skin)
			# Head & dark hair
			_add_box(st, Vector3(0.0, 1.50, 0.0), Vector3(0.28, 0.28, 0.28), skin)
			_add_box(st, Vector3(0.0, 1.52, 0.13), Vector3(0.28, 0.22, 0.04), hair)
			# Signature dark navy French beret + top nub
			_add_box(st, Vector3(0.02, 1.64, 0.0), Vector3(0.36, 0.10, 0.36), beret_navy)
			_add_box(st, Vector3(0.02, 1.70, 0.0), Vector3(0.26, 0.06, 0.26), beret_navy)
			_add_box(st, Vector3(0.02, 1.75, 0.0), Vector3(0.05, 0.06, 0.05), beret_navy)

		ARCHETYPE_PHOBOMAN:
			# Phoboman Look-Alike (~1.45 m): Non-humanoid round pho bowl sphere!
			# Giant round royal-blue body sphere, bold red dragon wrapping front,
			# brass diving helmet with glowing orange noodle porthole, stubby arms & tiny boots.
			var skin := Color(0.93, 0.74, 0.62)
			var body_blue := Color(0.14, 0.19, 0.48)
			var dragon_red := Color(0.82, 0.14, 0.14)
			var dragon_gold := Color(0.92, 0.74, 0.30)
			var helmet_gold := Color(0.82, 0.64, 0.25)
			var helmet_dark := Color(0.55, 0.41, 0.15)
			var glass := Color(0.55, 0.75, 0.82)
			var broth_orange := Color(0.95, 0.52, 0.18)
			var boots_black := Color(0.08, 0.08, 0.09)

			# Tiny black boots at bottom — feet at y = 0 (0.08 - 0.16/2 = 0)
			_add_box(st, Vector3(-0.11, 0.08, 0.0), Vector3(0.13, 0.16, 0.20), boots_black)
			_add_box(st, Vector3(0.11, 0.08, 0.0), Vector3(0.13, 0.16, 0.20), boots_black)
			# Giant round royal-blue body sphere (belly IS the body)
			_add_box(st, Vector3(0.0, 0.58, 0.0), Vector3(0.72, 0.68, 0.68), body_blue)
			_add_box(st, Vector3(0.0, 0.58, 0.0), Vector3(0.64, 0.76, 0.64), body_blue)
			# Bold red dragon wrapping front of sphere
			_add_box(st, Vector3(0.0, 0.58, -0.345), Vector3(0.48, 0.38, 0.03), dragon_red)
			_add_box(st, Vector3(0.0, 0.66, -0.355), Vector3(0.24, 0.14, 0.03), dragon_gold)
			# Short thick bare skin arms poking from upper sides
			_add_box(st, Vector3(-0.40, 0.68, 0.0), Vector3(0.16, 0.24, 0.16), skin)
			_add_box(st, Vector3(0.40, 0.68, 0.0), Vector3(0.16, 0.24, 0.16), skin)
			# Brass diving helmet sitting right on top of sphere + porthole & noodle glow
			_add_box(st, Vector3(0.0, 1.02, 0.0), Vector3(0.42, 0.10, 0.42), helmet_dark)
			_add_box(st, Vector3(0.0, 1.20, 0.0), Vector3(0.38, 0.28, 0.38), helmet_gold)
			_add_box(st, Vector3(0.0, 1.36, 0.0), Vector3(0.08, 0.08, 0.08), helmet_dark)
			_add_box(st, Vector3(0.0, 1.20, -0.195), Vector3(0.24, 0.20, 0.04), helmet_dark)
			_add_box(st, Vector3(0.0, 1.20, -0.21), Vector3(0.18, 0.14, 0.02), broth_orange)
			_add_box(st, Vector3(0.0, 1.20, -0.22), Vector3(0.18, 0.14, 0.01), glass)

	_archetype_meshes[archetype] = st.commit()
	return _archetype_meshes[archetype]

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	## Join the "crowd" group (discovery hook — citizens join NO group).
	add_to_group("crowd")
	_rng.randomize()

	# The pooled colliders. Built here so they exist for a manager driven
	# straight out of a harness, exactly like the MultiMeshes below.
	_proxies = AmbienceProxies.new()
	_proxies.build(self, CITIZEN_PROXY_POOL, CITIZEN_PROXY_HALF,
			CITIZEN_PROXY_HEIGHT, CITIZEN_PROXY_REACH)

	_crowd_max = CROWD_MAX_WEB if OS.has_feature("web") else CROWD_MAX_DESKTOP

	# Create 4 MultiMeshInstance3D child nodes (shadows off, matching fauna precedent)
	_multimesh_nodes.resize(ARCHETYPE_COUNT)
	var per_archetype := _crowd_max / ARCHETYPE_COUNT

	for k in ARCHETYPE_COUNT:
		var mm_inst := MultiMeshInstance3D.new()
		mm_inst.name = "Crowd_%s" % ARCHETYPE_NAMES[k].capitalize()
		mm_inst.material_override = _get_shared_material()
		mm_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = false
		mm.mesh = _get_archetype_mesh(k)
		mm.instance_count = per_archetype
		mm.visible_instance_count = 0
		mm_inst.multimesh = mm

		add_child(mm_inst)
		_multimesh_nodes[k] = mm_inst

	# Initialize citizen records
	_citizens.clear()
	for k in ARCHETYPE_COUNT:
		for i in per_archetype:
			_citizens.append({
				"archetype": k,
				"pos": Vector3.ZERO,
				"target": Vector3.ZERO,
				"lane_offset": LANE_OFFSETS[i % LANE_OFFSETS.size()],
				"speed": 2.0,
				"walk_phase": 0.0,
				"pause_timer": 0.0,
				"facing_yaw": 0.0,
				"heading_dir": Vector2(1.0, 0.0),
				"active": false,
				"lod_debt": 0.0,
				"lod_step": 0.0,
			})


func _process(delta: float) -> void:
	var player := _find_player()
	if player == null:
		_hide_all()
		return

	var player_pos: Vector3 = player.global_position
	# Check if player is near or inside Budapest
	if not _is_near_budapest(player_pos):
		_hide_all()
		return

	# Whose tick is it this frame? Asked ONCE per frame off the ACTIVE CAMERA
	# (never the player — the FRONT view looks backward along the hero), and
	# spent by both loops below. Empty planes (no camera) = everything visible.
	var planes: Array[Plane] = AmbienceLod.view_planes(get_viewport())

	# Open the proxy pool's candidate buffer: the nearest few citizens are picked
	# up INSIDE _update_walkers' existing loop (offer()), so the collision shares
	# 8gw.22's one pass per instance and adds no scan of its own.
	_proxies.begin(player_pos)

	# Maintain active citizens in bubble around player
	_update_crowd_spawns(delta, player_pos, planes)

	# Update movement, grid wayfinding, and animation
	_update_walkers(delta, true)

	# ...and place the handful of bodies on whatever that loop offered.
	_proxies.commit(delta, player_pos)


# ============================================================================
# CROWD LOGIC & WAYFINDING
# ============================================================================

func _find_player() -> Node3D:
	## Locate the local player through the "player" group.
	var player := get_tree().get_first_node_in_group("player")
	if player is Node3D:
		return player
	return null


func _is_near_budapest(player_pos: Vector3) -> bool:
	## True when player is inside or within 100m margin of Budapest rect.
	return PLAN_SCRIPT.rect().grow(100.0).has_point(Vector2(player_pos.x, player_pos.z))


## Slots that are open plazas, pedestrian streets, bridges, or plateaus
## where ground-level street path checks should not block walkers.
const WALKABLE_LANDMARK_IDS: Dictionary = {
	"heroes_square": true,
	"budapest_eye": true,
	"vaci_utca": true,
	"shoes_on_the_danube": true,
	"chain_bridge": true,
	"liberty_bridge": true,
	"elisabeth_bridge": true,
	"margaret_bridge": true,
	"margaret_island": true,
	"buda_castle": true,   # plateau_top_at handles plateau
	"matthias": true,      # plateau_top_at handles plateau
	"citadella": true,     # plateau_top_at handles plateau
}


static func _is_inside_solid_landmark(x: float, z: float) -> bool:
	## Checks dynamically against BudapestPlan.SLOTS using exact authored radii.
	for slot: Dictionary in PLAN_SCRIPT.SLOTS:
		var slot_id: String = slot.get("id", "")
		if WALKABLE_LANDMARK_IDS.has(slot_id):
			continue
		var spos: Vector3 = slot["pos"]
		var r: float = slot["radius"]
		var dx: float = x - spos.x
		var dz: float = z - spos.z
		if dx * dx + dz * dz < r * r:
			return true
	return false


static func is_walkable(x: float, z: float) -> bool:
	## Pure predicate: returns true if the coordinate is valid dry street ground.
	## Must be inside Budapest, outside Danube water, outside plateau massifs,
	## and outside solid landmark buildings.
	if not PLAN_SCRIPT.contains(x, z):
		return false
	if PLAN_SCRIPT.danube_wet(x, z):
		return false
	if PLAN_SCRIPT.plateau_top_at(x, z) > 0.0:
		return false
	if _is_inside_solid_landmark(x, z):
		return false
	return true


static func snap_to_grid(x: float, z: float) -> Vector2:
	## Snaps world XZ to the nearest Budapest street grid intersection.
	##
	## NO SPAWNER READS THIS ANY MORE — bead 8gw.23 took it out of
	## `_find_spawn_segment_near`, because collapsing a whole 62 m cell onto one
	## corner is half of why the crowd bunched up. It stays because it is the grid
	## origin written down once (`city_map_panel` names it as the reference for
	## its own pitch) and because `crowd_selfcheck` check 10's mutation control
	## rebuilds the retired sampler out of it. Deleting it silently guts that
	## control, so delete the control with it or leave both alone.
	var pitch: float = PLAN_SCRIPT.STREET_PITCH
	var origin_x: float = PLAN_SCRIPT.GATE.x
	var gx: float = roundf((x - origin_x) / pitch) * pitch + origin_x
	var gz: float = roundf(z / pitch) * pitch
	return Vector2(gx, gz)


func _pick_next_waypoint(current_pos: Vector3, current_heading: Vector2) -> Vector3:
	## Given a grid intersection, picks the next walkable neighbor along the grid.
	var gx: float = current_pos.x
	var gz: float = current_pos.z
	var pitch: float = PLAN_SCRIPT.STREET_PITCH

	var directions: Array[Vector2] = [
		Vector2(pitch, 0.0),
		Vector2(-pitch, 0.0),
		Vector2(0.0, pitch),
		Vector2(0.0, -pitch),
	]

	var valid_candidates: Array[Vector3] = []
	var straight_candidate := Vector3.ZERO
	var has_straight := false

	for dir: Vector2 in directions:
		var nx := gx + dir.x
		var nz := gz + dir.y
		var mx := (gx + nx) * 0.5
		var mz := (gz + nz) * 0.5
		# Both target intersection and street midpoint must be walkable
		if is_walkable(nx, nz) and is_walkable(mx, mz):
			var cand := Vector3(nx, 0.0, nz)
			valid_candidates.append(cand)
			if dir.normalized().dot(current_heading) > 0.8:
				straight_candidate = cand
				has_straight = true

	if valid_candidates.is_empty():
		# Fallback if somehow stranded: stay in place
		return current_pos

	# Prefer continuing straight (60% weight) to avoid jittery turning
	if has_straight and _rng.randf() < 0.60:
		return straight_candidate

	return valid_candidates[_rng.randi() % valid_candidates.size()]


static func _next_intersection(base: Vector3, dir: Vector2) -> Vector3:
	## The next 62 m grid intersection from `base` in `dir` — the walk target for
	## a citizen standing PART WAY along a street rather than on a corner.
	var pitch: float = PLAN_SCRIPT.STREET_PITCH
	var origin_x: float = PLAN_SCRIPT.GATE.x
	if absf(dir.x) > 0.5:
		var k: float = (base.x - origin_x) / pitch
		# The epsilon is what stops a citizen spawned exactly ON an intersection
		# from targeting the intersection it is already standing on.
		var nk: float = ceilf(k + 0.001) if dir.x > 0.0 else floorf(k - 0.001)
		return Vector3(origin_x + nk * pitch, 0.0, base.z)
	var m: float = base.z / pitch
	var nm: float = ceilf(m + 0.001) if dir.y > 0.0 else floorf(m - 0.001)
	return Vector3(base.x, 0.0, nm * pitch)


static func walks_an_avenue(base: Vector3, heading: Vector2) -> bool:
	## Is the street line this citizen is walking ALONG one of the avenues that
	## carry traffic? (Not "is this point on a carriageway" — that is
	## traffic_manager's question and includes every avenue a citizen CROSSES.)
	## The line is the coordinate that does NOT change as it walks.
	var ave_pitch: float = PLAN_SCRIPT.STREET_PITCH * float(PLAN_SCRIPT.CITY_AVENUE_EVERY)
	if absf(heading.x) > absf(heading.y):
		return absf(base.z - roundf(base.z / ave_pitch) * ave_pitch) < 1.0
	var origin_x: float = PLAN_SCRIPT.GATE.x
	var k := roundf((base.x - origin_x) / ave_pitch)
	return absf(base.x - (origin_x + k * ave_pitch)) < 1.0


func _pick_lane(base: Vector3, heading: Vector2) -> float:
	## The lateral offset for a walker on this street line, asked whenever the
	## heading CHANGES — a lane picked at spawn and never revisited put a citizen
	## who turned onto an avenue straight into the traffic. It must NOT be asked
	## when the heading is unchanged: a fresh draw is a sign flip half the time,
	## and on an avenue that is a 17.2 m sideways jump across both car lanes in
	## one frame (6.4 m on an ordinary street). The caller owns that condition.
	##
	## ponytail: A 90-DEGREE TURN STILL JUMPS, by `sqrt(2) * lane` (12.2 m on the
	## pavement, 4.5 m on the ±3.2 lanes it has always cost). A lane is an offset
	## along the heading's perpendicular, so turning rotates it onto the other
	## axis — the offset PATHS of two perpendicular streets meet at a corner the
	## walker never visits. Closing it means walking to that corner, which needs
	## the NEXT lane before the next street is picked: a two-leg waypoint model,
	## its own bead. `crowd_selfcheck` check 12 bounds the corner off this
	## constant so it cannot grow quietly in the meantime.
	var lane: float
	if walks_an_avenue(base, heading):
		lane = PAVEMENT_LANE_OFFSET if _rng.randf() < 0.5 else -PAVEMENT_LANE_OFFSET
	else:
		lane = LANE_OFFSETS[_rng.randi() % LANE_OFFSETS.size()]
	var lat_dir := Vector3(-heading.y, 0.0, heading.x)
	if is_walkable((base + lat_dir * lane).x, (base + lat_dir * lane).z):
		return lane
	# THE OTHER PAVEMENT, before giving up. The city's WEST edge is the gate
	# avenue itself (BUDAPEST_MIN.x == GATE.x), so for a north/south walker there
	# the western pavement is outside the rect and half of all draws used to fall
	# through to 0.0 — which parks the citizen on the centreline of the busiest
	# road in the city, at the one place every player enters it. Both offsets are
	# symmetric (LANE_OFFSETS as much as the pavement), so the mirror is always a
	# legitimate lane and not a second rule.
	var mirrored: Vector3 = base - lat_dir * lane
	if is_walkable(mirrored.x, mirrored.z):
		return -lane
	# Neither side fits. 0.0 is the centreline, which is the one strip of an
	# avenue no car lane covers (they sit at ±LANE_OFFSET), so it is a safe
	# degrade rather than a good lane — the car still brakes for whoever stands
	# there. With the mirror above there is no shipped street that reaches here.
	return 0.0


func _too_close_to_walker(world_pos: Vector3) -> bool:
	## MIN_WALKER_SPACING as a spawn clearance — traffic_manager's
	## `_is_occupied_near` precedent, per-axis reject first so the whole test is
	## a couple of compares for the citizens that cannot possibly be the answer.
	for other: Dictionary in _citizens:
		if not other["active"]:
			continue
		var obase: Vector3 = other["pos"]
		if absf(obase.x - world_pos.x) > MIN_WALKER_SPACING + PAVEMENT_LANE_OFFSET \
				or absf(obase.z - world_pos.z) > MIN_WALKER_SPACING + PAVEMENT_LANE_OFFSET:
			continue
		var ow: Vector3 = _citizen_world_pos(other)
		if Vector2(ow.x - world_pos.x, ow.z - world_pos.z).length() < MIN_WALKER_SPACING:
			return true
	return false


func _find_spawn_segment_near(player_pos: Vector3, min_dist: float = SPAWN_MIN_DIST) -> Dictionary:
	## A point drawn UNIFORMLY OVER THE STREET NETWORK inside the bubble.
	##
	## THE BUG THIS REPLACES (bead 8gw.23, owner: "why are they all in one
	## space"). The old sampler did three things, each of which piles citizens up:
	##   * `randf_range(SPAWN_MIN_DIST, SPAWN_RADIUS)` is uniform in *r*, and a
	##     disc's area grows as r² — so the middle of the bubble was over-weighted
	##     by 1/r.
	##   * it then SNAPPED to the nearest INTERSECTION, collapsing every point of
	##     a 62 x 62 m cell onto one corner.
	##   * and when 16 draws failed it fell back to the PLAYER'S OWN snapped
	##     intersection — so every rejected draw landed on a single spot. That
	##     fallback is gone; a frame with nowhere to stand simply spawns nobody
	##     (the caller's `spawn_exhausted` flag already handles that).
	##
	## THE DRAW NEVER TOUCHES A DISC, which is the whole trick: it picks a STREET
	## LINE uniformly among the lines that cross the bubble, then a point uniformly
	## along that line's CHORD inside it. Every line is equally likely, so the crowd
	## spreads over the grid rather than over the disc's middle, and the
	## along-street coordinate stays continuous — which is what a street is.
	## Area-weighting the disc and snapping ONE axis was the first fix and it was
	## measured and dropped: a snapped-disc sample is not uniform along a line, its
	## density follows the chord width, which piles points up near the centre again.
	##
	## The measurement is `crowd_selfcheck` check 10, and it is RADIAL rather than a
	## cell histogram (a 62 m cell grid is drawn on the very lines the walkers stand
	## on, so the peak cell count is mostly noise). Share of an arrival landing
	## inside half the spawn radius — a quarter of the area, so uniform is 25% —
	## over 1,200 arrivals at four city spots: 36% before, 21% now.
	var pitch: float = PLAN_SCRIPT.STREET_PITCH
	var origin_x: float = PLAN_SCRIPT.GATE.x
	for attempt in 24:
		var base: Vector3
		var dir_choice: Vector2
		if _rng.randf() < 0.5:
			# A line of constant Z, walked along X.
			var m_lo := ceili((player_pos.z - SPAWN_RADIUS) / pitch)
			var m_hi := floori((player_pos.z + SPAWN_RADIUS) / pitch)
			if m_hi < m_lo:
				continue
			var line_z := float(m_lo + _rng.randi() % (m_hi - m_lo + 1)) * pitch
			var half := sqrt(maxf(0.0, SPAWN_RADIUS * SPAWN_RADIUS
					- (line_z - player_pos.z) * (line_z - player_pos.z)))
			base = Vector3(player_pos.x + _rng.randf_range(-half, half), 0.0, line_z)
			dir_choice = Vector2(1.0 if _rng.randf() < 0.5 else -1.0, 0.0)
		else:
			# A line of constant X, walked along Z.
			var k_lo := ceili((player_pos.x - SPAWN_RADIUS - origin_x) / pitch)
			var k_hi := floori((player_pos.x + SPAWN_RADIUS - origin_x) / pitch)
			if k_hi < k_lo:
				continue
			var line_x := origin_x + float(k_lo + _rng.randi() % (k_hi - k_lo + 1)) * pitch
			var half := sqrt(maxf(0.0, SPAWN_RADIUS * SPAWN_RADIUS
					- (line_x - player_pos.x) * (line_x - player_pos.x)))
			base = Vector3(line_x, 0.0, player_pos.z + _rng.randf_range(-half, half))
			dir_choice = Vector2(0.0, 1.0 if _rng.randf() < 0.5 else -1.0)

		# The near hole: never place a walker on top of the hero.
		if Vector2(base.x - player_pos.x, base.z - player_pos.z).length() < min_dist:
			continue

		var target := _next_intersection(base, dir_choice)
		if not is_walkable(base.x, base.z) or not is_walkable(target.x, target.z):
			continue
		# THE LANE IS CHOSEN HERE, not in `_assign_citizen_from_segment`, because
		# the spacing test below has to see the position the citizen will really
		# STAND at. Two candidates on the same street can be 6 m apart on the
		# centreline, pass a test made against `base`, and then draw the same lane
		# and land on top of each other — MIN_WALKER_SPACING measured against a
		# point nobody occupies.
		var lane := _pick_lane(base, dir_choice)
		var lat_dir := Vector3(-dir_choice.y, 0.0, dir_choice.x)
		if _too_close_to_walker(base + lat_dir * lane):
			continue
		return {"start": base, "end": target, "dir": dir_choice, "lane": lane}

	return {}


func _assign_citizen_from_segment(citizen: Dictionary, seg: Dictionary) -> void:
	## The single home of the spawn/recycle assignment (it was copy-pasted twice,
	## and the lane rule now has to be applied in both).
	var start_pt: Vector3 = seg["start"]
	var end_pt: Vector3 = seg["end"]
	# `start` is ALREADY the uniform point along the street — the old sampler
	# lerped because its start was an intersection, and lerping now would pull
	# every draw back toward the corners this sampler exists to get away from.
	citizen["pos"] = start_pt
	citizen["target"] = end_pt
	var heading: Vector2 = (seg["dir"] as Vector2).normalized()
	citizen["heading_dir"] = heading
	citizen["facing_yaw"] = atan2(-heading.x, -heading.y)
	# The lane the sampler already cleared against every other walker — re-drawing
	# it here would throw that clearance away. `_pick_lane` is the fallback for a
	# caller that built a segment by hand (a harness, a probe).
	citizen["lane_offset"] = float(seg["lane"]) if seg.has("lane") \
			else _pick_lane(start_pt, heading)
	citizen["speed"] = _rng.randf_range(WALK_SPEED_MIN, WALK_SPEED_MAX)
	citizen["walk_phase"] = _rng.randf_range(0.0, TAU)
	citizen["pause_timer"] = 0.0
	citizen["lod_debt"] = 0.0
	citizen["active"] = true


func _update_crowd_spawns(delta: float, player_pos: Vector3, planes: Array[Plane] = []) -> void:
	## Activates or recycles citizens in a natural, distributed arrangement around the player.
	##
	## THIS IS ALSO WHERE THE COARSE TICK IS DECIDED, once per citizen per frame,
	## and written to `lod_step` for `_update_walkers` to spend. Deciding it here
	## rather than there is what makes the recycle test (walkability, the despawn
	## radius) happen on exactly the ticks a citizen moves on — a citizen that is
	## not stepping cannot have walked anywhere that needs re-checking, and the
	## dominant cost of this loop is `is_walkable`, not the movement.
	## `planes` empty (no camera) => everything visible => byte-for-byte today.
	# EVERY citizen must get its decision, which is why the "no walkable street
	# near the player" case sets a flag and carries on instead of breaking out of
	# the loop as it used to: a citizen the loop never reached would keep LAST
	# frame's `lod_step` and spend it a second time. The retry storm that `break`
	# existed to prevent is prevented by the flag — no further spawn searches.
	var spawn_exhausted: bool = false
	for citizen: Dictionary in _citizens:
		if not citizen["active"]:
			citizen["lod_step"] = delta  # nowhere to stand yet: never coarse-ticked
			if spawn_exhausted:
				continue
			var seg := _find_spawn_segment_near(player_pos)
			if seg.is_empty():
				# No walkable street near the player: stop searching this frame.
				spawn_exhausted = true
				continue
			_assign_citizen_from_segment(citizen, seg)
		else:
			var visible: bool = AmbienceLod.is_visible_at(planes, _citizen_world_pos(citizen))
			citizen["lod_step"] = AmbienceLod.step_delta(citizen, delta, visible)
			if float(citizen["lod_step"]) <= 0.0:
				continue  # not this citizen's tick — it moves later, by the banked time
			# Check if citizen has drifted beyond DESPAWN_RADIUS or out of walkable zone
			var cpos: Vector3 = citizen["pos"]
			var flat_dist := Vector2(cpos.x - player_pos.x, cpos.z - player_pos.z).length()
			if flat_dist > DESPAWN_RADIUS or not is_walkable(cpos.x, cpos.z):
				# Recycle to the FAR side of the bubble, never under the hero's
				# nose — see RECYCLE_MIN_DIST.
				var seg := _find_spawn_segment_near(player_pos, RECYCLE_MIN_DIST)
				if not seg.is_empty():
					_assign_citizen_from_segment(citizen, seg)
				else:
					citizen["active"] = false


func _update_walkers(delta: float, lod_gated: bool = false) -> void:
	## Advances citizen movement, applies procedural walk bob/sway, and pushes
	## transforms in bulk to the four MultiMeshes via multimesh.buffer.
	##
	## `lod_gated` false means every citizen steps by `delta` — which is what a
	## harness driving this function directly wants, and byte-for-byte what a
	## camera-less scene produces anyway. `_process` passes true and each citizen
	## spends the `lod_step` decided in `_update_crowd_spawns`: 0.0 means it is
	## not its tick, so it is DRAWN WHERE IT STANDS and moves on its next one.
	## Nothing is ever skipped out of the buffer — the crowd is never a hole.
	# THE KERB RULE's seam (bead 8gw.23), resolved ONCE per call through the group
	# — never a preload, which between these two managers would be a cycle, and
	# never per citizen. Absent (a harness, a standalone scene) => nobody holds,
	# which is byte-for-byte the behaviour before this bead.
	var traffic: Node = get_tree().get_first_node_in_group("traffic") if is_inside_tree() else null
	if traffic != null and not traffic.has_method("blocks_crossing"):
		traffic = null

	var counts := [0, 0, 0, 0]
	var buffers: Array[PackedFloat32Array] = []
	for k in ARCHETYPE_COUNT:
		var count: int = _multimesh_nodes[k].multimesh.instance_count
		var buf := PackedFloat32Array()
		buf.resize(count * 12)
		buffers.append(buf)

	for i in _citizens.size():
		var citizen: Dictionary = _citizens[i]
		if not citizen["active"]:
			continue

		var k: int = citizen["archetype"]
		var pos: Vector3 = citizen["pos"]
		var target: Vector3 = citizen["target"]
		var is_moving := false

		# The coarse tick: the REAL elapsed time since this citizen last stepped,
		# not one frame's worth — that is what keeps an unseen street walking.
		var step_dt: float = float(citizen["lod_step"]) if lod_gated else delta

		if step_dt <= 0.0:
			pass  # not its tick; fall through to the draw with its current state
		elif citizen["pause_timer"] > 0.0:
			citizen["pause_timer"] -= step_dt
		else:
			var step: float = citizen["speed"] * step_dt
			var to_target := target - pos
			var dist := to_target.length()

			if dist <= step or dist < 0.05:
				pos = target
				citizen["walk_phase"] += dist * STRIDE_FREQUENCY
				# Reached crossing: chance to pause
				if _rng.randf() < 0.25:
					citizen["pause_timer"] = _rng.randf_range(0.6, 2.0)
				# Pick next intersection
				var was_heading: Vector2 = citizen["heading_dir"]
				var next_target := _pick_next_waypoint(pos, was_heading)
				citizen["target"] = next_target
				var delta_x: float = next_target.x - pos.x
				var delta_z: float = next_target.z - pos.z
				if Vector2(delta_x, delta_z).length_squared() > 0.01:
					citizen["heading_dir"] = Vector2(delta_x, delta_z).normalized()
				# THE LANE IS RE-ASKED ON A TURN AND ONLY ON A TURN. A citizen that
				# walked off a side street onto an avenue keeping its old ±3.2 m
				# lane would be standing in the traffic (see PAVEMENT_LANE_OFFSET),
				# but `_pick_next_waypoint` carries straight on 60% of the time and
				# a fresh draw there flips the SIGN half of those — a 17.2 m
				# sideways teleport across both car lanes, once a block, for a
				# citizen that never turned.
				var new_h: Vector2 = citizen["heading_dir"]
				if new_h.is_equal_approx(-was_heading):
					# A U-TURN walks the SAME street line, so the same pavement is
					# still the right pavement — but `perp` turned round with the
					# heading, so the stored value has to turn with it or the
					# citizen crosses the road to stand on the other side of it.
					citizen["lane_offset"] = -float(citizen["lane_offset"])
				elif not new_h.is_equal_approx(was_heading):
					citizen["lane_offset"] = _pick_lane(pos, new_h)
			else:
				var move_dir := to_target / dist
				var next_pos := pos + move_dir * step
				# THE KERB RULE: a citizen does not STEP ONTO a carriageway while a
				# car is within its braking distance of the spot. It is asked of
				# the step, not of the citizen — one already in the road keeps
				# going and the car brakes for IT instead (traffic_manager's
				# `_distance_to_citizen_ahead`), because freezing somebody
				# mid-crossing is the one place to be run over.
				var lane_dir := Vector3(-float(citizen["heading_dir"].y), 0.0,
						float(citizen["heading_dir"].x)) * float(citizen["lane_offset"])
				if traffic != null and traffic.blocks_crossing(
						pos + lane_dir, next_pos + lane_dir, citizen["heading_dir"]):
					pass  # wait at the kerb; asked again next tick
				else:
					pos = next_pos
					citizen["walk_phase"] += step * STRIDE_FREQUENCY
					is_moving = true

					# Smoothly rotate facing yaw towards current heading
					var target_yaw := atan2(-move_dir.x, -move_dir.z)
					citizen["facing_yaw"] = rotate_toward(citizen["facing_yaw"], target_yaw, 5.0 * step_dt)

		citizen["pos"] = pos

		# Calculate lateral offset perpendicular to movement heading
		var world_pos := _citizen_world_pos(citizen)

		# Calculate walking animation procedural bob and sway
		var phase: float = citizen["walk_phase"]
		var bob_y: float = absf(sin(phase * 2.0)) * WALK_BOB_AMOUNT if is_moving else 0.0
		var sway_z: float = sin(phase) * WALK_SWAY_AMOUNT if is_moving else 0.0
		var pitch_x: float = sin(phase * 2.0) * WALK_PITCH_AMOUNT if is_moving else 0.0

		var basis := Basis().rotated(Vector3.UP, citizen["facing_yaw"])
		if is_moving:
			basis = basis.rotated(Vector3(0, 0, 1), sway_z).rotated(Vector3(1, 0, 0), pitch_x)

		var t := Transform3D(basis, Vector3(world_pos.x, bob_y, world_pos.z))

		# The proxy pool rides THIS loop — the world position and the facing are
		# already in hand, so being solid costs a box reject per citizen.
		_proxies.offer(Vector3(world_pos.x, 0.0, world_pos.z), float(citizen["facing_yaw"]))

		var idx: int = counts[k]
		var max_inst: int = _multimesh_nodes[k].multimesh.instance_count
		if idx < max_inst:
			var buf: PackedFloat32Array = buffers[k]
			var base := idx * 12
			buf[base + 0] = t.basis.x.x
			buf[base + 1] = t.basis.y.x
			buf[base + 2] = t.basis.z.x
			buf[base + 3] = t.origin.x

			buf[base + 4] = t.basis.x.y
			buf[base + 5] = t.basis.y.y
			buf[base + 6] = t.basis.z.y
			buf[base + 7] = t.origin.y

			buf[base + 8] = t.basis.x.z
			buf[base + 9] = t.basis.y.z
			buf[base + 10] = t.basis.z.z
			buf[base + 11] = t.origin.z
			counts[k] += 1

	# Push buffers and update visible counts in bulk for all four MultiMeshes
	for k in ARCHETYPE_COUNT:
		var mm: MultiMesh = _multimesh_nodes[k].multimesh
		mm.buffer = buffers[k]
		mm.visible_instance_count = counts[k]


static func _citizen_world_pos(citizen: Dictionary) -> Vector3:
	## World pos of one walker (base pos + lateral lane offset).
	var base: Vector3 = citizen["pos"]
	var h: Vector2 = citizen["heading_dir"]
	return base + Vector3(-h.y, 0.0, h.x) * float(citizen["lane_offset"])


func blocking_citizen_distance(from: Vector3, heading: Vector2,
		max_fwd: float, lat_tol: float) -> float:
	## THE TRAFFIC'S SEAM (bead 8gw.23): how far ahead of `from` along `heading`
	## the nearest citizen stands, or INF. traffic_manager feeds this into the
	## SHIPPED yield/brake path exactly as it feeds the hero's distance in, so a
	## citizen on the carriageway is braked for rather than driven through.
	##
	## Like nearest_citizen_to this is a pure read of the walker array — no scene
	## query, no group, no body. The per-axis reject is QUEUE_SCAN_RANGE's
	## precedent and is strictly conservative: a citizen that can be the answer is
	## within `max_fwd` along one axis and `lat_tol` across, both bounded by
	## `max_fwd`, plus one lane offset of slack between base and world position.
	var best := INF
	var reach: float = max_fwd + PAVEMENT_LANE_OFFSET
	for citizen: Dictionary in _citizens:
		if not citizen["active"]:
			continue
		var base: Vector3 = citizen["pos"]
		if absf(base.x - from.x) > reach or absf(base.z - from.z) > reach:
			continue
		var wpos: Vector3 = _citizen_world_pos(citizen)
		var to_c := Vector2(wpos.x - from.x, wpos.z - from.z)
		var fwd := to_c.dot(heading)
		if fwd <= 0.0 or fwd >= max_fwd:
			continue
		if absf(to_c.dot(Vector2(-heading.y, heading.x))) <= lat_tol and fwd < best:
			best = fwd
	return best


func nearest_citizen_to(pos: Vector3, max_dist: float = 40.0) -> Variant:
	## Nearest active citizen to `pos` within `max_dist`, or null.
	## Walks the manager's own walker array — citizens are MultiMesh instances
	## in no group with no collision, so this is not a scene query and never
	## gives them a body or group. Pure read of runtime state.
	var best: Variant = null
	var best_d2 := INF
	var max_d2 := max_dist * max_dist
	for citizen: Dictionary in _citizens:
		if not citizen["active"]:
			continue
		var wpos: Vector3 = _citizen_world_pos(citizen)
		var d2 := Vector2(wpos.x - pos.x, wpos.z - pos.z).length_squared()
		if d2 <= max_d2 and d2 < best_d2:
			best_d2 = d2
			best = wpos
	return best


func _hide_all() -> void:
	## Hides all citizens when outside Budapest — and with them the colliders,
	## or a hero leaving the city would keep bumping into ghosts.
	if _proxies != null:
		_proxies.sleep()
	for k in ARCHETYPE_COUNT:
		if k < _multimesh_nodes.size() and _multimesh_nodes[k] != null:
			_multimesh_nodes[k].multimesh.visible_instance_count = 0
	for citizen: Dictionary in _citizens:
		citizen["active"] = false
