# Rainbow Pour

A colorful Godot 4.6 puzzle project with a Water Sort game mode and a classic Towers of Hanoi mode.

## About

Water Sort includes adjustable beaker capacity, difficulty settings, scoring, mulligan undo, sound effects, loss conditions, and optimal-pour goal tracking.

## Getting Started

1. Install Godot 4.x from https://godotengine.org/
2. Open the project in Godot
3. Run the main scene

## Android

See [docs/ANDROID.md](docs/ANDROID.md) for building an APK and installing it on an Android phone.

## How to Play

Water Sort:
- Click a beaker to select it, then click another beaker to pour.
- Pours are legal when the destination is empty or its top color matches.
- Sort each color into its own beaker to win.

Towers of Hanoi:
- Move disks from one tower to another.
- Only one disk can be moved at a time.
- A larger disk cannot be placed on top of a smaller disk.

## Project Structure

- `scenes/` - Game scenes
- `scripts/` - GDScript files
- `assets/` - Game assets (sprites, sounds, etc.)
