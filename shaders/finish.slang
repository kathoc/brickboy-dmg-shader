#version 450

// Ported from brickboy src/display/shaders.ts FRAG_PASSTHROUGH (the present
// pass's screen-space finish): reflective sheen/glare, low-frequency
// non-uniformity, matte luma grain, corner vignette. All deterministic - the
// sheen is static and the grain is a fixed spatial hash, so nothing flickers.

layout(push_constant) uniform Push
{
    float bb_sheen;
    float bb_sheen_angle;
    float bb_sheen_hotspot;
    float bb_gradient;
    float bb_grain;
    float bb_vignette;
} param;

#pragma parameter bb_sheen         "Sheen"          0.00 0.0 1.0 0.01
#pragma parameter bb_sheen_angle   "Sheen angle"   28.00 0.0 90.0 1.0
#pragma parameter bb_sheen_hotspot "Sheen hotspot"  0.00 0.0 1.0 0.01
#pragma parameter bb_gradient      "Non-uniformity" 0.08 0.0 0.5 0.01
#pragma parameter bb_grain         "Matte grain"    0.012 0.0 0.1 0.001
#pragma parameter bb_vignette      "Vignette"       0.08 0.0 0.5 0.01

layout(std140, set = 0, binding = 0) uniform UBO
{
    mat4 MVP;
    vec4 OutputSize;
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

// Fixed reflection source, upper-left of the panel. brickboy's vUv is y-up and
// uses (0.30, 0.72); vTexCoord here is y-down, so the y flips.
const vec2 SHEEN_CENTER = vec2(0.30, 0.28);

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void main()
{
    vec3 col = texture(Source, vTexCoord).rgb;

    if (param.bb_gradient > 0.0) {
        float prox = 1.0 - clamp(distance(vTexCoord, SHEEN_CENTER), 0.0, 1.0);
        col *= 1.0 + param.bb_gradient * (prox - 0.5) * 2.0;
    }

    if (param.bb_vignette > 0.0) {
        vec2 vc = vTexCoord - 0.5;
        col *= 1.0 - param.bb_vignette * dot(vc, vc) * 2.0;
    }

    if (param.bb_sheen > 0.0 || param.bb_sheen_hotspot > 0.0) {
        float a = radians(param.bb_sheen_angle);
        vec2 dir = vec2(cos(a), sin(a));
        vec2 rel = vTexCoord - SHEEN_CENTER;
        float along  = dot(rel, dir);
        float across = dot(rel, vec2(-dir.y, dir.x));
        float broad = exp(-along * along * 3.0) * exp(-across * across * 0.7);
        float sheenAmt = broad * param.bb_sheen;
        col = 1.0 - (1.0 - col) * (1.0 - sheenAmt);
        float hd = distance(vTexCoord, SHEEN_CENTER);
        col += exp(-hd * hd * 22.0) * param.bb_sheen_hotspot;
    }

    if (param.bb_grain > 0.0) {
        float g = hash21(floor(vTexCoord * global.OutputSize.xy)) - 0.5;
        col += g * param.bb_grain;
    }

    FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
