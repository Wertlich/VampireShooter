extends SceneTree

# Renders a model's first animation at a few timestamps and prints the clip
# names, so a pack's single baked "Take 001" can be judged at a glance.
# Usage: godot --path . --script res://tools/preview_anim.gd -- <res path> <out prefix> [times csv]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "res://models/vrag v2/zombie_a.glb"
	var prefix: String = args[1] if args.size() > 1 else "anim"
	var times: Array = [0.05, 1.0, 2.5, 4.0, 6.0]
	if args.size() > 2:
		times.clear()
		for piece in args[2].split(","):
			times.append(float(piece))

	var world := Node3D.new()
	root.add_child(world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.09, 0.11)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.85)
	e.ambient_light_energy = 1.5
	env.environment = e
	world.add_child(env)

	var model: Node3D = (load(path) as PackedScene).instantiate()
	world.add_child(model)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -35, 0)
	light.light_energy = 2.2
	world.add_child(light)

	var player := _find_anim(model, "")
	if player:
		print("animations: ", player.get_animation_list())
		for name in player.get_animation_list():
			var anim := player.get_animation(name)
			print("   %s  length=%.2fs loop=%d" % [name, anim.length, anim.loop_mode])

	await process_frame
	await process_frame

	var box := _model_bounds(model)
	var center := box.get_center()
	var camera := Camera3D.new()
	camera.fov = 45.0
	camera.near = 0.01
	world.add_child(camera)
	camera.current = true
	camera.global_position = center + Vector3(0.7, 0.25, 1.0).normalized() * (maxf(box.size.length(), 0.5) * 1.35)
	camera.look_at(center, Vector3.UP)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots/anim"))
	for i in times.size():
		if player:
			player.stop()
			player.play(player.get_animation_list()[0] if player.get_animation_list().size() > 0 else "")
			player.seek(float(times[i]), true)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var out := ProjectSettings.globalize_path("res://screenshots/anim/") + "%s_%02d.png" % [prefix, i]
		root.get_texture().get_image().save_png(out)
		print("saved ", out, "  t=", times[i])
	quit()


func _find_anim(node: Node, _unused: String) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_anim(child, _unused)
		if found:
			return found
	return null


func _model_bounds(root_node: Node) -> AABB:
	"""Skinned meshes report a useless AABB, so bones are used when available."""
	var skeleton: Skeleton3D = null
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Skeleton3D:
			skeleton = node
			break
		stack.append_array(node.get_children())

	if skeleton:
		var lo := Vector3(1e9, 1e9, 1e9)
		var hi := Vector3(-1e9, -1e9, -1e9)
		for i in skeleton.get_bone_count():
			var p: Vector3 = skeleton.global_transform * skeleton.get_bone_global_rest(i).origin
			for axis in 3:
				lo[axis] = minf(lo[axis], p[axis])
				hi[axis] = maxf(hi[axis], p[axis])
		return AABB(lo, hi - lo)

	return _total_aabb(root_node)


func _total_aabb(root_node: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in _meshes(root_node):
		var world_box: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = world_box if first else box.merge(world_box)
		first = false
	return box


func _meshes(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_meshes(child))
	return found
