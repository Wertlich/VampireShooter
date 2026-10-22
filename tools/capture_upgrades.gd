extends SceneTree

# Saves the level-up menu with the health card in hand, and the god-mode HUD.
# Usage: godot --path . --script res://tools/capture_upgrades.gd

func _initialize() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(0.9).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var waves: WaveManager = scene.get("waves")
	var player: Player = scene.get("player")
	var menu: LevelUpMenu = scene.get("level_menu")
	waves.set_process(false)

	# A card set that always includes the health upgrade.
	var cards: Array = [scene.call("_health_card")]
	for card in scene.call("_build_cards"):
		if cards.size() >= 3:
			break
		cards.append(card)
	menu.open(cards, player.level)
	await create_timer(0.4).timeout
	await _save("24_health_card.png")
	menu.close()
	await create_timer(0.2).timeout

	# God mode: type the code for real, then show the HUD tag.
	for code in Player.CHEAT_CODE:
		var key := InputEventKey.new()
		key.physical_keycode = code
		key.pressed = true
		Input.parse_input_event(key)
		await process_frame
	print("god mode: ", player.god_mode)
	await create_timer(0.4).timeout
	await _save("25_god_mode.png")
	quit()


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("res://screenshots/") + file_name)
	print("saved ", file_name)
