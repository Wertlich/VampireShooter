class_name LadderZone
extends Area3D
## A non-blocking trigger in front of a ladder. The Player component handles the
## actual vertical movement, so the trigger only has to report enter/exit.

## Direction to the landing in the ladder scene's local space.
@export var exit_direction: Vector3 = Vector3.ZERO
## How far above this trigger's centre the step-off starts.
@export var exit_height_offset: float = 2.05
var _exit_direction_world := Vector3.ZERO


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	_exit_direction_world = (global_transform.basis * exit_direction).normalized()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## World-space direction from the ladder to its landing.
func get_exit_direction() -> Vector3:
	return _exit_direction_world


## World-space height where the player should step off.
func get_exit_height() -> float:
	return global_position.y + exit_height_offset


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		(body as Player).enter_ladder(self)


func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		(body as Player).exit_ladder(self)
