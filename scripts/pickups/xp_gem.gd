extends Area3D
## Experience crystal dropped by an enemy. High-tier crystals are bigger and
## crimson; crystals dropped in mid-air fall to the floor before they can be
## magnetised into the player.

@export var xp_value: float = 8.0
@export var tier: int = 1
@export var gem_color: Color = Color(0.45, 0.95, 1.0, 1.0)
@export var magnet_radius: float = 5.5
@export var magnet_speed: float = 7.0
@export var fall_gravity: float = 22.0

var _player: Player
var _mesh: MeshInstance3D
var _time: float = 0.0
var _collected: bool = false
var _ground_y: float = 0.0
var _fall_speed: float = 0.0
var _falling: bool = true


func _ready() -> void:
	add_to_group("xp_gems")
	_player = get_tree().get_first_node_in_group("player") as Player
	_mesh = $Mesh as MeshInstance3D
	_apply_tier_look()
	_find_ground()
	body_entered.connect(_on_body_entered)
	_time = randf() * TAU


func _process(delta: float) -> void:
	if _collected:
		return
	_time += delta
	_mesh.rotation.y = _time * 2.2
	if _falling:
		_fall(delta)
		return

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


func _apply_tier_look() -> void:
	if _mesh == null:
		return
	scale = Vector3.ONE * (1.0 + 0.2 * float(maxi(0, tier - 1)))
	var material := _mesh.material_override as StandardMaterial3D
	if material == null:
		return
	var copy := material.duplicate() as StandardMaterial3D
	copy.albedo_color = gem_color
	copy.emission = gem_color
	copy.emission_energy_multiplier = 2.4 + 0.6 * float(tier)
	_mesh.material_override = copy


func _find_ground() -> void:
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.2,
		global_position + Vector3.DOWN * 30.0,
		1)  # world geometry
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	_ground_y = (hit["position"] as Vector3).y if not hit.is_empty() else 0.0
	if global_position.y <= _ground_y + 0.02:
		global_position.y = _ground_y
		_falling = false


func _fall(delta: float) -> void:
	_fall_speed -= fall_gravity * delta
	global_position.y += _fall_speed * delta
	if global_position.y <= _ground_y:
		global_position.y = _ground_y
		_fall_speed = 0.0
		_falling = false


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
