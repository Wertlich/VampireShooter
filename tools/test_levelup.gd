extends SceneTree

# Checks the XP loop end to end and captures the level-up card menu.
# Usage: godot --path . --script res://tools/test_levelup.gd

func _initialize() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await create_timer(1.2).timeout

	var player := scene.get_node("Player") as Player
	var menu := scene.get_node("LevelUpMenu") as LevelUpMenu
	print("start: level=", player.level, " xp=", player.xp, " unlocked=", player.viewmodel.unlocked)

	# A killed skeleton must drop a gem.
	var skeleton: Enemy = scene.call("spawn_skeleton")
	await create_timer(0.4).timeout
	skeleton.take_damage(999.0, skeleton.global_position + Vector3(0, 1.6, 0), Vector3.FORWARD)
	await create_timer(0.2).timeout
	print("gems on the ground: ", get_nodes_in_group("xp_gems").size())

	# Enough XP for a level: the card menu should open and pause the game.
	player.add_xp(player.xp_to_next)
	await create_timer(0.5).timeout
	print("after xp: level=", player.level, " menu visible=", menu.visible, " paused=", paused)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://screenshots/levelup.png"))
	print("saved levelup.png")

	# Pick the first card and make sure the choice is applied.
	var cards: Array = menu._cards
	for card in cards:
		print("   card: ", card.get("tag"), " | ", card.get("title"))
	menu._choose(0)
	await create_timer(0.4).timeout
	print("after pick: menu visible=", menu.visible, " paused=", paused,
		" shotgun unlocked=", player.viewmodel.is_unlocked(1),
		" revolver damage=", (player.viewmodel.weapons[0] as Weapon).damage)
	quit()
