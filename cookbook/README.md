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


# Ultra 3D — what this is

`ultra-3d` turns "make me a 3D model / render / printable part / web GLB" into a pipeline: brief → routing →
concept checkpoint → build → `mesh_check` → rendered review by `3d-reviewer` → per-track exports. Recipes: `3D.md`.

## The stack (everything free except Meshy credits)
| Purpose | Tool | Licence | Cost | Where it lives |
|---|---|---|---|---|
| Scene, modeling, rendering | Blender 5.3 (Cycles on Metal, EEVEE) | GPL-2.0+ | free | `/Applications/Blender.app` |
| Claude ↔ Blender (interactive) | Blender Lab MCP 1.0.3 (official; **no sandbox**, port 9877, manual Start) | GPL-3.0+ | free | add-on in Blender prefs, server `~/.ultra-3d/blender_mcp` |
| Parametric CAD | build123d 0.13 · OpenSCAD 2026.10 snapshot | Apache-2.0 · GPL-2.0 | free | `~/.ultra-3d/venv` · `/Applications/OpenSCAD.app` |
| Mesh checks / repair | trimesh 5.2 · manifold3d 3.5 · fast-simplification | MIT · Apache-2.0 · MIT | free | `~/.ultra-3d/venv` |
| Web optimisation | glTF-Transform CLI 4.5 (+ optional KTX-Software `ktx` for KTX2) · gltfjsx 6.5.3 | MIT · Apache-2.0 · MIT | free | global npm |
| Slicing | Bambu Studio 2.08 CLI (P2S/P1S/A1/H2D system presets) | AGPL-3.0 | free | `/Applications/BambuStudio.app` |
| Video encode | FFmpeg | LGPL/GPL | free | Homebrew |
| AI meshes, texturing, rigging, animation | Meshy MCP 0.6.11 (bundled) + meshy-3d-generation/printing skills (know-how only) | MIT (client) | **credits** (Pro plan+) | npx cache; key in Keychain |
| HDRIs, textures, models | Poly Haven API | CC0 assets | free | downloaded per project |

Meshy credit guide (v0.6.11): text-to-3D preview 20 (meshy-7.1) / 5 (6-lite, t2, t2.5) · refine 10 · image-to-3D
20–30 (+10 texture) · remesh 5 · rig 5 · animation 3/action · print repair 10. See
`plugins/ultra-3d/skills/ultra-3d/references/meshy-playbook.md`.

## Disk budget (approx.)
Blender 1 GB · ultra-3d venv 0.7 GB · OpenSCAD 0.2 GB · Blender Lab MCP server env 0.1 GB · Metal kernel cache
(first Cycles render) ~0.3 GB. Projects: turntable PNG frames are deleted after encoding; keep `renders/` per project.
