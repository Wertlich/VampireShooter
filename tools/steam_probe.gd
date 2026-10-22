extends SceneTree

## Checks whether the GodotSteam GDExtension loaded and can talk to a Steam
## client on this machine.

func _initialize() -> void:
	print("singleton Steam: ", Engine.has_singleton("Steam"))
	print("class Steam: ", ClassDB.class_exists("Steam"))
	if not Engine.has_singleton("Steam"):
		print("RESULT: godotsteam не загрузился")
		quit(1)
		return
	var steam = Engine.get_singleton("Steam")
	print("has steamInitEx: ", steam.has_method("steamInitEx"))
	var running = steam.call("isSteamRunning")
	print("isSteamRunning: ", running)
	var result = steam.call("steamInitEx", false, 480)
	print("steamInitEx: ", result)
	print("RESULT: godotsteam загрузился")
	quit(0)
