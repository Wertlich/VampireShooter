@tool
extends EditorScenePostImport
## The skeleton GLB ships without an embedded texture. Its atlas lives next to
## the model, so bind it to every surface at import time (editor and runtime).
## The imported "Attack" clip is also rebuilt into a fast one-arm claw swipe:
## the source clip reaches forward with both open palms, which reads as petting.

const MATERIAL := "res://models/skelet/textures/skeleton_material.tres"
const ATTACK_ANIM := "Attack"
const ATTACK_LENGTH := 0.85


func _post_import(scene: Node) -> Object:
	var material := load(MATERIAL) as Material
	if material == null:
		push_error("skeleton texture material missing: " + MATERIAL)
		return scene
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		mesh_instance.mesh = mesh_instance.mesh.duplicate()
		for i in mesh_instance.mesh.get_surface_count():
			mesh_instance.mesh.surface_set_material(i, material)
	_tune_attack(scene)
	return scene


func _tune_attack(scene: Node) -> void:
	var player := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null:
		return
	var anim := player.get_animation(ATTACK_ANIM)
	if anim == null:
		return

	var arm_r := _first_rotation(anim, "upper_arm.R")
	var arm_l := _first_rotation(anim, "upper_arm.L")
	var fore_r := _first_rotation(anim, "forearm.R")
	var fore_l := _first_rotation(anim, "forearm.L")
	var chest := _first_rotation(anim, "chest")
	var spine := _first_rotation(anim, "spine")
	if arm_r == null or arm_l == null or fore_r == null or fore_l == null \
			or chest == null or spine == null:
		push_error("skeleton Attack clip is missing a bone track")
		return

	# Right claw: load up and to the right, then rake down across the body.
	_override_rotation(anim, "upper_arm.R", [
		[0.0, arm_r],
		[0.16, _rot(arm_r, Vector3(0, 0, 1), 80.0, Vector3(0, 1, 0), -40.0)],
		[0.30, _rot(arm_r, Vector3(0, 1, 0), 140.0, Vector3(0, 0, 1), -40.0)],
		[0.42, _rot(arm_r, Vector3(0, 1, 0), 155.0, Vector3(0, 0, 1), -25.0)],
		[0.62, _rot(arm_r, Vector3(0, 1, 0), 70.0)],
		[ATTACK_LENGTH, arm_r],
	])
	# The left arm stays in a guard instead of joining the old two-hand push.
	_override_rotation(anim, "upper_arm.L", [[0.0, arm_l], [ATTACK_LENGTH, arm_l]])
	_override_rotation(anim, "forearm.L", [[0.0, fore_l], [ATTACK_LENGTH, fore_l]])
	# Start the elbow mostly straight and fold it slightly on the wind-up.
	_override_rotation(anim, "forearm.R", [
		[0.0, fore_r],
		[0.16, _rot(fore_r, Vector3(1, 0, 0), -35.0)],
		[0.30, fore_r],
		[0.42, _rot(fore_r, Vector3(0, 1, 0), 20.0)],
		[ATTACK_LENGTH, fore_r],
	])
	# Torso winds away from the swing and snaps back through it.
	_override_rotation(anim, "chest", [
		[0.0, chest],
		[0.16, _rot(chest, Vector3(0, 1, 0), -25.0)],
		[0.30, _rot(chest, Vector3(0, 1, 0), 30.0)],
		[0.42, _rot(chest, Vector3(0, 1, 0), 15.0)],
		[ATTACK_LENGTH, chest],
	])
	_override_rotation(anim, "spine", [
		[0.0, spine],
		[0.16, _rot(spine, Vector3(0, 1, 0), -10.0)],
		[0.30, _rot(spine, Vector3(0, 1, 0), 15.0)],
		[ATTACK_LENGTH, spine],
	])
	# A real lunge: pull back on the wind-up, drive in on the hit.
	_override_position(anim, "root", [
		[0.0, Vector3.ZERO],
		[0.16, Vector3(0, 0, -0.04)],
		[0.30, Vector3(0, -0.06, 0.22)],
		[0.45, Vector3(0, -0.02, 0.10)],
		[ATTACK_LENGTH, Vector3.ZERO],
	])
	anim.length = ATTACK_LENGTH


func _first_rotation(anim: Animation, bone: String) -> Variant:
	var track := _track(anim, bone, Animation.TYPE_ROTATION_3D)
	if track < 0 or anim.track_get_key_count(track) == 0:
		return null
	return anim.track_get_key_value(track, 0)


func _rot(base: Quaternion, axis_a: Vector3, angle_a: float,
		axis_b: Vector3, angle_b: float) -> Quaternion:
	return base * Quaternion(axis_a, deg_to_rad(angle_a)) \
		* Quaternion(axis_b, deg_to_rad(angle_b))


func _rot(base: Quaternion, axis: Vector3, angle: float) -> Quaternion:
	return base * Quaternion(axis, deg_to_rad(angle))


func _track(anim: Animation, bone: String, type: int) -> int:
	var suffix := ":" + bone
	for i in anim.get_track_count():
		if anim.track_get_type(i) == type and str(anim.track_get_path(i)).ends_with(suffix):
			return i
	return -1


func _override_rotation(anim: Animation, bone: String, keys: Array) -> void:
	var track := _track(anim, bone, Animation.TYPE_ROTATION_3D)
	if track < 0:
		return
	_clear(anim, track)
	for key in keys:
		anim.track_insert_key(track, key[0], key[1])


func _override_position(anim: Animation, bone: String, keys: Array) -> void:
	var track := _track(anim, bone, Animation.TYPE_POSITION_3D)
	if track < 0:
		return
	_clear(anim, track)
	for key in keys:
		anim.track_insert_key(track, key[0], key[1])


func _clear(anim: Animation, track: int) -> void:
	while anim.track_get_key_count(track) > 0:
		anim.track_remove_key(track, anim.track_get_key_count(track) - 1)
	anim.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
