class_name KimchiJar
extends Node3D
## PHOBOMAN'S KIMCHI OFFERING — the jar (bead godot-test1-0mr0.5, epic
## godot-test1-0mr0, owner ruling 5: "yes, attract all").
##
## A clay jar set down 3 m ahead of Phoboman, with two beats on one clock:
##
##   BEAT 1, the instant it lands: everything idle within `LURE_RADIUS` walks
##     over and sniffs — crocodiles, the hunter robot, and the HQ's guards.
##   BEAT 2, at `FERMENT` seconds whether anybody came or not: the kimchi is
##     ready, a red-orange burst `BURST_RADIUS` wide, and every body with a NOSE
##     inside it bolts for `FLEE_DURATION`. They come for the smell and they
##     leave because of the smell.
##
## NOTHING DIES HERE AND NOTHING MAY (owner ruling 3, 2026-09-18): the jar lures
## and scatters. `capture_selfcheck` check 10d greps this file and the arm that
## spawns it for a kill call, and counts its live bodies afterwards.
##
## WHY THE GUARDS COME AND DO NOT RUN, with no species test anywhere. The two
## beats go through two existing functions and the split falls out of them:
## `investigate_point()` has never had a `stink_immune` test (it is the `P`
## plate's own path, and a guard taking a lure IS that feature), while
## `flee_from()` has had one since Phoboman shipped. So "lures everyone,
## scatters only the ones with a nose" is not an exception written here — it is
## what the two row-keyed functions already say. Adding a name test to either
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
## `MpWorldSync.apply_bait()`. Each copy runs its own clock and applies both
## beats locally, which is exactly `MpWorldSync.request_croc_flee()`'s coverage
## argument one ability along:
##
##   * ON THE MASTER the local pass IS the simulation, and the master's beat 2
##     is the one the room sees: `is_fleeing` is a bit in the croc-sync flag
##     byte, so its decision reaches every screen 100 ms later.
##   * ON A PEER the pass is correct for the bodies the master does not drive
##     (its terrain may be a kilometre away) and a no-op for the rest —
##     `investigate_point()` refuses a `remote_driven` body outright, and a flee
##     flag set on one is overwritten by the next sample.
##
## So the timers are the MASTER'S where it matters and a peer's jar cracks within
## one RTT of it. Nothing here sends a packet; the arm that drops the jar does.

## How far beat 1's invitation carries, in metres. Deliberately much wider than
## the burst: the jar is a PREPARATION tool — you place it, the storey's guard
## and the pack walk off their beat toward it, and you take the corridor they
## left. 20 m is a little under half `CrocodileLodManager.SIM_RADIUS`, so every
## body this wakes is one the LOD manager was already about to simulate.
const LURE_RADIUS: float = 20.0

## How long a body that took the lure stands over the jar, in seconds — passed
## straight to `investigate_point()` as its hold. Equal to `FERMENT` on purpose:
## a body that set off at the drop is still sniffing when the jar cracks.
const LURE_HOLD: float = 5.0

## Seconds from placement to beat 2. Long enough to walk 20 m at a wander speed
## and short enough that a jar is a play and not a mode.
const FERMENT: float = 5.0

## Beat 2's reach, in metres. A THIRD of the lure radius, and that gap is the
## whole joke: most of what came is still walking, and only the bodies that
## actually arrived are standing in it.
const BURST_RADIUS: float = 6.0

## How long the scattered run for, in seconds. Phoboman's own Stink Wave is 10 s;
## this is a fifth of a wave's worth, because the jar's job was done at beat 1.
const FLEE_DURATION: float = 4.0

## How long the cracked jar stays visible after the burst, in seconds, before it
## frees itself. One beat of "that was the jar" and then it is gone.
const LINGER: float = 1.0

## The clay and its rim. `LandmarkBuilders.LM_OCHRE` is the world's clay, one
## shade down so a jar on a pavement reads as a jar and not as paving.
const CLAY := Color(0.62, 0.38, 0.21)
const RIM := Color(0.78, 0.21, 0.12)

## The burst's colour, the stink's stagger in red-orange rather than the Stink
## Wave's green — a different smell, and the alpha says so.
const BURST_COLOR := Color(0.95, 0.4, 0.2, 0.5)

## The wave `_burst()` spawns three of, staggered. Same node the four F abilities
## use, so the jar costs the renderer nothing a Stink Wave does not.
const ABILITY_EFFECT := preload("res://scripts/ability_effect.gd")

## Seconds since the jar landed. The whole state machine: below `FERMENT` it is
## brewing, past it the burst has fired, past `FERMENT + LINGER` it is gone.
var _age: float = 0.0

## Whether beat 2 has fired. A latch and not a time test, so a frame long enough
## to step over the whole `LINGER` window can never scatter twice.
var _burst_done: bool = false


static func drop(parent: Node, pos: Vector3) -> KimchiJar:
	"""
	Set a jar down at `pos` and ring the dinner bell. The ONE way a jar is made.

	@param parent: the node to hang it on — the player's PARENT and never the
	    player, so a character switch, a respawn or a capture leaves the jar
	    standing in the world (the burst still comes; see
	    `PlayerAbilities._reset_ability_states`).
	@return: the jar, or null when there is nothing to parent it to.

	Static, and everything is built here rather than in `_ready()`, so the caller
	holds a fully-formed jar the instant it returns — `ability_effect.setup()`'s
	contract, for the same reason: the self-checks drive the beats synchronously
	and cannot wait a frame to find out whether beat 1 happened.
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
	BEAT 1. Invite everything idle within `LURE_RADIUS` over for a sniff.

	TWO WORLDS, AND THE BUILDING ROUTES ITS OWN. Outdoors the ground is flat and
	empty, so the route is empty too — "straight there" is the honest answer a
	caller with no floor plan can give, and `investigate_point()` says so. Inside
	the HQ a straight line is a wall: the corners come from the plan, and the plan
	belongs to `TowerInterior`, which is why the whole indoor case is one call to
	`lure_guard_to()` and no geometry is computed here. A predator that knew about
	`TowerPlans` would be a hunting AI with a level editor in it (`lure_guard()`).

	WHICH WORLD IS THE ROUTER'S ANSWER, not the shell's envelope — see the
	comment at the branch itself for the 1.2 m of wall band that told the two
	apart, and for what falling through now costs.

	INDOORS THE GUARD IS THE WHOLE POPULATION, and that is a `ponytail:` bound
	worth naming: the storey's guard is the only body `TowerInterior` can route,
	so a jar under the roof lures it and nothing else. The cell block's crocodiles
	are behind a gate on another storey and were never going to walk to it; the
	upgrade, if anybody ever wants it, is a router that takes a body rather than
	finding one, and it belongs in that file.

	THE CALLER OWNS TWO OF THE EXCLUSIONS and `investigate_point()` owns the rest:

	  * `is_boss` — a boss is leashed to its territory (`_steer_within_territory`),
	    so a lured one would walk to the edge of its leash and fight the clamp for
	    five seconds. Immunity through the `is_boss` LAYER, which is where
	    everything true of "boss" lives (CLAUDE.md), not through a row key.
	  * `lod_active` — `investigate_point()` deliberately WAKES what it lures, for
	    the far plate on a wide storey. Letting that reach a slept body here would
	    wake every sleeper in a 20 m ball on one key press, which is the sweep
	    `flee_from()` refuses for the same reason.

	Busy bodies (chasing, biting, already on an errand) and remote-driven ones
	refuse inside `investigate_point()`, where both doors into it can see the rule.
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
			and bool(interior.call("lure_guard_to", global_position, LURE_HOLD)):
		return
	var radius_sq := LURE_RADIUS * LURE_RADIUS
	for body: Node in get_tree().get_nodes_in_group("crocodile"):
		# `is Node3D` beside the `has_method` guard, `MpWorldSync.apply_flee()`'s
		# rule: `body as Node3D` on a non-Node3D yields null and the position read
		# below would be a hard error, which in GDScript unwinds this whole
		# function and abandons every remaining body mid-sweep.
		if not is_instance_valid(body) or not (body is Node3D):
			continue
		if not body.has_method("investigate_point"):
			continue
		if bool(body.get("is_boss")) or not bool(body.get("lod_active")):
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
		# shelters it, and with no unsheltered body within 20 m the press buys
		# nothing. That is the roof deciding, which is the policy above — but it
		# is a dud a player can reproduce, and it is named here rather than left
		# to be rediscovered. For the first two the loop DOES run and may walk an
		# unsheltered body at the outside of the wall it is behind;
		# `_investigate_move()`'s stall watchdog bounds that to one walk and hands
		# the leash back. The upgrade for all three is a router that takes a body
		# rather than finding one, and it belongs in `tower_interior.gd`.
		if _under_the_roof((body as Node3D).global_position):
			continue
		body.call("investigate_point", global_position, LURE_HOLD)


func _burst() -> void:
	"""
	BEAT 2. The kimchi is ready: three red-orange waves and everything with a
	nose inside `BURST_RADIUS` bolts AWAY FROM THE JAR.

	`tracks_player` IS FALSE, and it is the whole point of the beat. The smell's
	source is a pot on the ground, not a hero — with it true, `_flee()` runs every
	body away from the LOCAL player instead, which on a peer replaying somebody
	else's jar means straight at the teammate who placed it
	(`piglet_crocodile_ai.flee_from()` spells out that exact failure).

	NOTHING IS CANCELLED HERE, on purpose. A body still walking toward the jar
	keeps walking, arrives at the cracked pot, sniffs the empty spot for its five
	seconds and goes home. That is the joke, and `_investigate_move()`'s stall
	watchdog already bounds a body that cannot get there at all.

	`ponytail:` the bounded group loop below is the third in this codebase
	(`PlayerAbilities._scare_crocodiles`, `MpWorldSync.apply_flee`) and it is a
	copy because the jar can reach neither: it has no player to hang the first on
	and it outlives the room the second belongs to. The ceiling is three copies of
	six lines that must keep agreeing about what "within radius" means — the
	upgrade is a shared static on the AI script itself, and it is a refactor, not
	this bead.
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
		fx.setup(BURST_COLOR, BURST_RADIUS, 0.9, i * 0.18)
	var radius_sq := BURST_RADIUS * BURST_RADIUS
	for body: Node in get_tree().get_nodes_in_group("crocodile"):
		if not is_instance_valid(body) or not (body is Node3D):
			continue
		if not body.has_method("flee_from"):
			continue
		if (body as Node3D).global_position.distance_squared_to(global_position) > radius_sq:
			continue
		# Every immunity is `flee_from()`'s and stays there: a boss shrugs it, a
		# `stink_immune` row (the guards — "fearless furniture") sniffs and stands,
		# and a slept body is left alone because it could never tick the flee down.
		body.call("flee_from", global_position, FLEE_DURATION, false)


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
	"""The one clock: ferment, crack, linger, free itself."""
	_age += delta
	if not _burst_done and _age >= FERMENT:
		_burst_done = true
		_burst()
	if _age >= FERMENT + LINGER:
		queue_free()
