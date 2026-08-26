#!/usr/bin/env python3
"""
Generate the hound predator model -> assets/models/characters/hound.glb

The tracker — a feral dog, and deliberately the SMALLEST of the five. It shares
the wolf's build, so the two only stay apart at a distance by the three things
that differ hard: floppy ears instead of pricked, a thin tail carried UP instead
of a low brush, and a rusty red coat instead of grey. Change any of those and
the pack species become interchangeable on screen.

    python3 scripts/generate_hound.py
"""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from predator_parts import box, quadruped, rgba, save  # noqa: E402

# Rusty red coat, cream chest and underside, orange eye.
COAT = "#8f4f2a"
BELLY = "#e0c9a6"
DARK = "#241511"
EYE = "#e8a33c"

SHAPE = dict(
    body_len=0.58, body_h=0.22, body_w=0.22,   # smaller in every axis than the wolf
    leg_len=0.34, leg_w=0.065,
    head_len=0.16, head_h=0.15, head_w=0.15,
    snout_len=0.13,
    neck_drop=0.09,
    tail_len=0.28, tail_w=0.065,
    tail_droop=-0.40,                          # NEGATIVE: the tail rises, not droops
    tail_bushy=1.0,
    ears="flop", ear_size=0.10,
    haunch=0.0,
)


def build_hound():
    parts = quadruped(body=COAT, belly=BELLY, dark=DARK, eye=EYE, **SHAPE)

    # Cream chest blaze. On a small dark animal the chest is the only surface
    # facing the player head-on, so it carries the species' light accent.
    parts.append(box(
        (SHAPE["body_len"] * 0.12, SHAPE["body_h"] * 0.6, SHAPE["body_w"] * 0.5),
        (SHAPE["body_len"] * 0.5, SHAPE["leg_len"] + SHAPE["body_h"] * 0.4, 0.0),
        rgba(BELLY)))
    return parts


if __name__ == "__main__":
    save(build_hound(), "hound")
