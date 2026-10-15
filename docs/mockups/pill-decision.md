# Pill design decision (Task 12)

Chosen on 2026-10-15 from the design canvas
https://claude.ai/artifact/QbQJgC5as5g4DGYsWm4wEM (board "A1 · Calm Scroll").

**Style:** Midnight Capsule, attached to the MacBook notch as "Slim Wings".

## Shape and placement
- Idle: hidden (the real notch shows). The overlay is a black shape drawn over the notch.
- Active: notch grows sideways to **340 × 34 pt**, bottom corners radius **16 pt**, top flush with the screen edge.
- Layout: three columns `[left wing] [camera gap = notch width] [right wing]`; wing padding 14 pt; font 12 pt medium.
- Expand/collapse: width + height animate over **0.46 s**, spring-like overshoot (`cubic-bezier(.2,.95,.25,1.15)`); wing content fades in after 0.16 s.

## Wing content per state
| State | Left wing | Right wing |
|---|---|---|
| Listening | 7 bars | red dot (6 pt, blinking) + timer `0:04` |
| Thinking | spinner (13 pt) | "Thinking" |
| Pasted | green check | "Pasted" |
| Copied (no text field) | clipboard (cyan) | "⌘V" |
| Cancelled | grey ⊗ | "Esc" |
| Error / no speech | (amber/red icon) | short label |

## Waveform (A1 · Calm Scroll)
- 7 bars, **3 pt** wide, **3 pt** gap, height **3–16 pt**, colour **#5BD3FF**.
- Scrolling history (newest on the right), level sampled every **120 ms**.
- Smoothing: `shown = prev + 0.55 × (new − prev)`.
- Bar height eases over **180 ms** (`cubic-bezier(.3,.7,.4,1)`).
- Loudness: RMS → 0…1 across −50…0 dBFS (`AudioLevel.normalized`), so quiet speech = short bars, shouting = full height.

## Colours
- Shape `#000000`; text `#FFFFFF`; timer `rgba(255,255,255,0.7)`.
- Accent `#5BD3FF`; recording dot `#FF453A`; success `#30D158`; cancelled `#A1A1A6`; warning `#FF9F0A`; error `#FF453A`.
