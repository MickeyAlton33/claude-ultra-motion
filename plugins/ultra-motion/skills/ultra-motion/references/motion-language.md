# Motion language cheat sheet

Pick **one easing family** and **one transition language** per video and write them in the style contract.

## Easing families (GSAP names)
| Family | GSAP | Feel | Use for |
|---|---|---|---|
| Sine | `sine.in/out/inOut` | soft, breathing | ambient loops, background drift, slow camera |
| Quad | `power1.*` | gentle, UI-like | subtle UI, small nudges |
| Cubic | `power2.*` | neutral default | UI motion, product UI demos |
| Quart | `power3.*` | confident | most motion design text and shapes |
| Quint | `power4.*` | punchy, editorial | titles, hero moves |
| Expo | `expo.*` | dramatic, cinematic | hero reveals, big scale moves, tech/premium brands |
| Circ | `circ.*` | sharp stop | mechanical, precise products |
| Back | `back.out(1.2–1.7)` | overshoot, playful | pops, icons, friendly brands (not with expo in the same film) |
| Elastic / Bounce | `elastic.out(1, 0.4)`, `bounce.out` | toy-like | only if the brand is literally playful; avoid by default |
| Steps | `steps(n)` | stop-motion, digital | glitch-free typewriter, frame-by-frame looks |
| Linear | `none` | robotic | progress bars, constant rotation, scroll-like marquees |
| Custom | `CustomEase` | signature | a single brand curve reused everywhere |

Direction rules: entrances `.out` (fast start, soft landing) · exits `.in`, about 70% of the entrance duration ·
moves between two on-screen states `.inOut`. Never mix `back`/`elastic` with `expo`/`power4` in one film.

## Durations
| Kind | Seconds | Frames @30 | Frames @24 | Frames @60 |
|---|---|---|---|---|
| UI micro (hover, tick, toggle) | 0.10–0.20 | 3–6 | 2–5 | 6–12 |
| UI standard (panel, card) | 0.25–0.40 | 8–12 | 6–10 | 15–24 |
| Motion text in | 0.40–0.70 | 12–21 | 10–17 | 24–42 |
| Hero reveal / big scale | 0.80–1.50 | 24–45 | 19–36 | 48–90 |
| Scene transition | 0.30–0.60 | 9–18 | 7–14 | 18–36 |
| Key-text hold (minimum) | ≥ 0.40 | ≥ 12 | ≥ 10 | ≥ 24 |
| Ambient loop period | 4–12 | 120–360 | — | — |

Cinematic pieces sit at the long end; social/UI pieces at the short end. Reading time ≈ 0.3 s per word + 0.5 s.

## Stagger and overlap
- Lists, letters, tiles: `stagger: 0.04–0.08` (letters 0.02–0.03, max ~12 staggered items before it drags).
- Overlap sequential moves by 20–40% (`"-=0.2"` or `"<0.15"` position params) so motion flows.
- Lead the VO: a visual change lands 2–4 frames **before** the word that names it.

## Transitions — choose one language
| Transition | Reads as | Use when | Avoid when |
|---|---|---|---|
| Hard cut | confident, rhythmic | VO-driven explainers, cuts on beat or word | slow, contemplative pieces |
| Match cut | clever continuity | a shape/colour carries into the next scene | no shared element exists |
| Mask / wipe reveal | editorial, graphic | chapter changes, type-led design | used on every cut (gets busy) |
| Push / slide | spatial, UI | product flows, "next step" logic | cinematic tone |
| Zoom-through | energy, depth | teasers, logo reveals | calm brands, long VO |
| Morph | elegant, systemic | shape-to-shape stories, data that transforms | shapes with nothing in common |
| Cross-dissolve | time passing | mood, passage of time | as a default (looks unedited) |
| Whip pan / blur | high energy | social reels, sport | anything corporate |
| Light leak / flare | — | almost never | generic AI-template look |

## Text animation
- Line reveal: mask each line, move `y: 100% → 0`, `power4.out` 0.6 s, lines staggered 0.08 s.
- Word stagger for headlines ≤ 7 words; per-letter only for ≤ 3 words.
- Kinetic captions: current word highlighted (accent colour or weight), driven by `vo.words.json` start/end.
- Never animate letter-spacing and scale together; never scroll text the viewer must read.

## Camera and depth
- Slow push: scale 1.00 → 1.04 across a beat, `sine.inOut` or `none`.
- Parallax: 2–3 layers, background moves 30–50% of the foreground's distance.
- 3D (Three.js in HyperFrames or Blender renders): one camera move per beat, ease-in-out, no free orbiting.

## SVG stroke draw-on (HyperFrames)
Put each path's real length in the markup as attributes, `stroke-dasharray="L" stroke-dashoffset="L"`, and tween
the attribute: `tl.fromTo(path, {attr: {"stroke-dashoffset": L}}, {attr: {"stroke-dashoffset": 0}, …})`.
Don't use `pathLength="1"` with CSS `stroke-dasharray`/`stroke-dashoffset`. In HyperFrames renders that pops the
whole stroke in on a single frame. (Verified: the attribute version drew over 17 frames; the CSS version over 1.)
Draws read best with `power4.out` 0.6–0.9 s. Check it by counting stroke pixels frame by frame, not by eye on a sheet.

## Seek-safety (HyperFrames)
Every timeline paused and registered on `window.__timelines`; no `Math.random()` without a seed, no
`Date.now()`, `setTimeout`, `requestAnimationFrame` loops or CSS animations that run outside the GSAP timeline.
Rendering any frame out of order must give the same pixels.
