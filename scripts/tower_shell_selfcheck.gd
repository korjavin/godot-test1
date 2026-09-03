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
##   8. THE ROOF AND THE FACADE (phase 13). The owner's ruling is a building
##      Windman cannot fly into, and the answer is a lid rather than a height: a
##      solid slab rayed at every metre of its span (check 11) and a facade with no
##      horizontal top below it wide enough to land on and re-launch from (check
##      12), whose height budget is INTEGRATED from player_controller's own Air Rush
##      constants and Progression's max ranks. Check 12's docstring records what
##      neither check can promise — a maxed Windman can chain launches upward
##      without bound — and why the seal is therefore the actual guarantee.
##   9. THE ROOF KEEPS THE WEATHER OUT (bug godot-test1-li2). Sealing the shell in
##      phase 13 did not tell the sky about it: a storm drifting over the HQ drew
##      rain through the slab and grounded Windman indoors, because
##      `weather_manager.is_raining_at()` is an XZ circle and knows nothing about
##      roofs. Check 13 asserts the shell's own `sheltered()` over its footprint and
##      outside it, and then that a REAL weather manager parked under a REAL storm
##      answers "dry" indoors and "raining" one step out of the door.
##  10. THE CLOUDS STAY OUT OF THE BUILDING (bug godot-test1-x7k). The owner saw
##      a cloud on level 10: the cloud band started at 45 m, the sealed shell is
##      52 m tall, and the wind moves clouds in XZ only, so anything below the roof
##      drifted straight through the top storeys. Weather restates both numbers it
##      needs (it must run in scenes with no tower at all), so check 14 is the only
##      thing that reads BOTH sides — it fails if the band's floor drops under the
##      roof, if the keep-out disc stops covering the exclusion disc plus a
##      cluster's own reach, or if a real manager ticked over the real site ever
##      puts a puff inside the shell's volume.
##  11. THE MINIMAP MARK. It is the only marker on the map that is NOT read off a
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
const PLAYER_SCRIPT: String = "res://scripts/player_controller.gd"
## The shipped player scene — check 12 reads its collision capsule's radius so the
## facade rule is measured against the body the game actually has. See `_bodies()`.
const PLAYER_SCENE: String = "res://scenes/player.tscn"

## Spacing (metres) of the grid check 11 rays the roof on, and the height it fires
## from. 1 m is finer than any hole a `CharacterBody3D` could pass through and
## coarse enough that the whole 80 m span is ~6k rays in one frame; 60 m is above
## the roof and below nothing.
const ROOF_PROBE_STEP: float = 1.0
const ROOF_PROBE_Y: float = 60.0

## The widest horizontal top a `collide: true` box may expose BELOW the roof.
##
## THE FACADE RULE, and the whole reason the tower stays enterable only by its door:
## a Windman who lands re-launches, so a ledge 22 m up is a staircase with two
## steps. 0.3 m is under the radius of the player's own capsule — nothing to stand
## on. Deny the landing, not the height.
##
## IT IS A CEILING, NOT THE ANSWER, since bead godot-test1-3uh: the sweep is run
## once per body the game can HAVE, and the limit for each is
## `minf(LEDGE_MAX_WIDTH, that body's capsule radius)`. Teibi's small form is
## 0.45 scale — a 0.225 m radius — so the shipped 0.3 was a ledge HE could stand
## on and jump from, on a facade certified against a body twice his width. The
## jump apex is identical at every size (it is a velocity, not a length), so the
## small form buys no height; what it buys is somewhere to put its feet, which is
## exactly what this rule denies. Anything with a smaller capsule must be added to
## `_bodies()` or the facade is certified against a body that no longer exists.
const LEDGE_MAX_WIDTH: float = 0.3

## Metres the roof must clear a fully-skilled Air Rush launched off the tallest
## thing in the world by. Slack for a retune, not a design allowance.
const ROOF_CLEARANCE_MARGIN: float = 5.0

## The weather manager check 13 drives, and the ground radius it gives the one
## storm cloud it plants: big enough to cover the whole 80 m footprint AND the
## point outside the door, so the only thing that can separate those two answers
## is the roof.
const WEATHER_SCRIPT: String = "res://scripts/weather_manager.gd"
const STORM_RADIUS: float = 200.0

## How many weather ticks check 14 drives. At TICK_INTERVAL 0.1 s that is 150 s of
## wind — 240 m at WIND_SPEED, so the whole 250 m field walks across the building
## while the recycler keeps feeding fresh clouds in from the upwind rim.
const CLOUD_DRIFT_TICKS: int = 1500

## Geometry tolerance, in metres.
const EPS: float = 0.001

## Throwaway save file this check points `BestRunStore.config_path` at, so the
## machine's real `user://best_run.cfg` is never opened. See `_boot()`.
const LOCAL_STORE_PATH: String = "user://tower_shell_selfcheck_best_run.cfg"

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


## THE END-OF-CHECK SENTINEL. A GDScript runtime error aborts the FUNCTION it
## lands in and lets the script carry on, so a check that dies halfway simply
## stops asserting and this file prints "SELFCHECK OK". Every check below stamps
## itself at its exit; the report site asks whether every stamp was reached.
## `scripts/selfcheck_sentinel.gd` carries the whole reasoning.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")


func _initialize() -> void:
	_boot()


func _boot() -> void:
	# THE STORE SEAM FIRST, before any shell exists. A shell hydrates its opened
	# set from `BestRunStore` the moment it enters the tree (tower_shell.gd), so
	# without this every shell below would open the developer's real
	# `user://best_run.cfg`. Nothing here asserts gate state, so it would not fail
	# — but a self-check that reads a real profile at all is one edit away from
	# writing to it, which is the trap `progression_selfcheck.gd` documents.
	BestRunStore.config_path = LOCAL_STORE_PATH
	DirAccess.remove_absolute(LOCAL_STORE_PATH)
	# ONE FRAME BEFORE ANYTHING, for the reason tower_site_selfcheck.gd gives: a node
	# added to `root` from inside _initialize() is not `is_inside_tree()` until the
	# first frame, so anything reading a global transform measures a detached world.
	await process_frame
	await _run()


func _run() -> void:
	_check_box_budget()
	_check_footprint_fits_the_exclusion_disc()
	await _check_the_roof_is_sealed()
	_check_roof_is_above_windmans_reach()
	_check_node_shape()
	_check_materials_are_shared_and_already_toon()
	_check_doorway_is_a_hole()
	await _check_door_fires_for_the_player_only()
	await _check_shell_is_lazy_and_manager_parented()
	await _check_a_teammate_at_the_tower_builds_it_for_the_master()
	await _check_new_run_keeps_the_site()
	await _check_join_streams_the_tower_at_the_anchor()
	_check_a_detached_terrain_still_sites_the_tower()
	_check_no_road_coin_is_buried_in_the_walls()
	_check_impostor()
	_check_impostor_hidden_in_budapest()
	_check_minimap_marks_the_tower()
	await _check_the_roof_keeps_the_rain_out()
	_check_clouds_stay_clear_of_the_hq()
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
		Sentinel.done("box_budget")
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
	Sentinel.done("box_budget")


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
	Sentinel.done("footprint_fits_the_exclusion_disc")


func _check_the_roof_is_sealed() -> void:
	"""
	Check 11. THERE IS A LID, and it has no holes in it.

	Fires a downward ray from above the building at every metre of the span inside
	the walls and asserts each one stops at the roof. THROUGH THE REAL PHYSICS
	SERVER, not over the box table, because "sealed" is a claim about
	`CollisionShape3D`s: a roof mesh whose box was appended with `collide: false`,
	or a slab that misses a corner of the footprint, reads as a perfectly good roof
	in `boxes()` and is a hole you fly through in the game.

	WHY THIS IS THE GUARANTEE AND THE HEIGHT IS NOT — see check 12: a Windman can
	be made to reach any altitude at all, so the building is not defended by being
	tall. It is defended by having nowhere to come down.
	"""
	var shell := _make_shell()
	# Shapes only enter the space on the physics frame after they are added.
	await physics_frame
	var space := shell.get_world_3d().direct_space_state
	var inner: float = TowerShell.OUTER_HALF - TowerShell.WALL_THICK
	var roof_bottom: float = TowerShell.WALL_HEIGHT
	var holes := 0
	var worst := Vector2.ZERO
	var x := -inner
	while x <= inner + EPS:
		var z := -inner
		while z <= inner + EPS:
			var query := PhysicsRayQueryParameters3D.create(
				shell.global_position + Vector3(x, ROOF_PROBE_Y, z),
				shell.global_position + Vector3(x, -1.0, z))
			var hit := space.intersect_ray(query)
			# A ray that hits nothing, or first hits something below the roof slab,
			# is a way in from the sky.
			if hit.is_empty() or float(hit["position"].y) < roof_bottom - EPS:
				holes += 1
				worst = Vector2(x, z)
			z += ROOF_PROBE_STEP
		x += ROOF_PROBE_STEP
	if holes > 0:
		_fail("the roof has %d open grid points — e.g. (%.1f, %.1f), where a ray from %.0f m falls straight through" % [
			holes, worst.x, worst.y, ROOF_PROBE_Y])
	else:
		print("roof sealed: every %.0f m grid point inside +/-%.1f m stops at the slab" % [
			ROOF_PROBE_STEP, inner])
	shell.free()
	Sentinel.done("the_roof_is_sealed")


func _check_roof_is_above_windmans_reach() -> void:
	"""
	Check 12. The roof is out of reach of ONE fully-skilled Air Rush launched off
	the tallest ground in the world, and no ledge below it offers a second one.

	THE NUMBERS ARE MEASURED, NEVER RESTATED. The arc is integrated from
	`player_controller`'s own `gravity`, `WINDMAN_LIFT`, `WINDMAN_BOOST_DURATION`
	and `WINDMAN_GRAVITY_FACTOR`, with the three Air Rush skills at the max ranks
	`Progression.SKILL_TREES` declares and the caps `skill_mult()` enforces — so a
	balance pass that buys Windman another ten metres fails HERE, in the one place
	that would otherwise silently stop being true. The summit he launches from is
	`endless_terrain.MOUNTAIN_HEIGHT_MAX`, read off a live terrain the way check 2
	reads TOWER_RADIUS.

	THE CEILING OF THIS CHECK, stated so nobody mistakes it for a proof: the
	cooldown floor (8.0 s x COOLDOWN_MULT_MIN = 4.8 s) is SHORTER than a maxed
	boost (5.2 s), and `try_activate_ability` has no on-floor gate — so a maxed
	Windman can re-launch in mid-air and climb without bound, roughly 25 m a cycle.
	No roof height defeats that, which is exactly why phase 13 ships a SEALED roof
	(check 11) and a facade with nothing to land on (below): the guarantee is that
	there is no way IN, not that there is no way UP. Gating the re-launch is a
	design decision for the epic, not something this file may quietly assume.
	"""
	var peak := _air_rush_peak()
	if peak <= 0.0:
		_fail("could not integrate Air Rush out of player_controller/Progression — check 12 would pass vacuously")
		Sentinel.done("roof_is_above_windmans_reach")
		return
	var terrain := _make_terrain(SEED_A)
	var summit: float = terrain.MOUNTAIN_HEIGHT_MAX
	terrain.free()

	var boxes := TowerShell.boxes()
	var inner: float = TowerShell.OUTER_HALF - TowerShell.WALL_THICK
	var roof := _topmost_solid(boxes)
	if roof.is_empty():
		_fail("the shell has no collide:true box on top — there is no roof")
		Sentinel.done("roof_is_above_windmans_reach")
		return
	var roof_pos: Vector3 = roof["pos"]
	var roof_half: Vector3 = roof["size"] * 0.5
	var roof_top := roof_pos.y + roof_half.y
	var need := peak + summit + ROOF_CLEARANCE_MARGIN
	print("Air Rush peak %.2f m (maxed) + massif %.1f m + %.1f m margin = %.2f m; roof top %.2f m" % [
		peak, summit, ROOF_CLEARANCE_MARGIN, need, roof_top])
	if roof_top <= need:
		_fail("the roof tops out at %.2f m, inside a maxed Air Rush (%.2f m) off a %.1f m massif plus %.1f m of margin" % [
			roof_top, peak, summit, ROOF_CLEARANCE_MARGIN])

	# THE CASTLE RULE (bead godot-test1-rgt), stated where it can be read rather
	# than left to emerge as a confusing failure somewhere else. Everything the
	# silhouette pass added stands ON the slab, and none of it is solid — a
	# solid turret above the roof would silently BECOME "the roof" as far as
	# `_topmost_solid` is concerned, and the real slab would then fail its own
	# coverage test with a message about the wrong box. Body-independent, so it is
	# asked once, above the per-body sweeps.
	for box: Dictionary in boxes:
		if box["name"] == roof["name"] or not box["collide"]:
			continue
		if box["pos"].y + box["size"].y * 0.5 > roof_top + EPS:
			_fail("%s is solid and reaches %.2f m, above the roof at %.2f m — decoration above the seal must be collide:false, or it becomes the roof" % [
				box["name"], box["pos"].y + box["size"].y * 0.5, roof_top])

	# ...and nothing below it is a place to land and go again — asked once per body
	# the game can have, smallest capsule included.
	for body: Dictionary in _bodies():
		_sweep_for_ledges(boxes, roof, inner, body)
	Sentinel.done("roof_is_above_windmans_reach")


func _bodies() -> Array[Dictionary]:
	"""
	Every capsule the player can BE, widest first, as `{name, radius}`.

	Read off the shipped `player.tscn` capsule and `player_controller`'s own resize
	scales rather than written down here, so a retuned capsule — or a third form —
	retunes the facade rule instead of leaving it certified against a body that was
	replaced. Teibi's giant form is deliberately absent: it is strictly wider than
	the normal capsule, so it can stand on nothing the normal one cannot.
	"""
	var packed: PackedScene = load(PLAYER_SCENE)
	var probe: Node = packed.instantiate()
	var shape: CollisionShape3D = probe.get_node_or_null("CollisionShape3D")
	var radius := 0.0
	if shape and shape.shape is CapsuleShape3D:
		radius = (shape.shape as CapsuleShape3D).radius
	probe.free()
	if radius <= 0.0:
		_fail("player.tscn has no CapsuleShape3D — the facade sweep would measure nothing")
		return []
	# EVERY resize scale, and a MISSING one is a failure and not a 1.0 default:
	# defaulting would collapse the small sweep into a second normal sweep and this
	# check would go on printing two green lines while measuring one body. (codex
	# review, 2026-08-30.)
	var consts: Dictionary = load(PLAYER_SCRIPT).get_script_constant_map()
	var smallest := 1.0
	for key: String in ["TEIBI_SCALE_SMALL", "TEIBI_SCALE_BIG"]:
		if not consts.has(key):
			_fail("player_controller has no %s — the smallest body cannot be derived and the sweep would silently measure the normal capsule twice" % key)
			return []
		smallest = minf(smallest, float(consts[key]))
	return [
		{"name": "the normal capsule", "radius": radius},
		{"name": "the smallest Teibi (x%.2f)" % smallest, "radius": radius * smallest},
	]


func _sweep_for_ledges(boxes: Array[Dictionary], roof: Dictionary, inner: float,
		body: Dictionary) -> void:
	"""One body's half of check 12: no `collide: true` box under the roof exposes a
	top this capsule could stand on. See `LEDGE_MAX_WIDTH` for the limit."""
	var roof_pos: Vector3 = roof["pos"]
	var roof_half: Vector3 = roof["size"] * 0.5
	var roof_bottom := roof_pos.y - roof_half.y
	var limit: float = minf(LEDGE_MAX_WIDTH, float(body["radius"]))
	print("no-ledge sweep for %s: nothing wider than %.3f m under the roof" % [
		body["name"], limit])
	for box: Dictionary in boxes:
		if box["name"] == roof["name"] or not box["collide"]:
			continue
		var pos: Vector3 = box["pos"]
		var size: Vector3 = box["size"]
		var half: Vector3 = size * 0.5
		var top := pos.y + half.y
		# "Covered" is the roof standing ON it: its top meets the slab's underside
		# and it is inside the slab's footprint, so there is no top face left.
		var covered := top >= roof_bottom - EPS \
				and absf(pos.x) + half.x <= absf(roof_pos.x) + roof_half.x + EPS \
				and absf(pos.z) + half.z <= absf(roof_pos.z) + roof_half.z + EPS
		# INDOORS IS NOT A FACADE. The rule is about surfaces a flier OUTSIDE the
		# building can land on; anything under the sealed roof is inside a room with
		# no exit, and standing on it gets you nowhere. Since bd godot-test1-dn8 the
		# shell draws nothing solid in here at all (the inner keep's wall tops were
		# the clause's one subject), so it is vacuous against this table — it stays
		# because it is the RULE, and the interior's storeys are still built under
		# the same lid.
		var indoors := absf(pos.x) + half.x <= inner + EPS \
				and absf(pos.z) + half.z <= inner + EPS
		if covered or indoors or minf(size.x, size.z) <= limit:
			continue
		_fail("%s exposes a %.2f x %.2f m top at %.2f m, under the roof — %s stands there (limit %.3f m) and goes again" % [
			box["name"], size.x, size.z, top, body["name"], limit])


func _topmost_solid(boxes: Array[Dictionary]) -> Dictionary:
	"""The solid box with the highest top — the roof, found by geometry and not by
	name, so renaming it cannot make check 12 measure something else."""
	var best: Dictionary = {}
	var best_top := -INF
	for box: Dictionary in boxes:
		if not box["collide"]:
			continue
		var top: float = box["pos"].y + box["size"].y * 0.5
		if top > best_top:
			best_top = top
			best = box
	return best


func _air_rush_peak() -> float:
	"""
	How high ONE Air Rush carries a fully-skilled Windman above his launch point.

	Integrated in closed form off the shipped constants: he rises under the softened
	boost gravity until the boost runs out and — because a maxed glide never reaches
	its own apex before the wings cut (see `Progression.WINDMAN_GRAVITY_MULT_MIN`'s
	arc note) — coasts the rest of the way up under ORDINARY gravity. Missing that
	second leg under-reports the peak, which is the sort of margin this check exists
	to keep honest.

	The probe instance is the trick `tower_interior_selfcheck._jump_apex()` uses:
	`gravity` is a plain var, so one bare, never-readied instance is how you read its
	default without loading a character model.
	"""
	var script: GDScript = load(PLAYER_SCRIPT)
	var probe: Object = script.new()
	var g: float = float(probe.get("gravity"))
	if probe is Node:
		(probe as Node).free()
	var consts := script.get_script_constant_map()

	# Every Air Rush node at the rank the TREE declares, resolved through the getter
	# that owns the balance caps — never a hand-summed bonus.
	var maxed := {}
	for node: Dictionary in Progression.SKILL_TREES.get("windman", []):
		maxed[node["id"]] = int(node["max_ranks"])
	var prog := Progression.new()
	prog.skill_ranks = {"windman": maxed}
	var lift := float(consts.get("WINDMAN_LIFT", 0.0)) * prog.skill_mult("windman", "windman_lift")
	var boost := float(consts.get("WINDMAN_BOOST_DURATION", 0.0)) * prog.skill_mult("windman", "windman_boost")
	var g_boost := g * float(consts.get("WINDMAN_GRAVITY_FACTOR", 1.0)) \
			* prog.skill_mult("windman", "windman_gravity")
	prog.free()

	if g <= 0.0 or g_boost <= 0.0 or lift <= 0.0 or boost <= 0.0:
		return 0.0
	if lift / g_boost <= boost:
		# He tops out while still gliding.
		return lift * lift / (2.0 * g_boost)
	var v_end := lift - g_boost * boost
	return lift * boost - 0.5 * g_boost * boost * boost + v_end * v_end / (2.0 * g)


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
		_check_mesh_fills_its_box(meshes[i], box)

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
	Sentinel.done("node_shape")


func _check_mesh_fills_its_box(instance: MeshInstance3D, box: Dictionary) -> void:
	"""
	One built mesh really is the shape and the size its table entry declared.

	THE AABB IS THE ASSERTION, because since the castle pass (bead godot-test1-rgt)
	the table can name a cone or a welded parapet ring as well as a box, and the ONE
	property every other measurement in this file leans on is that whatever is built
	fits exactly inside `pos ± size/2`. A cone that quietly kept `CylinderMesh`'s
	default 1 m radius would still be a cone, still be positioned right, and would
	make the footprint sweep and the ledge rules measure a building that is not
	there. A plain box is still asserted exactly — a `BoxMesh` of the declared size,
	nothing else — so the loosening applies only to the shapes that need it.
	"""
	var mesh: Mesh = instance.mesh
	if mesh == null:
		_fail("mesh %s was not built at all" % box["name"])
		Sentinel.done("mesh_fills_its_box")
		return
	var kind: String = box.get("mesh", "box")
	if kind == "box":
		var as_box := mesh as BoxMesh
		if as_box == null or as_box.size != box["size"]:
			_fail("mesh %s is not a BoxMesh of size %s" % [box["name"], box["size"]])
		Sentinel.done("mesh_fills_its_box")
		return
	var aabb := mesh.get_aabb()
	var size: Vector3 = box["size"]
	if not aabb.size.is_equal_approx(size):
		_fail("mesh %s is declared %s but its %s geometry measures %s" % [
			box["name"], size, kind, aabb.size])
	if not (aabb.position + aabb.size * 0.5).is_equal_approx(Vector3.ZERO):
		_fail("mesh %s is not centred on its own origin — it sits at %s" % [
			box["name"], aabb.position + aabb.size * 0.5])
	Sentinel.done("mesh_fills_its_box")


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
	Sentinel.done("materials_are_shared_and_already_toon")


func _check_doorway_is_a_hole() -> void:
	"""
	Check 5. The door sits in a gap in the wall, that gap has walls either side of
	it, and the trigger is on that same wall plane.

	BOTH HALVES MATTER. "No solid box overlaps the trigger" alone is satisfied by a
	trigger floating in an empty field, and "the wall is there" alone is satisfied by
	a solid wall. So the doorway volume is tested clear, and then the SAME volume
	shifted sideways by its own width is tested BLOCKED — which is what makes this a
	measurement of a hole rather than of an absence.
	"""
	# ONE RING SINCE bd godot-test1-dn8. Phase 13 walked TWO wall planes here — the
	# 80 m envelope and the 20 m keep inside it — because a hole missing from either
	# was a building you could not enter. The keep is demolished and floors 0 and 1
	# are planned storeys, so there is one front wall again. The loop stays: it is
	# still a table of wall planes, and the day a second one is built it costs a row
	# rather than a rewrite.
	var rings: Array[Dictionary] = [
		{"what": "outer wall", "mid": TowerShell.OUTER_HALF - TowerShell.WALL_THICK * 0.5,
			"top": TowerShell.WALL_HEIGHT},
	]
	# The doorway proper: the trigger's own reach through the wall is deliberately
	# thicker than the wall (so a fast player cannot tunnel), and testing that depth
	# against the side walls would be a false positive. The HOLE is wall-thick.
	var door_size := Vector3(TowerShell.WALL_THICK, TowerShell.DOOR_HEIGHT,
		2.0 * TowerShell.DOOR_HALF_WIDTH)
	for ring: Dictionary in rings:
		var what: String = ring["what"]
		var door_pos := Vector3(float(ring["mid"]), TowerShell.DOOR_HEIGHT * 0.5, 0.0)
		var blockers: Array[String] = _solid_boxes_overlapping(door_pos, door_size)
		if not blockers.is_empty():
			_fail("the %s's doorway is blocked by %s — you cannot walk into the tower" % [
				what, ", ".join(blockers)])

		# NEGATIVE CONTROL: shift the same volume into each jamb. Both must be solid,
		# or the "hole" is just a wall that was never built.
		for side in [-1.0, 1.0]:
			var offset := Vector3(0.0, 0.0, side * (TowerShell.DOOR_HALF_WIDTH
				+ door_size.z * 0.5))
			if _solid_boxes_overlapping(door_pos + offset, door_size).is_empty():
				_fail("nothing solid stands %.1f m to the %s of the %s's doorway — it has no jamb"
					% [offset.z, "-Z" if side < 0.0 else "+Z", what])

		# And the lintel: above the doorway must be solid, or the "door" is a gap that
		# runs to the top of the wall and the ring has no front wall at all.
		var top: float = ring["top"]
		var above := Vector3(door_pos.x, (top + TowerShell.DOOR_HEIGHT) * 0.5, 0.0)
		if _solid_boxes_overlapping(above, Vector3(TowerShell.WALL_THICK,
				top - TowerShell.DOOR_HEIGHT, door_size.z)).is_empty():
			_fail("nothing solid stands above the %s's doorway — it is missing its lintel" % what)

	# The trigger itself is on the front wall's door line and must sit in that hole.
	var trigger: Dictionary = TowerShell.door_trigger_box()
	if not is_equal_approx(float(trigger["pos"].x), float(rings[0]["mid"])):
		_fail("the door trigger is at x = %.2f, not on the outer wall plane (%.2f)" % [
			trigger["pos"].x, rings[0]["mid"]])
	Sentinel.done("doorway_is_a_hole")


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
	Sentinel.done("door_fires_for_the_player_only")


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
		# THE IMPOSTOR IS DELIBERATELY STILL VISIBLE HERE (bead godot-test1-rgt).
		# Hiding it the frame the shell arrives is the hard swap the owner saw as
		# "black, then it pops to white"; the handover is now a material fade over
		# a band that starts INSIDE this radius, so at the load distance both are
		# on screen on purpose and the impostor is the one that is fully opaque.
		# What used to be defended here — no double image, no z-fight — is defended
		# in check 9 instead, on the fade band and the cull that follows it.
		if is_instance_valid(terrain._tower_impostor) and not terrain._tower_impostor.visible:
			_fail("the horizon impostor was switched off when the shell loaded — that hard swap is the pop this bead removed")

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
	Sentinel.done("shell_is_lazy_and_manager_parented")


func _check_a_teammate_at_the_tower_builds_it_for_the_master() -> void:
	"""
	Check 7b. A teammate standing at the tower makes the MASTER build it, even
	though the master is 4 km away.

	NOT A RENDERING QUESTION (codex review, 2026-08-28). `set_focus_points()` pins
	the chunks around every room member because the master SIMULATES what is in
	them, and crocodiles are master-simulated (CLAUDE.md). A master whose own player
	is out of load range would therefore be running a teammate's crocodiles against
	a world with no tower in it — walking them clean through walls that exist on the
	teammate's machine, and broadcasting transforms the teammate's own shell then
	refuses. The building has to exist wherever it is being SIMULATED, not only
	wherever it is being looked at.

	The control is the first half: with the same distant player and NO focus set,
	nothing may be built — otherwise this measures nothing but check 7 again.
	"""
	var terrain := _make_terrain(SEED_A)
	terrain.render_distance = 0
	var probe := Node3D.new()
	probe.add_to_group("player")
	root.add_child(probe)
	terrain.player = probe
	var site: Vector3 = terrain.tower_site()

	# The master is nowhere near the tower, and solo (an empty focus set).
	probe.global_position = site + Vector3(4000.0, 0.0, 0.0)
	terrain._process(0.0)
	if terrain.tower_shell() != null:
		_fail("control failed: a shell was built with the player 4 km out and no focus set")

	# A teammate walks in. This is exactly the presence path — MpManager publishes
	# peer positions and crocodile_lod_manager forwards them here.
	terrain.set_focus_points([site])
	terrain._process(0.0)
	if terrain.tower_shell() == null:
		_fail("a teammate reached the tower and the master built no shell — it would simulate that teammate's crocodiles through the walls")

	probe.free()
	terrain.free()
	await process_frame
	Sentinel.done("a_teammate_at_the_tower_builds_it_for_the_master")


func _check_new_run_keeps_the_site() -> void:
	"""
	Check 8. A new run does NOT move the site — and the shell is still rebuilt.

	INVERTED BY PHASE 12 (owner ruling 2026-08-29: the HQ is planned once and
	forever). What this used to assert — that a new seed re-sites the tower — is now
	the bug: the site is a constant, so a second run must find the building at the
	same address as the first.

	The other half is unchanged and is why the check still exists at all. The shell
	is the ONE thing under the terrain that a chunk wipe does not free (it is
	parented to the manager, which is the point of check 7), so new_run() has to
	free it by hand. Forgetting that leaves the PREVIOUS world's building — with the
	previous world's opened gates and captives on it — standing in the new world.
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
		Sentinel.done("new_run_keeps_the_site")
		return

	var old_site: Vector3 = terrain.tower_site()
	# The IDENTITY of the old building, taken while it is still alive. Comparing the
	# node reference is not enough — new_run() frees it, so `is_instance_valid` goes
	# false and a reference comparison silently stops asserting anything (codex
	# review, 2026-08-29). An instance id is never reused, so it still distinguishes
	# "rebuilt" from "kept" after the free.
	var old_id: int = terrain.tower_shell().get_instance_id()
	terrain.new_run(SEED_B)
	await process_frame  # queue_free lands at the end of the frame
	var new_site: Vector3 = terrain.tower_site()
	if new_site != old_site:
		_fail("a new run moved the tower from %s to %s — the site is hand-planned and fixed" % [
			old_site, new_site])

	# EXACTLY ONE BUILDING, AND IT IS A NEW ONE. The player never left the site (it
	# cannot move any more), so the awaited frame crosses a chunk boundary — the
	# rebuild was anchored on spawn — and streams a fresh shell straight back. What
	# must NOT survive is the old node: it carries the old world's opened gates,
	# captives and guards.
	#
	# Counted over the children rather than off `_tower_shell`, deliberately: a reset
	# that nulls the reference without freeing the node leaves the building in the
	# tree with the accessor answering null. Nodes already queued for deletion are
	# retired and do not count.
	var live: Array[Node] = []
	for child: Node in terrain.get_children():
		if child.is_in_group("tower") and not child.is_queued_for_deletion():
			live.append(child)
	if live.size() != 1:
		_fail("after new_run() the terrain owns %d live tower shells, expected exactly 1" % live.size())
	elif live[0].get_instance_id() == old_id:
		_fail("new_run() kept the previous world's tower shell — its opened gates and captives came along")
	if terrain.tower_shell() == null:
		_fail("new_run() left no tower shell for a player standing on the site")
	if not is_instance_valid(terrain._tower_impostor):
		_fail("new_run() lost the horizon impostor")
	elif not terrain._tower_impostor.global_position.is_equal_approx(new_site):
		_fail("after new_run() the impostor is at %s but the site moved to %s" % [
			terrain._tower_impostor.global_position, new_site])
	probe.free()
	terrain.free()
	await process_frame
	Sentinel.done("new_run_keeps_the_site")


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
	Sentinel.done("join_streams_the_tower_at_the_anchor")


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
	Sentinel.done("a_detached_terrain_still_sites_the_tower")


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
	Sentinel.done("no_road_coin_is_buried_in_the_walls")


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

	PALETTE PARITY AND THE CROSS-FADE are the third, added by bead godot-test1-rgt
	after the owner reported the tower reading black at range and popping to white
	on arrival. Both halves of that were authored: a near-black impostor palette
	that shared nothing with the shell, and a hard `visible = false` at the load
	radius. So this check now also asserts

	  * that no impostor colour is a palette of its own — each is the SHELL's colour
	    for that box put through `_impostor_color`, which is the only form of the
	    assertion that a second authored palette cannot pass;
	  * that the fade band is really configured on the material, and that the meshes
	    are culled once it has finished, so a transparent building is not still
	    being drawn over the real one; and
	  * that the band sits inside the WORST-CASE load distance — TOWER_LOAD_RADIUS
	    minus the chunk DIAGONAL minus the footprint radius (see the three terms
	    below the loop). Outside that, a player walks into a half-faded silhouette
	    with no building behind it, which is a worse artefact than the one being
	    fixed.
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
		# Same shape as the shell's box, not merely the same count and place — the
		# castle's cones and its welded parapet ring all have to arrive out here too.
		_check_mesh_fills_its_box(meshes[i], box)
		var mat := meshes[i].material_override as StandardMaterial3D
		if mat == null:
			_fail("impostor box %d has no material" % i)
			continue
		if not mat.disable_fog:
			_fail("impostor box %d is fogged — at 400 m under the web build's fog it draws nothing" % i)
		if mat.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
			_fail("impostor box %d is lit, not a flat silhouette" % i)
		# THE PARITY ITSELF. Derived from the shell's colour, never authored beside it.
		var want: Color = TowerShell._impostor_color(box["color"])
		if not mat.albedo_color.is_equal_approx(want):
			_fail("impostor box %s is %s but the shell's colour lifts to %s — the impostor has a palette of its own again" % [
				box["name"], mat.albedo_color, want])
		if mat.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_DISABLED:
			_fail("impostor box %s does not cross-fade — the handover is a hard swap again" % box["name"])
		if not is_equal_approx(mat.distance_fade_min_distance, TowerShell.IMPOSTOR_FADE_NEAR) \
				or not is_equal_approx(mat.distance_fade_max_distance, TowerShell.IMPOSTOR_FADE_FAR):
			_fail("impostor box %s fades over %.0f-%.0f m, not the declared %.0f-%.0f m" % [
				box["name"], mat.distance_fade_min_distance, mat.distance_fade_max_distance,
				TowerShell.IMPOSTOR_FADE_NEAR, TowerShell.IMPOSTOR_FADE_FAR])
		# ...and it stops being submitted once it is fully transparent, but never
		# while the fade would still have drawn a pixel.
		# MEASURED AGAINST THE MESH'S FURTHEST CORNER, not against NEAR flat (codex
		# review, 2026-08-30). The range test is a camera-to-origin distance while
		# the fade is per pixel, so on an 80 m box the far face is 40 m behind the
		# origin: culling at NEAR deletes pixels that were still visibly fading,
		# which is a pop inside the machinery that exists to remove one.
		var cull: float = meshes[i].visibility_range_begin
		var reach: float = (box["size"] as Vector3).length() * 0.5
		if cull <= 0.0:
			_fail("impostor box %s is never culled — a fully transparent building is still being rasterised in the doorway" % box["name"])
		elif cull + reach > TowerShell.IMPOSTOR_FADE_NEAR + EPS:
			_fail("impostor box %s is culled at %.1f m but reaches %.1f m past its origin, so its far face is still inside the %.0f m fade band — it would vanish mid-fade" % [
				box["name"], cull, reach, TowerShell.IMPOSTOR_FADE_NEAR])

	if TowerShell.IMPOSTOR_FADE_NEAR >= TowerShell.IMPOSTOR_FADE_FAR:
		_fail("the impostor's fade band is inverted: NEAR %.0f m is not inside FAR %.0f m" % [
			TowerShell.IMPOSTOR_FADE_NEAR, TowerShell.IMPOSTOR_FADE_FAR])

	# THE BAND FITS INSIDE THE WORST-CASE LOAD. Read off a live terrain, both
	# numbers, so retuning either one fails here rather than in the view.
	# THREE TERMS, AND THE FIRST DRAFT OF THIS CHECK GOT TWO OF THEM WRONG (codex
	# review, 2026-08-30 — it subtracted one chunk SIDE and measured to the tower's
	# CENTRE, and so certified 310 m for a band that can really open at 225.6 m):
	#
	#   * TOWER_LOAD_RADIUS is where the shell is promised;
	#   * minus the chunk DIAGONAL, because `_tower_stream` runs on a boundary
	#     CROSSING and a player can cross a chunk corner-to-corner between two of
	#     them — sqrt(2) * chunk_size, not chunk_size;
	#   * minus footprint_radius(), because `distance_fade` is per PIXEL: the fade
	#     opens on the impostor's nearest corner, which is that much closer to the
	#     camera than the centre the load test measures.
	var terrain := _make_terrain(SEED_A)
	var chunk_diagonal: float = sqrt(2.0) * float(terrain.chunk_size)
	var worst_case: float = terrain.TOWER_LOAD_RADIUS - chunk_diagonal - TowerShell.footprint_radius()
	terrain.free()
	if TowerShell.IMPOSTOR_FADE_FAR > worst_case:
		_fail("the impostor's nearest pixel starts fading at %.0f m but the shell is only guaranteed by %.1f m (TOWER_LOAD_RADIUS - chunk diagonal %.1f - footprint %.1f) — there is a window with a half-faded silhouette and no building behind it" % [
			TowerShell.IMPOSTOR_FADE_FAR, worst_case, chunk_diagonal, TowerShell.footprint_radius()])
	else:
		print("impostor cross-fade: opaque beyond %.0f m, gone by %.0f m, nearest pixel guaranteed a shell by %.1f m" % [
			TowerShell.IMPOSTOR_FADE_FAR, TowerShell.IMPOSTOR_FADE_NEAR, worst_case])

	# A picture and nothing else: no collision anywhere under it, or the field 400 m
	# out grows an invisible wall.
	if _has_collision(impostor):
		_fail("the horizon impostor carries a collision body — it is a picture, not a building")
	impostor.free()
	Sentinel.done("impostor")


func _check_impostor_hidden_in_budapest() -> void:
	"""
	Check 9b. The horizon impostor is hidden while the LOCAL player stands
	inside Budapest and returns the instant they step out.

	The fade band still owns opacity outside the city; this only suppresses
	the PICTURE entirely while inside, so the city on the horizon is not
	doubled by a second, fog-exempt silhouette behind it. "All heroes" is the
	local player — each peer decides for its own screen, remote avatars are
	pictures (bead godot-test1-8gw.14).
	"""
	var terrain := _make_terrain(SEED_A)
	terrain.render_distance = 0
	var probe := Node3D.new()
	probe.add_to_group("player")
	root.add_child(probe)
	terrain.player = probe
	# Drive the per-tick visibility update without waiting for a chunk-boundary
	# crossing — the update rides _process every frame, not the streamer's
	# boundary hook.
	var inside := Vector3(
			BudapestPlan.BUDAPEST_MIN.x + (BudapestPlan.BUDAPEST_MAX.x - BudapestPlan.BUDAPEST_MIN.x) * 0.5,
			0.0,
			BudapestPlan.BUDAPEST_MIN.y + (BudapestPlan.BUDAPEST_MAX.y - BudapestPlan.BUDAPEST_MIN.y) * 0.5)
	var outside := Vector3(BudapestPlan.BUDAPEST_MIN.x - 1.0, 0.0, 0.0)
	# One metre west of the rect's edge, still outside TOWER_LOAD_RADIUS, so
	# the usual far-field impostor is visible.
	if BudapestPlan.contains(outside.x, outside.z):
		_fail("self-check outside probe %s is inside Budapest — test is vacuous" % outside)
	if not BudapestPlan.contains(inside.x, inside.z):
		_fail("self-check inside probe %s is outside Budapest — test is vacuous" % inside)
	probe.global_position = inside
	terrain._process(0.0)
	if not is_instance_valid(terrain._tower_impostor):
		_fail("no horizon impostor to hide inside Budapest")
	elif terrain._tower_impostor.visible:
		_fail("the horizon impostor is still visible while the player stands inside Budapest at %s (rect %s -> %s)" % [
				inside, BudapestPlan.BUDAPEST_MIN, BudapestPlan.BUDAPEST_MAX])
	probe.global_position = outside
	terrain._process(0.0)
	if not is_instance_valid(terrain._tower_impostor):
		_fail("no horizon impostor after stepping out of Budapest")
	elif not terrain._tower_impostor.visible:
		_fail("the horizon impostor stayed hidden after the player stepped out of Budapest to %s" % outside)
	print("impostor Budapest gate: hidden at %s, visible at %s" % [inside, outside])
	probe.free()
	terrain.free()
	Sentinel.done("impostor_hidden_in_budapest")


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
	Sentinel.done("minimap_marks_the_tower")


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


func _check_the_roof_keeps_the_rain_out() -> void:
	"""
	Check 13. It does not rain indoors, and it still rains outdoors.

	THE BUG THIS IS THE ALARM FOR (godot-test1-li2): phase 13 put a lid on the
	shell and the weather never heard about it. `is_raining_at()` is a flat XZ
	circle around a storm cloud, and the emitter spawns its streaks ~14 m ABOVE the
	player — so a storm over the HQ rained inside the building and, through
	`player_controller._weather_is_raining_here()`, refused Windman's Air Rush in a
	room with a ceiling.

	TWO HALVES, AND BOTH ARE LOAD-BEARING:

	  * The GEOMETRY half asks the shell directly. `sheltered()` has to answer for
	    the whole 80 m roofed footprint — not `TowerInterior.inside_walls()`, which
	    was the 20 m phase-3 keep and would have left five-sixths of the building
	    wet —
	    and it has to STOP at the roof's underside, or the tower becomes a column of
	    weather immunity reaching into the sky.
	  * The WIRING half asks a real `WeatherManager` under a real storm cloud. That
	    is the half that fails if the group name drifts, if the guard is spelled
	    with the wrong method name, or if somebody puts the shelter test in one
	    consumer instead of in the shared query — because the single point measured
	    here, `is_raining_at()`, is exactly what the emitter, the rain bed and the
	    ability gate all read.

	The shell is parked at a site far from the origin on purpose: a `sheltered()`
	written against local coordinates and handed a world point passes at (0,0,0)
	and nowhere else in the game.
	"""
	var site := Vector3(400.0, 0.0, -120.0)
	var shell := _make_shell()
	shell.position = site
	await process_frame  # global transforms are only real once a frame has run

	# The group wiring the weather query depends on. If this resolves to anything
	# but the shell we just built, everything below is measuring the wrong tower.
	if root.get_tree().get_first_node_in_group("tower") != shell:
		_fail("check 13: group \"tower\" did not resolve to the shell — the weather query cannot find it")

	var half: float = TowerShell.OUTER_HALF
	var top: float = TowerShell.WALL_HEIGHT
	# Inside: the four corners and the middle, at head height and just under the
	# top storey's ceiling. All of it is roofed, so all of it is dry.
	for x: float in [-half + 1.0, 0.0, half - 1.0]:
		for z: float in [-half + 1.0, 0.0, half - 1.0]:
			for y: float in [1.0, top - 1.0]:
				if not shell.sheltered(site + Vector3(x, y, z)):
					_fail("check 13: sheltered() said no at (%.1f, %.1f, %.1f) inside the footprint" % [x, y, z])

	# Outside: one step past each face, and one step onto the roof.
	var exposed: Dictionary = {
		"past the door (+X)": Vector3(half + 1.0, 1.0, 0.0),
		"past the back wall (-X)": Vector3(-half - 1.0, 1.0, 0.0),
		"past the +Z wall": Vector3(0.0, 1.0, half + 1.0),
		"past the -Z wall": Vector3(0.0, 1.0, -half - 1.0),
		"standing ON the roof": Vector3(0.0, top + 1.0, 0.0),
		"out in the field": Vector3(half * 4.0, 1.0, 0.0),
	}
	for where: String in exposed:
		if shell.sheltered(site + (exposed[where] as Vector3)):
			_fail("check 13: sheltered() said yes %s — the roof does not extend there" % where)

	# ---- the wiring half: a real manager, a real storm, over the real building.
	var weather := Node3D.new()
	weather.set_script(load(WEATHER_SCRIPT))
	root.add_child(weather)
	# One hand-planted storm cloud, big enough to soak the tower and its doorstep.
	# Planted rather than waited for: the cloud field is randomize()d ambience (it
	# is deliberately outside the determinism contract), so a check that waited for
	# a storm to drift over the HQ would be a check that sometimes ran.
	weather._clouds = [{
		"center": site + Vector3(0.0, 120.0, 0.0),
		"boxes": [],
		"is_storm": true,
		"radius": STORM_RADIUS,
		"speed": 0.0,
		"bob_phase": 0.0,
	}]

	# Indoors, in the middle of that storm: no rain. This is the one call the
	# emitter, the rain bed and the Air Rush gate all make.
	if weather.is_raining_at(site + Vector3(0.0, 1.0, 0.0)):
		_fail("check 13: is_raining_at() still rains inside the sealed HQ")
	# One step out of the door, same storm: rain again. Without this the "fix"
	# could be a weather manager that never rains anywhere.
	if not weather.is_raining_at(site + Vector3(half + 2.0, 1.0, 0.0)):
		_fail("check 13: is_raining_at() said dry OUTSIDE the tower under a storm — the shelter test is too wide")
	# And the roof is not an umbrella for the whole column above it.
	if not weather.is_raining_at(site + Vector3(0.0, top + 1.0, 0.0)):
		_fail("check 13: is_raining_at() said dry on top of the roof")

	weather.free()
	shell.free()
	Sentinel.done("the_roof_keeps_the_rain_out")


func _check_clouds_stay_clear_of_the_hq() -> void:
	"""
	Check 14. No cloud is ever inside the HQ.

	THE BUG (godot-test1-x7k, owner playtest): `CLOUD_ALTITUDE_MIN` was 45 m, the
	sealed shell is `WALL_HEIGHT + ROOF_THICK` = 52 m tall, and the wind is XZ-only
	— so every cloud in the bottom 7 m of the band sailed through storeys 9 and 10
	and out of the roof, in full view from inside.

	WHY THIS CHECK AND NOT A COMMENT: the weather manager deliberately does not
	depend on the tower (no headless harness has one, and neither does the field
	outside `TOWER_LOAD_RADIUS`), so its floor and its keep-out radius are RESTATED
	constants, not imported ones. Restated numbers drift. This is the only place
	both sides are read at once — grow the building or shrink the disc and it says
	so here rather than in a screenshot three weeks later.

	THREE PARTS, and the third is the one that would survive a rewrite of the other
	two: an ALTITUDE bound, a RADIUS bound, and then a real manager, ticked over the
	real site, measured through the MultiMesh the player actually sees. The last one
	is what makes the check about a field that really drifted rather than about
	arithmetic — a keep-out applied to the wrong quantity passes both bounds.
	"""
	var terrain := _make_terrain(SEED_A)
	var site: Vector3 = terrain.tower_site()

	var weather := Node3D.new()
	weather.set_script(load(WEATHER_SCRIPT))
	root.add_child(weather)

	# The tallest a single puff can hang below its cluster centre: the cluster's own
	# downward scatter plus half a storm-sized puff. Anything less than this over the
	# roof and the band's floor is a number that only LOOKS clear.
	var puff_half: float = weather.CLOUD_BOX_SIZE_MAX * weather.STORM_SIZE_FACTOR * 0.5
	var sag: float = weather.BOB_AMPLITUDE + weather.CLOUD_SPREAD * 0.3 + puff_half
	var roof_top: float = TowerShell.WALL_HEIGHT + TowerShell.ROOF_THICK
	if weather.CLOUD_ALTITUDE_MIN < roof_top + sag:
		_fail("check 14: CLOUD_ALTITUDE_MIN %.1f m does not clear the %.1f m roof by a cloud's own %.1f m sag" % [
			weather.CLOUD_ALTITUDE_MIN, roof_top, sag])
	if weather.CLOUD_ALTITUDE_MAX <= weather.CLOUD_ALTITUDE_MIN:
		_fail("check 14: the cloud altitude band is empty or inverted")

	# The keep-out disc has to cover the exclusion disc the shell is promised (read
	# off the live terrain, exactly as check 2 does) PLUS how far a cluster reaches
	# from the centre the keep-out is applied to.
	var reach: float = Vector2(weather.CLOUD_SPREAD, weather.CLOUD_SPREAD).length() + puff_half
	if weather.CLOUD_TOWER_KEEPOUT < terrain.TOWER_RADIUS + reach:
		_fail("check 14: CLOUD_TOWER_KEEPOUT %.1f m is under TOWER_RADIUS %.1f m + a cluster's %.1f m reach" % [
			weather.CLOUD_TOWER_KEEPOUT, terrain.TOWER_RADIUS, reach])

	# The shell's whole volume, spire and beacon included — the band above is well
	# clear of the ROOF, and deliberately not clear of the keep, which is why the
	# XZ keep-out has to exist at all.
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for box: Dictionary in TowerShell.boxes():
		var pos: Vector3 = box["pos"]
		var half: Vector3 = box["size"] * 0.5
		lo = lo.min(pos - half)
		hi = hi.max(pos + half)
	var volume := AABB(site + lo, hi - lo)

	# A player parked at the door, so the cloud field is centred on the building and
	# the wind walks the whole field across it. No frame is awaited from here on: the
	# terrain would stream a ring of chunks around this node for nothing.
	var player := Node3D.new()
	player.add_to_group("player")
	player.position = site
	root.add_child(player)

	var tick: float = weather.TICK_INTERVAL
	weather._process(tick)  # first tick fills the field around the player
	# One cloud planted dead over the keep, at the very bottom of the band: the
	# drift below would get there eventually, but a check that relies on randomized
	# ambience to reach the failure case is a check that sometimes runs.
	if not weather._clouds.is_empty():
		weather._clouds[0]["center"] = site + Vector3(0.0, weather.CLOUD_ALTITUDE_MIN, 0.0)
		weather._process(tick)
		_clouds_clear_of(weather, volume, "after being planted on top of the keep")
	# TWO STATIONS, and the second is not decoration. With the player AT the site a
	# recycled cloud re-enters a whole FIELD_RADIUS away and can never land on the
	# building — so a keep-out applied BEFORE the recycler would pass this check.
	# From 200 m out the re-entry rim crosses the keep-out disc, which is exactly
	# the one-tick window codex found (2026-08-30).
	for station: Vector3 in [site, site + Vector3(200.0, 0.0, 0.0)]:
		player.position = station
		for i in CLOUD_DRIFT_TICKS:
			weather._process(tick)
			if not _clouds_clear_of(weather, volume, "after %.1f s of drift, player %.0f m out" % [
					(i + 1) * tick, station.distance_to(site)]):
				break

	player.free()
	weather.free()
	terrain.free()
	Sentinel.done("clouds_stay_clear_of_the_hq")


func _clouds_clear_of(weather: Node, volume: AABB, when: String) -> bool:
	## Every puff of every live cloud against the shell's volume. A puff is an
	## ellipsoid yawed about Y, so its XZ half-extent is bounded by its widest
	## horizontal semi-axis whatever the yaw; the vertical one carries the full sine
	## bob, so the answer holds for every phase rather than for the one this tick
	## happens to be at. Returns false on the first offender, so a cloud parked
	## inside the building cannot print CLOUD_DRIFT_TICKS lines.
	##
	## Read off the manager's own cloud list rather than the MultiMesh it writes:
	## `--headless` runs the dummy rendering server, and reading an instance
	## transform back from it returns identity — a check written against the render
	## buffer would pass no matter what the sky did.
	for cloud: Dictionary in weather._clouds:
		var center: Vector3 = cloud["center"]
		for box: Dictionary in cloud["boxes"]:
			var size: Vector3 = box["size"]
			var half := Vector3(
					maxf(size.x, size.z) * 0.5,
					size.y * 0.5 + weather.BOB_AMPLITUDE,
					maxf(size.x, size.z) * 0.5)
			var at: Vector3 = center + (box["offset"] as Vector3)
			if volume.intersects(AABB(at - half, half * 2.0)):
				_fail("check 14: a cloud puff at (%.1f, %.1f, %.1f) is inside the HQ %s" % [
					at.x, at.y, at.z, when])
				return false
	return true


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
		Sentinel.finish(self)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	quit(1)
