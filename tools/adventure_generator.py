#!/usr/bin/env python3
"""Offline adventure pack generator for Rainbow Pour.

The generator intentionally has no Godot dependency. It ports the current
board-code codec and optimal-pour solver so generated puzzles can be shipped as
plain JSON content with cached board codes.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import math
import random
import sys
import time
from collections import deque
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - Python < 3.11 fallback message.
    tomllib = None


BASE85_ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.-:+=^!/*?&<>()[]{}@%$#"
BOARD_CODE_PREFIX = "RP1"
COUNT_BITS = 4
GOAL_BITS = 16
MAX_TOTAL_BEAKERS = 16

TRAIT_NONE = ""
TRAIT_PRISMATIC = "prismatic"
TRAIT_TINTED = "tinted"
TRAIT_CRACKED = "cracked"

SCORE_MAX = 1000
STAR_SCORE_THRESHOLDS = {
    "1": 0,
    "2": 300,
    "3": 550,
    "4": 750,
    "5": 900,
}
DEFAULT_CHEATS = {
    "undo_max_uses": 4,
    "extra_beaker_max_uses": 1,
    "recovery_max_uses_each": 1,
    "stir_cost": 2.0,
    "swap_cost": 3.0,
    "pipette_cost": 4.0,
    "extra_beaker_penalty_ratio": 0.35,
    "extra_beaker_min_penalty": 4.0,
}


class GenerationError(RuntimeError):
    pass


class BitWriter:
    def __init__(self) -> None:
        self.bytes: list[int] = []
        self.current_byte = 0
        self.bits_filled = 0

    def write_bits(self, value: int, count: int) -> None:
        if count <= 0:
            return
        for bit_idx in range(count - 1, -1, -1):
            self.current_byte = (self.current_byte << 1) | ((value >> bit_idx) & 1)
            self.bits_filled += 1
            if self.bits_filled == 8:
                self.bytes.append(self.current_byte)
                self.current_byte = 0
                self.bits_filled = 0

    def finish(self) -> bytes:
        if self.bits_filled > 0:
            self.current_byte <<= 8 - self.bits_filled
            self.bytes.append(self.current_byte)
            self.current_byte = 0
            self.bits_filled = 0
        return bytes(self.bytes)


class BitReader:
    def __init__(self, source: bytes) -> None:
        self.bytes = source
        self.byte_idx = 0
        self.bit_idx = 0
        self.failed = False

    def read_bits(self, count: int) -> int:
        if count <= 0:
            return 0
        value = 0
        for _ in range(count):
            if self.byte_idx >= len(self.bytes):
                self.failed = True
                return 0
            bit = (self.bytes[self.byte_idx] >> (7 - self.bit_idx)) & 1
            value = (value << 1) | bit
            self.bit_idx += 1
            if self.bit_idx == 8:
                self.bit_idx = 0
                self.byte_idx += 1
        return value


def bits_needed(max_value: int) -> int:
    bits = 0
    value = max(0, max_value)
    while (1 << bits) <= value:
        bits += 1
    return bits


def encode_base85(source: bytes) -> str:
    encoded: list[str] = []
    idx = 0
    while idx < len(source):
        group_len = min(4, len(source) - idx)
        value = 0
        for byte_offset in range(4):
            value <<= 8
            if byte_offset < group_len:
                value |= source[idx + byte_offset]
        chars = [""] * 5
        for char_idx in range(4, -1, -1):
            chars[char_idx] = BASE85_ALPHABET[value % 85]
            value //= 85
        encoded.extend(chars[: group_len + 1])
        idx += group_len
    return "".join(encoded)


def decode_base85(text: str) -> bytes:
    output = bytearray()
    idx = 0
    while idx < len(text):
        group_len = min(5, len(text) - idx)
        if group_len <= 1:
            return b""
        value = 0
        for char_offset in range(group_len):
            digit = BASE85_ALPHABET.find(text[idx + char_offset])
            if digit < 0:
                return b""
            value = value * 85 + digit
        for _ in range(group_len, 5):
            value = value * 85 + 84
        group = bytearray(4)
        for byte_idx in range(3, -1, -1):
            group[byte_idx] = value & 0xFF
            value >>= 8
        output.extend(group[: group_len - 1])
        idx += group_len
    return bytes(output)


def luhn_check_value(text: str) -> int:
    factor = 2
    total = 0
    base = len(BASE85_ALPHABET)
    for idx in range(len(text) - 1, -1, -1):
        code_point = BASE85_ALPHABET.find(text[idx])
        if code_point < 0:
            return -1
        addend = factor * code_point
        factor = 1 if factor == 2 else 2
        addend = (addend // base) + (addend % base)
        total += addend
    return (base - (total % base)) % base


def blank_trait() -> dict[str, Any]:
    return {"type": TRAIT_NONE, "color": -1, "revealed": False}


def normalize_trait(value: Any, filled_count: int) -> dict[str, Any]:
    if not isinstance(value, dict):
        return blank_trait()
    trait_type = str(value.get("type", TRAIT_NONE))
    if trait_type == TRAIT_PRISMATIC:
        return {"type": TRAIT_PRISMATIC, "color": -1, "revealed": False}
    if trait_type == TRAIT_TINTED:
        color = int(value.get("color", -1))
        if 0 <= color < filled_count:
            return {"type": TRAIT_TINTED, "color": color, "revealed": False}
    if trait_type == TRAIT_CRACKED:
        return {"type": TRAIT_CRACKED, "color": -1, "revealed": bool(value.get("revealed", False))}
    return blank_trait()


def encode_board_code(
    capacity: int,
    filled_count: int,
    empty_count: int,
    beakers: list[list[int]],
    traits: list[dict[str, Any]],
    cached_goal: int = -1,
) -> str:
    beaker_count = filled_count + empty_count
    if capacity <= 0 or capacity > 8:
        return ""
    if filled_count <= 0 or filled_count > 15 or empty_count <= 0 or empty_count > 15:
        return ""
    if beaker_count <= 0 or beaker_count > MAX_TOTAL_BEAKERS:
        return ""

    writer = BitWriter()
    color_bits = bits_needed(filled_count - 1)
    length_bits = bits_needed(capacity)
    has_goal = 0 <= cached_goal < (1 << GOAL_BITS)

    writer.write_bits(capacity - 1, 3)
    writer.write_bits(filled_count, COUNT_BITS)
    writer.write_bits(empty_count, COUNT_BITS)
    writer.write_bits(1 if has_goal else 0, 1)
    if has_goal:
        writer.write_bits(cached_goal, GOAL_BITS)

    for beaker_idx in range(beaker_count):
        tube = beakers[beaker_idx] if beaker_idx < len(beakers) else []
        writer.write_bits(len(tube), length_bits)
        for color in tube:
            writer.write_bits(int(color), color_bits)

    for beaker_idx in range(beaker_count):
        trait_data = normalize_trait(traits[beaker_idx] if beaker_idx < len(traits) else {}, filled_count)
        trait_type = str(trait_data.get("type", TRAIT_NONE))
        if trait_type == TRAIT_PRISMATIC:
            writer.write_bits(1, 2)
        elif trait_type == TRAIT_TINTED:
            writer.write_bits(2, 2)
            writer.write_bits(int(trait_data.get("color", 0)), color_bits)
        elif trait_type == TRAIT_CRACKED:
            writer.write_bits(3, 2)
        else:
            writer.write_bits(0, 2)

    payload = encode_base85(writer.finish())
    check_char = BASE85_ALPHABET[luhn_check_value(payload)]
    return f"{BOARD_CODE_PREFIX}{payload}{check_char}"


def decode_board_code(raw_code: str) -> dict[str, Any]:
    code = raw_code.strip()
    if not code.startswith(BOARD_CODE_PREFIX):
        return {"ok": False}
    if len(code) <= len(BOARD_CODE_PREFIX) + 1:
        return {"ok": False}

    payload_with_check = code[len(BOARD_CODE_PREFIX) :]
    payload = payload_with_check[:-1]
    check_char = payload_with_check[-1]
    if BASE85_ALPHABET.find(check_char) != luhn_check_value(payload):
        return {"ok": False}

    source = decode_base85(payload)
    if not source:
        return {"ok": False}
    reader = BitReader(source)

    capacity = reader.read_bits(3) + 1
    filled_count = reader.read_bits(COUNT_BITS)
    empty_count = reader.read_bits(COUNT_BITS)
    has_goal = reader.read_bits(1) == 1
    cached_goal = -1
    if has_goal:
        cached_goal = reader.read_bits(GOAL_BITS)

    beaker_count = filled_count + empty_count
    if reader.failed or capacity <= 0 or filled_count <= 0 or empty_count <= 0:
        return {"ok": False}
    if filled_count > 15 or empty_count > 15 or beaker_count > MAX_TOTAL_BEAKERS:
        return {"ok": False}

    color_bits = bits_needed(filled_count - 1)
    length_bits = bits_needed(capacity)
    beakers: list[list[int]] = []
    for _ in range(beaker_count):
        tube_len = reader.read_bits(length_bits)
        if reader.failed or tube_len > capacity:
            return {"ok": False}
        tube: list[int] = []
        for _ in range(tube_len):
            color_idx = reader.read_bits(color_bits)
            if reader.failed or color_idx < 0 or color_idx >= filled_count:
                return {"ok": False}
            tube.append(color_idx)
        beakers.append(tube)

    traits: list[dict[str, Any]] = []
    for _ in range(beaker_count):
        trait_type = reader.read_bits(2)
        if reader.failed:
            return {"ok": False}
        if trait_type == 1:
            traits.append({"type": TRAIT_PRISMATIC, "color": -1, "revealed": False})
        elif trait_type == 2:
            color_idx = reader.read_bits(color_bits)
            if reader.failed or color_idx < 0 or color_idx >= filled_count:
                return {"ok": False}
            traits.append({"type": TRAIT_TINTED, "color": color_idx, "revealed": False})
        elif trait_type == 3:
            traits.append({"type": TRAIT_CRACKED, "color": -1, "revealed": False})
        else:
            traits.append(blank_trait())

    return {
        "ok": True,
        "version": 1,
        "capacity": capacity,
        "filled_count": filled_count,
        "empty_count": empty_count,
        "beakers": beakers,
        "traits": traits,
        "cached_goal": cached_goal,
    }


def as_state(beakers: list[list[int]]) -> tuple[tuple[int, ...], ...]:
    return tuple(tuple(int(color) for color in tube) for tube in beakers)


def tube_uniform(tube: tuple[int, ...] | list[int]) -> bool:
    if not tube:
        return True
    first = tube[0]
    return all(color == first for color in tube)


def tube_complete(tube: tuple[int, ...] | list[int], capacity: int) -> bool:
    return len(tube) == capacity and tube_uniform(tube)


def is_cracked(traits: list[dict[str, Any]], idx: int) -> bool:
    return 0 <= idx < len(traits) and str(traits[idx].get("type", TRAIT_NONE)) == TRAIT_CRACKED


def state_tube_complete_at(
    traits: list[dict[str, Any]], idx: int, tube: tuple[int, ...], capacity: int
) -> bool:
    if is_cracked(traits, idx):
        return False
    return tube_complete(tube, capacity)


def state_has_shattered_cracked(
    state: tuple[tuple[int, ...], ...], traits: list[dict[str, Any]], capacity: int
) -> bool:
    for idx, tube in enumerate(state):
        if is_cracked(traits, idx) and tube_complete(tube, capacity):
            return True
    return False


def state_complete(
    state: tuple[tuple[int, ...], ...], traits: list[dict[str, Any]], capacity: int
) -> bool:
    for idx, tube in enumerate(state):
        if is_cracked(traits, idx):
            if tube:
                return False
            continue
        if not tube:
            continue
        if not tube_complete(tube, capacity):
            return False
    return True


def trait_group(traits: list[dict[str, Any]], idx: int) -> str:
    return "C" if is_cracked(traits, idx) else "R"


def encode_state_key(
    state: tuple[tuple[int, ...], ...], traits: list[dict[str, Any]]
) -> tuple[tuple[tuple[int, ...], ...], tuple[tuple[int, ...], ...]]:
    cracked_tubes: list[tuple[int, ...]] = []
    regular_tubes: list[tuple[int, ...]] = []
    for idx, tube in enumerate(state):
        if is_cracked(traits, idx):
            cracked_tubes.append(tube)
        else:
            regular_tubes.append(tube)
    return (tuple(sorted(cracked_tubes)), tuple(sorted(regular_tubes)))


def can_pour_state(
    state: tuple[tuple[int, ...], ...], src: int, dst: int, capacity: int
) -> bool:
    if src == dst:
        return False
    from_tube = state[src]
    to_tube = state[dst]
    if not from_tube:
        return False
    if len(to_tube) >= capacity:
        return False
    if not to_tube:
        return True
    return from_tube[-1] == to_tube[-1]


def state_after_pour(
    state: tuple[tuple[int, ...], ...], src: int, dst: int, capacity: int
) -> tuple[tuple[int, ...], ...]:
    next_state = [list(tube) for tube in state]
    from_tube = next_state[src]
    to_tube = next_state[dst]
    top = from_tube[-1]
    while from_tube and from_tube[-1] == top and len(to_tube) < capacity:
        to_tube.append(from_tube.pop())
    return as_state(next_state)


def count_available_moves(
    state: tuple[tuple[int, ...], ...], traits: list[dict[str, Any]], capacity: int
) -> int:
    count = 0
    for src, from_tube in enumerate(state):
        if not from_tube or state_tube_complete_at(traits, src, from_tube, capacity):
            continue
        for dst in range(len(state)):
            if can_pour_state(state, src, dst, capacity):
                count += 1
    return count


@dataclass
class SolverResult:
    solved: bool
    depth: int = -1
    solution: tuple[tuple[int, int], ...] = field(default_factory=tuple)
    reason: str = ""
    searched: int = 0
    visited: int = 0
    frontier_peak: int = 0
    elapsed_ms: int = 0


def encode_solution_moves(moves: tuple[tuple[int, int], ...]) -> str:
    encoded: list[str] = []
    for src, dst in moves:
        if src < 0 or dst < 0 or src >= MAX_TOTAL_BEAKERS or dst >= MAX_TOTAL_BEAKERS:
            raise GenerationError("Optimal solution contains a beaker index outside 0..15.")
        encoded.append(f"{src:X}{dst:X}")
    return "".join(encoded)


def solve_optimal(
    start: tuple[tuple[int, ...], ...],
    traits: list[dict[str, Any]],
    capacity: int,
    node_limit: int,
    frontier_limit: int,
    timeout_ms: int = 0,
) -> SolverResult:
    started_at = time.perf_counter()
    if state_has_shattered_cracked(start, traits, capacity):
        return SolverResult(False, reason="cracked beaker would shatter")
    if state_complete(start, traits, capacity):
        return SolverResult(True, depth=0, solution=())

    queue: deque[
        tuple[tuple[tuple[int, ...], ...], int, tuple[tuple[int, int], ...]]
    ] = deque([(start, 0, ())])
    visited = {encode_state_key(start, traits)}
    searched = 0
    frontier_peak = 1

    while queue:
        if timeout_ms > 0 and elapsed_since_ms(started_at) >= timeout_ms:
            return SolverResult(
                False,
                reason="solver timeout",
                searched=searched,
                visited=len(visited),
                frontier_peak=frontier_peak,
                elapsed_ms=elapsed_since_ms(started_at),
            )
        if searched >= node_limit or len(visited) >= node_limit:
            return SolverResult(
                False,
                reason="state limit",
                searched=searched,
                visited=len(visited),
                frontier_peak=frontier_peak,
                elapsed_ms=elapsed_since_ms(started_at),
            )
        if len(queue) >= frontier_limit:
            return SolverResult(
                False,
                reason="frontier limit",
                searched=searched,
                visited=len(visited),
                frontier_peak=frontier_peak,
                elapsed_ms=elapsed_since_ms(started_at),
            )

        state, depth, path = queue.popleft()
        searched += 1

        seen_sources: set[tuple[str, tuple[int, ...]]] = set()
        for src, from_tube in enumerate(state):
            if not from_tube or state_tube_complete_at(traits, src, from_tube, capacity):
                continue
            source_key = (trait_group(traits, src), from_tube)
            if source_key in seen_sources:
                continue
            seen_sources.add(source_key)

            seen_destinations: set[tuple[str, tuple[int, ...]]] = set()
            used_empty_destinations: set[str] = set()
            for dst, to_tube in enumerate(state):
                if src == dst:
                    continue
                if not to_tube:
                    destination_group = trait_group(traits, dst)
                    if destination_group in used_empty_destinations:
                        continue
                    if tube_uniform(from_tube) and trait_group(traits, src) == destination_group:
                        continue
                    used_empty_destinations.add(destination_group)
                else:
                    destination_key = (trait_group(traits, dst), to_tube)
                    if destination_key in seen_destinations:
                        continue
                    seen_destinations.add(destination_key)

                if not can_pour_state(state, src, dst, capacity):
                    continue
                next_state = state_after_pour(state, src, dst, capacity)
                if state_has_shattered_cracked(next_state, traits, capacity):
                    continue
                key = encode_state_key(next_state, traits)
                if key in visited:
                    continue
                next_path = path + ((src, dst),)
                if state_complete(next_state, traits, capacity):
                    return SolverResult(
                        True,
                        depth=depth + 1,
                        solution=next_path,
                        searched=searched,
                        visited=len(visited) + 1,
                        frontier_peak=max(frontier_peak, len(queue) + 1),
                        elapsed_ms=elapsed_since_ms(started_at),
                    )
                visited.add(key)
                queue.append((next_state, depth + 1, next_path))
                frontier_peak = max(frontier_peak, len(queue))

    return SolverResult(
        False,
        reason="search exhausted",
        searched=searched,
        visited=len(visited),
        frontier_peak=frontier_peak,
        elapsed_ms=elapsed_since_ms(started_at),
    )


def elapsed_since_ms(started_at: float) -> int:
    return int(round((time.perf_counter() - started_at) * 1000.0))


def repair_completed_generated_beakers(
    beakers: list[list[int]], filled_beakers: int, capacity: int
) -> None:
    if filled_beakers <= 1:
        return
    for idx in range(filled_beakers):
        if idx >= len(beakers) or not tube_complete(beakers[idx], capacity):
            continue
        mix_completed_beaker_with_next(beakers, idx, filled_beakers)


def mix_completed_beaker_with_next(
    beakers: list[list[int]], idx: int, filled_beakers: int
) -> None:
    source = beakers[idx]
    if not source:
        return
    for offset in range(1, filled_beakers):
        dst_idx = (idx + offset) % filled_beakers
        if dst_idx >= len(beakers):
            continue
        dest = beakers[dst_idx]
        if not dest:
            continue
        for src_segment, src_color in enumerate(source):
            for dst_segment, dst_color in enumerate(dest):
                if src_color == dst_color:
                    continue
                source[src_segment], dest[dst_segment] = dest[dst_segment], source[src_segment]
                return


def random_fill_board(
    rng: random.Random, capacity: int, filled_beakers: int, empty_beakers: int
) -> list[list[int]]:
    pool = [color for color in range(filled_beakers) for _ in range(capacity)]
    rng.shuffle(pool)
    beakers: list[list[int]] = []
    for idx in range(filled_beakers):
        start = idx * capacity
        beakers.append(pool[start : start + capacity])
    for _ in range(empty_beakers):
        beakers.append([])
    repair_completed_generated_beakers(beakers, filled_beakers, capacity)
    return beakers


def assign_traits(
    rng: random.Random,
    beakers: list[list[int]],
    block: dict[str, Any],
    capacity: int,
    filled_beakers: int,
) -> list[dict[str, Any]] | None:
    total_count = len(beakers)
    traits = [blank_trait() for _ in range(total_count)]

    cracked_total = int(block.get("cracked_count", 0))
    if "hidden_cracked_count" in block:
        hidden_cracked = int(block.get("hidden_cracked_count", 0))
    elif "visible_cracked_count" in block:
        hidden_cracked = max(0, cracked_total - int(block.get("visible_cracked_count", 0)))
    else:
        hidden_cracked = cracked_total
    visible_cracked = int(block.get("visible_cracked_count", max(0, cracked_total - hidden_cracked)))
    cracked_total = max(cracked_total, hidden_cracked + visible_cracked)
    hidden_cracked = min(hidden_cracked, cracked_total)
    visible_cracked = min(visible_cracked, cracked_total - hidden_cracked)

    cracked_candidates = [
        idx
        for idx in range(filled_beakers)
        if idx < len(beakers) and beakers[idx] and not tube_complete(beakers[idx], capacity)
    ]
    rng.shuffle(cracked_candidates)
    if len(cracked_candidates) < cracked_total:
        return None

    assigned: set[int] = set()
    for cracked_idx, beaker_idx in enumerate(cracked_candidates[:cracked_total]):
        revealed = cracked_idx >= hidden_cracked and visible_cracked > 0
        traits[beaker_idx] = {"type": TRAIT_CRACKED, "color": -1, "revealed": revealed}
        assigned.add(beaker_idx)

    remaining = [idx for idx in range(total_count) if idx not in assigned]
    rng.shuffle(remaining)

    prismatic_count = max(0, int(block.get("prismatic_count", 0)))
    tinted_count = max(0, int(block.get("tinted_count", 0)))
    if prismatic_count + tinted_count > len(remaining):
        return None

    for _ in range(prismatic_count):
        idx = remaining.pop()
        traits[idx] = {"type": TRAIT_PRISMATIC, "color": -1, "revealed": False}

    for _ in range(tinted_count):
        idx = remaining.pop()
        traits[idx] = {
            "type": TRAIT_TINTED,
            "color": rng.randrange(max(1, filled_beakers)),
            "revealed": False,
        }

    return traits


def trait_summary(traits: list[dict[str, Any]]) -> dict[str, int]:
    summary = {
        "cracked": 0,
        "hidden_cracked": 0,
        "visible_cracked": 0,
        "prismatic": 0,
        "tinted": 0,
    }
    for trait in traits:
        trait_type = str(trait.get("type", TRAIT_NONE))
        if trait_type == TRAIT_CRACKED:
            summary["cracked"] += 1
            if bool(trait.get("revealed", False)):
                summary["visible_cracked"] += 1
            else:
                summary["hidden_cracked"] += 1
        elif trait_type == TRAIT_PRISMATIC:
            summary["prismatic"] += 1
        elif trait_type == TRAIT_TINTED:
            summary["tinted"] += 1
    return summary


def board_metrics(
    state: tuple[tuple[int, ...], ...], traits: list[dict[str, Any]], capacity: int
) -> dict[str, int]:
    mixed = 0
    uniform_partial = 0
    full_uniform = 0
    empty = 0
    for tube in state:
        if not tube:
            empty += 1
        elif tube_complete(tube, capacity):
            full_uniform += 1
        elif tube_uniform(tube):
            uniform_partial += 1
        else:
            mixed += 1
    return {
        "available_moves": count_available_moves(state, traits, capacity),
        "mixed_beakers": mixed,
        "uniform_partial_beakers": uniform_partial,
        "full_uniform_beakers": full_uniform,
        "empty_beakers": empty,
    }


def pour_limit_for_goal(optimal_pours: int) -> int:
    grace = max(6, int(math.ceil(float(optimal_pours) * 0.5)))
    return optimal_pours + grace


def normalize_dialog(value: Any, default_speaker: str = "") -> list[dict[str, str]]:
    if value is None or value == "":
        return []
    if isinstance(value, str):
        return [{"speaker": default_speaker, "text": value}]
    if isinstance(value, dict):
        speaker = str(value.get("speaker", default_speaker))
        if "lines" in value:
            return normalize_dialog(value.get("lines"), speaker)
        return [{"speaker": speaker, "text": str(value.get("text", ""))}]
    if not isinstance(value, list):
        return [{"speaker": default_speaker, "text": str(value)}]

    lines: list[dict[str, str]] = []
    for item in value:
        if isinstance(item, str):
            lines.append({"speaker": default_speaker, "text": item})
        elif isinstance(item, dict):
            speaker = str(item.get("speaker", default_speaker))
            if "lines" in item:
                lines.extend(normalize_dialog(item.get("lines"), speaker))
            else:
                lines.append({"speaker": speaker, "text": str(item.get("text", ""))})
        else:
            lines.append({"speaker": default_speaker, "text": str(item)})
    return [line for line in lines if line["text"] != ""]


def i18n_key(*parts: Any) -> str:
    return ".".join(str(part).strip().replace(" ", "_") for part in parts if str(part).strip() != "")


def register_i18n(i18n: dict[str, dict[str, str]], locale: str, key: str, text: Any) -> None:
    if not key:
        return
    value = str(text)
    if value == "":
        return
    if locale not in i18n:
        i18n[locale] = {}
    i18n[locale][key] = value


def add_i18n_field(
    container: dict[str, Any],
    field: str,
    key: str,
    i18n: dict[str, dict[str, str]],
    locale: str,
) -> None:
    container[f"{field}_key"] = key
    register_i18n(i18n, locale, key, container.get(field, ""))


def place_i18n_keys(container: dict[str, Any], fields: list[str]) -> None:
    ordered: dict[str, Any] = {}
    for key, value in container.items():
        if key.endswith("_key") and key[:-4] in fields:
            continue
        ordered[key] = value
        key_field = f"{key}_key"
        if key in fields and key_field in container:
            ordered[key_field] = container[key_field]
    container.clear()
    container.update(ordered)


def add_dialog_i18n(
    lines: list[dict[str, str]],
    base_key: str,
    i18n: dict[str, dict[str, str]],
    locale: str,
) -> None:
    for index, line in enumerate(lines, start=1):
        line_base_key = i18n_key(base_key, f"line_{index:02d}")
        add_i18n_field(line, "speaker", i18n_key(line_base_key, "speaker"), i18n, locale)
        add_i18n_field(line, "text", i18n_key(line_base_key, "text"), i18n, locale)
        place_i18n_keys(line, ["speaker", "text"])


def add_puzzle_i18n(
    puzzle: dict[str, Any],
    adventure_id: str,
    i18n: dict[str, dict[str, str]],
    locale: str,
) -> None:
    puzzle_id = str(puzzle.get("id", "puzzle"))
    puzzle_base_key = i18n_key("adventure", adventure_id, "puzzle", puzzle_id)
    add_i18n_field(puzzle, "title", i18n_key(puzzle_base_key, "title"), i18n, locale)
    add_i18n_field(puzzle, "introduces", i18n_key(puzzle_base_key, "introduces"), i18n, locale)
    place_i18n_keys(puzzle, ["title", "introduces"])

    dialog = puzzle.get("dialog", {})
    if not isinstance(dialog, dict):
        return
    intro = dialog.get("intro", [])
    if isinstance(intro, list):
        add_dialog_i18n(intro, i18n_key(puzzle_base_key, "dialog", "intro"), i18n, locale)
    outro = dialog.get("outro", [])
    if isinstance(outro, list):
        add_dialog_i18n(outro, i18n_key(puzzle_base_key, "dialog", "outro"), i18n, locale)


def deep_merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    merged = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged


def stable_seed(value: Any) -> int:
    if value is None:
        return 1
    if isinstance(value, int):
        return value
    try:
        return int(str(value), 0)
    except ValueError:
        digest = hashlib.sha256(str(value).encode("utf-8")).digest()
        return int.from_bytes(digest[:8], "big")


def validate_generation_shape(config: dict[str, Any], label: str) -> None:
    capacity = int(config.get("capacity", 4))
    filled = int(config.get("filled_beakers", 6))
    empty = int(config.get("empty_beakers", 2))
    if capacity < 3 or capacity > 8:
        raise GenerationError(f"{label}: capacity must be 3..8.")
    if filled <= 0 or empty <= 0:
        raise GenerationError(f"{label}: filled_beakers and empty_beakers must be positive.")
    if filled + empty > MAX_TOTAL_BEAKERS:
        raise GenerationError(f"{label}: total beakers cannot exceed {MAX_TOTAL_BEAKERS}.")
    if int(config.get("min_solution_depth", 1)) > int(config.get("max_solution_depth", 999)):
        raise GenerationError(f"{label}: min_solution_depth exceeds max_solution_depth.")


def validate_block(block: dict[str, Any], block_number: int) -> None:
    validate_generation_shape(block, f"Block {block_number}")
    capacity = int(block.get("capacity", 4))
    filled = int(block.get("filled_beakers", 6))
    empty = int(block.get("empty_beakers", 2))
    if int(block.get("puzzle_count", 10)) <= 0:
        raise GenerationError(f"Block {block_number}: puzzle_count must be positive.")
    # Keep local variables referenced so a malformed string value fails here with
    # a useful block label rather than later in generation.
    _ = capacity + filled + empty


def generate_puzzle(
    rng: random.Random,
    adventure_id: str,
    block: dict[str, Any],
    block_index: int,
    puzzle_index: int,
    used_codes: set[str],
) -> dict[str, Any]:
    capacity = int(block.get("capacity", 4))
    filled = int(block.get("filled_beakers", 6))
    empty = int(block.get("empty_beakers", 2))
    min_depth = int(block.get("min_solution_depth", 1))
    max_depth = int(block.get("max_solution_depth", 999))
    candidate_limit = int(block.get("candidate_limit", 500))
    node_limit = int(block.get("node_limit", 750000))
    frontier_limit = int(block.get("frontier_limit", 260000))
    solver_timeout_ms = int(block.get("solver_timeout_ms", 0))
    allow_duplicates = bool(block.get("allow_duplicates", False))
    embed_cracked_goal = bool(block.get("embed_cached_goal_for_cracked", False))

    rejection_counts: dict[str, int] = {}
    for candidate_idx in range(1, candidate_limit + 1):
        beakers = random_fill_board(rng, capacity, filled, empty)
        traits = assign_traits(rng, beakers, block, capacity, filled)
        if traits is None:
            rejection_counts["trait assignment failed"] = rejection_counts.get("trait assignment failed", 0) + 1
            continue

        state = as_state(beakers)
        if state_complete(state, traits, capacity):
            rejection_counts["already complete"] = rejection_counts.get("already complete", 0) + 1
            continue
        if state_has_shattered_cracked(state, traits, capacity):
            rejection_counts["cracked beaker would shatter"] = (
                rejection_counts.get("cracked beaker would shatter", 0) + 1
            )
            continue
        if count_available_moves(state, traits, capacity) <= 0:
            rejection_counts["no available moves"] = rejection_counts.get("no available moves", 0) + 1
            continue

        solver = solve_optimal(state, traits, capacity, node_limit, frontier_limit, solver_timeout_ms)
        if not solver.solved:
            rejection_counts[solver.reason or "unsolved"] = rejection_counts.get(solver.reason or "unsolved", 0) + 1
            continue
        if solver.depth < min_depth:
            rejection_counts["below min depth"] = rejection_counts.get("below min depth", 0) + 1
            continue
        if solver.depth > max_depth:
            rejection_counts["above max depth"] = rejection_counts.get("above max depth", 0) + 1
            continue

        has_cracked = any(is_cracked(traits, idx) for idx in range(len(traits)))
        cached_goal = solver.depth if (not has_cracked or embed_cracked_goal) else -1
        board_code = encode_board_code(capacity, filled, empty, beakers, traits, cached_goal)
        if not board_code:
            rejection_counts["board code encode failed"] = rejection_counts.get("board code encode failed", 0) + 1
            continue
        if not allow_duplicates and board_code in used_codes:
            rejection_counts["duplicate board"] = rejection_counts.get("duplicate board", 0) + 1
            continue
        decoded = decode_board_code(board_code)
        if not decoded.get("ok"):
            rejection_counts["board code roundtrip failed"] = (
                rejection_counts.get("board code roundtrip failed", 0) + 1
            )
            continue

        used_codes.add(board_code)
        puzzle_number = puzzle_index + 1
        block_number = block_index + 1
        puzzle_id = f"{adventure_id}-b{block_number:02d}-p{puzzle_number:02d}"
        puzzle_title = str(block.get("puzzle_title", "")).strip()
        if puzzle_title == "":
            puzzle_title_prefix = str(block.get("puzzle_title_prefix", "")).strip()
            puzzle_title = (
                f"{puzzle_title_prefix} {puzzle_number}"
                if puzzle_title_prefix
                else str(block.get("title", f"Puzzle {puzzle_number}"))
            )
        scoring_mode = "chill" if bool(block.get("chill", False)) else "scored"
        dialog_speaker = str(block.get("dialog_speaker", ""))
        return {
            "id": puzzle_id,
            "index": puzzle_number,
            "global_index": int(block.get("_global_start_index", 0)) + puzzle_number,
            "title": puzzle_title,
            "introduces": str(block.get("introduces", "")),
            "dialog": {
                "intro": normalize_dialog(block.get("intro_dialog", []), dialog_speaker),
                "outro": normalize_dialog(block.get("outro_dialog", []), dialog_speaker),
            },
            "board_code": board_code,
            "capacity": capacity,
            "filled_beakers": filled,
            "empty_beakers": empty,
            "beaker_count": filled + empty,
            "optimal_pours": solver.depth,
            "optimal_solution": encode_solution_moves(solver.solution),
            "optimal_solution_format": "hex_source_dest_pairs",
            "pour_limit": pour_limit_for_goal(solver.depth),
            "star_score_thresholds": STAR_SCORE_THRESHOLDS,
            "traits": trait_summary(traits),
            "rules": {
                "scoring": {
                    "mode": scoring_mode,
                    "stars_on_solve": int(block.get("stars_on_solve", 5 if scoring_mode == "chill" else 0)),
                },
                "cheats": deep_merge(DEFAULT_CHEATS, dict(block.get("cheats", {}))),
                "special_beakers": {
                    "visible_cracked_count": trait_summary(traits)["visible_cracked"],
                    "hidden_cracked_count": trait_summary(traits)["hidden_cracked"],
                    "prismatic_count": trait_summary(traits)["prismatic"],
                    "tinted_count": trait_summary(traits)["tinted"],
                },
            },
            "difficulty": {
                "solution_depth": solver.depth,
                "candidate": candidate_idx,
                "solver_searched": solver.searched,
                "solver_visited": solver.visited,
                "solver_frontier_peak": solver.frontier_peak,
                "solver_elapsed_ms": solver.elapsed_ms,
                **board_metrics(state, traits, capacity),
            },
            "generator": {
                "rejections": rejection_counts,
            },
        }

    raise GenerationError(
        "Could not generate puzzle "
        f"{puzzle_index + 1} for block {block_index + 1} after {candidate_limit} candidates. "
        f"Rejections: {rejection_counts}"
    )


def summarize_depths(blocks: list[dict[str, Any]]) -> dict[str, Any]:
    depths = [
        int(puzzle["optimal_pours"])
        for block in blocks
        for puzzle in block.get("puzzles", [])
        if "optimal_pours" in puzzle
    ]
    if not depths:
        return {"min": 0, "max": 0, "average": 0.0}
    return {
        "min": min(depths),
        "max": max(depths),
        "average": round(sum(depths) / float(len(depths)), 2),
    }


def generate_adventure(config: dict[str, Any], config_path: Path, seed_override: Any, quiet: bool) -> dict[str, Any]:
    adventure_cfg = dict(config.get("adventure", {}))
    adventure_id = str(adventure_cfg.get("id", "generated_adventure")).strip() or "generated_adventure"
    adventure_title = str(adventure_cfg.get("title", adventure_id.replace("_", " ").title()))
    adventure_version = int(adventure_cfg.get("version", 1))
    default_locale = str(adventure_cfg.get("default_locale", "en")).strip() or "en"
    master_seed = stable_seed(seed_override if seed_override is not None else adventure_cfg.get("seed", 1))
    master_rng = random.Random(master_seed)
    i18n: dict[str, dict[str, str]] = {default_locale: {}}

    defaults = dict(config.get("defaults", {}))
    blocks_cfg = config.get("blocks", [])
    if not isinstance(blocks_cfg, list) or not blocks_cfg:
        raise GenerationError("Config must contain at least one [[blocks]] entry.")

    generated_blocks: list[dict[str, Any]] = []
    used_codes: set[str] = set()
    global_start = 0
    total_puzzles = 0
    total_stars = 0

    for block_index, raw_block in enumerate(blocks_cfg):
        block = deep_merge(defaults, dict(raw_block))
        block["_global_start_index"] = global_start
        validate_block(block, block_index + 1)

        puzzle_count = int(block.get("puzzle_count", 10))
        total_puzzles += puzzle_count
        total_stars += puzzle_count * 5
        block_seed = master_rng.randrange(0, 2**63)
        block_rng = random.Random(block_seed)
        block_id = str(block.get("id", f"block_{block_index + 1:02d}"))
        block_title = str(block.get("title", block_id.replace("_", " ").title()))

        if not quiet:
            print(
                f"Generating {block_id} ({puzzle_count} puzzles, "
                f"{int(block.get('filled_beakers', 6))}+{int(block.get('empty_beakers', 2))} beakers, "
                f"capacity {int(block.get('capacity', 4))})",
                flush=True,
            )

        puzzle_overrides = block.get("puzzles", [])
        if puzzle_overrides is None:
            puzzle_overrides = []
        if not isinstance(puzzle_overrides, list):
            raise GenerationError(f"Block {block_index + 1}: puzzles must be a list of override tables.")

        puzzles: list[dict[str, Any]] = []
        for puzzle_index in range(puzzle_count):
            puzzle_config = dict(block)
            puzzle_config.pop("puzzles", None)
            if puzzle_index < len(puzzle_overrides):
                override = dict(puzzle_overrides[puzzle_index])
                if "title" in override and "puzzle_title" not in override:
                    override["puzzle_title"] = override["title"]
                puzzle_config = deep_merge(puzzle_config, override)
                puzzle_config["_global_start_index"] = global_start
            validate_generation_shape(
                puzzle_config,
                f"Block {block_index + 1} puzzle {puzzle_index + 1}",
            )
            puzzle = generate_puzzle(block_rng, adventure_id, puzzle_config, block_index, puzzle_index, used_codes)
            add_puzzle_i18n(puzzle, adventure_id, i18n, default_locale)
            puzzles.append(puzzle)
            if not quiet:
                mode = puzzle["rules"]["scoring"]["mode"]
                print(
                    "  "
                    f"{puzzle['id']}: goal {puzzle['optimal_pours']} pours, "
                    f"{mode}, "
                    f"candidate {puzzle['difficulty']['candidate']}, "
                    f"searched {puzzle['difficulty']['solver_searched']}",
                    flush=True,
                )

        unlock_min_stars = int(
            block.get(
                "min_stars_to_unlock_next",
                max(0, int(math.ceil(float(puzzle_count * 5) * 0.70))),
            )
        )
        block_payload = {
            "id": block_id,
            "index": block_index + 1,
            "title": block_title,
            "introduces": str(block.get("introduces", "")),
            "unlock_next": {
                "requires_all_solved": bool(block.get("requires_all_solved", True)),
                "min_stars": unlock_min_stars,
                "max_stars": puzzle_count * 5,
            },
            "rules": {
                "capacity": int(block.get("capacity", 4)),
                "filled_beakers": int(block.get("filled_beakers", 6)),
                "empty_beakers": int(block.get("empty_beakers", 2)),
                "min_solution_depth": int(block.get("min_solution_depth", 1)),
                "max_solution_depth": int(block.get("max_solution_depth", 999)),
                "cheats": deep_merge(DEFAULT_CHEATS, dict(block.get("cheats", {}))),
                "special_beakers": {
                    "cracked_count": int(block.get("cracked_count", 0)),
                    "hidden_cracked_count": int(block.get("hidden_cracked_count", block.get("cracked_count", 0))),
                    "visible_cracked_count": int(block.get("visible_cracked_count", 0)),
                    "prismatic_count": int(block.get("prismatic_count", 0)),
                    "tinted_count": int(block.get("tinted_count", 0)),
                },
            },
            "puzzles": puzzles,
        }
        block_base_key = i18n_key("adventure", adventure_id, "block", block_id)
        add_i18n_field(block_payload, "title", i18n_key(block_base_key, "title"), i18n, default_locale)
        add_i18n_field(block_payload, "introduces", i18n_key(block_base_key, "introduces"), i18n, default_locale)
        place_i18n_keys(block_payload, ["title", "introduces"])
        generated_blocks.append(block_payload)
        global_start += puzzle_count

    adventure_metadata = {
        "id": adventure_id,
        "title": adventure_title,
        "description": str(adventure_cfg.get("description", "")),
        "version": adventure_version,
        "seed": master_seed,
        "default_locale": default_locale,
        "block_count": len(generated_blocks),
        "puzzle_count": total_puzzles,
        "total_stars": total_stars,
    }
    adventure_base_key = i18n_key("adventure", adventure_id)
    add_i18n_field(adventure_metadata, "title", i18n_key(adventure_base_key, "title"), i18n, default_locale)
    add_i18n_field(adventure_metadata, "description", i18n_key(adventure_base_key, "description"), i18n, default_locale)
    place_i18n_keys(adventure_metadata, ["title", "description"])

    return {
        "schema_version": 1,
        "generated_at": dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat(),
        "generator": {
            "name": "rainbow-pour-adventure-generator",
            "version": 1,
            "config": str(config_path.as_posix()),
        },
        "adventure": adventure_metadata,
        "i18n": i18n,
        "scoring": {
            "score_max": SCORE_MAX,
            "star_score_thresholds": STAR_SCORE_THRESHOLDS,
            "pour_limit_grace": "max(6, ceil(optimal_pours * 0.5))",
            "default_cheats": DEFAULT_CHEATS,
        },
        "summary": {
            "optimal_pours": summarize_depths(generated_blocks),
        },
        "blocks": generated_blocks,
    }


def load_toml(path: Path) -> dict[str, Any]:
    if tomllib is None:
        raise GenerationError("Python 3.11+ is required for stdlib TOML parsing.")
    try:
        with path.open("rb") as handle:
            return tomllib.load(handle)
    except FileNotFoundError as exc:
        raise GenerationError(f"Config not found: {path}") from exc
    except tomllib.TOMLDecodeError as exc:
        raise GenerationError(f"Invalid TOML in {path}: {exc}") from exc


def resolve_output_path(config: dict[str, Any], config_path: Path, output_override: str | None) -> Path:
    if output_override:
        return Path(output_override)
    adventure_cfg = dict(config.get("adventure", {}))
    configured = str(adventure_cfg.get("output", "")).strip()
    if configured:
        return Path(configured)
    adventure_id = str(adventure_cfg.get("id", config_path.stem)).strip() or config_path.stem
    return Path("assets") / "adventures" / f"{adventure_id}.json"


def write_json(path: Path, payload: dict[str, Any], indent: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(payload, handle, indent=indent, sort_keys=False)
        handle.write("\n")


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Generate Rainbow Pour adventure JSON from TOML.")
    parser.add_argument("config", help="Path to the adventure TOML config.")
    parser.add_argument("-o", "--output", help="Output JSON path. Overrides [adventure].output.")
    parser.add_argument("--report", help="Optional diagnostics report JSON path.")
    parser.add_argument("--seed", help="Override [adventure].seed for reproducible variants.")
    parser.add_argument("--dry-run", action="store_true", help="Generate and validate without writing files.")
    parser.add_argument("--compact", action="store_true", help="Write compact JSON instead of pretty JSON.")
    parser.add_argument("-q", "--quiet", action="store_true", help="Suppress per-puzzle progress.")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_arg_parser().parse_args(argv)
    config_path = Path(args.config)
    try:
        config = load_toml(config_path)
        adventure = generate_adventure(config, config_path, args.seed, args.quiet)
        output_path = resolve_output_path(config, config_path, args.output)
        indent = None if args.compact else 2
        if not args.dry_run:
            write_json(output_path, adventure, indent if indent is not None else 0)
            if args.report:
                report = {
                    "generated_at": adventure["generated_at"],
                    "adventure": adventure["adventure"],
                    "summary": adventure["summary"],
                    "blocks": [
                        {
                            "id": block["id"],
                            "title": block["title"],
                            "unlock_next": block["unlock_next"],
                            "rules": block["rules"],
                            "puzzles": [
                                {
                                    "id": puzzle["id"],
                                    "optimal_pours": puzzle["optimal_pours"],
                                    "optimal_solution": puzzle["optimal_solution"],
                                    "pour_limit": puzzle["pour_limit"],
                                    "traits": puzzle["traits"],
                                    "difficulty": puzzle["difficulty"],
                                    "generator": puzzle["generator"],
                                }
                                for puzzle in block["puzzles"]
                            ],
                        }
                        for block in adventure["blocks"]
                    ],
                }
                write_json(Path(args.report), report, 2)
        if not args.quiet:
            destination = "(dry run)" if args.dry_run else str(output_path)
            print(
                f"Generated {adventure['adventure']['puzzle_count']} puzzles "
                f"across {adventure['adventure']['block_count']} blocks -> {destination}",
                flush=True,
            )
            depth = adventure["summary"]["optimal_pours"]
            print(
                f"Optimal pours: min {depth['min']}, max {depth['max']}, "
                f"avg {depth['average']}",
                flush=True,
            )
    except GenerationError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
