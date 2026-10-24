extends Node3D
## Short orange blast spawned by the revolver's headshot-kill card.

@export var lifetime: float = 0.42

@onready var flash: MeshInstance3D = $Flash
@onready var light: OmniLight3D = $Light

var _age: float = 0.0
var _flash_material: StandardMaterial3D
var _flash_scale: Vector3


func _ready() -> void:
	_flash_material = flash.material_override as StandardMaterial3D
	_flash_scale = flash.scale
	light.light_energy = 12.0


func _process(delta: float) -> void:
	_age += delta
	var grow := clampf(_age / 0.2, 0.0, 1.0)
	flash.scale = _flash_scale * lerpf(0.35, 3.6, ease(grow, 0.35))
	flash.rotation.z += delta * 1.7
	if _flash_material:
		_flash_material.albedo_color.a = 1.0 - grow
	light.light_energy = maxf(0.0, light.light_energy - delta * 30.0)
	if _age >= lifetime:
		queue_free()
