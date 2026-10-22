extends SceneTree

# Dev test: checks the wave pacing (sizes, break, clearing) and that the player
# actually dies at 0 HP and the run-over screen takes over.
# Usage: godot --headless --path . --script res://tools/test_waves.gd

var _failures: int = 0


func _initialize() -> void:
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var waves: WaveManager = scene.get("waves")
	var player: Player = scene.get("player")
	var run_over: RunOver = scene.get("run_over")

	print("--- manual spawn removed ---")
	_check(not InputMap.has_action("spawn_enemy"), "spawn_enemy action is gone")

	print("--- wave curve (+5 per wave) ---")
	var expected := [5, 10, 15, 20, 25, 30, 35, 40, 45, 50]
	for i in expected.size():
		var got := waves.wave_size_for(i + 1)
		_check(got == expected[i], "wave %d size = %d (expected %d)" % [i + 1, got, expected[i]])
	_check(waves.waves_per_map == 10, "10 waves per map (got %d)" % waves.waves_per_map)
	_check(is_equal_approx(waves.break_seconds, 10.0), "10 s break (got %.1f)" % waves.break_seconds)

	# Speed the pacing up for the test; the logic is the same.
	waves.first_wave_delay = 0.2
	waves.break_seconds = 0.3
	waves.spawn_ticks = 2
	waves.spawn_tick_seconds = 0.02

	print("--- wave 1 ---")
	waves.begin()
	await _wait_for(func() -> bool: return waves.state == WaveManager.State.FIGHTING, 6.0)
	_check(waves.wave_index == 1, "wave 1 started (got %d)" % waves.wave_index)
	_check(waves.wave_size == 5, "wave 1 is 5 skeletons (got %d)" % waves.wave_size)
	_check(waves.alive_count() == 5, "5 skeletons alive (got %d)" % waves.alive_count())

	print("--- clearing wave 1 ---")
	for enemy in get_nodes_in_group("enemies"):
		var skeleton := enemy as Enemy
		skeleton.take_damage(9999.0, skeleton.global_position + Vector3.UP * 1.7, Vector3.FORWARD)
	await process_frame
	_check(waves.alive_count() == 0, "arena empty after the kill (got %d)" % waves.alive_count())
	await _wait_for(func() -> bool: return waves.state == WaveManager.State.BREAK, 3.0)
	_check(waves.state == WaveManager.State.BREAK, "wave 1 cleared -> break")
	_check(waves.break_left > 0.0, "break timer running (%.2f s)" % waves.break_left)

	print("--- wave 2 ---")
	var started := await _wait_for(
		func() -> bool: return waves.state == WaveManager.State.FIGHTING and waves.wave_index == 2, 6.0)
	_check(started, "wave 2 started")
	_check(waves.wave_size == 10, "wave 2 is 10 skeletons (got %d)" % waves.wave_size)
	_check(waves.alive_count() == 10, "10 skeletons alive (got %d)" % waves.alive_count())
	_check(waves.kills == 5, "kill counter = 5 (got %d)" % waves.kills)

	print("--- health card ---")
	var max_before := player.max_health
	var health_card: Dictionary = {}
	for attempt in 80:
		for card in scene.call("_build_cards"):
			if String(card.get("kind", "")) == "player":
				health_card = card
				break
		if not health_card.is_empty():
			break
	_check(not health_card.is_empty(), "health card shows up in the level-up pool")
	if not health_card.is_empty():
		scene.call("_apply_card", health_card)
		_check(is_equal_approx(player.max_health, max_before * 1.25),
			"health card raises max hp %.0f -> %.0f" % [max_before, player.max_health])
		_check(is_equal_approx(player.health, player.max_health), "health card heals to full")

	print("--- dual mp9 card ---")
	var viewmodel: Viewmodel = player.viewmodel
	viewmodel.unlock(6)
	var mp9: Weapon = viewmodel.weapons[6]
	var ammo_before := mp9.max_ammo
	var dual_card: Dictionary = {}
	for card in scene.call("_build_cards"):
		if String(card.get("stat", "")) == "dual":
			dual_card = card
			break
	_check(not dual_card.is_empty(), "akimbo card is guaranteed once the MP9 is unlocked")
	if not dual_card.is_empty():
		scene.call("_apply_card", dual_card)
		_check(mp9.is_dual(), "the card puts a second MP9 in the left hand")
		_check(mp9.max_ammo == ammo_before * 2,
			"akimbo doubles the magazine (%d -> %d)" % [ammo_before, mp9.max_ammo])

	print("--- cheat code ---")
	await _type_cheat(player)
	_check(player.god_mode, "konami code on the arrow keys toggles god mode")
	_check(player.one_shot_kill, "the same code turns on one-shot kills")

	var boss: Enemy = waves.spawn_kind("boss", player.global_position + Vector3(0.0, 0.05, -7.0))
	boss.set_physics_process(false)
	await process_frame
	# Give the physics server a frame to register the new collider, otherwise the
	# hitscan sometimes runs before the boss can be hit.
	await physics_frame
	await physics_frame
	var gun := player.weapon
	gun.ammo = gun.max_ammo
	gun.pull_trigger()
	await process_frame
	_check(boss.health <= 0.0, "one revolver shot kills the boss (hp %.0f)" % boss.health)

	# God mode turns on with a full heal, so wound the player again before the
	# damage check to prove nothing gets through.
	player.health = 40.0
	player.take_damage(999.0)
	_check(not player.is_dead and is_equal_approx(player.health, 40.0),
		"god mode ignores damage (hp %.0f, dead %s)" % [player.health, player.is_dead])
	await _type_cheat(player)
	_check(not player.god_mode, "the same code turns god mode off again")
	_check(not player.one_shot_kill, "and turns one-shot kills off")

	print("--- gather key ---")
	var gathered: Array[Enemy] = []
	for i in 3:
		var enemy: Enemy = waves.spawn_kind(
			"skeleton", player.global_position + Vector3(28.0 + i * 3.0, 0.05, 0.0))
		enemy.set_physics_process(false)
		gathered.append(enemy)
	await process_frame
	var backslash := InputEventKey.new()
	backslash.keycode = KEY_BACKSLASH
	backslash.physical_keycode = KEY_BACKSLASH
	backslash.pressed = true
	Input.parse_input_event(backslash)
	await process_frame
	await process_frame
	var all_close := true
	for enemy in gathered:
		if enemy.global_position.distance_to(player.global_position) > 6.0:
			all_close = false
	_check(all_close, "backslash pulls every enemy onto the player")

	print("--- death ---")
	var died := [false]
	player.died.connect(func() -> void: died[0] = true)
	player.take_damage(1000.0)
	_check(player.is_dead, "player is dead at 0 HP")
	_check(is_zero_approx(player.health), "health clamped to 0 (got %.1f)" % player.health)
	_check(died[0], "died signal emitted")
	player.take_damage(40.0)
	_check(is_zero_approx(player.health), "no damage taken after death")

	await create_timer(1.8).timeout
	_check(run_over.visible, "run-over screen is shown")
	_check(paused, "tree paused by the run-over screen")

	print("--- restart ---")
	var press := InputEventKey.new()
	press.physical_keycode = KEY_R
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	await create_timer(0.5).timeout
	_check(not paused, "restart unpauses the game")
	var fresh: Node = current_scene
	var fresh_player: Player = fresh.get_node_or_null("Player") as Player
	_check(fresh_player != null and not fresh_player.is_dead, "fresh player after restart")
	_check(fresh_player != null and is_equal_approx(fresh_player.health, fresh_player.max_health),
		"restart restores full health")

	if paused:
		paused = false

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


## Types the immortality cheat, one key press at a time.
func _type_cheat(_player: Player) -> void:
	for code in Player.CHEAT_CODE:
		var key := InputEventKey.new()
		key.physical_keycode = code
		key.pressed = true
		Input.parse_input_event(key)
		await process_frame


func _wait_for(predicate: Callable, timeout: float) -> bool:
	var elapsed := 0.0
	while elapsed < timeout:
		if predicate.call():
			return true
		await create_timer(0.05).timeout
		elapsed += 0.05
	return false
