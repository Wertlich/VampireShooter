extends SceneTree

## Lists the Steam networking entry points exposed by this GodotSteam build.

func _initialize() -> void:
	var steam = Engine.get_singleton("Steam")
	var names: Array = []
	for m in steam.get_method_list():
		var name: String = m["name"]
		if name.to_lower().contains("callback") or name.to_lower().contains("run") or name.to_lower().contains("pump") or name.to_lower().contains("socket") or name.to_lower().contains("p2p") \
				or name.to_lower().contains("message") or name.to_lower().contains("lobby") \
				or name.to_lower().contains("connection") or name.to_lower().contains("poll"):
			names.append(name)
	names.sort()
	print("methods: ", ", ".join(names))
	quit()
