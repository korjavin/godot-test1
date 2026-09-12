extends RefCounted
## THE SKINNED RIG — the same walk, written onto BONES (bd godot-test1-5u3.2,
## epic `5u3`; the column the spike `5u3.1` shot and the owner picked), and since
## bd godot-test1-5u3.9 a walk a human would recognise.
##
## THE PICK WAS **PROC** (epic `5u3` NOTES, 2026-09-11): the sine rig
## re-expressed as bone rotations, not clips. The CC0 clip route died on its
## licence (Quaternius QAL v1.0 §3(a) forbids redistributing the files), so
## there is no `AnimationPlayer` here either — the pose is still a pure function
## of (hero, phase, gait state), which is the property that lets a remote mirror
## draw the same walk off a distance-driven phase with nothing added to the
## presence packet.
##
## WHAT A SKELETON BUYS that five whole-limb nodes could not: the joints — and
## bead `5u3.9` is the bead that spends them. Owner, 2026-09-11: *"human bodies
## for characters (our 4) i mean natural movements"*. Six things separate this
## from the sine it started as, and every one of them is a pure function of what
## the caller already computes:
##
##   1. THE KNEE IS PHASED AGAINST THE THIGH, not rectified off it. See
##      `set_clock()` — the whole reason this driver is handed a quadrature.
##   2. THE ANKLE COUNTER-ROTATES the thigh and the knee, so the sole stays
##      level and a planted foot reads as planted rather than as pointed.
##   3. THE PELVIS drops and twists with the stride, and `spine_02` takes the
##      same turn back, so the shoulders above it stay level.
##   4. THE ELBOW flexes a quarter-cycle behind the shoulder and the CLAVICLE
##      rolls with it, so the two arms are a linkage rather than two sticks.
##   5. STANDING STILL BREATHES (chest, ~0.25 Hz) and shifts its weight (pelvis,
##      ~0.13 Hz) — both off the caller's clock, so no RNG and no new state.
##   6. A LANDING IS ABSORBED THROUGH THE KNEES, not only through the `Body`
##      dip and the container squash the caller writes.
##
## ### THE BONE-ROLL TRAP — read this before touching a write below
##
## MakeHuman bones carry ROLLS. On the imported `game_engine` rig `thigh_l`'s
## own X axis reads (0.89, 0.21, -0.41) and `upperarm_l`'s reads
## (0.11, -0.99, 0.02), so `set_bone_pose_rotation(idx, Quaternion(RIGHT, a))`
## — a rotation about the BONE's X — swings a leg sideways and spins an arm
## about its own length. **Never write a per-bone axis table**: it is one more
## thing to get wrong per hero, and the next hero's rig will roll differently.
##
## Instead every write here is expressed about the SKELETON's axes and
## conjugated through the bone's PARENT global rest basis — `P⁻¹ · R · P` is the
## same turn written in the space `set_bone_pose_rotation()` expects. That is
## roll-agnostic, so it needs no table and no per-hero tuning (spike `5u3.1`'s
## finding; the probe that recorded it retired with bead `5u3.3`, and `_off_rest()`
## below is the conjugation itself).
##
## ### WHY THE POSE IS AN EULER TRIPLE, like a node's
##
## `_axis()` / `_set_axis()` read and write ONE component of the skeleton-space
## rotation off rest, leaving the others alone — exactly what `node.rotation.x =`
## does to a `Node3D`. Godot composes both in `EULER_ORDER_YXZ`, so the limb
## driver's writes and these are the same arithmetic on the same triple, and
## `measure()` can hand both to the same bounds.
##
## ### WHAT THIS DOES NOT WRITE, AND WHY `measure()` STILL MEANS ONE THING
##
## THE LEAN. The body's lean and sway stay on the `Body` NODE above the mesh,
## written by the caller for BOTH rig kinds — one lean, not two (the spike's
## column put it on the spine; doing both would double it, and bead `5u3.9`'s
## spec says so in as many words). That also keeps the landing squash,
## `capture_rest_pose()`'s `body` key and Teibi's resize working with zero lines
## changed. `spine_02` IS written now, but only as the pelvis's counter-rotation:
## it takes a turn BACK, never one forward.
##
## ### WHAT THE SKELETONS COST — MEASURED IN A BROWSER (bd godot-test1-5u3.11)
##
## Epic `5u3` closed on a four-in-a-room reading (bead `5u3.8`, PR #374) that
## charged three skinned heroes **+3.3 ms** of frame time. That reading was a
## WINDOWED DESKTOP `gl_compatibility` stand-in; bead `5u3.11` went and took it in
## the browser the stand-in stands in for, and **IT DOES NOT REPRODUCE.**
##
## The probe is 5u3.8's own scene: the local player plus three `RemoteAvatar`s
## through the shipped `receive_state()` (rig kinds ASSERTED — three skinned, one
## limb), Budapest through the shipped `\fb`, 60 s windows, `\fo`'s counters. Each
## control column below is the SAME RUN, continued with every
## `set_bone_pose_rotation()` suppressed: identical meshes, identical GDScript,
## the skeletons simply never
## go dirty, so the difference is the engine re-skinning them and nothing else.
##
##                    shipped           bones never written
##   DEBUG WEB EXPORT, Chrome/WebGL2, Apple M4 — the target, and the gate
##     frame ms        16.67 / 16.79    16.67 / 16.67
##     fps             60.0  / 59.6     60.0  / 60.0
##     process ms       6.61            5.82  / 5.85
##   DESKTOP STAND-IN, `--rendering-driver opengl3`, windowed 1280x720, same M4
##     frame ms        18.15 / 17.89    15.55 / 15.41
##     fps             55.1  / 55.9     64.3  / 64.9
##
## Three skeletons cost about **0.8 ms of CPU against a 16.7 ms budget** in the
## browser and the build never leaves the vsync ceiling; the frame-ms delta the
## bead was filed on comes out at 0.06 ms. The stand-in charges 2.5 ms for the
## same three bodies — and a separate-run pair on the same machine read 20.13 /
## 20.38 against 16.17 / 16.70, which is 5u3.8's published regression exactly,
## with the control column landing on its pre-epic baseline. So the stand-in was
## measuring macOS's deprecated desktop GL (Godot reports `OpenGL API 4.1 Metal -
## 90.5 - Compatibility`), which is not what the web target runs: Chrome drives
## WebGL2 through ANGLE/Metal and pays a fifth of it. No fix shipped, by
## measurement — the bead's own instruction for a browser reading inside noise.
##
## AND IT WAS NEVER THIS FILE. A third desktop window with the drivers not bound
## at all reads 16.02 ms against that separate run's control of 16.17, so every
## write below — seventeen bones a frame, each through `_set_axis`'s
## read-modify-write — is ~0.15 ms of it. Caching bone lookups harder or writing
## fewer bones
## cannot buy back a cost that is the ENGINE re-skinning a dirty skeleton; the
## only two levers that reach it are update FREQUENCY (the crocodile LOD's sleep,
## for avatars far enough away that a coarse pose is invisible) and VERTEX COUNT
## (a web-gated decimation in `build_hero.py`). At 0.8 ms neither is worth the
## divergence risk it would add to a pose two peers have to agree on.
##
## EVERY BONE `5u3.9` ADDED IS A BONE `measure()` DOES NOT EXPOSE — the calf, the
## foot, the forearm, the clavicle, the pelvis and the two spine bones. That is
## not an accident, it is the design rule that let this bead land: `measure()`'s
## keys are the SHOULDER and the HIP, so `gait_selfcheck`'s equivalence oracle
## (check 8g — the same script of driver calls run against the limb rig and this
## one, compared key by key) still holds exactly as it did, and the skinned hero
## still walks the stride the caller asked for. The new joints are measured in
## the skeleton's own space instead, by `_measure_skinned_joints()`.

## MPFB2's `game_engine` rig, UE-mannequin names. The four that stand in for the
## limb rig's four nodes, plus the joints only a skeleton has.
const THIGH: Dictionary = {"left": "thigh_l", "right": "thigh_r"}
const CALF: Dictionary = {"left": "calf_l", "right": "calf_r"}
const FOOT: Dictionary = {"left": "foot_l", "right": "foot_r"}
const UPPERARM: Dictionary = {"left": "upperarm_l", "right": "upperarm_r"}
const LOWERARM: Dictionary = {"left": "lowerarm_l", "right": "lowerarm_r"}
const CLAVICLE: Dictionary = {"left": "clavicle_l", "right": "clavicle_r"}
const HEAD: String = "head"
const PELVIS: String = "pelvis"
## The bone that takes the pelvis's turn back, and the one that breathes.
const SPINE: String = "spine_02"
const CHEST: String = "spine_03"

## Bones this driver USES but does not REQUIRE. A rig without them is not broken,
## it simply draws less — the rule the optional `Head` node has always had, as
## one list instead of eight `if`s (`_set_axis` on an unbound bone is a no-op and
## `_axis` reads zero). The four locomotion pairs are NOT in here: a rig missing
## a thigh cannot walk, and `bind()` refuses it rather than posing half a hero.
const OPTIONAL: Array[String] = [HEAD, PELVIS, SPINE, CHEST,
		"clavicle_l", "clavicle_r", "foot_l", "foot_r"]

## EVERY TUNABLE IN ONE TABLE, with its units (bd godot-test1-5u3.9's own rule,
## and the `GAITS` idiom one level down). Nothing here is per hero: the gait row
## already scales the two swings this driver is handed, and every amplitude below
## is expressed as a RATIO of that swing or of the `*_reference_deg` the DEFAULT
## row was authored at — so a heavy Teibi bends his knee further than a quick
## Primm without either of them appearing here.
const GAIT_SKIN: Dictionary = {
	# --- LEGS ---------------------------------------------------------------
	# Knee flex at the peak of the swing, in radians of knee per radian per
	# radian-of-phase of thigh RATE. At Teibi's 44-degree leg swing that is
	# 1.15 * 0.768 = 0.88 rad = 51 degrees, against a real walk's ~60.
	"knee_swing_ratio": 1.15,
	# How deep the knees take a landing, degrees of flex at the peak of the
	# squash arc (`PlayerAnimation.land_squash_amount()`).
	"knee_land_deg": 24.0,
	# The airborne tuck's knee, degrees of flex.
	"air_knee_deg": 38.0,
	# How much of (thigh + knee) the ankle gives back so the sole stays level.
	# 1.0 is a sole parallel to the ground at every phase; 0.0 is the ankle
	# riding the leg, which is what this driver did before `5u3.9`.
	"ankle_level_ratio": 1.0,
	# ...and the ANKLE'S OWN RANGE, degrees either way. A real ankle has about
	# 20 degrees of dorsiflexion and 50 of plantarflexion, and levelling a
	# 57-degree thigh over a 66-degree knee would ask it for 86 — so the clamp is
	# what keeps a mid-swing foot a foot instead of a flipper. It never binds at a
	# CONTACT frame, which is the frame that has to be level: there the knee is
	# straight and only the thigh has to be given back.
	"ankle_limit_deg": 40.0,
	# --- PELVIS / SPINE -----------------------------------------------------
	# Hip drop at a full stride, degrees of pelvis ROLL (skeleton Z).
	"pelvis_drop_deg": 3.0,
	# Transverse pelvis rotation at a full stride, degrees (skeleton Y).
	"pelvis_twist_deg": 4.0,
	# How much of the pelvis's turn `spine_02` takes back. 1.0 = the shoulders
	# stay exactly level; below 1.0 the upper body carries some of the sway.
	"spine_counter": 1.0,
	# What "a full stride" means: the DEFAULT `GAITS` row's `leg_deg` / `arm_deg`.
	# Every ratio above and below is a fraction of these, so the pelvis and the
	# shoulders open with the hero's own row and close to nothing when standing.
	"stride_reference_deg": 40.0,
	"arm_reference_deg": 30.0,
	# --- ARMS ---------------------------------------------------------------
	# The elbow's NEUTRAL — the rest this driver poses around on every path
	# (`locomotion`, `idle`, `air`, `rest_pose`), degrees of flex.
	"elbow_bend_deg": 15.0,
	# How much of the shoulder's own swing the forearm tracks, on top of it.
	"elbow_track_ratio": 0.3,
	# ...and the QUARTER-CYCLE LAG on top of that: degrees of extra flex peaking
	# where the arm passes centre on its way BACK, a quarter cycle after the
	# forward extreme. A forearm that is exactly in phase with its upper arm is
	# a stick; a forearm that lags it is an arm.
	#
	# THE SIGN IS THE ONE THING HERE THE OWNER RULES FROM THE STRIPS. The bead's
	# text asks for the peak on the BACK swing; anatomy (and `gait_selfcheck`
	# check 8h, which has asserted the forward-flex direction since `5u3.2`) puts
	# it just after the FORWARD one, which is what this lag draws. Negating this
	# number moves the peak to the back swing and nothing else changes.
	"elbow_lag_deg": 22.0,
	# The shoulder FOLLOWING ITS OWN ARM at a full swing, degrees of clavicle
	# protraction — a rotation about the skeleton's Y, so the shoulder travels
	# forward and back with the arm and the shoulder LINE stays level. (On Z it
	# would tilt the pair, which is precisely the thing `spine_02`'s
	# counter-rotation three fields up exists to prevent.)
	"shoulder_swing_deg": 5.0,
	# The forearms raised at the top of the wing beat, degrees of flex.
	"air_elbow_deg": 58.0,
	# --- IDLE ---------------------------------------------------------------
	# The breath, on the chest: rate in Hz and amplitude in degrees of pitch.
	# 1.1 degrees at spine_03 is about 8 mm at the shoulders — the "few mm" the
	# bead asks for, and deliberately under the eye's "is that a nod" threshold.
	"breath_hz": 0.25,
	"breath_deg": 1.1,
	# The standing weight shift, on the pelvis: Hz and degrees of roll. It fades
	# out as the stride opens (a walker does not also sway on the spot).
	"shift_hz": 0.13,
	"shift_deg": 2.2,
}

## Euler component indices, so the writes below read as axes rather than as 0/1/2.
const AXIS_X: int = 0
const AXIS_Y: int = 1
const AXIS_Z: int = 2

var _skel: Skeleton3D = null
var _body: Node3D = null
var _rest: Dictionary = {}

## Per-bone, resolved ONCE at bind because none of it can change afterwards:
## the bone index, the parent's global rest basis (and its inverse) that every
## write conjugates through, and the bone's own rest basis (and its inverse).
## A walk frame touches seventeen bones, so this is the difference between four
## `find_bone()` string lookups per bone per frame and none.
var _bones: Dictionary = {}

## THE CALLER'S CLOCK, HANDED OVER — not state (bd godot-test1-5u3.9).
##
## These four are overwritten by `set_clock()` every frame BEFORE the pose call
## that reads them, and nothing here ever accumulates into them or reads one it
## did not just receive. They are the caller's numbers parked for the length of
## one frame, which is why the pose stays a pure function of (hero,
## animation_time, gait state) and why `gait_selfcheck`'s determinism probe —
## two drivers on two instances at one clock — comes out bit-identical.
## `rest_pose()` clears them, so a driver nobody is clocking poses the still
## hero it always did.
var _clock: float = 0.0
var _land: float = 0.0
var _arm_rate: float = 0.0
var _leg_rate: float = 0.0


func kind() -> String:
	return "skinned"


func bind(body: Node3D, rest: Dictionary) -> bool:
	"""
	Find the `Skeleton3D` under `body` — BY TYPE, never by path — and cache the
	bases every write needs.

	@param rest: the limb rig's rest table. Its LIMB keys are ignored — a skeleton
	             carries its own rest pose (`get_bone_rest()`), which is what the
	             exporter baked and what `reset_bone_poses()` returns to. The
	             `body` key is read, by `measure()`, for the two columns the
	             caller writes on the `Body` NODE for either rig kind.
	@return false when the skeleton is missing the locomotion bones, so an
	        unexpected rig stands frozen instead of half-posed. A rig missing one
	        of the `OPTIONAL` bones binds fine and simply draws less.
	"""
	_body = body
	_rest = rest
	var found: Array[Node] = body.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return false
	_skel = found[0] as Skeleton3D
	var wanted: Array[String] = [HEAD, PELVIS, SPINE, CHEST]
	for side: String in ["left", "right"]:
		wanted.append_array([THIGH[side], CALF[side], FOOT[side],
				UPPERARM[side], LOWERARM[side], CLAVICLE[side]])
	var missing: Array[String] = []
	for bone: String in wanted:
		var idx: int = _skel.find_bone(bone)
		if idx < 0:
			if bone not in OPTIONAL:
				missing.append(bone)
			continue
		var parent: int = _skel.get_bone_parent(idx)
		var p: Basis = Basis.IDENTITY
		if parent >= 0:
			p = Basis(_skel.get_bone_global_rest(parent).basis.get_rotation_quaternion())
		var r: Basis = Basis(_skel.get_bone_rest(idx).basis.get_rotation_quaternion())
		_bones[bone] = {"idx": idx, "p": p, "p_inv": p.inverse(), "r": r, "r_inv": r.inverse()}
	if not missing.is_empty():
		push_warning("HeroRigSkeleton: rig is missing %s — the model will not animate"
				% ", ".join(missing))
		return false
	return true


func has_head() -> bool:
	return _bones.has(HEAD)


func set_clock(seconds: float, land: float,
		arm_rate: float = 0.0, leg_rate: float = 0.0) -> void:
	"""
	THE SEAM BEAD `5u3.9` ADDED, and the only one it added: the caller hands over
	the three things a natural gait needs that a swing ANGLE cannot carry.

	It is reached through `has_method("set_clock")` — CLAUDE.md's discovery rule —
	which is exactly what keeps `hero_rig_limbs.gd` the byte-identical file it has
	to stay: the limb rig does not answer this, so nobody calls it on the limb rig
	and its `locomotion()` signature never grows an argument.

	@param seconds:  the caller's animation clock. Drives the breath and the
	                 standing weight shift, and nothing else — both are slow
	                 enough (0.25 / 0.13 Hz) that a stride phase could not carry
	                 them and a stopped stride must not stop them.
	@param land:     the landing squash's own arc, 0..1
	                 (`PlayerAnimation.land_squash_amount()`). The caller keeps
	                 writing the `Body` dip and the container squash; this is the
	                 share the KNEES take.
	@param arm_rate: THE QUADRATURE of the arm swing the next `locomotion()` call
	@param leg_rate: carries — `d(swing)/dφ`, scaled by the same amplitude and
	                 hitch, i.e. `cos(φ)` where the swing is `A·sin(φ)`.

	WHY A QUADRATURE AND NOT A PHASE. A joint that is merely rectified off the
	swing (`max(0, -thigh)`, which is what this driver did before) cannot tell
	the forward half of the cycle from the backward one, because `sin(φ)` takes
	every value twice. A knee that peaks mid-SWING and is straight at heel strike
	AND at push-off needs to know which way the thigh is travelling, and that is
	the cosine. Handing the RATE rather than the raw phase means the driver never
	repeats the caller's amplitude arithmetic (the hitch, the remote's speed
	fade), so the two ends cannot drift apart in it — and a standing peer, whose
	rates are zero, gets a straight leg for free.
	"""
	_clock = seconds
	_land = land
	_arm_rate = arm_rate
	_leg_rate = leg_rate


func rest_pose() -> void:
	"""Back to the exported rest — every bone, and since bead `5u3.3` collapsed
	the fingers into `hand_l`/`hand_r` that is 23 of them — and then the
	elbow back to its neutral bend, because `elbow_bend_deg` is the rest this
	driver poses around on every other path (`locomotion`, `air`, `idle`). Left
	at the exported straight arm, a character swap would show one frame of
	straightened elbows before the first pose call bends them again.

	It also drops the caller's clock, so a driver that is posed WITHOUT being
	clocked (the tower's jailed-hero slump, `gait_selfcheck`'s driver script)
	draws the same still hero it drew before bead `5u3.9`."""
	_skel.reset_bone_poses()
	_clock = 0.0
	_land = 0.0
	_arm_rate = 0.0
	_leg_rate = 0.0
	for side: String in ["left", "right"]:
		_set_axis(LOWERARM[side], AXIS_X, _deg("elbow_bend_deg"))


func locomotion(arm_swing: float, leg_swing: float, arm_asym: float) -> void:
	"""
	One frame of the walk/run cycle, on bones. The four swings are the limb
	rig's four, sign for sign — a positive rotation about the skeleton's +X
	takes a limb hanging down toward -Z, which is the way every hero in this
	game faces, so positive is forward on both rigs. The THIGH and the SHOULDER
	are written exactly as the limb rig writes its four nodes, and that is the
	contract: everything bead `5u3.9` added hangs off bones `measure()` does not
	expose, so a skinned hero still walks the stride the gait row asked for.

	THE JOINTS ARE PHASED, not rectified (see `set_clock()`): the knee bends
	through the SWING half and is straight at heel strike and at push-off, the
	ankle gives the whole chain back so the sole stays level, the elbow lags its
	shoulder by a quarter cycle and the clavicle rolls with it. None of it needs
	a clock the caller is not already keeping.
	"""
	var knee_land: float = -_deg("knee_land_deg") * _land
	for side: String in ["left", "right"]:
		var mirror: float = -1.0 if side == "left" else 1.0

		# --- THE LEG.
		var leg: float = mirror * leg_swing
		_set_axis(THIGH[side], AXIS_X, leg)
		# The knee flexes (negative X) while this thigh is travelling FORWARD —
		# `max(0, rate)` is the swing half of the cycle and it is zero at both
		# extremes, which is what puts a straight leg under the body at heel
		# strike and at toe-off. A landing is the deeper of the two, never the
		# sum: adding them would let an eased residue pile up over a squash.
		var knee: float = minf(
				-float(GAIT_SKIN["knee_swing_ratio"]) * maxf(0.0, mirror * _leg_rate),
				knee_land)
		_set_axis(CALF[side], AXIS_X, knee)
		# ...and the ankle takes the whole chain back, so the sole is parallel to
		# the ground whatever the hip and the knee are doing.
		_set_axis(FOOT[side], AXIS_X, _ankle(leg, knee))

		# --- THE ARM.
		var asym: float = arm_asym if side == "left" else 1.0
		var arm: float = -mirror * arm_swing * asym
		var arm_rate: float = -mirror * _arm_rate * asym
		_set_axis(UPPERARM[side], AXIS_X, arm)
		_set_axis(LOWERARM[side], AXIS_X, _deg("elbow_bend_deg")
				+ float(GAIT_SKIN["elbow_track_ratio"]) * arm
				+ _deg("elbow_lag_deg") * maxf(0.0, -_unit(arm_rate, "arm_reference_deg")))
		# THE SAME TURN ON BOTH CLAVICLES, and that is not a typo. A rotation about
		# the skeleton's +Y carries a point at +X toward -Z and a point at -X
		# toward +Z, and the two clavicles extend in opposite X directions — so
		# ONE shared angle is what sends one shoulder forward while the other goes
		# back, which is the girdle counter-rotating against the pelvis. Feeding
		# it the per-side `arm` (which already alternates sign) would cancel that
		# and swing the whole chest as one slab. It rides the raw `arm_swing`
		# rather than either arm, `arm_asym` and all: a girdle is one bone pair,
		# not two independent shoulders.
		_set_axis(CLAVICLE[side], AXIS_Y,
				_deg("shoulder_swing_deg") * _unit(arm_swing, "arm_reference_deg"))

	_torso(leg_swing)


func head_bobble(angle: float) -> void:
	if has_head():
		_set_axis(HEAD, AXIS_Z, angle)


func relax_head(weight: float) -> void:
	if has_head():
		_set_axis(HEAD, AXIS_Z, lerp(_axis(HEAD, AXIS_Z), 0.0, weight))


func idle(weight: float) -> void:
	"""Ease the swing out of every joint the walk cycle drives — and then stand
	there ALIVE, which is the half of "natural movements" a stride strip cannot
	show: the chest breathes and the weight shifts from hip to hip, both off the
	caller's clock (`set_clock`), so there is no RNG and no timer.

	THE ELBOW'S NEUTRAL IS `elbow_bend_deg`, NOT ZERO, and it is the same on
	every path: `locomotion()` writes the bend plus the shoulder's track and lag,
	`air()` eases to the raised forearm and back, and standing still has to ease
	to the same number or the arms straighten over half a second and then snap
	back 15 degrees on the first walking frame. It is also what keeps a standing
	LOCAL hero and a standing REMOTE one identical — the mirror has no idle
	branch at all, it calls `locomotion()` with both swings at zero."""
	var knee_land: float = -_deg("knee_land_deg") * _land
	for side: String in ["left", "right"]:
		for bone: String in [THIGH[side], UPPERARM[side], CLAVICLE[side]]:
			var axis: int = AXIS_Y if bone == CLAVICLE[side] else AXIS_X
			_set_axis(bone, axis, lerp(_axis(bone, axis), 0.0, weight))
		# The stride's own flex eases out; a landing is written straight in, or a
		# 0.18 s squash would be over before a per-frame lerp had reached it.
		var knee: float = minf(lerp(_axis(CALF[side], AXIS_X), 0.0, weight), knee_land)
		_set_axis(CALF[side], AXIS_X, knee)
		_set_axis(FOOT[side], AXIS_X, _ankle(_axis(THIGH[side], AXIS_X), knee))
		_set_axis(LOWERARM[side], AXIS_X,
				lerp(_axis(LOWERARM[side], AXIS_X), _deg("elbow_bend_deg"), weight))
	_torso(0.0)


func slump(arm_x: float, leg_x: float) -> void:
	"""The authored slump on bones — the limb driver's two numbers written onto
	the shoulders and the hips, through the same conjugation every write in this
	file uses. NO PER-BONE AXIS TABLE: see the roll trap in the banner.

	The knee and the elbow keep whatever `rest_pose()` left them, which is the
	straight knee and the neutral `elbow_bend_deg` every other path holds them
	at. A captive is scenery, not a frame of a cycle."""
	for side: String in ["left", "right"]:
		_set_axis(UPPERARM[side], AXIS_X, arm_x)
		_set_axis(THIGH[side], AXIS_X, leg_x)


func air(spread: float, tuck: float, weight: float) -> void:
	"""Arms rolled out to the sides (the beat is already inside `spread`) with
	the forearms UP, the forward/back swing cleared so the wings sit level, and
	the legs tucked forward at the hip AND folded at the knee — a body that has
	left the ground pulls itself in, and a knee left frozen mid-flex is the
	skinned rig's own version of the leftover roll `drop_wings()` clears.

	Everything here EASES at `weight`, which is what makes going airborne out of
	a stride a transition rather than a snap. The remote mirror passes 1.0,
	having no clock of its own to ease against."""
	var knee: float = -_deg("air_knee_deg")
	for side: String in ["left", "right"]:
		var mirror: float = -1.0 if side == "left" else 1.0
		_set_axis(UPPERARM[side], AXIS_Z, mirror * spread)
		_set_axis(UPPERARM[side], AXIS_X, 0.0)
		_set_axis(CLAVICLE[side], AXIS_Y, lerp(_axis(CLAVICLE[side], AXIS_Y), 0.0, weight))
		_set_axis(LOWERARM[side], AXIS_X,
				lerp(_axis(LOWERARM[side], AXIS_X), _deg("air_elbow_deg"), weight))
		_set_axis(THIGH[side], AXIS_X, lerp(_axis(THIGH[side], AXIS_X), tuck, weight))
		_set_axis(CALF[side], AXIS_X, lerp(_axis(CALF[side], AXIS_X), knee, weight))
		_set_axis(FOOT[side], AXIS_X, lerp(_axis(FOOT[side], AXIS_X), 0.0, weight))
	_settle_torso(weight)


func drop_wings() -> void:
	for side: String in ["left", "right"]:
		_set_axis(UPPERARM[side], AXIS_Z, 0.0)


func sidestep(splay: float, reach: float, lift_left: bool, lift: float,
		arm_bias: float, arm_swing: float) -> void:
	"""The sideways shuffle, rolled on the skeleton's Z — the limb driver's
	expression, bone for bone.

	A strafe owns the Z axes and writes no joint at all, so the knees, ankles and
	pelvis it inherits from the stride it interrupted have to be put back here or
	they freeze there for as long as the step is held (`reset_sidestep_pose()` is
	the same argument one level up, for the limb roll)."""
	_set_axis(THIGH["left"], AXIS_Z, splay + reach + (lift if lift_left else 0.0))
	_set_axis(THIGH["right"], AXIS_Z, splay - reach + (0.0 if lift_left else lift))
	_set_axis(UPPERARM["left"], AXIS_Z, -arm_bias - arm_swing)
	_set_axis(UPPERARM["right"], AXIS_Z, -arm_bias + arm_swing)
	for side: String in ["left", "right"]:
		_set_axis(CALF[side], AXIS_X, 0.0)
		_set_axis(FOOT[side], AXIS_X, 0.0)
		_set_axis(CLAVICLE[side], AXIS_Y, 0.0)
	_settle_torso(1.0)


func reset_roll() -> void:
	for side: String in ["left", "right"]:
		_set_axis(UPPERARM[side], AXIS_Z, 0.0)
		_set_axis(THIGH[side], AXIS_Z, 0.0)


func measure() -> Dictionary:
	"""
	The same dictionary the limb driver answers, read back OFF THE SKELETON —
	never off a cached copy of what was written, or a deleted write would still
	measure. See `hero_rig_limbs.measure()` for the contract; the four limb keys
	are the shoulder and hip bones, which are what the limb rig's four nodes are.

	IT DELIBERATELY DOES NOT GROW with bead `5u3.9`'s seven new bones. Its job is
	to mean the SAME THING on either rig kind — that is what lets one set of
	bounds hold both, and what lets check 8g compare the two drivers pose for
	pose. The new joints are measured where they actually are, in skeleton space,
	by `gait_selfcheck._measure_skinned_joints()`.
	"""
	var body_rest: Vector3 = _rest.get("body", Vector3.ZERO)
	var out: Dictionary = {
		"left_arm_x": _axis(UPPERARM["left"], AXIS_X),
		"right_arm_x": _axis(UPPERARM["right"], AXIS_X),
		"left_leg_x": _axis(THIGH["left"], AXIS_X),
		"right_leg_x": _axis(THIGH["right"], AXIS_X),
		"left_arm_z": _axis(UPPERARM["left"], AXIS_Z),
		"right_arm_z": _axis(UPPERARM["right"], AXIS_Z),
		"left_leg_z": _axis(THIGH["left"], AXIS_Z),
		"right_leg_z": _axis(THIGH["right"], AXIS_Z),
		"body_y": _body.position.y,
		"body_x": _body.rotation.x - body_rest.x,
		"body_z": _body.rotation.z - body_rest.z,
	}
	if has_head():
		out["head_z"] = _axis(HEAD, AXIS_Z)
	return out


# ============================================================================
# THE TORSO — the pelvis, its counter-rotation, and the breath
# ============================================================================

func _torso(leg_swing: float) -> void:
	"""
	The pelvis drops and twists with the stride and `spine_02` takes the same
	turn straight back, so everything above it — the chest, the clavicles, the
	arms, the head — stays level. That pair is what separates a walk from a
	marionette hung off two hip joints, and it is why the pelvis may be written
	at all: rotate it alone and the shoulders roll with it.

	It also carries the two IDLE terms, because the remote mirror has no idle
	branch — it calls `locomotion()` with both swings at zero — so a standing
	peer has to breathe from the same place a standing local hero does. The
	weight shift fades out as the stride opens (`still`): a walker does not also
	sway on the spot.

	@param leg_swing: the caller's raw leg swing — the thigh's amplitude before
	                  the left/right mirror, so ONE pelvis turn per stride.
	"""
	var unit: float = _unit(leg_swing, "stride_reference_deg")
	var still: float = 1.0 - minf(1.0, absf(unit))
	var drop: float = _deg("pelvis_drop_deg") * unit \
			+ _deg("shift_deg") * still * sin(_clock * TAU * float(GAIT_SKIN["shift_hz"]))
	var twist: float = _deg("pelvis_twist_deg") * unit
	var counter: float = float(GAIT_SKIN["spine_counter"])
	# STATED AS WHOLE TRIPLES, not written one axis at a time — see `_set_euler`.
	# These three bones are owned end to end by this function and `_settle_torso`,
	# so there is nothing here to preserve and a read-modify-write would only feed
	# float drift back into itself.
	_set_euler(PELVIS, Vector3(0.0, twist, drop))
	_set_euler(SPINE, Vector3(0.0, -twist * counter, -drop * counter))
	# THE BREATH, on the chest ABOVE the counter-rotation, so it is a chest
	# rising and not a whole body rocking.
	_set_euler(CHEST, Vector3(
			_deg("breath_deg") * sin(_clock * TAU * float(GAIT_SKIN["breath_hz"])),
			0.0, 0.0))


func _settle_torso(weight: float) -> void:
	"""Ease the pelvis, its counter-rotation and the breath back to rest — for
	the two poses that own the body themselves (`air`, `sidestep`) and would
	otherwise wear whatever tilt the stride they interrupted left behind."""
	for bone: String in [PELVIS, SPINE, CHEST]:
		_set_euler(bone, _off_rest_euler(bone).lerp(Vector3.ZERO, weight))


func _ankle(leg: float, knee: float) -> float:
	"""The ankle gives the whole (thigh + knee) chain back, so the sole is
	parallel to the ground whatever the hip and the knee are doing — within an
	ankle's own range, which is what `ankle_limit_deg` is for."""
	var limit: float = _deg("ankle_limit_deg")
	return clampf(-(leg + knee) * float(GAIT_SKIN["ankle_level_ratio"]), -limit, limit)


func _deg(key: String) -> float:
	"""One `GAIT_SKIN` degree entry, in radians. Every amplitude in the table is
	authored in degrees because that is the unit a person judging a strip thinks
	in; every write below wants radians."""
	return deg_to_rad(float(GAIT_SKIN[key]))


func _unit(swing: float, reference: String) -> float:
	"""A swing (or a swing RATE) as a fraction of the DEFAULT gait row's own
	amplitude, clamped. This is how the pelvis and the shoulders scale with the
	hero without this file ever reading a `GAITS` row: Teibi's 44-degree legs
	give 1.1, Phoboman's 24 give 0.6, and a standing hero gives 0."""
	return clampf(swing / deg_to_rad(float(GAIT_SKIN[reference])), -1.5, 1.5)


# ============================================================================
# THE ONE PLACE A BONE IS READ OR WRITTEN — see the roll trap in the banner
# ============================================================================

func _off_rest_euler(bone: String) -> Vector3:
	return Vector3.ZERO if not _bones.has(bone) else _off_rest(bone).get_euler()


func _off_rest(bone: String) -> Basis:
	"""This bone's current rotation off its rest, in SKELETON axes: undo the
	rest, then conjugate the bone-local turn out through the parent's basis."""
	var b: Dictionary = _bones[bone]
	var local: Basis = Basis(_skel.get_bone_pose_rotation(b["idx"])) * (b["r_inv"] as Basis)
	return (b["p"] as Basis) * local * (b["p_inv"] as Basis)


func _axis(bone: String, axis: int) -> float:
	if not _bones.has(bone):
		return 0.0
	return _off_rest(bone).get_euler()[axis]


func _set_axis(bone: String, axis: int, value: float) -> void:
	"""Write ONE skeleton-space euler component of this bone's rotation off
	rest, leaving the other two — exactly what `node.rotation.x = v` does.

	A bone this rig does not have is not written and is not an error: that is the
	`OPTIONAL` list's whole contract, and it is what lets a hero exported without
	a clavicle or a foot bone still walk."""
	if not _bones.has(bone):
		return
	var e: Vector3 = _off_rest(bone).get_euler()
	e[axis] = value
	_set_euler(bone, e)


func _set_euler(bone: String, e: Vector3) -> void:
	"""Write ALL THREE skeleton-space euler components at once, stating the pose
	instead of amending it.

	WHY IT EXISTS, when `_set_axis` is the file's idiom: `_set_axis` is a
	READ-modify-write — that is the whole point of it, it is `node.rotation.x = v`
	— so the two components it does not write are round-tripped through
	`get_euler` / `from_euler` and a basis conjugation on every single frame. In
	float32 that walks: MEASURED on bead `5u3.9`, `spine_03` came out 0.001 rad
	apart on two instances of the same hero at the same clock after one of them
	had walked 430 frames and the other none. That is invisible on screen and NOT
	invisible to `gait_selfcheck`'s determinism probe, nor to two peers comparing
	the hero they each draw. Wherever this driver owns a bone's whole triple, it
	says so — which is exact, and cheaper than three read-modify-writes."""
	if not _bones.has(bone):
		return
	var b: Dictionary = _bones[bone]
	var local: Basis = (b["p_inv"] as Basis) * Basis.from_euler(e) * (b["p"] as Basis)
	_skel.set_bone_pose_rotation(b["idx"],
			(local * (b["r"] as Basis)).get_rotation_quaternion())
