extends SceneTree
## The one runnable check for the frame-spike telemetry in `perf_overlay.gd`.
## Run it headless:
##
##     godot --headless --path . --script res://scripts/perf_selfcheck.gd
##
## Prints "SELFCHECK OK" and quits 0, or prints the first failure and quits 1.
## Explicit `if`s rather than `assert`s, for the same reason mp_selfcheck.gd
## gives: asserts are stripped from release builds and this file's value is that
## it still works when somebody runs it against one a year from now.
##
## This telemetry is the measurement GATE for the whole web-performance epic —
## every later phase is judged by whether these numbers move — so a silently
## broken counter would not fail anything, it would just quietly bless a
## regression. Hence a check.
##
## What it guards:
##
##  1. **Sampling runs while the overlay is HIDDEN.** The most valuable spike is
##     the startup one, long before anyone presses F3, and in a release build the
##     overlay starts hidden. If `_sample_frame` ever drifts below the
##     `if not visible: return` early-return, that spike is lost and nothing else
##     would notice.
##  2. **The two thresholds classify correctly**, and a warn is not a severe.
##  3. **Correlation is PER FRAME, not cumulative.** Each spike must carry the
##     chunks built/freed and LOD scans of *its own* frame — the whole point is
##     attributing a freeze to an event, so a baseline that failed to advance
##     would blame every past chunk on the next spike.
##  4. **The log is capped** — an all-day session on a slow phone must not turn
##     the telemetry into its own memory leak.
##  5. **`reset_spike_stats()` re-baselines** rather than merely clearing: after
##     a reset the next spike must report the events of that frame only, not
##     every chunk built since the game started.
##  6. **No managers in the scene is not an error.** A character scene run
##     standalone has no terrain and no LOD manager; sampling must degrade to
##     zeros instead of crashing (the project's has_method/`in` guard rule).
##
## Deliberately NOT covered: the actual frame times of the real game — that is
## what the tool measures, not something a headless check can assert.

const PerfOverlay := preload("res://scripts/perf_overlay.gd")

## Source for a stand-in manager exposing just the counters the overlay polls.
## A stub rather than the real `endless_terrain.gd` / `crocodile_lod_manager.gd`
## on purpose: this check is about the SAMPLER, and booting the world would make
## it slow, non-deterministic and dependent on everything else in the game.
const STUB_SOURCE := """
extends Node
var chunks_created_total: int = 0
var chunks_removed_total: int = 0
var lod_scans_total: int = 0
"""


func _initialize() -> void:
	# _initialize() cannot await, so the checks run as their own coroutine; the
	# tree keeps processing until it calls quit().
	_run()


func _run() -> void:
	# ONE FRAME BEFORE ANYTHING. During `_initialize()` the root window is not in
	# the tree yet, so a node added to it gets no `_ready()` and its `get_tree()`
	# is null — which is exactly what the overlay's group lookups need. After this
	# await every `add_child` below takes effect immediately, and since nothing
	# below awaits again, the engine never ticks `_process` behind our backs: the
	# frame counts asserted here are only the frames we feed by hand.
	await process_frame

	var failure := _check_sampling()
	if failure.is_empty():
		failure = _check_cap_and_reset()
	if failure.is_empty():
		failure = _check_standalone()
	if failure.is_empty():
		print("SELFCHECK OK")
		quit(0)
	else:
		printerr("SELFCHECK FAILED: " + failure)
		quit(1)


# ============================================================================
# CHECKS
# ============================================================================

func _check_sampling() -> String:
	"""Guards 1, 2 and 3: hidden sampling, threshold classification, and that the
	correlated counts belong to the spiking frame alone."""
	if PerfOverlay.SPIKE_WARN_MS >= PerfOverlay.SPIKE_SEVERE_MS:
		return "SPIKE_WARN_MS must be below SPIKE_SEVERE_MS"

	var stub := _make_stub()
	var overlay := _make_overlay()
	# HIDDEN — everything below is asserted against an overlay nobody opened.
	overlay.visible = false

	# Ten ordinary 60 FPS frames: sampled, none of them a spike.
	for i in range(10):
		overlay._process(1.0 / 60.0)
	var summary: Dictionary = overlay.get_spike_summary()
	if summary["frames"] != 10:
		return "hidden overlay sampled %s frames, expected 10 (did _sample_frame " % summary["frames"] \
			+ "fall below the `if not visible: return` early-return?)"
	if summary["spikes"] != 0:
		return "a 16.7 ms frame was logged as a spike"

	# One severe frame, on which the world built 3 chunks, freed 5 and ran the
	# LOD scan once.
	stub.chunks_created_total += 3
	stub.chunks_removed_total += 5
	stub.lod_scans_total += 1
	overlay._process(0.060)

	var spikes: Array[Dictionary] = overlay.get_spike_log()
	if spikes.size() != 1:
		return "expected 1 spike record, got %d" % spikes.size()
	var rec: Dictionary = spikes[0]
	if not rec["severe"]:
		return "a 60 ms frame was not classified SEVERE (threshold is %.1f ms)" % PerfOverlay.SPIKE_SEVERE_MS
	if rec["ms"] < 59.0 or rec["ms"] > 61.0:
		return "spike magnitude recorded as %.2f ms, expected ~60" % rec["ms"]
	if rec["chunks_created"] != 3 or rec["chunks_removed"] != 5 or rec["lod_scans"] != 1:
		return "spike correlation wrong: +%d/-%d chunks, %d lod scans (expected +3/-5, 1)" % [
			rec["chunks_created"], rec["chunks_removed"], rec["lod_scans"]
		]

	# A second, milder spike on which only 2 chunks were built. Its counts must
	# be THAT frame's 2, not the cumulative 5 — the baseline has to have advanced.
	stub.chunks_created_total += 2
	overlay._process(0.040)
	spikes = overlay.get_spike_log()
	if spikes.size() != 2:
		return "expected 2 spike records, got %d" % spikes.size()
	if spikes[1]["severe"]:
		return "a 40 ms frame was classified SEVERE (threshold is %.1f ms)" % PerfOverlay.SPIKE_SEVERE_MS
	if spikes[1]["chunks_created"] != 2:
		return "second spike reported %d chunks built, expected 2 — the previous " % spikes[1]["chunks_created"] \
			+ "reading is not being carried forward, so every spike blames all history"
	summary = overlay.get_spike_summary()
	if summary["warn"] != 1 or summary["severe"] != 1:
		return "summary says warn=%s severe=%s, expected 1 and 1" % [summary["warn"], summary["severe"]]
	if summary["worst_ms"] < 59.0:
		return "worst_ms is %.2f, expected the 60 ms frame" % summary["worst_ms"]

	_destroy(overlay)
	_destroy(stub)
	return ""


func _check_cap_and_reset() -> String:
	"""Guards 4 and 5: the log is bounded, and a reset re-baselines the counters
	instead of replaying the world's whole history into the next spike."""
	var stub := _make_stub()
	var overlay := _make_overlay()

	# Twice the cap in spikes, each one uniquely identifiable by its chunk count.
	var overflow: int = PerfOverlay.SPIKE_LOG_SIZE * 2
	for i in range(overflow):
		stub.chunks_created_total += 1
		overlay._process(0.060)
	var spikes: Array[Dictionary] = overlay.get_spike_log()
	if spikes.size() != PerfOverlay.SPIKE_LOG_SIZE:
		return "spike log holds %d records, expected the SPIKE_LOG_SIZE cap of %d" % [
			spikes.size(), PerfOverlay.SPIKE_LOG_SIZE
		]
	if overlay.get_spike_summary()["severe"] != overflow:
		return "capping the log also lost the running spike COUNT — the cap must " \
			+ "bound memory, not the measurement"

	# Reset, then a spike frame on which nothing happened: it must report zero
	# chunks, not the 64 built above.
	overlay.reset_spike_stats()
	var summary: Dictionary = overlay.get_spike_summary()
	if summary["frames"] != 0 or summary["spikes"] != 0 or summary["worst_ms"] != 0.0:
		return "reset_spike_stats left %s" % summary
	if not overlay.get_spike_log().is_empty():
		return "reset_spike_stats left the spike log populated"

	overlay._process(0.060)
	spikes = overlay.get_spike_log()
	if spikes[0]["chunks_created"] != 0:
		return "after a reset the next spike reported %d chunks built — the " % spikes[0]["chunks_created"] \
			+ "manager baselines were cleared to 0 instead of re-read"

	_destroy(overlay)
	_destroy(stub)
	return ""


func _check_standalone() -> String:
	"""Guard 6: with no terrain and no LOD manager in the scene (a character
	scene run in isolation) sampling degrades to zeros rather than erroring."""
	var overlay := _make_overlay()
	overlay._process(0.060)
	var spikes: Array[Dictionary] = overlay.get_spike_log()
	if spikes.size() != 1:
		return "no-manager spike was not recorded at all"
	if spikes[0]["chunks_created"] != 0 or spikes[0]["lod_scans"] != 0:
		return "no-manager spike reported non-zero engine events"
	_destroy(overlay)
	return ""


# ============================================================================
# FIXTURES
# ============================================================================

func _make_overlay() -> Node:
	## A live perf overlay parented to the tree root, so its group lookups work.
	var overlay := Label.new()
	overlay.set_script(PerfOverlay)
	root.add_child(overlay)
	# Frames are fed by hand below, so take the engine's own `_process` off it —
	# an engine tick slipping in would add frames (and a startup-sized spike) to
	# the very counters we are asserting exact values for.
	overlay.set_process(false)
	return overlay


func _destroy(node: Node) -> void:
	## IMMEDIATE removal, never queue_free: `_initialize()` runs before the main
	## loop, so no frame ever arrives to drain the deletion queue. A queue_free'd
	## stub would still be sitting in the "terrain"/"lod_manager" groups for the
	## next check, which would then silently measure the previous check's fixture.
	root.remove_child(node)
	node.free()


func _make_stub() -> Node:
	## One stand-in node carrying all three counters, joined to BOTH groups the
	## overlay polls. One node for two groups is fine — the property names don't
	## collide, and the overlay caches the two lookups independently.
	var script := GDScript.new()
	script.source_code = STUB_SOURCE
	script.reload()
	var stub := Node.new()
	stub.set_script(script)
	stub.add_to_group("terrain")
	stub.add_to_group("lod_manager")
	root.add_child(stub)
	return stub
