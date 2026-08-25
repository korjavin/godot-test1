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
##     `lifetime_coins`. See "THE SKILL TREES" below for what spends them.
##   * In multiplayer the count is PERSONAL — see the hook note below.
##
## THE SKILL TREES (bead godot-test1-20z.3) live in this file too, as ONE const
## dict of plain dicts — no class hierarchy, no custom `Resource`, per house
## style. Three rules hold the whole feature up:
##
##   * **The hard caps live in `skill_mult()`, not in the tree data.** The epic's
##     balance guardrails (−40% cooldown, +20% run speed, and *never* walk speed)
##     are clamps inside the getter, so retuning `per_rank` or adding a rank can
##     shift the curve but cannot breach a contract. `player_controller.gd` reads
##     these through one null-safe helper at the EXISTING sites — the consts stay
##     consts and the skills multiply at the point of use.
##   * **Ranks only ever go up.** There is no respec in v1, which is what lets the
##     per-hero rank map merge with the same plain `maxi` every other layer under
##     this one uses, and what keeps `spent_points` — the one number that reaches
##     the server — monotone. See `BestRunStore` for the storage shape and for why
##     the ranks themselves stay on the LOCAL layer.
##   * **A spend is a rank plus `spent_points`, never a coin deduction.**
##     `unspent_points()` was already `level - spent_points`; spending is the only
##     thing that was missing.
##
## WHERE THE COUNT COMES FROM, AND WHY IT IS NOT THE ROOM'S BANK. There are TWO
## hooks and they credit the same thing: `player_controller.collect_coin()`, i.e.
## THIS player physically touching a coin, at its PRE-STREAK value (a plain coin
## is 1, a gem is 10) — and, in a multiplayer room, `bank_awarded()`, which pays a
## pickup won through the claim protocol at its PRE-MULTIPLIER value (the
## confirm's `b` field, bead godot-test1-42n). The streak multiplier is a SCORE
## multiplier — it multiplies what the run is worth, not how many coins were
## picked up — and a room's shared bank (mp phases 4–5) is a run-scoped display
## total summed across peers. Neither belongs here, which is why both hooks take
## the base figure and why the self-check measures them through the real
## functions rather than trusting the call site.
##
## So a player in a room banks exactly the lifetime coins they would have banked
## solo. Before 42n `bank_awarded()` had no hook at all, and since a claim is won
## for every coin a peer reaches first, that peer levelled almost not at all.
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

# =============================================================================
# SKILL TREE DATA
# =============================================================================

## HARD CAP: the most a hero's ability cooldowns may ever be shortened, as a
## multiplier (0.60 = −40%). An epic-level balance contract, so it is enforced in
## `skill_mult()` rather than left implicit in the rank arithmetic — retune
## `per_rank` or add a rank and the cap still holds.
const COOLDOWN_MULT_MIN: float = 0.60

## HARD CAP: the most the run/duck gaits may ever be sped up (+20%). Same
## reasoning as `COOLDOWN_MULT_MIN`. Faster running only ever WIDENS the existing
## escape hatch (`MAX_CHASE_SPEED` 8.5 < the slowest run 9.0), which is why a cap
## on the upside is a balance knob rather than a correctness one — and why
## **walk speed has no skill at all**: the catchable-walk contract
## (`BASE_CHASE_SPEED` 5.5 > `WALK_SPEED` 5.0) is already marginal, with Primm
## walking at 5.75, so no skill may touch it. There is deliberately no
## `WALK_SPEED` effect id anywhere in `SKILL_TREES`.
const RUN_SPEED_MULT_MAX: float = 1.20

## Every hero's tree: hero name → array of node defs, each a plain dict
##
##     { id, name, desc, branch, cost, max_ranks, prereq, effect, per_rank }
##
## `branch` is purely how the UI columns itself (`skill_tree_ui.gd` groups by it,
## in first-seen order), `prereq` is another node's `id` in the same tree or ""
## for a root, and `effect` is the string `skill_mult()` / `skill_bonus()` sum
## ranks under. `name` and `desc` are ENGLISH SOURCE STRINGS and therefore also
## their own translation keys — see CLAUDE.md's localization RULE 1, and
## `assets/translations/ui.csv` for the German.
##
## Deliberately SMALL: two branches of two-to-three nodes each. Every hero shares
## the same "Focus" branch (cooldown ×2 + the movement node) so the shape is
## learnable, and differs only in the power branch, which is the hero's own
## signature ability turned up. Nothing here grants a new verb — that is the
## active-skills bead (godot-test1-20z.4).
const SKILL_TREES: Dictionary = {
	"windman": [
		{
			"id": "cd1", "name": "Quick Recovery", "branch": "Focus",
			"desc": "Ability cooldown −10% per rank.",
			"cost": 1, "max_ranks": 3, "prereq": "",
			"effect": "cooldown", "per_rank": 0.10,
		},
		{
			"id": "cd2", "name": "Second Wind", "branch": "Focus",
			"desc": "A further −10% ability cooldown.",
			"cost": 1, "max_ranks": 1, "prereq": "cd1",
			"effect": "cooldown", "per_rank": 0.10,
		},
		{
			"id": "fleet", "name": "Fleet Foot", "branch": "Focus",
			"desc": "Running and ducking +7% per rank. Walking is never affected.",
			"cost": 1, "max_ranks": 2, "prereq": "",
			"effect": "run_speed", "per_rank": 0.07,
		},
		{
			"id": "gale", "name": "Long Gale", "branch": "Air Rush",
			"desc": "Air Rush lasts +15% longer per rank.",
			"cost": 1, "max_ranks": 2, "prereq": "",
			"effect": "windman_boost", "per_rank": 0.15,
		},
		{
			"id": "updraft", "name": "Updraft", "branch": "Air Rush",
			"desc": "Air Rush launches 20% higher.",
			"cost": 1, "max_ranks": 1, "prereq": "gale",
			"effect": "windman_lift", "per_rank": 0.20,
		},
	],
	"primm": [
		{
			"id": "cd1", "name": "Quick Recovery", "branch": "Focus",
			"desc": "Ability cooldown −10% per rank.",
			"cost": 1, "max_ranks": 3, "prereq": "",
			"effect": "cooldown", "per_rank": 0.10,
		},
		{
			"id": "cd2", "name": "Second Wind", "branch": "Focus",
			"desc": "A further −10% ability cooldown.",
			"cost": 1, "max_ranks": 1, "prereq": "cd1",
			"effect": "cooldown", "per_rank": 0.10,
		},
		{
			"id": "fleet", "name": "Fleet Foot", "branch": "Focus",
			"desc": "Running and ducking +7% per rank. Walking is never affected.",
			"cost": 1, "max_ranks": 2, "prereq": "",
			"effect": "run_speed", "per_rank": 0.07,
		},
		{
			"id": "reach", "name": "Long Step", "branch": "Phase Step",
			"desc": "Phase Step reaches +20% further per rank.",
			"cost": 1, "max_ranks": 2, "prereq": "",
			"effect": "primm_blink", "per_rank": 0.20,
		},
		{
			"id": "echo", "name": "Phase Echo", "branch": "Phase Step",
			"desc": "Blinking through a wall refunds 1 second of cooldown.",
			"cost": 1, "max_ranks": 1, "prereq": "reach",
			"effect": "primm_refund", "per_rank": 1.0,
		},
	],
	"teibi": [
		{
			"id": "cd1", "name": "Quick Recovery", "branch": "Focus",
			"desc": "Ability cooldown −10% per rank.",
			"cost": 1, "max_ranks": 3, "prereq": "",
			"effect": "cooldown", "per_rank": 0.10,
		},
		{
			"id": "cd2", "name": "Second Wind", "branch": "Focus",
			"desc": "A further −10% ability cooldown.",
			"cost": 1, "max_ranks": 1, "prereq": "cd1",
			"effect": "cooldown", "per_rank": 0.10,
		},
		{
			"id": "fleet", "name": "Fleet Foot", "branch": "Focus",
			"desc": "Running and ducking +7% per rank. Walking is never affected.",
			"cost": 1, "max_ranks": 2, "prereq": "",
			"effect": "run_speed", "per_rank": 0.07,
		},
		{
			"id": "hold", "name": "Held Form", "branch": "Resize",
			"desc": "Small and giant forms last +25% longer per rank.",
			"cost": 1, "max_ranks": 2, "prereq": "",
			"effect": "teibi_form", "per_rank": 0.25,
		},
		{
			"id": "scurry", "name": "Scurry", "branch": "Resize",
			"desc": "Small form runs and ducks 10% faster.",
			"cost": 1, "max_ranks": 1, "prereq": "hold",
			"effect": "teibi_small_speed", "per_rank": 0.10,
		},
	],
	"phoboman": [
		{
			"id": "cd1", "name": "Quick Recovery", "branch": "Focus",
			"desc": "Ability cooldown −10% per rank.",
			"cost": 1, "max_ranks": 3, "prereq": "",
			"effect": "cooldown", "per_rank": 0.10,
		},
		{
			"id": "cd2", "name": "Second Wind", "branch": "Focus",
			"desc": "A further −10% ability cooldown.",
			"cost": 1, "max_ranks": 1, "prereq": "cd1",
			"effect": "cooldown", "per_rank": 0.10,
		},
		{
			"id": "fleet", "name": "Fleet Foot", "branch": "Focus",
			"desc": "Running and ducking +7% per rank. Walking is never affected.",
			"cost": 1, "max_ranks": 2, "prereq": "",
			"effect": "run_speed", "per_rank": 0.07,
		},
		{
			"id": "reek", "name": "Lingering Reek", "branch": "Stink Wave",
			"desc": "Crocodiles flee +20% longer per rank.",
			"cost": 1, "max_ranks": 2, "prereq": "",
			"effect": "phoboman_flee", "per_rank": 0.20,
		},
		{
			"id": "billow", "name": "Billowing Cloud", "branch": "Stink Wave",
			"desc": "The stink wave spreads 25% wider.",
			"cost": 1, "max_ranks": 1, "prereq": "reek",
			"effect": "phoboman_radius", "per_rank": 0.25,
		},
	],
}

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

## Skill points already spent. Raised by `spend()`, never lowered (no respec in
## v1), which is what keeps the one number that reaches the server monotone.
var spent_points: int = 0

## Ranks bought, as `hero name → { skill id: rank }`. Absent keys mean rank 0, so
## a fresh profile is an empty dict rather than a pre-filled skeleton. Persisted
## through `BestRunStore`'s LOCAL layer only — see its header.
var skill_ranks: Dictionary = {}

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
	"""
	Skill points available to spend — `spend()` is the only thing that consumes
	them.

	The `maxi(0, …)` is load-bearing rather than defensive: a server reply may
	legitimately carry a HIGHER `spent_points` than this device's ranks account
	for (the same profile, spent on a device whose local rank map never reached
	here). Clamping means that shows up as "fewer points to spend", never as a
	negative count and never as a free rank — the safe direction to be wrong in.
	"""
	return maxi(0, level * POINTS_PER_LEVEL - spent_points)


# =============================================================================
# SKILL TREE — QUERIES (pure, allocation-free enough to call from a UI tick)
# =============================================================================

static func skills_for(hero: String) -> Array:
	"""Every node def in `hero`'s tree, in declaration order. [] for an unknown
	hero, so a scene with a character this file has never heard of renders an
	empty tree instead of erroring."""
	return SKILL_TREES.get(hero, [])


static func skill_def(hero: String, skill_id: String) -> Dictionary:
	"""One node def, or {} when the hero or the id is unknown."""
	for def: Dictionary in skills_for(hero):
		if String(def["id"]) == skill_id:
			return def
	return {}


func rank_of(hero: String, skill_id: String) -> int:
	"""Ranks bought in one node. 0 for anything never bought."""
	var per_hero: Dictionary = skill_ranks.get(hero, {})
	return int(per_hero.get(skill_id, 0))


func is_unlocked(hero: String, skill_id: String) -> bool:
	"""
	True when this node's prerequisite is satisfied. A root node ("" prereq) is
	always unlocked; a child needs ONE rank in its parent, not a maxed parent —
	the tree is five nodes deep in total, so demanding a full parent would make
	the second half of every branch unreachable until level 4.
	"""
	var def := skill_def(hero, skill_id)
	if def.is_empty():
		return false
	var prereq := String(def.get("prereq", ""))
	return prereq.is_empty() or rank_of(hero, prereq) >= 1


func can_spend(hero: String, skill_id: String) -> bool:
	"""True when a point can be put into this node right now."""
	var def := skill_def(hero, skill_id)
	if def.is_empty():
		return false
	if rank_of(hero, skill_id) >= int(def.get("max_ranks", 1)):
		return false
	if not is_unlocked(hero, skill_id):
		return false
	return unspent_points() >= int(def.get("cost", 1))


func skill_mult(hero: String, effect: String) -> float:
	"""
	THE getter every effect site reads, and the single home of the balance caps.
	Returns a MULTIPLIER to apply to an existing constant at its point of use:

	  * `"cooldown"`  → 1.0 down to `COOLDOWN_MULT_MIN` (−40% hard cap).
	  * `"run_speed"` → 1.0 up to `RUN_SPEED_MULT_MAX` (+20% hard cap).
	  * anything else → 1.0 + the summed per-rank bonus, uncapped, because those
	    effects are bounded by the ability they scale (Primm's blink scan already
	    stops at `PRIMM_BLINK_MAX_DISTANCE`, a longer Air Rush still ends).

	1.0 for an unknown hero or effect, so a caller never has to branch and the
	whole feature is inert for a character with no tree.
	"""
	var total := skill_bonus(hero, effect)
	match effect:
		"cooldown":
			return maxf(1.0 - total, COOLDOWN_MULT_MIN)
		"run_speed":
			return minf(1.0 + total, RUN_SPEED_MULT_MAX)
		_:
			return 1.0 + total


func skill_bonus(hero: String, effect: String) -> float:
	"""
	The raw summed bonus for `effect` — `per_rank * rank`, over every node in the
	hero's tree carrying that effect id. 0.0 when nothing is ranked.

	Exposed beside `skill_mult()` for the one effect that is a FLAT amount rather
	than a factor: Primm's Phase Echo refunds whole seconds of cooldown, which no
	multiplier expresses.
	"""
	var total := 0.0
	for def: Dictionary in skills_for(hero):
		if String(def.get("effect", "")) != effect:
			continue
		total += float(def.get("per_rank", 0.0)) * float(rank_of(hero, String(def["id"])))
	return total


# =============================================================================
# SKILL TREE — SPENDING
# =============================================================================

func spend(hero: String, skill_id: String) -> bool:
	"""
	Put one point into a node. Returns false (and changes nothing) when the node
	is maxed, locked, unknown, or unaffordable — so a UI can call this on every
	press and let the answer be the validation.

	Coins are NOT deducted; `spent_points` rises instead (owner rule, see the
	header), and the save is immediate for the same reason a level-up saves: a
	spent point is a thing a player would be angry to lose to a closed tab.
	"""
	if not can_spend(hero, skill_id):
		return false
	var def := skill_def(hero, skill_id)
	var per_hero: Dictionary = skill_ranks.get(hero, {})
	per_hero[skill_id] = int(per_hero.get(skill_id, 0)) + 1
	skill_ranks[hero] = per_hero
	spent_points += int(def.get("cost", 1))
	save()
	return true


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
		store.submit_progression(lifetime_coins, spent_points, skill_ranks)


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
	# The ranks ride the SAME store but not the same signal: `progression_loaded`
	# carries the two scalars the server also knows about, and adding a third
	# argument would break every existing connection (a GDScript signal cannot
	# grow an optional parameter). The store has already merged the local ranks
	# into itself by the time it emits, so reading them off it here is both
	# simpler and correctly ordered. Merged rather than assigned, for the same
	# monotone reason as the two lines above.
	if store:
		BestRunStore.merge_ranks(skill_ranks, store.skill_ranks)
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
