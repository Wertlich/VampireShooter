"""Keyframes run and attack actions for the skeleton rig and exports a GLB.

Run:
  blender --background --factory-startup --python tools/blender_animate.py -- \
      <rig.blend> <glb out> <render dir>
"""

import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
BLEND = argv[0]
OUT_GLB = argv[1]
OUT_DIR = argv[2]
os.makedirs(OUT_DIR, exist_ok=True)

FPS = 24
RUN_FRAMES = 16
ATTACK_FRAMES = 24


def world_rot(pb, axis, degrees):
    """Quaternion that rotates this bone about a world axis, in bone space."""
    rest = pb.bone.matrix_local.to_3x3()
    rot = Matrix.Rotation(math.radians(degrees), 3, axis)
    return (rest.inverted() @ rot @ rest).to_quaternion()


def pose(arm, frame, spec, root_loc=None):
    for bone_name, rotations in spec.items():
        pb = arm.pose.bones[bone_name]
        pb.rotation_mode = "QUATERNION"
        # Every keyframe is an absolute pose: start from the rest orientation.
        q = Quaternion()
        for axis, degrees in rotations:
            q = world_rot(pb, axis, degrees) @ q
        pb.rotation_quaternion = q
        pb.keyframe_insert("rotation_quaternion", frame=frame)

    if root_loc is not None:
        pb = arm.pose.bones["root"]
        pb.rotation_mode = "QUATERNION"
        # Bone points up: local Y is world +Z, local Z is world -Y (forward).
        pb.location = root_loc
        pb.keyframe_insert("location", frame=frame)


def clear_pose(arm):
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pb.location = (0.0, 0.0, 0.0)


def make_action(arm, name):
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = action
    clear_pose(arm)
    return action


def build_run(arm):
    action = make_action(arm, "Run")
    action.frame_range  # touch

    # A contact pose with the left leg forward, and its mirror.
    contact_l = {
        "thigh.L": [("X", -30.0)],
        "shin.L": [("X", 14.0)],
        "foot.L": [("X", 12.0)],
        "thigh.R": [("X", 24.0)],
        "shin.R": [("X", 52.0)],
        "foot.R": [("X", -18.0)],
        "upper_arm.L": [("X", 30.0), ("Y", 34.0)],
        "forearm.L": [("X", 24.0)],
        "upper_arm.R": [("X", -28.0), ("Y", -34.0)],
        "forearm.R": [("X", 44.0)],
        "spine": [("X", 7.0), ("Z", -5.0)],
        "chest": [("X", 4.0), ("Z", 6.0)],
        "head": [("X", -6.0)],
        "hips": [("Z", 5.0)],
    }
    contact_r = {
        "thigh.R": [("X", -30.0)],
        "shin.R": [("X", 14.0)],
        "foot.R": [("X", 12.0)],
        "thigh.L": [("X", 24.0)],
        "shin.L": [("X", 52.0)],
        "foot.L": [("X", -18.0)],
        "upper_arm.R": [("X", 30.0), ("Y", -34.0)],
        "forearm.R": [("X", 24.0)],
        "upper_arm.L": [("X", -28.0), ("Y", 34.0)],
        "forearm.L": [("X", 44.0)],
        "spine": [("X", 7.0), ("Z", 5.0)],
        "chest": [("X", 4.0), ("Z", -6.0)],
        "head": [("X", -6.0)],
        "hips": [("Z", -5.0)],
    }
    # Passing poses: legs under the body, one knee lifted.
    pass_l = {
        "thigh.L": [("X", 6.0)],
        "shin.L": [("X", 30.0)],
        "thigh.R": [("X", -8.0)],
        "shin.R": [("X", 10.0)],
        "upper_arm.L": [("X", 2.0), ("Y", 34.0)],
        "forearm.L": [("X", 30.0)],
        "upper_arm.R": [("X", -2.0), ("Y", -34.0)],
        "forearm.R": [("X", 32.0)],
        "spine": [("X", 7.0)],
        "chest": [("X", 4.0)],
        "head": [("X", -6.0)],
    }
    pass_r = {
        "thigh.R": [("X", 6.0)],
        "shin.R": [("X", 30.0)],
        "thigh.L": [("X", -8.0)],
        "shin.L": [("X", 10.0)],
        "upper_arm.R": [("X", 2.0), ("Y", -34.0)],
        "forearm.R": [("X", 30.0)],
        "upper_arm.L": [("X", -2.0), ("Y", 34.0)],
        "forearm.L": [("X", 32.0)],
        "spine": [("X", 7.0)],
        "chest": [("X", 4.0)],
        "head": [("X", -6.0)],
    }

    pose(arm, 0, contact_l, root_loc=(0.0, -0.02, 0.0))
    pose(arm, 4, pass_l, root_loc=(0.0, 0.04, 0.0))
    pose(arm, 8, contact_r, root_loc=(0.0, -0.02, 0.0))
    pose(arm, 12, pass_r, root_loc=(0.0, 0.04, 0.0))
    pose(arm, 16, contact_l, root_loc=(0.0, -0.02, 0.0))
    return action


def build_attack(arm):
    action = make_action(arm, "Attack")

    relax = {
        "upper_arm.L": [("Y", 20.0)],
        "upper_arm.R": [("Y", -20.0)],
        "forearm.L": [("X", 10.0)],
        "forearm.R": [("X", 10.0)],
        "spine": [("X", 4.0)],
    }
    # Pull the right claw back and across, twist away from the target.
    windup = {
        "upper_arm.R": [("Z", -30.0), ("X", 30.0), ("Y", -14.0)],
        "forearm.R": [("X", 50.0)],
        "upper_arm.L": [("Z", 16.0), ("X", -22.0), ("Y", 26.0)],
        "forearm.L": [("X", 30.0)],
        "thigh.R": [("X", 18.0)],
        "thigh.L": [("X", -14.0)],
        "shin.R": [("X", 34.0)],
        "spine": [("X", -6.0), ("Z", -16.0)],
        "chest": [("Z", -20.0)],
        "head": [("Z", 12.0)],
    }
    # Sweep the claw down and across the body, step into it.
    strike = {
        "upper_arm.R": [("Z", 50.0), ("X", -25.0)],
        "forearm.R": [("X", -5.0)],
        "upper_arm.L": [("Z", -12.0), ("X", 34.0), ("Y", 20.0)],
        "forearm.L": [("X", 26.0)],
        "thigh.R": [("X", -22.0)],
        "thigh.L": [("X", 16.0)],
        "shin.R": [("X", 18.0)],
        "spine": [("X", 18.0), ("Z", 16.0)],
        "chest": [("Z", 20.0)],
        "head": [("X", -12.0), ("Z", -8.0)],
    }
    follow = {
        "upper_arm.R": [("Z", 38.0), ("X", -15.0)],
        "forearm.R": [("X", 35.0)],
        "upper_arm.L": [("Z", -8.0), ("X", 16.0), ("Y", 20.0)],
        "forearm.L": [("X", 24.0)],
        "spine": [("X", 12.0), ("Z", 8.0)],
        "chest": [("Z", 10.0)],
        "head": [("X", -6.0)],
    }

    pose(arm, 0, relax, root_loc=(0.0, 0.0, 0.0))
    pose(arm, 7, windup, root_loc=(0.0, 0.0, -0.05))
    pose(arm, 12, strike, root_loc=(0.0, -0.05, 0.12))
    pose(arm, 17, follow, root_loc=(0.0, -0.02, 0.06))
    pose(arm, 24, relax, root_loc=(0.0, 0.0, 0.0))
    return action


def setup_render():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 520
    scene.render.resolution_y = 520
    scene.render.fps = FPS
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "SINGLE"
    shading.single_color = (0.82, 0.82, 0.84)
    shading.show_shadows = True


def render_frame(name, frame, cam_loc, look_at=(0.0, 0.0, 0.95)):
    scene = bpy.context.scene
    scene.frame_set(frame)
    cam_data = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = Vector(cam_loc)
    cam.rotation_euler = (Vector(look_at) - Vector(cam_loc)).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.filepath = os.path.join(OUT_DIR, name)
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)


def main():
    bpy.ops.wm.open_mainfile(filepath=BLEND)
    arm = bpy.data.objects["Rig"]
    bpy.context.view_layer.objects.active = arm

    # Re-runs must not stack duplicate actions and NLA tracks.
    ad = arm.animation_data
    if ad:
        for track in list(ad.nla_tracks):
            ad.nla_tracks.remove(track)
        ad.action = None
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)

    run = build_run(arm)
    setup_render()
    for frame in (0, 4, 8, 12):
        render_frame("run_%02d.png" % frame, frame, (2.2, -2.6, 1.5))

    attack = build_attack(arm)
    for frame in (0, 7, 12, 17):
        render_frame("attack_%02d.png" % frame, frame, (2.6, -2.2, 1.4))

    # Stash both actions in NLA so the glTF exporter picks them up.
    ad = arm.animation_data
    ad.action = None
    for action in (run, attack):
        track = ad.nla_tracks.new()
        track.name = action.name
        track.strips.new(action.name, 0, action)

    bpy.ops.export_scene.gltf(
        filepath=OUT_GLB,
        export_format="GLB",
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_apply=False,
        export_yup=True,
    )
    print("exported", OUT_GLB)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    print("saved", BLEND)


main()
