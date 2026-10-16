// Analytic smoothness check of the Casa camera and pointer (promo/CASA.md), frame by frame at 60 fps:
// the screen point under the frame centre, the zoom, and the pointer on screen; velocity, acceleration and jerk.
// A continuous quintic move has no velocity jumps; a hard cut or a kick would show as a spike.
// Usage: node scripts/casa-camera-check.mjs [wide|vertical]
import {build} from 'esbuild';
import {mkdtempSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

const format = process.argv[2] ?? 'wide';
const out = join(mkdtempSync(join(tmpdir(), 'casa-')), 'casa.mjs');
await build({entryPoints: ['src/casa/Casa.tsx'], bundle: true, platform: 'node', format: 'esm', outfile: out, logLevel: 'error',
  jsx: 'automatic', loader: {'.png': 'empty'}});
const {casaCamera, casaPointer, CASA_FRAMES} = await import(out);
const W = format === 'vertical' ? 1080 : 1920;
const H = format === 'vertical' ? 1920 : 1080;
const rows = [];
for (let f = 0; f < CASA_FRAMES; f++) {
  const c = casaCamera(f, format);
  const p = casaPointer(f);
  // Where three fixed screen points (notch centre, and 300 pt to either side lower down) land in the frame,
  // and where the pointer lands.
  const at = (x, y) => [W / 2 + (x - c.fx) * c.scale, c.top + y * c.scale];
  const [ax, ay] = at(756, 140), [bx, by] = at(456, 0), [qx, qy] = at(1056, 400);
  rows.push({f, ax, ay, bx, by, qx, qy, z: Math.log(c.scale), px: W / 2 + (p.x - c.fx) * c.scale, py: c.top + p.y * c.scale});
}
const d = (a, k) => a.slice(1).map((r, i) => r[k] - a[i][k]);
const stats = (name, k, unit) => {
  const v = d(rows, k);
  const a = v.slice(1).map((x, i) => x - v[i]);
  const j = a.slice(1).map((x, i) => x - a[i]);
  const max = (arr) => arr.reduce((m, x, i) => (Math.abs(x) > m[0] ? [Math.abs(x), i] : m), [0, 0]);
  const [mv, iv] = max(v), [ma, ia] = max(a), [mj, ij] = max(j);
  console.log(`${name.padEnd(16)} max speed ${mv.toFixed(2)} ${unit}/f @${iv + 1}   max accel ${ma.toFixed(3)} @${ia + 2}   max jerk ${mj.toFixed(3)} @${ij + 3}`);
};
console.log(`Casa ${format}: ${CASA_FRAMES} frames`);
// Pointer hops: peak on-screen speed of each move between keys.
{
  let fast = [];
  for (let f = 1; f < CASA_FRAMES; f++) {
    const s = Math.hypot(rows[f].px - rows[f - 1].px, rows[f].py - rows[f - 1].py);
    if (s > 40 && f > 120 && f < 1440) fast.push(`${f}:${s.toFixed(0)}`);
  }
  console.log('pointer frames over 40 px/f:', fast.length ? fast.join(' ') : 'none');
}
for (const k of ['ax', 'ay', 'bx', 'by', 'qx', 'qy']) stats(`camera ${k}`, k, 'px');
stats('zoom (log)', 'z', '');
stats('pointer x', 'px', 'px');
stats('pointer y', 'py', 'px');
