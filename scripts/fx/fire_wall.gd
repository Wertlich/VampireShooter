extends Node3D
## Boss fire wall: a burning shell expands from the boss to `max_radius`.

@export var max_radius: float = 20.0
@export var wall_height: float = 4.0
@export var damage: float = 30.0
@export var expand_time: float = 1.15
@export var hold_time: float = 0.35
@export var fade_time: float = 0.55
@export var segments: int = 96

var _hit: Dictionary = {}
var _materials: Array[StandardMaterial3D] = []
var _lights: Array[OmniLight3D] = []


func _ready() -> void:
	add_to_group("fire_walls")
	_build_visual()
	scale = Vector3(0.12, 1.0, 0.12)

	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(max_radius, 1.0, max_radius), expand_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(hold_time)
	tween.tween_callback(_fade_out)


func _fade_out() -> void:
	var tween := create_tween().set_parallel(true)
	for material in _materials:
		tween.tween_property(material, "albedo_color:a", 0.0, fade_time)
	for light in _lights:
		tween.tween_property(light, "light_energy", 0.0, fade_time)
	tween.chain().tween_callback(queue_free)


func _process(_delta: float) -> void:
	var radius := scale.x
	for node in get_tree().get_nodes_in_group("player"):
		var player := node as Player
		if player == null or player.is_dead or _hit.has(player.get_instance_id()):
			continue
		var offset := player.global_position - global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance > max_radius or distance > radius:
			continue
		_hit[player.get_instance_id()] = true
		player.take_damage(damage, player.global_position + Vector3.UP,
			offset.normalized() if distance > 0.001 else Vector3.FORWARD)


func _build_visual() -> void:
	var outer := MeshInstance3D.new()
	outer.mesh = _ring_mesh(wall_height, true)
	outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var outer_material := _fire_material(Color(1.0, 0.22, 0.02, 0.48), 4.2)
	outer.material_override = outer_material
	_materials.append(outer_material)
	add_child(outer)

	var inner := MeshInstance3D.new()
	inner.mesh = _ring_mesh(wall_height * 0.58)
	inner.position.y = 0.02
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var inner_material := _fire_material(Color(1.0, 0.7, 0.18, 0.42), 5.5)
	inner.material_override = inner_material
	_materials.append(inner_material)
	add_child(inner)

	# Eight small lights ride the expanding ring through the parent's scale.
	for i in 8:
		var angle := TAU * float(i) / 8.0
		var light := OmniLight3D.new()
		light.position = Vector3(cos(angle), wall_height * 0.5, sin(angle))
		light.light_color = Color(1.0, 0.38, 0.08)
		light.light_energy = 0.0
		light.omni_range = 7.0
		light.shadow_enabled = false
		add_child(light)
		_lights.append(light)

	var tween := create_tween().set_parallel(true)
	for light in _lights:
		tween.tween_property(light, "light_energy", 3.5, expand_time)


func _ring_mesh(height: float, jagged: bool = false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var b0 := Vector3(cos(a0), 0.0, sin(a0))
		var b1 := Vector3(cos(a1), 0.0, sin(a1))
		var top0 := height
		var top1 := height
		if jagged:
			top0 *= 0.62 + 0.38 * (0.5 + 0.5 * sin(float(i) * 2.1))
			top1 *= 0.62 + 0.38 * (0.5 + 0.5 * sin(float(i + 1) * 2.1))
		var t0 := b0 + Vector3.UP * top0
		var t1 := b1 + Vector3.UP * top1
		var n0 := Vector3(cos(a0), 0.0, sin(a0))
		var n1 := Vector3(cos(a1), 0.0, sin(a1))

		st.set_normal(n0)
		st.add_vertex(b0)
		st.set_normal(n0)
		st.add_vertex(t0)
		st.set_normal(n1)
		st.add_vertex(t1)

		st.set_normal(n0)
		st.add_vertex(b0)
		st.set_normal(n1)
		st.add_vertex(t1)
		st.set_normal(n1)
		st.add_vertex(b1)
	return st.commit()


func _fire_material(colour: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = colour
	material.emission_enabled = true
	material.emission = Color(1.0, 0.28, 0.03)
	material.emission_energy_multiplier = energy
	return material
