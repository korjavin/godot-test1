extends CharacterBody3D
## Player Controller Script
##
## This script controls the player character in a 3rd person perspective.
## It handles movement (walking, running), jumping, ducking, and camera control.
##
## EDUCATIONAL NOTES:
## - CharacterBody3D is Godot's built-in class for characters with physics
## - The velocity property is inherited from CharacterBody3D
## - We use Godot's physics engine to handle gravity and collisions

# ============================================================================
# SECTION 1: MOVEMENT SPEED CONSTANTS
# ============================================================================
# These constants define how fast the character moves in different states.
# Try adjusting these values to see how they affect gameplay!

## Normal walking speed in meters per second
const WALK_SPEED: float = 5.0

## Running speed when holding the run button (Shift)
## Note: This is 2x the walk speed for a noticeable difference
const RUN_SPEED: float = 10.0

## Speed when ducking (Ctrl)
## Note: Ducking is slower than walking for realism
const DUCK_SPEED: float = 2.5

## Speed multiplier applied to the GROUNDED gaits (duck/run/walk) while the
## player is standing in a river — see is_wading and calculate_current_speed().
## 0.5 is a 50% slowdown: enough to feel like wading and to make crossing a
## river a real decision. Deliberately NOT applied to Windman's Air Rush —
## flying over a river is not wading.
##
## This started at 0.6 and was deepened on owner feedback ("slower in general
## while submerged"). It bites on WALK and DUCK only: the run gait is floored at
## WADE_RUN_MIN_SPEED below, which already absorbed the whole drag at 0.6 and
## still does — deepening the factor must never be read as making the run slower.
const WADE_SPEED_FACTOR: float = 0.5

## Floor under the RUN gait while wading. The project's difficulty contract is
## "running always escapes": crocodile chase speed is capped at MAX_CHASE_SPEED
## (8.5 in piglet_crocodile_ai.gd) precisely so it stays under the slowest
## character's run (RUN_SPEED 10.0 × CHARACTER_SPEED 0.9 = 9.0). Applying the
## full wade factor to the run gait drops that to 5.4 — below even the BASE
## chase speed of 5.5 — which would make a river band an unescapable death
## trap rather than a decision, and river crossings are not length-bounded (see
## the RIVER_HALF_WIDTH note in endless_terrain.gd). So walk and duck take the
## full drag and the run is floored here instead.
const WADE_RUN_MIN_SPEED: float = 9.0

## How deep the MODEL sinks into a river, in metres, and how fast the offset
## eases in and out (metres per second — depth / ~0.2 s, so stepping in or out
## of the water takes about a fifth of a second instead of popping).
##
## VISUAL ONLY, AND THAT IS A HARD CONSTRAINT: this is written to
## $CharacterModel.position.y, exactly like the walk bob and the landing squash
## write to the model's own nodes. The CollisionShape3D, the body's global_position
## and the flat-world y = 0 ground plane are all untouched — every y-placement
## site in the project (coin heights, croc gravity settle, spawn point, block
## bases) assumes that plane, so "submerged" has to be a picture, never physics.
## Nothing else writes $CharacterModel.position, so this offset owns it outright:
## Teibi's resize tweens `scale` and the landing squash writes `scale` plus
## $CharacterModel/Body.position — different properties, so none of them fight.
##
## ponytail: a fixed depth, not one scaled by Teibi's form. A river is a river —
## giant Teibi wades the same 0.35 m and is barely wet, small Teibi is in it up
## to the chest. That reads correctly and costs no coupling to the resize state.
const WADE_SINK_DEPTH: float = 0.35
const WADE_SINK_EASE_SPEED: float = WADE_SINK_DEPTH / 0.2

## Multiplier on JUMP_VELOCITY for a jump that STARTS from wading — you cannot
## push off properly against water. 0.75 drops the apex from JUMP_VELOCITY^2 /
## (2 * gravity) = 3.61 m to 2.03 m, which is BELOW the 2.5 m top of a single
## decorative block: a block you can hop onto from dry land is genuinely
## unjumpable from inside the river. That is the intended reading of "jumping is
## harder in water", not a bug — wade out first.
##
## Keyed off `is_wading`, which is only ever true while is_on_floor(), so a
## COYOTE-TIME jump (fired from the air, up to COYOTE_TIME after leaving a ledge)
## sees `false` and keeps FULL power. is_wading is recomputed at STEP 1.5, above
## the jump step, precisely so this reads the current frame rather than the last.
const WADE_JUMP_FACTOR: float = 0.75

## How fast Q / E rotate the character, in radians per second.
## Q and E turn the body (tank-style steering), so whatever way the character
## ends up facing is the way W will walk.
const TURN_SPEED: float = 2.6

## How quickly horizontal velocity approaches the input's target speed, in m/s².
## Instead of snapping instantly to full speed the moment W is pressed, velocity
## ramps toward it — at 40 m/s² a standing start reaches walk speed (5 m/s) in
## ~0.125 s. Barely perceptible as "sluggishness", but it gives starts and
## direction changes a sense of weight. Stopping keeps the separate friction
## branch below, which was already gradual.
const MOVE_ACCELERATION: float = 40.0

# ============================================================================
# SECTION 2: JUMP AND PHYSICS CONSTANTS
# ============================================================================

## Jump velocity determines how high the character can jump
## Higher values = higher jumps
## Physics Note: This is the initial upward velocity when jumping.
## Apex height scales with the SQUARE of this: JUMP_VELOCITY^2 / (2 * gravity).
## We doubled velocity (5.1 -> 10.2) AND quadrupled gravity (3.6 -> 14.4), so the
## apex is EXACTLY unchanged: 10.2^2 / (2 * 14.4) = 3.6125 m — same as the old
## 5.1^2 / (2 * 3.6). Single blocks top out at 2.5 m and structures are climbed
## in <=3 m steps, so everything stays jumpable. What DID change is airtime
## (2v/g): 2.83 s -> 1.42 s — the jump reads arcade-snappy instead of floaty.
const JUMP_VELOCITY: float = 10.2

## Gravity value (meters per second squared)
## Deliberately unphysical: 14.4 (about 1.5× Earth) makes the jump arc snappy —
## the character pops up and comes right back down instead of floating. Paired
## with JUMP_VELOCITY above so the apex height is preserved (see the math there).
## For reference, real planets: Moon 1.6, Mars 3.7, Earth 9.8, Jupiter 24.8.
var gravity: float = 14.4

##  ProjectSettings.get_setting("physics/3d/default_gravity")

## Coyote time: for this many seconds AFTER walking off a ledge the jump still
## fires, as if the ground were still underfoot. Players expect it — without it
## a jump pressed one frame late at a block edge silently eats the input.
const COYOTE_TIME: float = 0.12
## Jump buffer: a jump pressed this many seconds BEFORE landing is remembered
## and fires on the first grounded frame, so button-mashing near the ground
## never drops a jump.
const JUMP_BUFFER_TIME: float = 0.12
## Countdown timers for the two grace windows above (ticked in _physics_process).
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0

## Landing impact ("squash"): touching down compresses the character for a brief
## moment, scaled by how fast we were falling — a soft hop barely dips, a long
## drop visibly squashes. Purely visual; the collision capsule never changes.
const LAND_SQUASH_DURATION: float = 0.18
## Impacts faster than this (m/s downward) also get a small camera shake and a
## flat dust ring at the feet — the "heavy landing" tier.
##
## MUST STAY ABOVE A PLAIN JUMP'S TOUCHDOWN SPEED, which is exactly JUMP_VELOCITY
## (10.2 m/s — a symmetric arc lands as fast as it left). At the old 4.0 the tier
## fired on EVERY jump, and even on a 0.56 m step down: constant camera shake and
## a fresh dust-ring mesh allocated per landing, with the "heavy" reading gone
## because nothing was ever light. 12.0 means a real drop from above the jump
## apex — i.e. off a stacked block or a mountain ledge.
const LAND_HARD_SPEED: float = 12.0
## Divisor mapping fall speed → squash strength. Also keyed to the jump arc: at
## the old 10.0 a plain jump saturated the clamp at 1.0, so the documented "a
## soft hop barely dips, a long drop visibly squashes" scaling never happened —
## every landing squashed maximally. 16.0 puts a plain jump at ~0.64 and leaves
## headroom above it for genuine drops.
const LAND_SQUASH_SPEED_DIVISOR: float = 16.0
## Seconds left in the current squash (0 = none) and its 0.2–1.0 strength.
var land_squash_timer: float = 0.0
var land_squash_strength: float = 0.0
## Downward speed recorded every airborne falling frame — move_and_slide zeroes
## velocity.y on touchdown, so the landing code reads this instead.
var _fall_speed: float = 0.0

# ============================================================================
# SECTION 3: CAMERA AND ROTATION SETTINGS
# ============================================================================

## How fast the character rotates to face the movement direction
## Higher values = faster rotation (more responsive but less smooth)
## Lower values = slower rotation (smoother but less responsive)
const ROTATION_SPEED: float = 10.0

## Camera rig references. The chain is CameraPivot → CameraArm → Camera3D:
## the pivot carries the mouse-look pitch, and the SpringArm3D between pivot
## and camera pulls the camera in whenever a wall/block sits in the way, so the
## view never clips through geometry. NOTE: a SpringArm3D OVERRIDES its
## children's local position every physics frame (it slides them along its
## local Z by the collision-clamped length) — so nothing may ever write
## camera.position. The bite shake uses Camera3D.h_offset/v_offset (view-space
## offsets the arm doesn't touch), and both the first-person and front views move
## the ARM itself (see _apply_view_mode).
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera_arm: SpringArm3D = $CameraPivot/CameraArm
@onready var camera: Camera3D = $CameraPivot/CameraArm/Camera3D

## Mouse sensitivity for camera rotation
const MOUSE_SENSITIVITY: float = 0.003

## Keyboard-turn camera easing: when A/D spin the body, the camera pivot lags
## the turn and eases back in at this rate (higher = catches up faster), so a
## keyboard turn sweeps smoothly instead of snapping with the body. MOUSE turns
## deliberately bypass this (they never touch camera_yaw_lag) and stay 1:1.
const CAMERA_TURN_EASE: float = 10.0

## Speed-scaled field of view: the camera widens from FOV_BASE (the Camera3D
## default) toward FOV_MAX as horizontal speed climbs from WALK_SPEED up to
## Windman's air-rush speed — fast movement literally looks fast. Eased at
## FOV_EASE per second so the lens never snaps.
const FOV_BASE: float = 75.0
const FOV_MAX: float = 97.0
const FOV_EASE: float = 5.0
## Transient FOV kick on Windman's Air Rush launch (degrees) and how fast the
## kick bleeds off (degrees per second) — a punch, not a sustained zoom.
const FOV_PUNCH_WINDMAN: float = 12.0
const FOV_PUNCH_DECAY: float = 30.0

## Camera pitch limits (prevents camera from flipping over)
const CAMERA_PITCH_MIN: float = -60.0  # Looking down limit (degrees)
const CAMERA_PITCH_MAX: float = 60.0   # Looking up limit (degrees)

## First-person view (one stop on the C / "toggle_camera" cycle).
## Eye height above the FEET at normal scale — just under the ~1.8 m head top,
## so the camera sits where the character's eyes would be.
const FIRST_PERSON_EYE_HEIGHT: float = 1.65

## The three camera views C cycles through, in cycle order.
enum ViewMode {
	THIRD_PERSON,  ## The shipped view: boom behind and above, looking forward.
	FIRST_PERSON,  ## From the character's own eyes; the model is hidden.
	FRONT,         ## Boom in FRONT looking back — the hero's face, plus what is behind them.
}

## The two run-ending outcomes.
enum Outcome {
	CAPTURED = 1,  ## All four heroes captured by GastroDefense.
	WON = 2,       ## Escaped to Budapest with city explored.
}

## Safe spawn radius - crocodiles within this distance will be removed on respawn
const SPAWN_SAFE_RADIUS: float = 25.0

# ============================================================================
# SECTION 4: STATE VARIABLES
# ============================================================================

## Tracks if the player is currently ducking
var is_ducking: bool = false

## Tracks if the player is currently running
var is_running: bool = false

## True while the player is standing in a river band (see the terrain's biome
## field). Recomputed from scratch every physics tick — it is a pure question
## about where we are standing right now, so it holds no history and needs no
## reset plumbing on respawn/restart. Drives the WADE_SPEED_FACTOR slowdown and
## swaps the footstep sound for a splash.
var is_wading: bool = false

## How far the MODEL is currently sunk below its rest position, in metres, eased
## toward WADE_SINK_DEPTH while wading and back to 0 on dry land. Unlike is_wading
## this one DOES hold history (it is the eased value), so reset_position() zeroes
## it — a hard teleport to the dry spawn point must not leave the hero standing
## in a puddle that is not there for the fifth of a second the ease would take.
var _wade_sink: float = 0.0

## Sidestep / strafe state. While A / D is held on the ground we strafe sideways
## and run a matching leg pose.
var is_stepping: bool = false
## Direction of the current sidestep in the character's local space:
## -1 = strafing left (A), +1 = strafing right (D).
var step_direction: float = 0.0

## How many golden coins the player has collected. The HUD reads this. Coins now
## survive a crocodile bite (it only bills the attacker's `coin_setback` fraction);
## they are reset to 0 only on a full restart from the Game Over screen (see
## restart_game / reset_position).
var coins_collected: int = 0

## Coin streak multiplier: picking up coins in quick succession (each pickup
## within STREAK_WINDOW seconds of the last) builds a streak. Every
## STREAK_COINS_PER_STEP consecutive coins raise the score multiplier by +1, up
## to 1 + STREAK_MAX_BONUS (x5). Letting the window lapse — or getting bitten
## (see hit_by_crocodile) — resets the streak to zero. This rewards staying ON
## the coin road and moving fast, which is exactly the risk the difficulty
## gradient punishes.
const STREAK_WINDOW: float = 2.5
const STREAK_MAX_BONUS: int = 4
const STREAK_COINS_PER_STEP: int = 10
var coin_streak: int = 0
var streak_timer: float = 0.0

## MULTIPLAYER CONTRIBUTION. Inside a room the two numbers the HUD shows —
## coins_collected and run_distance — become the ROOM's totals, summed by
## mp_manager.gd from what every member contributes. This field is what THIS
## peer contributes: the coins it banked itself. It has to be kept apart from
## the displayed field, because that one is overwritten with the shared total
## every physics tick (see _refresh_shared_totals) and would otherwise feed its
## own room total back into itself, doubling the bank on every frame. Offline it
## is simply carried along and never read, so solo play is unchanged.
var own_coins: int = 0

## True while _refresh_shared_totals is overwriting the displayed score fields
## with the room's totals. It exists purely to catch the falling edge — the frame
## the room ends — so this peer's own numbers can be put back; without it the
## room's totals are simply abandoned in the HUD fields for the rest of the run.
var _showing_shared_totals: bool = false

## This peer's OWN farthest displacement this run. Not a contribution the room
## sums (distance is a max, and run_distance already latches the room's — see
## _refresh_shared_totals); it exists because run_distance is OVERWRITTEN with
## the room's max every tick, and the persisted personal records in
## _trigger_game_over() must be this player's own run, not the furthest
## teammate's. Solo the two numbers are identical.
var own_distance: int = 0

## Where own_distance is measured FROM, on the XZ plane. Normally the (0,0) spawn,
## which is why the two distances agree solo. A mid-run joiner is placed beside a
## group that may be kilometres out (see join_at), and measuring from the origin
## there would write the group's distance straight into user://best_run.cfg as
## this player's personal best without them having run a metre — the one thing
## own_distance exists to prevent. run_distance keeps measuring from the origin:
## it is the run's position on the shared map, not a personal record.
var own_distance_origin: Vector2 = Vector2.ZERO

## Headline score: how far this run has travelled, in metres — the farthest
## HORIZONTAL DISPLACEMENT from the (0,0) spawn point ever reached this run.
## (Originally this tracked farthest world X — the coin road's forward axis —
## but playtesting showed that reads as a broken counter the moment the player
## wanders any other direction: the number just sits at 0. Displacement is
## direction-agnostic, and for a player following the road it is almost exactly
## the same number, since the road's X is strictly increasing by construction.)
## We track a running max so backtracking never lowers it. Reset to 0 only on a
## full restart (restart_game / reset_position).
var run_distance: int = 0

## Spawn facing: -PI/2 turns the body's -Z forward onto +X — straight down the
## coin road — so "just walk forward" from spawn follows the coin trail and the
## distance counter climbs immediately. (With the default 0.0 facing, a new
## player walks off along Z, sees Distance stuck at 0, and reads it as a bug.)
const SPAWN_FACING_Y: float = -PI / 2

## MID-RUN MULTIPLAYER JOIN. A joiner does not restart at the origin — it drops
## in beside the group (see join_at). We try the first clear spot on these rings
## (in metres) around the group's anchor, JOIN_RING_ANGLES evenly spaced
## candidates per ring, nearest ring first: close enough to see the others, far
## enough not to materialise on top of one. Tuned by eye.
const JOIN_RING_RADII: Array[float] = [3.0, 5.0, 8.0, 12.0]
const JOIN_RING_ANGLES: int = 8
## Drop-in height, the same short fall onto the flat ground reset_position()'s
## spawn point uses, so the landing squash reads instead of a hard snap.
const JOIN_SPAWN_HEIGHT: float = 2.0

## Best-run records (coins). Read in _trigger_game_over() to decide the
## "NEW BEST!" flash, and pushed back through the store there.
##
## WHERE THEY ARE KEPT IS NOT THIS FILE'S BUSINESS ANY MORE. `best_run_store.gd`
## owns both the local store (a ConfigFile on desktop, `localStorage` on web)
## and the lobby's `/best` endpoint, which is what makes a record follow a
## player between devices. All this side does is fold whatever the store
## reports in with `maxi`, so a late server reply can never lower a record and the
## order the two layers answer in does not matter.
var best_distance: int = 0
var best_coins: int = 0
var best_run_store: BestRunStore = null

## Did THIS run move the coin record? A LATCH, not a comparison, because
## `_bank_records()` now runs on every bite (bead godot-test1-0bc) and raises
## `best_coins` to `own_coins` as it goes — so by the time the ending
## panel asks, `own_coins > best_coins` is false on the very runs that
## earned the flash. The fact is recorded where it is still true and read at the
## ending; `reset_position()` (the hard-reset wipe list) clears it.
var run_beat_record: bool = false
## THIS RUN'S COIN PEAK — the highest `own_coins` ever reached, not the live
## balance. `_bank_records()` banks THIS (bead godot-test1-h6x) and
## `_reconcile_record_latch()` reconciles against it, both for the same reason:
## `own_coins` goes DOWN at a setback, and a bite bills the setback and then banks
## in the same call chain (`_on_caught_finished`), so a record read off the live
## balance is always one bill below the number the HUD showed.
##
## Maintained at the ONE place `own_coins` decreases (`_pay_coin_setback`, which
## snapshots the pre-bill balance) plus a `maxi` in `_bank_records` — never at the
## two `+=` sites, because a peak only needs recording where it is about to be
## lost. Both wipes of `own_coins` (`restart_game`, the room join) clear it.
var record_coins: int = 0

## How often the run's records are checkpointed while the player is simply
## playing. `_bank_records()` runs on every bite because a bite is what replaced
## the ending as the end of a leg (bead godot-test1-0bc) — but a bite is not
## GUARANTEED any more, and a careful player can run for an hour without one, so
## a closed tab would still take the whole session with it. This tick is the
## damage-independent half of the same guarantee. It is nearly free: both writers
## under `_bank_records()` are change-gated (`BestRunStore.submit()` only when a
## record moved, `Progression.save()` dropping a save whose counters have not),
## so a quiet interval costs two integer comparisons.
const BANK_INTERVAL: float = 15.0
var bank_timer: float = 0.0

## "Caught" sequence: when a crocodile bites the player we freeze briefly (so the
## bite is actually visible), flash the screen red and shake the camera, then
## respawn. These track that short window.
var is_caught: bool = false
var caught_timer: float = 0.0
const CAUGHT_DURATION: float = 0.55

## THE BILL FOR THIS CONTACT, latched across the caught freeze. Every hit in the
## game charges one — heroes are the lives now, so a bite takes coins and never a
## heart — and the fraction is the attacker's own `coin_setback` row key. Held
## here rather than re-derived in `_on_caught_finished()` because the attacker is
## gone by then (the caught freeze is 33 frames long and it may have been slept,
## freed by a population reset, or simply walked away), and re-asking would
## silently downgrade the hit to the default. Same shape and same reason as the
## capture gate two lines below it in `hit_by_crocodile()`: the decision is made
## where the evidence is.
var caught_setback: float = 0.0

## DID THIS CONTACT ARREST US? Latched beside the bill above, decided at the same
## seam and for the same reason: the attacker is gone by the time the freeze ends.
## Read by `_pay_coin_setback()`, which refuses the tower's checkpoint knockback
## for an arrest — owner ruling 2026-09-01 (bead godot-test1-3iy.19): a catch
## inside the HQ imprisons the hero exactly like a field grab, and the heroes
## still free "continue to play from the same place after cooldown". Dragging the
## survivor to the doorway plate would be a second, unruled penalty on top of the
## one the owner asked for — and on the storey where the arrest happened, the way
## back to the cells. The knockback still catches every OTHER way to lose in the
## building: a pre-beat guard, the press, an animal that followed
## you through the door.
var caught_captured: bool = false

## ...AND THE SAME FACT AGAIN, FOR THE CAPTION, because the one above cannot be
## read where the caption is written (bead godot-test1-tuc). `caught_captured` is
## SPENT by `_pay_coin_setback()` — it is cleared the moment the knockback
## decision is taken, and `capture_selfcheck` asserts that clearing by name ("the
## arrest latch survived the contact it was set for"), because a latch left armed
## waives the NEXT indoor hit's knockback for free. The respawn countdown is drawn
## a whole freeze later, every frame of the grace window, long after that. So the
## caption gets its own copy with its own lifetime: written at the same seam, read
## by `_show_respawn_countdown()`, and never consulted by anything that decides
## what a contact COSTS.
##
## What it buys is the owner's distinction (2026-09-04): a bite is a coin tax and
## a soft respawn — "Robbed!" — while "Caught!" is reserved for the arrest that
## actually puts a hero in a cell. The old caption said "Caught!" for both, which
## told the player they had lost a hero to every crocodile in the field.
var caught_was_arrest: bool = false

## What a hit with no SPECIES row behind it costs — the tower's press, a boss
## projectile, a `null` attacker in a self-check. Named rather than inlined so the
## "every contact pays" rule has no free hit hiding in it, and set to the ordinary
## field predator's number so an environmental hazard is neither the cheapest nor
## the most expensive way to lose coins.
const DEFAULT_COIN_SETBACK: float = 0.10

## GAME-OVER STATE. HEROES ARE THE LIVES (owner ruling 2026-08-31): there is no
## heart to spend, so an ordinary bite is the caught freeze plus the attacker's
## `coin_setback` and a respawn in place, forever. The only ending left is the
## free-hero set going empty — the FOURTH CAPTURE ends the run on the spot (owner
## veto 2026-09-01, bead godot-test1-ueg), which raises the Game Over screen and
## freezes the player until they restart. `_trigger_game_over()` is the one writer.
var is_game_over: bool = false
## Outcome of the ended run: CAPTURED (loss) or WON (victory).
var run_outcome: Outcome = Outcome.CAPTURED

## Post-respawn grace, in TWO phases. Phase 1: after a bite we stand
## frozen and invulnerable for RESPAWN_GRACE_DURATION seconds (with crocodiles
## swept out of the area). Phase 2: control returns immediately after, but we
## stay invulnerable for RESPAWN_BLINK_DURATION more seconds while the model
## blinks (classic arcade i-frames) — so we get moving again fast without a
## wandering crocodile biting us the instant we recover. The blink toggles
## visibility every RESPAWN_BLINK_CADENCE seconds (skipped in first-person,
## where the model is already hidden). hit_by_crocodile treats a running
## respawn_blink_timer exactly like the frozen window: bites are ignored.
var is_respawning: bool = false
var respawn_timer: float = 0.0
var respawn_blink_timer: float = 0.0
const RESPAWN_GRACE_DURATION: float = 1.5
const RESPAWN_BLINK_DURATION: float = 2.5
const RESPAWN_BLINK_CADENCE: float = 0.1

## Camera shake, used by the crocodile-bite hit effect. Decays back to 0.
## The shake drives Camera3D.h_offset/v_offset (view-space slide of the lens),
## NOT camera.position — the SpringArm3D owns the camera's local position and
## would stomp any write there every physics frame. Offsets also work
## identically in first-person, so the shake needs no per-view rest caching.
var shake_amount: float = 0.0
const SHAKE_MAX: float = 0.25
const SHAKE_DECAY: float = 1.0

## Keyboard-turn camera lag (radians). handle_turning subtracts each frame's
## body turn into this; _process applies it to the pivot's yaw and decays it to
## zero, so the camera trails an A/D turn and eases in behind the body. Mouse
## turns never touch it, keeping mouse look 1:1. Zeroed in reset_position().
var camera_yaw_lag: float = 0.0

## Mouse-look pitch (radians), tracked HERE rather than read back off the pivot.
## THIS IS LOAD-BEARING, not bookkeeping: the pivot now carries yaw (the lag
## above), and Node3D.rotate_x PRE-multiplies (basis = Rx(d) * Ry(yaw) * Rx(p)),
## which has no zero-roll YXZ decomposition — so reading `rotation.x` back and
## writing only it BAKES a parasitic `rotation.z` that nothing ever clears
## (measured: -76 deg of permanent horizon cant while holding A and dragging the
## mouse down; it survives respawn and restart). Every write to the pivot's
## rotation therefore goes through the full Vector3 below, with an explicit 0
## roll term. Never reintroduce rotate_x() here.
var camera_pitch: float = 0.0

## Transient FOV kick (degrees) added on top of the speed-scaled target — set
## to FOV_PUNCH_WINDMAN by Windman's Air Rush launch, decayed back to zero at
## FOV_PUNCH_DECAY per second by the FOV code in _process.
var fov_punch: float = 0.0

## Which of the three views we are in. This is a player PREFERENCE, not transient
## state: it deliberately survives respawn, restart, and character switches
## (nothing in those paths resets it). Cycled with C in _physics_process (STEP 0).
## Typed `int` rather than `ViewMode` on purpose: the cycle below is plain modular
## arithmetic, and GDScript will not implicitly narrow an int expression back into
## an enum type.
var view_mode: int = ViewMode.THIRD_PERSON
## The spring arm's original scene-file transform (−14° pitch at the pivot) and
## length (8.25 — the old camera's (0,2,8) offset expressed as an arm), plus the
## camera's residual −1° pitch, cached in _ready() so leaving first-person
## restores the shipped third-person framing byte-for-byte. First-person
## commandeers the ARM (identity basis at the eyes, zero length ⇒ no collision
## cast ⇒ the arm is bypassed in FP for free) — see _apply_view_mode().
var third_person_arm_transform: Transform3D = Transform3D.IDENTITY
var third_person_arm_length: float = 0.0
var third_person_camera_rotation: Vector3 = Vector3.ZERO

## THE INDOOR BOOM — the third-person arm length used while a room says we are in
## it, instead of the scene's 8.25. Two problems, one number (bd godot-test1-0nu):
##
##   THE COLLAPSE. The arm is pitched 14 degrees up, so what a wall has to make
##   room for is not the length but its HORIZONTAL reach, length * cos(14 deg),
##   plus the arm's 0.25 m margin. At 8.25 that is 8.25 m of clearance — and the
##   tower's courtyard is 8.3 m wide, so facing across it put a wall inside the
##   boom and the view became the back of the hero's head. 3.85 asks for
##   3.85 * cos(14 deg) + 0.25 = 3.98 m, which fits inside HALF that courtyard
##   (4.15 m): a player on its centre line keeps the whole boom whichever way they
##   turn, and the collapse only starts once they are genuinely against a wall —
##   which is what a third-person camera is supposed to do.
##
##   THE COST, and be careful with this half. A shorter arm sweeps less static
##   collision, and it MEASURES: a 300-frame A/B on the shipped legs put the
##   PHYSICS STEP down 0.3-0.8 ms in every tight room (cell gallery 3.83 -> 3.18,
##   vault 3.98 -> 3.23) against a ±0.3 ms noise floor. But that step is only
##   ~3.5 ms of a 30-45 ms tower frame, so the FRAME TIME did not move — bd
##   godot-test1-0nu's earlier bisection, which put the arm at ~9 ms of a ~46 ms
##   frame, does not reproduce on the current build. So this number is chosen for
##   the framing above and takes the physics saving as a bonus; the tower's real
##   frame cost is still unaccounted for and is somebody's next bead.
##
## It also lowers the camera to 1.5 + 3.85 * sin(14 deg) = 2.43 m over the feet,
## under the maintenance crawl's 2.8 m lintel — so the indoor view stops scraping
## indoor ceilings as well. Asserted against the courtyard in
## `tower_interior_selfcheck` check 4.
const INDOOR_ARM_LENGTH: float = 3.85

## How fast the boom travels between the two lengths, in metres per second. The
## whole trip is 8.25 - 3.85 = 4.4 m, so 18 puts a doorway at about a quarter of a
## second: fast enough to be over before you have looked around the room, slow
## enough to read as a dolly instead of a cut. See `_tick_arm_length()`.
const ARM_EASE_SPEED: float = 18.0

## Is a room currently holding the indoor boom? Written ONLY by
## `set_indoor_camera()`; read only through `_third_person_arm_target()`, which
## both the snap path and the ease path go through. Transient world state, not a
## preference: whoever set it clears it (including when the room is FREED — see
## `TowerInterior._exit_tree`), and `_refresh_indoor_camera()` re-derives it from
## scratch on every teleport, so a hard reset needs no line of its own.
var _indoor_camera: bool = false

## Character's visual mesh (for ducking animation)
@onready var mesh_instance: Node3D = $MeshInstance3D

## Original height of the character (for ducking)
var original_scale_y: float = 1.0

## Player collision capsule. Teibi's resize ability scales this (and the visible
## model) up and down; we cache its rest position and half-height so the capsule's
## BOTTOM can be pinned to the ground at any size — the player never sinks into the
## floor or gets launched when growing or shrinking.
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
var collision_base_y: float = 1.0
var collision_half_height: float = 1.0

# ============================================================================
# SECTION 5: CHARACTER SYSTEM
# ============================================================================

## Available characters in the game
const CHARACTERS: Array[Dictionary] = [
	{
		"name": "windman",
		"scene_path": "res://scenes/characters/windman_updated.tscn"
	},
	{
		"name": "primm",
		"scene_path": "res://scenes/characters/primm.tscn"
	},
	{
		"name": "teibi",
		"scene_path": "res://scenes/characters/teibi.tscn"
	},
	{
		"name": "phoboman",
		"scene_path": "res://scenes/characters/phoboman.tscn"
	}
]

## The 1-4 hotkeys, one row per `CHARACTERS` index: press 2 and you ARE Primm.
##
## RAW KEYCODES, outside project.godot's input map, for the same reason
## landmark_toast.gd's answer keys and minimap_hud.gd's M are raw: a named action
## is for rebindable GAMEPLAY input, and a key that only picks one specific hero
## has nothing to rebind against — rebinding "hero 2" to another key is a roster
## question, not a keymap one. Both the number row and the numpad are accepted,
## the same pair those two accept.
##
## The digits are the ones hero_hud.gd draws on its portrait tiles, and
## help_selfcheck.gd rebuilds the help card's "1 2 3 4" legend from this array.
const HERO_KEYCODES: Array = [
	[KEY_1, KEY_KP_1],
	[KEY_2, KEY_KP_2],
	[KEY_3, KEY_KP_3],
	[KEY_4, KEY_KP_4],
]

## Cheat-code sequence recogniser (bead godot-test1-a7i): \fo perf overlay,
## \fb teleport Budapest, \fh teleport HQ. Backslash arms an empty buffer;
## the next two letter keys within CHEAT_TIMEOUT_MS complete it.
const CHEAT_ARM_KEY: Key = KEY_BACKSLASH
const CHEAT_TIMEOUT_MS: int = 2000

const CHEAT_CODES: Dictionary = {
	"fo": "perf_overlay",
	"fb": "teleport_budapest",
	"fh": "teleport_hq",
}

var _cheat_armed: bool = false
var _cheat_buffer: String = ""
var _cheat_armed_msec: int = 0
var _cheat_swallowed_frame: int = -1

## Reentrancy guard for the teleport below: it awaits a physics frame, and a
## second press inside that window must not start a second rebuild.
var _debug_teleport_busy: bool = false

## Current character index (starts with windman at index 0)
var current_character_index: int = 0

## WHO THE CORPORATION IS HOLDING RIGHT NOW, as a set of `CHARACTERS` names.
##
## THE CAPTIVE SET (bead godot-test1-3iy.9). Availability is `hand INTERSECT free`:
## the E-cycle already restricts itself to an allowed-index array (the lobby's, in a
## room), and captivity is ONE MORE INTERSECTION at that same site rather than a
## second roster system. `available_character_indices()` is where the two meet, and
## it is the only question anything asks about the roster.
##
## NON-MONOTONE, AND THAT IS WHY IT LIVES HERE. A capture adds and a liberation
## removes, so this set can go BACKWARDS — which disqualifies it from the union/max
## merge in `best_run_store.gd`, where every field is monotone precisely so a late
## reply or a retry can never lower a record. The tower's opened-gate ids are the
## opposite kind of fact (earned, never lost) and ride that union; this one is plain
## world state and stays out of it. `best_run_store.gd`'s own header states the
## rule: "if it can go backwards it does not belong in a monotone set".
##
## Per-run: `restart_game()` empties it, so Play Again always hands back four heroes.
var captive_heroes: Dictionary = {}

# ---------------------------------------------------------------------------
# THE EXPLORED SET — 22 bits, and eighteen of them is the WIN
# ---------------------------------------------------------------------------
#
# Epic `godot-test1-8gw`, bead .5. `BudapestPlan.SLOTS` is the authored win set:
# 22 places, indexed once and forever, so "which landmarks has this run seen" is
# a bitmask and not a set of names, a set of ids or a list of nodes. One int.
#
# THREE PROPERTIES, and each one is why it is an int here rather than anything
# else:
#
#   * PER-RUN, LIKE THE CAPTIVE SET. `restart_game()` empties it beside
#     `captive_heroes` and for the same reason — nothing about a walk through
#     Budapest is EARNED, so this may not ride `best_run_store`'s monotone union.
#     What IS banked is the COUNT, through `submit_landmarks()`, which is a max
#     and therefore safe.
#   * ADD-ONLY WITHIN A RUN, which is what makes the multiplayer half trivial.
#     `adopt_explored_mask()` ORs and never assigns, so a stale `room` packet can
#     un-explore nothing and the two directions need none of the grace-window
#     machinery `_adopt_room_captives` carries for a set that can go backwards.
#   * ROOM-WIDE IN A ROOM. A landmark counts when ANY member walks it (bead .5),
#     so `MpManager` unions the room's claims and hands them back here. Solo, this
#     mask is the whole truth.
var explored_mask: int = 0

## How many of the 22 slots end the run in victory — the owner's 80%, rounded to
## the 18 the epic states in words. Written here rather than derived from
## `SLOTS.size()` because 18-of-22 is a DESIGN number: a wave that adds a
## twenty-third landmark must be an explicit decision about the win, not a
## silent retune of it.
const BUDAPEST_WIN_LANDMARKS: int = 18

# ---------------------------------------------------------------------------
# THE FOURTH CAPTURE IS THE ENDING (owner veto 2026-09-01, bead godot-test1-ueg)
# ---------------------------------------------------------------------------
#
# There used to be a designed break-out scene here — a recall clock, a raised
# containment and a roster grant — opened when the corporation held every hero.
# It was an ADOPTED READING layered onto the owner's actual ruling
# (`godot-test1-0bc`, "game over ONLY when all four heroes are jailed"), and the
# owner has vetoed it verbatim: "i still see this recall in 33 after all caught,
# why? I never asked for this". The fourth capture now ends the run where it
# lands — `BestRunStore.archive_world()` and `_trigger_game_over()`, the ending
# film on web and the plain panel on desktop.
#
# DO NOT RE-ADOPT THE SCENE. If a future pass wants one, that is an owner ruling
# and not a planning decision. What survives it is the ARCHIVE latch (its own
# `[world] archived` flag in `best_run_store.gd`, because New Game has to clear it
# and a monotone union has no removal verb) and the authored SCAR ROW, which is a
# PERSISTED id in profiles that survived a break-out and so may not be deleted.
#
# The PARTIAL-capture rescue play is untouched: spine doors, liberation, the
# benched-peer prison role below, the vent purge and the block confinement.

# ---------------------------------------------------------------------------
# THE PRISON ROLE (bead godot-test1-3iy.10) — multiplayer only
# ---------------------------------------------------------------------------
#
# The owner's rule is REASSIGN FIRST, IMPRISON LAST. A peer whose hero is taken
# is given a free unclaimed hero through the lobby's own `SetHero` and keeps
# playing in the field; only when the room has nothing to give does that peer
# play as their captive INSIDE the cell block, in a bounded role — no phasing, no
# combat loop, no solo escape.
#
# WHY IT IS A POLLED STATE AND NOT AN EVENT. The reassignment is a lobby round
# trip: `claim_hero()` changes nothing locally and the answer arrives one `heroes`
# broadcast later, possibly as `errHeroTaken` with fresher truth. So "am I benched"
# cannot be decided at the moment of capture — it is decided by asking, twice a
# second, the one question that has a local answer: does the lobby say I hold a
# hero, and is that hero in a cell? Everything else follows from that, including
# the exit (somebody freed him, or a claim finally landed), with no latch to leak.

## Is the local player serving the prison role right now?
##
## PUBLIC, because `TowerInterior._on_cell_enter()` reads it off the body to refuse
## a self-rescue. Solo it is false for the whole run and every line below is dead.
var prisoner_active: bool = false

## Seconds accumulated toward the next prison-role decision, and the interval.
##
## TWICE A SECOND, not per frame. The decision reads the lobby's last truth and
## may send a claim, and a claim per frame would be the storm `_auto_claim_hero()`
## documents; half a second is far under the caught freeze the player is watching
## anyway, so the bench never feels polled.
var _prison_accum: float = 0.0
const PRISON_TICK: float = 0.5

## The tower's world position, latched when the prison role began, so the
## confinement clamp costs no group lookup per frame. Vector3.INF-free: the flag
## below is what says whether it means anything, because a headless harness has no
## terrain and a prisoner there is simply not confined.
var _prison_origin: Vector3 = Vector3.ZERO
var _prison_confined: bool = false

## Reference to the character model container
@onready var character_container: Node3D = $CharacterModel

## Currently loaded character instance
var current_character_node: Node3D = null

## All character models, instanced once up front and reused. Switching characters
## just toggles which one is visible, so there is no per-press load/instance cost
## (which is what used to cause the hitch when pressing E).
var character_instances: Array[Node3D] = []

## Cached neutral limb rotations for each character, captured at startup while the
## model is in its untouched rest pose. Restoring from this on activation means a
## character never resumes from a frozen mid-animation pose after being hidden.
var character_rest_poses: Array[Dictionary] = []

# ============================================================================
# SECTION 6: ANIMATION SYSTEM
# ============================================================================

## THE ANIMATION SYSTEM, and it lives in `scripts/player_animation.gd`
## (bd godot-test1-ftn.9). The limb references, `original_rotations`, the
## `GAITS` table, the walk/idle/air/sidestep poses and the cel-shading of a
## character model all moved there whole; this node keeps movement, capture,
## respawn and every contract method the `"player"` group answers.
##
## A `RefCounted` HOLDING THE PLAYER, not a static library, because the pose
## IS state — five node references, `original_rotations` and two phase clocks —
## and `landmark_builders.gd`'s static-with-an-out-param contract would mean
## passing all of it on every frame. It reaches back through `player` for the
## things the BODY owns (`is_on_floor()`, the landing squash, the Teibi scale,
## the sidestep flags, `_sfx`), which is the one direction this seam runs.
var anim: PlayerAnimation = PlayerAnimation.new()

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init() -> void:
	"""
	Hand the animation helper its back-reference, before ANY tree callback runs.

	`_ready()` would be too late for a harness that pokes the pose on a freshly
	instanced body, and it is the only wiring the seam needs.
	"""
	anim.player = self

func _ready() -> void:
	"""
	Called when the node enters the scene tree.
	This is where we do initial setup.
	"""
	# Face straight down the coin road (+X) from the very first frame, so "just
	# walk forward" follows the coin trail and the distance counter climbs
	# immediately (see SPAWN_FACING_Y for why this beats the default facing).
	rotation.y = SPAWN_FACING_Y

	# Desktop pause handler (P key). Instanced in code — not a main.tscn node —
	# so any scene that runs the player standalone gets pausing for free; see
	# pause_controller.gd for why it must be a separate PROCESS_MODE_ALWAYS node.
	add_child(preload("res://scripts/pause_controller.gd").new())

	# Capture the mouse so it doesn't leave the game window — but ONLY when this is NOT
	# a touch session. On a phone/tablet the mobile controls are active and there is no
	# mouse to capture; requesting pointer-lock there would pop a useless permission
	# prompt and can leave the page in a weird captured state. So we skip the capture
	# on a touch session, leaving the cursor visible for the on-screen touch buttons.
	#
	# CANONICAL DETECTION (the fix): we ask `MobileSensors.is_touch_session()` — the
	# SAME static rule the touch UI uses (cached there as `_is_touch`) — instead
	# of the narrower `DisplayServer.is_touchscreen_available()`. Previously the UI could
	# decide "mobile" (via the web coarse-pointer check) while this guard still captured
	# the mouse, an inconsistency on web phones that report no Godot touchscreen.
	#
	# DESKTOP SAFETY: on a native desktop build (no touchscreen, not web) the static func
	# returns false WITHOUT touching JavaScriptBridge, so mouse capture happens exactly as
	# before — desktop keyboard+mouse play is byte-for-byte unchanged. (Mobile-motion plan.)
	if not MobileSensors.is_touch_session():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Load the persisted best-run records: the local store answers synchronously
	# inside fetch(), the lobby may raise them a moment later. See best_run_store.gd.
	best_run_store = BestRunStore.new()
	best_run_store.name = "BestRunStore"
	add_child(best_run_store)
	best_run_store.loaded.connect(_on_best_run_loaded)
	best_run_store.fetch()

	# Store the original character height for ducking calculations
	if mesh_instance:
		original_scale_y = mesh_instance.scale.y

	# Cache the collision capsule's rest pose so Teibi's resize ability can keep the
	# capsule grounded at any scale, and give every character its own cooldown slot.
	if collision_shape:
		collision_base_y = collision_shape.position.y
		if collision_shape.shape is CapsuleShape3D:
			collision_half_height = (collision_shape.shape as CapsuleShape3D).height * 0.5
	ability_cooldowns.resize(CHARACTERS.size())
	ability_cooldowns.fill(0.0)

	# Instance every character once up front, then show the starting one (windman).
	# Pre-instancing here keeps later character switches instant.
	preload_all_characters()
	set_active_character(current_character_index)

	# Cache the spring arm's scene pose (transform + length) and the camera's
	# residual pitch so the first-person toggle (C) can restore the exact
	# shipped third-person view when switching back. Also exclude our own
	# capsule from the arm's collision cast — otherwise the arm would "hit"
	# the player and yank the camera into the back of our head.
	if camera_arm:
		camera_arm.add_excluded_object(get_rid())
		third_person_arm_transform = camera_arm.transform
		third_person_arm_length = camera_arm.spring_length
	if camera:
		third_person_camera_rotation = camera.rotation

	# CONTINUE REOPENS THE ENDING SCREEN. An archived world (the record of a run
	# that lost every hero) is READ-ONLY: launching the game is what "Continue"
	# means here, so a run is not handed out — the ending comes back up and only
	# "Play Again" mints a fresh world. Deferred by one idle frame because the panel
	# is a sibling in `main.tscn` and may not have joined its group yet.
	if BestRunStore.world_archived():
		_reopen_archived_ending.call_deferred()

	print("Player Controller initialized!")
	print("Controls:")
	print("  W / S - Move forward / back (you run by default)")
	print("  Q / E - Turn left / right")
	print("  A / D - Strafe left / right")
	print("  Space - Jump")
	print("  Shift - Hold to slow to a walk")
	print("  Ctrl - Duck")
	print("  R - Switch Character")
	print("  F - Special ability (unique per character)")
	print("  K - Skill tree")
	print("  Mouse - Look around")
	print("  ESC - Release mouse")

# ============================================================================
# INPUT HANDLING
# ============================================================================

func _input(event: InputEvent) -> void:
	"""
	Handles mouse input for camera rotation.
	This runs whenever an input event occurs.
	"""
	# Check if the mouse moved
	if event is InputEventMouseMotion:
		# Only rotate camera if mouse is captured
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			# Rotate the entire character body left/right (yaw)
			rotate_y(-event.relative.x * MOUSE_SENSITIVITY)

			# Pitch the camera pivot up/down. Accumulated and clamped in our own
			# float, then written as a WHOLE rotation with a zero roll term —
			# see camera_pitch for why rotate_x() must not come back here.
			camera_pitch = clampf(camera_pitch - event.relative.y * MOUSE_SENSITIVITY,
					deg_to_rad(CAMERA_PITCH_MIN), deg_to_rad(CAMERA_PITCH_MAX))
			camera_pivot.rotation = Vector3(camera_pitch, camera_yaw_lag, 0.0)

	# Allow player to release mouse with ESC.
	# TOUCH-SESSION GUARD: on a phone/tablet we deliberately keep the mouse VISIBLE so
	# the on-screen touch buttons are usable and no pointer-lock prompt appears (matching
	# the same `MobileSensors.is_touch_session()` gate used by the mouse-capture sites in
	# `_ready()`/`restart_game()`). Without this guard, ESC's unconditional toggle could
	# re-capture the mouse in a touch session, bypassing that single source of truth. So
	# on a touch session ESC only ever moves TOWARD visible (never into captured); on
	# desktop (non-touch) the original capture<->visible toggle is byte-for-byte unchanged.
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		elif not MobileSensors.is_touch_session():
			# Desktop only: re-capture on a second ESC. A touch session never re-captures.
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# DESKTOP-WEB CLICK-TO-CAPTURE: browsers refuse pointer lock outside a user
	# gesture, so the `_ready()` capture silently fails on a fresh web page load
	# and the camera is dead until the (undiscoverable) double-ESC re-capture.
	# Any click while the mouse is free re-captures it — a click IS the required
	# gesture. Same touch-session guard as the sites above, and never during Game
	# Over (the Play Again button needs a visible, clickable cursor).
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
				and not MobileSensors.is_touch_session() and not is_game_over:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Handle character switching with E key. Not while the Game Over screen is up:
	# the cursor is free and other UI has focus there, and the MP panel's invite
	# codes are drawn from an alphabet that contains R (the second `switch_character`
	# binding), so typing one would otherwise swap the frozen player's model.
	if event.is_action_pressed("switch_character") and not is_game_over:
		switch_to_next_character()

	# CHEAT CODE SEQUENCE RECOGNISER (bead godot-test1-a7i): \fo, \fb, \fh.
	# Backslash arms an empty buffer; the next two letter keys within ~2 s
	# complete it. A match dispatches; any other key, a third letter, or the
	# timeout discards the buffer silently — never a partial action.
	#
	# Runs in _input() before any HUD panel's _unhandled_input() sees the keys,
	# so set_input_as_handled() steals them (e.g. 'b' from CityMapPanel).
	if is_game_over or get_tree().paused:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == CHEAT_ARM_KEY:
		_cheat_armed = true
		_cheat_buffer = ""
		_cheat_armed_msec = Time.get_ticks_msec()
		get_viewport().set_input_as_handled()
		return
	elif _cheat_armed:
		if Time.get_ticks_msec() - _cheat_armed_msec > CHEAT_TIMEOUT_MS:
			_cheat_armed = false
			_cheat_buffer = ""
		elif key.keycode >= KEY_A and key.keycode <= KEY_Z:
			# keycode identifies the physical key label regardless of Shift.
			_cheat_buffer += char(key.keycode).to_lower()
			_cheat_swallowed_frame = Engine.get_physics_frames()
			get_viewport().set_input_as_handled()
			if _cheat_buffer.length() == 2:
				var code: String = _cheat_buffer
				_cheat_armed = false
				_cheat_buffer = ""
				_dispatch_cheat_code(code)
			return
		else:
			_cheat_armed = false
			_cheat_buffer = ""


func _unhandled_input(event: InputEvent) -> void:
	"""
	1-4 (number row or numpad) jump STRAIGHT to that hero — the digits hero_hud.gd
	draws on its portrait tiles. R still cycles; this is the same switch by another
	road, through the same `switch_to_character()` primitive and the same filter.

	UNHANDLED, not `_input`, and that is the whole quiz story: landmark_toast.gd
	reads 1/2/3 in `_unhandled_input` too and `accept_event()`s them, so while a
	question is up the card answers and the hero must not also change. THE GUARD
	BELOW IS EXPLICIT AND MUST STAY — leaning on which node the engine reaches
	first would make the rule an accident of tree order, and the toast lives in the
	HUD CanvasLayer, not under the player. With the guard, 1/2/3 answer the quiz
	and 4 is simply inert while the card is up.

	It also stays out of the way of every overlay: the tree is paused by all of
	them (the skill tree, the pause screen, this card), so a digit typed to close
	one never swaps a hero. `is_game_over` is refused for the reason the R press
	above is — the MP panel's invite codes are typed with the cursor free.
	"""
	if is_game_over or get_tree().paused:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var toast := get_tree().get_first_node_in_group("landmark_toast")
	if toast and toast.has_method("is_quiz_pending") and toast.is_quiz_pending():
		return
	for index: int in HERO_KEYCODES.size():
		if (HERO_KEYCODES[index] as Array).has(key.keycode):
			switch_to_character(index)
			# `accept_event()` is a Control method and this is a CharacterBody3D, so
			# the consume is spelled the long way — same effect: nothing below us
			# sees the digit.
			get_viewport().set_input_as_handled()
			return


func _dispatch_cheat_code(code: String) -> void:
	if not CHEAT_CODES.has(code):
		return
	match code:
		"fo":
			var perf: Node = get_tree().get_first_node_in_group("perf_overlay")
			if perf != null and perf.has_method("toggle"):
				perf.toggle()
		"fb", "fh":
			if debug_teleport_allowed(OS.is_debug_build(), _debug_in_room()) \
					and not _debug_teleport_busy:
				var dest := debug_destination_budapest() \
					if code == "fb" else debug_destination_hq()
				debug_teleport_to(dest)

# ============================================================================
# CAMERA VIEW CYCLE (third-person / first-person / front)
# ============================================================================

func _apply_view_mode() -> void:
	"""
	Moves the EXISTING camera (no second Camera3D!) to match the current view
	mode. Deliberately idempotent — safe to re-run any time (e.g. after a Teibi
	resize or a character switch) without tracking what the previous state was.

	IT SNAPS, so it first makes sure it is snapping to the truth. Several callers
	are TELEPORTS — `join_at()` into a room's group, the bench into a cell — and
	`_indoor_camera` is polled by the building, so on the
	frame of a teleport it still describes where we WERE. Re-deriving it here from
	where we ARE turns those into clean cuts instead of a quarter-second ease
	starting from the wrong boom, and does it for every future teleport too.
	"""
	if not camera or not camera_arm:
		return
	_refresh_indoor_camera()
	if view_mode == ViewMode.FIRST_PERSON:
		# First-person commandeers the ARM, not the camera (the arm owns the
		# camera's local position — see the rig note in SECTION 3). Identity
		# basis zeroes the arm's −14° scene pitch so the pivot's pitch alone
		# (mouse-look) is the look pitch; the arm origin moves to the eyes; and
		# zero spring length means the camera slides to the arm origin AND no
		# collision ray is cast — the arm is bypassed in FP for free. The
		# camera's residual −1° pitch is zeroed too. Hide the model so we
		# don't see our own head from the inside.
		camera_arm.spring_length = 0.0
		camera_arm.transform = Transform3D(Basis.IDENTITY, _first_person_eye_position())
		camera.rotation = Vector3.ZERO
		if character_container:
			character_container.visible = false
	else:
		# THIRD_PERSON restores the CACHED scene arm pose (byte-identical to the
		# shipped view); FRONT is that same pose YAWED 180° in pivot space, so the
		# arm's +Z — the axis a SpringArm3D slides its children along — points
		# ahead of the body instead of behind it. The camera looks down its own
		# −Z, which the same flip turns back toward us: the hero's face in frame
		# and the ground they just covered behind them. Length is untouched, so
		# the front boom is collision-clamped exactly like the back one and can't
		# clip through a block. Nothing writes camera.position (SpringArm gotcha).
		var flip := Basis(Vector3.UP, PI) if view_mode == ViewMode.FRONT else Basis.IDENTITY
		camera_arm.transform = Transform3D(
				flip * third_person_arm_transform.basis, third_person_arm_transform.origin)
		# ...at whichever boom the world currently asks for. SNAPS, because every
		# path into this branch is a deliberate CUT (pressing C, switching hero,
		# a Teibi resize, a respawn) and a cut should land on the right framing
		# immediately. The other way the target changes — walking through a door —
		# is eased instead, by `_tick_arm_length()`; both read
		# `_third_person_arm_target()` so they cannot disagree about the value.
		camera_arm.spring_length = _third_person_arm_target()
		camera.rotation = third_person_camera_rotation
		if character_container:
			character_container.visible = true
	# No shake bookkeeping needed here: the bite shake lives on the camera's
	# h_offset/v_offset, which are view-space and identical in every view.


func set_indoor_camera(indoor: bool) -> void:
	"""
	Tell the camera it is in (or out of) a room. Called by whoever owns the room —
	today only `TowerInterior._update_visibility()`, which already tests the local
	player's position every frame and so pays nothing extra for this.

	IDEMPOTENT AND CHEAP: a no-op when the answer has not changed, so a caller can
	drive it unconditionally from `_process` (and must, since nothing else clears
	it — leaving the room is a call too). Never writes `camera.position`: the knob
	is the SpringArm3D's own `spring_length`, applied through `_apply_view_mode()`.

	IT ONLY MOVES THE TARGET; `_tick_arm_length()` walks the arm there. The tower's
	doorway is a 6 m x 4 m hole and the boom floats 3.5 m up, so it trails straight
	THROUGH the opening with nothing to clamp it — crossing the wall line would
	otherwise cut the camera 4.3 m forward in a single frame, on every entry and
	every exit. (Measured: 8.00 m of horizontal reach a step outside the wall,
	3.74 m a step inside.) That is the one place this is not free.
	"""
	_indoor_camera = indoor


func _refresh_indoor_camera() -> void:
	"""
	Ask the building, right now, whether we are in it — for the callers that
	TELEPORT and cannot wait a frame for its poll to catch up.

	NOT A SECOND OPINION: it calls the same pure `TowerInterior.inside_walls()` the
	building itself calls, on the same offset, so the two can never disagree. That
	is what the static function is for. Null-safe through the usual group seam, so
	a scene with no tower in it (every self-check, and most of a run) simply reads
	"outdoors" — which is the right answer when there is no room to be in.

	Event-rate only: `_apply_view_mode()` is called on presses and teleports, never
	per frame, so the group lookup is not on any budget.
	"""
	if not is_inside_tree():
		return
	var room := get_tree().get_first_node_in_group("tower_interior") as Node3D
	set_indoor_camera(room != null
			and TowerInterior.inside_walls(global_position - room.global_position))


func _third_person_arm_target() -> float:
	"""
	The boom the world is currently asking for: the indoor one while a room holds
	us, the cached scene length otherwise. ONE definition, read by both the snap
	path (`_apply_view_mode`) and the ease path (`_tick_arm_length`).
	"""
	return INDOOR_ARM_LENGTH if _indoor_camera else third_person_arm_length


func _tick_arm_length(delta: float) -> void:
	"""
	Walk the third-person boom toward its target at a fixed metres-per-second rate,
	so a doorway is a short dolly rather than a cut. `move_toward`, not a lerp, for
	the reason the horizontal velocity uses it (SECTION 2): a fixed rate arrives, and
	arrives in a predictable time — 4.4 m at ARM_EASE_SPEED is about a quarter second.

	FIRST PERSON IS SKIPPED ENTIRELY. There the arm is commandeered — zero length,
	identity basis, no collision cast (see `_apply_view_mode`) — and easing it would
	push the camera out of the hero's head. Leaving FP re-snaps through
	`_apply_view_mode`, so nothing to restore here either.
	"""
	if camera_arm == null or view_mode == ViewMode.FIRST_PERSON:
		return
	camera_arm.spring_length = move_toward(
			camera_arm.spring_length, _third_person_arm_target(), ARM_EASE_SPEED * delta)


func _first_person_eye_position() -> Vector3:
	"""
	The first-person eye point as a local position UNDER THE PIVOT (in FP the
	spring arm gets an identity basis, so arm-local == pivot-local and this
	value seats the ARM — the camera rides at its origin). The pivot sits at
	a fixed local height (1.5), so we subtract it from the desired eye height.
	Deriving the scale from the collision capsule means Teibi's small/giant
	forms move the eyes down/up automatically.
	"""
	var scale_y: float = collision_shape.scale.y if collision_shape else 1.0
	# Wading dips the eyes by exactly the same offset the model sinks by, so the
	# submersion is FELT in first person and not merely watched in third. Folded
	# in here rather than at the call sites so every path that re-seats the arm
	# (_apply_view_mode, the Teibi resize, a character switch) gets it for free.
	return Vector3(0.0,
			scale_y * FIRST_PERSON_EYE_HEIGHT - camera_pivot.position.y - _wade_sink, 0.0)


func _tick_wade_sink(delta: float) -> void:
	"""
	Ease the model's submersion offset toward wherever `is_wading` says it should
	be, and apply it. Called once per physics tick from _physics_process, right
	after is_wading is recomputed.

	Note it is BELOW the frozen-window early returns (game over / caught /
	respawn grace), which is deliberate: a player frozen mid-river should stay
	sunk rather than rise out of the water while the countdown runs.
	"""
	var target: float = WADE_SINK_DEPTH if is_wading else 0.0
	if is_equal_approx(_wade_sink, target):
		return
	_wade_sink = move_toward(_wade_sink, target, WADE_SINK_EASE_SPEED * delta)
	_apply_wade_sink()


func _apply_wade_sink() -> void:
	"""
	Push the current submersion offset onto the model — and, in first person,
	onto the spring arm carrying the camera (the eyes ride the same dip).

	Idempotent, like _apply_view_mode(), so it is safe to call from anywhere.
	"""
	if character_container:
		character_container.position.y = -_wade_sink
	if view_mode == ViewMode.FIRST_PERSON and camera_arm:
		# FP gives the arm an identity basis, so only the origin needs re-seating.
		camera_arm.transform = Transform3D(Basis.IDENTITY, _first_person_eye_position())

# ============================================================================
# PHYSICS PROCESSING (CALLED EVERY FRAME)
# ============================================================================

func _physics_process(delta: float) -> void:
	"""
	Called every physics frame (usually 60 times per second).
	This is where we handle movement and physics.

	@param delta: Time elapsed since last frame (in seconds)
	"""

	# STEP 0: First-person toggle (C). POLLED rather than handled in _input() on
	# purpose: the touch UI synthesizes actions via Input.parse_input_event,
	# which polled is_action_just_pressed() sees reliably — same reasoning as the
	# switch_character gotcha in CLAUDE.md. Polled BEFORE the caught/respawn early
	# returns below so a press during those frozen windows isn't silently dropped —
	# the view is a pure camera preference and safe to flip while frozen
	# (_apply_view_mode() only touches the camera rig and model).
	#
	# NOT while the Game Over screen is up, for exactly the reason switch_character
	# carries the same guard: the MP panel deliberately does not pause there, and
	# the lobby's invite-code alphabet contains C (the toggle_camera binding), so
	# typing a code would flip the view. View mode is a preference nothing resets,
	# so the next run would start in the wrong camera with no explanation.
	#
	# C CYCLES three views (third-person → eyes → front/mirror → third-person)
	# rather than toggling two. CONTROLS ARE NEVER MIRRORED WITH THE CAMERA: in
	# the front view A/D and the mouse still turn the BODY the same way they do
	# in third-person, and the camera swings with it. Inverting them to match
	# what the player sees on screen reads clever and plays terribly — the world
	# stops agreeing with the stick. Only the picture is mirrored.
	if Input.is_action_just_pressed("toggle_camera") and not is_game_over:
		view_mode = (view_mode + 1) % ViewMode.size()
		_apply_view_mode()

	# STEP 0-BOOM: walk the camera arm toward the length the world is asking for.
	# ABOVE THE FREEZE BRANCHES, and deliberately NOT beside `_tick_wade_sink()`
	# down at STEP 1.5 even though the two are the same kind of visual ease. The
	# difference is who moves the target: the wade sink's target is OUR OWN
	# position, which cannot change while we are frozen, so a tick there would be a
	# no-op. This one's target is set by the ROOM, which keeps polling through a
	# caught freeze and its 1.5 s of respawn grace — a player caught in the doorway
	# would otherwise sit at the wrong boom, clamped against a wall, for both.
	_tick_arm_length(delta)

	# STEP 0-BENCH: reassign-first / imprison-last, and the room-wide ending. Above
	# the freeze branches for the same reason the recall clock is — the decision is
	# made a beat after a capture, and a capture leaves the body in `is_caught` for
	# the whole CAUGHT_DURATION. A no-op solo (one group lookup and a return).
	_tick_prison(delta)

	# ...and keep a benched player inside the cell block. ABOVE THE FREEZE BRANCHES,
	# which is the whole reason it is here and not beside `move_and_slide()`: the
	# body spends the caught freeze, the respawn grace and the game-over screen
	# below those early returns, and a clamp under them would stop holding at
	# exactly the moments something else is moving the body (a guard's knockback, a
	# respawn placement). The cost is that an excursion is corrected on the NEXT
	# frame rather than the same one — at most one frame of travel, and the
	# correction is absolute, so no amount of speed accumulates a way out.
	_confine_to_block()

	# STEP 0a: Game over — the corporation holds every hero and the break-out was
	# lost. Stand frozen (the Game Over screen is up and the cursor is free) until
	# the player hits "Play Again", which calls restart_game(). We still settle
	# under gravity so we don't hang in the air.
	if is_game_over:
		_freeze_with_gravity(delta)
		anim.update_character_animation(delta, Vector2.ZERO)
		return

	# STEP 0b: If a crocodile just caught us, freeze in place and let the bite +
	# red flash play out for a moment. When the window ends we pay the attacker's
	# coin setback and respawn in place — heroes are the lives, so a bite never ends
	# the run (owner ruling 2026-08-31).
	if is_caught:
		# Same freeze the game-over and respawn-grace branches use: horizontal motion
		# stopped, gravity still applied. Zeroing velocity outright would pin a player
		# bitten at jump apex motionless in mid-air for the whole CAUGHT_DURATION.
		_freeze_with_gravity(delta)
		anim.update_character_animation(delta, Vector2.ZERO)
		caught_timer -= delta
		if caught_timer <= 0.0:
			is_caught = false
			_on_caught_finished()
		return

	# STEP 0c: Post-respawn grace, phase 1 (frozen). We keep standing still and
	# invulnerable (see hit_by_crocodile) while a short countdown runs, then hand
	# control back and start the phase-2 blink i-frames. A final crocodile sweep
	# on the last frame keeps the resume spot clear.
	if is_respawning:
		_freeze_with_gravity(delta)
		anim.update_character_animation(delta, Vector2.ZERO)
		respawn_timer -= delta
		_show_respawn_countdown()
		if respawn_timer <= 0.0:
			is_respawning = false
			_hide_respawn_message()
			clear_nearby_crocodiles(global_position)
			respawn_blink_timer = RESPAWN_BLINK_DURATION
		return

	# STEP 0.35: Post-respawn grace, phase 2 (blinking i-frames). We move
	# NORMALLY — no freeze branch — but stay invulnerable while the timer runs,
	# with the model blinking on a fixed cadence so the protection is readable.
	# First-person skips the toggle (the model is already hidden there); the FRONT
	# view blinks like third-person, since the model is exactly what it shows. When
	# the timer expires, _apply_view_mode() restores visibility idempotently,
	# respecting whichever view we're in.
	if respawn_blink_timer > 0.0:
		respawn_blink_timer = maxf(0.0, respawn_blink_timer - delta)
		if respawn_blink_timer <= 0.0:
			_apply_view_mode()
		elif view_mode != ViewMode.FIRST_PERSON and character_container:
			# One on/off blink per two cadence intervals: visible for the first
			# half of each 2×cadence window, hidden for the second.
			character_container.visible = fmod(respawn_blink_timer, RESPAWN_BLINK_CADENCE * 2.0) < RESPAWN_BLINK_CADENCE

	# STEP 0.4: Record the headline distance score — the farthest horizontal
	# displacement from the spawn point reached this run (see run_distance above
	# for why displacement, not raw X). Spawn is world (0,0) on the XZ plane, so
	# the displacement is just the length of the horizontal position.
	var here := Vector2(global_position.x, global_position.z)
	var travelled: int = int(here.length())
	run_distance = maxi(run_distance, travelled)
	# Measured from own_distance_origin, which is the spawn except after a mid-run
	# join — see that field for why the personal record cannot use `travelled`.
	own_distance = maxi(own_distance, int((here - own_distance_origin).length()))

	# STEP 0.41: Checkpoint those records on a slow timer. See BANK_INTERVAL — a
	# session that never takes a bite must not be lost to a closed tab.
	bank_timer += delta
	if bank_timer >= BANK_INTERVAL:
		bank_timer = 0.0
		_bank_records()

	# STEP 0.42: In a multiplayer room the score fields the two HUDs read become
	# the ROOM's, not this peer's. Done here, immediately after the local
	# distance max above, so this frame's own contribution is already folded in.
	# Costs one group lookup and nothing else when there is no room.
	_refresh_shared_totals()

	# STEP 0.45: Tick the coin-streak window down; when it lapses the streak is
	# over and the score multiplier drops back to x1 (see collect_coin).
	if streak_timer > 0.0:
		streak_timer = maxf(0.0, streak_timer - delta)
		if streak_timer <= 0.0:
			coin_streak = 0

	# STEP 0.5: Tick ability cooldowns / the Windman air boost, then read the F key.
	# Done before gravity so an active boost can soften this frame's fall.
	# If a cheat sequence is armed or a letter was swallowed on this physics frame,
	# skip the poll so typing \fo does not trigger special_ability.
	_update_ability_timers(delta)
	if not _cheat_armed and Engine.get_physics_frames() != _cheat_swallowed_frame:
		if Input.is_action_just_pressed("special_ability"):
			try_activate_ability()

	# STEP 1: Handle Gravity
	# If the character is not on the ground, apply gravity. While Windman's Air Rush
	# is active we soften gravity so he glides and soars on the wind instead of
	# dropping like a stone.
	if not is_on_floor():
		var frame_gravity := gravity
		if windman_boost_timer > 0.0:
			# Feather Fall softens the glide further (`windman_gravity` is a
			# REDUCING effect, capped at −20% inside Progression.skill_mult — see
			# WINDMAN_GRAVITY_MULT_MIN there for the measured arc this produces).
			# Only evaluated for an airborne, boosting Windman, so no other
			# character and no grounded frame pays for the lookup.
			frame_gravity *= WINDMAN_GRAVITY_FACTOR * _skill_mult("windman_gravity")
		# Note: We multiply by delta to make it frame-rate independent
		velocity.y -= frame_gravity * delta
		# Record the fall speed while dropping — move_and_slide zeroes velocity.y
		# the frame we touch down, so the landing squash reads this snapshot.
		if velocity.y < 0.0:
			_fall_speed = -velocity.y

	# STEP 1.5: Are we standing in a river? One noise evaluation per physics tick
	# (see the terrain's is_river_at) — that is the entire budget for wading.
	# Only meaningful with feet on the ground: a jumping or flying player is over
	# the water, not in it.
	#
	# IT MUST STAY ABOVE THE JUMP STEP. Two consumers read it later in this same
	# tick — WADE_JUMP_FACTOR below and calculate_current_speed() at STEP 7 — and
	# computing it after the jump would hand the jump the PREVIOUS frame's answer,
	# which is exactly wrong in the one case that matters: a coyote-time jump one
	# frame after walking off a river bank would be weakened, when the whole point
	# of WADE_JUMP_FACTOR keying off is_wading is that an airborne jump is not one.
	is_wading = is_on_floor() and _terrain_is_river_here()
	# Ease the model's submersion offset (visual only — see WADE_SINK_DEPTH).
	_tick_wade_sink(delta)

	# STEP 2: Handle Jumping (with coyote time + jump buffer — see SECTION 2)
	# Refresh the coyote window while grounded; tick it down while airborne.
	if is_on_floor():
		coyote_timer = COYOTE_TIME
	else:
		coyote_timer = maxf(0.0, coyote_timer - delta)
	# A fresh press arms the buffer; otherwise the buffer ticks down.
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = JUMP_BUFFER_TIME
	else:
		jump_buffer_timer = maxf(0.0, jump_buffer_timer - delta)
	# Fire when a buffered press meets ground OR the coyote window. Giant Teibi
	# is too heavy to leave the ground, so he can't jump while transformed.
	if jump_buffer_timer > 0.0 and (is_on_floor() or coyote_timer > 0.0) and not is_giant:
		# Set upward velocity for jump. Zero BOTH timers so the same press can't
		# fire twice (e.g. a coyote jump immediately re-triggering off the buffer).
		# A jump pushed off from inside a river is weaker (see WADE_JUMP_FACTOR);
		# is_wading is false whenever we are airborne, so a coyote jump that
		# started on dry ground — or off a river bank — keeps full power.
		velocity.y = JUMP_VELOCITY * (WADE_JUMP_FACTOR if is_wading else 1.0)
		coyote_timer = 0.0
		jump_buffer_timer = 0.0
		_sfx("play_jump")

	# STEP 3: Handle Ducking
	handle_ducking()

	# STEP 4: Handle Running — INVERTED. The default gait is RUN and the key SLOWS
	# you (owner ruling 2026-09-03, bead `godot-test1-kov`, verbatim: "let's
	# reverse shift logic, let's it be opposite, heroes always in run mode, and
	# shift put them to slower mode. I am tired to hold shift all the time").
	#
	# THE ACTION NAME "run" IS HISTORICAL and deliberately not renamed: it is the
	# key BINDING (Shift) and nothing about the binding changed, while the name is
	# spelled in project.godot, the keymap card's ACTION_ROWS and every future
	# rebind surface. Renaming buys no runtime behaviour and costs a four-file
	# rename, so the comment is the record instead. Read it as "the gait modifier".
	#
	# Ducking still wins over both, exactly as before — Ctrl beats the modifier and
	# beats the default. `wade_selfcheck` check 5 drives all three through the real
	# action and the shipped calculate_current_speed().
	is_running = not Input.is_action_pressed("run") and not is_ducking

	# STEP 5: Turn the character with Q / E (changes which way it faces)
	handle_turning(delta)

	# STEP 6: Track continuous sidestep with A / D
	update_sidestep(delta)

	# STEP 7: Read forward/back and strafe input and the current movement speed
	# (is_wading was computed back at STEP 1.5, so calculate_current_speed()
	# below already knows about the river underfoot.)
	var input_dir := get_input_direction()
	var current_speed := calculate_current_speed()

	# STEP 8: Build this frame's horizontal velocity from input_dir in local space,
	# rotated into the world by transform.basis. Composed (lateral, forward) is
	# normalized in get_input_direction() so diagonal speed never exceeds current_speed;
	# strafe rides current_speed (walk/run) uniformly with forward movement.
	var planar_velocity := Vector3.ZERO
	if input_dir != Vector2.ZERO:
		var move_dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y))
		planar_velocity = move_dir * current_speed

	if planar_velocity != Vector3.ZERO:
		# Accelerate toward the target velocity instead of snapping to it —
		# see MOVE_ACCELERATION in SECTION 1 for the feel rationale.
		velocity.x = move_toward(velocity.x, planar_velocity.x, MOVE_ACCELERATION * delta)
		velocity.z = move_toward(velocity.z, planar_velocity.z, MOVE_ACCELERATION * delta)
	else:
		# No input: gradually slow down (friction)
		velocity.x = move_toward(velocity.x, 0, current_speed * delta * 10.0)
		velocity.z = move_toward(velocity.z, 0, current_speed * delta * 10.0)

	# STEP 9: Move the character using Godot's built-in physics
	# This handles collisions automatically
	move_and_slide()

	# STEP 10: Update character animations
	anim.update_character_animation(delta, input_dir)

func _process(delta: float) -> void:
	"""
	Per-frame visual camera work that doesn't belong in the physics step:
	the bite shake (random view-space offsets that decay to zero), the eased
	keyboard-turn lag, and the speed-scaled FOV.
	"""
	if not camera:
		return

	# Bite shake — driven through h_offset/v_offset (a view-space slide of the
	# lens), because the SpringArm3D overwrites camera.position every physics
	# frame. Offsets ride on top of whatever the arm decides, in both views.
	if shake_amount > 0.0:
		shake_amount = maxf(0.0, shake_amount - SHAKE_DECAY * delta)
		camera.h_offset = randf_range(-1.0, 1.0) * shake_amount
		camera.v_offset = randf_range(-1.0, 1.0) * shake_amount
	elif camera.h_offset != 0.0 or camera.v_offset != 0.0:
		# Settle exactly back to rest once the shake is done.
		camera.h_offset = 0.0
		camera.v_offset = 0.0

	# Eased keyboard turn: the pivot's yaw holds the lag handle_turning banked,
	# then the lag decays toward zero — so the camera starts behind an A/D turn
	# and smoothly catches up. Mouse turns never bank lag, so they stay 1:1.
	camera_pivot.rotation = Vector3(camera_pitch, camera_yaw_lag, 0.0)
	camera_yaw_lag = lerpf(camera_yaw_lag, 0.0, minf(1.0, CAMERA_TURN_EASE * delta))

	# Speed-scaled FOV: map horizontal speed from WALK_SPEED → Windman's
	# air-rush speed onto FOV_BASE → FOV_MAX, add any transient ability punch,
	# and ease the lens toward it. A Camera3D property, so it applies
	# identically in first- and third-person.
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var speed_blend := clampf(
		(horizontal_speed - WALK_SPEED) / (WINDMAN_AIR_SPEED - WALK_SPEED), 0.0, 1.0)
	var target_fov := lerpf(FOV_BASE, FOV_MAX, speed_blend) + fov_punch
	camera.fov = lerpf(camera.fov, target_fov, minf(1.0, FOV_EASE * delta))
	# The launch punch bleeds off on its own, so the kick reads then settles.
	fov_punch = maxf(0.0, fov_punch - FOV_PUNCH_DECAY * delta)

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

func get_input_direction() -> Vector2:
	"""
	Reads movement input (forward/back and lateral strafe) and returns it as a
	normalized 2D direction vector.

	@return Vector2: x is the lateral strafe axis from A/D (step_left/step_right),
	                 y is the forward/back axis from W/S (move_forward/move_backward).

	EDUCATIONAL NOTE:
	- Input.get_axis() returns a value between -1 and 1.
	- Normalizing the composed 2D vector guarantees diagonal movement never
	  exceeds 1.0 magnitude (the speed contract).
	"""
	var input_x := Input.get_axis("step_left", "step_right") if is_on_floor() else 0.0
	var input_y := Input.get_axis("move_forward", "move_backward")
	var raw_dir := Vector2(input_x, input_y)
	if raw_dir.length_squared() > 1.0:
		return raw_dir.normalized()
	return raw_dir

func calculate_current_speed() -> float:
	"""
	Determines the current movement speed based on character state.

	@return float: Current speed in meters per second

	EDUCATIONAL NOTE:
	- We check states in priority order: air-rush > duck > run > walk
	- Only one state can be active at a time
	"""
	# Windman's Air Rush overrides everything while he is airborne — a wind-fast
	# flight through the sky (~5× walk speed, "Shift pressed five times over").
	# Deliberately BEFORE the wading factor: flying over a river is not wading.
	if windman_boost_timer > 0.0 and not is_on_floor():
		return WINDMAN_AIR_SPEED

	# Each character has a modest speed stat (see CHARACTER_SPEED) that scales
	# every grounded gait. Unknown names fall back to 1.0 — a new character
	# without an entry just moves at baseline speed.
	var char_name: String = CHARACTERS[current_character_index]["name"]
	var speed_scale: float = float(CHARACTER_SPEED.get(char_name, 1.0))

	# Wading through a river drags on every grounded gait (see WADE_SPEED_FACTOR).
	# Folded into the same multiplier so duck/run/walk all slow by the same share.
	if is_wading:
		speed_scale *= WADE_SPEED_FACTOR

	# Passive movement skills (see `_skill_mult`) scale the RUN and DUCK gaits and
	# NOTHING ELSE. That is the catchable-walk contract, restated as code: a
	# walking player has to stay catchable (BASE_CHASE_SPEED 5.5 > WALK_SPEED 5.0,
	# and Primm already walks at 5.75), so no skill may reach the `else` branch
	# below. Deliberately computed HERE, above the branch, so the walk return is
	# textually the only one that does not use it.
	# ONE call, not a product of two: Teibi's Scurry is a movement passive as much
	# as Fleet Foot is, and multiplying two separately-capped multipliers reaches
	# x1.254 — past the +20% both halves individually respect. `gait_mult()` sums
	# the bonuses and clamps once, which is why the small-form test is a parameter
	# rather than a second multiplication here.
	var gait_mult: float = _skill_gait_mult()

	if is_ducking:
		return DUCK_SPEED * speed_scale * gait_mult
	elif is_running:
		# The wading drag applies here too, but never below WADE_RUN_MIN_SPEED:
		# running has to keep outpacing a chasing crocodile even in the water.
		#
		# AS THE CONSTANTS STAND THE FLOOR ALWAYS WINS: the fastest character is
		# 10.0 * 1.15 * 0.6 = 6.9, under the 9.0 floor, so EVERY character runs at
		# exactly 9.0 while wading and the drag is fully absorbed. The maxf stays
		# as the general expression — retune CHARACTER_SPEED or WADE_SPEED_FACTOR
		# and the drag starts biting again without this line needing a thought.
		#
		# The skill multiplier goes INSIDE the maxf, i.e. it is applied BEFORE the
		# floor, which is what keeps the floor a floor: skills only ever raise this
		# number, so the result is still at least WADE_RUN_MIN_SPEED and a speed
		# passive cannot re-open the river-trap bug the floor exists to close.
		if is_wading:
			return maxf(RUN_SPEED * speed_scale * gait_mult, WADE_RUN_MIN_SPEED)
		return RUN_SPEED * speed_scale * gait_mult
	else:
		# NO `gait_mult` HERE, ever. See the comment above the branch.
		return WALK_SPEED * speed_scale

func handle_ducking() -> void:
	"""
	Handles the ducking mechanic.

	EDUCATIONAL NOTE:
	- Ducking makes the character shorter by scaling the mesh
	- In a real game, you'd also shrink the collision shape
	- This is a visual-only implementation for learning purposes
	"""
	var target_scale_y: float = original_scale_y

	if Input.is_action_pressed("duck") and is_on_floor():
		is_ducking = true
		target_scale_y = original_scale_y * 0.5  # Duck to 50% height
	else:
		is_ducking = false
		target_scale_y = original_scale_y  # Return to normal height

	# Smoothly interpolate the scale for a nice ducking animation
	if mesh_instance:
		mesh_instance.scale.y = lerp(mesh_instance.scale.y, target_scale_y, 0.1)

func handle_turning(delta: float) -> void:
	"""
	Rotate the whole character left/right with Q and E.

	Q and E change which way the character is *facing*, like the tank-style
	steering in classic adventure games. Whatever direction the body ends up
	pointing is the direction W will walk. (The mouse can still turn the body
	too; the two just add together.)

	@param delta: Time since last frame, so the turn rate is frame-rate independent
	"""
	# +1 when turning left (Q), -1 when turning right (E).
	var turn_input := Input.get_axis("turn_right", "turn_left")
	if absf(turn_input) > 0.01:
		# A positive angle spins counter-clockwise around +Y, i.e. to the
		# character's left — which matches Q producing a positive turn_input.
		var turn_delta := turn_input * TURN_SPEED * delta
		rotate_y(turn_delta)
		# Bank the same turn as camera lag: the pivot counter-rotates by it and
		# eases back to zero in _process, so the camera trails the keyboard
		# turn instead of snapping with the body. (Mouse turns happen in
		# _input and never touch this, keeping mouse look 1:1.)
		camera_yaw_lag -= turn_delta

func update_sidestep(_delta: float) -> void:
	"""
	Manage continuous sidestep / strafe triggered by A (left) and D (right).

	A/D strafe smoothly for as long as held while grounded. When released,
	when airborne, or when forward/backward movement (W/S) takes over the
	animation, resets the sidestep limb roll so key order never leaves
	a stuck lean.
	"""
	if not is_on_floor():
		if is_stepping:
			is_stepping = false
			step_direction = 0.0
			anim.reset_sidestep_pose()
		return

	var step_axis := Input.get_axis("step_left", "step_right")
	var moving_fwd := absf(Input.get_axis("move_forward", "move_backward")) > 0.01
	if absf(step_axis) > 0.01:
		is_stepping = true
		step_direction = step_axis
		if moving_fwd:
			# Forward/backward motion uses the standard walk/run animation cycle;
			# clear the lateral roll pose so W+A and A+W share the identical clean walk.
			anim.reset_sidestep_pose()
	elif is_stepping:
		is_stepping = false
		step_direction = 0.0
		anim.reset_sidestep_pose()

# ============================================================================
# DEBUG AND UTILITY FUNCTIONS
# ============================================================================

func _to_string() -> String:
	"""
	Returns a string representation of the player's current state.
	Useful for debugging.
	"""
	return "Player[Speed: %s, OnFloor: %s, Velocity: %s]" % [
		calculate_current_speed(),
		is_on_floor(),
		velocity
	]

# ============================================================================
# CHARACTER SWITCHING FUNCTIONS
# ============================================================================

func switch_to_next_character() -> void:
	"""
	Switches to the next character in the cycle:
	windman -> primm -> teibi -> phoboman -> windman (loops)

	This is now just a visibility swap between already-instanced models, so it
	happens instantly with no loading hitch.

	IN A MULTIPLAYER ROOM the lobby owns who plays which hero, so the cycle is
	restricted to the characters this peer was assigned (see below).
	"""
	# Which characters may we step to? `reachable_character_indices()` — the lobby's
	# hand INTERSECT free, PLUS (in a room) every free hero NOBODY holds, because
	# those are the ones switch_to_character() now claims through the lobby rather
	# than refusing (bead godot-test1-4zw). Solo, with nobody taken,
	# it answers all four and the cycle below is arithmetically the plain
	# `(i + 1) % size` it has always been, which is why the old `== null` branch is
	# gone rather than kept beside it: two spellings of one increment is how the
	# captive filter would end up applied to one of them and not the other.
	var indices := reachable_character_indices()

	# THIS FUNCTION ONLY PICKS AN INDEX — every guard, and the refusal feedback,
	# live in switch_to_character(). A hand of 0 or 1 has no "next" hero, so the
	# next hero is the one we already are, which that function refuses with the
	# flash: the singleton-hand refusal (a room member, or a player down to his
	# last free hero) is unchanged, it just no longer has its own spelling here.
	var next_index: int = current_character_index
	if indices.size() > 1:
		# find() returning -1 wraps to the first allowed entry, which is the right
		# answer when we are not currently in any of them.
		var slot: int = indices.find(current_character_index)
		next_index = int(indices[(slot + 1) % indices.size()])
	switch_to_character(next_index)


func switch_to_character(index: int) -> bool:
	"""
	BECOME this hero, if we are allowed to. The ONE switch primitive the player's
	own input goes through: R computes the next index and calls it, and the 1-4
	hotkeys pass their index straight in (bead godot-test1-hpv). Both therefore
	obey the same two ability guards and the same availability filter, and neither
	can grow a second, laxer spelling of the rules.

	NOT the lowest layer: `set_active_character()` is, and the lobby still calls
	THAT directly (mp_manager._apply_my_hero) because a confirmed hero assignment
	is not asking permission. This function is the layer that asks.

	@param index: index into CHARACTERS
	@return: true if we actually switched
	"""
	# Block switching while a prolonged ability (flying/resize) is active. Silent,
	# not a flash: the press is not "denied", it is "not yet".
	if windman_boost_timer > 0.0 or teibi_size_state != 0:
		return false

	# WHO HOLDS THE HERO THIS PRESS ASKS FOR, per the lobby — "" when nobody does,
	# and "" for every hero when there is no room. That plus the two index sets
	# below is everything the rule needs, so the rule itself is the pure static
	# `decide_switch()` and this function is only the ACTION.
	#
	# A player with no lobby verbs to reach (solo, or a scene with a stubbed
	# manager) can claim nothing, so it offers an EMPTY claimable set and the
	# decision degrades to exactly the two verdicts it has always had.
	var mp := _mp()
	var can_claim: bool = mp != null and mp.has_method("hero_holder") \
			and mp.has_method("claim_hero")
	var holder: String = ""
	if can_claim and index >= 0 and index < CHARACTERS.size():
		holder = String(mp.hero_holder(String(CHARACTERS[index]["name"])))
	var claimable: Array = free_character_indices() if can_claim else []

	match decide_switch(index, current_character_index,
			available_character_indices(), claimable, holder):
		SWITCH_LOCAL:
			# Show the newly selected character
			set_active_character(index)
			print("Switched to character: %s" % CHARACTERS[index]["name"])
			return true
		SWITCH_CLAIM:
			# ASK THE LOBBY, DO NOT MOVE (bead godot-test1-4zw). `claim_hero()`
			# changes nothing locally by contract: the body swaps when the room's
			# `heroes` broadcast confirms it, through `mp_manager._apply_my_hero`,
			# which is the same path the initial auto-claim and the capture-time
			# reassignment already take. So two peers pressing the same key in one
			# frame serialize on the lobby's room lock — one wins, the loser keeps
			# its hero and gets the status line, and neither ever half-switches.
			mp.claim_hero(String(CHARACTERS[index]["name"]))
			return true
		_:
			# Give a refused press the SAME dial flash and denial buzz a refused F
			# press gets, so the player reads "this hero is locked" rather than
			# "the key is broken". Pressing the hero you already are lands here
			# too — nothing happens either way, and the flash is what says so.
			_flash_blocked_feedback()
			return false


## `decide_switch()`'s three verdicts: refuse the press, swap the body here and
## now, or ask the lobby for the hero and let its broadcast do the swapping.
const SWITCH_REFUSE: int = 0
const SWITCH_LOCAL: int = 1
const SWITCH_CLAIM: int = 2


static func decide_switch(index: int, current: int, available: Array,
		claimable: Array, holder: String) -> int:
	"""
	What a hero press means. THE WHOLE RULE, as a pure function of four facts —
	no node lookups, no side effects — so scripts/mp_selfcheck.gd can pin all
	four cases without a lobby, a room or a player in a tree.

	@param index: the CHARACTERS index pressed (R computed it, or 1-4 passed it).
	@param current: the hero we are already walking as.
	@param available: `available_character_indices()` — the lobby's hand
	    INTERSECT free. Solo that is every hero nobody has captive.
	@param claimable: the free heroes we may ASK the lobby for —
	    `free_character_indices()` in a room, EMPTY with no lobby to ask.
	@param holder: the lobby id holding `index`'s hero, "" when nobody does.
	@return: one of SWITCH_REFUSE / SWITCH_LOCAL / SWITCH_CLAIM.

	The four cases, in the order they are decided:

	  1. Out of range, or the hero we already are  -> REFUSE (the flash).
	  2. In our hand                               -> LOCAL, no round trip.
	  3. Free, not in our hand, and UNHELD         -> CLAIM through the lobby.
	  4. Held by a teammate, or in a cell          -> REFUSE. Nothing is stolen
	     and nothing is sent; a captive hero is nobody's to ask for, his own
	     holder included, which is why case 3 tests `claimable` and not `holder`
	     alone.
	"""
	if index < 0 or index >= CHARACTERS.size() or index == current:
		return SWITCH_REFUSE
	if available.has(index):
		return SWITCH_LOCAL
	if claimable.has(index) and holder.is_empty():
		return SWITCH_CLAIM
	return SWITCH_REFUSE


func reachable_character_indices() -> Array:
	"""
	Every hero a PRESS can reach right now: `available_character_indices()` plus,
	in a room, the free heroes nobody holds — the ones `switch_to_character()`
	claims through the lobby instead of refusing (bead godot-test1-4zw).

	@return: A fresh Array of int in CHARACTERS order — possibly empty.

	R cycles this and `hero_hud` dims what is NOT in it, so the cycle, the HUD
	and the primitive's own verdict cannot disagree about which tile is pressable.
	Solo — and in any scene with no MP manager — it is exactly
	`available_character_indices()`, so nothing off-line changes.
	"""
	var available := available_character_indices()
	var mp := _mp()
	if mp == null or not mp.has_method("hero_holder") or not mp.has_method("claim_hero"):
		return available
	var free := free_character_indices()
	var out: Array = []
	# Walked in CHARACTERS order, which is the order both inputs are already in,
	# so the union is still the stable cycle order R steps through.
	for index: int in CHARACTERS.size():
		if available.has(index) \
				or (free.has(index) \
					and String(mp.hero_holder(String(CHARACTERS[index]["name"]))).is_empty()):
			out.append(index)
	return out


# ---------------------------------------------------------------------------
# THE CAPTIVE SET — capture, liberation, and what is left to play
# ---------------------------------------------------------------------------

func available_character_indices() -> Array:
	"""
	Who this player may actually BE right now: the lobby's hand INTERSECT free.

	@return: A fresh Array of int, in `CHARACTERS` order — possibly empty.

	THE ONE SITE WHERE THE TWO RESTRICTIONS MEET, and everything that asks "which
	heroes are left" asks it here: the E-cycle, the capture-time auto-switch and
	the end-of-run test. Splitting them is how the auto-switch ends up stepping a
	peer into a teammate's hero, or how a room ends a run this player could still
	have played.

	`my_character_indices()` answers `null` — offline, no room, or holding no hero
	yet — meaning "all of them", so solo this is exactly `free_character_indices()`
	and with nobody captive it is all four in order.
	"""
	var free := free_character_indices()
	var mp := _mp()
	var allowed: Variant = null
	if mp and mp.has_method("my_character_indices"):
		allowed = mp.my_character_indices()
	if allowed == null:
		return free
	var out: Array = []
	# Walked in `free` order rather than the lobby's, so the cycle E steps through
	# is stable however the room happened to hand the heroes out.
	for index: int in free:
		if (allowed as Array).has(index):
			out.append(index)
	return out


func free_character_indices() -> Array:
	"""
	Every `CHARACTERS` index whose hero is not in a cell, in cycle order.

	@return: A fresh Array of int — the caller may keep or mutate it.

	Half of `available_character_indices()`, and the ONLY thing that reads
	`captive_heroes` outside the two verbs that write it. Everything in gameplay
	goes through the intersection instead — the raw free set answers "who is not in
	a cell", which is not the same question as "who may I play".
	"""
	var out: Array = []
	for index: int in CHARACTERS.size():
		if not captive_heroes.has(String(CHARACTERS[index]["name"])):
			out.append(index)
	return out


func free_hero_count() -> int:
	"""
	How many heroes are still playable. THE HUNT DIRECTOR'S ROSTER SEAM.

	@return: 0 .. CHARACTERS.size().

	Death-spiral mitigation belongs in the hunt encounter director
	(`hunt_director.gd`, bead godot-test1-9rm.4) and NOT in the capture path —
	bead godot-test1-3iy.9's landmine, and session-02 doctrine underneath it: a
	player down to one hero should meet FEWER commitments, because mercy BEFORE
	contact is invisible and mercy DURING contact is a pulled punch the player can
	feel. So this path publishes the number and does nothing with it; the director
	reads it through the same null-safe group lookup it uses for everything else,
	and scales `ENGAGE_LULL` off it when that tuning lands. Deliberately a count
	and not the set: a mercy dial has no business knowing WHO is missing.
	"""
	return free_character_indices().size()


func is_hero_captive(hero: String) -> bool:
	"""Is this hero in a cell right now? @param hero: a `CHARACTERS` name."""
	return captive_heroes.has(hero)


func hero_freed(hero: String) -> void:
	"""
	The cell block freed somebody. Put him back in the E-cycle.

	@param hero: One of the `CHARACTERS` names.

	`TowerInterior._liberate()` calls this — null-safe, so the seam predates this
	bead — the moment ANY hero walks into an occupied cell. Idempotent, which is
	what makes the tower's mirror safe to re-drive: freeing somebody who is not
	held is a no-op, and so is freeing the authored captive, who was never in this
	set (he is the tower's staging, not a hero the field took off you).

	IN A ROOM IT IS ALSO A BROADCAST. The captive set is room-wide there (bead
	godot-test1-3iy.10), so a liberation has to reach the peer who lost that hero -
	it is what ends their prison role - and it reaches them the same way the
	capture did. A no-op offline, and idempotent on both sides.
	"""
	# ONLY A REAL RELEASE IS REPORTED, and `erase()`'s own answer is the test. The
	# tower calls this for the AUTHORED captive too — staging this player never had
	# taken off them — and telling the room about that would leave a release
	# tombstone on a hero nobody had captured. The very next thing that rescue
	# enables is hunter captures, so a genuine grab of that hero inside
	# RELEASE_GRACE_MSEC would then be dropped as the stale packet it is not, and
	# the room would never hear about it at all.
	if not captive_heroes.erase(hero):
		return
	var mp := _mp()
	if mp != null and mp.has_method("report_hero_freed"):
		mp.call("report_hero_freed", hero)


func set_hero_captive(hero: String, held: bool) -> void:
	"""
	THE ROOM'S MIRROR: a teammate's capture or liberation, applied to our copy.

	@param hero: one of the `CHARACTERS` names, already whitelisted against the
	    lobby's pool by `MpManager._apply_captive()`.
	@param held: true when the room says he is in a cell.

	The only thing `MpManager` calls on the player for the captive set, and it
	writes exactly what a local capture writes MINUS the local consequences - no
	auto-switch, no reassignment, no sting. Those belong to the peer who lost the
	hero; this is the other three peers learning about it, and for them a captured
	teammate is a name that leaves the roster and a cell frame that lights up.
	"""
	if held:
		captive_heroes[hero] = true
	else:
		captive_heroes.erase(hero)
	# Same null-safe seam a local capture uses, for the same reason: the tower is a
	# streamed landmark and is usually not in the tree when a grab lands anywhere in
	# the room, so `TowerInterior` re-seeds its mirror from this set on build.
	var interior := get_tree().get_first_node_in_group("tower_interior")
	if interior != null and interior.has_method("set_captive"):
		interior.call("set_captive", hero, held)


func _capture_active_hero() -> void:
	"""
	A GD-SURVEY machine earned its grab — the field's retrieval unit or the HQ's
	sentry, whichever row carried `captures_hero` — and the corporation keeps
	whoever was walking.

	THE HERO IS THE STAKE ON TOP OF THE BILL, NOT INSTEAD OF IT (bead
	godot-test1-0bc). Every predator in the table now charges `coin_setback`, the
	hunter at the top rate of the lot (0.25) — a grab you escaped is meant to cost
	the most — and this function still touches neither `coins_collected`, nor
	`coin_streak`, nor the bank. That is a matter of WHERE, not of whether: the coin
	bill is latched in `hit_by_crocodile()` and paid in `_on_caught_finished()`, one
	site for every contact in the game, so a capture that billed here would bill
	twice. The freeze is the same ordinary contact cost (a hunter's grab is not a
	pulled punch); what makes it a CAPTURE is this set.

	AUTO-SWITCH GOES THROUGH `set_active_character()`, NEVER THROUGH
	`switch_to_next_character()`, for two independent reasons and either one alone
	would be enough. First, the cycle REFUSES a press while a prolonged ability is
	running (Air Rush, giant Teibi) — a hunter that grabs a flying Windman must not
	be denied its catch. Second, and this is the landmine: `set_active_character()`
	is where `_reset_ability_states()` lives, so the body that walks away from the
	grab has clean transient state and no power bleeds across a capture. It is the
	same path the lobby's hero split uses for the same reason.
	"""
	var hero := hero_name()
	if captive_heroes.has(hero):
		return
	captive_heroes[hero] = true
	print("Captured by GD-SURVEY: %s" % hero)

	# THE CELL BLOCK IS THE WAY BACK, so it has to know who it is holding — its
	# `_liberate()` early-returns on a hero it has no record of, and a captive with
	# no cell can never be freed. Null-safe group lookup: the tower is a streamed
	# landmark and is usually not in the tree at all when a field grab lands, which
	# is exactly why `TowerInterior` re-seeds its mirror from this set on build.
	var interior := get_tree().get_first_node_in_group("tower_interior")
	if interior and interior.has_method("set_captive"):
		interior.set_captive(hero, true)

	# TELL THE ROOM, BEFORE ANYTHING IS DECIDED ABOUT IT. In a room the captive set
	# is room-wide (bead godot-test1-3iy.10) - nobody may pick a hero who is in a
	# cell, and the run ends when the ROOM has none left - so the assertion goes out
	# first and the reassignment below is decided against a truth every peer now
	# shares. A no-op offline.
	var mp := _mp()
	if mp != null and mp.has_method("report_hero_captured"):
		mp.call("report_hero_captured", hero)

	# NEITHER THE REASSIGNMENT NOR THE BENCH IS DECIDED HERE, and that is a
	# correctness rule rather than tidiness. `SetHero` releases our claim on the
	# hero just taken, so a claim sent from this line races the `cap` packet on
	# every other peer: whoever sees the lobby's `heroes` broadcast first no longer
	# has us down as that hero's holder and drops the capture, and the room's
	# captive sets diverge for the rest of the run. `_tick_prison()` sends it half a
	# second later - inside the caught freeze, so nothing is visibly slower - by
	# which time every peer has the capture.

	# ...and step into the next AVAILABLE hero on the spot, while the unit
	# withdraws. Available, not merely free: in a room the lobby owns who plays
	# whom, and a capture that stepped this peer into a teammate's hero would break
	# that assignment far more loudly than the capture itself. Nothing to step to
	# is game over, decided in `_on_caught_finished()` where every other
	# end-of-run branch is decided — not here.
	var available := available_character_indices()
	for offset: int in CHARACTERS.size():
		var index: int = (current_character_index + 1 + offset) % CHARACTERS.size()
		if available.has(index):
			set_active_character(index)
			return


func _takes_a_hero(attacker: Node) -> bool:
	"""
	Was this contact an ARREST rather than an animal's bite?

	@param attacker: whoever called `hit_by_crocodile`, or null when nobody said.
	@return: the attacker's `captures_hero` row key, false for a body without one.

	A ROW KEY, NEVER THE BEHAVIOUR AND NEVER A SPECIES NAME (bead
	godot-test1-3iy.19). It used to read `behavior == "hunt"`, which quietly tied
	"the corporation imprisons you" to how a body STEERS: the tower guard is the
	same GD-SURVEY chassis on a different duty, and to the owner a catch inside
	the HQ is a catch — but a sentry leashed to one storey by `set_confinement()`
	must not have the hunt arm's scent tracking or its hunt-director seams. So
	what a body does with the quarry it catches is its own key, the same
	data-not-species shape as `stink_immune` / `crush_immune` / `sweep_exempt` and
	`_coin_setback_of` below.

	Read off the row through `Node.get()`, which answers null for a body that has
	no `spec` at all (a boss projectile, the tower's press), so every other
	damage source falls through to the predator arithmetic.
	"""
	if attacker == null:
		return false
	var row: Variant = attacker.get("spec")
	return row is Dictionary and bool((row as Dictionary).get("captures_hero", false))


func _coin_setback_of(attacker: Node) -> float:
	"""
	What fraction of this player's coins does the thing that just hit us take?

	@param attacker: whoever called `hit_by_crocodile`, or null when nobody said.
	@return: every predator's own `coin_setback`, and `DEFAULT_COIN_SETBACK` for a
	         hit with no SPECIES row behind it.

	KEYED ON A ROW KEY, NOT ON A SPECIES NAME — the third time this file asks the
	attacker a question and the third time the answer is data (see
	`_takes_a_hero` above, and `stink_immune` / `crush_immune` in the AI). A new
	predator sets its own price by editing its row and nothing here changes.

	AND IT IS THE FRACTION, NOT A BOOLEAN, so this file holds no percentage of its
	own: "one arithmetic everywhere" means the number lives in exactly one place
	(the row) and is spent in exactly one place (`_pay_coin_setback`). Read
	through `Node.get()`, which answers null for a body with no `spec` at all — the
	tower's press, a boss projectile — and THAT is the one case with no row to
	read, so it falls to the named default rather than to a free hit.

	CLAMPED TO [0, 1] AT THE READ. A hand-edited or mis-typed row cannot make a hit
	refund coins or take more than there are, and the clamp being here rather than
	at the spend is what keeps the spend a single subtraction.
	"""
	if attacker == null:
		return DEFAULT_COIN_SETBACK
	var row: Variant = attacker.get("spec")
	if not (row is Dictionary):
		return DEFAULT_COIN_SETBACK
	return clampf(float((row as Dictionary).get("coin_setback", DEFAULT_COIN_SETBACK)), 0.0, 1.0)


func _is_sweep_exempt(body: Node) -> bool:
	"""
	Is this body authored furniture the respawn sweep must not free?

	@param body: any node in group `"crocodile"`.
	@return: the body's `sweep_exempt` row key, false for a body with no row.

	A ROW KEY, NEVER A SPECIES NAME, the same shape as `stink_immune` /
	`crush_immune` in the AI and for the same reason: the next authored body opts
	in by editing its row and `clear_nearby_crocodiles()` never changes. It used to
	be inferred from `coin_setback` being non-zero, which worked only while the
	guard was the sole row carrying that key — every predator bills coins now, so
	the inference matches the whole world and the property has to say its own name.
	"""
	if body == null:
		return false
	var row: Variant = body.get("spec")
	return row is Dictionary and bool((row as Dictionary).get("sweep_exempt", false))


func _pay_coin_setback(fraction: float) -> bool:
	"""
	Settle the bill for the hit that just landed: a slice of the run's coins, and
	— while standing inside the tower's walls — the ground back to the last
	checkpoint.

	@param fraction: the attacker's `coin_setback`, already clamped to [0, 1].
	@return: true if we RELOCATED, which tells `_on_caught_finished()` to skip the
	         ordinary respawn (see the tail of this function for why).

	NO LIFE IS SPENT AND NO RUN CAN END HERE, because there is no longer any such
	thing: heroes are the lives (owner ruling 2026-08-31) and the only ending left
	is the free-hero set going empty, which `_on_caught_finished()` tests after
	calling this.

	THE COINS COME OFF `own_coins`, WHICH IS THIS PEER'S OWN STAKE. Solo the two
	fields are identical and this is simply "that fraction of your coins". In a ROOM
	`coins_collected` is the whole room's bank (see `_refresh_shared_totals`), and
	billing a fraction of four players' bank to one player's contribution could
	drive `own_coins` negative and make the shared total drift. So the fraction is
	taken of what this player actually put in, and the SAME number comes off the
	displayed figure so the HUD moves on the frame the hit lands rather than on the
	next shared recompute.

	LIFETIME COINS ARE NEVER TOUCHED. `progression.gd`'s count and
	`best_run_store.gd`'s records are monotone by design (every persistence layer
	merges with a plain `max`), so the setback is a RUN-side tax and nothing here
	reaches either of them.

	NOTHING IS SWEPT. `clear_nearby_crocodiles()` frees bodies, and a guard is
	authored furniture rather than spawn clutter — see the exemption there. The
	grace freeze plus the blink i-frames are what keep the landing safe, and the
	checkpoint is safe by construction anyway: no guard's patrol box reaches it.
	"""
	caught_setback = 0.0
	var arrested: bool = caught_captured
	caught_captured = false
	var lost: int = int(floor(float(own_coins) * fraction))
	# THE PEAK, SNAPSHOTTED BEFORE THE BILL. This is the only place `own_coins`
	# ever goes down, so remembering it here is the whole of peak tracking — and it
	# has to happen HERE rather than in `_bank_records()`, which `_on_caught_finished`
	# calls immediately AFTER this bill and which would otherwise bank the balance
	# the player was left with instead of the one the HUD showed (bead godot-test1-h6x).
	record_coins = maxi(record_coins, own_coins)
	own_coins = maxi(0, own_coins - lost)
	coins_collected = maxi(0, coins_collected - lost)

	# THE KNOCKBACK, AND IT IS THE TOWER'S ALONE. Null-safe group lookup with a
	# `has_method` guard, the project's no-hard-references convention — and then
	# `inside_walls()`, the SAME predicate the indoor camera reads three hundred
	# lines up, because the group answering is not the question. The shell is
	# streamed in at TOWER_LOAD_RADIUS (360 m) and never freed for the rest of the
	# run, so once a player has been anywhere near the HQ the node is in the tree
	# forever: testing for it alone would teleport every field bite in the world
	# back to the doorway. That was invisible while the guard was the only row
	# carrying a `coin_setback`; the bill going universal is what made the lookup
	# fire everywhere.
	#
	# AND NEVER FOR A PRISONER, the same refusal `_respawn_in_place()` already
	# carries and for the same reason one storey further on. A benched peer stands
	# in a cell on storey 9, which is inside the walls, so a guard's bite — or the
	# block's press — would knock them to the checkpoint plate ten storeys below;
	# `_confine_to_block()` clamps x and z but deliberately not y, so the next frame
	# drags them back into the block's column at ground level, under the block, with
	# no ramp inside the clamp. The role is then unplayable for the rest of the run:
	# they can free nobody and work no purge, which is the only way their hero
	# returns.
	#
	# AND NEVER WHEN THE CONTACT WAS AN ARREST (owner ruling 2026-09-01, bead
	# godot-test1-3iy.19). A guard's grab now imprisons the hero exactly as a field
	# hunter's does, and the ruling's second half is that the heroes still free
	# "continue to play from the same place after cooldown" — so the hero that
	# steps in stands where the party fell, on the storey the arrest happened on,
	# which is also the way back to the cells. Relocating them as well would charge
	# a second penalty nobody ruled for the one contact that already charges the
	# expensive one. The coin bill above is deliberately NOT waived: one arithmetic
	# everywhere. The latch is `hit_by_crocodile()`'s, because by now the attacker
	# is gone and there is nothing left here to ask.
	var interior := get_tree().get_first_node_in_group("tower_interior") as Node3D
	if arrested or prisoner_active or interior == null \
			or not interior.has_method("setback_point") \
			or not TowerInterior.inside_walls(global_position - interior.global_position):
		print("Setback: -%d coins" % lost)
		return false
	global_position = interior.call("setback_point")

	# ...and the same landing every other respawn gets: clean ability state, a
	# frozen grace window, then the blinking i-frames. Written out rather than
	# routed through `_respawn_in_place()` because that function's first act is to
	# relocate a player to the room's group anchor, which would throw the knockback
	# we just made straight across the map — which is also why we report the
	# relocation to the caller, so it skips the respawn it would otherwise run.
	_reset_ability_states()
	velocity = Vector3.ZERO
	is_ducking = false
	is_running = false
	is_respawning = true
	respawn_timer = RESPAWN_GRACE_DURATION
	print("Setback: -%d coins, back to the checkpoint" % lost)
	return true


func _capture_is_armed() -> bool:
	"""
	May a hunter take a hero yet? Only after the authored Primm rescue.

	@return: true once `TowerInterior.RESCUE_DONE` is in the stored tower set.

	OWNER-RULED SEQUENCING: the authored beat is where the rule is TAUGHT, so
	before it a grab costs the ordinary predator arithmetic and nothing else — a
	systemic mechanic that fires before the scene that explains it reads as a bug.

	Read from the store rather than from the tower, because the tower is a streamed
	landmark and a grab in the field is nowhere near it, while `TowerShell.mark_opened()`
	writes through to disk on the opening itself. One `ConfigFile` read per grab.
	ponytail: cache it if capture ever stops being a once-in-a-run event — the
	answer only changes at the beat, which happens inside the building.
	"""
	return BestRunStore.tower_opened_ids().has(TowerInterior.RESCUE_DONE)


func preload_all_characters() -> void:
	"""
	Instance all characters a single time and park them (hidden) under the
	character container.

	Doing the expensive load + instance + outline work here, once at startup,
	means switching characters later (set_active_character) is just a visibility
	toggle. That removes the per-press hitch that used to come from re-loading
	and re-instancing a model — especially windman, which is 11 separate meshes.
	"""
	if not character_container:
		push_error("Character container node not found")
		return

	for index in CHARACTERS.size():
		var scene_path: String = CHARACTERS[index]["scene_path"]
		var character_scene := load(scene_path) as PackedScene
		if not character_scene:
			push_error("Failed to load character scene: %s" % scene_path)
			character_instances.append(null)
			character_rest_poses.append({})
			continue

		# Instance it, hide it, and add it to the container.
		var instance := character_scene.instantiate()
		character_container.add_child(instance)
		instance.visible = false

		# Give it the cel-shaded style (outline + toon/rim) and remember its rest
		# pose while limbs are still untouched (so re-activation never drifts it).
		anim.apply_character_style(instance)
		character_instances.append(instance)
		character_rest_poses.append(anim.capture_rest_pose(instance))

		print("Preloaded character: %s" % CHARACTERS[index]["name"])

func set_active_character(index: int) -> void:
	"""
	Make one preloaded character visible and route the animation system to it.
	Switching is instant because every character already exists in the tree.

	@param index: Index in the CHARACTERS array
	"""
	if index < 0 or index >= character_instances.size():
		push_error("Invalid character index: %d" % index)
		return

	current_character_index = index

	# Show only the chosen character; hide the rest.
	for i in character_instances.size():
		if character_instances[i]:
			character_instances[i].visible = (i == index)

	current_character_node = character_instances[index]
	if not current_character_node:
		return

	# Point the animation system at this character: limb references, the cached
	# rest pose, this hero's gait row and the footstep tracker's reset, all in
	# `PlayerAnimation.activate_character()` (bd godot-test1-ftn.9).
	anim.activate_character(index)

	# A freshly selected character always starts with NO transient ability state:
	# not Teibi's resize (a different character would inherit the giant body or
	# the shrunken capsule) and not Windman's air boost, which is read off a timer
	# rather than off the character — so a body swapped mid-Air-Rush would keep
	# flying at WINDMAN_AIR_SPEED under softened gravity as somebody else.
	# switch_to_next_character() refuses a mid-ability press, but the multiplayer
	# hero split calls in here directly (mp_manager._apply_my_hero) and the lobby
	# is not asking permission, so the clear has to live at this end.
	# _reset_ability_states() calls _revert_teibi_to_normal(), which re-applies
	# the first-person view when active (_apply_teibi_scale ends with
	# `if view_mode == ViewMode.FIRST_PERSON: _apply_view_mode()`), keeping the model hidden and the
	# camera at the eyes across the switch.
	_reset_ability_states()

func _sfx(method: String, arg: Variant = null) -> void:
	"""
	Fire one SoundManager one-shot (e.g. "play_jump") via the "sound_manager"
	group — null-safe like the hit_flash pattern, so a scene run without Main
	just stays silent instead of erroring.
	"""
	var sm := get_tree().get_first_node_in_group("sound_manager")
	if sm and sm.has_method(method):
		if arg == null:
			sm.call(method)
		else:
			sm.call(method, arg)

# ============================================================================
# SECTION 7: GAME STATE METHODS
# ============================================================================

func collect_coin(value: int = 1) -> void:
	"""
	Add a pickup's worth to the coin count. Called by a coin's Area3D when the
	player touches it (see coin.gd) — a plain coin passes 1, a purple gem passes
	its GEM_VALUE (10). The HUD picks up the new value on its next frame.

	One bonus happens here — STREAK: each pickup refreshes the streak window; the
	pickup's value is multiplied by the current streak multiplier (see
	get_streak_multiplier). The streak counts *pickups*, not value — a gem is one
	link in the chain. Coins buy nothing else: the thresholds that used to grant
	extra lives went with the hearts (owner ruling 2026-08-31), and coins are now
	purely the score and the thing a bite takes away.
	"""
	streak_timer = STREAK_WINDOW
	coin_streak += 1
	_maybe_start_speed_burst()
	coins_collected += value * get_streak_multiplier()
	# The same multiplied value, banked again as THIS peer's contribution to a
	# multiplayer room (see own_coins). Untouched by the shared recompute, which
	# overwrites coins_collected but never this.
	own_coins += value * get_streak_multiplier()
	# META-PROGRESSION: the PRE-STREAK value, because lifetime coins count what
	# was physically picked up (a coin is 1, a gem is 10) while the streak is a
	# SCORE multiplier on what the run is worth. This is also the only place
	# lifetime coins are credited, so it is deliberately the LOCAL player's own
	# pickup — a multiplayer room's shared bank is a run-scoped total summed
	# across peers and has nothing to do with this counter. See progression.gd's
	# header for the ceiling that leaves in a room.
	var progression := get_tree().get_first_node_in_group("progression")
	if progression and progression.has_method("add_coins"):
		progression.add_coins(value)
	print("Collected a coin worth %d (x%d streak)! Total: %d" % [value, get_streak_multiplier(), coins_collected])


func bank_awarded(amount: int, base_total: int = 0) -> void:
	"""
	Bank a pickup the MULTIPLAYER MASTER has already priced (see
	mp_manager._apply_confirm). Called only for the peer that won the claim.

	THE MULTIPLIER IS ALREADY IN `amount` — the master owns the room's coin streak
	and applied it when it resolved the claim, so multiplying again here would pay
	the winner the square of the room's multiplier. That is the whole difference
	from collect_coin(), which stays exactly as it was and is still the solo path.

	The streak itself is deliberately NOT touched: in a room the multiplier the HUD
	shows comes from the room (see get_streak_multiplier), and this peer's private
	coin_streak has no say in it.

	@param base_total: what the claim was worth BEFORE the room's multiplier —
	    `count` pickups at their base value each (a coin 1, a gem 10), threaded out
	    of the master's ruling as the confirm's `b` field. This is the ONLY figure
	    meta-progression may see (bead godot-test1-42n): lifetime coins count what
	    was physically picked up, and `amount` has a x1..x5 score multiplier baked
	    into it. Trailing, defaulting to 0, and 0 credits nothing — so a call site
	    that does not know about it behaves exactly as it did before.
	"""
	coins_collected += amount
	own_coins += amount
	# META-PROGRESSION, at the PRE-MULTIPLIER value — the SAME null-safe group
	# call collect_coin() makes, and deliberately the same rule: a coin won
	# through the claim protocol has to credit the player exactly what it would
	# have credited them solo. Before bead godot-test1-42n this path credited
	# NOTHING, so a peer in a room levelled only off the pickups it happened to
	# lose the race for (which pay through collect_coin's local fallback).
	if base_total > 0:
		var progression := get_tree().get_first_node_in_group("progression")
		if progression and progression.has_method("add_coins"):
			progression.add_coins(base_total)


func _maybe_start_speed_burst() -> void:
	"""
	Adrenaline: every `STREAK_COINS_PER_STEP` coins in one unbroken streak, a
	hero who has bought the node gets `speed_burst_timer` seconds of extra run and
	duck speed. Called from `collect_coin()` immediately after `coin_streak` rises,
	i.e. on exactly the pickups that step the streak multiplier up — so the burst
	lands on the moment the player already feels as a reward.

	Re-triggering REPLACES the timer rather than adding to it, which is what keeps
	the effect a burst: a treasure chest pays 8–15 pickups inside 0.8 s and would
	otherwise bank a minute of speed out of one box.

	NOT A COOLDOWN-GATED ACTIVE, so there is nothing to refuse and no dial to
	flash — an unranked hero simply reads a 0 s bonus and this is inert.

	MULTIPLAYER: this is a client-local stat change on the local player's own
	client-authoritative movement (the epic's locked default), so it composes with
	a room by construction — nothing is sent and nothing is arbitrated. `ponytail:`
	it hangs off the LOCAL `coin_streak`, and in a room a pickup won through the
	claim protocol lands in `bank_awarded()`, which deliberately does not touch
	that counter (the room owns the multiplier) and cannot recover the pickup
	COUNT from the confirm's totals. So in co-op the burst fires off the pickups
	that resolve locally rather than off every pickup — rarer, never wrong, and
	never a burst somebody else earned. The upgrade path is threading the claim's
	pickup count through `bank_awarded()`, which is a wire-format change.
	"""
	if coin_streak % STREAK_COINS_PER_STEP != 0:
		return
	var duration := _skill_bonus("streak_burst")
	if duration <= 0.0:
		return
	speed_burst_timer = duration
	# One quick warm flash at the feet so the burst is visible rather than merely
	# felt — the same self-freeing effect every ability uses, no new node type.
	_spawn_ability_effect(global_position, Color(1.0, 0.75, 0.3, 0.45), 2.5, 0.4)


func get_streak_multiplier() -> int:
	"""
	Current score multiplier from the coin streak: x1 with no streak, +1 per
	STREAK_COINS_PER_STEP consecutive coins, capped at 1 + STREAK_MAX_BONUS.
	Read by the coin HUD to show the "(xN)" suffix.

	IN A ROOM THE STREAK IS THE ROOM'S. The master owns one streak for everybody
	(it is the thing that prices every claim), so this defers to it — which makes
	coin_hud.gd show the room's "(xN)" with NO HUD change, the same trick phase 4
	used for the bank. `room_multiplier()` answers null offline and
	this falls through to the local value on one test.
	"""
	var mp := _mp()
	if mp != null and mp.has_method("room_multiplier"):
		var room: Variant = mp.room_multiplier()
		if room != null:
			return int(room)
	return 1 + mini(STREAK_MAX_BONUS, coin_streak / STREAK_COINS_PER_STEP)


func hit_by_crocodile(attacker: Node = null) -> void:
	"""
	Called by a crocodile when it bites the player (see piglet_crocodile_ai.gd).

	@param attacker: the body that made contact, when it says so. THE ONE DAMAGE
	VERB STAYS ONE VERB: a hunter's grab is not a second entry point with a second
	copy of the invulnerability rule, it is this one told who is biting. The
	parameter is OPTIONAL and defaults to null, so every existing caller — the
	ordinary bite, the boss bite, a boss projectile, the tower's press — keeps
	working byte for byte and takes the predator arithmetic it always has.

	Rather than teleporting away instantly, we play a clear "caught" signal: a red
	screen flash, a camera shake, and a brief freeze (handled in _physics_process).
	When that window ends _on_caught_finished() bills the attacker's coin setback
	and respawns us in place.

	Bites are ignored while we are already caught, inside either post-respawn
	grace phase (frozen OR blinking), or on the game-over screen — those states
	make us invulnerable.
	"""
	if is_caught or is_respawning or is_game_over or respawn_blink_timer > 0.0:
		return
	# A real bite breaks the coin streak. Deliberately AFTER the invulnerability
	# early-return above, so an ignored bite (grace window etc.) costs nothing.
	coin_streak = 0
	streak_timer = 0.0

	# SYSTEMIC CAPTURE. Deliberately BELOW the invulnerability early-return, for
	# the same reason the streak reset is: a bite that costs nothing must not cost
	# a hero either, and the blink window after a capture would otherwise strip the
	# roster one frame at a time. Both gates are cheap and both are `false` for
	# every contact in the game that is not a post-beat GD-SURVEY machine — the
	# field's retrieval unit or the HQ's sentry, which carry one row key between
	# them and no shared behaviour arm.
	# ...and the LATCH, which is what "the survivors carry on from the same place"
	# costs in code: `_pay_coin_setback()` runs a whole caught freeze later, with
	# the attacker long gone, so the one thing it cannot re-derive is whether this
	# contact was an arrest. Written here, where the evidence is, exactly like the
	# bill below.
	caught_captured = _takes_a_hero(attacker) and _capture_is_armed()
	# The caption's copy of the same answer, taken here and not re-derived, for the
	# reason the declaration gives: the bill SPENDS `caught_captured`, and the
	# countdown is drawn long after the bill. One evidence site, two lifetimes.
	caught_was_arrest = caught_captured
	if caught_captured:
		_capture_active_hero()

	# THE COIN BILL, decided at the same seam and for the same reason: this is where
	# the attacker is still in hand. EVERY contact charges one now that heroes are
	# the lives (owner ruling 2026-08-31) — each predator's own row key, and
	# `DEFAULT_COIN_SETBACK` for the press, a boss projectile or a plain `null`
	# attacker. What still makes a tower guard different is the knockback to the
	# last checkpoint you lit inside the building, and that is decided by the
	# building's presence, not here. Paid in `_on_caught_finished()`, after the same
	# caught freeze / red flash / sting every hit gets — a bigger animal is a bigger
	# BILL, not a different verb.
	caught_setback = _coin_setback_of(attacker)

	is_caught = true
	caught_timer = CAUGHT_DURATION
	# Drop the jump-forgiveness timers as we enter the freeze. Every frozen branch of
	# _physics_process returns ABOVE the step that ticks them, so they would otherwise
	# hold their pre-bite values for the whole caught/respawn/game-over window — and a
	# restart from the game-over screen (Enter/Space, and Space is also `jump`) would
	# then find a still-armed coyote_timer and launch the fresh run off the spawn point.
	coyote_timer = 0.0
	jump_buffer_timer = 0.0

	# Bite sting.
	_sfx("play_bite")

	# Pop the red full-screen flash (found via group, so the HUD isn't hard-wired).
	var flash := get_tree().get_first_node_in_group("hit_flash")
	if flash and flash.has_method("flash"):
		flash.flash()

	# Kick off the camera shake.
	shake_amount = SHAKE_MAX


func _on_caught_finished() -> void:
	"""
	Called once the "caught" freeze ends. EVERY contact pays the same bill — the
	freeze that already happened, plus the attacker's slice of the run's coins —
	and nothing here can end a run.

	HEROES ARE THE LIVES (owner ruling 2026-08-31). There is no heart to spend and
	no out-of-hearts branch to take: the only ending left in the game is the free
	set of heroes going empty, tested below. Every other challenge is fewer coins
	and a temporal freeze.
	"""
	# The bill first, because it is unconditional. It relocates ONLY while we are
	# standing inside the tower's walls, and when it does it has already run the
	# respawn tail itself — routing that through `_respawn_in_place()` would
	# relocate us straight back to the room's group anchor and throw the knockback
	# across the map.
	var relocated: bool = _pay_coin_setback(caught_setback)

	# ...and BANK THE LEG, because this is what replaced the ending. The record used
	# to be written by `_trigger_game_over()`, which the third bite reached; with no
	# hearts, most runs never reach an ending at all, so banking only there would
	# mean a session's distance and coins were never persisted. Banked AFTER the
	# bill, which is why `_bank_records()` banks the run's PEAK and not the live
	# balance (bead godot-test1-h6x): the record is the number the player reached,
	# not the change left in their pocket after the crocodile took its cut.
	# See `_bank_records()` — idempotent, and silent unless a record moved.
	_bank_records()

	if free_hero_count() == 0 and not captive_heroes.is_empty():
		# GAME OVER IS WORLD-LEVEL (bead godot-test1-3iy.10, an ADOPTED READING of
		# the owner's phrasing): the corporation has to hold EVERY hero, not merely
		# every hero this peer may play. Solo that is the same sentence it has
		# always been - `available_character_indices()` is exactly `free` there, so
		# an empty hand and an empty free set are one condition - but in a room they
		# part company, and the peer benched while a teammate is still running must
		# be imprisoned (`_tick_prison`), not handed an ending. `captive_heroes` is
		# mirrored room-wide, so this reads the ROOM's roster with no branch of its
		# own.
		#
		# The `not captive_heroes.is_empty()` guard survives for its original
		# reason: a build with no CHARACTERS at all would otherwise read 0 free and
		# end every run at the first bite.
		#
		# THE FOURTH CAPTURE IS THE ENDING, INSTANTLY (owner veto 2026-09-01, bead
		# godot-test1-ueg). There used to be a break-out scene here; the owner has
		# ruled it out ("I never asked for this"). The archive is written first and
		# on the same frame, exactly as the lost scene wrote it — so Continue
		# reopens this ending and only New Game hands out another world — and
		# `_trigger_game_over()` raises the screen, which on web is the ending film
		# through `game_over_ui.gd`'s own branch.
		#
		# BELOW THE BILL AND THE BANK ON PURPOSE: the grab that empties the roster
		# still pays its `coin_setback` and still banks the leg, which is the
		# ordering every other contact has.
		#
		# ponytail: IN A ROOM THIS IS DECIDED OFF AN EVENTUALLY CONSISTENT MIRROR,
		# and there is deliberately no authority over it (codex review 2026-09-01).
		# The ceiling: a liberation and the fourth capture crossing in flight leave
		# this peer reading four captives for one packet's flight, and the ending it
		# writes is irreversible — a later `cap: false` cannot un-archive a world.
		# The window is narrow (the only hero who can free anybody is the one being
		# grabbed) and it is not new — the vetoed break-out ALSO opened off this same
		# local mirror and only its OUTCOME was adjudicated, so a spurious scene
		# archived the world 35 s later instead of now. The upgrade path is a
		# master-published room-level ENDING verdict, which is the machinery the owner
		# vetoed on this very bead: it needs a ruling, not a patch. The 0.5 s poll in
		# `_tick_prison()` is what every OTHER peer ends through, and it rides out the
		# flap for free by being a poll rather than an edge.
		_end_run(Outcome.CAPTURED)
	elif not relocated:
		_respawn_in_place()


func _respawn_in_place() -> void:
	"""
	Soft respawn after a bite: stay exactly where we fell and keep every coin —
	the only penalty is the coin bill already paid. We sweep crocodiles out of the
	area and start a short, frozen grace window (see the is_respawning branch in
	_physics_process) so we can't be re-bitten the moment we recover. Any active
	ability state (air boost, giant/small form) is also cleared.

	IN A ROOM, "IN PLACE" BECOMES "BACK WITH THE GROUP" (bead godot-test1-s86.18).
	Dying 300 m behind the team ends that player's session in every way that
	matters — the group walks on while they walk back alone through the pack that
	just ate them — so the respawn reuses the mid-run join's placement wholesale:
	the group's anchor from `MpManager.group_anchor()` (centroid, or the master
	when the group is spread), the same `_place_near()` ring probe for a spot the
	body fits in, and the same crocodile sweep at the spot actually landed on,
	not the one we died on. Solo `group_anchor()` answers `null` and every line
	below is byte-for-byte what it has always been.

	THE RELOCATION FIRES ON THE RESPAWN EVENT AND NOTHING ELSE, which is the
	standing lesson of the drag bug (bead godot-test1-s86.17): placement belongs
	to an EVENT, never to the arrival of data that happens to complete a
	condition. `_on_caught_finished()` calls this exactly once per death, so
	there is no arrival window to gate and no latch to keep — and `group_anchor()`
	is deliberately a pure query with no latch of its own, so it cannot grow one.

	It composes with the grace freeze rather than fighting it: the move happens
	HERE, at the same moment the respawn settles the body, so the whole frozen
	countdown — and the blink invulnerability that follows it — is spent at the
	NEW spot. Landing first and being frozen afterwards would be the same two
	things in the wrong order: a player unfrozen, unswept and standing in the
	group's crocodiles.

	ponytail: the group can be past this peer's loaded terrain (web streams only
	~150 m), so the ring probe may judge candidates whose blocks do not exist
	yet, and the ground under the landing is built by the terrain's own streaming
	on the next frame — harmless because the body is frozen for
	RESPAWN_GRACE_DURATION either way, at the cost of at worst one shove-out from
	a block that turned up underneath. The upgrade path is asking the terrain to
	build around the anchor first, the way `_apply_join_placement()` does, which
	then also needs its `await get_tree().physics_frame`.
	"""
	_reset_ability_states()
	# A PRISONER RESPAWNS WHERE HE FELL, and that is the one exception to "in a room,
	# in place means back with the group". A guard's bite inside the cell block must
	# not fire the group relocation, which would throw the body kilometres out to the
	# team and hand it straight back to `_confine_to_block()` — the yank the clamp is
	# there to make impossible, arriving via the one path that outruns it.
	var anchor: Variant = null if prisoner_active else _room_group_anchor()
	if anchor != null:
		var from_xz := Vector2(global_position.x, global_position.z)
		_place_near(anchor as Vector3)
		# A TELEPORT IS NOT DISTANCE RUN. own_distance is measured from
		# own_distance_origin, so shifting the origin by exactly the jump leaves
		# the banked figure untouched and starts the next leg from here. Without
		# it, dying next to a team that is kilometres down the road would write
		# their distance into user://best_run.cfg as this player's personal best
		# — the one thing own_distance_origin exists to prevent, and the same
		# reason join_at() re-origins a mid-run joiner.
		own_distance_origin += Vector2(global_position.x, global_position.z) - from_xz
	clear_nearby_crocodiles(global_position)
	velocity = Vector3.ZERO
	is_ducking = false
	is_running = false
	is_respawning = true
	respawn_timer = RESPAWN_GRACE_DURATION


# ---------------------------------------------------------------------------
# THE PRISON ROLE — the bench, the block, and the way out of it
# ---------------------------------------------------------------------------

func _tick_prison(delta: float) -> void:
	"""
	Decide the bench, twice a second. The one owner of `prisoner_active`.

	THE ORDER OF THE THREE TESTS IS THE OWNER'S RULE, top to bottom:

	  1. THE ROOM IS OUT OF HEROES -> the run is over, for EVERY peer and not only
	     for whoever was bitten last. This is the world-level reading of game over
	     (see the roster clause in `_on_caught_finished()`); the peer who took the
	     last hero reaches it there, and this is how the other three learn.
	  2. MY HERO IS FREE -> nothing to do, and if we were benched we are not any
	     more: somebody walked into our cell, or a claim finally landed.
	  3. MY HERO IS IN A CELL -> REASSIGN FIRST. Ask the lobby for a free hero and
	     wait for the answer; only when the room has none is the prison role the
	     answer, which is what "imprison last" means in code.

	NOTHING HERE RUNS SOLO. `is_online()` is the gate, and it is the same one-test
	shape every other multiplayer read in this file uses.
	"""
	if is_game_over:
		return
	# ...AND NOT WHILE A BITE IS STILL BEING PAID FOR. The caught freeze runs 0.55 s
	# and this tick is 0.5 s, so on the grab that takes the room's last hero this
	# would end the run BEFORE `_on_caught_finished()` - clearing `is_caught` under
	# it, so the freeze is truncated and the coin bill that grab costs is never
	# spent. Every ending stays where it is decided.
	if is_caught:
		return
	_prison_accum += delta
	if _prison_accum < PRISON_TICK:
		return
	_prison_accum = 0.0

	var mp := _mp()
	if mp == null or not mp.has_method("is_online") or not bool(mp.call("is_online")):
		# The room ended under us (a leave, a dropped socket). The block is not a
		# place to leave somebody standing in solo play.
		if prisoner_active:
			_exit_prison()
		return

	# 1. The room is out of heroes -> the ending, on this peer too (owner veto
	# 2026-09-01, bead godot-test1-ueg). The other way in is the roster clause in
	# `_on_caught_finished()`, which is where the CAPTOR ends; this poll is how the
	# other three learn, and it rides out the release-grace flap for free by being
	# a poll rather than an edge. `_exit_prison()` first because a benched peer is
	# standing in a cell and the ending must not leave the role latched.
	if free_hero_count() == 0 and not captive_heroes.is_empty():
		_end_run(Outcome.CAPTURED)
		return

	# 2/3. What does the lobby say we are holding, and is he in a cell?
	var hero: String = String(mp.call("my_hero")) if mp.has_method("my_hero") else ""
	if hero.is_empty() or not captive_heroes.has(hero):
		if prisoner_active:
			_exit_prison()
		return

	# REASSIGN FIRST. A claim that is sent changes nothing yet — we come back here
	# in half a second and read the answer off `my_hero()`, whether it was a grant
	# or an `errHeroTaken` that left us exactly where we were.
	if mp.has_method("request_reassignment") and bool(mp.call("request_reassignment")):
		return

	# IMPRISON LAST.
	if not prisoner_active:
		_enter_prison(hero)


func in_prison_role() -> bool:
	"""Is this player benched inside the cell block? The tower's window in."""
	return prisoner_active


func _enter_prison(hero: String) -> void:
	"""
	Take up the prison role: play as your captive, inside his cell block.

	@param hero: the captive we hold — his cell is where we stand up.

	A PLACEMENT AND NOT A RESPAWN: no life is spent, no score, streak or record is
	touched, and the distance origin is shifted by the jump so the walk to the
	tower is not banked as a personal best nobody ran.
	"""
	prisoner_active = true
	velocity = Vector3.ZERO
	ability_cooldowns.fill(0.0)
	_reset_ability_states()
	_apply_view_mode()

	# Null-safe: a player with no terrain under it (every headless harness) serves
	# the role where it stands, unconfined. That is the right degrade — the role's
	# decisions are all roster arithmetic and none of them touches geometry.
	var terrain := get_tree().get_first_node_in_group("terrain")
	if terrain != null and terrain.has_method("tower_site"):
		_prison_origin = terrain.call("tower_site") as Vector3
		_prison_confined = true
		var from_xz := Vector2(global_position.x, global_position.z)
		global_position = _prison_origin + TowerInterior.cell_stand(hero)
		own_distance_origin += Vector2(global_position.x, global_position.z) - from_xz
	rotation.y = SPAWN_FACING_Y
	camera_pitch = 0.0
	clear_nearby_crocodiles(global_position)
	_sfx("play_hunter_lock_on")
	print("Benched: the room has no free hero. %s plays from the cell block." % hero)


func _exit_prison() -> void:
	"""
	Leave the prison role. The body stays where it is standing — in the block, with
	the way out in front of it, which is exactly where a survived break-out leaves
	you and for the same reason: walking out is the beat.
	"""
	if not prisoner_active:
		return
	prisoner_active = false
	_prison_confined = false
	_reset_ability_states()
	print("Back on the roster — out of the cell block.")


func _confine_to_block() -> void:
	"""
	Keep a prisoner inside the cell block. Movement confined, nothing else changed.

	A CLAMP AND NOT A WALL, deliberately: a wall is geometry every other body in the
	game would collide with too (a rescuer, a guard, a teammate's avatar), and the
	confinement is a property of THIS PLAYER'S ROLE, not of the building. Two
	clamps, x and z — y is left alone so gravity, the floor and the ramp all still
	behave, and there is no vertical way out of a roofed block anyway.
	"""
	if not prisoner_active or not _prison_confined:
		return
	var lo := _prison_origin + TowerInterior.block_min()
	var hi := _prison_origin + TowerInterior.block_max()
	global_position.x = clampf(global_position.x, lo.x, hi.x)
	global_position.z = clampf(global_position.z, lo.z, hi.z)


func _end_run(outcome: Outcome = Outcome.CAPTURED) -> void:
	"""
	The run is over — either the corporation holds every hero (CAPTURED),
	or the heroes reached Budapest and escaped (WON).

	LATCHING: the first call ends the run and sets the outcome. Every later
	call is a no-op, which stops wins double-counting when repair/replay
	re-enters the path.
	"""
	if is_game_over:
		return
	is_game_over = true
	run_outcome = outcome
	velocity = Vector3.ZERO
	# THE BENCH DOES NOT OUTLIVE THE RUN, and it is dropped HERE rather than at the
	# two call sites because a role left standing has nothing left to clear it:
	# `_tick_prison()` returns above every decision while `is_game_over`, and
	# `_confine_to_block()` would then own the body for the whole ending screen.
	# Idempotent, and a no-op solo.
	_exit_prison()
	_reset_ability_states()
	_hide_respawn_message()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if outcome == Outcome.WON:
		_sfx("play_level_up")
		BestRunStore.archive_world(BestRunStore.OUTCOME_WON)
		if best_run_store:
			best_run_store.record_win()
		print("Won the run! Escaped to Budapest! Final coins: %d" % coins_collected)
	else:
		# Game-over sting.
		_sfx("play_game_over")
		BestRunStore.archive_world(BestRunStore.OUTCOME_CAPTURED)
		print("Game over! Final coins: %d" % coins_collected)

	# Bank once more (idempotent) and then read the LATCH, not this call's return:
	# the grab that emptied the roster already banked this leg, so a fresh
	# `own_coins > best_coins` is false on exactly the record runs the flash
	# exists for.
	_bank_records()
	# ...and reconcile that latch against what the lobby answered while the run
	# was going on. See `_reconcile_record_latch()`.
	_reconcile_record_latch()

	var panel := get_tree().get_first_node_in_group("game_over_ui")
	if panel and panel.has_method("show_game_over"):
		panel.show_game_over(
			coins_collected, best_coins, run_beat_record, int(outcome)
		)


func _trigger_game_over() -> void:
	"""Compatibility alias for ending the run via capture."""
	_end_run(Outcome.CAPTURED)


func end_run(outcome: Outcome = Outcome.CAPTURED) -> void:
	"""
	Public entry point for ending the run (CAPTURED or WON).
	Can be called by landmark exploration system (.5) when Budapest is explored.
	"""
	_end_run(outcome)


# ============================================================================
# BUDAPEST — the explored set, and the win it decides
# ============================================================================
#
# See the `explored_mask` banner for the three properties of the set itself.
# These four methods are its whole public surface: one writer for a local
# arrival, one writer for the room's mirror, one reader for the HUD and the
# bank, and the win test they both end in.

func explore_landmark(index: int) -> bool:
	"""
	The local player walked into `BudapestPlan.SLOTS[index]`. Set its bit, tell
	the room, and ask whether that was the eighteenth.

	@return: whether the bit was NEW to this run — the caller's cue to pay the
	    arrival a card and its coins, so a return trip is silent and free.

	IDEMPOTENT. `landmark_toast.gd` re-arms its approach latch every time you walk
	out of range, so this is asked again on every visit to the same place.

	THE ROOM HEARS IT BEFORE ANYTHING IS DECIDED, which is `_capture_active_hero`'s
	ordering and for the same reason: in a room the win is a fact about the ROOM's
	mask, and the master is what unions the claims into one.
	"""
	if index < 0 or index >= BudapestPlan.SLOTS.size():
		return false
	var bit: int = 1 << index
	if explored_mask & bit != 0:
		return false
	explored_mask |= bit
	var mp := _mp()
	if mp != null and mp.has_method("report_landmark_explored"):
		mp.call("report_landmark_explored", index)
	_check_budapest_win()
	return true


func adopt_explored_mask(mask: int) -> void:
	"""
	THE ROOM'S MIRROR: fold the room's explored set into ours.

	@param mask: a 22-bit mask from `MpManager` — the room's union, or a join
	    snapshot's absolute picture.

	OR, NEVER ASSIGN, and masked to the slots that exist. The OR is what lets the
	`room` packet be a plain repair channel with none of `_adopt_room_captives`'s
	grace windows: this set only ever grows inside a run, so a master's older copy
	can undo nothing and the two directions converge on their own. The AND is the
	trust boundary's second half — `MpManager` range-checks every INDEX it accepts,
	but a mask crosses the wire as one integer.
	"""
	explored_mask |= mask & ((1 << BudapestPlan.SLOTS.size()) - 1)
	_check_budapest_win()


func explored_count() -> int:
	"""How many of Budapest's 22 landmarks this run has walked into."""
	return _popcount(explored_mask)


static func _popcount(mask: int) -> int:
	"""
	Bits set in `mask`. GDScript has no popcount, and Kernighan's loop runs once
	per SET bit — at most 22 here, and typically none at all outside the city.
	"""
	var n: int = 0
	var bits: int = mask
	while bits != 0:
		bits &= bits - 1
		n += 1
	return n


func _check_budapest_win() -> void:
	"""
	Eighteen of twenty-two ends the run in VICTORY — the epic's 80%.

	IN A ROOM THE MASK IS THE ROOM'S, AND IT IS NEVER READ BEFORE THE JOIN SETTLES
	(epic decision 7). A joiner is IN_ROOM from the `welcome` frame while its
	picture of the room still fills one snapshot at a time, so a mask read there is
	a partial one — and a win is not a thing you can take back. Deferring costs
	half a second at most: the master republishes at `ROOM_SYNC_HZ` and every
	`room` packet re-drives this through `adopt_explored_mask()`.

	`is_online()` AND NOT `is_busy()`, which is the opposite of the choice
	`landmark_toast._take_pause` makes and deliberately so (codex review
	2026-09-02). `is_busy()` is true through the seconds a join spends CONNECTING,
	where there is no room, no union and nothing to be partial about — deferring
	there would be deferring to nobody, and a join that then FAILS leaves the
	eighteenth landmark undecided with nothing left to ask again (the toast will
	not re-report a slot whose bit is already set). While CONNECTING our own mask
	IS the truth, exactly as it is solo; the gate belongs on the room, and the room
	is `is_online()`.
	"""
	if is_game_over:
		return
	var mask: int = explored_mask
	var mp := _mp()
	if mp != null and mp.has_method("is_online") and bool(mp.is_online()):
		if not mp.has_method("room_explored_mask"):
			return
		var room: Variant = mp.call("room_explored_mask")
		if room == null:
			return   # the join has not settled — the next `room` packet asks again
		mask |= int(room)
	if _popcount(mask) >= BUDAPEST_WIN_LANDMARKS:
		end_run(Outcome.WON)


func _bank_records() -> bool:
	"""
	Write this leg's records out. Idempotent, so it may be called as often as we
	like.

	@return: true if the COIN record moved ON THIS CALL. The "NEW BEST!" flash
	    reads the `run_beat_record` LATCH this also sets, never a fresh comparison:
	    a bite banks, so `best_coins` already equals `own_coins` by the time
	    the ending asks.

	CALLED ON EVERY CONTACT, NOT ONLY AT THE ENDING (bead godot-test1-0bc). While
	hearts existed the third bite ended the run, and `_trigger_game_over()` banking
	the record was the same event as "the player stopped playing". Heroes being the
	lives took that away: the only ending left is the corporation holding all four
	AND the break-out being lost, which most sessions never reach — so a player who
	walks, banks and closes the tab would have written nothing to
	`user://best_run.cfg`, `localStorage` or the lobby for the whole run, and their
	"Best" line would have been frozen forever. A bite is what replaced the ending
	as the natural end of a leg, so a bite is where the record is banked.

	Cheap to repeat: every field is monotone and `BestRunStore.submit()` is a
	read-modify-write merge in all three layers, and the guard below only calls it
	when a record ACTUALLY moved — so the network sees traffic on improvements and
	nothing else.

	Records are read off own_coins, NOT the displayed fields: in a
	room those are the ROOM's totals (see _refresh_shared_totals), so writing them
	here would persist the whole room's bank as this player's personal best. Solo
	the pairs are identical.

	...off the run's PEAK own_coins, though, not its live balance (bead
	godot-test1-h6x). `_on_caught_finished()` bills the attacker's setback and THEN
	calls this, so a record taken off the balance is a record one bill below the
	number the player watched the HUD reach — the peak is what they earned and what
	`_reconcile_record_latch()` already compared against.
	"""
	# Coins is the headline record, so IT decides the "NEW BEST!" flash (bead godot-test1-8gw.1).
	record_coins = maxi(record_coins, own_coins)
	var is_new_best := record_coins > best_coins
	run_beat_record = run_beat_record or is_new_best
	if is_new_best:
		best_coins = maxi(best_coins, record_coins)
		if best_run_store:
			best_run_store.submit(0, best_coins)

	# BUDAPEST'S RECORD, banked here for the coin record's reason (a run that never
	# reaches an ending would otherwise write nothing) and CHANGE-GATED for it too:
	# `submit_landmarks` is a `maxi` plus a disk write, and this function runs on
	# every bite. `landmarks_best` is a count and not the mask — a max merges, a
	# 22-bit set of WHICH ones is per-run world state and stays off the store.
	var landmarks: int = explored_count()
	if best_run_store and landmarks > best_run_store.landmarks_best:
		best_run_store.submit_landmarks(landmarks)

	# Meta-progression banks itself on every level-up, so this only catches the
	# coins picked up SINCE the last one — the partial progress toward the next
	# level, which is exactly what a player would notice missing on the next boot.
	# `Progression.save()` drops a save whose counters have not moved, which is
	# what keeps a bite off the disk and off the lobby when nothing changed — a
	# bite is a per-contact path now, not the once-a-run ending it used to be.
	var progression := get_tree().get_first_node_in_group("progression")
	if progression and progression.has_method("save"):
		progression.save()
	return is_new_best


func _reopen_archived_ending() -> void:
	"""
	Bring the ending screen back for a world whose campaign already ended.
	Reopens the right ending (WON vs CAPTURED) from the stored archive outcome.
	"""
	if BestRunStore.world_archived() and not is_game_over:
		var archived := BestRunStore.archived_outcome()
		var outcome: Outcome = Outcome.WON if archived == BestRunStore.OUTCOME_WON else Outcome.CAPTURED
		_end_run(outcome)


func _on_best_run_loaded(_store_distance: int, store_coins: int) -> void:
	"""
	Fold the store's records in. `maxi`, never assignment: this fires once with
	the local values and again if the lobby knows better, and it can land at any
	moment — including after a game over has already banked a fresh record — so a
	late or stale reply must be incapable of lowering anything.
	"""
	best_coins = maxi(best_coins, store_coins)


func _reconcile_record_latch() -> void:
	"""
	Take the "NEW BEST!" flash back if the record this run beat was one it never
	saw. Called at the ending, where the flash is read.

	`run_beat_record` is latched at BANK time against `best_coins` — and early
	in a run that is only whatever has loaded so far, because the store's server
	leg answers over the network and can still be in flight. So a bite in the
	first seconds latches a "record" the player's other device beat long ago.

	AT THE ENDING, and off the SERVER's own pre-merge number rather than anything
	emitted: by then `best_coins` and the store's merged `coins` both
	contain this run's `submit()`s, so an echo of our own bank is arithmetically
	indistinguishable from another device's record — which is why the store keeps
	`server_best_coins` separately. Reconciling on the `loaded` signal could
	not see the case at all: a server holding EXACTLY this run's coins raises
	nothing and emits nothing.

	Reconciliation compares against `record_coins` (the run's coin PEAK), not
	`own_coins`: subsequent setbacks/bites reduce the mutable `own_coins` balance
	while the banked record and ending "Best" line remain at the peak.

	`>=`, because a run that TIED the standing record set no new best. A store
	with no server answer reports 0, which outranks nothing and leaves the local
	comparison alone.
	"""
	if best_run_store and record_coins > 0 and best_run_store.server_best_coins >= record_coins:
		run_beat_record = false


func restart_game() -> void:
	"""
	Start a brand-new run. Called by the Game Over screen's "Play Again" button.
	Everything resets: coins to 0, the four heroes back in the player's hands, and
	the player is sent to the origin spawn with the mouse recaptured.
	"""
	# Coins, distance, streak AND this peer's multiplayer contributions
	# (own_coins / own_distance) are all wiped by
	# reset_position() below — the one owner of the "hard reset" wipe list, so
	# the two can never drift out of sync.
	#
	# IN A ROOM, "Play Again" LEAVES THE ROOM FIRST, and that is a correctness fix
	# rather than a policy choice. This method's ONE caller is the Game Over
	# screen, which in a room can only be up because the ROOM's free-hero set is
	# empty and the break-out was lost — a room-wide state living in the mirrored
	# captive set. Wiping our own heroes cannot bring the room's roster back: the
	# other peers' captives still stand, and the next `cap` / `room` packet puts
	# ours back too. Play Again was an infinite loop with no way out but leaving —
	# so leave, and hand the player the fresh solo run the button promises.
	# leave() is the manager's single complete unwind, so the
	# collected-coin set, the dead-crocodile set, the frozen `_gone_*` totals and
	# the room streak all go with it, and room_seed() then answers null below so
	# the world is re-rolled rather than replayed with every coin already taken.
	#
	# ponytail: the room dissolves as each member presses the button; playing
	# together again is a re-host or one tap in the room list. The upgrade path is
	# a room-wide restart verb the master broadcasts (`{"t":"rst"}` alongside
	# `cnf`/`dead`), on which every peer clears `_collected_ids`, `_dead_crocs`,
	# `_gone_*` and restarts in place — a real shared "Play Again" that keeps the
	# room, at the cost of a new protocol message and its own arbitration.
	var restart_mp := _mp()
	if restart_mp and restart_mp.has_method("leave") and restart_mp.has_method("shared_bank") \
			and restart_mp.shared_bank(own_coins) != null:
		restart_mp.leave()
	# NEW GAME MINTS A FRESH WORLD, which is the other half of the world archive
	# the fourth capture writes: this button is the only way out of an ended campaign, so it is the
	# one place the latch is cleared. Harmless on every ordinary Play Again — the
	# latch was never set. (When the per-world save-id epic lands, this call is
	# where an id is minted instead; see `BestRunStore.new_game`.)
	BestRunStore.new_game()
	is_game_over = false
	run_outcome = Outcome.CAPTURED
	is_caught = false
	# An unpaid coin bill dies with the run it was charged in. Cheap and
	# defensive: the setback path can never reach a game over, so this can only be
	# armed here if a bite and a Play Again land in the same freeze — but a stale
	# fraction would tax the NEXT run's coins for a bite it never took.
	caught_setback = 0.0
	caught_captured = false
	caught_was_arrest = false
	is_respawning = false
	# Play Again hands back all four heroes. The captive set is per-run world state
	# and nothing about it is earned, so unlike the tower's opened gates it does
	# not survive the button. The break-out scene's own state goes with it — it is
	# per-run for the same reason and stored in exactly as many places (none).
	captive_heroes.clear()
	# (Budapest's explored mask is wiped by `reset_position()` below, with the rest
	# of the hard-reset list.)
	# The bench goes with the run for the same reason: it is a fact about a room's
	# roster, and Play Again inside a room leaves the room first.
	prisoner_active = false
	_prison_confined = false
	_prison_accum = 0.0
	# Ability cooldowns are NOT part of reset_position()'s wipe list, and
	# _update_ability_timers() sits below the is_game_over early return in
	# _physics_process — so they freeze the moment the run ends and would carry
	# into the new one at full value (die right after a Stink Wave, hit Play
	# Again, and F is refused for ~12 s with the HUD dial nearly full).
	ability_cooldowns.fill(0.0)
	# Drop any mid-blink i-frames and restore model visibility for the current
	# view — blink state must never leak into a fresh run.
	respawn_blink_timer = 0.0
	_apply_view_mode()
	_hide_respawn_message()
	# Re-roll the world BEFORE teleporting back to spawn: new_run() re-seeds the
	# terrain and synchronously lays the ground around (0,0), so reset_position()
	# lands us on solid new-world ground in the same frame (the scenery on it fills
	# in over the next few frames). Group-based
	# lookup with a has_method guard — the project's no-hard-references convention.
	var terrain := get_tree().get_first_node_in_group("terrain")
	if terrain and terrain.has_method("new_run"):
		# IN A MULTIPLAYER ROOM, "Play Again" must rebuild the SHARED world, not
		# roll a private one — a re-roll here would leave this peer walking
		# different terrain, biomes and rivers from everyone else for the rest of
		# the room's life, with the avatars still drawing at coordinates that no
		# longer mean anything. Same null-safe group + has_method shape as
		# _terrain_is_river_here() / _weather_is_raining_here(); `null` (offline,
		# or no seed yet) falls through to the ordinary random re-roll, and `0` is
		# a legitimate seed, which is why this is a null and not a sentinel int.
		var mp := get_tree().get_first_node_in_group("mp")
		var shared_seed: Variant = mp.room_seed() if mp and mp.has_method("room_seed") else null
		if shared_seed == null:
			terrain.new_run()
		else:
			terrain.new_run(shared_seed)
	reset_position()
	# Recapture the mouse — but ONLY when this is NOT a touch session, mirroring the
	# `_ready()` guard via the SAME canonical `MobileSensors.is_touch_session()` rule.
	# "Play Again" on a phone must not re-grab the mouse (pointer-lock), which would
	# undo the touch mouse-capture guard. On native desktop the static func returns
	# false (no JavaScriptBridge touched), so the mouse is recaptured exactly as before.
	if not MobileSensors.is_touch_session():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# A web Play Again returns to the existing start card so the next run crosses
	# the same user-input boundary and PLAY SOLO starts IntroVideo again. Desktop
	# keeps its original direct-restart path: no extra screen or delay off-web.
	if OS.has_feature("web"):
		var start_overlay := get_tree().get_first_node_in_group("start_overlay")
		if start_overlay and start_overlay.has_method("reenter_for_new_run"):
			start_overlay.reenter_for_new_run()


func _freeze_with_gravity(delta: float) -> void:
	"""
	Hold the player still (no horizontal movement) while still settling under
	gravity, so a frozen state never leaves the character hovering. Used by the
	game-over and post-respawn-grace branches of _physics_process.
	"""
	velocity.x = 0.0
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	move_and_slide()


func _show_respawn_countdown() -> void:
	"""
	Show the centred respawn countdown (a plain Label found via group). The
	frozen window is only 1.5 s now, so a one-decimal readout keeps the short
	countdown visibly moving (a whole-seconds "2... 1..." would barely change).

	TWO CAPTIONS, AND THE SPLIT IS THE OWNER'S (2026-09-04, bead godot-test1-tuc).
	"Caught!" is what happens to a HERO: an arrest by a `captures_hero` machine,
	post-beat, which really does put them in a cell and hand you the next one. An
	ordinary predator does no such thing — CLAUDE.md's "every other contact is a
	TAX, never an ending" — so a crocodile that bites you says "Robbed!", which is
	exactly what it did: it took the attacker's slice of the run's coins and you
	stood back up where you fell, same hero, nothing lost but the streak and the
	change in your pocket. One caption for both told the player they were losing
	the roster to every animal in the field.

	It reads `caught_was_arrest`, NOT `caught_captured` — see that declaration for
	why the two exist.
	"""
	var label := get_tree().get_first_node_in_group("respawn_label")
	if label:
		label.visible = true
		# tr() on the FORMAT STRING, not the result — the formatted text ("Robbed!
		# Back in 1.2...") is a key in no table. See CLAUDE.md's localization RULE 2.
		var caption := "Caught! Back in %.1f..." if caught_was_arrest \
				else "Robbed! Back in %.1f..."
		label.text = tr(caption) % maxf(respawn_timer, 0.0)


func _hide_respawn_message() -> void:
	"""Hide the respawn countdown label."""
	var label := get_tree().get_first_node_in_group("respawn_label")
	if label:
		label.visible = false


func reset_position() -> void:
	"""
	Hard reset to the origin spawn point. This is the "start over" teleport used by
	restart_game() (and kept as the crocodile's legacy fallback). It wipes the coin
	count — a normal bite no longer does this; it only takes the attacker's slice
	of the coins and respawns in place (see _respawn_in_place).
	"""
	# Define spawn point
	var spawn_point = Vector3(0, 2, 0)

	# A full restart wipes the coin count, the distance score, and the streak that
	# hangs off the coin count.
	coins_collected = 0
	own_coins = 0  # ... and this peer's share of a room's bank along with it.
	run_distance = 0
	own_distance = 0
	own_distance_origin = Vector2.ZERO  # ... back to the origin spawn it teleports to.
	run_beat_record = false  # ... and the new run has not beaten anything yet.
	record_coins = 0
	coin_streak = 0
	streak_timer = 0.0
	# BUDAPEST IS UNEXPLORED AGAIN. Per-run world state, the captive set's rule —
	# nothing about the walk is earned, and the COUNT was already banked into
	# `landmarks_best` by `_bank_records()`. It lives HERE rather than in
	# `restart_game()` because this is the one owner of the hard-reset wipe list,
	# and the seed-arrival path into a room (`MpManager._receive_seed`) calls this
	# and not that: a peer carrying a solo run's eighteen landmarks into somebody
	# else's world would win it on arrival (codex review 2026-09-02).
	explored_mask = 0

	# Clear any crocodiles near the spawn point
	clear_nearby_crocodiles(spawn_point)

	# Reset position to spawn point
	global_position = spawn_point

	# Reset velocity to prevent carrying momentum
	velocity = Vector3.ZERO

	# Reset camera and character rotation to default
	rotation.y = SPAWN_FACING_Y  # Face straight down the coin road (+X)
	camera_pitch = 0.0  # Reset camera vertical rotation
	camera_yaw_lag = 0.0  # Drop any keyboard-turn lag along with the pivot yaw
	if camera_pivot:
		camera_pivot.rotation = Vector3.ZERO  # Whole rotation, so roll can't survive

	# Reset character state
	is_ducking = false
	is_running = false

	# Drop any mid-blink i-frames and restore model visibility for the current
	# view (idempotent — see _apply_view_mode). The indoor boom goes with them,
	# and needs no line of its own: this runs AFTER the teleport above, and
	# `_apply_view_mode()` re-derives the room from where we now are — the spawn
	# point, 400 m from the tower.
	respawn_blink_timer = 0.0
	_apply_view_mode()

	# Lift the model back out of the water. This is a hard teleport to the dry
	# spawn point, so easing the offset out over the next fifth of a second would
	# just be a visible glitch at a place with no river in it.
	_wade_sink = 0.0
	_apply_wade_sink()

	# Drop any active ability state (air boost, giant form, odd size) on respawn.
	_reset_ability_states()

	print("Player position reset - respawned at spawn point")


func clear_nearby_crocodiles(spawn_point: Vector3) -> void:
	"""
	Remove all crocodiles within SPAWN_SAFE_RADIUS of the spawn point.
	Prevents instant death after respawning.

	BOSSES ARE EXEMPT — same rule as flee_from() in piglet_crocodile_ai.gd, for
	the same reason: a boss is a deterministic road landmark, not spawn clutter.
	Freeing one here would make dying the CHEAPEST way past every boss on the
	road (the whole cost would be the boss row's own `coin_setback` bill).
	Leaving it standing is safe: the respawn grace freeze plus the blink
	invulnerability that follows are long enough to run, and running (>= 9.0)
	beats MAX_CHASE_SPEED (8.5) by design.

	IN A MULTIPLAYER ROOM NOTHING IS FREED — the room is asked to scare them off
	instead. Phase 5 makes the master the authority for every awake crocodile, and
	the sync layer's standing contract is that it never creates, re-parents or
	frees one; this sweep is outside that layer and would break it from both ends.
	Freeing on the MASTER stops it broadcasting those ids, so every other peer
	times out after CROC_SYNC_TIMEOUT and resumes local AI for ~10 crocodiles the
	authority no longer has — divergent packs, right where players are together.
	Freeing on a NON-master silently deletes bodies the master keeps sending
	samples for. The flee request is the arbitrated equivalent: it reaches every
	screen through the sync packet's CROC_FLAG_FLEEING bit, and it is also the
	only thing that unparks the master's copy from a peer it just bit — the local
	`is_paused` a bite sets is overwritten by the next sample 100 ms later, so
	without it the same crocodile bites again the instant the i-frames lapse.
	SPAWN_SAFE_RADIUS is carried INTO that request, because this is a bounded
	sweep: an unbounded flee disarmed every awake crocodile in the room, on every
	screen, for the whole grace window — once per death by any peer.

	@param spawn_point: The position to check distance from
	"""
	var mp := _mp()
	if mp != null and mp.has_method("request_croc_flee") \
			and mp.request_croc_flee(spawn_point, RESPAWN_GRACE_DURATION + RESPAWN_BLINK_DURATION, SPAWN_SAFE_RADIUS):
		return

	var crocodiles = get_tree().get_nodes_in_group("crocodile")
	var removed_count = 0

	for crocodile in crocodiles:
		if crocodile is Node3D:
			if "is_boss" in crocodile and crocodile.is_boss:
				continue
			# AND A TOWER GUARD IS EXEMPT FOR THE SAME REASON A BOSS IS: it is
			# authored furniture standing on an authored post, not spawn clutter.
			# This is NOT only about a guard's own bite — every other way to lose
			# inside the building routes here too (the press, a
			# crocodile that followed you through the door), and a 25 m sweep from
			# anywhere in a 17.6 m building frees the WHOLE floor. That would make
			# losing the cheapest way past a guarded room, and it would break the
			# other half of the ruling as well: the population is supposed to come
			# back at the doorway, not at whatever hazard you last lost to.
			#
			# KEYED ON ITS OWN ROW KEY, because the property is "authored furniture,
			# not spawn clutter" and nothing else. It used to be inferred from
			# `coin_setback` being non-zero, which held only while the guard was the
			# one row carrying that key; every predator bills coins now, so that
			# test would exempt the entire world. Row key, never a species name,
			# exactly like the two immunities in the AI.
			if _is_sweep_exempt(crocodile):
				continue
			var distance = spawn_point.distance_to(crocodile.global_position)
			if distance <= SPAWN_SAFE_RADIUS:
				crocodile.queue_free()
				removed_count += 1

	if removed_count > 0:
		print("Cleared %d crocodile(s) near spawn point" % removed_count)


func join_at(anchor: Vector3) -> void:
	"""
	Mid-run multiplayer join: drop in beside the group instead of at the world
	origin. Called once per room by mp_manager.gd, with `anchor` the group's
	centroid (or the master's position when the group is spread out).

	THIS IS NOT A RESTART. The coins, distance, heroes and streak belong to the
	room and must survive — so this performs exactly the teleport hygiene
	reset_position() does (velocity, facing, camera pivot, ability state, blink
	i-frames) and none of its score wipe.

	@param anchor: world position to arrive next to.
	"""
	_place_near(anchor)

	# This peer's SOLO tally is not the room's: own_coins would inflate the shared
	# bank with coins banked in a different world. The displayed coins/distance
	# are the room's from the next tick either way, so zeroing this costs nothing
	# visible. (It also makes a reconnect safe: the incumbents froze this peer's
	# old contribution in _gone_coins, and coming back at zero is what stops it
	# being counted twice.)
	own_coins = 0
	# The personal distance record restarts from where we arrived, or the group's
	# kilometres are banked into user://best_run.cfg as ours (see the field).
	own_distance = 0
	own_distance_origin = Vector2(global_position.x, global_position.z)
	# run_distance goes with them, and for the same reason one level up: it is a
	# running MAX and it is what this peer publishes as the room's distance (`dd`
	# in presence, and shared_distance()'s own input). Left at a long solo run's
	# value it would not merely look wrong here — a peer that walked 3 km alone and
	# then joined a room 100 m in would raise the shared distance to 3 km for
	# EVERYONE, permanently, because a max never comes back down. The room's real
	# figure arrives from the snapshots and the next presence packet.
	run_distance = 0
	# ...and so does the record LATCH, because it is derived from the coins the
	# lines above just wiped. It is set by `_bank_records()` on a bite and read
	# once at the ending; left standing from a solo leg it would flash "NEW BEST!"
	# over a room leg that started at zero and beat nothing.
	run_beat_record = false
	record_coins = 0
	# ...AND SO DOES BUDAPEST. This peer's solo walk is not the room's: the mask is
	# unioned across the room and the win is decided off it, so a joiner arriving
	# with a finished solo mask would win somebody else's run on its first `room`
	# packet — and a partial one would make this the only peer counting landmarks
	# nobody else has (codex review 2026-09-02). The room's set arrives whole in the
	# master's join snapshot (`lm`) moments later.
	explored_mask = 0

	# JOINING FROM THE GAME OVER SCREEN IS A SUPPORTED FLOW — mp_ui deliberately
	# does not pause over it, so the panel's Join button works there. Without this
	# the joiner is placed beside the group and left frozen: is_game_over
	# early-returns _physics_process above _refresh_shared_totals, so the room's
	# bank never even reaches it. The room owns the roster from the next tick.
	if is_game_over:
		is_game_over = false
		run_outcome = Outcome.CAPTURED
		is_caught = false
		is_respawning = false
		ability_cooldowns.fill(0.0)  # Frozen at full since the run ended (see restart_game).
		_hide_respawn_message()
		var over_ui := get_tree().get_first_node_in_group("game_over_ui")
		if over_ui and over_ui.has_method("hide_game_over"):
			over_ui.hide_game_over()
		if not MobileSensors.is_touch_session():
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# A joiner must not be bitten on its first frame in somebody else's run.
	clear_nearby_crocodiles(global_position)

	# Drop any mid-blink i-frames / active ability state and restore model
	# visibility for the current view (idempotent — see _apply_view_mode).
	respawn_blink_timer = 0.0
	_apply_view_mode()
	_reset_ability_states()

	print("Joined the run near %v" % anchor)


func _place_near(anchor: Vector3) -> void:
	"""
	Put the body down on a clear spot beside `anchor` and reset it to the neutral
	pose the origin spawn uses. Shared by the two moments a player is set down
	next to the group: the mid-run join (`join_at`) and, in a room, the
	death respawn (`_respawn_in_place`).

	Find a clear spot on a ring around the anchor so we never materialise inside
	a block. Nearest ring first, JOIN_RING_ANGLES evenly spaced candidates each,
	taking the first the body actually fits in — the same probe Primm's Phase
	Step lands with, which ignores the flat ground and only senses what rises
	above it. The ground IS flat, so every one of the ~32 candidates being
	blocked needs a landscape of solid stone; the anchor itself is the fallback
	for that, and at worst costs one shove-out from the physics engine.

	IT MOVES THE BODY AND NOTHING ELSE — no coins, no heroes, no distance, no run
	state. Both callers own their own bookkeeping, and keeping it out of here is
	exactly what lets one of them zero a solo tally while the other carries a
	live run across the teleport untouched.

	@param anchor: world position to arrive next to.
	"""
	var spot := anchor
	for radius: float in JOIN_RING_RADII:
		var placed := false
		for i: int in range(JOIN_RING_ANGLES):
			var angle: float = TAU * i / float(JOIN_RING_ANGLES)
			var candidate := Vector3(anchor.x + cos(angle) * radius, 0.0, anchor.z + sin(angle) * radius)
			if not _is_body_blocked_at(candidate):
				spot = candidate
				placed = true
				break
		if placed:
			break

	global_position = Vector3(spot.x, JOIN_SPAWN_HEIGHT, spot.z)
	velocity = Vector3.ZERO
	rotation.y = SPAWN_FACING_Y  # Face down the coin road, like the origin spawn
	camera_pitch = 0.0
	camera_yaw_lag = 0.0
	if camera_pivot:
		camera_pivot.rotation = Vector3.ZERO  # Whole rotation, so roll can't survive
	is_ducking = false
	is_running = false
	# Lift the model back out of the water, exactly as reset_position() does and
	# for the same reason: this is a teleport, so the river we were standing in is
	# not here any more. It matters most on the in-room respawn, where the grace
	# freeze early-returns out of _physics_process — without this the hero (and,
	# in first person, the camera) would sit 0.35 m sunk at the group's dry feet
	# for the whole countdown. Landing in ANOTHER river just eases straight back
	# down over the next fifth of a second, which is the correct reading of
	# "arrived somewhere new".
	_wade_sink = 0.0
	_apply_wade_sink()


# ============================================================================
# DEBUG-ONLY TELEPORT (\fb BUDAPEST GATE / \fh HQ — BEADS godot-test1-xtl / a7i)
# ============================================================================

static func debug_teleport_allowed(debug_build: bool, in_room: bool) -> bool:
	"""Whether the debug teleport may fire: debug builds only, never in a room.

	The two halves of the bead's gate as one testable predicate. The caller
	passes the REAL `OS.is_debug_build()` and the REAL room state; the check
	drives all four corners of this table.
	"""
	return debug_build and not in_room


static func debug_destination_budapest() -> Vector3:
	"""Where \\fb lands: inside Budapest past the gate, on the avenue.

	40 m inside the gate (BudapestPlan.GATE is the rect's west edge) is avenue,
	not wall; `_place_near()` ring-probes the exact clear spot from there, so
	this only has to name the neighborhood.
	"""
	return BudapestPlan.GATE + Vector3(40.0, 0.0, 0.0)


func debug_destination_hq() -> Vector3:
	"""Where \\fh lands: on the flat HQ ground outside the tower's dry disc.

	The site plus the disc radius plus a margin — the same "beside it, not in
	it" the join anchor uses. Read off the terrain (an instance const access,
	the minimap's `_terrain.TOWER_RADIUS` precedent), never a second copy of
	the site: `tower_site()` is a CONSTANT today and a retune must move this
	with it.
	"""
	var terrain := get_tree().get_first_node_in_group("terrain")
	if terrain != null and terrain.has_method("tower_site"):
		var site: Vector3 = terrain.tower_site()
		return site + Vector3(terrain.TOWER_RADIUS + 20.0, 0.0, 0.0)
	return Vector3(0.0, 2.0, 0.0)


func _debug_in_room() -> bool:
	"""Whether this player is in a multiplayer room, by `restart_game()`'s idiom:
	a settled room has a bank to share, and solo (or arriving) has null.
	"""
	var mp := _mp()
	return mp != null and mp.has_method("shared_bank") and mp.shared_bank(own_coins) != null


func debug_teleport_to(dest: Vector3) -> bool:
	"""Put the player at `dest` for a \fo perf reading, rebuilding the world
	under them. Returns false — placing NOTHING — when the gates refuse (release
	build, room, reentrant press) or the world is missing.

	THIS PRESERVES THE RUN: coins, streak, explored mask, heroes, captives —
	everything a measurement is taken OF. A teleport is a walk at infinite
	speed: chunk content is seed-deterministic (walking away and back rebuilds
	the same chunks), and every run total lives on the player, which this never
	touches. `join_at()`'s zeroing is room bookkeeping this path must not do.
	Proximity systems (landmark exploring, croc aggro) will of course notice the
	new neighborhood on arrival — that is what "debug-only" means: this must
	never be reachable in a release build, or it trivially defeats the win
	condition, the difficulty ramp and the road.

	NOT TOTAL, and the exception is the HQ: `new_run()` re-seeds even with the
	same value, and `set_run_seed()` resets the tower — so the shell re-streams
	and its PER-RUN interior state (taken dossiers, guards, the LOD scent
	trails) comes back. The monotone opened set is a store and survives.

	DISTANCE IS THE ONE THING A JUMP CANNOT LEAVE ALONE, and the file already
	knows what to do about it: `own_distance` is measured from
	`own_distance_origin`, so shifting that origin by exactly the jump leaves
	the PERSONAL figure — the one a bite banks — untouched, which is what
	`_respawn_in_place()` and `join_at()` both do for their own teleports.
	`run_distance` is a running max of raw displacement from the world origin
	and therefore moves with the body by definition; nothing persists it
	(`_bank_records` submits distance as 0) and the key is dead in a room, so
	it is left to tell the truth about where the body is.

	ABSENT IN ROOMS: the key is dead there and this returns false. A peer's
	position is mesh-published truth, and a teleport mid-arrival would fight
	`MpManager._apply_join_placement()`'s own placement; the arrival path wins
	by construction because it runs last.

	The re-seat is `MpManager._apply_join_placement()`'s sequence, minus the
	seed change it needs and we must not do: `new_run` with the CURRENT seed
	re-centres an identical world, `build_ring_now()` buys the ring's blocks
	and crocodiles up front so `_place_near()`'s probes see real geometry, and
	the physics-frame wait lets the physics space learn the new chunks before
	any probe runs (placing before it probes the OLD world and drops you inside
	a wall — the comment over there).
	"""
	if not debug_teleport_allowed(OS.is_debug_build(), _debug_in_room()):
		return false
	if _debug_teleport_busy:
		return false
	var terrain := get_tree().get_first_node_in_group("terrain")
	if terrain == null or not terrain.has_method("new_run") \
			or not terrain.has_method("world_to_chunk") \
			or not terrain.has_method("build_ring_now"):
		return false
	_debug_teleport_busy = true
	var chunk: Vector2i = terrain.world_to_chunk(dest)
	terrain.new_run(terrain.run_seed, chunk)
	terrain.build_ring_now(chunk)
	await get_tree().physics_frame
	var from_xz := Vector2(global_position.x, global_position.z)
	_place_near(dest)
	# A TELEPORT IS NOT DISTANCE RUN — `_respawn_in_place()`'s line, verbatim.
	own_distance_origin += Vector2(global_position.x, global_position.z) - from_xz
	clear_nearby_crocodiles(global_position)
	respawn_blink_timer = 0.0
	_apply_view_mode()
	_reset_ability_states()
	_debug_teleport_busy = false
	return true


func _room_group_anchor() -> Variant:
	"""
	Where the room's other members are standing, or `null` when there is no room
	(or no manager at all, so the player scene still runs standalone). One
	null-safe hop into the `"mp"` group, the same shape as `_sfx()` and
	`_weather_is_raining_here()`.
	"""
	var mp := _mp()
	if mp != null and mp.has_method("group_anchor"):
		return mp.group_anchor()
	return null


# ============================================================================
# SECTION 8: SPECIAL ABILITIES (F KEY)
# ============================================================================
## Every character has ONE signature power, fired with F (the "special_ability"
## input action). They all share a per-character cooldown and a HUD dial:
##
##   * windman  — Air Rush:   launches into the sky and flies at ~5× walk speed
##                            with softened gravity for a few seconds. INDOORS the
##                            same key is AIR SIGHT instead: the HQ's walls go
##                            translucent for a few seconds so he can watch a patrol
##                            through them. One ability, two rooms — see
##                            `_ability_air_sight()`.
##   * primm    — Phase Step: blinks straight forward THROUGH a block, never
##                            stopping inside it (an instant short teleport).
##   * teibi    — Resize:     cycles normal → small → giant → normal. Giant Teibi
##                            is fearless and CRUSHES any crocodile it touches.
##   * phoboman — Stink Wave: belches expanding waves of stench; every crocodile
##                            turns tail and flees for several seconds.
##
## Cooldowns are tracked PER CHARACTER (one timer each), so switching characters
## shows that character's own readiness on the HUD. Discovery stays group-based
## (crocodiles via the "crocodile" group), matching the rest of the project.

## One-shot expanding "wave" visual, reused by several abilities. We spawn it into
## the world (parented to our parent) so it lives on its own and frees itself.
const ABILITY_EFFECT := preload("res://scripts/ability_effect.gd")

## Per-character cooldown length, in seconds. Tunable — longer for stronger powers.
const ABILITY_COOLDOWN := {
	"windman": 8.0,
	"primm": 6.0,
	"teibi": 4.0,
	"phoboman": 12.0,
}

## Per-character movement speed multiplier, applied to duck/run/walk in
## calculate_current_speed() (NOT to Windman's Air Rush — that ability defines
## its own absolute speed). The spread is deliberately modest (0.9–1.15) so
## every character stays playable: Primm is the sprinter, Teibi the tank whose
## power compensates, and the others sit near baseline.
const CHARACTER_SPEED := {
	"windman": 1.0,
	"primm": 1.15,
	"teibi": 0.9,
	"phoboman": 1.05,
}

## Friendly ability names shown on the cooldown HUD.
const ABILITY_NAME := {
	"windman": "Air Rush",
	"primm": "Phase Step",
	"teibi": "Resize",
	"phoboman": "Stink Wave",
}

# --- Windman: Air Rush ---
## Top air speed during the boost (5× walk speed — "like Shift pressed five times").
const WINDMAN_AIR_SPEED: float = WALK_SPEED * 5.0
## How long the boost lasts, in seconds.
const WINDMAN_BOOST_DURATION: float = 4.0
## Gravity multiplier while boosting, so Windman glides instead of dropping.
## Retuned with the snappy-jump gravity change: 14.4 × 0.1125 = 1.62 m/s² —
## byte-identical to the old 3.6 × 0.45, so the Air Rush glide feel is
## preserved exactly even though base gravity quadrupled.
const WINDMAN_GRAVITY_FACTOR: float = 0.1125
## Upward launch applied on activation so he gets airborne to use the speed.
const WINDMAN_LIFT: float = 6.0

# --- Windman: Air Sight (bead godot-test1-oht) ---
## INDOORS, F IS A DIFFERENT ABILITY. Air Rush is a take-off and the HQ has a
## ceiling 4.6 m up, so in there the same key spends the same cooldown on the other
## half of "make the air work for him": the walls of the storey you are on go
## translucent and you can watch a patrol through them before committing to a
## corridor. Same dispatch, same cooldown dial, same block-reason surface — the
## branch is one `if` in `_ability_windman()` and everything downstream is unchanged.
##
## How long the walls stay see-through, in seconds. Long enough to read a room and
## watch one guard's leg of a patrol, short enough that the fill-rate cost of a
## storey of transparent walls on web `gl_compatibility` is a window and not a mode.
##
## IT IS NOT BOUNDED BY THE COOLDOWN AND MUST NOT BE MADE TO BE (codex review): 8.0 s
## is the UNSKILLED cooldown, and `_skilled_ability_cooldown()` takes a fully-ranked
## Windman to 4.80 s — under this duration, so a press on every recharge would hold
## the building transparent forever. That is the `"LAND"` gate's bug exactly, one
## ability along, and it takes the same answer: the STATE INVARIANT that was missing,
## not a retune. `"SEEING"` refuses the press while a look is already running, so
## cooldown ranks stay a straight buff (they shorten the wait, never the look) and
## the x-ray is a window whatever the skill tree says.
const WINDMAN_SIGHT_DURATION: float = 7.0

## The name the HUD gives Windman's F under the roof. A const rather than a literal
## because `help_selfcheck` reads it: the `?` card names every ability by walking
## `ABILITY_NAME`, and an ability that is not in that dict — because it is a second
## ability on an existing hero, not a fifth hero — would otherwise be the one thing
## the card is allowed to be silently wrong about.
const INDOOR_ABILITY_NAME: String = "Air Sight"

# --- Primm: Phase Step ---
## Desired blink distance — far enough to clear a single block in open ground.
const PRIMM_BLINK_DISTANCE: float = 6.0
## If the desired landing spot is inside a block, keep scanning outward in steps
## of this size until a clear spot is found (so Primm always exits the far side).
const PRIMM_BLINK_STEP: float = 0.5
## How far out the scan looks before giving up (covers any structure in-game).
const PRIMM_BLINK_MAX_DISTANCE: float = 40.0

# --- Teibi: Resize ---
## Scale factors for the small and giant forms (1.0 is the normal size).
const TEIBI_SCALE_SMALL: float = 0.45
const TEIBI_SCALE_BIG: float = 2.2
## How much the giant-fit probe pulls its capsule in AT THE BOTTOM ONLY before
## asking the physics server whether the grown body fits (`_teibi_grow_blocked`).
##
## The floor the player is standing on is always touching the capsule's bottom, so
## an honest full-size probe reports "blocked" everywhere and Resize would never
## grow at all. 5 cm is under any real clearance in the game and far more than the
## contact epsilon. The TOP is never trimmed: this number is an allowance for the
## floor, and spending it at the head would licence 5 cm of skull inside a ceiling.
const TEIBI_FIT_GROUND_CLEAR: float = 0.05

## How long Teibi may stay in an altered form (small OR giant) before he snaps
## back to normal on his own — no extra press needed. This is a TOTAL budget for
## the whole small/giant excursion: switching small↔giant does not refill it.
const TEIBI_FORM_DURATION: float = 10.0

## How long the automatic revert waits before asking AGAIN whether the normal
## capsule fits where the body is standing (bd godot-test1-3iy.23, codex review).
##
## The timeout used to grow the body back unconditionally, which was harmless while
## every space in this game was at least 2 m tall. The HQ's crawl alcove is 1.2 m,
## so a small Teibi whose form expires in there would have been inflated INSIDE
## solid stone and squirted out along whichever axis the depenetration liked —
## `_teibi_grow_blocked`'s bug, in the other direction. So the revert waits for
## room instead of forcing it, and this is how often it re-asks: five times a
## second, which is instant to a player walking out and costs one shape query per
## tick for one hero in a place he can only be by choosing to crawl in. Nothing can
## strand him — SMALL is not a penalty, F is not refused indoors, and the first
## frame the capsule fits he stands up.
const TEIBI_REVERT_RETRY: float = 0.2

## Seconds of shockwave flight Teibi's Crush Quake buys (the `quake` skill node).
## Deliberately far shorter than Phoboman's whole ability — the quake is a
## side-effect of a transformation Teibi wanted anyway, not a fear power.
const TEIBI_QUAKE_FLEE_DURATION: float = 3.0

# --- Phoboman: Stink Wave ---
## How long crocodiles flee after one whiff, in seconds.
const PHOBOMAN_FLEE_DURATION: float = 10.0
## Visual reach of the stink waves, in metres.
const PHOBOMAN_STINK_RADIUS: float = 9.0
## GAMEPLAY reach of the stink — how far a crocodile may be and still flee.
##
## THIS IS NEW IN BEAD godot-test1-20z.4 AND IT IS A DELIBERATE NERF; the number
## is derived rather than picked. Before it, `_ability_phoboman()` walked the
## whole "crocodile" group with no distance test at all, so the ability's only
## bound was an accident of `flee_from()`'s slept-crocodile early return (the LOD
## manager sleeps past `SIM_RADIUS` + hysteresis = 50 m). One press therefore
## disarmed every crocodile within ~50 m — including the pack 40 m down the road
## the player was about to run into — while the telegraph the player saw was a
## 9 m sphere. It also made `phoboman_radius` (Billowing Cloud) a node that cost
## a point and changed nothing but the picture.
##
## 22 m is the smallest honest bound: `DETECTION_RADIUS` is 15, so nothing
## outside 15 m can acquire the player at all, and the extra 7 m covers a
## crocodile closing at `MAX_CHASE_SPEED` (8.5) for the ~0.8 s the wave takes to
## play. Bosses are unaffected either way — `flee_from()` early-returns for one.
## So the crocodiles that stop being feared are the ones in the 22–50 m band,
## which could not have hunted the player during the flight anyway: the nerf is
## real on paper and close to invisible in play, and it buys a live skill node.
const PHOBOMAN_FLEE_RADIUS: float = 22.0

## Per-character cooldown timers (seconds remaining; 0 = ready). Sized in _ready().
var ability_cooldowns: Array[float] = []

## Windman boost time remaining (seconds; > 0 means the Air Rush is active).
var windman_boost_timer: float = 0.0

## Seconds left on an Adrenaline speed burst (0 = none running). THE ONE ACTIVE
## SKILL WITH NO KEY: it is triggered by a passive event (crossing a streak step
## in `collect_coin`) precisely so it costs no second keybind, no second cooldown
## dial and no third touch button — see `Progression.SKILL_TREES`' header. Read
## by `_skill_gait_mult()`, ticked by `_update_ability_timers()`, cleared by
## `_reset_ability_states()` like every other transient ability state.
var speed_burst_timer: float = 0.0

## Seconds of cooldown an ability earned back DURING its own activation, consumed
## by `try_activate_ability()` the moment it charges the cooldown. Written only by
## an ability that returns true (today: Primm's Phase Echo, on a wall-pass) and
## zeroed on use and on respawn, so it can never leak into the next press.
var _pending_cooldown_refund: float = 0.0

## Cached `Progression` node — see `_progression()` for why this one is cached
## when the sibling weather/terrain lookups beside it are not.
var _progression_node: Node = null

## Seconds left of Windman's Air Sight (0 when it is not running). Transient ability
## state like `windman_boost_timer` beside it: ticked by `_update_ability_timers()`,
## cleared by `_reset_ability_states()` on a switch, a respawn and a game over, and
## dropped early by walking back out of the building.
var windman_sight_timer: float = 0.0

## Teibi's size cycle: 0 = normal, 1 = small, 2 = giant.
var teibi_size_state: int = 0

## Seconds left in Teibi's current altered form before it auto-reverts to normal
## (0 while he is normal). See TEIBI_FORM_DURATION.
var teibi_form_timer: float = 0.0

## True only while Teibi is giant — makes him crush crocodiles on contact.
var is_giant: bool = false

## The Teibi resize scale tween, when one is animating character_container.scale
## (null/finished otherwise). The landing squash checks it so the two writers of
## that property never fight.
var _teibi_tween: Tween = null


func _mp() -> Node:
	"""
	The multiplayer manager, or null when there is none in the tree (solo play,
	or the player scene run on its own). The single door every multiplayer read
	in this script goes through — same null-safe group lookup shape as
	_weather_is_raining_here() / _terrain_is_river_here() below.
	"""
	return get_tree().get_first_node_in_group("mp")


func _refresh_shared_totals() -> void:
	"""
	While in a multiplayer room, overwrite the two DISPLAYED score fields with the
	room's totals: the bank is the sum of every member's own coins, and the
	distance the furthest anyone has reached. There is no third total — hearts
	were the room's other shared number and heroes are the lives now (owner ruling
	2026-08-31), so the room's shared death state is the captive set alone, which
	rides the mesh and is read where a run actually ends (`_on_caught_finished()`).

	coin_hud.gd is deliberately NOT edited — it reads these very fields, so it
	shows the room's numbers in a room and this peer's own numbers solo, with no
	branch of its own.

	Offline (or with no room joined) every call below answers null and nothing is
	written, so solo play is byte-for-byte what it was.
	"""
	var mp := _mp()
	if mp == null or not mp.has_method("shared_bank"):
		return
	var bank: Variant = mp.shared_bank(own_coins)
	if bank == null:
		# Manager present but no room: solo semantics, untouched — EXCEPT on the
		# frame the room ends. The displayed fields are still holding the room's
		# totals and nothing else ever writes them back, so a room's four-figure
		# bank would sit in coins_collected for the rest of the solo run. Restore
		# this peer's own numbers.
		if _showing_shared_totals:
			_showing_shared_totals = false
			coins_collected = own_coins
			run_distance = own_distance
		return
	_showing_shared_totals = true
	coins_collected = int(bank)


func _weather_is_raining_here() -> bool:
	"""
	Whether the player is standing in a storm cloud's rain zone, asked of the
	weather manager through the "weather" group — null-safe with a has_method
	guard exactly like _sfx(), so a scene without the manager (or the player
	scene run on its own) simply answers "no rain" instead of erroring.
	"""
	var weather := get_tree().get_first_node_in_group("weather")
	if weather and weather.has_method("is_raining_at"):
		return weather.is_raining_at(global_position)
	return false


func _sheltered() -> bool:
	"""
	Whether the body is under the HQ's roof, asked of the shell through the "tower"
	group — the same null-safe group + has_method shape as `_weather_is_raining_here()`
	above, so a scene with no tower in it (the player run standalone, most of the
	self-checks) simply answers "outdoors".

	THE BUILDING OWNS THIS QUESTION and always did — `sheltered()` is what already
	keeps the rain off Windman indoors (`weather_manager._sheltered_at`). Two indoor
	ability rules read it now: Windman's F becomes Air Sight in here, and Teibi may
	not be giant in here at all. Neither restates the envelope's numbers, which is
	the whole reason the predicate lives on the shell.

	Cheap enough for the per-frame paths that consume it (`get_ability_block_reason()`
	is polled by the HUD): one group lookup plus one transform multiply and three
	compares, no allocation.
	"""
	var tower := get_tree().get_first_node_in_group("tower")
	if tower and tower.has_method("sheltered"):
		return bool(tower.call("sheltered", global_position))
	return false


func _terrain_is_river_here() -> bool:
	"""
	Whether the player is standing IN a river, asked of the terrain through the
	"terrain" group — the same null-safe group + has_method shape as
	_weather_is_raining_here() above and _sfx(), so the player scene run on its
	own (no EndlessTerrain in the tree) simply answers "no river" instead of
	erroring.

	IT ASKS `is_wading_at`, NOT `is_river_at` (bead godot-test1-06o.2), and the
	difference is the Y. `is_river_at` is the BAND — XZ-only, the same function
	the ground shader paints, and it stays that way. Whether a BODY is in the
	water is a narrower question, because the body may be standing on a bridge
	deck over the band; that rule lives in ONE place on the terrain and this is
	one of its three callers (the remote avatar and the crocodile's river sink are
	the others).

	EDUCATIONAL NOTE:
	- is_wading_at() is a height compare and, only if that passes, one evaluation
	  of the terrain's biome noise: no allocation, no physics query, no node
	  lookup beyond this one — cheap enough to ask every physics tick, which is
	  exactly what _physics_process does.

	@return bool: true when the player is standing in the water here.
	"""
	var terrain := get_tree().get_first_node_in_group("terrain")
	if terrain and terrain.has_method("is_wading_at"):
		return terrain.is_wading_at(global_position)
	return false


# --- Meta-progression skills (bead godot-test1-20z.3) ------------------------
#
# The passive skill trees are DATA in `scripts/progression.gd`, and they reach
# gameplay by multiplying an existing constant AT ITS POINT OF USE. The constants
# below stay `const`: `WINDMAN_BOOST_DURATION` is still 4.0 seconds and
# `ABILITY_COOLDOWN["teibi"]` is still 4.0 — a skilled hero simply reads
# `CONST * _skill_mult("...")` where it used to read `CONST`.
#
# Everything goes through the two null-safe lookups below, modelled on
# `_weather_is_raining_here()` / `_terrain_is_river_here()`: no Progression node
# in the tree (the player scene run standalone, the self-checks, any scene
# without `Main`) means every multiplier is 1.0 and every bonus 0.0, i.e. the
# game before this bead, exactly.

func _progression() -> Node:
	"""
	The Progression node, or null. Group lookup, no hard reference — but CACHED,
	because two of the callers really are per-frame paths: `_skill_gait_mult()`
	runs from `calculate_current_speed()` in `_physics_process`, and
	`_skilled_ability_cooldown()` runs from `get_ability_cooldown_ratio()`, which
	`ability_hud.gd` polls every frame. Same caching (and the same
	`is_instance_valid` re-resolve) as `coin_hud.gd` and the skill panel, for the
	same reason: a group lookup per frame for a node that may legitimately never
	exist is the wrong shape.

	A null result is deliberately NOT cached — a scene with no Progression node
	pays one lookup per frame, exactly as `_weather_is_raining_here()` and
	`_terrain_is_river_here()` beside it already do, and the node cannot appear
	late in any scene that has one.
	"""
	if _progression_node == null or not is_instance_valid(_progression_node):
		var node := get_tree().get_first_node_in_group("progression")
		_progression_node = node if node != null and node.has_method("skill_mult") else null
	return _progression_node


func _skill_mult(effect: String) -> float:
	"""
	The skill multiplier for `effect` on the CURRENT character, or 1.0 when there
	is no progression. The hard caps (−40% cooldown, +20% run speed) live inside
	`Progression.skill_mult()`, so no call site can breach one by accident.
	"""
	var progression := _progression()
	if progression == null:
		return 1.0
	return float(progression.skill_mult(CHARACTERS[current_character_index]["name"], effect))


func _skill_bonus(effect: String) -> float:
	"""
	The raw summed bonus for `effect` (0.0 with no progression) — for the one
	effect that is a flat amount rather than a factor, Primm's cooldown refund.
	"""
	var progression := _progression()
	if progression == null:
		return 0.0
	return float(progression.skill_bonus(CHARACTERS[current_character_index]["name"], effect))


func _skill_gait_mult() -> float:
	"""
	The run/duck multiplier for the current character in its current form, capped
	at `RUN_SPEED_MULT_MAX` over ALL movement passives together (Fleet Foot and
	Teibi's small-form Scurry). One call, so the cap has one home — see
	`Progression.gait_mult()`. 1.0 with no progression.
	"""
	var progression := _progression()
	if progression == null:
		return 1.0
	return float(progression.gait_mult(
		CHARACTERS[current_character_index]["name"], teibi_size_state == 1,
		speed_burst_timer > 0.0
	))


func _update_ability_timers(delta: float) -> void:
	"""Count down cooldowns, the Windman air boost, Teibi's form timer and the
	Adrenaline speed burst."""
	for i in ability_cooldowns.size():
		if ability_cooldowns[i] > 0.0:
			ability_cooldowns[i] = maxf(0.0, ability_cooldowns[i] - delta)
	if speed_burst_timer > 0.0:
		speed_burst_timer = maxf(0.0, speed_burst_timer - delta)
	if windman_boost_timer > 0.0:
		windman_boost_timer = maxf(0.0, windman_boost_timer - delta)
		# Wet wings: a Windman who flies INTO a storm cloud's rain zone drops out
		# of the Air Rush immediately — the boost timer is zeroed and the normal
		# gravity/speed rules take back over mid-air. (Only checked while a boost
		# is actually running, so a grounded player never pays for this.)
		if windman_boost_timer > 0.0 and _weather_is_raining_here():
			windman_boost_timer = 0.0
	if windman_sight_timer > 0.0:
		windman_sight_timer = maxf(0.0, windman_sight_timer - delta)
		# Walking back out ends it too — the same shape as the wet-wings drop above,
		# and for the same reason: the ability is a property of being INSIDE this
		# building, so carrying it out of the door would leave a translucent HQ
		# standing behind a player who is no longer in it. (Only asked while the
		# sight is actually running, so nobody else pays for the lookup.)
		if windman_sight_timer <= 0.0 or not _sheltered():
			_end_air_sight()
	# Teibi's small/giant form expires on its own after a while, snapping him back
	# to normal size with no extra press — so he can never get stuck transformed.
	if teibi_size_state != 0 and teibi_form_timer > 0.0:
		teibi_form_timer = maxf(0.0, teibi_form_timer - delta)
		if teibi_form_timer <= 0.0:
			# ...BUT ONLY WHERE THE NORMAL BODY FITS (bd godot-test1-3iy.23, codex
			# review). Inflating inside stone is the exact shape of the tower breach
			# `_teibi_grow_blocked` closes, and the HQ's 1.2 m crawl alcove is the
			# first space in this game a normal capsule does not fit in. The revert
			# is DEFERRED, never cancelled: `TEIBI_REVERT_RETRY` re-asks five times a
			# second and the first frame there is room he stands up. The forced
			# reverts below and in `_reset_ability_states()` are unconditional on
			# purpose — a character switch, a respawn and the no-giant-indoors ruling
			# are not the body's decision to make.
			if _teibi_fit_blocked(1.0):
				teibi_form_timer = TEIBI_REVERT_RETRY
			else:
				_revert_teibi_to_normal()
	# NO GIANT INSIDE THE HQ, EVER (bead godot-test1-xdf). `get_ability_block_reason()`
	# refuses the press in there, which leaves exactly one way the state could still
	# exist indoors: growing outside and walking in. So it reverts AT THE DOOR, down
	# the same path the form timer uses, and the ruling ("Teibi can't be huge inside
	# the HQ") becomes a property of the body rather than of the door being watched.
	# Asked only while he is actually giant — a normal-size hero pays nothing.
	if is_giant and _sheltered():
		_revert_teibi_to_normal()


func _cooldown_remaining() -> float:
	"""
	The cooldown that stands in the way of an F press RIGHT NOW, in seconds —
	which is NOT always the timer sitting in `ability_cooldowns`.

	THIS IS THE ONE HOME OF THE COOLDOWN READ, for exactly the reason
	`get_ability_block_reason()` is the one home of the gates: the key press, the
	dial's arc, the dial's seconds text and `is_ability_ready()` all ask it, so
	the HUD can never paint an amber countdown over a press that fires. A waiver
	written at the press alone IS that bug — and the dial's three states come out
	of the ratio and `is_ability_ready()`, so it would have shown up in both.

	THE WAIVER (bead godot-test1-8rg, owner: "teibi shouldn't mandatory wait in
	tiny state cooldown to become giant"): while Teibi is ALREADY in an altered
	form, the next resize is free. Normal → small is the press that costs the 4 s;
	small is the weakest state in the game, and being parked there for a whole
	cooldown read as a punishment for using the ability rather than as its price.
	ENTERING an altered form from normal still pays, because `teibi_size_state` is
	0 at that press — the waiver cannot fire on the press that starts the cycle.

	IT WAIVES THE COOLDOWN AND NOTHING ELSE. `try_activate_ability()` asks the
	gates AFTER this, so INDOOR (no giant in the HQ, bead godot-test1-xdf) and
	TIGHT (`_teibi_grow_blocked()`) refuse a waived press exactly as they refuse a
	charged one; and the form budget is untouched, so a giant reached sooner is
	reached out of the SAME `TEIBI_FORM_DURATION` (`_ability_teibi()` refills it
	only from `prev_state == 0`) — a faster giant, never a longer one.

	The character name is checked as well as the state because `ability_cooldowns`
	is per-hero: a stale non-zero `teibi_size_state` must not be able to waive
	somebody else's cooldown. (It cannot today — every switch reverts him — which
	is why this is a belt, not a fix.)
	"""
	if teibi_size_state != 0 and String(CHARACTERS[current_character_index]["name"]) == "teibi":
		return 0.0
	return ability_cooldowns[current_character_index]


func try_activate_ability() -> void:
	"""
	Fire the current character's special ability if it isn't on cooldown. Each
	ability function returns true when it actually triggered, which is what starts
	the cooldown — so a no-op never locks the power.
	"""
	var char_name: String = CHARACTERS[current_character_index]["name"]

	# Still cooling down? The press doesn't fire, but it must not feel dead:
	# flash the cooldown dial red (via the "ability_hud" group — null-safe, no
	# hard reference, like every other HUD hookup) and play a low denial buzz.
	# Asked through `_cooldown_remaining()` so this press and the dial read the
	# same number — see the waiver documented there.
	if _cooldown_remaining() > 0.0:
		_flash_blocked_feedback()
		return

	# Charged, but is anything else in the way? The gates live in ONE function so
	# the HUD can ask the same question the key press asks — see
	# `get_ability_block_reason()`. A gated press refuses exactly like a cooling
	# one (same dial flash, same denial buzz) and costs no cooldown, so the player
	# can try again the instant the gate lifts.
	if get_ability_block_reason() != "":
		_flash_blocked_feedback()
		return

	var used := false
	match char_name:
		"windman":
			used = _ability_windman()
		"primm":
			used = _ability_primm()
		"teibi":
			used = _ability_teibi()
		"phoboman":
			used = _ability_phoboman()

	if used:
		# The skilled duration, and it MUST be the same expression
		# `get_ability_cooldown_ratio()` divides by — see the note there.
		var cooldown := _skilled_ability_cooldown()
		# ...minus anything an ability earned back on the way through (Primm's
		# Phase Echo). A generic one-shot rather than a Primm branch: it costs one
		# float, and the active-skills bead has more of these coming.
		cooldown = maxf(0.0, cooldown - _pending_cooldown_refund)
		_pending_cooldown_refund = 0.0
		ability_cooldowns[current_character_index] = cooldown
		# Whoosh only when the ability actually fired — a failed Primm blink that
		# costs no cooldown stays silent too.
		_sfx("play_ability", char_name)


func _flash_blocked_feedback() -> void:
	"""
	The one "that press was refused" signal: flash the cooldown dial red (via the
	"ability_hud" group — null-safe, no hard reference, like every other HUD
	hookup) and play the low denial buzz. Shared by the cooling-down F press,
	Windman-in-the-rain, and an E press locked to a single hero by the lobby, so
	a refusal always feels the same wherever it comes from.
	"""
	var hud := get_tree().get_first_node_in_group("ability_hud")
	if hud and hud.has_method("flash_blocked"):
		hud.flash_blocked()
	_sfx("play_buzz")


func _ability_windman() -> bool:
	"""Air Rush: launch up and forward, then soar fast with softened gravity —
	or, under the HQ's roof, Air Sight instead (see `_ability_air_sight`)."""
	if _sheltered():
		return _ability_air_sight()
	var forward := -transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()

	windman_boost_timer = WINDMAN_BOOST_DURATION * _skill_mult("windman_boost")
	# Kick the lens wide for the launch moment — the FOV code in _process adds
	# this on top of the speed-scaled target and decays it back to zero.
	fov_punch = FOV_PUNCH_WINDMAN
	# Launch: up so he is airborne, plus an immediate forward shove so even a
	# standing press blasts off into the wind right away.
	#
	# WINDMAN_LIFT is the ONE thing a skill may make jump higher, and that is an
	# epic-level decision rather than a local one: mountain massifs are impassable
	# because the base jump apex (3.6125 m) is under MOUNTAIN_MIN_LAYER_HEIGHT
	# (4.0), so there is deliberately NO skill anywhere touching JUMP_VELOCITY.
	# The "fly higher" fantasy routes through Air Rush, which is already the
	# sanctioned way over terrain.
	velocity.y = WINDMAN_LIFT * _skill_mult("windman_lift")
	velocity.x = forward.x * WINDMAN_AIR_SPEED
	velocity.z = forward.z * WINDMAN_AIR_SPEED

	# An airy cyan swirl around him to sell the gust.
	_spawn_ability_effect(global_position, Color(0.7, 0.92, 1.0, 0.4), 5.0, 0.6)
	return true


func _ability_air_sight() -> bool:
	"""
	Air Sight: for `WINDMAN_SIGHT_DURATION` the walls of the storey Windman is on go
	translucent, so he can read the layout and — the point — watch a guard's patrol
	through them before stepping into a corridor.

	WINDMAN'S INDOOR F, and it is the same ability rather than a fifth one: the wind
	is what he bends either way, and Air Rush under a 4.6 m ceiling was already a
	press that did nothing worth doing. Everything around it is untouched — the same
	dispatch, the same cooldown, the same dial, the same refusal surface.

	THE BUILDING DOES THE WORK (`TowerInterior.set_xray`), through the same null-safe
	group + `has_method` door every other system reads. No interior in the tree means
	no ability: `false` back, so `try_activate_ability()` charges no cooldown and the
	press can be tried again the moment he is somewhere it means something. That is
	the standing "a no-op never locks the power" rule, and it is what keeps a Windman
	standing under a roof this game does not have from losing eight seconds to it.
	"""
	var interior := get_tree().get_first_node_in_group("tower_interior")
	if interior == null or not interior.has_method("set_xray"):
		return false
	interior.call("set_xray", true)
	windman_sight_timer = WINDMAN_SIGHT_DURATION
	# The same self-building, self-freeing sphere every other ability sells itself
	# with — small and pale here, because the effect the player should be looking at
	# is the room around him going see-through.
	_spawn_ability_effect(global_position, Color(0.7, 0.92, 1.0, 0.3), 2.5, 0.5)
	return true


func _end_air_sight() -> void:
	"""
	Put the walls back. Idempotent and safe to call for any character at any time —
	which is what lets `_reset_ability_states()` call it unconditionally beside
	`_revert_teibi_to_normal()`, and what makes "cleared on switch, on respawn and on
	the way out of the door" one line each instead of a state machine.

	The interior is looked up fresh rather than remembered: the tower streams out
	with the terrain, and a remembered reference would be the one thing in this
	script holding a freed node.
	"""
	windman_sight_timer = 0.0
	var interior := get_tree().get_first_node_in_group("tower_interior")
	if interior != null and interior.has_method("set_xray"):
		interior.call("set_xray", false)


func _ability_primm() -> bool:
	"""
	Phase Step: instantly blink straight forward, passing THROUGH any block. Primm
	must never end up stuck inside geometry, so instead of a blind fixed hop we
	scan forward from the desired distance and land at the first spot where his
	body actually fits — which is always on the far side of whatever he phased
	through (a single block, a wall, or a whole pyramid). If there's no clear spot
	within reach (facing into an enormous solid), the blink simply doesn't fire and
	costs no cooldown.
	"""
	var forward := -transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		return false
	forward = forward.normalized()

	# March outward for the first position where Primm's body is NOT inside a block.
	# Long Step lengthens the DESIRED distance only; the scan still gives up at
	# PRIMM_BLINK_MAX_DISTANCE, which is what bounds the skill without a cap of its
	# own (a blink that lands past 40 m simply never happens).
	var target := global_position
	var found := false
	var d := phase_reach()
	while d <= PRIMM_BLINK_MAX_DISTANCE:
		var candidate := global_position + forward * d
		if not _is_body_blocked_at(candidate):
			target = candidate
			found = true
			break
		d += PRIMM_BLINK_STEP

	if not found:
		return false

	# Phase Echo: a wall-pass hands back whole seconds of cooldown, applied by
	# `try_activate_ability()` when it charges it.
	#
	# THE WALL IS USUALLY NOT AT THE LANDING SPOT, which is why this needs its own
	# scan rather than a flag set by the loop above. That loop starts at the
	# DESIRED distance and only ever walks OUTWARD, so the ordinary case — a single
	# 2 m block three metres ahead, with the 6 m landing spot in open ground — sees
	# a clear first candidate and never notices the wall it just went through. The
	# whole travelled segment is what has to be tested.
	#
	# Gated on the skill being ranked, so an unranked Primm pays for none of these
	# extra shape queries; and it is a key press either way, not a per-frame path.
	var refund := _skill_bonus("primm_refund")
	if refund > 0.0 and _blink_passed_through(target):
		_pending_cooldown_refund = refund

	# A quick flash where he leaves and where he arrives, to sell the teleport —
	# plus three small staggered flashes along the path between them, so the eye
	# can track WHERE the blink went instead of seeing two disconnected pops.
	_spawn_ability_effect(global_position, Color(0.45, 0.5, 1.0, 0.5), 2.0, 0.35)
	for i in range(3):
		_spawn_ability_effect(global_position.lerp(target, (i + 1) / 4.0),
			Color(0.45, 0.5, 1.0, 0.4), 1.0, 0.25, i * 0.05)
	global_position = target
	velocity = Vector3.ZERO  # land cleanly on the far side, no carried momentum
	_spawn_ability_effect(global_position, Color(0.45, 0.5, 1.0, 0.5), 2.0, 0.35)
	return true


func _blink_passed_through(target: Vector3) -> bool:
	"""
	True when solid geometry stands anywhere BETWEEN the player and `target` — i.e.
	when the blink about to happen is a genuine wall-pass rather than a hop across
	open ground. Sampled at `PRIMM_BLINK_STEP` with the same capsule-centre probe
	the landing scan uses, so the flat ground never counts and the two agree about
	what "solid" means.

	Called only for a Primm who has bought Phase Echo (see `_ability_primm`), on a
	key press, so a dozen shape queries is the right shape of cost. `ponytail:` a
	single swept capsule would be one query instead — the ceiling here is a wall
	thinner than the 0.5 m step slipping between two samples, which reads as "no
	refund that time", never as a wrong teleport.
	"""
	var travel := target - global_position
	var distance := travel.length()
	if distance <= PRIMM_BLINK_STEP:
		return false
	var direction := travel / distance
	var d := PRIMM_BLINK_STEP
	while d < distance:
		if _is_body_blocked_at(global_position + direction * d):
			return true
		d += PRIMM_BLINK_STEP
	return false


func _is_body_blocked_at(pos: Vector3) -> bool:
	"""
	True if solid geometry occupies Primm's body space at world position `pos`.
	We probe with a small sphere at capsule-CENTRE height (not at the feet) so the
	flat ground — which the capsule always rests on — never counts as "blocked";
	only blocks and structures that rise above the ground do.
	"""
	var probe := SphereShape3D.new()
	probe.radius = 0.5
	# Lift the probe to the capsule's centre height so it clears the ground plane.
	return _shape_blocked(probe, pos + Vector3(0.0, collision_base_y, 0.0))


func _teibi_grow_blocked() -> bool:
	"""
	True when the GIANT capsule would not fit where the body is standing right now.

	THE FIX FOR THE TOWER BREACH (bead godot-test1-3uh), and it is a fix anywhere:
	growing inside geometry buries the grown capsule in it and the physics server's
	depenetration then squirts the body out along the shallowest axis — which, in a
	4.6 m storey a 4.4 m giant does not fit under, is UP, through the ceiling, onto
	the next floor. That turned Resize into a free lift past every gate the tower's
	softlock audit believes in. Refusing the growth is the root cause; no amount of
	geometry tuning covers "the body got bigger than the room".

	The probe is the ACTUAL grown capsule, not Primm's point-sized sniff, because
	the ceiling is the half of the exploit a mid-height sphere cannot see. Only its
	BOTTOM is pulled in, by `TEIBI_FIT_GROUND_CLEAR`, so the floor the player is
	standing on — and only the floor — is not itself an overlap; that is the same
	"the ground is not an obstacle" allowance `_is_body_blocked_at` buys with its
	centre-height lift, spent here on a shape that has to span the whole body. The
	TOP is the giant's real crown and is not trimmed (codex review): shortening it
	there would licence exactly `TEIBI_FIT_GROUND_CLEAR` of head inside a ceiling,
	and a head inside a ceiling is the whole bug.

	Cheap enough to sit in `get_ability_block_reason()`, which the HUD polls every
	frame: it runs only for a Teibi whose NEXT press is the growth (size state 1),
	i.e. one query a frame for one hero inside a 10 s window.
	`ponytail:` one shape per call rather than a cached probe — the allocation is a
	RefCounted in a bounded window; cache it if the F3 overlay ever notices.
	"""
	return _teibi_fit_blocked(TEIBI_SCALE_BIG)


func _teibi_fit_blocked(s: float) -> bool:
	"""
	True when Teibi's capsule at scale `s` would not fit where the body is standing.

	@param s: the body scale to test — `TEIBI_SCALE_BIG` for the growth above, 1.0
	    for the automatic revert, which is the other direction of the same bug.

	THE PROBE IS THE ONE ABOVE, PARAMETERISED (bd godot-test1-3iy.23, codex review),
	and it had to become one function rather than two: "would this body fit here"
	has exactly one right answer, and a second copy of the bottom-clearance
	allowance is a second chance to spend it at the head.
	"""
	if not collision_shape or not (collision_shape.shape is CapsuleShape3D):
		return false
	var capsule: CapsuleShape3D = (collision_shape.shape as CapsuleShape3D)
	# Where the capsule's underside sits relative to the body's origin — the same
	# `bottom` `_apply_teibi_scale` pins the grown capsule to, so the probe stands
	# exactly where the giant would.
	var bottom := collision_base_y - collision_half_height
	var top := bottom + capsule.height * s
	var probe := CapsuleShape3D.new()
	probe.radius = capsule.radius * s
	probe.height = maxf(2.0 * probe.radius, top - bottom - TEIBI_FIT_GROUND_CLEAR)
	return _shape_blocked(probe, global_position
			+ Vector3(0.0, top - probe.height * 0.5, 0.0))


func _shape_blocked(probe: Shape3D, centre: Vector3) -> bool:
	"""
	THE one "is there solid geometry here" query — the space state, the self
	exclusion and the mask in a single place, so Primm's landing scan and Teibi's
	fit test can never drift apart about what counts as solid or about whose
	collider is our own. Callers bring the shape; the question is shared.
	"""
	var space := get_world_3d().direct_space_state
	if not space:
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.transform = Transform3D(Basis(), centre)
	query.exclude = [get_rid()]  # never sense our own collider
	query.collision_mask = collision_mask
	return not space.intersect_shape(query, 1).is_empty()


func _ability_teibi() -> bool:
	"""
	Resize: cycle normal → small → giant → normal. Giant form crushes crocodiles
	(see crushes_crocodiles) but is too heavy to jump (see the jump step). Any
	altered form auto-reverts to normal after TEIBI_FORM_DURATION, so Teibi can
	never get stuck giant or tiny.
	"""
	var prev_state := teibi_size_state
	teibi_size_state = (teibi_size_state + 1) % 3
	var s := 1.0
	match teibi_size_state:
		1:
			s = TEIBI_SCALE_SMALL
		2:
			s = TEIBI_SCALE_BIG
		_:
			s = 1.0
	_apply_teibi_scale(s)
	is_giant = (teibi_size_state == 2)

	# Manage the auto-revert budget: start it the moment he first leaves normal,
	# clear it when he's back to normal, and KEEP it running across a small↔giant
	# switch (it's a total time-in-altered-form budget, not per-form).
	if teibi_size_state == 0:
		teibi_form_timer = 0.0
	elif prev_state == 0:
		teibi_form_timer = TEIBI_FORM_DURATION * _skill_mult("teibi_form")

	# CRUSH QUAKE (the `quake` skill node): landing in giant form shakes the
	# ground and scatters the crocodiles standing on it. `skill_bonus` IS the
	# radius in metres, so an unranked Teibi reads 0 and none of this runs —
	# no branch on the rank, no second constant to keep in step.
	#
	# BOSS IMMUNITY IS NOT RE-IMPLEMENTED HERE and must not be: `flee_from()`
	# early-returns for `is_boss`, which is where Stink Wave's immunity already
	# lives, so a boss shrugs the quake off through the one rule that owns it.
	# (A boss also bites giant Teibi rather than being crushed — `is_boss` is
	# checked above the crush block in `_on_player_collision` — so the tooltip's
	# "bosses shrug it off" is true of both halves of the giant form.)
	var quake_radius := _skill_bonus("teibi_quake")
	if is_giant and quake_radius > 0.0:
		_spawn_ability_effect(global_position, Color(0.95, 0.7, 0.35, 0.5), quake_radius, 0.5)
		_scare_crocodiles(global_position, TEIBI_QUAKE_FLEE_DURATION, quake_radius)
	return true


func _ability_phoboman() -> bool:
	"""Stink Wave: send out smelly waves; every crocodile flees for a while."""
	# A few staggered green waves so it reads as rolling stench, not one pop.
	#
	# TWO RADII, ON PURPOSE. `PHOBOMAN_STINK_RADIUS` (9) is the TELEGRAPH — what
	# the player sees — and `PHOBOMAN_FLEE_RADIUS` (22) is the EFFECT. They are
	# deliberately different because a 22 m sphere drawn at the player's feet
	# fills the screen and reads as a bug rather than as a smell. Billowing Cloud
	# (`phoboman_radius`) scales BOTH by the same multiplier, so the picture and
	# the reach stay in proportion however the node is ranked — and, since bead
	# godot-test1-20z.4 gave the sweep a real bound, that node now buys reach in
	# the effect and not only in the picture. See PHOBOMAN_FLEE_RADIUS for the
	# derivation of 22 and for what the bound costs.
	var reach_mult: float = _skill_mult("phoboman_radius")
	var stink_radius: float = PHOBOMAN_STINK_RADIUS * reach_mult
	_spawn_ability_effect(global_position, Color(0.55, 0.85, 0.2, 0.55), stink_radius, 0.9, 0.0)
	_spawn_ability_effect(global_position, Color(0.5, 0.8, 0.25, 0.45), stink_radius, 0.9, 0.18)
	_spawn_ability_effect(global_position, Color(0.45, 0.75, 0.3, 0.4), stink_radius, 0.9, 0.36)

	var flee_duration: float = PHOBOMAN_FLEE_DURATION * _skill_mult("phoboman_flee")
	_scare_crocodiles(global_position, flee_duration, PHOBOMAN_FLEE_RADIUS * reach_mult)
	return true


func _scare_crocodiles(origin: Vector3, duration: float, radius: float) -> void:
	"""
	THE one "make the crocodiles round here run away" path, shared by Phoboman's
	Stink Wave and Teibi's Crush Quake — a helper rather than two loops, so the
	radius test, the group discovery and the multiplayer relay each have exactly
	one home and a third fear effect is one call.

	Discovery stays group-based with no hard references, per the project's
	convention, and boss/slept immunity is NOT re-implemented here: `flee_from()`
	owns both early returns, which is what keeps the rule in one file.

	MULTIPLAYER: the local loop runs on EVERY caller, master or not — it is
	correct for the crocodiles this peer still simulates and harmless on the
	remote-driven ones (the next 10 Hz sample overwrites the flag) — and the
	`request_croc_flee` relay asks the master to do the same to the crocodiles it
	is the authority for. That is the same master path bead godot-test1-s86.5
	already built for the Stink Wave, so a new fear effect needs no protocol work
	at all; `radius` is carried INTO the request, so a bounded sweep stays bounded
	room-wide (an unbounded one disarmed every awake crocodile on every screen).
	Nothing comes back and nothing needs to: `is_fleeing` is a bit in the sync
	packet, so the master's copy of the flight reaches every screen for free.
	"""
	var radius_sq := radius * radius
	for croc in get_tree().get_nodes_in_group("crocodile"):
		if not (croc is Node3D) or not croc.has_method("flee_from"):
			continue
		if (croc as Node3D).global_position.distance_squared_to(origin) > radius_sq:
			continue
		croc.flee_from(origin, duration)

	var mp := _mp()
	if mp and mp.has_method("request_croc_flee"):
		mp.request_croc_flee(origin, duration, radius)


func _current_teibi_scale() -> float:
	"""The character's current base scale from Teibi's size cycle (1.0 for every
	other character — their state is always 0). The landing squash multiplies
	around this so a squashed small/giant Teibi stays small/giant."""
	match teibi_size_state:
		1:
			return TEIBI_SCALE_SMALL
		2:
			return TEIBI_SCALE_BIG
		_:
			return 1.0


func _apply_teibi_scale(s: float) -> void:
	"""
	Resize the visible model AND the collision capsule to scale `s`, keeping the
	capsule's bottom pinned to the ground so the player never sinks into the floor
	or gets launched when growing or shrinking.

	Why the position tweak: scaling the CollisionShape3D node scales the capsule
	about the node's origin, which would move the capsule's bottom up/down. We move
	the node so the bottom stays exactly where it was at normal size.
	"""
	if character_container:
		# The VISUAL scale tweens with a springy overshoot so the resize pops
		# instead of snapping. Kill any in-flight resize tween first so rapid
		# F-presses don't leave two tweens fighting over the same property.
		if _teibi_tween:
			_teibi_tween.kill()
		_teibi_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_teibi_tween.tween_property(character_container, "scale", Vector3(s, s, s), 0.25)
	if collision_shape:
		# The COLLISION capsule snaps to the new size instantly — physics must
		# never lag the visual, or a "still shrinking" giant could clip blocks
		# and the first-person eye height would be mid-tween wrong.
		collision_shape.scale = Vector3(s, s, s)
		var bottom := collision_base_y - collision_half_height
		collision_shape.position.y = bottom + s * collision_half_height
	# First-person eyes are derived from this capsule scale, so a resize must
	# immediately re-seat the spring arm (which carries the camera) at the new
	# height — small Teibi looks from down low, giant Teibi from up high.
	# _apply_view_mode() is idempotent, so this is safe from every caller
	# (F-cycle, form timeout, character switch, respawn).
	if view_mode == ViewMode.FIRST_PERSON:
		_apply_view_mode()


func _spawn_ability_effect(pos: Vector3, color: Color, max_radius: float, lifetime: float, delay: float = 0.0) -> void:
	"""
	Spawn a one-shot expanding/fading wave at a world position. Parented to our
	parent (the main scene) so it lives independently of the player and frees
	itself when finished — no manual cleanup, no leak.
	"""
	var parent := get_parent()
	if not parent:
		return
	var fx := MeshInstance3D.new()
	fx.set_script(ABILITY_EFFECT)
	parent.add_child(fx)
	fx.global_position = pos
	fx.setup(color, max_radius, lifetime, delay)


func _reset_ability_states() -> void:
	"""Clear transient ability state on respawn (air boost, air sight, giant/small form)."""
	windman_boost_timer = 0.0
	speed_burst_timer = 0.0
	_pending_cooldown_refund = 0.0
	_revert_teibi_to_normal()
	# Air Sight lives in the BUILDING's materials rather than in a field here, so it
	# is the one transient state that leaks something visible if it is not cleared:
	# switch character mid-ability and the HQ would stay see-through with nobody
	# holding it that way.
	_end_air_sight()
	# Sidestep is transient too: the caught/respawn/game-over branches all return
	# BEFORE update_sidestep(), so a player caught mid-step would otherwise come
	# back with is_stepping still true and slide sideways out of the spawn.
	if is_stepping:
		is_stepping = false
		step_direction = 0.0
		anim.reset_sidestep_pose()


func _revert_teibi_to_normal() -> void:
	"""Snap Teibi back to normal size — used by the form timeout, character switch,
	and respawn. Safe to call for any character (a normal-size body is the default)."""
	teibi_size_state = 0
	is_giant = false
	teibi_form_timer = 0.0
	_apply_teibi_scale(1.0)


# --- Ability HUD contract (read by ability_hud.gd) ---------------------------

func hero_name() -> String:
	"""
	Which character is being played RIGHT NOW.

	@return: One of the `CHARACTERS` names — "windman", "primm", "teibi", "phoboman".

	THE ANSWER TO "WHO IS STANDING HERE", and the tower's identity gates ask it
	every frame rather than latching it: E switches character wherever you are
	standing, so a gate that remembered who walked in would be answering a question
	nobody asked.
	"""
	return String(CHARACTERS[current_character_index]["name"])


func phase_reach() -> float:
	"""
	How far the current hero's Phase Step reaches, in metres — 0 for anyone but
	Primm, who is the only one who has one.

	@return: `PRIMM_BLINK_DISTANCE` after Long Step ranks, or 0.0.

	THE ONE EXPRESSION, read by two callers. `_ability_primm()` blinks with it and
	the tower's demand gate is calibrated against it, so a gate can never ask for a
	distance the ability does not have and retuning Long Step moves both together.
	Returning 0 rather than refusing is what lets the gate's calibration ladder show
	a Windman an honest, empty reading instead of an error.
	"""
	if hero_name() != "primm":
		return 0.0
	return PRIMM_BLINK_DISTANCE * _skill_mult("primm_blink")


func get_ability_name() -> String:
	"""
	Friendly name of the current character's ability (for the HUD).

	ASKED EVERY FRAME RATHER THAN LATCHED, for the same reason `hero_name()` is:
	Windman's F is Air Rush outdoors and Air Sight under the HQ's roof, so the label
	changes when he walks through the door and a dial that remembered the old name
	would be advertising a power that press will not fire.
	"""
	var char_name: String = CHARACTERS[current_character_index]["name"]
	if char_name == "windman" and _sheltered():
		return INDOOR_ABILITY_NAME
	return ABILITY_NAME.get(char_name, "Ability")


func _skilled_ability_cooldown() -> float:
	"""
	The current character's cooldown length AFTER its skill tree, in seconds. The
	single expression both the charge in `try_activate_ability()` and the HUD dial
	divide by — which is the whole reason it is a function.

	Divide the dial by the UNSKILLED constant and a hero with cooldown ranks
	arrives at a dial that starts at 0.6 full and empties early: not an error
	anywhere, just a HUD that quietly stops meaning what it says.
	"""
	var char_name: String = CHARACTERS[current_character_index]["name"]
	return float(ABILITY_COOLDOWN.get(char_name, 10.0)) * _skill_mult("cooldown")


func get_ability_cooldown_ratio() -> float:
	"""Cooldown progress for the HUD dial: 1.0 just-used → 0.0 fully ready."""
	var duration: float = _skilled_ability_cooldown()
	if duration <= 0.0:
		return 0.0
	# `_cooldown_remaining()`, not the raw timer: `ability_hud` reads COOLING off
	# this ratio alone, so a waived press behind a full amber arc would be the
	# "dial says blocked while the key works" bug in its most visible form.
	return clampf(_cooldown_remaining() / duration, 0.0, 1.0)


func get_ability_remaining() -> float:
	"""Seconds of cooldown left on the current character's ability — the cooldown
	that is actually in the way, so a waived press shows no countdown."""
	return maxf(0.0, _cooldown_remaining())


func get_ability_block_reason() -> String:
	"""
	Why an F press would be refused RIGHT NOW even though the cooldown is spent,
	as a short label for the dial — or "" when nothing but the cooldown stands in
	the way. Keys into `assets/translations/ui.csv`; the HUD `tr()`s it.

	THIS IS THE ONE HOME OF THE GATES. `try_activate_ability()` asks it before
	firing and `is_ability_ready()` asks it before saying "ready", so the dial and
	the key press can never disagree about whether the power is available — which
	is exactly the bug that shipped when the gates lived inline up there
	(godot-test1-tw6: an airborne Windman saw a green READY dial and every press
	bounced). A new gate goes here and the HUD learns about it for free.

	It is a PURE READ of live state and stores nothing, so no gate can latch a
	hero off permanently, and refusing costs no cooldown — the two properties both
	gates have always had.

	  "CELL" — the prison role has no ability at all: every one of the four is a
	           phase, a flight, a combat verb or a wave, and the role is defined as
	           having none of them.
	  "INDOOR" — Teibi's next press would make him GIANT and he is inside the HQ.
	           Owner ruling (bead godot-test1-xdf): the building is the stealth
	           layer and a giant does not fit its pace. Not an exploit patch — the
	           exploit is `_teibi_grow_blocked()`'s job and it still does it — but a
	           design rule, which is why it refuses in the middle of an empty room
	           too. SMALL stays allowed in here: it is the stealth-flavoured form.
	  "TIGHT"— Teibi's next press would make him GIANT and the grown capsule does
	           not fit where he is standing. Growing inside geometry is not a
	           clipping artefact, it is a lift: the depenetration pops him out
	           upwards, through a storey's ceiling and past its gate.
	  "SEEING" — Windman's Air Sight is already running. The look outlives a skilled
	           hero's cooldown, so without this the press would refresh it forever
	           and the walls would never come back.
	  "RAIN" — Windman can't take off inside a storm cloud's rain zone.
	  "LAND" — AIR RUSH IS A TAKE-OFF, NOT A MID-AIR JET: Windman must have his
	           feet on the ground (or be inside the coyote window) to launch.
	           Without this the ability chains into infinite flight, because the
	           cooldown ticks from ACTIVATION and a fully-skilled hero's cooldown
	           is SHORTER than his own flight:

	               cooldown 8.0 s × 0.60 (cd1×3 + cd2) = 4.80 s
	               duration 4.0 s × 1.30 (gale ×2)     = 5.20 s

	           so the power came back 0.4 s before the previous rush expired, and
	           with Updraft + Soar he never fell far enough to land in between.
	           Gating on the ground rather than retuning either number is
	           deliberate: retuning the base cooldown would punish an UNSKILLED
	           Windman, who was never the problem, and charging the cooldown at
	           the END of the boost would make every duration upgrade a net nerf
	           and break the dial's cooldown-ratio division. The state invariant
	           — one rush per landing — is what was actually missing, and it
	           bounds his altitude to the designed single-arc ~26 m. Coyote time
	           is included on purpose: stepping off a ledge gets the same brief
	           grace here that it gets for a jump.
	"""
	# "CELL" — THE PRISON ROLE HAS NO ABILITY (bead godot-test1-3iy.10). The role is
	# "no phasing, no combat loop, no solo escape", and every one of the four powers
	# is one of those: Phase Step steps THROUGH geometry, Air Rush leaves the block
	# over its walls, giant Teibi is a combat verb and the Stink Wave is the field's
	# own version of the vent purge. Placed here rather than at the F press so the
	# HUD dial says so too — this function's whole reason for existing.
	#
	# Character-independent, which is why it sits ABOVE the windman test.
	if prisoner_active:
		return "CELL"
	var char_name: String = CHARACTERS[current_character_index]["name"]
	# "TIGHT" — THE GIANT NEEDS SOMEWHERE TO GROW INTO (bead godot-test1-3uh).
	# Only the press that would make him giant is asked: small is strictly inside
	# the normal capsule and normal is strictly inside the giant one, so every
	# other step of the cycle shrinks the body and always fits. See
	# `_teibi_grow_blocked()` for why growing inside stone is a traversal exploit
	# and not just a clipping artefact.
	#
	# "INDOOR" IS ASKED FIRST, ABOVE "TIGHT" (bead godot-test1-xdf). Both refuse the
	# same press and the order only decides which one the dial names, so it is decided
	# on which answer is TRUE: indoors "there is no room here" is not why — there is
	# no room here or anywhere in this building, and a hero told TIGHT would go
	# looking for a wider corridor that does not exist. `_teibi_grow_blocked()` stays
	# the outdoor refusal and is not weakened; it is simply not the one talking in
	# here. (`capture_selfcheck` check 9 keeps measuring it directly for that reason.)
	if char_name == "teibi" and teibi_size_state == 1:
		if _sheltered():
			return "INDOOR"
		if _teibi_grow_blocked():
			return "TIGHT"
	if char_name != "windman":
		return ""
	# INDOORS, F IS AIR SIGHT, AND NEITHER WINDMAN GATE APPLIES TO IT. RAIN could not
	# fire in here anyway (the weather asks the same `sheltered()` before it rains on
	# anybody), and LAND exists to stop Air Rush chaining into infinite flight — a
	# rule about a take-off, asked of an ability that is not one. Answering the whole
	# windman branch in one place also means one `_sheltered()` call for the frame.
	if _sheltered():
		# "SEEING" — ONE LOOK AT A TIME. See `WINDMAN_SIGHT_DURATION` for why this is
		# a gate and not a shorter duration: a fully-ranked cooldown comes back
		# BEFORE the look ends, and without this the walls never go solid again.
		return "SEEING" if windman_sight_timer > 0.0 else ""
	if _weather_is_raining_here():
		return "RAIN"
	if not (is_on_floor() or coyote_timer > 0.0):
		return "LAND"
	return ""


func is_ability_ready() -> bool:
	"""
	True when the current character can fire its ability right now — ACTUAL
	availability, cooldown AND gates, not just the cooldown.

	The dial reads this together with `get_ability_cooldown_ratio()`, and the two
	measure different things on purpose: the ratio is the COOLDOWN's own progress
	(what its name says, and all it can say), this is whether the press will land.
	So the HUD gets three states out of two honest inputs — cooling (ratio > 0),
	gated-but-charged (ratio == 0, not ready) and ready — rather than one input
	quietly overloaded. The gated state renders as its own colour and names the
	gate, because a player with a full charge and a refused press has nothing to
	wait for and needs to know the fix is to land, not to be patient.
	"""
	return _cooldown_remaining() <= 0.0 \
			and get_ability_block_reason() == ""


func crushes_crocodiles() -> bool:
	"""
	Crocodile contract: when true, a crocodile that touches the player is crushed
	instead of biting. Only giant-form Teibi qualifies. (See piglet_crocodile_ai
	._on_player_collision.)
	"""
	return is_giant


# ============================================================================
# THE ABILITY STATE A WATCHER CAN SEE (bead godot-test1-69p)
# ============================================================================
#
# Teibi's Resize and Windman's Air Rush change what the player LOOKS like, and
# until now only the local screen knew: the presence packet carries position,
# heading, hero, speed and the on-floor bit, so a teammate watching a giant
# Teibi saw a normal-sized one and a flying Windman never beat his wings.
#
# These three bits ride that packet as its `ab` field (mp_manager._send_presence
# / decode_presence) and RemoteAvatar applies them. They live HERE, beside the
# state and the scale constants they describe, so "giant means TEIBI_SCALE_BIG"
# has exactly one copy in the project.
#
# READ-ONLY, both of them: this reports ability state, it never changes any, so
# nothing about how an ability is ACTIVATED is on this path.

const ABILITY_BIT_FLYING: int = 1 << 0
const ABILITY_BIT_SMALL: int = 1 << 1
const ABILITY_BIT_GIANT: int = 1 << 2


func ability_visual_state() -> int:
	"""
	The transient ability state a watcher can see, as ABILITY_BIT_* flags. 0 —
	the normal case — means "nothing to draw differently", which is also what an
	older peer's silence means on the wire.
	"""
	var bits: int = 0
	if windman_boost_timer > 0.0:
		bits |= ABILITY_BIT_FLYING
	if teibi_size_state == 1:
		bits |= ABILITY_BIT_SMALL
	elif teibi_size_state == 2:
		bits |= ABILITY_BIT_GIANT
	return bits


static func ability_visual_scale(bits: int) -> float:
	"""
	The model scale `bits` asks for — the SAME constants the local player resizes
	by, which is the whole reason this is here rather than copied into
	RemoteAvatar.

	Static and pure, and total over all 2^32 inputs: `bits` arrives off the wire,
	so contradictory flags (a hostile packet setting small AND giant) resolve
	deterministically to giant rather than to something undefined, and bits this
	build has never heard of are simply ignored.
	"""
	if bits & ABILITY_BIT_GIANT:
		return TEIBI_SCALE_BIG
	if bits & ABILITY_BIT_SMALL:
		return TEIBI_SCALE_SMALL
	return 1.0
