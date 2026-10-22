class_name Settings
extends RefCounted
## Persisted audio/video settings.
##
## Everything is applied at runtime, so the pause menu can change resolution,
## sound volume or the quality preset without restarting the game. Values live
## in `user://settings.cfg`.

const CONFIG_PATH := "user://settings.cfg"

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]
const QUALITY_NAMES: Array[String] = ["Низкое", "Среднее", "Высокое"]

static var master_volume: float = 0.8
static var resolution: Vector2i = Vector2i(1600, 900)
static var fullscreen: bool = false
static var vsync: bool = true
## 0 = low, 1 = medium, 2 = high.
static var quality: int = 2


# --- Load / save ------------------------------------------------------------

static func load_all() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	master_volume = clampf(float(config.get_value("audio", "master", master_volume)), 0.0, 1.0)
	resolution = config.get_value("video", "resolution", resolution)
	fullscreen = bool(config.get_value("video", "fullscreen", fullscreen))
	vsync = bool(config.get_value("video", "vsync", vsync))
	quality = clampi(int(config.get_value("video", "quality", quality)), 0, 2)


static func save() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master", master_volume)
	config.set_value("video", "resolution", resolution)
	config.set_value("video", "fullscreen", fullscreen)
	config.set_value("video", "vsync", vsync)
	config.set_value("video", "quality", quality)
	config.save(CONFIG_PATH)


# --- Apply ------------------------------------------------------------------

static func apply_all(root: Node = null) -> void:
	apply_audio(master_volume)
	apply_video()
	apply_quality(quality, root)


static func apply_audio(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	var bus := AudioServer.get_bus_index("Master")
	if bus < 0:
		return
	AudioServer.set_bus_mute(bus, master_volume <= 0.005)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(master_volume, 0.005)))


static func apply_video() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var window := _window()
	if window == null:
		return
	window.mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
	if not fullscreen:
		window.size = resolution
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


## Applies the quality preset to the current scene: MSAA, render scale, SSAO,
## glow, fog and shadow distance.
static func apply_quality(level: int, root: Node = null) -> void:
	quality = clampi(level, 0, 2)
	var scene: Node = root if root != null else _scene()
	if scene == null or not scene.is_inside_tree():
		return

	var viewport := scene.get_viewport()
	if viewport:
		viewport.msaa_3d = [
			Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X,
		][quality]
		viewport.scaling_3d_scale = [0.75, 1.0, 1.0][quality]

	for node in _find(scene, "WorldEnvironment"):
		var environment: Environment = (node as WorldEnvironment).environment
		if environment == null:
			continue
		environment.ssao_enabled = quality >= 1
		environment.glow_enabled = quality >= 1
		environment.fog_enabled = quality >= 1

	var shadow_distance: float = [60.0, 120.0, 170.0][quality]
	for node in _find(scene, "DirectionalLight3D"):
		(node as DirectionalLight3D).directional_shadow_max_distance = shadow_distance
	RenderingServer.directional_shadow_atlas_set_size([1024, 2048, 4096][quality], true)


# --- Helpers ----------------------------------------------------------------

static func _window() -> Window:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root if tree else null


static func _scene() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.current_scene if tree else null


static func _find(node: Node, type_name: String) -> Array[Node]:
	var found: Array[Node] = []
	if node.is_class(type_name):
		found.append(node)
	for child in node.get_children():
		found.append_array(_find(child, type_name))
	return found
