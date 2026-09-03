extends SceneTree
## Headless self-check: THE CHUNK STREAM OWES EVERY CHUNK A FLOOR AND A WORLD.
##
##   godot --headless --path . --script res://scripts/chunk_stream_selfcheck.gd
##
## Prints "SELFCHECK OK" and exits 0, or prints what failed and exits 1 — the
## same shape as enemy_spawn_selfcheck.gd / prop_selfcheck.gd, and it exists for
## the same reason those do: every way of breaking this looks like ordinary
## scenery from the outside.
##
## WHAT IT GUARDS (bead godot-test1-6mh.3). `update_chunks` no longer builds the
## safety ring outright; it lays that ring's GROUND synchronously — the floor is
## the whole safety guarantee and ~3% of a chunk's cost — and queues the ring
## alongside everything else for the one-chunk-per-frame drain. That splits a
## chunk's life into two states, and both new failure modes are silent:
##
##   1. A GROUNDED CHUNK THAT NEVER GETS ITS CONTENT. It is in `active_chunks`,
##      so every "is this chunk loaded?" test says yes, and the player walks over
##      a flawless 50 m square with no props, no coins and no crocodiles in it
##      forever. Nothing logs anything. Checks 1 and 3.
##   2. A CHUNK GROUNDED TWICE. `_ensure_chunk_ground` runs from the synchronous
##      path AND again from create_chunk when the queue reaches the same chunk;
##      if it ever stops being idempotent the first mesh + collision body is
##      orphaned under the chunk and leaks, invisibly, once per ring chunk per
##      boundary crossing. Check 2.
##
## And the invariant the whole time-slicing rests on:
##
##   3. BUILDING A CHUNK OVER TWO FRAMES PRODUCES THE CHUNK A SINGLE FRAME
##      PRODUCED. Content is a pure function of (chunk coords, run_seed), so
##      deferring it must be a no-op on the world. Check 4 builds the same ring
##      both ways and compares every node in it.
##
## Deliberately NOT covered: frame timing. What this file protects is the
## correctness the timing win was bought with; the timing itself is measured by
## perf_overlay's `[SPIKE]` log on a real build, not asserted here.
##
## The "RID allocations … were leaked at exit" lines after the verdict are the
## engine reporting this project's deliberate static shared caches (the shared
## unit box and ground meshes, the crocodile/coin PackedScenes). They are not a
## failure — same note as enemy_spawn_selfcheck.gd's header.

const TERRAIN_SCRIPT: String = "res://scripts/endless_terrain.gd"

## One seed is enough: this check is about the STATE MACHINE around a chunk, not
## about what any particular chunk contains, and check 4 compares two builds of
## the same seed against each other rather than against a golden file.
const RUN_SEED: int = 20260826

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
	# ONE FRAME BEFORE ANYTHING, for the reason enemy_spawn_selfcheck.gd gives: a
	# node added to `root` from inside _initialize() is not `is_inside_tree()`
	# until the first frame, so anything that reads a global transform (the
	# treasure chest does) would silently measure a detached world.
	await process_frame
	_run()


func _run() -> void:
	var terrain := _make_terrain()

	# THE SYNCHRONOUS CALL UNDER TEST. render_distance 1 makes the field exactly
	# the safety ring, so "queued" and "the ring" are the same set and check 1 can
	# be stated without arithmetic.
	terrain.render_distance = 1
	terrain.update_chunks(Vector2i.ZERO)

	_check_ring_is_grounded_and_owed(terrain)
	_check_second_crossing_keeps_the_debt(terrain)
	_check_build_ring_now_pays_it_all_at_once(terrain)
	_drain(terrain)
	_check_drain_paid_the_debt(terrain)
	_check_two_frame_build_matches_one(terrain)

	terrain.free()
	_report()


func _make_terrain() -> Node3D:
	## A REAL terrain node in the tree, not a stub: this check is about
	## `update_chunks` / `create_chunk` themselves. It joins the tree so the
	## in-tree spawners behave, and it never streams on its own — `_ready` finds
	## no node in group "player", so `player` stays null and `_process` returns
	## immediately. `set_run_seed()` is the public seam (the same one `new_run()`
	## and the multiplayer forced seed go through), so it cannot rot.
	## NO FRAME IS ALLOWED TO PASS between the two builds check 4 compares. Both
	## fields are generated inside this one frame, because a crocodile that has
	## had a physics tick has already settled and wandered a few centimetres —
	## comparing a field built a frame earlier against one built now reports every
	## entity in it as different, which is a live simulation, not a broken build.
	## `_ready()` awaits, but only AFTER it has loaded the crocodile and coin
	## scenes, so everything create_chunk needs is in place the moment add_child
	## returns and this function never has to wait for it.
	var terrain := Node3D.new()
	terrain.set_script(load(TERRAIN_SCRIPT))
	root.add_child(terrain)
	terrain.set_run_seed(RUN_SEED)
	return terrain


func _ring() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(-1, 2):
		for z in range(-1, 2):
			out.append(Vector2i(x, z))
	return out


func _drain(terrain: Node3D) -> void:
	## Exactly what `_process` does, minus the one-per-frame pacing.
	while not terrain.pending_chunks.is_empty():
		terrain.create_chunk(terrain.pending_chunks.pop_front())


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		Sentinel.finish(self)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	quit(1)


# ============================================================================
# CHECKS
# ============================================================================

func _check_ring_is_grounded_and_owed(terrain: Node3D) -> void:
	"""
	Check 1. Every safety-ring chunk is loaded, has a real floor, is marked as
	still owing its content, and is in the queue that will deliver it.

	The negative control is the queue membership: "it has ground" and "it is
	bare" are both true of a chunk nobody will ever finish, and that is precisely
	failure mode 1.
	"""
	for chunk_pos: Vector2i in _ring():
		if chunk_pos not in terrain.active_chunks:
			_fail("safety-ring chunk %s got no ground from update_chunks — the player can fall through it" % chunk_pos)
			continue
		if not _has_ground_collision(terrain.active_chunks[chunk_pos], terrain.chunk_size):
			_fail("safety-ring chunk %s is in active_chunks but has no ground collision box" % chunk_pos)
		if chunk_pos not in terrain.bare_chunks:
			_fail("safety-ring chunk %s was not marked bare — update_chunks would skip it as already loaded and its content would never be built" % chunk_pos)
		if chunk_pos not in terrain.pending_chunks:
			_fail("safety-ring chunk %s was grounded but never queued — nothing will ever populate it" % chunk_pos)
	Sentinel.done("ring_is_grounded_and_owed")


func _check_second_crossing_keeps_the_debt(terrain: Node3D) -> void:
	"""
	Check 3. `update_chunks` rebuilds `pending_chunks` from scratch, and its skip
	test is "already in active_chunks". A bare chunk IS in active_chunks, so a
	second crossing before the drain catches up is exactly where a grounded chunk
	would be dropped from the queue and stranded empty forever.
	"""
	terrain.update_chunks(Vector2i.ZERO)
	for chunk_pos: Vector2i in _ring():
		if chunk_pos in terrain.bare_chunks and chunk_pos not in terrain.pending_chunks:
			_fail("a second update_chunks dropped still-bare chunk %s from the queue — it would stay empty for the rest of the run" % chunk_pos)
	Sentinel.done("second_crossing_keeps_the_debt")


func _check_build_ring_now_pays_it_all_at_once(terrain: Node3D) -> void:
	"""
	Check 5. The multiplayer join escape hatch. A mid-run joiner probes the world
	for a clear landing spot instead of walking into it, so it needs the ring's
	CONTENT, not just its floor, before that probe runs — `build_ring_now()` is
	what buys it, and the failure is silent in the worst way: the probe answers
	"all clear" everywhere and drops the player inside a block that turns up two
	frames later.

	The second half is the reason `create_chunk` carries a populated-already
	guard: `build_ring_now` deliberately leaves the ring's stale entries in
	`pending_chunks`, so the ordinary drain reaches every one of them afterwards
	and MUST do nothing. Without the guard it would parent a whole second set of
	props, coins and crocodiles into a chunk that already has them.
	"""
	terrain.build_ring_now(Vector2i.ZERO)
	for chunk_pos: Vector2i in _ring():
		if chunk_pos in terrain.bare_chunks:
			_fail("build_ring_now left chunk %s bare — a joining peer would probe a world with no blocks in it" % chunk_pos)

	var before: Dictionary = {}
	for chunk_pos: Vector2i in _ring():
		before[chunk_pos] = _signature(terrain.active_chunks[chunk_pos])
	_drain(terrain)
	for chunk_pos: Vector2i in _ring():
		var after := _signature(terrain.active_chunks[chunk_pos])
		if after.size() != (before[chunk_pos] as Array).size():
			_fail("draining the queue after build_ring_now rebuilt chunk %s (%d nodes -> %d) — create_chunk is not idempotent and doubled its contents" % [
				chunk_pos, (before[chunk_pos] as Array).size(), after.size()])
	Sentinel.done("build_ring_now_pays_it_all_at_once")


func _check_drain_paid_the_debt(terrain: Node3D) -> void:
	"""
	Check 1 (closing half) and check 2: after the drain nothing is owed, and no
	chunk was floored twice.
	"""
	if not terrain.bare_chunks.is_empty():
		_fail("%d chunks were still bare after draining the whole queue" % terrain.bare_chunks.size())

	# THE ORPHAN TEST, and it is the one that actually catches a lost idempotence:
	# a second _ensure_chunk_ground does not stack two floors inside one chunk, it
	# builds a WHOLE SECOND CHUNK NODE and overwrites the dictionary entry, so the
	# first one is left parented to the terrain, invisible to every lookup and
	# freed by nothing.
	#
	# STATED BY IDENTITY, not by counting children, because chunks are no longer the
	# terrain's only children: the tower's shell and its horizon impostor are
	# parented to the MANAGER on purpose (epic godot-test1-3iy — a chunk-parented
	# building would be freed the moment the player walked far enough), exactly as
	# fauna_manager parents its herds to itself.
	#
	# AND NOT BY NAME EITHER, which is the trap here: an orphan is a SECOND node with
	# the chunk's name, and Godot resolves the collision by renaming — to
	# "@MeshInstance3D@7", not to "Chunk_0_02". A name-prefix count therefore sees
	# one chunk where there are two and passes the exact bug it was written for
	# (measured, 2026-08-28). Membership in `active_chunks` is what "a lookup can
	# reach it" actually means, so that is what is asked.
	var reachable := {}
	for chunk: Node in terrain.active_chunks.values():
		reachable[chunk.get_instance_id()] = true
	for owned: Node in [terrain._tower_shell, terrain._tower_impostor]:
		if is_instance_valid(owned):
			reachable[owned.get_instance_id()] = true
	var strays: Array[String] = []
	for child: Node in terrain.get_children():
		if not reachable.has(child.get_instance_id()):
			strays.append("%s (%s)" % [child.name, child.get_class()])
	if not strays.is_empty():
		_fail("terrain holds %d nodes no lookup can reach — %s — _ensure_chunk_ground is not idempotent and orphaned them" % [
			strays.size(), ", ".join(strays)])

	for chunk_pos: Vector2i in _ring():
		var chunk: Node = terrain.active_chunks.get(chunk_pos)
		if chunk == null:
			continue
		var grounds := 0
		for child: Node in chunk.get_children():
			# The ground body is the chunk's OTHER StaticBody3D — the blocks all
			# share the one named "BlockCollision" (the project's one-body-per-
			# chunk rule), so anything else is a second floor.
			if child is StaticBody3D and child.name != "BlockCollision":
				grounds += 1
		if grounds != 1:
			_fail("chunk %s has %d ground bodies, expected exactly 1 — _ensure_chunk_ground is not idempotent and is leaking the first one" % [chunk_pos, grounds])
	Sentinel.done("drain_paid_the_debt")


func _check_two_frame_build_matches_one(built_over_two_frames: Node3D) -> void:
	"""
	Check 4. The same ring, same seed, built the OLD way — one create_chunk per
	chunk, ground and content in one go — must come out node-for-node identical
	to the ring above, which got its ground on one frame and its content later.

	Compared by NAME AND LOCAL POSITION of every descendant, which is the
	strongest thing that is still deterministic here. Two things are deliberately
	NOT in the signature because they are not part of the world:

	  * a crocodile's SCALE and speed, which come from a `randomize()`d
	    per-instance roll (see CLAUDE.md — only positions are deterministic);
	  * ENGINE-GENERATED node names (`@CollisionShape3D@205`), whose counter is
	    global to the process and so differs between any two builds, correct or
	    not. Those nodes contribute their class instead — see _label().
	"""
	var reference := _make_terrain()
	for chunk_pos: Vector2i in _ring():
		reference.create_chunk(chunk_pos)

	for chunk_pos: Vector2i in _ring():
		var a: Node = built_over_two_frames.active_chunks.get(chunk_pos)
		var b: Node = reference.active_chunks.get(chunk_pos)
		if a == null or b == null:
			_fail("chunk %s missing from one of the two builds — cannot compare" % chunk_pos)
			continue
		var sig_a := _signature(a)
		var sig_b := _signature(b)
		if sig_a != sig_b:
			_fail("chunk %s differs between the two-frame build and the one-frame build (%d vs %d nodes) — deferring content changed the world" % [
				chunk_pos, sig_a.size(), sig_b.size()])
			break
	reference.free()
	Sentinel.done("two_frame_build_matches_one")


# ============================================================================
# HELPERS
# ============================================================================

func _has_ground_collision(chunk: Node, chunk_size: float) -> bool:
	## A floor is a CollisionShape3D holding a BoxShape3D that spans the chunk.
	## Measured off the real shape rather than trusted from the node's existence,
	## the house rule enemy_spawn_selfcheck.gd states.
	for child: Node in chunk.get_children():
		if not (child is StaticBody3D):
			continue
		for shape: Node in child.get_children():
			if not (shape is CollisionShape3D):
				continue
			var box := (shape as CollisionShape3D).shape as BoxShape3D
			if box != null and is_equal_approx(box.size.x, chunk_size) and is_equal_approx(box.size.z, chunk_size):
				return true
	return false


func _signature(chunk: Node) -> Array[String]:
	## Every descendant as "label@x,y,z", sorted — order of creation is not part
	## of the world, only the set of things and where they are.
	var out: Array[String] = []
	_collect(chunk, out)
	out.sort()
	return out


func _collect(node: Node, out: Array[String]) -> void:
	for child: Node in node.get_children():
		var where := ""
		if child is Node3D:
			var p: Vector3 = (child as Node3D).position
			where = "@%.3f,%.3f,%.3f" % [p.x, p.y, p.z]
		out.append(_label(child) + where)
		_collect(child, out)


func _label(node: Node) -> String:
	## A node's name, unless the engine made it up. Nodes added without a name get
	## `@Class@<counter>`, and that counter is global to the process: it is higher
	## in the second build than in the first no matter how identical the two are,
	## so comparing it would fail every correct run. Their class is the part that
	## carries meaning. Named nodes (chunks, crocodiles, coins — whose names are
	## deterministic and, for crocodiles, are the multiplayer identity) keep theirs.
	if node.name.begins_with("@"):
		return node.get_class()
	return node.name
