extends SceneTree
## One-time migration, preserves authored values. Run with --headless --script.
func _init() -> void:
	for kind in ["skeleton", "zombie", "archer", "slime", "boss"]:
		var path := "res://scenes/enemy_%s.tscn" % kind
		var enemy := load(path).instantiate() as Enemy
		if not enemy.has_node("Behavior"):
			var behavior := EnemyBehavior.new()
			behavior.name = "Behavior"
			behavior.attack_style = enemy.mode
			enemy.add_child(behavior)
			behavior.owner = enemy
		_save(enemy, path)
		enemy.free()
	var castle := load("res://scenes/castle.tscn").instantiate() as Castle
	if not castle.has_node("MapCollision"):
		var data := castle._load_data()
		castle._build_collision(data)
		castle._build_lights(data)
		for name in ["MapCollision", "Lights"]:
			var branch := castle.get_node(name)
			branch.owner = castle
			for child in branch.get_children():
				child.owner = castle
	_save(castle, "res://scenes/castle.tscn")
	castle.free()
	print("Editor node migration complete")
	quit()

func _save(root: Node, path: String) -> void:
	var packed := PackedScene.new()
	assert(packed.pack(root) == OK)
	assert(ResourceSaver.save(packed, path) == OK)
