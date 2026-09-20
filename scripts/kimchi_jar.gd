class_name KimchiJar
extends Node3D
## PHOBOMAN'S KIMCHI OFFERING — the HONEYPOT jar (bead godot-test1-m7jp, owner
## ruling 2026-09-20: "immediate, 12 s, every hunter and crocodile in range
## holds at the jar and ignores everything").
##
## Immediate on landing, no arming, no ferment, no scatter. Every hunter and
## crocodile within `HONEYPOT_RADIUS` converges on the jar and HOLDS there for
## `HONEYPOT_SECONDS`, ignoring the heroes (no chase, no capture, no bite),
## the stink (no flee) and every scent track — then the pot cracks with a red
## shimmer and the pack is released. Phoboman walks away calmly.
##
## HOW IT WORKS. `_lure()` is a CONTINUOUS sweep, run from `_process` every
## tick while the jar is down and once synchronously from `drop()`: every body
## in range is told `take_bait()` with the jar's own remainder
## (`HONEYPOT_SECONDS - _age`), so a body that wanders into range at t=7 is
## caught too, with the 5 s the jar still has, and every body releases on the
## jar's 12 s no matter when it was caught. The AI's baited state outranks
## flee and chase, refuses `flee_from()` and `_on_player_collision()`, and ends
## on the lure's own home leg — the release is the errand expiring, not a
## second effect, and there is no release code here at all.
##
## BOSSES COME, CLAMPED. The sweep offers the pot to everything in range and
## the AI clamps it into the territory (the `is_boss` LAYER, CLAUDE.md), so a
## boss walks to its fence and holds there instead of fighting the hard clamp.
##
## INDOORS THE ROUTER STILL OWNS THE GUARD. Under a roof the field loop is
## skipped and the storey's guard is sent through
## `TowerInterior.lure_guard_to()` with the jar's remainder as the hold. A
## guard already chasing still refuses — that is the plate's anti-puppet rule
## and it stays refused: the owner's report was the field, and the building
## keeps its stake in you.
##
## NOTHING DIES HERE AND NOTHING MAY (owner ruling 3, 2026-09-18): the jar
## lures and releases. `capture_selfcheck` check 10d greps this file and the
## arm that spawns it for a kill call, and counts its live bodies afterwards.
##
## WHY NO SPECIES TEST ANYWHERE. `take_bait()` takes every row — the honeypot
## is not a smell the sealed rows shrug at, it is the owner's "ignore
## everything" — and indoors the router never had a `stink_immune` test (a
## guard taking a lure IS the plate feature). Adding a name test to either
## would be the bug.
##
## WHY A TRANSIENT NODE AND NOT A CHUNK BOX. `create_box()` writes into the
## seeded chunk batch, and an ability that placed geometry there would be a draw
## in a deterministic stream (CLAUDE.md, "the RNG stream is the contract").
## `ability_effect.gd` is the idiom this follows: built whole in a static
## factory, parented to the player's parent so it outlives a character switch,
## driven by a time accumulator in `_process`, and it frees itself.
##
## MULTIPLAYER — EVERY MACHINE HOLDS ITS OWN JAR, and that is what makes this
## file MP-blind. The `bait` verb is a BROADCAST (owner ruling 2026-09-18: "the
## kimchi jar is VISIBLE TO EVERYONE IN THE ROOM in v1"), so the caster drops one
## here and every other member drops the same one from the packet —
## `MpWorldSync.apply_bait()`. Each copy runs its own clock and sweeps locally,
## which is exactly `MpWorldSync.request_croc_flee()`'s coverage argument one
## ability along:
##
##   * ON THE MASTER the local sweep IS the simulation, and the master's 12 s
##     is the one the room obeys: `is_baited` is a bit in the croc-sync flag
##     byte (`MpCodec.CROC_FLAG_BAITED`), so its harmlessness reaches every
##     screen 100 ms later and clears itself with the next sample.
##   * ON A PEER the sweep is correct for the bodies the master does not drive
##     (its terrain may be a kilometre away) and a no-op for the rest —
##     `take_bait()` refuses a `remote_driven` body outright, and a baited flag
##     set on one is overwritten by the next sample.
##
## So the timers are the MASTER'S where it matters and a peer's jar cracks within
## one RTT of it. Nothing here sends a packet; the arm that drops the jar does.

## Seconds from placement to the crack. Twelve of them: long enough to walk
## away from anything the jar took, short enough that a jar is a play and not
## a mode. The ability's own cooldown (14 s) outlasts this plus `LINGER`.
const HONEYPOT_SECONDS: float = 12.0

## How far the invitation carries, in metres. Above every `detection_radius`
## (the hunter's 25.0 is the widest row), so every body that could see the
## hero from the jar's side is taken; below `CrocodileLodManager.SIM_RADIUS`
## (45), so a sleeper is never woken — a slept body could not reach the hero
## anyway, and waking a 30 m ball of them on one key press is the sweep
## `flee_from()` refuses for the same reason.
const HONEYPOT_RADIUS: float = 30.0

## How long the cracked jar stays visible after the release, in seconds, before
## it frees itself. One beat of "that was the jar" and then it is gone.
const LINGER: float = 1.0

## The clay and its rim. `LandmarkBuilders.LM_OCHRE` is the world's clay, one
## shade down so a jar on a pavement reads as a jar and not as paving.
const CLAY := Color(0.62, 0.38, 0.21)
const RIM := Color(0.78, 0.21, 0.12)

## The release's colour, the honeypot's shimmer in red-orange — a different
## smell, and the alpha says so.
const RELEASE_COLOR := Color(0.95, 0.4, 0.2, 0.5)

## The wave `_release()` spawns three of, staggered. Same node the four F abilities
## use, so the jar costs the renderer nothing a Stink Wave does not.
const ABILITY_EFFECT := preload("res://scripts/ability_effect.gd")

## Seconds since the jar landed. The whole state machine: below
## `HONEYPOT_SECONDS` it sweeps, past it the release has fired, past
## `HONEYPOT_SECONDS + LINGER` it is gone.
var _age: float = 0.0

## Whether the release has fired. A latch and not a time test, so a frame long
## enough to step over the whole `LINGER` window can never crack twice.
var _released: bool = false


static func drop(parent: Node, pos: Vector3) -> KimchiJar:
	"""
	Set a jar down at `pos` and ring the dinner bell. The ONE way a jar is made.

	@param parent: the node to hang it on — the player's PARENT and never the
	    player, so a character switch, a respawn or a capture leaves the jar
	    standing in the world (the release still comes; see
	    `PlayerAbilities._reset_ability_states`).
	@return: the jar, or null when there is nothing to parent it to.

	Static, and everything is built here rather than in `_ready()`, so the caller
	holds a fully-formed jar the instant it returns — `ability_effect.setup()`'s
	contract, for the same reason: the self-checks drive the clock synchronously
	and cannot wait a frame to find out whether the landing sweep happened.
	"""
	if parent == null:
		return null
	var jar := KimchiJar.new()
	jar.name = "KimchiJar"
	parent.add_child(jar)
	jar.global_position = pos
	jar._build()
	jar._lure()
	return jar


func _build() -> void:
	"""The two boxes: a squat clay belly and a red rim sitting on top of it."""
	_add_box(Vector3(0.55, 0.6, 0.55), 0.3, CLAY)
	_add_box(Vector3(0.40, 0.12, 0.40), 0.66, RIM)


func _add_box(size: Vector3, centre_y: float, color: Color) -> void:
	"""
	One unit mesh scaled to `size`, its centre `centre_y` above the jar's origin.

	`ChunkBatch.unit_mesh()`'s CYLINDER, which is the world's own round box kind:
	the jar is faceted exactly like every barrel and column around it, it costs no
	new GPU buffer (that table is a process-wide lazy singleton), and the kind's
	contract — inscribed in the unit cube — means `size` IS the bounding box, so
	the two pieces stack by arithmetic. The MATERIAL is per-instance because the
	two pieces are two colours; two of those per jar, and one jar at a time.
	"""
	var box := MeshInstance3D.new()
	box.mesh = ChunkBatch.unit_mesh(ChunkBatch.BoxKind.CYLINDER)
	box.scale = size
	box.position = Vector3(0.0, centre_y, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	box.material_override = mat
	add_child(box)


func _lure() -> void:
	"""
	ONE SWEEP. Offer the pot to everything in range: the building's guard
	through the router, every awake field body through `take_bait()`.

	TWO WORLDS, AND THE BUILDING ROUTES ITS OWN. Outdoors the ground is flat and
	empty, so the route is empty too — "straight there" is the honest answer a
	caller with no floor plan can give, and `take_bait()` says so. Inside
	the HQ a straight line is a wall: the corners come from the plan, and the plan
	belongs to `TowerInterior`, which is why the whole indoor case is one call to
	`lure_guard_to()` and no geometry is computed here. A predator that knew about
	`TowerPlans` would be a hunting AI with a level editor in it (`lure_guard()`).

	WHICH WORLD IS THE ROUTER'S ANSWER, not the shell's envelope — see the
	comment at the branch itself for the 1.2 m of wall band that told the two
	apart, and for what falling through now costs.

	INDOORS THE GUARD IS THE WHOLE POPULATION, and that is a `ponytail:` bound
	worth naming: the storey's guard is the only body `TowerInterior` can route,
	so a jar under the roof takes it and nothing else. The cell block's crocodiles
	are behind a gate on another storey and were never going to walk to it; the
	upgrade, if anybody ever wants it, is a router that takes a body rather than
	finding one, and it belongs in that file.

	THE CALLER OWNS ONE EXCLUSION and `take_bait()` owns the rest:

	  * `lod_active` — a slept body is left alone because it could never tick
	    the hold down: `set_lod_active(false)` switches the physics callback
	    off, so an offered pot would sit baited-but-frozen until the body woke,
	    and one press would hold every sleeper in a 30 m ball harmless-on-wake
	    for as long as the player keeps advancing. A slept body is past
	    `SIM_RADIUS` and could not reach the hero anyway.

	Busy bodies (chasing, biting, tracking, fleeing, already on an errand) are
	TAKEN, not refused — that is the honeypot, and the door is `take_bait()`'s.
	"""
	# A jar outside the tree lures nobody, and is not an error: `drop()` is called
	# with whatever parent the caller has, and a scene run standalone may hand it
	# one that has not entered yet. Same degrade as every group lookup here.
	if not is_inside_tree():
		return
	# THE BUILDING GETS FIRST REFUSAL, AND ITS OWN ANSWER IS WHAT DECIDES — not
	# the shell's envelope (revmux round 1, `arch+quality`). The two are not the
	# same box: `TowerShell.sheltered()` measures `OUTER_HALF` (40.0) and
	# `lure_guard_to()` measures `TowerPlans.PLAN_HALF` (38.8), and
	# `sheltered()`'s own docstring names that 1.2 m of wall band as a gap it
	# narrows without closing. Branching on the SHELL put every jar landing in
	# that band — a hero standing two metres outside the tower and facing it,
	# which is ordinary play — into a dead zone: the building refused it and the
	# field never saw it, so a 14 s cooldown bought a pot that lured nobody.
	# Asking the router instead has one answer for one question, and
	# `tower_guard_selfcheck` check 22(d) stands a crocodile in that band to
	# prove it.
	var interior: Node = get_tree().get_first_node_in_group("tower_interior")
	if interior != null and interior.has_method("lure_guard_to") \
			and bool(interior.call("lure_guard_to", global_position,
				HONEYPOT_SECONDS - _age)):
		return
	var radius_sq := HONEYPOT_RADIUS * HONEYPOT_RADIUS
	for body: Node in get_tree().get_nodes_in_group("crocodile"):
		# `is Node3D` beside the `has_method` guard, `MpWorldSync.apply_flee()`'s
		# rule: `body as Node3D` on a non-Node3D yields null and the position read
		# below would be a hard error, which in GDScript unwinds this whole
		# function and abandons every remaining body mid-sweep.
		if not is_instance_valid(body) or not (body is Node3D):
			continue
		if not body.has_method("take_bait"):
			continue
		if not bool(body.get("lod_active")):
			continue
		if (body as Node3D).global_position.distance_squared_to(global_position) > radius_sq:
			continue
		# A BODY THE SHELL SHELTERS IS THE BUILDING'S, and a straight line to it
		# goes through a wall. The router above is the only thing that may move
		# one; here the roof decides, not a species.
		#
		# `ponytail:` THE RESIDUAL, and there are exactly three ways to be refused
		# indoors and reach this loop: no `G` on that storey, a guard already
		# busy, and — the one a player can walk to on purpose — A JAR IN THE WALL
		# BAND (revmux round 2, `bugs+impl`). Every storey draws a one-cell `#`
		# ring, so a hero pressed to the inner face stands at |x| 36.36 and
		# `KIMCHI_PLACE_AHEAD` 3.0 lands the pot between 38.8 and 39.36: past
		# `TowerPlans.PLAN_HALF`, inside `TowerShell.OUTER_HALF`. The router
		# refuses it, this loop skips the guard two metres away because the shell
		# shelters it, and with no unsheltered body within 30 m the press buys
		# nothing. That is the roof deciding, which is the policy above — but it
		# is a dud a player can reproduce, and it is named here rather than left
		# to be rediscovered. For the first two the loop DOES run and may walk an
		# unsheltered body at the outside of the wall it is behind;
		# `_investigate_move()`'s stall watchdog bounds that to one walk and hands
		# the leash back. The upgrade for all three is a router that takes a body
		# rather than finding one, and it belongs in `tower_interior.gd`.
		if _under_the_roof((body as Node3D).global_position):
			continue
		body.call("take_bait", global_position, HONEYPOT_SECONDS - _age)


func _release() -> void:
	"""
	THE CRACK. Three red-orange waves and nothing else: the pot is empty, the
	pack is free, and nobody runs anywhere.

	`tracks_player` never comes up because there is no flight to aim — the
	release is a PICTURE, and the bodies' own holds expiring is what lets them
	go. A body still walking when the jar cracks keeps walking, arrives at the
	cracked pot, and sniffs the empty spot for the remainder of its hold. That
	is the hold the sweep gave it, and `_investigate_move()`'s stall watchdog
	bounds a body that cannot get there at all.
	"""
	if not is_inside_tree():
		return
	# Parented to the jar's PARENT and not to the jar, `_spawn_ability_effect()`'s
	# rule: the last wave's delay plus lifetime outlasts `LINGER`, so a wave hung
	# on the jar would be cut off mid-expansion when the jar frees itself.
	var here: Vector3 = global_position
	var parent: Node = get_parent()
	for i in range(3):
		if parent == null:
			break
		var fx := MeshInstance3D.new()
		fx.set_script(ABILITY_EFFECT)
		parent.add_child(fx)
		fx.global_position = here
		fx.setup(RELEASE_COLOR, HONEYPOT_RADIUS, 0.9, i * 0.18)


func _under_the_roof(pos: Vector3) -> bool:
	"""
	Whether `pos` is inside the HQ, asked of the SHELL through the "tower" group.

	`PlayerController._sheltered()`'s predicate exactly, and for its reason: the
	building owns the envelope, so nothing here restates its numbers and a scene
	with no tower in it (the field, and most of the self-checks) simply answers
	"outdoors". Group discovery with a `has_method` guard, like every other
	cross-system call in this file.
	"""
	var tower: Node = get_tree().get_first_node_in_group("tower")
	if tower != null and tower.has_method("sheltered"):
		return bool(tower.call("sheltered", pos))
	return false


func _process(delta: float) -> void:
	"""The one clock: sweep while down, crack at 12 s, linger, free itself."""
	_age += delta
	if _age < HONEYPOT_SECONDS:
		_lure()
	elif not _released:
		_released = true
		_release()
	if _age >= HONEYPOT_SECONDS + LINGER:
		queue_free()
