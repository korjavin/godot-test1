"""
scripts/build_hero.py — THE SKINNED HERO LANE. A hero is a `HEROES` row.

Bead godot-test1-5u3.1 (epic 5u3, SKINNED HEROES), the SOURCE OF RECORD for the
shipped Teibi since bead 5u3.3, and GENERALISED to the whole cast by bead 5u3.4:
windman, primm and teibi are three rows of one table and there is no second
script. A FOURTH ROW SINCE BEAD godot-test1-9k9n.1 (epic 9k9n, owner ruling
2026-09-18, option B): Phoboman was the one hero left on the part generator and
the limb rig — a sphere for a belly, ten `.glb` files — and he is a heavy HUMAN
here now, with the diving helmet, the pho-bowl face and the chest dragon as
joined accessories. He needed no new pipeline stage: a row, two builders and a
per-row head budget, which is the test this table was always going to be put to.
Started as a copy of the z3e.10 spike (`scripts/spike_z3e_teibi_body.py`,
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
  band + stripes    eyewear as CLOTH: `wrap_band` lifts the face's own surface
                    into a thick wrap and `stripes` are the colours it is painted
                    in (bead z3e.13's Windman bandage, folded in with the faces by
                    bead 5u3.8). Primm's goggles were `stripes` WITHOUT a band —
                    paint on the skin — until the owner called them a headband;
                    they are `goggles` now, below.
  goggles           Primm's, and Primm's alone (bead godot-test1-nvy): a frame,
                    two rectangular lenses, arms and a strap, seated on the head's
                    own measured outline and weighted to the head bone
                    (`build_goggles`). An ACCESSORY, not a garment and not cloth.
  beret/eyes        accessory GEOMETRY joined into the mesh and weighted to one
                    bone. An accessory that is not geometry is an ATTACHMENT and
                    belongs in the .tscn as a BoneAttachment3D (Windman's fan on
                    `hand_r`, bead 5u3.5) — the row does not model it and neither
                    does this.
  helmet/dragon     Phoboman's, and Phoboman's alone (bead godot-test1-9k9n.1):
                    the brass diving helmet with the pho-bowl face behind its
                    glass, rigid on `head` so the gait's bobble nods it, and the
                    red Chinese dragon on the belly, weighted ACROSS the three
                    spine bones because that is how much body it lies on
                    (`build_helmet`, `build_dragon`, `spine_split`). Both are
                    the retired part-tree generator's own pieces and palette,
                    re-seated on the hero's measured skull and belly.
  creases           a row's OWN crease heights, as `(landmark, offset)` pairs
                    appended to the cast's joint list in `_fold_bands`. The joints
                    are where a sleeve and a trouser leg fold, and `fold_garments`
                    reads how many of them a hero's cloth covers as "how much cloth
                    this hero has" — so a hero whose garments carry no joint (a
                    belly shell, bare arms) needs his own or he fails that budget.
  head_tris         a row's own head decimate target, overriding `HEAD_TRIS`, and
                    with it the `HEAD_TRIS_MIN` floor when the row wears a
                    `helmet`. One row has a face nobody can see, and the
                    triangles it does not spend are what its accessories cost.
  emblem            a MOTIF painted onto the body's own vertices: a centre-line,
                    a stroke width and a landmark to hang it off. Windman's chest
                    "W" is the only one (`paint_chest_glyph`).

AND EVERY GARMENT IS THEN MADE OF CLOTH (beads td8 the spike, 21m the rollout;
owner pick 2026-09-12 on `grid_27_cloth_spike.png`, "i choose A+B+D"): folds
subdivided and displaced into the crease and hem bands, occlusion and cavity
multiplied into the garment's own vertex colours, and the garment polygons split
onto a second material named `HeroCloth` that `scripts/toon_shading.gd` shades
with DIFFUSE_BURLEY and no rim while the skin and the face keep the cast's
DIFFUSE_TOON. Three passes, all three unconditional, all three written under THE
CLOTH section below — which is also where the triangle budget they spend is
asserted.

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
 3. The retired part-import lane's conjugation trick (W_blender =
    Rx(90)·W_godot·Rx(90)^-1) is for UNRIGGED parts hung on a .tscn node whose
    basis is Rx(-90). A
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
    polygon indices; anything joined AFTER it (the goggles, the beret, the eyes,
    Primm's coat tails, Phoboman's helmet and his dragon) is refused on a row that
    wears a band. `build()` holds both rules.
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
# landmark; the first stripe containing a vertex wins. It comes with `band` and only
# with it: since bead godot-test1-nvy took Primm's goggles off the skin and built
# them (`build_goggles`), there is no eyewear in the cast that is PAINT, and
# `paint_body` reads these on the wrap's own vertices and nowhere else.
#
# `band` says those colours are worn as CLOTH: `wrap_band` lifts that slab of the
# face off the skull into a thick wrap before `paint_body` colours it, and the face
# underneath — eye sockets included — is consumed by the lift. See `wrap_band`.
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
        # BEAD z3e.15 REVERSED THE CONTRAST, which was the right diagnosis of the
        # wrong thing. The note above had pulled the LENS darker and left the
        # frames at (0.70, 0.72, 0.76) — exactly the value it had just measured
        # clipping to flat white — so the shipped goggles were a 5.4 cm band of
        # paper white across the brow, the cheekbone and both temples with the lens
        # a faint blue line lost inside it; z3e.15 gave the frames `trim_silver`'s
        # measured dark, made the lens the thing that glows, and narrowed the band
        # to 4.0 cm. The owner looked at that and said it was a HEADBAND, which it
        # was: paint on a cheek has no silhouette, and no amount of contrast gives
        # it one.
        #
        # SO THERE ARE NO STRIPES IN THIS ROW ANY MORE (bead godot-test1-nvy). The
        # goggles are geometry — `build_goggles` — and the two colours moved with
        # them to `goggle_frame` and `goggle_lens` in the `HEROES` row's own
        # palette, where BOTH were re-measured for geometry: paint takes this
        # scene's key light at a grazing angle and a raked slab and a rimmed tube do
        # not (that palette's own note has the numbers). `stripes` now means CLOTH
        # and belongs to Windman's bandage alone (see the table's banner).
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
            # THE GOGGLES, which are geometry since bead godot-test1-nvy — see the
            # `build_goggles` banner for the whole of why, and for the transfer
            # these four are measured against: this scene lifts a linear albedo by
            # ~1.85 before the sRGB encode (skin 0.404 renders 225), measured on the
            # web `17_head_face` frame.
            #
            # NEITHER KEEPS z3e.15's PAINTED VALUE, and the first two renders of
            # this bead are why. Paint lies on a cheek and takes this scene's high
            # key light at a grazing angle; geometry does not. The LENS is a slab
            # RAKED INTO the sun, so it sits in the lit band of DIFFUSE_TOON at full
            # strength — at the painted (0.38, 0.76, 0.90) it rendered (244, 248,
            # 249), which is white, where the bead asked for cyan. The FRAME is a
            # tube with a horizontal top face AND it is on `HeroSkin`, which
            # `toon_shading.style()` gives a rim light: at the painted graphite
            # (0.22, 0.24, 0.29) it rendered at luma 171 against a lens at 188 — a
            # pale bar at the same brightness as its own lenses, where the portrait
            # draws a dark one. So the frame comes down by about the factor the lens
            # did. Re-measured along the bar on the same frame, it now runs from
            # (24, 31, 38) at the nose to (55, 59, 58) at the temple where the rim
            # catches it — luma 29 to 58, graphite at both ends — against a lens at
            # (63, 214, 242), luma 180. `goggle_glint` is the lens's own top edge,
            # which is the "lighter rim strip" the bead asked for in place of
            # transparency.
            "goggle_frame": (0.05, 0.06, 0.075, 1.0),
            "goggle_edge":  (0.09, 0.10, 0.125, 1.0),
            "goggle_lens":  (0.10, 0.32, 0.40, 1.0),
            "goggle_glint": (0.14, 0.40, 0.49, 1.0),
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
        # THE GOGGLES ARE GEOMETRY (bead godot-test1-nvy; owner, 2026-09-12: "they
        # look like a headband"). They were `stripes` — a band of colour across the
        # face — and a band of colour is a headband however its contrast is tuned.
        # NOT cloth either: no `band` key, because the wrap consumes the face it
        # lifts and these have eyes behind them. `build_goggles` is the whole row.
        "goggles": True,
        "hair": dict(zip(("lift", "front", "nape"),
                         (FACES["primm"]["hair_lift"],
                          FACES["primm"]["hair_front"],
                          FACES["primm"]["hair_nape"])), brows=False),
        "beret": False,
        # STILL NO EYEBALLS, and bead godot-test1-nvy built them before deleting
        # them again. The reason has changed: it is not that a painted lens would
        # be poked through any more, it is that an OPAQUE one hides them — the two
        # spheres are invisible from every angle where the lens covers the socket,
        # and visible only where it does not. On the 3/4 `17_head_face` frame that
        # was one white sliver of the FAR eyeball past the outer edge of its lens,
        # which is a defect and the only thing they contributed. The sockets stay
        # (this row wears no `band`, so nothing consumes them, which is the half of
        # the bead's "the eyes underneath stay" that geometry can carry); behind
        # the lens they read as the shadow under it.
        "eyes": False,
        # blender_hero.py measured the generated Primm at 1.7733 m with the
        # authored head.
        "height": 1.78,
        "out_dir": "primm_parts",
        "stem": "primm_skinned",
    },
    "phoboman": {
        # docs/characters/phoboman.md: "resembles a teaspoon" — short (140-150 cm),
        # a large round belly the upper body widens into, legs short and almost
        # invisible under it, arms short but noticeably muscular and BARE, black
        # short pants, flat black boots, and a deep-sea diving helmet with the
        # pho-soup face behind its glass.
        #
        # THE FOURTH ROW, AND THE OWNER'S OPTION B (2026-09-18, epic
        # godot-test1-9k9n): Phoboman is a heavy HUMAN on the same rig as the trio,
        # with the helmet, the pho face and the chest dragon as joined accessories.
        # This SUPERSEDES the 2026-09-11 "Phoboman keeps the limb rig for good /
        # sphere body" ruling. The design target that survives is the retired
        # part-tree generator's — its palette verbatim, its helmet assembly,
        # its dragon — ported onto a body that walks.
        #
        # NO `FACES` ROW. Every other hero's face is his own recipe because it is
        # what the camera reads at 3 m; Phoboman's is behind 3 mm of helmet glass
        # and is `build_helmet`'s broth, noodles and herb nose. The MakeHuman face
        # under the dome is never seen, which is also why this row carries
        # `head_tris` and `helmet` (see `build()`).
        "macros": {"gender": 0.9, "age": 0.5, "muscle": 0.6, "weight": 1.0,
                   # LOW PROPORTIONS is MakeHuman's own word for "not idealised":
                   # the slider runs from uncommon (0) to idealistic (1) and the
                   # canon's silhouette is the opposite of a fashion plate.
                   "proportions": 0.15,
                   # AND LOW HEIGHT, although `reframe` scales every hero to his
                   # row's metre value anyway: this macro is not a size, it is a
                   # set of PROPORTIONS — a short MakeHuman is short in the legs
                   # and large in the head and trunk, which is the canon's
                   # "140-150 cm ... legs are short and almost invisible under the
                   # belly" surviving the scale back up to the cast's one height.
                   "height": 0.2,
                   "caucasian": 1.0, "african": 0.0, "asian": 0.0},
        # THE TEASPOON, AS TARGETS. `weight` 1.0 alone makes a fat man, not a bowl:
        # it thickens everything evenly. The belly is `stomach-pregnant-incr` at
        # full (MakeHuman's own name for "the abdomen is a sphere"), softened by
        # `stomach-tone-decr`; the torso is widened and deepened around it and its
        # V is inverted so the shoulders narrow into the middle rather than out of
        # it ("upper body smoothly widens towards the middle"); both leg segments
        # are shortened to the floor of their range ("legs are short and almost
        # invisible under the belly"); the arms are shortened and thickened
        # ("short but noticeably muscular"); and the neck is collapsed, because
        # today's phoboman.tscn says "no neck by design" and the helmet collar
        # lands on the shoulders.
        "targets": [(("stomach", "stomach-pregnant-incr.target.gz"), 1.0),
                    (("stomach", "stomach-tone-decr.target.gz"), 0.7),
                    (("torso", "torso-scale-horiz-incr.target.gz"), 0.7),
                    (("torso", "torso-scale-depth-incr.target.gz"), 0.6),
                    (("torso", "torso-vshape-decr.target.gz"), 0.5),
                    (("torso", "measure-waist-circ-incr.target.gz"), 0.8),
                    (("hip", "hip-scale-horiz-incr.target.gz"), 0.5),
                    (("legs", "upperlegs-height-decr.target.gz"), 1.0),
                    (("legs", "lowerlegs-height-decr.target.gz"), 1.0),
                    (("legs", "measure-thigh-circ-incr.target.gz"), 0.5),
                    (("arms", "measure-upperarm-length-decr.target.gz"), 0.7),
                    (("arms", "measure-lowerarm-length-decr.target.gz"), 0.7),
                    (("arms", "measure-upperarm-circ-incr.target.gz"), 0.8),
                    (("arms", "l-upperarm-muscle-incr.target.gz"), 0.6),
                    (("arms", "r-upperarm-muscle-incr.target.gz"), 0.6),
                    (("arms", "l-lowerarm-muscle-incr.target.gz"), 0.6),
                    (("arms", "r-lowerarm-muscle-incr.target.gz"), 0.6),
                    (("neck", "neck-scale-vert-decr.target.gz"), 1.0),
                    (("neck", "neck-scale-horiz-incr.target.gz"), 0.5)],
        # The retired part-tree generator's `self.colors`, VERBATIM — the canon's
        # own "repeat the colors of the face, head, dragon on the belly, pants and
        # boots" and the convention every other row here follows. `skin` is graded
        # by `GRADED_COLOURS` like the rest of the cast's.
        #
        # THE ONE ADDITION is `pants_black`, because the generator dressed the legs
        # in `boots_black` and this row has a boot shaft to be black AGAINST (the
        # lesson Primm's `jeans_navy` note records). Two stops up, still black.
        #
        # EXPECT THE EXPOSURE PROBLEM Primm's goggle row documents: this scene
        # lifts a linear albedo by ~1.85 before the sRGB encode, so `glass` (0.55,
        # 0.75, 0.82), `broth_hi` (0.99, 0.78, 0.30) and `noodle` (0.97, 0.85,
        # 0.55) are all candidates to clip flat white on `HeroSkin`. They are
        # NOT moved here: nothing in this bead renders in Godot (the .glb is
        # unwired until child 9k9n.2), and a value moved against a guess is a value
        # nobody can re-derive. Child .2 measures the `17_head_face` frame and
        # moves them HERE, with the measurement in the comment, as Primm's did.
        "colours": {
            'body_blue':    (0.13, 0.18, 0.46, 1.0),   # deep royal/navy belly
            'dragon_red':   (0.80, 0.13, 0.13, 1.0),   # bold Chinese-dragon red
            'dragon_gold':  (0.92, 0.74, 0.30, 1.0),   # horns, eyes, whiskers
            'helmet_gold':  (0.80, 0.62, 0.24, 1.0),   # brass/gold diving helmet
            'helmet_dark':  (0.55, 0.41, 0.15, 1.0),   # darker brass: ring, rivets
            'glass':        (0.55, 0.75, 0.82, 1.0),   # porthole glass
            'broth':        (0.95, 0.52, 0.18, 1.0),   # orange pho broth
            'broth_hi':     (0.99, 0.78, 0.30, 1.0),   # bright-yellow highlight
            'noodle':       (0.97, 0.85, 0.55, 1.0),   # pale noodle strands
            'eye_dark':     (0.20, 0.10, 0.05, 1.0),   # dark noodle-eye pupils
            'nose_green':   (0.30, 0.70, 0.22, 1.0),   # bright-green herb nose
            'skin':         (0.91, 0.71, 0.58, 1.0),   # bare muscular arm skin
            'boots_black':  (0.07, 0.07, 0.08, 1.0),   # flat black boots
            'pants_black':  (0.11, 0.11, 0.13, 1.0),   # ... and the shorts over them
        },
        # BARE BEEFY ARMS and black legs, as bone regions: the upper and lower arm
        # leave the default `shirt` for `skin` (the hands are already skin), and the
        # calf leaves `trousers` for `shoes`, because the boot shaft reaches the
        # knee and the pants stop above it. `clavicle_*` stays behind in `shirt`,
        # which is the blue belly shell's shoulder cap.
        "bone_regions": {"upperarm_l": "skin", "upperarm_r": "skin",
                         "lowerarm_l": "skin", "lowerarm_r": "skin",
                         "calf_l": "shoes", "calf_r": "shoes"},
        "colour_key": {"skin": "skin", "shirt": "body_blue",
                       "trousers": "pants_black", "shoes": "boots_black"},
        # No belt, no cuff, no collar: the belly is one blue garment from the neck
        # to the hips and the arms it would band are bare.
        "bands": (),
        # THE BELLY IS A GARMENT (the canon's "blue background with a red Chinese
        # dragon" is a colour on a shell, not a skin tone), and it is the baggiest
        # cut in the cast because the canon's build is "round and loose". Under it
        # the short pants are fitted and stop 6 cm ABOVE the knee joint, where the
        # boot shaft takes over — Primm's trouser/boot pair, same two cuts in the
        # same order and the same one shared height, so the two hems meet exactly
        # and the prouder boot (24 mm to the trouser's 20) reads as swallowing it.
        "garments": (
            {"bones": TORSO_BONES + ["pelvis"], "top": ("neck", -0.02),
             "bottom": ("pelvis", -0.04), "cut": GARMENT_BAGGY, "key": "shirt"},
            {"bones": THIGH_BONES, "top": ("pelvis", -0.02),
             "bottom": ("knee", 0.06), "cut": GARMENT_FITTED, "key": "trousers"},
            {"bones": SHAFT_BONES, "top": ("knee", 0.06), "bottom": ("ground", 0.0),
             "cut": GARMENT_BOOT, "key": "shoes"},
        ),
        # THREE CREASES ACROSS THE BELLY, because a 63 cm garment shell with no
        # joint anywhere in it gets none from the cast's own list — see
        # `_fold_bands`. Three separate gathers 7 cm apart, each `CREASE_BAND`'s
        # own 5.6 cm tall, so 1.4 cm of flat shell is left between them: what a
        # loose blue shell over a round stomach does, and what "the build is round
        # and loose" asks for. NOT decoration — measured, the cast's joint list
        # alone folds him +10.2%, which is UNDER `FOLD_TRIS_MIN` and FAILS
        # `fold_garments`'s budget assert; these three take him to +18.1%.
        "creases": (("pelvis", 0.16), ("pelvis", 0.23), ("pelvis", 0.30)),
        # THE HELMET AND THE DRAGON, the two accessories this row brings — see
        # `build_helmet` and `build_dragon`. Both are geometry joined into the mesh
        # after the paint, the helmet rigid on `head` (so the gait's 7-degree head
        # bobble nods the whole dome) and the dragon weighted across the three
        # spine bones (so the belly's twist and breathing carry it).
        "helmet": True,
        "dragon": True,
        # NO HAIR IS VISIBLE UNDER A DIVING HELMET, and this row says so with the
        # numbers rather than with a branch in `paint_body`: a hairline a metre
        # above the eye line selects no vertex, so no vertex is painted `hair` and
        # nothing is lifted. (The alternative was an `if "hair" in row` guard on
        # four reads in `paint_body`; a row that dresses itself out is the smaller
        # change and it keeps that function's shape.)
        "hair": {"lift": 0.0, "front": 1.0, "nape": 0.0, "brows": False},
        "beret": False,
        # No eyeballs: the sockets are inside the dome and the face the camera
        # reads is the broth behind the glass.
        "eyes": False,
        # THE HEAD UNDER THE HELMET IS DEAD GEOMETRY and must not spend the head
        # budget — those triangles are what the helmet and the dragon are paid
        # from. Low enough to be cheap, high enough that MakeHuman's own `lips`
        # group survives the collapse (`paint_body`'s `LIP_VERTS_MIN`, which is an
        # assert this row still has to pass even though nobody will ever see the
        # mouth). `HEAD_TRIS_MIN` does not apply to a helmeted row: see `build()`.
        #
        # 1,500 AND NOT 1,200, and the difference is that mouth. 1,200 built and
        # passed with 12 lip vertices against a floor of 8 — a margin of four
        # vertices on a hero nobody is looking at, which is the kind of number that
        # turns a face target into a failed build two beads from now. 300 more
        # triangles is 2% of this hero's budget.
        "head_tris": 1500,
        # 1.70 AND NOT THE CANON'S 1.40-1.50. The shared capsule, `CameraPivot` and
        # `FIRST_PERSON_EYE_HEIGHT` are tuned for ONE height and bead godot-test1-9ynx
        # put the whole figure at 1.80 m; this is the HUMAN, crown-to-heel, short
        # and wide, and the helmet dome and its valve knob top the figure out near
        # 1.80. The total is measured by the build and written on the PROVENANCE
        # row, because child 9k9n.2's `PHOBOMAN_TARGET_HEIGHT` is taken from it.
        # (The `abs(height - row["height"])` assert measures the human BEFORE the
        # joins, so the helmet never fights it.)
        "height": 1.70,
        "out_dir": "phoboman_parts",
        "stem": "phoboman_skinned",
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
# fattest of the three is 18,775.
#
# 18,500 SINCE BEAD 21m, and it is the cloth folds and nothing else. It was 15,500
# — the measured build plus room for one more garment — and `fold_garments` now
# subdivides the crease and hem bands of every garment on every hero, which the
# owner's A+B+D pick bought at a budgeted +15-25% (`FOLD_TRIS_MIN` / `_MAX`, and
# asserted there, per hero, at the pass that spends it). The fattest of the three
# is Windman at 14,743 before folds, so the top of that range is 18,429; this is
# that number rounded up, still under the epic's 18,775 ceiling, and still NOT a
# licence — the fold budget is the gate, this is the backstop behind it.
TRI_BUDGET = 18500
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
# CLOTH — bead godot-test1-td8 (the spike) and godot-test1-21m (this rollout),
# AND EVERY LINE BELOW NOW RUNS ON THE SHIPPED PATH. Owner, 2026-09-12: "shirts
# and clothing look painted, not natural — just colour on the heroes." After bead
# 5u3.10 the garments have VOLUME (`dress_shells` stands them proud of the skin,
# with a cut hem) but the surface between the hems is one flat vertex colour under
# a two-band DIFFUSE_TOON, which is exactly what "painted on" describes.
#
# THE SPIKE BUILT FOUR COLUMNS AND THE OWNER PICKED THREE (2026-09-12, on
# `docs/style/z3e/grid_27_cloth_spike.png`: "i choose A+B+D"). So what was three
# passes behind a `--variant` flag nobody passed is now three passes every hero
# takes, in this order and for the reasons at each call site in `build()`:
#
#   fold_garments        A — the crease bands, the hem gathers and the drape line,
#                        as displacement along the garment's own normals.
#   bake_cloth_shading   B — occlusion and cavity multiplied into the garment's
#                        vertex colours. Zero geometry, zero bytes.
#   split_cloth_material D — the garments get their own material, which
#                        `toon_shading.gd` then shades as CLOTH and not as cast.
#   (C)                  the 512^2 fabric albedo on unwrapped shells: NOT BUILT,
#                        not picked, and still the one column that would need a UV
#                        layout and the lane's first texture byte.
#
# The `--variant` flag and the scratch `teibi_cloth_*.glb` it wrote are GONE with
# this bead: their job was to be compared, the comparison happened, and a scratch
# .glb nothing loads is 1.5 MB of web download waiting for someone to forget the
# export exclusion.

# Amplitudes, in metres, on a 1.78 m body. The bead asks for 4-8 mm creases and
# a 3 mm hem gather; these are the middle of that, because a fold deeper than the
# shell stands proud (12-24 mm, the `GARMENT_*` cuts) would push the cloth back
# through the skin it is standing off.
FOLD_CREASE = 0.006      # crease depth at a joint
FOLD_GATHER = 0.003      # the radial ripple at a hem or a cuff
FOLD_DRAPE = 0.002       # the shoulder-to-hem drape line
FOLD_WAVE = 0.042        # metres per crease — one to two of them inside a band
FOLD_GATHERS = 9         # ripples around a hem
FOLD_DRAPES = 3          # drape lines around the body

# HOW WIDE THE SUBDIVIDED BANDS ARE, WHICH IS THE WHOLE TRIANGLE BILL (bead 21m).
# The displacement above is free — it moves vertices that already exist. What
# costs triangles is the subdivide that gives a 42 mm crease something to bend,
# and its cost is linear in the band height, because a band is a horizontal slice
# of a body whose garment density is roughly uniform.
#
# THE SPIKE'S BANDS WERE HALF THE BODY. `FOLD_BAND * 1.4` is a 21 cm slice at each
# of three joints and 9 cm at each of three hems, which is 90 cm of a 183 cm hero
# — i.e. "the whole panel", which is exactly what bead 21m says not to subdivide.
# It cost +57% triangles (13,872 -> 21,742 on Teibi) against a +15-25% budget.
# These two numbers are that scale factor, measured and then re-measured on the
# rebuild: the crease band keeps the joint itself and drops the panel either side
# of it, and the gather ring keeps the hem and drops the skirt above it. Measured
# on Teibi: 0.042/0.020 was +29.5%, and these are that scaled onto the budget.
#
# THEY ARE ALSO THE DISPLACEMENT'S OWN ENVELOPE, through `_fold_offset`, and that
# is not tidiness — it is the one thing that keeps the folds from aliasing. A
# 42 mm crease wave drawn on vertices 30 mm apart is noise, not a crease, so the
# high-frequency terms must DIE where the subdivide stops giving them vertices.
# The gaussian sigma is the band over `FOLD_TAPER`, which leaves the wave at 10%
# of amplitude at the band edge and 3% at the cut — a tail measured in tenths of a
# millimetre on the coarse geometry outside.
CREASE_BAND = 0.028      # half-height of a subdivided crease band, metres
GATHER_BAND = 0.014      # half-height of a subdivided hem/cuff gather ring
FOLD_TAPER = 1.5         # band / sigma, i.e. how hard a fold dies at its band edge
# ...and the gate that keeps them honest, as a fraction of the pre-fold triangle
# count. The bead's budget, asserted at the one place that can spend it, so a
# retune of the two constants above cannot quietly walk back to +57%.
FOLD_TRIS_MIN = 0.15
FOLD_TRIS_MAX = 0.25


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
    # AND A ROW MAY NAME ITS OWN (bead godot-test1-9k9n.1). The three above are the
    # cast's JOINTS, which is where a sleeve and a trouser leg crease — and the
    # budget assert below reads them as "how much cloth this hero has". Phoboman's
    # arms are bare by canon and his biggest garment is a 63 cm belly shell with no
    # joint anywhere in it, so the joint list alone folds him +10.2% against the
    # trio's +20.2 / +19.0 / +17.5 — under `FOLD_TRIS_MIN`, which means the assert
    # below FAILS his build outright. His row names the heights his own loose cloth
    # gathers at instead ("the build is round and loose", `docs/characters/
    # phoboman.md`), which takes him to +18.1%. Empty for every other row, which is
    # why the trio's bands — and therefore their `.glb` — did not move.
    creases += [z[name] + offset for name, offset in row.get("creases", ())]
    return creases, gathers, z


def _fold_offset(co, creases, gathers, z):
    """How far proud of the shell one garment vertex stands. A pure function of
    the rest position, so it is the same answer on every rebuild."""
    out = 0.0
    for zc in creases:
        t = (co.z - zc) / (CREASE_BAND / FOLD_TAPER)
        if abs(t) < 2.0:
            out += FOLD_CREASE * math.exp(-t * t) * math.sin(
                (co.z - zc) / FOLD_WAVE * math.tau)
    bearing = math.atan2(co.y, co.x)
    for zh in gathers:
        t = (co.z - zh) / (GATHER_BAND / FOLD_TAPER)
        if abs(t) < 2.0:
            out += FOLD_GATHER * math.exp(-t * t) * math.sin(bearing * FOLD_GATHERS)
    # The drape: one soft vertical ripple hanging from the shoulder to the hem,
    # the thing that makes a shirt read as hanging rather than as shrink-wrap.
    span = z["shoulder"] - z["pelvis"]
    if span > 0.0:
        ramp = min(1.0, max(0.0, (z["shoulder"] - co.z) / span))
        out += FOLD_DRAPE * ramp * math.sin(bearing * FOLD_DRAPES)
    return out


# CLOTH'S OWN COPY OF `dress_shells`'s ANSWER, and the reason it exists:
# `paint_body` DELETES every `GARMENT_VG` group when it is done with it (its own
# rule — "nothing but a bone ever reaches the exporter"), and two of the three
# passes here run AFTER the paint. So the cloth is marked ONCE, under a prefix
# `paint_body` does not sweep, and dropped again just before the export — the
# same trap-1 lesson every other pass in this file pays: a vertex GROUP survives
# what a vertex INDEX does not, joins and renumbering included.
#
# IT IS ALSO WHERE GEOMETRY THAT HAS NO SHELL GETS TO BE CLOTH. `dress_shells`
# can only mark a garment it pushed out of the body, and Primm's coat TAILS are
# the one garment in the cast that is new geometry (`attach_tails`) — so `build()`
# adds them to this group by hand after the join, and the bake and the material
# split then treat them as the cloth they are.
CLOTH_VG = "cloth:garment"


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


def _tri_count(me):
    me.calc_loop_triangles()
    return len(me.loop_triangles)


def fold_garments(obj, tj, row):
    """PASS A — FOLDS AS GEOMETRY, and the pass that spends this bead's triangles.

    Two steps, in the order `dress_shells` already taught this lane: SUBDIVIDE
    first (a 42 mm crease needs a vertex every ~20 mm and the decimated body has
    one every ~30 mm), then displace along the vertex normal.

    THE SUBDIVIDE IS BAND-LIMITED and that is a budget decision, not a taste one:
    subdividing the whole garment (which is most of the body) is a 3x overrun.
    Only edges whose both ends are garment AND whose midpoint falls inside a
    crease or gather band are cut, which is where the folds are and nowhere else.
    `CREASE_BAND` / `GATHER_BAND` say how narrow those bands are and why, and the
    assert at the end of this function is the bead's +15-25% budget spent where it
    is spent.

    THE DISPLACEMENT IS NOT BAND-LIMITED, and that asymmetry is deliberate: it
    moves vertices that already exist, so it costs nothing, and the drape term in
    particular is a shoulder-to-hem ripple that would be nonsense clipped to a
    2.8 cm band. What the narrow bands buy is that the HIGH-frequency terms — the
    42 mm creases — only get extra vertices where there is a crease to resolve.

    WHAT IT DOES NOT REACH: Primm's coat TAILS. They are joined by `attach_tails`
    after this pass and they must be — the tails' own polygon indices are what
    `export_glb` flat-shades ("a tuxedo tail is a piece of tailoring with a
    crease") and a subdivide here renumbers every polygon (trap 9). They take
    passes B and D and not this one, which costs almost nothing: 16 vertices of
    faceted box have no panel for a crease band to resolve.

    Runs BEFORE `wrap_band` (trap 9 — it adds geometry and renumbers polygons)
    and before `paint_body`, whose classification reads the vertex GROUPS the
    subdivide interpolates onto the new vertices.
    """
    ids = _garment_group_ids(obj)
    if not ids:
        raise AssertionError("fold_garments: no %s groups — dress_shells must run first"
                             % GARMENT_VG)
    creases, gathers, z = _fold_bands(obj, tj, row)
    band_zs = [(zc, CREASE_BAND) for zc in creases] + \
              [(zh, GATHER_BAND) for zh in gathers]

    def in_band(zv):
        return any(abs(zv - zc) < w for zc, w in band_zs)

    me = obj.data
    before_t = _tri_count(me)
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
    after_t = _tri_count(me)
    grew = (after_t - before_t) / float(before_t)
    log("folds: subdivided %d banded garment edges, +%d verts, +%d faces, "
        "%d -> %d tris (+%.1f%%)"
        % (len(edges), len(me.vertices) - before_v, len(me.polygons) - before_f,
           before_t, after_t, grew * 100.0))
    # THE BUDGET, ASSERTED WHERE IT IS SPENT (bead 21m), and the owner's "+15-25%"
    # is a range and not a ceiling: too FEW subdivided edges means the creases have
    # nothing to bend and the fold is a dent, which is just as much a regression as
    # too many.
    #
    # THE DENOMINATOR IS THE MESH AS IT STANDS HERE, not the finished hero: the
    # wrap, the beret, the eyes and the coat tails all join after this pass, so
    # they are in the hero's final count and not in this one. That makes this
    # fraction the CONSERVATIVE reading — it is the larger of the two, because the
    # triangles this pass adds are the same either way and the accessories only
    # grow the denominator. Measured on the shipped builds: this assert sees
    # +20.2 / +19.0 / +17.5% where the finished heroes grew +19.2 / +18.2 / +17.4%
    # against master. Both are inside the range; if they ever straddle it, the
    # number to believe is the hero's, which is in `hero_manifest.json`.
    if not FOLD_TRIS_MIN <= grew <= FOLD_TRIS_MAX:
        raise AssertionError(
            "folds grew %s by %.1f%%, outside the %.0f-%.0f%% budget — retune "
            "CREASE_BAND (%.3f m) / GATHER_BAND (%.3f m)"
            % (row["stem"], grew * 100.0, FOLD_TRIS_MIN * 100.0,
               FOLD_TRIS_MAX * 100.0, CREASE_BAND, GATHER_BAND))

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
    """PASS B — OCCLUSION AND CAVITY, MULTIPLIED INTO THE GARMENT'S VERTEX COLOURS.

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


# The two names `scripts/toon_shading.gd` matches on, and since bead 21m EVERY
# shipped hero carries both: the garment polygons on `HeroCloth`, everything else
# — skin, face, hair, beret, eyes, the wrap — on `HeroSkin`. They are the whole
# of the Godot-side contract, so keep them in step with `ToonShading.CLOTH_MATERIAL`;
# that comparison is exact equality and a rename on one side shades a hero as cast
# without erroring.
CLOTH_MATERIAL = "HeroCloth"
SKIN_MATERIAL = "HeroSkin"


def split_cloth_material(obj):
    """PASS D — THE GARMENTS GET THEIR OWN MATERIAL.

    Two slots, split on the same `GARMENT_VG` groups every other pass uses: a
    polygon is cloth when every one of its vertices is. The materials are plain
    white with the vertex colours doing the albedo, exactly as the shipped hero's
    single default material does — the whole difference is the NAME, which is what
    `ToonShading.apply_to_mesh` reads to give the cloth DIFFUSE_BURLEY and no rim
    while the skin and the face keep the cast's DIFFUSE_TOON.

    THIS IS THE PASS THAT NARROWS THE y1o.22 RULING (the cast stays DIFFUSE_TOON),
    and it does so by the owner's own pick of 2026-09-12 — GARMENTS only, and only
    because the spike's grid showed it is the one column that changes the 3 m
    frame. The same sentence is in `toon_shading.gd`'s banner, on the branch that
    reads this name.

    IT COSTS ONE DRAW CALL PER HERO. A second material slot is a second surface,
    so a hero on screen is two draws where it was one — measured as acceptable
    against three heroes on the web stand-in (bead 21m's [PERF] row), and the
    reason the split is TWO slots and never one per garment.
    """
    me = obj.data
    ids = _garment_group_ids(obj)
    me.materials.clear()
    for name in (SKIN_MATERIAL, CLOTH_MATERIAL):
        # THE DATABLOCK MUST BE REMOVED FIRST, and this is `build()`'s own
        # `base.001` trap one level down: `clear_scene()` unlinks OBJECTS and
        # leaves material datablocks in `bpy.data`, so in a session that builds
        # more than one hero — `--all`, which is the documented rebuild command —
        # the second `new()` would be handed `HeroCloth.001`, a name
        # `toon_shading.gd` compares with exact equality and therefore MISSES,
        # silently shading Windman's and Primm's garments as cast. Measured on the
        # td8 spike, where it made the `all` column an A+B column wearing a D
        # label; `--all` is now the only way this runs, so the trap is not
        # hypothetical, it is every rebuild after the first hero.
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
    beret; the groups are written by hand instead.

    A WEIGHT MAY BE A CALLABLE `(vertex) -> weight` (bead godot-test1-9k9n.1), for
    an accessory that spans more than one bone's worth of body: Phoboman's dragon
    lies across his whole belly, which three spine bones drive, and one constant
    per bone would make the tail and the head of the same serpent move together
    while the belly under them does not. `spine_split` is the one writer; the map
    it returns still sums to 1 at every height, which is what keeps this a JOIN
    and not a second rig.
    """
    for bone, weight in weights.items():
        vg = extra.vertex_groups.new(name=bone)
        if callable(weight):
            for v in extra.data.vertices:
                vg.add([v.index], weight(v), 'REPLACE')
        else:
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


# ===========================================================================
# PHOBOMAN'S DIVING HELMET AND HIS CHEST DRAGON — bead godot-test1-9k9n.1,
# epic 9k9n, owner ruling 2026-09-18 (option B).
#
# Phoboman was a part tree — one sphere for a belly, a helmet dropped on top of
# it, ten `.glb` files and the limb rig. He is a `HEROES` row now, which means his
# two unmistakable pieces have to be built on a MakeHuman body instead of on a
# 0.52 m ball. Both are ACCESSORIES in this file's sense: geometry joined into the
# one skinned mesh and weighted by hand, like the beret, the eyes and the coat
# tails, and not garments (nothing here goes in `CLOTH_VG`).
#
# THE DESIGN TARGET IS the retired part-tree generator, piece for piece and
# colour for colour (bead godot-test1-9k9n.3 deleted its script) —
# `create_head_assembly`'s dome, collar, valve knob,
# rivets, porthole rim, glass, broth, highlight, noodle eyes, herb nose and
# strands, and `create_torso_assembly`'s swept red serpent with its gold horns,
# eyes, whiskers and claw tufts. What changes is WHERE each piece sits, and that
# is the beret's lesson from bead z3e.15, restated: a saucer sized for a 0.25 m
# sphere floats 8 cm off a MakeHuman skull. So the generator's internal
# proportions are kept as ONE affine map — a single scale `k` and a single seat —
# and the two numbers that feed that map are MEASURED on the body:
#
#   the dome's radius   the smallest dome that swallows this hero's own skull
#                       (`HELMET_CLEAR` of air), found by growing it until every
#                       head vertex above the neck joint is inside it.
#   the seat            chosen so the generator's own porthole height lands on
#                       this hero's own EYE LINE. The face behind the glass is
#                       then where a face goes, whatever the macros did.
#
# The collar lands where that map puts it, which is on the shoulders, and the
# assert below says so out loud: the collar is what hides the neck join ("no neck
# by design", today's phoboman.tscn), so a collar up by the ears is a build
# failure and not a judgement call.
# ===========================================================================

GEN_DOME_R = 0.27        # `create_head_assembly`'s own dome radius: the unit every
                         # other number in that function is written against, and
                         # therefore the divisor of this port's one scale. (The
                         # dragon has no such divisor: it is fitted to the belly it
                         # lies on rather than scaled from the generator's `BODY_R`
                         # — see `DRAGON_REACH`.)

HELMET_CLEAR = 0.055     # air between the skull's own surface and the dome. A
                         # DEEP-SEA DIVING HELMET IS NOT A CRASH HELMET: the head
                         # floats inside it, and the canon asks for a "wide dome"
                         # (the generator's was 0.54 m across, on a body that was
                         # one sphere). It is also the knob that tops the figure
                         # out: the dome's radius is the only free length in the
                         # assembly, the whole helmet scales with it, and 55 mm of
                         # air puts the valve knob at 1.80 m — where bead
                         # godot-test1-9ynx put the rest of the cast. Measured,
                         # not chosen: 22 mm (the smallest dome that encloses the
                         # skull) stopped the figure at 1.7605.
HELMET_FLAT = 0.94       # THIS PORT'S OWN, and the fourth departure in
                         # `build_helmet`'s list: `create_head_assembly` scales its
                         # dome (1.0, 1.02, 1.0), so it is deepened and not
                         # flattened at all — "a sphere flattened a touch" is that
                         # function's docstring describing something its code does
                         # not do. A diving helmet IS flatter than a ball and the
                         # canon asks for a "wide dome", so the docstring is taken
                         # over the code here. It is not inert: `outside()` uses it
                         # as the dome's z semi-axis, so a flatter dome has to grow
                         # WIDER to swallow the same skull, and the width is what
                         # scales the whole assembly and the figure's total height.
HELMET_DEEP = 1.02       # ... and this one is the generator's, verbatim.
HELMET_R_MAX = 0.40      # a dome wider than this is not a helmet, it is a bug in
                         # the head measurement — the growth loop's fence.
HELMET_STEP = 0.002      # and how finely it grows
HELMET_COLLAR = (-0.10, 0.04)   # where the collar ring may land, relative to the
                                # neck joint: on the shoulders, not on the ears
HELMET_FACE_PROUD = 0.004       # how far the bowl of soup stands off the dome's
                                # own surface, and `HELMET_FACE_FLAT` how much of
                                # the generator's depth spread between the broth,
                                # the noodles and the herb nose survives — both in
                                # the generator's units, both read by `fy` below.
HELMET_FACE_FLAT = 0.6
HELMET_TRIS = (1600, 3400)      # the budget, asserted where it is spent

# WHERE THE SERPENT RUNS ACROSS THE BELLY, as a fraction of its half-width: the
# canon's "starting from the left side and stretching to the middle"
# (`docs/characters/phoboman.md`), taken literally. The generator could not express
# this — its dragon is drawn on a sphere whose centre IS the character's centre, so
# it is scaled about the middle and reaches as far right as it does left.
#
# BOTH ENDS ARE MEASURED, and both of them by an assert that fired.
#
#   the RIGHT end is a hard limit, and it is the HANDS. The hero ships with his arms
#   5 degrees off vertical (`apply_pose_as_rest`) and his hands beside his hips,
#   which on a body this wide is over the belly's own flank. An earlier build of
#   this bead scaled the generator's path 1.6x about the centre and put the dragon's
#   head 4.6 mm from the right hand — 43 hand vertices inside its head sphere, found
#   by eye on `grid_33`'s 3/4 column. At 0.45 the clearance is 83.2 mm, and
#   `assert_clear_of_arms` is the guard that measures it every build.
#   the LEFT end is the TRUNK's own silhouette. 0.90 put the tail's top waypoint at
#   x -0.224, which at its own height (z 1.253, the upper chest, where a fat man is
#   narrower than at his waist) is off the front of him — `surface()` refused it.
#
# And the width between them is the boldness: the serpent's body is 7.0 cm across at
# the head, which is what it has to be to read red-on-blue at the 3 m the game is
# judged at. That is the trade if these ever move.
DRAGON_REACH = (-0.70, 0.45)
# The generator's own path PLUS the head assembly hung off its last waypoint, as an
# x span in ITS units: the tail's radius at one end, the snout's far edge at the
# other. `DRAGON_REACH` is mapped onto this, so those fractions bound the whole
# animal and not just its spine — which is the half of it the round-2 review found
# hanging off the body.
DRAGON_GEN_X = (-0.23, 0.33)
DRAGON_PROUD = 0.012     # the generator's own standoff, and world metres like
                         # every other argument to `surface()`'s `proud`: the tube's
                         # CENTRE line stands this far off the belly, so part of it
                         # is sunk in and it reads as embossed art rather than as a
                         # snake lying on a man. How much part varies along the
                         # serpent, because the standoff does NOT scale with it —
                         # measured on the shipped build, 12 mm against a 16 mm tail
                         # radius (a quarter buried) and against a 35 mm head radius
                         # (two thirds). That is the generator's own behaviour, not
                         # a slip: its radii vary the same way against the same flat
                         # 0.012, and a tail that buried two thirds of itself would
                         # be a tail nobody can see.
DRAGON_WHISKER_PROUD = 0.020   # ... and the generator's own extra for the gold
                               # whiskers, which flick off the belly rather than
                               # lying on it
DRAGON_TRIS = (600, 1800)


def _painted(obj, colour):
    """One flat `FLOAT_COLOR` vertex colour over a whole primitive, in the
    attribute name and domain the body's own paint uses — so a join merges the
    two instead of dropping one (`build_eyes` is the precedent, per sphere)."""
    attr = obj.data.color_attributes.new(name="Color", type='FLOAT_COLOR',
                                         domain='POINT')
    for i in range(len(obj.data.vertices)):
        attr.data[i].color = colour
    obj.data.color_attributes.active_color = attr
    obj.data.attributes.active_color = attr
    return obj


def _piece(name, colour, matrix):
    """The primitive `bpy.ops` just added, moved into place and painted.

    The transform goes on the mesh DATA and not on the object, so nothing has to
    be applied afterwards and `bpy.ops.object.join()` cannot drop it."""
    obj = bpy.context.active_object
    obj.name = name
    obj.data.transform(matrix)
    obj.data.update()
    return _painted(obj, colour)


def _join_pieces(pieces, name):
    for o in bpy.data.objects:
        o.select_set(o in pieces)
    bpy.context.view_layer.objects.active = pieces[0]
    bpy.ops.object.join()
    joined = bpy.context.active_object
    joined.name = name
    return joined


# A disc or a ring built on the XY plane, turned to look out of the face (+Y in
# this script's frame, which glTF's Y-up conversion lands on Godot's -Z: trap 3).
FACING_FRONT = Matrix.Rotation(-math.pi / 2.0, 4, 'X')


def _tube_seat(p0, p1, radius, sections=8):
    """Add a cylinder and return the matrix that lays it from `p0` to `p1` — the
    pair `_piece` wants, like every `bpy.ops.mesh.primitive_*_add` above it.

    The dragon's body segments and its claw tufts — its two callers, and the two
    pieces of it that are drawn between a pair of endpoints; the horns and the
    whiskers are seated by an anchor and an angle instead and add their own
    cylinder. The round joint spheres the generator already drops at every waypoint
    are what make the chain read as one continuous serpent, which is the same thing
    its capsules did for a tenth of the triangles."""
    p0, p1 = Vector(p0), Vector(p1)
    axis = p1 - p0
    if axis.length < 1e-6:
        raise AssertionError("zero-length tube at %s" % (tuple(p0),))
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=axis.length,
                                        vertices=sections)
    return (Matrix.Translation((p0 + p1) / 2.0)
            @ Vector((0.0, 0.0, 1.0)).rotation_difference(axis).to_matrix().to_4x4())


def build_helmet(colours, obj, tj):
    """The brass diving helmet, with the pho bowl in its visor, as ONE mesh, seated
    on this hero's own skull.

    `obj` and not the beret's bare `crown_z`, because a dome has to SWALLOW a head
    rather than sit on it: the radius is read off the skull's own extent and the
    enclosure is asserted, which a single crown height cannot express.

    Every piece is `create_head_assembly`'s, in its order, at its size times one
    scale `k`. FOUR DEPARTURES, each written up where it is made. The first three
    are one cause — that assembly was authored for a renderer it never had:

      the bowl        `create_head_assembly` hangs the broth and its noodles
                      INSIDE the dome — 6 cm behind its own front surface, with an
                      opaque glass disc in between. Nothing in this cast is
                      transparent, so that is a face sealed in a sphere and
                      invisible from every angle. The bowl sits ON the dome here
                      (`apex`, `fy`), and the arithmetic is at `apex`.
      the glass       and for the same reason the pane in front of it is a lid,
                      so it is a bevel RING around the soup instead.
      the noodles     the generator turns each strand OUT of the porthole plane,
                      so its "swirly noodle strands across the lower broth" are
                      four stubs pointing at the camera. They lie in the glass
                      plane here, tilted by the generator's own angles.

    And the fourth is a judgement and not a fix: `HELMET_FLAT` flattens the dome,
    which that function's docstring says it does and its code does not.
    """
    head_ids = _vg_ids(obj, ["head"])
    co = [v.co.copy() for v in obj.data.vertices
          if _group_weight(v, head_ids) > 0.5]
    if len(co) < 32:
        raise AssertionError("only %d head vertices: the helmet has no skull to "
                             "be measured against" % len(co))
    eye_z = (tj["l-eye"].z + tj["r-eye"].z) / 2.0
    neck_z = tj["neck"].z
    # `GOGGLE_SLAB` is the goggles' own "a band of head this thick is the face",
    # and the question here is the same one: where the skull's centre is, rather
    # than the body's (`_skull_axis` has the why).
    axis = _skull_axis(obj, eye_z - GOGGLE_SLAB, eye_z + GOGGLE_SLAB)
    skull = [c for c in co if c.z > neck_z]
    if not skull:
        raise AssertionError("no head vertex above the neck joint at z=%.3f" % neck_z)

    def seat(radius):
        """The dome's own centre, for a dome of this radius. It is the ONE degree
        of freedom left once the radius is fixed, and it is spent on the eye line:
        in the generator's frame the dome's centre sits 0.86 of a dome radius above
        the helmet's base and the porthole 0.92 of one, so putting the porthole on
        the eye line puts the centre 0.06 of a radius below it."""
        return eye_z - 0.06 * radius

    def outside(radius):
        """Head vertices above the neck that a dome of this radius does not cover."""
        dome_z = seat(radius)
        return [c for c in skull
                if ((c.x - axis.x) / radius) ** 2
                + ((c.y - axis.y) / (radius * HELMET_DEEP)) ** 2
                + ((c.z - dome_z) / (radius * HELMET_FLAT)) ** 2 > 1.0]

    r = max(max(abs(c.x - axis.x) for c in skull),
            max(abs(c.y - axis.y) for c in skull)) + HELMET_CLEAR
    while r < HELMET_R_MAX and outside(r):
        r += HELMET_STEP
    proud = outside(r)
    if proud:
        raise AssertionError(
            "%d head vertex(es) poke through a %.3f m dome — the head measurement "
            "is wrong or this hero has no head (highest %.4f, crown %.4f)"
            % (len(proud), r, max(c.z for c in proud), max(c.z for c in skull)))
    k = r / GEN_DOME_R
    dome_z = seat(r)
    base_z = dome_z - 0.86 * r      # the generator's local z = 0, the helmet's base

    def g(x, y, z):
        """A point of the generator's own frame, in the game frame."""
        return Vector((axis.x + x * k, axis.y + y * k, base_z + z * k))

    port_z = GEN_DOME_R * 0.92       # the generator's names, kept so the port
    port_r = 0.165                   # reads against `create_head_assembly`
    # WHERE THE DOME'S OWN SURFACE IS AT THE PORTHOLE, in the generator's units.
    # `create_head_assembly` put the soup and its noodles INSIDE the dome, and the
    # three numbers say the rest: its broth disc sits at y = 0.86*0.27 - 0.02 =
    # 0.2122, its opaque `glass` disc at 0.2522, and the dome's own opaque surface
    # at 0.2754. Nothing of that face can be seen from the front by any renderer in
    # this game — there is no transparency in the cast. So the bowl sits ON the dome
    # here, a few millimetres proud, framed by the rim that still hugs the curve —
    # which is what `assets/portraits/phoboman.png` draws and what the canon means
    # by "the open visor of the helmet shows the soup".
    apex = GEN_DOME_R * HELMET_DEEP * math.sqrt(max(0.0, 1.0 - (
        (port_z - GEN_DOME_R * 0.86) / (GEN_DOME_R * HELMET_FLAT)) ** 2))
    face_y = apex + HELMET_FACE_PROUD - 0.02   # the broth disc is 0.04 deep

    def fy(offset):
        """A face feature's own depth, the generator's offset off the broth,
        FLATTENED: those offsets were free to spread 6 cm inside a hollow dome and
        here every millimetre of them is a millimetre the porthole bulges."""
        return face_y + offset * HELMET_FACE_FLAT

    pieces = []

    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=18, ring_count=10)
    pieces.append(_piece(
        "HelmetDome", colours["helmet_gold"],
        Matrix.Translation(Vector((axis.x, axis.y, dome_z)))
        @ Matrix.Diagonal(Vector((1.0, HELMET_DEEP, HELMET_FLAT, 1.0)))))

    collar_z = g(0.0, 0.0, 0.03).z
    lo, hi = HELMET_COLLAR
    if not neck_z + lo <= collar_z <= neck_z + hi:
        raise AssertionError(
            "the collar lands at %.4f, outside the neck joint's %.4f%+.2f..%+.2f "
            "band — it is what hides the neck join, so it belongs on the shoulders"
            % (collar_z, neck_z, lo, hi))
    bpy.ops.mesh.primitive_torus_add(major_radius=0.235 * k, minor_radius=0.045 * k,
                                     major_segments=20, minor_segments=8)
    pieces.append(_piece("HelmetCollar", colours["helmet_dark"],
                         Matrix.Translation(g(0.0, 0.0, 0.03))))

    bpy.ops.mesh.primitive_cylinder_add(radius=0.045 * k, depth=0.05 * k, vertices=12)
    pieces.append(_piece("HelmetKnob", colours["helmet_dark"],
                         Matrix.Translation(g(0.0, 0.0, GEN_DOME_R * 1.72 + 0.02))))
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.035 * k, segments=10, ring_count=6)
    pieces.append(_piece("HelmetKnobTop", colours["helmet_gold"],
                         Matrix.Translation(g(0.0, 0.0, GEN_DOME_R * 1.72 + 0.07))))

    bpy.ops.mesh.primitive_torus_add(major_radius=port_r * k, minor_radius=0.028 * k,
                                     major_segments=20, minor_segments=8)
    pieces.append(_piece("HelmetPortRim", colours["helmet_dark"],
                         Matrix.Translation(g(0.0, GEN_DOME_R * 0.86, port_z))
                         @ FACING_FRONT))

    for i in range(10):
        ang = i * (2.0 * math.pi / 10.0)
        rx = math.cos(ang) * port_r
        rz = port_z + math.sin(ang) * port_r
        ry = math.sqrt(max(GEN_DOME_R ** 2 - rx * rx, 0.0)) * 0.92 + 0.03
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.017 * k, segments=6, ring_count=4)
        pieces.append(_piece("HelmetRivet%d" % i, colours["helmet_dark"],
                             Matrix.Translation(g(rx, ry + 0.02, rz))))

    # THE GLASS IS A BEVEL AND NOT A PANE, and it is the one piece of
    # `create_head_assembly` this port does not build as it stands. There is no
    # transparency anywhere in this cast — vertex colour on an opaque toon
    # material — so the generator's disc, which sits 4 cm in FRONT of the broth at
    # very nearly the porthole's own radius, is a lid: the first build of this bead
    # rendered a pale blue plate with two eyes and a nose poking through it, where
    # `assets/portraits/phoboman.png` and the canon both put the soup ("the open
    # visor of the helmet shows the soup"). A ring at the same height shows what
    # the portrait shows — a bright glazed edge round the broth — and the bowl
    # behind it. Same colour, same place, same 20 sections; a disc's worth of
    # triangles for a ring.
    bpy.ops.mesh.primitive_torus_add(major_radius=(port_r - 0.030) * k,
                                     minor_radius=0.014 * k,
                                     major_segments=20, minor_segments=6)
    pieces.append(_piece("HelmetGlass", colours["glass"],
                         Matrix.Translation(g(0.0, fy(0.04), port_z)) @ FACING_FRONT))

    # THE PHO, IN THE VISOR: broth, the bright pool along its top rim, two
    # noodle eyes with dark pupils, the green herb nose and its flecks, and the
    # slurped noodle tangle across the bottom. The canon's "face inside the
    # helmet", and the reason this row carries no `FACES` recipe at all.
    bpy.ops.mesh.primitive_cylinder_add(radius=(port_r - 0.02) * k,
                                        depth=0.04 * k, vertices=20)
    pieces.append(_piece("PhoBroth", colours["broth"],
                         Matrix.Translation(g(0.0, face_y, port_z)) @ FACING_FRONT))

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.05 * k, segments=10, ring_count=6)
    pieces.append(_piece("PhoHighlight", colours["broth_hi"],
                         Matrix.Translation(g(0.0, fy(0.01), port_z + 0.10))
                         @ Matrix.Diagonal(Vector((1.6, 0.4, 0.45, 1.0)))))

    eye_gz = port_z + 0.045
    for side, ex in (("L", -0.058), ("R", 0.058)):
        bpy.ops.mesh.primitive_torus_add(major_radius=0.040 * k,
                                         minor_radius=0.014 * k,
                                         major_segments=14, minor_segments=6)
        pieces.append(_piece("PhoEyeRing" + side, colours["noodle"],
                             Matrix.Translation(g(ex, fy(0.05), eye_gz)) @ FACING_FRONT))
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.028 * k, segments=10,
                                             ring_count=6)
        pieces.append(_piece("PhoPupil" + side, colours["eye_dark"],
                             Matrix.Translation(g(ex, fy(0.062), eye_gz))
                             @ Matrix.Diagonal(Vector((1.0, 0.7, 1.0, 1.0)))))

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.028 * k, segments=10, ring_count=6)
    pieces.append(_piece("PhoNose", colours["nose_green"],
                         Matrix.Translation(g(0.0, fy(0.04), port_z - 0.01))
                         @ Matrix.Diagonal(Vector((1.1, 0.7, 1.3, 1.0)))))
    for i, (hx, hz) in enumerate(((-0.05, -0.04), (0.055, -0.05), (0.0, -0.085))):
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.013 * k, segments=6,
                                             ring_count=4)
        pieces.append(_piece("PhoHerb%d" % i, colours["nose_green"],
                             Matrix.Translation(g(hx, fy(0.03), port_z + hz))))

    # THE STRANDS LIE IN THE GLASS PLANE, which is the third departure in this
    # function's docstring: `create_head_assembly` turns each one out of that plane
    # with a second 90-degree X rotation after the tilt, so its "swirly noodle
    # strands across the lower broth" end up four stubs pointing at the camera.
    # Only the tilt is applied here.
    for i, (sx, sz, sl, rot) in enumerate(((-0.07, -0.06, 0.10, 20),
                                           (0.05, -0.07, 0.09, -25),
                                           (-0.02, -0.095, 0.08, 10),
                                           (0.07, -0.04, 0.07, 35))):
        bpy.ops.mesh.primitive_cylinder_add(radius=0.009 * k, depth=sl * k,
                                            vertices=6)
        pieces.append(_piece(
            "PhoNoodle%d" % i, colours["noodle"],
            Matrix.Translation(g(sx, fy(0.03), port_z + sz))
            @ Matrix.Rotation(math.radians(rot), 4, 'Y')))

    helmet = _join_pieces(pieces, "Helmet")
    tris = _tri_count(helmet.data)
    log("helmet: radius %.4f m (scale %.3f), seat z %.4f, collar %.4f (neck %.4f), "
        "top %.4f, %d pieces, %d tris"
        % (r, k, base_z, collar_z, neck_z,
           max(v.co.z for v in helmet.data.vertices), len(pieces), tris))
    if not HELMET_TRIS[0] <= tris <= HELMET_TRIS[1]:
        raise AssertionError("the helmet is %d tris, outside the %d-%d budget"
                             % (tris, HELMET_TRIS[0], HELMET_TRIS[1]))
    return helmet


def spine_split(armature):
    """Per-vertex weights that hand a belly-wide accessory to the three spine
    bones by HEIGHT — `join_weighted`'s callable form, and the dragon's only
    caller.

    `hero_rig_skeleton.gd` writes all three spine bones (the lean, the twist and
    the breathing), so a serpent that runs from the hips to the chest on one of
    them tears away from the belly under it at every stride. The blend is the
    plainest partition of unity there is — linear between neighbouring bone
    heads, flat outside the pair — which is what a linear-blend skin does to the
    body's own vertices at the same heights.

    The bone heads are read off the REST data (`head_local`), because `reframe`
    transformed that and trap 6 says the pose bones still answer in the old frame.
    """
    zs = [armature.data.bones["spine_%02d" % n].head_local.z for n in (1, 2, 3)]
    if not zs[0] < zs[1] < zs[2]:
        raise AssertionError("the spine bones are not stacked: %s" % (zs,))

    def blend(z):
        if z <= zs[0]:
            return (1.0, 0.0, 0.0)
        if z >= zs[2]:
            return (0.0, 0.0, 1.0)
        i = 0 if z <= zs[1] else 1
        t = (z - zs[i]) / (zs[i + 1] - zs[i])
        w = [0.0, 0.0, 0.0]
        w[i], w[i + 1] = 1.0 - t, t
        return tuple(w)

    # THE CHECK: a blend that does not sum to 1 is a vertex that shrinks toward
    # the origin as the spine moves, and `report_weights` cannot see it (it only
    # catches a total of ZERO). Thirteen samples across the range and two past
    # each end, here, where the function is.
    for n in range(-2, 15):
        z = zs[0] + (zs[2] - zs[0]) * n / 12.0
        total = sum(blend(z))
        if abs(total - 1.0) > 1e-9:
            raise AssertionError("spine_split(%.4f) sums to %.6f, not 1" % (z, total))
    log("dragon weights: spine_01/02/03 rest heads at z %.4f / %.4f / %.4f"
        % tuple(zs))
    return {"spine_%02d" % (n + 1): (lambda i: lambda v: blend(v.co.z)[i])(n)
            for n in (0, 1, 2)}


DRAGON_ARM_CLEAR = 0.020    # how much air the dragon must leave around an ARM in
                            # the SHIPPED rest, measured after `apply_pose_as_rest`
ARM_BONES = ["upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r",
             "hand_l", "hand_r"]


def assert_clear_of_arms(obj, first_vert, clearance=DRAGON_ARM_CLEAR):
    """No vertex of the accessory joined at `first_vert` may be in an arm.

    THE WHOLE ARM AND NOT JUST THE HAND, although the hand is what this was written
    for: an arm hanging at 5 degrees puts its elbow over the widest part of a belly
    like this one, and on the shipped build the tightest clearance is the UPPER ARM
    and not the fist (59.8 mm against the hand's 83.2)."

    RUN AFTER `apply_pose_as_rest`, AND THAT IS THE WHOLE POINT. `build_dragon`
    measures a body in MakeHuman's A-pose, where the arms stand 41 degrees off
    vertical and the hands are out at the sides; the hero ships with them 5 degrees
    off vertical, beside his hips — which on a wide, short body is exactly where the
    belly's flank is. So a dragon that lies on the belly at build time can be inside
    a fist at export time, and nothing upstream can see it: `surface()` asks where
    the belly is, `report_weights` asks whether a vertex is driven, and a head
    modelled 2 cm proud of the skin two bones away from its own is neither question.
    Measured 2026-09-18 on the first build of bead 9k9n.1: 43 hand vertices inside
    the dragon's head sphere, found by eye on `grid_33`'s 3/4 column.

    A join APPENDS, so the accessory is exactly the vertices past `first_vert` — the
    coat tails' idiom.
    """
    ids = _vg_ids(obj, ARM_BONES)
    arm = [v.co for v in obj.data.vertices if _group_weight(v, ids) > 0.5]
    if not arm:
        raise AssertionError("no arm vertices: this hero has no arms to clear")
    xs = [c.x for c in arm]
    zs = [c.z for c in arm]
    worst, at = 1e9, None
    for v in obj.data.vertices[first_vert:]:
        for h in arm:
            d = (v.co - h).length
            if d < worst:
                worst, at = d, v.co.copy()
    log("arm clearance: %.1f mm (floor %.0f), nearest accessory vertex %s; arms "
        "x %.3f..%.3f z %.3f..%.3f"
        % (worst * 1000.0, clearance * 1000.0,
           tuple(round(c, 3) for c in at), min(xs), max(xs), min(zs), max(zs)))
    if worst < clearance:
        raise AssertionError(
            "the accessory joined at vertex %d comes %.1f mm of an arm in the "
            "shipped rest (floor %.0f mm), nearest at %s — it was modelled on the "
            "A-pose body and the arms have come down since"
            % (first_vert, worst * 1000.0, clearance * 1000.0,
               tuple(round(c, 3) for c in at)))


def build_dragon(colours, obj, tj):
    """`create_torso_assembly`'s red Chinese dragon, laid on the BELLY's own
    surface: the same eight waypoints, the same taper, the same gold horns, eyes,
    whiskers and claw tufts, and the same 1.2 cm of standoff.

    THE SURFACE IS READ BY RAY, not computed. The generator projected its
    waypoints onto a sphere it had just built, and knew the answer in closed
    form; this belly is a decimated MakeHuman torso that has since been morphed,
    dressed, folded and pushed 2 cm proud by its own garment shell, and the only
    honest question to ask it is where its front is at a point. `_face_front` is
    already that question (bead nvy asked it of a brow); this asks it of a belly.
    """
    from mathutils.bvhtree import BVHTree
    me = obj.data
    torso_ids = _vg_ids(obj, REGION_BONES["torso"])
    lo, hi = tj["pelvis"].z, tj["neck"].z
    # THE TREE IS THE TRUNK AND NOTHING ELSE. A ray cast at the whole body answers
    # "where is the first surface in front of this point", and at the flanks the
    # first surface can be an ARM — MakeHuman rests in an A-pose here, so a hand
    # hangs level with the hip. `surface()` below would then seat a segment on a
    # forearm and report success. Filtered, the same ray finds nothing there and
    # the assert fires, which is what a guard whose message says "off this hero's
    # own front" has to mean.
    #
    # TWO BONE SETS, AND THEY ARE TWO DIFFERENT QUESTIONS. The tree is the surface
    # the dragon may lie on, which is the blue shell's own scope (`garments`, the
    # first row) — clavicles included, because the tail tip reaches the upper chest.
    # `belly` below is the MEASUREMENT the path is scaled against, and that is the
    # belly proper: a waist half-width, not a shoulder one.
    shell_ids = _vg_ids(obj, TORSO_BONES + ["pelvis"])
    trunk = {i for i, v in enumerate(me.vertices)
             if _group_weight(v, shell_ids) > 0.5}
    bvh = BVHTree.FromPolygons(
        [tuple(v.co) for v in me.vertices],
        [tuple(p.vertices) for p in me.polygons
         if all(i in trunk for i in p.vertices)])
    belly = [v.co for v in me.vertices
             if _group_weight(v, torso_ids) > 0.5 and lo <= v.co.z <= hi]
    if len(belly) < 64:
        raise AssertionError("only %d torso vertices between z %.3f and %.3f: the "
                             "dragon has no belly to lie on" % (len(belly), lo, hi))
    cx = (min(c.x for c in belly) + max(c.x for c in belly)) / 2.0
    half_w = max(abs(c.x - cx) for c in belly)
    half_h = (hi - lo) / 2.0
    mid = (hi + lo) / 2.0
    # ONE SCALE AND ONE SHIFT, both read off `DRAGON_REACH`: the generator's whole
    # animal is mapped onto that span of this hero's own belly. The scale is then
    # used on z as well, because the path is drawn on a round sphere and keeping its
    # aspect is what keeps the serpent a serpent.
    lo_f, hi_f = DRAGON_REACH
    k = (hi_f - lo_f) * half_w / (DRAGON_GEN_X[1] - DRAGON_GEN_X[0])
    x0 = cx + lo_f * half_w - DRAGON_GEN_X[0] * k

    def surface(x, z, proud=DRAGON_PROUD):
        """The generator's `_project_to_sphere`, asked of the real belly."""
        px, pz = x0 + x * k, mid + z * k
        py = _face_front(bvh, px, pz)
        if py is None or py <= 0.0:
            raise AssertionError(
                "no belly surface in front of (%.4f, %.4f) — the dragon's %s "
                "waypoint is off this hero's own front" % (px, pz, (x, z)))
        return Vector((px, py + proud, pz))

    path_xz = [(-0.20, 0.26),    # tail tip, at the hero's left flank
               (-0.06, 0.20),
               (0.05, 0.09),
               (0.09, -0.03),
               (0.01, -0.13),
               (-0.08, -0.20),
               (0.02, -0.26),
               (0.15, -0.27)]    # head end, lower and centre-right of the belly
    pts = [surface(x, z) for x, z in path_xz]
    radii = [(0.030 + (0.064 - 0.030) * i / (len(pts) - 1.0)) * k
             for i in range(len(pts))]
    pieces = []
    for i in range(len(pts) - 1):
        m = _tube_seat(pts[i], pts[i + 1], (radii[i] + radii[i + 1]) / 2.0,
                       sections=8)
        pieces.append(_piece("DragonSeg%d" % i, colours["dragon_red"], m))
    for i, p in enumerate(pts):
        bpy.ops.mesh.primitive_uv_sphere_add(radius=radii[i] * 1.05, segments=8,
                                             ring_count=5)
        pieces.append(_piece("DragonJoint%d" % i, colours["dragon_red"],
                             Matrix.Translation(p)))

    # THE HEAD RIDES THE BELLY, like every segment behind it. The generator hung
    # its head, snout, horns and eyes off the last waypoint by a plain offset,
    # which is exact on a sphere it had just built and wrong on a body: 9 cm to
    # character-right of that waypoint the belly has already curved away, so a
    # snout placed at the ANCHOR's own depth floats off the front. Each piece goes
    # through `surface()` at its own (x, z) instead, which also means the same
    # assert that catches a waypoint off the front now catches a snout off it —
    # the review of round 2 found this one by reading `grid_33` and it was
    # invisible from the source.
    head_x, head_z = path_xz[-1]

    def off(dx, dy, dz):
        return Matrix.Translation(surface(head_x + dx, head_z + dz,
                                          DRAGON_PROUD + dy * k))

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.085 * k, segments=10, ring_count=6)
    pieces.append(_piece("DragonHead", colours["dragon_red"],
                         off(0.04, 0.01, -0.02)
                         @ Matrix.Diagonal(Vector((1.25, 0.9, 1.0, 1.0)))))
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.05 * k, segments=8, ring_count=5)
    pieces.append(_piece("DragonSnout", colours["dragon_red"],
                         off(0.11, 0.0, -0.04)
                         @ Matrix.Diagonal(Vector((1.4, 0.9, 0.85, 1.0)))))
    for side, hx in (("L", -0.025), ("R", 0.025)):
        bpy.ops.mesh.primitive_cylinder_add(radius=0.011 * k, depth=0.06 * k,
                                            vertices=6)
        pieces.append(_piece("DragonHorn" + side, colours["dragon_gold"],
                             off(hx, 0.02, 0.06)
                             @ Matrix.Rotation(math.radians(-30), 4, 'X')))
    for side, hx in (("L", -0.015), ("R", 0.035)):
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.012 * k, segments=6,
                                             ring_count=4)
        pieces.append(_piece("DragonEye" + side, colours["dragon_gold"],
                             off(hx + 0.03, 0.04, 0.0)))
    for i, (wx, wz, wr) in enumerate(((0.20, -0.24, 40), (0.20, -0.31, -20))):
        bpy.ops.mesh.primitive_cylinder_add(radius=0.008 * k, depth=0.08 * k,
                                            vertices=6)
        pieces.append(_piece("DragonWhisker%d" % i, colours["dragon_gold"],
                             Matrix.Translation(surface(wx + 0.04, wz,
                                                        DRAGON_WHISKER_PROUD))
                             @ Matrix.Rotation(math.radians(wr), 4, 'Y')))
    for i, (clx, clz) in enumerate(((0.06, 0.04), (0.03, -0.10), (-0.05, -0.18))):
        m = _tube_seat(surface(clx, clz), surface(clx + 0.05, clz - 0.05, 0.0),
                       0.016 * k, sections=6)
        pieces.append(_piece("DragonClaw%d" % i, colours["dragon_red"], m))

    dragon = _join_pieces(pieces, "Dragon")
    tris = _tri_count(dragon.data)
    log("dragon: scale %.3f on a %.3f x %.3f m belly (centre x %.4f, z %.4f), "
        "x %.4f..%.4f, %d pieces, %d tris"
        % (k, half_w * 2.0, half_h * 2.0, cx, mid,
           min(v.co.x for v in dragon.data.vertices),
           max(v.co.x for v in dragon.data.vertices), len(pieces), tris))
    if not DRAGON_TRIS[0] <= tris <= DRAGON_TRIS[1]:
        raise AssertionError("the dragon is %d tris, outside the %d-%d budget"
                             % (tris, DRAGON_TRIS[0], DRAGON_TRIS[1]))
    return dragon


# ---------------------------------------------------------------------------
# PRIMM'S GOGGLES — bead godot-test1-nvy, and the end of the third attempt to
# paint them. OWNER, 2026-09-12: "primm's goggles don't look like goggles, they
# look like a headband. But they ARE goggles — with rectangular lenses."
#
# He is describing a z-band of colour across the face, which is all `stripes`
# could ever be: bead z3e.5 measured the band, z3e.15 reversed its contrast (a
# dark frame around a bright cyan lens) and narrowed it, and a narrower band of
# colour is still a band of colour. `assets/portraits/primm.png` draws a WIDE
# VISOR — a dark frame with a straight top bar, two large rectangular cyan lenses
# joined over the nose, arms going back to the temples — and none of that is a
# height range on a cheek.
#
# SO THEY ARE GEOMETRY, BY THE SAME IDIOM AS THE WRAP (`wrap_band`, bead z3e.13):
# the head's own outline is measured at eye height and everything is seated on it,
# so the frame follows the skull instead of a circle somebody typed. What is NOT
# the wrap's idiom is how it gets there — the wrap LIFTS the face's own surface,
# which consumes the eye sockets under it, and the canon's lenses have eyes behind
# them. So this is new geometry, joined and weighted like the beret (`join_rigid`
# to `head`, which is what makes the pair ride the head bobble), and it is an
# ACCESSORY and not a GARMENT: no `dress_shells` shell, no cloth mark, no
# `HeroCloth` slot. A lens is not made of cloth.
#
# THE RING IS ONE RING. Frame, arms and strap are the same closed box-section tube
# round the skull at one height, changing cross-section by BEARING: the frame
# across the face, thin square arms over the ears, a flat strap round the back.
# Two pieces of tailoring for the price of one loop, and an arm cannot come away
# from the frame because it is the same tube.
#
# THE LENSES ARE OPAQUE, AND THE BEAD LICENSED THE CHOICE ("if it sorts badly,
# ship opaque cyan with a lighter rim strip, and say so"). It is not a sorting
# measurement, it is a material one: since bead 21m a hero exports exactly TWO
# materials, `HeroSkin` and `HeroCloth`, and the FACE is on `HeroSkin` — the same
# slot a lens would be on. Alpha there is alpha on the whole head, and a third
# material for two boxes is a third `ToonShading` branch, a third draw call and a
# transparent surface the renderer must sort against the hero it belongs to. The
# lighter rim is the lens's own top row of vertices, one step up: on a flat slab
# under DIFFUSE_TOON that gradient is what reads as glass.
#
# COLOURS: NOT bead z3e.15's stripe values, and the first render of this bead is
# why. Those were measured on PAINT lying on a cheek, which takes this scene's high
# key light at a grazing angle; every surface here is either raked into that light
# (the lens) or a tube that carries a horizontal top face and picks up
# `ToonShading`'s rim on `HeroSkin` (the frame), so both landed a stop or more
# brighter than the same number does on skin — the frame shipped at luma 171
# against a lens at 188, which is a pale bar beside its own lenses and not the
# portrait's dark one. Both are re-measured against the transfer this scene
# actually has (a linear albedo lifted by ~1.85 before the sRGB encode: skin 0.404
# renders 225), on the web `17_head_face` frame. The `*_edge`/`*_glint` entries are
# one step up from each: the frame's top bar, and the lens's "lighter rim strip".
# The palette rows in `HEROES["primm"]` carry the numbers and what each lands at.
#
# ROUND 2 — THE SIZE, bead godot-test1-khly. OWNER, 2026-09-16, twice, on
# `docs/style/z3e/grid_30_primm_goggles.png`: "goggles too small". Not the shape,
# not the colour: the FOOTPRINT. So this round is a measurement of the canon and
# not a taste, and the measurement is on `assets/portraits/primm.png` at the eye
# line (all of it in that image's own pixels, then carried over by the one ratio
# a portrait and a head share — how much of the head the thing covers):
#
#   head, hair included, at the eye line   x  84..182   99 px
#   the visor's dark frame, temple to temple  94..173   80 px   0.81 of the head
#   the LENS GLASS, the cyan pair              100..169   70 px   0.71 of the head
#   the lens glass, top of the lit bar to the bottom rim  y 64..95   31 px
#   the pupils                                            y ~84, 32 px apart
#
# and this head answers `_skull_reach` 0.0927 m at the ear, so 0.71 of it is
# 0.0655 m from the centre line, where round 1's outer corner landed at 0.047 —
# 0.53 of the head, which is the owner's complaint as a number. The pair is 131 mm
# across on a 185 mm head now, one lens is 68 x 34 against round 1's 44 x 18 (2.9x
# the glass), and the frame ring already goes wider than the canon's 0.81 because
# a ring goes all the way round. Vertically the canon's 31 px is ~49 mm at this
# scale, which is more lens than a slab standing proud of a nose can be without
# swallowing the nose; 34 mm is what covers the socket (16 mm each way off the
# pupil) plus the brow above it, and it is what is typed below. Everything that
# moves here moves because the lens grew: the bar goes up and gets thicker so it
# still reads as a bar ABOVE a lens and not a stripe across one, the splay goes up
# because an outer end 65 mm off the centre line is out where the temple has
# already turned away, and the standoff goes up because a 34 mm slab raked 15 deg
# has its top edge 4.4 mm behind its own centre and the old 4 mm was all of that.

# ROUND 3 — THE FRAME, bead godot-test1-w905. OWNER, 2026-09-16, on
# `docs/style/z3e/grid_31_primm_visor.png`: the pair still reads as a dark bar
# ABOVE two loose cyan plates, and what the canon has and this did not is "a frame
# AROUND the lenses". Three things were wrong and the round changes exactly those:
#
#   1. THE LENSES WERE OPEN ON THREE SIDES. Round 2's frame was the ring and the
#      ring alone — a bar over the top of the glass, nothing beside it and nothing
#      under it, so each lens ended in mid-cheek at a cyan edge. `_lens_rim` is
#      the missing three sides: a 3 mm box-section tube down the temple side, under
#      the glass and back up the nose side, its two ends run INTO the ring at that
#      bearing's own seat so the rim and the bar are one frame and not two parts.
#   2. THE SPLAY PIVOTED ON THE LENS'S CENTRE, which is why the glass stood off the
#      nose. Yawing a 68 mm slab 30 degrees about its middle pulls the outer end
#      17 mm back AND pushes the inner end 17 mm FORWARD — over the nose, which is
#      the one place on a face that has no room. The yaw is about the INNER END now:
#      that end stays where the bridge of the nose puts it and only the outer end
#      travels, which is what a wrap-around visor actually does. The BEAK goes with
#      the pivot, and that is the measurement: round 2's inner edge sat at y 0.196
#      (its own logged plane, 0.1790, plus half the width times sin 30) where the
#      nose bridge beside it reaches 0.174, and this one's sits at 0.1862 — 10 mm
#      back, with the glass leaning AWAY from the face across the whole span
#      instead of into it. The ANGLE came down with the pivot for the same reason:
#      the splay is how far the outer end sits behind the inner one, the outer end
#      still has to clear the temple, so a steeper one is paid for by the fit
#      pushing the WHOLE chord forward — and the inner edge back out over the nose.
#   3. A FLAT SLAB CANNOT GO TALLER, which is round 2's own deferral and the reason
#      the glass was 34 mm under a bar it did not touch. So the lens is not a slab:
#      it is two facets meeting on the PUPIL LINE, the upper one raked back to the
#      brow (`_TILT`, unchanged) and the lower one raked back harder toward the
#      cheek (`_LOWER_TILT`), with the inner end of the bottom edge cut away where
#      the nose comes forward (`_NOTCH`). That buys 46 mm of glass — the canon's
#      ~49 — with the top edge tucked under the bar and the bottom edge clear of
#      the nose instead of 5 mm inside it.
#
# AND THE UNIT WENT UP WITH IT. The ring is at eye+32 mm instead of eye+20 and the
# lens hangs off it: `_TUCK` under the bar's own lower face, 46 mm tall, which puts
# the glass centre 1.5 mm ABOVE the pupil line where round 2 hung it below both the
# bar and the eyes. The canon's visor runs from eye+37 mm to eye-21 mm at this
# scale; this one runs from the bar's top at eye+38 to the glass's bottom at
# eye-21.
#
# NOTHING POKES THROUGH ANYTHING, and that is fitted rather than argued: the seat
# itself is the deepest answer a grid of rays over the glass and its rim's own
# surface gives (`_face_front`), so the clearance holds by construction and the
# assert against `GOGGLE_LENS_CLEAR` is the floor under the knobs rather than a
# second opinion. The worst gap is logged either way. The lens's top edge clears
# the bar's lower face by `_TUCK` — the round-1 major of bead khly was a slab that
# shared the bar's height and rendered as a spike through it.

GOGGLE_STATIONS = 48          # cross-sections round the skull; 7.5 degrees apart
GOGGLE_FRAME_ARC = 72.0       # degrees off the nose where the frame hands over to
GOGGLE_ARM_ARC = 132.0        # the arm, and the arm to the strap (in front of the
                              # ear and behind it — the wrap's `half_angle` lesson:
                              # a ring at eye height that ignores the ears is one
                              # that goes THROUGH them. Here it does not have to
                              # stop, it only has to get thin and stand off.)
GOGGLE_RING_Z = 0.032         # the ring's centre above the eye line: the straight
                              # top bar of the portrait, with the lens under it —
                              # 12 mm higher than round 2 because the glass under
                              # it is 46 mm and centred on the pupils, and a bar
                              # that does not cap that glass is the loose bar the
                              # owner saw. The canon's own bar is at eye+37 mm.
GOGGLE_STANDOFF = 0.004       # how far proud of the skull's own outline it all
                              # stands — the bead's "4 mm proud of the eye sockets"
GOGGLE_FRAME = (0.005, 0.012)   # radial thickness, height — across the face. The
                                # 9 mm of round 1 was a bar over an 18 mm lens;
                                # over a 46 mm one it is piping. (Bead khly asked
                                # for "~8 mm", which is THINNER than what shipped
                                # — the owner asked for thicker, so it is 12.)
GOGGLE_ARM = (0.003, 0.003)     # square, over the ear
GOGGLE_STRAP = (0.003, 0.006)   # flat, round the back, sitting on the hair shell
GOGGLE_RIM = (0.003, 0.003)   # ROUND 3: the lower/side rim's section, square, the
                              # bead's "thin (3 mm) dark tube". It runs in the
                              # lens's own surface — not on a skull radius — so it
                              # frames the glass rather than crossing it.
GOGGLE_RIM_GROOVE = 0.001     # and it takes the glass into a GROOVE: the rim's
                              # centre line sits this far INSIDE the lens edge, so
                              # a 2 mm lens ends 1 mm deep in a 3 mm tube that is
                              # wider than it in every direction. Nothing pierces —
                              # the edge is swallowed, which is what a real rim
                              # does and what an offset-with-a-gap rim would not:
                              # two coplanar faces a hair apart is z-fighting, and
                              # a hairline of cheek between the frame and the glass
GOGGLE_LENS = (0.002, 0.046)  # thickness and height of one lens: the canon's glass
                              # is ~49 mm at this head's scale (bead khly measured
                              # it) and round 2 could only reach 34 because a flat
                              # slab that tall stands off the nose. Two facets can
                              # — see `_LOWER_TILT` and `_NOTCH`.
# AND ITS WIDTH IS MEASURED, NOT TYPED, because the bead's two numbers — "each ~32
# x 18 mm" and "a 6 mm bridge" — are only consistent on a head whose pupils are
# 38 mm apart, and this one's are 66. Taken literally they leave a 33 mm gap of
# frame between the lenses: a bridge wider than a lens, where the portrait draws
# the pair nearly meeting. So the lens is hung off its INNER end, `_GAP`/2 off the
# centre line, and reaches out to `_REACH` past the pupil.
GOGGLE_LENS_REACH = 0.033     # how far past the pupil the outer end sits — 0.71 of
                              # this head (bead khly's measurement of the canon's
                              # lens glass) is 65.5 mm off the centre line and the
                              # pupils are at 32.9, so 33. It is the CORNER that
                              # lands there now, not a mid-edge: since the yaw is
                              # about the inner end, the splay no longer eats into
                              # the reach and round 2's 37 would overshoot by 4.
GOGGLE_BRIDGE_GAP = 0.006     # how much daylight is left between the two lenses,
                              # and it is no longer opened by the splay (that
                              # pivots on this edge now). 6 and not 4 because each
                              # lens's rim runs up this edge: two 3 mm tubes in a
                              # 4 mm gap would grow through each other.
GOGGLE_LENS_TUCK = 0.001      # how far the glass's top edge sits under the bar's
                              # own lower face. A slab that shares the bar's height
                              # is in front of the ring at the temple and behind it
                              # at the nose, which renders as a cyan spike through
                              # the bar with a notch bitten out of it (bead khly's
                              # round-1 major). 1 mm is a pixel at 1 m and it is the
                              # whole of the daylight between bar and glass.
# AND IT IS SEATED BY THE WHOLE OF ITSELF, not by a point on it. Round 2 hung the
# slab off ONE measurement (the most forward the head reaches under its footprint)
# and round 3's first build hung it off another (the strip of face beside the nose,
# the end the yaw pivots on) — and that one put the glass 2.6 mm INSIDE the brow
# ridge at x 28 mm, because the brow is a wall from the nose out to x 30 and only
# then falls away, while the chord falls away from the first millimetre. A lens is
# a rigid surface over a face that is not flat: the only honest question is "how
# far forward must this whole surface be for the tightest point on it to clear",
# and `_face_front` asks it by ray at every point of a grid over the glass and its
# rim. So `_PROUD` is now the standoff AT THE TIGHTEST POINT — the brow, on this
# head — and everywhere else the face falls away under it.
GOGGLE_LENS_PROUD = 0.004     # how far the glass stands off the face at the one
                              # point it comes closest — the bead's original "4 mm
                              # proud of the eye sockets". That point is the BROW,
                              # every build so far, and it is why the glass cannot
                              # sit closer over the socket than it does: the ridge
                              # it has to clear stands ~9 mm in front of the eye
                              # behind it, and a lens is flat.
# AND IT IS RAKED, because a slab standing vertical takes this scene's high key
# light at a grazing angle and DIFFUSE_TOON then gives it the unlit band: a dark
# rectangle where the portrait has a bright cyan one. Top leaning back, like a
# windshield, which turns its normal up into the sun — and which is what a real
# pair does anyway. ROUND 3 SPLITS THE RAKE IN TWO, on the pupil line: the upper
# facet is the glass you see and it keeps the windshield angle, and the LOWER facet
# rakes back harder because below the pupil the face falls away — the cheek at the
# pupil's own x is 5 mm behind the eye, and a lens that does not follow it is a
# shelf standing off the face.
GOGGLE_LENS_TILT = 8.0        # degrees of top-back rake, above the pupil line —
                              # and it is CHEAPER THAN IT LOOKS TO OVERDO: the top
                              # edge is up on the brow, so every degree of it
                              # pushes the whole surface ~0.9 mm further off the
                              # face (round 2's 15 cost 6.6 mm over the eye). 8 is
                              # what keeps the normal out of the grazing band
                              # without buying it in standoff; the measured margin
                              # is thin either way, this light being 35 degrees up
                              # and DIFFUSE_TOON smoothstepping at roughness 1.0
GOGGLE_LENS_LOWER_TILT = 26.0 # and below it, bottom-back — measured, not chosen:
                              # at 26 the bottom edge lands 4 mm clear of the nose
                              # flank at the notch and 6 mm clear of the cheekbone
                              # in the middle, which is as far back as it can tuck
                              # before the glass stops covering the socket
GOGGLE_LENS_NOTCH = 0.30      # and the nose gets a NOTCH: this fraction of the
                              # width is cut off the INNER end of the bottom edge,
                              # so the lens's inner edge slants from the bridge of
                              # the nose at the top out to the cheek at the bottom.
                              # Without it the inner-bottom corner is 5 mm inside
                              # the nose (measured: the head reaches y 0.1748 at
                              # x 5-10 mm, eye-20 mm, where the glass would be at
                              # 0.1693) — the one place on this face that a lens
                              # tall enough to be the canon's cannot go.
# AND IT IS SPLAYED, its outer end turned back toward the temple. A pair of flat
# slabs square to the face is a pair that reads fine head-on and lets the FAR
# EYEBALL past its outer edge the moment the head turns — measured on the 3/4
# `17_head_face` frame, where his far eye sat white and round on the cheek beside
# the lens. Turning each slab back by its own eye's bearing wraps it round to where
# the eye stops, which is also what the portrait's visor does. ROUND 3 MOVED THE
# PIVOT to the inner end — see the section banner: a yaw about the middle buys the
# temple with the nose.
GOGGLE_LENS_SPLAY = 18.0      # degrees of outward wrap. 18 and not round 2's 30
                              # because a pivot at the inner end spends the whole
                              # angle on the outer end — 21 mm of setback over a
                              # 66 mm lens, against the 17 that a 30-degree yaw
                              # about the middle bought — and because the seat pays
                              # for every extra degree in standoff: see the banner.
                              # It stops being free the moment the chord's far end
                              # would need the near end pushed out over the nose
GOGGLE_LENS_CLEAR = 0.003     # the FLOOR under `_PROUD`, and it is honestly a
                              # near-tautology: the seat is FITTED on the same grid
                              # the assert then walks, so every sampled point clears
                              # by `_PROUD` or more by construction. What it catches
                              # is a knob — a `_PROUD` typed below this, a rake or a
                              # notch edited without re-reading the fit — not the
                              # head, which the fit has already answered. The head
                              # is only ever measured as finely as the grid: a brow
                              # spike between two of its points is missed by the fit
                              # and by the check alike, both sampling the same 286
                              # rays.
# AND THERE IS NO BRIDGE BAR ANY MORE. Rounds nvy and khly carried a straight
# `GOGGLE_BRIDGE` box between the lenses' inner ends, and round 3's first build
# kept it and broke it: those ends used to be parallel, and the notch turns them
# into a SLANT, so a bar sized for the gap at the top (9 mm) and placed at the
# lens's middle height — where the slant has opened that gap to 25 mm — touched
# neither lens. It rendered as a free-floating graphite chip in front of the nose,
# which is visible in this round's own evidence grid. Sizing it off `inner_at()`
# would have fixed the arithmetic and built the wrong thing anyway: the two rims
# now run UP their slanted inner edges and into the ring over the nose, so the pair
# is already joined there and a bar under that join is a bar across the notch —
# the one piece of daylight this design is deliberately opening.
GOGGLE_SLAB = 0.030           # half the band of head the axis is centred on
GOGGLE_REACH = 0.4            # how far outside the head a seating ray starts
GOGGLE_TRIS = (400, 1000)     # the bead's budget, asserted where it is spent
                              # (raised by 200 in round 3, for the rim)


def _skull_axis(obj, z_lo, z_hi):
    """The vertical axis the goggles are hung off: the centre of the head's own
    slab and not the body's, for `wrap_band`'s reason — a bounding box that reaches
    the neck is not centred on the face."""
    co = [v.co for v in obj.data.vertices if z_lo <= v.co.z <= z_hi]
    if len(co) < 32:
        raise AssertionError("only %d vertices between z %.3f and %.3f: the goggles "
                             "have no head to sit on" % (len(co), z_lo, z_hi))
    return Vector(((min(c.x for c in co) + max(c.x for c in co)) / 2.0,
                   (min(c.y for c in co) + max(c.y for c in co)) / 2.0))


def _skull_reach(bvh, axis, bearing, z):
    """(radius, outward) — how far the head reaches at `bearing`, AT THIS HEIGHT.

    MEASURED BY A RAY, and by a ray cast INWARD from outside the head. Two things
    that a nearest-vertices average cannot do, and both of them showed up in the
    first build of this bead: the skull decimates to ~3 cm between vertices, so a
    slab thin enough to be "at eye height" is empty at most bearings and a slab
    thick enough to be populated reaches the TIP OF THE NOSE — which then pushes
    the frame 1 cm off the brow it is supposed to rest on. The first surface an
    inward ray meets is the OUTERMOST one at exactly this height: the brow at the
    front, the ear where the arm crosses it, the hair shell at the back.

    Inward and not outward, because MakeHuman's basemesh folds into the eye socket
    and lines it (the same fold `wrap_band` deletes), so a ray leaving the axis can
    meet the inside of the face before its outside.
    """
    out = Vector((math.sin(bearing), math.cos(bearing), 0.0))
    origin = Vector((axis.x, axis.y, z)) + out * GOGGLE_REACH
    hit = bvh.ray_cast(origin, -out, GOGGLE_REACH)[0]
    if hit is None:
        raise AssertionError("no head surface at z %.4f, bearing %.1f deg: the "
                             "goggles have nothing to sit on there"
                             % (z, math.degrees(bearing)))
    return math.hypot(hit.x - axis.x, hit.y - axis.y), out


def _goggle_ring(bm, path):
    """Bridge (centre, out, half_thick, half_height) cross-sections into a closed
    box-section ring.

    Returns the rings, each (in-low, out-low, out-high, in-high), so the caller can
    colour one edge of the section differently — which is the whole highlight bar.
    The winding is left to `recalc_face_normals` at the end of the build: a
    station's own frame turns through 360 degrees round the skull, and hand-picking
    an order that is outward at every bearing is a trap for no gain.
    """
    rings = []
    for centre, out, half_d, half_h in path:
        rings.append([bm.verts.new(centre + out * (s * half_d)
                                   + Vector((0.0, 0.0, t * half_h)))
                      for s, t in ((-1, -1), (1, -1), (1, 1), (-1, 1))])
    for a, b in zip(rings, rings[1:] + [rings[0]]):
        for k in range(4):
            bm.faces.new((a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k]))
    return rings


def _lens_rim(bm, pts, normal, half_w, half_d):
    """A thin box-section tube along an OPEN polyline — one lens's rim.

    `_goggle_ring` above bridges a closed loop whose cross-section is squared to
    the skull's own outward; this one is open, and its cross-section is squared to
    the LENS: `half_d` along `normal` (the glass's own forward) and `half_w` across
    it, perpendicular to the path. That is the whole difference between a band
    round a head and a frame round a piece of glass, and it is why the rim follows
    the lens's two facets instead of a radius.

    Corners take the miter (the average of the two directions) and not a scale with
    it, so a right angle pinches by a fraction of 3 mm. The ends are CAPPED: both
    are buried in the frame ring, but a tube with a hole in it is a tube that shows
    one the day the ring moves.
    """
    rings = []
    for i, point in enumerate(pts):
        along = Vector((0.0, 0.0, 0.0))
        if i:
            along += (point - pts[i - 1]).normalized()
        if i + 1 < len(pts):
            along += (pts[i + 1] - point).normalized()
        across = normal.cross(along.normalized()).normalized()
        rings.append([bm.verts.new(point + across * (a * half_w)
                                   + normal * (b * half_d))
                      for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1))])
    for a, b in zip(rings, rings[1:]):
        for k in range(4):
            bm.faces.new((a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k]))
    bm.faces.new(rings[0])
    bm.faces.new(rings[-1])
    return [v for ring in rings for v in ring]


def _face_front(bvh, x, z):
    """Where the face's own front is at (x, z), or None off its silhouette.

    BY RAY, for `_skull_reach`'s reason and one of its own: the skull decimates to
    ~3 cm between vertices, so "the most forward vertex in a band round this point"
    is an answer about a band and not about this point — it cannot say whether the
    brow pokes through a lens BETWEEN two of them. A ray meets the surface itself.
    Straight back along -Y and from well outside the head, so the first hit is the
    outermost surface there: the brow, the nose, the cheekbone.
    """
    hit = bvh.ray_cast(Vector((x, 2.0 * GOGGLE_REACH, z)),
                       Vector((0.0, -1.0, 0.0)), 4.0 * GOGGLE_REACH)[0]
    return None if hit is None else hit.y


def build_goggles(obj, row, tj):
    """The pair, as one mesh: the ring (frame + arms + strap) and two lenses, each
    with the rim that frames it. The section banner above says what each is, and
    says why there is no separate bridge piece.

    ONE LOOP OF LENS GEOMETRY, and the two sides are built together on purpose: the
    seat is fitted across both of them, so neither can be placed before the other
    has been measured.

    Reads the body's OWN surface, so it is built before anything is joined onto
    that body (`build()` keeps that order) — a beret or a pair of eyeballs inside
    the slab would answer the outline question for a piece of the head that is not
    the head.
    """
    from mathutils.bvhtree import BVHTree
    colours = row["colours"]
    eye_z = (tj["l-eye"].z + tj["r-eye"].z) / 2.0
    ring_z = eye_z + GOGGLE_RING_Z
    axis = _skull_axis(obj, eye_z - GOGGLE_SLAB, eye_z + GOGGLE_SLAB)
    # `bake_cloth_shading`'s tree, built on the whole body: nothing but the head is
    # within 3 cm of the eye line on a standing human, so every ray below meets the
    # head whatever else is in it.
    me = obj.data
    bvh = BVHTree.FromPolygons([tuple(v.co) for v in me.vertices],
                               [tuple(p.vertices) for p in me.polygons])
    frame_arc = math.radians(GOGGLE_FRAME_ARC)
    arm_arc = math.radians(GOGGLE_ARM_ARC)
    bm = bmesh.new()
    paint = {}

    def seat(bearing, z, half_d):
        """Where a cross-section of half-thickness `half_d` sits at `bearing`: on
        the head's own surface at that height, `GOGGLE_STANDOFF` proud of it, and
        its INNER face on that line rather than its centre."""
        r, out = _skull_reach(bvh, axis, bearing, z)
        return Vector((axis.x, axis.y, z)) + out * (r + GOGGLE_STANDOFF + half_d), out

    path, zones = [], []
    for i in range(GOGGLE_STATIONS):
        bearing = ((2.0 * math.pi * i / GOGGLE_STATIONS + math.pi)
                   % (2.0 * math.pi) - math.pi)
        if abs(bearing) <= frame_arc:
            zone, section = "frame", GOGGLE_FRAME
        elif abs(bearing) <= arm_arc:
            zone, section = "arm", GOGGLE_ARM
        else:
            zone, section = "strap", GOGGLE_STRAP
        half_d, half_h = section[0] / 2.0, section[1] / 2.0
        centre, out = seat(bearing, ring_z, half_d)
        path.append((centre, out, half_d, half_h))
        zones.append(zone)
    for zone, ring in zip(zones, _goggle_ring(bm, path)):
        for v in ring:
            paint[v] = colours["goggle_frame"]
        if zone == "frame":
            # THE HIGHLIGHT BAR is the top edge of the frame and nothing else: the
            # portrait's straight top bar catches the light where the rest of the
            # graphite does not.
            paint[ring[2]] = paint[ring[3]] = colours["goggle_edge"]

    thick, tall = GOGGLE_LENS

    tilt = math.radians(GOGGLE_LENS_TILT)
    lower = math.radians(GOGGLE_LENS_LOWER_TILT)
    splay = math.radians(GOGGLE_LENS_SPLAY)
    half_gap = GOGGLE_BRIDGE_GAP / 2.0
    # From `GOGGLE_BRIDGE_GAP`/2 off the centre line out to `GOGGLE_LENS_REACH`
    # past the pupil — see those consts for why the width is measured and not
    # typed. `width` is the CHORD, so the outer corner still lands on the reach
    # once the yaw has turned the chord back toward the temple.
    reach = max(abs(tj[side + "-eye"].x) for side in ("l", "r")) + GOGGLE_LENS_REACH
    width = (reach - half_gap) / math.cos(splay)
    # THE GLASS HANGS OFF THE BAR, and that is one subtraction rather than two
    # consts that have to agree: its top edge is `_TUCK` under the ring's own lower
    # face, and the height then says where the bottom and the centre land. (Round 2
    # typed the centre and checked the tuck by hand; the first build of that round
    # is the cyan spike through the bar that came of it.)
    z_top = ring_z - GOGGLE_FRAME[1] / 2.0 - GOGGLE_LENS_TUCK
    z_bot = z_top - tall
    lens_z = (z_top + z_bot) / 2.0
    if GOGGLE_LENS_TUCK <= 0.0:
        raise AssertionError("GOGGLE_LENS_TUCK is %.4f: glass that reaches the "
                             "bar's own lower face at z %.4f is in front of the "
                             "ring at the temple and behind it at the nose, which "
                             "renders as a cyan spike through the bar (bead khly, "
                             "round 1)"
                             % (GOGGLE_LENS_TUCK, ring_z - GOGGLE_FRAME[1] / 2.0))
    rim_w, rim_d = GOGGLE_RIM
    # The rim's centre line, in the lens's own surface, relative to the glass edge:
    # positive is OUTWARD, and it is less than half the tube because of the groove.
    margin = rim_w / 2.0 - GOGGLE_RIM_GROOVE
    # ...and how far the frame's own SURFACE reaches past that edge, which is what
    # the grid below has to cover: a grid that stopped on the centre line would
    # leave the outer half of the tube unmeasured on every side at once — 1.5 mm
    # below the bottom run and 1.5 mm inward of the nose-side one, which is the
    # direction the face comes forward in.
    rim_out = margin + rim_w / 2.0

    def drop_at(z):
        """How far back the surface is at height `z` from the chord it hangs on —
        TWO FACETS meeting on the pupil line, the upper leaning back by `_TILT` and
        the lower back harder by `_LOWER_TILT`."""
        return ((z - eye_z) * math.tan(tilt) if z >= eye_z
                else (eye_z - z) * math.tan(lower))

    def inner_at(z):
        """Where a lens's inner edge is at height `z`: on the centre line's own gap
        at the top and `_NOTCH` of the width out at the bottom, which is the cut
        that lets the glass past the nose."""
        return GOGGLE_LENS_NOTCH * width * (z_top - z) / tall

    def surface_grid():
        """(sgn, s, z) over both lenses AND the rim's own footprint — the grid the
        seat is fitted on and then asserted on. Out to the rim's outer SURFACE on
        the three sides it runs down; the fourth is the top, where the glass ends
        under the bar and the rim's two ends leave the lens for the ring's own
        seat."""
        for sgn in (1.0, -1.0):
            for j in range(13):
                z = (z_bot - rim_out) + (z_top - z_bot + rim_out) * j / 12.0
                s0 = inner_at(max(z, z_bot)) - rim_out
                for i in range(11):
                    yield sgn, s0 + (width + rim_out - s0) * i / 10.0, z

    def chord_x(sgn, s):
        return sgn * (half_gap + s * math.cos(splay))

    # ONE DEPTH FOR BOTH LENSES, and it is FITTED and not sampled — see the const
    # banner. Every point of the grid asks how far forward the chord would have to
    # be for THAT point to stand `_PROUD` off the face under it; the deepest answer
    # is the one the pair is built at. (The head is symmetric and the two sides
    # agree to well under a millimetre, but a visor whose halves sit at two depths
    # is a visor with a kink in it, so they are fitted together.)
    seats = []
    for sgn, s, z in surface_grid():
        front = _face_front(bvh, chord_x(sgn, s), z)
        if front is not None:
            seats.append(front + GOGGLE_LENS_PROUD
                         + s * math.sin(splay) + drop_at(z))
    if not seats:
        raise AssertionError("no face under either lens between z %.4f and %.4f: "
                             "the glass has nothing to stand off" % (z_bot, z_top))
    lens_y = max(seats)

    def lens_at(sgn, s, z):
        """A point on one lens's own surface: `s` out along the chord from the
        inner edge, at height `z`. TWO FACETS meeting on the pupil line — above it
        the top leans back by `_TILT`, below it the bottom leans back harder by
        `_LOWER_TILT` — and the chord itself leans back by `_SPLAY` as it goes out,
        about the inner edge.
        """
        return Vector((chord_x(sgn, s), lens_y - s * math.sin(splay) - drop_at(z), z))

    def bearing_of(point):
        """The skull bearing a point is on — what a rim end hands `seat()` so that
        it comes up inside the ring instead of near it."""
        return math.atan2(point.x - axis.x, point.y - axis.y)

    rows = (z_bot, eye_z, z_top)
    for side in ("l", "r"):
        sgn = math.copysign(1.0, tj[side + "-eye"].x)
        # THE GLASS: three rows (bottom, pupil, top) by two columns (the slanted
        # inner edge, the outer edge), front and back. A box would not do it — the
        # bend on the pupil line and the notch on the inner edge are the whole of
        # what makes 46 mm of lens fit on this face.
        front, back = [], []
        for z in rows:
            # NOT `row` — that is this function's own parameter, the hero's config
            # dict, and `colours` is only read off it before the loop by luck.
            edge = [lens_at(sgn, inner_at(z), z), lens_at(sgn, width, z)]
            front.append([bm.verts.new(point) for point in edge])
            back.append([bm.verts.new(point - Vector((0.0, thick, 0.0)))
                         for point in edge])
        for r in range(len(rows) - 1):
            for grid in (front, back):
                bm.faces.new((grid[r][0], grid[r][1],
                              grid[r + 1][1], grid[r + 1][0]))
            for c in (0, 1):
                bm.faces.new((front[r][c], front[r + 1][c],
                              back[r + 1][c], back[r][c]))
        for r in (0, len(rows) - 1):
            bm.faces.new((front[r][0], front[r][1], back[r][1], back[r][0]))
        for r in range(len(rows)):
            # The "lighter rim strip" the bead licensed the opaque lens for: the
            # glass's own top row, one step up, which under DIFFUSE_TOON gradients
            # down the upper facet and is what reads as glass.
            for v in front[r] + back[r]:
                paint[v] = colours["goggle_glint" if r == len(rows) - 1
                                   else "goggle_lens"]
        # THE RIM: down the temple side, under the glass, back up the nose side,
        # and at both ends up INTO the ring at that bearing's own seat — so the bar
        # and the rim are one frame, which is the whole of this round.
        along = Vector((sgn * math.cos(splay), -math.sin(splay), 0.0))
        normal = Vector((sgn * math.sin(splay), math.cos(splay), 0.0))
        drop = Vector((0.0, 0.0, -margin))
        # BACK BY HALF THE GLASS, because `lens_at` is the glass's FRONT face and a
        # section centred on that leaves its BACK face 0.4 mm proud of the tube
        # (the lens is `thick` * cos SPLAY = 1.9 mm deep along the rim's own axis,
        # against the tube's 1.5 mm half-depth) — the groove honoured across the
        # lens and not through it, and a cyan hair behind the rim from below.
        # `GOGGLE_RIM_GROOVE` is what the tube has left over at each face.
        sunk = normal * (thick / 2.0)
        pts = [lens_at(sgn, width, z_top) + along * margin - sunk,
               lens_at(sgn, width, z_bot) + along * margin + drop - sunk,
               lens_at(sgn, inner_at(z_bot), z_bot) - along * margin + drop - sunk,
               lens_at(sgn, 0.0, z_top) - along * margin - sunk]
        pts = ([seat(bearing_of(pts[0]), ring_z, rim_d / 2.0)[0]] + pts
               + [seat(bearing_of(pts[-1]), ring_z, rim_d / 2.0)[0]])
        for v in _lens_rim(bm, pts, normal, rim_w / 2.0, rim_d / 2.0):
            paint[v] = colours["goggle_frame"]

    # THE FLOOR UNDER THE KNOBS, and not an independent measurement — the seat was
    # fitted on this same grid, so every point of it clears by `_PROUD` already.
    # What the walk buys is the LOG: the worst gap in the pair, the number to read
    # the day a const moves. See `GOGGLE_LENS_CLEAR`.
    worst, worst_at = GOGGLE_REACH, None
    for sgn, s, z in surface_grid():
        point = lens_at(sgn, s, z)
        front = _face_front(bvh, point.x, point.z)
        if front is not None and point.y - front < worst:
            worst, worst_at = point.y - front, point
    if worst < GOGGLE_LENS_CLEAR:
        raise AssertionError(
            "the face is only %.4f m behind the glass at (%.4f, %.4f, %.4f), under "
            "the %.4f m GOGGLE_LENS_CLEAR asks for: the lens is inside the head "
            "there" % (worst, worst_at.x, worst_at.y, worst_at.z, GOGGLE_LENS_CLEAR))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.verts.index_update()
    order = [paint[v] for v in bm.verts]
    pair = bpy.data.meshes.new("Goggles")
    bm.to_mesh(pair)
    bm.free()
    goggles = bpy.data.objects.new("Goggles", pair)
    bpy.context.collection.objects.link(goggles)
    attr = pair.color_attributes.new(name="Color", type='FLOAT_COLOR', domain='POINT')
    for i, colour in enumerate(order):
        attr.data[i].color = colour
    pair.color_attributes.active_color = attr
    pair.attributes.active_color = attr
    tris = _tri_count(pair)
    if not GOGGLE_TRIS[0] <= tris <= GOGGLE_TRIS[1]:
        raise AssertionError("the goggles are %d tris, outside the bead's %d-%d "
                             "budget" % (tris, GOGGLE_TRIS[0], GOGGLE_TRIS[1]))
    # The numbers to read when this looks wrong: where the glass sits against the
    # eye line and the bar, how far the head reaches at the nose and at the ear
    # (what everything here is seated on), and the tightest the glass ever comes to
    # the face.
    # NOT "how far it stands off the eye", which is the number the complaint sounds
    # like it is about and the one thing here that cannot be measured: this
    # basemesh's eye socket is OPEN and lined on the inside (`_skull_reach` names
    # the same fold), so a ray at the pupil falls into it and answers 0.0527 m —
    # the socket's own depth, not a standoff. `worst` is the honest global number
    # and it lands on the brow.
    log("goggles: %d tris, ring z %.4f (bar %.4f..%.4f) / glass z %.4f..%.4f "
        "(eye %.4f), inner edge y %.4f, outer corner x %+.4f, head reach %.4f m at "
        "the nose / %.4f m at the ear, worst face gap %.4f m"
        % (tris, ring_z, ring_z - GOGGLE_FRAME[1] / 2.0,
           ring_z + GOGGLE_FRAME[1] / 2.0, z_bot, z_top, eye_z, lens_y,
           half_gap + width * math.cos(splay),
           _skull_reach(bvh, axis, 0.0, ring_z)[0],
           _skull_reach(bvh, axis, math.pi / 2.0, ring_z)[0], worst))
    return goggles


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
    assert. Counted on the mesh as exported, so EVERY accessory `join_rigid` puts on
    `head` counts with it: the beret, the eyes, Primm's goggles, Phoboman's whole
    helmet, and so does the wrap. On a helmeted row the number is mostly dome (2,708
    of Phoboman's 4,208), which is exactly why `build()` drops the `HEAD_TRIS_MIN`
    floor for such a row rather than reading this as a face that survived."""
    ids = {vg.index for vg in obj.vertex_groups if vg.name in ("head", "neck_01")}
    head = {v.index for v in obj.data.vertices if _group_weight(v, ids) > 0.5}
    obj.data.calc_loop_triangles()
    return sum(1 for t in obj.data.loop_triangles
               if all(i in head for i in t.vertices))


def export_glb(obj, armature, path, sharp=frozenset()):
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

    `sharp` is every hard-edged thing on a hero: `wrap_band`'s rims and knots (the
    first of them — a cloth edge that shades smoothly into the cheek is the painted
    bandage again with extra steps, the spike's own ruling), and since then every
    ACCESSORY joined after the wrap that is a made object rather than a body —
    Primm's goggles and coat tails, Phoboman's helmet and his dragon. On Phoboman,
    who wears no band at all, those last two are the whole set and the largest
    flat-shaded region in the cast.

    It is a set of POLYGON INDICES, so nothing may be joined into the mesh between
    the wrap and the join that extends it, and a row may not wear both a band and
    an accessory; `build()` keeps that order and refuses such a row.
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
        # 'EXPORT' SINCE BEAD 21m, and it was 'NONE' before it. A hero used to
        # export no material at all and take Godot's importer default, which
        # `ToonShading.apply_to_mesh` styled as the cast; now `split_cloth_material`
        # writes the two names the Godot side splits on, and they have to reach the
        # file. The materials themselves are deliberately Godot's own default in
        # every respect but the name — white, roughness 1.0, back faces culled —
        # so what the split changes is the SHADING RECIPE and not the albedo.
        export_materials='EXPORT',
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


def build(hero, shot=None):
    """Build one hero: one skinned `.glb` and its `.blend`, plus the manifest row."""
    row = HEROES[hero]
    if "band" in row and (row["beret"] or row["eyes"] or "tails" in row
                          or "goggles" in row or row.get("helmet")
                          or row.get("dragon")):
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
    # A ROW MAY BUY A CHEAPER HEAD (bead godot-test1-9k9n.1). The head is 8% of the
    # silhouette and all of the acting — which is why it has its own target at all
    # — but Phoboman's is inside a sealed diving helmet and none of it is ever
    # drawn. Those triangles are what his helmet and his dragon are paid from, and
    # `TRI_BUDGET` is still the backstop behind the trade.
    decimate(obj, BODY_TRIS, row.get("head_tris", HEAD_TRIS))
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

    # CLOTH PASS A (beads td8 / 21m). Here and not later for trap 9's reason: the
    # subdivide adds geometry and renumbers every polygon, and `wrap_band` below
    # hands `export_glb` a set of polygon indices.
    fold_garments(obj, tj, row)
    mark_cloth(obj)

    band_verts, flat_faces = wrap_band(obj, (tj["l-eye"].z + tj["r-eye"].z) / 2.0,
                                       row)
    if band_verts:
        weight_strays_to(obj, armature, "head", tj["neck"].z)
    paint_body(obj, tj, row, band_verts)
    if "emblem" in row:
        paint_chest_glyph(obj, tj, row)

    # FIRST OF THE ACCESSORIES, because it MEASURES the body it is joined to:
    # `build_goggles` reads the head's own outline at eye height, and a beret brim
    # or an eyeball inside that slab would be measured as skull. `build_helmet` and
    # `build_dragon` below read the body too (the skull, and the belly by ray), so
    # the rule is that a measuring builder runs before anything is joined into what
    # it measures. The helmet sits after the beret and the eyes only because no row
    # wears both, and the day one does it moves up here; the dragon is safe after
    # the helmet because it rays a tree built from the TRUNK's own polygons, which
    # a dome weighted to `head` is not in.
    # (Its polygons are flat-shaded for the coat tails' reason — a frame and a lens
    # are hard-edged, and smoothing a box ring rounds it into a sausage.)
    if "goggles" in row:
        goggle_p0 = len(obj.data.polygons)
        obj = join_rigid(obj, build_goggles(obj, row, tj), "head")
        flat_faces = frozenset(flat_faces) | frozenset(
            range(goggle_p0, len(obj.data.polygons)))
    if row["beret"]:
        crown_z = max(v.co.z for v in obj.data.vertices)
        obj = join_rigid(obj, build_beret(row["colours"], crown_z), "head")
    if row["eyes"]:
        obj = join_rigid(obj, build_eyes(row["colours"], tj["l-eye"], tj["r-eye"]),
                         "head")
    # PHOBOMAN'S TWO (bead godot-test1-9k9n.1). The helmet rides `head` like the
    # beret, so the gait's 7-degree head bobble nods the whole dome — that is the
    # point of joining it to that bone rather than hanging it off a
    # `BoneAttachment3D`. The dragon rides the three SPINE bones at once, because
    # it lies across a belly all three of them drive (`spine_split`). Both are
    # flat-shaded for the coat tails' reason: a rivet or a rim smoothed into the
    # dome is a sausage.
    if row.get("helmet"):
        helmet_p0 = len(obj.data.polygons)
        obj = join_rigid(obj, build_helmet(row["colours"], obj, tj), "head")
        flat_faces = frozenset(flat_faces) | frozenset(
            range(helmet_p0, len(obj.data.polygons)))
    dragon_v0 = None
    if row.get("dragon"):
        dragon_p0 = len(obj.data.polygons)
        dragon_v0 = len(obj.data.vertices)
        obj = join_weighted(obj, build_dragon(row["colours"], obj, tj),
                            spine_split(armature))
        flat_faces = frozenset(flat_faces) | frozenset(
            range(dragon_p0, len(obj.data.polygons)))
    if "tails" in row:
        tail_v0 = len(obj.data.vertices)
        obj, tail_faces = attach_tails(obj, row, tj)
        flat_faces = frozenset(flat_faces) | tail_faces
        # THE TAILS ARE CLOTH AND NOTHING ELSE CAN SAY SO (bead 21m). Every other
        # garment was marked by `mark_cloth` off the shells `dress_shells` pushed
        # out of the body; the coat tails are the one garment that is NEW geometry,
        # so they carry no `GARMENT_VG` and would have shaded as skin — a coat
        # whose flaps are not made of the coat. A join APPENDS, so the tails are
        # exactly the vertices past the mark.
        tails = list(range(tail_v0, len(obj.data.vertices)))
        mark = obj.vertex_groups.get(CLOTH_VG)
        if not tails or mark is None:
            raise AssertionError("attach_tails added %d vertices and the %r group "
                                 "is %s — the tails cannot be marked as cloth"
                                 % (len(tails), CLOTH_VG,
                                    "missing" if mark is None else "present"))
        mark.add(tails, 1.0, 'REPLACE')
        log("cloth: marked %d joined tail verts as garment" % len(tails))

    # CLOTH PASS B (beads td8 / 21m). AFTER the paint, because it MULTIPLIES into
    # the colour the paint just wrote — and after the joins, which is this bead's
    # own correction to the spike's order: the tails above are garment, so they
    # want the bake, and the geometry they occlude (the trousers behind them) only
    # occludes once they are part of the same mesh the rays are cast against.
    bake_cloth_shading(obj)

    apply_pose_as_rest(armature, obj, ARMS_DOWN_DEG)
    # ... AND ONLY NOW CAN THE DRAGON BE CHECKED against the arms, because only now
    # are they where the hero ships them — see `assert_clear_of_arms`.
    if dragon_v0 is not None:
        assert_clear_of_arms(obj, dragon_v0)
    report_weights(obj, armature, "skinned body (accessories joined)")
    assert_no_multires([obj, armature])

    zs = [v.co.z for v in obj.data.vertices]
    log("final body: height %.4f m (z %.4f..%.4f), %d verts"
        % (max(zs) - min(zs), min(zs), max(zs), len(obj.data.vertices)))
    if abs(min(zs)) > 0.04:
        raise AssertionError("feet %.4f m off the ground (cap 0.04)" % min(zs))

    head_tris = head_tri_count(obj)
    # THE FLOOR IS THE FACE'S, AND A HELMETED HEAD HAS NO FACE (bead
    # godot-test1-9k9n.1). "The face melted" is a statement about what the camera
    # reads at 3 m; behind a sealed dome it reads the helmet, whose own triangles
    # are budgeted in `build_helmet`. Keyed on the row's `helmet`, not on its
    # `head_tris`, because the thing that makes the floor meaningless is the dome
    # and not the number.
    floor = 0 if row.get("helmet") else HEAD_TRIS_MIN
    log("head: %d tris (floor %d)" % (head_tris, floor))
    if head_tris < floor:
        raise AssertionError("the face melted: %d head tris under the %d floor"
                             % (head_tris, floor))

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
    # CLOTH PASS D (beads td8 / 21m) — the LAST pass before the export, because it
    # is the only one that touches material slots and `export_glb` reads them.
    split_cloth_material(obj)
    drop_cloth_mark(obj)
    glb = os.path.join(out_dir, row["stem"] + ".glb")
    tris, size = export_glb(obj, armature, glb, sharp=flat_faces)
    if tris > TRI_BUDGET:
        raise AssertionError("%d tris over the %d budget" % (tris, TRI_BUDGET))
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

    # The committed .blend is the hero's source of record beside the .glb (the
    # epic's "commit the compressed .blend" ruling).
    blend = os.path.join(out_dir, row["stem"] + ".blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend, compress=True)
    log("wrote %s (%d bytes)" % (os.path.basename(blend), os.path.getsize(blend)))

    if shot:
        # The `screenshot()` helper below shoots from -Y, because the part trees
        # the retired lane was written for are built facing that way (its Rx(+90)
        # root). These bodies face +Y, so without this the rest row is three backs
        # of heads. Turned at the OBJECT level and only after both files are
        # written — the .glb and the .blend already have the rest pose they are
        # supposed to have, and the mesh and the armature turn together so the
        # modifier still binds — which is what turning only the ROOTS does, the
        # mesh being MPFB2's child of the armature. Turning both instead composes
        # pi with pi and the hero faces front again (measured 2026-09-11: three
        # backs of heads).
        for o in (obj, armature):
            if o.parent is None:
                o.rotation_euler.z = math.pi
        # Workbench's default MATERIAL colour mode renders a hero with no material
        # as grey clay; these bodies ARE their vertex colours.
        bpy.context.scene.display.shading.color_type = 'VERTEX'
        screenshot(shot, max(zs))
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


def screenshot(path, height_hint):
    """Render the assembled hero from the game's third-person distance (~4 m,
    slightly above), Workbench: no material/light setup needed, fast headless.

    Folded in from the retired `scripts/blender_hero.py` (bead godot-test1-9k9n.3):
    that lane's import half has no hero left, and this helper is the only thing
    anyone still called in there. bpy + Vector + log is all it needs."""
    scene = bpy.context.scene
    target = Vector((0.0, 0.0, height_hint * 0.55))
    cam_loc = Vector((0.0, -4.0, height_hint * 0.75))
    cam_data = bpy.data.cameras.new("HeroCam")
    cam_obj = bpy.data.objects.new("HeroCam", cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = cam_loc
    cam_obj.rotation_euler = (target - cam_loc).to_track_quat('-Z', 'Y').to_euler()
    scene.camera = cam_obj

    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.filepath = path
    bpy.context.view_layer.update()
    bpy.ops.render.render(write_still=True)
    log("wrote screenshot", path)


def rest_row(shots, path):
    """The cast at rest, side by side in one strip. Blender renders each hero on its
    own (`screenshot`, just above) and numpy pastes them — Pillow is not
    installed in Blender's Python and is not worth adding for one concatenate."""
    import numpy

    frames = []
    for shot in shots:
        img = bpy.data.images.load(shot)
        buf = numpy.empty(len(img.pixels), dtype=numpy.float32)
        img.pixels.foreach_get(buf)
        frame = buf.reshape(img.size[1], img.size[0], 4)
        # The helper frames a whole 4 m field of view for a 1.8 m man, so most of
        # each square is floor. Keep the middle third: the cast at a readable size
        # beats a row of squares of background.
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
    # `--variant` (bead td8's scratch cloth columns) IS GONE, and a stale command
    # line that still passes it must not silently build a shipped hero instead:
    # the columns were compared, the owner picked A+B+D, and bead 21m made them
    # the only path there is.
    if "--variant" in argv:
        raise SystemExit("--variant was bead td8's cloth SPIKE and it shipped: "
                         "the columns are now every hero's default path (bead "
                         "godot-test1-21m). Drop the flag.")
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
        built[hero] = build(hero, shot)
        if shot:
            shots[hero] = shot
    if row_png:
        rest_row([shots[h] for h in heroes],
                 row_png if os.path.isabs(row_png) else os.path.join(REPO, row_png))
    if check:
        check_manifest(built)
    else:
        write_manifest(built)


if __name__ == "__main__":
    main()
