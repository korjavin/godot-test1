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
## Capped by the WEB build's terrain extent, not by taste: web drops
## render_distance to 3 chunks × 50 m, so the ground reaches only ~150 m from
## the player at worst (see endless_terrain.gd's fog comment). A herd spawned
## past that would stand over open sky with no ground plane under it, which
## the fog only partly hides for a 4 m-tall giraffe. 140 m keeps every spawn
## on solid ground on both platforms.
const FIELD_RADIUS: float = 140.0

## Distance (metres) from the live player position beyond which a herd is
## freed. Past FIELD_RADIUS so a herd is never culled mid-view — it always
## walks fully out of the visible field before despawning — but bounded by the
## SAME terrain-extent argument as FIELD_RADIUS: the web ground only reaches
## ~150 m, so a herd kept alive further than that would spend its last stretch
## walking over open sky. 150 m is the largest value that keeps every LIVE
## animal (not just every spawn) on solid ground.
const DESPAWN_RADIUS: float = 150.0

## Lateral offset (metres) of the migration line from the player, so a herd
## walks PAST them rather than THROUGH them. Without it the line is aimed
## exactly at the player's position at spawn time (the origin is placed on the
## ray from the player), and the miss distance comes only from the player
## having moved since — which is zero whenever they can't move: the 5 s
## respawn grace freeze, a pause, or the game-over screen. The floor covers
## MEANDER_AMPLITUDE (6) plus the widest formation spread, so a player standing
## still watches the herd pass several metres clear (measured: ~9 m at the
## closest draw). It does NOT make a crossing impossible — a player who runs
## across the migration line can still meet it, which is the accepted
## walk-through ceiling below, not a bug.
const MIGRATION_MISS_MIN: float = 25.0
const MIGRATION_MISS_MAX: float = 60.0

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

## Half-angle (radians) of the cone the migration heading is drawn from, taken
## AGAINST the player's run direction (+X). This is not decoration — it is what
## makes the event visible at all. The player runs down +X for the whole game
## (the coin road's X strictly increases) at 5–11 m/s, several times a herd's
## 2–3 m/s amble, so a uniformly random compass heading would waste most
## events: any herd walking roughly WITH the player is simply outrun and
## despawns far behind the camera, never seen. Spawning ahead down the road and
## walking back through the player's area is the only geometry that reliably
## produces a crossing. ~35° is wide enough that no two migrations arrive on
## the same line, narrow enough that the closing speed stays high.
const MIGRATION_HEADING_SPREAD: float = 0.6

# ============================================================================
# CONSTANTS — herd composition and formation
# ============================================================================

## Elephant family size: a small tight group — 1–2 adults leading, the rest
## calves trailing behind them (see _spawn_herd for the placement rule).
const ELEPHANT_HERD_MIN: int = 3
const ELEPHANT_HERD_MAX: int = 5
const ELEPHANT_ADULTS_MIN: int = 1
const ELEPHANT_ADULTS_MAX: int = 2

## Giraffe flock size: a looser, larger group in a diagonal spread.
const GIRAFFE_FLOCK_MIN: int = 4
const GIRAFFE_FLOCK_MAX: int = 8

## Formation spread (metres): how far members sit from the herd centre,
## sideways (perpendicular to travel) and along the travel direction.
const HERD_SPREAD_LATERAL: float = 6.0
const HERD_SPREAD_LONG: float = 5.0

## How far (metres) behind its parent adult an elephant calf walks.
const CALF_TRAIL_DISTANCE: float = 2.5

## Gentle shared meander: the herd centre swings MEANDER_AMPLITUDE metres
## sideways as sin(travelled * MEANDER_FREQUENCY) — frequency is per METRE
## travelled, not per second, so slower herds meander over the same ground.
## 0.03 gives a ~200 m wavelength: visibly "not a laser line", never a loop.
const MEANDER_AMPLITUDE: float = 6.0
const MEANDER_FREQUENCY: float = 0.03

## How quickly (1/s) each animal eases toward its formation slot. Low on
## purpose: the lag makes members drift in and out of formation like animals,
## not like a rigid parade float.
const FORMATION_LERP_SPEED: float = 1.5

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
# CONSTANTS — procedural walk animation
# ============================================================================
# Same idiom as piglet_crocodile_ai._animate_body: no AnimationPlayer anywhere,
# just sine waves written onto limb pivots. The one twist here is that the
# stride phase is a pure function of METRES WALKED, not of accumulated time —
# see STRIDE_FREQUENCY.

## Radians of stride phase per METRE the herd travels. Tying the stride to
## distance instead of elapsed time does two things for free: feet keep pace
## with the ground at any walk speed (a faster herd steps faster, exactly like
## the crocodile's move_factor-scaled stride), and the phase is stateless — it
## is recomputed from _herd_travelled every frame, so it can never drift.
## 1.6 rad/m at ~2.5 m/s is a ~0.6 Hz gait: a heavy, unhurried big-animal walk.
const STRIDE_FREQUENCY: float = 1.6

## Peak leg swing (degrees about the hip pivot's X axis).
const LEG_SWING_DEG: float = 18.0

## Stride phase offset per leg, in the fixed FL/FR/RL/RR order every builder
## uses. Diagonal pairs move together (front-left with rear-right) and the two
## diagonals are half a cycle apart — a real quadruped trot, which is what a
## walking elephant or giraffe reads as at this distance.
const LEG_PHASE_OFFSETS: Array[float] = [0.0, PI, PI, 0.0]

## Vertical body bob (metres), oscillating at TWICE the stride rate — one dip
## per footfall rather than one per full cycle. Same bob-is-double-the-stride
## relationship as the crocodile's _animate_body.
const BODY_BOB_AMOUNT: float = 0.06

## Giraffe neck bob: a couple of degrees at HALF the stride rate (a long neck
## swings slowly), layered on top of the neck's rest lean — never overwriting
## it, the same compose-on-rest-pose discipline as the crocodile's
## model_base_scale / model_base_y. NECK_BOB_RATE is that "half" as a fraction
## of the stride rate, the neck's counterpart to TRUNK_SWAY_RATE below.
const NECK_BOB_DEG: float = 3.5
const NECK_BOB_RATE: float = 0.5

## Elephant trunk sway (degrees per segment, side to side about Z) and the
## phase LAG between consecutive segments. The lag is what makes the chain read
## as floppy: each segment starts its swing slightly after its parent, so the
## trunk trails in an S instead of swinging as one rigid bar.
const TRUNK_SWAY_DEG: float = 7.0
const TRUNK_SEGMENT_LAG: float = 0.6

## Trunk sway rate as a fraction of the stride rate — slower than the legs, so
## the trunk drifts rather than marching in time with the feet.
const TRUNK_SWAY_RATE: float = 0.7

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

## The live herd's shared movement state. Heading and lateral are fixed unit
## XZ vectors for the herd's whole life (the migration LINE); position is the
## herd centre (y = 0) including the meander; travelled is metres walked,
## which drives the meander phase. All meaningless while _animals is empty.
var _herd_heading: Vector3 = Vector3.ZERO
var _herd_lateral: Vector3 = Vector3.ZERO
var _herd_position: Vector3 = Vector3.ZERO
var _herd_speed: float = 0.0
var _herd_travelled: float = 0.0

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


func _build_elephant(is_adult: bool) -> Dictionary:
	## Assemble one elephant entirely from the shared unit BoxMesh + shared
	## materials. Blocky BY DESIGN: the whole world (decorative blocks, the
	## low-poly character cast) is boxes and flat colours, so a box elephant
	## matches the art direction — a smooth model would look pasted in, and a
	## real mesh would mean an asset file this feature deliberately avoids.
	##
	## Returns the animal RECORD, not just the root: the builder already holds
	## every pivot the animation loop will ever touch, so it hands them over
	## directly rather than making _add_animal rediscover them by node name.
	## The record shape is species-agnostic — root/body/legs (always four, in
	## FL/FR/RL/RR order) plus the extras slot, which for an elephant is the
	## trunk chain and a null neck.
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
	var trunk: Array[Node3D] = []
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
		trunk.append(pivot)

	# Legs, always in FL/FR/RL/RR order — the species-agnostic contract the
	# animation loop relies on (diagonal trot pairs are picked by index).
	var hip_x := ELEPHANT_BODY_SIZE.x * 0.5 - ELEPHANT_LEG_SIZE.x * 0.5
	var hip_z := ELEPHANT_BODY_SIZE.z * 0.5 - ELEPHANT_LEG_SIZE.z * 0.5
	var hip_y := ELEPHANT_LEG_SIZE.y
	var legs: Array[Node3D] = [
		_make_leg("LegFL", Vector3(-hip_x, hip_y, -hip_z), ELEPHANT_LEG_SIZE, mat, body_shadows),
		_make_leg("LegFR", Vector3(hip_x, hip_y, -hip_z), ELEPHANT_LEG_SIZE, mat, body_shadows),
		_make_leg("LegRL", Vector3(-hip_x, hip_y, hip_z), ELEPHANT_LEG_SIZE, mat, body_shadows),
		_make_leg("LegRR", Vector3(hip_x, hip_y, hip_z), ELEPHANT_LEG_SIZE, mat, body_shadows),
	]
	for leg: Node3D in legs:
		body.add_child(leg)

	# A calf is the SAME build scaled once at the root — one scale write, no
	# smaller boxes, no second code path to keep in sync.
	if not is_adult:
		root.scale = Vector3.ONE * CALF_SCALE

	return {
		"root": root,
		"body": body,
		"legs": legs,
		"neck": null,        # elephants have no neck pivot — the trunk is their extra
		"neck_rest": 0.0,    # unused while neck is null; keeps the record one shape
		"trunk": trunk,
	}


func _build_giraffe() -> Dictionary:
	## Assemble one giraffe from the same shared unit BoxMesh + shared
	## materials, and return the SAME record shape as _build_elephant so the
	## animation loop reading it stays species-agnostic: root Node3D (feet at
	## y = 0, faces -Z) -> "Body" Node3D -> four hip-pivot legs in FL/FR/RL/RR
	## order. The only species difference is the extras slot: a giraffe has a
	## neck pivot (elephants: null) and no trunk chain (elephants: 3 segments)
	## — the record simply carries null/empty for the other species' extra.
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
	# Clamped to the hand-picked spot list: the placements are authored, not
	# generated, so raising GIRAFFE_PATCH_COUNT past them must cap out rather
	# than run off the end of the arrays.
	for i: int in mini(GIRAFFE_PATCH_COUNT, patch_offsets.size()):
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
	var legs: Array[Node3D] = [
		_make_leg("LegFL", Vector3(-hip_x, hip_y, -hip_z), GIRAFFE_LEG_SIZE, mat, true),
		_make_leg("LegFR", Vector3(hip_x, hip_y, -hip_z), GIRAFFE_LEG_SIZE, mat, true),
		_make_leg("LegRL", Vector3(-hip_x, hip_y, hip_z), GIRAFFE_LEG_SIZE, mat, true),
		_make_leg("LegRR", Vector3(hip_x, hip_y, hip_z), GIRAFFE_LEG_SIZE, mat, true),
	]
	for leg: Node3D in legs:
		body.add_child(leg)

	return {
		"root": root,
		"body": body,
		"legs": legs,
		"neck": neck,
		# The neck's forward lean is its REST pose: the bob is layered on top of
		# this value, never overwriting it (same discipline as the crocodile's
		# cached model_base_scale / model_base_y).
		"neck_rest": neck.rotation.x,
		"trunk": [] as Array[Node3D],   # giraffes have no trunk chain
	}


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
# CORE (herd spawning, migration movement, animation)
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
	## Build and place one herd on the edge of the field, aimed to walk
	## through the player's general area and out the far side.
	##
	## Placement: pick a heading from the rearward cone (see
	## MIGRATION_HEADING_SPREAD), put the herd origin on the field circle
	## FIELD_RADIUS away — ahead of the player down the road, offset sideways by
	## MIGRATION_MISS so the line passes BESIDE them, not through them — and walk
	## along +heading, so the migration line crosses TOWARD and PAST the player
	## even while they run.
	##
	## The animals are parented to THIS manager, never to a terrain chunk:
	## chunk unloading frees everything under a chunk mesh, and a herd must
	## survive its whole crossing regardless of which chunks come and go.
	##
	## ponytail: the bead's optional elephant trumpet is skipped this cycle —
	## sound_manager.gd is owned by a parallel executor; the upgrade path is a
	## play_*-style one-shot there plus a null-safe "sound_manager" group
	## lookup right here at spawn time.
	if not _animals.is_empty():
		# The ONE-HERD INVARIANT — this early-return IS the perf story: the
		# feature's worst case is a single ≤ 8-animal herd, ever.
		return
	var player := _find_player()
	if player == null:
		return

	# Heading is drawn from a cone facing back down the road (PI = straight
	# against the player's +X run direction) — see MIGRATION_HEADING_SPREAD for
	# why a uniform compass heading would leave most migrations unseen.
	var angle := PI + _rng.randf_range(-MIGRATION_HEADING_SPREAD, MIGRATION_HEADING_SPREAD)
	_herd_heading = Vector3(cos(angle), 0.0, sin(angle))
	# Lateral = heading rotated 90° in the ground plane; with heading, it is
	# the herd-local frame every formation offset is expressed in.
	_herd_lateral = Vector3(-_herd_heading.z, 0.0, _herd_heading.x)
	var player_ground := Vector3(player.global_position.x, 0.0, player.global_position.z)
	# Offset the whole migration line sideways so the herd passes BESIDE the
	# player instead of straight through them (see MIGRATION_MISS_MIN).
	var miss := _rng.randf_range(MIGRATION_MISS_MIN, MIGRATION_MISS_MAX)
	if _rng.randf() < 0.5:
		miss = -miss
	# The along-heading setback shrinks to keep the origin ON the FIELD_RADIUS
	# circle (Pythagoras), not past it — otherwise the lateral offset would push
	# the spawn beyond DESPAWN_RADIUS and the herd would be freed on its first
	# update frame. |miss| < FIELD_RADIUS always, so the root is real.
	var setback := sqrt(FIELD_RADIUS * FIELD_RADIUS - miss * miss)
	_herd_position = player_ground - _herd_heading * setback + _herd_lateral * miss
	_herd_speed = _rng.randf_range(WALK_SPEED_MIN, WALK_SPEED_MAX)
	_herd_travelled = 0.0

	# Build the members with their formation offsets (herd-local lateral/long
	# pairs turned into world-space vectors — heading never changes, so the
	# world-space offset is valid for the herd's whole life).
	if _rng.randf() < ELEPHANT_CHANCE:
		_spawn_elephant_family()
	else:
		_spawn_giraffe_flock()


func _spawn_elephant_family() -> void:
	## An elephant family: 1–2 adults spread abreast at the front, the calves
	## each trailing CALF_TRAIL_DISTANCE behind a randomly chosen adult with a
	## small lateral jitter — the classic "calf shadows its parent" read.
	var herd_size := _rng.randi_range(ELEPHANT_HERD_MIN, ELEPHANT_HERD_MAX)
	var adult_count := mini(_rng.randi_range(ELEPHANT_ADULTS_MIN, ELEPHANT_ADULTS_MAX), herd_size)

	var adult_offsets: Array[Vector3] = []
	for i: int in adult_count:
		# Adults abreast: centred lateral slots at the formation's front.
		var lat := (float(i) - float(adult_count - 1) * 0.5) * HERD_SPREAD_LATERAL
		var offset := _herd_lateral * lat + _herd_heading * _rng.randf_range(0.0, HERD_SPREAD_LONG * 0.4)
		adult_offsets.append(offset)
		_add_animal(_build_elephant(true), offset)
	for i: int in herd_size - adult_count:
		var parent_offset: Vector3 = adult_offsets[_rng.randi_range(0, adult_count - 1)]
		var jitter := _rng.randf_range(-HERD_SPREAD_LATERAL * 0.3, HERD_SPREAD_LATERAL * 0.3)
		var offset := parent_offset - _herd_heading * CALF_TRAIL_DISTANCE + _herd_lateral * jitter
		_add_animal(_build_elephant(false), offset)


func _spawn_giraffe_flock() -> void:
	## A giraffe flock: a loose DIAGONAL spread — each member steps a slot
	## along BOTH the heading and the lateral axis (plus jitter), so the line
	## reads as a staggered echelon rather than a row or a queue.
	var flock_size := _rng.randi_range(GIRAFFE_FLOCK_MIN, GIRAFFE_FLOCK_MAX)
	for i: int in flock_size:
		var step := float(i) - float(flock_size - 1) * 0.5
		var lat := step * HERD_SPREAD_LATERAL * 0.6 + _rng.randf_range(-1.5, 1.5)
		var lon := step * HERD_SPREAD_LONG * 0.5 + _rng.randf_range(-1.5, 1.5)
		_add_animal(_build_giraffe(), _herd_lateral * lat + _herd_heading * lon)


func _add_animal(record: Dictionary, offset: Vector3) -> void:
	## Parent one built animal, place it at its formation slot, face it along
	## the herd heading, and finish its record. The builder already cached every
	## node reference the movement/animation code will ever touch (limb pivots,
	## neck, trunk chain, rest pose), so the per-frame loops never call get_node
	## — and neither does this, there is no lookup anywhere at spawn either.
	##
	## `position`, not `global_position`: the animals hang off this manager, a
	## plain Node with no transform of its own, under Main at identity.
	var root: Node3D = record["root"]
	add_child(root)
	root.position = _herd_position + offset
	root.rotation.y = atan2(-_herd_heading.x, -_herd_heading.z)

	record["offset"] = offset                       # formation slot, world-space
	record["phase"] = _rng.randf_range(0.0, TAU)    # stride offset — no lockstep
	_animals.append(record)


func _update_herd(delta: float) -> void:
	## Advance the shared herd centre along the migration line, ease every
	## member toward its formation slot, and despawn once the crossing is
	## done. Feet stay at y = 0 by construction: the ground is one flat plane
	## at world y = 0 (see endless_terrain.gd), so there is no raycast and no
	## terrain query anywhere in fauna.
	##
	## ponytail: walk-through is the accepted ceiling — no collision bodies
	## and no obstacle avoidance, so a herd may clip a decorative block on its
	## way past; capsule bodies + a cheap forward raycast nudge are the
	## upgrade path if it ever reads badly in play.
	var player := _find_player()
	# Despawn when the crossing is over: the herd centre is measured against
	# the LIVE player position each tick, so "the herd walked past" and "the
	# player ran away from the herd" are the same check. No player at all
	# (scene torn down mid-walk) also ends the event.
	if player == null or _herd_position.distance_to(player.global_position) > DESPAWN_RADIUS:
		_despawn_herd()
		return

	_herd_travelled += _herd_speed * delta
	# Centre = straight line along the heading + the gentle shared meander on
	# the lateral axis, phased by distance walked (see MEANDER_FREQUENCY).
	_herd_position += _herd_heading * (_herd_speed * delta)
	var centre := _herd_position \
			+ _herd_lateral * (sin(_herd_travelled * MEANDER_FREQUENCY) * MEANDER_AMPLITUDE)

	# Facing: the centre's own velocity — the heading plus the meander's
	# derivative, which is exact and needs no previous-frame state. Computed
	# ONCE per frame, not once per animal: every member shares the same centre
	# path, the same formation offset arithmetic and the same ease weight, so
	# every member's motion vector is provably identical and N atan2 calls
	# would all return the same number. Local forward is -Z, hence the negated
	# atan2 arguments.
	var centre_velocity := _herd_heading + _herd_lateral \
			* (cos(_herd_travelled * MEANDER_FREQUENCY) * MEANDER_AMPLITUDE * MEANDER_FREQUENCY)
	var yaw := atan2(-centre_velocity.x, -centre_velocity.z)

	# The ease is a soft, uniform lag on the whole formation (members start
	# exactly on their slots, so nothing here spreads them apart): it takes the
	# edge off the meander's direction changes so the herd swings into a turn
	# instead of snapping onto the new line.
	var ease_weight := minf(1.0, FORMATION_LERP_SPEED * delta)
	for animal: Dictionary in _animals:
		var root: Node3D = animal["root"]
		var target: Vector3 = centre + animal["offset"]
		root.position = root.position.lerp(target, ease_weight)
		root.rotation.y = yaw

	_animate_animals()


func _animate_animals() -> void:
	## The ONE animation loop for every live animal — there are no per-animal
	## scripts and no AnimationPlayer anywhere in this feature, exactly like the
	## player's limb sines and the crocodile's _animate_body.
	##
	## Everything here is a pure function of _herd_travelled (metres walked) plus
	## the animal's own random phase offset, so nothing accumulates and nothing
	## drifts: the herd's stride is literally "where its feet are on the ground".
	## The loop allocates nothing per frame — every node reference was cached by
	## the builder that created it, so there is not one get_node() call in here.
	var leg_swing := deg_to_rad(LEG_SWING_DEG)
	var neck_bob := deg_to_rad(NECK_BOB_DEG)
	var trunk_sway := deg_to_rad(TRUNK_SWAY_DEG)

	for animal: Dictionary in _animals:
		# Per-animal phase offset — the herd is never in lockstep, same reason
		# the crocodiles carry an instance_phase.
		var stride: float = _herd_travelled * STRIDE_FREQUENCY + float(animal["phase"])

		# Legs: swing from the hip, diagonal pairs in trot phase (see
		# LEG_PHASE_OFFSETS). The pivot is at hip height with the box hung
		# below it, so this rotation reads as a real limb swing.
		var legs: Array[Node3D] = animal["legs"]
		for i: int in legs.size():
			legs[i].rotation.x = sin(stride + LEG_PHASE_OFFSETS[i]) * leg_swing

		# Body: one shallow dip per footfall, i.e. twice the stride rate. The
		# curve is offset to sit entirely at or ABOVE the Body node's rest
		# height (0 by construction — neither builder moves it), because the
		# legs hang off Body: a bob that dipped below rest would push every
		# foot through the flat ground plane at y = 0.
		var body: Node3D = animal["body"]
		body.position.y = (sin(stride * 2.0) * 0.5 + 0.5) * BODY_BOB_AMOUNT

		# Giraffe neck: a slow bob layered ON TOP of the rest lean (null for
		# elephants — the record simply carries no neck for that species).
		var neck: Node3D = animal["neck"]
		if neck != null:
			neck.rotation.x = float(animal["neck_rest"]) + sin(stride * NECK_BOB_RATE) * neck_bob

		# Elephant trunk: each chained segment sways side to side one
		# TRUNK_SEGMENT_LAG behind its parent, so the chain trails in a soft S.
		# (Empty for giraffes.)
		var trunk: Array[Node3D] = animal["trunk"]
		for i: int in trunk.size():
			trunk[i].rotation.z = sin(stride * TRUNK_SWAY_RATE - float(i) * TRUNK_SEGMENT_LAG) * trunk_sway


func _despawn_herd() -> void:
	## Free every animal, forget the herd, and re-arm the event timer with the
	## steady-state gap — the field goes back to costing one subtraction per
	## frame until the next migration.
	for animal: Dictionary in _animals:
		(animal["root"] as Node3D).queue_free()
	_animals.clear()
	_event_timer = _rng.randf_range(FAUNA_INTERVAL_MIN, FAUNA_INTERVAL_MAX)
