# Translations

All user-visible strings are wrapped with `tr()` in GDScript and scene nodes use `auto_translate_mode` so they pass through Godot's translation system automatically. The source of truth for all strings is `translations/strings.csv`.

## Adding a new language

1. Open `translations/strings.csv` and add a new column with the locale code (e.g. `fr`, `de`, `ja`):

   ```csv
   keys,en,fr
   Settings,Settings,Paramètres
   Close,Close,Fermer
   ...
   ```

2. Open the project in the Godot editor. It will import the updated CSV automatically.

3. Go to **Project → Project Settings → Localization → Translations** and add the compiled `.translation` file generated in `.godot/imported/`.

4. To test, change the locale at runtime or via **Project Settings → Localization → Locale → Test**.

## Notes on format strings

Some strings contain `%d` or `%s` placeholders, e.g. `"Completed in %d %s"`. Keep the placeholders in your translation — only the surrounding text changes. The order of `%d`/`%s` arguments is fixed in the source, so if your language needs a different word order you will need a code change as well.

## Files involved

| File | What changed |
|------|-------------|
| `translations/strings.csv` | All translatable strings with English values |
| `project.godot` | Points the editor at the CSV as a POT source |
| `scripts/main.gd` | All UI strings wrapped with `tr()` |
| `scripts/menu.gd` | Settings dialog strings wrapped with `tr()` |
| `scripts/board_builder.gd` | Board Builder UI strings wrapped with `tr()` |
| `scripts/game_settings.gd` | Difficulty and palette label getters use `tr()` |
| `scenes/menu.tscn` | Root node has `auto_translate_mode = 1` (all children inherit) |
| `scenes/beaker.tscn` | Static button/label nodes have `auto_translate_mode = 1` |
| `scenes/hanoi.tscn` | Static button/label nodes have `auto_translate_mode = 1` |
