#!/usr/bin/env bash
# doctor.sh — check every dependency of the ultra-3d pipeline and print the fix for anything missing.
# Usage: doctor.sh [--quiet]   (exit 0 = all required parts present, 1 = something required missing)
# Never installs anything itself: Homebrew/sudo/large downloads need the user's OK.
set -uo pipefail
Q=0; [[ "${1:-}" == "--quiet" ]] && Q=1
CONF="$HOME/.ultra-3d/config"
# shellcheck disable=SC1090
[[ -f "$CONF" ]] && set -a && source "$CONF" && set +a
BLENDER="${ULTRA3D_BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
PY="${ULTRA3D_PY:-$HOME/.ultra-3d/venv/bin/python}"
SLICER="${ULTRA3D_SLICER:-/Applications/BambuStudio.app/Contents/MacOS/BambuStudio}"
PRINTER="${ULTRA3D_PRINTER:-P2S}"
FAIL=0
ok()   { [[ $Q == 1 ]] || printf "  \033[32m✓\033[0m %-22s %s\n" "$1" "$2"; }
warn() { printf "  \033[33m!\033[0m %-22s %s\n      fix: %s\n" "$1" "$2" "$3"; }
bad()  { printf "  \033[31m✗\033[0m %-22s %s\n      fix: %s\n" "$1" "$2" "$3"; FAIL=1; }
ver_ge() { [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" == "$2" ]]; }

[[ $Q == 1 ]] || echo "ultra-3d doctor — $(date '+%Y-%m-%d %H:%M')"

# --- Blender + Blender Lab MCP --------------------------------------------------------------
if [[ -x "$BLENDER" ]]; then
  BV="$("$BLENDER" --version 2>/dev/null | awk '/^Blender/{print $2; exit}')"
  if ver_ge "$BV" "5.1"; then ok "blender" "$BV"; else bad "blender" "$BV < 5.1" "brew upgrade --cask blender"; fi
  MAJMIN="$(echo "$BV" | cut -d. -f1,2)"
  EXT="$HOME/Library/Application Support/Blender/$MAJMIN/extensions/user_default/mcp"
  if [[ -f "$EXT/blender_manifest.toml" ]]; then
    ok "blender-lab add-on" "$(awk -F'"' '/^version/{print $2}' "$EXT/blender_manifest.toml") (start the bridge: Preferences › Add-ons › MCP › Start)"
  else
    warn "blender-lab add-on" "not installed for Blender $MAJMIN" \
      "\"$BLENDER\" -b --command extension install-file -r user_default -e ~/.ultra-3d/downloads/blender-mcp-addon/mcp-1.0.3.zip"
  fi
else
  bad "blender" "not found at $BLENDER" "brew install --cask blender   (ask the user first)"
fi
if python3 - "$HOME/.claude.json" <<'EOF' 2>/dev/null; then ok "blender-lab MCP" "registered (user scope)"; else warn "blender-lab MCP" "not registered in ~/.claude.json" "claude mcp add --scope user blender-lab -e BLENDER_PATH=$BLENDER -- uv --directory ~/.ultra-3d/blender_mcp/mcp run blender-mcp"; fi
import json, sys
sys.exit(0 if "blender-lab" in json.load(open(sys.argv[1])).get("mcpServers", {}) else 1)
EOF

# --- Python CAD/mesh venv ------------------------------------------------------------------
if [[ -x "$PY" ]]; then
  if OUT="$("$PY" - <<'EOF' 2>&1
import importlib.metadata as md
mods = ["build123d", "trimesh", "manifold3d", "numpy", "rtree", "fast-simplification"]
print(" ".join(f"{m}={md.version(m)}" for m in mods))
import build123d, trimesh, manifold3d, rtree  # noqa
EOF
)"; then ok "venv" "$OUT"
  else bad "venv" "imports failed: $(echo "$OUT" | tail -1)" "VIRTUAL_ENV=~/.ultra-3d/venv uv pip install build123d trimesh manifold3d numpy scipy rtree fast-simplification pillow"; fi
else
  bad "venv" "missing $PY" "uv venv ~/.ultra-3d/venv --python 3.12 && VIRTUAL_ENV=~/.ultra-3d/venv uv pip install build123d trimesh manifold3d numpy scipy rtree fast-simplification pillow"
fi

# --- CLIs ------------------------------------------------------------------------------------
if command -v gltf-transform >/dev/null; then ok "gltf-transform" "$(gltf-transform --version 2>/dev/null | tail -1)"
else bad "gltf-transform" "missing" "npm i -g @gltf-transform/cli"; fi
if command -v ktx >/dev/null; then ok "ktx (KTX2)" "$(ktx --version 2>/dev/null | head -1)"
else warn "ktx (KTX2)" "missing — web textures fall back to WebP (fine)" "install KTX-Software ≥4.4 .pkg from github.com/KhronosGroup/KTX-Software/releases (needs admin)"; fi
if command -v ffmpeg >/dev/null; then ok "ffmpeg" "$(ffmpeg -version 2>/dev/null | awk 'NR==1{print $3}')"
else bad "ffmpeg" "missing (turntable MP4s)" "brew install ffmpeg"; fi
if command -v openscad >/dev/null; then ok "openscad" "$(openscad --version 2>&1 | tail -1)"
else warn "openscad" "missing (optional; build123d covers CAD)" "brew install --cask openscad@snapshot"; fi
if command -v node >/dev/null; then
  NV="$(node -v | tr -d v)"; if ver_ge "$NV" "20"; then ok "node" "$NV"; else warn "node" "$NV (<20)" "brew upgrade node"; fi
else bad "node" "missing (Meshy MCP via npx, gltf-transform)" "brew install node"; fi
command -v uv >/dev/null && ok "uv" "$(uv --version | awk '{print $2}')" || bad "uv" "missing (Blender Lab MCP server)" "brew install uv"

# --- Slicer --------------------------------------------------------------------------------
if [[ -x "$SLICER" ]]; then
  PROF="$(dirname "$(dirname "$SLICER")")/Resources/profiles/BBL/machine/Bambu Lab $PRINTER 0.4 nozzle.json"
  SV="$(defaults read "$(dirname "$(dirname "$SLICER")")/Info.plist" CFBundleShortVersionString 2>/dev/null)"
  if [[ -f "$PROF" ]]; then ok "bambu studio CLI" "$SV, $PRINTER 0.4 profile present"
  else warn "bambu studio CLI" "$SV but no '$PRINTER' profile" "update Bambu Studio, or set ULTRA3D_PRINTER in ~/.ultra-3d/config"; fi
else
  warn "bambu studio CLI" "not found (print track stops at STL/3MF)" "install Bambu Studio, or set ULTRA3D_SLICER"
fi

# --- Plugins / Meshy -------------------------------------------------------------------------
IP="$HOME/.claude/plugins/installed_plugins.json"
has_plugin() { [[ -f "$IP" ]] && grep -q "\"$1@" "$IP"; }
has_plugin ultra-3d && ok "ultra-3d plugin" "installed" || warn "ultra-3d plugin" "not installed" "claude plugin install ultra-3d@claude-ultra-motion"
if has_plugin meshy-3d-generation; then ok "meshy skills" "meshy-3d-generation installed"
else warn "meshy skills" "not installed (optional know-how)" "claude plugin marketplace add meshy-dev/meshy-3d-agent && claude plugin install meshy-3d-generation@meshy-3d-agent"; fi
if [[ $Q == 0 ]]; then
  echo "  · meshy MCP             bundled in the ultra-3d plugin; key in the Keychain via:"
  echo "                          claude plugin configure ultra-3d@claude-ultra-motion   (Meshy Pro plan+ API key)"
fi

# --- Disk ------------------------------------------------------------------------------------
FREE_GB=$(df -g "$HOME" | awk 'NR==2{print $4}')
if [[ "$FREE_GB" -lt 5 ]]; then bad "disk" "${FREE_GB} GB free" "free space before renders (turntables write PNG frames)"
elif [[ "$FREE_GB" -lt 15 ]]; then warn "disk" "${FREE_GB} GB free" "fine for single assets; clean renders/ between projects"
else ok "disk" "${FREE_GB} GB free"; fi

[[ $FAIL == 0 ]] && { [[ $Q == 1 ]] || echo "doctor: OK"; exit 0; } || { echo "doctor: missing required pieces (see fixes above)"; exit 1; }
