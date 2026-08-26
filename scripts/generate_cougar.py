#!/usr/bin/env python3
"""
Generate the cougar predator model -> assets/models/characters/cougar.glb

The pouncer. Everything here says "coiled": a long low body slung between short
legs, a heavy haunch over the back ones, a small round-eared head carried level
with the spine, and a tail nearly as long as the body. That tail is the point —
it is the one part still swinging while the cat is otherwise crouched and still,
so the whole-body sway has something to sell the pounce with.

    python3 scripts/generate_cougar.py
"""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from predator_parts import box, quadruped, rgba, save  # noqa: E402

# Desert-tan coat, cream underside, green eye (the one bright accent).
COAT = "#b8894e"
BELLY = "#e8dcc0"
DARK = "#2a1f16"
EYE = "#7ad14a"

SHAPE = dict(
    body_len=0.72, body_h=0.22, body_w=0.24,
    leg_len=0.36, leg_w=0.07,
    head_len=0.17, head_h=0.16, head_w=0.19,   # wide, short skull: cat, not dog
    snout_len=0.09,                            # blunt muzzle
    neck_drop=0.0,                             # head level with the back
    tail_len=0.55, tail_w=0.08, tail_droop=0.10,
    tail_bushy=1.0,                            # even taper: a whip, not a brush
    ears="round", ear_size=0.075,
    haunch=0.06,                               # rear drive, above the shoulder line
)


def build_cougar():
    parts = quadruped(body=COAT, belly=BELLY, dark=DARK, eye=EYE, **SHAPE)

    # Dark tail tip — the cougar's field mark, stuck on the far end of the
    # longest and most visible part of the model. `quadruped` appends the tail
    # last, so the final part IS the last segment; deriving the position from it
    # keeps the tip attached however the tail is retuned.
    tip = parts[-1].bounds.mean(axis=0)
    seg = SHAPE["tail_len"] / 5.0
    parts.append(box((seg * 0.9, 0.055, 0.055), (tip[0] - seg * 0.7, tip[1], tip[2]), rgba(DARK)))
    return parts


if __name__ == "__main__":
    save(build_cougar(), "cougar")
