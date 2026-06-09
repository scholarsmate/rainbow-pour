# Adventure Generator

`tools/adventure_generator.py` builds offline Adventure Mode JSON packs from TOML.

Run the starter sprint:

```powershell
python tools\adventure_generator.py tools\adventure_starter_sprint.toml
```

Write a diagnostics-only report too:

```powershell
python tools\adventure_generator.py tools\adventure_starter_sprint.toml --report logs\starter_sprint.report.json
```

The default output for the starter config is:

```text
assets/adventures/starter_sprint.json
```

## TOML Shape

- `[adventure]` describes the pack id, title, version, seed, default locale, and output path.
- `[defaults]` supplies generation defaults shared by every block.
- `[defaults.cheats]` stores the cheat costs and availability that the future game-side Adventure Mode loader can apply.
- `[[blocks]]` creates a 10-puzzle progression block by default.
- `[[blocks.puzzles]]` adds per-puzzle overrides inside the current block.
- `dialog_speaker`, `intro_dialog`, and `outro_dialog` add optional start/end dialog for a board.

Per-puzzle overrides are intended for tutorial beats. In the starter sprint, puzzles 1-3 are chill/tutorial puzzles:

- Puzzle 1: basic sorting with 3-segment beakers.
- Puzzle 2: 4-segment beakers and a prismatic beaker.
- Puzzle 3: more beakers and a tinted beaker.

## Output Notes

Each puzzle includes:

- `board_code`: an `RP1` board code compatible with the current board-code codec.
- `title_key`, `introduces_key`, and dialog `*_key` fields that resolve through the pack-local `i18n` table.
- `dialog`: optional `intro` and `outro` line arrays for Adventure Mode presentation.
- `optimal_pours`: the solver-verified optimal solution depth.
- `optimal_solution`: the solver-verified move path encoded as source/destination
  hex digit pairs. A 12-pour solution is 24 characters, such as `439A12...`.
- `pour_limit`: the current game score limit formula, `optimal + max(6, ceil(optimal * 0.5))`.
- `star_score_thresholds`: the current score thresholds for 1-5 stars.
- `rules`: scoring mode, cheat costs, and special-beaker counts.
- `difficulty`: solver diagnostics and simple board metrics.

Adventure packs keep their English text in normal fields such as `title`, `description`,
`introduces`, and dialog `text` for readability and backwards compatibility. Generated
packs also include a top-level `i18n` dictionary:

```json
{
  "adventure": {
    "id": "starter_sprint",
    "default_locale": "en",
    "title": "Starter Sprint",
    "title_key": "adventure.starter_sprint.title"
  },
  "i18n": {
    "en": {
      "adventure.starter_sprint.title": "Starter Sprint"
    }
  }
}
```

To localize a pack, add another locale table such as `es` or `fr_CA` with matching keys.
The game tries the active locale, the language code, the pack default locale, and then
English before falling back to the raw field.

Current limitations:

- The board-code codec records cracked beaker type, but not whether a cracked beaker starts revealed. Adventure Mode currently imports from `board_code`, so visible/hidden cracked counts remain JSON metadata until board imports can apply visibility separately.
- Difficulty is gated mainly by optimal pour depth. The emitted diagnostics leave room to add stronger filters later, such as branching factor, dead-end pressure, and cheat usefulness.

## Candidate Banks

Hard adventure packs can also be curated from generated candidate banks:

```powershell
python tools\adventure_candidate_bank.py tools\adventure_hard_candidates.toml
python tools\adventure_curate_pack.py tools\adventure_rainbow_trail_curated.toml
```

Candidate banks write JSONL files outside `assets/adventures`, so the game does not load them as playable packs.
The curator samples unique board codes by profile and depth band, then emits a normal Adventure JSON pack.
