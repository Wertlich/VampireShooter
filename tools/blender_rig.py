"""Builds an armature for the skeleton mesh, skins it with rigid-ish weights and
renders a posed test frame so the rig can be checked without opening the UI.

Run:
  blender --background --factory-startup --python tools/blender_rig.py -- \
      <obj> <out.blend> <render dir>
"""

import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OBJ = argv[0]
OUT_BLEND = argv[1]
OUT_DIR = argv[2]
os.makedirs(OUT_DIR, exist_ok=True)

# Bone layout in metres, model is 1.83 m tall after scaling by 0.01.
# Blender is Z-up, the character faces -Y.
BONES = [
    # name,        head,                  tail,                  parent,       connect
    ("root",       (0.00, 0.00, 0.00),   (0.00, 0.00, 0.12),   None,         False),
    ("hips",       (0.00, 0.00, 0.93),   (0.00, 0.00, 1.05),   "root",       False),
    ("spine",      (0.00, 0.00, 1.05),   (0.00, 0.00, 1.26),   "hips",       True),
    ("chest",      (0.00, 0.00, 1.26),   (0.00, 0.00, 1.46),   "spine",      True),
    ("neck",       (0.00, 0.00, 1.46),   (0.00, 0.00, 1.56),   "chest",      True),
    ("head",       (0.00, 0.00, 1.56),   (0.00, 0.00, 1.80),   "neck",       True),

    ("shoulder.L", (0.03, 0.00, 1.45),   (0.16, 0.00, 1.465),  "chest",      False),
    ("upper_arm.L", (0.16, 0.00, 1.465), (0.40, 0.00, 1.31),   "shoulder.L", True),
    ("forearm.L",  (0.40, 0.00, 1.31),   (0.64, 0.00, 1.16),   "upper_arm.L", True),
    ("hand.L",     (0.64, 0.00, 1.16),   (0.72, 0.00, 1.08),   "forearm.L",  True),

    ("shoulder.R", (-0.03, 0.00, 1.45),  (-0.16, 0.00, 1.465), "chest",      False),
    ("upper_arm.R", (-0.16, 0.00, 1.465), (-0.40, 0.00, 1.31), "shoulder.R", True),
    ("forearm.R",  (-0.40, 0.00, 1.31),  (-0.64, 0.00, 1.16),  "upper_arm.R", True),
    ("hand.R",     (-0.64, 0.00, 1.16),  (-0.72, 0.00, 1.08),  "forearm.R",  True),

    ("thigh.L",    (0.09, 0.00, 0.93),   (0.085, 0.00, 0.53),  "hips",       False),
    ("shin.L",     (0.085, 0.00, 0.53),  (0.08, 0.00, 0.09),   "thigh.L",    True),
    ("foot.L",     (0.08, 0.00, 0.09),   (0.08, -0.14, 0.02),  "shin.L",     True),

    ("thigh.R",    (-0.09, 0.00, 0.93),  (-0.085, 0.00, 0.53), "hips",       False),
    ("shin.R",     (-0.085, 0.00, 0.53), (-0.08, 0.00, 0.09),  "thigh.R",    True),
    ("foot.R",     (-0.08, 0.00, 0.09),  (-0.08, -0.14, 0.02), "shin.R",     True),
]


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_mesh():
    bpy.ops.wm.obj_import(filepath=OBJ)
    obj = bpy.context.selected_objects[0]
    bpy.context.view_layer.objects.active = obj
    # Bake the importer's axis rotation, then scale to real-world metres.
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.scale = (0.01, 0.01, 0.01)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.name = "Skeleton"
    return obj


def build_armature():
    bpy.ops.object.armature_add(enter_editmode=True, location=(0.0, 0.0, 0.0))
    arm_obj = bpy.context.object
    arm_obj.name = "Rig"
    arm = arm_obj.data
    arm.name = "Rig"

    eb = arm.edit_bones
    for bone in list(eb):
        eb.remove(bone)

    for name, head, tail, parent, connect in BONES:
        b = eb.new(name)
        b.head = Vector(head)
        b.tail = Vector(tail)
        if parent:
            b.parent = eb[parent]
            b.use_connect = connect

    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj


def segment_distance(p, a, b):
    ab = b - a
    length_sq = ab.length_squared
    if length_sq < 1e-12:
        return (p - a).length
    t = max(0.0, min(1.0, (p - a).dot(ab) / length_sq))
    return (p - (a + ab * t)).length


def skin(mesh_obj, arm_obj):
    """Rigid skinning by nearest bone, softened near the joints."""
    deform = [b for b in arm_obj.data.bones if b.name != "root"]
    segments = [(b.name, b.head_local.copy(), b.tail_local.copy()) for b in deform]

    for name, _, _ in segments:
        mesh_obj.vertex_groups.new(name=name)

    for v in mesh_obj.data.vertices:
        p = v.co
        distances = []
        for name, a, b in segments:
            distances.append((segment_distance(p, a, b), name))
        distances.sort()
        best_d, best = distances[0]
        second_d, second = distances[1]

        if second_d < best_d * 1.25 and best_d < 0.05:
            mesh_obj.vertex_groups[best].add([v.index], 0.65, "REPLACE")
            mesh_obj.vertex_groups[second].add([v.index], 0.35, "REPLACE")
        else:
            mesh_obj.vertex_groups[best].add([v.index], 1.0, "REPLACE")

    mod = mesh_obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm_obj
    mesh_obj.parent = arm_obj


def setup_render():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 700
    scene.render.resolution_y = 700
    scene.render.film_transparent = False
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "SINGLE"
    shading.single_color = (0.82, 0.82, 0.84)
    shading.show_shadows = True


def render(name, cam_loc, look_at=(0.0, 0.0, 0.95)):
    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = Vector(cam_loc)
    cam.rotation_euler = (Vector(look_at) - Vector(cam_loc)).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.filepath = os.path.join(OUT_DIR, name)
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)
    print("rendered", name)


def pose_test(arm_obj):
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    pb = arm_obj.pose.bones
    for name in ["thigh.L", "thigh.R", "upper_arm.L", "upper_arm.R", "forearm.L", "spine"]:
        pb[name].rotation_mode = "XYZ"
    pb["thigh.L"].rotation_euler = (math.radians(35.0), 0.0, 0.0)
    pb["thigh.R"].rotation_euler = (math.radians(-35.0), 0.0, 0.0)
    pb["upper_arm.L"].rotation_euler = (math.radians(30.0), 0.0, 0.0)
    pb["upper_arm.R"].rotation_euler = (math.radians(-30.0), 0.0, 0.0)
    pb["forearm.L"].rotation_euler = (math.radians(40.0), 0.0, 0.0)
    pb["spine"].rotation_euler = (math.radians(12.0), 0.0, 0.0)
    bpy.ops.object.mode_set(mode="OBJECT")


def main():
    reset_scene()
    mesh = import_mesh()
    arm = build_armature()
    skin(mesh, arm)
    setup_render()

    render("rig_rest_front.png", (0.0, -3.2, 1.1))
    render("rig_rest_side.png", (3.2, 0.0, 1.1))

    pose_test(arm)
    render("rig_pose_front.png", (0.0, -3.2, 1.1))
    render("rig_pose_side.png", (3.2, 0.0, 1.1))

    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
    print("saved", OUT_BLEND)


main()
