extends SceneTree
## Headless self-check for crowd_manager.gd (Budapest citizen crowds).
##
##   godot --headless --path . --script res://scripts/crowd_selfcheck.gd
##
## Prints "SELFCHECK OK" and exits 0, or prints failure details and exits 1.
##
## Validates:
##   1. Isolation contract: CrowdManager is in group "crowd", all descendants
##      join NO gameplay groups ("player", "crocodile", "enemy", "boss", "terrain"),
##      and carry NO collision bodies or Area3Ds (recursive check).
##   2. Mesh and material sharing: 4 MultiMeshInstance3D nodes (Windman, Primm,
##      Teibi, Phoboman), shared StandardMaterial3D with vertex colors and sRGB,
##      shared archetype meshes with feet at y = 0.
##   3. City boundaries and terrain safety: citizens spawn and walk strictly inside
##      BudapestPlan.rect(), never enter the wet Danube, never enter plateaus,
##      and maintain feet at y = 0.
##   4. Street grid wayfinding: walkers follow the 62 m grid, stop at crossings,
##      and choose valid street branches without getting stuck.
##   5. Platform budget and dormancy: 0 active walkers outside Budapest, up to
##      CROWD_MAX (60 web / 120 desktop) active walkers inside Budapest around player.
##   6. MultiMesh buffer readback: transforms read from MultiMesh.buffer are
##      finite, inside BudapestPlan.rect(), and outside Danube water.
##   8. SOLID, AND NEVER A CAGE (bead 8gw.21): the pooled proxy colliders are the
##      MANAGER's and nobody else's — every CollisionObject3D under the manager is
##      one of at most CITIZEN_PROXY_POOL StaticBody3Ds on the fauna-precedent
##      layer, in no group, carrying no mesh — and a REAL player.tscn driven by the
##      SHIPPED movement is (a) stopped by a citizen and (b) through it within a
##      beat, each mutation-tested against the other's absence.
##   9. NO GAMEPLAY GROUP GAINED A MEMBER: the proxy layer is invisible to the
##      shipped crocodile's own mask, and the shipped Stink Wave sweep touches the
##      crocodiles and nothing of the crowd's with a live crowd in the tree.
##   7. THE COARSE TICK (bead 8gw.22): a citizen the camera cannot see is ticked
##      a few times a second by the REAL elapsed time — it ADVANCES, it is never
##      frozen — a null camera degrades to full-rate updates for everything, and
##      the question asked is the CAMERA's rather than the player's, which is the
##      only thing that is right in all THREE views C cycles (THIRD_PERSON,
##      FIRST_PERSON and FRONT, which looks BACKWARD along the hero).

const SIM_FRAMES: int = 300
const DT: float = 1.0 / 60.0

## The coarse-tick window: 2 s at 60 Hz. Long enough that a 0.25 s tick fires
## ~8 times, so "advances" is measured over many ticks and not one lucky one.
const LOD_FRAMES: int = 120

## Where the two probe walkers stand relative to the hero, in metres along its
## facing. Comfortably more than AmbienceLod.FRUSTUM_MARGIN plus the third-person
## boom, so the probe behind the hero is unambiguously outside the margin.
const PROBE_REACH_MIN: float = 36.0
const PROBE_REACH_MAX: float = 60.0

const AmbienceLod := preload("res://scripts/ambience_lod.gd")
const Proxies := preload("res://scripts/ambience_proxies.gd")
const CrowdScript := preload("res://scripts/crowd_manager.gd")
const PLAYER_SCENE: String = "res://scenes/player.tscn"

## How many CollisionObject3Ds the isolation walk found under the manager.
var _proxies_seen: int = 0

## Where the probe citizen stands, straight ahead of the hero (metres). Contact
## is at ~0.8 m (player capsule 0.5 + proxy half 0.3), so a walking hero reaches
## it in well under half a second.
const PROBE_AHEAD: float = 2.0

## A street corner the crowd is happy to walk: Pest inner city.
const SOLID_PROBE_SPOT := Vector3(2900.0, 0.0, 0.0)

## The SOLID window: shorter than the anti-trap latch's own fuse. Measured — the
## hero reaches the citizen at frame ~14 and the latch (AmbienceProxies.
## STUCK_SECONDS, 0.5 s) therefore fires at frame ~44, so 30 frames is squarely
## "blocked", and what this measures is a citizen being solid rather than the
## yield happening not to have fired yet.
const SOLID_FRAMES: int = 30

## The NEVER-TRAPPED window, from the same standing start. Long enough for the
## latch to fire and for the hero to walk clear.
const ESCAPE_FRAMES: int = 200

var _root: Node3D = null
var _manager: Node3D = null
var _player: CharacterBody3D = null
var _failures: Array[String] = []
var _started: bool = false


## THE END-OF-CHECK SENTINEL. A GDScript runtime error aborts the FUNCTION it
## lands in and lets the script carry on, so a check that dies halfway simply
## stops asserting and this file prints "SELFCHECK OK". Every check below stamps
## itself at its exit; the report site asks whether every stamp was reached.
## `scripts/selfcheck_sentinel.gd` carries the whole reasoning.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")


func _initialize() -> void:
	_root = Node3D.new()
	root.add_child(_root)

	_player = CharacterBody3D.new()
	_player.name = "Player"
	_player.add_to_group("player")
	_player.position = Vector3(0.0, 1.0, 0.0) # Start outside Budapest
	_root.add_child(_player)

	var mgr_script: GDScript = load("res://scripts/crowd_manager.gd")
	_manager = Node3D.new()
	_manager.set_script(mgr_script)
	_root.add_child(_manager)


func _process(_delta: float) -> bool:
	# ONE shot: the checks below await physics frames, so this must not re-enter.
	if _started:
		return false
	_started = true
	_run_checks()
	return false


func _run_checks() -> void:
	print("--- Running crowd_selfcheck ---")

	_check_groups_and_collision()
	_check_multimesh_resources()
	_check_dormancy_outside_budapest()
	_check_simulation_and_boundaries()
	_check_coarse_tick_and_camera_views()
	await _check_solid_and_never_trapped()
	await _check_no_gameplay_group_gained_a_member()

	if _failures.is_empty():
		print("crowd_selfcheck: all checks passed cleanly")
		Sentinel.finish(self)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		quit(1)


func _check_groups_and_collision() -> void:
	## 1. Recursive group and collision isolation
	if not _manager.is_in_group("crowd"):
		_failures.append("CrowdManager is not in group 'crowd'")

	for g: String in ["player", "crocodile", "enemy", "boss", "terrain"]:
		if _manager.is_in_group(g):
			_failures.append("CrowdManager illegally joined gameplay group '%s'" % g)

	_proxies_seen = 0
	_check_node_isolation_recursive(_manager)
	if _proxies_seen != CrowdScript.CITIZEN_PROXY_POOL:
		_failures.append("the manager owns %d proxy bodies, expected exactly"
			% _proxies_seen + " CITIZEN_PROXY_POOL (%d) — the pool is a CONSTANT,"
			% CrowdScript.CITIZEN_PROXY_POOL
			+ " and one body per citizen is what this whole design refuses")
	Sentinel.done("groups_and_collision")


func _check_node_isolation_recursive(node: Node) -> void:
	## TIGHTENED rather than loosened by bead 8gw.21. The rule used to be "no
	## CollisionObject3D anywhere under this manager", which the pooled proxies
	## would simply break; the rule it becomes is stricter about everything that
	## mattered and says exactly what the ONE exception is. A CITIZEN still has no
	## body — a citizen is not a node at all — so what this now forbids is a body
	## that is not one of the manager's own numbered pool slots, a pool bigger than
	## CITIZEN_PROXY_POOL, one on a layer a predator can see, one carrying a mesh
	## (which would cost the draw call the whole design exists to protect) and, as
	## before, any group membership and any Area3D whatsoever.
	if node != _manager:
		var groups := node.get_groups()
		if not groups.is_empty():
			_failures.append("CrowdManager descendant '%s' has groups: %s (must have none)" % [node.name, str(groups)])
		if node is Area3D:
			_failures.append("CrowdManager descendant '%s' is an Area3D (must have none)" % node.name)
		elif node is CollisionObject3D:
			_proxies_seen += 1
			if not String(node.name).begins_with(Proxies.PROXY_NAME_PREFIX):
				_failures.append("CrowdManager descendant '%s' is a CollisionObject3D that is not"
					% node.name + " a pooled proxy — citizens themselves must carry no body")
			if not (node is StaticBody3D):
				_failures.append("proxy '%s' is not a StaticBody3D — anything that can be"
					% node.name + " driven by physics can push the hero")
			var body := node as CollisionObject3D
			if body.collision_layer != Proxies.PROXY_LAYER:
				_failures.append("proxy '%s' is on collision layer %d, not the fauna-precedent"
					% [node.name, body.collision_layer]
					+ " layer %d that ONLY the player masks" % Proxies.PROXY_LAYER)
			if body.collision_mask != 0:
				_failures.append("proxy '%s' masks %d — a proxy asks the world nothing;"
					% [node.name, body.collision_mask] + " the player asks it")
		if node is VisualInstance3D and not (node is MultiMeshInstance3D):
			_failures.append("CrowdManager descendant '%s' is a VisualInstance3D that is not"
				% node.name + " one of the four crowd MultiMeshes — the draw-call story is 4")

	for child in node.get_children():
		_check_node_isolation_recursive(child)
	Sentinel.done("node_isolation_recursive")


func _check_multimesh_resources() -> void:
	## 2. MultiMesh count, shared materials, and feet at y = 0
	var mm_nodes: Array = _manager.get("_multimesh_nodes")
	if mm_nodes.size() != 4:
		_failures.append("Expected exactly 4 MultiMeshInstance3D nodes, found %d" % mm_nodes.size())
		Sentinel.done("multimesh_resources")
		return

	var shared_mat: Material = mm_nodes[0].material_override
	if shared_mat == null:
		_failures.append("MultiMesh material_override is null")

	for k in 4:
		var node: MultiMeshInstance3D = mm_nodes[k]
		if node == null:
			_failures.append("MultiMeshInstance3D at index %d is null" % k)
			continue
		if node.material_override != shared_mat:
			_failures.append("MultiMeshInstance3D %s does not share the common material" % node.name)
		var mm: MultiMesh = node.multimesh
		if mm == null:
			_failures.append("MultiMeshInstance3D %s has null multimesh" % node.name)
			continue
		if mm.mesh == null:
			_failures.append("MultiMesh in %s has null mesh" % node.name)
			continue
		if mm.instance_count <= 0:
			_failures.append("MultiMesh in %s has instance_count <= 0" % node.name)

		# Verify mesh feet rest at y = 0 by construction
		var aabb: AABB = mm.mesh.get_aabb()
		if absf(aabb.position.y) > 0.001:
			_failures.append("MultiMesh %s mesh AABB position.y is %f (must be 0.0 for feet at y=0)" % [node.name, aabb.position.y])
	Sentinel.done("multimesh_resources")


func _check_dormancy_outside_budapest() -> void:
	## 3. Outside Budapest: all citizens dormant
	_player.position = Vector3(0.0, 1.0, 0.0) # Wilderness
	_manager._process(DT)

	var mm_nodes: Array = _manager.get("_multimesh_nodes")
	var total_visible := 0
	for node: MultiMeshInstance3D in mm_nodes:
		total_visible += node.multimesh.visible_instance_count

	if total_visible != 0:
		_failures.append("Crowd rendered %d visible instances while player is outside Budapest at x=0" % total_visible)
	Sentinel.done("dormancy_outside_budapest")


func _check_simulation_and_boundaries() -> void:
	## 4. Inside Budapest: spawn and simulate movement
	# Test location 1: Buda Gate / Avenue (x = 1750, z = 0)
	_player.position = Vector3(1750.0, 1.0, 0.0)
	for frame in 60:
		_manager._process(DT)

	_verify_active_citizens("Buda Avenue (x=1750)")

	# Test location 2: Pest Inner City / Erzsébet Square (x = 2900, z = 0)
	_player.position = Vector3(2900.0, 1.0, 0.0)
	for frame in SIM_FRAMES:
		_manager._process(DT)
		if frame % 30 == 0:
			_verify_active_citizens("Pest Inner City frame %d" % frame)

	# Test location 3: Heroes' Square (x = 3520, z = -520)
	_player.position = Vector3(3520.0, 1.0, -520.0)
	for frame in 60:
		_manager._process(DT)

	_verify_active_citizens("Heroes' Square (x=3520)")
	Sentinel.done("simulation_and_boundaries")


func _verify_active_citizens(context: String) -> void:
	var plan_script: GDScript = load("res://scripts/budapest_plan.gd")
	var mgr_script: GDScript = load("res://scripts/crowd_manager.gd")
	var citizens: Array = _manager.get("_citizens")
	var crowd_max: int = _manager.get("_crowd_max")
	var active_count := 0

	for citizen: Dictionary in citizens:
		if not citizen["active"]:
			continue
		active_count += 1
		var pos: Vector3 = citizen["pos"]

		# Must be strictly within Budapest bounds
		if not plan_script.contains(pos.x, pos.z):
			_failures.append("%s: citizen at (%f, %f) outside Budapest bounds" % [context, pos.x, pos.z])

		# Must never enter the wet Danube river
		if plan_script.danube_wet(pos.x, pos.z):
			_failures.append("%s: citizen at (%f, %f) is walking in the Danube river" % [context, pos.x, pos.z])

		# Must never enter a plateau
		if plan_script.plateau_top_at(pos.x, pos.z) > 0.0:
			_failures.append("%s: citizen at (%f, %f) is on a plateau cliff" % [context, pos.x, pos.z])

		# Must never enter solid landmark buildings
		if mgr_script._is_inside_solid_landmark(pos.x, pos.z):
			_failures.append("%s: citizen at (%f, %f) is inside a solid landmark building" % [context, pos.x, pos.z])

		# Speed must be positive
		if citizen["speed"] <= 0.0:
			_failures.append("%s: citizen has invalid speed %f" % [context, citizen["speed"]])

	if active_count == 0:
		_failures.append("%s: 0 active citizens spawned around player inside Budapest" % context)

	# Assert active count does not exceed platform budget
	if active_count > crowd_max:
		_failures.append("%s: active citizen count %d exceeds platform budget %d" % [context, active_count, crowd_max])

	# Assert MultiMesh buffer readback values
	var mm_nodes: Array = _manager.get("_multimesh_nodes")
	for k in mm_nodes.size():
		var node: MultiMeshInstance3D = mm_nodes[k]
		var mm: MultiMesh = node.multimesh
		var buf: PackedFloat32Array = mm.buffer
		var vis: int = mm.visible_instance_count
		for idx in vis:
			var base := idx * 12
			var ox: float = buf[base + 3]
			var oy: float = buf[base + 7]
			var oz: float = buf[base + 11]
			var origin := Vector3(ox, oy, oz)

			if not origin.is_finite():
				_failures.append("%s: MultiMesh %s instance %d has non-finite origin %s" % [context, node.name, idx, str(origin)])
			if not mgr_script.is_walkable(ox, oz):
				_failures.append("%s: MultiMesh %s instance %d drawn origin (%f, %f) is not walkable" % [context, node.name, idx, ox, oz])


# ============================================================================
# 7. THE COARSE TICK — "only those moving who we can see", without freezing
# ============================================================================

func _place_probe(citizen: Dictionary, world: Vector3) -> void:
	## Stands one walker at `world` walking +X at a fixed pace, with its target
	## far enough away that it never reaches a crossing inside the window (so no
	## pause roll and no waypoint re-pick can perturb the distance measured).
	citizen["pos"] = world
	citizen["target"] = world + Vector3(200.0, 0.0, 0.0)
	citizen["heading_dir"] = Vector2(1.0, 0.0)
	citizen["facing_yaw"] = 0.0
	citizen["lane_offset"] = 0.0
	citizen["speed"] = 2.0
	citizen["walk_phase"] = 0.0
	citizen["pause_timer"] = 0.0
	citizen["lod_debt"] = 0.0
	citizen["lod_step"] = 0.0
	citizen["active"] = true


func _probe_site(home: Vector3, sign: float) -> Vector3:
	## First walkable spot `sign`-ward of the hero along X, far enough out that
	## the frustum margin cannot reach it, and still walkable 5 m further on so
	## the probe cannot be recycled mid-window. Vector3.INF if there is none.
	var d: float = PROBE_REACH_MIN
	var mgr_script: GDScript = load("res://scripts/crowd_manager.gd")
	while d <= PROBE_REACH_MAX:
		var x: float = home.x + sign * d
		if mgr_script.is_walkable(x, home.z) and mgr_script.is_walkable(x + 5.0, home.z):
			return Vector3(x, 0.0, home.z)
		d += 2.0
	return Vector3.INF


func _drive_probes(frames: int, probes: Array[Dictionary]) -> Array:
	## Runs the SHIPPED _process for `frames` and reports, per probe,
	## {distance travelled, frames it stepped on, total time it was granted}.
	var start: Array[Vector3] = []
	var stepped: Array[int] = [0, 0]
	var granted: Array[float] = [0.0, 0.0]
	for p: Dictionary in probes:
		start.append(p["pos"])
	for f in frames:
		_manager._process(DT)
		for i in probes.size():
			var s: float = float(probes[i]["lod_step"])
			if s > 0.0:
				stepped[i] += 1
				granted[i] += s
	var out: Array = []
	for i in probes.size():
		out.append({
			"dist": (probes[i]["pos"] as Vector3).distance_to(start[i]),
			"stepped": stepped[i],
			"granted": granted[i],
		})
	return out


func _check_coarse_tick_and_camera_views() -> void:
	## Two probe walkers, one AHEAD of the hero and one BEHIND it, driven through
	## the shipped _process under each of the three cameras C cycles. Which of
	## them runs at full rate is the whole point: a gate written against the
	## PLAYER's facing would answer the same in all three, and the FRONT view —
	## whose camera stands in front of the hero looking BACK along it — would be
	## exactly wrong. See scripts/ambience_lod.gd.
	var home := Vector3(2900.0, 1.0, 0.0)
	_player.position = home
	var ahead_site: Vector3 = _probe_site(home, 1.0)
	var behind_site: Vector3 = _probe_site(home, -1.0)
	if not ahead_site.is_finite() or not behind_site.is_finite():
		_failures.append("coarse tick: no walkable probe site %.0f-%.0f m either side of %s"
			% [PROBE_REACH_MIN, PROBE_REACH_MAX, str(home)])
		Sentinel.done("coarse_tick_and_camera_views")
		return

	var citizens: Array = _manager.get("_citizens")
	var ahead: Dictionary = citizens[0]
	var behind: Dictionary = citizens[1]
	var probes: Array[Dictionary] = [ahead, behind]

	# --- A. NULL CAMERA => full rate for everything (today's behaviour) --------
	# There is no camera in this harness yet, which is the degrade every headless
	# run and every standalone scene gets. Both probes must step EVERY frame.
	_place_probe(ahead, ahead_site)
	_place_probe(behind, behind_site)
	var null_cam: Array = _drive_probes(LOD_FRAMES, probes)
	for i in 2:
		if int(null_cam[i]["stepped"]) != LOD_FRAMES:
			_failures.append("null camera: probe %d stepped on %d of %d frames — a camera-less scene must degrade to FULL RATE, never to a coarse tick"
				% [i, int(null_cam[i]["stepped"]), LOD_FRAMES])
	var full_dist: float = float(null_cam[0]["dist"])
	if full_dist < 3.0:
		_failures.append("null camera: full-rate probe covered only %.2f m in %d frames — expected ~%.1f m, and the rest of this check is measured against it"
			% [full_dist, LOD_FRAMES, 2.0 * LOD_FRAMES * DT])

	# --- B. THE THREE VIEWS ---------------------------------------------------
	# Faithful to player_controller._apply_view_mode(): THIRD_PERSON sits the
	# camera behind the hero looking along its facing, FIRST_PERSON sits it at
	# the eyes looking the same way, and FRONT is that arm yawed 180° — in front
	# of the hero, looking BACK at it. The hero faces +X throughout, so FRONT is
	# the view in which the citizen the PLAYER faces is the one nobody can see.
	var cam := Camera3D.new()
	_root.add_child(cam)
	cam.current = true
	var views: Array[Dictionary] = [
		{"name": "THIRD_PERSON", "pos": home + Vector3(-6.0, 2.0, 0.0), "yaw": -PI * 0.5, "sees": 0},
		{"name": "FIRST_PERSON", "pos": home + Vector3(0.0, 0.6, 0.0), "yaw": -PI * 0.5, "sees": 0},
		{"name": "FRONT", "pos": home + Vector3(6.0, 2.0, 0.0), "yaw": PI * 0.5, "sees": 1},
	]
	for v: Dictionary in views:
		# A camera looks down its own -Z, and yaw θ about UP sends -Z to (-sin θ, 0,
		# -cos θ) — so -90° looks along +X (the hero's facing) and +90° looks back.
		cam.global_transform = Transform3D(Basis(Vector3.UP, float(v["yaw"])), v["pos"])
		_place_probe(ahead, ahead_site)
		_place_probe(behind, behind_site)
		var res: Array = _drive_probes(LOD_FRAMES, probes)
		var seen: int = int(v["sees"])
		var unseen: int = 1 - seen
		var vname: String = v["name"]

		# The seen one runs at full rate...
		if int(res[seen]["stepped"]) != LOD_FRAMES:
			_failures.append("%s: the probe IN VIEW stepped on %d of %d frames — a visible citizen must never be coarse-ticked (firing in FRONT alone means the gate is reading the player instead of the camera)"
				% [vname, int(res[seen]["stepped"]), LOD_FRAMES])
		# ...the unseen one is COARSE...
		var unseen_steps: int = int(res[unseen]["stepped"])
		if unseen_steps >= LOD_FRAMES / 4:
			_failures.append("%s: the probe OUT OF VIEW stepped on %d of %d frames — expected about %d at a %.2f s coarse tick; the gate is not gating"
				% [vname, unseen_steps, LOD_FRAMES,
					int(LOD_FRAMES * DT / AmbienceLod.COARSE_TICK_SECONDS), AmbienceLod.COARSE_TICK_SECONDS])
		if unseen_steps == 0:
			_failures.append("%s: the probe OUT OF VIEW never stepped at all in %d frames — that is a FREEZE, not a coarse tick"
				% [vname, LOD_FRAMES])
		# ...and COARSE IS NOT FROZEN: it covers the same ground as the visible
		# one, bar at most one unspent tick. THIS is the assertion that protects
		# "natural" — a street that plausibly kept walking behind your back.
		var unseen_dist: float = float(res[unseen]["dist"])
		var seen_dist: float = float(res[seen]["dist"])
		var slack: float = 2.0 * AmbienceLod.COARSE_TICK_SECONDS + 0.05
		if unseen_dist < seen_dist - slack:
			_failures.append("%s: the out-of-view probe covered %.2f m against the visible probe's %.2f m — a coarse tick advances by the REAL elapsed time, so it may not fall behind by more than one unspent tick (%.2f m)"
				% [vname, unseen_dist, seen_dist, slack])
		# The same claim in the time domain, immune to anything that could slow a
		# walker: every second of wall clock is granted to it, just in fewer,
		# bigger pieces.
		var granted: float = float(res[unseen]["granted"])
		var elapsed: float = LOD_FRAMES * DT
		if absf(granted - elapsed) > AmbienceLod.COARSE_TICK_SECONDS + 0.001:
			_failures.append("%s: the out-of-view probe was granted %.3f s of the %.3f s that passed — the bank must be spent, not dropped"
				% [vname, granted, elapsed])

	cam.current = false
	_root.remove_child(cam)
	cam.free()

	# --- C. The camera going away restores full rate --------------------------
	_place_probe(ahead, ahead_site)
	_place_probe(behind, behind_site)
	var after: Array = _drive_probes(LOD_FRAMES, probes)
	for i in 2:
		if int(after[i]["stepped"]) != LOD_FRAMES:
			_failures.append("camera removed: probe %d stepped on %d of %d frames — losing the camera must return everything to full rate"
				% [i, int(after[i]["stepped"]), LOD_FRAMES])

	ahead["active"] = false
	behind["active"] = false
	Sentinel.done("coarse_tick_and_camera_views")


# ============================================================================
# CHECK 8 — SOLID, AND NEVER A CAGE (bead godot-test1-8gw.21)
# ============================================================================
#
# OWNER: "our hero can run through crowd and cars, shouldn't be so."
#
# The two halves are each other's control, and that is the point. A crowd that
# blocks is one assertion away from a crowd that CAGES — citizens walk their
# waypoints and never look where they are going, so a hero pressed into one by a
# facade would stand there forever. So this drives ONE press of `move_forward` on
# a real `player.tscn`, under real physics, against a citizen planted in the
# street ahead, and asserts BOTH:
#
#   (a) at SOLID_FRAMES the hero has walked up to the citizen and STOPPED short
#       of it — the pooled proxy is a wall;
#   (b) by ESCAPE_FRAMES the hero is PAST it — `AmbienceProxies`' pool-wide stuck
#       latch yielded and let him through.
#
# Each is mutation-tested by removing exactly the thing the other depends on: a
# pool with no bodies (the collision) must fail (a), and a latch held at zero
# every frame (the yield) must fail (b). Nothing here re-implements a metre of
# movement or of collision: the hero is the shipped controller, the wall is the
# shipped manager's own pool, placed by the shipped `_process`.

func _check_solid_and_never_trapped() -> void:
	# The bare probe body in group "player" would race the real hero for the
	# manager's `_find_player()`; from here on the real one is the only player.
	_player.remove_from_group("player")

	var floor_body := _make_floor()
	var hero: Node3D = load(PLAYER_SCENE).instantiate() as Node3D
	_root.add_child(hero)
	await physics_frame

	var probe := _pick_probe_spot()
	if probe == Vector3.INF:
		_failures.append("check 8 found no walkable street near %s to stand a citizen"
			% str(SOLID_PROBE_SPOT) + " on — the probe could not be staged")
		hero.queue_free()
		floor_body.queue_free()
		Sentinel.done("solid_and_never_trapped")
		return

	# ---- (a) A CITIZEN IS A WALL -------------------------------------------
	var start: Vector3 = await _drive_into_probe(hero, probe, SOLID_FRAMES, false)
	var gap: float = hero.global_position.z - probe.z
	if start.z - hero.global_position.z < 0.5:
		_failures.append("the hero barely moved (%.2f m in %d frames) — check 8 measured"
			% [start.z - hero.global_position.z, SOLID_FRAMES]
			+ " a wall against a hero that never walked into it, which every mutant passes")
	# Contact is ~0.80 m (capsule 0.5 + proxy half 0.3) and the real discriminator
	# is the SIGN: a hero who walked through ends up on the far side, with a
	# NEGATIVE gap and metres of it. 0.5 is that call with room for the few
	# centimetres of penetration `move_and_slide` leaves at a 10 m/s arrival.
	if gap < 0.5:
		_failures.append("the hero walked to within %.2f m of a citizen's centre (contact is"
			% gap + " ~0.8 m) — he went THROUGH a citizen, which is the bug this bead is")
	else:
		print("crowd solid: hero stopped %.2f m short of the citizen after %d frames"
			% [gap, SOLID_FRAMES])

	# ...MUTANT: the same drive with a pool that owns no bodies. This is the
	# collision and nothing else removed, and the hero must sail straight through.
	var real_pool: RefCounted = _manager.get("_proxies")
	var empty_pool: RefCounted = Proxies.new()
	empty_pool.build(_manager, 0, CrowdScript.CITIZEN_PROXY_HALF,
		CrowdScript.CITIZEN_PROXY_HEIGHT, CrowdScript.CITIZEN_PROXY_REACH)
	# ...and the real pool's bodies put to sleep first. A pool that is merely no
	# longer CONSULTED leaves its shapes standing wherever its last commit put
	# them, and the mutant would be blocked by the very collision it removed.
	real_pool.sleep()
	_manager.set("_proxies", empty_pool)
	await _drive_into_probe(hero, probe, SOLID_FRAMES, false)
	if hero.global_position.z - probe.z >= 0.5:
		_failures.append("with the proxy pool emptied the hero STILL stopped %.2f m short"
			% (hero.global_position.z - probe.z)
			+ " of the citizen — check 8(a) is measuring something other than the"
			+ " collision it claims to, so it would pass a build with no collision at all")
	_manager.set("_proxies", real_pool)

	# ---- (b) ...AND NEVER A CAGE -------------------------------------------
	await _drive_into_probe(hero, probe, ESCAPE_FRAMES, false)
	var through: float = probe.z - hero.global_position.z
	if through < 0.5:
		_failures.append("after %d frames of walking into a citizen the hero is still %.2f m"
			% [ESCAPE_FRAMES, -through] + " short of it — a solid crowd that never yields"
			+ " is an invisible wall, and a hero pinned against a facade would never get out")
	else:
		print("crowd yields: hero was %.2f m past the citizen after %d frames"
			% [through, ESCAPE_FRAMES])

	# ...MUTANT: the same drive with the pool-wide stuck latch held at zero every
	# frame — the yield and nothing else removed. Now he must never get through.
	await _drive_into_probe(hero, probe, ESCAPE_FRAMES, true)
	if probe.z - hero.global_position.z >= 0.5:
		_failures.append("with the anti-trap latch held at zero the hero got past the citizen"
			+ " anyway — check 8(b) is not measuring the yield, so a build in which a"
			+ " crowd can cage the player would pass it")

	hero.queue_free()
	floor_body.queue_free()
	await process_frame
	Sentinel.done("solid_and_never_trapped")


func _make_floor() -> StaticBody3D:
	## Something to stand on. Layer 1, which is what the player's mask 5 reads for
	## the world; the proxies live on layer 3 of that same mask.
	var body := StaticBody3D.new()
	body.name = "ProbeFloor"
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	cs.shape = box
	cs.position = Vector3(SOLID_PROBE_SPOT.x, -0.5, SOLID_PROBE_SPOT.z)
	body.add_child(cs)
	_root.add_child(body)
	return body


func _pick_probe_spot() -> Vector3:
	## A street point the crowd is willing to stand on, with PROBE_AHEAD metres of
	## walkable street behind it for the hero to start from. Asked of the SHIPPED
	## `is_walkable`, so the probe can never be staged somewhere a citizen would be
	## recycled out from under it mid-drive.
	for dx in range(-30, 31, 2):
		for dz in range(-30, 31, 2):
			var p := Vector3(SOLID_PROBE_SPOT.x + float(dx), 0.0, SOLID_PROBE_SPOT.z + float(dz))
			if CrowdScript.is_walkable(p.x, p.z) \
					and CrowdScript.is_walkable(p.x, p.z + PROBE_AHEAD) \
					and CrowdScript.is_walkable(p.x, p.z + PROBE_AHEAD + 4.0) \
					and CrowdScript.is_walkable(p.x, p.z - 4.0):
				return p
	return Vector3.INF


func _plant_probe(where: Vector3) -> void:
	## Stand citizen 0 on `where` and keep it there — a paused walker, planted
	## every frame so neither its own waypoint walk nor the recycle pass can move
	## the thing the hero is being driven into.
	var cits: Array = _manager.get("_citizens")
	var c: Dictionary = cits[0]
	c["pos"] = where
	c["target"] = where
	c["lane_offset"] = 0.0
	c["heading_dir"] = Vector2(0.0, 1.0)
	c["facing_yaw"] = 0.0
	c["pause_timer"] = 10.0
	c["speed"] = 0.0
	c["active"] = true
	c["lod_debt"] = 0.0


func _drive_into_probe(hero: Node3D, probe: Vector3, frames: int,
		kill_latch: bool) -> Vector3:
	## Stand the hero PROBE_AHEAD behind the probe and hold `move_forward` for
	## `frames` physics frames. Returns where he started.
	##
	## `player.tscn`'s root has an identity basis and `get_input_direction()`
	## answers (0, -1) for move_forward, so "forward" is world -Z: the probe is
	## planted at -Z of the start and the hero walks straight at it.
	hero.global_position = Vector3(probe.x, 0.05, probe.z + PROBE_AHEAD)
	# FACE -Z. `player.tscn`'s controller turns the body to face down the road on
	# `_ready`, so "forward" is not -Z until it is told to be — and a probe that
	# assumed it walked the hero off at right angles to the thing it was measuring.
	hero.rotation = Vector3.ZERO
	hero.velocity = Vector3.ZERO
	var start: Vector3 = hero.global_position
	Input.action_press("move_forward", 1.0)
	for _i in frames:
		_plant_probe(probe)
		if kill_latch:
			# The yield removed, and only the yield: the pool's contact window can
			# never reach AmbienceProxies.STUCK_SECONDS, so nothing ever softens.
			var pool: RefCounted = _manager.get("_proxies")
			pool.set("_watch_time", 0.0)
			pool.set("_soft", 0.0)
		_manager._process(DT)
		await physics_frame
	Input.action_release("move_forward")
	return start


# ============================================================================
# CHECK 9 — NO GAMEPLAY GROUP GAINED A MEMBER
# ============================================================================
#
# The pool is the first physics body this manager has ever owned, so the thing
# to prove is that it changed nothing about the game. Two independent readings,
# because either alone is weak: the LAYER ARITHMETIC (a predator's own shipped
# mask, read off `piglet_crocodile.tscn` rather than written down here, cannot
# see the proxy layer — which is what makes a proxy invisible to a chase, to the
# LOD manager's sweep and to the hunt director), and the SHIPPED STINK WAVE
# driven with a live crowd in the tree, which must scatter the crocodile and
# nothing else. Check 1 already forbids any group membership under the manager;
# this is the behavioural half of the same claim.

func _check_no_gameplay_group_gained_a_member() -> void:
	var croc_scene: PackedScene = load("res://scenes/characters/piglet_crocodile.tscn")
	var croc: Node3D = croc_scene.instantiate() as Node3D
	var croc_mask: int = (croc as CollisionObject3D).collision_mask
	if (croc_mask & Proxies.PROXY_LAYER) != 0:
		_failures.append("the shipped crocodile masks %d, which INCLUDES the proxy layer %d"
			% [croc_mask, Proxies.PROXY_LAYER] + " — every predator in the game would"
			+ " start bumping into pedestrians, and the fauna precedent this layer"
			+ " choice copies is broken")
	croc.free()

	# A live crowd, then the shipped fear sweep. Group discovery is the whole
	# mechanism, so if a proxy — or a citizen — had joined "crocodile" it would be
	# scattered here and counted.
	_player.add_to_group("player")
	_player.position = Vector3(2900.0, 1.0, 0.0)
	for _i in 90:
		_manager._process(DT)
	var active: int = 0
	for c: Dictionary in _manager.get("_citizens"):
		if c["active"]:
			active += 1
	if active <= 0:
		_failures.append("check 9 ran its Stink Wave probe over an EMPTY crowd — it would"
			+ " pass with the crowd in every gameplay group there is")

	var hero: Node3D = load(PLAYER_SCENE).instantiate() as Node3D
	_root.add_child(hero)
	hero.global_position = Vector3(2900.0, 0.05, 0.0)
	var real_croc: Node3D = croc_scene.instantiate() as Node3D
	_root.add_child(real_croc)
	real_croc.global_position = Vector3(2903.0, 0.0, 0.0)
	await physics_frame

	hero.call("_scare_crocodiles", hero.global_position, 3.0, 30.0)
	if not bool(real_croc.get("is_fleeing")):
		_failures.append("the shipped Stink Wave did not scatter a crocodile 3 m away —"
			+ " check 9's positive control is dead, so 'it scattered nothing of the"
			+ " crowd's' means nothing")
	for n: Node in get_nodes_in_group("crocodile"):
		if _manager.is_ancestor_of(n):
			_failures.append("'%s' is a descendant of the CrowdManager AND in group"
				% n.name + " 'crocodile' — a pedestrian the Stink Wave scatters, a hunter"
				+ " chases and the LOD manager sleeps")
	for g: String in ["player", "crocodile", "enemy", "boss", "coin", "landmark", "fauna"]:
		for n: Node in get_nodes_in_group(g):
			if _manager.is_ancestor_of(n):
				_failures.append("'%s' is under the CrowdManager and in gameplay group '%s'"
					% [n.name, g])
	print("crowd isolation: %d citizens live, crocodile mask %d never sees proxy layer %d"
		% [active, croc_mask, Proxies.PROXY_LAYER])

	real_croc.queue_free()
	hero.queue_free()
	await process_frame
	Sentinel.done("no_gameplay_group_gained_a_member")
