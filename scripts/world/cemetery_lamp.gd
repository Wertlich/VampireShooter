class_name CemeteryLamp
extends Node3D
## A reusable cemetery light: a warm flickering OmniLight3D plus an optional
## hanging chain. The model itself is a child so standing and hanging lamps can
## share the same behaviour without custom code per scene.

@export_group("Flame")
@export var enable_flicker: bool = true
@export var flicker_amount: float = 0.17
@export var flicker_speed: float = 4.6
@export var glow_pulse: float = 0.07
## Light energy does not need to be recalculated every rendered frame.
@export var flicker_update_rate: float = 20.0

@export_group("Hanging")
## 0 = standing lamp with no chain. Positive values extend a chain upward from
## `lamp_top` by this many metres.
@export var chain_length: float = 0.0
@export var lamp_top: float = 1.35

@onready var _light: OmniLight3D = $Light
@onready var _glow: MeshInstance3D = get_node_or_null("Glow") as MeshInstance3D
@onready var _chain: MeshInstance3D = get_node_or_null("Chain") as MeshInstance3D

var _base_energy: float = 1.0
var _phase: float = 0.0
var _speed: float = 1.0
var _time: float = 0.0
var _flicker_accumulator: float = 0.0
var _base_glow_scale: Vector3 = Vector3.ONE


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(global_position) ^ hash(name)
	_phase = rng.randf() * TAU
	_speed = flicker_speed + rng.randf_range(-0.45, 0.45)
	_base_energy = _light.light_energy
	if _glow:
		_base_glow_scale = _glow.scale
	_configure_chain()


func _configure_chain() -> void:
	if _chain == null:
		return
	_chain.visible = chain_length > 0.02
	if not _chain.visible:
		return
	_chain.position.y = lamp_top + chain_length * 0.5
	_chain.scale = Vector3(1.0, chain_length, 1.0)


func _process(delta: float) -> void:
	if not enable_flicker:
		return
	_time += delta
	_flicker_accumulator += delta
	if _flicker_accumulator < 1.0 / maxf(flicker_update_rate, 1.0):
		return
	_flicker_accumulator = 0.0
	var value := sin(_time * _speed + _phase) + 0.55 * sin(_time * _speed * 2.37 + _phase * 1.7)
	var flicker := 1.0 + flicker_amount * value * 0.5
	_light.light_energy = _base_energy * flicker
	if _glow:
		var pulse := 1.0 + glow_pulse * sin(_time * _speed * 1.8 + _phase)
		_glow.scale = _base_glow_scale * pulse
