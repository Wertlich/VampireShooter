class_name SteamBridge
extends Node
## Thin wrapper over the GodotSteam singleton: init, lobbies, invites.
##
## The heavy simulation transport stays ENet — Steam is used to find friends and
## to exchange the host's address, so nobody has to type an IP. If Steam is not
## running the game simply hides these buttons and direct IP keeps working.

signal status_changed(text: String)
signal lobby_ready(lobby_id: int, is_owner: bool)
signal lobby_failed(reason: String)
## Public lobbies of this game found by find_lobbies().
signal lobbies_found(lobbies: Array)

## Lobby key holding the host's "ip:port" so guests can connect.
const ADDR_KEY := "addr"
const NAME_KEY := "name"
## Exact value of GAME_KEY; Steam string filters compare whole values, not
## prefixes, so the game tag must be a complete string.
const GAME_KEY := "game"
const GAME_TAG := "vampireshooter"

static var instance: SteamBridge

var initialised: bool = false
var lobby_id: int = 0
var is_owner: bool = false
var persona: String = ""
var last_error: String = ""

var _steam: Object
var _pending_join: int = 0
var _filtered_request: bool = false


func _ready() -> void:
	instance = self


func _process(_delta: float) -> void:
	# Without embedded callbacks Steam signals (lobby created/joined) only fire
	# when the API is pumped from the main loop.
	if initialised and _steam != null:
		_steam.call("run_callbacks")


func _exit_tree() -> void:
	if initialised and _steam != null:
		if lobby_id != 0:
			_steam.call("leaveLobby", lobby_id)
		_steam.call("steamShutdown")


## False when the extension is missing or the Steam client is not running.
func available() -> bool:
	return Engine.has_singleton("Steam")


## Human-readable reason why the Steam block is not usable (empty when fine).
func diagnostic() -> String:
	if not available():
		return "Steam-модуль не найден: нужна папка addons рядом с exe"
	if _steam == null:
		_steam = Engine.get_singleton("Steam")
	if not bool(_steam.call("isSteamRunning")):
		return "Steam не запущен — запусти клиент Steam"
	return ""


func init_steam() -> bool:
	if initialised:
		return true
	if not available():
		return false
	_steam = Engine.get_singleton("Steam")
	if not bool(_steam.call("isSteamRunning")):
		return false
	# The app id comes from steam_appid.txt next to the project in development.
	var result: Dictionary = _steam.call("steamInitEx", false, _app_id())
	if int(result.get("status", -1)) != 0:
		last_error = "Steam не принял игру: %s" % String(result.get("verbal", "ошибка"))
		push_warning("Steam init failed: %s" % result)
		return false
	persona = String(_steam.call("getPersonaName"))
	initialised = true

	_steam.connect("lobby_created", Callable(self, "_on_lobby_created"))
	_steam.connect("lobby_joined", Callable(self, "_on_lobby_joined"))
	_steam.connect("lobby_match_list", Callable(self, "_on_lobby_match_list"))
	_steam.connect("join_requested", Callable(self, "_on_join_requested"))
	return true


func steam_id() -> int:
	if not initialised:
		return 0
	return int(_steam.call("getSteamID"))


## Development app id: `steam_appid.txt` next to project.godot, else Spacewar.
func _app_id() -> int:
	var file := FileAccess.open("res://steam_appid.txt", FileAccess.READ)
	if file == null:
		return 480
	var text := file.get_as_text().strip_edges()
	file.close()
	return int(text) if text.is_valid_int() else 480


# --- Lobbies ----------------------------------------------------------------

func create_lobby(address: String, lobby_name: String) -> void:
	if not initialised:
		lobby_failed.emit("Steam не инициализирован")
		return
	status_changed.emit("Создаём лобби…")
	_steam.call("createLobby", 2, Net.MAX_PLAYERS)  # 2 = public
	# The address is written once the lobby exists (see _on_lobby_created).
	set_meta("pending_address", address)
	set_meta("pending_name", lobby_name)


## Asks Steam for public lobbies of this game. appid 480 is shared with every
## studio testing on Spacewar, so results are filtered by our game tag. If the
## filter comes back empty we retry unfiltered and sift client-side.
func find_lobbies() -> void:
	if not initialised:
		return
	status_changed.emit("Ищем лобби…")
	_filtered_request = true
	_steam.call("addRequestLobbyListStringFilter", GAME_KEY, GAME_TAG, 2)
	_steam.call("addRequestLobbyListResultCountFilter", 50)
	_steam.call("requestLobbyList")


## Short human label for the lobby browser.
func lobby_label(id: int) -> String:
	var name := String(_steam.call("getLobbyData", id, NAME_KEY))
	var members := int(_steam.call("getNumLobbyMembers", id))
	return "%s · %d/%d" % [name if not name.is_empty() else str(id), members, Net.MAX_PLAYERS]


func join_lobby(id: int) -> void:
	if not initialised:
		lobby_failed.emit("Steam не инициализирован")
		return
	_pending_join = id
	status_changed.emit("Входим в лобби %d…" % id)
	_steam.call("joinLobby", id)


func leave_lobby() -> void:
	if initialised and lobby_id != 0:
		_steam.call("leaveLobby", lobby_id)
	lobby_id = 0
	is_owner = false


func invite_friend() -> void:
	if not initialised or lobby_id == 0:
		return
	_steam.call("activateGameOverlayInviteDialog", lobby_id)


func lobby_address() -> String:
	if not initialised or lobby_id == 0:
		return ""
	return String(_steam.call("getLobbyData", lobby_id, ADDR_KEY))


func lobby_of_friend() -> int:
	# Lobby the player was invited to from the Steam overlay or a friend.
	if not initialised:
		return 0
	var command: String = String(_steam.call("getLaunchCommandLine"))
	if command.begins_with("+connect_lobby"):
		var parts := command.split(" ", false)
		if parts.size() >= 2:
			return int(parts[1])
	return 0


func _on_lobby_created(result: int, id: int) -> void:
	if result != 1:
		lobby_failed.emit("Не удалось создать лобби (код %d)" % result)
		return
	lobby_id = id
	is_owner = true
	var address: String = String(get_meta("pending_address", ""))
	var lobby_name: String = String(get_meta("pending_name", "Vampire Shooter"))
	_steam.call("setLobbyData", lobby_id, ADDR_KEY, address)
	_steam.call("setLobbyData", lobby_id, NAME_KEY, lobby_name)
	_steam.call("setLobbyData", lobby_id, GAME_KEY, GAME_TAG)
	_steam.call("setLobbyJoinable", lobby_id, true)
	status_changed.emit("Лобби создано: %d" % lobby_id)
	lobby_ready.emit(lobby_id, true)


func _on_lobby_joined(id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != 1:
		lobby_failed.emit(_lobby_error(response))
		return
	# Creating a lobby also fires this callback; keep the owner flag from the
	# creation path, otherwise the host would think it is a guest.
	if id == lobby_id and is_owner:
		return
	lobby_id = id
	is_owner = false
	status_changed.emit("В лобби %d" % id)
	lobby_ready.emit(lobby_id, false)


## Keeps a single bridge alive across scene changes (lobby survives the menu).
static func ensure(node: Node) -> SteamBridge:
	if instance != null and is_instance_valid(instance):
		return instance
	var bridge := SteamBridge.new()
	bridge.name = "SteamBridge"
	# The menu is often mid-build here, so defer the insertion.
	node.get_tree().root.add_child.call_deferred(bridge)
	return bridge


## Steam's EChatRoomEnterResponse in plain Russian.
func _lobby_error(response: int) -> String:
	match response:
		2:
			return "Лобби не найдено (код 2): хост перезапустил игру или ID введён не целиком. Жми «Найти лобби»."
		3:
			return "Вход запрещён (код 3): лобби только для друзей"
		4:
			return "Лобби заполнено (код 4)"
		5:
			return "Лобби закрыто (код 5)"
		7:
			return "Ограниченный аккаунт Steam (код 7)"
		_:
			return "Не удалось войти в лобби (код %d)" % response


func _on_lobby_match_list(lobbies: Array) -> void:
	var ours: Array = []
	for id in lobbies:
		if String(_steam.call("getLobbyData", id, GAME_KEY)) == GAME_TAG:
			ours.append(id)

	# The tag filter can come back empty on some Steam setups; ask once more
	# without it and sift client-side.
	if ours.is_empty() and _filtered_request:
		_filtered_request = false
		status_changed.emit("Ищем ещё раз, без фильтра…")
		_steam.call("requestLobbyList")
		return

	_filtered_request = false
	status_changed.emit("Найдено лобби: %d" % ours.size())
	lobbies_found.emit(ours)


func _on_join_requested(lobby: String, friend_id: int) -> void:
	status_changed.emit("Приглашение от %d" % friend_id)
	join_lobby(int(lobby))
