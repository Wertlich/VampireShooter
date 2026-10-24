extends SceneTree

# Boss regression test: daemonium model, 20 m fire wall and 3 rows of 15 arms.
# Usage: godot --headless --path . --script res://tools/test_boss_attacks.gd

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
	for enemy in get_nodes_in_group("enemies"):
		enemy.queue_free()
	await process_frame

	player.global_position = Vector3(0.0, 0.2, 34.0)
	var boss := waves.spawn_kind("boss", Vector3(0.0, 0.05, 25.0)) as Enemy
	boss.rotation.y = 0.0
	boss.set_physics_process(false)
	var attacks := boss.get_node("Attacks")
	attacks.set_process(false)
	await process_frame

	print("--- daemonium model ---")
	var body := boss.get_node("Model/Body") as Node3D
	var meshes := body.find_children("*", "MeshInstance3D", true, false)
	_check(not meshes.is_empty(), "new boss model contains meshes")
	_check(is_equal_approx(body.scale.x, 0.03), "boss is scaled to arena size (%.3f)" % body.scale.x)

	print("--- fire wall ---")
	var hp_before := player.health
	attacks.cast_fire_wall()
	await create_timer(0.15).timeout
	var walls := get_nodes_in_group("fire_walls")
	_check(walls.size() == 1, "fire wall spawned (%d)" % walls.size())
	if not walls.is_empty():
		_check(is_equal_approx(float(walls[0].get("max_radius")), 20.0), "wall reaches 20 m")
		_check(is_equal_approx(float(walls[0].get("damage")), 30.0), "wall carries its damage")
	await create_timer(1.35).timeout
	_check(player.health < hp_before, "expanding wall hits the player (%.0f -> %.0f)" % [
		hp_before, player.health])

	print("--- three rows of arms ---")
	player.health = player.max_health
	player.global_position = Vector3(0.0, 0.2, 34.0)
	attacks.cast_arms()
	await create_timer(0.25).timeout
	var arms := get_nodes_in_group("boss_arms")
	_check(arms.size() == 45, "three rows of 15 arms spawn (%d)" % arms.size())
	var row_zs := {}
	for node in arms:
		row_zs[roundi((node as Node3D).global_position.z)] = true
	_check(row_zs.size() == 3, "the arms form three distinct rows (%s)" % [row_zs.keys()])
	var hp_arms := player.health
	await create_timer(1.2).timeout
	_check(player.health < hp_arms, "arms damage the player (%.0f -> %.0f)" % [
		hp_arms, player.health])

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
