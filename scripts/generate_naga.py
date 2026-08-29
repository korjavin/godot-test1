#!/usr/bin/env python3
"""
Generate the desert naga -> assets/models/characters/naga.glb

The DESERT band's boss ("Nagas inspired by hmm3"): an armoured upright torso with
four blade-armed arms, sitting on a coiled serpent body. The desert already has
the sand viper as its ordinary predator and that pairing is deliberate rather
than a repeat — the viper is a 0.2 m ambusher that buries itself, this never
hides. Same band, opposite silhouettes, which is why the two palettes below are
also deliberately opposite (charcoal snake, teal-and-gold naga).

The lower body is the toolkit's serpentine machinery, spent twice:

* THE COIL is three stacked rings of blocks, each ring a full turn of shrinking
  cubes with its start angle staggered half a step so the stack reads as one
  wound body rather than as a wedding cake. A full ring is mirror-symmetric about
  the spine by construction (the angles come in +-a pairs), which is what lets
  this model be verified `symmetric=True` — unlike the snake, whose S-curve is
  genuinely lopsided.
* THE TAIL is `tapered_chain`, the same helper every predator's tail uses, laid
  straight back out of the bottom ring so the animal is longer than it is wide
  (`verify` insists on that, and a pure coil is round).

WHY NOT `necks`: a naga has one head. The multi-head branch point ships in the
same bead but belongs to the hydra; spending it here for a fan of one would be a
more expensive way to write four boxes.

    python3 scripts/generate_naga.py
"""

import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from predator_parts import box, rgba, save, spike, tapered_chain  # noqa: E402

# --- Palette. READ THE GAMMA NOTE BEFORE EDITING. -----------------------------
#
# THESE HEXES ARE LINEAR, NOT sRGB, exactly as in generate_snake.py. Godot
# imports GLB vertex colours with `vertex_color_is_srgb = false`, so each byte
# reaches ALBEDO as-is and every constant here renders MUCH LIGHTER than it looks
# in a text editor. Pick a colour by deciding the DISPLAYED value and converting
# back (`linear = ((srgb + 0.055) / 1.055) ** 2.4`), never by eye off the hex —
# that mistake is what made the sand viper invisible in PR #78, in THIS BIOME.
#
# MEASURED against this boss's own band. The desert ground is `desert_color`
# (vec3(0.78, 0.68, 0.44), displays #e5d7b1) mottled +-12%:
#
#   SCALES #031414 displays #1c4f4f (deep teal)  vs sand  5.71 - 7.14 : 1
#   GOLD   #b15f0d displays #d9a440              vs sand  1.39 - 1.74 : 1
#          ...low against sand and that is the point: gold is armour, so it is
#          only ever seen ON the teal (4.09 : 1 against the scales), the same
#          role the viper's pale diamonds play on its charcoal.
#   BONE   #d8c9a3 displays #ede6d1 — fangs and belly scutes, 1.03 - 1.29 : 1
#          against sand, again read against the scales (11.0 : 1).
#   EYE    #e37a03 displays #f2b81c — the viper's amber, so a desert predator's
#          eye stays a desert predator's eye.
#
# For the record, and because the hydra ships in the same bead: these scales are
# 4.29 - 5.34 : 1 against plains grass too, so nothing here is band-fragile.
SCALES = "#031414"   # coil, tail, torso, head
GOLD = "#b15f0d"     # pauldrons, chest plate, belt, crown, blades
BONE = "#d8c9a3"     # belly scutes, fangs
DARK = "#020101"     # pupils, snout tip
EYE = "#e37a03"      # hot amber

# --- The coil: (ring radius, ring centre y, block count, cube edge). Read from
# the ground up; the extents are what hold the whole animal inside the 0.30 m
# capsule radius naga.tscn uses (0.20 + 0.18/2 = 0.29 at the widest ring).
COIL_RINGS = (
    (0.200, 0.090, 8, 0.18),
    (0.155, 0.245, 7, 0.16),
    (0.110, 0.375, 6, 0.14),
)
COIL_TOP = 0.44        # where the torso takes over from the coil

TAIL_SEGS = 5
TAIL_SEG = 0.10
TAIL_THICK = 0.16      # cross-section where it leaves the bottom ring

TORSO_H = 0.46
SHOULDER_W = 0.48
HEAD_H = 0.20

# Two pairs of arms, HMM3's several-armed silhouette without the face cost of
# six: (shoulder y, shoulder half-width, upper-arm length, blade length).
ARM_PAIRS = (
    (0.92, 0.22, 0.26, 0.18),
    (0.74, 0.19, 0.22, 0.16),
)


def build_naga():
    c_scale, c_gold = rgba(SCALES), rgba(GOLD)
    c_bone, c_dark, c_eye = rgba(BONE), rgba(DARK), rgba(EYE)
    parts = []

    # --- Coil. Each ring is a full turn of cubes; the half-step start offset
    # staggers one ring against the next so the joins interlock.
    for ring, (radius, cy, count, cube) in enumerate(COIL_RINGS):
        for i in range(count):
            a = (i + 0.5 * (ring % 2)) * 2.0 * np.pi / count
            parts.append(box((cube, cube, cube),
                             (np.cos(a) * radius, cy, np.sin(a) * radius), c_scale))
        # A bone scute on the front of each ring: the underside a coiled snake
        # actually shows, and the only light thing low on the silhouette.
        parts.append(box((cube * 0.4, cube * 0.55, cube * 1.1),
                         (radius + cube * 0.36, cy, 0.0), c_bone))

    # --- Tail, straight back out of the bottom ring, dropping as it thins so it
    # keeps lying ON the ground rather than in it (`build` would otherwise lift
    # the whole animal to compensate and float the coil).
    r0, y0, _, cube0 = COIL_RINGS[0]
    tail_dy = -((TAIL_THICK - TAIL_THICK * 0.3) / 2.0) / (TAIL_SEGS - 1) / TAIL_SEG
    parts += tapered_chain(
        (-r0 - cube0 * 0.4, TAIL_THICK / 2.0, 0.0),
        TAIL_SEG, TAIL_SEGS, TAIL_THICK, TAIL_THICK * 0.3, c_scale,
        dx=-1.0, dy=tail_dy,
    )

    # --- Torso rising out of the top ring, with a gold chest plate over it.
    torso_y = COIL_TOP + TORSO_H / 2
    parts.append(box((0.24, TORSO_H, 0.34), (0.02, torso_y, 0.0), c_scale))
    parts.append(box((0.10, TORSO_H * 0.5, 0.30), (0.13, torso_y + 0.05, 0.0), c_gold))
    parts.append(box((0.20, 0.07, 0.36), (0.02, COIL_TOP + 0.05, 0.0), c_gold))   # belt
    parts.append(box((0.20, 0.11, SHOULDER_W), (0.0, COIL_TOP + TORSO_H, 0.0), c_gold))

    # --- Arms. Two mirrored pairs, each an upper arm hanging down, a forearm
    # swung forward and a gold blade in place of a hand.
    for sy, hw, upper, blade in ARM_PAIRS:
        for side in (1.0, -1.0):
            ez = side * hw
            parts.append(box((0.10, upper, 0.10), (0.02, sy - upper / 2, ez), c_scale))
            fy = sy - upper - 0.03
            parts.append(box((0.19, 0.09, 0.09), (0.13, fy, ez + side * 0.015), c_scale))
            parts.append(box((blade, 0.05, 0.05),
                             (0.23 + blade / 2, fy, ez + side * 0.015), c_gold))

    # --- Neck and head, carried high and level.
    neck_y = COIL_TOP + TORSO_H + 0.11
    parts.append(box((0.12, 0.11, 0.15), (0.02, neck_y + 0.05, 0.0), c_scale))
    head_y = neck_y + 0.10 + HEAD_H / 2
    parts.append(box((0.22, HEAD_H, 0.20), (0.06, head_y, 0.0), c_scale))
    # Jaw, fangs, dark snout tip.
    parts.append(box((0.13, 0.09, 0.15), (0.19, head_y - 0.04, 0.0), c_scale))
    parts.append(box((0.05, 0.05, 0.13), (0.255, head_y - 0.06, 0.0), c_bone))
    parts.append(box((0.03, 0.05, 0.09), (0.275, head_y - 0.02, 0.0), c_dark))

    # --- Eyes, straddling the side of the skull (tucked in even a centimetre and
    # the head block swallows them — see `quadruped`).
    for side in (1.0, -1.0):
        ez = side * 0.10
        parts.append(box((0.05, 0.05, 0.03), (0.10, head_y + 0.03, ez), c_eye))
        parts.append(box((0.025, 0.025, 0.025), (0.125, head_y + 0.03, ez), c_dark))

    # --- Crown: a gold cobra-hood fan, the tallest thing on the animal and what
    # makes the silhouette read as a naga rather than as a snake standing up.
    for dz, height in ((0.0, 0.30), (0.085, 0.22), (-0.085, 0.22), (0.15, 0.13), (-0.15, 0.13)):
        parts.append(spike(0.05, height, (0.0, head_y + HEAD_H / 2 - 0.01, dz), c_gold))
    return parts


if __name__ == "__main__":
    # symmetric=True: unlike the snake, every ring is a full turn and every arm
    # is mirrored, so a z-bias here is a real mistake and not a pose.
    save(build_naga(), "naga")
