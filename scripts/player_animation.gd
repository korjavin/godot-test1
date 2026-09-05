class_name PlayerAnimation
extends RefCounted
## THE PLAYER'S PROCEDURAL ANIMATION — lifted whole out of `player_controller.gd`
## (bd godot-test1-ftn.9, epic `ftn`).
##
## THE SPLIT. The `CharacterBody3D` keeps movement, capture, respawn, the input
## map and every contract method the `"player"` group answers; this file keeps
## the POSE — the limb references, the rest-pose table, the `GAITS` personality
## rows, the walk / idle / air / sidestep cycles, and the cel-shading applied to
## a character model on the swap path. It is a MOVE and nothing else: not one
## number, not one branch and not one comment changed.
##
## WHY A `RefCounted` HOLDING THE PLAYER rather than `landmark_builders.gd`'s
## static-library-with-an-out-param contract. The pose IS state — five node
## references, `original_rotations`, `animation_time` and the footstep tracker —
## and a static library would have to be handed all of it on every frame. So the
## `ToonShading` / `PauseHub` helper idiom one step on: one object, created with
## the body and freed with it, reaching back through `player` for the things the
## BODY owns (`is_on_floor()`, the landing squash, the Teibi scale, the sidestep
## flags, `_sfx`). That reference is untyped on purpose: `player_controller.gd`
## carries no `class_name` (its readers `preload` it), so there is no type to
## write and nothing here can create a cyclic dependency.
##
## THE NODE-NAME CONTRACT IS UNCHANGED, and it is still the whole animation
## rig: there is no `AnimationPlayer` anywhere in this game. `Body`, and under
## it `LeftArm` / `RightArm` / `LeftLeg` / `RightLeg` (plus an OPTIONAL `Head`),
## looked up by EXACT NAME in `setup_animation_references()`. A new playable
## character scene that spells one of them differently loads and stays frozen.

## THE BODY THIS POSES. Assigned once by `PlayerController._init()`; every read
## of the player's own state goes through it, and nothing here ever writes to
## the player except the landing squash it was already driving.
var player = null


# ============================================================================
# THE GAIT TABLE
# ============================================================================

## HOW MUCH SLOWER THE HITCH SINE RUNS THAN THE STRIDE — and it is irrational
## on purpose (2 - phi, the most stubbornly non-rational ratio there is).
##
## The gait is two sines: the STRIDE (which owns the phase, the footstep beat
## and the leg opposition) and the HITCH, which owns nothing but AMPLITUDE. Two
## incommensurate periods never line up again, so the walk is "unpredictable"
## with no `randf()` anywhere: the pose stays a pure function of
## (hero, animation_time), identical on every peer, needing no state and no
## netcode. A random call in `_process` would instead make the remote mirror in
## `remote_avatar.gd` diverge from the body it is a picture of.
const GAIT_HITCH_RATIO: float = 0.381966

## HOW EACH HERO WALKS — the `SPECIES` / `SKILL_TREES` const-dict idiom, one row
## per `CHARACTERS` name, resolved ONCE per character swap into `_gait` (never a
## dict lookup per frame). `gait_for()` merges a row over `DEFAULT`, so a row
## lists only what it changes and an unknown hero — a fifth character, a scene
## run standalone — animates exactly as this game did before this table existed.
##
## THIS IS POSE ONLY. Not one field here is read by movement: `WALK_SPEED`,
## `RUN_SPEED`, `calculate_current_speed()` and the catchable-walk chain are
## untouched, and `stride_rate` scales the ANIMATION clock, never the body.
##
## The fields:
##   stride_rate  radians/second of stride phase at speed_multiplier 1.0 (the
##                old literal 8.0). This IS the footstep rate — the SFX fire on
##                the sign flip of the stride sine, so a slow row stomps slowly.
##   arm_deg/leg_deg  swing amplitude, degrees, forward/back on X.
##   arm_asym     LEFT arm amplitude ratio. Nobody's arms match; 1.0 is today's.
##   bob          body rise/fall, model-local metres, at twice the stride rate.
##                Held under 0.05 so the body stays inside the [-0.05, +0.10] m
##                band `gait_selfcheck` asserts (a bigger dip puts a foot under
##                the flat world at full leg swing).
##   sway_deg     body ROLL — the waddle. Zero for windman on purpose: he is the
##                default hero, and `capture_selfcheck`'s sidestep test asserts
##                the walk animation leaves `character_body.rotation.z` at rest.
##   lean_deg     constant body PITCH into the run.
##   head_deg     optional head bobble. The `Head` node is looked up with
##                `get_node_or_null` and a model without one simply gets none.
##   hitch        how hard the hitch sine modulates the limb amplitude — the
##                skip, the stumble, the bobble. Kept below 1.0 so the amplitude
##                factor never reaches zero, let alone flips sign.
##   phase        this hero's offset into the hitch sine. Two heroes on screen
##                must not stumble on the same beat.
##   idle_rate/idle_bob  the standing breathe.
const GAITS: Dictionary = {
	# TODAY'S NUMBERS, EXACTLY. animate_walking() read these as literals before
	# this table existed (8.0 / 30 / 40 / 0.03) and animate_idle() as 2.0 / 0.01.
	# `hitch` 0.0 means the DEFAULT gait is a single sine, byte-for-byte the old
	# cycle — which is what makes "an unknown hero animates as it always did" a
	# measurement rather than a claim.
	"DEFAULT": {
		"stride_rate": 8.0, "arm_deg": 30.0, "leg_deg": 40.0, "arm_asym": 1.0,
		"bob": 0.03, "sway_deg": 0.0, "lean_deg": 0.0, "head_deg": 0.0,
		"hitch": 0.0, "phase": 0.0, "idle_rate": 2.0, "idle_bob": 0.01,
	},
	# Long loping strides, big arms, leaning into the wind he makes.
	"windman": {
		"stride_rate": 6.5, "arm_deg": 44.0, "leg_deg": 46.0, "arm_asym": 1.12,
		"bob": 0.038, "lean_deg": 6.0, "hitch": 0.10, "phase": 0.0,
		"idle_rate": 1.7, "idle_bob": 0.014,
	},
	# Quick short steps, arms held low and tight, with an occasional skip.
	"primm": {
		"stride_rate": 10.6, "arm_deg": 20.0, "leg_deg": 30.0, "arm_asym": 0.86,
		"bob": 0.022, "head_deg": 3.0, "hitch": 0.28, "phase": 1.7,
		"idle_rate": 2.6, "idle_bob": 0.008,
	},
	# A heavy stomp: slow, big legs, a deep bob and a periodic stumble.
	"teibi": {
		"stride_rate": 5.2, "arm_deg": 26.0, "leg_deg": 44.0, "arm_asym": 1.05,
		"bob": 0.045, "sway_deg": 5.0, "lean_deg": 3.0, "hitch": 0.30,
		"phase": 3.4, "idle_rate": 1.4, "idle_bob": 0.016,
	},
	# A waddle: small legs, a wide roll, and a head that will not sit still.
	"phoboman": {
		"stride_rate": 7.4, "arm_deg": 22.0, "leg_deg": 24.0, "arm_asym": 1.25,
		"bob": 0.028, "sway_deg": 11.0, "head_deg": 7.0, "hitch": 0.16,
		"phase": 5.1, "idle_rate": 2.2, "idle_bob": 0.012,
	},
}

# ============================================================================
# ANIMATION STATE
# ============================================================================

## Animation timing variable (tracks time for procedural animations)
var animation_time: float = 0.0

## Animation speed multiplier for walking/running
var animation_speed: float = 1.0

## References to character limbs for animation
var left_arm: Node3D = null
var right_arm: Node3D = null
var left_leg: Node3D = null
var right_leg: Node3D = null
var character_body: Node3D = null

## OPTIONAL. The head bobble's node, looked up by exact name like every other
## limb — but unlike them a model without one is not even a warning: `head_deg`
## simply draws nothing. Nothing else in the game requires a `Head`.
var character_head: Node3D = null

## This character's `GAITS` row, resolved once per swap in set_active_character().
var _gait: Dictionary = GAITS["DEFAULT"]

## Shared cel-shading outline, created once and reused for every character.
## Applied as a material overlay so it works on any mesh — both the primitive
## characters and the GLB-based windman — without touching their own materials.
const OUTLINE_SHADER: Shader = preload("res://assets/shaders/outline.gdshader")
var outline_material: ShaderMaterial = null

## Original rotations for resetting animations
var original_rotations: Dictionary = {}

## Track if character was on floor last frame (for landing detection)
var was_on_floor: bool = true

## Footstep tracking: the sign of the walk-cycle sine last frame. Each sign flip
## of sin(time_factor) is one leg passing through centre — i.e. one foot
## planting — so flips are exactly the footstep moments, at any walk/run speed.
## 0 means "not walking" (the reset state), so the first frame of a new walk
## just records the sign instead of mis-firing a step.
var _last_walk_sine_sign: int = 0

# ============================================================================
# THE CHARACTER SWAP PATH — style, rest poses, limb references
# ============================================================================

func capture_rest_pose(instance: Node3D) -> Dictionary:
	"""
	Record a character's limb rotations while it sits in its untouched rest pose.
	Keys match those used by the animation functions (left_arm, right_leg, ...).

	@param instance: A freshly-instanced character model
	@return Dictionary of limb name -> rest rotation
	"""
	var pose: Dictionary = {}
	var body := instance.get_node_or_null("Body")
	if not body:
		return pose

	pose["body"] = body.rotation
	# `head` rides the same table as the four limbs because the gait bobbles it:
	# every axis an animation writes has to have a rest value here, or a swap
	# mid-stride leaves the tilt baked into the next character.
	var limb_keys := {
		"left_arm": "LeftArm", "right_arm": "RightArm",
		"left_leg": "LeftLeg", "right_leg": "RightLeg",
		"head": "Head",
	}
	for key in limb_keys:
		var limb := body.get_node_or_null(limb_keys[key])
		if limb:
			pose[key] = limb.rotation
	return pose

func restore_rest_pose(index: int) -> void:
	"""
	Snap the active character's limbs (and body) back to their cached rest pose.

	@param index: Index in the CHARACTERS array
	"""
	var pose: Dictionary = player.character_rest_poses[index]
	if left_arm and pose.has("left_arm"):
		left_arm.rotation = pose["left_arm"]
	if right_arm and pose.has("right_arm"):
		right_arm.rotation = pose["right_arm"]
	if left_leg and pose.has("left_leg"):
		left_leg.rotation = pose["left_leg"]
	if right_leg and pose.has("right_leg"):
		right_leg.rotation = pose["right_leg"]
	if character_head and pose.has("head"):
		character_head.rotation = pose["head"]
	if character_body and pose.has("body"):
		character_body.rotation = pose["body"]
		character_body.position.y = 0.0

func activate_character(index: int) -> void:
	"""
	Point the whole animation system at the character `set_active_character()`
	has just made visible. The ONE seam the swap path enters through, so the
	five things a swap has to do stay together instead of being spelled out on
	the body — they are all pose state and every one of them lives here.

	@param index: Index in the CHARACTERS array
	"""
	# Point the animation system at this character, then snap it back to its
	# cached rest pose so it never resumes from a frozen mid-animation pose.
	setup_animation_references()
	original_rotations = player.character_rest_poses[index].duplicate()
	restore_rest_pose(index)

	# Resolve this hero's walk personality ONCE. The per-frame animation reads
	# `_gait`, never GAITS — a dict lookup plus a merge every frame for a value
	# that only changes on a swap is the sort of thing the F3 overlay finds.
	_gait = gait_for(String(player.CHARACTERS[index]["name"]))
	# ...and FORGET THE OUTGOING HERO'S FOOT. `_last_walk_sine_sign` is a memory of
	# `sign(sin(animation_time * stride_rate))`, and the new row's `stride_rate` is
	# a different number — so at the same `animation_time` the new hero's stride
	# sine can simply have the other sign, and the first frame after a swap would
	# read that as a foot planting and fire a phantom footstep or wading splash
	# with no leg having crossed anything. 0 is the sentinel `animate_walking()`
	# already understands: "no history — record this frame's sign silently", which
	# is exactly what a hero who has just appeared needs.
	_last_walk_sine_sign = 0

# ============================================================================
# ANIMATION FUNCTIONS
# ============================================================================

static func gait_for(hero: String) -> Dictionary:
	"""
	Resolve one hero's walk personality: their `GAITS` row merged over `DEFAULT`.

	STATIC and total, so `remote_avatar.gd` can read it off the script const the
	way `hero_hud.gd` reaches `CHARACTERS` — a teammate's Teibi stomps like
	yours with no node reference and no netcode. An unknown name gets `DEFAULT`,
	which is the pre-GAITS cycle exactly.

	@param hero: a `CHARACTERS` name
	@return: a fresh Dictionary carrying every field (never a shared reference)
	"""
	var row: Dictionary = GAITS["DEFAULT"].duplicate()
	if GAITS.has(hero):
		row.merge(GAITS[hero], true)
	return row

func setup_animation_references() -> void:
	"""
	Finds and stores references to character limbs for animation.
	Called when a new character is loaded.
	"""
	if not player.current_character_node:
		return

	# Find the Body node that contains all limbs
	character_body = player.current_character_node.get_node_or_null("Body")

	if not character_body:
		print("Warning: Character doesn't have a 'Body' node")
		return

	print("Body node found!")

	# Find limb nodes
	left_arm = character_body.get_node_or_null("LeftArm")
	right_arm = character_body.get_node_or_null("RightArm")
	left_leg = character_body.get_node_or_null("LeftLeg")
	right_leg = character_body.get_node_or_null("RightLeg")
	# OPTIONAL, and deliberately not printed below: a model with no Head is not
	# a broken model, it is a model whose gait row's `head_deg` draws nothing.
	character_head = character_body.get_node_or_null("Head")

	# Debug output
	print("  Limb nodes found:")
	print("    LeftArm: ", left_arm != null)
	print("    RightArm: ", right_arm != null)
	print("    LeftLeg: ", left_leg != null)
	print("    RightLeg: ", right_leg != null)

	# Store original rotations
	original_rotations.clear()
	if left_arm:
		original_rotations["left_arm"] = left_arm.rotation
	if right_arm:
		original_rotations["right_arm"] = right_arm.rotation
	if left_leg:
		original_rotations["left_leg"] = left_leg.rotation
	if right_leg:
		original_rotations["right_leg"] = right_leg.rotation
	if character_body:
		original_rotations["body"] = character_body.rotation
	if character_head:
		original_rotations["head"] = character_head.rotation

	print("Animation system initialized for character")

func apply_character_style(node: Node) -> void:
	"""
	Recursively give every mesh in the character its cel-shaded look:
	  - a shared inverted-hull outline as a material overlay, and
	  - soft toon diffuse + rim light on each surface material.

	Walking the tree covers both the primitive-built characters AND the nested
	meshes inside the GLB-based windman, in one place. The primitive characters
	already declare toon shading in their scene files, so apply_toon_shading only
	upgrades materials that aren't toon yet (windman's baked GLB materials) and
	leaves the others exactly as authored.

	@param node: Root of the character subtree to style
	"""
	# Build the shared outline material the first time we need it.
	if outline_material == null:
		outline_material = ShaderMaterial.new()
		outline_material.shader = OUTLINE_SHADER

	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		mesh.material_overlay = outline_material
		apply_toon_shading(mesh)

	for child in node.get_children():
		apply_character_style(child)

func apply_toon_shading(mesh: MeshInstance3D) -> void:
	"""
	Add soft toon diffuse + rim light to a mesh's materials, matching the look
	the primitive characters get from their scene files. We duplicate each
	material first so we only ADD shading and never lose the baked albedo or
	textures — important for windman, whose colours live in its GLB materials.

	Materials that are already toon (the primitive characters) are skipped.

	The actual styling now lives in the shared ToonShading helper
	(scripts/toon_shading.gd) so crocodiles get the identical treatment; its
	static material cache is correct for the player too — the same source
	material always maps to the same styled duplicate.

	@param mesh: The mesh whose surface materials should be cel-shaded
	"""
	ToonShading.apply_to_mesh(mesh)

# ============================================================================
# THE PER-FRAME POSE
# ============================================================================

func update_character_animation(delta: float, input_dir: Vector2) -> void:
	"""
	Main animation update function. Determines which animation to play
	based on character state.

	@param delta: Time since last frame
	@param input_dir: Current input direction
	"""
	if not player.current_character_node or not character_body:
		return

	# Update animation time
	animation_time += delta

	# Determine animation state and animate accordingly
	var is_moving = input_dir.length() > 0.1
	var current_on_floor = player.is_on_floor()

	# Landing thud, keyed to the raw floor transition rather than the animation
	# branch below — an active sidestep would otherwise swallow it — and muted
	# during the frozen caught/respawn/game-over windows (this function still
	# runs there, and settling under gravity mid-freeze shouldn't thud).
	if current_on_floor and not was_on_floor \
			and not (player.is_caught or player.is_respawning or player.is_game_over):
		player._sfx("play_land")
		# Start the landing squash, scaled by impact speed (see SECTION 2). The
		# eased dip itself is applied AFTER the branch chain below, so the walk
		# bob / idle breathe can't overwrite it on the same frame.
		player.land_squash_timer = player.LAND_SQUASH_DURATION
		player.land_squash_strength = clampf(player._fall_speed / player.LAND_SQUASH_SPEED_DIVISOR, 0.2, 1.0)
		# Heavy landings additionally kick the camera and puff a flat dust ring
		# at the feet (the thud above already covers audio on every landing).
		if player._fall_speed > player.LAND_HARD_SPEED:
			player.shake_amount = maxf(player.shake_amount, 0.12)
			player._spawn_ability_effect(player.global_position, Color(0.75, 0.7, 0.6, 0.45), 1.6, 0.3)
		player._fall_speed = 0.0

	# Jump/Fall animation
	if not current_on_floor:
		animate_jumping()
	# Sidestep takes priority on the ground when strafing without forward motion
	elif player.is_stepping and absf(input_dir.y) <= 0.01:
		animate_sidestep()
	# Landing detected
	elif not was_on_floor and current_on_floor:
		animate_landing()
	# Walking/Running animation
	elif is_moving and current_on_floor:
		var speed_multiplier = 1.5 if player.is_running else 1.0
		animate_walking(delta, speed_multiplier)
	# Idle animation
	else:
		animate_idle(delta)

	# Landing squash — applied AFTER the branch chain so whatever body position
	# the active animation just wrote gets the dip added on top (instead of the
	# walk bob / idle breathe overwriting it). A sin(progress * PI) arc eases the
	# compression in and back out, ending at exactly zero so the pose hands back
	# to the animations with no snap. The scale squash stretches the container
	# wide and short (volume-preserving cartoon squash) around the current Teibi
	# base scale; it is skipped while a Teibi resize tween is animating that same
	# property, so the two never fight.
	if player.land_squash_timer > 0.0:
		player.land_squash_timer = maxf(0.0, player.land_squash_timer - delta)
		var squash_progress: float = 1.0 - player.land_squash_timer / player.LAND_SQUASH_DURATION
		var k: float = sin(squash_progress * PI) * player.land_squash_strength
		if character_body:
			character_body.position.y -= 0.14 * k
		if player.character_container and (player._teibi_tween == null or not player._teibi_tween.is_running()):
			var base: float = player._current_teibi_scale()
			player.character_container.scale = base * Vector3(1.0 + 0.2 * k, 1.0 - 0.3 * k, 1.0 + 0.2 * k)

	# Not in the walking state (idle, airborne)? Reset the footstep tracker to
	# its "no history" sentinel so the first frame of the next walk records the
	# sine sign instead of mis-firing a phantom step. (A sidestep deliberately
	# does NOT reset it — the walk cycle resumes where it left off, and a step
	# sound on the post-sidestep foot plant is a real plant anyway.)
	if not (is_moving and current_on_floor):
		_last_walk_sine_sign = 0

	# Update floor tracking
	was_on_floor = current_on_floor

func animate_walking(delta: float, speed_multiplier: float) -> void:
	"""
	Animates the character's limbs for walking/running.
	Arms and legs swing back and forth.

	TWO SINES, and which is which is the whole design (see `GAIT_HITCH_RATIO`):

	  * the STRIDE owns the PHASE — leg opposition, the body bob at twice the
	    rate, and the footstep SFX, which fire on its sign flip;
	  * the HITCH owns nothing but AMPLITUDE. It runs at an irrational fraction
	    of the stride, so the two never line up twice and the walk reads as
	    unpredictable while staying a pure function of (hero, animation_time) —
	    no RNG, no state, identical on every peer.

	Because the hitch scales amplitude and never touches `time_factor`, the
	footsteps stay exactly on the beat no matter how hard a hero stumbles.

	@param delta: Time since last frame
	@param speed_multiplier: How fast to play the animation (1.0 = normal, 1.5 = running)
	"""
	if not left_arm or not right_arm or not left_leg or not right_leg:
		return

	# Clear any residual sideways roll so diagonal and straight walks are identical.
	reset_sidestep_pose()

	# Walking animation uses sine waves for smooth swinging motion
	var walk_speed: float = float(_gait["stride_rate"]) * speed_multiplier

	# Calculate swing values using sine wave
	var time_factor: float = animation_time * walk_speed
	var stride: float = sin(time_factor)
	# The amplitude modulation. `hitch` is well under 1.0 in every row, so this
	# factor never reaches zero and can never flip a limb's direction.
	var wobble: float = sin(time_factor * GAIT_HITCH_RATIO + float(_gait["phase"]))
	var hitch: float = 1.0 + float(_gait["hitch"]) * wobble
	var arm_swing_amount: float = deg_to_rad(float(_gait["arm_deg"])) * hitch
	var leg_swing_amount: float = deg_to_rad(float(_gait["leg_deg"])) * hitch
	var arm_swing: float = stride * arm_swing_amount
	var leg_swing: float = stride * leg_swing_amount

	# Footstep sounds, keyed to the walk cycle itself: each sign flip of the
	# swing sine is a leg passing through centre — a foot planting. Because
	# time_factor already advances 1.5× when running, the step rate speeds up
	# automatically. Sign 0 is the "just started walking" reset state: record
	# the current sign silently so the first frame never mis-fires a step.
	# Wading swaps the pat for a wet slap on the very same trigger, so the
	# "occasional splash" cadence comes free from the walk cycle — no new timer.
	var sine_sign: int = 1 if stride >= 0.0 else -1
	if _last_walk_sine_sign != 0 and sine_sign != _last_walk_sine_sign and player.is_on_floor():
		player._sfx("play_splash" if player.is_wading else "play_footstep")
	_last_walk_sine_sign = sine_sign

	# Apply rotations (arms and legs swing opposite to each other). The LEFT arm
	# carries the asymmetry, because two arms swinging identically is the single
	# most robotic thing about the old cycle.
	left_arm.rotation.x = original_rotations["left_arm"].x + arm_swing * float(_gait["arm_asym"])
	right_arm.rotation.x = original_rotations["right_arm"].x - arm_swing

	left_leg.rotation.x = original_rotations["left_leg"].x - leg_swing
	right_leg.rotation.x = original_rotations["right_leg"].x + leg_swing

	# Add slight body bob for realism, plus this hero's roll (the waddle) and
	# pitch (the lean). The bob is MODEL-LOCAL metres — it lives under Body, so
	# it scales with Teibi's resize the way the limb angles do; the collision
	# capsule does not move with any of it, which is why the amplitudes are
	# small enough for the body to still look attached to it.
	if character_body:
		character_body.position.y = sin(time_factor * 2.0) * float(_gait["bob"])
		character_body.rotation.z = original_rotations["body"].z \
				+ stride * deg_to_rad(float(_gait["sway_deg"]))
		character_body.rotation.x = original_rotations["body"].x \
				+ deg_to_rad(float(_gait["lean_deg"]))

	# The head bobble — off the hitch sine, so it wanders rather than nodding in
	# lockstep with the feet. Optional node, per the row's docs.
	if character_head and original_rotations.has("head"):
		character_head.rotation.z = original_rotations["head"].z \
				+ wobble * deg_to_rad(float(_gait["head_deg"]))

func relax_gait_extras(weight: float) -> void:
	"""
	Ease the three axes only the WALK gait writes — body roll, body pitch and
	the head bobble — back to their rest values.

	`reset_sidestep_pose()` is the precedent and the reason this exists: an
	animation that writes an axis nobody else writes has to put it back, or
	stopping mid-stride leaves the lean baked in for as long as you stand there.
	Sidestep owns the roll itself, so it snaps (weight 1.0); idle and the air
	pose ease, because an 11-degree waddle snapping level the frame you stop is
	a visible pop.

	@param weight: 1.0 snaps to rest, smaller values lerp toward it per frame.
	"""
	if character_body and original_rotations.has("body"):
		var rest: Vector3 = original_rotations["body"]
		character_body.rotation.x = lerp(character_body.rotation.x, rest.x, weight)
		character_body.rotation.z = lerp(character_body.rotation.z, rest.z, weight)
	if character_head and original_rotations.has("head"):
		character_head.rotation.z = lerp(
				character_head.rotation.z, original_rotations["head"].z, weight)

func animate_sidestep() -> void:
	"""
	Animate the legs (and arms) for a sideways strafe while A / D is held.

	Unlike walking (which swings the limbs forward/back on the X axis), the
	sidestep rolls them on the Z axis so the motion reads as sideways.
	"""
	if not left_arm or not right_arm or not left_leg or not right_leg:
		return

	# Drop the walk gait's lean and head bobble first — this pose sets the roll
	# itself two blocks down, so only the pitch and the head would linger.
	relax_gait_extras(1.0)

	# How far the legs splay sideways, and the extra lift on the leading leg.
	var leg_splay: float = player.step_direction * deg_to_rad(28)
	var lead_lift: float = player.step_direction * deg_to_rad(14)
	# Arms counter-swing for balance.
	var arm_balance: float = player.step_direction * deg_to_rad(20)

	# Both legs lean toward the step; the leading leg (on the step side) lifts a
	# touch more so the step reads as one foot reaching out and the other following.
	left_leg.rotation.z = original_rotations["left_leg"].z + leg_splay
	right_leg.rotation.z = original_rotations["right_leg"].z + leg_splay
	if player.step_direction > 0.0:
		right_leg.rotation.z += lead_lift
	else:
		left_leg.rotation.z += lead_lift

	left_arm.rotation.z = original_rotations["left_arm"].z - arm_balance
	right_arm.rotation.z = original_rotations["right_arm"].z - arm_balance

	# Lean the body into the step direction for a bit of weight shift.
	if character_body:
		character_body.rotation.z = original_rotations["body"].z - player.step_direction * deg_to_rad(8)
		character_body.position.y = 0.0

func animate_jumping() -> void:
	"""
	Animate the character in mid-air: they throw their arms out to the sides and
	FLAP them like wings, as if trying to take off, while the legs tuck together.

	Walking swings the limbs forward/back on the X axis; the wing flap rolls the
	arms on the Z axis instead, so it never fights the walk pose. We set the arm
	roll directly (rather than easing toward it) so the flap stays crisp, and
	mirror the two arms with opposite signs so they spread and beat together.
	animate_landing() drops the wings back down on touchdown.
	"""
	if not left_arm or not right_arm or not left_leg or not right_leg:
		return

	# animate_jumping owns the air: no hitch fires up here, and the walk gait's
	# lean and head bobble ease out on the way up.
	relax_gait_extras(0.2)

	# Continuous wing beat while airborne.
	var flap_speed = 14.0
	var flap = sin(animation_time * flap_speed)

	# Base spread (arms out toward horizontal) with the flap added on top. The
	# right arm rolls toward +X and the left toward -X, so they mirror each other.
	var wing_spread = deg_to_rad(72)
	var flap_range = deg_to_rad(22)
	var wing_angle = wing_spread + flap * flap_range

	right_arm.rotation.z = original_rotations["right_arm"].z + wing_angle
	left_arm.rotation.z = original_rotations["left_arm"].z - wing_angle
	# Clear any leftover forward/back swing from walking so the wings sit level.
	right_arm.rotation.x = original_rotations["right_arm"].x
	left_arm.rotation.x = original_rotations["left_arm"].x

	# Tuck the legs slightly together underneath.
	var leg_together_angle = deg_to_rad(10)
	var lerp_speed = 0.2
	left_leg.rotation.x = lerp(left_leg.rotation.x, original_rotations["left_leg"].x + leg_together_angle, lerp_speed)
	right_leg.rotation.x = lerp(right_leg.rotation.x, original_rotations["right_leg"].x + leg_together_angle, lerp_speed)

	# Reset body position
	if character_body:
		character_body.position.y = lerp(character_body.position.y, 0.0, lerp_speed)

func animate_landing() -> void:
	"""
	Brief animation when the character lands on the ground. The impact crouch
	itself is no longer set here — the eased landing squash at the end of
	update_character_animation drives it over LAND_SQUASH_DURATION instead of
	the old single -0.1 frame — so this only lowers the wings back to rest.
	"""
	if not character_body:
		return

	# Drop the wings (arm roll) back to the sides now that we're grounded. The
	# walk/idle animations only drive the X axis, so without this the arms would
	# stay spread out after touchdown.
	if left_arm and original_rotations.has("left_arm"):
		left_arm.rotation.z = original_rotations["left_arm"].z
	if right_arm and original_rotations.has("right_arm"):
		right_arm.rotation.z = original_rotations["right_arm"].z

func animate_idle(delta: float) -> void:
	"""
	Animates the character when standing still.
	Creates a subtle breathing/idle motion.
	"""
	if not left_arm or not right_arm or not left_leg or not right_leg:
		return

	# Smoothly return limbs to original positions
	var lerp_speed = 0.1

	# ...and the gait's own axes with them, or a hero who stops mid-waddle
	# stands there leaning.
	relax_gait_extras(0.15)

	left_arm.rotation.x = lerp(left_arm.rotation.x, original_rotations["left_arm"].x, lerp_speed)
	right_arm.rotation.x = lerp(right_arm.rotation.x, original_rotations["right_arm"].x, lerp_speed)

	left_leg.rotation.x = lerp(left_leg.rotation.x, original_rotations["left_leg"].x, lerp_speed)
	right_leg.rotation.x = lerp(right_leg.rotation.x, original_rotations["right_leg"].x, lerp_speed)

	# Subtle breathing animation, at this hero's own rate and depth — a heavy
	# Teibi breathes slow and deep, a twitchy Primm shallow and quick.
	if character_body:
		var breathe: float = sin(animation_time * float(_gait["idle_rate"])) \
				* float(_gait["idle_bob"])
		character_body.position.y = lerp(character_body.position.y, breathe, 0.1)

func reset_sidestep_pose() -> void:
	"""
	Return the limb/body roll used by the sidestep back to their rest values.

	The sidestep is the only animation that rolls the LIMBS on Z, so nothing else
	puts that back on its own. We snap it here when a step ends so a finished
	step never leaves the legs slightly splayed.

	The BODY's roll is shared now — the walk gait writes `character_body.rotation.z`
	for a hero with a `sway_deg` (the waddle), which is exactly why
	`animate_walking()` calls this FIRST and then writes its own roll over the
	top. `relax_gait_extras()` is the other half: it is what puts the body's
	roll, pitch and head bobble back when the walk stops.
	"""
	if left_arm and original_rotations.has("left_arm"):
		left_arm.rotation.z = original_rotations["left_arm"].z
	if right_arm and original_rotations.has("right_arm"):
		right_arm.rotation.z = original_rotations["right_arm"].z
	if left_leg and original_rotations.has("left_leg"):
		left_leg.rotation.z = original_rotations["left_leg"].z
	if right_leg and original_rotations.has("right_leg"):
		right_leg.rotation.z = original_rotations["right_leg"].z
	if character_body and original_rotations.has("body"):
		character_body.rotation.z = original_rotations["body"].z
