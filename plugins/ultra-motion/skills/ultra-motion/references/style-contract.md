# Style contract — {{PROJECT}}

Fill this in at the Directions checkpoint (pipeline step 4). Every scene, review and fix is judged
against it. If a choice isn't written here, it isn't decided. Keep it to one screen.

## Format
- Master: 1920×1080 @ 30 fps · deliverables: 16:9 / 9:16 / 1:1 (strike what's not needed)
- Duration: __ s · VO: yes/no · voice: __ · speed: __ · language: __
- Safe margins: 5% on every side (96 px left/right, 54 px top/bottom at 1920×1080).
  9:16 (1080×1920): keep key content inside the overlap of the TikTok, Reels and Shorts clear areas
  (HyperFrames' safe-area data): **x 120–888, y 288–1248, and x ≤ 780 below y 840**. That area sits off-centre, so a
  left-aligned column at x = 120 usually works better than centring.
- Captions: bottom band, above the safe line, max 2 lines, active word highlighted.

## Palette (max 5)
| Role | Hex | Use |
|------|-----|-----|
| ground | | backgrounds |
| ink | | primary text |
| accent | | one thing per frame, never decoration |
| support | | secondary shapes, dividers |
| shade | | depth and shadows (never pure #000 on pure #fff) |

Text contrast ≥ 4.5:1 against its ground (≥ 3:1 for text ≥ 96 px).

## Type
- Display: family __, weight __, tracking −0.02 to −0.04em at ≥ 96 px
- Text: family __, weight __
- Min 48 px at 1080p (64 px in 9:16), ≤ 7 words on screen, ≤ 2 lines
- Hold key text still for ≥ 12 frames after it settles; reading time ≈ 0.3 s/word + 0.5 s
- Fonts: local or Google Fonts only; licence logged in credits.md

## Motion language
- Easing family: __ (e.g. expo: in `expo.out`, out `expo.in`, moves `expo.inOut`)
- Durations: micro __ s · standard __ s · hero __ s (see motion-language.md)
- Transition language (exactly one): __ (e.g. "hard cut on the VO beat + 8-frame mask wipe for chapter changes")
- Stagger: __ s per item (0.04–0.08 typical)
- Camera: static | slow push (≤ 3%/s) | parallax layers
- Signature move (one, repeated): __

## Audio
- VO: Kokoro `__`, speed __, gap between beats __ s
- Music: file __ · licence __ · `data-volume` 0.1 (−20 dB) under VO; up to 0.3 in VO-free stretches
- SFX: only on transitions or hits that move > 30% of the frame; each logged in credits.md
- Delivery: −14 LUFS integrated, −1.5 dBTP (deliver.sh)

## Brand
- Source: website / theme.css / guidelines: __
- Logo: file __, clear space __, min width __ px, never recoloured / stretched / on busy ground
- Voice and tone in on-screen copy: __

## Forbidden in this video
- Random particles, lens flares, stock glow, bokeh dust, generic tech grids, meaningless gradient orbs
- A second transition style, a second easing family
- Text under 48 px at 1080p, text inside the outer 5%
- Anything the brand guide forbids: __
