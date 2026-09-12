"""
scripts/build_hero.py — THE SKINNED HERO LANE. A hero is a `HEROES` row.

Bead godot-test1-5u3.1 (epic 5u3, SKINNED HEROES), the SOURCE OF RECORD for the
shipped Teibi since bead 5u3.3, and GENERALISED to the whole cast by bead 5u3.4:
windman, primm and teibi are three rows of one table and there is no second
script. Started as a copy of the z3e.10 spike (`scripts/spike_z3e_teibi_body.py`,
deleted by 5u3.3) with the ten-piece joint SPLIT removed and an ARMATURE added:
the body is one mesh on MPFB2's `game_engine` rig, exported as one skinned .glb.

WHAT A ROW IS (and where each half of it came from):

  macros + targets  the FACE — a `FACES` row below, the Windman and Primm
                    recipes `spike_z3e_head.py` authored and bead z3e.12 pulled
                    apart, folded in here when bead 5u3.8 deleted that spike.
                    Body and head are now ONE human at ONE scale (owner ruling
                    2026-09-11, "heads at body scale"), so the neck is
                    continuous by construction and the z3e.7 neck gap and the
                    z3e.10 stump cannot come back.
  colours           the hero's own generator palette (`self.colors`), verbatim,
                    ungraded — `hero_skin.SKIN_GRADE` is applied here, at paint
                    time, to the entries named in GRADED_COLOURS.
  bone_regions      clothing as BONE REGIONS: which bone wears which colour. A
                    sleeveless shirt is `upperarm_* -> skin`, shorts are
                    `calf_* -> skin`, gloves are `hand_* -> gloves`. No geometry,
                    no seam, no second material.
  bands             the joint-height overrides a bone cannot express: belt, cuff,
                    collar. A row lists the ones it wears.
  garments          clothing as GEOMETRY, not as paint (bead godot-test1-5u3.10;
                    owner, on the rest row: "why are the pants so slick"). A
                    garment is a bone scope, a z range and how far proud of the
                    skin it stands: `dress_shells` cuts a hem ring and pushes that
                    patch of body out, `paint_body` colours the same patch. Every
                    garment in the cast — trousers, shorts, shirt, sleeves, boot
                    shaft, waistband — is one row of that shape.
  tails             Primm's, and Primm's alone: the two coat flaps off the back
                    hem. The one garment that must be NEW geometry, because there
                    is no body under it to push out (`attach_tails`).
  dressing          one hero's OWN garment, as a callable `paint_body` runs after
                    those bands: Primm's open lab coat (`_primm_coat` — the V of
                    inner shirt, the silver seams, the rolled sleeve, the boot
                    shaft). A band worn by one hero is not a band, it is his coat.
  band + stripes    eyewear. `band` makes it CLOTH (`wrap_band`, bead z3e.13's
                    Windman bandage, folded in with the faces by bead 5u3.8);
                    `stripes` alone paints it on the skin (Primm's goggles).
  beret/eyes        accessory GEOMETRY joined into the mesh and weighted to one
                    bone. An accessory that is not geometry is an ATTACHMENT and
                    belongs in the .tscn as a BoneAttachment3D (Windman's fan on
                    `hand_r`, bead 5u3.5) — the row does not model it and neither
                    does this.
  emblem            a MOTIF painted onto the body's own vertices: a centre-line,
                    a stroke width and a landmark to hang it off. Windman's chest
                    "W" is the only one (`paint_chest_glyph`).

COLOUR IS VERTEX COLOUR AND THERE IS NO TEXTURE (owner ruling 2026-09-11,
"vertex colours by default with a body albedo only for a motif"). The cast has
exactly one motif — Windman's chest "W" — and bead 5u3.5 measured it back onto
the vertices rather than spending the lane's first texture on it: split the chest
once under the glyph (`densify_chest`) and the letter has four to five vertices
across every arm and three across every notch (`paint_chest_glyph`), which is
what a 512^2 bake would have bought at 3 m and no more. So there is still no bake
and no UV path here; the
row that first needs one brings it. `texture bytes: 0` is printed anyway, so the
day that changes is the day the number moves.

NOT part of the build, NOT run by CI (the runner has no Blender): run by hand.

  perl -e 'alarm 1800; exec @ARGV' \
      blender --background --python-exit-code 1 --python scripts/build_hero.py -- \
      --all --rest-row docs/style/z3e/build_hero_rest_row.png
  godot --headless --path . --import        # Godot caches .glb imports

  ... --python scripts/build_hero.py -- --hero teibi      # one hero
  ... --python scripts/build_hero.py -- --all --check     # rebuild and diff the manifest

THE MANIFEST IS THIS LANE'S OWN STALENESS GATE. `scripts/hero_manifest.json`
holds the tool versions and the tri / bone / byte / texture counts of every file
this script writes, `--check` rebuilds and diffs against it, and `build.yml` has
a five-line `stat` step that asserts the committed .glb sizes still match it —
Blender-free, because CI cannot run this script at all. That is the substitute
for the predators' rebuild-and-diff gate, and it is why a hand-edited hero .glb
is caught here the way a hand-edited hydra is caught there.

THE TRAPS THIS LANE PAYS FOR (the four in `bd show godot-test1-z3e` NOTES —
MPFB2 enable with default_set=True, no --factory-startup, the full
bl_ext.blender_org.mpfb import path, `--import` after every rebuild — plus
these, which are this lane's own):

 1. WEIGHTS ARE BASEMESH-INDEXED. `HumanService.add_builtin_rig(...,
    import_weights=True)` writes one vertex group per bone off
    weights.game_engine.json, whose indices are RAW BASEMESH indices, and
    `bake_to_plain_mesh()`'s `convert()` applies the helper MASK modifier, which
    RENUMBERS vertices. So every vertex group written off that JSON — the rig
    here, and `cut_fingers()` right after it — must be written on the RAW human
    BEFORE `convert()`: vertex GROUPS survive the mask and the decimate that
    follows, vertex INDICES do not. (The z3e.10 spike's own header trap, same
    cause, different victim.)
 2. `convert(target='MESH')` APPLIES AND REMOVES EVERY MODIFIER, the armature
    modifier included — the bone weights survive (they are vertex groups), the
    binding does not. Re-add it with `RigService.ensure_armature_modifier`.
 3. blender_hero.py's conjugation trick (W_blender = Rx(90)·W_godot·Rx(90)^-1)
    is for UNRIGGED parts hung on a .tscn node whose basis is Rx(-90). A
    SKINNED glTF is placed by its own root node and exports Y-up: do NOT copy
    it here. This script builds in Blender's Z-up with +Y = the face, exports
    with `export_yup=True` (the default), and glTF's (x, z, -y) map lands the
    face on Godot's -Z and the character's left on -X, which is what today's
    heroes do (teibi.tscn LeftArm x=-0.18).
 4. A RIG DOES NOT FOLLOW `mesh.vertices[i].co`. The spike reframed by editing
    vertex coordinates; that leaves the bones where they were and the body
    floats off its skeleton. `reframe()` here transforms the mesh DATA and the
    armature DATA with the same matrix (`ID.transform()` on both), so both
    objects keep identity transforms and the rest pose stays consistent.
 5. MAKEHUMAN RESTS IN AN A-POSE (measured: upper arms 41.3 deg off vertical).
    Fixed as REST POSE in Blender (`apply_pose_as_rest`), never in the .tscn —
    an exported rest that is not the game's rest means both animation columns
    start from the wrong arms.
 6. `pose.bones[...].head` / `.tail` / `.matrix` DO NOT FOLLOW `data.transform()`.
    They are evaluated through the depsgraph, `view_layer.update()` does not
    refresh them, and after `reframe()` they answer in the PRE-turn frame. Read
    and write the rest data (`data.bones[...].head_local`, `.tail_local`,
    `.matrix_local`, and `pose.bones[...].matrix_basis`) instead —
    `apply_pose_as_rest`'s docstring has the measurement that cost a rebuild.
 7. A LANDMARK IS READ OFF THE EVALUATED MESH, NEVER `human.data.vertices`
    (bead z3e.12's lesson, and this lane paid it a second time in bead 5u3.4).
    The macro sliders and the face targets are SHAPE KEYS, and a shape key does
    not move `vertex.co` — so `joint-l-eye` read raw answers for the UNMORPHED
    basemesh while `reframe()`'s scale is measured on the morphed one, and the
    two frames are not the same body. Teibi hid it (his macros sit near the
    basemesh default); Primm did not (age 0.30 / weight 0.35 morph him from
    1.61 m down to 1.505 m, which put his eye landmark 5 cm above his own crown
    and rendered him bald, his hairline being measured off it). `morphed_coords`
    and `joint_centroid` below exist for exactly this; they came from the head
    spike, which had paid for the same lesson first.
 8. `bmesh.ops.create_cube` WRITES NO DEFORM WEIGHTS. `wrap_band`'s knots are new
    geometry with no vertex groups at all, and an unweighted vertex is a vertex
    that stays behind when the hero walks. `weight_strays_to()` sweeps them onto
    one bone after the wrap; `report_weights()` is what would catch it.
 9. A GARMENT MOVES THE BODY'S OWN VERTICES; IT IS NOT A SECOND SURFACE. See
    `dress_shells()` — the shell idiom this lane can afford, and the tri budget
    that is why. Anything that ADDS geometry to the body (`dress_shells`'s hem
    cuts, `densify_chest`) must run BEFORE `wrap_band`, whose `flat_faces` are
    polygon indices; anything joined AFTER it (the beret, the eyes, Primm's coat
    tails) is refused on a row that wears a band. `build()` holds both rules.
"""

import json
import math
import os
import sys
import tempfile

import addon_utils
import bmesh
import bpy
import importlib
from mathutils import Matrix, Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# THE SKIN GRADE, one copy for the whole cast — read `scripts/hero_skin.py`
# before touching a `colours` row. Reached the way the generators reach
# `predator_parts.export_faceted`, because Blender runs this file by path and
# its directory is not on `sys.path`.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hero_skin import graded  # noqa: E402
# Blender's own screenshot helper, reused for the rest row (`--rest-row`).
import blender_hero  # noqa: E402

OUT_ROOT = os.path.join(REPO, "assets", "models", "characters")
MANIFEST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hero_manifest.json")
TEXTURE_BYTES_MAX = 512 * 512 * 4     # owner ruling: <= 512^2 albedo, no normal map
ARMS_DOWN_MAX_DEG = 12.0              # how far off vertical a shipped rest may stand

RIG = "game_engine"
RIG_BONES = 53               # what MPFB2 ships; asserted the moment the rig lands
# OWNER RULING 2026-09-11 (epic `5u3` NOTES, "cut them"): the 30 finger bones are
# COLLAPSED at build time — their weights folded into `hand_l`/`hand_r`, the bones
# deleted — so the shipped rig is 23 bones. Nothing this game has ever drawn moves
# a finger: `hero_rig_skeleton.gd` writes ten bones, the hand is one of nobody's,
# and every finger bone is a joint matrix, a palette entry and four more influences
# per hand vertex that the web renderer skins every frame for a shape no camera can
# resolve at 3 m. `scripts/spike_5u3_skinned_probe.gd` asserts the 23.
RIG_BONES_SHIPPED = 23
ARMS_DOWN_DEG = 5.0          # how far the arms stand off vertical in the shipped rest


def _fingers(side):
    return ["%s_%02d_%s" % (d, n, side)
            for d in ("thumb", "index", "middle", "ring", "pinky")
            for n in (1, 2, 3)]


# Which bones wear which colour. A vertex takes the region whose bones hold the
# most of its skin weight (argmax) — `paint_body`'s base coat, before the
# geometric band overrides. This is the DEFAULT dressing (long sleeves, long
# trousers, bare hands); a row's `bone_regions` moves individual bones out of it,
# which is how a sleeveless shirt, a pair of shorts and a pair of gloves are
# expressed without one line of geometry. The COLOURS are per row.
COLOUR_BONES = {
    "skin": ["head", "neck_01", "hand_l", "hand_r"] + _fingers("l") + _fingers("r"),
    "shirt": ["spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r",
              "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r"],
    "trousers": ["pelvis", "thigh_l", "thigh_r", "calf_l", "calf_r"],
    "shoes": ["foot_l", "foot_r", "ball_l", "ball_r"],
}
# Bone groups the band overrides are SCOPED by, so a belt never bleeds onto a
# leg and a cuff never onto the torso (spike_z3e_teibi_body.py's `piece_*`
# groups, re-expressed on the rig's own groups now that the rig exists).
REGION_BONES = {
    "torso": ["pelvis", "spine_01", "spine_02", "spine_03"],
    "head": ["head", "neck_01"],
    "lowerarm_l": ["lowerarm_l", "hand_l"] + _fingers("l"),
    "lowerarm_r": ["lowerarm_r", "hand_r"] + _fingers("r"),
}

# ===========================================================================
# THE FACES. One row per hero FACE — macro sliders, MakeHuman face targets, the
# skin/lips/hair palette and the eyewear. Authored by `scripts/spike_z3e_head.py`
# for the standalone heads of beads z3e.2 (Windman) and z3e.5 (Primm), sharpened
# apart by bead z3e.12, and FOLDED IN HERE by bead godot-test1-5u3.8, which
# deleted that spike: the heads it shipped are gone, built into the whole human
# below, so a second file holding their recipe was a second number to keep in
# step with the first. The head-only keys went with it (`parts_dir`,
# `target_height`, `neck_stump_radius` — a cut-at-the-neck lane's, and there is
# no neck cut any more; git history has them).
#
# `palette` is the hero's own colour, kept apart from the `HEROES` row below
# because it is the FACE's: skin and lips reach the mesh through
# `hero_skin.SKIN_GRADE` (see GRADED_COLOURS), so the row is the paint and that
# constant is the exposure. Windman's is his old generator's verbatim; Primm's
# deliberately leaves his (the note in his row says why).
#
# `stripes` is the eyewear's COLOURS, listed TOP-DOWN in metres relative to the eye
# landmark; the first stripe containing a vertex wins.
#
# `band` (optional) says those colours are worn as CLOTH: `wrap_band` lifts that slab
# of the face off the skull into a thick wrap before `paint_body` colours it, and the
# face underneath — eye sockets included — is consumed by the lift. A row WITHOUT
# `band` (Primm's goggles) keeps the stripes as paint on the skin. See `wrap_band`.
# ===========================================================================

# The seam where a `band` row's two cloth colours meet, drawn as one darker line so
# the wrap reads as TWO turns of cloth rather than a two-tone stripe. Half-height in
# metres, and how far the lower colour is pulled down to make the line.
SEAM_HALF = 0.0030
SEAM_DARKEN = 0.55

# THE MOUTH IS MAKEHUMAN'S OWN `lips` VERTEX GROUP (bead godot-test1-394; owner,
# 2026-09-12: "why do the heroes look like they have a beard? I don't like it").
#
# Every earlier pass at this was a GEOMETRIC BAND — z3e.15's first one took the
# whole front of the face at mouth height, cheeks included; its second bounded the
# band across (`LIP_HALF`) and forward (`LIP_DEPTH`) to something mouth-shaped. Both
# hung off `eye_z - 0.088`, a drop measured once on one head, and every face target
# a `FACES` row carries moves the mouth against the eye line (Windman's
# `chin-jaw-drop-decr`, Primm's `chin-prominent-incr`, Teibi's `mouth-angles-up`).
# So on the morphed heads the band slid DOWN onto the chin and round the jaw, and a
# colour picked to be darker than the skin became a beard shadow at 3 m.
#
# There is no band to tune here any more. MPFB2's `extra_vertex_groups=True` (see
# `build_human`, which prints the search) ships MakeHuman's own `lips` group — 418
# basemesh vertices, the region MPFB's layered skin material paints the lips with —
# and a vertex GROUP survives the mask and the decimate (trap 1 in this file's
# header). It is the mouth as MakeHuman models it, so it follows every morph for
# free and it cannot reach the chin: `CHIN_CLEAR` is the assert that says so out
# loud, because a selection that lands on the chin is exactly as invisible
# downstream as a selection that lands nowhere (same verts, same tris, same bytes,
# `--check` green) — which is how the beard shipped three times.
LIPS_VG = "lips"      # MakeHuman's own group name, shipped by `extra_vertex_groups`
LIP_WEIGHT = 0.5      # a decimated vertex is a lip if the group still mostly owns it
LIP_VERTS_MIN = 8     # below this there is no mouth — `paint_body` refuses to build
CHIN_CLEAR = 0.012    # metres of skin between the lowest lip vertex and the chin
FACE_FRONT = 0.72     # fraction of the head's half-depth that counts as "the face"

# THE LIP COLOUR IS THE SKIN'S. It used to be a per-row literal, and three
# hand-picked browns are three chances to pick a beard: the rows had the lips 25 to
# 40% darker than the face, which is a shadow, not a mouth. It is now derived from
# the hero's own GRADED skin — darker, and warmer rather than browner, so the mouth
# reads as lips on every skin tone in the cast without a number per hero. The red
# shift is a multiplier on the red channel alone (clamped), which is what keeps it
# from going grey as it darkens.
#
# THE STRENGTH IS THE SECOND PASS. 0.88 was the bead's "~12 percent" taken
# literally and it was too little: on the first `grid_28` Windman's mouth vanished
# into his bright skin entirely and Primm's was a tone shift you had to look for,
# which is the failure the z3e.15 banner above already names — "a mouth no darker
# than the face around it is not a mouth at this distance". 0.78 is ~21% of luma,
# which is between that and the 25-40% the old literals had, and `LIP_CONTRAST` is
# the assert that keeps a future hand from walking it back to either end: a band,
# because too little is no mouth and too much is the beard.
LIP_DARKEN = 0.78
LIP_RED = 1.06
LIP_CONTRAST = (0.15, 0.30)   # how much darker than the skin the lips must be

# How far past the arc's own end a skin-side band vertex may sit before it counts
# as a bisect that did not land — see the assert in `wrap_band`, which is the one
# reader. It is the ONE place the cloth's boundary is allowed to follow the head's
# triangulation instead of a cut line, so it has to be about one triangle wide and
# nothing more. It was 0.10 rad, measured on the Windman head of bead z3e.16;
# z3e.15 widened his skull (`head-scale-horiz-incr`, and the portrait is a broad
# man) and the two staircase vertices at each arc end moved out to 6.6 and 6.8
# degrees past it — one 9 mm triangle on a 7.5 cm radius. 0.14 rad is 8.0 degrees:
# that triangle, with a little room, and still an order under the 74-degree arc.
ARC_END_SLACK = 0.14

FACES = {
    "windman": {
        # docs/characters/windman.md: male, calm, no beard, slightly rounded face
        # with soft features; the blue-over-red bandage knotted at the back.
        #
        # BEAD z3e.15 — `assets/portraits/windman.png` and
        # `docs/characters/windman.png` read beside the 2026-09-12 `17_head_face`
        # frame. The portrait is a BROAD, ROUND, heavy-set man: full cheeks, a
        # wide square jaw, a short chin, a small mouth and a thick neck. The head
        # that shipped was none of that — an oval with hollow cheeks running down
        # to a long tapered chin, because `head-round` at 0.65 was carrying the
        # whole shape on its own against `head-fat-incr` 0.30. The move is width
        # and mass, not a new target family: `weight` and `muscle` up (they shape
        # the neck and jowl the portrait has and the render did not), `head-round`
        # and `head-fat-incr` up, `head-scale-horiz-incr` for the breadth across
        # the cheekbones, `chin-width-incr` for the square jaw and
        # `chin-jaw-drop-decr` more than doubled for the short chin under it.
        "macro": (("gender", 0.85), ("age", 0.45), ("muscle", 0.55),
                  ("weight", 0.70), ("caucasian", 1.0), ("african", 0.0),
                  ("asian", 0.0)),
        "targets": ((("head", "head-round.target.gz"), 0.85),
                    (("head", "head-fat-incr.target.gz"), 0.38),
                    (("head", "head-age-decr.target.gz"), 0.25),
                    (("head", "head-scale-horiz-incr.target.gz"), 0.30),
                    (("cheek", "l-cheek-volume-incr.target.gz"), 0.50),
                    (("cheek", "r-cheek-volume-incr.target.gz"), 0.50),
                    (("nose", "nose-scale-vert-decr.target.gz"), 0.30),
                    # 0.45 on the first tuned frame pushed the whole lower face
                    # forward into a muzzle — the jaw drop shortens the chin by
                    # rotating it UP and OUT. 0.28 is the short chin without it.
                    (("chin", "chin-jaw-drop-decr.target.gz"), 0.28),
                    (("chin", "chin-width-incr.target.gz"), 0.40),
                    # A small closed mouth, as every frame of him is drawn.
                    (("mouth", "mouth-scale-horiz-decr.target.gz"), 0.25)),
        # z3e.15 hand-picked a `lips` here; bead 394 took it away — see
        # `lip_colour`. His is the brightest skin in the cast and that is exactly
        # why a literal was the wrong tool: every tuning pass on it was a pass on
        # the RATIO to this skin, which is what the derivation writes down once.
        "palette": {"skin": (0.93, 0.74, 0.62, 1.0),
                    "hair": (0.32, 0.20, 0.11, 1.0)},
        "stripes": ((0.004, 0.022, (0.20, 0.38, 0.75, 1.0)),    # blue over red,
                    (-0.024, 0.004, (0.72, 0.18, 0.15, 1.0))),  # as the art has it
        # THE BANDAGE IS CLOTH (bead z3e.13, owner 2026-09-11: "it should be real
        # mask from cloth. thick one"). `top`/`bottom` are the stripes' own z-range,
        # so the wrap covers exactly what the paint covered; `thickness` is how far
        # proud of the skull it stands. `half_angle` is the whole reason this can be
        # geometry at all: the wrap is an ARC, not a ring — it runs from one temple
        # across the face to the other and STOPS in front of the ear, where `knot`
        # ties it off. A closed ring at eye height goes through the ears.
        "band": {"top": 0.022, "bottom": -0.024, "thickness": 0.012,
                 "half_angle": 74.0, "smooth": 3,
                 # tangent x outward x up, metres — a small fold of cloth.
                 "knot": (0.026, 0.018, 0.034)},
        # BEAD z3e.15 — the shipped crop is a smooth BOWL: a helmet of hair with
        # a flat fringe sitting straight on the band. Both portraits draw short
        # tousled hair standing UP off the crown with a strip of forehead showing
        # above the bandage. `hair_lift` is the whole of that difference (the
        # shell is lifted along the vertex normal, so more lift IS more crown),
        # and `hair_front` 8 mm higher is the forehead; `hair_nape` comes in
        # because a 5.5 cm drop at the back was reading as length he does not have.
        "hair_lift": 0.014,         # short hair as a shell over the scalp, metres
        "hair_front": 0.044,        # hairline above the eye line
        "hair_nape": 0.042,         # how much lower the hairline sits at the back
    },
    "primm": {
        # docs/characters/primm.md: "slim but slightly lean", "slightly elongated
        # face. Eyes sharp and focused; hair short to medium length, dark brown.
        # Wears thin, high-tech goggles across the eyes (transparent lenses with
        # slight blue tint)."
        #
        # BEAD z3e.12, and the whole point of it: the owner looked at the first
        # Primm beside Windman and said "primm looks exactly like windman, same
        # face just without mask". He was right, and the reason was the landmark
        # bug above — the macro sliders had to sit near the basemesh default or
        # the neck cut wandered, so both heroes were built from ONE recipe with
        # different paint. With `morphed` landmarks the sliders are free again,
        # so Primm is now a YOUNGER, LEANER, LONGER-FACED man at the macro level
        # (age 0.30 / weight 0.35 / muscle 0.45 against Windman's 0.45/0.6/0.5)
        # and the targets stack the canon's elongation on top of that rather than
        # doing all the work alone.
        "macro": (("gender", 0.90), ("age", 0.30), ("muscle", 0.45),
                  ("weight", 0.35), ("caucasian", 1.0), ("african", 0.0),
                  ("asian", 0.0)),
        #
        # BEAD z3e.15 — the portraits beside the 2026-09-12 frame. z3e.12 made
        # him a DIFFERENT man from Windman, which was its job; what it did not do
        # is make him the ANGULAR one. `assets/portraits/primm.png` is all planes:
        # cheekbones that cast their own shadow, hollows under them, a thin
        # straight nose and a narrow mouth. The render is a smooth, soft, slightly
        # long oval. So the cheekbones go up and `cheek-inner-decr` digs the
        # hollow under them (the target that actually makes a face read as lean —
        # `head-fat-decr` thins the whole skull and leaves the cheek flat).
        "targets": ((("head", "head-oval.target.gz"), 0.80),
                    (("head", "head-scale-vert-incr.target.gz"), 0.50),
                    (("head", "head-fat-decr.target.gz"), 0.70),
                    (("cheek", "l-cheek-bones-incr.target.gz"), 0.70),
                    (("cheek", "r-cheek-bones-incr.target.gz"), 0.70),
                    (("cheek", "l-cheek-inner-decr.target.gz"), 0.35),
                    (("cheek", "r-cheek-inner-decr.target.gz"), 0.35),
                    (("chin", "chin-jaw-drop-incr.target.gz"), 0.40),
                    (("chin", "chin-prominent-incr.target.gz"), 0.50),
                    (("nose", "nose-scale-vert-incr.target.gz"), 0.30),
                    (("nose", "nose-width2-decr.target.gz"), 0.30),
                    (("mouth", "mouth-scale-horiz-decr.target.gz"), 0.20),
                    # "Eyes sharp and focused" — narrowed lids, both sides.
                    (("eyes", "l-eye-height2-decr.target.gz"), 0.30),
                    (("eyes", "r-eye-height2-decr.target.gz"), 0.30)),
        # THE ONE PLACE A HERO'S PALETTE LEAVES ITS GENERATOR'S (see the note at
        # the top of the table). Primm's generator skin is Windman's skin to
        # within a rounding error — (0.91, 0.73, 0.62) against (0.93, 0.74, 0.62)
        # — which is half of why the two heads read as one man. This is that tone
        # pulled cooler and paler, and the hair pulled near-black. The seam it used
        # to risk was against a generated torso's neck cylinder; there is no torso
        # and no neck cut now, the body is one mesh, so the tone answers to nothing
        # but the collar above it.
        # z3e.15 pulls the skin two more stops down and a shade cooler still: in
        # the 2026-09-12 frame his whole face above the mouth is at the top of the
        # range before the goggles even start, which is the same clip the note
        # below is about, and the portrait's Primm is the PALE-COOL one of the
        # three, not the brightest.
        "palette": {"skin": (0.86, 0.72, 0.65, 1.0),
                    "hair": (0.18, 0.11, 0.07, 1.0)},
        # A blue lens between two silver frame lines, 5.4 cm of band all told —
        # the height of the generator's own visor slab (a box 0.052 m tall).
        #
        # TWO DEPARTURES FROM THE GENERATOR'S NUMBERS, both measured on the cast
        # row rather than argued: 3.4 cm of band vanished into the blown-out
        # cheek, and so did the generator's pale `visor_lens` (0.66, 0.80, 0.90)
        # even at full height. The generated visor got away with pale because it
        # was a SLAB standing 4 cm proud of a featureless sphere and read by its
        # silhouette; paint on a face with real sockets has no silhouette and
        # must read by contrast alone. This lens is that pale blue pulled toward
        # Windman's bandage blue (0.20, 0.38, 0.75), which is the one piece of
        # painted eyewear in the cast already proven to read at 3 m — still the
        # canon's "slight blue tint", dark enough to survive the grade.
        #
        # BEAD z3e.15 REVERSES THE CONTRAST, and this is the single biggest thing
        # between his head and his portrait. The note above got the diagnosis
        # right and the prescription backwards: it pulled the LENS darker and left
        # the frames at (0.70, 0.72, 0.76), which is exactly the value it had just
        # measured clipping to flat white — so the shipped goggles are a 5.4 cm
        # band of paper white across the brow, the cheekbone and both temples,
        # with the lens a faint blue line lost inside it (the 2026-09-12
        # `17_head_face` frame, and `clipped_fraction.py` agrees). Nobody draws
        # him that way. `assets/portraits/primm.png` and
        # `docs/characters/primm.png` both draw a SLIM band with a BRIGHT CYAN
        # lens held in a DARK frame.
        #
        # So the frames take `trim_silver`'s own measured value (a fifth of the
        # way up is what lands as metal in this scene, see the colours below) and
        # the lens goes bright — the frames now have something to be dark
        # against, and the lens is the thing that glows, as drawn. And the band
        # narrows from 5.4 cm to 4.0 cm: with the frames no longer blowing out
        # there is nothing left to compensate for, and 5.4 cm covered his brow.
        "stripes": ((0.017, 0.022, (0.22, 0.24, 0.29, 1.0)),    # dark frame, top
                    (-0.012, 0.017, (0.38, 0.76, 0.90, 1.0)),   # the cyan lens
                    (-0.018, -0.012, (0.22, 0.24, 0.29, 1.0))),  # frame, bottom
        # A DIFFERENT SILHOUETTE FROM WINDMAN'S CROP (0.008 / 0.036 / 0.055), and
        # the difference is the HAIRLINE, not the length: docs/characters/primm.png
        # is short hair swept back off a high forehead with the sides above the
        # ears, where Windman's fringe comes down to the brow. So Primm's hairline
        # sits 1.4 cm higher (0.050 against 0.036) with more volume on the crown to
        # carry the sweep. A first pass at "short to MEDIUM length" put the nape at
        # 0.090 and rendered a bowl cut that covered the temples — the canon's
        # picture wins over its prose here, and the nape stays short.
        # z3e.15: the hairline was already right and the VOLUME was not. Both
        # portraits sweep his hair up and back off the forehead — it stands
        # proud of the skull, which on a shell is `hair_lift` and nothing else;
        # at 0.012 it lay flat and read as the same bowl Windman wore. Up to
        # 0.020, the hairline 8 mm higher again for the sweep, and the nape
        # tightened because the back of a swept-back cut is short.
        # (and 0.058 still put the fringe on the goggles on the first tuned frame:
        # the portrait's forehead is HIGH, so the hairline goes up again)
        "hair_lift": 0.020,
        "hair_front": 0.066,
        "hair_nape": 0.046,
    },
}


def _face_row(hero):
    """A `FACES` row's macros and face targets for `hero`, in this file's shapes.
    Two tables and not one because they answer different questions — `FACES` is
    the face MakeHuman morphs, `HEROES` is the body, the clothes and the props —
    and because the face rows arrived whole from the head spike bead z3e.12 spent
    itself on. The macros come across whole because in MakeHuman they shape the
    WHOLE human — Windman's `weight` 0.6 is the same slider that makes the
    generated torso stout, and Primm's 0.35 the same one that makes his slim."""
    row = FACES[hero]
    return dict(row["macro"]), [(rel, w) for rel, w in row["targets"]]


def _face_palette(hero):
    """A `FACES` row's skin/hair for `hero`, UNGRADED — `paint_body` applies
    `hero_skin.SKIN_GRADE` to the entries in GRADED_COLOURS, so a pre-graded value
    here would be graded twice. Primm's skin deliberately leaves his old generator's
    (the note in his row says why); Windman's is his generator's verbatim."""
    return dict(FACES[hero]["palette"])


# ---------------------------------------------------------------------------
# PRIMM'S LAB COAT — bead godot-test1-5u3.6, and the first row whose dressing is
# not three bands. `docs/characters/primm.md`: "Sleek lab-coat-style jacket, dark
# purple with silver trims along seams. Jacket is slightly open at the front,
# showing a black inner shirt with faint glowing blue lines forming a subtle
# geometric pattern. Sleeves slightly rolled up, ending just above wrists ...
# Dark blue fitted trousers ... tucked into boots ... Black, medium height, with
# subtle silver accents ... Gloves: black with silver fingertips."
#
# THE GLOWING LINES ARE VERTEX COLOUR AND NOT EMISSION. The owner's ruling for
# this epic is "yes, vertex colours"; the cast path's `DIFFUSE_TOON` has no
# emission channel to spare and a 512^2 albedo for two hairlines is the texture
# cap spent on nothing. A bright cyan against near-black reads as a glow at 3 m,
# which is the distance the acceptance is judged at.
#
# EVERY NUMBER IS A HEIGHT, because a height is the only frame `paint_body` has:
# the mesh arrives reframed (heels on z = 0, scaled to the row's `height`) and the
# arms still stand in MakeHuman's A-pose, so a sleeve hem is a z band exactly as
# the belt and the cuff are. A z band also survives the decimate, which a vertex
# index would not.
#
# AND EVERY NUMBER IS AT LEAST 3 CM, WHICH IS WHAT THIS MESH CAN DRAW. The body
# collapses to 8,200 triangles — about 3,000 vertices over a whole human, one per
# ~3 cm — and a vertex colour is Gouraud-interpolated across the triangle, so a
# band narrower than that vertex spacing does not become a thin line: it becomes a
# scatter of lit vertices smeared over their whole one-ring. Measured 2026-09-12
# on the first build of this row: a 1.6 cm silver seam took 5 of 3,000 vertices
# and rendered as pale blotches on the chest and hips, and a 13 cm-wide V-panel
# took 33 and rendered as a smudge. The rewrite below is the same coat drawn with
# the only instruments this density has — RINGS that close all the way round, and
# AREAS big enough to have an interior. `docs/style/z3e/primm_skinned_shipped.png`
# is the before/after.
PRIMM_V_DROP = 0.34       # how far the open front falls below the collar
PRIMM_V_HALF = 0.10       # half-width of the V at the top; it tapers to 0
PRIMM_V_EDGE = 0.022      # the glowing line: the outer part of the V's width
PRIMM_TRIM = 0.026        # how wide a silver seam is — one vertex ring, closed
PRIMM_SLEEVE = 0.04       # the rolled sleeve ends this far ABOVE the wrist
PRIMM_COAT_HEM = 0.02     # ... and the coat ends this far above the pelvis joint;
                          # ONE number, read by the `garments` row that cuts the
                          # step and by the seam below that has to sit on it
PRIMM_BOOT_TOP = 0.28     # medium boots: the shaft rim, above the floor
PRIMM_FINGERS = 0.035     # the silver fingertips, off the lowest glove vertex


def _primm_open_front(co, neck_z, margin=0.0):
    """The open front of the coat, as a pure test on one point — and the ONE copy
    of it, because bead 5u3.10 made the V a hole in the coat's geometry as well as
    a patch of its paint. `dress_shells` carves the V out of the shell (so the
    black inner shirt is RECESSED, and the coat's own edge is the "silver trim" the
    canon asks for: a real ledge with silver on it, not a 2 mm painted line this
    mesh cannot hold — see `dress_shells`); `_primm_coat` paints it. If the two
    ever disagreed the silver would land off the step.

    Returns (inside the V widened by `margin`, on the V's own glowing edge).
    """
    top = neck_z - 0.04
    if co.y <= 0.0 or not (top - PRIMM_V_DROP <= co.z <= top):
        return False, False
    half = PRIMM_V_HALF * (co.z - (top - PRIMM_V_DROP)) / PRIMM_V_DROP
    if abs(co.x) > half + margin:
        return False, False
    return True, abs(co.x) > half - PRIMM_V_EDGE


def _primm_coat(v, key, in_torso, ctx):
    """The `dressing` callable for the `primm` row: one vertex in, one palette key
    out, run by `paint_body` after its own three bands have had their say.

    Ordered from the hem up, because the tests are disjoint and the reader should
    be able to stop at the first one that matches.
    """
    ck = ctx["key"]
    z = v.co.z

    # THE BOOT. The `shoes` region is only foot + ball — a bare MakeHuman ankle —
    # so the shaft is the bottom of the CALF repainted, with a silver band at the
    # rim. The rim is also where `paint_body`'s 6 mm shoe shell stops, so the band
    # sits on a real step in the silhouette rather than on flat paint.
    # (Since bead 5u3.10 the shaft is also its own geometry shell, so the key
    # arriving here is already `shoes` over the calf — the rim band still has to
    # be painted, and it now sits on the shell's own step rather than on flat skin.)
    if key in (ck["trousers"], ck["shoes"]) and z <= PRIMM_BOOT_TOP:
        return ck["trim"] if z >= PRIMM_BOOT_TOP - PRIMM_TRIM else ck["shoes"]

    # THE ROLLED SLEEVE: the jacket stops 4 cm above the wrist over a silver seam,
    # and bare forearm shows below it. Scoped to the forearm so the same z band on
    # the thigh is untouched; the gloves are their own region and never come here.
    if key == ck["shirt"]:
        for side in ("l", "r"):
            if _group_weight(v, ctx["scope"]["lowerarm_" + side]) <= 0.4:
                continue
            hem = ctx["wrist_z"][side] + PRIMM_SLEEVE
            if z < hem:
                return ck["skin"]
            if z < hem + PRIMM_TRIM:
                return ck["trim"]

    # THE SILVER FINGERTIPS, measured off the lowest glove vertex. The bead asked
    # for them on the `*_03` finger BONES; those were folded into `hand_*` by the
    # owner's "cut them" ruling (`cut_fingers`), so the tips are a geometric band
    # like every other band here. The hand hangs down in the A-pose, so the lowest
    # glove vertex IS a fingertip.
    if key == ck["gloves"]:
        if "tip_z" not in ctx:
            ids = ctx["region"]["gloves"]
            ctx["tip_z"] = min((w.co.z for w in ctx["me"].vertices
                                if _group_weight(w, ids) > 0.5), default=0.0)
        return ck["trim"] if z <= ctx["tip_z"] + PRIMM_FINGERS else key

    if not in_torso:
        return key

    # THE JACKET HEM — a silver seam at the bottom of the coat, which for a lab
    # coat cut for a runner is the pelvis. This row wears no belt: the generator's
    # was its own invention and the canon has none. The band sits ABOVE the hem
    # height rather than centred on it (bead 5u3.10) because that height is now
    # the coat shell's own step, and a seam straddling it paints half its silver
    # onto the torso underneath — measured on this bead's first build, 7 to 20 mm
    # of it below the edge it was supposed to mark.
    coat_hem = ctx["pelvis_z"] + PRIMM_COAT_HEM
    if coat_hem <= z <= coat_hem + PRIMM_TRIM:
        return ck["trim"]

    # THE OPEN FRONT: a V of black inner shirt down the chest, OUTLINED in the
    # glowing cyan. `half` tapering to zero is what makes it a V and not a stripe,
    # and outlining it is what makes the "faint glowing blue lines forming a subtle
    # geometric pattern" a shape this mesh can hold — a line ACROSS the panel is
    # three vertices long, the V's own edge is forty and runs the whole chest.
    # SINCE BEAD 5u3.10 THE V IS A HOLE IN THE COAT, so there are three bands and
    # not two: the panel and its glowing edge lie on the recessed inner shirt, and
    # the ring of coat immediately OUTSIDE the V — the lapel, `PRIMM_TRIM` wide —
    # is the silver trim, riding the step `dress_shells` left there.
    lapel, _ = _primm_open_front(v.co, ctx["neck_z"], PRIMM_TRIM)
    if not lapel:
        return key
    inside, edge = _primm_open_front(v.co, ctx["neck_z"])
    if not inside:
        return ck["trim"]
    return ck["line"] if edge else ck["panel"]


# ---------------------------------------------------------------------------
# HOW A GARMENT IS CUT — bead godot-test1-5u3.10, and the only numbers in a
# `garments` row that are not landmarks. A cut is (how far the shell stands proud
# of the skin at its TOP, how far at its HEM), in metres; `dress_shells` ramps
# between the two, and that ramp is what separates a trouser leg from a pair of
# tights (its docstring has the measurement). The hem number is also the height of
# the ledge the hem cut leaves, so two garments that meet must differ by enough to
# see, and the one ABOVE must be the prouder or its hem is a step the wrong way
# round. Read a hero's `garments` from the skin outwards and check that.
#
# Measured against the mesh's own pitch: the body decimates to ~3 cm between
# vertices, so a 2 cm hem is a ledge two thirds of a triangle deep and the
# silhouette at 3 m breaks on it. Under ~8 mm it does not — bead 5u3.6's 1.6 cm
# painted seam vanished at a third of that.
GARMENT_SLEEVE = (0.010, 0.016)   # an arm with nothing else on it, and its cuff
GARMENT_FITTED = (0.012, 0.020)   # "dark blue fitted trousers", "uniform pants"
GARMENT_SHIRT = (0.016, 0.024)    # a shirt or polo, and the hem it hangs over
GARMENT_COAT = (0.018, 0.028)     # a lab coat, which hangs off the shoulders
GARMENT_BAGGY = (0.020, 0.028)    # "slightly baggy, with natural folds"
GARMENT_BOOT = (0.024, 0.030)     # a shaft that swallows the trouser tucked in it
GARMENT_WAIST = (0.020, 0.020)    # a waistband is a ridge; a ridge does not flare

# Where every hem in the cast sits, so two heroes' trousers end at the same height
# off the same landmark rather than off two typed numbers.
HEM_WAIST = ("pelvis", 0.06)      # the top of the trousers = the bottom of the shirt
HEM_ANKLE = ("shoe_top", 0.02)    # trousers stop 2 cm above the shoe
HEM_SHOULDER = ("shoulder", 0.07)  # the top of a sleeve, over the deltoid

# The bones a garment can be hung on, named once. `dress_shells` reads these
# through the row, so a garment's scope is a list of bones exactly as
# `bone_regions` is — the same currency, for the same reason.
LEG_BONES = ["pelvis", "spine_01", "thigh_l", "thigh_r", "calf_l", "calf_r"]
THIGH_BONES = ["pelvis", "spine_01", "thigh_l", "thigh_r"]
TORSO_BONES = ["spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r"]
SLEEVE_BONES = ["upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r"]
SHOULDER_BONES = ["upperarm_l", "upperarm_r"]
SHAFT_BONES = ["calf_l", "calf_r", "foot_l", "foot_r", "ball_l", "ball_r"]


HEROES = {
    "teibi": {
        # docs/characters/tiebi.md: ordinary man, medium build, calm friendly
        # face, no facial hair. spike_z3e_teibi_body.py's numbers, verbatim —
        # which is to say the SPIKE's numbers, sitting near the basemesh default
        # on purpose (the landmark bug in trap 7 punished anyone who moved them),
        # and never revisited once `morphed_coords` freed the sliders.
        #
        # BEAD z3e.15, from `assets/portraits/teibi.png` and
        # `docs/characters/teibi.png` beside the 2026-09-12 frame. Three things a
        # viewer names straight away:
        #
        #  • HE IS SMILING IN EVERY PICTURE and the head that ships is flat and a
        #    little glum. The bead licenses MakeHuman's expression targets for
        #    exactly this. `mouth-angles-up` is the plain morph (the corners lift)
        #    and `mouth-corner-puller` is the expression unit behind a real smile
        #    (it takes the cheek with it); a little of both is a closed-mouth
        #    smile and not a grin, which is what he is drawn with.
        #  • HE IS YOUNGER AND LEANER than 0.4/0.45 build him — mid-twenties,
        #    light-athletic, with a defined jawline and cheekbones you can see.
        #    So age and weight down, muscle up, the round-head target halved and
        #    `head-oval` under it, the cheek VOLUME cut back and cheek BONES
        #    brought in instead, and `chin-bones-incr` for the jaw (the old
        #    `chin-jaw-drop-decr` was shortening the very chin the portrait has).
        "macros": {"gender": 0.9, "age": 0.33, "muscle": 0.55, "weight": 0.38,
                   "caucasian": 1.0, "african": 0.0, "asian": 0.0},
        "targets": [(("head", "head-round.target.gz"), 0.15),
                    (("head", "head-oval.target.gz"), 0.35),
                    (("cheek", "l-cheek-volume-incr.target.gz"), 0.10),
                    (("cheek", "r-cheek-volume-incr.target.gz"), 0.10),
                    (("cheek", "l-cheek-bones-incr.target.gz"), 0.40),
                    (("cheek", "r-cheek-bones-incr.target.gz"), 0.40),
                    (("nose", "nose-scale-vert-decr.target.gz"), 0.15),
                    (("chin", "chin-bones-incr.target.gz"), 0.35),
                    (("mouth", "mouth-angles-up.target.gz"), 0.60),
                    (("expression", "units", "caucasian",
                      "mouth-corner-puller.target.gz"), 0.35)],
        # generate_teibi_separate.py's palette, verbatim (owner ruling: vertex
        # colours, zero texture bytes). Skin and lips reach the mesh through
        # `hero_skin.SKIN_GRADE` — the row is the paint, that constant is the exposure.
        "colours": {
            # z3e.15: the portrait's Teibi is the TANNED one of the three — a warm
            # olive against Windman's pink and Primm's cool pale. The generator's
            # (0.86, 0.66, 0.54) renders as the same peach as the other two once
            # the scene's two stops are on it; this is that tone taken down and
            # further toward olive, and it is also the row's share of keeping the
            # clipped fraction under the z3e.14 line.
            "skin":          (0.80, 0.60, 0.46, 1.0),
            "hair":          (0.17, 0.12, 0.09, 1.0),
            "beret_navy":    (0.07, 0.09, 0.19, 1.0),
            "shirt_mustard": (0.87, 0.66, 0.17, 1.0),
            "shirt_collar":  (0.74, 0.55, 0.12, 1.0),
            "trousers":      (0.20, 0.22, 0.28, 1.0),
            "belt":          (0.11, 0.10, 0.11, 1.0),
            "belt_buckle":   (0.55, 0.50, 0.30, 1.0),
            "shoes":         (0.16, 0.11, 0.08, 1.0),
            "eye_white":     (0.92, 0.92, 0.90, 1.0),
            "eye_iris":      (0.22, 0.16, 0.11, 1.0),
        },
        "colour_key": {"skin": "skin", "shirt": "shirt_mustard",
                       "trousers": "trousers", "shoes": "shoes",
                       "belt": "belt", "belt_buckle": "belt_buckle",
                       "cuff": "shirt_collar", "collar": "shirt_collar"},
        "bands": ("belt", "cuff", "collar"),
        # THE UNIFORM (owner, 2026-09-12: "teibi has uniform pants"). Straight-cut
        # trousers from a waistband ridge down to 2 cm above the shoe, and the
        # mustard polo over torso and both arms. The sleeve hem is 2 cm BELOW the
        # estimated wrist on purpose: the `cuff` band above spans wrist +- 2 cm, so
        # a sleeve stopping at the wrist would paint half that collar-coloured ring
        # onto bare forearm — this way the whole band lands on the sleeve and the
        # step is under it. (The hand is its own bone region and the scope's weight
        # test keeps the shell off it.) Order matters for the COLOUR only, later
        # rows overwriting earlier ones; the lift is `max`, so it is order-free.
        "garments": (
            {"bones": LEG_BONES, "top": HEM_WAIST, "bottom": HEM_ANKLE,
             "cut": GARMENT_FITTED, "key": "trousers"},
            {"bones": THIGH_BONES, "top": ("pelvis", 0.055),
             "bottom": ("pelvis", -0.03), "cut": GARMENT_WAIST,
             "key": "trousers"},
            {"bones": TORSO_BONES, "top": ("neck", -0.02), "bottom": HEM_WAIST,
             "cut": GARMENT_SHIRT, "key": "shirt"},
            {"bones": SLEEVE_BONES, "top": HEM_SHOULDER, "bottom": ("wrist", -0.02),
             "cut": GARMENT_SLEEVE, "key": "shirt"},
        ),
        # z3e.15: the portrait shows a clear strip of forehead between the brows
        # and the beret's brim; the shipped fringe ran down to the eyebrows.
        "hair": {"lift": 0.006, "front": 0.046, "nape": 0.045, "brows": True},
        "beret": True,
        "eyes": True,
        "height": 1.78,      # crown-to-heel, natural MakeHuman proportions
        "out_dir": "teibi_parts",
        "stem": "teibi_skinned",
    },
    "windman": {
        # docs/characters/windman.md: stout, bare-armed, blue shirt over brown
        # shorts, black boots, and the blue-over-red bandage where his eyes would
        # be. The face is his `FACES` row — see `_face_row`.
        "macros": _face_row("windman")[0],
        "targets": _face_row("windman")[1],
        # Windman's old part generator's `self.colors`, verbatim and UNGRADED.
        # `fan_*` is not here: the fan is an ATTACHMENT, hung on
        # `hand_r` by bead 5u3.5's .tscn, and windman_fan.glb keeps its own colours.
        "colours": dict(_face_palette("windman"), **{
            "shirt_blue":   (0.16, 0.33, 0.60, 1.0),
            "letter_white": (0.93, 0.93, 0.93, 1.0),
            "shorts_brown": (0.42, 0.30, 0.18, 1.0),
            "boots_black":  (0.08, 0.08, 0.09, 1.0),
        }),
        # THE CHEST "W" — the defining icon, and the first motif in this lane
        # (bead godot-test1-5u3.5). VERTEX COLOUR, not a body albedo: the owner's
        # 2026-09-11 ruling asks for a texture only "where a motif needs it", and
        # this one does not — `paint_chest_glyph` measured 13.6 mm between chest
        # vertices against a 54 mm stroke, four vertices across every arm of the
        # letter, so the glyph resolves with zero texture bytes and no UV path.
        # The SHAPE is that generator's own `_make_w_emblem`, verbatim:
        # the same five-point centre-line and the same 27 mm buffer the retired
        # generator extruded — which is why the letter did not change the day it
        # stopped being geometry.
        "emblem": {
            "points": ((-0.092, 0.135), (-0.044, -0.048), (0.0, 0.072),
                       (0.044, -0.048), (0.092, 0.135)),
            "stroke": 0.027,
            # The generator hung the letter off its own torso part; this row hangs
            # it off a LANDMARK, so it rides the macros. 0.28 m below the neck
            # joint puts the glyph's origin at the sternum and its 18 cm of letter
            # between the collarbones and the waistband.
            "drop": 0.28,
            "colour": "letter_white",
            # The two asserts. `min_faces` is the densify's: it fails if the glyph
            # is not over a chest any more. `min_verts` is the paint's: below it
            # the letter is a rash of white dots rather than a "W".
            "min_faces": 80,
            "min_verts": 120,
        },
        # BARE ARMS AND SHORTS, AS BONE REGIONS. The generator paints the whole
        # upper and lower arm skin and leaves only a shirt-blue cap at the
        # shoulder, and paints the calves skin below brown shorts — which is
        # exactly `upperarm`/`lowerarm` and `calf` moving out of their default
        # regions, with `clavicle_*` left behind in "shirt" as the cap.
        "bone_regions": {"upperarm_l": "skin", "upperarm_r": "skin",
                         "lowerarm_l": "skin", "lowerarm_r": "skin",
                         "calf_l": "skin", "calf_r": "skin"},
        "colour_key": {"skin": "skin", "shirt": "shirt_blue",
                       "trousers": "shorts_brown", "shoes": "boots_black"},
        # No belt, no cuff, no collar: the generator's torso is one flat blue and
        # the arms it would band are bare skin now.
        "bands": (),
        # THE SHORTS AND THE T-SHIRT (owner, 2026-09-12: "Windman has shorts").
        # docs/characters/windman.md: "Brown shorts to the knee, straight cut ...
        # slightly baggy, with natural folds when moving", and a T-shirt whose
        # sleeves are "sleeveless or ... short sleeves that go to mid-shoulder".
        # So the shorts are the baggiest thing in the cast and they stop 3 cm
        # ABOVE the knee, with bare calf below (`below` puts the skin back on the
        # thigh the `trousers` bone region would otherwise paint brown all the way
        # down), and the sleeve is a cap ending a third of the way down the upper
        # arm — the first time his arms have worn anything at all.
        "garments": (
            {"bones": THIGH_BONES, "top": HEM_WAIST, "bottom": ("knee", 0.03),
             "cut": GARMENT_BAGGY, "key": "trousers", "below": "skin"},
            {"bones": TORSO_BONES, "top": ("neck", -0.02), "bottom": HEM_WAIST,
             "cut": GARMENT_SHIRT, "key": "shirt"},
            {"bones": SHOULDER_BONES, "top": HEM_SHOULDER,
             "bottom": ("shoulder", -0.10), "cut": GARMENT_SLEEVE,
             "key": "shirt"},
        ),
        # THE BANDAGE IS CLOTH, and it is bead z3e.13's cloth — `wrap_band` and the
        # row it reads, imported. It also deletes the eye sockets under it, which
        # is why this row builds no eyeballs: "windman has no eyes, he use air
        # abilities to see" (owner, 2026-09-11).
        "band": FACES["windman"]["band"],
        "stripes": FACES["windman"]["stripes"],
        "hair": dict(zip(("lift", "front", "nape"),
                         (FACES["windman"]["hair_lift"],
                          FACES["windman"]["hair_front"],
                          FACES["windman"]["hair_nape"])), brows=False),
        "beret": False,
        "eyes": False,
        # blender_hero.py measured the generated Windman at 1.7536 m; the skinned
        # body replaces it and keeps its silhouette.
        "height": 1.75,
        "out_dir": "windman_parts",
        "stem": "windman_skinned",
    },
    "primm": {
        # docs/characters/primm.md: slim, purple coat over a black shirt, navy
        # trousers, black boots and gloves, thin high-tech goggles. The face is the
        # spike's z3e.12 recipe — younger, leaner, longer than Windman's.
        "macros": _face_row("primm")[0],
        "targets": _face_row("primm")[1],
        # generate_primm_separate.py's `self.colors`, verbatim and UNGRADED, plus,
        # from bead 5u3.6, the three the coat itself needs. The generator's `belt_black`/`belt_buckle`/`cuff_grey` left with
        # the belt and the cuff (see `bands` below): the canon dresses him in an
        # open lab coat with rolled sleeves, not a shirt tucked into a belt.
        "colours": dict(_face_palette("primm"), **{
            "coat_purple": (0.30, 0.15, 0.44, 1.0),
            "coat_collar": (0.25, 0.12, 0.37, 1.0),
            "glove_black": (0.06, 0.06, 0.07, 1.0),
            # THE ONE GENERATOR COLOUR THIS ROW MOVES, and it is moved to be seen:
            # the generator's (0.10, 0.11, 0.17) trouser is within a hair of its own
            # (0.07, 0.07, 0.08) boot, which was fine when the boot was a separate
            # part with its own silhouette and is not fine now that the boot is the
            # bottom of the same leg. Still "dark blue fitted trousers", two stops
            # up, so the black shaft has something to be black against.
            "jeans_navy":  (0.15, 0.17, 0.29, 1.0),
            "boots_black": (0.05, 0.05, 0.06, 1.0),
            # "silver trims along seams", "subtle silver accents", "silver
            # fingertips" — ONE silver, because they are one material, and a DARK
            # one, and a DARK one — this field is not read as a colour on screen,
            # it is read through the cast's own exposure. Measured 2026-09-12 in
            # shot 18 on the web renderer across three builds: (0.76, 0.79, 0.84)
            # and (0.40, 0.43, 0.49) BOTH clip to flat white, because the scene
            # lifts an albedo by roughly two stops before DIFFUSE_TOON quantises it
            # — the same clip that ate 3.4 cm of Primm's goggle band in bead z3e.5.
            # A fifth of the way up is what lands as metal in that frame.
            "trim_silver": (0.20, 0.22, 0.27, 1.0),
            "panel_black": (0.04, 0.04, 0.05, 1.0),
            # The "faint glowing blue lines": vertex colour, not emission. Bright
            # enough against `panel_black` to read as a glow at 3 m.
            "line_cyan":   (0.20, 0.66, 0.82, 1.0),
        }),
        "bone_regions": {"hand_l": "gloves", "hand_r": "gloves"},
        "colour_key": {"skin": "skin", "shirt": "coat_purple",
                       "trousers": "jeans_navy", "shoes": "boots_black",
                       "gloves": "glove_black", "collar": "coat_collar",
                       # `_primm_coat`'s own three, on the same dictionary because
                       # a key is a key and `paint_body` resolves them all alike.
                       "trim": "trim_silver", "panel": "panel_black",
                       "line": "line_cyan"},
        # ONLY THE COLLAR of the three shared bands. The belt is gone (a lab coat
        # has none) and the cuff with it (the sleeve now ends 4 cm above the wrist,
        # which is `_primm_coat`'s job and a different band entirely).
        "bands": ("collar",),
        # THE COAT, AS A COAT (owner, 2026-09-12: "prim has long jacket, like a
        # tuxedo with tails"). The jacket shell stands 1.5 cm proud of the torso
        # and is CARVED at the open front, so the black inner shirt is recessed
        # and `_primm_coat`'s silver lapel has a real step to sit on; its sleeves
        # stop over the rolled-sleeve seam 4 cm above the wrist; the trousers are
        # fitted and TUCKED IN (they stop at the boot rim, and the shaft shell is
        # deeper, so the boot swallows them); the tails hang off the back hem —
        # see `attach_tails`, which is the only garment here that is new geometry.
        "garments": (
            {"bones": LEG_BONES, "top": ("pelvis", 0.04),
             "bottom": ("ground", PRIMM_BOOT_TOP), "cut": GARMENT_FITTED,
             "key": "trousers"},
            {"bones": SHAFT_BONES, "top": ("ground", PRIMM_BOOT_TOP),
             "bottom": ("ground", 0.0), "cut": GARMENT_BOOT, "key": "shoes"},
            {"bones": TORSO_BONES, "top": ("neck", -0.02),
             "bottom": ("pelvis", PRIMM_COAT_HEM), "cut": GARMENT_COAT, "key": "shirt",
             "carve": lambda v, z: _primm_open_front(v.co, z["neck"])[0]},
            {"bones": SLEEVE_BONES, "top": HEM_SHOULDER,
             "bottom": ("wrist", PRIMM_SLEEVE), "cut": GARMENT_SLEEVE,
             "key": "shirt"},
        ),
        # pelvis 0.6 / thigh 0.4, and the thigh half is not decoration: a flap
        # welded to the hips alone is a flap the back leg walks straight through.
        "tails": {"pelvis": 0.6},
        "dressing": _primm_coat,
        # THE GOGGLES ARE PAINT, not cloth — no `band` key. The spike's own ruling:
        # a lens is not a wrap, and stripes on the skin are what shipped.
        "stripes": FACES["primm"]["stripes"],
        "hair": dict(zip(("lift", "front", "nape"),
                         (FACES["primm"]["hair_lift"],
                          FACES["primm"]["hair_front"],
                          FACES["primm"]["hair_nape"])), brows=False),
        "beret": False,
        # The goggles cover the sockets; two white spheres behind a painted lens
        # would only poke through it.
        "eyes": False,
        # blender_hero.py measured the generated Primm at 1.7733 m with the
        # authored head.
        "height": 1.78,
        "out_dir": "primm_parts",
        "stem": "primm_skinned",
    },
}

# A FACE AND A FOREARM DO NOT WANT THE SAME DENSITY, so the collapse is aimed at
# each separately (`decimate`). Measured 2026-09-11 on Teibi's build: the MakeHuman
# head is 8,542 of the baked body's 26,756 triangles and a UNIFORM collapse hands
# it back only 26% of whatever it is given — 3,859 head triangles at a 12,600
# target, under the 4k floor, and no budget under ~15.5k fixes that for a hero who
# has no beret and no eyeballs to make the number up with. The head is 8% of the
# silhouette and all of the acting, so it gets its own target instead.
BODY_TRIS = 8200             # marginally denser than the 7,790 Teibi shipped at
HEAD_TRIS = 4400             # the spike's own 4,500-triangle head, at body scale
# INCL. EVERY ACCESSORY JOINED AFTER THE COLLAPSE, and since bead 5u3.10 every
# hem. Was 14,000, which the shipped Windman sat 589 triangles under: the garment
# shells cut two edge rings per hem (`dress_shells`) and Primm's coat tails join
# two boxes, and the bead's own ceiling is "+40 percent per hero", which for the
# fattest of the three is 18,775. 15,500 is the measured build plus room for one
# more garment, not the ceiling — a row that needs the rest of the 40% should
# come with the frame time that says it can have it.
TRI_BUDGET = 15500
HEAD_TRIS_MIN = 4000         # the face must survive the body's budget

# THE SHOE SHELL (bead 5u3.3's polish slot). MakeHuman ships bare feet with toes,
# and painting them brown reads as BARE FEET at 3 m — the toe split is still
# there in silhouette. So the shoe is geometry, by the same idiom as the hair:
# push the foot region's verts out along their own normals, which thickens the
# whole foot into a low dark slipper and swallows the toe gaps, then hold the
# sole ON the ground rather than 6 mm under it (`reframe()` put the bare heel at
# z = 0, and the hero's feet may not sink into the floor to buy a shoe).
SHOE_LIFT = 0.006

# Which palette entries are skin, and therefore go through `hero_skin.SKIN_GRADE`.
# `lips` is NOT a palette entry any more (bead godot-test1-394) — it is derived from
# the graded skin by `lip_colour`, so it is graded by construction.
GRADED_COLOURS = ("skin",)


def _luma(c):
    """Rec.709 luma, the same one `scripts/clipped_fraction.py` judges a face by."""
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def lip_colour(skin):
    """The mouth, from the hero's own GRADED skin: `LIP_DARKEN` down and `LIP_RED`
    warmer. See those constants for why it is not three literals any more.

    AND IT IS ASSERTED, because the vertex floor and `CHIN_CLEAR` are both about
    WHERE the lips are and neither can see a mouth that is the wrong COLOUR — the
    hero ships with the same verts, the same tris and the same bytes whether the
    band reads as a mouth, as nothing at all, or as a beard. `LIP_RED` lifts the red
    channel, so the luma drop is not `1 - LIP_DARKEN` and has to be measured."""
    r, g, b = skin[:3]
    out = (min(1.0, r * LIP_DARKEN * LIP_RED), g * LIP_DARKEN, b * LIP_DARKEN,
           ) + tuple(skin[3:])
    drop = 1.0 - _luma(out) / max(_luma(skin), 1e-6)
    low, high = LIP_CONTRAST
    if not low <= drop <= high:
        raise AssertionError(
            "the lips are %.1f%% darker than the skin, outside %.0f-%.0f%%: too "
            "little is no mouth at 3 m, too much is the beard bead 394 removed"
            % (drop * 100.0, low * 100.0, high * 100.0))
    return out


def log(*a):
    print("[BUILD]", *a)
    sys.stdout.flush()


def enable_mpfb():
    target = "bl_ext.blender_org.mpfb"
    addon_utils.enable(target, default_set=True, persistent=True)
    importlib.import_module(target)


def dyn(module_suffix, key):
    for name in sys.modules:
        if name.endswith(module_suffix):
            mod = importlib.import_module(name)
            if hasattr(mod, key):
                return getattr(mod, key)
    raise ValueError("no module %s with %s" % (module_suffix, key))


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)


# THE LANDMARKS ARE THE SPIKE'S, INCLUDING ITS BUG FIX. `morphed_coords` reads the
# joint cubes off the EVALUATED mesh (bead z3e.12, TRAP 7 in the header) and
# `joint_centroid` averages them; this file used to average `v.co` instead, which is
# the UNMORPHED basemesh. It got away with it for Teibi, whose macros sit near the
# basemesh default — and did not for Primm, whose age 0.30 / weight 0.35 shorten the
# morphed body to 1.505 m while the raw one stays 1.61, putting his eye landmark
# 5 cm ABOVE his own crown once `reframe()`'s matrix was applied to it (measured
# 2026-09-11, bead 5u3.4: his hairline landed off the top of his head and he came
# out bald). One import, and the bug cannot come back to this lane either.
def morphed_coords(obj):
    """Object-space vertex coordinates WITH every macro and target applied.

    `obj.data.vertices[i].co` is the UNMORPHED basemesh: MPFB2 applies macros and
    targets as shape keys, and a shape key does not move `vertex.co`. Evaluating
    the object as it stands does not help either — the helper MASK modifier deletes
    the `joint-*` cubes, which are exactly the landmarks we are here for. So the
    modifiers are switched off for the length of one depsgraph update: the evaluated
    mesh is then the basemesh plus its shape keys, in the same order, so index `i`
    still names the same vertex as `obj.data.vertices[i]` — which is where the
    vertex GROUPS stay readable. The equal-length assert is that guarantee's fence.
    """
    disabled = [m for m in obj.modifiers if m.show_viewport]
    for mod in disabled:
        mod.show_viewport = False
    try:
        bpy.context.view_layer.update()
        evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
        mesh = evaluated.to_mesh()
        if len(mesh.vertices) != len(obj.data.vertices):
            raise AssertionError(
                "evaluated mesh has %d verts, basemesh %d: a modifier is still "
                "changing the topology and the vertex groups no longer line up"
                % (len(mesh.vertices), len(obj.data.vertices)))
        coords = [v.co.copy() for v in mesh.vertices]
        evaluated.to_mesh_clear()
    finally:
        for mod in disabled:
            mod.show_viewport = True
    return coords


def joint_centroid(obj, group_name, coords):
    """Centre of one of the basemesh's helper JOINT CUBES, in object space. This is
    how the neck cut and the eye line are found: they are MakeHuman's own landmarks,
    not numbers guessed off a bounding box.

    Group MEMBERSHIP comes from `obj.data` (the only place it lives) and the
    POSITION from `coords` — `morphed_coords`'s evaluated copy, so the landmark
    tracks the macro sliders instead of the basemesh they morphed away from."""
    idx = obj.vertex_groups[group_name].index
    acc = Vector((0.0, 0.0, 0.0))
    n = 0
    for v in obj.data.vertices:
        for g in v.groups:
            if g.group == idx:
                acc += coords[v.index]
                n += 1
                break
    if n == 0:
        raise ValueError("empty vertex group " + group_name)
    return acc / n


def wrap_band(obj, eye_z, cfg):
    """The blindfold as CLOTH: a thick wrap lifted off the face, not paint on it.

    OWNER, 2026-09-11 (bead z3e.13): "windman mask seems like it's color sprayed /
    drawed on his face, it should be real mask from cloth. thick one. windman has no
    eyes". So the eye sockets are deleted and capped flat, and the slab of face inside
    the stripes' own z-range, from one temple across to the other, is EXTRUDED off the
    blank skull and pushed out horizontally: the lifted faces become the cloth's outer
    surface, the extrusion's side walls become its top and bottom rims (flat-shaded,
    so the edge is crisp and casts a shadow), and the face left underneath is deleted
    with the sockets. It stays flush ("fits tightly to the face") because it IS the
    face's own surface, offset.

    THE EARS ARE WHY THIS IS AN ARC AND NOT A RING. `half_angle` stops the wrap in
    front of each ear, where a small `knot` box ties it off — docs/characters/
    windman.md's "fastened near the ears". A ring at eye height goes through them.

    The push is RADIAL about the skull's vertical axis rather than along each vertex
    normal, and the lifted faces are smoothed first: cloth lies over a brow and a
    cheekbone, and a normal-offset would re-inflate every one of their creases as a
    bump in it.

    Returns (band vertex indices, flat-shaded polygon indices) for `paint` and
    `export`; both are empty for a hero whose row has no `band`.
    """
    band = cfg.get("band")
    if band is None:
        return frozenset(), frozenset()

    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uv_layer = bm.loops.layers.uv.active
    top = eye_z + band["top"]
    bottom = eye_z + band["bottom"]
    half = math.radians(band["half_angle"])
    thickness = band["thickness"]

    # THE TWO LINES ARE CUT INTO THE SKULL FIRST, because `lifted` below is a
    # face-by-face selection and a selection can only follow edges that exist. Without
    # the cuts the wrap's boundary is the head's own triangulation, and straightening
    # it afterwards can only ever reach one side: the snap this file used to do pulled
    # the CLOTH's rim onto the two lines and left the skin it was lifted off with the
    # sawtooth, so the edge that met the cheek was a triangle ragged while the outer
    # one was straight (bead z3e.16, grid 25). Bisecting puts a real edge ring at
    # `top` and at `bottom` and both edges lie on it — the same measurement
    # `build_hero.dress_shells` cuts every garment hem for.
    for height in (top, bottom):
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:],
                               dist=1e-5, plane_co=(0.0, 0.0, height),
                               plane_no=(0.0, 0.0, 1.0))

    # The skull's vertical axis, taken from the band's own slab so the arc is centred
    # on the face and not on a bounding box that includes the neck stump.
    slab = [v.co for v in bm.verts if bottom <= v.co.z <= top]
    axis = Vector(((min(c.x for c in slab) + max(c.x for c in slab)) / 2.0,
                   (min(c.y for c in slab) + max(c.y for c in slab)) / 2.0))

    def bearing(co):
        """Angle off dead-ahead (+Y), about the skull's axis. 0 = nose, +-90 = ear."""
        return math.atan2(co.x - axis.x, co.y - axis.y)

    def outward(co):
        out = Vector((co.x - axis.x, co.y - axis.y, 0.0))
        return out.normalized() if out.length > 1e-6 else Vector((0.0, 1.0, 0.0))

    def wrapped(co):
        return bottom <= co.z <= top and abs(bearing(co)) <= half

    lifted = [f for f in bm.faces if wrapped(f.calc_center_median())]
    if not lifted:
        raise AssertionError("no faces in the band slab z %.3f..%.3f" % (bottom, top))

    # THE EYES GO FIRST, and this is where "windman has no eyes, he use air abilities
    # to see" is actually carried out. MakeHuman's basemesh does not stop at the lids:
    # it folds inward and lines the SOCKET, around helper eyeballs that MPFB2's mask
    # already deleted. Lifted with the rest, that lining came out as two dark holes in
    # the middle of the bandage (first render of this bead). A face that points back
    # INTO the skull is socket and nothing else at this height — the skin, the temples
    # and even the bridge of the nose all face outward — so they are deleted and the
    # two openings capped flat, and the cloth is lifted off a blank face.
    sockets = [f for f in lifted
               if f.normal.dot(outward(f.calc_center_median())) < -0.2]
    # The hole they leave has a RIM, and that rim is a boundary of the lifted patch
    # too — an inner one, which ends up UNDER the cloth instead of beside it, so the
    # `skin_edge` assert below excuses it. Read here, while those faces still exist.
    socket_set = set(sockets)
    hole_rim = set(v for f in sockets for v in f.verts
                   if any(g not in socket_set for g in v.link_faces))
    if sockets:
        bmesh.ops.delete(bm, geom=sockets, context='FACES')
        # THE SOCKETS ARE THE ONLY OPEN EDGES, so filling every boundary edge
        # fills exactly them. This lane builds a WHOLE human and never cuts a neck
        # (the head spike did, and capped its own hole; bead 5u3.8 deleted it), so
        # the body arrives closed and these two holes are the ones just made.
        caps = [f for f in bmesh.ops.holes_fill(
            bm, edges=[e for e in bm.edges if e.is_boundary], sides=0)["faces"]
            if isinstance(f, bmesh.types.BMFace)]
        # ONE texel per cap, not the lid's own UVs. `holes_fill` writes no UVs at
        # all, and inheriting them from the ring lands the cap on MakeHuman's tiny
        # EYE island, where the wrap's seam line and its blue half occupy a third of
        # the island each and bake back onto the face as two eye-shaped blotches (the
        # third render of this bead: the bandage looked see-through). A cap is two
        # centimetres of cloth over a closed socket — one flat colour, taken from its
        # own lowest corner, is all of it.
        cap_set = set(caps)
        for f in caps:
            low = min(f.verts, key=lambda v: v.co.z)
            flat_uv = next(other[uv_layer].uv.copy() for other in low.link_loops
                           if other.face not in cap_set)
            for loop in f.loops:
                loop[uv_layer].uv = flat_uv
        lifted = [f for f in lifted if f.is_valid] + caps
        log("band: removed %d socket faces, capped with %d" % (len(sockets), len(caps)))

    ret = bmesh.ops.extrude_face_region(bm, geom=lifted)
    # The op returns the LIFTED CAP — its faces and every vertex of them, the
    # duplicated boundary included. The side walls it builds are NOT in that result:
    # they are the other faces that touch a cap vertex, and the skin around the hole
    # cannot be one of them because it kept the originals of those duplicates.
    moved = set(e for e in ret["geom"] if isinstance(e, bmesh.types.BMVert))
    cloth = set(e for e in ret["geom"] if isinstance(e, bmesh.types.BMFace))
    walls = [f for f in bm.faces
             if f not in cloth and any(v in moved for v in f.verts)]
    if not walls or len(cloth) != len(lifted):
        raise AssertionError(
            "extrude_face_region gave %d cap faces (%d lifted), %d verts and %d "
            "walls: the wrap would not be a closed shell"
            % (len(cloth), len(lifted), len(moved), len(walls)))
    # AND THIS IS WHAT SAYS THE CUT LANDED. A wall's vertices that are NOT the
    # extrusion's own are the originals of the duplicated boundary — the line where
    # the cloth meets the skin, and the one nothing here ever moves. After the bisect
    # every one of them sits on a band line. Two parts of that boundary are excused:
    # the arc's two ENDS, where it runs up the face and is meant to follow the
    # triangulation, and the capped sockets, whose rims are a hole inside the patch
    # and end up under the cloth rather than beside it. Measured on THIS check with
    # the two cuts disabled: 55 of 67 skin-side vertices off the lines, by up to
    # 1.0 cm. With them, none — on bead z3e.16's Windman. On z3e.15's wider skull
    # two vertices per arc end sit 6.6-6.8 degrees past the arc, which is one 9 mm
    # triangle and which is why `ARC_END_SLACK` is 0.14 rather than 0.10; off the
    # arc ends it is still none, and that is the half this assert is about. (The
    # ceiling is half the slab, 2.3 cm — a boundary vertex cannot be further than
    # that from BOTH lines.)
    skin_edge = set(v for f in walls for v in f.verts) - moved - hole_rim
    ragged = [v for v in skin_edge
              if abs(abs(bearing(v.co)) - half) >= ARC_END_SLACK
              and min(abs(v.co.z - top), abs(v.co.z - bottom)) > 1e-4]
    if ragged:
        raise AssertionError(
            "%d of %d skin-side band vertices are off both band lines, by up to "
            "%.4f m: the bisect did not cut the boundary. Offenders (metres off "
            "the nearer line, degrees inside the arc end): %s"
            % (len(ragged), len(skin_edge),
               max(min(abs(v.co.z - top), abs(v.co.z - bottom)) for v in ragged),
               ", ".join("%.4f/%.1f"
                         % (min(abs(v.co.z - top), abs(v.co.z - bottom)),
                            math.degrees(half - abs(bearing(v.co))))
                         for v in ragged)))
    # AND THE FACE UNDER THE CLOTH GOES WITH IT: the extrusion leaves the original
    # faces behind as an inner shell, and an inner shell is 1,200 triangles nobody
    # will ever see. The walls already close the hole it leaves.
    bmesh.ops.delete(bm, geom=lifted, context='FACES')

    # Flatten the sockets before the lift (the rim is pinned: it is shared with the
    # walls, and moving it would tear the cloth away from its own edge).
    rim = set(v for f in walls for v in f.verts) & moved
    interior = [v for v in moved if v not in rim]
    for _ in range(band["smooth"]):
        bmesh.ops.smooth_vert(bm, verts=interior, factor=0.5,
                              use_axis_x=True, use_axis_y=True, use_axis_z=True)
    # THE HEM IS THE CUT NOW. Until bead z3e.16 the rim was SNAPPED here — pulled
    # onto the band's two lines, because a face-by-face selection leaves a sawtooth
    # and sawtooth cloth reads as TORN. It straightened the cloth's own edge and
    # could not straighten the skin's, which is half a fix; the bisect above
    # straightens both, and the assert on `skin_edge` is what holds it there.
    for v in moved:
        out = Vector((v.co.x - axis.x, v.co.y - axis.y, 0.0))
        if out.length > 1e-6:
            v.co += out.normalized() * thickness

    # The rims and the knots have no UVs of their own — the extrusion copies the
    # boundary loop's and `create_cube` writes none at all. The head spike BAKED
    # through these UVs and an unset one sampled whatever sat at (0, 0); this lane
    # bakes nothing (`texture bytes: 0`), so the fixup is now insurance for the day
    # a row brings a bake — cheap, and the wrap is the one place UVs go missing.
    # Each is given a coordinate from the cloth beside it: the rim from its own
    # lifted corners, the
    # knot from the wrap's end at the same height. Overlapping the cloth's island is
    # exactly what is wanted here — they are the same cloth.
    uv_of = {}
    for f in cloth:
        for loop in f.loops:
            uv_of.setdefault(loop.vert, loop[uv_layer].uv.copy())
    for f in walls:
        inside = [uv_of[v] for v in f.verts if v in uv_of]
        fallback = sum(inside, Vector((0.0, 0.0))) / len(inside)
        for loop in f.loops:
            loop[uv_layer].uv = uv_of.get(loop.vert, fallback)

    knots = []
    for side in (-1.0, 1.0):
        ends = [v for v in moved if abs(bearing(v.co) - side * half) < 0.12]
        if not ends:
            continue
        centre = sum((v.co for v in ends), Vector()) / len(ends)
        out = Vector((math.sin(side * half), math.cos(side * half), 0.0))
        tangent = Vector((out.y, -out.x, 0.0))
        w, d, h = band["knot"]
        placed = centre + out * (thickness * 0.25)
        matrix = Matrix(((tangent.x * w, out.x * d, 0.0, placed.x),
                         (tangent.y * w, out.y * d, 0.0, placed.y),
                         (0.0, 0.0, h, placed.z),
                         (0.0, 0.0, 0.0, 1.0)))
        made = bmesh.ops.create_cube(bm, size=1.0, matrix=matrix)
        box = set(e for e in made["verts"] if isinstance(e, bmesh.types.BMVert))
        moved |= box
        for f in bm.faces:
            if f in knots or not all(v in box for v in f.verts):
                continue
            knots.append(f)
            for loop in f.loops:
                near = min(ends, key=lambda e: abs(e.co.z - loop.vert.co.z))
                loop[uv_layer].uv = uv_of[near]
    log("band: %d cloth faces, %d rim faces, %d knot faces, %d verts"
        % (len(cloth), len(walls), len(knots), len(moved)))

    for f in bm.faces:
        f.smooth = True
    for f in walls + knots:
        f.smooth = False
    bm.verts.index_update()
    bm.faces.index_update()
    band_verts = frozenset(v.index for v in moved)
    flat_faces = frozenset(f.index for f in walls + knots)
    bm.to_mesh(me)
    bm.free()
    me.update()
    return band_verts, flat_faces


# ---------------------------------------------------------------------------
# The human, the rig
# ---------------------------------------------------------------------------

def build_human(row):
    HumanService = dyn("mpfb.services.humanservice", "HumanService")
    TargetService = dyn("mpfb.services.targetservice", "TargetService")
    LocationService = dyn("mpfb.services.locationservice", "LocationService")
    HumanObjectProperties = dyn("mpfb.entities.objectproperties", "HumanObjectProperties")

    human = HumanService.create_human(mask_helpers=True, detailed_helpers=True,
                                      extra_vertex_groups=True)
    for key, value in row["macros"].items():
        HumanObjectProperties.set_value(key, value, entity_reference=human)
    TargetService.reapply_macro_details(human)

    targets_root = LocationService.get_mpfb_data("targets")
    for rel, weight in row["targets"]:
        path = os.path.join(targets_root, *rel)
        # RAISE, DO NOT SKIP (bead z3e.15). This used to log and carry on, which
        # means a mistyped target name is a face that quietly builds WITHOUT the
        # shape the row asked for — and the row is prose plus a filename, so the
        # typo is invisible in review and the .glb looks plausible. The manifest
        # would not catch it either; nothing downstream knows what the face was
        # supposed to be. MPFB2 2.0.17 is pinned in `hero_manifest.json`, so a
        # name that resolves here resolves on every machine this lane runs on.
        if not os.path.exists(path):
            raise AssertionError("no such MPFB2 target: %s" % path)
        TargetService.load_target(human, path, weight=weight)

    coords = morphed_coords(human)
    # THE GROUP LIST, PRINTED ONCE (bead godot-test1-394), because the bead asked
    # for the lips to come off "MakeHuman's own mouth/lips vertex groups" and the
    # answer had to be looked up rather than assumed. It is left in as the log line
    # that proves the group is there on the machine the build ran on: MPFB2's
    # `extra_vertex_groups=True` (this call, already) ships eight body-region groups
    # beside the `joint-*` helper cubes, and `lips` is one of them — 418 basemesh
    # vertices, the region MPFB's own layered skin material paints the lips with.
    # `paint_body` reads exactly that group; nothing here is a z band any more.
    log("basemesh groups matching mouth/lip/jaw/chin:",
        sorted(g.name for g in human.vertex_groups
               if any(w in g.name for w in ("mouth", "lip", "jaw", "chin"))))
    joints = {}
    for name in ("neck", "l-shoulder", "r-shoulder", "l-elbow", "r-elbow",
                 "l-upper-leg", "r-upper-leg", "l-knee", "r-knee", "pelvis",
                 "l-eye", "r-eye"):
        joints[name] = joint_centroid(human, "joint-" + name, coords)
    log("joints (morphed basemesh space):",
        {k: tuple(round(c, 4) for c in v) for k, v in joints.items()})
    return human, joints


def add_rig(human):
    """TRAP 1: before `convert()`, because the weights JSON is basemesh-indexed."""
    HumanService = dyn("mpfb.services.humanservice", "HumanService")
    armature = HumanService.add_builtin_rig(human, RIG, import_weights=True)
    if armature is None:
        raise AssertionError("add_builtin_rig returned None for rig " + RIG)
    bones = len(armature.data.bones)
    log("rig %r: %d bones, armature %r" % (RIG, bones, armature.name))
    if bones != RIG_BONES:
        raise AssertionError("expected %d bones, got %d" % (RIG_BONES, bones))
    # The armature object owns the human's old location; both are at the origin
    # for us, but keep the invariant explicit — `reframe()` bakes into DATA and
    # assumes both objects are at identity.
    armature.location = (0.0, 0.0, 0.0)
    human.location = (0.0, 0.0, 0.0)
    return armature


def cut_fingers(human, armature):
    """
    OWNER RULING 2026-09-11, "cut them": fold the 30 finger bones' skin weights
    into `hand_l` / `hand_r` and delete the bones, leaving the 23-bone rig the
    game ships.

    TRAP 1 applies: this runs on the RAW human, BEFORE `convert()`, because it
    reads and writes the vertex groups `add_builtin_rig` just wrote off the
    basemesh-indexed weights JSON.

    THE FOLD IS A PLAIN SUM AND THAT IS EXACTLY RIGHT. MPFB2's weights are
    normalised per vertex (every vertex's bone weights sum to 1), so moving a
    fingertip's five-or-so finger weights onto the one bone that all of them
    hang off leaves the vertex's total untouched — `report_weights()` after the
    bake is what proves it, and the region argmax in `paint_body()` is a sum
    over a bone GROUP that already contains both the fingers and the hand, so
    the paint comes out byte-identical.

    Deleting the bones is what actually saves anything: every finger bone is a
    joint matrix uploaded per frame and a palette slot the web renderer's
    transform-feedback skinning pass pays for, for a shape no camera in this
    game can resolve.
    """
    for side in ("l", "r"):
        hand = "hand_" + side
        if hand not in human.vertex_groups:
            raise AssertionError("no %s vertex group to fold the fingers into" % hand)
        hand_vg = human.vertex_groups[hand]
        finger_ids = {human.vertex_groups[n].index: n
                      for n in _fingers(side) if n in human.vertex_groups}
        moved = 0
        for v in human.data.vertices:
            extra = sum(g.weight for g in v.groups if g.group in finger_ids)
            if extra <= 0.0:
                continue
            held = next((g.weight for g in v.groups if g.group == hand_vg.index), 0.0)
            hand_vg.add([v.index], held + extra, 'REPLACE')
            moved += 1
        log("fold %s: %d finger groups -> %s on %d verts"
            % (side, len(finger_ids), hand, moved))
        for name in _fingers(side):
            if name in human.vertex_groups:
                human.vertex_groups.remove(human.vertex_groups[name])

    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.context.view_layer.objects.active = armature
    for o in bpy.data.objects:
        o.select_set(o is armature)
    bpy.ops.object.mode_set(mode='EDIT')
    edit_bones = armature.data.edit_bones
    # Tip-first, so a chain is never removed through its own parent: Blender
    # reparents a removed bone's children to ITS parent, which would leave
    # `thumb_02_l` hanging off `hand_l` for one iteration — harmless, but the
    # order makes the intent unambiguous rather than relying on that behaviour.
    for name in reversed(_fingers("l") + _fingers("r")):
        if name in edit_bones:
            edit_bones.remove(edit_bones[name])
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.context.view_layer.objects.active = human

    bones = len(armature.data.bones)
    log("fingers cut: rig is now %d bones" % bones)
    if bones != RIG_BONES_SHIPPED:
        raise AssertionError("expected %d bones after the cut, got %d"
                             % (RIG_BONES_SHIPPED, bones))


def report_weights(obj, armature, label):
    """Every vertex of the body must be driven by SOME bone, or it stays behind
    when the hero walks. Prints the five worst so a hole is nameable."""
    bone_names = {b.name for b in armature.data.bones}
    bone_group_ids = {vg.index for vg in obj.vertex_groups if vg.name in bone_names}
    totals = []
    for v in obj.data.vertices:
        totals.append(sum(g.weight for g in v.groups if g.group in bone_group_ids))
    totals_sorted = sorted(range(len(totals)), key=lambda i: totals[i])[:5]
    worst = [(i, round(totals[i], 5)) for i in totals_sorted]
    unweighted = sum(1 for t in totals if t <= 0.0)
    log("%s: %d verts, %d with ZERO bone weight, 5 lowest %s"
        % (label, len(totals), unweighted, worst))
    if unweighted:
        raise AssertionError("%d vertices carry no bone weight" % unweighted)


def bake_to_plain_mesh(obj, armature):
    """Apply the helper MASK modifier and every macro/target shape key in one go.
    TRAP 2: this also drops the armature modifier, so put it back."""
    RigService = dyn("mpfb.services.rigservice", "RigService")
    bpy.context.view_layer.objects.active = obj
    for o in bpy.data.objects:
        o.select_set(o is obj)
    bpy.ops.object.convert(target='MESH')
    obj = bpy.context.view_layer.objects.active
    has_armature = any(m.type == 'ARMATURE' for m in obj.modifiers)
    log("after convert: %d verts, armature modifier survived: %s"
        % (len(obj.data.vertices), has_armature))
    if not has_armature:
        RigService.ensure_armature_modifier(obj, armature)
        log("re-added the armature modifier (TRAP 2)")
    return obj


def decimate(obj, body_tris, head_tris):
    """TWO collapses: thin the body with the head held, then thin the head with the
    body held. Each pass's `ratio` is stated as the triangle count it aims at, so
    the two budgets are read off the constants rather than tuned.

    A ONE-PASS DIAL WAS TRIED FIRST AND DOES NOT EXIST. Blender's Decimate reads a
    vertex group as a VETO, not a weight: measured 2026-09-11 on this mesh, a
    `vertex_group_factor` of 0.3, 0.5, 0.7, 0.85 and 1.0 all preserved exactly the
    same 8,540 head triangles, because the modifier blends the factor in as
    `(1 - f) + f * w` and every weight in a BONE group is 1. So the head is either
    fully protected or not protected at all, and "not at all" is the second pass.

    The second pass protects the body and therefore cannot hit its ratio exactly —
    it runs out of head to collapse — so it undershoots the body by a percent or
    two. The asserts in `build()` read the result, not the request."""
    bpy.context.view_layer.objects.active = obj

    def counts():
        obj.data.calc_loop_triangles()
        total = len(obj.data.loop_triangles)
        return total, head_tri_count(obj)

    def collapse(want, protect_head):
        total = len(obj.data.loop_triangles)
        if want >= total:
            return
        mod = obj.modifiers.new("Decimate", 'DECIMATE')
        mod.decimate_type = 'COLLAPSE'
        mod.ratio = float(want) / float(total)
        mod.vertex_group = "head"
        mod.vertex_group_factor = 1.0
        mod.invert_vertex_group = protect_head
        bpy.ops.object.modifier_apply(modifier=mod.name)

    total, head = counts()
    log("pre-decimate: %d tris (%d head, %d body)" % (total, head, total - head))
    collapse(head + body_tris, protect_head=True)
    total, head = counts()
    log("body pass: %d tris (%d head, %d body)" % (total, head, total - head))
    collapse(head_tris + (total - head), protect_head=False)
    total, head = counts()
    log("head pass: %d tris (%d head, %d body)" % (total, head, total - head))


def reframe(obj, armature, target_height):
    """
    TRAP 4. Turn the human 180 degrees about Z (MakeHuman faces -Y, this game's
    frame faces +Y), scale it uniformly to `target_height` crown-to-heel, centre
    it on X and drop its heels to z=0 — applying the SAME matrix to the mesh data
    and to the armature data, so the bones move with the skin and both objects
    keep an identity object transform.

    Returns the matrix, so a joint centroid measured on the raw human can be
    carried into the same frame.
    """
    zs = [v.co.z for v in obj.data.vertices]
    xs = [v.co.x for v in obj.data.vertices]
    crown, heel = max(zs), min(zs)
    scale = target_height / (crown - heel)
    # Rz(180) first, then the uniform scale, then the recentre. The x centre is
    # measured pre-turn, so it is negated by the turn like every other x.
    centre_x = (min(xs) + max(xs)) / 2.0
    m = (Matrix.Translation(Vector((centre_x * scale, 0.0, -heel * scale)))
         @ Matrix.Scale(scale, 4)
         @ Matrix.Rotation(math.pi, 4, 'Z'))
    obj.data.transform(m)
    armature.data.transform(m)
    obj.data.update()
    zs2 = [v.co.z for v in obj.data.vertices]
    log("reframed: scale %.4f height %.4f (z %.4f..%.4f)"
        % (scale, max(zs2) - min(zs2), min(zs2), max(zs2)))
    return m


def apply_pose_as_rest(armature, obj, arms_down_deg):
    """
    TRAP 5. Swing both upper arms from MakeHuman's A-pose down to
    `arms_down_deg` off vertical, then bake that pose as the REST pose: apply
    the armature modifier on the skin, `pose.armature_apply()` on the bones,
    re-add the modifier.

    Done by hand rather than through `RigService.apply_pose_as_rest_pose`,
    which walks MPFB2's own basemesh/asset relations — after `convert()` and the
    beret/eye join this is a plain mesh with none of that bookkeeping left.

    The rotation is computed in ARMATURE space from the bone's own rest
    direction, so it needs no knowledge of the bone's roll: whatever axis
    `upperarm_l` happens to be built on, `rotation_difference` finds the turn
    that takes the arm from where it points to straight down. Children (forearm,
    hand, fingers) are parented and follow.

    TRAP 6, and it cost a whole rebuild and a whole re-shoot. EVERYTHING HERE IS
    READ AND WRITTEN THROUGH `armature.data`, never through `pose.bones[...].head
    / .tail / .matrix`, because `reframe()` moved the rig by transforming its
    DATA and the evaluated pose does not follow that until the depsgraph catches
    up — `view_layer.update()` does not make it. Measured: after the 180-degree
    reframe, `pose.bones["upperarm_l"].tail - .head` still read
    (+0.660, +0.005, -0.751), the PRE-turn direction, so the left arm was swung
    onto the right arm's side and the exported rest came out with both arms
    5 degrees off vertical THE SAME WAY. `data.bones[...].head_local` /
    `.tail_local` / `.matrix_local` are plain rest data and are current the
    instant `data.transform()` returns.

    So the pose is written as `matrix_basis` — the bone-local delta — by
    conjugating the wanted ARMATURE-space rotation through the bone's own rest
    basis, exactly the trick `style_shots.gd`'s `_bone_pose()` uses on the Godot
    side for the same reason (MakeHuman bones carry rolls).
    """
    RigService = dyn("mpfb.services.rigservice", "RigService")
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode='POSE')
    ang = math.radians(arms_down_deg)
    wanted = {}
    for side, sign in (("l", -1.0), ("r", 1.0)):
        bone = armature.data.bones["upperarm_" + side]
        d = (bone.tail_local - bone.head_local).normalized()
        want = Vector((sign * math.sin(ang), 0.0, -math.cos(ang)))
        wanted["upperarm_" + side] = want
        rest = bone.matrix_local.to_3x3()
        local = rest.inverted() @ d.rotation_difference(want).to_matrix() @ rest
        armature.pose.bones["upperarm_" + side].matrix_basis = local.to_4x4()
        log("upperarm_%s: A-pose %s -> want %s"
            % (side, tuple(round(v, 4) for v in d),
               tuple(round(v, 4) for v in want)))
    bpy.ops.object.mode_set(mode='OBJECT')

    bpy.context.view_layer.objects.active = obj
    for o in bpy.data.objects:
        o.select_set(o is obj)
    for mod in list(obj.modifiers):
        if mod.type == 'ARMATURE':
            bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.context.view_layer.objects.active = armature
    for o in bpy.data.objects:
        o.select_set(o is armature)
    bpy.ops.object.mode_set(mode='POSE')
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    RigService.ensure_armature_modifier(obj, armature)

    # SIGNED, and asserted on the REST data the bake just wrote — the one reading
    # that cannot be stale and the one the .glb is exported from. The first draft
    # logged `Vector.angle()`, which is unsigned, so it printed a contented
    # "5.0 deg" for both arms while one of them pointed into the hip.
    for name, want in wanted.items():
        bone = armature.data.bones[name]
        got = (bone.tail_local - bone.head_local).normalized()
        log("%s rest is now %s" % (name, tuple(round(v, 4) for v in got)))
        if (got - want).length > 1e-3:
            raise AssertionError(
                "%s rest %s is not the direction asked for %s"
                % (name, tuple(got), tuple(want)))


# ---------------------------------------------------------------------------
# Colour (spike_z3e_teibi_body.py's paint_body, on the rig's own groups)
# ---------------------------------------------------------------------------

def _group_weight(v, ids):
    return sum(g.weight for g in v.groups if g.group in ids)


def colour_regions(row):
    """The row's own region -> bones map: COLOUR_BONES with `bone_regions` applied.

    A row moves BONES, not regions, because that is how clothing actually reads —
    "the forearm is bare", "the hand is gloved" — and because a bone can only be in
    one region, which an override dict makes true by construction."""
    of_bone = {}
    for region, bones in COLOUR_BONES.items():
        for bone in bones:
            of_bone[bone] = region
    for bone, region in row.get("bone_regions", {}).items():
        if bone not in of_bone:
            raise AssertionError("bone_regions names %r, which is in no region" % bone)
        of_bone[bone] = region
    out = {}
    for bone, region in of_bone.items():
        out.setdefault(region, []).append(bone)
    missing = sorted(set(out) - set(row["colour_key"]))
    if missing:
        raise AssertionError("no colour_key entry for region(s) %s" % missing)
    return out


def _vg_ids(obj, names):
    return {vg.index for vg in obj.vertex_groups if vg.name in names}


def landmarks(obj, tj, row):
    """Every height a garment or a band is allowed to be measured from, in the
    reframed game frame, as ONE dictionary — because `dress_shells` cuts a hem at
    a height and `paint_body` colours the same hem at the same height, and two
    copies of "2 cm above the shoe" is how a seam ends up 4 mm off its own step.

    `wrist` has no joint helper behind it (MakeHuman ships none): the forearm is
    about as long as the upper arm, so it is estimated a forearm past the elbow,
    which is what `paint_body`'s cuff band has always done. `shoe_top` is measured
    off the mesh rather than off a joint — it is where the shoe REGION ends, which
    is the only thing a trouser hem can be hung on.
    """
    z = {"ground": 0.0,
         "pelvis": tj["pelvis"].z,
         "neck": tj["neck"].z,
         "knee": (tj["l-knee"].z + tj["r-knee"].z) / 2.0,
         "shoulder": (tj["l-shoulder"].z + tj["r-shoulder"].z) / 2.0,
         "eye": (tj["l-eye"].z + tj["r-eye"].z) / 2.0,
         }
    for side in ("l", "r"):
        z["wrist_" + side] = (tj["%s-elbow" % side].z
                              - (tj["%s-shoulder" % side].z
                                 - tj["%s-elbow" % side].z) * 0.85)
    z["wrist"] = (z["wrist_l"] + z["wrist_r"]) / 2.0
    shoe_ids = _vg_ids(obj, colour_regions(row)["shoes"])
    z["shoe_top"] = max((v.co.z for v in obj.data.vertices
                         if _group_weight(v, shoe_ids) > 0.5), default=0.0)
    return z


def _hem(spec, end, z):
    name, offset = spec[end]
    return z[name] + offset


# ---------------------------------------------------------------------------
# CLOTHING AS GEOMETRY — bead godot-test1-5u3.10
# ---------------------------------------------------------------------------
#
# OWNER, 2026-09-12, on `docs/style/z3e/build_hero_rest_row.png`: "not too bad,
# but what with pants, why are they so slick. Windman has shorts, teibi has
# uniform pants, prim has long jacket, как смокинг с фалдами."
#
# Everything the cast wore until this bead was PAINT: `paint_body` picks a colour
# per vertex off the bone weights and the band heights, and the vertex it paints
# is the naked MakeHuman body's own. A trouser leg is therefore exactly the shape
# of the leg inside it — no hem, no cuff, no waistband, no thickness anywhere —
# which at 3 m reads as body paint, because that is what it is.
#
# A GARMENT IS THE BODY'S OWN SURFACE, PUSHED OUT. Not a duplicated shell, and
# this is the one real decision in the bead. The obvious build — duplicate the
# region's faces, offset them, solidify, cap the boundary — doubles those faces
# and the cast has 590 triangles of headroom between the shipped Windman (13,411)
# and the budget the lane asserts. It also needs a seam policy nobody wants:
# cloth that is a separate surface z-fights the skin under it wherever the two
# curvatures disagree, and every copied vertex is a second set of four bone
# influences for the web renderer to skin. Pushing the body out instead is the
# idiom this file ALREADY ships twice — the hair lift and the shoe shell in
# `paint_body`, both "move the region's verts along their own normals" — and it
# costs nothing: the vertices are weighted already (trap 8 cannot bite), the
# surface stays one closed manifold, and the cloth cannot separate from the body
# in any pose because it IS the body.
#
# WHAT MAKES IT A HEM AND NOT A BULGE is the pair of cuts. A garment's bottom
# edge is bisected TWICE, `HEM_CUT` apart, and only the upper of the two rings is
# pushed out: the 3 mm of surface between them becomes a near-vertical wall a
# centimetre and a half tall, which is a hem with an edge on it and a shadow
# under it. Without the cuts the step lands on whatever ring the decimate left
# nearby and the hem zigzags by up to a triangle — measured on this body at ~3 cm,
# which is a ragged hem, not a straight one.
#
# WHAT IT CANNOT DO, and is not asked to: cloth that leaves the body. Folds that
# hang, a coat that swings away from the hip, a sleeve with slack in it — all of
# those need a second surface and a simulation this game does not have. The one
# garment that genuinely is not on a body — Primm's coat tails — is therefore the
# one that is new geometry (`attach_tails`). And the canon's 2-3 mm silver trim
# RIDGES stay vertex colour: at a ~3 cm vertex pitch a 3 mm ridge is a tenth of a
# triangle, which is the same measurement that made bead 5u3.6 rewrite this coat
# once already. What this bead gives them instead is a real STEP to sit on —
# the coat's carved front edge, the boot rim, the sleeve hem — so the silver is
# now paint on an edge rather than paint on a flat chest.
HEM_CUT = 0.003          # how far below a hem the second ring is cut
GARMENT_WEIGHT = 0.5     # how much of a vertex a garment's bones must hold to dress it
GARMENT_CUT = 0.25       # ... and how little is still worth cutting through
# THE PREFIX OF THE VERTEX GROUP `dress_shells` HANDS `paint_body`. A garment is
# classified ONCE, before the push, and the answer is carried in a vertex group
# because that is the only thing in this lane that survives both the push and the
# wrap — trap 1's own lesson ("vertex GROUPS survive ..., vertex INDICES do not"),
# and `dress_shells`'s docstring has the measurement that made it necessary.
# Removed again at the end of `paint_body`, so nothing but a bone ever reaches the
# exporter. Never a bone name, so `_vg_ids` / `report_weights` / `weight_strays_to`
# (all of which filter by the armature's own names) cannot see it.
GARMENT_VG = "garment:"


def _bisect_at(obj, height, ids):
    """One horizontal edge ring through the limb `ids` drives, at `height`.

    Scoped by bone weight and not by z alone, because in MakeHuman's A-pose the
    hands hang level with the hips: a plane through a trouser waistband is also a
    plane through both forearms, and the cut that gives the trousers a straight
    hem would give the coat sleeves a ring in the middle of nothing.

    The new vertices are interpolated along the edges they split, so they inherit
    the deform weights of both ends — a cut cannot make an unweighted vertex, and
    `report_weights()` after the bake is what says so.
    """
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    deform = bm.verts.layers.deform.verify()

    def held(v):
        return sum(w for g, w in v[deform].items() if g in ids)

    geom = set()
    for f in bm.faces:
        if any(held(v) > GARMENT_CUT for v in f.verts):
            geom.add(f)
            geom.update(f.verts)
            geom.update(f.edges)
    before = len(bm.verts)
    if geom:
        bmesh.ops.bisect_plane(bm, geom=list(geom), dist=1e-5,
                               plane_co=(0.0, 0.0, height),
                               plane_no=(0.0, 0.0, 1.0))
    added = len(bm.verts) - before
    bm.to_mesh(me)
    bm.free()
    me.update()
    return added


def _garment_verts(me, spec, ids, z):
    """The vertices of one garment: in its bone scope, between its two hems, and
    not carved out of it. Returns (dressed, bare) — `bare` is everything in the
    scope BELOW the hem, which is what a row's `below` key repaints (Windman's
    thigh under the shorts, which the `trousers` bone region would otherwise paint
    brown all the way to the boot)."""
    low = _hem(spec, "bottom", z)
    high = _hem(spec, "top", z)
    carve = spec.get("carve")
    dressed, bare = [], []
    for i, v in enumerate(me.vertices):
        if v.co.z > high or _group_weight(v, ids) <= GARMENT_WEIGHT:
            continue
        if v.co.z < low - 1e-6:
            bare.append(i)
        elif not (carve and carve(v, z)):
            dressed.append(i)
    return dressed, bare


def dress_shells(obj, tj, row):
    """THE GARMENTS, AS GEOMETRY. Cut every hem, then push every garment out.

    Two passes and not one, because a bisect renumbers and re-indexes the mesh:
    all the cutting happens first, the vertex set each garment claims is read off
    the mesh that comes out of it, and the push is applied ONCE per vertex at the
    deepest garment claiming it (`max`, not a sum — Teibi's waistband lies inside
    his trousers, and adding the two would stand it 3 cm off his hip).

    AND THE CLASSIFICATION IS DONE HERE, ONCE, FOR BOTH HALVES OF A GARMENT. The
    first build of this bead let `paint_body` re-run `_garment_verts` for the
    colour, which is the same question asked of a mesh that has since MOVED: every
    vertex within one lift of a hem answers the z test differently after the push,
    so the cloth colour stopped one ring short of the cloth geometry. Measured on
    that build — Windman's cap sleeve lost 50 of its 256 vertices to `skin` and
    his shorts hem 33 more, i.e. a pale fringe of bare leg on exactly the two
    edges this bead exists to create; Teibi and Primm were saved only by their
    fallback argmax landing on the same palette key. So the answer is written into
    `GARMENT_VG` vertex groups and `paint_body` reads those.

    Runs after `densify_chest` and BEFORE `wrap_band` — see trap 9. Both of those
    change polygon indices and the wrap hands `export_glb` a set of them. The
    groups are how the answer crosses the wrap, which renumbers vertices too.

    ONLY BOTTOM EDGES ARE CUT. A garment's top is either under a prouder garment
    (the constants' own ordering rule) or over a bone the scope excludes, so it
    never shows a hem; the day a row needs a visible top edge it needs its own
    pair of cuts here.
    """
    garments = row.get("garments", ())
    if not garments:
        return
    z = landmarks(obj, tj, row)
    added = cuts = 0
    for spec in garments:
        ids = _vg_ids(obj, spec["bones"])
        hem = _hem(spec, "bottom", z)
        # A hem ON the floor is the sole of a boot, which has no edge to cut and
        # no body below it (Primm's shaft bottoms out at z = 0): the pair of rings
        # would be two rows of vertices spent on nothing.
        if hem <= HEM_CUT:
            continue
        added += _bisect_at(obj, hem, ids)
        added += _bisect_at(obj, hem - HEM_CUT, ids)
        cuts += 2
    me = obj.data
    lift = [0.0] * len(me.vertices)
    worn = {}
    for spec in garments:
        ids = _vg_ids(obj, spec["bones"])
        dressed, bare = _garment_verts(me, spec, ids, z)
        for i in dressed:
            worn[i] = spec["key"]
        if "below" in spec:
            for i in bare:
                worn[i] = spec["below"]
        if not dressed:
            raise AssertionError(
                "the %r garment dressed no vertex — its hems (%.3f..%.3f) are not "
                "over the bones it names" % (spec["key"], _hem(spec, "bottom", z),
                                             _hem(spec, "top", z)))
        # THE HEM IS PROUDER THAN THE WAIST, and that is the whole difference
        # between a trouser leg and a pair of tights. The body inside narrows from
        # the thigh to the ankle and a constant offset narrows with it — the first
        # build of this bead came out in leggings 1.2 cm thick (`docs/style/z3e/
        # grid_26_clothing.png`, the middle column). A "straight cut" is the cloth
        # NOT following the leg in, so `flare` is what the shell stands proud at
        # the hem and `proud` what it stands at the top, ramped linearly between.
        # Linear, and not a fit to the leg's own radius: a real straight cut would
        # push every vertex out to a cylinder around the limb's axis, which needs
        # a per-leg axis and a per-hero radius — this reads right at 3 m for six
        # lines, and the knee is the place it does not (it stays a knee).
        low, high = _hem(spec, "bottom", z), _hem(spec, "top", z)
        proud, flare = spec["cut"]
        for i in dressed:
            t = 0.0 if high <= low else min(1.0, max(
                0.0, (high - me.vertices[i].co.z) / (high - low)))
            lift[i] = max(lift[i], proud + (flare - proud) * t)
        log("garment %-9s %-9s %.3f..%.3f m, %d verts, %.0f mm proud, %.0f at the hem"
            % (spec["key"], spec["bones"][0], low, high, len(dressed),
               proud * 1000.0, flare * 1000.0))
    by_key = {}
    for i, key in worn.items():
        by_key.setdefault(key, []).append(i)
    for key, ids in sorted(by_key.items()):
        obj.vertex_groups.new(name=GARMENT_VG + key).add(ids, 1.0, 'REPLACE')
    normals = [v.normal.copy() for v in me.vertices]
    for i, proud in enumerate(lift):
        if proud > 0.0:
            me.vertices[i].co += normals[i] * proud
    me.update()
    log("dressed: %d hem cut(s) added %d verts, %d of %d verts pushed out, "
        "worn: %s" % (cuts, added, sum(1 for p in lift if p > 0.0), len(lift),
                      {k: len(v) for k, v in sorted(by_key.items())}))


# ===========================================================================
# THE CLOTH SPIKE — bead godot-test1-td8, and NOTHING BELOW THIS COMMENT RUNS
# ON THE SHIPPED PATH. Owner, 2026-09-12: "shirts and clothing look painted, not
# natural — just colour on the heroes." After bead 5u3.10 the garments have
# VOLUME (`dress_shells` stands them proud of the skin, with a cut hem) but the
# surface between the hems is one flat vertex colour under a two-band
# DIFFUSE_TOON, which is exactly what "painted on" describes.
#
# A COLUMN IS A SET OF PASSES, reached with `--variant <name>`, and it writes a
# SCRATCH .glb beside the shipped one (`teibi_cloth_<name>.glb`) that no scene
# loads and no manifest row covers. `--all --check` is therefore untouched: the
# shipped bytes are written by exactly the code that wrote them before, because
# every pass here is gated on a variant nobody passes by default.
#
#   folds     COLUMN A — the crease bands, the hem gathers and the drape line,
#             as displacement along the garment's own normals (`fold_garments`).
#   bake      COLUMN B — occlusion and cavity multiplied into the garment's
#             vertex colours (`bake_cloth_shading`).
#   material  COLUMN D — the garments get their own material, which
#             `toon_shading.gd` then shades as CLOTH and not as cast
#             (`split_cloth_material`).
#   (C)       the 512^2 fabric albedo on unwrapped shells: NOT BUILT — see the
#             FINDINGS block on the bead. It is the one column that needs a UV
#             layout, a bake target and the lane's first texture byte, and this
#             spike's clock ran out before it; nothing here fakes it.
CLOTH_VARIANTS = {
    "a": ("folds",),
    "b": ("bake",),
    "d": ("material",),
    "all": ("folds", "bake", "material"),
}

# Amplitudes, in metres, on a 1.78 m body. The bead asks for 4-8 mm creases and
# a 3 mm hem gather; these are the middle of that, because a fold deeper than the
# shell stands proud (12-24 mm, the `GARMENT_*` cuts) would push the cloth back
# through the skin it is standing off.
FOLD_CREASE = 0.006      # crease depth at a joint
FOLD_GATHER = 0.003      # the radial ripple at a hem or a cuff
FOLD_DRAPE = 0.002       # the shoulder-to-hem drape line
FOLD_BAND = 0.075        # how far up and down a joint's crease band reaches
FOLD_WAVE = 0.042        # metres per crease — 3-4 of them inside a band
FOLD_GATHERS = 9         # ripples around a hem
FOLD_DRAPES = 3          # drape lines around the body


def _fold_bands(obj, tj, row):
    """The heights a crease sits at, and the heights a gather does.

    The bead asks for the crease to be "driven by a bone weight blend between the
    two bones so they sit at the joint". A BAND IN Z IS THAT BLEND, evaluated in
    the rest pose where the two are the same answer: the joint helper's own height
    is where the weight hands over, and a gaussian around it is the hand-over
    profile. It costs no per-vertex weight lookup and — this is the part that
    matters for a mesh that has to keep deforming — it is baked into the REST
    geometry, so the folds ride the skin cluster they sit on and a bent elbow
    carries its creases with it (what the stride strip is for).
    """
    z = landmarks(obj, tj, row)
    elbow = (tj["l-elbow"].z + tj["r-elbow"].z) / 2.0
    creases = [z["knee"], elbow, z["shoulder"] - 0.055]      # knee, elbow, armpit
    gathers = [z["pelvis"] + 0.055, z["wrist"] - 0.02, z["shoe_top"] + 0.01]
    return creases, gathers, z


def _fold_offset(co, creases, gathers, z):
    """How far proud of the shell one garment vertex stands. A pure function of
    the rest position, so it is the same answer on every rebuild."""
    out = 0.0
    for zc in creases:
        t = (co.z - zc) / FOLD_BAND
        if abs(t) < 2.0:
            out += FOLD_CREASE * math.exp(-t * t) * math.sin(
                (co.z - zc) / FOLD_WAVE * math.tau)
    bearing = math.atan2(co.y, co.x)
    for zh in gathers:
        t = (co.z - zh) / 0.030
        if abs(t) < 2.0:
            out += FOLD_GATHER * math.exp(-t * t) * math.sin(bearing * FOLD_GATHERS)
    # The drape: one soft vertical ripple hanging from the shoulder to the hem,
    # the thing that makes a shirt read as hanging rather than as shrink-wrap.
    span = z["shoulder"] - z["pelvis"]
    if span > 0.0:
        ramp = min(1.0, max(0.0, (z["shoulder"] - co.z) / span))
        out += FOLD_DRAPE * ramp * math.sin(bearing * FOLD_DRAPES)
    return out


# THE SPIKE'S OWN COPY OF `dress_shells`'s ANSWER, and the reason it exists:
# `paint_body` DELETES every `GARMENT_VG` group when it is done with it (its own
# rule — "nothing but a bone ever reaches the exporter"), and two of the three
# columns here run AFTER the paint. So the cloth is marked ONCE, under a prefix
# `paint_body` does not sweep, and dropped again just before the export — the
# same trap-1 lesson every other pass in this file pays: a vertex GROUP survives
# what a vertex INDEX does not, joins and renumbering included.
CLOTH_VG = "cloth:spike"


def mark_cloth(obj):
    """Copy the garment classification into a group that outlives `paint_body`."""
    ids = {vg.index for vg in obj.vertex_groups if vg.name.startswith(GARMENT_VG)}
    if not ids:
        raise AssertionError("mark_cloth: no %s groups — dress_shells must run first"
                             % GARMENT_VG)
    worn = [i for i, v in enumerate(obj.data.vertices) if ids & {g.group for g in v.groups}]
    obj.vertex_groups.new(name=CLOTH_VG).add(worn, 1.0, 'REPLACE')
    log("cloth: marked %d of %d verts as garment" % (len(worn), len(obj.data.vertices)))


def drop_cloth_mark(obj):
    vg = obj.vertex_groups.get(CLOTH_VG)
    if vg is not None:
        obj.vertex_groups.remove(vg)


def _garment_group_ids(obj):
    return {vg.index for vg in obj.vertex_groups
            if vg.name.startswith(GARMENT_VG) or vg.name == CLOTH_VG}


def _is_garment(v, ids):
    return bool(ids & {g.group for g in v.groups})


def fold_garments(obj, tj, row):
    """COLUMN A — FOLDS AS GEOMETRY.

    Two steps, in the order `dress_shells` already taught this lane: SUBDIVIDE
    first (a 42 mm crease needs a vertex every ~20 mm and the decimated body has
    one every ~30 mm), then displace along the vertex normal.

    THE SUBDIVIDE IS BAND-LIMITED and that is a budget decision, not a taste one:
    the shipped Teibi is 13,872 tris against a 15,500 `TRI_BUDGET`, so
    subdividing the whole garment (which is most of the body) would be a 3x
    overrun. Only edges whose both ends are garment AND whose midpoint falls
    inside a crease or gather band are cut, which is where the folds are and
    nowhere else.

    Runs BEFORE `wrap_band` (trap 9 — it adds geometry and renumbers polygons)
    and before `paint_body`, whose classification reads the vertex GROUPS the
    subdivide interpolates onto the new vertices.
    """
    ids = _garment_group_ids(obj)
    if not ids:
        raise AssertionError("fold_garments: no %s groups — dress_shells must run first"
                             % GARMENT_VG)
    creases, gathers, z = _fold_bands(obj, tj, row)
    band_zs = [(zc, FOLD_BAND * 1.4) for zc in creases] + \
              [(zh, 0.045) for zh in gathers]

    def in_band(zv):
        return any(abs(zv - zc) < w for zc, w in band_zs)

    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    deform = bm.verts.layers.deform.verify()
    edges = [e for e in bm.edges
             if all(ids & set(v[deform].keys()) for v in e.verts)
             and in_band((e.verts[0].co.z + e.verts[1].co.z) / 2.0)]
    before_v, before_f = len(bm.verts), len(bm.faces)
    if edges:
        bmesh.ops.subdivide_edges(bm, edges=edges, cuts=1, use_grid_fill=True)
    bm.to_mesh(me)
    bm.free()
    me.update()
    log("folds: subdivided %d banded garment edges, +%d verts, +%d faces"
        % (len(edges), len(me.vertices) - before_v, len(me.polygons) - before_f))

    # The normals are read ONCE, off the un-displaced mesh — displacing along a
    # normal that is itself being displaced turns a fold into a spiral.
    normals = [v.normal.copy() for v in me.vertices]
    moved = 0
    deepest = 0.0
    for i, v in enumerate(me.vertices):
        if not _is_garment(v, ids):
            continue
        d = _fold_offset(v.co, creases, gathers, z)
        if d != 0.0:
            v.co += normals[i] * d
            moved += 1
            deepest = max(deepest, abs(d))
    me.update()
    log("folds: displaced %d garment verts, deepest %.1f mm" % (moved, deepest * 1000.0))


# How many rays a vertex casts into its own hemisphere for the occlusion term,
# and how far one reaches. 24 rays at 12 cm is the cheapest pair that separated a
# fold valley from its flat panel by more than the vertex-colour quantisation.
AO_RAYS = 24
AO_DIST = 0.12
AO_FLOOR = 0.45          # how dark the deepest occlusion may take a vertex
CAVITY_GAIN = 0.9        # how hard concave curvature darkens on top of the occlusion
CAVITY_FLOOR = 0.70
AO_SEED = 20260912


def bake_cloth_shading(obj):
    """COLUMN B — OCCLUSION AND CAVITY, MULTIPLIED INTO THE GARMENT'S VERTEX COLOURS.

    Zero extra geometry, zero extra bytes: the colour attribute already ships, and
    this only changes what is in it. Under a two-band DIFFUSE_TOON — which cannot
    itself show a 6 mm crease, its second band being a lighting threshold and not
    a depth cue — a darkened valley is the ONLY thing that reads as depth.

    IT IS NOT `bpy.ops.object.bake`, and that is deliberate. Cycles' AO bake
    answers the same question, but it needs a render engine, a bake target and
    (for the pointiness half) a material graph, while the answer here is worth
    exactly two loops: occlusion is the fraction of a cosine-weighted hemisphere
    that hits the body's own BVH, and cavity is the mean signed distance of a
    vertex's one-ring along its normal, which is Blender's "pointiness" by its
    definition. Both are pure functions of the mesh and the ray set is drawn off a
    FIXED seed, so the bake is deterministic and a rebuild reproduces the bytes —
    which a sampled Cycles bake would not.
    """
    from mathutils.bvhtree import BVHTree
    import random
    me = obj.data
    ids = _garment_group_ids(obj)
    layer = me.color_attributes.active_color
    if layer is None:
        raise AssertionError("bake_cloth_shading: the body carries no colour attribute")
    tree = BVHTree.FromPolygons([tuple(v.co) for v in me.vertices],
                                [tuple(p.vertices) for p in me.polygons])

    # The cosine-weighted hemisphere, generated ONCE off a fixed seed and
    # re-oriented per vertex: a shared ray set makes the bake reproducible and
    # costs one basis per vertex instead of one sampler.
    rng = random.Random(AO_SEED)
    disc = []
    for _ in range(AO_RAYS):
        u, w = rng.random(), rng.random()
        r = math.sqrt(u)
        a = w * math.tau
        disc.append((r * math.cos(a), r * math.sin(a), math.sqrt(max(0.0, 1.0 - u))))

    # Cavity: the mean of (neighbour - v) . normal over the one-ring, and MIND THE
    # SIGN — the first build of this bead had it backwards and darkened every
    # ridge while leaving the creases alone. With outward normals a neighbour of a
    # CONVEX vertex sits BELOW the tangent plane and the dot is NEGATIVE (check it
    # on a unit sphere: n = v = (0,0,1), a neighbour at polar angle t is
    # (sin t, 0, cos t) and the dot is cos t - 1 < 0). A CONCAVE vertex — a crease
    # valley, an armpit, the groove under a waistband, which is everything this
    # pass exists for — has its neighbours on the normal side, so the dot is
    # POSITIVE. Darken the positive half.
    ring = [[] for _ in me.vertices]
    for e in me.edges:
        a, b = e.vertices
        ring[a].append(b)
        ring[b].append(a)

    dark = [1.0] * len(me.vertices)
    lit = []
    for i, v in enumerate(me.vertices):
        if not _is_garment(v, ids):
            continue
        n = v.normal
        # A basis with `n` as +Z, so the disc above lands on this vertex's own
        # hemisphere. `orthogonal()` is degenerate for nothing a mesh normal is.
        t = n.orthogonal().normalized()
        b = n.cross(t)
        origin = v.co + n * 1e-4
        hits = 0
        for dx, dy, dz in disc:
            if tree.ray_cast(origin, t * dx + b * dy + n * dz, AO_DIST)[0] is not None:
                hits += 1
        ao = 1.0 - (1.0 - AO_FLOOR) * (hits / float(AO_RAYS))
        if ring[i]:
            curv = sum((me.vertices[j].co - v.co).normalized().dot(n)
                       for j in ring[i]) / len(ring[i])
        else:
            curv = 0.0
        cav = 1.0 - max(0.0, curv) * CAVITY_GAIN
        dark[i] = max(CAVITY_FLOOR * AO_FLOOR, ao * max(CAVITY_FLOOR, cav))
        lit.append(dark[i])

    if not lit:
        raise AssertionError("bake_cloth_shading: no garment vertex was shaded")
    # The colour attribute may be per-CORNER (MPFB2's is): write through the loops,
    # each of which knows the vertex it belongs to.
    if layer.domain == 'CORNER':
        for loop in me.loops:
            c = layer.data[loop.index].color
            d = dark[loop.vertex_index]
            layer.data[loop.index].color = (c[0] * d, c[1] * d, c[2] * d, c[3])
    else:
        for i in range(len(me.vertices)):
            c = layer.data[i].color
            d = dark[i]
            layer.data[i].color = (c[0] * d, c[1] * d, c[2] * d, c[3])
    lit.sort()
    log("bake: %d garment verts shaded, darkening min %.3f, median %.3f, max %.3f"
        % (len(lit), lit[0], lit[len(lit) // 2], lit[-1]))


# The marker `scripts/toon_shading.gd` matches on. A shipped hero .glb carries NO
# material at all (`export_materials='NONE'`), so this name never appears on the
# shipped path and the Godot-side branch is a no-op there BY CONSTRUCTION.
CLOTH_MATERIAL = "HeroCloth"
SKIN_MATERIAL = "HeroSkin"


def split_cloth_material(obj):
    """COLUMN D — THE GARMENTS GET THEIR OWN MATERIAL.

    Two slots, split on the same `GARMENT_VG` groups every other pass uses: a
    polygon is cloth when every one of its vertices is. The materials are plain
    white with the vertex colours doing the albedo, exactly as the shipped hero's
    single default material does — the whole difference is the NAME, which is what
    `ToonShading.apply_to_mesh` reads to give the cloth DIFFUSE_BURLEY and no rim
    while the skin and the face keep the cast's DIFFUSE_TOON.

    This is the column that may violate the y1o.22 ruling (the cast stays
    DIFFUSE_TOON). The bead does not ship it; the owner rules from the picture.
    """
    me = obj.data
    ids = _garment_group_ids(obj)
    me.materials.clear()
    for name in (SKIN_MATERIAL, CLOTH_MATERIAL):
        # THE DATABLOCK MUST BE REMOVED FIRST, and this is `build()`'s own
        # `base.001` trap one level down: `clear_scene()` unlinks OBJECTS and
        # leaves material datablocks in `bpy.data`, so in a multi-variant session
        # (`--variant d --variant all`, which is the documented rebuild command)
        # the second `new()` would be handed `HeroCloth.001` — a name
        # `toon_shading.gd` compares with exact equality and therefore MISSES,
        # silently shading the garment as cast. Measured: it is what the first
        # build of this bead shipped, and it made the `all` column an A+B column
        # wearing a D label.
        old = bpy.data.materials.get(name)
        if old is not None:
            bpy.data.materials.remove(old)
        mat = bpy.data.materials.new(name=name)
        if mat.name != name:
            raise AssertionError("material came out as %r, not %r — a datablock of "
                                 "that name survived" % (mat.name, name))
        # PLAIN WHITE, AND THAT IS THE CONTROL, not a detail. Blender's default
        # Principled BSDF is 0.8 GREY at roughness 0.5 and the exporter writes both
        # into the glTF, while the control column exports NO material and gets
        # Godot's importer default (white, roughness 1.0, back faces culled). Left
        # at the defaults this column would differ from the control in four ways at
        # once — the name, a 0.8 albedo multiply over the whole body, the roughness
        # and double-sidedness — and only the first of those is its thesis. The
        # first build of this bead did exactly that and the 0.8 is what darkened
        # Teibi's skin.
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        if bsdf is None:
            raise AssertionError("no Principled BSDF on %r to neutralise" % name)
        bsdf.inputs["Base Color"].default_value = (1.0, 1.0, 1.0, 1.0)
        bsdf.inputs["Roughness"].default_value = 1.0
        mat.use_backface_culling = True
        me.materials.append(mat)
    cloth_v = {i for i, v in enumerate(me.vertices) if _is_garment(v, ids)}
    n = 0
    for p in me.polygons:
        if all(i in cloth_v for i in p.vertices):
            p.material_index = 1
            n += 1
    me.update()
    # THE NAMES ARE READ BACK OFF THE DATABLOCKS, never printed from the
    # constants: a log that echoes what was ASKED FOR is exactly what hid the
    # `HeroCloth.001` suffix above — the build said `HeroCloth` while the file got
    # something else.
    log("material: %d of %d polys on %r, the rest on %r"
        % (n, len(me.polygons), me.materials[1].name, me.materials[0].name))


def paint_body(obj, tj, row, band_verts=frozenset()):
    """Base region colour by bone-weight argmax, then geometric BAND overrides
    (belt, cuff, collar) scoped by bone region, then the face detail.

    `band_verts` is `wrap_band`'s cloth, if the row wears any: those vertices skip
    the skin entirely and take the row's `stripes` top-down, exactly as the spike's
    own `paint()` does — this is the same face recipe, run on a whole human."""
    colours = dict(row["colours"])
    for key in GRADED_COLOURS:
        colours[key] = graded(colours[key])
    colours["lips"] = lip_colour(colours["skin"])
    colour_key = row["colour_key"]
    bands = set(row.get("bands", ()))
    stripes = row.get("stripes", ())
    hair = row["hair"]
    for j, (_low, _high, colour) in enumerate(stripes):
        colours[j] = colour
    if stripes:
        colours["seam"] = tuple(c * SEAM_DARKEN
                                for c in stripes[-1][2][:3]) + (1.0,)
    me = obj.data
    name_to_id = {vg.name: vg.index for vg in obj.vertex_groups}

    def ids(bones):
        return {name_to_id[b] for b in bones if b in name_to_id}

    region_ids = {r: ids(bones) for r, bones in colour_regions(row).items()}
    scope_ids = {r: ids(bones) for r, bones in REGION_BONES.items()}

    z = landmarks(obj, tj, row)
    pelvis_z = z["pelvis"]
    neck_z = z["neck"]
    eye_z = z["eye"]
    wrist_z = {s: z["wrist_" + s] for s in ("l", "r")}

    # THE GARMENTS' OWN COLOUR (bead godot-test1-5u3.10), read off the vertex
    # groups `dress_shells` wrote when it classified them — NOT re-derived here,
    # because by now the mesh has moved and the same z test answers differently
    # (that docstring has the measurement). It replaces the bone-region argmax
    # where it speaks — which is how a sleeve can cover the top third of a bone
    # the row put in another region (Windman's cap sleeve over his bare
    # `upperarm`), and how `below` puts skin back under a hem (his thigh below the
    # shorts). Everything after this — the belt/cuff/collar bands and the row's
    # own `dressing` — still has the last word.
    garment_of_group = {vg.index: vg.name[len(GARMENT_VG):]
                        for vg in obj.vertex_groups
                        if vg.name.startswith(GARMENT_VG)}

    # A ROW MAY DRESS ITSELF FURTHER (bead godot-test1-5u3.6). The three bands
    # above are the ones every generator in this game wore; a garment that is ONE
    # hero's — Primm's open lab coat — belongs to that hero's own callable rather
    # than to this chain, which would otherwise grow a clause per hero.
    dressing = row.get("dressing")
    ctx = {"me": me, "key": colour_key, "region": region_ids, "scope": scope_ids,
           "pelvis_z": pelvis_z, "neck_z": neck_z, "wrist_z": wrist_z}

    per_vert = [None] * len(me.vertices)
    for i, v in enumerate(me.vertices):
        region = max(region_ids, key=lambda r: _group_weight(v, region_ids[r]))
        worn = next((garment_of_group[g.group] for g in v.groups
                     if g.group in garment_of_group), None)
        key = colour_key[region if worn is None else worn]

        in_torso = _group_weight(v, scope_ids["torso"]) > 0.4
        if "belt" in bands and in_torso and abs(v.co.z - pelvis_z) <= 0.025:
            key = colour_key["belt"]
            if v.co.y > 0.06 and abs(v.co.x) < 0.05:
                key = colour_key["belt_buckle"]
        elif "cuff" in bands and any(
                _group_weight(v, scope_ids["lowerarm_" + s]) > 0.4
                and abs(v.co.z - wrist_z[s]) <= 0.02 for s in ("l", "r")):
            key = colour_key["cuff"]
        elif ("collar" in bands and in_torso
              and neck_z - 0.03 <= v.co.z <= neck_z + 0.015):
            key = colour_key["collar"]
        per_vert[i] = dressing(v, key, in_torso, ctx) if dressing else key

    # THE HEAD REGION: eyewear, lips, eyebrows, hair — the head spike's own
    # `paint()`, position-relative-to-the-eye-line rather than by skinning weight.
    head_ids = scope_ids["head"]
    # THE MOUTH IS MAKEHUMAN'S OWN GROUP (bead godot-test1-394) — see the `LIP_*`
    # banner for what it replaced and why. `ids` has it already: `name_to_id` is
    # every vertex group on the object, bone or not.
    lip_ids = ids([LIPS_VG])
    if not lip_ids:
        raise AssertionError("no %r vertex group on the baked mesh — MPFB2's "
                             "`extra_vertex_groups` is how it gets here (see "
                             "`build_human`), and without it there is no mouth"
                             % LIPS_VG)
    hair_front = eye_z + hair["front"]
    seam_z = eye_z + stripes[0][0] if stripes else 0.0
    # THE SKULL, NOT THE ASSEMBLY. `depth` is measured against this and `band_verts`
    # has to come out of it: the cloth stands `thickness` proud of the head and
    # `wrap_band`'s two KNOT boxes sit at the arc ends, ~9.4 cm off centre against a
    # ~7.5 cm skull — and the knots carry head weight 1.0, because `weight_strays_to`
    # put it there. (Bead 394 removed the `x` half of this with the lip band's width
    # bound; the group needs no frame.)
    half_depth = max((abs(v.co.y) for i, v in enumerate(me.vertices)
                      if i not in band_verts and _group_weight(v, head_ids) > 0.4),
                     default=1e-6)
    # THE CHIN, MEASURED (bead godot-test1-394): the lowest vertex on the FRONT of
    # the face. `CHIN_CLEAR` below is the assert that no lip vertex comes near it.
    # (Both `default`s here and at `lip_low` below are unreachable: an empty head or
    # an empty face front empties the lip count too, and `LIP_VERTS_MIN` fires first.)
    chin_z = min((v.co.z for i, v in enumerate(me.vertices)
                  if i not in band_verts and _group_weight(v, head_ids) > 0.4
                  and v.co.y / half_depth > FACE_FRONT), default=0.0)
    for i, v in enumerate(me.vertices):
        if i in band_verts:
            # The cloth, top-down and clamped at both ends: the lift and the knots
            # put wrap outside the stripe range it was cut from.
            if abs(v.co.z - seam_z) <= SEAM_HALF:
                per_vert[i] = "seam"
            else:
                per_vert[i] = next((j for j, (low, _h, _c) in enumerate(stripes)
                                    if v.co.z >= eye_z + low), len(stripes) - 1)
            continue
        if _group_weight(v, head_ids) <= 0.4:
            continue
        depth = v.co.y / half_depth
        hair_z = hair_front - hair["nape"] * max(0.0, -depth)
        if v.co.z >= hair_z:
            per_vert[i] = "hair"
        elif not band_verts and any(eye_z + low <= v.co.z <= eye_z + high
                                    for low, high, _c in stripes):
            # Eyewear painted on the skin (Primm's goggles); first match wins.
            per_vert[i] = next(j for j, (low, high, _c) in enumerate(stripes)
                               if eye_z + low <= v.co.z <= eye_z + high)
        elif _group_weight(v, lip_ids) > LIP_WEIGHT:
            per_vert[i] = "lips"
        elif (hair["brows"] and eye_z + 0.028 <= v.co.z <= eye_z + 0.040
              and depth > 0.45):
            per_vert[i] = "hair"   # eyebrows, above the eye line

    counts = {}
    for k in per_vert:
        counts[k] = counts.get(k, 0) + 1
    log("paint counts:", counts)
    # AND THE MOUTH HAS TO STILL BE THERE. `lips` is a basemesh group and the head
    # is decimated to a tenth of the basemesh's face, so `LIP_WEIGHT` is a threshold
    # somebody may raise. If it selects nothing the hero ships with no mouth and
    # NOTHING DOWNSTREAM CAN SEE IT: no vertex is added or removed, so the tri
    # count, the bone count and the .glb byte size are all unchanged, `--check`
    # matches and `build.yml`'s `stat` gate stays green. Same shape as the "the face
    # melted" floor in `build()`, and for the same reason.
    if counts.get("lips", 0) < LIP_VERTS_MIN:
        raise AssertionError("the mouth vanished: %d lip vertices, floor %d — the "
                             "%r group selected (almost) nothing"
                             % (counts.get("lips", 0), LIP_VERTS_MIN, LIPS_VG))
    # AND IT HAS TO STILL BE A MOUTH AND NOT A BEARD (bead godot-test1-394): the
    # same guard from the other side, because a selection that lands on the chin is
    # exactly as invisible downstream as one that lands nowhere, and that is how the
    # beard shipped three times. A group cannot drift the way the old z band did,
    # but the decimate and `LIP_WEIGHT` between them decide which vertices carry it.
    lip_low = min((v.co.z for i, v in enumerate(me.vertices)
                   if per_vert[i] == "lips"), default=chin_z + CHIN_CLEAR)
    log("mouth: %d verts, lowest %.4f, chin %.4f, clearance %.1f mm"
        % (counts.get("lips", 0), lip_low, chin_z, (lip_low - chin_z) * 1000.0))
    if lip_low - chin_z < CHIN_CLEAR:
        raise AssertionError("the lips reach the chin: lowest lip vertex %.4f is "
                             "%.1f mm above the chin at %.4f, floor %.1f mm"
                             % (lip_low, (lip_low - chin_z) * 1000.0, chin_z,
                                CHIN_CLEAR * 1000.0))

    attr = me.color_attributes.new(name="Color", type='FLOAT_COLOR', domain='POINT')
    for i, key in enumerate(per_vert):
        attr.data[i].color = colours[key]
    me.color_attributes.active_color = attr
    me.attributes.active_color = attr

    # The hair shell — lift along the vertex normal, tapered at the hairline.
    me.calc_loop_triangles()
    normals = [v.normal.copy() for v in me.vertices]
    for i, v in enumerate(me.vertices):
        if per_vert[i] != "hair" or _group_weight(v, head_ids) <= 0.4:
            continue
        taper = min(1.0, (v.co.z - (hair_front - 0.05)) / 0.04)
        v.co += normals[i] * (hair["lift"] * max(0.0, taper))

    # The shoe shell — same lift, no taper (a shoe has a rim, hair does not),
    # and the sole clamped back onto the ground.
    shoe_key = colour_key["shoes"]
    for i, v in enumerate(me.vertices):
        if per_vert[i] != shoe_key:
            continue
        v.co += normals[i] * SHOE_LIFT
        v.co.z = max(v.co.z, 0.0)
    me.update()

    # `dress_shells`'s hand-off, spent. The exporter must see bone groups and
    # nothing else, and this is the last reader.
    for vg in [g for g in obj.vertex_groups if g.name.startswith(GARMENT_VG)]:
        obj.vertex_groups.remove(vg)


def _glyph_distance(spec, co, origin_z):
    """Distance from a point on the body to the emblem's centre-line, measured in
    the chest plane (x across, z up — the glyph has no depth and wraps onto
    whatever curve the chest has)."""
    p = Vector((co.x, 0.0, co.z - origin_z))
    best = 1e9
    pts = [Vector((x, 0.0, z)) for x, z in spec["points"]]
    for a, b in zip(pts, pts[1:]):
        ab = b - a
        t = min(1.0, max(0.0, (p - a).dot(ab) / ab.length_squared))
        best = min(best, (p - (a + ab * t)).length)
    return best


def densify_chest(obj, tj, row):
    """ONE SUBDIVISION UNDER THE EMBLEM (bead godot-test1-5u3.5, Windman only).

    The first build of the vertex "W" came out a white BLOB: painted at the
    body's own 24 mm triangle pitch, the letter's two notches are barely one
    triangle wide, and Gouraud fills them in from the corners either side. The
    stroke cannot get thinner (a 32 mm stroke at that pitch breaks into dots) and
    the letter cannot get wider (it already spans the shirt), so the pitch is what
    has to move — for this chest, and for nothing else.

    So this splits ONLY the front-facing triangles under the glyph, once: ~12 mm
    there, four to five vertices across every arm of the W and three across every
    notch, for a few hundred triangles inside `TRI_BUDGET`. The alternative the
    bead offered — `body_albedo` — buys a crisper edge for the lane's first UV
    unwrap, its first 512^2 bake and its first texture bytes, on a letter no
    camera in this game reads closer than 3 m; the owner's ruling puts vertex
    colours first and a texture only where a motif NEEDS one, and this one does
    not.

    RUNS BEFORE `wrap_band`, and that ordering is load-bearing: the wrap hands
    `export_glb` a set of POLYGON INDICES for its flat rims, and subdividing
    renumbers every polygon in the mesh. Before the wrap there is nothing yet to
    invalidate. (`build()` keeps the order; `export_glb`'s docstring is the other
    half of this rule.)
    """
    spec = row["emblem"]
    origin_z = tj["neck"].z - spec["drop"]
    # A margin past the stroke, so the finer pitch reaches the notches and the
    # outer edge rather than stopping exactly on the letter.
    reach = spec["stroke"] + 0.025
    me = obj.data
    bpy.context.view_layer.objects.active = obj
    for o in bpy.data.objects:
        o.select_set(o is obj)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_mode(type='FACE')
    bpy.ops.mesh.select_all(action='DESELECT')
    bpy.ops.object.mode_set(mode='OBJECT')
    picked = 0
    for poly in me.polygons:
        want = (poly.normal.y > 0.3
                and _glyph_distance(spec, poly.center, origin_z) <= reach)
        poly.select = want
        picked += int(want)
    before = len(me.polygons)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.subdivide(number_cuts=1)
    bpy.ops.object.mode_set(mode='OBJECT')
    log("chest densify: %d of %d faces split, %d -> %d tris"
        % (picked, before, before, len(me.polygons)))
    if picked < spec["min_faces"]:
        raise AssertionError(
            "the chest densify found %d faces under the glyph, under the %d floor "
            "— the emblem is not where the row says it is" % (picked, spec["min_faces"]))


def paint_chest_glyph(obj, tj, row):
    """WINDMAN'S "W", AS VERTEX COLOUR (bead godot-test1-5u3.5, his row only).

    The retired generator built this letter as GEOMETRY — a shapely poly-line
    buffered into a polygon and extruded 22 mm proud of a flat torso — and that
    slab is the last thing in this repo holding the `shapely` / `mapbox-earcut`
    pins (bead 5u3.8 drops them). On a MakeHuman chest it could not have stayed
    geometry anyway: a rigid slab over a curved, skinned surface either floats or
    is swallowed the moment the spine bends.

    So the letter is PAINT, on the vertices that are already there — after
    `densify_chest` has doubled how many of them there are under the glyph, which
    the first build proved is not optional: at the body's own 24 mm pitch the
    letter's two notches close up and the whole thing reads as one white blob.
    Split once, the chest runs ~12 mm and carries four to five vertices across
    each arm of the W and three across each notch. `min_verts` is the guard: a
    decimation change that thins this chest fails the build instead of shipping
    that blob again.

    Runs AFTER `paint_body`, which owns the colour attribute and the base coat:
    this only overwrites, and only on the FRONT of the torso — `v.normal.y > 0.3`
    (the build frame's +Y is the face) keeps the letter off the back and off the
    curve of the ribs, and the torso weight keeps it off the arms that hang
    inside the glyph's x span at rest.
    """
    spec = row["emblem"]
    colour = row["colours"][spec["colour"]]
    origin_z = tj["neck"].z - spec["drop"]
    me = obj.data
    attr = me.color_attributes.active_color
    torso_ids = {vg.index for vg in obj.vertex_groups
                 if vg.name in REGION_BONES["torso"]}

    hit = []
    for i, v in enumerate(me.vertices):
        if v.normal.y <= 0.3 or _group_weight(v, torso_ids) <= 0.4:
            continue
        if _glyph_distance(spec, v.co, origin_z) > spec["stroke"]:
            continue
        attr.data[i].color = colour
        hit.append(v.co.copy())
    zs = [c.z for c in hit]
    xs = [c.x for c in hit]
    log("chest glyph: %d vert(s), x %.3f..%.3f, z %.3f..%.3f"
        % (len(hit), min(xs, default=0.0), max(xs, default=0.0),
           min(zs, default=0.0), max(zs, default=0.0)))
    if len(hit) < spec["min_verts"]:
        raise AssertionError(
            "the chest glyph painted %d vertices, under the %d floor — at this "
            "density the letter is dots, not a W" % (len(hit), spec["min_verts"]))


# ---------------------------------------------------------------------------
# Beret + eyes (spike_z3e_teibi_body.py's, unchanged but for the head weights)
# ---------------------------------------------------------------------------

def _apply_all_transforms(obj):
    bpy.context.view_layer.objects.active = obj
    for o in bpy.data.objects:
        o.select_set(o is obj)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def _make_ring(r_in, r_out, height, name, vertices=18):
    bpy.ops.mesh.primitive_cylinder_add(radius=r_out, depth=height, vertices=vertices)
    outer = bpy.context.active_object
    outer.name = name
    bpy.ops.mesh.primitive_cylinder_add(radius=r_in, depth=height * 1.6, vertices=vertices)
    inner = bpy.context.active_object
    mod = outer.modifiers.new("Hole", 'BOOLEAN')
    mod.operation = 'DIFFERENCE'
    mod.object = inner
    bpy.context.view_layer.objects.active = outer
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(inner, do_unlink=True)
    return outer


BERET_WIDE = 0.78    # z3e.15 — the saucer pulled in onto the skull
BERET_EMBED = 0.040  # ... and seated deeper in it


def build_beret(colours, crown_z, embed=BERET_EMBED):
    """generate_teibi_separate.py's beret — dome, brim, headband, nub, tilted
    7/-11 degrees — seated on the crown. `embed` sinks the dome's own centre
    4 cm below the crown (the generator's own number was 3.2 cm; bead z3e.15
    moved it): a beret sits IN the scalp with its top third showing, and anchoring
    its lowest vertex on the crown floats the whole assembly 17 cm off the head
    (measured on the z3e.10 spike).

    BEAD z3e.15 SHRINKS IT SIDEWAYS AND SINKS IT. Its numbers are the generator's,
    and the generator hung them off a SPHERE head 0.25 m across; on a MakeHuman
    skull (half-width ~7.5 cm) the 0.162 m dome and the 0.112 m headband stand 8
    and 3.7 cm proud all the way round, so what the 2026-09-12 frame shows is a
    navy flying saucer hovering over Teibi with daylight under the brim. Both
    portraits wear it snug: it grips the skull, tilts, and overhangs on one side
    only. `BERET_WIDE` is one scale on x and y — the shape, the tilt, the seat and
    the proportions are the generator's still, it is only the radius that was a
    different head's — and `embed` NARROWS the gap under the brim; it does not
    close it. The headband is 8.7 cm to the skull's 7.5, so 1.2 cm of it still
    stands proud all the way round, which is a beret and not a defect. Height is
    NOT scaled: a flatter beret would be a different hat. WHAT THE OWNER SHOULD
    LOOK AT on the grid: narrowing it exposes a lobe of hair on the right that the
    old saucer covered. That is the portrait's tilt showing through, but it is a
    judgement, not a measurement — `BERET_WIDE` is the one knob if it reads wrong."""
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.162, segments=14, ring_count=8)
    dome = bpy.context.active_object
    dome.name = "BeretDome"
    dome.scale = (1.0, 1.0, 0.44)
    _apply_all_transforms(dome)

    brim = _make_ring(0.105, 0.165, 0.020, "BeretBrim")
    brim.location = (0.0, 0.0, -0.028)
    _apply_all_transforms(brim)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.112, depth=0.045, vertices=16,
                                        location=(0.0, 0.0, -0.050))
    band = bpy.context.active_object
    band.name = "BeretBand"
    _apply_all_transforms(band)

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.017, segments=8, ring_count=5,
                                         location=(0.0, 0.0, 0.066))
    nub = bpy.context.active_object
    nub.name = "BeretNub"
    _apply_all_transforms(nub)

    for o in bpy.data.objects:
        o.select_set(o in (dome, brim, band, nub))
    bpy.context.view_layer.objects.active = dome
    bpy.ops.object.join()
    beret = bpy.context.active_object
    beret.name = "Beret"

    tilt = (Matrix.Rotation(math.radians(7), 4, 'X')
            @ Matrix.Rotation(math.radians(-11), 4, 'Y'))
    narrow = Matrix.Diagonal(Vector((BERET_WIDE, BERET_WIDE, 1.0, 1.0)))
    # `seat` is applied LAST and therefore in the HEAD's frame: it is where the hat
    # sits on the skull, not a dimension of the hat, so `BERET_WIDE` has no business
    # in it. The generator's 1.5 cm, unscaled.
    seat = Matrix.Translation(Vector((0.015, 0.004, crown_z - embed)))
    beret.data.transform(seat @ tilt @ narrow)
    beret.data.update()

    attr = beret.data.color_attributes.new(name="Color", type='FLOAT_COLOR',
                                           domain='POINT')
    for i in range(len(beret.data.vertices)):
        attr.data[i].color = colours["beret_navy"]
    beret.data.color_attributes.active_color = attr
    beret.data.attributes.active_color = attr
    return beret


def build_eyes(colours, l_pos, r_pos, radius=0.012):
    """Two small spheres at the eye joints, white with a dark iris on the +Y
    (face) side — `mask_helpers=True` deleted MakeHuman's own eyeball helpers
    and MPFB2's eye ASSETS are a separate download."""
    spheres = []
    for pos, side in ((l_pos, "L"), (r_pos, "R")):
        bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, segments=10, ring_count=6,
                                             location=(pos.x, pos.y, pos.z))
        eye = bpy.context.active_object
        eye.name = "Eye" + side
        _apply_all_transforms(eye)
        attr = eye.data.color_attributes.new(name="Color", type='FLOAT_COLOR',
                                             domain='POINT')
        for i, v in enumerate(eye.data.vertices):
            attr.data[i].color = colours["eye_iris"] \
                if v.co.y - pos.y > radius * 0.55 else colours["eye_white"]
        eye.data.color_attributes.active_color = attr
        eye.data.attributes.active_color = attr
        spheres.append(eye)
    for o in bpy.data.objects:
        o.select_set(o in spheres)
    bpy.context.view_layer.objects.active = spheres[0]
    bpy.ops.object.join()
    eyes = bpy.context.active_object
    eyes.name = "Eyes"
    return eyes


def join_weighted(target, extra, weights):
    """Join `extra` into `target` with every one of its vertices carrying
    `weights` — a bone name to weight map that should sum to 1. The join happens
    AFTER the rig so MPFB2's automatic weights are never asked to guess for a
    beret; the groups are written by hand instead."""
    for bone, weight in weights.items():
        vg = extra.vertex_groups.new(name=bone)
        vg.add(list(range(len(extra.data.vertices))), weight, 'REPLACE')
    bpy.context.view_layer.objects.active = target
    for o in bpy.data.objects:
        o.select_set(o is target or o is extra)
    bpy.ops.object.join()
    return bpy.context.active_object


def join_rigid(target, extra, bone):
    """`join_weighted` for the accessories that ride ONE bone: the beret and the
    eyes, both of which are the head and nothing else."""
    return join_weighted(target, extra, {bone: 1.0})


# PRIMM'S COAT TAILS — bead godot-test1-5u3.10, and the owner's own words for
# this coat: "prim has long jacket, like a tuxedo with tails". Every other garment
# in the cast is the body pushed out (`dress_shells`); these two are not, because
# there is no body behind a tail to push. So they are the second piece of
# accessory geometry in this file after the beret — boxes, flat-shaded, joined
# into the mesh and weighted by hand.
#
# THE WEIGHTS ARE THE WHOLE DESIGN. The bead asked for the tails to "hang with the
# hips, not the thighs" and to be shown NOT piercing the leg in a stride frame,
# and those two pull opposite ways: a flap welded to `pelvis` alone is a flap the
# back leg walks straight through, because at mid-thigh the swinging leg travels
# ~9 cm further back than the hip does. Splitting each tail's weight between the
# pelvis and ITS OWN side's thigh (0.6 / 0.4) makes the flaps part around the
# stride instead of standing still in front of it — which is also what a coat
# does. The flare and the 3 cm of standoff do the rest.
PRIMM_TAIL_HEM = 0.07       # the tails' top edge, ABOVE the pelvis joint: 5 cm
                            # inside the coat, because a flap that starts exactly
                            # at the hem shows daylight under it from behind
                            # (measured on this build's first render)
PRIMM_TAIL_BOTTOM = 0.16    # ... and their bottom, this far above the knee: mid-thigh
PRIMM_TAIL_WIDE = 0.100
PRIMM_TAIL_GAP = 0.040      # the slit between them, over the spine
PRIMM_TAIL_THICK = 0.016
PRIMM_TAIL_BITE = 0.020     # how far the flap is sunk INTO the coat's own back
PRIMM_TAIL_FLARE = 0.030    # how much further back the bottom hangs than the top
PRIMM_TAIL_TAPER = 0.85     # and how much narrower
PRIMM_TAIL_SWALLOW = 0.055  # how much higher the OUTER bottom corner sits than the
                            # inner one — what makes it a tail and not a flag


def build_tail(row, side, sign, hem_z, bottom_z, back_y):
    """One flap: a box from inside the coat down to mid-thigh, flared, tapered and
    cut away at the outer corner, sunk into the coat's own back so the two never
    show daylight between them."""
    # A NEGATIVE Z SCALE MIRRORS THE CUBE AND INVERTS EVERY NORMAL, and Godot
    # back-face-culls: the tails would simply not be there, in a shot nobody takes
    # from behind. The landmarks this is measured from are macro-driven, so a
    # hero short enough to put his knee above his own coat hem is a build failure
    # and not a silent one.
    if hem_z <= bottom_z:
        raise AssertionError("the coat hem (%.3f) is not above the tail's bottom "
                             "(%.3f): the flap would export inside out"
                             % (hem_z, bottom_z))
    cx = sign * (PRIMM_TAIL_GAP + PRIMM_TAIL_WIDE) / 2.0
    cy = back_y + PRIMM_TAIL_BITE - PRIMM_TAIL_THICK / 2.0
    cz = (hem_z + bottom_z) / 2.0
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, cz))
    flap = bpy.context.active_object
    flap.name = "CoatTail" + side.upper()
    flap.scale = (PRIMM_TAIL_WIDE, PRIMM_TAIL_THICK, hem_z - bottom_z)
    _apply_all_transforms(flap)
    # The cube's own winding survives this because it is a per-vertex nudge, not a
    # mirror — every normal still points out of the box.
    for v in flap.data.vertices:
        if v.co.z < cz:
            v.co.y -= PRIMM_TAIL_FLARE
            outer = (v.co.x - cx) * sign > 0.0
            v.co.x = cx + (v.co.x - cx) * PRIMM_TAIL_TAPER
            if outer:
                v.co.z += PRIMM_TAIL_SWALLOW
    flap.data.update()
    attr = flap.data.color_attributes.new(name="Color", type='FLOAT_COLOR',
                                          domain='POINT')
    for i in range(len(flap.data.vertices)):
        attr.data[i].color = row["colours"]["coat_purple"]
    flap.data.color_attributes.active_color = attr
    flap.data.attributes.active_color = attr
    return flap


def attach_tails(obj, row, tj):
    """Both flaps, hung off the back of the coat hem. Returns the joined object
    and ITS OWN polygon indices, which `export_glb` flat-shades: a tuxedo tail is
    a piece of tailoring with a crease, and smoothing a box rounds it into a
    sausage (the same ruling `wrap_band`'s rims ship under)."""
    z = landmarks(obj, tj, row)
    hem_z = z["pelvis"] + PRIMM_TAIL_HEM
    bottom_z = z["knee"] + PRIMM_TAIL_BOTTOM
    torso_ids = _vg_ids(obj, REGION_BONES["torso"])
    back_y = min((v.co.y for v in obj.data.vertices
                  if _group_weight(v, torso_ids) > 0.5
                  and abs(v.co.z - hem_z) <= 0.06), default=0.0)
    share = row["tails"]["pelvis"]
    before = len(obj.data.polygons)
    for side, sign in (("l", -1.0), ("r", 1.0)):
        obj = join_weighted(obj, build_tail(row, side, sign, hem_z, bottom_z, back_y),
                            {"pelvis": share, "thigh_" + side: 1.0 - share})
    faces = frozenset(range(before, len(obj.data.polygons)))
    log("coat tails: z %.3f..%.3f, back y %.3f, %d faces, pelvis %.2f / thigh %.2f"
        % (bottom_z, hem_z, back_y, len(faces), share, 1.0 - share))
    return obj, faces


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

def weight_strays_to(obj, armature, bone, floor):
    """TRAP 8. Any vertex with no bone weight at all goes to `bone`, weight 1.0.

    `wrap_band`'s knots are `bmesh.ops.create_cube` geometry and carry no deform
    layer; everything else it makes is extruded from skin that does. The wrap lives
    entirely on the head, so `head` is not a guess — it is the only bone any of it
    could belong to. Returns how many were swept, so a number that is not the knots'
    two boxes is visible rather than silent.

    AND `floor` IS WHAT KEEPS IT HONEST. This runs over the WHOLE mesh, and since
    bead 5u3.10 the whole mesh includes a few hundred vertices `dress_shells` cut
    into the legs and the torso. A hem ring that lost its weights would be welded
    to the skull here and `report_weights` — the guard that is supposed to catch
    exactly that — would then see a fully weighted mesh and pass. So a stray below
    the neck is not a knot and is not swept: it is the bug, and it stops the build.
    """
    bone_names = {b.name for b in armature.data.bones}
    ids = {vg.index for vg in obj.vertex_groups if vg.name in bone_names}
    vg = obj.vertex_groups.get(bone) or obj.vertex_groups.new(name=bone)
    stray = [v.index for v in obj.data.vertices if _group_weight(v, ids) <= 0.0]
    below = [i for i in stray if obj.data.vertices[i].co.z < floor]
    if below:
        raise AssertionError(
            "%d unweighted vert(s) below z=%.3f — the wrap is on the head, so "
            "these are a garment's or the body's own, and sweeping them onto %r "
            "would hide them from report_weights (lowest %.3f)"
            % (len(below), floor, bone,
               min(obj.data.vertices[i].co.z for i in below)))
    if stray:
        vg.add(stray, 1.0, 'REPLACE')
    log("swept %d unweighted vert(s) onto %s (none below z=%.3f)"
        % (len(stray), bone, floor))
    return len(stray)


def head_tri_count(obj):
    """Triangles whose every vertex is driven by the head — the bead's face-survived
    assert. Counted on the mesh as exported, so the beret and the eyes (weighted to
    `head` by `join_rigid`) count with it, and so does the wrap."""
    ids = {vg.index for vg in obj.vertex_groups if vg.name in ("head", "neck_01")}
    head = {v.index for v in obj.data.vertices if _group_weight(v, ids) > 0.5}
    obj.data.calc_loop_triangles()
    return sum(1 for t in obj.data.loop_triangles
               if all(i in head for i in t.vertices))


def export_glb(obj, armature, path, sharp=frozenset(), materials=False):
    """
    SMOOTH, and deliberately not through `predator_parts.export_faceted()`.
    CLAUDE.md calls that "the one export seam for every generated `.glb`
    (heroes included)", and three things put this lane outside it: the y1o
    faceted ruling is WAIVED FOR THE FOUR HEROES by the owner (bd show
    godot-test1-z3e NOTES, 2026-09-06); `export_faceted` is trimesh code and
    cannot be called from Blender at all (its Blender port went with
    `blender_hero.py`'s export lane, bead 5u3.8); and the predecessor this script is a
    copy of (`spike_z3e_teibi_body.py:669`) smooth-shades the same MPFB2 body
    the same way. Flat normals on an organic basemesh are also what tore the
    hero outline into cracks (bead z3e.9).

    `sharp` is `wrap_band`'s rims and knots — the ONE place a smooth-shaded hero
    keeps flat faces, because a cloth edge that shades smoothly into the cheek is
    the painted bandage again with extra steps (the spike's own ruling). It is a
    set of POLYGON INDICES, so nothing may be joined into the mesh between the wrap
    and here; `build()` keeps that order and refuses a row that breaks it.
    """
    for o in bpy.data.objects:
        o.select_set(o is obj or o is armature)
    bpy.context.view_layer.objects.active = armature
    for poly in obj.data.polygons:
        poly.use_smooth = poly.index not in sharp
    obj.data.update()
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        # TRAP 3: a SKINNED glTF is placed by its own root node. Y-up (the
        # default), not blender_hero.py's Z-up part convention.
        export_yup=True,
        export_skins=True,
        export_normals=True,
        export_tangents=False,
        # Every one of the 23 bones left after `cut_fingers()` is exported:
        # `export_def_bones=True` would drop the non-deform ones, and the
        # Godot-side assert (and the humanoid bone map) want the whole rig.
        export_def_bones=False,
        export_vertex_color='ACTIVE',
        export_all_vertex_colors=False,
        export_texcoords=False,
        # 'NONE' ON EVERY SHIPPED HERO, and the default here stays that: a hero
        # that exports no material is a hero Godot hands one shared default, which
        # `ToonShading.apply_to_mesh` styles as the cast. `materials=True` is bead
        # td8's COLUMN D and its scratch .glb alone — it is what carries the
        # `HeroCloth` name the Godot side splits on.
        export_materials='EXPORT' if materials else 'NONE',
        export_image_format='NONE',
        export_animations=False,
    )
    obj.data.calc_loop_triangles()
    tris = len(obj.data.loop_triangles)
    size = os.path.getsize(path)
    log("wrote %s (%d tris, %d bones, %d bytes)"
        % (os.path.basename(path), tris, len(armature.data.bones), size))
    return tris, size


def assert_no_multires(objs):
    for obj in objs:
        for mod in getattr(obj, "modifiers", []):
            if mod.type == 'MULTIRES':
                raise AssertionError("%s carries a MULTIRES modifier" % obj.name)


def build(hero, shot=None, variant=None):
    """Build one hero. `variant` (bead td8, the CLOTH SPIKE) turns on the
    extra passes of one column and redirects the output to a SCRATCH .glb that
    no scene loads and no manifest row covers; `None` is the shipped path and
    is byte-for-byte what it was before that bead."""
    row = HEROES[hero]
    passes = CLOTH_VARIANTS[variant] if variant else ()
    if "band" in row and (row["beret"] or row["eyes"] or "tails" in row):
        raise AssertionError(
            "%s wears a cloth band AND an accessory: `sharp` is polygon indices "
            "and a join after the wrap renumbers them (see export_glb)" % hero)
    if ARMS_DOWN_DEG >= ARMS_DOWN_MAX_DEG:
        raise AssertionError("the shipped rest stands %.1f deg off vertical, over "
                             "the %.1f cap" % (ARMS_DOWN_DEG, ARMS_DOWN_MAX_DEG))
    enable_mpfb()
    clear_scene()

    human, joints = build_human(row)
    armature = add_rig(human)
    cut_fingers(human, armature)
    report_weights(human, armature, "basemesh (pre-convert)")

    obj = bake_to_plain_mesh(human, armature)
    decimate(obj, BODY_TRIS, HEAD_TRIS)
    m = reframe(obj, armature, row["height"])
    tj = {name: m @ p for name, p in joints.items()}
    log("joints (game frame):", {k: tuple(round(c, 4) for c in v) for k, v in tj.items()})

    # THE ORIENTATION ASSERT, IN THE EXPORT FRAME. glTF's Y-up conversion maps
    # Blender (x, y, z) to (x, z, -y) — x is carried across UNCHANGED and only the
    # depth axis flips — so the face this script builds on +Y lands on Godot's -Z
    # and the character's left, built on -x, stays on Godot's -X: today's heroes'
    # convention (teibi.tscn LeftArm x=-0.18). The z half is asserted as the number
    # Godot will read, because that is the half the conversion touches.
    godot_eye_z = [-tj["l-eye"].y, -tj["r-eye"].y]
    if max(godot_eye_z) >= 0.0:
        raise AssertionError("body faces +Z in Godot: eye z=%.4f/%.4f (want < 0)"
                             % tuple(godot_eye_z))
    if tj["l-shoulder"].x >= 0.0:
        raise AssertionError("left shoulder not at Godot -X: %.4f" % tj["l-shoulder"].x)
    log("ASSERT OK (export frame): eye z=%.4f/%.4f, left shoulder x=%.4f — all < 0"
        % (godot_eye_z[0], godot_eye_z[1], tj["l-shoulder"].x))

    height = max(v.co.z for v in obj.data.vertices) - min(v.co.z for v in obj.data.vertices)
    if abs(height - row["height"]) > 0.03:
        raise AssertionError("reframed to %.4f m, outside %.2f +- 0.03"
                             % (height, row["height"]))
    log("ASSERT OK: height %.4f m, within 3 cm of the row's %.2f" % (height, row["height"]))

    # BEFORE the wrap, because the wrap's `flat_faces` are polygon indices and
    # this renumbers every polygon — see `densify_chest`.
    if "emblem" in row:
        densify_chest(obj, tj, row)

    # AND BEFORE THE WRAP FOR THE SAME REASON (trap 9): the hem cuts add vertices
    # and renumber every polygon. After the densify, so the chest the "W" is
    # painted on is already split — the shirt shell then pushes those finer
    # triangles out with the rest of the torso and the letter rides them.
    dress_shells(obj, tj, row)

    # BEAD td8, COLUMN A. Here and not later for trap 9's reason: the subdivide
    # adds geometry and renumbers every polygon, and `wrap_band` below hands
    # `export_glb` a set of polygon indices.
    if "folds" in passes:
        fold_garments(obj, tj, row)
    if passes:
        mark_cloth(obj)

    band_verts, flat_faces = wrap_band(obj, (tj["l-eye"].z + tj["r-eye"].z) / 2.0,
                                       row)
    if band_verts:
        weight_strays_to(obj, armature, "head", tj["neck"].z)
    paint_body(obj, tj, row, band_verts)
    if "emblem" in row:
        paint_chest_glyph(obj, tj, row)

    # BEAD td8, COLUMN B. AFTER the paint, because it MULTIPLIES into the colour
    # the paint just wrote; before the accessories, which are not garments.
    if "bake" in passes:
        bake_cloth_shading(obj)

    if row["beret"]:
        crown_z = max(v.co.z for v in obj.data.vertices)
        obj = join_rigid(obj, build_beret(row["colours"], crown_z), "head")
    if row["eyes"]:
        obj = join_rigid(obj, build_eyes(row["colours"], tj["l-eye"], tj["r-eye"]),
                         "head")
    if "tails" in row:
        obj, tail_faces = attach_tails(obj, row, tj)
        flat_faces = frozenset(flat_faces) | tail_faces

    apply_pose_as_rest(armature, obj, ARMS_DOWN_DEG)
    report_weights(obj, armature, "skinned body (accessories joined)")
    assert_no_multires([obj, armature])

    zs = [v.co.z for v in obj.data.vertices]
    log("final body: height %.4f m (z %.4f..%.4f), %d verts"
        % (max(zs) - min(zs), min(zs), max(zs), len(obj.data.vertices)))
    if abs(min(zs)) > 0.04:
        raise AssertionError("feet %.4f m off the ground (cap 0.04)" % min(zs))

    head_tris = head_tri_count(obj)
    log("head: %d tris (floor %d)" % (head_tris, HEAD_TRIS_MIN))
    if head_tris < HEAD_TRIS_MIN:
        raise AssertionError("the face melted: %d head tris under the %d floor"
                             % (head_tris, HEAD_TRIS_MIN))

    out_dir = os.path.join(OUT_ROOT, row["out_dir"])
    os.makedirs(out_dir, exist_ok=True)
    # THE MESH DATABLOCK IS NAMED TOO, and that is not tidiness: glTF writes the
    # datablock name into the file, `clear_scene()` unlinks OBJECTS and leaves the
    # meshes behind, and MPFB2 calls every one of them `base` — so in an `--all`
    # run the second and third heroes export as `base.001` and `base.002` while a
    # single-hero rebuild of either exports as `base`, four JSON bytes shorter, and
    # the manifest's byte size would then depend on which order someone built in.
    obj.name = obj.data.name = hero.capitalize()
    armature.name = armature.data.name = "Armature"
    # BEAD td8, COLUMN D — the LAST pass before the export, because it is the only
    # one that touches material slots and `export_glb` reads them.
    if "material" in passes:
        split_cloth_material(obj)
    if passes:
        drop_cloth_mark(obj)
    stem = row["stem"] if variant is None else "%s_cloth_%s" % (hero, variant)
    glb = os.path.join(out_dir, stem + ".glb")
    tris, size = export_glb(obj, armature, glb, sharp=flat_faces,
                            materials="material" in passes)
    if tris > TRI_BUDGET:
        # A SPIKE COLUMN IS ALLOWED OVER THE BUDGET AND SAYS SO. The budget guards
        # what ships; a column nothing loads that costs too many triangles is a
        # FINDING, not a build failure — the number is what the owner rules on.
        if variant is None:
            raise AssertionError("%d tris over the %d budget" % (tris, TRI_BUDGET))
        log("NOTE: variant %r is %d tris, %d over the %d shipped budget"
            % (variant, tris, tris - TRI_BUDGET, TRI_BUDGET))
    # NO TEXTURE, BY RULING — see the header. Printed anyway so the cap is a
    # measurement and not a promise. Counted off THIS HERO'S MATERIALS, not off
    # `bpy.data.images`: `--rest-row` leaves a 640x640 "Render Result" in the file
    # between heroes, and a render is not something the .glb ships.
    texture_bytes = sum(
        node.image.size[0] * node.image.size[1] * 4
        for mat in obj.data.materials if mat and mat.use_nodes
        for node in mat.node_tree.nodes
        if node.type == 'TEX_IMAGE' and node.image)
    log("texture bytes: %d (cap %d) — vertex colours only"
        % (texture_bytes, TEXTURE_BYTES_MAX))
    if texture_bytes > TEXTURE_BYTES_MAX:
        raise AssertionError("%d texture bytes over the %d cap"
                             % (texture_bytes, TEXTURE_BYTES_MAX))

    # NO .blend FOR A SPIKE COLUMN. The committed .blend is the shipped hero's
    # source of record (the epic's "commit the compressed .blend" ruling); a
    # scratch variant's source of record is this script plus its `--variant` name.
    if variant is None:
        blend = os.path.join(out_dir, row["stem"] + ".blend")
        bpy.ops.wm.save_as_mainfile(filepath=blend, compress=True)
        log("wrote %s (%d bytes)" % (os.path.basename(blend), os.path.getsize(blend)))

    if shot:
        # blender_hero.py's helper shoots from -Y, because the part trees it was
        # written for are built facing that way (its Rx(+90) root). These bodies
        # face +Y, so without this the rest row is three backs of heads. Turned at
        # the OBJECT level and only after both files are written — the .glb and the
        # .blend already have the rest pose they are supposed to have, and the mesh
        # and the armature turn together so the modifier still binds — which is
        # what turning only the ROOTS does, the mesh being MPFB2's child of the
        # armature. Turning both instead composes pi with pi and the hero faces
        # front again (measured 2026-09-11: three backs of heads).
        for o in (obj, armature):
            if o.parent is None:
                o.rotation_euler.z = math.pi
        # Workbench's default MATERIAL colour mode renders a hero with no material
        # as grey clay; these bodies ARE their vertex colours.
        bpy.context.scene.display.shading.color_type = 'VERTEX'
        blender_hero.screenshot(shot, max(zs))
    log("done")
    return {
        "glb": os.path.relpath(glb, OUT_ROOT),
        "glb_bytes": size,
        "tris": tris,
        "head_tris": head_tris,
        "bones": len(armature.data.bones),
        "texture_bytes": texture_bytes,
        "texture_size": 0,
        "height_m": round(max(zs) - min(zs), 4),
    }


# ---------------------------------------------------------------------------
# The manifest, the rest row, the CLI
# ---------------------------------------------------------------------------

def tool_versions():
    mpfb = importlib.import_module("bl_ext.blender_org.mpfb")
    version = getattr(mpfb, "VERSION", None) or \
        getattr(mpfb, "bl_info", {}).get("version")
    return {"blender": bpy.app.version_string,
            "mpfb": ".".join(str(p) for p in version) if version else "unknown"}


def read_manifest():
    if not os.path.exists(MANIFEST):
        return {"tools": {}, "heroes": {}}
    with open(MANIFEST) as fh:
        return json.load(fh)


def write_manifest(built):
    """Merge this run's rows into the committed manifest. A single-hero rebuild
    updates its own row and leaves the others alone, so the file never has to be
    rewritten from a full `--all` to stay true."""
    data = read_manifest()
    data["tools"] = tool_versions()
    data.setdefault("heroes", {}).update(built)
    with open(MANIFEST, "w") as fh:
        json.dump(data, fh, indent=2, sort_keys=True)
        fh.write("\n")
    log("wrote %s" % os.path.relpath(MANIFEST, REPO))


def check_manifest(built):
    """`--check`: the rebuild against the committed numbers. The .glb's BYTE SIZE is
    in here and its bytes are not, because the glTF exporter is free to emit one
    primitive's triangles in a different rotation between runs (measured 2026-09-11
    on two identical Teibi builds: same vertex data, 1,001 index bytes apart, same
    366,452-byte file). Size, tris, bones and texture bytes are stable; the .blend's
    size is not (Blender stamps it), so it is not gated anywhere."""
    want = read_manifest().get("heroes", {})
    bad = []
    for hero, got in sorted(built.items()):
        if hero not in want:
            bad.append("%s: not in the manifest" % hero)
            continue
        for key, value in sorted(got.items()):
            if want[hero].get(key) != value:
                bad.append("%s.%s: manifest %r, rebuild %r"
                           % (hero, key, want[hero].get(key), value))
    tools = read_manifest().get("tools", {})
    if tools != tool_versions():
        bad.append("tools: manifest %r, this Blender %r" % (tools, tool_versions()))
    for line in bad:
        log("CHECK FAIL", line)
    if bad:
        raise SystemExit(1)
    log("CHECK OK: %d hero(es) match %s"
        % (len(built), os.path.relpath(MANIFEST, REPO)))


def rest_row(shots, path):
    """The cast at rest, side by side in one strip. Blender renders each hero on its
    own (`blender_hero.screenshot`, reused) and numpy pastes them — Pillow is not
    installed in Blender's Python and is not worth adding for one concatenate."""
    import numpy

    frames = []
    for shot in shots:
        img = bpy.data.images.load(shot)
        buf = numpy.empty(len(img.pixels), dtype=numpy.float32)
        img.pixels.foreach_get(buf)
        frame = buf.reshape(img.size[1], img.size[0], 4)
        # The helper frames a whole 4 m field of view for a 1.8 m man, so most of
        # each square is floor. Keep the middle third: three heroes at a readable
        # size beat three squares of background.
        cut = frame.shape[1] // 3
        frames.append(frame[:, cut:-cut])
        bpy.data.images.remove(img)
    strip = numpy.concatenate(frames, axis=1)
    out = bpy.data.images.new("rest_row", strip.shape[1], strip.shape[0])
    out.pixels.foreach_set(strip.ravel())
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out.filepath_raw = path
    out.file_format = 'PNG'
    out.save()
    log("wrote %s (%d x %d, %d bytes)"
        % (os.path.relpath(path, REPO), strip.shape[1], strip.shape[0],
           os.path.getsize(path)))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    check = "--check" in argv
    row_png = argv[argv.index("--rest-row") + 1] if "--rest-row" in argv else None
    # BEAD td8, THE CLOTH SPIKE. `--variant <name>` may repeat; each one is a
    # SEPARATE build writing its OWN scratch .glb, and none of them writes the
    # manifest — which is what keeps `--all --check` a statement about the
    # shipped files and nothing else.
    variants = [argv[i + 1] for i, a in enumerate(argv) if a == "--variant"]
    for v in variants:
        if v not in CLOTH_VARIANTS:
            raise SystemExit("unknown --variant %r (built: %s; column c, the "
                             "512^2 fabric albedo, is NOT built — see the bead)"
                             % (v, ", ".join(sorted(CLOTH_VARIANTS))))
    if variants and (check or "--all" in argv):
        raise SystemExit("--variant is a SCRATCH build: it writes no manifest row, "
                         "so --check and --all have nothing to say about it")
    heroes = [argv[i + 1] for i, a in enumerate(argv) if a == "--hero"]
    if "--all" in argv:
        heroes = list(HEROES)
    if not heroes:
        # The bare positional form PROVENANCE.md and every older note still use.
        heroes = [a for a in argv if not a.startswith("-")
                  and a != row_png] or ["teibi"]
    for hero in heroes:
        if hero not in HEROES:
            raise SystemExit("unknown hero %r (have: %s)"
                             % (hero, ", ".join(sorted(HEROES))))

    shots = {}
    built = {}
    for hero in heroes:
        shot = os.path.join(tempfile.gettempdir(), "build_hero_%s.png" % hero) \
            if row_png else None
        for variant in (variants or [None]):
            built[hero if variant is None else "%s:%s" % (hero, variant)] = \
                build(hero, shot, variant)
        if shot:
            shots[hero] = shot
    if row_png:
        rest_row([shots[h] for h in heroes],
                 row_png if os.path.isabs(row_png) else os.path.join(REPO, row_png))
    if variants:
        for name, row in sorted(built.items()):
            log("VARIANT %-16s %6d tris  %8d glb bytes  %6d texture bytes"
                % (name, row["tris"], row["glb_bytes"], row["texture_bytes"]))
        return
    if check:
        check_manifest(built)
    else:
        write_manifest(built)


if __name__ == "__main__":
    main()
