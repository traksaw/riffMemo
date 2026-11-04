---
name: RiffMemo
description: Dark, quiet, numbers like an instrument. Color only where it means something.
colors:
  ground: "#0E0E11"
  surface: "#17171C"
  raised: "#212128"
  text: "#EDEDF0"
  text-secondary: "#9A9AA3"
  text-tertiary: "#6E6E78"
  recording: "#FF453A"
  in-tune: "#30D158"
  warning: "#FFB340"
  divider: "rgba(255,255,255,0.07)"
  hairline: "rgba(255,255,255,0.12)"
  ring: "rgba(255,255,255,0.20)"
typography:
  readout:
    fontFamily: "SF Mono"
    fontSize: "56px"
    fontWeight: 200
    lineHeight: "60px"
    letterSpacing: "-1.5px"
    fontFeature: "tnum"
  readout-small:
    fontFamily: "SF Mono"
    fontSize: "17px"
    fontWeight: 300
    fontFeature: "tnum"
  title:
    fontFamily: "SF Pro"
    fontSize: "22px"
    fontWeight: 600
    lineHeight: "28px"
    letterSpacing: "-0.3px"
  body:
    fontFamily: "SF Pro"
    fontSize: "16px"
    fontWeight: 400
  body-emphasis:
    fontFamily: "SF Pro"
    fontSize: "16px"
    fontWeight: 500
  secondary:
    fontFamily: "SF Pro"
    fontSize: "13px"
    fontWeight: 400
  meta:
    fontFamily: "SF Mono"
    fontSize: "12px"
    fontWeight: 400
    fontFeature: "tnum"
  label:
    fontFamily: "SF Mono"
    fontSize: "11px"
    fontWeight: 400
    letterSpacing: "0.8px"
rounded:
  swatch: "8px"
  group: "16px"
  panel: "20px"
  pill: "9999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  gutter: "16px"
  section: "22px"
components:
  button-primary:
    backgroundColor: "{colors.text}"
    textColor: "{colors.ground}"
    typography: "{typography.body-emphasis}"
    rounded: "{rounded.pill}"
    height: "52px"
    padding: "0 22px"
  button-record:
    backgroundColor: "{colors.recording}"
    rounded: "{rounded.pill}"
    size: "88px"
  button-tool:
    backgroundColor: "{colors.raised}"
    textColor: "{colors.text}"
    typography: "{typography.readout-small}"
    rounded: "{rounded.pill}"
    size: "64px"
  button-icon:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text}"
    rounded: "{rounded.pill}"
    size: "44px"
  chip-selected:
    backgroundColor: "{colors.text}"
    textColor: "{colors.ground}"
    rounded: "{rounded.pill}"
    height: "44px"
    padding: "0 14px"
  chip-unselected:
    textColor: "{colors.text}"
    rounded: "{rounded.pill}"
    height: "44px"
    padding: "0 14px"
  list-group:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.group}"
  list-row:
    textColor: "{colors.text}"
    typography: "{typography.body}"
    height: "52px"
    padding: "0 14px"
---

# Design System: RiffMemo

> **Status (2026-11-04).** This file is the target, taken from the "RiffMemo system" and "Motion spec" boards on the [design canvas](https://claude.ai/artifact/9qMfxvGLxzCS8SmzMMMgqq). The app code does not follow it yet: it still uses system purple and blue and rounded fonts up to 120 pt. Build work moves the code to this file. Where code and this file disagree, this file wins. Product truth lives in `PRODUCT.md`.

## Overview

**Creative North Star: "The Quiet Instrument"**

RiffMemo is a tool you play, not a screen you look at. It reads like a hardware tuner or a looper pedal at night: a near-black body, a few large monospaced numbers, and one red button that matters more than anything else on the screen. The interface stays dark and still so the musician's attention stays on the sound.

Color is information, never decoration. Red means recording. Green means in tune. Amber means warning. The key of an idea shows as a single hue (a dot or a waveform tint), and neighbouring keys get neighbouring hues. Everything else is a shade of grey. If a color on screen doesn't answer "what is happening?" or "what key is this?", it should not be there.

Density is low and the hierarchy is blunt: one primary action per screen, numbers big enough to read from a music stand, and grouped lists for everything else. Structure, navigation and controls follow the iOS Human Interface Guidelines. The brand lives in the color discipline, the mono readouts and the motion feel.

**Key Characteristics:**
- Tonal layering on a near-black ground. No shadows.
- Monospaced, tabular numbers for every value that changes: time, BPM, Hz, cents, durations.
- Semantic color only: recording, in tune, warning, and the key hue.
- One primary action per screen. The record button is the visual centre of gravity.
- Pill shapes for every control. Rounded rectangles for groups.
- Dark only in 1.0. Light mode is a v1.1 feature.

## Colors

A near-black, slightly cool neutral ramp with three semantic signal colors and a generated key-color wheel.

### Primary
- **Take Red** (`recording`): the record button, the stop square, the recording timer and the live waveform while recording. Nothing else is red. Destructive actions use the system destructive role, not this token.

### Secondary
- **Needle Green** (`in-tune`): the tuner's in-tune band and confirmations that a value is correct. Never decoration, never "success" styling on ordinary buttons.
- **Stage Amber** (`warning`): warnings that need attention but are not errors (microphone off, storage low, recording interrupted).

### Neutral
- **Ground** (`ground`): the screen background behind everything.
- **Surface** (`surface`): grouped lists, cards and the icon buttons in the top bar.
- **Raised** (`raised`): controls that sit on a surface or float over content (the Click and Tune tool buttons).
- **Text** (`text`): primary text and the fill of the primary button and the selected chip.
- **Secondary text** (`text-secondary`): metadata, section labels, captions.
- **Tertiary** (`text-tertiary`): the "no key yet" dot and waveform tint, and the outline dot for Loose ideas. Never body text (3.5:1 on Surface).
- **Divider** (`divider`): row separators inside a group.
- **Hairline** (`hairline`): the outline of unselected chips and color swatches.
- **Ring** (`ring`): the 4 pt ring around the record button.

### Key colors

Key colors are generated, not picked. Walk the circle of fifths from C: C, G, D, A, E, B, F#, Db, Ab, Eb, Bb, F. For index `i`, the hue is `(48 − 30·i) mod 360`.

| Use | Major key | Minor key |
|---|---|---|
| Dot (8 pt on Home, 22 pt on the system board) | `hsl(h, 70%, 62%)` | `hsl(h, 55%, 52%)` |
| Waveform tint | `hsl(h, 65%, 70%)` | `hsl(h, 50%, 64%)` |

A minor key takes the hue of its relative major (A minor uses C's hue, D minor uses F's hue) and is deeper. An idea with no detected key uses Tertiary.

### Named Rules
**The Color Means Something Rule.** Every non-grey pixel answers "what is happening?" or "what key is this?". If it answers neither, make it grey.

**The Never Alone Rule.** A key color always appears next to the key name ("Am · 92"). Some minor dots fall below 3:1 on Surface (G#m is about 2.7:1), so the hue may never carry the meaning by itself.

**The One Red Rule.** Recording red appears only while something records or can start recording. A red badge, link or delete button breaks it.

## Typography

**UI Font:** SF Pro (system font)
**Readout and Label Font:** SF Mono (system monospaced design)

**Character:** SF Pro carries the words. SF Mono carries the numbers and the small capitals labels, so the screen reads like an instrument panel. Thin mono numerals at large sizes give the "quiet" half of the north star. Firm semibold titles give the hierarchy.

### Hierarchy
- **Readout** (Extra Light 200, 56 pt, 60 pt leading, −1.5 pt tracking, tabular): the recording timer, BPM, Hz and cents. Scales with Dynamic Type relative to Large Title.
- **Readout small** (Light 300, 17 pt, tabular): the BPM inside the Click tool button. Maps to the `body` text style.
- **Title** (Semibold 600, 22 pt, 28 pt leading, −0.3 pt tracking): screen titles and song names in headers. Maps to `title2`.
- **Body** (Regular 400, 16 pt): row titles and readable text. Maps to `callout`. **Body emphasis** (Medium 500, 16 pt) is for the review-card title and the primary button.
- **Secondary** (Regular 400, 13 pt): row metadata ("Recorded since Sunday · 6 min"). Maps to `footnote`.
- **Meta** (SF Mono Regular, 12 pt, tabular): key and tempo pairs ("Am · 92") and durations ("2:14"). Maps to `caption`.
- **Label** (SF Mono Regular, 11 pt, +0.8 pt tracking, all caps): section labels (SONGS, RECENT, TEMPO · TAKES · LAYERS). Maps to `caption2`.

### Named Rules
**The Tabular Numbers Rule.** Every number that changes while you watch uses monospaced digits. Digits never roll or animate.

**The Thin Only When Big Rule.** Extra Light (200) is for readouts of 34 pt and larger. Below that, use Light (300) or Regular. Thin strokes at small sizes disappear on a dark ground.

**The Text Style Rule.** Every size above maps to a system text style, so it follows Dynamic Type. Never set a fixed point size in SwiftUI without `relativeTo:` or `@ScaledMetric`.

## Layout

- **Screen:** 16 pt side gutters inside the safe area. The top bar is 44 pt tall: the title on the left, 44 pt icon buttons on the right.
- **Groups:** content sits in grouped lists on Surface with 16 pt corners. Section labels sit 22 pt above a group and 6 pt above its first row, inset 4 pt.
- **Rows:** 52 pt minimum for single-line rows (songs), 64 pt for two-line rows (ideas, the review card). 14 pt inner padding, 12 pt between elements.
- **Bottom action area:** Home anchors the record button (88 pt) between the Click and Tune tools (64 pt), 40 pt apart, 40 pt above the bottom edge. Content scrolls under it and fades into Ground (see Elevation & Depth).
- **Navigation:** no tab bar. Home is the root. Ideas and songs push or zoom from their row. Tools open as sheets.
- **Spacing rhythm:** 4, 8, 12, 16, 22 pt. Avoid other values unless a board shows them.

## Elevation & Depth

RiffMemo is flat. Depth comes from tonal layering: Ground, then Surface, then Raised, each one step lighter. No shadows anywhere.

Two places use material, and both are system materials, never hand-built blur:
- **Floating tool buttons** (Click, Tune) sit on a thin dark material over scrolling content, with a hairline border.
- **Scroll edge:** where content meets the bottom action area, it fades into Ground over about 210 pt. Use a gradient mask, not a divider line.

Sheets use the system sheet material and dimming.

### Named Rules
**The No-Shadow Rule.** A surface is lifted by being lighter, never by a shadow.

**The Solid Fallback Rule.** With Reduce Transparency on, the floating tool buttons become solid Raised. With Increase Contrast on, Secondary text, Hairline and Divider step one level brighter. Define these as asset catalog variants, not code branches.

## Shapes

- **Pills** for every control: buttons, chips, tool buttons, the record button. The corner radius is half the height.
- **Rounded rectangles** for containers: list groups and cards 16 pt, board panels 20 pt, color swatches 8 pt.
- **Circle ↔ square:** the record button is a 68 pt red circle inside a 4 pt ring. While recording it becomes a 32 pt square with 8 pt corners. It is one shape that changes its corner radius and size, never two shapes swapping.
- **Waveforms** are 2 pt bars with 1 pt rounded ends, 2 pt apart.

## Components

### Buttons
- **Record:** an 88 pt ring (4 pt, Ring) around a 68 pt Take Red circle. There is one per screen, at the bottom centre of Home and Recording. It responds on touch-down (see Motion).
- **Primary:** a 52 pt pill in Text color with Ground-colored Body emphasis text ("Send to a bandmate"). Use at most one per screen.
- **Tool:** a 64 pt circle on Raised material with a hairline border. It shows a small readout and a Label below it ("120 / CLICK", the tuner glyph with "TUNE").
- **Icon:** a 44 pt circle on Surface with an 18 pt stroke icon. Each one needs an accessibility label.

### Chips
- **Selected:** a 44 pt Text-filled pill with Ground text ("Take 4").
- **Unselected:** a 44 pt pill with a Hairline outline and Text-colored text ("Take 3").
- Chips select takes. They are never filters with counts or icons.

### Cards / Containers
- **Review card:** a 64 pt Surface card with 16 pt corners. It has a two-line title, and a 44 pt Text-filled play button on the right.
- **List group:** Surface, 16 pt corners, Divider between rows, no border.

### Lists
- **Song row:** an 8 pt key dot, the title in Body, "Am · 92" in Meta, and the idea count in Secondary.
- **Idea row:** a 56 × 28 pt mini waveform in the key tint, a title plus a metadata line, and the duration in Meta.
- **Loose ideas row:** an outline dot in Tertiary, with the title in Secondary text.

### Motion (policy; the `animate` skill owns implementation)

"Animate only what earns it. Anything faster than you can watch does not animate." These are decisions, not suggestions:

| Interaction | Decision | Spec |
|---|---|---|
| Record button press | Animate, subtle | Scale 0.92 on touch-down, 120 ms ease-out. Heavy haptic on start. |
| Circle ↔ square morph | Animate | One shape. Corner radius and size spring, 0.3 s, no bounce. |
| Open and close Recording | Animate | Zoom transition from the record button. Closes back into it. |
| Count-in numbers | Animate | 100 ms crossfade on each beat plus a light haptic, on the audio clock. |
| Beat dots | Do not animate | Instant on at the scheduled audio time, 80 ms fade out. |
| Timer digits | Do not animate | Monospaced digits, no rolling numbers. |
| Live waveform | Draw, do not animate | `TimelineView`, linear scroll, no easing. |
| Click and Tuner sheets | System default | `.presentationDetents`. Draggable and interruptible. Do not customize. |
| BPM + and − | Do not animate | Selection haptic per step. Long press repeats and speeds up. |
| Tuner needle | Smooth the data | 5-frame median, then 120 ms smoothing. In tune for 300 ms: green band plus one success haptic. |
| Scrub waveform | Direct manipulation | 1:1 with the finger. Audio seeks while dragging. Selection haptic on bar lines. No momentum. |
| Loop handles A and B | Direct manipulation | 1:1 drag. Snap to bar lines with a selection haptic. Rubber-band at the ends. |
| Switch take | Animate, subtle | Chip fill 150 ms ease-out, waveform crossfade 200 ms. The playhead keeps its place. |
| Mute and Solo | Nearly instant | The layer dims to 35% opacity in 150 ms. |
| Home ↔ Idea | Animate | Zoom transition from the row. Returns to the same row. |
| Saved, Deleted, Sent toasts | Animate | Enter and leave by the same edge, 250 ms ease-out. Undo stays 5 s. |
| New layer arrives (rare) | Delight budget | The row rises 8 pt and fades in, 300 ms ease-out. NEW badge. One soft haptic. |
| Reduce Motion | Gentler, not zero | Zooms and slides become 200 ms fades. Insertions use opacity only. Haptics stay. |

- **Springs:** damping 1.0, response 0.3 s by default. Bounce only after a flick.
- **Strong ease-out:** `.timingCurve(0.23, 1, 0.32, 1)`.
- **Harmony:** beat dots, haptics and the click fire on the same audio time, never on a UI timer.
- **Feel check:** test the record morph and the new-layer arrival on a device at 2–5× slow motion.

## Do's and Don'ts

### Do:
- **Do** put every color on Ground, Surface or Raised. Use Take Red, Needle Green and Stage Amber only for their one meaning.
- **Do** show the key name next to every key dot or tint.
- **Do** use monospaced, tabular digits for every changing number.
- **Do** keep one primary action per screen. On Home, it is the record button.
- **Do** make every tappable control at least 44 × 44 pt, including the Click and Tune tool buttons.
- **Do** use system sheets, system materials, SF Symbols and system text styles.
- **Do** keep haptics when Reduce Motion is on.

### Don't:
- **Don't** use shadows, gradients as decoration, or glass effects you built yourself. The one gradient allowed is the scroll edge fade into Ground.
- **Don't** use system purple, blue or `.rounded` fonts. They come from the old code and are not part of this system.
- **Don't** add a tab bar. Tools are sheets that open from Home.
- **Don't** animate timer digits, beat dots, BPM steps or the live waveform.
- **Don't** use Extra Light below 34 pt.
- **Don't** set text below 11 pt. The boards draw the CLICK and TUNE labels at 9 pt. Build them at 11 pt (`caption2`).
- **Don't** support light mode in 1.0. Lock the app to dark appearance until the v1.1 light mode ships.
