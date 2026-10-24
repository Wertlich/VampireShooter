extends SceneTree

# Builds the separate cemetery group scenes from the imported kit, the two
# Blender-extracted church variants and the modular fence/lamp assets. Run:
#   godot --headless --path . --script res://tools/build_cemetery.gd

const OUT_DIR := "res://scenes/cemetery/groups"
const GROUND_MAT := preload("res://assets/cemetery/materials/grass_ground.tres")
const PATH_MAT := preload("res://assets/cemetery/materials/path_mud.tres")
const STONE_MAT := preload("res://assets/cemetery/materials/stone_palette.tres")
const PEW_MAT := preload("res://assets/cemetery/materials/pew_wood.tres")

const CHURCH_INTACT := preload("res://scenes/cemetery/church_intact.tscn")
const CHURCH_RUINED := preload("res://scenes/cemetery/church_ruined.tscn")
const STANDING_LAMP := preload("res://scenes/cemetery/standing_lamp.tscn")
const HANGING_LAMP := preload("res://scenes/cemetery/hanging_lamp.tscn")

const FENCE_SCENES: Array[PackedScene] = [
	preload("res://models/cemetery/fence/fence_a.glb"),
	preload("res://models/cemetery/fence/fence_b.glb"),
	preload("res://models/cemetery/fence/fence_c.glb"),
]

const GRAVE_PATHS := [
	"res://models/cemetery/graves/EA_Grave_Stone_Mini_01a.fbx",
	"res://models/cemetery/graves/EA_Grave_Stone_Mini_01e.fbx",
	"res://models/cemetery/graves/EA_Grave_Stone_Mini_02c.fbx",
	"res://models/cemetery/graves/EA_Grave_Broken_Half_01a.fbx",
	"res://models/cemetery/graves/EA_Grave_Broken_Half_01d.fbx",
	"res://models/cemetery/graves/EA_Grave_Broken_Full_01b.fbx",
	"res://models/cemetery/graves/EA_Grave_Modern_Mini_01b.fbx",
	"res://models/cemetery/graves/EA_Grave_Modern_Full_01c.fbx",
	"res://models/cemetery/graves/EA_Grave_Wooden_Mini_01a.fbx",
	"res://models/cemetery/graves/EA_Grave_Wooden_Mini_01c.fbx",
	"res://models/cemetery/graves/EA_Grave_WoodForm_01a.fbx",
]

const PROP_PATHS := {
	"archway": "res://models/cemetery/props/EA_Grave_Archway_Wood_01a.glb",
	"lantern": "res://models/cemetery/props/EA_Grave_Lantern_Stone_01a.glb",
	"logs": "res://models/cemetery/props/EA_Grave_LogPile_01a.glb",
	"obelisk": "res://models/cemetery/props/EA_Grave_Obelisk_01a.glb",
	"railing": "res://models/cemetery/props/EA_Grave_Railing_01a.glb",
	"slab": "res://models/cemetery/props/EA_Grave_Slab_Tall_01a.glb",
	"mud_flat": "res://models/cemetery/props/EA_Grave_Mud_Flat_01a.glb",
	"mud_plank": "res://models/cemetery/props/EA_Grave_Mud_Plank_01a.glb",
	"mud_post": "res://models/cemetery/props/EA_Grave_Mud_Post_01a.glb",
	"mud_stones": "res://models/cemetery/props/EA_Grave_Mud_Stones_01a.glb",
	"tomb": "res://models/cemetery/graves/EA_Grave_Tomb_01a.fbx",
	"columbarium": "res://models/cemetery/graves/EA_Grave_Columbarium_01a.fbx",
	"monu": "res://models/cemetery/graves/EA_Grave_Monu_01a.fbx",
	"arch": "res://models/cemetery/graves/EA_Grave_Arch_01a.fbx",
	"grave01": "res://models/cemetery/graves/EA_Grave_01a.fbx",
}

const TREE_DEAD := preload("res://models/trees/tree_dead.glb")
const SOFT_DOT := preload("res://assets/textures/soft_dot.png")

var scene: Node3D
var rng := RandomNumberGenerator.new()
var _grave_meshes: Dictionary = {}
var _prop_meshes: Dictionary = {}
var _name_index: int = 0
var _stone_rubble_mat: StandardMaterial3D
var _box_meshes: Dictionary = {}


func _initialize() -> void:
	rng.seed = 0x20261024
	_name_index = 0
	_stone_rubble_mat = StandardMaterial3D.new()
	_stone_rubble_mat.albedo_color = Color(0.17, 0.17, 0.16)
	_stone_rubble_mat.roughness = 0.95

	scene = Node3D.new()
	scene.name = "Cemetery"
	root.add_child(scene)

	_cache_meshes()
	_build_ground_and_paths()
	_build_fence()
	_build_graves()
	_build_churches()
	_build_lamps()
	_build_props()
	_build_trees()
	_build_fireflies()
	_build_prop_collisions()
	_save_groups()
	quit()


func _cache_meshes() -> void:
	for path in GRAVE_PATHS:
		_grave_meshes[path] = _extract_lod0_mesh(path)
	for key in PROP_PATHS:
		_prop_meshes[key] = _extract_lod0_mesh(PROP_PATHS[key])


func _extract_lod0_mesh(path: String) -> Mesh:
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("Missing model: " + path)
		return null
	var instance := packed.instantiate()
	var found: Mesh = null
	for child in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		if mesh_instance.name.ends_with("_LOD0") or found == null:
			found = mesh_instance.mesh
		if mesh_instance.name.ends_with("_LOD0"):
			break
	instance.free()
	return found


# --- Ground, path ----------------------------------------------------------

func _build_ground_and_paths() -> void:
	var ground_root := Node3D.new()
	ground_root.name = "Ground"
	scene.add_child(ground_root)
	ground_root.owner = scene

	var ground := PlaneMesh.new()
	ground.size = Vector2(200, 200)
	var ground_mesh := MeshInstance3D.new()
	ground_mesh.name = "Grass"
	ground_mesh.mesh = ground
	ground_mesh.material_override = GROUND_MAT
	ground_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground_root.add_child(ground_mesh)
	ground_mesh.owner = scene

	var body := StaticBody3D.new()
	body.name = "GroundCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	ground_root.add_child(body)
	body.owner = scene
	_add_box_shape(body, "Floor", Vector3(0, -0.5, 0), Vector3(200, 1, 200))

	var paths := Node3D.new()
	paths.name = "Paths"
	scene.add_child(paths)
	paths.owner = scene

	_add_plane(paths, "MainPath", Vector2(4.8, 45.0), Vector3(0, 0.012, 22.0), 0.0, PATH_MAT)
	_add_plane(paths, "ChurchForecourt", Vector2(12.0, 8.0), Vector3(0, 0.010, 3.0), 0.0, PATH_MAT)
	# Diagonal path to the ruin.
	var branch_from := Vector3(3.0, 0, 4.0)
	var branch_to := Vector3(21.0, 0, -21.0)
	_add_path_strip(paths, "RuinPath", branch_from, branch_to, 3.4)
	var west_from := Vector3(-2.0, 0, 26.0)
	var west_to := Vector3(-24.0, 0, 20.0)
	_add_path_strip(paths, "WestPath", west_from, west_to, 2.6)


func _add_plane(parent: Node3D, node_name: String, size: Vector2, pos: Vector3, yaw: float,
		material: Material) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = size
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = plane
	instance.material_override = material
	instance.position = pos
	instance.rotation_degrees.y = yaw
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	instance.owner = scene
	return instance


func _add_path_strip(parent: Node3D, node_name: String, from: Vector3, to: Vector3,
		width: float) -> void:
	var delta := to - from
	var length := delta.length()
	var center := (from + to) * 0.5
	var yaw := rad_to_deg(atan2(delta.x, delta.z))
	_add_plane(parent, node_name, Vector2(width, length), center + Vector3(0, 0.011, 0), yaw, PATH_MAT)


# --- Fence -----------------------------------------------------------------

func _build_fence() -> void:
	var root := Node3D.new()
	root.name = "Fence"
	scene.add_child(root)
	root.owner = scene

	var index := 0
	for x in range(-40, 41, 8):
		if x == 0:
			continue
		_add_fence_piece(root, "SouthFence_%d" % index, Vector3(x, 0, 44.0), 0.0, index)
		index += 1
	for x in range(-40, 41, 8):
		_add_fence_piece(root, "NorthFence_%d" % index, Vector3(x, 0, -44.0), 0.0, index)
		index += 1
	for z in range(-40, 41, 8):
		_add_fence_piece(root, "EastFence_%d" % index, Vector3(44.0, 0, z), 90.0, index)
		index += 1
	for z in range(-40, 41, 8):
		_add_fence_piece(root, "WestFence_%d" % index, Vector3(-44.0, 0, z), 90.0, index)
		index += 1

	var collision := StaticBody3D.new()
	collision.name = "FenceCollision"
	collision.collision_layer = 1
	collision.collision_mask = 0
	root.add_child(collision)
	collision.owner = scene
	_add_box_shape(collision, "North", Vector3(0, 1.5, -44.25), Vector3(88.6, 3.0, 0.5))
	_add_box_shape(collision, "East", Vector3(44.25, 1.5, 0), Vector3(0.5, 3.0, 88.6))
	_add_box_shape(collision, "West", Vector3(-44.25, 1.5, 0), Vector3(0.5, 3.0, 88.6))
	_add_box_shape(collision, "SouthLeft", Vector3(-24.0, 1.5, 44.25), Vector3(40.0, 3.0, 0.5))
	_add_box_shape(collision, "SouthRight", Vector3(24.0, 1.5, 44.25), Vector3(40.0, 3.0, 0.5))

	# Gate posts and the wooden arch salvage.
	var gate_post_mesh := _box_mesh(Vector3(0.38, 3.4, 0.38))
	for x in [-4.15, 4.15]:
		var post := MeshInstance3D.new()
		post.name = "GatePost_%d" % int(x * 10.0)
		post.mesh = gate_post_mesh
		post.material_override = PEW_MAT
		post.position = Vector3(x, 1.7, 44.0)
		root.add_child(post)
		post.owner = scene
	_add_prop("GateArch", "archway", Vector3(0, 0, 44.0), 0.0, 1.7, root)


func _add_fence_piece(parent: Node3D, node_name: String, pos: Vector3, yaw: float,
		index: int) -> void:
	var packed := FENCE_SCENES[index % FENCE_SCENES.size()]
	var piece := packed.instantiate() as Node3D
	piece.name = node_name
	piece.position = pos
	piece.rotation_degrees.y = yaw + rng.randf_range(-1.8, 1.8)
	piece.scale = Vector3.ONE * rng.randf_range(0.96, 1.04)
	parent.add_child(piece)
	piece.owner = scene


# --- Graves ----------------------------------------------------------------

func _build_graves() -> void:
	var root := Node3D.new()
	root.name = "Graves"
	scene.add_child(root)
	root.owner = scene

	var west_columns := [-37.0, -31.0, -25.0, -19.0, -13.0, -8.5]
	var east_columns := [8.5, 13.0, 19.0, 25.0, 31.0, 37.0]
	var south_rows := [8.0, 13.0, 18.0, 23.0, 28.0, 33.0, 38.0]
	var north_rows := [-20.0, -26.0, -32.0, -38.0]

	for row in south_rows:
		for column in west_columns:
			_try_grave(root, Vector3(column, 0, row), true)
		for column in east_columns:
			_try_grave(root, Vector3(column, 0, row), false)
	for row in north_rows:
		for column in west_columns:
			_try_grave(root, Vector3(column, 0, row), true)
		for column in [8.5, 13.0, 19.0]:
			_try_grave(root, Vector3(column, 0, row), false)

	# A few extra stones scattered off-grid, leaning against trees and the ruin.
	var extras := [
		Vector3(-9.0, 0, -5.0), Vector3(8.5, 0, -7.5), Vector3(-15.0, 0, -4.0),
		Vector3(17.0, 0, -7.0), Vector3(-33.0, 0, 1.0), Vector3(34.0, 0, -6.0),
		Vector3(-6.5, 0, 41.0), Vector3(6.5, 0, 41.0),
	]
	for pos in extras:
		_add_grave(root, pos, rng.randi_range(0, GRAVE_PATHS.size() - 1), rng.randf_range(-35, 35),
				rng.randf_range(0.9, 1.2))


func _try_grave(root: Node3D, pos: Vector3, west: bool) -> void:
	# Leave holes in the rows: an over-full grid reads as a fence of stones.
	if rng.randf() < 0.13:
		return
	if _near_special(pos, 4.2):
		return
	var path: String = GRAVE_PATHS[rng.randi_range(0, GRAVE_PATHS.size() - 1)]
	var yaw := rng.randf_range(-12.0, 12.0)
	if not west and rng.randf() < 0.24:
		yaw += 180.0
	_add_grave(root, pos + Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.4, 0.4)),
			GRAVE_PATHS.find(path), yaw, rng.randf_range(0.92, 1.15))


func _add_grave(root: Node3D, pos: Vector3, path_index: int, yaw: float, scale_value: float) -> void:
	var path: String = GRAVE_PATHS[path_index]
	var mesh: Mesh = _grave_meshes.get(path)
	if mesh == null:
		return
	var instance := MeshInstance3D.new()
	_name_index += 1
	instance.name = "Grave_%03d" % _name_index
	instance.mesh = mesh
	instance.material_override = STONE_MAT
	instance.position = pos
	instance.rotation_degrees.y = yaw
	instance.scale = Vector3.ONE * scale_value
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(instance)
	instance.owner = scene


func _near_special(pos: Vector3, radius: float) -> bool:
	const SPECIAL := [
		Vector3(-27, 0, 16), Vector3(-22, 0, 30), Vector3(-31, 0, -7),
		Vector3(25, 0, 8), Vector3(-15, 0, 5), Vector3(15, 0, 15),
		Vector3(27, 0, -27), Vector3(38, 0, 22), Vector3(-38, 0, -18),
		Vector3(0, 0, -7), Vector3(0, 0, 44),
	]
	for point in SPECIAL:
		if Vector2(pos.x - point.x, pos.z - point.z).length() < radius:
			return true
	return false


# --- Churches --------------------------------------------------------------

func _build_churches() -> void:
	var root := Node3D.new()
	root.name = "Churches"
	scene.add_child(root)
	root.owner = scene

	var intact := CHURCH_INTACT.instantiate() as Node3D
	intact.name = "ChurchIntact"
	intact.position = Vector3(0, -0.5, -7.0)
	intact.rotation_degrees.y = 90.0
	root.add_child(intact)
	intact.owner = scene

	var ruined := CHURCH_RUINED.instantiate() as Node3D
	ruined.name = "ChurchRuined"
	ruined.position = Vector3(27, -0.5, -27.0)
	ruined.rotation_degrees.y = 45.0
	root.add_child(ruined)
	ruined.owner = scene

	# Rubble around the ruin: fallen beams and broken stone blocks.
	for i in 8:
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(5.0, 10.0)
		var pos := Vector3(27 + cos(angle) * dist, 0.25, -27 + sin(angle) * dist)
		var beam := MeshInstance3D.new()
		beam.name = "RuinBeam_%d" % i
		beam.mesh = _box_mesh(Vector3(0.24, 0.24, rng.randf_range(2.2, 4.2)))
		beam.material_override = PEW_MAT
		beam.position = pos
		beam.rotation = Vector3(rng.randf_range(-0.12, 0.12), rng.randf() * TAU,
				rng.randf_range(-0.1, 0.1))
		root.add_child(beam)
		beam.owner = scene
	for i in 10:
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(4.5, 11.0)
		var block := MeshInstance3D.new()
		block.name = "RuinStone_%d" % i
		block.mesh = _box_mesh(Vector3(rng.randf_range(0.5, 1.4), rng.randf_range(0.35, 0.8),
				rng.randf_range(0.5, 1.5)))
		block.material_override = _stone_rubble_mat
		block.position = Vector3(27 + cos(angle) * dist, 0.2, -27 + sin(angle) * dist)
		block.rotation = Vector3(rng.randf_range(-0.2, 0.2), rng.randf() * TAU,
				rng.randf_range(-0.2, 0.2))
		root.add_child(block)
		block.owner = scene


# --- Lamps -----------------------------------------------------------------

func _build_lamps() -> void:
	var root := Node3D.new()
	root.name = "Lamps"
	scene.add_child(root)
	root.owner = scene

	var church_positions := [
		Vector3(-6.2, 0, 2.0), Vector3(6.2, 0, 2.0),
		Vector3(-6.2, 0, -15.5), Vector3(6.2, 0, -15.5),
		Vector3(-3.6, 0, 12.0), Vector3(3.6, 0, 12.0),
		Vector3(-3.6, 0, 28.0), Vector3(3.6, 0, 28.0),
		Vector3(23.8, 0, -18.5), Vector3(34.5, 0, -35.0),
	]
	var index := 0
	for pos in church_positions:
		var lamp := STANDING_LAMP.instantiate() as Node3D
		lamp.name = "StandingLamp_%d" % index
		lamp.position = pos
		lamp.rotation_degrees.y = rng.randf_range(0, 360)
		var lamp_scale := 0.8
		if index >= 4 and index < 8:
			lamp_scale = 0.7
		elif index >= 8:
			lamp_scale = 0.68
		lamp.scale = Vector3.ONE * lamp_scale
		root.add_child(lamp)
		lamp.owner = scene
		index += 1

	# Interior hanging cage lamps sit in the shallow, accessible narthex. The
	# church asset has a solid core beyond local x≈0.5, so deeper lamps would be
	# buried inside masonry.
	_add_hanging_lamp(root, Vector3(0, -0.5, -7), 90.0, -6.4, 3.9, 6.3, 0)
	_add_hanging_lamp(root, Vector3(0, -0.5, -7), 90.0, -4.6, 3.9, 6.3, 1)
	_add_hanging_lamp(root, Vector3(0, -0.5, -7), 90.0, -3.0, 3.9, 6.3, 2)
	_add_hanging_lamp(root, Vector3(27, -0.5, -27), 45.0, -5.8, 3.9, 5.6, 3)
	_add_hanging_lamp(root, Vector3(27, -0.5, -27), 45.0, -3.4, 3.9, 5.6, 4)


func _add_hanging_lamp(root: Node3D, church_pos: Vector3, yaw_deg: float, local_x: float,
		height: float, chain: float, index: int) -> void:
	var lamp := HANGING_LAMP.instantiate() as CemeteryLamp
	lamp.name = "HangingLamp_%d" % index
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	lamp.position = church_pos + basis * Vector3(local_x, height, 0)
	lamp.rotation_degrees.y = yaw_deg
	lamp.chain_length = chain
	root.add_child(lamp)
	lamp.owner = scene


# --- Props -----------------------------------------------------------------

func _build_props() -> void:
	var root := Node3D.new()
	root.name = "Props"
	scene.add_child(root)
	root.owner = scene

	# Focal monuments.
	_add_prop("Columbarium", "columbarium", Vector3(-31, 0, -7), 90.0, 1.25, root)
	_add_prop("Tomb", "tomb", Vector3(25, 0, 8), -90.0, 1.15, root)
	_add_prop("Monu", "monu", Vector3(-15, 0, 5), 8.0, 1.1, root)
	_add_prop("StoneArch", "arch", Vector3(-27, 0, 16), 12.0, 1.05, root)
	_add_prop("DistinctiveGrave", "grave01", Vector3(15, 0, 15), 180.0, 1.05, root)
	_add_prop("Obelisk", "obelisk", Vector3(-22, 0, 30), 8.0, 1.35, root)
	_add_prop("ObeliskFar", "obelisk", Vector3(38, 0, 22), 18.0, 1.1, root)
	_add_prop("TallSlab", "slab", Vector3(-38, 0, -18), 32.0, 1.2, root)
	_add_prop("WoodForm", "grave01", Vector3(-34, 0, 8), 100.0, 0.9, root)

	# Plot railing around the west obelisk.
	for i in 4:
		var angle := i * 90.0
		var pos := Vector3(-22, 0, 30) + Basis(Vector3.UP, deg_to_rad(angle)) * Vector3(0, 0, 3.2)
		_add_prop("Railing_%d" % i, "railing", pos, angle, 1.0, root)

	# A few ground stones live at the fence margins. Keeping them off the path
	# avoids the old overlap between the piles and the standing lamps.
	_add_prop("EdgeStone_1", "mud_flat", Vector3(-41.0, 0, 8), 15.0, 1.0, root, _stone_rubble_mat)
	_add_prop("EdgeStone_2", "mud_stones", Vector3(41.0, 0, -10), 70.0, 1.0, root, _stone_rubble_mat)
	_add_prop("EdgeStone_3", "mud_stones", Vector3(41.0, 0, 28), 140.0, 0.9, root, _stone_rubble_mat)
	_add_prop("EdgeStone_4", "mud_flat", Vector3(-41.0, 0, -28), 40.0, 0.9, root, _stone_rubble_mat)
	for i in 4:
		_add_prop("RuinPlank_%d" % i, "mud_plank",
				Vector3(22 + rng.randf_range(-4, 4), 0, -22 + rng.randf_range(-5, 5)),
				rng.randf_range(0, 360), rng.randf_range(0.9, 1.2), root, PEW_MAT)
	_add_prop("RuinLogs", "logs", Vector3(31, 0, -22), 32.0, 1.0, root, PEW_MAT)

	# Stone lanterns line the path without extra lights.
	for z in [10.0, 22.0, 34.0]:
		_add_prop("LanternL_%d" % int(z), "lantern", Vector3(-4.8, 0, z), 90.0, 1.0, root)
		_add_prop("LanternR_%d" % int(z), "lantern", Vector3(4.8, 0, z), -90.0, 1.0, root)


func _add_prop(node_name: String, key: String, pos: Vector3, yaw: float, scale_value: float,
		parent: Node3D, material: Material = null) -> void:
	var mesh: Mesh = _prop_meshes.get(key)
	if mesh == null:
		push_warning("No mesh for prop " + key)
		return
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material if material != null else STONE_MAT
	instance.position = pos
	instance.rotation_degrees.y = yaw
	instance.scale = Vector3.ONE * scale_value
	parent.add_child(instance)
	instance.owner = scene


# --- Trees and atmosphere --------------------------------------------------

func _build_trees() -> void:
	var root := Node3D.new()
	root.name = "Trees"
	scene.add_child(root)
	root.owner = scene

	var dead_positions := [
		Vector3(-40, 0, -34), Vector3(-40, 0, 16), Vector3(-40, 0, 36),
		Vector3(40, 0, -8), Vector3(40, 0, 32), Vector3(-18, 0, -40),
		Vector3(8, 0, -40), Vector3(33, 0, -41), Vector3(-30, 0, 40),
		Vector3(19, 0, 40), Vector3(38, 0, 15), Vector3(-33, 0, 2),
		Vector3(12, 0, -32), Vector3(-26, 0, -26), Vector3(-9, 0, -16),
	]
	for i in dead_positions.size():
		var tree := TREE_DEAD.instantiate() as Node3D
		tree.name = "DeadTree_%d" % i
		tree.position = dead_positions[i]
		tree.rotation_degrees.y = rng.randf_range(0, 360)
		tree.scale = Vector3.ONE * rng.randf_range(1.5, 2.5)
		root.add_child(tree)
		tree.owner = scene


func _build_fireflies() -> void:
	_add_particles("Fireflies", Vector3(0, 1.4, 16), Vector3(34, 1.4, 25), 70, 0.10, true)
	_add_particles("ChurchFireflies", Vector3(0, 2.0, -6), Vector3(9, 2.5, 11), 34, 0.085, true)


# --- Collision -------------------------------------------------------------

func _build_prop_collisions() -> void:
	var body := StaticBody3D.new()
	body.name = "PropCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	scene.add_child(body)
	body.owner = scene

	var shape_count := 0
	shape_count += _collide_group(body, scene.get_node("Graves"))
	shape_count += _collide_group(body, scene.get_node("Props"), ["GateArch"])
	shape_count += _collide_group(body, scene.get_node("Trees"))

	# Lamp models are solid; the glowing sphere, chain and light are not.
	var lamps := scene.get_node("Lamps")
	for lamp in lamps.get_children():
		for mesh_instance in lamp.find_children("*", "MeshInstance3D", true, false):
			var mi := mesh_instance as MeshInstance3D
			if mi.name == "Glow" or mi.name == "Chain":
				continue
			_add_mesh_collision(body, mi)
			shape_count += 1

	# Rubble chunks created directly under Churches.
	for node in scene.get_node("Churches").find_children("RuinBeam_*", "MeshInstance3D", true, false):
		_add_mesh_collision(body, node as MeshInstance3D)
		shape_count += 1
	for node in scene.get_node("Churches").find_children("RuinStone_*", "MeshInstance3D", true, false):
		_add_mesh_collision(body, node as MeshInstance3D)
		shape_count += 1

	# The visual gate posts next to the south opening.
	for node in scene.get_node("Fence").find_children("GatePost_*", "MeshInstance3D", true, false):
		_add_mesh_collision(body, node as MeshInstance3D)
		shape_count += 1

	# The gate arch is a single mesh with a walk-through opening, so its full
	# AABB would wall the entrance off. Give its two side posts and top beam
	# explicit boxes instead.
	_add_box_collision(body, "GateArchLeft", Vector3(-1.9, 2.5, 44.0), Vector3(0.55, 5.0, 0.8))
	_add_box_collision(body, "GateArchRight", Vector3(1.9, 2.5, 44.0), Vector3(0.55, 5.0, 0.8))
	_add_box_collision(body, "GateArchBeam", Vector3(0, 5.35, 44.0), Vector3(4.4, 0.7, 0.8))
	shape_count += 3

	print("PROP COLLISION SHAPES ", shape_count)


func _collide_group(body: StaticBody3D, root: Node, excluded: Array[String] = []) -> int:
	var count := 0
	for mesh_instance in root.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_instance as MeshInstance3D
		if mi.name in excluded:
			continue
		_add_mesh_collision(body, mi)
		count += 1
	return count


func _add_mesh_collision(body: StaticBody3D, mi: MeshInstance3D) -> void:
	if mi.mesh == null:
		return
	var aabb := mi.mesh.get_aabb()
	if aabb.size.x < 0.01 or aabb.size.y < 0.01 or aabb.size.z < 0.01:
		return
	# Some imported sub-scenes report that their internal mesh nodes are not in
	# the tree yet during this generation pass, so derive the transform from
	# the parent chain instead of calling global_transform().
	var xf := _node_global_transform(mi)
	var scale := xf.basis.get_scale().abs()
	var size := Vector3(
		maxf(aabb.size.x * scale.x, 0.06),
		maxf(aabb.size.y * scale.y, 0.06),
		maxf(aabb.size.z * scale.z, 0.06))
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.name = "Box_%03d" % body.get_child_count()
	collider.shape = shape
	collider.transform = Transform3D(xf.basis.orthonormalized(), xf * aabb.get_center())
	body.add_child(collider)
	collider.owner = scene


func _node_global_transform(node: Node3D) -> Transform3D:
	var xf := node.transform
	var parent := node.get_parent()
	while parent != null and parent != scene:
		if parent is Node3D:
			xf = (parent as Node3D).transform * xf
		parent = parent.get_parent()
	return xf


func _add_box_collision(body: StaticBody3D, node_name: String, pos: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.name = node_name
	collider.shape = shape
	collider.position = pos
	body.add_child(collider)
	collider.owner = scene


func _add_particles(node_name: String, pos: Vector3, extents: Vector3, amount: int,
		size: float, warm: bool) -> void:
	var particles := GPUParticles3D.new()
	particles.name = node_name
	particles.amount = amount
	particles.lifetime = 11.0
	particles.preprocess = 6.0
	particles.position = pos
	particles.visibility_aabb = AABB(-extents * 2.0, extents * 4.0)

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = extents
	process.direction = Vector3(0, 1, 0)
	process.spread = 180.0
	process.initial_velocity_min = 0.02
	process.initial_velocity_max = 0.12
	process.gravity = Vector3(0, 0.015, 0)
	process.scale_min = 0.55
	process.scale_max = 1.35
	process.color = Color(1.0, 0.68, 0.26, 0.85) if warm else Color(0.55, 0.75, 1.0, 0.6)
	particles.process_material = process

	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = SOFT_DOT
	material.disable_receive_shadows = true
	quad.material = material
	particles.draw_pass_1 = quad
	scene.add_child(particles)
	particles.owner = scene


# --- Helpers ---------------------------------------------------------------

func _box_mesh(size: Vector3) -> BoxMesh:
	var key := size
	if _box_meshes.has(key):
		return _box_meshes[key]
	var mesh := BoxMesh.new()
	mesh.size = size
	_box_meshes[key] = mesh
	return mesh


func _add_box_shape(body: StaticBody3D, node_name: String, pos: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.name = node_name
	collider.shape = shape
	collider.position = pos
	body.add_child(collider)
	collider.owner = scene


func _save_groups() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var ok := true
	for group in scene.get_children():
		var group_name := String(group.name)
		if group_name == "Churches":
			ok = _save_group(_extract_ruin_rubble(group), "ruin_rubble") and ok
			continue
		ok = _save_group(group, group_name.to_snake_case()) and ok
	print("TOTAL GROUPS saved=", scene.get_child_count() - 1)
	quit(0 if ok else 1)


func _extract_ruin_rubble(churches: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "RuinRubble"
	scene.add_child(root)
	for child in churches.get_children():
		if String(child.name).begins_with("RuinBeam_") \
				or String(child.name).begins_with("RuinStone_"):
			child.owner = null
			churches.remove_child(child)
			root.add_child(child)
	return root


func _save_group(group: Node, file_name: String) -> bool:
	group.owner = null
	_set_owner_recursive(group, group)
	var packed := PackedScene.new()
	var err := packed.pack(group)
	if err != OK:
		push_error("PackedScene.pack failed for %s: %d" % [group.name, err])
		return false
	var path := "%s/%s.tscn" % [OUT_DIR, file_name]
	err = ResourceSaver.save(packed, path)
	print("SAVED ", path, " err=", err, " nodes=", _count_nodes(group))
	return err == OK


func _set_owner_recursive(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_set_owner_recursive(child, owner)


func _count_nodes(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count
