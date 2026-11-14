#!/usr/bin/env bash
# slice.sh — headless slicing with Bambu Studio's CLI → sliced 3MF + G-code + time/filament estimate.
#
# Usage:
#   slice.sh <model.stl|model.3mf> [--printer P2S] [--nozzle 0.4] [--process "0.20mm Standard"]
#            [--filament "Bambu PLA Basic"] [--plate textured|cool|engineering|smooth] [--out DIR]
#            [--orient] [--plate-png] [--set key=value ...]
#
#   --set     override any process key, repeatable: --set wall_loops=4 --set sparse_infill_density=30%
#             --set sparse_infill_pattern=gyroid --set enable_support=1 --set support_type=tree(auto)
#
# Defaults come from env or ~/.ultra-3d/config (KEY=VALUE lines):
#   ULTRA3D_PRINTER=P2S  ULTRA3D_NOZZLE=0.4  ULTRA3D_PROCESS="0.20mm Standard"  ULTRA3D_FILAMENT="Bambu PLA Basic"
#   ULTRA3D_PLATE=textured  ULTRA3D_SLICER=/Applications/BambuStudio.app/Contents/MacOS/BambuStudio
#
# Why the profile flattening: Bambu Studio's CLI does not resolve the `inherits` chain of the
# system presets you pass with --load-settings/--load-filaments, so e.g. filament_density is
# missing (weight reported as 0 g) and base values silently fall back to defaults. This script
# merges each preset with all its ancestors (base first) into a self-contained JSON before slicing.
set -euo pipefail

CONF="$HOME/.ultra-3d/config"
# shellcheck disable=SC1090
[[ -f "$CONF" ]] && set -a && source "$CONF" && set +a

PRINTER="${ULTRA3D_PRINTER:-P2S}"
NOZZLE="${ULTRA3D_NOZZLE:-0.4}"
PROCESS="${ULTRA3D_PROCESS:-0.20mm Standard}"
FILAMENT="${ULTRA3D_FILAMENT:-Bambu PLA Basic}"
SLICER="${ULTRA3D_SLICER:-/Applications/BambuStudio.app/Contents/MacOS/BambuStudio}"
PROFILES="${ULTRA3D_PROFILES:-/Applications/BambuStudio.app/Contents/Resources/profiles/BBL}"
PLATE="${ULTRA3D_PLATE:-textured}"
OUT=""
ORIENT=0
PLATE_PNG=0
OVERRIDES=()

usage() { sed -n '2,14p' "$0"; exit "${1:-0}"; }
[[ $# -lt 1 ]] && usage 1
MODEL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --printer) PRINTER="$2"; shift 2;;
    --nozzle) NOZZLE="$2"; shift 2;;
    --process) PROCESS="$2"; shift 2;;
    --filament) FILAMENT="$2"; shift 2;;
    --plate) PLATE="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --orient) ORIENT=1; shift;;
    --plate-png) PLATE_PNG=1; shift;;
    --set) OVERRIDES+=("$2"); shift 2;;
    -h|--help) usage 0;;
    -*) echo "unknown option: $1" >&2; usage 1;;
    *) MODEL="$1"; shift;;
  esac
done
[[ -z "$MODEL" ]] && { echo "no model given" >&2; exit 1; }
[[ -f "$MODEL" ]] || { echo "model not found: $MODEL" >&2; exit 1; }
[[ -x "$SLICER" ]] || { echo "Bambu Studio CLI not found at $SLICER (set ULTRA3D_SLICER)" >&2; exit 1; }

MODEL_ABS="$(cd "$(dirname "$MODEL")" && pwd)/$(basename "$MODEL")"
STEM="$(basename "${MODEL%.*}")"
# Bambu Studio resolves --export-3mf relative to --outputdir and mishandles relative outputdirs,
# so always pass an absolute outputdir and a bare file name.
if [[ -z "$OUT" ]]; then
  if [[ -d "$(dirname "$MODEL_ABS")/../exports" ]]; then OUT="$(cd "$(dirname "$MODEL_ABS")/../exports" && pwd)/slices"
  else OUT="$(dirname "$MODEL_ABS")/slices"; fi
fi
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ultra3d-slice.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PY="${ULTRA3D_PY:-$HOME/.ultra-3d/venv/bin/python}"
[[ -x "$PY" ]] || PY="$(command -v python3)"

case "$PLATE" in
  textured|pei|"Textured PEI Plate") PLATE_NAME="Textured PEI Plate";;
  cool|"Cool Plate") PLATE_NAME="Cool Plate";;
  engineering|eng|"Engineering Plate") PLATE_NAME="Engineering Plate";;
  smooth|hot|"High Temp Plate"|"Smooth PEI Plate") PLATE_NAME="High Temp Plate";;
  *) echo "unknown --plate '$PLATE' (textured|cool|engineering|smooth)" >&2; exit 1;;
esac
export ULTRA3D_PLATE_RESOLVED="$PLATE_NAME"
ULTRA3D_OVERRIDES="$(printf '%s\n' "${OVERRIDES[@]+"${OVERRIDES[@]}"}")"; export ULTRA3D_OVERRIDES

# --- resolve + flatten presets -------------------------------------------------------------
"$PY" - "$PROFILES" "$PRINTER" "$NOZZLE" "$PROCESS" "$FILAMENT" "$WORK" <<'PYEOF'
import json, os, sys
root, printer, nozzle, process, filament, work = sys.argv[1:7]

def index(kind):
    idx = {}
    d = os.path.join(root, kind)
    for f in os.listdir(d):
        if f.endswith(".json"):
            try:
                with open(os.path.join(d, f)) as fh:
                    j = json.load(fh)
                idx[j.get("name", f[:-5])] = os.path.join(d, f)
            except Exception:
                pass
    return idx

def load(kind, name, idx):
    path = idx.get(name)
    if not path: raise SystemExit(f"{kind} preset not found: {name!r}")
    with open(path) as fh: return json.load(fh)

def flatten(kind, name, idx):
    # Resolve `inherits` (base first) AND `include` (machine G-code templates such as
    # "Bambu Lab P2S 0.4 nozzle template machine_start_gcode"). Without the includes the
    # CLI falls back to a generic start G-code (wrong temps, no P2S calibration routine).
    chain, seen = [], set()
    cur = name
    while cur:
        if cur in seen: raise SystemExit(f"inheritance loop at {cur}")
        seen.add(cur)
        j = load(kind, cur, idx)
        chain.append(j); cur = j.get("inherits") or ""
    merged = {}
    for j in reversed(chain):
        for inc in j.get("include") or []:
            merged.update({k: v for k, v in load(kind, inc, idx).items()
                           if k not in ("name", "instantiation", "inherits", "from")})
        merged.update(j)
    for k in ("inherits", "include"):
        merged.pop(k, None)
    merged["name"] = name
    return merged

def pick(idx, candidates, kind):
    for c in candidates:
        if c in idx: return c
    raise SystemExit(f"no {kind} preset matched any of: {candidates}\n"
                     f"  hint: ls '{root}/{kind}' | grep '{printer}'")

suffix = "" if nozzle == "0.4" else f" {nozzle} nozzle"
m_idx, p_idx, f_idx = index("machine"), index("process"), index("filament")
m_name = pick(m_idx, [f"Bambu Lab {printer} {nozzle} nozzle"], "machine")
p_name = pick(p_idx, [f"{process} @BBL {printer}{suffix}", f"{process} @BBL {printer}"], "process")
f_name = pick(f_idx, [f"{filament} @BBL {printer}{suffix}", f"{filament} @BBL {printer}",
                      f"{filament} @BBL {printer} {nozzle} nozzle"], "filament")
plate = os.environ.get("ULTRA3D_PLATE_RESOLVED", "Textured PEI Plate")
for kind, name, idx in (("machine", m_name, m_idx), ("process", p_name, p_idx), ("filament", f_name, f_idx)):
    flat = flatten(kind, name, idx)
    if kind == "process":
        flat["curr_bed_type"] = plate   # CLI default is "Cool Plate" (35 °C bed for PLA)
        for kv in filter(None, os.environ.get("ULTRA3D_OVERRIDES", "").splitlines()):
            k, _, v = kv.partition("=")
            if k not in flat:
                print(f"  ! --set {k}: not a key of this process preset (typo?) — applied anyway")
            flat[k] = [v] if isinstance(flat.get(k), list) else v
            print(f"  override {k} = {v}")
    with open(os.path.join(work, f"{kind}.json"), "w") as fh:
        json.dump(flat, fh, indent=1)
print(f"presets: machine={m_name!r} process={p_name!r} filament={f_name!r} plate={plate!r}")
PYEOF

ARGS=(--orient "$ORIENT" --arrange 1 --slice 0
      --load-settings "$WORK/machine.json;$WORK/process.json"
      --load-filaments "$WORK/filament.json"
      --export-3mf "${STEM}_sliced.3mf"
      --outputdir "$OUT")
[[ "$PLATE_PNG" == 1 ]] && ARGS+=(--export-png 0)

echo "slicing $MODEL_ABS → $OUT"
LOG="$WORK/slicer.log"
set +e
"$SLICER" --debug 2 "${ARGS[@]}" "$MODEL_ABS" >"$LOG" 2>&1
RC=$?
set -e

# Keep result.json and a renamed G-code next to the sliced 3MF.
[[ -f "$OUT/result.json" ]] && mv -f "$OUT/result.json" "$OUT/${STEM}_result.json"
[[ -f "$OUT/plate_1.gcode" ]] && mv -f "$OUT/plate_1.gcode" "$OUT/${STEM}.gcode"

"$PY" - "$OUT" "$STEM" "$WORK/filament.json" "$RC" "$LOG" <<'PYEOF'
import json, math, os, re, sys
out, stem, fil_path, rc, log = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5]
res_p = os.path.join(out, f"{stem}_result.json")
gc_p = os.path.join(out, f"{stem}.gcode")
tmf_p = os.path.join(out, f"{stem}_sliced.3mf")
fil = json.load(open(fil_path))
def first(v, d=None):
    if isinstance(v, list): v = v[0] if v else d
    try: return float(v)
    except (TypeError, ValueError): return d
density = first(fil.get("filament_density"), 1.24)
diameter = first(fil.get("filament_diameter"), 1.75)
cost_kg = first(fil.get("filament_cost"), None)
summary = {"model": stem, "slicer_return_code": rc}
if os.path.exists(res_p):
    r = json.load(open(res_p))
    summary["slicer_return_code"] = r.get("return_code", rc)
    if r.get("error_string"): summary["slicer_error"] = r["error_string"]
    plates = r.get("sliced_plates") or []
    if plates:
        secs = plates[0].get("total_predication") or plates[0].get("main_predication") or 0
        summary["print_time"] = f"{int(secs // 3600)}h {int(secs % 3600 // 60)}m {int(secs % 60)}s"
        summary["print_time_s"] = round(secs)
    summary["layer_height_mm"] = round(r.get("layer_height", 0), 3)
if os.path.exists(gc_p):
    head = open(gc_p, errors="ignore").read(20000)
    m = re.search(r"total filament length \[mm\]\s*:\s*([\d.]+)", head)
    if m:
        length = float(m.group(1))
        vol_cm3 = math.pi * (diameter / 2) ** 2 * length / 1000.0
        summary["filament_length_m"] = round(length / 1000, 2)
        summary["filament_g"] = round(vol_cm3 * density, 1)
        if cost_kg: summary["filament_cost"] = round(summary["filament_g"] / 1000 * cost_kg, 2)
    m = re.search(r"total layer number:\s*(\d+)", head)
    if m: summary["layers"] = int(m.group(1))
    summary["gcode"] = gc_p
summary["sliced_3mf"] = tmf_p if os.path.exists(tmf_p) else None
json.dump(summary, open(os.path.join(out, f"{stem}_slice_summary.json"), "w"), indent=2)
print(json.dumps(summary, indent=2))
if not os.path.exists(gc_p):
    print("\nslicer log tail:\n" + "".join(open(log, errors="ignore").readlines()[-25:]), file=sys.stderr)
    sys.exit(1)
PYEOF
