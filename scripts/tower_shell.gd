class_name TowerShell
extends Node3D
## THE TOWER — GastroDefense HQ, the building itself (epic godot-test1-3iy, phase 2).
##
## Phase 1 decided WHERE the tower stands (`endless_terrain.tower_site()`) and kept
## that disc clear (`tower_excludes()`, radius `TOWER_RADIUS`). This file is what
## stands there: a sealed 80 x 80 x 52 m block, ONE ring of walls with one hole in
## it, a yard slab and the door trigger the interior hangs off. Phase 13 grew the
## envelope to the ten-storey HQ and, more importantly, put a LID on it — see
## `ROOF_THICK`. Bead godot-test1-dn8 then demolished the 20 m keep phase 3's
## interior was authored inside, so there is one wall line again (see the headstone
## where `KEEP_HALF` used to be).
##
## SELF-BUILDING, LIKE `ability_effect.gd`. The scene file
## `scenes/tower/tower_shell.tscn` is a bare Node3D carrying this script — every
## box comes out of `boxes()` below at `_ready()`. That is not laziness dressed as
## architecture, it buys three things a hand-authored .tscn cannot:
##
##   * ONE TABLE, TWO BUILDINGS. `build_impostor()` reads the SAME table, so the
##     far-away silhouette the player steers toward and the building they arrive at
##     are the same shape by construction rather than by somebody remembering to
##     edit both. (See the impostor block below for why there is one at all.)
##   * THE BUDGET IS CHECKABLE. `tower_shell_selfcheck.gd` counts and measures the
##     table without instancing anything, the discipline `landmark_selfcheck.gd`
##     applies to the procedural landmarks.
##   * THE DOORWAY CANNOT DRIFT SHUT. The two front jambs and the door trigger are
##     all derived from `DOOR_HALF_WIDTH` / `DOOR_HEIGHT`, so there is no second
##     number that has to agree with a first one.
##
## WHAT THIS IS NOT: chunk content. It never touches `create_box()` /
## `block_batch` / the per-chunk MultiMesh (CLAUDE.md's "everything in the world is
## spawned procedurally from the terrain" is about the streamed field; this is one
## authored building at one authored place). It is instanced ONCE and parented to
## the terrain MANAGER, never to a chunk — the fauna precedent — so chunk unloading
## can never free it out from under a player standing in the doorway.
##
## MULTIPLAYER: nothing to sync. `tower_site()` is a CONSTANT (the HQ is hand-
## planned once and forever), so every peer builds the same tower in the same place
## from local information only — it does not even need the seed. No spawn packet,
## no claim, no authority.
##
## COST: 24 `MeshInstance3D`s, ONE `StaticBody3D` holding 7 box shapes, one `Area3D`,
## and 8 materials shared process-wide by the static cache below. That is the whole
## bill, once, for the life of a run. Eleven of those meshes are the castle the
## silhouette bead added (godot-test1-rgt) — all of it above the sealed roof, none of
## it solid, and the 44 merlons of its parapet welded into ONE of the eleven. Four
## more are the Fachwerk facade (godot-test1-rzk), welded the same way: ~810 timbers,
## panels, window recesses and iron bars in FOUR meshes.

# ============================================================================
# SIGNALS
# ============================================================================

## Fired every time a body in the "player" group walks into the doorway volume.
##
## THE DOORWAY IS THE INTERACTION — no prompt, no menu, no key to press: walking
## through it IS entering, exactly like a coin is collected by touching it. Phase 3
## (the interior) is what consumes this; for now the signal plus `entered` is the
## whole contract, and the shell is deliberately inert without a listener.
signal player_entered(body: Node3D)

# ============================================================================
# GEOMETRY — the envelope, in metres, local space, feet at y = 0
# ============================================================================

## Half the building's OUTER footprint. The walls are a 2 * OUTER_HALF square; every
## other horizontal number below derives from this one — and since bd godot-test1-dn8
## demolished the inner keep, it is the ONLY wall line the shell draws.
##
## 10 -> 40 IN PHASE 13 (80 x 80 m). The owner's "100x size" ruling is read as
## usable FLOOR AREA (epic note, 2026-08-29): 16x the footprint times 5x the
## storeys is the 100x, and 80 m square is what ~100-150 hand-planned rooms per
## the epic's phase 14 need. It is ~1.6 chunks across, which is why
## `endless_terrain.TOWER_RADIUS` had to grow with it.
const OUTER_HALF: float = 40.0

## Wall thickness, and the storey grid the height is made of.
##
## PHASE 13 REPLACED A NUMBER WITH A PRODUCT. The height used to be an authored
## 11 m (phase 3 raised it from 7 for two interior storeys); it is now ten storeys
## of 5.0 m, because the owner asked for "a 10-storey building" and the storey
## count is the thing being asked for. 5.0 m clears `tower_interior.SLAB_Y`'s
## floor-to-floor minimum (a storey has to be at least 4.6 m: the jump apex is
## 3.6125 m and a floor you can jump onto is not a floor) with room for a slab.
const WALL_THICK: float = 1.2
const STOREY_HEIGHT: float = 5.0
const STOREYS: int = 10
const WALL_HEIGHT: float = STOREY_HEIGHT * STOREYS

## THE INNER KEEP IS GONE (bd godot-test1-dn8), and this paragraph is its headstone.
##
## `KEEP_HALF` (10 m) and `KEEP_HEIGHT` (11 m) used to stand here: a second six-box
## ring, the phase-3 building preserved inside the phase-13 envelope because the
## interior's floors 0 and 1 were hand-authored against its inner faces. The owner
## looked at it in playtest ("in the castle on the first floor there is a legacy
## prison; we can remove it") and it went — a windowless 20 m box standing in the
## middle of an 80 m hall, roofing nothing and read by nobody as a room.
##
## What replaced it is not geometry here but geometry THERE: floors 0 and 1 are now
## ordinary `TowerPlans.STOREYS` rows on the 40 x 40 grid like storeys 3-10, so their
## walls are cells against the ENVELOPE's inner faces and no width is authored at
## all. The 30 m annulus the ring used to stand in is simply floor now.
##
## Nothing above the roof moved: `KEEP_TOWER_*` / `KEEP_SPIRE_*` in the castle-pass
## block below are the SILHOUETTE's keep — a non-solid mass on the lid, a different
## thing that happens to share the word.

## THE ROOF, which is the whole point of this phase.
##
## The building is sealed: a solid `collide: true` slab over the entire footprint,
## with NO door, NO hatch and no way through it, ever. Windman's Air Rush is the
## only thing in the game that gains real altitude, and the epic's ruling is that
## the tower is entered through the door or not at all — so the answer is not a
## height nobody can reach (see the chain-launch note in
## `tower_shell_selfcheck._check_roof_is_above_windmans_reach`) but a lid.
##
## THICK ENOUGH TO BE THE PARAPET TOO. The slab spans WALL_HEIGHT -> 52 m, so the
## roof surface a flier could stand on is at 52 m — above one fully-skilled Air
## Rush launched from a 20 m massif summit (26.25 + 20 = 46.25 m) with margin, and
## it is one box instead of a slab plus four parapet walls whose tops would each
## be another ledge to reason about.
const ROOF_THICK: float = 2.0

## THE DOORWAY, and the only place its size is written down. The two front jambs
## are what is LEFT of the front wall once this hole is taken out of it, and the
## door trigger spans exactly the hole — so a doorway that drifts shut is a
## contradiction rather than a bug you have to notice. 6 m wide and 4 m tall clears
## a giant Teibi (the character with the largest silhouette) with room to spare.
##
## THE HOLE IS IN THE +X WALL, i.e. it faces back toward the world origin. The tower
## sits on -X (phase 1's ruling) and the player spawns at the origin, so a player who
## walks to the tower walks straight at the doorway instead of round the back.
##
## ONE RING SINCE bd godot-test1-dn8. Phase 13 cut these two numbers TWICE — the
## envelope's hole and the inner keep's, on one line so you walked straight through
## both — and hung the door TRIGGER on the keep's, because "entered the tower" is a
## claim about the rooms and the outer hole only got you into a courtyard. The keep
## is demolished and floor 0 is a planned storey that starts at the outer wall, so
## there is one hole, and `door_trigger_box()` is on it.
const DOOR_HALF_WIDTH: float = 3.0
const DOOR_HEIGHT: float = 4.0

## How far the door trigger reaches on either side of the wall plane. It only has
## to be thicker than the furthest a player travels in one physics tick — the
## fastest run in the game is 9 m/s, i.e. 0.15 m at 60 Hz — so 1 m each way is two
## orders of margin against tunnelling, and short enough that standing outside the
## wall does not count as being inside.
const DOOR_TRIGGER_DEPTH: float = 1.0

## THE BEACON: the amber light that says "that shape on the horizon is the one you
## are walking to". It sits on the -X/-Z corner OF THE ROOF.
##
## PHASE 13 DELETED THE SPIRE IT USED TO STAND ON. A 22 m corner tower with an
## overhanging cap was the silhouette when the keep was 11 m tall; against a 52 m
## slab it is a bump, and — fatally for this phase — its cap was a 8.6 m wide
## horizontal top 22 m up, i.e. a landing pad from which a Windman re-launches.
## Identity comes from mass now (the epic's ruling), and the facade below the roof
## carries nothing wide enough to stand on.
##
## THE CASTLE PASS (bead godot-test1-rgt) MOVED IT TO THE SPIRE TIP, which is where
## a beacon belongs and — more usefully — is the highest point of the silhouette, so
## the thing that says "over here" is the thing you can see furthest. It shrank with
## the move: a 4 m cube read as a shed on the roof corner, a 3 m one reads as a
## finial on a 98 m point.
const BEACON_SIDE: float = 3.0

# ----------------------------------------------------------------------------
# THE CASTLE, i.e. EVERYTHING ABOVE THE SEAL (bead godot-test1-rgt)
# ----------------------------------------------------------------------------
##
## THE ONE RULE THIS WHOLE SECTION OBEYS: nothing here is `collide: true`, and
## nothing here reaches below the roof slab. That is not decoration policy, it is
## the phase-13 seal restated — and both halves are load-bearing:
##
##   * NOT SOLID, so `tower_shell_selfcheck`'s check 12 skips it (it only judges
##     `collide: true` boxes) and `_topmost_solid()` still finds the Roof. A solid
##     turret above the slab would BECOME "the roof" as far as that check is
##     concerned, and the real roof would then fail its own coverage test.
##   * ABOVE THE SLAB, so check 11's ray grid — fired from 60 m straight down onto
##     collision shapes — is untouched, and so that no part of the facade a Windman
##     flies past below 52 m grows a ledge. The facade under the seal stays the
##     smooth 80 m box phase 13 made it; every scrap of castle is stacked on top.
##
## WHAT YOU GIVE UP: a maxed Windman who chain-launches onto the roof (check 12's
## documented ceiling) walks through the turrets. That is the correct trade — the
## guarantee being defended is "there is no way IN", and a ghost turret on a roof
## nobody is meant to reach costs nothing, while a solid one costs the seal.

## The crenellated parapet ring standing on the roof edge: merlon size, and the
## pitch it repeats at around the 80 m perimeter.
##
## ONE MESH, ONE DRAW CALL. 44 merlons as 44 `MeshInstance3D`s would quadruple this
## building's draw cost for a detail you read as a texture; they are welded into a
## single mesh by `_crenellation_mesh()` and appear in `boxes()` as ONE entry whose
## `size` is the ring's bounding box. That keeps the table the single source of the
## shape (the self-check measures the ring's footprint like any other box) without
## paying per-merlon.
##
## The pitch is chosen so the run closes exactly on both corners: the merlon centres
## walk from -MERLON_INSET to +MERLON_INSET in whole steps (11 gaps of 7 m = 77 m =
## 2 * 38.5), so there is no half-merlon at the end and no number to hand-tune.
const MERLON_SIZE: float = 3.0
const MERLON_HEIGHT: float = 2.5
const MERLON_PITCH: float = 7.0
## Distance from the centre to a merlon's own centre, so its OUTER face is flush
## with the roof edge at OUTER_HALF. Derived, never authored.
const MERLON_INSET: float = OUTER_HALF - MERLON_SIZE * 0.5

## The four corner turrets: a round shaft with a conical cap, standing on the roof.
##
## PLACED INSIDE THE ROOF'S FOOTPRINT (33 + 5.5 = 38.5 m of the 40 m half-span) for
## the same reason the parapet is: everything up here stands ON the slab, so the
## slab has to be under all of it. They still read as CORNER turrets because they
## push through the parapet ring at the corners, which is what a corner turret does.
const TURRET_OFFSET: float = 33.0
const TURRET_DIAMETER: float = 11.0
const TURRET_HEIGHT: float = 18.0
const TURRET_CAP_DIAMETER: float = 13.0
const TURRET_CAP_HEIGHT: float = 14.0

## The keep — the "taller than the body" mass the acceptance asks for, and the
## thing that makes the silhouette read as a castle rather than as a warehouse with
## four hats on it. A square Bergfried on the centre of the roof, under a steep
## spire that carries the beacon.
const KEEP_TOWER_WIDTH: float = 22.0
const KEEP_TOWER_HEIGHT: float = 26.0
const KEEP_SPIRE_DIAMETER: float = 26.0
const KEEP_SPIRE_HEIGHT: float = 20.0

# ----------------------------------------------------------------------------
# THE FACADE, i.e. EVERYTHING GLUED TO THE WALL BELOW THE SEAL (bead godot-test1-rzk)
# ----------------------------------------------------------------------------
##
## THE OWNER'S NOTE WAS "the HQ is just white from outside; it should look like a
## german castle, Fachwerkhaus on the top, some barred with iron bars small windows".
## So: stone for the bottom six storeys with small dark barred windows in it, and the
## top four storeys plastered and timber-framed.
##
## THE ONE RULE THIS SECTION OBEYS, and it is the castle section's rule one floor
## down: nothing here is `collide: true` and nothing here is more than a few
## centimetres proud of the wall it is stuck to. Both halves are load-bearing:
##
##   * NOT SOLID, so the phase-13 seal is untouched. `_topmost_solid()` still finds
##     the Roof, check 11's ray grid still lands on the slab, and — the sharp one —
##     the no-ledge sweep of check 12 never sees a 0.55 m timber rail as a thing a
##     Windman could stand on 45 m up. A solid facade would be a fire escape.
##   * PROUD BY CENTIMETRES, so `footprint_radius()` does not move. The furthest any
##     of it reaches is `OUTER_HALF + TIMBER_OUT` (40.25 m), well inside the yard's
##     own corners at 63.6 m, so the exclusion disc is unaffected.
##
## AND IT IS FOUR MESHES, NOT EIGHT HUNDRED NODES — the crenellation precedent
## (see `MERLON_SIZE`), generalised: `_facade_pieces()` returns a list of
## `{xform, size}` timbers, `_pieces_aabb()` measures them and `_welded_mesh()`
## stamps them all into ONE surface. That is what lets a whole timber lattice cost
## the draw budget of a single box, and what lets the table go on describing itself
## as `pos ± size/2` — the declared size IS the measured bounding box, so the
## footprint sweep, the budget and the impostor need to know nothing about any of it.
## A diagonal brace is just a stamp transform with a roll in it.

## How many of the ten storeys are timber-framed, counted DOWN FROM THE ROOF. The
## owner said "Fachwerkhaus on the top"; four of ten is the top 20 m of a 50 m wall,
## which is where the eye lands from the field.
const FACHWERK_STOREYS: int = 4
const FACHWERK_BASE: float = STOREY_HEIGHT * (STOREYS - FACHWERK_STOREYS)

## The three layers of the facade, as the distance each one's OUTER surface stands
## proud of the wall face at `OUTER_HALF`. Plaster first, timber over it, and the
## bars over their own window recess — so the frame reads as applied to the panel
## and the bars as sitting in front of the hole, from any angle and at any hour.
##
## They are millimetre-scale on purpose: this is paint with a relief, not a
## structure. `FACADE_THICK` is how deep each piece is BURIED, which only has to be
## enough that the wall behind never shows through at a grazing angle.
const PLASTER_OUT: float = 0.10
const TIMBER_OUT: float = 0.25
const FACADE_THICK: float = 0.40

## One timber's face width, and the bay the posts repeat at.
##
## THE BAY CLOSES ON BOTH CORNERS BY CONSTRUCTION, exactly like the merlons: the
## post centres walk from -inset to +inset in whole steps, and the step is DERIVED
## from that span rather than authored, so retuning `TIMBER_BAY` moves the pitch and
## never leaves a half-bay at one end.
##
## THE BRACES ARE SPARSE, AND THAT IS THE WHOLE DIFFERENCE BETWEEN A HALF-TIMBERED
## HOUSE AND A TRUSS (measured on a 110 m screenshot, 2026-09-01: the first draft
## braced every bay and read as a radio mast wrapped in a bridge). `TIMBER_BRACE_EVERY`
## bays carry one, its direction alternating with the bay and the storey — which is
## what a St Andrew's pattern looks like once you stop drawing both halves of it —
## and the bays between them stay plain plaster, which is what the eye reads as
## Fachwerk.
const TIMBER_WIDTH: float = 0.55
const TIMBER_BAY: float = 4.0
const TIMBER_BRACE_EVERY: int = 3

## THE BARRED WINDOWS, on the stone storeys only.
##
## SMALL, SPARSE AND IRREGULAR — a castle, not an office block. The irregularity is
## AUTHORED and not seeded: `WINDOW_ROW_PHASE` slides each row sideways by a fixed
## amount and the run has a fixed hole punched in it, because the tower is
## hand-planned once and forever (CLAUDE.md) and a window that moved between runs
## would be the same mistake as a tower that did. Grep this file for `run_seed` and
## there is nothing to find.
##
## The recess is a proud dark panel rather than a real hole: a hole means cutting
## the wall slab into pieces, which is collision geometry and a whole new class of
## bug, for something you read as a dark rectangle from 100 m.
const WINDOW_WIDTH: float = 1.4
const WINDOW_HEIGHT: float = 2.1
## Height of the sill above its own storey's floor, and the spacing along the wall.
const WINDOW_SILL: float = 2.2
const WINDOW_PITCH: float = 12.0
## The lowest storey INDEX that carries a row. Storey 0 is the entry hall and the
## doorway is in it; the rows start one floor up and stop where the plaster starts.
const WINDOW_ROW_FLOOR: int = 1
const WINDOW_ROW_PHASE: Array[float] = [0.0, 4.5, -2.0, 2.5, -3.5]
const WINDOW_OUT: float = 0.06
const WINDOW_THICK: float = 0.12
const WINDOW_BARS: int = 3
const BAR_WIDTH: float = 0.12
const BAR_OUT: float = 0.14
const BAR_THICK: float = 0.10

## The yard: a flat visual slab under the whole compound. VISUAL ONLY and 3 cm
## proud of the ground — no collision shape, no lip to step over. The flat-world
## invariant (CLAUDE.md) says the ground stays at y = 0 and everything assumes it;
## a slab you could stand on would be the first raised terrain in the game and
## would fight coin settling, crocodile gravity and the wade test. It is a change
## of colour, nothing more.
##
## 45 AND NOT 48, and the three metres are arithmetic rather than taste: the yard
## is a SQUARE and `TOWER_RADIUS` is a CIRCLE, so its corners reach 45 * sqrt2 =
## 63.6 m of the 65 m disc. At 48 they would reach 67.9 m and stand in scenery the
## site was never promised to be clear of — which check 2 of the self-check would
## (correctly) refuse.
const YARD_HALF: float = 45.0
const YARD_LIFT: float = 0.03

## Hard cap on how many boxes the shell may be made of, asserted headlessly by
## `tower_shell_selfcheck.gd`.
##
## The number that matters on web `gl_compatibility` is DRAW CALLS, and each box is
## a `MeshInstance3D` — this building is permanently on screen once you are near it,
## so the budget is what stops "one more buttress" from being free. 12 leaves room
## for the interior phase to add a step or a threshold without a new ruling, and
## bites immediately if somebody starts modelling crenellations. The check also
## measures the FOOTPRINT against endless_terrain's `TOWER_RADIUS`, which is the
## other half of the budget and is deliberately NOT restated here.
##
## 12 -> 16 IN PHASE 13: yard + roof + beacon + THE SAME SIX-BOX RING TWICE (3
## walls, 2 jambs, a lintel) — the 80 m envelope and the 20 m keep preserved inside
## it — was 15, with one spare slot, the same courtesy phase 3 was left. The spire,
## its cap and its overhang all went away (see BEACON_SIDE), so the growth was the
## inner ring and nothing else.
##
## 16 -> 28 IN THE CASTLE PASS (bead godot-test1-rgt), and the eleven new entries
## are the WHOLE castle: a parapet, a keep, its spire, and four turrets with four
## caps. That it is only eleven is the point — the 44 merlons are one welded mesh
## (see MERLON_SIZE) rather than 44 entries, because the budget is a DRAW CALL
## budget and a merlon is not worth one.
##
## 28 -> 22 IN THE DEMOLITION (bd godot-test1-dn8), and the six that went are the
## whole inner ring: `KeepWallBack`, `KeepWallSideNegZ`, `KeepWallSidePosZ`,
## `KeepJambNegZ`, `KeepJambPosZ`, `KeepLintel`. Phase 13 predicted this line
## ("phase 14 is also what deletes the inner ring again") and it took until floors
## 0 and 1 were drawn on the plan grid, because the ring was the wall those two
## storeys' rooms were authored against. 20 of 22 used, two spare, the same
## courtesy every previous phase was left.
##
## 22 -> 26 IN THE GERMAN-CASTLE PASS (bead godot-test1-rzk), and the four new
## entries are the WHOLE facade: the plaster field, its timber lattice, the window
## recesses and their iron bars. That it is only four — for ~810 timbers, panels and
## bars — is the crenellation argument restated: this is a DRAW CALL budget, and a
## single mullion is not worth one. 24 of 26 used, two spare, the same courtesy.
const BOX_BUDGET: int = 26

## Palette. Four colours, four materials, shared process-wide (see `_material`).
##
## DARKER THAN THEY LOOK ON PAPER, and deliberately. `main.tscn` grades the scene
## with a bright key light, glow and a BCS pass, and the ground and sky at the
## tower's latitudes are pale — a "weathered pale stone" wall at 0.6 albedo comes
## out of that pipeline as a white monolith with no readable edges (measured in the
## editor, 2026-08-28). Judge these against a screenshot, never against the swatch.
##
## THE CASTLE PASS RETUNED TWO OF THEM (bead godot-test1-rgt). The direction is
## "pale limestone walls, steep dark-blue slate roofs", and what sells that is the
## CONTRAST between the two, not the absolute lightness of either — so the wall
## moved a hair up (still well under the 0.6 that blows out) and the roof moved
## decisively into the blue, away from the near-neutral plum it was. A pale wall
## against a plum roof reads as one grey building; a pale wall against slate blue
## reads as a roof.
##
## AND THE GERMAN-CASTLE PASS MOVED THE WALL BACK DOWN (bead godot-test1-rzk). The
## owner's report was "the HQ is just white from outside", and a screenshot from
## 110 m is what settles which half of the new contrast was missing: the timber
## lattice read immediately, and the plaster/stone SPLIT did not, because a 0.48 wall
## under a 0.56 plaster is one value through the grade. Stone is now clearly the
## darker material of the two, which is also what makes the four turrets and the keep
## above the roof read as stonework rather than as more of the same white mass.
const COLOR_WALL := Color(0.37, 0.36, 0.34)      # weathered grey limestone
const COLOR_ROOF := Color(0.16, 0.18, 0.29)      # steep dark slate blue
const COLOR_YARD := Color(0.33, 0.31, 0.29)      # packed earth, a shade under the wall
const COLOR_BEACON := Color(1.0, 0.72, 0.18)     # the amber light on the spire

## THE GERMAN-CASTLE PASS ADDED THREE (bead godot-test1-rzk), and what they are FOR
## is contrast: the owner's complaint was that the HQ reads as one white mass from
## the field. The plaster is the pale one now and the stone under it is not (see
## COLOR_WALL above) — that split is the horizontal read, and the near-black oak
## lattice over the plaster is the vertical one. Judge them against a screenshot from
## ~100 m, never against the swatch (see the paragraph above).
##
## THE RECESS SHARES THE TIMBER, on purpose rather than to save a constant: a window
## opening and a weathered beam are the same near-black at any distance this building
## is seen from, and the thing that has to READ against the opening is the bar in
## front of it — which is why the iron is the one of the three that is a light value.
const COLOR_PLASTER := Color(0.58, 0.54, 0.44)   # warm lime plaster
const COLOR_TIMBER := Color(0.15, 0.10, 0.07)    # dark oak, and the window openings
const COLOR_IRON := Color(0.28, 0.29, 0.32)      # cold bar iron, over the openings

## The spires and turret caps: the same slate as the roof, but LIT FROM WITHIN.
##
## THE ONE "MAGICAL" IN "MAGICAL HUGE GERMAN CASTLE" (owner playtest, 2026-08-29).
## A faint cool emission costs no box and no draw call — it is a flag on a material
## that already exists — and it is what makes the spire tips hold a colour at dusk
## and through the pale fog instead of dissolving into it. Kept low on purpose: this
## is a glow you notice, not a lamp. The BEACON is still the bright thing.
const COLOR_SPIRE := Color(0.19, 0.23, 0.38)
const SPIRE_GLOW := Color(0.30, 0.52, 0.95)
const SPIRE_GLOW_ENERGY: float = 0.35

## HOW THE IMPOSTOR MATCHES THE SHELL: it does not carry a palette of its own.
##
## THE BLACK-THEN-WHITE BUG (owner playtest, 2026-08-29) WAS THIS CONSTANT. The
## impostor used to be one authored colour — 0.17/0.19/0.25, an almost-black
## blue-grey — for every box, unshaded, so at 400 m it rendered as EXACTLY that:
## a flat near-black slab against a 0.85 sky. Meanwhile the real shell is lit by
## `main.tscn`'s bright key through a glow and a BCS grade, and at handover range
## it is additionally 50-80% blended into FOG_COLOR (0.85, 0.86, 0.80). Black
## impostor, near-white fogged shell, one hard swap: the pop was authored.
##
## The fix is to stop authoring a second palette at all. The impostor takes the
## SHELL's colour for every box and lifts it toward white by this one gain, which
## is the cheapest possible stand-in for "what the key light does to that albedo".
## Judge it against a screenshot at 380 m, never against the swatch — and if the
## grade in `main.tscn` changes, this is the one number that moves.
const IMPOSTOR_LIT_GAIN: float = 1.35

## THE CROSS-FADE BAND, in metres from the camera: the impostor is fully opaque
## beyond FAR, invisible within NEAR, and linearly blended between.
##
## WHY A BAND AND NOT A SWAP. The impostor is `disable_fog` and the shell is not,
## so at any single distance the two are differently hazed BY CONSTRUCTION — no
## choice of albedo can make a hard swap invisible. Fading one out across the range
## where the other emerges from the fog is the only handover that has no frame in
## it where something changed.
##
## FAR (220) SITS INSIDE THE WORST-CASE LOAD DISTANCE, and that worst case has two
## terms people get wrong (codex review, 2026-08-30 — the first draft of this
## claimed 310 m and was wrong on both counts):
##
##   * `_tower_stream` is evaluated only on a chunk-boundary CROSSING, so between
##     two evaluations the player can cover a whole chunk DIAGONAL, not a chunk
##     side: sqrt(2) * chunk_size (70.7 m), not 50.
##   * `distance_fade` is PER PIXEL, measured camera-to-fragment. So the fade starts
##     on the NEAREST CORNER of the impostor, which is `footprint_radius()` (63.6 m,
##     the yard's corner) closer than the centre the load test measures.
##
## So the honest guarantee is `TOWER_LOAD_RADIUS - chunk diagonal - footprint
## radius` = 360 - 70.7 - 63.6 = 225.6 m, and FAR has to sit under THAT.
## `tower_shell_selfcheck` computes it from the live constants — it is three terms
## now precisely because nobody gets three terms right from memory.
##
## NEAR (150) is where the fade completes, and each mesh is culled outright once
## its FURTHEST pixel is inside it (`visibility_range_begin`, see `build_impostor`)
## so a fully transparent impostor is not still being rasterised while you stand in
## the doorway. It is also roughly where the web fog stops hiding the real shell —
## an unfogged crisp castle standing over a fogged field would be its own artefact.
##
## DEGRADES SAFELY. If `distance_fade` is ever unsupported on a target, the fade
## flattens to the hard cull at NEAR — i.e. back to a swap, but now a swap between
## two things that share a palette and a silhouette, which is the bead's other
## accepted answer rather than a regression.
const IMPOSTOR_FADE_FAR: float = 220.0
const IMPOSTOR_FADE_NEAR: float = 150.0

# ============================================================================
# STATE
# ============================================================================

## True once any player has walked through the doorway this run. A latch, not a
## presence flag: phase 3 wants "has this player found the way in", and a bool that
## flickers as somebody paces the threshold answers a different question.
var entered: bool = false

## Every gate, stop and stage inside this tower that has been opened this run, as a
## SET of string ids (`{id: true}` — GDScript has no Set, and a Dictionary's key
## lookup is the whole reason this is not an Array).
##
## THE STATE LIVES HERE AND NOWHERE ELSE, and that placement is the design:
##
##   * IT IS WORLD STATE, NOT PLAYER STATE. The interior's identity gate asks who
##     is standing on the pad and then writes the answer HERE — so what changed is
##     the building, not a permission the local player carries around. That is what
##     the epic's multiplayer landmine asks for: syncing it later is one broadcast
##     of `opened_ids()`, with no per-player bookkeeping to unpick, because there
##     never was any.
##   * IT SURVIVES THE WHOLE RUN. The tower is manager-parented and freed only by
##     `new_run()`, so "walk out of the tower and back in, gates still open" is a
##     property of where this variable lives rather than of anything remembering to
##     save it.
##   * IT SURVIVES THE PROCESS. `_enter_tree()` hydrates it from
##     `BestRunStore.tower_opened_ids()` and `mark_opened()` writes straight
##     through, so "quit, relaunch, the gate is still open" needs nobody to
##     remember to save either. That is phase 5, and it is four lines because the
##     set was already the right shape.
##   * IT IS MONOTONE. Ids are only ever added — never removed, never re-closed —
##     which is what lets two copies merge with a union and no conflict rule (see
##     `BestRunStore.merge_tower_opened_ids`), and what stops a met demand gate
##     from ever re-locking: earned progression must never become upkeep.
##
## Ids are declared as consts on `TowerGraph` (`GATE_*`) and re-exported by
## `TowerInterior`. THEY ARE PERSISTED VERBATIM, so adding one is free and
## renaming one is a save migration.
var opened: Dictionary = {}

## Albedo colour -> the one material of that colour, for the whole process.
##
## The same discipline (and the same reason) as `ToonShading._styled_cache`: never
## a material per instance. There is only ever one tower, so the saving here is
## small and the POINT is the contract — the impostor, a second shell built by a
## self-check, and a shell rebuilt after `new_run()` all share these four, and the
## renderer can batch what shares a material.
static var _materials: Dictionary = {}

## The same, for the impostor's flat fog-exempt variants — a SEPARATE dictionary,
## because since this bead the impostor's colours are derived from the shell's and
## a shared key space would let one builder serve the other's material. See
## `_impostor_material`.
static var _impostor_materials: Dictionary = {}


static func boxes() -> Array[Dictionary]:
	"""
	The whole building, as boxes: `{name, pos, size, color, collide}` in local metres,
	plus an optional `mesh` naming a shape other than a box ("cylinder", "cone",
	"crenellation", and the four facade kinds — see `_shape_mesh`).

	`mesh` IS A SHAPE, NEVER A SECOND SIZE. Whatever it names, the mesh it builds
	fits exactly inside `size`, so every measurement below — the footprint sweep,
	the budget, the self-check's ledge rules — keeps working on `pos ± size/2` and
	does not have to learn about cones. A round tower is still a box as far as the
	book-keeping is concerned; it just draws with its corners taken off.

	@return: One entry per `MeshInstance3D` the shell builds, in build order.

	THE SINGLE SOURCE OF THE SHAPE. `_ready()` builds the real thing from it,
	`build_impostor()` builds the far-away silhouette from it, and
	`tower_shell_selfcheck.gd` measures the budget and the footprint from it
	without instancing anything at all.

	Every position is a CENTRE and every size is a full extent, so a box occupies
	`pos ± size/2` — which is what makes the footprint measurement in the self-check
	a two-line loop over corners.
	"""
	# Centre of a wall slab: the outer face sits at OUTER_HALF, so the slab's middle
	# is half a thickness inside that.
	var wall_mid := OUTER_HALF - WALL_THICK * 0.5
	# The side walls run BETWEEN the two they meet, so the corners are not doubled.
	var side_len := 2.0 * (OUTER_HALF - WALL_THICK)
	# What is left of the front wall either side of the doorway.
	var jamb_len := OUTER_HALF - DOOR_HALF_WIDTH
	var jamb_mid := (OUTER_HALF + DOOR_HALF_WIDTH) * 0.5
	# The lintel bridges the hole, from the top of the doorway to the wall top.
	var lintel_height := WALL_HEIGHT - DOOR_HEIGHT
	var out: Array[Dictionary] = []
	# 1. The yard, first so everything else draws over it. No collision — see YARD_LIFT.
	out.append({"name": "Yard", "pos": Vector3(0.0, YARD_LIFT * 0.5, 0.0),
		"size": Vector3(2.0 * YARD_HALF, YARD_LIFT, 2.0 * YARD_HALF),
		"color": COLOR_YARD, "collide": false})
	# 2. The three solid walls. -X is the back (the door faces +X).
	out.append({"name": "WallBack", "pos": Vector3(-wall_mid, WALL_HEIGHT * 0.5, 0.0),
		"size": Vector3(WALL_THICK, WALL_HEIGHT, 2.0 * OUTER_HALF),
		"color": COLOR_WALL, "collide": true})
	out.append({"name": "WallSideNegZ", "pos": Vector3(0.0, WALL_HEIGHT * 0.5, -wall_mid),
		"size": Vector3(side_len, WALL_HEIGHT, WALL_THICK),
		"color": COLOR_WALL, "collide": true})
	out.append({"name": "WallSidePosZ", "pos": Vector3(0.0, WALL_HEIGHT * 0.5, wall_mid),
		"size": Vector3(side_len, WALL_HEIGHT, WALL_THICK),
		"color": COLOR_WALL, "collide": true})
	# 3. The front wall, as two jambs and a lintel — i.e. a wall with a hole in it.
	out.append({"name": "DoorJambNegZ", "pos": Vector3(wall_mid, WALL_HEIGHT * 0.5, -jamb_mid),
		"size": Vector3(WALL_THICK, WALL_HEIGHT, jamb_len),
		"color": COLOR_WALL, "collide": true})
	out.append({"name": "DoorJambPosZ", "pos": Vector3(wall_mid, WALL_HEIGHT * 0.5, jamb_mid),
		"size": Vector3(WALL_THICK, WALL_HEIGHT, jamb_len),
		"color": COLOR_WALL, "collide": true})
	out.append({"name": "DoorLintel", "pos": Vector3(wall_mid, DOOR_HEIGHT + lintel_height * 0.5, 0.0),
		"size": Vector3(WALL_THICK, lintel_height, 2.0 * DOOR_HALF_WIDTH),
		"color": COLOR_WALL, "collide": true})
	# 3b. THE FACADE (bead godot-test1-rzk): plaster and a timber lattice over the
	#     top FACHWERK_STOREYS, barred windows in the stone below. Four welded meshes
	#     stuck to the outside of the ring above, none of them solid and none of them
	#     more than 25 cm proud — see the FACADE section for why both of those are the
	#     seal and the exclusion disc restated rather than decoration policy.
	#
	#     THE TABLE ENTRY IS MEASURED, NOT AUTHORED. `_facade_box` takes the bounding
	#     box of the timbers it is about to weld, so the `pos ± size/2` contract every
	#     other measurement in this file leans on holds for a lattice exactly as it
	#     does for a slab, with no second number to keep in step.
	out.append(_facade_box("PlasterField", "plaster", COLOR_PLASTER, 1))
	out.append(_facade_box("Fachwerk", "fachwerk", COLOR_TIMBER, 2))
	out.append(_facade_box("Windows", "windows", COLOR_TIMBER, 1))
	out.append(_facade_box("WindowBars", "bars", COLOR_IRON, 2))
	# 4. THE LID. One slab over the whole footprint, so every wall top underneath it
	#    is covered rather than exposed — that is what makes the facade smooth: the
	#    only horizontal surface a flier can put his feet on is the top of this box.
	#    It spans the full 2 * OUTER_HALF square, not the inner hole, so it also is
	#    its own parapet (see ROOF_THICK).
	out.append({"name": "Roof", "pos": Vector3(0.0, WALL_HEIGHT + ROOF_THICK * 0.5, 0.0),
		"size": Vector3(2.0 * OUTER_HALF, ROOF_THICK, 2.0 * OUTER_HALF),
		"color": COLOR_ROOF, "collide": true})
	# 5. THE CASTLE, all of it standing ON the slab and none of it solid — see the
	#    "EVERYTHING ABOVE THE SEAL" section for why those two facts are the seal
	#    restated rather than a style choice.
	var roof_top := WALL_HEIGHT + ROOF_THICK
	# 5a. The crenellated parapet, welded into one mesh (see MERLON_SIZE). Its
	#     declared size is the ring's bounding box, so the footprint sweep and the
	#     budget check read it exactly like any other box.
	out.append({"name": "Crenellations",
		"pos": Vector3(0.0, roof_top + MERLON_HEIGHT * 0.5, 0.0),
		"size": Vector3(2.0 * OUTER_HALF, MERLON_HEIGHT, 2.0 * OUTER_HALF),
		"color": COLOR_ROOF, "collide": false, "mesh": "crenellation"})
	# 5b. The four corner turrets: a round shaft under a conical cap, one pair per
	#     corner, generated rather than written out four times so a retune of the
	#     offset cannot move three of them.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var tag := "%s%s" % ["Neg" if sx < 0.0 else "Pos", "NegZ" if sz < 0.0 else "PosZ"]
			var at := Vector2(sx * TURRET_OFFSET, sz * TURRET_OFFSET)
			out.append({"name": "Turret" + tag,
				"pos": Vector3(at.x, roof_top + TURRET_HEIGHT * 0.5, at.y),
				"size": Vector3(TURRET_DIAMETER, TURRET_HEIGHT, TURRET_DIAMETER),
				"color": COLOR_WALL, "collide": false, "mesh": "cylinder"})
			out.append({"name": "TurretCap" + tag,
				"pos": Vector3(at.x, roof_top + TURRET_HEIGHT + TURRET_CAP_HEIGHT * 0.5, at.y),
				"size": Vector3(TURRET_CAP_DIAMETER, TURRET_CAP_HEIGHT, TURRET_CAP_DIAMETER),
				"color": COLOR_SPIRE, "collide": false, "mesh": "cone"})
	# 5c. The keep: the mass that makes the silhouette taller than the body, and the
	#     spire on top of it, which is the highest point of the building.
	out.append({"name": "KeepTower",
		"pos": Vector3(0.0, roof_top + KEEP_TOWER_HEIGHT * 0.5, 0.0),
		"size": Vector3(KEEP_TOWER_WIDTH, KEEP_TOWER_HEIGHT, KEEP_TOWER_WIDTH),
		"color": COLOR_WALL, "collide": false})
	var spire_base := roof_top + KEEP_TOWER_HEIGHT
	out.append({"name": "KeepSpire",
		"pos": Vector3(0.0, spire_base + KEEP_SPIRE_HEIGHT * 0.5, 0.0),
		"size": Vector3(KEEP_SPIRE_DIAMETER, KEEP_SPIRE_HEIGHT, KEEP_SPIRE_DIAMETER),
		"color": COLOR_SPIRE, "collide": false, "mesh": "cone"})
	# 5d. The beacon, now the finial on the spire's point (see BEACON_SIDE). No
	#     collision: it is a light, and a 1-box finial is not a place to stand.
	out.append({"name": "Beacon",
		"pos": Vector3(0.0, spire_base + KEEP_SPIRE_HEIGHT, 0.0),
		"size": Vector3(BEACON_SIDE, BEACON_SIDE, BEACON_SIDE),
		"color": COLOR_BEACON, "collide": false})
	return out


static func door_trigger_box() -> Dictionary:
	"""
	The doorway volume, as the same `{pos, size}` shape `boxes()` speaks.

	@return: Centre and full extent of the `Area3D`'s box, local metres.

	Derived from the SAME `DOOR_*` constants the jambs are cut around, which is the
	whole reason it is a function and not a literal in `_ready()`: the trigger is
	the hole, so it cannot end up somewhere the hole is not.

	ONE RING, SO ONE DOORWAY (bd godot-test1-dn8). This used to sit on the inner
	keep's door line, because there were two front walls and walking through the
	outer one only put you in a courtyard — "entered the tower" was a claim about
	the rooms, not about the envelope. The keep is demolished and floor 0 is a
	planned storey that begins at this wall, so the hole and the trigger are the
	same doorway again and the argument for a second plane went with the second
	wall. `tower_shell_selfcheck` asserts no wall box may overlap this volume.
	"""
	var wall_mid := OUTER_HALF - WALL_THICK * 0.5
	return {
		"pos": Vector3(wall_mid, DOOR_HEIGHT * 0.5, 0.0),
		"size": Vector3(WALL_THICK + 2.0 * DOOR_TRIGGER_DEPTH,
			DOOR_HEIGHT, 2.0 * DOOR_HALF_WIDTH),
	}


static func footprint_radius() -> float:
	"""
	How far the shell reaches from its own centre, horizontally.

	@return: Metres, measured to the furthest CORNER of the furthest box.

	This is the number that has to fit inside phase 1's exclusion disc, and it is
	measured rather than declared so it can never quietly disagree with the geometry
	above. The comparison against `endless_terrain.TOWER_RADIUS` lives in the
	self-check, where the constant can be read from its owner instead of restated
	here (the bead's landmine: share the constant, never copy the number).
	"""
	var worst := 0.0
	for box: Dictionary in boxes():
		var pos: Vector3 = box["pos"]
		var half: Vector3 = box["size"] * 0.5
		# Furthest corner of an axis-aligned box from the origin, in XZ.
		worst = maxf(worst, Vector2(absf(pos.x) + half.x, absf(pos.z) + half.z).length())
	return worst


static func build_impostor() -> Node3D:
	"""
	THE HORIZON IMPOSTOR: the tower as it looks from 400 m away, which is to say
	as a shape.

	@return: A fresh, unparented Node3D holding the silhouette. The caller places it
	        at `tower_site()` and hides it once the real shell exists.

	WHY IT EXISTS (owner ruling, 2026-08-27: wayfinding, and it ships with this
	phase). The real shell is not instanced until the player is within
	`TOWER_LOAD_RADIUS`, and even if it were, the web build draws nothing past
	`render_distance` (150 m) and drowns what is left in fog at density 0.005 — so
	at 400 m the actual building is not merely dim, it is absent. Without a stand-in
	the tower is a place the minimap knows about and the world does not, and the
	walk out there is 400 m of featureless field.

	FOG-EXEMPT AND UNSHADED, which is the entire trick: `disable_fog` opts the
	material out of the depth fog that would otherwise erase it, and unshaded means
	its colour does not wash out with the light angle. It is the same boxes as the
	real shell at the same true scale — NOT scaled up — so walking toward it makes
	it grow the way a building does.

	AND IT NO LONGER SWAPS — IT DISSOLVES (bead godot-test1-rgt). The two things
	that made the old handover a visible pop were both here: an authored near-black
	palette (see `IMPOSTOR_LIT_GAIN` for the full post-mortem) and a hard
	`visible = false` the frame the shell arrived. Now every box takes the SHELL's
	own colour lifted by one gain, and the material fades itself out across
	`IMPOSTOR_FADE_FAR` -> `IMPOSTOR_FADE_NEAR` while the real building emerges from
	the fog underneath it. The impostor is transparent while it fades, so it does
	not write depth and cannot z-fight with the shell it is standing in.

	NO COLLISION, NO GROUP, NO SCRIPT: it is a picture. The cross-fade (bead
	godot-test1-rgt) is a material property and the cull a mesh property, so
	`_tower_stream` has no per-frame work. The one per-frame writer is
	`endless_terrain._process()`'s Budapest gate (bead godot-test1-8gw.14), which
	hides the fog-exempt silhouette while the local player stands inside the city.
	"""
	var root := Node3D.new()
	root.name = "TowerImpostor"
	for box: Dictionary in boxes():
		var mesh := MeshInstance3D.new()
		mesh.name = box["name"]
		mesh.mesh = _shape_mesh(box)
		mesh.position = box["pos"]
		mesh.material_override = _impostor_material(_impostor_color(box["color"]))
		# The silhouette must never be the reason something else does not draw.
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# THE OTHER HALF OF THE CROSS-FADE. The material fades the pixels out over
		# the band; this stops SUBMITTING the mesh once those pixels are all zero,
		# so a fully transparent 26-box building is not being rasterised over the
		# real one while the player stands in the doorway.
		#
		# MEASURED FROM THE MESH'S FURTHEST CORNER, not from NEAR flat (codex
		# review, 2026-08-30). The range test is a distance to the instance's
		# ORIGIN while the fade is per pixel, so on an 80 m slab the far half is
		# still 40 m behind the origin: cull it at NEAR and you delete pixels that
		# were 190 m out and still visibly fading — a pop, in the middle of the
		# thing that exists to remove one. Subtracting the bounding radius means the
		# mesh survives until its LAST pixel is inside NEAR. (Every box in the table
		# is centred on its own origin, which check 3 asserts, so the radius really
		# is the half-diagonal.)
		var reach: float = mesh.mesh.get_aabb().size.length() * 0.5
		mesh.visibility_range_begin = maxf(IMPOSTOR_FADE_NEAR - reach, 0.0)
		# AND THE FACADE HAS TO SORT IN FRONT OF THE WALL IT IS GLUED TO (codex
		# review, 2026-09-01). This is the price of the cross-fade: `PIXEL_ALPHA`
		# makes every impostor material TRANSPARENT, so none of them writes depth
		# and the renderer orders them back-to-front by their own ORIGINS instead.
		# The four facade meshes are whole-building meshes centred on the axis,
		# while the walls they are stuck to are centred on their own faces — so the
		# NEAR wall sorts last and paints over the Fachwerk, and the impostor
		# reverts to the plain white box this bead exists to remove. Measured, not
		# reasoned: rendered at 230 m the facade was simply gone.
		#
		# `sorting_offset` is the documented fix and needs no second material: a
		# mesh with a higher one is treated as that many metres NEARER for sorting
		# alone. A whole building's width clears every wall in the table, and one
		# metre per layer separates the timbers from their plaster and the bars
		# from their own recess (those two share an origin exactly, so without it
		# their order is not merely wrong but undefined).
		#
		# WHAT IT DOES NOT FIX, stated so nobody reads it as more than it is: a
		# facade layer is ONE mesh wrapping all four faces, so the FAR face's
		# timbers also sort in front of the NEAR face's plaster and the impostor is
		# faintly see-through where they cross. Rendered at 415 m — where this thing
		# is actually looked at, before the fog blend — it is invisible, and the
		# alternative is sixteen table entries and sixteen draw calls for four.
		var layer := int(box.get("layer", 0))
		if layer > 0:
			mesh.sorting_offset = 2.0 * OUTER_HALF + float(layer)
		root.add_child(mesh)
	return root


func _ready() -> void:
	"""Build the shell, its one collision body, and the door trigger."""
	# Group registration so phase 3's interior, a self-check or the HUD can find the
	# tower the project's way — no hard references anywhere (CLAUDE.md).
	add_to_group("tower")

	# ONE StaticBody3D for the whole building, the same rule chunks follow (one
	# collision body per chunk): a body per wall would be eight physics islands
	# where one does.
	var body := StaticBody3D.new()
	body.name = "TowerCollision"
	add_child(body)

	for box: Dictionary in boxes():
		var mesh := MeshInstance3D.new()
		mesh.name = box["name"]
		mesh.mesh = _shape_mesh(box)
		mesh.position = box["pos"]
		mesh.material_override = _material(box["color"])
		add_child(mesh)
		if not box["collide"]:
			continue
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = box["size"]
		shape.shape = box_shape
		shape.position = box["pos"]
		shape.name = "%sShape" % box["name"]
		body.add_child(shape)

	# The door trigger — an Area3D on the coin's idiom (coin.gd extends Area3D and
	# reacts to `body_entered` from the "player" group). Monitorable is off: nothing
	# ever asks whether the doorway is inside something else, and leaving it on
	# costs a broadphase entry for no reader.
	var door := Area3D.new()
	door.name = "DoorTrigger"
	door.monitorable = false
	var trigger: Dictionary = door_trigger_box()
	var door_shape := CollisionShape3D.new()
	var door_box := BoxShape3D.new()
	door_box.size = trigger["size"]
	door_shape.shape = door_box
	door.add_child(door_shape)
	door.position = trigger["pos"]
	door.body_entered.connect(_on_door_body_entered)
	add_child(door)


func _enter_tree() -> void:
	"""
	Hydrate the opened set from the local save before anything can read it.

	`_enter_tree` and not `_ready`, and that is the whole subtlety: ready
	propagates CHILDREN FIRST, so `TowerInterior._ready()` — which calls
	`_apply_opened()` to snap the gates to the set with no animation — runs before
	this node's own `_ready()` would. `_enter_tree` propagates parent first, so the
	set is loaded before the interior is built from it and a restored gate comes up
	open on its first frame, exactly as check 8 of `tower_interior_selfcheck.gd`
	asserts for a hand-seeded set.

	The merge is a union into whatever is already here, so re-entering the tree
	cannot lose an id opened while detached.
	"""
	for id: String in BestRunStore.tower_opened_ids():
		opened[id] = true


func mark_opened(id: String) -> void:
	"""
	Record a gate as open. Idempotent, and the only writer of `opened`.

	@param id: One of `TowerGraph`'s `GATE_*` constants.

	WRITES THROUGH IMMEDIATELY, on the opening only. A gate opening is rare and
	precious — a handful of times in a whole campaign — so there is nothing to
	batch and everything to lose by deferring it to a flush a crash can eat. The
	early return is what keeps it off any repeated path: re-marking an open gate,
	including every id this shell just hydrated, touches no disk at all.
	"""
	if opened.has(id):
		return
	opened[id] = true
	BestRunStore.merge_tower_opened_ids([id])


func is_opened(id: String) -> bool:
	"""
	Has this gate been opened this run?

	@param id: One of `TowerInterior`'s `GATE_*` constants.
	@return: true once `mark_opened` has been called for it.
	"""
	return opened.has(id)


func opened_ids() -> Array:
	"""
	Every opened id, sorted.

	@return: A fresh sorted Array of String — the caller may keep or mutate it.

	SORTED SO IT IS COMPARABLE. Dictionary key order is insertion order, which
	means two players who opened the same three gates in different orders would
	produce two different arrays; phase 5 merges these and a self-check compares
	them, and both want the set rather than the history.
	"""
	var out: Array = opened.keys()
	out.sort()
	return out


func sheltered(pos: Vector3) -> bool:
	"""
	Is this world point under the roof?

	@param pos: A world-space position.
	@return: true anywhere inside the roofed footprint, below the roof slab.

	THE BUILDING OWNS THIS QUESTION, because the building owns the numbers. Phase
	13 put a lid on the shell (`ROOF_THICK`) and the weather did not notice: a
	storm cloud drifting over the HQ drew rain through the slab and grounded
	Windman indoors (bug godot-test1-li2). `TowerInterior.inside_walls()` is the
	wrong boundary to ask — it answers "am I in a ROOM", i.e. the inner faces, and a
	roof covers the walls too — and restating OUTER_HALF anywhere else is how the two
	drift apart the next time the envelope grows. (When this was written that
	predicate was also still the 20 m phase-3 keep; phase 14 widened it to the
	envelope, which narrows the gap to one wall thickness without closing it.)

	`to_local` rather than subtracting `global_position`: the shell is parked
	unrotated today (`endless_terrain._tower_build_shell`), and this stays correct
	on the day somebody turns it.

	Half-open at the top: the roof's UNDERSIDE is the ceiling, so a player standing
	ON the roof (y >= WALL_HEIGHT) is outdoors and gets rained on, which is the
	answer that makes the gate read as a roof rather than as a column of immunity
	reaching to the sky. Bounded below at y = 0 for the mirror-image reason: the
	building's floor is not a lid for whatever is under it.

	Cheap enough for the per-tick weather query that consumes it: one transform
	multiply and three compares, no allocation.
	"""
	var local: Vector3 = to_local(pos)
	if local.y < 0.0 or local.y >= WALL_HEIGHT:
		return false
	return absf(local.x) <= OUTER_HALF and absf(local.z) <= OUTER_HALF


func _on_door_body_entered(body: Node3D) -> void:
	"""
	Somebody touched the doorway volume. Only the LOCAL player counts.

	"player" means the local player and nothing else (CLAUDE.md) — a remote
	teammate is a `RemoteAvatar`, which joins no group and carries no physics body,
	so it cannot reach here at all and this guard is not what excludes it. What the
	guard does exclude is every crocodile in the world: they are `CharacterBody3D`s
	that will happily wander into the doorway, and a tower that reports itself
	entered because a croc walked past would hand phase 3 a lie.
	"""
	if not body.is_in_group("player"):
		return
	entered = true
	player_entered.emit(body)


static func _shape_mesh(box: Dictionary) -> Mesh:
	"""
	The mesh for one table entry, whatever shape it declared.

	@param box: One entry of `boxes()`.
	@return: A fresh mesh whose AABB is exactly `box["size"]`, centred on the origin.

	One per box — not worth a cache the way the materials are (a `BoxMesh` carries
	its size, so sharing one would mean SCALING the `MeshInstance3D`s instead, and
	scaled instances are the thing that breaks batching).

	THE AABB CONTRACT is what lets the rest of the file — and every check in
	`tower_shell_selfcheck` — go on treating the table as boxes: a cone declares the
	box it fits in, and the self-check asserts that rather than trusting it.
	"""
	var size: Vector3 = box["size"]
	match box.get("mesh", "box"):
		"cylinder":
			var cyl := CylinderMesh.new()
			cyl.top_radius = size.x * 0.5
			cyl.bottom_radius = size.x * 0.5
			cyl.height = size.y
			# 12 sides reads as round at any distance this building is seen from and
			# costs a third of the default 64. Rings stay at 1: the shaft is
			# untextured and unlit-by-vertex, so subdividing its height buys nothing.
			cyl.radial_segments = 12
			cyl.rings = 1
			return cyl
		"cone":
			# A cone IS a cylinder with no top — Godot has no ConeMesh and does not
			# need one.
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = size.x * 0.5
			cone.height = size.y
			cone.radial_segments = 12
			cone.rings = 1
			return cone
		"crenellation":
			return _crenellation_mesh(size)
		"plaster", "fachwerk", "windows", "bars":
			# THE FACADE KINDS ALL SHARE ONE BUILDER, and it ignores `size` on
			# purpose: the pieces are laid out against the WALL (OUTER_HALF and the
			# storey grid), and `boxes()` measured the result to get the size in the
			# first place. Re-deriving the same list here rather than fitting it into
			# a declared box is what makes the AABB contract true by construction
			# instead of by two authors agreeing.
			var pieces := _facade_pieces(String(box.get("mesh", "")))
			return _welded_mesh(pieces, _pieces_aabb(pieces).get_center())
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


static func _crenellation_mesh(size: Vector3) -> ArrayMesh:
	"""
	The parapet ring: every merlon around the roof edge, welded into ONE mesh.

	@param size: The ring's declared bounding box — its own footprint, so the
	            merlons are laid out to fill exactly that and the AABB contract in
	            `_shape_mesh` holds.
	@return: A single-surface `ArrayMesh` centred on the origin.

	WHY IT IS WELDED AND NOT 44 NODES: the budget this building is held to is a
	DRAW CALL budget (see `BOX_BUDGET`), and a merlon is a 3 m cube you read as
	texture. `SurfaceTool.append_from` stamps one `BoxMesh` at 44 transforms into a
	single surface, which is one draw call for the whole parapet and no new concept
	— the chunk streamer solves the same problem with a MultiMesh, which this
	building deliberately does not use (check 3: "authored geometry, not chunk
	content").

	The layout closes on both corners by construction: centres walk from -inset to
	+inset in whole `MERLON_PITCH` steps, and the two runs along Z skip the corner
	slots the runs along X already filled, so no merlon is stamped twice.
	"""
	var inset: float = size.x * 0.5 - MERLON_SIZE * 0.5
	var steps := int(round(2.0 * inset / MERLON_PITCH))
	var merlon := BoxMesh.new()
	merlon.size = Vector3(MERLON_SIZE, size.y, MERLON_SIZE)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in steps + 1:
		var t := -inset + MERLON_PITCH * i
		# The two runs along X, corners included.
		st.append_from(merlon, 0, Transform3D(Basis(), Vector3(t, 0.0, -inset)))
		st.append_from(merlon, 0, Transform3D(Basis(), Vector3(t, 0.0, inset)))
		# ...and the two along Z, corners excluded — they are already standing.
		if i == 0 or i == steps:
			continue
		st.append_from(merlon, 0, Transform3D(Basis(), Vector3(-inset, 0.0, t)))
		st.append_from(merlon, 0, Transform3D(Basis(), Vector3(inset, 0.0, t)))
	return st.commit()


# ============================================================================
# THE FACADE — four welded meshes on the outside of the wall (bead godot-test1-rzk)
# ============================================================================
#
# The shape of this block is the crenellation trick with the hard part factored out.
# `_crenellation_mesh` could lay its merlons out against a declared size because a
# ring of cubes has an obvious bounding box; a timber lattice with rotated braces in
# it does not, so the direction is REVERSED here: each builder lays its pieces out
# against the WALL, `_pieces_aabb` measures what came out, and `boxes()` declares
# that. Nothing is ever fitted to a number somebody wrote down.
#
# Everything below is a pure function of the constants — no seed, no hash, no randf.
# The tower is hand-planned once and forever (CLAUDE.md), and that applies to a
# window as much as to a storey.


static func _face_normals() -> Array[Vector3]:
	"""
	The four wall faces, as outward normals.

	@return: +X (the door face), -X, +Z, -Z.

	Every builder writes ONE face in "panel space" — u along the wall, v up, n
	outward — and gets four, so a facade rule cannot come out different on the back
	of the building than on the front.
	"""
	return [Vector3(1.0, 0.0, 0.0), Vector3(-1.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, -1.0)]


static func _stamp(out: Array[Dictionary], n: Vector3, u: float, v: float,
		depth: float, size: Vector3, roll: float = 0.0) -> void:
	"""
	Place one timber on one face, in panel space.

	@param out: The piece list being built; one `{xform, size}` is appended.
	@param n: The face's outward normal, from `_face_normals()`.
	@param u: Sideways along that wall, from its middle.
	@param v: Height above the ground plane (NOT relative to anything).
	@param depth: Distance of the piece's CENTRE from the building's middle along n,
	             i.e. how far out the wall it stands.
	@param size: Full extent in panel space: (along the wall, up, out).
	@param roll: Rotation about the face normal, radians — this is the whole of what
	            makes a diagonal brace different from a post.

	`u_axis` is derived as `UP x n` rather than tabled, because that is the ONE
	choice that keeps the basis right-handed on all four faces. Hand-picking a
	sideways direction per face gets two of them wrong, and a left-handed basis
	inverts the winding: every box is then drawn inside out and back-face culling
	makes the whole facade invisible from outside — which is the only place it is
	ever seen from.
	"""
	var u_axis := Vector3.UP.cross(n)
	var basis := Basis(u_axis, Vector3.UP, n)
	if not is_zero_approx(roll):
		basis = basis * Basis(Vector3(0.0, 0.0, 1.0), roll)
	out.append({
		"xform": Transform3D(basis, u_axis * u + Vector3.UP * v + n * depth),
		"size": size,
	})


static func _pieces_aabb(pieces: Array[Dictionary]) -> AABB:
	"""
	The exact bounding box of a piece list, in the shell's local frame.

	@param pieces: `{xform, size}` entries from `_stamp`.
	@return: The AABB `boxes()` declares and `tower_shell_selfcheck` measures the
	        built mesh against.

	EIGHT CORNERS, NOT A SHORTCUT, because the braces are rotated: a rotated box's
	extent is not its size, and the whole point of declaring the measured box is that
	it is the same box the vertices produce. So this walks the same corners
	`SurfaceTool` is about to weld.
	"""
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for piece: Dictionary in pieces:
		var xform: Transform3D = piece["xform"]
		var half: Vector3 = (piece["size"] as Vector3) * 0.5
		for i in 8:
			var at: Vector3 = xform * Vector3(
				half.x if (i & 1) != 0 else -half.x,
				half.y if (i & 2) != 0 else -half.y,
				half.z if (i & 4) != 0 else -half.z)
			lo = Vector3(minf(lo.x, at.x), minf(lo.y, at.y), minf(lo.z, at.z))
			hi = Vector3(maxf(hi.x, at.x), maxf(hi.y, at.y), maxf(hi.z, at.z))
	return AABB(lo, hi - lo)


static func _welded_mesh(pieces: Array[Dictionary], centre: Vector3) -> ArrayMesh:
	"""
	Every piece of one facade layer, welded into ONE surface.

	@param pieces: `{xform, size}` entries from `_stamp`.
	@param centre: The AABB centre, subtracted so the mesh is centred on its own
	              origin — which `_shape_mesh`'s contract and the impostor's per-mesh
	              cull radius both require.
	@return: A single-surface `ArrayMesh`.

	The `BoxMesh` cache is per call and worth its four lines: a lattice is ~400
	pieces drawn from a handful of distinct sizes, so this is the difference between
	allocating four hundred meshes and allocating six.
	"""
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shapes: Dictionary = {}
	for piece: Dictionary in pieces:
		var size: Vector3 = piece["size"]
		var shape: BoxMesh = shapes.get(size)
		if shape == null:
			shape = BoxMesh.new()
			shape.size = size
			shapes[size] = shape
		var xform: Transform3D = piece["xform"]
		st.append_from(shape, 0, Transform3D(xform.basis, xform.origin - centre))
	return st.commit()


static func _facade_pieces(kind: String) -> Array[Dictionary]:
	"""
	Every timber of one facade layer. The one dispatch, read by both `boxes()` (to
	measure it) and `_shape_mesh` (to build it).

	@param kind: One of "plaster", "fachwerk", "windows", "bars".
	@return: `{xform, size}` entries; empty for an unknown kind, which then declares
	        an empty box and fails check 1 loudly rather than drawing nothing quietly.
	"""
	match kind:
		"plaster":
			return _plaster_pieces()
		"fachwerk":
			return _fachwerk_pieces()
		"windows":
			return _window_pieces(false)
		"bars":
			return _window_pieces(true)
	return []


static func _facade_box(box_name: String, kind: String, color: Color,
		layer: int) -> Dictionary:
	"""
	One facade layer as a `boxes()` table entry, measured off its own geometry.

	@param box_name: The mesh node's name.
	@param kind: The `_facade_pieces` kind, which is also the `mesh` field.
	@param color: One of the palette consts — never a literal, or the shared material
	             cache grows an entry check 4 will not account for.
	@param layer: How far OUT this sits from the wall, as a rank rather than a
	             distance: 1 is stuck to the stone (the plaster, the window
	             recesses), 2 is stuck to layer 1 (the timbers, the bars). Only
	             `build_impostor()` reads it — see `IMPOSTOR_SORT_LIFT`.
	@return: The same `{name, pos, size, color, collide, mesh}` shape as every
	        hand-written row above, plus `layer`.
	"""
	var aabb := _pieces_aabb(_facade_pieces(kind))
	return {"name": box_name, "pos": aabb.get_center(), "size": aabb.size,
		"color": color, "collide": false, "mesh": kind, "layer": layer}


static func _plaster_pieces() -> Array[Dictionary]:
	"""
	The plaster field: one panel per face over the top `FACHWERK_STOREYS`.

	A PANEL AND NOT A REPAINT, deliberately. Splitting each wall slab into
	stone-below and plaster-above would work and would cost four more table rows —
	but those slabs are `collide: true`, so it would also double the shell's
	collision shapes and put a horizontal seam at 30 m into the one geometry check 12
	is trying to prove has no ledges in it. A 40 cm panel stuck to the outside changes
	the colour of the wall and nothing about the wall.

	Each panel spans the full corner-to-corner width including its neighbours'
	thickness, so the four meet at the corners with no notch and the measured box
	comes out square.
	"""
	var out: Array[Dictionary] = []
	var half := OUTER_HALF + PLASTER_OUT
	var height := WALL_HEIGHT - FACHWERK_BASE
	for n: Vector3 in _face_normals():
		_stamp(out, n, 0.0, FACHWERK_BASE + height * 0.5, half - FACADE_THICK * 0.5,
			Vector3(2.0 * half, height, FACADE_THICK))
	return out


static func _rail_y(k: int) -> float:
	"""
	The centre height of the k-th horizontal rail of the timber frame.

	@param k: 0 at the bottom of the plaster field, `FACHWERK_STOREYS` at the top.
	@return: Metres above the ground plane.

	The two END rails are pulled half a timber INWARDS so the lattice finishes flush
	with the plaster it is drawn on instead of overhanging it — which is also what
	makes the measured box exactly the plaster band's height, with the braces safely
	inside it.
	"""
	var y := FACHWERK_BASE + STOREY_HEIGHT * k
	if k == 0:
		return y + TIMBER_WIDTH * 0.5
	if k == FACHWERK_STOREYS:
		return y - TIMBER_WIDTH * 0.5
	return y


static func _fachwerk_pieces() -> Array[Dictionary]:
	"""
	The timber lattice: rails at every storey line, posts every bay, and one diagonal
	brace per bay per storey.

	THE PITCH IS DERIVED, exactly like the merlons': the post centres walk from
	-inset to +inset in whole steps and the step is that span divided by the count,
	so there is no half-bay at either corner and no number to hand-tune when
	`TIMBER_BAY` is retuned.

	The braces alternate direction with `(bay + storey)`, which reads as a St
	Andrew's pattern across a wall while costing one timber per bay instead of two.
	A brace runs post-centre to post-centre and rail-centre to rail-centre, so it
	always lands inside the frame it braces and never outside the measured box.
	"""
	var out: Array[Dictionary] = []
	var half := OUTER_HALF + TIMBER_OUT
	var height := WALL_HEIGHT - FACHWERK_BASE
	var depth := half - FACADE_THICK * 0.5
	var inset := half - TIMBER_WIDTH * 0.5
	var steps := int(round(2.0 * inset / TIMBER_BAY))
	var pitch := 2.0 * inset / float(steps)
	for n: Vector3 in _face_normals():
		for k in FACHWERK_STOREYS + 1:
			_stamp(out, n, 0.0, _rail_y(k), depth,
				Vector3(2.0 * half, TIMBER_WIDTH, FACADE_THICK))
		for i in steps + 1:
			_stamp(out, n, -inset + pitch * i, FACHWERK_BASE + height * 0.5, depth,
				Vector3(TIMBER_WIDTH, height, FACADE_THICK))
		for storey in FACHWERK_STOREYS:
			var low := _rail_y(storey)
			var high := _rail_y(storey + 1)
			var rise := high - low
			var brace := Vector3(sqrt(pitch * pitch + rise * rise), TIMBER_WIDTH,
				FACADE_THICK)
			var angle := atan2(rise, pitch)
			for i in steps:
				if (i + storey) % TIMBER_BRACE_EVERY != 0:
					continue
				_stamp(out, n, -inset + pitch * (float(i) + 0.5), (low + high) * 0.5,
					depth, brace, angle if (i + storey) % 2 == 0 else -angle)
	return out


static func _window_pieces(bars: bool) -> Array[Dictionary]:
	"""
	The barred windows on the stone storeys — the recesses, or the iron in them.

	@param bars: false for the dark openings, true for the bars over them. ONE
	            layout function for both, because a bar that does not line up with
	            its own hole is the only way this can look wrong, and two functions
	            is how that happens.
	@return: `{xform, size}` entries for all four faces.

	The rows stop below `FACHWERK_BASE` (they are cut into stone, and the storeys
	above it are plastered) and start one storey above the ground, which is also what
	keeps them clear of the doorway without anybody having to special-case it.
	"""
	var out: Array[Dictionary] = []
	# Keep the run half a pitch off each corner, then close it on whole pitches so
	# the row is centred before its phase slides it.
	var reach := OUTER_HALF - WINDOW_PITCH * 0.5
	var count := int(floor(2.0 * reach / WINDOW_PITCH)) + 1
	var span := WINDOW_PITCH * float(count - 1)
	var depth := OUTER_HALF + (BAR_OUT - BAR_THICK * 0.5 if bars
		else WINDOW_OUT - WINDOW_THICK * 0.5)
	for n: Vector3 in _face_normals():
		for row in WINDOW_ROW_PHASE.size():
			var v := STOREY_HEIGHT * float(WINDOW_ROW_FLOOR + row) + WINDOW_SILL \
				+ WINDOW_HEIGHT * 0.5
			for i in count:
				# THE AUTHORED HOLE. Without it the rows are a grid and the building
				# reads as the office block it is pretending not to be; with it (and
				# the row phase) no two rows line up. Fixed arithmetic, no hash —
				# see the WINDOW_* block for why the tower may not roll for this.
				if (i + row * 2) % 5 == 0:
					continue
				var u := -span * 0.5 + WINDOW_PITCH * float(i) + WINDOW_ROW_PHASE[row]
				if not bars:
					_stamp(out, n, u, v, depth,
						Vector3(WINDOW_WIDTH, WINDOW_HEIGHT, WINDOW_THICK))
					continue
				for b in WINDOW_BARS:
					var offset := (float(b + 1) / float(WINDOW_BARS + 1) - 0.5) \
						* WINDOW_WIDTH
					_stamp(out, n, u + offset, v, depth,
						Vector3(BAR_WIDTH, WINDOW_HEIGHT, BAR_THICK))
	return out


static func _material(color: Color) -> StandardMaterial3D:
	"""
	The one material of this colour, for the life of the process.

	ALREADY TOON, on purpose. `ToonShading.apply_to_mesh()` skips a material whose
	`diffuse_mode` is already `DIFFUSE_TOON`, so authoring these the way that helper
	would have left them means the tower matches the cast's cel-shaded look AND can
	never be handed to the styler for a per-instance `duplicate()`. The rim numbers
	are copied from `ToonShading` deliberately — same look, one source of truth for
	what that look is, and `tower_shell_selfcheck` asserts they still agree.
	"""
	var hit: StandardMaterial3D = _materials.get(color)
	if hit != null:
		return hit
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.rim_enabled = true
	mat.rim = 0.4
	mat.rim_tint = 0.25
	if color == COLOR_BEACON:
		# The beacon is a light, not a stone: unshaded and emissive so it holds its
		# colour at any hour and at any angle. It is the one part of the real shell
		# that reads the same as its impostor counterpart.
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.emission = color
	elif color == COLOR_SPIRE:
		# The spires stay LIT — they are slate, and their shading is what gives the
		# cones a readable form — but carry a low cool emission under it, which is
		# the whole "magical" budget (see COLOR_SPIRE). Emission adds on top of the
		# toon diffuse, so the sunlit face is still the bright one.
		mat.emission_enabled = true
		mat.emission = SPIRE_GLOW
		mat.emission_energy_multiplier = SPIRE_GLOW_ENERGY
	_materials[color] = mat
	return mat


static func _impostor_color(color: Color) -> Color:
	"""
	What the shell's material of this colour actually RENDERS as, near enough for a
	flat silhouette. See `IMPOSTOR_LIT_GAIN` for why the impostor has no palette of
	its own.

	READ OFF THE SHELL'S OWN MATERIAL rather than off the colour alone, because two
	of the five are not plain lit stone: the beacon is unshaded, and the spires
	carry an emission. Modelling the light with one gain and then ignoring the
	emissive half would leave the most saturated part of the silhouette — the
	spire tips — as the one thing that still changed across the handover, which is
	the exact bug in miniature. So: lift by the gain only where there is a light to
	lift (an unshaded surface already IS its albedo), then add whatever the material
	emits.
	"""
	var mat := _material(color)
	var lit: Color = color
	if mat.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
		lit = color * IMPOSTOR_LIT_GAIN
	if mat.emission_enabled:
		lit += mat.emission * mat.emission_energy_multiplier
	return Color(minf(lit.r, 1.0), minf(lit.g, 1.0), minf(lit.b, 1.0))


static func _impostor_material(color: Color) -> StandardMaterial3D:
	"""
	The impostor's flat, fog-exempt, self-fading material.

	ITS OWN CACHE, AND THAT IS A BUG FIX. It used to key into `_materials` beside
	the shell's — safe only because the two palettes could not collide, which is
	exactly the property this bead deletes: the impostor now derives its colours
	FROM the shell's, so one shared dictionary would hand whichever builder ran
	second the other one's material. A lit, fogged "impostor" is invisible at 400 m
	and an unshaded, fog-exempt "shell" is a flat cut-out you walk into; both fail
	silently. Two dictionaries, no shared key space, no ordering to reason about.

	`disable_fog` is the load-bearing flag: without it the silhouette is erased by
	the same depth fog that erases the real building, and the impostor answers
	nothing. Unshaded keeps it a flat colour at 400 m, where a lit surface would
	just be a slightly different grey than the sky.

	`distance_fade` is the handover (see `IMPOSTOR_FADE_FAR`): opaque beyond FAR,
	gone by NEAR, linear between. PIXEL_ALPHA rather than the dither modes because
	the two buildings are COINCIDENT — a dithered impostor would punch holes in the
	shell behind it, while an alpha-blended one does not write depth at all.
	"""
	var hit: StandardMaterial3D = _impostor_materials.get(color)
	if hit != null:
		return hit
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_fog = true
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON  # so ToonShading never duplicates it
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = IMPOSTOR_FADE_NEAR
	mat.distance_fade_max_distance = IMPOSTOR_FADE_FAR
	_impostor_materials[color] = mat
	return mat
