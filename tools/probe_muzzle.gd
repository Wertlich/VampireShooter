extends SceneTree

# Finds the muzzle point of an imported gun mesh. Vertices are split by
# material surface, so the metal end (barrels) can be told apart from the
# wooden end (stock).
# Usage: godot --headless --path . --script res://tools/probe_muzzle.gd -- <res path>

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "res://models/shotgun/source/Escopeta doble canon para SP.fbx"
	var packed := load(path) as PackedScene
	var model := packed.instantiate() as Node3D
	root.add_child(model)
	await process_frame

	for mi in _meshes(model):
		var mesh: Mesh = mi.mesh
		print("mesh ", mi.name, " surfaces=", mesh.get_surface_count(), " transform=", mi.transform)
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var mat := mesh.surface_get_material(s)
			var verts: Array[Vector3] = []
			var zmin := INF
			var zmax := -INF
			for v in arrays[Mesh.ARRAY_VERTEX]:
				var p: Vector3 = mi.transform * (v as Vector3)
				verts.append(p)
				zmin = minf(zmin, p.z)
				zmax = maxf(zmax, p.z)
			var cmin := _centroid_near(verts, zmin, 0.02)
			var cmax := _centroid_near(verts, zmax, 0.02)
			print("  surface ", s, " mat=", mat.resource_name if mat else "null",
				" z=", zmin, "..", zmax)
			print("     low-z face centroid=", cmin, "  high-z face centroid=", cmax)
	quit()


func _centroid_near(verts: Array[Vector3], z: float, eps: float) -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for p in verts:
		if absf(p.z - z) <= eps:
			sum += p
			count += 1
	return sum / float(maxi(count, 1)) if count > 0 else Vector3.ZERO


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_meshes(child))
	return found
