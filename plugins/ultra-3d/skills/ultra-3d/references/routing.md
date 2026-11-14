# Routing — which track, which modeling method

Pick the **track** from what the user will *do* with the result, then the **method** from what the
object *is*. Write both into `brief.md` before modeling anything.

## 1. Track (deliverable)

| Track | The user wants… | Units | Final deliverables | Gate |
|---|---|---|---|---|
| **visual** | stills, product shots, turntables, frames for a film | m | 4K PNG stills (hero, front, side, top, detail) + turntable MP4 (+ .blend) | reviewer APPROVED on renders |
| **web** | a model on a website / R3F / three.js / AR | m | `*.web.glb` within budget + R3F snippet / gltfjsx component (+ USDZ for iOS AR) | `mesh_check --track web` PASS |
| **print** | a physical object off the P2S | mm | STL + 3MF in print orientation, sliced 3MF + G-code, time/filament estimate, notes | `mesh_check --track print` PASS + slice OK |
| **rigged** | a character/creature that moves (game, web, film) | m | GLB (+ FBX) with skin + listed animation clips | `mesh_check --track rigged` PASS + deformation review |

A request can have two tracks (e.g. "a figurine I can print and also show on my site"): build
once at real scale, export per track, and run the gate for each.

## 2. Method (how the geometry is made)

| The object… | Method | Why |
|---|---|---|
| must **fit, mate, mount, clip, hold, enclose**, has stated dimensions or tolerances (brackets, enclosures, stands, adapters, jigs, knobs, replacement parts) | **Parametric CAD — build123d** (OpenSCAD for simple CSG one-offs) | exact dimensions, editable named parameters, clean manifold solids. **Never AI mesh for parts that must fit.** |
| is organic / sculptural / decorative: characters, creatures, figurines, food, plants, stylised props, "a statue of…" | **Meshy** (text-to-3D or image-to-3D) → Blender cleanup | sculpting by hand is slow; AI is good at organic surface detail |
| is a **real object you have photos of** | **Meshy multi-image-to-3D** (2–4 photos, meshy-7.1 + meshy-7) | photogrammetry-lite |
| is a **scene / environment / product shot** | **Blender** (MCP for layout, `render.sh` for output) + Poly Haven HDRIs/textures/models + CAD or Meshy hero objects | lighting/composition is the work, not the mesh |
| is a **hard-surface prop for visuals only** (sci-fi crate, gadget, furniture) | CAD if it has clean primitives and dimensions; Meshy (meshy-7.1) if it's ornate | CAD stays crisp under studio light; AI bevels go soft |
| is **text, logo, sign, emblem, relief** | CAD (build123d `Text`, SVG import) — extrude/emboss | exact glyphs; AI garbles letters |
| is a **character that must animate** | Meshy **meshy-t2.5** (smart topology, `target_polycount`) + meshy-n1 texture → `meshy_rig` → `meshy_animate` | quad-ish topology deforms; rigging is 5 credits |
| is **mechanical + decorative** (ornate lamp with an E27 socket, figurine on a dovetail base) | **Hybrid**: CAD for every interface (socket, base, joints) + Meshy for the decorative shell, boolean-joined in build123d/manifold3d | keep the fit-critical geometry parametric |

### Red flags → re-route
- User gave a dimension with a tolerance, a screw size, a device to fit → CAD, even if it "looks organic".
- Meshy output will be printed and has features < 1.2 mm, floating bits, or thin fins → plan `mesh_fix.py --remesh 0.4 --thicken 1.6 --drop-small 1` *before* promising a print.
- Web track and Meshy output > budget → retopo via `meshy_remesh` (5 credits, set `target_polycount`) or Blender decimate before `web_optimize.sh`; never ship a 500k-tri AI mesh to a browser.
- Rigged track and a non-humanoid → Meshy auto-rig is humanoid-oriented; check the rig in Blender before animating.

## 3. Track → pipeline specifics

| Step | visual | web | print | rigged |
|---|---|---|---|---|
| Brief must capture | mood refs, backdrop/preset, aspect ratios | target page, budget tier, AR? | printer, material, fit partners, max size, orientation constraints | style, height, rig type, animation list |
| Concept checkpoint | blockout render (`render.sh --quick --stills hero`) | same + triangle estimate | CAD preview render + dims print-out | Meshy previews (or concept image) |
| Check | `mesh_check --track visual` (normals, scale, floating parts) | `mesh_check --track web --budget …` | `mesh_check --track print --expect X,Y,Z` | `mesh_check --track rigged` |
| Review renders | `--preset product` or `dark` | `--preset white --transparent` | `--material pla --color "#…" --preset product` | turntable of the rest pose + a frame per clip |
| Export | `render.sh --final` | `web_optimize.sh --budget … --jsx` | STL+3MF+STEP → `slice.sh` | GLB (+FBX) via Blender/Meshy, `web_optimize.sh --rigged` for web |

## 4. Default-mode boundary
If the user picked **default mode**, skip all of this — but still never spend Meshy credits without stating the cost, and still
use real-world units.
