extends SceneTree

# Builds exact static collision for the brick walls / floors / roof of both
# churches. The wooden ladders and loft planks are intentionally excluded so
# the climb volumes and platform boxes can handle them separately.
# Usage: godot --headless --path . --script res://tools/build_church_trimesh.gd

const JOBS := [
	["res://models/cemetery/church/church_intact.glb",
			"res://models/cemetery/church/church_intact_trimesh.res"],
	["res://models/cemetery/church/church_ruined.glb",
			"res://models/cemetery/church/church_ruined_trimesh.res"],
]


func _initialize() -> void:
	for job in JOBS:
		var source: String = job[0]
		var target: String = job[1]
		_build(source, target)
	quit()


func _build(source: String, target: String) -> void:
	var packed := load(source) as PackedScene
	if packed == null:
		push_error("Cannot load " + source)
		return
	var instance := packed.instantiate()
	var mesh_instance: MeshInstance3D = null
	for child in instance.find_children("*", "MeshInstance3D", true, false):
		mesh_instance = child as MeshInstance3D
		break
	if mesh_instance == null or mesh_instance.mesh == null:
		push_error("No mesh in " + source)
		instance.free()
		return
	var mesh := mesh_instance.mesh
	var faces := PackedVector3Array()
	var surfaces := 0
	var skipped := 0
	for s in mesh.get_surface_count():
		var material := mesh.surface_get_material(s)
		var mat_name := material.resource_name.to_lower() if material else ""
		if "wood" in mat_name:
			continue
		var arrays := mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var triangle_indices := PackedInt32Array()
		if indices.is_empty():
			for i in vertices.size():
				triangle_indices.append(i)
		else:
			triangle_indices = indices
		var t := 0
		while t + 2 < triangle_indices.size():
			var a := vertices[triangle_indices[t]]
			var b := vertices[triangle_indices[t + 1]]
			var c := vertices[triangle_indices[t + 2]]
			var center := (a + b + c) / 3.0
			if _is_entrance_cutout(center):
				skipped += 1
			else:
				faces.append(a)
				faces.append(b)
				faces.append(c)
			t += 3
		surfaces += 1
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var err := ResourceSaver.save(shape, target)
	print("TRIMESH ", target, " surfaces=", surfaces, " vertices=", faces.size(),
			" skipped_entrance=", skipped, " err=", err)
	instance.free()


## Keep the stair/porch volume out of the exact mesh: the hand-built ramp and
## side wall boxes own that area, otherwise a CharacterBody3D gets stuck on the
## imported step edges right at the door.
func _is_entrance_cutout(point: Vector3) -> bool:
	return point.x > -9.0 and point.x < -3.6 \
			and point.y > -0.5 and point.y < 5.5 \
			and point.z > -4.0 and point.z < 4.0
