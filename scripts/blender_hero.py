"""
scripts/blender_hero.py — bpy + stdlib only. The Blender import/export lane for hero
parts (bead godot-test1-z3e.3): reproduce a hero's whole node tree from its .tscn
inside Blender so a part can be edited in context, and write ONE edited part back
into the repo's glTF convention.

Run OUTSIDE Blender, invoking it headless (bound with `perl -e 'alarm 900; exec
@ARGV' ...` — there is no `timeout` binary here):

  blender --background --python-exit-code 1 --python scripts/blender_hero.py -- \
      import <hero> [--screenshot <path.png>]
  blender --background --python-exit-code 1 --python scripts/blender_hero.py -- \
      export <hero> <part> --out <path.glb> [--faceted]

<hero> is one of windman, primm, teibi, phoboman (scripts/player_controller.gd's
CHARACTERS); windman's scene is windman_updated.tscn, the other three are plain
scenes/characters/<hero>.tscn. <part> is a leaf part name (e.g. "head", "torso") or,
where that is ambiguous (both arms/legs reuse "UpperArm"/"LowerLeg"/"Mesh"), the
node's full .tscn path with "/" written as ".", e.g. "leftarm.upperarm".

No armature, no rigging, no animation — this lane only moves geometry. Not run in
CI (Blender is not on the runner); it is a tool like scripts/style_shots.gd.

THE TWO COORDINATE TRAPS (bead godot-test1-z3e.3's NOTES: paid for once on
2026-09-06 building the head spike, scripts/spike_z3e_head.py — READ THESE BEFORE
TOUCHING THE MATRIX MATH BELOW, do not re-derive them by trial and error):

1. "Transform3D(...) in a .tscn is ROW-major: the repeated part basis (1,0,0,
   0,0,1, 0,-1,0) is Rx(-90). Reading it as three column axis-vectors gives the
   transpose — the inverse rotation — and every limb mirrors about its joint
   (boots at the knee, feet 0.2 m off the ground). Build the matrix from rows."

2. "Blender's glTF importer bakes Y-up→Z-up into the MESH DATA, not only the
   object matrix. Build the rig in Godot coordinates and conjugate once:
   W_blender = Rx(90) · W_godot · Rx(90)^-1 — Rx(+90) on the root empty, Rx(-90)
   on every mesh object."

HOW THIS FILE ENCODES THEM. Trap 1: `parse_transform()` below fills a 3x3 straight
from the 12 numbers taken 3-at-a-time as ROWS (`Matrix(((xx,xy,xz,...), (yx,yy,yz,
...), (zx,zy,zz,...), ...))`) — never as three axis-vector columns. Trap 2, measured
directly on windman_head.glb on 2026-09-08 (this bead): importing it leaves
matrix_world/matrix_basis at IDENTITY and instead rewrites the vertex data itself —
x unchanged, y_new = -z_old, z_new = y_old, exactly Rx(+90) applied to the raw glTF
accessor. So on import (`build_hero()`), every instance node's local matrix is built
as the .tscn's own row-major T_node composed with a TRAILING Rx(-90) that undoes
that bake, and the whole rig then sits, node-for-node, exactly where Godot puts it;
only the scene ROOT additionally carries a LEADING Rx(+90) so the assembly stands
up the right way in Blender's Z-up viewport instead of lying on its back (a pure
rotation of the whole assembled shape — the per-mesh Rx(-90) already cancels the
bake before that outer Rx(+90) is even applied, so nothing downstream needs its own
correction). On export (`export_part()`) the same Rx(-90) undoes the OTHER half:
read the current, possibly hand-edited mesh data as it now sits in the rig and
rotate it by the fixed Rx(-90) to land back in the file's own Z-up, part-local
frame — the one the .tscn's untouched Transform3D already expects.

The height/feet assert below (`assert_height_and_feet`) is what catches trap 1 the
moment it regresses: get the row/column read backwards and a limb mirrors about its
joint, which throws the assembled bounding box and the feet position off hard
enough to fail immediately, well before anyone opens a screenshot.
"""

import argparse
import math
import os
import re
import sys

import bpy
from mathutils import Matrix, Vector

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHAR_DIR = os.path.join(REPO, "scenes", "characters")

# scripts/player_controller.gd's CHARACTERS array. Windman's scene is the
# "_updated" rebuild (windman_3d.tscn / generate_windman_model.py are dead art).
HERO_SCENES = {
    "windman": "windman_updated.tscn",
    "primm": "primm.tscn",
    "teibi": "teibi.tscn",
    "phoboman": "phoboman.tscn",
    # SPIKE godot-test1-z3e.10, scratch scenes only — NOT in
    # player_controller.gd's CHARACTERS, so no selfcheck ever loads them.
    "teibi_authored": "teibi_authored.tscn",
    "teibi_uncut": "teibi_uncut.tscn",
}

# The bead's height/feet assert. Ranges are MEASURED on this branch (2026-09-08),
# not the bead's own rough guess, per CLAUDE.md ("the measured numbers ... live
# next to the code"): windman 1.7536 m, primm 1.7733 m (1.7931 before bead
# godot-test1-z3e.5 gave him the authored head, whose crown sits 2 cm lower than
# the generated sphere's hair cap), teibi 1.7847 m, all inside
# the default band; phoboman measures 1.6344 m -- taller than the bead text's
# offhand "~1.4-1.5", because bead godot-test1-z3e.7 (closing the neck gap,
# merged after this bead was filed) raised its torso/head relative to its legs.
HEIGHT_RANGE = {"phoboman": (1.55, 1.72)}
DEFAULT_HEIGHT_RANGE = (1.65, 1.85)
# Real per-hero boot geometry puts the sole between -2.5 cm and +3.2 cm of z=0
# across the four heroes (measured 2026-09-08); trap 1 regressing throws this off
# by ~20 cm, two orders of magnitude past this tolerance, so this stays a tight
# catch of the real bug without flagging ordinary per-model variance.
FEET_TOLERANCE = 0.04  # metres


def rot_x(deg):
    return Matrix.Rotation(math.radians(deg), 4, 'X')


RX_POS90 = rot_x(90)
RX_NEG90 = rot_x(-90)


def log(*a):
    print("[blender_hero]", *a)
    sys.stdout.flush()


# ---------------------------------------------------------------------------
# .tscn parsing. Every hero scene here is written by hand in the same small,
# fixed subset of Godot's text-resource grammar (one ext_resource per part, one
# [node] per bone/part with an optional single-line `transform =`), so a couple
# of regexes cover it — no need for a general .tscn parser.
# ---------------------------------------------------------------------------

_EXT_RE = re.compile(r'\[ext_resource\s+type="PackedScene"\s+path="([^"]+)"\s+id="([^"]+)"\]')
_NODE_RE = re.compile(
    r'\[node\s+name="([^"]+)"'
    r'(?:\s+type="([^"]+)")?'
    r'(?:\s+parent="([^"]+)")?'
    r'(?:\s+instance=ExtResource\("([^"]+)"\))?\]'
)
_XFORM_RE = re.compile(r'transform\s*=\s*Transform3D\(([^)]+)\)')


class TscnNode:
    def __init__(self, name, path, parent_path, ext_id, xform):
        self.name = name              # this node's own name, e.g. "Head"
        self.path = path              # full path from scene root, "." for the root
        self.parent_path = parent_path  # raw parent= attribute, None for the root
        self.ext_id = ext_id          # ext_resource id if this node instances a .glb
        self.xform = xform            # 4x4 Matrix, or None (== identity)


def parse_transform(text):
    """TRAP 1. The 12 numbers are ROW-major (Godot's Basis::set fills its three
    internal rows directly from the first 9 args) — NOT three x/y/z axis COLUMN
    vectors, which is what the *other*, Vector3-based Transform3D constructor takes
    and what a skim of the docs suggests. Reading columns gives the transposed
    (inverse) rotation. Build the matrix from rows, exactly as Godot does."""
    xx, xy, xz, yx, yy, yz, zx, zy, zz, ox, oy, oz = (float(x) for x in text.split(","))
    return Matrix((
        (xx, xy, xz, ox),
        (yx, yy, yz, oy),
        (zx, zy, zz, oz),
        (0.0, 0.0, 0.0, 1.0),
    ))


def parse_tscn(path):
    """Returns (ext_resources: {id: absolute .glb path}, nodes: [TscnNode], in the
    file's own order — parent nodes are always written before their children."""
    ext = {}
    nodes = []
    with open(path) as f:
        lines = f.readlines()
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        m = _EXT_RE.match(line)
        if m:
            rel_path, rid = m.groups()
            ext[rid] = os.path.join(REPO, rel_path[len("res://"):])
            i += 1
            continue
        m = _NODE_RE.match(line)
        if m:
            name, _ntype, parent, ext_id = m.groups()
            if parent is None:
                node_path = "."
            elif parent == ".":
                node_path = name
            else:
                node_path = parent + "/" + name
            xform = None
            j = i + 1
            while j < len(lines):
                nxt = lines[j].strip()
                if not nxt or nxt.startswith("["):
                    break
                xm = _XFORM_RE.match(nxt)
                if xm:
                    xform = parse_transform(xm.group(1))
                j += 1
            nodes.append(TscnNode(name, node_path, parent, ext_id, xform))
            i = j
            continue
        i += 1
    return ext, nodes


# ---------------------------------------------------------------------------
# Import: reproduce the .tscn's node tree in Blender.
# ---------------------------------------------------------------------------

def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)


def import_part_mesh(glb_path):
    """Import one part .glb. TRAP 2, measured on windman_head.glb (2026-09-08):
    the importer leaves the new object's matrix_world/matrix_basis at IDENTITY and
    bakes the Y-up->Z-up turn into the MESH DATA instead (x unchanged, y_new =
    -z_old, z_new = y_old — Rx(+90) on the raw glTF accessor). Every part .glb this
    lane touches is a single MESH node with no wrapper empty."""
    before = set(bpy.data.objects.keys())
    bpy.ops.import_scene.gltf(filepath=glb_path)
    new_names = set(bpy.data.objects.keys()) - before
    new = [bpy.data.objects[n] for n in new_names]
    if len(new) != 1 or new[0].type != 'MESH':
        raise AssertionError("expected exactly one MESH object from %s, got %r" % (glb_path, new))
    return new[0]


def build_hero(hero):
    """Import every part named in <hero>'s .tscn and reproduce the node tree under
    empties, exactly as Godot lays it out (TRAP 1: rows), with the Y-up/Z-up
    bake (TRAP 2) undone on every mesh and re-applied once at the root.

    Returns (built: {tscn path: bpy object}, meshes: [bpy object], nodes: [TscnNode]).
    """
    scene_path = os.path.join(CHAR_DIR, HERO_SCENES[hero])
    ext, nodes = parse_tscn(scene_path)
    clear_scene()

    built = {}
    meshes = []
    for node in nodes:
        local = node.xform if node.xform is not None else Matrix.Identity(4)
        name = hero if node.parent_path is None else node.path.replace("/", ".")

        if node.ext_id:
            obj = import_part_mesh(ext[node.ext_id])
            # TRAP 2: undo the bake so this node's own (TRAP-1-correct) Transform3D
            # places the part exactly where Godot's node tree puts it.
            obj.matrix_basis = local @ RX_NEG90
            meshes.append(obj)
        else:
            obj = bpy.data.objects.new(name, None)
            obj.empty_display_size = 0.05
            bpy.context.collection.objects.link(obj)
            obj.matrix_basis = local
        obj.name = name

        if node.parent_path is None:
            # TRAP 2's other half: one correction at the root stands the whole
            # Godot-Y-up rig upright in Blender's Z-up viewport.
            obj.matrix_basis = RX_POS90 @ obj.matrix_basis
        else:
            obj.parent = built[node.parent_path]
        built[node.path] = obj

    bpy.context.view_layer.update()
    return built, meshes, nodes


def assert_height_and_feet(hero, meshes):
    """The check that catches TRAP 1 the moment it regresses: get the row/column
    read backwards and a limb mirrors about its joint, throwing the assembled
    bounding box and the feet position off immediately."""
    corners_z = [
        (obj.matrix_world @ Vector(c)).z
        for obj in meshes
        for c in obj.bound_box
    ]
    zmin, zmax = min(corners_z), max(corners_z)
    height = zmax - zmin
    lo, hi = HEIGHT_RANGE.get(hero, DEFAULT_HEIGHT_RANGE)
    if not (lo <= height <= hi):
        raise AssertionError(
            "%s assembled height %.4f m is outside [%.2f, %.2f] m -- trap 1 "
            "(row-major Transform3D) regressed?" % (hero, height, lo, hi))
    if abs(zmin) > FEET_TOLERANCE:
        raise AssertionError(
            "%s feet at z=%.4f, more than %.2f m from the ground -- trap 1 "
            "(row-major Transform3D) regressed?" % (hero, zmin, FEET_TOLERANCE))
    log("%s: height %.4f m, feet z=%.4f -- OK" % (hero, height, zmin))
    return height, zmin


def screenshot(path, height_hint):
    """Render the assembled hero from the game's third-person distance (~4 m,
    slightly above), Workbench: no material/light setup needed, fast headless."""
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


# ---------------------------------------------------------------------------
# Export: write ONE part back in the repo's convention.
# ---------------------------------------------------------------------------

def find_part(nodes, query):
    """A part is any node that instances a .glb. Look it up by its own (leaf) name
    if that is unique among parts, else by its full path with "/" written as "."."""
    q = query.strip().lower()
    parts = [n for n in nodes if n.ext_id]
    by_leaf = {}
    for n in parts:
        by_leaf.setdefault(n.name.lower(), []).append(n)
    if q in by_leaf and len(by_leaf[q]) == 1:
        return by_leaf[q][0]
    by_path = {n.path.lower().replace("/", "."): n for n in parts}
    if q in by_path:
        return by_path[q]
    if q in by_leaf:
        raise SystemExit("part %r is ambiguous: %s" % (query, [n.path for n in by_leaf[q]]))
    raise SystemExit("no part %r; choices: %s" % (query, sorted(by_path)))


def make_faceted(mesh):
    """THE export_faceted RULE IN BLENDER TERMS (predator_parts.py's export_faceted,
    ported): Edge Split every edge so each vertex belongs to exactly one face, then
    flat-shade, so each corner's normal is exactly that face's."""
    for e in mesh.edges:
        e.use_edge_sharp = True
    obj = [o for o in bpy.data.objects if o.data is mesh][0]
    mod = obj.modifiers.new("EdgeSplit", 'EDGE_SPLIT')
    mod.use_edge_angle = False
    mod.use_edge_sharp = True
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    for poly in obj.data.polygons:
        poly.use_smooth = False
    obj.data.update()


def assert_no_multires():
    """The NOTES ruling: Blender source files are committed to git, not R2, on the
    measured assumption that a retopo'd part's .blend is ~1-5 MB. A MULTIRES
    modifier's subdivision levels (or dyntopo sculpt data) is the one thing that
    blows that budget up, so a .blend this lane writes may carry neither."""
    for obj in bpy.data.objects:
        for mod in getattr(obj, "modifiers", []):
            if mod.type == 'MULTIRES':
                raise AssertionError(
                    "%s carries a MULTIRES modifier (%s) -- the repo commits .blend "
                    "files raw on the assumption a retopo'd part is ~1-5 MB; a "
                    "multires-sculpted mesh blows past that." % (obj.name, mod.name))
        if obj.type == 'MESH' and getattr(obj, "use_dynamic_topology_sculpting", False):
            raise AssertionError("%s has dyntopo sculpt data enabled" % obj.name)


def export_part(built, nodes, query, out_path, faceted):
    node = find_part(nodes, query)
    obj = built[node.path]

    # Work on a throwaway copy so the assembled rig (and its history, if this were
    # run interactively) is untouched by the bake below.
    tmp = obj.copy()
    tmp.data = obj.data.copy()
    bpy.context.collection.objects.link(tmp)
    tmp.parent = None
    # TRAP 2, in reverse: the mesh's current data sits ready for the Godot-frame
    # rig (already Rx(-90)'d relative to the import bake); undo exactly that one
    # fixed rotation to land back in the file's own Z-up, part-local frame -- the
    # SAME frame the .tscn's untouched Transform3D already expects on re-import.
    tmp.matrix_basis = RX_NEG90
    for o in bpy.data.objects:
        o.select_set(o is tmp)
    bpy.context.view_layer.objects.active = tmp
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    if faceted:
        make_faceted(tmp.data)

    has_color = bool(tmp.data.color_attributes)
    has_material = bool(tmp.data.materials)
    has_uv = bool(tmp.data.uv_layers)

    for o in bpy.data.objects:
        o.select_set(o is tmp)
    bpy.context.view_layer.objects.active = tmp
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        # THE .tscn's Rx(-90) IS AUTHORED AGAINST THE GENERATORS' TRIMESH OUTPUT,
        # WHICH DOES NOT CONVERT UP AXES (see spike_z3e_head.py's export()): every
        # shipped part .glb is Z-up, and the node's own Rx(-90) is exactly what
        # turns that into Godot's Y-up world. export_yup=True would write glTF's
        # own Y-up convention and lay the part on its back.
        export_yup=False,
        export_normals=True,
        export_tangents=False,
        export_vertex_color='ACTIVE' if has_color else 'NONE',
        export_all_vertex_colors=False,
        export_texcoords=has_uv,
        export_materials='EXPORT' if has_material else 'NONE',
        export_image_format='AUTO' if has_material else 'NONE',
    )
    tmp.data.calc_loop_triangles()
    tri_count = len(tmp.data.loop_triangles)
    log("wrote %s (%d tris, %d bytes)" % (out_path, tri_count, os.path.getsize(out_path)))

    assert_no_multires()
    blend_path = os.path.splitext(out_path)[0] + ".blend"
    bpy.ops.wm.save_as_mainfile(filepath=blend_path, compress=True)
    log("wrote", blend_path)


# ---------------------------------------------------------------------------

def main():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []

    parser = argparse.ArgumentParser(prog="blender_hero.py")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_import = sub.add_parser("import")
    p_import.add_argument("hero", choices=sorted(HERO_SCENES))
    p_import.add_argument("--screenshot")

    p_export = sub.add_parser("export")
    p_export.add_argument("hero", choices=sorted(HERO_SCENES))
    p_export.add_argument("part")
    p_export.add_argument("--out", required=True)
    p_export.add_argument("--faceted", action="store_true")

    args = parser.parse_args(argv)

    if args.cmd == "import":
        built, meshes, nodes = build_hero(args.hero)
        height, _feet = assert_height_and_feet(args.hero, meshes)
        if args.screenshot:
            screenshot(args.screenshot, height)
    else:
        built, meshes, nodes = build_hero(args.hero)
        export_part(built, nodes, args.part, args.out, args.faceted)

    log("done")


if __name__ == "__main__":
    main()
