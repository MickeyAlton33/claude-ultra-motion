---
name: ultra-motion
description: Use whenever the user asks for a motion design video, animated video, explainer, promo, teaser, product video, social reel, logo animation, kinetic typography or any animation rendered to video. Before doing anything else, ask the user whether to use the Ultra Motion Design pipeline or default mode.
user-invocable: false
---

# Ultra Motion Design

A free, local studio pipeline: HyperFrames + GSAP for animation, Manim for technical beats,
Blender (optional, via the `blender` MCP in safe mode) for 3D, Kokoro for voiceover,
whisper.cpp for word-timed captions, mflux FLUX.1 schnell (optional) for stills, FFmpeg for delivery.

- Scripts: `${CLAUDE_SKILL_DIR}/scripts/` (every script takes `--help`)
- References: `${CLAUDE_SKILL_DIR}/references/`
- Reviewer subagent: `motion-reviewer` (ships with this plugin)

## Step 0 — Always ask first
Use AskUserQuestion with one question, "How should I make this video?", and two options:
1. **Ultra Motion Design pipeline (Recommended)**: full studio process with script, storyboard, voiceover, synced
   captions, reviewed animation, multi-format delivery. Slower, much higher quality.
2. **Default mode**: quick direct build, no pipeline.

Skip the question only if the user already chose (e.g. they invoked /ultra-motion, or said "ultra" or "quick").
If default mode: proceed normally and stop following this skill.

## Free-stack rules (Ultra mode)
- No paid APIs or paid generators: no HeyGen generation, avatars or voices from `/media-use`, no ElevenLabs,
  fal or Runway. In the `blender` MCP keep Hyper3D, Hunyuan3D, Tripo, Meshy, World Labs and Sketchfab off.
- Images: FLUX.1 **schnell** only (Apache-2.0) through `scripts/img.sh`. Never FLUX dev, Kontext, Krea or
  Fill weights (non-commercial licence).
- Weights and venvs live in `~/.ultra-motion/`, never in the video project or the plugin repo.
- Every third-party file (music, SFX, stock, fonts, Poly Haven) is logged in `credits.md` with its licence.

## Pipeline (Ultra mode)
Run `${CLAUDE_SKILL_DIR}/scripts/doctor.sh` first; if anything is missing, report it and offer the fix.
Use a task list. Commit to git after each stage.

1. **Brief.** Extract or ask (max 3 questions in one AskUserQuestion): purpose and audience, duration,
   formats (16:9 / 9:16 / 1:1), brand (link a website or theme.css if one exists), voiceover yes/no and voice, language.
2. **Scaffold.** `${CLAUDE_SKILL_DIR}/scripts/new-video.sh <name>` (in the current directory unless the user
   names one): HyperFrames project + script.md, storyboard.md, assets/, audio/, renders/, review/, credits.md,
   and a CLAUDE.md that starts with the style contract from references/style-contract.md.
3. **Script.** Beat-mapped script.md with target seconds per beat. Words ≈ duration × 2.5 for VO.
   Write the VO text to `audio/vo.txt`, one paragraph per beat (blank line between beats).
4. **Directions.** Using references/motion-language.md, propose 2–3 distinct visual directions (style frames
   described plus palette, type, easing language, transition style). ⛔ CHECKPOINT: wait for the pick.
   Then fill in the style contract at the top of the project CLAUDE.md.
5. **Storyboard.** storyboard.md from references/storyboard-template.md: per beat, the visual, on-screen text
   (≤ 7 words), motion verbs, assets, duration. Use Manim for any technical or math beat.
6. **Audio first.** `scripts/tts.py audio/vo.txt -o audio/vo.wav --voice <voice>` for VO. It prints exact
   durations and writes `audio/vo.beats.json` (start/end per beat); beats follow the VO, not the other way round.
   Music and SFX from references/audio-sources.md; ask the user to download them; log every file in credits.md.
7. **Captions.** `scripts/captions.sh audio/vo.wav -o audio/vo` → `vo.srt` + `vo.words.json`; the word
   timestamps drive kinetic captions.
8. **Assets.** Procedural first (GSAP, SVG, shaders, Blender renders if available). Then stock (logged in
   credits.md), then `scripts/img.sh` if installed. No paid APIs.
9. **Animate.** Build with the HyperFrames skills (`/hyperframes`; search `/hyperframes-registry` before
   hand-building a named visual) and the GSAP skills: scene per beat, GSAP timelines, deterministic, seekable.
   Audio is placed in the composition: VO `<audio ... data-volume="1">`, music bed at `data-volume="0.1"`
   (−20 dB; keep it between 0.08 and 0.126 = −22 to −18 dB). `npx hyperframes check` must pass.
   Manim beats: render with `manim -qh --format mov -t scene.py Scene` (alpha) and place as a video clip.
10. **Review.** Low-res render (`npx hyperframes render --quality draft -o review/draft.mp4`) →
    `scripts/contact-sheet.sh review/draft.mp4 --at <key text moments>` → motion-reviewer subagent (give it the
    project path, the sheet, its .txt legend, the key frames and audio/vo.beats.json) → fix until APPROVED.
    Check key frames individually too. Stop after 3 rounds and show the user what is still open.
11. **Render & deliver.** Full render (`npx hyperframes render --quality delivery -o renders/master.mp4`) →
    `scripts/deliver.sh renders/master.mp4 --formats <requested>` (loudness normalized; all requested formats +
    GIF preview). For 9:16 and 1:1, prefer a re-laid-out composition rendered at that resolution and passed as
    `--master-9x16` / `--master-1x1`; otherwise deliver.sh reframes (`--fit crop|pad`) and says so.
12. **Report.** File paths, durations, the credits.md summary, and 3 suggested variations.

## Scripts
| Script | What it does |
|---|---|
| `doctor.sh` | Checks every dependency; prints the fix for anything missing. Exit 1 if a required tool is missing. |
| `new-video.sh <name>` | Scaffolds the HyperFrames project, pipeline files and git repo. |
| `tts.py <text> -o <wav>` | Kokoro VO; one paragraph per beat; prints durations; writes `<wav>.beats.json`. |
| `captions.sh <audio>` | whisper.cpp → phrase `.srt` + `.words.json` (word start/end in seconds). |
| `contact-sheet.sh <video>` | 1 fps tile grid PNG + `.txt` legend; `--at t1,t2` also saves full-size key frames. |
| `img.sh "<prompt>" -o <png>` | FLUX.1 schnell (4-bit, local). Exits 0 with a message if mflux isn't installed. |
| `deliver.sh <master>` | −14 LUFS / −1.5 dBTP two-pass loudnorm → 16:9, 9:16, 1:1 MP4s + GIF preview. |

## Quality bar
One transition language per video; consistent easing family; ≥ 12-frame holds on key text; 5% safe margins;
min 48px text at 1080p; no generic AI tropes (random particles, lens flares, stock glow); music −18 to −22 dB under VO.
