extends SceneTree

# Renders one model with four different rotations side by side, so the right
# orientation can be picked from a single screenshot.
# Usage: godot --path . --script res://tools/fit_orientation.gd -- <res path> <out.png> [scale]

const ROTATIONS: Array[Vector3] = [
	Vector3(0, 0, 0),
	Vector3(-90, 0, 0),
	Vector3(0, -90, 0),
	Vector3(-90, -90, 0),
]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0]
	var out_name: String = args[1] if args.size() > 1 else "fit.png"
	var scale: float = float(args[2]) if args.size() > 2 else 0.01

	var world := Node3D.new()
	root.add_child(world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.1, 0.1, 0.12)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.82, 0.9)
	e.ambient_light_energy = 1.4
	env.environment = e
	world.add_child(env)

	var scene: PackedScene = load(path)
	for i in ROTATIONS.size():
		var holder := Node3D.new()
		holder.position = Vector3(-3.0 + i * 2.0, 0.0, 0.0)
		holder.rotation_degrees = ROTATIONS[i]
		holder.scale = Vector3.ONE * scale
		world.add_child(holder)
		var instance := scene.instantiate()
		holder.add_child(instance)
		# Weapon models in this project are rendered with the skin binding
		# cleared, so the same has to happen here.
		_strip_skinning(instance)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -30, 0)
	light.light_energy = 2.0
	world.add_child(light)

	var camera := Camera3D.new()
	camera.fov = 40.0
	camera.near = 0.01
	world.add_child(camera)
	camera.current = true
	camera.global_position = Vector3(0.0, 0.6, 6.5)
	camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)

	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://screenshots/") + out_name)
	print("saved ", out_name, "  order: (0,0,0)  (-90,0,0)  (0,-90,0)  (-90,-90,0)")
	quit()


func _strip_skinning(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).skeleton = NodePath()
	for child in node.get_children():
		_strip_skinning(child)
