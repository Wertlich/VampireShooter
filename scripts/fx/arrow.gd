class_name Arrow
extends Node3D
## A slow, dodgeable projectile: it flies in a straight line and damages the
## first player hit. World geometry stops it, so archers need line of sight.

const IMPACT_SCENE := preload("res://scenes/fx/impact.tscn")

@export var speed: float = 18.0
@export var damage: float = 9.0
@export var lifetime: float = 5.0

var direction: Vector3 = Vector3.FORWARD

var _life: float = 0.0


func launch(dir: Vector3, shot_speed: float, shot_damage: float) -> void:
	direction = dir.normalized()
	speed = shot_speed
	damage = shot_damage
	_life = 0.0
	if absf(direction.dot(Vector3.UP)) > 0.99:
		rotation = Vector3(-PI * 0.5 * signf(direction.y), 0.0, 0.0)
	else:
		look_at(global_position + direction, Vector3.UP)


func _physics_process(delta: float) -> void:
	_life += delta
	if _life > lifetime:
		queue_free()
		return

	var from := global_position
	var to := from + direction * speed * delta
	# Layers 1|2: world geometry and the player. Other enemies are ignored.
	var query := PhysicsRayQueryParameters3D.create(from, to, 3)
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	if not hit.is_empty():
		var collider: Object = hit["collider"]
		if collider != null and collider.has_method("take_damage"):
			collider.call("take_damage", damage, hit["position"], direction)
		else:
			# Sparks on walls, but not in the player's face: a hit on the player
			# already flashes the HUD red.
			_spawn_impact(hit["position"], hit["normal"])
		queue_free()
		return

	global_position = to


func _spawn_impact(position: Vector3, normal: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var fx := IMPACT_SCENE.instantiate() as Node3D
	fx.position = scene.to_local(position + normal * 0.02)
	scene.add_child(fx)
