extends SceneTree

## Two-process smoke test for co-op:
##   godot --headless --path . --script <abs>/tools/online_probe.gd -- host
##   godot --headless --path . --script <abs>/tools/online_probe.gd -- client
## Prints how many players/enemies each side sees at the end.

var _connected := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var role: String = args[0] if args.size() > 0 else "host"

	var world := Node.new()
	world.name = "Root"
	root.add_child(world)
	var net_node := Node.new()
	world.add_child(net_node)

	# The root window is not fully up during _initialize.
	await create_timer(0.3).timeout

	if role == "host":
		if not Net.host(net_node, Net.PORT):
			print("HOST: failed ", Net.last_error)
			quit(1)
			return
	else:
		if not Net.join(net_node, "127.0.0.1", Net.PORT):
			print("CLIENT: failed ", Net.last_error)
			quit(1)
			return
		var api := net_node.multiplayer
		if api != null:
			api.connected_to_server.connect(func() -> void: _connected = true)
			api.connection_failed.connect(func() -> void: print("CLIENT: connection_failed"))
		for i in 80:
			if _connected:
				break
			await create_timer(0.1).timeout
		if not _connected:
			print("CLIENT: connect timeout")
			quit(1)
			return

	var scene: Node = load("res://scenes/main.tscn").instantiate()
	world.add_child(scene)

	if role == "host":
		await create_timer(0.8).timeout
		var waves := scene.get_node_or_null("WaveManager") as WaveManager
		if waves != null:
			waves.begin()

	await create_timer(6.0).timeout

	var players := get_nodes_in_group("player").size()
	var enemies := get_nodes_in_group("enemies").size()
	var network := scene.get_node_or_null("NetworkGame")
	var net_players := 0
	if network != null:
		var table = network.get("_players")
		if table is Dictionary:
			net_players = (table as Dictionary).size()
	print("%s: players=%d net_players=%d enemies=%d" % [role, players, net_players, enemies])
	quit(0)
