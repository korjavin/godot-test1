extends Area3D
## Collectible Golden Coin
##
## A coin spins in place (and bobs gently so the mid-air ones catch the eye).
## When the player walks or jumps into it, it bumps the player's coin counter and
## removes itself.
##
## EDUCATIONAL NOTES:
## - Collection is event-driven: an Area3D fires `body_entered` when a physics
##   body overlaps it. We only react to bodies in the "player" group.
## - Coins are spawned by the endless terrain and parented to their chunk, so
##   they unload automatically when the chunk does (same as blocks/crocodiles).

# ============================================================================
# CONSTANTS
# ============================================================================

## How fast the coin spins around the vertical axis (radians/sec)
const SPIN_SPEED: float = 3.0

## Gentle up/down bob so coins feel lively and mid-air ones are easy to spot
const BOB_SPEED: float = 2.0
const BOB_AMOUNT: float = 0.12

# ============================================================================
# STATE
# ============================================================================

## The spinning visual. We rotate this child, leaving the collision shape steady.
@onready var mesh: Node3D = $Mesh

## Guard so a coin can only ever be collected once.
var collected: bool = false

## Bob animation phase and the rest height we bob around.
var bob_phase: float = 0.0
var base_y: float = 0.0

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	add_to_group("coin")

	# Remember where we were placed so the bob oscillates around it.
	base_y = position.y

	# Offset the bob per-coin so a field of coins doesn't pulse in lockstep.
	bob_phase = randf() * TAU

	# React when something enters our collection volume.
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	# Spin the coin face.
	if mesh:
		mesh.rotate_y(SPIN_SPEED * delta)

	# Bob up and down a little around the spawn height.
	bob_phase += delta * BOB_SPEED
	position.y = base_y + sin(bob_phase) * BOB_AMOUNT


# ============================================================================
# COLLECTION
# ============================================================================

func _on_body_entered(body: Node) -> void:
	"""Collect the coin when the player touches it (ignore everything else)."""
	if collected:
		return
	if not body.is_in_group("player"):
		return

	collected = true
	if body.has_method("collect_coin"):
		body.collect_coin()

	# Remove the coin now that it's been picked up.
	queue_free()
