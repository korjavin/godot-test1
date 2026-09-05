class_name CityAgents
extends RefCounted
## What Budapest's two AMBIENCE CROWDS have in common, and nothing else
## (bead `godot-test1-ftn.22`).
##
## `crowd_manager.gd` (citizens, 4 MultiMeshes) and `traffic_manager.gd` (cars,
## 1 MultiMesh) are two separate features with two separate rule sets — the
## spawn samplers, the LOD step, the proxy pools, the kerb rule and the braking
## are each manager's own and deliberately STAY THERE. What they shared was a
## near-verbatim ~130-line prefix: a cached `BoxMesh` factory, the `SurfaceTool`
## box welder both build their meshes with, the player and Budapest lookups, and
## the open-slot table `is_inside_solid_landmark` walks.
##
## THE OPEN-SLOT TABLE IS WHY THIS FILE EXISTS. `WALKABLE_LANDMARK_IDS` is the
## kind of list that drifts in silence: the day a twenty-third slot becomes a
## plaza, one copy learns about it and the other keeps refusing to walk there,
## and nothing fails — citizens simply stop crossing a square cars still drive
## over. One table, one answer.
##
## It is `landmark_builders.gd`'s contract: `class_name`, every function
## `static`, no instance state, and **no node reference held anywhere** —
## `find_player` takes the caller's `SceneTree` and does the group lookup the
## managers always did (CLAUDE.md's group discovery, moved rather than replaced
## by a stored reference). Both managers keep a one-line forwarder for the names
## with many call sites (`_add_box` alone has 94), which is
## `endless_terrain.create_box`'s precedent: the BODY lives once, the spelling at
## the call sites does not have to change, and `crowd_selfcheck`'s reach for
## `_is_inside_solid_landmark` on the manager script still resolves.

const PLAN_SCRIPT := preload("res://scripts/budapest_plan.gd")

## ONE cache for BOTH managers, keyed by size (bead `godot-test1-ftn.22`).
## Merging the two was free and is a real saving: the key is the box's
## dimensions, so a citizen's 0.28-cube boot and a car part of the same size
## ARE the same mesh — there was never anything per-manager about a `BoxMesh`.
## Every entry is built once per process and read from both welders.
static var _box_cache: Dictionary = {}


static func box_mesh(size: Vector3) -> BoxMesh:
	## Cached BoxMesh generator to ensure engine-accurate standard normals,
	## vertex winding, and UVs.
	if not _box_cache.has(size):
		var bm := BoxMesh.new()
		bm.size = size
		_box_cache[size] = bm
	return _box_cache[size]


static func add_box(st: SurfaceTool, center: Vector3, size: Vector3, col: Color) -> void:
	## Adds an engine-accurate 6-sided box with correct outward CCW winding
	## and vertex color to a SurfaceTool.
	##
	## Every box is welded at its BODY offset, which is what makes model-space
	## `VERTEX.y` run boots-to-hat over a whole citizen and wheels-to-roof over a
	## whole car — the reason both managers' materials declare a `height_range`
	## (bead `godot-test1-y1o.15`) instead of taking the shader's unit-cube default.
	var arrays: Array = box_mesh(size).get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	for i: int in indices:
		st.set_color(col)
		st.set_normal(normals[i])
		st.add_vertex(center + verts[i])


static func gradient_material(mesh_top: float, roughness: float) -> ShaderMaterial:
	## One ambience material on the WORLD'S OWN block shader (bead
	## `godot-test1-y1o.15`, style direction A), so a citizen and a car are lit
	## like the street they stand on instead of reading flat against a
	## gradient-shaded city.
	##
	## The two callers differ in exactly two numbers — the body height the
	## gradient is measured over and the roughness — so they are the two
	## arguments, and each manager keeps its own lazy singleton over this. That
	## split is deliberate: "ONE material per manager, never one per instance" is
	## an invariant `crowd_selfcheck` and `traffic_selfcheck` both assert off the
	## live `material_override`, and a cache in here would quietly make it "one
	## per (height, roughness) pair" — the same thing today and not tomorrow.
	##
	## The tint arrives through `COLOR` (vertex colours, times the per-instance
	## colour of a `use_colors` MultiMesh), so `albedo` stays at its white default.
	var mat := ShaderMaterial.new()
	mat.shader = ChunkBatch.WORLD_BLOCK_SHADER
	mat.set_shader_parameter("height_range", Vector2(0.0, mesh_top))
	mat.set_shader_parameter("block_roughness", roughness)
	mat.set_shader_parameter("bottom_shade", ChunkBatch.BLOCK_BOTTOM_SHADE)
	return mat


static func find_player(tree: SceneTree) -> Node3D:
	## Locate the local player through the "player" group.
	##
	## The TREE is the argument rather than a stored node: this is CLAUDE.md's
	## group discovery moved, not turned into a reference — a library that cached
	## the player would outlive a respawn and hand back a freed body.
	if tree == null:
		return null
	var player := tree.get_first_node_in_group("player")
	if player is Node3D:
		return player
	return null


static func is_near_budapest(player_pos: Vector3) -> bool:
	## True when player is inside or within 100m margin of Budapest rect.
	return PLAN_SCRIPT.rect().grow(100.0).has_point(Vector2(player_pos.x, player_pos.z))


## Slots that are open plazas, pedestrian streets, bridges, or plateaus
## where ground-level street path checks should not block walkers.
##
## THE ONE COPY. It used to be two, one per manager, and the failure mode was
## silent in both directions — see this file's header.
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


static func is_inside_solid_landmark(x: float, z: float) -> bool:
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
