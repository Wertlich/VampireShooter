extends SceneTree

## Screenshots of the front screen: `-- <page> <out.png>` (0 main, 1 online, 2 settings).

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var page := int(args[0]) if args.size() > 0 else 0
	var out_name: String = args[1] if args.size() > 1 else "main_menu.png"

	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame
	menu.call("_show_page", page)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://screenshots/") + out_name)
	print("saved ", out_name)
	quit()
