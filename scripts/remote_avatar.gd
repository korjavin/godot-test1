extends Node3D
class_name RemoteAvatar
## One remote multiplayer peer, rendered locally. VISUAL ONLY.
##
## ============================================================================
## THE ISOLATION CONTRACT — read this before editing anything below
## ============================================================================
##
## A RemoteAvatar is a picture of somebody else's player. It is NOT a player.
## Three rules make that true, and every one of them is load-bearing:
##
##   1. It joins **NO group**. Above all it is never in "player".
##   2. It adds **NO** CollisionObject3D / Area3D / CharacterBody3D — nothing
##      physical, nothing monitorable. The character scenes it instances are
##      pure Node3D trees (they are already only ever parented under the local
##      player's $CharacterModel Node3D), so this costs nothing to honour.
##   3. It is parented to the MP manager (scripts/mp_manager.gd), **never** to a
##      terrain chunk — a chunk frees its children when it unloads, which would
##      delete a peer mid-run.
##
## Why rule 1 matters: this whole codebase discovers the player by group, so a
## second node in "player" would be picked up — silently and wrongly — by:
##
##   * scripts/endless_terrain.gd      — chunk streaming follows the player;
##                                        two players means thrashing chunks
##   * scripts/piglet_crocodile_ai.gd  — crocodiles would chase a hologram
##   * scripts/crocodile_lod_manager.gd — sleep/wake radii, coin animation LOD
##   * scripts/danger_vignette.gd      — the red screen edge + heartbeat
##   * scripts/fauna_manager.gd        — herd spawn/despawn field
##   * scripts/weather_manager.gd      — cloud field + rain zone follow
##
## get_tree().get_first_node_in_group("player") must keep meaning THE LOCAL
## PLAYER, always. scripts/fauna_manager.gd is the precedent to copy: its
## animals are in no group, carry no collision, and hang off their manager.
## scripts/mp_selfcheck.gd asserts rules 1 and 2 so a regression fails loudly
## instead of turning into "why are the crocodiles ignoring me?".
##
## What this node does: hold the last presence packet received for one peer,
## smooth toward it, and drive the same procedural limb animation the local
## player uses so a remote runner reads as a runner and not as a sliding statue.

# ============================================================================
# CONSTANTS
# ============================================================================

## Character roster, borrowed from the player. player_controller.gd has no
## class_name, so preload the script and read the const off it.
const PLAYER_SCRIPT: GDScript = preload("res://scripts/player_controller.gd")

## Exponential smoothing rate toward the latest presence sample (1/seconds).
## Higher = snappier and more jittery, lower = smoother and laggier.
##
## ponytail: plain exponential smoothing toward the newest sample, NOT a
## timestamped interpolation buffer. At the 15 Hz presence rate over a LAN or a
## single TURN hop this reads smooth, and it holds no history to get out of
## sync. Upgrade to a buffered-delay interpolator (render ~100 ms in the past
## from a queue of timestamped samples) if it visibly rubber-bands on a real
## connection.
const INTERP_RATE: float = 12.0

## Position error (metres) above which we stop smoothing and just teleport.
## A respawn, a restart or Primm's Phase Step moves a player much further than
## one 15 Hz tick ever could; without this the avatar would take a long serene
## glide across the field to catch up.
const TELEPORT_DISTANCE: float = 10.0

## Name tag height above the avatar's feet, in metres, and its glyph size.
const LABEL_HEIGHT: float = 2.2
const LABEL_PIXEL_SIZE: float = 0.006
const LABEL_FONT_SIZE: int = 48

## Stride phase advanced per metre walked, for a hero on the DEFAULT gait. A
## row with a different `stride_rate` scales this in step (see `_animate()`), so
## a slow-striding Teibi covers the same ground in fewer, longer strides here
## exactly as he does on his own screen.
const STRIDE_FREQUENCY: float = 1.6

## The swing amplitudes are NO LONGER COPIED. They used to be three floats
## duplicated out of `animate_walking()` — cheap, until each hero got their own
## walk. `PLAYER_SCRIPT.gait_for()` is a static, total, pure read of a script
## const (the shape `hero_hud.gd` uses to reach `CHARACTERS`), so this stays a
## visual-only node holding no reference to the player controller, and a
## teammate's Teibi stomps like yours with no netcode at all.
const DEFAULT_STRIDE_RATE: float = 8.0  ## `GAITS["DEFAULT"]["stride_rate"]`

## Speed (m/s) at or above which the walk cycle plays at full amplitude. Below
## it the pose fades toward rest, so a standing peer stands still.
const FULL_STRIDE_SPEED: float = 3.0

## Airborne pose, mirroring the player's tucked-leg jump pose.
const AIR_LEG_TUCK: float = 10.0      ## Degrees, both legs forward
const AIR_ARM_SPREAD: float = 72.0    ## Degrees, arms rolled out sideways

## The wing beat a peer running Air Rush gets on top of that spread — the two
## numbers player_controller.animate_jumping() flaps by, copied for the reason
## the walk-cycle three above are copied (bead godot-test1-69p).
const FLAP_SPEED: float = 14.0        ## Radians per second of beat
const FLAP_RANGE: float = 22.0        ## Degrees, added to and taken off the spread

# ============================================================================
# STATE
# ============================================================================

## This peer's display name, as the lobby reported it.
var peer_label: String = ""

## Which CHARACTERS entry is currently instanced (-1 = nothing yet).
var character_index: int = -1

## Minimum gap between model swaps — see the rate-limit note in `set_character()`.
const SWAP_COOLDOWN_MS: int = 500
var _last_swap_ms: int = -SWAP_COOLDOWN_MS

## Latest presence sample: where this peer says it is, and what it is doing.
var target_pos: Vector3 = Vector3.ZERO
var target_yaw: float = 0.0
var move_speed: float = 0.0
var on_floor: bool = true

## The peer's visible ability state, as `PLAYER_SCRIPT.ABILITY_BIT_*` flags —
## Teibi's Resize form and Windman's Air Rush (bead godot-test1-69p). Straight
## off the wire, already bounded to a byte by `MpCodec.decode_presence()`, and
## read only with `&` and `ability_visual_scale()`, both of which are total: a
## bit this build does not know draws nothing rather than breaking the pose.
var ability_bits: int = 0

## Local wing-beat clock for the Air Rush flap. OUR OWN, not the sender's: a
## flap is a loop with no meaningful phase, so nothing has to be carried on the
## wire for it to read right.
var _flap_phase: float = 0.0

## Container for the instanced character scene.
var model_root: Node3D = null

## The instanced character scene itself, and the limb nodes found inside it by
## the project's exact-name contract (Body / LeftArm / RightArm / LeftLeg /
## RightLeg — see CLAUDE.md "Procedural limb animation").
var character_node: Node3D = null
var character_body: Node3D = null
var left_arm: Node3D = null
var right_arm: Node3D = null
var left_leg: Node3D = null
var right_leg: Node3D = null
## OPTIONAL, exactly as it is for the local player: a model with no `Head` node
## simply gets no bobble.
var character_head: Node3D = null

## The shown hero's `PlayerController.GAITS` row, resolved once per model swap.
var _gait: Dictionary = PLAYER_SCRIPT.gait_for("")

## Rest rotations captured the moment the model is instanced, exactly as
## player_controller.setup_animation_references() does — every animated pose is
## an offset from these, so the limbs can always return to neutral.
var rest_rotations: Dictionary = {}

## Accumulated walk phase (radians). Advanced by distance walked, not by raw
## time, so the stride keeps pace with the peer's actual speed.
var stride_phase: float = 0.0

## How far the model is currently sunk into a river, mirroring the local player's
## own `_wade_sink` (same constants, read straight off PLAYER_SCRIPT so the two
## can never drift). It is computed LOCALLY rather than carried on the wire:
## `is_river_at` is a pure function of world position + the shared run seed, and
## presence already carries the peer's position and its on-floor bit, so a peer
## standing in a river is something every other peer can work out for itself for
## free. Nothing was added to the presence packet for this.
var _wade_sink: float = 0.0
## Cached "terrain" group node, resolved lazily like the crocodile AI caches the
## "mp" node — the group lookup is the only cost this feature could have had at
## frame rate, so it is paid once.
var _terrain: Node = null

# ============================================================================
# SETUP
# ============================================================================

func setup(peer_name: String) -> void:
	"""
	Build the avatar: a name tag and an empty model container.

	@param peer_name: The peer's display name, straight off the lobby. It is
	                  shown verbatim; the lobby already clamps names to 32
	                  characters (see server/conn.go), so there is no banner
	                  risk from a hostile name.
	"""
	peer_label = peer_name

	# The model container. Everything the character scene brings hangs off this
	# one node, so set_character() can free the whole previous character with a
	# single queue_free() and never orphan a limb reference.
	model_root = Node3D.new()
	model_root.name = "Model"
	add_child(model_root)

	# Floating name tag. One Label3D and nothing else — no health bar, no icon,
	# no ping readout. Billboarded so it faces the local camera from any angle,
	# and depth-tested (no_depth_test stays false) so a name behind a mountain
	# does not shine through it.
	var tag: Label3D = Label3D.new()
	tag.name = "NameTag"
	tag.text = peer_name
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = false
	tag.pixel_size = LABEL_PIXEL_SIZE
	tag.font_size = LABEL_FONT_SIZE
	tag.outline_size = 8
	tag.modulate = Color(1.0, 1.0, 1.0)
	tag.outline_modulate = Color(0.0, 0.0, 0.0, 0.8)
	tag.position = Vector3(0.0, LABEL_HEIGHT, 0.0)
	# A name tag is chrome, not scenery: it must not cast shadows onto the world.
	tag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tag)


func set_character(index: int) -> void:
	"""
	Swap the visible character model.

	@param index: Index into player_controller.CHARACTERS. This value arrives
	              over the network, so it is UNTRUSTED: an out-of-range index is
	              ignored outright rather than clamped into some other player's
	              hero, and a repeat of the current index is a no-op.

	ponytail: the model is instanced on demand, not preloaded four-deep for
	every peer the way the local player preloads all four and toggles
	visibility. A remote peer pressing E is rare, and four instanced character
	trees × three peers is real memory. If a remote switch ever visibly
	hitches, copy the player's preload-and-toggle scheme.
	"""
	if index < 0 or index >= PLAYER_SCRIPT.CHARACTERS.size():
		return
	if index == character_index:
		return
	# RATE LIMIT — the range check makes `c` safe to index, but not safe to OBEY
	# 15 times a second: a peer alternating between two valid indices in its
	# presence stream would force a queue_free + PackedScene.instantiate + a full
	# recursive `_style_model_meshes` walk per packet, per peer, which is a
	# remote-triggered frame-rate collapse on the gl_compatibility web build.
	# Dropping the swap is safe rather than lossy: presence repeats `c` every
	# packet, so a genuine switch simply applies on the first packet past the
	# window. A real player pressing E cannot beat this cadence anyway.
	var now: int = Time.get_ticks_msec()
	if now - _last_swap_ms < SWAP_COOLDOWN_MS:
		return

	# Drop the old model and every reference into it, so a half-freed limb can
	# never be animated on the frame between queue_free() and the actual free.
	if character_node:
		character_node.queue_free()
	character_node = null
	character_body = null
	left_arm = null
	right_arm = null
	left_leg = null
	right_leg = null
	character_head = null
	rest_rotations.clear()

	var scene_path: String = PLAYER_SCRIPT.CHARACTERS[index]["scene_path"]
	var scene: PackedScene = load(scene_path)
	if not scene:
		push_warning("RemoteAvatar: could not load character scene %s" % scene_path)
		return

	# `character_index` and the cooldown are committed HERE, not before the load:
	# the `index == character_index` no-op at the top of this function short-
	# circuits every repeat of `c`, so recording a swap that then failed would
	# leave this peer permanently model-less with no retry path. Presence repeats
	# `c` every packet, so leaving them uncommitted means the next packet retries.
	_last_swap_ms = now
	character_index = index
	# This hero's walk personality, resolved here for the same reason the player
	# resolves it in set_active_character(): a swap is rare, a frame is not.
	_gait = PLAYER_SCRIPT.gait_for(String(PLAYER_SCRIPT.CHARACTERS[index]["name"]))

	character_node = scene.instantiate()
	model_root.add_child(character_node)

	_cache_limbs()
	_style_model_meshes(character_node)


func _cache_limbs() -> void:
	"""
	Find the limb nodes BY EXACT NAME and record their rest rotations.

	This mirrors player_controller.setup_animation_references(): the project has
	no AnimationPlayer, so every character scene must expose a `Body` node with
	`LeftArm` / `RightArm` / `LeftLeg` / `RightLeg` beneath it. A model missing
	them still renders — it just stands frozen, exactly as it would for the
	local player.
	"""
	character_body = character_node.get_node_or_null("Body")
	if not character_body:
		return

	left_arm = character_body.get_node_or_null("LeftArm")
	right_arm = character_body.get_node_or_null("RightArm")
	left_leg = character_body.get_node_or_null("LeftLeg")
	right_leg = character_body.get_node_or_null("RightLeg")
	character_head = character_body.get_node_or_null("Head")

	# `body` and `head` ride the same table as the four limbs because the gait
	# rolls, pitches and bobbles them — every axis an animation writes needs a
	# rest value, or a model swap leaves the lean baked into the next hero.
	rest_rotations["body"] = character_body.rotation
	if character_head:
		rest_rotations["head"] = character_head.rotation
	if left_arm:
		rest_rotations["left_arm"] = left_arm.rotation
	if right_arm:
		rest_rotations["right_arm"] = right_arm.rotation
	if left_leg:
		rest_rotations["left_leg"] = left_leg.rotation
	if right_leg:
		rest_rotations["right_leg"] = right_leg.rotation


func _style_model_meshes(node: Node) -> void:
	"""
	Apply the shared toon+rim treatment to every mesh in the model, so a remote
	peer looks like the local hero rather than a flat-shaded impostor.

	Same subtree walk the crocodile does in its _ready (see
	piglet_crocodile_ai._style_model_meshes). ToonShading's static cache keys on
	the SOURCE material's instance id, so all four peers sharing a character
	share one styled material per source — never a duplicate per avatar.
	Deliberately NO inverted-hull outline overlay (the local player has one):
	that is a second draw call per mesh, and the local player is the one whose
	silhouette needs to pop.
	"""
	if node is MeshInstance3D:
		ToonShading.apply_to_mesh(node)
	for child in node.get_children():
		_style_model_meshes(child)

# ============================================================================
# NETWORK INPUT
# ============================================================================

func receive_state(pos: Vector3, yaw: float, char_index: int, speed: float,
		on_ground: bool, ability: int = 0) -> void:
	"""
	Store one presence sample. Called by mp_manager.gd once per packet from this
	peer (~15 Hz); _process does the actual smoothing between samples.

	Every argument here came off the wire. mp_manager validates types and ranges
	before calling — this function trusts only what set_character() re-checks.

	`ability` defaults to 0 so a caller that predates the field (and a peer whose
	build never sends it) simply gets the normal-sized, non-flying pose.
	"""
	target_pos = pos
	target_yaw = yaw
	move_speed = speed
	on_floor = on_ground
	ability_bits = ability
	set_character(char_index)

# ============================================================================
# PER-FRAME: SMOOTHING + ANIMATION
# ============================================================================

func _process(delta: float) -> void:
	# Frame-rate independent exponential smoothing: the weight is derived from
	# delta rather than being a fixed per-frame fraction, so the avatar chases
	# its target at the same real-world rate at 30 fps and at 144 fps.
	var weight: float = 1.0 - exp(-INTERP_RATE * delta)

	if global_position.distance_to(target_pos) > TELEPORT_DISTANCE:
		# Too far to be ordinary movement — a respawn, a restart, or a Phase
		# Step. Snap, so the avatar never glides serenely across the map.
		global_position = target_pos
		rotation.y = target_yaw
	else:
		global_position = global_position.lerp(target_pos, weight)
		# lerp_angle takes the short way round, so crossing ±PI does not spin
		# the avatar the long way.
		rotation.y = lerp_angle(rotation.y, target_yaw, weight)

	_tick_wade_sink(delta)
	_tick_ability_scale(delta)
	_animate(delta)


func _tick_ability_scale(delta: float) -> void:
	"""
	Match this peer's Teibi Resize form, with THE SAME constants the local player
	resizes by — `PLAYER_SCRIPT.ability_visual_scale()`, never a second copy of
	0.45 and 2.2.

	VISUAL ONLY, and the isolation contract is why this scales `model_root` and
	nothing else: the local player also scales its collision capsule (a giant has
	a giant body), and an avatar HAS NO BODY to scale. Nothing here adds one.

	Eased at the presence-smoothing rate rather than snapped, so the resize
	arriving on one 15 Hz packet reads as a grow rather than a pop — the local
	player's own tween is a springy overshoot, which is a nicety a watcher two
	hundred metres away cannot see.

	ponytail: the name tag keeps its fixed LABEL_HEIGHT, so a giant peer wears
	his name low. It hangs off the avatar root deliberately (the wade sink has
	the same reason); scale the tag's height by this factor if it ever reads
	wrong at 2.2x.
	"""
	if model_root == null:
		return
	var target: float = PLAYER_SCRIPT.ability_visual_scale(ability_bits)
	var s: float = lerpf(model_root.scale.x, target, 1.0 - exp(-INTERP_RATE * delta))
	model_root.scale = Vector3(s, s, s)


func _tick_wade_sink(delta: float) -> void:
	"""
	Sink the model when this peer is standing in a river, exactly as the local
	player sinks its own — same depth, same ease, same constants.

	The name tag is deliberately NOT sunk: it hangs off the avatar root, not off
	model_root, so a teammate wading is still labelled at a readable height.
	"""
	if model_root == null:
		return
	var wading: bool = on_floor and _terrain_is_river_at(target_pos)
	var target: float = PLAYER_SCRIPT.WADE_SINK_DEPTH if wading else 0.0
	if is_equal_approx(_wade_sink, target):
		return
	_wade_sink = move_toward(_wade_sink, target, PLAYER_SCRIPT.WADE_SINK_EASE_SPEED * delta)
	model_root.position.y = -_wade_sink


func _terrain_is_river_at(pos: Vector3) -> bool:
	"""
	Null-safe group lookup, the shape player_controller._terrain_is_river_here()
	uses: false when there is no terrain (the avatar must still run in a scene
	without one), and the has_method guard covers an older/stubbed terrain.
	"""
	if _terrain == null or not is_instance_valid(_terrain):
		# Re-resolved rather than latched: an avatar can be built before the
		# terrain node exists, and a latched null would stay null for the room's
		# life. Once found it is cached, so the steady state is zero lookups.
		_terrain = get_tree().get_first_node_in_group("terrain")
	if _terrain == null or not _terrain.has_method("is_river_at"):
		return false
	return _terrain.is_river_at(pos)


func _animate(delta: float) -> void:
	"""
	Drive the limbs from the last presence sample.

	Grounded: the player's walk cycle — arms and legs swinging in diagonal
	opposition off a sine, amplitude fading to nothing as speed drops so a
	standing peer stands still. Airborne: the player's static tucked pose.

	The phase advances by DISTANCE walked (speed * delta), not by raw time, so
	the stride matches the ground the peer is covering at any speed and cannot
	drift — the same trick fauna_manager.gd uses for its herds.
	"""
	if not left_arm or not right_arm or not left_leg or not right_leg:
		return

	if not on_floor:
		# Airborne: legs tucked forward, arms rolled out sideways. Static, like
		# the player's jump pose minus the wing flap (which is driven by the
		# player's own animation clock — a remote peer has no such clock, and a
		# flap out of sync with the peer's own screen would read as a glitch).
		var tuck: float = deg_to_rad(AIR_LEG_TUCK)
		var spread: float = deg_to_rad(AIR_ARM_SPREAD)
		# AIR RUSH BEATS THE WINGS (bead godot-test1-69p). The static spread is
		# the plain jump pose; a peer whose presence packet says Air Rush is
		# running gets the flap `player_controller.animate_jumping()` draws, off
		# OUR clock rather than the sender's — see `_flap_phase`. The phase only
		# advances while the boost is up, so the wings park level the instant it
		# ends rather than freezing mid-beat.
		if ability_bits & PLAYER_SCRIPT.ABILITY_BIT_FLYING:
			_flap_phase += delta * FLAP_SPEED
			spread += sin(_flap_phase) * deg_to_rad(FLAP_RANGE)
		left_leg.rotation.x = rest_rotations["left_leg"].x + tuck
		right_leg.rotation.x = rest_rotations["right_leg"].x + tuck
		left_arm.rotation.x = rest_rotations["left_arm"].x
		right_arm.rotation.x = rest_rotations["right_arm"].x
		left_arm.rotation.z = rest_rotations["left_arm"].z - spread
		right_arm.rotation.z = rest_rotations["right_arm"].z + spread
		_relax_gait_extras()
		return

	# Grounded: clear the airborne arm roll, then swing on the X axis only.
	left_arm.rotation.z = rest_rotations["left_arm"].z
	right_arm.rotation.z = rest_rotations["right_arm"].z

	stride_phase += move_speed * delta * STRIDE_FREQUENCY \
			* (float(_gait["stride_rate"]) / DEFAULT_STRIDE_RATE)

	# Amplitude scales with speed up to FULL_STRIDE_SPEED, so slowing to a stop
	# eases the pose back to rest instead of freezing it mid-stride.
	var amount: float = clampf(move_speed / FULL_STRIDE_SPEED, 0.0, 1.0)
	var swing: float = sin(stride_phase) * amount

	# The hitch — the player's second, incommensurate sine, off the phase this
	# node already keeps. It scales AMPLITUDE only, exactly as it does locally.
	var wobble: float = sin(stride_phase * PLAYER_SCRIPT.GAIT_HITCH_RATIO + float(_gait["phase"]))
	var hitch: float = 1.0 + float(_gait["hitch"]) * wobble
	var arm: float = deg_to_rad(float(_gait["arm_deg"])) * hitch
	var leg: float = deg_to_rad(float(_gait["leg_deg"])) * hitch

	left_arm.rotation.x = rest_rotations["left_arm"].x + swing * arm * float(_gait["arm_asym"])
	right_arm.rotation.x = rest_rotations["right_arm"].x - swing * arm
	left_leg.rotation.x = rest_rotations["left_leg"].x - swing * leg
	right_leg.rotation.x = rest_rotations["right_leg"].x + swing * leg

	# Body bob at twice the stride rate (one bob per footfall), offset to stay
	# at or above rest so the legs never punch through the ground plane, plus
	# this hero's roll and pitch. All three fade out with `amount`, so a peer
	# easing to a stop settles level instead of parking mid-waddle.
	if character_body:
		character_body.position.y = (sin(stride_phase * 2.0) * 0.5 + 0.5) \
				* float(_gait["bob"]) * amount
		character_body.rotation.z = rest_rotations["body"].z \
				+ swing * deg_to_rad(float(_gait["sway_deg"]))
		character_body.rotation.x = rest_rotations["body"].x \
				+ amount * deg_to_rad(float(_gait["lean_deg"]))
	if character_head and rest_rotations.has("head"):
		character_head.rotation.z = rest_rotations["head"].z \
				+ amount * wobble * deg_to_rad(float(_gait["head_deg"]))


func _relax_gait_extras() -> void:
	"""
	Snap the three axes only the grounded gait writes — body roll, body pitch,
	head bobble — back to rest. The airborne pose is static, so unlike the local
	player's eased version there is nothing to ease out of.
	"""
	if character_body and rest_rotations.has("body"):
		character_body.rotation.x = rest_rotations["body"].x
		character_body.rotation.z = rest_rotations["body"].z
	if character_head and rest_rotations.has("head"):
		character_head.rotation.z = rest_rotations["head"].z


func is_giant() -> bool:
	"""
	Quarry contract (bead godot-test1-upu): reports whether this remote peer is
	currently wearing the giant form, decoded from presence ability bits.
	Read by piglet_crocodile_ai to deter predators with fears_giant_radius.
	"""
	return bool(ability_bits & PLAYER_SCRIPT.ABILITY_BIT_GIANT)

