#!/usr/bin/env python3
"""Música del teaser «Mira arriba» (8 compases = 16,000 s, 120 BPM), con el material de la B del anuncio.

Idea: la canción del anuncio suena en el piso de arriba. Empieza apagada (paso bajo muy cerrado, como a
través del techo) y se va abriendo a medida que el notch deja ver más. Se corta en seco en «Mira arriba»
y el nombre entra con el golpe final, ya sin filtro.

  1–2    latido grave (sub en los tiempos 1 y 3) y pad oscuro con reverb
  3–4    entra la canción a través del techo: batería y gancho con paso bajo 260 → 900 Hz
  5      se abre más (900 → 2800 Hz) y entra el bajo
  6      subida: se abre del todo (2800 → 12000 Hz), ruido y redoble
  7      tiempo 1–2: SILENCIO («Mira arriba»); tiempo 3 (13,000 s): golpe final sin filtro y cola
  8      la cola se apaga

Uso: python3 scripts/teaser-music.py  →  public/anuncio/audio/teaser-misterio.wav
"""
import importlib.util
import pathlib

import numpy as np

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('mv', HERE / 'anuncio-music-variants.py')
mv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mv)
mv.BARS = 8  # Mix, render y master leen el total de compases del módulo

BAR_N, BEAT_N = mv.BAR_N, mv.BEAT_N
idp = '08 Indie Disco'
L = lambda name, beats, pack=idp: mv.load(f'{pack}/{name}', beats, src_bpm=120)

drums = L('Duncan - Hit Factory', 32, '13 Drummer')
big = L('Duncan - Chorus', 32, '13 Drummer')
bass = L('Disco Pop Bass', 16)
rgtr = L('Disco Pop Rhythm Guitar', 16)
lead = L('Disco Pop Lead Guitar', 16)
pad = L('Disco Pop Synth Pad', 16)
fill = mv.bars_of(drums, 8, 1)

m = mv.Mix()


def through_ceiling(clip, f0, f1):
    return mv.lowpass_sweep(clip, f0, f1)


# 1–2 · latido y pad oscuro
for bar in (1, 2, 3, 4):
    for beat in (0, 0.5):
        m.place(mv.sub_boom(48, 0.9), bar + beat, None, -8 if bar < 3 else -11, 'fx', fade=0, label='latido')
dark = mv.lowpass(mv.bars_of(pad, 1, 2), 420)
m.place(dark, 1, 2, -6, label='pad oscuro')
m.place(mv.reverb(dark, 3.0)[: 2 * BAR_N], 1, 2, -12, 'fx', fade=0.3)
m.place(mv.reverse_swell(mv.beats_of(pad, 1, 1), 2), 2.5, None, -14, 'fx', fade=0)

# 3–4 · la canción a través del techo
song = mv.bars_of(drums, 1, 4) + mv.bars_of(lead, 1, 4) * 0.9 + mv.bars_of(rgtr, 1, 4) * 0.4
m.place(through_ceiling(song[: 2 * BAR_N], 260, 900), 3, 2, 0, label='canción apagada')
# 5 · se abre y entra el bajo
b5 = song[2 * BAR_N: 3 * BAR_N] + mv.bars_of(bass, 3, 1)
m.place(through_ceiling(b5, 900, 2800), 5, 1, 0, label='canción + bajo')
# 6 · subida
b6 = mv.bars_of(big, 1, 1) + mv.bars_of(lead, 4, 1) + mv.bars_of(bass, 4, 1) + mv.bars_of(pad, 4, 1) * 0.4
m.place(through_ceiling(b6, 2800, 12000), 6, 1, 0, label='se abre')
m.place(mv.noise_riser(1, 500, 12000, -12), 6, 1, 0, 'fx', label='riser')
m.place(fill[2 * BEAT_N:], 6.5, 0.5, 0, 'drums', label='redoble')

# 7 · silencio y golpe final en el tiempo 3
final = (mv.beats_of(big, 1, 1) + mv.beats_of(bass, 1, 1) + mv.beats_of(rgtr, 1, 1) * 0.5
         + mv.beats_of(pad, 1, 1) * 0.5 + mv.beats_of(lead, 1, 1) * 0.6)
final *= mv.env_decay(len(final), 0.2, 0.12)
m.place(final, 7.5, None, 0, 'fx', fade=0, label='golpe final')
m.place(mv.sub_boom(45, 2.5), 7.5, None, -8, 'fx', fade=0)
m.place(mv.reverb(final, 3.4), 7.5, None, -7, 'fx', fade=0, label='cola')
m.place(mv.bars_of(pad, 1, 1) * mv.env_decay(BAR_N, 0.8, 0.8), 7.5, None, -8, 'fx', fade=0.01, label='cola')
m.sidechain(5, 6, 0.25)

mix = (m.drums + m.music * m.duck[:, None] + m.fx)[: 8 * BAR_N]
# Silencio de verdad en los tiempos 1–2 del compás 7 (cola del redoble recortada con 20 ms de fundido).
a, b, r = 6 * BAR_N, 6 * BAR_N + 2 * BEAT_N, int(0.02 * mv.SR)
mix[a:a + r] *= np.linspace(1, 0, r)[:, None]
mix[a + r:b] = 0

out = mv.OUTDIR / 'teaser-misterio.wav'
print('loudnorm:', mv.master(mix, out, 'treble=g=3:f=7000,'))
res = mv.measure(out)
print(f"I={res['I']} LUFS  TP={res['TP']} dBTP  dur={res['dur']} s")
for i in range(8):
    print(i + 1, f"{res['bars'][i]:6.1f}", ' '.join(f'{v:6.1f}' for v in res['beats'][i * 4:(i + 1) * 4]))
