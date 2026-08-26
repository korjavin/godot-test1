#!/usr/bin/env python3
"""
Generate the sand viper model -> assets/models/characters/snake.glb

The ambusher, and the one species that is not a quadruped — so it builds its own
body here instead of calling `quadruped`, out of the same blocks.

Two things drive every number below:

* It lies FLAT. The viper's whole gimmick is surfacing out of the sand to strike,
  which the AI does by easing the model's y (the same easing the crocodile uses
  to sink in a river). A tall snake would still be visible while "buried", so the
  body is barely thicker than the crocodile's toes and the head is the only part
  that rises at all.

* It is read from ABOVE. A player looking down at a thing this flat has almost no
  silhouette to go on, so the body colour and the dorsal diamonds are the entire
  warning. Both stay high-contrast against sand on purpose — see the palette note.

The resting pose is a fixed S-curve. The body is a chain of chunky blocks tracing
a sine wave in Z; the whole-body yaw sway then swings that S around, which is
close enough to slithering at the distance this thing is ever seen from.

    python3 scripts/generate_snake.py
"""

import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from predator_parts import box, rgba, save, spike  # noqa: E402

# --- Palette. Dark body, pale bands. READ THE GAMMA NOTE BEFORE EDITING. -------
#
# THESE HEXES ARE LINEAR, NOT sRGB. Godot imports this GLB's vertex colours with
# `vertex_color_is_srgb = false`, so each byte is fed to ALBEDO as-is and every
# constant here renders MUCH LIGHTER than it looks in a text editor. `#060503`
# below is not "almost black on screen", it is the warm charcoal `#2a261c`. Pick a
# colour by deciding the DISPLAYED value and converting back
# (`linear = ((srgb + 0.055) / 1.055) ** 2.4`), never by eye off the hex — that
# mistake is what produced the bug this palette fixes.
#
# This palette used to be the exact inverse: sand scales, dim brown diamonds, an
# eye the same amber as the ground — deliberate camouflage. It worked, and that is
# why it is gone. The old SCALE_COLOR `#d6bb84` displays as `#ecdebe`, and the
# desert band's ground (`desert_color` in ground.gdshader, vec3(0.78, 0.68, 0.44))
# displays as `#e5d7b1` — a contrast ratio of 1.08:1, i.e. the animal was the
# ground. On top of that the viper's ambush AI already IS the hiding mechanic (it
# burrows at speed 0 and lunges when you walk into it); camouflage stacked on
# burrowing is two invisibility mechanics on one predator, and no counterplay.
#
# So the ROLES swap and the STRUCTURE stays: charcoal carries the body, head and
# horns, and the sand tone is demoted to the dorsal diamonds and the jaw, which
# keeps it a *patterned* snake rather than a featureless black tube. Measured
# against that same ground across its ±12% mottling, body-vs-sand is now 9.3–11.7:1
# and band-on-body 9.2:1 (was 1.66:1). Note the bands alone are ~1.1:1 against sand
# and that is fine — they are read against the dark body, never against the ground.
SCALE_COLOR = "#060503"     # body / head / snout / horned scale -> shows #2a261c
BAND = "#b59651"            # dorsal diamonds, the warning stripe -> shows #dbca99
BELLY = "#d8c9a3"           # jaw line, bone -> shows #ede6d1
DARK = "#020101"            # snout tip, pupil, tongue -> shows #160d0d, black ON the body
EYE = "#e37a03"             # hot amber, so the eye still pops off a dark skull -> #f2b81c

SEGMENTS = 14          # body blocks behind the head
SEG_LEN = 0.10
THICK = 0.13           # cross-section at the neck
TAIL_TAPER = 0.74      # fraction of THICK lost by the tail tip
WAVE_AMP = 0.16        # how far the S swings either side of the spine
WAVE_RATE = 0.50       # radians of the sine per segment — about one and a half loops

HEAD_LEN = 0.17
HEAD_W = 0.16
HEAD_H = 0.12
SNOUT_LEN = 0.09


def build_snake():
    c_scale, c_band, c_belly = rgba(SCALE_COLOR), rgba(BAND), rgba(BELLY)
    c_dark, c_eye = rgba(DARK), rgba(EYE)
    parts = []

    # --- Body: blocks marching backwards from the neck along a sine in Z.
    for i in range(SEGMENTS):
        t = (i / (SEGMENTS - 1)) ** 1.4          # eased so the taper is all in the tail
        thick = THICK * (1.0 - TAIL_TAPER * t)
        x = -SEG_LEN * i
        z = WAVE_AMP * np.sin(i * WAVE_RATE)
        # Slightly overlong blocks so the corners of the curve never open a gap.
        parts.append(box((SEG_LEN * 1.25, thick, thick), (x, thick / 2, z), c_scale))
        # Dorsal diamond every other block: pale, and the only thing that breaks up
        # the dark body from overhead — what keeps this a snake and not a tube.
        if i % 2 == 0:
            parts.append(box((SEG_LEN * 0.6, thick * 0.25, thick * 1.05),
                             (x, thick * 0.95, z), c_band))

    # --- Head: a wedge wider than the neck, the one part held clear of the sand.
    head_x = HEAD_LEN / 2 + SEG_LEN * 0.4
    head_y = HEAD_H / 2 + THICK * 0.25
    parts.append(box((HEAD_LEN, HEAD_H, HEAD_W), (head_x, head_y, 0.0), c_scale))
    # Pale jaw line, wider than the skull so it shows from the side. A belly slab
    # narrower than the body would be entirely interior geometry: a snake lying
    # flat on the ground never shows its underside, so there isn't one.
    parts.append(box((HEAD_LEN * 0.8, HEAD_H * 0.22, HEAD_W * 1.06),
                     (head_x, HEAD_H * 0.16 + THICK * 0.25, 0.0), c_belly))

    # Blunt snout, dark at the tip.
    snout_x = head_x + HEAD_LEN / 2 + SNOUT_LEN / 2
    parts.append(box((SNOUT_LEN, HEAD_H * 0.62, HEAD_W * 0.66),
                     (snout_x, head_y - HEAD_H * 0.12, 0.0), c_scale))
    parts.append(box((SNOUT_LEN * 0.25, HEAD_H * 0.3, HEAD_W * 0.4),
                     (snout_x + SNOUT_LEN / 2, head_y - HEAD_H * 0.12, 0.0), c_dark))

    # --- Eyes high on the skull (a buried viper watches from the surface), each
    # with a vertical slit pupil, and the horned scale above it the species is
    # named for.
    for side in (1.0, -1.0):
        ez = side * HEAD_W * 0.5      # straddling the skull's side, not inside it
        parts.append(box((HEAD_LEN * 0.22, HEAD_H * 0.3, HEAD_W * 0.14),
                         (head_x + HEAD_LEN * 0.22, head_y + HEAD_H * 0.22, ez), c_eye))
        parts.append(box((HEAD_LEN * 0.07, HEAD_H * 0.26, HEAD_W * 0.1),
                         (head_x + HEAD_LEN * 0.3, head_y + HEAD_H * 0.22, ez), c_dark))
        parts.append(spike(HEAD_W * 0.09, HEAD_H * 0.45,
                           (head_x + HEAD_LEN * 0.18, head_y + HEAD_H / 2, ez), c_scale))

    # --- Forked tongue: two dark prongs flicking out past the snout. Splayed by
    # offsetting them in Z rather than rotating — at the distance this is seen,
    # the fork reads either way and a straight block is 12 faces.
    for side in (1.0, -1.0):
        parts.append(box((SNOUT_LEN * 0.8, HEAD_H * 0.06, HEAD_W * 0.05),
                         (snout_x + SNOUT_LEN * 0.9, head_y - HEAD_H * 0.2,
                          side * HEAD_W * 0.09), c_dark))
    return parts


if __name__ == "__main__":
    # symmetric=False: an S-curve is genuinely lopsided about the spine, unlike
    # the four quadrupeds, so it is only checked for being ROUGHLY centred.
    save(build_snake(), "snake", symmetric=False)
