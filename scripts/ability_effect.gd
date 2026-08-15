extends MeshInstance3D
## One-shot expanding, fading "wave" used to visualise a character's special
## ability — most visibly Phoboman's rolling stink wave, but also the little
## flashes for Windman's gust and Primm's phase blink.
##
## It builds its OWN mesh + material, grows from a point out to a target radius
## while fading to transparent, then frees itself. Callers just spawn it and
## forget it (no leak, no manual cleanup):
##
##     var fx := MeshInstance3D.new()
##     fx.set_script(preload("res://scripts/ability_effect.gd"))
##     parent.add_child(fx)
##     fx.global_position = pos
##     fx.setup(Color(0.5, 0.85, 0.2, 0.5), 9.0, 0.9)   # green, 9 m, 0.9 s
##
## EDUCATIONAL NOTE: this mirrors how the rest of the project animates without an
## AnimationPlayer — a value (here scale + alpha) driven by a time accumulator in
## _process — so it fits the codebase's "drive it procedurally" style.

## Seconds elapsed since this wave started expanding (after any start delay).
var _age: float = 0.0
## Optional delay before the wave starts, so a burst of waves can be staggered.
var _delay: float = 0.0
## Total time from first expansion to self-free.
var _lifetime: float = 0.8
## World-space radius the wave grows out to.
var _max_radius: float = 6.0
## Peak opacity, taken from the requested colour's alpha; fades to 0 over life.
var _base_alpha: float = 0.5
## Our own material, so we can fade albedo + emission each frame.
var _material: StandardMaterial3D = null

## The one unit sphere every wave ever drawn shares (see setup()).
static var _shared_sphere_mesh: SphereMesh = null


static func _get_shared_sphere_mesh() -> SphereMesh:
	if _shared_sphere_mesh == null:
		_shared_sphere_mesh = SphereMesh.new()
		_shared_sphere_mesh.radius = 1.0
		_shared_sphere_mesh.height = 2.0
		_shared_sphere_mesh.radial_segments = 16
		_shared_sphere_mesh.rings = 8
	return _shared_sphere_mesh


func setup(color: Color, max_radius: float, lifetime: float, delay: float = 0.0) -> void:
	"""
	Configure and build the wave. Safe to call right after add_child(): everything
	is created here (not in _ready), so the node is fully formed immediately.

	@param color: Tint of the wave; its alpha is the peak opacity.
	@param max_radius: World radius (metres) the wave expands to.
	@param lifetime: Seconds from first expansion until the node frees itself.
	@param delay: Seconds to wait before the wave starts (for staggered bursts).
	"""
	_max_radius = max_radius
	_lifetime = maxf(0.01, lifetime)
	_delay = maxf(0.0, delay)
	_base_alpha = color.a

	# A unit-radius sphere, so scaling by r gives a wave of radius r directly.
	# SHARED, not per-wave: only `scale` ever animates the geometry, and the coin
	# pickup sparkle spawns one of these on every collected coin (~2/s along the
	# road) — a fresh SphereMesh each time is a fresh GPU buffer each time, which
	# is exactly the churn the web build can least afford. Same shared lazy-getter
	# pattern as endless_terrain._get_shared_unit_box_mesh() and ToonShading's
	# cache. The MATERIAL still has to be per-instance, since alpha fades per wave.
	mesh = _get_shared_sphere_mesh()

	# Unshaded + additive-ish translucent + double-sided, so the shell glows and is
	# visible from inside as it sweeps out past the player.
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.albedo_color = color
	_material.emission_enabled = true
	_material.emission = Color(color.r, color.g, color.b)
	_material.emission_energy_multiplier = 0.6
	material_override = _material

	# Never let an FX bubble cast shadows; it's a transient overlay, not geometry.
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Start small (and hidden until any delay elapses).
	scale = Vector3.ONE * 0.3
	visible = _delay <= 0.0


func _process(delta: float) -> void:
	# Hold (invisible) until the start delay has passed.
	if _delay > 0.0:
		_delay -= delta
		visible = false
		return
	visible = true

	_age += delta
	var t := clampf(_age / _lifetime, 0.0, 1.0)

	# Ease-out expansion: fast at first, slowing as it reaches the max radius.
	var eased := 1.0 - pow(1.0 - t, 2.0)
	var r := lerpf(0.3, _max_radius, eased)
	scale = Vector3.ONE * r

	# Fade both the surface and its glow to nothing as it expands.
	if _material:
		_material.albedo_color.a = _base_alpha * (1.0 - t)
		_material.emission_energy_multiplier = 0.6 * (1.0 - t)

	# Done — clean up after ourselves.
	if t >= 1.0:
		queue_free()
