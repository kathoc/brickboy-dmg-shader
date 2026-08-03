#!/usr/bin/env python3
"""Run the .slangp pipeline headlessly and write PNGs.

This executes the real fragment bodies out of the .slang files, with the real
#include tree. Only the slang plumbing (push constant block, UBO block,
descriptor bindings) is rewritten into plain GLSL 450 uniforms, and the vertex
stage is replaced by a fullscreen quad, since every pass uses the same
boilerplate one.

Texture coordinates follow RetroArch's convention: scanline 0 sits at v=0. The
harness keeps that mapping consistent across every FBO, so no pass flips.

    python3 tools/preview.py
    python3 tools/preview.py --set bb_density=0.7 --set bb_paper=0.0
"""

import argparse
import pathlib
import re
import sys

import numpy as np
import moderngl
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHADERS = ROOT / "shaders"
OUT = ROOT / "preview"

VERTEX = """#version 450
layout(location = 0) in vec2 aPos;
layout(location = 0) out vec2 vTexCoord;
void main() {
    vTexCoord   = aPos * 0.5 + 0.5;
    gl_Position = vec4(aPos, 0.0, 1.0);
}
"""


# ----------------------------------------------------------------- slang bits

def resolve_includes(path, seen=None):
    seen = seen if seen is not None else set()
    out = []
    for line in path.read_text().splitlines():
        m = re.match(r'\s*#include\s+"([^"]+)"', line)
        if not m:
            out.append(line)
            continue
        target = (path.parent / m.group(1)).resolve()
        if target in seen:
            continue
        seen.add(target)
        out.append(resolve_includes(target, seen))
    return "\n".join(out)


def split_decls(body):
    decls = []
    for stmt in body.split(";"):
        stmt = re.sub(r"//.*", "", stmt).strip()
        if not stmt:
            continue
        parts = stmt.split(None, 1)
        if len(parts) != 2:
            continue
        ty, names = parts
        for n in names.split(","):
            n = n.strip()
            if n:
                decls.append((ty, n))
    return decls


def parse_params(src):
    params = {}
    for m in re.finditer(r'#pragma\s+parameter\s+(\w+)\s+"[^"]*"\s+([-\d.]+)', src):
        params[m.group(1)] = float(m.group(2))
    return params


def translate(src):
    header = src.split("#pragma stage vertex")[0]
    frag = src.split("#pragma stage fragment")[1]
    src = header + frag
    uniforms = []

    def take_push(m):
        for ty, name in split_decls(m.group(1)):
            uniforms.append(f"uniform {ty} {name};")
        return ""

    src = re.sub(r"layout\(push_constant\)\s*uniform\s+Push\s*\{(.*?)\}\s*param\s*;",
                 take_push, src, flags=re.S)

    def take_ubo(m):
        for ty, name in split_decls(m.group(1)):
            if name != "MVP":
                uniforms.append(f"uniform {ty} {name};")
        return ""

    src = re.sub(r"layout\(std140[^)]*\)\s*uniform\s+UBO\s*\{(.*?)\}\s*global\s*;",
                 take_ubo, src, flags=re.S)
    src = re.sub(r"layout\(set\s*=\s*0,\s*binding\s*=\s*\d+\)\s*uniform\s+sampler2D",
                 "uniform sampler2D", src)
    src = re.sub(r"\bparam\.", "", src)
    src = re.sub(r"\bglobal\.", "", src)
    src = re.sub(r"#pragma\s+parameter[^\n]*\n", "", src)
    src = src.replace("#version 450", "")
    return "#version 450\n" + "\n".join(uniforms) + "\n" + src


def load_pass(name):
    path = SHADERS / name
    raw = resolve_includes(path)
    return translate(raw), parse_params(raw)


def parse_slangp(path):
    cfg = {}
    for line in path.read_text().splitlines():
        line = line.split("#")[0].strip()
        if "=" not in line:
            continue
        k, v = (x.strip().strip('"') for x in line.split("=", 1))
        cfg[k] = v
    passes = []
    for i in range(int(cfg["shaders"])):
        passes.append({
            "file": cfg[f"shader{i}"].split("/")[-1],
            "scale_type": cfg.get(f"scale_type{i}", "source"),
            "linear": cfg.get(f"filter_linear{i}", "false") == "true",
        })
    luts = {}
    for name in (cfg.get("textures") or "").replace(";", " ").split():
        if name in cfg:
            luts[name] = ROOT / cfg[name]
    return passes, luts


# ------------------------------------------------------------------ test data

def scene(t=0):
    """A 160x144 frame of DMG shade indices, 0 clear .. 3 dark."""
    h, w = 144, 160
    img = np.zeros((h, w), dtype=np.uint8)

    img[26:74, 18:58] = 3           # dark block: crosstalk reach + drop shadows
    img[26:74, 64:86] = 2           # mid slab
    img[26:74, 92:114] = 1          # light slab

    yy, xx = np.mgrid[0:h, 0:w]
    check = ((xx // 2 + yy // 2) % 2).astype(np.uint8)
    img[96:128, 8:72] = check[96:128, 8:72] * 3       # fine checker
    img[96:128, 80:144:4] = 3                          # single-px columns
    img[10:16, :] = 3                                  # full-width bar

    sx = 8 + int(t * 6) % 120
    img[82:90, sx:sx + 8] = 3                          # moving sprite
    return img


# A plain greyscale core output; the shaders recover the shade from luminance.
CORE_GREY = np.array([[1.0, 1.0, 1.0], [2 / 3, 2 / 3, 2 / 3],
                      [1 / 3, 1 / 3, 1 / 3], [0.0, 0.0, 0.0]], dtype=np.float32)


# ------------------------------------------------------------------- pipeline

class Pipeline:
    def __init__(self, ctx, passes, luts, overrides):
        self.ctx = ctx
        self.passes = passes
        self.progs = []
        self.params = {}
        for p in passes:
            src, defaults = load_pass(p["file"])
            self.params.update(defaults)
            try:
                self.progs.append(ctx.program(vertex_shader=VERTEX, fragment_shader=src))
            except Exception as e:
                sys.stderr.write(f"\n=== {p['file']} ===\n{e}\n")
                raise
        self.params.update(overrides)

        self.luts = {}
        for name, path in luts.items():
            im = Image.open(path).convert("L")
            tex = ctx.texture(im.size, 1, im.tobytes())
            tex.build_mipmaps()
            tex.filter = (moderngl.LINEAR_MIPMAP_LINEAR, moderngl.LINEAR)
            tex.repeat_x = tex.repeat_y = False
            self.luts[name] = tex

        quad = np.array([-1, -1, 3, -1, -1, 3], dtype="f4")
        self.vbo = ctx.buffer(quad.tobytes())
        self.vaos = [ctx.vertex_array(pr, [(self.vbo, "2f", "aPos")]) for pr in self.progs]
        self.fbos = {}
        self.prev = {}
        self.frame = 0

    def target(self, i, src_size, out_size):
        if i not in self.fbos:
            sz = out_size if self.passes[i]["scale_type"] == "viewport" else src_size
            tex = self.ctx.texture(sz, 4, dtype="f4")
            tex.repeat_x = tex.repeat_y = False
            self.fbos[i] = (self.ctx.framebuffer([tex]), tex, sz)
        return self.fbos[i]

    def feedback(self, i, sz):
        if i not in self.prev:
            tex = self.ctx.texture(sz, 4, dtype="f4")
            tex.filter = (moderngl.NEAREST, moderngl.NEAREST)
            tex.repeat_x = tex.repeat_y = False
            fb = self.ctx.framebuffer([tex])
            fb.use()
            self.ctx.clear(0.0, 0.0, 0.0, 1.0)
            self.prev[i] = (fb, tex)
        return self.prev[i]

    def render(self, frame_rgb, out_size):
        ctx = self.ctx
        h, w, _ = frame_rgb.shape
        src_size = (w, h)

        original = ctx.texture(src_size, 3, frame_rgb.astype("f4").tobytes(), dtype="f4")
        original.repeat_x = original.repeat_y = False
        original.filter = (moderngl.NEAREST, moderngl.NEAREST)

        outputs = {}
        current = original

        for i, p in enumerate(self.passes):
            fbo, tex, sz = self.target(i, src_size, out_size)
            tex.filter = ((moderngl.LINEAR, moderngl.LINEAR) if p["linear"]
                          else (moderngl.NEAREST, moderngl.NEAREST))
            fbo.use()
            ctx.viewport = (0, 0, *sz)
            prog = self.progs[i]
            unit = 0

            def bind(name, texture):
                nonlocal unit
                if name in prog:
                    texture.use(unit)
                    prog[name].value = unit
                    unit += 1

            bind("Source", current)
            bind("Original", original)
            for j, t in outputs.items():
                bind(f"PassOutput{j}", t)
            for name, t in self.luts.items():
                bind(name, t)
            if f"PassFeedback{i}" in prog:
                bind(f"PassFeedback{i}", self.feedback(i, sz)[1])

            for name, src in (("SourceSize", current), ("OriginalSize", original),
                              ("OutputSize", None)):
                if name in prog:
                    ww, hh = sz if name == "OutputSize" else src.size
                    prog[name].value = (ww, hh, 1.0 / ww, 1.0 / hh)
            if "FrameCount" in prog:
                prog["FrameCount"].value = self.frame

            for k, v in self.params.items():
                if k in prog:
                    prog[k].value = v

            self.vaos[i].render(moderngl.TRIANGLES, vertices=3)
            outputs[i] = tex
            current = tex

            if i in self.prev:
                ctx.copy_framebuffer(self.prev[i][0], fbo)

        # One convention throughout: v=0 is texel row 0 for every texture and
        # every FBO, so scanline 0 stays at v=0 across the whole chain and the
        # readback needs no flip. That matches what the .slang code assumes.
        self.frame += 1
        data = current.read()
        return np.frombuffer(data, dtype="f4").reshape(sz[1], sz[0], 4)[:, :, :3]


def save(arr, path):
    OUT.mkdir(exist_ok=True)
    Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8)).save(path)
    print(f"  {path.relative_to(ROOT)}  {arr.shape[1]}x{arr.shape[0]}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preset", default="brickboy-dmg.slangp")
    ap.add_argument("--scale", type=int, default=6)
    ap.add_argument("--set", action="append", default=[], metavar="name=value")
    args = ap.parse_args()

    overrides = {}
    for s in args.set:
        k, v = s.split("=", 1)
        overrides[k] = float(v)

    passes, luts = parse_slangp(ROOT / args.preset)
    ctx = moderngl.create_context(standalone=True, backend="egl", require=450)
    print(f"GL {ctx.info['GL_VERSION']}")

    # The render target is the whole module (168x152), not just the dot field.
    out_size = (168 * args.scale, 152 * args.scale)

    def run(name, frames, extra=None):
        params = dict(overrides)
        if extra:
            params.update(extra)
        pipe = Pipeline(ctx, passes, luts, params)
        for f in frames:
            arr = pipe.render(CORE_GREY[f], out_size)
        save(arr, OUT / f"{name}.png")

    still = [scene(0)] * 40

    print("rendering")
    run("01-panel", still)
    run("02-no-crosstalk", still, {"bb_crosstalk": 0.0})
    run("03-no-shadow", still, {"bb_drop_opacity": 0.0})
    run("04-no-grain", still, {"bb_paper": 0.0})
    run("05-density-high", still, {"bb_density": 0.72})
    run("06-density-low", still, {"bb_density": 0.28})
    run("07-ghost-trail", [scene(t) for t in range(0, 16)])
    run("08-ghost-off", [scene(t) for t in range(0, 16)], {"bb_ghost_strength": 0.0})


if __name__ == "__main__":
    main()
