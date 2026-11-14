---
name: ultra-3d
description: Use whenever the user asks for 3D design or 3D modeling — a 3D model, asset, character, creature, prop, product render, scene, turntable, GLB/glTF for a website or AR, rigged or animated model, or a part to 3D print (STL/3MF/CAD, enclosure, bracket, mount, stand, figurine). Before doing anything else, ask whether to use the Ultra 3D pipeline or default mode. Typing /ultra-3d [brief] forces the Ultra pipeline.
argument-hint: "[brief: what it is, purpose, track (render / web GLB / print / rigged), size]"
allowed-tools:
  - Bash(${CLAUDE_SKILL_DIR}/scripts/*)
---

# Ultra 3D

Free local stack + the user's Meshy credits: **Blender 5.3** (headless scripts + `blender-lab` MCP), **build123d /
OpenSCAD** for parametric CAD, **trimesh + manifold3d** for checks/repair, **glTF-Transform** for web, **Bambu Studio CLI**
(P2S) for slicing, **Meshy MCP** for AI meshes, **Poly Haven** (CC0) for HDRIs/textures/models.

- Scripts: `${CLAUDE_SKILL_DIR}/scripts/` (every script takes `--help`; Python ones run with `~/.ultra-3d/venv/bin/python`)
- References: `${CLAUDE_SKILL_DIR}/references/` — routing.md, meshy-playbook.md, blender-recipes.md, print-rules.md,
  web-3d-rules.md, cookbook.md (worked recipes)
- Reviewer subagent: `3d-reviewer` (ships with this plugin)

## Step 0 — Always ask first
Use AskUserQuestion with one question, "How should I handle this 3D work?", and two options:
1. **Ultra 3D pipeline (Recommended)**: brief → references → right modeling method → checks → review → exports.
2. **Default mode**: quick direct attempt.

Skip the question only if the user already chose (they invoked /ultra-3d, or said "ultra" or "quick").
If default mode: proceed normally and stop following this skill — but still never spend Meshy credits without stating
the cost first, and still use real-world units.

**Typed as `/ultra-3d`:** the user ran this skill directly, which means they chose Ultra. Don't ask Step 0; go straight
to the pipeline. The brief they typed after the command (empty if none): $ARGUMENTS
If that brief is empty, start pipeline step 1 by asking for it.

## Pipeline (Ultra mode)
Run `${CLAUDE_SKILL_DIR}/scripts/doctor.sh` first; if anything required is missing, report it and offer the fix
(ask before brew/sudo/downloads > 2 GB). Use a task list. Commit to git after each stage.

1. **Brief.** One AskUserQuestion (max 3 questions): what it is and its purpose; the target **track**
   (visual render / web GLB / 3D print / rigged-animated); dimensions or scale; style references.
   Scaffold with `${CLAUDE_SKILL_DIR}/scripts/new-3d.sh "<name>" --track <track>` (creates `~/3d/<slug>/` with
   brief.md, refs/, src/, assets/, exports/, renders/, credits.md, meshy-log.md, CLAUDE.md, git). Fill brief.md.
2. **Route.** Pick the modeling method using `references/routing.md`:
   - Functional or dimensioned parts (enclosures, brackets, mounts, mechanical, anything that must fit) →
     **parametric CAD** (build123d; OpenSCAD for simple ones). Never AI mesh for parts that must fit.
   - Organic/decorative objects, characters, props → **Meshy** (text-to-3D or image-to-3D), then Blender cleanup.
   - Scenes, environments, product shots → **Blender** via MCP, with Poly Haven assets plus generated or CAD models.
   - Mixed (decorative shell + mechanical interface) → hybrid: CAD for every interface, Meshy for the shell.
3. **Concept.**
   - Meshy: write 2–3 prompt variants (`references/meshy-playbook.md`), call `meshy_check_balance`, state the credit
     cost as a table (tool, model, count, credits, total, balance after). ⛔ CHECKPOINT: user approves. Generate
     **previews** only, download to `assets/meshy/`, render each with
     `render.sh <glb> --quick --stills hero --turntable 0 --preset clay`, show them, user picks one, then **refine/texture**.
     Log every task in meshy-log.md.
   - CAD: write the parametric source in `src/` with **named dimensions at the top** (template: `new-3d.sh --track print`
     creates `src/part.py`); run it; render a quick preview (`render.sh exports/part.stl --quick --stills hero,front --turntable 0`).
   - Scenes: block out composition and camera first (Blender MCP or `render.sh --preset clay`);
     ⛔ CHECKPOINT on the blockout render.
4. **Build.** Cleanup in Blender (scale, origin, remesh/decimate, UVs, materials — `references/blender-recipes.md` §Cleanup).
   Rigging/animation via Meshy (`meshy_rig` 5 cr, `meshy_animate` 3 cr/action) when needed. Keep source files
   (.blend, .py, .scad) in `src/`. Blender MCP: start the bridge in the user's Blender (port 9877); only touch files
   inside the project folder.
5. **Check.** `~/.ultra-3d/venv/bin/python ${CLAUDE_SKILL_DIR}/scripts/mesh_check.py <export> --track <track>
   [--expect X,Y,Z] [--budget hero|secondary|prop|ar] --json renders/<name>.check.json` on every export:
   watertight/manifold + walls + overhangs (print), real-world dimensions, poly and texture budget (web), skins/clips
   (rigged), normals. Fix with `scripts/mesh_fix.py` (`--union`, `--remesh 0.4 [--thicken 1.6]`, `--drop-small 1`,
   `--units-from m`, `--fit-max MM`, `--center`) or in the CAD source. Re-check until PASS.
6. **Review.** `${CLAUDE_SKILL_DIR}/scripts/render.sh <model> --quick` → turntable MP4 + contact sheet + hero/front/side/
   top/detail stills → dispatch the **3d-reviewer** subagent with: the brief path, the stills, the contact sheet and the
   mesh_check JSON. Apply its ranked fixes, re-render, re-review until **APPROVED** (max 3 rounds, then ask the user).
7. **Export per track.**
   - Visual: `render.sh <model> --final` → 4K stills + 1080p Cycles turntable MP4 (can feed the ultra-motion pipeline).
   - Web: `scripts/web_optimize.sh <glb> --budget <tier> --jsx` → `exports/<name>.web.glb` within budget + typed R3F
     component (gltfjsx) + drei `useGLTF` snippet (`references/web-3d-rules.md`). USDZ too if AR was asked.
   - Print: STL + 3MF (+ STEP from CAD) in printed orientation → `scripts/slice.sh exports/<part>.3mf`
     (P2S, textured plate, PLA Basic by default; `--set wall_loops=4` etc.) → print time/filament/cost estimate, plus
     notes on supports, orientation and tolerances (`references/print-rules.md`).
   - Rigged: GLB (+ FBX) with animations listed (clip names + durations from `mesh_check --track rigged`);
     `web_optimize.sh --rigged` for web.
8. **Report.** Files (absolute paths), dimensions, poly counts, credits used (from meshy-log.md), licenses (credits.md
   for any Poly Haven/third-party assets), and 3 suggested variations.

## Quality bar
Real-world scale always (mm for print, meters in Blender/glTF); clean topology for anything animated; no floating or
intersecting geometry; studio-grade lighting on renders (no flat default light — use `render.sh` presets);
web GLB ≤ budget in web-3d-rules.md; print parts respect print-rules.md (≥ 1.2 mm walls, ≤ 45° unsupported overhangs
unless designed, named fit tolerances).

## Hard rules
- **Meshy credits:** balance check + cost table + explicit approval before every credit-spending call; previews before
  refines; never retry a failed paid task without asking; cancel only PENDING tasks (IN_PROGRESS is not refunded).
- Never commit API keys, model weights, renders or large meshes; the project `.gitignore` already excludes them.
- The `blender-lab` MCP has no sandbox: no network, subprocess, preference or add-on changes from generated code, and no
  paths outside the project folder.
- Third-party assets go in credits.md with license and URL; Poly Haven API calls send `User-Agent: ultra-3d/1.0`.
