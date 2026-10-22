extends SceneTree

# Renders one image per mesh surface with only that surface highlighted, so the
# part behind each material slot can be identified by eye.
# Usage: godot --path . --script res://tools/preview_surfaces.gd -- <res path> <out prefix>

var _meshes: Array[MeshInstance3D] = []

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "res://models/akm/source/akm_fit.glb"
	var prefix: String = args[1] if args.size() > 1 else "surf"

	var world := Node3D.new()
	root.add_child(world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.08, 0.1)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.72, 0.8)
	e.ambient_light_energy = 1.4
	env.environment = e
	world.add_child(env)

	var loaded := load(path)
	var model: Node3D = (loaded as PackedScene).instantiate()
	world.add_child(model)
	_collect_meshes(model)

	await process_frame
	await process_frame

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -30, 0)
	light.light_energy = 1.6
	world.add_child(light)

	var box := _total_aabb(model)
	var center := box.get_center()
	var camera := Camera3D.new()
	camera.fov = 40.0
	world.add_child(camera)
	camera.current = true
	var camera_offset := Vector3(1.0, 0.35, 0.0).normalized() * (box.size.length() * 1.25)
	camera.global_position = center + camera_offset
	camera.look_at(center, Vector3.UP)

	var hot := StandardMaterial3D.new()
	hot.albedo_color = Color(1.0, 0.25, 0.05)
	hot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var cold := StandardMaterial3D.new()
	cold.albedo_color = Color(0.16, 0.17, 0.2)
	cold.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots/surfaces"))
	var out_dir := ProjectSettings.globalize_path("res://screenshots/surfaces/")

	for mi in _meshes:
		if mi.mesh == null:
			continue
		print("MESH ", mi.name, " surfaces=", mi.mesh.get_surface_count())
		for s in mi.mesh.get_surface_count():
			for other in _meshes:
				for k in other.mesh.get_surface_count():
					other.set_surface_override_material(k, cold)
			mi.set_surface_override_material(s, hot)
			var mat := mi.mesh.surface_get_material(s)
			var mat_name := mat.resource_name if mat else "<none>"
			var points: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			var lo := Vector3(1e9, 1e9, 1e9)
			var hi := Vector3(-1e9, -1e9, -1e9)
			for p in points:
				for axis in 3:
					lo[axis] = minf(lo[axis], p[axis])
					hi[axis] = maxf(hi[axis], p[axis])
			print("SURF %d mat=%s verts=%d min=%s max=%s" % [
				s, mat_name, points.size(), lo, hi])
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			image.save_png("%s%s_%02d.png" % [out_dir, prefix, s])
	quit()


func _collect_meshes(node: Node) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		_meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child)


func _total_aabb(root_node: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in _meshes:
		var world_box: AABB = mi.global_transform * mi.get_aabb()
		box = world_box if first else box.merge(world_box)
		first = false
	return box
