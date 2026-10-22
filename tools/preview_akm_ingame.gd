extends SceneTree

# Renders the AKM in the real in-game view model (own SubViewport, own lights),
# which is where its materials actually have to read well.
# Usage: godot --path . --script res://tools/preview_akm_ingame.gd

func _initialize() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(1.2).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var player: Node = scene.get_node("Player")
	var viewmodel: Node = player.get("viewmodel")
	viewmodel.unlock(2)
	player.call("switch_to", 2)
	await create_timer(1.0).timeout
	await _save("akm_ingame_hip.png")

	Input.action_press("aim")
	await create_timer(0.6).timeout
	await _save("akm_ingame_aim.png")
	Input.action_release("aim")

	await create_timer(0.4).timeout
	var weapon: Node = player.get("weapon")
	if weapon:
		var real_flash: float = weapon.get("flash_duration")
		weapon.set("flash_duration", 1.2)
		weapon.call("pull_trigger")
		await create_timer(0.05).timeout
		await _save("akm_ingame_fire.png")
		weapon.call("hide_flash")
		weapon.set("flash_duration", real_flash)

	await create_timer(0.3).timeout
	quit()


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://screenshots/") + file_name
	var err := image.save_png(path)
	if err != OK:
		push_error("Could not save screenshot %s (error %d)" % [path, err])
	else:
		print("saved ", path)
