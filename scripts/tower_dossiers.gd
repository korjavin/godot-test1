class_name TowerDossiers
extends RefCounted
## THE EVIDENCE DOSSIERS — the HQ's six findings, lifted whole out of
## `tower_interior.gd` (bd godot-test1-ftn.12).
##
## THE SPLIT. `TowerInterior` keeps the BUILDING; this file keeps the one pickup
## standing in it — the authored table, the crawl-alcove lintel it hangs, the
## footprints it reserves against the dresser, the `MultiMesh` rack and its
## multiplayer replay. The seams are four lines in the interior: `plan_boxes()`
## appends `alcove_boxes()` and reserves `marks()`, `_ready()` calls `build()` and
## defers `latch()`, `_process()` calls `tick()`, and `_update_visibility()` calls
## `refresh()` when the drawn window moves.
##
## IT IS A MOVE AND NOTHING ELSE — the rules, the measured numbers, the six lore
## lines and every comment arrived unchanged, and the acceptance was that
## `DRAW_BUDGET`, `SURFACE_BUDGET` and check 20's box counts do not move by one.
##
## WHY STATIC FUNCTIONS THAT TAKE `interior`. `landmark_builders.gd`'s contract, one
## building along: there is no dossier state to hold that is not the interior
## NODE's — the rack is its child and the found set is per-run on it — so a static
## library that is handed the node costs no object and keeps the four state vars
## exactly where the rest of the interior can still see them. The one thing that
## stayed behind is `_on_dossier_enter`, because a `body_entered` handler belongs to
## the node whose `Area3D` emits it.


# ============================================================================
# THE EVIDENCE DOSSIERS (bead godot-test1-3iy.23) — the HQ's findings
# ============================================================================
#
# Six folders of GastroDefense paperwork, standing at HAND-PICKED cells on the
# office and operations storeys. Walk into one and it pays coins and tells you a
# line about the corporation; it is gone for the rest of the run and back on the
# next one, exactly like a coin.
#
# AUTHORED, LIKE EVERY OTHER THING IN THIS BUILDING. The table below is a const of
# plain dicts — no `run_seed`, no `randf`, no `hash` — for the reason `TowerPlans`
# gives at length: a tower whose contents moved between runs would mean the
# softlock audit certified a layout nobody plays. A designer moves a dossier by
# editing a `Vector2i` here.
#
# WHERE THEY MAY STAND, and the self-check asserts all of it: floors 2..6 (the
# office and ops storeys), never the labyrinth and never the cell block — those two
# are a maze and a jail and neither wants a scavenger hunt in it; a cell that is
# open on its storey's plan and reached by the same flood fill; and a cell nothing
# else this storey draws already occupies. That last one is `marks()`,
# which is handed to `TowerDressing.plan_dressing` as though the dossier were a set
# piece, so a derived desk can never land on top of a pickup.
#
# TWO OF THE SIX ARE GATED, and neither gate is new machinery:
#
#   * THE CRAWL ALCOVE — a one-cell dead end off storey 3's west record stack with
#     a lintel `DOSSIER_CRAWL_CLEAR` off the floor over its mouth. The player's
#     capsule is 2.0 m and small Teibi's is `TEIBI_SCALE_SMALL` of that (0.9 m), so
#     the alcove asks for a hero nobody has to bring and refuses everybody else.
#     SMALL is the one resize allowed indoors (owner ruling godot-test1-xdf refuses
#     only growth), and the maintenance crawl in the cell block is the same idea a
#     metre and a half higher. The 2-D audits cannot see a height gate, which is
#     exactly why the alcove's cells stay ordinary floor in `TowerPlans`.
#   * THE GUARD-CONE SPOT — a dossier standing in the stretch of corridor storey
#     3's sentry watches. It is PURE CELL CHOICE and zero code: the guard's 120
#     degree cone and its walked beat are already there, and taking the folder is a
#     matter of timing the beat. It must stay takeable by timing ALONE — the lure
#     plates (bead godot-test1-3iy.22) make it easier and are never required.
#
# NO PHASE-STEP SPOT, and that is a ruling rather than an omission: a blink-only
# sealed nook is either cells the flood fill cannot reach or a hole in a wall that
# `tower_selfcheck`'s gates-shut component rule is built to catch. An indoor blink
# challenge needs an audit-sanctioned mechanism of its own.

## What one dossier pays. Three gems (a gem is `Coin.GEM_VALUE`, 10), because a
## dossier is authored, one-per-run and often behind something — provisional
## against the coin economy and the one number to turn if they feel cheap.
const DOSSIER_VALUE: int = 30

## The folder itself: a squat matte box you read as paperwork on the floor.
const DOSSIER_SIZE := Vector3(0.62, 0.34, 0.44)

## Manila. Deliberately NOT a `GLOW_COLORS` entry — an emissive dossier would
## commit the rack a second surface (see `SURFACE_BUDGET`) to say something the
## shape already says.
const COLOR_DOSSIER := Color(0.88, 0.76, 0.46)

## The card's heading. A plain literal, so Godot's `Control` auto-translation picks
## it up off `assets/translations/ui.csv` with no `tr()` — localization RULE 1, and
## the same reason `landmark_toast` has none.
const DOSSIER_TITLE: String = "EVIDENCE DOSSIER"

## Clear air under the crawl alcove's lintel. Over small Teibi (2.0 m capsule at
## `TEIBI_SCALE_SMALL` 0.45 = 0.90 m) with room to walk, and comfortably under the
## 2.0 m everybody else is — the self-check reads both out of `player_controller`
## rather than restating either.
const DOSSIER_CRAWL_CLEAR: float = 1.2

## How often a peer standing in the HQ re-reads the room's collected set — see
## `tick()` for why a poll and not a third loop in the manager's sweep.
const DOSSIER_POLL: float = 0.5

## `Coin.id_at()` is the pickup id every peer agrees on, and a dossier borrows it
## rather than inventing a second scheme — which is the whole reason `mp_manager`
## needed no edit for this bead. See `id_of()`.
const COIN_SCRIPT: GDScript = preload("res://scripts/coin.gd")

## THE SIX, in the order their ids and their trigger names are derived from.
##
##   floor   int      index into `FLOOR_Y`; must be an office or ops storey (2..6).
##   cell    Vector2i `(column, row)` on that storey's `TowerPlans` grid.
##   alcove  bool     optional — this one stands in a crawl alcove, so the builder
##                    hangs a lintel over its cell (see `alcove_boxes`).
##   lore    String   the line the card shows. Player-facing, so it is a row in
##                    `ui.csv` in both languages and carries no `tr()` (RULE 1).
const DOSSIERS: Array[Dictionary] = [
	# Storey 3, the records floor. THE CRAWL ALCOVE: the cupboard bitten out of the
	# pier between the two west record stacks — see the storey's own comment block.
	{
		"floor": 2, "cell": Vector2i(10, 12), "alcove": true,
		"lore": "Shredder log, west stack: 41,000 pages, one afternoon, no reason given.",
	},
	# ...and THE GUARD-CONE SPOT, out in the north ring corridor two cells along the
	# sentry's beat. Nothing in the code knows that; the post is a `G` on the plan.
	{
		"floor": 2, "cell": Vector2i(26, 2),
		"lore": "Retrieval order 7: \"subject is fond of the four. Collect all four.\"",
	},
	# Storey 4, the accounts floor: deep in a supply office.
	{
		"floor": 3, "cell": Vector2i(5, 30),
		"lore": "Invoice, unpaid: 300 crocodile crates, delivered to the riverbank.",
	},
	# Storey 5, the executive floor: the audit suite, which audited nothing.
	{
		"floor": 4, "cell": Vector2i(10, 32),
		"lore": "Board minute: \"the field programme is not a programme. Bill it anyway.\"",
	},
	# Storey 6, operations: the control centre the fleet is dispatched from.
	{
		"floor": 5, "cell": Vector2i(20, 10),
		"lore": "Dispatch sheet: every unit sent north. Nobody wrote down who asked.",
	},
	# Storey 7, security: the briefing room under the labyrinth.
	{
		"floor": 6, "cell": Vector2i(10, 28),
		"lore": "Briefing card: \"the maze upstairs is not for intruders. It is for us.\"",
	},
]

## The storeys a dossier may stand on — the offices and operations, never the
## labyrinth and never the cell block. A range rather than a list because that is
## what the bead ruled and what the self-check asserts.
const DOSSIER_FLOOR_MIN: int = 2
const DOSSIER_FLOOR_MAX: int = 6



# ============================================================================
# THE EVIDENCE DOSSIERS — geometry (see the DOSSIERS banner for the design)
# ============================================================================

static func point(index: int) -> Vector3:
	"""
	Where dossier `index` stands, in interior-local metres — its BOX CENTRE.

	@return: `Vector3.INF` for an index no row names, which every caller treats as
	    "there is no such dossier".

	The centre and not the cell corner, because this is also what `id_of()`
	hashes: the id has to name the same 12.5 cm cell on every peer, and the only
	way to promise that is to derive both the picture and the name from one point.
	"""
	if index < 0 or index >= DOSSIERS.size():
		return Vector3.INF
	var row: Dictionary = DOSSIERS[index]
	var floor_index := int(row["floor"])
	var cell: Vector2i = row["cell"]
	return Vector3(TowerInterior._grid_x(float(cell.x) + 0.5),
			TowerInterior.FLOOR_Y[floor_index] + DOSSIER_SIZE.y * 0.5,
			TowerInterior._grid_z(float(cell.y) + 0.5))


static func marks(floor_index: int) -> Array[Dictionary]:
	"""
	One storey's dossier cells as bare footprints, for the dresser to keep clear.

	@return: `{pos, size}` entries — the two keys `TowerDressing._cell_is_taken()`
	    reads, and deliberately not `boxes()` entries: nothing here is ever drawn or collided
	    with, so a full box row carrying a name and a colour would invite somebody
	    to append it to `all_boxes()` and blow the budgets it is here to protect.

	The footprint is the WHOLE CELL rather than the folder, so the dresser refuses
	the cell a dossier stands in and nothing more: `TowerDressing._cell_is_taken`
	insets a candidate by `TowerDressing.DRESS_EPS` on all four sides, so a box that
	exactly fills one cell cannot reach the next one.
	"""
	var out: Array[Dictionary] = []
	for index: int in DOSSIERS.size():
		if int(DOSSIERS[index]["floor"]) != floor_index:
			continue
		var cell: Vector2i = DOSSIERS[index]["cell"]
		out.append({
			"pos": Vector3(TowerInterior._grid_x(float(cell.x) + 0.5),
					TowerInterior.FLOOR_Y[floor_index],
					TowerInterior._grid_z(float(cell.y) + 0.5)),
			"size": Vector3(TowerPlans.PLAN_CELL, TowerInterior.PLAN_PAD_THICK,
					TowerPlans.PLAN_CELL),
		})
	return out


static func alcove_boxes(plan: Dictionary) -> Array[Dictionary]:
	"""
	The lintel over a crawl alcove's mouth — the whole of the Teibi gate.

	@return: one box per `alcove` row on this storey, or `[]`.

	IT FILLS THE ALCOVE CELL FROM `DOSSIER_CRAWL_CLEAR` TO THE CEILING, which is
	what makes it stone rather than a step: check 2's structural rule is "a plan
	storey has exactly two kinds of solid — floor, and stone reaching the ceiling"
	and a box whose top stopped short of `TowerInterior.plan_clear_height()` would be
	a ledge you could jump onto. The maintenance crawl's lintel is the same shape
	1.6 m higher.

	The alcove is ordinary `.` floor on the drawing and must stay that way: both
	flood fills are 2-D, so this gate is invisible to them BY DESIGN — the alcove is
	a dead end that gates a pickup and never a route, so there is nothing for them
	to be wrong about.
	"""
	var out: Array[Dictionary] = []
	var floor_index := int(plan["floor"])
	var surface: float = TowerInterior.FLOOR_Y[floor_index]
	var top := surface + TowerInterior.plan_clear_height(floor_index)
	var bottom := surface + DOSSIER_CRAWL_CLEAR
	for index: int in DOSSIERS.size():
		var row: Dictionary = DOSSIERS[index]
		if int(row["floor"]) != floor_index or not bool(row.get("alcove", false)):
			continue
		var cell: Vector2i = row["cell"]
		out.append({
			"name": "%sDossierLintel%d" % [TowerInterior._plan_prefix(floor_index), index],
			"pos": Vector3(TowerInterior._grid_x(float(cell.x) + 0.5), (bottom + top) * 0.5,
					TowerInterior._grid_z(float(cell.y) + 0.5)),
			"size": Vector3(TowerPlans.PLAN_CELL, top - bottom, TowerPlans.PLAN_CELL),
			"color": TowerInterior.COLOR_STONE, "collide": true, "floor": floor_index,
		})
	return out


static func id_of(interior: TowerInterior, index: int) -> int:
	"""
	The pickup id every peer in a room agrees this dossier has.

	`Coin.id_at()` of its WORLD position, which is exactly what a field coin does —
	and the reason `mp_manager.gd` needed no edit for this feature: the claim, the
	confirm, the shared bank, the room multiplier and the join replay all already
	speak in these ids. World and not local, because the id namespace is shared with
	the field's coins and two things at different places must not collide.

	A DOSSIER NEVER MOVES, so unlike a coin there is nothing to latch against: the
	bob is what forced `coin.gd` to freeze its id at spawn, and this stands still.
	Callers must still be past the frame `endless_terrain` parks the shell on the
	tower site — see `latch(interior)`, which is deferred for that reason.
	"""
	var local := point(index)
	if not local.is_finite():
		return 0
	return int(COIN_SCRIPT.id_at(interior.global_position + local))


static func build(interior: TowerInterior) -> void:
	"""
	The six evidence dossiers: ONE `MultiMeshInstance3D` and one trigger apiece.

	WHY A MULTIMESH AND NOT SIX MESHES, since it is the one place this building
	breaks its own "authored geometry, not chunk content" habit. A dossier has to
	vanish when it is taken, which is exactly what the storey's merged batch cannot
	do — and six `MeshInstance3D` would be six nodes AND six surfaces against a
	`SURFACE_BUDGET` measured at 48 of 54. A multimesh is one node, one surface and
	one draw for as many dossiers as anyone ever authors, and hiding one is writing
	a zero-scaled transform. `DRAW_BUDGET` 37 -> 38 and surfaces 48 -> 49 is the
	whole cost, and check 5 asserts both by name.

	THE TRIGGERS ARE `_add_area`'s, like every pad in the building, so they hide
	with their storey and cost nothing while it is not drawn — and they are the only
	reason the rack itself never needs a collision shape.
	"""
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.mesh = TowerInterior._box_mesh(DOSSIER_SIZE)
	mesh.instance_count = DOSSIERS.size()
	interior._dossier_rack = MultiMeshInstance3D.new()
	interior._dossier_rack.name = "DossierRack"
	interior._dossier_rack.multimesh = mesh
	# One shared material out of the same per-colour cache every other part of this
	# building draws from — never a duplicate, and already `DIFFUSE_TOON`.
	interior._dossier_rack.material_override = TowerInterior._material(COLOR_DOSSIER)
	TowerInterior._no_shadow(interior._dossier_rack)
	interior.add_child(interior._dossier_rack)
	var cell := Vector3(TowerPlans.PLAN_CELL, 2.0, TowerPlans.PLAN_CELL)
	for index: int in DOSSIERS.size():
		var at := point(index)
		if not at.is_finite():
			continue
		interior._add_area("DossierTrigger%d" % index,
				Vector3(at.x, at.y + 0.5, at.z), cell,
				interior._on_dossier_enter.bind(index), Callable(),
				int(DOSSIERS[index]["floor"]))
	refresh(interior)


static func refresh(interior: TowerInterior) -> void:
	"""
	Re-decide which dossiers are drawn: not yet taken, and on a storey being drawn.

	A HIDDEN INSTANCE KEEPS ITS ORIGIN and loses its basis, rather than being moved
	away — so the rack's transforms stay a readable statement of where the dossiers
	are whatever their state, which is what the self-check reads them as.

	WRITTEN AS ONE `buffer`, NOT AS SIX `set_instance_transform` CALLS, and the
	reason is measurement rather than throughput (six calls is nothing). The
	per-instance setter writes THROUGH to the RenderingServer and reads back from it,
	and under `--headless` — which is every self-check and all of CI — that server is
	the dummy driver: the write vanishes and the read answers with an identity
	transform. `buffer` round-trips on the resource, so the state a check reads is
	the state the renderer is handed. It is also the bulk path the engine documents.

	`interior._drawn_floor < 0` means no frame has decided a window yet (a standalone
	build in a self-check, or the frame before the first `_process`), and then everything
	uncollected is drawn — the same "degrade to visible" every seam in this file
	takes when the thing it would ask is not there.
	"""
	if interior._dossier_rack == null:
		return
	var window := interior._drawn_floor >= 0 \
			and interior._drawn_floor < TowerInterior.FLOOR_Y.size()
	var buffer := PackedFloat32Array()
	buffer.resize(DOSSIERS.size() * 12)
	for index: int in DOSSIERS.size():
		var at := point(index)
		if not at.is_finite():
			continue
		var shown := not interior._dossier_found.has(index) \
				and (not window or TowerInterior._floor_visible(
						int(DOSSIERS[index]["floor"]), interior._drawn_floor))
		# The 3 x 4 rows a TRANSFORM_3D multimesh stores: the basis, scaled to
		# nothing when this dossier is not being drawn, then the origin.
		var s := 1.0 if shown else 0.0
		var base := index * 12
		buffer[base + 0] = s
		buffer[base + 3] = at.x
		buffer[base + 5] = s
		buffer[base + 7] = at.y
		buffer[base + 10] = s
		buffer[base + 11] = at.z
	interior._dossier_rack.multimesh.buffer = buffer


static func latch(interior: TowerInterior) -> void:
	"""
	Hide the dossiers the ROOM has already banked — the coin's join replay, verbatim.

	Deferred out of `_ready()` because a dossier id is its world position and the
	shell is not on the tower site yet when `_ready()` runs (see `reset_guards`).
	Offline the group lookup finds nothing and this is six failed lookups, once.
	"""
	var mp := interior.get_tree().get_first_node_in_group("mp")
	if mp == null or not mp.has_method("is_coin_collected"):
		return
	var moved := false
	for index: int in DOSSIERS.size():
		if interior._dossier_found.has(index):
			continue
		if bool(mp.call("is_coin_collected", id_of(interior, index))):
			interior._dossier_found[index] = true
			moved = true
	# CHANGE-GATED, because `tick()` drives this twice a second: rebuilding
	# the rack's buffer when nothing was taken is work with no output, and the same
	# discipline `_bank_records`' two writers follow.
	if moved:
		refresh(interior)


static func tick(interior: TowerInterior, delta: float) -> void:
	"""
	Ask the room, twice a second, whether a TEAMMATE has taken a dossier.

	THE ONE THING THE COIN'S MACHINERY DOES NOT HAND US FOR FREE (codex review).
	`MpManager._absorb_collected` sweeps the "coin" and "chest" groups when a
	confirm lands, so a coin a teammate banks disappears on every screen at once. A
	dossier is in neither group and could not usefully be — it is one instance of a
	shared `MultiMesh` plus a trigger, not a node the sweep could free — so without
	this a peer already standing in the HQ keeps seeing a folder that pays nothing
	when they walk into it.

	A POLL RATHER THAN A THIRD LOOP IN THAT SWEEP, and that is this bead's contract
	rather than a judgement about which is nicer: the whole point of borrowing
	`Coin.id_at` and `claim_pickup` was that `mp_manager.gd` is not touched.
	`latch(interior)` is already exactly the right read, so this is that call on a
	clock — six dictionary lookups twice a second, only while somebody is standing
	in this building (`_process` returns above), and only while something is still
	unfound.

	ponytail: a `"dossier"` group in `_absorb_collected` is the cheaper answer and
	the upgrade path, for the day somebody is editing that file anyway.
	"""
	if interior._dossier_lore_queue.is_empty() \
			and interior._dossier_found.size() >= DOSSIERS.size():
		return
	interior._dossier_poll -= delta
	if interior._dossier_poll > 0.0:
		return
	interior._dossier_poll = DOSSIER_POLL
	# A refused lore line retries here, one per tick — the same clock paces two
	# dossiers grabbed back to back, so neither card stamps out the other.
	if not interior._dossier_lore_queue.is_empty():
		var toast := interior.get_tree().get_first_node_in_group("landmark_toast")
		if toast != null and toast.has_method("announce") \
				and bool(toast.call("announce", DOSSIER_TITLE, interior._dossier_lore_queue[0])):
			interior._dossier_lore_queue.pop_front()
	if interior._dossier_found.size() < DOSSIERS.size():
		latch(interior)


static func collect(interior: TowerInterior, index: int, body: Node) -> void:
	"""
	Take one dossier: claim it, pay it, say its line, and put it away.

	THE MULTIPLAYER PATH IS `coin.gd`'S, LINE FOR LINE, and that is the point. In a
	room the pickup is CLAIMED and the master's confirm is what pays (which is why
	nothing is awarded on that branch); offline — and in a room with no mesh to
	arbitrate over — `claim_pickup` answers false and the solo path runs, banking
	locally and reporting the id so a later joiner never sees the folder. No verb,
	no id scheme and no line of `mp_manager.gd` was added for any of it.

	The card is shown either way, including on a claim this peer went on to LOSE:
	you walked to it and read it, and a lore line is not a payout.
	"""
	if interior._dossier_found.has(index) or index < 0 or index >= DOSSIERS.size():
		return
	interior._dossier_found[index] = true
	var id := id_of(interior, index)
	var mp := interior.get_tree().get_first_node_in_group("mp")
	var claimed: bool = mp != null and mp.has_method("claim_pickup") \
			and bool(mp.call("claim_pickup", id, 1, DOSSIER_VALUE))
	if not claimed:
		if body != null and body.has_method("collect_coin"):
			body.call("collect_coin", DOSSIER_VALUE)
		if mp != null and mp.has_method("report_coin_collected"):
			mp.call("report_coin_collected", id)
	refresh(interior)
	interior._sfx("play_coin")
	announce_lore(interior, String(DOSSIERS[index]["lore"]))


static func announce_lore(interior: TowerInterior, lore: String) -> void:
	"""
	Put one dossier's line on the landmark card — the HUD that already paces these.

	NOT `_say()`. This building's `Label3D`s stand where they were built, and a line
	about storey 5 written onto the entry hall's label is a line nobody reads (the
	lift stop's own comment says so). The toast is a screen-space card that queues
	and fades, which is what an announcement wants; `announce()` is its one public
	seam and it refuses politely while a landmark question is on screen.

	Group-discovered and `has_method`-guarded like every other seam here, so an
	interior built standalone simply says nothing.

	A REFUSAL IS A QUEUE, NOT A DROP (codex post-merge review): `announce()` answers
	false while a landmark question owns the card, and the folder is already hidden
	by the time this runs — so the line waits in `interior._dossier_lore_queue` and
	`tick()` retries it. Only an explicit false queues; a missing toast is
	the standalone interior, which stays silent by design.
	"""
	var toast := interior.get_tree().get_first_node_in_group("landmark_toast")
	if toast != null and toast.has_method("announce"):
		if not bool(toast.call("announce", DOSSIER_TITLE, lore)):
			interior._dossier_lore_queue.append(lore)
