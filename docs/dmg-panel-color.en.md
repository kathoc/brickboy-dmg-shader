# Where the DMG screen's colour comes from — measured across photographs of ten real units

*Investigated 2026-08-02 / brickboy development record*

*English translation of `dmg-panel-color.ja.md`. The Japanese file is the original; if the two disagree, trust it. The figures referenced below live in the brickboy repository and are not bundled here.*

## What this document is

brickboy is a Game Boy emulator, but its main concern is **reproducing how the real panel looked**. This is the record of checking whether its colour settings are right, against photographs of real hardware.

**The conclusion first: no evidence was found that brickboy's colour is wrong.** Along the way, five plausible conclusions were reached and then withdrawn. That process is kept here too, because the traps involved in arguing colour from photographs are the record.

---

## 1. Where the question started

The developer's impression was that "something decisive is missing in the picture quality compared to the real thing". This was an attempt to identify what, in numbers rather than impressions.

---

## 2. How the real thing is built — where the green comes from

First, the physical layers that make the colour.

### The reflector is silver

A Japanese teardown article states it plainly, with photographs of the real part.

> the **silver thing stuck to the back of the LCD** where I peeled it away is the reflector
> the reflector is the **white sheet** underneath this flat cable
>
> — [Replacing the reflector sheet in a Game Boy Pocket (kill-time DX)](https://naokit.info/2025/03/10/%E3%82%B2%E3%83%BC%E3%83%A0%E3%83%9C%E3%83%BC%E3%82%A4%E3%83%9D%E3%82%B1%E3%83%83%E3%83%88%E3%81%AE%E5%8F%8D%E5%B0%84%E6%9D%BF/)

The replacement part is sold as "Back **Silver** Reflector". **The reflector itself has no colour.**

![DMG LCD module](images/dmg-panel/lcd-module.jpg)

*A bare LCD module. Photo: Raimond Spekking, [Nintendo Game Boy DMG-01 - LCD module-0004.jpg](https://commons.wikimedia.org/wiki/File:Nintendo_Game_Boy_DMG-01_-_LCD_module-0004.jpg), CC BY-SA 4.0*

### The colour comes from the polariser and the crystal's birefringence

- **Polariser**: the DMG uses a linear polarising film which is itself greenish (the replacement part says: "This film will have a **green tint** to it closer to the look of the DMG")
- **STN birefringence**: this was the decisive part. STN panels come in two standard families, "yellow-green mode" and "blue mode".

> the birefringence effect, which shifts the **background color to yellow-green** and the **character color to blue**
>
> — [Phoenix Display: Super Twisted Nematic](https://www.phoenixdisplay.com/technical-resources-category/super-twisted-nematic/)

**The DMG is yellow-green mode.** The base being yellow-green and lit pixels going bluish is an optical property of the liquid crystal cell itself. Producing green does not require a green reflector.

### In summary

```
ambient light -> front polariser (greenish linear) -> LC layer (STN, birefringent)
              -> silver reflector -> LC layer -> front polariser -> eye
```

**There is no "green reflector".** The yellow-green base is what you get when an achromatic reflecting surface picks up the colour of the polariser and the birefringence twice, on the way in and on the way out.

---

## 3. How this was measured

Arguing colour from photographs is dangerous: exposure, white balance and the camera's saturation setting move the appearance arbitrarily. Two rules were kept.

**Measure in linear light.** Undo the sRGB gamma. The darker the photo, the more the gamma exaggerates channel ratios. Skipping this produced a wrong conclusion once already (§7-③).

**Use an achromatic object in the same photograph as the white reference.** That cancels out auto white balance. The brightest, least saturated pixel outside the screen is picked automatically — usually the casing or the background paper.

The metrics are **G/R** and **B/R**. Being ratios, they are insensitive to exposure.

**The limit of this method: absolute values cannot be compared.** Even for the same real DMG, §4 (ten powered-off units) gives a median G/R of 1.16 while the photo in §5 (powered on, Tetris) gives 2.45–5.71 — **more than a factor of two apart.** Shooting conditions, whether the unit is powered, and how the white reference is chosen produce that spread. **Only the trend within a single image can be trusted**; lining up numbers from different photographs and arguing which is better is not possible. Most of the conclusions withdrawn in this document (§7) came from crossing that line.

Reproduction script: [`scripts/panel-color.py`](../scripts/panel-color.py)

```
python3 scripts/panel-color.py <image>
```

---

## 4. Measuring ten powered-off units

To see the colour of the reflector and polariser directly, the right thing to look at is **a screen displaying nothing**. Freely licensed photographs were collected from Wikimedia Commons.

![twelve powered-off screens](images/dmg-panel/off-screens-contact.png)

*The screen area was detected and cropped automatically from each photo. Top-left (background misdetected) and second on the top row (powered on) are excluded from the totals. Individual sources and licences in §10.*

| Unit | G/R | B/R |
|---|---|---|
| Game Boy frontal 2026 | 1.89 | 0.67 |
| Evan-Amos FL (studio) | 1.32 | 0.49 |
| Evan-Amos FR (studio) | 1.32 | 0.52 |
| Game-Boy-Original (studio) | 1.32 | 0.14 |
| Nintendo GB (1989) | 1.29 | 0.23 |
| DMG-01 | 1.03 | 0.05 |
| Spekking 0246 | 1.02 | 0.75 |
| bare LCD module | 0.96 | 0.56 |
| Original Game Boy | 0.93 | 0.42 |
| Game Boy originale | 0.81 | 0.19 |
| **median** | **1.16** | **0.46** |
| **brickboy (current)** | **0.86** | **0.38** |

### What this shows

**Blue is strongly suppressed on every unit.** B/R peaks at 0.75 with a median of 0.46 — **blue is less than half of red.** Not one unit had a reflector that could be called "a green with a lot of blue in it".

**Green and red are roughly balanced.** The median G/R is 1.16. The reality is not a strong green but **an ochre with a slight green cast**.

**brickboy sits inside the measured range.** G/R = 0.86 falls inside the observed 0.81–1.89 (between the 0.81 and 0.93 units). B/R = 0.38 is close to the 0.46 median as well.

---

## 5. Comparing the dot structure

Lined up at the same dot pitch. Real hardware on top, brickboy below.

![dot comparison](images/dmg-panel/dot-compare.png)

*Top: a real DMG. Photo: William Warby, [Tetris on Game Boy.jpg](https://commons.wikimedia.org/wiki/File:Tetris_on_Game_Boy.jpg), CC BY 2.0 / Bottom: brickboy's output*

A high-resolution photograph of the real thing (Olympus E-3, 4:4:4, quality 99). **The grid is plainly visible even on the light background.**

![real screen, high resolution](images/dmg-panel/real-screen.jpg)

*Photo: William Warby, [Tetris on Game Boy.jpg](https://commons.wikimedia.org/wiki/File:Tetris_on_Game_Boy.jpg), CC BY 2.0*

Differences that remain by eye:

- the real dots have **soft edges and no shadow**; brickboy has **sharp-cornered squares with a shadow down and to the right**
- the real screen is **full of scratches** (scuffs in the plastic window show as white streaks)
- the real one has **strong vignetting**

None of these has been quantified. An attempt to measure edge width was disturbed by the grid ripple and produced nothing significant.

---

## 6. The density dial as a variable

The real DMG has a **density (contrast) dial** on its side. The hypothesis tested here is that "the real one was greener" is **a memory of a unit with the dial turned up**.

### The physical basis

On a passive-matrix STN, the dial changes the drive bias into the crystal. That bias **also reaches unlit pixels**, so turning it up darkens the base colour too and pulls **the whole screen toward the lit colour, i.e. the element's own colour**. It moves the **colour**, not just the brightness.

brickboy models it like this:

```glsl
if (uDensity > 0.5) {
  rgb = mix(rgb, uDmgPalette[3], (uDensity - 0.5) * 2.0);  // whole screen toward the darkest shade
} else {
  rgb = mix(rgb, uPanelBg, (0.5 - uDensity) * 2.0);        // whole screen toward the paper colour
}
```

Shade 3 in the DMG profile is **(33, 92, 43)**, a deep green. So **turning the dial up pulls the whole screen green.**

### Measurement

Sweeping `?density=` and measuring the whole-screen mean in linear light.

| Density dial | G/R | B/R | mean luminance |
|---|---|---|---|
| 0.30 | 0.93 | 0.41 | 0.274 |
| 0.40 | 0.97 | 0.42 | 0.240 |
| **0.50 (default)** | **1.00** | 0.43 | 0.214 |
| 0.60 | 1.06 | 0.45 | 0.184 |
| 0.70 | 1.12 | 0.47 | 0.156 |
| **0.80** | **1.18** | 0.49 | 0.136 |

![density dial sweep](images/dmg-panel/dial-sweep.png)

*brickboy's output. The higher the dial, the darker and greener. At 0.80 text starts to get hard to read.*

### What this shows

**Turning the dial up moves monotonically toward green.** G/R goes 0.93 → 1.18.

**The 0.81–1.89 range measured in §4 is wide enough that the dial position alone accounts for a good part of it.** Absolute values still cannot be mapped onto each other (see below).

**B/R barely moves** (0.41 → 0.49). Turning the dial up does not produce "a green with a lot of blue", which is consistent with the real observations (median 0.46).

### So

The memory that "the real one was greener" is accounted for by **the dial having been set high**. Plenty of people would have turned it up for legibility, and that state is what gets remembered as "the green screen".

**The spread across units in §4 is likely to be the dial position at the time of the photograph rather than a difference in panels.** Since a photograph does not reveal the dial position, **this variable cannot be ignored when talking about colour.**

Note that this table is the whole-screen mean including displayed content, a different population from §4's base-colour-only figures. It is a table for reading trends, not absolute values.

### What happens to each shade

The report that "turning it up barely touches shade 3, and shade 0 moves most" was checked using the tone page of the diagnostic ROM (four shades as bars).

Luminance change from density 0.50 to 0.90 (linear light):

| Shade | 0.50 | 0.90 | change |
|---|---|---|---|
| **0 (lightest)** | 0.4145 | 0.1663 | **−60%** |
| 1 | 0.3156 | 0.1655 | −48% |
| 2 | 0.1709 | 0.1318 | −23% |
| **3 (darkest)** | 0.1123 | 0.1008 | **−10%** |

The colour change follows the same order (G/R, density 0.30 → 0.90):

| Shade | 0.30 | 0.90 | change |
|---|---|---|---|
| **0** | 0.84 | 1.18 | **+0.34** |
| 1 | 0.99 | 1.26 | +0.27 |
| 2 | 1.05 | 1.25 | +0.20 |
| **3** | 1.04 | 1.21 | +0.17 |

**Shade 3 barely moves and shade 0 moves most.** That matches the report right down to the ordering.

It falls out of the implementation necessarily. `mix(rgb, palette[3], t)` **takes shade 3 as a fixed point and pulls everything else toward it**, so shade 3 mixes with itself and does not change, while shade 0, being furthest away, moves most. This is structural agreement, not coincidence.

### Where to set the density — shade 0's visibility is the criterion

One report from someone who played on real hardware: "**in Japan, having shade 0 just barely visible was about right. In some regions you had to turn the density up until shade 0 was clearly visible or it was hard to see.**"

Shade 0 is **the shade most sensitive to density** (−60%, per the table above), so it makes sense as the criterion. How visible it gets was measured.

| Density | how visible shade 0's dots are against the base | mean luminance | screen G/R |
|---|---|---|---|
| 0.30 | 2.8%  effectively invisible | 174.9 | 0.87 |
| 0.50 | 2.8%  effectively invisible | 170.8 | 0.90 |
| 0.65 | 3.6%  effectively invisible | 148.8 | 0.99 |
| **0.80** | **6.0%  faintly visible** | 124.4 | **1.08** |
| **0.90** | **8.1%  clearly visible** | 111.9 | **1.16** |

"Just barely visible" corresponds to density 0.65–0.80, "clearly visible" to around 0.90. **Between those two settings the screen gets 25% darker and G/R moves from 0.99 to 1.16, toward green.**

**Getting darker and getting greener happen together**, so the impression is "a deep green screen". A difference in where the criterion is set becomes, directly, a difference in how it looks.

Note that "barely" and "clearly" are labels applied here to brickboy's rendering, **not a measurement of a human perceptual threshold.** The real threshold moves with ambient light.

### There is no "correct" density

From all of the above, **the right density depends on the viewing environment.** That is surely why the real unit had a physical wheel: you do not fit one if a fixed value would do.

This bears directly on brickboy's design decisions. **Trying to decide a "correct default" here is the wrong approach.** The optimum moves with the brightness of the user's room and of their monitor. brickboy has a way to change the density (swipe at the left edge of the screen), so leaving it to that is more sensible than moving the default.

### The limits of this section

All of the above measures **brickboy's behaviour**, not **a dial being turned on real hardware**. The explanation "the real one was greener = the dial was up" is consistent in direction, but it has not been verified against real hardware.

An earlier version of this section said "the median G/R of 1.16 across ten real units corresponds to a dial setting of 0.75–0.80". **That was withdrawn**, because absolute comparison does not hold (see the limits in §3).

---

## 7. Record of withdrawn hypotheses

**This may be the most useful section here.** Five plausible conclusions were wrong.

### ① "The reflection (sheen) is missing" → rejected

The reasoning was that a reflective LCD needs the room reflected in it. That `sheen` was 0 in the profile looked like supporting evidence.

**Why rejected**: the monitor doing the displaying is already reflecting the room. Drawing a synthetic reflection **doubles it up and reads as more fake**. `sheen: 0` was the correct setting.

### ② "The random seed is too large and breaks the shader" → disproved by measurement

The shader contains `int(uSeed * 1013.0)`, undefined past a 32-bit int. Profile seeds default to 3–9, but one feature was passing values up to 2.1 billion.

**Why disproved**: sweeping the seed from 3 to 2.1 billion, the maximum difference against the baseline was 1.03, with zero columns over threshold. **Nothing was breaking.**

### ③ "The colour direction is backwards versus real hardware" → arithmetic error

The conclusion was "real hardware loses green as it darkens, brickboy does the opposite".

**The cause**: the metric `G−(R+B)/2` was applied **without undoing the sRGB gamma**. Converted to linear, **the real photos and brickboy go the same way** (greener as it darkens).

### ④ "The real base is a strong green at G/R = 2.6" → bad sample selection

From a single photograph of a powered-on unit, the near-conclusion was that real hardware has green at 2.6× red while brickboy's 0.86 is red-dominant.

**The causes**:
- that photo's EXIF said **saturation "high", auto white balance** (checked only after being told)
- the second photo used for comparison was **a re-encoded blog image with the EXIF stripped entirely**, unusable as a colour reference
- re-measured across ten powered-off units, the range was 0.81–1.89, making **2.6 an outlier**

### ⑤ "There is no grid in the light areas" → misread resolution

In low-resolution blog images no grid was visible against a light background.

**The cause**: in the high-resolution originals it is **plainly there**. It had simply been crushed away.

---

## 8. Differences by production lot and market

**This was investigated, and no material supporting a difference in optical characteristics was found.**

- DMG-01 has **eight mainboard revisions** (DMG-CPU-01 to 08), with revisions to the LCD board, power board and jack board as well ([Game Boy Hardware Database](https://gbhwdb.gekkio.fi/consoles/dmg/) tracks these per unit)
- but the documented differences are **the CPU, how the RAM is mounted (epoxy blob or not) and the voltage regulator**; [Modding Fridays](https://moddingfridays.bleu255.com/Game_Boy_Types) likewise says the LCD board revisions are minor component and layout changes only
- **Game Boy Bros.** (released 1994-11-21) came in six colours, and no material suggests a panel change

The spread observed in §4 (G/R 0.81–1.89) is more naturally explained by **the density dial position at the time of the photograph (§6) and by ageing** than by lot differences. The casing used as the normalisation reference yellows with age, so **the more yellowed the unit, the more the correction over-pushes toward green**. That the three studio photographs with neutral backgrounds all land on 1.32 is suggestive, but three is not enough to settle it.

### Differences in the light environment explain it without differences in hardware

Even if the panels are identical, **regional differences in how it looks can still be explained.** There are four paths, and **all of them push the same way: the brighter the region, the greener it looks.**

**① The Hunt effect — brighter reads as more colourful**

At the same chromaticity, people perceive more colourfulness as luminance rises (R.W.G. Hunt, 1952; part of the standard colour-appearance model built into CIECAM02).

> The Hunt effect comprises an **increase in colorfulness of a color with increasing luminance**

A reflective LCD returns light in direct proportion to the ambient light. In strong sun the returned light rises by orders of magnitude, so **the same panel returning physically the same colour reads as greener.**

**② The ratio against surface reflection — how the light falls changes the saturation**

The returning image is coloured light that passed through the crystal twice; the surface reflection is achromatic. That ratio sets the saturation.

- strong direct light: the sun lights the screen while what reflects off the surface is a relatively dark sky → **coloured light dominates, the colour is strong**
- diffuse indoor light: the illuminating light and the reflected light both come from the ceiling → **achromatic mixture, the colour is weak**

**③ The illuminant spectrum differs**

The LCD stack is a narrow-band filter traversed twice, so its transmission is squared and it picks up peaks and troughs in the illuminant spectrum strongly. In the DMG's era, Japanese homes were mostly lit by fluorescent lamps, which carry mercury emission lines (405 / 436 / **546** / 578 nm), and **546 nm is a green line**. Continuous daylight and line-heavy fluorescent light put different colours through the same filter (metamerism).

**④ Where the density dial is set**

In bright places the surface reflection crushes the shades, so people turn the density up to separate them again. As §6 shows, turning it up makes the screen darker and greener.

### What this implies for measurement

**The Hunt effect works on the photographer's eye but not on the camera's sensor.** The difference in illuminant spectrum, on the other hand, **does reach the sensor.** So it becomes even more likely that the distribution in §4 (G/R 0.81–1.89) was **measuring differences in shooting environment**, not differences in panels.

**The conclusion that "there is no single correct value" is thereby better supported.**

**Panel differences remain unresolved.** Settling that needs units of known manufacturing date, photographed under matched conditions. But as above, **explaining the spread does not require invoking a difference in panels.**

---

## 9. Conclusion

**No basis was found for changing brickboy's screen colour.** The current G/R = 0.86 / B/R = 0.38 sits inside the range observed across ten real units.

What was established:

- **the reflector is silver** and has no colour of its own
- the yellow-green base comes from **the polariser's colour and the STN birefringence** (yellow-green mode)
- on the real screen, **blue is less than half of red**. It is not "a green with a lot of blue"
- **turning the density dial up pulls the whole screen green**. The real median corresponds to a dial around 0.75–0.80
- the spread between real units is explained by **shooting environment and dial position**. **There is no single correct value**
- **the right density depends on the viewing environment** (the Hunt effect, surface reflection, illuminant spectrum and dial setting all push toward "the brighter the region, the greener it looks"). That is also why the real unit had a physical wheel

What remains:

- **verification on real hardware**. The diagnostic ROM (`public/roms/check.gb`) runs on real hardware. Put it on a flash cart, display it on a real DMG and photograph it, and **the same content** can be lined up. The four shades appear as bars and page 5 lights every dot, so the shades can be compared directly. That removes most of the uncertainty in arguing colour from photographs — exposure, white balance, saturation, different subjects
- **the persistence time constant**. brickboy relaxes at 61 ms (`8 + 102 × ghost.strength`). Contemporary STN modules are quoted at 100–200 ms. Measuring trail length off real hardware footage would settle it objectively
- **how hard the dots are**. The real ones have soft edges and no shadow. Light spreading on a diffuse reflecting surface may not be modelled

To decide colour from photographs, what is needed is real hardware shot with **fixed white balance, standard saturation and a grey card in frame**. Without that, this kind of argument goes in circles.

---

## 10. Sources and image licences

### Technical references

- [Liquid Crystal Display Modes — Displaysino](https://www.displaysino.com/technologyDetails/Liquid-Crystal-Display-Modes.html) — yellow-green mode and blue mode
- [STN: Super Twisted Nematic — Phoenix Display](https://www.phoenixdisplay.com/technical-resources-category/super-twisted-nematic/) — birefringence gives a yellow-green base and blue characters
- [Replacing the reflector sheet in a Game Boy Pocket — kill-time DX](https://naokit.info/2025/03/10/%E3%82%B2%E3%83%BC%E3%83%A0%E3%83%9C%E3%83%BC%E3%82%A4%E3%83%9D%E3%82%B1%E3%83%83%E3%83%88%E3%81%AE%E5%8F%8D%E5%B0%84%E6%9D%BF/) — the silver reflector, the white sheet
- [Polarization Film — Hand Held Legend](https://handheldlegend.com/products/polarization-film) — linear polariser, greenish cast
- [Replacement Polarizer Polarization Silver Reflector For Gameboy DMG — eBay](https://www.ebay.com/itm/196364250434)
- [Game Boy hardware database — Gekkio](https://gbhwdb.gekkio.fi/consoles/dmg/) — board revisions by unit
- [Game Boy Types — Modding Fridays](https://moddingfridays.bleu255.com/Game_Boy_Types) — eight mainboard revisions
- [Hunt effect (color) — Wikipedia](https://en.wikipedia.org/wiki/Hunt_effect_(color)) — colourfulness rises with luminance
- [How Does Ambient Light Affect Perceived Contrast Ratio? — KTC](https://us.ktcplay.com/blogs/technology-hub/ambient-light-perceived-contrast-ratio) — ambient light lifts the black end
- [Colorimetric significance of mercury-emission lines in fluorescent lamps — JOSA](https://opg.optica.org/josa/abstract.cfm?uri=josa-65-11-1354) — mercury lines in fluorescent lamps (546 nm)
- [Repairing A Sunburned Game Boy Screen — Hackaday](https://hackaday.com/2018/01/26/repairing-a-sunburned-game-boy-screen/) — UV degradation of the polariser
- [Why the Game Boy Screen Was Green — Game Boy Museum](https://www.gameboymuseum.com/single-post/why-game-boy-screen-green) — why reflective STN was chosen

### Photographs used (all Wikimedia Commons)

| File | Photographer | Licence |
|---|---|---|
| [Nintendo Game Boy DMG-01 - LCD module-0004.jpg](https://commons.wikimedia.org/wiki/File:Nintendo_Game_Boy_DMG-01_-_LCD_module-0004.jpg) | Raimond Spekking | CC BY-SA 4.0 |
| [Nintendo Game Boy DMG-01-0246.jpg](https://commons.wikimedia.org/wiki/File:Nintendo_Game_Boy_DMG-01-0246.jpg) | Raimond Spekking | CC BY-SA 4.0 |
| [Tetris on Game Boy.jpg](https://commons.wikimedia.org/wiki/File:Tetris_on_Game_Boy.jpg) | William Warby | CC BY 2.0 |
| [Game-Boy-FL.jpg](https://commons.wikimedia.org/wiki/File:Game-Boy-FL.jpg) | Evan-Amos | Public domain |
| [Game-Boy-FR.jpg](https://commons.wikimedia.org/wiki/File:Game-Boy-FR.jpg) | Evan-Amos | Public domain |
| [Game-Boy-Original.jpg](https://commons.wikimedia.org/wiki/File:Game-Boy-Original.jpg) | Evan-Amos | Public domain |
| [DMG-01.jpg](https://commons.wikimedia.org/wiki/File:DMG-01.jpg) | Chrisweird | CC BY-SA 3.0 |
| [Game Boy frontal 2026.jpg](https://commons.wikimedia.org/wiki/File:Game_Boy_frontal_2026.jpg) | Mark Gasoline | CC BY 4.0 |
| [Game Boy originale.jpg](https://commons.wikimedia.org/wiki/File:Game_Boy_originale.jpg) | Bontempi1953 | CC BY-SA 4.0 |
| [Nintendo Game Boy (1989) 1.jpg](https://commons.wikimedia.org/wiki/File:Nintendo_Game_Boy_(1989)_1.jpg) | Jzh2074 | CC BY-SA 4.0 |
| [Original Game Boy.jpg](https://commons.wikimedia.org/wiki/File:Original_Game_Boy.jpg) | Sammlung der Medien und Wissenschaft | CC BY 4.0 |

**The composite figures in this document** (under `images/dmg-panel/`) are crops and arrangements of the photographs above. Because they include CC BY-SA 4.0 material, **treat the composites as CC BY-SA 4.0** (original authors as in the table). The parts that are brickboy's own output are Apache-2.0, as part of brickboy.

Note that the close-up images from a blog referenced early in this investigation **could not be confirmed as redistributable and had their EXIF stripped**, so they are neither included here nor used as evidence for colour.

---

*"Game Boy" is a trademark of Nintendo Co., Ltd. brickboy is not affiliated with them.*
