# Translations

All user-visible strings are wrapped with `tr()` in GDScript and scene nodes use `auto_translate_mode` so they pass through Godot's translation system automatically. The source of truth for all strings is `translations/strings.csv`. The imported runtime resource is `translations/strings.en.translation`, and `project.godot` registers it under `locale/translations`.

Some decorative UI glyphs also use ASCII translation keys. For example, code should use a key such as `Solved Result Title`, while the CSV value can contain the displayed emoji or symbol.

## Adding A New Language

1. Open `translations/strings.csv` and add a new column with the locale code, for example `fr`, `de`, or `ja`:

   ```csv
   keys,en,fr
   Settings,Settings,Parametres
   Close,Close,Fermer
   ```

2. Open the project in the Godot editor. It will import the updated CSV automatically.

3. Go to **Project -> Project Settings -> Localization -> Translations** and add the compiled `.translation` file generated beside the CSV, for example `translations/strings.en.translation`.

4. To test, change the locale at runtime or via **Project Settings -> Localization -> Locale -> Test**.

5. Refresh imports from the repo root when editing outside the Godot editor:

   ```powershell
   godot --headless --path . --editor --quit
   ```

## Format Strings

Some strings contain `%d` or `%s` placeholders, e.g. `"Completed in %d %s"`. Keep the placeholders in your translation; only the surrounding text changes. The order of `%d` and `%s` arguments is fixed in the source, so a language that needs a different word order may need a code change.

## Files Involved

| File | Purpose |
|------|---------|
| `translations/strings.csv` | All translatable strings and UI glyph display values |
| `translations/strings.en.translation` | Imported English runtime translation resource |
| `project.godot` | Registers the runtime translation and points the editor at the CSV as a POT source |
| `scripts/main.gd` | Rainbow Pour UI strings and result modal strings |
| `scripts/menu.gd` | Settings dialog strings |
| `scripts/board_builder.gd` | Board Builder UI strings |
| `scripts/game_settings.gd` | Difficulty, palette, and symbol label getters |
| `scenes/menu.tscn` | Static menu button text keys |
| `scenes/beaker.tscn` | Static button/label nodes |
| `scenes/hanoi.tscn` | Static button/label nodes |
