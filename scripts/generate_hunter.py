#!/usr/bin/env python3
"""
Generate the GD-SURVEY hunter model -> assets/models/characters/hunter.glb

The one predator that is not an animal. Everything else the terrain spawns is a
quadruped (or a snake) built out of `quadruped()`; the hunter deliberately does
not call it, because the read that matters is MACHINE AT A GLANCE — the fear
class is carried by recognition before behaviour, and a robot assembled from the
animal builder would just be a square dog.

So the silhouette is built out of the four things an animal never has:

* A HEAD HELD FORWARD AND HIGH on a mast, level, never swinging below the
  shoulder line. Every quadruped here carries its skull at or under `back_y`
  (`neck_drop`); this one carries it a mast-height above it. That alone is most
  of the non-animal read from the side.
* A GLOWING VISOR instead of a pair of eyes. One horizontal bar, not two dots.
* PISTON LEGS: a fat barrel over a thin rod over a flat pad, all four identical
  and all four vertical. Animal legs here taper and end in a paw; a piston reads
  as a machine even in silhouette because the thin part is in the MIDDLE.
* CORPORATE LIVERY: a hazard band and an ID plate down each flank. Nothing in
  the field is painted, so paint is the tell.

And no tail — the rear is a retrieval pack with two clamp prongs, which is the
fiction (food-safety inspection units reflashed with asset-recovery firmware)
made geometry.

    python3 scripts/generate_hunter.py
"""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from predator_parts import box, rgba, save, spike  # noqa: E402

# --- Palette. THESE HEXES ARE LINEAR, NOT sRGB — see the long gamma note at the
# top of generate_snake.py's palette; the same trap applies here. Each constant
# is written with the value it actually DISPLAYS, because a colour picked by eye
# off the linear hex comes out roughly two stops too light in game.
HULL = "#1a1e23"      # cold slate chassis                     -> shows #5a6068
LIVERY = "#de4103"    # safety-orange hazard band              -> shows #f08a1c
TRIM = "#030404"      # piston rods, joints, shadow lines      -> shows #1e2024
LENS = "#09beff"      # sensor visor, the only emissive-looking part -> #35e0ff
PLATE = "#939aa4"     # pale ID plate / decal patch            -> shows #c8ccd2
BEACON = "#ff0b08"    # roof warning light                     -> shows #ff3b30

# --- Proportions, ground up. As with the quadrupeds, LEG_* alone decides how
# tall the thing stands and nothing below recomputes a y offset by hand.
HULL_LEN, HULL_H, HULL_W = 0.78, 0.26, 0.34

# The piston stack, bottom to top: pad, rod, barrel. They sum to the ride
# height, so the hull's underside lands exactly on top of the barrels.
FOOT_H, ROD_H, BARREL_H = 0.05, 0.11, 0.20
LEG_LEN = FOOT_H + ROD_H + BARREL_H
BARREL_W, ROD_W = 0.10, 0.055
LEG_X, LEG_Z = HULL_LEN * 0.33, 0.13

MAST_H = 0.14
HEAD_LEN, HEAD_H, HEAD_W = 0.26, 0.18, 0.30
HEAD_X = 0.44

PACK_LEN, PACK_H, PACK_W = 0.24, 0.28, 0.30
PRONG_LEN = 0.14

# Every joint below overlaps its neighbour by BITE rather than meeting it face to
# face. Two coincident coplanar faces z-fight, and a part that merely *touches*
# opens a hairline gap the moment anything is scaled — the same trap the wolf's
# dark-saddle comment describes, and this model is nothing but right angles.
BITE = 0.02

# --- The whole chassis is then scaled UP on export (owner: "scale hunters 150%
# bigger" -> 1.5x current size, bead godot-test1-6bj). It rides `save`'s existing
# scale argument rather than being multiplied into the proportions above, for two
# reasons: every number in this file stays the number a reader can compare against
# the other generators', and the scale is applied to the WELDED mesh before the
# feet-at-y=0 translation, so the contract `verify()` asserts survives it for free.
# 1.35 x 1.00 x 0.375 m becomes 2.025 x 1.50 x 0.5625 — still inside
# predator_parts' LENGTH_RANGE (0.6, 2.2), and still walks under every tower
# storey's ~4.6 m clear height. The .tscn capsules are the same 1.5x by hand
# (a scene cannot read a Python constant); see the hunter row's measured block in
# piglet_crocodile_ai.gd, which records both.
CHASSIS_SCALE = 1.5

BACK_Y = LEG_LEN + HULL_H          # top of the chassis, the machine's shoulder line
MAST_TOP = BACK_Y + MAST_H
HEAD_Y = MAST_TOP - BITE + HEAD_H / 2


def build_hunter():
    c_hull, c_livery, c_trim = rgba(HULL), rgba(LIVERY), rgba(TRIM)
    c_lens, c_plate, c_beacon = rgba(LENS), rgba(PLATE), rgba(BEACON)
    parts = []

    # --- Chassis: one slab, a dark skid plate under it and a dark roof panel
    # sunk a centimetre in, so the top and bottom faces never end up coplanar
    # with anything bolted to them (the z-fight the wolf's saddle comment warns
    # about).
    parts.append(box((HULL_LEN, HULL_H, HULL_W), (0.0, LEG_LEN + HULL_H / 2, 0.0), c_hull))
    parts.append(box((HULL_LEN * 0.9, HULL_H * 0.22, HULL_W * 0.9),
                     (0.0, LEG_LEN + HULL_H * 0.08, 0.0), c_trim))
    parts.append(box((HULL_LEN * 0.62, 0.03, HULL_W * 0.7),
                     (-HULL_LEN * 0.04, BACK_Y - 0.01, 0.0), c_trim))

    # --- Livery, one band and one ID plate per flank, standing 5 mm proud of the
    # side so they read as paint-on-panel rather than as part of the slab.
    for side in (1.0, -1.0):
        sz = side * (HULL_W / 2 + 0.005)
        parts.append(box((HULL_LEN * 0.72, 0.07, BITE),
                         (0.0, LEG_LEN + HULL_H * 0.62, sz), c_livery))
        parts.append(box((0.14, 0.08, BITE),
                         (-HULL_LEN * 0.24, LEG_LEN + HULL_H * 0.28, sz), c_plate))

    # --- Sensor mast and head. Carried FORWARD of the chest and ABOVE the
    # shoulder line — the inversion of every `neck_drop` in the quadruped table,
    # and the cheapest non-animal cue there is.
    parts.append(box((0.12, MAST_H + BITE, 0.14),
                     (HULL_LEN / 2 - 0.08, (BACK_Y - BITE + MAST_TOP) / 2, 0.0), c_hull))
    parts.append(box((HEAD_LEN, HEAD_H, HEAD_W), (HEAD_X, HEAD_Y, 0.0), c_hull))

    # One visor bar across the whole face instead of two eyes. Wider than the
    # skull so it survives being seen from an angle.
    parts.append(box((0.05, 0.08, HEAD_W * 0.94),
                     (HEAD_X + HEAD_LEN / 2 + 0.015, HEAD_Y + 0.01, 0.0), c_lens))
    # Chin scanner: a dark block under the visor, so the head has a front and a
    # back at a glance.
    parts.append(box((0.08, 0.05, HEAD_W * 0.5),
                     (HEAD_X + HEAD_LEN * 0.34, HEAD_Y - HEAD_H / 2 + 0.02, 0.0), c_trim))

    # Roof beacon plus two whip antennae — the top-down read, which is the angle
    # the side profile tells you nothing about.
    parts.append(box((0.07, 0.05, 0.07),
                     (HEAD_X - 0.06, HEAD_Y + HEAD_H / 2 + 0.01, 0.0), c_beacon))
    for side in (1.0, -1.0):
        parts.append(spike(0.02, 0.09,
                           (HEAD_X - 0.10, HEAD_Y + HEAD_H / 2 - 0.01,
                            side * HEAD_W * 0.36), c_trim))

    # --- Four identical piston legs. Barrel over rod over pad, plus a dark hub
    # where the barrel meets the chassis. No taper, no paw: the thin part is in
    # the middle, which is what stops it reading as a leg.
    for x in (LEG_X, -LEG_X):
        for z in (LEG_Z, -LEG_Z):
            parts.append(box((BARREL_W, BARREL_H, BARREL_W),
                             (x, FOOT_H + ROD_H + BARREL_H / 2, z), c_hull))
            parts.append(box((ROD_W, ROD_H + 2 * BITE, ROD_W),
                             (x, FOOT_H + ROD_H / 2, z), c_trim))
            parts.append(box((BARREL_W * 1.3, FOOT_H, BARREL_W * 1.1),
                             (x, FOOT_H / 2, z), c_trim))
            parts.append(box((BARREL_W * 1.15, 0.05, BARREL_W * 1.15),
                             (x, LEG_LEN - BITE, z), c_trim))

    # --- Retrieval pack where a tail would be: a slung module with two clamp
    # prongs. This is the "asset recovery" firmware made geometry, and it also
    # gives the rear a hard square end instead of an animal's taper.
    pack_x = -(HULL_LEN / 2 + PACK_LEN / 2 - BITE)
    pack_y = BACK_Y - PACK_H / 2 - BITE
    parts.append(box((PACK_LEN, PACK_H, PACK_W), (pack_x, pack_y, 0.0), c_hull))
    # Dark seam where the module bolts on. Without it the pack and the chassis are
    # the same slate at the same height and the side profile welds into one long
    # slab — i.e. back into an animal's body.
    parts.append(box((0.03, PACK_H, PACK_W * 1.04),
                     (pack_x + PACK_LEN / 2, pack_y, 0.0), c_trim))
    parts.append(box((0.03, PACK_H * 0.5, PACK_W * 0.8),
                     (pack_x - PACK_LEN / 2, pack_y, 0.0), c_livery))
    for side in (1.0, -1.0):
        parts.append(box((PRONG_LEN, 0.055, 0.05),
                         (pack_x - PACK_LEN / 2 - PRONG_LEN / 2 + BITE / 2,
                          pack_y - PACK_H / 2 + 0.08, side * 0.10), c_trim))
    return parts


if __name__ == "__main__":
    save(build_hunter(), "hunter", CHASSIS_SCALE)
