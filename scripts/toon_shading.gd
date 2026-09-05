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

## SCRATCH A/B SWITCH for bead `godot-test1-y1o.22`, and it ships `false` — which
## is byte for byte the cel-banded cast this game has always had.
##
## The epic's question is whether the CAST should keep `DIFFUSE_TOON`'s hard bands
## now that the WORLD is `diffuse_burley` plus `world_block.gdshader`'s top-lit
## gradient, or join it. Flipping this to `true` gives every hero and predator the
## world's diffuse response while KEEPING the rim (0.4 / tint 0.25) that reads as
## the cel outline — the two are independent, and only the first is in question.
## The owner rules from the rendered pair; `style_shots.gd`'s `cast=burley`
## argument is the only thing that writes it.
##
## ponytail: a bool and no enum. There are exactly two candidates and the loser is
## deleted with this var — a mode enum would outlive the decision it exists for.
static var cast_diffuse_burley: bool = false


## The diffuse mode a styled duplicate gets. One reader for both caches so the
## two `apply_*` functions can never disagree about the answer.
##
## ponytail: `apply_to_mesh`'s "already toon, skip it" guard is what makes a
## SECOND apply on the same mesh a no-op, and under Burley that guard no longer
## recognises this file's own output — a double apply would duplicate again. No
## caller does one (each node is styled once, on instance), and the tower checks
## that assert "applying changed nothing" run on materials authored DIFFUSE_TOON
## in the scene, which are skipped under either mode. If Burley wins, the guard
## becomes `!= _cast_diffuse_mode()` in the same commit that deletes the flag.
static func _cast_diffuse_mode() -> int:
	if cast_diffuse_burley:
		return BaseMaterial3D.DIFFUSE_BURLEY
	return BaseMaterial3D.DIFFUSE_TOON


static func set_cast_burley(on: bool) -> void:
	"""
	Set the A/B switch AND drop both caches, which is the whole reason this is a
	function and not a bare assignment.

	`scenes/style_shots.tscn` instances `main.tscn` as an EARLIER SIBLING, so the
	player's model is styled — and its source material cached — before the tool's
	own `_ready()` ever runs. The caches are keyed by source material id alone and
	know nothing about the mode, so a plain assignment would leave every hero
	wearing the duplicate made a frame ago under the old mode, and the A/B pair
	would come out identical for the most important body in the shot.

	Everything the cast is made of is re-styled after this: `_shoot()` re-runs
	`set_active_character()` and `new_run()` respawns the predators.
	"""
	cast_diffuse_burley = on
	_styled_cache.clear()
	_boss_styled_cache.clear()


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
				styled.diffuse_mode = _cast_diffuse_mode()
				styled.rim_enabled = true
				styled.rim = 0.4
				styled.rim_tint = 0.25
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
				styled.diffuse_mode = _cast_diffuse_mode()
				styled.rim_enabled = true
				styled.rim = 0.4
				styled.rim_tint = 0.25
				styled.albedo_color = styled.albedo_color * BOSS_TINT
				_boss_styled_cache[key] = styled
			mesh.set_surface_override_material(surface, styled)
