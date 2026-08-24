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

## Walk-cycle tuning. These three numbers are DUPLICATED from
## player_controller.gd's animate_walking() on purpose: three floats copied is
## cheaper than coupling a visual-only network avatar to the player controller,
## which owns input, physics, abilities and lives. If the player's walk cycle is
## ever retuned and the two visibly diverge, copy the numbers again.
const STRIDE_FREQUENCY: float = 1.6   ## Stride phase advanced per metre walked
const ARM_SWING: float = 30.0         ## Degrees, forward/back
const LEG_SWING: float = 40.0         ## Degrees, forward/back

## Speed (m/s) at or above which the walk cycle plays at full amplitude. Below
## it the pose fades toward rest, so a standing peer stands still.
const FULL_STRIDE_SPEED: float = 3.0

## Airborne pose, mirroring the player's tucked-leg jump pose.
const AIR_LEG_TUCK: float = 10.0      ## Degrees, both legs forward
const AIR_ARM_SPREAD: float = 72.0    ## Degrees, arms rolled out sideways

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

## Rest rotations captured the moment the model is instanced, exactly as
## player_controller.setup_animation_references() does — every animated pose is
## an offset from these, so the limbs can always return to neutral.
var rest_rotations: Dictionary = {}

## Accumulated walk phase (radians). Advanced by distance walked, not by raw
## time, so the stride keeps pace with the peer's actual speed.
var stride_phase: float = 0.0

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

func receive_state(pos: Vector3, yaw: float, char_index: int, speed: float, on_ground: bool) -> void:
	"""
	Store one presence sample. Called by mp_manager.gd once per packet from this
	peer (~15 Hz); _process does the actual smoothing between samples.

	Every argument here came off the wire. mp_manager validates types and ranges
	before calling — this function trusts only what set_character() re-checks.
	"""
	target_pos = pos
	target_yaw = yaw
	move_speed = speed
	on_floor = on_ground
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

	_animate(delta)


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
		left_leg.rotation.x = rest_rotations["left_leg"].x + tuck
		right_leg.rotation.x = rest_rotations["right_leg"].x + tuck
		left_arm.rotation.x = rest_rotations["left_arm"].x
		right_arm.rotation.x = rest_rotations["right_arm"].x
		left_arm.rotation.z = rest_rotations["left_arm"].z - spread
		right_arm.rotation.z = rest_rotations["right_arm"].z + spread
		return

	# Grounded: clear the airborne arm roll, then swing on the X axis only.
	left_arm.rotation.z = rest_rotations["left_arm"].z
	right_arm.rotation.z = rest_rotations["right_arm"].z

	stride_phase += move_speed * delta * STRIDE_FREQUENCY

	# Amplitude scales with speed up to FULL_STRIDE_SPEED, so slowing to a stop
	# eases the pose back to rest instead of freezing it mid-stride.
	var amount: float = clampf(move_speed / FULL_STRIDE_SPEED, 0.0, 1.0)
	var swing: float = sin(stride_phase) * amount

	left_arm.rotation.x = rest_rotations["left_arm"].x + swing * deg_to_rad(ARM_SWING)
	right_arm.rotation.x = rest_rotations["right_arm"].x - swing * deg_to_rad(ARM_SWING)
	left_leg.rotation.x = rest_rotations["left_leg"].x - swing * deg_to_rad(LEG_SWING)
	right_leg.rotation.x = rest_rotations["right_leg"].x + swing * deg_to_rad(LEG_SWING)

	# Body bob at twice the stride rate (one bob per footfall), offset to stay
	# at or above rest so the legs never punch through the ground plane.
	if character_body:
		character_body.position.y = (sin(stride_phase * 2.0) * 0.5 + 0.5) * 0.03 * amount
