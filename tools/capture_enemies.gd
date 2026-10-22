extends SceneTree

# Lines up one of every enemy type in front of the player and saves a frame, so
# scale, facing and materials can be checked in one go.
# Usage: godot --path . --script res://tools/capture_enemies.gd

func _initialize() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(0.8).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var waves: WaveManager = scene.get("waves")
	var player: Player = scene.get("player")
	# Keep the wave spawner out of the shot. Only its own _process is stopped:
	# process_mode would freeze the enemies parented to it as well.
	waves.set_process(false)

	player.global_position = Vector3(0.0, 0.2, 34.0)
	player._yaw = 0.0
	player._pitch = deg_to_rad(-2.0)
	# The models are posed, not fought, so keep the player alive for the shots.
	player.max_health = 100000.0
	player.health = 100000.0

	var kinds := ["skeleton", "zombie", "slime", "archer"]
	var origin := Vector3(0.0, 0.05, 25.0)
	for i in kinds.size():
		var enemy := waves.spawn_kind(kinds[i], origin + Vector3(-6.0 + i * 4.0, 0.0, 0.0))
		print("spawned ", kinds[i], " hp=", enemy.health, " at ", enemy.global_position)

	# Let them rise, then freeze them so the group holds still for the shot.
	await create_timer(1.4).timeout
	for enemy in get_nodes_in_group("enemies"):
		(enemy as Enemy).set_physics_process(false)
	await create_timer(0.4).timeout
	await _save("17_enemies.png")

	# The boss, alone and further back.
	for enemy in get_nodes_in_group("enemies"):
		enemy.queue_free()
	await create_timer(0.3).timeout
	var boss := waves.spawn_kind("boss", Vector3(0.0, 0.05, 22.0))
	print("boss hp=", boss.health)
	await create_timer(2.0).timeout
	boss.set_physics_process(false)
	await create_timer(0.2).timeout
	await _save("18_boss.png")

	# Archers shooting from range.
	for enemy in get_nodes_in_group("enemies"):
		enemy.queue_free()
	await create_timer(0.3).timeout
	for i in 3:
		waves.spawn_kind("archer", Vector3(-6.0 + i * 6.0, 0.05, 22.0))
	await create_timer(3.4).timeout
	await _save("19_archers.png")

	# Close portraits, to judge facing and readability.
	for enemy in get_nodes_in_group("enemies"):
		enemy.queue_free()
	await create_timer(0.3).timeout
	for kind in ["zombie", "boss", "archer"]:
		waves.spawn_kind(kind, Vector3(0.0, 0.05, 29.0))
		await create_timer(1.1).timeout
		for enemy in get_nodes_in_group("enemies"):
			(enemy as Enemy).set_physics_process(false)
		await create_timer(0.2).timeout
		await _save("20_%s_close.png" % kind)
		for enemy in get_nodes_in_group("enemies"):
			enemy.queue_free()
		await create_timer(0.3).timeout

	# A crowd of zombies, to show the model/texture randomizer in action.
	for i in 8:
		waves.spawn_kind("zombie", Vector3(-7.0 + (i % 4) * 4.5, 0.05, 26.0 - (i / 4) * 3.0))
	await create_timer(1.5).timeout
	for enemy in get_nodes_in_group("enemies"):
		(enemy as Enemy).set_physics_process(false)
	await create_timer(0.2).timeout
	await _save("23_zombie_crowd.png")
	quit()


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("res://screenshots/") + file_name)
	print("saved ", file_name)
