"""Build the cemetery's Blender-side assets.

Run headless from the Godot project root:
  blender --background --factory-startup --python tools/blender_cemetery.py

Outputs:
  models/cemetery/church/church_intact.glb   (OldChurch1, base at y=0, centred)
  models/cemetery/church/church_ruined.glb   (OldChurch2, base at y=0, centred)
  models/cemetery/lamps/japanese_lamp.glb    (optimised, base at y=0)
  models/cemetery/lamps/cage_lamp.glb        (textured, base at y=0)
  models/cemetery/fence/fence_a.glb          (8 m modular fence, ruined)
  models/cemetery/fence/fence_b.glb
  models/cemetery/fence/fence_c.glb
"""
import bpy
import bmesh
import math
import os
import random
import tempfile
import zipfile
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHURCH_SRC = os.path.join(ROOT, "models", "dom", "low-poly_church.glb")
JAPANESE_SRC = os.path.join(ROOT, "models", "lamp", "japanese_lamp_low-poly.glb")
CAGE_ZIP = os.path.join(ROOT, "models", "lamp for dom", "cage-lamp.zip")
CAGE_EXTRACT = os.path.join(tempfile.gettempdir(), "vampire_shooter_cage_lamp")
CAGE_SRC = os.path.join(CAGE_EXTRACT, "source", "cagecandle_lp.fbx")
CAGE_TEXTURES = os.path.join(CAGE_EXTRACT, "textures")
OUT_CHURCH = os.path.join(ROOT, "models", "cemetery", "church")
OUT_LAMPS = os.path.join(ROOT, "models", "cemetery", "lamps")
OUT_FENCE = os.path.join(ROOT, "models", "cemetery", "fence")


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"


def select_only(objects):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    if objects:
        bpy.context.view_layer.objects.active = objects[0]


def join_meshes(meshes, name):
    select_only(meshes)
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return joined


def world_bounds(objects):
    points = []
    for obj in objects:
        if obj.type != "MESH":
            continue
        for corner in obj.bound_box:
            points.append(obj.matrix_world @ Vector(corner))
    if not points:
        return Vector((0, 0, 0)), Vector((0, 0, 0))
    lo = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    hi = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return lo, hi


def ground_and_center(obj, target_height=None):
    lo, hi = world_bounds([obj])
    height = hi.z - lo.z
    if target_height is not None and height > 1e-6:
        scale = target_height / height
        obj.scale = (scale, scale, scale)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        lo, hi = world_bounds([obj])
    center = (lo + hi) * 0.5
    obj.location += Vector((-center.x, -center.y, -lo.z))
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    lo, hi = world_bounds([obj])
    return lo, hi


def export_glb(paths):
    os.makedirs(os.path.dirname(paths), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=paths,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_extras=False,
    )
    print("EXPORTED", paths, os.path.getsize(paths), "bytes")


def extract_church(branch, out_path):
    reset_scene()
    bpy.ops.import_scene.gltf(filepath=CHURCH_SRC)
    meshes = [obj for obj in bpy.data.objects if obj.type == "MESH" and obj.name.startswith(branch + "_")]
    if not meshes:
        raise RuntimeError("No meshes for " + branch)
    joined = join_meshes(meshes, branch)
    lo, hi = ground_and_center(joined)
    print("CHURCH", branch, "bounds", tuple(round(v, 3) for v in lo), tuple(round(v, 3) for v in hi),
          "verts", len(joined.data.vertices), "polys", len(joined.data.polygons))
    select_only([joined])
    export_glb(out_path)


def load_image(path, colorspace="sRGB", max_size=1024):
    img = bpy.data.images.load(path, check_existing=True)
    if max_size and max(img.size) > max_size:
        ratio = max_size / max(img.size)
        img.scale(max(1, int(img.size[0] * ratio)), max(1, int(img.size[1] * ratio)))
        img.pack()
    img.colorspace_settings.name = colorspace
    return img


def make_material(name, base=None, base_path=None, normal_path=None, roughness_path=None,
                  metallic_path=None, emissive_path=None, roughness=0.7, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    principled = nodes.get("Principled BSDF")
    principled.inputs["Roughness"].default_value = roughness
    principled.inputs["Metallic"].default_value = metallic
    if base is not None:
        principled.inputs["Base Color"].default_value = base
    if base_path:
        node = nodes.new("ShaderNodeTexImage")
        node.image = load_image(base_path, "sRGB")
        node.location = (-500, 300)
        links.new(node.outputs["Color"], principled.inputs["Base Color"])
    if roughness_path:
        node = nodes.new("ShaderNodeTexImage")
        node.image = load_image(roughness_path, "Non-Color")
        node.location = (-500, 0)
        links.new(node.outputs["Color"], principled.inputs["Roughness"])
    if metallic_path:
        node = nodes.new("ShaderNodeTexImage")
        node.image = load_image(metallic_path, "Non-Color")
        node.location = (-500, -200)
        links.new(node.outputs["Color"], principled.inputs["Metallic"])
    if normal_path:
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = load_image(normal_path, "Non-Color")
        tex.location = (-600, -450)
        normal = nodes.new("ShaderNodeNormalMap")
        normal.location = (-300, -450)
        links.new(tex.outputs["Color"], normal.inputs["Color"])
        links.new(normal.outputs["Normal"], principled.inputs["Normal"])
    if emissive_path:
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = load_image(emissive_path, "sRGB")
        tex.location = (-500, 500)
        links.new(tex.outputs["Color"], principled.inputs["Emission Color"])
        principled.inputs["Emission Strength"].default_value = 2.2
    return mat


def convert_japanese():
    reset_scene()
    bpy.ops.import_scene.gltf(filepath=JAPANESE_SRC)
    meshes = [obj for obj in bpy.data.objects if obj.type == "MESH"]
    joined = join_meshes(meshes, "JapaneseLamp")
    lo, hi = ground_and_center(joined, target_height=3.0)
    for img in bpy.data.images:
        if max(img.size) > 1024:
            ratio = 1024 / max(img.size)
            img.scale(max(1, int(img.size[0] * ratio)), max(1, int(img.size[1] * ratio)))
            img.pack()
    # The tiny box at the top of this asset is the paper light panel. Give the
    # untextured material a warm emission so the lamp reads as lit at night.
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        principled = mat.node_tree.nodes.get("Principled BSDF")
        if principled and mat.name.lower() == "material":
            principled.inputs["Base Color"].default_value = (1.0, 0.62, 0.28, 1.0)
            principled.inputs["Emission Color"].default_value = (1.0, 0.45, 0.12, 1.0)
            principled.inputs["Emission Strength"].default_value = 3.0
    print("JAPANESE bounds", tuple(round(v, 3) for v in lo), tuple(round(v, 3) for v in hi),
          "verts", len(joined.data.vertices), "polys", len(joined.data.polygons))
    select_only([joined])
    export_glb(os.path.join(OUT_LAMPS, "japanese_lamp.glb"))


def convert_cage():
    if not os.path.exists(CAGE_SRC):
        if not os.path.exists(CAGE_ZIP):
            raise RuntimeError("Missing cage-lamp source: " + CAGE_ZIP)
        os.makedirs(CAGE_EXTRACT, exist_ok=True)
        with zipfile.ZipFile(CAGE_ZIP) as archive:
            archive.extractall(CAGE_EXTRACT)
    reset_scene()
    bpy.ops.import_scene.fbx(filepath=CAGE_SRC)
    meshes = [obj for obj in bpy.data.objects if obj.type == "MESH"]
    joined = join_meshes(meshes, "CageLamp")
    lo, hi = ground_and_center(joined, target_height=1.35)
    mat = make_material(
        "CageLamp",
        base_path=os.path.join(CAGE_TEXTURES, "CageCandle_lp_CageCandle_BaseColor.png"),
        normal_path=os.path.join(CAGE_TEXTURES, "CageCandle_lp_CageCandle_Normal.png"),
        roughness_path=os.path.join(CAGE_TEXTURES, "CageCandle_lp_CageCandle_Roughness.png"),
        metallic_path=os.path.join(CAGE_TEXTURES, "CageCandle_lp_CageCandle_Metallic.png"),
        emissive_path=os.path.join(CAGE_TEXTURES, "CageCandle_lp_CageCandle_Emissive.png"),
        roughness=0.55,
        metallic=0.65,
    )
    joined.data.materials.clear()
    joined.data.materials.append(mat)
    for poly in joined.data.polygons:
        poly.material_index = 0
    print("CAGE bounds", tuple(round(v, 3) for v in lo), tuple(round(v, 3) for v in hi),
          "verts", len(joined.data.vertices), "polys", len(joined.data.polygons))
    select_only([joined])
    export_glb(os.path.join(OUT_LAMPS, "cage_lamp.glb"))


def wood_material(name, color, roughness=0.92):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    principled = mat.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = (*color, 1.0)
    principled.inputs["Roughness"].default_value = roughness
    principled.inputs["Metallic"].default_value = 0.0
    return mat


def add_box(name, center, size, mat, rot=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center, rotation=rot)
    obj = bpy.context.object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.data.materials.append(mat)
    return obj


def build_fence(seed, variant):
    reset_scene()
    rng = random.Random(seed)
    dark = wood_material("FenceWoodDark", (0.10, 0.065, 0.038), 0.95)
    grey = wood_material("FenceWoodGrey", (0.20, 0.155, 0.105), 0.9)
    moss = wood_material("FenceMoss", (0.13, 0.19, 0.055), 1.0)
    materials = [dark, grey, moss]
    pieces = []
    length = 8.0

    def pick():
        return materials[0] if rng.random() < 0.62 else materials[1]

    # Main posts, one of them leaning or broken on the heavier variants.
    for i, x in enumerate((-length * 0.5, length * 0.5)):
        lean = rng.uniform(-0.045, 0.045) if variant < 2 else rng.uniform(-0.12, 0.12)
        height = rng.uniform(2.15, 2.55)
        if variant == 2 and i == 1:
            height = 1.35
        post = add_box("post_%d" % i, (x, 0.0, height * 0.5), (0.22, 0.22, height),
                       pick(), (lean, 0.0, rng.uniform(-0.04, 0.04)))
        pieces.append(post)
        # A half-buried stone-ish base makes the post sit in the grass.
        pieces.append(add_box("post_base_%d" % i, (x, 0.0, 0.055), (0.36, 0.36, 0.11),
                              materials[1]))

    # Two rails; they are segmented and some pieces are missing or sagging.
    for rail_index, z in enumerate((0.65, 1.62)):
        for seg in range(3):
            if rng.random() < (0.15 if variant < 2 else 0.34):
                continue
            x0 = -length * 0.5 + 0.25 + seg * (length - 0.5) / 3.0
            seg_len = (length - 0.5) / 3.0 - rng.uniform(0.02, 0.25)
            cx = x0 + seg_len * 0.5
            sag = rng.uniform(-0.06, 0.06)
            pieces.append(add_box("rail_%d_%d" % (rail_index, seg),
                                  (cx, 0.0, z + sag), (seg_len, 0.10, 0.13),
                                  pick(), (rng.uniform(-0.02, 0.02), 0.0, rng.uniform(-0.02, 0.02))))

    # Pickets. Missing / shortened / crooked planks make each module read as old.
    x = -length * 0.5 + 0.34
    index = 0
    while x < length * 0.5 - 0.25:
        index += 1
        gone = 0.12 if variant < 2 else 0.28
        if rng.random() < gone:
            x += rng.uniform(0.28, 0.38)
            continue
        height = rng.uniform(1.55, 1.93)
        if rng.random() < 0.14:
            height = rng.uniform(0.55, 1.3)
        tilt = rng.uniform(-0.10, 0.10) if variant < 2 else rng.uniform(-0.24, 0.24)
        yaw = rng.uniform(-0.05, 0.05)
        z = height * 0.5 + 0.06
        picket = add_box("picket_%03d" % index, (x, 0.0, z), (0.16, 0.065, height),
                         pick(), (tilt, 0.0, yaw))
        pieces.append(picket)
        # Pointed top made from a small rotated cube; cheap but reads at distance.
        pieces.append(add_box("picket_tip_%03d" % index,
                              (x, 0.0, z + height * 0.5 + 0.055),
                              (0.12, 0.065, 0.11), pick(),
                              (tilt, 0.0, math.radians(45.0) + yaw)))
        x += rng.uniform(0.29, 0.36)

    # A fallen plank or two on the ground, especially on the broken variant.
    for i in range(2 if variant == 2 else 1):
        px = rng.uniform(-2.8, 2.8)
        py = rng.uniform(0.2, 0.75)
        pieces.append(add_box("fallen_%d" % i, (px, py, 0.09),
                              (rng.uniform(1.1, 2.0), 0.07, 0.16), pick(),
                              (0.04, 0.0, rng.uniform(-1.2, 1.2))))

    # A little moss on one post and one picket.
    pieces.append(add_box("moss_post", (-length * 0.5, 0.0, rng.uniform(0.6, 1.6)),
                          (0.235, 0.235, rng.uniform(0.25, 0.55)), materials[2]))
    pieces.append(add_box("moss_rail", (rng.uniform(-3.2, 3.2), 0.02, 1.60),
                          (rng.uniform(0.5, 1.3), 0.11, 0.14), materials[2]))

    joined = join_meshes(pieces, "Fence_%s" % variant)
    lo, hi = world_bounds([joined])
    print("FENCE", variant, "bounds", tuple(round(v, 3) for v in lo), tuple(round(v, 3) for v in hi),
          "verts", len(joined.data.vertices), "polys", len(joined.data.polygons))
    select_only([joined])
    export_glb(os.path.join(OUT_FENCE, "fence_%s.glb" % "abc"[variant]))


def main():
    os.makedirs(OUT_CHURCH, exist_ok=True)
    os.makedirs(OUT_LAMPS, exist_ok=True)
    os.makedirs(OUT_FENCE, exist_ok=True)
    extract_church("OldChurch1", os.path.join(OUT_CHURCH, "church_intact.glb"))
    extract_church("OldChurch2", os.path.join(OUT_CHURCH, "church_ruined.glb"))
    convert_japanese()
    convert_cage()
    for i in range(3):
        build_fence(4100 + i * 97, i)
    print("DONE")


if __name__ == "__main__":
    main()
