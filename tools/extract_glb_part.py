"""Extracts a single character out of a multi-character GLB (Sketchfab packs
often ship a dozen rigged variants standing on a display platform in one file).

Keeps the named node and its subtree plus the chain of parents above it, drops
every sibling, and rewrites nodes / meshes / materials / skins / animation
channels to the surviving indices. The binary chunk is reused untouched, so
accessors and buffer views keep their meaning.

Run:
  python tools/extract_glb_part.py <in.glb> <out.glb> <node name> [--zero]
"""

import json
import struct
import sys

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942


def read_glb(path):
    data = open(path, "rb").read()
    magic, version, _length = struct.unpack_from("<III", data, 0)
    if magic != GLB_MAGIC:
        raise SystemExit("not a GLB: %s" % path)
    offset = 12
    js = None
    binary = b""
    while offset < len(data):
        chunk_len, chunk_type = struct.unpack_from("<II", data, offset)
        offset += 8
        chunk = data[offset:offset + chunk_len]
        if chunk_type == CHUNK_JSON:
            js = json.loads(chunk.decode("utf-8"))
        elif chunk_type == CHUNK_BIN:
            binary = chunk
        offset += chunk_len
    return js, binary


def write_glb(path, js, binary):
    payload = json.dumps(js, separators=(",", ":")).encode("utf-8")
    payload += b" " * ((4 - len(payload) % 4) % 4)
    binary = binary + b"\0" * ((4 - len(binary) % 4) % 4)
    total = 12 + 8 + len(payload) + 8 + len(binary)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", GLB_MAGIC, 2, total))
        f.write(struct.pack("<II", len(payload), CHUNK_JSON))
        f.write(payload)
        f.write(struct.pack("<II", len(binary), CHUNK_BIN))
        f.write(binary)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    zero = "--zero" in sys.argv
    if len(args) < 3:
        raise SystemExit(__doc__)
    src, dst, wanted = args[0], args[1], args[2]

    js, binary = read_glb(src)
    nodes = js["nodes"]

    target = None
    for i, node in enumerate(nodes):
        if node.get("name") == wanted:
            target = i
            break
    if target is None:
        names = [n.get("name") for n in nodes]
        raise SystemExit("node %r not found; first 40 names: %s" % (wanted, names[:40]))

    parents = {}
    for i, node in enumerate(nodes):
        for child in node.get("children", []):
            parents[child] = i

    keep = set()

    def add_subtree(i):
        if i in keep:
            return
        keep.add(i)
        for child in nodes[i].get("children", []):
            add_subtree(child)

    add_subtree(target)
    walker = target
    while walker in parents:
        walker = parents[walker]
        keep.add(walker)

    order = [i for i in range(len(nodes)) if i in keep]
    remap = {old: new for new, old in enumerate(order)}

    new_nodes = []
    for old in order:
        node = json.loads(json.dumps(nodes[old]))
        node.pop("children", None)
        if "children" in nodes[old]:
            kids = [remap[c] for c in nodes[old]["children"] if c in remap]
            if kids:
                node["children"] = kids
        if old == target and zero:
            node.pop("translation", None)
        node.pop("mesh", None)
        new_nodes.append(node)

    # Meshes: only the ones still referenced, remapped onto the new node list.
    mesh_remap = {}
    for old, node in zip(order, new_nodes):
        src_node = nodes[old]
        if "mesh" in src_node:
            mesh_remap.setdefault(src_node["mesh"], len(mesh_remap))
            node["mesh"] = mesh_remap[src_node["mesh"]]

    new_meshes = [js["meshes"][old] for old in sorted(mesh_remap, key=lambda m: mesh_remap[m])]

    # Materials: keep only those used by the surviving meshes.
    material_remap = {}
    new_meshes = json.loads(json.dumps(new_meshes))
    for mesh in new_meshes:
        for prim in mesh.get("primitives", []):
            if "material" in prim:
                material_remap.setdefault(prim["material"], len(material_remap))
                prim["material"] = material_remap[prim["material"]]
    new_materials = [js["materials"][old] for old in sorted(material_remap, key=lambda m: material_remap[m])]

    # Skins: remap joints, drop joints that were left behind.
    new_skins = []
    skin_remap = {}
    for old, node in zip(order, new_nodes):
        src_node = nodes[old]
        if "skin" not in src_node:
            continue
        skin_old = src_node["skin"]
        if skin_old in skin_remap:
            node["skin"] = skin_remap[skin_old]
            continue
        skin = json.loads(json.dumps(js["skins"][skin_old]))
        skin["joints"] = [remap[j] for j in skin.get("joints", []) if j in remap]
        if "skeleton" in skin:
            skin["skeleton"] = remap.get(skin["skeleton"], skin.get("skeleton"))
        skin_remap[skin_old] = len(new_skins)
        node["skin"] = skin_remap[skin_old]
        new_skins.append(skin)

    # Animations: keep the channels that still have a target node, and only the
    # samplers those channels actually use — otherwise every other character's
    # keyframes keep the whole binary chunk alive.
    new_animations = []
    for anim in js.get("animations", []):
        kept_channels = []
        kept_samplers = []
        sampler_remap = {}
        for channel in anim.get("channels", []):
            target_node = channel.get("target", {}).get("node")
            if target_node is None or target_node not in remap:
                continue
            channel = json.loads(json.dumps(channel))
            channel["target"]["node"] = remap[target_node]
            old_sampler = channel.get("sampler")
            if old_sampler not in sampler_remap:
                sampler_remap[old_sampler] = len(kept_samplers)
                kept_samplers.append(anim["samplers"][old_sampler])
            channel["sampler"] = sampler_remap[old_sampler]
            kept_channels.append(channel)
        if not kept_channels:
            continue
        anim = json.loads(json.dumps(anim))
        anim["channels"] = kept_channels
        anim["samplers"] = kept_samplers
        new_animations.append(anim)

    out = {
        "asset": js.get("asset", {"version": "2.0"}),
        "scene": 0,
        "scenes": [{"name": "Scene", "nodes": [remap[js["scenes"][0]["nodes"][0]]]}],
        "nodes": new_nodes,
        "meshes": new_meshes,
        "materials": new_materials,
        "accessors": js["accessors"],
        "bufferViews": js["bufferViews"],
        "buffers": js["buffers"],
    }
    if new_skins:
        out["skins"] = new_skins
    if new_animations:
        out["animations"] = new_animations
    if "textures" in js:
        out["textures"] = js["textures"]
    if "images" in js:
        out["images"] = js["images"]
    if "samplers" in js:
        out["samplers"] = js["samplers"]
    if "extensionsUsed" in js:
        out["extensionsUsed"] = js["extensionsUsed"]

    binary = compact_buffers(out, binary)

    write_glb(dst, out, binary)
    print("wrote %s (%.1f MB binary)" % (dst, len(binary) / 1048576.0))
    print("  nodes %d -> %d, meshes %d -> %d, materials %d -> %d, skins -> %d, animations %d -> %d"
          % (len(nodes), len(new_nodes), len(js.get("meshes", [])), len(new_meshes),
             len(js.get("materials", [])), len(new_materials), len(new_skins),
             len(js.get("animations", [])), len(new_animations)))


COMPONENT_SIZES = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
TYPE_COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}


def compact_buffers(out, binary):
    """Rebuilds the binary chunk so only the bytes still referenced survive.

    Sketchfab packs write every character's keyframes and vertices into one or
    two huge buffer views, so slicing per buffer view is not enough: each
    accessor gets its own copy of exactly its own bytes.
    """
    used_accessors = set()

    def use_accessor(index):
        if index is not None:
            used_accessors.add(index)

    for mesh in out["meshes"]:
        for prim in mesh.get("primitives", []):
            for value in prim.get("attributes", {}).values():
                use_accessor(value)
            use_accessor(prim.get("indices"))
            for target in prim.get("targets", []):
                for value in target.values():
                    use_accessor(value)
    for skin in out.get("skins", []):
        use_accessor(skin.get("inverseBindMatrices"))
    for anim in out.get("animations", []):
        for sampler in anim.get("samplers", []):
            use_accessor(sampler.get("input"))
            use_accessor(sampler.get("output"))

    new_binary = bytearray()
    new_views = []

    def add_view(data, stride=None, target=None):
        while len(new_binary) % 4 != 0:
            new_binary.append(0)
        view = {"buffer": 0, "byteOffset": len(new_binary), "byteLength": len(data)}
        if stride:
            view["byteStride"] = stride
        if target is not None:
            view["target"] = target
        new_views.append(view)
        new_binary.extend(data)
        return len(new_views) - 1

    for index in sorted(used_accessors):
        acc = out["accessors"][index]
        view_index = acc.get("bufferView")
        if view_index is None:
            continue
        view = out["bufferViews"][view_index]
        element = COMPONENT_SIZES[acc["componentType"]] * TYPE_COMPONENTS[acc["type"]]
        stride = view.get("byteStride") or element
        start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        count = acc.get("count", 0)
        length = (count - 1) * stride + element if count > 0 else 0
        acc["bufferView"] = add_view(binary[start:start + length],
                                     stride if view.get("byteStride") else None,
                                     view.get("target"))
        acc["byteOffset"] = 0

    for image in out.get("images", []):
        if "bufferView" not in image:
            continue
        view = out["bufferViews"][image["bufferView"]]
        start = view.get("byteOffset", 0)
        image["bufferView"] = add_view(binary[start:start + view.get("byteLength", 0)])

    out["bufferViews"] = new_views
    out["buffers"] = [{"byteLength": len(new_binary)}]
    return bytes(new_binary)


if __name__ == "__main__":
    main()
