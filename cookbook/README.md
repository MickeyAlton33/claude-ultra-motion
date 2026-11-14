# Ultra Motion — what this is

A Claude Code plugin that turns "make me a motion design video" into a studio pipeline that runs entirely on free,
local tools. When you ask for a video, Claude first asks **"Ultra Motion Design pipeline or default mode?"**.

- **Ultra**: brief → scaffold → script → 2–3 visual directions (you pick) → storyboard → voiceover → word-timed
  captions → assets → HyperFrames/GSAP animation → draft render + contact sheet + `motion-reviewer` pass → full
  render → loudness-normalized 16:9 / 9:16 / 1:1 + GIF → report with credits.
- **Default**: a direct quick build with no pipeline.
- `/ultra-motion <brief>` skips the question and goes straight to Ultra.

## The stack (all free)
| Purpose | Tool | Licence | Cost | Where it lives |
|---|---|---|---|---|
| Animation engine + render | HyperFrames (Claude Code plugin + `npx hyperframes`) | Apache-2.0 | free | plugin cache, npm cache |
| Animation skills | GSAP skills plugin; GSAP runtime | skills free; GSAP free (standard "no charge" licence) | free | plugin cache, CDN |
| Technical / maths beats | Manim Community | MIT | free | `uv tool` |
| Maths typesetting (optional) | BasicTeX | LPPL/GPL mix (TeX Live) | free | `/Library/TeX` |
| 3D (optional) | Blender + an MCP server (safe mode) | GPL / MIT | free | `/Applications`, user MCP config |
| Voiceover | Kokoro-82M via `kokoro` | Apache-2.0 | free | `~/.ultra-motion/venv`, `~/.ultra-motion/hf` |
| Phonemizer fallback | espeak-ng | GPL-3.0 | free | Homebrew |
| Captions | whisper.cpp + ggml-small | MIT | free | Homebrew, `~/.ultra-motion/models` |
| Stills (optional) | mflux + FLUX.1 **schnell**, 4-bit (`mflux-community/flux-1-schnell-mflux-q4`) | MIT / Apache-2.0 | free | `uv tool`, `~/.ultra-motion/hf` (9.6 GB) |
| Encode / mux / loudness | FFmpeg | LGPL/GPL | free | Homebrew |

Never used: ElevenLabs, fal, Runway, HeyGen generation, Remotion (its licence isn't free for companies > 3 people),
FLUX dev/Krea/Kontext (non-commercial weights), paid 3D generators inside the Blender MCP.

## Disk budget (approx.)
Kokoro venv 1 GB + weights 0.33 GB · whisper small 0.49 GB · Manim 0.3 GB · Blender 1 GB · BasicTeX 0.3 GB ·
mflux 1 GB + FLUX schnell q4 9.6 GB · HyperFrames Chrome + npm cache ~0.5 GB. Renders need a few GB of headroom.

## Files
- `COOKBOOK.md` — recipes: product teaser, explainer (Manim), social reel, logo sting, captions-only.
- `RUNBOOK.md` — the runbook this repo was built from.
- `../setup/install.sh` — idempotent installer for a fresh Mac.
