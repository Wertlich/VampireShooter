extends SceneTree

# Measures an enemy model: how tall it really is (skinned meshes report bogus
# AABBs, so the skeleton bones are used), how many meshes it has, and which
# animations it ships.
# Usage: godot --headless --path . --script res://tools/measure_enemy.gd -- <res path>

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "res://models/vrag v2/zombie_a.glb"

	var model: Node3D = (load(path) as PackedScene).instantiate()
	root.add_child(model)
	await process_frame
	await process_frame

	var meshes: Array[Node] = []
	var skeletons: Array[Node] = []
	var players: Array[Node] = []
	_collect(model, meshes, skeletons, players)

	print("model: ", path)
	print("  meshes: ", meshes.size(), "  skeletons: ", skeletons.size(), "  animation players: ", players.size())

	for mi in meshes:
		var node := mi as MeshInstance3D
		print("   mesh %-28s surfaces=%d center=%s size=%s" % [
			node.name, node.mesh.get_surface_count() if node.mesh else 0,
			node.mesh.get_aabb().get_center() if node.mesh else Vector3.ZERO,
			node.mesh.get_aabb().size if node.mesh else Vector3.ZERO])

	for sk in skeletons:
		var skeleton := sk as Skeleton3D
		var lo := Vector3(1e9, 1e9, 1e9)
		var hi := Vector3(-1e9, -1e9, -1e9)
		for i in skeleton.get_bone_count():
			var p: Vector3 = skeleton.global_transform * skeleton.get_bone_global_rest(i).origin
			for axis in 3:
				lo[axis] = minf(lo[axis], p[axis])
				hi[axis] = maxf(hi[axis], p[axis])
		print("   skeleton %s bones=%d  rest height=%.2f m  foot y=%.2f  head y=%.2f" % [
			skeleton.name, skeleton.get_bone_count(), hi.y - lo.y, lo.y, hi.y])
		print("   bone bounds  min=(%.2f, %.2f, %.2f)  max=(%.2f, %.2f, %.2f)" % [
			lo.x, lo.y, lo.z, hi.x, hi.y, hi.z])

	for player in players:
		var ap := player as AnimationPlayer
		for name in ap.get_animation_list():
			var anim := ap.get_animation(name)
			print("   anim %-28s %.2fs" % [name, anim.length])

	if meshes.is_empty():
		var lo2 := Vector3(1e9, 1e9, 1e9)
		var hi2 := Vector3(-1e9, -1e9, -1e9)
		for mi in _all_meshes(model):
			var box: AABB = (mi as MeshInstance3D).get_aabb()
			var world: AABB = (mi as MeshInstance3D).global_transform * box
			lo2 = lo2.min(world.position)
			hi2 = hi2.max(world.position + world.size)
		print("   static size: ", hi2 - lo2)
	quit()


func _collect(node: Node, meshes: Array[Node], skeletons: Array[Node], players: Array[Node]) -> void:
	if node is MeshInstance3D:
		meshes.append(node)
	if node is Skeleton3D:
		skeletons.append(node)
	if node is AnimationPlayer:
		players.append(node)
	for child in node.get_children():
		_collect(child, meshes, skeletons, players)


func _all_meshes(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_all_meshes(child))
	return found
