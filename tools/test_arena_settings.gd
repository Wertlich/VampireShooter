extends SceneTree

# Dev test for the arena guard rails and the settings: invisible walls, the
# rescue of escaped enemies and players, audio/video/quality application and the
# pause menu.
# Usage: godot --headless --path . --script res://tools/test_arena_settings.gd

var _failures: int = 0


func _initialize() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var waves: WaveManager = scene.get("waves")
	var player: Player = scene.get("player")
	var bounds: ArenaBounds = scene.get_node("ArenaBounds") as ArenaBounds
	waves.set_process(false)
	await process_frame

	print("--- arena walls ---")
	_check(bounds != null, "ArenaBounds node exists")
	_check(bounds.wall_count() == 4, "four invisible walls (%d)" % bounds.wall_count())
	_check(bounds.half_size >= 45.0, "walls sit at the arena edge (±%.0f m)" % bounds.half_size)

	print("--- escaped enemies ---")
	var escapers: Array[Enemy] = []
	for position in [Vector3(200, 0, 0), Vector3(0, 0, -200), Vector3(0, -60, 0)]:
		var enemy: Enemy = waves.spawn_kind("skeleton", position)
		enemy.set_physics_process(false)
		escapers.append(enemy)
	await process_frame
	bounds.force_check()
	for enemy in escapers:
		var local := enemy.global_position
		_check(absf(local.x) < 6.0 and absf(local.z) < 6.0,
			"enemy rescued to the middle (%.1f, %.1f)" % [local.x, local.z])

	print("--- escaped player ---")
	var respawn := player.global_position
	player.global_position = Vector3(300, 0, 0)
	player.velocity = Vector3(100, 0, 100)
	bounds.force_check()
	_check(player.global_position.distance_to(respawn) < 0.5,
		"player outside is teleported back (%.1f, %.1f)" % [player.global_position.x, player.global_position.z])
	_check(player.velocity.length() < 0.1, "velocity cleared on respawn")

	player.global_position = Vector3(0, -40, 0)
	bounds.force_check()
	_check(player.global_position.distance_to(respawn) < 0.5, "player under the map is teleported back")
	_check(not bounds.is_outside(player.global_position), "respawn point counts as inside")

	print("--- audio settings ---")
	Settings.apply_audio(0.5)
	var bus := AudioServer.get_bus_index("Master")
	_check(absf(AudioServer.get_bus_volume_db(bus) - linear_to_db(0.5)) < 0.5,
		"half volume is about -6 dB (%.1f)" % AudioServer.get_bus_volume_db(bus))
	_check(not AudioServer.is_bus_mute(bus), "bus is not muted at 50%")
	Settings.apply_audio(0.0)
	_check(AudioServer.is_bus_mute(bus), "zero volume mutes the master bus")
	Settings.apply_audio(0.8)

	print("--- video settings ---")
	Settings.resolution = Vector2i(1920, 1080)
	Settings.fullscreen = false
	Settings.vsync = false
	Settings.apply_video()
	_check(true, "apply_video survives the headless display server")

	print("--- quality preset ---")
	Settings.apply_quality(0, scene)
	var viewport := scene.get_viewport()
	_check(viewport.msaa_3d == Viewport.MSAA_DISABLED, "low: MSAA off")
	_check(is_equal_approx(viewport.scaling_3d_scale, 0.75), "low: render scale 0.75")
	Settings.apply_quality(2, scene)
	_check(viewport.msaa_3d == Viewport.MSAA_4X, "high: MSAA 4x")
	_check(is_equal_approx(viewport.scaling_3d_scale, 1.0), "high: full render scale")
	var env := (scene.get_node("WorldEnvironment") as WorldEnvironment).environment
	Settings.apply_quality(0, scene)
	_check(not env.ssao_enabled and not env.glow_enabled, "low: SSAO and glow off")
	Settings.apply_quality(1, scene)
	_check(env.ssao_enabled and env.glow_enabled, "medium: SSAO and glow on")

	print("--- settings persist ---")
	Settings.master_volume = 0.35
	Settings.resolution = Vector2i(1280, 720)
	Settings.quality = 1
	Settings.fullscreen = true
	Settings.vsync = false
	Settings.save()
	Settings.master_volume = 0.9
	Settings.resolution = Vector2i(2560, 1440)
	Settings.quality = 2
	Settings.fullscreen = false
	Settings.vsync = true
	Settings.load_all()
	_check(is_equal_approx(Settings.master_volume, 0.35), "volume remembered (%.2f)" % Settings.master_volume)
	_check(Settings.resolution == Vector2i(1280, 720), "resolution remembered (%s)" % Settings.resolution)
	_check(Settings.quality == 1, "quality remembered (%d)" % Settings.quality)
	_check(Settings.fullscreen, "fullscreen remembered")
	_check(not Settings.vsync, "vsync remembered")

	print("--- pause menu ---")
	var menu: PauseMenu = scene.get_node("PauseMenu") as PauseMenu
	_check(menu != null, "PauseMenu node exists")
	var buttons := _button_texts(menu)
	_check("Продолжить" in buttons, "menu has a resume button")
	_check("Выход" in buttons, "menu has a quit button")
	menu.open()
	_check(menu.visible and paused, "Esc menu pauses the game")
	menu.close()
	_check(not menu.visible and not paused, "closing the menu resumes")

	if paused:
		paused = false

	# The test wrote real user settings; drop them so the game starts on its
	# built-in defaults.
	var config_path := ProjectSettings.globalize_path(Settings.CONFIG_PATH)
	if FileAccess.file_exists(config_path):
		DirAccess.remove_absolute(config_path)

	print("")
	if _failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok    ", label)
	else:
		_failures += 1
		print("  FAIL  ", label)


func _button_texts(node: Node) -> Array[String]:
	var texts: Array[String] = []
	if node is Button:
		texts.append((node as Button).text)
	for child in node.get_children():
		texts.append_array(_button_texts(child))
	return texts
