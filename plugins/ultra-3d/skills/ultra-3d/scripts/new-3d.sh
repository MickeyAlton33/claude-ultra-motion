#!/usr/bin/env bash
# new-3d.sh — scaffold an ultra-3d project.
#
# Usage: new-3d.sh <name> [--track visual|web|print|rigged] [--dir ~/3d] [--no-git]
#
# Creates <dir>/<slug>/ with:
#   brief.md      what / purpose / track / dimensions / style refs / acceptance criteria
#   refs/         reference images (inputs for Meshy image-to-3D and for the reviewer)
#   src/          parametric CAD source (build123d .py / OpenSCAD .scad) and Blender .blend files
#   assets/       downloaded/generated inputs: meshy/, polyhaven/, third-party/  (git-ignored)
#   exports/      deliverables: STL/3MF/GLB/FBX, slices/                       (git-ignored)
#   renders/      stills, turntables, contact sheets                            (git-ignored)
#   credits.md    licenses for every third-party asset (Poly Haven = CC0, Meshy = per plan)
#   CLAUDE.md     project rules for Claude (units, track, budgets, credit discipline)
#   meshy-log.md  every Meshy task: id, prompt, mode, credits, chosen/rejected
set -euo pipefail
NAME="${1:-}"; [[ -z "$NAME" || "$NAME" == -* ]] && { sed -n '2,16p' "$0"; exit 1; }
shift
TRACK="visual"; BASE="${ULTRA3D_PROJECTS:-$HOME/3d}"; GIT=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --track) TRACK="$2"; shift 2;;
    --dir) BASE="$2"; shift 2;;
    --no-git) GIT=0; shift;;
    *) echo "unknown option $1" >&2; exit 1;;
  esac
done
case "$TRACK" in visual|web|print|rigged) ;; *) echo "track must be visual|web|print|rigged" >&2; exit 1;; esac
SLUG="$(echo "$NAME" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"
P="$BASE/$SLUG"
[[ -e "$P" ]] && { echo "exists: $P" >&2; exit 1; }
mkdir -p "$P"/{refs,src,assets/meshy,assets/polyhaven,assets/third-party,exports/slices,renders}
TODAY="$(date +%Y-%m-%d)"

case "$TRACK" in
  print)  UNITS="millimetres (CAD and STL/3MF are mm; Bambu P2S build volume 256×256×256 mm)";;
  *)      UNITS="metres in Blender and glTF (1 unit = 1 m); real-world scale always";;
esac

cat > "$P/brief.md" <<EOF
# $NAME — brief  ($TODAY)

**Track:** $TRACK
**What it is / purpose:**
**Dimensions / scale:**  (e.g. 80 × 60 × 40 mm, or "fits a 1.8 m character")
**Style references:** (files in refs/, URLs, adjectives)
**Must fit / interface with:** (screws, phone, shelf, other parts — with measured numbers)
**Material / finish:** (PLA matte, anodised aluminium look, ceramic glaze, …)

## Acceptance criteria
- [ ] mesh_check PASS for the $TRACK track
- [ ] 3d-reviewer verdict APPROVED
- [ ] exports delivered: (list)

## Decisions log
- $TODAY  project created
EOF

cat > "$P/CLAUDE.md" <<EOF
# $NAME — ultra-3d project rules

- Track: **$TRACK**. Units: $UNITS.
- Follow the ultra-3d skill pipeline; commit to git after each stage (brief, concept, build, check, review, export).
- Parametric sources live in src/ with **named dimensions at the top**; never hand-edit exported meshes of CAD parts.
- Every export gets \`mesh_check.py\` before review; fix with \`mesh_fix.py\` or in the CAD source.
- **Meshy costs credits.** Check the balance, state the credit cost, wait for approval, previews before refines.
  Log every task in meshy-log.md.
- Third-party assets → credits.md (name, author, license, URL). Poly Haven = CC0.
- Blender MCP: only read/write files inside this folder ($P).
- Never commit API keys, model weights, or large binaries (exports/, renders/, assets/ are git-ignored).
EOF

cat > "$P/credits.md" <<EOF
# Credits & licenses — $NAME

| Asset | Source | Author | License | URL |
|---|---|---|---|---|
EOF

cat > "$P/meshy-log.md" <<EOF
# Meshy log — $NAME

| Date | Task ID | Mode (preview/refine/rig/anim) | Prompt / image | Credits | Kept? |
|---|---|---|---|---|---|
EOF

cat > "$P/.gitignore" <<'EOF'
assets/
exports/
renders/
*.blend1
*.blend2
*.stl
*.3mf
*.glb
*.gltf
*.fbx
*.obj
*.gcode
*.mp4
*.hdr
*.exr
.env*
__pycache__/
.DS_Store
EOF

if [[ "$TRACK" == "print" ]]; then
cat > "$P/src/part.py" <<'EOF'
"""Parametric part — build123d. Named dimensions first (mm). Run: ~/.ultra-3d/venv/bin/python src/part.py"""
from pathlib import Path
from build123d import *

# ---- named dimensions (mm) ------------------------------------------------------------
WIDTH = 60.0
DEPTH = 40.0
HEIGHT = 20.0
WALL = 2.0            # ≥ 1.2 mm (3 perimeters @ 0.4 mm nozzle ≈ 1.2 mm)
FILLET = 4.0          # vertical edge radius; must be > WALL or the shell (offset) op fails
CLEARANCE = 0.2       # slide fit; press fit 0.05–0.1, loose 0.3–0.4

# ---- model --------------------------------------------------------------------------------
with BuildPart() as part:
    Box(WIDTH, DEPTH, HEIGHT, align=(Align.CENTER, Align.CENTER, Align.MIN))
    fillet(part.edges().filter_by(Axis.Z), radius=FILLET)
    top = part.faces().sort_by(Axis.Z)[-1]
    offset(amount=-WALL, openings=top)

# ---- export ---------------------------------------------------------------------------------
out = Path(__file__).resolve().parent.parent / "exports"
out.mkdir(exist_ok=True)
# display copy for render.sh: front must face -Y (rotate here if your front is elsewhere)
export_stl(part.part, str(out / "part_display.stl"), tolerance=0.01, angular_tolerance=0.1)
export_step(part.part, str(out / "part.step"))
# print copy: already in print orientation, resting on Z = 0 (rotate here, never in the slicer)
printable = part.part  # e.g. part.part.rotate(Axis.X, -90) to print on its side
printable = printable.move(Location((0, 0, -printable.bounding_box().min.Z)))
export_stl(printable, str(out / "part.stl"), tolerance=0.01, angular_tolerance=0.1)
m = Mesher(); m.add_shape(printable); m.write(str(out / "part.3mf"))
bb = part.part.bounding_box().size
print(f"part: {bb.X:.2f} x {bb.Y:.2f} x {bb.Z:.2f} mm, volume {part.part.volume/1000:.2f} cm3")
EOF
fi

echo "created $P"
if [[ "$GIT" == 1 ]]; then
  ( cd "$P" && git init -q -b main && git add -A && git commit -q -m "Scaffold $NAME ($TRACK track)" && echo "git: initial commit" )
fi
find "$P" -maxdepth 2 -not -path "*/.git*" | sed "s|$BASE/||" | sort
