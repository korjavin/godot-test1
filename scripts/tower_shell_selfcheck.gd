extends SceneTree
## Headless self-check: THE TOWER IS BUILT, IT FITS, AND YOU CAN FIND IT.
##
##   godot --headless --path . --script res://scripts/tower_shell_selfcheck.gd
##
## Prints "SELFCHECK OK" and exits 0, or prints what failed and exits 1 — the same
## shape as tower_site_selfcheck.gd (phase 1) and landmark_selfcheck.gd, whose
## budget discipline this file applies to the one authored building in the game.
##
## WHY IT IS ITS OWN FILE and not more checks bolted onto landmark_selfcheck: the
## tower is not a landmark builder. It shares the *discipline* (declare a budget and
## a radius, then measure them) and none of the machinery.
##
## WHAT IT GUARDS (bead godot-test1-3iy.2), and why each is worth a check — every
## one of these fails SILENTLY in play, which is the only reason to write a check:
##
##   1. THE BUDGET AND THE FIT. The shell is authored geometry with no streamer to
##      keep it honest, so nothing but this stops it growing a buttress a week. And
##      it must fit inside the disc phase 1 clears (TOWER_RADIUS) — read from
##      endless_terrain, never restated here, because a copied number is exactly how
##      a building ends up standing in scenery it was promised was not there.
##      Checks 1 and 2.
##   2. IT IS A BUILDING, NOT CHUNK CONTENT: one StaticBody3D, one mesh per box, no
##      MultiMesh, and materials SHARED process-wide rather than duplicated per
##      instance — the ToonShading contract, verified by handing the meshes to
##      ToonShading and asserting it declined to copy anything. Checks 3 and 4.
##   3. THE DOORWAY IS A HOLE. The two jambs, the lintel and the trigger volume are
##      all cut from the same DOOR_* constants; a sign error there gives a wall with
##      a trigger in front of it, which looks entirely correct from every angle
##      except the one where you try to walk in. Check 5, with a negative control
##      that the hole really does have walls on both sides of it.
##   4. THE DOOR FIRES, for a player and for nothing else. Check 6 walks a real
##      CharacterBody3D through the real Area3D under real physics, then walks a
##      crocodile-shaped body through it and asserts nothing happened.
##   5. LAZY, AND ONCE. The shell must not exist while the player is far away (the
##      bead's "no per-frame cost"), must appear when they approach, must attach to
##      the terrain MANAGER rather than a chunk (chunk unloading would otherwise
##      free the building the player is standing in), and must not accumulate a
##      second copy on the next boundary crossing. Check 7.
##   6. A NEW RUN MOVES IT. The site is a function of run_seed and the shell is the
##      one thing in the terrain that survives a chunk wipe, so a restart that
##      forgets it leaves a building standing in the previous world's field.
##      Check 8 — plus three neighbours that all came out of review:
##        8b, the MID-RUN MULTIPLAYER JOIN, where the world is rebuilt around a
##            chunk the player has not been teleported into yet;
##        8c, the FRAME the two bodies are placed in — local, like every chunk,
##            because `set_run_seed()` is reachable on a terrain that is not in the
##            tree at all (three other self-checks build one that way);
##        8d, the COIN ROAD, which phase 1 deliberately did not exclude from the
##            site and which therefore lays gold coins inside the walls on some
##            seeds unless the spawner is told about the building.
##   7. THE HORIZON IMPOSTOR. It is the entire answer to "the tower is 400 m away
##      and the web build draws nothing past 150 m of fog", and every way it breaks
##      is invisible on a desktop editor run: fog re-enabled (erased at range),
##      geometry drifted from the shell (you walk toward one building and arrive at
##      another), still visible after the shell loads (z-fighting), or carrying
##      collision (an invisible wall in the middle of the field). Check 9.
##   8. THE MINIMAP MARK. It is the only marker on the map that is NOT read off a
##      group — it asks the terrain where the tower IS — so the usual has_method()
##      guard makes a rename fail silently, with the map still drawing and the
##      tower simply not on it. Check 10 is the alarm for that, plus the rim clamp,
##      the north-up bearing and the shared zoom scale.
##
## The "RID allocations … were leaked at exit" lines after the verdict are the
## engine reporting this project's deliberate static shared caches. Not a failure —
## same note as tower_site_selfcheck.gd's header.

const TERRAIN_SCRIPT: String = "res://scripts/endless_terrain.gd"
const MINIMAP_SCRIPT: String = "res://scripts/minimap_hud.gd"
const SHELL_SCENE: String = "res://scenes/tower/tower_shell.tscn"

## Seeds for the terrain-driven checks. Two is enough: those checks are about the
## STREAMING RULE, not about a particular world, and phase 1's own self-check is
## where the site is sampled across river fields.
const SEED_A: int = 20260828
const SEED_B: int = 4242

## Seeds for the coin-road check. REGRESSION SEEDS, not a sample: 56 is the one
## codex review found (2026-08-28) whose deterministic road lays a coin inside the
## -Z door jamb. The others are here so the check keeps saying something if the road
## generator is ever retuned and seed 56 stops crossing the building; each prints
## how many candidates it rejected, so a seed that has gone inert is visible rather
## than silently passing. Keep 56.
const ROAD_SEEDS: Array[int] = [56, 20260828, 4242]

var _failures: Array[String] = []


func _initialize() -> void:
	_boot()


func _boot() -> void:
	# ONE FRAME BEFORE ANYTHING, for the reason tower_site_selfcheck.gd gives: a node
	# added to `root` from inside _initialize() is not `is_inside_tree()` until the
	# first frame, so anything reading a global transform measures a detached world.
	await process_frame
	await _run()


func _run() -> void:
	_check_box_budget()
	_check_footprint_fits_the_exclusion_disc()
	_check_node_shape()
	_check_materials_are_shared_and_already_toon()
	_check_doorway_is_a_hole()
	await _check_door_fires_for_the_player_only()
	await _check_shell_is_lazy_and_manager_parented()
	await _check_new_run_resites_the_tower()
	await _check_join_streams_the_tower_at_the_anchor()
	_check_a_detached_terrain_still_sites_the_tower()
	_check_no_road_coin_is_buried_in_the_walls()
	_check_impostor()
	_check_minimap_marks_the_tower()
	_report()


# ============================================================================
# CHECKS
# ============================================================================

func _check_box_budget() -> void:
	"""
	Check 1. The shell is made of no more boxes than it declared, and every box is
	a real box standing on the flat world.

	THE BUDGET IS THE POINT. Each box is a MeshInstance3D on a building that is
	permanently on screen once you are inside its load radius, and the web
	`gl_compatibility` renderer counts draw calls. Nothing else in the project stops
	this table from growing — it is authored geometry, so no streamer, no chunk
	budget and no obstacle list ever objects.
	"""
	var boxes := TowerShell.boxes()
	if boxes.is_empty():
		_fail("TowerShell.boxes() is empty — there is no tower")
		return
	if boxes.size() > TowerShell.BOX_BUDGET:
		_fail("the tower shell is %d boxes, over its declared BOX_BUDGET of %d" % [
			boxes.size(), TowerShell.BOX_BUDGET])
	print("tower shell: %d boxes (budget %d), footprint radius %.2f m" % [
		boxes.size(), TowerShell.BOX_BUDGET, TowerShell.footprint_radius()])

	for box: Dictionary in boxes:
		var label: String = box["name"]
		var size: Vector3 = box["size"]
		if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
			_fail("box %s has a non-positive extent %s" % [label, size])
		var pos: Vector3 = box["pos"]
		# THE FLAT-WORLD INVARIANT (CLAUDE.md): the ground is at y = 0 and everything
		# assumes it. A box whose bottom is below zero is buried, and one floating
		# free is worse — the yard slab in particular has no collision, so a floating
		# building would simply have nothing under its walls.
		if pos.y - size.y * 0.5 < -0.001:
			_fail("box %s reaches y=%.3f, below the flat world's ground plane" % [
				label, pos.y - size.y * 0.5])


func _check_footprint_fits_the_exclusion_disc() -> void:
	"""
	Check 2. The whole shell fits inside the disc phase 1 keeps clear.

	THE BEAD'S LANDMINE, verbatim: "the shell must sit exactly on the footprint bead
	1 excludes (share the constant, do not restate the number)". So TOWER_RADIUS is
	read off a live terrain rather than copied into tower_shell.gd — which means
	this check fails not only when the building grows but also when somebody SHRINKS
	the exclusion disc, and that second failure is the one nobody would otherwise
	see until a boulder turned up in the yard.

	Measured per box corner rather than through footprint_radius() alone, so a
	failure names the offender.
	"""
	var terrain := _make_terrain(SEED_A)
	var limit: float = terrain.TOWER_RADIUS
	for box: Dictionary in TowerShell.boxes():
		var pos: Vector3 = box["pos"]
		var half: Vector3 = box["size"] * 0.5
		var reach := Vector2(absf(pos.x) + half.x, absf(pos.z) + half.z).length()
		if reach > limit:
			_fail("box %s reaches %.2f m from the tower centre, past endless_terrain's TOWER_RADIUS of %.1f m" % [
				box["name"], reach, limit])
	# ...and the helper the rest of the world would read must agree with that sweep.
	var declared := TowerShell.footprint_radius()
	if declared > limit:
		_fail("TowerShell.footprint_radius() is %.2f m, past TOWER_RADIUS %.1f m" % [declared, limit])
	terrain.free()


func _check_node_shape() -> void:
	"""
	Check 3. What the scene actually instantiates: one mesh per box, ONE physics
	body, one door, and no chunk machinery.

	The counts are the assertion. "One StaticBody3D" is the same rule chunks follow
	(one collision body per chunk) and the reason it is checkable at all; "no
	MultiMeshInstance3D" is the negative half of "this is authored geometry, not
	chunk content" — if somebody ever routes the shell through create_box() it lands
	in a chunk's batch and this check is what notices.
	"""
	var shell := _make_shell()
	var boxes := TowerShell.boxes()
	var meshes: Array[MeshInstance3D] = []
	var bodies := 0
	var areas := 0
	var multimeshes := 0
	for child: Node in shell.get_children():
		if child is MultiMeshInstance3D:
			multimeshes += 1
		elif child is MeshInstance3D:
			meshes.append(child)
		elif child is Area3D:
			areas += 1
		elif child is StaticBody3D:
			bodies += 1

	if multimeshes != 0:
		_fail("the tower shell holds %d MultiMeshInstance3D — it is authored geometry, not chunk content" % multimeshes)
	if bodies != 1:
		_fail("the tower shell has %d StaticBody3D, expected exactly one" % bodies)
	if areas != 1:
		_fail("the tower shell has %d Area3D, expected exactly one (the door trigger)" % areas)
	if meshes.size() != boxes.size():
		_fail("the tower shell built %d meshes for %d boxes" % [meshes.size(), boxes.size()])

	# Every box in the table is where it said it would be — the table is the shape,
	# so a builder that quietly ignored a field would still count right.
	for i in mini(meshes.size(), boxes.size()):
		var box: Dictionary = boxes[i]
		if meshes[i].position != box["pos"]:
			_fail("mesh %s stands at %s but its box says %s" % [
				box["name"], meshes[i].position, box["pos"]])
		var mesh := meshes[i].mesh as BoxMesh
		if mesh == null or mesh.size != box["size"]:
			_fail("mesh %s is not a BoxMesh of size %s" % [box["name"], box["size"]])

	# One collision shape per COLLIDABLE box — the yard slab and the beacon are
	# deliberately not solid (a 3 cm lip you have to step over, and a light 24 m up).
	var want_shapes := 0
	for box: Dictionary in boxes:
		if box["collide"]:
			want_shapes += 1
	var body := shell.get_node_or_null("TowerCollision") as StaticBody3D
	if body == null:
		_fail("the tower shell has no TowerCollision body")
	else:
		var shapes := 0
		for child: Node in body.get_children():
			if child is CollisionShape3D:
				shapes += 1
		if shapes != want_shapes:
			_fail("the tower body holds %d collision shapes for %d solid boxes" % [shapes, want_shapes])
	if not shell.is_in_group("tower"):
		_fail("the tower shell did not join the \"tower\" group — nothing can find it")
	shell.free()


func _check_materials_are_shared_and_already_toon() -> void:
	"""
	Check 4. The tower owns a fixed handful of materials, and ToonShading refuses to
	copy them.

	TWO SHELLS, SAME MATERIALS. A material built per instance is invisible in play
	and costs batching (the reason ToonShading._styled_cache exists at all), so the
	check builds a second shell and asserts the objects are IDENTICAL, not merely
	equal — the only form of the assertion a per-instance duplicate cannot pass.

	Then the real thing: hand every mesh to ToonShading.apply_to_mesh() and assert
	it changed nothing. That is the whole "toon-shading-compatible" requirement
	stated as an effect rather than as a property read — a material that lost its
	DIFFUSE_TOON would read back fine everywhere else and silently gain a private
	duplicate here.
	"""
	var a := _make_shell()
	var b := _make_shell()
	var mesh_a := _meshes_of(a)
	var mesh_b := _meshes_of(b)
	var distinct := {}
	for i in mini(mesh_a.size(), mesh_b.size()):
		var mat_a := mesh_a[i].material_override
		var mat_b := mesh_b[i].material_override
		if mat_a == null:
			_fail("mesh %s has no material" % mesh_a[i].name)
			continue
		if mat_a != mat_b:
			_fail("mesh %s got a private material per instance — the static cache is not being used" % mesh_a[i].name)
		distinct[mat_a.get_instance_id()] = true

	# One material per distinct colour in the table, and no more.
	var colors := {}
	for box: Dictionary in TowerShell.boxes():
		colors[box["color"]] = true
	if distinct.size() != colors.size():
		_fail("the shell uses %d materials for %d distinct colours" % [distinct.size(), colors.size()])

	for mesh: MeshInstance3D in mesh_a:
		var before := mesh.material_override
		ToonShading.apply_to_mesh(mesh)
		# apply_to_mesh writes a surface OVERRIDE when it decides to style; either an
		# override appearing or the active material changing means it duplicated.
		if mesh.get_surface_override_material(0) != null:
			_fail("ToonShading duplicated the material of %s — it is not already DIFFUSE_TOON" % mesh.name)
		if mesh.material_override != before:
			_fail("ToonShading replaced the material of %s" % mesh.name)
	a.free()
	b.free()


func _check_doorway_is_a_hole() -> void:
	"""
	Check 5. The door trigger sits in a gap in the wall, and that gap has walls
	either side of it.

	BOTH HALVES MATTER. "No solid box overlaps the trigger" alone is satisfied by a
	trigger floating in an empty field, and "the wall is there" alone is satisfied by
	a solid wall. So the doorway volume is tested clear, and then the SAME volume
	shifted sideways by its own width is tested BLOCKED — which is what makes this a
	measurement of a hole rather than of an absence.
	"""
	var trigger: Dictionary = TowerShell.door_trigger_box()
	# The doorway proper: the trigger's own reach through the wall is deliberately
	# thicker than the wall (so a fast player cannot tunnel), and testing that depth
	# against the side walls would be a false positive. The HOLE is wall-thick.
	var door_pos: Vector3 = trigger["pos"]
	var door_size := Vector3(TowerShell.WALL_THICK, TowerShell.DOOR_HEIGHT,
		2.0 * TowerShell.DOOR_HALF_WIDTH)

	var blockers: Array[String] = _solid_boxes_overlapping(door_pos, door_size)
	if not blockers.is_empty():
		_fail("the doorway is blocked by %s — you cannot walk into the tower" % ", ".join(blockers))

	# NEGATIVE CONTROL: shift the same volume into each jamb. Both must be solid, or
	# the "hole" is just a wall that was never built.
	for side in [-1.0, 1.0]:
		var offset := Vector3(0.0, 0.0, side * (TowerShell.DOOR_HALF_WIDTH
			+ door_size.z * 0.5))
		if _solid_boxes_overlapping(door_pos + offset, door_size).is_empty():
			_fail("nothing solid stands %.1f m to the %s of the doorway — the front wall has no jamb"
				% [offset.z, "-Z" if side < 0.0 else "+Z"])

	# And the lintel: above the doorway must be solid, or the "door" is a gap that
	# runs to the top of the wall and the building has no front wall at all.
	var above := door_pos + Vector3(0.0,
		(TowerShell.WALL_HEIGHT + TowerShell.DOOR_HEIGHT) * 0.5 - door_pos.y, 0.0)
	if _solid_boxes_overlapping(above, Vector3(TowerShell.WALL_THICK,
			TowerShell.WALL_HEIGHT - TowerShell.DOOR_HEIGHT, door_size.z)).is_empty():
		_fail("nothing solid stands above the doorway — the front wall is missing its lintel")


func _check_door_fires_for_the_player_only() -> void:
	"""
	Check 6. Walk a body through the doorway under real physics and assert the
	tower noticed — then walk one that is not the player and assert it did not.

	REAL PHYSICS, NOT A DIRECT CALL to the handler. The whole feature is "walking
	through the doorway IS entering", and every way it fails in play is a way a
	direct call would still pass: a trigger on the wrong collision mask, a shape
	that was never given a size, an Area3D with monitoring off. So this builds a
	CharacterBody3D on the player's layer, drops it in the doorway and waits for the
	broadphase.

	THE NEGATIVE CONTROL IS NOT DECORATION. Crocodiles are CharacterBody3Ds that
	wander, and the tower stands in a field full of them; a trigger that fires for
	anything with a collider would report itself entered before the player ever
	arrived, and phase 3 would open on an empty doorway.
	"""
	var shell := _make_shell()
	var seen: Array = []
	shell.player_entered.connect(func(body: Node3D) -> void: seen.append(body))

	# NOT a player: a crocodile-shaped body in the "crocodile" group.
	var croc := _make_probe_body("crocodile")
	root.add_child(croc)
	croc.global_position = shell.to_global(TowerShell.door_trigger_box()["pos"])
	await _settle_physics()
	if shell.entered or not seen.is_empty():
		_fail("the door trigger fired for a crocodile — anything with a collider counts as entering")
	croc.queue_free()

	var hero := _make_probe_body("player")
	root.add_child(hero)
	# Start OUTSIDE and move in, so this measures an entry and not a spawn overlap.
	var door_world: Vector3 = shell.to_global(TowerShell.door_trigger_box()["pos"])
	hero.global_position = door_world + Vector3(12.0, 0.0, 0.0)
	await _settle_physics()
	if shell.entered:
		_fail("the door trigger fired for a player standing 12 m outside the doorway")
	hero.global_position = door_world
	await _settle_physics()
	if not shell.entered:
		_fail("a player walked into the doorway and the tower did not notice (entered stayed false)")
	if seen.size() != 1 or seen[0] != hero:
		_fail("player_entered fired %d times, expected once with the player" % seen.size())

	hero.queue_free()
	shell.queue_free()
	await process_frame


func _check_shell_is_lazy_and_manager_parented() -> void:
	"""
	Check 7. The tower is not built until the player comes near, is built when they
	do, hangs off the terrain MANAGER, and is only ever built once.

	DRIVEN THROUGH _process(), not by calling _tower_stream() directly, because the
	claim under test is "it costs nothing per frame" — which is a claim about WHERE
	the call is wired, and a direct call would pass with the wiring removed.

	THE LAZINESS IS MEASURED AT BOTH ENDS. A shell that is always built passes "it
	exists when I am near"; a shell that is never built passes "it does not exist
	when I am far". Only the pair is an assertion.
	"""
	var terrain := _make_terrain(SEED_A)
	# render_distance 0 keeps this about the tower: update_chunks still runs on every
	# boundary crossing, it just has one chunk to think about instead of 121.
	terrain.render_distance = 0
	var site: Vector3 = terrain.tower_site()

	var probe := Node3D.new()
	probe.add_to_group("player")
	root.add_child(probe)
	terrain.player = probe

	# FAR: just outside the load radius, measured from the site so the check follows
	# the constant instead of restating a distance.
	probe.global_position = site + Vector3(terrain.TOWER_LOAD_RADIUS + 30.0, 0.0, 0.0)
	terrain._process(0.0)
	if terrain.tower_shell() != null:
		_fail("the tower shell was instanced with the player %.0f m away — the load is not lazy"
			% (terrain.TOWER_LOAD_RADIUS + 30.0))
	if not is_instance_valid(terrain._tower_impostor) or not terrain._tower_impostor.visible:
		_fail("with the shell unbuilt there is no visible horizon impostor — the tower is invisible from range")
	elif not terrain._tower_impostor.global_position.is_equal_approx(site):
		_fail("the horizon impostor stands at %s but the site is %s" % [
			terrain._tower_impostor.global_position, site])

	# NEAR: inside the radius. A different chunk, so _process really does cross a
	# boundary and reach the hook.
	probe.global_position = site + Vector3(terrain.TOWER_LOAD_RADIUS - 30.0, 0.0, 0.0)
	terrain._process(0.0)
	var shell: Node3D = terrain.tower_shell()
	if shell == null:
		_fail("the player came within %.0f m of the site and no tower was built"
			% (terrain.TOWER_LOAD_RADIUS - 30.0))
	else:
		if not shell.global_position.is_equal_approx(site):
			_fail("the tower shell stands at %s but tower_site() says %s" % [
				shell.global_position, site])
		# THE FAUNA PRECEDENT (CLAUDE.md): manager-parented, never chunk-parented, or
		# walking away frees the building.
		if shell.get_parent() != terrain:
			_fail("the tower shell is parented to %s, not to the terrain manager" % shell.get_parent())
		if is_instance_valid(terrain._tower_impostor) and terrain._tower_impostor.visible:
			_fail("the horizon impostor is still visible with the real shell standing in the same place")

	# ...and crossing another boundary must not build a second one.
	probe.global_position = site + Vector3(20.0, 0.0, 0.0)
	terrain._process(0.0)
	var towers := 0
	for child: Node in terrain.get_children():
		if child.is_in_group("tower"):
			towers += 1
	if towers != 1:
		_fail("%d tower shells stand on the site after a second boundary crossing" % towers)

	probe.free()
	terrain.free()
	await process_frame


func _check_new_run_resites_the_tower() -> void:
	"""
	Check 8. A new run moves the site, and the tower goes with it.

	The shell is the ONE thing under the terrain that a chunk wipe does not free (it
	is parented to the manager, which is the point of check 7), so new_run() has to
	free it by hand. Forgetting that leaves the previous world's building standing
	in the new world's field, 400 m from where the map now says the tower is — and
	nothing errors.
	"""
	var terrain := _make_terrain(SEED_A)
	terrain.render_distance = 0
	var probe := Node3D.new()
	probe.add_to_group("player")
	root.add_child(probe)
	terrain.player = probe
	probe.global_position = terrain.tower_site()
	terrain._process(0.0)
	if terrain.tower_shell() == null:
		_fail("could not build a shell to test new_run() against")
		probe.free()
		terrain.free()
		return

	var old_site: Vector3 = terrain.tower_site()
	terrain.new_run(SEED_B)
	await process_frame  # queue_free lands at the end of the frame
	var new_site: Vector3 = terrain.tower_site()
	if new_site == old_site:
		print("NOTE: seeds %d and %d sited the tower identically — new_run's move is untested this run"
			% [SEED_A, SEED_B])
	var live := 0
	for child: Node in terrain.get_children():
		if child.is_in_group("tower"):
			live += 1
	# The player is left standing at the OLD site, which after the re-site is far
	# from the new one — so the correct answer is "no shell, impostor showing".
	if new_site.distance_to(old_site) > terrain.TOWER_LOAD_RADIUS and live != 0:
		_fail("new_run() left %d old-world tower shells standing" % live)
	if not is_instance_valid(terrain._tower_impostor):
		_fail("new_run() lost the horizon impostor")
	elif not terrain._tower_impostor.global_position.is_equal_approx(new_site):
		_fail("after new_run() the impostor is at %s but the site moved to %s" % [
			terrain._tower_impostor.global_position, new_site])
	probe.free()
	terrain.free()
	await process_frame


func _check_join_streams_the_tower_at_the_anchor() -> void:
	"""
	Check 8b. A world rebuilt AROUND the tower's chunk has a tower standing in it —
	even though the player is still somewhere else when the rebuild happens.

	THE MID-RUN MULTIPLAYER JOIN (codex review, 2026-08-28). `new_run(seed, around)`
	rebuilds the world centred on the chunk the joiner is ABOUT to be placed in, and
	the teleport lands a moment later; `last_player_chunk` is pinned to `around`, so
	_process will not cross a boundary and re-stream on its own. Test the stream
	against `player.global_position` there and it measures where the joiner USED to
	be — they arrive at the site to find no building, no collision and no doorway
	until they walk a chunk away and back.

	Driven with the player deliberately parked far from the anchor, because that gap
	between "where the player is" and "where the world is being built" is the entire
	bug: any implementation that reads the player's position instead of `around`
	passes every other check in this file and fails only this one.
	"""
	var terrain := _make_terrain(SEED_A)
	terrain.render_distance = 0
	var probe := Node3D.new()
	probe.add_to_group("player")
	root.add_child(probe)
	terrain.player = probe
	var site: Vector3 = terrain.tower_site()

	# The joiner has not been teleported yet — they are still wherever they were.
	probe.global_position = site + Vector3(4000.0, 0.0, 0.0)
	terrain.new_run(SEED_A, terrain.world_to_chunk(site))
	await process_frame
	var shell: Node3D = terrain.tower_shell()
	if shell == null:
		_fail("new_run() rebuilt the world around the tower's own chunk and built no tower — a joiner placed there lands in an empty site")
	elif not shell.global_position.is_equal_approx(terrain.tower_site()):
		_fail("the join-time tower stands at %s, not at the site %s" % [
			shell.global_position, terrain.tower_site()])
	probe.free()
	terrain.free()
	await process_frame


func _check_a_detached_terrain_still_sites_the_tower() -> void:
	"""
	Check 8c. A terrain built OUTSIDE the scene tree can still take a seed.

	NOT A HYPOTHETICAL. `mp_selfcheck`, `prop_selfcheck` and `enemy_spawn_selfcheck`
	all construct a terrain and call `set_run_seed()` on it without ever adding it to
	the tree — that is their whole idiom, because those checks want the pure
	functions and not the streaming. `set_run_seed()` resets the tower, and writing
	`global_position` on a detached node is REJECTED by the engine: it logs
	`Condition "!is_inside_tree()" is true`, leaves the impostor at the origin, and
	the three unrelated checks fill their output with errors while still passing
	(codex review, 2026-08-28).

	TWO LEGS, because the first one alone has no teeth: a detached global write is
	degraded by the engine to "parent transform = identity", so it lands on the same
	number the local write does and only the error log differs. The second leg is
	what distinguishes them — a terrain under a MOVED parent, where the two answers
	part company — and it also pins the frame the whole file already works in:
	`create_chunk` parks a chunk with `position = chunk_to_world(...)`, i.e. the
	terrain node IS world space to everything under it. The tower obeys that same
	contract, so its LOCAL position must be the site whatever the parent does.
	"""
	# Leg 1: never in the tree at all. Catches the placement being dropped outright.
	var loose := Node3D.new()
	loose.set_script(load(TERRAIN_SCRIPT))
	loose.set_run_seed(SEED_A)
	var site: Vector3 = loose.tower_site()
	var impostor: Node3D = loose._tower_impostor
	if impostor == null:
		_fail("a detached terrain built no horizon impostor")
	elif not impostor.position.is_equal_approx(site):
		_fail("a detached terrain left the impostor at %s instead of the site %s" % [
			impostor.position, site])
	loose.free()

	# Leg 2: in the tree, under a parent that is nowhere near the origin.
	var moved := Node3D.new()
	moved.position = Vector3(1000.0, 7.0, -250.0)
	root.add_child(moved)
	var terrain := Node3D.new()
	terrain.set_script(load(TERRAIN_SCRIPT))
	moved.add_child(terrain)
	terrain.set_run_seed(SEED_A)
	var chunk_frame: Vector3 = terrain.chunk_to_world(Vector2i(3, -2))
	var placed: Node3D = terrain._tower_impostor
	if placed == null or not placed.position.is_equal_approx(terrain.tower_site()):
		_fail("under a moved parent the impostor's local position is %s, not the site %s — it was placed in world space while every chunk is placed in the terrain's own frame (chunk (3,-2) goes to local %s)" % [
			placed.position if placed != null else Vector3.ZERO,
			terrain.tower_site(), chunk_frame])

	# ...and the SHELL is placed in that same frame. Streamed directly rather than
	# through _process, because the point here is the frame the node lands in and
	# not the trigger that built it (check 7 owns the trigger).
	terrain._tower_stream(terrain.tower_site())
	var shell: Node3D = terrain.tower_shell()
	if shell == null:
		_fail("streaming at the site built no shell")
	elif not shell.position.is_equal_approx(terrain.tower_site()):
		_fail("under a moved parent the shell's local position is %s, not the site %s — it was placed in world space while every chunk is placed in the terrain's own frame" % [
			shell.position, terrain.tower_site()])
	moved.free()


func _check_no_road_coin_is_buried_in_the_walls() -> void:
	"""
	Check 8d. Generate the chunks the tower stands in and assert no coin came out
	inside its stonework.

	THE COIN ROAD IS NOT EXCLUDED FROM THE SITE, on purpose (phase 1's ruling: a hole
	in the coin trail breaks "follow the coins", and what the road does at the tower
	door is this phase's problem). It therefore runs THROUGH the building on the
	seeds where it passes that way, and the coins it lays were placed by a spawner
	that has never heard of the tower — `_settle_coin_y` reads the chunk's
	`obstacles` list and authored geometry is in no such list. The result is a
	visible gold coin sitting inside a wall, on a specific set of seeds, with nothing
	anywhere logging a word.

	END TO END: real chunks, real spawner, real coin nodes, measured against the
	shell's own box table. And with a NEGATIVE CONTROL that this seed is actually a
	test — a seed whose road misses the tower passes this trivially, so the check
	also counts the candidates the filter had to reject and says so.
	"""
	for seed_value: int in ROAD_SEEDS:
		var terrain := _make_terrain(seed_value)
		var site: Vector3 = terrain.tower_site()
		var home: Vector2i = terrain.world_to_chunk(site)
		# The disc is 60 m across and a chunk is 50, so 3x3 covers it whole.
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				terrain.create_chunk(home + Vector2i(dx, dz))

		var buried: Array[String] = []
		var coins := 0
		for chunk: Node in terrain.active_chunks.values():
			for node: Node in chunk.get_children():
				# BY GROUP, never by name. Godot renames a second node sharing a
				# name to "@Coin@7", so a `begins_with("Coin")` scan silently sees
				# ONE coin per chunk and the check passes its own mutant (measured,
				# 2026-08-28). coin.tscn declares groups=["coin"] in the scene file,
				# so membership is true from the moment it is instantiated.
				if not node.is_in_group("coin"):
					continue
				coins += 1
				var at: Vector3 = (node as Node3D).global_position
				var inside := _tower_box_at(at - site)
				if inside != "":
					buried.append("%s at %s" % [inside, at - site])
		if not buried.is_empty():
			_fail("seed %d: %d road coins are inside the tower's walls (%s)" % [
				seed_value, buried.size(), ", ".join(buried)])

		# The control: how many coins the road WOULD have laid in the stone. Zero
		# means this seed's road misses the building and proves nothing — which is
		# information, not a failure, so it is printed rather than asserted.
		var rejected := _road_coins_in_the_stone(terrain, site)
		print("seed %d: %d coins near the tower, %d road candidates rejected by the walls" % [
			seed_value, coins, rejected])
		terrain.free()


func _road_coins_in_the_stone(terrain: Node3D, site: Vector3) -> int:
	## How many of the road's OWN candidates land inside a solid tower box, asked of
	## the road directly rather than of the spawned result — the negative control for
	## the check above (see there).
	terrain._road_extend_to_x(site.x - 60.0, site.x + 60.0)
	var hits := 0
	for k in range(terrain.road_k_min, terrain.road_k_max + 1):
		for entry: Variant in terrain._road_coins_at(k):
			var pos: Vector3 = (entry as Dictionary)["pos"]
			if _tower_box_at(pos - site) != "":
				hits += 1
	return hits


func _tower_box_at(local: Vector3) -> String:
	## Which SOLID box of the shell contains this tower-local point, or "" for none.
	## Deliberately a bare point test with no clearance: the terrain's own filter
	## adds COIN_TOWER_CLEARANCE, so this measures the thing that actually matters
	## (is the coin in the stone) instead of re-stating the filter's own margin.
	for box: Dictionary in TowerShell.boxes():
		if not box["collide"]:
			continue
		var pos: Vector3 = box["pos"]
		var half: Vector3 = box["size"] * 0.5
		if absf(local.x - pos.x) < half.x and absf(local.y - pos.y) < half.y \
				and absf(local.z - pos.z) < half.z:
			return box["name"]
	return ""


func _check_impostor() -> void:
	"""
	Check 9. The horizon silhouette is the same building, is exempt from the fog,
	and is only a picture.

	FOG EXEMPTION IS THE WHOLE FEATURE. The web build fogs at density 0.005 and
	draws nothing past 150 m; the tower is 400 m out. A material that lost
	`disable_fog` produces an impostor that is present, correct, positioned right,
	and completely invisible in the build that needs it — and every desktop run
	looks fine.

	SILHOUETTE PARITY is the second half: the impostor exists so the player walks
	toward it, and arriving at a different shape than the one they steered by is the
	failure the shared box table exists to prevent.
	"""
	var impostor := TowerShell.build_impostor()
	var boxes := TowerShell.boxes()
	var meshes := _meshes_of(impostor)
	if meshes.size() != boxes.size():
		_fail("the impostor is %d boxes and the shell is %d — the silhouettes differ" % [
			meshes.size(), boxes.size()])
	for i in mini(meshes.size(), boxes.size()):
		var box: Dictionary = boxes[i]
		if meshes[i].position != box["pos"]:
			_fail("impostor box %d stands at %s, the shell's at %s" % [
				i, meshes[i].position, box["pos"]])
		var mat := meshes[i].material_override as StandardMaterial3D
		if mat == null:
			_fail("impostor box %d has no material" % i)
			continue
		if not mat.disable_fog:
			_fail("impostor box %d is fogged — at 400 m under the web build's fog it draws nothing" % i)
		if mat.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
			_fail("impostor box %d is lit, not a flat silhouette" % i)

	# A picture and nothing else: no collision anywhere under it, or the field 400 m
	# out grows an invisible wall.
	if _has_collision(impostor):
		_fail("the horizon impostor carries a collision body — it is a picture, not a building")
	impostor.free()


func _check_minimap_marks_the_tower() -> void:
	"""
	Check 10. The map draws the tower, in the right direction, clamped to the rim
	when it is off the disc, and at the shared zoom's scale.

	THE ALARM FOR A SILENT RENAME. This is the only minimap layer that reaches
	across to the terrain for a VALUE rather than scanning a group, through the
	project's standard has_method() guard — so `tower_site()` being renamed leaves
	the map drawing happily with no tower on it and nothing logged anywhere.

	THE BEARING IS CHECKED, not just the presence. The map is north-up (+X right,
	+Z down) and a sign error mirrors it, which looks entirely plausible and sends
	the player the wrong way for 400 m.

	THE ZOOM ASSERTION IS AN EFFECT MEASUREMENT, in minimap_selfcheck's style: the
	same on-disc tower must land at a different pixel radius after a zoom step. A
	layer that hardcoded 60 m instead of deriving from `_map_scale()` passes every
	other assertion here and fails only this one.
	"""
	var map: Control = _make_minimap()
	var probe := Node3D.new()
	root.add_child(probe)
	var stub := StubTerrain.new()
	root.add_child(stub)

	# NEGATIVE CONTROL FIRST: a terrain that does not answer tower_site() gets no
	# mark — which is also what the map does in a scene with no terrain at all.
	map._player = probe
	map._terrain = Node.new()
	map._tick()
	if map._tower_count != 0:
		_fail("the map drew a tower mark from a terrain that has no tower_site()")
	map._terrain.free()

	# FAR: the tower well off the disc, due -X (the ruling's direction).
	stub.site = Vector3(-400.0, 0.0, 0.0)
	probe.global_position = Vector3.ZERO
	map._terrain = stub
	map._tick()
	if map._tower_count != 1:
		_fail("the map drew no tower mark with a terrain that answers tower_site()")
	else:
		var center := _tower_mark_center(map)
		var from_middle: Vector2 = center - map.MAP_CENTER
		if from_middle.x >= 0.0:
			_fail("the tower is at x=-400 and its mark is to the RIGHT of centre — the map is mirrored")
		if absf(from_middle.y) > 0.001:
			_fail("the tower is due -X and its mark is off the horizontal axis by %.2f px" % from_middle.y)
		var want: float = map.MAP_RADIUS - map.TOWER_MARK_REACH
		if absf(from_middle.length() - want) > 0.01:
			_fail("the off-disc tower mark sits %.2f px from centre, not clamped to the rim inset %.2f px" % [
				from_middle.length(), want])
		if map._tower_colors[0].a >= map.COLOR_TOWER.a:
			_fail("the rim-clamped tower mark was not dimmed — off-map reads as certain as on-map")

	# NEAR: on the disc, at full alpha, and following the shared zoom scale.
	stub.site = probe.global_position + Vector3(-20.0, 0.0, 0.0)
	map._zoom_index = 2
	map._tick()
	var near_at: float = (_tower_mark_center(map) - map.MAP_CENTER).length()
	if map._tower_colors[0].a != map.COLOR_TOWER.a:
		_fail("an on-disc tower mark was dimmed as though it were off the map")
	if absf(near_at - (map.MAP_RADIUS - map.TOWER_MARK_REACH)) < 0.01:
		_fail("a tower 20 m away is still pinned to the rim — it is never drawn on the disc")
	map._zoom_index = 4
	map._tick()
	var zoomed_at: float = (_tower_mark_center(map) - map.MAP_CENTER).length()
	if absf(zoomed_at - near_at) < 0.5:
		_fail("zooming out moved the tower mark by %.2f px — the layer is not on the shared _map_scale()" % absf(zoomed_at - near_at))

	probe.free()
	stub.free()
	map.free()


# ============================================================================
# HELPERS
# ============================================================================

## A stand-in world for the minimap check, answering the three methods the map
## reaches for. `_tick()` re-fetches its terrain only when the cached one is null or
## freed, so assigning this over `map._terrain` redirects the layer — the same trick
## minimap_selfcheck.gd's own StubTerrain uses.
class StubTerrain extends Node:
	var site: Vector3 = Vector3(-400.0, 0.0, 0.0)

	func tower_site() -> Vector3:
		return site

	func biome_at(_x: float, _z: float) -> int:
		return 0

	func is_river_at(_pos: Vector3) -> bool:
		return false


func _make_terrain(seed_value: int) -> Node3D:
	## A REAL terrain node in the tree, the tower_site_selfcheck recipe. Without a
	## node in group "player" it streams nothing on its own, so every check below
	## drives it explicitly.
	var terrain := Node3D.new()
	terrain.set_script(load(TERRAIN_SCRIPT))
	root.add_child(terrain)
	terrain.set_run_seed(seed_value)
	return terrain


func _make_shell() -> Node3D:
	## An instanced shell, IN THE TREE — `_ready()` is what builds the geometry, and
	## `instantiate()` alone does not run it. Callers free what they take.
	var shell := load(SHELL_SCENE).instantiate() as Node3D
	root.add_child(shell)
	return shell


func _make_minimap() -> Control:
	var map := Control.new()
	map.set_script(load(MINIMAP_SCRIPT))
	root.add_child(map)
	return map


func _make_probe_body(group: String) -> CharacterBody3D:
	## A minimal physics body on the default layer (which is where the player is —
	## see player.tscn), carrying one box so the door's broadphase has something to
	## find. The group is what decides whether the tower should react.
	var body := CharacterBody3D.new()
	body.add_to_group(group)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 1.8, 0.8)
	shape.shape = box
	body.add_child(shape)
	return body


func _settle_physics() -> void:
	## Wait long enough for the area broadphase to have SEEN a body that was placed
	## by writing its transform.
	##
	## MEASURED, NOT GUESSED, and the reason this helper exists at all: a body added
	## to the tree and positioned in the same frame is reported by the area on the
	## THIRD physics frame, not the second — the first is spent registering it. Two
	## frames therefore reads as "the door did not fire", which is a check that
	## passes its own negative control and every mutant of the thing it guards.
	## (Caught exactly that way: a mutant with the "player" group guard deleted
	## survived a two-frame wait.)
	for _i in 4:
		await physics_frame


func _meshes_of(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			out.append(child)
	return out


func _has_collision(node: Node) -> bool:
	if node is CollisionObject3D:
		return true
	for child: Node in node.get_children():
		if _has_collision(child):
			return true
	return false


func _solid_boxes_overlapping(center: Vector3, size: Vector3) -> Array[String]:
	## Which COLLIDABLE boxes of the shell intersect this volume, by name.
	## Axis-aligned throughout — the shell is built from axis-aligned boxes with no
	## rotation anywhere, which is exactly why a three-axis interval test is the
	## whole of the geometry here. A tolerance keeps two boxes that merely touch
	## (the jamb and the doorway share a face by construction) from reading as an
	## overlap.
	const TOUCH: float = 0.001
	var out: Array[String] = []
	for box: Dictionary in TowerShell.boxes():
		if not box["collide"]:
			continue
		var pos: Vector3 = box["pos"]
		var half: Vector3 = box["size"] * 0.5
		var mine: Vector3 = size * 0.5
		if absf(pos.x - center.x) >= half.x + mine.x - TOUCH:
			continue
		if absf(pos.y - center.y) >= half.y + mine.y - TOUCH:
			continue
		if absf(pos.z - center.z) >= half.z + mine.z - TOUCH:
			continue
		out.append(box["name"])
	return out


func _tower_mark_center(map: Control) -> Vector2:
	## The cross's centre, recovered from the two segments the map left in its
	## buffer — read back the way the renderer sees it, never off a private field.
	var a: Vector2 = map._tower_points[0]
	var b: Vector2 = map._tower_points[1]
	return (a + b) * 0.5


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		print("SELFCHECK OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	quit(1)
