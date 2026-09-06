# CrimeKickers — review calibration

## What it is

A Godot **4.5** third-person endless-runner adventure ("CrimeKickers"): an infinite procedurally
generated field, four switchable heroes, hostile NPCs, one authored city (Budapest) and one authored
building (the GastroDefense HQ tower). 2–4 players share a world over WebRTC through a small Go lobby
(`server/`). One owner, developed almost entirely by coding agents, and **every merge to `master`
deploys to production** (web build + lobby image, Portainer). There is no staging.

Languages by weight: GDScript (nearly everything), GLSL (`assets/shaders/`), Go (`server/`, its own
`go test`), Python (`scripts/generate_*.py`, `scripts/predator_parts.py` — model generators with a
pinned toolchain), shell + GitHub Actions YAML (CI), and JavaScript that lives as **const strings inside
GDScript** (`voice_chat.gd`, `intro_video.gd`, `mobile_sensors.gd`). Judge each file by its own
language's bar; a shell or YAML commit is not held to GDScript conventions.

## Where the rules live

- `CLAUDE.md` — the map. It records where things live and the rules you would break without knowing.
  A deviation from a rule written there is always worth reporting. It is long; `rg` it for the file
  or the constant you are looking at rather than reading it end to end.
- **The scripts themselves.** The reasoning, the measured numbers and the tuning history live in the
  code as long comments, on purpose. Read the file you are reviewing, including its comment banner.
- Comments cite owner rulings and beads by id (`bead godot-test1-xxx`, `bd xtr.19`). Those are
  references, not junk: `bd show godot-test1-xxx` prints the ruling. Do not file them as stale text.
- `docs/CODE_STRUCTURE.md`, `docs/field-altitude-spike.md` for the two big open spikes.

## What a real failure looks like here

Ordered roughly by how badly they bite. A finding in one of these classes is `major` or above.

1. **Determinism broken.** Every spawn is a pure function of (chunk coords or station index) plus
   `run_seed`. One extra RNG draw from the shared chunk stream — a new `randf()`, a `continue` placed
   *before* the draws instead of after, a kind or dispatch that costs a draw — slides every spawn in the
   world and makes multiplayer peers build different worlds. New features take their **own** hash
   stream (own salt, own coordinate primes).
2. **CPU/GPU parity broken.** `_biome_noise` in `endless_terrain.gd` and `biome_noise` in
   `ground.gdshader` are one function in two languages; so are the city override, the Danube band,
   the dry rects and the HQ disc. An edit to one side without the other is a bug even if both compile.
   The GDScript port routes every step through `Vector2` to force fp32 — "simplifying" it to scalars
   changes the field.
3. **A self-check that stopped asserting.** There is no test framework: correctness is guarded by
   headless `scripts/*_selfcheck.gd` scripts. A GDScript runtime error aborts only the *function* it
   lands in and the script still prints `SELFCHECK OK`. Every check therefore stamps
   `Sentinel.done("name")` before every early exit and as its last statement, opens with
   `Sentinel.isolate_user_state()`, and reports through `Sentinel.finish(self)`. A new or edited check
   missing any of that, or a new assertion **without a negative / mutation control** (every check in
   this suite carries one), is a real finding.
4. **Softlock.** No traversal may demand a jump height; a river's deep channel is impassable and the
   road must be bridged or forded at every crossing; the tower's graph audit must still hold. Anything
   that can leave a player unable to progress is `critical`.
5. **Per-object nodes.** Decorative geometry goes through `create_box()` into the chunk's one
   MultiMesh and one collision body. A `MeshInstance3D`, `StaticBody3D` or material `duplicate()` per
   object is a web-build perf regression. Chunk-spawned things parent to the chunk or they leak.
6. **The speed lattice.** `WALK_SPEED` < species `chase_speed` <= `MAX_CHASE_SPEED` < slowest run.
   Walking gets you caught, running always escapes. Any retune touching that chain, the wade factor or
   a walk-speed effect breaks the game's central contract.
7. **Multiplayer trust and isolation.** Everything relayed is unvalidated peer input: type-check,
   bound, rate-limit. `_rtc` is never assigned to `multiplayer.multiplayer_peer`. A `RemoteAvatar`
   joins no group (never `"player"`) and carries no physics body. `bytes_to_var`, never
   `bytes_to_var_with_objects`.
8. **Web-build traps.** A bare JS boolean returned through `JavaScriptBridge.eval` is a corrupted
   Variant on Godot 4.5's web template — every bridge snippet returns a number. Audio must stay behind
   `unlock_audio()`. `light_angular_distance` and other Forward+-only knobs do nothing on the web
   renderer.
9. **The pause.** `PauseHub.take/release` is the only writer of `get_tree().paused`. A new
   `.paused =` anywhere else is a red build.
10. **Save migration by accident.** Persisted ids (opened gates, the dormant scar) and the monotone
    store's fields cannot be renamed or retired without a migration nobody ordered.
11. **A generator change without its regenerated `.glb` in the same commit**, or a `.gd.uid` edited
    by hand.

## Blast radius

Master is prod. A red `master` blocks every deploy behind it; a green one ships within minutes to the
lobby at `ck.wandergeek.org` and to real players' browsers, whose save profiles are monotone stores
that cannot be rolled back. The CI gate is the whole self-check suite plus a byte-compare of the
rebuilt models; a change that passes CI but breaks one of the classes above ships.

## Reporting bar

Material, not merely true. Noise here, do not file it:

- **Comment density and length.** This codebase is written to be read; the long banners, the quoted
  owner rulings and the "this was wrong once, here is why" paragraphs are the design record. "Too
  many comments" or "move this to docs" is never a finding. `ponytail:` comments mark deliberate
  simplifications with a named ceiling — that is intent, not ignorance.
- **The extraction idiom.** Static libraries (`class_name Foo`, all static, `terrain: Node3D` first
  argument, reaching back through the reference), one-line forwarders kept on the old home, and
  `const X := Lib.X` aliases back are all deliberate — they keep hundreds of call sites and
  `get_script_constant_map()` readers untouched. An **untyped** parameter or a lookup inside a function
  body instead of a `const` is usually the cycle rule (a type annotation is a parse-time reference).
  Dispatch by method-name string through a preloaded script object is deliberate: `Class.call(...)`
  is a parse error.
- **Group-based discovery with `has_method` guards** instead of typed references or `$`-paths, so a
  scene run standalone degrades instead of erroring.
- **Data over subclasses.** Species, skill trees, storeys, the tower graph, the city plan are const
  dicts of plain dicts. Do not ask for a class hierarchy or a custom `Resource`.
- **Measured "magic numbers".** A constant with a comment saying what was measured and when is a
  tuned value, not a magic number. Do not ask for it to be configurable.
- **Deliberate non-determinism.** Weather, fauna, crowds and traffic use `randomize()`d RNGs and must
  never touch `run_seed`. Per-instance speed and size rolls are random on purpose.
- **Entity counts.** Never propose reducing them as an optimisation; distant bodies are slept, never
  removed.
- **Flat-world invariant.** Ground at y = 0, mountains are impassable massifs, rivers are tinted
  bands. Do not suggest heightmaps, water meshes or physical gravity.
- Per-script arcade gravity, `PLAN_CELL` being 1.94 rather than 2.0, Budapest chunks casting no
  shadow, the wedge being the one convex hull — each is an owner ruling written beside the constant.
- Debug surfaces (`\fo`, F4–F7, self-check output) are deliberately not localised.
- Localisation: a plain English literal assigned to `.text` needs no `tr()`; only runtime-composed
  format strings do.

Things that *are* worth a finding at any severity: a documented rule in `CLAUDE.md` or a script banner
that the change contradicts; a new spawner that forgets scarcity `k`, `in_budapest()` policy or
`tower_excludes()`; a new `SPECIES` row without its behaviour probe; a new MP verb whose bounds are
typed twice instead of read from `MpCodec`; `CLAUDE.md`'s map not updated when a family of functions
moves file; a self-check the change should have extended and did not.

Do not run the self-checks, the export or the Python generators — the review is read-only and CI runs
them. Do read the self-check that covers the area and say whether the change is inside what it asserts.
