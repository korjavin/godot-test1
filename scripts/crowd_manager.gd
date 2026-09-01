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
##   * Shared static resources: one shared composite mesh per archetype with
##     baked vertex colors derived from the hero specifications, and ONE shared
##     StandardMaterial3D across all archetypes (never duplicate() per citizen).
##   * Waypoint walk: citizens follow the 62 m street grid of Budapest, spread
##     across lateral street lanes, maintaining walking queues, never walking into
##     the Danube river, plateau cliffs, or solid landmark buildings.
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
const SPAWN_MIN_DIST: float = 15.0

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

## Minimum distance between walkers in the same street lane (metres).
const MIN_WALKER_SPACING: float = 1.8

## Lateral lane offsets across the street corridor.
const LANE_OFFSETS: Array[float] = [-3.2, -1.6, 0.0, 1.6, 3.2]

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
	## Adds a 6-sided box with outward CCW normals and vertex color to a SurfaceTool.
	var h := size * 0.5
	var min_p := center - h
	var max_p := center + h

	# 1. Front (+Z, normal (0, 0, 1))
	st.set_normal(Vector3(0, 0, 1))
	st.set_color(col)
	st.add_vertex(Vector3(min_p.x, min_p.y, max_p.z))
	st.add_vertex(Vector3(max_p.x, min_p.y, max_p.z))
	st.add_vertex(Vector3(max_p.x, max_p.y, max_p.z))
	st.add_vertex(Vector3(min_p.x, min_p.y, max_p.z))
	st.add_vertex(Vector3(max_p.x, max_p.y, max_p.z))
	st.add_vertex(Vector3(min_p.x, max_p.y, max_p.z))

	# 2. Back (-Z, normal (0, 0, -1))
	st.set_normal(Vector3(0, 0, -1))
	st.set_color(col)
	st.add_vertex(Vector3(max_p.x, min_p.y, min_p.z))
	st.add_vertex(Vector3(min_p.x, min_p.y, min_p.z))
	st.add_vertex(Vector3(min_p.x, max_p.y, min_p.z))
	st.add_vertex(Vector3(max_p.x, min_p.y, min_p.z))
	st.add_vertex(Vector3(min_p.x, max_p.y, min_p.z))
	st.add_vertex(Vector3(max_p.x, max_p.y, min_p.z))

	# 3. Left (-X, normal (-1, 0, 0))
	st.set_normal(Vector3(-1, 0, 0))
	st.set_color(col)
	st.add_vertex(Vector3(min_p.x, min_p.y, min_p.z))
	st.add_vertex(Vector3(min_p.x, min_p.y, max_p.z))
	st.add_vertex(Vector3(min_p.x, max_p.y, max_p.z))
	st.add_vertex(Vector3(min_p.x, min_p.y, min_p.z))
	st.add_vertex(Vector3(min_p.x, max_p.y, max_p.z))
	st.add_vertex(Vector3(min_p.x, max_p.y, min_p.z))

	# 4. Right (+X, normal (1, 0, 0))
	st.set_normal(Vector3(1, 0, 0))
	st.set_color(col)
	st.add_vertex(Vector3(max_p.x, min_p.y, max_p.z))
	st.add_vertex(Vector3(max_p.x, min_p.y, min_p.z))
	st.add_vertex(Vector3(max_p.x, max_p.y, min_p.z))
	st.add_vertex(Vector3(max_p.x, min_p.y, max_p.z))
	st.add_vertex(Vector3(max_p.x, max_p.y, min_p.z))
	st.add_vertex(Vector3(max_p.x, max_p.y, max_p.z))

	# 5. Top (+Y, normal (0, 1, 0))
	st.set_normal(Vector3(0, 1, 0))
	st.set_color(col)
	st.add_vertex(Vector3(min_p.x, max_p.y, max_p.z))
	st.add_vertex(Vector3(max_p.x, max_p.y, max_p.z))
	st.add_vertex(Vector3(max_p.x, max_p.y, min_p.z))
	st.add_vertex(Vector3(min_p.x, max_p.y, max_p.z))
	st.add_vertex(Vector3(max_p.x, max_p.y, min_p.z))
	st.add_vertex(Vector3(min_p.x, max_p.y, min_p.z))

	# 6. Bottom (-Y, normal (0, -1, 0))
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

			# Boots (left & right)
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

			# Black boots with silver band
			_add_box(st, Vector3(-0.11, 0.12, 0.03), Vector3(0.14, 0.24, 0.26), boots_black)
			_add_box(st, Vector3(0.11, 0.12, 0.03), Vector3(0.14, 0.24, 0.26), boots_black)
			_add_box(st, Vector3(-0.11, 0.25, 0.0), Vector3(0.15, 0.04, 0.16), boot_band)
			_add_box(st, Vector3(0.11, 0.25, 0.0), Vector3(0.15, 0.04, 0.16), boot_band)
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

			# Dark shoes
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

			# Tiny black boots at bottom
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
				"lane_offset": LANE_OFFSETS[i % LANE_OFFSETS.size()],
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


## Major solid landmark building footprints to exclude from crowd street paths.
## Open plazas (Heroes' Square, Budapest Eye), pedestrian promenades (Váci utca),
## and bridges (Chain/Elisabeth/Liberty/Margaret) are kept walkable.
const SOLID_LANDMARK_EXCLUSIONS: Array = [
	{"id": "parliament", "pos": Vector2(2760.0, -480.0), "radius": 140.0},
	{"id": "basilica", "pos": Vector2(2920.0, -280.0), "radius": 52.0},
	{"id": "market_hall", "pos": Vector2(2820.0, 620.0), "radius": 75.0},
	{"id": "synagogue", "pos": Vector2(2960.0, 200.0), "radius": 45.0},
	{"id": "national_museum", "pos": Vector2(2920.0, 440.0), "radius": 55.0},
	{"id": "opera", "pos": Vector2(3000.0, -180.0), "radius": 45.0},
	{"id": "vajdahunyad", "pos": Vector2(3680.0, -340.0), "radius": 85.0},
	{"id": "szechenyi_bath", "pos": Vector2(3620.0, -760.0), "radius": 75.0},
	{"id": "gellert_bath", "pos": Vector2(2420.0, 1000.0), "radius": 55.0},
	{"id": "rudas_bath", "pos": Vector2(2370.0, 560.0), "radius": 45.0},
]


static func _is_inside_solid_landmark(x: float, z: float) -> bool:
	for slot: Dictionary in SOLID_LANDMARK_EXCLUSIONS:
		var spos: Vector2 = slot["pos"]
		var r: float = slot["radius"]
		var dx: float = x - spos.x
		var dz: float = z - spos.y
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


func _find_spawn_segment_near(player_pos: Vector3) -> Dictionary:
	## Finds a valid street segment (start, end) within SPAWN_RADIUS of the player.
	for attempt in 20:
		var angle := _rng.randf_range(0.0, TAU)
		var dist := _rng.randf_range(SPAWN_MIN_DIST, SPAWN_RADIUS)
		var cand_x := player_pos.x + cos(angle) * dist
		var cand_z := player_pos.z + sin(angle) * dist
		var snapped := snap_to_grid(cand_x, cand_z)

		if is_walkable(snapped.x, snapped.y):
			var corner := Vector3(snapped.x, 0.0, snapped.y)
			var dir_choice := Vector2(1.0 if _rng.randf() < 0.5 else -1.0, 0.0)
			if _rng.randf() < 0.5:
				dir_choice = Vector2(0.0, 1.0 if _rng.randf() < 0.5 else -1.0)
			var next_corner := _pick_next_waypoint(corner, dir_choice)
			if next_corner != corner:
				return {"start": corner, "end": next_corner, "dir": dir_choice}

	# Fallback to snapped player pos
	var p_snap := snap_to_grid(player_pos.x, player_pos.z)
	if is_walkable(p_snap.x, p_snap.y):
		var p_corner := Vector3(p_snap.x, 0.0, p_snap.y)
		var p_next := _pick_next_waypoint(p_corner, Vector2(1.0, 0.0))
		return {"start": p_corner, "end": p_next, "dir": Vector2(1.0, 0.0)}

	return {}


func _update_crowd_spawns(player_pos: Vector3) -> void:
	## Activates or recycles citizens in a natural, distributed arrangement around the player.
	for citizen: Dictionary in _citizens:
		if not citizen["active"]:
			var seg := _find_spawn_segment_near(player_pos)
			if not seg.is_empty():
				var start_pt: Vector3 = seg["start"]
				var end_pt: Vector3 = seg["end"]
				var t_prog := _rng.randf_range(0.05, 0.95)
				citizen["pos"] = start_pt.lerp(end_pt, t_prog)
				citizen["target"] = end_pt
				citizen["lane_offset"] = LANE_OFFSETS[_rng.randi() % LANE_OFFSETS.size()]
				citizen["speed"] = _rng.randf_range(WALK_SPEED_MIN, WALK_SPEED_MAX)
				citizen["walk_phase"] = _rng.randf_range(0.0, TAU)
				citizen["pause_timer"] = 0.0
				var delta_x: float = end_pt.x - start_pt.x
				var delta_z: float = end_pt.z - start_pt.z
				var heading := Vector2(delta_x, delta_z).normalized()
				citizen["heading_dir"] = heading
				citizen["facing_yaw"] = atan2(-delta_x, -delta_z)
				citizen["active"] = true
		else:
			# Check if citizen has drifted beyond DESPAWN_RADIUS or out of walkable zone
			var cpos: Vector3 = citizen["pos"]
			var flat_dist := Vector2(cpos.x - player_pos.x, cpos.z - player_pos.z).length()
			if flat_dist > DESPAWN_RADIUS or not is_walkable(cpos.x, cpos.z):
				# Recycle closer to player
				var seg := _find_spawn_segment_near(player_pos)
				if not seg.is_empty():
					var start_pt: Vector3 = seg["start"]
					var end_pt: Vector3 = seg["end"]
					var t_prog := _rng.randf_range(0.05, 0.95)
					citizen["pos"] = start_pt.lerp(end_pt, t_prog)
					citizen["target"] = end_pt
					citizen["lane_offset"] = LANE_OFFSETS[_rng.randi() % LANE_OFFSETS.size()]
					citizen["speed"] = _rng.randf_range(WALK_SPEED_MIN, WALK_SPEED_MAX)
					citizen["walk_phase"] = _rng.randf_range(0.0, TAU)
					citizen["pause_timer"] = 0.0
					var delta_x: float = end_pt.x - start_pt.x
					var delta_z: float = end_pt.z - start_pt.z
					var heading := Vector2(delta_x, delta_z).normalized()
					citizen["heading_dir"] = heading
					citizen["facing_yaw"] = atan2(-delta_x, -delta_z)
				else:
					citizen["active"] = false


func _update_walkers(delta: float, _player_pos: Vector3) -> void:
	## Advances citizen movement, avoids clumping via lane queuing, and pushes
	## transforms to the four MultiMeshes.
	var counts := [0, 0, 0, 0]

	for i in _citizens.size():
		var citizen: Dictionary = _citizens[i]
		if not citizen["active"]:
			continue

		var k: int = citizen["archetype"]
		var pos: Vector3 = citizen["pos"]
		var target: Vector3 = citizen["target"]
		var lane: float = citizen["lane_offset"]
		var is_moving := false

		# Check spacing against other walkers in the same corridor/lane
		var is_blocked := false
		for j in _citizens.size():
			if i == j:
				continue
			var other: Dictionary = _citizens[j]
			if not other["active"]:
				continue
			if absf(other["lane_offset"] - lane) < 1.4:
				var to_other: Vector3 = other["pos"] - pos
				var dist_other := to_other.length()
				if dist_other < MIN_WALKER_SPACING:
					var move_vec := (target - pos).normalized()
					if to_other.dot(move_vec) > 0.0:
						# Another walker is directly ahead in our lane: queue behind them
						is_blocked = true
						break

		if citizen["pause_timer"] > 0.0:
			citizen["pause_timer"] -= delta
		elif not is_blocked:
			var step: float = citizen["speed"] * delta
			var to_target := target - pos
			var dist := to_target.length()

			if dist <= step or dist < 0.05:
				pos = target
				citizen["walk_phase"] += dist * STRIDE_FREQUENCY
				# Reached crossing: chance to pause and switch lanes
				if _rng.randf() < 0.30:
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

		# Calculate lateral offset perpendicular to movement heading
		var h_dir: Vector2 = citizen["heading_dir"]
		var lat_dir := Vector3(-h_dir.y, 0.0, h_dir.x)
		var world_pos := pos + lat_dir * lane

		# Calculate walking animation procedural bob and sway
		var phase: float = citizen["walk_phase"]
		var bob_y: float = absf(sin(phase * 2.0)) * WALK_BOB_AMOUNT if is_moving else 0.0
		var sway_z: float = sin(phase) * WALK_SWAY_AMOUNT if is_moving else 0.0
		var pitch_x: float = sin(phase * 2.0) * WALK_PITCH_AMOUNT if is_moving else 0.0

		var basis := Basis().rotated(Vector3.UP, citizen["facing_yaw"])
		if is_moving:
			basis = basis.rotated(Vector3(0, 0, 1), sway_z).rotated(Vector3(1, 0, 0), pitch_x)

		var t := Transform3D(basis, Vector3(world_pos.x, bob_y, world_pos.z))

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
