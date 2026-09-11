# Hero character models

Heroes are **not** single rigged meshes. Each hero is a folder of separate GLB
parts (`<hero>_parts/`) assembled by a `.tscn` under `scenes/characters/`, whose
`Body/LeftArm` / `RightArm` / `LeftLeg` / `RightLeg` containers are rotated at run
time by the sine-wave procedural animation in `scripts/player_animation.gd`.
There is no `AnimationPlayer` and no `Skeleton3D` anywhere in the project — limbs
are found **by exact node name** (see CLAUDE.md, "Player and camera").

The predators in this directory are single `.glb` files instead; their contract is
`scripts/predator_parts.py`.

## Windman

- Parts: `windman_parts/` — 11 GLB files.
  - `windman_head_authored.glb` is **authored**, not generated: Blender + MPFB2,
    shipped 2026-09-08 (bead z3e.2). It has a `PROVENANCE.md` row and a
    `.blend` + albedo PNG beside it. **No generator writes it — never regenerate it.**
  - The other ten (`windman_torso.glb`, the four upper/lower arm parts, the four
    upper/lower leg parts, `windman_fan.glb`) come from
    `scripts/generate_windman_separate.py`.
- Scene: `scenes/characters/windman_updated.tscn` — this is the scene
  `player_controller.gd`'s `CHARACTERS` array loads.
- Pipeline notes, coordinate conventions and troubleshooting:
  `docs/WINDMAN_SEPARATE_MESHES.md`.

### Regenerating

```bash
python3 scripts/generate_windman_separate.py   # rewrites the ten generated parts
```

The pinned toolchain is `scripts/requirements.txt`. CI rebuilds every generated
model and **fails on a dirty tree**, so a generator change and its regenerated
`.glb` go in the same commit.

To inspect or screenshot an assembled hero in Blender:

```bash
blender --background --python-exit-code 1 --python scripts/blender_hero.py -- import windman [--screenshot out.png]
```

## Character design reference

`docs/characters/windman.md` (description + reference art).
