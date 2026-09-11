# Authored Character Models & Provenance

## Forbidden Sources

The following sources are **strictly forbidden** for any hero or character art in this repository:
- **Hunyuan3D**: Licence Territory excludes the EU, UK, and South Korea.
- **Mixamo**: Allowed to ship in a compiled game, but cannot be redistributed standalone as raw assets in a public repository.
- **Rodin / generative AI model output**: Unsettled copyright and IP ownership.

All shipping character assets must derive from CC0 or equivalently unencumbered sources (MPFB2 / MakeHuman core basemesh and targets, Poly Haven, AmbientCG).

## Source Files (.blend)

Source `.blend` files accompanying authored `.glb` models **are committed to git** directly beside the models. To keep repository size bounded, `.blend` files must be saved with compression enabled and must carry **no multiresolution modifiers or sculpt layers**. Godot never imports them: `project.godot` sets `filesystem/import/blender/enabled=false`, because the Blender importer needs a Blender binary the CI runner lacks and the headless import hangs on the scan.

## Authored Assets

| File | Tool + Version | Source | Licence | Date | .blend |
|---|---|---|---|---|---|
| `windman_head_authored.glb` | Blender 5.2.1 LTS, MPFB 2.0.17 | `scripts/spike_z3e_head.py`, MakeHuman basemesh + targets | CC0 | 2026-09-06 built, 2026-09-08 shipped | `windman_head_authored.blend` |
| `windman_head_authored_windman_head_albedo.png` | Blender 5.2.1 LTS, MPFB 2.0.17 | `scripts/spike_z3e_head.py`, MakeHuman basemesh + targets | CC0 | 2026-09-06 built, 2026-09-08 shipped | `windman_head_authored.blend` |
| `primm_parts/primm_head_authored.glb` | Blender 5.2.1 LTS, MPFB 2.0.17 | `scripts/spike_z3e_head.py --hero primm`, MakeHuman basemesh + targets | CC0 | 2026-09-11, bead godot-test1-z3e.5 | `primm_parts/primm_head_authored.blend` |
| `primm_parts/primm_head_authored_primm_head_albedo.png` | Blender 5.2.1 LTS, MPFB 2.0.17 | `scripts/spike_z3e_head.py --hero primm`, MakeHuman basemesh + targets | CC0 | 2026-09-11, bead godot-test1-z3e.5 | `primm_parts/primm_head_authored.blend` |
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

Each authored head's 512x512 albedo is EMBEDDED in its `.glb` — that is the copy Godot
renders. The loose `*_head_authored_*_head_albedo.png` beside each one is the sidecar
Blender's glTF exporter drops next to the file; it is kept as the readable source of the
bake, and nothing in the game loads it.

All ten `teibi_*_authored.glb` files above and `teibi_uncut_authored.glb` share the ONE `teibi_authored.blend` next to them — the ten pieces are cuts of the same whole-body mesh, exported before being split.

## CI Model Gate

The CI model rebuild step (`.github/workflows/build.yml`) only runs the procedural generators (`generate_*_separate.py` and `predator_parts.py`). Because the generator no longer emits these authored file names, `git status --porcelain -- assets/models/characters` stays clean by construction; a generated part edited by hand is still caught immediately.
