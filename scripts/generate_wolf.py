#!/usr/bin/env python3
"""
Generate the wolf predator model -> assets/models/characters/wolf.glb

The pack hunter. Read at a distance it has to be the LEAN one: long legs, a deep
narrow chest, pricked ears and a heavy brush of a tail carried low. Wolves
surround the player rather than charge them, so the silhouette is most often seen
from the side and from behind — hence the shoulder ruff and the dark saddle,
which are the two parts still legible once the head is turned away.

    python3 scripts/generate_wolf.py
"""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from predator_parts import box, quadruped, rgba, save  # noqa: E402

# Winter-grey coat, pale throat and underside, amber eye.
COAT = "#6b6b71"
BELLY = "#cfcac0"
DARK = "#1b1a1d"
EYE = "#f2c53d"

# One table of proportions, so the flourishes below can be placed off the same
# numbers instead of re-typing them and drifting.
SHAPE = dict(
    body_len=0.68, body_h=0.24, body_w=0.26,
    leg_len=0.40, leg_w=0.075,          # the longest legs of the four quadrupeds
    head_len=0.20, head_h=0.17, head_w=0.17,
    snout_len=0.15,                     # long muzzle: the canid giveaway
    neck_drop=0.06,                     # head carried just below the shoulder
    tail_len=0.36, tail_w=0.12, tail_droop=0.30,
    tail_bushy=2.2,                     # stays thick most of its length: a brush
    ears="point", ear_size=0.10,
    haunch=0.03,
)


def build_wolf():
    parts = quadruped(body=COAT, belly=BELLY, dark=DARK, eye=EYE, **SHAPE)

    back_y = SHAPE["leg_len"] + SHAPE["body_h"]

    # Shoulder ruff — a wider, taller collar over the chest. The mane is how a
    # wolf is recognised from behind, which is the angle a surrounding pack
    # shows the player most of the time.
    parts.append(box(
        (SHAPE["body_len"] * 0.24, SHAPE["body_h"] * 1.15, SHAPE["body_w"] * 1.25),
        (SHAPE["body_len"] * 0.34, back_y - SHAPE["body_h"] * 0.5, 0.0),
        rgba(COAT)))

    # Dark saddle down the spine, so the back reads as patterned from overhead —
    # the angle where the side profile tells you nothing. Sunk a centimetre INTO
    # the torso: sitting it exactly on `back_y` would make its underside coplanar
    # with the torso's top face and the two would z-fight.
    parts.append(box(
        (SHAPE["body_len"] * 0.7, 0.04, SHAPE["body_w"] * 0.75),
        (-SHAPE["body_len"] * 0.05, back_y - 0.01, 0.0),
        rgba(DARK)))
    return parts


if __name__ == "__main__":
    save(build_wolf(), "wolf")
