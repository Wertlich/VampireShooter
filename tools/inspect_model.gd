extends SceneTree

# Small headless helper: dumps the node tree, transforms and mesh AABBs of an
# imported model so the weapon can be positioned correctly in first person.
# Usage:
#   godot --headless --path . --script res://tools/inspect_model.gd -- <res path>

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path := args[0] if args.size() > 0 else "res://models/revolver/source/Revolver_44.fbx"
	print("=== INSPECT ", path, " ===")
	var ps := ResourceLoader.load(path)
	print("LOADED: ", ps, " (", ps.get_class() if ps else "null", ")")
	if ps is PackedScene:
		var root: Node = ps.instantiate()
		_dump(root, 0)
		root.free()
	quit()


func _dump(node: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	var line := pad + "- " + node.name + " [" + node.get_class() + "]"
	if node is Node3D:
		line += " pos=" + str(node.position) + " rot=" + str(node.rotation_degrees) + " scale=" + str(node.scale)
	print(line)
	if node is MeshInstance3D and node.mesh:
		var aabb: AABB = node.mesh.get_aabb()
		print(pad, "    aabb pos=", aabb.position, " size=", aabb.size, " surfaces=", node.mesh.get_surface_count())
		for i in node.mesh.get_surface_count():
			var mat: Material = node.get_active_material(i)
			print(pad, "    surface ", i, " mat=", mat)
	if node is Skeleton3D:
		print(pad, "    bones=", node.get_bone_count())
	for child in node.get_children():
		_dump(child, depth + 1)
