extends MeshInstance3D
class_name BossProjectile
## ============================================================================
## BOSS PROJECTILE — the game's one ranged-attack capability
## ============================================================================
##
## Until this file landed there was NO projectile anywhere in CrimeKickers and no
## enemy ranged attack of any kind: every predator in the game hurts you by
## touching you. This is the shared capability that changes that, built as a
## CAPABILITY rather than as one boss's special case — it ships with two styles
## at once (see STYLES) precisely so it cannot quietly become titan-shaped.
##
## SHAPE PRECEDENT: `ability_effect.gd`. A self-building, self-freeing node that
## constructs its own mesh and material in code — no .tscn, no asset files
## (repo rule), spawn it and forget it.
##
##     BossProjectile.fire(muzzle_pos, aim_pos, chunk, params, self)
##
## ----------------------------------------------------------------------------
## WHAT THIS FILE OWNS, AND WHAT IT DELIBERATELY DOES NOT
## ----------------------------------------------------------------------------
## OWNS: flight, visuals, lethality, lifetime, and the per-shooter live cap.
##
## DOES NOT OWN: firing LOGIC. When to fire, at whom, and how often is the
## firing predator's business and lives in its behaviour arm in
## `piglet_crocodile_ai.gd` — for a ranged boss that arm is exactly one call to
## `fire()`. Pulling a cooldown in here would make every ranged boss share one,
## which is the opposite of what the SPECIES table is for.
##
## ----------------------------------------------------------------------------
## THE PARAMS DICT IS THE WHOLE EXTENSION SEAM
## ----------------------------------------------------------------------------
## `fire()` takes a plain dictionary, and that dictionary is meant to live in the
## firing predator's SPECIES row under the key `"ranged"` (plain-dict convention,
## the same shape as the rest of that table and as `Progression.SKILL_TREES`).
## So a NEW ranged boss is ROW DATA plus one call — zero edits to this file. The
## two entries in STYLES below are the launch consumers' params, kept here rather
## than in a row because their bosses do not exist yet; a row may either carry a
## copy or hand `STYLES["..."]` straight through.
##
## Required keys (all of them; `_param` complains loudly about a missing one rather
## than flying with a silent zero):
##   style          String  — material-cache key AND the sound_manager cue name
##   trajectory     String  — "straight" or "lob"; anything else flies straight
##   speed          float   — HORIZONTAL m/s in both trajectories (see below)
##   gravity        float   — arcade fall for "lob" (ignored by "straight")
##   hit_radius     float   — lethal distance to the player's origin, metres
##   min_fire_range float   — the closest the AI arm may fire from; also the
##                            worst case the fairness contract is measured at
##   max_range      float   — self-free once this far from the muzzle
##   lifetime       float   — self-free after this many seconds, no matter what
##   max_live       int     — hard cap of live projectiles PER SHOOTER
##   color          Color   — albedo + emission of the shared per-style material
##   mesh_scale     Vector3 — scale applied to the one shared unit sphere
##
## `speed` means the same thing in both trajectories on purpose: it is the
## HORIZONTAL component. A lob's vertical launch velocity is not a tunable, it is
## SOLVED so the arc passes through the aim point (see `_launch_velocity`) — so a
## style has exactly one speed number and the fairness inequalities below read
## the same way for both.
##
## ----------------------------------------------------------------------------
## AIM IS FROZEN AT FIRE TIME. NO HOMING, NO MID-FLIGHT RETARGET.
## ----------------------------------------------------------------------------
## Both trajectories aim at where the target WAS when the trigger pulled, and
## never look at it again. That is not a simplification to be "fixed" later: a
## homing projectile cannot be dodged by moving, and dodging is the entire
## counterplay — these bosses are unkillable and one-shot lethal. See the
## fairness contract; homing would make every inequality in it meaningless.
##
## ----------------------------------------------------------------------------
## THE FAIRNESS CONTRACT (measured by scripts/projectile_selfcheck.gd)
## ----------------------------------------------------------------------------
## Two inequalities, asserted for EVERY style this file declares and for every
## `"ranged"` params dict found in a SPECIES row, so adding a ranged boss extends
## the check instead of needing an edit to it:
##
##   1. DODGEABLE BY WALKING. Fired from `min_fire_range` (the shortest flight
##      it can ever have), the projectile must be in the air long enough that a
##      player merely WALKING (player_controller.WALK_SPEED, 5.0) sideways from
##      the muzzle flash clears `hit_radius` with DODGE_MARGIN (3x) to spare:
##
##          min_fire_range / speed * WALK_SPEED >= 3 * hit_radius
##
##      Walking, not running: running is already the escape hatch from every
##      predator in the game, and a ranged attack you must sprint to survive
##      would be the first thing here that punishes exploring on foot.
##
##   2. CANNOT RUN YOU DOWN FROM BEHIND. Horizontal speed stays under
##      player_controller.RUN_SPEED (10.0) — the same reason
##      `MAX_CHASE_SPEED` (8.5) sits below the slowest character's run. A
##      projectile fired at a fleeing player's back must lose the race.
##
## Both are also why these things are SLOW on purpose. "It should be fast, it is
## lightning" is exactly the retune that breaks the feature.
##
## ----------------------------------------------------------------------------
## DETERMINISM STANCE — READ THIS BEFORE "FIXING" IT
## ----------------------------------------------------------------------------
## A projectile is a TRANSIENT COMBAT EFFECT and sits DELIBERATELY OUTSIDE the
## world-determinism contract, the same way weather and fauna do. It uses NO RNG
## at all (its whole flight is a pure function of the fire arguments), takes NO
## draw from any chunk hash stream, appends NO footprint to `obstacles`, and is
## never persisted or regenerated. Nothing about a revisited chunk depends on it.
## Wiring one into the chunk pipeline would consume draws that slide every
## crocodile in the world; there is nothing here to make deterministic.
##
## ----------------------------------------------------------------------------
## MULTIPLAYER: v1 IS LOCAL SIMULATION ONLY
## ----------------------------------------------------------------------------
## No relay verbs, no sync. Lethality resolves against group "player", which by
## definition is the LOCAL player and never a RemoteAvatar — so a projectile
## threatens exactly the machine that simulated it. A remote-driven boss already
## runs its collisions on the quarry's machine, so per-peer local firing composes
## into the existing scheme later with no protocol change.
##
## ----------------------------------------------------------------------------
## WEB-BUILD COST
## ----------------------------------------------------------------------------
## One MeshInstance3D per projectile, ONE shared unit sphere for all of them
## (ability_effect's trick), ONE shared material per STYLE via a static lazy
## getter (the fauna_manager pattern — never a per-instance duplicate, which is
## what would actually move the draw-call count), no lights, no particles, and a
## hard `max_live` cap per shooter enforced inside `fire()`.

## The muzzle flash. Reused, not reinvented — see `_telegraph()`.
const ABILITY_EFFECT := preload("res://scripts/ability_effect.gd")

## The world's ground plane. The flat-world invariant (see CLAUDE.md): ground is
## one shared PlaneMesh at y = 0, so "hit the ground" is a comparison against a
## constant and not a raycast.
const GROUND_Y: float = 0.0

## How much room the walking-dodge inequality must have. 3x means a walking
## player is not merely outside the hit radius when the shot arrives, they are
## three radii clear of it — so the dodge survives frame-rate jitter, a late
## reaction, and a player who strafes at an angle rather than square-on.
const DODGE_MARGIN: float = 3.0

## THE LAUNCH STYLES — the two consumers this capability ships with.
##
## Two, not one, on purpose: a single style proves nothing about whether this is
## a capability or one boss's feature. These are the params the snow Titan and
## the city Clown rows will carry; both sets satisfy the fairness contract above
## with room to spare (measured by projectile_selfcheck).
const STYLES: Dictionary = {
	## THE TITAN'S THUNDER BOLT — "they throw a electric arrow like thunderstorm,
	## likely it slow, so we can move and dodge it".
	##
	## Flat, straight, and slow: 7 m/s is barely above a walk and well under any
	## character's run, so it reads as a bolt you WATCH coming. From its 10 m
	## minimum that is 1.43 s in the air and 7.1 m of walked sidestep against a
	## 0.9 m hit radius — 7.9x the radius, against a required 3x.
	##
	## `max_range` 32 is the boss territory radius: a bolt can cross the whole
	## zone it was fired in and no further, so a boss cannot snipe you out of a
	## territory you have already walked out of. `lifetime` 6.0 is 32 / 7 plus
	## slack, i.e. the range is what actually ends the flight and the lifetime is
	## the backstop for a bolt fired straight up by a bug.
	"thunder_bolt": {
		"style": "thunder_bolt",
		"trajectory": "straight",
		"speed": 7.0,
		"gravity": 0.0,
		"hit_radius": 0.9,
		"min_fire_range": 10.0,
		"max_range": 32.0,
		"lifetime": 6.0,
		"max_live": 2,
		"color": Color(0.65, 0.85, 1.0),
		## Long and thin along the travel axis (the node is oriented to face its
		## velocity for "straight"), which is what makes it read as a bolt rather
		## than a ball of light.
		"mesh_scale": Vector3(0.18, 0.18, 0.95),
	},

	## THE CLOWN'S ICE CREAM — "let's clown thrown ice cream or like that also".
	##
	## The proof this is not a titan-shaped file: same factory, same lethality,
	## same cap, entirely different flight. A lobbed arc reads as a THROW, and its
	## slower 6 m/s horizontal makes it the more dodgeable of the two despite the
	## wider 1.1 m splat radius (6.7 m of sidestep from its 8 m minimum, 6.1x).
	##
	## `gravity` 12.0 is arcade, not physical — per repo convention every script
	## picks its own (the player, the crocodile and this one all differ). It sets
	## the arc height, since the vertical launch speed is solved from it and the
	## range: higher gravity, tighter and snappier lob.
	"ice_cream": {
		"style": "ice_cream",
		"trajectory": "lob",
		"speed": 6.0,
		"gravity": 12.0,
		"hit_radius": 1.1,
		"min_fire_range": 8.0,
		"max_range": 16.0,
		"lifetime": 5.0,
		"max_live": 3,
		"color": Color(1.0, 0.55, 0.75),
		"mesh_scale": Vector3(0.32, 0.32, 0.32),
	},
}

## Live projectile count per shooter, keyed by the shooter's instance id. This is
## what makes `max_live` a cap PER BOSS rather than per chunk or per world: two
## titans on two road stations each get their own two bolts. Entries are erased
## as they fall to zero, so this never grows.
static var _live_per_shooter: Dictionary = {}

## The one unit sphere every projectile of every style shares — same lazy static
## as ability_effect's, for the same reason: a fresh SphereMesh per shot is a
## fresh GPU buffer per shot, which is exactly the churn the web build cannot
## afford. Per-style SHAPE comes from `mesh_scale`, not from a second mesh.
static var _shared_sphere_mesh: SphereMesh = null

## One StandardMaterial3D per STYLE, never per instance (the fauna_manager rule).
## Keyed by the style name.
static var _style_materials: Dictionary = {}

## Frozen at fire time and never recomputed — see the no-homing note above.
var _velocity: Vector3 = Vector3.ZERO
var _gravity: float = 0.0
var _origin: Vector3 = Vector3.ZERO
var _hit_radius: float = 0.0
var _max_range: float = 0.0
var _lifetime: float = 0.0
var _age: float = 0.0

## Who fired us, as an instance id (never a reference — the boss may be freed by a
## chunk unload while we are still in the air, and holding it alive would be a
## leak). Used only to decrement `_live_per_shooter`.
var _shooter_id: int = 0
## Guards the decrement so a node cannot be counted out twice.
var _counted: bool = false


# ============================================================================
# THE SPAWN SURFACE
# ============================================================================

static func fire(from: Vector3, at: Vector3, parent: Node, params: Dictionary,
		shooter: Object = null) -> BossProjectile:
	"""
	Launch one projectile and hand it over to the tree. Returns it, or null if
	the shooter is already at its cap (a refused shot is not an error — the AI
	arm may spam this and simply gets nothing).

	@param from: Muzzle position in world space.
	@param at: Where the target IS RIGHT NOW. Frozen here; never looked at again.
	@param parent: The firing boss's own parent — its CHUNK. Chunk unload then
	               frees any projectile still in the air, for free.
	@param params: The style params dict (see the header, and STYLES).
	@param shooter: The firing node, for the per-shooter `max_live` cap. Passing
	                null skips the cap, which is only ever right in a harness.
	"""
	if parent == null or not is_instance_valid(parent):
		return null

	var shooter_id: int = shooter.get_instance_id() if shooter != null else 0
	if shooter_id != 0:
		var live: int = int(_live_per_shooter.get(shooter_id, 0))
		if live >= int(_param(params, "max_live", 2)):
			return null

	var p := BossProjectile.new()
	p._configure(from, at, params, shooter_id)
	parent.add_child(p)
	# top_level AFTER add_child and BEFORE the first placement: the projectile
	# must not inherit the chunk's (or, if anyone ever reparents it, a boss's)
	# transform — a 6x boss would otherwise fire a 6x bolt travelling 6x too far.
	p.top_level = true
	p.global_position = from
	if p._velocity.length_squared() > 0.0 and bool(params.get("orient", true)):
		p._face_velocity()

	if shooter_id != 0:
		_live_per_shooter[shooter_id] = int(_live_per_shooter.get(shooter_id, 0)) + 1
		p._counted = true

	# The telegraph. A one-shot cue plus a flash at the muzzle is what turns "you
	# died to something offscreen" into "you saw it coming and did not move" —
	# the fairness contract measures the dodge FROM this moment.
	p._telegraph(parent, from, params)
	return p


static func _param(params: Dictionary, key: String, fallback: Variant) -> Variant:
	## Read one params key. A missing key is a MISTAKE in a SPECIES row, not a
	## configuration choice, so it is pushed as an error — but we still return a
	## usable fallback, because a boss that crashes the frame is worse than a
	## boss whose bolt is the wrong speed.
	if not params.has(key):
		push_error("BossProjectile: params missing required key '%s' — check the "
				% key + "firing SPECIES row's \"ranged\" dict")
		return fallback
	return params[key]


# ============================================================================
# FLIGHT
# ============================================================================

func _configure(from: Vector3, at: Vector3, params: Dictionary, shooter_id: int) -> void:
	_origin = from
	_shooter_id = shooter_id
	_hit_radius = float(_param(params, "hit_radius", 1.0))
	_max_range = float(_param(params, "max_range", 30.0))
	_lifetime = maxf(0.01, float(_param(params, "lifetime", 5.0)))
	var trajectory: String = str(_param(params, "trajectory", "straight"))
	var speed: float = maxf(0.01, float(_param(params, "speed", 7.0)))
	_gravity = float(_param(params, "gravity", 0.0)) if trajectory == "lob" else 0.0
	_velocity = _launch_velocity(from, at, speed, _gravity, trajectory)

	mesh = _get_shared_sphere_mesh()
	scale = _param(params, "mesh_scale", Vector3.ONE * 0.3)
	material_override = _get_style_material(
			str(_param(params, "style", "thunder_bolt")),
			_param(params, "color", Color.WHITE))
	# A transient overlay, never geometry — and shadow casting on a dozen of these
	# is a real cost on the web build for something nobody would ever notice.
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _launch_velocity(from: Vector3, at: Vector3, speed: float,
		gravity: float, trajectory: String) -> Vector3:
	"""
	The whole trajectory decision, as a pure function — which is also what lets
	the selfcheck measure it without spawning anything.

	"straight": constant velocity along the fire ray, so the path never leaves
	that ray. "lob": constant HORIZONTAL velocity toward the aim point, plus the
	one vertical speed that makes the arc pass through the aim point at the
	moment it gets there. Everything else (an unknown string, a degenerate
	same-spot shot) degrades to straight — an unrecognised trajectory must fly,
	not error, exactly like an unknown `behavior` string degrading to solo.
	"""
	var delta: Vector3 = at - from
	if trajectory != "lob":
		if delta.length_squared() <= 0.0:
			return Vector3.FORWARD * speed
		return delta.normalized() * speed

	var flat := Vector3(delta.x, 0.0, delta.z)
	var horizontal_distance: float = flat.length()
	if horizontal_distance <= 0.0:
		# Straight up, and back down onto its own muzzle. Degenerate, but finite.
		return Vector3(0.0, speed, 0.0)
	# Time to the aim point is fixed by the horizontal leg alone (no drag, no
	# horizontal acceleration), which is why `speed` can mean "horizontal speed"
	# for both trajectories and the fairness inequality reads identically.
	var t: float = horizontal_distance / speed
	# y(t) = from.y + vy*t - 0.5*g*t^2, solved for y(t) == at.y.
	var vy: float = (delta.y + 0.5 * gravity * t * t) / t
	return flat / t + Vector3(0.0, vy, 0.0)


func _physics_process(delta: float) -> void:
	# Physics, not idle: the thing we collide against is a CharacterBody3D that
	# moves on the physics tick, so sampling anywhere else compares against a
	# stale position.
	_age += delta
	_velocity.y -= _gravity * delta
	global_position += _velocity * delta

	# LETHALITY. Group "player" is the LOCAL player by definition (a RemoteAvatar
	# deliberately joins no group), which is exactly the scope we want — and it is
	# guarded, so a scene with no player at all just flies and expires.
	# hit_by_crocodile() already enforces respawn invulnerability at its very
	# first line; re-checking it here would be a second copy of that rule to
	# drift out of step with.
	var player: Node = get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	if player is Node3D and player.has_method("hit_by_crocodile"):
		if global_position.distance_to((player as Node3D).global_position) <= _hit_radius:
			player.hit_by_crocodile()
			queue_free()
			return

	# Ground contact. The flat world means this is a constant, and the descending
	# guard is what keeps a level shot from freeing itself on frame one.
	if _velocity.y < 0.0 and global_position.y <= GROUND_Y:
		queue_free()
		return

	if _origin.distance_to(global_position) >= _max_range or _age >= _lifetime:
		queue_free()


func _face_velocity() -> void:
	## Point our local -Z along the flight direction, so a stretched `mesh_scale`
	## reads as a bolt travelling nose-first. Only meaningful for "straight",
	## whose direction never changes; a lob is a sphere and does not care.
	var dir: Vector3 = _velocity.normalized()
	var up: Vector3 = Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	# Building the basis directly rather than calling look_at(): look_at() reads
	# the CURRENT global transform, which on a top_level node placed this same
	# frame is exactly the thing we are still in the middle of setting.
	var oriented := Basis.looking_at(dir, up)
	global_transform = Transform3D(oriented.scaled(scale), global_position)


func _telegraph(parent: Node, from: Vector3, params: Dictionary) -> void:
	## Muzzle flash + one-shot cue. Reuses ability_effect.gd rather than growing a
	## second expanding-sphere implementation — it is already the project's
	## self-freeing flash, and the projectile's own colour makes it style-specific
	## for free.
	if not parent.is_inside_tree():
		return
	var flash := MeshInstance3D.new()
	flash.set_script(ABILITY_EFFECT)
	parent.add_child(flash)
	flash.top_level = true
	flash.global_position = from
	var tint: Color = _param(params, "color", Color.WHITE)
	flash.setup(Color(tint.r, tint.g, tint.b, 0.55), _hit_radius * 1.6, 0.25)

	var sm: Node = parent.get_tree().get_first_node_in_group("sound_manager")
	if sm != null and sm.has_method("play_projectile"):
		# play_projectile is gated on the browser-gesture unlock inside the sound
		# manager; nothing here bypasses it.
		sm.play_projectile(str(_param(params, "style", "")))


func _exit_tree() -> void:
	# The one place the cap is given back, and it covers every exit: queue_free
	# on a hit, on the ground, on range, on lifetime — AND the chunk unload that
	# frees us without us ever noticing.
	if not _counted:
		return
	_counted = false
	var live: int = int(_live_per_shooter.get(_shooter_id, 0)) - 1
	if live <= 0:
		_live_per_shooter.erase(_shooter_id)
	else:
		_live_per_shooter[_shooter_id] = live


static func live_count(shooter: Object) -> int:
	## How many of this shooter's projectiles are alive. Exists for the selfcheck
	## (and for an AI arm that wants to skip its cooldown work when capped) —
	## `fire()` enforces the cap itself, so nobody has to consult this first.
	if shooter == null:
		return 0
	return int(_live_per_shooter.get(shooter.get_instance_id(), 0))


# ============================================================================
# SHARED VISUAL RESOURCES (one per style, never one per instance)
# ============================================================================

static func _get_shared_sphere_mesh() -> SphereMesh:
	if _shared_sphere_mesh == null:
		_shared_sphere_mesh = SphereMesh.new()
		_shared_sphere_mesh.radius = 1.0
		_shared_sphere_mesh.height = 2.0
		# Deliberately coarser than ability_effect's 16/8: these are small, fast
		# and numerous, and nobody counts the facets on a thrown ice cream.
		_shared_sphere_mesh.radial_segments = 10
		_shared_sphere_mesh.rings = 5
	return _shared_sphere_mesh


static func _get_style_material(style: String, color: Color) -> StandardMaterial3D:
	## ONE material per style, cached forever. This is the fauna_manager rule and
	## the reason a volley of these does not move the F3 draw-call count: shared
	## material + shared mesh means the renderer can treat them as one family
	## instead of N unique surfaces.
	if _style_materials.has(style):
		return _style_materials[style]
	var mat := StandardMaterial3D.new()
	# Unshaded + emissive so it stays readable against a dark snow sky or a lit
	# city street, and at the distance these are fired from.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.6
	_style_materials[style] = mat
	return mat
