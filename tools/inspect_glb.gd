extends SceneTree

# Dumps the imported GLB tree and its animations.
# Usage: godot --headless --path . --script res://tools/inspect_glb.gd -- <res path>

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "res://models/skelet/animated/skeleton.glb"
	var packed := load(path) as PackedScene
	print("SCENE ", packed)
	if packed == null:
		quit(1)
		return
	var node := packed.instantiate()
	_dump(node, 0)
	var anims := node.find_children("*", "AnimationPlayer", true, false)
	for ap in anims:
		var player := ap as AnimationPlayer
		print("ANIM PLAYER ", player.name, " anims=", player.get_animation_list())
		for name in player.get_animation_list():
			var anim := player.get_animation(name)
			print("   ", name, " len=", anim.length, " loop=", anim.loop_mode, " tracks=", anim.get_track_count())
			for i in mini(anim.get_track_count(), 6):
				print("      track ", anim.track_get_path(i), " type ", anim.track_get_type(i))
	node.free()
	quit()


func _dump(node: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	var extra := ""
	if node is Node3D:
		extra = " pos=%s scale=%s" % [node.position, node.scale]
	print(pad, "- ", node.name, " [", node.get_class(), "]", extra)
	for child in node.get_children():
		_dump(child, depth + 1)
