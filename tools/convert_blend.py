"""Exports the mesh objects of a .blend to GLB for Godot.

Godot cannot import .blend without a configured Blender path, so weapons that
arrive as .blend are converted here once.

Run:
  blender --background <file.blend> --python tools/convert_blend.py -- <out.glb>
"""

import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
out_path = argv[0]

meshes = [o for o in bpy.data.objects if o.type == "MESH"]
print("mesh objects:", [(o.name, tuple(round(v, 3) for v in o.dimensions)) for o in meshes])
print("materials:", [m.name for m in bpy.data.materials])

bpy.ops.object.select_all(action="DESELECT")
for obj in meshes:
    obj.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]

bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format="GLB",
    use_selection=True,
    export_apply=True,
    export_yup=True,
    export_animations=False,
)
print("exported", out_path)
