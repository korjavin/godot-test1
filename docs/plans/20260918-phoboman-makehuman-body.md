# Phoboman's body on the MakeHuman rig — bead godot-test1-9k9n.1

Epic `godot-test1-9k9n`, owner ruling 2026-09-18 (option B): Phoboman is rebuilt as a
heavy HUMAN on the same 23-bone `game_engine` rig, materials and cloth as the trio, so the
cast reads as one cast. This child builds the BODY only — the `.glb` is unwired until
child `.2` (the precedent is bead 5u3.4, which shipped windman/primm unwired).

The lane is `scripts/build_hero.py` and a hero is a `HEROES` row. There is no second
script and no new pipeline stage: a fourth row plus two accessory builders.

## Tasks

1. **The fourth row.** `HEROES["phoboman"]`: inline macros (gender ~0.9, weight 1.0,
   muscle ~0.6, proportions low), MakeHuman stomach/torso/legs/arms targets for the
   teaspoon build, the generator's palette verbatim plus `pants_black`, `bone_regions`
   for bare arms and black legs, three `garments` (blue belly shell, short black pants,
   boot shafts), `bands: ()`, `beret`/`eyes` False, no `band`, `height` ~1.70,
   `out_dir: "phoboman_parts"`, `stem: "phoboman_skinned"`. No `FACES` row: the face is
   inside the helmet and the helmet carries the pho-bowl face as geometry.

2. **The per-row head budget.** `row.get("head_tris", HEAD_TRIS)` in `build()`'s
   `decimate` call and the `HEAD_TRIS_MIN` floor exempted for a row that carries
   `"helmet": True`. The saved triangles pay for the helmet and the dragon;
   `TRI_BUDGET` is the backstop and is not raised.

3. **`build_helmet`.** The generator's `create_head_assembly` ported piece by piece —
   dome, collar, valve knob, rivets, porthole rim, glass, broth, highlight, two noodle
   eye rings and pupils, herb nose and flecks, noodle strands — seated on the head's
   OWN measured landmarks (crown, eye line, neck, half-width) rather than the
   generator's sphere-head numbers, `FLOAT_COLOR` vertex-painted from the palette, and
   joined with `join_rigid(..., "head")` so the gait's head bobble nods the whole
   helmet. Flat-shaded through `export_glb`'s `sharp` set.

4. **`build_dragon`.** The generator's swept red tube laid on the BELLY's own evaluated
   surface (BVH ray, `_face_front`'s idiom), standing ~1.2 cm proud, from the left flank
   to the middle. Joined with `join_weighted`, weights split per vertex across
   `spine_01`/`spine_02`/`spine_03`, BEFORE `bake_cloth_shading` so the belly shell's
   occlusion sees it. On `HeroSkin`, not in the cloth group.

5. **The build.** `--hero phoboman` green (every ASSERT OK), then `--all --check` green
   with the trio's `.glb` byte sizes and manifest rows untouched. `hero_manifest.json`
   and the `.glb` in the same commit (build.yml's `stat` step). `.blend` compressed, no
   multires. `godot --headless --path . --import` after the rebuild.

6. **The paperwork.** `PROVENANCE.md`: Phoboman's row in the Authored Assets table in
   Primm's style, and the "Phoboman is NOT in this table" sentence goes.
   `build_hero.py`'s header gains the fourth row and the helmet/dragon accessories.
   `docs/style/z3e/build_hero_rest_row.png` re-shot with four heroes;
   `docs/style/z3e/grid_33_phoboman_blender.png` is the owner's evidence grid.

## Out of scope

`phoboman.tscn`, the GAITS row, `gait_selfcheck`, the limb-rig retirement and the ten
generated part `.glb` — children `.2` and `.3`.
