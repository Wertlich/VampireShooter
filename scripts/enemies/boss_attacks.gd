extends Node
## Special boss pattern: an expanding fire wall and three dense rows of
## skeleton arms bursting out of the ground in front of the boss.

const FIRE_WALL_SCENE := preload("res://scenes/fx/fire_wall.tscn")
const ARM_TRAP_SCENE := preload("res://scenes/fx/skeleton_arm_trap.tscn")

@export var first_attack_delay: float = 5.0
@export var attack_interval: float = 8.5
@export var fire_wall_radius: float = 20.0
@export var fire_wall_damage: float = 30.0
@export var arms_damage: float = 14.0
@export var arm_rows: int = 3
@export var arms_per_row: int = 15
@export var arms_start_distance: float = 2.0
@export var arms_end_distance: float = 14.0
@export var arms_spread: float = 8.0

var _cooldown: float = 0.0
var _next_is_wall: bool = true
var _boss: Enemy


func _ready() -> void:
	_boss = get_parent() as Enemy
	_cooldown = first_attack_delay
	if Net.is_online() and not multiplayer.is_server():
		set_process(false)


func _process(delta: float) -> void:
	if _boss == null or _boss.health <= 0.0 or _boss.is_queued_for_deletion():
		return
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	_cooldown = attack_interval
	if _next_is_wall:
		cast_fire_wall()
	else:
		cast_arms()
	_next_is_wall = not _next_is_wall


func cast_fire_wall() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var wall := FIRE_WALL_SCENE.instantiate() as Node3D
	wall.set("damage", fire_wall_damage)
	wall.set("max_radius", fire_wall_radius)
	scene.add_child(wall)
	wall.global_position = _boss.global_position + Vector3.UP * 0.05


func cast_arms() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var forward := _boss.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var rows := maxi(1, arm_rows)
	var spacing := (arms_spread * 2.0) / float(maxi(1, arms_per_row - 1))

	for row in rows:
		var row_t := float(row) / float(maxi(1, rows - 1))
		var forward_distance := lerpf(arms_start_distance, arms_end_distance, row_t)
		var row_offset := 0.0 if row % 2 == 0 else spacing * 0.5
		for i in arms_per_row:
			var lateral := -arms_spread + float(i) * spacing + row_offset
			lateral += randf_range(-0.28, 0.28)
			var spot := _boss.global_position + forward * forward_distance + right * lateral
			spot.y = _boss.global_position.y + 0.03
			var arm := ARM_TRAP_SCENE.instantiate() as Node3D
			arm.set("damage", arms_damage)
			arm.set("start_delay", row_t * 0.22 + absf(lateral) * 0.008
				+ randf_range(0.0, 0.08))
			scene.add_child(arm)
			arm.global_position = spot
			arm.rotation.y = atan2(forward.x, forward.z) + randf_range(-0.45, 0.45)
			arm.scale = Vector3.ONE * randf_range(0.85, 1.15)
