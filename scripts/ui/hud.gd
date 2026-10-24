extends Control
## Minimal diegetic-framed HUD: crosshair, ammo counter, short control hints.

@onready var ammo_label: Label = $Ammo
@onready var weapon_label: Label = $WeaponName
@onready var stats_label: Label = $Stats
@onready var hint_label: Label = $Hint
@onready var speed_label: Label = $Speed
@onready var enemy_label: Label = $Enemies
@onready var wave_label: Label = $Wave
@onready var cheat_label: Label = $Cheat

var _waves: WaveManager

var _weapon: Weapon
var _player: Player
var _reloading: bool = false
var _reload_duration: float = 1.0
var _reload_left: float = 0.0
var _pulse: float = 0.0
var _last_health: float = -1.0
var _damage_flash: float = 0.0
var _hit_flash: float = 0.0
var _hit_headshot: bool = false
var _stats_text: String = ""


func _ready() -> void:
	_waves = get_tree().get_first_node_in_group("wave_manager") as WaveManager
	_try_bind_player()


## The player may be spawned a frame or two later (network), so binding is lazy.
func _try_bind_player() -> void:
	if _player != null:
		return
	var candidate := Net.local_player() as Player
	if candidate == null:
		return
	_player = candidate
	_player.god_mode_changed.connect(_on_god_mode_changed)
	_player.weapon_changed.connect(_bind_weapon)
	_bind_weapon(_player.weapon)


func _on_god_mode_changed(enabled: bool) -> void:
	if cheat_label:
		cheat_label.text = "БЕССМЕРТИЕ + ВАНШОТ ВКЛ" if enabled else ""


func _bind_weapon(w: Weapon) -> void:
	if w == _weapon:
		return
	if _weapon:
		_weapon.ammo_changed.disconnect(_on_ammo_changed)
		_weapon.reload_started.disconnect(_on_reload_started)
		_weapon.reload_finished.disconnect(_on_reload_finished)
		_weapon.fired.disconnect(_on_fired)
		_weapon.hit_enemy.disconnect(_on_hit_enemy)

	_weapon = w
	_reloading = false
	_reload_left = 0.0
	_pulse = 0.0

	if _weapon:
		_weapon.ammo_changed.connect(_on_ammo_changed)
		_weapon.reload_started.connect(_on_reload_started)
		_weapon.reload_finished.connect(_on_reload_finished)
		_weapon.fired.connect(_on_fired)
		_weapon.hit_enemy.connect(_on_hit_enemy)
		weapon_label.text = _weapon.display_name
		_on_ammo_changed(_weapon.ammo, _weapon.max_ammo)


func _process(delta: float) -> void:
	if _player == null:
		_try_bind_player()
	_pulse = maxf(0.0, _pulse - delta * 7.0)
	_hit_flash = maxf(0.0, _hit_flash - delta * 4.5)
	if _reloading:
		_reload_left = maxf(0.0, _reload_left - delta)
	_update_speed_label()
	_update_weapon_stats()
	_update_health(delta)
	_update_enemy_label()
	_update_wave_label()
	queue_redraw()


func _update_wave_label() -> void:
	if wave_label == null:
		return
	wave_label.text = _waves.status_text() if _waves else ""


## Live numbers for the gun in hand, so upgrades are visible without opening
## anything.
func _update_weapon_stats() -> void:
	if _weapon == null or stats_label == null:
		return
	var rate := "%.2f" % _weapon.effective_fire_rate()
	if _weapon.has_unique("saiga_burst_pierce"):
		rate += "×2"
	var text := "урон %.0f\nтемп %s/с\nмагазин %d\nперезарядка %.2f с\nразброс %.2f°" % [
		_weapon.effective_damage(),
		rate,
		_weapon.max_ammo,
		_weapon.effective_reload_time(),
		_weapon.spread_degrees,
	]
	# Heavy guns show their mobility cost next to the damage numbers.
	if _weapon.move_speed_multiplier < 0.999:
		text += "\nход %d%%" % roundi(_weapon.move_speed_multiplier * 100.0)
	var status: Array[String] = []
	if _weapon.headshot_stacks > 0:
		if _weapon.has_unique("revolver_heat"):
			status.append("крест ×%d" % _weapon.headshot_stacks)
		elif _weapon.has_unique("svd_headshot"):
			status.append("серия ×%d" % _weapon.headshot_stacks)
	if _weapon.kill_stacks > 0 and _weapon.has_unique("akm_kill_heat"):
		status.append("убийства ×%d" % _weapon.kill_stacks)
	if _weapon.is_overheating():
		var burn := _weapon.self_burn_per_stack \
			* float(_weapon.kill_stacks - _weapon.self_burn_threshold + 1)
		status.append("ПЕРЕГРЕВ −%.1f HP" % burn)
	if not status.is_empty():
		text += "\n" + " · ".join(status)
	if text != _stats_text:
		_stats_text = text
		stats_label.text = text


func _on_hit_enemy(headshot: bool) -> void:
	_hit_flash = 1.0
	_hit_headshot = headshot


func _update_health(delta: float) -> void:
	if _player == null:
		return
	if _last_health >= 0.0 and _player.health < _last_health:
		_damage_flash = 1.0
	_last_health = _player.health
	_damage_flash = maxf(0.0, _damage_flash - delta * 2.5)


func _update_enemy_label() -> void:
	if enemy_label == null:
		return
	var count := get_tree().get_nodes_in_group("enemies").size()
	enemy_label.text = "ВРАГОВ: %d" % count if count > 0 else ""


func _update_speed_label() -> void:
	if _player == null or speed_label == null:
		return
	var speed := _player.planar_speed
	var streak := _player.hop_streak
	if speed < _player.walk_speed + 0.6 and streak < 2:
		speed_label.text = ""
		return

	var text := "%.1f м/с" % speed
	if streak >= 2:
		text += "    хоп ×%d" % streak
	speed_label.text = text
	# Hotter colour the faster you go: the streak is worth showing off.
	var heat := clampf((speed - _player.walk_speed) / 6.0, 0.0, 1.0)
	speed_label.modulate = Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.55, 0.25), heat)


func _draw() -> void:
	var center := size * 0.5
	var gap := 6.0 + _pulse * 12.0
	var length := 7.0
	var thickness := 2.0

	# Damage vignette: a quick red wash when the player is hit.
	if _damage_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.75, 0.06, 0.05, 0.2 * _damage_flash))
	# The overheated AKM keeps a low orange fire on the screen edges.
	if _weapon and _weapon.is_overheating():
		var flicker := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.023)
		draw_rect(Rect2(Vector2.ZERO, size),
			Color(1.0, 0.23, 0.02, 0.055 + 0.035 * flicker))

	# Health bar, bottom left, above the speed readout.
	if _player:
		var ratio := clampf(_player.health / maxf(_player.max_health, 1.0), 0.0, 1.0)
		var bar := Rect2(Vector2(32.0, size.y - 116.0), Vector2(220.0, 12.0))
		draw_rect(bar, Color(0.0, 0.0, 0.0, 0.45))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), Color(0.8, 0.16, 0.13, 0.95))
		draw_rect(bar, Color(1.0, 1.0, 1.0, 0.18), false, 1.0)

		# Experience bar, bottom centre, with the current level above it.
		var xp_bar := Rect2(Vector2((size.x - 640.0) * 0.5, size.y - 44.0), Vector2(640.0, 8.0))
		var xp_ratio := clampf(_player.xp / maxf(_player.xp_to_next, 1.0), 0.0, 1.0)
		draw_rect(xp_bar, Color(0.0, 0.0, 0.0, 0.55))
		draw_rect(Rect2(xp_bar.position, Vector2(xp_bar.size.x * xp_ratio, xp_bar.size.y)),
			Color(0.45, 0.78, 1.0, 0.95))
		draw_rect(xp_bar, Color(1.0, 1.0, 1.0, 0.16), false, 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(xp_bar.position.x, xp_bar.position.y - 6.0),
			"УР. %d" % _player.level, HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
			Color(0.72, 0.88, 1.0, 0.9))

	# While aiming down the sights the gun itself is the sight picture, so the
	# crosshair fades out instead of covering the target.
	var aim := _player.viewmodel.aim_blend if _player else 0.0
	var color := Color(0.95, 0.95, 0.95, 0.85 * (1.0 - aim))

	if color.a > 0.02:
		for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_line(center + dir * gap, center + dir * (gap + length), color, thickness, true)
		draw_circle(center, 1.5, Color(0.95, 0.2, 0.15, 0.9 * (1.0 - aim)))

	if _reloading:
		var progress := 1.0 - clampf(_reload_left / maxf(_reload_duration, 0.01), 0.0, 1.0)
		draw_arc(center, 26.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 48, Color(1.0, 0.85, 0.5, 0.55), 2.5, true)

	# Hit marker: four diagonal ticks, orange when the weak point was hit.
	if _hit_flash > 0.0:
		var marker_color := Color(1.0, 0.5, 0.15, _hit_flash) if _hit_headshot \
			else Color(1.0, 1.0, 1.0, 0.85 * _hit_flash)
		var outer := 15.0 + (3.0 if _hit_headshot else 0.0)
		for dir in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var d: Vector2 = (dir as Vector2).normalized()
			draw_line(center + d * (outer - 7.0), center + d * outer, marker_color, 2.0, true)

	if _weapon and _weapon.has_unique("revolver_heat") and _weapon.headshot_stacks > 0:
		_draw_burning_cross(center)


## The revolver's golden card turns every headshot into another notch of a
## burning cross. More stacks = longer, hotter, more restless flames.
func _draw_burning_cross(center: Vector2) -> void:
	var heat := clampf(float(_weapon.headshot_stacks) / maxf(float(_weapon.headshot_stack_cap), 1.0), 0.0, 1.0)
	var time := Time.get_ticks_msec() * 0.001
	var flicker := clampf(0.78 + 0.18 * sin(time * 17.0) + 0.04 * sin(time * 41.0), 0.55, 1.0)
	var reach := 22.0 + 16.0 * heat
	var alpha := (0.25 + 0.75 * heat) * flicker
	var hot := Color(1.0, lerpf(0.35, 0.9, heat), lerpf(0.06, 0.52, heat), alpha)

	# A soft heat halo behind the cross sells the "burning" part.
	draw_circle(center, 16.0 + 14.0 * heat, Color(1.0, 0.34, 0.03, 0.06 * alpha))
	for width in [14.0, 6.0, 2.5]:
		var layer := alpha * (0.06 if width > 8.0 else 0.14 if width > 4.0 else 0.9)
		var candle := Color(hot.r, hot.g, hot.b, layer)
		draw_line(center + Vector2(-reach, 0.0), center + Vector2(reach, 0.0), candle, width, true)
		draw_line(center + Vector2(0.0, -reach), center + Vector2(0.0, reach), candle, width, true)

	# Little licking flames at the four tips.
	var tip := 3.0 + 5.0 * heat
	for dir in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var d: Vector2 = dir as Vector2
		var side: Vector2 = Vector2(-d.y, d.x)
		draw_line(center + d * reach, center + d * (reach + tip) + side * 2.0,
			Color(1.0, 0.52, 0.08, alpha * 0.75), 1.5, true)
		draw_line(center + d * reach, center + d * (reach + tip) - side * 2.0,
			Color(1.0, 0.52, 0.08, alpha * 0.75), 1.5, true)

	draw_circle(center, 2.0 + 2.5 * heat, Color(1.0, 0.93, 0.62, alpha))
	var label := "×%d" % _weapon.headshot_stacks
	draw_string(ThemeDB.fallback_font, center + Vector2(-18.0, -reach - 9.0), label,
		HORIZONTAL_ALIGNMENT_CENTER, 36.0, 14, Color(1.0, 0.82, 0.35, alpha))


func _on_ammo_changed(current: int, maximum: int) -> void:
	if ammo_label:
		ammo_label.text = "%d / %d" % [current, maximum]
		ammo_label.modulate = Color(1.0, 0.45, 0.35) if current == 0 else Color.WHITE


func _on_reload_started(duration: float) -> void:
	_reloading = true
	_reload_duration = duration
	_reload_left = duration


func _on_reload_finished() -> void:
	_reloading = false
	_reload_left = 0.0


func _on_fired() -> void:
	_pulse = 1.0
