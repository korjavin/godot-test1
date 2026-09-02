extends Area3D
## The open-trigger of one deterministic treasure chest.
##
## The chest's WOOD AND BRASS ARE NOT HERE — they are plain create_box entries in
## the generating chunk's single block MultiMesh and single BlockCollision body
## (see spawn_chest_in_chunk in endless_terrain.gd). This node is the chest's ONE
## non-batched cost: a trigger volume with no mesh and no material, so a chest
## adds ZERO draw calls. At ~1 chest per 13 chunks that is a handful of Area3Ds
## alive at once.
##
## HOW THE REWARD IS PAID — read this before changing it. The chest does NOT
## spawn coin nodes and does NOT call collect_coin(N) once. It calls
## `player.collect_coin(1)` N times, spread over CHEST_BURST_DURATION, because
## the coin economy counts PICKUPS, not value:
##   - the streak multiplier (player_controller.get_streak_multiplier) steps every
##     STREAK_COINS_PER_STEP *pickups*, so one collect_coin(12) is one link in the
##     chain and a chest would never light the streak up at all;
##   - each pickup refreshes the STREAK_WINDOW (2.5 s), and the whole burst fits
##     inside one window, so a chest reliably pushes the multiplier up a step;
##   - the HUD and the coin blip all come along for free,
##     because they already hang off collect_coin.
## Staggering is therefore mechanical, not decorative: it is what makes a chest
## read (and score) as a coin *shower* rather than a single fat pickup.
##
## IN A MULTIPLAYER ROOM the payout is arbitrated instead: the chest claims its
## whole burst as ONE pickup event and the master prices it (see `_room_claimed`),
## so the burst below runs purely as animation. A chest another peer already
## emptied IS swept out of the world now: every chest joins group `CHEST_GROUP`
## and `mp_manager._absorb_collected()` walks it beside the `"coin"` group,
## calling `consume_silently()`. That covers both halves of the old gap — a chest
## emptied before we joined (the join snapshot's `ids` carry its id) and one a
## teammate empties while we stand next to it (the `cnf` confirm carries it).
##
## Spawned exactly like ability_effect.gd — a bare node, `set_script`, `add_child`,
## then `setup()` — so there is no .tscn to keep in step with this file.
##
## ponytail: the burst is driven by this node's own `_process`, not by a spawned
## one-shot helper. The chest is already a node parented to the chunk and already
## lives exactly as long as the reward needs to be paid; a second node would be a
## second thing to keep alive for nothing.

## Radius of the "you touched the chest" sphere, metres. Comfortably bigger than
## the chest box itself so it opens on a brush past rather than needing a nudge.
const TRIGGER_RADIUS: float = 2.0

## The pop when the lid comes off: the same self-freeing wave every ability and
## every coin pickup uses. It is the ONLY visual the opening gets — the chest
## geometry itself is baked into the chunk MultiMesh and cannot be animated per
## instance. ponytail: a real lid swing needs the lid lifted out of the MultiMesh
## into its own MeshInstance3D, i.e. a draw call per chest; not worth it for a
## quarter-second of motion.
const ABILITY_EFFECT := preload("res://scripts/ability_effect.gd")
const OPEN_FLASH_COLOR: Color = Color(1.0, 0.82, 0.35, 0.55)
const OPEN_FLASH_RADIUS: float = 2.4
const OPEN_FLASH_LIFETIME: float = 0.35

## The ONE sphere shape every chest trigger that will ever spawn shares. Same
## static lazy-getter discipline as ability_effect._get_shared_sphere_mesh() and
## endless_terrain._get_shared_unit_box_mesh(): every chest wants the identical
## radius, and chests are rebuilt on every chunk reload.
static var _shared_shape: SphereShape3D = null

## Guard so a chest can only ever be opened once (the deferred `monitoring` write
## below does not take effect until the end of the physics step, so a second body
## in the same step could otherwise re-enter).
var _opened: bool = false

## Burst state: how many single-coin awards are still owed, the gap between them,
## and the countdown to the next one.
var _remaining: int = 0
var _interval: float = 0.0
var _timer: float = 0.0

## The player that opened us. Held only for the length of the burst and always
## re-checked with is_instance_valid — a respawn or a restart can free things
## underneath a running effect.
var _player: Node = null

## MULTIPLAYER. `_id` is this chest's stable id — the SAME scheme coins use
## (Coin.id_at on the position), because a chest is deterministic in exactly the
## same way: every peer in a room has its own copy of it in the same place, so the
## position alone names it and no id had to be threaded out of the terrain.
##
## `_room_claimed` is set when the room's claim machinery took the payout over. In
## that case the master has ALREADY computed the whole award (the chest claims its
## entire burst as ONE claim, with the coin count as the pickup count, so the
## room's streak steps exactly as it would solo) and paid it through the confirm.
## The chest's job in a room is then purely the animation: the burst still runs, it
## still blips, it simply never calls collect_coin — awarding again would pay the
## room twice for one chest, which is the whole bug claims exist to fix.
const COIN_SCRIPT := preload("res://scripts/coin.gd")

## The group `mp_manager._absorb_collected()` sweeps for chests, beside the
## `"coin"` group it already sweeps for coins. Chests are deliberately NOT in
## `"coin"`: the crocodile LOD manager gates that group's `set_process` on
## distance, and a chest's `_process` is its payout burst — a chest opened 31 m
## from the local player would freeze mid-shower and never free itself.
const CHEST_GROUP: StringName = &"chest"

var _id: int = 0
var _room_claimed: bool = false


static func _get_shared_shape() -> SphereShape3D:
	if _shared_shape == null:
		_shared_shape = SphereShape3D.new()
		_shared_shape.radius = TRIGGER_RADIUS
	return _shared_shape


func setup(coin_count: int, burst_duration: float) -> void:
	"""
	Build the trigger and arm the reward. Safe to call right after add_child():
	everything is created here rather than in _ready, so the node is fully formed
	immediately (same contract as ability_effect.setup).

	@param coin_count: How many single-coin awards this chest pays out. Drawn from
	                   the chest's own seeded RNG by the terrain, so it is
	                   deterministic within a run like everything else about the
	                   chest.
	@param burst_duration: Seconds the payout is spread over.
	"""
	_remaining = maxi(1, coin_count)
	# Spread across the window rather than dividing into it: the first coin is paid
	# on contact and the rest follow, so a 1-coin chest degenerates gracefully.
	_interval = maxf(0.01, burst_duration) / float(_remaining)
	_timer = _interval

	# Same collision setup as coin.tscn's Area3D: on NO layer (nothing needs to
	# detect a chest) and masking layer 1 (the player). Crocodiles are layer 2 and
	# rideable fauna layer 3, so neither can ever trip a chest open.
	collision_layer = 0
	collision_mask = 1
	monitorable = false

	var shape := CollisionShape3D.new()
	shape.shape = _get_shared_shape()
	add_child(shape)

	# Idle until opened — a closed chest costs one physics-server area and no
	# script dispatch at all.
	set_process(false)

	# MULTIPLAYER: latch the id and check whether the room already emptied this
	# chest. Latched HERE rather than in a _ready(), because the terrain sets our
	# position BEFORE add_child and calls setup() straight after it — so
	# global_position is already final, and unlike a coin a chest never moves at
	# all, so there is no bob for the id to drift with. One failed group lookup per
	# chest at spawn, never per frame, exactly like coin.gd's.
	_id = COIN_SCRIPT.id_at(global_position)
	var mp := get_tree().get_first_node_in_group("mp")
	if mp and mp.has_method("is_coin_collected") and mp.is_coin_collected(_id):
		queue_free()
		return

	# Joined only once the chest is known to be UNSPENT: a chest that just freed
	# itself has nothing for the sweep to do, and the group is exactly "chests the
	# room might still have to empty".
	add_to_group(CHEST_GROUP)

	body_entered.connect(_on_body_entered)


func chest_id() -> int:
	"""
	This chest's stable id — a COIN id, because a chest is arbitrated as a pickup
	like any other (`Coin.id_at` on its position). Named for the sweep in
	`mp_manager._absorb_collected()`, which reads it off the `CHEST_GROUP` node the
	same way it reads `coin_id()` off a coin.
	"""
	return _id


func consume_silently() -> void:
	"""
	The room already emptied this chest: take it out of the world with no shower,
	no blips and no award.

	A CHEST MID-BURST IS LEFT ALONE, and that is why this is a method rather than
	a `queue_free()` at the call site. `_opened` means we are paying out an award
	the master already priced through `claim_pickup()`; cutting it short would
	swallow the shower the player is watching and — offline or on an unclaimed
	path — the coins it is still owed. The burst frees the node itself when it
	ends, and the id is already in the room's collected set either way.
	"""
	if _opened:
		return
	_opened = true
	queue_free()


func _on_body_entered(body: Node) -> void:
	if _opened:
		return
	if not body.is_in_group("player"):
		return
	_opened = true
	_player = body

	# MULTIPLAYER: claim the WHOLE burst as one pickup event, `_remaining` pickups
	# of value 1 — one claim, not one per coin, so a chest is arbitrated in a
	# single round trip and the master advances the room's streak the same number
	# of steps the burst would have. False offline, and then nothing below changes.
	var mp := get_tree().get_first_node_in_group("mp")
	_room_claimed = mp != null and mp.has_method("claim_pickup") \
			and mp.claim_pickup(_id, _remaining, 1)
	if not _room_claimed and mp and mp.has_method("report_coin_collected"):
		# The room could not arbitrate (no mesh yet, or offline), so we pay the
		# burst ourselves below — which means the room has to be told this chest
		# is empty, exactly as coin.gd does on its own unclaimed path. ONLY on
		# this path: on the claimed one `_resolve_claim` is the single writer of
		# the collected set. Without it `setup()`'s `is_coin_collected` check —
		# the chest's ONLY de-duplication, since nothing sweeps chests the way
		# `_absorb_collected` sweeps the "coin" group — misses on a chunk reload
		# or a later joiner, and the shared bank pays a second CHEST_COINS_MIN..MAX burst.
		mp.report_coin_collected(_id)

	# Stop listening. MUST be deferred: Godot blocks direct property writes to a
	# monitoring Area3D from inside its own body_entered signal ("Function blocked
	# during in/out signal") — the same reason coin.gd reaches for queue_free
	# rather than switching itself off.
	set_deferred("monitoring", false)

	# The lid pop, parented to the CHUNK (our parent) rather than to us: we free
	# ourselves when the burst ends and a child effect would die with us. Same
	# rule, same reason, as coin.gd's pickup sparkle.
	var fx_parent := get_parent()
	if fx_parent:
		var fx := MeshInstance3D.new()
		fx.set_script(ABILITY_EFFECT)
		fx_parent.add_child(fx)
		fx.global_position = global_position
		fx.setup(OPEN_FLASH_COLOR, OPEN_FLASH_RADIUS, OPEN_FLASH_LIFETIME)

	# First coin lands on contact; _process pays out the rest.
	_award_one()
	set_process(true)


func _process(delta: float) -> void:
	_timer -= delta
	# A `while`, not an `if`: at CHEST_COINS_MAX over CHEST_BURST_DURATION the gap
	# is ~53 ms, which a frame hitch (or a browser tab regaining focus) can easily
	# overrun — paying only one coin per frame would silently stretch the burst
	# past the streak window on a slow frame.
	while _remaining > 0 and _timer <= 0.0:
		_timer += _interval
		_award_one()
	if _remaining <= 0:
		set_process(false)
		queue_free()


func _award_one() -> void:
	"""
	One ordinary coin, through the ordinary path — the whole point of the burst.

	IN A ROOM the award is skipped entirely (see `_room_claimed`): the master
	already priced the whole chest and paid the winner through the confirm, so all
	that is left here is the shower — the stagger, the blips and the flash.
	"""
	_remaining -= 1
	if not _room_claimed and is_instance_valid(_player) and _player.has_method("collect_coin"):
		_player.collect_coin(1)

	# The pickup blip, through the manager's own player pool (we free ourselves at
	# the end of the burst, so a sound attached to this node would be cut off).
	# Null-safe group lookup + has_method, so a scene without SoundManager stays
	# silent instead of erroring, and the manager's own web unlock gate still
	# applies — play_coin early-returns until the first user gesture.
	var sm := get_tree().get_first_node_in_group("sound_manager")
	if sm and sm.has_method("play_coin"):
		sm.play_coin()
