class_name PlayerAbilities
extends RefCounted
## THE FOUR F ABILITIES — lifted whole out of `player_controller.gd`
## (bd godot-test1-ftn.15, epic `ftn`, the split the epic's FRAMEWORK point 3
## names beside `player_animation.gd`).
##
## THE SPLIT. The `CharacterBody3D` keeps movement, capture, respawn, the input
## map, the null-safe discovery lookups every section shares, the ability STATE
## VARS and the whole HUD contract surface; this file keeps the ARMS — the
## activation, the four powers, their timers, Teibi's fit probes and Air Sight.
## It is a MOVE and nothing else: not one number, not one branch and not one
## comment changed.
##
## WHY A `RefCounted` HOLDING THE PLAYER — `player_animation.gd`'s idiom one
## concern along, and for the same reason: an arm reaches half the body on every
## press (`global_position`, `velocity`, `transform`, `collision_shape`, the
## skill lookups, `_sfx`), so a static library would be handed all of it as
## out-params. One object, created with the body and freed with it. That
## reference is untyped on purpose: `player_controller.gd` carries no
## `class_name` (its readers `preload` it), so there is no type to write and
## nothing here can create a cyclic dependency.
##
## THE STATE STAYS ON THE NODE, and that is the difference from
## `player_animation.gd`. `ability_cooldowns`, `windman_boost_timer`,
## `windman_sight_timer`, `teibi_size_state`, `teibi_form_timer`, `is_giant`,
## `_teibi_tween`, `speed_burst_timer` and `_pending_cooldown_refund` are read
## by `mp_manager` (the `ab` presence bits), by the HUD contract getters, by
## `player_animation` and by four self-checks THROUGH THE PLAYER NODE — so they
## stay where every reader already binds them and the arms write them through
## `player`.
##
## AND SO DOES EVERY NAME: `player_controller.gd` keeps a one-line forwarder for
## each function here. That is the epic's rule-(d) exception, and it is not
## politeness — `ability_hud.gd`, `mp_manager.gd`, `tower_interior.gd`,
## `player_animation.gd`, `coin.gd` and six self-checks call these names on the
## "player" group's one node, twenty-three call sites for `try_activate_ability`
## alone. The group answers to one node; this file is where the code lives.

## THE BODY THIS EMPOWERS. Assigned once by `PlayerController._init()`, exactly
## like `PlayerAnimation.player` beside it.
var player = null


# ============================================================================
# THE ABILITY CONSTANT BANNER
# ============================================================================
## Moved here whole with the arms, and ALIASED BACK on the player
## (`const TEIBI_SCALE_BIG := PlayerAbilities.TEIBI_SCALE_BIG` and so on),
## because `tower_interior.gd`, `capture_selfcheck`, `progression_selfcheck` and
## `tower_interior_selfcheck` read them off the player script.
##
## TWO STAYED BEHIND and both are on the player for a reason:
##   * `CHARACTER_SPEED` is a MOVEMENT multiplier — `calculate_current_speed()`
##     is its only reader and movement did not move.
##   * `WINDMAN_AIR_SPEED` is `WALK_SPEED * 5.0`, and `WALK_SPEED` is the
##     player's. Restating the derivation here would let a walk-speed retune
##     stop reaching the Air Rush, and a `preload` back to `player_controller.gd`
##     is the cyclic dependency this file's header refuses. So it stays with the
##     number it is derived from and `_ability_windman()` reads
##     `player.WINDMAN_AIR_SPEED`.

## One-shot expanding "wave" visual, reused by several abilities. We spawn it into
## the world (parented to our parent) so it lives on its own and frees itself.
const ABILITY_EFFECT := preload("res://scripts/ability_effect.gd")

## Per-character cooldown length, in seconds. Tunable — longer for stronger powers.
const ABILITY_COOLDOWN := {
	"windman": 8.0,
	"primm": 6.0,
	"teibi": 4.0,
	"phoboman": 12.0,
}

## Friendly ability names shown on the cooldown HUD.
const ABILITY_NAME := {
	"windman": "Air Rush",
	"primm": "Phase Step",
	"teibi": "Resize",
	"phoboman": "Stink Wave",
}

# --- Windman: Air Rush ---
## How long the boost lasts, in seconds.
const WINDMAN_BOOST_DURATION: float = 4.0
## Gravity multiplier while boosting, so Windman glides instead of dropping.
## Retuned with the snappy-jump gravity change: 14.4 × 0.1125 = 1.62 m/s² —
## byte-identical to the old 3.6 × 0.45, so the Air Rush glide feel is
## preserved exactly even though base gravity quadrupled.
const WINDMAN_GRAVITY_FACTOR: float = 0.1125
## Upward launch applied on activation so he gets airborne to use the speed.
const WINDMAN_LIFT: float = 6.0

# --- Windman: Air Sight (bead godot-test1-oht) ---
## INDOORS, F IS A DIFFERENT ABILITY. Air Rush is a take-off and the HQ has a
## ceiling 4.6 m up, so in there the same key spends the same cooldown on the other
## half of "make the air work for him": the walls of the storey you are on go
## translucent and you can watch a patrol through them before committing to a
## corridor. Same dispatch, same cooldown dial, same block-reason surface — the
## branch is one `if` in `_ability_windman()` and everything downstream is unchanged.
##
## How long the walls stay see-through, in seconds. Long enough to read a room and
## watch one guard's leg of a patrol, short enough that the fill-rate cost of a
## storey of transparent walls on web `gl_compatibility` is a window and not a mode.
##
## IT IS NOT BOUNDED BY THE COOLDOWN AND MUST NOT BE MADE TO BE (codex review): 8.0 s
## is the UNSKILLED cooldown, and `_skilled_ability_cooldown()` takes a fully-ranked
## Windman to 4.80 s — under this duration, so a press on every recharge would hold
## the building transparent forever. That is the `"LAND"` gate's bug exactly, one
## ability along, and it takes the same answer: the STATE INVARIANT that was missing,
## not a retune. `"SEEING"` refuses the press while a look is already running, so
## cooldown ranks stay a straight buff (they shorten the wait, never the look) and
## the x-ray is a window whatever the skill tree says.
const WINDMAN_SIGHT_DURATION: float = 7.0

## The name the HUD gives Windman's F under the roof. A const rather than a literal
## because `help_selfcheck` reads it: the `?` card names every ability by walking
## `ABILITY_NAME`, and an ability that is not in that dict — because it is a second
## ability on an existing hero, not a fifth hero — would otherwise be the one thing
## the card is allowed to be silently wrong about.
const INDOOR_ABILITY_NAME: String = "Air Sight"

# --- Primm: Phase Step ---
## Desired blink distance — far enough to clear a single block in open ground.
const PRIMM_BLINK_DISTANCE: float = 6.0
## If the desired landing spot is inside a block, keep scanning outward in steps
## of this size until a clear spot is found (so Primm always exits the far side).
const PRIMM_BLINK_STEP: float = 0.5
## How far out the scan looks before giving up (covers any structure in-game).
const PRIMM_BLINK_MAX_DISTANCE: float = 40.0

# --- Teibi: Resize ---
## Scale factors for the small and giant forms (1.0 is the normal size).
const TEIBI_SCALE_SMALL: float = 0.45
const TEIBI_SCALE_BIG: float = 2.2
## How much the giant-fit probe pulls its capsule in AT THE BOTTOM ONLY before
## asking the physics server whether the grown body fits (`_teibi_grow_blocked`).
##
## The floor the player is standing on is always touching the capsule's bottom, so
## an honest full-size probe reports "blocked" everywhere and Resize would never
## grow at all. 5 cm is under any real clearance in the game and far more than the
## contact epsilon. The TOP is never trimmed: this number is an allowance for the
## floor, and spending it at the head would licence 5 cm of skull inside a ceiling.
const TEIBI_FIT_GROUND_CLEAR: float = 0.05

## How long Teibi may stay in an altered form (small OR giant) before he snaps
## back to normal on his own — no extra press needed. This is a TOTAL budget for
## the whole small/giant excursion: switching small↔giant does not refill it.
const TEIBI_FORM_DURATION: float = 10.0

## How long the automatic revert waits before asking AGAIN whether the normal
## capsule fits where the body is standing (bd godot-test1-3iy.23, codex review).
##
## The timeout used to grow the body back unconditionally, which was harmless while
## every space in this game was at least 2 m tall. The HQ's crawl alcove is 1.2 m,
## so a small Teibi whose form expires in there would have been inflated INSIDE
## solid stone and squirted out along whichever axis the depenetration liked —
## `_teibi_grow_blocked`'s bug, in the other direction. So the revert waits for
## room instead of forcing it, and this is how often it re-asks: five times a
## second, which is instant to a player walking out and costs one shape query per
## tick for one hero in a place he can only be by choosing to crawl in. Nothing can
## strand him — SMALL is not a penalty, F is not refused indoors, and the first
## frame the capsule fits he stands up.
const TEIBI_REVERT_RETRY: float = 0.2

## Seconds of shockwave flight Teibi's Crush Quake buys (the `quake` skill node).
## Deliberately far shorter than Phoboman's whole ability — the quake is a
## side-effect of a transformation Teibi wanted anyway, not a fear power.
const TEIBI_QUAKE_FLEE_DURATION: float = 3.0

# --- Phoboman: Stink Wave ---
## How long crocodiles flee after one whiff, in seconds.
const PHOBOMAN_FLEE_DURATION: float = 10.0
## Visual reach of the stink waves, in metres.
const PHOBOMAN_STINK_RADIUS: float = 9.0
## GAMEPLAY reach of the stink — how far a crocodile may be and still flee.
##
## THIS IS NEW IN BEAD godot-test1-20z.4 AND IT IS A DELIBERATE NERF; the number
## is derived rather than picked. Before it, `_ability_phoboman()` walked the
## whole "crocodile" group with no distance test at all, so the ability's only
## bound was an accident of `flee_from()`'s slept-crocodile early return (the LOD
## manager sleeps past `SIM_RADIUS` + hysteresis = 50 m). One press therefore
## disarmed every crocodile within ~50 m — including the pack 40 m down the road
## the player was about to run into — while the telegraph the player saw was a
## 9 m sphere. It also made `phoboman_radius` (Billowing Cloud) a node that cost
## a point and changed nothing but the picture.
##
## 22 m is the smallest honest bound: `DETECTION_RADIUS` is 15, so nothing
## outside 15 m can acquire the player at all, and the extra 7 m covers a
## crocodile closing at `MAX_CHASE_SPEED` (8.5) for the ~0.8 s the wave takes to
## play. Bosses are unaffected either way — `flee_from()` early-returns for one.
## So the crocodiles that stop being feared are the ones in the 22–50 m band,
## which could not have hunted the player during the flight anyway: the nerf is
## real on paper and close to invisible in play, and it buys a live skill node.
const PHOBOMAN_FLEE_RADIUS: float = 22.0


# ============================================================================
# THE ARMS
# ============================================================================

func _update_ability_timers(delta: float) -> void:
	"""Count down cooldowns, the Windman air boost, Teibi's form timer and the
	Adrenaline speed burst."""
	for i in player.ability_cooldowns.size():
		if player.ability_cooldowns[i] > 0.0:
			player.ability_cooldowns[i] = maxf(0.0, player.ability_cooldowns[i] - delta)
	if player.speed_burst_timer > 0.0:
		player.speed_burst_timer = maxf(0.0, player.speed_burst_timer - delta)
	if player.windman_boost_timer > 0.0:
		player.windman_boost_timer = maxf(0.0, player.windman_boost_timer - delta)
		# Wet wings: a Windman who flies INTO a storm cloud's rain zone drops out
		# of the Air Rush immediately — the boost timer is zeroed and the normal
		# gravity/speed rules take back over mid-air. (Only checked while a boost
		# is actually running, so a grounded player never pays for this.)
		if player.windman_boost_timer > 0.0 and player._weather_is_raining_here():
			player.windman_boost_timer = 0.0
	if player.windman_sight_timer > 0.0:
		player.windman_sight_timer = maxf(0.0, player.windman_sight_timer - delta)
		# Walking back out ends it too — the same shape as the wet-wings drop above,
		# and for the same reason: the ability is a property of being INSIDE this
		# building, so carrying it out of the door would leave a translucent HQ
		# standing behind a player who is no longer in it. (Only asked while the
		# sight is actually running, so nobody else pays for the lookup.)
		if player.windman_sight_timer <= 0.0 or not player._sheltered():
			_end_air_sight()
	# Teibi's small/giant form expires on its own after a while, snapping him back
	# to normal size with no extra press — so he can never get stuck transformed.
	if player.teibi_size_state != 0 and player.teibi_form_timer > 0.0:
		player.teibi_form_timer = maxf(0.0, player.teibi_form_timer - delta)
		if player.teibi_form_timer <= 0.0:
			# ...BUT ONLY WHERE THE NORMAL BODY FITS (bd godot-test1-3iy.23, codex
			# review). Inflating inside stone is the exact shape of the tower breach
			# `_teibi_grow_blocked` closes, and the HQ's 1.2 m crawl alcove is the
			# first space in this game a normal capsule does not fit in. The revert
			# is DEFERRED, never cancelled: `TEIBI_REVERT_RETRY` re-asks five times a
			# second and the first frame there is room he stands up. The forced
			# reverts below and in `_reset_ability_states()` are unconditional on
			# purpose — a character switch, a respawn and the no-giant-indoors ruling
			# are not the body's decision to make.
			if _teibi_fit_blocked(1.0):
				player.teibi_form_timer = TEIBI_REVERT_RETRY
			else:
				_revert_teibi_to_normal()
	# NO GIANT INSIDE THE HQ, EVER (bead godot-test1-xdf). `get_ability_block_reason()`
	# refuses the press in there, which leaves exactly one way the state could still
	# exist indoors: growing outside and walking in. So it reverts AT THE DOOR, down
	# the same path the form timer uses, and the ruling ("Teibi can't be huge inside
	# the HQ") becomes a property of the body rather than of the door being watched.
	# Asked only while he is actually giant — a normal-size hero pays nothing.
	if player.is_giant and player._sheltered():
		_revert_teibi_to_normal()


func _cooldown_remaining() -> float:
	"""
	The cooldown that stands in the way of an F press RIGHT NOW, in seconds —
	which is NOT always the timer sitting in `ability_cooldowns`.

	THIS IS THE ONE HOME OF THE COOLDOWN READ, for exactly the reason
	`get_ability_block_reason()` is the one home of the gates: the key press, the
	dial's arc, the dial's seconds text and `is_ability_ready()` all ask it, so
	the HUD can never paint an amber countdown over a press that fires. A waiver
	written at the press alone IS that bug — and the dial's three states come out
	of the ratio and `is_ability_ready()`, so it would have shown up in both.

	THE WAIVER (bead godot-test1-8rg, owner: "teibi shouldn't mandatory wait in
	tiny state cooldown to become giant"): while Teibi is ALREADY in an altered
	form, the next resize is free. Normal → small is the press that costs the 4 s;
	small is the weakest state in the game, and being parked there for a whole
	cooldown read as a punishment for using the ability rather than as its price.
	ENTERING an altered form from normal still pays, because `teibi_size_state` is
	0 at that press — the waiver cannot fire on the press that starts the cycle.

	IT WAIVES THE COOLDOWN AND NOTHING ELSE. `try_activate_ability()` asks the
	gates AFTER this, so INDOOR (no giant in the HQ, bead godot-test1-xdf) and
	TIGHT (`_teibi_grow_blocked()`) refuse a waived press exactly as they refuse a
	charged one; and the form budget is untouched, so a giant reached sooner is
	reached out of the SAME `TEIBI_FORM_DURATION` (`_ability_teibi()` refills it
	only from `prev_state == 0`) — a faster giant, never a longer one.

	The character name is checked as well as the state because `ability_cooldowns`
	is per-hero: a stale non-zero `teibi_size_state` must not be able to waive
	somebody else's cooldown. (It cannot today — every switch reverts him — which
	is why this is a belt, not a fix.)
	"""
	if player.teibi_size_state != 0 and String(player.CHARACTERS[player.current_character_index]["name"]) == "teibi":
		return 0.0
	return player.ability_cooldowns[player.current_character_index]


func try_activate_ability() -> void:
	"""
	Fire the current character's special ability if it isn't on cooldown. Each
	ability function returns true when it actually triggered, which is what starts
	the cooldown — so a no-op never locks the power.
	"""
	var char_name: String = player.CHARACTERS[player.current_character_index]["name"]

	# Still cooling down? The press doesn't fire, but it must not feel dead:
	# flash the cooldown dial red (via the "ability_hud" group — null-safe, no
	# hard reference, like every other HUD hookup) and play a low denial buzz.
	# Asked through `_cooldown_remaining()` so this press and the dial read the
	# same number — see the waiver documented there.
	if _cooldown_remaining() > 0.0:
		_flash_blocked_feedback()
		return

	# Charged, but is anything else in the way? The gates live in ONE function so
	# the HUD can ask the same question the key press asks — see
	# `get_ability_block_reason()`. A gated press refuses exactly like a cooling
	# one (same dial flash, same denial buzz) and costs no cooldown, so the player
	# can try again the instant the gate lifts.
	if player.get_ability_block_reason() != "":
		_flash_blocked_feedback()
		return

	var used := false
	match char_name:
		"windman":
			used = _ability_windman()
		"primm":
			used = _ability_primm()
		"teibi":
			used = _ability_teibi()
		"phoboman":
			used = _ability_phoboman()

	if used:
		# The skilled duration, and it MUST be the same expression
		# `get_ability_cooldown_ratio()` divides by — see the note there.
		var cooldown: float = player._skilled_ability_cooldown()
		# ...minus anything an ability earned back on the way through (Primm's
		# Phase Echo). A generic one-shot rather than a Primm branch: it costs one
		# float, and the active-skills bead has more of these coming.
		cooldown = maxf(0.0, cooldown - player._pending_cooldown_refund)
		player._pending_cooldown_refund = 0.0
		player.ability_cooldowns[player.current_character_index] = cooldown
		# Whoosh only when the ability actually fired — a failed Primm blink that
		# costs no cooldown stays silent too.
		player._sfx("play_ability", char_name)


func _flash_blocked_feedback() -> void:
	"""
	The one "that press was refused" signal: flash the cooldown dial red (via the
	"ability_hud" group — null-safe, no hard reference, like every other HUD
	hookup) and play the low denial buzz. Shared by the cooling-down F press,
	Windman-in-the-rain, and an E press locked to a single hero by the lobby, so
	a refusal always feels the same wherever it comes from.
	"""
	var hud: Node = player.get_tree().get_first_node_in_group("ability_hud")
	if hud and hud.has_method("flash_blocked"):
		hud.flash_blocked()
	player._sfx("play_buzz")


func _ability_windman() -> bool:
	"""Air Rush: launch up and forward, then soar fast with softened gravity —
	or, under the HQ's roof, Air Sight instead (see `_ability_air_sight`)."""
	if player._sheltered():
		return _ability_air_sight()
	var forward: Vector3 = -player.transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()

	player.windman_boost_timer = WINDMAN_BOOST_DURATION * player._skill_mult("windman_boost")
	# Kick the lens wide for the launch moment — the FOV code in _process adds
	# this on top of the speed-scaled target and decays it back to zero.
	player.fov_punch = player.FOV_PUNCH_WINDMAN
	# Launch: up so he is airborne, plus an immediate forward shove so even a
	# standing press blasts off into the wind right away.
	#
	# WINDMAN_LIFT is the ONE thing a skill may make jump higher, and that is an
	# epic-level decision rather than a local one: mountain massifs are impassable
	# because the base jump apex (3.6125 m) is under MOUNTAIN_MIN_LAYER_HEIGHT
	# (4.0), so there is deliberately NO skill anywhere touching JUMP_VELOCITY.
	# The "fly higher" fantasy routes through Air Rush, which is already the
	# sanctioned way over terrain.
	player.velocity.y = WINDMAN_LIFT * player._skill_mult("windman_lift")
	player.velocity.x = forward.x * player.WINDMAN_AIR_SPEED
	player.velocity.z = forward.z * player.WINDMAN_AIR_SPEED

	# An airy cyan swirl around him to sell the gust.
	_spawn_ability_effect(player.global_position, Color(0.7, 0.92, 1.0, 0.4), 5.0, 0.6)
	return true


func _ability_air_sight() -> bool:
	"""
	Air Sight: for `WINDMAN_SIGHT_DURATION` the walls of the storey Windman is on go
	translucent, so he can read the layout and — the point — watch a guard's patrol
	through them before stepping into a corridor.

	WINDMAN'S INDOOR F, and it is the same ability rather than a fifth one: the wind
	is what he bends either way, and Air Rush under a 4.6 m ceiling was already a
	press that did nothing worth doing. Everything around it is untouched — the same
	dispatch, the same cooldown, the same dial, the same refusal surface.

	THE BUILDING DOES THE WORK (`TowerInterior.set_xray`), through the same null-safe
	group + `has_method` door every other system reads. No interior in the tree means
	no ability: `false` back, so `try_activate_ability()` charges no cooldown and the
	press can be tried again the moment he is somewhere it means something. That is
	the standing "a no-op never locks the power" rule, and it is what keeps a Windman
	standing under a roof this game does not have from losing eight seconds to it.
	"""
	var interior: Node = player.get_tree().get_first_node_in_group("tower_interior")
	if interior == null or not interior.has_method("set_xray"):
		return false
	interior.call("set_xray", true)
	player.windman_sight_timer = WINDMAN_SIGHT_DURATION
	# The same self-building, self-freeing sphere every other ability sells itself
	# with — small and pale here, because the effect the player should be looking at
	# is the room around him going see-through.
	_spawn_ability_effect(player.global_position, Color(0.7, 0.92, 1.0, 0.3), 2.5, 0.5)
	return true


func _end_air_sight() -> void:
	"""
	Put the walls back. Idempotent and safe to call for any character at any time —
	which is what lets `_reset_ability_states()` call it unconditionally beside
	`_revert_teibi_to_normal()`, and what makes "cleared on switch, on respawn and on
	the way out of the door" one line each instead of a state machine.

	The interior is looked up fresh rather than remembered: the tower streams out
	with the terrain, and a remembered reference would be the one thing in this
	script holding a freed node.
	"""
	player.windman_sight_timer = 0.0
	var interior: Node = player.get_tree().get_first_node_in_group("tower_interior")
	if interior != null and interior.has_method("set_xray"):
		interior.call("set_xray", false)


func _ability_primm() -> bool:
	"""
	Phase Step: instantly blink straight forward, passing THROUGH any block. Primm
	must never end up stuck inside geometry, so instead of a blind fixed hop we
	scan forward from the desired distance and land at the first spot where his
	body actually fits — which is always on the far side of whatever he phased
	through (a single block, a wall, or a whole pyramid). If there's no clear spot
	within reach (facing into an enormous solid), the blink simply doesn't fire and
	costs no cooldown.
	"""
	var forward: Vector3 = -player.transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		return false
	forward = forward.normalized()

	# March outward for the first position where Primm's body is NOT inside a block.
	# Long Step lengthens the DESIRED distance only; the scan still gives up at
	# PRIMM_BLINK_MAX_DISTANCE, which is what bounds the skill without a cap of its
	# own (a blink that lands past 40 m simply never happens).
	var target: Vector3 = player.global_position
	var found := false
	var d: float = player.phase_reach()
	while d <= PRIMM_BLINK_MAX_DISTANCE:
		var candidate: Vector3 = player.global_position + forward * d
		if not _is_body_blocked_at(candidate):
			target = candidate
			found = true
			break
		d += PRIMM_BLINK_STEP

	if not found:
		return false

	# Phase Echo: a wall-pass hands back whole seconds of cooldown, applied by
	# `try_activate_ability()` when it charges it.
	#
	# THE WALL IS USUALLY NOT AT THE LANDING SPOT, which is why this needs its own
	# scan rather than a flag set by the loop above. That loop starts at the
	# DESIRED distance and only ever walks OUTWARD, so the ordinary case — a single
	# 2 m block three metres ahead, with the 6 m landing spot in open ground — sees
	# a clear first candidate and never notices the wall it just went through. The
	# whole travelled segment is what has to be tested.
	#
	# Gated on the skill being ranked, so an unranked Primm pays for none of these
	# extra shape queries; and it is a key press either way, not a per-frame path.
	var refund: float = player._skill_bonus("primm_refund")
	if refund > 0.0 and _blink_passed_through(target):
		player._pending_cooldown_refund = refund

	# A quick flash where he leaves and where he arrives, to sell the teleport —
	# plus three small staggered flashes along the path between them, so the eye
	# can track WHERE the blink went instead of seeing two disconnected pops.
	_spawn_ability_effect(player.global_position, Color(0.45, 0.5, 1.0, 0.5), 2.0, 0.35)
	for i in range(3):
		_spawn_ability_effect(player.global_position.lerp(target, (i + 1) / 4.0),
			Color(0.45, 0.5, 1.0, 0.4), 1.0, 0.25, i * 0.05)
	player.global_position = target
	player.velocity = Vector3.ZERO  # land cleanly on the far side, no carried momentum
	_spawn_ability_effect(player.global_position, Color(0.45, 0.5, 1.0, 0.5), 2.0, 0.35)
	return true


func _blink_passed_through(target: Vector3) -> bool:
	"""
	True when solid geometry stands anywhere BETWEEN the player and `target` — i.e.
	when the blink about to happen is a genuine wall-pass rather than a hop across
	open ground. Sampled at `PRIMM_BLINK_STEP` with the same capsule-centre probe
	the landing scan uses, so the flat ground never counts and the two agree about
	what "solid" means.

	Called only for a Primm who has bought Phase Echo (see `_ability_primm`), on a
	key press, so a dozen shape queries is the right shape of cost. `ponytail:` a
	single swept capsule would be one query instead — the ceiling here is a wall
	thinner than the 0.5 m step slipping between two samples, which reads as "no
	refund that time", never as a wrong teleport.
	"""
	var travel: Vector3 = target - player.global_position
	var distance := travel.length()
	if distance <= PRIMM_BLINK_STEP:
		return false
	var direction := travel / distance
	var d := PRIMM_BLINK_STEP
	while d < distance:
		if _is_body_blocked_at(player.global_position + direction * d):
			return true
		d += PRIMM_BLINK_STEP
	return false


func _is_body_blocked_at(pos: Vector3) -> bool:
	"""
	True if solid geometry occupies Primm's body space at world position `pos`.
	We probe with a small sphere at capsule-CENTRE height (not at the feet) so the
	flat ground — which the capsule always rests on — never counts as "blocked";
	only blocks and structures that rise above the ground do.
	"""
	var probe := SphereShape3D.new()
	probe.radius = 0.5
	# Lift the probe to the capsule's centre height so it clears the ground plane.
	return _shape_blocked(probe, pos + Vector3(0.0, player.collision_base_y, 0.0))


func _teibi_grow_blocked() -> bool:
	"""
	True when the GIANT capsule would not fit where the body is standing right now.

	THE FIX FOR THE TOWER BREACH (bead godot-test1-3uh), and it is a fix anywhere:
	growing inside geometry buries the grown capsule in it and the physics server's
	depenetration then squirts the body out along the shallowest axis — which, in a
	4.6 m storey a 4.4 m giant does not fit under, is UP, through the ceiling, onto
	the next floor. That turned Resize into a free lift past every gate the tower's
	softlock audit believes in. Refusing the growth is the root cause; no amount of
	geometry tuning covers "the body got bigger than the room".

	The probe is the ACTUAL grown capsule, not Primm's point-sized sniff, because
	the ceiling is the half of the exploit a mid-height sphere cannot see. Only its
	BOTTOM is pulled in, by `TEIBI_FIT_GROUND_CLEAR`, so the floor the player is
	standing on — and only the floor — is not itself an overlap; that is the same
	"the ground is not an obstacle" allowance `_is_body_blocked_at` buys with its
	centre-height lift, spent here on a shape that has to span the whole body. The
	TOP is the giant's real crown and is not trimmed (codex review): shortening it
	there would licence exactly `TEIBI_FIT_GROUND_CLEAR` of head inside a ceiling,
	and a head inside a ceiling is the whole bug.

	Cheap enough to sit in `get_ability_block_reason()`, which the HUD polls every
	frame: it runs only for a Teibi whose NEXT press is the growth (size state 1),
	i.e. one query a frame for one hero inside a 10 s window.
	`ponytail:` one shape per call rather than a cached probe — the allocation is a
	RefCounted in a bounded window; cache it if the F3 overlay ever notices.
	"""
	return _teibi_fit_blocked(TEIBI_SCALE_BIG)


func _teibi_fit_blocked(s: float) -> bool:
	"""
	True when Teibi's capsule at scale `s` would not fit where the body is standing.

	@param s: the body scale to test — `TEIBI_SCALE_BIG` for the growth above, 1.0
	    for the automatic revert, which is the other direction of the same bug.

	THE PROBE IS THE ONE ABOVE, PARAMETERISED (bd godot-test1-3iy.23, codex review),
	and it had to become one function rather than two: "would this body fit here"
	has exactly one right answer, and a second copy of the bottom-clearance
	allowance is a second chance to spend it at the head.
	"""
	if not player.collision_shape or not (player.collision_shape.shape is CapsuleShape3D):
		return false
	var capsule: CapsuleShape3D = (player.collision_shape.shape as CapsuleShape3D)
	# Where the capsule's underside sits relative to the body's origin — the same
	# `bottom` `_apply_teibi_scale` pins the grown capsule to, so the probe stands
	# exactly where the giant would.
	var bottom: float = player.collision_base_y - player.collision_half_height
	var top := bottom + capsule.height * s
	var probe := CapsuleShape3D.new()
	probe.radius = capsule.radius * s
	probe.height = maxf(2.0 * probe.radius, top - bottom - TEIBI_FIT_GROUND_CLEAR)
	return _shape_blocked(probe, player.global_position
			+ Vector3(0.0, top - probe.height * 0.5, 0.0))


func _shape_blocked(probe: Shape3D, centre: Vector3) -> bool:
	"""
	THE one "is there solid geometry here" query — the space state, the self
	exclusion and the mask in a single place, so Primm's landing scan and Teibi's
	fit test can never drift apart about what counts as solid or about whose
	collider is our own. Callers bring the shape; the question is shared.
	"""
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	if not space:
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.transform = Transform3D(Basis(), centre)
	query.exclude = [player.get_rid()]  # never sense our own collider
	query.collision_mask = player.collision_mask
	return not space.intersect_shape(query, 1).is_empty()


func _ability_teibi() -> bool:
	"""
	Resize: cycle normal → small → giant → normal. Giant form crushes crocodiles
	(see crushes_crocodiles) but is too heavy to jump (see the jump step). Any
	altered form auto-reverts to normal after TEIBI_FORM_DURATION, so Teibi can
	never get stuck giant or tiny.
	"""
	var prev_state: int = player.teibi_size_state
	player.teibi_size_state = (player.teibi_size_state + 1) % 3
	var s := 1.0
	match player.teibi_size_state:
		1:
			s = TEIBI_SCALE_SMALL
		2:
			s = TEIBI_SCALE_BIG
		_:
			s = 1.0
	_apply_teibi_scale(s)
	player.is_giant = (player.teibi_size_state == 2)

	# Manage the auto-revert budget: start it the moment he first leaves normal,
	# clear it when he's back to normal, and KEEP it running across a small↔giant
	# switch (it's a total time-in-altered-form budget, not per-form).
	if player.teibi_size_state == 0:
		player.teibi_form_timer = 0.0
	elif prev_state == 0:
		player.teibi_form_timer = TEIBI_FORM_DURATION * player._skill_mult("teibi_form")

	# CRUSH QUAKE (the `quake` skill node): landing in giant form shakes the
	# ground and scatters the crocodiles standing on it. `skill_bonus` IS the
	# radius in metres, so an unranked Teibi reads 0 and none of this runs —
	# no branch on the rank, no second constant to keep in step.
	#
	# BOSS IMMUNITY IS NOT RE-IMPLEMENTED HERE and must not be: `flee_from()`
	# early-returns for `is_boss`, which is where Stink Wave's immunity already
	# lives, so a boss shrugs the quake off through the one rule that owns it.
	# (A boss also bites giant Teibi rather than being crushed — `is_boss` is
	# checked above the crush block in `_on_player_collision` — so the tooltip's
	# "bosses shrug it off" is true of both halves of the giant form.)
	var quake_radius: float = player._skill_bonus("teibi_quake")
	if player.is_giant and quake_radius > 0.0:
		_spawn_ability_effect(player.global_position, Color(0.95, 0.7, 0.35, 0.5), quake_radius, 0.5)
		_scare_crocodiles(player.global_position, TEIBI_QUAKE_FLEE_DURATION, quake_radius)
	return true


func _ability_phoboman() -> bool:
	"""Stink Wave: send out smelly waves; every crocodile flees for a while."""
	# A few staggered green waves so it reads as rolling stench, not one pop.
	#
	# TWO RADII, ON PURPOSE. `PHOBOMAN_STINK_RADIUS` (9) is the TELEGRAPH — what
	# the player sees — and `PHOBOMAN_FLEE_RADIUS` (22) is the EFFECT. They are
	# deliberately different because a 22 m sphere drawn at the player's feet
	# fills the screen and reads as a bug rather than as a smell. Billowing Cloud
	# (`phoboman_radius`) scales BOTH by the same multiplier, so the picture and
	# the reach stay in proportion however the node is ranked — and, since bead
	# godot-test1-20z.4 gave the sweep a real bound, that node now buys reach in
	# the effect and not only in the picture. See PHOBOMAN_FLEE_RADIUS for the
	# derivation of 22 and for what the bound costs.
	var reach_mult: float = player._skill_mult("phoboman_radius")
	var stink_radius: float = PHOBOMAN_STINK_RADIUS * reach_mult
	_spawn_ability_effect(player.global_position, Color(0.55, 0.85, 0.2, 0.55), stink_radius, 0.9, 0.0)
	_spawn_ability_effect(player.global_position, Color(0.5, 0.8, 0.25, 0.45), stink_radius, 0.9, 0.18)
	_spawn_ability_effect(player.global_position, Color(0.45, 0.75, 0.3, 0.4), stink_radius, 0.9, 0.36)

	var flee_duration: float = PHOBOMAN_FLEE_DURATION * player._skill_mult("phoboman_flee")
	_scare_crocodiles(player.global_position, flee_duration, PHOBOMAN_FLEE_RADIUS * reach_mult)
	return true


func _scare_crocodiles(origin: Vector3, duration: float, radius: float) -> void:
	"""
	THE one "make the crocodiles round here run away" path, shared by Phoboman's
	Stink Wave and Teibi's Crush Quake — a helper rather than two loops, so the
	radius test, the group discovery and the multiplayer relay each have exactly
	one home and a third fear effect is one call.

	Discovery stays group-based with no hard references, per the project's
	convention, and boss/slept immunity is NOT re-implemented here: `flee_from()`
	owns both early returns, which is what keeps the rule in one file.

	MULTIPLAYER: the local loop runs on EVERY caller, master or not — it is
	correct for the crocodiles this peer still simulates and harmless on the
	remote-driven ones (the next 10 Hz sample overwrites the flag) — and the
	`request_croc_flee` relay asks the master to do the same to the crocodiles it
	is the authority for. That is the same master path bead godot-test1-s86.5
	already built for the Stink Wave, so a new fear effect needs no protocol work
	at all; `radius` is carried INTO the request, so a bounded sweep stays bounded
	room-wide (an unbounded one disarmed every awake crocodile on every screen).
	Nothing comes back and nothing needs to: `is_fleeing` is a bit in the sync
	packet, so the master's copy of the flight reaches every screen for free.
	"""
	var radius_sq := radius * radius
	for croc in player.get_tree().get_nodes_in_group("crocodile"):
		if not (croc is Node3D) or not croc.has_method("flee_from"):
			continue
		if (croc as Node3D).global_position.distance_squared_to(origin) > radius_sq:
			continue
		croc.flee_from(origin, duration)

	var mp: Node = player._mp()
	if mp and mp.has_method("request_croc_flee"):
		mp.request_croc_flee(origin, duration, radius)


func _current_teibi_scale() -> float:
	"""The character's current base scale from Teibi's size cycle (1.0 for every
	other character — their state is always 0). The landing squash multiplies
	around this so a squashed small/giant Teibi stays small/giant."""
	match player.teibi_size_state:
		1:
			return TEIBI_SCALE_SMALL
		2:
			return TEIBI_SCALE_BIG
		_:
			return 1.0


func _apply_teibi_scale(s: float) -> void:
	"""
	Resize the visible model AND the collision capsule to scale `s`, keeping the
	capsule's bottom pinned to the ground so the player never sinks into the floor
	or gets launched when growing or shrinking.

	Why the position tweak: scaling the CollisionShape3D node scales the capsule
	about the node's origin, which would move the capsule's bottom up/down. We move
	the node so the bottom stays exactly where it was at normal size.
	"""
	if player.character_container:
		# The VISUAL scale tweens with a springy overshoot so the resize pops
		# instead of snapping. Kill any in-flight resize tween first so rapid
		# F-presses don't leave two tweens fighting over the same property.
		if player._teibi_tween:
			player._teibi_tween.kill()
		player._teibi_tween = player.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		player._teibi_tween.tween_property(player.character_container, "scale", Vector3(s, s, s), 0.25)
	if player.collision_shape:
		# The COLLISION capsule snaps to the new size instantly — physics must
		# never lag the visual, or a "still shrinking" giant could clip blocks
		# and the first-person eye height would be mid-tween wrong.
		player.collision_shape.scale = Vector3(s, s, s)
		var bottom: float = player.collision_base_y - player.collision_half_height
		player.collision_shape.position.y = bottom + s * player.collision_half_height
	# First-person eyes are derived from this capsule scale, so a resize must
	# immediately re-seat the spring arm (which carries the camera) at the new
	# height — small Teibi looks from down low, giant Teibi from up high.
	# _apply_view_mode() is idempotent, so this is safe from every caller
	# (F-cycle, form timeout, character switch, respawn).
	if player.view_mode == player.ViewMode.FIRST_PERSON:
		player._apply_view_mode()


func _spawn_ability_effect(pos: Vector3, color: Color, max_radius: float, lifetime: float, delay: float = 0.0) -> void:
	"""
	Spawn a one-shot expanding/fading wave at a world position. Parented to our
	parent (the main scene) so it lives independently of the player and frees
	itself when finished — no manual cleanup, no leak.
	"""
	var parent: Node = player.get_parent()
	if not parent:
		return
	var fx := MeshInstance3D.new()
	fx.set_script(ABILITY_EFFECT)
	parent.add_child(fx)
	fx.global_position = pos
	fx.setup(color, max_radius, lifetime, delay)


func _reset_ability_states() -> void:
	"""Clear transient ability state on respawn (air boost, air sight, giant/small form)."""
	player.windman_boost_timer = 0.0
	player.speed_burst_timer = 0.0
	player._pending_cooldown_refund = 0.0
	_revert_teibi_to_normal()
	# Air Sight lives in the BUILDING's materials rather than in a field here, so it
	# is the one transient state that leaks something visible if it is not cleared:
	# switch character mid-ability and the HQ would stay see-through with nobody
	# holding it that way.
	_end_air_sight()
	# Sidestep is transient too: the caught/respawn/game-over branches all return
	# BEFORE update_sidestep(), so a player caught mid-step would otherwise come
	# back with is_stepping still true and slide sideways out of the spawn.
	if player.is_stepping:
		player.is_stepping = false
		player.step_direction = 0.0
		player.anim.reset_sidestep_pose()


func _revert_teibi_to_normal() -> void:
	"""Snap Teibi back to normal size — used by the form timeout, character switch,
	and respawn. Safe to call for any character (a normal-size body is the default)."""
	player.teibi_size_state = 0
	player.is_giant = false
	player.teibi_form_timer = 0.0
	_apply_teibi_scale(1.0)
