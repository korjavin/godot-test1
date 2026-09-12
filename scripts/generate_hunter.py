#!/usr/bin/env python3
"""
Generate the GD-SURVEY hunter model -> assets/models/characters/hunter.glb

The one predator that is not an animal. Everything else the terrain spawns is a
quadruped (or a snake) built out of `quadruped()`; the hunter deliberately does
not call it, because the read that matters is MACHINE AT A GLANCE — the fear
class is carried by recognition before behaviour, and a robot assembled from the
animal builder would just be a square dog.

THE GOAL IS UNCHANGED SINCE THE FIRST VERSION OF THIS FILE; THE ANSWER IS NOT.
Until bead godot-test1-hb0 the machine-at-a-glance read was bought with a
FOUR-LEGGED piston chassis and a sensor mast: not an animal, certainly, but the
owner's verdict on it was "not scary" — an inspection drone reads as equipment,
and equipment is not a fear class. The owner's reference (docs/characters/hunter.png,
canon in docs/characters/hunter.md) is a heavy armoured BIPED, and a biped is
scary for the reason a drone is not: it is shaped like a person and it is a head
taller than you. So the four things the silhouette is built from are now:

* A HUMAN SHAPE AT INHUMAN SIZE. 2.56 m tall against a 1.7 m hero and 1.24 m
  across the shoulders — the proportions of a person wearing four hundred kilos
  of plate. Nothing else in the cast stands upright, so the stance alone is the
  non-animal read from any angle, the way the mast used to be from the side.
* A GLOWING VISOR instead of a pair of eyes. One horizontal AMBER bar under a
  dark brow, in a dome helmet with a chin grille. Amber rather than the old cyan
  because the reference is amber and because a warm slit on a cold steel dome is
  the one warm thing on the model.
* BLOCK LIMBS THAT DO NOT TAPER: oversized forearms ending in fingerless slab
  fists that hang to mid-thigh, and thighs/calves the same width top to bottom
  with a knee plate bolted across the joint. An animal limb tapers to a paw; this
  one gets BIGGER toward the hand.
* CORPORATE LIVERY: brushed steel/grey-beige panels with dark seams, the crossed
  FORK-AND-SPOON emblem in blue and gold on the chest plate, and a pale
  GD-SURVEY ID plate under it. Nothing in the field is painted, so paint is the
  tell — and the emblem is the fiction (food-safety inspection units reflashed
  with asset-recovery firmware) worn where a soldier wears a unit patch.

FACE BUDGET IS THE REASON THERE ARE FOUR RIVETS AND NOT FORTY. The bead's
acceptance pins the triangle count at no more than 1.3x the old chassis's 412,
i.e. 536, and a box is 12 triangles whatever its size — so a forty-stud rivet
line would cost more than the entire torso. Four studs sit on the chest plate's
corners, where a three-quarter view catches them, and every other edge the
reference rivets is spent instead on a DARK SEAM BOX, which is one part for the
whole edge and is what actually reads at the five metres the owner rules from.
Same arithmetic killed the roof beacon, which the bead made optional.

ANIMATION: still ONE WELDED MESH. `piglet_crocodile_ai.gd::_animate_body` bobs,
rolls, sways and leans the whole `Model` node and there is no leg-phase hook to
split the legs onto (the bead offered one if the AI already had it; it does not,
and inventing one here would be a rig in everything but name). A biped leaning
into its travel axis at a 12 Hz stride reads as a stomping march, which is the
whole reason the gait numbers in the `hunter_robot` row did not have to change.

    python3 scripts/generate_hunter.py
"""

import pathlib
import sys

import trimesh

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from predator_parts import OUT_DIR, MAX_FACES, box, build, export_faceted, rgba  # noqa: E402

# --- Palette. THESE HEXES ARE LINEAR, NOT sRGB — see the long gamma note at the
# top of generate_snake.py's palette; the same trap applies here. Each constant
# is written with the value it actually DISPLAYS, because a colour picked by eye
# off the linear hex comes out roughly two stops too light in game.
# THE THREE GREYS ARE THREE VALUES, NOT THREE TINTS, and that is the whole
# lesson of the first round of this model: a light plate, a mid plate and a
# near-black joint, alternating DOWN EVERY LIMB. Built once with the two greys a
# stop apart, the machine came back as a pale blob — chest, pauldrons and arms
# welded into one silhouette under the game's white sky, and the head read as a
# hat on top of it. Faceted shading gives a box about a stop of self-shadow, so
# two colours that close are the same colour once they are lit.
STEEL = "#2d2c28"      # brushed grey-beige plate: chest, thighs, forearms -> #747370
STEEL_DK = "#100f0d"   # the mid value: calves, upper arms, pelvis, boots  -> #474540
SEAM = "#020303"       # joints, seams, grille, brow, fists                -> #191b1d
LENS = "#ff6803"       # the visor slit, the only emissive-looking part      -> #ffab1c
PLATE = "#9c9582"      # the pale GD-SURVEY ID plate                         -> #cdc9bd
EMBLEM_BLUE = "#0725ab"  # the fork of the corporate emblem                  -> #2f6ad6
EMBLEM_GOLD = "#be6507"  # the spoon of the corporate emblem                 -> #e0a92e

# --- Proportions, ground up, IN FINAL METRES. The old chassis authored a ~1 m
# machine and multiplied it by a CHASSIS_SCALE on export, which had accumulated
# two owner-ruled 1.5x re-scales and a paragraph explaining which was which.
# There is no scale factor any more: every number below is the metre it ships as,
# `build()` is called at 1.0, and a retune is a number in this block rather than
# an archaeology problem. The heights are a stack — each part's span is written
# beside it, and each overlaps its neighbour (see BITE). The two numbers a
# reader wants first — 2.56 m to the crown of the dome, 1.24 m across the
# pauldrons — are NOT constants here: they are sums of the stack, and a constant
# that merely restates a sum is a second place for the truth to live. They are
# asserted (as a window) in `verify_hunter` and printed on every build.

# Every joint below overlaps its neighbour by BITE rather than meeting it face to
# face. Two coincident coplanar faces z-fight, and a part that merely *touches*
# opens a hairline gap the moment anything is scaled — the same trap the wolf's
# dark-saddle comment describes, and this model is nothing but right angles.
#
# STATING THE RULE WAS NOT ENOUGH: the first build of this biped broke it seven
# times — both emblem bars on one plane, the chest and its rim sharing a bottom
# face, both fists coplanar with a thigh, the brow meeting the visor face to
# face — none of which a screenshot shows and all of which z-fight on somebody
# else's GPU. `assert_no_shared_planes()` below audits every pair on every
# build, which is why some numbers here look untidy: a coordinate is nudged a
# millimetre off its neighbour's ON PURPOSE.
BITE = 0.02

LEG_Z = 0.235          # half the stance; deliberately narrower than the shoulders
ARM_Z = 0.46           # centre-line of the arm stack, OUTSIDE the chest's 0.37
# The chest plate's front face is x = 0.36. Each decal spans its own slab across
# it — every one biting INTO the plate rather than floating 5 mm off it, and no
# two sharing an edge. That is what the four hand-picked thicknesses buy.
DECAL_BLUE = (0.0290, 0.37300)    # (x thickness, x centre) -> 0.3585 .. 0.3875
DECAL_GOLD = (0.0310, 0.37350)    #                         -> 0.3580 .. 0.3890
DECAL_PLATE = (0.0285, 0.37175)   #                         -> 0.3575 .. 0.3860
DECAL_TEXT = (0.0210, 0.37950)    #                         -> 0.3690 .. 0.3900


def build_hunter():
    c_steel, c_dark, c_seam = rgba(STEEL), rgba(STEEL_DK), rgba(SEAM)
    c_lens, c_plate = rgba(LENS), rgba(PLATE)
    c_blue, c_gold = rgba(EMBLEM_BLUE), rgba(EMBLEM_GOLD)
    parts = []

    # --- Legs, mirrored. Boot -> calf -> knee plate -> thigh -> hip joint, and
    # NOTHING IN THE STACK TAPERS: the calf is as thick as the thigh and the
    # boot is wider than both. A leg that narrows toward the ground is the one
    # thing that would pull this back toward the animals it stands beside. The
    # COLOURS alternate down the stack — dark boot, mid calf, black knee, light
    # thigh — which is what makes a welded column of boxes read as a jointed leg.
    for side in (1.0, -1.0):
        z = side * LEG_Z
        # Boot: a black sole under a squat upper, the sole LONGER than the boot so
        # the machine has a visible FOOT rather than a shin ending on the floor.
        parts.append(box((0.58, 0.09, 0.36), (0.06, 0.045, z), c_seam))    # 0.00-0.09
        parts.append(box((0.50, 0.21, 0.33), (0.03, 0.175, z), c_dark))    # 0.07-0.28
        parts.append(box((0.40, 0.52, 0.31), (0.00, 0.52, z), c_dark))     # 0.26-0.78
        # Knee plate: wider and deeper than the calf it caps and wider than the
        # thigh above it, so the joint is a bolted-on slab and not a crease.
        parts.append(box((0.48, 0.16, 0.35), (0.03, 0.82, z), c_seam))     # 0.74-0.90
        parts.append(box((0.46, 0.48, 0.36), (0.00, 1.12, z), c_steel))    # 0.88-1.36
        # Hip: inset fore-aft and proud sideways, which is what makes it read as
        # a joint the thigh swings on instead of another panel.
        parts.append(box((0.38, 0.16, 0.42), (0.00, 1.36, z), c_seam))     # 1.28-1.44

    # --- Pelvis and abdomen, and BOTH ARE BLACK. Not decoration: the forearms
    # hang exactly here, and a lit hip beside a lit forearm welds the arms into
    # the body — measured, in the second round of this model, as a single slab
    # from shoulder to knee. A black waist between two steel forearms is the
    # whole separation, and it is also what the reference does.
    parts.append(box((0.62, 0.28, 0.64), (0.0, 1.48, 0.0), c_seam))        # 1.34-1.62
    parts.append(box((0.52, 0.16, 0.50), (0.0, 1.68, 0.0), c_seam))        # 1.60-1.76

    # --- The barrel chest, the model's subject, and it is NARROWER THAN THE
    # SHOULDERS ON PURPOSE (0.74 against the pauldrons' 1.24). Built as wide as
    # them, the torso and both shoulders weld into one slab whose top edge reads
    # as the top of a head — which is exactly what the first round of this model
    # photographed. The rim under it and the collar yoke over it are black and
    # PROUD of the plate on every axis (a band sunk inside the chest box would
    # simply not be drawn), and the yoke is narrow, so the head rises out of a
    # notch between two shoulder humps rather than off a flat shelf.
    parts.append(box((0.68, 0.42, 0.74), (0.02, 1.95, 0.0), c_steel))      # 1.74-2.16
    parts.append(box((0.70, 0.075, 0.76), (0.02, 1.762, 0.0), c_seam))     # 1.7245-1.7995
    parts.append(box((0.56, 0.12, 0.50), (0.0, 2.16, 0.0), c_seam))        # 2.10-2.22
    # Backpack plate: the rear is a hard square end rather than a spine, and it
    # is what the old model's retrieval pack has become now that there is no tail
    # position to hang one off.
    parts.append(box((0.14, 0.40, 0.62), (-0.36, 1.95, 0.0), c_dark))

    # --- The livery. Two crossed bars for the corporation's fork-and-spoon, a
    # pale ID plate under them with one dark bar across it for the lettering.
    # NO TEXT GEOMETRY: at the five metres this is ruled from, a dark bar on a
    # pale rectangle is exactly what a word looks like, and it costs one box.
    # `roll` rotates about X, which is the only axis that tilts a bar within the
    # chest's FRONT face (the YZ plane).
    parts.append(box((DECAL_BLUE[0], 0.30, 0.065), (DECAL_BLUE[1], 2.00, 0.0),
                     c_blue, roll=0.62))
    # The spoon is a HAIR longer and thicker than the fork. Half of that is the
    # picture (a spoon is the fatter of the two) and half is the plane audit: two
    # bars that differ only by the sign of their roll have an identical bounding
    # box, and the audit cannot see that their tilted faces never meet.
    parts.append(box((DECAL_GOLD[0], 0.305, 0.067), (DECAL_GOLD[1], 2.00, 0.0),
                     c_gold, roll=-0.62))
    parts.append(box((DECAL_PLATE[0], 0.10, 0.38), (DECAL_PLATE[1], 1.83, 0.0), c_plate))
    parts.append(box((DECAL_TEXT[0], 0.04, 0.29), (DECAL_TEXT[1], 1.83, 0.0), c_seam))

    # Four rivet studs, one per corner of the chest plate. See the face-budget
    # paragraph in the module docstring for why there are four of them.
    for sy in (2.10, 1.86):
        for sz in (0.31, -0.31):
            parts.append(box((0.03, 0.05, 0.05), (0.365, sy, sz), c_seam))

    # --- Arms, mirrored. Pauldron -> upper arm -> elbow -> OVERSIZED forearm ->
    # slab fist, and the stack gets WIDER on the way down. The fists hang at
    # mid-thigh, which is the reference's single loudest proportion and the thing
    # that makes the machine read as heavy rather than tall. The pauldrons top out
    # ABOVE the chest, so the shoulder line is the silhouette's highest point
    # short of the head.
    for side in (1.0, -1.0):
        z = side * ARM_Z
        parts.append(box((0.52, 0.32, 0.30), (0.0, 2.08, side * 0.46), c_steel))  # 1.92-2.24
        parts.append(box((0.50, 0.06, 0.32), (0.0, 1.93, side * 0.46), c_seam))
        parts.append(box((0.32, 0.32, 0.26), (0.0, 1.78, z), c_dark))             # 1.62-1.94
        parts.append(box((0.30, 0.10, 0.32), (0.0, 1.60, z), c_seam))             # 1.55-1.65
        parts.append(box((0.44, 0.46, 0.30), (0.02, 1.36, z), c_steel))           # 1.13-1.59
        parts.append(box((0.42, 0.22, 0.28), (0.035, 1.03, z), c_seam))           # 0.92-1.14

    # --- Neck and dome. A visible dark NECK (the first round had none worth the
    # name, and a head bolted straight onto a torso is a torso), a two-step dome
    # over it, one AMBER slit across the face with a dark brow above and a dark
    # chin grille below. The brow is what makes the lens a SLIT rather than a
    # panel: without it the amber bar sits on a pale dome and loses its edge at
    # any distance.
    parts.append(box((0.28, 0.16, 0.28), (0.02, 2.26, 0.0), c_seam))       # 2.18-2.34
    parts.append(box((0.42, 0.20, 0.40), (0.03, 2.40, 0.0), c_steel))      # 2.30-2.50
    parts.append(box((0.34, 0.12, 0.32), (0.02, 2.50, 0.0), c_steel))      # 2.44-2.56
    parts.append(box((0.055, 0.05, 0.36), (0.2145, 2.455, 0.0), c_seam))
    parts.append(box((0.055, 0.066, 0.34), (0.21625, 2.400, 0.0), c_lens))
    parts.append(box((0.07, 0.08, 0.26), (0.21, 2.335, 0.0), c_seam))
    return parts


def assert_no_shared_planes(parts) -> None:
    """No two parts may put a face on the same plane where those faces overlap.

    THE BITE RULE, ENFORCED. Every part here is an axis-aligned box — the two
    emblem bars are rolled, but a roll about X leaves their X faces exactly where
    the size puts them, and their AABB is conservative on the other two axes,
    which for a guard is the safe direction to be wrong in. So two parts share a
    face plane exactly when one axis has a coincident bound AND they overlap with
    positive area on the other two: that is either a z-fight or the face-to-face
    touch the BITE comment forbids, and a picture shows neither reliably (the
    winner of a z-fight is the driver's business, so the model can look right
    here and wrong on a player's machine).

    The tolerance is 0.1 mm — under it two coordinates were meant to be the same
    number, over it the offset is deliberate. It runs on the UNWELDED parts
    because after `trimesh.util.concatenate` there are no parts left to name.
    """
    bounds = [p.bounds for p in parts]
    for i, a in enumerate(bounds):
        for j in range(i + 1, len(bounds)):
            b = bounds[j]
            for axis in range(3):
                others = [k for k in range(3) if k != axis]
                if any(min(a[1][k], b[1][k]) - max(a[0][k], b[0][k]) <= 1e-9 for k in others):
                    continue
                for va in (a[0][axis], a[1][axis]):
                    for vb in (b[0][axis], b[1][axis]):
                        assert abs(va - vb) > 1e-4, (
                            f"hunter: parts {i} and {j} share the plane "
                            f"{'xyz'[axis]} = {va:.5f} and overlap on it — z-fight. "
                            "Nudge one of them by a millimetre.")


def verify_hunter(mesh: trimesh.Trimesh) -> None:
    """Assert enemy-model contracts and the hunter's own size envelope.

    The shared `verify()` in predator_parts cannot judge this model, for two
    reasons and neither of them is new. Its LENGTH_RANGE (0.6, 2.2) is an
    ABSOLUTE-size envelope for the animals, so a 2.56 m machine would have to
    widen it and loosen every quadruped's guard; and its "longer than it is
    wide" proportion guard is a statement about ANIMALS — a biped is broader
    across the shoulders than it is deep front to back, which is exactly what
    that assert exists to reject. So the hunter carries its own window, beside
    the humanoid bosses' `verify_titan` / `verify_clown`, the way they do.

    The window is written around the BIPED and rejects the four-legged chassis
    it replaced (3.04 m long, 0.84 m wide) on three separate clauses, so a stale
    generator or a stale .glb fails here rather than shipping a wrong-shaped
    machine over a capsule measured off the other one.
    """
    assert len(mesh.faces) > 0, "hunter: empty mesh"
    assert len(mesh.faces) <= MAX_FACES, f"hunter: {len(mesh.faces)} faces exceeds {MAX_FACES}"
    # The bead's own perf clause: no more than 1.3x the 412 faces of the chassis
    # this replaced. Pinned here rather than left to a reviewer's arithmetic,
    # because the cheapest way to "improve" a blocky model is to add boxes.
    assert len(mesh.faces) <= 535, \
        f"hunter: {len(mesh.faces)} faces is over 1.3x the 412 the old chassis cost"

    lo, hi = mesh.bounds
    assert abs(lo[1]) < 1e-6, f"hunter: feet at y={lo[1]:.4f}, must be 0"

    height = hi[1] - lo[1]
    assert 2.4 <= height <= 2.6, f"hunter: height {height:.2f}m outside [2.4, 2.6]"

    width = hi[2] - lo[2]
    depth = hi[0] - lo[0]
    assert 1.1 <= width <= 1.4, f"hunter: shoulders {width:.2f}m outside [1.1, 1.4]"
    # A BIPED IS BROADER THAN IT IS DEEP — the inverse of the animals' guard, and
    # the clause that rejects the old four-legged chassis outright.
    assert width > depth, f"hunter: {depth:.2f}m deep against {width:.2f}m wide — not a biped"
    assert height > width, f"hunter: {height:.2f}m tall is not over {width:.2f}m wide"
    # NOSE ALONG +X, and asked of the HEAD rather than of the bounding box. A
    # bare `hi[0] > 0` is satisfied by one stray millimetre and would bless a
    # machine built facing backwards — which matters more here than on a
    # quadruped, because a biped's bounding box is nearly symmetric fore-aft
    # (this one is -0.43 to +0.39) and gives the test nothing to lean on. The
    # dome is the only part above 2.2 m, so this says "the face is on the front".
    head = mesh.vertices[mesh.vertices[:, 1] > 2.2]
    assert len(head) > 0 and head[:, 0].max() > 0.2, \
        "hunter: the head's front is not on +X — is the model facing backwards?"

    bias = hi[2] + lo[2]
    assert abs(bias) <= 1e-6, f"hunter: off-centre on z (bias {bias:.4f})"
    # ...and it stands on its feet rather than on one of them.
    assert abs(mesh.bounds[0][2] + mesh.bounds[1][2]) <= 1e-6

    colors = mesh.visual.vertex_colors
    assert colors is not None and len(colors) == len(mesh.vertices), \
        "hunter: missing vertex colors"


def save_hunter() -> trimesh.Trimesh:
    """Weld at final metres, check against verify_hunter, export, report."""
    parts = build_hunter()
    assert_no_shared_planes(parts)
    mesh = build(parts)
    verify_hunter(mesh)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / "hunter.glb"
    export_faceted(mesh, path)
    lo, hi = mesh.bounds
    print(f"✓ hunter: {path}")
    print(f"  {len(mesh.vertices)} verts / {len(mesh.faces)} faces")
    print(f"  {hi[0] - lo[0]:.2f} m deep, {hi[1]:.2f} m tall, {hi[2] - lo[2]:.2f} m wide")
    # The three numbers hunter_robot.tscn and tower_guard.tscn carry by hand — a
    # scene cannot read a Python constant, so the generator prints what they owe.
    print(f"  capsule: radius {(hi[2] - lo[2]) / 2.0:.4f}, height {hi[1]:.4f}, "
          f"upright at (0, {hi[1] / 2.0:.4f}, 0)")
    return mesh


if __name__ == "__main__":
    save_hunter()
