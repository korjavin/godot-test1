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
##      the graph is invented, and nothing in the building is unmodelled. From
##      phase 14 the same correspondence covers the storeys drawn as ASCII in
##      `tower_plans.gd`: every letter on a floor plan names a built room row,
##      every room row a plan claims is drawn on exactly one floor, every `D` cell
##      is a real gate, and the graph joins the whole storey to its landing.
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
##   8. **EVERY AUTHORED SCAR IS ONE THE BUILDING CAN INFLICT.** Checks 2 and 5
##      prove a scar is safe; only this one asks whether it HAPPENS. A `removes`
##      row no box implements is a passage the audit believes is gone and the
##      player finds standing open — the sanctioned exception, shipped inert.
##   9. **THE GRID FLOOD-FILL** (phase 14). Checks 1-8 walk a graph, and a graph
##      cannot see a corridor that was never drawn: one `.` typed as a `#` in a
##      doorway leaves every one of them green and the floor in two sealed halves.
##      So every storey in `tower_plans.gd` is flood-filled 4-connected from its
##      landing, its ramp lane is checked against the storey it stands on, and its
##      slope against the phase-3 ramp — with a negative control per assertion.
##
## ============================================================================
## LANDMINES
## ============================================================================
##
## PURE GRAPH WALKING. Nothing here instances a scene, adds a node or runs a frame;
## `TowerInterior.all_boxes()` is static and the rest is dictionaries. A check that
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
	# ...and phase 15's indigo, which is the mass of a riddle and nothing else. The
	# lock's four pad colours are deliberately NOT here: a pad is bound to its gate
	# by the plan's own `gates` dict, in both directions, which is a tighter binding
	# than a colour and the only one that can span two storeys.
	TowerInterior.COLOR_RIDDLE,
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
## `clue_room` and `answer` are on the list because a RIDDLE carries them; the
## optional `geometry` key is the narrow secure-door mass exception, and check 2
## rejects it on every other row. The whitelist stays what it is for — the only
## mechanical form of "no such key exists".
const GATE_KEYS: Array[String] = [
	"class", "identity", "geometry", "effect", "scale", "needed_during_captivity",
	"built", "quest", "parts", "note", "clue_room", "answer",
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

## THERE IS NO EXEMPTION LIST ANY MORE, and its absence is the demolition's
## receipt. `KEEP_ROOMS` used to name the six rooms the phase-3 keep drew from its
## own box table (`entry_hall`, `outer_hall`, `courtyard`, `upper_landing`, `vault`,
## `checkpoint_room`) — the complete list of built rooms no ASCII plan lettered, and
## the only rooms check 1 let go undrawn. Bead `godot-test1-dn8` drew floors 0 and 1
## on the grid, so every built room is now claimed by exactly one storey and the
## rule below is total: a room nothing draws is a room the grid checks cannot see,
## so every edge it carries is silently skipped by check 14 — which is what
## `s5_stairhead` cost before phase 16 merged it away.

## Rank budgets a walk can be run at. FLOOR is what the beat guarantees and the only
## honest budget for a rescue route; MAX is what a completionist eventually has and
## the right budget for optional quest content.
const FLOOR: String = "floor"
const MAX: String = "max"

var _failures: Array[String] = []
var _graph: Dictionary = TowerGraph.TOWER_GRAPH

## The walker's two memos, both keyed "<story id>|<scar id>" — see `_edges_for` and
## `_index_for`. The state pair is the outer loop of every walking check, so the
## edge set and its adjacency index are each built once per state and then reused
## across every entry and all fifteen subsets.
var _edges_cache: Dictionary = {}
var _index_cache: Dictionary = {}

## Check 9's one line, held until `_report` so the summary reads in one block.
var _plan_summary: String = ""

## `_ungated_components`' memo — a property of the shipped graph, so it is built
## once and read by every storey's gates-shut fill.
var _ungated_cache: Dictionary = {}


## THE END-OF-CHECK SENTINEL. A GDScript runtime error aborts the FUNCTION it
## lands in and lets the script carry on, so a check that dies halfway simply
## stops asserting and this file prints "SELFCHECK OK". Every check below stamps
## itself at its exit; the report site asks whether every stamp was reached.
## `scripts/selfcheck_sentinel.gd` carries the whole reasoning.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")


func _initialize() -> void:
	# No `await process_frame`: nothing here touches the tree. See LANDMINES.
	_check_graph_matches_the_building()
	_check_design_laws()
	_check_spines_at_the_readiness_floor()
	_check_demands_are_forecastable()
	_check_every_subset_reaches_a_cell()
	_check_captivity_flags_are_honest()
	_check_quests_and_liberation()
	_check_scars_are_built()
	_check_plans_are_walkable()
	_check_riddles_are_answerable()
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
	# `all_boxes()` and not `boxes()`: from phase 14 the building is the authored
	# keep PLUS every hand-planned storey, and a gate painted onto a plan storey has
	# to be claimed by a row exactly like one built into the keep. (No storey drawn
	# in this phase paints one — that is the point. This check is the reason it
	# stays true when phase 15 starts drawing riddles up there.)
	var built_boxes: Dictionary = {}
	for box: Dictionary in TowerInterior.all_boxes():
		var box_id := String(box["name"])
		if built_boxes.has(box_id):
			_fail("two interior boxes are both named '%s' — the keep and every plan storey "
				% box_id + "share one namespace, and a row claiming that name claims neither")
		built_boxes[box_id] = box["color"]

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
				_fail("%s claims interior box '%s', which TowerInterior.all_boxes() does not build" % [
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

	# --- and the same correspondence for the storeys drawn as text ----------
	_check_plans_bind_to_the_graph()
	Sentinel.done("graph_matches_the_building")


func _check_plans_bind_to_the_graph() -> void:
	"""
	Check 1, phase 14: every hand-planned storey and `TOWER_GRAPH` are the same
	building — in both directions, and in both alphabets.

	A storey is DRAWN as ASCII (`tower_plans.gd`) and WALKED as a graph, and neither half can see the other's drift on its own. The graph cannot
	see a room lettered on no floor; the ASCII cannot see a room the audit walks
	through that nobody ever drew. Both are the same failure this check exists for —
	an audit reasoning about a building the player is not standing in.

	Four bindings, all mechanical:

	  * every id a plan names (its `rooms` values and its `landing`) is a BUILT
	    room row, and every id is claimed by exactly ONE storey — a room is on one
	    floor. The other way too: every built room is drawn by SOME storey, with no
	    exemptions left since the keep was demolished, because a room nothing draws
	    is a room check 14 skips every edge of;
	  * every letter drawn on the grid is in that storey's `rooms` dict, and every
	    `rooms` entry is drawn somewhere on the grid;
	  * every `D` cell's `"<c>,<r>"` key is in `gates` and names a real gate row,
	    and every `gates` key names a `D` cell. No storey authored in this phase has
	    one; the check is what makes phase 15's riddles cheap and what stops a `D`
	    being drawn and forgotten;
	  * the GRAPH agrees the storey hangs together: one walk from the landing with
	    the whole roster free reaches every room the storey claims. That is the
	    graph half of the question; the flood-fill over the same grid is the
	    geometry half, and together they are what "the graph the audit walks IS
	    what the player walks" means.
	"""
	var rooms: Dictionary = _graph["rooms"]
	var gates: Dictionary = _graph["gates"]
	# The base state is the right one to ask in: story overlays and mutations only
	# ADD edges (law 3, asserted in check 2), so a floor that hangs together here
	# hangs together in every later state.
	var base_index := _index_for(_graph["story_states"][0], _graph["scars"][0])
	var full: Array[String] = TowerGraph.HEROES.duplicate()
	var claimed_by: Dictionary = {}   # room id -> the storey that drew it

	for plan: Dictionary in TowerPlans.STOREYS:
		var label := "plan storey %d" % int(plan["floor"])
		var plan_rooms: Dictionary = plan["rooms"]
		var plan_gates: Dictionary = plan["gates"]

		# --- plan -> graph: every id the floor names is a BUILT room row -----
		# A ROOM IS ON ONE FLOOR, AND A STOREY CLAIMING ITS OWN LANDING TWICE IS NOT
		# TWO FLOORS. Storey 10 letters its muster floor `M` -> `s10_landing`, which
		# is also its `landing` — the floor the ramp arrives on and the floor the
		# block stands in are one room, and a plate has to stand beside a drawn room
		# (the pad rule in `_plan_problems`). Deduping here keeps the cross-storey
		# claim exactly as strict as it was; `claimed_by` is still one storey per id.
		var named: Array[String] = [String(plan["landing"])]
		for letter: String in plan_rooms:
			var lettered := String(plan_rooms[letter])
			if not named.has(lettered):
				named.append(lettered)
		for rid: String in named:
			if not rooms.has(rid):
				_fail("%s names room '%s', which is not a TOWER_GRAPH room" % [label, rid])
				continue
			if not bool(rooms[rid]["built"]):
				_fail("%s draws room '%s', whose graph row says built: false — the audit would "
					% [label, rid] + "walk round a floor the player is standing on")
			if claimed_by.has(rid):
				_fail("room '%s' is drawn by both %s and %s — a room is on one floor" % [
					rid, String(claimed_by[rid]), label])
				continue
			claimed_by[rid] = label
		for slot: String in plan_gates:
			var gid := String(plan_gates[slot])
			if not gates.has(gid):
				_fail("%s puts gate '%s' in cell %s, which is not a TOWER_GRAPH gate" % [
					label, gid, slot])

		# --- what the grid actually draws ------------------------------------
		var drawn_letters: Dictionary = {}
		var drawn_slots: Dictionary = {}
		for r: int in plan["rows"].size():
			var row := String(plan["rows"][r])
			for c: int in row.length():
				var ch := row[c]
				if ch == TowerPlans.GATE_CHAR or TowerPlans.pad_digit(ch) > 0:
					drawn_slots["%d,%d" % [c, r]] = true
				elif ch >= "A" and ch <= "Z" and ch != TowerPlans.STAIR_UP_CHAR \
						and ch != TowerPlans.PAD_CHAR and ch != TowerPlans.POST_CHAR:
					drawn_letters[ch] = true

		# --- ...against the two dicts, both ways -----------------------------
		for drawn: String in drawn_letters:
			if not plan_rooms.has(drawn):
				_fail("%s draws cells lettered '%s', which its rooms dict maps to no "
					% [label, drawn] + "TOWER_GRAPH room")
		for letter2: String in plan_rooms:
			if not drawn_letters.has(letter2):
				_fail("%s maps '%s' to room '%s', but no cell on the floor carries that letter "
					% [label, letter2, String(plan_rooms[letter2])] + "— a row about nothing")
		for slot2: String in drawn_slots:
			if not plan_gates.has(slot2):
				_fail("%s draws a gate cell ('%s' or a lock pad) at %s that its gates dict does "
					% [label, TowerPlans.GATE_CHAR, slot2]
					+ "not name — a gate drawn and forgotten is a passage the audit cannot see")
		for slot3: String in plan_gates:
			if not drawn_slots.has(slot3):
				_fail("%s names a gate at cell %s, where the plan draws neither a '%s' nor a "
					% [label, slot3, TowerPlans.GATE_CHAR] + "lock pad")

		# --- ...and every rising mass can say which side you open it from ---
		# A mass pad is DERIVED from the plain-floor side of its own `D` run
		# (`TowerInterior.gate_pad_cell`) and never drawn, so the failure it can
		# have is a doorway with floor on both sides or on neither — one builds no
		# pad at all, the other would be a coin toss between "you open this from the
		# corridor" and "you open it from inside the room it guards". Named here
		# because the fix is a character in this file.
		for slot4: String in plan_gates:
			var gid4 := String(plan_gates[slot4])
			var gate4: Dictionary = gates.get(gid4, {})
			var geometry4 := String(gate4.get("geometry", ""))
			if String(gate4.get("class", "")) != TowerGraph.CLASS_IDENTITY \
					and not (gid4 == TowerGraph.GATE_IDENTITY \
					and geometry4 == TowerGraph.GEOMETRY_MASS):
				continue
			var run: Rect2i = TowerInterior.gate_slots(plan)["masses"].get(gid4, Rect2i())
			if run.size == Vector2i.ZERO:
				continue
			if TowerInterior.gate_pad_cell(plan, run).x < 0:
				_fail(("%s: rising mass '%s' has no side to stand on — exactly one cell "
					+ "4-adjacent to its doorway must be plain floor, and the plan gives it "
					+ "two or none") % [label, gid4])

		# --- the graph agrees the floor hangs together -----------------------
		var landing := String(plan["landing"])
		if rooms.has(landing):
			var seen := _reach(base_index, landing, full, MAX, "")
			for rid2: String in named:
				if not seen.has(rid2):
					_fail("%s: no route joins '%s' to the landing '%s' — the floor is drawn "
						% [label, rid2, landing] + "but the graph does not connect it")

	# --- graph -> plan: a built room NO floor draws -----------------------------
	# The direction the four bindings above were missing, and it is the one that
	# bites silently. A room with no cells on any grid still walks perfectly in the
	# graph, so checks 1 and 3 stay green — while `_gates_shut_problems` skips every
	# edge it carries, because it looks the room up on the drawing and does not find
	# it. One vestigial row cost storey 5 all ten of its edges, `riddle_stair`'s
	# among them.
	for rid3: String in rooms:
		if not bool(rooms[rid3]["built"]) or claimed_by.has(rid3):
			continue
		_fail(("room '%s' is built but no storey plan draws it — the grid checks cannot see "
			+ "a room with no cells, so every gates-shut binding it carries is skipped. "
			+ "Letter it on its floor, or merge it into the room it is half of") % rid3)
	Sentinel.done("plans_bind_to_the_graph")


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
				TowerGraph.CLASS_DEMAND, TowerGraph.CLASS_RIDDLE]:
			_fail("gate '%s' has class '%s', which is none of the four verbs" % [gid, cls])
		var who := String(g.get("identity", ""))
		if cls == TowerGraph.CLASS_IDENTITY:
			if who not in TowerGraph.HEROES:
				_fail("identity gate '%s' asks for '%s', who is not a hero" % [gid, who])
		elif who != "":
			# THE RIDDLE'S OWN LAW LANDS HERE. A riddle that named a hero would be an
			# identity gate wearing the wrong colour — and one the fixpoint walk would
			# then treat as free for everybody, which is the audit lying rather than
			# merely a design smell.
			_fail("gate '%s' is a %s gate but names a hero ('%s')" % [gid, cls, who])
		var geometry := String(g.get("geometry", ""))
		if geometry not in ["", TowerGraph.GEOMETRY_MASS]:
			_fail("gate '%s' has geometry '%s', which is not a supported gate shape" % [
				gid, geometry])
		if geometry == TowerGraph.GEOMETRY_MASS and (gid != TowerGraph.GATE_IDENTITY \
				or cls != TowerGraph.CLASS_CHALLENGE or who != ""):
			_fail("gate '%s' uses mass geometry outside the base-kit secure-door exception" % gid)
		if gid == TowerGraph.GATE_IDENTITY and (cls != TowerGraph.CLASS_CHALLENGE \
				or geometry != TowerGraph.GEOMETRY_MASS or who != ""):
			_fail("the secure-door gate must remain the base-kit mass exception")
		# ...and the two riddle-only keys are riddle-only in both directions.
		var riddle := cls == TowerGraph.CLASS_RIDDLE
		for key: String in ["clue_room", "answer"]:
			var carried: bool = g.has(key) and not (
				(g[key] is String and String(g[key]) == "")
				or (g[key] is Array and (g[key] as Array).is_empty()))
			if riddle and not carried:
				_fail("riddle gate '%s' carries no '%s' — the whole class is that key" % [
					gid, key])
			elif carried and not riddle:
				_fail("gate '%s' is a %s gate but carries '%s', which only a riddle may" % [
					gid, cls, key])

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
	Sentinel.done("design_laws")


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
	Sentinel.done("spines_at_the_readiness_floor")


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
	Sentinel.done("demands_are_forecastable")


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
			for entry: Dictionary in _all_entries():
				for free: Array in _subsets():
					var typed: Array[String] = []
					for h: String in free:
						typed.append(h)
					_audit_one(story, scar, entry, typed)
	Sentinel.done("every_subset_reaches_a_cell")


func _audit_one(story: Dictionary, scar: Dictionary, entry: Dictionary,
		free: Array[String]) -> void:
	"""One walk. Fails naming the case, the subset and what stopped it."""
	var targets := _captive_cells(free)
	if targets.is_empty():
		return  # nobody is captive: no rescue to make.
	var seen := _reach(_index_for(story, scar), String(entry["room"]), free, FLOOR, "")
	for cell: String in targets:
		if seen.has(cell):
			return
	# Name the gate. The blockers are the impassable gates on the frontier — the
	# doors this subset stood in front of and could not open, which is the sentence
	# a designer can act on.
	var blockers: Dictionary = {}
	for edge: Dictionary in _edges_for(story, scar):
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
			var index := _index_for(story, scar)
			for entry: Dictionary in _all_entries():
				for free_any: Array in _subsets():
					var free: Array[String] = []
					for h: String in free_any:
						free.append(h)
					var targets := _captive_cells(free)
					if targets.is_empty():
						continue
					if not _reaches_any(index, entry, free, targets, ""):
						continue  # already failed in check 5; do not double-report
					for gid: String in _graph["gates"]:
						if necessary.has(gid):
							continue
						if not _reaches_any(index, entry, free, targets, gid):
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
	Sentinel.done("captivity_flags_are_honest")


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
			var index := _index_for(story, scar)
			for entry: Dictionary in _all_entries():
				var seen := _reach(index, String(entry["room"]), full, MAX, "")
				for rid: String in all_rooms:
					if seen.has(rid):
						continue
					_fail("the FULL ROSTER at max ranks cannot reach room '%s' from entry '%s' "
						% [rid, String(entry["id"])]
						+ "(story '%s', scar '%s')" % [String(story["id"]), String(scar["id"])])

	# Each quest solo-completable by at least one hero, somewhere in the tree.
	var base_index := _index_for(_graph["story_states"][0], _graph["scars"][0])
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
				if _reach(base_index, String(entry["room"]), [hero], MAX, "").has(room):
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
	Sentinel.done("quests_and_liberation")


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

	Memoized on (story, scar): the state space is the OUTER pair of loops in checks
	5, 6 and 7, so the same set is rebuilt once per entry x subset otherwise.
	"""
	var key := String(story["id"]) + "|" + String(scar["id"])
	if _edges_cache.has(key):
		return _edges_cache[key]

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
	_edges_cache[key] = out
	return out


func _index_for(story: Dictionary, scar: Dictionary) -> Dictionary:
	"""
	The ADJACENCY INDEX of that edge set: room id -> the edges touching it.

	`_reach` used to re-scan every edge for every popped room, which is
	O(rooms x edges) per walk. Fourteen rooms and fifteen edges made that free; the
	epic's target is ~150 rooms and ~200 edges, where one walk is 30 000 edge tests
	and this file stops finishing inside its 30 s acceptance. The index makes a pop
	cost O(degree) instead, and it is built once per (story, scar) — the same
	memoization key as the edge set it is derived from, because it changes exactly
	when that does.
	"""
	var key := String(story["id"]) + "|" + String(scar["id"])
	if _index_cache.has(key):
		return _index_cache[key]

	var index: Dictionary = {}
	for edge: Dictionary in _edges_for(story, scar):
		for end_: String in [String(edge["a"]), String(edge["b"])]:
			if not index.has(end_):
				index[end_] = []
			index[end_].append(edge)
	_index_cache[key] = index
	return index


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


func _reach(index: Dictionary, start: String, free: Array[String], mode: String,
		skip_gate: String) -> Dictionary:
	"""
	Everywhere this free set can get to — walked to a FIXPOINT over the riddles.

	@param index: `_index_for(story, scar)` — room id -> the edges touching it.
	@param skip_gate: a gate id to treat as impassable, for check 6's necessity
	                  probe. "" for an ordinary walk.
	@return: room id -> true, for every room reached.

	WHY A FIXPOINT AND NOT ONE WALK (phase 15). Every other gate class is a pure
	function of the free set, so one breadth-first pass answers the question. A
	RIDDLE is passable if this same walk reaches its clue room — a gate whose
	openness depends on the very reachability being computed. So: walk with the
	riddles shut, open the ones whose clue rooms turned up, walk again, and repeat
	until no new riddle opens.

	IT TERMINATES AND IT IS THE LEAST FIXPOINT. Each round either opens at least one
	riddle or stops, so there are at most (riddles + 1) rounds; and reachability is
	monotone in the solved set, so starting from nothing solved and only ever adding
	lands on the SMALLEST set of rooms consistent with the rules — the worst case,
	which is the only direction a softlock audit may err in. A riddle whose clue is
	shut behind itself is exactly the case that never opens here, which is how the
	landmine is caught rather than assumed away.
	"""
	var solved: Dictionary = {}
	while true:
		var seen := _walk(index, start, free, mode, skip_gate, solved)
		var grew := false
		for gid: String in _graph["gates"]:
			if solved.has(gid) or gid == skip_gate:
				continue
			var g: Dictionary = _graph["gates"][gid]
			if String(g.get("class", "")) != TowerGraph.CLASS_RIDDLE:
				continue
			if seen.has(String(g.get("clue_room", ""))):
				solved[gid] = true
				grew = true
		if not grew:
			return seen
	return {}


func _walk(index: Dictionary, start: String, free: Array[String], mode: String,
		skip_gate: String, solved: Dictionary) -> Dictionary:
	"""
	One breadth-first pass, with `solved` naming the riddles already worked out.

	A room with no edges is simply absent from `index`, which reads as "nowhere to
	go from here", exactly as the old full scan did.
	"""
	var seen: Dictionary = {start: true}
	var queue: Array[String] = [start]
	while not queue.is_empty():
		var here: String = queue.pop_back()
		for edge: Dictionary in index.get(here, []):
			var far := _across(edge, here)
			if far == "" or seen.has(far):
				continue
			var gid := String(edge["gate"])
			if gid != "" and (gid == skip_gate or not _passable(gid, free, mode, solved)):
				continue
			seen[far] = true
			queue.append(far)
	return seen


func _reaches_any(index: Dictionary, entry: Dictionary, free: Array[String],
		targets: Array[String], skip_gate: String) -> bool:
	"""True when at least one target room is reachable from `entry` at floor rank."""
	var seen := _reach(index, String(entry["room"]), free, FLOOR, skip_gate)
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


func _passable(gate_id: String, free: Array[String], mode: String,
		solved: Dictionary = {}) -> bool:
	"""
	Can this free set get through this gate, with nothing assumed opened?

	@param solved: the riddles this walk has already worked out — see `_reach`. It
	               defaults to none, which is the honest answer for a caller asking
	               about one gate in isolation (check 5's blocker naming): a riddle
	               that is closed there is one the walk really did stop at.

	ONE RULE PER GATE CLASS, and they are the epic's four verbs:

	  * challenge — the base kit beats it, so anybody does. (A challenge that needed
	    a rank would be a demand gate painted the wrong colour; check 2 refuses one.)
	  * identity  — only while its hero is free. The one class that can strand a
	    subset, which is why every one of them is a suspect in check 5.
	  * demand    — some free hero must read `scale` on `effect`. Only heroes whose
	    SKILL_TREES carry that effect can read it at all, so a hero-specific demand
	    (`primm_blink`) requires that hero exactly as an identity gate would. That
	    equivalence is derived from the trees, never authored twice.
	  * riddle    — passable once this walk has reached its clue room. NOTHING about
	    the free set enters into it: knowledge is party-level, so a riddle can never
	    be the gate that strands a subset, and the only way it can hurt anybody is by
	    having its clue shut behind itself. That is what the fixpoint is for.
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
		TowerGraph.CLASS_RIDDLE:
			return solved.has(gate_id)
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
		TowerGraph.CLASS_RIDDLE:
			return "riddle gate, its clue is in '%s'" % String(g.get("clue_room", "?"))
	return "challenge gate, base kit"


# ============================================================================
# VERDICT
# ============================================================================

# ============================================================================
# CHECK 8 — every authored scar is a scar the building can actually inflict
# ============================================================================

func _check_scars_are_built() -> void:
	"""
	Check 8. The `scars` table and `tower_interior.gd` describe the same event.

	CHECK 1's ARGUMENT, ONE ROW TYPE LOWER, and it is the one that stops the whole
	sanctioned exception shipping inert. Checks 2 and 5 already prove a scar is
	SAFE — the fifteen-subset property re-runs inside every one of them, and a scar
	that severed the last singleton spine would fail the build. Neither of them
	asks whether the scar HAPPENS. A `removes: ["block_main_door"]` that no box in
	the building implements is a doorway that stays open forever: the audit passes,
	the protocol "succeeds", and the permanent consequence the whole bead is about
	is a line of data nobody can see.

	So the binding is mechanical and BIDIRECTIONAL, exactly as check 1's is:

	  * every scar row with a non-empty `removes` must be built by at least one box
	    that names it (`"scar": <id>`), and that box must COLLIDE — rubble you walk
	    through is not a closed passage;
	  * every scar box must name an authored scar and an edge that scar really
	    removes (`"severs"`), so a box cannot claim to close something the graph
	    thinks is still open.

	`all_boxes()` AND NOT `boxes()`, and that is the landmine phase 16 walked into:
	the scar's rubble moved out of the hand-authored keep and onto storey 10's plan,
	so a check reading only the keep would have found no scar box at all — and its
	own "nothing implements this scar" branch would then have been the thing that
	caught it. Reading the whole building is what makes that branch about the DATA
	rather than about which population the box happens to live in.

	`ponytail:` WHAT IT STILL CANNOT PROVE is that the box stands physically ON the
	route the edge represents — the graph has rooms and edges, not coordinates, so
	there is nothing to compare a position against. `tower_interior_selfcheck`'s own
	scar check closes the next inch of that gap (the box's span is open in the
	unscarred plan and stone in the scarred one, sampled); the last inch is a
	walkthrough. The upgrade path is per-edge geometry in `TOWER_GRAPH`, which is a
	much bigger file for one scar.
	"""
	var boxes: Array[Dictionary] = TowerInterior.all_boxes()
	var authored: Array[String] = TowerGraph.scar_ids()
	var built: Dictionary = {}

	for box: Dictionary in boxes:
		var scar := String(box.get("scar", ""))
		if scar == "":
			continue
		var box_name := String(box["name"])
		if not authored.has(scar):
			_fail(("the interior builds '%s' for scar '%s', which TOWER_GRAPH does not "
				+ "enumerate (%s) — an unenumerated scar is a state the audit never walks")
				% [box_name, scar, str(authored)])
			continue
		if not bool(box.get("collide", false)):
			_fail(("scar box '%s' does not collide — it draws a closed passage and leaves "
				+ "it walkable, which is the worst of both") % box_name)
		var severs := String(box.get("severs", ""))
		var removes: Array = _scar_row(scar).get("removes", [])
		if severs == "":
			_fail("scar box '%s' names no edge it severs" % box_name)
		elif not removes.has(severs):
			_fail(("scar box '%s' claims to sever '%s', but scar '%s' removes %s")
				% [box_name, severs, scar, str(removes)])
		built[scar] = true

	for scar: Dictionary in _graph["scars"]:
		var id := String(scar["id"])
		var removes: Array = scar.get("removes", [])
		if removes.is_empty():
			continue
		if not built.has(id):
			_fail(("scar '%s' removes %s and NOTHING IN THE BUILDING IMPLEMENTS IT — the "
				+ "audit walks a tower where that passage is gone and the player walks one "
				+ "where it is still open") % [id, str(removes)])

	print("tower scars: %d authored, %d built into the interior" % [
		authored.size(), built.size()])
	Sentinel.done("scars_are_built")


# ============================================================================
# CHECK 9 — the flood fill: every drawn floor is actually walkable
# ============================================================================

func _check_plans_are_walkable() -> void:
	"""
	Check 9. Every hand-planned storey is one connected walking surface, reached
	by a ramp no steeper than the one the game has always had.

	WHAT THE GRAPH AUDIT CANNOT SEE. Checks 1-8 reason about `TOWER_GRAPH`, whose
	rooms are nodes and whose edges are "there is a way through". That is exactly
	the right abstraction for the softlock property and it is blind to the thing a
	designer editing 1600 characters of ASCII will actually get wrong: the graph
	says two rooms are joined, and only the GRID says the corridor between them was
	drawn. One `.` typed as a `#` in a doorway and check 1 still passes, the
	fifteen subset walks still pass, and the floor is two sealed halves.

	So this check walks the same storey the builder builds, in cells:

	  * well-formedness first, because every assertion below assumes a rectangular
	    grid of legal characters — 40 rows of 40, one solid `S` lane with its long
	    axis on X, its `s` landing against one short end, exactly two pads, each
	    beside a room;
	  * a 4-connected FLOOD FILL from the landing over every non-`#` cell, which
	    must reach every room cell, every pad, every post and every gate slot. The
	    first cell it cannot reach is reported as `(c, r)` AND as world XZ, because
	    a designer fixing it is looking at a text file and a screenshot;
	  * the stair COINCIDES with the floor below — its lane stands on walkable
	    cells of the storey it climbs from. Every floor is a plan now (bd
	    godot-test1-dn8), so this is one rule read off two grids and no longer has
	    a keep-clearance special case beside it;
	  * and the ramp is no steeper than the phase-3 ramp, which is the only slope
	    in this building anyone has ever walked.

	THE GROUND STOREY IS THE ONE WITHOUT A RAMP, and it says so in data: `from ==
	floor` means entered from outside the building, its `s` cells are the doormat,
	and the four lane rules above (`_lane_problems`) are skipped for it. Everything
	else — well-formedness, the pads, both fills — is asked of it unchanged, and
	its own negative control at the bottom is what proves that.

	NEGATIVE CONTROLS AT THE BOTTOM. A flood fill that passes on a broken plan is
	worse than no flood fill, so each assertion is re-asked against a deliberately
	broken COPY of the shipped storey and must come back with that assertion's own
	complaint. The copies are built here; nothing edits `tower_plans.gd`.
	"""
	var walkable := 0
	var rooms_drawn := 0
	var angles: PackedStringArray = []
	for plan: Dictionary in TowerPlans.STOREYS:
		for problem: String in _plan_problems(plan):
			_fail("plan storey %d: %s" % [int(plan["floor"]), problem])
		var letters: Dictionary = {}
		for r: int in plan["rows"].size():
			var line := String(plan["rows"][r])
			for c: int in line.length():
				var ch := line[c]
				if ch != TowerPlans.WALL_CHAR:
					walkable += 1
				if _is_room_letter(ch):
					letters[ch] = true
		rooms_drawn += letters.size()
		angles.append("%.1f" % rad_to_deg(atan(_plan_slope(plan))))
	_plan_summary = "tower plans: %d storeys, %d rooms, %d cells walkable, ramps %s deg" % [
		TowerPlans.STOREYS.size(), rooms_drawn, walkable, ", ".join(angles)]

	_check_the_flood_fill_can_fail()
	Sentinel.done("plans_are_walkable")


# ============================================================================
# CHECK 10 — the riddles: a clue you can get to, a lock you can enter
# ============================================================================

func _check_riddles_are_answerable() -> void:
	"""
	Check 10. Every riddle has a clue somebody can read and a lock somebody can
	press, and neither is shut behind the riddle it belongs to.

	THE SOFTLOCK CLAUSE IS THE LAST ONE, and it is the reason this check exists.
	A riddle is passable exactly when its clue room is reachable (`_passable`), so a
	clue room reachable ONLY through the riddle it explains is a door whose key is
	behind the door — a state the fixpoint walk in `_reach` correctly refuses to
	open, which means checks 5 and 7 would report it as "room unreachable" and name
	the room rather than the mistake. So it is asked directly here: with this riddle
	treated as a wall, the full roster at max ranks must still reach its clue, from
	every legal entry and in every story and scar state. The message names the
	riddle, because that is the file the author has to open.

	Everything above it is the cheap structural half — the answer is a permutation
	of the pads actually drawn, the mass is actually drawn, and the clue strip lands
	on plain floor of the clue room rather than in a wall or over a system pad.
	"""
	var rooms: Dictionary = _graph["rooms"]
	# The lock cells, gathered off the storeys once: gate id -> digit -> cells.
	var pads: Dictionary = {}
	var masses: Dictionary = {}
	for plan: Dictionary in TowerPlans.STOREYS:
		var slots := TowerInterior.gate_slots(plan)
		for gid: String in slots["masses"]:
			masses[gid] = true
		for pad: Dictionary in slots["pads"]:
			var of: Dictionary = pads.get(String(pad["gate"]), {})
			of[int(pad["digit"])] = int(of.get(int(pad["digit"]), 0)) + 1
			pads[String(pad["gate"])] = of

	var riddles := 0
	for gid2: String in _graph["gates"]:
		var g: Dictionary = _graph["gates"][gid2]
		if String(g.get("class", "")) != TowerGraph.CLASS_RIDDLE:
			continue
		riddles += 1
		# --- the clue room is a room, and one that exists ---------------------
		var clue := String(g.get("clue_room", ""))
		if not rooms.has(clue):
			_fail("riddle '%s' points at clue room '%s', which is not a room" % [gid2, clue])
			continue
		if not bool(rooms[clue]["built"]):
			_fail("riddle '%s' points at clue room '%s', which nobody has built" % [gid2, clue])

		# --- the answer is a permutation of the pads that are actually drawn ---
		var answer: Array = g.get("answer", [])
		var of_gate: Dictionary = pads.get(gid2, {})
		if answer.size() < 3 or answer.size() > TowerPlans.PAD_DIGITS.length():
			_fail("riddle '%s' has a %d-step answer — a sequence is 3 to %d steps" % [
				gid2, answer.size(), TowerPlans.PAD_DIGITS.length()])
		var used: Dictionary = {}
		for step in answer:
			var digit := int(step)
			if digit < 1 or digit > TowerPlans.PAD_DIGITS.length():
				_fail("riddle '%s' asks for pad %d, which is not one of '%s'" % [
					gid2, digit, TowerPlans.PAD_DIGITS])
			elif used.has(digit):
				_fail(("riddle '%s' presses pad %d twice — an answer is a PERMUTATION of its "
					+ "pads, which is what makes the mass's notch count honest") % [gid2, digit])
			used[digit] = true
			if int(of_gate.get(digit, 0)) != 1:
				_fail("riddle '%s' asks for pad %d, which %d cells on the plans carry" % [
					gid2, digit, int(of_gate.get(digit, 0))])
		for drawn: int in of_gate:
			if not used.has(drawn):
				_fail(("riddle '%s' has a pad %d drawn on a plan that its answer never presses "
					+ "— a lock button that does nothing") % [gid2, drawn])
		if not masses.has(gid2):
			_fail("riddle '%s' has no '%s' cell on any storey — a lock with nothing to open" % [
				gid2, TowerPlans.GATE_CHAR])

		# --- the clue is painted on floor the clue room really has ------------
		var strip := TowerInterior.clue_strip(gid2)
		if strip.is_empty():
			_fail("riddle '%s': no storey draws its clue room '%s', so the clue is painted "
				% [gid2, clue] + "nowhere")
		else:
			var plan2 := TowerPlans.storey(int(strip["floor"]))
			var letter := ""
			for key: String in plan2["rooms"]:
				if String(plan2["rooms"][key]) == clue:
					letter = key
			for i: int in answer.size():
				var c := int(strip["c"]) + i
				var r := int(strip["r"])
				var line := String(plan2["rows"][r])
				if c < 0 or c >= line.length() or line[c] != letter:
					_fail(("riddle '%s': its clue strip runs off '%s' at cell (%d, %d), which "
						+ "is '%s' — the room is too narrow for a %d-mark clue, or the strip "
						+ "lands on something else drawn in it")
						% [gid2, clue, c, r,
							"off the grid" if c < 0 or c >= line.length() else line[c],
							answer.size()])
					break

		# --- and the clue is not shut behind the riddle it explains -----------
		for story: Dictionary in _graph["story_states"]:
			for scar: Dictionary in _graph["scars"]:
				var index := _index_for(story, scar)
				for entry: Dictionary in _all_entries():
					var full: Array[String] = TowerGraph.HEROES.duplicate()
					if _reach(index, String(entry["room"]), full, MAX, gid2).has(clue):
						continue
					_fail(("SOFTLOCK: riddle '%s' is the only way to its own clue room '%s' "
						+ "from entry '%s' (story '%s', scar '%s') — the answer is locked "
						+ "behind the door it opens")
						% [gid2, clue, String(entry["id"]), String(story["id"]),
							String(scar["id"])])
	if riddles > 0:
		print("tower riddles: %d, each with a %d-pad lock and a clue reachable with it shut" % [
			riddles, TowerPlans.PAD_DIGITS.length()])
	Sentinel.done("riddles_are_answerable")


func _check_the_flood_fill_can_fail() -> void:
	"""
	The negative controls: one deliberately broken copy of a shipped storey per
	assertion above, each of which must produce that assertion's own complaint.
	`_control` matches on a phrase from the message, not merely on "something
	failed" — a control that trips a different rule proves nothing.

	EVERY BASE IS FOUND BY A ROOM IT DRAWS, never by an index into `STOREYS`. That
	was `STOREYS[0]` until the ground storey was drawn on the grid in front of it
	(bd godot-test1-dn8), at which point six controls started mutating cells that
	mean nothing on the new first row and reported "the assertion is decorative" —
	the check catching itself, which is the good failure mode and exactly the one
	`_control_storey` two functions down already argued for.
	"""
	var base := _control_storey("s3_records_west", "the storey-3 controls")
	if base.is_empty():
		Sentinel.done("the_flood_fill_can_fail")
		return
	# A row one character short — the assertion every other one stands on.
	_control("a short row", _row_at(base, 1, String(base["rows"][1]).substr(1)),
			"characters wide")
	# A character nobody taught the builder.
	_control("an illegal character", _cell_at(base, 2, 2, "@"), "not a legal plan character")
	# The two-cell doorway into the north-west record stack, walled up: check 1
	# still binds the room, and only the fill can tell that nobody can get in.
	_control("a walled-off room",
			_cell_at(_cell_at(base, 6, 18, TowerPlans.WALL_CHAR), 7, 18, TowerPlans.WALL_CHAR),
			"cannot be walked to")
	# The landing moved off the lane's end, into the middle of the floor.
	var moved := _cell_at(base, 15, 1, TowerPlans.FLOOR_CHAR)
	moved = _cell_at(moved, 15, 2, TowerPlans.FLOOR_CHAR)
	moved = _cell_at(moved, 20, 20, TowerPlans.LANDING_CHAR)
	_control("a landing off the lane's end", moved, "short end")
	# The lane cut to its eastern five cells: 6.4 m of rise over 9.70 m of run is
	# 0.660, over the phase-3 ramp's proven 0.575. ONE cell used to be enough — the
	# grand ramp carried the whole 11.0 m from the ground and nine cells put it at
	# 0.630 — but bd godot-test1-dn8 moved its foot up onto storey 2, so the same
	# ten cells now carry 6.4 m and it takes half the lane to make it too steep.
	# The cells go from the WEST end so the landing stays against a short end and
	# this control keeps tripping its own rule and not the landing's.
	var short_lane: Dictionary = base
	for c: int in range(5, 10):
		short_lane = _cell_at(short_lane, c, 1, TowerPlans.FLOOR_CHAR)
		short_lane = _cell_at(short_lane, c, 2, TowerPlans.FLOOR_CHAR)
	_control("a lane half its length", short_lane, "steeper than")
	# THE GRAND RAMP MOVED OFF THE CELLS THE STOREY BELOW KEEPS CLEAR FOR IT. This
	# control used to redraw the ramp "through the keep" and assert the report said
	# `inside the keep`; the keep is demolished (bd godot-test1-dn8) and its
	# clearance rule went with it, so the control is re-aimed at the general rule
	# that replaced it — a lane's cells stand on floor somebody can walk on, read
	# out of the storey below's own grid. Moved down the plate to rows 21-22, the
	# ten lane cells cross storey 2's south partition at column 22.
	var off_the_clear: Dictionary = base.duplicate(true)
	var clear_row := TowerPlans.WALL_CHAR + TowerPlans.FLOOR_CHAR.repeat(TowerPlans.PLAN_GRID - 2) \
			+ TowerPlans.WALL_CHAR
	var lane_row := TowerPlans.WALL_CHAR + TowerPlans.FLOOR_CHAR.repeat(15) \
			+ TowerPlans.STAIR_UP_CHAR.repeat(10) + TowerPlans.LANDING_CHAR \
			+ TowerPlans.FLOOR_CHAR.repeat(12) + TowerPlans.WALL_CHAR
	off_the_clear["rows"][1] = clear_row
	off_the_clear["rows"][2] = clear_row
	off_the_clear["rows"][21] = lane_row
	off_the_clear["rows"][22] = lane_row
	_control("a grand ramp redrawn over the storey below's partitions", off_the_clear,
			"land on floor somebody can walk on")
	# THE FLOOR ENTERED ONLY BY STEPPING OFF THE RAMP. Wall the two cells east of
	# storey 3's landing and the drawing is still perfectly connected on paper — but
	# the only way off the landing is west onto the lane, and the only way off the
	# lane is a sideways step onto a floor up to a storey below its deck. Every
	# room on the floor is then unreachable, and before `_off_the_lane` the fill
	# walked that step and said nothing.
	var only_off_the_lane := _cell_at(base, 16, 1, TowerPlans.WALL_CHAR)
	only_off_the_lane = _cell_at(only_off_the_lane, 16, 2, TowerPlans.WALL_CHAR)
	_control("a floor entered only by stepping off the ramp", only_off_the_lane,
			"cannot be walked to")
	# A pad moved out into the corridor, beside nothing.
	var stray := _cell_at(base, 6, 10, "A")
	stray = _cell_at(stray, 20, 20, TowerPlans.PAD_CHAR)
	_control("a pad beside no room", stray, "not beside a room")

	# --- and the two rules the first fill cannot state -------------------------
	# A ROOM LEFT REACHABLE ONLY THROUGH A RIDDLE. Storey 8's maze core has one
	# north face, at (20, 16), and the graph joins it to the stair hall UNGATED
	# (`s8_core_north`) — the second half of route A. Wall that one cell and the
	# core is still perfectly reachable, so the fill above stays silent, every
	# subset walk stays silent, and the only way through it is `riddle_maze_lower`.
	var maze := _control_storey("s8_maze_core", "a room left reachable only through a riddle")
	if not maze.is_empty():
		_control("a room left reachable only through a riddle",
				_cell_at(maze, 20, 16, TowerPlans.WALL_CHAR), "the graph promises a walk")
	# A HOLE IN THE CELL BLOCK'S PERIMETER. The north wall of Teibi's recess opened
	# onto the muster floor — the four identity gates walked round, on a wall that
	# check 11 samples neither of its two lines across.
	var block := _control_storey(TowerInterior.BLOCK_ROOM, "a hole in the cell block's outer wall")
	if not block.is_empty():
		_control("a hole in the cell block's outer wall",
				_cell_at(block, 22, 3, TowerPlans.FLOOR_CHAR), "way ROUND a door")
	# ...and a riddle drawn over somebody's floor: the same lock one column east is
	# the middle of Teibi's cell, which is where it stood until this review. It is
	# the storey BELOW the block that carries the lock, so it is found on its own
	# room and not nested inside the block's guard.
	var upper := _control_storey("s9_maze_core", "a riddle drawn under a room")
	if not upper.is_empty():
		var over_cell: Dictionary = upper.duplicate(true)
		over_cell = _cell_at(over_cell, 21, 5, TowerPlans.GATE_CHAR)
		over_cell["gates"]["21,5"] = "riddle_maze_upper"
		_control("a riddle drawn under a room", over_cell, "belongs under a wall")

	# --- and the two halves of the ground storey's `from == floor` rule --------
	# THE ARM THAT SKIPS THE LANE RULES MUST NOT SKIP THE FLOOR. `from == floor`
	# turns off four assertions for the one storey entered from outside the
	# building, and an arm like that is one `return` away from turning off the
	# whole function — at which point the ground floor, the storey every run starts
	# on, would be the only one nothing checks. So: wall the vault's doorway and the
	# fill must still say the vault is sealed, exactly as it does on a ramped floor.
	var ground := _control_storey("courtyard", "the ground storey's lane-less rules")
	if not ground.is_empty():
		_control("a walled-off room on the storey with no lane",
				_cell_at(_cell_at(ground, 29, 27, TowerPlans.WALL_CHAR),
					30, 27, TowerPlans.WALL_CHAR),
				"cannot be walked to")
		# ...and the other direction: a storey entered from outside that draws a
		# lane anyway is a ramp rising out of its own floor, which is a broken
		# `from` and the reason the arm tests the pair rather than just "no S".
		var own_lane := _cell_at(ground, 25, 15, TowerPlans.STAIR_UP_CHAR)
		own_lane = _cell_at(own_lane, 26, 15, TowerPlans.STAIR_UP_CHAR)
		_control("a ramp drawn on the storey entered from outside", own_lane,
				"stands on its own storey")
	Sentinel.done("the_flood_fill_can_fail")


func _control_storey(room: String, what: String) -> Dictionary:
	"""
	The shipped storey a negative control mutates, found by the ROOM it draws.

	NEVER a floor index written down here. An index would make "the labyrinth moved
	to another floor" read as `storey(n).is_empty()` and silently skip the control,
	leaving the assertion behind it decorative with nothing printed — which is the
	exact failure mode these controls exist to catch elsewhere. A room that no
	storey draws is a FAILURE, not a skip.
	"""
	for floor_index: int in TowerPlans.floors():
		var plan := TowerPlans.storey(floor_index)
		for letter: String in Dictionary(plan["rooms"]):
			if String(plan["rooms"][letter]) == room:
				return plan
	_fail(("no storey draws '%s', so the negative control for %s cannot be built — the "
		+ "assertion it stands behind is unmeasured") % [room, what])
	return {}


func _control(what: String, broken: Dictionary, needle: String) -> void:
	"""One negative control: `broken` must be refused, and refused for `needle`."""
	var problems := _plan_problems(broken)
	for problem: String in problems:
		if problem.contains(needle):
			return
	_fail(("the plan flood-fill ACCEPTS %s — it reported %s, none of which mentions '%s', "
		+ "so the assertion it is meant to enforce is decorative") % [what, str(problems), needle])


func _plan_problems(plan: Dictionary) -> Array[String]:
	"""
	Everything wrong with one storey's grid, as messages. Empty means the floor is
	well-formed, fully connected from its landing, standing on the storey below and
	climbed by a legal ramp.

	Deliberately returns rather than calling `_fail`, because the negative controls
	above drive this same function on plans that are SUPPOSED to be refused.
	"""
	var out: Array[String] = []
	var rows: Array = plan["rows"]

	# --- well-formedness: everything below assumes a rectangle of legal chars ---
	if rows.size() != TowerPlans.PLAN_GRID:
		out.append("%d rows, not %d — the grid is not the grid" % [
			rows.size(), TowerPlans.PLAN_GRID])
		return out
	for r: int in rows.size():
		var line := String(rows[r])
		if line.length() != TowerPlans.PLAN_GRID:
			out.append("row %d is %d characters wide, not %d" % [
				r, line.length(), TowerPlans.PLAN_GRID])
			return out
		for c: int in line.length():
			if not _is_legal_plan_char(line[c]):
				out.append("cell (%d, %d) is '%s', which is not a legal plan character" % [
					c, r, line[c]])

	# --- is there a lane at all, and should there be? --------------------------
	# THE GROUND STOREY DRAWS NO LANE, and that is DATA rather than a special case
	# here: `from == floor` is the format's way of saying **this storey is entered
	# from outside the building**. Floor 0 is the only one — a player arrives
	# through the shell's doorway, not up a ramp — and since bd godot-test1-dn8 drew
	# floors 0 and 1 on the grid the audit has to know the rule the plan format
	# states. Its `s` cells are the DOORMAT, so every assertion about a LANE is
	# skipped (they are gathered in `_lane_problems`, called at the bottom) and
	# every assertion about the LANDING still stands: the doormat is where a player
	# actually arrives and therefore still where the flood fill starts.
	#
	# The rule runs both ways, which is what makes it a rule and not a licence: a
	# storey entered from outside that DOES draw a lane has a ramp rising out of its
	# own floor, which is a broken `from` and not a stair.
	var from_outside: bool = int(plan["from"]) == int(plan["floor"])
	var lane_cells := _plan_cells(plan, TowerPlans.STAIR_UP_CHAR)
	var landing_cells := _plan_cells(plan, TowerPlans.LANDING_CHAR)
	if lane_cells.is_empty() and not from_outside:
		out.append(("no '%s' cells — a storey drawn over another floor is reached by a ramp, "
			+ "and only 'from' == 'floor' (entered from outside the building) draws none")
			% TowerPlans.STAIR_UP_CHAR)
		return out
	if not lane_cells.is_empty() and from_outside:
		out.append(("floor %d says 'from' == 'floor', so it is entered from outside the "
			+ "building, yet draws %d '%s' cells — a lane whose foot stands on its own storey")
			% [int(plan["floor"]), lane_cells.size(), TowerPlans.STAIR_UP_CHAR])
		return out
	if landing_cells.is_empty():
		out.append(("no '%s' landing — on a ramped storey it is the head of the lane and says "
			+ "which way the ramp rises; on the ground storey it is the doormat. Either way "
			+ "it is where the fill starts") % TowerPlans.LANDING_CHAR)
		return out

	# --- the pads --------------------------------------------------------------
	var pads := _plan_cells(plan, TowerPlans.PAD_CHAR)
	if pads.size() != 2:
		out.append("%d '%s' cells — a storey carries exactly two pads" % [
			pads.size(), TowerPlans.PAD_CHAR])
	for pad: Vector2i in pads:
		var beside := false
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := pad + step
			if n.x < 0 or n.y < 0 or n.x >= TowerPlans.PLAN_GRID or n.y >= TowerPlans.PLAN_GRID:
				continue
			if _is_room_letter(String(rows[n.y])[n.x]):
				beside = true
		if not beside:
			out.append(("the pad at (%d, %d) is not beside a room — a plate in open floor "
				+ "belongs to nothing and opens nothing") % [pad.x, pad.y])

	# --- the flood fill --------------------------------------------------------
	var seen: Dictionary = {}
	var queue: Array[Vector2i] = landing_cells.duplicate()
	for cell: Vector2i in queue:
		seen[cell] = true
	while not queue.is_empty():
		var here: Vector2i = queue.pop_back()
		for step2: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n2: Vector2i = here + step2
			if n2.x < 0 or n2.y < 0 or n2.x >= TowerPlans.PLAN_GRID or n2.y >= TowerPlans.PLAN_GRID:
				continue
			if seen.has(n2) or String(rows[n2.y])[n2.x] == TowerPlans.WALL_CHAR:
				continue
			if _off_the_lane(String(rows[here.y])[here.x], String(rows[n2.y])[n2.x]):
				continue
			seen[n2] = true
			queue.append(n2)
	for r2: int in rows.size():
		var line2 := String(rows[r2])
		for c2: int in line2.length():
			var ch := line2[c2]
			if ch == TowerPlans.WALL_CHAR or ch == TowerPlans.FLOOR_CHAR:
				continue
			if seen.has(Vector2i(c2, r2)):
				continue
			out.append(("cell (%d, %d) — '%s' at world x %.2f, z %.2f — cannot be walked to "
				+ "from the landing. The floor is drawn in two pieces")
				% [c2, r2, ch, _cell_x(c2), _cell_x(r2)])
			break   # one report per row: a sealed wing is hundreds of cells

	# --- the same fill again, with every gate SHUT -----------------------------
	# WHAT THE FIRST FILL CANNOT SEE. It walks a gate cell like any other floor, so
	# it proves the storey is one surface and says nothing about which SIDE of a
	# door anything is on. That is the labyrinth's whole design law — route A is
	# the UNGATED circuit and the four rescue spines walk it — and the law lived
	# only in `TOWER_GRAPH`, where `gate: ""` is a hand-written CLAIM about an ASCII
	# drawing that nothing read back. One '.' swapped for a '#' on storey 8's outer
	# ring and check 1, check 3 and all fifteen subset walks still pass while the
	# only way up is through `riddle_maze_lower`.
	#
	# So: label the floor's components with every gate cell treated as stone, and
	# hold the graph's own rows to them, IN BOTH DIRECTIONS —
	#
	#   gate == ""   the two rooms must land in ONE component. An ungated edge is a
	#                promise you can walk it with nothing solved.
	#   gate != ""   if they land in one component anyway, the graph must ALSO join
	#                them by an ungated path. Otherwise the drawing offers a way
	#                round a door the softlock audit models — which is exactly what
	#                a hole in the cell block's perimeter is, and what check 11's
	#                two sampled lines stopped covering when the block became an
	#                island in the open muster floor.
	out.append_array(_gates_shut_problems(plan, rows))

	# --- a riddle's mass has to have somewhere to RISE INTO --------------------
	# A riddle's mass is floor to ceiling and lifts a notch per correct step, and a
	# part-entered lock STAYS lifted: nothing resets `_riddle_step` when you walk
	# away. Its top starts at the slab underside, so every millimetre past
	# `SLAB_THICK` stands proud of the next storey's WALKING SURFACE — a solid block
	# in whatever room happens to be drawn over the doorway, and one no player can
	# step over. (`_retire` covers the fully open case and only that one.)
	var above := TowerPlans.storey(int(plan["floor"]) + 1)
	if not above.is_empty():
		for key: String in Dictionary(plan.get("gates", {})):
			var gid3 := String(plan["gates"][key])
			if String(TowerGraph.gate(gid3).get("class", "")) != TowerGraph.CLASS_RIDDLE:
				continue
			var at := key.split(",")
			if at.size() != 2:
				continue
			var c3 := int(at[0])
			var r3 := int(at[1])
			if c3 < 0 or r3 < 0 or c3 >= TowerPlans.PLAN_GRID or r3 >= TowerPlans.PLAN_GRID:
				continue
			if String(rows[r3])[c3] != TowerPlans.GATE_CHAR:
				continue   # a lock's PAD cells are in this dict too; they never move
			var steps := maxi(Array(TowerGraph.gate(gid3).get("answer", [])).size(), 1)
			var lift: float = TowerInterior.RIDDLE_NOTCH * float(steps - 1) / float(steps) \
					+ TowerInterior.RIDDLE_RATTLE
			if lift <= TowerInterior.SLAB_THICK:
				continue
			var over := String(above["rows"][r3])[c3]
			if over != TowerPlans.WALL_CHAR:
				out.append(("riddle '%s' is drawn at (%d, %d), under '%s' on floor %d — its "
					+ "mass rises up to %.2f m part-entered and the slab is %.2f m, so it "
					+ "stands %.2f m proud of that room's floor and STAYS there. A rising "
					+ "gate belongs under a wall")
					% [gid3, c3, r3, over, int(plan["floor"]) + 1, lift,
						TowerInterior.SLAB_THICK, lift - TowerInterior.SLAB_THICK])

	# --- and everything that is only true of a storey with a ramp --------------
	if not from_outside:
		out.append_array(_lane_problems(plan, lane_cells, landing_cells))
	return out


func _lane_problems(plan: Dictionary, lane_cells: Array[Vector2i],
		landing_cells: Array[Vector2i]) -> Array[String]:
	"""
	Everything the `S` lane has to be: one solid rectangle with its long axis on X,
	its landing against ONE short end, standing on floor somebody can walk on, and
	no steeper than the ramp this game has always had.

	Split out of `_plan_problems` when the ground storey joined `STOREYS` (bd
	godot-test1-dn8): a floor entered from outside draws no lane, and "skip the four
	lane rules" reads better as one call the caller can decline than as four
	`from == floor` guards buried among rules that apply to every storey.
	"""
	var out: Array[String] = []

	# --- the ramp lane: one solid rectangle, long axis on X --------------------
	var c0 := TowerPlans.PLAN_GRID
	var c1 := -1
	var r0 := TowerPlans.PLAN_GRID
	var r1 := -1
	for cell: Vector2i in lane_cells:
		c0 = mini(c0, cell.x)
		c1 = maxi(c1, cell.x)
		r0 = mini(r0, cell.y)
		r1 = maxi(r1, cell.y)
	var lane_w := c1 - c0 + 1
	var lane_d := r1 - r0 + 1
	if lane_cells.size() != lane_w * lane_d:
		out.append(("the '%s' cells are not one solid rectangle (%d cells in a %d x %d box) "
			+ "— the deck is one box and cannot follow a scattered lane")
			% [TowerPlans.STAIR_UP_CHAR, lane_cells.size(), lane_w, lane_d])
	if lane_w <= lane_d:
		out.append(("the ramp lane is %d x %d — its long axis must be X, because every ramp "
			+ "in this building is X-running and check 3 and the underside test both reason "
			+ "in the XY plane") % [lane_w, lane_d])
	# ...with its landing against ONE short end, which is how the rise is derived.
	var east := 0
	var west := 0
	for cell: Vector2i in landing_cells:
		if cell.y < r0 or cell.y > r1:
			out.append(("the landing at (%d, %d) is not across a short end of the lane "
				+ "(rows %d..%d)") % [cell.x, cell.y, r0, r1])
		elif cell.x == c1 + 1:
			east += 1
		elif cell.x == c0 - 1:
			west += 1
		else:
			out.append(("the landing at (%d, %d) does not sit against a short end of the "
				+ "lane (columns %d and %d)") % [cell.x, cell.y, c0 - 1, c1 + 1])
	if east > 0 and west > 0:
		out.append("landing cells sit against BOTH short ends — the ramp rises two ways")

	# --- the stair stands on the storey below ----------------------------------
	var below := TowerPlans.storey(int(plan["from"]))
	# EVERY floor a ramp can arrive from now has a plan (bd godot-test1-dn8 drew
	# floors 0 and 1 on the grid), so `below` is never empty and the keep-clearance
	# / door-corridor special case that used to stand here is gone with the keep it
	# measured. An empty plan below is now a broken `from`, and saying so beats
	# silently skipping the cell.
	for cell2: Vector2i in lane_cells:
		if below.is_empty():
			out.append(("the lane arrives from floor %d, which no storey draws — every "
				+ "floor is a plan now, so a ramp's foot has nothing to stand on")
				% int(plan["from"]))
			break
		var under := String(below["rows"][cell2.y])[cell2.x]
		if under == TowerPlans.WALL_CHAR or under == TowerPlans.STAIR_UP_CHAR:
			out.append(("the lane cell (%d, %d) stands over '%s' on floor %d — a ramp's "
				+ "foot has to land on floor somebody can walk on")
				% [cell2.x, cell2.y, under, int(plan["from"])])

	# --- and it is no steeper than the ramp this game has always had -----------
	var slope := _plan_slope(plan)
	if slope > TowerInterior.PLAN_RAMP_MAX_SLOPE + 0.0001:
		out.append(("the ramp's slope is %.4f (%.1f deg) over %d cells, steeper than the "
			+ "phase-3 ramp's proven %.4f — a stair nobody has walked")
			% [slope, rad_to_deg(atan(slope)), lane_w, TowerInterior.PLAN_RAMP_MAX_SLOPE])
	if rad_to_deg(atan(slope)) >= 40.0:
		out.append("the ramp's slope is %.1f deg, at or past the 40 deg hard ceiling"
			% rad_to_deg(atan(slope)))
	return out


func _plan_slope(plan: Dictionary) -> float:
	"""The storey's ramp slope: its rise over its lane's length. 0.0 if it has no lane."""
	var lane := _plan_cells(plan, TowerPlans.STAIR_UP_CHAR)
	if lane.is_empty():
		return 0.0
	var c0 := TowerPlans.PLAN_GRID
	var c1 := -1
	for cell: Vector2i in lane:
		c0 = mini(c0, cell.x)
		c1 = maxi(c1, cell.x)
	var run := float(c1 - c0 + 1) * TowerPlans.PLAN_CELL
	var rise: float = TowerInterior.FLOOR_Y[int(plan["floor"])] \
			- TowerInterior.FLOOR_Y[int(plan["from"])]
	return 0.0 if run <= 0.0 else rise / run


func _off_the_lane(from_ch: String, to_ch: String) -> bool:
	"""
	Is a step between these two cells a walk off the SIDE of a ramp lane?

	THE ONE PIECE OF HEIGHT IN A FLAT GRID. `S` cells are the ramp's deck and it
	DESCENDS a whole storey along the lane, so stepping sideways off one is a step
	of up to a storey — not a doorway. Only the `s` landing at the lane's high end
	is flush with this floor, which is why the lane is walked onto there and
	nowhere else.

	Storey 8's own plan comment warns about exactly this ("a 5 m step up at
	(19, 38)") and left it to a future author to remember. Without this rule both
	fills below step off the lane's foot onto the floor, so a maze that sealed its
	circuit the far side of the landing would be certified green — reachable in the
	model, a hard softlock in the building.
	"""
	var a_lane := from_ch == TowerPlans.STAIR_UP_CHAR
	var b_lane := to_ch == TowerPlans.STAIR_UP_CHAR
	if a_lane == b_lane:
		return false   # lane to lane, or floor to floor: an ordinary step
	return (to_ch if a_lane else from_ch) != TowerPlans.LANDING_CHAR


func _gates_shut_problems(plan: Dictionary, rows: Array) -> Array[String]:
	"""
	One storey walked with every gate cell treated as stone, against the graph rows
	that join two of ITS rooms. See the call site for why this is a separate fill.

	@return: this storey's disagreements, empty when the drawing and the graph say
	        the same thing about which rooms need a door between them.
	"""
	var out: Array[String] = []
	# Component id per cell, over everything that is neither wall nor gate.
	var comp: Dictionary = {}
	var next_id := 0
	for r: int in rows.size():
		var line := String(rows[r])
		for c: int in line.length():
			var start := Vector2i(c, r)
			if comp.has(start) or line[c] == TowerPlans.WALL_CHAR \
					or line[c] == TowerPlans.GATE_CHAR:
				continue
			var queue: Array[Vector2i] = [start]
			comp[start] = next_id
			while not queue.is_empty():
				var here: Vector2i = queue.pop_back()
				for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0),
						Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = here + step
					if n.x < 0 or n.y < 0 or n.x >= TowerPlans.PLAN_GRID \
							or n.y >= TowerPlans.PLAN_GRID or comp.has(n):
						continue
					var ch := String(rows[n.y])[n.x]
					if ch == TowerPlans.WALL_CHAR or ch == TowerPlans.GATE_CHAR:
						continue
					if _off_the_lane(String(rows[here.y])[here.x], ch):
						continue
					comp[n] = next_id
					queue.append(n)
			next_id += 1

	# Which components each of this storey's rooms occupies. The landing is a room
	# in the graph and a lane in the drawing, so it is read off its own characters.
	var parts: Dictionary = {}   # room id -> { component id: true }
	var letters: Dictionary = {}
	for letter: String in Dictionary(plan.get("rooms", {})):
		letters[letter] = String(plan["rooms"][letter])
	for r2: int in rows.size():
		var line2 := String(rows[r2])
		for c2: int in line2.length():
			var ch2 := line2[c2]
			var room := ""
			if letters.has(ch2):
				room = String(letters[ch2])
			elif ch2 == TowerPlans.LANDING_CHAR or ch2 == TowerPlans.STAIR_UP_CHAR:
				room = String(plan.get("landing", ""))
			if room == "" or not comp.has(Vector2i(c2, r2)):
				continue
			if not parts.has(room):
				parts[room] = {}
			parts[room][comp[Vector2i(c2, r2)]] = true

	var ungated := _ungated_components()
	for edge: Dictionary in _graph["edges"]:
		if not bool(edge.get("built", false)):
			continue
		var a := String(edge["a"])
		var b := String(edge["b"])
		if not parts.has(a) or not parts.has(b):
			continue   # not both drawn here: a ramp between storeys, or off-plan
		var joined := false
		for id: int in Dictionary(parts[a]):
			if Dictionary(parts[b]).has(id):
				joined = true
		if String(edge.get("gate", "")) == "":
			if not joined:
				out.append(("the ungated passage '%s' joins '%s' to '%s', but with every "
					+ "gate shut they are different pieces of this floor — the graph "
					+ "promises a walk the drawing does not have")
					% [String(edge["id"]), a, b])
		elif joined and String(ungated.get(a, a)) != String(ungated.get(b, b)):
			out.append(("'%s' and '%s' are one piece of this floor with every gate shut, "
				+ "but the graph only joins them through '%s' — the drawing offers a way "
				+ "ROUND a door the softlock audit models")
				% [a, b, String(edge["gate"])])
	return out


func _ungated_components() -> Dictionary:
	"""
	Room id -> a representative id, over the graph's BUILT and UNGATED edges only.

	Two rooms share a representative exactly when you can walk between them with
	nothing opened and nobody in particular in the party. Mutations are ignored on
	purpose: this answers "is the door decorative in the building as shipped".
	"""
	if not _ungated_cache.is_empty():
		return _ungated_cache
	for room: String in Dictionary(_graph["rooms"]):
		_ungated_cache[room] = room
	for edge: Dictionary in _graph["edges"]:
		if not bool(edge.get("built", false)) or String(edge.get("gate", "")) != "":
			continue
		var a := String(_ungated_cache.get(String(edge["a"]), ""))
		var b := String(_ungated_cache.get(String(edge["b"]), ""))
		if a == "" or b == "" or a == b:
			continue
		for room2: String in _ungated_cache:
			if String(_ungated_cache[room2]) == b:
				_ungated_cache[room2] = a
	return _ungated_cache


func _plan_cells(plan: Dictionary, want: String) -> Array[Vector2i]:
	"""Every cell of a storey carrying one character, in reading order."""
	var out: Array[Vector2i] = []
	for r: int in plan["rows"].size():
		var line := String(plan["rows"][r])
		for c: int in line.length():
			if line[c] == want:
				out.append(Vector2i(c, r))
	return out


func _is_room_letter(ch: String) -> bool:
	"""A-Z, less the four characters the format has already spent."""
	return ch >= "A" and ch <= "Z" and ch != TowerPlans.STAIR_UP_CHAR \
		and ch != TowerPlans.PAD_CHAR and ch != TowerPlans.POST_CHAR \
		and ch != TowerPlans.GATE_CHAR


func _is_legal_plan_char(ch: String) -> bool:
	return ch == TowerPlans.WALL_CHAR or ch == TowerPlans.FLOOR_CHAR \
		or ch == TowerPlans.LANDING_CHAR or ch == TowerPlans.STAIR_UP_CHAR \
		or ch == TowerPlans.PAD_CHAR or ch == TowerPlans.POST_CHAR \
		or ch == TowerPlans.GATE_CHAR or TowerPlans.pad_digit(ch) > 0 \
		or _is_room_letter(ch)


func _cell_x(c: int) -> float:
	"""The CENTRE of column (or row) `c`, in interior metres. The grid is square."""
	return -TowerPlans.PLAN_HALF + (float(c) + 0.5) * TowerPlans.PLAN_CELL


func _row_at(plan: Dictionary, r: int, line: String) -> Dictionary:
	"""A deep copy of a storey with one row replaced — for the negative controls."""
	var out: Dictionary = plan.duplicate(true)
	out["rows"][r] = line
	return out


func _cell_at(plan: Dictionary, c: int, r: int, ch: String) -> Dictionary:
	"""A deep copy of a storey with one cell replaced — for the negative controls."""
	var line := String(plan["rows"][r])
	return _row_at(plan, r, line.substr(0, c) + ch + line.substr(c + 1))


func _scar_row(id: String) -> Dictionary:
	"""The scar row for `id`, or an empty dict. Local — nothing else wants it."""
	for scar: Dictionary in _graph["scars"]:
		if String(scar["id"]) == id:
			return scar
	return {}


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		if not _plan_summary.is_empty():
			print(_plan_summary)
		print("tower graph: %d rooms, %d edges, %d gates, %d entries, %d scars — %d subset walks clean"
			% [_graph["rooms"].size(), _graph["edges"].size(), _graph["gates"].size(),
				_all_entries().size(), _graph["scars"].size(), _subsets().size()])
		Sentinel.finish(self)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	quit(1)
