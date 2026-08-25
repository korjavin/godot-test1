extends Node
class_name Progression
## Meta-progression: lifetime coins → levels → skill points, kept across runs.
##
## A `Node` named `Progression` under `Main` in `main.tscn`, in group
## `"progression"` — the `SoundManager` / `Weather` / `FaunaManager` pattern, found
## by a null-safe group lookup so any scene run without `Main` simply has no
## progression instead of erroring.
##
## THE STORED STATE IS THE RAW COUNT, NOT THE LEVEL. `level` is derived from
## `lifetime_coins` by `level_for()` every time it changes, so there is no second
## number that can drift away from the first — a stored level and a stored count
## that disagree is the classic bug in this shape, and the cheapest way not to
## have it is not to store the level.
##
## THREE RULES THE OWNER FIXED (2026-08-25), all of which the code depends on:
##
##   * Levels are LIFETIME-CUMULATIVE. Coins are never deducted, so
##     `lifetime_coins` only ever rises — which is what lets every layer under
##     this one (local file, localStorage, the lobby's record) use a plain
##     monotone `max` merge and stop worrying about ordering, retries and stale
##     writes entirely.
##   * Spending a skill point raises `spent_points`; it does NOT lower
##     `lifetime_coins`. Nothing spends yet (that is the skill-tree bead,
##     godot-test1-20z.3) — the counter is stored now so that bead touches only
##     this file.
##   * In multiplayer the count is PERSONAL — see the hook note below.
##
## WHERE THE COUNT COMES FROM, AND WHY IT IS NOT THE ROOM'S BANK. The single hook
## is `player_controller.collect_coin()`, i.e. THIS player physically touching a
## coin, at its PRE-STREAK value (a plain coin is 1, a gem is 10). The streak
## multiplier is a SCORE multiplier — it multiplies what the run is worth, not how
## many coins were picked up — and a room's shared bank (mp phases 4–5) is a
## run-scoped display total summed across peers. Neither belongs here. `ponytail:`
## the ceiling that follows is that in a multiplayer room a coin won through the
## claim protocol pays through `player_controller.bank_awarded()` instead, which
## receives only the already-multiplied total, so those pickups currently credit
## no lifetime coins; crediting them needs the claim's base value threaded into
## `bank_awarded()` from `mp_manager.gd`, which this bead deliberately did not
## touch (a parallel branch owns that file).
##
## PERSISTENCE IS `BestRunStore`, NOT A SECOND STORE. It already does exactly this
## job for the best-run records — a `ConfigFile` on desktop, `localStorage` on web,
## and `GET`/`POST <lobby>/best?id=<player id>` keyed by a persistent player id,
## with every server failure silent and non-fatal because the local layer has
## already answered. The progression counters ride the same record (see
## `server/best.go`), so this file gets the whole web-storage-eviction fix from
## godot-test1-6ah for free and nothing new appears on the wire.
##
## Two `BestRunStore` instances therefore exist in a running game — the player's,
## for records, and this one, for progression — and that is safe rather than
## sloppy: every field merges upward only, `submit*()` re-reads the local store
## before it writes, and the two touch disjoint fields anyway. The alternative was
## reaching across nodes for the player's instance, which would have made this
## file's correctness depend on `_ready()` ordering.

# =============================================================================
# CONFIGURATION
# =============================================================================

## Level N is reached at `LEVEL_COIN_STEP * N * (N + 1) / 2` lifetime coins, i.e.
## 50 / 150 / 300 / 500 / 750 / 1050 … — each level costs `LEVEL_COIN_STEP` more
## than the one before it. Triangular rather than geometric on purpose: geometric
## curves stop rewarding a player who is still playing well within an hour, while
## this one keeps the gap between levels legible (a level is always a countable
## number of coins away) and still slows down forever.
const LEVEL_COIN_STEP: int = 50

## Skill points granted per level. One, deliberately — the level IS the point.
const POINTS_PER_LEVEL: int = 1

## How long the centred "LEVEL N" flash stays up.
const LEVEL_UP_MESSAGE_DURATION: float = 2.2

## Test affordance, exposed nowhere in the UI — the same shape as
## `mp_manager.heartbeat_enabled`. With it off no `BestRunStore` is created, so
## the level maths can be driven headless without reading, rewriting or POSTing
## the developer's REAL record (`scripts/progression_selfcheck.gd` sets it; the
## persistence round trip is covered end to end by `scripts/best_run_e2e.gd`
## against a local lobby instead).
@export var persistence_enabled: bool = true

# =============================================================================
# SIGNALS
# =============================================================================

## Emitted when the level rises. `gained` is how many levels at once — one gem at
## a high streak cannot do it (lifetime counts the pre-streak value), but a
## treasure chest's burst near a threshold can, and so can a server reply that
## raises the count from another device.
signal levelled_up(level: int, gained: int)

# =============================================================================
# STATE
# =============================================================================

## Cumulative coins picked up across every run ever. The one authoritative number.
var lifetime_coins: int = 0

## Derived from `lifetime_coins`; never stored, never assigned from outside.
var level: int = 0

## Skill points already spent. 0 until the skill-tree bead exists.
var spent_points: int = 0

## Where the counters are kept. See the header for why this is our own instance.
var store: BestRunStore = null

var _message_timer: float = 0.0


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	add_to_group("progression")
	set_process(false)  # nothing to do until a level-up puts a message up

	if not persistence_enabled:
		return
	store = BestRunStore.new()
	store.name = "ProgressionStore"
	add_child(store)
	# `fetch()` answers out of the local store synchronously and fires the signal
	# again later if the lobby knows better — a second device, or this device
	# after the browser threw its site storage away. Folding both in with `maxi`
	# is what makes the ordering irrelevant.
	store.progression_loaded.connect(_on_progression_loaded)
	store.fetch()


func _process(delta: float) -> void:
	_message_timer -= delta
	if _message_timer <= 0.0:
		_set_message("")
		set_process(false)


# =============================================================================
# PUBLIC API
# =============================================================================

func add_coins(value: int) -> void:
	"""
	Credit `value` lifetime coins — one pickup's PRE-STREAK worth. Called from
	`player_controller.collect_coin()` through a null-safe group lookup.

	Negative and zero values are ignored rather than trusted: lifetime only ever
	rises (see the header), and every layer below assumes it.
	"""
	if value <= 0:
		return
	lifetime_coins += value
	var new_level := level_for(lifetime_coins)
	if new_level <= level:
		return
	var gained := new_level - level
	level = new_level
	_announce_level_up(gained)
	# Save on the level-up itself, not only at game over: a level is the thing a
	# player would be angry to lose to a closed tab.
	save()
	levelled_up.emit(level, gained)


func unspent_points() -> int:
	"""Skill points available to spend. Nothing spends them yet (bead 20z.3)."""
	return maxi(0, level * POINTS_PER_LEVEL - spent_points)


func coins_to_next_level() -> int:
	"""Lifetime coins still needed for the next level — for HUD/UI use."""
	return maxi(0, level_coin_threshold(level + 1) - lifetime_coins)


func save() -> void:
	"""
	Persist the counters (local layer first, then the lobby). Called on a level-up
	and from `player_controller._trigger_game_over()`, so coins banked below the
	next threshold survive the run that earned them.
	"""
	if store:
		store.submit_progression(lifetime_coins, spent_points)


static func level_coin_threshold(target_level: int) -> int:
	"""
	Lifetime coins needed to REACH `target_level`. Level 0 is free; level N costs
	`LEVEL_COIN_STEP * N * (N + 1) / 2` in total.
	"""
	if target_level <= 0:
		return 0
	return LEVEL_COIN_STEP * target_level * (target_level + 1) / 2


static func level_for(coins: int) -> int:
	"""
	The level `coins` lifetime coins buys. A plain loop rather than the closed-form
	inverse of the triangular number: it is exact by construction (no float
	`sqrt` to round the wrong way at a threshold, which is precisely where this
	function is read), it runs a handful of iterations for any reachable count,
	and it is obviously the same rule as `level_coin_threshold` to anyone reading
	both. It runs only when the count changes, never per frame.
	"""
	var result := 0
	while coins >= level_coin_threshold(result + 1):
		result += 1
	return result


# =============================================================================
# INTERNALS
# =============================================================================

func _on_progression_loaded(loaded_lifetime: int, loaded_spent: int) -> void:
	"""
	Fold in whatever the store now knows. May fire twice (local, then the server),
	and only ever upward — so this can never take a level away, and a late reply
	that raises the count silently levels the player up on the spot.
	"""
	lifetime_coins = maxi(lifetime_coins, loaded_lifetime)
	spent_points = maxi(spent_points, loaded_spent)
	var new_level := level_for(lifetime_coins)
	if new_level > level:
		var gained := new_level - level
		level = new_level
		# Deliberately silent at boot (`_message_timer` untouched, no sound): the
		# local read happens in `_ready()`, and flashing "LEVEL 7" at every player
		# every time they start the game reads as a bug.
		levelled_up.emit(level, gained)


func _announce_level_up(gained: int) -> void:
	"""Centred flash + a one-shot through the sound manager. Both are optional."""
	# tr() on the FORMAT STRING, never the formatted result — see CLAUDE.md's
	# localization RULE 2.
	_set_message(tr("LEVEL %d\n+%d skill point") % [level, gained * POINTS_PER_LEVEL])
	_message_timer = LEVEL_UP_MESSAGE_DURATION
	set_process(true)
	var sm := get_tree().get_first_node_in_group("sound_manager")
	if sm and sm.has_method("play_level_up"):
		sm.play_level_up()


func _set_message(text: String) -> void:
	"""
	Drive the centred level-up label, found by group like the respawn countdown.
	Its own node rather than a share of `RespawnLabel`, because the countdown
	rewrites that label every frame it is up and would eat the message whole.
	"""
	var label := get_tree().get_first_node_in_group("level_up_label")
	if label == null:
		return
	label.text = text
	label.visible = not text.is_empty()
