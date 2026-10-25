class_name ArenaBounds
extends Node3D
## Invisible walls around the map plus a keeper that puts back whatever escapes.
##
## The castle has its own walls, but the gates and the gaps between towers are
## open. Four invisible boxes close the arena, and a cheap periodic check
## rescues enemies that end up outside (knockback can throw them over a wall)
## and the player if they fall through the map.

@export var half_size: float = 1000.0
@export var wall_height: float = 16.0
@export var wall_thickness: float = 1.0
## How far past the walls something must be before it counts as escaped.
@export var escape_margin: float = 3.0
## Below this height the player has fallen out of the world.
@export var fall_limit: float = -8.0
@export var check_interval: float = 0.5

var _player: Player
var _respawn: Vector3
var _timer: float = 0.0
## How many bodies have been rescued so far (useful in tests).
var recovered: int = 0


func _ready() -> void:
	_build_walls()
	# The player is registered in its own _ready, which may run after this one.
	_bind_player.call_deferred()
	_timer = check_interval


func _bind_player() -> void:
	_player = get_tree().get_first_node_in_group("player") as Player
	if _player:
		_respawn = _player.global_position


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = check_interval
	force_check()


## Runs the escape check immediately. Used by `_process` and by tests.
func force_check() -> void:
	if _player == null or not is_instance_valid(_player):
		_bind_player()
	var center := global_position
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var body := enemy as CharacterBody3D
		if body == null:
			continue
		if not is_outside(body.global_position):
			continue
		# Back to the middle of the arena, spread out a little so a whole pack
		# thrown over the wall does not land in one point.
		body.global_position = center + Vector3(
			randf_range(-2.5, 2.5), 0.1, randf_range(-2.5, 2.5))
		body.velocity = Vector3.ZERO
		recovered += 1

	if _player and not _player.is_dead and is_outside(_player.global_position):
		_player.global_position = _respawn
		_player.velocity = Vector3.ZERO
		recovered += 1


func is_outside(position: Vector3) -> bool:
	if position.y < fall_limit:
		return true
	var local := position - global_position
	return absf(local.x) > half_size + escape_margin \
		or absf(local.z) > half_size + escape_margin


func wall_count() -> int:
	var walls := get_node_or_null("Walls")
	return walls.get_child_count() if walls else 0


func _build_walls() -> void:
	var body := StaticBody3D.new()
	body.name = "Walls"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	var span := half_size * 2.0 + wall_thickness * 2.0
	var specs := [
		# size, offset
		[Vector3(wall_thickness, wall_height, span), Vector3(half_size + wall_thickness * 0.5, wall_height * 0.5, 0.0)],
		[Vector3(wall_thickness, wall_height, span), Vector3(-half_size - wall_thickness * 0.5, wall_height * 0.5, 0.0)],
		[Vector3(span, wall_height, wall_thickness), Vector3(0.0, wall_height * 0.5, half_size + wall_thickness * 0.5)],
		[Vector3(span, wall_height, wall_thickness), Vector3(0.0, wall_height * 0.5, -half_size - wall_thickness * 0.5)],
	]
	for spec in specs:
		var shape := BoxShape3D.new()
		shape.size = spec[0]
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position = spec[1]
		body.add_child(collider)
