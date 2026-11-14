#!/usr/bin/env python3
"""mesh_fix.py — repair + rescale a mesh, then re-run mesh_check on the result.

Stages (in order, each optional except the basic cleanup):
  1. cleanup      merge verts, drop degenerate/duplicate faces, unreferenced verts, fix winding
                  and normals, fill small holes (trimesh)
  2. --union      boolean-union all shells into one solid (manifold3d) — for AI meshes made of
                  overlapping pieces
  0. scaling      --scale F | --units-from m|cm|in (→ mm) | --fit-max MM | --fit AXIS=MM
                  (applied FIRST, so every mm value below is real millimetres)
  3. --remesh MM  voxel remesh in headless Blender (voxel size in mm) — the robust fix for
                  self-intersecting / non-manifold AI meshes; destroys UVs, so print-only.
                  Rule of thumb: voxel = 0.3–0.5 mm for 50–150 mm prints.
     --thicken MM Solidify open shells (helmets, leaves, cloth, "paper" surfaces) to MM wall
                  thickness before the remesh; without it an open shell remeshes into a
                  paper-thin double wall.
  4. --decimate R keep ratio R of faces (0–1), Blender collapse decimation (keeps closed meshes
                  closed; same Blender pass as --remesh)
  5. --drop-small PCT  delete floating bodies smaller than PCT % of the largest (AI debris)
  6. placement    --center (XY centered, sitting on Z=0) and --z-up (Y-up → Z-up for GLB/OBJ sources)

Usage:
  mesh_fix.py IN [-o OUT] [--union] [--remesh 0.4 [--thicken 1.6]] [--decimate 0.5] [--drop-small 1]
              [--scale 1000 | --units-from m | --fit-max 120 | --fit z=80]
              [--center] [--z-up] [--track print] [--expect "X,Y,Z"]

Default OUT = <stem>_fixed.<ext> (STL/3MF/OBJ/PLY/GLB supported by trimesh).
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile

import numpy as np
import trimesh

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mesh_check  # noqa: E402

BLENDER = os.environ.get("ULTRA3D_BLENDER", "/Applications/Blender.app/Contents/MacOS/Blender")
UNIT_TO_MM = mesh_check.UNIT_TO_MM

BLENDER_PY = r"""
import bpy, sys
argv = sys.argv[sys.argv.index("--") + 1:]
src, dst = argv[0], argv[1]
voxel, thick, ratio = float(argv[2]), float(argv[3]), float(argv[4])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.stl_import(filepath=src)
obj = bpy.context.selected_objects[0]
bpy.context.view_layer.objects.active = obj
if thick > 0:
    mod = obj.modifiers.new("thicken", "SOLIDIFY")
    mod.thickness = thick
    mod.offset = 0.0                 # grow both sides of the surface
    mod.use_even_offset = False      # even offset throws long spikes at sharp verts (80 mm → 248 mm)
    mod.use_quality_normals = True
    mod.nonmanifold_thickness_mode = "CONSTRAINTS"
    bpy.ops.object.modifier_apply(modifier=mod.name)
if voxel > 0:
    obj.data.remesh_voxel_size = voxel
    obj.data.remesh_voxel_adaptivity = 0.0
    bpy.ops.object.voxel_remesh()
if 0 < ratio < 1:
    # Collapse decimation keeps a closed voxel mesh closed (fast-simplification did not:
    # it produced stray vertices and holes on remeshed AI meshes).
    mod = obj.modifiers.new("decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = ratio
    mod.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=mod.name)
bpy.ops.wm.stl_export(filepath=dst, export_selected_objects=True, ascii_format=False)
print("BLENDER_OK", len(obj.data.polygons))
"""


def cleanup(mesh: trimesh.Trimesh) -> trimesh.Trimesh:
    mesh = mesh.copy()
    mesh.merge_vertices()
    mesh.update_faces(mesh.nondegenerate_faces())
    mesh.update_faces(mesh.unique_faces())
    mesh.remove_unreferenced_vertices()
    trimesh.repair.fix_winding(mesh)
    trimesh.repair.fix_inversion(mesh, multibody=True)
    trimesh.repair.fix_normals(mesh, multibody=True)
    if not mesh.is_watertight:
        trimesh.repair.fill_holes(mesh)
    return mesh


def union_shells(mesh: trimesh.Trimesh) -> trimesh.Trimesh:
    import manifold3d as m3
    parts = []
    for body in mesh.split(only_watertight=False):
        mm = m3.Manifold(m3.Mesh(vert_properties=np.asarray(body.vertices, dtype=np.float32),
                                 tri_verts=np.asarray(body.faces, dtype=np.uint32)))
        if mm.status() == m3.Error.NoError and not mm.is_empty():
            parts.append(mm)
        else:
            print(f"  ! skipped a non-manifold shell ({len(body.faces)} tris) in union — "
                  "use --remesh instead", file=sys.stderr)
    if not parts:
        raise SystemExit("no manifold shells to union — use --remesh")
    out = m3.Manifold.batch_boolean(parts, m3.OpType.Add) if len(parts) > 1 else parts[0]
    res = out.to_mesh()
    return trimesh.Trimesh(vertices=np.asarray(res.vert_properties)[:, :3],
                           faces=np.asarray(res.tri_verts), process=True)


def blender_pass(mesh: trimesh.Trimesh, voxel: float = 0.0, thicken: float = 0.0,
                 ratio: float = 1.0) -> trimesh.Trimesh:
    if not os.path.exists(BLENDER):
        raise SystemExit(f"Blender not found at {BLENDER} (set ULTRA3D_BLENDER)")
    with tempfile.TemporaryDirectory() as td:
        src, dst, script = (os.path.join(td, n) for n in ("in.stl", "out.stl", "pass.py"))
        mesh.export(src)
        with open(script, "w") as fh:
            fh.write(BLENDER_PY)
        r = subprocess.run([BLENDER, "-b", "--factory-startup", "--python", script, "--",
                            src, dst, str(voxel), str(thicken), str(ratio)],
                           capture_output=True, text=True, timeout=1800)
        if "BLENDER_OK" not in r.stdout or not os.path.exists(dst):
            raise SystemExit("Blender pass failed:\n" + r.stdout[-2000:] + r.stderr[-2000:])
        return trimesh.load(dst, force="mesh")


def drop_small(mesh: trimesh.Trimesh, pct: float) -> trimesh.Trimesh:
    """Remove bodies whose size is < pct % of the largest body's (volume when closed, else area)."""
    bodies = mesh.split(only_watertight=False)
    if len(bodies) < 2:
        return mesh
    size = [abs(b.volume) if b.is_watertight else b.area for b in bodies]
    keep = [b for b, s in zip(bodies, size) if s >= max(size) * pct / 100.0]
    return trimesh.util.concatenate(keep)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("model")
    ap.add_argument("-o", "--out")
    ap.add_argument("--union", action="store_true")
    ap.add_argument("--remesh", type=float, metavar="VOXEL_MM")
    ap.add_argument("--thicken", type=float, metavar="MM",
                    help="with --remesh: Solidify open shells to this wall thickness first")
    ap.add_argument("--decimate", type=float, metavar="RATIO")
    ap.add_argument("--drop-small", type=float, metavar="PCT",
                    help="remove floating bodies smaller than PCT %% of the largest (AI debris)")
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--scale", type=float)
    g.add_argument("--units-from", choices=list(UNIT_TO_MM))
    g.add_argument("--fit-max", type=float, metavar="MM")
    g.add_argument("--fit", metavar="AXIS=MM", help="e.g. z=80 → scale uniformly so Z is 80 mm")
    ap.add_argument("--center", action="store_true", help="center XY, rest on Z=0")
    ap.add_argument("--z-up", action="store_true", help="rotate Y-up source (GLB/OBJ) to Z-up")
    ap.add_argument("--track", default="print", choices=["print", "web", "visual", "rigged"])
    ap.add_argument("--expect")
    a = ap.parse_args(argv)

    stem, ext = os.path.splitext(a.model)
    out = a.out or f"{stem}_fixed{ext if ext.lower() not in ('.gltf',) else '.glb'}"

    mesh = mesh_check.load_mesh(a.model)
    print(f"loaded {a.model}: {len(mesh.faces):,} tris, watertight={mesh.is_watertight}, "
          f"extents={mesh.extents.round(4).tolist()}")
    if ext.lower() in (".glb", ".gltf") and not a.track == "print":
        print("  note: GLB in → geometry-only out (materials/UVs/rig are not preserved by this tool;"
              " do visual/web cleanup in Blender instead)")

    if a.z_up:
        mesh.apply_transform(trimesh.transformations.rotation_matrix(np.pi / 2, [1, 0, 0]))

    # Scale FIRST so --remesh/--thicken values are real millimetres.
    factor = 1.0
    if a.scale:
        factor = a.scale
    elif a.units_from:
        factor = UNIT_TO_MM[a.units_from]
    elif a.fit_max:
        factor = a.fit_max / float(mesh.extents.max())
    elif a.fit:
        axis, mm = a.fit.lower().split("=")
        factor = float(mm) / float(mesh.extents["xyz".index(axis)])
    if factor != 1.0:
        mesh.apply_scale(factor)
        print(f"scaled ×{factor:.6g} → extents {mesh.extents.round(3).tolist()}")

    mesh = cleanup(mesh)
    print(f"cleanup: {len(mesh.faces):,} tris, watertight={mesh.is_watertight}")
    if a.union:
        mesh = union_shells(mesh)
        print(f"union: {len(mesh.faces):,} tris, bodies={len(mesh.split(only_watertight=False))}")
    if a.remesh or a.decimate:
        mesh = blender_pass(mesh, a.remesh or 0.0, (a.thicken or 0.0) if a.remesh else 0.0,
                            a.decimate or 1.0)
        mesh = cleanup(mesh)
        print(f"blender pass (remesh {a.remesh or '-'} mm, thicken {a.thicken or '-'} mm, "
              f"decimate {a.decimate or '-'}): {len(mesh.faces):,} tris, "
              f"watertight={mesh.is_watertight}, bodies={len(mesh.split(only_watertight=False))}")
    if a.drop_small:
        before = len(mesh.split(only_watertight=False))
        mesh = drop_small(mesh, a.drop_small)
        print(f"drop-small <{a.drop_small}%: bodies {before} → {len(mesh.split(only_watertight=False))}")
    if a.center:
        b = mesh.bounds
        mesh.apply_translation([-(b[0][0] + b[1][0]) / 2, -(b[0][1] + b[1][1]) / 2, -b[0][2]])

    mesh.export(out)
    print(f"wrote {out}\n")
    expect = [float(x) for x in a.expect.split(",")] if a.expect else None
    units = "mm" if a.track == "print" else "auto"
    rep = mesh_check.check(out, a.track, units, expect, 0.5, 1.2, 45.0, "hero",
                           mesh_check.BEDS.get(os.environ.get("ULTRA3D_PRINTER", "P2S").upper()))
    print(mesh_check.human(rep))
    return 2 if rep["verdict"] == "FAIL" else 0


if __name__ == "__main__":
    sys.exit(main())
