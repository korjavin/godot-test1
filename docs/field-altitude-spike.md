# Field altitude spike — the red-check list

Bead `godot-test1-ope.1`, epic `godot-test1-ope`. This file is the SPIKE's report.
The measurement below is Task 6 of `docs/plans/20260904-field-altitude-spike.md`;
the web numbers and the migration order are Task 7 and land in the sections after it.

**The flag ships `false`.** `FIELD_ALTITUDE` in `scripts/endless_terrain.gd` and
`alt_enabled` in `assets/shaders/ground.gdshader` are both inert in the committed
tree, and `altitude_selfcheck` asserts that in the merged branch.

## How the suite was run

Every `scripts/*_selfcheck.gd` in the glob (36 files), one process each, exactly as
CI judges them: a check is GREEN only when it exits 0 **and** printed `SELFCHECK OK`
**and** logged no `SCRIPT ERROR`. Godot exits 0 on a runtime error, so the exit code
alone is not a verdict.

Three runs: flag off, flag on (flipped locally, never committed), flag off again.

| run | green | red |
|---|---|---|
| `FIELD_ALTITUDE = false` | 36 / 36 | — |
| `FIELD_ALTITUDE = true` | 34 / 36 | `altitude_selfcheck`, `chunk_stream_selfcheck` |
| `FIELD_ALTITUDE = false` (after the flip back) | 36 / 36 | — |

The flag-off runs bracket the flip and agree, so the flip is clean and the flag-off
path is inert — which is the branch's merge condition.

## The red list

| check | verdict | first failure | consumer it guards | migration size |
|---|---|---|---|---|
| `altitude_selfcheck` | RED **by design** | `FIELD_ALTITUDE is true in the committed tree — the spike ships false (see the flag's docstring)` | the spike's own merge condition: the flag ships false, `alt_enabled` is pushed as 0.0, the ground shape is a `BoxShape3D` and the timed heightmap block is never entered | none — this check is written to be red exactly while the flag is on locally, and its remaining seven checks all passed with the flag on |
| `chunk_stream_selfcheck` | RED | `safety-ring chunk (-1, -1) is in active_chunks but has no ground collision box` (all 9 ring chunks) | **the ground floor is a chunk-spanning `BoxShape3D`** — `_has_ground_collision` at `scripts/chunk_stream_selfcheck.gd:312` measures the real shape, and a `HeightMapShape3D` is not one | **small** — the helper becomes "a `BoxShape3D` spanning the chunk, or a `HeightMapShape3D` of `GROUND_SUBDIVISIONS + 1` samples covering it"; one helper, both branches, no other assertion in that file moves |

## The finding that matters more than the red list

**Only the two checks that read the GROUND SHAPE ITSELF went red.** Every flat-world
consumer the plan expected to fail stayed green — coin settling (`prop_selfcheck`,
`enemy_spawn_selfcheck` check 14), road stations at y = 0 (`enemy_spawn_selfcheck`
check 11), crocodile gravity settle (`enemy_spawn_selfcheck`, `boss_selfcheck`),
block bases (`prop_selfcheck`, `landmark_selfcheck`), the spawn point,
`wade_selfcheck` and `minimap_selfcheck`.

That is not the mask saving them; it is the spike's scope. `height_at()` has
**exactly one production consumer** — the per-chunk `HeightMapShape3D` in
`_ensure_chunk_ground` — so every other system still computes its y the way it did
yesterday. Those checks assert today's y = 0 behaviour against code that still
produces y = 0, and the mismatch between a coin at y = 1.0 and a floor now 2 m below
it is **invisible to all of them**.

Two consequences for the migration, and both are load-bearing:

- **The red list is not a to-do list.** It names two files. The epic's consumer list
  is a dozen systems, and the suite does not currently protect eleven of them.
- **Every consumer migrated needs its check TAUGHT about height first**, or it will
  certify the migration silently. The order in Task 7 is written against the consumer
  list, never against this table.

`budapest_selfcheck`, `tower_site_selfcheck`, `tower_shell_selfcheck`,
`tower_interior_selfcheck`, `tower_lift_selfcheck`, `tower_selfcheck` and
`capture_selfcheck` staying green **is** a real result: those zones are forced flat by
`_alt_flat_mask` and a red one there would have been a mask bug. So is
`wade_selfcheck` — the river bands are clause 3 of the same mask.
