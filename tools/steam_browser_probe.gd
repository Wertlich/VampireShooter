extends SceneTree

## Verifies the lobby browser: create a lobby, find it through the name filter,
## and check the label/address it exposes.

var _bridge: SteamBridge
var _created := false
var _lobby := 0
var _found: Array = []


func _initialize() -> void:
	_bridge = SteamBridge.new()
	root.add_child(_bridge)
	await create_timer(0.2).timeout
	if not _bridge.init_steam():
		print("RESULT: steam init failed")
		quit(1)
		return

	_bridge.lobby_ready.connect(func(id: int, _owner: bool) -> void:
		_created = true
		_lobby = id)
	_bridge.lobbies_found.connect(func(lobbies: Array) -> void: _found = lobbies)

	_bridge.create_lobby("192.168.31.221:27015", "Vampire Shooter · %s" % _bridge.persona)
	for i in 60:
		if _created:
			break
		await create_timer(0.1).timeout
	if not _created:
		print("RESULT: lobby not created")
		quit(1)
		return
	print("created lobby: ", _lobby)

	_bridge.find_lobbies()
	for i in 80:
		if not _found.is_empty():
			break
		await create_timer(0.1).timeout

	print("found: ", _found.size())
	for id in _found:
		print("  %s  |  %s  |  addr=%s" % [
			str(id), _bridge.lobby_label(int(id)),
			str(Engine.get_singleton("Steam").call("getLobbyData", id, SteamBridge.ADDR_KEY))])
	print("RESULT: browser ", "works" if _found.has(_lobby) else "missed own lobby")
	quit(0)
