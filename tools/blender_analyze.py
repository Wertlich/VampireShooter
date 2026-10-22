"""Print skeleton mesh statistics so the armature bones can be placed by numbers.

Run: blender --background --factory-startup --python tools/blender_analyze.py -- <obj path>
"""

import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
obj_path = argv[0]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.obj_import(filepath=obj_path)
obj = bpy.context.selected_objects[0]
print("OBJECT", obj.name, "dims", tuple(round(v, 2) for v in obj.dimensions))

mw = obj.matrix_world
verts = [mw @ v.co for v in obj.data.vertices]
xs = [v.x for v in verts]
ys = [v.y for v in verts]
zs = [v.z for v in verts]
print("BOUNDS x %.2f..%.2f  y %.2f..%.2f  z %.2f..%.2f  verts %d" % (
    min(xs), max(xs), min(ys), max(ys), min(zs), max(zs), len(verts)))

zmin, zmax = min(zs), max(zs)
height = zmax - zmin
print("HEIGHT %.2f" % height)


def clusters(values, gap=6.0):
    values = sorted(values)
    out = []
    start = prev = values[0]
    for v in values[1:]:
        if v - prev > gap:
            out.append((start, prev))
            start = v
        prev = v
    out.append((start, prev))
    return out


for frac in [0.02, 0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4, 0.45, 0.5,
             0.55, 0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.9, 0.95, 0.99]:
    z = zmin + height * frac
    band = [v for v in verts if abs(v.z - z) < height * 0.012]
    if not band:
        continue
    bx = [v.x for v in band]
    by = [v.y for v in band]
    cl = clusters(bx, gap=8.0)
    print("z=%6.1f (%.2f h)  n=%3d  x[%.1f..%.1f] y[%.1f..%.1f]  clusters=%s" % (
        z, frac, len(band), min(bx), max(bx), min(by), max(by),
        [("%.0f..%.0f" % c) for c in cl]))
