#!/usr/bin/env python3
"""Generate a stream of solver-verified adventure board candidates.

This is intentionally separate from the adventure-pack emitter. Candidate banks
are curation material, not playable packs, so they live outside assets/adventures
and are written incrementally as JSONL.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import random
import sys
import time
from pathlib import Path
from typing import Any

import adventure_generator as ag


def utc_now() -> str:
    return dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def as_int(value: Any, fallback: int) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return fallback


def as_float(value: Any, fallback: float) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return fallback


def resolve_output_path(config: dict[str, Any], output_override: str | None) -> Path:
    if output_override:
        return Path(output_override)
    bank = dict(config.get("bank", {}))
    configured = str(bank.get("output", "")).strip()
    if configured:
        return Path(configured)
    bank_id = str(bank.get("id", "adventure_candidates")).strip() or "adventure_candidates"
    return Path("build") / "adventure_candidates" / f"{bank_id}.jsonl"


def resolve_summary_path(config: dict[str, Any], output_path: Path, summary_override: str | None) -> Path:
    if summary_override:
        return Path(summary_override)
    bank = dict(config.get("bank", {}))
    configured = str(bank.get("summary_output", "")).strip()
    if configured:
        return Path(configured)
    return output_path.with_suffix(".summary.json")


def load_existing(output_path: Path) -> tuple[set[str], dict[str, int], int]:
    used_codes: set[str] = set()
    counts_by_profile: dict[str, int] = {}
    total = 0
    if not output_path.exists():
        return used_codes, counts_by_profile, total
    with output_path.open("r", encoding="utf-8") as handle:
        for line in handle:
            clean = line.strip()
            if clean == "":
                continue
            try:
                record = json.loads(clean)
            except json.JSONDecodeError:
                continue
            board_code = str(record.get("board_code", "")).strip()
            if board_code:
                used_codes.add(board_code)
            profile_id = str(record.get("profile_id", "unknown"))
            counts_by_profile[profile_id] = counts_by_profile.get(profile_id, 0) + 1
            total += 1
    return used_codes, counts_by_profile, total


def build_profiles(config: dict[str, Any]) -> list[dict[str, Any]]:
    defaults = dict(config.get("defaults", {}))
    raw_profiles = config.get("profiles", [])
    if not isinstance(raw_profiles, list) or not raw_profiles:
        raise ag.GenerationError("Config must contain at least one [[profiles]] entry.")
    profiles: list[dict[str, Any]] = []
    for index, raw_profile in enumerate(raw_profiles):
        if not isinstance(raw_profile, dict):
            raise ag.GenerationError(f"Profile {index + 1}: expected a table.")
        profile = ag.deep_merge(defaults, dict(raw_profile))
        profile_id = str(profile.get("id", f"profile_{index + 1:02d}")).strip() or f"profile_{index + 1:02d}"
        profile["id"] = profile_id
        profile["index"] = index
        profile["target_count"] = as_int(profile.get("target_count", 0), 0)
        if profile["target_count"] <= 0:
            raise ag.GenerationError(f"Profile {profile_id}: target_count must be positive.")
        ag.validate_generation_shape(profile, f"Profile {profile_id}")
        profiles.append(profile)
    return profiles


def profile_incomplete(profile: dict[str, Any], counts_by_profile: dict[str, int]) -> bool:
    return counts_by_profile.get(str(profile["id"]), 0) < int(profile["target_count"])


def make_record(
    puzzle: dict[str, Any],
    bank_id: str,
    profile: dict[str, Any],
    run_seed: int,
    attempt_index: int,
) -> dict[str, Any]:
    profile_id = str(profile["id"])
    return {
        "schema_version": 1,
        "bank_id": bank_id,
        "profile_id": profile_id,
        "profile_title": str(profile.get("title", profile_id)),
        "generated_at": utc_now(),
        "run_seed": run_seed,
        "attempt_index": attempt_index,
        "id": puzzle["id"],
        "title": puzzle["title"],
        "introduces": puzzle.get("introduces", ""),
        "board_code": puzzle["board_code"],
        "capacity": puzzle["capacity"],
        "filled_beakers": puzzle["filled_beakers"],
        "empty_beakers": puzzle["empty_beakers"],
        "beaker_count": puzzle["beaker_count"],
        "optimal_pours": puzzle["optimal_pours"],
        "optimal_solution": puzzle["optimal_solution"],
        "optimal_solution_format": puzzle["optimal_solution_format"],
        "pour_limit": puzzle["pour_limit"],
        "traits": puzzle["traits"],
        "rules": puzzle["rules"],
        "difficulty": puzzle["difficulty"],
        "generator": puzzle["generator"],
        "tags": [
            f"capacity:{puzzle['capacity']}",
            f"filled:{puzzle['filled_beakers']}",
            f"empty:{puzzle['empty_beakers']}",
            f"depth:{puzzle['optimal_pours']}",
            f"profile:{profile_id}",
        ],
    }


def write_summary(
    summary_path: Path,
    bank_id: str,
    output_path: Path,
    started_at: str,
    counts_by_profile: dict[str, int],
    failures_by_profile: dict[str, int],
    profiles: list[dict[str, Any]],
    total_existing: int,
    total_new: int,
    attempts: int,
    done: bool,
) -> None:
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    profile_payload = []
    for profile in profiles:
        profile_id = str(profile["id"])
        profile_payload.append(
            {
                "id": profile_id,
                "title": str(profile.get("title", profile_id)),
                "count": counts_by_profile.get(profile_id, 0),
                "target_count": int(profile["target_count"]),
                "failures_this_run": failures_by_profile.get(profile_id, 0),
                "capacity": int(profile.get("capacity", 4)),
                "filled_beakers": int(profile.get("filled_beakers", 6)),
                "empty_beakers": int(profile.get("empty_beakers", 2)),
                "min_solution_depth": int(profile.get("min_solution_depth", 1)),
                "max_solution_depth": int(profile.get("max_solution_depth", 999)),
                "traits": {
                    "cracked_count": int(profile.get("cracked_count", 0)),
                    "hidden_cracked_count": int(profile.get("hidden_cracked_count", profile.get("cracked_count", 0))),
                    "visible_cracked_count": int(profile.get("visible_cracked_count", 0)),
                    "prismatic_count": int(profile.get("prismatic_count", 0)),
                    "tinted_count": int(profile.get("tinted_count", 0)),
                },
            }
        )
    payload = {
        "schema_version": 1,
        "bank_id": bank_id,
        "output": str(output_path),
        "started_at": started_at,
        "updated_at": utc_now(),
        "done": done,
        "total_existing_at_start": total_existing,
        "total_new_this_run": total_new,
        "total_records": sum(counts_by_profile.values()),
        "attempts_this_run": attempts,
        "profiles": profile_payload,
    }
    with summary_path.open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Generate Rainbow Pour adventure board candidates as JSONL.")
    parser.add_argument("config", help="Path to the candidate-bank TOML config.")
    parser.add_argument("-o", "--output", help="Output JSONL path. Overrides [bank].output.")
    parser.add_argument("--summary-output", help="Summary JSON path. Overrides [bank].summary_output.")
    parser.add_argument("--seed", help="Override [bank].seed.")
    parser.add_argument("--target-total", type=int, help="Override [bank].target_total.")
    parser.add_argument("--max-runtime-minutes", type=float, help="Override [bank].max_runtime_minutes.")
    parser.add_argument("--fresh", action="store_true", help="Delete existing output before generating.")
    parser.add_argument("-q", "--quiet", action="store_true", help="Suppress progress messages.")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_arg_parser().parse_args(argv)
    config_path = Path(args.config)
    try:
        config = ag.load_toml(config_path)
        bank = dict(config.get("bank", {}))
        bank_id = str(bank.get("id", config_path.stem)).strip() or config_path.stem
        output_path = resolve_output_path(config, args.output)
        summary_path = resolve_summary_path(config, output_path, args.summary_output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        if args.fresh and output_path.exists():
            output_path.unlink()

        profiles = build_profiles(config)
        target_total = args.target_total if args.target_total is not None else as_int(
            bank.get("target_total", sum(int(profile["target_count"]) for profile in profiles)),
            sum(int(profile["target_count"]) for profile in profiles),
        )
        max_runtime_minutes = (
            args.max_runtime_minutes
            if args.max_runtime_minutes is not None
            else as_float(bank.get("max_runtime_minutes", 0), 0.0)
        )
        status_interval = max(1, as_int(bank.get("status_interval", 10), 10))

        used_codes, counts_by_profile, total_existing = load_existing(output_path)
        total_records = sum(counts_by_profile.values())
        master_seed = ag.stable_seed(args.seed if args.seed is not None else bank.get("seed", 1))
        run_seed = ag.stable_seed(f"{master_seed}:{time.time_ns()}")
        started_at = utc_now()
        started_perf = time.perf_counter()
        attempts = 0
        total_new = 0
        failures_by_profile: dict[str, int] = {}
        profile_cursor = 0

        if not args.quiet:
            print(
                f"Writing candidate bank {bank_id} to {output_path} "
                f"(existing {total_existing}, target {target_total})",
                flush=True,
            )

        with output_path.open("a", encoding="utf-8", newline="\n") as handle:
            while total_records < target_total:
                if max_runtime_minutes > 0 and (time.perf_counter() - started_perf) >= max_runtime_minutes * 60.0:
                    break
                incomplete = [profile for profile in profiles if profile_incomplete(profile, counts_by_profile)]
                if not incomplete:
                    break

                profile = incomplete[profile_cursor % len(incomplete)]
                profile_cursor += 1
                profile_id = str(profile["id"])
                profile_count = counts_by_profile.get(profile_id, 0)
                attempts += 1
                attempt_seed = ag.stable_seed(f"{run_seed}:{profile_id}:{attempts}:{profile_count}")
                rng = random.Random(attempt_seed)
                block = dict(profile)
                block["_global_start_index"] = total_records
                block["puzzle_title_prefix"] = str(profile.get("puzzle_title_prefix", profile.get("title", profile_id)))

                try:
                    puzzle = ag.generate_puzzle(
                        rng,
                        bank_id,
                        block,
                        int(profile.get("index", 0)),
                        profile_count,
                        used_codes,
                    )
                except ag.GenerationError as exc:
                    failures_by_profile[profile_id] = failures_by_profile.get(profile_id, 0) + 1
                    if not args.quiet:
                        print(f"miss {profile_id}: {exc}", flush=True)
                    if attempts % status_interval == 0:
                        write_summary(
                            summary_path,
                            bank_id,
                            output_path,
                            started_at,
                            counts_by_profile,
                            failures_by_profile,
                            profiles,
                            total_existing,
                            total_new,
                            attempts,
                            False,
                        )
                    continue

                record = make_record(puzzle, bank_id, profile, run_seed, attempts)
                handle.write(json.dumps(record, separators=(",", ":"), sort_keys=False))
                handle.write("\n")
                handle.flush()
                counts_by_profile[profile_id] = profile_count + 1
                total_records += 1
                total_new += 1
                if not args.quiet:
                    print(
                        f"hit {total_records}/{target_total} {profile_id}: "
                        f"depth {record['optimal_pours']} searched {record['difficulty']['solver_searched']}",
                        flush=True,
                    )
                if total_new % status_interval == 0:
                    write_summary(
                        summary_path,
                        bank_id,
                        output_path,
                        started_at,
                        counts_by_profile,
                        failures_by_profile,
                        profiles,
                        total_existing,
                        total_new,
                        attempts,
                        False,
                    )

        done = total_records >= target_total or not any(profile_incomplete(profile, counts_by_profile) for profile in profiles)
        write_summary(
            summary_path,
            bank_id,
            output_path,
            started_at,
            counts_by_profile,
            failures_by_profile,
            profiles,
            total_existing,
            total_new,
            attempts,
            done,
        )
        if not args.quiet:
            print(f"Generated {total_new} new candidates; total records {total_records}.", flush=True)
        return 0
    except ag.GenerationError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
