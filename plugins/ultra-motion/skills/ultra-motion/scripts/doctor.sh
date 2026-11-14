#!/usr/bin/env bash
# doctor.sh — check every Ultra Motion dependency and print the fix for anything missing.
# No network. Exit 0 if all REQUIRED tools are present (optional ones only warn), 1 otherwise.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: doctor.sh [-q|--quiet] [-h|--help]

Checks the Ultra Motion stack and prints one line per tool:
  ✅ present   ❌ required and missing (with the fix)   ⚠️  optional and missing (with the fix)

Required: node ≥ 22, npx, ffmpeg, ffprobe, python3, uv, git, whisper-cli + model,
          espeak-ng, Kokoro venv, manim, HyperFrames + GSAP plugins.
Optional: LaTeX (Manim MathTex), Blender + blender MCP, mflux + FLUX.1 schnell weights.

  -q, --quiet   only print problems and the summary
Exit status: 0 = ready, 1 = a required tool is missing.
EOF
}

QUIET=0
for a in "$@"; do
  case "$a" in
    -h|--help) usage; exit 0 ;;
    -q|--quiet) QUIET=1 ;;
    *) echo "doctor.sh: unknown option: $a" >&2; usage >&2; exit 2 ;;
  esac
done

UM_HOME="${ULTRA_MOTION_HOME:-$HOME/.ultra-motion}"
WHISPER_MODEL="${UM_WHISPER_MODEL:-$UM_HOME/models/ggml-small.bin}"
BLENDER_APP="/Applications/Blender.app/Contents/MacOS/Blender"
FLUX_CACHE="$UM_HOME/hf/hub/models--mflux-community--flux-1-schnell-mflux-q4"
PLUGINS_JSON="$HOME/.claude/plugins/installed_plugins.json"

missing_required=0
missing_optional=0

ok()   { [[ $QUIET -eq 1 ]] || printf '✅ %-22s %s\n' "$1" "$2"; }
bad()  { printf '❌ %-22s missing — fix: %s\n' "$1" "$2"; missing_required=$((missing_required+1)); }
warn() { printf '⚠️  %-21s optional, missing — fix: %s\n' "$1" "$2"; missing_optional=$((missing_optional+1)); }
have() { command -v "$1" >/dev/null 2>&1; }

# --- required -----------------------------------------------------------------
if have node; then
  nv="$(node -v)"; major="${nv#v}"; major="${major%%.*}"
  if [[ "$major" -ge 22 ]]; then ok node "$nv"; else bad node "need ≥ 22 (have $nv): brew upgrade node"; fi
else bad node "brew install node"; fi

have npx && ok npx "$(npx -v 2>/dev/null)" || bad npx "brew install node"

for t in ffmpeg ffprobe; do
  if have "$t"; then ok "$t" "$("$t" -version 2>/dev/null | head -1 | awk '{print $3}')"; else bad "$t" "brew install ffmpeg"; fi
done

have python3 && ok python3 "$(python3 --version 2>&1 | awk '{print $2}')" || bad python3 "brew install python"
have uv && ok uv "$(uv --version | awk '{print $2}')" || bad uv "brew install uv"
have git && ok git "$(git --version | awk '{print $3}')" || bad git "xcode-select --install"

if have whisper-cli; then ok whisper-cli "$(whisper-cli --version 2>&1 | head -1 | awk '{print $NF}')"
else bad whisper-cli "brew install whisper-cpp"; fi
if [[ -s "$WHISPER_MODEL" ]]; then ok "whisper model" "$(basename "$WHISPER_MODEL")"
else bad "whisper model" "mkdir -p $UM_HOME/models && curl -fL -o $WHISPER_MODEL https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"; fi

have espeak-ng && ok espeak-ng "$(espeak-ng --version | awk '{print $4}')" || bad espeak-ng "brew install espeak-ng"

VENV_PY="$UM_HOME/venv/bin/python"
if [[ -x "$VENV_PY" ]] && "$VENV_PY" -c 'import importlib.util as u,sys; sys.exit(0 if u.find_spec("kokoro") and u.find_spec("soundfile") else 1)' 2>/dev/null; then
  ok kokoro "$("$VENV_PY" -c 'from importlib.metadata import version; print(version("kokoro"))')"
else
  bad kokoro "uv venv --python 3.12 $UM_HOME/venv && uv pip install --python $VENV_PY 'kokoro>=0.9.4' soundfile pip"
fi

if have manim; then ok manim "$(manim --version 2>&1 | grep -o -E 'v[0-9]+(\.[0-9]+)+' | head -1)"
else bad manim "brew install cairo pango pkg-config && uv tool install --python 3.12 manim"; fi

if [[ -f "$PLUGINS_JSON" ]] && grep -q '"hyperframes@hyperframes"' "$PLUGINS_JSON"; then ok "hyperframes plugin" "installed"
else bad "hyperframes plugin" "claude plugin marketplace add heygen-com/hyperframes && claude plugin install hyperframes@hyperframes"; fi
if [[ -f "$PLUGINS_JSON" ]] && grep -q '"gsap-skills@gsap-skills"' "$PLUGINS_JSON"; then ok "gsap-skills plugin" "installed"
else bad "gsap-skills plugin" "claude plugin marketplace add greensock/gsap-skills && claude plugin install gsap-skills@gsap-skills"; fi

# --- optional -----------------------------------------------------------------
if have latex || [[ -x /Library/TeX/texbin/latex ]]; then ok LaTeX "for Manim MathTex"
else warn LaTeX "brew install --cask basictex (sudo) then sudo tlmgr install standalone preview doublestroke relsize fundus-calligra wasysym physics dvisvgm rsfs wasy cm-super babel-english gnu-freefont mathastext cbfonts-fd"; fi

if [[ -x "$BLENDER_APP" ]]; then ok Blender "$("$BLENDER_APP" --version 2>/dev/null | head -1 | awk '{print $2}')"
else warn Blender "brew install --cask blender"; fi
blender_mcp="$(python3 -I - "$HOME/.claude.json" <<'PY' 2>/dev/null || true
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
found = []
def walk(o):
    if isinstance(o, dict):
        for k, v in (o.get("mcpServers") or {}).items():
            blob = json.dumps(v)
            if "blender" in k.lower() or "blender" in blob.lower():
                safe = "safe mode" if '"BLENDER_MCP_SAFE_MODE": "1"' in blob else "no safe mode"
                found.append(f"{k} ({safe})")
        for v in o.values():
            walk(v)
walk(d)
print(", ".join(dict.fromkeys(found)))
PY
)"
if [[ -n "$blender_mcp" ]]; then ok "blender MCP" "$blender_mcp"
else warn "blender MCP" "claude mcp add blender -s user -e BLENDER_MCP_SAFE_MODE=1 -e DISABLE_TELEMETRY=true -- uvx mcp-for-blender"; fi

if have mflux-generate; then ok mflux "installed"
else warn mflux "uv tool install --python 3.12 mflux   (Apple Silicon only)"; fi
if [[ -d "$FLUX_CACHE/snapshots" ]] && [[ -n "$(find -L "$FLUX_CACHE/snapshots" -name '*.safetensors' -size +100M 2>/dev/null | head -1)" ]]; then ok "FLUX.1 schnell q4" "weights cached"
else warn "FLUX.1 schnell q4" "img.sh --allow-download '<prompt>' -o x.png   (one-time 9.6 GB download)"; fi

# --- disk ---------------------------------------------------------------------
free_gb="$(df -g "$HOME" | awk 'NR==2{print $4}')"
if [[ "$free_gb" -lt 10 ]]; then
  printf '⚠️  %-21s only %s GB free — renders write many frames; free space before a full render\n' "disk" "$free_gb"
else
  [[ $QUIET -eq 1 ]] || printf '✅ %-22s %s GB free\n' "disk" "$free_gb"
fi

echo
if [[ $missing_required -eq 0 ]]; then
  echo "doctor: READY ($missing_optional optional item(s) missing)"
  exit 0
fi
echo "doctor: NOT READY — $missing_required required item(s) missing, $missing_optional optional"
exit 1
