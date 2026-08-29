#!/usr/bin/env python3
"""
Generate the plains hydra -> assets/models/characters/hydra.glb

The PLAINS band's boss, and the first one most runs meet. Its whole read is the
one thing no other model in this game has: THREE HEADS on three necks off one
body ("Hydras, like in Bog castle in hmm3"). That branch point is not built here
— it is `predator_parts.necks`, added with this model precisely so the next
many-headed thing spends it instead of re-deriving the arc trigonometry and
getting the mirror wrong on one side.

Three shape decisions, all of them about being read at boss scale from a
distance, since the terrain's size schedule blows this up 2.5x-6x:

* HEAVY AND LOW, then the necks. The body is a squat slab on stubby legs with a
  short tail — a bog thing that drags itself around its own pool at the slowest
  patrol speed in the family (`move_speed` 2.0 in its SPECIES row). Everything
  vertical in the silhouette is neck.

* THE FAN IS WIDE ENOUGH TO COUNT. Necks spaced 0.42 rad apart put the outer two
  heads ~0.2 m either side of the spine at base scale, which at 2.5x is over a
  metre — three distinct heads from across a field, not a lumpy one. There is no
  per-head animation (the whole `Model` node sways as one, `sway_yaw` 8 degrees,
  the widest in the table), so the STATIC spacing is the entire multi-head read.

* IT IS NOT LONGER THAN ITS CAPSULE MAY BE. hydra.tscn's collision capsule lies
  along the travel axis and covers the whole mesh, and endless_terrain's
  BOSS_FOOTPRINT_RADIUS_PER_SCALE (0.7) caps a boss's horizontal reach at body
  scale 1 — so the nose-to-tail length is held under 1.4 m on purpose. Growing a
  boss UP is free; growing it out is not.

    python3 scripts/generate_hydra.py
"""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from predator_parts import box, necks, rgba, save, spike, tapered_chain  # noqa: E402

# --- Palette. READ THE GAMMA NOTE BEFORE EDITING. -----------------------------
#
# THESE HEXES ARE LINEAR, NOT sRGB, exactly as in generate_snake.py. Godot
# imports GLB vertex colours with `vertex_color_is_srgb = false`, so each byte
# reaches ALBEDO as-is and every constant here renders MUCH LIGHTER than it looks
# in a text editor. Pick a colour by deciding the DISPLAYED value and converting
# back (`linear = ((srgb + 0.055) / 1.055) ** 2.4`), never by eye off the hex —
# that mistake is what made the sand viper invisible in PR #78.
#
# MEASURED against this boss's own band. The plains ground is `green_a`
# (vec3(0.42, 0.55, 0.24), displays #adc486) fading to `green_b`
# (vec3(0.20, 0.44, 0.26), displays #7cb18b), each mottled +-12%:
#
#   BODY  #080409 displays #322235 (a wet bog violet-black)
#         vs green_a  6.96 - 8.66 : 1      vs green_b  5.41 - 6.69 : 1
#   BILE  #7a8a1a displays #b8c25a
#         vs green_a  1.11 - 1.12 : 1      vs green_b  1.16 - 1.43 : 1
#         ...which is fine and deliberate: the bile is read against the BODY
#         (7.76 : 1), never against the grass, the same role the viper's dorsal
#         diamonds play against its charcoal. It is the throat and the ridge, so
#         it is always sitting on the dark mass.
#   EYE   #e37a03 displays #f2b81c — hot amber, so three faces still separate
#         from one dark mass at range.
#
# The desert number is recorded too, because the naga ships in the same bead and
# the two palettes must not collide: this body is 9.25 - 11.58 : 1 against desert
# sand, so a hydra would read there as well — it simply never spawns there.
BODY = "#080409"     # torso, legs, necks, heads
BILE = "#7a8a1a"     # belly, throat, dorsal ridge — the two-tone that stops it being a lump
DARK = "#020101"     # snout tip, claws
EYE = "#e37a03"      # nine eyes' worth of amber

# --- Proportions. Metres, at BASE size: the terrain scales a boss 2.5x-6x at
# spawn, so nothing here is pre-scaled.
BODY_LEN = 0.56
BODY_H = 0.28
BODY_W = 0.40
LEG_LEN = 0.13
LEG_W = 0.11
TAIL_SEGS = 3
TAIL_SEG = 0.09

HEAD_COUNT = 3
NECK_LEN = 0.36
NECK_SPREAD = 0.42     # radians of yaw to the outer necks — the multi-head read
NECK_RISE = 0.95       # radians of pitch at the root, eased off towards the jaw
NECK_THICK = 0.15


def build_hydra():
    c_body, c_bile, c_dark, c_eye = rgba(BODY), rgba(BILE), rgba(DARK), rgba(EYE)
    parts = []

    back_y = LEG_LEN + BODY_H          # top of the slab

    # --- Torso, with a bile-green belly slab hung under it (the quadruped's
    # two-tone, kept because a boss seen from the front is mostly underside).
    parts.append(box((BODY_LEN, BODY_H, BODY_W), (0.0, LEG_LEN + BODY_H / 2, 0.0), c_body))
    parts.append(box((BODY_LEN * 0.88, BODY_H * 0.32, BODY_W * 0.88),
                     (0.0, LEG_LEN + BODY_H * 0.15, 0.0), c_bile))

    # --- Four stubby legs with dark claws. Short on purpose: the mass reads as
    # dragged, and every centimetre of leg is a centimetre the necks lose.
    claw_h = LEG_LEN * 0.22
    for x in (BODY_LEN * 0.3, -BODY_LEN * 0.28):
        for z in (BODY_W / 2 - LEG_W / 2, -(BODY_W / 2 - LEG_W / 2)):
            parts.append(box((LEG_W, LEG_LEN, LEG_W), (x, LEG_LEN / 2, z), c_body))
            parts.append(box((LEG_W * 1.3, claw_h, LEG_W * 1.15),
                             (x + LEG_W * 0.12, claw_h / 2, z), c_dark))

    # --- Short heavy tail. Three blocks, barely tapered: a counterweight, not a
    # whip, and short enough to keep the whole animal inside its capsule budget.
    parts += tapered_chain(
        (-BODY_LEN / 2 - TAIL_SEG / 2, LEG_LEN + BODY_H * 0.45, 0.0),
        TAIL_SEG, TAIL_SEGS, BODY_W * 0.55, BODY_W * 0.22, c_body,
        dx=-1.0, dy=-0.25,
    )

    # --- Dorsal ridge: bile spikes down the spine, tallest over the shoulders.
    # The one thing that stops the profile between the legs and the necks being a
    # featureless brick.
    for i in range(5):
        t = i / 4.0
        parts.append(spike(BODY_W * 0.09, BODY_H * (0.5 - 0.28 * t),
                           (BODY_LEN * (0.18 - 0.62 * t), back_y - 0.005, 0.0), c_bile))

    # --- THE HEADS. One call; the branch point, the fan, the arc, the mirror and
    # the ground guard all live in `necks`.
    parts += necks((BODY_LEN / 2 - 0.03, back_y - BODY_H * 0.15, 0.0),
                   HEAD_COUNT, NECK_LEN, c_body,
                   segments=3, spread=NECK_SPREAD, rise=NECK_RISE,
                   thick=NECK_THICK, taper=0.40, head=1.7, eye=c_eye)
    return parts


if __name__ == "__main__":
    # symmetric=True, unlike the snake: the body is straight along the spine and
    # `necks` is mirror-exact, so a z-bias here means something genuinely moved.
    save(build_hydra(), "hydra")
