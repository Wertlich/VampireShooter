extends Node3D
## Short-lived emissive beam used by the SVD piercing shot.

@export var lifetime: float = 0.22
@export var width: float = 0.018

var _age: float = 0.0
var _material: StandardMaterial3D


func setup(from: Vector3, to: Vector3) -> void:
	var direction := to - from
	var length := direction.length()
	if length < 0.02:
		queue_free()
		return
	global_position = (from + to) * 0.5
	global_basis = Basis(Quaternion(Vector3.UP, direction.normalized()))
	var beam := $Beam.mesh as CylinderMesh
	beam.height = length
	beam.top_radius = width
	beam.bottom_radius = width


func _ready() -> void:
	_material = $Beam.material_override as StandardMaterial3D


func _process(delta: float) -> void:
	_age += delta
	var fade := 1.0 - clampf(_age / lifetime, 0.0, 1.0)
	if _material:
		_material.albedo_color.a = fade
		_material.emission_energy_multiplier = 5.0 * fade
	if _age >= lifetime:
		queue_free()
