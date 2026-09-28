#!/usr/bin/env python3
"""Tres bandas sonoras alternativas para el anuncio (A: disco-funk, B: indie-pop, C: electro-pop).

Mismo enfoque que anuncio-music.py: Apple Loops (licencia de Apple: uso libre en composiciones propias)
colocados con numpy sobre una rejilla de compases a 120 BPM, y master en dos pasadas de loudnorm lineal.

Estructura fija (16 compases = 32,000 s, 4/4, 120 BPM; compás b empieza en (b-1)·2 s):
  1      intro ligera (riff principal filtrado, sin batería completa) que crece hacia…
  2      DROP en el primer tiempo
  2–10   sección principal con el gancho; relleno al final del compás 3 y del 7; capas cambian cada 4 compases
  11     BREAK: golpe en el tiempo 1, silencio desde el tiempo 2 («toc, toc»), relleno/aspiración al final
  12–14  vuelve todo (sección más grande); 14 = subida
  15     GOLPE FINAL en el primer tiempo y cola limpia hasta 32 s

Uso:  python3 scripts/anuncio-music-variants.py [a] [b] [c]      (sin argumentos: las tres)
Salida: public/anuncio/audio/score-{a,b,c}.wav (48 kHz, estéreo, 24 bits) + /tmp/score-{a,b,c}.png
"""
import json
import pathlib
import struct
import subprocess
import sys

import numpy as np
from scipy import signal

SR = 48000
BPM = 120
BEAT = 60 / BPM
BAR = 4 * BEAT
BARS = 16
BAR_N = int(BAR * SR)          # 96 000 muestras
BEAT_N = int(BEAT * SR)        # 24 000 muestras
LOOPS = pathlib.Path('/Library/Audio/Apple Loops/Apple')
ROOT = pathlib.Path(__file__).resolve().parents[1]
OUTDIR = ROOT / 'public/anuncio/audio'
RNG = np.random.default_rng(7)


# ─── Utilidades de material ──────────────────────────────────────────────────
def caf_pakt(path: pathlib.Path) -> tuple[int, int] | None:
    """(frames válidos, frames de «priming») del chunk 'pakt' de un CAF AAC.

    Los Apple Loops son AAC con 2112 muestras de retardo del codificador que ffmpeg NO recorta
    (initial_padding=0): sin esto, cada loop llega ~48 ms tarde y cada repetición deja un hueco de ~48 ms.
    """
    b = path.read_bytes()
    i = 8
    while i + 12 <= len(b):
        kind, size = b[i:i + 4], struct.unpack('>q', b[i + 4:i + 12])[0]
        if kind == b'pakt':
            _, valid, prime, _ = struct.unpack('>qqii', b[i + 12:i + 36])
            return valid, prime
        if size < 0:
            break
        i += 12 + size
    return None


def load(rel: str, beats: int, src_bpm: float | None = None, semitones: float = 0.0) -> np.ndarray:
    """Decodifica un loop a float32 estéreo 48 kHz, lo ajusta a 120 BPM y lo recorta a `beats` tiempos exactos.

    Primero quita el retardo AAC (chunk 'pakt'). Si se da `src_bpm`, el factor de atempo es 120/src_bpm
    (rubberband no está en este ffmpeg); si no, se deduce de la duración válida. `semitones` transpone sin
    cambiar la duración.
    """
    src = LOOPS / f'{rel}.caf'
    src_sr = int(subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'stream=sample_rate', '-of', 'csv=p=0', str(src)],
                                capture_output=True, text=True).stdout.strip())
    af = []
    pk = caf_pakt(src)
    if pk:
        valid, prime = pk
        af.append(f'atrim=start_sample={prime}:end_sample={prime + valid},asetpts=PTS-STARTPTS')
        dur = valid / src_sr
    else:
        dur = float(subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', str(src)],
                                   capture_output=True, text=True).stdout)
    tempo = BPM / src_bpm if src_bpm else dur / (beats * BEAT)
    af.append(f'aresample={SR}')
    if semitones:
        r = 2 ** (semitones / 12)
        af += [f'asetrate={SR * r:.3f}', f'aresample={SR}']
        tempo /= r
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(src), '-af', ','.join(af), '-ac', '2', '-f', 'f32le', '-'],
                         capture_output=True, check=True).stdout
    x = np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).copy()
    if abs(tempo - 1) > 1e-4:
        # atempo sobre el loop repetido 3 veces y nos quedamos con la vuelta central: sin bordes vacíos al repetir
        rep = np.tile(x, (3, 1))
        out = subprocess.run(['ffmpeg', '-v', 'error', '-f', 'f32le', '-ar', str(SR), '-ac', '2', '-i', '-',
                              '-af', f'atempo={tempo:.6f}', '-f', 'f32le', '-'], input=rep.tobytes(), capture_output=True, check=True).stdout
        y = np.frombuffer(out, dtype=np.float32).reshape(-1, 2)
        n1 = int(round(len(y) / 3))  # longitud real de una vuelta (atempo no es exacto al milisegundo)
        x = y[n1:2 * n1].copy()
    n = int(round(beats * BEAT * SR))
    if len(x) < n:
        x = np.vstack([x, np.zeros((n - len(x), 2), np.float32)])
    return x[:n]


def bars_of(clip: np.ndarray, first: float, count: float) -> np.ndarray:
    """Compases [first, first+count) del loop (1 = primero), con vuelta al principio si hace falta."""
    a = int((first - 1) * BAR_N)
    n = int(count * BAR_N)
    idx = (np.arange(a, a + n)) % len(clip)
    return clip[idx]


def beats_of(clip: np.ndarray, first_beat: float, count: float) -> np.ndarray:
    a = int((first_beat - 1) * BEAT_N)
    n = int(count * BEAT_N)
    return clip[(np.arange(a, a + n)) % len(clip)]


def env_decay(n: int, hold: float, tau: float) -> np.ndarray:
    """Mantiene `hold` s y cae exponencialmente con constante `tau` s (para golpes con cola)."""
    t = np.arange(n) / SR
    e = np.where(t < hold, 1.0, np.exp(-(t - hold) / tau))
    k = int(0.3 * n)  # termina siempre en cero (coseno en el último 30 %) → nunca hay corte audible
    e[n - k:] *= 0.5 * (1 + np.cos(np.linspace(0, np.pi, k)))
    return e[:, None].astype(np.float32)


def lowpass_sweep(clip: np.ndarray, f0: float, f1: float, block: int = 256) -> np.ndarray:
    """Paso bajo de 2 polos (Butterworth) cuya frecuencia sube exponencialmente de f0 a f1, por bloques."""
    out = np.empty_like(clip)
    zi = np.zeros((1, 2, 2))
    nblk = int(np.ceil(len(clip) / block))
    for i in range(nblk):
        f = f0 * (f1 / f0) ** (i / max(1, nblk - 1))
        sos = signal.butter(2, min(f, SR * 0.45), 'low', fs=SR, output='sos')
        seg = clip[i * block:(i + 1) * block]
        y, zi = signal.sosfilt(sos, seg, axis=0, zi=zi)
        out[i * block:(i + 1) * block] = y
    return out


def highpass(clip: np.ndarray, f: float) -> np.ndarray:
    return signal.sosfilt(signal.butter(2, f, 'high', fs=SR, output='sos'), clip, axis=0).astype(np.float32)


def lowpass(clip: np.ndarray, f: float) -> np.ndarray:
    return signal.sosfilt(signal.butter(2, f, 'low', fs=SR, output='sos'), clip, axis=0).astype(np.float32)


_IR: dict[float, np.ndarray] = {}


def reverb(clip: np.ndarray, rt60: float = 2.4) -> np.ndarray:
    """Reverb de sala sencilla: convolución con ruido estéreo que decae (RT60), oscurecido y sin graves."""
    if rt60 not in _IR:
        n = int(rt60 * 1.3 * SR)
        t = np.arange(n) / SR
        ir = RNG.standard_normal((n, 2)) * np.exp(-6.91 * t / rt60)[:, None]
        ir = lowpass(highpass(ir.astype(np.float32), 180), 5500)
        ir[: int(0.012 * SR)] = 0  # predelay
        _IR[rt60] = ir / np.sqrt((ir ** 2).sum(axis=0))
    ir = _IR[rt60]
    return np.stack([signal.fftconvolve(clip[:, c], ir[:, c]) for c in range(2)], axis=1).astype(np.float32)


def noise_riser(bars: float, f0=400, f1=9000, peak_db=-14) -> np.ndarray:
    """Ruido blanco que se abre y sube de volumen: subida clásica hacia un golpe."""
    n = int(bars * BAR_N)
    x = RNG.standard_normal((n, 2)).astype(np.float32) * 0.3
    x = highpass(lowpass_sweep(x, f0, f1), 250)
    ramp = (np.linspace(0, 1, n) ** 2.2)[:, None]
    x = x * ramp
    return x / (np.abs(x).max() + 1e-9) * 10 ** (peak_db / 20)


def reverse_swell(hit: np.ndarray, length_beats: float = 2) -> np.ndarray:
    """Cola de reverb de un golpe, invertida: «aspiración» que termina justo en el tiempo fuerte."""
    wet = reverb(hit)[: int(length_beats * BEAT_N)]
    rev = wet[::-1].copy()
    return rev / (np.abs(rev).max() + 1e-9)


def sub_boom(freq=50.0, dur=1.6) -> np.ndarray:
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = freq * (1 + 0.6 * np.exp(-t / 0.04))
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = np.sin(ph) * np.exp(-t / 0.35)
    x[: 96] *= np.linspace(0, 1, 96)
    return np.stack([x, x], axis=1).astype(np.float32)


def synth_bass(roots: list[str], octave: int = 2, pattern: str = 'offbeat') -> np.ndarray:
    """Bajo sintético limpio (sierra filtrada + sub seno) en corcheas; `roots` = una nota por medio compás."""
    names = 'C C# D D# E F F# G G# A A# B'.split()
    alias = {'Db': 'C#', 'Eb': 'D#', 'Gb': 'F#', 'Ab': 'G#', 'Bb': 'A#'}
    eighth = BEAT_N // 2
    out = np.zeros((len(roots) * 2 * BEAT_N, 2), np.float32)
    for h, r in enumerate(roots):
        midi = 12 * (octave + 1) + names.index(alias.get(r, r))
        f = 440 * 2 ** ((midi - 69) / 12)
        for k in range(4):  # 4 corcheas por medio compás
            if pattern == 'offbeat' and k % 2 == 0:
                continue
            n = int(eighth * 0.92)
            t = np.arange(n) / SR
            saw = 2 * ((t * f) % 1) - 1
            sub = np.sin(2 * np.pi * f * t)
            tone = 0.45 * saw + 0.9 * sub
            env = np.minimum(1, t / 0.004) * np.exp(-t / 0.22)
            env[-240:] *= np.linspace(1, 0, 240)
            s = (tone * env).astype(np.float32)
            a = h * 2 * BEAT_N + k * eighth
            out[a:a + n] += s[:, None]
    return lowpass(out, 900)


# ─── Mezclador ───────────────────────────────────────────────────────────────
class Mix:
    def __init__(self):
        self.drums = np.zeros((BARS * BAR_N + SR * 4, 2), np.float32)
        self.music = np.zeros_like(self.drums)   # va bajo el «sidechain»
        self.fx = np.zeros_like(self.drums)
        self.duck = np.ones(len(self.drums), np.float32)
        self.layers: dict[int, set] = {b: set() for b in range(1, BARS + 1)}

    def place(self, clip: np.ndarray, bar: float, bars: float | None = None, gain_db: float = 0.0,
              bus: str = 'music', fade: float = 0.004, label: str | None = None):
        """Coloca `clip` en el compás `bar` (1 = inicio), repitiéndolo durante `bars` compases."""
        start = int(round((bar - 1) * BAR_N))
        length = int(round(bars * BAR_N)) if bars else len(clip)
        reps = int(np.ceil(length / len(clip)))
        seg = np.tile(clip, (reps, 1))[:length].copy()
        n = int(fade * SR)
        if n and len(seg) > 2 * n:
            ramp = np.linspace(0, 1, n)[:, None]
            seg[:n] *= ramp
            seg[-n:] *= ramp[::-1]
        dst = getattr(self, bus)
        end = min(len(dst), start + len(seg))
        if start < 0:
            seg, start = seg[-start:], 0
        dst[start:end] += seg[: end - start] * (10 ** (gain_db / 20))
        if label:
            for b in range(int(np.floor(bar)), int(np.ceil(bar + length / BAR_N - 1e-6))):
                if 1 <= b <= BARS:
                    self.layers[b].add(label)

    def sidechain(self, first_bar: int, last_bar: int, depth: float, release: float = 0.11):
        """Bombeo tipo sidechain: la ganancia del bus `music` cae `depth` en cada negra y se recupera."""
        a = (first_bar - 1) * BAR_N
        n = (last_bar - first_bar + 1) * BAR_N
        t = (np.arange(n) % BEAT_N) / SR
        att = np.minimum(1, t / 0.003)
        g = 1 - depth * att * np.exp(-t / release)
        g = np.where(t < 0.003, 1 - depth * t / 0.003, g)
        self.duck[a:a + n] = np.minimum(self.duck[a:a + n], g.astype(np.float32))

    def render(self, lift_db: float = 1.5) -> np.ndarray:
        mix = self.drums + self.music * self.duck[:, None] + self.fx
        # 12–14 es la sección más grande: +lift_db con rampas cortas (no afecta al golpe del 15)
        g = np.ones(len(mix), np.float32)
        a, b, r = 11 * BAR_N, 14 * BAR_N, int(0.02 * SR)
        g[a:b] = 10 ** (lift_db / 20)
        g[b:b + r] = np.linspace(10 ** (lift_db / 20), 1, r)
        return (mix * g[:, None])[: BARS * BAR_N]


# ─── Variante A — disco-funk pop (09 Disco Funk, kit «Disco Delight», Si mixolidio) ──────────────
def variant_a() -> tuple[Mix, list]:
    df = '09 Disco Funk'
    used = []

    def L(name, beats, pack=df, **kw):
        used.append((name, pack, kw))
        return load(f'{pack}/{name}', beats, **kw)

    drums = L('Glitter Nights Beat', 16, src_bpm=120)
    hats = L('Glitter Nights Hi-Hat Topper', 16, src_bpm=120)
    funk = L('Throwback Funk Beat 04', 8, src_bpm=120)
    bass = L('Disco Delight Bass', 8, src_bpm=120)
    slap = L('Disco Delight Slap Bass', 8, src_bpm=120)
    rgtr = L('Disco Delight Rhythm Guitar', 16, src_bpm=120)
    lead = L('Disco Delight Lead Guitar', 8, src_bpm=120)           # el gancho
    clav = L('Disco Delight Clav', 8, src_bpm=120)
    piano = L('Disco Delight Piano', 16, src_bpm=120)
    brass = L('Throwback Funk Brass 01', 8, src_bpm=120, semitones=2)  # La7 → Si7
    riser = L('80s Synth FX Riser 01', 8, src_bpm=120)
    fill1 = L('Snare Drum Fill 01', 4, pack='10 Vintage Breaks')
    fill3 = L('Snare Drum Fill 03', 4, pack='10 Vintage Breaks')

    m = Mix()
    stab = beats_of(brass, 1, 1) * env_decay(BEAT_N, 0.18, 0.08)       # Si7 de metales, un tiempo
    half = 2 * BEAT_N

    # 1 · intro: gancho filtrado que se abre + charles; aspiración inversa hacia el drop
    m.place(lowpass_sweep(bars_of(lead, 1, 1), 300, 6000), 1, 1, -2, label='gancho filtrado')
    m.place(bars_of(hats, 1, 1), 1, 1, -3, 'drums', label='charles')
    m.place(riser[-BAR_N:], 1, 1, -12, 'fx', label='riser')
    m.place(reverse_swell(stab + beats_of(piano, 1, 1)), 1.5, None, -10, 'fx', fade=0)

    # 2–5 · DROP: batería disco, bajo, guitarra rítmica, gancho (lead) + metales en el 1
    m.place(bars_of(drums, 1, 4), 2, 4, 0, 'drums', label='batería')
    m.place(bass, 2, 4, -1, label='bajo')
    m.place(rgtr, 2, 4, -6, label='guitarra rítmica')
    m.place(lead, 2, 4, 0, label='gancho')
    m.place(stab, 2, None, -3, 'fx', fade=0, label='metales')
    m.place(sub_boom(), 2, None, -10, 'fx', fade=0)
    m.place(fill1[half:], 3.5, 0.5, -3, 'drums', label='relleno')            # cámara entra en la pantalla

    # 6–9 · capa nueva: clavinet + piano (fuera guitarra rítmica), charles extra
    m.place(bars_of(drums, 1, 4), 6, 4, 0, 'drums', label='batería')
    m.place(bars_of(hats, 1, 4), 6, 4, -8, 'drums', label='charles')
    m.place(bass, 6, 4, -1, label='bajo')
    m.place(clav, 6, 4, -8, label='clavinet')
    m.place(piano, 6, 4, -7, label='piano')
    m.place(lead, 6, 4, 0, label='gancho')
    m.place(fill3[half:], 7.5, 0.5, -3, 'drums', label='relleno')

    # 10 · capa de batería funk encima, vuelve la guitarra rítmica
    m.place(bars_of(drums, 1, 1), 10, 1, 0, 'drums', label='batería')
    m.place(bars_of(hats, 1, 1), 10, 1, -6, 'drums', label='charles')
    m.place(bars_of(funk, 1, 1), 10, 1, -5, 'drums', label='batería funk')
    m.place(bars_of(bass, 1, 1), 10, 1, -1, label='bajo')
    m.place(bars_of(rgtr, 1, 1), 10, 1, -6, label='guitarra rítmica')
    m.place(bars_of(lead, 1, 1), 10, 1, 0, label='gancho')

    # 11 · BREAK: golpe en el 1 y silencio desde el 2; relleno + aspiración en el 4
    hit = np.vstack([beats_of(drums, 1, 1) + beats_of(bass, 1, 1) * 0.9 + stab * 0.8])
    hit *= env_decay(len(hit), 0.15, 0.06)
    m.place(hit, 11, None, -1, 'fx', fade=0, label='golpe')
    m.place(reverb(stab) , 11, None, -14, 'fx', fade=0, label='cola reverb')
    m.place(fill1[3 * BEAT_N:], 11.75, 0.25, -2, 'drums', label='relleno')
    m.place(reverse_swell(stab, 1), 11.75, None, -12, 'fx', fade=0)

    # 12–14 · lo más grande: slap bass, guitarra, piano, gancho, metales en cada compás
    m.place(bars_of(drums, 1, 3), 12, 3, 0, 'drums', label='batería')
    m.place(bars_of(hats, 1, 3), 12, 3, -8, 'drums', label='charles')
    m.place(slap, 12, 3, -2, label='slap bass')
    m.place(bars_of(rgtr, 1, 3), 12, 3, -6, label='guitarra rítmica')
    m.place(bars_of(piano, 1, 3), 12, 3, -8, label='piano')
    m.place(lead, 12, 3, 0, label='gancho')
    for b in (12, 13):
        m.place(stab, b, None, -4, 'fx', fade=0, label='metales')
    m.place(sub_boom(), 12, None, -10, 'fx', fade=0)
    # 14 · subida
    m.place(riser, 13, 2, -10, 'fx', label='riser')
    m.place(noise_riser(1), 14, 1, -6, 'fx', label='riser ruido')
    m.place(fill3[half:], 14.5, 0.5, -1, 'drums', label='relleno')

    # 15 · GOLPE FINAL (Si7): batería, bajo, piano, guitarra, metales en el 1 + cola
    final = (beats_of(drums, 1, 1) + beats_of(bass, 1, 1) + beats_of(rgtr, 1, 1) * 0.5
             + beats_of(piano, 1, 1) * 0.5 + stab)
    final *= env_decay(len(final), 0.2, 0.12)
    m.place(final, 15, None, 0, 'fx', fade=0, label='golpe final')
    m.place(sub_boom(45, 2.5), 15, None, -8, 'fx', fade=0)
    m.place(reverb(final, 3.4), 15, None, -6, 'fx', fade=0, label='cola')
    ring = reverb(beats_of(piano, 1, 2) * env_decay(2 * BEAT_N, 0.5, 0.6), 3.4)[: 3 * BAR_N // 2]
    ring *= env_decay(len(ring), 0.8, 1.2)
    m.place(ring, 15, None, -8, 'fx', fade=0.01, label='cola')

    m.sidechain(2, 10, 0.25)
    m.sidechain(12, 14, 0.25)
    return m, used


# ─── Variante B — indie-pop (08 Indie Disco «Disco Pop» en Re♭ + batería Drummer «Duncan») ──────
def variant_b() -> tuple[Mix, list]:
    idp = '08 Indie Disco'
    used = []

    def L(name, beats, pack=idp, **kw):
        used.append((name, pack, kw))
        return load(f'{pack}/{name}', beats, **kw)

    dr_main = L('Duncan - Hit Factory', 32, pack='13 Drummer', src_bpm=120)
    dr_big = L('Duncan - Chorus', 32, pack='13 Drummer', src_bpm=120)
    dr_intro = L('Duncan - Intro', 32, pack='13 Drummer', src_bpm=120)
    tamb = L('Tambourine 03', 8, pack='Apple Loops for GarageBand', src_bpm=120)
    bass = L('Disco Pop Bass', 16, src_bpm=120)
    rgtr = L('Disco Pop Rhythm Guitar', 16, src_bpm=120)
    lead = L('Disco Pop Lead Guitar', 16, src_bpm=120)                 # el gancho
    pad = L('Disco Pop Synth Pad', 16, src_bpm=120)
    stabs = L('Disco Pop Synth Stabs', 16, src_bpm=120)
    fill = bars_of(dr_main, 8, 1)                                        # compás 8 de Hit Factory = redoble

    m = Mix()
    half = 2 * BEAT_N

    # 1 · intro: gancho filtrado + batería de «intro» (sin bombo) + aspiración
    m.place(lowpass_sweep(bars_of(lead, 1, 1), 300, 6500), 1, 1, -2, label='gancho filtrado')
    m.place(bars_of(dr_intro, 1, 1), 1, 1, -3, 'drums', label='caja/charles intro')
    m.place(noise_riser(0.5, 800, 9000, -16), 1.5, 0.5, 0, 'fx', label='riser')
    m.place(reverse_swell(beats_of(pad, 1, 1)), 1.5, None, -10, 'fx', fade=0)

    # 2–5 · DROP: batería, bajo, guitarra rítmica, gancho
    m.place(bars_of(dr_main, 1, 4), 2, 4, 0, 'drums', label='batería')
    m.place(bass, 2, 4, -1, label='bajo')
    m.place(rgtr, 2, 4, -6, label='guitarra rítmica')
    m.place(lead, 2, 4, -1, label='gancho')
    m.place(sub_boom(), 2, None, -12, 'fx', fade=0)
    m.place(fill[half:], 3.5, 0.5, 0, 'drums', label='relleno')

    # 6–9 · nueva capa: pad + stabs + pandereta (fuera guitarra rítmica)
    m.place(bars_of(dr_main, 5, 4), 6, 4, 0, 'drums', label='batería')
    m.place(tamb, 6, 4, -6, 'drums', label='pandereta')
    m.place(bass, 6, 4, -1, label='bajo')
    m.place(lead, 6, 4, -1, label='gancho')
    m.place(pad, 6, 4, -10, label='pad')
    m.place(stabs, 6, 4, -8, label='stabs')
    m.place(fill[half:], 7.5, 0.5, 0, 'drums', label='relleno')

    # 10 · guitarra rítmica de vuelta
    m.place(bars_of(dr_main, 2, 1), 10, 1, 0, 'drums', label='batería')
    m.place(bars_of(bass, 1, 1), 10, 1, -1, label='bajo')
    m.place(bars_of(rgtr, 1, 1), 10, 1, -6, label='guitarra rítmica')
    m.place(bars_of(lead, 1, 1), 10, 1, -1, label='gancho')

    # 11 · BREAK: acorde en el 1, silencio, redoble en el 4
    hit = (beats_of(dr_main, 1, 1) + beats_of(bass, 5, 1) + beats_of(stabs, 5, 1) + beats_of(pad, 5, 1) * 0.5)
    hit *= env_decay(len(hit), 0.15, 0.06)
    m.place(hit, 11, None, -1, 'fx', fade=0, label='golpe')
    m.place(reverb(beats_of(stabs, 5, 1)), 11, None, -12, 'fx', fade=0, label='cola reverb')
    m.place(fill[3 * BEAT_N:], 11.75, 0.25, 0, 'drums', label='relleno')
    m.place(reverse_swell(beats_of(pad, 1, 1), 1), 11.75, None, -12, 'fx', fade=0)

    # 12–14 · estribillo: batería «Chorus», pandereta, bajo, guitarra, pad, gancho
    m.place(bars_of(dr_big, 1, 3), 12, 3, 0, 'drums', label='batería grande')
    m.place(bars_of(tamb, 1, 3), 12, 3, -6, 'drums', label='pandereta')
    m.place(bars_of(bass, 1, 3), 12, 3, -1, label='bajo')
    m.place(bars_of(rgtr, 1, 3), 12, 3, -7, label='guitarra rítmica')
    m.place(bars_of(pad, 1, 3), 12, 3, -11, label='pad')
    m.place(bars_of(lead, 1, 3), 12, 3, -1, label='gancho')
    m.place(sub_boom(), 12, None, -12, 'fx', fade=0)
    # 14 · subida: ruido + redoble de la batería
    m.place(noise_riser(1), 14, 1, -6, 'fx', label='riser ruido')
    m.place(fill[half:], 14.5, 0.5, 1, 'drums', label='relleno')

    # 15 · GOLPE FINAL (Re♭): todo en el 1 + pad que se apaga
    final = (beats_of(dr_big, 1, 1) + beats_of(bass, 1, 1) + beats_of(rgtr, 1, 1) * 0.5
             + beats_of(pad, 1, 1) * 0.5 + beats_of(lead, 1, 1) * 0.6)
    final *= env_decay(len(final), 0.2, 0.12)
    m.place(final, 15, None, 0, 'fx', fade=0, label='golpe final')
    m.place(sub_boom(45, 2.5), 15, None, -9, 'fx', fade=0)
    m.place(reverb(final, 3.4), 15, None, -7, 'fx', fade=0, label='cola')
    ring = bars_of(pad, 1, 1) * env_decay(BAR_N, 0.6, 0.9)                 # compás 1 del pad = Re♭
    m.place(ring, 15, None, -7, 'fx', fade=0.01, label='cola')

    m.sidechain(2, 10, 0.3)
    m.sidechain(12, 14, 0.3)
    return m, used


# ─── Variante C — electro-pop (02 Electro House a 120 + batería Drummer «Julian», Do menor / Mi♭) ──
def variant_c() -> tuple[Mix, list]:
    eh = '02 Electro House'
    used = []

    def L(name, beats, pack=eh, **kw):
        used.append((name, pack, kw))
        return load(f'{pack}/{name}', beats, **kw)

    dr_main = L('Julian - Star Burst', 32, pack='13 Drummer', src_bpm=120)
    dr_big = L('Julian - Chorus', 32, pack='13 Drummer', src_bpm=120)
    chords = L('Bedlam Synth Layers', 16, src_bpm=128)      # La♭ | La♭–Si♭ | Do m | Do m–Si♭
    hook = L('Night Vision Synth Layers', 16, src_bpm=128)  # el gancho
    vox = L('Airy Vox Synth', 16, src_bpm=128)
    clap = L('House Clap Topper', 8, src_bpm=128)
    revtop = L('Almost Reverse Topper', 8, src_bpm=128)
    roll = bars_of(dr_big, 8, 1)                               # compás 8 de «Chorus» = redoble creciente
    bass = synth_bass(['Ab', 'Ab', 'Ab', 'Bb', 'C', 'C', 'C', 'Bb'])  # 4 compases, sigue a Bedlam
    used.append(('bajo sintetizado (numpy)', '—', {}))

    m = Mix()
    half = 2 * BEAT_N

    # 1 · intro: acordes + gancho filtrados, sin batería; aspiración inversa en la 2.ª mitad
    m.place(lowpass_sweep(bars_of(chords, 1, 1), 250, 5000), 1, 1, -3, label='acordes filtrados')
    m.place(lowpass_sweep(bars_of(hook, 1, 1), 300, 7000), 1, 1, -4, label='gancho filtrado')
    m.place(revtop[-half:], 1.5, 0.5, -4, 'fx', label='reverse')
    m.place(noise_riser(0.5, 800, 10000, -16), 1.5, 0.5, 0, 'fx')

    # 2–5 · DROP: batería 4×4, bajo, acordes, gancho
    m.place(bars_of(dr_main, 1, 4), 2, 4, -4, 'drums', label='batería')
    m.place(bass, 2, 4, -8, label='bajo')
    m.place(chords, 2, 4, -4, label='acordes')
    m.place(hook, 2, 4, -1, label='gancho')
    m.place(sub_boom(), 2, None, -10, 'fx', fade=0)
    m.place(roll[half:], 3.5, 0.5, -2, 'drums', label='relleno')

    # 6–9 · nueva capa: voz sintética + palmas
    m.place(bars_of(dr_main, 5, 4), 6, 4, -4, 'drums', label='batería')
    m.place(clap, 6, 4, -8, 'drums', label='palmas')
    m.place(bass, 6, 4, -8, label='bajo')
    m.place(chords, 6, 4, -5, label='acordes')
    m.place(hook, 6, 4, -1, label='gancho')
    m.place(vox, 6, 4, -6, label='voz synth')
    m.place(roll[half:], 7.5, 0.5, -2, 'drums', label='relleno')

    # 10
    m.place(bars_of(dr_main, 2, 1), 10, 1, -4, 'drums', label='batería')
    m.place(bars_of(bass, 1, 1), 10, 1, -8, label='bajo')
    m.place(bars_of(chords, 1, 1), 10, 1, -4, label='acordes')
    m.place(bars_of(hook, 1, 1), 10, 1, -1, label='gancho')

    # 11 · BREAK
    hitsrc = beats_of(chords, 5, 1) + beats_of(bass, 5, 1) + beats_of(dr_main, 1, 1)
    hit = hitsrc * env_decay(BEAT_N, 0.15, 0.06)
    m.place(hit, 11, None, -1, 'fx', fade=0, label='golpe')
    m.place(reverb(beats_of(chords, 5, 1)), 11, None, -11, 'fx', fade=0, label='cola reverb')
    m.place(roll[3 * BEAT_N:], 11.75, 0.25, -1, 'drums', label='relleno')
    m.place(revtop[-BEAT_N:], 11.75, 0.25, -4, 'fx')

    # 12–14 · lo más grande: batería «Chorus», palmas, bajo, acordes, gancho, voz
    m.place(bars_of(dr_big, 1, 3), 12, 3, -4, 'drums', label='batería grande')
    m.place(bars_of(clap, 1, 3), 12, 3, -8, 'drums', label='palmas')
    m.place(bars_of(bass, 1, 3), 12, 3, -8, label='bajo')
    m.place(bars_of(chords, 1, 3), 12, 3, -5, label='acordes')
    m.place(bars_of(hook, 1, 3), 12, 3, -1, label='gancho')
    m.place(bars_of(vox, 1, 3), 12, 3, -7, label='voz synth')
    m.place(sub_boom(), 12, None, -10, 'fx', fade=0)
    # 14 · subida: redoble + ruido
    m.place(noise_riser(1), 14, 1, -6, 'fx', label='riser ruido')
    m.place(roll[half:], 14.5, 0.5, 0, 'drums', label='relleno')

    # 15 · GOLPE FINAL (La♭): todo en el 1 + acorde que se apaga
    final = beats_of(dr_big, 1, 1) + beats_of(bass, 1, 1) * 1.2 + beats_of(chords, 1, 1) * 0.6 + beats_of(hook, 1, 1) * 0.6
    final *= env_decay(len(final), 0.2, 0.12)
    m.place(final, 15, None, 0, 'fx', fade=0, label='golpe final')
    m.place(sub_boom(45, 2.5), 15, None, -8, 'fx', fade=0)
    m.place(reverb(final, 3.4), 15, None, -7, 'fx', fade=0, label='cola')
    ring = bars_of(chords, 1, 1.5) * env_decay(int(1.5 * BAR_N), 0.6, 0.9)   # 1,5 compases = La♭
    m.place(lowpass(ring, 4000), 15, None, -8, 'fx', fade=0.01, label='cola')

    m.sidechain(2, 10, 0.45)
    m.sidechain(12, 14, 0.45)
    return m, used


# ─── Master y medidas ────────────────────────────────────────────────────────
def master(mix: np.ndarray, out: pathlib.Path, eq: str = ''):
    # cola limpia: fundido del último segundo (el golpe ya decae por sí solo)
    tail = int(1.0 * SR)
    mix = mix.copy()
    mix[-tail:] *= (np.linspace(1, 0, tail) ** 2)[:, None]
    raw = out.with_suffix('.raw.wav')
    pcm = (mix * 0.5).astype(np.float32)
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'f32le', '-ar', str(SR), '-ac', '2', '-i', '-', '-c:a', 'pcm_f32le', str(raw)],
                   input=pcm.tobytes(), check=True)
    # Techo del limitador ajustado en bucle hasta que, tras la ganancia lineal de loudnorm (−14 LUFS),
    # el pico real medido en el WAV final quede ≤ −1,5 dBTP (si no, loudnorm cae a modo dinámico y bombea).
    ceiling = 0.5
    for _ in range(8):
        pre = (f'highpass=f=30,{eq}acompressor=threshold=-18dB:ratio=2.5:attack=10:release=120,'
               f'alimiter=limit={ceiling:.4f}:attack=3:release=60:level=false')
        meas = subprocess.run(['ffmpeg', '-v', 'info', '-i', str(raw), '-af', pre + ',loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json',
                               '-f', 'null', '-'], capture_output=True, text=True).stderr
        mm = json.loads(meas[meas.rindex('{'):meas.rindex('}') + 1])
        ln = (f"loudnorm=I=-14:TP=-1.5:LRA=11:measured_I={mm['input_i']}:measured_TP={mm['input_tp']}:"
              f"measured_LRA={mm['input_lra']}:measured_thresh={mm['input_thresh']}:offset={mm['target_offset']}:linear=true")
        res = subprocess.run(['ffmpeg', '-v', 'info', '-y', '-i', str(raw), '-af', pre + ',' + ln + ':print_format=json',
                              '-ar', str(SR), '-t', f'{BARS * BAR:.3f}', '-c:a', 'pcm_s24le', str(out)], capture_output=True, text=True).stderr
        r = json.loads(res[res.rindex('{'):res.rindex('}') + 1])
        tp = measure_tp(out)
        if tp <= -1.6 and r.get('normalization_type') == 'linear':
            break
        ceiling = max(0.05, ceiling * 10 ** ((-1.9 - max(tp, -1.0)) / 20))
    raw.unlink()
    return r.get('normalization_type')


def measure_tp(path: pathlib.Path) -> float:
    ebu = subprocess.run(['ffmpeg', '-v', 'info', '-nostats', '-i', str(path), '-af', 'ebur128=peak=true', '-f', 'null', '-'],
                         capture_output=True, text=True).stderr
    summ = ebu[ebu.rindex('True peak'):]
    return float([l for l in summ.splitlines() if l.strip().startswith('Peak:')][0].split(':')[1].split()[0])


def measure(path: pathlib.Path) -> dict:
    ebu = subprocess.run(['ffmpeg', '-v', 'info', '-nostats', '-i', str(path), '-af', 'ebur128=peak=true', '-f', 'null', '-'],
                         capture_output=True, text=True).stderr
    summ = ebu[ebu.rindex('Summary:'):]
    def grab(key, after=None):
        s = summ if after is None else summ[summ.index(after):]
        line = [l for l in s.splitlines() if l.strip().startswith(key)][0]
        return float(line.split(':')[1].split()[0])
    st = json.loads(subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'stream=duration,sample_rate,channels,bits_per_raw_sample',
                                    '-of', 'json', str(path)], capture_output=True, text=True).stdout)['streams'][0]
    dur = float(st['duration'])
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(path), '-f', 'f32le', '-ac', '2', '-'], capture_output=True).stdout
    x = np.frombuffer(raw, np.float32).reshape(-1, 2)
    mono = x.mean(axis=1)
    bars = [20 * np.log10(np.sqrt((mono[b * BAR_N:(b + 1) * BAR_N] ** 2).mean()) + 1e-9) for b in range(BARS)]
    beats = [20 * np.log10(np.sqrt((mono[i * BEAT_N:(i + 1) * BEAT_N] ** 2).mean()) + 1e-9) for i in range(BARS * 4)]
    # huecos: ventanas de 100 ms por debajo de -50 dBFS fuera del break (compás 11) y la cola (15–16)
    w = SR // 10
    win = [20 * np.log10(np.sqrt((mono[i:i + w] ** 2).mean()) + 1e-9) for i in range(0, len(mono) - w + 1, w)]
    gaps = [i * 0.1 for i, v in enumerate(win) if v < -50 and not (20.0 <= i * 0.1 < 22.0) and i * 0.1 < 28.0]
    clip = int((np.abs(x) >= 0.999).sum())
    return dict(fmt=f"{st['sample_rate']} Hz, {st['channels']} ch, {st.get('bits_per_raw_sample')} bit", I=grab('I:'), LRA=grab('LRA:'), TP=grab('Peak:', 'True peak'), dur=dur, samples=len(x), bars=bars,
                beats=beats, gaps=gaps, clip=clip, peak=20 * np.log10(np.abs(x).max()))


def png(path: pathlib.Path, dst: pathlib.Path, title: str):
    from PIL import Image, ImageDraw
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(path), '-f', 'f32le', '-ac', '1', '-'], capture_output=True).stdout
    x = np.frombuffer(raw, np.float32)
    W, H = 1600, 360
    img = Image.new('RGB', (W, H + 30), (250, 248, 244))
    d = ImageDraw.Draw(img)
    per = len(x) // W
    for i in range(W):
        s = x[i * per:(i + 1) * per]
        top, bot = s.max(), s.min()
        rms = np.sqrt((s ** 2).mean())
        d.line([(i, H / 2 - top * H / 2), (i, H / 2 - bot * H / 2)], fill=(150, 160, 190))
        d.line([(i, H / 2 - rms * H / 2), (i, H / 2 + rms * H / 2)], fill=(40, 60, 120))
    for b in range(BARS + 1):
        X = int(b * W / BARS)
        col = (220, 60, 60) if b in (1, 10, 11, 14) else (190, 190, 190)
        d.line([(X, 0), (X, H)], fill=col)
        if b < BARS:
            d.text((X + 4, H + 8), str(b + 1), fill=(60, 60, 60))
    d.text((8, 6), title, fill=(20, 20, 20))
    img.save(dst)


# Ecualización de master por variante (medida con el balance espectral de las mezclas).
EQ = {'a': '', 'b': 'treble=g=3:f=7000,', 'c': 'bass=g=-4:f=60,treble=g=2:f=7000,'}

VARIANTS = {'a': ('Disco-funk pop', variant_a), 'b': ('Indie-pop band', variant_b), 'c': ('Electro-pop', variant_c)}

if __name__ == '__main__':
    which = [a.lower() for a in sys.argv[1:]] or list(VARIANTS)
    OUTDIR.mkdir(parents=True, exist_ok=True)
    summary = {}
    for v in which:
        title, fn = VARIANTS[v]
        m, used = fn()
        out = OUTDIR / f'score-{v}.wav'
        norm = master(m.render(), out, EQ[v])
        r = measure(out)
        png(out, pathlib.Path(f'/tmp/score-{v}.png'), f'score-{v} - {title}  (I={r["I"]} LUFS, TP={r["TP"]} dBTP)')
        r['normalization'] = norm
        r['layers'] = {b: sorted(s) for b, s in m.layers.items()}
        r['used'] = [(n, p, {k: v2 for k, v2 in kw.items()}) for n, p, kw in used]
        summary[v] = r
        print(f'\n=== score-{v}.wav — {title} ===')
        print(f"I={r['I']} LUFS  TP={r['TP']} dBTP  LRA={r['LRA']} LU  dur={r['dur']} s  ({r['fmt']})  samples={r['samples']}  "
              f"sample-peak={r['peak']:.2f} dBFS  clipped={r['clip']}  loudnorm={norm}")
        print('bar  dBFS RMS   beats(1-4)               capas')
        for b in range(BARS):
            bt = ' '.join(f'{v3:6.1f}' for v3 in r['beats'][b * 4:(b + 1) * 4])
            print(f'{b + 1:3d}  {r["bars"][b]:6.1f}   {bt}   {", ".join(r["layers"][b + 1])}')
        print('huecos (<-50 dBFS, fuera del break/cola):', r['gaps'] or 'ninguno')
    pathlib.Path('/tmp/score-variants.json').write_text(json.dumps(summary, indent=1, ensure_ascii=False, default=str))
