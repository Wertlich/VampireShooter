extends SceneTree

# Captures the HUD weapon panel for both guns.
# Usage: godot --path . --script res://tools/preview_hud.gd

func _initialize() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await create_timer(1.2).timeout
	await _shot("hud_revolver.png")

	var player := scene.get_node("Player") as Player
	player.viewmodel.unlock(1)
	player.switch_to(1)
	await create_timer(0.9).timeout
	await _shot("hud_shotgun.png")
	quit()


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://screenshots/") + file_name)
	print("saved ", file_name)
