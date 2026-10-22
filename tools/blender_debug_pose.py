"""Prints world-space bone directions for a given action and frame.

Run: blender --background --factory-startup --python tools/blender_debug_pose.py -- <blend> <action> <frame>
"""

import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
BLEND, ACTION, FRAME = argv[0], argv[1], int(argv[2])

bpy.ops.wm.open_mainfile(filepath=BLEND)
arm = bpy.data.objects["Rig"]
ad = arm.animation_data
ad.use_nla = False
ad.action = bpy.data.actions[ACTION]
bpy.context.scene.frame_set(FRAME)
bpy.context.view_layer.update()

for name in ("upper_arm.R", "forearm.R", "hand.R", "upper_arm.L", "thigh.R", "shin.R"):
    pb = arm.pose.bones[name]
    head = arm.matrix_world @ pb.head
    tail = arm.matrix_world @ pb.tail
    d = (tail - head).normalized()
    print("%-12s head=(%.2f %.2f %.2f) dir=(%.2f %.2f %.2f)" % (
        name, head.x, head.y, head.z, d.x, d.y, d.z))
