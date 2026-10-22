extends SceneTree

# Dev smoke test: instantiates the main scene headless and checks weapon wiring,
# ammo, reload and weapon switching.
# Usage: godot --headless --path . --script res://tools/validate.gd

func _initialize() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		printerr("main scene failed to load")
		quit(1)
		return

	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var player := scene.get_node_or_null("Player") as Player
	if player == null:
		printerr("player missing")
		quit(1)
		return

	print("player at ", player.global_position, " camera at ", player.camera.global_position)
	print("weapons: ", player.viewmodel.weapons.size())
	for w in player.viewmodel.weapons:
		print("   ", w.display_name, " ammo=", w.ammo, "/", w.max_ammo, " rate=", w.fire_rate, " recoil=", w.recoil_pitch)

	var weapon: Weapon = player.weapon
	print("active: ", weapon.display_name, " ammo=", weapon.ammo)
	print("pull_trigger -> ", weapon.pull_trigger(), ", ammo now ", weapon.ammo)
	await create_timer(0.5).timeout
	weapon.reload()
	await create_timer(2.3).timeout
	print("after reload: ammo=", weapon.ammo, " reloading=", weapon.is_reloading)

	# Switch to the shotgun and back.
	player.switch_to(1)
	await create_timer(0.6).timeout
	print("switched to: ", player.weapon.display_name, " ammo=", player.weapon.ammo, "/", player.weapon.max_ammo)
	print("shotgun fired -> ", player.weapon.pull_trigger(), ", ammo now ", player.weapon.ammo)

	player.switch_to(0)
	await create_timer(0.6).timeout
	print("switched back to: ", player.weapon.display_name)
	print("shotgun visible? ", player.viewmodel.weapons[1].visible, " revolver visible? ", player.viewmodel.weapons[0].visible)

	var hud := scene.get_node_or_null("HUD")
	print("hud: ", hud, " children=", hud.get_child_count() if hud else -1)
	quit()
