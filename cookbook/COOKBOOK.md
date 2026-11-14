# Ultra Motion cookbook

`$UM` below means the plugin's scripts folder. In a project it's on the `Scripts:` line of CLAUDE.md; otherwise:
`UM=$(ls -d ~/.claude/plugins/cache/*/ultra-motion/*/skills/ultra-motion/scripts | tail -1)`

Every recipe starts the same way:
```bash
$UM/doctor.sh                       # everything green?
$UM/new-video.sh <slug>             # scaffold + git
cd <slug>
```
and ends the same way:
```bash
npx hyperframes render --quality draft -o review/draft.mp4
$UM/contact-sheet.sh review/draft.mp4 --at <key moments>     # → motion-reviewer until APPROVED
npx hyperframes render --quality delivery -o renders/master.mp4
$UM/deliver.sh renders/master.mp4 --formats 16x9,9x16,1x1
```

---

## 1. Product teaser (10–20 s, 16:9 + 9:16)
**Shape:** hook (2 s) → product reveal (3–5 s) → 2–3 benefit beats (2 s each) → end card + CTA (2–3 s).
**Direction defaults:** expo or power4 family; hard cuts on the VO beat; one signature move (e.g. mask reveal).

```bash
cat > audio/vo.txt <<'EOF'
Every great morning starts somewhere.

This one starts with Ember Roast.

Small batch. Bold flavor.
EOF
$UM/tts.py audio/vo.txt -o audio/vo.wav --voice af_heart        # prints beat timings
$UM/captions.sh audio/vo.wav -o audio/vo                        # vo.srt + vo.words.json
$UM/img.sh "studio still life of a matte black coffee bag, soft top light, cream backdrop" \
  -o assets/hero.png --w 1920 --h 1088                          # optional, if no product photo
```
Build: one `<div class="clip">` per beat with `data-start`/`data-duration` from `vo.beats.json`; VO as
`<audio src="audio/vo.wav" data-start="0" data-volume="1">`, music bed at `data-volume="0.1"`.
For 9:16, duplicate `index.html` as `vertical.html` at 1080×1920 and re-lay it out inside the platform safe area
(x 120–888, y 288–1248, x ≤ 780 below y 840; a left-aligned column at x = 120 works well). Render it with
`npx hyperframes render -c vertical.html -o renders/vertical.mp4` and pass `--master-9x16 renders/vertical.mp4`.
The e2e test teaser (`/tmp/um-test/ember-teaser`) did exactly this: the padded reframe shrank captions to ~29 px,
while the dedicated vertical passed every TikTok/Reels/Shorts safe-zone check.

## 2. Technical explainer with Manim (45–90 s)
**Shape:** question → intuition → mechanism (Manim) → consequence → recap.
**Rule:** anything with equations, graphs, geometry or step-by-step transforms is a Manim beat.

```python
# assets/manim/beat3.py
from manim import *
class Mechanism(Scene):
    def construct(self):
        self.camera.background_color = "#0E0F12"
        eq = MathTex(r"E = mc^2", color="#F4F1EA").scale(2)     # needs LaTeX (doctor.sh)
        self.play(Write(eq), run_time=1.2)
        self.wait(0.6)
```
```bash
cd assets/manim && manim -qh --format mov -t beat3.py Mechanism      # ProRes 4444 with alpha
# → place as <video src="assets/manim/media/videos/beat3/1080p60/Mechanism.mov" class="clip" muted playsinline ...>
```
No LaTeX? Use `Text(...)` instead of `MathTex`/`Tex`. Match Manim colours and fonts to the style contract.
Timing: set `run_time`s from `vo.beats.json` so the Manim clip is exactly as long as its beat.

## 3. Social reel (15–30 s, 9:16 first)
**Shape:** hook in the first 1.5 s (big kinetic text) → 3–5 fast beats → loopable end.
**Defaults:** master at 1080×1920 (`new-video.sh <slug> --resolution portrait`); text ≥ 64 px; keep the bottom
20% and right 12% clear (platform UI); kinetic captions always on (most viewers watch muted).

```bash
$UM/new-video.sh reel-launch --resolution portrait
$UM/tts.py audio/vo.txt -o audio/vo.wav --voice am_michael --speed 1.08
$UM/captions.sh audio/vo.wav -o audio/vo --max-words 3        # punchier lines for reels
# … build, review …
$UM/deliver.sh renders/master.mp4 --formats 9x16,1x1 --fit pad
```
Kinetic captions: for each word in `vo.words.json`, a span that turns accent-coloured at `start` and back at `end`
(GSAP `set` calls on the timeline, so it stays seekable).

## 4. Logo sting (3–6 s, no VO)
**Shape:** build-up (1–2 s) → resolve on the logo (hold ≥ 1 s) → optional tagline.
**Defaults:** one idea only (draw-on, assemble from parts, mask reveal, morph from a brand shape); back.out or
expo.out for the resolve; a single SFX hit on the resolve frame; no music bed.

```bash
$UM/new-video.sh logo-sting
# assets/logo.svg from the brand kit → split paths for DrawSVG-style stroke animation
# one SFX (CC0, logged in credits.md) at the resolve frame:
#   <audio src="assets/audio/hit.wav" data-start="2.4" data-volume="0.4" ...>
$UM/deliver.sh renders/master.mp4 --formats 16x9,1x1 --gif-seconds 5
```
Check the resolve frame on its own: `contact-sheet.sh renders/master.mp4 --at 2.4,4.5`.

## 5. Captions only (existing video)
For a finished video that needs burned-in or sidecar captions. Whisper timings are approximate (± 0.3 s,
worse after long pauses).

```bash
$UM/captions.sh input.mp4 -o captions/input               # input.srt + input.words.json
# sidecar (soft) subtitles, no re-encode:
ffmpeg -i input.mp4 -i captions/input.srt -c copy -c:s mov_text -metadata:s:s:0 language=eng out_subbed.mp4
```
Styled kinetic captions instead: `new-video.sh` a project, put the video in as a `<video data-has-audio="true">`
clip, drive caption spans from `input.words.json`, render, then `deliver.sh`.

---

## Troubleshooting
| Symptom | Fix |
|---|---|
| `doctor.sh` ❌ kokoro | `uv venv --python 3.12 ~/.ultra-motion/venv && uv pip install --python ~/.ultra-motion/venv/bin/python 'kokoro>=0.9.4' soundfile pip` (Kokoro needs Python < 3.13) |
| mflux 401 / "gated repo" | don't use `--model schnell`; img.sh loads the self-contained `mflux-community/flux-1-schnell-mflux-q4` |
| Manim `MathTex` fails | install BasicTeX + the tlmgr packages from doctor.sh, open a new shell |
| `hyperframes render` slow | `--workers auto` is the default; close Chrome-heavy apps; draft renders with `--quality draft` |
| Disk full mid-render | check `df -h ~`; macOS swap in `/System/Volumes/VM` grows after FLUX runs and drains on its own |
| Captions early on Kokoro VO | make sure `audio/vo.beats.json` sits next to `vo.wav`, which makes captions.sh use exact timings |
