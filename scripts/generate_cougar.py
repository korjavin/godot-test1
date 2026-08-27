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

# --- Palette. Dark tawny cat on pale scree. READ THE GAMMA NOTE BEFORE EDITING. -
#
# THESE HEXES ARE LINEAR, NOT sRGB. Godot imports this GLB's vertex colours with
# `vertex_color_is_srgb = false`, so each byte is fed to ALBEDO as-is and every
# constant here renders MUCH LIGHTER than it looks in a text editor. `#170e06`
# below is not "nearly black on screen", it is the dark tawny umber `#55422a`.
# Pick a colour by deciding the DISPLAYED value and converting back
# (`linear = ((srgb + 0.055) / 1.055) ** 2.4`), never by eye off the hex — that
# mistake is what produced the sand viper's camouflage bug (see the same note in
# generate_snake.py), and this animal shipped with the identical version of it.
#
# WHAT WAS WRONG. The art track built this cat desert-tan (`#b8894e`), which
# DISPLAYS as `#ddc296` — a pale sandy cream. Its own ground is
# ground.gdshader's `mountain_color` vec3(0.45, 0.43, 0.40), displaying `#b3afaa`.
# That is a contrast ratio of 1.26:1, worse than the sand viper's 1.08:1 was by
# any margin worth arguing about: the cougar WAS the mountain. On an animal whose
# whole behaviour is a >8.5 m/s pounce out of nowhere, invisibility is not
# atmosphere, it is a hit with no telegraph.
#
# WHAT IT IS NOW. The coat drops to a dark tawny umber and keeps its hue, so this
# is still a big cat and still not the wolf's grey or the hound's rust. Measured
# against that same ground across its ±12% mottling, coat-vs-scree is 3.91–4.85:1
# (was 1.14–1.42:1). The cream belly (7.5:1 on the coat) and the green eye
# (5.9:1) carry the internal form that a uniformly dark animal would lose.
#
# THE DARK TAIL TIP IS NOW A SILHOUETTE, NOT A FIELD MARK, and that is a real
# consequence rather than an oversight. `DARK` sits at 1.8:1 against the new coat
# — invisible AS a marking — but at 7.7:1 against the ground, which is where a
# tail that swings clear of the body is actually read. The same is true of the
# paws, which `quadruped` colours `DARK` for exactly that reason.
COAT = "#170e06"     # coat / haunch -> shows #55422a, dark tawny umber
BELLY = "#dcc498"    # underside -> shows #efe3cb, cream
DARK = "#040302"     # paws, snout tip, pupil, tail tip -> shows #221c16
EYE = "#46be1a"      # the one bright accent -> shows #8fe05a, hot green

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
