extends SceneTree

## Creates a public lobby, then asks Steam for the lobby list.
## Confirms that discovery works (the same lobby should appear in the list).

var _bridge: SteamBridge
var _created := false
var _lobby := 0
var _list: Array = []


func _initialize() -> void:
	_bridge = SteamBridge.new()
	root.add_child(_bridge)
	await create_timer(0.2).timeout
	if not _bridge.init_steam():
		print("RESULT: steam init failed")
		quit(1)
		return

	var steam = Engine.get_singleton("Steam")
	print("app id: ", steam.call("getAppID") if steam.has_method("getAppID") else "n/a")

	_bridge.lobby_ready.connect(func(id: int, owner: bool) -> void:
		_created = true
		_lobby = id)
	_bridge.create_lobby("127.0.0.1:27015", "Vampire Shooter")
	for i in 60:
		if _created:
			break
		await create_timer(0.1).timeout
	if not _created:
		print("RESULT: lobby not created")
		quit(1)
		return
	print("lobby: ", _lobby)

	steam.connect("lobby_match_list", func(lobbies: Array) -> void: _list = lobbies)
	steam.call("requestLobbyList")
	for i in 60:
		if not _list.is_empty():
			break
		await create_timer(0.1).timeout

	print("lobby list size: ", _list.size())
	for id in _list:
		print("  lobby %s name=%s members=%s" % [
			str(id),
			str(steam.call("getLobbyData", id, "name")),
			str(steam.call("getNumLobbyMembers", id))])
	print("RESULT: discovery ", "works" if _list.has(_lobby) else "empty")
	quit(0)
