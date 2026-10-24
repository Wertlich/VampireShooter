class_name Castle
extends Node3D
## The gothic castle map: loads the collision boxes and candle positions that
## the Blender generator wrote next to the GLB, and keeps the flames flickering.

const DATA_PATH := "res://models/castle/castle_data.json"

@export var candle_energy: float = 1.5
@export var candle_range: float = 6.0
@export var brazier_energy: float = 6.0
@export var brazier_range: float = 13.0
@export var flicker_amount: float = 0.22

var _lights: Array[OmniLight3D] = []
var _base_energy: PackedFloat32Array = []
var _phase: PackedFloat32Array = []
var _speed: PackedFloat32Array = []
var _time: float = 0.0


func _ready() -> void:
	if has_node("MapCollision") and has_node("Lights"):
		for child in $Lights.get_children():
			if child is OmniLight3D:
				_lights.append(child)
				_base_energy.append(child.light_energy)
				_phase.append(randf() * TAU)
				_speed.append(3.0 + randf_range(-0.6, 0.6))
		return
	var data := _load_data()
	if data.is_empty():
		return
	_build_collision(data)
	_build_lights(data)


func _process(delta: float) -> void:
	_time += delta
	for i in _lights.size():
		var flicker := 1.0 + flicker_amount * (
			sin(_time * _speed[i] + _phase[i])
			+ 0.6 * sin(_time * _speed[i] * 2.7 + _phase[i] * 1.7)
		) * 0.5
		_lights[i].light_energy = _base_energy[i] * flicker


func _load_data() -> Dictionary:
	if not FileAccess.file_exists(DATA_PATH):
		push_error("castle data missing: " + DATA_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if parsed is not Dictionary:
		push_error("castle data is not valid JSON")
		return {}
	return parsed


## Blender is Z-up, Godot is Y-up: (x, y, z) -> (x, z, -y).
func _to_godot(v: Array) -> Vector3:
	return Vector3(float(v[0]), float(v[2]), -float(v[1]))


func _build_collision(data: Dictionary) -> void:
	var body := StaticBody3D.new()
	body.name = "MapCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	for entry in data.get("collision", []):
		var size: Array = entry["size"]
		var shape := BoxShape3D.new()
		# Size axes swap the same way the positions do.
		shape.size = Vector3(float(size[0]), float(size[2]), float(size[1]))

		var collider := CollisionShape3D.new()
		collider.shape = shape
		var pos: Array = entry["pos"]
		collider.position = _to_godot(pos)
		collider.rotation.y = -float(entry.get("rot_y", 0.0))
		body.add_child(collider)


func _build_lights(data: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Lights"
	add_child(root)

	for point in data.get("candles", []):
		_add_light(root, _to_godot(point), Color(1.0, 0.68, 0.36), candle_energy, candle_range, false, 3.0)
	for point in data.get("braziers", []):
		_add_light(root, _to_godot(point), Color(1.0, 0.52, 0.2), brazier_energy, brazier_range, true, 5.5)


func _add_light(root: Node3D, position: Vector3, color: Color, energy: float,
		range_m: float, shadows: bool, speed: float) -> void:
	var light := OmniLight3D.new()
	light.position = position
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_m
	light.omni_attenuation = 1.4
	light.shadow_enabled = shadows
	light.light_specular = 0.25
	root.add_child(light)

	_lights.append(light)
	_base_energy.append(energy)
	_phase.append(randf() * TAU)
	_speed.append(speed + randf_range(-0.6, 0.6))
