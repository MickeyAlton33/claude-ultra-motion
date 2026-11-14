#!/usr/bin/env bash
# render.sh — headless Blender studio renders: hero stills + turntable MP4 + review contact sheet.
#
# Usage:
#   render.sh MODEL [MODEL…] [--out DIR] [--preset product|dark|white|clay] [--material pla|clay|…]
#             [--color "#hex"] [--units auto|mm|m] [--final] [--quick] [--turntable N|0]
#             [--stills hero,front,side,top,detail] [--engine cycles|eevee] [--hdri FILE]
#             [--transparent] [--save-blend FILE] [--name NAME]
#
#   --quick   review pass: 1280x720, 48 samples, 72-frame EEVEE turntable  (default)
#   --final   delivery:    3840x2160, 256 samples, 180-frame Cycles turntable at 1920x1080
#
# Outputs (in --out, default ./renders or <project>/renders):
#   <name>_<still>.png · <name>_turntable.mp4 · <name>_contact.png (8 turntable frames, for review)
# 3MF inputs are converted to STL (mm) first. STL/PLY/OBJ are treated as mm, GLB/FBX/USD as meters.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLENDER="${ULTRA3D_BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
PY="${ULTRA3D_PY:-$HOME/.ultra-3d/venv/bin/python}"
[[ -x "$BLENDER" ]] || { echo "Blender not found at $BLENDER (set ULTRA3D_BLENDER)" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg not found (brew install ffmpeg)" >&2; exit 1; }

MODELS=(); OUT=""; MODE="quick"; TT=""; PASS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT="$2"; shift 2;;
    --final) MODE="final"; shift;;
    --quick) MODE="quick"; shift;;
    --turntable) TT="$2"; shift 2;;
    --preset|--material|--color|--units|--stills|--engine|--hdri|--save-blend|--name|--focal|--samples)
      PASS+=("$1" "$2"); shift 2;;
    --transparent) PASS+=("$1"); shift;;
    -h|--help) sed -n '2,16p' "$0"; exit 0;;
    -*) echo "unknown option $1" >&2; exit 1;;
    *) MODELS+=("$1"); shift;;
  esac
done
[[ ${#MODELS[@]} -gt 0 ]] || { sed -n '2,16p' "$0"; exit 1; }

FIRST="${MODELS[0]}"
NAME="$(basename "${FIRST%.*}")"
for ((i = 0; i < ${#PASS[@]}; i++)); do [[ "${PASS[$i]}" == "--name" ]] && NAME="${PASS[$((i + 1))]}"; done
if [[ -z "$OUT" ]]; then
  d="$(cd "$(dirname "$FIRST")" && pwd)"
  if [[ -d "$d/../renders" ]]; then OUT="$(cd "$d/../renders" && pwd)"; else OUT="$PWD/renders"; fi
fi
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ultra3d-render.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT

INPUTS=()
for m in "${MODELS[@]}"; do
  [[ -f "$m" ]] || { echo "not found: $m" >&2; exit 1; }
  abs="$(cd "$(dirname "$m")" && pwd)/$(basename "$m")"
  if [[ "$(echo "$abs" | tr '[:upper:]' '[:lower:]')" == *.3mf ]]; then   # bash 3.2-safe lowercase
    conv="$WORK/$(basename "${abs%.*}").stl"
    "$PY" -c "import trimesh,sys; trimesh.load(sys.argv[1], force='mesh').export(sys.argv[2])" "$abs" "$conv"
    abs="$conv"
  fi
  INPUTS+=(--input "$abs")
done

if [[ "$MODE" == "final" ]]; then
  ARGS=(--final --tt-engine cycles --tt-res 1920x1080); TT="${TT:-180}"
else
  ARGS=(--res 1280x720 --samples 48 --tt-engine eevee --tt-res 1280x720); TT="${TT:-72}"
fi

echo "render [$MODE] $NAME → $OUT"
LOG="$OUT/.${NAME}_render.log"
set +e
"$BLENDER" -b --factory-startup --python "$HERE/blender_studio.py" -- \
  "${INPUTS[@]}" --out "$OUT" --name "$NAME" --turntable "$TT" "${ARGS[@]}" "${PASS[@]}" >"$LOG" 2>&1
RC=$?
set -e
grep -E "^STUDIO" "$LOG" || true
if [[ $RC -ne 0 ]] || ! grep -q "STUDIO_OK" "$LOG"; then
  echo "Blender failed (rc=$RC) — log tail:" >&2; tail -30 "$LOG" >&2; exit 1
fi

FR="$OUT/.${NAME}_turntable_frames"
if [[ "$TT" -gt 0 && -d "$FR" ]]; then
  ffmpeg -y -loglevel error -framerate 30 -i "$FR/f_%04d.png" -c:v libx264 -pix_fmt yuv420p \
    -crf 18 -movflags +faststart "$OUT/${NAME}_turntable.mp4"
  step=$(( TT / 8 > 0 ? TT / 8 : 1 ))
  ffmpeg -y -loglevel error -framerate 30 -i "$FR/f_%04d.png" \
    -vf "select='not(mod(n\,$step))',scale=640:-2,tile=4x2:padding=6:color=white" -frames:v 1 \
    "$OUT/${NAME}_contact.png"
  rm -rf "$FR"
  echo "turntable: $OUT/${NAME}_turntable.mp4"
  echo "contact sheet (review this): $OUT/${NAME}_contact.png"
fi
ls -1 "$OUT" | grep -E "^${NAME}_" | sed "s|^|  $OUT/|"
