#!/usr/bin/env python3
"""Bake the reflector sheet grain, ported from brickboy src/display/reflector.ts.

The grain is a static property of one console's sheet, so brickboy bakes it once
on the CPU rather than evaluating ~28 hashes per fragment every frame. A slang
preset cannot run CPU code, so it ships as a PNG lookup instead; the maths and
constants are the same, including the JS integer-hash semantics.

    python3 tools/bake_grain.py            # writes shaders/grain.png
"""

import pathlib
import sys

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent

GRAIN_TEXELS_PER_DOT = 4
GRAIN_STORED_SIGMA = 1.0 / 3.0
UNIT_SIGMA = 0.81

# Module geometry from src/display/pipeline.ts
NATIVE_W, NATIVE_H = 160, 144
MARGIN = 4
PANEL_W, PANEL_H = NATIVE_W + 2 * MARGIN, NATIVE_H + 2 * MARGIN

M32 = 0xFFFFFFFF


def hash2(x, y, seed):
    """Integer hash -> [0,1). Mirrors the JS >>>0 / Math.imul semantics."""
    t = (np.asarray(x, dtype=np.float64) * 374761393.0
         + np.asarray(y, dtype=np.float64) * 668265263.0
         + float(seed) * 1442695041.0)
    u = (t.astype(np.int64) & M32).astype(np.uint64)
    h = (u ^ (u >> np.uint64(13))) & np.uint64(M32)
    h = (h * np.uint64(1274126177)) & np.uint64(M32)
    h = (h ^ (h >> np.uint64(16))) & np.uint64(M32)
    return h.astype(np.float64) / 4294967296.0


def vnoise(x, y, seed):
    """Value noise (bilinear-smoothed hash) at a point in lattice units."""
    x = np.asarray(x, dtype=np.float64)
    y = np.asarray(y, dtype=np.float64)
    ix = np.floor(x)
    iy = np.floor(y)
    fx = x - ix
    fy = y - iy
    fx = fx * fx * (3.0 - 2.0 * fx)
    fy = fy * fy * (3.0 - 2.0 * fy)
    a = hash2(ix, iy, seed)
    b = hash2(ix + 1, iy, seed)
    c = hash2(ix, iy + 1, seed)
    d = hash2(ix + 1, iy + 1, seed)
    return a + (b - a) * fx + (c - a + (d - b - c + a) * fx) * fy


def fbm(x, y, seed):
    """3-octave fbm; enough for the broad bands."""
    v = 0.0
    amp = 0.5
    px, py = np.asarray(x, dtype=np.float64), np.asarray(y, dtype=np.float64)
    for i in range(3):
        v = v + amp * vnoise(px, py, seed + i * 101)
        px = px * 2.03
        py = py * 2.03
        amp *= 0.5
    return v


def build(width_dots, height_dots, seed, fine_scale):
    T = GRAIN_TEXELS_PER_DOT
    w = max(1, round(width_dots * T))
    h = max(1, round(height_dots * T))
    fs = max(fine_scale, 0.1)
    s = int(round(seed * 1013))

    # The mottle and blotch bands vary far more slowly than one texel, so they
    # are evaluated once per DOT and interpolated.
    cw = int(np.ceil(width_dots)) + 2
    ch = int(np.ceil(height_dots)) + 2
    cy, cx = np.mgrid[0:ch, 0:cw].astype(np.float64)
    mottle = fbm(cx / 5.0, cy / 5.0, s + 11) - 0.5
    blotch = vnoise(cx / 18.0, cy / 18.0, s + 23) - 0.5
    # The slowest band overlaps finish.gradient, so it is weighted well below
    # its measured amplitude to avoid counting the same thing twice.
    coarse = 1.0 * mottle + 0.5 * blotch

    ty, tx = np.mgrid[0:h, 0:w].astype(np.float64)
    px = tx / T
    py = ty / T

    # Two decorrelated fine octaves: dense and isotropic, without the lattice
    # direction a single value noise shows at very small feature sizes.
    fine = (vnoise(px / fs, py / fs, s)
            + vnoise(px / (fs * 1.7), py / (fs * 1.7), s + 37)) * 0.5 - 0.5

    cx0 = np.floor(px).astype(np.int64)
    cy0 = np.floor(py).astype(np.int64)
    fx = px - cx0
    fy = py - cy0
    a = coarse[cy0, cx0]
    b = coarse[cy0, cx0 + 1]
    c = coarse[cy0 + 1, cx0]
    d = coarse[cy0 + 1, cx0 + 1]
    broad = a + (b - a) * fx + (c - a + (d - b - c + a) * fx) * fy

    # 2.5 : 1 by measured sigma - fine dominates, it is the わら半紙 read.
    g = (2.5 * fine + broad) * UNIT_SIGMA
    data = np.round(128.0 + 127.0 * np.clip(g, -1.0, 1.0)).astype(np.uint8)
    return data


def main():
    seed = float(sys.argv[1]) if len(sys.argv) > 1 else 7.0        # dmg.json defects.seed
    scale = float(sys.argv[2]) if len(sys.argv) > 2 else 0.45      # finish.paperScale
    g = build(PANEL_W, PANEL_H, seed, scale)
    out = ROOT / "shaders" / "grain.png"
    Image.fromarray(g, mode="L").save(out)
    print(f"{out.relative_to(ROOT)}  {g.shape[1]}x{g.shape[0]}  "
          f"sigma={g.astype(np.float64).std()/127.0:.3f} "
          f"(stored target {GRAIN_STORED_SIGMA:.3f})")


if __name__ == "__main__":
    main()
