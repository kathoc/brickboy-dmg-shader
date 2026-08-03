#version 450

// Ported from brickboy src/display/shaders.ts FRAG_COLUMN_REDUCE.
//
// Passive-matrix crosstalk FIELD at native resolution. For each pixel it
// accumulates the darkness of the pixels above it in the same column (a dark
// block bleeds a shadow downward - the defining passive-matrix look) with an
// exponential-decay tail, plus a weak leftward row term. Accumulation is
// RMS-ish (square-weighted) after Alt-Pleshko.
//
// Adaptation: brickboy reads the native R16UI framebuffer and takes shade/3
// directly. A libretro core hands us sRGB, so darkness is recovered from
// luminance. Set the core to a plain DMG palette so the four shades stay
// separable.

layout(push_constant) uniform Push
{
    float bb_seed;
    float bb_xtalk_noise;
    float bb_xtalk_edge;
} param;

#pragma parameter bb_seed        "Unit seed"                  7.0 0.0 64.0 1.0
#pragma parameter bb_xtalk_noise "Crosstalk column noise"     0.18 0.0 1.0 0.01
#pragma parameter bb_xtalk_edge  "Crosstalk edge banding"     0.40 0.0 1.0 0.01

layout(std140, set = 0, binding = 0) uniform UBO
{
    mat4 MVP;
    vec4 SourceSize;
} global;

#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;

void main()
{
    gl_Position = global.MVP * Position;
    vTexCoord   = TexCoord;
}

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float lumaOf(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

// Native-pixel darkness (0 light .. 1 dark), clamped to the panel.
float darkAt(ivec2 c) {
    ivec2 sz = ivec2(global.SourceSize.xy);
    c = clamp(c, ivec2(0), sz - 1);
    float l = lumaOf(texelFetch(Source, c, 0).rgb);
    return clamp(floor((1.0 - l) * 3.0 + 0.5) / 3.0, 0.0, 1.0);
}

void main()
{
    ivec2 sz = ivec2(global.SourceSize.xy);
    int col = clamp(int(vTexCoord.x * global.SourceSize.x), 0, sz.x - 1);
    int row = clamp(int(vTexCoord.y * global.SourceSize.y), 0, sz.y - 1);

    // Vertical crosstalk: bidirectional. A dark block shifts the gray both below
    // (stronger, discharge direction) and above (weaker), so it surrounds dark
    // content rather than reading as a one-way drop-shadow that would duplicate
    // the pixel drop-shadow in the grid pass.
    const float decayV = 12.0;
    float wnV = 1.0 - exp(-1.0 / decayV);
    float vsum = 0.0;
    for (int k = 1; k <= 40; k++) {
        float w = exp(-float(k) / decayV);
        int ya = row - k;
        if (ya >= 0) { float d = darkAt(ivec2(col, ya)); vsum += d * d * w; }
        int yb = row + k;
        if (yb < sz.y) { float d = darkAt(ivec2(col, yb)); vsum += 0.4 * d * d * w; }
    }
    vsum *= wnV;

    // Weak leftward row term, shorter tail, quarter weight.
    const float decayH = 8.0;
    float wnH = 1.0 - exp(-1.0 / decayH);
    float hsum = 0.0;
    for (int k = 1; k <= 24; k++) {
        int x = col - k;
        if (x < 0) break;
        float d = darkAt(ivec2(x, row));
        hsum += d * d * exp(-float(k) / decayH);
    }
    hsum *= wnH;

    float field = vsum + 0.25 * hsum;

    // Edge-triggered banding: emphasise the shift at the top and bottom edges of
    // a dark block so it reads as bands rather than a uniform column tint.
    if (param.bb_xtalk_edge > 0.0) {
        float dUp = darkAt(ivec2(col, row - 1));
        float dDn = darkAt(ivec2(col, row + 1));
        field += param.bb_xtalk_edge * abs(dDn - dUp);
    }

    // Per-unit crosstalk noise: a faint per-column gain variation keyed on the
    // shared defect seed, so one seed = one console's crosstalk fingerprint.
    if (param.bb_xtalk_noise > 0.0) {
        float n = hash21(vec2(float(col), param.bb_seed * 1.3 + 3.0));
        field *= 1.0 + param.bb_xtalk_noise * (n - 0.5);
    }

    FragColor = vec4(max(field, 0.0), 0.0, 0.0, 1.0);
}
