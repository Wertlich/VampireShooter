class_name WaveManager
extends Node3D
## Runs the horde in waves: a fixed number of waves per map, a break between
## them, a linear size curve and a per-wave enemy mix that fades the weak
## enemies out as the strong ones come in.
##
## Wave sizes with the default curve: 5, 10, 15, 20, ... — five more every wave.
## The last wave is a single boss instead of the curve.
## Every number here is exported so a map can be tuned without touching code.

signal wave_started(index: int, size: int, total: int)
signal wave_cleared(index: int)
signal break_started(seconds: float)
signal all_waves_cleared

enum State { IDLE, BREAK, SPAWNING, FIGHTING, FINISHED }

## Enemy mix per wave: {kind: weight}. Kinds are the roster names below.
## Skeletons fade out by wave 7, zombies by wave 10 — every new wave brings more
## of the heavy enemies and fewer of the old ones. A wave missing from the table
## is pure skeletons. The boss wave ignores this table entirely.
const WAVE_MIX := {
	1: {"skeleton": 1.0},
	2: {"skeleton": 1.0},
	3: {"skeleton": 0.7, "zombie": 0.3},
	4: {"skeleton": 0.45, "zombie": 0.4, "archer": 0.15},
	5: {"skeleton": 0.25, "zombie": 0.45, "archer": 0.3},
	6: {"skeleton": 0.1, "zombie": 0.4, "archer": 0.3, "slime": 0.2},
	7: {"zombie": 0.35, "archer": 0.3, "slime": 0.35},
	8: {"zombie": 0.2, "archer": 0.3, "slime": 0.5},
	9: {"zombie": 0.1, "archer": 0.25, "slime": 0.65},
}

@export_group("Wave Curve")
## Overrides the default mix for matching wave numbers. Boss wave takes precedence.
@export var compositions: Array[WaveComposition] = _default_compositions()
## Waves one map is worth. Later maps reuse the same curve.
@export var waves_per_map: int = 10
## Enemies in the first wave.
@export var first_wave_size: int = 5
## How many more enemies every next wave brings (5 = 5, 10, 15, 20...).
@export var wave_size_step: int = 5
## Seconds of calm between a cleared wave and the next one.
@export var break_seconds: float = 10.0
## Grace period on load, before the first wave.
@export var first_wave_delay: float = 3.0

@export_group("Enemy Roster")
@export var skeleton_scene: PackedScene
@export var zombie_scene: PackedScene
@export var slime_scene: PackedScene
@export var archer_scene: PackedScene
@export var boss_scene: PackedScene
## The boss arrives alone, without the usual crowd.
@export var boss_wave: int = 10

@export_group("Spawn")
## Ring around the player where enemies are allowed to rise.
@export var spawn_radius_min: float = 12.0
@export var spawn_radius_max: float = 18.0
## Used to keep spawns inside the castle walls.
@export var arena_half_size: float = 46.0
## A wave pours in over this many ticks instead of all at once, so a big wave
## does not stall the frame it arrives on.
@export var spawn_ticks: int = 20
@export var spawn_tick_seconds: float = 0.2

var state: State = State.IDLE
## 1-based number of the wave being fought or just cleared.
var wave_index: int = 0
## Enemies this wave is worth in total.
var wave_size: int = 0
## Enemies killed across the run, for the end screen.
var kills: int = 0
## Seconds left before the next wave starts.
var break_left: float = 0.0

var _queue: Array[PackedScene] = []
var _spawned: int = 0
var _batch: int = 1
var _tick_left: float = 0.0
var _started: bool = false

static func _default_compositions() -> Array[WaveComposition]:
	var result: Array[WaveComposition] = []
	for index in WAVE_MIX:
		var composition := WaveComposition.new()
		composition.wave = index
		composition.skeleton = 0.0
		for kind in WAVE_MIX[index]:
			composition.set(kind, WAVE_MIX[index][kind])
		result.append(composition)
	return result


func _enter_tree() -> void:
	# Registered here, not in _ready(): the HUD sits earlier in the scene tree
	# and looks the manager up while its own _ready runs.
	add_to_group("wave_manager")


func _ready() -> void:
	# Only the host simulates the horde; clients get snapshots from it.
	if Net.is_online() and not multiplayer.is_server():
		return
	# Tools and screenshot passes spawn their own enemies; auto-starting waves
	# there would move the camera target around mid-capture.
	if DisplayServer.get_name() == "headless" or "--capture" in OS.get_cmdline_user_args():
		return
	begin()


func _process(delta: float) -> void:
	if Net.is_online() and not multiplayer.is_server():
		return
	match state:
		State.BREAK:
			break_left = maxf(0.0, break_left - delta)
			if break_left <= 0.0:
				_start_wave(wave_index + 1)
		State.SPAWNING:
			_tick_left -= delta
			while _tick_left <= 0.0 and _spawned < wave_size:
				_spawn_batch()
				_tick_left += maxf(spawn_tick_seconds, 0.02)
			if _spawned >= wave_size:
				state = State.FIGHTING
		State.FIGHTING:
			# Dead enemies leave the "enemies" group immediately, so an empty
			# group means the wave is done.
			if alive_count() == 0:
				_clear_wave()


# --- Public API -------------------------------------------------------------

func begin() -> void:
	if _started:
		return
	_started = true
	wave_index = 0
	kills = 0
	state = State.BREAK
	break_left = first_wave_delay
	break_started.emit(break_left)


## Starts the next wave right now, skipping the break. Used by tests.
func force_next_wave() -> void:
	if state == State.FINISHED:
		return
	_start_wave(wave_index + 1)


func wave_size_for(index: int) -> int:
	return maxi(1, first_wave_size + wave_size_step * (index - 1))


## How many of each enemy kind a wave is made of. Exact sum: the rounding
## remainder goes to the kinds with the biggest fractions.
func roster_for(index: int) -> Dictionary:
	if index == boss_wave:
		return {"boss": 1}

	var size := wave_size_for(index)
	var mix: Dictionary = WAVE_MIX.get(index, {"skeleton": 1.0})
	for composition in compositions:
		if composition != null and composition.wave == index:
			mix = composition.weights()
			break
	var weight_sum := 0.0
	for kind in mix:
		weight_sum += float(mix[kind])
	if weight_sum <= 0.0:
		return {"skeleton": size}

	var counts := {}
	var fractions: Array[Dictionary] = []
	var assigned := 0
	for kind in mix:
		var exact := size * float(mix[kind]) / weight_sum
		var take := int(floor(exact))
		counts[kind] = take
		assigned += take
		fractions.append({"kind": kind, "fraction": exact - take})

	fractions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["fraction"]) > float(b["fraction"]))
	var i := 0
	while assigned < size:
		var kind: String = fractions[i % fractions.size()]["kind"]
		counts[kind] = int(counts[kind]) + 1
		assigned += 1
		i += 1

	for kind in counts.keys():
		if int(counts[kind]) <= 0:
			counts.erase(kind)
	return counts


func scene_for(kind: String) -> PackedScene:
	match kind:
		"skeleton":
			return skeleton_scene
		"zombie":
			return zombie_scene
		"slime":
			return slime_scene
		"archer":
			return archer_scene
		"boss":
			return boss_scene
	return null


func alive_count() -> int:
	return get_tree().get_nodes_in_group("enemies").size()


## One-line status for the HUD.
func status_text() -> String:
	match state:
		State.BREAK:
			if wave_index <= 0:
				return "ПЕРВАЯ ВОЛНА ЧЕРЕЗ %d" % ceili(break_left)
			return "ВОЛНА %d/%d ЗАЧИЩЕНА · СЛЕДУЮЩАЯ ЧЕРЕЗ %d" % [
				wave_index, waves_per_map, ceili(break_left)]
		State.SPAWNING, State.FIGHTING:
			if wave_index == boss_wave:
				return "ВОЛНА %d/%d · БОСС" % [wave_index, waves_per_map]
			return "ВОЛНА %d/%d" % [wave_index, waves_per_map]
		State.FINISHED:
			return "ВСЕ %d ВОЛН ОТБИТЫ" % waves_per_map
	return ""


## Spawns one skeleton, at `at` or at a free spot around the player. Used by the
## capture pass and by the test tools; gameplay spawns through the wave queue.
func spawn_one(at: Vector3 = Vector3.INF) -> Enemy:
	return spawn_kind("skeleton", at)


func spawn_kind(kind: String, at: Vector3 = Vector3.INF) -> Enemy:
	var scene := scene_for(kind)
	if scene == null:
		push_error("WaveManager: no scene for enemy kind '%s'" % kind)
		return null
	var enemy := scene.instantiate() as Enemy
	if enemy == null:
		push_error("WaveManager: scene for '%s' is not an Enemy" % kind)
		return null
	enemy.net_kind = kind
	enemy.died.connect(_on_enemy_died)
	add_child(enemy)
	enemy.global_position = _find_spawn_position() if at == Vector3.INF else at
	return enemy


func restart() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	wave_index = 0
	_spawned = 0
	kills = 0
	_started = false
	state = State.IDLE
	begin()


# --- Internals --------------------------------------------------------------

func _start_wave(index: int) -> void:
	wave_index = index
	_queue = build_queue(index)
	wave_size = _queue.size()
	_spawned = 0
	_batch = maxi(1, ceili(float(wave_size) / float(maxi(1, spawn_ticks))))
	_tick_left = 0.0
	state = State.SPAWNING
	wave_started.emit(wave_index, wave_size, waves_per_map)


func build_queue(index: int) -> Array[PackedScene]:
	var queue: Array[PackedScene] = []
	var roster := roster_for(index)
	for kind in roster:
		var scene := scene_for(kind)
		if scene == null:
			push_error("WaveManager: no scene for enemy kind '%s'" % kind)
			continue
		for i in int(roster[kind]):
			queue.append(scene)
	queue.shuffle()
	return queue


func _spawn_batch() -> void:
	for i in _batch:
		if _spawned >= _queue.size():
			return
		_spawn_from_queue(_queue[_spawned])
		_spawned += 1


func _spawn_from_queue(scene: PackedScene) -> void:
	var enemy := scene.instantiate() as Enemy
	if enemy == null:
		return
	enemy.net_kind = kind_for_scene(scene)
	enemy.died.connect(_on_enemy_died)
	add_child(enemy)
	enemy.global_position = _find_spawn_position()


## Roster name of a scene, so clients know what to instantiate.
func kind_for_scene(scene: PackedScene) -> String:
	for kind in ["skeleton", "zombie", "slime", "archer", "boss"]:
		if scene_for(kind) == scene:
			return kind
	return "skeleton"


func _clear_wave() -> void:
	wave_cleared.emit(wave_index)
	if wave_index >= waves_per_map:
		state = State.FINISHED
		all_waves_cleared.emit()
		return
	state = State.BREAK
	break_left = break_seconds
	break_started.emit(break_left)


func _on_enemy_died(_enemy: Enemy) -> void:
	kills += 1


func _find_spawn_position() -> Vector3:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return global_position

	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 0.6
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 5  # world geometry + already spawned enemies

	for i in 12:
		var angle := randf() * TAU
		var distance := randf_range(spawn_radius_min, spawn_radius_max)
		var candidate := player.global_position + Vector3(cos(angle), 0.0, sin(angle)) * distance
		candidate.x = clampf(candidate.x, -arena_half_size, arena_half_size)
		candidate.z = clampf(candidate.z, -arena_half_size, arena_half_size)
		if candidate.distance_to(player.global_position) < spawn_radius_min:
			continue
		candidate.y = 1.0
		query.transform = Transform3D(Basis(), candidate)
		if space.intersect_shape(query, 1).is_empty():
			candidate.y = 0.05
			return candidate

	# Keep the minimum distance even when random attempts are blocked.
	for angle in range(0, 360, 30):
		var radians := deg_to_rad(float(angle))
		var candidate := player.global_position + Vector3(cos(radians), 0.0, sin(radians)) * spawn_radius_min
		candidate.x = clampf(candidate.x, -arena_half_size, arena_half_size)
		candidate.z = clampf(candidate.z, -arena_half_size, arena_half_size)
		if candidate.distance_to(player.global_position) < spawn_radius_min:
			continue
		candidate.y = 1.0
		query.transform = Transform3D(Basis(), candidate)
		if space.intersect_shape(query, 1).is_empty():
			candidate.y = 0.05
			return candidate

	# If every valid point is blocked, keep the distance rule instead of spawning
	# nearby. This is preferable to clamping inside the arena and breaking the
	# minimum-distance guarantee.
	var fallback := player.global_position + Vector3.RIGHT * spawn_radius_min
	fallback.y = 0.05
	return fallback
