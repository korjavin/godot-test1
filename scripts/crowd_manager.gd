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
##   * Story only, no mechanics: hunters are NOT confused by crowds in this bead.
##   * Budget: hard CROWD_MAX (60 on web, 120 on desktop) rendered via FOUR
##     MultiMeshInstance3D nodes (one per hero archetype: Windman, Primm, Teibi,
##     Phoboman), costing exactly 4 draw calls for the entire crowd.
##   * Shared static resources: one shared BoxMesh-derived composite mesh per
##     archetype with baked vertex colors, and ONE shared StandardMaterial3D
##     across all archetypes (never duplicate() per citizen).
##   * Waypoint walk: citizens follow the 62 m street grid of Budapest, pausing
##     at crossings, never walking into the Danube river or the plateau cliffs.
##   * Feet rest at y = 0 by construction. Spawning occurs in a bubble around
##     the local player inside BudapestPlan.rect(), recycling when out of range.

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
const SPAWN_MIN_DIST: float = 20.0

## Walking speeds (m/s) — a natural pedestrian pace.
const WALK_SPEED_MIN: float = 1.8
const WALK_SPEED_MAX: float = 2.8

## Stride animation parameters: radians of phase per metre travelled.
const STRIDE_FREQUENCY: float = 4.2
const WALK_BOB_AMOUNT: float = 0.045
const WALK_SWAY_AMOUNT: float = 0.035
const WALK_PITCH_AMOUNT: float = 0.015

## Street grid step (matches BudapestPlan.STREET_PITCH).
const GRID_PITCH: float = 62.0
const GRID_ORIGIN_X: float = 1600.0
const GRID_ORIGIN_Z: float = 0.0

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
##   pos: Vector3 (world position, y = 0)
##   target: Vector3 (current target waypoint, y = 0)
##   speed: float (walking speed in m/s)
##   walk_phase: float (accumulated stride distance)
##   pause_timer: float (time remaining to wait at intersection)
##   facing_yaw: float (current facing angle in radians)
##   heading_dir: Vector2 (current direction vector on XZ)
##   active: bool (whether currently spawned and active)
var _citizens: Array[Dictionary] = []

## Four MultiMeshInstance3D child nodes (one per archetype).
var _multimesh_nodes: Array[MultiMeshInstance3D] = []

## Reusable Budapest plan reference (pure static calls).
const PLAN_SCRIPT := preload("res://scripts/budapest_plan.gd")

# ============================================================================
# SHARED RESOURCES (static — one per PROCESS, not per citizen/manager)
# ============================================================================

static var _shared_material: StandardMaterial3D = null
static var _archetype_meshes: Array = [null, null, null, null]


static func _get_shared_material() -> StandardMaterial3D:
	## The ONE standard material with vertex colors enabled, shared by all
	## four crowd MultiMeshes across the entire session.
	if _shared_material == null:
		_shared_material = StandardMaterial3D.new()
		_shared_material.vertex_color_use_as_albedo = true
		_shared_material.roughness = 0.85
		_shared_material.cull_mode = BaseMaterial3D.CULL_BACK
	return _shared_material


static func _add_box(st: SurfaceTool, center: Vector3, size: Vector3, col: Color) -> void:
	## Adds a 6-sided box with normals and vertex color to a SurfaceTool.
	var h := size * 0.5
	var min_p := center - h
	var max_p := center + h

	# 1. Front (+Z)
	st.set_normal(Vector3(0, 0, 1))
	st.set_color(col)
	st.add_vertex(Vector3(min_p.x, min_p.y, max_p.z))
	st.add_vertex(Vector3(max_p.x, min_p.y, max_p.z))
	st.add_vertex(Vector3(max_p.x, max_p.y, max_p.z))
	st.add_vertex(Vector3(min_p.x, min_p.y, max_p.z))
	st.add_vertex(Vector3(max_p.x, max_p.y, max_p.z))
	st.add_vertex(Vector3(min_p.x, max_p.y, max_p.z))

	# 2. Back (-Z)
	st.set_normal(Vector3(0, 0, -1))
	st.set_color(col)
	st.add_vertex(Vector3(max_p.x, min_p.y, min_p.z))
	st.add_vertex(Vector3(min_p.x, min_p.y, min_p.z))
	st.add_vertex(Vector3(min_p.x, max_p.y, min_p.z))
	st.add_vertex(Vector3(max_p.x, min_p.y, min_p.z))
	st.add_vertex(Vector3(min_p.x, max_p.y, min_p.z))
	st.add_vertex(Vector3(max_p.x, min_p.y, min_p.z))

	# 3. Left (-X)
	st.set_normal(Vector3(-1, 0, 0))
	st.set_color(col)
	st.add_vertex(Vector3(min_p.x, min_p.y, min_p.z))
	st.add_vertex(Vector3(min_p.x, min_p.y, max_p.z))
	st.add_vertex(Vector3(min_p.x, max_p.y, max_p.z))
	st.add_vertex(Vector3(min_p.x, min_p.y, min_p.z))
	st.add_vertex(Vector3(min_p.x, max_p.y, max_p.z))
	st.add_vertex(Vector3(min_p.x, min_p.y, max_p.z))

	# 4. Right (+X)
	st.set_normal(Vector3(1, 0, 0))
	st.set_color(col)
	st.add_vertex(Vector3(max_p.x, min_p.y, min_p.z))
	st.add_vertex(Vector3(max_p.x, min_p.y, max_p.z))
	st.add_vertex(Vector3(max_p.x, max_p.y, max_p.z))
	st.add_vertex(Vector3(max_p.x, min_p.y, min_p.z))
	st.add_vertex(Vector3(max_p.x, max_p.y, max_p.z))
	st.add_vertex(Vector3(max_p.x, min_p.y, min_p.z))

	# 5. Top (+Y)
	st.set_normal(Vector3(0, 1, 0))
	st.set_color(col)
	st.add_vertex(Vector3(min_p.x, max_p.y, min_p.z))
	st.add_vertex(Vector3(max_p.x, max_p.y, min_p.z))
	st.add_vertex(Vector3(max_p.x, max_p.y, max_p.z))
	st.add_vertex(Vector3(min_p.x, max_p.y, min_p.z))
	st.add_vertex(Vector3(max_p.x, max_p.y, max_p.z))
	st.add_vertex(Vector3(min_p.x, max_p.y, max_p.z))

	# 6. Bottom (-Y)
	st.set_normal(Vector3(0, -1, 0))
	st.set_color(col)
	st.add_vertex(Vector3(min_p.x, min_p.y, min_p.z))
	st.add_vertex(Vector3(max_p.x, min_p.y, min_p.z))
	st.add_vertex(Vector3(max_p.x, min_p.y, max_p.z))
	st.add_vertex(Vector3(min_p.x, min_p.y, min_p.z))
	st.add_vertex(Vector3(max_p.x, min_p.y, max_p.z))
	st.add_vertex(Vector3(min_p.x, min_p.y, max_p.z))


static func _get_archetype_mesh(archetype: int) -> ArrayMesh:
	## Lazy getter for the composite Mesh of a given hero archetype.
	## Built once per archetype using SurfaceTool and shared across all instances.
	if _archetype_meshes[archetype] != null:
		return _archetype_meshes[archetype]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	match archetype:
		ARCHETYPE_WINDMAN:
			# Windman Look-Alike: Athletic build, blue tunic, headband, fan in hand
			var skin := Color(0.88, 0.74, 0.60)
			var shirt := Color(0.24, 0.44, 0.82)
			var headband_blue := Color(0.35, 0.55, 0.90)
			var headband_red := Color(0.82, 0.25, 0.25)
			var shorts := Color(0.38, 0.28, 0.20)
			var boots := Color(0.12, 0.12, 0.14)
			var fan := Color(0.40, 0.30, 0.18)

			# Boots (left & right)
			_add_box(st, Vector3(-0.15, 0.15, 0.03), Vector3(0.18, 0.30, 0.30), boots)
			_add_box(st, Vector3(0.15, 0.15, 0.03), Vector3(0.18, 0.30, 0.30), boots)
			# Legs
			_add_box(st, Vector3(-0.15, 0.50, 0.0), Vector3(0.15, 0.45, 0.15), shorts)
			_add_box(st, Vector3(0.15, 0.50, 0.0), Vector3(0.15, 0.45, 0.15), shorts)
			# Shorts / Hips
			_add_box(st, Vector3(0.0, 0.80, 0.0), Vector3(0.42, 0.25, 0.28), shorts)
			# Torso (blue shirt)
			_add_box(st, Vector3(0.0, 1.15, 0.0), Vector3(0.42, 0.50, 0.26), shirt)
			# Arms
			_add_box(st, Vector3(-0.28, 1.15, 0.0), Vector3(0.12, 0.45, 0.12), shirt)
			_add_box(st, Vector3(0.28, 1.15, 0.0), Vector3(0.12, 0.45, 0.12), shirt)
			# Hands
			_add_box(st, Vector3(-0.28, 0.85, 0.0), Vector3(0.10, 0.14, 0.10), skin)
			_add_box(st, Vector3(0.28, 0.85, 0.0), Vector3(0.10, 0.14, 0.10), skin)
			# Fan in right hand
			_add_box(st, Vector3(0.35, 0.88, -0.10), Vector3(0.04, 0.28, 0.16), fan)
			# Head
			_add_box(st, Vector3(0.0, 1.58, 0.0), Vector3(0.32, 0.32, 0.32), skin)
			# Headband (upper blue + lower red)
			_add_box(st, Vector3(0.0, 1.64, 0.0), Vector3(0.34, 0.07, 0.34), headband_blue)
			_add_box(st, Vector3(0.0, 1.57, 0.0), Vector3(0.34, 0.05, 0.34), headband_red)

		ARCHETYPE_PRIMM:
			# Primm Look-Alike: Slender, violet/purple tunic, twin-tails hair buns
			var skin := Color(0.92, 0.78, 0.65)
			var hair_violet := Color(0.62, 0.38, 0.88)
			var dress_violet := Color(0.55, 0.32, 0.80)
			var trim_lilac := Color(0.78, 0.68, 0.88)
			var stockings := Color(0.35, 0.22, 0.45)
			var boots := Color(0.20, 0.15, 0.25)

			# Boots
			_add_box(st, Vector3(-0.10, 0.15, 0.03), Vector3(0.14, 0.30, 0.26), boots)
			_add_box(st, Vector3(0.10, 0.15, 0.03), Vector3(0.14, 0.30, 0.26), boots)
			# Legs / Stockings
			_add_box(st, Vector3(-0.10, 0.52, 0.0), Vector3(0.12, 0.48, 0.12), stockings)
			_add_box(st, Vector3(0.10, 0.52, 0.0), Vector3(0.12, 0.48, 0.12), stockings)
			# Skirt / Hips
			_add_box(st, Vector3(0.0, 0.82, 0.0), Vector3(0.36, 0.22, 0.26), dress_violet)
			# Torso
			_add_box(st, Vector3(0.0, 1.12, 0.0), Vector3(0.34, 0.42, 0.22), dress_violet)
			_add_box(st, Vector3(0.0, 1.20, 0.0), Vector3(0.35, 0.14, 0.23), trim_lilac)
			# Arms
			_add_box(st, Vector3(-0.24, 1.12, 0.0), Vector3(0.10, 0.42, 0.10), dress_violet)
			_add_box(st, Vector3(0.24, 1.12, 0.0), Vector3(0.10, 0.42, 0.10), dress_violet)
			_add_box(st, Vector3(-0.24, 0.84, 0.0), Vector3(0.08, 0.12, 0.08), skin)
			_add_box(st, Vector3(0.24, 0.84, 0.0), Vector3(0.08, 0.12, 0.08), skin)
			# Head
			_add_box(st, Vector3(0.0, 1.50, 0.0), Vector3(0.28, 0.28, 0.28), skin)
			# Twin-tails / Hair Buns
			_add_box(st, Vector3(-0.18, 1.62, -0.04), Vector3(0.12, 0.22, 0.12), hair_violet)
			_add_box(st, Vector3(0.18, 1.62, -0.04), Vector3(0.12, 0.22, 0.12), hair_violet)
			_add_box(st, Vector3(0.0, 1.60, 0.06), Vector3(0.26, 0.14, 0.18), hair_violet)

		ARCHETYPE_TEIBI:
			# Teibi Look-Alike: Compact stout build, warm amber/orange helmet, backpack
			var skin := Color(0.90, 0.74, 0.60)
			var helmet_orange := Color(0.95, 0.60, 0.18)
			var overalls := Color(0.85, 0.50, 0.14)
			var backpack := Color(0.48, 0.32, 0.18)
			var legs_brown := Color(0.42, 0.30, 0.18)
			var boots := Color(0.18, 0.14, 0.12)

			# Boots
			_add_box(st, Vector3(-0.12, 0.12, 0.03), Vector3(0.16, 0.24, 0.26), boots)
			_add_box(st, Vector3(0.12, 0.12, 0.03), Vector3(0.16, 0.24, 0.26), boots)
			# Legs
			_add_box(st, Vector3(-0.12, 0.38, 0.0), Vector3(0.14, 0.32, 0.14), legs_brown)
			_add_box(st, Vector3(0.12, 0.38, 0.0), Vector3(0.14, 0.32, 0.14), legs_brown)
			# Stout Torso / Overalls
			_add_box(st, Vector3(0.0, 0.78, 0.0), Vector3(0.42, 0.48, 0.32), overalls)
			# Backpack
			_add_box(st, Vector3(0.0, 0.82, 0.20), Vector3(0.34, 0.36, 0.14), backpack)
			# Arms
			_add_box(st, Vector3(-0.26, 0.78, 0.0), Vector3(0.11, 0.36, 0.11), overalls)
			_add_box(st, Vector3(0.26, 0.78, 0.0), Vector3(0.11, 0.36, 0.11), overalls)
			_add_box(st, Vector3(-0.26, 0.54, 0.0), Vector3(0.09, 0.12, 0.09), skin)
			_add_box(st, Vector3(0.26, 0.54, 0.0), Vector3(0.09, 0.12, 0.09), skin)
			# Head
			_add_box(st, Vector3(0.0, 1.18, 0.0), Vector3(0.32, 0.30, 0.32), skin)
			# Helmet dome & visor
			_add_box(st, Vector3(0.0, 1.28, 0.0), Vector3(0.36, 0.16, 0.36), helmet_orange)
			_add_box(st, Vector3(0.0, 1.22, -0.16), Vector3(0.34, 0.08, 0.08), helmet_orange.darkened(0.2))

		ARCHETYPE_PHOBOMAN:
			# Phoboman Look-Alike: Broad cloaked mantle, dark forest charcoal, glowing visor
			var hood_dark := Color(0.20, 0.28, 0.22)
			var cloak_black := Color(0.16, 0.22, 0.18)
			var vest_emerald := Color(0.28, 0.62, 0.36)
			var glowing_visor := Color(0.45, 0.88, 0.40)
			var boots := Color(0.10, 0.12, 0.10)

			# Boots
			_add_box(st, Vector3(-0.15, 0.15, 0.04), Vector3(0.18, 0.30, 0.32), boots)
			_add_box(st, Vector3(0.15, 0.15, 0.04), Vector3(0.18, 0.30, 0.32), boots)
			# Legs
			_add_box(st, Vector3(-0.15, 0.48, 0.0), Vector3(0.16, 0.40, 0.16), cloak_black)
			_add_box(st, Vector3(0.15, 0.48, 0.0), Vector3(0.16, 0.40, 0.16), cloak_black)
			# Long Coat Lower
			_add_box(st, Vector3(0.0, 0.68, 0.0), Vector3(0.46, 0.42, 0.32), cloak_black)
			# Broad Torso
			_add_box(st, Vector3(0.0, 1.10, 0.0), Vector3(0.50, 0.48, 0.32), vest_emerald)
			# Broad Shoulder Mantle
			_add_box(st, Vector3(0.0, 1.34, 0.0), Vector3(0.58, 0.16, 0.36), hood_dark)
			# Arms
			_add_box(st, Vector3(-0.32, 1.05, 0.0), Vector3(0.14, 0.45, 0.14), hood_dark)
			_add_box(st, Vector3(0.32, 1.05, 0.0), Vector3(0.14, 0.45, 0.14), hood_dark)
			# Head (Hooded)
			_add_box(st, Vector3(0.0, 1.55, 0.0), Vector3(0.34, 0.34, 0.34), hood_dark)
			# Glowing Visor / Eyes
			_add_box(st, Vector3(0.0, 1.55, -0.16), Vector3(0.24, 0.08, 0.06), glowing_visor)

	_archetype_meshes[archetype] = st.commit()
	return _archetype_meshes[archetype]

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	## Join the "crowd" group (discovery hook — citizens join NO group).
	add_to_group("crowd")
	_rng.randomize()

	_crowd_max = CROWD_MAX_WEB if OS.has_feature("web") else CROWD_MAX_DESKTOP

	# Create 4 MultiMeshInstance3D child nodes
	_multimesh_nodes.resize(ARCHETYPE_COUNT)
	var per_archetype := _crowd_max / ARCHETYPE_COUNT

	for k in ARCHETYPE_COUNT:
		var mm_inst := MultiMeshInstance3D.new()
		mm_inst.name = "Crowd_%s" % ARCHETYPE_NAMES[k].capitalize()
		mm_inst.material_override = _get_shared_material()
		mm_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

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
				"speed": 2.0,
				"walk_phase": 0.0,
				"pause_timer": 0.0,
				"facing_yaw": 0.0,
				"heading_dir": Vector2(1.0, 0.0),
				"active": false,
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

	# Maintain active citizens in bubble around player
	_update_crowd_spawns(player_pos)

	# Update movement, grid wayfinding, and animation
	_update_walkers(delta, player_pos)


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
	## True when player is inside or approaching Budapest (x: 1500..3900, z: -1200..1200).
	return player_pos.x >= 1500.0 and player_pos.x <= 3900.0 \
			and player_pos.z >= -1200.0 and player_pos.z <= 1200.0


static func is_walkable(x: float, z: float) -> bool:
	## Pure predicate: returns true if the coordinate is valid dry street ground.
	## Must be inside Budapest, outside Danube water, and outside plateau massifs.
	if not PLAN_SCRIPT.contains(x, z):
		return false
	if PLAN_SCRIPT.danube_wet(x, z):
		return false
	if PLAN_SCRIPT.plateau_top_at(x, z) > 0.0:
		return false
	return true


static func snap_to_grid(x: float, z: float) -> Vector2:
	## Snaps world XZ to the nearest Budapest street grid intersection.
	var gx: float = roundf((x - GRID_ORIGIN_X) / GRID_PITCH) * GRID_PITCH + GRID_ORIGIN_X
	var gz: float = roundf((z - GRID_ORIGIN_Z) / GRID_PITCH) * GRID_PITCH + GRID_ORIGIN_Z
	return Vector2(gx, gz)


func _pick_next_waypoint(current_pos: Vector3, current_heading: Vector2) -> Vector3:
	## Given a grid intersection, picks the next walkable neighbor along the grid.
	var gx: float = current_pos.x
	var gz: float = current_pos.z

	var directions: Array[Vector2] = [
		Vector2(GRID_PITCH, 0.0),
		Vector2(-GRID_PITCH, 0.0),
		Vector2(0.0, GRID_PITCH),
		Vector2(0.0, -GRID_PITCH),
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


func _find_spawn_point_near(player_pos: Vector3) -> Vector3:
	## Finds a valid walkable grid corner within SPAWN_RADIUS of the player.
	for attempt in 16:
		var angle := _rng.randf_range(0.0, TAU)
		var dist := _rng.randf_range(SPAWN_MIN_DIST, SPAWN_RADIUS)
		var cand_x := player_pos.x + cos(angle) * dist
		var cand_z := player_pos.z + sin(angle) * dist
		var snapped := snap_to_grid(cand_x, cand_z)

		if is_walkable(snapped.x, snapped.y):
			return Vector3(snapped.x, 0.0, snapped.y)

	# Fallback: snap player position directly if valid
	var p_snap := snap_to_grid(player_pos.x, player_pos.z)
	if is_walkable(p_snap.x, p_snap.y):
		return Vector3(p_snap.x, 0.0, p_snap.y)

	return Vector3.ZERO


func _update_crowd_spawns(player_pos: Vector3) -> void:
	## Activates or recycles citizens so they surround the player within SPAWN_RADIUS.
	for citizen: Dictionary in _citizens:
		if not citizen["active"]:
			var spawn_pt := _find_spawn_point_near(player_pos)
			if spawn_pt != Vector3.ZERO:
				citizen["pos"] = spawn_pt
				citizen["speed"] = _rng.randf_range(WALK_SPEED_MIN, WALK_SPEED_MAX)
				citizen["walk_phase"] = _rng.randf_range(0.0, TAU)
				citizen["pause_timer"] = 0.0
				var initial_dir := Vector2(1.0 if _rng.randf() < 0.5 else -1.0, 0.0)
				citizen["heading_dir"] = initial_dir
				citizen["target"] = _pick_next_waypoint(spawn_pt, initial_dir)
				var delta_x: float = citizen["target"].x - spawn_pt.x
				var delta_z: float = citizen["target"].z - spawn_pt.z
				citizen["facing_yaw"] = atan2(-delta_x, -delta_z)
				citizen["active"] = true
		else:
			# Check if citizen has drifted beyond DESPAWN_RADIUS or out of walkable zone
			var cpos: Vector3 = citizen["pos"]
			var flat_dist := Vector2(cpos.x - player_pos.x, cpos.z - player_pos.z).length()
			if flat_dist > DESPAWN_RADIUS or not is_walkable(cpos.x, cpos.z):
				# Recycle closer to player
				var new_pt := _find_spawn_point_near(player_pos)
				if new_pt != Vector3.ZERO:
					citizen["pos"] = new_pt
					citizen["speed"] = _rng.randf_range(WALK_SPEED_MIN, WALK_SPEED_MAX)
					citizen["walk_phase"] = _rng.randf_range(0.0, TAU)
					citizen["pause_timer"] = 0.0
					var initial_dir := Vector2(0.0, 1.0 if _rng.randf() < 0.5 else -1.0)
					citizen["heading_dir"] = initial_dir
					citizen["target"] = _pick_next_waypoint(new_pt, initial_dir)
					var delta_x: float = citizen["target"].x - new_pt.x
					var delta_z: float = citizen["target"].z - new_pt.z
					citizen["facing_yaw"] = atan2(-delta_x, -delta_z)
				else:
					citizen["active"] = false


func _update_walkers(delta: float, _player_pos: Vector3) -> void:
	## Advances citizen movement, handles crossing pauses, and pushes transforms
	## to the four MultiMeshes.
	var counts := [0, 0, 0, 0]

	for citizen: Dictionary in _citizens:
		if not citizen["active"]:
			continue

		var k: int = citizen["archetype"]
		var pos: Vector3 = citizen["pos"]
		var target: Vector3 = citizen["target"]
		var is_moving := false

		if citizen["pause_timer"] > 0.0:
			citizen["pause_timer"] -= delta
		else:
			var step: float = citizen["speed"] * delta
			var to_target := target - pos
			var dist := to_target.length()

			if dist <= step or dist < 0.05:
				pos = target
				citizen["walk_phase"] += dist * STRIDE_FREQUENCY
				# Reached crossing: chance to pause
				if _rng.randf() < 0.25:
					citizen["pause_timer"] = _rng.randf_range(0.6, 2.0)
				# Pick next intersection
				var next_target := _pick_next_waypoint(pos, citizen["heading_dir"])
				citizen["target"] = next_target
				var delta_x: float = next_target.x - pos.x
				var delta_z: float = next_target.z - pos.z
				if Vector2(delta_x, delta_z).length_squared() > 0.01:
					citizen["heading_dir"] = Vector2(delta_x, delta_z).normalized()
			else:
				var move_dir := to_target / dist
				pos += move_dir * step
				citizen["walk_phase"] += step * STRIDE_FREQUENCY
				is_moving = true

				# Smoothly rotate facing yaw towards current heading
				var target_yaw := atan2(-move_dir.x, -move_dir.z)
				citizen["facing_yaw"] = rotate_toward(citizen["facing_yaw"], target_yaw, 5.0 * delta)

		citizen["pos"] = pos

		# Calculate walking animation procedural bob and sway
		var phase: float = citizen["walk_phase"]
		var bob_y: float = absf(sin(phase * 2.0)) * WALK_BOB_AMOUNT if is_moving else 0.0
		var sway_z: float = sin(phase) * WALK_SWAY_AMOUNT if is_moving else 0.0
		var pitch_x: float = sin(phase * 2.0) * WALK_PITCH_AMOUNT if is_moving else 0.0

		var basis := Basis().rotated(Vector3.UP, citizen["facing_yaw"])
		if is_moving:
			basis = basis.rotated(Vector3(0, 0, 1), sway_z).rotated(Vector3(1, 0, 0), pitch_x)

		var t := Transform3D(basis, Vector3(pos.x, bob_y, pos.z))

		var mm_inst: MultiMeshInstance3D = _multimesh_nodes[k]
		var mm: MultiMesh = mm_inst.multimesh
		var idx: int = counts[k]
		if idx < mm.instance_count:
			mm.set_instance_transform(idx, t)
			counts[k] += 1

	# Update visible count for all four MultiMeshes
	for k in ARCHETYPE_COUNT:
		_multimesh_nodes[k].multimesh.visible_instance_count = counts[k]


func _hide_all() -> void:
	## Hides all citizens when outside Budapest.
	for k in ARCHETYPE_COUNT:
		if k < _multimesh_nodes.size() and _multimesh_nodes[k] != null:
			_multimesh_nodes[k].multimesh.visible_instance_count = 0
	for citizen: Dictionary in _citizens:
		citizen["active"] = false
