"""Builds a 100x100 gothic castle (ruined cathedral courtyard) and exports it
for Godot together with a JSON of collision boxes and light positions.

Run:
  blender --background --factory-startup --python tools/blender_castle.py -- \
      <out.glb> <out.json> <render dir>
"""

import json
import math
import os
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_GLB, OUT_JSON, OUT_DIR = argv[0], argv[1], argv[2]
os.makedirs(OUT_DIR, exist_ok=True)
os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)

SIZE = 100.0
HALF = SIZE / 2.0
WALL_H = 13.0
WALL_T = 1.6

PARTS = []
COLLISION = []
CANDLES = []
BRAZIERS = []


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


MATS = {}


def mat(name, color, rough=0.9, metal=0.0, emit=None, strength=0.0):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit is not None:
        for key in ("Emission Color", "Emission"):
            if key in bsdf.inputs:
                bsdf.inputs[key].default_value = (*emit, 1.0)
                break
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = strength
    MATS[name] = m
    return m


STONE = None
STONE_DARK = None
STONE_LIGHT = None
WOOD = None
IRON = None
WAX = None
FLAME = None
GLASS = {}


def build_materials():
    global STONE, STONE_DARK, STONE_LIGHT, WOOD, IRON, WAX, FLAME
    STONE = mat("stone", (0.16, 0.155, 0.16), 0.92)
    STONE_DARK = mat("stone_dark", (0.09, 0.09, 0.1), 0.95)
    STONE_LIGHT = mat("stone_light", (0.24, 0.23, 0.22), 0.88)
    WOOD = mat("wood", (0.14, 0.08, 0.04), 0.8)
    IRON = mat("iron", (0.05, 0.05, 0.06), 0.45, metal=1.0)
    WAX = mat("wax", (0.75, 0.7, 0.6), 0.7)
    FLAME = mat("flame", (1.0, 0.55, 0.2), 0.4, emit=(1.0, 0.55, 0.2), strength=9.0)
    GLASS["red"] = mat("glass_red", (0.3, 0.03, 0.05), 0.35, emit=(0.9, 0.08, 0.1), strength=0.9)
    GLASS["blue"] = mat("glass_blue", (0.05, 0.1, 0.35), 0.35, emit=(0.15, 0.3, 1.0), strength=0.8)
    GLASS["violet"] = mat("glass_violet", (0.2, 0.05, 0.3), 0.35, emit=(0.55, 0.15, 0.85), strength=0.8)


def register(obj, material):
    obj.data.materials.clear()
    obj.data.materials.append(material)
    PARTS.append(obj)
    return obj


def box(center, size, material, rot=(0.0, 0.0, 0.0), name="box", collide=False):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center, rotation=rot)
    o = bpy.context.object
    o.name = name
    o.scale = (size[0], size[1], size[2])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if collide:
        COLLISION.append({
            "pos": [round(v, 3) for v in center],
            "size": [round(v, 3) for v in size],
            "rot_y": round(rot[2], 4),
        })
    return register(o, material)


def cyl(center, radius, depth, material, vertices=14, name="cyl", collide=False):
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, location=center, vertices=vertices)
    o = bpy.context.object
    o.name = name
    if collide:
        COLLISION.append({
            "pos": [round(v, 3) for v in center],
            "size": [round(radius * 2, 3), round(radius * 2, 3), round(depth, 3)],
            "rot_y": 0.0,
        })
    return register(o, material)


def cone(center, radius, depth, material, vertices=14, name="cone"):
    bpy.ops.mesh.primitive_cone_add(radius1=radius, radius2=0.0, depth=depth,
                                    location=center, vertices=vertices)
    o = bpy.context.object
    o.name = name
    return register(o, material)


def sphere(center, radius, material, name="sphere"):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=center, segments=10, ring_count=6)
    o = bpy.context.object
    o.name = name
    return register(o, material)


# --- Architecture -----------------------------------------------------------

def ground():
    box((0, 0, -0.5), (SIZE, SIZE, 1.0), STONE_DARK, name="ground", collide=True)
    # Border paving so the courtyard reads as a place, not a plane.
    box((0, 0, 0.02), (SIZE - 12, SIZE - 12, 0.06), STONE_LIGHT, name="paving")
    for i in range(-4, 5):
        box((i * 10.0, 0, 0.05), (0.4, SIZE - 14, 0.06), STONE, name="seam_x")
        box((0, i * 10.0, 0.05), (SIZE - 14, 0.4, 0.06), STONE, name="seam_y")


def crenellations(x0, y0, x1, y1, z, along_x):
    length = (x1 - x0) if along_x else (y1 - y0)
    count = max(2, int(length / 3.2))
    for i in range(count):
        t = (i + 0.5) / count
        cx = x0 + (x1 - x0) * t
        cy = y0 + (y1 - y0) * t
        size = (1.5, 0.9, 1.5) if along_x else (0.9, 1.5, 1.5)
        box((cx, cy, z + 0.75), size, STONE_DARK, name="merlon")


def curtain_wall(fixed, axis, gate=False):
    """A 100 m wall with crenellations; optionally with a gate opening."""
    if axis == "x":
        y = fixed
        if gate:
            seg = 8.0
            for sx in (-1, 1):
                box((sx * (seg + (HALF - seg) / 2), y, WALL_H / 2),
                    (HALF - seg, WALL_T, WALL_H), STONE, name="wall", collide=True)
                crenellations(sx * seg, y - WALL_T / 2, sx * HALF, y + WALL_T / 2, WALL_H, True)
            # Gate arch frame.
            box((-7.0, y, WALL_H * 0.55), (1.2, WALL_T + 0.6, WALL_H * 1.1), STONE_LIGHT, name="gate_pier", collide=True)
            box((7.0, y, WALL_H * 0.55), (1.2, WALL_T + 0.6, WALL_H * 1.1), STONE_LIGHT, name="gate_pier", collide=True)
            box((0.0, y, WALL_H * 0.95), (15.2, WALL_T + 0.6, 2.4), STONE_LIGHT, name="gate_lintel")
            arch(0.0, y, 7.0, WALL_H * 0.55, 0.9, WALL_T + 0.4, STONE_LIGHT, vertical_axis="z")
        else:
            box((0, y, WALL_H / 2), (SIZE, WALL_T, WALL_H), STONE, name="wall", collide=True)
            crenellations(-HALF, y - WALL_T / 2, HALF, y + WALL_T / 2, WALL_H, True)
    else:
        x = fixed
        box((x, 0, WALL_H / 2), (WALL_T, SIZE, WALL_H), STONE, name="wall", collide=True)
        crenellations(x - WALL_T / 2, -HALF, x + WALL_T / 2, HALF, WALL_H, False)


def arc_samples(cx, cz, radius, a0, a1, segs):
    return [(cx + radius * math.cos(math.radians(a0 + (a1 - a0) * i / segs)),
             cz + radius * math.sin(math.radians(a0 + (a1 - a0) * i / segs)))
            for i in range(segs + 1)]


def arch(cx, cy, span, spring_z, thickness, depth, material, vertical_axis="z"):
    """Pointed gothic arch from voussoir blocks, spanning along X."""
    radius = span
    half = span / 2.0
    segs = 7
    left = arc_samples(-half, spring_z, radius, 0.0, 60.0, segs)
    right = arc_samples(half, spring_z, radius, 120.0, 180.0, segs)
    path = left + right
    for i in range(len(path) - 1):
        x0, z0 = path[i]
        x1, z1 = path[i + 1]
        mx, mz = (x0 + x1) / 2.0, (z0 + z1) / 2.0
        dx, dz = x1 - x0, z1 - z0
        length = math.hypot(dx, dz) * 1.25
        angle = math.atan2(-dz, dx)
        box((cx + mx, cy, mz), (length, depth, thickness), material,
            rot=(0.0, angle, 0.0), name="voussoir")


def tower(x, y, radius, height, roof_h):
    cyl((x, y, height / 2), radius, height, STONE, vertices=16, name="tower", collide=True)
    cyl((x, y, height + 0.4), radius + 0.7, 0.8, STONE_DARK, vertices=16, name="tower_rim")
    cone((x, y, height + roof_h / 2 + 0.8), radius + 0.9, roof_h, STONE_DARK, vertices=16, name="tower_roof")
    # Slit windows.
    for i in range(3):
        a = math.radians(i * 120.0 + 30.0)
        wx = x + math.cos(a) * (radius - 0.05)
        wy = y + math.sin(a) * (radius - 0.05)
        box((wx, wy, height * 0.65), (0.35, 0.8, 1.8), STONE_DARK,
            rot=(0.0, 0.0, a), name="slit")


def gargoyle(x, y, z, facing):
    """Small stone beast: body, head, wings, tail."""
    rot = (0.0, 0.0, facing)
    box((x, y, z), (0.9, 1.3, 0.7), STONE_DARK, rot=rot, name="garg_body")
    box((x + math.sin(facing) * 0.7, y + math.cos(facing) * 0.7, z + 0.35),
        (0.55, 0.6, 0.5), STONE_DARK, rot=rot, name="garg_head")
    box((x + math.sin(facing) * 0.95, y + math.cos(facing) * 0.95, z + 0.28),
        (0.28, 0.35, 0.25), STONE_DARK, rot=rot, name="garg_snout")
    for side in (-1, 1):
        box((x + math.cos(facing) * 0.45 * side, y - math.sin(facing) * 0.45 * side, z + 0.55),
            (0.9, 0.18, 0.75), STONE_DARK,
            rot=(math.radians(38 * side), 0.0, facing + math.radians(20 * side)),
            name="garg_wing")
    box((x - math.sin(facing) * 0.8, y - math.cos(facing) * 0.8, z + 0.2),
        (0.2, 0.9, 0.2), STONE_DARK, rot=rot, name="garg_tail")


def candle(x, y, z, height=0.45):
    cyl((x, y, z + height / 2), 0.09, height, WAX, vertices=8, name="candle")
    cone((x, y, z + height + 0.1), 0.07, 0.22, FLAME, vertices=8, name="flame")
    CANDLES.append([round(x, 2), round(y, 2), round(z + height + 0.1, 2)])


def candelabra(x, y, z):
    cyl((x, y, z + 0.05), 0.35, 0.1, IRON, vertices=10, name="cand_base")
    cyl((x, y, z + 0.9), 0.07, 1.8, IRON, vertices=8, name="cand_pole")
    for i in range(3):
        a = math.radians(i * 120.0)
        candle(x + math.cos(a) * 0.45, y + math.sin(a) * 0.45, z + 1.75, 0.35)


def brazier(x, y):
    cyl((x, y, 0.75), 0.55, 1.5, IRON, vertices=12, name="brazier", collide=True)
    cyl((x, y, 1.55), 0.75, 0.35, IRON, vertices=12, name="brazier_bowl")
    sphere((x, y, 1.85), 0.42, FLAME, name="fire")
    BRAZIERS.append([round(x, 2), round(y, 2), 1.9])


def window_wall(center, length, height, thickness, axis, glass_colors):
    """Wall with lancet windows made of emissive panes (no booleans).

    `axis` is the direction the wall runs along: "x" or "y".
    """
    count = len(glass_colors)
    slot = length / count

    def place(offset, along_size, across_size, z, h, material, name, collide=False):
        if axis == "x":
            pos = (center[0] + offset, center[1], z)
            size = (along_size, across_size, h)
        else:
            pos = (center[0], center[1] + offset, z)
            size = (across_size, along_size, h)
        box(pos, size, material, name=name, collide=collide)

    for i in range(count):
        offset = (i - (count - 1) / 2.0) * slot
        color = GLASS[glass_colors[i]]
        place(offset - slot * 0.5, slot * 0.2, thickness, height / 2, height, STONE, "pier", True)
        place(offset, slot * 0.8, thickness, 1.6, 3.2, STONE, "sill", True)
        place(offset, slot * 0.8, thickness, height - 1.2, 2.4, STONE, "lintel")
        # Narrow lancet pane with a stone mullion down the middle.
        place(offset, slot * 0.17, thickness * 0.4, (height - 0.8) / 2.0 + 0.6,
            height - 7.2, color, "glass")
        place(offset, slot * 0.05, thickness * 0.5, (height - 0.8) / 2.0 + 0.6,
            height - 7.2, STONE_DARK, "mullion")

    last = (count - 1) / 2.0 * slot + slot * 0.5
    place(last, slot * 0.2, thickness, height / 2, height, STONE, "pier", True)


def cathedral():
    # Raised platform with steps.
    box((0, 0, 0.35), (44.0, 30.0, 0.7), STONE_LIGHT, name="platform", collide=True)
    for i in range(3):
        box((0, 15.6 + i * 0.5, 0.7 - i * 0.2), (30.0 - i * 2, 1.0, 0.2), STONE_LIGHT, name="step")

    # Colonnade: two rows of columns with pointed arches.
    for side in (-1, 1):
        x = 10.0 * side
        for k in range(4):
            y = -10.0 + k * 6.0
            cyl((x, y, 4.7), 0.75, 8.0, STONE, vertices=14, name="column", collide=True)
            box((x, y, 0.45), (2.0, 2.0, 0.9), STONE_DARK, name="column_base")
            box((x, y, 8.9), (2.2, 2.2, 0.8), STONE_DARK, name="capital")
            candle(x, y, 9.3, 0.5)
            if k < 3:
                arch(x, y + 3.0, 6.0, 9.3, 0.7, 1.2, STONE)

    # Back wall with stained glass.
    window_wall((0.0, 13.5), 26.0, 14.0, 1.2, "x", ["red", "violet", "blue"])
    # Side walls, shorter, with lancets.
    window_wall((16.0, 0.0), 26.0, 10.0, 1.2, "y", ["blue", "red"])
    window_wall((-16.0, 0.0), 26.0, 10.0, 1.2, "y", ["violet", "blue"])

    # Altar block.
    box((0, 10.0, 1.2), (5.0, 2.4, 1.6), STONE_DARK, name="altar", collide=True)
    candle(-1.2, 10.0, 2.1, 0.6)
    candle(1.2, 10.0, 2.1, 0.6)

    # Rose window above the altar: a ring of stone over emissive glass.
    bpy.ops.mesh.primitive_torus_add(location=(0, 13.4, 12.0), rotation=(math.radians(90), 0, 0),
                                     major_radius=3.2, minor_radius=0.35, major_segments=20,
                                     minor_segments=8)
    register(bpy.context.object, STONE_DARK)
    cyl((0, 13.45, 12.0), 3.1, 0.2, GLASS["red"], vertices=20, name="rose_glass")
    bpy.context.object.rotation_euler = (math.radians(90), 0, 0)
    for i in range(8):
        a = math.radians(i * 45.0)
        box((math.cos(a) * 1.6, 13.3, 12.0 + math.sin(a) * 1.6),
            (0.28, 0.35, 3.0), STONE_DARK, rot=(0.0, a, 0.0), name="rose_spoke")

    # Gargoyles at the back wall corners.
    gargoyle(-13.0, 13.6, 13.6, math.radians(180))
    gargoyle(13.0, 13.6, 13.6, math.radians(180))
    gargoyle(-17.0, -12.0, 10.5, math.radians(90))
    gargoyle(17.0, -12.0, 10.5, math.radians(-90))


def courtyard():
    # Candles and braziers around the yard.
    for i in range(8):
        a = math.radians(45.0 * i + 22.5)
        candelabra(math.cos(a) * 30.0, math.sin(a) * 30.0, 0.0)
    for sx in (-1, 1):
        for sy in (-1, 1):
            brazier(sx * 34.0, sy * 34.0)
            gargoyle(sx * 46.0, sy * 46.0, 8.0, math.radians(45 * sx))
    # Cover props: crates and tombs.
    for i, (x, y) in enumerate([(-26, -18), (26, -18), (-27, 16), (27, 16), (0, -22)]):
        box((x, y, 0.6), (2.2, 1.4, 1.2), WOOD, name="crate", collide=True)
        box((x, y, 1.25), (2.4, 1.6, 0.2), STONE_DARK, name="crate_lid")
    for i in range(6):
        a = math.radians(60.0 * i)
        x, y = math.cos(a) * 22.0, math.sin(a) * 22.0
        box((x, y, 0.45), (1.1, 2.4, 0.9), STONE_DARK, rot=(0, 0, a), name="tomb", collide=True)
        box((x, y, 0.85), (0.8, 0.6, 1.2), STONE_DARK, rot=(0, 0, a), name="tomb_cross")

    # Torch candles along the curtain walls.
    for i in range(5):
        t = -40.0 + i * 20.0
        candle(t, -47.5, 3.2, 0.6)
        candle(t, 47.5, 3.2, 0.6)
        candle(-47.5, t, 3.2, 0.6)
        candle(47.5, t, 3.2, 0.6)


def main():
    reset()
    build_materials()
    ground()
    curtain_wall(-HALF + WALL_T / 2, "x", gate=True)
    curtain_wall(HALF - WALL_T / 2, "x", gate=False)
    curtain_wall(-HALF + WALL_T / 2, "y", gate=False)
    curtain_wall(HALF - WALL_T / 2, "y", gate=False)
    for sx in (-1, 1):
        for sy in (-1, 1):
            tower(sx * 46.0, sy * 46.0, 6.0, 20.0, 9.0)
    tower(-46.0, 0.0, 4.5, 17.0, 7.0)
    tower(46.0, 0.0, 4.5, 17.0, 7.0)
    cathedral()
    courtyard()

    # Join everything per material: a handful of draw calls instead of hundreds.
    bpy.ops.object.select_all(action="DESELECT")
    buckets = {}
    for obj in PARTS:
        buckets.setdefault(obj.data.materials[0].name, []).append(obj)
    for mat_name, objs in buckets.items():
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        if len(objs) > 1:
            bpy.ops.object.join()
        joined = bpy.context.view_layer.objects.active
        joined.name = "castle_" + mat_name

    data = {
        "size": SIZE,
        "collision": COLLISION,
        "candles": CANDLES,
        "braziers": BRAZIERS,
        "player_spawn": [0.0, 1.2, 30.0],
    }
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1)
    print("wrote", OUT_JSON, "collision boxes:", len(COLLISION), "candles:", len(CANDLES))

    bpy.ops.export_scene.gltf(
        filepath=OUT_GLB,
        export_format="GLB",
        export_apply=True,
        export_yup=True,
        export_animations=False,
    )
    print("exported", OUT_GLB)

    render_previews()


def render_previews():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_shadows = True

    for name, loc, look in (
        ("castle_persp.png", (78.0, -78.0, 58.0), (0.0, 0.0, 4.0)),
        ("castle_top.png", (0.0, -1.0, 130.0), (0.0, 0.0, 0.0)),
    ):
        cam_data = bpy.data.cameras.new("cam")
        cam = bpy.data.objects.new("cam", cam_data)
        scene.collection.objects.link(cam)
        cam.location = loc
        from mathutils import Vector
        cam.rotation_euler = (Vector(look) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        cam.data.lens = 32
        scene.camera = cam
        scene.render.filepath = os.path.join(OUT_DIR, name)
        bpy.ops.render.render(write_still=True)
        bpy.data.objects.remove(cam)


main()
