# Zelda-like Educational Game 🎮

A 3rd person adventure game built with Godot 4.3 for learning game development concepts.

## 🎯 Project Overview

This is an educational project designed to teach Godot game development through a Zelda-like adventure game. The project features:

- **3rd Person Character Controller** - Walk, run, duck, and jump
- **Endless Terrain System** - Procedurally generated infinite field
- **Physics-Based Movement** - Realistic gravity and movement mechanics
- **Extensively Commented Code** - Learn as you read
- **Clean Architecture** - Well-organized project structure

## 📋 Table of Contents

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Running the Game](#running-the-game)
- [Project Structure](#project-structure)
- [Controls](#controls)
- [Learning Resources](#learning-resources)
- [Customization Guide](#customization-guide)
- [Building for Distribution](#building-for-distribution)
- [CI/CD](#cicd)
- [Troubleshooting](#troubleshooting)

## 🔧 Prerequisites

### Required Software

1. **Godot Engine 4.3 or later**
   - Download from: https://godotengine.org/download
   - Choose the "Standard" version (not .NET unless you want C# support)
   - Supports Windows, macOS, and Linux

2. **Git** (optional, for version control)
   - Download from: https://git-scm.com/

### System Requirements

- **OS**: Windows 7+, macOS 10.13+, or Linux
- **RAM**: 4 GB minimum, 8 GB recommended
- **GPU**: Any GPU with OpenGL 3.3 / Vulkan support
- **Storage**: 200 MB for Godot + 50 MB for project

## 📥 Installation

### Step 1: Install Godot

#### Windows
1. Download Godot from https://godotengine.org/download
2. Extract the ZIP file to a folder (e.g., `C:\Godot`)
3. Run `Godot_v4.3-stable_win64.exe`
4. (Optional) Create a desktop shortcut

#### macOS
1. Download the macOS version
2. Open the DMG file
3. Drag Godot to Applications folder
4. Right-click and select "Open" (first time only, due to security)

#### Linux
```bash
# Download and extract
wget https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip
unzip Godot_v4.3-stable_linux.x86_64.zip

# Make executable
chmod +x Godot_v4.3-stable_linux.x86_64

# Run
./Godot_v4.3-stable_linux.x86_64
```

### Step 2: Get the Project

#### Option A: Clone with Git
```bash
git clone <your-repository-url>
cd godot-test1
```

#### Option B: Download ZIP
1. Download the project ZIP from GitHub
2. Extract to your desired location
3. Navigate to the extracted folder

## 🚀 Running the Game

### Method 1: Using Godot Editor (Recommended for Learning)

1. **Open Godot Engine**
2. **Import the Project**:
   - Click "Import" on the project manager
   - Navigate to the project folder
   - Select `project.godot`
   - Click "Import & Edit"

3. **Run the Game**:
   - Press `F5` or click the "Play" button (▶️) in the top-right
   - First time: You may need to wait for shaders to compile

4. **Edit the Game**:
   - Explore the Scene tab to see the game structure
   - Double-click scripts to edit them
   - Press `F6` to run the current scene

### Method 2: Command Line (Quick Testing)

```bash
# Navigate to project directory
cd /path/to/godot-test1

# Run with Godot (replace path with your Godot executable)
godot --path . scenes/main.tscn
```

### Method 3: Export and Run (For Distribution)

See [Building for Distribution](#building-for-distribution) section.

## 📁 Project Structure

```
godot-test1/
├── project.godot           # Main project configuration
├── icon.svg                # Project icon
│
├── scenes/                 # Scene files (.tscn)
│   ├── main.tscn          # Main game scene (world + player)
│   └── player.tscn        # Player character scene
│
├── scripts/               # GDScript files
│   ├── player_controller.gd    # Character movement logic
│   └── endless_terrain.gd      # Terrain generation system
│
├── assets/                # Game assets
│   ├── models/           # 3D models (.glb, .obj)
│   ├── textures/         # Textures and images
│   └── materials/        # Material files (.tres)
│
├── docs/                  # Documentation
│   ├── TUTORIAL.md       # Customization tutorials
│   └── CODE_STRUCTURE.md # Code architecture guide
│
├── .github/              # CI/CD configuration
│   └── workflows/
│       └── build.yml     # Automated build pipeline
│
├── README.md             # This file!
└── LICENSE               # MIT License
```

## 🎮 Controls

| Action | Key | Description |
|--------|-----|-------------|
| **Move Forward** | W | Walk forward |
| **Move Backward** | S | Walk backward |
| **Move Left** | A | Strafe left |
| **Move Right** | D | Strafe right |
| **Jump** | Space | Jump (only on ground) |
| **Run** | Left Shift | Run (2x speed) |
| **Duck** | Left Ctrl | Crouch (0.5x speed, 0.5x height) |
| **Look Around** | Mouse | Rotate camera |
| **Release Mouse** | ESC | Show/hide cursor |

### Tips
- Hold **Shift** while moving to run faster
- You can only jump when on the ground
- Ducking makes you shorter (useful for... future obstacles!)
- Mouse controls the camera - character rotates with mouse left/right

## 📚 Learning Resources

### Godot Official Resources
- [Godot Documentation](https://docs.godotengine.org/en/stable/)
- [GDScript Basics](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html)
- [3D Tutorial](https://docs.godotengine.org/en/stable/tutorials/3d/introduction_to_3d.html)

### Project-Specific Guides
- **[TUTORIAL.md](docs/TUTORIAL.md)** - How to customize your hero
- **[CODE_STRUCTURE.md](docs/CODE_STRUCTURE.md)** - Understanding the architecture

### Recommended Learning Path
1. Read through `scripts/player_controller.gd` - It's heavily commented
2. Experiment with the constants (WALK_SPEED, JUMP_VELOCITY, etc.)
3. Follow the TUTORIAL.md to customize your character
4. Try modifying the terrain system in `scripts/endless_terrain.gd`

## 🎨 Customization Guide

### Quick Customization Examples

#### Change Movement Speed
Edit `scripts/player_controller.gd`:
```gdscript
const WALK_SPEED: float = 5.0   # Try 10.0 for faster movement!
const RUN_SPEED: float = 10.0   # Try 20.0 for super speed!
```

#### Change Jump Height
```gdscript
const JUMP_VELOCITY: float = 8.0  # Try 15.0 for higher jumps!
```

#### Change Gravity (Simulate Different Planets!)
```gdscript
# Moon gravity (weak)
var gravity: float = 1.6

# Jupiter gravity (strong)
var gravity: float = 24.8
```

#### Change Terrain Appearance
Edit `scripts/endless_terrain.gd`:
```gdscript
# In _ready() function, change the color:
terrain_material.albedo_color = Color(0.8, 0.6, 0.4)  # Sandy color!
```

For detailed customization, see **[TUTORIAL.md](docs/TUTORIAL.md)**.

## 📦 Building for Distribution

### Export Templates

First, download export templates:
1. Open Godot
2. Go to **Editor → Manage Export Templates**
3. Click **Download and Install**

### Windows Build

1. In Godot: **Project → Export**
2. Click **Add...** → **Windows Desktop**
3. Configure:
   - **Export Path**: `builds/windows/game.exe`
   - **Runnable**: ✅ Checked
4. Click **Export Project**

### Linux Build

1. **Project → Export** → **Add...** → **Linux/X11**
2. **Export Path**: `builds/linux/game.x86_64`
3. **Export Project**

### macOS Build

1. **Project → Export** → **Add...** → **macOS**
2. **Export Path**: `builds/macos/game.zip`
3. **Export Project**
4. Note: May require code signing for distribution

### Web Build (HTML5)

1. **Project → Export** → **Add...** → **Web**
2. **Export Path**: `builds/web/index.html`
3. **Export Project**
4. Host on GitHub Pages, itch.io, or your own server

## 🔄 CI/CD

This project includes GitHub Actions for automated builds.

### What Gets Built Automatically

When you push code to GitHub:
- ✅ Windows executable (`.exe`)
- ✅ Linux executable (`.x86_64`)
- ✅ Web build (`index.html`)

### Accessing Builds

1. Go to your GitHub repository
2. Click **Actions** tab
3. Click on the latest workflow run
4. Download artifacts from the bottom of the page

### Manual Build Trigger

```bash
# Commit and push your changes
git add .
git commit -m "Update game"
git push origin main
```

See `.github/workflows/build.yml` for configuration details.

## 🐛 Troubleshooting

### Issue: "Failed to load scene"
**Solution**: Ensure you opened `project.godot`, not individual files.

### Issue: Mouse not captured
**Solution**: Click inside the game window, or press ESC to toggle mouse mode.

### Issue: Character falls through ground
**Solution**:
1. Check that terrain chunks have StaticBody3D nodes
2. Verify collision layers in Project Settings

### Issue: Low FPS / Performance issues
**Solution**:
- Reduce `render_distance` in `scripts/endless_terrain.gd`
- Lower graphics settings in Project Settings → Rendering
- Disable shadows on DirectionalLight3D

### Issue: Export templates not found
**Solution**:
1. Editor → Manage Export Templates
2. Download and Install
3. Restart Godot

### Issue: Code changes not taking effect
**Solution**:
1. Save the script (Ctrl+S)
2. Reload the scene (Ctrl+R)
3. If still not working, close and reopen the project

## 🤝 Contributing

This is an educational project! Feel free to:
- Experiment with the code
- Add new features
- Improve documentation
- Share your modifications

## 📄 License

MIT License - See [LICENSE](LICENSE) file for details.

## 🎓 Educational Goals

By working with this project, you'll learn:

1. **Godot Fundamentals**
   - Scene tree structure
   - Node types and inheritance
   - GDScript syntax and patterns

2. **Game Development Concepts**
   - Character controllers
   - Camera systems
   - Physics and collision
   - Input handling

3. **Software Engineering**
   - Code organization
   - Documentation practices
   - Version control with Git
   - CI/CD pipelines

4. **3D Game Mechanics**
   - 3D transformations
   - Vector math
   - Procedural generation
   - Optimization techniques

## 🚀 Next Steps

Once you're comfortable with the basics, try:

1. **Add Enemies** - Create wandering NPCs
2. **Implement Combat** - Add a sword attack
3. **Create Collectibles** - Add items to pick up
4. **Add Sound Effects** - Make the game come alive
5. **Build a HUD** - Display health and stamina bars
6. **Create Multiple Levels** - Design different areas

## 📞 Support

- **Godot Community**: https://godotengine.org/community
- **Godot Discord**: https://discord.gg/godotengine
- **Godot Forums**: https://forum.godotengine.org/

## 🌟 Acknowledgments

- **Godot Engine** - For the amazing open-source game engine
- **Godot Community** - For excellent documentation and tutorials

---

**Happy Game Development! 🎮✨**

Remember: Every great game developer started as a beginner. Take your time, experiment, and most importantly - have fun!
