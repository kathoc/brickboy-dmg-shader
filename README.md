# brickboy-dmg (RetroArch slang port)

A port of the DMG display pipeline from **brickboy** (`~/Playground/brickboy`,
`src/display/`) to a RetroArch slang preset. This is not an independent
implementation: the maths, the pass order and the constants come from there.

## Provenance

| this repo | ported from |
|---|---|
| `shaders/xtalk-field.slang` | `shaders.ts` `FRAG_COLUMN_REDUCE` |
| `shaders/color-correct.slang` | `shaders.ts` `FRAG_COLOR_CORRECT` (dmg-lut path) |
| `shaders/grid.slang` | `shaders.ts` `FRAG_GRID` |
| `shaders/ghost.slang` | `shaders.ts` `FRAG_GHOST` |
| `shaders/defects.slang` | `shaders.ts` `FRAG_DEFECTS` |
| `shaders/finish.slang` | `shaders.ts` `FRAG_PASSTHROUGH` (present finish) |
| `tools/bake_grain.py` | `reflector.ts` `buildGrainTexture` |
| parameter defaults | `src/display/profiles/dmg.json` |
| `brickboy-dmg-real.slangp` | `src/display/profiles/dmg-real.json` (measured) |
| module geometry | `src/display/pipeline.ts` (`PANEL_MARGIN` 4 → 168×152) |
| tau derivation | `src/display/pipeline.ts` (`8 + 102·strength`, fall = ×0.35) |
| `docs/display-pipeline.ja.md` | brickboy `docs/` (verbatim) |
| `docs/dmg-panel-color.ja.md` | brickboy `docs/` (verbatim) |

Not yet ported: the non-DMG colour-correction modes (`cgb-byuu`, `gba-byuu`).

## Deliberate adaptations

Four places could not be carried over as-is. Everything else is the same code.

1. **Shade recovery.** brickboy reads the native framebuffer (`R16UI`, shade
   0..3) straight out of its own PPU. A libretro core hands the shader sRGB, so
   the shade is recovered from luminance and then mapped through the profile
   palette. Set the core to a plain DMG palette so the four shades stay
   separable — the palette that reaches the screen is the profile's, not the
   core's.
2. **Frame time.** brickboy feeds real elapsed ms into the ghost IIR. RetroArch
   exposes no frame time, so `dt` is fixed at one GB frame (16.742 ms), which is
   what brickboy's own offline render harness does.
3. **Dead-line flicker time.** `FRAG_DEFECTS` takes elapsed seconds in `uTime`,
   used only by the marginal-contact flicker. RetroArch exposes `FrameCount`, so
   time is derived from it at the GB frame rate. The dead-line *layout* is
   seeded and deterministic either way.
4. **Reflector grain.** brickboy bakes it on the CPU at startup. A preset cannot
   run CPU code, so `tools/bake_grain.py` bakes the same texture (same hash, same
   bands, same constants) to `shaders/grain.png`. The baked sigma comes out at
   0.335 against the 1/3 target, which is a useful check on the port.

## Install

Copy `brickboy-dmg.slangp`, `shaders/` into your RetroArch shader directory and
load the preset. Passes 0-3 need `float_framebuffer`; the ghost feedback buffer
is the analog cell state and an 8 bit buffer quantises the relaxation into steps.

## Preview

`tools/preview.py` runs the preset headlessly on the GPU and writes PNGs to
`preview/`. It executes the real fragment bodies from the `.slang` files with the
real `#include` tree; only the slang plumbing is rewritten into plain GLSL
uniforms, and the vertex stage becomes a fullscreen quad.

```
python3 tools/bake_grain.py
python3 tools/preview.py
python3 tools/preview.py --set bb_density=0.72 --set bb_paper=0.0
```

Needs `moderngl` and an EGL-capable GPU. No display or RetroArch install needed.

## Still to do

Pixel-level comparison against brickboy itself. `src/render-harness.ts` exposes
`window.__rf.renderBatch()` under `?renderfarm=1` and is documented as pixel
identical to the app, so the same input frames can be pushed through both and
differenced, rather than judging by eye.

## Where the numbers come from

`docs/display-pipeline` is brickboy's own full specification of the look, written
so it can be re-implemented on any core in any language. It is bundled verbatim
and it, not this README, is the authority. Both documents ship in Japanese
(`.ja.md`, the original) and English (`.en.md`, a translation — the Japanese wins
where they disagree). The figures they reference live in the brickboy repository
and are not bundled.

Read its opening before trusting any constant. In short: the values are **not
instrument measurements of real hardware**. They start from the author's memory
of the real thing, are assembled against published specs, technical write-ups and
photographs, then tuned until it looks right. The document marks which parts have
a cited source (the colour-correction matrices, the boundary values) and which
are tuning, and it deliberately keeps the conclusions that were later withdrawn
so the same traps are not walked into twice.

`docs/dmg-panel-color` is the part that *is* a measurement: the panel colour
checked against photographs of ten real units. Its own summary is worth
repeating - no evidence was found that brickboy's colour is wrong, and five
plausible conclusions were reached and withdrawn along the way.

## Licence

Apache License 2.0, the same as the project this is ported from.

The shader bodies, constants and the measurements behind them come from
**brickboy** (`src/display/`). This repository is a derivative work: the pipeline
was translated from GLSL ES 3.0 to slang and the four adaptations listed above
were made. Everything else is that code.

## Support

This is free, and it stays free. But it was a lot of measuring against real
hardware to get right, and if any of it is useful to you, a little help would
genuinely make me happy.

[**Sponsor @kathoc**](https://github.com/sponsors/kathoc)

No pressure at all — a star or a bug report is welcome too.
