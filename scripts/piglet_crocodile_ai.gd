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
		## child, so this local offset is scaled by the engine: a 6x boss sinks
		## 6 × 0.18 = 1.08 m in world space and shows 6 × 0.060 = 0.36 m of ridge.
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
		## one that hunts you. The 7.5 strike is what it spends the difference on.
		"behavior": "ambush",

		# ----- Speed and detection -----
		## THE LATTICE IS THE LATTICE: 5.0 (WALK_SPEED) < 7.5 <= 8.5
		## (MAX_CHASE_SPEED) < 9.0 (the slowest character's run). This is the
		## fastest STRIKE in the table and it is the only thing this animal has.
		## The worst case still clamps (7.5 x 1.2 x 1.6 = 14.4, cut to 8.5), so
		## RUNNING ESCAPES A VIPER exactly as it escapes everything else — which is
		## the whole counterplay, because escaping the strike means noticing it in
		## the ~1 s it takes to cross 5 m.
		##
		## MOVE_SPEED IS ZERO, AND IT IS A BEHAVIOUR, NOT A TUNING. `_wander_speed`
		## multiplies it, so a buried viper's wander velocity is identically 0 at
		## every point of the sin cycle and for every roll of speed_factor: it
		## holds the spot it spawned on until something walks into its 5 m. That is
		## the "does not close distance on a passing player" half of the ambush,
		## and croc_spawn_selfcheck MEASURES it against a walking quarry rather
		## than trusting this number. The one place it needs care is
		## `_animate_body`, whose stride divisor is this value — see the maxf()
		## there, which exists for this row and only this row.
		"move_speed": 0.0,
		"chase_speed": 7.5,

		## ±20% / ±20%. TIGHTER on speed than phase 2's ±35%, and that is the
		## ambush changing the argument rather than a nerf being undone. The
		## SPECIES doc block above is right that a slow roll is a feature — a
		## straggler in a crowd reads as a straggler. An ambusher is not in a
		## crowd: it gets ONE strike from 5 m, and at ±35% the bottom roll is
		## 4.88 m/s, UNDER WALK_SPEED — not a straggler but a viper the player
		## strolls away from mid-lunge with nothing on screen to explain it. ±20%
		## floors the strike at 6.0: still caught by a run, never by a walk. Size
		## keeps its ±20%; a fat viper is still a viper.
		"speed_random_factor": 0.2,
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
		## a key it does not carry. (croc_spawn_selfcheck derives its required key
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
		## one thing an ambush cannot afford. croc_spawn_selfcheck measures this
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
		## use is a key it does not carry. (croc_spawn_selfcheck derives its
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
		## those working while still reading as weight. croc_spawn_selfcheck
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
## croc_spawn_selfcheck measures out of a pack that all started on one bearing.
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
## has any business knowing about it. Always false for every species whose row
## has no `ambush_burrow_depth`.
var is_burrowed: bool = false

## THE CHARGE ARM'S ONE PIECE OF MEMORY (`_behave_charge`): the bearing this bear
## committed to and the point it committed from, as { "dir": Vector3, "origin":
## Vector3 }. Empty means "not committed". It is a Dictionary rather than two
## floats so `charge_steer_point()` can be a STATIC function that both the arm
## and croc_spawn_selfcheck's dodge probe drive — the check measures the shipped
## steering instead of a restatement of it, exactly as it does for the wolf's
## `pack_steer_point()`. Behaviour-local: nothing outside the charge reads it.
var _charge_lock: Dictionary = {}

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
	var distance_factor := 1.0 + clampf(
		absf(global_position.x) / DISTANCE_SPEED_SCALE_DENOM, 0.0, DISTANCE_SPEED_SCALE_MAX
	)

	if is_boss:
		# Bosses take NO per-instance random rolls: their size comes from the
		# terrain's deterministic schedule (boss_scale) and their speeds are fixed,
		# so a boss regenerates byte-identically when its chunk is revisited.
		detection_radius = BOSS_DETECTION_RADIUS
		move_speed_instance = spec["move_speed"]
		# The MAX_CHASE_SPEED cap keeps the running-escape hatch true at any distance.
		chase_speed_instance = minf(BOSS_CHASE_SPEED * distance_factor, MAX_CHASE_SPEED)
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
		# Bosses scale the cull range by their body scale: a 6x boss is visible
		# from ~6x further, so culling it at the regular 60 m would make a
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
			# Run directly away from the player.
			_flee()
		else:
			_update_chase_state()
			if is_chasing and player_node:
				# Chase the player
				_chase_player()
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

		# Rotate smoothly toward the desired heading and move that way.
		# Driving velocity from facing (not the raw direction) prevents sliding
		# sideways and makes turns curve naturally.
		if movement_direction.length() > 0.1:
			var target_rotation := atan2(movement_direction.x, movement_direction.z)
			# Turn harder while avoiding so we actually clear the block in time.
			var turn_rate: float = spec["turn_smoothness"] * (2.0 if avoiding else 1.0)
			rotation.y = lerp_angle(rotation.y, target_rotation, delta * turn_rate)

			# Flee and chase both move at the faster "chase" speed.
			var current_speed := chase_speed_instance if (is_chasing or is_fleeing) else _wander_speed(delta)
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

	# Update chase state based on detection radius. `distance_to_player` is INF
	# when nothing is smellable, so the grounded rule is folded into this one test.
	# Bosses smell farther (still well under the LOD SIM_RADIUS — see the const);
	# `detection_radius` is resolved once in _ready(), see the var.
	if distance_to_player <= detection_radius:
		if not is_chasing:
			# Just started chasing
			is_chasing = true
			# Bosses announce themselves with a growl on the not-chasing →
			# chasing transition (null-safe group lookup, like every SFX hook —
			# a scene run without Main just stays silent).
			if is_boss:
				var sm := get_tree().get_first_node_in_group("sound_manager")
				if sm and sm.has_method("play_boss_growl"):
					sm.play_boss_growl()
	else:
		if is_chasing:
			# Lost the player (too far OR player jumped)
			is_chasing = false
			# Choose new random direction
			_choose_new_direction()

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
	#   between arms, no `if` before the match. Ambush, pounce, charge and urban
	#   patrol are each two lines here plus one function of their own, and none
	#   of them has to read, or risk breaking, any of the others.
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
	  * "high-speed strike"   -> `chase_speed` 7.5, clamped by MAX_CHASE_SPEED
	                             like every other row.
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
	than a walk. croc_spawn_selfcheck measures it against the same bear with this
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
	flee_time_remaining = duration
	flee_source = source
	flee_tracks_player = tracks_player
	is_chasing = false


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
	# 6x boss's capsule alone reaches 0.7 * 6 = 4.2 m ahead of its origin — past the
	# fixed 3 m world-space feeler, leaving avoidance completely dead from boss 4 on
	# (useful reach 1.25 m, 0.64 m, 0.03 m, 0, 0 …) against a body that is also 6x
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

	lod_active = active

	# Stop (or resume) the per-tick physics callback itself. Asleep → the engine
	# never calls _physics_process on this crocodile, saving the script dispatch.
	set_physics_process(active)
	if not active:
		velocity = Vector3.ZERO
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

	_remote_pos = pos
	_remote_yaw = fposmod(yaw, TAU)

	is_chasing = (flags & MpManager.CROC_FLAG_CHASING) != 0
	is_fleeing = (flags & MpManager.CROC_FLAG_FLEEING) != 0
	is_paused = (flags & MpManager.CROC_FLAG_PAUSED) != 0
	if (flags & MpManager.CROC_FLAG_BITING) != 0:
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
	    size schedule (2.5x and up — always bigger than any regular croc's roll)
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
	var facing := Basis(Vector3.UP, spec["model_facing_offset"])
	var oscillation := Basis.from_euler(Vector3(current_pitch, yaw_sway, roll))
	model.transform.basis = (oscillation * facing).scaled(model_base_scale)
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
	# A REMOTE-DRIVEN crocodile never runs the behaviour dispatch — it renders the
	# master's samples instead of simulating — so the ambush arm's flag would stay
	# false and a viper the master has buried would sit on the sand on every other
	# peer. Every input the arm uses arrives in the sample's flag byte, so the flag
	# is recomputed here from the arm's own rule.
	#
	# UNDER THE SAME GUARD AS THE ARM, WHICH IS THE WHOLE SUBTLETY. The master
	# reaches _update_chase_state only when it is neither paused nor fleeing;
	# through either state its `is_burrowed` FREEZES at whatever it last was. A
	# peer that kept recomputing would not freeze with it — a striking viper hit
	# by a Stink Wave clears `is_chasing` on its way into the flee, so the master
	# would hold it surfaced for the whole flight while every client buried it.
	# Both flags ride the same sample byte (CROC_FLAG_PAUSED / CROC_FLAG_FLEEING),
	# so freezing on both sides freezes at the same value. Keyed off the row's own
	# tunable, exactly like the ease below: no species name is tested outside the
	# dispatch.
	if remote_driven and not is_paused and not is_fleeing:
		is_burrowed = not is_chasing and spec.has("ambush_burrow_depth")

	var target_y: float = model_rest_y
	if terrain and is_on_floor() and terrain.is_river_at(global_position):
		target_y = model_rest_y - spec["river_sink_depth"]
	# THE AMBUSHER'S BURROW COMPOSES HERE rather than in a second easing of its
	# own, and "whichever target is DEEPER" is the whole composition: a viper that
	# is burrowed AND standing in a river is simply burrowed. That keeps this
	# function the single writer of `model_base_y` — the property the docstring
	# above promises the animation does not fight over — instead of two easings
	# racing for it.
	if is_burrowed:
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
	model.transform.basis = (snap * facing).scaled(model_base_scale)
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
	# A BOSS is bigger than even giant-form Teibi (2.5x+ vs the giant scale), so
	# giant form gets bitten like anyone else — bosses are never crushable. This
	# early check sits ABOVE the crush block so that block stays untouched.
	# ponytail: the few bite lines below are duplicated from the normal path on
	# purpose — a shared helper would tangle this with the crush block another
	# change owns; fold them together once that settles.
	if is_boss:
		print("💀 BOSS crocodile bites the player!")
		_start_bite()
		if player.has_method("hit_by_crocodile"):
			player.hit_by_crocodile()
		elif player.has_method("reset_position"):
			player.reset_position()
		_pause_and_change_direction()
		return

	# Giant Teibi squashes crocodiles on contact instead of being bitten.
	# Instead of vanishing in one frame, the croc visibly dies: physics stops,
	# a dust puff pops, a crunch plays, the player's camera gets a tiny kick,
	# and the body squashes flat before freeing itself.
	if player.has_method("crushes_crocodiles") and player.crushes_crocodiles():
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

	# Tell the player it was bitten. hit_by_crocodile() plays the red flash /
	# camera shake / brief freeze and then respawns; older saves without it fall
	# back to a plain reset.
	if player.has_method("hit_by_crocodile"):
		player.hit_by_crocodile()
	elif player.has_method("reset_position"):
		player.reset_position()
	else:
		# Fallback: move player up and away
		if player is Node3D:
			player.global_position = Vector3(0, 2, 0)

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
