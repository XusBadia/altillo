#!/usr/bin/env python3
"""Per-frame motion analysis of a rendered video (is it smooth?).

For every pair of consecutive frames (downscaled to 480 px wide, greyscale, Hann window):
  - the camera: features tracked (Lucas–Kanade) and a similarity transform fitted with RANSAC → translation of the
    frame centre in px/frame (of the full-size video) and zoom ratio per frame;
  - the mean absolute difference → hard cuts show up as spikes.
Then acceleration = change of velocity (and of log-scale) between frames. A smooth camera has small accelerations
everywhere; a jerk shows as a spike. Prints the worst frames and every cut, and writes a CSV to /tmp/<video>-motion.csv.

Usage: python3 scripts/motion-check.py videos/altillo-casa.mp4 [--expect-cuts 120,1440]
"""
import csv
import subprocess
import sys

import cv2
import numpy as np

path = sys.argv[1]
expect = [int(x) for x in sys.argv[sys.argv.index('--expect-cuts') + 1].split(',')] if '--expect-cuts' in sys.argv else []
probe = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height',
                        '-of', 'csv=p=0', path], capture_output=True, text=True).stdout.strip().split(',')
W0, H0 = int(probe[0]), int(probe[1])
w = 480
h = int(round(H0 * w / W0 / 2) * 2)
raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', path, '-vf', f'scale={w}:{h},format=gray', '-f', 'rawvideo', '-'],
                     capture_output=True, check=True).stdout
frames = np.frombuffer(raw, np.uint8).reshape(-1, h, w).astype(np.float32)
k = W0 / w
win = cv2.createHanningWindow((w, h), cv2.CV_32F)
center = (w / 2, h / 2)
M = w / np.log(w / 2)


def logpolar(img):
    f = np.fft.fftshift(np.abs(np.fft.fft2(img * win)))
    f = np.log1p(f).astype(np.float32)
    return cv2.warpPolar(f, (w, h), center, w / 2, cv2.WARP_POLAR_LOG + cv2.INTER_LINEAR)


rows = []
for i in range(1, len(frames)):
    a, b = frames[i - 1], frames[i]
    mad = float(np.mean(np.abs(a - b)))
    # Camera = the similarity transform most tracked features agree on (RANSAC), so UI changes, the cursor
    # and type popping in don't count as camera motion.
    a8, b8 = a.astype(np.uint8), b.astype(np.uint8)
    pts = cv2.goodFeaturesToTrack(a8, 400, 0.01, 6)
    dx = dy = 0.0
    scale = 1.0
    inl = 0.0
    if pts is not None and len(pts) >= 12:
        nxt, st, _ = cv2.calcOpticalFlowPyrLK(a8, b8, pts, None, winSize=(21, 21), maxLevel=3)
        good = st.ravel() == 1
        if good.sum() >= 12:
            # Centre the coordinates so the translation is the motion of the frame centre.
            p0 = pts[good].reshape(-1, 2) - [w / 2, h / 2]
            p1 = nxt[good].reshape(-1, 2) - [w / 2, h / 2]
            m, inliers = cv2.estimateAffinePartial2D(p0, p1, method=cv2.RANSAC, ransacReprojThreshold=1.0)
            if m is not None:
                scale = float(np.hypot(m[0, 0], m[1, 0]))
                dx, dy = float(m[0, 2]), float(m[1, 2])
                inl = float(inliers.mean())
    rows.append((i, dx * k, dy * k, scale, inl, mad))

arr = np.array(rows)
vel = np.hypot(arr[:, 1], arr[:, 2])
logs = np.log(arr[:, 3])
mad = arr[:, 5]
cut = mad > np.maximum(10, 8 * np.median(mad) + 3)
# A 3-frame median first: single-frame tracking glitches on flat areas are noise, a real jerk lasts longer.
def med3(x):
    p = np.pad(x, (1, 1), mode='edge')
    return np.median(np.stack([p[:-2], p[1:-1], p[2:]]), axis=0)


acc = np.abs(np.diff(np.stack([med3(arr[:, 1]), med3(arr[:, 2])], 1), axis=0)).max(1)
acc_s = np.abs(np.diff(med3(logs)))
# Ignore accelerations right at cuts and where correlation is unreliable (mostly flat frames or big content change).
ok = (~cut[1:]) & (~cut[:-1]) & (arr[1:, 4] > 0.5) & (arr[:-1, 4] > 0.5)
cuts = [int(arr[j, 0]) for j in np.where(cut)[0]]
unexpected = [c for c in cuts if not any(abs(c - e) <= 3 for e in expect)]

import os
with open('/tmp/' + os.path.basename(path).rsplit('.', 1)[0] + '-motion.csv', 'w', newline='') as f:
    wr = csv.writer(f)
    wr.writerow(['frame', 'dx_px', 'dy_px', 'scale', 'inlier_ratio', 'mean_abs_diff'])
    wr.writerows(rows)

print(f'{path}: {len(frames)} frames')
live = (~cut) & (arr[:, 4] > 0.5)
print(f'  max camera speed     {vel[live].max():6.1f} px/frame (frame {int(arr[live][vel[live].argmax(), 0])})')
print(f'  max zoom rate        {np.abs(logs[live]).max() * 100:6.2f} %/frame')
print(f'  max acceleration     {acc[ok].max():6.2f} px/frame² (frame {int(arr[1:][ok][acc[ok].argmax(), 0])})'
      f'   p99 {np.percentile(acc[ok], 99):.2f}')
print(f'  max zoom accel.      {acc_s[ok].max() * 100:6.3f} %/frame²   p99 {np.percentile(acc_s[ok], 99) * 100:.3f}')
print(f'  big frame differences (cuts, or the notch opening/closing): {cuts}')
print(f'  unexpected cuts: {unexpected if unexpected else "none"}')
worst = np.argsort(-np.where(ok, acc, 0))[:8]
print('  worst accelerations:', ', '.join(f'{int(arr[j + 1, 0])}:{acc[j]:.1f}' for j in worst))
