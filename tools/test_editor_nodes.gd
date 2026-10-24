extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var arena: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await process_frame
	var waves: WaveManager = arena.get_node("WaveManager")
	var composition := WaveComposition.new()
	composition.wave = 3
	composition.skeleton = 0.0
	composition.archer = 1.0
	waves.compositions = [composition]
	assert(waves.roster_for(3) == {"archer": 15})
	assert(waves.roster_for(waves.boss_wave) == {"boss": 1})
	var enemy := waves.spawn_kind("skeleton", Vector3(10, 0.1, 10))
	assert(enemy.behavior != null)
	enemy.behavior.enabled = false
	enemy.behavior.tick(enemy, Vector3.RIGHT, 3.0, 1.0)
	assert(enemy.velocity.x == 0.0 and enemy.behavior.current_state == &"Idle")
	enemy.behavior.enabled = true
	enemy.behavior.attacks_enabled = false
	assert(not enemy._player_alive())
	enemy.behavior.movement_enabled = false
	enemy.behavior.tick(enemy, Vector3.RIGHT, 10.0, 1.0)
	assert(enemy.velocity.x == 0.0)
	var castle := load("res://scenes/castle.tscn").instantiate() as Castle
	var light_count := castle.get_node("Lights").get_child_count()
	assert(light_count > 0)
	assert(castle.get_node("MapCollision").get_child_count() > 0)
	root.add_child(castle)
	assert(castle.get_node("Lights").get_child_count() == light_count)
	assert(castle._lights.size() == light_count)
	castle.queue_free()
	arena.queue_free()
	await process_frame
	print("ALL CHECKS PASSED")
	quit()
