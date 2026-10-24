class_name EnemyBehavior
extends Node
## Add as a direct child of Enemy. Controls targeting, movement and attacks.
## Disable to create a passive enemy; other combat/damage systems still work.
signal state_changed(state: StringName)

@export var enabled: bool = true
@export_enum("Melee", "Ranged") var attack_style: int = 0
@export_range(0.0, 200.0, 0.5) var detection_range: float = 200.0
@export_range(0.05, 10.0, 0.05) var retarget_seconds: float = 0.5
@export_range(0.0, 30.0, 0.1) var turn_speed: float = 10.0
@export var movement_enabled: bool = true
@export var attacks_enabled: bool = true

var current_state: StringName = &"Idle"

func set_state(value: StringName) -> void:
	if value != current_state:
		current_state = value
		state_changed.emit(value)

func tick(enemy: Enemy, direction: Vector3, distance: float, delta: float) -> void:
	if not enabled or distance > detection_range:
		enemy.velocity.x = move_toward(enemy.velocity.x, 0.0, 14.0 * delta)
		enemy.velocity.z = move_toward(enemy.velocity.z, 0.0, 14.0 * delta)
		set_state(&"Idle")
		return
	if attack_style == 1:
		enemy._move_ranged(direction, distance, delta)
	else:
		enemy._move_melee(direction, distance, delta)
	if not movement_enabled:
		enemy.velocity.x = 0.0
		enemy.velocity.z = 0.0
	set_state(&"Attack" if enemy._attacking else (&"Move" if Vector2(enemy.velocity.x, enemy.velocity.z).length() > 0.1 else &"Idle"))
