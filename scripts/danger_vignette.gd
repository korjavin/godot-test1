extends Control
## Danger telegraph: a screen-EDGE vignette + ramping heartbeat that warn the
## player something is actively hunting them BEFORE the hit lands.
##
## TWO KINDS OF THREAT, TWO CHANNELS: a red glow with a heartbeat for an animal,
## a cold scanning rim for a GD-SURVEY hunter. See VIGNETTE_SHADER_CODE for what
## separates them and for what the player sees when both are closing at once.
##
## The CrocodileLODManager already iterates every crocodile ~9 Hz with the
## player position in hand; it publishes a 0..1 danger LEVEL here via
## `set_danger_level()` (group "danger_vignette", null-safe — the project's
## standard no-hard-refs convention). A level rather than raw metres because
## each chaser has its OWN smell range (15 m regular, 25 m boss), so the manager
## normalises by the radius of the croc that is actually hunting; a single range
## on this side would leave a boss un-telegraphed over its extra 10 m — and it is
## what makes a hunter's 25 m warning arrive as early as a boss's for free. This
## node turns those numbers into two feedback channels:
##   - VISUAL: a fullscreen ColorRect running a tiny canvas_item shader (built
##     in code — no asset files) that tints only the screen edges, fading in as
##     the chaser closes. Deliberately cheap: ONE 2D quad and ONE draw for both
##     threat channels, and even that cost is skipped (`visible = false`)
##     whenever there is no danger of either kind.
##   - AUDIO: the sound manager's pre-baked "heartbeat" loop (see
##     sound_manager.gd), fetched via get_loop_player("heartbeat"). We own
##     play/stop and drive pitch_scale + volume_db live, so the heart beats
##     faster and louder as the croc closes its detection range → 0. play() is
##     gated on is_unlocked() — the browser-gesture gate only guards the
##     manager's own play_* methods, not loop players driven directly.
##
## The published level only arrives ~9 Hz (the LOD scan cadence), so the
## displayed alpha is EASED toward its target every frame — the vignette
## breathes smoothly instead of stepping visibly at scan rate.

# ============================================================================
# CONSTANTS
# ============================================================================

## Vignette opacity at point-blank range (danger level 1.0). Kept well under
## fully opaque so the world stays readable while the player flees.
const MAX_ALPHA: float = 0.45

## How fast the displayed alpha eases toward its target (per second, lerp
## weight). High enough to feel responsive, low enough to hide the 9 Hz steps.
const ALPHA_EASE_SPEED: float = 6.0

## Heartbeat ramp endpoints: calm distant thump → fast loud pounding at 0 m.
const HEARTBEAT_PITCH_FAR: float = 1.0
const HEARTBEAT_PITCH_NEAR: float = 1.8
const HEARTBEAT_VOLUME_FAR_DB: float = -18.0
const HEARTBEAT_VOLUME_NEAR_DB: float = -6.0

## How long (seconds) the danger level must stay at zero before the heartbeat
## loop is actually stopped. Jumping is the documented way to break a
## crocodile's scent (piglet_crocodile_ai clears is_chasing the moment the
## player leaves the ground), so a normal run-and-jump chase drops the level to
## 0 for roughly a second at a time. Without this hold the loop would stop and
## restart FROM SAMPLE 0 on every jump — the "lub" is the loudest sample in the
## cycle, so each restart clicks. Holding through the gap keeps one continuous
## heartbeat for one continuous chase; a real escape still silences it.
const HEARTBEAT_HOLD: float = 1.5

## Vignette opacity for the MACHINE channel at point blank. A shade under the
## predator's, because its band is narrower and harder-edged and therefore reads
## as brighter at equal alpha.
const MAX_HUNTER_ALPHA: float = 0.38

## The edge-vignette shader — TWO CHANNELS in one fragment, one quad, one draw.
##
## THE TWO ARE MEANT TO BE TELLABLE APART AT A GLANCE (owner ruling, bead
## godot-test1-9rm.6): a GD-SURVEY hunter is a different KIND of threat from an
## animal, so it does not simply redden the same edge harder. They differ on all
## three axes a player reads without thinking about it:
##
##   PREDATOR   warm red    a WIDE soft radial glow (0.35 -> 0.72)   still
##   HUNTER     cold cyan   a NARROW hard rim at the extreme edge     scanning
##                          (0.62 -> 0.80)
##
## The hunter band is modulated by a travelling horizontal wave, which is the
## cheapest thing that reads as a device sweeping a sensor over you rather than
## as an animal breathing. One `sin` per fragment, and only on frames the quad is
## visible at all.
##
## HOW THEY COMPOSE WHEN BOTH ARE CLOSING — the question the ruling asks to be
## answered rather than left to whichever wrote last. They ADD, into one COLOR,
## in DIFFERENT RADIAL BANDS: the red glow lives inside the cyan rim, so at full
## strength on both channels the player sees a cyan scanning border framing a red
## glow, and can still tell which is which. Neither channel can hide the other —
## there is no branch here and no priority — which is the property the ruling
## actually needs, because "a hunter is closing" and "a crocodile is closing" are
## two facts and suppressing either one is a lie about the world.
##
## THE AUDIO SPLIT IS THE OTHER HALF OF THE SAME ANSWER, and it is deliberate:
## the heartbeat below stays on the PREDATOR channel alone. A pounding heart is
## the flesh channel; the machine's channel is its own lock-on ping, fired once
## per engagement from piglet_crocodile_ai. So a lone hunter closing is a silent
## cyan sweep after one ping, an animal is a red glow and a rising heartbeat, and
## the two together are audibly as well as visually two things.
const VIGNETTE_SHADER_CODE: String = """
shader_type canvas_item;

// Per-channel strength, 0 = invisible, both driven from GDScript.
uniform float vignette_alpha = 0.0;
uniform float hunter_alpha = 0.0;

void fragment() {
	// Distance from screen centre in UV space (0 at centre, ~0.71 in corners).
	float dist = distance(UV, vec2(0.5));
	// Only the outer band contributes: fully clear inside 0.35, ramping up
	// smoothly toward the corners, so gameplay in the middle stays unobscured.
	float edge = smoothstep(0.35, 0.72, dist);
	float predator_a = edge * vignette_alpha;

	// The machine channel: a tighter rim, further out, swept by a travelling
	// band. 0.75 + 0.25 * sin keeps the sweep a modulation rather than a
	// flicker — the rim never blinks fully out, it pulses.
	float rim = smoothstep(0.62, 0.80, dist);
	float sweep = 0.75 + 0.25 * sin(UV.y * 34.0 - TIME * 3.0);
	float machine_a = rim * sweep * hunter_alpha;

	// Additive in COVERAGE, weighted-average in COLOUR — so neither channel can
	// suppress the other, and NEITHER IS DARKENED BY THE PRESENCE OF THE SECOND
	// UNIFORM. The naive form (multiply each rgb by its own alpha, then sum both
	// alphas) looks like premultiplied compositing, but this canvas_item is drawn
	// with ordinary alpha blending, so it would apply the alpha TWICE: the red
	// glow would render at a*a and the channel that has shipped for months would
	// quietly go dark. Dividing the weighted sum back out by the total gives
	// exactly the colour the single-channel shader produced whenever the other
	// channel is silent. The max() only guards the divide.
	float total = predator_a + machine_a;
	vec3 tint = (vec3(0.8, 0.05, 0.05) * predator_a
			+ vec3(0.25, 0.85, 0.95) * machine_a) / max(total, 0.0001);
	COLOR = vec4(tint, min(total, 1.0));
}
"""

# ============================================================================
# STATE
# ============================================================================

## Latest published danger level: 0 = nobody hunting, 1 = a chaser at point
## blank. Written by the LOD manager ~9 Hz via set_danger_level.
var _danger_level: float = 0.0

## The same, for the machine channel — a closing GD-SURVEY hunter. Its own
## number rather than a max with the one above, because the two are drawn as two
## different things (see VIGNETTE_SHADER_CODE).
var _hunter_level: float = 0.0

## The alpha actually on screen this frame, eased toward the target.
var _display_alpha: float = 0.0

## The machine channel's on-screen alpha, eased at the same rate.
var _hunter_display_alpha: float = 0.0

## Whether WE started the heartbeat loop (so we know to stop it when safe).
var _heartbeat_playing: bool = false

## Seconds of continuous "no danger" so far, against HEARTBEAT_HOLD (see there).
var _heartbeat_quiet: float = 0.0

## The fullscreen quad running the vignette shader.
var _rect: ColorRect


# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	# Group registration — how the LOD manager finds us (no hard refs).
	add_to_group("danger_vignette")
	# Never block clicks/touches; this is pure feedback.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Build the shader + quad entirely in code (no asset files, matching the
	# synthesized-audio convention).
	var shader := Shader.new()
	shader.code = VIGNETTE_SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader

	_rect = ColorRect.new()
	_rect.material = mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)

	# Start hidden: visible=false skips the fullscreen shader entirely while
	# there is no danger (the common case).
	visible = false


func set_danger_level(level: float, hunter_level: float = 0.0) -> void:
	## Called by CrocodileLODManager after each ~9 Hz scan: 0..1 each, where 1 is
	## a chaser at point blank and 0 is "nobody of that kind is hunting". Both are
	## already normalised by each chaser's own detection radius (see the header),
	## which is what makes a hunter's 25 m telegraph as early as a boss's rather
	## than as late as a crocodile's 15 m — no radius is restated on this side.
	##
	## `hunter_level` defaults so that a caller that predates the second channel
	## still compiles and simply never lights it — the same forgiving shape every
	## other cross-system hook in this project has.
	_danger_level = level
	_hunter_level = hunter_level


func _process(delta: float) -> void:
	# Danger level t: 0 when nothing hunts, 1 at point blank.
	var t: float = clampf(_danger_level, 0.0, 1.0)

	# Ease the on-screen alpha toward the target so the 9 Hz publish cadence
	# never shows as visible steps.
	var ease: float = minf(1.0, ALPHA_EASE_SPEED * delta)
	var target_alpha: float = t * MAX_ALPHA
	_display_alpha = lerpf(_display_alpha, target_alpha, ease)
	# Snap the asymptotic tail to true zero so we can actually hide the quad.
	if target_alpha == 0.0 and _display_alpha < 0.005:
		_display_alpha = 0.0

	# The machine channel, eased identically. Both must reach true zero before the
	# quad is hidden, or a lone hunter would be telegraphed by nothing at all.
	var hunter_t: float = clampf(_hunter_level, 0.0, 1.0)
	var hunter_target: float = hunter_t * MAX_HUNTER_ALPHA
	_hunter_display_alpha = lerpf(_hunter_display_alpha, hunter_target, ease)
	if hunter_target == 0.0 and _hunter_display_alpha < 0.005:
		_hunter_display_alpha = 0.0

	visible = _display_alpha > 0.0 or _hunter_display_alpha > 0.0
	if visible:
		var mat := _rect.material as ShaderMaterial
		mat.set_shader_parameter("vignette_alpha", _display_alpha)
		mat.set_shader_parameter("hunter_alpha", _hunter_display_alpha)

	_update_heartbeat(t, delta)


# ============================================================================
# HEARTBEAT
# ============================================================================

func _update_heartbeat(t: float, delta: float) -> void:
	## Drive the sound manager's looping heartbeat from the raw danger level
	## (not the eased alpha — audio should track the actual threat instantly).
	var sm := get_tree().get_first_node_in_group("sound_manager")
	if sm == null or not sm.has_method("get_loop_player"):
		# No sound manager (scene run in isolation) → silent, never an error.
		return

	var in_danger: bool = t > 0.0
	_heartbeat_quiet = 0.0 if in_danger else _heartbeat_quiet + delta

	if in_danger and not _heartbeat_playing:
		# The gesture gate only guards the manager's own play_* methods; loop
		# players driven directly must check is_unlocked() themselves. If the
		# gate is still closed we simply retry next frame (no state latched).
		if not (sm.has_method("is_unlocked") and sm.is_unlocked()):
			return
		# Set the ramp BEFORE play(): the loop player is built with the engine
		# default 0 dB, and the "lub" is the loudest sample in the cycle, so
		# starting it before the first volume write pops at full scale instead
		# of the intended -18 dB.
		_apply_heartbeat_ramp(sm, t)
		sm.get_loop_player("heartbeat").play()
		_heartbeat_playing = true
	elif _heartbeat_playing and _heartbeat_quiet >= HEARTBEAT_HOLD:
		# Genuinely clear — not just a jump-length gap (see HEARTBEAT_HOLD).
		sm.get_loop_player("heartbeat").stop()
		_heartbeat_playing = false

	if _heartbeat_playing:
		_apply_heartbeat_ramp(sm, t)


func _apply_heartbeat_ramp(sm: Node, t: float) -> void:
	## Faster and louder as the chaser closes detection_radius → 0. Split out so
	## the pre-play() write and the per-frame write can never drift apart.
	var p: AudioStreamPlayer = sm.get_loop_player("heartbeat")
	p.pitch_scale = lerpf(HEARTBEAT_PITCH_FAR, HEARTBEAT_PITCH_NEAR, t)
	p.volume_db = lerpf(HEARTBEAT_VOLUME_FAR_DB, HEARTBEAT_VOLUME_NEAR_DB, t)
