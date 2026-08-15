extends Node
## Ambient migrating fauna: elephant families and giraffe flocks.
##
## From time to time a herd of migrating animals walks across the landscape in
## the distance — PURE SCENERY, nothing else. The animals never react to the
## player, the crocodiles, or any special ability; they have no collision
## bodies, no Area3Ds, no per-animal scripts, and they belong to NO gameplay
## group (see below for why that matters). They enter at the edge of a
## ~FIELD_RADIUS circle around the player, walk a straight-ish migration line
## at a calm 2–3 m/s, and are freed once past DESPAWN_RADIUS.
##
## This node (named FaunaManager, added once under Main in main.tscn, in group
## "fauna") is the ENTIRE feature — sibling in spirit to
## crocodile_lod_manager.gd and sound_manager.gd: a single self-contained
## manager that owns its own entities, builds their meshes fully in code (no
## asset files), and drives all of their movement and animation from one
## _process. It holds no hard references to any other system; the player is
## found through the "player" group like everything else in this codebase.
##
## The perf story is deliberately boring:
## - At most ONE herd (≤ 8 animals) is alive at a time.
## - Every animal is plain Node3D + MeshInstance3D boxes sharing ONE BoxMesh
##   and one material per species (see the static lazy getters below).
## - Between events the entire per-frame cost is a single float subtraction.
##
## WHY the animals join no group: the Phoboman stink wave iterates the
## "crocodile" group and the LOD manager iterates it too — a fauna node in any
## gameplay group would be grabbed by systems that were never written to
## handle it. The manager itself sits in "fauna" purely so future tools can
## find it; the animals themselves are in no group at all.
##
## Fauna is deliberately NON-deterministic ambience: its RNG is randomize()d
## per run and never touches the terrain's run_seed determinism contract —
## revisiting a chunk regenerates the world byte-identically, but which herd
## crosses when is fresh every time, like the crocodiles' per-instance rolls.

# ============================================================================
# CONSTANTS — event scheduling and migration field
# ============================================================================

## Radius (metres) of the field around the player where herds live: a herd
## spawns ON this circle and walks a line through the player's general area.
## Chosen to be past the desktop fog's heavy haze but near enough to read.
const FIELD_RADIUS: float = 180.0

## Distance (metres) from the live player position beyond which a herd is
## freed. Comfortably past FIELD_RADIUS so a herd is never culled mid-view —
## it always walks fully out of the visible field before despawning.
const DESPAWN_RADIUS: float = 230.0

## The very first herd of a session comes sooner than the steady-state gap so
## a short play session still sees one (the acceptance criterion is "within a
## few minutes").
const FIRST_EVENT_DELAY_MIN: float = 40.0
const FIRST_EVENT_DELAY_MAX: float = 80.0

## Steady-state gap (seconds) between one herd despawning and the next
## spawning. Wide and random so migrations feel like events, not a schedule.
const FAUNA_INTERVAL_MIN: float = 120.0
const FAUNA_INTERVAL_MAX: float = 240.0

## Herd walking speed range (m/s) — a calm amble, well below every character's
## walk speed, so a herd reads as scenery drifting past rather than a chase.
const WALK_SPEED_MIN: float = 2.0
const WALK_SPEED_MAX: float = 3.0

## Probability that a given event is an elephant family; otherwise a giraffe
## flock. 50/50 — both species should feel equally common.
const ELEPHANT_CHANCE: float = 0.5

# ============================================================================
# CONSTANTS — elephant geometry
# ============================================================================
# All sizes in metres as Vector3(width, height, length). The animal's local
# forward is -Z (Godot's look-at convention, so the herd code can yaw it along
# its travel direction), and feet rest at local y = 0 by construction — the
# ground is a flat plane at world y = 0, so placing the root on the ground
# needs no raycast (see endless_terrain.gd).

## The barrel of the body. Sized so an adult reads clearly at FIELD_RADIUS
## through the fog: bigger than any crocodile, unmistakably "large animal".
const ELEPHANT_BODY_SIZE: Vector3 = Vector3(1.6, 1.5, 2.6)

## One leg column. Its y is the leg LENGTH and doubles as the hip height —
## the hip pivots sit at exactly this y so the foot bottoms out at y = 0.
const ELEPHANT_LEG_SIZE: Vector3 = Vector3(0.4, 1.1, 0.4)

## The head block, hung on the front of the body slightly above centre.
const ELEPHANT_HEAD_SIZE: Vector3 = Vector3(1.0, 1.0, 0.9)

## One big flat ear slab (thin on x so it reads as a flap, not a block).
const ELEPHANT_EAR_SIZE: Vector3 = Vector3(0.12, 0.8, 0.65)

## One trunk segment box; the trunk is ELEPHANT_TRUNK_SEGMENTS of these in a
## nested pivot chain so it can sway like a floppy chain, not a rigid bar.
const ELEPHANT_TRUNK_SEGMENT_SIZE: Vector3 = Vector3(0.28, 0.55, 0.28)

## How many chained trunk segments (2–3 reads fine; 3 sways best).
const ELEPHANT_TRUNK_SEGMENTS: int = 3

## One tusk box (adults only), tilted forward off the head's lower corners.
const ELEPHANT_TUSK_SIZE: Vector3 = Vector3(0.12, 0.55, 0.12)

## Whole-calf scale relative to an adult: applied as ONE scale write on the
## calf's root, never by rebuilding smaller boxes — same geometry, same code
## path, half-ish size.
const CALF_SCALE: float = 0.55

# ============================================================================
# CONSTANTS — giraffe geometry
# ============================================================================
# Same conventions as the elephant block: metres, Vector3(width, height,
# length), local forward -Z, feet at local y = 0.

## The torso block — smaller than an elephant's barrel; a giraffe's read is
## all in the legs and neck, not the body mass.
const GIRAFFE_BODY_SIZE: Vector3 = Vector3(1.0, 1.1, 1.9)

## One long thin leg column; its y doubles as hip height (same trick as the
## elephant), which is most of what makes the silhouette unmistakably giraffe.
const GIRAFFE_LEG_SIZE: Vector3 = Vector3(0.25, 1.9, 0.25)

## The neck box, hung from a shoulder pivot and tilted forward — its y is the
## neck LENGTH along the pivot's local up axis.
const GIRAFFE_NECK_SIZE: Vector3 = Vector3(0.35, 1.9, 0.35)

## Neck lean (degrees about the pivot's X): negative tips the top toward -Z
## (the animal's forward), giving the classic angled-forward giraffe neck.
const GIRAFFE_NECK_ANGLE_DEG: float = -28.0

## The small head block riding the far end of the neck.
const GIRAFFE_HEAD_SIZE: Vector3 = Vector3(0.42, 0.40, 0.75)

## One ossicone horn nub (two per head), tiny accent boxes on the crown.
const GIRAFFE_HORN_SIZE: Vector3 = Vector3(0.08, 0.22, 0.08)

## A FEW darker coat patches — thin slabs sitting just proud of the body's
## sides. Deliberately 2–3 and NOT a checker pattern: a real giraffe pattern
## would need a texture, and this feature ships zero asset files; a handful of
## darker slabs is enough to say "giraffe" at FIELD_RADIUS through the fog.
const GIRAFFE_PATCH_COUNT: int = 3
const GIRAFFE_PATCH_SIZE: Vector3 = Vector3(0.06, 0.45, 0.55)

# ============================================================================
# STATE
# ============================================================================

## Seconds until the next herd event. Counts down only while no herd is alive;
## re-armed from FAUNA_INTERVAL_* after each despawn.
var _event_timer: float = 0.0

## One record per live animal (see the per-animal record shape in the plan:
## root/body/legs plus species extras and animation phases). Empty array ==
## no herd alive — that emptiness IS the one-herd invariant's bookkeeping.
var _animals: Array[Dictionary] = []

## Private randomize()d RNG, like the crocodile's per-instance rng. Fauna is
## deliberately non-deterministic ambience — it must NOT draw from any seeded
## stream tied to the terrain's run_seed contract.
var _rng := RandomNumberGenerator.new()

# ============================================================================
# SHARED RESOURCES (static — one per PROCESS, not one per manager/animal)
# ============================================================================
# Same discipline as endless_terrain._get_shared_unit_box_mesh() and
# ToonShading's static material cache: every animal that will ever exist is
# built from ONE unit BoxMesh scaled per part, and the total material count
# for the whole feature is a small constant (2 species + 2 accents), no matter
# how many animals spawn over a session. Never duplicate() these per animal —
# that would defeat batching and grow memory with every herd.

static var _shared_box_mesh: BoxMesh = null
static var _elephant_material: StandardMaterial3D = null
static var _giraffe_material: StandardMaterial3D = null
static var _accent_material: StandardMaterial3D = null
static var _patch_material: StandardMaterial3D = null


static func _get_shared_box_mesh() -> BoxMesh:
	## The ONE mesh every fauna body part uses: a unit cube, scaled per part
	## via each MeshInstance3D's own scale. Shared so the renderer sees one
	## mesh resource across every animal ever spawned (batching + memory).
	if _shared_box_mesh == null:
		_shared_box_mesh = BoxMesh.new()
		_shared_box_mesh.size = Vector3.ONE
	return _shared_box_mesh


static func _get_elephant_material() -> StandardMaterial3D:
	## The ONE elephant material (grey hide). Shared by every box of every
	## elephant ever spawned — N animals must never add N materials.
	if _elephant_material == null:
		_elephant_material = StandardMaterial3D.new()
		_elephant_material.albedo_color = Color(0.52, 0.52, 0.55)
		_elephant_material.roughness = 0.9
	return _elephant_material


static func _get_giraffe_material() -> StandardMaterial3D:
	## The ONE giraffe material (tan-orange coat). Same sharing rule as the
	## elephant material above.
	if _giraffe_material == null:
		_giraffe_material = StandardMaterial3D.new()
		_giraffe_material.albedo_color = Color(0.85, 0.62, 0.30)
		_giraffe_material.roughness = 0.9
	return _giraffe_material


static func _get_accent_material() -> StandardMaterial3D:
	## The ONE light accent material (off-white elephant tusks). Shared by
	## every tusk of every elephant ever spawned — accents follow the same
	## one-shared-material rule as the species hides.
	if _accent_material == null:
		_accent_material = StandardMaterial3D.new()
		_accent_material.albedo_color = Color(0.92, 0.90, 0.82)
		_accent_material.roughness = 0.7
	return _accent_material


static func _get_patch_material() -> StandardMaterial3D:
	## The ONE dark accent material (darker-brown giraffe coat patches and
	## horn nubs — both need a darker-than-coat read, so they share it). With
	## this the feature's total material count is capped at a constant 4,
	## independent of how many animals ever spawn.
	if _patch_material == null:
		_patch_material = StandardMaterial3D.new()
		_patch_material.albedo_color = Color(0.48, 0.32, 0.16)
		_patch_material.roughness = 0.9
	return _patch_material


# ============================================================================
# MODEL BUILDERS (pure code, no scene files, no assets — ability_effect.gd
# precedent: build the visual tree in script, free it when done)
# ============================================================================

static func _make_box_part(part_name: String, size: Vector3, local_pos: Vector3,
		material: StandardMaterial3D, casts_shadow: bool) -> MeshInstance3D:
	## One box-shaped body part: the ONE shared unit BoxMesh scaled to `size`
	## via the node's own scale (never a new mesh resource), painted with a
	## shared species material. `casts_shadow` is a per-part choice: the big
	## silhouette parts keep the default ON (near-ground shadows sell an
	## animal's size), while small accents turn it OFF because they add
	## shadow-pass draws without contributing anything visible to the shadow.
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = _get_shared_box_mesh()
	part.material_override = material
	part.scale = size
	part.position = local_pos
	if not casts_shadow:
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return part


static func _make_leg(leg_name: String, hip_pos: Vector3, leg_size: Vector3,
		material: StandardMaterial3D, casts_shadow: bool) -> Node3D:
	## One leg = a bare pivot Node3D AT HIP HEIGHT with the visible box hung
	## half a leg-length BELOW it. That offset is the whole trick: rotating
	## the pivot about X swings the leg from the hip like a real limb, instead
	## of spinning the box around its own centre. The walk animation only ever
	## touches the pivot; the box never moves in its own frame.
	var pivot := Node3D.new()
	pivot.name = leg_name
	pivot.position = hip_pos
	pivot.add_child(_make_box_part("LegBox", leg_size,
			Vector3(0.0, -leg_size.y * 0.5, 0.0), material, casts_shadow))
	return pivot


func _build_elephant(is_adult: bool) -> Node3D:
	## Assemble one elephant entirely from the shared unit BoxMesh + shared
	## materials. Blocky BY DESIGN: the whole world (decorative blocks, the
	## low-poly character cast) is boxes and flat colours, so a box elephant
	## matches the art direction — a smooth model would look pasted in, and a
	## real mesh would mean an asset file this feature deliberately avoids.
	##
	## Tree contract (Task 5's animation depends on these exact shapes):
	## root Node3D (feet at y = 0, faces -Z) -> "Body" Node3D (bobs
	## vertically, carries the static boxes) -> four hip-pivot Node3Ds
	## (FL/FR/RL/RR) and a nested "Trunk0..N" pivot chain off the head.
	var mat := _get_elephant_material()
	# Calves cast no shadows AT ALL: at CALF_SCALE they are small accents in
	# the herd picture, and dropping them from the shadow passes is free
	# fidelity headroom for the adults (whose shadows sell the size contrast).
	var body_shadows := is_adult

	var root := Node3D.new()
	root.name = "Elephant"
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)

	# Barrel: bottom rests on the leg tops, so its centre is hip + half height.
	var body_center_y := ELEPHANT_LEG_SIZE.y + ELEPHANT_BODY_SIZE.y * 0.5
	body.add_child(_make_box_part("BodyBox", ELEPHANT_BODY_SIZE,
			Vector3(0.0, body_center_y, 0.0), mat, body_shadows))

	# Head: hung on the front (-Z) face, slightly above body centre, tucked
	# 0.15 m back into the barrel so the joint never shows a gap.
	var head_pos := Vector3(0.0, body_center_y + 0.35,
			-(ELEPHANT_BODY_SIZE.z * 0.5 + ELEPHANT_HEAD_SIZE.z * 0.5 - 0.15))
	body.add_child(_make_box_part("Head", ELEPHANT_HEAD_SIZE, head_pos, mat, body_shadows))

	# Ears: thin slabs on the head's sides. Shadow OFF — a 12 cm slab adds a
	# shadow-pass draw and zero silhouette.
	var ear_x := ELEPHANT_HEAD_SIZE.x * 0.5 + ELEPHANT_EAR_SIZE.x * 0.5
	body.add_child(_make_box_part("EarL", ELEPHANT_EAR_SIZE,
			head_pos + Vector3(-ear_x, 0.05, 0.15), mat, false))
	body.add_child(_make_box_part("EarR", ELEPHANT_EAR_SIZE,
			head_pos + Vector3(ear_x, 0.05, 0.15), mat, false))

	# Tusks: adults only — the visual cue that separates parents from calves.
	# Accent material (off-white), tilted so the tops lean forward, shadow OFF.
	if is_adult:
		var tusk_y := head_pos.y - ELEPHANT_HEAD_SIZE.y * 0.5
		var tusk_z := head_pos.z - ELEPHANT_HEAD_SIZE.z * 0.5 + 0.1
		for side: float in [-1.0, 1.0]:
			var tusk := _make_box_part("TuskL" if side < 0.0 else "TuskR",
					ELEPHANT_TUSK_SIZE, Vector3(side * 0.25, tusk_y, tusk_z),
					_get_accent_material(), false)
			tusk.rotation_degrees.x = -35.0
			body.add_child(tusk)

	# Trunk: a chain of nested pivots hanging from the head's front-bottom
	# edge. Each pivot sits at the BOTTOM of its parent segment and its box
	# hangs half a segment below it, so rotating any pivot swings everything
	# downstream — the chain structure Task 5's per-segment sway lag needs.
	var seg_len := ELEPHANT_TRUNK_SEGMENT_SIZE.y
	var trunk_parent: Node3D = body
	for i: int in ELEPHANT_TRUNK_SEGMENTS:
		var pivot := Node3D.new()
		pivot.name = "Trunk%d" % i
		if i == 0:
			pivot.position = Vector3(0.0, head_pos.y - ELEPHANT_HEAD_SIZE.y * 0.5,
					head_pos.z - ELEPHANT_HEAD_SIZE.z * 0.5)
		else:
			pivot.position = Vector3(0.0, -seg_len, 0.0)
		pivot.add_child(_make_box_part("TrunkBox", ELEPHANT_TRUNK_SEGMENT_SIZE,
				Vector3(0.0, -seg_len * 0.5, 0.0), mat, false))
		trunk_parent.add_child(pivot)
		trunk_parent = pivot

	# Legs, always in FL/FR/RL/RR order — the species-agnostic contract the
	# animation loop relies on (diagonal trot pairs are picked by index).
	var hip_x := ELEPHANT_BODY_SIZE.x * 0.5 - ELEPHANT_LEG_SIZE.x * 0.5
	var hip_z := ELEPHANT_BODY_SIZE.z * 0.5 - ELEPHANT_LEG_SIZE.z * 0.5
	var hip_y := ELEPHANT_LEG_SIZE.y
	body.add_child(_make_leg("LegFL", Vector3(-hip_x, hip_y, -hip_z),
			ELEPHANT_LEG_SIZE, mat, body_shadows))
	body.add_child(_make_leg("LegFR", Vector3(hip_x, hip_y, -hip_z),
			ELEPHANT_LEG_SIZE, mat, body_shadows))
	body.add_child(_make_leg("LegRL", Vector3(-hip_x, hip_y, hip_z),
			ELEPHANT_LEG_SIZE, mat, body_shadows))
	body.add_child(_make_leg("LegRR", Vector3(hip_x, hip_y, hip_z),
			ELEPHANT_LEG_SIZE, mat, body_shadows))

	# A calf is the SAME build scaled once at the root — one scale write, no
	# smaller boxes, no second code path to keep in sync.
	if not is_adult:
		root.scale = Vector3.ONE * CALF_SCALE
	return root


func _build_giraffe() -> Node3D:
	## Assemble one giraffe from the same shared unit BoxMesh + shared
	## materials, under the SAME node-structure contract as _build_elephant so
	## the animal record (and the animation loop reading it) stays
	## species-agnostic: root Node3D (feet at y = 0, faces -Z) -> "Body"
	## Node3D -> four hip-pivot legs added in FL/FR/RL/RR order. The only
	## species difference is the extras slot: a giraffe has a "Neck" pivot
	## (elephants: null) and no trunk chain (elephants: "Trunk0..N") — the
	## record simply carries null/empty for the other species' extra.
	var mat := _get_giraffe_material()

	var root := Node3D.new()
	root.name = "Giraffe"
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)

	# Torso: rests on the long leg columns, so its centre is hip + half height.
	var body_center_y := GIRAFFE_LEG_SIZE.y + GIRAFFE_BODY_SIZE.y * 0.5
	body.add_child(_make_box_part("BodyBox", GIRAFFE_BODY_SIZE,
			Vector3(0.0, body_center_y, 0.0), mat, true))

	# Coat patches: a few darker slabs just proud of the torso's flanks, at
	# fixed hand-picked spots (alternating sides, staggered along the body) —
	# see GIRAFFE_PATCH_COUNT for why this is NOT a checker pattern. Shadow
	# OFF: a 6 cm slab flush against the body adds a shadow-pass draw and
	# nothing to the silhouette.
	var patch_x := GIRAFFE_BODY_SIZE.x * 0.5 + GIRAFFE_PATCH_SIZE.x * 0.5 - 0.02
	var patch_sides: Array[float] = [-1.0, 1.0, -1.0]
	var patch_offsets: Array[Vector3] = [
		Vector3(0.0, 0.12, -0.55), Vector3(0.0, -0.10, 0.10), Vector3(0.0, 0.18, 0.60),
	]
	for i: int in GIRAFFE_PATCH_COUNT:
		body.add_child(_make_box_part("Patch%d" % i, GIRAFFE_PATCH_SIZE,
				Vector3(patch_sides[i] * patch_x, body_center_y, 0.0) + patch_offsets[i],
				_get_patch_material(), false))

	# Neck: a pivot Node3D at the shoulders (front-top of the torso) with the
	# neck box hung half a length ABOVE it along the pivot's local up — the
	# same offset-from-pivot trick as the legs, so the neck-bob animation can
	# swing the whole neck (head and horns included) from the shoulders. The
	# forward lean is the pivot's REST rotation; Task 5 caches it and layers
	# the bob on top instead of overwriting it.
	var neck := Node3D.new()
	neck.name = "Neck"
	neck.position = Vector3(0.0, body_center_y + GIRAFFE_BODY_SIZE.y * 0.35,
			-(GIRAFFE_BODY_SIZE.z * 0.5 - GIRAFFE_NECK_SIZE.z * 0.5))
	neck.rotation_degrees.x = GIRAFFE_NECK_ANGLE_DEG
	body.add_child(neck)
	neck.add_child(_make_box_part("NeckBox", GIRAFFE_NECK_SIZE,
			Vector3(0.0, GIRAFFE_NECK_SIZE.y * 0.5, 0.0), mat, true))

	# Head + horn nubs live in NECK-local space at the neck's far end, so they
	# ride every neck swing for free. The head is a silhouette part (shadow
	# stays ON like body/legs/neck); the horn nubs are accents (shadow OFF).
	var head_pos := Vector3(0.0, GIRAFFE_NECK_SIZE.y + GIRAFFE_HEAD_SIZE.y * 0.5 - 0.08,
			-(GIRAFFE_HEAD_SIZE.z * 0.5 - GIRAFFE_NECK_SIZE.z * 0.5))
	neck.add_child(_make_box_part("Head", GIRAFFE_HEAD_SIZE, head_pos, mat, true))
	for side: float in [-1.0, 1.0]:
		neck.add_child(_make_box_part("HornL" if side < 0.0 else "HornR",
				GIRAFFE_HORN_SIZE,
				head_pos + Vector3(side * 0.12,
						GIRAFFE_HEAD_SIZE.y * 0.5 + GIRAFFE_HORN_SIZE.y * 0.5, 0.1),
				_get_patch_material(), false))

	# Legs, always in FL/FR/RL/RR order — the species-agnostic contract the
	# animation loop relies on (diagonal trot pairs are picked by index).
	var hip_x := GIRAFFE_BODY_SIZE.x * 0.5 - GIRAFFE_LEG_SIZE.x * 0.5
	var hip_z := GIRAFFE_BODY_SIZE.z * 0.5 - GIRAFFE_LEG_SIZE.z * 0.5
	var hip_y := GIRAFFE_LEG_SIZE.y
	body.add_child(_make_leg("LegFL", Vector3(-hip_x, hip_y, -hip_z),
			GIRAFFE_LEG_SIZE, mat, true))
	body.add_child(_make_leg("LegFR", Vector3(hip_x, hip_y, -hip_z),
			GIRAFFE_LEG_SIZE, mat, true))
	body.add_child(_make_leg("LegRL", Vector3(-hip_x, hip_y, hip_z),
			GIRAFFE_LEG_SIZE, mat, true))
	body.add_child(_make_leg("LegRR", Vector3(hip_x, hip_y, hip_z),
			GIRAFFE_LEG_SIZE, mat, true))
	return root


# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	## Join the "fauna" group (discovery hook for future tools — the ANIMALS
	## join no group, only the manager), seed the private RNG, and arm the
	## first-event timer with the shorter first-session delay.
	add_to_group("fauna")
	_rng.randomize()
	_event_timer = _rng.randf_range(FIRST_EVENT_DELAY_MIN, FIRST_EVENT_DELAY_MAX)


func _process(delta: float) -> void:
	## The whole per-frame driver. With a herd alive it advances and animates
	## it; with none alive the ENTIRE cost of this feature is the one float
	## subtraction and compare below — that's the idle perf story.
	if not _animals.is_empty():
		_update_herd(delta)
		return

	_event_timer -= delta
	if _event_timer <= 0.0:
		_spawn_herd()
		# Re-arm now so a failed spawn (no player yet) just retries later
		# instead of hammering every frame.
		_event_timer = _rng.randf_range(FAUNA_INTERVAL_MIN, FAUNA_INTERVAL_MAX)


# ============================================================================
# CORE (stubs — herd building/movement/animation land in later tasks)
# ============================================================================

func _find_player() -> Node3D:
	## Locate the player through the "player" group — group-based discovery,
	## never a hard $-path (matches crocodile_lod_manager.gd). Null-safe: in a
	## scene run without a player (a character scene tested standalone) this
	## returns null and the manager simply does nothing, same defensive style
	## as the sound-manager group lookups.
	var player := get_tree().get_first_node_in_group("player")
	if player is Node3D:
		return player
	return null


func _spawn_herd() -> void:
	## Build and place one herd (filled in by the spawning task). Stub: does
	## nothing yet beyond respecting the null-safe no-player case.
	var player := _find_player()
	if player == null:
		return


func _update_herd(_delta: float) -> void:
	## Advance, animate, and despawn-check the live herd (filled in by the
	## movement/animation tasks). Stub for now.
	pass
