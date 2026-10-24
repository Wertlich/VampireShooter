class_name LadderZone
extends Area3D
## A non-blocking trigger in front of a ladder. The Player component handles the
## actual vertical movement, so the trigger only has to report enter/exit.

## World-space direction of the landing, used to step off at the top.
@export var exit_direction: Vector3 = Vector3.ZERO
## World-space height at which the step-off starts.
@export var exit_height: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		(body as Player).enter_ladder(self)


func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		(body as Player).exit_ladder(self)
