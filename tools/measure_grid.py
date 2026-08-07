#!/usr/bin/env python3
"""Measure the grid modulation of the real shader on flat fields.

Renders a uniform frame of one shade through the actual .slang pipeline and
reports the peak-to-trough luminance swing over a native cell, the figure
display-pipeline.md 4-3 tabulates. Run at several upscale factors, because the
dot gap is 0.20 cell wide and stops being resolvable below ~6x - which is the
number that matters for the Pocket, where the scale is fixed at 4x.

    python3 tools/measure_grid.py --scales 4 6 10
"""

import argparse
import numpy as np
import moderngl

import preview

LUMA = np.array([0.299, 0.587, 0.114], dtype=np.float64)


def modulation(cell):
    lum = cell @ LUMA
    return (lum.max() - lum.min()) / lum.mean()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scales", type=int, nargs="+", default=[4, 6, 10])
    ap.add_argument("--set", action="append", default=[], metavar="name=value")
    args = ap.parse_args()

    overrides = {}
    for kv in args.set:
        k, v = kv.split("=", 1)
        overrides[k] = float(v)

    passes, luts = preview.parse_slangp(preview.ROOT / "brickboy-dmg.slangp")
    ctx = moderngl.create_standalone_context(backend="egl")

    print("scale  " + "  ".join(f"shade{s}" for s in range(4)))
    for scale in args.scales:
        out_size = (168 * scale, 152 * scale)
        row = []
        for s in range(4):
            pipe = preview.Pipeline(ctx, passes, luts, dict(overrides))
            frame = np.tile(preview.CORE_GREY[s], (144, 160, 1)).astype(np.float32)
            # Settle the persistence feedback before measuring.
            for _ in range(8):
                arr = pipe.render(frame, out_size)
            # A cell well inside the field, away from the aperture edge.
            ox = int(round((4 + 80) * scale))
            oy = int(round((4 + 72) * scale))
            cell = arr[oy:oy + scale, ox:ox + scale, :3].astype(np.float64) / 255.0
            row.append(modulation(cell) * 100)
        print(f"{scale:4d}   " + "  ".join(f"{v:6.2f}%" for v in row))


if __name__ == "__main__":
    main()
