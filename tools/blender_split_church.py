"""Split the two church GLBs into loose mesh parts for hand editing.

Each connected component becomes its own Blender object (and therefore its own
MeshInstance3D after the Godot import). Run:

  blender --background --factory-startup --python tools/blender_split_church.py
"""

import bpy
import os

ROOT = r"D:\games godom\VampireShooter"
JOBS = [
    ("church_intact.glb", "church_intact_parts.glb"),
    ("church_ruined.glb", "church_ruined_parts.glb"),
]
FOLDER = os.path.join(ROOT, "models", "cemetery", "church")


def split_one(source: str, target: str) -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(FOLDER, source))
    meshes = [obj for obj in bpy.data.objects if obj.type == "MESH"]
    print("SOURCE", source, "mesh objects", len(meshes))
    for obj in meshes:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.separate(type="LOOSE")
        bpy.ops.object.mode_set(mode="OBJECT")
    parts = [obj for obj in bpy.data.objects if obj.type == "MESH"]
    parts.sort(key=lambda item: item.name)
    kept = 0
    for index, obj in enumerate(parts):
        if len(obj.data.polygons) == 0:
            bpy.data.objects.remove(obj, do_unlink=True)
            continue
        mat_name = "Part"
        if obj.data.materials:
            mat_name = obj.data.materials[0].name.split(".")[0]
        obj.name = "Part_%03d_%s" % (index, mat_name)
        kept += 1
    out = os.path.join(FOLDER, target)
    bpy.ops.export_scene.gltf(
        filepath=out,
        export_format="GLB",
        use_selection=False,
        export_apply=True,
        export_yup=True,
    )
    print("EXPORTED", out, "parts", kept, "bytes", os.path.getsize(out))


for source_name, target_name in JOBS:
    split_one(source_name, target_name)
