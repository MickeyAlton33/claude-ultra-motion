# Print rules — Bambu Lab P2S (0.4 mm nozzle), FDM

Printer defaults live in `~/.ultra-3d/config` (`ULTRA3D_PRINTER=P2S`, nozzle 0.4, "0.20mm Standard", Bambu PLA Basic,
textured PEI plate). `slice.sh` flattens Bambu's system presets (inherits + G-code includes) so the CLI uses the real
P2S start G-code and filament data. Other printers: `--printer A1M|H2D|P1S`.

## Build volume & placement
- P2S: **256 × 256 × 256 mm**. Keep ≥ 5 mm from plate edges; > 230 mm in X/Y → split the part (dovetail / pin + hole).
- A1 mini 180³ · H2D 325 × 320 × 325 (single nozzle) · P1S 256³.
- Parts sit on Z = 0, centred (`mesh_fix.py --center`), largest flat face down.

## Walls, floors, features (0.4 mm nozzle, ~0.42 mm line width)
| Feature | Minimum | Preferred | Why |
|---|---|---|---|
| Vertical wall | **1.2 mm** (2 perimeters ≈ 0.84 + margin) | 1.6–2.4 mm (load-bearing ≥ 2.4) | thinner walls print as single gap-filled lines |
| Horizontal floor/roof | 0.8 mm (4 × 0.2 layers) | 1.2 mm | top surface quality needs ≥ 4–5 top layers |
| Pin / standalone post | Ø 3 mm | Ø 4 mm+ | thin posts wobble & snap |
| Embossed/engraved detail | 0.4 mm wide, 0.4 mm deep | 0.6 × 0.6 mm | below nozzle width disappears |
| Text (sans, bold) | 6 pt cap height ≈ 2 mm, emboss 0.6 mm | ≥ 3 mm caps, 0.8 mm deep | engraved text reads better on top faces |
| Hole (vertical, in XY plane) | Ø 1.5 mm | Ø 2 mm+ | |
| Gap between moving parts (print-in-place) | 0.3 mm | 0.4 mm | |

`mesh_check.py --track print --min-wall 1.2` ray-casts wall thickness and fails if > 1 % of samples are below it.

## Overhangs, bridges, supports
- Unsupported overhang ≤ **45°** from vertical (PLA can do 50–55° with cooling, but plan for 45°).
- Bridges ≤ 10 mm clean, ≤ 25 mm acceptable in PLA; longer → add a support rib or reorient.
- Horizontal holes: use a **teardrop** or diamond top (45° roof) for Ø > 6 mm; small holes self-bridge.
- Chamfer (45°) bottom edges instead of filleting them — fillets on the bed face become overhangs.
- **Elephant foot:** 0.4 × 45° chamfer on the bottom edge of anything that must mate.
- Supports: prefer *designing them out*. If needed: tree supports (auto) for organic parts, normal for flat ceilings;
  support interface top Z distance 0.2 mm. Never support threads or mating faces.
- `mesh_check` reports overhang area % (> 2 % → warning) and bed contact area (< 25 mm² → add a flat base or brim).

## Fit tolerances (PLA, 0.4 nozzle, 0.2 layers — calibrate once with a test coupon)
| Fit | Clearance per side | Use |
|---|---|---|
| Press / interference | 0.00–0.05 mm | pins that should not come out; expect to sand |
| Tight / friction | 0.10 mm | lids that stay on, snap-in inserts |
| Slide | **0.20 mm** | sliding lids, drawers, telescoping parts |
| Loose / rotating | 0.30–0.40 mm | hinges, print-in-place joints, axles |
| Holes for screws (clearance) | M3 → Ø 3.4, M4 → Ø 4.5, M5 → Ø 5.5 | |
| Self-tapping into plastic | M3 → Ø 2.5–2.7 | ≥ 3 perimeters around |
| Heat-set inserts (brass, CNC Kitchen style) | M3 → Ø 4.0–4.2 × 5.7 deep, M4 → Ø 5.6 × 8.1 | boss wall ≥ 1.5 mm around |
| Hex nut trap | M3 nut 5.5 AF → 5.8–5.9 AF pocket | |
| Magnets (6 × 3 mm disc) | Ø 6.2 × 3.2 pocket | glue or press |
Holes print ~0.1–0.2 mm undersized; outer dimensions ~0.05–0.1 mm oversized. Put named constants in the CAD source
(`CLEARANCE = 0.2`) and never hard-code fitted numbers twice.

## Orientation (decide before modeling details)
1. Strength: layers are the weak plane — load along layers, never peeling them apart (hooks, clips, brackets: print
   on their side so the bend is within layers).
2. Accuracy: dimensions that must fit → in XY (circles are rounder in XY, Z steps by layer height).
3. Surface: the face that's seen → up or vertical; bed face is flat but textured-plate-patterned.
4. Supports: minimise supported area; supports on hidden faces only.
5. Overhang budget: rotate until `mesh_check` overhang % is minimal (`slice.sh --orient` lets Bambu auto-orient).
6. **Design for the orientation:** if a part is printed on its side, make its side profile a *constant-section prism*
   (full-width ribs/struts instead of two thin side gussets). A gusset at one end of the extrusion becomes an
   unsupported ceiling when printed sideways — the E2E phone stand went from 4 % overhang to 0.09 % this way.
7. Export two files from CAD: `<part>_display.stl` (front faces −Y, for renders) and `<part>_print.stl/.3mf`
   (already in print orientation, on Z = 0) — never rotate CAD exports by hand in the slicer.

## Snap fits, hinges, threads
- Cantilever snap: length ≥ 5× thickness, deflection ≤ 1.5 % strain of length for PLA (PETG better: ~3 %).
  Hook depth 0.6–1.0 mm, 30° lead-in, 90° retaining face.
- Living hinges: **not in PLA** (cracks). PETG ok-ish (0.4–0.6 mm thick), PP/TPU best.
- Printed threads: ≥ M8, 1.5 mm pitch minimum; otherwise heat-set inserts or nut traps. Use build123d `Thread`/bd_warehouse.

## Materials on the P2S (Bambu system filaments)
| Filament | Nozzle °C | Bed °C (textured PEI) | Notes |
|---|---|---|---|
| Bambu PLA Basic | 220 | 55 | default; stiff, brittle; ≤ 55 °C service |
| PLA Matte | 220 | 55 | hides layer lines — great for decorative |
| PETG HF | 250–260 | 70 | tougher, slight flex, glossy; snap fits |
| ABS / ASA | 260–270 | 90–100 | heat resistant, needs enclosure (P2S is enclosed) — ASA for outdoor/UV |
| TPU 95A | 230 | 35 | flexible; slow; no AMS |
| PLA-CF / PETG-CF | 220 / 260 | 55 / 70 | needs hardened nozzle |
Plate: textured PEI (default in `slice.sh`; no glue). Smooth PEI (`--plate smooth`) for glossy bottoms. Cool plate needs glue.

## Slicer settings cheat-sheet (process presets)
| Goal | Process | Walls | Infill |
|---|---|---|---|
| Fast draft / test fit | 0.24mm Standard @BBL P2S | 2 | 15 % grid |
| Default | **0.20mm Standard @BBL P2S** | 2 | 20 % (sparse) |
| Strong functional | 0.20mm Standard + `--set wall_loops=4 --set sparse_infill_density=30% --set sparse_infill_pattern=gyroid` | 4 | 30 % gyroid |
| Decorative / figurine | 0.12mm or 0.16mm High Quality @BBL P2S | 2–3 | 10–15 % |
Strength comes from **walls** before infill: 4 walls at 15 % > 2 walls at 40 %.

## Checklist before slicing
- [ ] `mesh_check --track print --expect X,Y,Z` PASS (watertight, manifold, walls ≥ 1.2, dims within 0.5 mm)
- [ ] Oriented per above; largest flat face down; bed contact ≥ 25 mm²
- [ ] Mating features have named clearances; bottom edges chamfered 0.4 mm
- [ ] `slice.sh part.3mf` OK → time, grams, cost reported; note supports/brim in the delivery notes
- [ ] For multi-part assemblies: a test coupon of the critical fit first (≤ 10 min print)
