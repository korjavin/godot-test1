#!/usr/bin/env python3
"""
Generate the forest green dragon -> assets/models/characters/green_dragon.glb

The FOREST band's boss ("inspired by hmm3 elves' Rampart dragon" — stylized-blocky
like the rest of the bestiary, not a copy). It is a quadruped, so almost all of it
is `predator_parts.quadruped` with a table of proportions, exactly like the wolf;
what makes it a dragon rather than a big lizard is three flourishes on top: WINGS,
swept HORNS, and a bone ridge down the spine.

WINGS ARE SILHOUETTE, NOT FLIGHT. The owner settled this at the epic: this world
is flat, nothing flies, and the dragon's SPECIES row carries `behavior: "leap"` —
a bounded Windman-style hop, 3.56 m of apex over 1.78 s. The wings are what makes
that hop read as a beat rather than as a jump, and nothing in this file touches
movement. They come from `predator_parts.wings`, the primitive built for exactly
this pair of bosses; the fold, the mirror, the ground guard and the leading-edge
spar all live there and this model only picks numbers.

WHY `fold = 0.55` AND NOT 0. A wing fully tucked (fold 0) is a vertical fin laid
back along the flank — correct at rest, and from directly in front it is a line.
Half-open trades a little of that flank sweep for width off the shoulder, which is
the read that survives the 3/4 view a chasing boss is usually seen from. It is
still a resting pose, not a spread one: at 0.55 rad the wing reaches 0.24 m off
the shoulder against 0.39 m back along the body.

THREE SHAPE DECISIONS, all about being read at boss scale (the terrain's schedule
blows this up 2.5x-6x at spawn, so nothing here is pre-scaled):

* LONG AND LOW, then the wings. A wolf's leg length on a heavier body, the head
  carried LEVEL rather than slung (`neck_drop` 0) — a reptile watching you, not a
  bear nosing the ground. Everything above the backline is wing, horn or ridge.

* IT IS NOT LONGER THAN ITS CAPSULE MAY BE, AND IT IS CENTRED ON ITS ORIGIN. The
  hydra's trap, restated because it is the one that bites: endless_terrain's
  BOSS_FOOTPRINT_RADIUS_PER_SCALE (0.7) caps a boss's horizontal reach at body
  scale 1, and the reach of a LAID capsule is its offset PLUS its half-length — so
  a mesh whose mass sits forward of the origin spends the 0.7 twice and lands a
  scaled boss inside the tree it was placed clear of. Nose to tail is held under
  1.4 m and the whole animal is shifted onto its own x-midpoint at the end.

* THE WINGS ARE WIDER THAN THE CAPSULE AND THAT IS FINE. Collision is the body;
  a wing you can walk through is the same deal every other model's tail already
  makes. `verify` still insists the animal is longer than it is wide, which is
  what stops the fold being opened until the dragon reads as a kite.

    python3 scripts/generate_green_dragon.py
"""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from predator_parts import box, quadruped, rgba, save, spike, wings  # noqa: E402

# --- Palette. READ THE GAMMA NOTE BEFORE EDITING. -----------------------------
#
# THESE HEXES ARE LINEAR, NOT sRGB, exactly as in generate_snake.py. Godot imports
# GLB vertex colours with `vertex_color_is_srgb = false`, so each byte reaches
# ALBEDO as-is and every constant here renders MUCH LIGHTER than it looks in a
# text editor. Pick a colour by deciding the DISPLAYED value and converting back
# (`linear = ((srgb + 0.055) / 1.055) ** 2.4`), never by eye off the hex — that
# mistake is what made the sand viper invisible in PR #78.
#
# MEASURED against this boss's own band. The forest ground is `forest_color`
# (vec3(0.13, 0.30, 0.17), displays #659573) mottled +-12%, and it is the DARKEST
# floor in the game — which changes the usual answer:
#
#   SCALES  #030704 displays #1c2e22 (green-black)  vs forest  3.74 - 4.57 : 1
#   MEMBRANE #0a1204 displays #384b22               vs forest  2.49 - 3.05 : 1
#           ...and 1.50 : 1 against the scales. Deliberately a near-miss: the
#           membrane is a large surface, so it has to clear the FLOOR first; the
#           wing separates from the flank by its bone spar, not by its fill.
#   BONE    #b8c49a displays #dde3cc                vs forest  2.38 - 2.91 : 1
#   EYE     #e37a03 displays #f2b81c (the family amber), 7.95 : 1 on the scales.
#
# WHY BOTH A DARK MASS AND A LIGHT ACCENT, which is the bead's "tuned against the
# forest floor UNDER TREE-SHADOW DENSITY". Against the open forest floor
# (L = 0.254) going dark is the better direction by a wide margin — the ceiling is
# 6.7 : 1 dark against 3.8 : 1 light. Under canopy shadow the floor darkens and
# that flips: a dark animal loses contrast exactly where the trees are thickest.
# A mid-value dragon would lose in BOTH lightings, so this one is two-tone on
# purpose — the scales win in the open, the bone horns / ridge / wing spars win
# under the canopy, and there is no lighting in this biome where nothing separates.
SCALES = "#030704"    # body, legs, neck, head, tail
MEMBRANE = "#0a1204"  # belly slab and the wing plates
BONE = "#b8c49a"      # horns, dorsal ridge, wing spars — the canopy-proof half
DARK = "#010301"      # claws, nostril, pupils
EYE = "#e37a03"       # hot amber

# --- Proportions. Metres, at BASE size.
SHAPE = dict(
    body_len=0.62, body_h=0.26, body_w=0.28,
    leg_len=0.30, leg_w=0.095,           # a wolf's stance carrying a heavier body
    head_len=0.20, head_h=0.16, head_w=0.17,
    snout_len=0.15,                      # a long reptile jaw
    neck_drop=0.0,                       # head carried LEVEL: the lizard read
    tail_len=0.30, tail_w=0.14, tail_droop=0.20,
    tail_bushy=1.0,                      # a straight taper — a whip, not a brush
    ears="point", ear_size=0.08,         # small ear frills; the HORNS are below
    haunch=0.05,                         # the hind drive a leaping animal needs
)

# --- The wings, in the primitive's own language. See the header for why the fold
# is a resting-but-open 0.55 rather than the fully tucked 0.
WING_SPAN = 0.46
WING_CHORD = 0.26
WING_FOLD = 0.55
WING_SEGMENTS = 4

HORN_LEN = 0.20       # swept out and up off the back of the skull
RIDGE_COUNT = 6       # bone plates down the spine, tallest over the shoulders


def build_green_dragon():
    c_bone = rgba(BONE)
    parts = quadruped(body=SCALES, belly=MEMBRANE, dark=DARK, eye=EYE, **SHAPE)

    back_y = SHAPE["leg_len"] + SHAPE["body_h"]      # top of the torso
    head_x = SHAPE["body_len"] / 2 + SHAPE["head_len"] / 2 + 0.02
    head_y = back_y - SHAPE["neck_drop"] - SHAPE["head_h"] / 2

    # --- HORNS. Two bone spikes off the back of the skull, rolled outwards so
    # they splay instead of standing like a second pair of ears. `spike` rolls
    # about X, which is exactly the sideways splay wanted here — a backward sweep
    # would need a pitch the primitive does not carry, and is not worth one knob.
    for side in (1.0, -1.0):
        parts.append(spike(0.045, HORN_LEN,
                           (head_x - SHAPE["head_len"] * 0.30,
                            head_y + SHAPE["head_h"] / 2 - 0.01,
                            side * SHAPE["head_w"] * 0.30),
                           c_bone, roll=side * 0.55))

    # --- DORSAL RIDGE. Bone plates down the spine, tallest at the shoulders and
    # dying away over the hips — the same trick the hydra's bile ridge plays, and
    # the thing that stops the backline between the wings and the tail being a
    # featureless brick. Sunk 5 mm INTO the torso so no plate's underside is
    # coplanar with the torso's top face and z-fights it.
    for i in range(RIDGE_COUNT):
        t = i / (RIDGE_COUNT - 1)
        parts.append(box((0.035, SHAPE["body_h"] * (0.40 - 0.26 * t), 0.02),
                         (SHAPE["body_len"] * (0.30 - 0.66 * t),
                          back_y + SHAPE["body_h"] * (0.40 - 0.26 * t) / 2 - 0.005,
                          0.0),
                         c_bone))

    # --- THE WINGS. One call; the fold, the mirror, the leading-edge spar and the
    # ground guard all live in `predator_parts.wings`. Rooted over the SHOULDERS
    # (forward of centre, inboard of the flank) so the tucked sweep lies along the
    # ribs and the tail stays clear of it, and 5 cm ABOVE the backline: at this
    # fold the plate stands roughly +-half a chord in y about its root, so a root
    # sitting exactly on the spine hides the whole wing inside the body's own
    # profile from the side — which is the view a chased player has most of the
    # time. The lift is what puts the wing's top edge over the dorsal ridge.
    parts += wings((SHAPE["body_len"] * 0.16, back_y + 0.05, SHAPE["body_w"] / 2 - 0.02),
                   WING_SPAN, rgba(MEMBRANE),
                   segments=WING_SEGMENTS, fold=WING_FOLD,
                   chord=WING_CHORD, thickness=0.035, taper=0.50, edge=c_bone)

    # --- A brow plate over each eye, so the face still has a scowl once the head
    # is 6x and the eye block is the only bright thing on it.
    for side in (1.0, -1.0):
        parts.append(box((SHAPE["head_len"] * 0.34, 0.022, SHAPE["head_w"] * 0.30),
                         (head_x + SHAPE["head_len"] * 0.24,
                          head_y + SHAPE["head_h"] * 0.38,
                          side * SHAPE["head_w"] * 0.30), c_bone))

    # --- Centre the animal on its own origin along x. `build()` plants the feet
    # at y = 0 and leaves x alone, but a BOSS with a laid capsule cannot afford
    # that: the reach of a laid capsule is its offset PLUS its half-length, so an
    # off-centre mesh spends BOSS_FOOTPRINT_RADIUS_PER_SCALE twice. Derived rather
    # than hand-typed so retuning the tail, the fold or the jaw can never silently
    # push the capsule back over the 0.7 bound.
    shift = -(min(p.bounds[0][0] for p in parts) + max(p.bounds[1][0] for p in parts)) / 2
    for part in parts:
        part.apply_translation((shift, 0.0, 0.0))
    return parts


if __name__ == "__main__":
    # symmetric=True: the body is straight along the spine and `wings` is
    # mirror-exact, so a z-bias here means something genuinely moved.
    save(build_green_dragon(), "green_dragon")
