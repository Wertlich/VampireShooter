extends SceneTree

# Prints the albedo/metallic/roughness of every material found in an imported scene.
# Usage: godot --headless --path . --script res://tools/inspect_material.gd -- <res path>

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path := args[0] if args.size() > 0 else "res://models/revolver/source/Revolver_44.fbx"
	var ps := ResourceLoader.load(path) as PackedScene
	if ps == null:
		print("NOT A PACKED SCENE")
		quit()
		return
	var root: Node = ps.instantiate()
	var seen := {}
	_collect(root, seen)
	for key in seen.keys():
		var m: StandardMaterial3D = seen[key]
		print("MAT ", key, " albedo=", m.albedo_texture, " metallic=", m.metallic, " rough=", m.roughness, " metallic_tex=", m.metallic_texture, " rough_tex=", m.roughness_texture)
	root.free()
	quit()


func _collect(node: Node, seen: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh:
		for i in node.mesh.get_surface_count():
			var m: Material = node.mesh.surface_get_material(i)
			if m:
				seen[str(m.resource_name)] = m
	for c in node.get_children():
		_collect(c, seen)
