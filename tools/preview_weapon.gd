extends SceneTree

# Renders one weapon from the view model, for checking scale and grip.
# Usage: godot --path . --script res://tools/preview_weapon.gd -- <index> <out.png> [aim]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var index: int = int(args[0]) if args.size() > 0 else 2
	var out_name: String = args[1] if args.size() > 1 else "weapon.png"
	var aim := args.size() > 2 and args[2] == "aim"

	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(0.8).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var waves: WaveManager = scene.get("waves")
	waves.set_process(false)
	var player: Player = scene.get("player")
	player.viewmodel.unlock(index)
	player.switch_to(index)
	await create_timer(0.9).timeout

	if aim:
		Input.action_press("aim")
		await create_timer(0.7).timeout

	var weapon: Weapon = player.weapon
	if args.size() > 2 and args[2] == "dual":
		weapon.make_dual()
		await create_timer(0.2).timeout
	print("weapon: ", weapon.display_name, " index ", index, " ammo ", weapon.ammo, " dual ", weapon.is_dual())

	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://screenshots/") + out_name)
	print("saved ", out_name)
	quit()
