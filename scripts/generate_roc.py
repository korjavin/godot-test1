#!/usr/bin/env python3
"""
Generate the mountain roc -> assets/models/characters/roc.glb

The MOUNTAIN band's boss. Owner, verbatim: "huge rock birds, like in barbarian
castle in hmm3". This is the toolkit's FIRST AVIAN — every other animal in
`predator_parts` is a quadruped hung off `quadruped()`, and a bird is not one:
two legs, a body carried upright over them, a neck that rises instead of reaching
forward, and a beak instead of a muzzle.

WHY THERE IS NO `biped()` PRIMITIVE. A primitive earns its place when the shape
cannot be spent at the call site without re-deriving something easy to get wrong —
the wing's mirror and fold, the hydra's branch-point arc. A bird's legs are four
stacked boxes per side with the mirror written out in a `for side in (1.0, -1.0)`
loop, which is the same thing `quadruped` does inline and the naga's coil does
inline. One consumer, no trigonometry, no mirror to lose: it lives here. The
moment a SECOND two-legged animal lands, this is the code to lift.

WINGS ARE SILHOUETTE, NOT FLIGHT — the owner settled it at the epic and the SPECIES
row carries `behavior: "leap"`: a bounded hop, 5.06 m of apex over 2.25 s, higher
and floatier than the dragon's. Nothing in this file touches movement. The wings
come from `predator_parts.wings`, and this bird wears them nearly SHUT (`fold`
0.30 against the dragon's 0.55) — a standing raptor with its wings clamped over
its flanks, which is both the territorial pose the bead asks for ("standing and
hulking — a giant bird guarding ground") and what keeps a 6x roc from being wider
than its own footprint budget.

TWO SHAPE DECISIONS, both about being read at boss scale (the terrain's schedule
blows this up 2.5x-6x at spawn, so nothing here is pre-scaled):

* TALLER THAN IT IS LONG, WHICH IS WHY ITS CAPSULE STANDS UP. Everything about
  this animal is vertical — legs, then a slab of a body, then a neck. A laid
  capsule of the crocodile's kind could not cover it, so roc.tscn uses an UPRIGHT
  one, exactly as the naga and the titan do, and for an upright capsule the RADIUS
  is the horizontal reach.

* IT IS CENTRED ON ITS OWN ORIGIN. The hydra's trap, restated: the reach of a
  capsule is its offset PLUS its extent, so a mesh whose mass sits forward of the
  origin spends endless_terrain's BOSS_FOOTPRINT_RADIUS_PER_SCALE (0.7) twice and
  lands a scaled boss inside the rock it was placed clear of. MOUNTAIN is the band
  made of walls and the one where boss stations most often find no clear candidate
  at all, so this is the biome where an over-wide footprint costs the most.

    python3 scripts/generate_roc.py
"""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from predator_parts import box, rgba, save, spike, tapered_chain, wings  # noqa: E402

# --- Palette. READ THE GAMMA NOTE BEFORE EDITING. -----------------------------
#
# THESE HEXES ARE LINEAR, NOT sRGB, exactly as in generate_snake.py. Godot imports
# GLB vertex colours with `vertex_color_is_srgb = false`, so each byte reaches
# ALBEDO as-is and every constant here renders MUCH LIGHTER than it looks in a
# text editor. Pick a colour by deciding the DISPLAYED value and converting back
# (`linear = ((srgb + 0.055) / 1.055) ** 2.4`), never by eye off the hex — that
# mistake is what made the sand viper invisible in PR #78.
#
# MEASURED against this boss's own band. The mountain ground is `mountain_color`
# (vec3(0.45, 0.43, 0.40), displays #b3afaa — pale grey-brown scree) mottled +-12%,
# and it is a LIGHT floor, so the whole answer here is "go dark":
#
#   ROCK  #0b0907 displays #3b352e (wet basalt)  vs scree  4.98 - 6.18 : 1
#   STONE #231d16 displays #685f53               vs scree  2.58 - 3.20 : 1
#         ...the only accent in the family that clears its OWN floor as well as
#         its own body (1.93 : 1 on the rock). A light band is the one place a
#         mid-tone still reads, so the chest and the underwing get to be a real
#         second value instead of a detail colour.
#   HORN  #c9a13a displays #e6d083 — beak, talons, wing spars: 7.94 : 1 on the
#         rock and only 1.28 - 1.59 : 1 on the scree, which is fine and is the
#         naga's gold played again — horn is only ever seen ON the dark body.
#   EYE   #e3a103 displays #f2d01c — a raptor's hot gold, 8.01 : 1 on the rock.
#
# The forest number is recorded too, because the dragon ships in the same bead and
# the two palettes must not collide: this body is 3.17 - 3.88 : 1 against the
# forest floor, so a roc would read there as well — it simply never spawns there.
ROCK = "#0b0907"    # body, legs, wing membrane, tail
STONE = "#231d16"   # chest, belly, underwing coverts, crest — the second value
HORN = "#c9a13a"    # beak, talons, wing spars
DARK = "#020202"    # beak tip, pupils
EYE = "#e3a103"     # hot gold

# --- Proportions. Metres, at BASE size.
#
# The legs read from the ground up: talons, foot pad, shank, thigh. Nothing here
# computes a y offset — `build()` plants the finished animal's lowest vertex on
# y = 0, and the lowest vertex is a talon by construction.
FOOT_H = 0.05
SHANK_LEN = 0.24
THIGH_LEN = 0.24
LEG_Z = 0.12          # half the stance width
HIP_Y = FOOT_H + SHANK_LEN * 0.85 + THIGH_LEN   # where the body sits on the legs

BODY_LEN = 0.50
BODY_H = 0.40
BODY_W = 0.40

TAIL_SEGS = 3
TAIL_SEG = 0.08

NECK_H = 0.22
HEAD_LEN = 0.20
HEAD_H = 0.17
HEAD_W = 0.18
BEAK_LEN = 0.18

# --- The wings, in the primitive's own language. Nearly shut (see the header):
# big enough to be the widest thing on the bird, clamped enough to stay a
# standing pose rather than a spread one.
WING_SPAN = 0.60
WING_CHORD = 0.34
WING_FOLD = 0.30
WING_SEGMENTS = 4


def build_roc():
    c_rock, c_stone = rgba(ROCK), rgba(STONE)
    c_horn, c_dark, c_eye = rgba(HORN), rgba(DARK), rgba(EYE)
    parts = []

    body_y = HIP_Y + BODY_H / 2          # centre of the torso slab
    back_y = HIP_Y + BODY_H              # top of it

    # --- LEGS. Two of them, and they carry everything: a raptor's mass sits over
    # its feet, which is why the row's `chase_pitch` is the shallowest of the
    # family. Each is talons -> pad -> shank -> thigh, mirrored across the spine.
    for side in (1.0, -1.0):
        z = side * LEG_Z
        parts.append(box((0.16, THIGH_LEN, 0.16),
                         (-0.02, HIP_Y - THIGH_LEN / 2, z), c_rock))
        parts.append(box((0.10, SHANK_LEN, 0.10),
                         (0.02, FOOT_H + SHANK_LEN / 2, z), c_rock))
        parts.append(box((0.15, FOOT_H, 0.14), (0.05, FOOT_H / 2, z), c_rock))
        # Three forward talons per foot. They are the lowest thing on the animal,
        # so they are also what `build()` plants on y = 0 — a bird standing on its
        # toes, not sunk to the ankle.
        for dz in (-0.045, 0.0, 0.045):
            parts.append(box((0.11, 0.035, 0.035),
                             (0.16, 0.0175, z + dz), c_horn))

    # --- TORSO: one heavy slab, with a stone chest bulge in front of it and a
    # stone belly under it. The two-tone is doing real work here (see the palette
    # note): on a light floor the pale half reads on its own, so a roc seen from
    # the front is a dark mass with a lit breast rather than one silhouette.
    parts.append(box((BODY_LEN, BODY_H, BODY_W), (0.0, body_y, 0.0), c_rock))
    parts.append(box((0.18, BODY_H * 0.72, BODY_W * 0.84),
                     (BODY_LEN / 2 + 0.01, body_y - 0.03, 0.0), c_stone))
    parts.append(box((BODY_LEN * 0.86, 0.09, BODY_W * 0.84),
                     (0.0, HIP_Y + 0.04, 0.0), c_stone))

    # --- TAIL: a short blunt fan of blocks angled back and down. A bird's tail is
    # a counterweight over its feet, not a whip, so it is barely tapered and it
    # stops well before the wings do — the roc's rearmost silhouette is WING.
    parts += tapered_chain(
        (-BODY_LEN / 2 - TAIL_SEG / 2, body_y - 0.02, 0.0),
        TAIL_SEG, TAIL_SEGS, 0.26, 0.12, c_rock,
        dx=-1.0, dy=-0.30,
    )

    # --- NECK and HEAD, carried high and forward off the shoulders.
    neck_x = BODY_LEN / 2 - 0.10
    parts.append(box((0.15, NECK_H, 0.19), (neck_x, back_y + NECK_H / 2 - 0.03, 0.0),
                     c_rock))
    head_x = neck_x + 0.10
    head_y = back_y + NECK_H + HEAD_H / 2 - 0.05
    parts.append(box((HEAD_LEN, HEAD_H, HEAD_W), (head_x, head_y, 0.0), c_rock))

    # --- BEAK: a horn wedge with a hooked, near-black tip pointing DOWN. The hook
    # is the whole "bird of prey" read at distance and the one thing that stops
    # the head being a smaller torso.
    beak_x = head_x + HEAD_LEN / 2 + BEAK_LEN / 2
    parts.append(box((BEAK_LEN, 0.10, 0.12), (beak_x, head_y - 0.02, 0.0),
                     c_horn, pitch=-0.12))
    parts.append(box((0.06, 0.10, 0.09),
                     (beak_x + BEAK_LEN / 2, head_y - 0.075, 0.0), c_dark,
                     pitch=-0.35))

    # --- EYES straddling the side of the skull, never inside it — an eye tucked
    # in by a centimetre is swallowed by the head block (see `quadruped`), and a
    # blank-faced 6x bird is the failure this whole family is most visible for.
    for side in (1.0, -1.0):
        ez = side * HEAD_W * 0.5
        parts.append(box((0.055, 0.055, 0.03),
                         (head_x + 0.02, head_y + 0.025, ez), c_eye))
        parts.append(box((0.028, 0.028, 0.025),
                         (head_x + 0.045, head_y + 0.025, ez), c_dark))
    # A stone brow ridge over both, so the face keeps a scowl at boss scale.
    parts.append(box((0.09, 0.03, HEAD_W * 1.02),
                     (head_x + 0.015, head_y + HEAD_H / 2 - 0.01, 0.0), c_stone))

    # --- CREST: three stone quills off the back of the skull. Cheap (4 faces
    # each) and the only thing breaking the head's outline against the sky.
    for dx, h in ((-0.03, 0.11), (-0.06, 0.09), (-0.09, 0.06)):
        parts.append(spike(0.035, h, (head_x + dx, head_y + HEAD_H / 2 - 0.01, 0.0),
                           c_stone))

    # --- THE WINGS. One call; the fold, the mirror, the leading-edge spar and the
    # ground guard all live in `predator_parts.wings`. Rooted high on the flanks
    # just below the backline, so the clamped sweep lies over the ribs and the
    # tail passes under it.
    parts += wings((0.02, back_y - 0.06, BODY_W / 2 - 0.03),
                   WING_SPAN, c_rock,
                   segments=WING_SEGMENTS, fold=WING_FOLD,
                   chord=WING_CHORD, thickness=0.045, taper=0.45, edge=c_horn)

    # --- Underwing coverts: a stone plate over the root of each wing, the shoulder
    # patch a folded bird actually shows. Placed AFTER the wings so it sits on top
    # of the membrane rather than inside it.
    for side in (1.0, -1.0):
        parts.append(box((0.20, 0.05, 0.10),
                         (0.02, back_y - 0.04, side * (BODY_W / 2 - 0.02)), c_stone))

    # --- Centre the animal on its own origin along x. `build()` plants the feet at
    # y = 0 and leaves x alone; an upright capsule's reach is its offset plus its
    # radius, so an off-centre mesh spends BOSS_FOOTPRINT_RADIUS_PER_SCALE twice.
    # Derived rather than hand-typed so retuning the beak, the tail or the fold can
    # never silently push the capsule back over the 0.7 bound.
    shift = -(min(p.bounds[0][0] for p in parts) + max(p.bounds[1][0] for p in parts)) / 2
    for part in parts:
        part.apply_translation((shift, 0.0, 0.0))
    return parts


if __name__ == "__main__":
    # symmetric=True: every leg, eye and wing is mirrored and the body is straight
    # along the spine, so a z-bias here means something genuinely moved.
    save(build_roc(), "roc")
