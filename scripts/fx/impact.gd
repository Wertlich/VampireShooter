extends Node3D
## Short-lived spark burst spawned where a hitscan ray lands.

@export var lifetime: float = 0.7

@onready var particles: CPUParticles3D = $Sparks
@onready var light: OmniLight3D = $FlashLight
@onready var sprite: MeshInstance3D = $FlashSprite

var _age: float = 0.0
var _glow_material: StandardMaterial3D


func _ready() -> void:
	particles.emitting = true
	light.light_energy = 3.5
	sprite.visible = true
	sprite.scale = Vector3.ONE * 0.06
	_glow_material = sprite.material_override as StandardMaterial3D


func _process(delta: float) -> void:
	_age += delta
	light.light_energy = maxf(0.0, light.light_energy - delta * 55.0)

	var k := clampf(_age / 0.12, 0.0, 1.0)
	sprite.scale = Vector3.ONE * lerpf(0.06, 0.26, k)
	if _glow_material:
		_glow_material.albedo_color.a = 1.0 - k

	if _age >= lifetime:
		queue_free()
