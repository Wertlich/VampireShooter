class_name NetworkGame
extends Node3D
## Co-op plumbing for the arena: spawns one player per peer, mirrors the host's
## enemies to the clients, and resolves shots on the host.
##
## The host owns the simulation (waves, AI, damage). Clients mirror it: their
## players send their own transform, and enemies are puppets driven by
## snapshots. Offline play goes through the same path with a single player, so
## there is only one code path to keep working.

signal local_player_spawned(player: Node)

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const SPAWN_POINT := Vector3(0.0, 0.2, 34.0)
const ENEMY_INTERVAL := 0.1
const IMPACT_SCENE := preload("res://scenes/fx/impact.tscn")

var _players: Dictionary = {}
var _enemies: Dictionary = {}
var _enemy_timer: float = 0.0
var _next_enemy_id: int = 1
## Latest snapshot targets, so puppets glide instead of teleporting.
var _enemy_targets: Dictionary = {}
var _enemy_yaws: Dictionary = {}


func _ready() -> void:
	add_to_group("network_game")
	# Deferred so the arena (main.gd, HUD) can connect to the spawn signal first.
	_start.call_deferred()


func _start() -> void:
	if not Net.is_online():
		# Offline keeps the player authored in the arena scene, so tools and
		# tests that look up "Player" keep working.
		var fixed := get_parent().get_node_or_null("Player")
		if fixed != null:
			fixed.call("configure", 1)
			_players[1] = fixed
			local_player_spawned.emit(fixed)
		else:
			spawn_player(1)
		return

	# Online: the fixed body would be an unused second player.
	var unused := get_parent().get_node_or_null("Player")
	if unused != null:
		unused.queue_free()

	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	if Net.is_host():
		spawn_player(1)
	else:
		# The client can control itself right away; the host only needs to learn
		# about it so everyone else sees it.
		spawn_player(multiplayer.get_unique_id())
		_hello.call_deferred()


# --- Players ----------------------------------------------------------------

func spawn_player(peer_id: int) -> void:
	if _players.has(peer_id) or PLAYER_SCENE == null:
		return
	var player := PLAYER_SCENE.instantiate()
	player.name = "Player_%d" % peer_id
	player.call("configure", peer_id)
	add_child(player)
	player.global_position = SPAWN_POINT + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))
	_players[peer_id] = player
	if player.call("is_local_player"):
		local_player_spawned.emit(player)


func _hello() -> void:
	rpc_id(1, "net_hello")


@rpc("any_peer", "reliable")
func net_hello() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	for id in _players.keys():
		rpc_id(sender, "net_spawn_player", id)
	spawn_player(sender)
	rpc("net_spawn_player", sender)


@rpc("authority", "reliable", "call_remote")
func net_spawn_player(peer_id: int) -> void:
	spawn_player(peer_id)


@rpc("authority", "reliable", "call_remote")
func net_remove_player(peer_id: int) -> void:
	if not _players.has(peer_id):
		return
	(_players[peer_id] as Node).queue_free()
	_players.erase(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	rpc("net_remove_player", peer_id)
	net_remove_player(peer_id)


func _on_connected_to_server() -> void:
	rpc_id(1, "net_hello")


func _on_connection_failed() -> void:
	Net.last_error = "Сервер не ответил"
	_leave_to_menu()


func _on_server_disconnected() -> void:
	Net.last_error = "Соединение с хостом потеряно"
	_leave_to_menu()


func _leave_to_menu() -> void:
	Net.shutdown(self)
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# --- Enemy replication ------------------------------------------------------

func _process(delta: float) -> void:
	if not Net.is_host():
		_smooth_enemies(delta)
		return
	_enemy_timer -= delta
	if _enemy_timer > 0.0:
		return
	_enemy_timer = ENEMY_INTERVAL

	var data := []
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null:
			continue
		if enemy.net_id == 0:
			enemy.net_id = _next_enemy_id
			_next_enemy_id += 1
		data.append([enemy.net_id, enemy.net_kind, enemy.global_position, enemy.rotation.y, enemy.health])
	rpc("net_enemy_snapshot", data)


## Puppets chase the latest snapshot instead of snapping to it: 10 Hz packets
## would otherwise look like a slide show.
func _smooth_enemies(delta: float) -> void:
	var weight := clampf(delta * 14.0, 0.0, 1.0)
	for id in _enemies.keys():
		var enemy: Enemy = _enemies[id]
		if not is_instance_valid(enemy):
			_enemies.erase(id)
			continue
		var target: Vector3 = _enemy_targets.get(id, enemy.global_position)
		if enemy.global_position.distance_to(target) > 6.0:
			# Teleport spawn or a huge gap: catch up instantly.
			enemy.global_position = target
		else:
			enemy.global_position = enemy.global_position.lerp(target, weight)
		enemy.rotation.y = lerp_angle(enemy.rotation.y, float(_enemy_yaws.get(id, enemy.rotation.y)), weight)


@rpc("authority", "unreliable_ordered", "call_remote")
func net_enemy_snapshot(data: Array) -> void:
	var seen := {}
	for entry in data:
		var id: int = int(entry[0])
		seen[id] = true
		var enemy: Enemy = _enemies.get(id)
		if enemy == null:
			enemy = _spawn_puppet(String(entry[1]), entry[2] as Vector3)
			if enemy == null:
				continue
			enemy.net_id = id
			_enemies[id] = enemy
		_enemy_targets[id] = entry[2]
		_enemy_yaws[id] = float(entry[3])
		enemy.net_apply_health(float(entry[4]))

	for id in _enemies.keys():
		if not seen.has(id):
			(_enemies[id] as Node).queue_free()
			_enemies.erase(id)
			_enemy_targets.erase(id)
			_enemy_yaws.erase(id)


func _spawn_puppet(kind: String, at: Vector3) -> Enemy:
	var waves := get_tree().get_first_node_in_group("wave_manager") as WaveManager
	if waves == null:
		return null
	var scene := waves.scene_for(kind)
	if scene == null:
		return null
	var enemy := scene.instantiate() as Enemy
	if enemy == null:
		return null
	enemy.net_kind = kind
	enemy.net_puppet = true
	enemy.set_physics_process(false)
	waves.add_child(enemy)
	enemy.global_position = at
	return enemy


# --- Shots ------------------------------------------------------------------

## Called by every weapon. The host resolves it; clients ask the host.
func request_shot(origin: Vector3, direction: Vector3, spread: float,
		pellets: int, damage: float, range_m: float) -> void:
	if multiplayer.is_server():
		_resolve_shot(origin, direction, spread, pellets, damage, range_m)
	else:
		rpc_id(1, "net_shot", origin, direction, spread, pellets, damage, range_m)


@rpc("any_peer", "reliable")
func net_shot(origin: Vector3, direction: Vector3, spread: float,
		pellets: int, damage: float, range_m: float) -> void:
	if not multiplayer.is_server():
		return
	_resolve_shot(origin, direction, spread, pellets, damage, range_m)


func _resolve_shot(origin: Vector3, direction: Vector3, spread: float,
		pellets: int, damage: float, range_m: float) -> void:
	var space := get_world_3d().direct_space_state
	for i in maxi(1, pellets):
		var dir := _spread(direction, spread)
		# world + enemies + props (players are not hittable)
		var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * range_m, 0b1101)
		query.collide_with_areas = false
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var collider: Object = hit["collider"]
		if collider != null and collider.has_method("take_damage"):
			collider.call("take_damage", damage, hit["position"], dir)
		rpc("net_impact", hit["position"], hit["normal"])


func _spread(direction: Vector3, spread_degrees: float) -> Vector3:
	if spread_degrees <= 0.0:
		return direction
	var basis := Basis.looking_at(direction, Vector3.UP)
	var angle := deg_to_rad(spread_degrees) * randf()
	var around := randf() * TAU
	var offset := Vector3(cos(around) * sin(angle), sin(around) * sin(angle), 0.0)
	return (basis * (Vector3(0, 0, -1) + offset)).normalized()


@rpc("authority", "unreliable", "call_remote")
func net_impact(position: Vector3, normal: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var fx := IMPACT_SCENE.instantiate() as Node3D
	fx.position = scene.to_local(position + normal * 0.02)
	scene.add_child(fx)
