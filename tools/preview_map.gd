extends SceneTree

# Renders a few views of the castle map: player eye level and an aerial shot.
# Usage: godot --path . --script res://tools/preview_map.gd

var _scene: Node3D
var _player: Player


func _initialize() -> void:
	_scene = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	current_scene = _scene
	await create_timer(1.2).timeout

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots/castle"))

	_player = _scene.get_node("Player") as Player
	_player._yaw = 0.0
	_player._pitch = 0.0
	await create_timer(0.3).timeout
	await _shot("castle_spawn.png")

	# Walk closer to the cathedral.
	_player.global_position = Vector3(0.0, 0.2, 20.0)
	await create_timer(0.4).timeout
	await _shot("castle_cathedral.png")

	# Aerial overview from a temporary camera.
	var camera := Camera3D.new()
	camera.fov = 55.0
	_scene.add_child(camera)
	camera.global_position = Vector3(46.0, 58.0, 62.0)
	await process_frame
	camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	camera.current = true
	await create_timer(0.3).timeout
	await _shot("castle_aerial.png")

	quit()


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://screenshots/castle/") + file_name
	image.save_png(path)
	print("saved ", file_name)
