class_name TowerGraph
extends RefCounted
## THE TOWER AS A GRAPH — rooms, passages and what each passage asks of you.
##
## Epic godot-test1-3iy, phase 4. This file is DATA. It holds no logic, runs no
## world, and is read by exactly two things:
##
##   * `tower_interior.gd`, which takes the gate ids and the identity gate's hero
##     from here rather than restating them (so the building and the graph cannot
##     disagree about what a gate IS);
##   * `tower_selfcheck.gd`, which walks it headlessly and proves the campaign
##     cannot softlock (so the building and the graph cannot disagree about what a
##     gate DOES).
##
## ============================================================================
## THE RULE THIS GRAPH EXISTS TO MAKE CHECKABLE
## ============================================================================
##
## For EVERY non-empty subset of free heroes, from EVERY legal HQ entry, and in
## every persistent tower state reachable at that point, at least one route to a
## CELL must be traversable using only the free heroes' guaranteed capabilities and
## no item held by a captive.
##
## Four heroes means fifteen subsets, several entries and a growing pile of
## permanent world-state changes. Nobody can eyeball that, and the failure mode is
## the worst one a campaign has: a save that is still playable, still fun, and can
## never be finished. So it is a headless check, and the check is only as good as
## this graph's honesty about the building.
##
## ============================================================================
## THE THREE DESIGN LAWS — why fifteen graph walks are enough
## ============================================================================
##
## The rule quantifies over every reachable tower state, which is a set that grows
## combinatorially with every gate. Three authored laws collapse it to the base
## graph, and `tower_selfcheck.gd` asserts each law STRUCTURALLY over this file
## rather than trusting it:
##
## 1. SPINES AT FLOOR RANK. Four per-hero rescue spines with shared neutral
##    segments (`spines` below). Each is passable by its own hero ALONE, using base
##    capability plus whatever ranks `readiness_floor` guarantees. Any larger free
##    set contains a singleton, so its reachability is a superset of that
##    singleton's — the four spines imply all fifteen subsets by monotonicity. The
##    check enumerates all fifteen anyway, because fifteen walks of a fourteen-room
##    graph cost nothing and survive somebody rewriting this paragraph.
##
## 2. NO ITEM CUSTODY. Keys and quest items are PARTY-LEVEL world state — they join
##    the same monotone opened set that gates do (`tower_shell.opened`), and are
##    never a hero's inventory. That is what lets the check skip a custody model
##    entirely: nothing can be locked in a captive's pocket. `items` below records
##    the scope of every one, and the check refuses any row that names a carrier.
##    **If per-hero carry is ever authored, this check must grow a custody model
##    the same day** — the whole collapse above depends on it.
##
## 3. EDGE-ADDITIVE MUTATIONS. A permanent route transformation may only OPEN
##    passages, never close or consume one (`mutations` below carry `adds` and the
##    check forbids any removal key). Reachability is then monotone in tower state,
##    so the BASE graph — nothing yet opened — is the worst case, and "every
##    reachable state" collapses to one walk per story-flag state.
##
##    ONE SANCTIONED EXCEPTION, owner-ruled: the full-custody protocol SCAR may
##    close passages. Scar states are authored, enumerated and few (`scars` below),
##    the whole property re-runs inside each one, and a scar that would sever the
##    last singleton spine fails THE BUILD, not the player.
##
## ============================================================================
## WHAT IS BUILT AND WHAT IS AUTHORED
## ============================================================================
##
## `built: true` means the geometry exists TODAY in `tower_interior.gd`, and the
## self-check binds it to that file's own boxes — by the colours of the legibility
## language, so a new gate cannot appear in the building without appearing here.
##
## `built: false` is a CONTRACT for a later phase, not a wish. The check asserts an
## unbuilt row claims no geometry — a graph that quietly credits itself with rooms
## nobody built would certify a softlock as safe, which is worse than having no
## graph at all — and, in the other direction, that a BUILT row's `parts` are boxes
## the interior really has and that no gate-coloured box is left unclaimed.
##
## The cell block, its four hero segments and the maintenance crawl were authored
## here as contracts by phase 4 and BUILT BY PHASE 8 against them: the geometry was
## written to satisfy this file rather than the other way round, which is the whole
## reason the audit had to land first. What is still `false` is phase 7's lift —
## the `lift_shaft` edge and the `lift_stop_upper` entry it grants. The audit
## already walks FROM that entry (see `_all_entries`), so building the lift adds a
## route and can only make the property easier to satisfy.
##
## ============================================================================
## THE SHAPE — one const dict of plain dicts (`SPECIES` / `SKILL_TREES` idiom)
## ============================================================================
##
## No class hierarchy, no custom `Resource`, no logic inside the dict. Everything
## below is a literal a human can read top to bottom and a walker can index. The
## few functions at the end are pure lookups over it and nothing else.

# ============================================================================
# GATE IDS — the strings that go in the tower's monotone opened set
# ============================================================================
#
# Stable, lowercase, and PERSISTED VERBATIM by phase 5, so renaming one is a save
# migration. Add, never rename. `tower_interior.gd` takes its own `GATE_*`
# constants from these three, which is what stops the building and the graph from
# drifting apart on the only strings both of them touch.
#
# EVERY KEY IN `gates` BELOW IS ALSO ONE OF THESE STRINGS. The three constants are
# named here because they predate the graph and the building spells them out; the
# phase-8 doors are opened by a loop over `TowerInterior.SPINE_DOORS`, which reads
# the key straight out of this file. So the dictionary key IS the persisted id, and
# renaming a gate row is a save migration exactly as renaming a constant is. (The
# three below carry a `tower_` prefix and the phase-8 keys do not — a cosmetic
# split, kept because these three are already on disk in players' profiles.)

const GATE_DEMAND: String = "tower_vault"
const GATE_IDENTITY: String = "tower_secure_door"
const GATE_CHECKPOINT: String = "tower_checkpoint"

# ============================================================================
# SCAR IDS — the same strings, in the same persisted set
# ============================================================================
#
# A scar rides the tower's monotone opened set exactly as a gate does (phase 11):
# it is EARNED, it is PERMANENT and there is no verb that heals it, which is the
# whole of what that set demands. What makes a scar different is only what the
# building does with the id — a gate opens a way, a scar closes one — and that
# asymmetry is design law 3's one sanctioned exception, audited in `scars` below.
#
# PERSISTED VERBATIM, so the same rule holds: add, never rename.

## The unscarred tower. Not a stored id — nothing writes it — but the first row of
## `scars`, so the audit always walks the clean building first.
const SCAR_NONE: String = "none"

## The full-custody protocol's scar: the courtyard stair comes down.
const SCAR_CUSTODY: String = "custody_stair_collapse"

## The four playable heroes, in `PlayerController.CHARACTERS` order. Restated here
## rather than imported because this file must stay pure data with no dependency on
## a scene-bearing script; `tower_selfcheck.gd` asserts the two lists are equal.
const HEROES: Array[String] = ["windman", "primm", "teibi", "phoboman"]

## Gate classes, and what each one asks of the party. These are the three verbs of
## the epic's legibility language (see `tower_interior.gd`'s header) and the check
## has exactly one traversability rule per class:
##
##   "challenge" — a hazard beaten with the BASE KIT. Passable by any hero, always.
##                 A challenge that needs a rank is a demand gate wearing the wrong
##                 colour, and the legibility law forbids it.
##   "identity"  — passable only while its named hero is FREE. Can never be
##                 out-levelled, and is therefore the one thing that can strand a
##                 subset. Every one is a suspect in the softlock audit.
##   "demand"    — passable when some free hero's reading of `effect` reaches
##                 `scale`. A hero-specific effect (`primm_blink` is one) makes the
##                 gate require THAT hero, exactly like an identity gate, and the
##                 check treats it that way.
##   "riddle"    — passable by any free set THAT CAN REACH `clue_room`. Knowledge is
##                 PARTY-LEVEL, exactly like an item (design law 2): once the clue
##                 has been seen it is known, and the gate joins the monotone opened
##                 set on the solve (law 3). So a riddle asks nothing of WHO you
##                 are — it asks where you have been — and the audit refuses a
##                 riddle row that names a hero.
const CLASS_CHALLENGE: String = "challenge"
const CLASS_IDENTITY: String = "identity"
const CLASS_DEMAND: String = "demand"
const CLASS_RIDDLE: String = "riddle"

## Which ability constant a demand gate's `effect` scales. One entry per effect any
## demand gate uses — the check asserts each is a real `SKILL_TREES` effect id AND
## that the base value matches the live constant it names, so retuning the ability
## breaks the build instead of silently moving the gate.
const EFFECT_BASE: Dictionary = {
	"primm_blink": {"base": 6.0, "source": "PlayerController.PRIMM_BLINK_DISTANCE"},
}

const TOWER_GRAPH: Dictionary = {

	# ------------------------------------------------------------------------
	# ROOMS. `quest` names the quest completed here (""), `cell` names the hero
	# whose cell this is (""). `parts` are the `TowerInterior.boxes()` entries that
	# ARE this room's marker — only the checkpoint has one today.
	# ------------------------------------------------------------------------
	"rooms": {
		# --- built, phase 3 ---
		"entry_hall": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "Under the slab, behind the shell doorway. Every route starts here.",
		},
		"vault": {
			"built": true, "quest": "vault_gem", "cell": "", "parts": [],
			"note": "Behind the demand gate, off the hall's south end. Optional by design.",
		},
		"courtyard": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "Open to the sky, west of the rotor doorway. The ramp starts here.",
		},
		"upper_landing": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "Top of the ramp, west of the secure door.",
		},
		"checkpoint_room": {
			"built": true, "quest": "checkpoint", "cell": "",
			"parts": ["CheckpointPlate", "CheckpointPost"],
			"note": "East of the identity gate. The run's respawn anchor.",
		},
		# --- built, phase 8: the cell block wing, north of the entry hall ---
		"service_stair": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "The shared neutral segment all four spines pass through. A corridor "
				+ "with the courtyard at one end, the crawl at the other, and the four "
				+ "hero doors along its north side.",
		},
		"cell_gallery": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "The junction the four cells open off. Reaching it IS the rescue.",
		},
		# UNIFORM BY CONSTRUCTION (owner-ruled): any hero can land in any cell, so a
		# cell's only geometry is its recess and its containment frame. `parts` claims
		# that frame — the box the interior paints in the cell marker colour — which is
		# what stops a fifth cell appearing in the building and not here.
		"cell_windman": {"built": true, "quest": "", "cell": "windman",
			"parts": ["CellFrameWindman"]},
		# ...plus the ONE piece of authored staging in the building: the steel
		# containment unit that smothers Primm's field. Set dressing inside a STANDARD
		# cell, present for the first rescue and gone for good after it — which is what
		# "no distinguished hand-built Primm cell" means in geometry.
		"cell_primm": {"built": true, "quest": "", "cell": "primm",
			"parts": ["CellFramePrimm", "PrimmContainment"]},
		"cell_teibi": {"built": true, "quest": "", "cell": "teibi",
			"parts": ["CellFrameTeibi"]},
		"cell_phoboman": {"built": true, "quest": "", "cell": "phoboman",
			"parts": ["CellFramePhoboman"]},

		# --- built, phase 14: the annulus and the three hand-planned storeys ---
		# The annulus was never a room here: the front door's entry row lands
		# straight in `entry_hall`, which is strictly harsher than the truth and so
		# changed no verdict. Storey 3's grand ramp starts out here, so the space
		# now needs a name the graph can walk through.
		"outer_hall": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "The 80 m entrance hall the phase-13 envelope opened up. The keep "
				+ "stands in the middle of it and the grand ramp climbs from its floor.",
		},
		# The storeys above are HAND-PLANNED AS TEXT — see `tower_plans.gd`. Every
		# room a plan letters needs a row here, and `tower_selfcheck` binds the two
		# in both directions: a letter with no row, or a row no floor draws, fails.
		"s3_landing": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "Head of the grand ramp on storey 3, where the ring corridor "
				+ "and both cross corridors meet. Every room on the floor hangs "
				+ "off it.",
		},
		"s3_records_west": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "Records, west stack. Long room off the north cross corridor.",
		},
		"s3_records_east": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "Records, east stack. Its twin across the partition.",
		},
		"s3_permits_west": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "Permits, west stack — the paperwork a gastro licence needs.",
		},
		"s3_permits_east": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "Permits, east stack. Carries one of the floor's two pads.",
		},
		"s3_archive_west": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "Archive, west stack, off the south cross corridor.",
		},
		"s3_archive_east": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "Archive, east stack.",
		},
		"s3_evidence_west": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "Evidence store, west stack — what the corporation keeps on people.",
		},
		"s3_evidence_east": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "Evidence store, east stack. Carries the floor's second pad.",
		},
		"s4_landing": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "Head of the storey-4 ramp, in the north ring corridor directly "
				+ "over storey 3's own stairwell.",
		},
		"s4_accounts_a": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "Accounts, first of three offices in the north-west block.",
		},
		"s4_accounts_b": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "Accounts, second office. Carries one of the floor's two pads.",
		},
		"s4_accounts_c": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "Accounts, third and widest office of the block.",
		},
		"s4_payroll_a": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "Payroll, first office of the north-east block.",
		},
		"s4_payroll_b": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "Payroll, second office.",
		},
		"s4_payroll_c": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "Payroll, third office.",
		},
		"s4_supply_a": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "Supply, first office of the south-west block.",
		},
		"s4_supply_b": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "Supply, second office.",
		},
		"s4_supply_c": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "Supply, third office.",
		},
		"s4_dispatch_a": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "Dispatch, first office of the south-east block.",
		},
		"s4_dispatch_b": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "Dispatch, second office.",
		},
		"s4_dispatch_c": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "Dispatch, third office. Carries the floor's second pad.",
		},
		# THE POCKET AT THE HEAD OF THE STOREY-5 RAMP, and it is a room of its own
		# for one reason: phase 15's riddle stands across its far end. The ramp is
		# ungated (you may always climb it), the FLOOR beyond is what the sequence
		# lock opens — so the passage the gate sits on needs two ends, and the near
		# one is this. Walled north and south, the ramp behind, the mass in front:
		# there is no way onto the floor round it, which is what makes the gate the
		# audit walks the gate the player meets.
		"s5_stairhead": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "The landing at the head of the storey-5 ramp, with the sequence "
				+ "lock's four pads on it and the riddle's mass across its east end.",
		},
		"s5_landing": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "Storey 5's ring and cross corridors, behind the riddle gate. "
				+ "The top of the building until phase 16 opens storeys 6-10.",
		},
		"s5_boardroom": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "The boardroom. Deep suite on the north-west, opening onto the "
				+ "west ring corridor. Carries one of the floor's two pads.",
		},
		"s5_secretariat": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "The secretariat, south of the boardroom and sharing its wall.",
		},
		"s5_directors_north": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "Directors' suite, north half of the east side.",
		},
		"s5_directors_south": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "Directors' suite, south half.",
		},
		"s5_legal": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "Legal, on the south-west, off the west ring corridor.",
		},
		"s5_audit": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "Audit, the south-west corner suite. Carries the floor's second pad.",
		},
		"s5_lounge": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "The executive lounge, south-east.",
		},
		"s5_press_room": {
			"built": true, "quest": "", "cell": "", "parts": [],
			"note": "The press room, the south-east corner suite.",
		},
	},

	# ------------------------------------------------------------------------
	# EDGES. Undirected passages: `{id, a, b, gate}`, gate "" for an open way
	# through. An edge id in some mutation's `adds` is NOT part of the base graph —
	# see `mutations`.
	# ------------------------------------------------------------------------
	"edges": [
		{"id": "hall_courtyard", "a": "entry_hall", "b": "courtyard",
			"gate": "rotor_gate", "built": true},
		{"id": "hall_vault", "a": "entry_hall", "b": "vault",
			"gate": GATE_DEMAND, "built": true},
		# The ramp. Not a gate: it is the only way up and it asks nothing.
		{"id": "courtyard_landing", "a": "courtyard", "b": "upper_landing",
			"gate": "", "built": true},
		{"id": "landing_checkpoint", "a": "upper_landing", "b": "checkpoint_room",
			"gate": GATE_IDENTITY, "built": true},

		# --- phase 8: the neutral approach, two ways round ---
		{"id": "courtyard_stair", "a": "courtyard", "b": "service_stair",
			"gate": "", "built": true},
		# THE REDUNDANT WAY IN, and it is not decoration: it is what lets the
		# authored scar close the courtyard stair without stranding anybody.
		{"id": "hall_stair", "a": "entry_hall", "b": "service_stair",
			"gate": "maintenance_crawl", "built": true},

		# --- phase 8: where the four spines diverge, one segment per hero ---
		{"id": "stair_gallery_windman", "a": "service_stair", "b": "cell_gallery",
			"gate": "updraft_shaft", "built": true},
		{"id": "stair_gallery_primm", "a": "service_stair", "b": "cell_gallery",
			"gate": "phase_grate", "built": true},
		{"id": "stair_gallery_teibi", "a": "service_stair", "b": "cell_gallery",
			"gate": "collapsed_slab", "built": true},
		{"id": "stair_gallery_phoboman", "a": "service_stair", "b": "cell_gallery",
			"gate": "hound_den", "built": true},

		# --- phase 8: the cells themselves. UNIFORM and ungated: whoever reaches
		# the gallery can open any door, which is what "uniform cells" means. ---
		{"id": "gallery_cell_windman", "a": "cell_gallery", "b": "cell_windman",
			"gate": "", "built": true},
		{"id": "gallery_cell_primm", "a": "cell_gallery", "b": "cell_primm",
			"gate": "", "built": true},
		{"id": "gallery_cell_teibi", "a": "cell_gallery", "b": "cell_teibi",
			"gate": "", "built": true},
		{"id": "gallery_cell_phoboman", "a": "cell_gallery", "b": "cell_phoboman",
			"gate": "", "built": true},

		# --- phase 14: out into the annulus and up the three storeys. Every one
		# of these is UNGATED: the new floors are optional space, the four rescue
		# spines still run through the phase-8 wing, and every subset's verdict is
		# unchanged. Phase 15 is what starts hanging riddles up here. ---
		# ponytail: UNGATED is the deferral, and its ceiling is that these 30-odd
		# rows grow the 15-subset audit's SIZE without adding a route obligation —
		# the walk gets longer, its verdict cannot change. Phase 15 hanging one
		# riddle up here is what makes the audit start earning its keep again.
		{"id": "hall_outer", "a": "entry_hall", "b": "outer_hall",
			"gate": "", "built": true},
		{"id": "outer_s3", "a": "outer_hall", "b": "s3_landing",
			"gate": "", "built": true},
		{"id": "s3_landing_records_west", "a": "s3_landing", "b": "s3_records_west",
			"gate": "", "built": true},
		{"id": "s3_landing_records_east", "a": "s3_landing", "b": "s3_records_east",
			"gate": "", "built": true},
		# ...one of which phase 15 sealed: the west permits stack is the strongroom,
		# and its doorway is the optional riddle. Optional exactly like the vault —
		# no cell lies behind it, so no subset can be stranded by it.
		{"id": "s3_landing_permits_west", "a": "s3_landing", "b": "s3_permits_west",
			"gate": "riddle_strongroom", "built": true},
		{"id": "s3_landing_permits_east", "a": "s3_landing", "b": "s3_permits_east",
			"gate": "", "built": true},
		{"id": "s3_landing_archive_west", "a": "s3_landing", "b": "s3_archive_west",
			"gate": "", "built": true},
		{"id": "s3_landing_archive_east", "a": "s3_landing", "b": "s3_archive_east",
			"gate": "", "built": true},
		{"id": "s3_landing_evidence_west", "a": "s3_landing", "b": "s3_evidence_west",
			"gate": "", "built": true},
		{"id": "s3_landing_evidence_east", "a": "s3_landing", "b": "s3_evidence_east",
			"gate": "", "built": true},
		# ...and up again, one ramp per storey. Both feet stand in the corridor
		# of the floor below — asserted cell by cell against that floor's own grid.
		{"id": "s3_s4", "a": "s3_landing", "b": "s4_landing",
			"gate": "", "built": true},
		{"id": "s4_landing_accounts_a", "a": "s4_landing", "b": "s4_accounts_a",
			"gate": "", "built": true},
		{"id": "s4_landing_accounts_b", "a": "s4_landing", "b": "s4_accounts_b",
			"gate": "", "built": true},
		{"id": "s4_landing_accounts_c", "a": "s4_landing", "b": "s4_accounts_c",
			"gate": "", "built": true},
		{"id": "s4_landing_payroll_a", "a": "s4_landing", "b": "s4_payroll_a",
			"gate": "", "built": true},
		{"id": "s4_landing_payroll_b", "a": "s4_landing", "b": "s4_payroll_b",
			"gate": "", "built": true},
		{"id": "s4_landing_payroll_c", "a": "s4_landing", "b": "s4_payroll_c",
			"gate": "", "built": true},
		{"id": "s4_landing_supply_a", "a": "s4_landing", "b": "s4_supply_a",
			"gate": "", "built": true},
		{"id": "s4_landing_supply_b", "a": "s4_landing", "b": "s4_supply_b",
			"gate": "", "built": true},
		{"id": "s4_landing_supply_c", "a": "s4_landing", "b": "s4_supply_c",
			"gate": "", "built": true},
		{"id": "s4_landing_dispatch_a", "a": "s4_landing", "b": "s4_dispatch_a",
			"gate": "", "built": true},
		{"id": "s4_landing_dispatch_b", "a": "s4_landing", "b": "s4_dispatch_b",
			"gate": "", "built": true},
		{"id": "s4_landing_dispatch_c", "a": "s4_landing", "b": "s4_dispatch_c",
			"gate": "", "built": true},
		# THE STAIR 4 -> 5, IN TWO HALVES. Climbing it asks nothing; the storey at
		# the top is what the riddle holds shut. Splitting the passage rather than
		# gating the ramp itself is what makes the gate honest: a ramp is a deck you
		# can step onto from the rooms beside it, and a lock the player can jump
		# over is a lock the audit is lying about.
		{"id": "s4_s5", "a": "s4_landing", "b": "s5_stairhead",
			"gate": "", "built": true},
		{"id": "s5_stairhead_landing", "a": "s5_stairhead", "b": "s5_landing",
			"gate": "riddle_stair", "built": true},
		{"id": "s5_landing_boardroom", "a": "s5_landing", "b": "s5_boardroom",
			"gate": "", "built": true},
		{"id": "s5_landing_secretariat", "a": "s5_landing", "b": "s5_secretariat",
			"gate": "", "built": true},
		{"id": "s5_landing_directors_north", "a": "s5_landing", "b": "s5_directors_north",
			"gate": "", "built": true},
		{"id": "s5_landing_directors_south", "a": "s5_landing", "b": "s5_directors_south",
			"gate": "", "built": true},
		{"id": "s5_landing_legal", "a": "s5_landing", "b": "s5_legal",
			"gate": "", "built": true},
		{"id": "s5_landing_audit", "a": "s5_landing", "b": "s5_audit",
			"gate": "", "built": true},
		{"id": "s5_landing_lounge", "a": "s5_landing", "b": "s5_lounge",
			"gate": "", "built": true},
		{"id": "s5_landing_press_room", "a": "s5_landing", "b": "s5_press_room",
			"gate": "", "built": true},

		# --- phase 7: the lift shaft. Exists only once `lift_activated` fires. ---
		{"id": "lift_shaft", "a": "entry_hall", "b": "upper_landing",
			"gate": "", "built": false},
	],

	# ------------------------------------------------------------------------
	# GATES. `needed_during_captivity` is a CLAIM the check verifies rather than
	# trusts: it recomputes, for every story/scar/entry/subset case, whether the
	# gate lies on EVERY route to a cell, and fails on any disagreement. So the
	# flag is documentation that cannot rot.
	#
	# `parts` are the `TowerInterior.boxes()` names that build this gate. Every box
	# the interior paints in a gate colour must be claimed by exactly one of these
	# lists, which is how a gate added to the building but not to the graph is
	# caught. An unbuilt gate claims nothing.
	# ------------------------------------------------------------------------
	"gates": {
		"rotor_gate": {
			"class": CLASS_CHALLENGE, "identity": "", "effect": "", "scale": 0.0,
			# TRUE, and not for the obvious reason: from the lift stop, with the
			# custody scar having dropped the courtyard stair, this doorway is the
			# only way back down to the maintenance crawl. The audit computes that
			# — this flag is its answer written down, and it is checked, not
			# trusted.
			"needed_during_captivity": true, "built": true, "quest": "",
			"parts": ["RotorPost", "RotorBarLow", "RotorBarHigh"],
			"note": "Two counter-rotating bars. Base kit, so no subset can be stopped by it.",
		},
		GATE_DEMAND: {
			"class": CLASS_DEMAND, "identity": "", "effect": "primm_blink",
			# Kept equal to `TowerInterior.DEMAND_TARGET` by the self-check — the
			# reasoning for the number lives at that constant, not here.
			"scale": 7.2,
			"needed_during_captivity": false, "built": true, "quest": "vault_gem",
			"parts": ["DemandShutter", "Receptacle"],
			"note": "Optional vault. One rank of Long Step — forecastable, never on a rescue route.",
		},
		GATE_IDENTITY: {
			"class": CLASS_IDENTITY, "identity": "teibi", "effect": "", "scale": 0.0,
			"needed_during_captivity": false, "built": true, "quest": "checkpoint",
			"parts": ["IdentityMass", "IdentityPad"],
			"note": "The mass only Teibi lifts. Behind it is a checkpoint, never a cell.",
		},

		# --- phase 8 ---
		"maintenance_crawl": {
			"class": CLASS_CHALLENGE, "identity": "", "effect": "", "scale": 0.0,
			"needed_during_captivity": true, "built": true, "quest": "",
			"parts": ["CrawlPress"],
			"note": "A duct out of the hall with a stamping press across it — base kit, "
				+ "so no subset can be stopped by it. It is the scar's survival route, "
				+ "which is why it may never ask for a hero or a rank.",
		},
		"updraft_shaft": {
			"class": CLASS_IDENTITY, "identity": "windman", "effect": "", "scale": 0.0,
			"needed_during_captivity": true, "built": true, "quest": "",
			"parts": ["UpdraftMass", "UpdraftPad"],
			"note": "A shaft with no floor. Air Rush, base kit — no rank in the budget.",
		},
		"phase_grate": {
			"class": CLASS_IDENTITY, "identity": "primm", "effect": "", "scale": 0.0,
			"needed_during_captivity": true, "built": true, "quest": "",
			"parts": ["GrateMass", "GratePad"],
			"note": "A grate with a body-width of wall behind it. Base Phase Step reaches it.",
		},
		"collapsed_slab": {
			"class": CLASS_IDENTITY, "identity": "teibi", "effect": "", "scale": 0.0,
			"needed_during_captivity": true, "built": true, "quest": "",
			"parts": ["SlabMass", "SlabPad"],
			"note": "Dead weight across the way. Giant Teibi shifts it.",
		},
		"hound_den": {
			"class": CLASS_IDENTITY, "identity": "phoboman", "effect": "", "scale": 0.0,
			"needed_during_captivity": true, "built": true, "quest": "",
			"parts": ["DenMass", "DenPad"],
			"note": "A kennelled run. Stink Wave empties it.",
		},

		# --- phase 15: the riddles ------------------------------------------
		#
		# TWO EXTRA KEYS, AND ONLY A RIDDLE MAY CARRY THEM (check 2 refuses either
		# on any other class):
		#
		#   clue_room  the room whose wall carries the answer. THE WHOLE
		#              TRAVERSABILITY RULE: the gate is passable by any free set
		#              that can reach this room, at any rank, with no ability — so a
		#              riddle can never strand a subset the way an identity gate can,
		#              and the audit's job is to prove the clue is not shut behind
		#              the riddle it explains.
		#   answer     the pad sequence, as the digits drawn on the plan. A
		#              PERMUTATION of the storey's four lock pads, so every pad is
		#              pressed exactly once and the mass's four-notch rise is a
		#              faithful count of how far in you are.
		#
		# `identity` stays "" and the audit refuses it otherwise: a riddle is a
		# base-kit knowledge gate, and one that asked for a hero would be an
		# identity gate wearing the wrong colour — the same law the legibility
		# language puts on a challenge.
		"riddle_stair": {
			"class": CLASS_RIDDLE, "identity": "", "effect": "", "scale": 0.0,
			"clue_room": "s3_records_east", "answer": [3, 1, 4, 2],
			"needed_during_captivity": false, "built": true, "quest": "",
			"parts": ["S4PlanRiddleMass_riddle_stair"],
			"note": "The sequence lock at the head of the storey-5 ramp. Its four "
				+ "colours are painted on the east records stack's floor, three "
				+ "storeys of walking away and free to anybody who goes.",
		},
		"riddle_strongroom": {
			"class": CLASS_RIDDLE, "identity": "", "effect": "", "scale": 0.0,
			"clue_room": "s3_archive_west", "answer": [2, 4, 1, 3],
			"needed_during_captivity": false, "built": true, "quest": "",
			"parts": ["S2PlanRiddleMass_riddle_strongroom"],
			"note": "The west permits stack, sealed. Optional side room in the "
				+ "vault's mould; its clue is one floor away in the west archive.",
		},
	},

	# ------------------------------------------------------------------------
	# ENTRIES. Every LEGAL way into the tower. The rule quantifies over all of
	# them, so a new entry is a new fifteen-subset audit, automatically.
	# ------------------------------------------------------------------------
	"entries": [
		{"id": "front_door", "room": "entry_hall", "built": true,
			"note": "The shell doorway. Always open, always legal."},
		{"id": "lift_stop_upper", "room": "upper_landing", "built": false,
			"note": "Phase 7's unlockable lift stop, granted by `lift_activated`."},
	],

	# ------------------------------------------------------------------------
	# MUTATIONS — permanent route transformations. ADDITIVE ONLY (design law 3):
	# a row may add edges and entries and NOTHING ELSE. The self-check whitelists
	# these keys, so a row that grew a `removes` fails the build.
	#
	# The audit deliberately walks the BASE graph (no mutation fired) while still
	# starting from every entry any mutation can grant. That is strictly harsher
	# than reality — you cannot reach the lift stop without the lift edge — and
	# harsher is the only direction a softlock audit may err in.
	# ------------------------------------------------------------------------
	"mutations": [
		{
			"id": "lift_activated",
			"trigger": "checkpoint",
			"adds": ["lift_shaft"],
			"adds_entries": ["lift_stop_upper"],
			"note": "Lighting the checkpoint powers the lift. Opens a shaft, closes nothing.",
		},
	],

	# ------------------------------------------------------------------------
	# SCARS — the ONE sanctioned exception to law 3 (owner-ruled), phase 11's
	# full-custody protocol. A scar may CLOSE passages. Enumerated and few, and the
	# whole property re-runs inside each one; a scar that severs the last singleton
	# spine fails the build, not the player.
	# ------------------------------------------------------------------------
	"scars": [
		{
			"id": SCAR_NONE, "removes": [],
			"note": "The unscarred tower. Always audited first.",
		},
		{
			"id": SCAR_CUSTODY, "removes": ["courtyard_stair"],
			"note": "The protocol drops the courtyard stair. `hall_stair` is why "
				+ "that is survivable — and why it exists.",
		},
	],

	# ------------------------------------------------------------------------
	# STORY STATES — the flag overlays the property is re-run under. `captivity`
	# is what matters: before the beat nobody is captive and the cell clause is
	# void; after it, the full fifteen-subset audit has teeth. Overlays are
	# additive for the same reason mutations are, and checked the same way.
	# ------------------------------------------------------------------------
	"story_states": [
		{"id": "pre_beat", "captivity": false, "adds": [],
			"note": "Systemic capture not yet armed. Quest reachability still holds."},
		{"id": "post_beat", "captivity": true, "adds": [],
			"note": "Capture armed. Every subset must still reach a cell."},
	],

	# ------------------------------------------------------------------------
	# SPINES — the four base-kit rescue routes, as ordered edge ids from an entry
	# to the cell gallery. The first two segments are SHARED and neutral; only the
	# last is the hero's own. Each must be passable by its hero ALONE at the
	# readiness floor, which check 3 walks edge by edge.
	# ------------------------------------------------------------------------
	"spines": {
		"windman": {"entry": "front_door",
			"edges": ["hall_courtyard", "courtyard_stair", "stair_gallery_windman"]},
		"primm": {"entry": "front_door",
			"edges": ["hall_courtyard", "courtyard_stair", "stair_gallery_primm"]},
		"teibi": {"entry": "front_door",
			"edges": ["hall_courtyard", "courtyard_stair", "stair_gallery_teibi"]},
		"phoboman": {"entry": "front_door",
			"edges": ["hall_courtyard", "courtyard_stair", "stair_gallery_phoboman"]},
	},

	# ------------------------------------------------------------------------
	# THE READINESS FLOOR — `{hero: {skill_id: rank}}`, the ranks the authored beat
	# GUARANTEES a hero has before systemic capture arms. Capture arms only after
	# the beat, so the beat's floor IS the spine rank budget and the check reads
	# one from the other rather than restating a number.
	#
	# IT IS EMPTY TODAY, AND EMPTY IS THE STRICTEST CASE: every spine is passable
	# on base capability alone, so no beat has to promise anything and no save can
	# arrive under-ranked. Author a rank here only when the beat truly grants it —
	# every entry weakens the guarantee by exactly that much.
	# ------------------------------------------------------------------------
	"readiness_floor": {
		"windman": {}, "primm": {}, "teibi": {}, "phoboman": {},
	},

	# ------------------------------------------------------------------------
	# ITEMS — design law 2. `scope` must be "party" for every one: an item is world
	# state joining the tower's monotone opened set, never a hero's inventory. The
	# check rejects any row naming a carrier, because a key in a captive's pocket
	# is precisely the softlock this graph cannot model.
	# ------------------------------------------------------------------------
	"items": [
		{"id": "vault_gem", "scope": "party", "room": "vault",
			"note": "The existing collectible. Score is party-level; nobody carries it."},
	],

	# ------------------------------------------------------------------------
	# QUESTS — an OPEN SET. Each is solo-completable at some capability level and
	# none requires another (`requires_quest` must be "" for every row): a quest
	# chain is a second way to strand a player, one the subset audit cannot see.
	# ------------------------------------------------------------------------
	"quests": [
		{"id": "vault_gem", "room": "vault", "requires_quest": "",
			"note": "Solo for Primm at one rank of Long Step."},
		{"id": "checkpoint", "room": "checkpoint_room", "requires_quest": "",
			"note": "Solo for Teibi on base capability."},
	],
}


static func gate(id: String) -> Dictionary:
	"""The gate row for `id`, or an empty dict when there is no such gate."""
	return TOWER_GRAPH["gates"].get(id, {})


static func identity_of(id: String) -> String:
	"""
	Which hero an identity gate asks for, "" when it asks for nobody.

	`tower_interior.gd` reads its identity gate's hero through here, so the name
	"teibi" is written once in this repository and the building cannot ask for a
	hero the audit thinks it does not.
	"""
	return String(gate(id).get("identity", ""))


static func room(id: String) -> Dictionary:
	"""The room row for `id`, or an empty dict."""
	return TOWER_GRAPH["rooms"].get(id, {})


static func cells() -> Array[String]:
	"""Every cell room id, in `rooms` order."""
	var out: Array[String] = []
	for id: String in TOWER_GRAPH["rooms"]:
		if String(TOWER_GRAPH["rooms"][id].get("cell", "")) != "":
			out.append(id)
	return out


static func scar_ids() -> Array[String]:
	"""
	Every AUTHORED scar id, in `scars` order, minus the unscarred row.

	@return: A fresh Array of String — the caller may keep or mutate it.

	The enumeration design law 3's exception rests on. Anything that applies a scar
	picks from this list and never invents an id, which is what "authored and
	enumerated, not computed" means in code.
	"""
	var out: Array[String] = []
	for scar: Dictionary in TOWER_GRAPH["scars"]:
		var id := String(scar.get("id", ""))
		if id != SCAR_NONE and id != "":
			out.append(id)
	return out


static func next_scar(applied: Array) -> String:
	"""
	The first authored scar this world has not taken yet, "" when it has taken all.

	@param applied: the tower's opened set (or any array of ids already applied).
	@return: one id out of `scar_ids()`, or "" — never a computed string.

	PURE, and it takes the applied set as an argument rather than reading a store:
	this file is data with no dependency on anything that saves. The protocol's
	"exactly one enumerated scar" is this call plus the write, and a second
	full-custody outcome in a world that has already collapsed its stair takes no
	new scar rather than inventing one — the list is the budget.
	"""
	for id: String in scar_ids():
		if not applied.has(id):
			return id
	return ""
