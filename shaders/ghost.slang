#version 450

// Ported from brickboy src/display/shaders.ts FRAG_GHOST.
//
// LCD persistence as a per-pixel ANALOG STATE. The feedback texture IS the
// panel's analog LC state; each frame it relaxes toward the freshly-gridded
// target:  state += (target - state) * (1 - exp(-dt / tau))
//
// Direction-dependent tau is the core STN cue. The GB panel is normally white
// (no voltage = light reflector). Driving it dark twists the molecules and is
// FAST; letting it go light is elastic relaxation and is SLOW. So the trail is
// on the lightening side - behind a sprite that has left, not in front of it.
//
// Adaptation: brickboy feeds real elapsed ms. RetroArch gives no frame time, so
// dt is fixed at one GB frame (16.742 ms), which is what brickboy's own offline
// render harness does.
//
// tau derivation, from src/display/pipeline.ts:
//   tauRelax = (8 + 102 * ghost.strength) * (1 + 2 * temperature)
//   tauDrive = tauRelax * 0.35

layout(push_constant) uniform Push
{
    float bb_ghost_strength;
    float bb_temperature;
    float bb_ghost_gamma;
    float bb_ghost_gate;
} param;

#pragma parameter bb_ghost_strength "Ghost strength"  0.52 0.0 1.0 0.01
#pragma parameter bb_temperature    "Panel cold"      0.00 0.0 1.0 0.01
#pragma parameter bb_ghost_gamma    "Ghost gamma"     2.20 1.0 3.0 0.05
#pragma parameter bb_ghost_gate     "Ghost gate"      0.05 0.0 0.5 0.01

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
layout(set = 0, binding = 2) uniform sampler2D Source;         // post-grid target
layout(set = 0, binding = 3) uniform sampler2D PassFeedback3;  // the LC state

const float BB_DT_MS = 16.742;   // one GB frame

void main()
{
    vec3 target = texture(Source, vTexCoord).rgb;
    vec3 state  = texture(PassFeedback3, vTexCoord).rgb;

    float tempMul  = 1.0 + 2.0 * param.bb_temperature;
    float tauRelax = (8.0 + 102.0 * param.bb_ghost_strength) * tempMul;
    float tauDrive = tauRelax * 0.35;

    // step(target, state) = 1 where state >= target (darkening) -> tauDrive.
    vec3 fall = step(target, state);
    vec3 tau  = mix(vec3(tauRelax), vec3(tauDrive), fall);
    vec3 a    = 1.0 - exp(-vec3(BB_DT_MS) / tau);

    // Luminance-delta gate: tiny frame-to-frame deltas settle near-instantly so
    // static content stays crisp; only real motion keeps the slow trail.
    if (param.bb_ghost_gate > 0.0) {
        float snap = 1.0 - smoothstep(0.0, param.bb_ghost_gate, length(target - state));
        a = mix(a, vec3(1.0), snap);
    }

    // Relax in a transmittance (gamma) space so mid-gray trails carry the right
    // weight. 1.0 = identity.
    vec3 outc;
    if (param.bb_ghost_gamma != 1.0) {
        vec3 tg = pow(max(target, 0.0), vec3(param.bb_ghost_gamma));
        vec3 st = pow(max(state,  0.0), vec3(param.bb_ghost_gamma));
        outc = pow(max(st + (tg - st) * a, 0.0), vec3(1.0 / param.bb_ghost_gamma));
    } else {
        outc = state + (target - state) * a;
    }

    FragColor = vec4(outc, 1.0);
}
