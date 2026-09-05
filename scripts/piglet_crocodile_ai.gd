extends CharacterBody3D
## Piglet Crocodile NPC AI
##
## This script controls the behavior of hostile piglet crocodiles.
## They wander randomly but will chase the player when detected.
##
## Behavior:
## - Random wandering with periodic direction changes
## - Detection radius: can "smell" the player within range
## - Chase mode: pursues player at increased speed when detected
## - Returns to wandering when player escapes detection range
## - Fatal collision with player (resets player position)

# ============================================================================
# SPECIES TABLE
# ============================================================================
## The table itself lives in `scripts/species_table.gd` (bead godot-test1-ftn.10)
## — the rows, their numbers and the whole design argument beside each one. It is
## aliased back in here under its old name, so every reader (this body's own
## `_ready()` resolution, `CROC_SCRIPT.SPECIES` in the selfchecks,
## `BIOME_SPECIES` / `BIOME_BOSS` in endless_terrain.gd) still spells it
## `SPECIES`. What stays here is what a row is not: the behaviour arms it
## dispatches into, the guards that read its keys, and the game-wide constants
## below that no species may opt out of.
const SPECIES: Dictionary = SpeciesTable.SPECIES

# ============================================================================
# CONSTANTS (game-wide — NOT per species)
# ============================================================================

## Movement speed in meters per second (wandering)
var move_speed_instance: float = 0.0

## Chase speed when pursuing player (faster)
var chase_speed_instance: float = 0.0

## Difficulty gradient: crocodiles chase faster the farther from origin they spawn.
## The multiplier is 1.0 + clamp(|x| / DENOM, 0, MAX) — +60% at 3 km and capped there,
## so late-run walking is lethal but running/abilities still escape.
const DISTANCE_SPEED_SCALE_DENOM: float = 3000.0
const DISTANCE_SPEED_SCALE_MAX: float = 0.6

## Hard ceiling on the final chase speed, applied to EVERY species. The
## per-instance ±50% roll and the distance factor MULTIPLY (worst case
## 5.5 × 1.5 × 1.6 = 13.2), which would outrun even a RUNNING player (RUN_SPEED
## 10.0 — 9.0 for the slowest character) and silently break the "running still
## escapes" promise above. Capping just under the slowest run speed keeps that
## escape hatch true; the gradient still bites walkers hard. This is the top of
## the speed lattice and lives OUTSIDE the species table on purpose — no entry in
## SPECIES may raise it.
const MAX_CHASE_SPEED: float = 8.5

# ----- Pack steering (behavior == "pack") -----
## Aliased back from `croc_steering.gd`, which moved with `pack_steer_point()` —
## the only thing that reads it (bd godot-test1-ftn.16). The 25 lines on why it
## must stay strictly below 1.0, and what closing rate 0.75 buys, live there
## beside the arithmetic. Kept here so every reader is untouched, including
## `enemy_behavior_selfcheck`'s `get_script_constant_map()["PACK_FLANK_TAPER"]`.
const PACK_FLANK_TAPER: float = CrocSteering.PACK_FLANK_TAPER

# ----- Boss crocodiles -----
## Bosses are the rare, huge road-guardian crocodiles the terrain places
## deterministically along the coin road (see endless_terrain.gd). They reuse
## this exact AI wholesale — a boss differs only in a handful of flags set via
## setup_as_boss() below, never in behaviour code. A boss is a MODIFIER on a
## species, not a species of its own: it overrides the two numbers below and
## inherits everything else from its `spec`.
##
## Boss chase speed: above WALK_SPEED (5.0) so a walking player is run down,
## but the MAX_CHASE_SPEED cap (8.5) keeps it under the slowest RUN (9.0), so
## RUNNING always escapes — the core escape hatch survives.
const BOSS_CHASE_SPEED: float = 7.0

## Boss detection radius: wider "smell" than a regular crocodile so the boss
## reads as a real threat guarding the road. INVARIANT: must stay well below
## the LOD manager's SIM_RADIUS (45.0) — any crocodile that can detect the
## player must always be awake, so near-player behaviour never changes.
const BOSS_DETECTION_RADIUS: float = 25.0

# ----- Vision cones (the optional `view_cone_deg` row field) -----
## THE DEFAULT EVERY ROW CARRIES WITHOUT WRITING IT DOWN: a full circle, which is
## what every predator in this game has always had. `spec.get("view_cone_deg",
## VIEW_CONE_FULL)` is the only read, so a row that says nothing keeps the
## 360-degree distance test byte-for-byte — the cone costs the field spawners
## nothing, takes no RNG draw, and moves no body.
##
## A CONE IS PART OF THE SMELL TEST, NOT A BEHAVIOUR. CLAUDE.md's rule is that
## detection is settled ABOVE the dispatch and an arm may only bend
## `chase_target`; "how far it can smell" and "which way it is looking" are the
## same question asked twice, so both live in `_update_chase_state` and neither
## is an arm. That is also what makes a cone free for every future row: it is a
## number, and a number is what a SPECIES row is for.
const VIEW_CONE_FULL: float = 360.0

## THE STEALTH BEAT, and the reason a cone is playable rather than merely narrow.
## A coned predator that has you in its cone does not start chasing for this long:
## it stands, it questions (the `?` over its head and one ping), and only then
## commits. Without it a cone is a strictly harsher 360 detector — you are seen
## the frame you cross the edge and there is nothing to react to.
##
## GAME-WIDE AND NOT A ROW FIELD, the same call as MAX_CHASE_SPEED: "you get a
## beat to back out of a cone" is a promise the player reads once and expects
## everywhere, and a species that could shorten it would be un-learnable. 0.6 s is
## about two walked steps back out of the arc.
##
## Only a CONED body ever counts it down — a 360 row has no edge to cross and no
## beat to give, so every existing species acquires on the same frame it always
## has. See `_update_chase_state`.
const SPOT_TELEGRAPH_TIME: float = 0.6

## HOW FAR ABOVE OR BELOW ITSELF A CONED BODY MAY ACQUIRE A QUARRY, in metres.
##
## A cone is a horizontal bearing test, so on its own it says nothing about
## height — and the tower's guards stand on ten stacked storeys 4 to 5 m apart.
## The keep's own two posts are 8.08 m apart through a SOLID SLAB, which the old
## 6.5 m radius excluded by accident and 9.0 m does not: without this a courtyard
## guard smells the player on the mezzanine, charges its leash boundary and stands
## there pushing at a floor it can never leave.
##
## 3.0 m is over any body's standing height and under the shortest gap between two
## walking surfaces in this building (4.0 m), so "on my floor" and "inside the
## band" are the same statement, checked without a raycast, an occlusion test or a
## storey field the AI would have to be told about.
##
## CONED ROWS ONLY, like the beat: nothing without a `view_cone_deg` reaches this,
## so a field predator still smells a quarry stood on a block above it exactly as
## it always did.
const VIEW_CONE_HEIGHT_BAND: float = 3.0

## How long fear holds after seeing giant Teibi, in seconds (bead godot-test1-upu).
## Refreshed every frame while a giant quarry remains in fears_giant_radius, so fear
## releases ~1.0 s after the giant leaves or reverts with no persistent state to clear.
const GIANT_FEAR_HOLD: float = 1.0


## Boss territory radius: the LEASH, and the whole of this bead. A boss hunts
## you normally anywhere inside `home_position` + this, and never steps outside
## it — walking out of the circle is the only counterplay, because there is no
## way to kill a boss. Everything that asks the question goes through
## `in_territory()`; nothing compares a radius by hand.
##
## THE INEQUALITY CHAIN, and both links are load-bearing:
##
##     BOSS_DETECTION_RADIUS (25) <= BOSS_TERRITORY_RADIUS (32) < SIM_RADIUS (45)
##
## LEFT LINK — the territory is at least as wide as the smell. Below it a boss
## could acquire a quarry it is then forbidden to walk to: it would growl once
## and stand there. At or above it, "smelled" implies "reachable", so a boss
## inside its own zone hunts with the ordinary chase code and nothing else.
##
## RIGHT LINK — the whole territory fits well inside the LOD manager's SIM_RADIUS
## (crocodile_lod_manager.SIM_RADIUS, 45). That is the same invariant
## BOSS_DETECTION_RADIUS states, widened from the smell to the ZONE: an engaged
## boss is at most 25 m from its quarry so it is always fully awake, and even a
## disengaged one is never more than 32 m from a player standing at its home, so
## you cannot watch a boss from inside its own territory and see a frozen
## sleeper. Push this to 45+ and both of those stop being true, silently.
##
## NOT part of the speed lattice, deliberately: a leash makes escape strictly
## EASIER, which is the point, so BOSS_CHASE_SPEED / MAX_CHASE_SPEED are
## untouched by it.
const BOSS_TERRITORY_RADIUS: float = 32.0

## How far inside the boundary a boss starts refusing to steer outward. Exactly
## the job CONFINE_MARGIN does for a platform patrol, one shape over: with no
## band the body would only ever meet the fence through the hard clamp below,
## which zeroes velocity — so a boss would stutter against an invisible wall
## instead of turning away from it.
const BOSS_TERRITORY_MARGIN: float = 3.0

## Visual draw cull: past this distance the crocodile's MESHES stop being drawn
## (visibility_range_end on every GeometryInstance3D in the model subtree). This
## is a pure RENDERING cull — the crocodile entity itself stays alive and counted;
## the LOD manager sleeps its SIMULATION separately at 45/50 m. Entity counts are
## unchanged: nothing is removed, meshes just skip the draw when far away. 60 m is
## deliberately wider than the 50 m sleep radius so a visible crocodile is never a
## frozen-mid-stride sleeper close up, and the universal depth fog hides the pop.
const VISUAL_CULL_DISTANCE: float = 60.0
## Fade margin for the cull boundary (Godot hysteresis band, avoids flicker).
const VISUAL_CULL_MARGIN: float = 8.0

## Gravity acceleration (matches project default)
const GRAVITY: float = 9.8

## ---------------------------------------------------------------------------
## MULTIPLAYER SYNC (phase 5) — see set_remote_state() for the whole scheme
## ---------------------------------------------------------------------------

## How far a synced sample may land from the body before we SNAP to it instead of
## easing. A master migration, a chunk rebuild or a burst of dropped packets all
## move a crocodile further than one 10 Hz step ever could; without the snap the
## body would take a long serene glide to catch up. Same rule, same reason, as
## RemoteAvatar's TELEPORT_DISTANCE.
const CROC_TELEPORT_DISTANCE: float = 8.0

## Ceiling on the velocity a remote sample may ask for (m/s). The samples already
## passed the manager's decoder, so this is belt-and-braces: it bounds how far one
## bad-but-finite sample can fling the body. Comfortably above MAX_CHASE_SPEED
## (8.5), so honest catch-up after a dropped packet still works.
const CROC_REMOTE_MAX_SPEED: float = 40.0

## How fast a remote-driven crocodile eases toward the synced yaw (per second).
const CROC_REMOTE_TURN_RATE: float = 12.0

## How fast a remote-driven crocodile closes the gap to the latest sample (per
## second). Deliberately the SAMPLE rate (MpManager.CROC_SYNC_HZ), never the frame
## rate: dividing the gap by the frame delta asks for a velocity that lands
## exactly on the sample THIS frame, so the body arrives in one frame and then
## sits at velocity ~0 for the other five — a 10 Hz teleport-and-freeze rather
## than the easing this is documented to do. Worse, `_animate_body` derives its
## stride from `velocity`, so those five frames take the `move_factor < 0.05`
## branch and the crocodile visibly flips between sprinting and idle breathing ten
## times a second on every peer that is NOT the master. Closing over the sample
## period instead gives the same exponential smoothing RemoteAvatar uses, and a
## croc moving at its own top speed asks for its own top speed.
const CROC_REMOTE_INTERP_RATE: float = 10.0

## How near the local player a giant-Teibi crush has to be for it to kick the
## camera (metres). Only ever meaningful in a room, where squash_and_die() also
## runs for a teammate's kill an unknown distance away; a contact crush is a
## couple of metres, so the single-player feel is unchanged.
const CRUSH_SHAKE_RADIUS: float = 6.0

# ============================================================================
# STATE VARIABLES
# ============================================================================

## Which entry of SPECIES this predator is. CALL-ORDER CONTRACT, exactly like
## setup_as_boss() and setup_roll_seed(): a spawner assigns it on the fresh
## instance BEFORE add_child(), because _ready() is where it is resolved into
## `spec` and where the speed/size rolls that read `spec` happen. It is a plain
## public field rather than a setup_*() call because there is a single value to
## set and nothing to derive — _ready() does the validation and the fallback.
## Left alone — piglet_crocodile.tscn run standalone, or any spawner that does
## not know about the contract — it stays "crocodile" and the node behaves
## exactly as it always did.
var species: String = "crocodile"

## This instance's row of the SPECIES table, resolved ONCE in _ready() and then
## read directly by the per-frame paths (_wander, _avoid_obstacles,
## _animate_body, _tick_river_sink, _animate_bite). Initialised here as well so
## the dictionary is never empty for the window before _ready() runs.
var spec: Dictionary = SPECIES["crocodile"]

## Current movement direction (normalized Vector3)
var movement_direction: Vector3 = Vector3.ZERO

## Time accumulator for direction changes
var time_since_direction_change: float = 0.0

## Is the crocodile currently paused?
var is_paused: bool = false

## Pause time remaining
var pause_time_remaining: float = 0.0

## Is the crocodile currently chasing the player?
var is_chasing: bool = false

## THE AMBUSH ARM'S ONE OUTPUT (`_behave_ambush`): true while this predator is
## lying buried and waiting. Read by `_tick_river_sink`, which owns the model's
## rest height, and by nothing else — the burrow is VISUAL, so no other system
## has any business knowing about it.
##
## TWO WRITERS, and the second is why this is a stored flag rather than a
## derivation: the arm on a simulating machine, and `set_remote_state` from the
## master's flag byte on every other peer in a room (MpCodec.CROC_FLAG_BURROWED
## carries the note on why the byte has to say it out loud). Locally it is only
## ever raised on a row that has an `ambush_burrow_depth`; over the wire it is
## peer input like everything else, so the reader checks the key.
var is_burrowed: bool = false

## THE CHARGE ARM'S ONE PIECE OF MEMORY (`_behave_charge`): the bearing this bear
## committed to and the point it committed from, as { "dir": Vector3, "origin":
## Vector3 }. Empty means "not committed". It is a Dictionary rather than two
## floats so `charge_steer_point()` can be a STATIC function that both the arm
## and enemy_spawn_selfcheck's dodge probe drive — the check measures the shipped
## steering instead of a restatement of it, exactly as it does for the wolf's
## `pack_steer_point()`. Behaviour-local: nothing outside the charge reads it.
var _charge_lock: Dictionary = {}

## THE BURST ARM'S ONE PIECE OF MEMORY (`_behave_burst`): which leg of the
## pounce/sprint cycle this animal is on, how much of that leg it has spent, and
## where it stood last frame, as { "bursting": bool, "travelled": float,
## "last": Vector3 }. Empty means "not committed". The leg is spent in PATH
## LENGTH rather than displacement from a fixed origin — see burst_cycle_factor,
## where that is the difference between a bounded pounce and a cougar that
## circles you at 11 m/s forever. It is a
## Dictionary rather than a bool and a Vector3 so `burst_cycle_factor()` can be a
## STATIC function that both the arm and enemy_spawn_selfcheck's escape probe
## drive — the check measures the shipped cycle instead of a restatement of it,
## exactly as it does for the wolf's `pack_steer_point()` and the bear's
## `charge_steer_point()`. Behaviour-local: nothing outside the burst reads it.
var _burst_lock: Dictionary = {}

## THE RANGED ARM'S ONE PIECE OF MEMORY (`_behave_ranged`): how many seconds are
## left before this archer may release its next shot, as { "cooldown": float }.
## Empty means "ready now", which is what makes a titan that has just acquired
## you shoot on the acquisition frame rather than after a silent pause.
##
## A Dictionary rather than a bare float for the same reason `_burst_lock` is
## one: it lets `ranged_shot_due()` be a STATIC pure function that both the arm
## and enemy_spawn_selfcheck's cadence probe drive, so the check measures the
## shipped firing rule instead of a restatement of it. Behaviour-local: nothing
## outside the ranged arm reads it.
var _ranged_lock: Dictionary = {}

## THE HUNT ARM'S ONE PIECE OF MEMORY (`_behave_hunt`): the whole retrieval state
## machine, as { "telegraph": float, "disengage": float, "closing": bool }.
## Empty means "has not acquired anything", which is what makes the first frame
## of a chase the frame the telegraph starts and the lock-on cue fires.
##
## THE TIMERS ARE SECONDS COUNTED DOWN BY THE ARM, NOT WALL-CLOCK DEADLINES, and
## that is the LOD contract in one sentence: a slept hunter runs no
## `_physics_process`, so neither timer drains while it is asleep and it wakes
## owing exactly the telegraph (or the disengage) it owed when it went under. No
## catch-up, no lurch, nothing to reconcile — the same answer `burst_cycle_factor`
## gets by measuring metres and `charge_steer_point` gets by measuring
## displacement, and the opposite of what a `Time.get_ticks_msec()` deadline
## would have done (expire mid-sleep and hand back a hunter that wakes already
## committed, or one whose telegraph was spent 50 m away where nobody could see
## it). A paused tree gets the same treatment for free.
##
## A Dictionary rather than three bare fields for the same reason `_burst_lock`
## is one: it keeps the arm's whole state clearable in a single `clear()` on the
## edge where the chase drops. Behaviour-local: nothing outside the hunt arm
## reads it, and `_on_player_collision` only WRITES the disengage into it.
var _hunt_lock: Dictionary = {}

## THE HUNT ARM'S SECOND LEG — scent tracking, and the two fields it needs.
##
## `is_tracking` means "I cannot smell the quarry directly, but I am standing on
## its track and walking up it". It is DELIBERATELY NOT `is_chasing`: the chase
## flag is the detection decision, which is settled above the behaviour dispatch
## and which the danger vignette, the encounter director, the MP sync flags and
## the acquisition ping all read. A tracker has detected NOTHING — it has found a
## footprint — so it must light none of those. What it does instead is steer and
## move, which is all a behaviour arm is ever allowed to do.
##
## PUBLIC (no underscore) on purpose, unlike `_hunt_lock`: two systems outside
## this file read it. `crocodile_lod_manager` walks a slept tracker along the
## trail (see `advance_tracking`), and `MpCrocSync.send_croc_sync` publishes one
## even though it is asleep — a stalking body has left the deterministic spawn
## state every peer would otherwise assume for a sleeper.
var is_tracking: bool = false

## The trail crumb this unit is currently walking at, world space. Only read
## while `is_tracking`; recomputed from scratch every check, so it is a cache and
## never memory — a waking tracker produces the same point from where it stands
## that it would have produced had it never slept, exactly like `hunt_steer_point`.
var track_target: Vector3 = Vector3.ZERO

## Has this body EVER been walked by `advance_tracking`? Latched true on the first
## slept step and never cleared — a unit that has stalked is not standing where it
## spawned any more, and nothing puts it back.
##
## `MpCrocSync.send_croc_sync` reads exactly this rather than `is_tracking`. The
## rule it needs is "the peers' deterministic spawn position is a lie about this
## body", which stays true after the trail goes cold: a sleeper that stopped
## tracking is still displaced, and dropping it from the sync then would snap it
## into place the moment it woke — the very artefact the exception exists to
## prevent.
var has_stalked: bool = false

## ---------------------------------------------------------------------------
## THE LURE — a point somebody asked this body to walk over and look at
## (bead godot-test1-3iy.22, the HQ's `P` plates)
## ---------------------------------------------------------------------------
##
## A FLAG STATE BESIDE `is_tracking`, AND DELIBERATELY NOT A BEHAVIOUR ARM. It
## steers and it holds a facing, which is all a state down here is ever allowed
## to do; it lights no detection flag, so the cone, the telegraph, the danger
## vignette, the encounter director and the MP chase bit all still mean exactly
## what they meant. The one row that uses it today is `tower_guard`, whose
## `behavior` stays "solo" BY RULING (bead godot-test1-3iy.19) — an arm here
## would have handed a sentry the hunt arm's nose and its director seams.
##
## SPEED FALLS OUT: the movement branch reads `chase_speed_instance` only while
## chasing, fleeing or tracking, so an investigating body walks at
## `_wander_speed()`. A lured guard travels at its patrol pace with no speed
## code anywhere, which is what makes the walk something you can watch and time.
##
## IT WALKS A ROUTE SOMEBODY ELSE DREW. The caller passes the corners to follow
## (`TowerInterior.plan_route()` reads them off the floor plan) because the
## obstacle feelers are a 1.8 m reflex with no memory: of the seventeen (post,
## plate) pairs in the HQ exactly ONE has a clear straight line, so a lure that
## steered by bearing was a lure that walked fifteen guards into a wall. This file
## knows nothing about that plan — it is handed points and walks them, which is
## also what keeps the seam usable by anything else that wants to send a body
## somewhere.
##
## THE LEASH IS GROWN, NEVER BYPASSED. The plates are tens of metres from the post
## that guards them and a derived patrol box is 3 cells long — so the architect's
## "the clamp is normally a no-op" is not true of this building, and a lure that
## respected the shipped box would move a guard a metre and a half. The box is
## grown to reach whichever waypoint is being walked at, keeping its centre, so it
## can only ever CONTAIN the authored one; `_steer_within_platform` and
## `_clamp_to_platform` keep running every frame throughout, which is the
## difference between a bigger leash and no leash.
##
## AND AN ACQUISITION TAKES THE GROWTH BACK, on the spot: the box becomes the
## authored EXTENTS around wherever the body is standing, so a guard that spots
## you mid-errand chases you over a beat-sized patch of floor instead of the whole
## storey the errand opened up. The centre moves rather than the size, so nothing
## is teleported.
##
## AND THE WALK HOME IS PART OF THE DIVERSION, for a reason that is mechanical
## rather than decorative: `_clamp_to_platform` is a HARD clamp, so restoring the
## authored box while the body stands on a pad 40 m away would teleport it back.
## The guard walks its own route home and the box is restored at the post, where
## restoring it moves nothing.
var is_investigating: bool = false

## Where the investigation is walking RIGHT NOW — the head of `_investigate_path`,
## in world space, kept as a plain field because it is what everything outside
## this state (the self-check, a future HUD tell) wants to ask.
var investigate_target: Vector3 = Vector3.ZERO

## The corners still to walk, world space, the last one being the destination: the
## plate on the way out, the authored patrol centre on the way home.
var _investigate_path: Array[Vector3] = []

## The way back, built at the same time as the way out and swapped in when the
## hold expires (or an acquisition cancels). Empty for an unconfined body, which
## has no post to return to and simply ends where it stands.
var _investigate_home: Array[Vector3] = []

## Seconds of facing hold still owed at the pad. > 0 IS THE OUTBOUND LEG — it is
## the one bit that says which way this body is walking, so there is no phase
## enum to keep in step with it.
var _investigate_hold: float = 0.0

## THE STALL CLOCK: seconds since this leg last got measurably closer to the
## waypoint it is walking at, and the nearest it has been. A LENGTH-BASED BUDGET
## WAS THE FIRST TRY AND IT WAS THE WRONG SHAPE — the routes in this building run
## from ten metres to a hundred and seventy, so a budget generous enough for the
## long ones left a wedged guard shuffling against a doorway jamb for two minutes.
## Progress is the thing actually being asked about, and a body that is making
## none is stuck no matter how far it still has to go.
##
## The sniff pause and the spot telegraph both stand the body still, and neither
## can spend this: a paused body never reaches this function at all, and the
## telegraph is 0.6 s against `INVESTIGATE_STALL_TIME`.
var _investigate_stall: float = 0.0
var _investigate_best: float = INF

## The authored leash, `{center: Vector3, half: Vector2}`, put back when the body
## is home again. Empty for an unconfined body, which simply ends the lure where
## it stands — nothing to give back and nowhere to give it back at.
var _investigate_leash: Dictionary = {}

## How close to the pad (or to the patrol centre) counts as arrived, in metres.
## Comfortably over the chassis' own footprint: a body that has to stand exactly
## on a point orbits it forever, turning a hold into a shuffle.
const INVESTIGATE_ARRIVE: float = 1.6

## How much room the grown leash leaves around the pad. It must exceed
## CONFINE_MARGIN (0.9) or `_steer_within_platform` would push the guard off the
## plate it was lured onto — the steer starts a margin short of the edge.
const INVESTIGATE_LEASH_MARGIN: float = 2.0

## How long a leg may make no progress before the errand gives up, and how much
## closer counts as progress. Six seconds is several times a sniff pause and a
## whole turn, and half a metre is a third of `INVESTIGATE_ARRIVE` — so an honest
## walk resets the clock long before it runs, and a body pressed against a jamb
## turns round in six seconds instead of standing there for the rest of the run.
const INVESTIGATE_STALL_TIME: float = 6.0
const INVESTIGATE_PROGRESS: float = 0.5

## CROWD CONFUSION — per-body re-roll guard (bead godot-test1-8gw.16).
## After a false-arrest errand finishes the body must not immediately re-roll
## on the same re-acquisition while the player stands still, or the hunter
## never threatens inside the city. One cooldown per body, in seconds, counted
## down each physics frame while awake (and sleep is refused while it ticks, so
## a just-confused hunter that would otherwise sleep keeps its guard). Set on a
## successful confusion (see _try_crowd_confusion) and cleared on the next
## chase-loss edge; a miss does NOT set it. Paused while the errand runs so the
## 6 s covers the period AFTER the citizen check, not the walk+hold itself.
const CROWD_CONFUSION_COOLDOWN: float = 6.0
var _crowd_confusion_cooldown: float = 0.0
## Dedicated latch so the persist guard is keyed on crowd confusion alone —
## is_investigating is also set by the HQ lure, and keying on it broke that
## contract (finding #1). Only a confused row ever sets this.
var _crowd_errand: bool = false

func _tick_crowd_cooldown(delta: float) -> void:
	## Cooldown tick with pause while the crowd errand runs (finding #3).
	## Extracted so the probe can drive the shipped tick rather than a copy of it.
	if _crowd_confusion_cooldown > 0.0 and not _crowd_errand:
		_crowd_confusion_cooldown = maxf(_crowd_confusion_cooldown - delta, 0.0)

## THE LEAP ARM'S ONE PIECE OF MEMORY (`_behave_leap`): how many seconds of
## GROUNDED recovery this boss still owes before it may hop again, as
## { "cooldown": float }. Empty means "ready now", so a dragon that has just
## smelled you bounds on the acquisition frame rather than after a silent pause —
## the same edge, and the same reason, as `_ranged_lock`.
##
## THE CLOCK ONLY TICKS ON THE GROUND, which is what makes "recovery window" mean
## something: `leap_due()` returns early while airborne, so the hop's own airtime
## is not spent paying for itself and the cooldown is entirely a landed animal
## catching its breath. It is also the whole LOD contract, the hunt arm's verbatim:
## a slept boss runs no `_physics_process`, drains nothing, and wakes owing exactly
## what it owed. (SIM_RADIUS (45) is far outside BOSS_DETECTION_RADIUS (25), so a
## boss that is chasing — and therefore possibly mid-arc — is always awake anyway.)
##
## A Dictionary rather than a bare float for the same reason `_ranged_lock` is
## one: it lets `leap_due()` be a STATIC pure function that both the arm and
## enemy_spawn_selfcheck's leap probe drive, so the check measures the shipped
## cadence instead of a restatement of it. Behaviour-local: nothing outside the
## leap arm reads it.
var _leap_lock: Dictionary = {}

## THE SPEED-MULTIPLIER SEAM: the multiplier applied to `chase_speed_instance`
## for this frame. Two arms write it — "burst" (the cougar's pounce and the
## hound's sprint) and "leap" (the winged bosses' hop, faster through the air and
## slower during the landed recovery) — and they can never collide, because a row
## carries exactly one `behavior` string and therefore runs exactly one arm. It is
## named for the burst because that arm had it first.
##
## 1.0 for every species on neither arm, and 1.0
## is a hard requirement rather than a tidy default — it is what makes the one
## line in `_physics_process` that reads this a no-op for the crocodile, the
## viper, the wolf and the bear, so their movement stays byte-for-byte what it was.
##
## THIS IS THE ONLY THING IN THE GAME THAT CAN PUT A BODY ABOVE MAX_CHASE_SPEED,
## and the SPECIES rows that set it carry the argument for why that is safe (the
## contract is the CYCLE average, not the instant). Two things bound it in code
## regardless: it is applied ONLY while `is_chasing` — a fleeing predator never
## runs either arm, so a stale burst can never leak into a Stink Wave flight — and
## `_avoid_obstacles` multiplies `avoid_speed_factor` on top of it, so a burst
## into a block eases off on its own.
var burst_factor: float = 1.0

## Flee state. When Phoboman unleashes his Stink Wave, every crocodile turns tail
## and runs from the player for a while. Fleeing OVERRIDES both chase and wander,
## and a fleeing crocodile is harmless — it won't bite (see _on_player_collision).
var is_fleeing: bool = false
## Seconds of fleeing left (counts down to 0).
var flee_time_remaining: float = 0.0
## The smell's origin — the "run from here" point whenever the wave did not come
## from the local player (see flee_from), and the fallback when it did but the
## player reference is momentarily missing.
var flee_source: Vector3 = Vector3.ZERO
## Whether this flight tracks the LOCAL player (true: the player's own wave) or
## the fixed `flee_source` (false: a wave relayed from another peer in the room).
var flee_tracks_player: bool = true

## Boss flags, set by the terrain via setup_as_boss() BEFORE this node enters
## the tree (so _ready sees them). A boss skips the per-instance random
## speed/size rolls — its size comes from the deterministic schedule instead.
var is_boss: bool = false
## Uniform body scale for a boss (from the terrain's size schedule; 1.0 = unused).
var boss_scale: float = 1.0

## THE CENTRE OF A BOSS'S TERRITORY — its spawn spot, captured in _ready()'s
## is_boss branch. `global_position` is already the true spawn spot there because
## the terrain parents the boss into its chunk BEFORE _ready runs; that is the
## same guarantee the distance_factor line just above it relies on.
##
## This plus `territory_radius()` is THE queryable seam for the zone, and it is
## meant to be one: the owner intends the area to grow gameplay of its own later
## ("later we will invent some game mechanics there"), so every check asks
## `in_territory()` rather than open-coding a radius comparison. Meaningless (and
## never read) on a non-boss — every caller is behind an `is_boss` gate.
var home_position: Vector3 = Vector3.ZERO

## Deterministic seed for this crocodile's per-instance speed/size rolls, handed
## over by the terrain via setup_roll_seed() BEFORE this node enters the tree —
## the same call-order contract as setup_as_boss(), for the same reason (_ready()
## is where the rolls happen). When it is set, `rng` is seeded from it instead of
## randomize()d, so every peer in a multiplayer session derives the same pack from
## the shared run_seed. When it is NOT set — piglet_crocodile.tscn run standalone,
## or any future spawner that doesn't know about the contract — _ready() falls
## back to rng.randomize() and the crocodile behaves exactly as it always did.
var roll_seed: int = 0
var has_roll_seed: bool = false

## This crocodile's effective "smell" range — the ONE place that resolves the
## regular-vs-boss detection radius. `_update_chase_state` reads it, and so does
## the danger telegraph in `crocodile_lod_manager` (which must normalise each
## chaser's distance by ITS OWN radius: a boss acquires the player at 25 m, so a
## telegraph hardcoded to the regular 15 m would stay dark and silent for the
## first 10 m of the game's biggest threat closing on you). Resolved in _ready()
## because `setup_as_boss()` is contracted to run before the node enters the tree,
## and so is `setup_species()` — the non-boss value is this instance's
## `spec.detection_radius`.
var detection_radius: float = SPECIES["crocodile"]["detection_radius"]

## THE COSINE OF HALF THIS BODY'S VIEW CONE, or -1.0 when it has none.
##
## A COSINE AND NOT AN ANGLE, resolved once in `_ready()` alongside
## `detection_radius`, because the per-frame test is a dot product: comparing
## `forward.dot(to_quarry) >= this` costs one multiply-add, where comparing
## angles costs an `acos` per frame per body. -1.0 is the full circle, so the
## SAME comparison is trivially true for every 360-degree row — there is no
## branch on the hot path and nothing to skip.
var view_cone_cos: float = -1.0

## Does this body have a cone at all? Only the telegraph and the "?" read it — the
## detection test itself needs no branch (see `view_cone_cos`), but a 360 species
## must not grow a 0.6 s reaction beat it never had.
var has_view_cone: bool = false

## How long this body has held the quarry in its cone WITHOUT chasing yet, in
## seconds. Counts up while the beat runs and is reset to 0 the moment the quarry
## leaves the cone, the radius, or the chase starts — so backing out of an arc
## really does spend the guard's read, and re-entering costs a fresh one.
var spot_clock: float = 0.0

## The `?` over a coned body's head, created lazily on its first spot and shown
## for exactly the beat. One Label3D per coned body and none at all for the other
## eight species — the whole population that can grow one is the handful of guards
## standing inside one building.
var _spot_label: Label3D = null

## Reference to the player node
var player_node: Node3D = null

## The multiplayer manager, cached once in _find_player() (it is a fixed child of
## Main, so it exists for the whole session and never has to be re-looked-up).
## Null in any scene without it, which is what keeps solo play untouched.
var mp_node: Node = null

## Where this crocodile is currently STEERING when chasing. It starts each frame
## as the quarry — the local player, or in a room the nearest MEMBER of it — and
## the behaviour dispatch at the end of _update_chase_state() may then bend it
## somewhere else (a wolf aims at its own slot on a ring around the quarry, so
## the pack arrives from every side at once). Refreshed by _update_chase_state()
## every frame it runs, read by _chase_player(). See _update_chase_state for why
## the local player alone is not enough to find the quarry with.
##
## The DETECTION decision above the dispatch is made against the quarry itself,
## never against this, so bending it can only change the route a predator takes —
## never whether it smelled you, and never how far it can smell.
var chase_target: Vector3 = Vector3.ZERO

## Random number generator for movement
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Smoothly-drifting heading used while wandering (radians)
var wander_heading: float = 0.0

## Phase accumulator for wander-speed variation
var speed_phase: float = 0.0

## Per-instance phase offset so the whole pack doesn't move in lockstep
var instance_phase: float = 0.0

# --- Body animation state ---

## The model node we animate (single static mesh, no rigged limbs)
var model: Node3D = null

## Cached rest scale / height of the model so animation composes on top
var model_base_scale: Vector3 = Vector3.ONE
## The height the animation composes its bob/lunge ON TOP OF — i.e. the model's
## CURRENT rest height, which the river sink eases up and down (see
## `spec.river_sink_depth`). _animate_body / _animate_bite only ever READ this; the sink
## is the sole writer after _ready(), which is what keeps the two from fighting.
## They own `model.position` outright, so the sink deliberately does not touch it.
var model_base_y: float = 0.0
## The model's DRY rest height, latched once in _ready() and never written again.
## The fixed end of the ease `model_base_y` travels between.
var model_rest_y: float = 0.0

## The terrain, resolved once in _ready() — cached rather than looked up per tick
## because _animate_body runs every physics frame on every AWAKE crocodile (the
## player affords a per-tick group lookup at 1 node; a pack does not). Held only
## if it answers `is_wading_at`, so the null check below is the whole guard and the
## standalone piglet_crocodile.tscn simply never sinks.
var terrain: Node = null

## Stride / idle phase accumulators
var stride_phase: float = 0.0
var animation_time: float = 0.0

## Current (eased) forward lean
var current_pitch: float = 0.0

## Bite/chomp animation state, played when the crocodile catches the player.
var is_biting: bool = false
var bite_timer: float = 0.0

## LOD (simulation level-of-detail) gate. When true, this crocodile runs its full
## per-frame AI/physics step exactly as before. When false, it is "asleep": the
## central CrocodileLODManager has decided it is too far from the player to
## possibly matter this frame, so _physics_process is disabled entirely (with a
## cheap-return backstop at its top — see set_lod_active, which is also what makes
## a slept croc harmless). Defaults to TRUE so a crocodile spawned before the manager's
## first scan behaves normally for that brief window (the manager will sleep it on
## its next tick if it's far away). See crocodile_lod_manager.gd for the contract.
var lod_active: bool = true

## ---------------------------------------------------------------------------
## MULTIPLAYER IDENTITY AND REMOTE DRIVE (phase 5)
## ---------------------------------------------------------------------------
## This crocodile's room-wide id, LATCHED IN _ready() from the node name and never
## recomputed — the same contract, for the same reason, as coin.gd's `_id`.
var _croc_id: int = 0

## True while the room MASTER is driving this body (see set_remote_state, the only
## place that turns it on, and clear_remote_drive, the only place that turns it
## off). Always false outside a room, which is what keeps solo play unchanged.
var remote_driven: bool = false
## The last transform the master sent, and whether any sample has arrived yet.
var _remote_pos: Vector3 = Vector3.ZERO
var _remote_yaw: float = 0.0
var _has_remote_sample: bool = false

## When this body last asked the room master to kill it (giant-Teibi crush), in
## `Time.get_ticks_msec()`, or -1 for never.
##
## The master's `dead` broadcast is a round trip, and the body stays alive, solid
## and overlapping the player until it lands — so `_handle_collisions` fires the
## crush again on EVERY physics frame in between, and each one would put another
## RELIABLE packet on the one channel that also carries claims and confirms.
## Latched here rather than in the manager because the request is per-crocodile.
##
## It EXPIRES rather than latching forever, because nothing acknowledges the
## request: `request_croc_kill()` reports only that the packet left. The master's
## own `VERB_BUDGET_PER_SEC` drops `kill` past 10/s per peer SILENTLY, and a
## giant Teibi crossing a dense far-out pack touches more than that in a second —
## so a permanent latch left those crocodiles unable to be crushed AND unable to
## bite (the early return is above the bite path), i.e. immortal harmless
## obstacles for the rest of the run. A stall vote deposing the master mid-round-
## trip, or a channel mid-renegotiation, lose a request the same way.
var _kill_requested_msec: int = -1
## How long to wait for the master's ruling before asking again. Long enough that
## the per-frame re-send this exists to suppress still costs one packet; short
## enough that a dropped request is retried while the player is still standing on
## the crocodile.
const KILL_RETRY_MSEC: int = 1000

## Confinement: elevated "patrol" crocodiles are pinned to a structure top (a
## pyramid apex or wall ridge) and can never wander off it, since they can't jump
## or climb back up. Set up by the terrain via set_confinement().
var is_confined: bool = false
var confine_center: Vector3 = Vector3.ZERO
## Half-extents of the platform box on world X (.x) and world Z (.y).
var confine_half: Vector2 = Vector2.ZERO
## Start steering back toward the centre once this close to the platform edge.
const CONFINE_MARGIN: float = 0.9

# ============================================================================
# LIFECYCLE METHODS
# ============================================================================

func _ready() -> void:
	"""Initialize the crocodile NPC."""
	# Resolve this instance's row of the SPECIES table FIRST — the rolls, the
	# detection radius and every per-frame path below read it. An unknown name
	# (a typo, or a save/scene from a build that had a species this one doesn't)
	# falls back to the crocodile row rather than crashing the spawner: a wrong
	# predator is a bug, a missing one is a dead chunk.
	if not SPECIES.has(species):
		push_warning("piglet_crocodile_ai: unknown species '%s', using 'crocodile'" % species)
		species = "crocodile"
	spec = SPECIES[species]

	# The cone, resolved once into a cosine here rather than per frame (see
	# `view_cone_cos`). Above the boss/ordinary split on purpose: a cone is a
	# property of the ROW, and boss-ness is a modifier on a row — a boss of a coned
	# species looks where its species looks. Takes no RNG draw, so adding the field
	# to a row cannot slide a single spawn.
	var cone: float = float(spec.get("view_cone_deg", VIEW_CONE_FULL))
	has_view_cone = cone < VIEW_CONE_FULL
	view_cone_cos = cos(deg_to_rad(clampf(cone, 0.0, VIEW_CONE_FULL) * 0.5)) if has_view_cone else -1.0

	# Seed the RNG. The terrain hands every crocodile it spawns a deterministic
	# seed (setup_roll_seed, called before add_child), so the size/speed rolls
	# below — and every other draw this instance ever takes — are a pure function
	# of chunk coords + croc index + run_seed. Only a crocodile spawned WITHOUT
	# that seed (the standalone scene) falls back to a random one.
	if has_roll_seed:
		rng.seed = roll_seed
	else:
		rng.randomize()

	# Difficulty gradient: scale CHASE speed up with distance from the world origin.
	# global_position is already valid here because the terrain parents the crocodile
	# into the chunk BEFORE _ready runs, so |x| is the true spawn distance. Only the
	# chase speed scales — wandering stays lazy everywhere; it's being HUNTED that
	# gets scarier the farther you push. Shared by both branches below so the
	# gradient applies to bosses too.
	#
	# CLAMPED AT BUDAPEST'S GATE (bead godot-test1-8gw.3). The city is the run's
	# destination, not another 2.2 km of escalation: `minf` on the SIGNED x pins
	# the gradient at the gate's own X, so walking east into Pest is exactly as
	# dangerous as arriving at the gate was and no more. `absf` stays OUTSIDE it,
	# so travelling WEST — the HQ is at x = -400 and the world runs on — is
	# untouched. BudapestPlan is a class_name on a RefCounted that depends on
	# nothing, so this is a constant read and not a cycle.
	var distance_factor := 1.0 + clampf(
		absf(minf(global_position.x, BudapestPlan.GATE.x)) / DISTANCE_SPEED_SCALE_DENOM,
		0.0, DISTANCE_SPEED_SCALE_MAX
	)

	if is_boss:
		# Bosses take NO per-instance random rolls: their size comes from the
		# terrain's deterministic schedule (boss_scale) and their speeds are fixed,
		# so a boss regenerates byte-identically when its chunk is revisited.
		detection_radius = BOSS_DETECTION_RADIUS
		# The centre of the territory this boss will never leave. See
		# home_position for why global_position is already the real spawn spot.
		home_position = global_position
		move_speed_instance = spec["move_speed"]
		# The MAX_CHASE_SPEED cap keeps the running-escape hatch true at any distance.
		#
		# BOSS_CHASE_SPEED is the boss MODIFIER's speed and applies to every kind
		# by default — a boss overrides its row here rather than inheriting it.
		# `boss_chase_speed` is the one opt-out, and it exists for a species whose
		# whole design is NOT reaching you: the snow titan is an archer that must
		# stay under a walking player, and inheriting 7 m/s would silently turn it
		# into a melee giant. Absent from every other row, so this `get` answers
		# the const for all of them (see SPECIES["titan"] for the full argument).
		chase_speed_instance = minf(
				float(spec.get("boss_chase_speed", BOSS_CHASE_SPEED)) * distance_factor,
				MAX_CHASE_SPEED
		)
		scale = Vector3.ONE * boss_scale
	else:
		# Set instance-specific speeds. One shared multiplier drives both speeds, so a
		# "fast" crocodile is fast at everything (and its chase always still outpaces its
		# own wander) instead of the two speeds drifting apart independently.
		var speed_factor := rng.randf_range(
				1.0 - spec["speed_random_factor"], 1.0 + spec["speed_random_factor"]
		)
		detection_radius = spec["detection_radius"]
		move_speed_instance = spec["move_speed"] * speed_factor
		# The min() keeps a top-rolled far croc from outrunning a RUNNING player — see
		# MAX_CHASE_SPEED above.
		chase_speed_instance = minf(
				spec["chase_speed"] * speed_factor * distance_factor, MAX_CHASE_SPEED
		)

		# Give this crocodile a randomized overall size. We scale the whole body
		# uniformly so the visual model and the physics capsule grow/shrink together;
		# gravity then settles it onto the ground regardless of size. The model's OWN
		# local scale stays 1, so model_base_scale cached below is unaffected and the
		# procedural body animation composes correctly on top of this body scale.
		var size_scale := rng.randf_range(
				1.0 - spec["size_random_factor"], 1.0 + spec["size_random_factor"]
		)
		scale = Vector3.ONE * size_scale

	# Set initial random direction
	_choose_new_direction()

	# Latch this crocodile's room-wide id from its (deterministic) node name, before
	# anything downstream can rename the node — see croc_id_for() for the scheme.
	_croc_id = croc_id_for(String(name))

	# Add to "crocodile" group for easy detection
	add_to_group("crocodile")
	add_to_group("enemy")

	# In a multiplayer room, a crocodile the ROOM has already killed (giant Teibi
	# crushed it on some peer and the master confirmed) must not come back when its
	# chunk regenerates here. One failed group lookup per crocodile AT SPAWN, never
	# per frame, and a plain no-op offline — exactly the shape and placement coin.gd
	# uses for is_coin_collected.
	var mp := get_tree().get_first_node_in_group("mp")
	if mp and mp.has_method("is_croc_dead") and mp.is_croc_dead(croc_id()):
		queue_free()
		return

	# Start with a random offset to avoid all crocodiles changing direction at once
	time_since_direction_change = randf() * spec["direction_change_interval"]

	# Per-instance phase offsets so a pack of crocodiles doesn't move in lockstep
	instance_phase = rng.randf_range(0.0, TAU)
	speed_phase = rng.randf_range(0.0, TAU)
	stride_phase = rng.randf_range(0.0, TAU)

	# Cache the visual model so we can animate its body procedurally
	model = get_node_or_null("Model")
	if model:
		model_base_scale = model.scale
		model_base_y = model.position.y
		model_rest_y = model_base_y
		# One walk over the model subtree applies all per-mesh styling (draw
		# cull + shared toon materials).
		_style_model_meshes(model)

	# Cached here, not per tick — see the `terrain` var. Safe at this point in the
	# spawn order: endless_terrain joins the "terrain" group at the top of its own
	# _ready(), long before it generates the chunk this crocodile is parented into.
	var found_terrain := get_tree().get_first_node_in_group("terrain")
	if found_terrain and found_terrain.has_method("is_wading_at"):
		terrain = found_terrain

	# Find the player node (defer to allow scene to fully load)
	call_deferred("_find_player")


func _style_model_meshes(node: Node) -> void:
	"""
	Recursively apply per-mesh styling to every GeometryInstance3D under the model.

	Two treatments per mesh, one walk:
	- Visual draw-range cull: beyond VISUAL_CULL_DISTANCE the renderer simply
	  skips drawing these meshes (works in gl_compatibility too). This changes
	  RENDERING only — the crocodile body, its AI, and its collision all stay
	  exactly as they were; the LOD manager's sleep radius handles the
	  simulation side independently. Entity counts are never reduced by this.
	- Shared toon+rim styling via ToonShading.apply_to_mesh, so crocs match the
	  hero's cel-shaded look. Its static cache hands every croc the SAME styled
	  material per source, so ~490 bodies add only a handful of materials.
	  Deliberately NO inverted-hull outline overlay here (the player has one):
	  that is a second draw call per mesh × ~490 crocs — unaffordable.
	"""
	if node is GeometryInstance3D:
		# Bosses scale the cull range by their body scale: a 9x boss is visible
		# from ~9x further, so culling it at the regular 60 m would make a
		# mountain of crocodile pop into view. Regular crocs (boss_scale = 1.0)
		# get byte-identical values to before.
		node.visibility_range_end = VISUAL_CULL_DISTANCE * boss_scale
		node.visibility_range_end_margin = VISUAL_CULL_MARGIN * boss_scale
	if node is MeshInstance3D:
		# Bosses get the darker/red-shifted shared variant so they read
		# menacing; both paths cache per SOURCE material, never per body.
		if is_boss:
			ToonShading.apply_boss_to_mesh(node)
		else:
			ToonShading.apply_to_mesh(node)
	for child in node.get_children():
		_style_model_meshes(child)


func _physics_process(delta: float) -> void:
	"""Update movement, body animation and collisions every physics frame."""
	# ------------------------------------------------------------------------
	# REMOTE DRIVE (multiplayer phase 5) — ABOVE the LOD backstop on purpose
	# ------------------------------------------------------------------------
	# In a room the master simulates every awake crocodile and broadcasts its
	# transform at 10 Hz; every other peer renders that instead of running its own
	# AI, so the whole room sees one crocodile in one place. This sits above the
	# lod_active backstop because a remote-driven crocodile is by definition near
	# SOME peer and must keep moving even in the window before this peer's own LOD
	# bookkeeping has caught up with that.
	if remote_driven:
		_tick_remote(delta)
		return

	# ------------------------------------------------------------------------
	# LOD SLEEP GATE (simulation level-of-detail) — BACKSTOP ONLY
	# ------------------------------------------------------------------------
	# Normally this never runs while asleep: set_lod_active(false) disables the
	# _physics_process callback entirely via set_physics_process(false), so a
	# slept crocodile costs zero script dispatches per tick. This early-return is
	# kept purely as a defensive backstop — if anything ever re-enables physics
	# processing on a slept crocodile, we still freeze in place (zero velocity,
	# no move_and_slide, no gravity — a distant croc was already standing on the
	# terrain, and skipping gravity is what keeps it perfectly put) instead of
	# half-simulating. Every other piece of state (heading, chase flags, phases,
	# confinement) is preserved untouched, so waking resumes seamlessly.
	# Crowd cooldown tick — before the lod gate so the frame that decides to sleep
	# still ticks, and sleep itself is refused while the guard ticks (see set_lod_active).
	_tick_crowd_cooldown(delta)

	if not lod_active:
		velocity = Vector3.ZERO
		return

	# Apply gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	# Snapshot BEFORE the branch below, which can clear is_paused mid-frame. The
	# collision check after move_and_slide must judge the frame we actually just
	# simulated: on the frame a pause expires the crocodile still stood perfectly
	# still, so handling collisions there would re-arm the bite a frame early and
	# defeat the point of _pause_and_change_direction's recovery window.
	var was_paused: bool = is_paused

	if is_paused:
		# Stand still while paused (still breathes via _animate_body below).
		pause_time_remaining -= delta
		if pause_time_remaining <= 0:
			is_paused = false
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		# Decide what we want to do this frame. Fleeing (Phoboman's Stink Wave)
		# overrides everything; otherwise chase the player if in range, else wander.
		if is_fleeing:
			flee_time_remaining -= delta
			if flee_time_remaining <= 0.0:
				# The whiff wore off — go back to normal wandering.
				is_fleeing = false
				_choose_new_direction()

		if is_fleeing:
			# If this row fears giant Teibi, refresh fear each frame while the giant remains in range.
			if float(spec.get("fears_giant_radius", 0.0)) > 0.0 and player_node != null:
				_update_chase_state()
			# Run directly away from the player.
			_flee()
		else:
			_update_chase_state()
			if is_chasing and player_node:
				# Chase the player
				_chase_player()
			elif is_tracking:
				# Nothing in smelling range, but a track underfoot: walk it. Set
				# by the hunt arm's second leg (`_track_scent`), which only a row
				# carrying `scent_radius` can ever reach — so for every animal in
				# the table this branch is dead and the wander below is unchanged.
				_track_move()
			elif is_investigating:
				# Somebody set a plate off across the floor: go and look at it.
				# UNDER the track and the chase on purpose — a live quarry and a
				# fresh footprint both outrank a noise, so the lure can never pull
				# a committed body off anything. See `investigate_point()`.
				_investigate_move(delta)
			else:
				# Wander with smooth, organic steering
				_wander(delta)

		# Steer around any block ahead so we don't drive our snout into it. This
		# may override the chase/wander heading for this frame.
		var avoiding := _avoid_obstacles()

		# If this is a patrol crocodile, turn it back toward the platform centre
		# when it gets near an edge (overrides the heading above).
		if is_confined:
			_steer_within_platform()

		# A boss is leashed to the area it spawned in. Same job as the platform
		# steer above, one shape over (a circle around home_position), and it sits
		# here for the same reason: it has to override the chase / wander / avoid
		# heading that was just chosen.
		if is_boss:
			_steer_within_territory()

		# THE TELEGRAPH IS A STANDSTILL, and it has to be one for the beat to mean
		# anything. `spot_clock` is non-zero only on a CONED body that has the
		# quarry in its arc and has not committed yet (`_update_chase_state`), and
		# a body that kept walking through its own warning would turn as it went —
		# rotating the quarry back out of the cone, resetting the clock, and
		# producing a guard that notices you forever and never engages. Zeroing
		# the heading rather than the velocity is what freezes the FACING too:
		# the branch below leaves `rotation.y` alone when there is nowhere to go.
		#
		# LAST, so it out-votes the wander, the obstacle feelers and both leashes —
		# every one of which would otherwise nudge a standing sentry. It cannot
		# strand one: the clock is reset the moment the quarry leaves the arc, and
		# the frame after that this is a no-op again.
		if spot_clock > 0.0 and not is_chasing:
			movement_direction = Vector3.ZERO

		# Rotate smoothly toward the desired heading and move that way.
		# Driving velocity from facing (not the raw direction) prevents sliding
		# sideways and makes turns curve naturally.
		if movement_direction.length() > 0.1:
			var target_rotation := atan2(movement_direction.x, movement_direction.z)
			# Turn harder while avoiding so we actually clear the block in time.
			var turn_rate: float = spec["turn_smoothness"] * (2.0 if avoiding else 1.0)
			rotation.y = lerp_angle(rotation.y, target_rotation, delta * turn_rate)

			# Flee and chase both move at the faster "chase" speed — and so does
			# TRACKING, which is the owner's "close to the characters' speed" and
			# the reason the number is this one rather than a new tunable: a
			# tracker travels at a speed `_ready()` has already clamped to
			# MAX_CHASE_SPEED, so a walking player is overhauled and a running one
			# is not, and no retune of a species row can reach around that.
			var current_speed := chase_speed_instance if (is_chasing or is_fleeing or is_tracking) else _wander_speed(delta)
			# The burst arm's one output (see `burst_factor`). It is 1.0 for every
			# species but the mountain cougar and the city alley hound, so this is
			# a no-op multiply for all four older rows.
			# Gated on `is_chasing` and NOT on `is_fleeing`: fleeing predators never
			# run the chase dispatch and would otherwise carry whatever factor it held
			# when the wave hit.
			if is_chasing:
				current_speed *= burst_factor
			if avoiding:
				current_speed *= spec["avoid_speed_factor"]
			velocity.x = sin(rotation.y) * current_speed
			velocity.z = cos(rotation.y) * current_speed
		else:
			velocity.x = 0.0
			velocity.z = 0.0

	# Move and resolve collisions (collisions are ignored while paused, matching
	# the original "harmless while recovering" behaviour).
	move_and_slide()
	if not was_paused:
		_handle_collisions()

	# Hard backstop: pin a patrol crocodile inside its platform so it can never
	# slip off the edge, even if a collision or the bite-lunge nudged it.
	if is_confined:
		_clamp_to_platform()

	# Hard backstop for the boss leash: the steer above is smooth and can be
	# out-voted (turn lag, a bite lunge, a shove from another body), this cannot.
	# After this line a boss's distance from home is <= BOSS_TERRITORY_RADIUS,
	# every frame, with no epsilon. Note _tick_remote returned long before here:
	# on a peer a boss is replayed from the master's samples, which are already
	# leashed — so there is no leash logic on the remote path and no protocol
	# change, which is also why a slept boss stays contained for free (its
	# position simply never changes).
	if is_boss:
		_clamp_to_territory()

	# Animate the body to match how fast we're actually moving.
	_animate_body(delta)


# ============================================================================
# DETECTION AND CHASE METHODS
# ============================================================================

func _find_player() -> void:
	"""Find and store reference to the player node (plus the MP manager, if any)."""
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player_node = players[0]
	# Cached once, group-based and null-safe like every other cross-system lookup
	# in this project — a scene run without Main simply leaves it null and every
	# read below falls through to the single-player behaviour.
	var mp := get_tree().get_first_node_in_group("mp")
	if mp != null and mp.has_method("nearest_member_position"):
		mp_node = mp


static func _is_quarry_giant(q: Node) -> bool:
	return q != null and q.has_method("crushes_crocodiles") and q.crushes_crocodiles()


func _update_chase_state() -> void:
	"""Check distance to the nearest quarry and update chase state."""
	if not player_node:
		is_chasing = false
		return

	# Check if the local player is grounded (can be smelled).
	# If the player jumps (is not on floor), crocodiles lose the scent.
	var player_is_grounded = true
	if player_node.has_method("is_on_floor"):
		player_is_grounded = player_node.is_on_floor()

	# Nearest SMELLABLE quarry, not nearest quarry — the two candidates are judged
	# INDEPENDENTLY. Letting the nearest one's groundedness stand for both means
	# one airborne peer vetoes the scent of a grounded teammate standing right
	# beside it, and on the master (which simulates the pack for everybody) that is
	# one player bunny-hopping to call every crocodile in range off their friend.
	var quarry: Node = player_node
	chase_target = player_node.global_position
	var distance_to_player: float = INF
	if player_is_grounded:
		distance_to_player = global_position.distance_to(chase_target)

	# IN A ROOM, "the player" means "the nearest MEMBER of the room". The master
	# simulates every awake crocodile for everybody, and by the isolation contract
	# a remote peer is a RemoteAvatar in NO group — so a crocodile that resolves
	# its quarry through group "player" alone can only ever hunt whoever happens
	# to be master, and the other one to three peers walk through the pack
	# untouched on every screen. Offline `nearest_member_position` answers null
	# and this whole block is skipped, so single-player is byte-for-byte unchanged.
	#
	# The bite still lands correctly with no protocol: the crocodile is
	# remote-driven on the quarry's own machine, where _tick_remote runs
	# move_and_slide + _handle_collisions against a real local player body.
	#
	# THE JUMP HATCH APPLIES TO REMOTE MEMBERS TOO (bead godot-test1-s86.15).
	# `nearest_member_position()` now honours the on-floor bit presence has always
	# carried, so it simply does not offer a teammate who is mid-jump — there is
	# no branch here, because "not smellable" and "not in the room" are the same
	# answer (`null`, or a nearer grounded member) to this loop.
	if mp_node != null:
		var remote: Variant = mp_node.nearest_member_position(global_position)
		if remote != null:
			# Whatever comes back is grounded by construction, so it is a candidate
			# unconditionally — which is what makes it able to win when the LOCAL
			# player is mid-jump and therefore not one. The two candidates stay
			# judged independently; see the comment above.
			var remote_distance: float = global_position.distance_to(remote as Vector3)
			if remote_distance < distance_to_player:
				distance_to_player = remote_distance
				chase_target = remote as Vector3

	# GIANT TEIBI DETERRENT (owner ruling 2026-09-04, bead godot-test1-upu).
	# A row carrying fears_giant_radius flees when ANY candidate (local player or
	# remote peer) is giant within fears_giant_radius.
	# Decided independent of the quarry/scent choice (Codex P1/P2) so a closer normal
	# teammate or an airborne giant does not suppress fear.
	# Placed above the acquisition beat so a hunter in the standstill beat flees
	# immediately instead of standing still to acquire.
	var fears_giant_radius: float = float(spec.get("fears_giant_radius", 0.0))
	if fears_giant_radius > 0.0:
		var giant_source: Vector3 = Vector3.ZERO
		var found_giant: bool = false
		var nearest_giant_dist: float = INF

		# Check local player candidate
		if player_node != null and _is_quarry_giant(player_node):
			var dist: float = global_position.distance_to(player_node.global_position)
			if dist <= fears_giant_radius:
				found_giant = true
				nearest_giant_dist = dist
				giant_source = player_node.global_position

		# Check remote avatar candidates
		if mp_node != null and mp_node.has_method("remote_avatars"):
			for avatar in mp_node.remote_avatars():
				if avatar != null and _is_quarry_giant(avatar):
					var avatar_pos: Vector3 = avatar.target_pos if ("target_pos" in avatar and avatar.target_pos is Vector3) else (avatar.global_position if (avatar is Node3D) else Vector3.ZERO)
					var dist: float = global_position.distance_to(avatar_pos)
					if dist <= fears_giant_radius and dist < nearest_giant_dist:
						found_giant = true
						nearest_giant_dist = dist
						giant_source = avatar_pos

		if found_giant:
			flee_from(giant_source, GIANT_FEAR_HOLD, player_node != null and giant_source == player_node.global_position)
			return

	if is_fleeing:
		return

	# TERRITORIAL LEASH (bosses only — and every boss KIND inherits it, because
	# boss is a MODIFIER on a species, so this one gate already covers the titan
	# and the dragon that come after the crocodile). A boss hunts NORMALLY while
	# the quarry is inside its territory and cannot engage one outside it at all:
	# walking out of the circle is the only counterplay, since a boss can't be
	# killed.
	#
	# Applied to the CHOSEN `chase_target`, never to the local player, because in
	# a room the quarry may be the remote member resolved just above — testing the
	# local player instead would leash the boss against a body it isn't hunting.
	#
	# Sits above the behaviour dispatch on purpose: this is a DETECTION decision
	# (may I engage this quarry at all), not a steering one, and CLAUDE.md's rule
	# is that detection is settled before the dispatch and an arm only bends the
	# route. Written as INF rather than as a second condition so it folds into the
	# single test below exactly like the grounded rule does — and so losing the
	# quarry runs the ordinary "lost the player" branch, which drops is_chasing
	# and picks a fresh wander heading. That is the whole of "they walk inside
	# some area".
	if is_boss and not in_territory(chase_target):
		distance_to_player = INF

	# Update chase state based on detection radius. `distance_to_player` is INF
	# when nothing is smellable, so the grounded rule is folded into this one test.
	# Bosses smell farther (still well under the LOD SIM_RADIUS — see the const);
	# `detection_radius` is resolved once in _ready(), see the var.
	var seen: bool = distance_to_player <= detection_radius

	# THE VIEW CONE, and it gates the ACQUISITION EDGE ONLY. A body that has
	# already got you keeps you until distance drops it — that is the existing
	# rule and the reason "sneak behind it" is a way past a guard rather than a
	# way to make one blind mid-chase. `view_cone_cos` is -1.0 for every
	# 360-degree row, so this is one dot product and never a behaviour change for
	# anything that has not asked for a cone.
	#
	# ABOVE THE DISPATCH, with the boss leash and the grounded rule, because all
	# four are the same question: may this body engage this quarry at all. An arm
	# bends where a predator steers; none of them may widen what it can see.
	if seen and not is_chasing and has_view_cone:
		var to_quarry := chase_target - global_position
		# ...and the storey. A bearing test is blind to height, and these bodies
		# stand on stacked floors — see VIEW_CONE_HEIGHT_BAND for the slab this
		# would otherwise see straight through.
		if absf(to_quarry.y) > VIEW_CONE_HEIGHT_BAND:
			seen = false
		to_quarry.y = 0.0
		if seen and to_quarry.length_squared() > 0.0001:
			var forward := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
			seen = forward.dot(to_quarry.normalized()) >= view_cone_cos

	# ...AND THE BEAT. In the cone and not yet chasing is not "caught": it is a
	# question mark and a ping, and `SPOT_TELEGRAPH_TIME` of standing there before
	# the chase flag flips. Leave the arc and the clock is spent — re-entering
	# costs a fresh one, which is what makes backing out of a doorway a real move.
	if has_view_cone:
		if seen and not is_chasing:
			if spot_clock <= 0.0:
				_announce_spot()
			spot_clock += get_physics_process_delta_time()
			# Still inside the beat: the body has noticed and has not committed.
			seen = spot_clock >= SPOT_TELEGRAPH_TIME
		else:
			spot_clock = 0.0
		if _spot_label != null:
			_spot_label.visible = spot_clock > 0.0

	if seen:
		if not is_chasing:
			# CROWD CONFUSION — refused acquisition inside Budapest (bead 8gw.16).
			# Above the is_chasing write: investigate_point refuses a chasing body,
			# so a confused hunter never lights the chase flag — it walks to a
			# citizen and checks documents for 2-10 s at _wander_speed() instead.
			# The refusal must PERSIST for the whole errand via _crowd_errand,
			# not is_investigating (which the HQ lure also sets — finding #1).
			# is_tracking / spot_clock are cleared once on the initial hit inside
			# _try_crowd_confusion, not on each persist frame (finding #5 ping loop).
			if _try_crowd_confusion():
				return
			# Just started chasing
			is_chasing = true
			# The beat is SPENT, not merely satisfied: `spot_clock` means "a
			# telegraph is running", and everything that reads it — the `?`, the
			# standstill in `_physics_process` — has to stop the frame the chase
			# starts, or a committed body stands still wearing a question mark.
			spot_clock = 0.0
			if _spot_label != null:
				_spot_label.visible = false
			# ...AND THE LURE IS OFF. A guard that spots you on its way to a plate
			# has something better to do than the errand, and it must not pick the
			# errand back up when it loses you — a diversion that survives an
			# acquisition is a puppet string. See `_abandon_investigation()`.
			_abandon_investigation()
			_announce_acquisition()
	else:
		if is_chasing:
			# Lost the player (too far OR player jumped)
			is_chasing = false
			# Choose new random direction
			_choose_new_direction()
			# Crowd-confusion cooldown is per-acquisition, not per-run; losing
			# the quarry is the edge that clears it so the next engagement can be
			# confused again. A miss does not set it, so this is the only clear.
			_crowd_confusion_cooldown = 0.0

	# ------------------------------------------------------------------------
	# BEHAVIOUR DISPATCH — the whole of it, and it is deliberately this small
	# ------------------------------------------------------------------------
	# Everything above this line is what EVERY predator does: find the quarry,
	# decide whether it can be smelled, and set `is_chasing` / `chase_target`.
	# Everything a SPECIES does differently hangs off the one `match` below, and
	# the shape of it is a contract for the beads that follow this one:
	#
	#   ONE ARM, ONE CALL, NOTHING ELSE. An arm is a species' behaviour name and
	#   a call to its own `_behave_*()`. No logic in the arm, no state shared
	#   between arms, no `if` before the match. Pack, ambush, charge, burst,
	#   ranged, hunt and leap are each two lines here plus one function of their
	#   own, and none of them has to read, or risk breaking, any of the others.
	#
	# AN ARM IS A MECHANIC, NOT AN ANIMAL, and "burst" is where that stopped
	# being a stylistic claim: the mountain cougar's pounce and the city alley
	# hound's alley sprint are ONE arm read with two sets of numbers. Eight
	# species, six arms. If a new predator's difference can be a number in its
	# SPECIES row, it must be — a seventh arm is for a mechanic none of these six
	# is. "ranged" earned its own because it is the first arm that does not steer
	# at all: it SPAWNS something (a bolt), which is a verb none of the others has.
	# "hunt" earned its own because it is the first whose subject is TIME: it does
	# not change where a predator can go or how fast, it changes WHEN a predator
	# that has already smelled you is allowed to walk in, and afterwards.
	# "leap" earned its own because it is the first that touches the Y AXIS: every
	# other arm leaves the body on the flat world's ground plane, and a winged boss
	# that never leaves it is a heavy quadruped with a wing-shaped silhouette.
	#
	# "solo" has NO ARM on purpose — it is the code above, unmodified, which is
	# also why an unknown or misspelled behaviour string degrades to solo instead
	# of crashing. The same degrade-don't-crash rule as the unknown-species
	# fallback in _ready().
	#
	# WHY IT LIVES AT THE END OF THIS FUNCTION rather than in _chase_player():
	# a behaviour may want to act when the predator is NOT chasing (an ambusher
	# has to burrow and wait), and this is the last point in the frame where both
	# `is_chasing` and `chase_target` are settled. Each arm decides for itself
	# whether it cares; `_behave_pack` returns immediately when idle.
	match spec["behavior"]:
		"pack":
			_behave_pack()
		"ambush":
			_behave_ambush()
		"charge":
			_behave_charge()
		"burst":
			_behave_burst()
		"ranged":
			_behave_ranged()
		"hunt":
			_behave_hunt()
		"leap":
			_behave_leap()


func _announce_spot() -> void:
	"""
	The telegraph beat: one `?` over the head and one ping, on the frame a coned
	body first holds the quarry in its arc.

	ONLY THE ENTERING EDGE, like `_announce_acquisition()` below and for the same
	reason — `spot_clock` is zero exactly when the beat is not already running, so
	standing in a guard's cone is one question mark and not sixty.

	THE LABEL IS BUILT HERE AND NEVER IN `_ready()`. Only a coned body can reach
	this, and only after it has actually seen something, so a field of crocodiles
	grows no nodes at all and the handful of guards inside one building grow one
	each, once, the first time they notice you. It is parented to the body, so the
	population reset frees it with everything else it was holding.

	THE PING IS THE HUNTER'S, deliberately reused rather than synthesized again: a
	guard and a retrieval unit are the same corporate chassis on two duties (see
	the `tower_guard` row), so "a GD-SURVEY unit has locked onto you" is one sound
	in this game and not two. Null-safe group lookup and `has_method` like every
	SFX hook here, so a self-check or a standalone scene stays quiet.

	# ponytail: SIMULATING PEER ONLY, and that is the known ceiling. This is reached
	# from `_update_chase_state`, which sits below `_tick_remote()`'s early return,
	# so in a room only the master sees the `?` — the same gap
	# `_announce_acquisition()` closes by re-detecting its edge off
	# `CROC_FLAG_CHASING` in `set_remote_state()`. The beat itself is correct
	# everywhere (the chase still starts 0.6 s late on every screen); only the tell
	# is missing. Closing it needs a new state bit for "telegraphing", which is a
	# protocol change this bead does not owe, and the upgrade path is exactly that
	# bit plus one more edge in `set_remote_state`.
	"""
	if _spot_label == null:
		_spot_label = Label3D.new()
		_spot_label.text = "?"
		_spot_label.font_size = 96
		_spot_label.pixel_size = 0.006
		_spot_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_spot_label.no_depth_test = true
		_spot_label.modulate = Color(1.0, 0.86, 0.25)
		_spot_label.position = Vector3(0.0, 1.9, 0.0)
		add_child(_spot_label)
	_spot_label.visible = true
	var sm := get_tree().get_first_node_in_group("sound_manager")
	if sm != null and sm.has_method("play_hunter_lock_on"):
		sm.play_hunter_lock_on()


func _announce_acquisition() -> void:
	"""
	ONE CUE, on the not-chasing -> chasing edge. Bosses growl, ambushers hiss,
	hunters ping; every other species acquires you in silence.

	WHY THIS IS A FUNCTION AND NOT THREE LINES IN THE EDGE ABOVE — it has TWO
	callers, and the second one is the whole point. The edge in
	`_update_chase_state` is only reached on the machine SIMULATING this body:
	`_tick_remote()` sits at the top of `_physics_process` and returns, so a
	remote-driven crocodile never reaches the chase logic, never reaches the
	behaviour dispatch, and never announces anything. Every peer but the master
	therefore heard nothing at all. `set_remote_state()` re-detects the same edge
	off `CROC_FLAG_CHASING` — which the packet has always carried — and calls
	this, so the cue fires once per engagement on EVERY screen in the room, with
	no new flag bit and no protocol change (see CROC_FLAG_BURROWED's note in
	mp_manager.gd, which rules exactly this).

	KEYED ON THE BEHAVIOUR, not the species name, for the hunt and the ambush
	alike: "you cannot see me coming" (the buried viper, smelling 5 m) and "I have
	started a clock you cannot see" (the hunter's 1.8 s telegraph) are properties
	of a MECHANIC, so a second ambusher or a second retrieval unit inherits its
	warning with its SPECIES row and no edit here. Boss-ness is the one exception,
	because it is a modifier rather than a behaviour.

	The hunter's ping used to live inside `_behave_hunt()`, at the point the
	telegraph clock is armed. That read naturally and was silent for three players
	out of four for the reason above; the clock stays there, the cue moved here.

	Null-safe group lookup and `has_method` like every SFX hook in this project, so
	a scene run without Main — every self-check, the standalone character scenes —
	simply stays quiet, and every cue routes through the sound manager's
	`_unlocked` browser-gesture gate rather than around it.
	"""
	var sm := get_tree().get_first_node_in_group("sound_manager")
	if sm == null:
		return
	if is_boss:
		if sm.has_method("play_boss_growl"):
			sm.play_boss_growl()
		return
	match spec["behavior"]:
		"ambush":
			if sm.has_method("play_viper_hiss"):
				sm.play_viper_hiss()
		"hunt":
			if sm.has_method("play_hunter_lock_on"):
				sm.play_hunter_lock_on()


func _behave_pack() -> void:
	"""
	The wolf arm: aim at MY slot on a ring around the quarry, not at the quarry.

	Three lines of work and no lines of coordination — see pack_steer_point() for
	the geometry and for the three invariants (no coordinator, LOD-safe,
	multiplayer-safe) that fall out of it being a pure function of this animal's
	own id and its own position.
	"""
	if not is_chasing:
		return
	chase_target = CrocSteering.pack_steer_point(
			chase_target, global_position, croc_id(),
			int(spec["pack_size"]), float(spec["pack_flank_radius"])
	)


func _behave_ambush() -> void:
	"""
	The viper arm: raise a flag, and let four numbers be the animal.

	THIS IS THE SHORTEST ARM IN THE FILE AND THAT IS THE FINDING, not an
	omission, so it is worth being able to check rather than take on faith. Walk
	the ambush back to its parts:

	  * "wander speed 0"      -> `move_speed` 0.0. `_wander_speed` multiplies it,
	                             so the wander velocity is identically zero.
	  * "reduced detection"   -> `detection_radius` 5.0, and because the trigger
	                             has no hysteresis the same number ENDS the lunge:
	                             that is the "short" in "short lunge", with no
	                             timer and no second state anywhere.
	  * "the strike"          -> `chase_speed` 5.5 (see the row: it is the
	                             crocodile's speed on purpose — an ambusher is
	                             paid in surprise, not in a foot race) plus
	                             `bite_lunge`, which is a MODEL offset and moves
	                             no body, so nothing here outruns the row.
	  * "surfaces rapidly"    -> `ambush_surface_ease_speed`, four times the sink.

	Which leaves exactly one thing that is NOT a number: whether the model is
	underground right now. That is this line. `_tick_river_sink` consumes it —
	it already owns `model_base_y`, and one owner of the rest height is the rule
	the burrow had to fit into rather than break.

	WHY NOT-CHASING IS THE RIGHT TEST, including the two edges: a SLEPT viper
	stops running this and freezes mid-ease, which is the same answer the river
	sink gives and needs no reconciliation (the target is recomputed from scratch
	every frame). A FLEEING viper never reaches here at all — the flee branch
	sits above _update_chase_state — so it keeps whatever it had, which for an
	animal that was by definition not chasing means it dives away under the sand.
	That is the read a snake fleeing a stink wave should have anyway.
	"""
	is_burrowed = not is_chasing


func _behave_charge() -> void:
	"""
	The bear arm: aim where I COMMITTED to go, not at where the quarry is now.

	Two lines of work and one Dictionary of memory — see charge_steer_point() for
	the geometry and for why the commitment is measured in metres rather than
	seconds. Clearing the lock the moment the chase drops is what makes a bear
	that reacquires you start a FRESH charge rather than resume a stale bearing.
	"""
	if not is_chasing:
		_charge_lock.clear()
		return
	chase_target = CrocSteering.charge_steer_point(
			chase_target, global_position, _charge_lock, float(spec["charge_commit"])
	)


func _behave_burst() -> void:
	"""
	The cougar/hound arm: run in surges, and pay for every one of them.

	Two lines of work and one Dictionary of memory, the same shape as the bear's.
	It is the FIRST arm shared by two species — the mountain cougar's pounce and
	the city alley hound's alley sprint are the same mechanic at different numbers
	— which is what the SPECIES table has been claiming since the crocodile row
	and had not yet had to prove.

	IT IS ALSO THE ONLY ARM THAT TOUCHES SPEED, and that is worth stating loudly
	because the other three go out of their way not to. `_behave_pack` and
	`_behave_charge` both return a POINT and their docstrings say, in as many
	words, that nothing there touches `chase_speed_instance` because a flanking or
	charging predator must not be able to outrun a running player. This one sets a
	MULTIPLIER on that clamped speed, so for the length of a pounce the body moves
	above MAX_CHASE_SPEED. The two SPECIES rows carry the full argument; the short
	version is that "running always escapes" is a claim about whether a GAP
	CLOSES, the gap is closed over time, and the mandatory recovery leg makes the
	cycle average fall well under the slowest character's run at every roll. It is
	measured in enemy_spawn_selfcheck's check 8, over repeated cycles, against a
	control with the recovery removed — which catches the runner, and is therefore
	the proof that the recovery is what saves them.

	Clearing the lock the moment the chase drops is what makes a cougar that
	reacquires you start a FRESH pounce rather than resume a half-spent one, and
	it is also what resets `burst_factor` to 1.0 so an idle animal wanders at its
	ordinary speed.
	"""
	if not is_chasing:
		_burst_lock.clear()
		burst_factor = 1.0
		return
	burst_factor = CrocSteering.burst_cycle_factor(global_position, _burst_lock, spec)


func _behave_ranged() -> void:
	"""
	The titan arm: stand off and throw a bolt at what you already decided to hunt.

	THE FIRST ARM THAT DOES NOT STEER. Pack and charge bend `chase_target`, burst
	bends the speed; this one leaves both exactly as the code above set them and
	instead SPAWNS something. Everything about that something — how it flies,
	what it looks like, what it kills, when it frees itself, how many of them one
	shooter may have in the air — belongs to scripts/boss_projectile.gd and is
	shared with every ranged enemy that follows. What is left here is the firing
	LOGIC that file's header explicitly refuses to own: when, at whom, how often.

	FOUR GATES, IN THIS ORDER, and each one is a rule rather than a tweak:

	  1. NOT CHASING, NO SHOT. A titan that has not smelled you does not fire into
	     the fog. This is also what makes the arm inert for a wandering boss, and
	     it needs no state of its own to be — `is_chasing` is settled above the
	     dispatch, for every species, before we get here.
	  2. INSIDE THE TERRITORY. Asked through the `in_territory()` seam, never as a
	     hand-rolled radius: the leash bounds where a boss may GO, and a boss that
	     could shell you from inside a circle you have already left would give
	     back the one counterplay the design has ("only skedaddle"). The detection
	     gate above already refuses a quarry outside the circle, so today this can
	     only fire if that gate is ever loosened — which is exactly the regression
	     worth a line, and boss_selfcheck drives this branch directly rather than
	     trusting it.
	  3. INSIDE THE FIRING BAND, and 4. OFF COOLDOWN — both of them
	     `ranged_shot_due()`, which is static and pure so the selfcheck measures
	     the shipped rule instead of a copy of it. See the "ranged" dict in
	     SPECIES["titan"] for why the band has a FLOOR as well as a ceiling.

	A refused shot is not an error anywhere: `fire()` itself answers null when the
	shooter is at its cap, and this arm may call it as often as it likes.
	"""
	if not is_chasing:
		# The lock is left ALONE here, where the pack, charge and burst arms all
		# clear theirs on the same edge. Those three hold a COMMITMENT that must
		# not be resumed stale (a half-spent pounce, a dead bearing); this one
		# holds a RELOAD, and a reload that reset every time the quarry stepped
		# out of range for a moment would make ducking behind a rock a way to get
		# an instant shot on every re-acquisition. It does not tick while idle
		# either — this return is above the countdown — so a titan that has been
		# alone for a minute comes back with exactly the cooldown it had left.
		return
	if is_boss and not in_territory(chase_target):
		return
	var row: Dictionary = spec["ranged"]
	# Flat distance: the world is flat at y = 0 by invariant, and the muzzle sits
	# metres above the body, so a 3D distance would report a longer shot than the
	# one the fairness contract is measured on.
	var flat := Vector2(chase_target.x - global_position.x, chase_target.z - global_position.z)
	if not CrocSteering.ranged_shot_due(flat.length(), get_physics_process_delta_time(), _ranged_lock, row):
		return
	# The muzzle rides the body's scale, so the bolt leaves a 6x titan's shoulder
	# rather than its ankle (see `muzzle_height`). The parent is our CHUNK, which
	# is what makes an unloaded chunk free any bolt still in the air.
	BossProjectile.fire(
			global_position + Vector3.UP * float(row["muzzle_height"]) * scale.y,
			chase_target, get_parent(), row, self)


func _behave_hunt() -> void:
	"""
	The hunter arm: announce, PACE, commit, and stop once the job is done.

	THE SIXTH ARM, and the first whose subject is TIME rather than geometry or
	speed. Pack bends the aim point, charge makes the aim point stale, burst bends
	the speed, ranged spawns a bolt; this one decides WHEN a predator that has
	already smelled you is allowed to walk in. Everything it does is either
	pre-contact pacing or post-contact resolution, and it can do neither by
	widening what the unit can smell: the detection decision is settled above the
	dispatch and this function never touches `detection_radius`, `is_chasing` or
	any speed. It bends `chase_target` and nothing else.

	    on acquisition   telegraph := hunt_telegraph_time, cue the lock-on
	    each frame       telegraph -= dt, disengage -= dt (floored at 0)
	    may close when   both are spent AND the director grants it
	    steer            hunt_steer_point(..., closing, hunt_standoff)

	THE THREE STATES ARE ONE BOOLEAN, on purpose. "Shadowing" is not a state with
	its own code — it is `closing == false`, which is the only thing the geometry
	takes — so the telegraph and the disengage are two reasons for the same
	answer rather than two branches that can disagree. There is nothing here for a
	fourth reason to have to be added to except one more `and`.

	LOD SAFETY, stated the way the wolf's `pack_steer_point` states it, because
	this is the first arm whose memory is measured in SECONDS: both timers are
	counted down by THIS function, which the LOD manager stops calling when it
	sleeps a distant body. A slept hunter therefore drains neither, and wakes
	owing exactly what it owed — it does not wake already committed, and it does
	not lurch, because there is no accumulated phase and no deadline in wall-clock
	time to have passed meanwhile. Losing the chase clears the whole lock, so a
	re-acquisition is a fresh engagement with a fresh telegraph; that errs
	MERCIFUL, which is the direction this class is allowed to err in.

	MULTIPLAYER-SAFE for the same reason the other steering arms are: `chase_target`
	is whatever `_update_chase_state` resolved (in a room, the nearest ROOM MEMBER),
	this only bends that point, and a remote-driven hunter never runs the arm at
	all — it renders the master's samples.
	"""
	if not is_chasing:
		# Everything: the telegraph owed, the disengage owed, and the commitment.
		# A hunter that loses you and finds you again starts the whole ritual over.
		_hunt_lock.clear()
		# ...and THEN the second leg. Out of detection is exactly where tracking
		# lives: the unit has no quarry to chase, so it goes looking for the track
		# of one. See `_track_scent()`.
		_track_scent()
		return

	# Direct detection out-votes the nose, always. A body that can smell you does
	# not need your footprints, and leaving the flag up would let the movement
	# branch in _physics_process pick the stale crumb over the live quarry.
	is_tracking = false

	if not _hunt_lock.has("telegraph"):
		# THE ACQUISITION EDGE — where the telegraph clock is armed, and nothing
		# else. The lock-on PING used to fire from right here, which read naturally
		# and was wrong: this arm runs only on the machine simulating the body, so
		# on a peer (which returns from `_tick_remote()` long before the dispatch)
		# the warning was silent — for three players out of four in a four-player
		# room. The cue now lives in `_announce_acquisition()`, called from the
		# `is_chasing` edge in `_update_chase_state()` AND from the same edge
		# re-detected in `set_remote_state()`. Read that function for the whole of
		# it. The clock stays here because a clock is behaviour, not feedback.
		_hunt_lock["telegraph"] = float(spec.get("hunt_telegraph_time", 0.0))

	# `_update_chase_state` has no `delta` of its own (see the note on the
	# dispatch), and this is the same seam `_behave_ranged` uses to get one.
	var delta: float = get_physics_process_delta_time()
	_hunt_lock["telegraph"] = maxf(float(_hunt_lock["telegraph"]) - delta, 0.0)
	_hunt_lock["disengage"] = maxf(float(_hunt_lock.get("disengage", 0.0)) - delta, 0.0)

	var closing: bool = bool(_hunt_lock.get("closing", false))
	var ready: bool = (float(_hunt_lock["telegraph"]) <= 0.0
			and float(_hunt_lock["disengage"]) <= 0.0)
	if not ready:
		# A grab that landed this frame put seconds on the disengage clock, which
		# drops an already-closing unit straight back to the ring. That is the
		# whole of "grab and disengage" — the hit itself was resolved at full cost
		# by the ordinary collision path before we ever got here.
		closing = false
	elif not closing:
		closing = _hunt_close_granted()
	_hunt_lock["closing"] = closing

	chase_target = CrocSteering.hunt_steer_point(chase_target, global_position, closing,
			float(spec.get("hunt_standoff", 0.0)))


func _track_scent() -> void:
	"""
	The hunt arm's SECOND LEG: with no quarry in smelling range, walk its track.
	Crowd errand has the movement branch (finding #2): while _crowd_errand
	the hunter must keep walking to the citizen, not to a scent crumb.

	Owner design ruling 2026-08-31: "hunters get a sled/smell sense... they can
	SMELL THE TRACK the heroes leave and follow it, at a speed close to the
	characters' speed - so there is adequate, persistent pressure from hunters on
	the heroes, not just ambient presence."

	    row key      scent_radius (absent or <= 0 = this species has no nose)
	    trail        crocodile_lod_manager's breadcrumb ring buffer
	    each check   is_tracking := a crumb was in range; track_target := that crumb
	    steering     _track_move() — the movement branch in _physics_process
	    while slept  advance_tracking() — the LOD manager's 9 Hz scan

	WHAT THIS DOES NOT TOUCH, and the list is the whole safety argument:

	  * `is_chasing`. The detection decision is settled above the behaviour
	    dispatch and stays there — this leg runs only when that decision came back
	    false, and it cannot flip it. So the danger vignette, the encounter
	    director, the acquisition ping and the MP chase flag all still mean
	    "something has actually smelled you", and mercy is still decided at
	    ENGAGEMENT, by the director, exactly as it was.
	  * `detection_radius`. The nose is a separate, wider sense that produces a
	    POINT TO WALK AT, never a longer reach. A tracker that arrives still has
	    to acquire you at 25 m like anything else, and everything that happens
	    after that acquisition is the code that already shipped.
	  * any speed constant. Tracking travels at this body's own
	    `chase_speed_instance`, which `_ready()` already clamped to
	    MAX_CHASE_SPEED. The lattice is therefore not merely respected but
	    unreachable from here: walking (5.0) lets a tracker close, running (9.0)
	    leaves it behind, and retuning the row cannot break either end.

	DETERMINISM: the trail is runtime state, outside the contract, the weather /
	fauna precedent. This function rolls no dice and draws from no RNG stream — it
	cannot slide a single spawn position anywhere in the world.

	Null-safe and group-discovered like every cross-system read here: no LOD
	manager in the scene (a character scene run standalone, most self-checks) and
	the unit simply has nothing to smell and wanders as it always did.
	"""
	# While on a crowd errand the branch order would otherwise hand the movement
	# to _track_move() and the hold never decrements (finding #2).
	if _crowd_errand:
		is_tracking = false
		return
	is_tracking = false
	var radius: float = float(spec.get("scent_radius", 0.0))
	if radius <= 0.0:
		return
	# Not cached, deliberately: `get_first_node_in_group` is a hash lookup, and a
	# cached reference would need invalidating on a scene change to buy it back.
	var trail := get_tree().get_first_node_in_group("lod_manager")
	if trail == null or not trail.has_method("scent_point"):
		return
	var point: Variant = trail.scent_point(global_position, radius)
	if not (point is Vector3) or not (point as Vector3).is_finite():
		return
	track_target = point
	is_tracking = true


func _track_move() -> void:
	"""
	Set the heading toward the crumb this tracker is walking at.

	The tracking twin of `_chase_player()`, and as small: a behaviour that steers
	is a direction and nothing else. Keeping `wander_heading` in step is the same
	trick `_flee()` uses — the frame the trail goes cold the unit carries on in the
	direction it was already facing instead of snapping back to a stale heading.
	"""
	var to_track := track_target - global_position
	to_track.y = 0.0
	if to_track.length() < 0.01:
		return
	movement_direction = to_track.normalized()
	wander_heading = atan2(movement_direction.x, movement_direction.z)


func investigate_point(pos: Vector3, seconds: float,
		route: PackedVector3Array = PackedVector3Array()) -> bool:
	"""
	Go and look at `pos` for `seconds`, then walk back and resume the beat.

	@param pos: world space. The HQ's cyan `P` plate that was just stepped on.
	@param seconds: how long to stand facing it once there.
	@param route: the corners to walk on the way, world space, ending at or near
	    `pos` — `TowerInterior.plan_route()`'s output. EMPTY means "straight
	    there", which is the honest answer for an open room and the only thing a
	    caller without a floor plan can say.
	@return: whether the lure was TAKEN. False is the ordinary answer, not an
	    error: a body that is busy refuses, and the caller spends its cooldown
	    anyway (see `TowerInterior._press_lure_pad`).

	THE ANTI-PUPPET RULES ARE ALL HERE, in the one shared function, because there
	are two ways in — a local press and the master applying a relayed `pad` verb —
	and a rule enforced at either door is a rule the other door does not have:

	  1. A BUSY BODY REFUSES. Chasing, biting or already on an errand: the
	     diversion may never erase a guard's stake in you, and it may never queue.
	  2. AN ACQUISITION CANCELS (`_abandon_investigation`, on the `is_chasing`
	     edge in `_update_chase_state`) — so a guard that catches sight of you
	     mid-walk does not resume the errand after losing you.
	  3. THE PAD'S OWN COOLDOWN re-arms only after the walk and the hold, which is
	     the caller's half and the one that stops two players alternating a pair.

	REMOTE-DRIVEN BODIES REFUSE TOO: in a room the master owns the walk and every
	other peer renders its samples, so a peer applying this locally would be
	writing state its own `_tick_remote()` overwrites 100 ms later — and would
	grow a leash nothing on that machine ever hands back. `set_remote_state()`
	clears an errand that was already running when the master's first sample
	arrived, which is the same hole reached from the other side.
	"""
	if remote_driven or is_chasing or is_biting or is_investigating:
		return false
	if not pos.is_finite() or not is_finite(seconds) or seconds <= 0.0:
		return false
	_investigate_path = []
	for point: Vector3 in route:
		if point.is_finite():
			_investigate_path.append(point)
	if _investigate_path.is_empty() or not _investigate_path[-1].is_equal_approx(pos):
		_investigate_path.append(pos)
	# THE WAY BACK IS THE WAY OUT, REVERSED, with the post on the end — built now
	# rather than when it is wanted, because by then the body is standing on a
	# plate and the corners it came round are the only ones it knows are walkable.
	_investigate_home = []
	for i in range(_investigate_path.size() - 2, -1, -1):
		_investigate_home.append(_investigate_path[i])
	is_investigating = true
	# WAKE IT, and the refusal in `set_lod_active()` keeps it awake for the errand.
	# A storey is wider than SIM_RADIUS, so the guard a far plate lures is usually
	# asleep when the plate is pressed — and a sleeper runs no `_physics_process`,
	# so setting the flag alone would have lured nobody. The manager's next scan
	# puts it back down the moment the errand ends.
	set_lod_active(true)
	investigate_target = _investigate_path[0]
	_investigate_hold = seconds
	_investigate_aim(_investigate_path[0])
	if is_confined:
		_investigate_leash = {"center": confine_center, "half": confine_half}
		_investigate_home.append(confine_center)
	return true


func _investigate_aim(point: Vector3) -> void:
	"""Walk at `point` from here, with a fresh stall clock. The one waypoint seam."""
	investigate_target = point
	_investigate_stall = 0.0
	_investigate_best = INF


func _investigate_move(delta: float) -> void:
	"""
	One frame of the lure: walk the corners out, stand and face the plate, walk
	the corners home.

	Three legs and no phase enum — `_investigate_hold` above zero IS the outbound
	leg, and the last waypoint of whichever list is being walked is that leg's
	destination. Nothing here touches a speed: leaving `is_chasing` / `is_tracking`
	alone is what makes the whole errand happen at `_wander_speed()`.
	"""
	# THE LEASH REACHES WHERE THE BODY IS GOING, and it is re-grown here rather
	# than once at the press because an acquisition SHRINKS it back around the
	# body (see `_abandon_investigation`) and the walk home has to be able to
	# reach the post again afterwards.
	_investigate_grow_leash(investigate_target)
	var to_target := investigate_target - global_position
	to_target.y = 0.0
	var reach := to_target.length()

	if reach > INVESTIGATE_ARRIVE:
		# ---- WALKING, and watched for PROGRESS rather than for time. A leg that
		# stops getting closer gives up, rather than leaving a body off its post
		# with a grown leash for the rest of the run.
		if reach < _investigate_best - INVESTIGATE_PROGRESS:
			_investigate_best = reach
			_investigate_stall = 0.0
		else:
			_investigate_stall += delta
		if _investigate_stall > INVESTIGATE_STALL_TIME:
			if _investigate_hold > 0.0:
				_abandon_investigation()
			else:
				# ponytail: the way home is blocked too, so the leash is handed
				# back where the body stands and the hard clamp puts it back on
				# its beat in one frame. A visible jump, in the one case where
				# every other option is a guard that is never on its post again.
				_end_investigation()
			return
		movement_direction = to_target / reach
		wander_heading = atan2(movement_direction.x, movement_direction.z)
		return

	if _investigate_path.size() > 1:
		# ---- A CORNER. Take the next one; the heading is picked next frame.
		_investigate_path.pop_front()
		_investigate_aim(_investigate_path[0])
		return

	if _investigate_hold <= 0.0:
		_end_investigation()  # Home: the last waypoint IS the authored post.
		return

	# ---- THE HOLD. A zero heading is what freezes the body AND its facing (the
	# rotation branch in `_physics_process` leaves `rotation.y` alone when there is
	# nowhere to go), so the facing is written straight in — this is the whole
	# point of the diversion: 120 degrees of cone pointing at a plate and away from
	# wherever the player is walking.
	movement_direction = Vector3.ZERO
	if reach > 0.05:
		rotation.y = atan2(to_target.x, to_target.z)
		wander_heading = rotation.y
	_investigate_hold -= delta
	if _investigate_hold <= 0.0:
		_investigate_go_home()


func _investigate_grow_leash(point: Vector3) -> void:
	"""
	Widen the patrol box, around its current centre, until it contains `point`.

	Never shrinks and never moves the centre, so the box always contains both the
	body and where the body is going — which is what makes growing it safe: the
	hard clamp keeps running and cannot teleport anybody.
	"""
	if not is_confined or _investigate_leash.is_empty():
		return
	var off := Vector2(point.x - confine_center.x, point.z - confine_center.z)
	confine_half = Vector2(
			maxf(confine_half.x, absf(off.x) + INVESTIGATE_LEASH_MARGIN),
			maxf(confine_half.y, absf(off.y) + INVESTIGATE_LEASH_MARGIN))


func _abandon_investigation() -> void:
	"""
	Cancel an OUTBOUND errand: the guard spotted somebody, or the walk timed out.
	# Also clears the crowd latch (finding #1) — a lure cancellation must not
	# leave a ghost crowd errand that keeps refusing acquisitions.

	ONE FUNCTION FOR BOTH, because the body's obligation is the same either way —
	the leash it is standing in is borrowed and it has to be given back where it
	was taken. What the acquisition adds is that the plate stops being the
	destination, which is exactly what "does not resume the walk after losing you"
	means, and that THE GROWTH IS TAKEN BACK IMMEDIATELY: the box becomes the
	authored extents around wherever the body is now, so the chase that just
	started is fought over a beat-sized patch and not over the whole storey the
	errand opened up. The centre moves instead of the size, so nothing jumps.
	"""
	if not is_investigating or _investigate_hold <= 0.0:
		return  # Already on the way home; an errand is abandoned once.
	_crowd_errand = false
	_investigate_go_home()


func _investigate_go_home() -> void:
	"""
	Turn the errand around: the plate stops being the destination and the route
	the body came by, reversed, becomes the way back to the post.

	Shared by the two ways an outbound leg ends — the hold running out and an
	acquisition cancelling it — because what the body owes afterwards is the same
	either way, and a second copy of "swap the path, hand the growth back" is a
	second copy to get wrong. It is also why the natural expiry cannot be routed
	through `_abandon_investigation()`: that one refuses a body whose hold has
	already reached zero, which is exactly what an expiring hold is.
	"""
	_investigate_hold = 0.0
	if not _investigate_leash.is_empty():
		confine_center = global_position
		confine_half = _investigate_leash["half"]
	if _investigate_home.is_empty():
		_end_investigation()  # Unconfined: no post to walk back to.
		return
	_investigate_path = _investigate_home
	_investigate_home = []
	_investigate_aim(_investigate_path[0])


func _end_investigation() -> void:
	"""Home again: hand the authored leash back and go back to the beat."""
	if not _investigate_leash.is_empty():
		confine_center = _investigate_leash["center"]
		confine_half = _investigate_leash["half"]
		_investigate_leash = {}
	_crowd_errand = false
	is_investigating = false
	_investigate_hold = 0.0
	_investigate_path = []
	_investigate_home = []
	_choose_new_direction()


## CROWD CONFUSION — Budapest crowd false-arrest (bead godot-test1-8gw.16).
## One pure helper so the probe can drive the decision without a body.
## Returns true if THIS acquisition should be refused (caller must NOT set
## is_chasing and should walk to a citizen instead). Runtime RNG only —
## no hash, no run_seed, no chunk draw, so no spawn moves.
## ponytail: errand targets a SNAPSHOT of the citizen's pos; the walker keeps
## walking, so the robot checks an empty patch of pavement. Tracking the walker
## needs a live handle, which citizens do not have (no body, no group).
static func _should_confuse(chance: float, inside_budapest: bool, has_citizen: bool, roll: float) -> bool:
	return inside_budapest and has_citizen and chance > 0.0 and roll < chance


func _nearest_citizen_pos() -> Variant:
	"""Walk the crowd manager's walker array for the nearest active citizen."""
	var crowd := get_tree().get_first_node_in_group("crowd")
	if crowd == null or not crowd.has_method("nearest_citizen_to"):
		return null
	return crowd.nearest_citizen_to(global_position)


func _try_crowd_confusion() -> bool:
	"""
	Refused-acquisition gate for Budapest crowd confusion.

	Called ABOVE the is_chasing write, on the acquisition edge only.
	investigate_point() refuses a chasing/busy/remote body, so this being a
	refusal rather than a cancellation is enforced by the callee. Uses the
	global randf() family (randomized at boot, never a run_seed hash), so
	it costs the deterministic streams nothing — verified by the world A/B.
	City-only via BudapestPlan.contains() and requires a citizen nearby.

	persistence: once confused the body is _crowd_errand for 2-10 s; the
	next frame's _update_chase_state would otherwise see seen+!is_chasing and
	fall through to is_chasing=true + _abandon_investigation(), destroying the
	stall ~16 ms after it started. So a running errand keeps refusing on the
	dedicated latch, not on is_investigating which the HQ lure also sets.
	"""
	# Persist the refusal for the whole crowd errand via dedicated latch (finding #1).
	if _crowd_errand:
		return true
	var chance := float(spec.get("crowd_confusion_chance", 0.0))
	if chance <= 0.0:
		return false
	if remote_driven:
		return false
	if _crowd_confusion_cooldown > 0.0:
		return false
	# CITY-ONLY — BudapestPlan.contains via the class, never a restated rect.
	if not BudapestPlan.contains(global_position.x, global_position.z):
		return false
	# Roll BEFORE the O(60) crowd walk so misses (30% at 0.7) pay nothing.
	var roll := randf()
	if roll >= chance:
		return false
	var citizen_pos: Variant = _nearest_citizen_pos()
	if citizen_pos == null or not (citizen_pos is Vector3):
		return false
	var pos: Vector3 = citizen_pos as Vector3
	if not pos.is_finite():
		return false
	# Runtime draw, uniform 2-10 s stall, outside the determinism contract.
	var stall := randf_range(2.0, 10.0)
	# investigate_point walks at _wander_speed() so the stall is watchable;
	# busy/remote guards make this return false with no side effect.
	if not investigate_point(pos, stall):
		return false
	_crowd_errand = true
	_crowd_confusion_cooldown = CROWD_CONFUSION_COOLDOWN
	is_tracking = false
	spot_clock = 0.0
	if _spot_label != null:
		_spot_label.visible = false
	return true


func advance_tracking(delta: float) -> void:
	"""
	SLEPT BUT STALKING: walk a sleeping tracker up the trail, kinematically.

	@param delta: seconds since the LOD manager's previous scan (~0.11 s)

	THE CONFLICT THIS SOLVES, and it is the reason the owner's ruling called it
	out by name: `scent_radius` is 150 m and `crocodile_lod_manager.SIM_RADIUS` is
	45, so a hunter that has just found your track is by definition asleep — and a
	slept body runs no `_physics_process` at all, which is the whole point of the
	LOD gate and must stay true. Waking it instead would put every tracker inside
	150 m back on the full physics+raycast budget, which is precisely the cost the
	LOD manager exists to avoid.

	So the sleeper is advanced by the scan that is already running: no physics, no
	gravity, no collision, no `move_and_slide`, one lerped step of
	`chase_speed_instance * delta` on the XZ plane. Entity counts are unchanged
	(a slept crocodile is still slept, never removed), near-player behaviour is
	unchanged (inside SIM_RADIUS the body is awake and this never runs), and the
	body wakes into the ordinary hunt arm from wherever the trail brought it.

	Y IS LEFT ALONE. The world is flat at y = 0 and `set_lod_active()` refuses to
	sleep a body that is not `is_on_floor()`, so a sleeper is standing on the
	ground and stays standing on it. The crumbs carry the PLAYER's y, which is a
	capsule's centre and not a floor.

	ponytail: no obstacle feelers on the slept step — the walk is a straight line
	and can cross a mountain massif. It is beyond SIM_RADIUS and past the draw
	cull for every metre of it, and `move_and_slide`'s depenetration pushes a woken
	body out of a block within a few frames. The upgrade path is to run
	`_avoid_obstacles()` here, which needs a physics-space query from `_process`
	rather than from `_physics_process`.
	"""
	# Awake bodies steer through the ordinary movement branch; a remote-driven one
	# renders the master's samples and owns none of its own motion. Bosses never
	# sleep, and none carries the row key anyway.
	if lod_active or remote_driven or is_boss:
		return
	_track_scent()
	if not is_tracking:
		return
	var to_track := track_target - global_position
	to_track.y = 0.0
	var step: float = chase_speed_instance * delta
	var reach: float = to_track.length()
	if reach < 0.01:
		return
	# Never overshoot the crumb: the next scan picks a fresher one from there.
	var dir := to_track / reach
	global_position += dir * minf(step, reach)
	rotation.y = atan2(dir.x, dir.z)
	has_stalked = true

	# ...AND HAND THE BODY TO THE GROUND IT IS NOW STANDING ON. Everything the
	# terrain spawns is parented to its chunk so that unloading the chunk frees it,
	# which is exactly right for a body that never moves — and exactly wrong for
	# one that walks 200 m. A tracker following a quarry away from its birth chunk
	# would otherwise be deleted mid-stalk, by a chunk that unloaded *because the
	# player left it*: the one case where the unit is doing precisely what it is
	# supposed to. `adopt_wanderer` re-parents it to the chunk under its feet, so
	# it keeps a correct streaming lifetime (it still dies when the ground it is
	# actually on unloads) and keeps its NAME, which is its room-wide id.
	#
	# Group-discovered and `has_method`-guarded like every cross-system call here:
	# a standalone scene or a headless harness has no terrain, and the unit simply
	# stays where it was parented.
	var terrain := get_tree().get_first_node_in_group("terrain")
	if terrain != null and terrain.has_method("adopt_wanderer"):
		terrain.adopt_wanderer(self)


func _behave_leap() -> void:
	"""
	The winged-boss arm: hop, and let the leash decide where you may land.

	Owner, verbatim: "let those Rock and Dragons be able to make a decent jumps
	like windman does with F key." THE SEVENTH ARM, and the first that touches the
	Y AXIS — pack and charge and hunt bend the aim point, burst bends the speed,
	ranged spawns a bolt, and every one of them leaves the body on the ground. A
	roc and a green dragon have wings and must not read as heavy quadrupeds, and
	this world is flat at y = 0 by invariant, so the answer is neither terrain nor
	flight: a BOUNDED LEAP. The body launches, arcs under its own softened gravity,
	and lands back on the same flat ground it left. Nothing about the world's
	flatness changes; the only thing that leaves y = 0 is a boss, transiently, on
	its own arc.

	    grounded, clock spent, landing legal   ->  velocity.y := leap_launch_speed
	    airborne                               ->  hold the arc, burst_factor := leap_speed_factor
	    grounded, clock running                ->  burst_factor := leap_recover_factor

	IT IS THE BURST'S SHAPE WITH A VERTICAL COMPONENT, and deliberately so: a leg
	above the sustained ceiling, paid for by a mandatory recovery leg below it. The
	only difference is the unit — the cougar spends its pounce in METRES (see
	`burst_cycle_factor` for why that is right for a ground sprint), a hop is a
	single indivisible commitment whose length physics already fixes, so the cycle
	here is measured in SECONDS by `leap_due()`. The promise is the burst's,
	verbatim: not "nothing is ever faster than 8.5" but "running escapes across the
	whole hop-and-recovery cycle" — a claim about a gap over time, measured over
	repeated cycles by enemy_spawn_selfcheck's leap probe against a negative
	control with the recovery removed (which catches the runner, and is therefore
	the proof that the recovery is what saves them).

	THE ARC RIDES ON TOP OF `_physics_process`'s GRAVITY RATHER THAN REPLACING IT.
	That block runs before the dispatch and has already subtracted `GRAVITY * delta`
	this frame, so one line adds the difference back and the body falls at
	`leap_gravity` instead. Windman's Air Rush does exactly this (it multiplies
	`frame_gravity` by WINDMAN_GRAVITY_FACTOR to glide), and it is why the arc
	constants live in the SPECIES row rather than borrowing GRAVITY: this project's
	gravity is per-script and deliberately arcade-y, so a hop tunes its own arc.
	Nothing else in the file writes `velocity.y`, and nothing here writes
	`global_position` — the feet come back to y = 0 by the arc, not by a settle.

	THE LEASH BOUNDS THE JUMP, AND IT DOES SO IN THREE PLACES — which is worth
	being precise about, because only the VERTICAL half of a hop is ballistic. The
	horizontal half is not: `_physics_process` re-drives `velocity.x/z` from the
	body's facing every frame, airborne included, so a hop is steered by exactly
	the same chase / avoid / leash chain a walk is. What a launch commits to is the
	airtime, not the destination. So:

	  1. BEFORE THE LAUNCH, here. The landing point is PROJECTED — `leap_reach()`
	     along the bearing to the quarry, i.e. where the hop goes if nothing bends
	     it, which is the OUTERMOST landing the steer can produce — and asked the
	     keystone's own `in_territory()` seam, never a hand-rolled radius. Illegal
	     landing, no hop: the boss keeps hunting on the ground (the inherited boss
	     behaviour it has whenever it is not mid-arc anyway) and bounds again the
	     moment a legal landing exists. The clock is NOT spent on a refusal — a
	     dragon pinned at its fence is not also being made to wait.
	  2. DURING, by `_steer_within_territory()`, which runs below the dispatch and
	     cancels the outward part of the heading for an airborne body exactly as it
	     does for a walking one. Nothing here had to teach it about y.
	  3. AFTER, by `_clamp_to_territory()`, still the hard backstop and still
	     needing no y-awareness to be one: it is measured on XZ, so it contains a
	     body mid-arc exactly as it contains one on the ground, and it zeroes only
	     the horizontal velocity — a clamped hop still falls and still lands.

	The pre-launch gate is what makes 2 and 3 rare rather than load-bearing: a boss
	that never launches at its own fence is not one that keeps being caught at it.

	MULTIPLAYER: a hop is MOTION. `_tick_remote()` returns long before the
	dispatch, so a peer never runs this arm and simply replays the master's position
	samples, y included (it assigns the whole interpolation Vector3 to `velocity`) —
	no flag, no new byte, no protocol change.

	TWO PLACES ALREADY STOP THIS ARM, and neither needed teaching about y. A PAUSED
	body (`_pause_and_change_direction`, which every landed bite opens) skips the
	whole dispatch, so a boss that bites you mid-arc finishes the arc under the
	file's own GRAVITY — it drops out of the sky onto what it just bit, which is the
	right read and is why boss_selfcheck measures the arc's AIRTIME rather than its
	apex. A SLEPT body (`set_lod_active(false)`) runs no `_physics_process` at all
	and freezes wherever it was; SIM_RADIUS (45) is far outside
	BOSS_DETECTION_RADIUS (25), so a boss close enough to be mid-arc for a reason is
	always awake, and one slept mid-air resumes its fall on the frame it wakes.
	"""
	if not is_chasing:
		# The commitment and the clock both go, the burst arm's edge verbatim: a
		# boss that loses you and finds you again bounds on the re-acquisition
		# frame rather than resuming someone else's recovery, and the multiplier
		# goes back to 1.0 so an idle animal wanders at its ordinary speed.
		_leap_lock.clear()
		burst_factor = 1.0
		return

	var grounded := is_on_floor()
	if not grounded:
		# Mid-arc. Hold the softened gravity and carry the hop's speed; no steering
		# decision is taken here, which is what "the arc stays honest" means.
		velocity.y += (GRAVITY - float(spec.get("leap_gravity", GRAVITY))) \
				* get_physics_process_delta_time()
		burst_factor = float(spec.get("leap_speed_factor", 1.0))
		return

	# On the ground: recovering, and possibly about to go again.
	burst_factor = float(spec.get("leap_recover_factor", 1.0))
	var bearing := Vector3(chase_target.x - global_position.x, 0.0,
			chase_target.z - global_position.z)
	if bearing.length() <= 0.01:
		# STANDING ON THE QUARRY. There is no bearing to project along, and the
		# tempting answer — project nothing, land where you are — is an UNGUARDED
		# LAUNCH: the body still travels for the whole airtime, along its own
		# facing, which three metres inside the fence is a hop straight through it.
		# So project the facing, which is the direction the hop actually takes.
		bearing = Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	var landing: Vector3 = global_position \
			+ bearing.normalized() * CrocSteering.leap_reach(chase_speed_instance, spec)
	# `in_territory()` is meaningless on a non-boss (home_position is never
	# captured there), so a hypothetical ordinary leaper is simply unleashed —
	# the same shape as every other `is_boss` gate in this file.
	var landing_ok := (not is_boss) or in_territory(landing)
	if CrocSteering.leap_due(true, landing_ok, get_physics_process_delta_time(), _leap_lock, spec):
		velocity.y = float(spec["leap_launch_speed"])
		burst_factor = float(spec.get("leap_speed_factor", 1.0))


func _hunt_close_granted() -> bool:
	"""
	May this unit escalate from shadowing to closing? ABSENT DIRECTOR = GRANTED.

	The seam the encounter director (bead godot-test1-9rm.4) hangs off: it will
	join group "hunt_director" and answer `request_hunt_close()` with the pursuer
	caps, the shared cooldown and the escape-sector rule. None of that exists yet
	and this bead does not wait for it — a missing director, a director that does
	not implement the method, and a scene with no director at all (the standalone
	`hunter_robot.tscn`, every self-check, every headless harness) all take the
	same path and answer true, so the behaviour above is complete and shippable
	with nothing else in the world. The same degrade-don't-crash rule as the
	unknown-behaviour fallback in the dispatch and the unknown-species fallback in
	_ready(): the absence of an optional system is a GRANT, never an error and
	never a hang.

	@return true when this hunter may close on its quarry

	ponytail: asked once per escalation edge and then latched in the lock, not
	polled every frame — one group lookup per engagement rather than one per
	hunter per tick. The ceiling is that a director cannot REVOKE a commitment
	already in flight, only withhold the next one; if .4 needs revocation, the
	upgrade path is to drop the latch and ask every frame while closing.
	"""
	var director := get_tree().get_first_node_in_group("hunt_director")
	if director and director.has_method("request_hunt_close"):
		return bool(director.request_hunt_close(self))
	return true


func _chase_player() -> void:
	"""Set movement direction toward whatever _update_chase_state picked."""
	if not player_node:
		return

	# Calculate direction to the quarry (on XZ plane). `chase_target` is the local
	# player's position solo, and in a room the nearest member's — see
	# _update_chase_state; it is only ever read on a frame that function just set it.
	var direction_to_player = chase_target - global_position
	direction_to_player.y = 0  # Keep movement on horizontal plane
	movement_direction = direction_to_player.normalized()


func _flee() -> void:
	"""
	Run directly AWAY from the player (Phoboman's stink). Falls back to the
	remembered smell origin if the player reference is momentarily missing, and to
	the current heading if we somehow sit right on top of the source.
	"""
	var away := Vector3.ZERO
	if player_node and flee_tracks_player:
		away = global_position - player_node.global_position
	else:
		# `flee_tracks_player` false means the smell came from SOMEBODY ELSE'S
		# screen (MpManager relayed it to the master). The local player is then
		# the wrong reference entirely — running from it would herd the pack
		# straight at the peer who cast the wave — so the remembered origin is
		# the only correct one. See flee_from().
		away = global_position - flee_source
	away.y = 0.0

	if away.length() < 0.01:
		away = Vector3(sin(wander_heading), 0.0, cos(wander_heading))

	movement_direction = away.normalized()
	# Keep the wander heading in sync so obstacle-avoidance steering composes
	# cleanly and the croc holds its escape course instead of curving back.
	wander_heading = atan2(movement_direction.x, movement_direction.z)


func flee_from(source: Vector3, duration: float, tracks_player: bool = true) -> void:
	"""
	Public hook called by Phoboman's Stink Wave (via the "crocodile" group): make
	this crocodile turn tail and run from the player for `duration` seconds. Drops
	any current chase. `source` is the smell's origin.

	`tracks_player` is what makes the source mean something. Solo — and for the
	local player's own wave — it stays true and the flight tracks the player as it
	always has. A wave RELAYED from another peer passes false, because the master
	applying it has no body for the caster: `_flee()` would otherwise run every
	crocodile away from the MASTER's player, i.e. straight toward the peer who
	actually cast it, and `player_controller.clear_nearby_crocodiles()` would herd
	the pack onto a respawning teammate instead of off them.
	"""
	# Bosses shrug the stink off. They KEEP group "crocodile" membership — the
	# wave still finds them, they just don't care; immunity lives here, not in
	# group tricks (so LOD sleep and every other group consumer stays intact).
	if is_boss:
		return
	# A SEALED MACHINE HAS NO NOSE. Same placement and same reason as the boss
	# return above — immunity lives HERE, not in group tricks, so the wave still
	# finds the body and every other group consumer (LOD sleep, the MP relay)
	# stays intact.
	#
	# IT IS A ROW KEY AND NOT A NAME TEST, deliberately. `spec.get(..., false)`
	# means every animal in the table is untouched by this line and a future
	# machine-like predator opts in by editing its row — species are data, not
	# subclasses (CLAUDE.md). Testing `species == "hunter_robot"` here would be
	# the subclass-by-string the SPECIES table exists to avoid.
	if spec.get("stink_immune", false):
		return
	# A SLEPT croc ignores the stink too, and that is a correctness rule, not a
	# nicety: set_lod_active(false) turns physics dispatch off, so its
	# flee_time_remaining can never tick down. It would hold is_fleeing until it
	# woke and then flee for the FULL duration — one press would leave every
	# crocodile in every loaded chunk (~1000 of them) harmless-on-wake for as
	# long as the player keeps advancing. A slept croc is > 50 m away (see
	# SIM_RADIUS in crocodile_lod_manager); no smell reaches that far anyway.
	if not lod_active:
		return
	# NOT guarded on remote_driven, and that is deliberate — do not "fix" it. A
	# remote-driven crocodile takes its motion (and its flee flag) from the
	# master's samples, so setting the flag here is harmless: the next sample
	# overwrites it. Meanwhile the master, whose own crocodiles are never
	# remote-driven, gets the real flee from this very call — see
	# MpManager.request_croc_flee.
	is_fleeing = true
	# A flee trigger/refresh must never shorten an active flee already in progress (Codex P2).
	flee_time_remaining = maxf(flee_time_remaining, duration)
	flee_source = source
	flee_tracks_player = tracks_player
	is_chasing = false
	spot_clock = 0.0
	if _spot_label != null:
		_spot_label.visible = false


func _wander(delta: float) -> void:
	"""
	Organic wandering: instead of snapping to a brand-new random direction and
	walking dead-straight, the heading drifts continuously by small random
	amounts (a bounded random walk), producing smooth, curved meandering. Every
	so often we apply a bigger course correction and occasionally pause to sniff.
	"""
	# Continuous gentle steering — this is what curves the path.
	wander_heading += rng.randf_range(-1.0, 1.0) * spec["wander_turn_rate"] * delta

	# Periodic bigger nudges / occasional pauses to look around.
	time_since_direction_change += delta
	if time_since_direction_change >= spec["direction_change_interval"]:
		time_since_direction_change = 0.0
		wander_heading += rng.randf_range(-PI / 2.0, PI / 2.0)
		if rng.randf() < spec["sniff_pause_chance"]:
			is_paused = true
			pause_time_remaining = spec["pause_duration"]

	# Convert heading to a direction vector on the XZ plane.
	movement_direction = Vector3(sin(wander_heading), 0.0, cos(wander_heading))


func _wander_speed(delta: float) -> float:
	"""
	A gently varying wander speed so crocodiles ease between strolling and a
	brisker walk instead of gliding at one constant velocity.
	"""
	speed_phase += delta * spec["speed_variation_freq"]
	var t := 0.5 * (sin(speed_phase + instance_phase) + 1.0)  # 0..1
	return move_speed_instance * lerpf(spec["min_wander_speed_factor"], 1.0, t)


func _avoid_obstacles() -> bool:
	"""
	Steer around blocks so the crocodile never drives its snout into one.

	We cast a short feeler ray straight ahead; if it hits a block, we probe to the
	left and right and turn toward whichever side is open (or turn hard if both are
	blocked, e.g. facing into a wall). Because the look-ahead is longer than the
	model, the crocodile starts turning before its nose can reach the block.

	The player, other crocodiles and the flat ground are NOT treated as obstacles,
	so this never stops a crocodile from reaching the player.

	@return true if a block was sensed and we steered around it this frame.
	"""
	if movement_direction.length() < 0.1:
		return false

	var space := get_world_3d().direct_space_state
	if not space:
		return false

	# Both probe dimensions SCALE WITH THE BODY (inert at scale 1, i.e. for every
	# regular crocodile). _ready() sets `scale = ONE * boss_scale` for a boss, so a
	# 9x boss's capsule alone reaches 0.7 * 9 = 6.3 m ahead of its origin — past the
	# fixed 3 m world-space feeler, leaving avoidance completely dead from boss 2 on
	# (useful reach 0.38 m at 3.75x, then 0, 0, 0 …) against a body that is also 9x
	# wider and needs MORE clearance. The height likewise has to rise, or a big boss
	# samples the ground at its own feet instead of a block's side wall.
	var probe_scale := maxf(scale.x, scale.z)
	var origin := global_position + Vector3(0.0, spec["avoid_feeler_height"] * scale.y, 0.0)
	var reach: float = spec["avoid_look_ahead"] * probe_scale
	var forward := movement_direction.normalized()

	# Nothing straight ahead? Then there's nothing to steer around.
	if not _feeler_blocked(space, origin, forward, reach):
		return false

	# Probe both sides and pick a clear way around.
	var left_dir := forward.rotated(Vector3.UP, spec["avoid_feeler_angle"])
	var right_dir := forward.rotated(Vector3.UP, -spec["avoid_feeler_angle"])
	var left_blocked := _feeler_blocked(space, origin, left_dir, reach)
	var right_blocked := _feeler_blocked(space, origin, right_dir, reach)

	var steer_dir: Vector3
	if left_blocked and right_blocked:
		# Boxed in (running into a wall) — turn hard to one side to escape.
		steer_dir = forward.rotated(Vector3.UP, PI / 2.0)
	elif right_blocked:
		steer_dir = left_dir
	elif left_blocked:
		steer_dir = right_dir
	else:
		# A single block dead ahead with both sides open — ease around it.
		steer_dir = left_dir

	movement_direction = steer_dir.normalized()
	# Keep the wander heading in sync so a wandering crocodile holds the new
	# course after it clears the block instead of curving straight back into it.
	wander_heading = atan2(movement_direction.x, movement_direction.z)
	return true


func _feeler_blocked(space: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3, reach: float) -> bool:
	"""
	Cast one feeler ray and report whether a *block* sits within `reach`.
	The player, other crocodiles and the (horizontal) ground are not blocks.

	@param space: The physics space to query
	@param origin: Ray start, already lifted to feeler height
	@param dir: Direction to probe (need not be normalized)
	@param reach: Ray length — `spec.avoid_look_ahead` scaled by the body (see _avoid_obstacles)
	@return true if the ray hits something we should steer around
	"""
	# OUR OWN MASK, not `create()`'s default of all 32 layers. Fauna roots are
	# `AnimatableBody3D` bodies on layer 3 which crocodiles deliberately do not
	# mask (mask 3 = layers 1+2), and they are in no group, so the group test
	# below cannot reject them. Ordinary crocodiles are saved only by geometry —
	# the feeler sits at 0.28-0.43 m, under every deck — but `_avoid_obstacles`
	# scales both probe dimensions by the body, so a boss at scale >= 3.375 lifts
	# it to 1.1 m+ and starts swerving away from, and cutting speed for, a pack
	# beast it cannot touch.
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + dir.normalized() * reach, collision_mask
	)
	query.exclude = [get_rid()]  # never sense our own collider
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return false

	var collider = hit.get("collider")
	if collider == null:
		return false
	# Ignore the things we don't want to swerve around.
	if collider.is_in_group("player") or collider.is_in_group("crocodile"):
		return false
	return true


# ============================================================================
# LOD (SIMULATION LEVEL-OF-DETAIL)
# ============================================================================

func set_lod_active(active: bool) -> void:
	"""
	Wake (active = true) or sleep (active = false) this crocodile's simulation.
	Called by the central CrocodileLODManager only when the awake/asleep decision
	actually changes, so the transition work below runs at most once per change.

	What actually keeps a sleeping crocodile from harming the player is that its
	physics step never runs: set_physics_process(false) below stops the engine from
	dispatching _physics_process at all, which means the crocodile never runs
	move_and_slide nor _handle_collisions — and _handle_collisions (reading
	get_slide_collision()) is the ONLY code path that calls player.reset_position().
	So a slept crocodile is harmless; no contact damage can occur.

	Why set_physics_process instead of relying only on the early-return inside
	_physics_process? With ~460 slept crocodiles, even a cheap-return still costs
	~460 script dispatches (engine→GDScript call overhead) every physics tick.
	Disabling the callback removes those dispatches entirely; the early-return
	stays in _physics_process purely as a backstop in case something else ever
	re-enables processing on a slept crocodile.

	We still zero velocity here (not just in the backstop) so the freeze is
	immediate — the body holds exactly its current spot from this frame on.
	"""
	# No-op if nothing actually changed (defensive; the manager already guards this).
	if active == lod_active:
		return

	# REFUSE to sleep a crocodile that has not landed yet. The terrain spawns crocs
	# ABOVE the ground (local y 0.5 on the ground, +0.6 over a platform) and lets
	# gravity settle them, but every chunk outside the synchronous ring is built
	# ≥100 m away — so the manager's next scan (≤ SCAN_INTERVAL 0.11 s later, ~0.06 m
	# of fall) would sleep them mid-air, and sleeping stops gravity FOREVER. The
	# whole pack would hang ~0.44 m up until the player closed to SIM_RADIUS, and
	# the draw cull (60 m) is deliberately WIDER than the sleep radius (45/50 m), so
	# the floaters would be visibly drawn. The manager re-reads `lod_active` every
	# scan and re-issues the call while the states disagree, so refusing here just
	# costs a few extra calls until the body is on the floor.
	if not active and not is_on_floor():
		return

	# ...AND REFUSE TO SLEEP A BODY THAT IS ON AN ERRAND, the same way and for the
	# same shape of reason (bead godot-test1-3iy.22). A storey is ~78 m across and
	# SIM_RADIUS is 45, so the guard the far plate lures is usually asleep when the
	# plate is pressed — and a sleeper runs no `_physics_process`, so it would
	# neither walk nor (`MpCrocSync.send_croc_sync` skips sleepers) travel to
	# anybody else's screen. The window is bounded by the lure itself (one body,
	# one walk-hold-return) and an awake body syncs normally, which is why this is
	# a refusal here rather than a second slept-step path beside `advance_tracking`.
	if not active and is_investigating:
		return

	# ...AND WHILE THE CROWD-CONFUSION COOLDOWN TICKS (bead 8gw.16). Same shape:
	# a just-confused hunter that would otherwise sleep would freeze its 6 s guard
	# indefinitely, because _physics_process never ticks it while slept.
	if not active and _crowd_confusion_cooldown > 0.0:
		return

	lod_active = active

	# Stop (or resume) the per-tick physics callback itself. Asleep → the engine
	# never calls _physics_process on this crocodile, saving the script dispatch.
	set_physics_process(active)
	if not active:
		velocity = Vector3.ZERO
		# ...and any telegraph, for exactly the reason the flee state is dropped
		# below: `spot_clock` only ever counts in _physics_process, which we just
		# switched off, so a body slept mid-beat would hold a frozen `?` over its
		# head until the player walked back inside SIM_RADIUS — and the draw cull
		# is wider than the sleep radius, so it would be visible the whole time.
		spot_clock = 0.0
		if _spot_label != null:
			_spot_label.visible = false
		# Drop any flee state on the way down. flee_time_remaining is decremented
		# ONLY in _physics_process, which we just switched off — so a croc slept
		# mid-flee would hold is_fleeing (and stay harmless on contact) for its
		# whole sleep, which is the exact failure flee_from's own slept-croc guard
		# exists to prevent, reached from the other direction: Stink Wave, then Air
		# Rush across the 50 m sleep boundary.
		is_fleeing = false
		flee_time_remaining = 0.0


# ============================================================================
# MULTIPLAYER SYNC (phase 5)
# ============================================================================

static func croc_id_for(node_name: String) -> int:
	"""
	This crocodile's room-wide id, derived from its NODE NAME alone.

	Every crocodile the terrain spawns is named deterministically BEFORE add_child
	from data that is a pure function of chunk coords + run_seed
	(`Crocodile_<cx>_<cy>_<index>`, `PatrolCrocodile_<cx>_<cy>_<count>`,
	`BossCrocodile_<index>`), so two peers sharing a run_seed put the SAME
	crocodile, under the SAME name, in the same place. The name therefore
	identifies it across the room — which is why not one line of
	endless_terrain.gd has to change. Exactly the reasoning, and exactly the
	shape, of Coin.id_at().

	ponytail: two ceilings, both cosmetic by construction. (1) A crocodile spawned
	OUTSIDE the terrain (the standalone piglet_crocodile.tscn, or a future
	spawner) has a non-unique name and could collide with another's id; it never
	happens in a room, and the failure mode is one crocodile following another's
	transform, not a crash. (2) String.hash() is 32-bit, so a collision across the
	~1000 loaded crocodiles is a ~1e-4 birthday chance per run. The upgrade path
	for both is the coin id's: thread an explicit (chunk, index) id out of the
	spawners.

	SIGN-EXTENDED TO int32, AND THAT IS LOAD-BEARING, NOT TIDINESS. String.hash()
	is an unsigned 32-bit value widened into a GDScript int, so it runs to 2^32-1
	— but mp_manager ships these ids in the sync packet's PackedInt32Array ("i"),
	which stores int32_t. Every id above INT32_MAX therefore WRAPPED NEGATIVE in
	transit, missed the receiver's `_synced_crocs` lookup (whose keys were the
	unwrapped values), and landed on the deliberately-silent "this peer has not
	generated that chunk" path. Measured over the real name scheme, 43% of
	crocodiles hash above INT32_MAX — so nearly half the pack was silently never
	synced, fell back to local simulation after CROC_SYNC_TIMEOUT and drifted, in
	the one code path engineered to say nothing. Sign-extending here (rather than
	widening the packet) keeps sender, receiver, `_dead_crocs` and `_synced_crocs`
	all naming a crocodile by the same number, at zero bandwidth.
	"""
	var h: int = node_name.hash()
	return h - 4294967296 if h > 2147483647 else h


func croc_id() -> int:
	"""This crocodile's room-wide id. Valid from _ready on — the name is latched
	once there and never recomputed (see _croc_id), so nothing that touches the
	node later can quietly rename this crocodile mid-run."""
	return _croc_id


func set_remote_state(pos: Vector3, yaw: float, flags: int) -> void:
	"""
	Overlay the MASTER's simulation of this crocodile onto this local body.

	The sync layer never creates, re-parents or frees a crocodile: crocs stay
	chunk-parented, per-peer, deterministic and freed on chunk unload exactly as
	in single player. This only overlays DYNAMIC state onto a node that already
	exists here, matched by croc_id(); a sample naming a crocodile this peer has
	not generated is dropped by the manager before it ever reaches this method.

	This is the ONLY place remote_driven is turned on. The first sample — and any
	sample further than CROC_TELEPORT_DISTANCE from where the body currently
	stands — SNAPS; everything else is eased in _tick_remote, so 10 Hz samples
	read as smooth motion at 60 fps.

	@param flags: the state byte, decoded with MpManager.CROC_FLAG_* so the
	    encoder and this decoder cannot drift. Biting goes through _start_bite()
	    rather than a raw assignment, so the chomp gets its usual timer and the
	    local animation clears it — a flag that only ever says "started".
	"""
	# A body already dying (squash_and_die leaves the group and stops physics) is
	# never driven again — the sample forcing processing back on below would
	# otherwise walk a corpse through its own squash tween, still solid and still
	# able to bite. The manager erases a killed id from its cache, so this only
	# catches a sample that was already in flight.
	if not is_in_group("crocodile"):
		return

	# ...AND ANY ERRAND THIS PEER HAD STARTED IS OVER, because the master owns this
	# body from here on. `investigate_point()` refuses a remote-driven body, but a
	# lure pressed on THIS screen a moment before the master's first sample arrived
	# is already running — and `_tick_remote()` returns above `_investigate_move()`,
	# so it could never finish, never hand its grown leash back, and would resume
	# a stale walk if authority ever came home. Cleared where authority changes,
	# which is the one place that knows. Also clears crowd latch/cooldown so a
	# locally-confused hunter that becomes remote does not keep a frozen cooldown
	# and refuse sleep forever (finding #6).
	if is_investigating:
		_end_investigation()
	_crowd_errand = false
	_crowd_confusion_cooldown = 0.0

	_remote_pos = pos
	_remote_yaw = fposmod(yaw, TAU)

	# THE ACQUISITION EDGE, RE-DETECTED FROM THE WIRE. Read before the write, so a
	# false -> true transition in the master's own `is_chasing` announces itself
	# here exactly as it announced itself there. Without this the boss growl, the
	# viper hiss and the hunter's lock-on ping are audible ONLY to whoever is
	# simulating the body: this method is reached from `_tick_remote()`, which sits
	# at the top of `_physics_process` and returns before the chase logic that owns
	# the local edge, so on every other screen those cues simply never fired.
	#
	# It costs no protocol. CROC_FLAG_CHASING has been on the wire and restored
	# below since the sync shipped — the edge was always there to be read, and this
	# is the "the acquisition cue is the same answer from the other end" that
	# CROC_FLAG_BURROWED's note in mp_codec.gd rules out a sixth bit for.
	#
	# Fires only on the transition, so a peer receiving 10 samples a second of a
	# crocodile that is still chasing hears one cue per engagement, not ten a
	# second — the identical guarantee the local edge gives.
	var was_chasing: bool = is_chasing
	is_chasing = (flags & MpCodec.CROC_FLAG_CHASING) != 0
	if is_chasing and not was_chasing:
		_announce_acquisition()
	is_fleeing = (flags & MpCodec.CROC_FLAG_FLEEING) != 0
	is_paused = (flags & MpCodec.CROC_FLAG_PAUSED) != 0
	# The burrow rides the byte rather than being re-derived here, and the reason
	# is in CROC_FLAG_BURROWED's own note: it is the one part of the pose the
	# other bits do not imply, because the behaviour dispatch that decides it is
	# skipped for the whole of a pause or a flee.
	is_burrowed = (flags & MpCodec.CROC_FLAG_BURROWED) != 0
	if (flags & MpCodec.CROC_FLAG_BITING) != 0:
		_start_bite()

	if not _has_remote_sample or global_position.distance_to(pos) > CROC_TELEPORT_DISTANCE:
		global_position = pos
		rotation.y = _remote_yaw
		velocity = Vector3.ZERO

	_has_remote_sample = true
	remote_driven = true

	# TURN THE PHYSICS CALLBACK BACK ON. A crocodile the LOD manager had already
	# put to sleep has had set_physics_process(false) called on it, so
	# _tick_remote() — which lives at the top of _physics_process — would never
	# run: the body would jump CROC_TELEPORT_DISTANCE at a time on the snap
	# branch above, never animate, and (the sharp part) never reach
	# move_and_slide/_handle_collisions, so it would be neither solid nor able to
	# bite. That last one breaks the rule this whole phase is specified against —
	# the BITTEN peer detects its own bite locally.
	#
	# It is not an edge case: the master syncs every crocodile within
	# CROC_SYNC_RADIUS (55 m) of a peer, while that peer's own LOD sleeps anything
	# past SIM_RADIUS + HYSTERESIS_MARGIN (50 m), so the 50–55 m band is exactly
	# this. `lod_active` is deliberately left alone — the sync layer owns the
	# processing switch only while it is driving, and clear_remote_drive() hands
	# it straight back to whatever the LOD manager last decided.
	set_physics_process(true)


func clear_remote_drive() -> void:
	"""
	Hand this crocodile back to its own local AI, from wherever the body now
	stands. Called when the master's samples stop arriving (the sync timeout — the
	master is too far away to have this chunk loaded, or the room ended) and when
	THIS peer is promoted to master.

	Promotion is seamless precisely because a synced crocodile is a real local
	node holding the master's last known transform: dropping the flag resumes
	simulation from that exact spot, so the whole pack is a hot standby replica
	for free.
	"""
	if not remote_driven:
		return
	remote_driven = false
	_has_remote_sample = false
	# Same guard, same reason, as set_remote_state(): a body already dying
	# (squash_and_die left the group and stopped physics) must not have physics
	# handed back to it. It can still be remote-driven here — a local crush runs
	# when request_croc_kill() could not reach the master, so no `dead` broadcast
	# erases us from the manager's cache — and the set_physics_process below would
	# then walk the corpse through its own squash tween under the FULL LOCAL AI,
	# solid and able to bite.
	if not is_in_group("crocodile"):
		return
	velocity = Vector3.ZERO
	# Hand the physics switch back to the LOD manager's last decision. While we
	# were remote-driven set_remote_state() forced processing ON regardless of
	# `lod_active` (see there); leaving it on for a crocodile the manager thinks is
	# asleep would silently un-sleep it — and it would not sleep again, because
	# set_lod_active() no-ops when the state already matches.
	set_physics_process(lod_active)


func squash_and_die() -> void:
	"""
	Die the giant-Teibi death: physics stops, a dust puff pops, a crunch plays,
	the nearby player's camera gets a tiny kick, and the body squashes flat before
	freeing itself.

	Public because in a multiplayer room the crush is arbitrated by the master, so
	this has to be runnable from `MpCrocSync.apply_dead()` on a peer where nobody
	touched this crocodile at all — a crush must READ as a crush on every screen,
	not as a crocodile blinking out. Idempotent: a second call finds us already out
	of the "crocodile" group and returns.
	"""
	if not is_in_group("crocodile"):
		return
	print("🐊 Squashed by a giant!")
	# Guard re-entry FIRST: stop physics and leave the "crocodile" group so
	# the dying body can't crush-trigger a second time (or be found by the
	# stink wave / danger telegraph / croc sync) during the short squash tween.
	set_physics_process(false)
	remove_from_group("crocodile")
	# Dust puff at the body, parented to the croc's PARENT (the chunk) so it
	# outlives this node — the same self-freeing wave pattern as the coin pop.
	var fx_parent := get_parent()
	if fx_parent:
		var fx := MeshInstance3D.new()
		fx.set_script(preload("res://scripts/ability_effect.gd"))
		fx_parent.add_child(fx)
		fx.global_position = global_position
		fx.setup(Color(0.75, 0.7, 0.6, 0.5), 1.8, 0.3)
	# Crunch sound + a small nudge on the player's camera shake (both null-safe,
	# matching the project's group-lookup convention).
	var sound_manager := get_tree().get_first_node_in_group("sound_manager")
	if sound_manager and sound_manager.has_method("play_crunch"):
		sound_manager.play_crunch()
	# The shake is RANGE-GATED, which it did not have to be when this only ever ran
	# on the crushing player's own screen: in a room a teammate's kill three chunks
	# away arrives here as a "dead" packet, and jolting the camera for a crocodile
	# nobody can see reads as a bug. Contact crushes are metres away, so the local
	# case is unchanged.
	var player := get_tree().get_first_node_in_group("player")
	if player is Node3D and "shake_amount" in player \
			and global_position.distance_to((player as Node3D).global_position) <= CRUSH_SHAKE_RADIUS:
		player.shake_amount = maxf(player.shake_amount, 0.15)
	# Squash flat, then free — the TWEEN owns the queue_free. A tween dies
	# with its node, so a chunk unloading mid-squash frees us safely anyway.
	var squash := create_tween()
	squash.tween_property(self, "scale:y", scale.y * 0.15, 0.12)
	squash.tween_callback(queue_free)


func _tick_remote(delta: float) -> void:
	"""
	Drive the body toward the master's latest sample for one physics frame.

	move_and_slide() here is DELIBERATE, not incidental: it is what keeps a synced
	crocodile SOLID to the player, and what makes the BITTEN peer detect its own
	bite locally through _handle_collisions — which is the bite rule this whole
	phase is specified against ("the bite is decided by the peer being bitten, on
	its own machine"). Never replace it with a direct global_position write.
	"""
	# Velocity that closes the gap over one SAMPLE period, not one frame — see
	# CROC_REMOTE_INTERP_RATE for why the frame delta is the wrong divisor.
	# Clamped so one bad-but-finite sample cannot launch the body across the map.
	var wanted: Vector3 = (_remote_pos - global_position) * CROC_REMOTE_INTERP_RATE
	if wanted.length() > CROC_REMOTE_MAX_SPEED:
		wanted = wanted.normalized() * CROC_REMOTE_MAX_SPEED
	velocity = wanted

	rotation.y = lerp_angle(rotation.y, _remote_yaw, minf(delta * CROC_REMOTE_TURN_RATE, 1.0))

	move_and_slide()
	# GATED ON is_paused, exactly as the local path gates on `was_paused`. The
	# pause IS _pause_and_change_direction's post-bite recovery window, and the
	# master ships it in the sample's CROC_FLAG_PAUSED bit precisely so every peer
	# knows this crocodile is standing down. Ungated, a synced crocodile kept
	# re-triggering _on_player_collision throughout a pause the master treats as
	# harmless — so the peer it had just bitten could be bitten again the instant
	# its respawn i-frames lapsed, i.e. bites were strictly harsher for everyone
	# who is not the master, which is the opposite of what the sync is for.
	if not is_paused:
		_handle_collisions()

	# Animate from the speed we actually moved at, exactly like the local path.
	_animate_body(delta)


# ============================================================================
# BOSS SETUP
# ============================================================================

func setup_as_boss(body_scale: float) -> void:
	"""
	Mark this crocodile as a road-guardian BOSS. CALL-ORDER CONTRACT: the terrain
	must call this on the fresh instance BEFORE add_child() — _ready() branches on
	these flags (skipping the random speed/size rolls and applying the scale), so
	setting them after the node enters the tree would be too late.

	@param body_scale: Uniform body scale from the terrain's deterministic
	    size schedule (3.75x and up — always bigger than any regular croc's roll)
	"""
	is_boss = true
	boss_scale = body_scale


func setup_roll_seed(seed_value: int) -> void:
	"""
	Hand this crocodile the deterministic seed for its per-instance speed/size
	rolls. CALL-ORDER CONTRACT, exactly like setup_as_boss above: the terrain must
	call this on the fresh instance BEFORE add_child(), because _ready() is where
	the rolls happen — seeding after the node enters the tree would be too late and
	the crocodile would already have randomize()d itself.

	Bosses may be given a seed too; it simply goes unused, since the is_boss branch
	in _ready() takes no size/speed roll at all.

	@param seed_value: Seed from the terrain's independent croc-roll hash stream
	    (see endless_terrain._croc_roll_seed)
	"""
	roll_seed = seed_value
	has_roll_seed = true


# ============================================================================
# PLATFORM CONFINEMENT (patrolling crocodiles)
# ============================================================================

func set_confinement(center: Vector3, half: Vector2) -> void:
	"""
	Pin this crocodile to a platform so it patrols but never walks off. Called by
	the terrain right after spawning an elevated "patrol" crocodile.

	@param center: World-space centre of the platform (its surface height in .y)
	@param half: Half-extents of the platform on world X (.x) and world Z (.y)
	"""
	is_confined = true
	confine_center = center
	confine_half = half


func _steer_within_platform() -> void:
	"""
	Turn a patrol crocodile back toward the platform centre as it nears an edge,
	so it paces the surface instead of strolling off it.
	"""
	var off := global_position - confine_center
	var steer := Vector3.ZERO

	if off.x > confine_half.x - CONFINE_MARGIN:
		steer.x = -1.0
	elif off.x < -confine_half.x + CONFINE_MARGIN:
		steer.x = 1.0

	if off.z > confine_half.y - CONFINE_MARGIN:
		steer.z = -1.0
	elif off.z < -confine_half.y + CONFINE_MARGIN:
		steer.z = 1.0

	if steer != Vector3.ZERO:
		movement_direction = steer.normalized()
		wander_heading = atan2(movement_direction.x, movement_direction.z)


func _clamp_to_platform() -> void:
	"""
	Hard backstop: keep the crocodile's position inside the platform box. If it
	somehow reached the edge, pull it back and kill the outward velocity.
	"""
	var off := global_position - confine_center
	var clamped_x := clampf(off.x, -confine_half.x, confine_half.x)
	var clamped_z := clampf(off.z, -confine_half.y, confine_half.y)

	if clamped_x != off.x or clamped_z != off.z:
		global_position.x = confine_center.x + clamped_x
		global_position.z = confine_center.z + clamped_z
		velocity.x = 0.0
		velocity.z = 0.0


# ============================================================================
# BOSS TERRITORY (the leash)
# ============================================================================
#
# THE SEAM. `home_position` + `territory_radius()` + `in_territory()` is the one
# place the zone is described, and every question about it — the chase gate, the
# steer, the hard clamp, the selfcheck — asks through here rather than comparing
# a radius for itself. That is deliberate, and it is the extensibility the owner
# asked for: the area is meant to grow gameplay of its own later ("later we will
# invent some game mechanics there"), and when it does it hangs off these two
# functions instead of chasing scattered copies of `distance_to(home) < R`.
# No zone mechanics exist yet, and none should be added here speculatively.

func territory_radius() -> float:
	"""
	How far from `home_position` this boss may roam. A plain accessor today — it
	is the seam a per-boss or per-species radius would arrive through, which is
	why the three callers below never read the const directly.
	"""
	return BOSS_TERRITORY_RADIUS


func in_territory(pos: Vector3) -> bool:
	"""
	Is `pos` inside this boss's territory?

	Measured on XZ only, because the world is flat at y = 0 by invariant and the
	quarry's y is the one axis that moves (a jump). Folding height into the radius
	would quietly shrink the leash for an airborne player, which is a rule nobody
	asked for. Meaningless on a non-boss (home_position is never captured there);
	every caller is behind an `is_boss` gate.
	"""
	var off := Vector2(pos.x - home_position.x, pos.z - home_position.z)
	return off.length() <= territory_radius()


func _steer_within_territory() -> void:
	"""
	Keep a boss inside its circle by REMOVING the outward part of the heading it
	just chose, rather than by turning it toward home.

	The difference is the difference between a leash and a cage. Turning
	dead-inward at the boundary means a quarry standing in the outer few metres of
	the territory can never be reached: the boss veers home, re-acquires, veers
	out, and oscillates in the margin band forever. Cancelling only the outward
	component lets it slide ALONG the boundary and keep whatever inward or
	tangential intent the chase gave it — it still hunts you at the fence, it just
	cannot follow you through it.
	"""
	var off := Vector2(global_position.x - home_position.x, global_position.z - home_position.z)
	if off.length() <= territory_radius() - BOSS_TERRITORY_MARGIN:
		return  # Deep inside, which is most of the time; the leash is invisible here.

	var outward := off.normalized()
	var dir := Vector2(movement_direction.x, movement_direction.z)
	var outward_part := dir.dot(outward)
	if outward_part <= 0.0:
		return  # Already heading back in — leave the chase/wander heading alone.

	dir -= outward * outward_part
	if dir.length() < 0.01:
		# Aimed dead at the fence, so there is no tangent left to slide along.
		dir = -outward
	dir = dir.normalized()
	movement_direction = Vector3(dir.x, 0.0, dir.y)
	wander_heading = atan2(movement_direction.x, movement_direction.z)


func _clamp_to_territory() -> void:
	"""
	Hard backstop: pull a boss back onto its territory boundary and kill the
	outward velocity. Runs AFTER move_and_slide, so the position anything else can
	observe is always inside the circle — the boundary is hard, with no epsilon.
	"""
	var off := Vector2(global_position.x - home_position.x, global_position.z - home_position.z)
	var radius := territory_radius()
	if off.length() <= radius:
		return

	off = off.normalized() * radius
	global_position.x = home_position.x + off.x
	global_position.z = home_position.z + off.y
	velocity.x = 0.0
	velocity.z = 0.0


# ============================================================================
# AI BEHAVIOR METHODS
# ============================================================================

func _choose_new_direction() -> void:
	"""Pick a fresh random heading to wander toward."""
	# Random angle in radians (TAU = 2*PI = full circle)
	wander_heading = rng.randf_range(0.0, TAU)

	# Convert to a direction vector on the XZ plane (Y=0 for ground movement)
	movement_direction = Vector3(sin(wander_heading), 0.0, cos(wander_heading))

	# Reset timer
	time_since_direction_change = 0.0


func _pause_and_change_direction() -> void:
	"""Pause briefly, then choose a new direction."""
	is_paused = true
	pause_time_remaining = spec["pause_duration"]
	_choose_new_direction()


# ============================================================================
# BODY ANIMATION
# ============================================================================

func _animate_body(delta: float) -> void:
	"""
	Procedural body animation. The crocodile model is a single static mesh with
	no rigged limbs, so — like the player animates its limbs with sine waves — we
	animate the whole `Model` node: a side-to-side waddle, a vertical bob, a slow
	body "snake", and a forward lean while hunting. The stride speeds up the
	faster the crocodile moves and freezes (to a gentle breath) when it stops.
	"""
	if not model:
		return

	# Ease the river submersion FIRST, and above the bite branch: it moves the rest
	# height both animation branches compose on, so a crocodile that chomps you
	# from the water stays in the water for the whole chomp.
	_tick_river_sink(delta)

	animation_time += delta

	# A bite overrides the normal locomotion animation while it plays.
	if is_biting:
		_animate_bite(delta)
		return

	# How fast are we actually moving along the ground? (0 = standing still)
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	# The divisor is the species' resting pace, and the AMBUSHER's is 0.0 — a
	# buried viper does not stroll, so its row says so with a zero (see
	# SPECIES.sand_viper.move_speed). Floored, because 0.0 / 0.0 is NAN and a NAN
	# stride phase bakes a NAN basis into the model for the rest of its life. The
	# floor only ever bites on that one row, and there it is exactly right: for an
	# animal whose resting pace is zero, ANY motion at all is full effort, which
	# is what a strike should look like.
	var move_factor := clampf(horizontal_speed / maxf(spec["move_speed"], 0.01), 0.0, 1.6)

	# Advance the stride phase faster the quicker we move.
	stride_phase += delta * spec["stride_frequency"] * move_factor

	# Waddle (roll about the forward axis) + vertical bob (twice the stride rate).
	var roll: float = sin(stride_phase) * spec["waddle_roll"] * move_factor
	var bob: float = sin(stride_phase * 2.0) * spec["bob_amount"] * move_factor

	# Slow body "snaking" — a lazy yaw sway, offset per-instance.
	var yaw_sway: float = sin(stride_phase * 0.5 + instance_phase) * spec["sway_yaw"] * move_factor

	# Lean forward while hunting; ease back to level otherwise.
	var target_pitch: float = spec["chase_pitch"] if is_chasing else 0.0
	current_pitch = lerp(current_pitch, target_pitch, delta * 6.0)

	# When basically still, replace the bob with a subtle breathing motion.
	if move_factor < 0.05:
		bob = sin(animation_time * spec["breathe_speed"]) * spec["breathe_amount"]

	# Compose the transform: first align the snout to the travel direction, then
	# layer the oscillations on top (re-applying the model's rest scale).
	#
	# scaled_LOCAL, not scaled(): `Basis.scaled(v)` is diag(v) * basis, i.e. the
	# scale lands in the PARENT's axes, after the rotation. For every model whose
	# rest scale is uniform the two are identical (a uniform scale commutes with
	# rotation), which is why this read as `scaled()` for six species and was
	# right. The green dragon is the first row whose model is stretched on ONE
	# axis (1, 1.6, 1 — see its SPECIES entry), and a parent-frame stretch applied
	# after a pitch or a roll is a SHEAR: the body leans 14 degrees into a chase
	# and gets taller in world y instead of along its own spine. scaled_local is
	# basis * from_scale(v), which stretches the model along the model's own axes
	# — a rigid stretched dragon at every angle, and byte-identical for the six
	# uniform rows. Same fix, same reason, in _animate_bite below.
	var facing := Basis(Vector3.UP, spec["model_facing_offset"])
	var oscillation := Basis.from_euler(Vector3(current_pitch, yaw_sway, roll))
	model.transform.basis = (oscillation * facing).scaled_local(model_base_scale)
	model.position.y = model_base_y + bob


func _tick_river_sink(delta: float) -> void:
	"""
	Ease the model's rest height toward "sunk" while standing in a river and back
	to dry otherwise. Called once per physics frame from the top of _animate_body,
	so both the local and the remote-driven (multiplayer) paths get it for free —
	they already share that one call.

	Grounded only, exactly like the player's `is_wading`: a crocodile mid-air over
	a river (spawn drop, a shove off a ledge) is not in the water.

	Writes ONLY `model_base_y`, never `model.position` — the animation owns that
	outright and rewrites it every frame from `model_base_y`, so this is the one
	property the two do not both touch.

	LOD: a slept crocodile has set_physics_process(false), so nothing here is
	dispatched at all — the sink costs a slept crocodile exactly zero, and its
	offset simply freezes wherever it was. On wake it eases on from there, which
	is the right answer in both directions: slept dry and woken in a river it sinks
	over the usual ~0.2 s, and slept sunk it rises the same way. There is no state
	to reconcile, because the target is recomputed from scratch every frame.
	"""
	var target_y: float = model_rest_y
	# `is_wading_at`, not `is_river_at` — the Y-AWARE question (bead
	# godot-test1-06o.2). An animal standing on a bridge deck is over the band and
	# not in it, so it must not sink through the stone it is standing on. Same one
	# rule the player and the remote avatar ask; the height compare rejects a body
	# on a deck before the noise evaluation runs, so it is cheaper too.
	if terrain and is_on_floor() and terrain.is_wading_at(global_position):
		target_y = model_rest_y - spec["river_sink_depth"]
	# THE AMBUSHER'S BURROW COMPOSES HERE rather than in a second easing of its
	# own, and "whichever target is DEEPER" is the whole composition: a viper that
	# is burrowed AND standing in a river is simply burrowed. That keeps this
	# function the single writer of `model_base_y` — the property the docstring
	# above promises the animation does not fight over — instead of two easings
	# racing for it.
	# `spec.has` rather than a bare `is_burrowed`, because on a remote-driven body
	# the flag is UNVALIDATED PEER INPUT (see set_remote_state): a hostile or
	# simply older master can set the bit on any species, and a row with no burrow
	# has no depth to read. Locally the arm only ever raises it on the ambusher,
	# so this costs one hash lookup on the frames the height is actually moving.
	if is_burrowed and spec.has("ambush_burrow_depth"):
		target_y = minf(target_y, model_rest_y - float(spec["ambush_burrow_depth"]))
	if is_equal_approx(model_base_y, target_y):
		return
	# RISING IS THE STRIKE. An ambusher surfaces four times faster than anything
	# sinks (see ambush_surface_ease_speed), and the asymmetry is the animation:
	# the strike erupts, the re-burial slides. Every other species, and this one
	# going back under, takes the ordinary sink ease. The lookup sits BELOW the
	# early-return, so it costs a settled crocodile nothing at all.
	var ease: float = spec["river_sink_ease_speed"]
	if target_y > model_base_y and spec.has("ambush_surface_ease_speed"):
		ease = spec["ambush_surface_ease_speed"]
	model_base_y = move_toward(model_base_y, target_y, ease * delta)


func _animate_bite(delta: float) -> void:
	"""
	Play the chomp: the head snaps down/up a couple of times while the body lunges
	forward (toward the player it just caught, since the crocodile keeps facing
	them while paused). The lunge eases in and back out, so the model returns
	cleanly to its rest pose as the bite ends.
	"""
	bite_timer -= delta
	if bite_timer <= 0.0:
		is_biting = false
		# Put the model back on the capsule's centreline. _animate_body only ever
		# writes position.y, so without this the last drawn lunge frame (~3.6 cm
		# of forward +Z) would stay baked into the model FOREVER — every crocodile
		# that has ever bitten drifts permanently ahead of its own collider.
		model.position = Vector3(0.0, model_base_y, 0.0)
		return

	# Progress through the bite: 0 at the start, 1 at the end.
	var p := 1.0 - clampf(bite_timer / spec["bite_duration"], 0.0, 1.0)
	# Two fast chomps (sin over two cycles) and a single forward lunge (sin over
	# half a cycle, so it pushes out then pulls back to zero).
	var chomp := sin(p * TAU * 2.0)
	var lunge: float = sin(p * PI) * spec["bite_lunge"]

	var facing := Basis(Vector3.UP, spec["model_facing_offset"])
	var snap := Basis.from_euler(Vector3(chomp * spec["bite_pitch"], 0.0, 0.0))
	# scaled_local for the reason spelled out in _animate_body: the bite is the
	# DEEPEST pitch in the game (30 degrees on the dragon), so a parent-frame
	# stretch would shear hardest exactly here.
	model.transform.basis = (snap * facing).scaled_local(model_base_scale)
	# Lunge along the body's forward axis (+Z) and lift a touch on each snap.
	model.position = Vector3(0.0, model_base_y + absf(chomp) * 0.04, lunge)


# ============================================================================
# COLLISION DETECTION
# ============================================================================

func _handle_collisions() -> void:
	"""
	Check collisions with the player.

	Crocodiles are now SOLID to one another (their collision_mask includes their own
	layer), so move_and_slide already shoves two bumping crocodiles apart on its own
	— they push past each other instead of overlapping. We therefore do NOTHING on a
	crocodile-vs-crocodile contact (the earlier eat-on-touch "cannibalism" is gone);
	the physical push is the entire behaviour, and only the player still matters here.
	"""
	# Check all collisions from move_and_slide()
	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		var collider := collision.get_collider()

		if not collider:
			continue

		# Check if we hit the player
		if collider.is_in_group("player"):
			_on_player_collision(collider)
			return # Prioritize player collision


func _start_bite() -> void:
	"""Begin the chomp animation (ignored if one is already playing)."""
	if is_biting:
		return
	is_biting = true
	bite_timer = spec["bite_duration"]


func _on_player_collision(player: Node) -> void:
	"""
	Handle collision with the player. Normally FATAL (chomp, then send them back),
	with two exceptions tied to special abilities:
	  * Giant-form Teibi CRUSHES the crocodile on contact instead of being bitten.
	  * A crocodile fleeing Phoboman's stink is harmless and just brushes past.
	"""
	# A BOSS is bigger than even giant-form Teibi (3.75x+ vs the giant scale), so
	# giant form gets bitten like anyone else — bosses are never crushable. This
	# early check sits ABOVE the crush block so that block stays untouched.
	#
	# THE ORDERING IS THE FEATURE, AND IT IS PROVISIONAL. Immunity is a property
	# of BOSS-NESS, not of any one boss, which is the owner's rule verbatim: "yes,
	# for now all bosses immune. we will think about it later on." So every boss
	# kind added after the crocodile inherits it for free — and the day one of them
	# is meant to be killable, that is a change HERE, not a new subclass. Reorder
	# these two blocks and giant Teibi silently one-shots the game's biggest
	# threat, with no error anywhere, so boss_selfcheck pins the ordering — with a
	# non-boss negative control, because "the boss survived" is also true of a stub
	# that never crushed anything.
	# ponytail: the few bite lines below are duplicated from the normal path on
	# purpose — a shared helper would tangle this with the crush block another
	# change owns; fold them together once that settles.
	if is_boss:
		print("💀 BOSS crocodile bites the player!")
		_start_bite()
		if player.has_method("hit_by_crocodile"):
			player.hit_by_crocodile(self)
		elif player.has_method("reset_position"):
			player.reset_position()
		_pause_and_change_direction()
		return

	# Giant Teibi squashes crocodiles on contact instead of being bitten.
	# Instead of vanishing in one frame, the croc visibly dies: physics stops,
	# a dust puff pops, a crunch plays, the player's camera gets a tiny kick,
	# and the body squashes flat before freeing itself.
	#
	# `crush_immune` is the ARMOURED half of the same idea the is_boss block
	# above states: a chassis is not flesh, so stepping on it does not pop it. It
	# is a CONDITION on this block rather than a third early return, precisely so
	# the block ORDER the comment above calls the feature is left alone — an
	# immune body simply falls through to the ordinary bite path below and grabs
	# the giant like any other quarry. Row data, defaulting to false, for the
	# same reason as `stink_immune` in flee_from(): a future armoured predator
	# opts in with a row edit and no code change.
	if player.has_method("crushes_crocodiles") and player.crushes_crocodiles() \
			and not spec.get("crush_immune", false):
		# In a ROOM the kill belongs to the master, not to whichever screen it
		# happened on: it has to free the SAME crocodile on every peer. The manager
		# answers true when it is in a room and has relayed the request, and we then
		# return WITHOUT squashing — the master's kill broadcast frees this body
		# everywhere, including here. Offline, or with no manager in the scene, it
		# answers false and the squash below runs byte-for-byte unchanged.
		var now_msec: int = Time.get_ticks_msec()
		if _kill_requested_msec >= 0 and now_msec - _kill_requested_msec < KILL_RETRY_MSEC:
			return  # Already asked; waiting on the master's ruling. See the var.
		var mp := get_tree().get_first_node_in_group("mp")
		if mp and mp.has_method("request_croc_kill") and mp.request_croc_kill(croc_id()):
			_kill_requested_msec = now_msec
			return
		squash_and_die()
		return

	# While fleeing Phoboman's stink, crocodiles can't bring themselves to bite.
	if is_fleeing:
		return

	print("💀 Piglet Crocodile bites the player!")

	# Snap at the player so the hit reads clearly.
	_start_bite()

	# Tell the player it was bitten, AND WHO BIT IT. hit_by_crocodile() plays the
	# red flash / camera shake / brief freeze and then respawns; older saves
	# without it fall back to a plain reset.
	#
	# `self` rather than nothing, at BOTH bite sites in this function, because the
	# damage verb is one verb and the argument is how it learns what kind of
	# contact this was: `_is_hunter_grab()` in player_controller reads the
	# attacker's `spec["behavior"]`, so a hunter's grab takes the active HERO and
	# an animal's bite takes the ordinary predator arithmetic. Passed
	# unconditionally rather than only from the hunt branch below, so the fact
	# "the player knows who hit it" is a property of this function rather than of
	# one species — a boss, a crocodile and a viper all answer `false` to that
	# test exactly as `null` did, which capture_selfcheck check 2 pins.
	#
	# Without it `attacker` is null, `_is_hunter_grab` answers false, and the
	# whole systemic-capture mechanic (PR #120) is unreachable code.
	if player.has_method("hit_by_crocodile"):
		player.hit_by_crocodile(self)
	elif player.has_method("reset_position"):
		player.reset_position()
	else:
		# Fallback: move player up and away
		if player is Node3D:
			player.global_position = Vector3(0, 2, 0)

	# RETRIEVAL ATTEMPT LOGGED — the hunt arm's post-contact half, and it fires
	# AFTER the hit above has already been paid in full. Nothing on this path is
	# a pulled punch: a hunter's grab costs exactly what a crocodile's bite costs,
	# through the same `hit_by_crocodile` call. What the disengage buys is PACING
	# — the unit backs off to its standoff ring for `hunt_disengage_time` instead
	# of standing on the respawn point re-chomping, and a second grab has to earn
	# a fresh telegraph first.
	#
	# Keyed on the BEHAVIOUR, not on the species name, exactly like the viper's
	# hiss above the dispatch: "I stop once I have what I came for" is a trait of
	# the mechanic, so a second retrieval unit inherits it with its row. This is
	# the only place outside `_behave_hunt` that touches `_hunt_lock`, and it only
	# WRITES the clock the arm reads.
	#
	# ponytail: in a room this line fires on whichever screen the contact happened
	# on, and on a PEER that body is remote-driven — it renders the master's
	# samples and never runs the arm — so the lock it writes there is inert and the
	# master's own hunter keeps closing. That is exactly the shape
	# `_pause_and_change_direction()` below already has for every species, so the
	# ceiling is the crocodile's ceiling and not a new one; the upgrade path, if a
	# room ever needs the withdrawal to be shared, is a relayed verb, which this
	# bead was told not to add.
	if spec["behavior"] == "hunt":
		_hunt_lock["disengage"] = float(spec.get("hunt_disengage_time", 0.0))
		# And the clamp closing, on top of the ordinary bite feedback the hit
		# above already paid for — a servo sting rather than a second chomp, so a
		# grab is legible as a DIFFERENT kind of hit without being a cheaper one.
		# This runs on the machine where the contact was detected, which by the
		# sync layer's design is the machine of the player who was grabbed: the
		# one screen that must hear it. Same null-safe / has_method / _unlocked
		# routing as every other cue.
		var sm := get_tree().get_first_node_in_group("sound_manager")
		if sm and sm.has_method("play_hunter_grab"):
			sm.play_hunter_grab()

	# Pause/turn away so we don't immediately re-trigger on the same overlap.
	_pause_and_change_direction()


# ============================================================================
# UTILITY METHODS
# ============================================================================

func _to_string() -> String:
	"""Debug string representation."""
	return "PigletCrocodile(pos=%s, dir=%s, paused=%s)" % [
		global_position,
		movement_direction,
		is_paused
	]
