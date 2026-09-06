extends Label
## In-game performance overlay (debug HUD) — our measurement "safety net".
##
## This is Task 1 of the web-performance-optimization plan. Before we change
## anything about how the world renders or how the crocodiles simulate, we need a
## way to *prove* each later change actually helps (numbers move the right way)
## and that nothing regressed. There is no automated test suite in this project,
## so this live overlay is how we measure on the real (web) build.
##
## What it shows, refreshed a few times a second:
##   * FPS                — frames per second (higher is smoother).
##   * Process ms         — CPU time spent in the main (per-frame) logic.
##   * Physics ms         — CPU time spent in the fixed-step physics loop
##                          (this is where the ~1,200 crocodiles cost us today).
##   * Draw calls         — how many separate "draw this" commands the GPU got
##                          this frame. Thousands of unique block meshes blow this
##                          up; MultiMesh batching (Task 4) collapses it.
##   * Primitives         — rendered triangles/lines this frame (geometry load).
##   * Nodes              — total nodes alive in the scene tree (consolidating
##                          per-block collision in Task 5 should drop this hard).
##   * Crocodiles         — how many crocodiles exist, and (once Task 3 lands)
##                          how many are actually *simulating* vs frozen by LOD.
##   * Spikes             — see below.
##
## ----------------------------------------------------------------------------
## FRAME-SPIKE TELEMETRY (the measurement gate for the optimization phases)
## ----------------------------------------------------------------------------
## Average FPS hides the thing players actually complain about: the world runs
## at 60 and then stops dead for a tenth of a second. The rows above are sampled
## at 4 Hz and would never show that frame at all. So on EVERY frame — including
## while the overlay is hidden, because the spike we care about most is the one
## during startup before anyone typed \fo — we compare the frame's own delta
## against two thresholds and, when it is over, log the frame's magnitude
## TOGETHER WITH what the engine did on that same frame:
##
##   * chunks built / freed this frame  (endless_terrain's lifetime counters)
##   * whether the LOD scan ticked      (crocodile_lod_manager's counter)
##   * the live node count
##
## That correlation is the whole point. "60 ms spike" is a complaint; "60 ms
## spike on the frame that freed 5 chunks" is a bug report with an address, and
## it is what the later optimization phases are measured against — each one has
## to move these numbers, not a vibe. Getting the two lined up on the SAME frame
## is the one subtle thing in here; see the off-by-one note in `_sample_frame`.
## Spikes are also printed (throttled) as `[SPIKE]` lines, so a web run leaves a
## readable trail in the browser console with no overlay open.
##
## Read the numbers back with `get_spike_summary()` / `get_spike_log()`, and
## start a fresh measurement window with `reset_spike_stats()`.
##
## Sampling is POLL-based (we read plain counters off the two managers through
## their groups) rather than the managers pushing events at us: the measurement
## must never be able to change what it measures, and a poll that finds no
## manager simply reports zero, so a scene run standalone still works.
##
## Toggle the on-screen stats with cheat code **\fo**. It lives in the HUD
## CanvasLayer as a plain Label. It does not touch gameplay: it only reads
## counters and prints them. It ignores mouse input and starts hidden in release
## builds so it never ends up in a player's face.
##
## **Not localized, deliberately.** This is a debug surface (\fo), read while
## tuning against English documentation, and it is excluded from the game's
## en/de translation pass by design — see CLAUDE.md "Localization".

## How often (seconds) we recompute the text. We deliberately do NOT update every
## frame: counting nodes / iterating the crocodile group every frame would itself
## cost performance and bias the very numbers we are trying to measure. ~4 Hz is
## smooth enough to read while staying cheap.
const REFRESH_INTERVAL: float = 0.25

## Frame-time (ms) at which a frame counts as a SPIKE. 33 ms is one missed frame
## at 30 FPS — the point where a 60 FPS run visibly stutters rather than merely
## dips. Anything under this is normal frame-to-frame jitter and logging it would
## bury the real events.
const SPIKE_WARN_MS: float = 33.0

## Frame-time (ms) at which a spike counts as SEVERE — a hitch nobody misses.
## Kept as a second threshold rather than replacing the first because the two
## measure different things: the warn count is "is frame pacing rough?", the
## severe count is "did the game freeze?", and an optimization can fix one
## without touching the other.
const SPIKE_SEVERE_MS: float = 50.0

## How many spike records `get_spike_log()` keeps. Oldest are dropped once full.
## A cap exists at all because a long session on a bad device could otherwise log
## thousands and the telemetry would become its own memory leak; 32 is plenty to
## eyeball a pattern and small enough that the drop is a trivial pop_front.
const SPIKE_LOG_SIZE: int = 32

## Minimum gap (ms) between two `[SPIKE]` console lines. Every spike is still
## counted and still recorded in the log — this throttles ONLY the printing,
## because a device stuck at 25 FPS spikes on every single frame and 30 console
## writes a second is a measurable cost on exactly the weak targets this tool
## exists to measure.
const SPIKE_PRINT_INTERVAL_MS: int = 1000

## Seconds left until the next text refresh (counts down each frame).
var _time_until_refresh: float = 0.0

# ----------------------------------------------------------------------------
# FRAME-SPIKE TELEMETRY STATE
# ----------------------------------------------------------------------------

## The most recent spikes, oldest first, capped at SPIKE_LOG_SIZE. Each entry is
## a plain Dictionary — see `_sample_frame` for the fields.
var _spike_log: Array[Dictionary] = []

## Totals since the last `reset_spike_stats()` (or since load).
var _frames_sampled: int = 0
var _spike_warn_count: int = 0
var _spike_severe_count: int = 0
var _worst_frame_ms: float = 0.0

## Previous readings of the managers' lifetime counters, so each frame's DELTA
## is a subtraction rather than anything the managers have to reset for us.
var _prev_chunks_created: int = 0
var _prev_chunks_removed: int = 0
var _prev_lod_scans: int = 0

## The PREVIOUS frame's deltas — the work that the `delta` we are handed next
## call is the duration of. See the off-by-one note in `_sample_frame`: these,
## not the freshly computed ones, are what a spike record is built from.
var _pending_created: int = 0
var _pending_removed: int = 0
var _pending_lod: int = 0

## When the last `[SPIKE]` line was printed, for the console throttle.
var _last_spike_print_ms: int = -SPIKE_PRINT_INTERVAL_MS

## Cached manager references, re-acquired whenever they go stale — the same
## group-lookup-plus-revalidate pattern crocodile_lod_manager uses for the
## player. Cached because this samples every frame and a per-frame group lookup
## in the measurement tool is exactly the kind of cost that biases the numbers.
var _terrain: Node = null
var _lod_manager: Node = null


func _ready() -> void:
	# Add to a group so other systems could find/toggle us later if needed.
	add_to_group("perf_overlay")

	# Never let this debug label eat mouse clicks meant for the game/UI.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# MEASURE UNDER THE PAUSE TOO (bead godot-test1-xtr.15). This file's own two
	# promises — "samples EVERY frame, hidden or not", and `_sample_frame`'s note
	# that it takes the ENGINE's delta precisely so a paused tree cannot be read as
	# a 60,000 ms spike — are both false for a PAUSABLE node: `PauseHub` stops
	# `_process` outright, so under any overlay the spike log stops recording and
	# the text freezes at whatever it last said. That is not cosmetic. Every panel
	# that puts the game into a state worth measuring pauses to do it — the MP
	# panel is how you get INTO a room, so the Voice row (bead xtr.4) was reported
	# as permanently empty by everyone who read \fo with that panel open: the last
	# refresh had happened while still OFFLINE, where `debug_line()` correctly
	# answers "". What it costs is what it always cost — a handful of counter
	# reads per frame, plus the 4 Hz group walk and voice query behind the
	# `visible` gate — and none of it MUTATES anything, which is the property a
	# measurement tool needs while the thing it measures is stopped.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Make the readout legible over the bright sky: pale text with a dark outline,
	# pinned to the top-left so it never overlaps the top-right coin counter.
	add_theme_color_override("font_color", Color(0.9, 1.0, 0.9, 1.0))
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	add_theme_constant_override("outline_size", 6)
	add_theme_font_size_override("font_size", 18)

	# Start hidden by default. In a debug build (running from the editor or a
	# debug export) we show it immediately so we always have numbers while
	# developing; in a release build it stays hidden until the player types \fo.
	# This guarantees the overlay never ships "in the player's face".
	visible = OS.is_debug_build()

	# Seed the first refresh so text appears right away rather than after a delay.
	_time_until_refresh = 0.0


func toggle() -> void:
	visible = not visible
	# Forcing an immediate refresh makes the overlay feel instant the
	# moment it is shown.
	if visible:
		_time_until_refresh = 0.0


func _process(delta: float) -> void:
	# Spike sampling runs on EVERY frame, hidden or not — a few int reads and a
	# comparison, cheaper than the visibility check it sits above. It has to be
	# here rather than below the early-return because the freezes we are hunting
	# happen at startup and on chunk-boundary crossings, long before (or entirely
	# without) anyone typing \fo.
	_sample_frame(delta)

	# Cheap-return while hidden so the overlay costs essentially nothing when off.
	if not visible:
		return

	# Throttle the (relatively expensive) stat gathering to REFRESH_INTERVAL.
	_time_until_refresh -= delta
	if _time_until_refresh > 0.0:
		return
	_time_until_refresh = REFRESH_INTERVAL

	_update_text()


## Gather all the counters and rebuild the label text.
func _update_text() -> void:
	# --- Frame timing ------------------------------------------------------
	# FPS straight from the engine. Performance.TIME_PROCESS / TIME_PHYSICS_PROCESS
	# report the last frame's CPU time in *seconds*, so multiply by 1000 for ms,
	# which is the unit everyone reasons about for frame budget (16.6 ms = 60 FPS).
	var fps: float = Engine.get_frames_per_second()
	var process_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0

	# --- GPU / render load -------------------------------------------------
	# Draw calls are the headline number for the MultiMesh batching task: today
	# every decorative block is its own MeshInstance3D + material = its own draw
	# call. Primitives is the raw geometry (triangles) submitted this frame.
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var primitives: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))

	# --- Scene size --------------------------------------------------------
	# Total nodes alive. Consolidating per-block StaticBody3D collision into one
	# body per chunk (Task 5) should make this fall sharply.
	var node_count: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))

	# --- Crocodile simulation count ---------------------------------------
	# Count crocodiles via the "crocodile" group (the same group the LOD manager
	# uses). We also count how many are "active" (fully simulating) vs frozen by
	# LOD. Task 3 added the real `lod_active` flag on each crocodile, so this line
	# now proves the LOD manager is working: when you stand in an open field the
	# active count should be a small handful while the total stays large.
	var crocodiles: Array = get_tree().get_nodes_in_group("crocodile")
	var croc_total: int = crocodiles.size()
	var croc_active: int = 0
	for croc in crocodiles:
		# Stay defensive: `"lod_active" in croc` is true once the property exists
		# (Task 3 onward). If for some reason a crocodile lacks the flag, or its
		# flag is true, it counts as actively simulating.
		if not ("lod_active" in croc) or croc.lod_active:
			croc_active += 1

	# --- Compose the readout ----------------------------------------------
	# Using a multi-line string keeps each metric on its own row, easy to read
	# and easy to screenshot for the before/after measurement table in the plan.
	text = "PERF (\\fo)\n"
	text += "FPS: %d\n" % int(roundf(fps))
	text += "Process: %.2f ms\n" % process_ms
	text += "Physics: %.2f ms\n" % physics_ms
	text += "Draw calls: %d\n" % draw_calls
	text += "Primitives: %d\n" % primitives
	text += "Nodes: %d\n" % node_count
	text += "Crocs (active/total): %d / %d\n" % [croc_active, croc_total]

	# --- Frame-spike telemetry ---------------------------------------------
	# Chunk count first, because it is the number the chunk-streaming phases move
	# and it makes the spike rows below readable at a glance.
	if is_instance_valid(_terrain) and _terrain.has_method("get_chunk_count"):
		text += "Chunks: %d\n" % int(_terrain.get_chunk_count())
	# FIELD ALTITUDE (the spike, bead godot-test1-ope.1): the per-chunk ground
	# collision heightmap is built inside update_chunks' SYNCHRONOUS safety-ring
	# path, so its lifetime cost is polled here like every other spike source.
	# The counter is 0 with FIELD_ALTITUDE off — the shipped world builds a
	# BoxShape3D and never enters the timed block — so the row is absent entirely
	# and the overlay the player sees is byte for byte the one it always was.
	var ground_usec: int = _read_counter(_terrain, "ground_collision_usec_total")
	if ground_usec > 0:
		text += "Ground collision: %.1f ms total\n" % (float(ground_usec) / 1000.0)
	var summary: Dictionary = get_spike_summary()
	# Thresholds come from the constants, not typed into the string, so retuning
	# one can't leave the label claiming a number the code no longer uses.
	text += "Spikes >%d/>%d: %d / %d (worst %.0f ms)\n" % [
		int(SPIKE_WARN_MS), int(SPIKE_SEVERE_MS),
		summary["warn"], summary["severe"], summary["worst_ms"]
	]
	if not _spike_log.is_empty():
		var last: Dictionary = _spike_log[-1]
		text += "Last: %.0f ms  chunks +%d/-%d  lod %d" % [
			last["ms"], last["chunks_created"], last["chunks_removed"], last["lod_scans"]
		]
	else:
		text += "Last: none"

	# --- Voice telemetry (bead godot-test1-xtr.4) -------------------------
	var voice: Node = get_tree().get_first_node_in_group("voice")
	if is_instance_valid(voice) and voice.has_method("debug_line"):
		var vline: String = str(voice.debug_line())
		if not vline.is_empty():
			text += "\n" + vline


# ============================================================================
# FRAME-SPIKE TELEMETRY
# ============================================================================

func _sample_frame(delta: float) -> void:
	## One frame's worth of spike detection. Called every frame; does almost
	## nothing unless the frame was slow.
	##
	## `delta` is the engine's own frame delta, deliberately NOT a wall-clock
	## difference we measure ourselves. That matters most under a PAUSE, which
	## this node runs through (`PROCESS_MODE_ALWAYS`, see `_ready()`): a skill
	## tree left open for a minute is still sixty seconds of ordinary 16 ms
	## frames, and a wall-clock reading taken across a `_process` the engine had
	## skipped would report the whole pause as one 60,000 ms "spike". The
	## engine's delta is the frame's real duration either way.
	_refresh_manager_refs()
	_frames_sampled += 1

	var frame_ms: float = delta * 1000.0
	if frame_ms > _worst_frame_ms:
		_worst_frame_ms = frame_ms

	# Read the correlated counters EVERY frame, spike or not: they are lifetime
	# totals, so skipping a frame would silently fold that frame's work into the
	# next reading and blame the wrong frame.
	var chunks_created: int = _read_counter(_terrain, "chunks_created_total")
	var chunks_removed: int = _read_counter(_terrain, "chunks_removed_total")
	var lod_scans: int = _read_counter(_lod_manager, "lod_scans_total")

	var d_created: int = chunks_created - _prev_chunks_created
	var d_removed: int = chunks_removed - _prev_chunks_removed
	var d_lod: int = lod_scans - _prev_lod_scans
	_prev_chunks_created = chunks_created
	_prev_chunks_removed = chunks_removed
	_prev_lod_scans = lod_scans

	# THE FIRST SAMPLED FRAME IS THE ONE EXCEPTION to the shift explained below,
	# and it happens to be the frame we care about most (the startup freeze phase
	# 3 is aimed at). Everything before the main loop — scene instantiation and
	# every `_ready`, including the terrain's whole synchronous first build — is
	# inside the very first `delta`, AND is already visible in this first counter
	# reading. So frame one owns the work it just observed; it is consumed here so
	# the next frame cannot be blamed for it a second time.
	if _frames_sampled == 1:
		_pending_created = d_created
		_pending_removed = d_removed
		_pending_lod = d_lod
		d_created = 0
		d_removed = 0
		d_lod = 0

	if frame_ms >= SPIKE_WARN_MS:
		# THE OFF-BY-ONE THAT WOULD MAKE ALL OF THIS LIE, and why the record uses
		# `_pending_*` rather than the deltas just computed above:
		#
		# `delta` is the duration of the frame BEFORE this one — the engine hands
		# `_process` the time elapsed since the previous frame. The counters, by
		# contrast, are read now, so the work they just picked up belongs to the
		# frame that is still running. Pairing the two directly would attribute
		# every hitch to the frame AFTER the one that caused it: a spike caused by
		# building ten chunks would be logged with "+0 chunks", and the next,
		# perfectly fine frame would get the blame — exactly backwards for a tool
		# whose entire job is naming the cause.
		#
		# So the deltas measured on the previous call (`_pending_*`, the work of
		# the frame `delta` is now reporting the duration of) are what gets
		# recorded. This holds because EndlessTerrain and CrocodileLODManager both
		# sit above the HUD in main.tscn's tree order and so have already run when
		# we sample; if a future scene reorders them below the HUD, a spike's
		# counts would land one frame late again.
		_record_spike(frame_ms)

	_pending_created = d_created
	_pending_removed = d_removed
	_pending_lod = d_lod


func _record_spike(frame_ms: float) -> void:
	## Log one spiking frame, correlated with the work of that same frame (see the
	## off-by-one note in `_sample_frame` for why that is `_pending_*`).
	var severe: bool = frame_ms >= SPIKE_SEVERE_MS
	if severe:
		_spike_severe_count += 1
	else:
		_spike_warn_count += 1

	# The node count is read HERE and not on every frame because it is the one
	# monitor call in this path, and a spike frame is a rare frame.
	var record: Dictionary = {
		"ms": frame_ms,
		"severe": severe,
		"uptime_ms": Time.get_ticks_msec(),
		"chunks_created": _pending_created,
		"chunks_removed": _pending_removed,
		"lod_scans": _pending_lod,
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
	}
	_spike_log.append(record)
	if _spike_log.size() > SPIKE_LOG_SIZE:
		_spike_log.pop_front()

	# A line to the console/browser log — the only way to capture the trail from a
	# web build nobody opened the overlay on. THROTTLED, because the case we most
	# want to measure is a device sustaining 25 FPS, where EVERY frame clears the
	# 33 ms bar: printing 30 lines a second into a browser console is itself
	# expensive enough to change the numbers we came to read. The in-memory log
	# and the counters are unthrottled, and the running spike total in the line
	# below makes any suppressed run visible (the count jumps).
	var now: int = Time.get_ticks_msec()
	if now - _last_spike_print_ms < SPIKE_PRINT_INTERVAL_MS:
		return
	_last_spike_print_ms = now
	print("[SPIKE] %.1f ms%s | chunks +%d/-%d | lod scans %d | nodes %d | #%d" % [
		frame_ms,
		" SEVERE" if severe else "",
		record["chunks_created"],
		record["chunks_removed"],
		record["lod_scans"],
		record["nodes"],
		_spike_warn_count + _spike_severe_count,
	])


func _read_counter(cached: Node, property: String) -> int:
	## Read one lifetime counter off a manager, or 0 if it isn't there.
	##
	## Defensive on purpose and in the project's usual style: a scene run
	## standalone has no terrain and no LOD manager, and another node that
	## happened to join the group may not expose the property. Neither is an
	## error — the telemetry just reports no events from that source.
	if not is_instance_valid(cached) or not (property in cached):
		return 0
	return int(cached.get(property))


func _refresh_manager_refs() -> void:
	## (Re)acquire the two managers we poll, through their groups (never a
	## $-path or an exported reference). Only looks a manager up when we don't
	## already hold a live one, so the steady state costs two validity checks per
	## frame and no group lookup.
	if not is_instance_valid(_terrain):
		_terrain = get_tree().get_first_node_in_group("terrain")
	if not is_instance_valid(_lod_manager):
		_lod_manager = get_tree().get_first_node_in_group("lod_manager")


# ----------------------------------------------------------------------------
# PUBLIC TELEMETRY API (used by the later optimization phases and by selfchecks)
# ----------------------------------------------------------------------------

func get_spike_summary() -> Dictionary:
	## Headline numbers for the current measurement window: how many frames were
	## sampled, how many spiked (split by severity), and the worst frame seen.
	## `spikes_per_min` is the comparable one — two runs of different lengths
	## have incomparable raw counts. It assumes a 60 FPS nominal frame budget,
	## which is what "frames sampled" has to be converted with; it is a rate for
	## comparing two runs, not a wall-clock measurement.
	var spikes: int = _spike_warn_count + _spike_severe_count
	var minutes: float = maxf(float(_frames_sampled), 1.0) / (60.0 * 60.0)
	return {
		"frames": _frames_sampled,
		"spikes": spikes,
		"warn": _spike_warn_count,
		"severe": _spike_severe_count,
		"worst_ms": _worst_frame_ms,
		"spikes_per_min": float(spikes) / minutes,
	}


func get_spike_log() -> Array[Dictionary]:
	## The recorded spikes, oldest first (at most SPIKE_LOG_SIZE). Each entry:
	## `ms`, `severe`, `uptime_ms`, `chunks_created`, `chunks_removed`,
	## `lod_scans`, `nodes`. Returns the live array — read it, don't mutate it.
	return _spike_log


func reset_spike_stats() -> void:
	## Start a fresh measurement window: take a before/after around the change
	## you are testing. The managers' lifetime counters are NOT reset (they
	## aren't ours); we only re-baseline our own previous readings so the first
	## frame after a reset doesn't report every event since the game started.
	_spike_log.clear()
	_frames_sampled = 0
	_spike_warn_count = 0
	_spike_severe_count = 0
	_worst_frame_ms = 0.0
	_refresh_manager_refs()
	_prev_chunks_created = _read_counter(_terrain, "chunks_created_total")
	_prev_chunks_removed = _read_counter(_terrain, "chunks_removed_total")
	_prev_lod_scans = _read_counter(_lod_manager, "lod_scans_total")
	# The carried-over frame's work goes too, or the first spike after a reset
	# would still be labelled with the events of the frame before it.
	_pending_created = 0
	_pending_removed = 0
	_pending_lod = 0
