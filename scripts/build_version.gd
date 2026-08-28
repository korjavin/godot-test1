extends Node
## ============================================================================
## BUILD VERSION WATCH — pull the tab onto a new build, web only
## ============================================================================
## A tab left open for hours keeps running whatever build it booted with. The
## service-worker tombstone (godot-test1-8bu) forced exactly ONE reload on the
## population still holding the old cache-first worker, and after it ran there is
## no service worker left at all — so nothing can push a reload again, and
## `web/nginx.conf`'s `Cache-Control: no-cache` only helps a tab that reloads on
## its own. This node is what makes it reload on its own.
##
## Do NOT solve this by bringing a service worker back. Removing it was the whole
## point of that bead; this works over plain HTTP.
##
## ----------------------------------------------------------------------------
## THE ONE DESIGN POINT THAT MATTERS: THE RUNNING BUILD'S ID IS BAKED IN
## ----------------------------------------------------------------------------
## `BUILD_SHA` below is rewritten by `.github/workflows/build.yml` BEFORE
## `godot --headless --export-release "Web"` runs, so it travels inside the export
## pack — it is the identity of the code the browser is actually executing. The
## same SHA is written to `build/web/version.json` AFTER the export, and that file
## is the identity of the code the server currently offers.
##
## A client must never learn its own version by fetching it. A player served a
## stale shell would fetch the CURRENT marker, compare it against itself, and
## conclude it is up to date — which is precisely the failure this feature exists
## to catch. Baked-in versus fetched is the entire mechanism; keep the bake step
## ahead of the export or this node silently becomes a no-op that always agrees.
##
## ----------------------------------------------------------------------------
## NEVER RELOAD MID-RUN
## ----------------------------------------------------------------------------
## A reload costs the player their distance, their coins and their lives, which is
## a worse outcome than one more session on an old build. So the poll never
## reloads: it only LATCHES `_pending`, and `_process` spends that latch at the
## next safe moment — the start card (nothing to lose yet) or the game-over screen
## (nothing left to lose). An active multiplayer room is unsafe too whatever else
## is on screen: a reload drops the peer out of the mesh mid-session, so we wait
## until they have left the room.
##
## ----------------------------------------------------------------------------
## FAILURE IS ALWAYS SILENCE
## ----------------------------------------------------------------------------
## Offline, a 404, a proxy's HTML error page, a truncated body, a JSON object with
## no `sha` — every one of them leaves the latch exactly as it was and logs
## nothing. This runs unattended for hours; a poll that can spam the console or
## block play is worse than a poll that misses an update.
##
## ----------------------------------------------------------------------------
## KNOWN CEILING: THE GITHUB PAGES MIRROR
## ----------------------------------------------------------------------------
## `web/nginx.conf` is what guarantees `version.json` comes back fresh, and Pages
## does not read it — it applies its own caching to the mirror. So on Pages this
## may notice an update late, or (behind a long-lived CDN copy) not until the next
## natural load. Accepted, not fixed here: the origin players are sent to is
## ck.wandergeek.org, which is the nginx image.
##
## Off-web — desktop, the editor, every headless self-check — `_ready()` returns
## before it builds anything: no HTTPRequest, no timer, no `JavaScriptBridge`,
## no `_process`. The same shape `MobileSensors` and `IntroVideo` carry.

# ============================================================================
# TUNABLES
# ============================================================================

## THE RUNNING BUILD'S IDENTITY, baked in at export time — see the header.
##
## CI rewrites this exact line with `sed`, anchored on `^const BUILD_SHA`, and
## then greps to prove the rewrite landed. Renaming the const or reshaping the
## line turns the bake into a silent no-op, which is why
## `build_version_selfcheck.gd` asserts the line's shape as well as its value.
const BUILD_SHA: String = "dev"

## What an un-baked build carries. A local export, an editor run and this
## repository's own checkout all sit at this value, and it disables the watch
## entirely: with no identity of its own there is nothing to compare against, and
## "differs from the marker" would be true forever.
const UNVERSIONED_SHA: String = "dev"

## The marker CI writes next to `index.html`, resolved against the page's own
## directory so it works under a Pages sub-path as well as at an origin root.
const VERSION_FILE: String = "version.json"

## How often to ask. Minutes, not seconds: this is a courtesy nudge for a tab
## somebody left open, not a race — and every poll is a request per player.
const POLL_INTERVAL_SEC: float = 300.0

## `HTTPRequest` waits forever by default, and one stuck request makes every later
## one on the same node answer ERR_BUSY — the trap `best_run_store.gd` and
## `lobby_client.gd` both document. Short, because nothing waits on this.
const REQUEST_TIMEOUT_SEC: float = 10.0

# ============================================================================
# STATE
# ============================================================================

## Latched by `note_version_body()` the moment the server offers a different
## build, and spent by `_process()` at the next safe moment. Nothing else ever
## clears it: once the running code is known to be superseded it does not become
## current again, so a marker that later agrees (a rollback, a stale CDN copy)
## must not un-latch a reload that is already owed.
var _pending: bool = false

## The poller. Null off-web and until `_ready()` builds it.
var _http: HTTPRequest = null

## The page's own directory URL (".../" including the trailing slash), read once
## from the browser because `HTTPRequest` needs an absolute URL and the export is
## served from a sub-path on one of its two homes. Empty off-web.
var _base_url: String = ""


func _ready() -> void:
	# Group-discovered like everything else here, and PROCESS_MODE_ALWAYS because
	# both safe points can be reached with the tree paused — the start overlay
	# holds a pause of its own, and any panel may be open over the game-over
	# screen. A poll timer that stops whenever the world stops would never fire on
	# the one screen a player leaves a tab sitting on.
	add_to_group("build_version")
	process_mode = Node.PROCESS_MODE_ALWAYS

	if not _watch_enabled():
		# Total no-op off-web and on an un-baked build: nothing built, nothing
		# polled, not even a per-frame branch.
		set_process(false)
		return

	# `pathname`, not `href`: href carries the query string and the hash, and
	# trimming back to the last "/" of THAT can eat the wrong piece. pathname is
	# just the path, so dropping its final segment is exactly "the directory
	# index.html was served from" — which is the origin root on the nginx image and
	# a sub-path on the Pages mirror.
	_base_url = str(JavaScriptBridge.eval(
		"location.origin + location.pathname.replace(/[^/]*$/, '')", true))

	_http = HTTPRequest.new()
	_http.timeout = REQUEST_TIMEOUT_SEC
	_http.request_completed.connect(_on_request_completed)
	add_child(_http)

	var timer := Timer.new()
	timer.wait_time = POLL_INTERVAL_SEC
	timer.autostart = true
	timer.timeout.connect(_poll)
	add_child(timer)


## True only where the watch has both halves it needs: a browser to reload, and an
## identity of its own to compare against. Checked before `JavaScriptBridge` is
## ever touched, which is what keeps a desktop build from erroring.
func _watch_enabled() -> bool:
	return OS.has_feature("web") and BUILD_SHA != UNVERSIONED_SHA


func _process(_delta: float) -> void:
	# One bool test per frame in the overwhelmingly common case. The group lookups
	# below only ever run once an update is actually waiting.
	if not _pending:
		return
	if not _safe_to_reload():
		return
	# Spend the latch BEFORE the reload. `location.reload()` returns immediately
	# and the browser tears the page down whenever it gets round to it, so several
	# more frames run after this line — without clearing here, each of them would
	# fire another reload.
	_pending = false
	_reload_now()


# ============================================================================
# THE SAFE POINT
# ============================================================================

## Is this a moment where losing everything in memory costs the player nothing?
##
## Only two are: the start card, before a run exists, and the game-over screen,
## after the run is already over. Everything else — mid-run, respawning, a panel
## open over a live world — is a moment where a reload throws away distance, coins
## and lives, which is worse than one more session on an old build.
##
## All three lookups are group-based with `has_method` / type guards, so this
## degrades to "not safe" in a scene run standalone rather than erroring.
func _safe_to_reload() -> bool:
	# A room is unsafe whatever is on screen. Reloading drops this peer out of the
	# mesh mid-session, which costs the OTHER players their teammate — so a room
	# outranks both safe points and we simply wait until they have left it.
	var mp: Node = get_tree().get_first_node_in_group("mp")
	if mp != null and mp.has_method("is_online") and bool(mp.is_online()):
		return false

	# Pre-run: the start card (or the intro film behind it) still owns the screen
	# and no run has begun.
	var start: Node = get_tree().get_first_node_in_group("start_overlay")
	if start != null and start.has_method("is_showing") and bool(start.is_showing()):
		return true

	# Post-run: the game-over screen is up. The run is already spent, so there is
	# nothing left for a reload to destroy.
	var game_over: Node = get_tree().get_first_node_in_group("game_over_ui")
	if game_over is CanvasItem and (game_over as CanvasItem).visible:
		return true

	return false


## The one browser call, behind a one-line wrapper so `build_version_selfcheck.gd`
## can drive every decision above on a headless build that has no DOM — the same
## seam `start_overlay._film_finished()` / `_film_teardown()` exists for.
##
## A plain `reload()`, not the long-deprecated `reload(true)`: forced reload was
## removed from every engine, and it is not needed — `web/nginx.conf` sends
## `Cache-Control: no-cache`, so an ordinary reload revalidates every asset and
## lands on the current build.
func _reload_now() -> void:
	JavaScriptBridge.eval("location.reload()", true)


# ============================================================================
# THE POLL
# ============================================================================

func _poll() -> void:
	if _http == null:
		return
	# Already known to be superseded — the answer cannot change, so stop asking.
	if _pending:
		return
	# Cache-busted twice over: a unique query string so no intermediary can match a
	# stored copy, and an explicit `no-cache` for the ones that ignore it. Without
	# this, the marker is the one file whose staleness makes the whole feature a
	# no-op that always agrees.
	var url: String = "%s%s?t=%d" % [_base_url, VERSION_FILE, Time.get_ticks_msec()]
	# Silent on failure, ERR_BUSY included: the next tick is minutes away and
	# nothing waits on this.
	@warning_ignore("return_value_discarded")
	_http.request(url, PackedStringArray(["Cache-Control: no-cache"]))


func _on_request_completed(
	result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	# Transport gate. Offline, DNS failure, a 404 from a build that predates the
	# marker, a proxy's own error page — all "no answer", all silent.
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	note_version_body(body.get_string_from_utf8())


## The whole decision, in one pure function of the fetched text — which is what
## makes it checkable headlessly. Anything that is not an object carrying a
## non-empty string `sha` is "no answer" and leaves the latch untouched; only a
## well-formed marker naming a DIFFERENT build ever latches it.
func note_version_body(body: String) -> void:
	# The INSTANCE parser, never the static one-shot helper: the static one pushes
	# an engine ERROR of its own on malformed input, so a proxy serving an HTML
	# error page would print one to the player's console every poll, forever. Same
	# reason `best_run_store.gd` parses this way, and
	# `build_version_selfcheck.gd` greps this file to keep it that way.
	var json := JSON.new()
	if json.parse(body) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return
	var sha: Variant = (json.data as Dictionary).get("sha")
	if typeof(sha) != TYPE_STRING:
		return
	var served: String = sha as String
	if served.is_empty() or served == BUILD_SHA:
		return
	_pending = true
