# Development Guide

## Current Implementation

The project includes:

1. **Project Configuration** (`project.godot`)
   - Set up for Godot 4.6
   - 1280x720 resolution
   - 2D rendering mode

2. **Main Scene** (`scenes/main.tscn`)
   - Background
   - UI elements (title, move counter, instructions, reset button)
   - Towers node

3. **Game Logic** (`scripts/`)
   - `main.gd`: Main game controller, handles moves, win condition
   - `towers.gd`: Tower and disk logic, rendering, input handling

## Features Implemented

- ✅ 3 towers with configurable disk count (default: 5)
- ✅ Water Sort: beaker capacity slider (in-game, Water Sort screen only)
- ✅ Rainbow-colored disks
- ✅ Click-based disk movement
- ✅ Valid move checking (larger disks can't go on smaller ones)
- ✅ Move counter
- ✅ Win detection
- ✅ Reset functionality
- ✅ Visual feedback with colored disks

## Game Rules

1. Click a tower to select it (must have disks)
2. Click another tower to move the top disk
3. Larger disks cannot be placed on smaller disks
4. Goal: Move all disks from the leftmost tower to the rightmost tower

## Next Steps / Future Enhancements

- [ ] Add animations for disk movement
- [ ] Add sound effects
- [ ] Add particle effects on successful moves
- [ ] Add difficulty levels (different disk counts)
- [ ] Add timer/speed mode
- [ ] Add undo functionality
- [ ] Add optimal move hint system
- [ ] Add celebration screen on win
- [ ] Add music
- [ ] Add visual selection indicator for selected tower
- [ ] Add disk dragging support

## How to Run

1. Install Godot 4.x from https://godotengine.org/download
2. Open Godot
3. Click "Import"
4. Navigate to this directory and select `project.godot`
5. Click "Import & Edit"
6. Press F5 or click the Play button to run the game

## Customization

You can easily customize the game by editing constants in `scripts/towers.gd`:
- `TOWER_COUNT`: Number of towers (default: 3)
- `DISK_COUNT`: Number of disks (default: 5)
- Color array: Customize disk colors
