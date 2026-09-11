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
| `teibi_parts/teibi_head_authored.glb` | Blender 5.2.1 LTS, MPFB 2.0.17 | `scripts/spike_z3e_teibi_body.py`, MakeHuman basemesh + targets + `weights.game_engine.json` (bone-weight piece split) | CC0 | 2026-09-08, SPIKE godot-test1-z3e.10, not shipped | `teibi_parts/teibi_authored.blend` |
| `teibi_parts/teibi_torso_authored.glb` | Blender 5.2.1 LTS, MPFB 2.0.17 | `scripts/spike_z3e_teibi_body.py`, MakeHuman basemesh + targets + `weights.game_engine.json` | CC0 | 2026-09-08, SPIKE godot-test1-z3e.10, not shipped | `teibi_parts/teibi_authored.blend` |
| `teibi_parts/teibi_left_upper_arm_authored.glb` | Blender 5.2.1 LTS, MPFB 2.0.17 | `scripts/spike_z3e_teibi_body.py`, MakeHuman basemesh + targets + `weights.game_engine.json` | CC0 | 2026-09-08, SPIKE godot-test1-z3e.10, not shipped | `teibi_parts/teibi_authored.blend` |
| `teibi_parts/teibi_left_lower_arm_authored.glb` | Blender 5.2.1 LTS, MPFB 2.0.17 | `scripts/spike_z3e_teibi_body.py`, MakeHuman basemesh + targets + `weights.game_engine.json` | CC0 | 2026-09-08, SPIKE godot-test1-z3e.10, not shipped | `teibi_parts/teibi_authored.blend` |
| `teibi_parts/teibi_right_upper_arm_authored.glb` | Blender 5.2.1 LTS, MPFB 2.0.17 | `scripts/spike_z3e_teibi_body.py`, MakeHuman basemesh + targets + `weights.game_engine.json` | CC0 | 2026-09-08, SPIKE godot-test1-z3e.10, not shipped | `teibi_parts/teibi_authored.blend` |
| `teibi_parts/teibi_right_lower_arm_authored.glb` | Blender 5.2.1 LTS, MPFB 2.0.17 | `scripts/spike_z3e_teibi_body.py`, MakeHuman basemesh + targets + `weights.game_engine.json` | CC0 | 2026-09-08, SPIKE godot-test1-z3e.10, not shipped | `teibi_parts/teibi_authored.blend` |
| `teibi_parts/teibi_left_upper_leg_authored.glb` | Blender 5.2.1 LTS, MPFB 2.0.17 | `scripts/spike_z3e_teibi_body.py`, MakeHuman basemesh + targets + `weights.game_engine.json` | CC0 | 2026-09-08, SPIKE godot-test1-z3e.10, not shipped | `teibi_parts/teibi_authored.blend` |
| `teibi_parts/teibi_left_lower_leg_authored.glb` | Blender 5.2.1 LTS, MPFB 2.0.17 | `scripts/spike_z3e_teibi_body.py`, MakeHuman basemesh + targets + `weights.game_engine.json` | CC0 | 2026-09-08, SPIKE godot-test1-z3e.10, not shipped | `teibi_parts/teibi_authored.blend` |
| `teibi_parts/teibi_right_upper_leg_authored.glb` | Blender 5.2.1 LTS, MPFB 2.0.17 | `scripts/spike_z3e_teibi_body.py`, MakeHuman basemesh + targets + `weights.game_engine.json` | CC0 | 2026-09-08, SPIKE godot-test1-z3e.10, not shipped | `teibi_parts/teibi_authored.blend` |
| `teibi_parts/teibi_right_lower_leg_authored.glb` | Blender 5.2.1 LTS, MPFB 2.0.17 | `scripts/spike_z3e_teibi_body.py`, MakeHuman basemesh + targets + `weights.game_engine.json` | CC0 | 2026-09-08, SPIKE godot-test1-z3e.10, not shipped | `teibi_parts/teibi_authored.blend` |
| `teibi_parts/teibi_uncut_authored.glb` | Blender 5.2.1 LTS, MPFB 2.0.17 | `scripts/spike_z3e_teibi_body.py`, MakeHuman basemesh + targets | CC0 | 2026-09-08, SPIKE godot-test1-z3e.10, not shipped | `teibi_parts/teibi_authored.blend` |
| `teibi_parts/teibi_skinned.glb` | Blender 5.2.1 LTS, MPFB 2.0.17 | `scripts/build_hero.py teibi`, MakeHuman basemesh + targets + `rig.game_engine.json` + `weights.game_engine.json` | CC0 | 2026-09-11, SPIKE godot-test1-5u3.1, rebuilt 2026-09-11 for bead godot-test1-z3e.14 (skin and lips through `SKIN_GRADE`, geometry byte-identical), not shipped | `teibi_parts/teibi_skinned.blend` |

Each authored head's 512x512 albedo is EMBEDDED in its `.glb` — that is the copy Godot
renders. The loose `*_head_authored_*_head_albedo.png` beside each one is the same bake
written out again by `spike_z3e_head.py` as the readable source of it; nothing in the
game loads it. It is written AFTER the export, because giving the image a filepath
before it puts that name inside the `.glb` (bead godot-test1-z3e.12, which found Primm's
copy still showing the z3e.5 palette — the glTF exporter never wrote one at all).

THE SKIN GRADE. Every authored face's skin and lips are darkened by one factor —
`SKIN_GRADE` in `scripts/spike_z3e_head.py` and the same number in
`scripts/build_hero.py` — before they are painted or baked (bead
godot-test1-z3e.14). The palettes in those scripts are still the generators'
verbatim, so the two files record the paint and the constant records the exposure;
the two copies must move together.

All ten `teibi_*_authored.glb` files above and `teibi_uncut_authored.glb` share the ONE `teibi_authored.blend` next to them — the ten pieces are cuts of the same whole-body mesh, exported before being split.

## CI Model Gate

The CI model rebuild step (`.github/workflows/build.yml`) only runs the procedural generators (`generate_*_separate.py` and `predator_parts.py`). Because the generator no longer emits these authored file names, `git status --porcelain -- assets/models/characters` stays clean by construction; a generated part edited by hand is still caught immediately.
