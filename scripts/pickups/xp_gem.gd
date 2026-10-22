extends Area3D
## Experience gem dropped by a killed skeleton. Bobs in place, gets pulled in
## when the player is close and disappears into the XP bar.

@export var xp_value: float = 8.0
@export var magnet_radius: float = 5.5
@export var magnet_speed: float = 7.0

var _player: Player
var _mesh: MeshInstance3D
var _time: float = 0.0
var _collected: bool = false


func _ready() -> void:
	add_to_group("xp_gems")
	_player = get_tree().get_first_node_in_group("player") as Player
	_mesh = $Mesh as MeshInstance3D
	body_entered.connect(_on_body_entered)
	_time = randf() * TAU


func _process(delta: float) -> void:
	if _collected:
		return
	_time += delta
	_mesh.rotation.y = _time * 2.2
	_mesh.position.y = 0.32 + sin(_time * 2.6) * 0.07

	if _player == null or not is_instance_valid(_player):
		return

	var target := _player.global_position + Vector3.UP * 1.1
	var distance := global_position.distance_to(target)
	if distance < magnet_radius:
		# Start slow, then snap in: feels like the gem "notices" you.
		var pull := magnet_speed * (1.0 + (magnet_radius - distance))
		global_position = global_position.move_toward(target, pull * delta)
	if distance < 0.9:
		_collect()


func _on_body_entered(body: Node) -> void:
	if body is Player:
		_collect()


func _collect() -> void:
	if _collected:
		return
	_collected = true
	if _player:
		_player.add_xp(xp_value)
	queue_free()
