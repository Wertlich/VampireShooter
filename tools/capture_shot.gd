extends SceneTree

# Debug helper: fires one shot from the default spawn view and saves frames
# before/after so the muzzle flash and impact effects can be inspected.
# Usage: godot --path . --script res://tools/capture_shot.gd

func _initialize() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene

	await create_timer(1.0).timeout
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))

	var player := scene.get_node("Player") as Player
	var args := OS.get_cmdline_user_args()
	var yaw := float(args[0]) if args.size() > 0 else 0.0
	player._yaw = deg_to_rad(yaw)
	player._pitch = 0.0
	await create_timer(0.25).timeout

	await _shot("dbg_01_before.png")

	var weapon: Weapon = player.weapon
	print("firing from ", player.camera.global_position, " dir ", -player.camera.global_transform.basis.z)
	var space := player.camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		player.camera.global_position,
		player.camera.global_position + -player.camera.global_transform.basis.z * 150.0
	)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		print("ray: no hit")
	else:
		print("ray hit collider=", hit["collider"], " at ", hit["position"], " normal ", hit["normal"])
	weapon.pull_trigger()
	await _shot("dbg_02_after.png")

	for child in scene.get_children():
		if child.name.begins_with("Impact"):
			print("impact node at ", child.global_position, " distance ", child.global_position.distance_to(player.camera.global_position))

	await create_timer(0.10).timeout
	await _shot("dbg_03_100ms.png")

	await create_timer(0.30).timeout
	await _shot("dbg_04_400ms.png")

	quit()


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://screenshots/") + file_name
	image.save_png(path)
	print("saved ", file_name)
