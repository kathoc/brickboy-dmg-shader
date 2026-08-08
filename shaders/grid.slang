#version 450

// Ported from brickboy src/display/shaders.ts FRAG_GRID.
//
// Synthesises the LCD dot structure at the displayed resolution, then lays the
// pixel drop-shadow (air-gap depth) and the reflector sheet grain over it, and
// paints the printed border outside the aperture.

layout(push_constant) uniform Push
{
    float bb_strength;
    float bb_shadow_opacity;
    float bb_pixel_size;
    float bb_baseline_alpha;
    float bb_grid_contrast;
    float bb_bg_r, bb_bg_g, bb_bg_b;
    float bb_gap_r, bb_gap_g, bb_gap_b;
    float bb_drop_offset;
    float bb_drop_blur;
    float bb_drop_opacity;
    float bb_drop_r, bb_drop_g, bb_drop_b;
    float bb_paper;
    float bb_mask_sliver;
    float bb_mask_width;
    float bb_mask_radius;
    float bb_sliver_gain;
    float bb_mask_r, bb_mask_g, bb_mask_b;
} param;

#pragma parameter bb_strength       "Grid strength"       0.62 0.0 1.0 0.01
#pragma parameter bb_shadow_opacity "Grid gap darkness"   0.60 0.0 1.0 0.01
#pragma parameter bb_pixel_size     "Dot fill"            0.80 0.3 1.0 0.01
#pragma parameter bb_baseline_alpha "Unlit dot opacity"   0.10 0.0 1.0 0.01
#pragma parameter bb_grid_contrast  "Grid contrast"       0.95 0.5 1.5 0.01
#pragma parameter bb_bg_r "Panel bg R" 0.930 0.0 1.0 0.002
#pragma parameter bb_bg_g "Panel bg G" 0.850 0.0 1.0 0.002
#pragma parameter bb_bg_b "Panel bg B" 0.586 0.0 1.0 0.002
// The gap colour is shade 0 x gapGain (the profile palette[0], gain 1.0). It is
// NOT the bare reflector - see the derivation at the use site.
#pragma parameter bb_gap_r "Gap R (shade 0)" 0.860 0.0 1.0 0.002
#pragma parameter bb_gap_g "Gap G (shade 0)" 0.811 0.0 1.0 0.002
#pragma parameter bb_gap_b "Gap B (shade 0)" 0.533 0.0 1.0 0.002
#pragma parameter bb_drop_offset  "Air-gap depth"     1.35 0.0 4.0 0.05
#pragma parameter bb_drop_blur    "Shadow blur"       0.85 0.0 3.0 0.05
#pragma parameter bb_drop_opacity "Shadow opacity"    0.34 0.0 1.0 0.01
#pragma parameter bb_drop_r "Shadow R" 0.397 0.0 1.0 0.002
#pragma parameter bb_drop_g "Shadow G" 0.391 0.0 1.0 0.002
#pragma parameter bb_drop_b "Shadow B" 0.222 0.0 1.0 0.002
#pragma parameter bb_paper        "Reflector grain"   0.03 0.0 0.3 0.005
#pragma parameter bb_mask_sliver  "Bare sliver px"    1.60 0.0 6.0 0.1
#pragma parameter bb_mask_width   "Mask width px"     1.80 0.0 8.0 0.1
#pragma parameter bb_mask_radius  "Mask radius px"    0.00 0.0 6.0 0.1
#pragma parameter bb_sliver_gain  "Sliver gain"       1.00 0.5 1.5 0.01
#pragma parameter bb_mask_r "Mask R" 0.392 0.0 1.0 0.002
#pragma parameter bb_mask_g "Mask G" 0.392 0.0 1.0 0.002
#pragma parameter bb_mask_b "Mask B" 0.275 0.0 1.0 0.002

layout(std140, set = 0, binding = 0) uniform UBO
{
    mat4 MVP;
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
layout(set = 0, binding = 2) uniform sampler2D Source;    // colour-corrected
layout(set = 0, binding = 3) uniform sampler2D GrainTex;  // baked reflector grain

#include "inc/bb_panel.inc"

float lumaOf(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

// Darkness (0 light .. 1 dark) of the LC ink casting onto this point, sampled
// off native px toward the light with a blur-px penumbra.
float casterDark(vec2 uv, vec2 texel, vec2 dir, float off, float blur)
{
    vec2 c = uv + off * texel * dir;
    float sd = 1.0 - lumaOf(texture(Source, c).rgb);
    if (blur > 0.0) {
        vec2 b = blur * texel;
        sd = (sd
          + (1.0 - lumaOf(texture(Source, c + b).rgb))
          + (1.0 - lumaOf(texture(Source, c - b).rgb))
          + (1.0 - lumaOf(texture(Source, c + vec2(b.x, -b.y)).rgb))
          + (1.0 - lumaOf(texture(Source, c - vec2(b.x, -b.y)).rgb))) * 0.2;
    }
    return sd;
}

void main()
{
    vec3 bgTint    = vec3(param.bb_bg_r, param.bb_bg_g, param.bb_bg_b);
    vec3 maskColor = vec3(param.bb_mask_r, param.bb_mask_g, param.bb_mask_b);

    vec2 aUv = (vTexCoord - BB_ACTIVE.xy) / BB_ACTIVE.zw;

    // Point on the reflector sheet in native pixels, continuous across the dot
    // field and the border, so the grain runs uninterrupted under the aperture
    // edge - the cue that it is one physical sheet lying behind everything.
    vec2 pRef = aUv * BB_NATIVE;

    // Signed distance in native px from the aperture edge, rounded rectangle.
    float rad = param.bb_mask_radius;
    vec2 hs = BB_NATIVE * 0.5;
    vec2 q = abs(pRef - hs) - (hs - vec2(rad));
    float sd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rad;
    bool inActive = sd < 0.0;

    float sliverEnd = param.bb_mask_sliver;
    float maskEnd   = sliverEnd + param.bb_mask_width;
    float maskCov = smoothstep(sliverEnd, sliverEnd + 0.35, sd);
    float edgeCov = smoothstep(maskEnd, maskEnd + 0.35, sd);

    vec3 outc;
    if (!inActive) {
        vec3 border = mix(bgTint * param.bb_sliver_gain, maskColor, maskCov);
        outc = mix(border, maskColor * 0.5, edgeCov);
    } else {
        vec3 base = texture(Source, vTexCoord).rgb;

        vec2 cc   = aUv * BB_NATIVE;
        vec2 cell = fract(cc);
        vec2 fw   = fwidth(cc) + 1e-4;

        // The dot fills bb_pixel_size of the cell. The edge is never narrower
        // than one device pixel, so a cell shrunk below the resolution limit is
        // prefiltered instead of aliasing.
        float margin = clamp((1.0 - param.bb_pixel_size) * 0.5 + 0.10, 0.0, 0.42);
        vec2 e = max(vec2(margin), fw);
        vec2 m = smoothstep(vec2(0.0), e, cell) * smoothstep(vec2(0.0), e, 1.0 - cell);
        float body = m.x * m.y;

        // The gap is where no electrode covers the sheet, so its light goes
        // through UN-DRIVEN LC and back off the reflector - a path at least as
        // open as the off pixel's. That is shade 0 (x gapGain, 1.0 here), which
        // makes "the gap is never darker than shade 0" structural rather than
        // something the tuned numbers happen to satisfy.
        //
        // It used to be bgTint darkened by the grid shadow opacity, wrong in
        // both terms: bgTint is the BARE reflector, a different optical path
        // that measures darker than shade 0 on real hardware, and darkening it
        // again drew a dark grid over the light shades. On the panel the mesh is
        // LIGHT over dark pixels and nearly invisible on a light field.
        vec3 gap = vec3(param.bb_gap_r, param.bb_gap_g, param.bb_gap_b);
        vec3 gridded = mix(gap, mix(bgTint, base, 1.0 - param.bb_baseline_alpha), body);

        gridded = (gridded - 0.5) * param.bb_grid_contrast + 0.5;
        outc = mix(base, gridded, param.bb_strength);
    }

    // Pixel drop-shadow (air-gap depth), applied on top of the dot structure and
    // of the bare sliver in one pass, so the shadows the outermost elements throw
    // run past the aperture onto the sliver. That overhang - a shadow seen
    // detached from its caster - is what makes the gap readable.
    //
    // Two layers, because a real air gap under diffuse room light throws both:
    //   near = the sharp umbra just off the element, offset ~= the gap
    //   far  = a broad soft penumbra at ~2.4x, weaker - the depth cue
    if (param.bb_drop_opacity > 0.0) {
        vec2 texel = BB_ACTIVE.zw / BB_NATIVE;
        // Light upper-left. vTexCoord is y-down here, so "up" is -y.
        const vec2 lightDir = vec2(-0.70710678, -0.70710678);

        float near = casterDark(vTexCoord, texel, lightDir,
                                param.bb_drop_offset, param.bb_drop_blur);
        float far  = casterDark(vTexCoord, texel, lightDir,
                                param.bb_drop_offset * 2.4,
                                max(param.bb_drop_blur, 0.25) * 2.6);
        near = smoothstep(0.40, 0.75, near);
        far  = smoothstep(0.34, 0.80, far);

        float own = smoothstep(0.40, 0.75, 1.0 - lumaOf(outc));
        float amt = param.bb_drop_opacity * (1.0 - own) * (1.0 - maskCov)
                  * clamp(near + 0.45 * far, 0.0, 1.0);
        outc = mix(outc, vec3(param.bb_drop_r, param.bb_drop_g, param.bb_drop_b),
                   clamp(amt, 0.0, 1.0));
    }

    // Reflector grain, applied last and multiplicatively. It is a reflectance
    // variation of the sheet seen through the LC, so it scales whatever light
    // comes back: plain on the light shades and the bare sliver, all but
    // invisible in the dark ink. Hidden under the printed mask, which is in
    // front of the sheet. Hue wobble is ~1/3 of the luminance wobble.
    if (param.bb_paper > 0.0) {
        float g = (texture(GrainTex, vTexCoord).r * 2.0 - 1.0) * (1.0 - maskCov);
        outc *= 1.0 + param.bb_paper * g;
        outc += param.bb_paper * g * 0.33 * lumaOf(outc) * vec3(0.5, 0.0, -0.5);
    }

    FragColor = vec4(clamp(outc, 0.0, 1.0), 1.0);
}
