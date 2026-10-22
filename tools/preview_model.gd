extends SceneTree

# Renders an imported model on a neutral background from an angle, so its
# orientation and scale can be checked without opening the editor.
# Usage: godot --path . --script res://tools/preview_model.gd -- <res path> [out name]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "res://models/shotgun/source/Escopeta doble canon para SP.fbx"
	var out_name: String = args[1] if args.size() > 1 else "preview.png"

	var world := Node3D.new()
	root.add_child(world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.12, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.62, 0.7)
	e.ambient_light_energy = 1.2
	env.environment = e
	world.add_child(env)

	var loaded := load(path)
	var model: Node3D
	if loaded is PackedScene:
		model = (loaded as PackedScene).instantiate()
	elif loaded is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = loaded
		model = mi
	else:
		printerr("unsupported resource: ", loaded)
		quit(1)
		return
	world.add_child(model)

	# Transforms need one frame to propagate before global AABBs are meaningful.
	await process_frame
	await process_frame

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -35, 0)
	light.light_energy = 2.0
	world.add_child(light)

	var light2 := DirectionalLight3D.new()
	light2.rotation_degrees = Vector3(-15, 140, 0)
	light2.light_energy = 0.8
	world.add_child(light2)

	var box := _total_aabb(model)
	print("model aabb position=", box.position, " size=", box.size, " center=", box.get_center())

	var view: String = args[2] if args.size() > 2 else "persp"
	var dir := Vector3(0.8, 0.45, 1.0).normalized()
	match view:
		"front":
			dir = Vector3(0.0, 0.1, 1.0).normalized()
		"back":
			dir = Vector3(0.0, 0.1, -1.0).normalized()
		"left":
			dir = Vector3(-1.0, 0.1, 0.0).normalized()
		"right":
			dir = Vector3(1.0, 0.1, 0.0).normalized()

	var camera := Camera3D.new()
	camera.fov = 45.0
	world.add_child(camera)
	camera.current = true
	var center := box.get_center()
	var distance: float = box.size.length() * 1.35
	camera.global_position = center + dir * distance
	camera.look_at(center, Vector3.UP)

	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	var image := root.get_texture().get_image()
	var out_path := ProjectSettings.globalize_path("res://screenshots/") + out_name
	image.save_png(out_path)
	print("saved ", out_path)
	quit()


func _total_aabb(root_node: Node) -> AABB:
	var box := AABB()
	var first := true
	for node in _meshes(root_node):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var world_box: AABB = mi.global_transform * mi.get_aabb()
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
