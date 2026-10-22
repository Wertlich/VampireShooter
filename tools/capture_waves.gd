extends SceneTree

# Saves documentation shots: the first wave, the break countdown, a mixed wave,
# the boss wave and the death screen.
# Usage: godot --path . --script res://tools/capture_waves.gd

func _initialize() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(0.8).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var waves: WaveManager = scene.get("waves")
	var player: Player = scene.get("player")
	waves.first_wave_delay = 0.6
	# Keep the level-up cards out of the shots.
	player.xp_to_next = 1.0e9
	# The waves are fought for real here, but the camera should survive to the
	# last frame; the death screen sets its own health back to normal.
	player.max_health = 100000.0
	player.health = 100000.0

	print("waiting for wave 1 ...")
	var elapsed := 0.0
	while waves.wave_index < 1 and elapsed < 8.0:
		await create_timer(0.1).timeout
		elapsed += 0.1
	# Let the skeletons rise out of the floor before the shot.
	await create_timer(2.6).timeout
	print("wave ", waves.wave_index, " alive ", waves.alive_count())
	await _save("14_wave.png")

	print("break ...")
	for enemy in get_nodes_in_group("enemies"):
		(enemy as Enemy).take_damage(9999.0, enemy.global_position + Vector3.UP * 1.7, Vector3.FORWARD)
	await create_timer(0.6).timeout
	await _save("15_wave_break.png")

	print("mixed wave ...")
	_clear_enemies()
	waves.call("_start_wave", 4)
	await create_timer(3.0).timeout
	print("mixed alive ", waves.alive_count())
	await _save("21_wave_mixed.png")

	print("late wave ...")
	_clear_enemies()
	waves.call("_start_wave", 9)
	await create_timer(4.6).timeout
	print("late alive ", waves.alive_count())
	await _save("26_wave_late.png")

	print("boss wave ...")
	_clear_enemies()
	# The boss hits hard and the player just walked out of a mixed wave, so give
	# them room to breathe for the shot.
	player.max_health = 100000.0
	player.health = 100000.0
	player.global_position = Vector3(0.0, 0.2, 34.0)
	waves.call("_start_wave", waves.boss_wave)
	await create_timer(2.0).timeout
	# The wave spawns the boss at a random angle and it starts walking at once;
	# park it in front of the camera and freeze it for the shot.
	for enemy in get_nodes_in_group("enemies"):
		var boss := enemy as Enemy
		boss.set_physics_process(false)
		boss.global_position = Vector3(0.0, 0.05, 21.5)
		boss.rotation.y = 0.0
	await create_timer(0.3).timeout
	print("boss wave alive ", waves.alive_count())
	await _save("22_boss_wave.png")

	print("death ...")
	player.max_health = 100.0
	player.health = 100.0
	player.take_damage(1000.0)
	await create_timer(2.0).timeout
	await _save("16_death.png")
	quit()


func _clear_enemies() -> void:
	for enemy in get_nodes_in_group("enemies"):
		enemy.queue_free()


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("res://screenshots/") + file_name)
	print("saved ", file_name)
