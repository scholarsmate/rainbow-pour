# Development Guide

## Project Snapshot

Rainbow Pour is a Godot 4.6 puzzle game. The primary game is a water-sort style pour puzzle with scoring, chill mode, special beakers, cheats, sounds, animations, translations, and Android export support. Rainbow Hanoi remains available as a bonus side mode.

## Primary Entry Points

- `project.godot` - Godot project configuration, autoloads, input, localization, and export metadata.
- `scenes/menu.tscn` / `scripts/menu.gd` - Main menu, mode selection, settings, palette controls, and navigation.
- `scenes/main.tscn` / `scripts/main.gd` - Rainbow Pour screen controller, HUD, scoring, solved/loss modals, cheat UI, and game-state orchestration.
- `scripts/towers.gd` - Rainbow Pour board state, puzzle generation/import, rules, rendering, input handling, special beakers, animations, and cheat execution.
- `scenes/hanoi.tscn` / `scripts/hanoi.gd` - Rainbow Hanoi side mode.
- `scripts/game_settings.gd` - Persistent settings, palettes, difficulty labels, accessibility options, chill mode, and special-beaker toggles.
- `translations/strings.csv` - Source of truth for user-visible strings and UI glyph display values.
- `docs/ANDROID.md` - Android build and phone-testing workflow.

## Current Feature Surface

- Core Rainbow Pour puzzle generation with configurable difficulty, beaker count, capacity, and optimal-pour goal tracking.
- Score-focused mode with move scoring, star awards, bonuses, and loss conditions.
- Chill mode without score pressure, with each cheat available once per game and redo available up to four times.
- Cheats including undo/redo, extra beaker, stir, swap, and pipette transfer.
- Pipette animations and sampled pipette sounds for transfer, stir, and swap actions.
- Special beakers including cracked, tinted, and prismatic behavior.
- Delayed cracked-beaker reveal with impact animation and distinct cracking audio.
- Beaker accessibility symbols, palette selection, localized UI text, and mobile-friendly settings controls.
- Android debug APK export and phone testing.
- Rainbow Hanoi side mode.

## Development Workflow

Run the project from the repo root:

```powershell
godot --path .
```

Refresh imports and catch parse/import errors without opening the editor:

```powershell
godot --headless --path . --editor --quit
```

Export the current Android debug APK:

```powershell
godot --headless --path . --export-debug Android build/rainbow-pour.apk
```

Check for whitespace problems before committing:

```powershell
git diff --check
```

## Refactor Notes

The highest-complexity files are `scripts/main.gd` and `scripts/towers.gd`. Prefer small, behavior-preserving extractions over large file splits unless a feature clearly needs a new ownership boundary.

Good future cleanup targets:

- Move solved/loss modal assembly out of `main.gd`.
- Move cheat button state and cheat history text formatting out of `main.gd`.
- Move pipette animation drawing/state helpers out of `towers.gd` once the interface settles.
- Move board generation and solvability scoring out of `towers.gd`.
- Add focused regression tests around cheat legality, chill-mode cheat limits, cracked-beaker reveal, and bonus scoring if a GDScript test harness is added.

## Documentation Checks

- Keep `README.md` focused on player-facing project overview and setup.
- Keep `docs/ANDROID.md` current with the local export path and Android SDK requirements.
- Keep `TRANSLATIONS.md` aligned with `translations/strings.csv` and new UI surfaces.
- After changing strings, run the Godot headless import command above and inspect generated translation import changes.
