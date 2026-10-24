class_name Enemy
extends CharacterBody3D
## Shared enemy brain: walk at the player, claw or shoot, take damage, die.
##
## Every enemy type (skeleton, zombie, slime, archer, boss) is this script with
## different exports and a different model, so hit flash, knockback, headshots,
## XP gems and the death fade only exist once. The ranged branch keeps its
## distance and shoots instead of closing in.

## Emitted the moment the enemy dies, before the death animation plays.
signal died(enemy: Enemy)

const XP_GEM := preload("res://scenes/pickups/xp_gem.tscn")

enum Mode { MELEE, RANGED }

## Debug switch from the in-game console: frozen enemies still take hits and die
## but stop moving and attacking. Static so newly spawned waves freeze too.
static var ai_frozen: bool = false

@export_group("Stats")
@export var max_health: float = 120.0
@export var move_speed: float = 3.0
@export var damage: float = 12.0
## Melee: how close it has to be to swing. Ranged: unused.
@export var attack_range: float = 1.8
@export var attack_cooldown: float = 1.5
## Delay between the wind-up and the actual hit, so the swing can be dodged.
@export var attack_hit_delay: float = 0.45
@export var knockback_force: float = 4.0
@export var head_zone_height: float = 1.45
@export var headshot_multiplier: float = 2.0
@export var gem_count: int = 1

@export_group("Loot")
## XP per crystal. Slimes use a higher-value tier than the basic enemies.
@export var gem_xp_value: float = 8.0
@export var gem_tier: int = 1
## Visual scale of the crystal. Slime red = 1.2, boss gold = 3x red.
@export var gem_size: float = 1.0
@export var gem_color: Color = Color(0.45, 0.95, 1.0, 1.0)

@export_group("Behaviour")
@export var mode: Mode = Mode.MELEE
## Ranged enemies try to sit at this distance from the player.
@export var preferred_distance: float = 9.0
## Closer than this and they back away instead of holding ground.
@export var retreat_distance: float = 5.5
## How far their projectile is allowed to start from.
@export var shot_range: float = 22.0

@export_group("Projectile")
@export var projectile_scene: PackedScene
@export var projectile_speed: float = 18.0
@export var projectile_spawn_height: float = 1.3

@export_group("Flight")
## Body-centre altitude above the player's feet when far away. 0 keeps the old
## ground-based hover behaviour.
@export var flight_altitude: float = 0.0
## Altitude once the enemy is right on top of the player.
@export var flight_low_altitude: float = 1.5
## Start descending when the horizontal distance drops below this.
@export var flight_descent_radius: float = 12.0
## Distance at which the low altitude is reached.
@export var flight_close_distance: float = 2.5
@export var flight_speed: float = 6.0

@export_group("Animations")
@export var walk_anim: StringName = &"Run"
@export var attack_anim: StringName = &"Attack"
## Optional idle clip, played when the enemy stands still.
@export var idle_anim: StringName = &""
## Scale playback with real speed (off for clips that are a fixed montage).
@export var sync_anim_speed: bool = true
@export var anim_speed: float = 1.0

@export_group("Model")
## Alternative models for the same enemy. One is picked at random on spawn, so a
## wave of zombies does not look like an army of clones.
@export var variants: Array[PackedScene] = []

@export_group("Look Randomizer")
## Per-instance tint of the model's textures (skin, clothes, bones), so even the
## same variant reads differently from enemy to enemy.
@export var random_tint: bool = false
## 0 = no tint, 1 = a strongly coloured one.
@export var tint_strength: float = 0.35
@export var brightness_range: Vector2 = Vector2(0.82, 1.18)
@export var scale_range: Vector2 = Vector2(1.0, 1.0)

@export_group("Spawn And Look")
## Skeletons rise out of the floor on spawn; flying enemies do not.
@export var rise_from_ground: bool = true
## Flying enemies ignore gravity and stay at whatever height they spawned at.
@export var flying: bool = false
## Height the model floats at (slimes and ghosts).
@export var hover_height: float = 0.0
## Extra yaw for models whose front is not +Z.
@export var model_yaw_degrees: float = 0.0
## Multiplies the albedo of every surface: 1.0 keeps the texture as it is, and
## values above 1 lift models whose own textures are too dark to read in a
## moonlit arena (the pig demon is nearly black on its own).
@export var albedo_boost: float = 1.0
@export var gravity: float = 22.0
@export var separation_radius: float = 1.35
@export var separation_strength: float = 2.6

var health: float = 60.0
## Network identity, assigned by the host; 0 while offline.
var net_id: int = 0
## Roster name ("skeleton", "zombie"...) so clients can spawn the right scene.
var net_kind: String = ""
## True on clients: the host owns this enemy, we only mirror its state.
var net_puppet: bool = false

var _player: Player
var _model: Node3D
var _anim: AnimationPlayer
## One entry per surface: the per-enemy material copy used for flash and fade.
var _surfaces: Array[Dictionary] = []
## Colour the randomizer picked for this instance.
var _tint: Color = Color.WHITE
var _attack_cd: float = 0.0
var _stagger: float = 0.0
var _flash: float = 0.0
var _rise: float = 0.0
var _dead: bool = false
var _attacking: bool = false
var _strafe: float = 1.0
var _strafe_timer: float = 0.0
## Seconds until the enemy looks for a closer player again.
var _retarget: float = 0.0
## First flight tick snaps the body from the spawn point up to its cruise height.
var _flight_ready: bool = false
var behavior: EnemyBehavior


## Damage applied by the host, mirrored on a client copy.
func net_apply_health(value: float) -> void:
	if not net_puppet:
		return
	if value <= 0.0 and not _dead:
		_die()
		return
	if _dead:
		return
	if value < health:
		_flash = 1.0
		_apply_flash()
	health = value


## Nearest living player wins the aggro. Only runs on the host.
func _pick_target() -> void:
	var best: Player = null
	var best_distance := 1.0e9
	for node in get_tree().get_nodes_in_group("player"):
		var candidate := node as Player
		if candidate == null or candidate.is_dead:
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	_player = best


func _ready() -> void:
	for child in get_children():
		if child is EnemyBehavior:
			behavior = child
			mode = behavior.attack_style as Mode
			break
	health = max_health
	if net_puppet:
		# Mirror-only copy on a client: no AI, no spawn rise.
		_player = null
		_model = _build_model()
		_model.rotation_degrees.y = model_yaw_degrees
		_anim = _find_anim(_model)
		_dress_materials()
		_setup_animations()
		_rise = 1.0
		_model.position.y = hover_height
		return
	_pick_target()
	_tint = _roll_tint()
	_model = _build_model()
	_model.rotation_degrees.y = model_yaw_degrees
	if not is_equal_approx(scale_range.x, 1.0) or not is_equal_approx(scale_range.y, 1.0):
		_model.scale *= randf_range(scale_range.x, scale_range.y)
	_anim = _find_anim(_model)
	_dress_materials()
	_setup_animations()

	if rise_from_ground:
		_rise = 0.0
		_model.position.y = -1.6
	else:
		_rise = 1.0
		_model.position.y = hover_height


## Instantiates one of the `variants` at random, or uses the scene's own Body.
func _build_model() -> Node3D:
	var holder := $Model as Node3D
	if variants.is_empty():
		return $Model/Body as Node3D
	var pick: PackedScene = variants[randi() % variants.size()]
	var body := pick.instantiate() as Node3D
	body.name = "Body"
	holder.add_child(body)
	return body


## Random skin/clothes colour for this instance (white = untouched textures).
func _roll_tint() -> Color:
	if not random_tint:
		return Color.WHITE
	var coloured := Color.from_hsv(randf(), 1.0, 1.0).lerp(Color.WHITE, 1.0 - clampf(tint_strength, 0.0, 1.0))
	var brightness := randf_range(brightness_range.x, brightness_range.y)
	return Color(coloured.r * brightness, coloured.g * brightness, coloured.b * brightness, 1.0)


func _physics_process(delta: float) -> void:
	if net_puppet:
		return
	if _dead:
		if behavior:
			behavior.set_state(&"Dead")
		velocity.y -= gravity * delta
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		move_and_slide()
		return

	if ai_frozen:
		if behavior:
			behavior.set_state(&"Idle")
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		if flying or is_on_floor():
			velocity.y = 0.0
		else:
			velocity.y -= gravity * delta
		move_and_slide()
		_update_visual(delta)
		return

	_attack_cd = maxf(0.0, _attack_cd - delta)
	_stagger = maxf(0.0, _stagger - delta)

	# In co-op the nearest player can change, so look around now and then.
	_retarget -= delta
	if _retarget <= 0.0:
		_retarget = behavior.retarget_seconds if behavior else 0.5
		_pick_target()

	if not is_on_floor():
		if not flying:
			velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	var to_player := Vector3.ZERO
	if is_instance_valid(_player):
		to_player = _player.global_position - global_position
		to_player.y = 0.0

	var distance := to_player.length()
	_update_flight(delta, distance)
	if distance > 0.05:
		var dir := to_player / distance
		# Model front is +Z, so aim +Z at the player.
		var turn_speed := behavior.turn_speed if behavior else 10.0
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), clampf(delta * turn_speed, 0.0, 1.0))

		if behavior:
			behavior.tick(self, dir, distance, delta)
		elif mode == Mode.RANGED:
			_move_ranged(dir, distance, delta)
		else:
			_move_melee(dir, distance, delta)

		# Push away from neighbours so the pack spreads instead of stacking up.
		var allow_movement := behavior == null or (behavior.enabled and behavior.movement_enabled and distance <= behavior.detection_range)
		var push := _separation() if allow_movement else Vector3.ZERO
		velocity.x += push.x
		velocity.z += push.z
	else:
		if behavior:
			behavior.set_state(&"Idle")
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)

	move_and_slide()
	_update_visual(delta)


# --- Movement ---------------------------------------------------------------

func _uses_descent_flight() -> bool:
	return flying and flight_altitude > 0.0


## Cruise high above the arena, then glide down as the player gets closer.
func _update_flight(delta: float, distance: float) -> void:
	if not _uses_descent_flight():
		return
	var base_y := _player.global_position.y if is_instance_valid(_player) else 0.0
	if not _flight_ready:
		global_position.y = base_y + flight_altitude
		velocity.y = 0.0
		_flight_ready = true
		return

	var target_y := base_y + _flight_target_altitude(distance)
	velocity.y = clampf((target_y - global_position.y) * 4.0, -flight_speed, flight_speed)


func _flight_target_altitude(distance: float) -> float:
	var span := maxf(flight_descent_radius - flight_close_distance, 0.01)
	var blend := clampf((distance - flight_close_distance) / span, 0.0, 1.0)
	return lerpf(flight_low_altitude, flight_altitude, blend)


func _move_melee(dir: Vector3, distance: float, _delta: float) -> void:
	var wants_to_move := _stagger <= 0.0 and distance > attack_range * 0.85 and not _attacking
	if wants_to_move:
		velocity.x = dir.x * move_speed
		velocity.z = dir.z * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, 14.0 * _delta)
		velocity.z = move_toward(velocity.z, 0.0, 14.0 * _delta)

	if distance <= attack_range and _attack_cd <= 0.0 and _stagger <= 0.0 and _player_alive():
		_swing()


func _move_ranged(dir: Vector3, distance: float, delta: float) -> void:
	# Archers shuffle sideways now and then so they are not a static target.
	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = randf_range(1.2, 2.6)
		_strafe = -1.0 if randf() < 0.5 else 1.0
	var sideways := dir.cross(Vector3.UP) * _strafe

	var wish := Vector3.ZERO
	if distance < retreat_distance:
		wish = -dir + sideways * 0.7
	elif distance > preferred_distance:
		wish = dir + sideways * 0.25
	else:
		wish = sideways * 0.8

	if _stagger > 0.0 or _attacking:
		wish = Vector3.ZERO
	wish = wish.normalized() if wish.length() > 0.01 else Vector3.ZERO

	velocity.x = move_toward(velocity.x, wish.x * move_speed, 12.0 * delta)
	velocity.z = move_toward(velocity.z, wish.z * move_speed, 12.0 * delta)

	if _attacking or _attack_cd > 0.0 or _stagger > 0.0 or not _player_alive():
		return
	if distance > shot_range:
		return
	if not _has_line_of_sight():
		return
	_fire_arrow()


func _has_line_of_sight() -> bool:
	var from := global_position + Vector3.UP * maxf(1.0, projectile_spawn_height)
	var to := _player.global_position + Vector3.UP * 1.1
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)  # world geometry only
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


# --- Attacks ----------------------------------------------------------------

func _player_alive() -> bool:
	return is_instance_valid(_player) and not _player.is_dead and (behavior == null or (behavior.enabled and behavior.attacks_enabled))


func _swing() -> void:
	_attack_cd = attack_cooldown
	_attacking = true
	_play_attack_anim()

	# The claw connects partway through the swing, not on the first frame.
	await get_tree().create_timer(attack_hit_delay).timeout
	if _dead:
		return
	_attacking = false
	if ai_frozen or not _player_alive():
		return
	if is_instance_valid(_player) and not _player.is_dead \
			and global_position.distance_to(_player.global_position) <= attack_range * 1.35:
		_player.take_damage(damage, global_position + Vector3.UP, global_basis.z)


func _fire_arrow() -> void:
	_attack_cd = attack_cooldown
	_attacking = true
	_play_attack_anim()

	# The bow releases after the draw, so a player who breaks line of sight in
	# that window is safe.
	await get_tree().create_timer(attack_hit_delay).timeout
	_attacking = false
	if _dead or ai_frozen or projectile_scene == null:
		return
	if not _player_alive():
		return
	if not _has_line_of_sight():
		return

	var scene := get_tree().current_scene
	if scene == null:
		return
	var origin := global_position + Vector3.UP * projectile_spawn_height \
		+ global_basis.z * 0.45
	var target := _player.global_position + Vector3.UP * 1.1
	var shot := projectile_scene.instantiate() as Node3D
	scene.add_child(shot)
	shot.global_position = origin
	if shot.has_method("launch"):
		shot.call("launch", (target - origin).normalized(), projectile_speed, damage)


func _play_attack_anim() -> void:
	if _anim == null or attack_anim == &"" or not _anim.has_animation(attack_anim):
		return
	_anim.stop()
	_anim.play(attack_anim)
	_anim.speed_scale = 1.0


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name != attack_anim or _dead:
		return
	_attacking = false
	_play_locomotion()


# --- Visuals ----------------------------------------------------------------

func _update_visual(delta: float) -> void:
	if _rise < 1.0:
		_rise = minf(1.0, _rise + delta * 1.8)
		_model.position.y = lerpf(-1.6, hover_height, ease(_rise, 0.4))
		return

	if _uses_descent_flight():
		_model.position.y = sin(Time.get_ticks_msec() * 0.0024) * 0.08
	elif hover_height > 0.0:
		var bob := 0.07 + minf(hover_height * 0.05, 0.1)
		_model.position.y = hover_height + sin(Time.get_ticks_msec() * 0.002) * bob

	var speed := Vector2(velocity.x, velocity.z).length()
	if _anim and not _attacking:
		if sync_anim_speed:
			_anim.speed_scale = clampf(speed / maxf(move_speed, 0.1), 0.55, 1.6) * anim_speed
		_play_locomotion(speed)

	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 5.0)
	_apply_flash()


func _play_locomotion(speed: float = -1.0) -> void:
	if _anim == null:
		return
	if speed < 0.0:
		speed = Vector2(velocity.x, velocity.z).length()
	if idle_anim != &"" and speed < 0.3 and _anim.has_animation(idle_anim):
		if _anim.current_animation != idle_anim:
			_anim.play(idle_anim)
		return
	if walk_anim != &"" and _anim.has_animation(walk_anim) and _anim.current_animation != walk_anim:
		_anim.play(walk_anim)


func _apply_flash() -> void:
	for entry in _surfaces:
		var mat: StandardMaterial3D = entry["material"]
		mat.albedo_color = (entry["base"] as Color).lerp(Color(1.0, 0.32, 0.2), _flash)


# --- Damage and death -------------------------------------------------------

func is_weak_point_hit(hit_position: Vector3) -> bool:
	"""Headshots: anything that lands at skull height on this enemy."""
	return hit_position.y - global_position.y >= head_zone_height


func take_damage(amount: float, hit_position: Vector3 = Vector3.ZERO, direction: Vector3 = Vector3.ZERO) -> void:
	if _dead:
		return
	var headshot := is_weak_point_hit(hit_position)
	health -= amount * (headshot_multiplier if headshot else 1.0)
	_flash = 1.0
	_apply_flash()
	if direction.length_squared() > 0.001:
		var force := knockback_force * (1.6 if headshot else 1.0)
		var push := Vector3(direction.x, 0.0, direction.z).normalized() * force
		velocity.x += push.x
		velocity.z += push.z
	_stagger = 0.2
	if health <= 0.0:
		_die()


func _drop_gems() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	for i in maxi(1, gem_count):
		var gem := XP_GEM.instantiate() as Area3D
		gem.set("xp_value", gem_xp_value)
		gem.set("tier", gem_tier)
		gem.set("size_scale", gem_size)
		gem.set("gem_color", gem_color)
		var spread := Vector3.ZERO
		if gem_count > 1:
			var angle := TAU * float(i) / float(gem_count)
			# Big boss crystals need a wider ring, otherwise they merge visually.
			var ring_radius := maxf(0.7, gem_size * 0.75)
			spread = Vector3(cos(angle), 0.0, sin(angle)) * ring_radius
		# Place before entering the tree, same rule as the impact effect.
		gem.position = scene.to_local(global_position + Vector3.UP * 0.6 + spread)
		scene.add_child(gem)


func _die() -> void:
	_dead = true
	_attacking = false
	remove_from_group("enemies")  # stops counting as a live target immediately
	died.emit(self)
	collision_layer = 0
	collision_mask = 1  # still rests on the floor while fading out
	if _anim:
		_anim.stop()

	_drop_gems()

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_model, "rotation:x", deg_to_rad(-85.0), 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_model, "position:y", 0.0, 0.45)
	for entry in _surfaces:
		var mat: StandardMaterial3D = entry["material"]
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tween.tween_property(mat, "albedo_color:a", 0.0, 0.9).set_delay(1.1)

	await get_tree().create_timer(2.2).timeout
	queue_free()


# --- Helpers ----------------------------------------------------------------

func _dress_materials() -> void:
	# One material copy per surface, so the hit flash and the death fade stay
	# local to this enemy even when the model has a dozen materials.
	for mi in _mesh_instances(_model):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i)
			if mat is not StandardMaterial3D:
				continue
			var copy := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			if not is_equal_approx(albedo_boost, 1.0):
				copy.albedo_color = Color(
					copy.albedo_color.r * albedo_boost,
					copy.albedo_color.g * albedo_boost,
					copy.albedo_color.b * albedo_boost,
					copy.albedo_color.a)
			if _tint != Color.WHITE:
				copy.albedo_color = Color(
					copy.albedo_color.r * _tint.r,
					copy.albedo_color.g * _tint.g,
					copy.albedo_color.b * _tint.b,
					copy.albedo_color.a)
			mi.set_surface_override_material(i, copy)
			_surfaces.append({
				"mesh": mi,
				"index": i,
				"material": copy,
				"base": copy.albedo_color,
			})


func _setup_animations() -> void:
	if _anim == null:
		return
	var walk := _anim.get_animation(walk_anim) if walk_anim != &"" else null
	if walk:
		walk.loop_mode = Animation.LOOP_LINEAR
	var idle := _anim.get_animation(idle_anim) if idle_anim != &"" else null
	if idle:
		idle.loop_mode = Animation.LOOP_LINEAR
	var attack := _anim.get_animation(attack_anim) if attack_anim != &"" else null
	if attack:
		attack.loop_mode = Animation.LOOP_NONE
	_anim.animation_finished.connect(_on_animation_finished)
	_anim.speed_scale = anim_speed
	_play_locomotion()


func _separation() -> Vector3:
	var push := Vector3.ZERO
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or not is_instance_valid(other):
			continue
		var delta: Vector3 = global_position - (other as Node3D).global_position
		delta.y = 0.0
		var distance := delta.length()
		if distance > 0.001 and distance < separation_radius:
			push += delta / distance * (1.0 - distance / separation_radius)
	return push * separation_strength


func _find_anim(node: Node) -> AnimationPlayer:
	if node == null:
		return null
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_anim(child)
		if found:
			return found
	return null


func _mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node == null:
		return found
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		found.append(node as MeshInstance3D)
	for child in node.get_children():
		found.append_array(_mesh_instances(child))
	return found
