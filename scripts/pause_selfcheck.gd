extends SceneTree
## ============================================================================
## PAUSE SELF-CHECK — run headless, prints "SELFCHECK OK", exits 0
## ============================================================================
##
##     godot --headless --path . --import      # once, so class_name types resolve
##     godot --headless --path . --script res://scripts/pause_selfcheck.gd
##
## Guards `scripts/pause_hub.gd` and the seven scripts that pause through it.
##
## THE DEFECT THIS FILE EXISTS FOR, reproducible on the shipped game before the
## hub landed: press P (pause_controller freezes the world), press `?` to open the
## keymap card over it (help_overlay is PROCESS_MODE_ALWAYS and opening over a
## pause is the point of it — under the old first-taker-owns discipline it claimed
## NOTHING because the tree was already paused), press P again. pause_controller
## released the one and only pause, the world started running, and the help card
## sat over live crocodiles. Check 2 below is that exact sequence, driven through
## the real nodes from `main.tscn` with real key events.
##
## What each check guards, and why it is not vacuous:
##
##  1. **The hub's lifecycle, in isolation.** A takes, B takes, A releases → STILL
##     PAUSED, B releases → running. Plus the three ways a refcount is got wrong:
##     counting occurrences instead of identities (which would strand the world
##     paused forever, because `mp_ui` and `start_overlay` deliberately re-assert
##     their claim every frame), releasing on behalf of a non-holder, and failing
##     to forget a holder that was FREED without releasing.
##
##  2. **The master repro, end to end, through real nodes.** P, `?`, P, `?` — with
##     an assertion after every step, including the positive control that the last
##     `?` really does start the world again (without it, "still paused" would also
##     be satisfied by a P that never released anything).
##
##  3. **Nothing writes `get_tree().paused` behind the hub's back.** A structural
##     scan of every `scripts/*.gd`. The bug was emergent — seven individually
##     correct files — so the durable guard is not "these seven are right today"
##     but "the eighth cannot be written the old way". `touch_controls.gd` carries
##     the one documented exception and says so at the line.
##
##  4. **`mobile_input`'s claim, which is the landmine of the port.** Its
##     `pause_game()` early-returns when already paused, deliberately, so a double
##     app-switch cannot clobber `_was_active_before_pause`. Guarding that on the
##     TREE rather than on our own claim turned it into a missing claim under any
##     foreign pause. Both halves are checked: the claim is now taken over a
##     foreign pause, and the double-call protection still holds.
##
## Deliberately NOT covered: the mouse-capture handovers (headless has no pointer
## lock — `help_selfcheck` covers the half that works without one), and the touch
## resume overlay's own gating, which `touch_controls` decides from
## `paused_by_driver` and which check 4 pins the value of.

const PauseController := preload("res://scripts/pause_controller.gd")
const MobileInput := preload("res://scripts/mobile_input.gd")

## Every `scripts/*.gd` that check 3 lets write `.paused` directly.
##
##   * `pause_hub.gd` IS the authority — it is the one place that may.
##   * `touch_controls.gd` keeps a two-line anti-softlock belt in the unreachable
##     `else` of its resume tap: there is no driver, so there is no holder
##     identity to release with. The line says all this where it lives.
##   * `*_selfcheck.gd` files are `SceneTree` scripts driving fixtures; `paused`
##     there is the harness, not a pauser.
const RAW_PAUSE_ALLOWED: Array = ["pause_hub.gd", "touch_controls.gd"]

var _overlay: Control = null
var _pause_controller: Node = null


## THE END-OF-CHECK SENTINEL. A GDScript runtime error aborts the FUNCTION it
## lands in and lets the script carry on, so a check that dies halfway simply
## stops asserting and this file prints "SELFCHECK OK". Every check below stamps
## itself at its exit; the report site asks whether every stamp was reached.
## `scripts/selfcheck_sentinel.gd` carries the whole reasoning.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")


func _initialize() -> void:
	Sentinel.isolate_user_state()
	# ONE FRAME FIRST. `_initialize()` runs before the main loop, and a node added
	# to `root` before that answers null to `get_tree()` — so every holder in
	# check 1 would claim into nothing and the check would fail on its own fixture.
	# (The same lesson `minimap_selfcheck.gd` records at length.)
	await process_frame
	var failure := _check_hub_lifecycle()
	if failure.is_empty():
		failure = _check_no_raw_pause_writes()
	if failure.is_empty():
		failure = await _check_master_repro()
	if failure.is_empty():
		failure = await _check_mobile_driver_claim()
	if failure.is_empty():
		Sentinel.finish(self)
	else:
		printerr("SELFCHECK FAILED: " + failure)
		quit(1)


# ============================================================================
# 1. THE HUB'S LIFECYCLE
# ============================================================================

func _check_hub_lifecycle() -> String:
	# Plain Nodes as stand-in holders: the hub keys on identity and knows nothing
	# about overlays, so anything in the tree is a valid holder. That is also the
	# point — a future pauser needs no cooperation from this file.
	var a := Node.new()
	var b := Node.new()
	var c := Node.new()
	root.add_child(a)
	root.add_child(b)
	root.add_child(c)

	# Prove the fixture starts clean, or every assertion below reads a stale state.
	if paused or PauseHub.holder_count() != 0:
		return "the tree was already paused (or the hub already had %d holders) before check 1 started" \
			% PauseHub.holder_count()

	PauseHub.take(a)
	if not paused or PauseHub.holder_count() != 1:
		return "one holder took the pause and the tree did not stop (paused=%s, holders=%d)" \
			% [paused, PauseHub.holder_count()]

	PauseHub.take(b)
	if not paused or PauseHub.holder_count() != 2:
		return "a second holder was recorded as %d holders, and the tree is paused=%s" \
			% [PauseHub.holder_count(), paused]

	# --- THE BUG, in one assertion ------------------------------------------
	PauseHub.release(a)
	if not paused:
		return ("A released while B was still holding and the world started running " \
			+ "— this is the shipped defect: press P, press ? over it, press P again, " \
			+ "and the help card is left over live crocodiles")
	if PauseHub.holder_count() != 1:
		return "after A released, the hub reports %d holders instead of 1" % PauseHub.holder_count()

	# POSITIVE CONTROL. Without it "still paused" is equally true of a hub that
	# never unpauses at all — which is a softlock, not a fix.
	PauseHub.release(b)
	if paused or PauseHub.holder_count() != 0:
		return "the last holder released and the tree is still paused (holders=%d) — the game never starts again" \
			% PauseHub.holder_count()

	# --- Idempotence: claims are IDENTITIES, not a tally ---------------------
	# `mp_ui._apply_pause()` and `start_overlay._apply_pause()` are called every
	# frame while open. A hub that counted occurrences would need one release per
	# frame elapsed, i.e. would never unpause again.
	PauseHub.take(a)
	PauseHub.take(a)
	PauseHub.take(a)
	if PauseHub.holder_count() != 1:
		return ("the same holder claiming three times was recorded as %d holders — a " \
			+ "caller that re-asserts its claim every frame could never release it") \
			% PauseHub.holder_count()
	PauseHub.release(a)
	if paused:
		return "one release did not undo three claims by the same holder — the world stays frozen forever"

	# --- A non-holder may not release the world ------------------------------
	PauseHub.take(a)
	PauseHub.release(c)
	if not paused:
		return ("a node that never claimed the pause released it anyway — the exact " \
			+ "shape of the bug, moved one level down into the hub")

	# --- A holder FREED without releasing must be forgotten ------------------
	# The softlock the whole mechanism exists to make impossible: a scene change or
	# a self-check tearing its fixture down leaves a dead id in the set, and the
	# tree stays paused with nothing alive that could ever release it.
	PauseHub.take(b)
	if PauseHub.holder_count() != 2:
		return "the freed-holder case cannot be measured — expected 2 holders, got %d" \
			% PauseHub.holder_count()
	b.free()
	PauseHub.release(a)
	if paused or PauseHub.holder_count() != 0:
		return ("a holder that was FREED without releasing still pins the tree paused " \
			+ "(holders=%d) — nothing alive can ever start the world again") \
			% PauseHub.holder_count()

	# --- The SOLE holder freed, with nothing left to call the hub afterwards ---
	# The case above is the easy one: `release(a)` is itself a hub call, so a hub
	# that only prunes when touched still recovers. This is the one that bites —
	# a scene changed with the start menu, the P-pause or the MP panel still
	# holding the ONLY claim. Nothing calls take or release again, so pruning can
	# never run, and the same SceneTree is left frozen with every holder dead.
	# `take()`'s `tree_exiting` hook is what makes this recoverable.
	var lone := Node.new()
	root.add_child(lone)
	PauseHub.take(lone)
	if not paused:
		return "the sole-holder case cannot be measured — the holder did not pause the tree"
	lone.free()
	if paused:
		return ("the ONLY holder was freed without releasing and the tree is still " \
			+ "paused — a scene change with any overlay up freezes the game forever, " \
			+ "with nothing alive that is allowed to unpause it")
	if PauseHub.holder_count() != 0:
		return "the freed sole holder is still counted (%d holders)" % PauseHub.holder_count()

	a.free()
	c.free()
	print("hub: overlapping claims counted by identity; a dying holder releases itself")
	Sentinel.done("hub_lifecycle")
	return ""


# ============================================================================
# 2. THE MASTER REPRO, THROUGH THE REAL NODES
# ============================================================================

func _check_master_repro() -> String:
	root.add_child(load("res://scenes/main.tscn").instantiate())
	# ONE FRAME before touching anything: `_initialize()` runs before the main
	# loop, so nothing added here has had `_ready()` called yet. (The lesson
	# `minimap_selfcheck.gd` records at length, and `help_selfcheck` repeats.)
	await process_frame

	# `start_overlay` holds a claim of its own from its `_ready()`, and holds it
	# across the whole intro film. Dismissing it is what hands the world back —
	# and is itself the check that the start overlay's claim is releasable.
	var start: Node = root.get_node_or_null("Main/HUD/StartOverlay")
	if start == null:
		return "no StartOverlay under Main/HUD"
	if not start.has_method("_dismiss"):
		return "StartOverlay has no script — run `godot --headless --path . --import` first, " \
			+ "or class_name types fail to resolve and this check passes vacuously"
	if not paused:
		return "the StartOverlay is up but the tree is not paused — the world runs behind the menu"
	# NOT just "the tree is paused" — that was equally true before the refactor,
	# when the menu owned the pause outright and registered with nothing. The
	# assertion with teeth is that the menu is a HOLDER: it is the one pauser that
	# keeps its claim across the whole intro film and hands it to `_dismiss()`, so
	# an overlay opening over the film has to become a second holder rather than
	# ride a claim nobody owns.
	if PauseHub.holder_count() != 1:
		return ("the StartOverlay paused the tree but the hub has %d holders — the menu " \
			+ "is not registered, so anything opening over the film would strand it") \
			% PauseHub.holder_count()
	start._dismiss()
	if paused:
		return "the tree is still paused after dismissing StartOverlay — its claim was never released"

	_overlay = root.get_node_or_null("Main/HUD/HelpOverlay") as Control
	if _overlay == null:
		return "no HelpOverlay under Main/HUD — was it dropped from main.tscn?"
	# `pause_controller` has no scene slot: `player_controller._ready()` adds it as
	# a child of the player at runtime, with whatever name the engine assigns. Find
	# it by script, which is the only stable handle.
	var player: Node = get_first_node_in_group("player")
	if player == null:
		return "no node in group \"player\" — the pause controller is a child of the player"
	for child: Node in player.get_children():
		if child.get_script() == PauseController:
			_pause_controller = child
			break
	if _pause_controller == null:
		return "the player has no pause_controller child — P does not pause anything"

	# --- P: the first holder -------------------------------------------------
	await _press(KEY_P)
	if not paused:
		return "P did not pause the game"
	if not bool(_pause_controller.get("_paused_by_us")):
		return "P paused the game but pause_controller did not record a claim — it can never release it"

	# --- ?: the second holder, over the first --------------------------------
	await _press_question()
	if not bool(_overlay.get("_open")):
		return "\"?\" would not open the help overlay over the P-pause"
	if not bool(_overlay.get("_paused_by_us")):
		return ("the help overlay opened over the P-pause and claimed NOTHING — this is " \
			+ "the shipped defect verbatim: the next P starts the world underneath it")
	if PauseHub.holder_count() != 2:
		return "P and \"?\" are both up but the hub counts %d holders" % PauseHub.holder_count()

	# --- P AGAIN: the release that used to unpause the world ------------------
	await _press(KEY_P)
	if bool(_pause_controller.get("_paused_by_us")):
		return "the second P did not release pause_controller's own claim"
	if not bool(_overlay.get("_open")):
		return "the second P closed the help overlay — it should only drop the P-pause"
	if not paused:
		return ("THE BUG: P released the pause while the help card was still open, and " \
			+ "the world is running behind it with the crocodiles moving")

	# --- POSITIVE CONTROL: closing the help really does start the world -------
	# Without this, every "still paused" above is equally satisfied by a P that
	# releases nothing and a hub that never unpauses.
	await _press_question()
	if bool(_overlay.get("_open")):
		return "\"?\" did not close the help overlay"
	if paused:
		return "STUCK PAUSE — the last holder closed and the tree is still paused; the game never starts again"
	if PauseHub.holder_count() != 0:
		return "the help overlay closed but the hub still holds %d claims" % PauseHub.holder_count()

	print("repro: P + ? + P leaves the world frozen behind the help card; closing it resumes")
	Sentinel.done("master_repro")
	return ""


## Press a raw key the way a player does — through `Input.parse_input_event`, so
## the event takes the real route (viewport → `_input` / `_unhandled_input`).
## Calling a handler directly would prove nothing about whether the key arrives.
func _press(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)
	# Two frames, as `help_selfcheck` does: one to deliver, one for the `_process`
	# re-asserts (`mp_ui`, `skill_tree_ui`, `start_overlay`) to settle.
	await process_frame
	await process_frame


func _press_question() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_QUESTION
	event.unicode = 63
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	await process_frame


# ============================================================================
# 3. NOTHING WRITES get_tree().paused BEHIND THE HUB
# ============================================================================

func _check_no_raw_pause_writes() -> String:
	"""
	The bug was EMERGENT — seven files, each individually correct. So the check
	that keeps it fixed is not about those seven; it is that an eighth pauser
	cannot be written the old way without this failing.

	Matches `.paused =` (an assignment through a dot), which catches
	`tree.paused = true` and `get_tree().paused = false` while leaving the claim
	bits (`_paused_by_us = false`, `paused_by_driver = true`) alone — they carry no
	dot and are exactly what every pauser is supposed to keep.
	"""
	var pattern := RegEx.new()
	if pattern.compile("\\.paused\\s*=[^=]") != OK:
		return "the raw-pause-write regex would not compile — check 3 would pass vacuously"

	var dir := DirAccess.open("res://scripts")
	if dir == null:
		return "could not open res://scripts — check 3 would pass vacuously"
	var names: PackedStringArray = dir.get_files()
	if names.size() < 20:
		return "res://scripts listed only %d files — check 3 would pass vacuously" % names.size()

	var scanned := 0
	var seen_a_pauser := false
	for name: String in names:
		if not name.ends_with(".gd"):
			continue
		if name.ends_with("_selfcheck.gd") or RAW_PAUSE_ALLOWED.has(name):
			continue
		var source: String = FileAccess.get_file_as_string("res://scripts/" + name)
		if source.is_empty():
			return "could not read res://scripts/%s — check 3 would pass vacuously" % name
		scanned += 1
		if source.contains("PauseHub."):
			seen_a_pauser = true
		# Strip the comment tail of every line first: the headers in these files
		# quote the OLD `tree.paused = true` shape at length, on purpose, and a
		# check that cannot tell prose from code would force those explanations out.
		for line: String in source.split("\n"):
			var code: String = line
			var hash_at: int = code.find("#")
			if hash_at >= 0:
				code = code.substr(0, hash_at)
			if pattern.search(code) != null:
				return ("%s writes the tree's paused state directly (`%s`) — every pauser " \
					+ "must go through PauseHub.take()/release(), or its overlay is stranded " \
					+ "over a running world the moment somebody else releases") \
					% [name, code.strip_edges()]

	# The scan must actually be looking at the files that matter, or a rename would
	# turn it into an expensive no-op that reads only bystanders.
	if not seen_a_pauser:
		return "the scan found no PauseHub caller in %d files — it is not reading the pausers" % scanned
	print("sources: %d scripts scanned, none writes get_tree().paused directly" % scanned)
	Sentinel.done("no_raw_pause_writes")
	return ""


# ============================================================================
# 4. THE MOBILE DRIVER'S CLAIM
# ============================================================================

func _check_mobile_driver_claim() -> String:
	"""
	`mobile_input.pause_game()` is the landmine of the port. It early-returns when
	already paused — deliberately, so a double app-switch cannot overwrite
	`_was_active_before_pause` and leave motion permanently dead after the resume
	tap. Testing the TREE rather than our own claim made that early return a
	MISSING CLAIM under any foreign pause, which is the same stranding bug one
	scope down: the phone's resume overlay never appears, and whoever else was
	holding starts the world in a backgrounded tab.
	"""
	var foreign := Node.new()
	root.add_child(foreign)
	var driver := MobileInput.new()
	root.add_child(driver)
	await process_frame

	if paused or PauseHub.holder_count() != 0:
		return "check 4 started with %d holders — an earlier check leaked a claim" \
			% PauseHub.holder_count()

	# Somebody else — the MP panel, the help card — freezes the world first.
	PauseHub.take(foreign)
	driver.active = true
	driver.pause_game()
	if not bool(driver.get("paused_by_driver")):
		return ("a focus-loss pause arriving over somebody else's pause claimed NOTHING " \
			+ "— the phone shows no resume overlay and the other holder's release " \
			+ "starts the world in a backgrounded tab")
	if PauseHub.holder_count() != 2:
		return "the driver claimed over a foreign pause but the hub counts %d holders" \
			% PauseHub.holder_count()

	# THE DOUBLE APP-SWITCH. `active` is false now (pause_game disabled the driver);
	# a second call that re-ran the body would remember THAT as the pre-pause state
	# and motion would stay dead forever after the resume tap.
	if not bool(driver.get("_was_active_before_pause")):
		return "pause_game() did not remember that motion was running — the resume tap cannot restore it"
	driver.pause_game()
	if not bool(driver.get("_was_active_before_pause")):
		return ("a second pause_game() overwrote _was_active_before_pause — a double " \
			+ "app-switch leaves motion permanently dead, with no other re-enable path")

	# The foreign holder lets go; the driver's claim must keep the world frozen.
	PauseHub.release(foreign)
	if not paused:
		return "the foreign holder released and the world started running under the driver's own pause"

	driver.resume_from_pause()
	if paused or bool(driver.get("paused_by_driver")) or PauseHub.holder_count() != 0:
		return "the resume tap left the tree paused (holders=%d) — the phone is stuck on a frozen screen" \
			% PauseHub.holder_count()

	foreign.free()
	driver.queue_free()
	print("mobile: the driver claims over a foreign pause and keeps its double-switch guard")
	Sentinel.done("mobile_driver_claim")
	return ""
