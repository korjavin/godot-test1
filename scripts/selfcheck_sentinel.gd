extends RefCounted
class_name SelfcheckSentinel
## ============================================================================
## THE END-OF-CHECK SENTINEL — shared by every `scripts/*_selfcheck.gd`
## ============================================================================
##
## THE BUG THIS EXISTS FOR (bead `godot-test1-llo`): a GDScript RUNTIME ERROR
## does not stop the script. It aborts the FUNCTION it happened in — returning
## that function's declared default, `""` for a `-> String` check, which reads as
## "no failure" — and execution carries straight on. So a check that dies three
## assertions in simply stops asserting, the run reaches its report, and the file
## prints `SELFCHECK OK`. Godot exits 0 on such an error, and CI's verdict is
## "exit 0 AND printed SELFCHECK OK" (CLAUDE.md), so today the whole thing is
## invisible. It has shipped twice: `city_map_selfcheck`'s key-free check aborted
## at owner 7 of 13 (fixed in PR #186, whose per-file sentinel this generalises),
## and `landmark_progress_selfcheck._check_room_hygiene` threw
## `Nonexistent function 'fetch_ice' in base 'Nil'` on master and still passed.
##
## THE RULE: every check stamps itself with `done()` as its last statement, and
## before every early return that leaves the run PASSING. The report site calls
## `finish()` instead of printing `SELFCHECK OK` itself; a missing stamp is named
## and the run fails.
##
## TWO DELIBERATE CHOICES, both about not being noisy:
##
##  * **The expected set is READ OUT OF THE CALLING SCRIPT'S SOURCE**, not written
##    down in a `const CHECKS` array beside it. A list is a second place to edit,
##    and a check renamed or added without touching it is silently unguarded —
##    which is the same class of defect this file is here to catch. What the
##    source says it stamps is exactly what must be stamped.
##    `ponytail:` the ceiling is that the `.gd` has to be readable at runtime.
##    A self-check only ever runs as `godot --headless --script res://…`, where it
##    is; nothing here runs in an exported build.
##
##  * **The sentinel is consulted ONLY on the passing path.** A run that already
##    has a real failure fails anyway, and `mp_selfcheck`'s runner stops at the
##    first one — so consulting it there would bury one honest message under
##    twenty-seven "never reached its end" lines for checks that were never
##    reached because the run had already stopped. The defect is precisely
##    "prints SELFCHECK OK after an abort", so the pass is the only place that
##    needs guarding.
##
## USAGE, the whole of it:
##
##     const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")
##     ...
##     func _initialize() -> void:
##         Sentinel.isolate_user_state()   # FIRST statement — see below
##     ...
##     func _check_thing() -> void:
##         ...
##         Sentinel.done("thing")     # last statement, and before any early exit
##     ...
##     if _failures.is_empty():
##         Sentinel.finish(self)      # replaces print("SELFCHECK OK") + quit(0)

## Which checks reached a deliberate exit this run. Static because a self-check is
## one process running one file — there is no second run to keep apart.
static var _reached: Dictionary = {}

# ============================================================================
# HERMETIC `user://` STATE — bead `godot-test1-3y3`
# ============================================================================
#
# `user://` is per PROJECT NAME, not per checkout: every git worktree of this
# repo on one machine writes into the SAME
# `~/Library/Application Support/Godot/app_userdata/CrimeKickers/`. So a check
# that reads the persisted store reads whatever the machine holds, and the two
# ways that goes wrong are both real and were both measured on 2026-09-04:
#
#   * CONCURRENTLY — five developers' sweeps on one box. Each check used to
#     redirect `BestRunStore.config_path` at a FIXED throwaway name of its own
#     (`user://capture_selfcheck_best_run.cfg`), which is private against the
#     player's profile and private against the OTHER checks, and not private at
#     all against the same check running in another worktree. A neighbour's
#     write lands between a check's arrange and its assert.
#
#   * SEQUENTIALLY — a check SIGTERM'd under host load (boss_selfcheck, rc=143)
#     runs no cleanup at all and leaves a store carrying `tower_rescue_primm`,
#     which ARMS systemic capture; `capture_selfcheck`'s pre-beat cases then
#     legitimately fail three checks later. No `finally`-style teardown can fix
#     that, because the killed process never reaches one.
#
# THE ANSWER IS THE SAME FOR BOTH, and it is arranged at ENTRY rather than
# cleaned at exit: every check calls `isolate_user_state()` as the first
# statement of its `_initialize()`, which points every persisted `user://` file
# at a directory private to THIS PROCESS and CREATES IT EMPTY on the spot. A
# neighbour cannot reach it (different pid) and a corpse cannot poison it (its
# leftovers are under its own pid, and this one is new). `progression_selfcheck`
# audits every `scripts/*_selfcheck.gd` for that call and for the absence of any
# other spelling — the store's real path included.
#
# The GAME is untouched: it never assigns these seams, so it still reads and
# writes `user://best_run.cfg` and `user://locale.cfg`.

const SCRATCH_ROOT: String = "user://selfcheck_scratch"

## What the SHIPPED GAME persists to, and the one place those two strings are
## written down outside the files that own them. `progression_selfcheck`'s
## hermeticity audit compares against this and every self-check compares against
## nothing: spelling either path in a `*_selfcheck.gd` is precisely what that
## audit fails on, so it must not have to.
const REAL_PATHS: PackedStringArray = ["user://best_run.cfg", "user://locale.cfg"]

## How long an abandoned scratch directory is left alone before the next check to
## start sweeps it. Only a check killed mid-run leaves one (`release()` takes the
## rest), so this is litter control and nothing else — the day is generous enough
## that it can never race a run that is merely slow.
const SCRATCH_STALE_SECONDS: int = 86400

# UNANNOTATED on purpose: `const X: GDScript = preload(...)` makes X a constant OF
# TYPE GDScript, and the parser then refuses `X.static_var = ...` as an assignment
# to a constant. Inferred, it resolves to the script's class and the static seam is
# writable — `locale_selfcheck.gd` carries the same line for the same reason.
const _BestRunStoreScript := preload("res://scripts/best_run_store.gd")
const _StartOverlayScript := preload("res://scripts/start_overlay.gd")

## This process's private scratch directory, or "" before `isolate_user_state()`.
static var _scratch_dir: String = ""


static func _static_init() -> void:
	"""THE SEAMS MOVE THE MOMENT THIS SCRIPT LOADS, WHICH IS BEFORE ANY CHECK RUNS.

	A GDScript runtime error aborts only the function it lands in, so a redirect
	that lives in an ordinary function has a window: anything that throws with the
	assignments still pending returns to the check with both seams on the SHIPPED
	paths, and the check carries on. That is not merely unhermetic — `_fresh_store()`
	is `remove_absolute(config_path)`, so the next line the check runs DELETES the
	player's real profile. Measured on this branch's first head with an
	out-of-bounds index planted in `isolate_user_state()`.

	Godot's static constructor closes the window instead of narrowing it: it runs
	once, on class load, which is the `preload` at the top of every check — before
	`_initialize()` exists to abort in. Nothing here can throw (two assignments and a
	format string) and nothing here touches the disk, which is the other half of the
	argument: the filesystem work stays in `isolate_user_state()` where a failure is
	survivable.

	THE SHIPPED GAME NEVER LOADS THIS FILE — only `scripts/*_selfcheck.gd` and
	`best_run_e2e.gd` preload it — so the game still persists to its own paths."""
	_point_seams_at_scratch()


static func _point_seams_at_scratch() -> void:
	_scratch_dir = "%s/pid_%d" % [SCRATCH_ROOT, OS.get_process_id()]
	_BestRunStoreScript.config_path = _scratch_dir.path_join("best_run.cfg")
	_StartOverlayScript.locale_config_path = _scratch_dir.path_join("locale.cfg")


static func isolate_user_state() -> void:
	"""Give this process an EMPTY private scratch directory. First statement of
	every check's `_initialize()`.

	The seams are already pointed at it by `_static_init()` above — they are
	re-asserted here so this function is the whole story at its call site, and so a
	check that somehow ran after a `release_user_state()` still lands somewhere
	private. What only this can do is make the directory FRESH, which is the half of
	the bead that stops a SIGTERM'd predecessor's store being inherited."""
	_point_seams_at_scratch()
	_purge_stale_scratch()
	# Wiped rather than merely created: pids are reused, and inheriting a
	# same-pid predecessor's file is the very failure this is here to stop. If the
	# mkdir fails, `ConfigFile.save` into a missing directory fails and the store
	# reads empty — wrong, but still nobody else's file.
	_remove_scratch(_scratch_dir)
	DirAccess.make_dir_recursive_absolute(_scratch_dir)


static func release_user_state() -> void:
	"""Remove this process's scratch directory. Called from `finish()`, on the
	failing branch as well as the passing one; a check that dies harder than that
	simply leaves an inert directory for the next run's `_purge_stale_scratch()`."""
	if _scratch_dir.is_empty():
		return
	_remove_scratch(_scratch_dir)
	_scratch_dir = ""


static func _remove_scratch(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for file_name: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	DirAccess.remove_absolute(path)


static func _purge_stale_scratch() -> void:
	var root: DirAccess = DirAccess.open(SCRATCH_ROOT)
	if root == null:
		return
	var now: int = int(Time.get_unix_time_from_system())
	for name: String in root.get_directories():
		var path: String = SCRATCH_ROOT.path_join(name)
		var stamp: int = int(FileAccess.get_modified_time(path))
		# A zero means the platform would not answer, which is not evidence of
		# staleness — leave it rather than delete a live neighbour's directory.
		if stamp > 0 and now - stamp > SCRATCH_STALE_SECONDS:
			_remove_scratch(path)


static func _isolated() -> bool:
	"""Did `isolate_user_state()` actually finish? Both seams under the scratch
	root is the whole of it — the shipped defaults are not, and neither is a fixed
	throwaway name of somebody's own, which is shared by every worktree on the box."""
	var prefix: String = SCRATCH_ROOT + "/"
	return (_BestRunStoreScript.config_path.begins_with(prefix)
		and _StartOverlayScript.locale_config_path.begins_with(prefix))


static func done(name: String) -> void:
	"""Stamp `name` as having run to a deliberate exit."""
	_reached[name] = true


static func finish(tree: SceneTree) -> void:
	"""The passing report site: print `SELFCHECK OK` and exit 0 only if every
	stamp the script's own source declares was actually reached."""
	var missed: Array[String] = missing(tree.get_script())
	# EVERY CHECK'S PASSING SITE IS WHERE THE ISOLATION IS RE-ASKED, because this is
	# the only place that can see an `isolate_user_state()` that aborted halfway in
	# a check with no live rule of its own — and a check whose stores were the
	# player's may not report OK whatever else it proved. `progression_selfcheck`
	# asserts the same property over the whole glob by reading SOURCE; this asserts
	# it for the process actually running.
	var stray: bool = not _isolated()
	release_user_state()
	if missed.is_empty() and not stray:
		print("SELFCHECK OK")
		tree.quit(0)
		return
	if stray:
		printerr("FAIL: this run's %s / %s are not under %s — `isolate_user_state()` "
			% [_BestRunStoreScript.config_path, _StartOverlayScript.locale_config_path,
				SCRATCH_ROOT]
			+ "never finished, so every store this check touched was somebody else's")
	for name: String in missed:
		printerr("FAIL: check \"%s\" never reached its end — a runtime error " % name
			+ "aborted it and every assertion after that point was skipped")
	printerr("SELFCHECK FAILED (%d)" % (missed.size() + (1 if stray else 0)))
	tree.quit(1)


static func missing(script: Script) -> Array[String]:
	"""Every name `script`'s source stamps that this run never reached, in source
	order. An unreadable source answers empty — the sentinel degrades to the
	behaviour it replaced rather than failing a run it cannot judge."""
	var missed: Array[String] = []
	if script == null:
		return missed
	var source: String = FileAccess.get_file_as_string(script.resource_path)
	if source.is_empty():
		return missed
	var re := RegEx.create_from_string("\\bdone\\(\"([A-Za-z0-9_]+)\"\\)")
	for m: RegExMatch in re.search_all(source):
		var name: String = m.get_string(1)
		if not _reached.has(name) and not missed.has(name):
			missed.append(name)
	return missed
