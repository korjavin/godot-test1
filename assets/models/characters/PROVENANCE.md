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
| `windman_head_authored.glb` | Blender 5.2.1 LTS, MPFB 2.0.17 | `scripts/spike_z3e_head.py`, MakeHuman basemesh + targets | CC0 | 2026-09-06 built, 2026-09-08 shipped, 2026-09-11 bead godot-test1-z3e.13 (rebuilt: the bandage is cloth geometry, the eye sockets under it are gone, and the head is cut at the evaluated neck like Primm's), 2026-09-11 bead godot-test1-z3e.14 (rebuilt: skin and lips through `SKIN_GRADE`, geometry byte-identical) | `windman_head_authored.blend` |
| `windman_head_authored_windman_head_albedo.png` | Blender 5.2.1 LTS, MPFB 2.0.17 | `scripts/spike_z3e_head.py`, MakeHuman basemesh + targets | CC0 | 2026-09-06 built, 2026-09-08 shipped, 2026-09-11 bead godot-test1-z3e.13, 2026-09-11 bead godot-test1-z3e.14 (re-baked darker) | `windman_head_authored.blend` |
| `primm_parts/primm_head_authored.glb` | Blender 5.2.1 LTS, MPFB 2.0.17 | `scripts/spike_z3e_head.py --hero primm`, MakeHuman basemesh + targets | CC0 | 2026-09-11, beads godot-test1-z3e.5 then z3e.12 (rebuilt: morphed landmarks + Primm's own macro recipe) then z3e.14 (rebuilt: skin and lips through `SKIN_GRADE`, geometry byte-identical) | `primm_parts/primm_head_authored.blend` |
| `primm_parts/primm_head_authored_primm_head_albedo.png` | Blender 5.2.1 LTS, MPFB 2.0.17 | `scripts/spike_z3e_head.py --hero primm`, MakeHuman basemesh + targets | CC0 | 2026-09-11, beads godot-test1-z3e.5 then z3e.12 (rebuilt: morphed landmarks + Primm's own macro recipe) then z3e.14 (re-baked darker) | `primm_parts/primm_head_authored.blend` |
| `teibi_parts/teibi_skinned.glb` | Blender 5.2.1 LTS, MPFB 2.0.17 | `scripts/build_hero.py teibi`, MakeHuman basemesh + targets + `rig.game_engine.json` + `weights.game_engine.json` | CC0 | 2026-09-11, SPIKE godot-test1-5u3.1; rebuilt 2026-09-11 for bead godot-test1-z3e.14 (skin and lips through `SKIN_GRADE`, geometry byte-identical); **shipped** 2026-09-11 by bead godot-test1-5u3.3, rebuilt again with the 30 finger bones collapsed into `hand_l`/`hand_r` (owner ruling — 23 bones) and a low shoe shell over the bare MakeHuman feet | `teibi_parts/teibi_skinned.blend` |

Each authored head's 512x512 albedo is EMBEDDED in its `.glb` — that is the copy Godot
renders. The loose `*_head_authored_*_head_albedo.png` beside each one is the same bake
written out again by `spike_z3e_head.py` as the readable source of it; nothing in the
game loads it. It is written AFTER the export, because giving the image a filepath
before it puts that name inside the `.glb` (bead godot-test1-z3e.12, which found Primm's
copy still showing the z3e.5 palette — the glTF exporter never wrote one at all).

THE SKIN GRADE. Every hero's skin and lips — the authored faces AND the generated
bodies they sit on — are darkened by one factor, `SKIN_GRADE` in
`scripts/hero_skin.py`, before they are painted or baked (bead godot-test1-z3e.14).
The palettes in the four scripts that import it are still each hero's own, verbatim:
they record the paint, that constant records the exposure. A head graded without its
body is a white seam under the chin, which is why `generate_windman_separate.py` and
`generate_primm_separate.py` import it too.

TEIBI IS THE ONE SHIPPED AUTHORED BODY. `teibi_parts/teibi_skinned.glb` IS the hero
`scenes/characters/teibi.tscn` instances — one skinned mesh, no parts. The z3e.10 spike's
ten `teibi_*_authored.glb` joint cuts, the `teibi_uncut_authored.glb` whole body, the
`teibi_authored.blend` they shared and the ten generated `teibi_*.glb` that shipped before
them were all retired by bead godot-test1-5u3.3 together with
`scripts/generate_teibi_separate.py` and `scripts/spike_z3e_teibi_body.py`: the spike's
parts pick is superseded by a skeleton, and `teibi_skinned.blend` carries the same
MakeHuman human by construction (`build_hero.py` builds it from the `HEROES` row).

## CI Model Gate

The CI model rebuild step (`.github/workflows/build.yml`) only runs the procedural generators (`generate_*_separate.py` for windman/primm/phoboman, and `predator_parts.py`). Because the generators no longer emit these authored file names — and, since bead godot-test1-5u3.3, there is no Teibi generator at all — `git status --porcelain -- assets/models/characters` stays clean by construction; a generated part edited by hand is still caught immediately. `build_hero.py` needs Blender and MPFB2, which the runner does not have, so the skinned bodies are outside that gate and their rows here are the record instead.
