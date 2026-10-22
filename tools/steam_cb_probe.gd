extends SceneTree

func _initialize() -> void:
	var steam = Engine.get_singleton("Steam")
	var hits := []
	for m in steam.get_method_list():
		var n: String = m["name"]
		if n.to_lower().contains("callback") or n.to_lower().contains("pump") or n.begins_with("run"):
			hits.append(n)
	print("callback-ish: ", ", ".join(hits))
	quit()
