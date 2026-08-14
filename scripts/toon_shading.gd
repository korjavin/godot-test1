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
				styled.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
				styled.rim_enabled = true
				styled.rim = 0.4
				styled.rim_tint = 0.25
				_styled_cache[key] = styled
			mesh.set_surface_override_material(surface, styled)
