extends Node3D
## Entry point of the arena. The horde paces itself through WaveManager; this
## script only reacts to the outcomes: death and level-up cards.
## It also owns the debug screenshot pass (`-- --capture`).

## A run carries three guns: the starting revolver plus two picks.
const MAX_WEAPONS := 3
## How much the health card adds to the player's maximum health.
const HEALTH_CARD_GAIN := 1.25
## Slot of the MP9 in the view model — the akimbo card hangs off it.
const MP9_INDEX := 6
## Golden weapon cards unlock after this many normal stat upgrades.
const NORMAL_UPGRADES_FOR_UNIQUE := 3
const UNIQUE_CARDS := preload("res://scripts/weapons/unique_cards.gd")

@onready var level_menu: LevelUpMenu = $LevelUpMenu
@onready var waves: WaveManager = $WaveManager
@onready var run_over: RunOver = $RunOver
@onready var network: NetworkGame = $NetworkGame

## The player this machine controls; spawned by NetworkGame (single player
## offline, one per peer online).
var player: Player

## Level-ups that happened while a card menu was already open.
var _pending_levels: int = 0
## Normal damage/rate/ammo/reload/spread upgrades taken this run. Golden cards
## stay hidden until this reaches NORMAL_UPGRADES_FOR_UNIQUE.
var _normal_upgrades: int = 0


func _ready() -> void:
	# A new arena starts with thinking enemies even after a debug/console run.
	Enemy.ai_frozen = false
	# Sound, resolution and the quality preset from the last session.
	Settings.load_all()
	Settings.apply_all(self)

	level_menu.chosen.connect(_on_card_chosen)
	network.local_player_spawned.connect(_bind_player)
	var existing := Net.local_player()
	if existing != null:
		_bind_player(existing)
	if "--capture" in OS.get_cmdline_user_args():
		_capture()


## Grabs the local player as soon as NetworkGame spawns it.
func _bind_player(spawned: Node) -> void:
	if spawned == player:
		return
	player = spawned as Player
	if player == null:
		return
	player.level_up.connect(_on_level_up)
	player.died.connect(_on_player_died)

# --- Run flow ---------------------------------------------------------------

func _on_player_died() -> void:
	# A card menu may already be open (the last kills can level the player up).
	# Close it so the death screen is the only thing on screen.
	_pending_levels = 0
	if level_menu.visible:
		level_menu.close()
	# Let the camera slump and the last hit land before the screen takes over.
	await get_tree().create_timer(1.1).timeout
	run_over.show_death(waves.wave_index, waves.waves_per_map, player.level, waves.kills)


## Spawns a single skeleton regardless of the wave state. Used by the capture
## pass and by the test tools; gameplay itself is driven by WaveManager.
func spawn_skeleton() -> Enemy:
	return waves.spawn_one()


## Debug key: pulls every living enemy onto the player. Handy for testing a
## crowd, a weapon or the death screen without waiting for the wave to walk in.
func gather_enemies() -> int:
	var alive := get_tree().get_nodes_in_group("enemies")
	var ring := maxf(1.2, 1.0 + float(alive.size()) * 0.12)
	for i in alive.size():
		var body := alive[i] as CharacterBody3D
		if body == null:
			continue
		var angle := TAU * float(i) / float(alive.size())
		var spot := player.global_position + Vector3(cos(angle), 0.0, sin(angle)) * ring
		spot.y = maxf(player.global_position.y - 0.15, 0.05)
		body.global_position = spot
		body.velocity = Vector3.ZERO
	return alive.size()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("gather_enemies"):
		gather_enemies()
		get_viewport().set_input_as_handled()


# --- Levelling --------------------------------------------------------------

func _on_level_up(_new_level: int) -> void:
	# Nothing to pick when the run is already over.
	if player.is_dead:
		return
	_pending_levels += 1
	if not level_menu.visible:
		_open_cards()


func _open_cards() -> void:
	if _pending_levels <= 0:
		return
	_pending_levels -= 1
	level_menu.open(_build_cards(), player.level)


func _on_card_chosen(card: Dictionary) -> void:
	_apply_card(card)
	if _pending_levels > 0:
		_open_cards()
	else:
		level_menu.close()


func _build_cards() -> Array:
	var viewmodel: Viewmodel = player.viewmodel
	var unlocks: Array[Dictionary] = []
	var upgrades: Array[Dictionary] = []
	var uniques := _available_unique_cards(viewmodel)
	var unlocked_count := 0

	for i in viewmodel.weapons.size():
		var weapon: Weapon = viewmodel.weapons[i]
		if not viewmodel.is_unlocked(i):
			unlocks.append({
				"kind": "unlock",
				"index": i,
				"title": weapon.display_name,
				"tag": "новое оружие",
				"desc": _weapon_blurb(i),
				"accent": Color(0.55, 0.8, 1.0),
			})
			continue
		unlocked_count += 1
		for stat in ["damage", "fire_rate", "ammo", "reload", "spread"]:
			upgrades.append(_upgrade_card(i, weapon, stat))

	# The player's own body is on the card table too: more headroom is what
	# keeps a run alive once the waves start doubling.
	upgrades.append(_health_card())

	# Akimbo MP9: only once the SMG is in hand and not yet doubled. It is kept
	# out of the random upgrade pool so the offer is guaranteed, not a lottery.
	var dual_card: Dictionary = {}
	var mp9: Weapon = viewmodel.weapons[MP9_INDEX] if viewmodel.weapons.size() > MP9_INDEX else null
	if mp9 and viewmodel.is_unlocked(MP9_INDEX) and mp9.can_be_dual and not mp9.is_dual():
		dual_card = {
			"kind": "upgrade",
			"index": MP9_INDEX,
			"stat": "dual",
			"title": "Двойные MP9",
			"tag": "модификация",
			"desc": "Второй ПП в левую руку:\nмагазин ×2 (%d) и вспышки по очереди" % (mp9.max_ammo * 2),
			"accent": Color(0.72, 0.86, 1.0),
		}

	# While a weapon is still locked, always offer it: the choice between a new
	# gun and an upgrade is the point of the level-up. A run carries three guns.
	var options: Array[Dictionary] = []
	if unlocked_count < MAX_WEAPONS and not unlocks.is_empty():
		unlocks.shuffle()
		options.append(unlocks[0])
	if not uniques.is_empty():
		# The golden offer is guaranteed once the run is deep enough, otherwise
		# it could stay buried under a pile of ordinary stat cards.
		uniques.shuffle()
		options.append(uniques[0])
	if not dual_card.is_empty():
		options.append(dual_card)

	upgrades.shuffle()
	for card in upgrades:
		if options.size() >= 3:
			break
		options.append(card)

	options.shuffle()
	return options


## Golden cards for guns already in hand and not yet fully mastered.
func _available_unique_cards(viewmodel: Viewmodel) -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	if _normal_upgrades < NORMAL_UPGRADES_FOR_UNIQUE:
		return cards
	for i in viewmodel.weapons.size():
		if not viewmodel.is_unlocked(i):
			continue
		var weapon: Weapon = viewmodel.weapons[i]
		for definition in UNIQUE_CARDS.for_weapon(i):
			var perk := String(definition.get("perk", ""))
			if perk == "" or weapon.has_unique(perk):
				continue
			cards.append({
				"kind": "unique",
				"index": i,
				"perk": perk,
				"unique": true,
				"title": String(definition.get("title", "")),
				"tag": String(definition.get("tag", "уникальное")),
				"desc": String(definition.get("desc", "")),
				"accent": UNIQUE_CARDS.GOLD,
			})
	return cards


func _health_card() -> Dictionary:
	return {
		"kind": "player",
		"index": -1,
		"stat": "health",
		"title": "Здоровье +25%",
		"tag": "игрок",
		"desc": "Максимум HP %.0f → %.0f\nи полное лечение" % [
			player.max_health, roundf(player.max_health * HEALTH_CARD_GAIN)],
		"accent": Color(1.0, 0.48, 0.42),
	}


func _upgrade_card(index: int, weapon: Weapon, stat: String) -> Dictionary:
	var title := ""
	var desc := ""
	var accent := Color(1.0, 0.85, 0.5)

	match stat:
		"damage":
			title = "Урон +25%"
			desc = "%s\n%.0f → %.0f" % [weapon.display_name, weapon.damage, weapon.damage * 1.25]
		"fire_rate":
			title = "Темп +20%"
			desc = "%s\n%.2f → %.2f выстр./с" % [weapon.display_name, weapon.fire_rate, weapon.fire_rate * 1.2]
		"ammo":
			title = "Магазин +20%"
			desc = "%s\n%d → %d патронов" % [weapon.display_name, weapon.max_ammo, weapon.max_ammo * 1.2]
		"reload":
			title = "Перезарядка −22%"
			desc = "%s\n%.2f → %.2f с" % [weapon.display_name, weapon.reload_time, weapon.reload_time * 0.78]
		"spread":
			title = "Точность +30%"
			desc = "%s\n%.2f° → %.2f°" % [weapon.display_name, weapon.spread_degrees, weapon.spread_degrees * 0.7]
			accent = Color(0.6, 1.0, 0.72)

	return {
		"kind": "upgrade",
		"index": index,
		"stat": stat,
		"title": title,
		"tag": "улучшение",
		"desc": desc,
		"accent": accent,
	}


func _weapon_blurb(index: int) -> String:
	match index:
		1:
			return "Два ствола, 9 дробин за выстрел.\nМедленная, но бьёт как грузовик."
		2:
			return "Автомат: 30 патронов, очередь.\nБыстрый и злой на средней дистанции."
		3:
			return "Снайперка: 10 патронов, 130 урона.\nОдин выстрел — один скелет."
		4:
			return "Пулемёт: 100 патронов, шквал огня.\nТяжёлый — с ним ходишь на 25% медленнее."
		5:
			return "Дробовик-автомат: 8 патронов.\nБлизко — страшная сила."
		6:
			return "ПП: 15 выстр./с, магазин на 30.\nБыстрый и вертлявый."
	return "Надёжный ствол на шесть патронов."


func _apply_card(card: Dictionary) -> void:
	var viewmodel: Viewmodel = player.viewmodel

	# The health card is not tied to a weapon, so it is handled before the
	# weapon index is validated.
	if String(card.get("kind", "")) == "player":
		player.max_health = roundf(player.max_health * HEALTH_CARD_GAIN)
		player.health = player.max_health
		player.health_changed.emit(player.health, player.max_health)
		return

	var index := int(card.get("index", -1))
	if index < 0 or index >= viewmodel.weapons.size():
		return
	var weapon: Weapon = viewmodel.weapons[index]
	var kind := String(card.get("kind", ""))
	var stat := String(card.get("stat", ""))

	if kind == "unique":
		weapon.grant_unique(String(card.get("perk", "")))
		return

	match kind:
		"unlock":
			viewmodel.unlock(index)
			player.switch_to(index)
		"upgrade":
			match stat:
				"dual":
					weapon.make_dual()
				"damage":
					weapon.damage *= 1.25
				"fire_rate":
					weapon.fire_rate *= 1.2
				"ammo":
					weapon.max_ammo *= 1.2
					weapon.ammo = weapon.max_ammo
					weapon.ammo_changed.emit(weapon.ammo, weapon.max_ammo)
				"reload":
					weapon.reload_time = maxf(0.6, weapon.reload_time * 0.78)
				"spread":
					weapon.spread_degrees = maxf(0.05, weapon.spread_degrees * 0.7)
			# Akimbo is a modification, not one of the three normal masteries.
			if stat != "dual":
				_normal_upgrades += 1


func _capture() -> void:
	await get_tree().create_timer(0.9).timeout
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	await _save("01_arena.png")

	var weapon: Weapon = player.weapon
	if weapon:
		var real_flash := weapon.flash_duration
		weapon.flash_duration = 2.0
		weapon.pull_trigger()
		await _save("02_revolver_fire.png")
		weapon.hide_flash()
		weapon.flash_duration = real_flash

		weapon.reload()
		await get_tree().create_timer(0.9).timeout
		await _save("03_revolver_reload.png")
		await get_tree().create_timer(1.4).timeout

		# Aim at the lit crate and catch the impact sparks.
		player._yaw = deg_to_rad(-12.1)
		player._pitch = deg_to_rad(-4.4)
		await get_tree().create_timer(0.2).timeout
		weapon.pull_trigger()
		await get_tree().create_timer(0.06).timeout
		await _save("05_impact.png")

		# Aim down the revolver sights.
		Input.action_press("aim")
		await get_tree().create_timer(0.5).timeout
		await _save("08_revolver_aim.png")
		Input.action_release("aim")
		await get_tree().create_timer(0.4).timeout

	player._pitch = deg_to_rad(2.0)
	player._yaw = deg_to_rad(38.0)
	await get_tree().create_timer(0.35).timeout
	await _save("04_arena_side.png")

	# Shotgun pass: the swap animation runs, then the double barrel fires.
	player._yaw = 0.0
	player._pitch = 0.0
	player.switch_to(1)
	await get_tree().create_timer(0.6).timeout
	var shotgun: Weapon = player.weapon
	if shotgun:
		await _save("06_shotgun_idle.png")
		var real_shotgun_flash := shotgun.flash_duration
		shotgun.flash_duration = 2.0
		shotgun.pull_trigger()
		await _save("07_shotgun_fire.png")
		shotgun.hide_flash()
		shotgun.flash_duration = real_shotgun_flash

		await get_tree().create_timer(3.0).timeout
		Input.action_press("aim")
		await get_tree().create_timer(0.5).timeout
		await _save("09_shotgun_aim.png")
		Input.action_release("aim")

	# Skeleton pass: a few of them rise in front of the player and start walking.
	player._yaw = 0.0
	player._pitch = 0.0
	await get_tree().create_timer(0.25).timeout
	for i in 3:
		var skeleton := spawn_skeleton()
		skeleton.global_position = player.global_position + Vector3(-3.0 + i * 3.0, 0.05, -6.5)
	await get_tree().create_timer(1.2).timeout
	await _save("11_skeletons.png")

	# Let them close in and swing so the attack animation is on screen.
	await get_tree().create_timer(2.4).timeout
	await _save("12_skeleton_attack.png")

	# Headshot pass: clear the crowd, take the revolver and hit a skull.
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	player.switch_to(0)
	await get_tree().create_timer(0.15).timeout
	var target := spawn_skeleton()
	target.global_position = player.global_position + Vector3(0.0, 0.05, -8.5)
	player._yaw = 0.0
	player._pitch = deg_to_rad(-0.5)
	await get_tree().create_timer(0.95).timeout
	player.weapon.pull_trigger()
	await get_tree().create_timer(0.04).timeout
	await _save("13_headshot.png")

	# Bunny hop pass: run up, then chain hops down the long lane.
	player.global_position = Vector3(-16.0, 0.2, 16.0)
	player._yaw = deg_to_rad(-90.0)
	player._pitch = 0.0
	await get_tree().create_timer(0.3).timeout
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await get_tree().create_timer(1.0).timeout
	Input.action_press("jump")
	await get_tree().create_timer(1.9).timeout
	await _save("10_bhop.png")
	Input.action_release("jump")
	Input.action_release("move_forward")
	Input.action_release("sprint")

	get_tree().quit()


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://screenshots/") + file_name
	var err := image.save_png(path)
	if err != OK:
		push_error("Could not save screenshot %s (error %d)" % [path, err])
	else:
		print("saved ", path)
