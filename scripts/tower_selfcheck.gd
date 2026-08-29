extends SceneTree
## Headless self-check: **THE TOWER CANNOT SOFTLOCK.**
##
##   godot --headless --path . --script res://scripts/tower_selfcheck.gd
##
## Prints "SELFCHECK OK" and exits 0, or prints what failed and exits 1 — the shape
## the other three tower checks established. Epic godot-test1-3iy, phase 4, and the
## owner's ruling is that no wing of this building ships without it green.
##
## ============================================================================
## THE PROPERTY
## ============================================================================
##
## For every non-empty subset of FREE heroes, from every legal HQ entry, and in
## every persistent tower state reachable at that point, at least one route to a
## CELL is traversable using only the free heroes' guaranteed capabilities and no
## item held by a captive.
##
## Four heroes is fifteen subsets; add entries, story flags, scars and a growing
## pile of gates and the state space stops being something a human can hold. The
## failure it hides is the worst one a campaign has — a save that still runs, still
## looks right, and can never be finished — and it is invisible in every
## screenshot. That is the entire argument for a headless check.
##
## ============================================================================
## WHY FIFTEEN GRAPH WALKS ARE ENOUGH — and what this file must prove first
## ============================================================================
##
## The property quantifies over "every reachable tower state", which is
## combinatorial. `tower_graph.gd`'s three design laws collapse it, and THE LAWS
## ARE ASSERTED HERE STRUCTURALLY rather than believed:
##
##   * mutations are edge-ADDITIVE (check 2), so reachability is monotone in tower
##     state and the BASE graph — nothing opened yet — is the worst case;
##   * items have NO CUSTODY (check 2), so there is no "the key is in his pocket"
##     state to model at all;
##   * the four SPINES pass at the readiness floor (check 3), so every larger
##     subset follows by monotonicity as a union of its members' spines.
##
## Only then does the base graph mean anything, which is why checks 1-3 run before
## the walks. The walks (checks 5-7) enumerate all fifteen subsets anyway: fifteen
## breadth-first searches over a fourteen-room graph cost nothing, and they survive
## somebody rewriting the monotonicity argument above.
##
## ============================================================================
## WHAT IT GUARDS, check by check
## ============================================================================
##
##   1. **THE GRAPH IS THE TOWER THAT EXISTS.** A `TOWER_GRAPH` that has drifted
##      from `tower_interior.gd` is worse than no graph, because it certifies a
##      softlock as safe. So the correspondence is mechanical and BIDIRECTIONAL,
##      through the interior's own legibility colours: every box the building
##      paints in a gate colour must be claimed by exactly one gate here, and every
##      part a built gate claims must be a box the building really has. Nothing in
##      the graph is invented, and nothing in the building is unmodelled.
##   2. THE DESIGN LAWS, structurally: no gate keys on a hero's ABSENCE, every
##      mutation and every story overlay is edge-additive, no item has a carrier,
##      no quest requires another quest.
##   3. **THE FOUR SPINES AT THE READINESS FLOOR.** Not at current-save ranks: at
##      the rank budget the authored beat guarantees, which is what a player who
##      just walked into the beat actually has.
##   4. Demand gates are forecastable: each maps to a real `SKILL_TREES` effect at
##      a rank that is actually achievable, so "come back stronger" is true.
##   5. **THE FIFTEEN-SUBSET AUDIT**, per story-flag state, per scar state, per
##      legal entry. The check this file exists for.
##   6. `needed_during_captivity` is RECOMPUTED and compared to what the graph
##      claims — a comment that cannot rot.
##   7. Quest rooms are reachable by the full roster, quests are an open set, and
##      liberation at a cell needs nobody in particular.
##
## ============================================================================
## LANDMINES
## ============================================================================
##
## PURE GRAPH WALKING. Nothing here instances a scene, adds a node or runs a frame;
## `TowerInterior.boxes()` is static and the rest is dictionaries. A check that
## needed a running world could not be run on a graph whose rooms are not built
## yet — and phase 8's cell block, which this audit exists to constrain, is exactly
## that.
##
## THE AUDIT IS ALWAYS RUN AT ITS HARSHEST. Gates start CLOSED (nothing is assumed
## opened), spines are walked at the readiness floor and never at max ranks, and a
## mutation-granted entry is walked WITHOUT the edges that mutation adds. Every one
## of those is stricter than the game, and stricter is the only direction a
## softlock audit may err in.

const PLAYER_SCRIPT: String = "res://scripts/player_controller.gd"

## The interior's colours that mean "this box is part of a passage gate". Straight
## from the legibility language in `tower_interior.gd`'s header — hazard orange is a
## challenge, steel is a demand mechanism, violet is an identity mass and its pad.
## A box painted one of these IS a gate as far as the player is concerned, so the
## graph has to know about it.
var _gate_colors: Array[Color] = [
	TowerInterior.COLOR_HAZARD,
	TowerInterior.COLOR_MECHANISM,
	TowerInterior.COLOR_IDENTITY,
	TowerInterior.COLOR_IDENTITY_PAD,
]

## ...and the colours that mean "this box marks a room". A room's `parts` claim
## these the way a gate's claim the above: the checkpoint's green, and — from phase
## 8 — a cell's containment red. That second one is what fences the cell block in
## both directions: a fifth cell built into the wing and not authored here fails,
## and an authored cell whose frame nobody built fails too.
var _room_colors: Array[Color] = [
	TowerInterior.COLOR_CHECKPOINT,
	TowerInterior.COLOR_CELL,
]

## Keys a gate row may carry. A WHITELIST, because the law that matters here is a
## negative one — no gate may key on a hero's ABSENCE — and the only mechanical
## form of "no such key exists" is "these are the keys that do".
const GATE_KEYS: Array[String] = [
	"class", "identity", "effect", "scale", "needed_during_captivity",
	"built", "quest", "parts", "note",
]

## Keys a mutation row may carry. Design law 3 lives in this list: there is no
## `removes`, no `closes`, no `consumes`, so a subtractive mutation cannot be
## written without failing this check.
const MUTATION_KEYS: Array[String] = ["id", "trigger", "adds", "adds_entries", "note"]

## Keys a story-flag overlay may carry. Same law, same reason.
const STORY_KEYS: Array[String] = ["id", "captivity", "adds", "note"]

## Keys a scar row may carry. The ONE sanctioned exception, so `removes` is legal
## here and nowhere else.
const SCAR_KEYS: Array[String] = ["id", "removes", "note"]

## Keys an item row may carry. Design law 2: no `carrier`, no `hero`, no `held_by`.
const ITEM_KEYS: Array[String] = ["id", "scope", "room", "note"]

## Rank budgets a walk can be run at. FLOOR is what the beat guarantees and the only
## honest budget for a rescue route; MAX is what a completionist eventually has and
## the right budget for optional quest content.
const FLOOR: String = "floor"
const MAX: String = "max"

var _failures: Array[String] = []
var _graph: Dictionary = TowerGraph.TOWER_GRAPH


func _initialize() -> void:
	# No `await process_frame`: nothing here touches the tree. See LANDMINES.
	_check_graph_matches_the_building()
	_check_design_laws()
	_check_spines_at_the_readiness_floor()
	_check_demands_are_forecastable()
	_check_every_subset_reaches_a_cell()
	_check_captivity_flags_are_honest()
	_check_quests_and_liberation()
	_report()


# ============================================================================
# CHECK 1 — the graph is the tower that exists
# ============================================================================

func _check_graph_matches_the_building() -> void:
	"""
	Check 1. `TOWER_GRAPH` describes the building `tower_interior.gd` actually
	builds, in both directions.

	THIS IS THE CHECK THAT MAKES THE OTHER SIX WORTH RUNNING. Everything below
	reasons about gates as rows in a dictionary; if a row can exist without a gate,
	or a gate without a row, the audit is proving something about a tower nobody
	will ever walk. It would still print SELFCHECK OK.

	The binding is the interior's own LEGIBILITY COLOURS rather than a hand-kept
	list, because a colour is what the file is forced to choose for every gate it
	builds — the epic's rule is that hazard orange, steel and violet each mean one
	thing and are used for nothing else. So a gate cannot be added to the building
	without being painted, and a painted box that no graph row claims fails here.
	"""
	# --- the roster the whole audit is a power set of -----------------------
	var characters: Array = load(PLAYER_SCRIPT).get_script_constant_map().get("CHARACTERS", [])
	var names: Array[String] = []
	for entry: Dictionary in characters:
		names.append(String(entry.get("name", "")))
	if names != TowerGraph.HEROES:
		_fail(("TowerGraph.HEROES %s is not PlayerController.CHARACTERS %s — the subset audit "
			+ "would enumerate the wrong power set") % [str(TowerGraph.HEROES), str(names)])

	# --- structural well-formedness, so a walk cannot silently skip an edge --
	var rooms: Dictionary = _graph["rooms"]
	var gates: Dictionary = _graph["gates"]
	var seen_edges: Dictionary = {}
	var used_gates: Dictionary = {}
	for edge: Dictionary in _graph["edges"]:
		var eid := String(edge["id"])
		if seen_edges.has(eid):
			_fail("duplicate edge id '%s'" % eid)
		seen_edges[eid] = true
		for side: String in ["a", "b"]:
			if not rooms.has(String(edge[side])):
				_fail("edge '%s' joins '%s', which is not a room" % [eid, String(edge[side])])
		var gid := String(edge["gate"])
		if gid == "":
			continue
		if not gates.has(gid):
			_fail("edge '%s' is gated by '%s', which is not a gate" % [eid, gid])
			continue
		used_gates[gid] = true
		if bool(edge["built"]) and not bool(gates[gid]["built"]):
			_fail("edge '%s' is built but its gate '%s' is not" % [eid, gid])
		for side: String in ["a", "b"]:
			var rid := String(edge[side])
			if bool(edge["built"]) and rooms.has(rid) and not bool(rooms[rid]["built"]):
				_fail("edge '%s' is built but the room '%s' it reaches is not" % [eid, rid])
	for gid: String in gates:
		if not used_gates.has(gid):
			_fail("gate '%s' gates no edge — it is a row about nothing" % gid)

	# --- the colour binding, both directions --------------------------------
	var built_boxes: Dictionary = {}
	for box: Dictionary in TowerInterior.boxes():
		built_boxes[String(box["name"])] = box["color"]

	# Every part any row claims must be a box the building really has, and an
	# UNBUILT row must claim nothing — a graph that credits itself with geometry
	# nobody built is the exact drift this check exists to catch.
	var claimed: Dictionary = {}
	var claimants: Array[Array] = []
	for gid: String in gates:
		claimants.append(["gate '%s'" % gid, gates[gid]])
	for rid: String in rooms:
		claimants.append(["room '%s'" % rid, rooms[rid]])
	for pair: Array in claimants:
		var label: String = pair[0]
		var row: Dictionary = pair[1]
		var parts: Array = row.get("parts", [])
		if not bool(row["built"]):
			if not parts.is_empty():
				_fail("%s is authored but not built, yet claims interior boxes %s" % [
					label, str(parts)])
			continue
		for part: String in parts:
			if not built_boxes.has(part):
				_fail("%s claims interior box '%s', which TowerInterior.boxes() does not build" % [
					label, part])
				continue
			if claimed.has(part):
				_fail("interior box '%s' is claimed by both %s and %s" % [
					part, claimed[part], label])
			claimed[part] = label

	# ...and every box the building paints in a gate or marker colour must be
	# claimed. THIS is the direction that catches a gate added to the tower and not
	# to the graph — the audit would otherwise walk straight through it.
	for box_name: String in built_boxes:
		var color: Color = built_boxes[box_name]
		if not (_gate_colors.has(color) or _room_colors.has(color)):
			continue
		if not claimed.has(box_name):
			_fail("interior box '%s' is painted a gate colour but no TOWER_GRAPH row claims it "
				% box_name + "— the audit does not know this gate exists")

	# --- the two numbers the building and the graph both hold ---------------
	var demand: Dictionary = TowerGraph.gate(TowerGraph.GATE_DEMAND)
	if not is_equal_approx(float(demand.get("scale", 0.0)), TowerInterior.DEMAND_TARGET):
		_fail("the graph's demand gate asks %.4f, the building asks %.4f" % [
			float(demand.get("scale", 0.0)), TowerInterior.DEMAND_TARGET])
	var blink_base: float = float(
		load(PLAYER_SCRIPT).get_script_constant_map().get("PRIMM_BLINK_DISTANCE", 0.0))
	var declared: float = float(TowerGraph.EFFECT_BASE["primm_blink"]["base"])
	if not is_equal_approx(declared, blink_base):
		_fail("EFFECT_BASE says primm_blink starts at %.4f, PRIMM_BLINK_DISTANCE is %.4f" % [
			declared, blink_base])

	# The checkpoint is a MARKER, not a passage: it goes in the opened set and opens
	# nothing, so it must never appear as a gate on an edge.
	if gates.has(TowerGraph.GATE_CHECKPOINT):
		_fail("'%s' is a room marker, not a passage — it must not be a gate row" % [
			TowerGraph.GATE_CHECKPOINT])


# ============================================================================
# CHECK 2 — the three design laws, structurally
# ============================================================================

func _check_design_laws() -> void:
	"""
	Check 2. The laws that let fifteen walks stand in for the whole state space.

	Each is enforced as a KEY WHITELIST, which is the only mechanical form a
	negative law has: you cannot check that nobody ever writes `"removes"` on a
	mutation, but you can check that a mutation carries none but five known keys.
	A row that grows a sixth fails here, loudly, with the key named.
	"""
	# --- law: no gate keys on a hero's ABSENCE ------------------------------
	for gid: String in _graph["gates"]:
		var g: Dictionary = _graph["gates"][gid]
		_whitelist("gate '%s'" % gid, g, GATE_KEYS)
		var cls := String(g.get("class", ""))
		if cls not in [TowerGraph.CLASS_CHALLENGE, TowerGraph.CLASS_IDENTITY,
				TowerGraph.CLASS_DEMAND]:
			_fail("gate '%s' has class '%s', which is none of the three verbs" % [gid, cls])
		var who := String(g.get("identity", ""))
		if cls == TowerGraph.CLASS_IDENTITY:
			if who not in TowerGraph.HEROES:
				_fail("identity gate '%s' asks for '%s', who is not a hero" % [gid, who])
		elif who != "":
			_fail("gate '%s' is a %s gate but names a hero ('%s')" % [gid, cls, who])

	# --- law: mutations are edge-ADDITIVE ----------------------------------
	var edge_ids: Dictionary = {}
	for edge: Dictionary in _graph["edges"]:
		edge_ids[String(edge["id"])] = true
	var entry_ids: Dictionary = {}
	for entry: Dictionary in _graph["entries"]:
		entry_ids[String(entry["id"])] = true
	for mut: Dictionary in _graph["mutations"]:
		var mid := String(mut.get("id", "?"))
		_whitelist("mutation '%s'" % mid, mut, MUTATION_KEYS)
		if mut.get("adds", []).is_empty() and mut.get("adds_entries", []).is_empty():
			_fail("mutation '%s' adds nothing — a route transformation that transforms no route" % mid)
		for eid: String in mut.get("adds", []):
			if not edge_ids.has(eid):
				_fail("mutation '%s' adds edge '%s', which is not in the graph" % [mid, eid])
		for eid2: String in mut.get("adds_entries", []):
			if not entry_ids.has(eid2):
				_fail("mutation '%s' grants entry '%s', which is not in the graph" % [mid, eid2])

	# --- law: story overlays are additive too ------------------------------
	for story: Dictionary in _graph["story_states"]:
		_whitelist("story state '%s'" % String(story.get("id", "?")), story, STORY_KEYS)
		for eid3: String in story.get("adds", []):
			if not edge_ids.has(eid3):
				_fail("story state '%s' adds edge '%s', which is not in the graph" % [
					String(story.get("id", "?")), eid3])

	# --- the ONE sanctioned exception, kept enumerated ---------------------
	for scar: Dictionary in _graph["scars"]:
		_whitelist("scar '%s'" % String(scar.get("id", "?")), scar, SCAR_KEYS)
		for eid4: String in scar.get("removes", []):
			if not edge_ids.has(eid4):
				_fail("scar '%s' removes edge '%s', which is not in the graph" % [
					String(scar.get("id", "?")), eid4])

	# --- law: no item custody ----------------------------------------------
	for item: Dictionary in _graph["items"]:
		var iid := String(item.get("id", "?"))
		_whitelist("item '%s'" % iid, item, ITEM_KEYS)
		if String(item.get("scope", "")) != "party":
			_fail("item '%s' has scope '%s' — every item is party-level world state, or this "
				% [iid, String(item.get("scope", ""))]
				+ "audit needs a custody model it does not have")

	# --- quests are an open set --------------------------------------------
	for quest: Dictionary in _graph["quests"]:
		if String(quest.get("requires_quest", "")) != "":
			_fail("quest '%s' requires quest '%s' — quests are an open set, and a chain is a "
				% [String(quest["id"]), String(quest["requires_quest"])]
				+ "second way to strand a player that the subset audit cannot see")


func _whitelist(label: String, row: Dictionary, allowed: Array[String]) -> void:
	"""Fail naming any key `row` carries that `allowed` does not permit."""
	for key: String in row.keys():
		if not allowed.has(key):
			_fail("%s carries the key '%s', which the design law does not permit "
				% [label, key] + "(allowed: %s)" % str(allowed))


# ============================================================================
# CHECK 3 — the four spines, at the readiness floor
# ============================================================================

func _check_spines_at_the_readiness_floor() -> void:
	"""
	Check 3. Each hero's rescue spine is a real path, and he can walk it ALONE at
	the rank budget the authored beat guarantees.

	THE RANK BUDGET IS THE POINT. Systemic capture arms only after the beat, so the
	beat's readiness floor IS the spine's budget — and it is read out of
	`readiness_floor` rather than restated here, so the day somebody authors a beat
	that grants less, this fails instead of the player's save quietly becoming
	unfinishable. Current-save ranks are the wrong budget for the same reason a
	tutorial cannot assume you have played the tutorial.

	Empty ranks is the strictest case and is what the floor says today: every spine
	must be walkable on base capability alone.
	"""
	var by_id: Dictionary = {}
	for edge: Dictionary in _graph["edges"]:
		by_id[String(edge["id"])] = edge
	var entries: Dictionary = {}
	for entry: Dictionary in _graph["entries"]:
		entries[String(entry["id"])] = entry

	# The floor is the budget every spine below is walked at, so it is validated
	# before it is spent: a typo'd skill id grants nothing silently, which is the
	# safe direction but still an authoring bug, and a rank over the node's own
	# `max_ranks` is a promise the tree cannot keep.
	for hero: String in _graph["readiness_floor"]:
		if not TowerGraph.HEROES.has(hero):
			_fail("the readiness floor budgets ranks for '%s', who is not a hero" % hero)
			continue
		var caps: Dictionary = {}
		for node: Dictionary in Progression.SKILL_TREES.get(hero, []):
			caps[String(node["id"])] = int(node.get("max_ranks", 0))
		for skill_id: String in _graph["readiness_floor"][hero]:
			if not caps.has(skill_id):
				_fail("the readiness floor grants %s rank in '%s', which is not a node in his "
					% [hero, skill_id] + "skill tree — the beat would guarantee nothing")
			elif int(_graph["readiness_floor"][hero][skill_id]) > caps[skill_id]:
				_fail("the readiness floor grants %s %d ranks of '%s', which caps at %d" % [
					hero, int(_graph["readiness_floor"][hero][skill_id]), skill_id,
					caps[skill_id]])
	for hero2: String in TowerGraph.HEROES:
		if not _graph["readiness_floor"].has(hero2):
			_fail("the readiness floor says nothing about %s — write {} to mean base kit, "
				% hero2 + "so the silence is deliberate rather than forgotten")

	for spine_hero: String in _graph["spines"]:
		if not TowerGraph.HEROES.has(spine_hero):
			_fail("a rescue spine is authored for '%s', who is not a hero" % spine_hero)

	for hero: String in TowerGraph.HEROES:
		if not _graph["spines"].has(hero):
			_fail("no rescue spine is authored for %s — one of the four is missing" % hero)
			continue
		var spine: Dictionary = _graph["spines"][hero]
		var entry_id := String(spine["entry"])
		if not entries.has(entry_id):
			_fail("%s's spine starts at entry '%s', which is not a legal entry" % [hero, entry_id])
			continue
		var here := String(entries[entry_id]["room"])
		var free: Array[String] = [hero]
		for eid: String in spine["edges"]:
			if not by_id.has(eid):
				_fail("%s's spine walks edge '%s', which is not in the graph — the spine is severed"
					% [hero, eid])
				here = ""
				break
			var edge: Dictionary = by_id[eid]
			var far := _across(edge, here)
			if far == "":
				_fail("%s's spine is not a path: edge '%s' joins %s and %s, but the walk is at %s"
					% [hero, eid, String(edge["a"]), String(edge["b"]), here])
				here = ""
				break
			var gid := String(edge["gate"])
			if not _passable(gid, free, FLOOR):
				_fail("%s's spine is blocked at its own gate: edge '%s' gate '%s' (%s) is not "
					% [hero, eid, gid, _gate_words(gid)]
					+ "passable by %s alone at the readiness floor %s" % [
						hero, str(_graph["readiness_floor"].get(hero, {}))])
				here = ""
				break
			here = far
		if here == "":
			continue
		# A spine has to end somewhere a rescue can happen.
		var cells := TowerGraph.cells()
		var reached_cell := cells.has(here)
		if not reached_cell:
			for edge2: Dictionary in _graph["edges"]:
				if String(edge2["gate"]) != "":
					continue
				if _across(edge2, here) in cells:
					reached_cell = true
					break
		if not reached_cell:
			_fail("%s's spine ends at '%s', from which no cell is one open door away" % [hero, here])


# ============================================================================
# CHECK 4 — demand gates are forecastable
# ============================================================================

func _check_demands_are_forecastable() -> void:
	"""
	Check 4. Every demand gate measures a REAL `SKILL_TREES` effect and asks for a
	reading that is actually achievable.

	"Come back stronger" is a promise, and a gate calibrated above the tree's own
	ceiling is a wall wearing a number — the exact failure the epic's legibility
	ruling forbids. The ceiling is computed from the tree rather than restated, so
	retuning a skill node moves the verdict with it.
	"""
	for gid: String in _graph["gates"]:
		var g: Dictionary = _graph["gates"][gid]
		if String(g["class"]) != TowerGraph.CLASS_DEMAND:
			if String(g.get("effect", "")) != "" or not is_zero_approx(float(g.get("scale", 0.0))):
				_fail("gate '%s' is not a demand gate but carries an effect/scale" % gid)
			continue
		var effect := String(g["effect"])
		if not TowerGraph.EFFECT_BASE.has(effect):
			_fail("demand gate '%s' measures '%s', which EFFECT_BASE cannot value" % [gid, effect])
			continue
		var owners := _owners(effect)
		if owners.is_empty():
			_fail("demand gate '%s' measures '%s', which appears in no hero's SKILL_TREES — it "
				% [gid, effect] + "demands a capability the game does not have")
			continue
		var scale := float(g["scale"])
		var best := 0.0
		var reachable_by: Array[String] = []
		for hero: String in owners:
			var reading := _reading(hero, effect, MAX)
			best = maxf(best, reading)
			if _meets(reading, scale):
				reachable_by.append(hero)
		if reachable_by.is_empty():
			_fail("demand gate '%s' asks for %.4f but the best any hero reaches at MAX ranks is "
				% [gid, scale] + "%.4f — it is a wall, not a demand" % best)
		# ...and the other end of the same promise: a gate the whole roster already
		# satisfies at the floor is a door with a number painted on it.
		var everyone := owners.size() == TowerGraph.HEROES.size()
		for hero2: String in owners:
			everyone = everyone and _meets(_reading(hero2, effect, FLOOR), scale)
		if everyone:
			_fail("demand gate '%s' is met by every hero at the readiness floor — it demands nothing"
				% gid)


# ============================================================================
# CHECK 5 — the fifteen-subset audit
# ============================================================================

func _check_every_subset_reaches_a_cell() -> void:
	"""
	Check 5. THE PROPERTY. Per story-flag state, per scar state, per legal entry,
	per non-empty free-hero subset: a cell holding a captive is reachable using only
	the free heroes' floor-rank capabilities.

	Captives are exactly the heroes NOT in the subset, and because the walk only
	ever uses the free set's capabilities, a captive can never open a gate on the
	way to his own cell — the rule falls out of the traversal rather than needing a
	special case.

	WORST-CASE BY CONSTRUCTION: no gate is assumed opened, no mutation is assumed
	fired, and a mutation-granted entry (the lift stop) is walked WITHOUT the edges
	that mutation adds. Every one of those is harsher than the running game.

	Story states with no captivity have no cell clause; check 7 still holds them to
	quest reachability, so the state is not skipped, only narrowed.
	"""
	for story: Dictionary in _graph["story_states"]:
		if not bool(story["captivity"]):
			continue
		for scar: Dictionary in _graph["scars"]:
			var edges := _edges_for(story, scar)
			for entry: Dictionary in _all_entries():
				for free: Array in _subsets():
					var typed: Array[String] = []
					for h: String in free:
						typed.append(h)
					_audit_one(story, scar, entry, typed, edges)


func _audit_one(story: Dictionary, scar: Dictionary, entry: Dictionary,
		free: Array[String], edges: Array) -> void:
	"""One walk. Fails naming the case, the subset and what stopped it."""
	var targets := _captive_cells(free)
	if targets.is_empty():
		return  # nobody is captive: no rescue to make.
	var seen := _reach(edges, String(entry["room"]), free, FLOOR, "")
	for cell: String in targets:
		if seen.has(cell):
			return
	# Name the gate. The blockers are the impassable gates on the frontier — the
	# doors this subset stood in front of and could not open, which is the sentence
	# a designer can act on.
	var blockers: Dictionary = {}
	for edge: Dictionary in edges:
		var a := String(edge["a"])
		var b := String(edge["b"])
		if seen.has(a) == seen.has(b):
			continue
		var gid := String(edge["gate"])
		if gid != "" and not _passable(gid, free, FLOOR):
			blockers[gid] = _gate_words(gid)
	var words: Array[String] = []
	for gid2: String in blockers:
		words.append("'%s' (%s)" % [gid2, blockers[gid2]])
	_fail(("SOFTLOCK: free heroes %s (captive: %s), entering at '%s', story '%s', scar '%s' — "
		+ "no cell is reachable at the readiness floor. Blocked by %s.") % [
			str(free), str(_captives(free)), String(entry["id"]),
			String(story["id"]), String(scar["id"]),
			"nothing passable at all" if words.is_empty() else ", ".join(words)])


# ============================================================================
# CHECK 6 — the captivity flags are honest
# ============================================================================

func _check_captivity_flags_are_honest() -> void:
	"""
	Check 6. `needed_during_captivity` is RECOMPUTED, not trusted.

	A gate is needed during captivity when there is some (story, scar, entry,
	subset) case in which removing it strands that subset — i.e. it lies on every
	route to a cell. That is a small brute force over a tiny graph, and it turns a
	comment that would rot into a claim the build checks.

	It also earns its keep going forward: a gate that BECOMES necessary because
	somebody deleted the redundant way round shows up here as a flag disagreement
	long before it shows up as a bug report.
	"""
	var necessary: Dictionary = {}
	for story: Dictionary in _graph["story_states"]:
		if not bool(story["captivity"]):
			continue
		for scar: Dictionary in _graph["scars"]:
			var edges := _edges_for(story, scar)
			for entry: Dictionary in _all_entries():
				for free_any: Array in _subsets():
					var free: Array[String] = []
					for h: String in free_any:
						free.append(h)
					var targets := _captive_cells(free)
					if targets.is_empty():
						continue
					if not _reaches_any(edges, entry, free, targets, ""):
						continue  # already failed in check 5; do not double-report
					for gid: String in _graph["gates"]:
						if necessary.has(gid):
							continue
						if not _reaches_any(edges, entry, free, targets, gid):
							necessary[gid] = "%s from '%s' under scar '%s'" % [
								str(free), String(entry["id"]), String(scar["id"])]

	for gid2: String in _graph["gates"]:
		var claimed := bool(_graph["gates"][gid2]["needed_during_captivity"])
		var real := necessary.has(gid2)
		if claimed and not real:
			_fail("gate '%s' claims needed_during_captivity, but no subset in any state depends "
				% gid2 + "on it — the flag is stale")
		elif real and not claimed:
			_fail("gate '%s' is NOT flagged needed_during_captivity, but %s cannot reach a cell "
				% [gid2, necessary[gid2]] + "without it")


# ============================================================================
# CHECK 7 — quest rooms, the open set, and liberation
# ============================================================================

func _check_quests_and_liberation() -> void:
	"""
	Check 7. The full roster reaches every room worth reaching; each quest is
	solo-completable by somebody; and a cell needs nobody in particular to open.

	QUEST CONTENT IS AUDITED AT MAX RANKS, rescue routes at the floor, and the
	split is deliberate: the vault is optional and forecastable ("come back
	stronger" is a real answer), while a rescue route must work for the player who
	just walked into the beat with nothing.
	"""
	var full: Array[String] = TowerGraph.HEROES.duplicate()
	var all_rooms: Dictionary = _graph["rooms"]
	for story: Dictionary in _graph["story_states"]:
		for scar: Dictionary in _graph["scars"]:
			var edges := _edges_for(story, scar)
			for entry: Dictionary in _all_entries():
				var seen := _reach(edges, String(entry["room"]), full, MAX, "")
				for rid: String in all_rooms:
					if seen.has(rid):
						continue
					_fail("the FULL ROSTER at max ranks cannot reach room '%s' from entry '%s' "
						% [rid, String(entry["id"])]
						+ "(story '%s', scar '%s')" % [String(story["id"]), String(scar["id"])])

	# Each quest solo-completable by at least one hero, somewhere in the tree.
	var base_edges := _edges_for(_graph["story_states"][0], _graph["scars"][0])
	for quest: Dictionary in _graph["quests"]:
		var room := String(quest["room"])
		if not all_rooms.has(room):
			_fail("quest '%s' happens in '%s', which is not a room" % [String(quest["id"]), room])
			continue
		var solo := false
		for entry: Dictionary in _all_entries():
			if not bool(entry["built"]):
				continue  # a quest may not depend on an entry nobody can use yet.
			for hero: String in TowerGraph.HEROES:
				if _reach(base_edges, String(entry["room"]), [hero], MAX, "").has(room):
					solo = true
					break
		if not solo:
			_fail("quest '%s' is completable by no hero alone at any rank — it needs a party, "
				% String(quest["id"]) + "which a captive roster may not have")

	# Liberation: a cell hangs off its gallery on an OPEN edge, so whoever got there
	# can perform it. Nothing about a cell may ask who you are.
	var cells := TowerGraph.cells()
	var by_hero: Dictionary = {}
	for cell: String in cells:
		var who := String(all_rooms[cell]["cell"])
		if by_hero.has(who):
			_fail("two cells claim %s: '%s' and '%s'" % [who, by_hero[who], cell])
		by_hero[who] = cell
		var open_ways := 0
		for edge: Dictionary in _graph["edges"]:
			if String(edge["gate"]) == "" and (String(edge["a"]) == cell or String(edge["b"]) == cell):
				open_ways += 1
		if open_ways == 0:
			_fail("cell '%s' has no ungated door — liberation there is not performable by any "
				% cell + "single hero, which is what uniform cells promise")
	for hero2: String in TowerGraph.HEROES:
		if not by_hero.has(hero2):
			_fail("no cell is authored for %s — a captive with no cell can never be freed" % hero2)


# ============================================================================
# THE WALKER — pure graph, no world
# ============================================================================

func _edges_for(story: Dictionary, scar: Dictionary) -> Array:
	"""
	The edge set to walk in this (story, scar) state.

	THE BASE GRAPH, plus the story overlay's additions, minus the scar's removals.
	Mutation-added edges are deliberately LEFT OUT: mutations are additive (law 3,
	asserted in check 2), so the un-mutated graph is the worst case and walking it
	is strictly harsher than the game.
	"""
	var added: Dictionary = {}
	for mut: Dictionary in _graph["mutations"]:
		for eid: String in mut.get("adds", []):
			added[eid] = true
	var overlay: Dictionary = {}
	for eid2: String in story.get("adds", []):
		overlay[eid2] = true
	var removed: Dictionary = {}
	for eid3: String in scar.get("removes", []):
		removed[eid3] = true

	var out: Array = []
	for edge: Dictionary in _graph["edges"]:
		var eid4 := String(edge["id"])
		if removed.has(eid4):
			continue
		if added.has(eid4) and not overlay.has(eid4):
			continue
		out.append(edge)
	return out


func _all_entries() -> Array:
	"""
	Every LEGAL entry: the ones that exist from the start plus every one a mutation
	can grant. The rule quantifies over all of them, so a new lift stop is a new
	fifteen-subset audit the day its row lands.
	"""
	var granted: Dictionary = {}
	for mut: Dictionary in _graph["mutations"]:
		for eid: String in mut.get("adds_entries", []):
			granted[eid] = true
	var out: Array = []
	for entry: Dictionary in _graph["entries"]:
		if bool(entry["built"]) or granted.has(String(entry["id"])):
			out.append(entry)
	return out


func _reach(edges: Array, start: String, free: Array[String], mode: String,
		skip_gate: String) -> Dictionary:
	"""
	Breadth-first over the passages this free set can actually get through.

	@param skip_gate: a gate id to treat as impassable, for check 6's necessity
	                  probe. "" for an ordinary walk.
	@return: room id -> true, for every room reached.
	"""
	var seen: Dictionary = {start: true}
	var queue: Array[String] = [start]
	while not queue.is_empty():
		var here: String = queue.pop_back()
		for edge: Dictionary in edges:
			var far := _across(edge, here)
			if far == "" or seen.has(far):
				continue
			var gid := String(edge["gate"])
			if gid != "" and (gid == skip_gate or not _passable(gid, free, mode)):
				continue
			seen[far] = true
			queue.append(far)
	return seen


func _reaches_any(edges: Array, entry: Dictionary, free: Array[String],
		targets: Array[String], skip_gate: String) -> bool:
	"""True when at least one target room is reachable from `entry` at floor rank."""
	var seen := _reach(edges, String(entry["room"]), free, FLOOR, skip_gate)
	for room: String in targets:
		if seen.has(room):
			return true
	return false


func _across(edge: Dictionary, here: String) -> String:
	"""The far end of `edge` from `here`, or "" when `edge` does not touch it."""
	if String(edge["a"]) == here:
		return String(edge["b"])
	if String(edge["b"]) == here:
		return String(edge["a"])
	return ""


func _passable(gate_id: String, free: Array[String], mode: String) -> bool:
	"""
	Can this free set get through this gate, with nothing assumed opened?

	ONE RULE PER GATE CLASS, and they are the epic's three verbs:

	  * challenge — the base kit beats it, so anybody does. (A challenge that needed
	    a rank would be a demand gate painted the wrong colour; check 2 refuses one.)
	  * identity  — only while its hero is free. The one class that can strand a
	    subset, which is why every one of them is a suspect in check 5.
	  * demand    — some free hero must read `scale` on `effect`. Only heroes whose
	    SKILL_TREES carry that effect can read it at all, so a hero-specific demand
	    (`primm_blink`) requires that hero exactly as an identity gate would. That
	    equivalence is derived from the trees, never authored twice.
	"""
	if gate_id == "":
		return true
	var g := TowerGraph.gate(gate_id)
	if g.is_empty():
		return false  # an unknown gate is impassable; check 1 has already failed.
	match String(g["class"]):
		TowerGraph.CLASS_CHALLENGE:
			return true
		TowerGraph.CLASS_IDENTITY:
			return free.has(String(g["identity"]))
		TowerGraph.CLASS_DEMAND:
			var effect := String(g["effect"])
			for hero: String in _owners(effect):
				if free.has(hero) and _meets(_reading(hero, effect, mode), float(g["scale"])):
					return true
			return false
	return false


func _owners(effect: String) -> Array[String]:
	"""
	Which heroes can produce a reading for this effect at all — i.e. whose skill tree
	carries a node with it. Derived from `SKILL_TREES`, which is what makes
	"a hero-specific demand requires that hero" a fact rather than an annotation.
	"""
	var out: Array[String] = []
	for hero: String in TowerGraph.HEROES:
		for node: Dictionary in Progression.SKILL_TREES.get(hero, []):
			if String(node.get("effect", "")) == effect:
				out.append(hero)
				break
	return out


func _reading(hero: String, effect: String, mode: String) -> float:
	"""
	What this hero measures on this effect, at the floor budget or at max ranks.

	`base * (1 + sum(per_rank * rank))` — `Progression.skill_bonus()`'s own
	arithmetic, run over authored ranks instead of a live save, because the whole
	point of the floor is that no save exists yet.
	"""
	var base: float = float(TowerGraph.EFFECT_BASE.get(effect, {}).get("base", 0.0))
	var floor_ranks: Dictionary = _graph["readiness_floor"].get(hero, {})
	var bonus := 0.0
	for node: Dictionary in Progression.SKILL_TREES.get(hero, []):
		if String(node.get("effect", "")) != effect:
			continue
		var rank := (int(node.get("max_ranks", 0)) if mode == MAX
			else int(floor_ranks.get(String(node["id"]), 0)))
		bonus += float(node.get("per_rank", 0.0)) * float(rank)
	return base * (1.0 + bonus)


func _meets(reading: float, scale: float) -> bool:
	"""
	Does this reading satisfy that demand? `TowerInterior.DEMAND_TOLERANCE`, not a
	bare `>=`, and for the reason written at that constant: one rank of Long Step is
	7.199999999999999 in IEEE 754, and a gate that refuses the exact rank it
	advertises is the most confusing failure this feature can have.
	"""
	return reading + TowerInterior.DEMAND_TOLERANCE >= scale


func _subsets() -> Array:
	"""The fifteen non-empty free-hero subsets, smallest first."""
	var out: Array = []
	for size in range(1, TowerGraph.HEROES.size() + 1):
		for mask in range(1, 1 << TowerGraph.HEROES.size()):
			var picked: Array[String] = []
			for i in TowerGraph.HEROES.size():
				if mask & (1 << i):
					picked.append(TowerGraph.HEROES[i])
			if picked.size() == size:
				out.append(picked)
	return out


func _captives(free: Array[String]) -> Array[String]:
	"""Exactly the heroes not free."""
	var out: Array[String] = []
	for hero: String in TowerGraph.HEROES:
		if not free.has(hero):
			out.append(hero)
	return out


func _captive_cells(free: Array[String]) -> Array[String]:
	"""The cells that actually hold somebody, given this free set."""
	var out: Array[String] = []
	for cell: String in TowerGraph.cells():
		if not free.has(String(_graph["rooms"][cell]["cell"])):
			out.append(cell)
	return out


func _gate_words(gate_id: String) -> String:
	"""A human sentence for a gate, so a failure names what to go and look at."""
	var g := TowerGraph.gate(gate_id)
	if g.is_empty():
		return "unknown gate"
	match String(g["class"]):
		TowerGraph.CLASS_IDENTITY:
			return "identity gate, needs %s" % String(g["identity"])
		TowerGraph.CLASS_DEMAND:
			return "demand gate, needs %s >= %.2f" % [String(g["effect"]), float(g["scale"])]
	return "challenge gate, base kit"


# ============================================================================
# VERDICT
# ============================================================================

func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		print("tower graph: %d rooms, %d edges, %d gates, %d entries, %d scars — %d subset walks clean"
			% [_graph["rooms"].size(), _graph["edges"].size(), _graph["gates"].size(),
				_all_entries().size(), _graph["scars"].size(), _subsets().size()])
		print("SELFCHECK OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	quit(1)
