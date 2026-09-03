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
##     func _check_thing() -> void:
##         ...
##         Sentinel.done("thing")     # last statement, and before any early exit
##     ...
##     if _failures.is_empty():
##         Sentinel.finish(self)      # replaces print("SELFCHECK OK") + quit(0)

## Which checks reached a deliberate exit this run. Static because a self-check is
## one process running one file — there is no second run to keep apart.
static var _reached: Dictionary = {}


static func done(name: String) -> void:
	"""Stamp `name` as having run to a deliberate exit."""
	_reached[name] = true


static func finish(tree: SceneTree) -> void:
	"""The passing report site: print `SELFCHECK OK` and exit 0 only if every
	stamp the script's own source declares was actually reached."""
	var missed: Array[String] = missing(tree.get_script())
	if missed.is_empty():
		print("SELFCHECK OK")
		tree.quit(0)
		return
	for name: String in missed:
		printerr("FAIL: check \"%s\" never reached its end — a runtime error " % name
			+ "aborted it and every assertion after that point was skipped")
	printerr("SELFCHECK FAILED (%d)" % missed.size())
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
