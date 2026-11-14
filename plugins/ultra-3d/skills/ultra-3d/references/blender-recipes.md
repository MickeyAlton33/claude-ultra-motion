# Blender recipes (Blender 5.3, Apple Silicon)

Two ways to drive Blender:
- **Headless scripts (default for output):** `render.sh` → `blender_studio.py`. Deterministic, no GUI, used for every review
  render and every final. Mesh repair passes run through `mesh_fix.py` (voxel remesh / solidify / decimate).
- **Blender Lab MCP (`blender-lab`, interactive):** for layout, scene dressing, materials by eye. The user opens Blender →
  Preferences › Add-ons › MCP › **Start** (bridge on **localhost:9877**; autostart is off on purpose). It has **no
  sandbox** — generated code runs with the user's privileges: only read/write inside the current project folder, never
  touch prefs/add-ons/other folders, never `os.system`/`subprocess`/network calls.
  The `blender` MCP (mcp-for-blender, safe mode, port 9876) belongs to the ultra-motion pipeline; keep its generators
  (Hyper3D, Hunyuan3D, Tripo, Meshy, Sketchfab) off.
  Headless bridge for automation: `Blender -b --online-mode --addons bl_ext.user_default.mcp --command blender_mcp --port 9877`.
  Gotcha: `render_viewport_to_path` ignores the path and writes into a temp folder — render with
  `bpy.ops.render.render(write_still=True)` after setting `scene.render.filepath`, via `execute_blender_code`.

## Units & scale
- Scene units: Metric, unit scale 1.0 → **1 BU = 1 m**. A 120 mm vase is 0.12 BU tall. glTF is meters, STL is "mm by convention".
- `render.sh`/`blender_studio.py` auto-scale: STL/PLY/OBJ ×0.001 (mm→m), GLB/FBX/USD as-is. Override with `--units`.
- After any import: Object › Apply › All Transforms (Ctrl-A) before modifiers, exports, or rigging.
- Origin at **bottom centre** for props and prints (`Object › Set Origin › Origin to 3D Cursor` with the cursor at the base).
- **Front faces −Y** (Blender's front view). `render.sh` assumes it; for CAD modeled with its front at −X pass `--yaw 90`
  (or export a rotated `_display.stl`).

## Studio lighting rigs (what `blender_studio.py` builds — reuse the numbers by hand)
Distances scale with the model: `R` = half its bounding diagonal, `d = 3.2·R`; key power `P = 13·d²` W
(inverse-square: a 1 m object → d ≈ 2.8 m → key ≈ 100 W; a 100 mm print → d ≈ 0.28 m → key ≈ 1 W).
Camera on −Y looking +Y; lights relative to it:

| Light | Type | Position (x, y, z) | Size | Power | Role |
|---|---|---|---|---|---|
| Key | Area rect, spread 70° | (−0.75d, −0.75d, +0.65d) | 1.2R | 1.0P | shape, main shadow (camera-left, high) |
| Fill | Area rect | (+1.0d, −0.55d, +0.2d) | 2.4R | 0.30P (white 0.45, dark 0.12) | lift shadows, keep ratio ~3:1 |
| Rim | Area strip | (+0.35d, +0.95d, +0.75d) | 0.4R × 2.2R | 1.4P (dark 2.6P) | edge separation from backdrop |
| Top | Area disk | (0, 0, +1.3d) | 2.0R | 0.25P | soft top sheen, kills black tops |
| World | colour / HDRI | — | — | 0.10 (white 0.35, dark 0.02) | reflections only |

Presets: **product** (mid-grey 0.42 sweep, roughness 0.55) · **white** (0.92 sweep, +0.35 EV, e-commerce) ·
**dark** (0.035 sweep, roughness 0.72, strong rim — premium/tech) · **clay** (all materials → clay; form review).
Colour: **AgX**, look "Medium High Contrast", exposure 0. Never Standard/Filmic for new work.
Backdrop: a cyclorama sweep (floor → 2.2R-radius cove → wall at +Y), 14S wide, so no horizon line is ever visible.
For transparent web/hero PNGs: `--transparent` (film transparent + shadow catcher sweep).

## Camera presets
| Shot | Object yaw | Camera elevation | Lens | Notes |
|---|---|---|---|---|
| hero | −35° | 18° | 70 mm | the "money shot"; slightly above, 3/4 |
| front | 0° | 6° | 70 mm | orthographic feel without ortho |
| side | −90° | 6° | 70 mm | silhouette check |
| back | 180° | 12° | 70 mm | |
| top | −35° | 58° | 70 mm | shows top surfaces / prints' top skin |
| detail | −20° | 22° | 133 mm, 0.55 framing | texture & edge quality |
The object turns, the camera stays: lights and backdrop are identical across stills → comparable frames.
Product macro: 85–135 mm, f/5.6–f/11 (DOF only on finals: `cam.data.dof.use_dof = True; aperture_fstop = 8`).
Hero characters: 50 mm at eye level (elev 0–5°) reads as human scale; 24–35 mm for heroic/low angles.

## Turntable
`render.sh model.glb --quick` → 72 frames EEVEE 1280×720 (≈0.75 s/frame) → `<name>_turntable.mp4` (H.264, CRF 18,
yuv420p, 30 fps) + `<name>_contact.png` (8 frames, 4×2) for the reviewer.
`--final` → 180 frames Cycles 1920×1080 (6 s at 30 fps). Camera at 15° elevation, framing fits the rotation-safe footprint.

## Render settings
- Cycles on **Metal GPU** (set automatically), OIDN denoise. Review: 48 samples 1280×720. Final: 256 samples 3840×2160.
- **First Cycles render after installing/updating Blender compiles Metal kernels: ~3–4 min once**, cached afterwards
  (later stills ≈ 8 s at 720p). Don't kill it, don't assume a hang.
- EEVEE (`BLENDER_EEVEE`) for turntables/blockouts; Cycles for anything with glass, metal reflections or caustics.

## Material presets (Principled BSDF — `--material`)
| Key | Base colour (linear) | Metallic | Roughness | Extra |
|---|---|---|---|---|
| clay | 0.80 0.77 0.72 | 0 | 0.62 | form review |
| pla | 0.85 0.85 0.83 (or `--color`) | 0 | 0.42 | IOR level 0.5 — FDM plastic |
| pla-black | 0.025 | 0 | 0.45 | |
| resin | 0.70 0.72 0.74 | 0 | 0.22 | coat 0.2, subsurface 0.15 |
| aluminium | 0.91 0.92 0.92 | 1 | 0.28 | add anisotropic 0.3 for brushed |
| steel | 0.56 0.57 0.58 | 1 | 0.22 | |
| ceramic | 0.93 0.92 0.90 | 0 | 0.18 | coat 0.6 |
| gold | 1.00 0.77 0.34 | 1 | 0.18 | |
| rubber | 0.04 | 0 | 0.85 | IOR level 0.3 |
Imported GLB/FBX materials are kept unless `--material`/`--preset clay` overrides. `--color "#e2572b"` takes sRGB hex.
FDM realism (finals only): add a Wave texture (bands, scale = 1/layer height in BU, ~0.2 mm) into Bump at strength 0.05.

## Cleanup recipe for AI / imported meshes (before any export)
1. Apply transforms; set origin bottom-centre; scale to brief size (N-panel dimensions).
2. `Mesh › Clean Up`: Merge by Distance (0.0001 m), Delete Loose, Degenerate Dissolve, Fill Holes (sides 8).
3. Recalculate normals outside (Shift-N); check Face Orientation overlay (all blue).
4. Remove internal/floating shells (Select Linked → delete small islands) or `mesh_fix.py --drop-small 1`.
5. Poly budget: Decimate (Collapse, triangulate) to the track budget; or Remesh (voxel) for prints.
6. UVs: keep Meshy's UVs; if broken → Smart UV Project (angle 66°, margin 0.003) or `meshy_uv_unwrap`.
7. Shade Auto Smooth 30–35°; weighted normals for hard-surface.
8. Materials: one Principled per material; textures 2048 (web hero) or 4096 (renders).

## Export settings
- **GLB (web/AR):** `bpy.ops.export_scene.gltf(filepath=..., export_format='GLB', export_apply=True,
  export_yup=True, export_texcoords=True, export_normals=True, export_tangents=False, export_materials='EXPORT',
  export_animations=True, export_skins=True, export_draco_mesh_compression_enable=False)` — compress later with
  `web_optimize.sh` (meshopt), not in Blender.
- **FBX (game engines):** `apply_unit_scale=True, apply_scale_options='FBX_SCALE_ALL', bake_anim=True,
  add_leaf_bones=False, primary_bone_axis='Y', secondary_bone_axis='X'`.
- **STL (print):** `bpy.ops.wm.stl_export(filepath=..., export_selected_objects=True, global_scale=1000.0)` — note the
  ×1000 (m→mm) when the scene is in meters. Prefer build123d/trimesh for CAD exports.
- **USDZ (iOS AR Quick Look):** `bpy.ops.wm.usd_export(filepath='x.usdz', export_materials=True,
  export_textures_mode='NEW')` (Blender 5.3 name; textures are packed into the .usdz).

## Poly Haven (CC0) via API
Base `https://api.polyhaven.com`, no key. **Send a User-Agent naming the tool** (their ToS): `-A "ultra-3d/1.0"`.
- List: `/assets?type=hdris&categories=studio` · Files: `/files/<id>` → URLs on `dl.polyhaven.org` by resolution.
- Good studio HDRIs: `studio_small_08`, `studio_small_09`, `photo_studio_loft_hall`, `brown_photostudio_02`.
- Download to `assets/polyhaven/`, pass with `render.sh --hdri assets/polyhaven/x_2k.hdr`, log in credits.md (CC0).
