#version 450

// Ported from brickboy src/display/shaders.ts FRAG_DEFECTS.
//
// The aged / faulty panel: dead electrode lines, vinegar syndrome, dust and the
// global illumination faults. Applied AFTER ghosting so panel damage never feeds
// the persistence loop.
//
// Adaptation: brickboy passes elapsed seconds in uTime, used ONLY by the
// dead-line marginal-contact flicker. RetroArch exposes FrameCount instead, so
// time is derived from it at the GB frame rate. Nothing else here is temporal -
// the layout is seeded and deterministic.
//
// Note on precision: the original carries `precision highp int` and a comment
// explaining that GLSL ES defaults int to mediump, which makes the 32 bit mix in
// dlMix lose digits on real GPUs and degenerate into "every column dead". Vulkan
// GLSL is always 32 bit, so that hazard does not exist here.

layout(push_constant) uniform Push
{
    float bb_seed;
    float bb_screen_rot;
    float bb_rot_mode;
    float bb_dimming;
    float bb_frontlight;
    float bb_backlight_bleed;
    float bb_dust;
    float bb_contrast_fade;
    float bb_dead_severity;
    float bb_dead_edge_bias;
    float bb_dead_lit;
    float bb_dead_row_ratio;
    float bb_dead_shimmer;
    float bb_bg_r, bb_bg_g, bb_bg_b;
    float bb_p3r, bb_p3g, bb_p3b;
} param;

// dmg.json leaves every damage defect off - a healthy panel - and seeds only
// defects.seed. Turn them up to age the unit.
#pragma parameter bb_screen_rot      "Vinegar syndrome"        0.0 0.0 1.0 0.01
#pragma parameter bb_rot_mode        "Rot pattern (0 blob 1 centre)" 1.0 0.0 1.0 1.0
#pragma parameter bb_dimming         "Panel dimming"           0.0 0.0 1.0 0.01
#pragma parameter bb_frontlight      "Frontlight gradient"     0.0 0.0 1.0 0.01
#pragma parameter bb_backlight_bleed "Backlight bleed"         0.0 0.0 1.0 0.01
#pragma parameter bb_dust            "Dust specks"             0.0 0.0 1.0 0.01
#pragma parameter bb_contrast_fade   "Contrast fade"           0.0 0.0 1.0 0.01
#pragma parameter bb_dead_severity   "Dead lines"              0.0 0.0 1.0 0.01
#pragma parameter bb_dead_edge_bias  "Dead line edge bias"     1.0 0.0 1.0 0.01
#pragma parameter bb_dead_lit        "Dead lines stuck dark"   0.06 0.0 1.0 0.01
#pragma parameter bb_dead_row_ratio  "Dead row rate"           0.15 0.0 1.0 0.01
#pragma parameter bb_dead_shimmer    "Dead line shimmer"       1.0 0.0 1.0 0.01

// Shared with the earlier passes. Every push constant member has to carry a
// #pragma parameter in the shader that declares it, or RetroArch rejects the
// block as an unknown semantic; the values themselves are global by name.
#pragma parameter bb_seed "Unit seed"   7.0 0.0 64.0 1.0
#pragma parameter bb_bg_r "Panel bg R" 0.930 0.0 1.0 0.002
#pragma parameter bb_bg_g "Panel bg G" 0.850 0.0 1.0 0.002
#pragma parameter bb_bg_b "Panel bg B" 0.586 0.0 1.0 0.002
#pragma parameter bb_p3r  "Shade 3 R"  0.130 0.0 1.0 0.002
#pragma parameter bb_p3g  "Shade 3 G"  0.360 0.0 1.0 0.002
#pragma parameter bb_p3b  "Shade 3 B"  0.170 0.0 1.0 0.002

layout(std140, set = 0, binding = 0) uniform UBO
{
    mat4 MVP;
    uint FrameCount;
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
layout(set = 0, binding = 2) uniform sampler2D Source;   // ghosted frame to degrade

#include "inc/bb_panel.inc"

#define NATIVE BB_NATIVE

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * vnoise(p);
        p *= 2.0;
        a *= 0.5;
    }
    return v;
}

// --- Dead-line RNG -----------------------------------------------------------
// The rot/dust noise above uses fract(sin(dot(...))*43758.5453), which is fine
// for organic blobs but NOT for a decision that has to be uniformly distributed:
// at a column index of 159 the argument to sin() is already ~20000, and argument
// reduction there is lossy enough that the result develops visible structure.
// Dead-line placement is a probability, so it gets an exact integer bit-mix.
uint dlMix(uint x) {
    x ^= x >> 16; x *= 0x7feb352du;
    x ^= x >> 15; x *= 0x846ca68bu;
    x ^= x >> 16;
    return x;
}

float dlRand(int a, int b) {
    uint h = dlMix(uint(a) * 0x9e3779b9u ^ dlMix(uint(b)));
    return float(h) * (1.0 / 4294967296.0);
}

float dlNoise(float t, int salt) {
    float i = floor(t);
    float f = fract(t);
    f = f * f * (3.0 - 2.0 * f);
    return mix(dlRand(int(i), salt), dlRand(int(i) + 1, salt), f);
}

vec3 reflectorColor() { return vec3(param.bb_bg_r, param.bb_bg_g, param.bb_bg_b); }
vec3 darkShade()      { return vec3(param.bb_p3r, param.bb_p3g, param.bb_p3b); }

// Where along the screen a COLUMN is likely to drop out. Not flat: the column
// electrodes reach the glass through one lap-bonded flex along a screen edge,
// and a lap joint peels from the ENDS of its overlap, which are the left and
// right edges of the picture. Surveyed on 28 units / 192 lines: the outer 20% of
// the screen holds 39% of all dropped columns against a flat expectation of 20%,
// and the centre 20% holds 13%. Normalised to mean 1, so raising the severity
// still kills the same FRACTION of columns - this moves WHERE they die.
float vEdgeWeight(float cx) {
    if (param.bb_dead_edge_bias <= 0.0) return 1.0;
    float x = cx / (NATIVE.x - 1.0);
    const float L = 0.14;
    const float A = 0.230;
    const float B = 0.040;
    const float MEAN = 0.10435;   // integral of the above over [0,1]
    float w = A * (exp(-x / L) + exp(-(1.0 - x) / L)) + B;
    return mix(1.0, w / MEAN, clamp(param.bb_dead_edge_bias, 0.0, 1.0));
}

// Life or death for one column, as an explicit PROBABILITY. u is uniform and
// decides alone, so P(dead) is exactly sev x edge x clump. Both factors average
// 1, so the severity dial sets the dead fraction and the factors only decide
// where those columns are; clump is spatially correlated, which is what makes
// dropouts arrive as contiguous bands rather than scattered singletons.
float vDeadDrop(float cx, float sev) {
    int sd = int(param.bb_seed * 1013.0);
    float u = dlRand(int(cx), sd ^ 23473);
    float clump = clamp(0.35 + 1.3 * dlNoise(cx * 0.18, sd ^ 7991), 0.0, 2.0);
    if (u >= sev * 0.94 * vEdgeWeight(cx) * clump) return 0.0;
    return clamp(0.86 + 0.14 * dlRand(int(cx), sd ^ 41221), 0.0, 1.0);
}

// A bond failure DISCONNECTS the electrode, so its LC relaxes to the UN-DRIVEN
// state - on a normally-white reflective panel that is the light reflector,
// which is why real dead lines are overwhelmingly white. A minority instead
// settle dark: a floating electrode can pick up enough leakage bias to sit
// on-ish. bb_dead_lit is that minority fraction.
vec3 vDeadShade(float cx) {
    float s = dlRand(int(cx), int(param.bb_seed * 1013.0) ^ 9001);
    return s < param.bb_dead_lit ? darkShade() : reflectorColor();
}

// Marginal-contact flicker for a dead line:
//  - WHOLE LINE, not per-segment. A column electrode is fed from a SINGLE bond
//    at the screen edge, so a marginal bond drops the drive on the whole column.
//  - RARE. Most dead lines are fully disconnected and sit dead-steady.
//  - BURSTY, not a constant strobe: mostly holds, then a drift tips it into a
//    short episode of instability, then it settles again.
//  - Two-VALUE. During a burst the line toggles present/gone, not dimming.
float deadFlicker(float line, int sd, float sh, float t) {
    if (sh <= 0.0) return 1.0;
    int li = int(line);
    float q = dlRand(li, sd ^ 21507);
    if (q < 1.0 - 0.12 * sh) return 1.0;            // steady dead line
    float inst = dlNoise(t * 0.45 + float(li) * 7.3, sd ^ 4021);
    float burst = smoothstep(0.80, 0.93, inst);
    if (burst <= 0.0) return 1.0;                   // between episodes
    int tq = int(t * 14.0);
    float toggle = step(0.5, dlRand(li * 911, tq ^ 30671));
    return mix(1.0, toggle, burst);
}

// Dot coverage. Contains fwidth, so it MUST be called once, outside any branch:
// taking derivatives inside non-uniform control flow is undefined, and doing so
// wrecked the whole picture on real hardware while looking fine under software
// rendering. margin matches the grid pass at the default pixel_size (0.8).
float deadDotBody(vec2 aUvLocal) {
    vec2 cc = aUvLocal * NATIVE;
    vec2 cell = fract(cc);
    vec2 fw = fwidth(cc) + 1e-4;
    const float margin = 0.20;
    vec2 e = max(vec2(margin), fw);
    vec2 mm = smoothstep(vec2(0.0), e, cell) * smoothstep(vec2(0.0), e, 1.0 - cell);
    return mm.x * mm.y;
}

// Apply the dot grid to a settled dead-line colour, so the line reads as a
// string of DOTS with reflector gaps between them, not a solid painted bar.
vec3 deadGridded(vec3 shade, float body) {
    return mix(reflectorColor() * 0.94, shade, body);
}

// Rows get NO edge bias. They fail through a different path - a flimsy
// compression-held film with carbon traces, i.e. distributed contact pressure,
// not end peel. The survey agrees, but on only 7 units and with repair-induced
// damage in the sample, so flat is the honest read.
float rDeadDrop(float cy, float sev) {
    int sd = int(param.bb_seed * 1013.0);
    float u = dlRand(int(cy), sd ^ 55127);
    float clump = clamp(0.35 + 1.3 * dlNoise(cy * 0.22, sd ^ 13109), 0.0, 2.0);
    if (u >= sev * 0.94 * param.bb_dead_row_ratio * clump) return 0.0;
    return clamp(0.86 + 0.14 * dlRand(int(cy), sd ^ 60659), 0.0, 1.0);
}

vec3 rDeadShade(float cy) {
    float s = dlRand(int(cy), int(param.bb_seed * 1013.0) ^ 24677);
    return s < param.bb_dead_lit ? darkShade() : reflectorColor();
}

void main()
{
    vec3 rgb = texture(Source, vTexCoord).rgb;

    // brickboy works in a y-up module uv; vTexCoord here is y-down.
    vec2 uv = vec2(vTexCoord.x, 1.0 - vTexCoord.y);
    vec2 aUv = (uv - BB_ACTIVE.xy) / BB_ACTIVE.zw;
    bool inActive = aUv.x >= 0.0 && aUv.x < 1.0 && aUv.y >= 0.0 && aUv.y < 1.0;

    // Take the derivative unconditionally - see deadDotBody.
    float deadBody = deadDotBody(aUv);
    float edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));

    float t = float(global.FrameCount) / 59.7275;

    // --- Global tone -------------------------------------------------------
    rgb *= mix(1.0, 0.35, param.bb_dimming);

    float fl = mix(1.0 - 0.30 * param.bb_frontlight,
                   1.0 + 0.15 * param.bb_frontlight, uv.y);
    rgb *= fl;

    float bleed = 1.0 - smoothstep(0.0, 0.22, edgeDist);
    rgb += vec3(bleed) * param.bb_backlight_bleed * 0.45;

    rgb = mix(rgb, vec3(0.5), param.bb_contrast_fade * 0.5);

    // --- Screen rot / vinegar syndrome -------------------------------------
    if (param.bb_screen_rot > 0.0) {
        float depth = param.bb_screen_rot;
        float cover = 0.0;
        if (param.bb_rot_mode >= 0.5) {
            // Follow the LCD's rounded-RECTANGLE shape, not a perfect circle.
            vec2 dv = abs(uv - vec2(0.5)) * 2.0;
            float pw = 2.6;
            float dist = pow(pow(dv.x, pw) + pow(dv.y, pw), 1.0 / pw) * 0.5;
            float wob = 0.045 * (fbm((uv - 0.5) * 5.0 + param.bb_seed) - 0.5);
            float front = depth * 0.66;
            cover = 1.0 - smoothstep(front - 0.16 + wob, front + wob, dist);
            cover *= mix(1.0, 0.5, clamp(dist / max(front, 1e-3), 0.0, 1.0));
        } else {
            for (int i = 0; i < 4; i++) {
                float fi = float(i);
                vec2 s = vec2(hash(vec2(param.bb_seed + fi * 3.1, 7.0)),
                              hash(vec2(param.bb_seed + fi * 5.7, 13.0)));
                vec2 cen = vec2(0.5) + (s - 0.5) * 0.7;
                float thresh = 0.08 + fi * 0.22;
                float grow = smoothstep(thresh, min(thresh + 0.5, 1.0), depth);
                if (grow <= 0.0) continue;
                vec2 dv = uv - cen;
                dv.x *= NATIVE.x / NATIVE.y;
                float ang = atan(dv.y, dv.x);
                float ragged = 0.45 + 0.55 * fbm(vec2(ang * 1.7, ang * 0.6) + s * 9.0);
                float rad = (0.09 + 0.30 * grow) * ragged;
                cover = max(cover, 1.0 - smoothstep(rad * 0.55, rad, length(dv)));
            }
        }
        vec3 rotColor = vec3(0.11, 0.07, 0.14);
        float op = cover * (0.45 + 0.5 * cover) * clamp(depth * 1.3, 0.0, 0.94);
        rgb = mix(rgb, rotColor, clamp(op, 0.0, 0.94));
    }

    // --- Dust / blemish specks ---------------------------------------------
    if (param.bb_dust > 0.0) {
        vec2 cell = floor(uv * NATIVE);
        float dn = hash(cell + vec2(param.bb_seed * 3.1, param.bb_seed * 5.7));
        if (dn > 1.0 - param.bb_dust * 0.05) rgb *= 0.25;
    }

    float nx = aUv.x * NATIVE.x;

    // --- Procedural dead-line dropout --------------------------------------
    // A ribbon / heat-seal bond failure floats a whole electrode: vertical
    // (column) and, fewer, horizontal (row) lines settle to a leakage shade.
    // Deterministic layout from the seed; time drives only the marginal-contact
    // flicker, never any positional wander - the electrode is fixed.
    if (param.bb_dead_severity > 0.0 && inActive) {
        // The dial is deliberately non-linear. P(dead) is exactly proportional
        // to sev, so a linear dial would put ~15 dead columns on screen at 0.1.
        // ^2.2 restores a fine low end (~1 column at 0.1, ~7 at 0.25) while
        // keeping the ~92%-dead top end.
        float sev = pow(clamp(param.bb_dead_severity, 0.0, 1.0), 2.2);
        float sh = param.bb_dead_shimmer;
        int sd = int(param.bb_seed * 1013.0);

        // Vertical columns ---------------------------------------------------
        float xf = clamp(nx, 0.0, NATIVE.x - 1.0);
        float c0 = floor(xf);
        float fr = xf - c0;
        float cN = fr < 0.5 ? c0 - 1.0 : c0 + 1.0;
        float dOwn = vDeadDrop(c0, sev);
        float dNb  = vDeadDrop(cN, sev);
        // Soft ~1px edges: feather coverage across the shared column boundary,
        // continuous across it, so bands of dead columns show no interior seam.
        float vEdge = fr < 0.5 ? fr : 1.0 - fr;
        float vCov = mix((dOwn + dNb) * 0.5, dOwn, smoothstep(0.0, 0.6, vEdge));
        if (vCov > 0.0) {
            float cy = clamp((1.0 - aUv.y) * NATIVE.y, 0.0, NATIVE.y - 1.0);
            // Gradient along the line: contact resistance fades end to end.
            float gA = 0.55 + 0.45 * hash(vec2(c0 * 1.7, param.bb_seed + 4.0));
            float gB = 0.55 + 0.45 * hash(vec2(c0 * 2.3, param.bb_seed + 8.0));
            float vGrad = mix(gA, gB, cy / NATIVE.y);
            float flick = deadFlicker(c0, sd, sh, t);
            vec3 vDead = deadGridded(vDeadShade(c0), deadBody);
            rgb = mix(rgb, vDead, clamp(vCov * vGrad * flick, 0.0, 1.0));
        }

        // Horizontal rows ----------------------------------------------------
        float yf = clamp((1.0 - aUv.y) * NATIVE.y, 0.0, NATIVE.y - 1.0);
        float r0 = floor(yf);
        float rfr = yf - r0;
        float rN = rfr < 0.5 ? r0 - 1.0 : r0 + 1.0;
        float eOwn = rDeadDrop(r0, sev);
        float eNb  = rDeadDrop(rN, sev);
        float rEdge = rfr < 0.5 ? rfr : 1.0 - rfr;
        float rCov = mix((eOwn + eNb) * 0.5, eOwn, smoothstep(0.0, 0.6, rEdge));
        if (rCov > 0.0) {
            float rx = clamp(nx, 0.0, NATIVE.x - 1.0);
            float hA = 0.55 + 0.45 * hash(vec2(r0 * 1.9, param.bb_seed + 6.0));
            float hB = 0.55 + 0.45 * hash(vec2(r0 * 2.7, param.bb_seed + 12.0));
            float rGrad = mix(hA, hB, rx / NATIVE.x);
            // r0 salted so rows and columns do not flicker in lock-step.
            float rFlick = deadFlicker(r0 + 512.0, sd ^ 44029, sh, t);
            vec3 rDead = deadGridded(rDeadShade(r0), deadBody);
            rgb = mix(rgb, rDead, clamp(rCov * rGrad * rFlick, 0.0, 1.0));
        }
    }

    FragColor = vec4(clamp(rgb, 0.0, 1.0), 1.0);
}
