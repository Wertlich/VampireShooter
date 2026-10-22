extends SceneTree

# Dev test: spawns a skeleton through the arena's spawn helper, lets it walk to
# the player, checks that it deals damage, then kills it.
# Usage: godot --headless --path . --script res://tools/test_enemy.gd

func _initialize() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var player := scene.get_node("Player") as Player
	var skeleton: Enemy = scene.call("spawn_skeleton")
	print("spawned at ", skeleton.global_position.snapped(Vector3.ONE * 0.1),
		" player at ", player.global_position.snapped(Vector3.ONE * 0.1))
	print("enemies in group: ", get_nodes_in_group("enemies").size())

	for i in 16:
		await create_timer(0.3).timeout
		if not is_instance_valid(skeleton):
			print("enemy vanished")
			break
		var distance := skeleton.global_position.distance_to(player.global_position)
		print("t=%4.1fs  dist=%5.2f  enemy_hp=%3.0f  player_hp=%5.0f  y=%.2f" % [
			(i + 1) * 0.3, distance, skeleton.health, player.health, skeleton.global_position.y
		])

	if is_instance_valid(skeleton):
		var before := player.health
		skeleton.take_damage(999.0, skeleton.global_position, Vector3.FORWARD)
		print("killed skeleton; player hp %0.0f -> %0.0f" % [before, player.health])
		await create_timer(0.4).timeout
		print("after death: in_group=", skeleton.is_in_group("enemies"),
			" layer=", skeleton.collision_layer,
			" alive_enemies=", get_nodes_in_group("enemies").size())

	await create_timer(2.4).timeout
	print("skeleton freed? ", not is_instance_valid(skeleton))
	quit()
