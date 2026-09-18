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


## GARMENTS ARE NOT CAST — the name a garment material carries, and the ONE thing
## that separates cloth from cast here. Beads godot-test1-td8 (the spike) and
## godot-test1-21m (the rollout).
##
## THIS NARROWS THE y1o.22 RULING — "the cast stays DIFFUSE_TOON" — TO GARMENTS,
## AND ONLY BY THE OWNER'S OWN PICK. Owner, 2026-09-12, on
## `docs/style/z3e/grid_27_cloth_spike.png`: "i choose A+B+D", D being exactly
## this. The spike measured why: under the cast's two-band toon diffuse a garment
## is a flat panel with a hard step across it — the owner's "clothing looks
## painted, not natural" as a number — and swapping the garment alone onto
## DIFFUSE_BURLEY was the only column in that grid that moved the 3 m frame
## (+11% luma sd, the gameplay distance). Skin, face, hair, beret, eyes and
## Windman's wrap all stay on the cast's recipe; so does every predator, every
## boss and every surface of the HQ, none of which can carry this name.
##
## IT IS NOW A LIVE BRANCH AND NOT A GUARDED NO-OP. Before bead 21m a hero
## exported no material at all and this string could not match anything;
## `scripts/build_hero.py`'s `split_cloth_material` now puts every garment polygon
## of all four skinned heroes on a material called exactly this, and everything
## else on `HeroSkin`. The comparison is EXACT EQUALITY, so the two names are one
## contract across the two languages — rename either side and a hero silently
## shades as cast again. Phoboman joined the recipe at bead godot-test1-9k9n.2:
## his skinned mesh exports HeroSkin + HeroCloth like the trio (belly shell,
## pants and boot shafts on cloth, the dragon on skin), and his generated parts —
## which carried no such material and read as cast — are child 9k9n.3's to retire.
const CLOTH_MATERIAL := "HeroCloth"

## Cloth-styled duplicates, keyed like `_styled_cache` and separate from it for
## the same reason `_boss_styled_cache` is: the same source material must be able
## to answer twice, once as cast and once as cloth.
static var _cloth_styled_cache: Dictionary = {}


static func style_cloth(mat: BaseMaterial3D) -> void:
	"""
	WHAT A GARMENT IS SHADED AS when it is not shaded as the cast.

	AND WHY IT READS A LITTLE DARKER THAN THE CAST DID, which bead td8 left open
	as a suspected COLOR_0 colour-space bug and bead 21m closed by measurement.
	It is NOT the vertex colours and NOT the importer: dumped side by side, the
	`HeroCloth`/`HeroSkin` materials Godot builds for a hero that exports two and
	the single default it builds for a hero that exports none are identical in
	every property — white albedo, `FLAG_ALBEDO_FROM_VERTEX_COLOR` on,
	`FLAG_SRGB_VERTEX_COLOR` off, metallic 0, roughness 1, back faces culled, no
	texture — and the `COLOR_0` arrays are the same bytes, seam duplicates aside.
	What changes the picture is the line below and nothing else: a two-band toon
	diffuse CLAMPS most of the lit hemisphere to full brightness, Burley falls off
	with N.L across all of it, and the rim light the cast carries is extra light at
	the silhouette that a garment no longer gets. So the garment is darker exactly
	where a real garment curves away from the key light, which is the whole point
	of the pick.

	IT IS A REAL DROP AND NOT A ROUNDING ONE, and the bead's "within a few percent
	of today" is knowingly NOT met: on a garment-only crop at 3 m the mean luma
	falls 13% on Teibi's polo, 48% on Windman's shorts and 54% on Primm's trousers,
	because the deficit depends on how each garment faces the sun. Whole-hero at
	3 m it is 7-8%. What rises is the variation the owner was actually buying —
	Teibi's 1 m torso goes from luma sd 1.36 to 45.65. `DIFFUSE_LAMBERT_WRAP`, the
	middle ground one enum away, was measured and recovers almost none of the luma
	while giving up half of that variation. Every number, and what the owner would
	turn if he wants the brightness back, is in
	`docs/style/z3e/grid_29_cloth_rollout.md`.

	`style()`'s DIFFUSE_TOON is a lighting threshold, not a depth cue: a 6 mm
	crease either falls entirely inside one band or straddles the step, so a
	fold reads as a hard edge or as nothing, and never as cloth. DIFFUSE_BURLEY is
	a smooth diffuse falloff, which is the whole point here — it is the term that
	can show a shallow curvature at all. Fully rough (cloth has no highlight),
	specular floored, and NO RIM, because the rim light is a cast convention that
	traces a silhouette and a garment inside the silhouette does not want one.

	Godot's toon diffuse has NO BAND COUNT to raise — the bead asked; there is no
	such property on `BaseMaterial3D`, the step is fixed in the shader. The middle
	ground spike td8 nominated, `DIFFUSE_LAMBERT_WRAP`, is still one enum away from
	this line, but bead 21m measured it and it is NOT free: at roughness 1.0 its
	wrap term peaks at 0.5, so it recovers almost none of the luma above while
	giving up half the variation the pick was made for.
	"""
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	mat.roughness = 1.0
	mat.metallic_specular = 0.05
	mat.rim_enabled = false


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
		# A material NAMED `HeroCloth` is a GARMENT and takes the cloth recipe
		# instead of the cast's (see CLOTH_MATERIAL for whose ruling that is).
		# Every skinned hero reaches here with two surfaces since bead 21m — this
		# branch for one of them, the cast branch below for the other — and
		# everything else in the game still has exactly one and still takes the
		# branch it always took.
		if mat is BaseMaterial3D and mat.resource_name == CLOTH_MATERIAL:
			var cloth_key: int = mat.get_instance_id()
			var cloth: BaseMaterial3D = _cloth_styled_cache.get(cloth_key)
			if cloth == null:
				cloth = mat.duplicate() as BaseMaterial3D
				style_cloth(cloth)
				_cloth_styled_cache[cloth_key] = cloth
			mesh.set_surface_override_material(surface, cloth)
		elif mat is BaseMaterial3D and mat.diffuse_mode != BaseMaterial3D.DIFFUSE_TOON:
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
