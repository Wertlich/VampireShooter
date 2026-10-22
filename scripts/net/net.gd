class_name Net
extends RefCounted
## Network role and ENet peer, kept in static state so the menu can configure it
## before the arena scene loads.
##
## This is deliberately *not* an autoload: the project's headless tools run with
## `--script`, where autoload singletons do not exist, and they still need
## Net.is_online() to compile. Static state lives as long as the process.

enum Mode { OFFLINE, HOST, CLIENT }

const PORT := 27015
const MAX_PLAYERS := 4

static var mode: Mode = Mode.OFFLINE
static var last_error: String = ""


static func is_online() -> bool:
	return mode != Mode.OFFLINE


static func is_host() -> bool:
	return mode == Mode.HOST


static func is_client() -> bool:
	return mode == Mode.CLIENT


## `host_node` supplies the MultiplayerAPI (any node of the current tree).
static func host(host_node: Node, port: int = PORT) -> bool:
	var api := _api(host_node)
	if api == null:
		last_error = "Нет MultiplayerAPI"
		return false
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		last_error = "Не удалось поднять сервер (порт %d, код %d)" % [port, err]
		return false
	api.multiplayer_peer = peer
	mode = Mode.HOST
	last_error = ""
	return true


static func join(host_node: Node, address: String, port: int = PORT) -> bool:
	var api := _api(host_node)
	if api == null:
		last_error = "Нет MultiplayerAPI"
		return false
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		last_error = "Не удалось подключиться к %s:%d (код %d)" % [address, port, err]
		return false
	api.multiplayer_peer = peer
	mode = Mode.CLIENT
	last_error = ""
	return true


static func shutdown(host_node: Node) -> void:
	var api := _api(host_node)
	if api != null:
		var peer := api.multiplayer_peer
		if peer != null:
			peer.close()
		api.multiplayer_peer = null
	mode = Mode.OFFLINE


## Headless tools run without a default interface, so create one on demand.
static func _api(node: Node) -> MultiplayerAPI:
	if node == null:
		return null
	var api := node.multiplayer
	if api != null:
		return api
	var tree := node.get_tree()
	if tree == null:
		return null
	api = MultiplayerAPI.create_default_interface()
	tree.set_multiplayer(api)
	return api


## The player node this machine controls (falls back to the first one).
static func local_player() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var players := tree.get_nodes_in_group("player")
	for node in players:
		if node.has_method("is_local_player") and node.call("is_local_player"):
			return node
	return players[0] if not players.is_empty() else null
