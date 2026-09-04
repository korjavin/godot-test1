# Quick Start Guide 🚀

Get running in 5 minutes.

## Just play it

**https://korjavin.github.io/godot-test1/** — desktop or phone browser, nothing
to install.

## Run from source

1. Download **Godot 4.5** (standard build): https://godotengine.org/download
2. Launch Godot → **Import** → select this folder's `project.godot` → **Import & Edit**
3. Press **F5** (or the ▶ Play button)

## Controls

- **W/S** move · **A/D** turn · **Q/E** sidestep · **Mouse** look
- **Space** jump · **Shift** run · **Ctrl** duck
- **R** switch hero · **F** special ability
- **P** pause · **Esc** release/recapture mouse · **\fo** perf overlay

### 📱 On mobile (web build)

Open the GitHub Pages URL on your phone and tap the start overlay (this also
grants iOS motion permission). Then **step in place** to walk, **tilt** to steer
(tap the on-screen toggle for **twist** steering), and use the on-screen
**JUMP / SPECIAL / SWITCH** buttons. The **⚙ Tune** panel calibrates step
detection and steering live, and your settings persist between visits. The touch
controls appear automatically on touch devices only — desktop keyboard + mouse
is unchanged.

## Poke at the code

Everything is heavily commented — start with `scripts/player_controller.gd`
(movement, heroes, abilities) and `scripts/endless_terrain.gd` (the procedural
world and the coin road). Architecture notes live in [CLAUDE.md](CLAUDE.md).

Fun quick tweaks (constants at the top of each script):

```gdscript
# scripts/player_controller.gd
const WALK_SPEED: float = 5.0     # crank it
const RUN_SPEED: float = 10.0

# scripts/piglet_crocodile_ai.gd
const BASE_CHASE_SPEED: float = 5.5   # how scary are the crocs?
```

## Common issues

- **Mouse not working?** Click the game window; Esc toggles capture.
- **No motion controls on iPhone over LAN?** iOS only delivers motion sensor
  data on HTTPS — test motion on the GitHub Pages build (or a tunnel), not
  `http://<lan-ip>`.
- **Changes not taking effect?** Save the script and restart the scene.

---

**Welcome to the CrimeKickers universe! 🐊**
