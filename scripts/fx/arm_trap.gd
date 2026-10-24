extends Node3D
## One skeleton arm bursting out of the ground under the boss's arm attack.

@export var damage: float = 14.0
@export var rise_time: float = 0.42
@export var active_time: float = 0.65
@export var sink_time: float = 0.5
@export var start_delay: float = 0.0

var _active: bool = false
var _hit: Dictionary = {}

@onready var pivot: Node3D = $Pivot
@onready var area: Area3D = $DamageArea
@onready var dust: CPUParticles3D = $Dust


func _ready() -> void:
	add_to_group("boss_arms")
	area.monitoring = false
	pivot.position.y = -2.7
	var tween := create_tween()
	if start_delay > 0.0:
		tween.tween_interval(start_delay)
	tween.tween_property(pivot, "position:y", 0.0, rise_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_activate)
	tween.tween_interval(active_time)
	tween.tween_callback(_deactivate)
	tween.tween_property(pivot, "position:y", -2.8, sink_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)


func _process(_delta: float) -> void:
	if not _active:
		return
	for body in area.get_overlapping_bodies():
		var player := body as Player
		if player == null or player.is_dead or _hit.has(player.get_instance_id()):
			continue
		_hit[player.get_instance_id()] = true
		var push := player.global_position - global_position
		push.y = 0.0
		player.take_damage(damage, player.global_position + Vector3.UP,
			push.normalized() if push.length() > 0.001 else Vector3.FORWARD)


func _activate() -> void:
	_active = true
	area.monitoring = true
	dust.emitting = true


func _deactivate() -> void:
	_active = false
	area.monitoring = false
