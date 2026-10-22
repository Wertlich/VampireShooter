extends SceneTree

# Renders a weapon scene with a grid of candidate orientations, so the one that
# points the barrel away from the camera can be picked from one screenshot.
# Usage: godot --path . --script res://tools/fit_weapon_grid.gd -- <weapon scene> <out.png>

const CANDIDATES: Array[Vector3] = [
	Vector3(0, 0, 0),
	Vector3(-90, 0, 0),
	Vector3(90, 0, 0),
	Vector3(180, 0, 0),
	Vector3(0, 90, 0),
	Vector3(0, 180, 0),
	Vector3(0, 270, 0),
	Vector3(-90, 0, 90),
	Vector3(-90, 0, 270),
	Vector3(90, 0, 90),
	Vector3(90, 0, 270),
	Vector3(0, 90, 90),
]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0]
	var out_name: String = args[1] if args.size() > 1 else "grid.png"

	var world := Node3D.new()
	root.add_child(world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.1, 0.1, 0.12)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.87, 0.95)
	e.ambient_light_energy = 1.6
	env.environment = e
	world.add_child(env)

	var scene: PackedScene = load(path)
	for i in CANDIDATES.size():
		var weapon := scene.instantiate() as Node3D
		world.add_child(weapon)
		weapon.position = Vector3(-6.0 + i * 1.1, 0.0, 0.0)
		var model := weapon.get_node_or_null("Model") as Node3D
		if model:
			model.rotation_degrees = CANDIDATES[i]
		# Keep only the mesh visible in the grid.
		for node in weapon.get_children():
			if node is Marker3D or node is MeshInstance3D or node is AudioStreamPlayer:
				node.queue_free()
		weapon.set_process(false)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = 2.2
	world.add_child(light)

	var camera := Camera3D.new()
	camera.fov = 45.0
	camera.near = 0.01
	world.add_child(camera)
	camera.current = true
	camera.global_position = Vector3(0.0, 0.9, 9.0)
	camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)

	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://screenshots/") + out_name)
	var names := []
	for c in CANDIDATES:
		names.append("(%d,%d,%d)" % [c.x, c.y, c.z])
	print("saved ", out_name)
	print("order: ", ", ".join(names))
	quit()
