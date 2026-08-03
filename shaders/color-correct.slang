#version 450

// Ported from brickboy src/display/shaders.ts FRAG_COLOR_CORRECT (dmg-lut path).
//
// Maps the native shade to the profile's measured sRGB palette, then applies
// density (the physical contrast wheel), off-pixel tint, passive-matrix
// crosstalk, panel gamma, saturation, warm tint, tone and the reflective
// black-lift floor.
//
// The render target is the whole LCD MODULE (active area plus the exposed
// reflector margin), so uActive locates the 160x144 dot field inside it.

layout(push_constant) uniform Push
{
    float bb_p0r, bb_p0g, bb_p0b;
    float bb_p1r, bb_p1g, bb_p1b;
    float bb_p2r, bb_p2g, bb_p2b;
    float bb_p3r, bb_p3g, bb_p3b;
    float bb_bg_r, bb_bg_g, bb_bg_b;
    float bb_brightness;
    float bb_contrast;
    float bb_bleed;
    float bb_saturation;
    float bb_warm;
    float bb_panel_gamma;
    float bb_black_lift;
    float bb_density;
    float bb_crosstalk;
    float bb_temperature;
    float bb_off_tint;
    float bb_xtalk_signed;
    float bb_xtalk_gray;
} param;

// dmg.json dmgPalette
#pragma parameter bb_p0r "Shade 0 R" 0.860 0.0 1.0 0.002
#pragma parameter bb_p0g "Shade 0 G" 0.811 0.0 1.0 0.002
#pragma parameter bb_p0b "Shade 0 B" 0.533 0.0 1.0 0.002
#pragma parameter bb_p1r "Shade 1 R" 0.550 0.0 1.0 0.002
#pragma parameter bb_p1g "Shade 1 G" 0.700 0.0 1.0 0.002
#pragma parameter bb_p1b "Shade 1 B" 0.400 0.0 1.0 0.002
#pragma parameter bb_p2r "Shade 2 R" 0.280 0.0 1.0 0.002
#pragma parameter bb_p2g "Shade 2 G" 0.510 0.0 1.0 0.002
#pragma parameter bb_p2b "Shade 2 B" 0.260 0.0 1.0 0.002
#pragma parameter bb_p3r "Shade 3 R" 0.130 0.0 1.0 0.002
#pragma parameter bb_p3g "Shade 3 G" 0.360 0.0 1.0 0.002
#pragma parameter bb_p3b "Shade 3 B" 0.170 0.0 1.0 0.002
// grid.bgTint - the unlit reflector colour
#pragma parameter bb_bg_r "Panel bg R" 0.930 0.0 1.0 0.002
#pragma parameter bb_bg_g "Panel bg G" 0.850 0.0 1.0 0.002
#pragma parameter bb_bg_b "Panel bg B" 0.586 0.0 1.0 0.002

#pragma parameter bb_brightness   "Brightness"        0.88 0.0 2.0 0.01
#pragma parameter bb_contrast     "Contrast"          0.88 0.0 2.0 0.01
#pragma parameter bb_bleed        "STN bleed"         0.16 0.0 1.0 0.01
#pragma parameter bb_saturation   "Saturation"        0.85 0.0 2.0 0.01
#pragma parameter bb_warm         "Warm tint"         0.06 0.0 0.5 0.01
#pragma parameter bb_panel_gamma  "Panel gamma"       1.10 0.5 2.5 0.01
#pragma parameter bb_black_lift   "Black lift"        0.10 0.0 1.0 0.01
#pragma parameter bb_density      "Contrast dial"     0.50 0.0 1.0 0.01
#pragma parameter bb_crosstalk    "Crosstalk"         0.34 0.0 2.0 0.01
#pragma parameter bb_temperature  "Panel cold"        0.00 0.0 1.0 0.01
#pragma parameter bb_off_tint     "Off-pixel tint"    0.10 0.0 1.0 0.01
#pragma parameter bb_xtalk_signed "Crosstalk signed"  0.22 0.0 1.0 0.01
#pragma parameter bb_xtalk_gray   "Crosstalk gray"    0.40 0.0 1.0 0.01

layout(std140, set = 0, binding = 0) uniform UBO
{
    mat4 MVP;
    vec4 OriginalSize;
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
layout(set = 0, binding = 2) uniform sampler2D Original;
layout(set = 0, binding = 3) uniform sampler2D PassOutput0;   // crosstalk field

#include "inc/bb_panel.inc"

float lumaOf(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

vec3 shadeColor(int s)
{
    if (s <= 0) return vec3(param.bb_p0r, param.bb_p0g, param.bb_p0b);
    if (s == 1) return vec3(param.bb_p1r, param.bb_p1g, param.bb_p1b);
    if (s == 2) return vec3(param.bb_p2r, param.bb_p2g, param.bb_p2b);
    return vec3(param.bb_p3r, param.bb_p3g, param.bb_p3b);
}

// Recover the native shade from the core's output and map it through the
// profile palette. This replaces brickboy's texelFetch of the R16UI native
// framebuffer; everything downstream is identical.
vec3 decodeTexel(ivec2 coord)
{
    ivec2 sz = ivec2(global.OriginalSize.xy);
    coord = clamp(coord, ivec2(0), sz - 1);
    float l = lumaOf(texelFetch(Original, coord, 0).rgb);
    int shade = int(clamp(floor((1.0 - l) * 3.0 + 0.5), 0.0, 3.0));
    return shadeColor(shade);
}

void main()
{
    vec3 panelBg = vec3(param.bb_bg_r, param.bb_bg_g, param.bb_bg_b);
    vec2 aUv = (vTexCoord - BB_ACTIVE.xy) / BB_ACTIVE.zw;

    if (aUv.x < 0.0 || aUv.x >= 1.0 || aUv.y < 0.0 || aUv.y >= 1.0) {
        // Bare reflector margin: un-driven, so simply the paper colour. This is
        // also what the grid pass's drop-shadow lookup reads as "no caster here".
        FragColor = vec4(clamp(panelBg, 0.0, 1.0), 1.0);
        return;
    }

    ivec2 coord = ivec2(int(aUv.x * global.OriginalSize.x),
                        int(aUv.y * global.OriginalSize.y));
    vec3 rgb = decodeTexel(coord);

    // Inter-pixel bleed (STN smear).
    if (param.bb_bleed > 0.0) {
        vec3 nb = decodeTexel(coord + ivec2(-1, 0))
                + decodeTexel(coord + ivec2( 1, 0))
                + decodeTexel(coord + ivec2( 0,-1))
                + decodeTexel(coord + ivec2( 0, 1));
        rgb = mix(rgb, nb * 0.25, param.bb_bleed);
    }

    // Density: the physical DMG contrast wheel. Not a separation control - the
    // side wheel drives every pixel's LC bias together. 0.5 is neutral.
    if (param.bb_density > 0.5) {
        rgb = mix(rgb, shadeColor(3), (param.bb_density - 0.5) * 2.0);
    } else {
        rgb = mix(rgb, panelBg, (0.5 - param.bb_density) * 2.0);
    }

    // The lightest shade never fully clears the LC.
    if (param.bb_off_tint > 0.0) {
        float offW = smoothstep(0.5, 1.0, lumaOf(rgb));
        rgb = mix(rgb, shadeColor(3), param.bb_off_tint * param.bb_density * offW);
    }

    // Passive-matrix crosstalk from the pre-pass field.
    if (param.bb_crosstalk > 0.0) {
        float field = texture(PassOutput0, aUv).r;
        float tempMul = 1.0 + 2.0 * param.bb_temperature;
        float amt = param.bb_crosstalk * param.bb_density * tempMul * field;

        // Most visible on a mid-gray background, invisible on solid black/white.
        if (param.bb_xtalk_gray > 0.0) {
            float mg = 1.0 - abs(lumaOf(rgb) - 0.5) * 2.0;
            amt *= mix(1.0, clamp(mg, 0.0, 1.0), param.bb_xtalk_gray);
        }

        float darken = clamp(amt, 0.0, 0.65);
        rgb *= 1.0 - darken;

        // Real bleed shifts gray both ways, not purely down.
        if (param.bb_xtalk_signed > 0.0) {
            float pol = lumaOf(rgb) - 0.5;
            rgb += param.bb_xtalk_signed * darken * pol;
        }
    }

    rgb = pow(max(rgb, 0.0), vec3(param.bb_panel_gamma));

    float luma = lumaOf(rgb);
    rgb = mix(vec3(luma), rgb, param.bb_saturation);
    rgb += param.bb_warm * luma * vec3(0.5, 0.15, -0.4);

    rgb = (rgb - 0.5) * param.bb_contrast + 0.5;
    rgb *= param.bb_brightness;

    rgb = mix(rgb, panelBg, param.bb_black_lift);

    FragColor = vec4(clamp(rgb, 0.0, 1.0), 1.0);
}
