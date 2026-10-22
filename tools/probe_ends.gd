extends SceneTree

# Finds which end of a gun is the muzzle by comparing the cross-section of both
# ends along the longest axis. The muzzle end is the thin one.
# Usage: godot --headless --path . --script res://tools/probe_ends.gd -- <res path>

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0]
	var packed := load(path) as PackedScene
	var node := packed.instantiate() as Node3D
	root.add_child(node)
	await process_frame

	var verts: Array[Vector3] = []
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			for v in arrays[Mesh.ARRAY_VERTEX]:
				verts.append((mi as MeshInstance3D).global_transform * (v as Vector3))

	var mins := Vector3(1e9, 1e9, 1e9)
	var maxs := Vector3(-1e9, -1e9, -1e9)
	for v in verts:
		mins = mins.min(v)
		maxs = maxs.max(v)
	var size := maxs - mins
	print("verts=", verts.size(), " size=", size, " center=", (mins + maxs) * 0.5)

	# Longest axis: 0 = X, 1 = Y, 2 = Z.
	var axis := 0
	if size.y > size[axis]:
		axis = 1
	if size.z > size[axis]:
		axis = 2

	var slab := size[axis] * 0.12
	for end in ["min", "max"]:
		var limit := mins[axis] + slab if end == "min" else maxs[axis] - slab
		var lo := Vector3(1e9, 1e9, 1e9)
		var hi := Vector3(-1e9, -1e9, -1e9)
		var count := 0
		var sum := Vector3.ZERO
		for v in verts:
			var inside := v[axis] <= limit if end == "min" else v[axis] >= limit
			if not inside:
				continue
			count += 1
			sum += v
			lo = lo.min(v)
			hi = hi.max(v)
		var cross := hi - lo
		print("%s end (axis %d): verts=%d cross=(%.2f, %.2f, %.2f) centroid=%s" % [
			end, axis, count, cross.x, cross.y, cross.z,
			(sum / maxf(count, 1.0)).snapped(Vector3.ONE * 0.01)])
	quit()
