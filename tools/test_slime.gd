extends SceneTree

# Slime regression test: the hitbox follows the floating body, the slime dives
# from its cruise altitude as it closes in, and its red tier-2 crystals fall.
# Usage: godot --headless --path . --script res://tools/test_slime.gd

var _failures: int = 0


func _initialize() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var player := scene.get("player") as Player
	var waves := scene.get("waves") as WaveManager
	waves.set_process(false)
	waves.set_physics_process(false)
	Enemy.ai_frozen = false
	for enemy in get_nodes_in_group("enemies"):
		enemy.queue_free()
	await process_frame

	print("--- slime hitbox ---")
	var slime := waves.spawn_kind("slime", Vector3(-10.0, 0.05, 16.0)) as Enemy
	slime.behavior.enabled = false
	await create_timer(1.2).timeout
	var collision := slime.get_node("Collision") as CollisionShape3D
	var sphere := collision.shape as SphereShape3D
	_check(sphere.radius >= 1.0, "hitbox is large enough for the body (r=%.2f)" % sphere.radius)
	_check(absf(collision.position.y) < 0.2,
		"hitbox is centred on the flying body, not the floor (y=%.2f)" % collision.position.y)
	var world_centre := slime.global_position + collision.position
	_check(world_centre.y > 3.5, "hitbox rides with the slime at %.1f m" % world_centre.y)
	_check(slime.global_position.y > 3.5, "slime cruises high above the arena (%.1f m)" % slime.global_position.y)
	var cast_from := slime.global_position + Vector3(0.0, 0.0, 4.0)
	var cast_to := slime.global_position + Vector3(0.0, 0.0, -4.0)
	var query := PhysicsRayQueryParameters3D.create(cast_from, cast_to, 4)
	var hit: Dictionary = slime.get_world_3d().direct_space_state.intersect_ray(query)
	_check(hit.get("collider") == slime, "a shot through the floating body hits its hitbox")

	print("--- descent on approach ---")
	player.global_position = Vector3(-8.0, 0.2, 16.0)
	await create_timer(1.2).timeout
	_check(slime.global_position.y < 2.6 and slime.global_position.y > 0.8,
		"slime dives down near the player (%.1f m)" % slime.global_position.y)

	print("--- red tier-2 crystals ---")
	player.global_position = Vector3(0.0, 0.2, 34.0)
	slime.global_position = Vector3(-10.0, 4.0, 16.0)
	slime.take_damage(999.0, slime.global_position + Vector3.UP * 0.6, Vector3.FORWARD)
	await create_timer(0.25).timeout

	var gems := get_nodes_in_group("xp_gems")
	_check(gems.size() == 3, "slime drops three crystals (%d)" % gems.size())
	var all_red := true
	var all_high := true
	var all_falling := true
	for node in gems:
		if float(node.get("xp_value")) <= 8.0 or int(node.get("tier")) < 2:
			all_red = false
		var colour: Color = node.get("gem_color")
		if colour.r < 0.9 or colour.g > 0.3:
			all_red = false
		if node.global_position.y < 1.0:
			all_high = false
		if not bool(node.get("_falling")):
			all_falling = false
	_check(all_red, "crystals are red and worth more XP")
	_check(int(gems[0].get("tier")) == 2 if not gems.is_empty() else false, "crystals are tier 2")
	_check(all_high, "crystals start in the air under the corpse")
	_check(all_falling, "airborne crystals fall instead of hovering")

	await create_timer(2.0).timeout
	var landed := true
	for node in gems:
		if node.global_position.y > 0.4 or bool(node.get("_falling")):
			landed = false
	_check(landed, "crystals land on the floor")

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
