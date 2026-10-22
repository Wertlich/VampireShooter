extends SceneTree

# Checks weak-point damage and that a group of skeletons does not collapse into
# one spot.
# Usage: godot --headless --path . --script res://tools/test_weakpoint.gd

func _initialize() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var skeleton: Enemy = scene.call("spawn_skeleton")
	await create_timer(0.8).timeout
	var base := skeleton.global_position
	print("weak point at head (y+1.6): ", skeleton.is_weak_point_hit(base + Vector3(0.0, 1.6, 0.0)))
	print("weak point at chest (y+1.0): ", skeleton.is_weak_point_hit(base + Vector3(0.0, 1.0, 0.0)))
	print("weak point at legs (y+0.3): ", skeleton.is_weak_point_hit(base + Vector3(0.0, 0.3, 0.0)))

	var before := skeleton.health
	skeleton.take_damage(10.0, base + Vector3(0.0, 1.0, 0.0), Vector3.FORWARD)
	print("body hit 10 dmg -> hp %.1f (lost %.1f)" % [skeleton.health, before - skeleton.health])
	before = skeleton.health
	skeleton.take_damage(10.0, base + Vector3(0.0, 1.6, 0.0), Vector3.FORWARD)
	print("head hit 10 dmg -> hp %.1f (lost %.1f)" % [skeleton.health, before - skeleton.health])

	# Group test: four skeletons spawned almost on top of each other.
	var group: Array[Enemy] = []
	for i in 4:
		var e: Enemy = scene.call("spawn_skeleton")
		e.global_position = Vector3(0.15 * i, 0.05, -3.0 + 0.1 * i)
		group.append(e)
	await create_timer(4.0).timeout

	var min_distance := 999.0
	for i in group.size():
		for j in range(i + 1, group.size()):
			if is_instance_valid(group[i]) and is_instance_valid(group[j]):
				min_distance = minf(min_distance, group[i].global_position.distance_to(group[j].global_position))
	print("closest pair after 4s: %.2f m (capsules are 0.7 m wide together)" % min_distance)
	for e in group:
		if is_instance_valid(e):
			print("   at ", e.global_position.snapped(Vector3.ONE * 0.1))
	quit()
