extends SceneTree

# Renders review shots of the new cemetery map through the real arena scene.
# Usage: godot --path . --script res://tools/preview_cemetery.gd

const OUT_DIR := "res://screenshots/cemetery"


func _initialize() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		push_error("main scene failed to load")
		quit(1)
		return
	var scene := packed.instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var waves := scene.get_node_or_null("WaveManager") as WaveManager
	if waves:
		waves.set_process(false)
		waves.state = WaveManager.State.FINISHED
	var hud := scene.get_node_or_null("HUD") as CanvasLayer
	if hud:
		hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	Settings.apply_quality(2, scene)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var player := scene.get_node("Player") as Player
	await create_timer(2.5).timeout
	# First frames compile the sky/material shaders; burn one frame before the
	# actual review shots so the opening image is not black.
	await _shot("00_warmup.png")
	await create_timer(0.4).timeout

	# Main approach from the south gate.
	player.global_position = Vector3(0, 0.2, 35)
	player._yaw = 0.0
	player._pitch = 0.0
	await create_timer(0.6).timeout
	await _shot("01_spawn.png")

	# Mid-path, graves on both sides.
	player.global_position = Vector3(0, 0.2, 19)
	player._yaw = 0.0
	player._pitch = 0.02
	await create_timer(0.4).timeout
	await _shot("02_graves.png")

	# The intact church facade and entrance lamps.
	player.global_position = Vector3(0, 0.2, 5.5)
	player._yaw = 0.0
	player._pitch = 0.13
	await create_timer(0.4).timeout
	await _shot("03_church.png")

	# Walk inside the nave and look toward the altar.
	player.global_position = Vector3(0, 0.2, -0.3)
	player._yaw = 0.0
	player._pitch = 0.35
	await create_timer(0.4).timeout
	await _shot("04_church_interior.png")

	# The climbable wooden ladder just right of the entrance, seen from the nave.
	player.global_position = Vector3(0.6, 0.2, -3.6)
	player._yaw = deg_to_rad(-134.0)
	player._pitch = 0.18
	await create_timer(0.4).timeout
	await _shot("09_church_ladder.png")

	# The ruined church across the diagonal path.
	player.global_position = Vector3(17, 0.2, -16)
	player._yaw = deg_to_rad(-45.0)
	player._pitch = 0.1
	await create_timer(0.4).timeout
	await _shot("05_ruin.png")

	# Look up at the moon and clouds.
	player.global_position = Vector3(0, 0.2, 25)
	player._yaw = deg_to_rad(-25.0)
	player._pitch = deg_to_rad(32.0)
	await create_timer(0.4).timeout
	await _shot("06_moon.png")

	# South gate and the half-ruined fence.
	player.global_position = Vector3(0, 0.2, 36)
	player._yaw = deg_to_rad(180.0)
	player._pitch = 0.06
	await create_timer(0.4).timeout
	await _shot("07_gate.png")

	# Aerial overview from a temporary camera.
	var camera := Camera3D.new()
	camera.fov = 60.0
	scene.add_child(camera)
	camera.global_position = Vector3(52, 44, 64)
	camera.look_at(Vector3(0, 0, -4), Vector3.UP)
	camera.current = true
	await create_timer(0.4).timeout
	await _shot("11_aerial.png")

	quit()


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT_DIR + "/") + file_name
	var err := image.save_png(path)
	print("saved ", path, " err=", err)
