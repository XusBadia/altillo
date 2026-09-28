#!/usr/bin/env python3
"""Compone la banda sonora del anuncio con Apple Loops (licencia de Apple: uso libre en composiciones propias).

120 BPM, Do. 16 compases = 32 s exactos, alineados con la línea de tiempo de src/anuncio/Anuncio.tsx
(un compás = 2 s = 120 fotogramas a 60 fps). Salida: public/anuncio/audio/score.wav (48 kHz, estéreo).
"""
import pathlib
import subprocess

import numpy as np

SR = 48000
BPM = 120
BEAT = 60 / BPM
BAR = 4 * BEAT
BARS = 16
LOOPS = pathlib.Path('/Library/Audio/Apple Loops/Apple')
ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / 'public/anuncio/audio/score.wav'


def load(rel: str, beats: int | None = None, atempo: float | None = None) -> np.ndarray:
    """Decodifica un loop a float32 estéreo 48 kHz; si se da `beats`, lo ajusta a 120 BPM."""
    src = LOOPS / f'{rel}.caf'
    af = []
    if beats is not None:
        dur = float(subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', str(src)],
                                   capture_output=True, text=True).stdout)
        atempo = dur / (beats * BEAT)
    if atempo and abs(atempo - 1) > 1e-3:
        af = ['-af', f'atempo={atempo:.6f}']
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(src), *af, '-ar', str(SR), '-ac', '2', '-f', 'f32le', '-'],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).copy()


mix = np.zeros((int(BARS * BAR * SR), 2), dtype=np.float32)


def place(clip: np.ndarray, bar: float, bars: float | None = None, gain_db: float = 0.0, fade: float = 0.004):
    """Coloca `clip` desde el compás `bar` (1 = inicio), repitiéndolo durante `bars` compases."""
    start = int((bar - 1) * BAR * SR)
    length = int((bars * BAR if bars else len(clip) / SR) * SR)
    reps = int(np.ceil(length / len(clip)))
    seg = np.tile(clip, (reps, 1))[:length].copy()
    n = int(fade * SR)
    if n:
        ramp = np.linspace(0, 1, n)[:, None]
        seg[:n] *= ramp
        seg[-n:] *= ramp[::-1]
    end = min(len(mix), start + len(seg))
    mix[start:end] += seg[: end - start] * (10 ** (gain_db / 20))


def lowpass_sweep(clip: np.ndarray, f0: float, f1: float) -> np.ndarray:
    """Filtro paso bajo de un polo cuya frecuencia sube (exponencialmente) de f0 a f1."""
    out = np.empty_like(clip)
    freqs = f0 * (f1 / f0) ** np.linspace(0, 1, len(clip))
    alpha = 1 - np.exp(-2 * np.pi * freqs / SR)
    y = np.zeros(2, dtype=np.float32)
    for i in range(len(clip)):
        y += alpha[i] * (clip[i] - y)
        out[i] = y
    return out


# ─── Material ────────────────────────────────────────────────────────────────
cw = '07 Chillwave'
beat_a = load(f'{cw}/Doubledown Beat 01')
beat_b = load(f'{cw}/Disco Swagger Beat 01')
beat_c = load(f'{cw}/Disco Swagger Beat 02')
beat_min = load(f'{cw}/Minimal Backbeat 01')
bass = load(f'{cw}/Landing in LA Bass 02')
bass_b = load(f'{cw}/Road Trip Summer Bass')
synth1 = load(f'{cw}/Landing in LA Synth 01')
synth2 = load(f'{cw}/Landing in LA Synth 02')
synth3 = load(f'{cw}/Landing in LA Synth 03')
hook = load(f'{cw}/Road Trip Summer Synth')
guitar = load(f'{cw}/Landing in LA Guitar')
riser = load('09 Disco Funk/80s Synth FX Riser 01', beats=8)
fill1 = load('10 Vintage Breaks/Snare Drum Fill 01', beats=4)
fill3 = load('10 Vintage Breaks/Snare Drum Fill 03', beats=4)
rev = load('02 Electro House/Almost Reverse Topper', beats=8)

half = int(2 * BEAT * SR)  # medio compás

# ─── Arreglo (compases) ──────────────────────────────────────────────────────
# 1: intro filtrada mientras se escribe «hola»; aspiración inversa hacia el golpe.
place(lowpass_sweep(synth1[: int(BAR * SR)], 350, 5000), 1, 1, -3)
place(lowpass_sweep(guitar, 500, 7000), 1, 1, -8)
place(rev[-half:], 1.5, 0.5, -6)

# 2–8: entra todo con el MacBook; relleno de caja antes del notch y antes de Uso.
place(beat_a, 2, 2, -1)
place(beat_b, 4, 4, -1)
place(beat_a, 8, 1, -1)
place(bass, 2, 7, -2)
place(synth1, 2, 2, -5)
place(synth3, 4, 5, -6)
place(hook, 4, 5, -7)
place(guitar, 2, 7, -12)
place(fill1[half:], 3.5, 0.5, -4)
place(fill3[half:], 6.5, 0.5, -5)
place(fill1[half:], 8.5, 0.5, -4)

# 9: «toc, toc»: queda la base mínima y en la segunda mitad todo se para.
place(beat_min[:half], 9, 0.5, -4)
place(synth2[:half], 9, 0.5, -7)
place(rev[-half:], 9.5, 0.5, -3)

# 10–13: vuelve con Agentes; Pregunta; montaje rápido.
place(beat_c, 10, 2, -1)
place(beat_b, 12, 2, -1)
place(bass_b, 10, 4, -3)
place(synth3, 10, 4, -6)
place(hook, 10, 4, -6)
place(synth2, 12, 2, -8)
place(fill3[half:], 11.5, 0.5, -5)

# 14: subida hacia la firma.
place(beat_min, 14, 1, -6)
place(bass[: int(BAR * SR)], 14, 1, -6)
place(riser, 13, 2, -6)
place(fill1, 14, 1, -3)

# 15–16: golpe final y acorde que se apaga.
place(synth1[: int(2 * BAR * SR)] if len(synth1) >= 2 * BAR * SR else np.tile(synth1, (2, 1)), 15, 2, -4)
place(bass[: int(BEAT * SR)], 15, 0.5, -3)
place(beat_a[: int(BEAT * SR)], 15, 0.5, 0)

# Final: fundido de los dos últimos compases.
tail = int(2 * BAR * SR)
mix[-tail:] *= np.linspace(1, 0, tail)[:, None] ** 1.6

# ─── Master: limitador suave y normalización a -14 LUFS (redes) ─────────────
OUT.parent.mkdir(parents=True, exist_ok=True)
raw = OUT.with_suffix('.raw.wav')
pcm = (np.clip(mix, -4, 4) * 0.5).astype(np.float32)
subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'f32le', '-ar', str(SR), '-ac', '2', '-i', '-', str(raw)], input=pcm.tobytes(), check=True)
pre = 'highpass=f=30,acompressor=threshold=-16dB:ratio=2.5:attack=8:release=120,alimiter=limit=0.6:level=false'
# Dos pasadas de loudnorm en modo lineal: -14 LUFS sin bombeo y con el pico por debajo de -1,5 dBTP.
import json
meas = subprocess.run(['ffmpeg', '-v', 'info', '-i', str(raw), '-af', pre + ',loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json',
                       '-f', 'null', '-'], capture_output=True, text=True).stderr
m = json.loads(meas[meas.rindex('{'):meas.rindex('}') + 1])
ln = (f"loudnorm=I=-14:TP=-1.5:LRA=11:measured_I={m['input_i']}:measured_TP={m['input_tp']}:"
      f"measured_LRA={m['input_lra']}:measured_thresh={m['input_thresh']}:offset={m['target_offset']}:linear=true")
subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(raw), '-af', pre + ',' + ln,
                '-ar', str(SR), '-t', str(BARS * BAR), '-c:a', 'pcm_s24le', str(OUT)], check=True)
raw.unlink()
print(OUT)
