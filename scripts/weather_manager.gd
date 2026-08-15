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
##
## ponytail: two optional extras from the design were deliberately NOT built.
## (1) A full-screen darkening ColorRect while inside a rain zone — a screen-
## sized alpha blend is exactly the mobile fill-rate cost this project's perf
## conventions warn about, for mood the particles + audio already carry; add it
## if playtesting says the rain reads too cheerful. (2) A distant bird caw
## one-shot — it would mean growing sound_manager.gd (a file parallel work
## keeps touching) for one rare noise; add it there beside the other _synth_*
## helpers if the flocks ever feel too silent.

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

## Base colour of a normal cloud: near-white, faintly warm. Each cloud jitters
## its brightness a little (± CLOUD_BRIGHTNESS_JITTER, rolled once per cloud)
## so the field doesn't read as one flat white stamp.
const CLOUD_COLOR: Color = Color(0.93, 0.94, 0.96)
const CLOUD_BRIGHTNESS_JITTER: float = 0.07

## Storm clouds render this dark blue-grey.
const STORM_COLOR: Color = Color(0.32, 0.34, 0.42)

## Chance a freshly rolled cloud is a storm cloud (~1 in 7 → with 26 clouds,
## roughly 3–4 storms in the sky at any moment).
const STORM_CHANCE: float = 1.0 / 7.0

## Storm clouds are beefier than fair-weather ones: box count and box size are
## both multiplied by this, so a storm visibly looms rather than being a white
## cloud recoloured dark.
const STORM_SIZE_FACTOR: float = 1.5

## Ground rain-zone radius = this × the cloud's actual visual cluster radius
## (measured from its rolled boxes, not a constant), so the wet footprint on
## the ground matches what the player sees overhead. Slightly over 1 so the
## zone edge isn't pixel-tight to the silhouette.
const RAIN_ZONE_FACTOR: float = 1.2

# ============================================================================
# RAIN PARTICLE TUNABLES
# ============================================================================

## Live particle budget for the rain. 120 thin streaks recycled continuously
## reads as steady rain without denting the web frame budget.
const RAIN_PARTICLE_COUNT: int = 120

## How high above the player's position the emitter box sits. High enough that
## streaks are already at full speed when they cross eye level.
const RAIN_SPAWN_HEIGHT: float = 14.0

## Half-extent (metres, X and Z) of the emission box around the player — the
## visible "it is raining here" bubble that follows them through the zone.
const RAIN_AREA_EXTENT: float = 12.0

## Fall speed (m/s) and streak lifetime. Lifetime is sized so a streak spawned
## RAIN_SPAWN_HEIGHT up at this speed falls just past ground level, then recycles.
const RAIN_FALL_SPEED: float = 20.0
const RAIN_LIFETIME: float = 0.9

## Streak mesh dimensions: a thin elongated box motion-stretched by eye.
const RAIN_STREAK_SIZE: Vector3 = Vector3(0.03, 0.7, 0.03)

## Pale grey-blue, unshaded — rain should read as neutral streaks, not lit geometry.
const RAIN_COLOR: Color = Color(0.65, 0.70, 0.78)

# ============================================================================
# RAIN AUDIO TUNABLES
# ============================================================================

## Rain loop level when fully faded in. Louder than the -26 dB ambient wind
## bed (rain should be *noticed*), still below the -6..-10 dB one-shots.
const RAIN_VOLUME_DB: float = -14.0

## "Fully faded out" floor. -60 dB is inaudible; once the fade reaches it the
## player is stop()ped entirely so no silent voice is left mixing.
const RAIN_SILENT_DB: float = -60.0

## Seconds for the full silent↔audible fade on rain-zone enter/exit.
const RAIN_FADE_TIME: float = 1.5

## How much the ambient wind bed ducks (dB, negative) while rain is audible,
## scaled by the same fade progress so the two beds trade places smoothly.
const WIND_DUCK_DB: float = -6.0

## Rain loop synthesis (mirrors sound_manager._synth_wind(), kept LOCAL so
## sound_manager.gd stays untouched): ~2 s of one-pole low-passed noise with a
## crossfaded loop seam. The filter factor is much larger than the wind's 0.02
## — less filtering keeps the noise bright and hissy, which is what reads as
## "rain" instead of "distant rumble".
const RAIN_LOOP_DURATION: float = 2.0
const RAIN_LOWPASS: float = 0.25
const RAIN_CROSSFADE: float = 0.05      # seconds blended across the loop seam
const RAIN_MIX_RATE: int = 22050        # matches sound_manager.MIX_RATE

# ============================================================================
# BIRD TUNABLES
# ============================================================================
# Birds are pure ambience: no collision, no AI, no interaction, nothing to
# collect. A flock crosses the sky now and then purely so the world feels
# inhabited, then despawns. They are RARE by design — seen too often they stop
# being a moment and become wallpaper.

## Seconds between flocks (rolled fresh after each flock leaves).
const BIRD_INTERVAL_MIN: float = 60.0
const BIRD_INTERVAL_MAX: float = 120.0

## How many birds in one flock. BIRD_FLOCK_MAX sizes the MultiMesh allocation.
const BIRD_FLOCK_MIN: int = 3
const BIRD_FLOCK_MAX: int = 7

## Cruising altitude band (metres). Below the clouds (45–70 m) so they read as
## clearly nearer, well above anything the player can reach.
const BIRD_ALTITUDE_MIN: float = 30.0
const BIRD_ALTITUDE_MAX: float = 40.0

## Flight speed (m/s) — much faster than the clouds, which is what makes a
## flock read as a living thing rather than more weather.
const BIRD_SPEED: float = 9.0

## Distance (metres) from the player the flock spawns at / despawns past. It
## enters and leaves well outside the fogged view distance, so no popping.
const BIRD_SPAWN_DISTANCE: float = 160.0
const BIRD_DESPAWN_DISTANCE: float = 200.0

## Wing beats per second, and how far (radians) a wing swings up/down from
## level at the extremes of the beat.
const BIRD_FLAP_HZ: float = 3.0
const BIRD_FLAP_ANGLE: float = 0.6

## Gentle vertical bob along the flight path (metres / cycles per second), so
## the flock undulates instead of sliding along a ruler.
const BIRD_BOB_AMPLITUDE: float = 0.5
const BIRD_BOB_SPEED: float = 0.8

## Body box (local axes: X = across, Y = up, Z = along the flight direction) and
## one wing's box. Small — at 30–40 m these are specks with moving wings, which
## is exactly the silhouette that reads as "bird".
const BIRD_BODY_SIZE: Vector3 = Vector3(0.25, 0.25, 0.9)
const BIRD_WING_SIZE: Vector3 = Vector3(1.1, 0.05, 0.35)

## How far flock-mates scatter from the leader (metres, per axis).
const BIRD_FLOCK_SPREAD: float = 6.0

## Dark silhouette colour — a bird against a bright sky is a shadow, not a
## lit object, so the material is unshaded and simply dark.
const BIRD_COLOR: Color = Color(0.12, 0.13, 0.16)

## Instances per bird in the MultiMesh: body + left wing + right wing.
const BIRD_PARTS: int = 3

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
##     "is_storm": bool,    # dark rain-carrying cloud
##     "radius": float,     # ground rain-zone radius (storm clouds only, else 0)
##     "speed": float,      # this cloud's wind speed (WIND_SPEED ± variation)
##     "bob_phase": float } # phase offset so the field doesn't bob in unison
var _clouds: Array = []

## Cached player reference — looked up via the "player" group, re-fetched when
## invalid, never a hard reference (project convention). While there is no
## player (scene mid-load, or a scene without one), the manager does nothing.
var _player: Node3D = null

## Whether the player currently stands inside any storm cloud's rain zone.
## Recomputed once per throttled tick (not per frame) so later systems (rain
## particles, audio fades) see clean enter/exit transitions at ~10 Hz.
var _player_in_rain: bool = false

## Accumulator for the throttled tick.
var _tick_accum: float = 0.0

## Running clock for the sine bob (advanced on the tick — the bob is only ever
## rendered on the tick, so a finer clock would be wasted precision).
var _time: float = 0.0

## The one draw call for the whole cloud field: a single MultiMeshInstance3D
## holding every box of every cloud (see _build_cloud_multimesh()).
var _cloud_mmi: MultiMeshInstance3D = null

## The one rain emitter (see _build_rain_particles()). `emitting` is flipped
## ONLY on the _player_in_rain enter/exit transition, so outside a rain zone
## the entire rain path costs nothing beyond the manager's own tick.
var _rain: CPUParticles3D = null

## The rain loop stream, synthesized once in _ready() (see _synth_rain_stream()).
var _rain_stream: AudioStreamWAV = null

## The sound manager's dedicated "rain" loop voice (from get_loop_player()) and
## its "wind" bed, both fetched lazily via the "sound_manager" group behind
## has_method guards — with no sound manager in the scene the rain is simply
## silent, no errors (same degradation rule as player_controller._sfx()).
var _rain_player: AudioStreamPlayer = null
var _wind_bed: AudioStreamPlayer = null

## The wind bed's own volume, captured ONCE the first time we duck it (never
## assumed to be a constant — the sound manager owns that number). Ducking is
## always expressed relative to this, so the bed restores exactly.
var _wind_base_db: float = 0.0

## Rain audio fade progress, 0 (silent) .. 1 (full), moved toward the
## _player_in_rain target at 1/RAIN_FADE_TIME per second on the throttled tick.
var _rain_mix: float = 0.0

## The one draw call for a bird flock (body + 2 wings per bird). Empty of
## visible geometry — every instance parked at zero scale — while no flock is
## in the air, which is nearly all the time.
var _bird_mmi: MultiMeshInstance3D = null

## The live flock: one Dictionary per bird —
##   { "pos": Vector3,      # world position (advanced every frame)
##     "phase": float }     # per-bird wing-beat + bob phase offset
## Empty between flocks.
var _birds: Array = []

## Flight direction of the current flock (unit, XZ) and seconds until the next
## flock spawns (rolled from BIRD_INTERVAL_MIN/MAX after each one leaves).
var _bird_dir: Vector3 = Vector3.FORWARD
var _bird_timer: float = 0.0

## Running clock for the wing beat. Separate from _time because birds are
## updated EVERY frame while _time only advances on the 10 Hz tick.
var _bird_time: float = 0.0


# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	add_to_group("weather")
	_rng.randomize()
	_build_cloud_multimesh()
	_build_rain_particles()
	_build_bird_multimesh()
	_rain_stream = _synth_rain_stream()
	_bird_timer = _rng.randf_range(BIRD_INTERVAL_MIN, BIRD_INTERVAL_MAX)


func _process(delta: float) -> void:
	# Birds are the ONE thing updated every frame — a 3 Hz wing beat sampled at
	# the 10 Hz cloud tick would alias into a stutter. It is affordable because
	# a flock is at most BIRD_FLOCK_MAX birds and exists only for the few
	# seconds of a crossing; between flocks this call is a timer decrement.
	_update_birds(delta)

	# Throttle: all cloud work happens on the ~10 Hz tick, so on most frames
	# the rest of this function is a single accumulate-and-return.
	_tick_accum += delta
	if _tick_accum < TICK_INTERVAL:
		return
	var elapsed: float = _tick_accum
	_tick_accum = 0.0
	_time += elapsed

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

	# Rain state: recomputed once per tick (not per frame) so downstream
	# systems (particles, audio fades) get clean ~10 Hz enter/exit transitions.
	var now_in_rain: bool = is_raining_at(player_pos)
	if now_in_rain != _player_in_rain:
		_player_in_rain = now_in_rain
		# Transition-only toggle: while dry, the emitter is fully off and the
		# rain path costs nothing.
		_rain.emitting = now_in_rain
	if _player_in_rain:
		# Follow the player through the zone (throttled tick only — streaks are
		# world-space, so the box lagging a step behind is invisible).
		_rain.global_position = player_pos + Vector3(0.0, RAIN_SPAWN_HEIGHT, 0.0)

	_update_rain_audio(elapsed)


# ============================================================================
# CLOUD RENDERING — one MultiMesh, one draw call
# ============================================================================

func _build_cloud_multimesh() -> void:
	## Same batching pattern as endless_terrain's per-chunk block MultiMesh:
	## one shared unit BoxMesh, per-instance transform carries the box size,
	## per-instance colour carries the cloud tint — the entire sky costs ONE
	## draw call regardless of cloud count.
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = BoxMesh.new()  # unit box; per-instance basis scales it
	# ponytail: fixed allocation at the worst case (every cloud rolls max boxes);
	# unused slots are parked with a zero-scale basis instead of repacking the
	# buffer each tick — cheaper and simpler, the GPU skips degenerate boxes.
	mm.instance_count = CLOUD_COUNT * BOXES_PER_CLOUD_MAX
	var parked := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	for i in mm.instance_count:
		mm.set_instance_transform(i, parked)

	# ONE shared material for every box. Soft matte white: full roughness, no
	# specular glint (a sun highlight on a "cloud" reads as plastic). NO
	# transparency — alpha-blended sky quads this big are mobile fill-rate
	# poison (every covered pixel pays blend cost); opaque blocky clouds match
	# the world's look and cost nothing extra.
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.metallic_specular = 0.0

	_cloud_mmi = MultiMeshInstance3D.new()
	_cloud_mmi.multimesh = mm
	_cloud_mmi.material_override = mat
	# Shadows off: directional_shadow_max_distance is tuned to ~55 m, so clouds
	# at 45–70 m altitude are outside the shadow range anyway — casting would
	# add them to the shadow passes for nothing. Don't fight the tuning.
	_cloud_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cloud_mmi)


func _write_cloud_instances() -> void:
	## Write every instance transform + colour for the whole field. Runs on the
	## ~10 Hz tick only; ~234 transform writes at 10 Hz is negligible.
	var mm: MultiMesh = _cloud_mmi.multimesh
	var parked := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	for ci in _clouds.size():
		var cloud: Dictionary = _clouds[ci]
		var bob: float = sin(_time * BOB_SPEED * TAU + cloud["bob_phase"]) * BOB_AMPLITUDE
		var center: Vector3 = cloud["center"] + Vector3(0.0, bob, 0.0)
		var boxes: Array = cloud["boxes"]
		var color: Color = STORM_COLOR if cloud["is_storm"] \
				else CLOUD_COLOR * cloud["brightness"]
		for bi in BOXES_PER_CLOUD_MAX:
			var idx: int = ci * BOXES_PER_CLOUD_MAX + bi
			if bi < boxes.size():
				var box: Dictionary = boxes[bi]
				# scaled_local (not scaled): the size applies along the box's OWN
				# axes after the yaw, exactly like the terrain's block MultiMesh —
				# scaling world axes after a rotation shears a non-cubic box.
				var basis := Basis(Vector3.UP, box["yaw"]).scaled_local(box["size"])
				mm.set_instance_transform(idx, Transform3D(basis, center + box["offset"]))
				mm.set_instance_color(idx, color)
			else:
				# Unused slot for this cloud (it rolled fewer than max boxes).
				mm.set_instance_transform(idx, parked)


# ============================================================================
# RAIN PARTICLES
# ============================================================================

func _build_rain_particles() -> void:
	## ONE CPUParticles3D for all rain — NOT GPUParticles3D, because the web
	## build runs gl_compatibility where GPU particles are unsupported/flaky;
	## 120 CPU-simulated streaks is nothing. Starts silent (`emitting = false`)
	## and is only ever toggled on the rain-zone enter/exit transition.
	_rain = CPUParticles3D.new()
	_rain.emitting = false
	_rain.amount = RAIN_PARTICLE_COUNT
	# World-space streaks: the emitter box follows the player, but already-
	# spawned drops must keep falling straight where they are, not drag along.
	_rain.local_coords = false
	_rain.lifetime = RAIN_LIFETIME
	# Fast vertical fall with a slight lean along the wind, so the rain visibly
	# belongs to the same weather as the drifting clouds above it.
	_rain.direction = (Vector3.DOWN + WIND_DIR * 0.15).normalized()
	_rain.spread = 0.0
	_rain.initial_velocity_min = RAIN_FALL_SPEED
	_rain.initial_velocity_max = RAIN_FALL_SPEED * 1.25
	_rain.gravity = Vector3.ZERO  # constant terminal velocity; no accel needed

	# Spawn drops in a flat box above the player's head covering the play area.
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(RAIN_AREA_EXTENT, 1.0, RAIN_AREA_EXTENT)

	# Thin elongated streak, unshaded pale grey-blue — one shared mesh+material
	# for every drop.
	var streak := BoxMesh.new()
	streak.size = RAIN_STREAK_SIZE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = RAIN_COLOR
	streak.material = mat
	_rain.mesh = streak
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rain)


# ============================================================================
# RAIN AUDIO — fade the rain loop in/out, duck the wind bed under it
# ============================================================================

func _update_rain_audio(elapsed: float) -> void:
	## One throttled tick of the rain audio state machine (see the plan's
	## Technical Details): _rain_mix chases the in-rain target at
	## 1/RAIN_FADE_TIME per second, and both beds' volumes are pure functions
	## of it. 10 Hz volume steps on a noise bed are inaudible.
	var target: float = 1.0 if _player_in_rain else 0.0
	if _rain_mix == 0.0 and target == 0.0:
		return  # dry and fully faded out — the whole audio path costs nothing
	_rain_mix = move_toward(_rain_mix, target, elapsed / RAIN_FADE_TIME)

	# Null-safe group lookup, same shape as player_controller._sfx(): no sound
	# manager (or a freed one) → silently do nothing, never error.
	var sm := get_tree().get_first_node_in_group("sound_manager")
	if sm == null or not sm.has_method("get_loop_player"):
		return
	if not is_instance_valid(_rain_player):
		_rain_player = sm.get_loop_player("rain")
		_rain_player.stream = _rain_stream  # assigned once; the voice keeps it
	if not is_instance_valid(_wind_bed):
		_wind_bed = sm.get_loop_player("wind")
		_wind_base_db = _wind_bed.volume_db  # capture, don't assume a constant

	_rain_player.volume_db = lerpf(RAIN_SILENT_DB, RAIN_VOLUME_DB, _rain_mix)
	_wind_bed.volume_db = _wind_base_db + WIND_DUCK_DB * _rain_mix

	if _rain_mix > 0.0:
		# Start the loop on the way up — but only once the browser-gesture gate
		# is open (get_loop_player voices are NOT guarded by the manager's own
		# play_* gate, so we must check is_unlocked() ourselves). If the unlock
		# lands mid-rain, a later tick starts the loop then.
		if not _rain_player.playing and sm.has_method("is_unlocked") and sm.is_unlocked():
			_rain_player.play()
	elif _rain_player.playing:
		# Faded fully back to 0: stop the voice so it doesn't sit in the mix
		# silently forever. The wind duck is exactly 0 here, so the bed is
		# restored to its captured base on this same tick.
		_rain_player.stop()


func _synth_rain_stream() -> AudioStreamWAV:
	## The rain bed: ~2 s of LIGHTLY low-passed noise, looped forever — the
	## same recipe as sound_manager._synth_wind() but with a much brighter
	## filter (RAIN_LOWPASS 0.25 vs the wind's 0.02), because retained hiss is
	## what makes noise read as rain. Synthesis lives HERE, not in
	## sound_manager.gd, purely to keep that file untouched (zero merge
	## surface with the parallel executors editing it).
	##
	## Loop-seam trick (same as the wind): synthesize a surplus tail, then
	## crossfade it into the head so sample[frames] (which playback wraps to
	## sample[0]) transitions smoothly instead of clicking.
	var fade_frames: int = int(RAIN_CROSSFADE * RAIN_MIX_RATE)
	var frames: int = int(RAIN_LOOP_DURATION * RAIN_MIX_RATE)
	var raw := PackedFloat32Array()
	var filtered: float = 0.0
	for i in range(frames + fade_frames):  # surplus tail for the crossfade
		filtered += RAIN_LOWPASS * (_rng.randf_range(-1.0, 1.0) - filtered)
		raw.append(filtered * 1.4)  # mild filtering eats little amplitude
	var samples := raw.slice(0, frames)
	for i in range(fade_frames):
		var blend: float = float(i) / fade_frames  # 0 at seam → 1 into the head
		samples[i] = raw[frames + i] * (1.0 - blend) + samples[i] * blend

	# float → 16-bit mono PCM, a local copy of sound_manager._build_wav() (kept
	# here for the same untouched-file reason as the synthesis above).
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)  # 2 bytes per 16-bit frame
	for i in range(samples.size()):
		var s: int = clampi(int(samples[i] * 32767.0), -32768, 32767)
		bytes[i * 2] = s & 0xFF
		bytes[i * 2 + 1] = (s >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RAIN_MIX_RATE
	wav.stereo = false
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = frames
	return wav


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
	var is_storm: bool = _rng.randf() < STORM_CHANCE
	# Storms loom: more boxes AND bigger boxes than a fair-weather cloud.
	# BOXES_PER_CLOUD_MAX already accounts for the storm count ceiling, so the
	# fixed MultiMesh allocation never overflows.
	var size_factor: float = STORM_SIZE_FACTOR if is_storm else 1.0
	var boxes: Array = []
	var box_count: int = mini(
			int(_rng.randi_range(BOXES_PER_CLOUD_MIN, BOXES_PER_CLOUD_MAX) * size_factor),
			BOXES_PER_CLOUD_MAX)
	# Visual cluster radius (XZ, from centre to a box's far edge) — measured
	# from the ACTUAL rolled boxes so the storm's ground rain zone matches the
	# silhouette the player sees overhead, not a one-size constant.
	var cluster_radius: float = 0.0
	for i in box_count:
		var offset := Vector3(
				_rng.randf_range(-CLOUD_SPREAD, CLOUD_SPREAD),
				_rng.randf_range(-CLOUD_SPREAD, CLOUD_SPREAD) * 0.3,
				_rng.randf_range(-CLOUD_SPREAD, CLOUD_SPREAD))
		# Wide and flat: full-range X/Z, half-height Y reads as a cloud slab.
		var size := Vector3(
				_rng.randf_range(CLOUD_BOX_SIZE_MIN, CLOUD_BOX_SIZE_MAX),
				_rng.randf_range(CLOUD_BOX_SIZE_MIN, CLOUD_BOX_SIZE_MAX) * 0.5,
				_rng.randf_range(CLOUD_BOX_SIZE_MIN, CLOUD_BOX_SIZE_MAX)) * size_factor
		boxes.append({
			"offset": offset,
			"size": size,
			"yaw": _rng.randf_range(0.0, TAU),
		})
		cluster_radius = maxf(cluster_radius,
				Vector2(offset.x, offset.z).length() + maxf(size.x, size.z) * 0.5)
	return {
		"center": Vector3.ZERO,
		"boxes": boxes,
		"is_storm": is_storm,
		"radius": cluster_radius * RAIN_ZONE_FACTOR if is_storm else 0.0,
		"speed": WIND_SPEED * (1.0 + _rng.randf_range(-CLOUD_SPEED_VARIATION, CLOUD_SPEED_VARIATION)),
		"bob_phase": _rng.randf_range(0.0, TAU),
		# Per-cloud brightness multiplier on CLOUD_COLOR (storms ignore it).
		"brightness": 1.0 + _rng.randf_range(-CLOUD_BRIGHTNESS_JITTER, CLOUD_BRIGHTNESS_JITTER),
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
	## One throttled tick of cloud simulation: drift each cluster with the wind,
	## recycle any that fell too far behind, then push the whole field into the
	## MultiMesh.
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
			cloud["brightness"] = fresh["brightness"]
			cloud["is_storm"] = fresh["is_storm"]
			cloud["radius"] = fresh["radius"]
			_place_cloud_around(cloud, player_pos, true)
	_write_cloud_instances()


# ============================================================================
# RAIN ZONES — the gameplay-facing weather API
# ============================================================================

func is_raining_at(world_pos: Vector3) -> bool:
	## True if `world_pos` stands inside any storm cloud's ground rain zone —
	## a flat XZ circle test against each storm cloud's moving centre. Only
	## ~1 in 7 of the 26 clouds is a storm, so this is a few
	## distance_squared_to calls: cheap enough to call per-frame from the
	## player (the Windman hooks do exactly that).
	for cloud in _clouds:
		if not cloud["is_storm"]:
			continue
		var center: Vector3 = cloud["center"]
		var radius: float = cloud["radius"]
		if Vector2(world_pos.x - center.x, world_pos.z - center.z).length_squared() \
				<= radius * radius:
			return true
	return false


# ============================================================================
# BIRDS — rare flocks crossing the sky (ambience only)
# ============================================================================

func _build_bird_multimesh() -> void:
	## Second (and last) MultiMesh of this manager: every part of every bird in
	## one draw call, same batching pattern as the clouds. Sized for the biggest
	## possible flock and parked at zero scale, so while no flock is in the air
	## it draws nothing at all — a MultiMesh whose instances are all degenerate
	## costs one skipped draw, not one per bird.
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()  # the same unit box the clouds use, per-instance scaled
	mm.instance_count = BIRD_FLOCK_MAX * BIRD_PARTS

	# Flat dark silhouette: a bird seen against a bright sky is a shadow, so
	# unshaded is both cheaper AND more correct than lighting it.
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = BIRD_COLOR

	_bird_mmi = MultiMeshInstance3D.new()
	_bird_mmi.multimesh = mm
	_bird_mmi.material_override = mat
	_bird_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bird_mmi)
	_park_bird_instances()


func _park_bird_instances() -> void:
	## Collapse every bird instance to zero scale — the "no flock" state.
	var mm: MultiMesh = _bird_mmi.multimesh
	var parked := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	for i in mm.instance_count:
		mm.set_instance_transform(i, parked)


func _update_birds(delta: float) -> void:
	## Per-frame bird step. Between flocks (the common case) this is a timer
	## decrement and an early return.
	if _birds.is_empty():
		_bird_timer -= delta
		if _bird_timer <= 0.0 and is_instance_valid(_player):
			_spawn_flock(_player.global_position)
		return

	_bird_time += delta
	for bird in _birds:
		bird["pos"] += _bird_dir * BIRD_SPEED * delta
	_write_bird_instances()

	# The flock leads with _birds[0]; once IT is far past the player the whole
	# flock has crossed, so retire them and roll the next wait.
	if is_instance_valid(_player):
		var lead: Vector3 = _birds[0]["pos"] - _player.global_position
		if Vector2(lead.x, lead.z).length() > BIRD_DESPAWN_DISTANCE:
			_birds.clear()
			_park_bird_instances()
			_bird_timer = _rng.randf_range(BIRD_INTERVAL_MIN, BIRD_INTERVAL_MAX)
	else:
		# Player vanished mid-crossing (scene change) — drop the flock rather
		# than leaving it flying forever with nothing to measure against.
		_birds.clear()
		_park_bird_instances()
		_bird_timer = _rng.randf_range(BIRD_INTERVAL_MIN, BIRD_INTERVAL_MAX)


func _spawn_flock(player_pos: Vector3) -> void:
	## Launch one flock on a straight crossing near the player: pick a random
	## heading, start BIRD_SPAWN_DISTANCE upstream of a point beside the player,
	## and scatter the flock-mates around the leader.
	var heading: float = _rng.randf_range(0.0, TAU)
	_bird_dir = Vector3(cos(heading), 0.0, sin(heading))
	# Offset the crossing line sideways so flocks don't always fly right at the
	# player's head.
	var side: Vector3 = _bird_dir.cross(Vector3.UP) * _rng.randf_range(-60.0, 60.0)
	var altitude: float = _rng.randf_range(BIRD_ALTITUDE_MIN, BIRD_ALTITUDE_MAX)
	var lead_pos: Vector3 = player_pos - _bird_dir * BIRD_SPAWN_DISTANCE + side
	lead_pos.y = altitude

	var count: int = _rng.randi_range(BIRD_FLOCK_MIN, BIRD_FLOCK_MAX)
	_birds.clear()
	for i in count:
		# Bird 0 is the leader (exact lead_pos); the rest trail and spread out
		# around it, each with its own wing-beat phase so the flock doesn't flap
		# in lockstep like a single animated sprite.
		var offset := Vector3.ZERO
		if i > 0:
			offset = Vector3(
					_rng.randf_range(-BIRD_FLOCK_SPREAD, BIRD_FLOCK_SPREAD),
					_rng.randf_range(-BIRD_FLOCK_SPREAD, BIRD_FLOCK_SPREAD) * 0.3,
					_rng.randf_range(-BIRD_FLOCK_SPREAD, BIRD_FLOCK_SPREAD))
		_birds.append({
			"pos": lead_pos + offset,
			"phase": _rng.randf_range(0.0, TAU),
		})


func _write_bird_instances() -> void:
	## Write the whole flock into the MultiMesh: per bird a body box plus two
	## wing boxes rotated by the shared sine flap.
	##
	## Each bird gets a local frame built from the flight direction —
	## X = right (wing span), Y = up, Z = backwards (so the body's long Z axis
	## lies along the flight path). A wing is that frame rotated about its local
	## Z (the travel axis) by ±flap, which swings it up and down exactly like a
	## real wing hinge.
	var mm: MultiMesh = _bird_mmi.multimesh
	var right: Vector3 = _bird_dir.cross(Vector3.UP).normalized()
	var frame := Basis(right, Vector3.UP, -_bird_dir)
	var parked := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)

	for bi in BIRD_FLOCK_MAX:
		var base_idx: int = bi * BIRD_PARTS
		if bi >= _birds.size():
			# Slot unused by this (smaller) flock.
			for part in BIRD_PARTS:
				mm.set_instance_transform(base_idx + part, parked)
			continue

		var bird: Dictionary = _birds[bi]
		var phase: float = bird["phase"]
		var pos: Vector3 = bird["pos"]
		# Gentle undulation along the path, on top of the flap.
		pos.y += sin(_bird_time * BIRD_BOB_SPEED * TAU + phase) * BIRD_BOB_AMPLITUDE
		var flap: float = sin(_bird_time * BIRD_FLAP_HZ * TAU + phase) * BIRD_FLAP_ANGLE

		mm.set_instance_transform(base_idx,
				Transform3D(frame.scaled_local(BIRD_BODY_SIZE), pos))
		# Wings mirror each other: left hinges +flap, right hinges -flap, and
		# each sits half a wingspan out along its own rotated span axis.
		for w in 2:
			var sign_w: float = 1.0 if w == 0 else -1.0
			var wing_basis: Basis = frame * Basis(Vector3.BACK, flap * sign_w)
			var wing_pos: Vector3 = pos \
					+ wing_basis * Vector3(BIRD_WING_SIZE.x * 0.5 * sign_w, 0.0, 0.0)
			mm.set_instance_transform(base_idx + 1 + w,
					Transform3D(wing_basis.scaled_local(BIRD_WING_SIZE), wing_pos))
