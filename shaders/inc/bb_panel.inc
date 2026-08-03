#ifndef BB_PANEL_INC
#define BB_PANEL_INC

// Module geometry, from brickboy src/display/pipeline.ts:
//   NATIVE 160x144, PANEL_MARGIN 4 -> module 168x152
//   ACTIVE_RECT = (margin/W, margin/H, native/W, native/H)
//
// The render target is the whole LCD module, so the dot field is inset by the
// exposed reflector margin on every side.

#define BB_NATIVE  vec2(160.0, 144.0)
#define BB_MARGIN  4.0
#define BB_MODULE  vec2(168.0, 152.0)
#define BB_ACTIVE  vec4(BB_MARGIN / BB_MODULE.x, BB_MARGIN / BB_MODULE.y, \
                        BB_NATIVE.x / BB_MODULE.x, BB_NATIVE.y / BB_MODULE.y)

#endif
