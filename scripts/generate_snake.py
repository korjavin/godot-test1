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

* It is read from ABOVE. A player looking down at a low sandy shape against sandy
  ground has almost no silhouette to go on, so the dorsal diamonds are not
  decoration — they are the entire warning. They stay high-contrast on purpose.

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

# Sand-camouflaged above, pale jaw, dark dorsal bands. The eye is the same amber as
# the sand so only the slit pupil really shows — deliberately hard to spot.
SCALE_COLOR = "#d6bb84"
BAND = "#8a6a35"
BELLY = "#efe3c6"
DARK = "#3a2d18"
EYE = "#c9a227"

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
        # Dorsal diamond every other block: the only thing visible from overhead.
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
