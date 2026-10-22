extends SceneTree

# Saves the pause/settings menu, opened the same way the player opens it: Esc.
# Usage: godot --path . --script res://tools/capture_menu.gd

func _initialize() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(0.9).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var waves: WaveManager = scene.get("waves")
	waves.set_process(false)

	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	await create_timer(0.4).timeout

	var menu: PauseMenu = scene.get_node("PauseMenu") as PauseMenu
	print("pause menu visible: ", menu.visible, " paused: ", paused)
	await _save("27_pause_menu.png")

	# And the low preset, to see what the quality switch does to the scene.
	menu.close()
	await create_timer(0.3).timeout
	Settings.apply_quality(0, scene)
	await create_timer(0.4).timeout
	await _save("28_quality_low.png")
	Settings.apply_quality(2, scene)
	quit()


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("res://screenshots/") + file_name)
	print("saved ", file_name)
