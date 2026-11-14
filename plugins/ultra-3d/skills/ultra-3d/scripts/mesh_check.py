#!/usr/bin/env python3
"""mesh_check.py — one report for every export in the ultra-3d pipeline.

Checks (all tracks): load, bodies, watertight, winding/normals, non-manifold edges,
degenerate faces, manifold3d validity, real-world dimensions, volume, triangle count.
Print track adds: thin walls (ray-cast), unsupported overhangs, bed contact, build-volume fit.
Web/rigged tracks add (GLB/glTF, read from the JSON chunk so Draco/Meshopt files still work):
triangle + texture budget, file size, compression extensions, skins/joints/animations.

Usage:
  mesh_check.py MODEL [--track print|web|visual|rigged] [--units mm|m|cm|in|auto]
                [--expect "X,Y,Z"] [--tol 0.5] [--min-wall 1.2] [--overhang 45]
                [--budget hero|secondary|prop|ar] [--bed "256,256,256"] [--json out.json]

Exit code: 0 = PASS, 2 = FAIL (any blocking issue), 1 = could not run.
Run with ~/.ultra-3d/venv/bin/python (trimesh, manifold3d, numpy, rtree).
"""
from __future__ import annotations

import argparse
import json
import math
import os
import struct
import sys

import numpy as np

try:
    import trimesh
except ImportError:  # pragma: no cover
    sys.exit("trimesh missing — run with ~/.ultra-3d/venv/bin/python (see doctor.sh)")

UNIT_TO_MM = {"mm": 1.0, "cm": 10.0, "m": 1000.0, "in": 25.4}

# Web budgets — keep in sync with references/web-3d-rules.md
BUDGETS = {
    #            triangles, max texture px, max GLB bytes (after web_optimize), max draw calls
    "hero":      (150_000, 2048, 4_000_000, 30),
    "secondary": (50_000, 1024, 1_500_000, 15),
    "prop":      (15_000, 1024, 500_000, 5),
    "ar":        (100_000, 2048, 4_000_000, 20),
}

# Build volumes (mm) — keep in sync with references/print-rules.md
BEDS = {
    "P2S": (256, 256, 256), "P1S": (256, 256, 256), "X1C": (256, 256, 256),
    "A1": (256, 256, 256), "A1M": (180, 180, 180), "H2D": (325, 320, 325),
}


# ---------------------------------------------------------------------------------------------
# glTF JSON-level inspection (works on Draco/Meshopt/KTX2 files, no decoding needed)
# ---------------------------------------------------------------------------------------------
def read_gltf_json(path: str):
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:4] == b"glTF":
        _, _, _ = struct.unpack_from("<4sII", data, 0)
        clen, ctype = struct.unpack_from("<II", data, 12)
        if ctype != 0x4E4F534A:
            raise ValueError("first GLB chunk is not JSON")
        doc = json.loads(data[20:20 + clen])
        bin_off = 20 + clen
        binchunk = b""
        if bin_off + 8 <= len(data):
            blen, _btype = struct.unpack_from("<II", data, bin_off)
            binchunk = data[bin_off + 8: bin_off + 8 + blen]
        return doc, binchunk, os.path.dirname(path)
    return json.loads(data.decode("utf-8")), b"", os.path.dirname(path)


def image_dims(blob: bytes):
    if blob[:8] == b"\x89PNG\r\n\x1a\n":
        w, h = struct.unpack(">II", blob[16:24]); return w, h, "png"
    if blob[:2] == b"\xff\xd8":
        i = 2
        while i < len(blob) - 9:
            if blob[i] != 0xFF: i += 1; continue
            marker = blob[i + 1]
            if marker in (0xC0, 0xC1, 0xC2):
                h, w = struct.unpack(">HH", blob[i + 5:i + 9]); return w, h, "jpeg"
            seg = struct.unpack(">H", blob[i + 2:i + 4])[0]; i += 2 + seg
        return None, None, "jpeg"
    if blob[:4] == b"RIFF" and blob[8:12] == b"WEBP":
        try:
            from PIL import Image
            import io
            im = Image.open(io.BytesIO(blob)); return im.width, im.height, "webp"
        except Exception:
            return None, None, "webp"
    if blob[:12] == b"\xabKTX 20\xbb\r\n\x1a\n":
        w, h = struct.unpack_from("<II", blob, 20); return w, h, "ktx2"
    if blob[4:12] in (b"ftypavif", b"ftypavis"):
        return None, None, "avif"
    return None, None, "unknown"


def gltf_stats(path: str) -> dict:
    doc, binchunk, base = read_gltf_json(path)
    acc = doc.get("accessors", [])
    views = doc.get("bufferViews", [])
    tris = 0
    prims = 0
    morph_targets = 0
    for mesh in doc.get("meshes", []):
        for p in mesh.get("primitives", []):
            prims += 1
            mode = p.get("mode", 4)
            if "indices" in p:
                n = acc[p["indices"]]["count"]
            else:
                n = acc[p["attributes"]["POSITION"]]["count"]
            if mode == 4: tris += n // 3
            elif mode in (5, 6): tris += max(0, n - 2)
            morph_targets = max(morph_targets, len(p.get("targets", [])))
    # instancing multiplies drawn triangles; count mesh references per node
    textures = []
    for img in doc.get("images", []):
        blob = b""
        if "bufferView" in img and binchunk:
            bv = views[img["bufferView"]]
            off = bv.get("byteOffset", 0); blob = binchunk[off: off + bv["byteLength"]]
        elif "uri" in img and not img["uri"].startswith("data:"):
            p = os.path.join(base, img["uri"])
            if os.path.exists(p):
                with open(p, "rb") as fh: blob = fh.read()
        w, h, fmt = image_dims(blob) if blob else (None, None, img.get("mimeType", "?"))
        textures.append({"name": img.get("name", ""), "w": w, "h": h, "format": fmt,
                         "bytes": len(blob)})
    skins = [{"name": s.get("name", ""), "joints": len(s.get("joints", []))} for s in doc.get("skins", [])]
    anims = []
    for a in doc.get("animations", []):
        dur = 0.0
        for s in a.get("samplers", []):
            mx = acc[s["input"]].get("max")
            if mx: dur = max(dur, float(mx[0]))
        anims.append({"name": a.get("name", ""), "channels": len(a.get("channels", [])),
                      "duration_s": round(dur, 3)})
    weighted = any("JOINTS_0" in p.get("attributes", {}) and "WEIGHTS_0" in p.get("attributes", {})
                   for m in doc.get("meshes", []) for p in m.get("primitives", []))
    return {
        "triangles": tris, "primitives_draw_calls": prims, "materials": len(doc.get("materials", [])),
        "textures": textures, "skins": skins, "skin_weights_present": weighted,
        "animations": anims, "morph_targets_max": morph_targets,
        "extensions_used": doc.get("extensionsUsed", []),
        "generator": doc.get("asset", {}).get("generator", ""),
        "file_bytes": os.path.getsize(path),
    }


# ---------------------------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------------------------
def load_mesh(path: str):
    loaded = trimesh.load(path, force="scene", process=False)
    if isinstance(loaded, trimesh.Scene):
        if not loaded.geometry:
            raise ValueError("no geometry in file")
        mesh = loaded.to_geometry() if hasattr(loaded, "to_geometry") else loaded.dump(concatenate=True)
    else:
        mesh = loaded
    # merge coincident verts (STL is a triangle soup) without destroying the original data
    mesh = mesh.copy()
    mesh.merge_vertices(merge_tex=True, merge_norm=True)
    return mesh


def nonmanifold_edges(mesh) -> int:
    e = np.sort(mesh.edges, axis=1)
    _, counts = np.unique(e, axis=0, return_counts=True)
    return int((counts > 2).sum())


def manifold3d_status(mesh):
    try:
        import manifold3d as m3
        mm = m3.Manifold(m3.Mesh(vert_properties=np.asarray(mesh.vertices, dtype=np.float32),
                                 tri_verts=np.asarray(mesh.faces, dtype=np.uint32)))
        st = mm.status()
        return str(st).split(".")[-1], (None if mm.is_empty() else int(mm.genus()))
    except Exception as exc:  # noqa: BLE001
        return f"unavailable ({exc.__class__.__name__})", None


def thin_walls(mesh, scale_mm: float, min_wall_mm: float, samples: int = 4000):
    """Ray-cast inward from surface samples; return thickness stats in mm.
    Rays whose hit face is not roughly opposite (dot > -0.5) are discarded: those are corner
    artifacts, not walls."""
    if len(mesh.faces) == 0:
        return None
    n = int(min(samples, max(500, len(mesh.faces) * 2)))
    pts, fidx = trimesh.sample.sample_surface(mesh, n, seed=7)
    normals = mesh.face_normals[fidx]
    eps = 1e-4 * float(mesh.scale or 1.0)
    origins = pts - normals * eps
    dirs = -normals
    try:
        locs, ray_idx, tri_idx = mesh.ray.intersects_location(origins, dirs, multiple_hits=False)
    except Exception:
        return None
    if len(ray_idx) == 0:
        return None
    opposite = (mesh.face_normals[tri_idx] * normals[ray_idx]).sum(axis=1) < -0.5
    d = np.linalg.norm(locs - origins[ray_idx], axis=1)[opposite] * scale_mm + eps * scale_mm
    if d.size == 0:
        return None
    below = float((d < min_wall_mm).mean() * 100.0)
    return {"samples": int(d.size), "min_mm": round(float(d.min()), 3),
            "p1_mm": round(float(np.percentile(d, 1)), 3),
            "p5_mm": round(float(np.percentile(d, 5)), 3),
            "median_mm": round(float(np.median(d)), 3),
            "pct_below_min_wall": round(below, 2)}


def overhangs(mesh, scale_mm: float, max_angle_deg: float):
    """Downward-facing area steeper than max_angle from vertical (0° = wall, 90° = ceiling),
    ignoring faces touching the bed."""
    n = mesh.face_normals
    a = mesh.area_faces * scale_mm ** 2
    zmin = mesh.bounds[0][2]
    tri_z = mesh.triangles[:, :, 2].max(axis=1)
    on_bed = (tri_z - zmin) * scale_mm < 0.2
    limit = math.sin(math.radians(max_angle_deg))
    mask = (n[:, 2] < -limit) & ~on_bed
    total = float(a.sum())
    over = float(a[mask].sum())
    bed_area = float(a[on_bed & (n[:, 2] < -0.99)].sum())
    return {"overhang_area_mm2": round(over, 1),
            "overhang_pct_of_surface": round(over / total * 100, 2) if total else 0.0,
            "bed_contact_area_mm2": round(bed_area, 1)}


def check(path: str, track: str, units: str, expect, tol, min_wall, overhang_deg, budget, bed):
    rep: dict = {"file": os.path.abspath(path), "track": track, "issues": [], "warnings": []}
    ext = os.path.splitext(path)[1].lower()
    if units == "auto":
        units = "m" if ext in (".glb", ".gltf", ".fbx", ".usdz", ".usd") else "mm"
    rep["units_assumed"] = units
    s = UNIT_TO_MM[units]

    if ext in (".glb", ".gltf"):
        try:
            rep["gltf"] = gltf_stats(path)
        except Exception as exc:  # noqa: BLE001
            rep["warnings"].append(f"glTF JSON parse failed: {exc}")

    mesh = None
    try:
        mesh = load_mesh(path)
    except Exception as exc:  # noqa: BLE001
        msg = str(exc)
        if "draco" in msg.lower() or "meshopt" in msg.lower() or (
                rep.get("gltf") and any(e in rep["gltf"]["extensions_used"] for e in
                                        ("KHR_draco_mesh_compression", "EXT_meshopt_compression"))):
            rep["warnings"].append("geometry is Draco/Meshopt-compressed: geometry checks skipped "
                                   "(run mesh_check on the uncompressed source before web_optimize)")
        else:
            rep["issues"].append(f"could not load geometry: {msg}")

    if mesh is not None and len(mesh.faces):
        ext_mm = (mesh.extents * s).round(3).tolist()
        bodies = mesh.split(only_watertight=False)
        status, genus = manifold3d_status(mesh)
        degenerate = int((mesh.area_faces < 1e-12).sum())
        nm = nonmanifold_edges(mesh)
        geo = {
            "triangles": int(len(mesh.faces)), "vertices": int(len(mesh.vertices)),
            "bodies": len(bodies),
            "dims_mm": ext_mm, "dims_native": mesh.extents.round(6).tolist(),
            "watertight": bool(mesh.is_watertight),
            "winding_consistent": bool(mesh.is_winding_consistent),
            "nonmanifold_edges": nm, "degenerate_faces": degenerate,
            "manifold3d": status, "genus": genus,
            "volume_cm3": round(abs(float(mesh.volume)) * s ** 3 / 1000.0, 3) if mesh.is_watertight else None,
            "surface_cm2": round(float(mesh.area) * s ** 2 / 100.0, 2),
            "normals_inverted": bool(mesh.is_watertight and mesh.volume < 0),
            "origin_offset_native": mesh.bounds[0].round(6).tolist(),
        }
        rep["geometry"] = geo

        if expect:
            got = sorted(ext_mm); want = sorted(expect)
            off = [abs(g - w) for g, w in zip(got, want)]
            geo["dims_expected_mm"] = expect
            if max(off) > tol:
                rep["issues"].append(f"dimensions {ext_mm} mm differ from expected {expect} mm "
                                     f"by up to {max(off):.2f} mm (tol {tol})")
        if geo["normals_inverted"]:
            rep["issues"].append("normals inverted (negative volume) — mesh_fix.py fixes this")
        if degenerate:
            rep["warnings"].append(f"{degenerate} degenerate (zero-area) faces")

        if track == "print":
            if not geo["watertight"]:
                rep["issues"].append("not watertight — slicers will guess; run mesh_fix.py")
            if nm:
                rep["issues"].append(f"{nm} non-manifold edges")
            if status not in ("NoError",) and not status.startswith("unavailable"):
                rep["issues"].append(f"manifold3d rejects mesh: {status}")
            if len(bodies) > 1:
                rep["warnings"].append(f"{len(bodies)} separate bodies — fine for multi-part plates, "
                                       "bad if they should be one part (union them)")
            tw = thin_walls(mesh, s, min_wall)
            rep["thin_walls"] = tw
            if tw and tw["p1_mm"] < min_wall:
                lvl = "issues" if tw["pct_below_min_wall"] > 1.0 else "warnings"
                rep[lvl].append(f"thin walls: {tw['pct_below_min_wall']}% of samples < {min_wall} mm "
                                f"(min {tw['min_mm']} mm)")
            oh = overhangs(mesh, s, overhang_deg)
            rep["overhangs"] = oh
            if oh["overhang_pct_of_surface"] > 2.0:
                rep["warnings"].append(f"{oh['overhang_pct_of_surface']}% of surface overhangs > "
                                       f"{overhang_deg}° — needs supports or reorientation")
            if oh["bed_contact_area_mm2"] < 25:
                rep["warnings"].append(f"small bed contact ({oh['bed_contact_area_mm2']} mm²) — "
                                       "add a flat base, brim, or reorient")
            if bed:
                fits = all(d <= b for d, b in zip(sorted(ext_mm), sorted(bed)))
                geo["fits_bed"] = fits
                if not fits:
                    rep["issues"].append(f"{ext_mm} mm does not fit build volume {bed} mm — split it")
            if max(ext_mm) < 1.0:
                rep["issues"].append("largest dimension < 1 mm — almost certainly a unit error "
                                     "(model in meters? use mesh_fix.py --scale 1000)")
        else:
            if max(geo["dims_native"]) > 50 and units == "m":
                rep["warnings"].append(f"model is {max(geo['dims_native']):.1f} m across — "
                                       "probably exported in mm; Blender/web expect meters")

    if track in ("web", "rigged", "visual") and rep.get("gltf"):
        g = rep["gltf"]
        tri_max, tex_max, bytes_max, dc_max = BUDGETS[budget]
        g["budget"] = {"name": budget, "triangles": tri_max, "texture_px": tex_max,
                       "file_bytes": bytes_max, "draw_calls": dc_max}
        if track == "web":
            if g["triangles"] > tri_max:
                rep["issues"].append(f"{g['triangles']:,} triangles > {budget} budget {tri_max:,}")
            big = [t for t in g["textures"] if t["w"] and max(t["w"], t["h"]) > tex_max]
            if big:
                rep["issues"].append(f"{len(big)} textures larger than {tex_max}px "
                                     f"(largest {max(max(t['w'], t['h']) for t in big)}px)")
            npot = [t for t in g["textures"] if t["w"] and (t["w"] & (t["w"] - 1) or t["h"] & (t["h"] - 1))]
            if npot:
                rep["warnings"].append(f"{len(npot)} non-power-of-two textures (KTX2/mips prefer POT)")
            if g["file_bytes"] > bytes_max:
                rep["issues"].append(f"GLB is {g['file_bytes']/1e6:.2f} MB > {bytes_max/1e6:.1f} MB budget")
            if g["primitives_draw_calls"] > dc_max:
                rep["warnings"].append(f"{g['primitives_draw_calls']} primitives (draw calls) > {dc_max}")
            if not any(e in g["extensions_used"] for e in
                       ("KHR_draco_mesh_compression", "EXT_meshopt_compression")):
                rep["warnings"].append("geometry not compressed — run web_optimize.sh")
        if track == "rigged":
            if not g["skins"]:
                rep["issues"].append("no skin found — model is not rigged")
            elif not g["skin_weights_present"]:
                rep["issues"].append("skin present but no JOINTS_0/WEIGHTS_0 on any primitive")
            jmax = max((sk["joints"] for sk in g["skins"]), default=0)
            if jmax > 150:
                rep["warnings"].append(f"{jmax} joints — heavy for web/mobile (aim ≤ 100)")
            if not g["animations"]:
                rep["warnings"].append("rigged but no animations embedded")

    rep["verdict"] = "FAIL" if rep["issues"] else "PASS"
    return rep


def human(rep: dict) -> str:
    out = [f"== mesh_check: {os.path.basename(rep['file'])}  [{rep['track']}]  → {rep['verdict']}"]
    g = rep.get("geometry")
    if g:
        out.append(f"   dims {g['dims_mm']} mm  | tris {g['triangles']:,}  verts {g['vertices']:,}  "
                   f"bodies {g['bodies']}")
        out.append(f"   watertight {g['watertight']}  winding_ok {g['winding_consistent']}  "
                   f"nonmanifold_edges {g['nonmanifold_edges']}  manifold3d {g['manifold3d']}  "
                   f"genus {g['genus']}")
        if g.get("volume_cm3") is not None:
            out.append(f"   volume {g['volume_cm3']} cm³  surface {g['surface_cm2']} cm²")
    if rep.get("thin_walls"):
        t = rep["thin_walls"]
        out.append(f"   walls: min {t['min_mm']} mm  p1 {t['p1_mm']}  p5 {t['p5_mm']}  "
                   f"median {t['median_mm']}  below-min {t['pct_below_min_wall']}%")
    if rep.get("overhangs"):
        o = rep["overhangs"]
        out.append(f"   overhangs {o['overhang_pct_of_surface']}% of surface  "
                   f"bed contact {o['bed_contact_area_mm2']} mm²")
    gl = rep.get("gltf")
    if gl:
        tex = ", ".join(f"{t['w']}x{t['h']} {t['format']}" for t in gl["textures"][:8]) or "none"
        out.append(f"   glTF: {gl['triangles']:,} tris  {gl['primitives_draw_calls']} prims  "
                   f"{gl['materials']} mats  {gl['file_bytes']/1e6:.2f} MB  ext {gl['extensions_used']}")
        out.append(f"   textures: {tex}")
        if gl["skins"] or gl["animations"]:
            out.append(f"   skins {gl['skins']}  anims {[a['name'] for a in gl['animations']]}")
    for i in rep["issues"]:
        out.append(f"   ✗ {i}")
    for w in rep["warnings"]:
        out.append(f"   ! {w}")
    return "\n".join(out)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("model")
    ap.add_argument("--track", choices=["print", "web", "visual", "rigged"], default="print")
    ap.add_argument("--units", choices=["mm", "cm", "m", "in", "auto"], default="auto")
    ap.add_argument("--expect", help="expected dims in mm, e.g. '80,60,40' (order-independent)")
    ap.add_argument("--tol", type=float, default=0.5, help="dimension tolerance in mm")
    ap.add_argument("--min-wall", type=float, default=1.2)
    ap.add_argument("--overhang", type=float, default=45.0)
    ap.add_argument("--budget", choices=list(BUDGETS), default="hero")
    ap.add_argument("--bed", help="build volume mm 'X,Y,Z' or printer name (P2S, A1M, H2D…)",
                    default=os.environ.get("ULTRA3D_PRINTER", "P2S"))
    ap.add_argument("--json", help="also write the report to this path")
    a = ap.parse_args(argv)
    if not os.path.exists(a.model):
        print(f"not found: {a.model}", file=sys.stderr); return 1
    expect = [float(x) for x in a.expect.split(",")] if a.expect else None
    bed = None
    if a.bed:
        bed = BEDS.get(a.bed.upper()) or ([float(x) for x in a.bed.split(",")] if "," in a.bed else None)
    rep = check(a.model, a.track, a.units, expect, a.tol, a.min_wall, a.overhang, a.budget, bed)
    print(human(rep))
    if a.json:
        with open(a.json, "w") as fh:
            json.dump(rep, fh, indent=2)
    return 2 if rep["verdict"] == "FAIL" else 0


if __name__ == "__main__":
    sys.exit(main())
