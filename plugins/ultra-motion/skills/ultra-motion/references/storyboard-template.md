# Storyboard

Project: __ · Duration: __ s · Master: 1920×1080 @ 30 fps · Direction: __

Timing comes from `audio/vo.beats.json` (step 6). Re-time this table after the VO exists; the VO wins.
On-screen text ≤ 7 words. One focal point per beat. Motion verbs come from motion-language.md.

| # | In → Out (s) | VO line | Visual (what we see) | On-screen text (≤ 7 words) | Motion verbs (in / hold / out) | Transition out | Assets | Engine |
|---|--------------|---------|----------------------|----------------------------|--------------------------------|----------------|--------|--------|
| 1 | 0.00 → 2.40 | "…" | | | rise-in `expo.out` 0.6 s / hold 1.2 s / cut | hard cut | | GSAP |
| 2 | | | | | | | | GSAP / Manim / Blender |

## Beat notes
For each beat that needs more than a row: composition sketch in words (left/right thirds, scale, depth), what
moves first, what the eye should land on, and the exact frame the key text settles.

## Key frames for review
List the moments the reviewer must check individually (pass them to `contact-sheet.sh --at`):
- __ s: beat 1 title settled
- __ s: product hero
- __ s: end card / CTA

## Checklist before animating
- [ ] Every beat has a start/end from vo.beats.json
- [ ] Every on-screen line ≤ 7 words and ≥ 12-frame hold
- [ ] One transition language across all rows
- [ ] Every asset is procedural, logged in credits.md, or made with img.sh
- [ ] Technical/maths beats are marked Manim
