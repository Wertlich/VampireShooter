extends SceneTree

# Measures the revolver view model in camera space. Dev helper.
# Usage: godot --headless --path . --script res://tools/measure_weapon.gd

func _initialize() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var player := scene.get_node("Player") as Player
	var camera := player.camera
	var weapon := player.weapon
	var muzzle := weapon.get_node("Muzzle") as Node3D
	var flash := weapon.get_node("Muzzle/MuzzleFlash") as MeshInstance3D
	var barrel := weapon.find_child("Magnum_Barrel", true, false) as MeshInstance3D

	print("camera fov=", camera.fov, " keep_aspect=", camera.keep_aspect, " size=", get_root().size)
	print("weapon global=", weapon.global_position)
	print("muzzle global=", muzzle.global_position, " screen=", camera.unproject_position(muzzle.global_position))
	print("flash global=", flash.global_position, " screen=", camera.unproject_position(flash.global_position))

	if barrel:
		var xf := barrel.global_transform
		var box := barrel.get_aabb()
		var near_end := xf * box.position
		var far_end := xf * (box.position + box.size)
		print("barrel node global=", barrel.global_position)
		print("barrel aabb near=", near_end, " screen=", camera.unproject_position(near_end))
		print("barrel aabb far =", far_end, " screen=", camera.unproject_position(far_end))

	var model := weapon.get_node("Model") as Node3D
	print("model global transform=", model.global_transform)
	quit()
