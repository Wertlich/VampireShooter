class_name Player
extends CharacterBody3D
## First-person controller with head bob and view-model sway.

signal health_changed(current: float, maximum: float)
signal weapon_changed(weapon: Weapon)
signal xp_changed(current: float, needed: float, level: int)
signal level_up(new_level: int)
## Health reached zero. The arena listens to this to end the run.
signal died
## Cheat code toggled the player's immortality.
signal god_mode_changed(enabled: bool)

## ↑ ↑ ↓ ↓ ← → ← → B A — on the arrow keys, then the letters.
const CHEAT_CODE: Array[int] = [
	KEY_UP, KEY_UP, KEY_DOWN, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_LEFT, KEY_RIGHT, KEY_B, KEY_A,
]

@export_group("Movement")
@export var walk_speed: float = 5.2
@export var sprint_speed: float = 8.0
@export var ground_acceleration: float = 12.0
@export var ground_friction: float = 12.0
@export var jump_velocity: float = 6.0
@export var gravity: float = 18.0

@export_group("Bunny Hop")
## Air acceleration. Higher = easier to build speed by strafing in the air.
@export var air_accel: float = 14.0
## How much speed one air-strafe tick may add along the wish direction.
@export var air_wish_speed: float = 2.0
## Hard ceiling for horizontal speed gained while hopping.
@export var max_air_speed: float = 14.0
## Every chained hop multiplies horizontal speed by this much (1.05 = +5%).
@export var hop_speed_gain: float = 1.05
## Hold jump to keep hopping on landing instead of tapping it.
@export var auto_bhop: bool = true
## Grounded time after which the hop streak resets.
@export var hop_streak_timeout: float = 0.35

@export_group("Ladders")
## Vertical speed while holding forward/jump inside a LadderZone.
@export var climb_speed: float = 3.4

@export_group("Look")
@export var mouse_sensitivity: float = 0.0021
@export var max_pitch_degrees: float = 88.0

@export_group("Camera Feel")
@export var base_fov: float = 78.0
@export var sprint_fov: float = 83.0
@export var bob_amount: float = 0.022
@export var bob_speed: float = 9.0

@export_group("Aim Down Sights")
@export var aim_fov: float = 62.0
@export var aim_sensitivity_scale: float = 0.62
@export var aim_speed_scale: float = 0.7

@export_group("Health")
@export var max_health: float = 100.0

var health: float = 100.0
var is_aiming: bool = false
## Which peer owns this player. Set by NetworkGame right after spawning.
var peer_id: int = 1
## Latest transform received from a remote owner.
var _remote_target: Vector3 = Vector3.ZERO
var _remote_yaw: float = 0.0
var _remote_pitch: float = 0.0
var _net_timer: float = 0.0
## Set once health hits zero: the run is over, but the body still falls.
var is_dead: bool = false
## Cheat: damage is ignored while this is on.
var god_mode: bool = false
## Cheat: every bullet kills whatever it touches (toggled with god mode).
var one_shot_kill: bool = false
## Experience curve: gems fill the bar, every level offers a card choice.
var xp: float = 0.0
var xp_to_next: float = 24.0
var level: int = 1
## Horizontal speed, exposed for the HUD speedometer.
var planar_speed: float = 0.0
## Consecutive bunny hops without stopping.
var hop_streak: int = 0
var _grounded_time: float = 0.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera
@onready var world_flash: OmniLight3D = $Head/Camera/WorldFlash
@onready var viewmodel: Viewmodel = $Viewmodel
@onready var weapon_holder: Node3D = viewmodel.weapon_holder
@onready var weapon: Weapon = viewmodel.weapon

var _pitch: float = 0.0
var _yaw: float = 0.0
## Trigger under the player's feet currently offering a climb.
var _ladder_zone: LadderZone
var _recoil_pitch: float = 0.0
var _recoil_yaw: float = 0.0
var _bob_time: float = 0.0
var _sway: Vector2 = Vector2.ZERO
var _holder_base_pos: Vector3
var _holder_base_rot: Vector3
var _fov: float = 78.0
var _flash_left: float = 0.0
var _camera_pos := Vector3.ZERO
var _punch: float = 0.0
var _camera_roll: float = 0.0
const SWITCH_TIME: float = 0.34
var _switch_left: float = 0.0
var _pending_weapon: int = -1
## Keys typed so far towards the cheat code.
var _cheat_progress: Array[int] = []


func configure(id: int) -> void:
	peer_id = id
	set_multiplayer_authority(id)


## True on the machine that controls this player (always true offline).
func is_local_player() -> bool:
	if not Net.is_online():
		return true
	return peer_id == multiplayer.get_unique_id()


func _ready() -> void:
	add_to_group("player")
	_yaw = rotation.y
	_pitch = head.rotation.x
	_fov = base_fov
	camera.fov = base_fov
	health = max_health

	if not is_local_player():
		_become_remote()
		return

	_holder_base_pos = weapon_holder.position
	_holder_base_rot = weapon_holder.rotation

	# Every weapon gets the aim camera and the shared player reactions; only the
	# active one ever fires, so connecting both is safe.
	for w in viewmodel.weapons:
		w.set_aim_camera(camera)
		w.camera_recoil.connect(_on_camera_recoil)
		w.fired.connect(_on_weapon_fired)
	weapon = viewmodel.weapon

	if DisplayServer.get_name() != "headless" and not "--capture" in OS.get_cmdline_user_args():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	health_changed.emit(health, max_health)


## Turns this node into a visible stand-in for another peer's player.
func _become_remote() -> void:
	$Head/Camera.current = false
	$Viewmodel.visible = false
	var avatar := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	avatar.mesh = capsule
	avatar.position = Vector3(0.0, 0.9, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.42, 0.52, 0.82)
	material.roughness = 0.7
	material.metallic = 0.1
	avatar.material_override = material
	add_child(avatar)
	_remote_target = global_position
	_remote_yaw = rotation.y
	set_physics_process(false)


@rpc("any_peer", "unreliable_ordered", "call_remote")
func net_state(state_position: Vector3, yaw: float, pitch: float) -> void:
	if is_local_player():
		return
	# Host-side sanity check: a peer cannot teleport across the castle.
	if multiplayer.is_server() and global_position.distance_to(state_position) > 15.0:
		return
	_remote_target = state_position
	_remote_yaw = yaw
	_remote_pitch = pitch


## The host tells the owning client what its health is now.
@rpc("any_peer", "reliable", "call_remote")
func net_health(value: float) -> void:
	if not is_local_player():
		return
	health = maxf(0.0, value)
	health_changed.emit(health, max_health)
	if health <= 0.0 and not is_dead:
		_die()


func _send_net_state() -> void:
	_net_timer += get_physics_process_delta_time()
	if _net_timer < 0.05:
		return
	_net_timer = 0.0
	rpc("net_state", global_position, rotation.y, _pitch)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := (event as InputEventMouseMotion).relative
		# Aiming slows the look speed down so the sights can be placed precisely.
		var sensitivity := mouse_sensitivity * lerpf(1.0, aim_sensitivity_scale, viewmodel.aim_blend)
		_yaw -= motion.x * sensitivity
		_pitch = clampf(
			_pitch - motion.y * sensitivity,
			deg_to_rad(-max_pitch_degrees),
			deg_to_rad(max_pitch_degrees)
		)
		_sway += motion * 0.0009
		_sway = _sway.limit_length(0.6)

	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			_track_cheat_code(key.physical_keycode)


## Collects key presses and toggles god mode when the whole code is typed.
func _track_cheat_code(code: int) -> void:
	var expected := CHEAT_CODE[_cheat_progress.size()]
	if code != expected:
		# Start over, but a wrong key may itself be the first key of the code.
		_cheat_progress.clear()
		if code == CHEAT_CODE[0]:
			_cheat_progress.append(code)
		return

	_cheat_progress.append(code)
	if _cheat_progress.size() < CHEAT_CODE.size():
		return

	_cheat_progress.clear()
	god_mode = not god_mode
	one_shot_kill = god_mode
	if god_mode:
		health = max_health
		health_changed.emit(health, max_health)
	god_mode_changed.emit(god_mode)


func _physics_process(delta: float) -> void:
	if is_dead:
		# No input, no shooting: just let the body settle on the floor.
		velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		planar_speed = 0.0
		return
	_handle_movement(delta)
	_handle_weapon_input()
	_apply_look(delta)
	_update_camera_feel(delta)
	if Net.is_online():
		_send_net_state()


func _process(delta: float) -> void:
	if not is_local_player():
		# Remote players are driven by snapshots from their owner.
		global_position = global_position.lerp(_remote_target, clampf(delta * 12.0, 0.0, 1.0))
		rotation.y = lerp_angle(rotation.y, _remote_yaw, clampf(delta * 12.0, 0.0, 1.0))
		head.rotation.x = lerp_angle(head.rotation.x, _remote_pitch, clampf(delta * 12.0, 0.0, 1.0))
		return
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_flash_left = 0.0
			world_flash.light_energy = 0.0


func _on_weapon_fired() -> void:
	# The real muzzle light lives in the view-model viewport; this one lights
	# the world around the player for the same split second.
	world_flash.light_energy = 9.0
	_flash_left = 0.06


## Called by a LadderZone when the player steps into it.
func enter_ladder(zone: LadderZone) -> void:
	_ladder_zone = zone


## Called by a LadderZone when the player leaves it.
func exit_ladder(zone: LadderZone) -> void:
	if _ladder_zone == zone:
		_ladder_zone = null


func _handle_climb() -> bool:
	if _ladder_zone == null or not is_instance_valid(_ladder_zone):
		_ladder_zone = null
		return false
	var wants_up := Input.is_action_pressed("move_forward") \
			or Input.is_action_pressed("jump")
	var wants_down := Input.is_action_pressed("move_back")
	if not wants_up and not wants_down:
		return false
	# Step off onto the landing instead of climbing into the loft ceiling.
	if wants_up and _ladder_zone.exit_height > 0.0 \
			and global_position.y >= _ladder_zone.exit_height - 0.05 \
			and _ladder_zone.exit_direction.length_squared() > 0.01:
		velocity.y = 0.0
		velocity.x = _ladder_zone.exit_direction.x * 2.4
		velocity.z = _ladder_zone.exit_direction.z * 2.4
		move_and_slide()
		planar_speed = 0.0
		return true
	velocity.y = climb_speed if wants_up else -climb_speed
	# Stay in the trigger column while climbing. Moving forward here would
	# leave the Area3D before the player reaches the top.
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()
	planar_speed = 0.0
	return true


func _handle_movement(delta: float) -> void:
	if _handle_climb():
		return
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var speed_scale := lerpf(1.0, aim_speed_scale, viewmodel.aim_blend)
	# Heavy guns (the RPD) slow the owner down; switching back restores speed at once.
	if weapon:
		speed_scale *= weapon.move_speed_multiplier

	if is_on_floor():
		_grounded_time += delta
		if _grounded_time > hop_streak_timeout and hop_streak > 0:
			hop_streak = 0

		# Jump before applying ground friction: that is what lets a bunny hop
		# keep the speed it built up in the air.
		var wants_jump := Input.is_action_just_pressed("jump") \
			or (auto_bhop and Input.is_action_pressed("jump"))
		if wants_jump:
			velocity.y = jump_velocity
			hop_streak += 1
			_grounded_time = 0.0
			# Chained hops keep the momentum going and add a little on top, so a
			# clean chain visibly accelerates even without perfect strafing.
			if hop_streak >= 2:
				var flat := Vector2(velocity.x, velocity.z)
				var flat_speed := flat.length()
				if flat_speed > 0.2:
					var grown := minf(flat_speed * hop_speed_gain, max_air_speed)
					flat = flat / flat_speed * grown
					velocity.x = flat.x
					velocity.z = flat.y
		else:
			var sprinting := Input.is_action_pressed("sprint") and input_dir.y < 0.0
			var target_speed := (sprint_speed if sprinting else walk_speed) * speed_scale
			if direction.length_squared() > 0.001:
				velocity.x = move_toward(velocity.x, direction.x * target_speed, ground_acceleration * delta)
				velocity.z = move_toward(velocity.z, direction.z * target_speed, ground_acceleration * delta)
			else:
				velocity.x = move_toward(velocity.x, 0.0, ground_friction * delta)
				velocity.z = move_toward(velocity.z, 0.0, ground_friction * delta)
	else:
		# Classic strafe-jump acceleration: only acceleration along the wish
		# direction is limited, so turning while strafing keeps adding speed.
		if direction.length_squared() > 0.001:
			var current := Vector2(velocity.x, velocity.z).dot(Vector2(direction.x, direction.z))
			var add_speed := air_wish_speed - current
			if add_speed > 0.0:
				var accel := minf(air_accel * delta * air_wish_speed, add_speed)
				velocity.x += direction.x * accel
				velocity.z += direction.z * accel
		velocity.y -= gravity * delta

		var air_speed := Vector2(velocity.x, velocity.z).length()
		if air_speed > max_air_speed:
			var scale := max_air_speed / air_speed
			velocity.x *= scale
			velocity.z *= scale

	move_and_slide()
	planar_speed = Vector2(velocity.x, velocity.z).length()


func _handle_weapon_input() -> void:
	if Input.is_action_just_pressed("weapon_1"):
		switch_to(0)
	if Input.is_action_just_pressed("weapon_2"):
		switch_to(1)
	if Input.is_action_just_pressed("weapon_3"):
		switch_to(2)
	if Input.is_action_just_pressed("weapon_4"):
		switch_to(3)
	if Input.is_action_just_pressed("weapon_5"):
		switch_to(4)
	if Input.is_action_just_pressed("weapon_6"):
		switch_to(5)
	if Input.is_action_just_pressed("weapon_7"):
		switch_to(6)
	if Input.is_action_just_pressed("weapon_next") and viewmodel.weapons.size() > 0:
		switch_to(viewmodel.next_unlocked(viewmodel.current))

	# Aim while the right button is held (not during a weapon swap).
	is_aiming = Input.is_action_pressed("aim") and _switch_left <= 0.0
	viewmodel.aim_target = 1.0 if is_aiming else 0.0
	if weapon:
		weapon.is_aiming = is_aiming

	if weapon == null or _switch_left > 0.0:
		return
	if weapon.automatic:
		if Input.is_action_pressed("fire"):
			weapon.pull_trigger()
	elif Input.is_action_just_pressed("fire"):
		weapon.pull_trigger()

	if Input.is_action_just_pressed("reload"):
		weapon.reload()


func switch_to(index: int) -> void:
	if not viewmodel.is_unlocked(index) or index == viewmodel.current or _switch_left > 0.0:
		return
	_pending_weapon = index
	_switch_left = SWITCH_TIME


func _apply_look(delta: float) -> void:
	_recoil_pitch = lerpf(_recoil_pitch, 0.0, clampf(delta * 6.5, 0.0, 1.0))
	_recoil_yaw = lerpf(_recoil_yaw, 0.0, clampf(delta * 6.5, 0.0, 1.0))

	rotation.y = _yaw
	head.rotation.x = clampf(
		_pitch + _recoil_pitch,
		deg_to_rad(-max_pitch_degrees),
		deg_to_rad(max_pitch_degrees)
	)
	head.rotation.y = _recoil_yaw


func _update_camera_feel(delta: float) -> void:
	var target_fov := base_fov
	# FOV follows the real speed, so a good bunny-hop chain visibly stretches
	# the view instead of just feeling faster.
	if planar_speed > walk_speed:
		var t := clampf((planar_speed - walk_speed) / maxf(sprint_speed - walk_speed, 0.1), 0.0, 1.0)
		target_fov = lerpf(base_fov, sprint_fov, t)
	if planar_speed > sprint_speed:
		target_fov += clampf((planar_speed - sprint_speed) * 1.2, 0.0, 7.0)
	if is_aiming:
		target_fov = aim_fov
	var fov_speed := 14.0 if is_aiming or target_fov < _fov else 6.0
	_fov = lerpf(_fov, target_fov, clampf(delta * fov_speed, 0.0, 1.0))
	camera.fov = _fov

	# Head bob only while walking on the ground, and it calms down when aiming.
	var moving := planar_speed > 0.4 and is_on_floor()
	if moving:
		_bob_time += delta * bob_speed * clampf(planar_speed / walk_speed, 0.5, 1.5)
	var bob_strength := clampf(planar_speed / walk_speed, 0.0, 1.2) if moving else 0.0
	bob_strength *= lerpf(1.0, 0.3, viewmodel.aim_blend)
	var bob := Vector3(
		cos(_bob_time * 0.5) * bob_amount * 0.6 * bob_strength,
		sin(_bob_time) * bob_amount * bob_strength,
		0.0
	)
	_camera_pos = _camera_pos.lerp(bob, clampf(delta * 10.0, 0.0, 1.0))
	_punch = lerpf(_punch, 0.0, clampf(delta * 11.0, 0.0, 1.0))
	camera.position = _camera_pos + Vector3(0.0, 0.0, _punch)

	# Bank into lateral movement; in the air the lean is much stronger, which
	# sells the speed of a good strafe.
	var lateral := velocity.dot(transform.basis.x)
	var target_roll := clampf(-lateral * 0.013, -0.1, 0.1)
	if is_on_floor():
		target_roll *= 0.3
	_camera_roll = lerpf(_camera_roll, target_roll, clampf(delta * 8.0, 0.0, 1.0))
	head.rotation.z = _camera_roll

	# Weapon sways behind the mouse movement, then settles.
	_sway = _sway.lerp(Vector2.ZERO, clampf(delta * 8.0, 0.0, 1.0))

	# Swapping guns: dip the view model down, swap at the bottom, bring it back.
	var dip := 0.0
	if _switch_left > 0.0:
		_switch_left = maxf(0.0, _switch_left - delta)
		var progress := 1.0 - _switch_left / SWITCH_TIME
		dip = sin(clampf(progress, 0.0, 1.0) * PI) * 0.28
		if _pending_weapon >= 0 and progress >= 0.5:
			viewmodel.set_active(_pending_weapon)
			weapon = viewmodel.weapon
			_pending_weapon = -1
			weapon_changed.emit(weapon)

	# Aiming calms the sway so the sights stay where they were placed.
	var sway_scale := lerpf(1.0, 0.22, viewmodel.aim_blend)
	var holder_pos := _holder_base_pos + Vector3(
		-_sway.x * 0.06 * sway_scale,
		-_sway.y * 0.06 * sway_scale - dip,
		0.0
	)
	var holder_rot := _holder_base_rot + Vector3(
		_sway.y * 0.7 * sway_scale + dip * 1.1,
		_sway.x * 0.7 * sway_scale,
		_sway.x * 0.5 * sway_scale
	)
	weapon_holder.position = weapon_holder.position.lerp(holder_pos, clampf(delta * 12.0, 0.0, 1.0))
	weapon_holder.rotation = weapon_holder.rotation.lerp(holder_rot, clampf(delta * 12.0, 0.0, 1.0))


func _on_camera_recoil(pitch_degrees: float, yaw_degrees: float) -> void:
	_recoil_pitch += deg_to_rad(pitch_degrees)
	_recoil_yaw += deg_to_rad(yaw_degrees)
	# The viewmodel alone is not enough: shove the whole camera back a little so
	# the shot lands in the shoulders, not just on the screen.
	_punch = minf(_punch + deg_to_rad(pitch_degrees) * 0.014, 0.1)


## Restores health without going over the maximum. Used by the AKM lifesteal.
func heal(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	health = minf(max_health, health + amount)
	health_changed.emit(health, max_health)


func take_damage(amount: float, _hit_position: Vector3 = Vector3.ZERO, _direction: Vector3 = Vector3.ZERO) -> void:
	if is_dead or god_mode:
		return
	health = maxf(0.0, health - amount)
	health_changed.emit(health, max_health)
	# The host simulates the horde; the owning client needs its own health back.
	if Net.is_online() and not is_local_player():
		rpc_id(peer_id, "net_health", health)
	if health <= 0.0:
		_die()


func _die() -> void:
	is_dead = true
	health = 0.0
	is_aiming = false
	viewmodel.aim_target = 0.0
	if weapon:
		weapon.is_aiming = false
		weapon.reset_state()
	# Stop the controller updates so the death drop is not fought by head bob.
	set_physics_process(false)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(head, "position:y", 0.35, 0.85) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(head, "rotation:z", deg_to_rad(48.0), 0.85) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(camera, "fov", base_fov * 0.92, 0.85)
	died.emit()


func add_xp(amount: float) -> void:
	if is_dead:
		return
	xp += amount
	var leveled := false
	while xp >= xp_to_next:
		xp -= xp_to_next
		level += 1
		xp_to_next = roundf(xp_to_next * 1.35)
		leveled = true
	xp_changed.emit(xp, xp_to_next, level)
	if leveled:
		level_up.emit(level)
