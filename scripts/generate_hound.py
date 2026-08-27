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

# --- Palette. Deep rust on pale pavement. READ THE GAMMA NOTE BEFORE EDITING. --
#
# THESE HEXES ARE LINEAR, NOT sRGB. Godot imports this GLB's vertex colours with
# `vertex_color_is_srgb = false`, so each byte is fed to ALBEDO as-is and every
# constant here renders MUCH LIGHTER than it looks in a text editor. `#1b0904`
# below is not "nearly black on screen", it is the deep rust `#5c3522`. Pick a
# colour by deciding the DISPLAYED value and converting back
# (`linear = ((srgb + 0.055) / 1.055) ** 2.4`), never by eye off the hex — that
# mistake is what produced the sand viper's camouflage bug (see the same note in
# generate_snake.py), and this animal shipped with the identical version of it.
#
# WHAT WAS WRONG. The rusty red `#8f4f2a` DISPLAYS as `#c59771`, a pale tan. Its
# own ground is ground.gdshader's `city_color` vec3(0.50, 0.48, 0.45), displaying
# `#bcb8b3`. That is 1.32:1 — the hound was the pavement. It matters more here
# than for most: CITY_CROC_DIVISOR thins this band to ~40% of the usual predator
# count precisely so the city reads as the SAFE territory, which means the few
# that are there have to be seen, or the band stops being safe and starts being
# quiet-then-fatal.
#
# WHAT IT IS NOW. The same rust, four stops down. Measured against that ground
# across its ±12% mottling, coat-vs-pavement is 4.80–5.97:1 (was 1.18–1.47:1),
# and against the city's own walls 4.6:1 (weathered render) to 7.5:1 (limewash).
# The hue is untouched on purpose: rust is the one thing keeping this animal
# apart from the timber wolf's grey at a distance, and the file header above is
# right that losing it makes the two pack species interchangeable on screen.
# The cream chest blaze below now runs 8.6:1 against the coat, so the head-on
# silhouette this small dog is usually seen in is the highest-contrast view of it.
COAT = "#1b0904"     # coat -> shows #5c3522, deep rust
BELLY = "#decaa4"    # underside + chest blaze -> shows #f0e6d2, cream
DARK = "#030201"     # paws, snout tip, pupil -> shows #1c160d
EYE = "#ff8a08"      # hot amber, so the eye pops off a dark skull -> #ffc232

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
