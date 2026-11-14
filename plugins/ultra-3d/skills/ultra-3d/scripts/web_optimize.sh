#!/usr/bin/env bash
# web_optimize.sh — glTF-Transform pipeline → web GLB within budget + budget report + R3F component.
#
# Usage:
#   web_optimize.sh IN.glb [--budget hero|secondary|prop|ar] [--out OUT.glb]
#                   [--compress meshopt|draco] [--textures auto|webp|ktx2|avif]
#                   [--rigged] [--simplify RATIO] [--jsx] [--keep-structure]
#
#   --budget     triangle/texture/size budget from references/web-3d-rules.md (default hero)
#   --compress   meshopt (default: smallest, also compresses animation) | draco (widest legacy support)
#   --textures   auto = ktx2 if Khronos `ktx` (KTX-Software ≥ 4.4) is on PATH, else webp
#   --rigged     skinned/animated asset: no flatten/join/simplify (they break skins & clips)
#   --simplify   force a vertex keep-ratio (0–1); default = only when over the triangle budget
#   --jsx        also write a typed R3F component via pmndrs gltfjsx (Model.tsx next to the GLB)
#   --keep-structure  keep node hierarchy/names (no flatten/join) for code that targets nodes
#
# Steps: inspect → optimize (dedup, prune, weld, [simplify], resample, instance, palette,
#        texture resize + compress, meshopt/draco) → mesh_check --track web → report.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="${ULTRA3D_PY:-$HOME/.ultra-3d/venv/bin/python}"
command -v gltf-transform >/dev/null || { echo "gltf-transform missing: npm i -g @gltf-transform/cli" >&2; exit 1; }

IN=""; OUT=""; BUDGET="hero"; COMPRESS="meshopt"; TEX="auto"; RIGGED=0; SIMPLIFY=""; JSX=0; KEEP=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --budget) BUDGET="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --compress) COMPRESS="$2"; shift 2;;
    --textures) TEX="$2"; shift 2;;
    --rigged) RIGGED=1; shift;;
    --simplify) SIMPLIFY="$2"; shift 2;;
    --jsx) JSX=1; shift;;
    --keep-structure) KEEP=1; shift;;
    -h|--help) sed -n '2,20p' "$0"; exit 0;;
    -*) echo "unknown option $1" >&2; exit 1;;
    *) IN="$1"; shift;;
  esac
done
[[ -f "$IN" ]] || { sed -n '2,20p' "$0"; exit 1; }
case "$BUDGET" in
  hero) TRI=150000; TEXPX=2048;; secondary) TRI=50000; TEXPX=1024;;
  prop) TRI=15000; TEXPX=1024;;  ar) TRI=100000; TEXPX=2048;;
  *) echo "unknown budget $BUDGET" >&2; exit 1;;
esac
if [[ -z "$OUT" ]]; then
  stem="$(basename "${IN%.*}")"
  d="$(cd "$(dirname "$IN")" && pwd)"
  if [[ -d "$d/../exports" ]]; then OUT="$(cd "$d/../exports" && pwd)/${stem}.web.glb"; else OUT="$d/${stem}.web.glb"; fi
fi
if [[ "$TEX" == "auto" ]]; then
  if command -v ktx >/dev/null; then TEX="ktx2"; else TEX="webp"; fi
fi
if [[ "$TEX" == "ktx2" ]] && ! command -v ktx >/dev/null; then
  echo "ktx2 needs Khronos 'ktx' ≥ 4.4 (KTX-Software .pkg from github.com/KhronosGroup/KTX-Software/releases); falling back to webp" >&2
  TEX="webp"
fi

# Current triangle count (works on any glTF, compressed or not)
TRIS_IN=$("$PY" -c "import sys; sys.path.insert(0,'$HERE'); import mesh_check as m; print(m.gltf_stats(sys.argv[1])['triangles'])" "$IN")
RATIO="${SIMPLIFY:-}"
if [[ -z "$RATIO" && "$RIGGED" == 0 && "$TRIS_IN" -gt "$TRI" ]]; then
  RATIO=$("$PY" -c "print(round(min(1.0, $TRI / $TRIS_IN * 0.92), 4))")
fi

ARGS=(--compress "$COMPRESS" --texture-compress "$TEX" --texture-size "$TEXPX")
if [[ "$RIGGED" == 1 || "$KEEP" == 1 ]]; then
  ARGS+=(--flatten false --join false --simplify false)
elif [[ -n "$RATIO" ]]; then
  ARGS+=(--simplify true --simplify-ratio "$RATIO" --simplify-error 0.001)
else
  ARGS+=(--simplify false)
fi

echo "web_optimize: $IN ($TRIS_IN tris) → $OUT  [budget=$BUDGET tris≤$TRI tex≤${TEXPX}px compress=$COMPRESS textures=$TEX${RATIO:+ simplify=$RATIO}]"
mkdir -p "$(dirname "$OUT")"
gltf-transform optimize "$IN" "$OUT" "${ARGS[@]}" 2>&1 | grep -v -E "^\s*$" | tail -4

BYTES_IN=$(stat -f %z "$IN"); BYTES_OUT=$(stat -f %z "$OUT")
awk -v a="$BYTES_IN" -v b="$BYTES_OUT" 'BEGIN { printf "size: %.2f MB → %.2f MB (%.0f%% smaller)\n", a/1e6, b/1e6, (1-b/a)*100 }'

TRACK="web"; [[ "$RIGGED" == 1 ]] && TRACK="rigged"
set +e
"$PY" "$HERE/mesh_check.py" "$OUT" --track "$TRACK" --budget "$BUDGET" --json "${OUT%.glb}.check.json"
RC=$?
set -e
if [[ "$TRACK" == "rigged" ]]; then   # rigged assets must also meet the web budget
  "$PY" "$HERE/mesh_check.py" "$OUT" --track web --budget "$BUDGET" >/dev/null || RC=2
fi

if [[ "$JSX" == 1 ]]; then
  ( cd "$(dirname "$OUT")" && npx -y gltfjsx@6.5.3 "$(basename "$OUT")" --types --shadows \
      --output "$(basename "${OUT%.web.glb}" | sed 's/\.glb$//')Model.tsx" >/dev/null 2>&1 ) \
    && echo "R3F component: $(dirname "$OUT")/$(basename "${OUT%.web.glb}" | sed 's/\.glb$//')Model.tsx" \
    || echo "gltfjsx failed — use the useGLTF snippet below" >&2
fi

URL="/models/$(basename "$OUT")"
cat <<EOF

R3F usage (drei) — copy $(basename "$OUT") to public/models/:
  import { useGLTF } from '@react-three/drei'
  export function Model(props) {
    const { scene } = useGLTF('$URL')        // meshopt/draco decoders are wired by drei by default
    return <primitive object={scene} {...props} />
  }
  useGLTF.preload('$URL')
EOF
exit $RC
