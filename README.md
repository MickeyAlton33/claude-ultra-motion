# claude-ultra-motion

A Claude Code plugin marketplace with two plugins:
- **ultra-motion**: a free, local motion-design video pipeline. Ask Claude for any motion video and it first asks
  **"Ultra Motion Design pipeline or default mode?"**.
- **ultra-3d**: a 3D design & modeling pipeline (renders, web GLBs, 3D prints, rigged models). Ask for any 3D work and
  it first asks **"Ultra 3D pipeline or default mode?"** — see [ultra-3d](#ultra-3d) below.

## Install (any machine)
```bash
claude plugin marketplace add MickeyAlton33/claude-ultra-motion
claude plugin install ultra-motion@claude-ultra-motion
```
Then install the free tool stack (asks before Homebrew installs and big downloads):
```bash
git clone https://github.com/MickeyAlton33/claude-ultra-motion ~/code/claude-ultra-motion
~/code/claude-ultra-motion/setup/install.sh
```
Check it any time from Claude: the skill runs `doctor.sh` first, or run it yourself:
`$(ls -d ~/.claude/plugins/cache/*/ultra-motion/*/skills/ultra-motion/scripts | tail -1)/doctor.sh`

## Use
- "Make me a 10-second motion design teaser for a coffee brand" → Claude asks Ultra or default.
- `/ultra-motion <brief>` → straight into the Ultra pipeline.

## What's inside
```
.claude-plugin/marketplace.json          this repo is a marketplace
plugins/ultra-motion/
  .claude-plugin/plugin.json
  skills/ultra-motion/SKILL.md           the pipeline (Step 0 question, 12 stages, quality bar)
  skills/ultra-motion/references/        style contract, storyboard template, motion language, audio sources
  skills/ultra-motion/scripts/           doctor, new-video, tts.py, captions, contact-sheet, img, deliver
  agents/motion-reviewer.md              frame-only creative-director review → APPROVED / CHANGES REQUIRED
cookbook/                                README (stack + licences), COOKBOOK (recipes), RUNBOOK
setup/install.sh                         idempotent installer for the tool stack
```
Model weights and venvs live in `~/.ultra-motion/`, never in this repo.

Why there's no `commands/` folder: Claude Code now registers plugin commands as skills, so a
`commands/ultra-motion.md` next to the `ultra-motion` skill produced two skills with the same name. The command
won the listing and hid the skill's trigger description. The skill is therefore user-invocable itself:
`/ultra-motion [brief]` runs it directly, skipping the Ultra/default question.

## Update
```bash
cd ~/code/claude-ultra-motion && git commit -am "…" && git push
claude plugin marketplace update claude-ultra-motion
claude plugin update ultra-motion@claude-ultra-motion
```
Then restart Claude Code.

## ultra-3d

### Install
```bash
claude plugin marketplace add MickeyAlton33/claude-ultra-motion     # once per machine
claude plugin install ultra-3d@claude-ultra-motion
claude plugin configure ultra-3d@claude-ultra-motion                # paste your Meshy API key (stored in the Keychain)
```
Tool stack (asks before Homebrew installs): Blender ≥ 5.1 (`brew install --cask blender`), OpenSCAD
(`brew install --cask openscad@snapshot`), a Python venv at `~/.ultra-3d/venv` with
`build123d trimesh manifold3d numpy scipy rtree fast-simplification pillow`, `npm i -g @gltf-transform/cli`, ffmpeg,
uv, and Bambu Studio for slicing. The **Blender Lab MCP** (official, v1.0.3) is installed separately — see
`cookbook/3D.md` → *Setup on a new machine*. Check everything with
`$(ls -d ~/.claude/plugins/cache/*/ultra-3d/*/skills/ultra-3d/scripts | tail -1)/doctor.sh`.

### Use
- "Make me a 3D model of a desk lamp" → Claude asks Ultra 3D or default.
- `/ultra-3d <brief>` → straight into the Ultra pipeline.
- Meshy (AI meshes) costs credits: Claude checks the balance, shows a cost table and waits for approval before every
  paid call; previews before refines. Everything else is free.

### What's inside
```
plugins/ultra-3d/
  .claude-plugin/plugin.json             Meshy MCP (pinned 0.6.11) + sensitive userConfig for its key
  skills/ultra-3d/SKILL.md               Step 0 question, 8-stage pipeline, quality bar, hard rules
  skills/ultra-3d/references/            routing, meshy-playbook, blender-recipes, print-rules, web-3d-rules, cookbook → ../cookbook/3D.md
  skills/ultra-3d/scripts/               doctor, new-3d, mesh_check.py, mesh_fix.py, render.sh (+ blender_studio.py),
                                         web_optimize.sh, slice.sh (Bambu Studio CLI, P2S default)
  agents/3d-reviewer.md                  render + report review → APPROVED / CHANGES REQUIRED
cookbook/3D.md                           recipes: product hero, web GLB for R3F, rigged character, parametric print,
                                         decorative print from AI mesh, Meshy → Blender scene
```
Same no-`commands/` rule as ultra-motion: `/ultra-3d` is the skill itself. Venv, downloads and the Blender Lab MCP
server live in `~/.ultra-3d/`; printer defaults in `~/.ultra-3d/config`. Meshes, renders and slices are git-ignored.
