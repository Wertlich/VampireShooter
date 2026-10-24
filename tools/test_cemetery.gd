extends SceneTree

# Headless sanity checks for the cemetery map: the scene is wired into Main,
# collision blocks the nave and the fence, lamps are present and flicker, and
# the night sky really uses the cloud/star shader.
# Usage: godot --headless --path . --script res://tools/test_cemetery.gd

var _failures: int = 0


func _initialize() -> void:
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await physics_frame
	await process_frame

	var cemetery := scene.get_node_or_null("Cemetery")
	_check(cemetery != null, "Cemetery is instanced in main.tscn")
	if cemetery == null:
		_finish()
		return

	var graves := cemetery.get_node_or_null("Graves")
	_check(graves != null and graves.get_child_count() >= 60,
			"grave field is populated (%d markers)" % (graves.get_child_count() if graves else 0))
	var fences := cemetery.get_node_or_null("Fence")
	_check(fences != null and fences.get_child_count() >= 40,
			"ruined fence ring is populated (%d pieces)" % (fences.get_child_count() if fences else 0))
	_check(cemetery.has_node("Churches/ChurchIntact"), "intact church is present")
	_check(cemetery.has_node("Churches/ChurchRuined"), "ruined church is present")
	# Cleanup requested after the first playtest: no pews/altar glow inside, no
	# pyramid memorial, no anchor boulder, no broadleaf canopies.
	_check(cemetery.find_children("Pew*", "", true, false).is_empty(), "no pew furniture inside")
	_check(cemetery.find_children("Altar*", "", true, false).is_empty(), "no altar glow spheres")
	_check(cemetery.find_children("Pyramid*", "", true, false).is_empty(), "no pyramid memorial")
	_check(cemetery.find_children("Rock", "", true, false).is_empty(), "no anchor boulder")
	_check(cemetery.find_children("DistantTree*", "", true, false).is_empty()
			and cemetery.find_children("BorderTree*", "", true, false).is_empty(),
			"no broadleaf bush canopies")

	var standing := cemetery.find_children("StandingLamp_*", "", true, false)
	var hanging := cemetery.find_children("HangingLamp_*", "", true, false)
	_check(standing.size() >= 8, "standing lamps around the church/path (%d)" % standing.size())
	_check(hanging.size() >= 2, "hanging lamps inside the churches (%d)" % hanging.size())
	if not standing.is_empty():
		var lamp := standing[0] as CemeteryLamp
		var light := lamp.get_node_or_null("Light") as OmniLight3D
		_check(light != null and light.light_energy > 0.0, "standing lamp has a live light")
		if light:
			var before := light.light_energy
			await create_timer(0.35).timeout
			_check(not is_equal_approx(before, light.light_energy), "lamp light flickers")

	var space := (scene as Node3D).get_world_3d().direct_space_state
	# Ground at the path.
	var ground_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			Vector3(0, 6, 20), Vector3(0, -2, 20), 1))
	_check(not ground_hit.is_empty() and absf(ground_hit.position.y) < 0.15,
			"grass ground has collision (y=%.2f)" % (ground_hit.position.y if not ground_hit.is_empty() else 99.0))
	# The visible nave wall at local x=-2.45 must block the player.
	var nave_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			Vector3(0, 1.2, -1), Vector3(0, 1.2, -8), 1))
	_check(not nave_hit.is_empty() and nave_hit.position.z > -5.2,
			"nave wall blocks the back of the church (z=%.2f)" % (nave_hit.position.z if not nave_hit.is_empty() else 99.0))
	# Fence collision on the east side of the south gate.
	var fence_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			Vector3(10, 1.2, 40), Vector3(10, 1.2, 50), 1))
	_check(not fence_hit.is_empty() and fence_hit.position.z > 43.5 and fence_hit.position.z < 45.5,
			"fence collision sits on the boundary (z=%.2f)" % (fence_hit.position.z if not fence_hit.is_empty() else 99.0))

	var environment := (scene.get_node("WorldEnvironment") as WorldEnvironment).environment
	_check(environment != null and environment.background_mode == Environment.BG_SKY,
			"night environment uses a sky background")
	var sky_material := environment.sky.sky_material as ShaderMaterial
	_check(sky_material != null, "sky uses a shader material")
	if sky_material:
		_check(bool(sky_material.get_shader_parameter("clouds_enabled")), "clouds are enabled in the sky shader")
		_check(bool(sky_material.get_shader_parameter("stars_enabled")), "stars are enabled in the sky shader")
	var moon := scene.get_node_or_null("Moon") as DirectionalLight3D
	_check(moon != null and moon.shadow_enabled, "moon light casts shadows")

	var player := scene.get("player") as Player
	_check(player != null and player.global_position.y > -1.0, "player spawns on the map")
	var bounds := scene.get_node("ArenaBounds") as ArenaBounds
	_check(bounds != null and bounds.half_size >= 45.0, "arena guard rails remain outside the fence")

	print("--- everything is solid ---")
	var prop_body := cemetery.get_node_or_null("PropCollision") as StaticBody3D
	_check(prop_body != null and prop_body.get_child_count() >= 170,
			"prop collision covers graves, monuments, trees, lamps and rubble (%d shapes)"
			% (prop_body.get_child_count() if prop_body else 0))
	if prop_body and graves and graves.get_child_count() > 0:
		var grave := graves.get_child(0) as MeshInstance3D
		var target := (grave.global_transform * grave.mesh.get_aabb()).get_center()
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
				target + Vector3(0, 6, 0), target - Vector3(0, 0.5, 0), 1))
		_check(not hit.is_empty() and hit.collider == prop_body, "a gravestone blocks a ray")
	if prop_body and not standing.is_empty():
		var lamp_model := (standing[0] as Node).get_node_or_null("Model")
		var lamp_hit := false
		if lamp_model:
			for child in lamp_model.find_children("*", "MeshInstance3D", true, false):
				var mi := child as MeshInstance3D
				var lamp_target := (mi.global_transform * mi.mesh.get_aabb()).get_center()
				var probe := space.intersect_ray(PhysicsRayQueryParameters3D.create(
						lamp_target + Vector3(0, 5, 0), lamp_target - Vector3(0, 0.3, 0), 1))
				if not probe.is_empty() and probe.collider == prop_body:
					lamp_hit = true
					break
		_check(lamp_hit, "a standing lamp blocks a ray")
	# The south gate must still be walkable through its opening.
	var gate_probe := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			Vector3(0, 1.2, 42), Vector3(0, 1.2, 46), 1))
	_check(gate_probe.is_empty(), "gate opening stays passable")

	print("--- church access ---")
	var intact_church := cemetery.get_node("Churches/ChurchIntact")
	var ruined_church := cemetery.get_node("Churches/ChurchRuined")
	var intact_collision := intact_church.get_node("Collision") as StaticBody3D
	var ruined_collision := ruined_church.get_node("Collision") as StaticBody3D
	_check(intact_collision.get_child_count() >= 8,
			"intact church collision is split into parts (%d shapes)" % intact_collision.get_child_count())
	_check(ruined_collision.get_child_count() >= 8,
			"ruined church collision is split into parts (%d shapes)" % ruined_collision.get_child_count())
	var intact_ladder := intact_church.get_node("LadderAccess")
	var ruined_ladder := ruined_church.get_node("LadderAccess")
	_check(intact_ladder.get_node_or_null("Climb") is LadderZone
			and ruined_ladder.get_node_or_null("Climb") is LadderZone,
			"ladder triggers exist in both churches (2)")
	_check(intact_ladder.get_node_or_null("Landing") is StaticBody3D
			and ruined_ladder.get_node_or_null("Landing") is StaticBody3D,
			"landings at the top of the ladders are solid (2)")
	var climb_zone := intact_ladder.get_node("Climb") as LadderZone
	_check(climb_zone != null, "the church ladder has a climb trigger")
	if climb_zone and player:
		player.global_position = Vector3(
				climb_zone.global_position.x, climb_zone.global_position.y - 1.4,
				climb_zone.global_position.z)
		player.velocity = Vector3.ZERO
		await physics_frame
		var climb_start := player.global_position.y
		Input.action_press("move_forward")
		await create_timer(0.8).timeout
		var climb_mid := player.global_position.y
		_check(climb_mid > climb_start + 0.8,
				"holding forward climbs the ladder (y %.2f -> %.2f)" % [climb_start, climb_mid])
		await create_timer(0.5).timeout
		Input.action_release("move_forward")
		await create_timer(0.6).timeout
		_check(player.global_position.y > 3.8,
				"the climb ends on the wooden loft (y=%.2f)" % player.global_position.y)

	# Walk up the entrance steps and stop at the visible nave wall instead of
	# clipping through the church's solid core.
	if player:
		player.global_position = Vector3(0, 0.2, 5.0)
		player.velocity = Vector3.ZERO
		player._yaw = 0.0
		player._pitch = 0.0
		Input.action_press("move_forward")
		await create_timer(2.4).timeout
		Input.action_release("move_forward")
		await physics_frame
		var z := player.global_position.z
		_check(player.global_position.y > -0.2 and z < 0.5 and z > -5.2,
				"player walks into the nave and stops at its wall (z=%.2f)" % z)

	_finish()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok    ", label)
	else:
		_failures += 1
		print("  FAIL  ", label)


func _finish() -> void:
	print("")
	if _failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % _failures)
	quit(1 if _failures > 0 else 0)
