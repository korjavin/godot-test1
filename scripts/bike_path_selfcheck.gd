extends SceneTree
## Headless self-check for THE BICYCLE PATHS — the seeded station polyline, the
## flat strip, the dashes and the poles (epic `godot-test1-z2yv`, child `.1`).
##
##   godot --headless --path . --script res://scripts/bike_path_selfcheck.gd
##
## ...and epic `godot-test1-pnvb`, child `.2`, adds TIER 1 — the trunk routes that
## run between named anchors — to the same file, because everything below the walk
## is shared. THE TIER-1 SET IS SIX CHECKS IN FIVE CALLS: 2d, 3b, T1, T2, T5 and T4
## are the calls, and T3a and T3b are the two that live inside `_check_scarcity`.
## Six, counting T3a and T3b separately, is the number every statement in this file
## uses. They are listed after check 11.
##
## ...and child `.3` adds THE BRIDGE SET, six statements in four calls: B1 (with
## B1b), B3 and B4 share `_check_trunk_bridges` because they all need the same drawn
## deck, B5 and B6 are unit assertions on the two pieces no seed reliably exercises,
## and B2 (with B2b) is its own sweep. They are listed after T4.
##
## ...and child `.4` (road crossings + aimed spurs) adds FOUR, each its own call
## after the drawn chain: C1 (the world tie off the DRAWN box, the route spanning
## the swath, the zebra override at the flanking poles), C2 (no road coin stands
## on a drawn strip), C3 (the angle rule over the CI seeds, failing on zero
## crossings), C4 (every surviving spur attaches, with the spur:trunk ratio). Check
## 1 additionally re-rolls the four spur draws and asserts the aim replacing
## bearing and length; 3b counts mid-span crossings beside the shallow refusals.
##
## ...and bead `godot-test1-z2yv.3` — the bike-stand rack at every NETWORK ANCHOR
## a trunk touches — adds THREE of its own after C4: R1 (exactly one rack per
## touched anchor across the field, every marker within `RACK_ANCHOR_REACH` of
## its anchor AND inside the building chunk, dedup by construction on
## preliminary sites, untouched anchors and pure spur ends bare; fails on zero
## racks), R2 (the contract the rental epic reads: group exactly `bike_stand`,
## metas `anchor: int` and `pos: Vector3`, tier-separated from the path
## markers), R3 (the world tie: a rack box really in the chunk's batch, through
## the shipped bucketing, standing within a stated literal distance of its
## anchor, with the marker on top of the geometry and the footprint in the
## building chunk), R4 (the rack asks the footprint test with its own 1.4 m
## radius, not the pole's — one synthetic obstacle between the two thresholds,
## refused or moved, never kept). A rack is owned by its site's chunk, never
## its anchor's —
## an 80 m ring puts the HQ rack two chunks east of it. Checks 1 and 5 need no
## change — the racks land inside the family's own batch slice as CUBEs — and
## check 6 counts one footprint per rack beside the one per pole.
##
## `scripts/terrain_bike_paths.gd`'s banner carries the design; this file is the
## part of it a future edit cannot slip past. Six checks, every one of them an
## effect measurement WITH A CONTROL — the house rule in this suite:
##
##   1. THE KILL SWITCH, and it is check 1 because it is the one that must never
##      go red. A field of chunks built through the SHIPPED `create_chunk` with
##      `spawn_bike_paths` off, against the same field with it on and this
##      family's boxes sliced out of the built CUBE MultiMesh by the marker's
##      own `cube_start` / `batch_count`: byte-identical, every other bucket
##      whole, and every crocodile and coin on the same metre. A stray draw from
##      the shared chunk stream slides every body in the chunk, so the node half
##      is what catches a draw hidden behind a helper. Its two controls run the
##      other way: the field must contain a chunk WITH a path (or the slice is
##      never exercised) and a chunk WITHOUT one (or "identical" is trivial).
##   2. PURITY, SEAMLESSNESS, AND WHERE THE GEOMETRY ACTUALLY LANDS. The same
##      chunk built twice is byte-identical, batch and `obstacles` both. Then, for
##      real paths across a real field: (b) the union of the segments drawn by
##      every chunk in reach is EXACTLY the station list — each segment once, none
##      missing — with a mutation control on the comparator in both directions;
##      and (c) every strip box's WORLD position is its segment's midpoint, which
##      is the only assertion in the file that ties a drawn box to the station
##      that produced it. Without (c) a wrong local frame — chunk-local is
##      relative to the chunk NODE, which stands at the chunk CENTRE, not its
##      corner — puts every strip half a chunk off the ground the walk cleared
##      and the other five checks all still pass.
##   3. TRUNCATION, NOT GAPS. Every station in the list is legal, measured against
##      the shipped predicate; a path shorter than `BIKE_PATH_MIN_STATIONS` is a
##      failure. Then a SWEEP over seeds and origins for a path that actually runs
##      into something, and it FAILS IF IT FINDS NONE — a check that can pass by
##      never testing the thing is not a check. The successor station is taken
##      from the shipped recurrence and asked whether it is blocked; that is a
##      NON-VACUITY COUNTER and not an assertion, deliberately, because a path may
##      also simply have run out of its rolled length and then has a perfectly
##      legal successor. "Never resumes past a block" is the prefix loop above it.
##   4. SCARCITY, form 2. Origins in the HQ corridor produce paths; origins
##      beyond `SCARCITY_PLAIN_DISTANCE` produce NONE. The near field is the
##      control — `scarcity_selfcheck` check 2's own shape — and `scarcity_at()`
##      is asserted to really be 0 out there, so the far half cannot pass because
##      the band was mis-chosen.
##   5. ZERO NEW BUCKETS. A chunk carrying a path has exactly the
##      `BlockMultiMesh_*` children it has without one. The "CUBE only" ruling
##      (`batch_selfcheck` check 5's `KIND_CAP_BY_NAME` needs no row changed),
##      made unfailable rather than promised in a comment.
##   6. FOOTPRINTS. Every pole appends exactly one `{climbable: false}` footprint
##      with the post's own radius and top; the strip and the dashes append
##      nothing at all. Non-vacuous: the sweep must find poles.
##
## ...and child `.2` — the four authored signs and the traffic head — adds six:
## 7, 8, 7c, 9, 10 and 11. That is FIVE functions in `_run()`, because 7 and 8 share
## one sweep; the count is the only cross-check on the list below, so keep both
## halves of it true.
##
##   7 + 8. WHAT STANDS ON THE POLES, in one sweep because they share it. Every
##      pole carries EXACTLY ONE top; every top is a legal kind; all four sign
##      kinds AND the signal head turn up across the seeds, because a kind that
##      can never be drawn is a dead branch and a broken dispatch looks exactly
##      like one. And every box this family emits is still a `BoxKind.CUBE` with
##      the signs and the heads present, which is `batch_selfcheck` check 5's
##      `KIND_CAP_BY_NAME` table needing no row changed, asserted where the boxes
##      are rather than promised in a comment.
##   7c. AND WHERE THAT TOP ACTUALLY STANDS. Every box a pole carries within the
##      post's own height must be IN FRONT of the post, measured off the emitted
##      transforms. Round 1 of the review found the sign plate built at the post's
##      own centre, inside a 0.16 m box — a grey bar down the middle of every sign
##      and CROSSING's centre pip swallowed whole — and NOTHING above could see it:
##      7 and 8 count, 9 indexes, 1 and 5 compare a build to a build. It is `.1`'s
##      25 m bug in miniature, and this is the assertion shaped like the one that
##      caught that. Its control is the predicate run on the post itself.
##   9. THE INDEX, AND IT IS THE REASON THIS BEAD WAS NOT MECHANICAL. A lamp's
##      MultiMesh instance index is its position among the CUBE ENTRIES ONLY —
##      `_build_block_multimesh` buckets by kind — so the index the marker records
##      is not its index in `block_batch` and an index one out still writes a
##      perfectly valid box. MULTIMESH INSTANCE DATA IS WRITE-ONLY UNDER THE
##      HEADLESS DUMMY RENDERER (measured — see that check), so "read the colour
##      back" is not available and would have read black at every index and passed
##      with any base. Instead the recorded index is compared against what the
##      SHIPPED `_build_block_multimesh` does with the very batch the spawner
##      wrote, on a fixture that holds non-CUBE boxes too; its control is that a
##      lens's batch index and its bucket index must be DIFFERENT NUMBERS, or the
##      check could not tell the two apart. Then the head's own Timer is fired
##      through its `timeout` signal on a real chunk, which steps the phase only if
##      the connection, the Timer -> bucket walk and the index range all hold — and
##      its control is a deliberately out-of-range index, which must not step.
##  10. THE CYCLE IS NOT ON THE SEED. Two terrains on the same seed build the head
##      geometry byte-identically (so nothing drawn depends on the `randomize()`d
##      clock), and the plant/tick/write functions are read AS TEXT: the plant
##      randomizes and never touches `run_seed`, the geometry never randomizes, and
##      the write linearises. `scarcity_selfcheck` check 3's shape, and the only
##      form of those three assertions a future edit cannot slip past.
##  11. AN UNLOADED CHUNK LEAVES NO TIMER BEHIND. The cycle Timer hangs off this
##      family's marker rather than off the chunk (a deliberate departure from the
##      bead — it keeps the Timer out of the child list check 1 compares), which is
##      only safe if it is still freed with the chunk. Measured through the shipped
##      `remove_chunk()`, which is `queue_free`, so this is the one check in the
##      file that awaits a frame. Its control is a second chunk left loaded, whose
##      Timer must still be alive at the end.
##
## ...and epic `godot-test1-pnvb` child `.2` — THE TRUNK ROUTES — grows three of the
## checks above (2, 3 and 4) and adds six of its own. A trunk is a polyline between
## two anchors of `bike_network.gd`'s graph; it is found by a BOUNDING BOX rather than by `scan_radius_chunks()`, its
## route is EXEMPT from scarcity and its FURNITURE is not.
##
##   2d. THE BOUNDING-BOX LOOKUP AGREES WITH THE MIDPOINT RULE. Check 2b's cover
##      assertion, re-made for the other way a chunk finds a polyline. A box that
##      is too tight loses the segments at the ends, which is the chunk-seam bug in
##      a new place. Its comparator is `_cover_fault_set`, which is new here and
##      carries its own three-way control at the bottom of the check.
##   3b. A TRUNK NEVER ENDS IN OPEN FIELD — the exact defect the owner reported. It
##      ends at its own anchor or at Budapest's rect edge, or it does not exist at
##      all; and the reasons the others were abandoned are PRINTED, split by cause,
##      because how many the coin road costs is `godot-test1-pnvb.4`'s whole case.
##      It also pins `TRUNK_APPROACH_RADIUS` to the tower disc it was derived from.
##   T1. THE WORLD TIE, and it is this bead's named non-negotiable assertion. A
##      drawn strip box's WORLD centre is its segment's midpoint to under a
##      centimetre, its length is the segment's length, its axis runs along it, and
##      the chunk's marker for that edge claims that segment. Every other trunk
##      check here compares a build to a build or a list to itself, all of which a
##      uniformly wrong frame satisfies — the strips-25-m-off bug in a new tier.
##   T2. THE INTERSECTION IS EXACT. Two trunks sharing an anchor end on the same
##      `Vector2` to the bit, because the arrival is an ASSIGNMENT. Found loosely
##      (inside one arrival radius) and asserted with `==`, which is the gap a
##      "stop when close enough" would fall into.
##   T3a + T3b. THE SCARCITY SPLIT. T3a drives BOTH code paths at a synthetic
##      k = 0 site and at a k = 1 control — the strip IS drawn, the pole is NOT —
##      because with corridor-only endpoints there may be no real trunk past 3 km
##      on any seed and a check that hunted for one would pass by finding nothing.
##      T3b sweeps for a real sub-k = 1 trunk and PRINTS the count, including zero,
##      as a FINDING and never as a verdict. AN EXEMPTION DELETED BECAUSE IT LOOKED
##      UNUSED IS THE BUG.
##   T5. A TRUNK WALKS TO ITS ANCHOR AND PAINTS NONE OF THE LAST STRETCH. The HQ
##      anchor IS the tower's centre, so the route walks its last 65 m through the
##      disc that protects the building's authored approach — and nothing this
##      family draws may stand in there. Measured on the first build of this bead:
##      `tower_site_selfcheck` failed with a marker 35.4 m from the tower and three
##      collision shapes at 19.9, 40.1 and 59.8 m. Asserted for ALL FOUR keep-outs
##      (the tower's disc, the teleport circles, the landmark chunks and the COIN
##      ROAD'S SWATH), not only the one that failed — and the road half is not a
##      footnote: it is the sole owner of "no paint under a coin" since check 3b's
##      station assertion moved out, and it is what lets the trunk reach the gate,
##      which sits dead centre in the swath. NON-VACUOUS: it fails unless it finds a
##      trunk whose stations really do enter one.
##   T4. THE MEMO. Its station count is printed and capped, it regenerates
##      identically after `_drop_seeded_memos()`, and it CHANGES after
##      `set_run_seed()` — the half that fails if the drop list ever loses it.
##   B1. THE DECK, TIED TO THE RIVER SPAN THAT PRODUCED IT — this child's named
##      world tie. A box really in the chunk's batch, at a slab midpoint of the
##      row, over a point where `is_river_at` is TRUE, at this family's own width,
##      with a walking surface `field_bridge_surface_y` agrees about, and a MARKER
##      beside it so check 1 can still slice the family out of the CUBE bucket. It
##      fails loudly if the seed grew no deck at all.
##   B2. NO PAINT ON OPEN WATER, swept over every truncation seed and tier-blind
##      like T5. It prints how many river crossings the trunks make and how many
##      carry a deck, and fails on zero of either — a sweep with no crossing in it
##      asserts nothing, and a sweep where every crossing is refused is what this
##      child looks like when it is dead.
##   B3. THE WADE SUPPRESSION. A body ON a deck is neither wading nor pushed by
##      the deep channel, while the water under it is real — the control without
##      which B3 would pass on dry ground. The mechanism is the WADE_SURFACE_MAX
##      height gate, asserted directly against FIELD_BRIDGE_TOP, and not
##      `_deep_channel_ford`, which is only reached below that gate and answers
##      about the ROAD's stations.
##   B4. THE KILL SWITCH, over a deck's own window: with `spawn_bike_paths` off,
##      `field_bridges_near()` returns exactly what it returns with the flag on
##      minus this family's rows — so the flag turns off the QUERIES as well as
##      the boxes. It fails if the window it compared held no bike deck.
##   B6. THE DECK-WIDE WET PROBE REACHES ITS FAR EDGE at a width the probe step
##      does not divide. A constructed section with a river exactly on its far
##      lane, because the defect only shows where the water starts inside the last
##      step and no seed reliably puts a ramp there.
##   B5. THE WINDOW SCAN REJECTS ON A ROW'S WHOLE EXTENT, not on its endpoints:
##      the two older sources are monotone in X and a trunk may run due north. A
##      unit assertion on a deck built to bulge west of its own ends, because
##      whether a seed grows one is the population question that would make a
##      behavioural check vacuous.

## The end-of-check sentinel — see `scripts/selfcheck_sentinel.gd` for why every
## check stamps itself and the report site never prints SELFCHECK OK itself.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")

const TERRAIN_SCRIPT: String = "res://scripts/endless_terrain.gd"
## Check 1 builds real chunks, and a real chunk spawns real predators.
const CROC_SCENE: String = "res://scenes/characters/piglet_crocodile.tscn"

## The `landmark_sites_selfcheck` / `scarcity_selfcheck` / `waypoint_selfcheck`
## set. The paths move with `run_seed`, so one world proves nothing about the
## rule and only about that world.
const SEEDS: Array[int] = [20260904, 777, 4242]

## THE A/B FIELD: a 4x4 band of chunks off the road's north side on `SEEDS[0]`,
## chosen because it holds every kind of chunk check 1 needs — four carrying path
## geometry WITH poles, one carrying strip and dashes but NO pole (which is where
## the node-for-node comparison is made, see that check), and eleven carrying no
## path at all. It is a band and not a scatter so that a path crossing a seam is
## compared on both sides of it.
##
## IT MOVES WHEN THE STREAM DOES, which is the point of the controls below rather
## than a fragility: they assert the mix instead of trusting this comment, so a
## retuned prime, salt or chance empties the band LOUDLY. Re-derive it by
## sweeping `spawn_bike_path_in_chunk` over a band and reading which chunks draw.
##
## RE-DERIVED for child `godot-test1-pnvb.4`: aimed spurs live where a trunk is in
## reach, so the old band (y 8..11) holds no path at all and checks 1, 2a and 5 go
## red on empty. This one (y 2..5, same X) holds 6 path chunks, 10 empty ones, 2
## that draw geometry with no pole, and 3 spur markers on seed 20260904: the mix
## the controls screen for, counted with empty obstacles (the real pipeline can
## only skip more poles, never fewer, so the bare count is the conservative one).
const AB_X: Array[int] = [-5, -4, -3, -2]
const AB_Y: Array[int] = [2, 3, 4, 5]

## The CUBE bucket's node name — `ChunkBatch._emit_kind_multimesh` keeps the bare
## name for CUBE and suffixes every other kind, and this family builds CUBEs only.
const CUBE_BUCKET: String = "BlockMultiMesh"
## The chunk's single shared collision body.
const BLOCK_BODY: String = "BlockCollision"

## How many real paths check 2b walks the whole cover of. Every one of them costs
## `(2 * scan_radius + 1)^2` spawner calls, so this is a bound on the check's cost
## rather than on its meaning: the assertion is about the RULE, and six paths on
## six different stretches of field exercise it as well as thirty do.
const COVER_SAMPLE: int = 6

## Check 3's SEARCH SPACE in seeds, not a sample: it sweeps these in order and
## stops at the first seed by which it has seen both shapes it needs — a
## truncated path and one that ran to `BIKE_PATH_MAX_STATIONS`. The three CI
## `SEEDS` lead it only because they are cheap to try first, and
## `waypoint_selfcheck`'s CONTROL_SEEDS is the same shape.
const TRUNCATION_SEEDS: Array[int] = [20260904, 777, 4242, 1, 424242, 999983, 750, 99]

## How many station-strides `_check_half_step_control` samples looking for a
## narrow river band. The measured rate is one per ~49,000 dry pairs, so this is
## sized to find several and it stops at the first.
const HALF_STEP_SAMPLES: int = 250000

## Check 2's and check 3's search space, in chunks, centred on the origin. Big
## enough to hold several paths on every seed (measured: 3 to 20 per seed over
## this square) and small enough to stay a fraction of a second.
const SWEEP_HALF: int = 14

## C4's corridor band, in origin chunks: the sweep the spur:trunk ratio is
## printed over. Wide enough that aimed spurs survive on every CI seed (a 29x29
## square holds 0-3); the ratio is survivors per trunk in the world memo, so the
## band sets its scale and the const comment on `BIKE_PATH_CHANCE` records what
## this one measured.
const C4_X0: int = -30
const C4_X1: int = 30
const C4_Y0: int = -10
const C4_Y1: int = 20

## How far a strip box's world centre may sit from its segment's midpoint in
## check 2c. Metres, and it is a float-comparison tolerance rather than a design
## allowance: the two numbers are computed from the same `Vector2` a few calls
## apart, so anything above millimetres is a real displacement.
const STRIP_TOLERANCE: float = 0.01

## Check 4's far field: origins this many chunks out on Z, which at chunk_size 50
## is ~6 km from both the Budapest rect and the HQ corridor — comfortably past
## `SCARCITY_PLAIN_DISTANCE` (4 km), where `scarcity_at()` is exactly 0.
const FAR_CHUNK_Y: int = 130

## Checks 7-8 sweep THREE seeds, so their square is smaller than `SWEEP_HALF`'s —
## 19x19 chunks per seed is a few hundred poles, which is two orders of magnitude
## more than the five-kind histogram needs and still a fraction of a second. The
## histogram is the assertion; the square is only its cost.
const TOP_SWEEP_HALF: int = 9

## How many boxes check 7c will read as a pole's top. `_draw_path_share` emits the
## post and then exactly one top, and the largest top is four boxes (a head plus its
## three lenses; CROSSING is a plate plus three pips). The run also stops at the next
## post or at ground level, so this is a bound and not a count — and check 7c asserts
## the bound still covers `SIGN_KINDS`, because a top that outgrew it would lose its
## last box out of the measurement in silence.
const TOP_BOXES_MAX: int = 4

## Below this height, in metres, a box is this family's PAINT — the strip sits at 0.03
## and a dash at 0.075, so anything under it is the next segment's rather than the
## pole's top. It is what ends the run when a pole's top is shorter than
## `TOP_BOXES_MAX`.
const GROUND_BAND: float = 0.2

## Float slack on check 7c's clearance comparison, metres. The two sides are computed
## from the same constants a few calls apart, so this is precision and not an
## allowance: a real overlap is centimetres, not microns.
const CLEARANCE_TOLERANCE: float = 0.0005

## Check 9's fixture prefix: the kinds a real chunk already holds by the time this
## family runs — a mast, a rock, a wedged roof. THREE of the seven are CUBEs, so a
## bike-path box's CUBE-bucket index and its batch index are DIFFERENT NUMBERS,
## which is the only reason that check can tell one from the other. Check 9 (b)
## fails loudly if this stops being true.
const PREFIX_KINDS: Array[int] = [
	ChunkBatch.BoxKind.CYLINDER, ChunkBatch.BoxKind.CUBE, ChunkBatch.BoxKind.ROCK,
	ChunkBatch.BoxKind.CUBE, ChunkBatch.BoxKind.CYLINDER, ChunkBatch.BoxKind.WEDGE,
	ChunkBatch.BoxKind.CUBE,
]

## How many chunks check 9 will build for real looking for a head that survived
## the pole's footprint skip. A bare-spawner hit is only a candidate — see that
## check — and at the shipped mix most candidates do survive, so this is a bound
## on a search that normally ends on its first try.
const LAMP_CANDIDATES: int = 12

## Check 10b reads this family AS TEXT.
const FAMILY_SCRIPT: String = "res://scripts/terrain_bike_paths.gd"

## `[function, needle, must contain, why]`. Each row is a rule that a behavioural
## check can only speak for the world it sampled, so it is read out of the source
## instead — `scarcity_selfcheck` check 3's form. The needles are deliberately the
## CODE spelling and not the prose one (`rng.randomize()`, not `randomize()`), so a
## rule cannot be satisfied by the docstring that explains it.
const TEXT_RULES: Array[Array] = [
	["_plant_signal_timers", "rng.randomize()", true,
		"the traffic light's phase and dwell are AMBIENCE and CLAUDE.md puts ambience "
		+ "outside the determinism contract on a randomize()d RNG. A seeded clock would "
		+ "put two peers' lamps in lockstep, which is a promise this game does not make "
		+ "and the wire does not carry"],
	["_plant_signal_timers", "run_seed", false,
		"the cycle must never read the seed — see the rule above. Placement is seeded; "
		+ "the clock is not"],
	["_build_signal_head", "rng.randomize()", false,
		"the head's GEOMETRY is the seed's business and is drawn from the spawner's "
		+ "fixed-seed generator. Randomising it would make the same chunk differ between "
		+ "two players, which is the one thing the world contract forbids"],
	["write_lamps", ".srgb_to_linear())", true,
		"create_box stores its colour already linearised (chunk_batch.gd's COLOUR SPACE "
		+ "paragraph), so a raw Color written into the MultiMesh renders one lamp "
		+ "brighter than every other box in the world, on desktop and on web"],
]

## How far two colours may differ and still count as the same. A float-comparison
## tolerance and not a design allowance: both sides of every comparison in check 9
## run the same `srgb_to_linear()` on the same constant, so anything above the
## MultiMesh buffer's own float precision is a different colour.
const COLOR_TOLERANCE: float = 0.002

# ============================================================================
# TIER 1 — the trunk checks (epic `godot-test1-pnvb`, child `.2`)
# ============================================================================

## How many TRUNKS check T1 ties to the world, and how many segments of each. Every
## one costs a real `spawn_bike_path_in_chunk` over the whole chunk (both tiers), so
## this bounds the check's COST and not its meaning: the assertion is about the
## frame the geometry is drawn in, and one wrong frame is wrong everywhere.
const TIE_TRUNKS: int = 3
const TIE_SEGMENTS: int = 2

## How far a trunk strip's world centre may sit from its segment's midpoint, and how
## far its axis may swing off the segment's own direction. Both are float-comparison
## slack: the two sides come out of the same `Vector2` a few calls apart, so metres
## and degrees here would be a real displacement. The direction is compared as
## `absf(dot)` because a box yawed by PI is the same box.
const TIE_YAW_TOLERANCE: float = 1e-4

## T3a's FAR chunk — the synthetic k = 0 site both halves of the scarcity split are
## driven at, on the same band check 4 already measures as `scarcity_at() == 0`. The
## X is off the corridor's own axis so the pair below cannot share a road.
const T3A_FAR_CHUNK: Vector2i = Vector2i(3, FAR_CHUNK_Y)
## ...and the SEARCH BAND for its k = 1 CONTROL, inside `SCARCITY_CORRIDOR_RECT`.
## SEARCHED AND NOT TYPED, because a typed one rots: the first version was
## `Vector2i(3, 0)`, on the corridor's own axis, and the moment the coin road's
## swath joined `trunk_keep_out` that chunk could draw nothing at all and the
## control failed for a reason that had nothing to do with scarcity. The check
## takes the first chunk in this band that carries k = 1 AND actually stands a pole
## on a synthetic trunk — the thing the control asserts, screened on itself — and
## fails loudly if the band holds none.
const T3A_NEAR_BAND_X: Array[int] = [2, 3, 4, 5, 6, 7, 8]
const T3A_NEAR_BAND_Y: Array[int] = [0, 1, -1, 2, -2, 3, -3]

## How many stations T3a's synthetic trunk carries. It is laid straight across the
## chunk under test, so this only has to be long enough that several segment
## midpoints fall inside one 50 m chunk AND that the `BIKE_POLE_STRIDE` puts more
## than one pole there — 40 stations is 195 m centred on the chunk, which is both.
const T3A_STATIONS: int = 40

## T3b's SEED SWEEP. It is a MEASUREMENT and never a pass/fail (see that check), so
## this is "how much of the world was looked at" rather than a search that has to
## succeed. Eight seeds is a few seconds and is the number printed in the finding.
const T3B_SEEDS: Array[int] = [20260904, 777, 4242, 1, 424242, 999983, 750, 99]

## The drawn-chain sweep (bead godot-test1-pnvb.7, owner decision a′): T3B blind,
## exactly as it stood before any result was seen, plus 2 (a boundary-dangle
## world) and 42 (an HQ-sealed world) so every failure class found is represented.
## Do NOT extend this to chase green — a seed that passes post-hoc proves nothing.
const DRAWN_CHAIN_SEEDS: Array[int] = [20260904, 777, 4242, 1, 424242, 999983, 750, 99, 2, 42]
## Sealed worlds (owner decision a′): seed → [human reason, observed class]. The
## check asserts these come out BROKEN in the matching class — "exhausted" (the
## HQ reach stalls with the frontier spent) or "dangle" (a trunk touches the gate
## but its far end is a rect point) — and FAILS a sealed seed that comes out
## THERE ("no longer sealed — move it to the green list") or in the other class,
## so the record can never rot: a future walk-level fix has to touch this list.
const DRAWN_CHAIN_SEALED := {
	1: ["gate massif", "exhausted"],
	424242: ["hq massif", "exhausted"],
	42: ["hq in mountain biome", "exhausted"],
	2: ["boundary dangle", "dangle"],
}

## T4's ceiling on the trunk memo, in STATIONS across the whole world. Measured on
## the three CI seeds at the shipped `TRUNK_DEGREES`: 125 to 558. The ceiling is set
## an order of magnitude above the worst of them, because what it guards is a
## RETUNED density knob or a `TRUNK_MAX_EDGE` that suddenly joins the map corner to
## corner — not the current number, which T4 prints instead of asserting.
const TRUNK_MEMO_STATION_CAP: int = 20000

## How many TRUNKS check 2d walks the whole cover of. A trunk's box can reach a
## 10x10 block of chunks and every one of them costs a full two-tier spawner call,
## so this is a bound on the check's COST: the assertion is about the RULE, and
## three routes on three stretches of field exercise it as well as thirty do.
const TRUNK_COVER_SAMPLE: int = 3

## How far either side of a deck B4 asks `field_bridges_near()` about. Wider than
## one bridge and far narrower than the road, so the comparison is about this
## crossing rather than about the whole world — and it is in the same units the
## shipped consumers use (`spawn_field_bridges_in_chunk` asks for half a chunk).
const BRIDGE_WINDOW: float = 120.0

## How far a drawn deck's walking surface may sit from the one
## `field_bridge_surface_y()` reports. A float-comparison tolerance and not a
## design allowance: both sides are the same profile read two different ways, so
## anything above the batch transform's own precision is a real disagreement.
const BRIDGE_Y_TOLERANCE: float = 0.002

## B5's synthetic deck: how far east it stands, and how far its middle bulges
## WEST of its two ends. The bulge only has to be bigger than nothing — it is 60 m
## so the window arithmetic has room on both sides of it and the failure message
## can print a number a reader recognises as a real deck's width of drift.
const X_WINDOW_EAST: float = 900.0
const X_WINDOW_BULGE: float = 60.0

## B2b's own sampling pitch over a ramp rectangle, metres. A QUARTER of the
## builder's `FIELD_BRIDGE_PROBE_STEP` on purpose: a control that sampled at the
## same pitch as the code under test would agree with it about which points exist,
## and the defect this catches is exactly a lane the builder's walk never reached.
const RAMP_PROBE: float = 0.25

## Where B6 looks for a river EDGE — a band of the corridor either side of the
## road, which every seed's rivers cross. It is a search space and not a claim
## about a world: the check fails if it finds nothing in here, which is what makes
## retuning it the right response rather than deleting the assertion.
const PROBE_SCAN_RECT: Rect2 = Rect2(-300.0, -200.0, 900.0, 400.0)
## Its pitch. Fine in Z because it is hunting a band edge, coarse in X because one
## river crossing anywhere in the rect is all it needs.
const PROBE_SCAN_STEP: float = 0.5
const PROBE_SCAN_STEP_X: float = 7.0
## A hair, to keep the lane walk below `half` off the far edge itself.
const EDGE_EPS_LOCAL: float = 0.001

## The edge id T3a's synthetic route wears. It replaces the memo whole, so it
## cannot collide with anything — but it is deliberately not 0 either, so a marker
## carrying it can never be mistaken for a real trunk in a log.
const SYNTHETIC_EDGE_ID: int = 909090

## R1/R2/R3 — the anchor racks (bead `godot-test1-z2yv.3`). The tie table: which
## anchors R3 builds for real, and the stated literal distance each rack's
## geometry may stand from its anchor. Seed-pinned like AB_X/AB_Y: the sites are
## the search's nearest clearing ring on SEEDS[0] — 80 m for the HQ past the
## tower disc, 16 m for wp_spawn, 36 m for landmark_0 out of its own chunk — and
## each bound gives a small allowance past it. A rack slid 25 m outward lands
## past every one of them, which is the displacement mutation.
const TIE_ANCHORS: Array[int] = [0, 3, 13]
const TIE_BOUNDS: Array[float] = [82.0, 20.0, 40.0]

## How near a rack's geometry its marker must be. The marker carries the site
## itself, so anything above millimetres is a real disagreement — and a marker
## with no rack under it is the lie this bead exists to prevent.
const MARKER_GEOMETRY_TOLERANCE: float = 3.0

## How near a spur end a stand marker may stand before R1 calls it a rack on a
## spur. A rack is ~2 m of steel, so 5 m is far past float slack and far short
## of the reach that would explain the marker as some anchor's.
const SPUR_END_CLEARANCE: float = 5.0

var _failures: Array[String] = []


func _initialize() -> void:
	Sentinel.isolate_user_state()
	# A coroutine because check 1 needs a terrain that is really IN the tree
	# before it calls `create_chunk` — `root.add_child()` inside `_initialize()`
	# has not put a node in the tree yet, and several spawners ask the chunk for a
	# global transform. `waypoint_selfcheck`'s recipe.
	_run()


func _run() -> void:
	await process_frame
	var terrain_script: GDScript = load(TERRAIN_SCRIPT)
	_check_kill_switch(terrain_script)
	_check_purity_and_seams(terrain_script)
	_check_truncation(terrain_script)
	_check_scarcity(terrain_script)
	_check_no_new_buckets(terrain_script)
	_check_footprints(terrain_script)
	_check_tops_and_cubes(terrain_script)
	_check_sign_clearance(terrain_script)
	_check_lamp_indices(terrain_script)
	_check_cycle_off_the_seed(terrain_script)
	# --- TIER 1, the trunk routes (epic `godot-test1-pnvb`, child `.2`). Checks 2, 3
	# and 4 above already grew a trunk half of their own. 2d rides check 2, 3b rides
	# check 3, T3a and T3b ride check 4; everything below is its own call: T1, T2,
	# T5, T4, the drawn chain, and child `.4`'s C1 through C4.
	# Keep that list true. — the banner says why it is the only
	# cross-check on the list.
	_check_trunk_world_tie(terrain_script)
	_check_trunk_intersections(terrain_script)
	_check_trunk_keep_outs(terrain_script)
	_check_trunk_memo(terrain_script)
	_check_drawn_chain_reaches_budapest(terrain_script)
	_check_road_crossing_world_tie(terrain_script)
	_check_no_coin_on_strip(terrain_script)
	_check_crossing_angle_rule(terrain_script)
	_check_spurs_attach(terrain_script)
	# --- BEAD `godot-test1-z2yv.3`, the anchor racks: R1 (one rack per touched
	# anchor, spurs bare), R2 (the `bike_stand` contract), R3 (the world tie).
	_check_anchor_racks(terrain_script)
	_check_bike_stand_contract(terrain_script)
	_check_anchor_rack_world_tie(terrain_script)
	_check_rack_clearance(terrain_script)
	# --- CHILD `.3`, the bridges. SIX STATEMENTS IN FOUR CALLS: B1 (with B1b), B3
	# and B4 are one call because they all need the same drawn deck, B5 and B6 are
	# the two unit assertions on the pieces no seed reliably exercises, and B2 (with
	# B2b) is its own sweep.
	_check_trunk_bridges(terrain_script)
	_check_bridge_x_window(terrain_script)
	_check_deck_probe_width(terrain_script)
	_check_no_paint_on_water(terrain_script)
	# AWAITED, and it is the only one that is: a chunk unloads through `queue_free`,
	# so the check has to let a frame pass before it can ask whether the Timer is
	# really gone. See `_check_unload`.
	await _check_unload(terrain_script)

	if _failures.is_empty():
		print("bike paths: the kill switch leaves every other box in the world where "
				+ "it was, each strip stands on the ground its own walk cleared, the "
				+ "per-chunk shares cover every segment exactly once, blocked paths "
				+ "truncate rather than gap, scarcity empties the far field, no chunk "
				+ "grew a MultiMesh bucket, only the poles claim a footprint, every "
				+ "pole carries one of the five authored tops and stands it clear of "
				+ "its own post, the CUBE-bucket index recorded for a lamp is the one "
				+ "the shipped bucketing really puts it at, the cycle is randomize()d "
				+ "ambience the seed cannot see, an unloaded chunk leaves no Timer "
				+ "behind, every trunk runs from one anchor to another and never stops in "
				+ "open field, two trunks sharing an anchor end on the same metre to the "
				+ "bit, a trunk's bounding-box lookup covers every segment exactly once, "
				+ "the far field keeps a trunk's paint while losing all of its poles, and "
				+ "no trunk lays a box or a footprint inside the disc of the destination it "
				+ "is heading for, a trunk crosses a river on a deck whose stone, whose "
				+ "surface query and whose water all agree about one place, a hero standing "
				+ "on one is neither wading nor pushed off it, the kill switch takes the "
				+ "decks out of field_bridges_near() as well as out of the batch, and no "
				+ "strip of this family's paint is ever laid on open water, one "
				+ "bike-stand rack stands at every network anchor a trunk touches "
				+ "and no spur end grows one, every marker carries exactly the "
				+ "contract the rental epic will read, and a rack box really in "
				+ "the chunk's batch stands within a stated distance of its anchor, "
				+ "with the footprint asked in the rack's own radius")
		Sentinel.finish(self)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	quit(1)


func _fail(message: String) -> void:
	_failures.append(message)


# ============================================================================
# CHECK 1 — the kill switch, and therefore the RNG stream
# ============================================================================

func _check_kill_switch(terrain_script: GDScript) -> void:
	"""
	The same field of chunks with `spawn_bike_paths` true and false, compared
	through the SHIPPED `create_chunk` on both sides.

	WHY THE WHOLE PIPELINE AND NOT THE SPAWNER ALONE: what has to hold is that
	this family costs the shared chunk / biome / crocodile streams NOTHING, and
	the only place that is visible is downstream of it. A single stray draw slides
	every crocodile and every coin in the chunk, which the node table below sees;
	a box drawn in the wrong place the MultiMesh table sees. Calling the spawner
	on an empty batch would prove neither.

	THE SLICE is the `gag_start` / `gag_count` idiom (`camp_story_selfcheck`),
	moved into CUBE-bucket coordinates because by comparison time the batch is
	gone and the MultiMesh is what is left: `_build_block_multimesh` buckets by
	kind, so the marker's `cube_start` plus `batch_count` is exactly this family's
	run of instances in the CUBE bucket. Cutting it out must leave the OFF chunk.
	"""
	var on: Node3D = _terrain(terrain_script, SEEDS[0], true)
	var off: Node3D = _terrain(terrain_script, SEEDS[0], false)
	var with_path: int = 0
	var without: int = 0
	var bare_path: int = 0
	var nodes_seen: int = 0

	for x: int in AB_X:
		for y: int in AB_Y:
			var chunk_pos := Vector2i(x, y)
			on.create_chunk(chunk_pos)
			off.create_chunk(chunk_pos)
			var chunk_on: Node = on.active_chunks[chunk_pos]
			var chunk_off: Node = off.active_chunks[chunk_pos]

			var markers: Array[Node] = _markers(chunk_on)
			var poles: int = 0
			var sliced: int = 0
			for marker: Node in markers:
				poles += (marker.get_meta("poles") as PackedInt32Array).size()
			if not markers.is_empty():
				sliced = int(markers[0].get_meta("batch_count"))
			if markers.is_empty():
				without += 1
			else:
				with_path += 1

			# --- The boxes, bucket by bucket, with our own run cut out of CUBE.
			var table_on: Dictionary = _multimesh_table(chunk_on)
			var table_off: Dictionary = _multimesh_table(chunk_off)
			if not markers.is_empty():
				var start: int = int(markers[0].get_meta("cube_start"))
				var count: int = int(markers[0].get_meta("batch_count"))
				if not table_on.has(CUBE_BUCKET):
					_fail("chunk %s carries a bike path but has no '%s' child — every box "
							% [chunk_pos, CUBE_BUCKET] + "this family builds is a CUBE")
				else:
					var rows: Array = table_on[CUBE_BUCKET]
					if start + count > rows.size():
						_fail("chunk %s: the marker claims CUBE instances [%d, %d) but the "
								% [chunk_pos, start, start + count]
								+ "bucket holds %d — the cube-bucket invariant has broken "
								% rows.size()
								+ "(a later spawner now inserts rather than appends)")
					else:
						table_on[CUBE_BUCKET] = rows.slice(0, start) + rows.slice(start + count)
			if table_on.keys() != table_off.keys():
				_fail("chunk %s has MultiMesh buckets %s with the paths on and %s with them "
						% [chunk_pos, table_on.keys(), table_off.keys()] + "off")
			else:
				for name: String in table_off:
					if var_to_bytes(table_on[name]) != var_to_bytes(table_off[name]):
						_fail("chunk %s: the '%s' bucket differs between the two builds once "
								% [chunk_pos, name] + "this family's own %d boxes are sliced out "
								% sliced + "— the paths moved somebody else's geometry")
						break

			# --- The bodies: crocodiles, coins, everything parented to the chunk.
			#
			# ONLY WHERE THIS FAMILY APPENDED NO FOOTPRINT, and that is not a
			# weakening — it is where the claim is exactly true. A pole footprint is
			# read by the crocodile, boss and hunter spawners that run after this
			# one, and `terrain_predators.gd` says what follows: "a rejection still
			# skips the successful spawn's `rotation.y` draw below, so the rest of
			# this chunk's crocodile positions shift". That is the shared-currency
			# mechanism camps and chests use too, so a difference on a chunk with a
			# pole would be sanctioned behaviour and this comparator cannot tell it
			# from a stray draw. On a chunk with no pole nothing downstream can even
			# see the paths, so a single differing node IS a draw.
			if poles == 0:
				# ...and THIS is the one with any power: a chunk where the drawing code
				# really ran and still appended no footprint. Counted separately from
				# `nodes_seen`, which the band's eleven path-free chunks would keep
				# comfortably above zero on their own.
				if not markers.is_empty():
					bare_path += 1
				var nodes_on: Array[String] = _node_table(chunk_on)
				var nodes_off: Array[String] = _node_table(chunk_off)
				nodes_seen += nodes_off.size()
				if nodes_on != nodes_off:
					_fail("chunk %s carries no bike-path pole, so nothing downstream can see "
							% chunk_pos + "this family at all — yet it holds %d chunk-parented "
							% nodes_on.size() + "nodes with the paths on and %d with them off. "
							% nodes_off.size() + "A draw was taken from the shared chunk stream")

			# --- The collision body. Its shapes are added inline by `create_box`, so
			# they are not a list a marker indexes; what IS exactly stated is that
			# this family adds one shape per POLE and none for its paint.
			var shapes_on: int = _shape_count(chunk_on)
			var shapes_off: int = _shape_count(chunk_off)
			if shapes_on != shapes_off + poles:
				_fail("chunk %s: %d collision shapes with the paths on, %d without and %d "
						% [chunk_pos, shapes_on, shapes_off, poles]
						+ "poles built — the strip or the dashes are colliding")

	if with_path == 0:
		_fail("check 1's A/B field holds no chunk with a bike path in it, so the slice was "
				+ "never exercised and the comparison passed for the wrong reason — retune "
				+ "AB_X / AB_Y against the current seed")
	if without == 0:
		_fail("check 1's A/B field holds no chunk WITHOUT a bike path, so 'identical' was "
				+ "never the trivial case it needs as a control")
	if nodes_seen == 0:
		_fail("check 1 compared %d chunks and found no chunk-parented nodes at all in any of "
				% (AB_X.size() * AB_Y.size())
				+ "them — the half of this check that catches a stray draw is blind")
	if bare_path == 0:
		# THE CONTROL THE `poles == 0` GATE NEEDS, and it is not the same as
		# `with_path`. On a chunk with no path at all the spawner reaches no
		# `create_box` and the two builds are identical by construction whatever bug
		# exists, so the node comparison asserts nothing there. Only a chunk that
		# DREW and still appended no footprint can show a stray draw — and a retune
		# of the chance, the stride, the primes or the band that leaves every path
		# chunk carrying a pole would empty that set silently.
		_fail("check 1's A/B field holds no chunk that draws bike-path geometry AND appends "
				+ "no footprint, so its stray-draw comparison ran only on chunks where the "
				+ "spawner drew nothing and could not have failed. Retune AB_X / AB_Y until "
				+ "the band contains a path with no pole on it")
	# --- THE AIM, MEASURED (child `godot-test1-pnvb.4`, decision c-prime). Every
	# surviving spur in the band above re-rolls its four draws in their shipped
	# order and asserts the replacement: the rarity and the two offsets reproduce
	# the walk's start (no draw skipped or reordered), and the walked bearing and
	# length equal the aim at the nearest trunk station (consume-and-discard on
	# both). The target is brute-forced off the shipped memo WITHOUT the box
	# prefilter, so the lookup agrees with `_spur_aim_target` by value rather
	# than by sharing its code.
	var aim_checked: int = 0
	var trunks_on: Array[Dictionary] = BikePaths.trunks(on)
	for x: int in AB_X:
		for y: int in AB_Y:
			var chunk_here: Node = on.active_chunks[Vector2i(x, y)]
			for marker: Node in _markers(chunk_here):
				if int(marker.get_meta("edge")) != -1:
					continue
				var origin: Vector2i = marker.get_meta("origin")
				var stations: Array[Dictionary] = BikePaths.bike_path_at(on, origin)
				if stations.is_empty():
					_fail("check 1: a spur marker promises geometry the walk never drew")
					continue
				var rng := RandomNumberGenerator.new()
				rng.seed = hash(Vector3i(origin.x * BikePaths.BIKE_HASH_PRIME_X,
					origin.y * BikePaths.BIKE_HASH_PRIME_Y,
					on.run_seed ^ BikePaths.BIKE_PATH_SALT))
				var size: float = on.chunk_size
				var k: float = on.scarcity_at(on.chunk_to_world(origin))
				if not (rng.randf() < BikePaths.BIKE_PATH_CHANCE * k):
					_fail("check 1: a surviving spur whose rarity roll fails; the draw order moved")
				var start: Vector2 = stations[0]["pos"]
				if start != Vector2(float(origin.x) * size + rng.randf() * size,
					float(origin.y) * size + rng.randf() * size):
					_fail("check 1: a surviving spur starts away from its two offset draws "
					+ "a draw was added, removed or reordered ahead of them")
				var _bearing: float = rng.randf() * TAU
				var _length: int = rng.randi_range(BikePaths.BIKE_PATH_MIN_STATIONS,
					BikePaths.BIKE_PATH_MAX_STATIONS)
				var target := Vector2.INF
				var best_d: float = BikePaths.BIKE_PATH_MAX_REACH
				for trunk: Dictionary in trunks_on:
					for station: Dictionary in (trunk["stations"] as Array[Dictionary]):
						var d: float = start.distance_to(station["pos"])
						if d < best_d:
							best_d = d
							target = station["pos"]
				if target == Vector2.INF:
					_fail("check 1: a surviving spur with no trunk station in reach of its start")
					continue
				if float(stations[0]["heading"]) != (target - start).angle():
					_fail("check 1: a surviving spur not walking the aim at its nearest trunk station "
					+ "though the bearing draw was consumed")
				var want_count: int = mini(int(ceil(start.distance_to(target)
					/ BikePaths.BIKE_STATION_SPACING)) + 1, BikePaths.BIKE_PATH_MAX_STATIONS)
				if stations.size() != want_count:
					_fail("check 1: a surviving spur walking the wrong station count for its aim "
					+ "though the length draw was consumed")
				aim_checked += 1
	if aim_checked == 0:
		_fail("check 1 found no surviving spur in its A/B field, so the aim was never measured")
	print("check 1: the aim holds on %d band spurs" % aim_checked)
	on.free()
	off.free()
	Sentinel.done("kill_switch")


# ============================================================================
# CHECK 2 — purity, and the per-chunk shares of one polyline
# ============================================================================

func _check_purity_and_seams(terrain_script: GDScript) -> void:
	"""
	The same chunk twice is the same chunk; and across a field, the segments drawn
	by every chunk in reach of an origin are the polyline's own, each exactly once.

	THE SEAM IS THE POINT. A path is rolled at its ORIGIN and drawn by whichever
	chunk each segment's MIDPOINT falls in, so "no duplicate, no gap" is the whole
	statement of that rule — the failure it excludes is a strip that stops at a
	chunk edge and starts again half a metre later.

	The union is read off the markers' `segments` meta rather than recomputed
	here, deliberately: a second copy of the midpoint rule inside this check would
	agree with a broken one. What this check owns instead is the COMPARATOR, and
	the two mutations below are the control on it.

	...AND THEN (c) WHERE THE BOX ACTUALLY LANDS, which is the one assertion in
	this file that connects a drawn box to the station that produced it. Every
	other check compares a build against another build (1, 5), a list against
	itself (2a, 2b), a station list against a predicate (3, 4) or a count against
	a count (6) — all of which a uniformly wrong local frame satisfies perfectly.
	`create_box` takes a CHUNK-LOCAL centre and the chunk node stands at the chunk
	CENTRE, so a conversion that subtracted the corner instead would put every
	strip half a chunk off the ground `station_blocked` cleared, across the coin
	road and the rivers, with all six checks green. This is measured in WORLD
	space — the chunk node's position plus the batch entry's own origin — because
	that is the frame the claim is made in.

	WHAT IT DOES AND DOES NOT PIN, honestly: ANY partition of the segments is a
	perfect cover, so this does not prove the rule is the MIDPOINT one — it proves
	it is a partition. That is the property the seam needs, and the two realistic
	ways to lose it are exactly the two the mutations exercise: draw a segment in
	every chunk an endpoint touches (a strip drawn twice) and draw it only where
	both endpoints land (a hole at every seam).
	"""
	var terrain: Node3D = _terrain(terrain_script, SEEDS[0], true)
	var radius: int = BikePaths.scan_radius_chunks(terrain)

	# --- a. WITHIN A RUN: the same chunk, built twice, down to the byte.
	var rebuilt: int = 0
	for x: int in AB_X:
		for y: int in AB_Y:
			var chunk_pos := Vector2i(x, y)
			var first: Dictionary = _spawn_bare(terrain, chunk_pos)
			var second: Dictionary = _spawn_bare(terrain, chunk_pos)
			if var_to_bytes(first["batch"]) != var_to_bytes(second["batch"]):
				_fail("chunk %s built two different batches on two passes of the same run — "
						% chunk_pos + "a revisited chunk must regenerate identically")
			if var_to_bytes(first["obstacles"]) != var_to_bytes(second["obstacles"]):
				_fail("chunk %s appended two different obstacle lists on two passes"
						% chunk_pos)
			if var_to_bytes(first["paths"]) != var_to_bytes(second["paths"]):
				_fail("chunk %s recorded two different marker tables on two passes"
						% chunk_pos)
			if not (first["batch"] as Array).is_empty():
				rebuilt += 1
	if rebuilt == 0:
		_fail("check 2a rebuilt %d chunks and not one of them drew a box, so 'identical' "
				% (AB_X.size() * AB_Y.size()) + "was vacuous")

	# --- b. THE COVER, over every path in a sweep of origins.
	var covered: int = 0
	var strip_checked: int = 0
	var sample: Array = []  # one real per-chunk split, kept for the mutation control
	for ox in range(-SWEEP_HALF, SWEEP_HALF + 1):
		for oy in range(-SWEEP_HALF, SWEEP_HALF + 1):
			var origin := Vector2i(ox, oy)
			if covered >= COVER_SAMPLE:
				break
			var stations: Array[Dictionary] = BikePaths.bike_path_at(terrain, origin)
			if stations.size() < 2:
				continue
			var lists: Array = []
			for cx in range(ox - radius, ox + radius + 1):
				for cy in range(oy - radius, oy + radius + 1):
					var chunk_pos := Vector2i(cx, cy)
					var built: Dictionary = _spawn_bare(terrain, chunk_pos)
					var drawn := PackedInt32Array()
					for row: Dictionary in (built["paths"] as Array[Dictionary]):
						if row["origin"] == origin:
							drawn = row["segments"]
					if drawn.is_empty():
						continue
					lists.append(drawn)
					# --- c. AND THE BOXES ARE WHERE THE WALK SAID. See the docstring.
					var strips: Array[Vector2] = _strip_positions(terrain, chunk_pos, built["batch"])
					for i: int in drawn:
						var a: Vector2 = stations[i]["pos"]
						var b: Vector2 = stations[i + 1]["pos"]
						var want: Vector2 = (a + b) * 0.5
						var best: float = INF
						for at: Vector2 in strips:
							best = minf(best, at.distance_to(want))
						if best > STRIP_TOLERANCE:
							_fail("origin %s segment %d: chunk %s claims to draw it, but its nearest "
									% [origin, i, chunk_pos] + "strip box stands %.2f m from the "
									% best + "segment's midpoint %s. The strip is not on the ground "
									% want + "the walk cleared — check the chunk-local frame, which "
									+ "is centred on the chunk NODE and not on its corner")
							break
						strip_checked += 1
			var fault: String = _cover_fault(lists, stations.size() - 1)
			if fault != "":
				_fail("the path from origin %s is not covered by the chunks around it: %s"
						% [origin, fault])
			else:
				covered += 1
			if sample.is_empty() and lists.size() >= 2:
				sample = lists
	if covered == 0:
		_fail("check 2b found no path at all in a %dx%d sweep of origins on seed %d — the "
				% [SWEEP_HALF * 2 + 1, SWEEP_HALF * 2 + 1, SEEDS[0]]
				+ "cover assertion was never made")
	if strip_checked == 0:
		_fail("check 2c located no strip box at all, so the one assertion in this file that "
				+ "ties a drawn box to the station that produced it never fired")
	if sample.is_empty():
		_fail("check 2b found no path that spans more than one chunk, so the seam — the "
				+ "whole subject of this check — was never crossed")
	else:
		# THE MUTATION CONTROL. Both directions, over the same real data: a rule
		# that dropped a segment and a rule that drew one twice must each be caught,
		# or a "perfect cover" verdict says nothing.
		var n: int = 0
		for list_v: Variant in sample:
			n += (list_v as PackedInt32Array).size()
		var gapped: Array = sample.duplicate(true)
		var first_list: PackedInt32Array = gapped[0]
		first_list.remove_at(0)
		gapped[0] = first_list
		if _cover_fault(gapped, n) == "":
			_fail("check 2b's comparator called a cover with a segment MISSING perfect — it "
					+ "would not notice a bike path with a hole at a chunk seam")
		var doubled: Array = sample.duplicate(true)
		doubled.append(sample[0])
		if _cover_fault(doubled, n) == "":
			_fail("check 2b's comparator called a cover with a segment drawn TWICE perfect — "
					+ "it would not notice two chunks both claiming the same strip")
	terrain.free()
	# --- d. AND THE SAME STATEMENT FOR A TRUNK, whose chunks are found by a
	# BOUNDING BOX and not by the radius scan the three passes above rely on.
	_check_trunk_cover(terrain_script)
	Sentinel.done("purity_and_seams")


func _check_trunk_cover(terrain_script: GDScript) -> void:
	"""
	CHECK 2 EXTENDED — a trunk's per-chunk shares are a perfect cover of its
	segments, so the BOUNDING-BOX LOOKUP AGREES WITH THE MIDPOINT RULE.

	THIS IS A DIFFERENT STATEMENT FROM 2b AND THAT IS WHY IT EXISTS. A spur is
	found by `scan_radius_chunks()`, a square sweep derived from the path's own
	maximum reach; a trunk is kilometres long and is found instead by rejecting on
	its bounding box. Those are two ways of answering "which chunks might hold a
	piece of this?", and a box that is too tight loses the segments at the ends —
	the chunk-seam bug, back in a new place. The midpoint rule is unchanged, so the
	cover is the whole assertion: every segment drawn by exactly one chunk.

	SWEPT OVER THE TRUNK'S OWN BOX IN CHUNKS, one chunk wider each way than the
	box claims, so a segment the box wrongly excluded would be FOUND by the sweep
	and reported as a duplicate-free hole rather than missed by both.

	THE COMPARATOR IS `_cover_fault_set`, NOT check 2b's `_cover_fault`, and it
	carries a third branch 2b's does not: "drawn, though it is over water or inside
	a keep-out disc". 2b's mutation controls do not reach it, so this check drives
	that branch itself at the bottom — a comparator credited with a control it does
	not have is the claim the next author would rely on instead of re-deriving.
	"""
	var terrain: Node3D = _terrain(terrain_script, SEEDS[0], true)
	var waypoints: Array[Dictionary] = terrain.waypoint_sites()
	var trunks: Array[Dictionary] = BikePaths.trunks(terrain)
	var covered: int = 0
	var spanned: int = 0
	var drawable_total: int = 0
	for trunk: Dictionary in trunks:
		if covered >= TRUNK_COVER_SAMPLE:
			break
		var stations: Array[Dictionary] = trunk["stations"]
		var edge_id: int = int(trunk["id"])
		# A TRUNK WITH NOTHING DRAWABLE IS NOT A SAMPLE, it is a vacuous pass — and
		# they exist: `hq -> wp_hq` is 48 m entirely inside the tower's keep-out disc,
		# so every one of its segments is skipped and any cover of the empty set is
		# perfect. Counting one toward `TRUNK_COVER_SAMPLE` was measured to let a
		# `_trunk_box` shrunk by three station strides pass this check (mutation M5).
		var want: Dictionary = _drawable_segments(terrain, stations, waypoints)
		if want.is_empty():
			continue
		# THE SWEEP IS DERIVED FROM THE STATIONS, NOT FROM `trunk["box"]`, and that is
		# the control rather than a detail: the box is the thing under test, so a
		# sweep taken from it would shrink in step with a box that had gone too tight
		# and the hole would close behind the mutation. Measured — an earlier draft
		# used the box and a `grow(-3 * spacing)` mutation came back GREEN.
		var lo := Vector2i(1 << 30, 1 << 30)
		var hi := Vector2i(-(1 << 30), -(1 << 30))
		for station: Dictionary in stations:
			var at: Vector2 = station["pos"]
			var c: Vector2i = terrain.world_to_chunk(Vector3(at.x, 0.0, at.y))
			lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
			hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
		var lists: Array = []
		for cx in range(lo.x - 1, hi.x + 2):
			for cy in range(lo.y - 1, hi.y + 2):
				var built: Dictionary = _spawn_bare(terrain, Vector2i(cx, cy))
				for row: Dictionary in (built["paths"] as Array[Dictionary]):
					if int(row["edge"]) == edge_id:
						lists.append(row["segments"])
		# THE EXPECTED SET IS THE DRAWABLE SEGMENTS above, not every segment. A trunk
		# is deliberately not drawn AT GROUND LEVEL over water (`.3` carries it on a
		# deck instead) or inside a destination's keep-out disc (T5), so a chunk
		# records only what it drew —
		# which is also why it leaves no marker where it drew nothing. Computed from
		# the SHIPPED predicates, so this owns no copy of the rule it is checking:
		# the midpoint assignment is still entirely the marker's word.
		drawable_total += want.size()
		var fault: String = _cover_fault_set(lists, want)
		if fault != "":
			_fail("trunk %d (%d stations, %d drawable) is not covered by the chunks its "
					% [edge_id, stations.size(), want.size()] + "bounding box reaches: %s. "
					% fault + "The box lookup and the midpoint rule disagree, which is a "
					+ "hole in the paint at a chunk seam")
		else:
			covered += 1
		if lists.size() >= 2:
			spanned += 1
	if trunks.is_empty():
		_fail("check 2d found no trunk at all on seed %d, so the bounding-box lookup was "
				% SEEDS[0] + "never exercised — the whole of tier 1 may be dead and every "
				+ "trunk assertion in this file would pass by finding nothing")
	elif covered == 0:
		_fail("check 2d walked %d trunks and could not complete the cover assertion on one "
				% trunks.size() + "of them")
	if spanned == 0:
		_fail("check 2d found no trunk whose segments are split across more than one chunk, "
				+ "so the seam — the whole subject of this check — was never crossed")
	if drawable_total == 0:
		_fail("check 2d expected no drawable segment at all across the trunks it walked, so "
				+ "its cover assertion was satisfied by an empty set")
	# THE COMPARATOR'S OWN CONTROL, all three directions, on a fixture rather than on
	# the world — `_cover_fault_set` is new in this bead and 2b's mutations drive
	# `_cover_fault` instead. Without the third one, a lost water or keep-out skip
	# would draw paint under a coin and this check would call it a perfect cover.
	var probe: Dictionary = { 1: true, 2: true }
	if _cover_fault_set([PackedInt32Array([1, 2])], probe) != "":
		_fail("check 2d's comparator rejects a cover that is in fact perfect")
	if _cover_fault_set([PackedInt32Array([1])], probe) == "":
		_fail("check 2d's comparator called a cover with a segment MISSING perfect — it "
				+ "would not notice a hole in a trunk at a chunk seam")
	if _cover_fault_set([PackedInt32Array([1, 2]), PackedInt32Array([2])], probe) == "":
		_fail("check 2d's comparator called a cover with a segment drawn TWICE perfect")
	if _cover_fault_set([PackedInt32Array([1, 2, 3])], probe) == "":
		_fail("check 2d's comparator accepted a segment that is NOT drawable — it would not "
				+ "notice the water skip or the keep-out skip being lost, which is paint "
				+ "over a river or under the coin road's coins")
	terrain.free()
	Sentinel.done("trunk_cover")


func _drawable_segments(terrain: Node3D, stations: Array[Dictionary],
		waypoints: Array[Dictionary]) -> Dictionary:
	"""
	Which of a route's segments this family draws at all, as a set of indices.

	Both skip rules, asked of the SHIPPED predicates rather than restated: the
	water (`is_river_at` at both stations, `segment_blocked` between — a trunk
	segment over a river is carried on `godot-test1-pnvb.3`'s DECK and is never
	painted at ground level, so it is not a drawn segment either way) and the
	destination keep-outs (`BikePaths.trunk_keep_out`, T5's ruling).
	"""
	var out: Dictionary = {}
	for i in range(stations.size() - 1):
		var a: Vector2 = stations[i]["pos"]
		var b: Vector2 = stations[i + 1]["pos"]
		if terrain.is_river_at(Vector3(a.x, 0.0, a.y)) \
				or terrain.is_river_at(Vector3(b.x, 0.0, b.y)) \
				or BikePaths.segment_blocked(terrain, a, b):
			continue
		if BikePaths.trunk_keep_out(terrain, a, waypoints) \
				or BikePaths.trunk_keep_out(terrain, b, waypoints) \
				or BikePaths.trunk_keep_out(terrain, (a + b) * 0.5, waypoints):
			continue
		out[i] = true
	return out


func _cover_fault_set(lists: Array, expected: Dictionary) -> String:
	"""
	`_cover_fault` against an EXPLICIT expected set rather than `0 .. n-1`.

	@return: "" when `lists` is a perfect cover of `expected`, otherwise the first
	         fault in words — a duplicate, a hole, or a segment drawn that should
	         not have been, which is the direction `_cover_fault` cannot express and
	         is exactly how a lost keep-out or water skip would show up here.
	"""
	var seen: Dictionary = {}
	for list_v: Variant in lists:
		for i: int in (list_v as PackedInt32Array):
			if seen.has(i):
				return "segment %d is drawn by two chunks" % i
			if not expected.has(i):
				return "segment %d is drawn, though it is over water or inside a keep-out disc" % i
			seen[i] = true
	for i_v: Variant in expected:
		if not seen.has(i_v):
			return "segment %d is drawn by no chunk at all" % int(i_v)
	return ""


func _cover_fault(lists: Array, segment_count: int) -> String:
	"""
	Is `lists` — one per-chunk list of segment indices — a perfect cover of
	`0 .. segment_count - 1`?

	@return: "" when it is, otherwise the first fault in words.
	"""
	var seen: Dictionary = {}
	for list_v: Variant in lists:
		for i: int in (list_v as PackedInt32Array):
			if seen.has(i):
				return "segment %d is drawn by two chunks" % i
			seen[i] = true
	for i in segment_count:
		if not seen.has(i):
			return "segment %d is drawn by no chunk at all" % i
	return ""


# ============================================================================
# CHECK 3 — blocked means truncated, never gapped
# ============================================================================

func _check_truncation(terrain_script: GDScript) -> void:
	"""
	Find paths that actually run into something and assert they STOP there.

	A SWEEP AND NOT A FIXTURE, and it fails when the sweep comes up empty: the
	rule under test is "a blocked station ends the path", and a check that never
	met a blocked station would report that rule as holding while saying nothing.
	TWO shapes have to turn up, not one — a truncated path and a path that ran to
	full length — and `TRUNCATION_SEEDS` is a search space rather than a sample.

	THE HALF-STEP SAMPLE IS CONTROLLED SEPARATELY, in `_check_half_step_control`
	below, because no path sweep this file can afford would ever meet the shape it
	guards. Read that function before trusting the segment assertion here.

	WHAT IS ASSERTED and what is only COUNTED, because the difference matters to
	the next reader. ASSERTED, per path: every station in the list passes the
	station predicate, every SEGMENT between two of them passes the half-step
	river sample, and the list is at least `BIKE_PATH_MIN_STATIONS` long. Both
	predicates, because the walk stops on both and the second is not implied by
	the first — two stations either side of a narrow band are each legal on their
	own. That set IS the "never resumes past a block" rule: a walk that resumed
	would leave a blocked station, or a drowned segment, inside the list.
	COUNTED, per path: whether the station
	after the last one is blocked. That cannot be asserted, and deliberately so —
	`_bike_path_at` rolls its length with `randi_range`, so a path that simply ran
	out has a perfectly legal successor. It is the NON-VACUITY GUARD at the bottom
	of this function instead, and the guard is the point: without it the two
	assertions above hold trivially in a world where nothing is ever blocked.

	The successor comes from `BikePaths.next_station()` and
	`BikePaths.segment_blocked()` — the shipped recurrence and the shipped
	half-step river sample, not copies of them here.
	"""
	var truncated: int = 0
	var full_length: int = 0
	var swept: int = 0
	for seed_value: int in TRUNCATION_SEEDS:
		# Stop at the first seed by which every shape has been seen. The prefix
		# assertions below ran on every path of every seed swept, so this bounds the
		# SEARCH and not the checking.
		if truncated > 0 and full_length > 0:
			break
		swept += 1
		var terrain: Node3D = _terrain(terrain_script, seed_value, true)
		for ox in range(-SWEEP_HALF, SWEEP_HALF + 1):
			for oy in range(-SWEEP_HALF, SWEEP_HALF + 1):
				var origin := Vector2i(ox, oy)
				var stations: Array[Dictionary] = BikePaths.bike_path_at(terrain, origin)
				if stations.is_empty():
					continue
				# THE PREFIX IS LEGAL, and that is BOTH predicates the walk stops on.
				# The stations first...
				for i in stations.size():
					if BikePaths.station_blocked(terrain, stations[i]["pos"]):
						_fail("seed %d origin %s: station %d of %d stands somewhere the walk "
								% [seed_value, origin, i, stations.size()]
								+ "should have stopped — the path is not a legal prefix")
						break
				# ...and then the GROUND BETWEEN THEM, which is a separate statement and
				# not a corollary of the one above: the whole reason `segment_blocked`
				# exists is that both stations flanking a river band narrower than the
				# station pitch are individually legal. Asserting only the stations would
				# pass a strip laid straight across the water.
				for i in range(stations.size() - 1):
					if BikePaths.segment_blocked(terrain, stations[i]["pos"], stations[i + 1]["pos"]):
						_fail("seed %d origin %s: the strip between stations %d and %d crosses "
								% [seed_value, origin, i, i + 1]
								+ "water, though both of its ends stand on dry ground — the "
								+ "half-step river sample is not stopping the walk")
						break
				if stations.size() < BikePaths.BIKE_PATH_MIN_STATIONS:
					_fail("seed %d origin %s: a path of %d stations survived, below "
							% [seed_value, origin, stations.size()]
							+ "BIKE_PATH_MIN_STATIONS %d — a stub should be dropped whole"
							% BikePaths.BIKE_PATH_MIN_STATIONS)
				var head: float = stations[0]["heading"]
				var next: Dictionary = BikePaths.next_station(terrain, origin, head,
						stations[-1], stations.size() - 1)
				if BikePaths.station_blocked(terrain, next["pos"]) \
						or BikePaths.segment_blocked(terrain, stations[-1]["pos"], next["pos"]):
					truncated += 1
				elif stations.size() == BikePaths.BIKE_PATH_MAX_STATIONS:
					full_length += 1
		terrain.free()

	if truncated == 0:
		_fail("check 3 swept %d seeds x %dx%d origins and found no path that was stopped by "
				% [swept, SWEEP_HALF * 2 + 1, SWEEP_HALF * 2 + 1]
				+ "the road, a river, the mountains, the city, the HQ, a landmark or a "
				+ "waypoint — the truncation rule is untested, so widen TRUNCATION_SEEDS "
				+ "rather than trusting this")
	if full_length == 0:
		_fail("check 3 found no path that ran to BIKE_PATH_MAX_STATIONS, so 'it stopped "
				+ "because it was blocked' has no control: every path may simply be short")
	_check_half_step_control(terrain_script)
	_check_trunk_endings(terrain_script)
	Sentinel.done("truncation")


func _check_trunk_endings(terrain_script: GDScript) -> void:
	"""
	CHECK 3 EXTENDED — A TRUNK NEVER ENDS IN OPEN FIELD, which is the exact defect
	the owner reported and the reason this epic exists.

	A spur truncates at any of seven tests. A trunk may not: a route that stops
	halfway is the litter the owner played and disliked, so the only legal endings
	are its own ANCHOR (the snap) and BUDAPEST'S RECT EDGE (the city's streets are
	authored). Everything else abandons the route WHOLE, and this asserts that the
	ones that survived really did end one of those two ways.

	AND IT PRINTS WHY THE OTHERS DID NOT, split by cause, because one of those
	numbers WAS `godot-test1-pnvb.4`'s case and is now its report card: steep crossings
	MID-SPAN (*"a crossing would put road coins on the strip"*), and how many edges
	that costs the network is a measurement rather than an argument. Near its OWN
	anchor a trunk may walk the corridor — the gate sits dead centre in it — and T5
	is what asserts it paints none of that stretch. The reasons come
	from the shipped `BikePaths.trunk_abandoned()`, not from a second walk here.

	IT ALSO PINS `TRUNK_APPROACH_RADIUS` TO THE DISC IT WAS DERIVED FROM. That
	constant exists so a trunk to the HQ may cross the tower's exclusion disc for
	its last stretch, and it is typed rather than computed because a `const` cannot
	read the terrain. A `TOWER_RADIUS` that grew past it would silently start
	abandoning every trunk that ends at the HQ, with nothing else in this file
	able to see it.
	"""
	var reasons: Dictionary = {}
	var checked: int = 0
	var at_anchor: int = 0
	var at_rect: int = 0
	var road_stations: int = 0
	var midspan_crossings: int = 0
	for seed_value: int in SEEDS:
		var terrain: Node3D = _terrain(terrain_script, seed_value, true)
		if BikePaths.TRUNK_APPROACH_RADIUS < terrain.TOWER_RADIUS:
			_fail("BikePaths.TRUNK_APPROACH_RADIUS is %.1f m but the tower's exclusion disc "
					% BikePaths.TRUNK_APPROACH_RADIUS + "is %.1f m — a trunk whose anchor IS "
					% terrain.TOWER_RADIUS + "the tower's centre can no longer reach it, and "
					+ "every HQ trunk is being abandoned in silence")
		var anchors: Array[Dictionary] = terrain.bike_anchors()
		var edges: Array[Dictionary] = terrain.bike_edges()
		var built: Dictionary = {}
		for trunk: Dictionary in BikePaths.trunks(terrain):
			built[int(trunk["id"])] = trunk
		for edge: Dictionary in edges:
			var edge_id: int = int(edge["id"])
			if not built.has(edge_id):
				var why: String = BikePaths.trunk_abandoned(terrain, edge)
				if why == "":
					_fail("seed %d: edge %d produced no trunk, yet trunk_abandoned() gives no "
							% [seed_value, edge_id] + "reason — a route is disappearing "
							+ "somewhere the reporting cannot see")
				reasons[why] = int(reasons.get(why, 0)) + 1
				continue
			checked += 1
			var stations: Array[Dictionary] = built[edge_id]["stations"]
			var fa: Vector2 = anchors[int(built[edge_id]["a"])]["pos"]
			var fb: Vector2 = anchors[int(built[edge_id]["b"])]["pos"]
			for station: Dictionary in stations:
				var at: Vector2 = station["pos"]
				if at.distance_to(fa) < BikePaths.TRUNK_APPROACH_RADIUS \
					or at.distance_to(fb) < BikePaths.TRUNK_APPROACH_RADIUS:
					continue
				if terrain._road_lateral_distance(at.x, at.y, BikePaths.BIKE_ROAD_CLEARANCE) \
					< BikePaths.BIKE_ROAD_CLEARANCE:
					midspan_crossings += 1
					break
			for station: Dictionary in stations:
				var at: Vector2 = station["pos"]
				if terrain._road_lateral_distance(at.x, at.y, BikePaths.BIKE_ROAD_CLEARANCE) \
						< BikePaths.BIKE_ROAD_CLEARANCE:
					road_stations += 1
			var last: Vector2 = stations[-1]["pos"]
			var ends_at_anchor: bool = last == (anchors[int(edge["a"])]["pos"] as Vector2) \
					or last == (anchors[int(edge["b"])]["pos"] as Vector2)
			# The rect edge, measured with one station's slack: the walk stops at the
			# LAST station outside the rect, so the terminal one stands up to a stride
			# short of the boundary it was stopped by.
			var ends_at_rect: bool = terrain.in_budapest(
					last.x + cos(float(stations[-1]["heading"])) * BikePaths.BIKE_STATION_SPACING,
					last.y + sin(float(stations[-1]["heading"])) * BikePaths.BIKE_STATION_SPACING)
			if ends_at_anchor:
				at_anchor += 1
			elif ends_at_rect:
				at_rect += 1
			else:
				_fail("seed %d trunk %d ends at %s, which is neither of its anchors (%s, %s) "
						% [seed_value, edge_id, last, anchors[int(edge["a"])]["pos"],
						anchors[int(edge["b"])]["pos"]] + "nor Budapest's rect edge. A trunk "
						+ "that stops in open field is exactly the defect this epic exists to "
						+ "remove")
		terrain.free()
	if checked == 0:
		_fail("check 3b found no trunk at all across %d seeds, so 'a trunk never ends in "
				% SEEDS.size() + "open field' was asserted of nothing")
	# THE ROAD STILL REFUSES A TRUNK MID-SPAN, and that number is
	# `godot-test1-pnvb.4`'s case. The road is exempt only within
	# `TRUNK_APPROACH_RADIUS` of the trunk's OWN anchors — the gate sits dead centre
	# in the swath, so without that exemption every edge incident on it is abandoned
	# and the epic's headline ("get to Budapest along them") is unreachable. What
	# the exemption does NOT do any more is let paint onto the swath: the road is
	# inside `trunk_keep_out`, so T5's box-and-footprint sweep is what asserts no
	# strip ever lies under a coin. This half only measures that the refusal is
	# still alive at all.
	if int(reasons.get("road", 0)) == 0 and midspan_crossings == 0:
		_fail("check 3b: not one edge across %d seeds was abandoned for the coin road, so "
				% SEEDS.size() + "the mid-span refusal was never seen to fire. "
				+ "`godot-test1-pnvb.4` owns that crossing and this number is its case, so "
				+ "a zero here means the refusal never fired AND no trunk crosses mid-span: "
				+ "the network stopped meeting the road at all (steep crossings walk through "
				+ "under child godot-test1-pnvb.4, so a refusal or a crossing must show)")
	# ...AND THE STATIONS THE EXEMPTION LET THROUGH ARE COUNTED, NOT ASSERTED, because
	# they are legitimate: a trunk to the gate walks the last 70 m along the corridor
	# and draws none of it. A ZERO here would mean the exemption is inert and T5's
	# road half is testing nothing, so that direction IS a failure.
	if road_stations == 0:
		_fail("check 3b: not one trunk station falls inside the coin road's swath, so the "
				+ "endpoint exemption never fired and T5's assertion that no PAINT lands "
				+ "there holds for free. The gate anchor sits dead centre in the swath, so "
				+ "a world with a trunk to the gate must produce some")
	print("bike trunks: the endpoint exemption let %d trunk stations into the coin road's "
			% road_stations + "swath, where T5 asserts no box and no footprint is drawn")
	if at_anchor == 0:
		_fail("check 3b found no trunk that ended at its own anchor, so the snap — the thing "
				+ "that makes the owner's intersections exact — was never once seen to happen")
	print("bike trunks: %d routes cross the coin road mid-span (walked through, paint gapped)"
			% midspan_crossings)
	print("bike trunks: %d routes end at their anchor, %d at Budapest's rect edge, over %d "
			% [at_anchor, at_rect, SEEDS.size()] + "seeds. Edges that produced NO trunk, by "
			+ "cause: %s — \"road\" is a shallow crossing refused under godot-test1-pnvb.4, \"city\" is edges "
			% reasons + "with both anchors inside the authored rect, and \"mountain\" is a "
			+ "massif the skirt could not clear")
	Sentinel.done("trunk_endings")


func _check_half_step_control(terrain_script: GDScript) -> void:
	"""
	THE CONTROL ON `segment_blocked` ITSELF, because the sweep above cannot be one.

	The segment half of check 3's prefix assertion holds over every path swept —
	and it would hold just as perfectly if `segment_blocked` were `return false`.
	Widening the sweep does not fix that: MEASURED over 778,924 dry-dry pairs a
	station-stride apart, across four seeds and the whole corridor, exactly 16 had
	a wet midpoint. That is one narrow band per ~49,000 pairs, or roughly one path
	in four thousand — so a sweep big enough to meet one by chance would cost more
	than every other check in this file put together, and a sweep that did NOT
	meet one would report green either way.

	So the predicate is controlled DIRECTLY instead: search the field for the
	shape it exists for — two dry points a station apart with water between them —
	and assert it answers true there. That turns "no drawn segment crosses water"
	from a claim the suite cannot fail into one whose predicate is known to work,
	and it is the reason `segment_blocked` cannot be quietly emptied out.

	A FIXED-SEED sample and not `randomize()`: this is a search over a
	deterministic field, so a fixed generator makes the same search every run and
	a failure is reproducible. It stops at the first hit, which at the measured
	rate is a few thousand samples in.
	"""
	var terrain: Node3D = _terrain(terrain_script, SEEDS[0], true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var found: int = 0
	var dry_pairs: int = 0
	for _i in HALF_STEP_SAMPLES:
		var p := Vector2(rng.randf_range(-2000.0, 2000.0), rng.randf_range(-1500.0, 1500.0))
		var heading: float = rng.randf() * TAU
		var q: Vector2 = p + Vector2(cos(heading), sin(heading)) * BikePaths.BIKE_STATION_SPACING
		if terrain.is_river_at(Vector3(p.x, 0.0, p.y)) \
				or terrain.is_river_at(Vector3(q.x, 0.0, q.y)):
			continue
		dry_pairs += 1
		if BikePaths.segment_blocked(terrain, p, q):
			found += 1
			break
	terrain.free()
	if dry_pairs == 0:
		_fail("check 3's half-step control found no dry pair at all in %d samples — it is "
				% HALF_STEP_SAMPLES + "not sampling the field")
	elif found == 0:
		_fail("check 3's half-step control swept %d dry station-strides on seed %d and found "
				% [dry_pairs, SEEDS[0]] + "no pair with water between its two dry ends, so "
				+ "`BikePaths.segment_blocked()` was never once seen to answer true and could "
				+ "be `return false` with this file still green. Raise HALF_STEP_SAMPLES (the "
				+ "measured rate is about one such pair per 49,000)")
	Sentinel.done("half_step_control")


# ============================================================================
# CHECK 4 — scarcity, form 2
# ============================================================================

func _check_scarcity(terrain_script: GDScript) -> void:
	"""
	Paths near the HQ corridor, and NONE beyond `SCARCITY_PLAIN_DISTANCE`.

	`scarcity_selfcheck` check 2's shape: the near field is the control, because
	"no path out there" is also what a rarity roll that never fires looks like.
	The far band's own `scarcity_at()` is asserted to be 0 as well, so the check
	cannot pass because the band was chosen too close to the city.
	"""
	for seed_value: int in SEEDS:
		var terrain: Node3D = _terrain(terrain_script, seed_value, true)
		var near: int = 0
		var far: int = 0
		var k_far: float = 0.0
		for ox in range(-SWEEP_HALF, SWEEP_HALF + 1):
			for oy in range(-SWEEP_HALF, SWEEP_HALF + 1):
				if not BikePaths.bike_path_at(terrain, Vector2i(ox, oy)).is_empty():
					near += 1
				var out := Vector2i(ox, FAR_CHUNK_Y + oy)
				k_far = maxf(k_far, terrain.scarcity_at(terrain.chunk_to_world(out)))
				if not BikePaths.bike_path_at(terrain, out).is_empty():
					far += 1
		if near == 0:
			_fail("seed %d: not one path in the %dx%d of origins around the corridor, where "
					% [seed_value, SWEEP_HALF * 2 + 1, SWEEP_HALF * 2 + 1]
					+ "scarcity is 1 — the rarity roll never fires and the far half of this "
					+ "check passes for the wrong reason")
		if k_far > 0.0:
			_fail("seed %d: check 4's far band reaches scarcity %.3f, so it is not past "
					% [seed_value, k_far] + "SCARCITY_PLAIN_DISTANCE at all — raise "
					+ "FAR_CHUNK_Y")
		elif far > 0:
			_fail("seed %d: %d paths stand beyond SCARCITY_PLAIN_DISTANCE, where "
					% [seed_value, far] + "scarcity_at() is 0 — the bike paths are exempting "
					+ "themselves from the one rule every biome shares")
		terrain.free()
	# --- AND THE OTHER HALF OF THE RULE, which tier 1 splits in two.
	_check_trunk_scarcity_split(terrain_script)
	_measure_trunks_below_k1(terrain_script)
	Sentinel.done("scarcity")


func _check_trunk_scarcity_split(terrain_script: GDScript) -> void:
	"""
	CHECK 4 EXTENDED / T3a — THE SCARCITY SPLIT, BOTH HALVES, UNCONDITIONALLY.
	THE ROUTE IS TOPOLOGY AND EXEMPT; THE FURNITURE IS CONTENT AND THINNED.

	WHY THIS DRIVES THE CODE INSTEAD OF HUNTING FOR A SEED, and it is the whole
	design of the check. Owner Ruling 3 made trunk endpoints corridor-only, and k
	is exactly 1 across the corridor — so THERE MAY BE NO TRUNK PAST 3 km ON ANY
	SEED, and a check that swept for one would find nothing, assert nothing and
	pass. That is precisely the failure this epic's second build lesson is about.
	So a SYNTHETIC trunk is pushed into the shipped memo at a site whose k is
	MEASURED to be 0, and the SHIPPED `spawn_bike_path_in_chunk` is run over it:
	both code paths execute, every time, on every seed, whatever the world holds.

	TWO SITES AND BOTH HALVES AT EACH:
	  * k = 0: the strip IS drawn (the route is exempt) and NOT ONE POLE is (the
	    furniture is on form 3).
	  * k = 1, the control: the same synthetic trunk carries poles. Without it,
	    "no poles out there" is also what a pole builder that never runs looks
	    like — and that is the near-corridor half the bead asks for, which is now
	    the common case.
	Each site's own `scarcity_at()` is asserted too, so neither half can pass
	because the chunk was mis-chosen.

	AN EXEMPTION DELETED BECAUSE IT LOOKED UNUSED IS THE BUG. This check is what
	stands between the next author and that deletion: remove the route exemption
	and the far strip count goes to zero; remove the furniture's form-3 roll and
	the far pole count does not.
	"""
	var terrain: Node3D = _terrain(terrain_script, SEEDS[0], true)
	var waypoints: Array[Dictionary] = terrain.waypoint_sites()
	var far_k: float = terrain.scarcity_at(terrain.chunk_to_world(T3A_FAR_CHUNK))
	if far_k != 0.0:
		_fail("T3a's far site %s has scarcity %.3f, not 0 — the exemption half of this "
				% [T3A_FAR_CHUNK, far_k] + "check would be measuring the ordinary case. "
				+ "Move T3A_FAR_CHUNK further out")
	# THE CONTROL SITE, SEARCHED — AND SCREENED ON WHAT IT IS ABOUT TO ASSERT, which
	# is a POLE and not a drawable segment. Those are different predicates: a pole
	# additionally needs a segment at a `BIKE_POLE_STRIDE` index, a free footprint,
	# and a pole SITE (1.65 m to the side of the strip) outside every keep-out — and
	# `trunk_keep_out` now carries the coin road's swath. So a chunk merely clipped
	# by the road or by a circle can keep a drawable segment, pass a screen written
	# on segments, and still stand no pole — failing the control for a reason with
	# nothing to do with scarcity, which is the exact failure the search replaced a
	# typed `Vector2i(3, 0)` to remove. Screening on the pole count closes it rather
	# than narrowing it. See `T3A_NEAR_BAND_X`.
	var near_chunk := Vector2i(1 << 30, 1 << 30)
	for bx: int in T3A_NEAR_BAND_X:
		for by: int in T3A_NEAR_BAND_Y:
			var cand := Vector2i(bx, by)
			if terrain.scarcity_at(terrain.chunk_to_world(cand)) != 1.0:
				continue
			if _synthetic_poles(terrain, cand) == 0:
				continue
			near_chunk = cand
			break
		if near_chunk.x != 1 << 30:
			break
	if near_chunk.x == 1 << 30:
		_fail("T3a found no chunk in its search band that is at k = 1 AND stands a pole on "
				+ "a synthetic trunk, so the control half — 'a trunk in the corridor DOES "
				+ "carry poles' — could not be made at all. Widen T3A_NEAR_BAND_X / _Y")
		terrain.free()
		Sentinel.done("trunk_scarcity_split")
		return
	for chunk_pos: Vector2i in [T3A_FAR_CHUNK, near_chunk]:
		var k: float = terrain.scarcity_at(terrain.chunk_to_world(chunk_pos))
		var stations: Array[Dictionary] = _synthetic_trunk(terrain, chunk_pos)
		# THE SHIPPED MEMO, overwritten with one route. `spawn_bike_path_in_chunk`
		# reads it through `BikePaths.trunks()`, so what runs below is the production
		# emission path in full — the bounding-box lookup, the k read at the chunk
		# centre, the midpoint rule and both halves of the split.
		# TYPED, and it has to be: `BikePaths.trunks()` is declared
		# `-> Array[Dictionary]` and returns this value straight out of the memo, so
		# an untyped Array literal here raises at the RETURN — which aborts that
		# function, hands the spawner an empty table and leaves every assertion
		# below failing for a reason that has nothing to do with scarcity.
		var only: Array[Dictionary] = [{
			"id": SYNTHETIC_EDGE_ID, "a": -1, "b": -2, "stations": stations,
			"box": BikePaths._trunk_box(stations),
			"from": stations[0]["pos"], "to": stations[-1]["pos"],
			"bridges": [],   # child `.3`: a synthetic route crosses no water
		}]
		terrain._bike_trunk_cache["trunks"] = only
		var built: Dictionary = _spawn_bare(terrain, chunk_pos)
		var want: int = _dry_segments_in(terrain, stations, chunk_pos, waypoints)
		var strips: int = _strips_on(terrain, chunk_pos, built["batch"], stations)
		var poles: int = -1
		for row: Dictionary in (built["paths"] as Array[Dictionary]):
			if int(row["edge"]) == SYNTHETIC_EDGE_ID:
				poles = (row["poles"] as PackedInt32Array).size()
		if want == 0:
			_fail("T3a's synthetic trunk at %s owns no dry segment in that chunk, so "
					% chunk_pos + "neither half of the split was driven. Move the site off "
					+ "the water")
			continue
		if strips != want:
			_fail("T3a at %s (k = %.2f): the trunk owns %d dry segments there and %d strip "
					% [chunk_pos, k, want, strips] + "boxes were drawn. THE ROUTE IS "
					+ "TOPOLOGY AND IS EXEMPT FROM SCARCITY — a trunk far out is bare paint, "
					+ "never no paint, or the network disconnects wherever the world thins")
		if poles < 0:
			_fail("T3a at %s: the synthetic trunk drew geometry but left no marker, so its "
					% chunk_pos + "pole count could not be read at all")
		elif k == 0.0 and poles != 0:
			_fail("T3a at %s: k is 0 and the trunk still stands %d poles. THE FURNITURE IS "
					% [chunk_pos, poles] + "CONTENT AND IS NOT EXEMPT — every pole goes "
					+ "through terrain._scarcity_keep() on form 3, a post-draw continue "
					+ "immediately before its first create_box")
		elif k == 1.0 and poles == 0:
			_fail("T3a's control at %s: k is 1 and the trunk carries no pole at all, so the "
					% chunk_pos + "far site's zero says nothing — a pole builder that never "
					+ "runs looks exactly like a thinning that always fires")
	terrain.free()
	Sentinel.done("trunk_scarcity_split")


func _measure_trunks_below_k1(terrain_script: GDScript) -> void:
	"""
	T3b — A MEASUREMENT, NEVER A PASS OR A FAIL. How often a REAL trunk leaves
	k = 1, printed including when the answer is zero.

	Owner Ruling 3 (corridor-only endpoints) means a trunk runs at k = 1 end to
	end almost always, so the exemption T3a proves correct is also nearly silent.
	*"The corridor filter means the exemption never fires on N seeds"* is a
	valuable finding and the number the next author needs — it is not a defect and
	it is not a reason to delete the rule. If it were asserted, a legitimate world
	would fail this file; if it were absent, nobody would ever learn the number.

	THE CASE WORTH HUNTING IS A TRUNK BOWING OUTSIDE THE CORRIDOR MID-SPAN — two
	anchors both at k = 1 joined by a route that wanders past the rect's Z edge —
	because that one really happens and is the only way the exemption fires today.
	It is counted separately from the station total for that reason.
	"""
	var seeds_swept: int = 0
	var trunks_seen: int = 0
	var trunks_below: int = 0
	var stations_below: int = 0
	var worst: float = 1.0
	for seed_value: int in T3B_SEEDS:
		var terrain: Node3D = _terrain(terrain_script, seed_value, true)
		seeds_swept += 1
		for trunk: Dictionary in BikePaths.trunks(terrain):
			trunks_seen += 1
			var dipped: bool = false
			for station: Dictionary in (trunk["stations"] as Array[Dictionary]):
				var at: Vector2 = station["pos"]
				var k: float = terrain.scarcity_at(Vector3(at.x, 0.0, at.y))
				if k < 1.0:
					stations_below += 1
					dipped = true
					worst = minf(worst, k)
			if dipped:
				trunks_below += 1
		terrain.free()
	print("bike trunks T3b (a MEASUREMENT, not an assertion): across %d seeds and %d "
			% [seeds_swept, trunks_seen] + "trunks, %d routes bow outside k = 1 mid-span, "
			% trunks_below + "over %d stations, the worst at k = %.3f. Owner Ruling 3 makes "
			% [stations_below, worst] + "trunk endpoints corridor-only, so a zero here is "
			+ "the expected finding and NOT a reason to delete the route exemption — T3a "
			+ "drives both halves of the split directly for exactly that reason")
	Sentinel.done("trunks_below_k1")


# ============================================================================
# CHECK 5 — CUBE only: no chunk grows a MultiMesh bucket
# ============================================================================

func _check_no_new_buckets(terrain_script: GDScript) -> void:
	"""
	A chunk carrying a path has exactly the `BlockMultiMesh_*` children it has
	without one.

	THE RULING, MADE UNFAILABLE. `batch_selfcheck` check 5 caps the draw calls per
	biome from a table its own sweep cannot reach this family with — it builds
	`spawn_objects_in_chunk` + `spawn_biome_content_in_chunk`, and a bike path is
	neither. So the guarantee that `KIND_CAP_BY_NAME` needs no row changed is
	asserted HERE, where the paths are: one new bucket would be +1 draw call on
	every PLAINS / SNOW / FOREST chunk that carries a strip, which is a great many
	more chunks than the eleven the waypoint disc is forgiven for.
	"""
	var on: Node3D = _terrain(terrain_script, SEEDS[0], true)
	var off: Node3D = _terrain(terrain_script, SEEDS[0], false)
	var compared: int = 0
	for x: int in AB_X:
		for y: int in AB_Y:
			var chunk_pos := Vector2i(x, y)
			on.create_chunk(chunk_pos)
			var chunk_on: Node = on.active_chunks[chunk_pos]
			if _markers(chunk_on).is_empty():
				continue
			off.create_chunk(chunk_pos)
			var chunk_off: Node = off.active_chunks[chunk_pos]
			compared += 1
			var buckets_on: Array = _multimesh_table(chunk_on).keys()
			var buckets_off: Array = _multimesh_table(chunk_off).keys()
			buckets_on.sort()
			buckets_off.sort()
			if buckets_on != buckets_off:
				_fail("chunk %s draws buckets %s with a bike path in it and %s without — a "
						% [chunk_pos, buckets_on, buckets_off]
						+ "bike path must be CUBEs and nothing else")
			if buckets_off.is_empty():
				_fail("chunk %s has no MultiMesh bucket at all with the paths off, so the "
						% chunk_pos + "comparison above cannot see a bucket being added")
	if compared == 0:
		_fail("check 5 found no chunk with a path in the A/B field — it asserted nothing")
	on.free()
	off.free()
	Sentinel.done("no_new_buckets")


# ============================================================================
# CHECK 6 — only the poles claim a footprint
# ============================================================================

func _check_footprints(terrain_script: GDScript) -> void:
	"""
	One `{climbable: false}` footprint per pole AND ONE PER RACK, and not one
	for the paint.

	The strip and the dashes are paint you walk over — `terrain_waypoints.gd`'s
	"no footprint, and why", the same ruling one family along — so the count of
	appended footprints must equal the poles the markers recorded PLUS the racks
	(bead `godot-test1-z2yv.3`: one footprint for the whole stand, not one per
	upright), never the count of boxes. A post is NON-CLIMBABLE and its `top` is
	its full height: a mast has no top to stand on (`terrain_biomes.gd`'s street
	furniture) — and a stand is no more climbable than a post.
	"""
	var terrain: Node3D = _terrain(terrain_script, SEEDS[0], true)
	var poles_seen: int = 0
	var racks_seen: int = 0
	var paint_seen: int = 0
	for ox in range(-SWEEP_HALF, SWEEP_HALF + 1):
		for oy in range(-SWEEP_HALF, SWEEP_HALF + 1):
			var chunk_pos := Vector2i(ox, oy)
			var built: Dictionary = _spawn_bare(terrain, chunk_pos)
			var batch: Array = built["batch"]
			var obstacles: Array = built["obstacles"]
			var poles: int = built["poles"]
			var racks: int = built["racks"]
			poles_seen += poles
			racks_seen += racks
			paint_seen += batch.size() - poles - racks * (1 + BikePaths.RACK_UPRIGHT_COUNT)
			if obstacles.size() != poles + racks:
				_fail("chunk %s built %d boxes of which %d are poles and %d racks, and "
						% [chunk_pos, batch.size(), poles, racks] + "appended %d "
						% obstacles.size() + "footprints — it must be exactly one per "
						+ "pole, one per rack, and none for the strip or the dashes")
				continue
			for entry_v: Variant in obstacles:
				var entry: Dictionary = entry_v
				if bool(entry["climbable"]):
					_fail("chunk %s appended a CLIMBABLE footprint — neither a post nor "
							% chunk_pos + "a stand has a top to stand on")
					continue
				if is_equal_approx(float(entry["top"]), BikePaths.BIKE_POLE_HEIGHT):
					if not is_equal_approx(float(entry["radius"]), BikePaths.BIKE_POLE_RADIUS):
						_fail("chunk %s: a pole footprint claims radius %.2f, not "
								% [chunk_pos, float(entry["radius"])]
								+ "BIKE_POLE_RADIUS %.2f" % BikePaths.BIKE_POLE_RADIUS)
				elif is_equal_approx(float(entry["top"]), BikePaths.RACK_TOP):
					if not is_equal_approx(float(entry["radius"]), BikePaths.RACK_RADIUS):
						_fail("chunk %s: a rack footprint claims radius %.2f, not "
								% [chunk_pos, float(entry["radius"])] + "RACK_RADIUS %.2f"
								% BikePaths.RACK_RADIUS)
				else:
					_fail("chunk %s: a footprint with top %.2f, which is neither the "
							% [chunk_pos, float(entry["top"])] + "post's height nor the "
							+ "rack's — footprints come one per pole and one per rack")
	if poles_seen == 0:
		_fail("check 6 swept %dx%d chunks and found no pole at all, so 'one footprint per "
				% [SWEEP_HALF * 2 + 1, SWEEP_HALF * 2 + 1] + "pole' was vacuous")
	if racks_seen == 0:
		_fail("check 6 swept %dx%d chunks and found no rack at all, so 'one footprint per "
				% [SWEEP_HALF * 2 + 1, SWEEP_HALF * 2 + 1] + "rack' was vacuous")
	if paint_seen == 0:
		_fail("check 6 found poles but no strip or dash boxes, so 'and none for the paint' "
				+ "was vacuous")
	terrain.free()
	Sentinel.done("footprints")


# ============================================================================
# CHECKS 7 + 8 — one top per pole, all five kinds drawn, and all of them CUBEs
# ============================================================================

func _check_tops_and_cubes(terrain_script: GDScript) -> void:
	"""
	Every pole carries exactly one top; every kind the table can produce is really
	produced; and every box this family emits is still a CUBE.

	ONE SWEEP FOR BOTH, because both are statements about the same boxes and the
	sweep is the expensive part.

	WHY "ALL FIVE KINDS APPEAR" IS THE ASSERTION AND NOT A NICETY: the top is a HASH
	DISPATCH into a fixed table, and the two ways that breaks are a fold that cannot
	reach part of the table (a negative modulo, a mask too narrow, a `% 4` left over
	from a four-row version) and a table row nothing indexes. Both leave a kind that
	can never be drawn — a dead branch that no other check in this file, and nothing
	in the game, would ever notice. Counting the histogram over three seeds is the
	control that catches it.

	THE CUBE HALF is `batch_selfcheck` check 5's `KIND_CAP_BY_NAME` ruling, asserted
	on the entries themselves. Check 5 above compares a chunk's BUCKETS with the
	paths on and off, which is the same statement from the outside; this one also
	fails if a sign plate is emitted as a CYLINDER in a chunk that already had a
	CYLINDER bucket from its own biome content — the case the bucket comparison
	cannot see, and exactly the mast the epic refused.
	"""
	var histogram: Dictionary = {}
	var poles_seen: int = 0
	var boxes_seen: int = 0
	for seed_value: int in SEEDS:
		var terrain: Node3D = _terrain(terrain_script, seed_value, true)
		for ox in range(-TOP_SWEEP_HALF, TOP_SWEEP_HALF + 1):
			for oy in range(-TOP_SWEEP_HALF, TOP_SWEEP_HALF + 1):
				var chunk_pos := Vector2i(ox, oy)
				var built: Dictionary = _spawn_bare(terrain, chunk_pos)
				for entry_v: Variant in (built["batch"] as Array):
					boxes_seen += 1
					var kind: int = (entry_v as Dictionary).get("kind", ChunkBatch.BoxKind.CUBE)
					if kind != ChunkBatch.BoxKind.CUBE:
						_fail("seed %d chunk %s emitted a box of kind %s — this family is CUBE "
								% [seed_value, chunk_pos, ChunkBatch.BoxKind.find_key(kind)]
								+ "only, so that `KIND_CAP_BY_NAME` in batch_selfcheck needs no "
								+ "row changed and a path costs no chunk a second draw call")
						break
				for row: Dictionary in (built["paths"] as Array[Dictionary]):
					var poles: PackedInt32Array = row["poles"]
					var tops: PackedInt32Array = row["tops"]
					var signals: PackedInt32Array = row["signals"]
					poles_seen += poles.size()
					if tops.size() != poles.size():
						_fail("seed %d chunk %s origin %s built %d poles but recorded %d tops — "
								% [seed_value, chunk_pos, row["origin"], poles.size(), tops.size()]
								+ "every pole carries exactly one sign or one head, and a pole "
								+ "skipped for a footprint must skip its top with it")
					var heads: int = 0
					for top: int in tops:
						if top != BikePaths.POLE_TOP_SIGNAL \
								and (top < 0 or top >= BikePaths.SIGN_KINDS.size()):
							_fail("seed %d chunk %s: a pole carries top %d, which is neither a "
									% [seed_value, chunk_pos, top] + "SIGN_KINDS index nor "
									+ "POLE_TOP_SIGNAL — the dispatch fold is out of range")
							continue
						if top == BikePaths.POLE_TOP_SIGNAL:
							heads += 1
						histogram[top] = int(histogram.get(top, 0)) + 1
					if signals.size() != heads:
						_fail("seed %d chunk %s origin %s dispatched %d signal heads but recorded "
								% [seed_value, chunk_pos, row["origin"], heads]
								+ "%d lamp indices — the cycle would drive a head that is not "
								% signals.size() + "there, or leave one dark forever")
		terrain.free()

	if poles_seen == 0:
		_fail("checks 7-8 swept %d seeds x %dx%d chunks and found no pole at all, so every "
				% [SEEDS.size(), TOP_SWEEP_HALF * 2 + 1, TOP_SWEEP_HALF * 2 + 1]
				+ "assertion about what stands on one was vacuous")
	if boxes_seen == 0:
		_fail("checks 7-8 found no box at all in the sweep, so 'CUBE only' asserted nothing")
	for kind in BikePaths.SIGN_KINDS.size():
		if not histogram.has(kind):
			_fail("sign kind %d (`%s`) was never once drawn in %d seeds x %dx%d chunks over "
					% [kind, _sign_name(kind), SEEDS.size(), TOP_SWEEP_HALF * 2 + 1,
					TOP_SWEEP_HALF * 2 + 1] + "%d poles — it is a dead branch, which is what a "
					% poles_seen + "dispatch fold that cannot reach the whole of POLE_TOPS looks "
					+ "like from the outside")
	if not histogram.has(BikePaths.POLE_TOP_SIGNAL):
		_fail("not one traffic head was dispatched over %d poles — the cycling signal, which "
				% poles_seen + "is half of this bead, is never built and check 9 has nothing "
				+ "to read")
	Sentinel.done("tops_and_cubes")


func _sign_name(kind: int) -> String:
	## The authored sign kinds in `SIGN_KINDS` order, for a message a reader can act
	## on. A plain lookup table: the family stores no names (a sign carries no text,
	## which is the whole ruling), so this is the one place they are written down.
	return ["ROUTE", "YIELD", "STOP", "CROSSING"][kind] if kind >= 0 and kind < 4 \
			else "kind %d" % kind


# ============================================================================
# CHECK 7c — a sign stands CLEAR of its own post
# ============================================================================

func _check_sign_clearance(terrain_script: GDScript) -> void:
	"""
	EVERY BOX A POLE CARRIES THAT STANDS WITHIN THE POST'S OWN HEIGHT MUST BE IN
	FRONT OF THE POST, measured off the drawn boxes.

	This is round 1's major, turned into an assertion. A sign plate is
	`SIGN_PLATE_DEPTH` = 0.05 thick and the post it hangs on is `BIKE_POLE_WIDTH` =
	0.16 square, so a plate centred on the post's own XZ is INSIDE it: the sign reads
	with a grey bar straight down its middle, and CROSSING's centre bar — one of its
	three — is swallowed whole. NOTHING ELSE IN THIS FILE COULD SEE THAT. Checks 7
	and 8 count tops and box kinds, check 9 pins indices, check 1 compares a build to
	a build, and the style shot that would have shown it is deferred. It is the same
	shape as `.1`'s 25 m bug: every count was right and the geometry was wrong.

	MEASURED OFF THE TRANSFORMS AND NOT OFF THE CONSTANTS. A batch entry's own basis
	carries its facing and its size (`Basis(UP, yaw).scaled_local(dims)`, so
	`basis.x` is the approach axis scaled by the box's depth), so the post and the
	sign are each read from what was actually emitted — a check written against
	`SIGN_STANDOFF` would agree with any value of it, including zero.

	ONLY BOXES INSIDE THE POST'S HEIGHT are held to it: the traffic head sits ON TOP
	of the post (its lenses are above `BIKE_POLE_HEIGHT`), so it is not occluded by
	anything and is exempt by construction rather than by exception.

	ITS CONTROL is the predicate applied to the POST ITSELF, which must report a
	failure — a post is not clear of a post. Without it "every sign is clear" would
	also be what a predicate that can never fail prints.
	"""
	var terrain: Node3D = _terrain(terrain_script, SEEDS[0], true)
	# THE BOUND HAS TO COVER THE AUTHORED TABLES, and it is asserted rather than
	# trusted because the failure is silent: a top of five boxes would have its fifth
	# walk out of the run below unmeasured, `signs_seen` would still be non-zero, and
	# a pictogram built inside the post — round 1's major — would ship green. A fourth
	# pip on any `SIGN_KINDS` row is all it takes.
	var widest: int = 4  # the traffic head: one head box plus three lenses.
	for row: Dictionary in BikePaths.SIGN_KINDS:
		widest = maxi(widest, 1 + (row["pips"] as Array).size())
	if TOP_BOXES_MAX < widest:
		_fail("check 7c reads at most %d boxes as a pole's top, but the authored tables now "
				% TOP_BOXES_MAX + "build one of %d — the boxes past the bound would never be "
				% widest + "measured against the post, which is the one thing this check exists "
				+ "to see. Raise TOP_BOXES_MAX")
	var posts_seen: int = 0
	var signs_seen: int = 0
	var control_fired: bool = false
	for ox in range(-SWEEP_HALF, SWEEP_HALF + 1):
		for oy in range(-SWEEP_HALF, SWEEP_HALF + 1):
			var chunk_pos := Vector2i(ox, oy)
			var built: Dictionary = _spawn_bare(terrain, chunk_pos)
			var batch: Array = built["batch"]
			for row: Dictionary in (built["paths"] as Array[Dictionary]):
				for p: int in (row["poles"] as PackedInt32Array):
					if p < 0 or p >= batch.size():
						_fail("chunk %s: the marker records a pole at CUBE instance %d and the "
								% [chunk_pos, p] + "chunk's own batch holds %d boxes"
								% batch.size())
						continue
					var post: Transform3D = (batch[p] as Dictionary)["transform"]
					# THE INDEX IS THE TIE, and asserting it is free: `_spawn_bare` starts
					# from an EMPTY batch and this family emits CUBEs only, so a pole's
					# CUBE-bucket index IS its batch index here. If that ever stops being
					# true the entry at `p` is not a post and this says so, rather than
					# quietly measuring the wrong box.
					if not _is_post(post):
						_fail("chunk %s: the marker records a pole at index %d, but the box "
								% [chunk_pos, p] + "there is not a post — the recorded index and "
								+ "the geometry have come apart")
						continue
					posts_seen += 1
					if not control_fired:
						# THE CONTROL: a post is not clear of itself.
						control_fired = true
						if _clearance_fault(post, post) == "":
							_fail("check 7c's clearance predicate calls the POST ITSELF clear of "
									+ "the post, so it cannot fail and 'every sign stands clear' "
									+ "is an assertion about nothing")
					# THE TOP IS THE CONTIGUOUS RUN AFTER THE POST — `_draw_path_share`
					# emits the pole and then its one top, nothing between. Bounding it by
					# `TOP_BOXES_MAX` and stopping at the next post or at ground level is
					# what keeps a CROSSING path's strip out: two bike paths may cross, and
					# a filter that took every box within a radius of the post would read a
					# foreign 5 m strip box as a sign buried in it and fail a correct world.
					for k in range(p + 1, mini(p + 1 + TOP_BOXES_MAX, batch.size())):
						var box: Transform3D = (batch[k] as Dictionary)["transform"]
						if _is_post(box) or box.origin.y < GROUND_BAND:
							break
						# Above the post's own top nothing can be occluded by it — that is
						# where the traffic head lives, exempt by construction.
						if box.origin.y + box.basis.y.length() * 0.5 > BikePaths.BIKE_POLE_HEIGHT:
							continue
						signs_seen += 1
						var fault: String = _clearance_fault(post, box)
						if fault != "":
							_fail("chunk %s: box %d, which the pole at index %d carries, %s. A "
									% [chunk_pos, k, p, fault] + "plate or a pictogram inside the "
									+ "post reads with a grey bar down its middle, and a centred "
									+ "pip does not read at all — see `SIGN_STANDOFF`")
	terrain.free()
	if posts_seen == 0:
		_fail("check 7c swept %dx%d chunks and found no post at all, so it measured nothing"
				% [SWEEP_HALF * 2 + 1, SWEEP_HALF * 2 + 1])
	if signs_seen == 0:
		_fail("check 7c found %d posts and not one box standing on any of them within the "
				% posts_seen + "post's own height — the sign geometry it exists to measure was "
				+ "never looked at (did every plate move above BIKE_POLE_HEIGHT, or is "
				+ "TOP_BOXES_MAX now too small to reach one?)")
	Sentinel.done("sign_clearance")


func _is_post(t: Transform3D) -> bool:
	## A pole post, picked out by its own dimensions and its centre height — no meta
	## and no index, the same way `_strip_positions` finds a strip.
	return is_equal_approx(t.origin.y, BikePaths.BIKE_POLE_HEIGHT * 0.5) \
			and is_equal_approx(t.basis.y.length(), BikePaths.BIKE_POLE_HEIGHT) \
			and is_equal_approx(t.basis.x.length(), BikePaths.BIKE_POLE_WIDTH)


func _clearance_fault(post: Transform3D, box: Transform3D) -> String:
	"""
	Does `box` stand in front of `post` along the post's own approach axis?

	@return: "" when it does, otherwise the overlap in words.

	`basis.x` is the box's local +X scaled by its depth, and for this family local +X
	is the direction of travel (`yaw == -head`), so its normalised form is the axis
	and its length is the depth. A sign is built on the -X side, so "in front" is a
	NEGATIVE offset along that axis, and the near face must clear the post's own half
	width.
	"""
	var axis: Vector3 = post.basis.x.normalized()
	var along: float = (box.origin - post.origin).dot(axis)
	var depth: float = box.basis.x.length()
	var near: float = -along - depth * 0.5
	if near >= BikePaths.BIKE_POLE_WIDTH * 0.5 - CLEARANCE_TOLERANCE:
		return ""
	return "stands %.3f m in front of the post's centre and is %.3f m deep, so its near " \
			% [-along, depth] + "face is %.3f m out where the post's own is %.3f m" \
			% [near, BikePaths.BIKE_POLE_WIDTH * 0.5]


# ============================================================================
# CHECK 9 — the recorded CUBE-bucket index really is that lamp
# ============================================================================

func _check_lamp_indices(terrain_script: GDScript) -> void:
	"""
	THE CHECK THIS BEAD EXISTS FOR.

	`ChunkBatch._build_block_multimesh` buckets the batch BY KIND and emits in ENUM
	order, so a lamp's MultiMesh instance index is its position among the CUBE
	ENTRIES ONLY — never its index in `block_batch`. The spawner records the former,
	and an index one out still addresses a real box: the head above it, the lens
	below it, or some other family's block entirely. Nothing in the game would ever
	report that; one lamp would simply light the wrong thing.

	WHAT A HEADLESS CHECK CAN AND CANNOT SEE, measured before this check was written
	because the obvious form of it is a mirage: under the dummy rendering server
	`--headless` runs on, MULTIMESH INSTANCE DATA IS WRITE-ONLY.
	`get_instance_color()` returns opaque black and `get_instance_transform()` the
	identity for every instance of every MultiMesh, and `buffer` comes back empty
	(measured on a two-instance MultiMesh built by hand, in and out of the tree).
	So "read the colour back at the recorded index" cannot be the assertion here —
	it would read black at every index, pass with any base, and look like coverage.
	`instance_count` IS real, and so is everything in `block_batch`, and this check
	is built out of those two.

	  (a) THE INDEX, END TO END AND WITHOUT A SECOND COPY OF THE BUCKETING RULE. Run
	      the shipped spawner into a batch that already holds NON-CUBE entries (the
	      masts, rocks and trees a real chunk has by the time this family runs), find
	      the three lamp boxes in that batch by their own colour, and ask the SHIPPED
	      `ChunkBatch._build_block_multimesh` where each of them lands: built on the
	      batch TRUNCATED at a lamp, the CUBE bucket's `instance_count` IS that
	      lamp's CUBE-bucket index. That number must equal what the marker recorded.
	  (b) THE CONTROL, permanent and not a mutation someone once ran: the lamp's
	      BATCH index must differ from its CUBE-bucket index. If they were equal the
	      whole check would pass just as well on a spawner that recorded the batch
	      index — the exact bug it exists for — so a fixture that stopped containing
	      non-CUBE entries has to fail loudly rather than quietly assert nothing.
	  (c) THE LIVE PLUMBING, on a REAL chunk built through `create_chunk`. Fire the
	      head's own Timer through its `timeout` signal and assert the phase
	      ADVANCED — which it can only do if the connection reached
	      `BikePaths.tick_signal`, if `signal_multimesh()` found the chunk's CUBE
	      bucket from the Timer, and if `base + 3` really is inside that bucket's
	      `instance_count`; every one of those failures returns early and leaves the
	      phase alone. Its control is a Timer whose `lamp0` is deliberately out of
	      range, which must NOT advance.
	"""
	var terrain: Node3D = _terrain(terrain_script, SEEDS[0], true)

	# THE SWEEP, and it collects two different things at once. The bare spawner below
	# is handed an EMPTY `obstacles`, so no pole is skipped and every chunk that CAN
	# carry a head does; in a real chunk a pole whose site is already taken is skipped
	# and takes its head with it. So a hit here is a candidate for (c) and nothing
	# more — while its batch, a real run of the shipped spawner, is what (a) needs.
	var candidates: Array[Vector2i] = []
	var probe := Vector2i(0, 0)
	var batch: Array = []
	var bases := PackedInt32Array()
	for ox in range(-SWEEP_HALF, SWEEP_HALF + 1):
		if candidates.size() >= LAMP_CANDIDATES:
			break
		for oy in range(-SWEEP_HALF, SWEEP_HALF + 1):
			var pos := Vector2i(ox, oy)
			var trial: Array = _prefix_batch()
			var obstacles: Array = []
			var body := StaticBody3D.new()
			var chunk := MeshInstance3D.new()
			BikePaths.spawn_bike_path_in_chunk(terrain, pos, chunk, obstacles, trial, body)
			var here := PackedInt32Array()
			for marker: Node in _markers(chunk):
				here.append_array(marker.get_meta("signals") as PackedInt32Array)
			chunk.free()
			body.free()
			if here.is_empty():
				continue
			candidates.append(pos)
			if batch.is_empty():
				probe = pos
				batch = trial
				bases = here
			if candidates.size() >= LAMP_CANDIDATES:
				break
	if bases.is_empty():
		_fail("check 9 swept %dx%d chunks on seed %d and found no traffic head at all, so the "
				% [SWEEP_HALF * 2 + 1, SWEEP_HALF * 2 + 1, SEEDS[0]] + "one assertion in this "
				+ "file that ties a recorded MultiMesh index to the lamp it claims to address "
				+ "never fired")
		terrain.free()
		Sentinel.done("lamp_indices")
		return

	# --- (a) THE INDEX. Find the lenses in the batch by their own colour — the three
	# DARKENED lamp colours are the only boxes in the world drawn in them — and ask
	# the shipped bucketing function where each one lands.
	var dark := PackedColorArray()
	for j in 3:
		dark.append(BikePaths.lamp_color(terrain, j, false).srgb_to_linear())
	var lamp_rows: Array[Array] = []
	for t in batch.size():
		var c: Color = (batch[t] as Dictionary)["color"]
		for j in 3:
			if _same_color(c, dark[j]):
				lamp_rows.append([t, j])
				break
	if lamp_rows.size() != bases.size() * 3:
		_fail("chunk %s recorded %d traffic heads but its batch holds %d boxes painted in the "
				% [probe, bases.size(), lamp_rows.size()] + "three lens colours — a head is "
				+ "three lenses, and `signals` must carry exactly one entry per head")
	else:
		for n in bases.size():
			for j in 3:
				var row: Array = lamp_rows[n * 3 + j]
				if int(row[1]) != j:
					_fail("chunk %s head %d: the lenses are emitted out of order — `SIGNAL_LIT` "
							% [probe, n] + "and the cycle both assume the stack is built "
							+ "top-down red, amber, green")
					continue
				var want: int = bases[n] + j
				var got: int = _cube_index_of(batch, int(row[0]))
				if got != want:
					_fail("chunk %s head %d: the marker records its %s lens at CUBE instance %d, "
							% [probe, n, ["red", "amber", "green"][j], want]
							+ "but that box is batch entry %d, which the shipped "
							% int(row[0]) + "`_build_block_multimesh` puts at CUBE instance %d. "
							% got + "A lamp's instance index is its position among the CUBE "
							+ "ENTRIES ONLY (the batch is bucketed BY KIND and emitted in ENUM "
							+ "order) — recording a `block_batch` index, or forgetting the head "
							+ "box that precedes the lenses, is exactly what this looks like")
		# --- (b) THE CONTROL. If a lens's batch index and its CUBE-bucket index were
		# the same number, every assertion above would hold just as well for a spawner
		# that recorded the wrong one, and this check would be decoration.
		var first: Array = lamp_rows[0]
		if int(first[0]) == bases[0]:
			_fail("check 9's fixture has stopped containing non-CUBE boxes: the first lens is "
					+ "batch entry %d AND CUBE instance %d, so the assertions above cannot tell "
					% [int(first[0]), bases[0]] + "a batch index from a bucket index — which is "
					+ "the only bug they exist to catch. Restore PREFIX_KINDS")
		if bases[0] <= 0:
			_fail("check 9's fixture put the first lens at CUBE instance %d, so the offset this "
					% bases[0] + "check is about is zero and any bookkeeping would pass")

	# --- (c) THE LIVE PLUMBING, on a chunk built through the shipped `create_chunk`.
	var timer: Timer = null
	var live := Vector2i(0, 0)
	var instances: int = 0
	for candidate: Vector2i in candidates:
		terrain.create_chunk(candidate)
		var chunk_node: Node = terrain.active_chunks[candidate]
		var bucket: Node = chunk_node.get_node_or_null(CUBE_BUCKET)
		timer = _signal_timer(chunk_node)
		if timer == null or bucket == null:
			timer = null
			continue
		live = candidate
		instances = (bucket as MultiMeshInstance3D).multimesh.instance_count
		break
	if timer == null:
		_fail("check 9 built %d chunks that carry a traffic head through the bare spawner and "
				% candidates.size() + "not one of them grew a head and a CUBE bucket for real, "
				+ "so the Timer, its connection and the node walk from Timer to bucket are all "
				+ "untested. Raise LAMP_CANDIDATES, or find out why every candidate pole is "
				+ "being skipped")
		terrain.free()
		Sentinel.done("lamp_indices")
		return
	var live_base: int = int(timer.get_meta("lamp0"))
	if live_base + 3 > instances:
		_fail("chunk %s: the head's lenses are recorded at CUBE instances [%d, %d) and the built "
				% [live, live_base, live_base + 3] + "bucket holds %d — the cycle would write "
				% instances + "off the end of the buffer and silently do nothing forever")
	var phase: int = int(timer.get_meta("phase"))
	for step in 2:
		# A TICK THROUGH THE TIMER'S OWN SIGNAL, so the `connect` at plant time is
		# under test along with everything else. The phase can only advance if the
		# callable arrived, if `signal_multimesh()` walked Timer -> marker -> chunk ->
		# bucket, and if `base + 3` is inside that bucket: every other outcome returns
		# early and leaves the phase alone.
		timer.timeout.emit()
		var stepped: int = int(timer.get_meta("phase"))
		if stepped != (phase + 1) % 3:
			_fail("chunk %s: tick %d left the head at phase %d, not %d — either the Timer's "
					% [live, step, stepped, (phase + 1) % 3] + "`timeout` never reaches "
					+ "`BikePaths.tick_signal`, or the tick bailed out because it could not walk "
					+ "from the Timer to the chunk's '%s', or because the recorded index is "
					% CUBE_BUCKET + "outside that bucket. The lamps would never change")
			break
		phase = stepped
	# THE CONTROL ON THAT ASSERTION: the phase advances only where the write is really
	# addressable, so an index off the end must leave it exactly where it was. Without
	# this, "the phase advanced" would also be satisfied by a tick that stepped first
	# and checked afterwards — which is a tick that writes into a neighbour's boxes.
	timer.set_meta("lamp0", instances)
	var held: int = int(timer.get_meta("phase"))
	timer.timeout.emit()
	if int(timer.get_meta("phase")) != held:
		_fail("chunk %s: a head whose lenses are recorded at CUBE instance %d, one past the end "
				% [live, instances] + "of a %d-instance bucket, still stepped its phase — so the "
				% instances + "tick writes before it checks, and 'the phase advanced' says "
				+ "nothing about whether the write landed anywhere")
	terrain.free()
	Sentinel.done("lamp_indices")


func _prefix_batch() -> Array:
	"""
	A stand-in for the boxes a real chunk already holds when this family runs.

	THE POINT IS THE NON-CUBES. `_build_block_multimesh` buckets by kind, so a batch
	of nothing but CUBEs gives every box a bucket index equal to its batch index, and
	check 9 could not then tell the two apart. A real chunk has masts, rocks, trees
	and wedged roofs in it by the time the bike paths are drawn; these seven entries
	are the cheapest thing with that shape, and check 9 (b) fails if they stop having
	it.
	"""
	var out: Array = []
	for i in PREFIX_KINDS.size():
		out.append({
			"transform": Transform3D(Basis(), Vector3(float(i), 0.0, 0.0)),
			"color": Color(0.1, 0.1, 0.1),
			"kind": PREFIX_KINDS[i],
		})
	return out


func _cube_index_of(batch: Array, t: int) -> int:
	"""
	Where batch entry `t` lands in the CUBE bucket, ASKED OF THE SHIPPED BUCKETING
	FUNCTION rather than worked out here.

	Built on the batch TRUNCATED at `t`, the CUBE bucket's `instance_count` is
	exactly the number of CUBE entries before `t` — which is `t`'s own CUBE-bucket
	index. That is the whole trick, and it is why this check needs no second copy of
	`_build_block_multimesh`'s rule: a copy would agree with a broken original.
	`instance_count` is also one of the few things a MultiMesh will still tell you
	under the headless dummy renderer — see this check's docstring.
	"""
	var probe := MeshInstance3D.new()
	ChunkBatch._build_block_multimesh(probe, batch.slice(0, t))
	var node: Node = probe.get_node_or_null(CUBE_BUCKET)
	var n: int = 0 if node == null else (node as MultiMeshInstance3D).multimesh.instance_count
	probe.free()
	return n



# ============================================================================
# CHECK 10 — the cycle is ambience: the seed cannot see it
# ============================================================================

func _check_cycle_off_the_seed(terrain_script: GDScript) -> void:
	"""
	PLACEMENT is seeded, THE CYCLE IS NOT, and both halves are asserted here.

	(a) BEHAVIOURAL. Two SEPARATE terrains on the same seed build the same chunk
	    byte-identically. A `randomize()`d value that leaked into the geometry —
	    the obvious slip being to light the initial lamp from the rolled phase —
	    differs between two processes and between two terrains in one, so this is
	    the measurement that catches it. It is non-vacuous only if the chunk it
	    compares actually holds a head, which is what the sweep below insists on.

	(b) TEXTUAL, `scarcity_selfcheck` check 3's shape and for its reason: a
	    behavioural check can only speak for the world it sampled, and "this clock
	    is not on the seed" is a statement about the code. The plant randomizes and
	    never reads `run_seed`; the geometry never randomizes; the write linearises.
	    Each of the three is a rule a future edit would otherwise slip past, and the
	    check fails by name if a function it reads has been renamed away.
	"""
	# --- (a)
	var a: Node3D = _terrain(terrain_script, SEEDS[0], true)
	var b: Node3D = _terrain(terrain_script, SEEDS[0], true)
	var compared: int = 0
	for ox in range(-SWEEP_HALF, SWEEP_HALF + 1):
		if compared > 0:
			break
		for oy in range(-SWEEP_HALF, SWEEP_HALF + 1):
			var chunk_pos := Vector2i(ox, oy)
			var built_a: Dictionary = _spawn_bare(a, chunk_pos)
			var heads: int = 0
			for row: Dictionary in (built_a["paths"] as Array[Dictionary]):
				heads += (row["signals"] as PackedInt32Array).size()
			if heads == 0:
				continue
			var built_b: Dictionary = _spawn_bare(b, chunk_pos)
			compared += 1
			if var_to_bytes(built_a["batch"]) != var_to_bytes(built_b["batch"]):
				_fail("chunk %s carries %d traffic heads and two terrains on seed %d built it "
						% [chunk_pos, heads, SEEDS[0]] + "differently — something the "
						+ "`randomize()`d cycle rolls has leaked into the geometry, and the "
						+ "world is no longer a pure function of its seed")
			break
	if compared == 0:
		_fail("check 10a swept %dx%d chunks and found none with a traffic head in it, so its "
				% [SWEEP_HALF * 2 + 1, SWEEP_HALF * 2 + 1] + "same-seed comparison never "
				+ "covered the one feature in this family that has a randomize()d clock")
	a.free()
	b.free()

	# --- (b)
	var source: String = FileAccess.get_file_as_string(FAMILY_SCRIPT)
	if source.is_empty():
		_fail("could not read %s as text — check 10b cannot run" % FAMILY_SCRIPT)
		Sentinel.done("cycle_off_the_seed")
		return
	for rule: Array in TEXT_RULES:
		var fn: String = rule[0]
		var needle: String = rule[1]
		var must: bool = rule[2]
		var why: String = rule[3]
		var body: String = _function_body(source, fn)
		if body.strip_edges().is_empty():
			_fail("check 10b found no function `%s` in %s — it was renamed or removed, and "
					% [fn, FAMILY_SCRIPT] + "this assertion is now measuring nothing")
			continue
		if body.contains(needle) != must:
			_fail("`%s` %s `%s`: %s" % [fn, "must contain" if must else "must not contain",
					needle, why])
	Sentinel.done("cycle_off_the_seed")


# ============================================================================
# CHECK 11 — an unloaded chunk leaves no Timer behind
# ============================================================================

func _check_unload(terrain_script: GDScript) -> void:
	"""
	THE PARENTING RULE, MEASURED RATHER THAN TRUSTED.

	This family's Timer hangs off its MARKER, which hangs off the chunk — a
	deliberate departure from the bead, which said to parent it to the chunk itself,
	taken so the Timer stays out of the chunk's own child list (check 1 compares that
	list node for node to catch a stray draw). The departure is only safe if the
	Timer is still freed with the chunk, and "parented under it, so it must be" is a
	claim about Godot rather than a measurement. A per-chunk node that outlived its
	chunk in an endless runner is an unbounded leak AND a Timer ticking forever into
	a freed bucket.

	`remove_chunk()` is the shipped unload path and it uses `queue_free`, so this is
	the one check in the file that awaits a frame — a `free()` here would measure a
	teardown the game never performs.

	Non-vacuous by construction: it fails if it cannot find a chunk with a Timer in
	the first place, and it asserts the Timer was ALIVE before the unload as well as
	gone after it.

	ITS CONTROL IS A SECOND CHUNK THAT IS NOT UNLOADED, and its Timer must still be
	alive at the end. Without it, "the weak reference went null" is also what a check
	that had freed the whole world — or that was reading a reference which is null
	however the frame went — would print, and the assertion would pass whatever the
	unload did.
	"""
	var terrain: Node3D = _terrain(terrain_script, SEEDS[0], true)
	var found := Vector2i(0, 0)
	var timer: Timer = null
	var kept: Timer = null
	for ox in range(-SWEEP_HALF, SWEEP_HALF + 1):
		if timer != null and kept != null:
			break
		for oy in range(-SWEEP_HALF, SWEEP_HALF + 1):
			var pos := Vector2i(ox, oy)
			var built: Dictionary = _spawn_bare(terrain, pos)
			var heads: int = 0
			for row: Dictionary in (built["paths"] as Array[Dictionary]):
				heads += (row["signals"] as PackedInt32Array).size()
			if heads == 0:
				continue
			terrain.create_chunk(pos)
			var here: Timer = _signal_timer(terrain.active_chunks[pos])
			if here == null:
				continue
			if timer == null:
				timer = here
				found = pos
			elif kept == null:
				# THE CONTROL'S CHUNK: built, never unloaded, and its Timer must still
				# be alive when this check ends.
				kept = here
				break
	if timer == null:
		_fail("check 11 swept %dx%d chunks and built no chunk that carried a cycle Timer, so "
				% [SWEEP_HALF * 2 + 1, SWEEP_HALF * 2 + 1] + "'an unloaded chunk leaves none "
				+ "behind' was never once asked of a chunk that had one")
		terrain.free()
		Sentinel.done("unload")
		return
	var ref: WeakRef = weakref(timer)
	if ref.get_ref() == null:
		_fail("check 11's Timer was already dead before the chunk was unloaded")
	# REMEMBERED AS A BOOLEAN, AND THAT IS THE WHOLE POINT: in Godot a reference to a
	# FREED object compares equal to null, so a `kept != null` written after the unload
	# is false exactly when the control has something to say, and the guard below would
	# short-circuit itself into silence in the one state it exists to detect.
	var has_control: bool = kept != null
	if not has_control:
		_fail("check 11 found only one chunk with a cycle Timer in a %dx%d sweep, so it has no "
				% [SWEEP_HALF * 2 + 1, SWEEP_HALF * 2 + 1] + "second chunk to leave loaded — "
				+ "and without that control 'the Timer went away' is also what this check would "
				+ "print if nothing it holds survived the frame")
	var control: WeakRef = weakref(kept)
	terrain.remove_chunk(found)
	# `queue_free` frees at the end of the frame, which is why this check is awaited.
	await process_frame
	await process_frame
	if ref.get_ref() != null:
		_fail("chunk %s was unloaded through the shipped `remove_chunk()` and its bike-path "
				% found + "cycle Timer is still alive — every head the player walks past leaks "
				+ "a node that goes on ticking into a bucket that no longer exists")
	if terrain.active_chunks.has(found):
		_fail("chunk %s is still in `active_chunks` after `remove_chunk()`, so check 11 "
				% found + "measured an unload that did not happen")
	if has_control and control.get_ref() == null:
		_fail("check 11's control Timer, in a chunk that was never unloaded, died along with "
				+ "the one that was — so 'the Timer went away' says nothing about the unload")
	terrain.free()
	Sentinel.done("unload")


func _function_body(source: String, name: String) -> String:
	"""
	The lines of `func <name>(...)` up to the next top-level `func`, or "" when there
	is no such function. `scarcity_selfcheck`'s helper, and crude for its reason:
	GDScript's one-function-per-column-0-`func` layout is the whole grammar this
	needs, and `static func` counts — this family is static from end to end, so a
	matcher that only knew the instance spelling would find nothing at all and pass.
	"""
	var out: PackedStringArray = PackedStringArray()
	var inside := false
	for line: String in source.split("\n"):
		if line.begins_with("func " + name + "(") or line.begins_with("static func " + name + "("):
			inside = true
			continue
		if inside:
			if line.begins_with("func ") or line.begins_with("static func "):
				break
			out.append(line)
	return "\n".join(out)


# ============================================================================
# T1 — THE WORLD TIE, and it is this bead's named non-negotiable assertion
# ============================================================================

func _check_road_crossing_world_tie(terrain_script: GDScript) -> void:
	"""
	C1 (child `godot-test1-pnvb.4`, Part A) -- THE WORLD TIE OFF THE DRAWN BOX,
	AND THE ROUTE CONTINUES ACROSS THE ROAD.
	
	On seed 20260904 trunk 31 crosses the coin road through chunk (13, -3) with
	strip boxes, road coins and flanking poles all in it. Built through the
	SHIPPED `create_chunk`, then tied to a bare spawner run whose batch is
	readable: per edge the real marker's segments must equal the bare one's
	(segments never depend on footprints, so a mismatch is a second share-rule
	hiding somewhere), and past that tie every measurement is off the DRAWN box,
	never off the station list.
	
	Three statements: (a) every drawn strip box in the chunk stands at least
	`BIKE_ROAD_CLEARANCE` from the centreline, measured at its own world centre
	through the shipped `_road_lateral_distance` (which reads INF off-road, so
	the comparison IS the test); (b) the trunk's stations DO span the swath --
	an in-swath station exists mid-span, which is what distinguishes a crossing
	from a truncation -- while the chunk's marker for that edge still claims
	drawn segments, so the gap is in the paint and not in the route; (c) every
	built trunk pole flanking the road gap carries the CROSSING zebra
	(SIGN_KINDS[3], pinned as the literal 3), forced over the dispatch. The
	chunk is chosen so at least one flanking pole dispatches something else,
	and the check fails if it finds no flanking pole at all.
	
	No MultiMesh colour or transform is read back anywhere: instance data is
	write-only under the headless dummy renderer (`_multimesh_table`'s note).
	The batch is a plain Array of Dictionaries and every field in it is real,
	which is what T1 already relies on.
	"""
	var terrain: Node3D = _terrain(terrain_script, 20260904, true)
	var chunk_pos := Vector2i(13, -3)
	var edge_id: int = 31
	terrain.create_chunk(chunk_pos)
	if not terrain.active_chunks.has(chunk_pos):
		_fail("C1: chunk %s never streamed, so the crossing has nothing to stand on" % chunk_pos)
		terrain.free()
		Sentinel.done("road_crossing_world_tie")
		return
	var chunk_node: Node = terrain.active_chunks[chunk_pos]
	var built: Dictionary = _spawn_bare(terrain, chunk_pos)
	var at: Vector3 = terrain.chunk_to_world(chunk_pos)
	var real_rows: Dictionary = {}
	for marker: Node in _markers(chunk_node):
		real_rows[int(marker.get_meta("edge"))] = marker.get_meta("segments")
	var bare_rows: Dictionary = {}
	for row: Dictionary in (built["paths"] as Array[Dictionary]):
		bare_rows[int(row["edge"])] = row["segments"]
	for edge_v: Variant in real_rows:
		if not bare_rows.has(edge_v) or (bare_rows[edge_v] as PackedInt32Array) != (real_rows[edge_v] as PackedInt32Array):
			_fail("C1: edge %d draws %s for real but %s bare -- the per-chunk share " % [edge_v, real_rows[edge_v], bare_rows.get(edge_v, [])] + "is not the midpoint rule in both places")
	for edge_v: Variant in bare_rows:
		if not real_rows.has(edge_v):
			_fail("C1: edge %d draws %s bare but nothing for real -- same rule, both ways" % [edge_v, bare_rows[edge_v]])
	var strips: Array = []
	for entry_v: Variant in (built["batch"] as Array):
		var entry: Dictionary = entry_v
		var t: Transform3D = entry["transform"]
		if not is_equal_approx(t.origin.y, BikePaths.BIKE_PATH_THICKNESS * 0.5):
			continue
		var world := Vector2(at.x + t.origin.x, at.z + t.origin.z)
		if terrain._road_lateral_distance(world.x, world.y, BikePaths.BIKE_ROAD_CLEARANCE) < 14.0:
			_fail("C1: chunk %s draws a bike strip box at %s, inside the coin road's swath " % [chunk_pos, world] + "-- the paint gap the crossing owes the road is missing")
		var axis := Vector2(t.basis.x.x, t.basis.x.z).normalized()
		strips.append({"pos": world, "half": t.basis.x.length() * 0.5, "axis": axis})
	if strips.is_empty():
		_fail("C1: chunk %s draws no strip box at all, so the swath assertion held for free" % chunk_pos)
	var route: Array[Dictionary] = []
	for trunk: Dictionary in BikePaths.trunks(terrain):
		if int(trunk["id"]) == edge_id:
			route = trunk["stations"]
	if route.is_empty():
		_fail("C1: trunk %d does not exist on seed 20260904 -- the crossing moved" % edge_id)
		terrain.free()
		Sentinel.done("road_crossing_world_tie")
		return
	var in_swath: int = 0
	for station: Dictionary in route:
		var p: Vector2 = station["pos"]
		if terrain._road_lateral_distance(p.x, p.y, BikePaths.BIKE_ROAD_CLEARANCE) < BikePaths.BIKE_ROAD_CLEARANCE:
			in_swath += 1
	if in_swath == 0:
		_fail("C1: trunk %d has no station in the swath -- it truncates at the road, " % edge_id + "it does not cross it")
	if not real_rows.has(edge_id) or (real_rows[edge_id] as PackedInt32Array).is_empty():
		_fail("C1: trunk %d draws nothing in chunk %s -- the gap swallowed the route, " % [edge_id, chunk_pos] + "not just the paint")
	var bare_poles := PackedInt32Array()
	var bare_tops := PackedInt32Array()
	for row: Dictionary in (built["paths"] as Array[Dictionary]):
		if int(row["edge"]) == edge_id:
			bare_poles = row["poles"]
			bare_tops = row["tops"]
	var flanks: int = 0
	for pi in bare_poles.size():
		var bt: Transform3D = ((built["batch"] as Array)[int(bare_poles[pi])] as Dictionary)["transform"]
		var pw := Vector2(at.x + bt.origin.x, at.z + bt.origin.z)
		var best_j: int = 0
		var best_d: float = INF
		for j in route.size():
			var dd: float = pw.distance_to(route[j]["pos"])
			if dd < best_d:
				best_d = dd
				best_j = j
		var flanking: bool = false
		for o in range(maxi(0, best_j - 8), mini(route.size() - 1, best_j + 9)):
			var m2: Vector2 = ((route[o]["pos"] as Vector2) + (route[o + 1]["pos"] as Vector2)) * 0.5
			if terrain._road_lateral_distance(m2.x, m2.y, BikePaths.BIKE_ROAD_CLEARANCE) < BikePaths.BIKE_ROAD_CLEARANCE:
				flanking = true
				break
		if flanking:
			flanks += 1
			if int(bare_tops[pi]) != 3:
				_fail("C1: trunk %d has a pole flanking the road gap at %s carrying top %d, " % [edge_id, pw, int(bare_tops[pi])] + "not the CROSSING zebra (SIGN_KINDS[3]) the override owes it")
	if flanks == 0:
		_fail("C1: trunk %d shows no flanking pole in chunk %s, so the zebra override " % [edge_id, chunk_pos] + "was never exercised -- re-derive the chunk")
	print("C1: chunk %s draws %d strip boxes clear of the swath; " % [chunk_pos, strips.size()] + "trunk %d spans %d in-swath stations with %d flanking zebra poles" % [edge_id, in_swath, flanks])
	terrain.free()
	Sentinel.done("road_crossing_world_tie")


func _check_no_coin_on_strip(terrain_script: GDScript) -> void:
	"""
	C2 (child `godot-test1-pnvb.4`, Part A) -- NO ROAD COIN STANDS ON A DRAWN STRIP.
	
	The shipped refusal's actual worry, asserted directly and strictly stronger
	than the refusal was: on C1's chunk, every coin `CoinRoad.spawn_coins_in_chunk`
	places is measured against every drawn strip box. A coin counts as ON a strip
	when its XZ falls inside the box's footprint grown by a 0.3 m hair (float
	slack and nothing more -- the nearest real pair is metres apart). Fails if
	the chunk holds no coin or no strip, so neither half can hold for free.
	
	The coins are read off the shipped `_road_coins_at` over a 60 m window around
	the chunk (far wider than the spawner's own pad, so no station is missed) and
	bucketed by final chunk exactly the way the spawner buckets them. Settling,
	tower and deck adjustments never move a coin in XZ -- perch changes Y and
	skips only remove -- so this raw scatter set is a SUPERSET of the placed set
	and the assertion over it is stronger than over the placed set.
	"""
	var terrain: Node3D = _terrain(terrain_script, 20260904, true)
	var chunk_pos := Vector2i(13, -3)
	var built: Dictionary = _spawn_bare(terrain, chunk_pos)
	var at: Vector3 = terrain.chunk_to_world(chunk_pos)
	var strips: Array = []
	for entry_v: Variant in (built["batch"] as Array):
		var t: Transform3D = (entry_v as Dictionary)["transform"]
		if not is_equal_approx(t.origin.y, BikePaths.BIKE_PATH_THICKNESS * 0.5):
			continue
		var axis := Vector2(t.basis.x.x, t.basis.x.z).normalized()
		strips.append({"pos": Vector2(at.x + t.origin.x, at.z + t.origin.z),
			"half": t.basis.x.length() * 0.5, "axis": axis})
	if strips.is_empty():
		_fail("C2: chunk %s draws no strip box, so no coin can overlap one" % chunk_pos)
		terrain.free()
		Sentinel.done("no_coin_on_strip")
		return
	var coins: Array[Vector2] = []
	terrain._road_extend_to_x(at.x - 60.0, at.x + 60.0)
	var kk: int = terrain._road_first_k_at_or_after_x(at.x - 60.0)
	while kk <= terrain.road_k_max:
		var st: Dictionary = terrain._road_station(kk)
		kk += 1
		if (st["center"] as Vector2).x > at.x + 60.0:
			break
		for cw_v: Variant in terrain._road_coins_at(kk - 1):
			var cp: Vector3 = (cw_v as Dictionary)["pos"]
			if terrain.world_to_chunk(cp) == chunk_pos:
				coins.append(Vector2(cp.x, cp.z))
	if coins.is_empty():
		_fail("C2: chunk %s holds no road coin, so the overlap assertion held for free" % chunk_pos)
		terrain.free()
		Sentinel.done("no_coin_on_strip")
		return
	for coin: Vector2 in coins:
		for strip: Dictionary in strips:
			var rel: Vector2 = coin - (strip["pos"] as Vector2)
			var axis: Vector2 = strip["axis"]
			var along: float = absf(rel.dot(axis))
			var across: float = absf(rel.dot(Vector2(-axis.y, axis.x)))
			if along <= float(strip["half"]) + 0.3 and across <= BikePaths.BIKE_PATH_WIDTH * 0.5 + 0.3:
				_fail("C2: road coin at %s stands on a drawn strip box at %s in chunk %s -- " % [coin, strip["pos"], chunk_pos] + "a coin can land on paint the crossing failed to gap")
				break
	print("C2: %d road coins stand clear of %d drawn strip boxes in chunk %s" % [coins.size(), strips.size(), chunk_pos])
	terrain.free()
	Sentinel.done("no_coin_on_strip")


func _check_crossing_angle_rule(terrain_script: GDScript) -> void:
	"""
	C3 (child `godot-test1-pnvb.4`, Part A) -- THE ANGLE RULE BITES.
	
	Over the CI seeds, every trunk station walked through the swath mid-span must
	cross it at an acute angle above 45 degrees (pinned as the literal
	`acute <= 45.0` against `BIKE_ROAD_CROSSING_MIN_DEG`), measured between
	the station's own walked heading and the road station's heading through the
	shipped seam `BikePaths.road_station_near` -- which C3 drives rather than
	re-implementing the pick. Round 2 removed a `best_k = -1` sentinel the check
	used to share with the walk, blind west of the origin where station indices
	go negative; a sub-assertion fails on zero crossings judged by a negative
	station, so the seam cannot go blind there again. Endpoint-exempt corridor
	walking (the gate approach)
	is out of scope: it runs alongside by entitlement, not by crossing. Fails
	if the sweep finds no crossing at all, and prints how many candidate
	crossings were refused for running shallow (the `trunk_abandoned` "road"
	bucket), which is the rule's other half.
	"""
	var crossings: int = 0
	var neg_crossings: int = 0
	var shallow: int = 0
	var min_acute: float = 90.0
	for seed_value: int in SEEDS:
		var terrain: Node3D = _terrain(terrain_script, seed_value, true)
		var anchors: Array = terrain.bike_anchors()
		for trunk: Dictionary in BikePaths.trunks(terrain):
			var fa: Vector2 = anchors[int(trunk["a"])]["pos"]
			var fb: Vector2 = anchors[int(trunk["b"])]["pos"]
			var crosses: bool = false
			var neg: bool = false
			for station: Dictionary in (trunk["stations"] as Array[Dictionary]):
				var p: Vector2 = station["pos"]
				if p.distance_to(fa) < BikePaths.TRUNK_APPROACH_RADIUS \
					or p.distance_to(fb) < BikePaths.TRUNK_APPROACH_RADIUS:
					continue
				if terrain._road_lateral_distance(p.x, p.y, BikePaths.BIKE_ROAD_CLEARANCE) \
					>= BikePaths.BIKE_ROAD_CLEARANCE:
					continue
				var near: Dictionary = BikePaths.road_station_near(terrain, p)
				if near.is_empty():
					_fail("C3: seed %d has a trunk station in the swath with no road station near -- " % seed_value + "the swath reading disagrees with the station cache")
					continue
				var rh: float = float((near["station"] as Dictionary)["heading"])
				if int(near["k"]) < 0:
					neg = true
				var diff: float = absf(wrapf(float(station["heading"]) - rh, -PI, PI))
				var acute: float = rad_to_deg(minf(diff, PI - diff))
				if acute <= 45.0:
					_fail("C3: seed %d trunk %d crosses the swath at %.1f degrees -- " % [seed_value, int(trunk["id"]), acute] + "the near-perpendicular rule let a shallow crossing through")
				min_acute = minf(min_acute, acute)
				crosses = true
			if crosses:
				crossings += 1
			if neg:
				neg_crossings += 1
		for edge: Dictionary in terrain.bike_edges():
			if BikePaths.trunk_abandoned(terrain, edge) == "road":
				shallow += 1
		terrain.free()
	if crossings == 0:
		_fail("C3 swept %d seeds and found no trunk crossing the coin road -- a rule " % SEEDS.size() + "with no crossing in it asserts nothing")
	if neg_crossings == 0:
		_fail("C3 swept %d seeds and no crossing is judged by a negative road station index " % SEEDS.size() + "-- west of the origin the pick may be refusing blind (round-2 sentinel)")
	print("C3: %d trunks cross mid-span, shallowest at %.1f deg (rule: above 45); " % [crossings, min_acute] + "%d shallow candidates refused, %d judged by a negative station" % [shallow, neg_crossings])
	Sentinel.done("crossing_angle_rule")


func _check_spurs_attach(terrain_script: GDScript) -> void:
	"""
	C4 (child `godot-test1-pnvb.4`, Part B) -- EVERY SURVIVING SPUR ATTACHES.
	
	Over a corridor band on the CI seeds, every spur the walk keeps must have an
	endpoint within `SPUR_ATTACH_DISTANCE` of a trunk station, asked of the
	shipped `spur_attach_ok` the way check 3 asks `station_blocked` of its
	prefixes. Prints per seed the survivors, the aim/guard rejects (origins
	whose rarity roll passes but no spur survives, classified by the shipped
	`spur_reject_reason`) and the trunk count, with the spur:trunk ratio -- the
	number the owner's complaint is really about and the number `BIKE_PATH_CHANCE`
	is retuned against. Fails if no spur survives anywhere, so the assertion
	cannot hold for free.
	"""
	var total_surv: int = 0
	var total_rej: int = 0
	var total_trunks: int = 0
	for seed_value: int in SEEDS:
		var terrain: Node3D = _terrain(terrain_script, seed_value, true)
		var trunks: Array[Dictionary] = BikePaths.trunks(terrain)
		var surv: int = 0
		var rej: int = 0
		for ox in range(C4_X0, C4_X1 + 1):
			for oy in range(C4_Y0, C4_Y1 + 1):
				var origin := Vector2i(ox, oy)
				var stations: Array[Dictionary] = BikePaths.bike_path_at(terrain, origin)
				if not stations.is_empty():
					if not BikePaths.spur_attach_ok(terrain, stations):
						_fail("C4: seed %d keeps the spur from origin %s, yet neither endpoint " % [seed_value, origin] + "lands within a stride of a trunk station -- an unattached spur exists")
					surv += 1
				else:
					var rng := RandomNumberGenerator.new()
					rng.seed = hash(Vector3i(origin.x * BikePaths.BIKE_HASH_PRIME_X,
						origin.y * BikePaths.BIKE_HASH_PRIME_Y,
						terrain.run_seed ^ BikePaths.BIKE_PATH_SALT))
					var k: float = terrain.scarcity_at(terrain.chunk_to_world(origin))
					if rng.randf() < BikePaths.BIKE_PATH_CHANCE * k:
						if BikePaths.spur_reject_reason(terrain, origin) == "attach":
							rej += 1
		print("C4: seed %d: %d surviving spurs attach, %d aimed walks rejected, %d trunks (ratio %.2f)" % [seed_value, surv, rej, trunks.size(), float(surv) / float(maxi(1, trunks.size()))])
		total_surv += surv
		total_rej += rej
		total_trunks += trunks.size()
		terrain.free()
	if total_surv == 0:
		_fail("C4 swept %d seeds x %d origins and no spur survived anywhere, so every " % [SEEDS.size(), (C4_X1 - C4_X0 + 1) * (C4_Y1 - C4_Y0 + 1)] + "survivor attaches holds for free")
	print("C4: %d survivors attach over %d trunks (%d rejects); mean spur:trunk ratio %.2f" % [total_surv, total_trunks, total_rej, float(total_surv) / float(maxi(1, total_trunks))])
	Sentinel.done("spurs_attach")


func _stand_markers(chunk: Node) -> Array[Node]:
	## The rental epic's markers: this family's bare Node3Ds in group
	## `bike_stand`, found BY GROUP the way the game will find them.
	var out: Array[Node] = []
	for child: Node in chunk.get_children():
		if child.is_in_group(BikePaths.BIKE_STAND_GROUP):
			out.append(child)
	return out


func _sorted_lengths(v: Vector3) -> Array[float]:
	## A box's three side lengths, least first — what identifies a rack box
	## without trusting a yaw. The rail reads [0.08, 0.12, 2.2] and an upright
	## [0.09, 0.09, 1.0] however either is turned.
	var a: Array[float] = [v.x, v.y, v.z]
	a.sort()
	return a


func _skip_explained(terrain: Node3D, apos: Vector2, prelim: Vector2,
		home: Vector2i, waypoints: Array[Dictionary]) -> String:
	"""
	Why the touched anchor's owner chunk built no rack for it: rebuild the
	owner's pre-bike `obstacles` EXACTLY as `create_chunk` does — the same eight
	spawners in the same order — and show the preliminary site reads taken
	there, with the taker named; and that every OTHER owner-homed candidate
	reads taken or keep-out too, or phase 2 should have built THERE instead.

	@return: "" when the skip does NOT follow from the inputs (a broken build
	         decision — M-phase2 below), otherwise the taker's description.
	"""
	var centre: Vector3 = terrain.chunk_to_world(home)
	# In the tree, because the chest plant walks it from its marker.
	var mesh_instance := MeshInstance3D.new()
	root.add_child(mesh_instance)
	var platforms: Array = []
	var block_batch: Array = []
	var block_body := StaticBody3D.new()
	var obstacles: Array = terrain.spawn_objects_in_chunk(
			home, platforms, block_batch, block_body)
	terrain.spawn_artifact_in_chunk(home, mesh_instance, obstacles, block_batch, block_body)
	TerrainBiomes.spawn_biome_content_in_chunk(terrain, home, obstacles, block_batch, block_body)
	terrain.spawn_camp_in_chunk(home, mesh_instance, obstacles, block_batch, block_body)
	terrain.spawn_landmark_in_chunk(home, mesh_instance, obstacles, block_batch, block_body)
	terrain.spawn_chest_in_chunk(home, mesh_instance, obstacles, block_batch, block_body)
	TerrainWaypoints.spawn_waypoint_in_chunk(terrain, home, mesh_instance, obstacles, block_batch, block_body)
	terrain.spawn_city_in_chunk(home, mesh_instance, obstacles, block_batch, block_body)
	var at: Vector2 = prelim - Vector2(centre.x, centre.z)
	var excuse: String = ""
	if BikePaths._footprint_taken(obstacles, at, BikePaths.RACK_RADIUS):
		var best_d: float = INF
		var best := {"top": 0.0, "radius": 0.0}
		for o_v: Variant in obstacles:
			var entry: Dictionary = o_v
			var fpos: Vector3 = entry["pos"]
			var d: float = Vector2(fpos.x - at.x, fpos.y - at.y).length() \
					- float(entry["radius"])
			if d < best_d:
				best_d = d
				best = entry
		excuse = "a footprint (top %.2f, radius %.2f) takes the preliminary site" \
				% [float(best["top"]), float(best["radius"])]
		for dist: float in BikePaths.RACK_SITE_DISTANCES:
			for dir: Vector2 in BikePaths.RACK_SITE_DIRECTIONS:
				var site: Vector2 = apos + dir * dist
				if site == prelim:
					continue
				if terrain.world_to_chunk(Vector3(site.x, 0.0, site.y)) != home:
					continue
				if BikePaths._site_keep_out(terrain, site, waypoints):
					continue
				if BikePaths._footprint_taken(obstacles,
						site - Vector2(centre.x, centre.z), BikePaths.RACK_RADIUS):
					continue
				excuse = ""
				break
			if excuse == "":
				break
	mesh_instance.free()
	block_body.free()
	return excuse


func _same_dims(a: Array[float], b: Array[float]) -> bool:
	## Equal to within float precision — the `_same_color` idiom, for sizes.
	for i in 3:
		if not is_equal_approx(a[i], b[i]):
			return false
	return true


func _touched_from_edges(terrain: Node3D) -> Array[int]:
	## Every anchor index incident to the shipped edge set, least first.
	##
	## Deliberately NOT `BikePaths.touched_anchors()` — the flatmap the spawner
	## itself reads. Deriving the expected set from the same helper the build
	## does would agree with a broken one (M-untouched below grew racks on
	## twenty-one far-field anchors and stayed green on exactly that); asked of
	## `terrain.bike_edges()` instead, the graph tier pnvb.1's own suite owns,
	## this tier's mapping is measured by value. Check 1's aim re-derivation is
	## the same shape, for the same reason.
	var out: Array[int] = []
	for edge: Dictionary in terrain.bike_edges():
		for key: String in ["a", "b"]:
			var idx: int = int(edge[key])
			if not out.has(idx):
				out.append(idx)
	out.sort()
	return out


# ============================================================================
# R1 — one rack per touched anchor, and spurs get none (bead godot-test1-z2yv.3)
# ============================================================================

func _check_anchor_racks(terrain_script: GDScript) -> void:
	"""
	Across the field, exactly one rack per anchor a trunk touches.

	Every touched anchor's OWNER chunk — the chunk containing its preliminary
	site, derived here from the shipped pure `rack_site()` rather than by
	trusting the spawner's memo — is built through the SHIPPED `create_chunk`
	and must hold exactly one `bike_stand` marker for it, standing within
	`RACK_ANCHOR_REACH` of the anchor AND inside the building chunk: a rack is
	owned by its site's chunk, never its anchor's. The shapes under the marker
	must be the rack's and may overhang the seam by no more than the rack's own
	half-length. Dedup is by construction, so an owner chunk must hold exactly
	the markers site-homed in it — nothing else. Untouched anchors (the
	far-field landmarks no trunk reaches) must grow nothing. Fails on zero
	racks found.

	SPURS GET NO RACK, over C4's own population: every surviving spur end in
	pure-spur territory — farther than any anchor's rack can explain — must have
	no stand marker within `SPUR_END_CLEARANCE` of it. Fails if no pure end was
	tested.
	"""
	var pure_tested: int = 0
	for seed_value: int in SEEDS:
		var terrain: Node3D = _terrain(terrain_script, seed_value, true)
		var anchors: Array[Dictionary] = terrain.bike_anchors()
		var touched: Array[int] = _touched_from_edges(terrain)
		var waypoints: Array[Dictionary] = terrain.waypoint_sites()
		var built_chunks := {}
		# Every anchor's preliminary site this seed — the ownership map, derived
		# from the shipped pure function so the chunks built below are the
		# owners by value rather than by trusting the spawner's memo.
		var prelim := {}
		for i in anchors.size():
			prelim[i] = BikePaths.rack_site(terrain, anchors[i]["pos"], waypoints)
		var racks_found: int = 0
		var skipped: int = 0
		var skipped_homes := {}
		for idx: int in touched:
			var apos: Vector2 = anchors[idx]["pos"]
			var psite: Vector2 = prelim[idx]
			if psite == Vector2.INF:
				_fail("R1 seed %d anchor %d (%s): no keep-out-clearing site "
						% [seed_value, idx, String(anchors[idx]["id"])] + "anywhere, "
						+ "so it can never grow its rack")
				continue
			var home: Vector2i = terrain.world_to_chunk(
					Vector3(psite.x, 0.0, psite.y))
			if not built_chunks.has(home):
				terrain.create_chunk(home)
				built_chunks[home] = true
			var mine: Array[Node] = []
			for s: Node in _stand_markers(terrain.active_chunks[home]):
				# Defaulted: a marker with no `anchor` meta is R2's catch, and
				# matching it here must fail the count, never raise.
				if int(s.get_meta("anchor", -999)) == idx:
					mine.append(s)
			if mine.is_empty():
				# AN EXPLAINED SKIP. A taken site builds no rack and plants no
				# marker — the bead's own rule — so an owner that built nothing
				# must name the taker (M-phase2 below breaks the build decision
				# and turns this red).
				var excuse: String = _skip_explained(terrain, apos, psite, home,
						waypoints)
				if excuse == "":
					_fail("R1 seed %d anchor %d (%s): its owner chunk %s holds no "
							% [seed_value, idx, String(anchors[idx]["id"]), home]
							+ "marker for it, and the skip is UNEXPLAINED — the "
							+ "preliminary site reads free, so phase 2 should have "
							+ "built there")
					continue
				print("R1: seed %d anchor %d (%s) skipped: %s"
						% [seed_value, idx, String(anchors[idx]["id"]), excuse])
				skipped += 1
				skipped_homes[home] = int(skipped_homes.get(home, 0)) + 1
				continue
			if not mine[0].has_meta("pos"):
				_fail("R1 seed %d anchor %d (%s): its marker carries no `pos` meta"
						% [seed_value, idx, String(anchors[idx]["id"])])
				continue
			var pos: Vector3 = mine[0].get_meta("pos")
			var d: float = Vector2(pos.x - apos.x, pos.z - apos.y).length()
			if d > BikePaths.RACK_ANCHOR_REACH + 0.01:
				_fail("R1 seed %d anchor %d (%s): its marker stands %.1f m from the "
						% [seed_value, idx, String(anchors[idx]["id"]), d] + "anchor, "
						+ "past RACK_ANCHOR_REACH %.1f — every marker sits at its anchor"
						% BikePaths.RACK_ANCHOR_REACH)
				continue
			# IN-CHUNK, STRICT: the marker stands in the chunk that built it. A
			# rack owned by its anchor's chunk instead (M-owner below) plants
			# the marker a chunk away from its own geometry, which is what this
			# half turns red on.
			if terrain.world_to_chunk(Vector3(pos.x, 0.0, pos.z)) != home:
				_fail("R1 seed %d anchor %d (%s): its marker stands at %s, in chunk "
						% [seed_value, idx, String(anchors[idx]["id"]), pos] + "%s — "
						% terrain.world_to_chunk(Vector3(pos.x, 0.0, pos.z)) + "built "
						+ "by chunk %s. A rack is owned by its site's chunk, never "
						% home + "its anchor's")
				continue
			# ...AND RACK GEOMETRY UNDER IT, IN THE SAME CHUNK. A marker with no
			# rack under it is a lie the rental epic would build on, so every
			# marker must have the rail's and the uprights' shapes standing
			# within tolerance of it (M-norack below builds the marker with no
			# boxes and turns this red) — and every one of those shapes must
			# stand in the building chunk within the rack's own half-length of
			# its edge (M-owner below parents the geometry a chunk away and
			# turns that red). Centres may overhang a seam the way any box may;
			# what may not live in another chunk is the rack.
			var rail_dims := _sorted_lengths(Vector3(BikePaths.RACK_RAIL_LENGTH,
					BikePaths.RACK_RAIL_HEIGHT, BikePaths.RACK_RAIL_DEPTH))
			var upright_dims := _sorted_lengths(Vector3(BikePaths.RACK_UPRIGHT_WIDTH,
					BikePaths.RACK_UPRIGHT_HEIGHT, BikePaths.RACK_UPRIGHT_DEPTH))
			var rail_under: int = 0
			var uprights_under: int = 0
			var chunk_centre: Vector3 = terrain.chunk_to_world(home)
			var half: float = terrain.chunk_size * 0.5
			var grown := Rect2(chunk_centre.x - half, chunk_centre.z - half,
					half * 2.0, half * 2.0).grow(BikePaths.RACK_EXTENT)
			var out_of_chunk: int = 0
			var block_body: Node = terrain.active_chunks[home].get_node_or_null(
					BLOCK_BODY)
			if block_body != null:
				for shape_node: Node in block_body.get_children():
					if not (shape_node is CollisionShape3D):
						continue
					var sh: Shape3D = (shape_node as CollisionShape3D).shape
					if not (sh is BoxShape3D):
						continue
					var key := _sorted_lengths((sh as BoxShape3D).size)
					if not (_same_dims(key, rail_dims) \
							or _same_dims(key, upright_dims)):
						continue
					var at: Vector3 = (shape_node as Node3D).position
					var world := Vector2(chunk_centre.x + at.x, chunk_centre.z + at.z)
					var near: float = world.distance_to(Vector2(pos.x, pos.z))
					if near > MARKER_GEOMETRY_TOLERANCE:
						continue
					if _same_dims(key, rail_dims):
						rail_under += 1
					else:
						uprights_under += 1
					if not grown.has_point(world):
						out_of_chunk += 1
			if rail_under != 1 or uprights_under != BikePaths.RACK_UPRIGHT_COUNT:
				_fail("R1 seed %d anchor %d (%s): %d rail + %d upright shapes stand "
						% [seed_value, idx, String(anchors[idx]["id"]), rail_under,
							uprights_under] + "at its marker, want 1 + %d"
						% BikePaths.RACK_UPRIGHT_COUNT)
				continue
			if out_of_chunk > 0:
				_fail("R1 seed %d anchor %d (%s): %d of its rack shapes stand past "
						% [seed_value, idx, String(anchors[idx]["id"]), out_of_chunk]
						+ "the building chunk %s plus the rack's own half-length — "
						% home + "geometry parented to a chunk it does not stand in "
						+ "unloads with the wrong chunk")
				continue
			racks_found += 1
		# DEDUP BY CONSTRUCTION — on preliminary sites, not anchor positions. A
		# chunk owns the anchors whose sites fall in it; building from every
		# trunk end (M-dedup below) or from the anchor's chunk (M-owner below)
		# puts racks where no site-homing allows, which is what this half turns
		# red on.
		for home_v: Variant in built_chunks:
			var home: Vector2i = home_v
			var stands: Array[Node] = _stand_markers(terrain.active_chunks[home])
			var want: int = 0
			for idx: int in touched:
				var psite: Vector2 = prelim[idx]
				if psite == Vector2.INF:
					continue
				if terrain.world_to_chunk(Vector3(psite.x, 0.0, psite.y)) == home:
					want += 1
			want -= int(skipped_homes.get(home, 0))
			if stands.size() != want:
				_fail("R1 seed %d chunk %s homes %d touched anchors but holds %d "
						% [seed_value, home, want, stands.size()] + "bike_stand markers "
						+ "— dedup is by construction (one anchor, one chunk, one rack), "
						+ "not by a runtime set")
		# UNTOUCHED anchors grow nothing: no trunk reaches them, so no rack does.
		# Looked for in their preliminary owner's chunk — where a rack would
		# stand if the touched gate broke (M-untouched below).
		var untouched_tested: int = 0
		for i in anchors.size():
			if touched.has(i):
				continue
			var psite: Vector2 = prelim[i]
			if psite == Vector2.INF:
				continue
			untouched_tested += 1
			var home: Vector2i = terrain.world_to_chunk(Vector3(psite.x, 0.0, psite.y))
			if not built_chunks.has(home):
				terrain.create_chunk(home)
				built_chunks[home] = true
			for s: Node in _stand_markers(terrain.active_chunks[home]):
				if int(s.get_meta("anchor", -999)) == i:
					_fail("R1 seed %d anchor %d (%s): no trunk touches it, yet its "
							% [seed_value, i, String(anchors[i]["id"])] + "chunk holds "
							+ "a bike_stand marker for it")
					break
		if untouched_tested == 0:
			_fail("R1 seed %d: no untouched anchor has a preliminary site, so "
					% seed_value + "'untouched anchors grow nothing' held for free")
		if racks_found == 0:
			_fail("R1 seed %d found no rack on %d touched anchors, so 'exactly one "
					% [seed_value, touched.size()] + "rack per touched anchor' held "
					+ "for free")
		print("R1: seed %d: %d racks stand on %d touched anchors (%d explained skips)"
				% [seed_value, racks_found, touched.size(), skipped])
		# --- SPURS GET NO RACK. C4's survivors, filtered to pure-spur territory
		# so no anchor's own rack can explain a marker near the end.
		for ox in range(C4_X0, C4_X1 + 1):
			for oy in range(C4_Y0, C4_Y1 + 1):
				var origin := Vector2i(ox, oy)
				var stations: Array[Dictionary] = BikePaths.bike_path_at(terrain, origin)
				if stations.is_empty():
					continue
				if not BikePaths.spur_attach_ok(terrain, stations):
					continue
				var end: Vector2 = stations[-1]["pos"]
				var pure: bool = true
				for idx: int in touched:
					var apos: Vector2 = anchors[idx]["pos"]
					if end.distance_to(apos) \
							<= BikePaths.RACK_ANCHOR_REACH + SPUR_END_CLEARANCE:
						pure = false
						break
				if not pure:
					continue
				var home: Vector2i = terrain.world_to_chunk(Vector3(end.x, 0.0, end.y))
				if not built_chunks.has(home):
					terrain.create_chunk(home)
					built_chunks[home] = true
				for s: Node in _stand_markers(terrain.active_chunks[home]):
					# Defaulted: a marker with no `pos` meta is R2's catch, and it
					# must never read as standing at a spur end.
					var pos: Vector3 = s.get_meta("pos", Vector3.INF)
					var d: float = Vector2(pos.x - end.x, pos.z - end.y).length()
					if d <= SPUR_END_CLEARANCE:
						_fail("R1 seed %d: the surviving spur from origin %s ends at %s, "
								% [seed_value, origin, end] + "clear of every touched "
								+ "anchor, yet a bike_stand marker (anchor %d) stands "
								% int(s.get_meta("anchor", -999)) + "%.1f m from its end — "
								% d + "spurs get no rack")
						break
				pure_tested += 1
		terrain.free()
	if pure_tested == 0:
		_fail("R1 swept %d seeds x %d origins and no surviving spur ended in "
				% [SEEDS.size(), (C4_X1 - C4_X0 + 1) * (C4_Y1 - C4_Y0 + 1)] + "pure-spur "
				+ "territory, so 'spurs get no rack' held for free")
	print("R1: %d pure spur ends tested bare over %d seeds" % [pure_tested, SEEDS.size()])
	Sentinel.done("anchor_racks")


# ============================================================================
# R4 — the rack asks with its OWN radius (round-2 finding)
# ============================================================================

func _check_rack_clearance(terrain_script: GDScript) -> void:
	"""
	The footprint currency only works when the asker spends what it is: a post
	asks with the pole's radius, a rack with the stand's (`RACK_RADIUS` = 1.4 m,
	not 0.26 m).

	ONE synthetic obstacle, placed BETWEEN the two thresholds — at
	obstacle.radius + 0.8 m from a real preliminary site, so it reads FREE to a
	post and TAKEN to a rack — and the shipped `rack_build_site` must refuse
	the site (move or skip). With the pole radius back in it builds there, and
	the `moved == prelim` assertion below is what turns red (M-radius). The
	unit pair above it pins the two thresholds directly. Fail-on-zero: the
	probe asserts the unmutated build did NOT stay, not merely that nothing
	fired.
	"""
	var terrain: Node3D = _terrain(terrain_script, SEEDS[0], true)
	var anchors: Array[Dictionary] = terrain.bike_anchors()
	var touched: Array[int] = _touched_from_edges(terrain)
	var waypoints: Array[Dictionary] = terrain.waypoint_sites()
	var idx: int = -1
	var apos := Vector2.INF
	var prelim := Vector2.INF
	for cand: int in touched:
		var site: Vector2 = BikePaths.rack_site(terrain, anchors[cand]["pos"], waypoints)
		if site != Vector2.INF:
			idx = cand
			apos = anchors[cand]["pos"]
			prelim = site
			break
	if idx < 0:
		_fail("R4 found no touched anchor with a preliminary site on seed %d, "
				% SEEDS[0] + "so the clearance probe never ran")
		terrain.free()
		Sentinel.done("rack_clearance")
		return
	var owner: Vector2i = terrain.world_to_chunk(Vector3(prelim.x, 0.0, prelim.y))
	var centre: Vector3 = terrain.chunk_to_world(owner)
	var at: Vector2 = prelim - Vector2(centre.x, centre.z)
	var obstacles: Array = [{
		"pos": Vector3(at.x + 2.8, 0.0, at.y),
		"radius": 2.0, "top": 1.0, "climbable": false,
	}]
	if BikePaths._footprint_taken(obstacles, at):
		_fail("R4: a post reads TAKEN 2.8 m from a radius-2.0 obstacle — the pole "
				+ "threshold moved")
	if not BikePaths._footprint_taken(obstacles, at, BikePaths.RACK_RADIUS):
		_fail("R4: a rack reads FREE 2.8 m from a radius-2.0 obstacle — the rack "
				+ "threshold moved")
	var moved: Vector2 = BikePaths.rack_build_site(terrain, apos, owner,
			waypoints, obstacles, Vector2(centre.x, centre.z))
	if moved == prelim:
		_fail("R4: the shipped build site kept the preliminary site with a taken "
				+ "footprint 2.8 m out — the rack asks with the pole's radius")
	elif moved == Vector2.INF:
		print("R4: anchor %d (%s): the synthetic obstacle skips the rack"
				% [idx, String(anchors[idx]["id"])])
	else:
		var dm: float = moved.distance_to(apos)
		print("R4: anchor %d (%s): the synthetic obstacle moves the rack to %.1f m"
				% [idx, String(anchors[idx]["id"]), dm])
		if dm > BikePaths.RACK_ANCHOR_REACH + 0.01:
			_fail("R4: the moved site stands %.1f m from its anchor, past "
					% dm + "RACK_ANCHOR_REACH")
	terrain.free()
	Sentinel.done("rack_clearance")


# ============================================================================
# R2 — the contract the rental epic reads (bead godot-test1-z2yv.3)
# ============================================================================

func _check_bike_stand_contract(terrain_script: GDScript) -> void:
	"""
	The group name is exactly `bike_stand`, and every marker carries `anchor`
	and `pos`, correctly typed.

	Found BY GROUP, the waypoint/landmark idiom — so the lookup itself is the
	group-name half of the assertion. What is asserted per marker: both metas
	present, `anchor` an int indexing the anchor table, `pos` a Vector3, and the
	marker NOT in `bike_path` — the tiers share no group, or every consumer that
	reads path markers by group trips over a marker with no `poles` meta. Fails
	on zero markers seen.
	"""
	var seen: int = 0
	for seed_value: int in SEEDS:
		var terrain: Node3D = _terrain(terrain_script, seed_value, true)
		var anchors: Array[Dictionary] = terrain.bike_anchors()
		var touched: Array[int] = _touched_from_edges(terrain)
		var waypoints: Array[Dictionary] = terrain.waypoint_sites()
		var built_chunks := {}
		for idx: int in touched:
			var psite: Vector2 = BikePaths.rack_site(
					terrain, anchors[idx]["pos"], waypoints)
			if psite == Vector2.INF:
				continue  # R1 owns the missing-owner verdict
			var home: Vector2i = terrain.world_to_chunk(
					Vector3(psite.x, 0.0, psite.y))
			if not built_chunks.has(home):
				terrain.create_chunk(home)
				built_chunks[home] = true
			for s: Node in _stand_markers(terrain.active_chunks[home]):
				if s.is_in_group(BikePaths.BIKE_PATH_GROUP):
					_fail("R2 seed %d: a bike_stand marker sits in bike_path too — "
							% seed_value + "the tiers share no group")
				if not s.has_meta("anchor") or not s.has_meta("pos"):
					_fail("R2 seed %d chunk %s: a bike_stand marker carries metas %s — "
							% [seed_value, home, s.get_meta_list()] + "the contract is "
							+ "exactly `anchor: int` and `pos: Vector3`")
					continue
				var a: Variant = s.get_meta("anchor")
				var p: Variant = s.get_meta("pos")
				if typeof(a) != TYPE_INT:
					_fail("R2 seed %d chunk %s: a marker's `anchor` is %s, not int"
							% [seed_value, home, typeof(a)])
				elif int(a) < 0 or int(a) >= anchors.size():
					_fail("R2 seed %d chunk %s: a marker's `anchor` %d indexes no row "
							% [seed_value, home, int(a)] + "of %d anchors"
							% anchors.size())
				if typeof(p) != TYPE_VECTOR3:
					_fail("R2 seed %d chunk %s: a marker's `pos` is %s, not Vector3"
							% [seed_value, home, typeof(p)])
				seen += 1
		terrain.free()
	if seen == 0:
		_fail("R2 swept %d seeds and found no bike_stand marker at all, so the "
				% SEEDS.size() + "contract asserted nothing")
	print("R2: %d bike_stand markers carry anchor:int + pos:Vector3 over %d seeds"
			% [seen, SEEDS.size()])
	Sentinel.done("bike_stand_contract")


# ============================================================================
# R3 — the world tie: a rack box really in the batch stands at its anchor
# ============================================================================

func _check_anchor_rack_world_tie(terrain_script: GDScript) -> void:
	"""
	THIS BEAD'S NAMED NON-NEGOTIABLE: the rack is geometry in the world, not a
	marker that says geometry.

	For each tied anchor (`TIE_ANCHORS`, bounds in `TIE_BOUNDS`): build its chunk
	through the SHIPPED `create_chunk`, take the marker R1 counts, and (a) find
	the rack's boxes in the chunk's collision body by their own dimensions —
	real pipeline geometry, readable headless — asserting each stands within the
	stated bound of the anchor AND within `MARKER_GEOMETRY_TOLERANCE` of the
	marker; then (b) run the shipped spawner into a prefix batch, find the same
	boxes by the same dimensions, and drive the SHIPPED
	`ChunkBatch._build_block_multimesh` truncated at the rail — the check-9
	idiom — asserting the rail occupies exactly one CUBE instance and stands
	within the bound of the anchor and on top of the real marker. Never a
	MultiMesh colour or transform read back: instance data is write-only under
	the headless dummy renderer (check 9's docstring carries the measurement).

	The bare-vs-real half (b) is also what ties the two builds together: the
	real chunk's obstacles must not have moved the site off the bare one, or the
	check names it and the ties are re-derived rather than trusted.
	"""
	var terrain: Node3D = _terrain(terrain_script, SEEDS[0], true)
	var anchors: Array[Dictionary] = terrain.bike_anchors()
	var rail_dims := _sorted_lengths(Vector3(BikePaths.RACK_RAIL_LENGTH,
			BikePaths.RACK_RAIL_HEIGHT, BikePaths.RACK_RAIL_DEPTH))
	var upright_dims := _sorted_lengths(Vector3(BikePaths.RACK_UPRIGHT_WIDTH,
			BikePaths.RACK_UPRIGHT_HEIGHT, BikePaths.RACK_UPRIGHT_DEPTH))
	for t in TIE_ANCHORS.size():
		var idx: int = TIE_ANCHORS[t]
		var bound: float = TIE_BOUNDS[t]
		var apos: Vector2 = anchors[idx]["pos"]
		var prelim: Vector2 = BikePaths.rack_site(
				terrain, apos, terrain.waypoint_sites())
		if prelim == Vector2.INF:
			_fail("R3 anchor %d (%s): no keep-out-clearing site — the tie needs "
					% [idx, String(anchors[idx]["id"])] + "R1's owner")
			continue
		var home: Vector2i = terrain.world_to_chunk(
				Vector3(prelim.x, 0.0, prelim.y))
		terrain.create_chunk(home)
		var chunk_node: Node = terrain.active_chunks[home]
		var centre: Vector3 = terrain.chunk_to_world(home)
		var mine: Array[Node] = []
		for s: Node in _stand_markers(chunk_node):
			if int(s.get_meta("anchor", -999)) == idx:
				mine.append(s)
		if mine.size() != 1:
			_fail("R3 anchor %d (%s): chunk %s holds %d of its markers — the tie "
					% [idx, String(anchors[idx]["id"]), home, mine.size()] + "needs "
					+ "the one R1 counts")
			continue
		if not mine[0].has_meta("pos"):
			_fail("R3 anchor %d (%s): its marker carries no `pos` meta"
					% [idx, String(anchors[idx]["id"])])
			continue
		var mpos: Vector3 = mine[0].get_meta("pos")
		var dm: float = Vector2(mpos.x - apos.x, mpos.z - apos.y).length()
		print("R3 anchor %d (%s): marker %.1f m from anchor (bound %.1f)"
				% [idx, String(anchors[idx]["id"]), dm, bound])
		if dm > bound:
			_fail("R3 anchor %d (%s): its marker stands %.1f m from the anchor, past "
					% [idx, String(anchors[idx]["id"]), dm] + "the stated bound %.1f"
					% bound)
			continue
		# --- (a) THE SHAPES: the shipped pipeline's own collision half.
		var body: Node = chunk_node.get_node_or_null(BLOCK_BODY)
		if body == null:
			_fail("R3 anchor %d (%s): chunk %s grew no BlockCollision body — a rack "
					% [idx, String(anchors[idx]["id"]), home] + "is furniture, not paint")
			continue
		var rail_here: Array[Vector3] = []
		var uprights_here: Array[Vector3] = []
		for shape_node: Node in body.get_children():
			if not (shape_node is CollisionShape3D):
				continue
			var sh: Shape3D = (shape_node as CollisionShape3D).shape
			if not (sh is BoxShape3D):
				continue
			var key := _sorted_lengths((sh as BoxShape3D).size)
			var at: Vector3 = (shape_node as Node3D).position
			var near_marker: float = Vector2(
					centre.x + at.x - mpos.x, centre.z + at.z - mpos.z).length()
			if near_marker > MARKER_GEOMETRY_TOLERANCE:
				continue
			if _same_dims(key, rail_dims):
				rail_here.append(at)
			elif _same_dims(key, upright_dims):
				uprights_here.append(at)
		if rail_here.size() != 1 \
				or uprights_here.size() != BikePaths.RACK_UPRIGHT_COUNT:
			_fail("R3 anchor %d (%s): %d rail + %d upright shapes stand at its "
					% [idx, String(anchors[idx]["id"]), rail_here.size(),
						uprights_here.size()] + "marker, want 1 + %d — a marker with "
					% BikePaths.RACK_UPRIGHT_COUNT + "no rack under it is a lie")
			continue
		var tied: Array[Vector3] = [rail_here[0]]
		for u: Vector3 in uprights_here:
			tied.append(u)
		for at: Vector3 in tied:
			var world := Vector2(centre.x + at.x, centre.z + at.z)
			var dw: float = world.distance_to(apos)
			if dw > bound:
				_fail("R3 anchor %d (%s): a rack shape stands at %s, %.1f m from the "
						% [idx, String(anchors[idx]["id"]), world, dw] + "anchor — past "
						+ "the stated bound %.1f" % bound)
		# --- (b) THE BATCH: the same boxes as the MultiMesh will see them.
		var batch: Array = _prefix_batch()
		var obstacles: Array = []
		var bbody := StaticBody3D.new()
		var bchunk := MeshInstance3D.new()
		BikePaths.spawn_bike_path_in_chunk(terrain, home, bchunk, obstacles, batch, bbody)
		var rail_t: int = -1
		var mine_count: int = 0
		for e in batch.size():
			var entry: Dictionary = batch[e]
			if int(entry.get("kind", ChunkBatch.BoxKind.CUBE)) \
					!= ChunkBatch.BoxKind.CUBE:
				continue
			var bt: Transform3D = entry["transform"]
			var key := _sorted_lengths(Vector3(bt.basis.x.length(),
					bt.basis.y.length(), bt.basis.z.length()))
			if not (_same_dims(key, rail_dims) or _same_dims(key, upright_dims)):
				continue
			var world := Vector2(centre.x + bt.origin.x, centre.z + bt.origin.z)
			if world.distance_to(Vector2(mpos.x, mpos.z)) > MARKER_GEOMETRY_TOLERANCE:
				continue
			mine_count += 1
			if _same_dims(key, rail_dims):
				rail_t = e if rail_t < 0 else -2
		if mine_count != 1 + BikePaths.RACK_UPRIGHT_COUNT or rail_t < 0:
			_fail("R3 anchor %d (%s): its marker has %d rack boxes in the batch, "
					% [idx, String(anchors[idx]["id"]), mine_count] + "want %d — the "
					% (1 + BikePaths.RACK_UPRIGHT_COUNT) + "batch and the marker "
					+ "have come apart")
			bchunk.free()
			bbody.free()
			continue
		var before: int = _cube_index_of(batch, rail_t)
		var after: int = _cube_index_of(batch, rail_t + 1)
		if after != before + 1:
			_fail("R3 anchor %d (%s): batch entry %d (the rail) occupies no CUBE "
					% [idx, String(anchors[idx]["id"]), rail_t] + "instance of its own "
					+ "in the shipped bucketing — it is not a real CUBE")
		var bt: Transform3D = (batch[rail_t] as Dictionary)["transform"]
		var world := Vector2(centre.x + bt.origin.x, centre.z + bt.origin.z)
		var dw: float = world.distance_to(apos)
		print("R3 anchor %d (%s): rail box %.1f m from anchor (bound %.1f)"
				% [idx, String(anchors[idx]["id"]), dw, bound])
		if dw > bound:
			_fail("R3 anchor %d (%s): the rail box stands %.1f m from the anchor, "
					% [idx, String(anchors[idx]["id"]), dw] + "past the stated bound "
					+ "%.1f" % bound)
		# IN-CHUNK, both halves of the finding: the rail box may overhang the
		# seam by no more than the rack's half-length, and the footprint the
		# bare run appended stands strictly inside the building chunk — the
		# obstacles list the crocodile spawner reads is the chunk the rack
		# stands in.
		var half: float = terrain.chunk_size * 0.5
		var grown := Rect2(centre.x - half, centre.z - half,
				half * 2.0, half * 2.0).grow(BikePaths.RACK_EXTENT)
		if not grown.has_point(world):
			_fail("R3 anchor %d (%s): the rail box stands at %s, past chunk %s "
					% [idx, String(anchors[idx]["id"]), world, home] + "plus the "
					+ "rack's own half-length — geometry parented to a chunk it "
					+ "does not stand in unloads with the wrong chunk")
		var prints_under: int = 0
		for o_v: Variant in obstacles:
			var entry: Dictionary = o_v
			if not is_equal_approx(float(entry["top"]), BikePaths.RACK_TOP):
				continue
			var fpos: Vector3 = entry["pos"]
			var fworld := Vector2(centre.x + fpos.x, centre.z + fpos.z)
			if fworld.distance_to(Vector2(mpos.x, mpos.z)) > MARKER_GEOMETRY_TOLERANCE:
				continue
			prints_under += 1
			var strict := Rect2(centre.x - half, centre.z - half,
					half * 2.0, half * 2.0).grow(0.01)
			if not strict.has_point(fworld):
				_fail("R3 anchor %d (%s): its footprint stands at %s, outside "
						% [idx, String(anchors[idx]["id"]), fworld] + "chunk %s — "
						% home + "the obstacles list it reserves is the wrong "
						+ "chunk's")
		if prints_under != 1:
			_fail("R3 anchor %d (%s): %d rack footprints stand at its marker, "
					% [idx, String(anchors[idx]["id"]), prints_under] + "want "
					+ "exactly one")
		var drift: float = world.distance_to(Vector2(mpos.x, mpos.z))
		if drift > MARKER_GEOMETRY_TOLERANCE:
			_fail("R3 anchor %d (%s): the bare spawner's rail stands %.1f m from the "
					% [idx, String(anchors[idx]["id"]), drift] + "real chunk's marker "
					+ "— the chunk's obstacles moved the site off the bare one, so "
					+ "the ties are re-derived rather than trusted")
		bchunk.free()
		bbody.free()
	terrain.free()
	Sentinel.done("anchor_rack_world_tie")


func _check_trunk_world_tie(terrain_script: GDScript) -> void:
	"""
	A DRAWN TRUNK BOX, TIED TO THE STATION THAT PRODUCED IT.

	*Two shipped beads drew geometry that was consistently wrong against the world
	while every internal check passed — the strips 25 m off (a chunk-centre /
	chunk-corner mix-up) and every sign plate built inside its post — because each
	check compared a build to a build, a list to itself, or a count to a count.*
	Tier 1 introduces a whole new way in: its stations come out of a graph rather
	than out of a chunk's own coordinates, so a frame error here would land every
	trunk in the world somewhere other than the ground its walk cleared, and 2c
	would not see it (it only reads spurs) while 2d, 3b and T2 all still passed.

	SO, PER SAMPLED SEGMENT, FOUR STATEMENTS ABOUT ONE BOX:
	  * a strip box exists in that chunk's batch whose WORLD centre — the chunk
	    node's own position plus the batch entry's origin — is the segment's
	    midpoint to under a centimetre;
	  * its length along its own +X is the segment's length;
	  * its +X axis points ALONG the segment (`absf(dot)`, because a box yawed by
	    PI is the same box);
	  * and the chunk's marker for THAT EDGE claims that segment index, which ties
	    the bookkeeping `.3` and `.4` will read to the geometry a player sees.
	It FAILS LOUDLY if no strip box was found, and again if no segment was tied at
	all — a check that asserted nothing is the failure mode being guarded against.

	MEASURED OFF `block_batch` AND NOT OFF THE BUILT MULTIMESH, for check 2c's
	reason: instance data is write-only under the headless dummy renderer
	(`_multimesh_table`'s note carries that measurement), so a transform read back
	from a real `create_chunk` would be the identity at every index and this would
	pass with the geometry anywhere at all. The batch is a plain Array of
	Dictionaries and every field in it is real, and `_spawn_bare` drives the
	SHIPPED `spawn_bike_path_in_chunk` into one.

	WATER IS SKIPPED, AND THE SKIP IS PERMANENT. A trunk segment over a river is
	never painted at ground level — child `godot-test1-pnvb.3` carries it on a DECK
	at `FieldBridges.FIELD_BRIDGE_TOP` instead, which is B1's subject and not this
	check's, and where a crossing is refused the gap stays. Deleting this skip would
	make T1 look for a strip box that must not exist.
	"""
	var terrain: Node3D = _terrain(terrain_script, SEEDS[0], true)
	var waypoints: Array[Dictionary] = terrain.waypoint_sites()
	var trunks: Array[Dictionary] = BikePaths.trunks(terrain)
	var tied: int = 0
	var trunks_used: int = 0
	for trunk: Dictionary in trunks:
		if trunks_used >= TIE_TRUNKS:
			break
		var stations: Array[Dictionary] = trunk["stations"]
		var edge_id: int = int(trunk["id"])
		var here: int = 0
		for i in range(stations.size() - 1):
			if here >= TIE_SEGMENTS:
				break
			var a: Vector2 = stations[i]["pos"]
			var b: Vector2 = stations[i + 1]["pos"]
			if terrain.is_river_at(Vector3(a.x, 0.0, a.y)) \
					or terrain.is_river_at(Vector3(b.x, 0.0, b.y)) \
					or BikePaths.segment_blocked(terrain, a, b):
				continue
			var mid: Vector2 = (a + b) * 0.5
			# ...and the segments inside a DESTINATION'S KEEP-OUT DISC, which are not
			# drawn either (T5's ruling). A trunk's first segments are the ones most
			# likely to be in one — the HQ anchor IS the tower's centre — so without
			# this T1 would sample exactly the stretch the family deliberately leaves
			# bare and report every route as missing its paint.
			if BikePaths.trunk_keep_out(terrain, a, waypoints) \
					or BikePaths.trunk_keep_out(terrain, b, waypoints) \
					or BikePaths.trunk_keep_out(terrain, mid, waypoints):
				continue
			var chunk_pos: Vector2i = terrain.world_to_chunk(Vector3(mid.x, 0.0, mid.y))
			var built: Dictionary = _spawn_bare(terrain, chunk_pos)
			var at: Vector3 = terrain.chunk_to_world(chunk_pos)
			var best: float = INF
			var hit: Transform3D = Transform3D()
			var found: bool = false
			for entry_v: Variant in (built["batch"] as Array):
				var t: Transform3D = (entry_v as Dictionary)["transform"]
				if not is_equal_approx(t.origin.y, BikePaths.BIKE_PATH_THICKNESS * 0.5):
					continue
				var world := Vector2(at.x + t.origin.x, at.z + t.origin.z)
				var d: float = world.distance_to(mid)
				best = minf(best, d)
				if d <= STRIP_TOLERANCE:
					hit = t
					found = true
					break
			if not found:
				_fail("T1: trunk %d segment %d runs from %s to %s, so its midpoint %s falls "
						% [edge_id, i, a, b, mid] + "in chunk %s — and the nearest strip box "
						% chunk_pos + "that chunk drew stands %.2f m away. The trunk is not on "
						% best + "the ground its own walk cleared: check the chunk-local frame, "
						+ "which is centred on the chunk NODE and not on its corner")
				here += 1
				continue
			var want_len: float = a.distance_to(b)
			if absf(hit.basis.x.length() - want_len) > STRIP_TOLERANCE:
				_fail("T1: trunk %d segment %d is %.3f m long and its strip box is %.3f m — "
						% [edge_id, i, want_len, hit.basis.x.length()]
						+ "the paint does not reach from one station to the next")
			var axis := Vector2(hit.basis.x.x, hit.basis.x.z).normalized()
			var along: Vector2 = (b - a).normalized()
			if absf(axis.dot(along)) < 1.0 - TIE_YAW_TOLERANCE:
				_fail("T1: trunk %d segment %d runs along %s and its strip box is yawed along "
						% [edge_id, i, along] + "%s — the strip is laid across its own segment"
						% axis)
			var claimed: bool = false
			for row: Dictionary in (built["paths"] as Array[Dictionary]):
				if int(row["edge"]) == edge_id and i in (row["segments"] as PackedInt32Array):
					claimed = true
			if not claimed:
				_fail("T1: chunk %s drew trunk %d's segment %d but its marker does not list "
						% [chunk_pos, edge_id, i] + "it, so the metas `.3` and `.4` read have "
						+ "come apart from the boxes a player sees")
			tied += 1
			here += 1
		if here > 0:
			trunks_used += 1
	if trunks.is_empty():
		_fail("T1 found no trunk on seed %d, so the world tie — this bead's named "
				% SEEDS[0] + "non-negotiable assertion — was never made. Tier 1 may be dead")
	elif tied == 0:
		_fail("T1 walked %d trunks and tied not one segment to the world. Every other trunk "
				% trunks.size() + "check in this file compares a build to a build or a list "
				+ "to itself, so nothing here would notice geometry drawn 25 m off")
	terrain.free()
	Sentinel.done("trunk_world_tie")


# ============================================================================
# T2 — the intersection is EXACT, because it is an assignment
# ============================================================================

func _check_trunk_intersections(terrain_script: GDScript) -> void:
	"""
	TWO TRUNKS SHARING AN ANCHOR END ON THE SAME `Vector2`, TO THE BIT.

	This is the owner's *"there should be INTERSECTIONS"*, asserted. It is the one
	property that needs no crossing query, no lattice and no snapping tolerance:
	both routes are DEFINED to end at the anchor, and `_trunk_route` writes the
	anchor's own `Vector2` into the terminal station rather than stopping near it.

	FOUND LOOSELY, ASSERTED EXACTLY, and that gap IS the check. A route is taken to
	reach an anchor when one of its two ends lands inside one `BIKE_STATION_SPACING`
	of it — which is the arrival condition itself — and is then asserted to be
	EQUAL to it with `==`. Replace the snap assignment with "stop when close
	enough" and exactly the same routes are found and every one of them fails,
	which is the mutation this shape exists to catch. `is_equal_approx` would not:
	at 1e-5 it is far too tight to find an unsnapped end at all, so the check would
	go quiet instead of red.
	"""
	var meets: int = 0
	for seed_value: int in SEEDS:
		var terrain: Node3D = _terrain(terrain_script, seed_value, true)
		var anchors: Array[Dictionary] = terrain.bike_anchors()
		var routes: Dictionary = {}
		for trunk: Dictionary in BikePaths.trunks(terrain):
			routes[int(trunk["id"])] = trunk["stations"]
		# anchor index -> [[edge id, the end that reached it], ...]
		var reaching: Dictionary = {}
		for edge: Dictionary in terrain.bike_edges():
			var edge_id: int = int(edge["id"])
			if not routes.has(edge_id):
				continue
			var stations: Array[Dictionary] = routes[edge_id]
			for n: int in [int(edge["a"]), int(edge["b"])]:
				var anchor: Vector2 = anchors[n]["pos"]
				for end_v: Variant in [stations[0]["pos"], stations[-1]["pos"]]:
					var end: Vector2 = end_v
					if end.distance_to(anchor) > BikePaths.BIKE_STATION_SPACING:
						continue
					if not reaching.has(n):
						reaching[n] = []
					(reaching[n] as Array).append([edge_id, end])
					break
		for n_v: Variant in reaching:
			var n: int = n_v
			var rows: Array = reaching[n]
			if rows.size() < 2:
				continue
			var anchor: Vector2 = anchors[n]["pos"]
			for row_v: Variant in rows:
				var row: Array = row_v
				if (row[1] as Vector2) != anchor:
					_fail("seed %d: trunk %d reaches anchor %d (\"%s\") at %s, and that anchor "
							% [seed_value, int(row[0]), n, anchors[n]["id"], row[1]]
							+ "stands at %s. The arrival must be an ASSIGNMENT and not a "
							% anchor + "tolerance, or two trunks meeting here do not actually "
							+ "touch and the owner's intersection is a near miss")
			meets += 1
		terrain.free()
	if meets == 0:
		_fail("T2 found no anchor at all where two trunks meet, across %d seeds — the "
				% SEEDS.size() + "owner's \"there should be INTERSECTIONS\" is unasserted, and "
				+ "so is the snap that makes one exact")
	Sentinel.done("trunk_intersections")


# ============================================================================
# T5 — a trunk stops at its destination's keep-out disc
# ============================================================================

func _check_trunk_keep_outs(terrain_script: GDScript) -> void:
	"""
	NOTHING THIS FAMILY EMITS STANDS INSIDE A KEEP-OUT — not a box, not a collision
	shape, not a footprint. Four of them: the tower's disc, a teleport circle, a
	landmark's chunk, and THE COIN ROAD'S SWATH.

	THE ROAD HALF IS THE LOAD-BEARING ONE, and it arrived in round 2 of the review.
	`BudapestPlan.GATE` sits dead centre in the swath, so a trunk to the gate — the
	anchor this whole epic is pointed at — has to be allowed to WALK the corridor.
	What stops it PAINTING there is this assertion and nothing else: check 3b's own
	station assertion moved out when the road joined `trunk_keep_out`, so "no coin
	ever lands on a strip because no strip is there" is asserted here, over every box
	and every footprint in the chunk, or nowhere.

	THE COLLISION THIS EXISTS FOR, measured rather than imagined. The HQ anchor is
	`tower_site()`, the tower's OWN CENTRE, so `TRUNK_APPROACH_RADIUS` entitles a
	trunk ending there to walk its last 65 m straight through the keep-out disc
	that protects the building's authored approach — and the first build of this
	bead did exactly that. `tower_site_selfcheck` caught it: a `BikePathMarker`
	35.4 m from the tower site and three `CollisionShape3D`s at 19.9, 40.1 and
	59.8 m. Both rules were correct on their own; nobody had put them together.

	The owner's ruling is to stop the PAINT at the disc rather than exempt the
	trunk from it, so the stop is a draw-time `continue` in `_draw_path_share` on
	the shipped `BikePaths.trunk_keep_out()`. This is that ruling, asserted where
	the family lives — `tower_site_selfcheck` would catch the tower again, but it
	knows nothing about the waypoint circles or the landmark sites, which have
	exactly the same shape of problem and were never the one that failed.

	NON-VACUOUS BY CONSTRUCTION, and this is the half that matters. A trunk that
	never enters a disc satisfies the assertion for free, so the check first counts
	the STATIONS that really do fall inside one — the ones the walk's endpoint
	exemption produced — and FAILS IF THAT COUNT IS ZERO. Only then does "no box in
	there" mean the draw-time stop is doing the work.

	It reads the boxes and the footprints off `_spawn_bare`'s own batch and
	`obstacles`, in world space, and never off a built MultiMesh: instance data is
	write-only under the headless dummy renderer.

	THE SWEEP IS TIER-BLIND, DELIBERATELY, and the messages below say "a bike box"
	rather than "a trunk" because of it. `_spawn_bare` drives the shipped spawner,
	which draws BOTH tiers, and the `edge` meta could filter it — but a SPUR standing
	geometry in a keep-out is a defect on exactly the same grounds, and there are two
	narrow ways it can: `_station_blocked` clears a spur STATION against these same
	radii and nothing re-tests its POLE, which leans `BIKE_POLE_OFFSET` = 1.65 m to
	the side, so a station 72.6 m from the tower centre or half a metre outside a
	landmark's chunk can still plant a post inside. THE COIN ROAD IS A THIRD WAY and
	the widest of them, added when the swath joined `trunk_keep_out`: a spur station
	is cleared at 14 m lateral, so one standing at 14.0-15.65 m with its pole on the
	road side plants a post in the swath. Filtering to trunks would hide all three.
	If this ever fires on a spur it is a finding and not a false alarm, and the fix
	is the same guard the trunk tier already carries — `terrain_bike_paths.gd` says
	at that guard why this bead does not reach across and apply it.
	"""
	var terrain: Node3D = _terrain(terrain_script, SEEDS[0], true)
	var waypoints: Array[Dictionary] = terrain.waypoint_sites()
	var inside_stations: int = 0
	var chunks: Dictionary = {}
	for trunk: Dictionary in BikePaths.trunks(terrain):
		for station: Dictionary in (trunk["stations"] as Array[Dictionary]):
			var at: Vector2 = station["pos"]
			if not BikePaths.trunk_keep_out(terrain, at, waypoints):
				continue
			inside_stations += 1
			# Every chunk that could draw a segment ending here, and its ring, so a
			# box overhanging the seam from outside is measured too.
			var home: Vector2i = terrain.world_to_chunk(Vector3(at.x, 0.0, at.y))
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					chunks[home + Vector2i(dx, dy)] = true
	if inside_stations == 0:
		_fail("T5 found no trunk station inside any keep-out on seed %d, "
				% SEEDS[0] + "so the draw-time stop was never exercised and 'no box in the "
				+ "disc' holds for free. The HQ anchor IS the tower's centre, so a world "
				+ "with a trunk to the HQ must produce some — re-derive the seed rather "
				+ "than trusting this")
	var boxes: int = 0
	var shapes: int = 0
	for key: Variant in chunks:
		var chunk_pos: Vector2i = key
		var built: Dictionary = _spawn_bare(terrain, chunk_pos)
		var at: Vector3 = terrain.chunk_to_world(chunk_pos)
		for entry_v: Variant in (built["batch"] as Array):
			var t: Transform3D = (entry_v as Dictionary)["transform"]
			var world := Vector2(at.x + t.origin.x, at.z + t.origin.z)
			if BikePaths.trunk_keep_out(terrain, world, waypoints):
				boxes += 1
				_fail("T5: chunk %s draws a bike box at %s, which is inside a destination's "
						% [chunk_pos, world] + "keep-out (the tower's disc, a teleport "
						+ "circle, a landmark's chunk or the coin road's swath). This family "
						+ "must STOP at one, not be exempt from it — a trunk is entitled to "
						+ "WALK to its own anchor, never to PAINT the last 70 m of it")
				break
		for o_v: Variant in (built["obstacles"] as Array):
			var pos: Vector3 = (o_v as Dictionary)["pos"]
			var world := Vector2(at.x + pos.x, at.z + pos.z)
			if BikePaths.trunk_keep_out(terrain, world, waypoints):
				shapes += 1
				_fail("T5: chunk %s appends a bike-path FOOTPRINT at %s, inside a "
						% [chunk_pos, world] + "keep-out. Three of the five failures this "
						+ "check exists for were collision shapes, so the stop has to cover "
						+ "the poles and not only the paint")
				break
	if chunks.is_empty():
		_fail("T5 built no chunk at all, so neither half of it ran")
	print("bike trunks T5: %d trunk stations fall inside a keep-out (a disc, a landmark "
			% inside_stations + "chunk or the coin road's swath) on seed %d, over %d chunks; "
			% [SEEDS[0], chunks.size()] + "%d boxes and %d footprints were drawn in there "
			% [boxes, shapes] + "(both must be 0)")
	terrain.free()
	Sentinel.done("trunk_keep_outs")


# ============================================================================
# B1 / B3 / B4 — THE TRUNK BRIDGES (child `godot-test1-pnvb.3`)
# ============================================================================

func _check_trunk_bridges(terrain_script: GDScript) -> void:
	"""
	B1 / B3 / B4 — A DRAWN DECK, TIED TO THE RIVER SPAN THAT PRODUCED IT.

	*Two shipped beads drew geometry that was consistently wrong against the world
	while every internal check passed.* A deck has two new ways in: it is built
	from a polyline the BRIDGE family walks rather than from the trunk's own
	stations, and it is the one thing this family draws ABOVE the ground, so a
	frame error would put a strip at y = 0 over open water and a row in
	`field_bridges_near` claiming stone that is not there. Comparing the row to the
	row would see neither.

	SO, PER DECK, THREE SUBSYSTEMS ARE MADE TO AGREE ABOUT ONE PHYSICAL PLACE:

	  * **B1** a box really in the chunk's batch, whose WORLD centre — the chunk
	    node's own position plus the batch entry's origin — is a slab midpoint of
	    the row to under a centimetre, standing over a point where the shipped
	    `terrain.is_river_at()` is TRUE; and whose WALKING SURFACE (the box centre
	    plus half the slab's thickness) is what `terrain.field_bridge_surface_y()`
	    answers there. A deck built for the wrong span puts no box at that XZ; a
	    strip drawn at ground level instead of on the deck fails the Y.
	  * **B1b** and it is asked of EVERY SLAB OF THE ROW, ramps included, each in
	    whatever chunk the centre rule gave it. That is the control on the
	    trunk-route box merge: a ramp foot stands a ramp run plus its push budget
	    past the last station the deck was built from, so the chunk holding nothing
	    but that ramp rejects the whole trunk unless its box was widened to hold the
	    decks — and the ramp is then silently never drawn, which asking only about a
	    slab over the water cannot see.
	  * **B3** at that same XZ, a body at deck height is NOT wading and the deep
	    channel does NOT push it — while the water underneath it is real, which is
	    the control that stops B3 passing on dry ground. THE MECHANISM IS THE
	    HEIGHT GATE and it is asserted directly below: `WADE_SURFACE_MAX` is 0.6 m
	    and a deck stands at 1.6, so `is_wading_at` and `deep_channel_push` reject a
	    body on a bike deck before they evaluate any noise, exactly as they do on a
	    road deck. `_deep_channel_ford` is NOT the mechanism here — it is only
	    reached below `WADE_SURFACE_MAX` and it answers about the ROAD's stations —
	    so registering in `field_bridges_near` buys the deck the SPAWNER queries
	    (`field_bridge_surface_y`, `field_bridge_stand_y`) and the height gate buys
	    it the wading.
	  * **B4** the kill switch: with `spawn_bike_paths` false,
	    `field_bridges_near()` over that same window returns EXACTLY the rows it
	    returns with the flag on minus this family's own — so the flag turns off the
	    queries as well as the boxes. Non-vacuous by construction: it fails if the
	    ON side held no bike row in the window it compared.

	MEASURED OFF `block_batch` AND NOT OFF THE BUILT MULTIMESH, for check 2c's and
	T1's reason: instance data is write-only under the headless dummy renderer.
	"""
	var terrain: Node3D = _terrain(terrain_script, SEEDS[0], true)
	if FieldBridges.FIELD_BRIDGE_TOP <= terrain.WADE_SURFACE_MAX:
		_fail("B3: a field deck stands at %.2f m and WADE_SURFACE_MAX is %.2f m, so a hero "
				% [FieldBridges.FIELD_BRIDGE_TOP, terrain.WADE_SURFACE_MAX]
				+ "ON a trunk bridge is inside the wading band. The height gate is the only "
				+ "thing that stops the deep channel shoving him off it — see B3")
	var tied: int = 0
	var decks: int = 0
	var deck_only: int = 0
	var slabs_tied: int = 0
	# `_deck_box_at`'s memo is keyed on a chunk and holds THIS terrain's batches, so
	# it is emptied here rather than left to leak into a later seed's world.
	_deck_chunks.clear()
	for trunk: Dictionary in BikePaths.trunks(terrain):
		for row_v: Variant in (trunk["bridges"] as Array):
			var row: Dictionary = row_v
			decks += 1
			# --- B1b. EVERY SLAB OF THE ROW IS DRAWN, in whatever chunk the centre rule
			# gave it. See the banner: this is the control on the box merge, and the
			# slabs it is really about are the two RAMPS, which reach furthest from the
			# stations the route's own box was built from.
			var mid := Vector2.INF
			for slab_v: Variant in FieldBridges._field_bridge_slabs(row):
				var slab: Dictionary = slab_v
				var at: Vector2 = Vector2(slab["start"]) \
						+ (slab["dir"] as Vector2) * float(slab["len"]) * 0.5
				var ramp: bool = float(slab["y_a"]) < FieldBridges.FIELD_BRIDGE_TOP \
						or float(slab["y_b"]) < FieldBridges.FIELD_BRIDGE_TOP
				if _deck_box_at(terrain, at) == INF:
					_fail("B1b: trunk %d's deck carries a %s centred at %s, and the chunk %s "
							% [int(trunk["id"]), "ramp" if ramp else "slab", at,
							terrain.world_to_chunk(Vector3(at.x, 0.0, at.y))]
							+ "the centre rule gives it drew no box there. A deck's stone "
							+ "reaches past the stations it was built from, so the route's "
							+ "own bounding box has to be merged with its decks' or the "
							+ "chunk rejects the trunk before the deck pass runs")
					continue
				slabs_tied += 1
				# ...and the WETTEST slab is the one the rest of B1 and all of B3 use:
				# the deck runs on past the banks (it grows until a ramp foot is dry),
				# so the middle of the table is not automatically the middle of the river.
				if mid == Vector2.INF and not ramp \
						and terrain.is_river_at(Vector3(at.x, 0.0, at.y)):
					mid = at
			if mid == Vector2.INF:
				continue   # this crossing's deck slabs all straddle the bank; try the next
			# --- B1. The chunk that owns that slab is the one the centre rule gave it,
			# and `_deck_box_at` above already built it.
			var chunk_pos: Vector2i = terrain.world_to_chunk(Vector3(mid.x, 0.0, mid.y))
			var built: Dictionary = _deck_chunks[chunk_pos]
			var at_world: Vector3 = terrain.chunk_to_world(chunk_pos)
			var best: float = INF
			var hit: Transform3D = Transform3D()
			var found: bool = false
			for entry_v: Variant in (built["batch"] as Array):
				var t: Transform3D = (entry_v as Dictionary)["transform"]
				var world := Vector2(at_world.x + t.origin.x, at_world.z + t.origin.z)
				var d: float = world.distance_to(mid)
				best = minf(best, d)
				if d <= STRIP_TOLERANCE:
					hit = t
					found = true
					break
			if not found:
				_fail("B1: trunk %d has a deck slab centred at %s, over water, so the chunk "
						% [int(trunk["id"]), mid] + "%s owns it — and the nearest box that "
						% chunk_pos + "chunk drew stands %.2f m away. The deck was built for "
						% best + "a span that is not the one under it"
				)
				continue
			# ...and the surface the query answers IS the surface the box draws. The
			# slab box hangs UNDER its walking surface by half its thickness (the
			# city's convention), so the two are one addition apart — and nothing but
			# a real registration in `field_bridges_near` can make them agree.
			# ...AT THIS FAMILY'S OWN WIDTH, which is the second thing the row carries
			# and the one the shipped code was still reading a const for: the deck box
			# is dimensioned (half * 2, thickness, length), so its own +X axis IS the
			# path's width. An 8 m road deck under a 2.4 m strip looks wrong and would
			# pass every count in this file.
			if absf(hit.basis.x.length() - BikePaths.BIKE_PATH_WIDTH) > STRIP_TOLERANCE:
				_fail("B1: trunk %d's deck at %s is %.2f m wide and the strip it carries is "
						% [int(trunk["id"]), mid, hit.basis.x.length()]
						+ "%.2f m. The deck was built at somebody else's half-width"
						% BikePaths.BIKE_PATH_WIDTH)
			var drawn_surface: float = hit.origin.y + FieldBridges.FIELD_BRIDGE_THICKNESS * 0.5
			var asked: float = terrain.field_bridge_surface_y(Vector3(mid.x, 0.0, mid.y))
			if absf(asked - drawn_surface) > BRIDGE_Y_TOLERANCE:
				_fail("B1: trunk %d draws its deck at %s with a walking surface at %.3f m, "
						% [int(trunk["id"]), mid, drawn_surface]
						+ "and field_bridge_surface_y() answers %.3f m there. The stone a "
						% asked + "player stands on and the surface every spawner asks about "
						+ "have come apart — or the strip is painted at ground level over the "
						+ "deck rather than being it")
			# ...and the chunk that drew it CARRIES A MARKER for this edge. That is not
			# bookkeeping: check 1 slices this family out of the CUBE bucket using
			# `batch_start` / `cube_start` off the first marker in the chunk, so a chunk
			# whose whole share is a deck — which is the ordinary shape of the middle of
			# a crossing, where every segment is wet and none is painted — would
			# otherwise hand the A/B a run of boxes it cannot cut out.
			var claimed: bool = false
			var bare_deck: bool = true
			for row2: Dictionary in (built["paths"] as Array[Dictionary]):
				if int(row2["edge"]) != int(trunk["id"]):
					continue
				claimed = true
				if not (row2["segments"] as PackedInt32Array).is_empty():
					bare_deck = false
			if not claimed:
				_fail("B1: chunk %s drew trunk %d's deck and left no marker, so check 1 "
						% [chunk_pos, int(trunk["id"])] + "cannot cut this family's boxes "
						+ "out of the CUBE bucket and the kill-switch A/B would report the "
						+ "bike paths as having moved somebody else's geometry")
			elif bare_deck:
				deck_only += 1
			# --- B3. A body ON the deck is out of the water; a body UNDER it is not.
			var on_deck := Vector3(mid.x, FieldBridges.FIELD_BRIDGE_TOP, mid.y)
			if terrain.is_wading_at(on_deck):
				_fail("B3: a hero standing on trunk %d's deck at %s reads as WADING. A "
						% [int(trunk["id"]), mid] + "bridge you wade is not a bridge")
			if terrain.deep_channel_push(on_deck) != Vector3.ZERO:
				_fail("B3: the deep channel pushes a hero standing on trunk %d's deck at %s "
						% [int(trunk["id"]), mid] + "off it. This is the property that makes "
						+ "a trunk crossing walkable at all")
			if not terrain.is_wading_at(Vector3(mid.x, 0.0, mid.y)):
				_fail("B3's control failed at %s: a body at GROUND level there does not read "
						% mid + "as wading either, so the two assertions above hold for dry "
						+ "ground and prove nothing")
			# --- B4. The kill switch, over this deck's own window.
			_bridge_kill_switch(terrain_script, terrain, mid)
			tied += 1
	if decks == 0:
		_fail("B1 found no trunk bridge at all on seed %d, so this bead's named world tie "
				% SEEDS[0] + "was never made. Either no route crosses water on that seed or "
				+ "the scan is dead — re-derive the seed rather than trusting this")
	elif tied == 0:
		_fail("B1 walked %d trunk decks and tied not one of them to the water underneath it. "
				% decks + "Every other assertion in this file compares a build to a build")
	if slabs_tied == 0 and decks > 0:
		_fail("B1b tied not one slab of %d decks to a drawn box, so the box merge has no "
				% decks + "control at all")
	print("bike trunks B1: %d of %d decks on seed %d were tied box-for-box to the river span "
			% [tied, decks, SEEDS[0]] + "that produced them, over %d slabs and ramps; %d of "
			% [slabs_tied, deck_only] + "those chunks drew a deck and no strip at all, which "
			+ "is the case check 1's slice needs a marker for")
	terrain.free()
	Sentinel.done("trunk_bridges")


var _deck_chunks: Dictionary = {}

func _deck_box_at(terrain: Node3D, at: Vector2) -> float:
	"""
	How far the nearest box in the batch of `at`'s OWN chunk stands from it, or INF
	when that chunk drew nothing within `STRIP_TOLERANCE`.

	The chunk is the one the shipped `world_to_chunk` gives the point, which is the
	centre rule the emitter slices every slab by — so this asks the same question
	the geometry answers, never a rect intersection of its own.

	MEMOIZED PER CHUNK, because a deck's slabs share two or three chunks between
	them and `_spawn_bare` drives the whole two-tier spawner. Dropped by the caller
	when it changes terrain.
	"""
	var chunk_pos: Vector2i = terrain.world_to_chunk(Vector3(at.x, 0.0, at.y))
	if not _deck_chunks.has(chunk_pos):
		_deck_chunks[chunk_pos] = _spawn_bare(terrain, chunk_pos)
	var built: Dictionary = _deck_chunks[chunk_pos]
	var origin: Vector3 = terrain.chunk_to_world(chunk_pos)
	var best: float = INF
	for entry_v: Variant in (built["batch"] as Array):
		var t: Transform3D = (entry_v as Dictionary)["transform"]
		best = minf(best, Vector2(origin.x + t.origin.x,
				origin.z + t.origin.z).distance_to(at))
	return INF if best > STRIP_TOLERANCE else best


func _bridge_kill_switch(terrain_script: GDScript, on: Node3D, at: Vector2) -> void:
	"""
	B4 — `field_bridges_near()` over one deck's window, with the family off.

	The rows the ROAD and the APPROACH CORRIDOR put there must be byte-for-byte
	what they were before this bead, and this family's own must be gone. Compared
	as POLYLINES rather than as row identities, because a row is a Dictionary and
	two builds never share one.
	"""
	var off: Node3D = _terrain(terrain_script, SEEDS[0], false)
	var x0: float = at.x - BRIDGE_WINDOW
	var x1: float = at.x + BRIDGE_WINDOW
	var mine: int = 0
	var theirs: Array[String] = []
	for row_v: Variant in on.field_bridges_near(x0, x1):
		var row: Dictionary = row_v
		if bool(row.get("bike", false)):
			mine += 1
			continue
		theirs.append(var_to_bytes(row["poly"]).hex_encode())
	var without: Array[String] = []
	for row_v: Variant in off.field_bridges_near(x0, x1):
		var row: Dictionary = row_v
		if bool(row.get("bike", false)):
			_fail("B4: with spawn_bike_paths off, field_bridges_near() still hands back a "
					+ "bike deck near %s. The flag turns off the boxes but not the queries, "
					% at + "so the world still has invisible stone in it")
		without.append(var_to_bytes(row["poly"]).hex_encode())
	theirs.sort()
	without.sort()
	if theirs != without:
		_fail("B4: near %s the road's and the corridor's own bridges are %d with this family "
				% [at, theirs.size()] + "on and %d with it off. This bead threaded a `half` "
				% without.size() + "parameter through the deck builder and must have moved "
				+ "the road's stone doing it")
	if mine == 0:
		_fail("B4 compared a window around %s that holds no bike deck at all, so 'the flag "
				% at + "removes them' was asserted of nothing")
	off.free()


func _check_bridge_x_window(terrain_script: GDScript) -> void:
	"""
	B5 — `field_bridges_near()` REJECTS A BIKE DECK ON ITS WHOLE X EXTENT, not on
	its two endpoints.

	The window scan's two older sources are MONOTONE IN X by construction — the
	coin road's stations advance in X, and so does the approach corridor — so it
	tests `poly[0].x` and `poly[-1].x` and that is exactly right for them. A TRUNK
	runs between two anchors and may head due north and come back, so its endpoints
	say nothing about how far west or east its stone reached. The row therefore
	carries a `box`, computed once over every point when it is built.

	THE ROW CARRIES A `box` AND THE SCAN REJECTS ON IT. That box is also the
	per-chunk reject at the emission site, so getting it wrong is two defects and
	not one.

	IT IS A UNIT ASSERTION ON A HAND-BUILT ROW, and deliberately so. The difference
	between the two rules only shows on a deck whose extremes are not its ends, and
	whether any CI seed grows one is precisely the population question that makes a
	behavioural check vacuous — the endpoint rule was measured to survive every
	assertion in this file on all three seeds. So the row is made to order: a deck
	that runs due north with a 60 m westward bulge in the middle, stuffed into the
	trunk memo the way T3a stuffs a synthetic route, and a window placed WEST of its
	endpoints and reaching the bulge. Nothing else about it is synthetic — it goes
	through the shipped `field_bridges_near()` and the shipped reach.
	"""
	var terrain: Node3D = _terrain(terrain_script, SEEDS[0], true)
	var reach: float = FieldBridges._field_bridge_reach(terrain)
	# Far off the road, so the road's and the corridor's own rows cannot be confused
	# with this one, and far enough north that nothing else is near.
	var east: float = X_WINDOW_EAST
	var poly := PackedVector2Array([
		Vector2(east, -80.0), Vector2(east - X_WINDOW_BULGE, -40.0),
		Vector2(east - X_WINDOW_BULGE, 40.0), Vector2(east, 80.0),
	])
	var lo: Vector2 = Vector2(INF, INF)
	var hi: Vector2 = Vector2(-INF, -INF)
	for pt: Vector2 in poly:
		lo = lo.min(pt)
		hi = hi.max(pt)
	var pad: float = FieldBridges.field_bridge_outer_reach(
			BikePaths.BIKE_PATH_WIDTH * 0.5)
	var along := PackedFloat32Array([0.0])
	for i in range(1, poly.size()):
		along.append(along[i - 1] + poly[i].distance_to(poly[i - 1]))
	var row: Dictionary = {
		"poly": poly, "along": along, "half": BikePaths.BIKE_PATH_WIDTH * 0.5,
		"k0": -1, "k1": -1, "bike": true,
		"box": Rect2(lo - Vector2(pad, pad), hi - lo + Vector2(pad, pad) * 2.0),
	}
	# Typed, because `trunks()` hands the memo straight back under an
	# `Array[Dictionary]` annotation. An empty station list and an empty box mean the
	# spawner can never draw this route — only the window scan ever sees it.
	var only: Array[Dictionary] = [{
		"id": SYNTHETIC_EDGE_ID, "a": -1, "b": -2, "stations": [] as Array[Dictionary],
		"box": Rect2(), "from": poly[0], "to": poly[poly.size() - 1],
		"bridges": [row],
	}]
	terrain._bike_trunk_cache["trunks"] = only
	# A window whose padded eastern edge falls BETWEEN the bulge and the endpoints:
	# the extent test keeps the row, the endpoint test throws it away.
	var x1: float = east - reach - X_WINDOW_BULGE * 0.5
	if not (lo.x - pad <= x1 + reach and poly[0].x > x1 + reach):
		_fail("B5 built a window that does not discriminate between the two rules "
				+ "(west stone at %.1f, endpoints at %.1f, window edge at %.1f) — the "
				% [lo.x - pad, poly[0].x, x1 + reach] + "assertion below would hold under "
				+ "either, so retune X_WINDOW_BULGE against the current reach")
	var found: bool = false
	for row_v: Variant in terrain.field_bridges_near(x1 - 1.0, x1):
		if (row_v as Dictionary).get("bike", false):
			found = true
	if not found:
		_fail("B5: a bike deck reaching west to x = %.1f was not returned for the window "
				% (lo.x - pad) + "[%.1f, %.1f], which its stone reaches into. The X rejection is "
				% [x1 - 1.0, x1] + "reading the polyline's ENDPOINTS (x = %.1f), and a trunk "
				% poly[0].x + "may run due north — so a chunk near the edge of the scan "
				+ "window is told there is no deck over water there")
	# ...and the control: a window this deck's stone really cannot reach must NOT
	# return it, or B5 would pass on a source that rejects nothing at all.
	var far: float = lo.x - pad - reach - X_WINDOW_BULGE
	for row_v: Variant in terrain.field_bridges_near(far - 1.0, far):
		if (row_v as Dictionary).get("bike", false):
			_fail("B5's control failed: the same deck came back for a window %.0f m west "
					% (lo.x - pad - far) + "of its westernmost stone, so the source rejects "
					+ "nothing and the assertion above holds for free")
	terrain.free()
	Sentinel.done("bridge_x_window")


func _check_deck_probe_width(terrain_script: GDScript) -> void:
	"""
	B6 — THE DECK-WIDE WET PROBE REACHES ITS FAR EDGE, at a width that is not a
	whole number of probe steps.

	`FieldBridges._field_bridge_dry_across` walks lanes from `-half` outward at
	`FIELD_BRIDGE_PROBE_STEP` and clamps the last one back onto `+half`. Whether
	that clamp is ever reached depends on the loop bound, and the bound was written
	for a width the step divides: the road's 8.0 at 1.0 lands a lane exactly on the
	edge, and this family's 1.2 does not — its +1.2 m edge was never sampled at all,
	so a deck could be called dry across a section with water under one rail.

	IT IS A UNIT ASSERTION ON A CONSTRUCTED SECTION, for B5's reason. The defect
	only shows where the water starts INSIDE the last step, and whether any seed
	grows a ramp positioned like that is exactly the population question that makes
	a behavioural check vacuous — B2b walks every ramp rectangle in eight seeds and
	stayed green with the bound reverted (measured, mutation M11). So the section is
	found rather than waited for: a wet point with every lane below it dry, which is
	a river's own EDGE, and the probe centred half a deck short of it.

	The search itself is the non-vacuity guard — it fails if the world it scanned
	held no river edge at all, because then nothing was asked.
	"""
	var terrain: Node3D = _terrain(terrain_script, SEEDS[0], true)
	var half: float = BikePaths.BIKE_PATH_WIDTH * 0.5
	# `_field_bridge_dry_across` takes its normal as (-dir.y, dir.x), so a section
	# running east samples along +Z and the far edge is the one at +half.
	var dir := Vector2.RIGHT
	var tested := false
	var x: float = PROBE_SCAN_RECT.position.x
	while x < PROBE_SCAN_RECT.end.x and not tested:
		var z: float = PROBE_SCAN_RECT.position.y
		while z < PROBE_SCAN_RECT.end.y:
			z += PROBE_SCAN_STEP
			var edge := Vector2(x, z)
			if not terrain.is_river_at(Vector3(edge.x, 0.0, edge.y)):
				continue
			# The probe centred so that `edge` is exactly its far lane. Every lane
			# BELOW that must be dry, or both bounds answer "wet" and the case
			# discriminates nothing.
			var centre: Vector2 = edge - Vector2(0.0, half)
			var clean: bool = true
			var lane: float = -half
			while lane < half - EDGE_EPS_LOCAL:
				if terrain.is_river_at(Vector3(centre.x, 0.0, centre.y + lane)):
					clean = false
					break
				lane += FieldBridges.FIELD_BRIDGE_PROBE_STEP
			if not clean:
				continue
			tested = true
			if FieldBridges._field_bridge_dry_across(terrain, centre, dir, half):
				_fail("B6: a %.1f m section centred at %s reads as DRY ALL THE WAY ACROSS, "
						% [half * 2.0, centre] + "and the river starts at %s — its own far "
						% edge + "edge. The lane walk is stopping short of `half`, so a deck "
						+ "of this width can be built with water under one of its rails")
			break
		x += PROBE_SCAN_STEP_X
	if not tested:
		_fail("B6 scanned %s and found no river edge with dry ground a deck's width behind "
				% PROBE_SCAN_RECT + "it, so the probe's far lane was never once exercised. "
				+ "Retune PROBE_SCAN_RECT against the current seed")
	terrain.free()
	Sentinel.done("deck_probe_width")


func _check_no_paint_on_water(terrain_script: GDScript) -> void:
	"""
	B2 — NO SEGMENT OF THIS FAMILY'S PAINT IS EVER LAID ON OPEN WATER, swept over
	every truncation seed, and the number of CROSSINGS it found is printed.

	Child `.3` is the one that could break this: before it, a wet trunk segment was
	simply skipped, and the skip is still there — but a crossing now also grows a
	DECK, and the failure mode of getting that wrong is a strip drawn at y = 0
	across the river with a bridge beside it. So the sweep is over the STRIP boxes
	alone (picked out by their height, `BIKE_PATH_THICKNESS * 0.5`, the only box
	this family puts there — a deck slab stands a metre and a half up), and the
	question asked of each is the shipped `is_river_at`.

	TIER-BLIND, like T5 and for the same reason: a SPUR over water is the same
	defect on the same grounds, and `_station_blocked` test 5 plus
	`segment_blocked`'s half-step are what keep one out today. If this ever fires
	on a spur it is a finding, not a false alarm.

	IT FAILS ON ZERO CROSSINGS, because a sweep of seeds where no route ever meets
	a river asserts nothing at all — and it prints how many of those crossings got
	a deck, which is the measurement this bead is judged on.

	**B2b — AND EVERY DECK'S RAMP RECTANGLE IS DRY, walked HERE.** That is the
	control on the deck-wide wet probe, and it has to be an independent walk or it
	is no control at all: asking `FieldBridges._field_bridge_dry_across` would ask
	the function under test. So this samples the whole rectangle itself, at a
	quarter metre in both axes and with BOTH edges included, and it is over eight
	seeds because whether any one of them grows a ramp whose edge clips the water
	is a population question. A ramp is the one piece of a bridge that is under
	`WADE_SURFACE_MAX` for its first stretch, so a wet edge there is a hero wading
	on a bridge.
	"""
	var crossings: int = 0
	var bridged: int = 0
	var bare: int = 0
	var strips_seen: int = 0
	var ramps: int = 0
	for seed_value: int in TRUNCATION_SEEDS:
		var terrain: Node3D = _terrain(terrain_script, seed_value, true)
		for trunk: Dictionary in BikePaths.trunks(terrain):
			# --- B2b. The ramps, walked by this file and not by the builder.
			for row_v: Variant in (trunk["bridges"] as Array):
				var row: Dictionary = row_v
				var half: float = row["half"]
				for slab_v: Variant in FieldBridges._field_bridge_slabs(row):
					var slab: Dictionary = slab_v
					if float(slab["y_a"]) >= FieldBridges.FIELD_BRIDGE_TOP \
							and float(slab["y_b"]) >= FieldBridges.FIELD_BRIDGE_TOP:
						continue        # a deck slab; it is MEANT to be over water
					ramps += 1
					var dir: Vector2 = slab["dir"]
					var perp := Vector2(-dir.y, dir.x)
					var run: float = slab["len"]
					var steps: int = maxi(1, int(run / RAMP_PROBE))
					var lanes: int = maxi(1, int(half * 2.0 / RAMP_PROBE))
					for a in steps + 1:
						for b in lanes + 1:
							var at: Vector2 = Vector2(slab["start"]) \
									+ dir * (run * float(a) / float(steps)) \
									+ perp * (half * (2.0 * float(b) / float(lanes) - 1.0))
							if not terrain.is_river_at(Vector3(at.x, 0.0, at.y)):
								continue
							_fail("B2b: seed %d, trunk %d has a RAMP standing in the water "
									% [seed_value, int(trunk["id"])] + "at %s. A ramp is "
									% at + "under WADE_SURFACE_MAX for its first stretch and "
									+ "it is %.1f m wide, so a hero on that edge wades ON a "
									% (half * 2.0) + "bridge. The deck-wide probe is missing "
									+ "part of its section — check that its lane walk really "
									+ "reaches both edges when `half` is not a whole number "
									+ "of probe steps")
							break
			var stations: Array[Dictionary] = trunk["stations"]
			var was_wet: bool = false
			for i in range(stations.size() - 1):
				var a: Vector2 = stations[i]["pos"]
				var b: Vector2 = stations[i + 1]["pos"]
				var mid: Vector2 = (a + b) * 0.5
				var wet: bool = terrain.is_river_at(Vector3(a.x, 0.0, a.y)) \
						or terrain.is_river_at(Vector3(b.x, 0.0, b.y)) \
						or BikePaths.segment_blocked(terrain, a, b)
				if not wet:
					was_wet = false
					continue
				if not was_wet:
					crossings += 1
					if terrain.field_bridge_surface_y(Vector3(mid.x, 0.0, mid.y)) > -INF:
						bridged += 1
					else:
						bare += 1
				was_wet = true
				# The chunk the midpoint rule gives this segment, built through the
				# SHIPPED spawner — and every strip box in it measured, not only this
				# segment's, so a neighbour laid over the same water is caught too.
				var chunk_pos: Vector2i = terrain.world_to_chunk(Vector3(mid.x, 0.0, mid.y))
				var built: Dictionary = _spawn_bare(terrain, chunk_pos)
				for world: Vector2 in _strip_positions(terrain, chunk_pos, built["batch"]):
					strips_seen += 1
					if terrain.is_river_at(Vector3(world.x, 0.0, world.y)):
						_fail("B2: seed %d, chunk %s draws a bike STRIP at %s — at ground "
								% [seed_value, chunk_pos, world] + "level, in a river band. "
								+ "A crossing is carried on a deck at %.2f m or it is not "
								% FieldBridges.FIELD_BRIDGE_TOP + "carried at all; paint on "
								+ "the water is a strip the hero wades")
		terrain.free()
	if crossings == 0:
		_fail("B2 swept %d seeds and found no trunk crossing a river at all, so 'no paint on "
				% TRUNCATION_SEEDS.size() + "open water' held for free and this bead's "
				+ "subject was never once exercised")
	if bridged == 0:
		_fail("B2 found %d trunk river crossings over %d seeds and not ONE of them carries a "
				% [crossings, TRUNCATION_SEEDS.size()] + "deck. Every crossing being refused "
				+ "is what this bead looks like when it is dead — a wet probe wider than the "
				+ "deck, a scan that never finds a bank, or a filter that drops every row")
	if strips_seen == 0:
		_fail("B2 built the chunks around %d crossings and found no strip box in any of "
				% crossings + "them, so the sweep measured nothing")
	if ramps == 0 and bridged > 0:
		_fail("B2b walked %d bridged crossings and found no ramp slab in any of them, so "
				% bridged + "the deck-wide probe's control asserted nothing")
	print("bike trunks B2: %d ramp rectangles walked dry; %d trunk river crossings over %d "
			% [ramps, crossings, TRUNCATION_SEEDS.size()] + "seeds — %d carry a deck, %d are "
			% [bridged, bare] + "left as bare gaps (a "
			+ "bank with no dry abutment, or a crossing inside a keep-out). %d strip boxes "
			% strips_seen + "were measured against the water and none stands in it")
	Sentinel.done("no_paint_on_water")


# ============================================================================
# T4 — what the trunk memo costs, and that it is really seeded
# ============================================================================

func _check_trunk_memo(terrain_script: GDScript) -> void:
	"""
	THE MEMO'S SIZE, PRINTED; and that it is a pure function of `run_seed`.

	The trunk table is built once per run and held on the terrain, so its cost is
	paid by whichever chunk streams in first and its correctness depends entirely
	on `_drop_seeded_memos()` reaching it. Three statements:
	  * its total station count is under `TRUNK_MEMO_STATION_CAP`, and the MEASURED
	    number is PRINTED rather than asserted — the ceiling guards a retuned
	    density knob, not today's world;
	  * dropping the memos and asking again returns the IDENTICAL routes, which is
	    what makes a chunk regenerate the same paint after a round trip out of the
	    streaming radius;
	  * re-seeding CHANGES them, which is the half that fails if
	    `_bike_trunk_cache` were ever left out of the drop list — a memo that
	    outlives a re-seed hands a multiplayer joiner the wrong world.
	The second and third together are `scarcity_selfcheck`'s within-run /
	across-run pair, and neither means anything without the other.
	"""
	var terrain: Node3D = _terrain(terrain_script, SEEDS[0], true)
	var before: Array[Dictionary] = BikePaths.trunks(terrain)
	var stations: int = 0
	var metres: float = 0.0
	for trunk: Dictionary in before:
		var route: Array[Dictionary] = trunk["stations"]
		stations += route.size()
		for i in range(route.size() - 1):
			metres += (route[i]["pos"] as Vector2).distance_to(route[i + 1]["pos"])
	print("bike trunks T4: seed %d holds %d trunks, %d stations and %.0f m of route in "
			% [SEEDS[0], before.size(), stations, metres]
			+ "_bike_trunk_cache (ceiling %d stations)" % TRUNK_MEMO_STATION_CAP)
	if before.is_empty():
		_fail("T4 found an empty trunk memo on seed %d, so its size, its purity and its "
				% SEEDS[0] + "reset are all measured against nothing")
	if stations > TRUNK_MEMO_STATION_CAP:
		_fail("T4: the trunk memo holds %d stations, past the %d ceiling. Every chunk that "
				% [stations, TRUNK_MEMO_STATION_CAP] + "streams in walks this table's "
				+ "bounding boxes, so a density knob or a TRUNK_MAX_EDGE that grew it by an "
				+ "order of magnitude is a per-chunk cost nobody measured")

	var snapshot: PackedByteArray = var_to_bytes(before)
	terrain._drop_seeded_memos()
	if terrain._bike_trunk_cache.has("trunks"):
		_fail("T4: `_drop_seeded_memos()` left `_bike_trunk_cache` filled — a trunk kept "
				+ "across a re-seed is paint laid out for the last world's monuments, and "
				+ "`chunk_stream_selfcheck` check 6 audits the drop list for exactly this")
	if var_to_bytes(BikePaths.trunks(terrain)) != snapshot:
		_fail("T4: the same seed produced different trunks after `_drop_seeded_memos()`. A "
				+ "route must be a pure function of (anchor pair, run_seed), or a chunk redraws "
				+ "different paint every time it streams back in")

	terrain.set_run_seed(SEEDS[1])
	if var_to_bytes(BikePaths.trunks(terrain)) == snapshot:
		_fail("T4: seeds %d and %d produced byte-identical trunk routes, so the network is "
				% [SEEDS[0], SEEDS[1]] + "not seeded at all — or a memo survived the re-seed "
				+ "and the check is comparing one world with itself")
	terrain.free()
	Sentinel.done("trunk_memo")


func _check_drawn_chain_reaches_budapest(terrain_script: GDScript) -> void:
	"""
	CHECK — A DRAWN TRUNK CHAIN CONNECTS THE HQ ANCHOR TO THE GATE ANCHOR, ON
	EVERY GREEN SEED (bead godot-test1-pnvb.7, the owner's headline: "you should
	be able to get to Budapest along them"; owner decision a′ for the sealed ones).

	Not the graph — the DRAWN tier: breadth-first search over the exact from/to
	endpoints of the same `BikePaths.trunks()` rows the spawner draws. The snap
	assigns anchor positions bit-for-bit, so exact Vector2 equality IS the chain;
	a trunk ending at the rect edge connects at its anchor end only, and a link the
	walk abandoned whole is not a link at all.

	TWO ASSERTIONS over DRAWN_CHAIN_SEEDS (the blind eight plus the two failure
	classes): every green seed comes out THERE (failing on zero trunks, naming the
	seed and the stall x), and every sealed seed comes out BROKEN IN ITS RECORDED
	CLASS — "exhausted" (the HQ reach stalls with the frontier spent) or "dangle"
	(a trunk touches the gate but dangles at a rect point). A sealed seed that
	comes out THERE, or in the other class, fails LOUD, so the record can never
	rot: the walk-level fix has to touch DRAWN_CHAIN_SEALED to land. Prints per
	seed (trunks, metres, x-range, THERE/BROKEN-for-reason) plus the abandonment
	reason histogram over the whole list.
	"""
	var reasons := {}
	for seed_value: int in DRAWN_CHAIN_SEEDS:
		var terrain: Node3D = _terrain(terrain_script, seed_value, true)
		var anchors: Array = terrain.bike_anchors()
		var hq := Vector2.INF
		var gate := Vector2.INF
		for row: Dictionary in anchors:
			if str(row["id"]) == "hq":
				hq = row["pos"]
			elif str(row["id"]) == "gate":
				gate = row["pos"]
		if hq == Vector2.INF or gate == Vector2.INF:
			_fail("seed %d: no HQ anchor or no gate anchor — the chain has no ends" % seed_value)
			terrain.free()
			continue
		var edges: Array = terrain.bike_edges()
		var trunks: Array[Dictionary] = BikePaths.trunks(terrain)
		var built := {}
		for trunk: Dictionary in trunks:
			built[int(trunk["id"])] = true
		for edge: Dictionary in edges:
			if built.has(int(edge["id"])):
				continue
			var why: String = BikePaths.trunk_abandoned(terrain, edge)
			reasons[why] = int(reasons.get(why, 0)) + 1
		if trunks.is_empty():
			_fail("seed %d: no trunks drawn at all — the chain cannot start" % seed_value)
			terrain.free()
			continue
		var reach := {hq: true}
		var changed: bool = true
		while changed:
			changed = false
			for trunk: Dictionary in trunks:
				var f: Vector2 = trunk["from"]
				var tt: Vector2 = trunk["to"]
				if reach.has(f) and not reach.has(tt):
					reach[tt] = true
					changed = true
				if reach.has(tt) and not reach.has(f):
					reach[f] = true
					changed = true
		var metres: float = 0.0
		var xmin: float = INF
		var xmax: float = -INF
		for trunk: Dictionary in trunks:
			var route: Array[Dictionary] = trunk["stations"]
			for s: Dictionary in route:
				var x: float = (s["pos"] as Vector2).x
				xmin = minf(xmin, x)
				xmax = maxf(xmax, x)
			for i in range(route.size() - 1):
				metres += (route[i]["pos"] as Vector2).distance_to(route[i + 1]["pos"])
		var reached: bool = reach.has(gate)
		var reached_x: float = -INF
		for p: Vector2 in reach.keys():
			reached_x = maxf(reached_x, p.x)
		if reached:
			print("drawn chain: seed %d holds %d trunks and %d m of route over x %.0f..%.0f; "
					% [seed_value, trunks.size(), int(metres), xmin, xmax]
					+ "the drawn chain to the gate is THERE")
			if DRAWN_CHAIN_SEALED.has(seed_value):
				_fail("seed %d is no longer sealed (%s) — move it to the green list"
					% [seed_value, DRAWN_CHAIN_SEALED[seed_value][0]])
			terrain.free()
			continue
		# BROKEN. Which class? A trunk touching the gate whose far end is a rect
		# point (not any anchor) is the boundary dangle: the approach ended on the
		# rect edge. A gate touched only by snapped island links — or not touched at
		# all — is the exhausted frontier.
		var dangle := false
		for trunk: Dictionary in trunks:
			var f: Vector2 = trunk["from"]
			var tt: Vector2 = trunk["to"]
			if f != gate and tt != gate:
				continue
			var far: Vector2 = tt if f == gate else f
			var far_is_anchor := false
			for row: Dictionary in anchors:
				if row["pos"] == far:
					far_is_anchor = true
					break
			if not far_is_anchor:
				dangle = true
				break
		var actual := "dangle" if dangle else "exhausted"
		if not DRAWN_CHAIN_SEALED.has(seed_value):
			_fail("seed %d: the drawn chain from the HQ stalls at x %.0f with %d m of trunk, "
				% [seed_value, reached_x, int(metres)]
				+ "the gate stands at x %.0f — pass 2b found no strict pair to extend it, "
				% gate.x + "so on this world the owner's headline does not hold")
			terrain.free()
			continue
		var record: Array = DRAWN_CHAIN_SEALED[seed_value]
		if actual != String(record[1]):
			_fail("seed %d is sealed as %s but came out %s — the record rotted, re-survey it"
				% [seed_value, record[0], actual])
			terrain.free()
			continue
		print("drawn chain: seed %d holds %d trunks and %d m of route over x %.0f..%.0f; "
				% [seed_value, trunks.size(), int(metres), xmin, xmax]
				+ "BROKEN for its recorded reason (%s: %s)" % [record[0], actual])
		terrain.free()
	print("drawn chain abandonment reasons over %d seeds: %s" % [DRAWN_CHAIN_SEEDS.size(), str(reasons)])
	Sentinel.done("drawn_chain_reaches_budapest")


# ============================================================================
# HELPERS
# ============================================================================


func _synthetic_trunk(terrain: Node3D, chunk_pos: Vector2i) -> Array[Dictionary]:
	"""
	A STRAIGHT trunk laid east-west through a chunk's centre, for T3a.

	Synthetic and not a real route on purpose: what T3a has to drive is the two
	SCARCITY code paths, and whether any seed happens to grow a trunk at k = 0 is
	exactly the population question that would make the check vacuous. A straight
	line is also the only shape whose owned segments this file can predict without
	re-deriving the midpoint rule — see `_dry_segments_in`.
	"""
	var centre: Vector3 = terrain.chunk_to_world(chunk_pos)
	var out: Array[Dictionary] = []
	for i in T3A_STATIONS:
		var x: float = centre.x \
				+ (float(i) - float(T3A_STATIONS) * 0.5) * BikePaths.BIKE_STATION_SPACING
		out.append({ "pos": Vector2(x, centre.z), "heading": 0.0 })
	return out


func _synthetic_poles(terrain: Node3D, chunk_pos: Vector2i) -> int:
	"""
	How many poles a synthetic straight trunk through `chunk_pos` would stand there.

	T3a's control screen. It drives the SHIPPED `spawn_bike_path_in_chunk` over the
	shipped memo — the same production path the assertion itself runs — so the screen
	and the assertion cannot disagree about what a pole needs. It costs one spawner
	call per candidate and the search normally ends on its first.

	IT LEAVES THE MEMO HOLDING THE CANDIDATE'S ROUTE, which is harmless: the caller
	overwrites it for every site it tests, and the terrain is freed at the end of the
	check.
	"""
	var stations: Array[Dictionary] = _synthetic_trunk(terrain, chunk_pos)
	var only: Array[Dictionary] = [{
		"id": SYNTHETIC_EDGE_ID, "a": -1, "b": -2, "stations": stations,
		"box": BikePaths._trunk_box(stations),
		"from": stations[0]["pos"], "to": stations[-1]["pos"],
		# Child `.3`: a synthetic route crosses no water, so it needs no deck — and
		# the key is PRESENT because the spawner reads it unguarded, which is what
		# keeps a real trunk that lost its decks a loud failure rather than a quiet one.
		"bridges": [],
	}]
	terrain._bike_trunk_cache["trunks"] = only
	var built: Dictionary = _spawn_bare(terrain, chunk_pos)
	for row: Dictionary in (built["paths"] as Array[Dictionary]):
		if int(row["edge"]) == SYNTHETIC_EDGE_ID:
			return (row["poles"] as PackedInt32Array).size()
	return 0


func _dry_segments_in(terrain: Node3D, stations: Array[Dictionary],
		chunk_pos: Vector2i, waypoints: Array[Dictionary]) -> int:
	"""
	How many of a route's segments this chunk owns AND is allowed to draw.

	The midpoint rule is asked of the SHIPPED `world_to_chunk`, and the water test
	is the shipped pair (`is_river_at` at both ends, `segment_blocked` between) —
	so this predicts the strip count without owning a second copy of either rule.
	"""
	var n: int = 0
	for i in range(stations.size() - 1):
		var a: Vector2 = stations[i]["pos"]
		var b: Vector2 = stations[i + 1]["pos"]
		var mid: Vector2 = (a + b) * 0.5
		if terrain.world_to_chunk(Vector3(mid.x, 0.0, mid.y)) != chunk_pos:
			continue
		if terrain.is_river_at(Vector3(a.x, 0.0, a.y)) \
				or terrain.is_river_at(Vector3(b.x, 0.0, b.y)) \
				or BikePaths.segment_blocked(terrain, a, b):
			continue
		if BikePaths.trunk_keep_out(terrain, a, waypoints) \
				or BikePaths.trunk_keep_out(terrain, b, waypoints) \
				or BikePaths.trunk_keep_out(terrain, (a + b) * 0.5, waypoints):
			continue
		n += 1
	return n


func _strips_on(terrain: Node3D, chunk_pos: Vector2i, batch: Array,
		stations: Array[Dictionary]) -> int:
	"""
	How many strip boxes in `batch` stand on one of `stations`' segment midpoints.

	POSITION-MATCHED AND NOT COUNTED, because T3a's near site is a real corridor
	chunk that also carries spurs: a bare count of the strips in that batch would
	be measuring somebody else's paint. Matching against the synthetic route's own
	midpoints is also a second, cheap world tie.
	"""
	var at: Vector3 = terrain.chunk_to_world(chunk_pos)
	var n: int = 0
	for entry_v: Variant in batch:
		var t: Transform3D = (entry_v as Dictionary)["transform"]
		if not is_equal_approx(t.origin.y, BikePaths.BIKE_PATH_THICKNESS * 0.5):
			continue
		var world := Vector2(at.x + t.origin.x, at.z + t.origin.z)
		for i in range(stations.size() - 1):
			var mid: Vector2 = ((stations[i]["pos"] as Vector2)
					+ (stations[i + 1]["pos"] as Vector2)) * 0.5
			if world.distance_to(mid) <= STRIP_TOLERANCE:
				n += 1
				break
	return n

func _terrain(terrain_script: GDScript, seed_value: int, paths_on: bool) -> Node3D:
	"""
	A REAL terrain in the tree on `seed_value`, with the crocodile scene check 1
	needs. `waypoint_selfcheck` / `landmark_sites_selfcheck`'s recipe, and both
	halves of it matter: IN THE TREE because `create_chunk` parents its chunk to
	it and several spawners ask that chunk for a global transform, and SEEDED
	AFTER `add_child` because `_ready()` rolls its own seed and would throw an
	earlier one away.

	It never streams on its own: `_ready` finds no node in group "player", so
	`player` stays null and `_process` returns immediately.
	"""
	var terrain := Node3D.new()
	terrain.set_script(terrain_script)
	terrain.crocodile_scene = load(CROC_SCENE)
	terrain.spawn_bike_paths = paths_on
	root.add_child(terrain)
	terrain.set_run_seed(seed_value)
	return terrain


func _spawn_bare(terrain: Node3D, chunk_pos: Vector2i) -> Dictionary:
	"""
	Run the SHIPPED spawner alone into a throwaway batch, body and chunk, and
	return what it produced with every node freed again.

	@return: `{ "batch": Array, "obstacles": Array, "poles": int,
	            "paths": Array[Dictionary], "racks": int }`. `poles` is the chunk's
	          TOTAL pole count; `racks` the chunk's TOTAL bike-stand rack count
	          (bead `godot-test1-z2yv.3`); `paths` is one row per marker, carrying
	          that marker's whole
	          meta: `origin`, `segments`, `poles` (this path's own poles, as
	          CUBE-BUCKET indices — see check 9's banner for why that is not the
	          batch index, though in this helper's empty CUBE-only batch the two
	          coincide, which is what lets check 7c index the batch with them),
	          `tops` (one per pole) and `signals` (each head's first lens).

	An EMPTY `obstacles` on purpose, in the checks that count footprints: with
	nothing already built no pole is skipped, so the pole count is the stride's
	own and the assertion is about this family rather than about whatever the
	chunk's blocks happened to be. Check 1 is the one that runs the real pipeline.
	"""
	var batch: Array = []
	var obstacles: Array = []
	var body := StaticBody3D.new()
	var chunk := MeshInstance3D.new()
	BikePaths.spawn_bike_path_in_chunk(terrain, chunk_pos, chunk, obstacles, batch, body)
	var paths: Array[Dictionary] = []
	var poles: int = 0
	for marker: Node in _markers(chunk):
		var mine: PackedInt32Array = marker.get_meta("poles")
		poles += mine.size()
		paths.append({
			"origin": marker.get_meta("origin"),
			"segments": marker.get_meta("segments"),
			"poles": mine,
			# Child `.2`: what each of those poles carries, and each signal head's
			# first lens in CUBE-bucket coordinates. Checks 7-9.
			"tops": marker.get_meta("tops"),
			"signals": marker.get_meta("signals"),
			# Child `pnvb.2`: -1 for a SPUR, the edge id for a TRUNK. Check 2d and
			# T1 tell the two tiers apart with it rather than by re-deriving
			# anything from a position.
			"edge": int(marker.get_meta("edge")),
		})
	var stands: int = 0
	for child: Node in chunk.get_children():
		if child.is_in_group(BikePaths.BIKE_STAND_GROUP):
			stands += 1
	# Everything this call built is freed here — a self-check that leaked a node
	# per chunk over a 29x29 sweep would be the slowest check in the suite.
	chunk.free()
	body.free()
	return { "batch": batch, "obstacles": obstacles, "poles": poles, "paths": paths,
			"racks": stands }


func _markers(chunk: Node) -> Array[Node]:
	## This family's bare Node3Ds, found BY GROUP the way the game finds them.
	var out: Array[Node] = []
	for child: Node in chunk.get_children():
		if child.is_in_group(BikePaths.BIKE_PATH_GROUP):
			out.append(child)
	return out


func _strip_positions(terrain: Node3D, chunk_pos: Vector2i, batch: Array) -> Array[Vector2]:
	"""
	The WORLD XZ centre of every STRIP box in `batch`.

	A strip is picked out by its height alone — `BIKE_PATH_THICKNESS * 0.5`, the
	only box this family puts there (the dashes ride on top of it and the posts
	stand half their own height up) — so this needs no index and no meta, which
	is what keeps it independent of the bookkeeping the rest of the file trusts.

	World, not chunk-local: the chunk node stands at `chunk_to_world(chunk_pos)`
	and a batch entry's transform origin is relative to it, so this is the sum.
	"""
	var at: Vector3 = terrain.chunk_to_world(chunk_pos)
	var out: Array[Vector2] = []
	for entry_v: Variant in batch:
		var t: Transform3D = (entry_v as Dictionary)["transform"]
		if not is_equal_approx(t.origin.y, BikePaths.BIKE_PATH_THICKNESS * 0.5):
			continue
		out.append(Vector2(at.x + t.origin.x, at.z + t.origin.z))
	return out


func _multimesh_table(chunk: Node) -> Dictionary:
	## Every `BlockMultiMesh*` child as name -> [[transform, colour], ...], which
	## is the batch as it survived into the GPU buffer.
	##
	## READ THIS BEFORE TRUSTING WHAT A COMPARISON OF TWO OF THESE PROVES (measured
	## at bead `.2`): under the dummy rendering server `--headless` runs on, MultiMesh
	## instance data is WRITE-ONLY — `get_instance_transform()` returns the identity
	## and `get_instance_color()` opaque black for every instance, and `buffer` comes
	## back empty. So the rows below are placeholders, and what a table-against-table
	## comparison really asserts is the BUCKET NAMES and each bucket's
	## `instance_count`. That is still the whole of check 5's claim and most of check
	## 1's (a stray draw changes a count), but the geometry itself is pinned by check
	## 2c, which reads `block_batch` directly — the batch is a plain Array of
	## Dictionaries and every field in it is real.
	var out: Dictionary = {}
	for child: Node in chunk.get_children():
		if not (child is MultiMeshInstance3D):
			continue
		var mm: MultiMesh = (child as MultiMeshInstance3D).multimesh
		var rows: Array = []
		for i in mm.instance_count:
			rows.append([mm.get_instance_transform(i), mm.get_instance_color(i)])
		out[String(child.name)] = rows
	return out


func _node_table(chunk: Node) -> Array[String]:
	## Every chunk-parented NODE — crocodiles, coins, accents — as a sorted list of
	## descriptors. This is the half of check 1 that catches a stray draw from the
	## shared chunk stream, since one extra draw slides every body in the chunk.
	## The batch's own children and this family's markers are excluded: they are
	## compared by the MultiMesh table and by the slice respectively.
	var out: Array[String] = []
	for child: Node in chunk.get_children():
		if child is MultiMeshInstance3D or String(child.name) == BLOCK_BODY:
			continue
		if child.is_in_group(BikePaths.BIKE_PATH_GROUP):
			continue
		var at: Vector3 = (child as Node3D).position if child is Node3D else Vector3.ZERO
		# CLASS AND POSITION, NEVER THE NODE NAME. Godot auto-names an unnamed
		# instance with a process-wide counter, so the two terrains this check
		# builds side by side would disagree about every generated name while
		# agreeing about every position — the one difference that means nothing.
		out.append("%s|%.4f,%.4f,%.4f" % [child.get_class(), at.x, at.y, at.z])
	out.sort()
	return out


func _signal_timer(chunk: Node) -> Timer:
	## The first traffic head's cycle Timer in a built chunk. It hangs off this
	## family's MARKER rather than off the chunk itself — see
	## `BikePaths.SIGNAL_TIMER_NAME` for why — so this walks one level deeper than
	## `_markers` does.
	for marker: Node in _markers(chunk):
		for child: Node in marker.get_children():
			if child is Timer:
				return child as Timer
	return null


func _same_color(a: Color, b: Color) -> bool:
	## Equal to within float precision — see `COLOR_TOLERANCE`. Read off BATCH
	## ENTRIES, never off a built MultiMesh: instance data is write-only under the
	## headless dummy renderer (check 9's docstring carries that measurement).
	return absf(a.r - b.r) <= COLOR_TOLERANCE and absf(a.g - b.g) <= COLOR_TOLERANCE \
			and absf(a.b - b.b) <= COLOR_TOLERANCE


func _shape_count(chunk: Node) -> int:
	## How many collision shapes hang on the chunk's single shared block body.
	for child: Node in chunk.get_children():
		if String(child.name) == BLOCK_BODY:
			return child.get_child_count()
	return 0
