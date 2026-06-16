# Quick Start Guide 🚀

Get up and running in 5 minutes!

## Step 1: Install Godot

Download Godot 4.3 or later from: https://godotengine.org/download

## Step 2: Open the Project

1. Launch Godot
2. Click **Import**
3. Navigate to this folder
4. Select `project.godot`
5. Click **Import & Edit**

## Step 3: Run the Game

Press **F5** or click the Play button (▶️)

## Controls

- **WASD** - Move
- **Space** - Jump
- **Shift** - Run
- **Ctrl** - Duck
- **Mouse** - Look around
- **ESC** - Release/capture mouse

### 📱 On mobile (web build)

Open the GitHub Pages URL on your phone and tap **"enable motion controls"** (this also grants iOS motion permission). Then **step** to walk, **tilt** to steer (tap the on-screen toggle for **twist** steering), and use the on-screen **JUMP / R (switch) / F (special)** buttons. The touch controls appear automatically on touch devices only — desktop keyboard + mouse is unchanged.

## What's Next?

1. **Explore the code**: Open `scripts/player_controller.gd` - it's heavily commented!
2. **Read the tutorial**: See `docs/TUTORIAL.md` for customization guides
3. **Understand the architecture**: Check `docs/CODE_STRUCTURE.md`
4. **Experiment**: Try changing values like WALK_SPEED or JUMP_VELOCITY

## Quick Tweaks to Try

### Make the character faster:
Edit `scripts/player_controller.gd`:
```gdscript
const WALK_SPEED: float = 10.0  # Was 5.0
const RUN_SPEED: float = 20.0   # Was 10.0
```

### Jump higher:
```gdscript
const JUMP_VELOCITY: float = 15.0  # Was 8.0
```

### Change gravity (simulate moon!):
```gdscript
var gravity: float = 1.6  # Moon gravity!
```

### Change terrain color:
Edit `scripts/endless_terrain.gd` in the `_ready()` function:
```gdscript
terrain_material.albedo_color = Color(0.8, 0.6, 0.4)  # Sandy!
```

## Project Structure

```
godot-test1/
├── scenes/          # Game scenes
├── scripts/         # GDScript code
├── assets/          # 3D models, textures
├── docs/            # Documentation
└── README.md        # Full documentation
```

## Need Help?

- **Full Documentation**: See [README.md](README.md)
- **Tutorials**: See [docs/TUTORIAL.md](docs/TUTORIAL.md)
- **Code Explanation**: See [docs/CODE_STRUCTURE.md](docs/CODE_STRUCTURE.md)
- **Godot Docs**: https://docs.godotengine.org

## Common Issues

**Mouse not working?**
- Click in the game window
- Press ESC to toggle mouse capture

**Character falls through ground?**
- Wait a moment for terrain to generate
- Check that you're starting above Y=0

**Changes not taking effect?**
- Save the script (Ctrl+S)
- Restart the scene (F6)

---

**Happy Game Development! 🎮**
