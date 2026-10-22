class_name Weapon
extends Node3D
## Base first-person weapon.
##
## Handles ammo, fire rate, hitscan, muzzle flash and all view-model "juice"
## (recoil kick, reload dip, cylinder spin). Any gun can reuse this script by
## changing the exported values, so adding the shotgun later is just a new scene.

signal ammo_changed(current: int, maximum: int)
signal reload_started(duration: float)
signal reload_finished
signal fired
signal camera_recoil(pitch_degrees: float, yaw_degrees: float)
## A bullet landed on an enemy. `headshot` is true for weak-point hits.
signal hit_enemy(headshot: bool)

const IMPACT_SCENE := preload("res://scenes/fx/impact.tscn")

@export_group("Identity")
@export var display_name: String = "Revolver"

@export_group("Damage")
@export var damage: float = 55.0
@export var max_range: float = 150.0
@export var pellets: int = 1

@export_group("Fire")
@export var automatic: bool = false
@export var fire_rate: float = 3.0
## Cone half-angle in degrees. 0 = perfectly accurate.
@export var spread_degrees: float = 0.35
@export var recoil_pitch: float = 2.4
@export var recoil_yaw: float = 0.55

@export_group("Ammo")
@export var max_ammo: int = 6
@export var reload_time: float = 2.1
@export var auto_reload: bool = true

@export_group("View Model Feel")
@export var kick_back: float = 0.055
@export var kick_up_degrees: float = 9.0
@export var kick_roll_degrees: float = 5.0
@export var flash_duration: float = 0.045

@export_group("Materials")
## Optional per-surface materials, in mesh surface order. When empty the
## imported FBX materials are used with a generic metal tweak.
@export var surface_materials: Array[Material] = []
## Allows the dual-wield modification (a second gun in the left hand).
@export var can_be_dual: bool = false
## Use the materials exactly as imported (models that already ship textures).
@export var keep_materials: bool = false
## Some FBX weapon exports bring a stray armature: clearing the skin binding
## makes the mesh render in its own space, so scale and rotation behave.
@export var strip_skinning: bool = false
## Rotates the model from its measured bounds: longest axis points -Z (barrel
## away), middle axis +Y (up), shortest axis +X. For models that arrived lying
## on their side.
@export var auto_orient: bool = false
## Flips auto-orientation 180° when the muzzle ends up facing the camera.
@export var auto_orient_flip: bool = false

@export_group("Aim Down Sights")
## View-model pose when aiming, in the weapon holder's space. The hip pose is
## whatever the weapon node has in the scene.
@export var aim_position: Vector3 = Vector3.ZERO
@export var aim_rotation_degrees: Vector3 = Vector3.ZERO
## Spread multiplier while aiming (0.35 = much tighter groups).
@export var aim_spread_multiplier: float = 0.35

var ammo: int = 0
var is_reloading: bool = false
## Set by the player while the aim button is held.
var is_aiming: bool = false
## Camera the hitscan originates from. Set by the player, because the weapon
## itself lives in the view-model SubViewport with its own camera.
var aim_camera: Camera3D

var _cooldown: float = 0.0
var _reload_left: float = 0.0
var _flash_left: float = 0.0
var _model: Node3D
## Second gun for the akimbo modification (dual MP9).
var _dual_model: Node3D
## Every muzzle marker in the scene; a dual-wield gun has two of them.
var _muzzles: Array[Marker3D] = []
var _flashes: Array[MeshInstance3D] = []
var _lights: Array[OmniLight3D] = []
var _muzzle_turn: int = 0
var _cylinder: Node3D
var _fire_sound: AudioStreamPlayer
var _dry_sound: AudioStreamPlayer
var _reload_sound: AudioStreamPlayer
var _headshot_sound: AudioStreamPlayer
var _base_model_pos: Vector3
var _base_model_rot: Vector3
var _dual_base_pos: Vector3
var _dual_base_rot: Vector3
var _cylinder_base_rot: float = 0.0
var _kick_pos: Vector3 = Vector3.ZERO
var _kick_rot: Vector3 = Vector3.ZERO


func _ready() -> void:
	_model = get_node_or_null("Model") as Node3D
	_cylinder = _find_by_name(_model, "Revolving_Cylinder") as Node3D
	_fire_sound = get_node_or_null("FireSound") as AudioStreamPlayer
	_dry_sound = get_node_or_null("DrySound") as AudioStreamPlayer
	_reload_sound = get_node_or_null("ReloadSound") as AudioStreamPlayer
	_headshot_sound = get_node_or_null("HeadshotSound") as AudioStreamPlayer

	if _model:
		_base_model_pos = _model.position
		_base_model_rot = _model.rotation
		if strip_skinning:
			_strip_skinning(_model)
		if auto_orient:
			_auto_orient()
		_dress_materials(_model)
	_collect_muzzles()
	if _cylinder:
		_cylinder_base_rot = _cylinder.rotation.z

	ammo = max_ammo
	ammo_changed.emit(ammo, max_ammo)


## Finds every muzzle in the weapon (two when the dual modification is on).
func _collect_muzzles() -> void:
	_muzzles.clear()
	_flashes.clear()
	_lights.clear()
	for marker in _markers(self):
		_muzzles.append(marker)
		_flashes.append(_find_by_name(marker, "MuzzleFlash") as MeshInstance3D)
		_lights.append(_find_by_name(marker, "MuzzleLight") as OmniLight3D)
	for flash in _flashes:
		if flash:
			flash.visible = false
	for light in _lights:
		if light:
			light.light_energy = 0.0


## Renders every mesh in its own space instead of being deformed by a skeleton.
func _strip_skinning(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).skeleton = NodePath()
	for child in node.get_children():
		_strip_skinning(child)


## Measures the meshes and rebuilds the "Body" transform so the gun points -Z.
func _auto_orient() -> void:
	var body := _model.get_node_or_null("Body") as Node3D
	if body == null:
		return
	var to_body := body.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for mesh in _mesh_list(_model):
		var local: Transform3D = to_body * mesh.global_transform
		var mesh_box: AABB = local * mesh.get_aabb()
		box = mesh_box if first else box.merge(mesh_box)
		first = false
	if first:
		return

	var size := box.size
	var order := [0, 1, 2]
	order.sort_custom(func(a: int, b: int) -> bool: return size[a] > size[b])
	# longest -> -Z (barrel), middle -> +Y (up), shortest -> +X (thickness)
	var targets := [Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)]
	var images := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	for rank in 3:
		images[order[rank]] = targets[rank]
	if auto_orient_flip:
		# Turn the gun around without standing it on its head: flip the barrel
		# axis and the (invisible) thickness axis so the determinant stays +1.
		images[order[0]] = -images[order[0]]
		images[order[2]] = -images[order[2]]
	var orient := Basis(images[0], images[1], images[2])
	if orient.determinant() < 0.0:
		# Mirroring the thin axis is invisible; mirroring up would flip the gun.
		images[order[2]] = -images[order[2]]
		orient = Basis(images[0], images[1], images[2])

	var current_scale: Vector3 = body.scale
	# Centre the model on the Body origin and lay it along the new axes.
	var centre: Vector3 = orient * (box.get_center() * current_scale)
	body.transform = Transform3D(orient * Basis.from_scale(current_scale), -centre)


func _mesh_list(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		found.append(node as MeshInstance3D)
	for child in node.get_children():
		found.append_array(_mesh_list(child))
	return found


func _markers(node: Node) -> Array[Marker3D]:
	var found: Array[Marker3D] = []
	if node is Marker3D and (node as Marker3D).name.begins_with("Muzzle"):
		found.append(node as Marker3D)
	for child in node.get_children():
		if child is Marker3D and (child as Marker3D).name.begins_with("Muzzle"):
			continue  # the flash/light markers live under a Muzzle already
		found.append_array(_markers(child))
	return found


## True once the akimbo modification is installed.
func is_dual() -> bool:
	return _dual_model != null


## Turns the gun into two: a mirrored copy on the left hand, alternating muzzle
## flashes and a doubled magazine.
func make_dual() -> bool:
	if not can_be_dual or _dual_model != null or _model == null:
		return false
	_dual_model = _model.duplicate() as Node3D
	if _dual_model == null:
		return false
	_dual_model.name = "ModelDual"
	add_child(_dual_model)
	_dual_base_pos = _base_model_pos + Vector3(-0.26, 0.015, 0.05)
	_dual_base_rot = _base_model_rot + Vector3(0.0, deg_to_rad(7.0), 0.0)
	_dual_model.position = _dual_base_pos
	_dual_model.rotation = _dual_base_rot
	_dual_model.scale = Vector3(-_model.scale.x, _model.scale.y, _model.scale.z)

	max_ammo *= 2
	ammo = max_ammo
	_collect_muzzles()
	ammo_changed.emit(ammo, max_ammo)
	return true


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_update_flash(delta)
	_update_reload(delta)
	_update_recoil(delta)


# --- Public API -------------------------------------------------------------

func pull_trigger() -> bool:
	"""Tries to fire once. Returns true when a round left the barrel."""
	if is_reloading or _cooldown > 0.0:
		return false
	if ammo <= 0:
		if _dry_sound:
			_dry_sound.pitch_scale = randf_range(0.94, 1.06)
			_dry_sound.play()
		if auto_reload:
			reload()
		return false

	ammo -= 1
	_cooldown = 1.0 / maxf(fire_rate, 0.01)
	_shoot()
	_kick()
	ammo_changed.emit(ammo, max_ammo)
	fired.emit()

	if ammo <= 0 and auto_reload:
		reload()
	return true


func reload() -> void:
	if is_reloading or ammo >= max_ammo:
		return
	is_reloading = true
	_reload_left = reload_time
	if _reload_sound:
		_reload_sound.pitch_scale = 1.0
		_reload_sound.play()
	reload_started.emit(reload_time)


func can_fire() -> bool:
	return not is_reloading and _cooldown <= 0.0 and ammo > 0


func cancel_reload() -> void:
	if not is_reloading:
		return
	is_reloading = false
	_reload_left = 0.0
	if _cylinder:
		_cylinder.rotation.z = _cylinder_base_rot
	if _reload_sound and _reload_sound.playing:
		_reload_sound.stop()


func reset_state() -> void:
	"""Puts the view model back to rest, used when the weapon is holstered."""
	cancel_reload()
	hide_flash()
	_kick_pos = Vector3.ZERO
	_kick_rot = Vector3.ZERO
	if _model:
		_model.position = _base_model_pos
		_model.rotation = _base_model_rot
	if _dual_model:
		_dual_model.position = _dual_base_pos
		_dual_model.rotation = _dual_base_rot


func set_aim_camera(camera: Camera3D) -> void:
	aim_camera = camera


func hide_flash() -> void:
	_flash_left = 0.0
	for flash in _flashes:
		if flash:
			flash.visible = false
	for light in _lights:
		if light:
			light.light_energy = 0.0


# --- Shooting ---------------------------------------------------------------

func _shoot() -> void:
	var camera := aim_camera
	if camera == null or not is_instance_valid(camera):
		camera = get_viewport().get_camera_3d()
	if camera == null:
		return

	var origin := camera.global_position
	var forward := -camera.global_transform.basis.z
	var space := camera.get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	var body := _owner_body()
	if body:
		exclude.append(body.get_rid())

	# The one-shot cheat turns any gun into a death ray.
	var dealt := damage
	if body is Player and (body as Player).one_shot_kill:
		dealt = 1.0e9

	var spread := spread_degrees * (aim_spread_multiplier if is_aiming else 1.0)

	# Online: the host resolves the shot so damage is authoritative.
	if Net.is_online():
		var game := get_tree().get_first_node_in_group("network_game")
		if game != null and game.has_method("request_shot"):
			game.call("request_shot", origin, forward, spread, pellets, dealt, max_range)
		return

	for i in pellets:
		var dir := _spread_direction(forward, spread)
		var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_range, 0b1101, exclude)
		query.collide_with_areas = false
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		_spawn_impact(hit["position"], hit["normal"])
		var collider: Object = hit["collider"]
		if collider and collider.has_method("take_damage"):
			collider.take_damage(dealt, hit["position"], dir)
			if collider is Node and collider.is_in_group("enemies"):
				var headshot: bool = collider.has_method("is_weak_point_hit") \
					and collider.is_weak_point_hit(hit["position"])
				if headshot and _headshot_sound:
					# Slightly different pitch every time so a streak does not
					# machine-gun the same sample.
					_headshot_sound.pitch_scale = randf_range(0.92, 1.08)
					_headshot_sound.play()
				hit_enemy.emit(headshot)


func _spread_direction(forward: Vector3, spread: float) -> Vector3:
	if spread <= 0.0:
		return forward
	var up := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var right := forward.cross(up).normalized()
	var real_up := right.cross(forward).normalized()
	var angle := deg_to_rad(spread) * sqrt(randf())
	var roll := randf() * TAU
	var offset := right * sin(roll) * tan(angle) + real_up * cos(roll) * tan(angle)
	return (forward + offset).normalized()


func _spawn_impact(position: Vector3, normal: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var fx := IMPACT_SCENE.instantiate() as Node3D
	# Place the effect BEFORE it enters the tree: _ready() starts the particle
	# emission, and anything emitted while the node still sits at the scene
	# origin would stay there (world-space particles) as a floating spark cloud.
	fx.position = scene.to_local(position + normal * 0.02)
	scene.add_child(fx)


func _owner_body() -> CharacterBody3D:
	var node := get_parent()
	while node:
		if node is CharacterBody3D:
			return node
		node = node.get_parent()
	return null


# --- View model animation ---------------------------------------------------

func _kick() -> void:
	_kick_pos.z += kick_back
	_kick_pos.y += kick_back * 0.15
	_kick_rot.x -= deg_to_rad(kick_up_degrees)
	_kick_rot.z += deg_to_rad(randf_range(-kick_roll_degrees, kick_roll_degrees))
	camera_recoil.emit(recoil_pitch * randf_range(0.85, 1.15), recoil_yaw * randf_range(-1.0, 1.0))

	if _fire_sound:
		_fire_sound.pitch_scale = randf_range(0.94, 1.05)
		_fire_sound.play()

	# Dual wield alternates the flash between the two muzzles.
	var slot := _muzzle_turn % _flashes.size() if not _flashes.is_empty() else -1
	_muzzle_turn += 1
	if slot >= 0:
		var flash := _flashes[slot]
		if flash:
			flash.visible = true
			flash.rotation.z = randf() * TAU
			flash.scale = Vector3.ONE * randf_range(0.85, 1.25)
		var light := _lights[slot] if slot < _lights.size() else null
		if light:
			light.light_energy = randf_range(4.0, 7.5)
			light.rotation.z = randf() * TAU
	_flash_left = flash_duration


func _update_flash(delta: float) -> void:
	if _flash_left <= 0.0:
		return
	_flash_left -= delta
	if _flash_left > 0.0:
		return
	hide_flash()


func _update_recoil(delta: float) -> void:
	if _model == null:
		return
	_kick_pos = _kick_pos.lerp(Vector3.ZERO, clampf(delta * 16.0, 0.0, 1.0))
	_kick_rot = _kick_rot.lerp(Vector3.ZERO, clampf(delta * 11.0, 0.0, 1.0))

	var dip := Vector3.ZERO
	var roll := 0.0
	if is_reloading:
		var progress := 1.0 - clampf(_reload_left / maxf(reload_time, 0.01), 0.0, 1.0)
		var curve := sin(progress * PI)
		dip = Vector3(0.0, -0.075 * curve, 0.02 * curve)
		roll = deg_to_rad(22.0) * curve

	_model.position = _base_model_pos + _kick_pos + dip
	var rotation := _base_model_rot + _kick_rot
	rotation.z += roll
	_model.rotation = rotation

	# The second gun follows the same recoil, mirrored to the other hand.
	if _dual_model:
		_dual_model.position = _dual_base_pos + _kick_pos + dip
		var dual_rotation := _dual_base_rot + _kick_rot
		dual_rotation.z += roll
		_dual_model.rotation = dual_rotation


func _update_reload(delta: float) -> void:
	if is_reloading == false:
		if _cylinder:
			_cylinder.rotation.z = _cylinder_base_rot
		return

	var duration := maxf(reload_time, 0.01)
	var progress := 1.0 - clampf(_reload_left / duration, 0.0, 1.0)
	if _cylinder:
		# Six chambers, six clicks: the cylinder turns a sixth of a turn at a time.
		var chambers := 6.0
		_cylinder.rotation.z = _cylinder_base_rot + TAU * floor(progress * chambers) / chambers

	_reload_left -= delta
	if _reload_left > 0.0:
		return

	_reload_left = 0.0
	is_reloading = false
	ammo = max_ammo
	if _cylinder:
		_cylinder.rotation.z = _cylinder_base_rot
	ammo_changed.emit(ammo, max_ammo)
	reload_finished.emit()


# --- Helpers ----------------------------------------------------------------

func _find_by_name(node: Node, wanted: String) -> Node:
	if node == null:
		return null
	if node.name == wanted:
		return node
	for child in node.get_children():
		var found := _find_by_name(child, wanted)
		if found:
			return found
	return null


func _dress_materials(root: Node) -> void:
	if keep_materials:
		for node in _mesh_list(root):
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return
	# The view-model guns are drawn with their own lights; shadows from such a
	# close model only produce flicker.
	for node in _mesh_list(root):
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not surface_materials.is_empty():
		_apply_surface_materials(root)
	else:
		# The FBX comes with flat imported materials: make the metal look like metal.
		_walk_meshes(root, {})


func _apply_surface_materials(root: Node) -> void:
	var meshes: Array[Node] = []
	_collect_meshes(root, meshes)
	var index := 0
	for node in meshes:
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			if index < surface_materials.size() and surface_materials[index] != null:
				mi.set_surface_override_material(i, surface_materials[index])
			index += 1


func _collect_meshes(node: Node, out: Array[Node]) -> void:
	if node is MeshInstance3D and node.mesh:
		out.append(node)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_collect_meshes(child, out)


func _walk_meshes(node: Node, seen: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh:
		var mesh: Mesh = node.mesh
		for i in mesh.get_surface_count():
			var mat: Material = node.get_active_material(i)
			if mat is StandardMaterial3D:
				var key: int = mat.get_instance_id()
				if not seen.has(key):
					var tweaked: StandardMaterial3D = mat.duplicate()
					tweaked.albedo_color = Color(0.74, 0.76, 0.8, 1)
					tweaked.metallic = 0.55
					tweaked.roughness = 0.4
					# A touch of self-illumination keeps the view model readable in
					# dark rooms without turning it into a glowing toy.
					tweaked.emission_enabled = true
					tweaked.emission_texture = tweaked.albedo_texture
					tweaked.emission_energy_multiplier = 0.18
					seen[key] = tweaked
				node.set_surface_override_material(i, seen[key])
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_walk_meshes(child, seen)
