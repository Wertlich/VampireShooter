extends SceneTree

# Simulates bunny hopping with a strafe to check that air acceleration actually
# builds speed. Usage: godot --headless --path . --script res://tools/test_bhop.gd

func _initialize() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame

	var player := scene.get_node("Player") as Player
	# Long clear lane along +X near the south wall, away from the crate clutter.
	player.global_position = Vector3(-16.0, 0.2, 16.0)
	player._yaw = deg_to_rad(-90.0)
	await create_timer(0.5).timeout
	print("start: speed=%.2f hops=%d" % [player.planar_speed, player.hop_streak])

	# Run first: you cannot bunny hop from a standstill, you carry ground speed.
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await create_timer(1.2).timeout
	print("after run-up: speed=%.2f" % player.planar_speed)

	Input.action_press("move_right")
	Input.action_press("jump")

	var max_speed := 0.0
	for step in 24:
		# Keep turning while strafing: that is what feeds the air acceleration.
		player._yaw += deg_to_rad(4.0)
		await create_timer(0.16).timeout
		max_speed = maxf(max_speed, player.planar_speed)
		print("t=%4.1fs  speed=%5.2f  hops=%2d  grounded=%s  pos=%s" % [
			(step + 1) * 0.16, player.planar_speed, player.hop_streak,
			player.is_on_floor(), player.global_position.snapped(Vector3.ONE * 0.1)
		])

	Input.action_release("jump")
	Input.action_release("move_forward")
	Input.action_release("move_right")
	Input.action_release("sprint")
	await create_timer(1.0).timeout
	print("peak speed: %.2f m/s (walk %.1f, sprint %.1f)" % [max_speed, player.walk_speed, player.sprint_speed])
	quit()
