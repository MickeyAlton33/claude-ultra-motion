"""blender_studio.py — headless studio renders for the ultra-3d pipeline (run by render.sh).

    Blender -b --factory-startup --python blender_studio.py -- \
        --input model.glb --out renders/ [--preset product|dark|white|clay] \
        [--material clay|pla|pla-black|resin|aluminium|steel|ceramic|gold|rubber] [--color "#d8d2c8"] \
        [--units auto|mm|m] [--res 1920x1080] [--final] [--samples 128] \
        [--engine cycles|eevee] [--turntable 120] [--tt-engine eevee] [--stills hero,front,side,top,detail] \
        [--hdri studio.hdr] [--transparent] [--save-blend scene.blend]

Camera stays on the front (-Y) side; the OBJECT turns for each still and for the turntable, so the
backdrop and light rig stay identical across every image (consistent, comparable review frames).
Everything is sized from the model's bounding box, in real-world meters.
"""
import argparse
import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ap = argparse.ArgumentParser()
ap.add_argument("--input", required=True, action="append")
ap.add_argument("--out", required=True)
ap.add_argument("--name")
ap.add_argument("--preset", default="product", choices=["product", "dark", "white", "clay"])
ap.add_argument("--material", default="auto")
ap.add_argument("--color")
ap.add_argument("--units", default="auto", choices=["auto", "mm", "cm", "m"])
ap.add_argument("--res", default="1920x1080")
ap.add_argument("--final", action="store_true", help="3840x2160, 256 samples")
ap.add_argument("--samples", type=int, default=128)
ap.add_argument("--engine", default="cycles", choices=["cycles", "eevee"])
ap.add_argument("--turntable", type=int, default=0, help="frames for a 360° turntable (0 = none)")
ap.add_argument("--tt-engine", default="eevee", choices=["cycles", "eevee"])
ap.add_argument("--tt-res", default="1280x720")
ap.add_argument("--stills", default="hero,front,side,top,detail")
ap.add_argument("--hdri")
ap.add_argument("--transparent", action="store_true")
ap.add_argument("--save-blend")
ap.add_argument("--focal", type=float, default=70.0)
ap.add_argument("--yaw", type=float, default=0.0,
                help="base yaw (deg) added to every still/turntable angle; use 90 for CAD modeled with its front at -X")
A = ap.parse_args(argv)
os.makedirs(A.out, exist_ok=True)
NAME = A.name or os.path.splitext(os.path.basename(A.input[0]))[0]

PRESETS = {
    #           backdrop RGB          backdrop rough  world   key  fill  rim   top   exposure
    "product": ((0.42, 0.42, 0.43), 0.55, 0.10, 1.0, 0.30, 1.4, 0.25, 0.0),
    "white":   ((0.92, 0.92, 0.92), 0.6, 0.35, 1.0, 0.45, 0.8, 0.35, 0.35),
    "dark":    ((0.035, 0.036, 0.04), 0.72, 0.02, 0.9, 0.12, 2.6, 0.10, 0.0),
    "clay":    ((0.55, 0.55, 0.56), 0.6, 0.12, 1.0, 0.30, 1.2, 0.25, 0.0),
}
MATS = {
    #            base color             metal rough  coat  sss    ior_lvl
    "clay":      ((0.80, 0.77, 0.72), 0.0, 0.62, 0.0, 0.0, 0.35),
    "pla":       ((0.85, 0.85, 0.83), 0.0, 0.42, 0.0, 0.0, 0.5),
    "pla-black": ((0.025, 0.025, 0.027), 0.0, 0.45, 0.0, 0.0, 0.5),
    "resin":     ((0.70, 0.72, 0.74), 0.0, 0.22, 0.2, 0.15, 0.5),
    "aluminium": ((0.91, 0.92, 0.92), 1.0, 0.28, 0.0, 0.0, 0.5),
    "steel":     ((0.56, 0.57, 0.58), 1.0, 0.22, 0.0, 0.0, 0.5),
    "ceramic":   ((0.93, 0.92, 0.90), 0.0, 0.18, 0.6, 0.05, 0.5),
    "gold":      ((1.00, 0.77, 0.34), 1.0, 0.18, 0.0, 0.0, 0.5),
    "rubber":    ((0.04, 0.04, 0.04), 0.0, 0.85, 0.0, 0.0, 0.3),
}
UNITS = {"mm": 0.001, "cm": 0.01, "m": 1.0}


def hex_rgb(h):
    h = h.lstrip("#")
    srgb = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb)


def nodes_of(idblock):
    # use_nodes is deprecated in 5.x (always on) and warns; only set it where it is still off
    if getattr(idblock, "node_tree", None) is None:
        idblock.use_nodes = True
    return idblock.node_tree


# ---------------------------------------------------------------- scene reset + import
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

before = set(bpy.data.objects)
for path in A.input:
    ext = os.path.splitext(path)[1].lower()
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path)
    elif ext == ".stl":
        bpy.ops.wm.stl_import(filepath=path)
    elif ext == ".ply":
        bpy.ops.wm.ply_import(filepath=path)
    elif ext in (".usd", ".usda", ".usdc", ".usdz"):
        bpy.ops.wm.usd_import(filepath=path)
    elif ext == ".blend":
        with bpy.data.libraries.load(path) as (src, dst):
            dst.objects = src.objects
        for o in dst.objects:
            if o is not None and o.type in {"MESH", "ARMATURE", "EMPTY", "CURVE"}:
                scene.collection.objects.link(o)
    else:
        raise SystemExit(f"unsupported input {path} (convert 3MF with render.sh)")
imported = [o for o in bpy.data.objects if o not in before]
# drop imported cameras/lights — the studio rig replaces them
for o in list(imported):
    if o.type in {"CAMERA", "LIGHT"}:
        bpy.data.objects.remove(o, do_unlink=True)
imported = [o for o in imported if o.name in bpy.data.objects]
meshes = [o for o in imported if o.type == "MESH"]
if not meshes:
    raise SystemExit("no mesh objects imported")

units = A.units
if units == "auto":
    units = "mm" if all(os.path.splitext(p)[1].lower() in (".stl", ".ply", ".obj") for p in A.input) else "m"
scale = UNITS[units]

root = bpy.data.objects.new("ULTRA_ROOT", None)
scene.collection.objects.link(root)
for o in imported:
    if o.parent is None:
        o.parent = root
root.scale = (scale, scale, scale)
bpy.context.view_layer.update()


def world_bbox(objs):
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


lo, hi = world_bbox(meshes)
center = (lo + hi) / 2
root.location -= Vector((center.x, center.y, lo.z))   # centered on XY, resting on the floor
bpy.context.view_layer.update()
lo, hi = world_bbox(meshes)
dims = hi - lo
S = max(dims)                     # characteristic size (m)
R = 0.5 * dims.length             # bounding-sphere radius
mid = Vector((0, 0, dims.z / 2))
print(f"STUDIO dims_m={tuple(round(d, 4) for d in dims)} units={units}")

# ---------------------------------------------------------------- materials
untextured = [o for o in meshes if not o.data.materials or all(m is None for m in o.data.materials)]
mat_name = A.material
if A.preset == "clay":
    mat_name = "clay"
if mat_name == "auto":
    mat_name = "pla" if units == "mm" else "clay"


def make_mat(key, color=None):
    base, metal, rough, coat, sss, ior_lvl = MATS[key]
    m = bpy.data.materials.new(f"ultra_{key}")
    nt = nodes_of(m)
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*(color or base), 1)
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = rough
    for k, v in (("Coat Weight", coat), ("Subsurface Weight", sss), ("Specular IOR Level", ior_lvl)):
        if k in bsdf.inputs:
            bsdf.inputs[k].default_value = v
    return m


override = A.preset == "clay" or A.material != "auto"
if untextured or override:
    mat = make_mat(mat_name if mat_name in MATS else "clay", hex_rgb(A.color) if A.color else None)
    for o in (meshes if override else untextured):
        o.data.materials.clear()
        o.data.materials.append(mat)
for o in meshes:  # smooth-by-angle shading so tessellated CAD/STL doesn't look faceted
    if o.type == "MESH" and not o.data.shape_keys:
        try:
            o.data.set_sharp_from_angle(angle=math.radians(35))
        except Exception:
            pass

# ---------------------------------------------------------------- cyclorama backdrop (sweep)
bd_col, bd_rough, world_str, k_key, k_fill, k_rim, k_top, exposure = PRESETS[A.preset]
W, D, H, r = 14 * S, 10 * S, 7 * S, 2.2 * S
bm = bmesh.new()
profile = [(-D, 0.0)]
for i in range(13):
    a = math.radians(90 * i / 12)
    profile.append((r * math.sin(a), r - r * math.cos(a)))
profile.append((r, H))
rows = []
for x in (-W / 2, W / 2):
    rows.append([bm.verts.new((x, y + 2.5 * S, z)) for y, z in profile])
for j in range(len(profile) - 1):
    bm.faces.new((rows[0][j], rows[1][j], rows[1][j + 1], rows[0][j + 1]))
me = bpy.data.meshes.new("cyc")
bm.to_mesh(me)
bm.free()
for p in me.polygons:
    p.use_smooth = True
cyc = bpy.data.objects.new("cyclorama", me)
scene.collection.objects.link(cyc)
bdm = bpy.data.materials.new("backdrop")
bsdf = next(n for n in nodes_of(bdm).nodes if n.type == "BSDF_PRINCIPLED")
bsdf.inputs["Base Color"].default_value = (*bd_col, 1)
bsdf.inputs["Roughness"].default_value = bd_rough
cyc.data.materials.append(bdm)
if A.transparent:
    cyc.is_shadow_catcher = True

# ---------------------------------------------------------------- lights (camera on -Y)
def area(name, loc, size, power, shape="RECTANGLE", size_y=None, spread=None):
    ld = bpy.data.lights.new(name, "AREA")
    ld.shape = shape
    ld.size = size
    if size_y:
        ld.size_y = size_y
    ld.energy = power
    if spread:
        ld.spread = math.radians(spread)
    ob = bpy.data.objects.new(name, ld)
    scene.collection.objects.link(ob)
    ob.location = loc
    tr = ob.constraints.new("TRACK_TO")
    tr.target = aim
    tr.track_axis = "TRACK_NEGATIVE_Z"
    tr.up_axis = "UP_Y"
    return ob


aim = bpy.data.objects.new("aim", None)
scene.collection.objects.link(aim)
aim.location = mid
d = 3.2 * R + 0.05
P = 13.0 * d * d                   # key watts, inverse-square scaled (≈130 W at 3.2 m; AgX, exposure 0)
                                   # calibrated so a 0.42 grey sweep reads mid-grey and #2f6f8f stays teal
area("key", (-0.75 * d, -0.75 * d, mid.z + 0.65 * d), 1.2 * R + 0.02, P * k_key, spread=70)
area("fill", (1.0 * d, -0.55 * d, mid.z + 0.2 * d), 2.4 * R + 0.04, P * k_fill)
area("rim", (0.35 * d, 0.95 * d, mid.z + 0.75 * d), 0.4 * R + 0.01, P * k_rim, size_y=2.2 * R + 0.03)
area("top", (0, 0, mid.z + 1.3 * d), 2.0 * R + 0.04, P * k_top, shape="DISK")

# ---------------------------------------------------------------- world
world = bpy.data.worlds.new("studio_world")
scene.world = world
wn = nodes_of(world)
bg = next(n for n in wn.nodes if n.type == "BACKGROUND")
if A.hdri and os.path.exists(A.hdri):
    env = wn.nodes.new("ShaderNodeTexEnvironment")
    env.image = bpy.data.images.load(A.hdri)
    wn.links.new(env.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = world_str * 3
else:
    bg.inputs["Color"].default_value = (0.8, 0.8, 0.82, 1)
    bg.inputs["Strength"].default_value = world_str

# ---------------------------------------------------------------- camera
cam_d = bpy.data.cameras.new("cam")
cam_d.lens = A.focal
cam_d.sensor_width = 36
cam = bpy.data.objects.new("cam", cam_d)
scene.collection.objects.link(cam)
scene.camera = cam
ct = cam.constraints.new("TRACK_TO")
ct.target = aim
ct.track_axis = "TRACK_NEGATIVE_Z"
ct.up_axis = "UP_Y"
cam_d.clip_start = max(0.001, S / 200)
cam_d.clip_end = 100 * S + 10


def set_res(res):
    w, h = (int(v) for v in res.lower().split("x"))
    scene.render.resolution_x, scene.render.resolution_y = w, h
    scene.render.resolution_percentage = 100


RXY = 0.5 * math.hypot(dims.x, dims.y)   # footprint radius: safe for any yaw (turntable)
HZ = dims.z / 2


def place_camera(elev_deg, lens, margin=1.08):
    """Fit the rotation-safe footprint horizontally and the projected height vertically."""
    cam_d.lens = lens
    w, h = scene.render.resolution_x, scene.render.resolution_y
    tan_w = 18.0 / lens                                   # sensor_fit AUTO: width is 36 mm
    tan_h = tan_w * h / w if w >= h else tan_w
    if h > w:
        tan_w = tan_w * w / h
    e = math.radians(elev_deg)
    vert = HZ * math.cos(e) + RXY * math.sin(e)           # projected half-height at this elevation
    dist = max(RXY / tan_w, vert / tan_h) * margin + RXY  # + RXY: nearest point is closer than centre
    cam.location = (0, -dist * math.cos(e), mid.z + dist * math.sin(e))


# ---------------------------------------------------------------- render settings
def set_engine(kind, samples):
    if kind == "eevee":
        for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
            try:
                scene.render.engine = eng
                break
            except TypeError:
                continue
        try:
            scene.eevee.taa_render_samples = max(32, samples // 2)
            scene.eevee.use_shadows = True
            scene.eevee.use_raytracing = True
        except Exception:
            pass
    else:
        scene.render.engine = "CYCLES"
        scene.cycles.samples = samples
        scene.cycles.use_denoising = True
        try:
            prefs = bpy.context.preferences.addons["cycles"].preferences
            prefs.compute_device_type = "METAL"
            prefs.get_devices()
            for dev in prefs.devices:
                dev.use = True
            scene.cycles.device = "GPU"
        except Exception as exc:
            print("STUDIO cycles GPU unavailable, using CPU:", exc)


scene.render.film_transparent = A.transparent
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA" if A.transparent else "RGB"
try:
    scene.view_settings.view_transform = "AgX"
    for look in ("AgX - Medium High Contrast", "Medium High Contrast", "None"):
        try:
            scene.view_settings.look = look
            break
        except TypeError:
            continue
except TypeError:
    pass
scene.view_settings.exposure = exposure

# ---------------------------------------------------------------- stills (object turns, camera fixed)
STILLS = {
    #          object yaw  cam elevation  lens
    "hero":   (-35, 18, A.focal),
    "front":  (0, 6, A.focal),
    "side":   (-90, 6, A.focal),
    "back":   (180, 12, A.focal),
    "top":    (-35, 58, A.focal),
    "detail": (-20, 22, A.focal * 1.9),
}
samples = 256 if A.final else A.samples
set_res("3840x2160" if A.final else A.res)
set_engine(A.engine, samples)
written = []
for key in [s.strip() for s in A.stills.split(",") if s.strip()]:
    yaw, elev, lens = STILLS[key]
    root.rotation_euler = (0, 0, math.radians(yaw + A.yaw))
    margin = 0.55 if key == "detail" else 1.08
    place_camera(elev, lens, margin)
    bpy.context.view_layer.update()
    scene.render.filepath = os.path.join(A.out, f"{NAME}_{key}.png")
    bpy.ops.render.render(write_still=True)
    written.append(scene.render.filepath)
    print("STUDIO wrote", scene.render.filepath)

# ---------------------------------------------------------------- turntable frames
if A.turntable > 0:
    tt_dir = os.path.join(A.out, f".{NAME}_turntable_frames")
    os.makedirs(tt_dir, exist_ok=True)
    set_res(A.tt_res)
    set_engine(A.tt_engine, 64 if A.tt_engine == "cycles" else 64)
    place_camera(15, A.focal, 1.08)
    for i in range(A.turntable):
        root.rotation_euler = (0, 0, math.radians(A.yaw) + 2 * math.pi * i / A.turntable)
        bpy.context.view_layer.update()
        scene.render.filepath = os.path.join(tt_dir, f"f_{i:04d}.png")
        bpy.ops.render.render(write_still=True)
    print("STUDIO turntable_frames", tt_dir)

if A.save_blend:
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(A.save_blend))
print("STUDIO_OK", len(written))
