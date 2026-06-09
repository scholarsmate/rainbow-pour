from __future__ import annotations

from array import array
import math
from pathlib import Path
import random
import sys
import wave

RATE = 22050
TAU = math.tau
OUT_DIR = Path("assets/audio/generated")
RNG_SEED = 431209


def clamp_sample(value: float) -> int:
    return max(-32768, min(32767, int(value * 32767.0)))


def loop_hz(hz: float, dur: float) -> float:
    return round(hz * dur) / dur


def quantize_notes(notes: list[float], dur: float) -> list[float]:
    return [loop_hz(float(hz), dur) for hz in notes]


def quantize_chords(chords: list[list[float]], dur: float) -> list[list[float]]:
    return [quantize_notes(chord, dur) for chord in chords]


def music_kick(hit_t: float, rng: random.Random, amp: float = 1.0) -> float:
    attack = min(1.0, hit_t / 0.012)
    tail = math.exp(-hit_t * 24.0)
    drop = 84.0 - 50.0 * min(1.0, hit_t / 0.13)
    sub = math.sin(TAU * drop * hit_t) * attack * tail * 0.34
    low = math.sin(TAU * 43.0 * hit_t) * math.exp(-hit_t * 13.0) * 0.21
    knock = math.sin(TAU * 118.0 * hit_t) * math.exp(-hit_t * 38.0) * 0.055
    click = rng.uniform(-1.0, 1.0) * attack * math.exp(-hit_t * 120.0) * 0.028
    return (sub + low + knock + click) * amp


def music_snare(hit_t: float, rng: random.Random, amp: float = 1.0) -> float:
    snap = rng.uniform(-1.0, 1.0) * math.exp(-hit_t * 64.0) * 0.034
    brush = rng.uniform(-1.0, 1.0) * math.exp(-hit_t * 25.0) * 0.026
    tick = math.sin(TAU * 720.0 * hit_t) * math.exp(-hit_t * 36.0) * 0.018
    air = math.sin(TAU * 1350.0 * hit_t) * math.exp(-hit_t * 52.0) * 0.006
    return (snap + brush + tick + air) * amp


def render_game_loop(rng: random.Random) -> array:
    dur = 63.0
    chords = quantize_chords([
        [261.63, 329.63, 392.00],
        [293.66, 349.23, 440.00],
        [329.63, 392.00, 493.88],
        [246.94, 329.63, 392.00],
        [261.63, 349.23, 440.00],
        [293.66, 369.99, 440.00],
        [329.63, 415.30, 493.88],
        [246.94, 329.63, 440.00],
        [261.63, 392.00, 523.25],
        [293.66, 349.23, 523.25],
        [329.63, 392.00, 587.33],
        [246.94, 369.99, 493.88],
        [261.63, 329.63, 440.00],
        [293.66, 392.00, 493.88],
        [329.63, 440.00, 659.25],
        [246.94, 329.63, 392.00],
    ], dur)
    ripples = quantize_notes([
        659.25, 783.99, 880.00, 987.77,
        783.99, 659.25, 587.33, 523.25,
        698.46, 880.00, 987.77, 1046.50,
        880.00, 783.99, 659.25, 587.33,
        783.99, 987.77, 1174.66, 1318.51,
        1046.50, 880.00, 783.99, 659.25,
        587.33, 659.25, 783.99, 880.00,
        987.77, 880.00, 659.25, 523.25,
    ], dur)
    chord_step = dur / len(chords)
    kick_hits = [0.0, chord_step * 0.25, chord_step * 0.4375, chord_step * 0.625, chord_step * 0.75]
    kick_amps = [1.34, 0.94, 0.74, 1.16, 0.64]
    snare_hits = [chord_step * 0.1875, chord_step * 0.375, chord_step * 0.5625, chord_step * 0.84375]
    snare_amps = [0.26, 0.48, 0.22, 0.36]
    low_hz = loop_hz(110.0, dur)
    samples = array("h")
    for i in range(int(RATE * dur)):
        t = i / RATE
        chord = chords[int(t / chord_step) % len(chords)]
        section_swell = 0.92 + 0.08 * math.sin(TAU * t / (dur * 0.5))
        sample = 0.0
        for hz in chord:
            sample += math.sin(TAU * hz * 0.5 * t) * 0.056 * section_swell
            sample += math.sin(TAU * hz * t) * 0.017
        ripple_t = t % 0.5
        ripple_idx = int(t * 2.0) % len(ripples)
        ripple_hz = ripples[ripple_idx]
        ripple_amp = 0.035 + 0.008 * math.sin(TAU * (ripple_idx / len(ripples)))
        sample += math.sin(TAU * ripple_hz * t) * math.exp(-ripple_t * 8.0) * ripple_amp
        if int(t * 2.0) % 16 == 7:
            echo_t = (t + 0.18) % 0.5
            sample += math.sin(TAU * ripple_hz * 0.5 * t) * math.exp(-echo_t * 7.0) * 0.014
        sample += math.sin(TAU * low_hz * t + math.sin(TAU * 8.0 * t / dur) * 0.18) * 0.036
        pattern_t = t % chord_step
        for hit, amp in zip(kick_hits, kick_amps):
            hit_t = pattern_t - hit
            if 0.0 <= hit_t < 0.19:
                sample += music_kick(hit_t, rng, amp)
        for hit, amp in zip(snare_hits, snare_amps):
            hit_t = pattern_t - hit
            if 0.0 <= hit_t < 0.22:
                sample += music_snare(hit_t, rng, amp)
        samples.append(clamp_sample(sample))
    return samples


def render_menu_loop(_rng: random.Random) -> array:
    dur = 32.0
    chords = quantize_chords([
        [261.63, 329.63, 392.00, 523.25],
        [293.66, 349.23, 440.00, 587.33],
        [246.94, 329.63, 392.00, 493.88],
        [261.63, 349.23, 440.00, 523.25],
        [329.63, 392.00, 493.88, 659.25],
        [293.66, 369.99, 440.00, 587.33],
        [246.94, 329.63, 415.30, 493.88],
        [261.63, 329.63, 392.00, 523.25],
    ], dur)
    melody = quantize_notes([
        659.25, 783.99, 880.00, 783.99,
        587.33, 659.25, 783.99, 659.25,
        523.25, 587.33, 659.25, 783.99,
        880.00, 783.99, 659.25, 523.25,
    ], dur)
    chord_step = dur / len(chords)
    note_step = dur / len(melody)
    low_hz = loop_hz(65.41, dur)
    shimmer_hz = loop_hz(1318.51, dur)
    samples = array("h")
    for i in range(int(RATE * dur)):
        t = i / RATE
        chord = chords[int(t / chord_step) % len(chords)]
        sample = 0.0
        swell = 0.86 + 0.14 * math.sin(TAU * t / dur)
        for hz in chord:
            sample += math.sin(TAU * hz * 0.5 * t) * 0.038 * swell
            sample += math.sin(TAU * hz * t) * 0.010
        note_t = t % note_step
        note_hz = melody[int(t / note_step) % len(melody)]
        bell_env = math.exp(-note_t * 5.8)
        sample += math.sin(TAU * note_hz * t) * bell_env * 0.042
        sample += math.sin(TAU * note_hz * 2.0 * t) * bell_env * 0.012
        ripple_t = (t + note_step * 0.5) % note_step
        if ripple_t < note_step * 0.62:
            sample += math.sin(TAU * shimmer_hz * 0.5 * t) * math.exp(-ripple_t * 7.0) * 0.014
        sample += math.sin(TAU * low_hz * t + math.sin(TAU * 2.0 * t / dur) * 0.16) * 0.024
        samples.append(clamp_sample(sample))
    return samples


def render_result_loop(rng: random.Random, solved: bool) -> array:
    dur = 16.0
    if solved:
        chords = [
            [261.63, 329.63, 392.00, 523.25],
            [293.66, 369.99, 440.00, 587.33],
            [329.63, 392.00, 493.88, 659.25],
            [392.00, 493.88, 587.33, 783.99],
        ]
        melody = [783.99, 987.77, 1046.50, 1318.51, 1174.66, 987.77, 880.00, 1046.50]
    else:
        chords = [
            [220.00, 261.63, 329.63],
            [196.00, 246.94, 293.66],
            [174.61, 220.00, 261.63],
            [196.00, 233.08, 293.66],
        ]
        melody = [392.00, 349.23, 329.63, 293.66, 261.63, 246.94, 220.00, 196.00]

    chords = quantize_chords(chords, dur)
    melody = quantize_notes(melody, dur)
    failed_low_hz = loop_hz(72.0, dur)
    samples = array("h")
    for i in range(int(RATE * dur)):
        t = i / RATE
        chord = chords[int(t / 4.0) % len(chords)]
        sample = 0.0
        for hz in chord:
            if solved:
                sample += math.sin(TAU * hz * 0.5 * t) * 0.035
                sample += math.sin(TAU * hz * t) * 0.012
            else:
                sample += math.sin(TAU * hz * 0.5 * t) * 0.045
                sample += math.sin(TAU * hz * 0.25 * t) * 0.020
        if solved:
            step = 0.50
            note_t = t % step
            note_idx = int(t / step) % len(melody)
            hz = melody[note_idx]
            bell_env = math.exp(-note_t * 7.5)
            sample += math.sin(TAU * hz * t) * bell_env * 0.065
            sample += math.sin(TAU * hz * 2.0 * t) * bell_env * 0.020
            if int(t / 2.0) % 2 == 0:
                sparkle_t = (t + 0.125) % 0.50
                sample += math.sin(TAU * hz * 1.5 * t) * math.exp(-sparkle_t * 9.0) * 0.018
        else:
            step = 1.0
            note_t = t % step
            note_idx = int(t / step) % len(melody)
            hz = melody[note_idx]
            soft_env = math.exp(-note_t * 3.6)
            sample += math.sin(TAU * hz * 0.5 * t) * soft_env * 0.050
            sample += math.sin(TAU * failed_low_hz * t + math.sin(TAU * 3.0 * t / dur) * 0.22) * 0.028
            if note_t < 0.28 and note_idx % 2 == 1:
                sample += music_kick(note_t, rng, 0.20)
            sample += math.sin(TAU * loop_hz(997.0, dur) * t) * math.exp(-note_t * 5.0) * 0.006
        samples.append(clamp_sample(sample))
    return samples


def write_wav(path: Path, samples: array) -> None:
    if sys.byteorder != "little":
        samples = array("h", samples)
        samples.byteswap()
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(samples.tobytes())


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    tracks = [
        ("game_loop.wav", render_game_loop),
        ("menu_loop.wav", render_menu_loop),
        ("solved_loop.wav", lambda rng: render_result_loop(rng, True)),
        ("failed_loop.wav", lambda rng: render_result_loop(rng, False)),
    ]
    for idx, (name, renderer) in enumerate(tracks):
        rng = random.Random(RNG_SEED + idx)
        path = OUT_DIR / name
        samples = renderer(rng)
        write_wav(path, samples)
        print(f"Saved {path} ({len(samples) / RATE:.1f}s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
