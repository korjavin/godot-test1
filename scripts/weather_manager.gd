extends Node
## Weather manager: drifting clouds, storm-cloud rain zones, and rare bird flocks.
##
## This one node owns ALL ambient weather. It lives under Main in main.tscn
## (next to SoundManager / CrocodileLODManager) and joins the "weather" group,
## which is how the rest of the game reaches it — group-based discovery plus a
## `has_method` guard, never a hard reference, exactly like every other system
## in this project. With this node absent from a scene, nothing else changes:
## every caller degrades to "no weather" silently.
##
## Why this is deliberately NOT part of endless_terrain.gd: the terrain is the
## *world* engine — everything it spawns is a deterministic pure function of
## chunk coords + run_seed so chunks regenerate byte-identically. Weather is
## *ambience*: clouds drift over chunk boundaries, follow the player rather
## than the grid, and nobody cares whether run 2's clouds match run 1's. So it
## needs none of the terrain's determinism machinery (precedent: crocodile
## size/speed rolls are already `randomize()`d per instance). Keeping it here
## keeps the terrain's determinism contract clean and this file self-contained.
##
## The model: a fixed pool of CLOUD_COUNT blocky cloud clusters floats in a
## FIELD_RADIUS disc around the player, drifting with the wind. A cloud that
## falls too far behind (downwind of) the player is not freed — it is RECYCLED:
## re-rolled and re-placed at the upwind edge, so the field never depletes and
## nothing ever pops into existence in view (the fog + distance hide the seam).

# ============================================================================
# CLOUD TUNABLES
# ============================================================================

## Radius (metres) of the cloud field disc around the player. Clouds live inside
## this circle; a cloud drifting further than this behind the player recycles.
## 250 m comfortably covers the fogged view distance on both platforms.
const FIELD_RADIUS: float = 250.0

## How many cloud clusters exist at once. Fixed pool — never grows, never
## shrinks; recycling keeps all of them in play forever.
const CLOUD_COUNT: int = 26

## Altitude band (metres above ground) the clouds float in. Well above the
## tallest blocks and Windman's Air Rush arc, below "why is the sky empty".
const CLOUD_ALTITUDE_MIN: float = 45.0
const CLOUD_ALTITUDE_MAX: float = 70.0

## Each cloud is a cluster of a few chunky boxes, matching the blocky look of
## the world's decorative cubes. This is the boxes-per-cluster roll range.
const BOXES_PER_CLOUD_MIN: int = 4
const BOXES_PER_CLOUD_MAX: int = 9

## Size range (metres, per axis) for one cloud box. Wide and flat reads more
## "cloud" than cubic, so X/Z roll the full range while Y is halved in
## _make_cloud().
const CLOUD_BOX_SIZE_MIN: float = 6.0
const CLOUD_BOX_SIZE_MAX: float = 14.0

## How far (metres) a box's centre may scatter from its cluster's centre.
## Larger = looser, wispier clusters.
const CLOUD_SPREAD: float = 10.0

## Wind direction, normalized, XZ only (clouds never gain or lose altitude from
## wind — the sine bob below is the only vertical motion). +X is the run
## direction, with a slight sideways drift so the motion reads in 3D.
const WIND_DIR: Vector3 = Vector3(0.9701425, 0.0, 0.2425356)  # normalize(4, 0, 1)

## Base wind speed (m/s). Slow — clouds should feel far away and lazy.
const WIND_SPEED: float = 1.6

## Per-cloud speed variation (fraction of WIND_SPEED, ±). Uniform speed looks
## like a printed backdrop scrolling; a little spread sells depth.
const CLOUD_SPEED_VARIATION: float = 0.25

## Gentle vertical sine bob so a stared-at cloud isn't perfectly rigid.
const BOB_AMPLITUDE: float = 1.5
const BOB_SPEED: float = 0.3

## Throttled tick period (seconds), same discipline as crocodile_lod_manager's
## SCAN_INTERVAL: cloud work runs at ~10 Hz, not per frame. At WIND_SPEED
## 1.6 m/s a 0.1 s step moves a cloud ~16 cm — invisible on an object 50 m up.
const TICK_INTERVAL: float = 0.1

# ============================================================================
# STATE
# ============================================================================

## Cosmetic-only RNG, `randomize()`d in _ready(). This is deliberately NOT the
## terrain's deterministic chunk RNG and never touches it: cloud shapes and
## positions are pure ambience, so fresh randomness every run is correct here
## (same precedent as the crocodiles' randomize()d size/speed rolls).
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## The cloud field: one Dictionary per cloud —
##   { "center": Vector3,   # world-space cluster centre (drifts with the wind)
##     "boxes": Array,      # per-box { "offset": Vector3, "size": Vector3, "yaw": float }
##     "is_storm": bool,    # dark rain-carrying cloud (rolled in a later task)
##     "radius": float,     # ground rain-zone radius (storm clouds only)
##     "speed": float,      # this cloud's wind speed (WIND_SPEED ± variation)
##     "bob_phase": float } # phase offset so the field doesn't bob in unison
var _clouds: Array = []

## Cached player reference — looked up via the "player" group, re-fetched when
## invalid, never a hard reference (project convention). While there is no
## player (scene mid-load, or a scene without one), the manager does nothing.
var _player: Node3D = null

## Accumulator for the throttled tick.
var _tick_accum: float = 0.0


# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	add_to_group("weather")
	_rng.randomize()


func _process(delta: float) -> void:
	# Throttle: all cloud work happens on the ~10 Hz tick, so on most frames
	# this function is a single accumulate-and-return.
	_tick_accum += delta
	if _tick_accum < TICK_INTERVAL:
		return
	var elapsed: float = _tick_accum
	_tick_accum = 0.0

	# Re-acquire the player if needed; with no player in the tree the whole
	# manager idles (nothing to centre the field on).
	if not is_instance_valid(_player):
		_find_player()
		if not is_instance_valid(_player):
			return
	var player_pos: Vector3 = _player.global_position

	# First tick with a live player: fill the cloud field around them.
	# (Lazy init rather than _ready() because the player may not exist yet.)
	if _clouds.is_empty():
		for i in CLOUD_COUNT:
			var cloud: Dictionary = _make_cloud()
			_place_cloud_around(cloud, player_pos, false)
			_clouds.append(cloud)

	_update_clouds(player_pos, elapsed)


# ============================================================================
# CLOUD FIELD
# ============================================================================

func _find_player() -> void:
	## Group-based player lookup, identical to crocodile_lod_manager.gd.
	var player := get_tree().get_first_node_in_group("player")
	if player is Node3D:
		_player = player
	else:
		_player = null


func _make_cloud() -> Dictionary:
	## Roll one cloud cluster: a handful of flat-ish boxes scattered around a
	## shared centre. Position is left at ZERO — _place_cloud_around() sets it.
	var boxes: Array = []
	var box_count: int = _rng.randi_range(BOXES_PER_CLOUD_MIN, BOXES_PER_CLOUD_MAX)
	for i in box_count:
		boxes.append({
			"offset": Vector3(
				_rng.randf_range(-CLOUD_SPREAD, CLOUD_SPREAD),
				_rng.randf_range(-CLOUD_SPREAD, CLOUD_SPREAD) * 0.3,
				_rng.randf_range(-CLOUD_SPREAD, CLOUD_SPREAD)),
			# Wide and flat: full-range X/Z, half-height Y reads as a cloud slab.
			"size": Vector3(
				_rng.randf_range(CLOUD_BOX_SIZE_MIN, CLOUD_BOX_SIZE_MAX),
				_rng.randf_range(CLOUD_BOX_SIZE_MIN, CLOUD_BOX_SIZE_MAX) * 0.5,
				_rng.randf_range(CLOUD_BOX_SIZE_MIN, CLOUD_BOX_SIZE_MAX)),
			"yaw": _rng.randf_range(0.0, TAU),
		})
	return {
		"center": Vector3.ZERO,
		"boxes": boxes,
		"is_storm": false,  # storm roll + zone radius arrive in the storm task
		"radius": 0.0,
		"speed": WIND_SPEED * (1.0 + _rng.randf_range(-CLOUD_SPEED_VARIATION, CLOUD_SPEED_VARIATION)),
		"bob_phase": _rng.randf_range(0.0, TAU),
	}


func _place_cloud_around(cloud: Dictionary, player_pos: Vector3, ahead_only: bool) -> void:
	## Position a cloud in the field disc around the player at a fresh altitude.
	## Initial fill (`ahead_only = false`): anywhere in the disc, so the sky is
	## populated in every direction from frame one. Recycling
	## (`ahead_only = true`): only along the UPWIND edge — the cloud re-enters
	## far away where the fog hides it and drifts back across the field, so the
	## player never sees one pop in.
	var pos: Vector3
	if ahead_only:
		# A point on the upwind semicircle rim: start FIELD_RADIUS upwind of the
		# player, then swing up to ±90° around them so re-entries spread out.
		var angle: float = _rng.randf_range(-PI * 0.5, PI * 0.5)
		pos = player_pos + (-WIND_DIR * FIELD_RADIUS).rotated(Vector3.UP, angle)
	else:
		# Uniform-ish point in the disc (sqrt for area-uniform radial density).
		var angle: float = _rng.randf_range(0.0, TAU)
		var dist: float = FIELD_RADIUS * sqrt(_rng.randf())
		pos = player_pos + Vector3(cos(angle), 0.0, sin(angle)) * dist
	pos.y = _rng.randf_range(CLOUD_ALTITUDE_MIN, CLOUD_ALTITUDE_MAX)
	cloud["center"] = pos


func _update_clouds(player_pos: Vector3, elapsed: float) -> void:
	## One throttled tick of cloud simulation: drift each cluster with the wind
	## and recycle any that fell too far behind. (Rendering — writing the
	## MultiMesh instance transforms — is added by the rendering task.)
	for cloud in _clouds:
		cloud["center"] += WIND_DIR * cloud["speed"] * elapsed
		# "Behind" = along-wind offset from the player, projected onto WIND_DIR.
		var to_cloud: Vector3 = cloud["center"] - player_pos
		to_cloud.y = 0.0
		if to_cloud.dot(WIND_DIR) > FIELD_RADIUS:
			# Drifted past the downwind edge: re-roll shape + re-enter upwind.
			var fresh: Dictionary = _make_cloud()
			cloud["boxes"] = fresh["boxes"]
			cloud["speed"] = fresh["speed"]
			cloud["bob_phase"] = fresh["bob_phase"]
			_place_cloud_around(cloud, player_pos, true)
