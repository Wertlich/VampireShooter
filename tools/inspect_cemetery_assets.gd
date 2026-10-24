extends SceneTree

# Prints the imported bounds of the cemetery kit so map placement uses real
# sizes instead of guessed ones. Also reports the grass-field resource type.
# Usage: godot --headless --path . --script res://tools/inspect_cemetery_assets.gd

const DIRS := [
	"res://models/cemetery/graves",
	"res://models/cemetery/props",
]


func _initialize() -> void:
	for dir_path in DIRS:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		print("=== ", dir_path, " ===")
		for file_name in dir.get_files():
			if not (file_name.ends_with(".fbx") or file_name.ends_with(".glb")):
				continue
			await _report(dir_path.path_join(file_name))
	quit()


func _report(path: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		print("FAILED ", path)
		return
	var instance := packed.instantiate() as Node3D
	root.add_child(instance)
	await process_frame
	var bounds := AABB()
	var first := true
	var meshes := 0
	var materials: Array[String] = []
	for child in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		meshes += 1
		var mesh_aabb: AABB = mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
		if first:
			bounds = mesh_aabb
			first = false
		else:
			bounds = bounds.merge(mesh_aabb)
		for i in mesh_instance.mesh.get_surface_count():
			var mat := mesh_instance.get_active_material(i)
			var label := "<none>" if mat == null else mat.resource_path.get_file()
			if label not in materials:
				materials.append(label)
	print("%-52s meshes=%-2d min=%s max=%s size=%s mats=%s" % [
		path.get_file(), meshes, bounds.position, bounds.end, bounds.size, materials])
	instance.queue_free()
	await process_frame
