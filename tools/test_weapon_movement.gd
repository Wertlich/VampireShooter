extends SceneTree

# Checks that a heavy weapon slows the player down while it is in hand and that
# the speed comes back after switching to a light gun.
# Usage: godot --headless --path . --script res://tools/test_weapon_movement.gd

const RPD_INDEX := 4
const REVOLVER_INDEX := 0

var _failures: int = 0
var _player: Player


func _initialize() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	_player = scene.get("player") as Player
	var hud := scene.get_node("HUD/Root")
	var waves: WaveManager = scene.get("waves") as WaveManager
	waves.set_process(false)
	waves.set_physics_process(false)
	for enemy in get_nodes_in_group("enemies"):
		enemy.queue_free()

	# A clear lane near the south wall, the same one test_bhop.gd uses.
	_player.global_position = Vector3(-30.0, 0.2, 16.0)
	_player._yaw = deg_to_rad(-90.0)
	await create_timer(0.6).timeout

	print("--- light gun ---")
	_check(not ("ход" in hud.stats_label.text), "light gun has no mobility penalty in HUD")
	var walk := await _measure_speed(false, "revolver walk")
	_check(walk > 4.8 and walk < 5.3, "revolver walk is near 5.2 m/s (%.2f)" % walk)
	var sprint := await _measure_speed(true, "revolver sprint")
	_check(sprint > 7.5 and sprint < 8.3, "revolver sprint is near 8.0 m/s (%.2f)" % sprint)

	print("--- RPD in hand ---")
	_player.viewmodel.unlock(RPD_INDEX)
	_player.switch_to(RPD_INDEX)
	await create_timer(0.5).timeout
	_check(_player.weapon != null and _player.weapon.display_name == "РПД", "RPD is equipped")
	_check("ход 75%" in hud.stats_label.text, "HUD shows the RPD mobility penalty")
	var rpd_walk := await _measure_speed(false, "RPD walk")
	_check(rpd_walk < walk * 0.85, "RPD walk is clearly slower (%.2f vs %.2f)" % [rpd_walk, walk])
	_check(absf(rpd_walk - walk * 0.75) < 0.2,
		"RPD walk is 75%% of the light-gun speed (%.2f)" % rpd_walk)
	var rpd_sprint := await _measure_speed(true, "RPD sprint")
	_check(absf(rpd_sprint - sprint * 0.75) < 0.2,
		"RPD sprint is 75%% of the light-gun speed (%.2f)" % rpd_sprint)

	print("--- holster ---")
	_player.switch_to(REVOLVER_INDEX)
	await create_timer(0.5).timeout
	var restored := await _measure_speed(false, "revolver walk after RPD")
	_check(absf(restored - walk) < 0.2, "switching back restores walk speed (%.2f)" % restored)

	print("")
	if _failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _measure_speed(sprint: bool, label: String) -> float:
	Input.action_release("aim")
	Input.action_press("move_forward")
	if sprint:
		Input.action_press("sprint")
	await create_timer(1.2).timeout
	var measured := _player.planar_speed
	print("  %-28s %.2f m/s" % [label, measured])
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await create_timer(0.6).timeout
	return measured


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok    ", label)
	else:
		_failures += 1
		print("  FAIL  ", label)
