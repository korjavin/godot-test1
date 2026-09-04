extends Node
class_name BestRunStore
## Where the personal best-run records live, and how they reach the lobby.
##
## Two layers, and the split is the whole point:
##
##   * LOCAL — a `ConfigFile` at `user://best_run.cfg` on desktop, and
##     `window.localStorage` **on web**.
##
##     MEASURED, because the obvious story turned out to be wrong: `user://` on
##     the web export IS a working IndexedDB mount. Driven headless against the
##     deployed build, a record written at game over reached IndexedDB, came back
##     across a reload, and correctly suppressed the "NEW BEST!" flash — in
##     Chromium AND in WebKit. So the reported "every run flashes NEW BEST" is
##     **not** this code path failing; it is site storage not surviving in the
##     reporter's browser (Safari/iOS purges IndexedDB for sites without recent
##     interaction, a private window keeps none of it, and GitHub Pages vs the
##     deployment host are two different origins with two different stores) —
##     which is exactly the class of failure only a server-side store can fix.
##
##     localStorage is still the better local half, for two reasons that survive
##     that finding: the player id has to live there anyway (nothing else on web
##     is both synchronous and readable before the engine's first frame), and
##     `setItem` has committed when it returns, whereas an IndexedDB write is
##     flushed a frame or more later — a tab closed inside that window loses it.
##     A pre-existing `user://` record is still READ on web, so nobody's stored
##     best is thrown away by the switch; see `_read_local`.
##
##   * SERVER — `GET`/`POST <lobby>/best?id=<player id>` on the same Go lobby the
##     multiplayer code already talks to (`server/best.go`). It is the
##     owner-chosen fix, and what it actually buys is that a record survives the
##     browser throwing site storage away. Every failure is silent and non-fatal:
##     the local layer has already answered, so a lobby that is down, old, or
##     blocked by CORS costs nothing but the server half.
##
##     **CEILING — "follows you between devices" means devices that SHARE THE ID,
##     and nothing here transfers one.** The id is minted per browser profile and
##     per install, so a second device starts a fresh record; wiping localStorage
##     *and* `user://` on the one device orphans the old record too (it stays on
##     the server, unreachable, until the cap evicts it). That is the bead's own
##     design — this game has no accounts and the owner scoped the acceptance to
##     "devices sharing the player id". `ponytail:` the upgrade path is showing
##     the id somewhere the player can copy it and accepting a pasted one, which
##     is a UI feature, not a change here; a real login is the one after that.
##
## RECORDS ONLY EVER GO UP, on both layers and on the server. That is what makes
## the ordering irrelevant: `loaded` fires once with the local values (inside
## `fetch()`, synchronously) and possibly again when the server answers with
## better ones, and the player folds each in with `maxi`. A late reply cannot
## lower anything, a lost reply costs nothing, and a retried POST is idempotent.
##
## Deliberately NOT here: a leaderboard (owner: personal bests only), any
## authentication (see `server/best.go`'s trust-model note), and any retry timer —
## the next game over posts again.
##
## IT ALSO CARRIES THE META-PROGRESSION COUNTERS (`lifetime_coins` /
## `spent_points`), and that is reuse rather than scope creep: they are keyed by
## the same player id, want the same monotone merge, the same local layers and the
## same silent-failure rule, so a store of their own would have been this file
## twice plus a second `/best`-shaped route (and a second entry in the Traefik
## path rule in `server/docker-compose.yml`). They ride the SAME record on the
## server — see `server/best.go`. `scripts/progression.gd` owns what they MEAN;
## this file only knows they are two numbers that never go down.
##
## THE PER-HERO SKILL RANKS (`skill_ranks`) ride the LOCAL layer AND NOTHING
## ELSE, and that asymmetry with the two counters beside them is deliberate:
##
##   * `spent_points` — a scalar that only ever rises — stays the whole of the
##     progression surface the server sees, so `server/best.go` needed no change,
##     no new route appeared, and the Traefik path rule in
##     `server/docker-compose.yml` stayed as it was. A dict of dicts on the wire
##     would need a schema plus a per-entry merge rule on the Go side to keep the
##     monotone guarantee that makes every POST idempotent.
##   * The ranks merge **per entry with `maxi`** (`merge_ranks()`), which is the
##     same monotone rule one dimension down, and is exactly right because v1 has
##     no respec: a rank never falls, so a stale local copy can only ever be
##     behind and merging can only ever be correct.
##   * The ceiling, stated plainly: a device that somehow learns a HIGHER
##     `spent_points` from the server than its own rank map accounts for has
##     fewer points to spend and no extra ranks. `unspent_points()`'s `maxi(0, …)`
##     absorbs it. Never a free rank, never a negative count — the safe
##     direction, and unreachable in practice for the same reason the record
##     "follows you between devices" ceiling above is: the player id is minted per
##     browser profile and per install, so two devices are two profiles.

# =============================================================================
# CONFIGURATION
# =============================================================================

## Desktop persistence. Kept at the path (and section) `player_controller.gd`
## already used, so an existing desktop record survives this change.
##
## STATIC AND WRITABLE PURELY AS A TEST SEAM, and nothing in the game ever
## assigns it — the running game always uses the default. A self-check cannot
## assert against this file: every write here is a monotone read-modify-write
## merge (see `_write_local`), so a check that stores 1234 into a developer's
## real profile reads back whatever larger number that profile already held.
## Backing the file up and putting it back does not fix that — the merge happens
## while the check is running — and it puts a real record one crashed assertion
## away from being lost. So a check points this at a throwaway path for its
## duration instead; `progression_selfcheck.gd` and `best_run_e2e.gd` both do.
## Static rather than per-instance so ONE assignment covers every store the run
## builds, including the one `player_controller._ready()` makes for itself.
static var config_path: String = "user://best_run.cfg"
const CONFIG_SECTION: String = "best"
const CONFIG_PLAYER_SECTION: String = "player"

## Web persistence: `localStorage` keys. Prefixed because the origin is shared
## with whatever else is served from it.
const LS_PLAYER_ID: String = "ck_player_id"
const LS_DISTANCE: String = "ck_best_distance"
const LS_COINS: String = "ck_best_coins"
const LS_HAS_WON: String = "ck_has_won"
const LS_LANDMARKS_BEST: String = "ck_landmarks_best"
const LS_LIFETIME: String = "ck_lifetime_coins"
const LS_SPENT: String = "ck_spent_points"
## The per-hero skill ranks, as a JSON object. JSON on BOTH layers (rather than a
## ConfigFile-native Dictionary on desktop) so there is one parse path to get
## wrong instead of two, and so a hand-edited or truncated value fails the same
## way everywhere: it is ignored and the ranks stay as they were.
const LS_RANKS: String = "ck_skill_ranks"

const CONFIG_RECORD_HAS_WON: String = "has_won"
const CONFIG_RECORD_LANDMARKS_BEST: String = "landmarks_best"

## Desktop section for the progression counters. A section of its own so a
## player's meta-progression is legible in `best_run.cfg` and so deleting it by
## hand (the bead's "clean profile" case) does not touch their best run.
const CONFIG_PROGRESSION_SECTION: String = "progression"

## Desktop section for THE TOWER'S EARNED STATE — one monotone set of ids (see
## the tower block further down). A section of its own for the same two reasons
## the progression one has one: it is legible in the file, and deleting it by
## hand resets the tower without touching a best run or a level.
##
## `ponytail:` THE PER-WORLD SAVE MODEL IS A SEPARATE, LARGER EPIC — session-03
## of the tower epic (godot-test1-3iy) identified it, and NEW GAME BEHAVIOUR IS
## EXPLICITLY OUT OF SCOPE HERE. So today there is exactly one record and
## `endless_terrain.new_run()` does not clear it: a new run moves the tower's
## SITE and rebuilds the shell, and the rebuilt shell hydrates the same earned
## set — deliberately, and on the same footing as the meta-progression counters
## above, which are run-independent for the same reason.
##
## The epic slots in AROUND this record without touching the set semantics: a
## save id becomes a second key in this section, or a section suffix, and each
## save gets its own union-merged set. Nothing below needs to know that happened
## — which is the point of putting the whole thing in one section behind two
## functions.
const CONFIG_TOWER_SECTION: String = "tower"
const CONFIG_TOWER_KEY: String = "opened_ids"

## THE WORLD ARCHIVE — the full-custody protocol's failure record (phase 11).
##
## `[world] archived = true` and nothing else. Its own section, and the choice of
## home is the whole design decision, so it is written down rather than implied:
##
##   * NOT the tower's opened set above, even though it sits one section away. That
##     set is a monotone UNION with no removal verb, by design — and this latch has
##     to be CLEARED, because New Game is what un-ends a campaign. A latch that can
##     go backwards does not belong in a union, which is the same rule that keeps
##     the captive set out of it (`player_controller.captive_heroes`).
##   * NOT nowhere, which is where the tower guards live: a campaign that ended
##     must still be over after a relaunch. That is the entire feature — Continue
##     reopens the ending screen.
##
## `ponytail:` THE PER-WORLD SAVE ID IS STILL THE SEPARATE, LARGER EPIC the tower
## section above declined to entangle with, and it has not landed. So today there
## is one world, `new_game()` clears the latch, and that IS "New Game mints a fresh
## save id" with one slot. The epic slots in around this exactly as it does around
## the tower set: the id becomes a second key here or a section suffix, `new_game()`
## mints it instead of clearing, and no caller below or above changes.
const CONFIG_WORLD_SECTION: String = "world"
const CONFIG_WORLD_ARCHIVED: String = "archived"

## Hard bound on the stored tower set, at BOTH ends — what is written and what is
## accepted back. The same discipline (and the same reason) as
## `MpCodec.MAX_STATE_IDS`: this exists to keep a corrupt or hand-edited file
## from being walked without limit, not to police how much of the tower a player
## may open. The whole authored building is a dozen ids (`tower_graph.gd`), so
## 256 is two orders of headroom and still a bound.
const MAX_TOWER_IDS: int = 256

## The player id is 128 random bits as 32 hex characters — inside the lobby's
## `^[A-Za-z0-9_-]{8,64}$` guard, and wide enough that guessing somebody else's
## is the only attack and it does not work.
const PLAYER_ID_HEX_LEN: int = 32

## `HTTPRequest`'s default timeout is *wait forever*, and a stuck request makes
## every later one on that node answer ERR_BUSY — the trap `lobby_client.gd`
## documents at length. Short, because nothing waits on these.
const REQUEST_TIMEOUT_SEC: float = 5.0

# =============================================================================
# SIGNALS
# =============================================================================

## Best-known records. May fire more than once (local first, then the server if
## it knows better); the values only ever rise.
signal loaded(distance: int, coins: int)

## Best-known progression counters. Same contract as `loaded`: fires once with
## the local values inside `fetch()`, and again only if the server knew better.
## The values only ever rise, so a listener folds each in with `maxi`.
signal progression_loaded(lifetime_coins: int, spent_points: int)

# =============================================================================
# STATE
# =============================================================================

## Best known to this store. Public so a caller can read them without waiting.
var distance: int = 0
var coins: int = 0

## The coins record THE SERVER REPORTED, kept PRE-MERGE and deliberately
## beside `coins` rather than folded into it. `coins` is the merged best
## and includes this session's own `submit()`s, so it cannot answer the one
## question the "NEW BEST!" flash needs — "was there already a record this run
## had to beat" — because by then an echo of our own bank and a record another
## device holds are the same number. This one is only ever written from a GET
## reply, so it is that other device's number and nothing else.
##
## Stays 0 while the lobby is unreachable, which reads as "no external record"
## and leaves the caller's local comparison standing.
var server_best_coins: int = 0
var server_best_distance: int = 0

## Meta-progression, same monotone rule. `lifetime_coins` is cumulative coins
## picked up across every run ever and is NEVER deducted (owner, 2026-08-25);
## spending a skill point raises `spent_points` instead. The LEVEL is not stored
## anywhere — `progression.gd` derives it from `lifetime_coins`, so a stored level
## cannot drift from the count that produced it.
var lifetime_coins: int = 0
var spent_points: int = 0

## Win state (OR-merged) and best landmark count (max-merged) for Budapest escape.
var has_won: bool = false
var landmarks_best: int = 0

## Per-hero skill ranks (`hero → { skill id: rank }`), LOCAL LAYER ONLY — see the
## header for why they never reach the server. Merged, never assigned.
var skill_ranks: Dictionary = {}

var _player_id: String = ""

## Two `HTTPRequest` nodes, deliberately — one node answers ERR_BUSY while a
## request is in flight, and the boot GET can still be running when a very short
## first run ends. Same reasoning (and the same fix) as `lobby_client.gd`'s
## `_http` / `_rooms_http` split.
var _get_http: HTTPRequest = null
var _post_http: HTTPRequest = null

## Whether the boot GET's reply may be trusted as a PRE-SUBMIT baseline — which is
## the only thing `server_best_distance` is for, and the one property the two
## `HTTPRequest` nodes above take away. They overlap on purpose (that is the whole
## reason for the split), the lobby serves them concurrently, and nothing orders
## them: a bite in the first seconds of a run POSTs this run's distance, and if
## that merge lands before the still-in-flight GET is read, the reply hands our
## OWN number back as if another device held it. The reconciliation then takes
## back a flash the player earned — exactly the echo the pre-merge field exists
## to be immune to.
##
## So a POST that actually started while the GET was outstanding retires the
## baseline. `server_best_distance` then stays 0, which is already the documented
## "no external record" degrade, and the local comparison stands — the safe
## direction, because the alternative claims a record on evidence we produced.
## The next boot's GET has no POST racing it and reports the truth.
var _get_in_flight: bool = false
var _get_baseline_ok: bool = false


# =============================================================================
# PUBLIC API
# =============================================================================

func fetch() -> void:
	"""
	Load the records. The local layer answers immediately (so a boot with no
	network behaves exactly as it always did), then the server is asked and may
	raise them.
	"""
	_read_local()
	loaded.emit(distance, coins)
	progression_loaded.emit(lifetime_coins, spent_points)
	_request_get()


func submit(_new_distance: int, new_coins: int) -> void:
	"""
	Record a run's results. Called from `_trigger_game_over()` only when a record
	actually moved, so this is not a per-frame path.

	It re-reads the local store first so that a `submit()` without a preceding
	`fetch()` cannot LOWER a stored record — `coins` starts at 0, and a plain
	`_write_local()` off that would overwrite a real best with this run's number.
	One file open per game over, and it makes call order stop mattering.
	"""
	_read_local()
	coins = maxi(coins, new_coins)
	distance = 0
	_write_local()
	_request_post()


func submit_progression(
	new_lifetime: int, new_spent: int, new_ranks: Dictionary = {}
) -> void:
	"""
	Record the meta-progression counters. Called by `progression.gd` on a level-up,
	at game over, and on every skill point spent — not a per-pickup path.

	`new_ranks` is a TRAILING parameter defaulting to {}, so the pre-skill-tree
	call shape stays inert (an empty merge changes nothing); the ranks are merged
	per entry, never assigned, for the monotone reason in the header.

	Same shape and same reasoning as `submit()`, including the `_read_local()`
	first: without it a store whose `fetch()` never ran would write its zeroes over
	a real lifetime total, which on this record is a player's LEVEL.

	A save landing while the previous POST is still in flight is answered ERR_BUSY
	and dropped — a level-up followed closely by a game over is the realistic case.
	That costs only the SERVER half (the local layer is written above, before the
	request), and it is self-repairing rather than lost: the next boot's GET sees a
	server behind the local record and fires the catch-up POST for exactly this.
	"""
	_read_local()
	lifetime_coins = maxi(lifetime_coins, new_lifetime)
	spent_points = maxi(spent_points, new_spent)
	merge_ranks(skill_ranks, new_ranks)
	_write_local()
	_request_post()


func player_id() -> String:
	"""
	This player's persistent id, generated once and kept in the same local store
	as the records. Empty only when the store is unwritable (a private window
	with `localStorage` disabled), in which case the server half is simply
	skipped — see `_request_get`.
	"""
	if _player_id.is_empty():
		_player_id = _load_or_make_player_id()
	return _player_id


# =============================================================================
# LOCAL LAYER
# =============================================================================

func _read_local() -> void:
	"""
	Raise the in-memory records from the local store.

	The ConfigFile is read on EVERY platform, web included, and that is the
	one-way migration: a web player who already has a record in the old
	`user://best_run.cfg` keeps it, and the next `_write_local()` mirrors it into
	localStorage. Reading both costs one file open at boot and means the switch
	throws nobody's best away.
	"""
	if OS.has_feature("web"):
		coins = maxi(coins, maxi(0, _ls_get(LS_COINS).to_int()))
		lifetime_coins = maxi(lifetime_coins, maxi(0, _ls_get(LS_LIFETIME).to_int()))
		spent_points = maxi(spent_points, maxi(0, _ls_get(LS_SPENT).to_int()))
		has_won = has_won or (_ls_get(LS_HAS_WON) == "1" or _ls_get(LS_HAS_WON) == "true")
		landmarks_best = maxi(landmarks_best, maxi(0, _ls_get(LS_LANDMARKS_BEST).to_int()))
		merge_ranks(skill_ranks, _parse_ranks(_ls_get(LS_RANKS)))
	var cfg := ConfigFile.new()
	# A missing file (first ever run) is NOT an error — the zero defaults stand.
	# That is also the bead's "delete the file, get a clean level-0 profile" case.
	if cfg.load(config_path) != OK:
		return
	coins = maxi(coins, maxi(0, int(cfg.get_value(CONFIG_SECTION, "coins", 0))))
	has_won = has_won or bool(cfg.get_value(CONFIG_SECTION, CONFIG_RECORD_HAS_WON, false))
	landmarks_best = maxi(
		landmarks_best,
		maxi(0, int(cfg.get_value(CONFIG_SECTION, CONFIG_RECORD_LANDMARKS_BEST, 0)))
	)
	lifetime_coins = maxi(
		lifetime_coins,
		maxi(0, int(cfg.get_value(CONFIG_PROGRESSION_SECTION, "lifetime_coins", 0)))
	)
	spent_points = maxi(
		spent_points,
		maxi(0, int(cfg.get_value(CONFIG_PROGRESSION_SECTION, "spent_points", 0)))
	)
	merge_ranks(
		skill_ranks,
		_parse_ranks(String(cfg.get_value(CONFIG_PROGRESSION_SECTION, "skill_ranks", "")))
	)


func _write_local() -> void:
	"""
	Persist the records (and the player id, which shares the store). Failures are
	ignored: an unpersisted record is non-fatal and must never interrupt the
	game-over flow.

	EVERY WRITE IS A READ-MODIFY-WRITE MERGE, and that is what makes two stores on
	one file safe. A store serializes ALL its fields, but it only ever *changes*
	the two it was told about — the other pair is whatever it happened to read at
	boot. So without the `_read_local()` below, the player's store mirroring a
	late GET reply would write its boot-time `lifetime_coins` over a level the
	player earned in between (and the progression store would do the same to a
	fresh best run). Reading first makes the write a merge instead of an
	overwrite: `_read_local()` only ever raises, so this cannot lower anything,
	and the cost is one file open on a path that runs at a level-up and a game
	over, never per frame.
	"""
	_read_local()
	if OS.has_feature("web"):
		_ls_set(LS_DISTANCE, "0")
		_ls_set(LS_COINS, str(coins))
		_ls_set(LS_HAS_WON, "1" if has_won else "0")
		_ls_set(LS_LANDMARKS_BEST, str(landmarks_best))
		_ls_set(LS_LIFETIME, str(lifetime_coins))
		_ls_set(LS_SPENT, str(spent_points))
		_ls_set(LS_RANKS, JSON.stringify(skill_ranks))
		return
	var cfg := ConfigFile.new()
	cfg.load(config_path)  # keep any other section (the player id) intact
	cfg.set_value(CONFIG_SECTION, "distance", 0)
	cfg.set_value(CONFIG_SECTION, "coins", coins)
	cfg.set_value(CONFIG_SECTION, CONFIG_RECORD_HAS_WON, has_won)
	cfg.set_value(CONFIG_SECTION, CONFIG_RECORD_LANDMARKS_BEST, landmarks_best)
	cfg.set_value(CONFIG_PROGRESSION_SECTION, "lifetime_coins", lifetime_coins)
	cfg.set_value(CONFIG_PROGRESSION_SECTION, "spent_points", spent_points)
	cfg.set_value(CONFIG_PROGRESSION_SECTION, "skill_ranks", JSON.stringify(skill_ranks))
	cfg.save(config_path)


func record_win() -> void:
	"""Record that the player has won the game: OR-merged so a win is never lost."""
	has_won = true
	_write_local()


func submit_landmarks(count: int) -> void:
	"""Record explored landmark count: max-merged."""
	landmarks_best = maxi(landmarks_best, count)
	_write_local()


# =============================================================================
# SKILL RANKS — the local-only third field (see the header)
# =============================================================================

static func merge_ranks(into: Dictionary, from: Dictionary) -> void:
	"""
	Fold `from` into `into` with a per-entry `maxi`, in place.

	The same monotone rule the scalars use, one dimension down: because there is
	no respec, a rank never falls, so the higher of two copies is always the newer
	one and ordering stops mattering — a late load, a re-read before a write and a
	retried save are all idempotent.

	Every level is type-checked because one source of `from` is parsed JSON out of
	`localStorage`, i.e. a string a player (or a broken write) can put anything in.
	A malformed hero or rank is skipped rather than rejecting the whole map: the
	rest of a player's tree is worth keeping.
	"""
	for hero: Variant in from:
		if typeof(hero) != TYPE_STRING or typeof(from[hero]) != TYPE_DICTIONARY:
			continue
		var src: Dictionary = from[hero]
		var dst: Dictionary = into.get(hero, {})
		for skill_id: Variant in src:
			if typeof(skill_id) != TYPE_STRING:
				continue
			var rank: Variant = src[skill_id]
			if typeof(rank) != TYPE_INT and typeof(rank) != TYPE_FLOAT:
				continue
			dst[skill_id] = maxi(int(dst.get(skill_id, 0)), maxi(0, int(rank)))
		into[hero] = dst


static func _parse_ranks(raw: String) -> Dictionary:
	"""
	Decode a stored rank map. Anything that is not a JSON object reads as "no
	ranks stored", which is the correct answer for a missing key, an empty string
	and a corrupt value alike — and, thanks to the merge above, costs nothing when
	the other local layer still has them.
	"""
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}


# =============================================================================
# THE TOWER'S EARNED STATE — a monotone set, merged by union
# =============================================================================
#
# WHY IT IS HERE AND NOT IN A STORE OF ITS OWN: exactly the reuse argument the
# header makes for the progression counters. It wants the same local file, the
# same read-modify-write merge and the same silent-failure rule, so a second
# store would have been this file again for one array.
#
# WHY IT IS STATIC AND INSTANCE-FREE: `tower_shell.gd` is a building, not a node
# that owns a player's records. It needs two calls — "what did I open before" and
# "remember I just opened this" — and neither wants an `HTTPRequest` pair, a
# player id or a `fetch()`. Both functions are complete round trips to the file.
#
# WHY THE UNION IS THE WHOLE MERGE RULE: a gate only ever OPENS, a stop only ever
# UNLOCKS, a stage only ever COMPLETES. The set can only grow, so the newer of
# two copies is the superset and `stored | ours` is always the right answer —
# which makes a stale copy harmless, a re-save idempotent and an interleaved
# write from a second instance a no-op rather than a rollback. It is the scalars'
# `maxi` one dimension up, and `merge_ranks`'s per-entry `maxi` one across.
#
# **A MET DEMAND GATE NEVER RE-LOCKS.** Earned progression must not become
# upkeep, so a demand gate's opened state is in this same set as an identity
# gate's, and nothing here can ever take an id back out.
#
# WHAT IS NEVER WRITTEN: anything that resets. Guards, alarms, loose objects and
# unfinished in-room puzzle configuration go nowhere near this — if it can go
# backwards it does not belong in a monotone set, and the tower rebuilds it from
# scratch every time it is streamed in.
#
# V1 IS THE LOCAL LAYER ONLY. No `/best` POST: the lobby record is a scalar
# schema whose monotone merge lives in Go (`server/best.go`), and putting a set
# on that wire needs a merge rule on the server side, which is its own bead.
# `user://` is a working store on web too (the header measured it), so the one
# ceiling is the IndexedDB flush lag — a tab closed within a frame of opening a
# gate loses that gate, and re-opening it costs one walk.

static func tower_opened_ids() -> Array[String]:
	"""
	The tower ids this profile has already earned.

	@return: A fresh sorted Array of String — the caller may keep or mutate it.

	A missing file, a missing key, a truncated value or a hand-edited mess all
	read as "nothing opened yet", which is the correct answer for every one of
	them: the tower simply comes up shut and can be opened again. Every entry is
	type-checked and the count is bounded, because this is a file a player can
	edit.
	"""
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return []
	var raw := String(cfg.get_value(CONFIG_TOWER_SECTION, CONFIG_TOWER_KEY, ""))
	if raw.is_empty():
		return []
	# `JSON.new().parse()` rather than the `JSON.parse_string()` helper the ranks
	# use, for one reason: the helper PRINTS an engine error on malformed input,
	# and a truncated or hand-edited record is an expected state on this path, not
	# an incident. The check that exercises it should not have to print an ERROR
	# line in order to pass.
	var json := JSON.new()
	if json.parse(raw) != OK:
		return []
	return _sanitize_tower_ids(json.data)


static func merge_tower_opened_ids(ids: Array) -> void:
	"""
	Fold `ids` into the stored set and save it. The only writer.

	@param ids: The ids to add. Already-stored ones cost nothing.

	READ-MODIFY-WRITE, like every other write in this file — and here it is not
	only about the other sections: it is what makes the merge a UNION rather than
	an overwrite. Without the re-read, a shell hydrated from a stale copy (or one
	built before a second instance saved) would write its own smaller set over the
	larger one on disk, and a gate the player had earned would re-lock. That is
	the bug this whole shape exists to make impossible.

	Called on a gate OPENING and nowhere else — rare and precious, so it writes
	immediately rather than batching to some later flush that a crash eats.
	Failures are ignored, for the reason `_write_local` gives.
	"""
	var merged := tower_opened_ids()
	for id: Variant in ids:
		if merged.size() >= MAX_TOWER_IDS:
			break
		if typeof(id) == TYPE_STRING and not String(id).is_empty() and not merged.has(id):
			merged.append(String(id))
	merged.sort()
	var cfg := ConfigFile.new()
	cfg.load(config_path)  # keep the records, the counters and the player id intact
	cfg.set_value(CONFIG_TOWER_SECTION, CONFIG_TOWER_KEY, JSON.stringify(merged))
	cfg.save(config_path)


static func _sanitize_tower_ids(parsed: Variant) -> Array[String]:
	"""
	Turn whatever came out of the store into a sorted, bounded Array of String.

	Anything that is not a JSON array is nothing; a non-string or empty entry is
	skipped rather than rejecting the whole set, for the same reason a malformed
	rank is skipped in `merge_ranks` — the rest of what a player earned is worth
	keeping. Duplicates collapse, because this is a SET.
	"""
	var out: Array[String] = []
	if typeof(parsed) != TYPE_ARRAY:
		return out
	for id: Variant in parsed as Array:
		if out.size() >= MAX_TOWER_IDS:
			break
		if typeof(id) == TYPE_STRING and not String(id).is_empty() and not out.has(id):
			out.append(String(id))
	out.sort()
	return out


# =============================================================================
# THE WORLD ARCHIVE — read-only-save semantics for a campaign that ended
# =============================================================================
#
# Three lines of state and one rule: while the latch is set the world is finished,
# and the only thing that clears it is starting a new one. Read at boot by
# `player_controller`, which raises the ending screen instead of handing out a run.

const OUTCOME_CAPTURED: String = "captured"
const OUTCOME_WON: String = "won"

static func world_archived() -> bool:
	"""
	Has this world's campaign ended? False for a missing, unreadable, or active file.
	"""
	return not archived_outcome().is_empty()


static func archived_outcome() -> String:
	"""
	Return the archived outcome ("captured" or "won"), or "" if no world is archived.
	Handles legacy boolean `true` as "captured".
	"""
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return ""
	var val: Variant = cfg.get_value(CONFIG_WORLD_SECTION, CONFIG_WORLD_ARCHIVED, false)
	if typeof(val) == TYPE_STRING:
		return String(val)
	elif typeof(val) == TYPE_BOOL and bool(val):
		return OUTCOME_CAPTURED
	return ""


static func has_ever_won() -> bool:
	"""
	Has the player ever won? Reads local store.
	"""
	if OS.has_feature("web"):
		return _ls_get(LS_HAS_WON) == "1" or _ls_get(LS_HAS_WON) == "true"
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return false
	return bool(cfg.get_value(CONFIG_SECTION, CONFIG_RECORD_HAS_WON, false))


static func archive_world(outcome: String = OUTCOME_CAPTURED) -> void:
	"""
	End this world with the specified outcome ("captured" or "won").

	READ-MODIFY-WRITE like every other write in this file, so the records, the
	counters, the player id and the tower's opened set survive it — an archived
	world is still the profile that earned them.
	"""
	var cfg := ConfigFile.new()
	cfg.load(config_path)
	cfg.set_value(CONFIG_WORLD_SECTION, CONFIG_WORLD_ARCHIVED, outcome)
	cfg.save(config_path)


static func new_game() -> void:
	"""
	Start a fresh world: clear the archive latch.

	`ponytail:` one save slot, so "mint a fresh save id" is "clear the flag" — see
	the section constant for the epic this leaves room for. The ceiling is that a
	new game inherits the old world's earned tower set (gates AND scars), exactly as
	it already inherits the meta-progression counters; the save-id epic is what
	separates them, and it separates all three together or none.
	"""
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return
	cfg.set_value(CONFIG_WORLD_SECTION, CONFIG_WORLD_ARCHIVED, false)
	cfg.save(config_path)


func _load_or_make_player_id() -> String:
	"""Read the stored id, or mint and store a fresh one."""
	var stored := ""
	if OS.has_feature("web"):
		stored = _ls_get(LS_PLAYER_ID)
	if stored.is_empty():
		# Also the web migration path: an id already in the ConfigFile is reused
		# rather than replaced, so a player who has one keeps their server record.
		var cfg := ConfigFile.new()
		if cfg.load(config_path) == OK:
			stored = str(cfg.get_value(CONFIG_PLAYER_SECTION, "id", ""))
	# Re-mint anything the lobby would refuse, so a corrupted store self-heals
	# instead of 400ing every request for the rest of this install's life.
	if stored.length() == PLAYER_ID_HEX_LEN and stored.is_valid_hex_number():
		return stored

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var fresh := ""
	for _i in 4:
		fresh += "%08x" % rng.randi()

	if OS.has_feature("web"):
		_ls_set(LS_PLAYER_ID, fresh)
	else:
		var cfg := ConfigFile.new()
		cfg.load(config_path)
		cfg.set_value(CONFIG_PLAYER_SECTION, "id", fresh)
		cfg.save(config_path)
	return fresh


static func _ls_get(key: String) -> String:
	"""
	Read one `localStorage` key, or "" for anything that is not a stored string.

	The whole expression is wrapped in a JS `try` because `localStorage` *throws*
	rather than returning null when a browser has site data blocked (a private
	window, or a strict privacy setting) — an unguarded read would surface as a
	JavaScriptBridge error every boot. The key goes through `JSON.stringify` so it
	is a JS string literal and cannot break out of the call.
	"""
	if not OS.has_feature("web"):
		return ""
	var js := "(function(){try{return window.localStorage.getItem(%s)||'';}catch(e){return '';}})()"
	var value: Variant = JavaScriptBridge.eval(js % JSON.stringify(key), true)
	return value as String if typeof(value) == TYPE_STRING else ""


static func _ls_set(key: String, value: String) -> void:
	"""Write one `localStorage` key. Same throw guard and same quoting as _ls_get."""
	if not OS.has_feature("web"):
		return
	var js := "try{window.localStorage.setItem(%s,%s);}catch(e){}"
	JavaScriptBridge.eval(js % [JSON.stringify(key), JSON.stringify(value)], true)


# =============================================================================
# SERVER LAYER
# =============================================================================

func _endpoint() -> String:
	"""`<lobby origin>/best?id=<player id>`, honouring the usual lobby overrides."""
	return "%s/best?id=%s" % [LobbyClient.http_url(), player_id().uri_encode()]


func _request_get() -> void:
	"""Ask the lobby for this player's stored records. Failure is silent."""
	if player_id().is_empty():
		return
	if _get_http == null:
		_get_http = HTTPRequest.new()
		_get_http.timeout = REQUEST_TIMEOUT_SEC
		add_child(_get_http)
	var err: int = _get_http.request(_endpoint())
	if err != OK:
		# ERR_BUSY is an ordinary overlap and says nothing. Anything else — above
		# all ERR_UNCONFIGURED, which is what a node not yet inside the tree
		# answers — is the silent-no-sync failure this whole feature is prone to,
		# so say it out loud rather than degrading quietly.
		if err != ERR_BUSY:
			push_warning("BestRunStore: /best GET could not start (%d)" % err)
		return
	# The window opens here and closes in the reply handler; a POST inside it is
	# what closes the baseline. See `_get_baseline_ok`.
	_get_in_flight = true
	_get_baseline_ok = true
	_get_http.request_completed.connect(_on_get_completed, CONNECT_ONE_SHOT)


func _on_get_completed(
	result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	"""
	Fold the server's records in. Anything unexpected — transport failure, a lobby
	too old to have the route, an unparseable body — is simply "no server record",
	which is the state a solo desktop player is permanently in.
	"""
	# Closed FIRST, above every early return: a GET that failed is still no longer
	# outstanding, and a POST after it races nothing.
	_get_in_flight = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return
	var data := json.data as Dictionary
	var server_coins := maxi(0, int(data.get("coins", 0)))
	# A lobby too old to know about progression simply omits these, which reads as
	# zero and raises nothing — the same forward/backward compatibility the server
	# side has for an old client's POST.
	var server_lifetime := maxi(0, int(data.get("lifetime", 0)))
	var server_spent := maxi(0, int(data.get("spent", 0)))
	# The server can be BEHIND us: a record set before this feature shipped, one
	# migrated out of the old `user://` file, or simply a run banked while the
	# lobby was unreachable. Without this the whole local history sits here until
	# the player happens to beat it, and never reaches their other devices — the
	# reply is the only moment we know what the server has, so it is where the
	# catch-up POST belongs. It converges: the next boot finds them equal.
	var server_is_behind := (
		server_coins < coins
		or server_lifetime < lifetime_coins
		or server_spent < spent_points
	)
	# Kept BEFORE the merge below, and `maxi` because a monotone field never
	# unlearns. This is the only writer — and it only writes when this reply is a
	# causally pre-submit baseline, which `_get_baseline_ok` is the whole record of.
	if _get_baseline_ok:
		server_best_coins = maxi(server_best_coins, server_coins)
	var raised := server_coins > coins
	var progression_raised := server_lifetime > lifetime_coins or server_spent > spent_points

	coins = maxi(coins, server_coins)
	distance = 0
	lifetime_coins = maxi(lifetime_coins, server_lifetime)
	spent_points = maxi(spent_points, server_spent)
	if raised or progression_raised:
		# Mirror down, so the next boot has them even with the lobby unreachable.
		_write_local()
	if raised:
		loaded.emit(0, coins)
	if progression_raised:
		progression_loaded.emit(lifetime_coins, spent_points)
	if server_is_behind:
		_request_post()


func _request_post() -> void:
	"""
	Publish the records. The lobby merges rather than overwrites, so this is
	idempotent and a dropped POST costs nothing but a round of cross-device sync —
	the next game over sends the same numbers again.
	"""
	if player_id().is_empty():
		return
	if _post_http == null:
		_post_http = HTTPRequest.new()
		_post_http.timeout = REQUEST_TIMEOUT_SEC
		add_child(_post_http)
	var body := JSON.stringify({
		"distance": 0,
		"coins": coins,
		"lifetime": lifetime_coins,
		"spent": spent_points,
	})
	var err: int = _post_http.request(
		_endpoint(), ["Content-Type: application/json"], HTTPClient.METHOD_POST, body
	)
	if err == OK and _get_in_flight:
		# This run's numbers are now on their way to a lobby whose reply to the boot
		# GET has not been read yet, so that reply may echo them back. Retire the
		# baseline — only a POST that really started can contaminate it, which is why
		# this sits under `err == OK` and not above the request.
		_get_baseline_ok = false
	# Same reasoning as the GET: the local record is already written, so a failure
	# here costs only the cross-device half — but it must not be invisible.
	if err != OK and err != ERR_BUSY:
		push_warning("BestRunStore: /best POST could not start (%d)" % err)
