"""Scales/rotates a gun GLB to a real-world length, points it along Godot -Z and
centres it on the origin, so Godot can use it without node scaling.

Run:
  blender --background --factory-startup --python tools/prepare_weapon.py -- \
      <in.glb> <out.glb> <target_length_m> <yaw_deg>
"""

import math
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
src, dst = argv[0], argv[1]
target_len = float(argv[2])
yaw_deg = float(argv[3]) if len(argv) > 3 else 0.0

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.import_scene.gltf(filepath=src) if False else bpy.ops.import_scene.gltf(filepath=src)

meshes = [o for o in bpy.data.objects if o.type == "MESH"]
bpy.ops.object.select_all(action="DESELECT")
for obj in meshes:
    obj.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
gun = bpy.context.view_layer.objects.active
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def bounds(obj):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for corner in obj.bound_box:
        world = obj.matrix_world @ Vector(corner)
        for i in range(3):
            lo[i] = min(lo[i], world[i])
            hi[i] = max(hi[i], world[i])
    return lo, hi


lo, hi = bounds(gun)
size = hi - lo
scale = target_len / max(size)
gun.scale = (scale, scale, scale)
# The glTF importer leaves objects in quaternion mode, where rotation_euler is
# ignored; switch first or the yaw silently does nothing.
gun.rotation_mode = "XYZ"
gun.rotation_euler = (0.0, 0.0, math.radians(yaw_deg))
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

lo, hi = bounds(gun)
center = (lo + hi) * 0.5
gun.location = gun.location - center
bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)

lo, hi = bounds(gun)
print("FIT bounds min", tuple(round(v, 3) for v in lo), "max", tuple(round(v, 3) for v in hi))
print("FIT size", tuple(round(v, 3) for v in (hi - lo)))

bpy.ops.export_scene.gltf(
    filepath=dst,
    export_format="GLB",
    use_selection=True,
    export_apply=True,
    export_yup=True,
    export_animations=False,
)
print("exported", dst)
