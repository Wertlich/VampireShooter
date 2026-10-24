extends SceneTree

const OUT := "res://screenshots/cemetery/09_sky.png"

func _initialize() -> void:
	var env := load("res://assets/cemetery/materials/night_environment.tres") as Environment
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)
	var camera := Camera3D.new()
	camera.fov = 72.0
	camera.far = 1000.0
	camera.rotation_degrees = Vector3(30, -20, 0)
	root.add_child(camera)
	camera.current = true
	await create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var err := image.save_png(ProjectSettings.globalize_path(OUT))
	print("saved ", OUT, " err=", err)
	quit()
