extends SceneTree

## Verifies the Steam bridge end to end as far as a single machine allows:
## init, persona, lobby creation, lobby data round-trip, leave.

var _bridge: SteamBridge
var _created := false
var _lobby := 0


func _initialize() -> void:
	_bridge = SteamBridge.new()
	root.add_child(_bridge)
	await create_timer(0.2).timeout

	if not _bridge.available():
		print("RESULT: godotsteam не загружен")
		quit(1)
		return
	if not _bridge.init_steam():
		print("RESULT: Steam не запущен или init не удался")
		quit(1)
		return
	print("persona: ", _bridge.persona)
	print("steam id: ", _bridge.steam_id())

	_bridge.lobby_ready.connect(func(id: int, owner: bool) -> void:
		_created = true
		_lobby = id
		print("lobby: ", id, " owner=", owner))

	_bridge.create_lobby("127.0.0.1:27015", "Vampire Shooter test")
	for i in 60:
		if _created:
			break
		await create_timer(0.1).timeout

	if not _created:
		print("RESULT: лобби не создалось за 6 с")
		quit(1)
		return

	print("lobby data addr: ", _bridge.lobby_address())
	print("lobby members: ", _bridge._steam.call("getNumLobbyMembers", _lobby))
	_bridge.leave_lobby()
	print("RESULT: steam lobbies работают")
	quit(0)
