#!/usr/bin/env python3
"""Banda sonora de «Casa» (promo/CASA.md): la música B del anuncio, recortada a 14 compases (28,000 s), con timbre.

La B (scripts/anuncio-music-variants.py, Apple Loops) tiene 16 compases: intro 1, drop 2, sección 2–10, BREAK 11,
grande 12–14 y golpe final 15. Aquí se quitan los compases 8–9 (14–18 s de la B) para que todo llegue antes:

  salida  1–7   = B 1–7     (0–14 s)   hook, drop a los 2 s, relleno al final del 7
  salida  8     = B 10      (14–16 s)  variación antes del break
  salida  9     = B 11      (16–18 s)  BREAK: golpe en el 1, silencio → «ding-dong» del timbre (sintetizado)
  salida 10–12  = B 12–14   (18–24 s)  vuelve todo, subida en el 12
  salida 13–14  = B 15–16   (24–28 s)  GOLPE FINAL a los 24,000 s y cola

El empalme es en un límite de compás (fundido de 6 ms). El timbre son dos campanas (Mi5 → Do5, «ding… dong»)
hechas con parciales inarmónicos, en 16,5 s y 17,0 s (tiempos 2 y 3 del break).

Uso: python3 scripts/casa-music.py  →  public/casa/audio/casa.wav (48 kHz, estéreo, 24 bits) y loudnorm −14 LUFS.
"""
import pathlib
import subprocess

import numpy as np

SR = 48000
BAR = 2.0
ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / 'public/anuncio/audio/score-b.wav'
OUT = ROOT / 'public/casa/audio/casa.wav'


def read(path: pathlib.Path) -> np.ndarray:
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(path), '-f', 'f32le', '-ac', '2', '-ar', str(SR), '-'],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).copy()


def bars(x: np.ndarray, first: int, last: int) -> np.ndarray:
    return x[int((first - 1) * BAR * SR):int(last * BAR * SR)]


def splice(a: np.ndarray, b: np.ndarray, fade: float = 0.006) -> np.ndarray:
    n = int(fade * SR)
    ramp = np.linspace(0, 1, n, dtype=np.float32)[:, None]
    mid = a[-n:] * (1 - ramp) + b[:n] * ramp
    return np.vstack([a[:-n], mid, b[n:]])


def bell(freq: float, dur: float) -> np.ndarray:
    """Campana de timbre: parciales inarmónicos con caídas distintas y un ataque de 2 ms."""
    t = np.arange(int(dur * SR)) / SR
    partials = [(1.0, 1.0, 1.4), (2.0, 0.45, 0.9), (2.76, 0.28, 0.6), (5.4, 0.12, 0.25), (0.5, 0.18, 1.8)]
    y = sum(a * np.sin(2 * np.pi * freq * r * t) * np.exp(-t / tau) for r, a, tau in partials)
    y *= np.minimum(1, t / 0.002)
    k = int(0.1 * len(t))
    y[-k:] *= np.cos(np.linspace(0, np.pi / 2, k)) ** 2
    return y.astype(np.float32)


def main() -> None:
    b = read(SRC)
    out = splice(bars(b, 1, 7), bars(b, 10, 16))
    out = out[:int(28 * SR)]
    out = np.vstack([out, np.zeros((int(28 * SR) - len(out), 2), np.float32)])
    # Timbre en el silencio del break, un poco abierto en estéreo, con un eco corto de sala.
    for at, freq, gain in [(16.5, 659.25, 0.30), (17.0, 523.25, 0.30)]:
        tone = bell(freq, 2.4) * gain
        i = int(at * SR)
        n = min(len(tone), len(out) - i)
        out[i:i + n, 0] += tone[:n] * 0.92
        out[i:i + n, 1] += tone[:n]
        d = int(0.083 * SR)
        out[i + d:i + n, 0] += tone[:n - d] * 0.18
        out[i + d:i + n, 1] += tone[:n - d] * 0.14
    # Último medio segundo: fundido a cero.
    k = int(0.5 * SR)
    out[-k:] *= np.cos(np.linspace(0, np.pi / 2, k))[:, None] ** 2
    OUT.parent.mkdir(parents=True, exist_ok=True)
    tmp = OUT.with_suffix('.raw.wav')
    pcm = np.clip(out, -1, 1)
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'f32le', '-ar', str(SR), '-ac', '2', '-i', '-',
                    '-c:a', 'pcm_s24le', str(tmp)], input=pcm.tobytes(), check=True)
    # Dos pasadas de loudnorm lineal a −14 LUFS / −1,5 dBTP, como el anuncio.
    probe = subprocess.run(['ffmpeg', '-v', 'info', '-i', str(tmp), '-af', 'loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json',
                            '-f', 'null', '-'], capture_output=True, text=True).stderr
    import json
    m = json.loads(probe[probe.rindex('{'):probe.rindex('}') + 1])
    af = (f"loudnorm=I=-14:TP=-1.5:LRA=11:measured_I={m['input_i']}:measured_TP={m['input_tp']}:"
          f"measured_LRA={m['input_lra']}:measured_thresh={m['input_thresh']}:offset={m['target_offset']}:linear=true")
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(tmp), '-af', af, '-ar', str(SR), '-c:a', 'pcm_s24le', str(OUT)],
                   check=True)
    tmp.unlink()
    print(OUT, f'{len(out) / SR:.3f} s')


if __name__ == '__main__':
    main()
