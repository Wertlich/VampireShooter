extends SceneTree

# Checks the golden weapon cards: catalog size, the three-normal-upgrade gate,
# stacking perks, piercing, lifesteal, overheat, the Saiga burst and knockback.
# Usage: godot --headless --path . --script res://tools/test_unique_cards.gd

const UNIQUE_CARDS := preload("res://scripts/weapons/unique_cards.gd")

var _failures: int = 0


func _initialize() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var main = scene
	var player := scene.get("player") as Player
	var waves := scene.get("waves") as WaveManager
	var menu = scene.get_node("LevelUpMenu")
	var hud = scene.get_node("HUD/Root")
	waves.set_process(false)
	waves.set_physics_process(false)
	for enemy in get_nodes_in_group("enemies"):
		enemy.queue_free()
	Enemy.ai_frozen = true
	await process_frame
	await physics_frame

	print("--- catalog ---")
	var expected := {0: 2, 1: 1, 2: 2, 3: 2, 4: 1, 5: 1, 6: 1}
	for index in expected:
		var cards := UNIQUE_CARDS.for_weapon(index)
		_check(cards.size() == expected[index],
			"weapon %d has %d unique card(s), got %d" % [index, expected[index], cards.size()])
		for card in cards:
			_check(String(card.get("perk", "")) != "" and String(card.get("title", "")) != "",
				"card has a perk id and title")

	print("--- three normal upgrades unlock golden cards ---")
	_check(not _has_unique(main._build_cards()), "no golden card before three upgrades")
	var revolver := player.viewmodel.weapons[0] as Weapon
	for i in 3:
		main._apply_card({"kind": "upgrade", "index": 0, "stat": "damage"})
	_check(int(main.get("_normal_upgrades")) == 3, "three normal upgrades counted")
	var cards = main._build_cards()
	var golden := _find_unique(cards)
	_check(not golden.is_empty(), "a golden card is offered after three upgrades")
	if not golden.is_empty():
		_check(bool(golden.get("unique", false)), "card carries the unique flag")
		_check(golden.get("accent") == UNIQUE_CARDS.GOLD, "card uses the golden accent")
		var panel := menu._make_card(golden, 0) as PanelContainer
		var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
		_check(style.border_width_left >= 3 and style.shadow_size >= 16 and style.shadow_color.a > 0.2,
			"golden card has a glowing border (shadow %d)" % style.shadow_size)
		panel.queue_free()
		var perk := String(golden.get("perk", ""))
		main._apply_card(golden)
		_check(revolver.has_unique(perk), "golden card installs its perk")
		var next_cards = main._build_cards()
		var found_taken := false
		for card in next_cards:
			if String(card.get("perk", "")) == perk:
				found_taken = true
		_check(not found_taken, "taken golden card is not offered again")

	print("--- revolver burning cross ---")
	revolver.grant_unique("revolver_heat")
	var base_damage := revolver.damage
	var base_rate := revolver.effective_fire_rate()
	for i in 3:
		revolver._apply_shot_result({"hits": 1, "headshots": 1, "kills": 0, "damage": 55.0})
	_check(revolver.headshot_stacks == 3, "three headshots build three cross stacks")
	_check(revolver.effective_damage() > base_damage, "stacks raise revolver damage")
	_check(revolver.effective_fire_rate() > base_rate, "stacks raise revolver fire rate")
	hud._update_weapon_stats()
	_check("крест ×3" in hud.stats_label.text, "HUD reports the burning-cross stacks")
	player.viewmodel.unlock(1)
	player.switch_to(1)
	await create_timer(0.5).timeout
	_check(revolver.headshot_stacks == 3, "holstering does not wipe the cross")
	player.switch_to(0)
	await create_timer(0.5).timeout
	revolver.ammo = 0
	revolver.reload()
	_check(revolver.headshot_stacks == 3, "revolver stacks survive reload")
	revolver.cancel_reload()
	revolver.ammo = revolver.max_ammo
	revolver._process(3.1)
	_check(revolver.headshot_stacks == 0, "cross goes out after three seconds")

	print("--- revolver headshot blast ---")
	revolver.grant_unique("revolver_blast")
	var blast_a := _spawn_enemy(waves, Vector3(10.0, 0.05, 16.0))
	var blast_b := _spawn_enemy(waves, Vector3(11.0, 0.05, 16.0))
	await physics_frame
	var health_a := blast_a.health
	var health_b := blast_b.health
	revolver._explode_headshot(Vector3(10.5, 0.2, 16.0))
	var expected_blast := revolver.damage * revolver.blast_damage_fraction
	_check(absf((health_a - blast_a.health) - expected_blast) < 0.2,
		"blast hits the first enemy for 1/3 base damage (%.1f)" % (health_a - blast_a.health))
	_check(absf((health_b - blast_b.health) - expected_blast) < 0.2,
		"blast hits the second enemy for 1/3 base damage (%.1f)" % (health_b - blast_b.health))

	print("--- SVD headshot tempo ---")
	var svd := player.viewmodel.weapons[3] as Weapon
	svd.grant_unique("svd_headshot")
	var svd_base := svd.effective_fire_rate()
	svd._apply_shot_result({"hits": 1, "headshots": 1, "kills": 0, "damage": 130.0})
	_check(svd.headshot_stacks == 1, "SVD headshot starts the streak")
	_check(svd.effective_fire_rate() > svd_base, "SVD streak raises fire rate")
	svd._apply_shot_result({"hits": 0, "headshots": 0, "kills": 0, "damage": 0.0})
	_check(svd.headshot_stacks == 0, "SVD miss clears the streak")
	svd._apply_shot_result({"hits": 1, "headshots": 1, "kills": 0, "damage": 130.0})
	svd.ammo = 0
	svd.reload()
	_check(svd.headshot_stacks == 0, "SVD reload clears the streak")
	svd.cancel_reload()
	svd.ammo = svd.max_ammo
	svd._apply_shot_result({"hits": 1, "headshots": 1, "kills": 0, "damage": 130.0})
	svd._process(3.1)
	_check(svd.headshot_stacks == 0, "SVD streak expires after three seconds")

	print("--- SVD piercing ---")
	svd.grant_unique("svd_pierce")
	player.global_position = Vector3(-10.0, 0.2, 16.0)
	player._yaw = deg_to_rad(-90.0)
	player._pitch = 0.0
	await create_timer(0.3).timeout
	var first := _spawn_enemy(waves, Vector3(-5.0, 0.05, 16.0))
	var second := _spawn_enemy(waves, Vector3(-2.0, 0.05, 16.0))
	await create_timer(0.3).timeout
	svd.ammo = svd.max_ammo
	var shot := svd._shoot(svd.damage)
	_check(int(shot.get("hits", 0)) >= 2, "piercing shot hits two enemies (%d)" % int(shot.get("hits", 0)))
	_check(first.health <= 0.0 and second.health <= 0.0,
		"both lined-up enemies die (%.1f / %.1f HP)" % [first.health, second.health])

	print("--- AKM lifesteal and overheat ---")
	var akm := player.viewmodel.weapons[2] as Weapon
	akm.grant_unique("akm_lifesteal")
	player.health = 50.0
	akm._apply_shot_result({"hits": 1, "headshots": 0, "kills": 0, "damage": 100.0})
	_check(is_equal_approx(player.health, 55.0), "5%% lifesteal heals 5 HP (%.1f)" % player.health)
	akm.grant_unique("akm_kill_heat")
	var akm_base_rate := akm.effective_fire_rate()
	var akm_base_reload := akm.effective_reload_time()
	player.health = 80.0
	akm._apply_shot_result({"hits": 1, "headshots": 0, "kills": 6, "damage": 0.0})
	_check(akm.kill_stacks == 6, "six kills build six overheat stacks")
	_check(akm.effective_fire_rate() > akm_base_rate, "overheat raises fire rate")
	_check(akm.effective_reload_time() < akm_base_reload, "overheat shortens reload")
	_check(player.health < 80.0, "six stacks burn the shooter (%.1f HP)" % player.health)
	akm._process(3.1)
	_check(akm.kill_stacks == 0, "overheat expires after three seconds")

	print("--- double barrel knockback ---")
	player.viewmodel.unlock(1)
	player.switch_to(1)
	await create_timer(0.5).timeout
	var shotgun := player.viewmodel.weapons[1] as Weapon
	var old_spread := shotgun.spread_degrees
	shotgun.grant_unique("shotgun_knockback")
	_check(shotgun.spread_degrees > old_spread, "shotgun spread grows (%.2f -> %.2f)" % [
		old_spread, shotgun.spread_degrees])
	shotgun.ammo = shotgun.max_ammo
	player.velocity = Vector3.ZERO
	shotgun.pull_trigger()
	_check(Vector2(player.velocity.x, player.velocity.z).length() > 1.0,
		"shot kicks the player backwards (%.2f m/s)" % Vector2(player.velocity.x, player.velocity.z).length())
	player.velocity = Vector3.ZERO

	print("--- Saiga burst ---")
	player.viewmodel.unlock(5)
	player.switch_to(5)
	await create_timer(0.5).timeout
	var saiga := player.viewmodel.weapons[5] as Weapon
	saiga.grant_unique("saiga_burst_pierce")
	_check(is_equal_approx(saiga.fire_rate, saiga.burst_fire_rate),
		"Saiga reaches AKM-like base rate (%.2f)" % saiga.fire_rate)
	_check(saiga._has_piercing(), "Saiga burst pierces")
	saiga.ammo = saiga.max_ammo
	saiga._cooldown = 0.0
	saiga.pull_trigger()
	await create_timer(0.15).timeout
	_check(saiga.ammo == saiga.max_ammo - 2, "one click fires two quick shells (%d left)" % saiga.ammo)

	print("--- RPD and MP9 unique stats ---")
	var rpd := player.viewmodel.weapons[4] as Weapon
	var rpd_damage := rpd.damage
	rpd.grant_unique("rpd_heavy_caliber")
	_check(rpd.damage > rpd_damage, "RPD heavy caliber raises damage (%.1f)" % rpd.damage)
	_check(is_equal_approx(rpd.move_speed_multiplier, 0.65),
		"RPD heavy caliber deepens the movement penalty (%.2f)" % rpd.move_speed_multiplier)
	var mp9 := player.viewmodel.weapons[6] as Weapon
	var mp9_rate := mp9.fire_rate
	var mp9_ammo := mp9.max_ammo
	mp9.grant_unique("mp9_swarm")
	_check(mp9.fire_rate > mp9_rate, "MP9 swarm raises fire rate (%.2f)" % mp9.fire_rate)
	_check(mp9.max_ammo > mp9_ammo, "MP9 swarm raises magazine (%d)" % mp9.max_ammo)

	Enemy.ai_frozen = false
	print("")
	if _failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _spawn_enemy(waves: WaveManager, at: Vector3) -> Enemy:
	var enemy := waves.spawn_kind("skeleton", at) as Enemy
	enemy.global_position = at
	return enemy


func _has_unique(cards: Array) -> bool:
	for card in cards:
		if bool(card.get("unique", false)):
			return true
	return false


func _find_unique(cards: Array) -> Dictionary:
	for card in cards:
		if bool(card.get("unique", false)):
			return card
	return {}


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok    ", label)
	else:
		_failures += 1
		print("  FAIL  ", label)
