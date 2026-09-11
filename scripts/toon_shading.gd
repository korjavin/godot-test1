class_name ToonShading
extends RefCounted
## Shared toon+rim material styling, used by BOTH the player characters and the
## crocodiles so the whole cast reads with one cohesive cel-shaded look.
##
## The single static entry point is `ToonShading.apply_to_mesh(mesh)` — it holds
## the exact logic that used to live in player_controller.apply_toon_shading,
## plus one crucial addition: a STATIC cache of styled materials.
##
## The cache is the whole point of this file. ~490 crocodiles share the same
## handful of source GLB materials; without the cache each croc would call
## `duplicate()` on those same sources and end up with ~490 private material
## copies — extra memory AND a batching killer (the renderer can only batch
## meshes that share a material). With the cache, every mesh whose surface uses
## the same source material receives the SAME styled duplicate, so the scene
## gains exactly one new material per distinct source, no matter how many
## bodies are on screen.


## Source material instance id -> its toon-styled duplicate. Static so the
## cache is shared across every caller (player + all crocodiles) for the whole
## session. Materials are Resources kept alive by the meshes referencing them,
## so holding them here never leaks scene nodes.
static var _styled_cache: Dictionary = {}

## Boss tint: multiplied into the styled duplicate's albedo so bosses read
## darker and red-shifted — menacing at a glance, without any new textures.
const BOSS_TINT := Color(0.85, 0.4, 0.4)

## Source material instance id -> its BOSS-styled duplicate (toon + rim + the
## darker/red-shifted tint). A separate cache from `_styled_cache` because the
## boss variant is a DIFFERENT output for the same source: regular crocs must
## keep getting the plain toon duplicate. Same sharing rationale as above —
## every boss mesh using the same source gets the SAME boss material, so any
## number of bosses add exactly one material per distinct source.
static var _boss_styled_cache: Dictionary = {}


static func style(mat: BaseMaterial3D, force_srgb: bool = false) -> void:
	"""
	THE CAST'S TOON RECIPE, and the one place it is written down.

	@param mat: the material to style, in place.
	@param force_srgb: opt in to the Compatibility sRGB correction below. The CAST
		(`apply_to_mesh` / `apply_boss_to_mesh`) passes true; every caller that
		styles a material of its own — the tower's batch material, and above all
		the HQ's dossier PORTRAITS, which are a loose lossless `.png` and already
		decode correctly — leaves it false and is unaffected.

	It was typed out six times — twice here, once in `tower_shell.gd` and three
	times in `tower_interior.gd` — so retuning the rim was six edits and the cast
	and the building were one missed edit away from reading differently. That is
	the whole of bead `godot-test1-ftn.23`; the values are unchanged.

	IT SETS THESE FOUR PROPERTIES AND NOTHING ELSE — plus, on ONE renderer, the
	fifth below. Every caller has its own
	business around the call — an albedo colour or texture, `UNSHADED`,
	`vertex_color_use_as_albedo`, emission, the boss tint — and that stays at the
	call site, because it is what makes each material different. `DIFFUSE_TOON` is
	load-bearing for the tower in particular: `apply_to_mesh` SKIPS a material that
	already carries it, which is how the building's shared materials avoid being
	duplicated per mesh.
	"""
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.rim_enabled = true
	mat.rim = 0.4
	mat.rim_tint = 0.25
	# THE COMPATIBILITY sRGB GAP (bead godot-test1-z3e.14, measured on Godot 4.5).
	# An albedo TEXTURE that arrives EMBEDDED IN A `.glb` comes back about a gamma too
	# bright under `gl_compatibility` — the renderer the web build ships — while
	# Forward+ decodes the same bytes correctly. Measured on Windman's face: 28.0% of
	# it over the clipping line on web against 0.0% on Forward+, and 0.00% on web the
	# moment this flag is set.
	#
	# THE VRAM COMPRESSION WAS THE FIRST SUSPECT AND IS NOT RULED OUT. Turning
	# `import_etc2_astc` off in project.godot and re-importing left the face at
	# 28.04%, the same figure to two decimals — but that reading was taken the way
	# every web number in this bead was, on a DESKTOP binary with
	# `--rendering-method gl_compatibility`, which never selects the ETC2 variant in
	# the first place. So it says "not reproduced on the stand-in", not "not the
	# cause"; settling it needs a real web export. Either way the correction belongs
	# here until someone does that.
	#
	# IT IS GATED THREE WAYS, and each gate has a measurement or a reason behind it:
	#  * on the RENDERER, because setting it on Forward+ too means the texture is
	#    decoded twice — the same face falls to 0.339 mean luma from 0.622, i.e.
	#    dirt. `get_current_rendering_method()` asks the actual question, and the
	#    difference is not academic: measured, a `--headless` run answers
	#    `forward_plus` here but `get_rendering_device() == null` — so the obvious
	#    predicate would fire in every self-check and all of CI, on Forward+.
	#  * on the CALLER, via `force_srgb` — the CAST opts in; the HQ's dossier
	#    PORTRAITS do not. Those reach `style()` directly with a loose `.png` on a
	#    different import path (`compress/mode=0`, no VRAM compression) and they are
	#    UNSHADED art the owner has already accepted; nothing in this bead measured
	#    them, and an unmeasured gamma on somebody else's picture is not a fix.
	#  * on the MATERIAL, by the engine: the flag does nothing without an albedo
	#    texture, which is every predator, every tower surface and every generated
	#    hero part (all vertex colours, checked by walking the `.glb`s). So the only
	#    meshes it reaches are Windman's and Primm's authored heads.
	#
	# IT IS A WORKAROUND, SO IT HAS AN EXPIRY: if a later Godot decodes that texture
	# correctly under Compatibility, this line starts double-decoding and the two
	# faces go dark on the web build with nothing to catch it. Re-take the number
	# (`scripts/clipped_fraction.py`) on an engine upgrade, and delete this line if
	# the engine is ever fixed instead.
	if force_srgb and RenderingServer.get_current_rendering_method() == "gl_compatibility":
		mat.albedo_texture_force_srgb = true


static func apply_to_mesh(mesh: MeshInstance3D) -> void:
	"""
	Add soft toon diffuse + rim light to a mesh's materials, matching the look
	the primitive characters get from their scene files. The source material is
	duplicated (once per DISTINCT source, via the static cache) so we only ADD
	shading and never lose the baked albedo or textures — important for GLB
	models, whose colours live in their imported materials.

	Materials that are already toon (the primitive characters) are skipped.

	@param mesh: The mesh whose surface materials should be cel-shaded
	"""
	for surface in mesh.get_surface_override_material_count():
		var mat := mesh.get_active_material(surface)
		if mat is BaseMaterial3D and mat.diffuse_mode != BaseMaterial3D.DIFFUSE_TOON:
			# Reuse the styled duplicate if this exact source material was
			# styled before (same source -> same result, so sharing is safe).
			var key: int = mat.get_instance_id()
			var styled: BaseMaterial3D = _styled_cache.get(key)
			if styled == null:
				styled = mat.duplicate() as BaseMaterial3D
				# The cast is where the textured hero heads are — see `style`.
				style(styled, true)
				_styled_cache[key] = styled
			mesh.set_surface_override_material(surface, styled)


static func apply_boss_to_mesh(mesh: MeshInstance3D) -> void:
	"""
	Boss variant of apply_to_mesh: same toon+rim treatment, plus the albedo is
	multiplied by BOSS_TINT so bosses read darker and redder than the pack.

	Unlike apply_to_mesh this does NOT skip materials that are already
	DIFFUSE_TOON — a boss's source material may be the plain styled duplicate
	from `_styled_cache` (shared croc GLB materials get styled once, globally),
	and the boss must still get its tinted copy on top. The cache is keyed off
	whatever source material the mesh currently shows, so the answer is always
	the same shared boss duplicate for that source.

	@param mesh: The mesh whose surface materials should get the boss look
	"""
	for surface in mesh.get_surface_override_material_count():
		var mat := mesh.get_active_material(surface)
		if mat is BaseMaterial3D:
			var key: int = mat.get_instance_id()
			var styled: BaseMaterial3D = _boss_styled_cache.get(key)
			if styled == null:
				styled = mat.duplicate() as BaseMaterial3D
				style(styled, true)
				styled.albedo_color = styled.albedo_color * BOSS_TINT
				_boss_styled_cache[key] = styled
			mesh.set_surface_override_material(surface, styled)
