class_name SpeciesTable
extends RefCounted
## THE SPECIES TABLE — every predator in this game as one const dictionary.
##
## Lifted whole out of piglet_crocodile_ai.gd by bead godot-test1-ftn.10, which
## is a MECHANICAL extraction: not one row, key, number or comment changed, and
## the rows are in the order they have always been in. The AI keeps
## `const SPECIES := SpeciesTable.SPECIES`, so every reader — `CROC_SCRIPT.SPECIES`
## in the selfchecks, `BIOME_SPECIES` / `BIOME_BOSS` in endless_terrain.gd, the
## body's own `_ready()` row resolution — is untouched. The reasoning came WITH
## the data, because a row's numbers are only legible next to the argument for
## them.
##
## This file is DATA and depends on nobody: the behaviour arms, the guards
## (`stink_immune` / `crush_immune` / `captures_hero`) and every game-wide const
## the table deliberately does NOT hold stay with the body they steer.

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
		## every OTHER way to lose inside the building (the press, a boss
		## projectile, an animal that followed you in) and it was never this
		## row's anyway — `_pay_coin_setback()`
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
		## `crush_immune`. THERE IS NO LONGER AN ARMING GATE (owner ruling
		## 2026-09-05, bead godot-test1-bxx, "yes, from start"): this row arrests
		## from the first second of a run, so a guard met on a tutorial visit CAN
		## cost a hero — the ruling's accepted consequence, not an oversight.
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
