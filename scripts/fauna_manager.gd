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
# for the whole feature is a small constant (2 species + 1 accent), no matter
# how many animals spawn over a session. Never duplicate() these per animal —
# that would defeat batching and grow memory with every herd.

static var _shared_box_mesh: BoxMesh = null
static var _elephant_material: StandardMaterial3D = null
static var _giraffe_material: StandardMaterial3D = null
static var _accent_material: StandardMaterial3D = null


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
	## The ONE accent material, shared across species for the small trim
	## pieces (off-white elephant tusks, and it doubles for giraffe details
	## where an off-white read is fine). Keeping accents on a single shared
	## material caps the feature's total material count at a constant 3.
	if _accent_material == null:
		_accent_material = StandardMaterial3D.new()
		_accent_material.albedo_color = Color(0.92, 0.90, 0.82)
		_accent_material.roughness = 0.7
	return _accent_material


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
