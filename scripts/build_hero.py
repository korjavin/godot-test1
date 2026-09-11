"""
scripts/build_hero.py — THE SKINNED HERO LANE. A hero is a `HEROES` row.

Bead godot-test1-5u3.1 (epic 5u3, SKINNED HEROES), the SOURCE OF RECORD for the
shipped Teibi since bead 5u3.3, and GENERALISED to the whole cast by bead 5u3.4:
windman, primm and teibi are three rows of one table and there is no second
script. Started as a copy of the z3e.10 spike (`scripts/spike_z3e_teibi_body.py`,
deleted by 5u3.3) with the ten-piece joint SPLIT removed and an ARMATURE added:
the body is one mesh on MPFB2's `game_engine` rig, exported as one skinned .glb.

WHAT A ROW IS (and where each half of it came from):

  macros + targets  the FACE, imported verbatim from `spike_z3e_head.py`'s own
                    HEROES table — the shipped Windman and Primm faces, not a
                    retyped copy of them. Body and head are now ONE human at ONE
                    scale (owner ruling 2026-09-11, "heads at body scale"), so
                    the neck is continuous by construction and the z3e.7 neck gap
                    and the z3e.10 stump cannot come back.
  colours           the hero's own generator palette (`self.colors`), verbatim,
                    ungraded — `hero_skin.SKIN_GRADE` is applied here, at paint
                    time, to the entries named in GRADED_COLOURS.
  bone_regions      clothing as BONE REGIONS: which bone wears which colour. A
                    sleeveless shirt is `upperarm_* -> skin`, shorts are
                    `calf_* -> skin`, gloves are `hand_* -> gloves`. No geometry,
                    no seam, no second material.
  bands             the joint-height overrides a bone cannot express: belt, cuff,
                    collar. A row lists the ones it wears.
  band + stripes    eyewear. `band` makes it CLOTH (`spike_z3e_head.wrap_band`,
                    bead z3e.13's Windman bandage, imported not copied);
                    `stripes` alone paints it on the skin (Primm's goggles).
  beret/eyes        accessory GEOMETRY joined into the mesh and weighted to one
                    bone. An accessory that is not geometry is an ATTACHMENT and
                    belongs in the .tscn as a BoneAttachment3D (Windman's fan on
                    `hand_r`) — the row does not model it and neither does this.

COLOUR IS VERTEX COLOUR AND THERE IS NO TEXTURE (owner ruling 2026-09-11,
"vertex colours by default with a body albedo only for a motif"). No hero here
needs a motif yet: Windman's chest W is bead 5u3.5's call ("body albedo or vertex
glyph"), Phoboman is out of this lane entirely (his sphere body stays generated),
and nothing else in the cast has one. So there is no bake and no UV path here;
the row that first needs one brings it. `texture bytes: 0` is printed anyway, so
the day that changes is the day the number moves.

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
    and `joint_centroid` are imported from `spike_z3e_head.py` for exactly this.
 8. `bmesh.ops.create_cube` WRITES NO DEFORM WEIGHTS. `wrap_band`'s knots are new
    geometry with no vertex groups at all, and an unweighted vertex is a vertex
    that stays behind when the hero walks. `weight_strays_to()` sweeps them onto
    one bone after the wrap; `report_weights()` is what would catch it.
"""

import json
import math
import os
import sys
import tempfile

import addon_utils
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
# THE FACES, AND THE BANDAGE, ARE IMPORTED — NOT RETYPED. `spike_z3e_head.py` is
# the lane that authored and shipped the Windman and Primm heads; its HEROES rows
# are the face recipe of record (macros, targets, palette, eyewear stripes, the
# cloth `band`) and `wrap_band` is bead z3e.13's cloth bandage itself. Both files
# are `__main__`-guarded so either can import the other without building a head.
import spike_z3e_head as face  # noqa: E402
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

def _face_row(hero):
    """`spike_z3e_head.py`'s macros and face targets for `hero`, in this file's
    shapes. The SPIKE IS THE SOURCE: that lane authored and shipped both faces and
    bead z3e.12 spent itself differentiating them, so a copy here would be a second
    number to keep in step with the first. The macros come across whole because in
    MakeHuman they shape the WHOLE human — Windman's `weight` 0.6 is the same
    slider that makes the generated torso stout, and Primm's 0.35 the same one that
    makes his slim."""
    row = face.HEROES[hero]
    return dict(row["macro"]), [(rel, w) for rel, w in row["targets"]]


def _face_palette(hero):
    """The spike's own skin/lips/hair for `hero`, UNGRADED — `paint_body` applies
    `hero_skin.SKIN_GRADE` to the entries in GRADED_COLOURS, so a pre-graded value
    here would be graded twice. Primm's skin deliberately leaves his generator's
    (see the spike's table); Windman's is his generator's verbatim."""
    return dict(face.HEROES[hero]["palette"])


HEROES = {
    "teibi": {
        # docs/characters/tiebi.md: ordinary man, medium build, calm friendly
        # face, no facial hair. spike_z3e_teibi_body.py's numbers, verbatim.
        "macros": {"gender": 0.9, "age": 0.4, "muscle": 0.5, "weight": 0.45,
                   "caucasian": 1.0, "african": 0.0, "asian": 0.0},
        "targets": [(("head", "head-round.target.gz"), 0.30),
                    (("cheek", "l-cheek-volume-incr.target.gz"), 0.18),
                    (("cheek", "r-cheek-volume-incr.target.gz"), 0.18),
                    (("nose", "nose-scale-vert-decr.target.gz"), 0.15),
                    (("chin", "chin-jaw-drop-decr.target.gz"), 0.12)],
        # generate_teibi_separate.py's palette, verbatim (owner ruling: vertex
        # colours, zero texture bytes). Skin and lips reach the mesh through
        # `hero_skin.SKIN_GRADE` — the row is the paint, that constant is the exposure.
        "colours": {
            "skin":          (0.86, 0.66, 0.54, 1.0),
            "hair":          (0.17, 0.12, 0.09, 1.0),
            "beret_navy":    (0.07, 0.09, 0.19, 1.0),
            "shirt_mustard": (0.87, 0.66, 0.17, 1.0),
            "shirt_collar":  (0.74, 0.55, 0.12, 1.0),
            "trousers":      (0.20, 0.22, 0.28, 1.0),
            "belt":          (0.11, 0.10, 0.11, 1.0),
            "belt_buckle":   (0.55, 0.50, 0.30, 1.0),
            "shoes":         (0.16, 0.11, 0.08, 1.0),
            "lips":          (0.80, 0.55, 0.48, 1.0),
            "eye_white":     (0.92, 0.92, 0.90, 1.0),
            "eye_iris":      (0.22, 0.16, 0.11, 1.0),
        },
        "colour_key": {"skin": "skin", "shirt": "shirt_mustard",
                       "trousers": "trousers", "shoes": "shoes",
                       "belt": "belt", "belt_buckle": "belt_buckle",
                       "cuff": "shirt_collar", "collar": "shirt_collar"},
        "bands": ("belt", "cuff", "collar"),
        "hair": {"lift": 0.006, "front": 0.036, "nape": 0.05, "brows": True},
        "beret": True,
        "eyes": True,
        "height": 1.78,      # crown-to-heel, natural MakeHuman proportions
        "out_dir": "teibi_parts",
        "stem": "teibi_skinned",
    },
    "windman": {
        # docs/characters/windman.md: stout, bare-armed, blue shirt over brown
        # shorts, black boots, and the blue-over-red bandage where his eyes would
        # be. The face is the spike's — see `_face_row`.
        "macros": _face_row("windman")[0],
        "targets": _face_row("windman")[1],
        # generate_windman_separate.py's `self.colors`, verbatim and UNGRADED, plus
        # the spike's `lips`. `fan_*` is not here: the fan is an ATTACHMENT, hung on
        # `hand_r` by bead 5u3.5's .tscn, and windman_fan.glb keeps its own colours.
        "colours": dict(_face_palette("windman"), **{
            "shirt_blue":   (0.16, 0.33, 0.60, 1.0),
            "shorts_brown": (0.42, 0.30, 0.18, 1.0),
            "boots_black":  (0.08, 0.08, 0.09, 1.0),
        }),
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
        # THE BANDAGE IS CLOTH, and it is bead z3e.13's cloth — `wrap_band` and the
        # row it reads, imported. It also deletes the eye sockets under it, which
        # is why this row builds no eyeballs: "windman has no eyes, he use air
        # abilities to see" (owner, 2026-09-11).
        "band": face.HEROES["windman"]["band"],
        "stripes": face.HEROES["windman"]["stripes"],
        "hair": dict(zip(("lift", "front", "nape"),
                         (face.HEROES["windman"]["hair_lift"],
                          face.HEROES["windman"]["hair_front"],
                          face.HEROES["windman"]["hair_nape"])), brows=False),
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
        # generate_primm_separate.py's `self.colors`, verbatim and UNGRADED, plus
        # the spike's `lips`. The coat's silver trims and the black V-panel with its
        # cyan lines are NOT here: they are bead 5u3.6's call, and neither is a bone
        # region or a joint-height band.
        "colours": dict(_face_palette("primm"), **{
            "coat_purple": (0.30, 0.15, 0.44, 1.0),
            "coat_collar": (0.25, 0.12, 0.37, 1.0),
            "cuff_grey":   (0.62, 0.68, 0.74, 1.0),
            "glove_black": (0.06, 0.06, 0.07, 1.0),
            "belt_black":  (0.05, 0.05, 0.06, 1.0),
            "belt_buckle": (0.70, 0.72, 0.76, 1.0),
            "jeans_navy":  (0.10, 0.11, 0.17, 1.0),
            "boots_black": (0.07, 0.07, 0.08, 1.0),
        }),
        "bone_regions": {"hand_l": "gloves", "hand_r": "gloves"},
        "colour_key": {"skin": "skin", "shirt": "coat_purple",
                       "trousers": "jeans_navy", "shoes": "boots_black",
                       "gloves": "glove_black",
                       "belt": "belt_black", "belt_buckle": "belt_buckle",
                       "cuff": "cuff_grey", "collar": "coat_collar"},
        "bands": ("belt", "cuff", "collar"),
        # THE GOGGLES ARE PAINT, not cloth — no `band` key. The spike's own ruling:
        # a lens is not a wrap, and stripes on the skin are what shipped.
        "stripes": face.HEROES["primm"]["stripes"],
        "hair": dict(zip(("lift", "front", "nape"),
                         (face.HEROES["primm"]["hair_lift"],
                          face.HEROES["primm"]["hair_front"],
                          face.HEROES["primm"]["hair_nape"])), brows=False),
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
TRI_BUDGET = 14000           # incl. every accessory joined after the collapse
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
GRADED_COLOURS = ("skin", "lips")


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
morphed_coords = face.morphed_coords
joint_centroid = face.joint_centroid


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
        if not os.path.exists(path):
            log("target missing, skipped:", path)
            continue
        TargetService.load_target(human, path, weight=weight)

    coords = morphed_coords(human)
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


def paint_body(obj, tj, row, band_verts=frozenset()):
    """Base region colour by bone-weight argmax, then geometric BAND overrides
    (belt, cuff, collar) scoped by bone region, then the face detail.

    `band_verts` is `wrap_band`'s cloth, if the row wears any: those vertices skip
    the skin entirely and take the row's `stripes` top-down, exactly as the spike's
    own `paint()` does — this is the same face recipe, run on a whole human."""
    colours = dict(row["colours"])
    for key in GRADED_COLOURS:
        colours[key] = graded(colours[key])
    colour_key = row["colour_key"]
    bands = set(row.get("bands", ()))
    stripes = row.get("stripes", ())
    hair = row["hair"]
    for j, (_low, _high, colour) in enumerate(stripes):
        colours[j] = colour
    if stripes:
        colours["seam"] = tuple(c * face.SEAM_DARKEN
                                for c in stripes[-1][2][:3]) + (1.0,)
    me = obj.data
    name_to_id = {vg.name: vg.index for vg in obj.vertex_groups}

    def ids(bones):
        return {name_to_id[b] for b in bones if b in name_to_id}

    region_ids = {r: ids(bones) for r, bones in colour_regions(row).items()}
    scope_ids = {r: ids(bones) for r, bones in REGION_BONES.items()}

    pelvis_z = tj["pelvis"].z
    neck_z = tj["neck"].z
    eye_z = (tj["l-eye"].z + tj["r-eye"].z) / 2.0
    # No joint-l-wrist helper exists; the forearm is roughly as long as the upper
    # arm, so estimate the wrist a forearm-length past the elbow.
    wrist_z = {s: tj["%s-elbow" % s].z
               - (tj["%s-shoulder" % s].z - tj["%s-elbow" % s].z) * 0.85
               for s in ("l", "r")}

    per_vert = [None] * len(me.vertices)
    for i, v in enumerate(me.vertices):
        region = max(region_ids, key=lambda r: _group_weight(v, region_ids[r]))
        key = colour_key[region]

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
        per_vert[i] = key

    # THE HEAD REGION: eyewear, lips, eyebrows, hair — spike_z3e_head.py's paint(),
    # position-relative-to-the-eye-line rather than by skinning weight.
    head_ids = scope_ids["head"]
    lip_z = eye_z - 0.088
    hair_front = eye_z + hair["front"]
    seam_z = eye_z + stripes[0][0] if stripes else 0.0
    half_depth = max((abs(v.co.y) for v in me.vertices
                      if _group_weight(v, head_ids) > 0.4), default=1e-6)
    for i, v in enumerate(me.vertices):
        if i in band_verts:
            # The cloth, top-down and clamped at both ends: the lift and the knots
            # put wrap outside the stripe range it was cut from.
            if abs(v.co.z - seam_z) <= face.SEAM_HALF:
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
        elif lip_z - 0.014 <= v.co.z <= lip_z + 0.010 and depth > 0.55:
            per_vert[i] = "lips"
        elif (hair["brows"] and eye_z + 0.028 <= v.co.z <= eye_z + 0.040
              and depth > 0.45):
            per_vert[i] = "hair"   # eyebrows, above the eye line

    counts = {}
    for k in per_vert:
        counts[k] = counts.get(k, 0) + 1
    log("paint counts:", counts)

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


def build_beret(colours, crown_z, embed=0.032):
    """generate_teibi_separate.py's beret — dome, brim, headband, nub, tilted
    7/-11 degrees — seated on the crown. `embed` sinks the dome's own centre
    3.2 cm below the crown, which is where the generator wears it: a beret sits
    IN the scalp with its top third showing, and anchoring its lowest vertex on
    the crown floats the whole assembly 17 cm off the head (measured on the
    z3e.10 spike)."""
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
    seat = Matrix.Translation(Vector((0.015, 0.004, crown_z - embed)))
    beret.data.transform(seat @ tilt)
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


def join_rigid(target, extra, bone):
    """Join `extra` into `target` with every one of its vertices weighted 1.0 to
    `bone`. The join happens AFTER the rig so MPFB2's automatic weights are
    never asked to guess for a beret; the group is written by hand instead."""
    vg = extra.vertex_groups.new(name=bone)
    vg.add(list(range(len(extra.data.vertices))), 1.0, 'REPLACE')
    bpy.context.view_layer.objects.active = target
    for o in bpy.data.objects:
        o.select_set(o is target or o is extra)
    bpy.ops.object.join()
    return bpy.context.active_object


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

def weight_strays_to(obj, armature, bone):
    """TRAP 8. Any vertex with no bone weight at all goes to `bone`, weight 1.0.

    `wrap_band`'s knots are `bmesh.ops.create_cube` geometry and carry no deform
    layer; everything else it makes is extruded from skin that does. The wrap lives
    entirely on the head, so `head` is not a guess — it is the only bone any of it
    could belong to. Returns how many were swept, so a number that is not the knots'
    two boxes is visible rather than silent."""
    bone_names = {b.name for b in armature.data.bones}
    ids = {vg.index for vg in obj.vertex_groups if vg.name in bone_names}
    vg = obj.vertex_groups.get(bone) or obj.vertex_groups.new(name=bone)
    stray = [v.index for v in obj.data.vertices if _group_weight(v, ids) <= 0.0]
    if stray:
        vg.add(stray, 1.0, 'REPLACE')
    log("swept %d unweighted vert(s) onto %s" % (len(stray), bone))
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


def export_glb(obj, armature, path, sharp=frozenset()):
    """
    SMOOTH, and deliberately not through `predator_parts.export_faceted()`.
    CLAUDE.md calls that "the one export seam for every generated `.glb`
    (heroes included)", and three things put this lane outside it: the y1o
    faceted ruling is WAIVED FOR THE FOUR HEROES by the owner (bd show
    godot-test1-z3e NOTES, 2026-09-06); `export_faceted` is trimesh code and
    cannot be called from Blender at all, its Blender port being
    `blender_hero.py`'s opt-in `--faceted`; and the predecessor this script is a
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
        export_materials='NONE',
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
    row = HEROES[hero]
    if "band" in row and (row["beret"] or row["eyes"]):
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

    band_verts, flat_faces = face.wrap_band(obj, (tj["l-eye"].z + tj["r-eye"].z) / 2.0,
                                            row)
    if band_verts:
        weight_strays_to(obj, armature, "head")
    paint_body(obj, tj, row, band_verts)

    if row["beret"]:
        crown_z = max(v.co.z for v in obj.data.vertices)
        obj = join_rigid(obj, build_beret(row["colours"], crown_z), "head")
    if row["eyes"]:
        obj = join_rigid(obj, build_eyes(row["colours"], tj["l-eye"], tj["r-eye"]),
                         "head")

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
