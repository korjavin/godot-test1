extends SceneTree
## ============================================================================
## LANDMARK PROGRESS SELF-CHECK — run headless, prints "SELFCHECK OK", exits 0
## ============================================================================
##
##     godot --headless --path . --import      # once, so class_name types resolve
##     godot --headless --path . --script res://scripts/landmark_progress_selfcheck.gd
##
## Guards BUDAPEST'S WIN CONDITION (epic `godot-test1-8gw`, bead .5): the
## catalogue that turns 22 authored slots into named landmarks, the 22-bit
## explored mask that records walking into them, the eighteen-of-twenty-two
## threshold that ends the run in victory, and the two wire formats that carry
## the mask between peers.
##
## Six checks, and what each is not vacuous about:
##
##  1. **THE CATALOGUE.** Every `BudapestPlan.SLOTS` row either names a
##     `LandmarkBuilders.CITY_LANDMARKS` builder or is a wave-C reservation with
##     an empty one; a named row's radius agrees with the slot's; and — the
##     bead's own requirement — an EMPTY builder is handled gracefully rather
##     than looked up and found missing. This is what stops the catalogue and the
##     plan drifting while bead .8 fills the seven reservations in a different
##     file on a different branch.
##
##  2. **THE MASK, on a real `player.tscn`.** A bit is set once, an index out of
##     range sets nothing, a repeat is refused (so a re-visit pays nothing twice),
##     and `explored_count()` counts what is actually there. Driven on the shipped
##     node, not on a copy of the arithmetic.
##
##  3. **THE THRESHOLD.** Seventeen landmarks is not a win and the eighteenth is —
##     with the negative control, because "the run ended" is also satisfied by a
##     check that ends every run. Plus the outcome really being WON, since the
##     panel and the archive both branch on it.
##
##  4. **THE DECODE WITH THE FIELD ABSENT.** The `room` packet's `m` and the join
##     snapshot's `lm` are OPTIONAL, because a master on a pre-.5 build is a state
##     that really happens (`build_version` refuses to reload a peer that is in a
##     room). A missing field must read as ZERO and must NOT drop the packet — the
##     packet is also the captive set's repair channel, so dropping it would stop a
##     mixed room converging its CELLS over a field that master has never heard of.
##     Present-but-malformed still costs the whole packet. Both directions, both
##     packets, with the captive half asserted alongside so a "pass" cannot come
##     from a parser that dropped everything.
##
##  5. **THE CLAIM VERB.** `decode_lmk` over ints, floats (the relay hands every
##     number back as one), fractions, negatives, out-of-range indices and
##     non-numbers; and `landmark_claim_in_reach` from close, from far, from a
##     plateau lid 46 m up (the distance is flat XZ on purpose) and from a
##     non-finite point.
##
##  7. **THE ROOM'S TWO HYGIENE RULES** (both from codex review 2026-09-02). A
##     claim is made ONCE PER RUN — `explore_landmark()` will never report the same
##     slot again — so a claim the master discards (a joiner reaching a landmark
##     before its first presence packet) is a landmark permanently missing from the
##     room's win set: it must be REMEMBERED and re-sent until the master's own
##     published mask acknowledges it. And a peer that adopts a foreign world seed
##     must arrive with an EMPTY mask, or a finished solo run wins somebody else's
##     room on its first `room` packet.
##
##  6. **THE TRIGGER.** `landmark_toast._scan_city()` driven against the real
##     shipped widget with a player standing on a slot: the bit is claimed, the
##     approach latches so a second tick does not re-fire, and walking out past
##     `radius + LEAVE_PAD` re-arms it. This is the seam between "the plan says
##     there is a landmark here" and "the mask moved", and nothing else measures it.
##
## Deliberately NOT covered: the multiplayer TRANSPORT (mp_selfcheck owns the mesh
## and the relay; this file owns the parsers they carry), and whether the German
## rows read well — `locale_selfcheck` owns the CSV and cannot judge prose.

## ============================================================================
## LANDMINE — THE STORE IS REDIRECTED FIRST, BEFORE ANY PLAYER EXISTS
## ============================================================================
##
## `capture_selfcheck`'s rule, and this file learns it the expensive way: check 3
## really ends a run in VICTORY, and `_end_run(Outcome.WON)` calls
## `BestRunStore.archive_world()`. Against the real `user://best_run.cfg` that
## latches the profile as a finished world — and `player_controller._ready()`
## then calls `_reopen_archived_ending()` on EVERY player any LATER check builds,
## setting `is_game_over` before its first frame. `_physics_process` returns above
## everything at that point, so `wade_selfcheck` measures a body that cannot jump
## and `pause_selfcheck` presses P at a game-over screen: two unrelated checks
## turned red by this one's leftovers, in a suite that shares one `user://`.
##
## So the store is pointed at a directory private to THIS PROCESS, created empty,
## in the first statement of `_initialize()` — and NEVER the player's own save.
## `selfcheck_sentinel.gd` carries the whole reasoning.

const PLAYER_SCENE: String = "res://scenes/player.tscn"
const TOAST_SCRIPT: GDScript = preload("res://scripts/landmark_toast.gd")
## `player_controller.gd` and `mp_manager.gd` reached as SCRIPTS, not as
## `class_name` types: the player has no `class_name` at all, and the manager's is
## `MpManager` while every check in this project spells it `MPManager` through a
## preload — one alias here rather than two spellings across the file.
const PlayerScript: GDScript = preload("res://scripts/player_controller.gd")
const MPManager: GDScript = preload("res://scripts/mp_manager.gd")

var _failures: Array[String] = []


## THE END-OF-CHECK SENTINEL. A GDScript runtime error aborts the FUNCTION it
## lands in and lets the script carry on, so a check that dies halfway simply
## stops asserting and this file prints "SELFCHECK OK". Every check below stamps
## itself at its exit; the report site asks whether every stamp was reached.
## `scripts/selfcheck_sentinel.gd` carries the whole reasoning.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")


func _initialize() -> void:
	# FIRST, BEFORE ANY PLAYER EXISTS — see the LANDMINE banner. This check wins a
	# run for real, and a win archives the world; the store it archives into is the
	# empty one this process just made for itself, never anybody's real profile.
	Sentinel.isolate_user_state()
	# ONE FRAME FIRST: `_initialize()` runs before the main loop, and a node added
	# to `root` before that answers null to `get_tree()`. The same lesson
	# `pause_selfcheck` and `minimap_selfcheck` both record.
	await process_frame

	_check_catalogue()
	await _check_mask()
	await _check_threshold()
	_check_decode_absent()
	_check_claim_verb()
	await _check_trigger()
	await _check_room_hygiene()

	if _failures.is_empty():
		Sentinel.finish(self)
	else:
		for line: String in _failures:
			printerr("FAIL: " + line)
		printerr("SELFCHECK FAILED (%d)" % _failures.size())
		quit(1)


func _fail(message: String) -> void:
	_failures.append(message)


# ============================================================================
# 1. THE CATALOGUE — 22 slots, and a graceful empty builder
# ============================================================================

func _check_catalogue() -> void:
	var named: int = 0
	var reserved: int = 0
	for i in range(BudapestPlan.SLOTS.size()):
		var slot: Dictionary = BudapestPlan.SLOTS[i]
		var builder: String = String(slot["builder"])
		var row: Dictionary = TOAST_SCRIPT._city_row(builder)
		if builder.is_empty():
			# THE BEAD'S OWN REQUIREMENT: a wave-C reservation must not be looked
			# up and found missing — it must be recognised as having no row at all,
			# so the arrival sets its bit and says nothing.
			reserved += 1
			if not row.is_empty():
				_fail("slot %d (%s) has an empty builder but resolved a catalogue row"
					% [i, slot["id"]])
			continue
		named += 1
		if row.is_empty():
			_fail("slot %d (%s) names builder %s, which no CITY_LANDMARKS row carries "
				% [i, slot["id"], builder]
				+ "— the catalogue cannot name it and it would count silently")
			continue
		# The plan copies the registry's declared radius; a later edit to a shipped
		# builder's radius must fail a build rather than move the trigger under it.
		if absf(float(row["radius"]) - float(slot["radius"])) > 0.001:
			_fail("slot %d (%s): plan radius %.1f vs registry radius %.1f"
				% [i, slot["id"], float(slot["radius"]), float(row["radius"])])
		if String(row["name"]).is_empty() or String(row["fact"]).is_empty():
			_fail("slot %d (%s) has an empty name or fact — the card would be blank"
				% [i, slot["id"]])

	# The win needs 18 of them, so the table has to hold at least that many.
	if BudapestPlan.SLOTS.size() < PlayerScript.BUDAPEST_WIN_LANDMARKS:
		_fail("the plan has %d slots but the win asks for %d — it is unreachable"
			% [BudapestPlan.SLOTS.size(), PlayerScript.BUDAPEST_WIN_LANDMARKS])
	# A POSITIVE CONTROL on the loop itself: if `_city_row` ever answered {} for
	# everything the loop above would pass in silence.
	if named == 0:
		_fail("no slot in the plan resolved a catalogue row — check 1 measured nothing")
	# Ids are what bead .9's map and any future save would key on.
	var seen: Dictionary = {}
	for i in range(BudapestPlan.SLOTS.size()):
		var id: String = String(BudapestPlan.SLOTS[i]["id"])
		if seen.has(id):
			_fail("slot id %s appears twice in the plan" % id)
		seen[id] = true
	print("[landmark_progress] %d named slots, %d wave-C reservations, win at %d"
		% [named, reserved, PlayerScript.BUDAPEST_WIN_LANDMARKS])
	Sentinel.done("catalogue")


# ============================================================================
# 2. THE MASK, on the shipped player
# ============================================================================

func _check_mask() -> void:
	var player: Node = await _make_player()

	if player.explored_mask != 0 or player.explored_count() != 0:
		_fail("a fresh player starts with mask %d / count %d, not empty"
			% [player.explored_mask, player.explored_count()])

	if not player.explore_landmark(0):
		_fail("the first arrival at slot 0 reported nothing new")
	if player.explored_count() != 1:
		_fail("one landmark explored reads as %d" % player.explored_count())

	# IDEMPOTENT: the toast re-arms its approach latch every time you walk away,
	# so this is asked again on every return trip and must pay nothing twice.
	if player.explore_landmark(0):
		_fail("a second arrival at slot 0 reported itself as new")
	if player.explored_count() != 1:
		_fail("a repeat arrival moved the count to %d" % player.explored_count())

	# Out of range in both directions sets no bit and cannot shift anything.
	for bad: int in [-1, BudapestPlan.SLOTS.size(), 9999]:
		if player.explore_landmark(bad):
			_fail("slot index %d was accepted" % bad)
	if player.explored_count() != 1:
		_fail("an out-of-range index moved the count to %d" % player.explored_count())

	# The mirror ORs and never assigns, and it masks to the slots that exist —
	# both halves, because a mask crosses the wire as one integer.
	player.adopt_explored_mask(0b110)
	if player.explored_count() != 3:
		_fail("adopting two more landmarks reads as %d" % player.explored_count())
	player.adopt_explored_mask(0)
	if player.explored_count() != 3:
		_fail("adopting an EMPTY mask lowered the count to %d — the mirror assigned "
			% player.explored_count() + "instead of OR-ing, and a stale master packet "
			+ "would un-explore the city")
	var hostile: int = 1 << (BudapestPlan.SLOTS.size() + 3)
	player.adopt_explored_mask(hostile)
	if player.explored_count() != 3:
		_fail("a bit outside the plan's %d slots was adopted (count %d)"
			% [BudapestPlan.SLOTS.size(), player.explored_count()])

	player.queue_free()
	Sentinel.done("mask")


# ============================================================================
# 3. THE THRESHOLD — seventeen is not a win, eighteen is
# ============================================================================

func _check_threshold() -> void:
	var win_at: int = PlayerScript.BUDAPEST_WIN_LANDMARKS

	# THE NEGATIVE CONTROL FIRST, and it is the half that matters: without it
	# "eighteen ends the run" is also satisfied by a build that ends every run.
	var short: Node = await _make_player()
	for i in range(win_at - 1):
		short.explore_landmark(i)
	if short.explored_count() != win_at - 1:
		_fail("staging %d landmarks produced a count of %d" % [win_at - 1, short.explored_count()])
	if short.is_game_over:
		_fail("%d of %d landmarks ended the run — the threshold fires early"
			% [win_at - 1, BudapestPlan.SLOTS.size()])
	short.queue_free()

	var full: Node = await _make_player()
	for i in range(win_at):
		full.explore_landmark(i)
	if not full.is_game_over:
		_fail("%d of %d landmarks did not end the run — the win is unreachable"
			% [win_at, BudapestPlan.SLOTS.size()])
	# WON and not CAPTURED: the panel's title, the story line, the film slot and
	# the world archive all branch on this one value.
	if full.run_outcome != PlayerScript.Outcome.WON:
		_fail("the run ended with outcome %d, not WON" % int(full.run_outcome))
	full.queue_free()
	Sentinel.done("threshold")


# ============================================================================
# 4. THE WIRE, WITH THE FIELD ABSENT
# ============================================================================

func _check_decode_absent() -> void:
	# --- the `room` packet ---------------------------------------------------
	# AN OLD MASTER'S PACKET. No `m` at all, and it must still repair the cells:
	# dropping it would cost a mixed room its captive-set convergence over a field
	# that master has never heard of.
	var old_master: Dictionary = MpCodec.decode_room({"cap": ["primm"], "cd": 0.0, "co": 0})
	if old_master.is_empty():
		_fail("decode_room DROPPED a packet with no `m` — an old master's captive-set "
			+ "repair would stop working the day this field shipped")
	elif old_master["cap"] != ["primm"] or int(old_master["m"]) != 0:
		_fail("decode_room read an absent `m` as %s (cap %s), not 0"
			% [old_master.get("m", "<missing>"), old_master["cap"]])

	# A packet that DOES carry one.
	var fresh: Dictionary = MpCodec.decode_room({"cap": [], "cd": 0.0, "co": 0, "m": 0b1011})
	if fresh.is_empty() or int(fresh["m"]) != 0b1011:
		_fail("decode_room lost a live mask: %s" % fresh)

	# A LARGER MASK IS FOLDED, NOT DROPPED — the `co` rule: a peer on a build with
	# a twenty-third landmark is still telling the truth about the first 22.
	var wide: Dictionary = MpCodec.decode_room({
		"cap": [], "cd": 0.0, "co": 0, "m": (1 << (BudapestPlan.SLOTS.size() + 2)) | 0b1,
	})
	if wide.is_empty():
		_fail("decode_room dropped a packet over a mask bit this build does not know")
	elif int(wide["m"]) != 0b1:
		_fail("decode_room folded a wide mask to %d, not to its known bits" % int(wide["m"]))

	# PRESENT BUT MALFORMED STILL COSTS THE PACKET — including the non-finite case,
	# which is the one that matters: `int(INF)` is undefined and on wasm the trunc
	# can trap the module, so it has to be refused BEFORE any cast.
	for bad: Variant in ["7", true, [], {}, INF, -INF, NAN, -1.0]:
		if not MpCodec.decode_room({"cap": [], "cd": 0.0, "co": 0, "m": bad}).is_empty():
			_fail("decode_room accepted a malformed mask %s" % [bad])

	# --- the join snapshot ---------------------------------------------------
	var base: Dictionary = {
		"cc": 0, "gs": 0, "dd": 0, "gc": 0,
		"px": 0.0, "py": 0.0, "pz": 0.0, "ids": [],
	}
	var no_lm: Dictionary = MpCodec.decode_state(base.duplicate())
	if no_lm.is_empty():
		_fail("decode_state DROPPED a snapshot with no `lm` — a peer on an older "
			+ "build is still worth its position, its counters and its id lists")
	elif int(no_lm["lm"]) != 0:
		_fail("decode_state read an absent `lm` as %d, not 0" % int(no_lm["lm"]))

	var with_lm: Dictionary = base.duplicate()
	with_lm["lm"] = 0b101
	var got: Dictionary = MpCodec.decode_state(with_lm)
	if got.is_empty() or int(got["lm"]) != 0b101:
		_fail("decode_state lost a snapshot mask: %s" % got)

	for bad: Variant in ["3", INF, NAN, -2.0, []]:
		var hostile: Dictionary = base.duplicate()
		hostile["lm"] = bad
		if not MpCodec.decode_state(hostile).is_empty():
			_fail("decode_state accepted a malformed `lm` %s" % [bad])
	Sentinel.done("decode_absent")


# ============================================================================
# 5. THE CLAIM VERB — the parser and the proximity rule
# ============================================================================

func _check_claim_verb() -> void:
	var good: Dictionary = MpCodec.decode_lmk({"t": "lmk", "i": 3})
	if good.is_empty() or int(good["i"]) != 3:
		_fail("decode_lmk lost a plain int index: %s" % good)
	# THE RELAY LEG: `JSON.parse_string` hands every number back as a float, so a
	# whole-numbered float is the SAME claim and must decode.
	var relayed: Dictionary = MpCodec.decode_lmk({"mp": "lmk", "i": 3.0})
	if relayed.is_empty() or int(relayed["i"]) != 3:
		_fail("decode_lmk dropped a relayed (float) index — every claim made while "
			+ "ICE is still negotiating would be lost to the room: %s" % relayed)

	var last: int = BudapestPlan.SLOTS.size() - 1
	if MpCodec.decode_lmk({"i": last}).is_empty():
		_fail("decode_lmk refused the LAST slot — the range test is off by one")
	for bad: Variant in [-1, last + 1, 3.5, "3", true, null, INF, NAN, [], {}]:
		if not MpCodec.decode_lmk({"i": bad}).is_empty():
			_fail("decode_lmk accepted a hostile index %s" % [bad])

	# --- the proximity rule --------------------------------------------------
	var slot: Dictionary = BudapestPlan.SLOTS[0]
	var here: Vector3 = slot["pos"]
	var radius: float = float(slot["radius"])
	if not MpCodec.landmark_claim_in_reach(here, here, radius):
		_fail("a peer standing ON a landmark was refused its claim")
	# Just inside and just outside the skirt, so the bound is measured and not
	# merely present.
	var near: Vector3 = here + Vector3(radius + MpCodec.MAX_LANDMARK_CLAIM_PAD - 1.0, 0.0, 0.0)
	if not MpCodec.landmark_claim_in_reach(near, here, radius):
		_fail("a peer inside radius + pad was refused its claim")
	var far: Vector3 = here + Vector3(radius + MpCodec.MAX_LANDMARK_CLAIM_PAD + 1.0, 0.0, 0.0)
	if MpCodec.landmark_claim_in_reach(far, here, radius):
		_fail("a peer OUTSIDE radius + pad was granted its claim — a modified client "
			+ "would win the run from the gate")
	# THE ATTACK THIS EXISTS FOR: a claim from the far side of the world.
	if MpCodec.landmark_claim_in_reach(Vector3(-4000.0, 0.0, 0.0), here, radius):
		_fail("a claim from 5 km away was granted")
	# FLAT XZ: three slots stand on a plateau lid 30-46 m up, and a Y-aware
	# distance would refuse somebody standing directly on top of Buda Castle.
	if not MpCodec.landmark_claim_in_reach(here + Vector3(0.0, 46.0, 0.0), here, radius):
		_fail("a peer 46 m above a landmark was refused — the distance is not flat XZ")
	for bad: Vector3 in [Vector3(INF, 0, 0), Vector3(NAN, 0, 0)]:
		if MpCodec.landmark_claim_in_reach(bad, here, radius):
			_fail("a non-finite claim position was granted")
	if MpCodec.landmark_claim_in_reach(here, here, NAN):
		_fail("a non-finite radius was granted")
	Sentinel.done("claim_verb")


# ============================================================================
# 6. THE TRIGGER — the plan's slots, through the shipped toast
# ============================================================================

func _check_trigger() -> void:
	var player: Node = await _make_player()
	var toast: Control = Control.new()
	toast.set_script(TOAST_SCRIPT)
	root.add_child(toast)
	await process_frame

	# Pick a NAMED slot, so the card path runs too (a reservation returns before
	# `announce` and would leave half of `_arrive_city` unmeasured).
	var index: int = -1
	for i in range(BudapestPlan.SLOTS.size()):
		if not String(BudapestPlan.SLOTS[i]["builder"]).is_empty():
			index = i
			break
	if index < 0:
		_fail("no slot in the plan has a builder — check 6 has nothing to walk into")
		toast.queue_free()
		player.queue_free()
		Sentinel.done("trigger")
		return

	var slot: Dictionary = BudapestPlan.SLOTS[index]
	var centre: Vector3 = slot["pos"]
	var radius: float = float(slot["radius"])

	# OUTSIDE THE CITY FIRST — the rect reject is the whole cost of this feature
	# for the rest of the world, so it had better also be a REJECT.
	player.global_position = Vector3(0.0, 0.0, 0.0)
	toast._scan_city()
	if player.explored_count() != 0:
		_fail("standing at the world origin explored a Budapest landmark")

	# Walk in.
	player.global_position = centre
	toast._scan_city()
	if player.explored_mask & (1 << index) == 0:
		_fail("standing on slot %d (%s) did not claim it" % [index, slot["id"]])
	if toast._city_active != index:
		_fail("the approach did not latch: _city_active is %d, expected %d"
			% [toast._city_active, index])

	# A SECOND TICK IN THE SAME PLACE MUST NOT RE-FIRE. The latch is what stops a
	# card every 0.25 s for as long as you stand still.
	var before: int = toast._visited.size()
	toast._scan_city()
	if toast._visited.size() != before:
		_fail("a second tick on the same slot re-fired the arrival")

	# WALK OUT PAST radius + LEAVE_PAD and the latch re-arms — without which no
	# second landmark could ever be announced.
	player.global_position = centre + Vector3(radius + TOAST_SCRIPT.LEAVE_PAD + 5.0, 0.0, 0.0)
	toast._scan_city()
	if toast._city_active != -1:
		_fail("walking %.0f m past the slot did not re-arm the approach latch"
			% (radius + TOAST_SCRIPT.LEAVE_PAD + 5.0))

	toast.queue_free()
	player.queue_free()
	Sentinel.done("trigger")


# ============================================================================
# 7. THE ROOM'S HYGIENE — the retry queue and the world-replacement wipe
# ============================================================================

func _check_room_hygiene() -> void:
	# --- the wipe, on the shipped player ------------------------------------
	# `reset_position()` is the one owner of the hard-reset wipe list, and
	# `join_at()` is the mid-run path that deliberately does not call it — so both
	# have to clear the mask and both are asked here.
	var player: Node = await _make_player()
	player.explored_mask = 0b111
	player.reset_position()
	if player.explored_mask != 0:
		_fail("reset_position() left %d landmarks explored — a peer adopting a "
			% player.explored_count() + "foreign world seed would carry its solo walk in")
	player.explored_mask = 0b111
	player.join_at(Vector3.ZERO)
	if player.explored_mask != 0:
		_fail("join_at() left %d landmarks explored — a mid-run joiner would count "
			% player.explored_count() + "landmarks the room has never seen")
	player.queue_free()

	# --- the winning arrival pays nothing behind its own panel ---------------
	# `explore_landmark()` reaches `_end_run()` synchronously, so an eighteenth
	# landmark that then armed a 15-25 coin burst would trickle coins into a total
	# the victory panel has already banked and displayed (codex review 2026-09-02).
	var winner: Node = await _make_player()
	var toast: Control = Control.new()
	toast.set_script(TOAST_SCRIPT)
	root.add_child(toast)
	await process_frame
	var win_at: int = PlayerScript.BUDAPEST_WIN_LANDMARKS
	# The FINAL one has to be NAMED, or the card-and-coins path this is about is
	# never reached — so it is picked first and the rest of the staging works round
	# it. Slot 0 today; found rather than assumed, because wave C moves nothing but
	# a future author might.
	var last: int = -1
	for i in range(BudapestPlan.SLOTS.size()):
		if not String(BudapestPlan.SLOTS[i]["builder"]).is_empty():
			last = i
			break
	var staged: int = 0
	for i in range(BudapestPlan.SLOTS.size()):
		if i == last or staged >= win_at - 1:
			continue
		winner.explore_landmark(i)
		staged += 1
	if last < 0 or staged != win_at - 1:
		_fail("could not stage %d landmarks under a named one for the winning-arrival check"
			% (win_at - 1))
	else:
		var coins_before: int = winner.coins_collected
		winner.global_position = BudapestPlan.SLOTS[last]["pos"]
		toast._scan_city()
		if not winner.is_game_over:
			_fail("the eighteenth landmark did not end the run through the toast")
		if winner.coins_collected != coins_before:
			_fail("the winning landmark paid %d coins AFTER the run was banked"
				% (winner.coins_collected - coins_before))
		if toast.visible:
			_fail("the winning landmark raised its card over the victory panel")
	toast.queue_free()
	winner.queue_free()
	# The next two blocks resolve "the player" by group, so the freed one has to be
	# gone from it before they run.
	await process_frame

	# --- the host's retained walk seeds the room's union ---------------------
	# A host is the one peer whose world is NOT replaced, so its `explored_mask`
	# deliberately survives into the room. Left out of `_explored_mask` those
	# landmarks are invisible to every peer for the room's life —
	# `explore_landmark()` refuses a bit it has already set, so nothing can ever
	# report them again (codex review 2026-09-02).
	#
	# Driven through the real `welcome` handler, which is the only place that
	# decides `_first_member`.
	#
	# `lobby_only` IS THE FIXTURE'S SEAM, and it is the shipped flag rather than a
	# stub: the handler's last line is `_lobby.fetch_ice(...)`, and there is no
	# socket under a headless manager, so this used to throw "Nonexistent function
	# 'fetch_ice' in base 'Nil'" on every run. That error aborted
	# `_on_lobby_joined` — the very class of defect bead `godot-test1-llo` is
	# about, one frame down: the mesh setup never ran and nothing said so.
	# `lobby_only` is the relay-only mode's own early return, one line ABOVE the
	# fetch and BELOW everything this block reads, so both fields are still set by
	# the real code on the real path.
	var host: Node = await _make_player()
	host.explored_mask = 0b1001
	var host_mp: Node = MPManager.new()
	host_mp.lobby_only = true
	root.add_child(host_mp)
	await process_frame
	host_mp._on_lobby_joined("host", "AAAAAA", "host", [{"id": "host", "name": "Host"}])
	if not host_mp._first_member:
		_fail("the welcome fixture did not read as a host — check 7's host block "
			+ "measured a joiner instead")
	elif host_mp._explored_mask & 0b1001 != 0b1001:
		_fail("hosting dropped the host's own %d landmarks from the room's union — "
			% 2 + "every peer would evaluate the win against a smaller set")
	host_mp.queue_free()
	host.queue_free()
	await process_frame

	# --- the retry queue, on a real manager ---------------------------------
	# Driven on a bare `MpManager` with the room fields set directly. Every send
	# path degrades to a no-op with no `_rtc` and no `_lobby`
	# (`_send_reliable_to_master` and `_relay_to_negotiating` both return early),
	# which is exactly the case the queue exists for: the packet did not leave.
	var mp: Node = MPManager.new()
	root.add_child(mp)
	await process_frame
	mp._state = MPManager.State.IN_ROOM
	mp._you = "us"
	mp._master = "them"

	mp.report_landmark_explored(4)
	if not mp._pending_landmarks.has(4):
		_fail("a claim the mesh could not carry was forgotten — that landmark can "
			+ "never be reported again and is lost to the room for the run")
	if mp._explored_mask & (1 << 4) == 0:
		_fail("our own claim did not reach our own room mask")

	# THE ACK IS THE MASTER'S PUBLISHED MASK AND NOTHING ELSE. Our own bits are
	# already in `_explored_mask`, so a queue drained by `_apply_explored` would
	# acknowledge every claim the instant it was made — which is a retry that never
	# retries, and passes every other assertion here.
	mp._tick_landmark_claims()
	if not mp._pending_landmarks.has(4):
		_fail("the retry tick dropped an unacknowledged claim")

	# A packet from somebody who is NOT the master acknowledges nothing.
	mp._receive_room("a-stranger", {"cap": [], "cd": 0.0, "co": 0, "m": 1 << 4})
	if not mp._pending_landmarks.has(4):
		_fail("a stranger's `room` packet acknowledged our claim")

	# ...and the master's own does.
	mp._receive_room("them", {"cap": [], "cd": 0.0, "co": 0, "m": 1 << 4})
	if mp._pending_landmarks.has(4):
		_fail("the master published our claim back and it stayed queued — this peer "
			+ "would re-send it twice a second for the rest of the room")

	# A re-election makes US the union: nothing is left outstanding, because
	# everything queued is already in the mask we are about to publish.
	mp.report_landmark_explored(5)
	mp._master = "us"
	mp._tick_landmark_claims()
	if not mp._pending_landmarks.is_empty():
		_fail("becoming the master left %d claims queued for a master that is us"
			% mp._pending_landmarks.size())

	mp.queue_free()
	Sentinel.done("room_hygiene")


# ============================================================================
# FIXTURES
# ============================================================================

func _make_player() -> Node:
	"""
	A real `player.tscn` in the tree, with whatever the staging frame happened to
	do to it undone — `capture_selfcheck._make_player`'s rule and its reason: one
	`await process_frame` is an UNBOUNDED number of physics ticks, so a loaded CI
	runner can land a hit on the body before the check starts.
	"""
	var player: Node = (load(PLAYER_SCENE) as PackedScene).instantiate()
	root.add_child(player)
	await process_frame
	player.is_caught = false
	player.caught_timer = 0.0
	player.is_respawning = false
	player.respawn_timer = 0.0
	player.respawn_blink_timer = 0.0
	player.is_game_over = false
	player.explored_mask = 0
	return player
