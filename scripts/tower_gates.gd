class_name TowerGates
extends RefCounted
## THE TOWER'S GATES AND RIDDLE LOCKS — where a door is, what it looks like, and
## where you stand to work it.
##
## Lifted whole out of `tower_interior.gd` by bead `godot-test1-ftn.21`, the LAST of
## the epic's three tower extractions (plan boxes -> guards -> gates). A MECHANICAL
## move: not one box, colour, travel, tolerance or gate id changed, and the
## acceptance is `gate_slots()` / `_plan_gates()` and every demand and checkpoint box
## byte-identical against master, storey by storey.
##
## THE SPLIT IS STATICS FROM RUNTIME, and the line is exactly where CLAUDE.md draws
## it. Everything here is a pure function of `TowerPlans`' text and `TowerGraph`'s
## rows — which cells a gate fills, what colour it is, where its pads go, how far a
## riddle's mass sinks per step. What STAYED on the node is the GATE RUNTIME: the
## dozen per-gate dictionaries (`_riddle_step`, `_gate_rest`, `_spine_open`, …),
## `_tick_gates` and its `_place_*` writers, `_press_riddle` — and above all
## **`_apply_opened()`, the one place state becomes geometry** and the seam a save
## loads through. That function is named in CLAUDE.md and must not move.
##
## THE GATE IDS ARE `TowerGraph`'S AND ARE NEVER RESTATED HERE. `riddle_ids()` reads
## them off the graph, `gate_slots()` matches the plan's `D` runs to them, and
## `tower_selfcheck` binds the two together in BOTH directions through the
## legibility colours — which are the interior's palette, reached back for at
## runtime like `TowerDressing` does.
##
## DEPENDENCY DIRECTION, and it is the rule bd `godot-test1-ftn.20` paid to learn:
##
##   TowerInterior --const--> TowerGates      (the aliases below its own banner)
##   TowerGates --runtime--> TowerInterior    (the palette, `plan_room_rect`,
##                                             `_cell_span`, `_plan_prefix`, …)
##
## The const direction is ONE WAY and the reach back is only ever inside a function
## body. **No parameter here is typed `TowerInterior`** — a type annotation is a
## parse-time reference exactly like a `const`, and a file that is const-aliased
## from the interior may not make one back. This file needs no interior at all
## (every function is pure), so unlike `TowerGuards` it pays nothing for the rule.
##
## `TowerPlanBoxes`' idiom: `class_name`, all `static`, holds no scene state.

# ============================================================================
# THE RIDDLE LOCK (phase 15) — the fourth gate verb
# ============================================================================
#
# A riddle is a COMBINATION LOCK: four coloured pads in front of a sealed mass,
# pressed in an order painted on a floor somewhere else in the building. It asks
# nothing of who you are and nothing of your ranks — only that you have been to the
# clue room — which is why `tower_graph.gd` calls knowledge party-level and why the
# audit's rule for it is a reachability question and not a capability one.
#
#   Silhouette: a MASS in a doorway, exactly like an identity gate's, with four
#               floor plates in front of it instead of one.
#   Material:   COLOR_RIDDLE, a cold indigo in neither gate family, plus the four
#               pad colours — which are the alphabet the clue is written in.
#   Motion:     it RISES, and one NOTCH per correct step on the way. Up = "the
#               world changed", the identity gate's own sentence.
#   Reads as:   "the answer is somewhere else in this building".

## How far the mass lifts per correct step, at four steps to a lock — the progress
## display, and the demand gate's calibration ladder laid on its side.
##
## THE NUMBER IS CAPPED BY THE PLAYER'S CAPSULE AND NOT CHOSEN FOR LOOKS. A gap a
## `CharacterBody3D` fits through is an open gate, so the whole partial rise has to
## stay well under the 2.0 m capsule; 1.2 m is that with a wide margin, and the
## three-quarters of it a player can actually be looking at is 0.9 m.
##
## ponytail: the mass IS the ladder. A separate stack of four lit bands beside each
## lock would be four more unbatched meshes per riddle for the same four bits, and
## the pads are drawn in front of the mass precisely so the thing you are opening is
## in your eye line. If a later riddle puts its lock out of sight of its gate, that
## is when the bands earn their nodes.
const RIDDLE_NOTCH: float = 1.2

## How hard the mass clunks on a wrong step, scaled by how far in you were — the
## demand gate's `_nudge_ratio` reaction, in the one direction a mass can move.
const RIDDLE_RATTLE: float = 0.22

## How far it travels once solved: ITS OWN HEIGHT, so the doorway is fully clear.
##
## Read off the mass rather than declared, because since phase 16 a mass is as tall
## as the storey it stands on (`plan_clear_height`) and a storey is not always 4.6 m.
## A travel written down separately would leave a lock on a taller floor three
## quarters open — solved, and still a wall.
static func riddle_travel(mass: MeshInstance3D) -> float:
	"""How far one riddle's mass lifts when solved: the height of the mass itself."""
	var box := mass.mesh as BoxMesh
	return 0.0 if box == null else box.size.y

## The receptacle pillar's calibration ladder. `DEMAND_BANDS` is the SCALE the
## player reads: lit bands are their current capability, the full stack is what the
## gate wants. Four is enough to see a shortfall at a glance and few enough to count
## without counting.
##
## WHERE the vault, its shutter and its pillar stand is the PLAN's to say since bead
## `godot-test1-dn8` — the `D` run bound to `GATE_DEMAND` and the plain-floor cell
## `gate_pad_cell()` picks out in front of it. `VAULT_X0`, `VAULT_Z`, `SHUTTER_X0`,
## `SHUTTER_X1`, `RECEPTACLE_X` and `RECEPTACLE_Z` were the keep's authored widths
## and went with the keep; `_demand_boxes()` reads the drawing instead.
const DEMAND_BANDS: int = 4

## WHAT THE DEMAND GATE DEMANDS, and why this number.
##
## Primm's Phase Step reaches `PRIMM_BLINK_DISTANCE` (6.0 m) unskilled and 20% more
## per rank of Long Step. 7.2 m is therefore EXACTLY one rank — the gate is a
## single skill point away for a player who has already found Primm, which makes it
## forecastable ("I know what fixes this") rather than merely refusing. A gate
## calibrated to the maxed 8.4 would be a wall wearing a number.
##
## Read through `player.phase_reach()`, which is the same expression `_ability_primm`
## blinks with — so the gate can never demand a distance the ability does not have.
const DEMAND_TARGET: float = 7.2

## Slack on the calibration comparison, in metres. NOT A FUDGE — a bug fix with a
## constant attached, and the reason it exists is worth the paragraph:
##
##   PRIMM_BLINK_DISTANCE * (1.0 + 0.20) == 7.199999999999999
##
## in IEEE 754, so a gate calibrated to "exactly one rank of Long Step" refused
## exactly one rank of Long Step, while printing "needs 7.2 m, reads 7.2 m" at
## `%.1f` — the single most confusing failure this feature could have. Caught by
## eye in the real game (2026-08-28), not by any structural assertion, which is why
## `tower_interior_selfcheck` now derives the one-rank reading from
## `Progression.SKILL_TREES` and asserts the gate opens for it.
##
## 1 cm is far below any rank step (each is 1.2 m) so it can never let a genuinely
## short reading through; it only makes the comparison mean what the number says.
const DEMAND_TOLERANCE: float = 0.01

## How far the secure mass rises when it opens, and how far the demand shutter
## sinks. Both are a full body-height of travel so the opening is unambiguous, and
## the mass's is enough to carry its foot clear of the shell parapet — the risen
## counterweight is visible from the yard, which is what makes it WORLD state
## rather than a door that quietly stopped being there.
const MASS_TRAVEL: float = 4.4
const SHUTTER_TRAVEL: float = 4.4

## Seconds a gate takes to finish moving. Long enough to watch, short enough that
## nobody waits on it.
const GATE_TIME: float = 1.6

## The partway reaction: how much of its travel the shutter gives an under-strength
## reading, as a fraction, scaled by how close that reading was. A player at 83% of
## the demand sees the slab drop 0.83 * 0.3 of the way and grind back — the shutter
## itself is a second, redundant readout of the same number the bands show.
const NUDGE_FRACTION: float = 0.3
const NUDGE_TIME: float = 1.4


static func riddle_ids() -> Array[String]:
	"""
	Every riddle gate in the graph, in `gates` order.

	Read out of `TowerGraph` rather than listed here, exactly as the identity gate's
	hero is: the building must not be able to hold a riddle the audit has never
	heard of, or miss one it has.
	"""
	var out: Array[String] = []
	for gid: String in TowerGraph.TOWER_GRAPH["gates"]:
		if String(TowerGraph.gate(gid).get("class", "")) == TowerGraph.CLASS_RIDDLE:
			out.append(gid)
	return out


static func gate_slots(plan: Dictionary) -> Dictionary:
	"""
	One storey's gate cells, resolved against the grid it is drawn on.

	@return: `{"masses": {gate id: Rect2i in cells}, "pads": [{gate, digit, c, r}]}`

	The storey's `gates` dict is the ONE binding, for both characters: a `"c,r"` key
	whose cell is a `D` is part of that gate's run, and one whose cell is a lock
	digit is one of its pads. That is what lets a lock and the mass it lifts sit on
	different floors — and `tower_selfcheck` walks the same dict from both ends, so
	neither a cell nobody named nor a name nobody drew can survive a build.

	`"masses"` is EVERY class's `D` run, not just a riddle's: phase 16 gave the
	identity gates and the maintenance crawl `D` cells too, and `_plan_gates` is
	what decides what each run becomes. `"pads"` is only ever a riddle's lock,
	because an identity pad is DERIVED from its own doorway and never drawn.
	"""
	var masses: Dictionary = {}
	var pads: Array[Dictionary] = []
	var rows: Array = plan["rows"]
	var slots: Dictionary = plan["gates"]
	for key: String in slots:
		var parts := key.split(",")
		if parts.size() != 2:
			continue
		var c := int(parts[0])
		var r := int(parts[1])
		if r < 0 or r >= rows.size():
			continue
		var line := String(rows[r])
		if c < 0 or c >= line.length():
			continue
		var gid := String(slots[key])
		var ch := line[c]
		if ch == TowerPlans.GATE_CHAR:
			var span: Rect2i = masses.get(gid, Rect2i(c, r, 1, 1))
			masses[gid] = span.merge(Rect2i(c, r, 1, 1))
		elif TowerPlans.pad_digit(ch) > 0:
			pads.append({"gate": gid, "digit": TowerPlans.pad_digit(ch), "c": c, "r": r})
	return {"masses": masses, "pads": pads}


static func _plan_gates(plan: Dictionary) -> Array[Dictionary]:
	"""
	One storey's gate geometry: what each `D` run becomes, its pads, and any clue
	strip this floor happens to carry.

	@return: `boxes()`-shaped entries. Empty for a storey that draws no gate cell
	        and holds no riddle's clue room.

	ONE ARM PER GATE CLASS, dispatched on `TowerGraph.gate(id)["class"]` — the same
	binding `tower_interior` uses for every other thing it takes from the graph, so
	a gate cannot be drawn in a colour its own row disagrees with:

	  RIDDLE    the MASS, indigo, floor slab to ceiling so it can be neither jumped
	            nor crawled. It travels, so it carries `dynamic` and stays out of
	            the batch. Its four lock pads are DRAWN (`1`-`4` cells) and coloured
	            from `COLOR_RIDDLE_PADS`.
	  IDENTITY  the same mass in the hero's violet, plus ONE pad, which is not drawn
	            at all — see `gate_pad_cell()` for why it is derived.
	  CHALLENGE a LINTEL: a partial-height wall over the run, in ordinary stone and
	            batched, so the opening reads as a duct. The hazard that sweeps
	            under it is hand-built from the same run (`_block_boxes` for the
	            crawl's press), because a thing that moves is not a plan character.
	            The secure checkpoint is
	            the one authored exception: its graph row declares `GEOMETRY_MASS`
	            so the rising mass and derived pad remain while access stays base kit.
	  DEMAND    nothing at all. Its shutter SINKS rather than rising and its
	            receptacle is not a character either, so `_demand_boxes` builds the
	            whole gate off the same run — see the arm for the argument.

	The CLUE is four plates in a row on the clue room's floor, in the answer's order
	and the answer's colours. DERIVED FROM THE ANSWER ARRAY, so the clue cannot
	drift from the lock it explains — the failure a hand-painted clue would
	eventually have, and one no self-check could see.
	"""
	var out: Array[Dictionary] = []
	var floor_index := int(plan["floor"])
	var prefix := TowerInterior._plan_prefix(floor_index)
	var top: float = TowerPlanBoxes.FLOOR_Y[floor_index]
	var slots := gate_slots(plan)

	# Slab to ceiling, so a mass can be neither jumped nor crawled — and the ceiling
	# is this storey's, which is not every storey's (`plan_clear_height`).
	var clear := TowerPlanBoxes.plan_clear_height(floor_index)
	var masses: Dictionary = slots["masses"]
	for gid: String in masses:
		var span: Rect2i = masses[gid]
		var x0 := TowerPlanBoxes._grid_x(float(span.position.x))
		var x1 := TowerPlanBoxes._grid_x(float(span.end.x))
		var z0 := TowerPlanBoxes._grid_z(float(span.position.y))
		var z1 := TowerPlanBoxes._grid_z(float(span.end.y))
		var gate := TowerGraph.gate(gid)
		var cls := String(gate.get("class", ""))
		if cls == TowerGraph.CLASS_DEMAND:
			# NOTHING, on purpose. A demand gate's mass SINKS — it is the one gate in
			# the building that opens downwards — so the generic mass above, which is
			# drawn to be lifted and retired, would be the wrong body in the right
			# hole. And a demand gate is not just a mass: its RECEPTACLE and its four
			# calibration bands are the whole of its legibility, and a pillar standing
			# in front of a door is not a plan character. `_demand_boxes()` reads this
			# same run and builds all six.
			continue
		# Access class and authored silhouette are separate. The secure checkpoint
		# is base kit (challenge semantics), but its existing rising mass and derived
		# pad are part of the shipped floor plan and must remain in the doorway.
		var geometry := String(gate.get("geometry", ""))
		if cls == TowerGraph.CLASS_CHALLENGE and geometry != TowerGraph.GEOMETRY_MASS:
			var lintel_h := clear - TowerInterior.CRAWL_LINTEL_Y
			out.append({
				"name": "%sGateLintel_%s" % [prefix, gid],
				"pos": Vector3((x0 + x1) * 0.5, top + TowerInterior.CRAWL_LINTEL_Y + lintel_h * 0.5,
						(z0 + z1) * 0.5),
				"size": Vector3(x1 - x0, lintel_h, z1 - z0),
				"color": TowerInterior.COLOR_STONE, "collide": true, "floor": floor_index,
			})
			continue
		var identity := cls == TowerGraph.CLASS_IDENTITY
		var mass_style := geometry == TowerGraph.GEOMETRY_MASS
		out.append({
			"name": "%sGateMass_%s" % [prefix, gid],
			"pos": Vector3((x0 + x1) * 0.5, top + clear * 0.5, (z0 + z1) * 0.5),
			"size": Vector3(x1 - x0, clear, z1 - z0),
			# A mass override does not turn a base-kit challenge into an identity
			# gate visually. Violet is reserved for doors that name a hero; this
			# checkpoint remains hazard orange like the other challenge geometry.
			"color": TowerInterior.COLOR_IDENTITY if identity else TowerInterior.COLOR_HAZARD if mass_style else TowerInterior.COLOR_RIDDLE,
			"collide": true, "floor": floor_index,
			"dynamic": true,
		})
		if not identity and not mass_style:
			continue
		# ...and the one pad you stand on, on the side of the doorway you approach
		# it from. An unresolvable side is an AUTHORING ERROR and is left unbuilt
		# rather than guessed at: `tower_selfcheck` fails a gate with no pad, which
		# is the report the author needs. A pad on the wrong side of a door would be
		# a gate you open from inside the room it guards.
		var cell := gate_pad_cell(plan, span)
		if cell.x < 0:
			continue
		out.append({
			"name": "%sGatePad_%s" % [prefix, gid],
			"pos": Vector3(TowerPlanBoxes._grid_x(float(cell.x) + 0.5), top + TowerPlanBoxes.PLAN_PAD_THICK * 0.5,
					TowerPlanBoxes._grid_z(float(cell.y) + 0.5)),
			"size": Vector3(TowerPlans.PLAN_CELL, TowerPlanBoxes.PLAN_PAD_THICK, TowerPlans.PLAN_CELL),
			"color": TowerInterior.COLOR_IDENTITY_PAD if identity else TowerInterior.COLOR_HAZARD,
			"collide": false, "floor": floor_index,
		})

	for pad: Dictionary in slots["pads"]:
		out.append(_riddle_plate("%sRiddlePad_%s_%d" % [prefix, String(pad["gate"]),
				int(pad["digit"])], int(pad["c"]), int(pad["r"]), int(pad["digit"]),
				floor_index, TowerPlans.PLAN_CELL))

	# ...and any clue this storey happens to carry. A riddle's clue room is named in
	# the GRAPH, so the storey that draws that room paints the strip whether or not
	# it draws any of the riddle's own cells — which is the whole point of a clue.
	for gid2: String in riddle_ids():
		var strip := clue_strip(gid2)
		if strip.is_empty() or int(strip["floor"]) != floor_index:
			continue
		var answer: Array = TowerGraph.gate(gid2)["answer"]
		for i: int in answer.size():
			out.append(_riddle_plate("%sRiddleClue_%s_%d" % [prefix, gid2, i],
					int(strip["c"]) + i, int(strip["r"]), int(answer[i]), floor_index,
					TowerPlans.PLAN_CELL * 0.7))
	return out


static func gate_pad_cell(plan: Dictionary, span: Rect2i) -> Vector2i:
	"""
	Which cell a rising mass's pad stands on, `Vector2i(-1, -1)` when the plan
	cannot say. This serves named identity gates and the base-kit secure mass.

	@param span: The gate's `D` run, in cells.

	DERIVED, NEVER AUTHORED. Of the four cells 4-adjacent to the run's midpoint,
	exactly ONE must be plain floor, and that is the corridor side — the side you
	walk up to the door from. The run's own cells are `D`, the wall it is cut into
	is `#` and the room it guards is a lettered room, so in a well-drawn plan
	exactly one neighbour is ever `.`; the two-sided and no-sided cases are
	authoring errors, and `tower_selfcheck` names them rather than this file
	guessing. A pad on the wrong side of a door is a gate you open from inside the
	room it guards.
	"""
	var rows: Array = plan["rows"]
	var mid := span.position + span.size / 2
	var found := Vector2i(-1, -1)
	var seen := 0
	for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var cell := mid + step
		if cell.x < 0 or cell.y < 0 or cell.y >= rows.size():
			continue
		var line := String(rows[cell.y])
		if cell.x >= line.length() or line[cell.x] != TowerPlans.FLOOR_CHAR:
			continue
		found = cell
		seen += 1
	return found if seen == 1 else Vector2i(-1, -1)


static func _riddle_plate(plate_name: String, c: int, r: int, digit: int,
		floor_index: int, side: float) -> Dictionary:
	"""One coloured plate on a storey's floor — a lock pad or a clue mark."""
	return {
		"name": plate_name,
		"pos": Vector3(TowerPlanBoxes._grid_x(float(c) + 0.5), TowerPlanBoxes.FLOOR_Y[floor_index] + TowerPlanBoxes.PLAN_PAD_THICK * 0.5,
				TowerPlanBoxes._grid_z(float(r) + 0.5)),
		"size": Vector3(side, TowerPlanBoxes.PLAN_PAD_THICK, side),
		"color": TowerInterior.COLOR_RIDDLE_PADS[clampi(digit - 1, 0, TowerInterior.COLOR_RIDDLE_PADS.size() - 1)],
		"collide": false, "floor": floor_index,
	}


static func clue_strip(gate_id: String) -> Dictionary:
	"""
	Where one riddle's clue is painted: `{floor, c, r}`, the WEST end of the strip.

	@return: `{}` when the gate is not a riddle, or when no storey draws its clue
	        room — which `tower_selfcheck` fails on rather than shrugging at.

	DERIVED FROM THE CLUE ROOM'S OWN CELLS, centred on their bounding box, because
	an authored xz would be a third place the plan has to agree with itself. The
	self-check asserts every plate lands on a plain cell of that room, so a strip
	that ran into a wall or over a system pad fails the build.
	"""
	var room_id := String(TowerGraph.gate(gate_id).get("clue_room", ""))
	var answer: Array = TowerGraph.gate(gate_id).get("answer", [])
	if room_id == "" or answer.is_empty():
		return {}
	for floor_index: int in TowerPlans.floors():
		var plan := TowerPlans.storey(floor_index)
		var letter := ""
		for key: String in plan["rooms"]:
			if String(plan["rooms"][key]) == room_id:
				letter = key
				break
		if letter == "":
			continue
		var span := Rect2i()
		var first := true
		for r: int in plan["rows"].size():
			var line := String(plan["rows"][r])
			for c: int in line.length():
				if line[c] != letter:
					continue
				var cell := Rect2i(c, r, 1, 1)
				span = cell if first else span.merge(cell)
				first = false
		if first:
			continue
		var start := span.position.x + int(floorf(float(span.size.x - answer.size()) * 0.5))
		return {
			"floor": floor_index,
			"c": start,
			"r": span.position.y + span.size.y / 2,
		}
	return {}


static func plan_gate_rect(floor_index: int, gate_id: String) -> Rect2i:
	"""
	The cell bounding box of one gate's `D` run on one storey, `Rect2i()` if absent.

	`gate_slots()` already walks the storey's `gates` dict from both ends; this is
	that walk looked up by id, and deliberately not a second walker.
	"""
	var plan := TowerPlans.storey(floor_index)
	if plan.is_empty():
		return Rect2i()
	return gate_slots(plan)["masses"].get(gate_id, Rect2i())


static func plan_doorway_rect(floor_index: int, room_id: String) -> Rect2i:
	"""
	The plain-floor gap in the wall row on the +Z side of one room's cells.

	@return: The doorway's cells, or `Rect2i()` when that row has no gap.

	THE ONE DOORWAY IN THIS BUILDING WITH NOTHING DRAWN IN IT. `block_main_door` is
	ungated, so it has no `D` and no `gates` entry to look up — and the custody
	scar's rubble has to stand exactly in it. Rather than write its cells down a
	second time, this reads the wall the corridor's south side is closed by and
	returns the run somebody can walk through. A wall with two gaps in it would be
	two doorways and is not what this answers; the run it returns is the first.
	"""
	var rect := TowerInterior.plan_room_rect(floor_index, room_id)
	if rect.size == Vector2i.ZERO:
		return Rect2i()
	var plan := TowerPlans.storey(floor_index)
	var r := rect.end.y
	if r >= plan["rows"].size():
		return Rect2i()
	var line := String(plan["rows"][r])
	var span := Rect2i()
	var first := true
	for c: int in range(rect.position.x, mini(rect.end.x, line.length())):
		if line[c] != TowerPlans.FLOOR_CHAR:
			if not first:
				break
			continue
		var cell := Rect2i(c, r, 1, 1)
		span = cell if first else span.merge(cell)
		first = false
	return Rect2i() if first else span


## The room whose presence says "this storey draws the cell block". Keyed on a
## graph room and never on a floor number, so the block is wherever it is drawn.


static func gate_stand(gate_id: String, steps: int) -> Vector3:
	"""
	Where a player stands to work one gate: the centre of the cell `steps` out from
	its `D` run, on the side `gate_pad_cell()` picked.

	@param steps: 1 is the pad cell itself (an identity gate's plate); 2 is one cell
	        further back, which is where you end up when something SOLID stands on
	        the pad — the demand gate's receptacle pillar.
	@return: interior-local metres at the storey's walking surface, `Vector3.ZERO`
	        when no storey draws the gate or the drawing cannot say which side.

	DERIVED, LIKE THE PAD ITSELF. Every trigger volume in the phase-3 keep used to
	be an authored `Vector3` beside an authored mass; bead `godot-test1-dn8` drew
	both gates on the grid, and a trigger that did not follow the drawing would be
	a plate you stand on and a volume three metres away.
	"""
	for floor_index: int in TowerPlans.floors():
		var run := plan_gate_rect(floor_index, gate_id)
		if run.size == Vector2i.ZERO:
			continue
		var pad := gate_pad_cell(TowerPlans.storey(floor_index), run)
		if pad.x < 0:
			return Vector3.ZERO
		var cell := pad + (pad - (run.position + run.size / 2)) * (steps - 1)
		return Vector3(TowerPlanBoxes._grid_x(float(cell.x) + 0.5), TowerPlanBoxes.FLOOR_Y[floor_index],
				TowerPlanBoxes._grid_z(float(cell.y) + 0.5))
	return Vector3.ZERO


static func checkpoint_stand() -> Vector3:
	"""
	Where a knockback drops a player who HAS lit the checkpoint.

	Inside `CheckpointTrigger`'s volume and clear of `CheckpointPost` by
	`CHECKPOINT_CLEAR` — "the checkpoint" is the space beside the post, not the
	post's own footprint. It was a `const Vector3` authored against the keep's upper
	floor until bead `godot-test1-dn8`; it is now the room's own cells, so moving
	the checkpoint in the ASCII moves the respawn with it.
	"""
	var floor_index := TowerInterior.room_floor(TowerInterior.CHECKPOINT_ROOM)
	if floor_index < 0:
		return entry_stand()
	var room := TowerInterior._cell_span(TowerInterior.plan_room_rect(floor_index, TowerInterior.CHECKPOINT_ROOM))
	return Vector3((room["x0"] + room["x1"]) * 0.5 - TowerInterior.CHECKPOINT_CLEAR,
			TowerPlanBoxes.FLOOR_Y[floor_index] + 0.2, (room["z0"] + room["z1"]) * 0.5)


static func entry_stand() -> Vector3:
	"""
	...and where it drops a player who has not: just inside the front door.

	Derived from the SHELL's own door constants and clear of the trigger volume by a
	metre, so a setback never lands you in the doorway you are about to re-enter.
	The x moved outward with bead `godot-test1-dn8`: the keep's own door — the one
	this used to stand behind — no longer exists, and there is one ring now.
	"""
	return Vector3(TowerPlans.PLAN_HALF - TowerShell.DOOR_TRIGGER_DEPTH - 1.0, 0.2, 0.0)


static func _demand_boxes(plan: Dictionary) -> Array[Dictionary]:
	"""
	The demand gate: the shutter that sinks, the receptacle pillar you read it from,
	and the four calibration bands up its face.

	@return: `DemandShutter`, `Receptacle`, `Band1`..`Band4`. Every name is kept
	        exactly — they are claimed by `TOWER_GRAPH`, held in `MOVING_PARTS` and
	        looked up by `_remember()`, and keeping them is what makes this a
	        geometry move rather than a rename.

	`_plan_gates` deliberately builds NOTHING for a demand gate (see its
	`CLASS_DEMAND` arm): a shutter sinks where every other mass in the building
	rises, and a receptacle is not a plan character at all. So the run is read here
	and the pillar stands on the cell `gate_pad_cell()` picked — the side of the
	doorway you walk up from, drawn rather than authored — with the bands on the
	face that looks back at you. `bottom band first`, because `_update_bands()`
	lights them by index.
	"""
	var floor_index := int(plan["floor"])
	var top: float = TowerPlanBoxes.FLOOR_Y[floor_index]
	var clear := TowerPlanBoxes.plan_clear_height(floor_index)
	var slot := plan_gate_rect(floor_index, TowerInterior.GATE_DEMAND)
	var run := TowerInterior._cell_span(slot)
	var out: Array[Dictionary] = [{
		"name": "DemandShutter",
		"pos": Vector3((run["x0"] + run["x1"]) * 0.5, top + clear * 0.5,
				(run["z0"] + run["z1"]) * 0.5),
		"size": Vector3(run["x1"] - run["x0"], clear, run["z1"] - run["z0"]),
		"color": TowerInterior.COLOR_MECHANISM, "collide": true, "floor": floor_index,
		"dynamic": true,
	}]
	var pad := gate_pad_cell(plan, slot)
	if pad.x < 0:
		return out   # an authoring error `tower_selfcheck` names; never guessed at.
	var step := pad - (slot.position + slot.size / 2)
	var face := Vector3(float(step.x), 0.0, float(step.y))
	var at_x := TowerPlanBoxes._grid_x(float(pad.x) + 0.5)
	var at_z := TowerPlanBoxes._grid_z(float(pad.y) + 0.5)
	# The pillar is THIN ACROSS THE APPROACH and wide along it, whichever axis the
	# drawing put the doorway on, so its face is the one you are looking at.
	var along_x := absf(face.x) > absf(face.z)
	out.append({
		"name": "Receptacle",
		"pos": Vector3(at_x, top + 1.3, at_z),
		"size": Vector3(0.6, 2.6, 1.0) if along_x else Vector3(1.0, 2.6, 0.6),
		"color": TowerInterior.COLOR_MECHANISM, "collide": true, "floor": floor_index,
	})
	for i in DEMAND_BANDS:
		out.append({
			"name": "Band%d" % (i + 1),
			"pos": Vector3(at_x + face.x * 0.35, top + 0.75 + 0.45 * float(i),
					at_z + face.z * 0.35),
			"size": Vector3(0.1, 0.18, 0.7) if along_x else Vector3(0.7, 0.18, 0.1),
			"color": TowerInterior.COLOR_BAND_DARK, "collide": false, "floor": floor_index,
		})
	return out


static func _checkpoint_boxes(plan: Dictionary) -> Array[Dictionary]:
	"""
	The checkpoint: a plate you cross and the post standing on it, both relit once.

	@return: `CheckpointPlate` (0.1 m proud and never solid — a lip of any height is
	        a wall in this engine) and `CheckpointPost`, centred in the room the plan
	        letters `checkpoint_room`.

	It is a MARKER and not a passage — `GATE_CHECKPOINT` gates no edge, and check 1
	of `tower_selfcheck` refuses it as one — so the room's own `parts` claim these
	two boxes rather than a gate row.
	"""
	var floor_index := int(plan["floor"])
	var top: float = TowerPlanBoxes.FLOOR_Y[floor_index]
	var room := TowerInterior._cell_span(TowerInterior.plan_room_rect(floor_index, TowerInterior.CHECKPOINT_ROOM))
	var at_x: float = (room["x0"] + room["x1"]) * 0.5
	var at_z: float = (room["z0"] + room["z1"]) * 0.5
	return [
		{
			"name": "CheckpointPlate",
			"pos": Vector3(at_x, top + 0.05, at_z),
			"size": Vector3(3.0, 0.1, 3.0),
			"color": TowerInterior.COLOR_CHECKPOINT, "collide": false, "floor": floor_index,
		},
		{
			"name": "CheckpointPost",
			"pos": Vector3(at_x, top + 1.3, at_z),
			"size": Vector3(0.7, 2.6, 0.7),
			"color": TowerInterior.COLOR_CHECKPOINT, "collide": true, "floor": floor_index,
		},
	]
