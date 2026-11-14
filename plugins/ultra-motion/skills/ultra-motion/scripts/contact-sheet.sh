#!/usr/bin/env bash
# contact-sheet.sh — ffmpeg tile grid of a video (1 fps by default) + optional full-size key frames. No network.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: contact-sheet.sh <video> [-o SHEET.png] [--fps F] [--cols N] [--width PX] [--at t1,t2,...]

  -o SHEET.png   output (default: <video>.sheet.png next to the video)
  --fps F        frames per second sampled (default 1; use 2–4 for short videos)
  --cols N       tiles per row (default 5)
  --width PX     tile width (default 384)
  --at LIST      also save full-size key frames at these seconds, e.g. --at 0.5,2,4.25
                 → <sheet>_t0.50.png … next to the sheet

Also writes SHEET.txt mapping each tile (row, col) to its timestamp, since tiles carry no text.
EOF
}

VIDEO=""; OUT=""; FPS=1; COLS=5; W=384; AT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -o) OUT="${2:?}"; shift 2 ;;
    --fps) FPS="${2:?}"; shift 2 ;;
    --cols) COLS="${2:?}"; shift 2 ;;
    --width) W="${2:?}"; shift 2 ;;
    --at) AT="${2:?}"; shift 2 ;;
    -*) echo "contact-sheet.sh: unknown option $1" >&2; usage >&2; exit 2 ;;
    *) VIDEO="$1"; shift ;;
  esac
done
[[ -n "$VIDEO" ]] || { usage >&2; exit 2; }
[[ -f "$VIDEO" ]] || { echo "contact-sheet.sh: no such file: $VIDEO" >&2; exit 1; }
for dep in ffmpeg ffprobe python3; do
  command -v "$dep" >/dev/null 2>&1 || { echo "contact-sheet.sh: missing $dep (brew install ffmpeg)" >&2; exit 1; }
done
[[ -n "$OUT" ]] || OUT="${VIDEO%.*}.sheet.png"
mkdir -p "$(dirname "$OUT")"

DUR="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$VIDEO")"
VFPS="$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 "$VIDEO")"
NFR="$(ffprobe -v error -select_streams v:0 -count_packets -show_entries stream=nb_read_packets -of csv=p=0 "$VIDEO")"

# Pick exact frame numbers at the middle of each 1/FPS interval: tile k shows frame round((k+0.5)/FPS * vfps).
# (The fps filter's rounding drifts by up to half an interval, so frames are selected by index instead.)
FRAMES="$(python3 -I - "$DUR" "$FPS" "$VFPS" "$NFR" <<'PY'
import math, sys
dur, fps, nfr = float(sys.argv[1]), float(sys.argv[2]), int(sys.argv[4])
num, _, den = sys.argv[3].partition("/")
vfps = float(num) / float(den or 1)
n = max(1, math.ceil(dur * fps))
idx = sorted({min(nfr - 1, int(round((k + 0.5) / fps * vfps))) for k in range(n)})
print(f"{vfps} " + " ".join(map(str, idx)))
PY
)"
VFPS_F="${FRAMES%% *}"; IDX=(${FRAMES#* })
N="${#IDX[@]}"
ROWS=$(( (N + COLS - 1) / COLS ))
SEL="$(printf 'eq(n\\,%s)+' "${IDX[@]}")"; SEL="${SEL%+}"

ffmpeg -nostdin -hide_banner -loglevel error -y -i "$VIDEO" \
  -vf "select='${SEL}',scale=${W}:-2:flags=lanczos,tile=${COLS}x${ROWS}:padding=6:margin=6:color=0x1b1b1b" \
  -fps_mode passthrough -frames:v 1 -update 1 "$OUT"

python3 -I - "$OUT" "$COLS" "$FPS" "$DUR" "$VIDEO" "$VFPS_F" "${IDX[@]}" <<'PY'
import sys
out, cols, fps, dur, video, vfps = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4]), sys.argv[5], float(sys.argv[6])
idx = [int(x) for x in sys.argv[7:]]
with open(out.rsplit(".", 1)[0] + ".txt", "w") as f:
    f.write(f"contact sheet of {video} ({dur:.2f}s @ {vfps:g} fps, sampled {fps:g}/s, {cols} cols)\n")
    for k, fr in enumerate(idx):
        f.write(f"tile {k+1:>3}  row {k//cols+1} col {k%cols+1}  frame {fr:>5}  t={fr/vfps:7.3f}s\n")
PY

if [[ -n "$AT" ]]; then
  IFS=',' read -r -a TIMES <<< "$AT"
  for t in "${TIMES[@]}"; do
    [[ "$t" =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "contact-sheet.sh: bad time in --at: $t" >&2; exit 2; }
    f="${OUT%.*}_t$(printf '%.2f' "$t").png"
    ffmpeg -nostdin -hide_banner -loglevel error -y -ss "$t" -i "$VIDEO" -frames:v 1 -update 1 "$f"
    echo "frame=$f"
  done
fi
echo "sheet=$OUT"
echo "legend=${OUT%.*}.txt"
echo "tiles=$N (${COLS}x${ROWS})"
