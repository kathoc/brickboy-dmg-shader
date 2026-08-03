# brickboy display pipeline — full specification

*A reference for re-implementing the exact same look, in any language, on top of any emulator core*

*Last updated: 2026-08-03*

*English translation of `display-pipeline.ja.md`. The Japanese file is the original; if the two disagree, trust it. The figures referenced below live in the brickboy repository and are not bundled here.*

---

## Preface — what this document is

**The look described here is not measured off real hardware.**

It starts from the author's **memory of the real thing** and is assembled by cross-checking **published specifications, technical write-ups and photographs found on the web**. Nothing here came off a spectrometer, and no response curve was taken with an oscilloscope.

So:

- **No number here carries a guarantee that the real unit was like this.** They are the result of tuning until it looked right.
- **Sourced and unsourced parts are mixed together.** Where something was taken from another implementation or from the literature — the colour-correction matrices, the boundary values — the source is named. Where it was decided by tuning, such as most of the texture work, it says "tuned".
- **Some conclusions were reached and later withdrawn.** Those are kept rather than deleted (§10), because as a record of traps to avoid they are more useful than the tidy version.

**If you are re-implementing this.** The goal of this document is "produce the same picture as brickboy", not "reproduce real hardware correctly". Those two overlap heavily, but they are not the same thing. If you have better measurements, prefer yours.

---

## Contents

1. [Overall structure](#1-overall-structure)
2. [PRE-PASS — per-column darkness](#2-pre-pass--per-column-darkness)
3. [PASS 1 — colour correction and the panel's electrical quirks](#3-pass-1--colour-correction-and-the-panels-electrical-quirks)
4. [PASS 2 — dot structure and reflector](#4-pass-2--dot-structure-and-reflector)
5. [PASS 3 — persistence](#5-pass-3--persistence)
6. [PASS 4 — ageing and faults](#6-pass-4--ageing-and-faults)
7. [PRESENT — finish](#7-present--finish)
8. [Every profile parameter](#8-every-profile-parameter)
9. [Things outside the display that change the look](#9-things-outside-the-display-that-change-the-look)
10. [Rejected and withdrawn](#10-rejected-and-withdrawn)
11. [How this gets verified](#11-how-this-gets-verified)
12. [Re-implementation checklist](#12-re-implementation-checklist)
13. [Sources](#13-sources)

---

## 1. Overall structure

All the emulator core produces is a **raw 160×144 framebuffer**: 2 bits of shade per pixel (0–3) for DMG, BGR555 for CGB/GBA. Everything after that is the display work, and it runs as **six passes in a fixed order**.

```
        core (160×144, R16UI)
              │
    ┌─────────┴──────────┐
    │ PRE-PASS  column   │  collapse to 160×1. raw material for crosstalk
    │           darkness │
    └─────────┬──────────┘
              ▼
    ┌────────────────────┐
    │ PASS 1  colour     │  shade→sRGB, density, crosstalk,
    │                    │  saturation, gamma, brightness, black lift
    └─────────┬──────────┘
              ▼
    ┌────────────────────┐
    │ PASS 2  dots       │  grid, reflector, drop shadow, paper grain
    └─────────┬──────────┘
              ▼
    ┌────────────────────┐
    │ PASS 3  persistence│  holds a per-pixel analog state
    └─────────┬──────────┘
              ▼
    ┌────────────────────┐
    │ PASS 4  faults     │  ageing. all default 0 (pass-through)
    └─────────┬──────────┘
              ▼
    ┌────────────────────┐
    │ PRESENT  finish    │  non-uniformity, grain, vignette
    └─────────┬──────────┘
              ▼
           screen (canvas)
```

### Why the order cannot change

**Persistence (PASS 3) comes after the dot structure (PASS 2).** What persists on real hardware is the state of the liquid crystal, not the gaps in the grid — but applying the grid afterwards lays a second grid over the persistence trail as well. Holding the already-gridded picture as the state lands closer to the real thing.

**Faults (PASS 4) come after persistence.** A dead line is a place where the crystal does not move, so it **does not persist**. Apply faults first and the dead lines smear.

**Crosstalk belongs to PASS 1.** It is an electrical phenomenon — pixels sharing a column electrode interfere — and quite separate from optical degradation, so it goes in while the colour is being decided.

### Implementation constraints that matter

- **Make the intermediate buffers floating point.** At 8 bits the exponential decay of the persistence quantises into steps.
- **Size the backing store to exactly the real device pixel count.** Leave a non-integer upscale to the browser or the OS and the composited dot grid gets resampled into **moiré**.
- **Persistence needs two buffers, ping-ponged** — you cannot read and write the same one.

---

## 2. PRE-PASS — per-column darkness

**Purpose**: build the raw material for passive-matrix crosstalk.

Collapse 160×144 down to **160×1**, the mean darkness of each column.

```glsl
// DMG: shade 0..3 -> darkness 0..1
darkness = min(native, 3) / 3.0

// CGB/GBA: darkness from the BGR555 sum
darkness = 1.0 - (r + g + b) / 93.0     // 31*3 = 93
```

Two things season that column profile.

**Per-column gain wobble** (`crosstalkNoise`): unit-to-unit variation in the driver IC. `hash21(col, seed)` gives each column a fixed wobble. It **does not vary over time** — re-rolling it every frame makes the picture boil.

**Edge-triggered banding** (`crosstalkEdge`): interference shows up hardest at light/dark boundaries. Take the difference against the neighbouring column and weight by it.

> **Why collapse to one dimension**: real crosstalk is "when other pixels in the same column are dark, the whole column is affected". Filter in two dimensions instead and you get a plain blur, which is a different phenomenon.

**The whole pass is skipped when crosstalk is 0.**

---

## 3. PASS 1 — colour correction and the panel's electrical quirks

### 3-1. Shade → sRGB

Three modes.

| Mode | For | Conversion |
|---|---|---|
| `dmg-lut` | DMG / Pocket / Light | shade 0–3 into a **4-entry palette** |
| `cgb-byuu` | GBC | BGR555 → sRGB, the **byuu/ares integer matrix** |
| `gba-byuu` | GBA family | byuu's GBA gamma (lcdGamma 4.0 / out 2.2 / ×255÷280) |

The CGB and GBA conversions are taken straight from **ares (`gb/ppu/color.cpp`, `gba/ppu/color.cpp`)**. That part is not tuning — it matches an existing implementation.

The DMG palette started from SameBoy's `GB_PALETTE_DMG` and was then tuned. **The current values have drifted from that starting point** (see §10-④).

### 3-2. Order of operations

**Change this order and the picture changes.** Applied top to bottom.

```
 1. shade -> sRGB (above)
 2. STN bleed (bleed)          mix neighbours at weight 0.25
 3. density dial (density)     0.5 is neutral
 4. off-pixel tint (offTint)
 5. crosstalk (crosstalk)
 6. panel gamma (panelGamma)   pow(rgb, y)
 7. saturation (saturation)    mix toward luma
 8. warm tint (warm)
 9. contrast (contrast)        (rgb - 0.5) * c + 0.5
10. brightness (brightness)    rgb *= b
11. black lift (blackLift)     mix toward the paper colour
```

### 3-3. The density dial (the wheel on the side of the real unit)

```glsl
if (density > 0.5) rgb = mix(rgb, palette[3], (density - 0.5) * 2.0);
else               rgb = mix(rgb, panelBg,    (0.5 - density) * 2.0);
```

**Shade 3 is the fixed point and everything else is pulled toward it.** Therefore:

- shade 3 mixes with itself and **does not move**
- shade 0 is furthest away and **moves the most**

Measured (luminance change from density 0.50 to 0.90):

| Shade | 0.50 | 0.90 | change |
|---|---|---|---|
| **0 (lightest)** | 0.4145 | 0.1663 | **−60%** |
| 1 | 0.3156 | 0.1655 | −48% |
| 2 | 0.1709 | 0.1318 | −23% |
| **3 (darkest)** | 0.1123 | 0.1008 | **−10%** |

This matches, in order as well as direction, what people who played on the real thing report: turning it up barely touches shade 3, and shade 0 moves most.

**Density moves the colour too.** The higher it goes the more the whole picture is pulled toward shade 3 (dark green), so it gets **darker and greener**.

| Density | 0.30 | 0.50 | 0.70 | 0.90 |
|---|---|---|---|---|
| whole-screen G/R | 0.93 | 1.00 | 1.12 | 1.18 |

> **Important**: **there is no "correct" density.** The right value depends on the viewing environment (§9-2). That is exactly why the real unit had a physical wheel — you do not fit one if a fixed value would do. brickboy defaults to 0.5, which means "neutral", not "right".

### 3-4. Crosstalk

Split into four components.

| Parameter | What it does |
|---|---|
| `crosstalk` | master strength. Sinks a whole column according to its darkness |
| `crosstalkSigned` | also works in the lightening direction (the real thing goes both ways) |
| `crosstalkGrayField` | most visible in the midtones (weighted by `grayField`) |
| `crosstalkEdge` | strongest at light/dark boundaries |
| `crosstalkNoise` | fixed per-column wobble (driver variation) |

**Cold makes it stronger** (`temperature`): a cold panel shows more crosstalk, applied as `tempMul`.

---

## 4. PASS 2 — dot structure and reflector

**This pass decides the impression more than any other.**

### 4-1. Raw frame versus rendered

**The raw 160×144 without even colour correction (four shades as plain grey):**

![raw framebuffer](images/display/01-native-tone.png)

**After the pipeline:**

![rendered](images/display/03-rendered-tone.jpg)

### 4-2. Dot structure, magnified

![dot structure](images/display/04-dot-structure.png)

*The grid page of the diagnostic ROM, magnified 4× with no interpolation.*

What is visible:

- **the dots are near-square with a gap on all four sides** (`pixelSize` is the fill fraction)
- **the gap shows the reflector colour** (`bgTint`). It is not a dark grid line
- **each dot casts a shadow down and to the right** (`shadowOffset` / `shadowBlur` / `shadowOpacity`)
- **a paper-like grain** lies over everything (`paper` / `paperScale`)
- **the grid is faint on light shades and strong on dark ones**

### 4-3. The colour of the gap

```glsl
vec3 gap = bgTint * (1.0 - shadowOpacity * 0.4);
vec3 gridded = mix(gap, mix(bgTint, lit, 1.0 - baselineAlpha), body);
```

**The gap is not "a dark line", it is "where the reflector shows through".** Darken it and a black grid lands on the light areas too, which is a different thing entirely.

Measured grid modulation (peak-to-trough over mean, on a flat light field):

| | real photo | brickboy shade 0 | brickboy shade 1 | brickboy shade 3 |
|---|---|---|---|---|
| grid visibility | 1.2% | **3.7%** | 17.3% | **31.4%** |

**Fainter when light, stronger when dark** is the physically correct direction — in the light state the pixel and the gap are the same reflecting surface.

### 4-4. Drop shadow

There is an **air gap** between the liquid crystal layer and the reflector, so dark dots cast a shadow onto the reflecting surface behind them.

- `shadowOffset` 1.35 (in native pixels) — how far it shifts toward the light
- `shadowBlur` 0.85 — blur radius
- `shadowOpacity` 0.34 — strength
- `shadowColor` — the shadow's colour, **not black, but a darkened reflector colour**

> Make the shadow black and it reads as print. All that is happening is that the reflecting surface got darker, so keep the colour close to the reflector.

### 4-5. The border outside the picture

There is structure outside the dot field too, and it is **drawn by the shader, not made of CSS margins**.

```
[dot field 160x144] -> exposed reflector ~0.7 dot -> printed mask ~2.2 dot -> module edge
```

Two reasons. **The reflector grain has to run continuously under the border or it looks fake.** And **the outermost dots need somewhere to cast their shadows**, which is that exposed strip. Between them, those two make the gap between the element plane and the sheet readable.

### 4-6. Subpixels (GBC/GBA only)

Colour units split the cell into R|G|B thirds vertically. **When one stripe falls below about 4 device pixels the amplitude is faded out** to prevent moiré (`SUB_CONTRAST = 0.55`, faded with `smoothstep(2.0, 5.0, ...)`).

---

## 5. PASS 3 — persistence

**Every pixel holds an analog state that relaxes exponentially toward its target.** This is not a frame blend.

```glsl
vec3 fall = step(target, state);              // is it heading darker
vec3 tau  = mix(vec3(tauRise), vec3(tauFall), fall);
vec3 a    = 1.0 - exp(-dt / tau);
state     = mix(state, target, a);
```

### 5-1. The time constants are asymmetric

| Direction | Physics | Speed |
|---|---|---|
| going dark (`tauFall`) | **driven** by voltage | **fast** |
| going light (`tauRise`) | voltage removed, **relaxes on its own** | **slow** |

```
tauRise = (8 + 102 x ghost.strength) x tempMul
tauFall = tauRise x 0.35
```

DMG has `ghost.strength = 0.52`, so **tauRise ≈ 61 ms and tauFall ≈ 21 ms**.

> **This used to be the wrong way round.** The slow side was assigned to "going dark", so a character appearing at its new position advanced only 21% in one frame while the place it had left cleared faster — the opposite of the real thing. It feels like "press the button, a beat passes, then the character moves", which is **easily misread as input lag** (the input path measured 0.57 frames and was not the main cause).

> **Unresolved**: contemporary STN modules are quoted at 100–200 ms response. brickboy's 61 ms is less than half that. But those figures are for general-purpose character-display modules, and it is hard to believe the panel chosen for a 60 fps games console was that slow. **Nothing can be settled here until the trail length is measured off real hardware footage.**

### 5-2. Temperature and warm-up

```
tempMul = (1 + 2 x temperature) x warmupMul
```

`warmupMul` eases from 1.6 to 1.0 over about 45 seconds from power-on: **a cold panel, or one just switched on, holds a longer trail**.

### 5-3. Gate

`ghostGate` (0.05 on DMG). When the difference from the target is small, snap to it. Without this a tiny residual lingers forever and the whole picture goes soft.

### 5-4. Implementation notes

**Use real elapsed time (ms) for dt** and clamp it, so a dropped frame does not jump the state.

**For offline rendering (video export and the like), fix dt.** brickboy fixes it at one frame = 16.742 ms (= 70224 ÷ 4194304 s). Render at any speed you like and the trail still looks right when the video is played back in real time.

**The history buffer starts black.** Capture straight away and the opening is a fade-in from black, so **throw away a few dozen frames first** to reach steady state. Forget that warm-up and your measurement baseline is wrong (§10-⑦).

---

## 6. PASS 4 — ageing and faults

**Everything defaults to 0**, i.e. a healthy panel passes straight through. Applied in this order:

```
1. global tone   dimming / frontlight / backlightBleed / contrastFade
2. polariser rot screenRot (two patterns)
3. dust/blemish  dust
4. dead lines    deadLineSeverity (vertical and horizontal)
```

### 6-1. Comparison

| healthy | polariser rot 0.45 |
|---|---|
| ![healthy](images/display/06-defect-pristine.jpg) | ![rot](images/display/06-defect-vinegar.jpg) |

| dead lines 0.25 | global dimming 0.4 |
|---|---|
| ![dead lines](images/display/06-defect-deadlines.jpg) | ![dimming](images/display/06-defect-dimming.jpg) |

### 6-2. Dead lines

**This is the part that needs the most work.** A ribbon-cable or heat-seal bond failure floats a column (or row) electrode.

| Element | Implementation |
|---|---|
| **which columns die** | per-column hash (depends on `seed`). Fixed in time |
| **edge bias** | `deadLineEdgeBias` 1.0 = they cluster at the bonded edge |
| **they come in bands** | low-frequency noise clumps them into runs of 2–5 |
| **colour** | mostly the reflector colour; a minority stay dark (`deadLineLit` 0.06) |
| **gradient along the line** | contact resistance fades it end to end (`gA`→`gB`, 0.55–1.0) |
| **flicker** | only the segments, about 5 px each, where the contact is marginal blink, at random |
| **soft edges** | feathered across the neighbouring column, so bands show no interior seam |
| **through the dots** | drawn through the grid: **a string of dots, not a bar** |
| **horizontal** | rows fail too (`deadLineRowRatio` 0.15 = rarer than vertical) |

Severity is **non-linear** (`sev^2.2`) so the low end stays usable: about 1 column at 0.1, about 7 at 0.25, and about 92% dead at 1.0.

> **There is no path that names coordinates and paints them.** There used to be a `deadColumns` (x, width, strength) route; it was removed. Why is in §10-②.

### 6-3. Polariser rot

Two patterns, switchable with `rotMode`:

- **1 (default)**: radial, invading from the centre outward. The classic "vinegar syndrome" look
- **0**: irregular amoeba-like blotches

`fbm` (stacked value noise) gives the outline its organic edge; `seed` fixes the position. **It does not vary over time.**

---

## 7. PRESENT — finish

Applied last, over the whole screen.

| Parameter | What | DMG value |
|---|---|---|
| `gradient` | low-frequency brightness non-uniformity | 0.08 |
| `grain` | matte grain (fixed hash) | 0.012 |
| `vignette` | corner darkening | 0.08 |
| `sheen` | reflection | **0 (deliberately off)** |
| `sheenHotspot` | the bright core of the reflection | **0 (same)** |

### Why no reflection is drawn

**Because the display you are looking at is already reflecting the room.**

Draw a synthetic reflection and it **doubles up** with the real one coming off the user's monitor, which reads as more fake, not less. The implementation is still there, but the DMG profile sets it to 0.

**If you are re-implementing this, carrying that decision over is recommended.** (Background in §10-①.)

---

## 8. Every profile parameter

Every value for DMG (`src/display/profiles/dmg.json`). The other models are written as deltas against it.

### 8-1. Colour

```json
"dmgPalette": [
  [0.86,  0.811, 0.533],   // shade 0 (lightest)
  [0.55,  0.70,  0.40 ],   // shade 1
  [0.28,  0.51,  0.26 ],   // shade 2
  [0.13,  0.36,  0.17 ]    // shade 3 (darkest)
],
"brightness": 0.88,
"contrast":   0.88
```

**The relative order of the channels** — the easiest thing to get wrong when re-implementing:

| Shade | R | G | B | G−R |
|---|---|---|---|---|
| 0 | 219 | 207 | 136 | **−12 (yellowish)** |
| 1 | 140 | 178 | 102 | +38 (green) |
| 2 | 71 | 130 | 66 | +59 (green) |
| 3 | 33 | 92 | 43 | +59 (green) |

The design is **yellower when light, greener when dark**. Measured across photographs of ten real units, the powered-off screen has a median G/R of 1.16 (range 0.81–1.89); brickboy's 0.86 sits inside that range (§10-④).

### 8-2. Grid

```json
"grid": {
  "strength": 0.62,
  "subpixel": false,
  "shadowOpacity": 0.6,
  "bgTint": [0.93, 0.85, 0.586]
}
```

### 8-3. Persistence

```json
"ghost": {
  "strength": 0.52,
  "riseFall": [0.45, 0.45, 0.45, 0.45],
  "gamma": 2.2,
  "gate": 0.05
}
```

### 8-4. Finish and texture

```json
"finish": {
  "sheen": 0, "sheenAngle": 28, "sheenHotspot": 0,
  "blackLift": 0.1,  "bleed": 0.16,
  "gradient": 0.08,  "grain": 0.012,  "vignette": 0.08,
  "saturation": 0.85, "warm": 0.06,   "panelGamma": 1.1,
  "shadowOffset": 1.35, "shadowBlur": 0.85, "shadowOpacity": 0.34,
  "shadowColor": [0.397, 0.391, 0.222],
  "paper": 0.01, "paperScale": 0.45,
  "maskSliver": 1.6, "maskWidth": 1.8, "maskRadius": 0.0,
  "maskColor": [0.392, 0.392, 0.275],
  "crosstalk": 0.34, "crosstalkSigned": 0.22,
  "crosstalkGrayField": 0.4, "crosstalkEdge": 0.4, "crosstalkNoise": 0.18,
  "offTint": 0.1, "density": 0.5
}
```

### 8-5. Faults (healthy by default)

```json
"defects": { "seed": 7 }
```

**The seed is a small value, 3–9.** Large values were measured not to break anything (tried up to 2.1 billion, maximum difference 1.03), but the tuning assumes small ones.

### 8-6. Per-model profiles

`dmg` / `pocket` / `light` / `gbc` / `gbc-ips` / `gba` / `gba-sp-001` / `gba-sp-101` / `micro`

| DMG | Pocket | GBC |
|---|---|---|
| ![dmg](images/display/05-panel-dmg.jpg) | ![pocket](images/display/05-panel-pocket.jpg) | ![gbc](images/display/05-panel-gbc.jpg) |

---

## 9. Things outside the display that change the look

### 9-1. Scaling mode

**Fill (default)**: stretch the game picture edge to edge and **let the reflector border and bezel run off-screen**. That matches how the real casing continues past the screen.

**Integer**: integer multiples. No blurring, but it only grows in steps, so there is letterboxing.

Either way, **size the backing store to exactly the real device pixel count**. Let the browser or OS do a non-integer upscale and the composited dot grid gets resampled into **moiré**.

### 9-2. The environment changes what you see (and cannot be reproduced)

**The same picture reads as a different colour in a different room.** That cannot be reproduced in the implementation, and should not be.

| Path | What |
|---|---|
| **Hunt effect** | at the same chromaticity, **higher luminance reads as more colourful** (a standard colour-appearance model, built into CIECAM02) |
| **Ratio against surface reflection** | stronger direct light means less achromatic mixture, so saturation rises |
| **Illuminant spectrum** | fluorescent mercury lines (405/436/**546**/578 nm, 546 being green) against the continuous spectrum of daylight put different colours through the same filter |
| **Density dial** | people turn it up in bright places, which makes it darker and greener |

**All four paths push in the same direction: the brighter the region, the greener it looks.** That accounts for "the real one was greener than this", and for the spread across photographs of real units, without having to invoke different panels.

---

## 10. Rejected and withdrawn

**This section may be the most useful one here.** Plausible conclusions were wrong repeatedly.

### ① Draw the reflection (sheen) → rejected

The reasoning was that a reflective LCD needs the room reflected in it, and that `sheen: 0` in the profile looked like an unfinished feature.

**Why rejected**: **the monitor doing the displaying is already reflecting the room.** Adding a synthetic one doubles it up and reads as more fake. `sheen: 0` was the correct setting.

### ② The "dead columns / dead pixels named by coordinate" route → deleted

There were `deadColumns` (x, width, strength) and `deadPixels` (x, y, state) routes that specified positions directly. **They were deleted.**

**Why**: no profile used them, the UI could not reach them, and the type definitions already said `deadLineSeverity` had superseded them. And **leaving them in invites the mistake** — which duly happened: a feature that adds random ageing used them because it wanted an exact line count, and threw away the entire worked-out look.

**What was different**:

| | `deadLineSeverity` (the worked-out one) | explicit (the deleted one) |
|---|---|---|
| colour | leakage differs per column | one flat reflector colour |
| edges | feathered across the neighbour | cut at the boundary. **a hard 1px line** |
| along the line | contact resistance fades end to end | **uniform top to bottom** |
| variation | marginal contacts blink per segment | **completely static** |
| dot structure | **a string of dots** through the grid | **a solid bar** ignoring the grid |
| width | clumps into 2–5px bands | **always exactly 1px** |
| position | biased to the edges (the real distribution) | **evenly spaced**. One line lands dead centre |

**Lesson**: never leave two routes to the same phenomenon. If one of them is the worked-out one, the other is nothing but a chance to misuse it.

### ③ Random ageing applied at every launch → removed

A feature that added unit-to-unit variation on each start, shipped on by default. **Removed.**

**The problem**: it used route ② above, so what appeared was **a hard straight line down the middle of the screen**, nothing like the worked-out dead lines. And because the "Dead lines" control stayed at 0, **there was a line on screen that the settings could not account for**.

**The tests were not working either.** They read a DOM string — a value the test itself had generated from the random source and written there — and **never looked at a single pixel**. All seven checks passed; a swapped-out mechanism is undetectable that way in principle.

**Lesson**: anything that changes what is on screen has to be **verified in pixels**. A test that reads DOM values or settings does not count as verification.

### ④ "The real panel's base colour is a strong green at G/R = 2.6" → withdrawn

From a single photograph of a powered-on unit, the conclusion was nearly drawn that brickboy's base colour (G/R 0.86) was red-dominant and therefore backwards.

**Why withdrawn**:

- that photo's EXIF said **saturation "high", auto white balance** (the EXIF was only checked after someone pointed it out)
- the second photo used for comparison was **a re-encoded blog image with the EXIF stripped entirely**, unusable as a colour reference
- re-measured across **ten powered-off units**, the range was G/R 0.81–1.89, making **2.6 an outlier**

**Lesson**: if you are going to talk about colour from photographs, **look at the EXIF first**. A number produced without checking white balance, saturation setting and colour space is not evidence.

### ⑤ "The colour direction is backwards versus real hardware" → arithmetic error

The conclusion was "real hardware loses green as it darkens, brickboy does the opposite". **Wrong.**

The metric `G−(R+B)/2` was being applied **without undoing the sRGB gamma**. Converted to linear, **the real photos and brickboy go the same way** (greener as it darkens).

**Lesson**: if you are talking about channel ratios, **always go back to linear light**. The darker the photo, the more the gamma exaggerates the ratio.

### ⑥ "There is no grid in the light areas" → misread resolution

In low-resolution blog images no grid was visible against a light background. **In the high-resolution originals it is plainly there.** It had simply been crushed away.

### ⑦ "The random seed is too large and breaks the shader" → disproved by measurement

The shader contains `int(uSeed * 1013.0)`, which is undefined past a 32-bit int. Profile seeds default to 3–9, but one feature was passing values up to 2.1 billion.

**Why disproved**: sweeping the seed from 3 to 2.1 billion, the **maximum difference against the baseline was 1.03, with zero columns over threshold**. Nothing was breaking.

Note that in the first version of that check, **the baseline's first frame was taken with a cold persistence buffer**, which produced a difference of 45 even between identical seeds. Adding the warm-up brought it to 0.00, and only then was the comparison meaningful.

### ⑧ "Fill the leftover area with the panel's base colour" → rejected

Against the problem of bands appearing when the window shape does not match, the proposal was to paint them in the base colour so they stop being visible.

**Why rejected**: the panel has a dark bezel and rounded corners, so **the seam stays visible anyway**. It **paints over the symptom without fixing the geometry**, and it makes the screen look wider than it is — actively harmful in a tool that sells itself on display fidelity.

---

## 11. How this gets verified

Looks are easy to argue about subjectively, so **whatever can be measured, is**.

### 11-1. The bundled diagnostic ROM

`public/roms/check.gb`, generated by `scripts/build-check-rom.mjs`. **It runs on real hardware too.**

| Page | What it shows |
|---|---|
| 1 TONE | four shades and a 2×2 dither. Colour correction and shadow crush |
| 2 GRID | 1px vertical/horizontal lines and a checkerboard. Dot structure, moiré, dead lines |
| 3 GHOST | a moving square beside a static one. **Lets you compare the amount of persistence side by side** |
| 4 INPUT | which buttons are down. Isolates whether input is arriving |
| 5 ALL ON | every dot lit. **No base colour mixed in, so you see the element's own colour** |

**Put it on a flash cart, display it on real hardware and photograph it, and you can line the two up directly.** That removes the biggest weakness of arguing colour from photographs — that the subject is different.

### 11-2. The render harness

`?renderfarm=1` mounts it in place of the normal UI and exposes, on `window.__rf`:

```js
__rf.init(panelId, scale, defects)   // init, with fault overrides
__rf.renderBatch(base64)             // raw framebuffers -> rendered pixels
```

**The display pipeline is literally the same object as the PWA's**, so the output is pixel identical to what is on screen. Nothing is ported to Node and nothing is implemented twice.

### 11-3. Automated tests

| Script | What it measures |
|---|---|
| `test/render-defects.mjs` | dead column count and luminance, handling of invalid values, re-render consistency |
| `test/check-rom.mjs` | whether the diagnostic ROM actually runs (8 checks) |
| `scripts/panel-color.py` | screen colour from a photograph (linear light, normalised against an achromatic patch in frame) |
| `scripts/make-display-figures.mjs` | generates the figures in this document |

### 11-4. Traps when measuring

- **Warm the persistence buffer up before measuring.** Capture cold and the first frame is darker, which shifts the baseline
- **Convert to linear light before taking ratios.** Ratios taken in sRGB are exaggerated
- **Check a photo's EXIF first.** Do not produce numbers without looking at white balance, saturation and colour space
- **Do not write tests that track the bundled ROM.** Swap the ROM and the verdict moves. Use a ROM you will not swap as the baseline

---

## 12. Re-implementation checklist

Building from scratch, confirm in this order.

**Structure**

- [ ] the six-pass order (column reduce → colour → grid → persistence → faults → finish)
- [ ] intermediate buffers are floating point
- [ ] persistence ping-pongs two buffers
- [ ] the backing store is exactly the device pixel count

**Colour (PASS 1)**

- [ ] DMG uses a 4-entry LUT; CGB/GBA use the byuu/ares conversions
- [ ] the 11-step order of operations (§3-2)
- [ ] density is a mix with shade 3 as the fixed point
- [ ] crosstalk is collapsed to one dimension (columns) before being applied

**Structure (PASS 2)**

- [ ] the gap is the reflector colour, not a dark line
- [ ] lighter shades show a fainter grid
- [ ] the drop shadow's colour is reflector-ish, not black
- [ ] the exposed reflector and printed mask outside the dot field are **drawn**
- [ ] colour models fade the subpixel amplitude out as the stripes get fine

**Persistence (PASS 3)**

- [ ] **going dark is fast, going light is slow** (do not invert this)
- [ ] dt is real time, clamped; fixed for offline rendering
- [ ] a gate for small differences
- [ ] warm up before capturing

**Faults (PASS 4)**

- [ ] everything defaults to 0 (a healthy panel)
- [ ] dead lines have **exactly one procedural route**; no coordinate-named route
- [ ] the seed does not vary with time (positions fixed; only the flicker moves)
- [ ] faults come **after** persistence

**Finish (PRESENT)**

- [ ] no reflection is drawn (the display is already reflecting)

**Verification**

- [ ] measure in pixels. Tests that read DOM values or settings do not count
- [ ] if you use photographs, look at the EXIF first
- [ ] take channel ratios in linear light

---

## 13. Sources

### Where the implementation comes from

| Subject | Source |
|---|---|
| CGB colour conversion | ares `gb/ppu/color.cpp` (byuu / near) |
| GBA colour conversion and gamma | ares `gba/ppu/color.cpp` (lcdGamma 4.0 / out 2.2 / ×255÷280) |
| DMG palette starting point | SameBoy `Core/display.c`, `GB_PALETTE_DMG`; off-pixel `#D2E6A6` |
| The dot-grid approach | libretro slang shader `handheld/gameboy` (`pixel_size` / `shadow_opacity` / `baseline_alpha` / `contrast`) |
| Audio high-pass coefficients | Pan Docs (DMG cf 0.999958 → 28.0 Hz, MGB/CGB cf 0.998943 → 706 Hz) |

### LCD technical references

- [Liquid Crystal Display Modes — Displaysino](https://www.displaysino.com/technologyDetails/Liquid-Crystal-Display-Modes.html) — STN yellow-green mode and blue mode
- [STN: Super Twisted Nematic — Phoenix Display](https://www.phoenixdisplay.com/technical-resources-category/super-twisted-nematic/) — birefringence gives a yellow-green base and blue characters
- [STN display — Wikipedia](https://en.wikipedia.org/wiki/STN_display) — 100–200 ms response, passive-matrix crosstalk
- [Hunt effect (color) — Wikipedia](https://en.wikipedia.org/wiki/Hunt_effect_(color)) — colourfulness rises with luminance
- [How Does Ambient Light Affect Perceived Contrast Ratio? — KTC](https://us.ktcplay.com/blogs/technology-hub/ambient-light-perceived-contrast-ratio) — ambient light lifts the black end
- [Sunlight-Readable Displays — VarTech](https://www.vartechsystems.com/articles/designing-operator-interfaces-bright-outdoor-conditions) — contrast loss in direct light
- [Colorimetric significance of mercury-emission lines in fluorescent lamps — JOSA](https://opg.optica.org/josa/abstract.cfm?uri=josa-65-11-1354) — the mercury lines in fluorescent lamps (546 nm)
- [The Effects of UV Light on LCD Degradation — Digi-Key Forum](https://forum.digikey.com/t/the-effects-of-uv-light-on-lcd-degradation/45820) — UV degradation of the polariser

### Real hardware construction

- [Replacing the reflector sheet in a Game Boy Pocket — kill-time DX](https://naokit.info/2025/03/10/%E3%82%B2%E3%83%BC%E3%83%A0%E3%83%9C%E3%83%BC%E3%82%A4%E3%83%9D%E3%82%B1%E3%83%83%E3%83%88%E3%81%AE%E5%8F%8D%E5%B0%84%E6%9D%BF/) — **the reflector is a silver, white sheet** (with photographs of the real part)
- [Polarization Film — Hand Held Legend](https://handheldlegend.com/products/polarization-film) — linear polariser, greenish cast
- [Replacement Polarizer Polarization Silver Reflector For Gameboy DMG — eBay](https://www.ebay.com/itm/196364250434) — how the replacement part is described
- [Repairing A Sunburned Game Boy Screen — Hackaday](https://hackaday.com/2018/01/26/repairing-a-sunburned-game-boy-screen/) — repairing a sun-damaged screen
- [Game Boy hardware database — Gekkio](https://gbhwdb.gekkio.fi/consoles/dmg/) — board revisions by unit
- [Game Boy Types — Modding Fridays](https://moddingfridays.bleu255.com/Game_Boy_Types) — eight mainboard revisions
- [Why the Game Boy Screen Was Green — Game Boy Museum](https://www.gameboymuseum.com/single-post/why-game-boy-screen-green) — why reflective STN was chosen

### Photographs of real units (used for the colour measurement; all Wikimedia Commons)

| File | Photographer | Licence |
|---|---|---|
| [Tetris on Game Boy.jpg](https://commons.wikimedia.org/wiki/File:Tetris_on_Game_Boy.jpg) | William Warby | CC BY 2.0 |
| [Nintendo Game Boy DMG-01 - LCD module-0004.jpg](https://commons.wikimedia.org/wiki/File:Nintendo_Game_Boy_DMG-01_-_LCD_module-0004.jpg) | Raimond Spekking | CC BY-SA 4.0 |
| [Nintendo Game Boy DMG-01-0246.jpg](https://commons.wikimedia.org/wiki/File:Nintendo_Game_Boy_DMG-01-0246.jpg) | Raimond Spekking | CC BY-SA 4.0 |
| [Game-Boy-FL.jpg](https://commons.wikimedia.org/wiki/File:Game-Boy-FL.jpg) / [FR](https://commons.wikimedia.org/wiki/File:Game-Boy-FR.jpg) / [Original](https://commons.wikimedia.org/wiki/File:Game-Boy-Original.jpg) | Evan-Amos | Public domain |
| [DMG-01.jpg](https://commons.wikimedia.org/wiki/File:DMG-01.jpg) | Chrisweird | CC BY-SA 3.0 |
| [Game Boy frontal 2026.jpg](https://commons.wikimedia.org/wiki/File:Game_Boy_frontal_2026.jpg) | Mark Gasoline | CC BY 4.0 |
| [Game Boy originale.jpg](https://commons.wikimedia.org/wiki/File:Game_Boy_originale.jpg) | Bontempi1953 | CC BY-SA 4.0 |
| [Nintendo Game Boy (1989) 1.jpg](https://commons.wikimedia.org/wiki/File:Nintendo_Game_Boy_(1989)_1.jpg) | Jzh2074 | CC BY-SA 4.0 |
| [Original Game Boy.jpg](https://commons.wikimedia.org/wiki/File:Original_Game_Boy.jpg) | Sammlung der Medien und Wissenschaft | CC BY 4.0 |

### Related documents in the repository

| Document | Content |
|---|---|
| [`docs/dmg-panel-color.md`](dmg-panel-color.en.md) | the colour measurement across ten real units, and the record of withdrawn hypotheses |
| `docs/hardware-profiles-research.md` | the basis for the per-model profiles (§1–§8) |
| `docs/lcd-stack-comparison.md` | comparison of the LCD stack's layers |
| `docs/lcd-realism-ideas.md` | every effect considered, marked adopted or not |
| `docs/audio-profiles-research.md` | the basis for the audio side |

### The source is the authority

The **authoritative** version of the numbers and formulas is the source code, not this document. Where they disagree, believe the source.

| File | Content |
|---|---|
| `src/display/shaders.ts` | the GLSL for every pass. Authoritative for the formulas |
| `src/display/pipeline.ts` | pass order, buffer management, time-constant derivation |
| `src/display/profiles/*.json` | every parameter, per model |
| `src/display/defects.ts` | fault parameter state |
| `src/display/types.ts` | what each parameter means (with comments) |

---

*Every figure here was generated from this repository by `scripts/make-display-figures.mjs`. Anyone who runs it gets the same pictures.*

*"Game Boy" is a trademark of Nintendo Co., Ltd. brickboy is not affiliated with them.*
