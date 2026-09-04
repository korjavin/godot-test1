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
##      SHIPPED movement is (a) stopped by a citizen, (b) through it within a
##      beat and (c) never SHOVED by one planted on top of him — the crowd's end
##      of the 3-D no-shove guard bead godot-test1-d5f made 3-D, at a citizen's
##      own height rather than a car's — each mutation-tested against the
##      absence of exactly the rule it names.
##   9. NO GAMEPLAY GROUP GAINED A MEMBER: the proxy layer is invisible to the
##      shipped crocodile's own mask, and the shipped Stink Wave sweep touches the
##      crocodiles and nothing of the crowd's with a live crowd in the tree.
##  10. THE SPAWN IS SPREAD (bead 8gw.23): the whole bubble filled from cold —
##      what the player sees WALKING IN THE GATE, when every citizen comes off
##      the sampler in one pass — is uniform over the streets rather than piled
##      around the hero, measured as the share landing in the inner QUARTER OF
##      THE AREA and as the number of 62 m cells used. The OLD sampler, written
##      out here, is the mutation control and must go RED on the same numbers.
##  11. CITIZENS AND CARS SEE EACH OTHER (bead 8gw.23), three ways: a walker
##      following an AVENUE is put on the pavement rather than in the traffic
##      (with an ordinary street as the control); a citizen crossing in front of
##      a moving car is never inside the car's footprint, mutation-tested by
##      taking the crowd out of its group — the car must then drive over it; and
##      a citizen at the KERB waits, measured against the same walk on an empty
##      road.
##  13. NOBODY WALKS ON THE DANUBE (bead 8gw.23): a live bubble at each of the
##      four bridges, every RENDERED walker position asked of the shipped
##      `is_walkable`. A lane is up to 8.6 m to the SIDE of the street line and
##      a bridge deck's DRY rect covers the centreline but not the lane, so a
##      base-only test walked citizens out over the water; non-vacuity is the
##      count of walkers that came within reach of the band.
##  12. A WALKER NEVER TELEPORTS MID-BLOCK (bead 8gw.23): over 2,000 driven
##      steps, no citizen that did not TURN moves further in one frame than its
##      own top speed allows — which is how a lane re-drawn on a straight step
##      shows up (a sign flip is 17.2 m sideways on an avenue) — a turn is
##      bounded by the lane geometry instead of forbidden (read the check's
##      header for why the corner is a known discontinuity), and the spawn
##      clearance is measured on the positions walkers really stand at.
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
const PLAN := preload("res://scripts/budapest_plan.gd")
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

## THE NO-SHOVE WINDOW (bead godot-test1-d5f). How long a citizen is held ON the
## hero, and how far he may be moved by it. `traffic_selfcheck`'s check 18(c) is
## the same probe at a car's height; this one is the CROWD's, because the guard
## it drives is now 3-D and a citizen is 1.75 m tall where a car is 1.15.
const ON_TOP_FRAMES: int = 40
const ON_TOP_MAX_MOVE: float = 0.5

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
	Sentinel.isolate_user_state()
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
	_check_spawn_distribution()
	_check_pavement_lane()
	await _check_car_never_drives_through_a_citizen()
	_check_walkers_never_teleport()
	_check_no_walker_on_water()

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

	# ---- (c) ...AND NEVER A SHOVE, AT A CITIZEN'S OWN HEIGHT ---------------
	# `AmbienceProxies._player_inside()` became 3-D in bead godot-test1-d5f so a
	# hero could stand on a car ROOF, and the vertical half is measured against
	# the pool's own height — which is 1.75 m here and 1.15 m over in the
	# traffic. A grace tuned for one and not the other would leave a citizen
	# teleported onto the hero (Phase Step, a respawn, the HQ setback) solid, and
	# `move_and_slide` resolves that overlap by throwing him out of it. So the
	# crowd asserts its own end of the shared rule: a citizen planted ON him for
	# ON_TOP_FRAMES moves him nowhere.
	var stood: Vector3 = Vector3(probe.x, 0.05, probe.z)
	var moved: float = await _hold_citizen_on_hero(hero, stood, ON_TOP_FRAMES)
	if moved > ON_TOP_MAX_MOVE:
		_failures.append("a citizen planted ON the hero threw him %.2f m — a proxy over the"
			% moved + " hero's own body must not be solid, or every teleport that lands him"
			+ " in a crowd is a launch")
	else:
		print("crowd no-shove: a citizen planted on the hero moved him %.3f m" % moved)

	# ...MUTANT: the guard removed and nothing else. A pool whose roof is at y = 0
	# finds the hero's feet ABOVE it, decides he is standing ON the citizen and
	# leaves it solid on him — which is this guard switched off for exactly this
	# pose, so he must now be thrown. (`traffic_selfcheck`'s roof mutant moves the
	# same `_height` the other way, out of reach, because there it is the roof
	# rather than the guard that has to stop existing.)
	var real_h: float = float(_manager.get("_proxies").get("_height"))
	_manager.get("_proxies").set("_height", 0.0)
	var mutant_moved: float = await _hold_citizen_on_hero(hero, stood, ON_TOP_FRAMES)
	_manager.get("_proxies").set("_height", real_h)
	if mutant_moved <= ON_TOP_MAX_MOVE:
		_failures.append("with the pool's height zeroed — the no-shove guard removed — a"
			+ " citizen planted on the hero STILL moved him only %.2f m, so check 8(c) is"
			% mutant_moved + " measuring something other than the guard it names")

	hero.queue_free()
	floor_body.queue_free()
	await process_frame
	Sentinel.done("solid_and_never_trapped")


func _hold_citizen_on_hero(hero: Node3D, where: Vector3, frames: int) -> float:
	## Stand the hero on `where` and plant a citizen on exactly the same spot for
	## `frames` frames, through the shipped `_process`. Returns how far he moved.
	##
	## THE ANTI-TRAP LATCH IS CLEARED FIRST, and without this the (c) pair is a
	## coin toss. A hero standing still IS a hero making no headway, so the pool's
	## contact window softens the WHOLE pool a beat into either hold — and the
	## mutant, which runs second, then inherits a pool that is already yielding
	## and can never be solid on anybody, whatever its height is. It reported
	## "moved him 0.00 m" and blamed the guard. Both holds therefore start from
	## the same cleared latch, which is `_drive_into_probe`'s own kill switch used
	## the other way round: there it is held at zero to REMOVE the yield, here it
	## is zeroed once so neither hold begins inside somebody else's.
	var pool: RefCounted = _manager.get("_proxies")
	pool.set("_watching", false)
	pool.set("_watch_time", 0.0)
	pool.set("_soft", 0.0)
	hero.global_position = where
	hero.rotation = Vector3.ZERO
	hero.velocity = Vector3.ZERO
	await physics_frame
	var from: Vector3 = hero.global_position
	for _i in frames:
		_plant_probe(Vector3(where.x, 0.0, where.z))
		_manager._process(DT)
		await physics_frame
	return hero.global_position.distance_to(from)


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


# ============================================================================
# CHECK 10 — THE SPAWN IS SPREAD (bead godot-test1-8gw.23)
# ============================================================================
#
# OWNER: "let's spread crowds in budapest more uniform, why they are all in one
# space".
#
# WHERE THE CLUSTER IS VISIBLE. In steady state the walk itself diffuses the
# crowd, so a sampler bias is nearly invisible a minute in — which is exactly why
# this is measured on the bubble filled FROM COLD, the state the player is
# handed when he walks in the gate, when he re-enters the city, and on every F2.
# All 120 come off the sampler in one pass there.
#
# THE METRIC IS RADIAL, and deliberately not a cell histogram: a 62 m cell grid
# is drawn on the street LINES the citizens stand on, so which side of a boundary
# a walker falls on is arbitrary and the peak cell count is mostly noise. The
# share landing inside HALF the bubble radius is not: that circle is a QUARTER of
# the bubble's area, so a sampler uniform over the streets puts ~25% of the crowd
# in it and no argument about tiling can move the number.
#
# The old sampler drew its radius UNIFORMLY IN r — which over-weights the middle
# of a disc by 1/r — and fell back to the player's OWN intersection after 16
# failed draws. Measured over 1,200 arrivals at four city spots: 42 / 32 / 37 /
# 29% inside that circle against a uniform 25%. It is written out below as the
# mutation control and must fail this check's own bound.

## Four city spots, and the bubble filled from cold ten times at each.
const DIST_SPOTS: Array[Vector3] = [
	Vector3(2400.0, 0.0, 0.0),
	Vector3(2600.0, 0.0, 400.0),
	Vector3(3000.0, 0.0, -500.0),
	Vector3(2900.0, 0.0, 800.0),
]
const DIST_ARRIVALS: int = 10

## The bound, on the share inside SPAWN_RADIUS / 2 — a quarter of the bubble's
## area, so uniform is 25%. Shipped measures 17-23%, the old sampler 29-42%;
## 28% sits between the two with room on both sides.
const DIST_INNER_SHARE_MAX: float = 28.0

## ...and a floor on the SPREAD, so a sampler that collapsed onto one street
## still fails even if it collapsed at the right radius. The bubble is 220 m
## across on a 62 m grid, so a dozen cells is most of what there is.
const DIST_MIN_CELLS: int = 8


func _dist_profile(spot: Vector3, use_old: bool) -> Dictionary:
	## Fill the bubble from cold `DIST_ARRIVALS` times and report the share of
	## walkers inside half the spawn radius plus the 62 m cells they used.
	var pitch: float = PLAN.STREET_PITCH
	var half_r: float = CrowdScript.SPAWN_RADIUS * 0.5
	var cells := {}
	var inner: int = 0
	var total: int = 0
	_player.position = spot
	for _rep in DIST_ARRIVALS:
		_manager._hide_all()
		var points: Array[Vector3] = []
		if use_old:
			for _i in _manager.get("_citizens").size():
				var p := _old_sampler_point(spot)
				if p != Vector3.INF:
					points.append(p)
		else:
			_manager._process(DT)
			for c: Dictionary in _manager.get("_citizens"):
				if c["active"]:
					points.append(CrowdScript._citizen_world_pos(c))
		for w: Vector3 in points:
			total += 1
			if Vector2(w.x - spot.x, w.z - spot.z).length() < half_r:
				inner += 1
			cells[Vector2i(int(floor((w.x - PLAN.GATE.x) / pitch)),
					int(floor(w.z / pitch)))] = true
	return {
		"n": total,
		"inner_share": 100.0 * float(inner) / maxf(1.0, float(total)),
		"cells": cells.size(),
	}


func _old_sampler_point(player_pos: Vector3) -> Vector3:
	## THE MUTATION CONTROL: `_find_spawn_segment_near` as it stood before bead
	## 8gw.23, written out here so "the fix moved the number" is a comparison of
	## two live samplers and not of a number against a memory. Uniform in r, snap
	## to the nearest INTERSECTION, then lerp along one edge — and on 16 failures
	## fall back to the player's own intersection, which is the pile-up.
	var rng := _manager.get("_rng") as RandomNumberGenerator
	for _attempt in 16:
		var angle := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(CrowdScript.SPAWN_MIN_DIST, CrowdScript.SPAWN_RADIUS)
		var snapped: Vector2 = CrowdScript.snap_to_grid(player_pos.x + cos(angle) * dist,
				player_pos.z + sin(angle) * dist)
		if CrowdScript.is_walkable(snapped.x, snapped.y):
			var corner := Vector3(snapped.x, 0.0, snapped.y)
			var d := Vector2(1.0 if rng.randf() < 0.5 else -1.0, 0.0)
			if rng.randf() < 0.5:
				d = Vector2(0.0, 1.0 if rng.randf() < 0.5 else -1.0)
			var nxt: Vector3 = _manager._pick_next_waypoint(corner, d)
			if nxt != corner:
				return corner.lerp(nxt, rng.randf_range(0.05, 0.95))
	var p: Vector2 = CrowdScript.snap_to_grid(player_pos.x, player_pos.z)
	if CrowdScript.is_walkable(p.x, p.y):
		var c := Vector3(p.x, 0.0, p.y)
		var n: Vector3 = _manager._pick_next_waypoint(c, Vector2(1.0, 0.0))
		if n != c:
			return c.lerp(n, rng.randf_range(0.05, 0.95))
	return Vector3.INF


func _check_spawn_distribution() -> void:
	var shipped_inner: float = 0.0
	var control_inner: float = 0.0
	var spots: int = 0
	for spot: Vector3 in DIST_SPOTS:
		var got: Dictionary = _dist_profile(spot, false)
		var old: Dictionary = _dist_profile(spot, true)
		if int(got["n"]) < 500:
			_failures.append("check 10 got only %d spawns at %s — too few to mean anything"
				% [int(got["n"]), str(spot)])
			Sentinel.done("spawn_distribution")
			return
		if float(got["inner_share"]) > DIST_INNER_SHARE_MAX:
			_failures.append(("at %s, %.1f%% of the crowd spawned inside HALF the bubble"
				+ " radius — a quarter of its area, so uniform is 25%% and the bound is"
				+ " %.0f%%. The crowd is piling up around the hero again; see"
				+ " _find_spawn_segment_near.")
				% [str(spot), float(got["inner_share"]), DIST_INNER_SHARE_MAX])
		if int(got["cells"]) < DIST_MIN_CELLS:
			_failures.append("at %s the whole crowd fitted in %d 62 m cells (floor %d) —"
				% [str(spot), int(got["cells"]), DIST_MIN_CELLS]
				+ " it collapsed onto a handful of streets")
		shipped_inner += float(got["inner_share"])
		control_inner += float(old["inner_share"])
		spots += 1
		print("spawn spread at %s: %.1f%% inner / %d cells (old sampler: %.1f%% / %d)"
			% [str(spot), float(got["inner_share"]), int(got["cells"]),
			float(old["inner_share"]), int(old["cells"])])

	# THE MUTATION CONTROL, run for real rather than asserted: the retired sampler
	# has to FAIL the bound this check holds the shipped one to, or the bound is
	# loose enough to pass anything.
	var control_avg: float = control_inner / maxf(1.0, float(spots))
	var shipped_avg: float = shipped_inner / maxf(1.0, float(spots))
	if control_avg <= DIST_INNER_SHARE_MAX:
		_failures.append(("check 10's mutation control PASSED: the pre-8gw.23 sampler"
			+ " averaged %.1f%% inside the inner quarter-area, under the %.0f%% bound."
			+ " The bound cannot tell the two samplers apart, so it is measuring nothing.")
			% [control_avg, DIST_INNER_SHARE_MAX])
	print("spawn spread: shipped %.1f%% vs retired sampler %.1f%% inside the inner"
		% [shipped_avg, control_avg] + " quarter-area (uniform 25%%, bound %.0f%%)"
		% DIST_INNER_SHARE_MAX)
	_manager._hide_all()
	Sentinel.done("spawn_distribution")


# ============================================================================
# CHECK 11 — A CAR NEVER DRIVES THROUGH A CITIZEN (bead godot-test1-8gw.23)
# ============================================================================
#
# OWNER: "crowds in budapest still go through cars, not good, fix".
#
# Neither a citizen nor a car has a body — the pooled proxies exist only for the
# hero — so nothing physical was ever going to stop this, and the fix is the
# SHIPPED brake: `traffic_manager._distance_to_citizen_ahead` feeds a citizen on
# the carriageway into `target_speed_for_distance` exactly as it feeds the hero.
#
# The probe is a citizen already MID-CROSSING (the kerb rule deliberately lets it
# carry on; stopping somebody in the road is the one place to be run over) with a
# car bearing down on it. Driven on the two shipped movement passes, and
# mutation-tested by taking the crowd out of the group — the seam is discovered
# through it, so an unfixed build is exactly what that run measures, and the car
# must then drive straight over the walker.

const TrafficScript := preload("res://scripts/traffic_manager.gd")

## Long enough for a car starting 25 m back at cruise (4–6.5 m/s) to reach and
## pass the crossing point, twice over.
const CAR_PROBE_FRAMES: int = 300

## The car's footprint plus the citizen's half-width — "inside the car" for a
## walker whose own box is CITIZEN_PROXY_HALF.
const CAR_HIT_LONG: float = TrafficScript.CAR_LENGTH * 0.5 + 0.3
const CAR_HIT_LAT: float = TrafficScript.CAR_WIDTH * 0.5 + 0.3

## The kerb probe's own window: the walk is 17 m at 2.4 m/s (7.1 s) plus the wait
## for a car to clear, so 700 frames is that with room either side.
const KERB_PROBE_FRAMES: int = 700


func _car_probe_min_gap(traffic: Node3D, crowd: Node3D) -> float:
	## Drive one car east down an avenue at one citizen crossing it, and report
	## the closest the citizen ever came to being INSIDE the car — as a fraction
	## of the footprint, so < 1.0 means it was driven through.
	var cars: Array = traffic.get("_cars")
	var citizens: Array = crowd.get("_citizens")
	traffic._hide_all()
	crowd._hide_all()

	# The z = 0 avenue (CITY_AVENUE_EVERY-th grid line through the gate), a car
	# in the +X lane, and a citizen on an ORDINARY street line crossing it.
	var cross_x: float = PLAN.GATE.x + 13.0 * PLAN.STREET_PITCH  # not a multiple of 4
	var car: Dictionary = cars[0]
	car["pos"] = Vector3(cross_x - 25.0, 0.0, 0.0)
	car["heading_dir"] = Vector2(1.0, 0.0)
	car["facing_yaw"] = atan2(-1.0, 0.0)
	car["cruise_speed"] = 6.0
	car["speed"] = 6.0
	car["blocked_time"] = 0.0
	car["honk_cooldown"] = 0.0
	car["lod_step"] = DT
	car["active"] = true

	var walker: Dictionary = citizens[0]
	# Already ON the carriageway (|z| < AVENUE_HALF_WIDTH), and placed so that at
	# 1.2 m/s it stands in the car's own lane (z = +LANE_OFFSET) at the moment a
	# car 25 m back at 6 m/s arrives — the collision is dead centre, not a near miss.
	walker["pos"] = Vector3(cross_x, 0.0, TrafficScript.LANE_OFFSET - 1.2 * (25.0 / 6.0))
	walker["target"] = Vector3(cross_x, 0.0, 12.0)
	walker["heading_dir"] = Vector2(0.0, 1.0)
	walker["facing_yaw"] = 0.0
	walker["lane_offset"] = 0.0
	walker["speed"] = 1.2
	walker["pause_timer"] = 0.0
	walker["walk_phase"] = 0.0
	walker["lod_step"] = DT
	walker["active"] = true

	var worst := INF
	var far_away := Vector3(0.0, 0.0, 9000.0)  # the hero is nowhere near this
	for _f in CAR_PROBE_FRAMES:
		traffic._update_cars(DT, far_away, false)
		crowd._update_walkers(DT, false)
		var cw: Vector3 = TrafficScript._car_world_pos(car)
		var pw: Vector3 = CrowdScript._citizen_world_pos(walker)
		var d := Vector2(pw.x - cw.x, pw.z - cw.z)
		var h: Vector2 = car["heading_dir"]
		var along: float = absf(d.dot(h)) / CAR_HIT_LONG
		var across: float = absf(d.dot(Vector2(-h.y, h.x))) / CAR_HIT_LAT
		worst = minf(worst, maxf(along, across))
	return worst


func _kerb_probe(traffic: Node3D, crowd: Node3D, with_car: bool) -> int:
	## THE KERB RULE's own measurement: a citizen starting on the PAVEMENT and
	## walking across the avenue. Returns the frame it clears the far kerb — with
	## a car coming that must be LATER, because it waited.
	var cars: Array = traffic.get("_cars")
	var citizens: Array = crowd.get("_citizens")
	traffic._hide_all()
	crowd._hide_all()
	var cross_x: float = PLAN.GATE.x + 13.0 * PLAN.STREET_PITCH
	var kerb: float = PLAN.AVENUE_HALF_WIDTH

	if with_car:
		var car: Dictionary = cars[0]
		# 15 m back at 6 m/s: it is inside YIELD_DISTANCE of the crossing point at
		# the moment the walker reaches the kerb, which is what has to hold it.
		car["pos"] = Vector3(cross_x - 15.0, 0.0, 0.0)
		car["heading_dir"] = Vector2(1.0, 0.0)
		car["facing_yaw"] = atan2(-1.0, 0.0)
		car["cruise_speed"] = 6.0
		car["speed"] = 6.0
		car["blocked_time"] = 0.0
		car["honk_cooldown"] = 0.0
		car["lod_step"] = DT
		car["active"] = true

	var walker: Dictionary = citizens[0]
	walker["pos"] = Vector3(cross_x, 0.0, -kerb - 1.0)  # on the pavement, not the road
	walker["target"] = Vector3(cross_x, 0.0, kerb + 12.0)
	walker["heading_dir"] = Vector2(0.0, 1.0)
	walker["facing_yaw"] = 0.0
	walker["lane_offset"] = 0.0
	walker["speed"] = 2.4
	walker["pause_timer"] = 0.0
	walker["walk_phase"] = 0.0
	walker["lod_step"] = DT
	walker["active"] = true

	var far_away := Vector3(0.0, 0.0, 9000.0)
	for f in KERB_PROBE_FRAMES:
		if with_car:
			traffic._update_cars(DT, far_away, false)
		crowd._update_walkers(DT, false)
		if float((walker["pos"] as Vector3).z) >= kerb:
			return f
	return KERB_PROBE_FRAMES


func _check_pavement_lane() -> void:
	## THE HALF THE CAR PROBE CANNOT SEE: a citizen walking ALONG an avenue is on
	## the PAVEMENT, so the cars never have to brake for it in the first place.
	## `_pick_lane` is asked directly, at an avenue line and at an ordinary street
	## line, because the difference between the two answers IS the rule.
	var ave_pitch: float = PLAN.STREET_PITCH * float(PLAN.CITY_AVENUE_EVERY)
	# An avenue of constant Z through the middle of Pest, walked along X.
	var on_avenue := Vector3(PLAN.GATE.x + 5.0 * PLAN.STREET_PITCH, 0.0, 4.0 * ave_pitch)
	# ...and an ordinary street line one pitch off it, walked the same way.
	var on_street := Vector3(on_avenue.x, 0.0, on_avenue.z + PLAN.STREET_PITCH)
	var along := Vector2(1.0, 0.0)

	if not CrowdScript.walks_an_avenue(on_avenue, along):
		_failures.append("check 11's avenue probe at %s is not on an avenue line —"
			% str(on_avenue) + " it measures nothing")
		Sentinel.done("pavement_lane")
		return
	if CrowdScript.walks_an_avenue(on_street, along):
		_failures.append("check 11's control line at %s IS an avenue — the two probes"
			% str(on_street) + " cannot tell the rule from the default")
		Sentinel.done("pavement_lane")
		return

	# Twenty draws each: the lane is a random pick, so one sample proves nothing.
	for _i in 20:
		var ave_lane: float = absf(_manager._pick_lane(on_avenue, along, on_avenue + Vector3(PLAN.STREET_PITCH, 0.0, 0.0)))
		if ave_lane <= PLAN.AVENUE_HALF_WIDTH:
			_failures.append(("a citizen walking ALONG an avenue was put %.1f m off the"
				+ " centreline, inside the %.1f m carriageway — it is standing in the"
				+ " traffic, which is most of what 'crowds go through cars' was.")
				% [ave_lane, PLAN.AVENUE_HALF_WIDTH])
			break
		if ave_lane >= PLAN.AVENUE_HALF_WIDTH + PLAN.BLOCK_PAVEMENT:
			_failures.append(("a citizen walking ALONG an avenue was put %.1f m off the"
				+ " centreline, at or past the block face at %.1f m — it is inside a"
				+ " building.") % [ave_lane, PLAN.AVENUE_HALF_WIDTH + PLAN.BLOCK_PAVEMENT])
			break
	for _i in 20:
		var street_lane: float = absf(_manager._pick_lane(on_street, along, on_street + Vector3(PLAN.STREET_PITCH, 0.0, 0.0)))
		if street_lane > PLAN.AVENUE_HALF_WIDTH:
			_failures.append(("an ordinary street put a walker %.1f m off the centreline —"
				+ " the pavement lane is for AVENUES, and a 62 m street has no traffic to"
				+ " keep clear of.") % street_lane)
			break
	# THE GATE AVENUE, which is the city's own western EDGE: BudapestPlan puts
	# BUDAPEST_MIN.x exactly on GATE.x, so for a north/south walker there the
	# WESTERN pavement is outside the rect and unwalkable. A `_pick_lane` that
	# gave up on its first draw fell through to 0.0 half the time — the middle of
	# the busiest road in the city, at the one place every player walks in.
	var gate_ns := Vector3(PLAN.GATE.x, 0.0, 3.0 * ave_pitch)
	var north := Vector2(0.0, 1.0)
	if not CrowdScript.walks_an_avenue(gate_ns, north):
		_failures.append("check 11's gate probe at %s is not on an avenue" % str(gate_ns))
	elif CrowdScript.is_walkable(gate_ns.x - CrowdScript.PAVEMENT_LANE_OFFSET, gate_ns.z):
		_failures.append("check 11's gate probe has a walkable WEST pavement, so it is not"
			+ " standing on the city edge the mirror rule exists for")
	else:
		for _i in 20:
			var gate_lane: float = absf(_manager._pick_lane(gate_ns, north, gate_ns + Vector3(0.0, 0.0, PLAN.STREET_PITCH)))
			if gate_lane <= PLAN.AVENUE_HALF_WIDTH:
				_failures.append(("on the GATE avenue — the city's own west edge, where one"
					+ " pavement is outside the rect — a walker was put %.1f m off the"
					+ " centreline, inside the %.1f m carriageway. _pick_lane must try the"
					+ " other pavement before it gives up.")
					% [gate_lane, PLAN.AVENUE_HALF_WIDTH])
				break
	print("pavement lane: avenue walkers at +/-%.1f m (carriageway %.1f, block face %.1f),"
		% [CrowdScript.PAVEMENT_LANE_OFFSET, PLAN.AVENUE_HALF_WIDTH,
		PLAN.AVENUE_HALF_WIDTH + PLAN.BLOCK_PAVEMENT]
		+ " gate avenue mirrored to the east pavement")
	Sentinel.done("pavement_lane")


func _check_car_never_drives_through_a_citizen() -> void:
	var traffic := Node3D.new()
	traffic.set_script(TrafficScript)
	_root.add_child(traffic)
	await process_frame

	var with_crowd: float = _car_probe_min_gap(traffic, _manager)
	if with_crowd < 1.0:
		_failures.append(("a car drove THROUGH a crossing citizen — it reached %.2f of its"
			+ " own footprint (1.0 is the bumper). traffic_manager brakes for the hero and"
			+ " for cars ahead; a citizen on the carriageway has to be the same blocker,"
			+ " through _distance_to_citizen_ahead.") % with_crowd)

	# THE MUTATION CONTROL: the seam is group discovery, so a crowd out of the
	# group IS the pre-8gw.23 build. The car must run the walker over.
	_manager.remove_from_group("crowd")
	var without: float = _car_probe_min_gap(traffic, _manager)
	_manager.add_to_group("crowd")
	if without >= 1.0:
		_failures.append(("check 11's mutation control PASSED: with the crowd out of the"
			+ " 'crowd' group the car still missed the citizen (%.2f of a footprint), so"
			+ " the probe never put anybody in front of a car and proves nothing.")
			% without)
	print("car vs citizen: closest approach %.2f of a car footprint with the brake,"
		% with_crowd + " %.2f with the crowd unreachable" % without)

	# THE KERB RULE, the citizen's own half: it waits on the pavement rather than
	# stepping in front of a car. Its control is the same walk with no car at all
	# — the crossing must be strictly slower with one coming, or the hold never
	# fired and `blocks_crossing` is decorative.
	var waited: int = _kerb_probe(traffic, _manager, true)
	var clear: int = _kerb_probe(traffic, _manager, false)
	if waited <= clear:
		_failures.append(("a citizen stepped off the kerb in front of a car: it cleared the"
			+ " avenue on frame %d with a car bearing down and frame %d with an empty road,"
			+ " so it never waited. traffic_manager.blocks_crossing is the hold.")
			% [waited, clear])
	else:
		print("kerb rule: crossing took %d frames with a car coming, %d on an empty road"
			% [waited, clear])

	# A PARALLEL AVENUE IS NOT A CROSSING. Both lines are infinite, so a car on
	# the z = 248 avenue still "crosses" a northbound walker's line — 248 m up it.
	# Without the travel bound that car holds a citizen stepping onto z = 0.
	traffic._hide_all()
	var far_car: Dictionary = (traffic.get("_cars") as Array)[0]
	var step_x: float = PLAN.GATE.x + 13.0 * PLAN.STREET_PITCH
	var ave_pitch: float = PLAN.STREET_PITCH * float(PLAN.CITY_AVENUE_EVERY)
	far_car["pos"] = Vector3(step_x - 5.0, 0.0, ave_pitch)
	far_car["heading_dir"] = Vector2(1.0, 0.0)
	far_car["facing_yaw"] = 0.0
	far_car["speed"] = 6.0
	far_car["cruise_speed"] = 6.0
	far_car["active"] = true
	# The same step the kerb probe makes, onto the z = 0 avenue.
	var kerb_from := Vector3(step_x, 0.0, -PLAN.AVENUE_HALF_WIDTH - 0.1)
	var kerb_to := Vector3(step_x, 0.0, -PLAN.AVENUE_HALF_WIDTH + 0.1)
	if traffic.blocks_crossing(kerb_from, kerb_to, Vector2(0.0, 1.0)):
		_failures.append(("a citizen stepping onto the z = 0 avenue was held by a car on the"
			+ " PARALLEL avenue %.0f m away — blocks_crossing projected onto the walker's"
			+ " INFINITE line and found a crossing nobody is about to make.") % ave_pitch)
	# ...and the positive control: the same car moved onto the avenue being
	# entered must still hold it, or the bound rejected everything.
	far_car["pos"] = Vector3(step_x - 5.0, 0.0, 0.0)
	if not traffic.blocks_crossing(kerb_from, kerb_to, Vector2(0.0, 1.0)):
		_failures.append("with the car on the avenue actually being crossed the kerb rule"
			+ " did NOT hold — the travel bound is rejecting real crossings too")
	else:
		print("kerb rule: a car on the parallel avenue %.0f m away holds nobody;" % ave_pitch
			+ " the same car on the crossed avenue does")

	# A STOPPED CAR STRADDLING THE CROSSING still blocks it. `fwd <= 0` released the
	# walker the moment the car's CENTRE passed, while 2.2 m of body was still
	# across the lane — and a car stopped by the hero ahead straddles it for as
	# long as the hero stands there, so the walker steps into a stationary car
	# that, looking only forward, never sees it.
	traffic._hide_all()
	var stalled: Dictionary = (traffic.get("_cars") as Array)[0]
	stalled["pos"] = Vector3(step_x + 1.0, 0.0, 0.0)   # centre 1 m PAST the crossing
	stalled["heading_dir"] = Vector2(1.0, 0.0)
	stalled["facing_yaw"] = 0.0
	stalled["speed"] = 0.0
	stalled["cruise_speed"] = 0.0
	stalled["active"] = true
	if not traffic.blocks_crossing(kerb_from, kerb_to, Vector2(0.0, 1.0)):
		_failures.append(("a citizen was released onto the crossing with a STOPPED car"
			+ " straddling it — its centre is 1.0 m past, but %.1f m of car is still"
			+ " across the lane. blocks_crossing must use the car's BODY, not its centre.")
			% (TrafficScript.CAR_LENGTH * 0.5))
	# ...and the control: the same car a whole body-length further on, genuinely
	# clear, must release. Without this the fix could just be "always blocked".
	stalled["pos"] = Vector3(step_x + TrafficScript.CROSSING_REAR_CLEAR + 1.0, 0.0, 0.0)
	if traffic.blocks_crossing(kerb_from, kerb_to, Vector2(0.0, 1.0)):
		_failures.append("a car entirely PAST the crossing still held the walker — the rear"
			+ " clearance is not releasing, so a citizen waits for cars that have gone")
	else:
		print("kerb rule: a car straddling the crossing holds; the same car %.1f m past"
			% (TrafficScript.CROSSING_REAR_CLEAR + 1.0) + " releases")

	traffic._hide_all()
	traffic.queue_free()
	_manager._hide_all()
	await process_frame
	Sentinel.done("car_never_drives_through_a_citizen")


# ============================================================================
# CHECK 12 — A WALKER NEVER TELEPORTS MID-BLOCK, AND NEVER SPAWNS ON ANOTHER
# ============================================================================
#
# TWO THINGS A LANE CAN DO WRONG, and neither is visible to any check above.
#
# (a) The lane is drawn at a TURN, and `_pick_next_waypoint` carries straight on
#     60% of the time. Re-drawing on those steps flips the SIGN half of them,
#     which on an avenue is +8.6 m to -8.6 m — a 17.2 m sideways jump across both
#     car lanes, in one frame, for a citizen that never turned (6.4 m on an
#     ordinary street). The proxy pool follows the citizen, so it is a collider
#     jumping through the hero too.
#
#     THE MEASUREMENT IS PER-FRAME WORLD DISPLACEMENT, and SINCE BEAD 8gw.24 a
#     TURN IS HELD TO THE SAME BOUND AS ANY OTHER STEP. A lane is an offset
#     along the heading's PERPENDICULAR, so a 90° turn rotates it: leaving the
#     value alone, a walker at +8.6 m on a street of constant Z was at -8.6 m
#     along X the instant it turned, `sqrt(2) * lane` = 12.2 m away, in one
#     frame. `_plan_corner` closed that by picking the next street's lane one
#     block EARLY and ending the leg where the two offset paths cross, so the
#     walker rounds the corner on foot. The turn is still counted separately
#     here — but only so the check can say a turn was exercised at all and so
#     the retired model can be run beside it as the mutation control.
#
#     THE MUTATION CONTROL is `_retired_turn_step`: the arrival branch exactly as
#     it stood before the corner leg, driven on the same crowd, which must blow
#     the same bound. Without it "the corner is bounded" is a claim about code
#     nobody re-ran — the check-10 precedent, where the retired sampler is
#     written out and has to fail.
#
#     `_update_walkers` is driven DIRECTLY rather than through `_process`: the
#     spawn/recycle pass legitimately teleports (that is what a recycle IS), so
#     leaving it out is what makes any jump here the walk's own.
#
# (b) The spawn clearance is `MIN_WALKER_SPACING`, and it used to be measured
#     against the street CENTRELINE while the lane was chosen afterwards — so two
#     candidates 6 m apart on the centreline could pass and then draw the same
#     lane and stand on each other. Measured on the world positions, after a cold
#     fill, which is where every walker's lane has just been drawn.

## 2,000 steps: ~33 s of walking, so every citizen crosses several intersections
## and the 60%-straight case is taken thousands of times over the crowd.
const WALK_STEPS: int = 2000

## The mid-block bound: the fastest walker's own step, doubled. `lod_gated` is
## false here so every citizen advances by exactly DT, and nothing in a walk can
## outrun its own speed — a lane re-roll is 6.4 m or 17.2 m against 0.09 m.
const MAX_STEP_FACTOR: float = 2.0


func _retired_turn_step(citizen: Dictionary, dt: float) -> void:
	## THE RETIRED TURN — the mutation control for the corner waypoint (bead
	## 8gw.24). This is `_update_walkers`'s arrival branch as it stood before
	## `_plan_corner` existed: the walker reaches the grid INTERSECTION and its
	## lane rotates onto the new axis in that same frame. Trimmed to exactly the
	## state the bound measures (pos / target / heading / lane) — the pause roll,
	## the kerb rule, the animation and the proxy pool cannot move a walker
	## sideways, so leaving them out cannot flatter the control.
	var pos: Vector3 = citizen["pos"]
	var target: Vector3 = citizen["target"]
	var to_target: Vector3 = target - pos
	var dist := to_target.length()
	var step: float = float(citizen["speed"]) * dt
	if dist > step and dist >= 0.05:
		citizen["pos"] = pos + to_target / dist * step
		return
	citizen["pos"] = target
	var was: Vector2 = citizen["heading_dir"]
	var nxt: Vector3 = _manager._pick_next_waypoint(target, was)
	citizen["target"] = nxt
	var d := Vector2(nxt.x - target.x, nxt.z - target.z)
	if d.length_squared() > 0.01:
		citizen["heading_dir"] = d.normalized()
	var now_h: Vector2 = citizen["heading_dir"]
	if now_h.is_equal_approx(-was):
		citizen["lane_offset"] = -float(citizen["lane_offset"])
	elif not now_h.is_equal_approx(was):
		citizen["lane_offset"] = _manager._pick_lane(target, now_h, nxt)


func _worst_turn_jump(cits: Array, retired: bool, bound: float) -> Dictionary:
	## Walks the live crowd for WALK_STEPS and reports the worst per-frame world
	## displacement, split on whether the citizen turned that frame. `retired`
	## drives `_retired_turn_step` instead of the shipped `_update_walkers`, which
	## is the only difference between the subject and the control.
	var prev: Array[Vector3] = []
	var prev_h: Array[Vector2] = []
	prev.resize(cits.size())
	prev_h.resize(cits.size())
	for i in cits.size():
		prev[i] = CrowdScript._citizen_world_pos(cits[i])
		prev_h[i] = cits[i]["heading_dir"]
	var out := {"straight": 0.0, "straight_at": -1, "corner": 0.0, "turns": 0}
	for _f in WALK_STEPS:
		if retired:
			for c: Dictionary in cits:
				if c["active"]:
					_retired_turn_step(c, DT)
		else:
			_manager._update_walkers(DT, false)
		for i in cits.size():
			if not cits[i]["active"]:
				continue
			var now: Vector3 = CrowdScript._citizen_world_pos(cits[i])
			var h: Vector2 = cits[i]["heading_dir"]
			var moved := Vector2(now.x - prev[i].x, now.z - prev[i].z).length()
			if h.is_equal_approx(prev_h[i]):
				if moved > float(out["straight"]):
					out["straight"] = moved
					out["straight_at"] = i
			else:
				out["turns"] = int(out["turns"]) + 1
				out["corner"] = maxf(float(out["corner"]), moved)
			prev[i] = now
			prev_h[i] = h
	return out


func _check_walkers_never_teleport() -> void:
	# ONE bound for every frame of a walk, turning or not (bead 8gw.24): nothing
	# in a walk can outrun its own speed, and rounding a corner is walking.
	var bound: float = CrowdScript.WALK_SPEED_MAX * DT * MAX_STEP_FACTOR
	_manager._hide_all()
	_player.position = Vector3(2600.0, 1.0, 0.0)
	# The SPAWN PASS ALONE, not `_process`: the movement pass would step every
	# walker up to WALK_SPEED_MAX * DT before the clearance below is measured, and
	# two placed exactly at the floor closing on each other read as a violation the
	# sampler never committed. This is also the last spawn pass of the check — the
	# walk below is driven straight into `_update_walkers`.
	var no_planes: Array[Plane] = []
	_manager._update_crowd_spawns(DT, _player.position, no_planes)

	var cits: Array = _manager.get("_citizens")
	# (b) THE SPAWN CLEARANCE, on the positions the walkers really stand at.
	var world: Array[Vector3] = []
	for c: Dictionary in cits:
		if c["active"]:
			world.append(CrowdScript._citizen_world_pos(c))
	var live: int = world.size()
	var worst_gap := INF
	for a in world.size():
		for b in range(a + 1, world.size()):
			var gap := Vector2(world[a].x - world[b].x, world[a].z - world[b].z).length()
			worst_gap = minf(worst_gap, gap)
	if live < 20:
		_failures.append("check 12 filled only %d walkers — too few to mean anything" % live)
		Sentinel.done("walkers_never_teleport")
		return
	if worst_gap < CrowdScript.MIN_WALKER_SPACING:
		_failures.append(("two walkers spawned %.2f m apart, inside MIN_WALKER_SPACING"
			+ " (%.2f) — the clearance is being measured somewhere nobody stands, which is"
			+ " what happens when the lane is drawn after the test.")
			% [worst_gap, CrowdScript.MIN_WALKER_SPACING])

	# (a) THE WALK ITSELF, split on whether the citizen turned that frame.
	var walk := _worst_turn_jump(cits, false, bound)
	var worst_step: float = float(walk["straight"])
	var worst_at: int = int(walk["straight_at"])
	var worst_corner: float = float(walk["corner"])
	var turns: int = int(walk["turns"])
	if turns < 20:
		_failures.append("check 12 saw only %d turns in %d steps — the corner bound below"
			% [turns, WALK_STEPS] + " was never exercised. A 62 m block at ~2.3 m/s is"
			+ " ~1,600 frames, so a few dozen is the expected yield; zero is not.")
	if worst_step > bound:
		_failures.append(("walker %d moved %.2f m in ONE frame WITHOUT TURNING, against a"
			+ " bound of %.3f m (WALK_SPEED_MAX x %.3f x %.0f). A walk cannot outrun its own"
			+ " speed, so this is the lane jumping sideways — _pick_lane must be asked on a"
			+ " TURN and only on a turn.") % [worst_at, worst_step, bound, DT, MAX_STEP_FACTOR])
	if worst_corner > bound:
		_failures.append(("a walker moved %.2f m through a CORNER, against the same %.3f m"
			+ " bound every other frame is held to. Rounding a corner is WALKING since bead"
			+ " 8gw.24: `_plan_corner` picks the next street's lane a block early and ends"
			+ " the leg where the two offset paths cross, so the rendered position must not"
			+ " move at the turn at all.") % [worst_corner, bound])
	else:
		print("walk continuity: %d walkers, %d steps, worst straight frame %.4f m (bound"
			% [live, WALK_STEPS, worst_step]
			+ " %.4f); %d corners, worst %.4f m (same bound); closest spawn pair %.2f m"
			% [bound, turns, worst_corner, worst_gap])

	# (c) THE MUTATION CONTROL: the retired arrival branch on a freshly filled
	# crowd. It has to blow the bound the shipped walk just met, or "the corner is
	# bounded" is a statement about a model nobody ran.
	_manager._hide_all()
	_manager._update_crowd_spawns(DT, _player.position, no_planes)
	var retired := _worst_turn_jump(_manager.get("_citizens"), true, bound)
	if int(retired["turns"]) < 20:
		_failures.append("check 12's mutation control saw only %d turns — it proves nothing"
			% int(retired["turns"]))
	elif float(retired["corner"]) <= bound:
		_failures.append(("check 12's mutation control (the retired turn, which rotates the"
			+ " lane at the intersection) stayed inside %.3f m at its worst corner (%.4f m)."
			+ " It is supposed to jump sqrt(2) x lane, so this check can no longer tell the"
			+ " corner waypoint apart from its absence.") % [bound, float(retired["corner"])])
	else:
		print("  mutation control (retired turn): worst corner %.2f m, past the %.3f m bound"
			% [float(retired["corner"]), bound])
	_manager._hide_all()
	Sentinel.done("walkers_never_teleport")


# ============================================================================
# CHECK 13 — NOBODY WALKS ON THE DANUBE (bead godot-test1-8gw.23, round 3)
# ============================================================================
#
# THE BUG THIS EXISTS FOR. A walker's lane is up to PAVEMENT_LANE_OFFSET to the
# SIDE of the street line it follows, and every walkability test in this file
# used to be asked of the CENTRELINE. On the four bridge avenues those two answer
# differently: a `DRY_RECTS` row covers the deck, so a north/south walker at
# x = 2344 is on dry ground while its RENDERED position at x = 2352.6 is over open
# water — and the recycle pass, asking the base too, never took it away. A citizen
# walking on the Danube, for as long as the bubble held it.
#
# Both halves are fixed and this measures the pair from the outside: the lane is
# validated along the WHOLE leg (`_lane_walkable`, sampled at both ends and the
# middle) and the recycle guard asks `_citizen_world_pos`. So the assertion needs
# to know about neither — it drives a live bubble at each bridge and asks the
# shipped `is_walkable` of every RENDERED position.
#
# Non-vacuity matters more than usual here: a probe that never puts a walker
# NEAR the river proves nothing, so it counts the walkers within reach of the
# band and fails if the bubbles never went near the water.

## Frames per bridge: enough for a walker spawned on a deck avenue to walk clear
## of the DRY rect (32 m of deck at ~2.3 m/s is ~14 s).
const RIVER_FRAMES: int = 1200

## How near the Danube's centreline a walker has to come for this to have been a
## real test of the river edge at all.
const RIVER_REACH: float = 160.0
const RIVER_MIN_NEAR: int = 20


func _check_no_walker_on_water() -> void:
	var wet: int = 0
	var near_river: int = 0
	var worst := Vector3.ZERO
	for row_v: Variant in PLAN.BRIDGES:
		var row: Dictionary = row_v
		var rect: Rect2 = PLAN.DRY_RECTS[int(row["dry"])]
		# Stand the hero ON the deck: the bubble then straddles both banks and the
		# open water either side of it, which is exactly the geometry that broke.
		var spot := Vector3(rect.position.x + rect.size.x * 0.5, 1.0,
				rect.position.y + rect.size.y * 0.5)
		_manager._hide_all()
		_player.position = spot
		for _f in RIVER_FRAMES:
			_manager._process(DT)
			for c: Dictionary in _manager.get("_citizens"):
				if not c["active"]:
					continue
				var w: Vector3 = CrowdScript._citizen_world_pos(c)
				if PLAN.danube_distance(w.x, w.z) < RIVER_REACH:
					near_river += 1
				if not CrowdScript.is_walkable(w.x, w.z):
					wet += 1
					worst = w
	if near_river < RIVER_MIN_NEAR:
		_failures.append("check 13 never put a walker within %.0f m of the Danube (%d"
			% [RIVER_REACH, near_river] + " samples) — it measured nothing about the river")
	if wet > 0:
		_failures.append(("%d walker frames were rendered on unwalkable ground — the last at"
			+ " %s, %.1f m from the Danube's centreline. A lane is up to %.1f m to the SIDE"
			+ " of the street line, so a base that is dry says nothing; `_lane_walkable`"
			+ " validates the whole leg and the recycle guard asks the RENDERED position.")
			% [wet, str(worst), PLAN.danube_distance(worst.x, worst.z),
			CrowdScript.PAVEMENT_LANE_OFFSET])
	else:
		print("river: %d walker-frames sampled at the four bridges, %d of them within"
			% [near_river, near_river] + " %.0f m of the Danube, none on water"
			% RIVER_REACH)
	_manager._hide_all()
	Sentinel.done("no_walker_on_water")
