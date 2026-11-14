#!/usr/bin/env bash
# img.sh — local still images with mflux + FLUX.1 schnell (Apache-2.0), 4-bit, Apple Silicon.
# No-op (exit 0 with a message) if mflux isn't installed.
# Network: only with --allow-download, for the one-time 9.6 GB weights download; otherwise offline.
set -euo pipefail

MODEL="mflux-community/flux-1-schnell-mflux-q4"   # pinned: schnell only, never dev/krea/kontext (non-commercial)
UM_HOME="${ULTRA_MOTION_HOME:-$HOME/.ultra-motion}"
export HF_HOME="${HF_HOME:-$UM_HOME/hf}"
CACHE="$HF_HOME/hub/models--mflux-community--flux-1-schnell-mflux-q4"

usage() {
  cat <<'EOF'
Usage: img.sh "<prompt>" -o OUT.png [--w 1920] [--h 1088] [--steps 4] [--seed N] [--allow-download]

  --w/--h            size in px, rounded to a multiple of 16 (default 1920x1088; crop to 1080 later)
  --steps            denoising steps, schnell is tuned for 2–4 (default 4)
  --seed             integer seed (default: random, printed)
  --allow-download   permit the one-time 9.6 GB weights download (needed on a fresh machine)

Writes OUT.png and OUT.png.txt (prompt, seed, model, licence) for credits.md.
If mflux isn't installed: prints a message and exits 0 without making an image.
EOF
}

PROMPT=""; OUT=""; W=1920; H=1088; STEPS=4; SEED=""; ALLOW=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -o) OUT="${2:?}"; shift 2 ;;
    --w) W="${2:?}"; shift 2 ;;
    --h) H="${2:?}"; shift 2 ;;
    --steps) STEPS="${2:?}"; shift 2 ;;
    --seed) SEED="${2:?}"; shift 2 ;;
    --allow-download) ALLOW=1; shift ;;
    -*) echo "img.sh: unknown option $1" >&2; usage >&2; exit 2 ;;
    *) [[ -z "$PROMPT" ]] || { echo "img.sh: one prompt only (quote it)" >&2; exit 2; }; PROMPT="$1"; shift ;;
  esac
done
[[ -n "$PROMPT" && -n "$OUT" ]] || { usage >&2; exit 2; }

if ! command -v mflux-generate >/dev/null 2>&1; then
  echo "img.sh: mflux is not installed — skipping image generation (no-op)."
  echo "        To enable (Apple Silicon, ~10 GB): uv tool install --python 3.12 mflux && img.sh --allow-download \"test\" -o /tmp/t.png"
  exit 0
fi
[[ "$(uname -m)" == "arm64" ]] || { echo "img.sh: mflux needs Apple Silicon (arm64)" >&2; exit 1; }
for v in "$W" "$H" "$STEPS"; do [[ "$v" =~ ^[0-9]+$ ]] || { echo "img.sh: --w/--h/--steps must be integers" >&2; exit 2; }; done
W=$(( (W + 15) / 16 * 16 )); H=$(( (H + 15) / 16 * 16 ))
[[ -n "$SEED" ]] || SEED=$(( RANDOM * 32768 + RANDOM ))

if [[ -d "$CACHE/snapshots" ]]; then
  export HF_HUB_OFFLINE=1
elif [[ $ALLOW -eq 1 ]]; then
  echo "img.sh: downloading $MODEL (~9.6 GB, one time) into $HF_HOME …" >&2
else
  echo "img.sh: FLUX.1 schnell weights are not cached. Re-run with --allow-download (one-time ~9.6 GB)." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"
mflux-generate --model "$MODEL" --base-model schnell --steps "$STEPS" --seed "$SEED" \
  --width "$W" --height "$H" --prompt "$PROMPT" --output "$OUT" 2>&1 | grep -v -E '%\||it/s|s/it' || true
[[ -s "$OUT" ]] || { echo "img.sh: generation failed (no output written)" >&2; exit 1; }

cat > "$OUT.txt" <<EOF
prompt: $PROMPT
seed: $SEED
size: ${W}x${H}, steps: $STEPS
model: $MODEL (FLUX.1 schnell, black-forest-labs, Apache-2.0), generated locally with mflux
EOF
echo "image=$OUT"
echo "seed=$SEED"
