#!/usr/bin/env bash
# deliver.sh — master video -> loudness-normalized 16:9 / 9:16 / 1:1 MP4s + GIF preview. No network.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: deliver.sh <master.mp4> [-o OUTDIR] [-n NAME] [--formats 16x9,9x16,1x1]
                  [--master-16x9 F] [--master-9x16 F] [--master-1x1 F] [--fit crop|pad]
                  [--lufs -14] [--tp -1.5] [--gif-seconds 6] [--no-gif]

  -o OUTDIR        output folder (default: <master dir>/deliver)
  -n NAME          file name stem (default: master file name)
  --formats        which to make (default 16x9,9x16,1x1)
  --master-XxY     a dedicated render for that aspect (preferred: re-laid-out composition)
  --fit            how to reframe when no dedicated master matches the aspect:
                     crop = scale to cover + centre crop (default)   pad = blurred-fill background
  --lufs / --tp    integrated loudness target and true-peak ceiling (default -14 LUFS, -1.5 dBTP)
  --gif-seconds    length of the GIF preview from the start (default 6); --no-gif to skip

Audio: two-pass EBU R128 loudnorm of the master's soundtrack, shared by every format.
Video: H.264 High, yuv420p, CRF 18, +faststart; AAC 192 kb/s 48 kHz.
Outputs: NAME_16x9.mp4 (1920x1080), NAME_9x16.mp4 (1080x1920), NAME_1x1.mp4 (1080x1080), NAME_preview.gif
EOF
}

MASTER=""; OUTDIR=""; NAME=""; FORMATS="16x9,9x16,1x1"; FIT="crop"; LUFS="-14"; TP="-1.5"
GIFSEC=6; GIF=1; M169=""; M916=""; M11=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -o) OUTDIR="${2:?}"; shift 2 ;;
    -n) NAME="${2:?}"; shift 2 ;;
    --formats) FORMATS="${2:?}"; shift 2 ;;
    --master-16x9) M169="${2:?}"; shift 2 ;;
    --master-9x16) M916="${2:?}"; shift 2 ;;
    --master-1x1) M11="${2:?}"; shift 2 ;;
    --fit) FIT="${2:?}"; shift 2 ;;
    --lufs) LUFS="${2:?}"; shift 2 ;;
    --tp) TP="${2:?}"; shift 2 ;;
    --gif-seconds) GIFSEC="${2:?}"; shift 2 ;;
    --no-gif) GIF=0; shift ;;
    -*) echo "deliver.sh: unknown option $1" >&2; usage >&2; exit 2 ;;
    *) MASTER="$1"; shift ;;
  esac
done
[[ -n "$MASTER" ]] || { usage >&2; exit 2; }
for f in "$MASTER" "$M169" "$M916" "$M11"; do
  [[ -z "$f" || -f "$f" ]] || { echo "deliver.sh: no such file: $f" >&2; exit 1; }
done
[[ "$FIT" == crop || "$FIT" == pad ]] || { echo "deliver.sh: --fit must be crop or pad" >&2; exit 2; }
for dep in ffmpeg ffprobe python3; do
  command -v "$dep" >/dev/null 2>&1 || { echo "deliver.sh: missing $dep (brew install ffmpeg)" >&2; exit 1; }
done
[[ -n "$OUTDIR" ]] || OUTDIR="$(cd "$(dirname "$MASTER")" && pwd)/deliver"
[[ -n "$NAME" ]] || { NAME="$(basename "$MASTER")"; NAME="${NAME%.*}"; }
mkdir -p "$OUTDIR"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FF=(ffmpeg -nostdin -hide_banner -loglevel error -y)

dims() { ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$1"; }
has_audio() { [[ -n "$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$1")" ]]; }

# ---- audio: two-pass loudnorm -------------------------------------------------
HAS_A=0
if has_audio "$MASTER"; then
  HAS_A=1
  echo "→ measuring loudness"
  ffmpeg -nostdin -hide_banner -loglevel info -i "$MASTER" -vn \
    -af "loudnorm=I=${LUFS}:TP=${TP}:LRA=11:print_format=json" -f null - 2> "$TMP/pass1.log" || true
  FILTER="$(python3 -I - "$TMP/pass1.log" "$LUFS" "$TP" <<'PY'
import json, re, sys
log, I, TP = open(sys.argv[1]).read(), sys.argv[2], sys.argv[3]
m = re.findall(r"\{[^{}]*\"input_i\"[^{}]*\}", log)
if not m:
    sys.exit("deliver.sh: loudnorm measurement failed")
d = json.loads(m[-1])
if d["input_i"] in ("-inf", "inf"):
    print("anull")   # silent track: nothing to normalize
else:
    print(f"loudnorm=I={I}:TP={TP}:LRA=11:measured_I={d['input_i']}:measured_TP={d['input_tp']}:"
          f"measured_LRA={d['input_lra']}:measured_thresh={d['input_thresh']}:offset={d['target_offset']}:linear=true")
PY
)"
  echo "→ normalizing to ${LUFS} LUFS / ${TP} dBTP"
  "${FF[@]}" -i "$MASTER" -vn -af "${FILTER},aresample=48000" -c:a aac -b:a 192k "$TMP/audio.m4a"
fi

# ---- video formats ------------------------------------------------------------
vf_for() {  # $1 target WxH, $2 source WxH
  local tw="${1%x*}" th="${1#*x}" sw="${2%x*}" sh="${2#*x}"
  if python3 -I -c "import sys; sys.exit(0 if abs($sw/$sh - $tw/$th) < 0.01 else 1)"; then
    echo "[0:v]scale=${tw}:${th}:flags=lanczos,setsar=1,format=yuv420p[v]"
  elif [[ "$FIT" == crop ]]; then
    echo "[0:v]scale=${tw}:${th}:force_original_aspect_ratio=increase:flags=lanczos,crop=${tw}:${th},setsar=1,format=yuv420p[v]"
  else
    echo "[0:v]split[a][b];[a]scale=${tw}:${th}:force_original_aspect_ratio=increase,crop=${tw}:${th},boxblur=40:2,eq=brightness=-0.08[bg];[b]scale=${tw}:${th}:force_original_aspect_ratio=decrease:flags=lanczos[fg];[bg][fg]overlay=(W-w)/2:(H-h)/2,setsar=1,format=yuv420p[v]"
  fi
}

declare -a MADE=()
IFS=',' read -r -a FMTS <<< "$FORMATS"
for fmt in "${FMTS[@]}"; do
  case "$fmt" in
    16x9) size=1920x1080; src="${M169:-$MASTER}" ;;
    9x16) size=1080x1920; src="${M916:-$MASTER}" ;;
    1x1)  size=1080x1080; src="${M11:-$MASTER}" ;;
    *) echo "deliver.sh: unknown format $fmt (use 16x9, 9x16, 1x1)" >&2; exit 2 ;;
  esac
  sdim="$(dims "$src")"
  note=""
  python3 -I -c "import sys; sys.exit(0 if abs(${sdim%x*}/${sdim#*x} - ${size%x*}/${size#*x}) < 0.01 else 1)" || note=" (reframed from ${sdim} by ${FIT} — a dedicated --master-${fmt} looks better)"
  out="$OUTDIR/${NAME}_${fmt}.mp4"
  echo "→ $fmt ${size}${note}"
  VENC=(-c:v libx264 -profile:v high -preset slow -crf 18 -pix_fmt yuv420p -movflags +faststart)
  if [[ $HAS_A -eq 1 ]]; then
    "${FF[@]}" -i "$src" -i "$TMP/audio.m4a" -filter_complex "$(vf_for "$size" "$sdim")" \
      -map "[v]" -map 1:a:0 -c:a copy -shortest "${VENC[@]}" "$out"
  else
    "${FF[@]}" -i "$src" -filter_complex "$(vf_for "$size" "$sdim")" -map "[v]" -an "${VENC[@]}" "$out"
  fi
  MADE+=("$out")
done

# ---- GIF preview ----------------------------------------------------------------
if [[ $GIF -eq 1 && ${#MADE[@]} -gt 0 ]]; then
  gif="$OUTDIR/${NAME}_preview.gif"
  echo "→ GIF preview (${GIFSEC}s)"
  "${FF[@]}" -t "$GIFSEC" -i "${MADE[0]}" \
    -filter_complex "fps=15,scale=640:-2:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a" \
    -loop 0 "$gif"
  MADE+=("$gif")
fi

# ---- report ---------------------------------------------------------------------
echo
printf '%-44s %-11s %8s %10s\n' "file" "size" "seconds" "LUFS"
for f in "${MADE[@]}"; do
  d="$(dims "$f")"; s="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f")"
  l="—"
  if [[ "$f" == *.mp4 ]] && has_audio "$f"; then
    l="$(ffmpeg -nostdin -hide_banner -i "$f" -vn -af ebur128=peak=true -f null - 2>&1 | awk '/^ *I:/ {v=$2} END {print v}')"
  fi
  printf '%-44s %-11s %8.2f %10s\n' "$(basename "$f")" "$d" "$s" "$l"
done
echo "outdir=$OUTDIR"
