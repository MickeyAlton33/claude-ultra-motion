#!/usr/bin/env bash
# install.sh — idempotent installer for the Ultra Motion free stack on macOS.
# Asks before every Homebrew install and every download over ~200 MB. Safe to re-run: skips what's present.
# Network: Homebrew, PyPI, npm, GitHub (plugins) and Hugging Face (Kokoro, whisper, FLUX weights).
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: setup/install.sh [--yes] [--minimal] [--help]

  --yes      answer yes to every prompt (still never runs sudo without a terminal to ask for the password)
  --minimal  required tools only: skip LaTeX, Blender and FLUX

Installs into: Homebrew (espeak-ng, whisper-cpp, cairo, pango, pkg-config, ffmpeg, uv, node),
~/.ultra-motion (Kokoro venv + weights, whisper model, FLUX weights), uv tools (manim, mflux),
Claude Code plugins (hyperframes, gsap-skills), optional BasicTeX, Blender + its MCP add-on.
Ends by running doctor.sh.
EOF
}

YES=0; MINIMAL=0
for a in "$@"; do
  case "$a" in
    -h|--help) usage; exit 0 ;;
    --yes) YES=1 ;;
    --minimal) MINIMAL=1 ;;
    *) echo "install.sh: unknown option $a" >&2; usage >&2; exit 2 ;;
  esac
done

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$REPO_DIR/plugins/ultra-motion/skills/ultra-motion/scripts"
UM_HOME="${ULTRA_MOTION_HOME:-$HOME/.ultra-motion}"
export HF_HOME="$UM_HOME/hf"

say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
ask()  {  # ask "question" → 0 yes / 1 no
  [[ $YES -eq 1 ]] && return 0
  [[ -t 0 ]] || { echo "  (no terminal: skipping — re-run interactively or with --yes)"; return 1; }
  local r; read -r -p "  $1 [y/N] " r; [[ "$r" =~ ^[Yy] ]]
}
brew_has() { brew list --versions "$1" >/dev/null 2>&1; }

[[ "$(uname -s)" == Darwin ]] || { echo "install.sh: macOS only" >&2; exit 1; }
ARCH="$(uname -m)"
have brew || { echo "install.sh: Homebrew is required: https://brew.sh" >&2; exit 1; }
mkdir -p "$UM_HOME/models" "$HF_HOME"

say "1/9 Homebrew formulae"
NEED=()
for f in ffmpeg uv node espeak-ng whisper-cpp cairo pango pkg-config; do brew_has "$f" || NEED+=("$f"); done
if [[ ${#NEED[@]} -eq 0 ]]; then echo "  all present"
elif ask "brew install ${NEED[*]} ?"; then brew install "${NEED[@]}"
else echo "  skipped"; fi

say "2/9 Claude Code plugins (HyperFrames, GSAP skills)"
if have claude; then
  installed="$(claude plugin list 2>/dev/null || true)"
  if ! grep -q 'hyperframes@hyperframes' <<<"$installed"; then
    claude plugin marketplace add heygen-com/hyperframes && claude plugin install hyperframes@hyperframes
  else echo "  hyperframes present"; fi
  if ! grep -q 'gsap-skills@gsap-skills' <<<"$installed"; then
    claude plugin marketplace add greensock/gsap-skills && claude plugin install gsap-skills@gsap-skills
  else echo "  gsap-skills present"; fi
else
  echo "  claude CLI not found — install Claude Code, then re-run"
fi

say "3/9 Manim Community"
if have manim; then echo "  present: $(manim --version 2>&1 | head -1)"
else uv tool install --python 3.12 manim; fi

say "4/9 Kokoro TTS venv (~1 GB, Python 3.12)"
VENV_PY="$UM_HOME/venv/bin/python"
if [[ -x "$VENV_PY" ]] && "$VENV_PY" -c 'import kokoro, soundfile' 2>/dev/null; then echo "  present"
elif ask "create $UM_HOME/venv and install kokoro + torch (~1 GB)?"; then
  [[ -x "$VENV_PY" ]] || uv venv --python 3.12 "$UM_HOME/venv"
  uv pip install --python "$VENV_PY" "kokoro>=0.9.4" soundfile pip
else echo "  skipped"; fi
if [[ -x "$VENV_PY" ]] && [[ ! -d "$HF_HOME/hub/models--hexgrad--Kokoro-82M" ]]; then
  if ask "download Kokoro-82M weights (~330 MB) now?"; then
    printf 'Ultra Motion is ready.\n' > "$UM_HOME/.tts-warmup.txt"
    "$SCRIPTS/tts.py" "$UM_HOME/.tts-warmup.txt" -o "$UM_HOME/.tts-warmup.wav" >/dev/null && echo "  Kokoro ready"
    rm -f "$UM_HOME/.tts-warmup.txt" "$UM_HOME/.tts-warmup.wav" "$UM_HOME/.tts-warmup.beats.json"
  fi
fi

say "5/9 whisper.cpp model (ggml-small, ~490 MB)"
WM="$UM_HOME/models/ggml-small.bin"
if [[ -s "$WM" ]]; then echo "  present"
elif ask "download ggml-small.bin (~490 MB) to $UM_HOME/models?"; then
  curl -fL --progress-bar -o "$WM.part" https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin
  mv "$WM.part" "$WM"
else echo "  skipped"; fi

if [[ $MINIMAL -eq 1 ]]; then
  echo; echo "--minimal: skipping LaTeX, Blender, FLUX"
else
  say "6/9 BasicTeX for Manim MathTex (optional, ~300 MB, needs your sudo password)"
  if have latex || [[ -x /Library/TeX/texbin/latex ]]; then echo "  present"
  elif [[ -t 0 ]] && ask "brew install --cask basictex + Manim's TeX packages (sudo)?"; then
    brew install --cask basictex
    eval "$(/usr/libexec/path_helper)"
    sudo tlmgr update --self
    sudo tlmgr install standalone preview doublestroke relsize fundus-calligra wasysym physics dvisvgm rsfs \
      wasy cm-super babel-english gnu-freefont mathastext cbfonts-fd ragged2e setspace ms microtype jknapltx
  else echo "  skipped (Manim Text() still works; MathTex/Tex need LaTeX)"; fi

  say "7/9 Blender + MCP add-on (optional 3D, ~1 GB)"
  BL=/Applications/Blender.app/Contents/MacOS/Blender
  if [[ -x "$BL" ]]; then echo "  Blender present: $("$BL" --version 2>/dev/null | head -1)"
  elif ask "brew install --cask blender (~1 GB)?"; then brew install --cask blender
  fi
  if [[ -x "$BL" ]]; then
    VER="$("$BL" --version 2>/dev/null | head -1 | awk '{print $2}' | cut -d. -f1,2)"
    ADDONS="$HOME/Library/Application Support/Blender/$VER/scripts/addons"
    if [[ -f "$ADDONS/blender_mcp.py" ]]; then echo "  MCP add-on present"
    elif ask "install the MCP for Blender add-on into Blender $VER and enable it?"; then
      mkdir -p "$ADDONS"
      BLENDERMCP_ADDONS_DIR="$ADDONS" DISABLE_TELEMETRY=true uvx mcp-for-blender install-addon
      "$BL" -b --python-expr "import bpy, addon_utils; addon_utils.enable('blender_mcp', default_set=True, persistent=True); bpy.ops.wm.save_userpref()" >/dev/null 2>&1 \
        && echo "  add-on enabled (paid generators and telemetry consent stay off by default)"
    fi
    if have claude && ! claude mcp list 2>/dev/null | grep -qi blender; then
      if ask "register the blender MCP in Claude Code (safe mode, telemetry off)?"; then
        claude mcp add blender -s user -e BLENDER_MCP_SAFE_MODE=1 -e DISABLE_TELEMETRY=true -- uvx mcp-for-blender
      fi
    else echo "  a blender MCP is already registered"; fi
  fi

  say "8/9 mflux + FLUX.1 schnell 4-bit (optional, Apple Silicon, ~10 GB)"
  if [[ "$ARCH" != arm64 ]]; then echo "  skipped: needs Apple Silicon"
  else
    have mflux-generate || { ask "uv tool install mflux?" && uv tool install --python 3.12 mflux; } || true
    if have mflux-generate && [[ ! -d "$HF_HOME/hub/models--mflux-community--flux-1-schnell-mflux-q4/snapshots" ]]; then
      free_gb="$(df -g "$HOME" | awk 'NR==2{print $4}')"
      echo "  free disk: ${free_gb} GB (weights need 9.6 GB + headroom; generation peaks ~10.5 GB RAM)"
      if ask "download FLUX.1 schnell q4 weights (9.6 GB) now?"; then
        "$SCRIPTS/img.sh" --allow-download "a ceramic cup on a plain backdrop" -o "$UM_HOME/.flux-warmup.png" \
          --w 512 --h 512 --steps 2 --seed 1 && rm -f "$UM_HOME/.flux-warmup.png" "$UM_HOME/.flux-warmup.png.txt"
      fi
    else echo "  present or skipped"; fi
  fi
fi

say "9/9 doctor"
"$SCRIPTS/doctor.sh" || true
