#!/usr/bin/env python3
"""Render three original Altillo instrumental miniatures. Requires numpy and ffmpeg.

Run from any directory: python3 website/scripts/generate-demo-music.py
All sounds are synthesized here; no samples, external music or API keys are used.
"""
from pathlib import Path
import subprocess
import tempfile
import wave

import numpy as np

SR = 44100
OUTPUT = Path(__file__).resolve().parents[1] / "public/media/music"


def hz(note):
    return 440 * 2 ** ((note - 69) / 12)


def render(name, title, bpm, chords, melody, seed, mood):
    rng = np.random.default_rng(seed)
    beat = 60 / bpm
    length = 16 * 4 * beat + 3
    mix = np.zeros((int(length * SR), 2), dtype=np.float64)

    def place(sound, start, gain=1, pan=0, echo=False):
        # Equal-power panning; note tails and room reflections are stereo.
        idx = max(0, round(start * SR))
        size = min(len(sound), len(mix) - idx)
        if size <= 0:
            return
        angle = (pan + 1) * np.pi / 4
        mix[idx:idx + size, 0] += sound[:size] * gain * np.cos(angle)
        mix[idx:idx + size, 1] += sound[:size] * gain * np.sin(angle)
        if echo:
            for delay, strength, side in [(0.13, .12, -.6), (.23, .10, .65),
                                           (.37, .065, -.4), (.53, .04, .4)]:
                place(sound, start + delay, gain * strength, side)

    def piano(note, duration=2.6):
        t = np.arange(int(SR * duration)) / SR
        f = hz(note)
        # Rounded tine piano: soft fundamental, decaying upper partials and
        # minute detuning create an instrument rather than a pure oscillator.
        voice = (np.sin(2 * np.pi * f * t + .32 * np.sin(2 * np.pi * f * 2 * t)
                        * np.exp(-t * 3)) * np.exp(-t / 1.35)
                 + .18 * np.sin(2 * np.pi * f * 2.002 * t) * np.exp(-t / .65)
                 + .055 * np.sin(2 * np.pi * f * 3 * t) * np.exp(-t / .24))
        return voice * np.minimum(t / .008, 1) * np.minimum((duration - t) / .16, 1)

    def pad(notes, duration):
        t = np.arange(int(SR * duration)) / SR
        sound = np.zeros(len(t))
        for note in notes:
            f = hz(note)
            sound += (np.sin(2 * np.pi * f * .999 * t)
                      + np.sin(2 * np.pi * f * 1.001 * t)
                      + .14 * np.sin(2 * np.pi * f * 2 * t)) / len(notes)
        envelope = np.minimum(t / .7, 1) * np.minimum((duration - t) / 1.1, 1)
        return sound * envelope * (.9 + .1 * np.sin(2 * np.pi * .22 * t))

    def bass(note, duration):
        t = np.arange(int(SR * duration)) / SR
        return (np.sin(2 * np.pi * hz(note) * t)
                + .19 * np.sin(2 * np.pi * hz(note) * 2 * t)) * np.minimum(t / .02, 1) * np.exp(-t / .65) * np.minimum((duration - t) / .1, 1)

    def drum(kind):
        duration = {"kick": .45, "snare": .18, "hat": .075}[kind]
        t = np.arange(int(SR * duration)) / SR
        noise = rng.normal(0, 1, len(t))
        if kind == "kick":
            phase = 2 * np.pi * (47 * t + 3 * (1 - np.exp(-t * 35)))
            return np.sin(phase) * np.exp(-t * 12) * np.minimum(t / .003, 1)
        if kind == "snare":
            soft = np.convolve(noise, np.ones(9) / 9, mode="same")
            return (soft * .65 + .17 * np.sin(2 * np.pi * 175 * t)) * np.exp(-t * 29) * np.minimum(t / .002, 1)
        high = noise - np.convolve(noise, np.ones(7) / 7, mode="same")
        return high * np.exp(-t * 85) * np.minimum(t / .001, 1)

    for bar in range(16):
        chord = chords[bar % len(chords)]
        start = bar * 4 * beat
        intensity = .72 if bar < 2 or bar > 13 else 1
        place(pad([n + 12 for n in chord[:3]], beat * 4 + 1), start, .043, -.15)
        # Slightly rolled, syncopated extended chords.
        for pulse, strength in [(0, .105), (1.75, .068), (3.0, .082)]:
            if bar > 13 and pulse == 1.75:
                continue
            for j, note in enumerate(chord):
                place(piano(note), start + pulse * beat + j * .014,
                      strength * intensity * rng.uniform(.9, 1.05), (j - 1.5) * .15, True)
        for pulse, note, volume in [(0, chord[0] - 24, .20), (2.5, chord[0] - 24, .145), (3.5, chord[0] - 12, .09)]:
            place(bass(note, beat * 1.4), start + pulse * beat, volume * intensity)
        # Four-bar melodies recur with a small octave answer halfway through.
        for pulse, note in melody[bar % 4]:
            if bar < 1:
                continue
            place(piano(note + (12 if mood == "night" and 8 <= bar < 12 else 0), 2.8),
                  start + pulse * beat, .102 * intensity, .27, True)
        if 1 <= bar < 15:
            for pulse in [0, 2.25] + ([3.5] if bar % 4 == 3 else []):
                place(drum("kick"), start + pulse * beat, .25 * intensity)
            for pulse in [1, 3]:
                place(drum("snare"), start + (pulse + .024) * beat, .18 * intensity, -.09, True)
            for step in range(8):
                # Restrained swing, quiet closed hats, no harsh crash samples.
                pulse = step * .5 + (.065 if step % 2 else 0)
                place(drum("hat"), start + pulse * beat,
                      (.026 if step % 2 else .039) * intensity, .35)

    # Natural intro and ringing outro. Leave headroom before loudness mastering.
    fade_in = min(int(.65 * SR), len(mix))
    fade_out = int(3.8 * SR)
    mix[:fade_in] *= np.linspace(0, 1, fade_in)[:, None]
    mix[-fade_out:] *= np.linspace(1, 0, fade_out)[:, None] ** 1.5
    peak = np.max(np.abs(mix))
    mix = np.tanh(mix / peak * .85)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = Path(tmp) / "source.wav"
        with wave.open(str(wav_path), "wb") as wav:
            wav.setnchannels(2)
            wav.setsampwidth(2)
            wav.setframerate(SR)
            wav.writeframes((mix * 32767).astype("<i2").tobytes())
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(wav_path),
                        "-af", "loudnorm=I=-18:TP=-1.5:LRA=8", "-ar", str(SR),
                        "-codec:a", "libmp3lame", "-b:a", "128k",
                        "-metadata", f"title={title}", "-metadata", "artist=Estudio Altillo",
                        "-metadata", "album=Desde el altillo", str(OUTPUT / f"{name}.mp3")], check=True)
    print(f"{name}: {length:.2f}s, {(OUTPUT / f'{name}.mp3').stat().st_size:,} bytes")


if __name__ == "__main__":
    render("azotea", "Azotea", 82,
           [[57, 60, 64, 67], [53, 57, 60, 64], [60, 64, 67, 71], [55, 59, 62, 69]],
           [[(.5, 76), (1.5, 72), (2.75, 71), (3.5, 67)],
            [(.5, 69), (2, 72), (3.25, 76)],
            [(0, 79), (1.5, 76), (2.5, 74), (3.5, 71)],
            [(.5, 74), (1.75, 71), (3, 69)]], 11, "day")
    render("luz-de-tarde", "Luz de tarde", 76,
           [[53, 57, 60, 64], [55, 59, 62, 65], [52, 55, 59, 62], [57, 60, 64, 67]],
           [[(0, 72), (1.5, 69), (2.5, 67)],
            [(.5, 71), (2, 74), (3.5, 72)],
            [(.5, 71), (1.5, 67), (3, 64)],
            [(0, 69), (2, 72), (3.25, 76)]], 23, "warm")
    render("ultimo-tranvia", "Último tranvía", 86,
           [[50, 53, 57, 60], [55, 59, 62, 65], [48, 52, 55, 59], [57, 60, 64, 67]],
           [[(.5, 69), (1.25, 72), (2.75, 77)],
            [(0, 74), (1.5, 71), (3, 69)],
            [(.75, 67), (2, 71), (3.5, 76)],
            [(.5, 72), (1.75, 71), (3, 69)]], 37, "night")
