# Authored Character Models & Provenance

## Forbidden Sources

The following sources are **strictly forbidden** for any hero or character art in this repository:
- **Hunyuan3D**: Licence Territory excludes the EU, UK, and South Korea.
- **Mixamo**: Allowed to ship in a compiled game, but cannot be redistributed standalone as raw assets in a public repository.
- **Rodin / generative AI model output**: Unsettled copyright and IP ownership.
- **Quaternius asset packs** (read 2026-09-11 for the Universal Animation Library, bead
  godot-test1-5u3.1): allowed to ship inside a compiled game, but **not committable to
  this public repo**. The pack page still shows a "(CC0 License)" badge linking to CC0
  1.0, but the site's own governing licence — *Quaternius Asset License (QAL) v1.0, last
  updated 8/28/2026*, linked from the "License" button on that same page — is not CC0.
  Its §3(a) reads, verbatim: *"Resell or redistribute the Assets themselves. You may not
  extract, repackage, sublicense, sell, or otherwise redistribute the Assets (in original
  or modified form) as a standalone asset, asset pack, stock file, template, or similar
  product, whether for free or for payment, and whether alone or bundled with other
  assets. This restriction applies regardless of how much the Assets have been modified.
  It does not restrict distributing a completed Product that merely incorporates the
  Assets."* §7 adds that *"the version in effect at the time you obtained the Assets
  governs"*, so a download made today is governed by QAL v1.0 whatever an older bundled
  licence file says, and §9 makes it the entire agreement. A retargeted clip `.glb`
  sitting in this repository is the asset in modified form as a standalone file, not a
  completed Product — the same reason Mixamo is already on this list.

All shipping character assets must derive from CC0 or equivalently unencumbered sources (MPFB2 / MakeHuman core basemesh and targets, Poly Haven, AmbientCG).

## Source Files (.blend)

Source `.blend` files accompanying authored `.glb` models **are committed to git** directly beside the models. To keep repository size bounded, `.blend` files must be saved with compression enabled and must carry **no multiresolution modifiers or sculpt layers**. Godot never imports them: `project.godot` sets `filesystem/import/blender/enabled=false`, because the Blender importer needs a Blender binary the CI runner lacks and the headless import hangs on the scan.

## Authored Assets

| File | Tool + Version | Source | Licence | Date | .blend |
|---|---|---|---|---|---|
| `teibi_parts/teibi_skinned.glb` | Blender 5.2.1 LTS, MPFB 2.0.17 | `scripts/build_hero.py teibi`, MakeHuman basemesh + targets + `rig.game_engine.json` + `weights.game_engine.json` | CC0 | 2026-09-11, SPIKE godot-test1-5u3.1; rebuilt 2026-09-11 for bead godot-test1-z3e.14 (skin and lips through `SKIN_GRADE`, geometry byte-identical); **shipped** 2026-09-11 by bead godot-test1-5u3.3, rebuilt again with the 30 finger bones collapsed into `hand_l`/`hand_r` (owner ruling — 23 bones) and a low shoe shell over the bare MakeHuman feet; rebuilt 2026-09-12 by bead godot-test1-5u3.4 when the lane was generalised (the face is now its own decimate target at 4,400 triangles, and his landmarks are read off the MORPHED mesh — 13,266 tris, 5,064 of them head); rebuilt 2026-09-12 by bead godot-test1-5u3.10, which turned his clothes into GEOMETRY — uniform trousers with a waistband ridge and a hem 2 cm above the shoe, the mustard polo with a hem below the belt line and a cuff at each wrist, every one of them the body's own surface pushed 1.0-2.4 cm proud over a cut hem ring (`dress_shells`). 13,870 tris (5,064 head), +4.6%, 23 bones, no texture; rebuilt 2026-09-12 by bead godot-test1-z3e.15, which tuned the face TOWARD `assets/portraits/teibi.png` (owner: "faces more similar to our comics") — younger and leaner macros, `head-oval` under a halved `head-round`, cheek BONES instead of cheek volume, `chin-bones-incr` for the jaw, a closed-mouth SMILE (`mouth-angles-up` + the `mouth-corner-puller` expression unit, the epic's first use of MakeHuman's expression targets), a tanned skin, a higher hairline and a beret shrunk 22% across and seated 8 mm deeper so it grips the skull instead of hovering over it. Evidence: `docs/style/z3e/grid_24_faces_vs_comics.png`. 13,872 tris (5,064 head), +0.01%, 23 bones, no texture, 1.8349 m -> 1.8269 m ; rebuilt 2026-09-12 by bead godot-test1-394 (owner: "why do the heroes look like they have a beard? I don't like it") — the lip paint is MakeHuman's own `lips` VERTEX GROUP now, not a z band hung off the eye line: every face target in a `FACES` row moves the mouth against the eyes, so the band had slid onto the chin and round the jaw and read as stubble. The lip colour is derived from the hero's own graded skin (~12% darker with a slight red shift) instead of a hand-picked brown, and `paint_body` now asserts the lowest lip vertex clears the chin. Geometry, bounds, tri count, bone count and .glb size are UNCHANGED (vertex colours only) — 13,872 tris (5,064 head), 23 bones, no texture, 1.8269 m. Evidence: `docs/style/z3e/grid_28_no_beard.png` (today | fixed, at `17_head_face` and the new `21_jaw_1m` jaw close-up, on the web renderer); clipped fraction re-measured 0.22%, unchanged | `teibi_parts/teibi_skinned.blend` |
| `windman_parts/windman_skinned.glb` | Blender 5.2.1 LTS, MPFB 2.0.17 | `scripts/build_hero.py --hero windman`, MakeHuman basemesh + targets + `rig.game_engine.json` + `weights.game_engine.json` | CC0 | 2026-09-12, bead godot-test1-5u3.4 built it unwired; **shipped** 2026-09-12 by bead godot-test1-5u3.5 — `windman_updated.tscn` instances this and nothing else, the ten generated parts and the authored head are retired, and the chest "W" is painted into its vertex colours (`paint_chest_glyph`). 12,649 tris at first build and 13,411 (4,447 head) once the chest densify landed — the manifest's number, and the one the delta below is measured from — 23 bones, no texture; rebuilt 2026-09-12 by bead godot-test1-5u3.10 — the blue T-shirt and the brown knee shorts are geometry now: a torso shell with a hem below the waist, a short cap sleeve to mid-upper-arm (canon: "sleeveless or ... short sleeves that go to mid-shoulder"), and baggy shorts hemmed 3 cm above the knee with bare calf below. 14,185 tris (4,447 head), +5.8%, 23 bones, no texture; rebuilt 2026-09-12 by bead godot-test1-z3e.16 — `wrap_band` now BISECTS the skull at the band's two lines before it lifts the cloth, so the edge that meets the cheek is straight instead of one triangle ragged (`docs/style/z3e/grid_25_windman_band_edge.png`); the two edge rings are what the extra triangles buy. 14,739 tris (5,001 head), +3.9%, 23 bones, no texture; rebuilt 2026-09-12 by bead godot-test1-z3e.15, which tuned the face TOWARD `assets/portraits/windman.png` — the portrait's broad heavy-set man: `weight` and `muscle` up, `head-round` 0.65 -> 0.85 over `head-scale-horiz-incr` and `chin-width-incr` for the square jaw, a short chin, a small mouth, darker lips so the mouth reads as drawn rather than as a pale patch, and a taller crown with a higher hairline. Evidence: `docs/style/z3e/grid_24_faces_vs_comics.png` — portrait, today, tuned on the web renderer, tuned on Forward+, one row per hero. 14,743 tris (5,027 head), +0.03%, 23 bones, no texture, 1.7579 m -> 1.7639 m ; rebuilt 2026-09-12 by bead godot-test1-394 (owner: "why do the heroes look like they have a beard? I don't like it") — the lip paint is MakeHuman's own `lips` VERTEX GROUP now, not a z band hung off the eye line: every face target in a `FACES` row moves the mouth against the eyes, so the band had slid onto the chin and round the jaw and read as stubble. The lip colour is derived from the hero's own graded skin (~12% darker with a slight red shift) instead of a hand-picked brown, and `paint_body` now asserts the lowest lip vertex clears the chin. Geometry, bounds, tri count, bone count and .glb size are UNCHANGED (vertex colours only) — 14,743 tris (5,027 head), 23 bones, no texture, 1.7639 m. Evidence: `docs/style/z3e/grid_28_no_beard.png` (today | fixed, at `17_head_face` and the new `21_jaw_1m` jaw close-up, on the web renderer); clipped fraction re-measured 0.00%, unchanged | `windman_parts/windman_skinned.blend` |
| `primm_parts/primm_skinned.glb` | Blender 5.2.1 LTS, MPFB 2.0.17 | `scripts/build_hero.py --hero primm`, MakeHuman basemesh + targets + `rig.game_engine.json` + `weights.game_engine.json` | CC0 | 2026-09-12, bead godot-test1-5u3.4 built it unwired; **shipped** 2026-09-12 by bead godot-test1-5u3.6 and rebuilt there with the lab coat painted on — the open V of black inner shirt outlined in glowing cyan, silver seams at the jacket hem, the rolled sleeve and the boot rim, the boot shaft up the calf, silver fingertips, and the trousers two stops lighter so the black shaft has something to be black against. 12,602 tris (4,400 head), 23 bones, no texture; rebuilt 2026-09-12 by bead godot-test1-5u3.10 — the coat is a shell 1.8-2.8 cm proud CARVED at the open front (the black inner shirt is recessed and the silver lapel rides the step it leaves), fitted trousers tucked into a boot shaft that swallows them, and two COAT TAILS off the back hem: boxes weighted pelvis 0.6 / thigh 0.4 so they part around the stride rather than being walked through (owner: "like a tuxedo with tails"). 13,178 tris (4,400 head), +4.6%, 23 bones, no texture; rebuilt 2026-09-12 by bead godot-test1-z3e.15, which tuned the face TOWARD `assets/portraits/primm.png` — the goggles' contrast REVERSED (a dark frame around a bright cyan lens, where the shipped silver frame clipped to paper white across the brow) and the band narrowed 5.4 cm -> 4.0 cm, sharper cheekbones with a hollow under them, a thinner nose and mouth, a skin two stops DARKER and a shade cooler, and the hair swept off a higher forehead with more crown volume. Measured on the web renderer with `scripts/clipped_fraction.py`: 14.6% of his face clipped to white before, 2.1% after. Evidence: `docs/style/z3e/grid_24_faces_vs_comics.png`. 13,178 tris (4,400 head), no change, 23 bones, no texture, 1.792 m -> 1.800 m ; rebuilt 2026-09-12 by bead godot-test1-394 (owner: "why do the heroes look like they have a beard? I don't like it") — the lip paint is MakeHuman's own `lips` VERTEX GROUP now, not a z band hung off the eye line: every face target in a `FACES` row moves the mouth against the eyes, so the band had slid onto the chin and round the jaw and read as stubble. The lip colour is derived from the hero's own graded skin (~12% darker with a slight red shift) instead of a hand-picked brown, and `paint_body` now asserts the lowest lip vertex clears the chin. Geometry, bounds, tri count, bone count and .glb size are UNCHANGED (vertex colours only) — 13,178 tris (4,400 head), 23 bones, no texture, 1.8000 m. Evidence: `docs/style/z3e/grid_28_no_beard.png` (today | fixed, at `17_head_face` and the new `21_jaw_1m` jaw close-up, on the web renderer); clipped fraction re-measured 2.10%, unchanged | `primm_parts/primm_skinned.blend` |

THE SKINNED HEROES ARE ONE TABLE NOW, AND ONE SCRIPT. `scripts/build_hero.py`'s
`HEROES` rows are windman, primm and teibi — clothing expressed as bone regions,
joint-height bands and garment shells; the FACE recipes live in the same file's `FACES`
rows and Windman's bandage is its `wrap_band`. Both came from
`scripts/spike_z3e_head.py`, the lane that authored the standalone heads; bead
godot-test1-5u3.8 folded them in and deleted that file, because no head ships on its own
any more — every one is part of its hero's skinned mesh, and the rows above are the
whole authored inventory. Phoboman is NOT in this table: his body stays generated (owner
ruling, 2026-09-11). Colour is vertex colour throughout and no hero here carries a
texture; the numbers above and in `scripts/hero_manifest.json` are one rebuild's output
and the manifest is what CI gates them on.

THE SKIN GRADE. Every hero's skin and lips — the authored faces AND the generated
bodies they sit on — are darkened by one factor, `SKIN_GRADE` in
`scripts/hero_skin.py`, before they are painted or baked (bead godot-test1-z3e.14).
The palettes in the scripts that import it are still each hero's own, verbatim:
they record the paint, that constant records the exposure. A head graded without its
body is a white seam under the chin — and it is why only `build_hero.py` imports it
now: `generate_primm_separate.py` retired with bead godot-test1-5u3.6, and
`generate_windman_fan.py` (`generate_windman_separate.py` until bead 5u3.8 renamed it
after its one output) builds a FAN and nothing else since bead 5u3.5, and a fan has no
skin.

TEIBI, WINDMAN AND PRIMM ARE THE SHIPPED AUTHORED BODIES. `teibi_skinned.glb`,
`windman_skinned.glb` and `primm_skinned.glb` ARE the heroes
`scenes/characters/teibi.tscn`, `windman_updated.tscn` and `primm.tscn` instance —
one skinned mesh each, no parts. Primm's nine generated parts, his authored head
(`primm_head_authored.glb`, its `.blend` and its loose albedo) and
`scripts/generate_primm_separate.py` were retired by bead godot-test1-5u3.6, and
Windman's ten parts and his authored head by bead 5u3.5: neither head is gone, each
is INSIDE its hero's skinned .glb — the same face recipe, now a `FACES` row in
`build_hero.py` itself, built as part of one human, so there is no neck seam left to
hide. The z3e.10 spike's
ten `teibi_*_authored.glb` joint cuts, the `teibi_uncut_authored.glb` whole body, the
`teibi_authored.blend` they shared and the ten generated `teibi_*.glb` that shipped before
them were all retired by bead godot-test1-5u3.3 together with
`scripts/generate_teibi_separate.py` and `scripts/spike_z3e_teibi_body.py`: the spike's
parts pick is superseded by a skeleton, and `teibi_skinned.blend` carries the same
MakeHuman human by construction (`build_hero.py` builds it from the `HEROES` row).

WHAT SURVIVED WINDMAN'S GENERATOR is `windman_fan.glb`: a prop, not a body, hung on the
`hand_r` bone by a `BoneAttachment3D` in `windman_updated.tscn`, still rebuilt and
diffed by CI — which is why `scripts/generate_windman_fan.py` is still a line in that
workflow's rebuild loop when `teibi` and `primm` have none. His chest "W" did not survive as geometry and did not
become a texture either: `build_hero.paint_chest_glyph` paints it into the body's vertex
colours over a chest `densify_chest` splits once, which is what let the `shapely` /
`mapbox-earcut` pins leave `scripts/requirements.txt` with bead 5u3.5.

## Spike Artifacts — the CLOTH columns (bead godot-test1-td8)

`teibi_parts/teibi_cloth_{a,b,d,all}.glb` are SCRATCH builds and **nothing loads them**.
No `.tscn` references one, `player_controller.CHARACTERS` does not name one, and the
only code in this repo that opens one is `scripts/style_shots.gd`'s `cloth=<a|b|d|all>`
argument — a debug tool reached from the command line. They are committed for the same
reason bead z3e.10's cut-joint bodies were: the grid the owner rules from
(`docs/style/z3e/grid_27_cloth_spike.png`) is evidence only while the meshes behind it
can still be re-rendered.

Same source as the shipped Teibi and the same licence: MakeHuman / MPFB2 (CC0), built by
`scripts/build_hero.py` from the SAME `HEROES["teibi"]` row, with one column's extra
passes turned on by `--variant`:

| file | column | pass | tris | bytes |
|---|---|---|---|---|
| `teibi_skinned.glb` | today (the control, and the SHIPPED hero) | — | 13,872 | 453,116 |
| `teibi_cloth_a.glb` | A | procedural folds displaced along the garment normal | 21,742 | 704,968 |
| `teibi_cloth_b.glb` | B | occlusion + cavity multiplied into the vertex colours | 13,872 | 453,116 |
| `teibi_cloth_d.glb` | D | the garments on their own `HeroCloth` material | 13,872 | 466,768 |
| `teibi_cloth_all.glb` | all | A + B + D | 21,742 | 725,888 |

Column **C** (a 512² fabric albedo on UV-unwrapped shells) is **NOT BUILT** — the spike's
clock ran out before it. There is no `teibi_cloth_c.glb` and `--variant c` refuses with
that reason rather than building something else and calling it C.

They carry NO `.blend`: a shipped hero's source of record is its committed `.blend`, a
scratch column's is this script plus its `--variant` name (`build()` skips the save for
exactly that reason). The four `teibi_cloth_*.glb` are outside the manifest by
construction — `--variant` refuses to run with `--check` or `--all` — so the `stat` gate
below and `--all --check` both keep saying exactly what they said before this bead, about
the three SHIPPED heroes and nothing else. (`teibi_skinned.glb`, the first row of the
table, is the control column AND the shipped hero: the gate does cover it, and it is
byte-identical on this branch, which is the point of listing it there.)

**They do not ship.** Godot packs by resource and not by reference, so committing them
would otherwise put 1.53 MB of geometry nothing instantiates into the web download; the
Web preset's `exclude_filter` in `export_presets.cfg` names them. A `.gdignore` would have
worked for the export and broken the spike, since `style_shots.gd` has to be able to load
them.

Rebuild:

```bash
perl -e 'alarm 1800; exec @ARGV' blender --background --python-exit-code 1 \
    --python scripts/build_hero.py -- --hero teibi --variant b --variant a \
    --variant d --variant all
godot --headless --path . --import
```

## CI Model Gate

The CI model rebuild step (`.github/workflows/build.yml`) only runs the procedural generators (`generate_windman_fan.py` — his FAN alone since bead godot-test1-5u3.5 — `generate_phoboman_separate.py`, which still builds his whole part tree, and `predator_parts.py`). Because the generators no longer emit these authored file names — and, since beads godot-test1-5u3.3 and .6, there is no Teibi or Primm generator at all — `git status --porcelain -- assets/models/characters` stays clean by construction; a generated part edited by hand is still caught immediately. `build_hero.py` needs Blender and MPFB2, which the runner does not have, so the skinned bodies are outside that gate — and, since bead godot-test1-5u3.4, they have their own: a `stat`-only step asserts every skinned `.glb`'s byte size still matches its row in `scripts/hero_manifest.json`, which `build_hero.py` rewrites on every rebuild. A hand-edited skinned hero is caught there the way a hand-edited hydra is caught by the dirty check. The full rebuild-and-diff is `build_hero.py -- --all --check`, run by hand where Blender exists; size and not a checksum, because the glTF exporter may permute one primitive's triangle order between two otherwise identical runs.
