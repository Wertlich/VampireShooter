extends SceneTree

# Dev test for the enemy roster: HP ladder, per-wave mix, the solo boss wave and
# archer behaviour (keeps distance, shoots arrows, damages the player).
# Usage: godot --headless --path . --script res://tools/test_enemies.gd

var _failures: int = 0


func _initialize() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var waves: WaveManager = scene.get("waves")
	var player: Player = scene.get("player")
	waves.set_process(false)

	print("--- hit points ---")
	var expected := {
		"skeleton": 120.0,
		"zombie": 180.0,
		"slime": 360.0,
		"archer": 180.0,
		"boss": 2520.0,
	}
	for kind in expected:
		var enemy: Enemy = waves.spawn_kind(kind, Vector3(0.0, 0.05, 20.0))
		_check(enemy != null, "%s spawns" % kind)
		if enemy:
			_check(is_equal_approx(enemy.max_health, float(expected[kind])),
				"%s hp = %.0f (got %.0f)" % [kind, expected[kind], enemy.max_health])
			enemy.queue_free()
		await process_frame

	print("--- hp ladder asked for by design ---")
	_check(is_equal_approx(180.0, 120.0 * 1.5), "zombie = 1.5x skeleton")
	_check(is_equal_approx(360.0, 180.0 * 2.0), "slime = 2x zombie")
	_check(is_equal_approx(180.0, 180.0), "archer = zombie hp")
	_check(is_equal_approx(2520.0, 360.0 * 7.0), "boss = 7x slime")

	print("--- wave roster ---")
	var r1 := waves.roster_for(1)
	_check(r1.size() == 1 and int(r1.get("skeleton", 0)) == 5, "wave 1 = 5 skeletons (%s)" % r1)

	var r3 := waves.roster_for(3)
	_check(int(r3.get("zombie", 0)) > 0 and int(r3.get("skeleton", 0)) > 0,
		"wave 3 mixes skeletons and zombies (%s)" % r3)

	var r4 := waves.roster_for(4)
	_check(int(r4.get("archer", 0)) > 0, "wave 4 brings archers (%s)" % r4)

	var r6 := waves.roster_for(6)
	_check(int(r6.get("slime", 0)) > 0, "wave 6 brings slimes (%s)" % r6)

	for index in [3, 4, 6, 9]:
		var roster := waves.roster_for(index)
		var total := 0
		for kind in roster:
			total += int(roster[kind])
		_check(total == waves.wave_size_for(index),
			"wave %d roster sums to wave size %d (got %d)" % [index, waves.wave_size_for(index), total])

	var r10 := waves.roster_for(waves.boss_wave)
	_check(r10.size() == 1 and int(r10.get("boss", 0)) == 1,
		"boss wave is boss only (%s)" % r10)
	_check(waves.build_queue(waves.boss_wave).size() == 1, "boss wave queue holds one enemy")

	print("--- archer behaviour ---")
	var archer: Enemy = waves.spawn_kind("archer", player.global_position + Vector3(0.0, 0.05, -4.0))
	_check(archer.mode == Enemy.Mode.RANGED, "archer uses ranged mode")

	var start := player.global_position.distance_to(player.global_position)
	await create_timer(2.2).timeout
	var distance := archer.global_position.distance_to(player.global_position)
	_check(distance > 5.0, "archer backed away to %.1f m (started at 4.0 m)" % distance)
	_check(start < 0.01, "sanity")

	var saw_arrow := false
	var hp_before := player.health
	for i in 60:
		await create_timer(0.1).timeout
		for node in current_scene.get_children():
			if node is Arrow:
				saw_arrow = true
				break
		if saw_arrow and player.health < hp_before:
			break
	_check(saw_arrow, "archer fired an arrow")
	await create_timer(1.5).timeout
	_check(player.health < hp_before, "arrows damaged the player (%.0f -> %.0f)" % [hp_before, player.health])

	print("--- boss is visibly bigger than a skeleton ---")
	var skeleton: Enemy = waves.spawn_kind("skeleton", Vector3(4.0, 0.05, 24.0))
	var boss: Enemy = waves.spawn_kind("boss", Vector3(-4.0, 0.05, 24.0))
	_check(boss.max_health > skeleton.max_health * 20.0, "boss is far tougher (%.0f vs %.0f)" % [
		boss.max_health, skeleton.max_health])

	var boss_body := boss.get_node("Model/Body") as Node3D
	_check(is_equal_approx(boss_body.scale.x, 0.06075),
		"boss model is 2.5x the base scale (got %.5f)" % boss_body.scale.x)
	var boss_shape := (boss.get_node("Collision") as CollisionShape3D).shape as CapsuleShape3D
	_check(boss_shape.radius > 2.0 and boss_shape.height > 6.0,
		"boss collision grew with it (r=%.2f h=%.2f)" % [boss_shape.radius, boss_shape.height])

	print("--- zombie randomizer ---")
	var models := {}
	var tints := {}
	for i in 12:
		var zombie: Enemy = waves.spawn_kind("zombie", Vector3(0.0, 0.05, 20.0))
		models[_node_count(zombie.get_node("Model/Body"))] = true
		tints[str(zombie.get("_tint"))] = true
		zombie.queue_free()
		await process_frame
	var probe := (waves.get("zombie_scene") as PackedScene).instantiate() as Enemy
	var variant_count := probe.variants.size()
	probe.free()
	_check(variant_count == 4, "zombie scene ships 4 variants (got %d)" % variant_count)
	_check(models.size() >= 2, "zombies use different variant models (%d seen)" % models.size())
	_check(tints.size() >= 2, "zombies get different texture tints (%d seen)" % tints.size())

	print("")
	if _failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _node_count(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _node_count(child)
	return total


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok    ", label)
	else:
		_failures += 1
		print("  FAIL  ", label)
