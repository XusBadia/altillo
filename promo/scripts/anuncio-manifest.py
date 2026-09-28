#!/usr/bin/env python3
"""Mide el contorno opaco de cada estado exportado (en puntos, @3x) y escribe src/anuncio/ui-manifest.ts."""
import json, pathlib
from PIL import Image

root = pathlib.Path(__file__).resolve().parents[1]
ui = root / 'public/anuncio/ui'
out = {}
for lang_dir in sorted(p for p in ui.iterdir() if p.is_dir()):
    for png in sorted(lang_dir.glob('*.png')):
        im = Image.open(png).convert('RGBA')
        alpha = im.getchannel('A').point(lambda a: 255 if a > 40 else 0)
        box = alpha.getbbox() or (0, 0, 0, 0)
        out.setdefault(png.stem, {})[lang_dir.name] = [round(v / 3, 1) for v in box]
src = 'export const UI_BOXES: Record<string, Record<string, [number, number, number, number]>> = ' + json.dumps(out, indent=1) + ';\n'
(root / 'src/anuncio/ui-manifest.ts').write_text('// Generado por scripts/anuncio-manifest.py: caja opaca [x0, y0, x1, y1] en puntos.\n' + src)
print(json.dumps({k: v.get('es') for k, v in out.items()}, indent=0))
