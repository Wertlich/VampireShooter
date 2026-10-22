"""Converts an FBX to GLB through Blender (Godot's FBX importer chokes on some
exports). Prints dimensions so the weapon can be scaled correctly.

Run:
  blender --background --factory-startup --python tools/convert_fbx.py -- <in.fbx> <out.glb>
"""

import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
src, out = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=src)

meshes = [o for o in bpy.data.objects if o.type == "MESH"]
print("meshes:", [(o.name, tuple(round(v, 3) for v in o.dimensions)) for o in meshes])
print("materials:", [m.name for m in bpy.data.materials])

mins = Vector((1e9, 1e9, 1e9))
maxs = Vector((-1e9, -1e9, -1e9))
for obj in meshes:
    for corner in obj.bound_box:
        world = obj.matrix_world @ Vector(corner)
        for i in range(3):
            mins[i] = min(mins[i], world[i])
            maxs[i] = max(maxs[i], world[i])
print("bounds min", tuple(round(v, 3) for v in mins), "max", tuple(round(v, 3) for v in maxs))

bpy.ops.object.select_all(action="DESELECT")
for obj in meshes:
    obj.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]

bpy.ops.export_scene.gltf(
    filepath=out,
    export_format="GLB",
    use_selection=True,
    export_apply=True,
    export_yup=True,
    export_animations=False,
)
print("exported", out)
