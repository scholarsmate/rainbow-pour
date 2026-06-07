#!/usr/bin/env python3
"""Build an Adventure Mode pack by curating candidate-bank JSONL records."""

from __future__ import annotations

import argparse
import datetime as dt
import glob
import json
import math
import random
import sys
from pathlib import Path
from typing import Any

import adventure_generator as ag


def utc_now() -> str:
    return dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat()


def load_candidates(patterns: list[str]) -> list[dict[str, Any]]:
    candidates: list[dict[str, Any]] = []
    seen_codes: set[str] = set()
    for pattern in patterns:
        for path in sorted(glob.glob(pattern)):
            with Path(path).open("r", encoding="utf-8") as handle:
                for line in handle:
                    clean = line.strip()
                    if clean == "":
                        continue
                    record = json.loads(clean)
                    board_code = str(record.get("board_code", "")).strip()
                    if board_code == "" or board_code in seen_codes:
                        continue
                    depth = int(record.get("optimal_pours", -1))
                    solution = str(record.get("optimal_solution", ""))
                    if depth <= 0 or len(solution) != depth * 2:
                        continue
                    seen_codes.add(board_code)
                    candidates.append(record)
    return candidates


def normalize_dialog(value: Any) -> list[dict[str, str]]:
    return ag.normalize_dialog(value, "")


def as_list(value: Any) -> list[Any]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def candidate_matches(candidate: dict[str, Any], block: dict[str, Any]) -> bool:
    profiles = [str(item) for item in as_list(block.get("source_profiles", []))]
    if profiles and str(candidate.get("profile_id", "")) not in profiles:
        return False
    depth = int(candidate.get("optimal_pours", -1))
    if depth < int(block.get("min_depth", block.get("min_solution_depth", 0))):
        return False
    if depth > int(block.get("max_depth", block.get("max_solution_depth", 999))):
        return False
    traits = candidate.get("traits", {}) if isinstance(candidate.get("traits", {}), dict) else {}
    for trait_key in ["cracked", "hidden_cracked", "visible_cracked", "prismatic", "tinted"]:
        min_key = f"min_{trait_key}"
        if min_key in block and int(traits.get(trait_key, 0)) < int(block[min_key]):
            return False
        max_key = f"max_{trait_key}"
        if max_key in block and int(traits.get(trait_key, 0)) > int(block[max_key]):
            return False
    return True


def select_for_block(
    candidates: list[dict[str, Any]],
    block: dict[str, Any],
    count: int,
    used_codes: set[str],
    rng: random.Random,
) -> list[dict[str, Any]]:
    pool = [
        candidate
        for candidate in candidates
        if str(candidate.get("board_code", "")) not in used_codes and candidate_matches(candidate, block)
    ]
    if len(pool) < count:
        raise ag.GenerationError(
            f"Block {block.get('id', block.get('title', 'unknown'))}: needs {count} candidates, found {len(pool)}."
        )

    min_depth = int(block.get("min_depth", min(int(candidate["optimal_pours"]) for candidate in pool)))
    max_depth = int(block.get("max_depth", max(int(candidate["optimal_pours"]) for candidate in pool)))
    jitter = {str(candidate["board_code"]): rng.random() for candidate in pool}
    selected: list[dict[str, Any]] = []
    for index in range(count):
        if count <= 1:
            target_depth = min_depth
        else:
            target_depth = round(min_depth + (max_depth - min_depth) * float(index) / float(count - 1))
        pool.sort(
            key=lambda candidate: (
                abs(int(candidate["optimal_pours"]) - target_depth),
                int(candidate.get("difficulty", {}).get("solver_searched", 0)),
                jitter[str(candidate["board_code"])],
            )
        )
        choice = pool.pop(0)
        selected.append(choice)
        used_codes.add(str(choice["board_code"]))
    selected.sort(
        key=lambda candidate: (
            int(candidate["optimal_pours"]),
            int(candidate.get("difficulty", {}).get("solver_searched", 0)),
            str(candidate["board_code"]),
        )
    )
    return selected


def merge_cheats(default_cheats: dict[str, Any], block: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    candidate_rules = candidate.get("rules", {}) if isinstance(candidate.get("rules", {}), dict) else {}
    candidate_cheats = candidate_rules.get("cheats", {}) if isinstance(candidate_rules.get("cheats", {}), dict) else {}
    block_cheats = block.get("cheats", {}) if isinstance(block.get("cheats", {}), dict) else {}
    return ag.deep_merge(ag.deep_merge(default_cheats, candidate_cheats), block_cheats)


def build_puzzle(
    candidate: dict[str, Any],
    adventure_id: str,
    block: dict[str, Any],
    block_index: int,
    puzzle_index: int,
    global_index: int,
    default_cheats: dict[str, Any],
    i18n: dict[str, dict[str, str]],
    locale: str,
    puzzle_count: int,
) -> dict[str, Any]:
    puzzle_number = puzzle_index + 1
    block_number = block_index + 1
    puzzle_id = f"{adventure_id}-b{block_number:02d}-p{puzzle_number:02d}"
    prefix = str(block.get("puzzle_title_prefix", block.get("title", "Puzzle"))).strip() or "Puzzle"
    title = f"{prefix} {puzzle_number}"
    intro = normalize_dialog(block.get("intro_dialog", [])) if puzzle_index == 0 else []
    outro = normalize_dialog(block.get("outro_dialog", [])) if puzzle_index == puzzle_count - 1 else []
    candidate_traits = candidate.get("traits", {}) if isinstance(candidate.get("traits", {}), dict) else {}
    cheats = merge_cheats(default_cheats, block, candidate)
    puzzle = {
        "id": puzzle_id,
        "index": puzzle_number,
        "global_index": global_index,
        "title": title,
        "introduces": str(block.get("introduces", "")),
        "dialog": {
            "intro": intro,
            "outro": outro,
        },
        "board_code": str(candidate["board_code"]),
        "capacity": int(candidate["capacity"]),
        "filled_beakers": int(candidate["filled_beakers"]),
        "empty_beakers": int(candidate["empty_beakers"]),
        "beaker_count": int(candidate["beaker_count"]),
        "optimal_pours": int(candidate["optimal_pours"]),
        "optimal_solution": str(candidate["optimal_solution"]),
        "optimal_solution_format": str(candidate.get("optimal_solution_format", "hex_source_dest_pairs")),
        "pour_limit": int(candidate.get("pour_limit", ag.pour_limit_for_goal(int(candidate["optimal_pours"])))),
        "star_score_thresholds": ag.STAR_SCORE_THRESHOLDS,
        "traits": {
            "cracked": int(candidate_traits.get("cracked", 0)),
            "hidden_cracked": int(candidate_traits.get("hidden_cracked", 0)),
            "visible_cracked": int(candidate_traits.get("visible_cracked", 0)),
            "prismatic": int(candidate_traits.get("prismatic", 0)),
            "tinted": int(candidate_traits.get("tinted", 0)),
        },
        "rules": {
            "scoring": {
                "mode": "scored",
                "stars_on_solve": 0,
            },
            "cheats": cheats,
            "special_beakers": {
                "visible_cracked_count": int(candidate_traits.get("visible_cracked", 0)),
                "hidden_cracked_count": int(candidate_traits.get("hidden_cracked", 0)),
                "prismatic_count": int(candidate_traits.get("prismatic", 0)),
                "tinted_count": int(candidate_traits.get("tinted", 0)),
            },
        },
        "difficulty": dict(candidate.get("difficulty", {})),
        "generator": {
            "source": "candidate_bank",
            "bank_id": str(candidate.get("bank_id", "")),
            "profile_id": str(candidate.get("profile_id", "")),
            "candidate_id": str(candidate.get("id", "")),
            "source_generated_at": str(candidate.get("generated_at", "")),
        },
    }
    ag.add_puzzle_i18n(puzzle, adventure_id, i18n, locale)
    return puzzle


def summarize_depths(blocks: list[dict[str, Any]]) -> dict[str, Any]:
    depths = [int(puzzle["optimal_pours"]) for block in blocks for puzzle in block["puzzles"]]
    return {
        "min": min(depths) if depths else 0,
        "max": max(depths) if depths else 0,
        "average": round(sum(depths) / float(len(depths)), 2) if depths else 0.0,
    }


def build_adventure(config: dict[str, Any], config_path: Path) -> dict[str, Any]:
    adventure_cfg = dict(config.get("adventure", {}))
    adventure_id = str(adventure_cfg.get("id", "curated_adventure")).strip() or "curated_adventure"
    default_locale = str(adventure_cfg.get("default_locale", "en")).strip() or "en"
    seed = ag.stable_seed(adventure_cfg.get("seed", 1))
    rng = random.Random(seed)
    i18n: dict[str, dict[str, str]] = {default_locale: {}}
    candidate_cfg = dict(config.get("candidates", {}))
    input_patterns = [str(item) for item in as_list(candidate_cfg.get("input_glob", []))]
    if not input_patterns:
        raise ag.GenerationError("Config must include [candidates].input_glob.")
    candidates = load_candidates(input_patterns)
    if not candidates:
        raise ag.GenerationError("No usable candidates found.")

    defaults = dict(config.get("defaults", {}))
    default_cheats = ag.deep_merge(ag.DEFAULT_CHEATS, dict(defaults.get("cheats", {})))
    blocks_cfg = config.get("blocks", [])
    if not isinstance(blocks_cfg, list) or not blocks_cfg:
        raise ag.GenerationError("Config must contain at least one [[blocks]] entry.")

    used_codes: set[str] = set()
    blocks: list[dict[str, Any]] = []
    global_index = 1
    for block_index, raw_block in enumerate(blocks_cfg):
        block = ag.deep_merge(defaults, dict(raw_block))
        puzzle_count = int(block.get("puzzle_count", defaults.get("puzzle_count", 10)))
        selected = select_for_block(candidates, block, puzzle_count, used_codes, rng)
        block_id = str(block.get("id", f"block_{block_index + 1:02d}"))
        cheats = ag.deep_merge(default_cheats, dict(block.get("cheats", {})) if isinstance(block.get("cheats", {}), dict) else {})
        puzzles = []
        for puzzle_index, candidate in enumerate(selected):
            puzzles.append(
                build_puzzle(
                    candidate,
                    adventure_id,
                    block,
                    block_index,
                    puzzle_index,
                    global_index,
                    default_cheats,
                    i18n,
                    default_locale,
                    puzzle_count,
                )
            )
            global_index += 1
        block_depths = [int(puzzle["optimal_pours"]) for puzzle in puzzles]
        block_payload = {
            "id": block_id,
            "index": block_index + 1,
            "title": str(block.get("title", block_id.replace("_", " ").title())),
            "introduces": str(block.get("introduces", "")),
            "unlock_next": {
                "requires_all_solved": bool(block.get("requires_all_solved", True)),
                "min_stars": int(block.get("min_stars_to_unlock_next", math.ceil(float(puzzle_count * 5) * 0.70))),
                "max_stars": puzzle_count * 5,
            },
            "rules": {
                "capacity": int(block.get("capacity", puzzles[0]["capacity"])),
                "filled_beakers": int(block.get("filled_beakers", puzzles[0]["filled_beakers"])),
                "empty_beakers": int(block.get("empty_beakers", puzzles[0]["empty_beakers"])),
                "min_solution_depth": min(block_depths),
                "max_solution_depth": max(block_depths),
                "cheats": cheats,
                "special_beakers": dict(block.get("special_beakers", {})) if isinstance(block.get("special_beakers", {}), dict) else {},
            },
            "puzzles": puzzles,
        }
        block_base_key = ag.i18n_key("adventure", adventure_id, "block", block_id)
        ag.add_i18n_field(block_payload, "title", ag.i18n_key(block_base_key, "title"), i18n, default_locale)
        ag.add_i18n_field(block_payload, "introduces", ag.i18n_key(block_base_key, "introduces"), i18n, default_locale)
        ag.place_i18n_keys(block_payload, ["title", "introduces"])
        blocks.append(block_payload)

    adventure_metadata = {
        "id": adventure_id,
        "title": str(adventure_cfg.get("title", adventure_id.replace("_", " ").title())),
        "description": str(adventure_cfg.get("description", "")),
        "version": int(adventure_cfg.get("version", 1)),
        "seed": seed,
        "default_locale": default_locale,
        "block_count": len(blocks),
        "puzzle_count": sum(len(block["puzzles"]) for block in blocks),
        "total_stars": sum(len(block["puzzles"]) * 5 for block in blocks),
    }
    ag.add_i18n_field(adventure_metadata, "title", ag.i18n_key("adventure", adventure_id, "title"), i18n, default_locale)
    ag.add_i18n_field(adventure_metadata, "description", ag.i18n_key("adventure", adventure_id, "description"), i18n, default_locale)
    ag.place_i18n_keys(adventure_metadata, ["title", "description"])
    return {
        "schema_version": 1,
        "generated_at": utc_now(),
        "generator": {
            "name": "rainbow-pour-adventure-curator",
            "version": 1,
            "config": str(config_path),
            "candidate_count": len(candidates),
        },
        "adventure": adventure_metadata,
        "i18n": i18n,
        "scoring": {
            "score_max": ag.SCORE_MAX,
            "star_score_thresholds": ag.STAR_SCORE_THRESHOLDS,
            "pour_limit_grace": "max(6, ceil(optimal_pours * 0.5))",
            "default_cheats": default_cheats,
        },
        "summary": {
            "optimal_pours": summarize_depths(blocks),
        },
        "blocks": blocks,
    }


def resolve_output_path(config: dict[str, Any], output_override: str | None, config_path: Path) -> Path:
    if output_override:
        return Path(output_override)
    configured = str(dict(config.get("adventure", {})).get("output", "")).strip()
    if configured:
        return Path(configured)
    return Path("assets") / "adventures" / f"{config_path.stem}.json"


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Curate a Rainbow Pour adventure pack from candidate JSONL records.")
    parser.add_argument("config", help="Path to curation TOML config.")
    parser.add_argument("-o", "--output", help="Output adventure JSON path.")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_arg_parser().parse_args(argv)
    config_path = Path(args.config)
    try:
        config = ag.load_toml(config_path)
        adventure = build_adventure(config, config_path)
        output_path = resolve_output_path(config, args.output, config_path)
        ag.write_json(output_path, adventure, 2)
        print(
            f"Curated {adventure['adventure']['puzzle_count']} puzzles across "
            f"{adventure['adventure']['block_count']} blocks -> {output_path}",
            flush=True,
        )
        depth = adventure["summary"]["optimal_pours"]
        print(f"Optimal pours: min {depth['min']}, max {depth['max']}, avg {depth['average']}", flush=True)
    except ag.GenerationError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
