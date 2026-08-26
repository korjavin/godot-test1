#!/usr/bin/env python3
"""
Generate the bear predator model -> assets/models/characters/bear.glb

The charger. Short, wide and heavy: the only one of the five that is bulkier
than it is long. The shoulder hump and the head slung LOW between the shoulders
are the whole silhouette — a bear that carries its head like a wolf reads as a
big dog. Thick legs and a stub of a tail keep the mass low, which is what makes
the existing waddle roll look like weight rather than a stumble.

    python3 scripts/generate_bear.py
"""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from predator_parts import box, quadruped, rgba, save  # noqa: E402

# Dark brown coat, muddy tan muzzle/underside, small black eye.
COAT = "#5a3d26"
BELLY = "#8a6a48"
DARK = "#1a120c"
EYE = "#2a1a0c"

SHAPE = dict(
    body_len=0.72, body_h=0.38, body_w=0.42,   # deep and broad: twice a wolf's bulk
    leg_len=0.34, leg_w=0.14,                  # short, thick, planted
    head_len=0.22, head_h=0.22, head_w=0.24,
    snout_len=0.14,
    neck_drop=0.16,                            # head slung low: the bear read
    tail_len=0.10, tail_w=0.09, tail_droop=0.3,
    tail_bushy=1.0,
    ears="round", ear_size=0.12,               # big round ears, set wide
    haunch=0.0,                                # the hump goes at the SHOULDER instead
)


def build_bear():
    parts = quadruped(body=COAT, belly=BELLY, dark=DARK, eye=EYE, **SHAPE)

    back_y = SHAPE["leg_len"] + SHAPE["body_h"]

    # The shoulder hump. `quadruped`'s `haunch` knob puts its bulge over the HIND
    # legs (a cat's drive); a bear's mass is over the front ones, so it gets its
    # own block here rather than a second knob nobody else would set.
    hump = 0.11
    parts.append(box(
        (SHAPE["body_len"] * 0.38, hump, SHAPE["body_w"] * 0.88),
        (SHAPE["body_len"] * 0.20, back_y + hump / 2 - 0.01, 0.0),
        rgba(COAT)))

    # Pale muzzle band across the snout — the one light patch on an otherwise
    # dark animal, and what keeps the face from vanishing at dusk.
    head_x = SHAPE["body_len"] / 2 + SHAPE["head_len"] / 2 + 0.02
    head_y = back_y - SHAPE["neck_drop"] - SHAPE["head_h"] / 2
    parts.append(box(
        (SHAPE["snout_len"] * 0.75, SHAPE["head_h"] * 0.3, SHAPE["head_w"] * 0.68),
        (head_x + SHAPE["head_len"] / 2 + SHAPE["snout_len"] * 0.45,
         head_y - SHAPE["head_h"] * 0.3, 0.0),
        rgba(BELLY)))
    return parts


if __name__ == "__main__":
    save(build_bear(), "bear")
