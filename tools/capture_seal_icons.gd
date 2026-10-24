extends SceneTree

# Renders transparent inventory icons for the golden weapon seals.
# Usage (needs a window): godot --path . --script res://tools/capture_seal_icons.gd

const ICON_SIZE := Vector2i(512, 256)
const SOURCES := [
	["revolver", "res://scenes/weapon_revolver.tscn"],
	["shotgun", "res://scenes/weapon_shotgun.tscn"],
	["akm", "res://scenes/weapon_akm.tscn"],
	["svd", "res://scenes/weapon_svd.tscn"],
	["rpd", "res://scenes/weapon_rpd.tscn"],
	["saiga", "res://scenes/weapon_saiga.tscn"],
	["mp9", "res://scenes/weapon_mp9.tscn"],
]


func _initialize() -> void:
	var viewport := SubViewport.new()
	viewport.size = ICON_SIZE
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var world := Node3D.new()
	world.name = "IconWorld"
	viewport.add_child(world)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.76, 0.9)
	environment.ambient_light_energy = 0.9
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	world.add_child(world_env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38.0, -35.0, 0.0)
	key.light_color = Color(1.0, 0.92, 0.8)
	key.light_energy = 2.0
	key.shadow_enabled = false
	world.add_child(key)

	var rim := OmniLight3D.new()
	rim.position = Vector3(-1.0, 0.8, 1.4)
	rim.light_color = Color(0.55, 0.72, 1.0)
	rim.light_energy = 3.0
	rim.omni_range = 8.0
	world.add_child(rim)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	camera.near = 0.01
	camera.far = 200.0
	world.add_child(camera)

	var out_dir := ProjectSettings.globalize_path("res://assets/ui/seals")
	DirAccess.make_dir_recursive_absolute(out_dir)

	for entry in SOURCES:
		var name: String = entry[0]
		var path: String = entry[1]
		var weapon := (load(path) as PackedScene).instantiate() as Node3D
		world.add_child(weapon)
		await process_frame
		await process_frame
		var box := _mesh_bounds(weapon)
		if box.size.length() < 0.01:
			push_error("No meshes for %s" % name)
			weapon.queue_free()
			continue

		var radius := box.size.length() * 0.5
		var direction := Vector3(2.1, 0.75, 1.3).normalized()
		camera.size = maxf(radius * 1.2, 0.15)
		camera.position = box.get_center() + direction * radius * 4.0
		camera.look_at(box.get_center(), Vector3.UP)
		await RenderingServer.frame_post_draw
		var image := _trim_transparent(viewport.get_texture().get_image())
		var target := "%s/%s.png" % [out_dir, name]
		print("%-9s box=%s  -> %s (%s)" % [name, box.size.snapped(Vector3.ONE * 0.01),
			target, image.save_png(target)])
		weapon.queue_free()
		await process_frame

	quit()


## Crops the transparent margins so every gun fills its card evenly.
func _trim_transparent(image: Image) -> Image:
	var used := image.get_used_rect()
	if used.size.x < 1 or used.size.y < 1:
		return image
	var padded := used.grow(10)
	var bounds := Rect2i(Vector2i.ZERO, image.get_size())
	return image.get_region(padded.intersection(bounds))


func _mesh_bounds(node: Node) -> AABB:
	var box := AABB()
	var found := false
	for mesh in _meshes(node):
		var local: AABB = mesh.global_transform * mesh.get_aabb()
		box = local if not found else box.merge(local)
		found = true
	return box


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		found.append(node as MeshInstance3D)
	for child in node.get_children():
		found.append_array(_meshes(child))
	return found
