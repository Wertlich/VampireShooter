class_name Viewmodel
extends CanvasLayer
## Renders the first-person weapons in their own SubViewport.
##
## A dedicated viewport with a narrower FOV gives the guns the proper
## "hand-held" look, keeps them from clipping into walls and lets them be lit
## separately from the world. Only one weapon is visible at a time.

@onready var weapon_holder: Node3D = $Container/Viewport/Camera/WeaponHolder
@onready var weapons: Array[Weapon] = [
	$Container/Viewport/Camera/WeaponHolder/Revolver,
	$Container/Viewport/Camera/WeaponHolder/Shotgun,
	$Container/Viewport/Camera/WeaponHolder/AKM,
	$Container/Viewport/Camera/WeaponHolder/SVD,
	$Container/Viewport/Camera/WeaponHolder/RPD,
	$Container/Viewport/Camera/WeaponHolder/Saiga,
	$Container/Viewport/Camera/WeaponHolder/MP9,
]

var current: int = 0
## Weapons start locked; level-up cards unlock them (up to three per run).
var unlocked: Array[bool] = [true, false, false, false, false, false, false]
## 0 = hip fire pose, 1 = sights aligned. Driven by the player's aim button.
var aim_target: float = 0.0
var aim_blend: float = 0.0

var weapon: Weapon:
	get:
		return weapons[current] if current >= 0 and current < weapons.size() else null

var _hip_positions: Array[Vector3] = []
var _hip_rotations: Array[Vector3] = []
var _aim_rotations: Array[Vector3] = []


func _ready() -> void:
	# The container must not eat mouse input meant for the game.
	$Container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for w in weapons:
		_hip_positions.append(w.position)
		_hip_rotations.append(w.rotation)
		_aim_rotations.append(w.aim_rotation_degrees * (PI / 180.0))
	set_active(0)


func _process(delta: float) -> void:
	# Snap up fast, come down a little slower: that reads as "shouldering" the gun.
	var speed := 16.0 if aim_target > aim_blend else 10.0
	aim_blend = lerpf(aim_blend, aim_target, clampf(delta * speed, 0.0, 1.0))
	_apply_aim_pose()


func has_weapon(index: int) -> bool:
	return index >= 0 and index < weapons.size()


func is_unlocked(index: int) -> bool:
	return has_weapon(index) and index < unlocked.size() and unlocked[index]


func unlock(index: int) -> void:
	if has_weapon(index) and index < unlocked.size():
		unlocked[index] = true


func next_unlocked(from_index: int) -> int:
	for step in range(1, weapons.size() + 1):
		var index := (from_index + step) % weapons.size()
		if is_unlocked(index):
			return index
	return from_index


func set_active(index: int) -> void:
	if not is_unlocked(index):
		return
	current = index
	for i in weapons.size():
		var w: Weapon = weapons[i]
		var active := i == index
		w.visible = active
		# Holstered guns stay frozen: no recoil animation, no reload timer.
		w.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
		# reset_state() also cancels a reload in progress on the gun being put away.
		w.reset_state()
	_apply_aim_pose()


func _apply_aim_pose() -> void:
	for i in weapons.size():
		var w: Weapon = weapons[i]
		if i >= _hip_positions.size():
			continue
		w.position = _hip_positions[i].lerp(w.aim_position, aim_blend)
		w.rotation = _hip_rotations[i].lerp(_aim_rotations[i], aim_blend)
