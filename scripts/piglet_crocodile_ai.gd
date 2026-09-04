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
## Every trait that makes one predator FEEL different from another lives in
## here: speeds, detection, wander rhythm, obstacle feelers, waddle and bite
## geometry, river sink. One const dictionary of plain dictionaries — no class
## hierarchy, no custom Resource. That is the same shape `progression.gd` uses
## for `SKILL_TREES`, for the same reason: this is data you READ, not a type you
## subclass, so a new predator is a new ENTRY here plus (at most) one new arm in
## a `match`, never a new script and never a subclass of this one.
##
## What is deliberately NOT in here matters as much as what is. Anything that is
## a GAME-WIDE contract rather than a species trait stays a top-level const
## below — `MAX_CHASE_SPEED` (the speed-lattice ceiling), the distance gradient,
## gravity, the visual cull, the multiplayer sync constants. A species may not
## opt out of the lattice: walking is caught, running escapes, at every entry.
##
## RANGED ATTACKS ARE A ROW KEY TOO. A species that throws something carries a
## `"ranged"` sub-dictionary here — the projectile's speed, hit radius,
## trajectory, minimum firing range, cap and colour — and its behaviour arm's
## whole job is one `BossProjectile.fire(muzzle, quarry_pos, get_parent(),
## spec["ranged"], self)` behind its own cooldown. The flight, the visuals, the
## lethality and the lifetime all live in `scripts/boss_projectile.gd` and are
## the same code for every shooter; what makes a bolt different from a thrown ice
## cream is entirely the numbers in this table. See that file's header for the
## required keys and for the FAIRNESS CONTRACT every set of them must satisfy —
## `scripts/projectile_selfcheck.gd` measures it over every `"ranged"` dict it
## finds in here, so a new ranged row is covered the day it lands.
##
## READ THE LATTICE AS A STATEMENT ABOUT THE TABLE, NOT ABOUT EACH ANIMAL. It
## constrains the ROW (`chase_speed` above WALK_SPEED) and the CEILING
## (MAX_CHASE_SPEED clamps the product), and it deliberately says nothing about
## an individual's roll. `speed_random_factor` exists precisely so some of them
## are slow: at the origin the crocodile's ±50% puts 41% of the pack under a
## walking player, and the sand viper's tighter ±35% puts 22% there. That is the
## pack reading as a mix of stragglers and hunters, and a review that measures
## the WORST roll against WALK_SPEED is measuring the wrong end — the promise the
## game is balanced on is the other one, that the BEST roll still cannot outrun a
## run, and MAX_CHASE_SPEED is what keeps it.
##
## Resolved ONCE per instance into `spec` (see `species` below), then read
## straight off that dictionary in the per-frame paths. A dozen hash lookups per
## crocodile per frame is nothing beside the two obstacle raycasts sitting in
## the same tick, and it is what keeps the table a table instead of thirty
## copied instance floats.
const SPECIES: Dictionary = {
	"crocodile": {
		## Which arm of the behaviour dispatch in `_update_chase_state()` this
		## species runs. "solo" is today's, and the only one implemented: wander
		## alone, chase whatever you smell, flee a stink wave. Later species add
		## their own strings here (pack, ambush, pounce, charge) together with
		## the `match` arm that reads them — a string with no arm behaves as solo.
		"behavior": "solo",

		# ----- Speed and detection -----
		## Movement speed in metres per second while wandering, and the chase
		## speed used when pursuing the player. Chase is deliberately ABOVE the
		## player's WALK_SPEED (5.0), so a merely-walking player WILL get caught —
		## escaping a chase takes running, jumping (crocodiles lose the scent when
		## you leave the ground), or a special ability. This is the game's core
		## fail pressure, and every species entry has to honour it: the lattice is
		## WALK_SPEED (5.0) < chase_speed <= MAX_CHASE_SPEED (8.5) < the slowest
		## run (9.0).
		"move_speed": 2.5,
		"chase_speed": 5.5,

		## Per-instance speed spread: each crocodile rolls ONE multiplier in
		## [1-factor, 1+factor] and applies it to BOTH its wander and chase speed,
		## so some crocodiles are clearly faster and some slower — yet a given
		## crocodile's chase always still outpaces its own stroll (the two speeds
		## never drift apart). ±50%.
		"speed_random_factor": 0.5,

		## Per-instance size spread: each crocodile rolls a uniform scale in
		## [1-factor, 1+factor] applied to the whole body (visual model + physics
		## capsule together), so the pack is a mix of smaller and larger
		## crocodiles. ±25%.
		"size_random_factor": 0.25,

		## Detection radius — distance at which this predator can "smell" the
		## player. INVARIANT for every species: must stay well below the LOD
		## manager's SIM_RADIUS (45.0), because anything that can detect the
		## player must always be awake.
		"detection_radius": 15.0,

		# ----- Organic wandering -----
		## Time between direction changes (seconds) and the pause taken when one
		## happens.
		"direction_change_interval": 4.0,
		"pause_duration": 0.5,

		## How sharply the heading drifts while wandering (radians/sec of random
		## steer). Small continuous nudges produce smooth, curved meandering
		## instead of straight lines with hard turns.
		"wander_turn_rate": 1.2,

		## How smoothly the body turns to face its heading (higher = snappier)
		"turn_smoothness": 5.0,

		## Slowest wander speed as a fraction of the instance's base speed
		"min_wander_speed_factor": 0.45,

		## How quickly wander speed ebbs and flows (radians/sec)
		"speed_variation_freq": 0.8,

		## Chance (per direction-change interval) of pausing to "sniff" around
		"sniff_pause_chance": 0.3,

		# ----- Obstacle avoidance -----
		## How far ahead (metres) the crocodile senses blocks. This is
		## deliberately longer than the visual model so the crocodile turns away
		## *before* its snout can reach a block — the snout poking into blocks is
		## exactly what this fixes (the physics capsule is much shorter than the
		## model, so move_and_slide alone stops the body but lets the longer nose
		## overlap the block).
		"avoid_look_ahead": 3.0,

		## Angle of the left/right "feeler" probes used to find a clear way
		## around (radians).
		"avoid_feeler_angle": PI / 5.0,  # 36°

		## Height above the body origin to cast the feelers from, so they sample
		## the block's side walls rather than the flat ground.
		"avoid_feeler_height": 0.3,

		## Speed multiplier while steering around a block, so the crocodile eases
		## off and curves around instead of ramming the block nose-first.
		"avoid_speed_factor": 0.5,

		# ----- Procedural body animation -----
		## Yaw applied to the model so its snout points along the travel
		## direction. The mesh is authored facing +X but the body travels +Z, so
		## we rotate -90°. If a species' model ends up facing the wrong way
		## in-editor, flip this sign in ITS entry.
		"model_facing_offset": -PI / 2.0,

		## Stride frequency at full speed (radians/sec) — drives the waddle/bob
		"stride_frequency": 9.0,

		## Side-to-side waddle roll amplitude (radians) — uses PI math so it
		## stays a constant expression (deg_to_rad() can't be used in a const)
		"waddle_roll": 9.0 * PI / 180.0,

		## Vertical bob amplitude (metres)
		"bob_amount": 0.025,

		## Slow body "snaking" yaw amplitude (radians)
		"sway_yaw": 5.0 * PI / 180.0,

		## Forward lean while hunting the player (radians)
		"chase_pitch": 10.0 * PI / 180.0,

		## Idle breathing speed/amount when standing still
		"breathe_speed": 2.0,
		"breathe_amount": 0.012,

		# ----- River submersion (VISUAL ONLY) -----
		## How far the MODEL drops, in model-local metres, while the crocodile is
		## standing in a river. The player's own wading sink (WADE_SINK_DEPTH
		## 0.35) is the pattern; the DEPTH is not, and could not be — measured off
		## the GLB, this crocodile is 1.40 m long and only 0.276 m TALL (local y
		## −0.036 .. +0.240), so the player's 0.35 would bury it, mud and all,
		## with nothing to see. Which is exactly why the depth is a SPECIES trait
		## and not a global: it is measured off one particular model.
		##
		## 0.18 leaves the top 0.060 m proud — a quarter of the 0.240 m that
		## stands above the ground plane — and shrinks the visible silhouette from
		## the full 1.40 m down to the 0.75 m of it that reaches above y = 0.18.
		## Half the crocodile's outline, at a tenth of its height: hard to pick
		## out of a river, exactly the point. There is no water MESH (a river is a
		## tint on the flat y = 0 ground plane), so what hides the rest is the
		## opaque ground itself.
		##
		## HONEST NOTE ON "just the snout": this mesh has no raised eye/nostril
		## bump. Its back is a flat plateau at y ≈ 0.239 running from the
		## shoulders (x = −0.2) to the skull (x = +0.5), and the snout TIP is the
		## LOW point of the head at y = 0.120. So no depth exists that shows the
		## nose while hiding the back — sink past 0.12 and the nose tip goes under
		## before the spine does. What 0.18 gives is the "log in the water" read:
		## a thin dark ridge of back-and-skull. Wanting a literal periscope snout
		## is a MODEL change (raise the nostrils above the back), not a constant
		## change here.
		##
		## VISUAL ONLY, AND THAT IS A HARD CONSTRAINT — same rule as the player's
		## sink: this never touches the CharacterBody3D, its CollisionShape3D, or
		## global_position. Bite range, chase mechanics and the flat-world y = 0
		## invariant are byte-identical wet or dry. A submerged crocodile is
		## exactly as dangerous as a dry one; it is only harder to SEE, and the
		## danger vignette + heartbeat still telegraph it the moment it starts
		## chasing (crocodile_lod_manager publishes that from the same scan, and
		## it reads `is_chasing`, which this does not touch).
		##
		## BOSSES NEED NO SPECIAL CASE. _ready() sets
		## `scale = Vector3.ONE * boss_scale` on the BODY, and the model is its
		## child, so this local offset is scaled by the engine: a 9x boss sinks
		## 9 × 0.18 = 1.62 m in world space and shows 9 × 0.060 = 0.54 m of ridge.
		## The submerged FRACTION is identical at every scale, which is what "a
		## proportional snout" actually means. Same free ride for the ±25%
		## size_random_factor roll on regular crocodiles.
		"river_sink_depth": 0.18,

		## Ease rate (m/s), sized so the full sink takes ~0.2 s — the player's
		## ease time, so a crocodile and the hero wading beside it settle at the
		## same visual pace. Written as depth/time rather than a bare number so
		## the derivation survives a retune of the depth above it.
		"river_sink_ease_speed": 0.18 / 0.2,

		# ----- Bite -----
		## How long the chomp animation plays when the crocodile catches the
		## player (seconds).
		"bite_duration": 0.5,

		## How far the head snaps down/up during the chomp (radians).
		"bite_pitch": 26.0 * PI / 180.0,

		## How far the body lunges forward during the bite (metres).
		"bite_lunge": 0.35,

		# ----- THE STAKE -----
		## WHAT LOSING TO THIS ANIMAL COSTS, and it is the ONLY thing it costs.
		## Owner ruling 2026-08-31: hearts are gone, and so is every game over
		## that was not "all four heroes jailed". A bite is now the caught freeze
		## plus this fraction of the RUN's coins, then a respawn in place — a tax,
		## never an ending. `player_controller._coin_setback_of()` is the single
		## site that reads this key and `_pay_coin_setback()` the single site that
		## charges it, off `own_coins` / `coins_collected` and never off the
		## lifetime count in `progression.gd`.
		##
		## IT IS A FRACTION AND NOT A BOOLEAN, so the arithmetic lives HERE, in
		## the table — the same shape `stink_immune` / `crush_immune` established
		## for "this is a property of the row, not of a species name". EVERY row
		## owes it (`enemy_spawn_selfcheck` fails one that omits it) and the
		## SPREAD is the tuning: a small ambusher bills less than a titan, and a
		## grab you escaped bills most of all. Keep every value in (0.0, 0.35] —
		## above that the tax stops being survivable and becomes the soft game
		## over this bead deleted.
		##
		## What it may NOT do is stand in for speed. The lattice above is
		## untouched by any of this: walking still gets you caught, running still
		## escapes, and what a bite now applies is pressure on coins and time.
		"coin_setback": 0.10,
	},

	## ------------------------------------------------------------------------
	## SAND VIPER — the DESERT band's predator.
	## ------------------------------------------------------------------------
	## The first entry that is not the crocodile, and the proof the table works:
	## everything below is a NUMBER. The only other things a new predator needs
	## are its own .tscn (a `Model` child and a CollisionShape3D that fit its
	## mesh) and one line in endless_terrain.gd's BIOME_SPECIES map. No subclass,
	## no new script, no new arm in any per-frame path.
	##
	## Every number that touches geometry is measured off
	## assets/models/characters/snake.glb (built by scripts/generate_snake.py):
	## 1.7345 m long (x -1.3625 .. +0.372), 0.4111 m across its resting S-curve,
	## and 0.2065 m TALL — an eighth of its own length. It is a fundamentally
	## different SHAPE from the crocodile (1.40 x 0.28 x 0.276), which is why so
	## few of these numbers could have been shared as globals.
	##
	## THE CAPSULE IN sand_viper.tscn COMES OFF THE SAME THREE FIGURES, and it is
	## recorded here because a .tscn cannot hold a comment an editor resave will
	## not eat. `radius = 0.11, height = 1.75`, laid down on the travel axis with
	## the crocodile's basis, at `(0, 0.11, -0.495)`:
	##   * 0.11 makes a 0.22 m tube around a 0.2065 m body — the tightest fit the
	##     mesh allows, and the point of it: a serpent's collision has to HUG the
	##     ground. The crocodile's 0.16 would float this animal's head over its
	##     own capsule. It is deliberately NARROWER than the 0.41 m S-curve too;
	##     the wiggle is silhouette, not bulk, and a capsule fat enough to cover
	##     it would wedge in gaps a snake ought to slip through.
	##     0.11 IS ALSO THE SHAPE'S HEIGHT, and that is not a coincidence: a
	##     CapsuleShape3D's transform origin is its CENTRE, so centre 0.11 with
	##     radius 0.11 puts the capsule's bottom exactly on y = 0. The body then
	##     settles with the mesh's own y = 0 underside on the ground. (The
	##     crocodile's 0.16/0.16 is the same identity. Measured, because it reads
	##     like a floating model and isn't: dropped onto a plane, the viper's
	##     lowest vertex lands at y = -0.003 and the crocodile's at y = -0.035.)
	##   * 1.75 covers the 1.7345 m length with the caps included.
	##   * z = -0.495 is the ONE thing this scene does that the crocodile's does
	##     not. generate_snake.py builds the viper HEAD-FIRST from the origin, so
	##     the mesh is lopsided about it where the crocodile's is centred.
	##     A capsule centred on the origin would put ~0.87 m of invisible solid
	##     body out in front of the snout and leave the tail hanging with nothing
	##     behind it. -0.495 is the mesh's own midpoint, so the shape covers
	##     x -1.37 .. +0.38: the visible animal, and only it.
	## What origin-at-the-head buys for free: bite range, the obstacle feelers and
	## the chase distance are all measured from the node origin, which for this
	## species is where its fangs are — and the right pivot for the asc.4 strike.
	"sand_viper": {
		## THE AMBUSHER (asc.4). Phase 2 shipped this row as "solo" — a viper that
		## wandered and chased exactly like a crocodile — and everything that turns
		## it into an ambush is on this page: four NUMBERS below, plus one `match`
		## arm (`_behave_ambush()`) that is a single assignment.
		##
		## READ THE THREE ZEROES-AND-FIVES TOGETHER, because separately none of
		## them is the behaviour: move_speed 0.0 (it never leaves its patch),
		## detection_radius 5.0 (it cannot smell you coming — you have to step on
		## it) and ambush_burrow_depth (you cannot see it while it waits). A
		## predator that does not move, does not sense and cannot be seen is not a
		## weak crocodile; it is a different threat, one you walk INTO rather than
		## one that hunts you. Surprise and position ARE the weapon — see the
		## chase_speed note for why the foot race stopped being one.
		"behavior": "ambush",

		# ----- Speed and detection -----
		## THE LATTICE IS THE LATTICE: 5.0 (WALK_SPEED) < 5.5 <= 8.5
		## (MAX_CHASE_SPEED) < 9.0 (the slowest character's run).
		##
		## 7.5 UNTIL godot-test1-lyk, WHICH MADE THE ANIMAL YOU CANNOT SEE THE
		## FASTEST ROW IN THE TABLE. The lattice held — 7.5 x 1.2 clamps to 8.5 and
		## a run still escapes — but it held on the CLAMP, and that is what made the
		## row a lie in play. Read the two ends against a 9.0 run:
		##
		##   7.5: top roll 9.0 -> clamped 8.5, margin 0.5 m/s; median 7.5, margin
		##        1.5. A player sprinting flat out pulled half a metre a second.
		##   5.5: top roll 5.9, margin 3.1 m/s; median 5.5, margin 3.5. The SAME
		##        margin a crocodile leaves, which is the number this game's feel
		##        was tuned around.
		##
		## An ambusher is the one species that does not need the foot race. It
		## already has the burrow, a trip-wire you have to walk into, and a lunge
		## that erupts from 5 m — it earns kills from SURPRISE AND POSITION, and
		## paying for that twice (invisible AND fastest) is what the owner reported
		## as unsurvivable. Matching the crocodile's 5.5 is the deliberate reading:
		## the viper is a normal-speed animal you did not see coming, and the hiss
		## below is the beat it now gives you to react.
		##
		## THE FAR-FIELD IS NOT A LOOPHOLE AND IT IS NOT VIPER-SPECIFIC: the
		## distance gradient tops out at x1.6, so EVERY non-burst row above
		## 8.5 / (1.2 x 1.6) = 4.43 pins to MAX_CHASE_SPEED out at 1800 m, the
		## crocodile included, and all of them measure the same +0.50 margin there.
		## That ceiling is a game-wide contract; what this row owns is the near and
		## middle field, which is where the ambush actually happens.
		##
		## AND THIS ROW IS NOT A BURST ROW. The pounce in `_behave_burst` is the
		## one sanctioned way past MAX_CHASE_SPEED (see CLAUDE.md and check 8),
		## it is paid back in a mandatory recovery leg, and an ambusher does not
		## get one: the burrow already IS its opening move.
		##
		## MOVE_SPEED IS ZERO, AND IT IS A BEHAVIOUR, NOT A TUNING. `_wander_speed`
		## multiplies it, so a buried viper's wander velocity is identically 0 at
		## every point of the sin cycle and for every roll of speed_factor: it
		## holds the spot it spawned on until something walks into its 5 m. That is
		## the "does not close distance on a passing player" half of the ambush,
		## and enemy_spawn_selfcheck MEASURES it against a walking quarry rather
		## than trusting this number. The one place it needs care is
		## `_animate_body`, whose stride divisor is this value — see the maxf()
		## there, which exists for this row and only this row.
		"move_speed": 0.0,
		"chase_speed": 5.5,

		## ±7% / ±20%, and the SPEED figure is a consequence of 5.5 above, not an
		## independent nerf. The argument this row has always made is unchanged:
		## the SPECIES doc block is right that a slow roll is a feature — a
		## straggler in a crowd reads as a straggler — but an ambusher is not in a
		## crowd. It gets ONE strike from 5 m, so a roll that drops it under
		## WALK_SPEED (5.0) is not a straggler, it is a viper the player strolls
		## away from mid-lunge with nothing on screen to explain it. Phase 2's ±35%
		## floored at 4.88 and was cut to ±20% for exactly that reason.
		##
		## ±20% ON 5.5 FLOORS AT 4.40, which is further under WALK_SPEED than the
		## number that cut was made to fix, so the spread had to come down with the
		## speed: ±7% floors the strike at 5.115 and caps it at 5.885. Every viper
		## in the world still catches a WALKING player — the one thing an ambusher
		## must do — and none of them comes near a run. Size keeps its ±20%; a fat
		## viper is still a viper, and its size never decided a chase.
		"speed_random_factor": 0.07,
		"size_random_factor": 0.2,

		## THE TRIGGER RADIUS, and phase 2's row promised exactly this cut: an
		## ambusher trades senses for surprise and gets the danger back from the
		## strike. 5.0 m is about three body lengths — one second of walking, and
		## barely further than the strike itself travels. It is a HYSTERESIS-FREE
		## trigger, which is what makes the lunge SHORT with no timer anywhere: the
		## same radius that fires the strike ends it, so a viper that has not
		## closed the gap re-buries the moment you are 5 m clear. Still far below
		## the LOD manager's SIM_RADIUS (45.0), the invariant every species owes.
		"detection_radius": 5.0,

		# ----- Organic wandering -----
		## Longer interval and a longer pause than the crocodile: a viper basks.
		"direction_change_interval": 5.0,
		"pause_duration": 0.8,

		## Lazier drift, but a snappier TURN once it commits — a snake pivots
		## along its own length instead of swinging a rigid body round.
		"wander_turn_rate": 0.9,
		"turn_smoothness": 6.0,

		## The wander SHAPE is now decoration on a stationary animal — move_speed
		## 0.0 multiplies the first two into nothing — but the third is
		## load-bearing, and its zero is not tidiness.
		##
		## `sniff_pause_chance` 0.0 IS THE TRIP-WIRE STAYING ARMED. Look at
		## _physics_process: `is_paused` short-circuits the whole else-branch, so a
		## paused predator never reaches _update_chase_state and cannot detect
		## anything at all. At phase 2's 0.45 this viper would spend a 0.8 s pause
		## BLIND on a coin flip every 5 s — roughly one ambusher in seven deaf at
		## any instant, and deaf is fatal for a species whose entire behaviour is a
		## 5 m trip-wire you are meant to walk into. Nothing about a buried animal
		## needs to stop and sniff anyway: it already never moved.
		"min_wander_speed_factor": 0.35,
		"speed_variation_freq": 0.6,
		"sniff_pause_chance": 0.0,

		# ----- Obstacle avoidance -----
		## Look-ahead is the crocodile's ratio applied to this body: ~1.45x the
		## mesh length, so it turns before the snout can reach a block. Wider
		## feelers and a gentler slowdown than the crocodile — it whips around an
		## obstacle rather than easing round it.
		"avoid_look_ahead": 2.5,
		"avoid_feeler_angle": PI / 4.0,  # 45°
		## Cast just above the 0.13 m neck, so the probes sample a block's side
		## wall and not the flat ground. The crocodile's 0.3 would fly clean over
		## this animal's whole head.
		"avoid_feeler_height": 0.15,
		"avoid_speed_factor": 0.6,

		# ----- Procedural body animation -----
		## Same nose-along-+X model contract as every predator mesh, so the same
		## -90° puts the snout on the travel axis.
		"model_facing_offset": -PI / 2.0,

		## THE SLITHER, and it is all in `sway_yaw`. The crocodile waddles: a big
		## ROLL (9°) with a small yaw sway (5°). A snake is the exact inverse —
		## it barely rolls (3°) and swings hugely in yaw (14°), which swings the
		## mesh's built-in resting S-curve from side to side. Faster stride to
		## match, and a bob a third of the crocodile's because a body 0.21 m tall
		## that bobs 0.025 m does not undulate, it hops.
		"stride_frequency": 12.0,
		"waddle_roll": 3.0 * PI / 180.0,
		"bob_amount": 0.008,
		"sway_yaw": 14.0 * PI / 180.0,

		## Rears its head a little when hunting, but a snake tracking prey stays
		## LOW — a third of the crocodile's forward lean.
		"chase_pitch": 6.0 * PI / 180.0,

		## Slower and shallower idle breathing than the crocodile's: at this
		## scale anything larger reads as twitching, not breathing.
		"breathe_speed": 1.4,
		"breathe_amount": 0.006,

		# ----- River submersion (VISUAL ONLY) -----
		## 0.10 m — and this species gets the read the crocodile's entry above
		## explains it can never have. The crocodile's back is a flat plateau, so
		## no depth exists that shows its nose while hiding its spine. The viper
		## is the opposite shape: a 0.13 m body with a head standing 0.21 m up,
		## so sinking 0.10 puts the entire body under and leaves the head —
		## whose eyes and horned scales generate_snake.py deliberately sits at the
		## top of the skull — gliding along the surface. A literal periscope, out
		## of the same one constant.
		##
		## The hard constraint is unchanged and not negotiable: VISUAL ONLY. The
		## CharacterBody3D, its CollisionShape3D and global_position never move,
		## so a wading viper is exactly as dangerous as a dry one.
		"river_sink_depth": 0.10,
		## Same ~0.2 s ease as the crocodile and the player, written as
		## depth/time so the derivation survives a retune of the depth above it.
		"river_sink_ease_speed": 0.10 / 0.2,

		# ----- Bite -----
		## The strike: shorter, sharper and further than the crocodile's chomp
		## (0.5 s / 26° / 0.35 m). A snake bite is one fast lunge, not a chew.
		"bite_duration": 0.3,
		"bite_pitch": 34.0 * PI / 180.0,
		"bite_lunge": 0.5,

		# ----- The burrow (the "ambush" behaviour reads these two) -------------
		## The only keys in this table no other row has, exactly like the wolf's
		## two pack keys, and for the same reason: a key a species does not use is
		## a key it does not carry. (enemy_spawn_selfcheck derives its required key
		## set from the CROCODILE row, so behaviour-local keys are allowed — what
		## it forbids is a row MISSING something the crocodile has.)
		##
		## HOW DEEP THE MODEL SITS WHILE IT WAITS, in model-local metres, and it
		## goes through `_tick_river_sink` — the same one property the sink already
		## owns (`model_base_y`), eased the same way, composed as "whichever target
		## is DEEPER". That reuse is the point and it was the bead's instruction:
		## there is exactly one writer of the model's rest height, so a viper that
		## is burrowed AND in a river is simply burrowed, with no second easing
		## fighting the first.
		##
		## 0.24 IS MEASURED, NOT PICKED. snake.glb stands 0.2065 m tall, and the
		## locomotion bob adds 0.008 on top of the rest height, so 0.2145 is the
		## highest point this mesh ever reaches. 0.24 clears it by 25 mm and the
		## opaque ground plane at y = 0 does the rest — there is no water mesh and
		## no hole, the ground simply draws over it (see the crocodile row's
		## river_sink note for why that is the whole trick). Deeper buys nothing;
		## shallower leaves a snake-shaped ridge lying in the sand, which is the
		## one thing an ambush cannot afford. enemy_spawn_selfcheck measures this
		## against the scene's real mesh AABB rather than trusting the number.
		##
		## Model-LOCAL, so the ±20% size roll and any boss scale carry it for free,
		## exactly like the river sink. And VISUAL ONLY, the same hard constraint:
		## the CharacterBody3D, its CollisionShape3D and global_position never
		## move. A buried viper is exactly as dangerous as a surfaced one — you
		## simply cannot see it, and the player's collision_mask 1 means they walk
		## through it rather than into an invisible wall.
		"ambush_burrow_depth": 0.24,

		## HOW FAST IT COMES UP: 0.24 m in 0.12 s. Written as depth/time, like
		## every ease in this table, so the derivation survives a retune of the
		## depth above it.
		##
		## It is deliberately FOUR TIMES the sink ease (0.10 / 0.2 = 0.5 m/s) and
		## the asymmetry is the animation: a strike ERUPTS and a re-burial SLIDES.
		## _tick_river_sink picks this rate only when the rest height is RISING,
		## so going back under is left at the species' ordinary sink ease and takes
		## ~0.48 s. The body itself is not eased at all — physics lunges on frame
		## one — so what this number sets is only how much of the animal you see
		## while it is already on its way to you.
		"ambush_surface_ease_speed": 0.24 / 0.12,

		## THE STAKE (see the crocodile row): an ambush you barely saw, so a
		## small bill.
		"coin_setback": 0.08,
	},

	## ------------------------------------------------------------------------
	## TIMBER WOLF — the FOREST band's predator, and the first entry whose
	## `behavior` is not "solo".
	## ------------------------------------------------------------------------
	## Everything a wolf IS lives in two extra numbers at the bottom of this row
	## (`pack_size`, `pack_flank_radius`) and one arm of the `match` in
	## `_update_chase_state()`. There is no pack object, no leader, no registry
	## and no group scan: each wolf reads its OWN deterministic id and steers to
	## its OWN slot on a ring around the quarry, and the surround is what happens
	## when several of them do that at once. See `pack_steer_point()` for the
	## geometry, and for why that stays true when the LOD manager sleeps half of
	## them.
	##
	## Geometry measured off assets/models/characters/wolf.glb (built by
	## scripts/generate_wolf.py): 1.4265 m nose to tail (x -0.700 .. +0.7265),
	## 0.325 m across (z ±0.1625) and 0.740 m TALL. Read those three together —
	## it is almost exactly the crocodile's LENGTH (1.40) standing on legs that
	## make it nearly three times the crocodile's HEIGHT (0.276). That one
	## difference is where every number below diverges, and where the rest
	## deliberately does not.
	##
	## THE CAPSULE IN timber_wolf.tscn COMES OFF THE SAME THREE FIGURES, recorded
	## here because a .tscn cannot hold a comment an editor resave will not eat.
	## `radius = 0.1625, height = 1.45`, laid down on the travel axis with the
	## crocodile's basis, at `(0, 0.1625, 0)`:
	##   * 0.1625 is EXACTLY the mesh's half-width, so the shape stops the body
	##     at the precise distance where the wolf's flank meets a block face. The
	##     crocodile's 0.16 is a near miss on a differently-shaped animal, not a
	##     fit — this is the number that made it worth its own shape.
	##   * 1.45 covers the 1.4265 m length with the caps included, the same
	##     nose-out-of-the-block reason the crocodile's 1.4 covers its 1.40 — and
	##     the reason this species does NOT get the upright capsule its standing
	##     pose suggests. A column would leave 0.55 m of muzzle and 0.55 m of
	##     tail free to slide into stone.
	##   * radius == centre y, like both rows above, puts the capsule's bottom on
	##     y = 0, so gravity settles the mesh's own feet onto the ground plane.
	##   * WHAT THIS SHAPE DELIBERATELY DOES NOT COVER is the wolf ABOVE its
	##     knees: the capsule occupies y 0 .. 0.325 while the torso sits at
	##     0.40 .. 0.64. That costs nothing in a world whose blocks are solid
	##     from the ground UP — anything that could touch the chest has already
	##     stopped the legs — and buying the height instead would take radius
	##     0.37: a 0.74 m thick log around a 0.325 m animal. Same call the
	##     viper's row makes about its S-curve: the shape hugs the body, not the
	##     pose.
	## The mesh's own midpoint is x = +0.013, so the capsule is left centred on
	## the origin; 13 mm is inside the noise of a 1.43 m animal, where the viper's
	## head-first 0.495 m was not.
	"timber_wolf": {
		## The first non-solo arm. `_behave_pack()` is all it selects, and all
		## that does is bend the chase TARGET onto this wolf's ring slot — chase
		## acquisition, the jump hatch, the bite, the flee and the LOD sleep are
		## untouched. A wolf is a crocodile that arrives from a different angle.
		"behavior": "pack",

		# ----- Speed and detection -----
		## THE LATTICE IS THE LATTICE: 5.0 (WALK_SPEED) < 6.8 <= 8.5
		## (MAX_CHASE_SPEED) < 9.0 (the slowest character's run). The wolf is the
		## fastest cruiser in the table (3.0 against 2.5 and 2.0 — it covers
		## ground even when it is not hunting) and the fastest pursuer, and it
		## still cannot break the promise: 6.8 x 1.25 x 1.6 = 13.6, and
		## MAX_CHASE_SPEED cuts it to 8.5. Running escapes a wolf pack exactly as
		## it escapes everything else.
		##
		## 6.8 IS NOT A BUFF, IT IS THE FARE FOR THE ANGLE, and the arithmetic is
		## worth stating because it is the whole design of this species. A
		## flanking wolf does not spend its speed on the straight line to you: it
		## holds a 37° lead angle (see PACK_FLANK_TAPER), so only cos(37°) = 0.80
		## of it closes the gap — 6.8 x 0.80 = 5.44 m/s, which is the crocodile's
		## 5.5 to within a rounding. A wolf therefore runs a walking player down
		## at the same rate a crocodile does, having spent the difference on
		## arriving from the side. That is what "dangerous by cutting angles, not
		## by exceeding the ceiling" costs when you write it down.
		"move_speed": 3.0,
		"chase_speed": 6.8,

		## ±25% / ±15% — the TIGHTEST spreads in the table, and that is a pack
		## requirement rather than a taste. The crocodile's ±50% exists to string
		## a crowd out into stragglers and hunters; do that to wolves and the slow
		## half never arrives, the ring never closes, and the surround this
		## species is built around simply never appears on screen. A pack has to
		## travel at one pace to read as a pack.
		"speed_random_factor": 0.25,
		"size_random_factor": 0.15,

		## The longest "smell" of any regular predator (crocodile 15, viper 12).
		## A pack has to commit early, because a flanking approach is a LONGER
		## path than a straight one — a wolf that only acquires you at 12 m has
		## no room left to swing wide before it is already on top of you.
		## INVARIANT, unchanged and not negotiable: far below the LOD manager's
		## SIM_RADIUS (45.0), so anything that can detect the player is awake.
		"detection_radius": 18.0,

		# ----- Organic wandering -----
		## Restless where the viper basks: the shortest interval and the shortest
		## pause in the table. An idle wolf is a trotting wolf.
		"direction_change_interval": 3.0,
		"pause_duration": 0.35,

		## The most agile steering in the table, and `turn_smoothness` in
		## particular is load-bearing rather than flavour: a flanking wolf chases
		## a target point that slides sideways as it closes, so a body that turns
		## at the crocodile's 5.0 lags its own ring slot and cuts the very corner
		## it was supposed to swing around.
		"wander_turn_rate": 1.5,
		"turn_smoothness": 7.0,

		## Ebbs shallower than either row above (0.45 / 0.35) and varies faster:
		## a wolf slows down to sniff, it does not stop to bask.
		"min_wander_speed_factor": 0.55,
		"speed_variation_freq": 1.0,
		"sniff_pause_chance": 0.35,

		# ----- Obstacle avoidance -----
		## Look-ahead is ~2x the mesh length, a longer ratio than the crocodile's
		## because this animal closes faster and needs the extra metre to commit
		## a turn. Narrow feelers and a mild slowdown are the same idea from the
		## other side: a wolf keeps its pace THROUGH a gap rather than easing
		## around the outside of it.
		"avoid_look_ahead": 3.0,
		"avoid_feeler_angle": PI / 5.0,  # 36°
		## Chest height on a 0.74 m animal, so the probes sample a block's side
		## wall well above the ground plane. The crocodile's 0.3 would fire under
		## this animal's belly (0.40) and read the empty air between its legs.
		"avoid_feeler_height": 0.45,
		"avoid_speed_factor": 0.65,

		# ----- Procedural body animation -----
		## Same nose-along-+X model contract as every predator mesh.
		"model_facing_offset": -PI / 2.0,

		## THE LOPE. The crocodile waddles (9° roll, 0.025 bob) because it is a
		## long body dragged between splayed legs; the wolf is the opposite
		## machine — a light frame on the longest legs of the five generated
		## predators — so the roll drops to 4° and the BOB doubles the
		## crocodile's. Vertical travel is what a bounding gait looks like, and
		## 0.05 m is a fourteenth of this animal's own height, where the same
		## number on the 0.21 m viper would read as hopping.
		"stride_frequency": 10.0,
		"waddle_roll": 4.0 * PI / 180.0,
		"bob_amount": 0.05,
		"sway_yaw": 6.0 * PI / 180.0,

		## Head down, shoulders forward once it commits. Slightly past the
		## crocodile's 10°, because the ruff over the chest (see
		## generate_wolf.py) is what the lean shows off.
		"chase_pitch": 12.0 * PI / 180.0,

		"breathe_speed": 2.4,
		"breathe_amount": 0.02,

		# ----- River submersion (VISUAL ONLY) -----
		## 0.25 m — and unlike the two rows above, this one is not hiding. A wolf
		## does not submerge, it WADES: sink 0.25 and the legs (0 .. 0.40) go
		## under while the belly line sits 0.15 m proud and the whole torso,
		## saddle and head stay in plain view. That is the read this species
		## wants — a crocodile in a river is a threat you cannot see, a wolf in a
		## river is one you can, slowed to the same wade you are.
		##
		## Same hard constraint as every row: VISUAL ONLY. The CharacterBody3D,
		## its CollisionShape3D and global_position never move, so a wading wolf
		## is exactly as dangerous as a dry one.
		"river_sink_depth": 0.25,
		## Same ~0.2 s ease as the crocodile, the viper and the player, written
		## as depth/time so the derivation survives a retune of the depth.
		"river_sink_ease_speed": 0.25 / 0.2,

		# ----- Bite -----
		## Between the crocodile's chew (0.5 s) and the viper's strike (0.3 s):
		## a wolf snaps and drives THROUGH, so the lunge is long and the pitch is
		## a head dropping to the throat.
		"bite_duration": 0.35,
		"bite_pitch": 30.0 * PI / 180.0,
		"bite_lunge": 0.45,

		# ----- Pack steering (the "pack" behaviour reads these two) -----
		## The only keys in this table no other row has, and the only two the
		## surround needs. They live HERE rather than as file-level consts for
		## the same reason every other number in this row does: the next
		## behaviour bead adds ITS keys to ITS row, and a key a species does not
		## use is a key it does not carry. (enemy_spawn_selfcheck derives its
		## required key set from the CROCODILE row, so behaviour-local keys are
		## allowed — what it forbids is a row MISSING something the crocodile
		## has.)
		##
		## How many slots the ring is divided into: five compass points, 72°
		## apart. Deliberately ABOVE the number of wolves usually in earshot at
		## once (a forest chunk holds a handful, and only the near ones are
		## inside the 18 m detection radius), because slots are claimed by
		## `id % pack_size` with nobody arbitrating — a smaller ring would collide
		## slots often, and two wolves sharing a bearing is the single thing that
		## reads as "they are NOT surrounding me". Five is also odd, so no two
		## slots are exact opposites and a two-wolf pack never reads as a line.
		"pack_size": 5,

		## How far off the quarry the ring sits, in metres, at full spread. Four
		## metres is a little over half of the wolf's 6.8 m/s chase — roughly the
		## distance one covers in the time it takes to turn — so the swing is
		## wide enough to see from inside it and short enough that the pack still
		## arrives together. It is a MAXIMUM, not a standoff distance: the ring
		## tapers to nothing as the wolf closes (see pack_steer_point), so this
		## number shapes the APPROACH and never becomes an orbit the player can
		## stand safely in the middle of.
		"pack_flank_radius": 4.0,

		## THE STAKE (see the crocodile row): you were surrounded by the pack —
		## it earned the extra.
		"coin_setback": 0.12,
	},

	## ------------------------------------------------------------------------
	## FROST BEAR — the SNOW band's predator, and the table's heavy.
	## ------------------------------------------------------------------------
	## Every other row in this table is an animal that STEERS. The bear is the one
	## that does not: once it locks on it commits to a bearing and drives, and the
	## counterplay is not outrunning it (though you can — the lattice is the
	## lattice) but STEPPING OUT OF THE WAY. That is one extra number at the
	## bottom of this row (`charge_commit`) and one arm of the `match` in
	## _update_chase_state; see `charge_steer_point()` for the geometry.
	##
	## WHY THE SNOW GETS IT. endless_terrain's SNOW block calls the tundra the
	## HOSTILE band: nothing is thinned, croc density is the full distance-scaled
	## figure, and the only shelter is ice you can climb onto. It is also the most
	## OPEN ground in the world — a handful of dead trees per chunk and a lot of
	## nothing between them. Open ground is the one place a straight-line charger
	## is readable from far enough away to dodge, and where a dodge has somewhere
	## to go. Put this animal in the forest and it would spend its life bouncing
	## off trunks; put the wolf out here and its flanking ring would have nothing
	## to hide behind.
	##
	## Geometry measured off assets/models/characters/bear.glb (built by
	## scripts/generate_bear.py): 1.2154 m nose to tail (x -0.460 .. +0.7554),
	## 0.434 m across (z ±0.217) and 0.820 m TALL. Read those three against the
	## wolf's (1.4265 / 0.325 / 0.740): the bear is SHORTER and yet a third wider
	## and taller — the only predator in the set that is bulkier than it is long,
	## which is exactly the silhouette generate_bear.py is after (shoulder hump,
	## head slung low, short thick legs). It is why this row could not have reused
	## the crocodile's capsule, and why its waddle is the heaviest in the table.
	##
	## THE CAPSULE IN frost_bear.tscn COMES OFF THE SAME THREE FIGURES, recorded
	## here because a .tscn cannot hold a comment an editor resave will not eat.
	## `radius = 0.217, height = 1.25`, laid down on the travel axis with the
	## crocodile's basis, at `(0, 0.217, 0.148)`:
	##   * 0.217 is EXACTLY the mesh's half-width, the same fit rule the wolf's
	##     0.1625 follows. The crocodile's 0.16 would leave 5.7 cm of bear hanging
	##     out of each flank — on the widest animal in the set, which is precisely
	##     the one that cannot afford it, because a charger that clips a block it
	##     is not touching stops dead mid-charge.
	##   * 1.25 covers the 1.2154 m length with the caps included. Like the wolf,
	##     the shape lies DOWN along the travel axis rather than standing up: a
	##     column would leave the muzzle and the rump free to slide into stone.
	##   * radius == centre y puts the capsule's bottom on y = 0, so gravity
	##     settles the mesh's own paws onto the ground plane. Same identity as all
	##     three rows above.
	##   * z = +0.148 is the mesh's own midpoint, and this row needs it for the
	##     reason the viper's -0.495 does and the wolf's +0.013 does not.
	##     generate_bear.py hangs the head and snout off the front of a body
	##     centred near the origin, so the mesh runs -0.460 .. +0.7554: centre the
	##     capsule on the origin and 0.13 m of muzzle pokes out of the front of it.
	##     On a charger, the muzzle is the end that arrives first.
	##   * WHAT IT DELIBERATELY DOES NOT COVER, same call as the wolf's row: the
	##     bear above 0.434 m. The torso sits at 0.34 .. 0.72 and the hump above
	##     that; buying the height would take radius 0.41, a 0.82 m thick log
	##     around a 0.43 m animal. In a world whose blocks are solid from the
	##     ground UP, anything that could touch the chest has already stopped the
	##     legs.
	"frost_bear": {
		## The second non-solo arm. `_behave_charge()` is all it selects, and all
		## that does is bend the chase TARGET onto the bearing this bear committed
		## to — chase acquisition, the jump hatch, the bite, the flee and the LOD
		## sleep are untouched. A bear is a crocodile that will not turn.
		"behavior": "charge",

		# ----- Speed and detection -----
		## THE LATTICE IS THE LATTICE: 5.0 (WALK_SPEED) < 6.0 <= 8.5
		## (MAX_CHASE_SPEED) < 9.0 (the slowest character's run). 6.0 x 1.2 x 1.6
		## = 11.5 and MAX_CHASE_SPEED cuts it to 8.5, so running escapes a bear
		## exactly as it escapes everything else.
		##
		## 6.0 IS THE SLOWEST CHASE OF THE THREE NEW SPECIES ON PURPOSE, and the
		## row is dangerous anyway, which is the point of the whole bead: the bear
		## does not need to be fast because it is not trying to follow you. It
		## needs to be faster than a WALK (it is, by a full metre per second) so
		## that ignoring a charge is fatal, and it needs to be slow enough that
		## the ~0.7 s of committed straight line below is a window you can see and
		## use. A faster bear would cross its own commitment before you could
		## react to it, and the behaviour would read as an unfair instant hit
		## rather than as a dodge you missed.
		##
		## move_speed 1.6 is the slowest cruiser in the table (crocodile 2.5, wolf
		## 3.0): the "slower base wander" half of the spec. An idle bear plods.
		"move_speed": 1.6,
		"chase_speed": 6.0,

		## ±20% / ±15%. Speed is tight for the same reason the viper's is: the
		## charge is a timing puzzle, and a bear rolling 4.2 m/s would be one the
		## player strolls away from with no dodge needed, while the top roll is
		## capped by the lattice regardless. Size is the wolf's ±15% — the mass is
		## this animal's whole read, and a small one stops being a bear.
		"speed_random_factor": 0.2,
		"size_random_factor": 0.15,

		## 14.0 — between the crocodile's 15 and the wolf's 18, and well above the
		## viper's 5. A charger needs to acquire you EARLY, because the behaviour
		## is a long straight line and a bear that only notices you at bite range
		## has no line to run. INVARIANT, unchanged and not negotiable: far below
		## the LOD manager's SIM_RADIUS (45.0), so anything that can detect the
		## player is awake.
		"detection_radius": 14.0,

		# ----- Organic wandering -----
		## The longest interval and the longest pause in the table: a bear ambles,
		## stops, considers, ambles on.
		"direction_change_interval": 6.0,
		"pause_duration": 1.2,

		## THE MOMENTUM, and `turn_smoothness` is the load-bearing one. 0.5 is the
		## laziest drift in the table (the "slower base turn rate" half of the
		## spec), but 3.0 against the crocodile's 5.0 and the wolf's 7.0 is what
		## makes a bear that has committed hard to redirect: velocity is driven
		## from the body's FACING, never from the raw movement direction (see
		## _physics_process), so a slow lerp_angle is literally momentum.
		##
		## 3.0 AND NOT LOWER, DELIBERATELY. The commitment this species is built
		## around comes from `charge_commit` below, not from here, and the two are
		## not interchangeable: crank turn_smoothness down far enough and the bear
		## also fails to leave its own charge, fails to round a block (the avoid
		## path doubles this rate, and doubling something tiny is still tiny) and
		## fails to acquire a quarry standing behind it. 3.0 keeps every one of
		## those working while still reading as weight. enemy_spawn_selfcheck
		## measures the dodge against a bear with the charge arm SWITCHED OFF, so
		## if the commitment ever quietly migrated from the arm into this number
		## the negative control is what says so.
		"wander_turn_rate": 0.5,
		"turn_smoothness": 3.0,

		## Ebbs deep and slow — a plod that varies, not a trot that pauses.
		"min_wander_speed_factor": 0.5,
		"speed_variation_freq": 0.5,
		"sniff_pause_chance": 0.3,

		# ----- Obstacle avoidance -----
		## Look-ahead is ~3x the mesh length, the longest ratio in the table, and
		## it is the fare for `turn_smoothness` 3.0: this animal needs the extra
		## metre because it commits a turn slowly. The FEELERS are the widest too
		## (45° against everyone else's 36°), because they are the one place the
		## bear's bulk has to be paid for — a probe at the wolf's 36° sweeps a
		## corridor narrower than this body actually is, so it clears a gap the
		## flanks then catch on.
		"avoid_look_ahead": 3.6,
		"avoid_feeler_angle": PI / 4.0,  # 45°
		## Chest height on a 0.82 m animal whose belly line is at 0.34, so the
		## probes sample a block's side wall rather than the air under it.
		"avoid_feeler_height": 0.5,
		## The heaviest slowdown in the table, tied with the crocodile's: mass
		## does not corner at speed.
		"avoid_speed_factor": 0.5,

		# ----- Procedural body animation -----
		## Same nose-along-+X model contract as every predator mesh.
		"model_facing_offset": -PI / 2.0,

		## THE LUMBER. The slowest stride in the table over the biggest roll:
		## generate_bear.py's own note says the low mass is what makes the
		## existing waddle read as weight rather than as a stumble, and 11° is
		## what cashes that in. The bob follows the roll up (0.035, between the
		## crocodile's 0.025 and the wolf's 0.05) while the yaw sway drops to 4° —
		## a bear swings side to side, it does not snake.
		"stride_frequency": 7.0,
		"waddle_roll": 11.0 * PI / 180.0,
		"bob_amount": 0.035,
		"sway_yaw": 4.0 * PI / 180.0,

		## The deepest lean in the table. Shoulders down into the charge is the
		## whole pose, and the hump generate_bear.py puts over the FRONT legs is
		## the part of the silhouette the lean shows off.
		"chase_pitch": 14.0 * PI / 180.0,

		## Slow, deep idle breathing to match the mass.
		"breathe_speed": 1.6,
		"breathe_amount": 0.025,

		# ----- River submersion (VISUAL ONLY) -----
		## 0.30 m — the wolf's read on a bigger animal. The legs (0 .. 0.34) go
		## under, the belly line sits 0.04 m proud and the whole torso, hump and
		## head stay in plain view. A bear in a river is a threat you can see,
		## slowed to the same wade you are; hiding this animal would waste the one
		## silhouette in the set you are supposed to spot from a long way off.
		##
		## Same hard constraint as every row: VISUAL ONLY. The CharacterBody3D,
		## its CollisionShape3D and global_position never move, so a wading bear is
		## exactly as dangerous as a dry one.
		"river_sink_depth": 0.30,
		## Same ~0.2 s ease as every other row and as the player, written as
		## depth/time so the derivation survives a retune of the depth.
		"river_sink_ease_speed": 0.30 / 0.2,

		# ----- Bite -----
		## The slowest, heaviest maul in the table (crocodile 0.5, wolf 0.35, viper
		## 0.3). A bear does not snap — it swats, and the pitch is shallow because
		## the head is already slung low.
		"bite_duration": 0.55,
		"bite_pitch": 24.0 * PI / 180.0,
		"bite_lunge": 0.4,

		# ----- The charge (the "charge" behaviour reads this one) -------------
		## HOW FAR THE BEAR RUNS BLIND, in metres, before it looks up and re-aims.
		## The only key in this table no other row has besides the wolf's two and
		## the viper's two, and the same rule applies: a key a species does not use
		## is a key it does not carry.
		##
		## THIS NUMBER IS THE COUNTERPLAY, stated as a distance rather than a
		## timer, and the distance form is not a style choice — _update_chase_state
		## has no `delta` (see the note on the dispatch), so a timer would have
		## needed one plumbed through every arm. A distance needs only the two
		## things the bear already knows: where it locked on, and where it is now.
		## It also happens to be the more honest quantity: what the player dodges
		## is a body travelling through space, not a clock.
		##
		## 4.0 m is ~0.7 s at this row's chase speed, which is comfortably longer
		## than a sidestep (a walking player covers 3.3 m in that time and the bear
		## is 0.43 m wide) and comfortably shorter than the 14 m acquisition, so a
		## charge is three or four committed runs rather than one unmissable
		## freight train. Shorter and it degenerates into ordinary tracking with a
		## slow turn; much longer and the bear stops being able to hit a player who
		## is merely walking in a straight line, which is not a difficulty knob but
		## a broken predator.
		"charge_commit": 4.0,

		## THE STAKE (see the crocodile row): a big animal bills hard.
		"coin_setback": 0.20,
	},

	## ------------------------------------------------------------------------
	## MOUNTAIN COUGAR — the MOUNTAIN band's predator, and the only animal in
	## this game that is allowed to break MAX_CHASE_SPEED.
	## ------------------------------------------------------------------------
	## READ THE `burst_*` KEYS AT THE BOTTOM OF THIS ROW BEFORE ANYTHING ELSE, and
	## read them together with the alley hound's, because the two rows share one
	## `match` arm and one static function and mean very different animals with it.
	##
	## THE POUNCE IS THE ONE PLACE THE SPEED LATTICE BENDS, AND IT BENDS EXACTLY
	## ONCE. Every other row in this table honours the ceiling as an instantaneous
	## bound: `chase_speed x roll x distance` is clamped to MAX_CHASE_SPEED (8.5)
	## in _ready() and that is the fastest the animal ever moves. This one is
	## clamped identically — and then `burst_factor` multiplies the clamped value
	## for the length of a pounce, so a cougar at the top of the gradient touches
	## 8.5 x 1.3 = 11.05 m/s, above the ceiling AND above the slowest character's
	## run (9.0). That is deliberate, it is what the bead asked for (">8.5 m/s"),
	## and it is safe for exactly one reason:
	##
	##   THE CONTRACT IS THE CYCLE, NOT THE INSTANT. "Running always escapes" is a
	##   statement about whether the gap closes, and a gap is closed over TIME.
	##   The pounce is followed by a mandatory recovery leg at `recover_factor`,
	##   and the CYCLE average is what a fleeing player actually races:
	##
	##       avg = V x (Db + Dr) / (Db / Fb + Dr / Fr)
	##           = V x 7.0 / (4.0 / 1.3 + 3.0 / 0.55) = V x 0.8205
	##
	##   At the worst case the game can produce (V clamped to 8.5) that is
	##   6.97 m/s against a 9.0 m/s run: the runner gains 2.03 m every second and
	##   the gap grows without bound. Inside one cycle it dips — the pounce takes
	##   0.74 m back over its 0.36 s — and then the recovery hands 2.78 m of it
	##   straight back. A runner more than about a metre clear is never caught, and
	##   enemy_spawn_selfcheck's check 8 MEASURES that over repeated cycles rather
	##   than trusting this arithmetic, with the recovery switched off as its
	##   negative control (that control catches the runner, which is the proof the
	##   recovery is what saves them).
	##
	##   THE OTHER END OF THE LATTICE SURVIVES TOO, and it is the end a burst is
	##   likelier to break: 0.8205 x 7.8 = 6.40 m/s average, comfortably above
	##   WALK_SPEED (5.0), so walking is still caught. A recovery deep enough to
	##   make the cycle average dip UNDER 5.0 would not be a nerf, it would be a
	##   predator a player strolls away from. Check 8 measures that end as well.
	##
	## ON "PERCHES ON MOUNTAIN ROCKS / HIGH LEDGES", HONESTLY. It is not here, and
	## the reason is CLAUDE.md's flat-world invariant rather than an oversight: the
	## ground is one plane at y = 0 and a mountain is an IMPASSABLE BLOCK MASSIF
	## you route around, not raised terrain you climb. The only "high ground" in
	## this world is the `top` of a climbable footprint in the chunk's `obstacles`
	## list — which is how a coin perches, and which no predator can reach, because
	## nothing in this AI climbs. A cougar dropped onto a ledge at spawn would walk
	## off it on its first frame and never get back up; a one-frame pose is a worse
	## lie than no perch at all. What the pounce keeps from the idea is the part
	## that survives a flat world: a predator that closes the last few metres far
	## faster than it travels, and then has to stop.
	##
	## WHY THE MOUNTAIN GETS IT. A massif band is a maze of solid walls with long
	## sight-lines down the corridors between them, so a cougar is a thing that
	## appears at the end of an alley of rock and covers it in one go — and the
	## walls give the recovery leg somewhere to break line of sight. It also gets
	## the pounce's one free safety valve: `_avoid_obstacles` multiplies
	## `avoid_speed_factor` onto the burst AFTER it, so a cougar pouncing into a
	## rock face eases off on its own with no code in this row (see the note there).
	##
	## Geometry measured off assets/models/characters/cougar.glb (built by
	## scripts/generate_cougar.py): 1.6314 m nose to tail-tip (x -0.9815 .. +0.6499),
	## 0.2470 m across (z ±0.1235) and 0.6438 m TALL. Read those against the wolf's
	## (1.4265 / 0.325 / 0.740): the cougar is LONGER and yet a quarter narrower and
	## shorter — the leanest silhouette in the set, and 0.55 m of that length is
	## tail. Long, low and thin is exactly the coiled-cat read generate_cougar.py is
	## after, and it is why this row could not have reused the wolf's capsule.
	##
	## THE CAPSULE IN mountain_cougar.tscn COMES OFF THE SAME THREE FIGURES,
	## recorded here because a .tscn cannot hold a comment an editor resave will not
	## eat. `radius = 0.1235, height = 1.65`, laid down on the travel axis with the
	## crocodile's basis, at `(0, 0.1235, -0.166)`:
	##   * 0.1235 is EXACTLY the mesh's half-width, the same fit rule the wolf's
	##     0.1625 and the bear's 0.217 follow. It is the narrowest shape in the set,
	##     which is what lets this animal take the gaps between massifs that the
	##     bear's 0.217 would catch on.
	##   * 1.65 covers the 1.6314 m length with the caps included — tail INCLUDED,
	##     like the wolf's. A tail that passes through stone is the same bug as a
	##     muzzle that does, one body part further back.
	##   * radius == centre y puts the capsule's bottom on y = 0, so gravity settles
	##     the mesh's own paws onto the ground plane. Same identity as every row
	##     above.
	##   * z = -0.166 is the mesh's own midpoint, and it is NEGATIVE where the
	##     bear's is positive because the imbalance is at the other end: this animal
	##     is mostly tail behind the origin, where the bear is mostly muzzle in
	##     front of it. Centre the capsule on the origin and 0.17 m of tail hangs
	##     out of the back of it.
	##   * WHAT IT DELIBERATELY DOES NOT COVER, the same call every row above makes:
	##     the cougar above 0.247 m. The torso sits at 0.36 .. 0.58; buying the
	##     height would take radius 0.32, a 0.64 m log around a 0.25 m animal, and
	##     in a world whose blocks are solid from the ground UP, anything that could
	##     touch the chest has already stopped the legs.
	"mountain_cougar": {
		## The third non-solo arm, and the FIRST ONE SHARED BY TWO SPECIES —
		## `_behave_burst()` runs for this row and for the alley hound's. That is
		## the table's own thesis, not a shortcut: a pounce and an alley sprint are
		## the same mechanic (a bounded burst with a mandatory recovery leg) at
		## different numbers, and the whole point of SPECIES is that a difference
		## which can be a number should be a number.
		"behavior": "burst",

		# ----- Speed and detection -----
		## THE LATTICE, AND THE ONE EXCEPTION TO IT: 5.0 (WALK_SPEED) < 7.8 <= 8.5
		## (MAX_CHASE_SPEED) < 9.0 (the slowest character's run). The SUSTAINED
		## speed obeys the ceiling exactly like every other row — 7.8 x 1.15 x 1.6
		## = 14.4, cut to 8.5 — and only the pounce goes above it, for the metres
		## `burst_distance` allows. See the block at the top of this row for why
		## that is safe and where it is measured.
		##
		## 7.8 IS THE FASTEST SUSTAINED CHASE IN THE TABLE and it has to be, because
		## the cycle average is what this animal actually travels at: 0.8205 x 7.8
		## = 6.40 m/s, which lands it between the bear (6.0) and the wolf (6.8) as a
		## PURSUER while making it much the fastest thing on screen for a third of a
		## second at a time. Reading 7.8 as "the fastest predator" is reading the
		## wrong number; the burst is what you feel and the average is what catches
		## you.
		##
		## move_speed 2.2 is the second-slowest cruiser in the table (only the bear
		## plods harder). A stalking cat is slow, and the contrast with the pounce
		## is the whole silhouette.
		"move_speed": 2.2,
		"chase_speed": 7.8,

		## ±15% / ±15% — tied with the wolf and the bear for the tightest speed
		## spread, and it is the burst that requires it rather than taste. This
		## row's promise is two-sided (a pounce ABOVE 8.5, a cycle average BELOW the
		## run and above the walk), and both ends move with the roll: at the bottom
		## roll the pounce is 8.62 m/s, which still clears 8.5, and the average is
		## 5.44 m/s, which still clears the walk. Widen the spread and one of those
		## two goes — a cougar whose "pounce" is 7.9 is a cougar with no mechanic.
		"speed_random_factor": 0.15,
		"size_random_factor": 0.15,

		## 16.0 — between the crocodile's 15 and the wolf's 18. A burst predator
		## needs enough runway to complete two or three full cycles before it is on
		## you (at the cycle average that is ~2.5 s), because one cycle in isolation
		## is just a fast crocodile. INVARIANT, unchanged and not negotiable: far
		## below the LOD manager's SIM_RADIUS (45.0), so anything that can detect
		## the player is awake.
		"detection_radius": 16.0,

		# ----- Organic wandering -----
		## A cat's rhythm: long stretches of nothing, then a long stop to watch.
		## Between the bear's amble (6.0 / 1.2) and the crocodile's (4.0 / 0.5).
		"direction_change_interval": 5.0,
		"pause_duration": 1.0,

		## Lazy drift over a snappy body. `turn_smoothness` 6.0 is deliberately
		## high — the burst arm bends no heading at all (it is a SPEED, not a
		## steer), so unlike the bear this animal must be able to follow a target
		## that jinks, or the pounce would miss for the wrong reason.
		"wander_turn_rate": 1.0,
		"turn_smoothness": 6.0,

		## Ebbs the deepest of any moving row (0.4) and varies slowly: a stalk is
		## mostly standing still with the occasional few metres of ground covered.
		## The highest sniff chance in the table for the same reason.
		"min_wander_speed_factor": 0.4,
		"speed_variation_freq": 0.7,
		"sniff_pause_chance": 0.4,

		# ----- Obstacle avoidance -----
		## Look-ahead is ~2x the mesh length, the wolf's ratio, and it earns its
		## keep twice here: once for the ordinary turn, and once as the pounce's
		## only brake. `_avoid_obstacles` applies `avoid_speed_factor` to
		## `current_speed` AFTER the burst multiplier, so a cougar that starts a
		## pounce at a rock face is already halving it by the time it arrives, with
		## no branch anywhere and no key in this row. Narrow feelers (36°) on the
		## narrowest body in the set: this animal is meant to take the gaps.
		"avoid_look_ahead": 3.2,
		"avoid_feeler_angle": PI / 5.0,  # 36°
		## Mid-torso on a 0.64 m animal whose belly line is at 0.36, so the probes
		## sample a block's side wall rather than the air under it.
		"avoid_feeler_height": 0.45,
		"avoid_speed_factor": 0.6,

		# ----- Procedural body animation -----
		## Same nose-along-+X model contract as every predator mesh.
		"model_facing_offset": -PI / 2.0,

		## THE PROWL. Quick feet over almost no roll — a cat's spine stays level
		## where the bear's swings (11°) and the crocodile's waddles (9°). The
		## motion that IS big is `sway_yaw` at 8°, second only to the viper's
		## slither, and it is there to swing the 0.55 m tail: generate_cougar.py's
		## header says the tail is the one part still moving while the cat is
		## otherwise crouched and still, and this is the number that cashes that in.
		"stride_frequency": 11.0,
		"waddle_roll": 5.0 * PI / 180.0,
		"bob_amount": 0.04,
		"sway_yaw": 8.0 * PI / 180.0,

		## Shoulders down, head level — a cat closing is nearly horizontal.
		"chase_pitch": 13.0 * PI / 180.0,

		"breathe_speed": 2.2,
		"breathe_amount": 0.015,

		# ----- River submersion (VISUAL ONLY) -----
		## 0.22 m — the wolf's wade read on a shorter animal. The legs (0 .. 0.36)
		## go most of the way under, the belly line sits 0.14 m proud, and the whole
		## torso, head and the arch of the tail stay in plain view. A cat crossing
		## water is a thing you can see; hiding the one predator that can break the
		## speed ceiling is the last thing this band needs, and the palette note in
		## generate_cougar.py is about the same mistake made with colour.
		##
		## Same hard constraint as every row: VISUAL ONLY. The CharacterBody3D, its
		## CollisionShape3D and global_position never move, so a wading cougar is
		## exactly as dangerous as a dry one.
		"river_sink_depth": 0.22,
		## Same ~0.2 s ease as every other row and as the player, written as
		## depth/time so the derivation survives a retune of the depth.
		"river_sink_ease_speed": 0.22 / 0.2,

		# ----- Bite -----
		## The fastest bite in the table (viper 0.3, wolf 0.35, crocodile 0.5, bear
		## 0.55) over the second-longest lunge. A cat's killing bite is one motion
		## arriving at the end of a leap, and it should land on the same frame the
		## pounce does rather than a beat behind it.
		"bite_duration": 0.28,
		"bite_pitch": 32.0 * PI / 180.0,
		"bite_lunge": 0.5,

		# ----- The pounce (the "burst" behaviour reads these four) -------------
		## THE ONLY FOUR KEYS THAT MAKE THIS ANIMAL, and the same rule as the wolf's
		## two, the viper's two and the bear's one applies: a key a species does not
		## use is a key it does not carry. (enemy_spawn_selfcheck derives its
		## required key set from the CROCODILE row, so behaviour-local keys are
		## allowed — what it forbids is a row MISSING something the crocodile has.)
		##
		## THE CYCLE IS MEASURED IN METRES, NOT SECONDS, for the bear's reason and
		## with the bear's payoff: `_update_chase_state` has no `delta` (see the
		## note on the dispatch), so a timer would have had to be plumbed through
		## every arm — and a distance is LOD-SAFE for free. A slept cougar does not
		## move, so its leg does not drain, and it wakes mid-pounce exactly as it
		## slept. A timer would have run out in its sleep and handed the player a
		## predator that arrives already exhausted.
		##
		## 4.0 m OF POUNCE is ~0.36 s at the clamped speed — roughly the crocodile's
		## whole bite animation, and about two and a half of this animal's own body
		## lengths. Shorter and the burst is a flicker the player cannot read as a
		## pounce; longer and the cycle average climbs toward the run and the escape
		## hatch starts closing (at 6.0 m of pounce against 3.0 of recovery the
		## average is 7.5 m/s, and a 9.0 runner only gains 1.5 m/s).
		"burst_distance": 4.0,

		## 3.0 m OF RECOVERY, and this is the number that keeps the promise. It is
		## deliberately SHORTER in metres than the pounce and far LONGER in time
		## (0.64 s against 0.36 s at the clamp), because it is walked at
		## `recover_factor`. That asymmetry is the exhaustion: the cat spends more
		## of every cycle catching its breath than it does pouncing.
		"recover_distance": 3.0,

		## THE POUNCE ITSELF: 1.3 x the clamped chase speed. At the top of the
		## distance gradient that is 11.05 m/s — above MAX_CHASE_SPEED (8.5) and
		## above the slowest run (9.0), which is precisely what the bead asked for
		## and precisely what nothing else in this game is allowed to do.
		"burst_factor": 1.3,

		## THE EXHAUSTION: 0.55 x, so 4.68 m/s at the clamp — BELOW WALK_SPEED. A
		## recovering cougar is briefly slower than a strolling player, which is the
		## whole counterplay made visible: the moment to move is the moment after it
		## lands. Raise this and the cycle average climbs into the run; drop it much
		## further and the average falls under the walk and the animal stops being
		## able to catch anybody. Both ends are measured in check 8.
		"recover_factor": 0.55,

		## THE STAKE (see the crocodile row): a burst attacker with reach.
		"coin_setback": 0.12,
	},

	## ------------------------------------------------------------------------
	## CITY ALLEY HOUND — the CITY band's predator, and the table's proof that a
	## behaviour can be shared without the two animals feeling alike.
	## ------------------------------------------------------------------------
	## It runs the SAME arm as the cougar above (`behavior: "burst"`) and reads the
	## same four keys, and it is not the same animal in any way a player would
	## notice. The cougar is one enormous lunge every second; the hound is a dog
	## that will not settle to a pace, surging and easing every 0.6 s. Same
	## function, different numbers — which is the SPECIES table's entire argument,
	## finally exercised rather than asserted.
	##
	## WHAT "URBAN PATROL, HIGH TURN RATE, TIGHT CORNERING" IS, MECHANICALLY: it is
	## six numbers in this row and not one line of code. `turn_smoothness` 9.0 and
	## `wander_turn_rate` 1.8 are both the highest in the table (the turn rate);
	## `avoid_look_ahead` 1.8 is the shortest (it commits to a corner late instead
	## of swinging wide around it) and `avoid_feeler_angle` PI/6 the narrowest (it
	## looks for the GAP, not the way round); `avoid_speed_factor` 0.85 is by far
	## the highest, which is the cornering itself — every other predator sheds half
	## its speed to get round a block and this one barely slows. And
	## `direction_change_interval` 2.2 with `pause_duration` 0.3 is the shortest
	## rhythm in the table: a patrolling dog turns down another street.
	##
	## WHY THE CITY GETS IT, and how it reads against CITY_CROC_DIVISOR. The city is
	## the SAFE band by design — endless_terrain divides its predator target by 2.5
	## (an owner call: a city is not croc-free, it is QUIETER) and roofs are the
	## real shelter. So the few animals that ARE there each have to carry the whole
	## band's threat, and the way to do that without raising the count or the
	## ceiling is to make one hound harder to shake in a straight alley than a
	## crocodile is in the open. The burst does that: the sprint is 9.18 m/s at
	## nominal, faster than the slowest character's run, for the two and a half
	## metres an alley mouth is wide. It cannot sustain it (see below), so the band
	## stays escapable — it just stops being a stroll.
	##
	## Geometry measured off assets/models/characters/hound.glb (built by
	## scripts/generate_hound.py): 1.1843 m nose to tail (x -0.5700 .. +0.6143),
	## 0.2382 m across (z ±0.1191) and 0.6060 m TALL. It is the SMALLEST predator in
	## the set on every axis — shorter than the bear (1.2154), narrower than the
	## cougar (0.2470), lower than the wolf (0.740) — and generate_hound.py's header
	## says that is the point: it shares the wolf's build, so the two only stay apart
	## on screen by size, floppy ears, an upright tail and the rust coat.
	##
	## THE CAPSULE IN alley_hound.tscn COMES OFF THE SAME THREE FIGURES, recorded
	## here because a .tscn cannot hold a comment an editor resave will not eat.
	## `radius = 0.1191, height = 1.20`, laid down on the travel axis with the
	## crocodile's basis, at `(0, 0.1191, 0.022)`:
	##   * 0.1191 is EXACTLY the mesh's half-width, the same fit rule every row
	##     above follows, and the smallest shape in the set. On the animal whose
	##     whole read is threading alleys, a capsule any wider than the dog would
	##     stop it in gaps a dog fits through.
	##   * 1.20 covers the 1.1843 m length with the caps included.
	##   * radius == centre y puts the capsule's bottom on y = 0, so gravity settles
	##     the mesh's own paws onto the ground plane.
	##   * z = +0.022 is the mesh's own midpoint. The wolf's row drops its +0.013 as
	##     noise; this one keeps its 22 mm because the hound is the SHORTEST animal
	##     in the set, so the same absolute offset is twice the fraction of the body
	##     — and it costs nothing to be exact.
	"alley_hound": {
		## The same arm as the cougar, and the whole reason it is called "burst"
		## rather than "pounce": a behaviour name describes the MECHANIC, so a
		## second animal can mean something else by it. See _behave_burst().
		"behavior": "burst",

		# ----- Speed and detection -----
		## THE LATTICE, WITH THE SAME ONE EXCEPTION THE COUGAR TAKES: 5.0
		## (WALK_SPEED) < 6.8 <= 8.5 (MAX_CHASE_SPEED) < 9.0 (the slowest run). The
		## sustained speed is clamped exactly like every other row (6.8 x 1.15 x 1.6
		## = 12.5, cut to 8.5) and only the sprint goes above it.
		##
		## THE CYCLE AVERAGE IS WHAT ESCAPES, and it is measured in check 8 the same
		## way as the cougar's:
		##
		##     avg = V x 4.5 / (2.5 / 1.35 + 2.0 / 0.6) = V x 0.8679
		##
		## At the worst case (V clamped to 8.5) that is 7.38 m/s against a 9.0 run —
		## the runner gains 1.62 m/s, a tighter margin than the cougar's 2.03 and
		## the tightest in the game, which is what makes this the band's real threat
		## despite the thinned count. At the other end 0.8679 x 6.8 = 5.90 m/s,
		## comfortably over WALK_SPEED, so walking is still caught.
		##
		## move_speed 3.2 is the FASTEST cruiser in the table (wolf 3.0, crocodile
		## 2.5, cougar 2.2, bear 1.6) and that is the "patroller" half of the spec
		## stated as a number: this animal covers ground when it is not hunting
		## anything at all.
		"move_speed": 3.2,
		"chase_speed": 6.8,

		## ±15% / ±15%, the cougar's spreads for the cougar's reason: both ends of
		## this row's promise move with the roll. At the bottom roll (V = 5.78) the
		## cycle average is 5.02 m/s — still, just, above the walk.
		"speed_random_factor": 0.15,
		"size_random_factor": 0.15,

		## 13.0 — the shortest of any non-ambusher (crocodile 15, cougar 16, wolf
		## 18), and short ON PURPOSE rather than as a nerf. A city chunk is walls;
		## an animal that acquired you at the wolf's 18 m would mostly be acquiring
		## you through a building, and the band's whole read is that the danger
		## starts at the corner. INVARIANT, unchanged and not negotiable: far below
		## the LOD manager's SIM_RADIUS (45.0), so anything that can detect the
		## player is awake.
		"detection_radius": 13.0,

		# ----- Organic wandering -----
		## The shortest rhythm in the table by some way (the wolf's 3.0 / 0.35 was
		## the previous record). A patrolling dog turns down another street every
		## couple of seconds and barely stops when it does.
		"direction_change_interval": 2.2,
		"pause_duration": 0.3,

		## THE TURN RATE, and both numbers are the table's highest. `turn_smoothness`
		## 9.0 against the wolf's 7.0 and the bear's 3.0 is the load-bearing one:
		## velocity is driven from the body's FACING (see _physics_process), so this
		## is literally how fast the animal can change where it is going. It is the
		## exact opposite end of the same dial the bear's 3.0 sits on — that row
		## calls a slow lerp_angle "momentum", and this one is what having none
		## looks like.
		"wander_turn_rate": 1.8,
		"turn_smoothness": 9.0,

		## Ebbs the shallowest in the table and varies the fastest: this animal is
		## never really standing still.
		"min_wander_speed_factor": 0.6,
		"speed_variation_freq": 1.2,
		"sniff_pause_chance": 0.3,

		# ----- Obstacle avoidance -----
		## TIGHT CORNERING, and all three numbers are it. `avoid_look_ahead` 1.8 is
		## ~1.5x the mesh length and the SHORTEST ratio in the table (the bear's is
		## ~3x): this animal commits to a corner late rather than swinging wide
		## around it, which is only survivable because it can turn. The feelers are
		## the narrowest at 30°, so they sweep a corridor about as wide as the dog
		## actually is and it aims for gaps instead of detours. And 0.85 is the
		## highest `avoid_speed_factor` by a distance — everything else in the table
		## sheds 35-50% of its speed to get around a block and this one sheds 15%.
		##
		## THAT LAST NUMBER ALSO MEETS THE SPRINT, and the interaction is the good
		## kind: `_avoid_obstacles` multiplies it onto `current_speed` AFTER the
		## burst factor, so a cougar pouncing into a wall loses 40% of a huge number
		## and a hound cornering mid-sprint loses 15% of a smaller one. Same two
		## lines of shared code, two completely different animals come out.
		"avoid_look_ahead": 1.8,
		"avoid_feeler_angle": PI / 6.0,  # 30°
		## Mid-torso on a 0.61 m animal whose belly line is at 0.34, so the probes
		## sample a block's side wall rather than the air under it. The wolf's 0.45
		## would fire over this smaller dog's back.
		"avoid_feeler_height": 0.42,
		"avoid_speed_factor": 0.85,

		# ----- Procedural body animation -----
		## Same nose-along-+X model contract as every predator mesh.
		"model_facing_offset": -PI / 2.0,

		## THE SCURRY. The fastest stride in the table (viper 12, wolf 10) over
		## almost no roll — short legs turning over quickly under a body that stays
		## level. The bob is nearly the wolf's on an animal five-sixths its height,
		## which is what a small dog's bouncing trot looks like.
		"stride_frequency": 13.0,
		"waddle_roll": 3.0 * PI / 180.0,
		"bob_amount": 0.045,
		"sway_yaw": 7.0 * PI / 180.0,

		## The shallowest chase lean of the four new species: this dog runs with its
		## head up, which is also what keeps the cream chest blaze
		## (generate_hound.py) pointed at the player.
		"chase_pitch": 11.0 * PI / 180.0,

		"breathe_speed": 2.8,
		"breathe_amount": 0.018,

		# ----- River submersion (VISUAL ONLY) -----
		## 0.20 m — the wolf's and cougar's wade read on the smallest body in the
		## set. Legs (0 .. 0.34) mostly under, belly line 0.14 m proud, torso and
		## head in plain view. Rivers barely cross the city band anyway; what this
		## number buys is that a hound chasing you into one does not vanish.
		##
		## Same hard constraint as every row: VISUAL ONLY. The CharacterBody3D, its
		## CollisionShape3D and global_position never move.
		"river_sink_depth": 0.20,
		## Same ~0.2 s ease as every other row and as the player, written as
		## depth/time so the derivation survives a retune of the depth.
		"river_sink_ease_speed": 0.20 / 0.2,

		# ----- Bite -----
		## A snap, between the viper's strike (0.3) and the wolf's (0.35), over the
		## crocodile's lunge. A small dog bites and lets go.
		"bite_duration": 0.3,
		"bite_pitch": 28.0 * PI / 180.0,
		"bite_lunge": 0.4,

		# ----- The sprint (the "burst" behaviour reads these four) -------------
		## THE SAME FOUR KEYS AS THE COUGAR, MEANING A DIFFERENT ANIMAL. Read the
		## two sets side by side — 4.0/3.0/1.3/0.55 against 2.5/2.0/1.35/0.6 — and
		## the difference is almost entirely the CYCLE LENGTH: the cougar's is
		## 1.00 s at the clamp and this one's is 0.61 s. One pounce a second reads
		## as a cat committing; nearly two surges a second reads as a dog that
		## cannot hold a pace, which is what "rapid short-burst" asks for.
		##
		## 2.5 m OF SPRINT is about an alley's width and about two of this dog's
		## body lengths — deliberately short enough that the sprint fits BETWEEN
		## two corners rather than through one, which is what makes the cornering
		## numbers above matter instead of being decoration.
		"burst_distance": 2.5,

		## 2.0 m OF RECOVERY, the shortest leg in either row, and the same
		## metres-not-seconds and LOD-safety arguments as the cougar's (see there).
		## Its ratio to the sprint is deliberately TIGHTER than the cougar's
		## (2.0/2.5 against 3.0/4.0), which is where the hound's higher cycle
		## average — and its tighter escape margin — comes from.
		"recover_distance": 2.0,

		## THE SPRINT: 1.35 x the clamped chase speed, a hair above the cougar's
		## 1.3, so the peak is 11.48 m/s at the top of the distance gradient and
		## 9.18 m/s at nominal. Above MAX_CHASE_SPEED either way, and at nominal
		## just above the slowest character's run — for 0.22 s at a time.
		"burst_factor": 1.35,

		## THE BLOWN LUNG: 0.6 x, so 5.1 m/s at the clamp. Shallower than the
		## cougar's 0.55 because a dog that has run 2.5 m is winded, not spent —
		## and because this row's whole margin is tighter on purpose. It is still
		## below the clamped chase speed at every roll, which is what makes the
		## recovery a real window rather than a slight ease.
		"recover_factor": 0.6,

		## THE STAKE (see the crocodile row): a burst attacker, ordinary bill.
		"coin_setback": 0.10,
	},

	## ------------------------------------------------------------------------
	## SNOW TITAN — the SNOW band's BOSS, and the game's first RANGED enemy.
	## ------------------------------------------------------------------------
	## Owner, verbatim: "titans is like titans from might and magic 3", "titan
	## should be slow, they are archers", "titan not trying to bite you, they
	## throw a electric arrow like thunderstorm, likely it slow, so we can move
	## and dodge it".
	##
	## THIS ROW IS BOSS-ONLY. Nothing in BIOME_SPECIES points at it — it is
	## reached exclusively through endless_terrain's BIOME_BOSS[SNOW], so every
	## titan in the world arrives through setup_as_boss(): giant, territorial,
	## crush-immune, one-shot lethal on contact, and unkillable. That is why the
	## numbers below read strangely against the other six rows, and why they are
	## not a lattice violation:
	##
	##   IT IS SLOWER THAN A WALKING PLAYER, ON PURPOSE. `chase_speed` 3.0 is
	##   well under WALK_SPEED (5.0), so a titan cannot catch anybody who keeps
	##   moving. The lattice exists to guarantee ESCAPE ("walking is caught,
	##   running escapes") and a boss you can stroll away from sits at the easy
	##   end of that promise, not outside it. Its threat is not its feet, it is
	##   the bolt — and the bolt's fairness is a MEASURED contract
	##   (projectile_selfcheck reads the "ranged" dict below and proves a WALKING
	##   player clears it by 3x the hit radius). enemy_spawn_selfcheck ASSERTS
	##   the sub-walk speeds rather than merely tolerating them, so "slow archer"
	##   cannot quietly be retuned into "fast melee giant holding a bow".
	"titan": {
		## The fifth arm, and the only one that SPAWNS anything: `_behave_ranged`
		## is one cooldown and one BossProjectile.fire() call. Everything about
		## the bolt itself — flight, visuals, lethality, lifetime, the per-shooter
		## cap — lives in scripts/boss_projectile.gd and is shared with every
		## ranged enemy that follows this one.
		"behavior": "ranged",

		# ----- Speed and detection -----
		## A giant archer's stroll, and its barely-a-pursuit. Both are BELOW
		## WALK_SPEED (5.0) — see the block above for why that is the design and
		## not a hole in the lattice.
		"move_speed": 2.2,
		"chase_speed": 3.0,

		## THE BOSS SPEED OVERRIDE, OPTED OUT OF. A boss normally throws its row's
		## chase speed away and takes the game-wide BOSS_CHASE_SPEED (7.0) — a
		## boss is a MODIFIER on a species. The titan is the one row where that
		## modifier would contradict the animal: at 7 m/s it would run down a
		## walking player, i.e. be exactly the melee giant the owner said it is
		## not. So the row states its own boss speed, `_ready()` reads it through
		## `spec.get("boss_chase_speed", BOSS_CHASE_SPEED)`, and every other row
		## (present and future) is untouched by this key existing.
		##
		## It is the same number as `chase_speed` deliberately: a titan has ONE
		## speed, and the two slots exist only because a boss and a plain predator
		## read different ones. Both are asserted sub-walk by the selfcheck, so
		## neither is dead data free to drift.
		"boss_chase_speed": 3.0,

		## Bosses take no per-instance rolls at all (see _ready), so these are
		## zero rather than a spread that would never be drawn: a titan's size is
		## the terrain's deterministic boss schedule and its speed is the row.
		"speed_random_factor": 0.0,
		"size_random_factor": 0.0,

		## A boss overrides this with BOSS_DETECTION_RADIUS (25.0), so what this
		## number says is the intent: 22 is also `ranged.max_fire_range`, i.e. the
		## titan starts shooting the moment it acquires you rather than spending
		## the first metres of an engagement walking. Keep the two in step.
		"detection_radius": 22.0,

		# ----- Organic wandering -----
		## A giant is slow to change its mind and stands a long time when it does:
		## twice the crocodile's interval and pause.
		"direction_change_interval": 8.0,
		"pause_duration": 1.2,
		"wander_turn_rate": 0.5,
		## The heaviest turn in the table (the crocodile's is 5.0, the hound's
		## 7.0). Mass reads as turn lag more than as anything else.
		"turn_smoothness": 2.5,
		"min_wander_speed_factor": 0.5,
		"speed_variation_freq": 0.4,
		"sniff_pause_chance": 0.25,

		# ----- Obstacle avoidance -----
		## Longer feelers than any quadruped's, cast from higher up: this body is
		## a 1.8 m humanoid BEFORE the 3.75x-9x boss scale, so a probe at the
		## crocodile's 0.3 m would sample the snow under its knees.
		"avoid_look_ahead": 4.0,
		"avoid_feeler_angle": PI / 5.0,  # 36°
		"avoid_feeler_height": 1.0,
		"avoid_speed_factor": 0.6,

		# ----- Procedural body animation -----
		## -PI/2, the standard enemy/boss facing offset. titan.glb is authored
		## nose/front-along-+X (the toolkit's first contract) and the body travels
		## +Z, so the model rotates -90°.
		##
		## THE CAPSULE IN titan.tscn IS RECORDED HERE for the reason the viper's
		## is: a .tscn cannot hold a comment an editor resave will not eat.
		## titan.glb spans x -0.48..+0.76, z ±0.45 and stands 1.91 m tall. The
		## capsule is `radius = 0.45, height = 1.91` at `(0, 0.955, 0)`, UPRIGHT —
		## no lay-down rotation, the one thing this scene does that the
		## quadrupeds' do not:
		##   * 1.91 is the mesh's full standing height, and centre
		##     0.955 = height/2 puts its bottom exactly on y = 0 (the same
		##     identity the crocodile's 0.16/0.16 and the viper's 0.11/0.11 use),
		##     so the gravity settle rests the feet on the flat world's ground.
		##   * 0.45 covers the ±0.45 m half-width across the shoulders and
		##     pauldrons, and is inside endless_terrain's
		##     BOSS_FOOTPRINT_RADIUS_PER_SCALE (0.7), the clearance every boss
		##     candidate is judged against.
		##   * THE RAISED ARM AND ITS JAVELIN REACH PAST THE CAPSULE (out to
		##     x +0.76 against a 0.45 radius) and that is the green dragon's wing
		##     deal exactly: collision is the BODY, and pricing a held weapon into
		##     the footprint would cost the snow band boss stations for a surface
		##     nothing can stand on.
		## The body scale from the boss schedule multiplies all of it, so a 9x
		## titan is a 17.19 m capsule around a 17.19 m model.
		"model_facing_offset": -PI / 2.0,

		## A slow, heavy tread with almost no waddle — the read is a colossus
		## planting its feet, not an animal scurrying.
		"stride_frequency": 3.5,
		"waddle_roll": 3.0 * PI / 180.0,
		"bob_amount": 0.06,
		"sway_yaw": 2.0 * PI / 180.0,
		## Barely any chase lean: an archer draws upright.
		"chase_pitch": 3.0 * PI / 180.0,
		"breathe_speed": 1.1,
		"breathe_amount": 0.03,

		# ----- River submersion (VISUAL ONLY) -----
		## 0.55 m on a 1.8 m biped is mid-thigh — the same fraction of the body
		## the quadruped rows put under, measured off a mesh that STANDS instead
		## of lying down. Scales with boss_scale for free (the model is a child of
		## the scaled body), exactly like every other row.
		##
		## Same hard constraint as every row: VISUAL ONLY. The CharacterBody3D,
		## its CollisionShape3D and global_position never move.
		"river_sink_depth": 0.55,
		"river_sink_ease_speed": 0.55 / 0.2,

		# ----- Bite -----
		## A titan you let walk into you still kills you — contact is one-shot
		## lethal for every boss, there is no health pool. It is a slow overhead
		## STOMP rather than a chomp, so the animation is long, shallow and barely
		## lunges. Being hit by this is a choice; the bolt is the real threat.
		"bite_duration": 0.7,
		"bite_pitch": 10.0 * PI / 180.0,
		"bite_lunge": 0.5,

		# ----- The thunder bolt (the "ranged" behaviour reads this) -----------
		## A COPY of BossProjectile.STYLES["thunder_bolt"] plus the three keys
		## that are the AI's business rather than the projectile's. Copied and not
		## referenced because those three have to live somewhere, and adding them
		## to the shared STYLES dict would hand them to every future shooter. The
		## two sets are measured INDEPENDENTLY by projectile_selfcheck (it scans
		## STYLES *and* every "ranged" row), so a drift between them fails the
		## fairness contract on whichever side broke rather than hiding.
		##
		## The flight numbers and their argument belong to boss_projectile.gd —
		## read its STYLES entry, not this copy, for why 7 m/s and 0.9 m are the
		## numbers. In one line: from its 10 m minimum the bolt is 1.43 s in the
		## air, in which a WALKING player covers 7.1 m against a 0.9 m hit radius.
		"ranged": {
			"style": "thunder_bolt",
			"trajectory": "straight",
			"speed": 7.0,
			"gravity": 0.0,
			"hit_radius": 0.9,
			"min_fire_range": 10.0,
			"max_range": 32.0,
			"lifetime": 6.0,
			"max_live": 2,
			"color": Color(0.65, 0.85, 1.0),
			"mesh_scale": Vector3(0.18, 0.18, 0.95),

			## ---- Read by _behave_ranged(), never by the projectile ----------
			## SECONDS BETWEEN SHOTS, and the whole difficulty dial of this boss.
			## Deliberately long: a bolt from the far end of the firing band is
			## ~3.1 s in the air, so at this cadence there is at most one or two
			## in flight and the player always gets a gap between the dodge and
			## the next telegraph. `max_live` 2 above is the backstop if this is
			## ever shortened.
			"fire_cooldown": 3.0,

			## THE FIRING BAND, together with `min_fire_range` above.
			##
			## The FLOOR (10 m) is the projectile's own: closer than that the bolt
			## arrives faster than a walking player can clear the hit radius, so
			## the ARM refuses to fire rather than the style being retuned. Get
			## close to a titan and it stops shooting and has to try to STOMP you,
			## which it is far too slow to manage — that is the counterplay the
			## shape of this boss offers, and it costs no code beyond this number.
			##
			## The CEILING (22 m) sits inside BOSS_DETECTION_RADIUS (25), so the
			## band is fully contained in what a titan can smell — the arm only
			## runs while chasing, so a wider ceiling would simply never fire —
			## and well inside BOSS_TERRITORY_RADIUS (32), which is also the
			## bolt's own max_range: a titan cannot snipe you out of a territory
			## you have already walked out of.
			"max_fire_range": 22.0,

			## Height of the drawn bow above the body origin, in MODEL-LOCAL
			## metres — _behave_ranged multiplies it by the body's scale, so a 9x
			## titan fires from 13.5 m up and a 3.75x one from 5.63 m, which keeps the
			## muzzle at the shoulder of whatever size the schedule handed out.
			## 1.5 is shoulder height on the 1.8 m humanoid mesh.
			"muzzle_height": 1.5,
		},

		## THE STAKE (see the crocodile row): the heaviest thing that walks.
		"coin_setback": 0.25,
	},
	## ------------------------------------------------------------------------
	## GREEN DRAGON — the FOREST band's BOSS, and the cheapest row in this table.
	## ------------------------------------------------------------------------
	## Owner, verbatim: "green dragons for forest".
	##
	## THIS ROW SHIPPED BORING AND STAYED MOSTLY BORING. When it landed it was
	## `behavior: "solo"` — thirty numbers, one .tscn and one BIOME_BOSS line, and
	## not a character of new logic anywhere — which was the family seam working.
	## What changed it is the owner, verbatim: "let those Rock and Dragons be able
	## to make a decent jumps like windman does with F key." It is now
	## `behavior: "leap"` and carries five more numbers at the bottom of the row;
	## everything ELSE about it is still inherited boss behaviour, and between hops
	## it hunts on the ground exactly as it did before. See `_behave_leap()` — one
	## arm, shared with the roc, and nothing here branches on the animal.
	##
	## BOSS-ONLY, like the titan: nothing in BIOME_SPECIES points here, so every
	## green dragon in the world arrives through BIOME_BOSS[FOREST] and therefore
	## through setup_as_boss() — giant, territorial (it hunts inside
	## BOSS_TERRITORY_RADIUS and never leaves), crush-immune, stink-immune,
	## unkillable, one-shot lethal on contact. All of it inherited from
	## boss-ness; none of it stated here.
	##
	## IT TAKES THE DEFAULT BOSS SPEED, AND THAT IS A DECISION. `boss_chase_speed`
	## exists (see the titan, which opts out at 3.0 because an archer that runs
	## you down is not an archer) and this row deliberately does NOT carry it: a
	## melee territorial dragon is exactly the animal BOSS_CHASE_SPEED (7.0) was
	## written for — over WALK_SPEED (5.0) so strolling out of its territory gets
	## you eaten, under MAX_CHASE_SPEED (8.5) and so under the slowest run (9.0)
	## so sprinting for the fence always works. A melee boss is the case where
	## that lattice matters most, which is why it takes the default rather than
	## a number of its own.
	##
	## PURPOSE-BUILT, MEASURED (bead lce.7 — the placeholder was piglet_crocodile.glb
	## stretched to (1, 1.6, 1)). scenes/characters/green_dragon.tscn instances
	## green_dragon.glb at IDENTITY: a quadruped on `predator_parts.quadruped` with
	## WINGS off the toolkit's `wings` primitive, swept horns and a bone ridge down
	## the spine, built by scripts/generate_green_dragon.py. Read that file for the
	## palette (measured against the forest floor) and the wing geometry. THE WINGS
	## ARE SILHOUETTE, NOT FLIGHT — this world is flat, nothing flies, and the hop
	## at the bottom of this row is the whole of the animal's verticality.
	##
	## THE MESH IS 1.3065 LONG (x -0.653 .. +0.653), 0.7408 TALL and 0.8100 ACROSS,
	## recorded here because the geometry keys are model numbers and a .tscn cannot
	## hold a comment an editor resave will not eat. The capsule in
	## green_dragon.tscn is `radius = 0.371, height = 1.306`, laid on the travel
	## axis with the crocodile's basis, at `(0, 0.371, 0)`:
	##   * 0.371 makes a 0.742 m tube around the 0.7408 m standing height — the
	##     viper's tightest-fit rule, applied to the tallest axis.
	##   * 1.306 is the nose-to-tail length, caps included, so the horizontal reach
	##     is 0.653 — inside endless_terrain's BOSS_FOOTPRINT_RADIUS_PER_SCALE
	##     (0.7), which is the clearance every boss candidate is judged against.
	##     The reach of a LAID capsule is its offset PLUS its half-length, which is
	##     why generate_green_dragon.py shifts the finished animal onto its own
	##     x-midpoint: an off-centre mesh spends that 0.7 twice and at the 9x cap
	##     lands the dragon inside the tree it was placed clear of.
	##   * radius == centre y, the crocodile/viper/hunter identity, so the
	##     capsule's bottom sits exactly on y = 0 and the body rests on the flat
	##     world's ground plane.
	##   * z = 0: the mesh is centred on its own origin.
	## THE WINGS REACH PAST THE CAPSULE (0.405 either side against a 0.371 radius)
	## AND THAT IS DELIBERATE. Collision is the body; a wing you can walk through
	## is the same deal every other model's tail already makes, and pricing the
	## wingspan into the capsule would cost the mountain and forest bands boss
	## stations for a surface nothing can stand on.
	## The boss schedule's `scale = ONE * boss_scale` multiplies all of it, so a
	## 9x dragon is an 11.7 m capsule around a 6.6 m tall model.
	"green_dragon": {
		## THE SEVENTH ARM, shared with the roc: a bounded hop with an arc and a
		## grounded recovery window (`_behave_leap`). Everything the row does NOT
		## say is still "solo" — the shared code above the behaviour `match` —
		## because an arm only adds; between hops this is the same melee
		## territorial boss it was, wandering its circle and chasing what it
		## smells. The five `leap_*` keys at the bottom of the row are the whole
		## of the difference.
		"behavior": "leap",

		# ----- Speed and detection -----
		## The crocodile's numbers, unchanged and on purpose. A boss overrides
		## both at spawn — `move_speed` is read straight through, and the chase
		## speed is replaced by BOSS_CHASE_SPEED because this row states no
		## `boss_chase_speed` — so what these buy is not gameplay but LATTICE
		## HYGIENE: 5.5 sits in (WALK_SPEED, MAX_CHASE_SPEED] like every ordinary
		## row, so if a later bead ever gives the dragon a BIOME_SPECIES entry it
		## is already a legal predator instead of a slow-archer exemption nobody
		## re-examined.
		"move_speed": 2.5,
		"chase_speed": 5.5,

		## Zero, not a spread — the titan's reasoning verbatim: a boss takes no
		## per-instance rolls (see the is_boss branch in _ready()), so a factor
		## here would be a number that is never drawn. Stating 0.0 says "this
		## animal has one size and one speed" instead of leaving a spread that
		## reads as live and is not.
		"speed_random_factor": 0.0,
		"size_random_factor": 0.0,

		## Also overridden at spawn (BOSS_DETECTION_RADIUS, 25). The crocodile's
		## 15 is kept for the same hygiene reason as the speeds, and it honours
		## the game-wide LOD invariant either way: well under
		## crocodile_lod_manager's SIM_RADIUS (45), so a dragon that can smell
		## you is always awake.
		"detection_radius": 15.0,

		# ----- Organic wandering -----
		## Slower and lazier than the crocodile's rhythm: a territorial animal
		## patrolling ground it owns, not a scavenger casting about. It has
		## nowhere to be — the leash keeps it inside its own circle regardless.
		"direction_change_interval": 5.0,
		"pause_duration": 0.6,
		"wander_turn_rate": 0.9,
		"turn_smoothness": 4.0,
		"min_wander_speed_factor": 0.45,
		"speed_variation_freq": 0.7,
		"sniff_pause_chance": 0.25,

		# ----- Obstacle avoidance -----
		## Feelers cast from higher up than the crocodile's, because this body is
		## 1.6x taller before the boss scale and FOREST is the densest tree cover
		## in the world — a probe at the crocodile's 0.3 m would sample bark below
		## the dragon's own knee. Reach is a little longer too, so a heavy animal
		## with a slower turn (see turn_smoothness) starts its curve sooner.
		"avoid_look_ahead": 3.5,
		"avoid_feeler_angle": PI / 5.0,  # 36°
		"avoid_feeler_height": 0.5,
		"avoid_speed_factor": 0.5,

		# ----- Procedural body animation -----
		## -PI/2, the quadruped default and UNCHANGED by the lce.7 model swap:
		## green_dragon.glb is a predator_parts build, so it is authored
		## nose-along-+X exactly as the crocodile placeholder was, and the body
		## travels +Z. (The naga is the counter-example that makes this worth
		## restating — its placeholder was a humanoid facing -Z, so its offset had
		## to move with the mesh. A row's facing offset is a property of the MESH.)
		"model_facing_offset": -PI / 2.0,

		## A heavy, deliberate gait. Everything here is the crocodile's read
		## slowed and deepened — a big animal covering the same ground in fewer,
		## longer strides. Authored against the placeholder and kept through the
		## lce.7 model swap on purpose: the new mesh is the same kind of animal
		## (a quadruped, nose-along-+X, feet at y = 0) and a gait is not art.
		"stride_frequency": 5.5,
		"waddle_roll": 6.0 * PI / 180.0,
		"bob_amount": 0.05,
		"sway_yaw": 4.0 * PI / 180.0,
		## A deep predatory lean when it commits to you.
		"chase_pitch": 14.0 * PI / 180.0,
		"breathe_speed": 1.4,
		"breathe_amount": 0.02,

		# ----- River submersion (VISUAL ONLY) -----
		## 0.29, unchanged across the lce.7 model swap and re-derived rather than
		## re-typed: it was the crocodile's 0.18 carried through the placeholder's
		## 1.6x stretch, and on the purpose-built mesh it is the LEG LENGTH
		## (generate_green_dragon.py's `leg_len` 0.30). Both readings put the water
		## line at the belly, so the number stands. The sink is written in
		## MODEL-LOCAL metres and applied to `model.position.y`, which is in the
		## BODY's frame, so a Model node's own scale never touches it — which is
		## exactly how this key goes silently wrong when a mesh is replaced with
		## one of a different height and the depth is left as an inherited constant
		## nobody re-measured.
		##
		## Same hard constraint as every row: VISUAL ONLY. The CharacterBody3D,
		## its CollisionShape3D and global_position never move, so a wading dragon
		## is exactly as dangerous as a dry one.
		"river_sink_depth": 0.29,
		"river_sink_ease_speed": 0.29 / 0.2,

		# ----- Bite -----
		## A dragon's snap: slower to wind up than the crocodile's 0.5 s chomp,
		## further through, and lunging harder. Contact is one-shot lethal for
		## every boss — there is no health pool and this animation is the only
		## warning you get.
		"bite_duration": 0.6,
		"bite_pitch": 30.0 * PI / 180.0,
		"bite_lunge": 0.5,

		# ----- The hop (the "leap" behaviour reads these five) -----------------
		## Owner, verbatim: "a decent jump like windman does with F key". The
		## reference is real and it is measured: Windman's F leaves the ground at
		## JUMP_VELOCITY (10.2) under a gravity he softens to 1.62, and an ordinary
		## jump in this game apexes at 10.2^2 / (2 * 14.4) = 3.61 m. THIS ARC IS
		## PITCHED AT THAT SAME APEX so a dragon's bound reads as tall as the one
		## the player already has a feel for: 8.0^2 / (2 * 9.0) = 3.56 m, over an
		## airtime of 2 * 8.0 / 9.0 = 1.78 s. The numbers are the row's own rather
		## than borrowed from GRAVITY (9.8) because gravity in this project is
		## per-script and deliberately unphysical — see `_behave_leap`, which adds
		## the difference back on top of the file's constant every airborne frame.
		"leap_launch_speed": 8.0,
		"leap_gravity": 9.0,

		## THE BURST'S ARGUMENT, IN SECONDS INSTEAD OF METRES, and it is the same
		## deliberate break of the game's tightest contract the cougar's row spells
		## out at length. A boss's chase speed resolves to BOSS_CHASE_SPEED (7.0)
		## scaled by the distance gradient and clamped to MAX_CHASE_SPEED (8.5), so
		## at the worst the game can produce this hop touches 8.5 x 1.25 = 10.63
		## m/s — above the ceiling AND above the slowest character's run (9.0). It
		## is bounded by physics rather than by a rule: the hop lasts exactly the
		## 1.78 s of its own arc and cannot be extended, re-triggered or steered.
		##
		## AND IT IS PAID FOR TWICE. The 3.0 s of grounded recovery below is spent
		## at 0.85 of the ordinary chase speed, so the CYCLE average is
		##   (1.25 x 1.78 + 0.85 x 3.0) / (1.78 + 3.0) = 0.999 x chase
		## — a hair UNDER an ordinary chase. That is the whole design intent: the
		## leap changes how a dragon READS, not how hard it is. Running still
		## escapes across the full hop-and-recovery cycle (8.49 m/s against a 9.0
		## run) and walking still gets you caught (6.99 m/s against a 5.0 walk),
		## both measured over repeated cycles — against a negative control with the
		## recovery removed, which catches the runner — by enemy_spawn_selfcheck's
		## leap probe. Retune any of the five and that probe re-derives the
		## inequality; do not hand-check it here.
		"leap_speed_factor": 1.25,
		"leap_cooldown": 3.0,
		"leap_recover_factor": 0.85,

		## REACH, because it is what the leash actually judges: 1.78 s x 8.5 x 1.25
		## = 18.9 m at the worst case, 15.6 m at the nominal 7.0. Both are well
		## inside BOSS_TERRITORY_RADIUS (32), so a dragon standing anywhere near its
		## home can always find a legal landing; near its fence the projected
		## landing falls outside and `_behave_leap` simply does not launch. That
		## refusal is the mechanism — read its docstring before retuning the arc,
		## because a reach past 32 would be a boss that can only hop from home.

		## THE STAKE (see the crocodile row): a boss bite, near the top of the
		## range.
		"coin_setback": 0.22,
	},

	## ------------------------------------------------------------------------
	## THE FOUR THAT COMPLETE THE FAMILY — hydra, naga, roc, clown.
	## ------------------------------------------------------------------------
	## Owner, verbatim: PLAINS "Hydras, like in Bog castle in hmm3"; DESERT "Nags
	## inspired by hmm3"; MOUNTAIN "let it be huge rock birds, like in barbarian
	## castle in hmm3"; CITY "let it be clown like in 'It' of King (inspired)" +
	## "let's clown thrown ice cream or like that also". FIVE HMM3 CREATURES AND
	## ONE STEPHEN KING REFERENCE IS THE DESIGN, not a slip: the city is the band
	## where uncanny-and-out-of-place is the read. Do not "correct" the clown.
	##
	## THEY COST WHAT THE DRAGON COST, WHICH IS THE WHOLE POINT OF THE SEAM. Three
	## of them are `behavior: "solo"` — the code above the dispatch `match`, which
	## has no arm at all on purpose — and the fourth reuses the titan's `"ranged"`
	## arm UNCHANGED, differing from it only in the numbers of its "ranged" dict.
	## Not one character of new logic lands with these four rows; everything that
	## makes them bosses (territorial, unkillable, crush- and stink-immune,
	## one-shot lethal on contact, giant) is inherited from boss-ness and stated
	## nowhere below. With these four, BIOME_BOSS is TOTAL over the Biome enum and
	## the crocodile survives as a boss only on RIVER stations (the is_river_at
	## overlay, which overrides the band) and as the degrade path for a row whose
	## scene fails to load — both still measured, by enemy_spawn_selfcheck check
	## 11's river gate and by boss_selfcheck's crocodile subject respectively.
	##
	## EACH MODEL BELOW SAYS WHETHER IT IS A PLACEHOLDER, the same art-decoupling
	## convention the titan (a re-skinned Teibi) and the clown (a re-skinned
	## Phoboman) still ship under. The purpose-built meshes are their own art beads
	## — lce.6 (serpentine builders: naga + hydra, LANDED), lce.7 (winged pair: roc
	## + dragon, LANDED), lce.8 (humanoids: titan + clown) — and when they land
	## only the .tscn and the measured geometry in these comments change, never a
	## line of behaviour. lce.6 is the one counter-example and it proves the rule:
	## naga.glb is authored nose-along-+X where the humanoid placeholder faced -Z,
	## so its `model_facing_offset` moved with the mesh. A row's facing offset is a
	## property of the MESH, not of the animal — and the corollary held for lce.7,
	## where both winged rows keep -PI/2 because a predator_parts build faces the
	## same way the toolkit placeholders they replaced did.
	##
	## THE ONE HARD PLACEMENT CONSTRAINT ON EVERY SCENE HERE, restated from the
	## dragon's row because it is the rule that bites: endless_terrain's
	## BOSS_FOOTPRINT_RADIUS_PER_SCALE (0.7) is the clearance every boss candidate
	## is judged against, so no scene here may have a collision capsule reaching
	## further than 0.7 m horizontally at body scale 1. On a placeholder that is
	## what the horizontal DOWN-scale is for (0.75 on the clown's phoboman): it is
	## placement arithmetic, not an art choice. On a purpose-built mesh it is the
	## generator's job instead — every one of them holds its own nose-to-tail
	## length under the bound AND shifts the finished animal onto its own
	## x-midpoint, because the reach of a capsule is its offset PLUS its extent and
	## an off-centre mesh spends the 0.7 twice. Growing a boss UP is free; growing
	## it out, or off-centre, is not.

	## ------------------------------------------------------------------------
	## HYDRA — the PLAINS band's boss, and the one players meet first.
	## ------------------------------------------------------------------------
	## Plains is the most common biome and reaches close to spawn, so this is the
	## family member most runs meet and the one they meet most often. It gets NO
	## special-casing for that: the spawn-safe bubble and the boss station
	## schedule already govern how near one can appear, and a gentler first boss
	## is a retune the owner makes on a whole family, not a hidden exception here.
	##
	## PURPOSE-BUILT, MEASURED (bead lce.6 — the placeholder was a squashed, reared
	## snake.glb). scenes/characters/hydra.tscn instances hydra.glb at IDENTITY: a
	## heavy low body on stubby legs carrying THREE necks and heads off one branch
	## point, built by scripts/generate_hydra.py on the toolkit's `necks` primitive.
	## Read that file for the palette and the fan geometry. The mesh is 1.3197 long
	## (x -0.660 .. +0.660), 0.662 tall and 0.524 across. The capsule in hydra.tscn
	## is `radius = 0.331, height = 1.32`, laid on the travel axis with the
	## crocodile's basis, at `(0, 0.331, 0)`:
	##   * 1.32 covers the 1.3197 m length, caps included, so the horizontal reach
	##     is 0.66 — inside the spawner's 0.7 bound.
	##   * 0.331 makes a 0.662 m tube around the 0.662 m height — the viper's
	##     tightest-fit rule, and radius == centre y (the crocodile/viper identity)
	##     puts the capsule's bottom exactly on y = 0.
	##   * NO z offset, unlike the viper's -0.495 and the roc's +0.133, because
	##     generate_hydra.py centres this mesh on its own origin. That is not a
	##     detail: a laid capsule's reach is its offset PLUS its half-length, so an
	##     off-centre boss mesh spends BOSS_FOOTPRINT_RADIUS_PER_SCALE twice and
	##     lands scaled inside the rock the spawner placed it clear of.
	"hydra": {
		## No arm. Same reasoning as the green dragon's, one band over: a melee
		## territorial boss is exactly what the code above the `match` already is,
		## and "solo" is deliberately the string with no case.
		"behavior": "solo",

		# ----- Speed and detection -----
		## A boss overrides the chase speed (BOSS_CHASE_SPEED, 7.0 — this row
		## states no `boss_chase_speed`, which is the melee default the lattice was
		## written for) and the detection radius (BOSS_DETECTION_RADIUS, 25), so
		## what these two buy is LATTICE HYGIENE: 5.5 sits in (WALK_SPEED 5.0,
		## MAX_CHASE_SPEED 8.5] and 15 sits well under the LOD SIM_RADIUS (45), so
		## if a later bead ever gives the hydra a BIOME_SPECIES entry it is already
		## a legal ordinary predator. `move_speed` is the exception: a boss reads
		## it STRAIGHT THROUGH, so 2.0 is live — the slowest patrol in the family,
		## a heavy swamp thing dragging itself round its own pool.
		"move_speed": 2.0,
		"chase_speed": 5.5,

		## Zero, not a spread: a boss takes no per-instance rolls at all (see the
		## is_boss branch in _ready), so a factor here would never be drawn.
		"speed_random_factor": 0.0,
		"size_random_factor": 0.0,
		"detection_radius": 15.0,

		# ----- Organic wandering -----
		## Slow to decide and slow to turn — it owns this ground and the leash
		## keeps it here regardless, so it has nowhere to be.
		"direction_change_interval": 5.0,
		"pause_duration": 0.7,
		"wander_turn_rate": 0.8,
		"turn_smoothness": 3.5,
		"min_wander_speed_factor": 0.40,
		"speed_variation_freq": 0.6,
		"sniff_pause_chance": 0.30,

		# ----- Obstacle avoidance -----
		## Feelers from 0.4 m: the body slab's back is 0.41 m up and the mesh
		## stands 0.662 before the boss scale, so a probe at the crocodile's 0.3
		## would sample the body rather than the ground ahead of it.
		"avoid_look_ahead": 3.5,
		"avoid_feeler_angle": PI / 5.0,  # 36°
		"avoid_feeler_height": 0.4,
		"avoid_speed_factor": 0.5,

		# ----- Procedural body animation -----
		## -PI/2, the quadruped/serpent default: snake.glb is authored
		## nose-along-+X and the body travels +Z.
		"model_facing_offset": -PI / 2.0,

		## THE SWAY IS THE HEADS, and it still is now that the heads are real.
		## There is no rig and no per-head motion — the whole `Model` node sways as
		## one — so the read is carried by the widest `sway_yaw` in the table (8°,
		## against the crocodile's 3°) over a slow stride: a fan of necks weaving
		## over a body that barely moves. What makes three heads legible from a
		## distance is their STATIC spacing in the mesh, not animation.
		"stride_frequency": 4.5,
		"waddle_roll": 5.0 * PI / 180.0,
		"bob_amount": 0.04,
		"sway_yaw": 8.0 * PI / 180.0,
		"chase_pitch": 12.0 * PI / 180.0,
		"breathe_speed": 1.2,
		"breathe_amount": 0.03,

		# ----- River submersion (VISUAL ONLY) -----
		## The viper's 0.10 carried through the 2.5x rear: 0.25. The sink is
		## written in MODEL-LOCAL metres and applied to `model.position.y`, which
		## is in the BODY's frame, so the Model node's own scale does not touch it
		## — leave it at the viper's number and a hydra two and a half times taller
		## would wade proportionally shallower. VISUAL ONLY, like every row: the
		## CharacterBody3D, its CollisionShape3D and global_position never move.
		"river_sink_depth": 0.25,
		"river_sink_ease_speed": 0.25 / 0.2,

		# ----- Bite -----
		## Fast and shallow, because it is MANY heads: the animation is one head
		## darting in, not a single jaw committing. Contact is one-shot lethal for
		## every boss regardless — this is the only warning you get.
		"bite_duration": 0.35,
		"bite_pitch": 26.0 * PI / 180.0,
		"bite_lunge": 0.45,

		## THE STAKE (see the crocodile row): a boss bite, several mouths of it.
		"coin_setback": 0.18,
	},

	## ------------------------------------------------------------------------
	## NAGA — the DESERT band's boss.
	## ------------------------------------------------------------------------
	## The desert already has the sand viper as its ordinary predator, and that is
	## a deliberate pairing rather than a repeat: the viper is a 0.2 m ambusher
	## that buries itself, the naga is a 1.6 m torso over a coiled base that never
	## hides. Same band, opposite silhouettes.
	##
	## PURPOSE-BUILT, MEASURED (bead lce.6 — the placeholder was a re-skinned
	## primm.tscn). scenes/characters/naga.tscn instances naga.glb at IDENTITY: an
	## armoured four-armed torso on a coiled serpent base, built by
	## scripts/generate_naga.py. The mesh is 1.1320 long (x -0.722 .. +0.410),
	## 1.600 tall and 0.580 across — the same standing height the placeholder had,
	## so every number below it still reads true. The capsule in naga.tscn is
	## unchanged at `radius = 0.30, height = 1.60`, `(0, 0.80, 0)`, UPRIGHT — no
	## lay-down rotation, the same thing titan.tscn does and the quadruped scenes
	## do not:
	##   * 1.60 is the full standing height and 0.80 = height/2 puts the capsule's
	##     bottom exactly on y = 0.
	##   * 0.30 covers the 0.290 m half-width, and it is also the horizontal reach
	##     — an upright capsule's reach is its RADIUS, not half its height — so the
	##     spawner's 0.7 bound has 0.4 m of slack.
	##   * The trailing tail tip and the arm blades sit OUTSIDE it, deliberately.
	##     A capsule wraps a model's LONG axis and stays narrow across it — the
	##     crocodile's own flanks are outside its 0.16 m capsule for the same
	##     reason — and on a boss whose contact is one-shot lethal, a hit volume
	##     smaller than the art is the only direction that is fair.
	"naga": {
		## No arm, for the hydra's reason. HMM3's naga is a melee unit; the ranged
		## opt-in in this family belongs to the clown alone.
		"behavior": "solo",

		# ----- Speed and detection -----
		## Hygiene numbers, overridden at spawn — see the hydra's block for the
		## full argument. `move_speed` is the live one: 3.0 is the QUICKEST patrol
		## of the four, a glide over sand rather than a walk over it.
		"move_speed": 3.0,
		"chase_speed": 5.5,
		"speed_random_factor": 0.0,
		"size_random_factor": 0.0,
		"detection_radius": 15.0,

		# ----- Organic wandering -----
		## Quicker to change its mind than the hydra and much snappier to turn: a
		## serpent pivots on its own coils.
		"direction_change_interval": 4.5,
		"pause_duration": 0.5,
		"wander_turn_rate": 1.0,
		"turn_smoothness": 4.5,
		"min_wander_speed_factor": 0.50,
		"speed_variation_freq": 0.8,
		"sniff_pause_chance": 0.20,

		# ----- Obstacle avoidance -----
		## Cast from 0.8 m — chest height on the 1.6 m placeholder, the titan's
		## reasoning at a smaller size. A probe down at the quadrupeds' 0.3 would
		## sample sand under the coils.
		"avoid_look_ahead": 3.5,
		"avoid_feeler_angle": PI / 5.0,  # 36°
		"avoid_feeler_height": 0.8,
		"avoid_speed_factor": 0.55,

		# ----- Procedural body animation -----
		## -PI/2, the quadruped/serpent default. It was PI while this row wore a
		## humanoid CHARACTER mesh (those are authored facing -Z); naga.glb is
		## authored nose-along-+X like every other predator model, which is the
		## toolkit's first contract, so the half turn came off with the
		## placeholder. Get this wrong and the boss glides sideways.
		"model_facing_offset": -PI / 2.0,

		## A GLIDE, and it is defined by what is missing: almost no roll and the
		## smallest bob of the four (there is no gait to bob), carried instead by a
		## wide yaw sway — the tail's weave swinging the torso over it.
		"stride_frequency": 4.0,
		"waddle_roll": 2.0 * PI / 180.0,
		"bob_amount": 0.03,
		"sway_yaw": 7.0 * PI / 180.0,
		"chase_pitch": 10.0 * PI / 180.0,
		"breathe_speed": 1.3,
		"breathe_amount": 0.025,

		# ----- River submersion (VISUAL ONLY) -----
		## The titan's 0.55 on a 1.8 m biped, rescaled to this 1.6 m one: 0.49,
		## i.e. the same mid-thigh fraction measured off a mesh that STANDS.
		## VISUAL ONLY — body, capsule and global_position never move.
		"river_sink_depth": 0.49,
		"river_sink_ease_speed": 0.49 / 0.2,

		# ----- Bite -----
		## The viper's strike shape on a much bigger body: short, sharp and far
		## through. One-shot lethal, like every boss's contact.
		"bite_duration": 0.35,
		"bite_pitch": 32.0 * PI / 180.0,
		"bite_lunge": 0.55,

		## THE STAKE (see the crocodile row): the lightest of the bosses.
		"coin_setback": 0.15,
	},

	## ------------------------------------------------------------------------
	## ROC — the MOUNTAIN band's boss.
	## ------------------------------------------------------------------------
	## IT WALKS. Mountains in this game are impassable block massifs you route
	## AROUND — the flat-world invariant means nothing flies and nothing climbs —
	## so the rock bird launches ground-bound like every other boss, and its wings
	## are silhouette. The owner-approved bounded LEAP (a Windman-Air-Rush-shaped
	## hop, with the cougar's pounce as prior art) for the roc and the dragon is
	## its own follow-up bead, godot-test1-lce.9; there is deliberately no jump
	## code here and this row carries no key for one.
	##
	## A massif band is also the one where a boss station most often finds NO
	## clear candidate: spawn_bosses_in_chunk walks obstacle footprints with
	## per-scale clearance, and a 9x roc is a wide body (~6.3 m). Some mountain stations
	## will legitimately place no boss at all — that is the designed outcome of
	## that walk, not a reason to loosen the clearance.
	##
	## PURPOSE-BUILT, MEASURED (bead lce.7 — the placeholder was bear.glb reared and
	## squashed to (0.9, 1.6, 0.9)). scenes/characters/roc.tscn instances roc.glb at
	## IDENTITY: the toolkit's FIRST AVIAN — two heavy legs, a slab of a body
	## carried over them, a hooked beak, and big wings worn nearly SHUT off
	## `predator_parts.wings` — built by scripts/generate_roc.py. Read that file for
	## the palette (measured against the mountain scree) and for why a bird's legs
	## are written inline rather than lifted into a `biped()` nobody else calls.
	##
	## THE MESH IS 1.1488 LONG (x -0.574 .. +0.574), 1.3340 TALL and 0.7932 ACROSS.
	## The capsule in roc.tscn is `radius = 0.575, height = 1.334` at
	## `(0, 0.667, 0)`, UPRIGHT like the titan's and the naga's — this body is
	## taller than it is long, so a laid-down capsule could not cover it:
	##   * 1.334 is the standing height and 0.667 = height/2 puts the bottom on
	##     y = 0.
	##   * 0.575 covers the 0.574 m half-length, and being an upright capsule that
	##     radius IS the horizontal reach — inside the spawner's 0.7 bound.
	##   * z = 0, where the placeholder needed +0.133: generate_roc.py shifts the
	##     finished bird onto its own x-midpoint, so there is no offset left to add
	##     to the radius. (Model +X becomes body +Z under the -PI/2 facing offset,
	##     which is why an x-midpoint shows up as a z offset here at all.)
	## The wings reach 0.397 either side, inside the 0.575 radius, so this bird is
	## the one boss whose whole silhouette really does fit its own capsule.
	"roc": {
		## The dragon's row one band over, arm included: `_behave_leap`, one
		## function shared by both winged bosses with not one `if species ==`
		## anywhere. The numbers at the bottom are the only difference — a bird
		## goes higher and hangs longer than a dragon does, and that is a value in
		## a table rather than a second behaviour.
		"behavior": "leap",

		# ----- Speed and detection -----
		## Hygiene numbers, overridden at spawn (see the hydra). The live one is
		## `move_speed` 2.4: a big bird's stalking walk between the massifs.
		"move_speed": 2.4,
		"chase_speed": 5.5,
		"speed_random_factor": 0.0,
		"size_random_factor": 0.0,
		"detection_radius": 15.0,

		# ----- Organic wandering -----
		## Long stands and hard, deliberate turns — a bird holding still and then
		## snapping its whole body round.
		"direction_change_interval": 6.0,
		"pause_duration": 1.0,
		"wander_turn_rate": 0.7,
		"turn_smoothness": 5.5,
		"min_wander_speed_factor": 0.45,
		"speed_variation_freq": 0.5,
		"sniff_pause_chance": 0.30,

		# ----- Obstacle avoidance -----
		## The longest reach in the family and the highest probe: MOUNTAIN is the
		## band made of walls, and a 1.3 m body before the boss scale needs to
		## sample rock at chest height rather than scree at its feet.
		"avoid_look_ahead": 4.0,
		"avoid_feeler_angle": PI / 5.0,  # 36°
		"avoid_feeler_height": 0.7,
		"avoid_speed_factor": 0.5,

		# ----- Procedural body animation -----
		## -PI/2, the quadruped default and UNCHANGED by the lce.7 model swap:
		## roc.glb is a predator_parts build, authored nose-along-+X exactly as the
		## bear placeholder was. See the preamble above for why that is worth
		## saying out loud.
		"model_facing_offset": -PI / 2.0,

		## A STRUT. Two legs carrying a heavy body read as a slow stride with a
		## deep bob and a big roll — the largest `bob_amount` of the four — and
		## almost no forward lean, because a bird's mass sits over its feet.
		"stride_frequency": 3.8,
		"waddle_roll": 8.0 * PI / 180.0,
		"bob_amount": 0.10,
		"sway_yaw": 5.0 * PI / 180.0,
		"chase_pitch": 8.0 * PI / 180.0,
		"breathe_speed": 1.0,
		"breathe_amount": 0.035,

		# ----- River submersion (VISUAL ONLY) -----
		## 0.48, unchanged across the lce.7 model swap and re-derived rather than
		## re-typed: it was the bear's 0.30 carried through the placeholder's 1.6x
		## rear, and on the purpose-built mesh it is just under the hip
		## (generate_roc.py's HIP_Y is 0.494). Both readings put the water line at
		## the top of the legs — long legs, so it wades where a quadruped of the
		## same bulk would be swimming. VISUAL ONLY.
		"river_sink_depth": 0.48,
		"river_sink_ease_speed": 0.48 / 0.2,

		# ----- Bite -----
		## A beak, so: the longest wind-up and the deepest pitch of the four, and
		## the furthest lunge — one committed stoop rather than a chew.
		"bite_duration": 0.55,
		"bite_pitch": 36.0 * PI / 180.0,
		"bite_lunge": 0.6,

		# ----- The hop (the "leap" behaviour reads these five) -----------------
		## A BIRD'S HOP, WHICH MEANS HIGHER AND FLOATIER THAN THE DRAGON'S, and
		## that is the entire authored difference between the two leaping bosses.
		## 9.0^2 / (2 * 8.0) = 5.06 m of apex over 2 * 9.0 / 8.0 = 2.25 s of
		## airtime, against the dragon's 3.56 m over 1.78 s: half again the height
		## and a quarter longer in the air, which is what separates a beat of wings
		## from a bound. See SPECIES["green_dragon"] for the arc arithmetic and for
		## why these are the row's own numbers rather than the file's GRAVITY.
		"leap_launch_speed": 9.0,
		"leap_gravity": 8.0,

		## The dragon's inequality with the roc's numbers, and it comes out with a
		## little more room because the longer airtime is bought back by a longer
		## recovery: peak 8.5 x 1.20 = 10.20 m/s (above MAX_CHASE_SPEED and above
		## the 9.0 run), cycle average
		##   (1.20 x 2.25 + 0.85 x 3.5) / (2.25 + 3.5) = 0.987 x chase
		## — 8.39 m/s at the worst case against a 9.0 run, 6.91 m/s against a 5.0
		## walk. Measured, not argued, by enemy_spawn_selfcheck's leap probe over
		## repeated cycles and against a recovery-removed control.
		"leap_speed_factor": 1.20,
		"leap_cooldown": 3.5,
		"leap_recover_factor": 0.85,

		## Reach 2.25 s x 8.5 x 1.20 = 22.9 m at the worst case (18.9 m nominal) —
		## the longest hop in the game and still inside BOSS_TERRITORY_RADIUS (32),
		## which is the bound that matters: past it a roc could only ever launch
		## from the exact centre of its territory. MOUNTAIN is also the band made
		## of walls, and a hop carries no obstacle feelers with it — the arc is
		## ballistic by design — so `avoid_look_ahead` above only steers the
		## GROUNDED legs. A roc that bounds into a massif slides off it exactly as
		## it would have walked into it, at a fifth of the frames.

		## THE STAKE (see the crocodile row): a boss bite from above.
		"coin_setback": 0.18,
	},

	## ------------------------------------------------------------------------
	## ICE CREAM CLOWN — the CITY band's boss, and the family's second archer.
	## ------------------------------------------------------------------------
	## Owner, verbatim: "let it be clown like in 'It' of King (inspired)" and
	## "let's clown thrown ice cream or like that also". THE TONAL BREAK IS THE
	## DESIGN. Five HMM3 creatures and one Stephen King reference is not a slip:
	## the city is the band where uncanny-and-out-of-place is the whole read, and
	## the same file already calls it the SAFE band (CITY_CROC_DIVISOR thins its
	## predators, roofs are real shelter). A safe band whose guardian is a clown
	## throwing ice cream is a deliberate joke with teeth.
	##
	## AND IT IS THE PROOF THE RANGED CAPABILITY IS A CAPABILITY. It reuses
	## `_behave_ranged` — the titan's arm — UNCHANGED and un-branched: not one
	## `if species ==` anywhere, no second arm, no edit to boss_projectile.gd.
	## Everything that makes an ice cream different from a thunder bolt is the
	## numbers in the "ranged" dict below, and the fairness contract over those
	## numbers is measured by projectile_selfcheck's sweep, which scans every
	## "ranged" dict in this table and so picked this row up the day it landed.
	##
	## THE CAPSULE IN clown.tscn IS RECORDED HERE for the reason the viper's and
	## titan's are: a .tscn cannot hold a comment an editor resave will not eat.
	## clown.glb spans x -0.215..+0.313, z ±0.36, and stands 1.67 m tall. The
	## capsule is `radius = 0.36, height = 1.67` at `(0, 0.835, 0)`, UPRIGHT:
	##   * 1.67 is the standing height, 0.835 = height/2 puts the bottom on y = 0.
	##   * 0.36 covers the ±0.36 m half-width of the ruffled suit and limbs, and
	##     is well under the spawner's 0.7 bound (BOSS_FOOTPRINT_RADIUS_PER_SCALE).
	"clown": {
		## THE TITAN'S ARM, REUSED. `_behave_ranged` is one cooldown and one
		## BossProjectile.fire() call, and everything it does is read out of the
		## "ranged" dict below — so this string is the entire opt-in.
		"behavior": "ranged",

		# ----- Speed and detection -----
		## BOTH SPEEDS ARE UNDER WALK_SPEED (5.0), and for a ranged row that is not
		## a hole in the lattice but the contract: enemy_spawn_selfcheck's ranged
		## probe ASSERTS every speed slot a "ranged" row fills is sub-walk,
		## precisely because a boss-only row is exempt from the lattice's lower
		## bound. A thrower you cannot stroll away from is a melee boss holding a
		## cone.
		"move_speed": 2.0,
		"chase_speed": 3.5,

		## THE BOSS SPEED OPT-OUT, taken for the titan's reason exactly: without it
		## this row would inherit BOSS_CHASE_SPEED (7.0) and run down a walking
		## player, i.e. stop being an archer. Same number as `chase_speed` because
		## a clown has one gait; the two slots exist only because a boss and a
		## plain predator read different ones, and both are asserted sub-walk.
		"boss_chase_speed": 3.5,

		"speed_random_factor": 0.0,
		"size_random_factor": 0.0,
		## A boss overrides this with BOSS_DETECTION_RADIUS (25.0). What the number
		## states is intent, and it is the `ranged.max_fire_range` below plus a
		## metre: the clown starts throwing as soon as it acquires you rather than
		## walking the first stretch of an engagement. Keep the two in step.
		"detection_radius": 15.0,

		# ----- Organic wandering -----
		## THE TWITCHIEST RHYTHM IN THE TABLE: the shortest interval, the longest
		## pause, the fastest turn rate. Capering — a thing that changes its mind
		## constantly and then stands far too still.
		"direction_change_interval": 3.5,
		"pause_duration": 0.9,
		"wander_turn_rate": 1.4,
		"turn_smoothness": 4.0,
		"min_wander_speed_factor": 0.35,
		"speed_variation_freq": 1.1,
		"sniff_pause_chance": 0.35,

		# ----- Obstacle avoidance -----
		## The titan's reach and near its probe height — this is a 1.6 m humanoid
		## before the boss scale, in the band with the most walls per square metre.
		"avoid_look_ahead": 4.0,
		"avoid_feeler_angle": PI / 5.0,  # 36°
		"avoid_feeler_height": 0.9,
		"avoid_speed_factor": 0.6,

		# ----- Procedural body animation -----
		## -PI/2, the standard enemy/boss facing offset. clown.glb is authored
		## nose/front-along-+X (the toolkit's first contract) and the body travels
		## +Z, so the model rotates -90°.
		"model_facing_offset": -PI / 2.0,

		## A CAPER. The biggest waddle roll and the biggest bob of any row here,
		## over a quick stride, with almost no chase lean — the read is a thing
		## bouncing along on its toes, not a predator committing. It is deliberately
		## the opposite of the titan's near-still tread.
		"stride_frequency": 5.0,
		"waddle_roll": 9.0 * PI / 180.0,
		"bob_amount": 0.09,
		"sway_yaw": 7.0 * PI / 180.0,
		"chase_pitch": 6.0 * PI / 180.0,
		"breathe_speed": 1.6,
		"breathe_amount": 0.04,

		# ----- River submersion (VISUAL ONLY) -----
		## The naga's 0.49, the same mid-thigh fraction on the same 1.6 m standing
		## height. VISUAL ONLY: body, capsule and global_position never move.
		"river_sink_depth": 0.49,
		"river_sink_ease_speed": 0.49 / 0.2,

		# ----- Bite -----
		## Slow, shallow and short. Letting a clown walk into you still kills you —
		## contact is one-shot lethal for every boss — but this animation is a
		## lunge you can see coming from a body far too slow to land it. The cone
		## is the threat.
		"bite_duration": 0.5,
		"bite_pitch": 18.0 * PI / 180.0,
		"bite_lunge": 0.4,

		# ----- The ice cream (the "ranged" behaviour reads this) ---------------
		## A COPY of BossProjectile.STYLES["ice_cream"] plus the three keys that
		## are the AI's business rather than the projectile's, exactly as the
		## titan's row copies "thunder_bolt". Copied and not referenced because
		## those three have to live somewhere and adding them to the shared STYLES
		## dict would hand them to every future shooter; the two sets are measured
		## INDEPENDENTLY by projectile_selfcheck (it scans STYLES *and* every
		## "ranged" row), so a drift between them fails on whichever side broke.
		##
		## The flight numbers and their argument belong to boss_projectile.gd —
		## read its STYLES entry, not this copy. In one line: from its 8 m minimum
		## the lob is 1.33 s in the air, in which a WALKING player covers 6.7 m
		## against a 1.1 m splat radius, 6.1x a required 3x.
		"ranged": {
			"style": "ice_cream",
			"trajectory": "lob",
			"speed": 6.0,
			"gravity": 12.0,
			"hit_radius": 1.1,
			"min_fire_range": 8.0,
			"max_range": 20.0,
			"lifetime": 5.0,
			"max_live": 3,
			"color": Color(1.0, 0.55, 0.75),
			"mesh_scale": Vector3(0.32, 0.32, 0.32),

			## ---- Read by _behave_ranged(), never by the projectile ----------
			## SECONDS BETWEEN SHOTS. Faster than the titan's 3.0 and that is the
			## whole difference in how the two archers feel: an ice cream is half
			## the flight time of a bolt over half the band, so a longer cadence
			## would leave a clown standing silent most of an engagement.
			## `max_live` 3 above is the backstop if this is ever shortened.
			"fire_cooldown": 2.0,

			## THE FIRING BAND's ceiling, with `min_fire_range` 8.0 as its floor.
			##
			## The FLOOR is the projectile's own: closer than 8 m the lob arrives
			## faster than a walking player can clear the splat, so the ARM refuses
			## to fire rather than the style being retuned. Walk INTO a clown and it
			## stops throwing and has to try to grab you, which at 3.5 m/s it
			## cannot — the same counterplay the titan offers, for free.
			##
			## The CEILING (14 m) sits under three things at once: the projectile's
			## own `max_range` (20), so no shot is fired that would evaporate short
			## of its aim point — and that is a 3-D distance from a muzzle that at
			## the 9x cap stands 11.7 m up, i.e. hypot(14, 11.7) = 18.24 m, which
			## is why 16 was not enough once bead godot-test1-9k7 raised the size
			## schedule (projectile_selfcheck check 1c now asserts exactly this);
			## BOSS_DETECTION_RADIUS (25), so the whole band is
			## inside what a clown can smell (the arm only runs while chasing, so a
			## wider ceiling would simply never fire); and BOSS_TERRITORY_RADIUS
			## (32), so it cannot shell you out of a zone you have already left.
			"max_fire_range": 14.0,

			## Height of the throwing hand above the body origin, in MODEL-LOCAL
			## metres — _behave_ranged multiplies it by the body's scale, so a 9x
			## clown throws from 11.7 m up and a 3.75x one from 4.88 m, keeping the
			## muzzle at the raised arm of whatever size the schedule handed out.
			## 1.3 is shoulder-and-a-bit on the 1.61 m placeholder.
			"muzzle_height": 1.3,
		},

		## THE STAKE (see the crocodile row): its threat is the throw, not the
		## bite, so the bite bills like an animal.
		"coin_setback": 0.12,
	},

	## ------------------------------------------------------------------------
	## GD-SURVEY HUNTER ROBOT — the corporation's retrieval unit.
	## ------------------------------------------------------------------------
	## THE ONE ROW THAT IS NOT AN ANIMAL, and it is a row anyway. That is the
	## point of this table: a machine differs from a crocodile in ~30 numbers, not
	## in a class. Nothing below is new code — the SAME `_animate_body`,
	## `_update_chase_state` and feeler math drive it, and what makes it read as a
	## servo instead of a lumbering reptile is entirely the animation block.
	##
	## AND IT IS THE ONE ROW BIOME_SPECIES DOES NOT DISPATCH. Every other predator
	## belongs to a band; the corporation hunts EVERYWHERE, so hunters come from
	## their own spawner on their own hash stream in endless_terrain.gd
	## (spawn_hunters_in_chunk / HUNTER_SALT) rather than from the biome map. That
	## is dispatch-free and costs the chunk RNG zero draws — see that function.
	##
	## MEASURED OFF assets/models/characters/hunter.glb (built by
	## scripts/generate_hunter.py), recorded here for the same reason the viper's
	## are: a .tscn cannot hold a comment an editor resave will not eat.
	##   * 3.0375 m long, 2.250 m TALL, 0.84375 m wide — the only predator in the
	##     table that is TALLER than it is wide by a factor of nearly three, and
	##     the only one a full head taller than a player. A crocodile is
	##     1.40 x 0.28 x 0.276; this thing stands up, and since bead
	##     godot-test1-5ow it towers (the generator's `CHASSIS_SCALE` 2.25 — the
	##     second 1.5x on top of godot-test1-6bj's — every number in this block is
	##     the old one times that, because the scale is applied uniformly to the welded mesh).
	##   * The capsule in hunter_robot.tscn is `radius = 0.421875, height = 3.0375`,
	##     laid on the travel axis with the crocodile's basis, at
	##     `(0, 0.421875, -0.14625)`. radius == centre y, the crocodile/viper
	##     identity, so the capsule's bottom sits exactly on y = 0 and the chassis
	##     rests on the ground plane. z = -0.14625 is the mesh's own midpoint: like
	##     the viper, the hunter is built forward of its origin, so a capsule
	##     centred on the origin would leave solid body hanging off the back.
	##     tower_guard.tscn carries the identical three numbers — one chassis, one
	##     capsule, and a grown model over an unscaled capsule would be the bug.
	"hunter_robot": {
		## THE SIXTH ARM, and the first one whose subject is PACING rather than
		## geometry or speed. `_behave_hunt()` is all it selects, and all it
		## selects is that: telegraph, shadow, close, disengage. Everything else
		## in this row is the same numbers every other row carries.
		"behavior": "hunt",

		# ----- Speed and detection -----
		## THE LATTICE IS THE LATTICE: 5.0 (WALK_SPEED) < 6.5 <= 8.5
		## (MAX_CHASE_SPEED) < 9.0 (the slowest character's run). Read against a
		## running player: top roll 6.5 x 1.1 = 7.15, margin 1.85 m/s; median 6.5,
		## margin 2.5. A hunter is FASTER than a crocodile (5.5) and slower than
		## anything with a burst — it closes ground you gave away by walking, and
		## it never wins a footrace. RUNNING ALWAYS ESCAPES A HUNTER, and that
		## promise is what the whole fear class is allowed to be built on: the
		## machine is frightening because it commits and does not stop, not
		## because it is unsurvivable.
		##
		## move_speed 2.8 is a PATROL, a shade above the crocodile's 2.5 — read
		## with min_wander_speed_factor and speed_variation_freq below, which take
		## nearly all the wobble out of it, this is a unit walking a beat rather
		## than an animal browsing.
		"move_speed": 2.8,
		"chase_speed": 6.5,

		## MACHINES DO NOT VARY, and that is the whole corporate read: a pack of
		## hunters must look ISSUED, not born. ±10% on speed and ±5% on size are
		## the tightest spreads in the table (the crocodile's are ±50% / ±25%),
		## deliberately left non-zero so two units on screen are not literally the
		## same body — a fleet has service wear, it does not have a runt.
		"speed_random_factor": 0.1,
		"size_random_factor": 0.05,

		## 25.0 — THE BOSS PRECEDENT (BOSS_DETECTION_RADIUS), and the widest any
		## row is allowed to be. A hunter commits early: it sees you across open
		## ground and starts walking, which is the fear the class is built on. The
		## ceiling is not aesthetic — crocodile_lod_manager's SIM_RADIUS (45) has
		## to stay WELL above every row's detection, or a body that can already
		## smell the player could still be asleep. 25 leaves the same 20 m of
		## margin a boss has, and enemy_spawn_selfcheck check 4 now measures it.
		"detection_radius": 25.0,

		# ----- Organic wandering (deliberately INORGANIC here) -----
		## A LONG STRAIGHT LEG AND A SHORT SCAN HALT. 6.0 s between heading
		## changes is the longest in the table (the crocodile's is 4.0, the
		## hound's 2.2), and the 0.25 s pause is the shortest — a patrol walks a
		## line, stops, sweeps, walks the next line. Nothing here is a sniff.
		"direction_change_interval": 6.0,
		"pause_duration": 0.25,

		## 0.3 rad/s is a QUARTER of the crocodile's 1.2: the continuous random
		## steer that makes an animal meander is exactly what a machine must not
		## do. What is left reads as course correction, not wandering.
		"wander_turn_rate": 0.3,

		## …but the turn ITSELF is crisp. 8.0 (croc 5.0) is a servo yawing to a
		## commanded heading: it arrives, it does not swing.
		"turn_smoothness": 8.0,

		## ONE CADENCE. 0.92 floor and a 0.25 rad/s variation frequency leave the
		## patrol speed essentially flat — the sine is still there (a dead-constant
		## speed reads as a slide), it is just under the threshold of notice.
		"min_wander_speed_factor": 0.92,
		"speed_variation_freq": 0.25,

		## Half the crocodile's chance, and it is a sensor sweep rather than a
		## sniff — see pause_duration.
		"sniff_pause_chance": 0.15,

		# ----- Obstacle avoidance -----
		## 2.4 m of feeler for a 1.35 m chassis — proportionally the crocodile's
		## 3.0-for-1.40, because the failure it prevents is the same one (the model
		## reaching into a block the shorter capsule stopped clear of).
		"avoid_look_ahead": 2.4,
		"avoid_feeler_angle": PI / 5.0,  # 36°

		## Cast at 0.5, not the crocodile's 0.3: this animal's mass is its HULL,
		## which sits at 0.36-0.62 m off the ground on the piston legs. A feeler at
		## croc height would sample the air between the legs and under the chassis.
		"avoid_feeler_height": 0.5,

		## 0.7 — it eases off less than a crocodile (0.5) rounding a block. A
		## machine reroutes; it does not shy.
		"avoid_speed_factor": 0.7,

		# ----- Procedural body animation (THE SERVO GAIT) -----
		## The mesh is authored facing +X and the body travels +Z, like every other
		## model in predator_parts — same -90°.
		"model_facing_offset": -PI / 2.0,

		## THIS BLOCK IS WHERE THE MACHINE ACTUALLY LIVES. Every number in it is
		## near the table's floor, and they have to be read together: the four
		## amplitudes below are what turn a walk cycle into a lumber, and a hunter
		## must not lumber. What is left is stride frequency — a fast, even, high
		## step rate with almost no body motion hung off it, which is exactly what
		## a servo gait looks like.
		"stride_frequency": 12.0,

		## 0.5° of roll — effectively zero (the crocodile waddles 9°). A chassis on
		## four vertical pistons has nothing to roll about, and any visible roll at
		## all instantly reads as an animal.
		"waddle_roll": 0.5 * PI / 180.0,

		## Half the crocodile's bob. A piston stack absorbs the step; it does not
		## heave the body.
		"bob_amount": 0.012,

		## 1° of sway against the crocodile's 5°: the slow body "snaking" yaw is a
		## spine, and this thing has a frame.
		"sway_yaw": 1.0 * PI / 180.0,

		## 4° of forward lean when it commits (croc 10°). Just enough that a
		## closing hunter is legible in silhouette from the side.
		"chase_pitch": 4.0 * PI / 180.0,

		## A MACHINE IDLES STILL. This is the smallest breathe in the table by an
		## order of magnitude and it is deliberately NOT zero: at 0.002 m the hull
		## has a faint servo-hold tremor, which reads as powered-and-waiting where
		## a perfectly frozen model reads as a bug.
		"breathe_speed": 1.0,
		"breathe_amount": 0.002,

		# ----- River wading (VISUAL ONLY — same hard rule as every row) -----
		## 0.22 m off a model that stands 1.000 m tall and rides 0.36 m clear on
		## its pistons: the legs go under, the hull does not. That is the read
		## being bought — the corporation's unit FORDS the river, chest-high and
		## unbothered, where a crocodile hides in it. Deeper would swallow the
		## hazard livery, which is the whole recognition cue at distance.
		##
		## VISUAL ONLY: never touches the CharacterBody3D, its CollisionShape3D or
		## global_position. A wading hunter is exactly as dangerous as a dry one.
		"river_sink_depth": 0.22,

		## Sized so the full sink takes ~0.2 s, the player's own ease time — the
		## depth/time form so the derivation survives a retune of the depth.
		"river_sink_ease_speed": 0.22 / 0.2,

		# ----- The clamp (this row's "bite") -----
		## The rear pack's two retrieval prongs, not a jaw. Faster than a
		## crocodile's chomp (0.35 vs 0.5) and much shallower in pitch (12° vs 26°)
		## because a clamp closes, it does not gape; the lunge is nearly the
		## crocodile's, since the unit does step into the grab.
		"bite_duration": 0.35,
		"bite_pitch": 12.0 * PI / 180.0,
		"bite_lunge": 0.30,

		# ----- The hunt (behavior == "hunt") -----
		## THE THREE NUMBERS THAT MAKE A RETRIEVAL UNIT OUT OF A FAST CROCODILE.
		## Read them as one shape: it tells you it has you, it walks a ring while
		## you decide what to do about it, it commits, and once it has what it
		## came for it stops. See `_behave_hunt()` for the state machine and
		## `hunt_steer_point()` for the geometry.

		## WARNING TIME, in seconds, and the first mercy-before-contact lever in
		## the game that costs no director. On the not-chasing → chasing edge the
		## unit holds the standoff ring for this long before it may close, so a
		## hunter that acquires you at the 25 m detection edge spends 1.8 s
		## visibly pacing rather than immediately walking in. At the 6.5 m/s
		## chase speed that is ~11.7 m of approach the player gets for free, which
		## is most of the way back out of detection at a run.
		##
		## 1.8 is at the long end of the 1.5-2.0 band the design asked for,
		## because the announcement it pairs with is not built yet (see the
		## sound hook in `_behave_hunt`): until there is a ping, the SILHOUETTE
		## holding the ring is the whole warning, and it needs long enough to read
		## as deliberate rather than as a hitch in the pathing.
		"hunt_telegraph_time": 1.8,

		## THE RING, in metres. Wide enough that a shadowing hunter is scenery you
		## can watch and walk away from — well outside the ~1 m contact radius and
		## outside any ability's reach — and inside the 25 m detection radius by
		## enough (15 m) that holding the ring never drops the chase and starts
		## the telegraph over. A ring at or past detection would make a hunter
		## that shadows you flicker in and out of acquisition, which is the same
		## boundary-flicker failure DETECTION_SIM_MARGIN exists to prevent one
		## level up.
		"hunt_standoff": 10.0,

		## POST-GRAB DISENGAGE, in seconds. The grab itself lands at FULL
		## predator-parity cost through the ordinary `hit_by_crocodile` path —
		## nothing here is a pulled punch — and then the unit backs off to the
		## ring for this long instead of standing on the respawn point chewing.
		## 8 s is long enough to read as "retrieval attempt logged, withdrawing"
		## and to hand the player the whole invulnerability blink plus a running
		## start; a second grab needs a fresh telegraph anyway, so the honest
		## cost of two hits from one hunter is 8 + 1.8 seconds of daylight.
		"hunt_disengage_time": 8.0,

		## THE NOSE, in metres, and the fourth number of the hunt arm (owner
		## design ruling 2026-08-31, "sled/smell sense"). Beyond direct detection
		## this unit reads the SCENT TRAIL the heroes leave — the breadcrumb ring
		## buffer `crocodile_lod_manager` records at 9 Hz — and walks it toward
		## fresher crumbs. That is what turns "one hunter per seven chunks idles
		## in a corner" into "the retrieval division is working the field": the
		## owner's playtest complaint was never that hunters are absent (a
		## headless sweep finds 8-23 in a loaded ring, 2-8 of them inside 150 m)
		## but that nothing brings them to you.
		##
		## 150 IS SIX TIMES SIM_RADIUS, deliberately, and it is why this feature
		## needed the LOD manager rather than only this file: a hunter at 150 m is
		## slept, and a slept body runs no `_physics_process` at all. See
		## `advance_tracking()` for the slept-but-stalking half.
		##
		## ABSENT = NO NOSE, which is the statement `stink_immune` makes one block
		## down: every animal in the table, and the tower guard on its post,
		## simply does not carry this key and no line of the tracking code can
		## reach them. A second retrieval unit opts in with a number.
		##
		## IT IS A RADIUS, NEVER A SPEED. Tracking moves at this row's own
		## `chase_speed` (6.5, already clamped to MAX_CHASE_SPEED in _ready()), so
		## the lattice is untouched and un-retunable from here: walking (5.0) lets
		## a tracker arrive — that IS the pressure the ruling asks for — and
		## running (9.0 at the slowest character) still leaves it behind.
		"scent_radius": 150.0,

		# ----- Immunities & Fear (beads godot-test1-bvh, godot-test1-upu) -----
		## STINK IMMUNITY DROPPED: by owner ruling 2026-09-04 (bead godot-test1-bvh),
		## gameplay beats fiction — Phoboman's Stink Wave scares hunter robots away
		## as well. "stink_immune": true is removed from this row, so a hunter takes
		## the ordinary flee_from() path like any animal.
		##
		## CRUSH IMMUNITY STAYS: giant-form teibi squashes predators on contact
		## (`_on_player_collision`); this row falls through that block to the
		## ordinary bite path instead, so a giant who steps on a hunter GETS
		## GRABBED rather than popping it. Same sentence as the boss immunity one
		## block up, for a different reason: a boss is too big to squash, this
		## thing is too hard.
		"crush_immune": true,

		## GIANT FEAR (owner ruling 2026-09-04, bead godot-test1-upu): giant Teibi
		## is a deterrent to GD-SURVEY hunters, not a killer. A hunter within this
		## radius of a giant quarry flees (flee_from) every frame while giant, holding
		## for GIANT_FEAR_HOLD after revert. Absent = fearless.
		"fears_giant_radius": 14.0,

		## THE STAKE (see the crocodile row): a corporate grab you escaped costs
		## the most in the table — the one contact that can also take a hero.
		"coin_setback": 0.25,

		## CROWD CONFUSION — Budapest's defence (bead godot-test1-8gw.16).
		## Probability that an ACQUISITION EDGE inside the city is a false alarm:
		## the robot walks to a nearby citizen and checks documents for 2-10 s
		## instead of acquiring the player. Absent = 0.0, so a key-less row
		## behaves byte-for-byte as today. Data, not a species test — the next
		## machine opts in with a row edit. 0.7 is the owner's ceiling; the
		## tower guard does NOT carry it (no crowd indoors).
		"crowd_confusion_chance": 0.7,

		## ...AND TAKING THE HERO IS ITS OWN KEY, not a reading of `behavior`.
		## `player_controller._takes_a_hero()` used to answer `behavior == "hunt"`,
		## which made "the corporation imprisons you" a side effect of how this unit
		## STEERS — so the tower guard, the same chassis on a different duty, could
		## not imprison anybody without being moved onto an arm whose scent tracking
		## and hunt-director seams a sentry on a post must not have (bead
		## godot-test1-3iy.19). The same data-not-species-name shape as
		## `stink_immune` / `crush_immune` / `sweep_exempt`: absent is the statement,
		## and every animal in the table is absent.
		"captures_hero": true,
	},
	"tower_guard": {
		## THE NINTH ROW, AND THE FIRST THAT IS FURNITURE RATHER THAN WILDLIFE.
		## A GD-SURVEY sentry standing a post inside GastroDefense HQ (the tower
		## epic, godot-test1-3iy). Everything that makes it a guard rather than a
		## hunter is in this table plus WHERE IT IS PUT — and that second half is
		## the finding worth stating out loud, because it is why there is NO NEW
		## BEHAVIOUR ARM here:
		##
		##   "patrols its floor and never leaves it" is `set_confinement()`, which
		##   has existed since the elevated-platform guards and whose own docstring
		##   already says "so it patrols but never walks off". `TowerInterior` hands
		##   each guard its storey's box the same way `spawn_platform_crocodiles`
		##   hands a mound-top guard its summit. A "patrol" arm would have been a
		##   second copy of a leash the file already owns, measured by a second
		##   probe, for identical behaviour — the arm dispatch is for a MECHANIC
		##   none of the six covers, not for an animal that is new.
		##
		## So this row is "solo", the arm-less path, and the patrol is geometry.
		"behavior": "solo",

		# ----- Speed and detection -----
		## SLOW ON PATROL, ORDINARY IN PURSUIT. 1.4 is a walked beat rather than an
		## animal's amble — a sentry covering ground it has covered a thousand times
		## — and it is the read that makes a guard something you can watch, time and
		## walk around, which is the sneak-and-solve tempo the epic was ruled to.
		##
		## THE CHASE SPEED IS THE LATTICE AND NOTHING MORE: 5.6 is just over
		## WALK_SPEED (5.0), so strolling past a guard that has seen you WILL be
		## caught, and far under MAX_CHASE_SPEED (8.5) and the slowest run (9.0), so
		## backing out of the room always works. Losing to one costs a hero and the
		## smallest coin bill in the table (see `captures_hero` and `coin_setback`
		## below) — the arrest is the stake, so the sentry has no business also being
		## fast enough to make it unavoidable.
		"move_speed": 1.4,
		"chase_speed": 5.6,

		## Barely any spread. Two or three guards stand in one small building and a
		## visibly mismatched pair reads as a bug rather than as variety; the
		## corporation issues one chassis. Same argument as the hunter's row, one
		## notch tighter because these are seen side by side.
		"speed_random_factor": 0.05,
		"size_random_factor": 0.03,

		## SEES FURTHER, BUT ONLY AHEAD — and the two halves of that sentence are
		## these two numbers, which were retuned together and only make sense
		## together (owner item 3: "with less hunters ... instead of run-away, it's
		## a stealth game").
		##
		## 9.0 m rather than the 6.5 this row shipped with, because a cone that
		## reached one room would leave a guard blind to the corridor it is
		## standing in — and the corridor is where the sneak happens. Still well
		## under the LOD SIM_RADIUS with its margin (9.0 + 15 << 45), which the
		## species table check measures.
		##
		## 120 degrees is the ONLY cone in the table and the first use of the
		## optional field: 60 degrees either side of where the body is walking, so
		## the arc reads as "looking down the corridor" rather than as a torch
		## beam, and the whole 240 degrees behind it is a way past. Everything
		## about how it is applied — acquisition only, never mid-chase, plus the
		## `SPOT_TELEGRAPH_TIME` beat before the flag flips — is in
		## `_update_chase_state`, in the shared detection code above the dispatch,
		## because a cone is part of the smell test and not a behaviour.
		"detection_radius": 9.0,
		"view_cone_deg": 120.0,

		# ----- Organic wandering (a beat, not a meander) -----
		## Long legs between turns and a LONG pause at the end of each: the pause is
		## the sentry's whole tell, the moment it is standing still and looking
		## somewhere. `sniff_pause_chance` is the highest in the table for the same
		## reason — a guard stops much more than it walks.
		"direction_change_interval": 5.0,
		"pause_duration": 1.2,
		"wander_turn_rate": 0.5,
		"turn_smoothness": 6.0,
		"min_wander_speed_factor": 0.8,
		"speed_variation_freq": 0.3,
		"sniff_pause_chance": 0.45,

		# ----- Obstacle avoidance (indoors, so short) -----
		## 1.8 m of feeler rather than the crocodile's 3.0: the building is jambs,
		## piers and pillars, and a long probe indoors turns the guard away
		## from a doorway it is two metres from walking through.
		"avoid_look_ahead": 1.8,
		"avoid_feeler_angle": PI / 4.0,  # 45°, wider than the field rows: corners
		"avoid_feeler_height": 0.5,
		"avoid_speed_factor": 0.7,

		# ----- Model orientation and gait (the hunter chassis, reused) -----
		## SAME MODEL AS THE HUNTER (`assets/models/characters/hunter.glb`), which
		## is the point rather than a saving: a guard and a retrieval unit ARE the
		## same corporate machine on two duties, and they are never in frame
		## together (the hunter belongs to no band and works the field, the guard
		## stands inside one building). So the facing offset and the gait numbers
		## are the hunter's, slowed to the walked beat above — and so is the SIZE:
		## the 2.25x chassis of bead godot-test1-5ow is the shared .glb, so
		## tower_guard.tscn's capsule is the hunter's capsule (radius 0.421875,
		## height 3.0375, at `(0, 0.421875, -0.14625)`) and grew with it. 2.25 m of
		## machine still clears a storey's ~4.6 m ceiling with room to spare.
		"model_facing_offset": -PI / 2.0,
		"stride_frequency": 9.0,
		"waddle_roll": 0.5 * PI / 180.0,
		"bob_amount": 0.012,
		"sway_yaw": 1.0 * PI / 180.0,
		"chase_pitch": 4.0 * PI / 180.0,
		"breathe_speed": 1.0,
		"breathe_amount": 0.002,

		## Never wades — it stands on a floor 400 m from the nearest river band —
		## but the keys are the crocodile's and every row owes them, so they carry
		## the hunter's numbers rather than a zero that would read as a claim.
		"river_sink_depth": 0.22,
		"river_sink_ease_speed": 0.22 / 0.2,

		## The clamp, the hunter's, with a shorter step into it: indoors there is
		## usually a wall behind the quarry.
		"bite_duration": 0.35,
		"bite_pitch": 12.0 * PI / 180.0,
		"bite_lunge": 0.20,

		# ----- THE STAKE, and what makes the guard's DIFFERENT ------------------
		## WHAT LOSING TO A GUARD COSTS: this fraction of your coins — the bill
		## every row in this table now charges — plus, once the authored beat has
		## armed capture, THE HERO (see `captures_hero` below). Owner ruling
		## 2026-09-01 (bead godot-test1-3iy.19) SUPERSEDES the 2026-08-27 third
		## stake: to the player the thing that grabbed them in the HQ is a hunter —
		## it is the same chassis — so it does what a hunter does, and the
		## checkpoint knockback that used to be the guard's whole distinguishing
		## stake is skipped on exactly the contacts that arrest, so the surviving
		## heroes carry on from where the party fell. The knockback still catches
		## every OTHER way to lose inside the building (a pre-beat guard, the
		## press) and it was never this row's anyway — `_pay_coin_setback()`
		## relocates whoever bit you, gated on standing inside the walls.
		##
		## THE NUMBER IS THE LOWEST IN THE TABLE ON PURPOSE, and the arrest is why
		## it stays lowest: the building is the place the campaign asks you to spend
		## the most time in, and a hero in a cell is already the expensive half of
		## the bill. One arithmetic everywhere — a capture does not waive the coins,
		## here or on the hunt arm.
		"coin_setback": 0.07,

		## THE HERO, and it is the hunter's key rather than the hunt arm's
		## behaviour. `behavior` stays "solo" because behaviour is STEERING — the
		## scent trail, the hunt-director's engagement seams, the shadowing lull —
		## and a sentry leashed to one storey by `set_confinement()` must have none
		## of it. What the corporation does with a body it catches is a separate
		## question, so it is a separate key, read by
		## `player_controller._takes_a_hero()` beside `stink_immune` and
		## `crush_immune`. The arming gate is unchanged and is REQUIRED here: the
		## authored Primm rescue happens inside this building, so pre-beat a guard
		## still charges coins and the knockback and takes nobody — a tutorial visit
		## may not strip the roster before the scene that teaches the rule.
		"captures_hero": true,

		## AUTHORED FURNITURE, SO THE RESPAWN SWEEP LEAVES IT ALONE.
		## `player_controller.clear_nearby_crocodiles()` frees every ordinary body
		## within SPAWN_SAFE_RADIUS of a respawn, and from anywhere in a 17.6 m
		## building that is the WHOLE floor — so without this key losing to the
		## press would be the cheapest way past a guarded room. A guard stands
		## an authored post and its lifetime belongs to `reset_guards()`, not to a
		## chunk. Absent everywhere else is the statement, like the two immunities
		## above; the sweep used to infer this from `coin_setback` being non-zero,
		## which stopped meaning anything the day every row grew one.
		"sweep_exempt": true,

		# ----- Immunities: sealed and hard chassis inside a stealth building ----
		## Stated as a DESIGN CHOICE rather than inherited by accident, because the
		## bead asked for the decision out loud (bead godot-test1-bvh): the guard
		## keeps stink_immune even after the hunter lost it by owner ruling 2026-09-04.
		## The guard stands inside a STEALTH BUILDING: a wave that scatters guards
		## turns "time the patrol and walk past" into "press F".
		## Likewise, crush_immune stays, and this row does NOT get fears_giant_radius
		## (bead godot-test1-upu): giants cannot exist indoors anyway (indoor refusal
		## + threshold auto-revert), so the building stays a stealth problem.
		## Guards stay in group "crocodile" (the scene declares it, `_ready` re-adds it)
		## so the LOD manager still sleeps a distant one and the MP relay still sees it;
		## immunity lives in these keys, never in group tricks.
		"stink_immune": true,
		"crush_immune": true,
	},
}

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
## How much of the remaining distance to the quarry the flank offset is allowed
## to be. It is the ONE number that decides whether a ring is a flank or an
## orbit, and it is a property of the algorithm rather than of any animal, which
## is why it sits here and not in a SPECIES row.
##
## WHAT IT ACTUALLY CONTROLS IS A LEAD ANGLE. pack_steer_point() aims at a point
## `ring` metres to one side of the quarry, where ring = min(flank_radius,
## d * TAPER); once d is inside the flank ceiling, that is a target sitting at a
## CONSTANT angle atan(TAPER) = 37° off the straight line in. A pursuer holding a
## constant lead angle walks a logarithmic spiral, and the arc it sweeps closing
## from d0 to d1 is exactly tan(TAPER's angle) * ln(d0 / d1) — 0.75 * ln(16/3) =
## 68° each way for a wolf committing at 16 m, which is the ~136° of surround
## enemy_spawn_selfcheck measures out of a pack that all started on one bearing.
## Turning this up widens the spiral; the two things that stop it are below.
##
## IT MUST STAY STRICTLY BELOW 1.0, and 1.0 is not a rounding but a singularity.
## A wolf already ON its slot bearing at distance d is handed the target
## quarry + d * TAPER * u, which at TAPER = 1.0 is the point it is standing on:
## every point of its own slot ray becomes a fixed point and the pack freezes in
## a ring around a player who can then stroll away. Below 1.0 the same wolf is
## handed a point d * (1 - TAPER) in front of it and always has somewhere to
## walk; its radial closing rate is v / sqrt(1 + TAPER^2), positive for any
## finite value.
##
## AND THAT RATE IS THE REAL CEILING, because it is the walk-catch contract in
## disguise. At 0.75 a wolf spends cos(37°) = 0.80 of its speed actually closing:
## 6.8 * 0.80 = 5.44 m/s toward you, which is the crocodile's 5.5 almost exactly.
## THAT is the number the wolf's chase_speed was chosen to land on — the extra
## 1.3 m/s over a crocodile is the fare for the angle, not a faster catch. Push
## TAPER to 0.85 and the same wolf closes at 5.18, a hair over WALK_SPEED (5.0),
## and the species quietly stops being able to catch a walking player at all.
const PACK_FLANK_TAPER: float = 0.75

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
## trail (see `advance_tracking`), and `mp_manager._send_croc_sync` publishes one
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
## `mp_manager._send_croc_sync` reads exactly this rather than `is_tracking`. The
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
## if it answers `is_river_at`, so the null check below is the whole guard and the
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
	if found_terrain and found_terrain.has_method("is_river_at"):
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
			# a no-op multiply for all four older rows. Gated on `is_chasing` and
			# NOT on `is_fleeing`: the flee branch above sits over
			# _update_chase_state, so a fleeing predator never runs the arm and
			# would otherwise carry whatever factor it held when the wave hit.
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
	if q == null:
		return false
	if q.has_method("is_giant"):
		return q.is_giant()
	if "is_giant" in q:
		return bool(q.get("is_giant"))
	return false


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
			spot_clock = 0.0
			if _spot_label != null:
				_spot_label.visible = false
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
	chase_target = pack_steer_point(
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
	chase_target = charge_steer_point(
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
	burst_factor = burst_cycle_factor(global_position, _burst_lock, spec)


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
	if not ranged_shot_due(flat.length(), get_physics_process_delta_time(), _ranged_lock, row):
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

	chase_target = hunt_steer_point(chase_target, global_position, closing,
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
			+ bearing.normalized() * leap_reach(chase_speed_instance, spec)
	# `in_territory()` is meaningless on a non-boss (home_position is never
	# captured there), so a hypothetical ordinary leaper is simply unleashed —
	# the same shape as every other `is_boss` gate in this file.
	var landing_ok := (not is_boss) or in_territory(landing)
	if leap_due(true, landing_ok, get_physics_process_delta_time(), _leap_lock, spec):
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


static func hunt_steer_point(quarry: Vector3, from: Vector3, closing: bool,
		standoff: float) -> Vector3:
	"""
	Where one hunter steers: at the quarry when closing, at the RING when not.

	    closing    -> quarry                       (walk in and take it)
	    shadowing  -> quarry + standoff * away     (hold the ring, either way)

	`away` is the flat unit vector FROM the quarry TO this unit, so the one
	expression covers both halves of shadowing with no branch: a hunter outside
	the ring walks in to it, and one inside the ring — the state a grab leaves it
	in, standing on top of the player — walks OUT to it. That is what makes
	"withdraw after the grab" and "pace before the grab" the same line of code,
	and it is why the disengage needs no geometry of its own.

	STATIC AND PURE for the same reason `pack_steer_point`, `charge_steer_point`
	and `burst_cycle_factor` are: enemy_spawn_selfcheck's shadow/close probe
	drives THIS function, so the ring it measures is the ring the game ships
	rather than a restatement of it that can drift apart from it.

	Three properties follow from that, each a requirement rather than an accident:

	  * LOD-SAFE. It has no memory at all — no lock, no integrator, no phase. A
	    waking hunter recomputes the identical point from where it is standing
	    now, so the first frame back is the frame it would have produced had it
	    never slept. (The arm's two timers are the part with memory, and the note
	    on `_hunt_lock` covers those.)
	  * MULTIPLAYER-SAFE. `quarry` is whatever _update_chase_state resolved, which
	    in a room is the nearest ROOM MEMBER. This only bends that point; it can
	    neither widen who is hunted nor reach past the detection radius.
	  * SPEED-LATTICE-SAFE. It returns a POINT. Nothing here touches
	    `chase_speed_instance`, which _ready() already clamped to MAX_CHASE_SPEED.
	    A hunter is frightening because it commits and does not stop, never
	    because it is fast; running escapes it in every phase.

	@param quarry: where the chase currently wants to go
	@param from: this hunter's own position
	@param closing: true once the telegraph is spent and the director has granted
	@param standoff: metres of ring to hold while shadowing (the row's hunt_standoff)
	@return the point to steer at this frame

	A standoff of zero or less answers `quarry` — a hunter with no ring is an
	ordinary chaser rather than a body dividing by zero — as does standing exactly
	on the quarry, where there is no bearing to hold a ring on. Same
	degrade-don't-crash rule as everywhere else in this file.
	"""
	if closing or standoff <= 0.0:
		return quarry
	var away := from - quarry
	away.y = 0.0
	if away.length() < 0.01:
		return quarry
	return quarry + away.normalized() * standoff


static func ranged_shot_due(distance: float, delta: float, lock: Dictionary,
		row: Dictionary) -> bool:
	"""
	May a ranged predator release a shot this frame? Advances its cooldown.

	    each frame  cooldown -= delta            (always, even out of band)
	    fire when   cooldown <= 0 AND min_fire_range <= distance <= max_fire_range
	    on firing   cooldown := fire_cooldown

	@param distance: flat distance from the shooter to its quarry, metres
	@param delta: seconds since the last call (the physics tick)
	@param lock: this shooter's `_ranged_lock`, MUTATED here. Empty = ready now.
	@param row: the species row's "ranged" dict
	@return true exactly on the frames a shot should be launched

	STATIC AND PURE for the same reason `burst_cycle_factor` and
	`pack_steer_point` are: enemy_spawn_selfcheck's cadence probe drives THIS
	function, so the measured cadence is the shipped cadence and not a
	restatement of it that can drift.

	THE COOLDOWN TICKS EVEN WHILE OUT OF BAND, which is a decision and not an
	accident: an archer that had to stand still for its full cooldown after you
	stepped out of range and back in would reward yo-yoing across the 10 m floor,
	and the floor exists to make closing the distance the counterplay rather than
	a way to disarm the boss for three seconds. It never accumulates CREDIT —
	the clamp at zero means the longest wait is one full cooldown and the reward
	for a long walk between engagements is one immediate shot, not five.
	"""
	var left: float = float(lock.get("cooldown", 0.0)) - delta
	lock["cooldown"] = maxf(left, 0.0)
	if distance < float(row["min_fire_range"]) or distance > float(row["max_fire_range"]):
		return false
	if left > 0.0:
		return false
	lock["cooldown"] = float(row["fire_cooldown"])
	return true


static func leap_airtime(row: Dictionary) -> float:
	"""
	How long one hop keeps a body off the ground, in seconds.

	    t = 2 * leap_launch_speed / leap_gravity

	The whole of a symmetric ballistic arc: up at `leap_launch_speed`, down under
	`leap_gravity` (the row's own, not the file's GRAVITY — see `_behave_leap`),
	back to the flat world's y = 0. The apex it implies is
	`leap_launch_speed^2 / (2 * leap_gravity)`, which is the number to tune a
	silhouette against.

	@param row: the species row, for the two arc keys
	@return the airtime in seconds, or 0.0 for a row that cannot hop

	A row missing either key answers 0.0 — which makes `leap_reach()` zero and
	`leap_due()` refuse — so a half-finished species degrades to an ordinary
	ground chase instead of dividing by zero. The same degrade-don't-crash rule as
	`burst_cycle_factor`'s missing-distance answer and the unknown-behaviour
	fallback in the dispatch.
	"""
	var launch: float = float(row.get("leap_launch_speed", 0.0))
	var arc_gravity: float = float(row.get("leap_gravity", 0.0))
	if launch <= 0.0 or arc_gravity <= 0.0:
		return 0.0
	return 2.0 * launch / arc_gravity


static func leap_reach(chase_speed: float, row: Dictionary) -> float:
	"""
	How far one hop carries a body across the ground, in metres.

	    reach = leap_airtime(row) * chase_speed * leap_speed_factor

	@param chase_speed: the body's RESOLVED chase speed (already clamped to
	                    MAX_CHASE_SPEED by _ready(); a boss's is BOSS_CHASE_SPEED
	                    scaled by the distance gradient and clamped)
	@param row: the species row
	@return the ground distance the arc covers

	STATIC AND PURE for the reason every helper in this block is: the arm projects
	its landing point with this, and enemy_spawn_selfcheck's leap probe measures
	the cycle with it, so the reach the leash is asked about is the reach that
	ships. It is the horizontal leg of the same arc `leap_airtime` describes,
	assuming the body holds its heading for the hop — which is the OUTERMOST
	landing the leash's steer can produce and therefore the conservative one to
	test a fence against.
	"""
	return leap_airtime(row) * chase_speed * float(row.get("leap_speed_factor", 1.0))


static func leap_due(grounded: bool, landing_ok: bool, delta: float, lock: Dictionary,
		row: Dictionary) -> bool:
	"""
	May a leaping predator launch this frame? Advances its GROUNDED recovery clock.

	    airborne     never (and the clock does not tick — the arc is not recovery)
	    each grounded frame  cooldown -= delta
	    hop when     cooldown <= 0 AND the projected landing is legal
	    on hopping   cooldown := leap_cooldown

	@param grounded: is_on_floor() — the arc runs itself, this only starts one
	@param landing_ok: has the caller's `in_territory()` accepted the landing point
	@param delta: seconds since the last call (the physics tick)
	@param lock: this body's `_leap_lock`, MUTATED here. Empty = ready now.
	@param row: its SPECIES row, for the arc and cooldown keys
	@return true exactly on the frames a launch should happen

	STATIC AND PURE for the same reason `ranged_shot_due` and `burst_cycle_factor`
	are: enemy_spawn_selfcheck's leap probe drives THIS function, so the measured
	cadence and the measured cycle average are the shipped ones and not a
	restatement that can drift.

	THE CLOCK DOES NOT TICK IN THE AIR, unlike the archer's, and that is the
	opposite decision made for the opposite reason. An archer's cooldown ticks even
	out of band so that stepping in and out of range cannot disarm it; a hop's
	recovery is the PRICE of the hop, so letting the airtime pay part of it would
	shorten the recovery leg the escape guarantee is balanced on. `leap_cooldown`
	therefore means exactly "seconds on the ground between one landing and the next
	launch", which is what the probe's cycle arithmetic assumes.

	A REFUSED LANDING COSTS NOTHING. The clock still drains (a boss pinned at its
	fence is not also made to wait) but it is not re-armed, so the hop happens on
	the first frame the leash allows one. It never accumulates credit either — the
	clamp at zero means the longest wait is one full cooldown.
	"""
	if leap_airtime(row) <= 0.0:
		return false
	if not grounded:
		return false
	var left: float = float(lock.get("cooldown", 0.0)) - delta
	lock["cooldown"] = maxf(left, 0.0)
	if left > 0.0 or not landing_ok:
		return false
	lock["cooldown"] = float(row["leap_cooldown"])
	return true


static func burst_cycle_factor(from: Vector3, lock: Dictionary, row: Dictionary) -> float:
	"""
	Which leg of the burst cycle this animal is on, as a speed multiplier.

	    each frame  travelled += |from - lock.last|   (PATH LENGTH, see below)
	    flip when   travelled >= (burst_distance if bursting else recover_distance)
	    on flip     bursting := not bursting, travelled := 0
	    factor      burst_factor while bursting, recover_factor while recovering

	THE CYCLE IS MEASURED IN METRES, NOT SECONDS, and that is the same call
	`charge_steer_point` makes for the same two reasons. `_update_chase_state` has
	no `delta` (see the note on the dispatch), so a timer would have had to be
	plumbed through every arm to serve one of them — and a distance is LOD-SAFE
	for free: a slept predator does not move, so its leg does not drain, and it
	wakes on the leg it slept on. A seconds-based cycle would have run down during
	the sleep and handed the player a cougar that arrives already exhausted, or
	one whose pounce was spent 40 m away where nobody could see it.

	THE METRES ARE PATH LENGTH, NOT DISPLACEMENT FROM WHERE THE LEG STARTED, and
	that distinction is the whole correctness of this function rather than a
	refinement of it. The bear's `charge_steer_point` measures displacement from
	its lock origin, which is right for a bear: what it is asking is "how far have
	I got from where I took aim". Ask a BURST the same question and a predator
	that never gets far from its starting point never finishes its pounce — a
	cougar steered around a massif, or one following a player who circles it
	inside a four-metre radius, stays inside `burst_distance` of its origin
	forever and therefore runs at 11 m/s indefinitely, which is precisely the
	promise this whole species was built to keep. Path length has no such hole:
	every metre the animal actually covers is a metre of pounce spent, whatever
	shape it covered it in. It also gives the pinned-against-a-block case the
	physically honest answer for free — a body that is not moving is not spending
	its burst, and it resumes with the metres it had left.

	Three properties follow from it being a pure function of the lock, and each
	one was a requirement rather than a happy accident:

	  * LOD-SAFE, as above, with no timer to have drained.
	  * MULTIPLAYER-SAFE. It reads only this body's own position and its own lock,
	    and returns a scalar. A remote-driven predator never runs the arm at all —
	    it renders the master's samples, and CROC_REMOTE_MAX_SPEED (40.0) is
	    comfortably above any burst — so there is no second simulation to
	    disagree and no new byte on the wire.
	  * LATTICE-SAFE OVER THE CYCLE, WHICH IS THE ONLY SENSE THAT MATTERS. The
	    factor multiplies `chase_speed_instance`, which _ready() already clamped to
	    MAX_CHASE_SPEED, so the burst is an explicit, auditable multiple of the
	    ceiling rather than an unbounded speed. `burst_factor` is above 1.0 and
	    `recover_factor` below it, and the two legs together average out under the
	    slowest run and over the walk — measured, not asserted, in check 8.

	@param from: this animal's own position
	@param lock: its cycle state, MUTATED here — { "bursting", "origin" }
	@param row: its SPECIES row, for the four burst_* keys
	@return the multiplier to apply to chase_speed_instance this frame

	A row missing either distance answers 1.0 — an ordinary chase — so a
	half-finished species degrades to a crocodile instead of dividing by zero.
	That is the same degrade-don't-crash rule as the unknown-species fallback in
	_ready() and the unknown-behaviour fallback in the dispatch.

	ponytail: a predator pinned against a block covers no path, so it does not
	advance its leg and resumes with the metres it had left. That is the right
	answer rather than a shortcut — a pounce is metres of ground covered, and a
	cat shouldering into stone has covered none of them. The one visible
	consequence is that it comes round the corner still on the leg it arrived on,
	which reads as a cat coiled at the corner. The upgrade path, if it ever
	matters, is the bear's: flip the leg on a blocked feeler.
	"""
	var burst_distance: float = float(row.get("burst_distance", 0.0))
	var recover_distance: float = float(row.get("recover_distance", 0.0))
	if burst_distance <= 0.0 or recover_distance <= 0.0:
		return 1.0

	if not lock.has("last"):
		lock["last"] = from
		lock["travelled"] = 0.0
		lock["bursting"] = true
	# Path length, one frame at a time — see the docstring for why this is not
	# `from.distance_to(origin)`. The step is the ground this body actually
	# covered since the last frame it was chasing, so a curve spends its pounce
	# at the same rate a straight line does.
	var travelled: float = float(lock["travelled"]) + from.distance_to(lock["last"])
	lock["last"] = from
	var bursting: bool = bool(lock["bursting"])
	var leg: float = burst_distance if bursting else recover_distance
	if travelled >= leg:
		bursting = not bursting
		lock["bursting"] = bursting
		travelled = 0.0
	lock["travelled"] = travelled
	return float(row["burst_factor"]) if bursting else float(row["recover_factor"])


static func charge_steer_point(quarry: Vector3, from: Vector3, lock: Dictionary,
		commit: float) -> Vector3:
	"""
	Where one heavy charger steers, given its own position and its own lock.

	    re-lock when   dir is unset OR |from - lock.origin| >= commit
	    on re-lock     dir := bearing to the quarry, origin := here
	    point          from + dir        (one metre along the committed bearing)

	THE BEHAVIOUR IS THE STALENESS. Every other predator in this game recomputes
	its heading from the quarry's CURRENT position every frame, so it curves onto
	you and a sidestep only ever buys the width of the curve. This one takes that
	reading once and then spends `commit` metres refusing to take another, so a
	sidestep during those metres is not a curve to be out-turned — the bear is
	aiming at a place you are simply not standing any more. That is the entire
	counterplay, and it is why the dodge works at a WALK against an animal faster
	than a walk. enemy_spawn_selfcheck measures it against the same bear with this
	function switched off, because "the player dodged" is also true of a bear that
	merely turns slowly.

	IT RETURNS A POINT ONE METRE AHEAD, not a distant aim point, and the metre is
	arbitrary in the only way that matters: `_chase_player` normalizes
	`chase_target - global_position`, so any positive multiple of `dir` produces
	the identical heading. One metre keeps the value readable in a debugger as
	"just in front of its nose", which is exactly what a charging bear is looking
	at.

	Three properties follow from it being a pure function of the lock, and each
	one was a requirement rather than a happy accident:

	  * LOD-SAFE. A slept bear does not move, so `|from - origin|` does not grow
	    and it wakes still committed to the bearing it slept on — with no timer to
	    have drained meanwhile, which is precisely the bug a seconds-based commit
	    would have had (see the note on `charge_commit` in the SPECIES row).
	  * MULTIPLAYER-SAFE. `quarry` is whatever _update_chase_state resolved, which
	    in a room is the nearest ROOM MEMBER. This only bends that point; it can
	    neither widen who is hunted nor reach past the detection radius. A
	    remote-driven bear never runs the arm at all — it renders the master's
	    samples — so there is no second simulation to disagree.
	  * SPEED-LATTICE-SAFE. It returns a POINT. Nothing here touches
	    chase_speed_instance, which _ready() already clamped to MAX_CHASE_SPEED.
	    A charging bear is dangerous because it does not need to slow down to
	    turn, never because it is fast; running still escapes it.

	@param quarry: where the chase currently wants to go
	@param from: this bear's own position
	@param lock: its committed bearing, MUTATED here — { "dir", "origin" }
	@param commit: metres of straight line before it looks up again
	@return the point to steer at this frame

	ponytail: the lock is cleared by the arm on losing the chase and never
	otherwise, so a bear that is knocked off course by a block finishes its
	committed metres against the wall before re-aiming. That reads as a bear
	shouldering into stone, which is the right animation for the wrong reason;
	the upgrade path, if it ever matters, is to re-lock on a blocked feeler.
	"""
	var dir: Vector3 = lock.get("dir", Vector3.ZERO)
	if dir == Vector3.ZERO or from.distance_to(lock["origin"]) >= commit:
		var aim := quarry - from
		aim.y = 0.0
		if aim.length() < 0.01:
			# Standing on top of the quarry: there is no bearing to commit to, so
			# leave the lock alone and let the plain chase have this frame.
			return quarry
		dir = aim.normalized()
		lock["dir"] = dir
		lock["origin"] = from
	return from + dir


static func pack_steer_point(quarry: Vector3, from: Vector3, id: int,
		pack_size: int, flank_radius: float) -> Vector3:
	"""
	Where one pack hunter steers, given only ITS OWN id and ITS OWN position.

	    slot  = id modulo pack_size          -> this animal's compass point
	    ring  = min(flank_radius, d * TAPER) -> how wide the swing still is
	    point = quarry + ring * (sin, 0, cos) of TAU * slot / pack_size

	THE SURROUND IS EMERGENT, AND "EMERGENT" HERE HAS A PRECISE MEANING: nothing
	in this function can see another wolf. There is no coordinator, no leader, no
	registry, no group scan and not one byte of inter-agent communication — six
	wolves each running this arrive on six different bearings for the same reason
	six people each told to stand at a different hour of a clock face end up in a
	circle. What they share is the CLOCK (this function), never a message.

	Three properties follow from it being PURE, and each one is a requirement
	this bead had to meet rather than a happy accident:

	  * LOD-SAFE. The LOD manager sleeps distant crocodiles by zeroing velocity
	    and switching off _physics_process. A slept wolf therefore stops steering
	    — and cannot corrupt the pack's shape, because no other wolf was ever
	    reading it. A waking one recomputes this from where it is standing NOW,
	    with no integrator, no accumulated phase and no remembered target to
	    catch up to, so it rejoins its slot with no lurch: the first frame back
	    produces exactly the point it would have produced had it never slept.
	  * MULTIPLAYER-SAFE. `quarry` is whatever _update_chase_state resolved,
	    which in a room is the nearest ROOM MEMBER (a RemoteAvatar is in no
	    group, so it is found through presence, never through group "player").
	    This function only bends that point; it cannot widen who is hunted or
	    reach past the detection radius, and every peer computing it gets the
	    same answer from the same id.
	  * SPEED-LATTICE-SAFE. It returns a POINT. Nothing here touches
	    chase_speed_instance, which _ready() already clamped to MAX_CHASE_SPEED.
	    A flanking wolf covers more ground than a charging one at the SAME speed,
	    which is the entire trick: the pack is dangerous because it cuts angles,
	    and running still escapes it.

	The ring is anchored to WORLD compass bearings rather than to the quarry's
	facing, deliberately. A ring that rotated with the player would swing every
	wolf sideways the instant the player turned around — a pack that pirouettes
	on camera input. World-anchored, a wolf holds its bearing and the player is
	the one who has to keep turning to face it.

	ponytail: slots are claimed by `id % pack_size` with nobody arbitrating, so
	two wolves CAN draw the same bearing (see pack_size for why the ring is wider
	than the pack). They are solid to one another (collision_mask 3) and simply
	jostle, which reads as two wolves fighting over an angle. The upgrade path,
	if it ever matters, is the one thing this bead was told not to build: a
	claim, which needs a coordinator.
	"""
	if pack_size <= 0 or flank_radius <= 0.0:
		return quarry

	var to_quarry := quarry - from
	to_quarry.y = 0.0
	# The taper is what turns a ring into a spiral — see PACK_FLANK_TAPER for the
	# proof that it converges. Note it uses the wolf's CURRENT distance, so the
	# offset shrinks continuously rather than switching off at a threshold; there
	# is no radius at which a wolf visibly changes its mind.
	var ring := minf(flank_radius, to_quarry.length() * PACK_FLANK_TAPER)
	var angle := TAU * float(posmod(id, pack_size)) / float(pack_size)
	return quarry + Vector3(sin(angle), 0.0, cos(angle)) * ring


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
	# neither walk nor (`mp_manager._send_croc_sync` skips sleepers) travel to
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
	this has to be runnable from `mp_manager._apply_dead()` on a peer where nobody
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
	if terrain and is_on_floor() and terrain.is_river_at(global_position):
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
