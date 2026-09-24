extends SceneTree
# Walks Route 1 end to end with real collision and prints ROUTE OK when every
# beat works. Run it after regenerating the route:
#
#   Godot --headless --path . --script res://tools/route1_check.gd
#
# It walks with move_and_slide (or the player's own movement), not teleports,
# wherever a wall or the floor matters. The old straight route passed a
# teleporting test with its bridge blocked. Anything else printed is detail.

var s: Node
var p: Node
var t: Node
var Route: GDScript
# Loaded in _initialize: preloading player.gd here would compile it before the
# autoloads (Metrics) exist.
var Player: GDScript


func _cur() -> void:
	s = current_scene
	p = s.get_node("Player")
	t = s.get_node("Terrain")
	p.set_physics_process(false)


# Walk in a direction with collision; returns how far past the walkable edge
# the player ever got (the walls stand 0.35m out).
func _push(dir: Vector3, secs: float, speed := 5.0) -> float:
	var worst := -INF
	for i in int(secs * 60):
		p.velocity = Vector3(dir.x * speed, p.velocity.y - 0.4, dir.z * speed)
		p.move_and_slide()
		if p.is_on_floor():
			p.velocity.y = 0.0
		worst = maxf(worst, t.sdf(p.global_position.x, p.global_position.z))
		await physics_frame
	return worst


# Glide along waypoints (for stealth: sight and hearing don't care about walls).
func _glide(points: Array, speed: float, sneak: bool) -> void:
	p.sneaking = sneak
	for i in range(1, points.size()):
		var a: Vector3 = points[i - 1]
		var b: Vector3 = points[i]
		var steps := int(a.distance_to(b) / (speed / 60.0))
		for k in steps:
			p.global_position = a.lerp(b, float(k) / steps) + Vector3(0, 1.05, 0)
			p.velocity = (b - a).normalized() * speed
			await physics_frame


# Stand at `pos`, then hold forward for half a second with the player's own
# movement (so hazard slow applies). Returns [standing y, speed].
func _stride(pos: Vector3) -> Array:
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.set_physics_process(true)
	for i in 20:
		await physics_frame
	var y0: float = p.global_position.y
	var from: Vector3 = p.global_position
	Input.action_press("move_forward")
	for i in 30:
		await physics_frame
	Input.action_release("move_forward")
	p.set_physics_process(false)
	return [y0, Vector2(p.global_position.x - from.x, p.global_position.z - from.z).length() / 0.5]


func _die() -> void:
	p.cs.health = 0.0
	for i in 150:
		await physics_frame
	_cur()


func _flat(n: String, y := 1.05) -> Vector3:
	var q: Vector3 = s.get_node(n).global_position
	return Vector3(q.x, y, q.z)


func _initialize() -> void:
	create_timer(180.0).timeout.connect(func(): print("TIMEOUT"); quit(1))
	Route = load("res://route.gd")
	Player = load("res://player.gd")
	Player.unlocked.clear()
	var t0 := Time.get_ticks_msec()
	change_scene_to_file("res://demos/route1.tscn")
	await process_frame
	await process_frame
	paused = false
	_cur()
	print("load+build %d ms, foliage %s" % [Time.get_ticks_msec() - t0, s.get_node("Foliage").counts()])
	assert(Route.leg == 1)

	# Walls: push 8 ways from the Glade and from the first path.
	var worst := -INF
	for origin in [p.global_position, _flat("StumpBarkling")]:
		for k in 8:
			p.global_position = origin
			p.velocity = Vector3.ZERO
			worst = maxf(worst, await _push(Vector3.FORWARD.rotated(Vector3.UP, k * TAU / 8), 3.0))
	s.get_node("StumpBarkling").queue_free()
	print("walls: furthest past the walkable edge %.2f m" % worst)
	assert(worst < 0.5, "walked through a wall")

	# Mud: sunk into it and slowed.
	for n in ["MudBarkling1", "MudBarkling2"]:
		s.get_node(n).queue_free()
	var dry: Array = await _stride(_flat("SignGlade"))
	var wet: Array = await _stride(_flat("Mud"))
	print("mud: dry y %.2f speed %.1f | mud y %.2f speed %.1f (%d%%)" % [dry[0], dry[1], wet[0], wet[1], int(wet[1] / dry[1] * 100.0)])
	assert(wet[0] < dry[0] - 0.25, "the mud didn't sink the player")
	assert(wet[1] < dry[1] * 0.5, "the mud didn't slow the player")

	# The chest: key 2 is locked until it's opened, then it's the bow.
	p._select("shot")
	print("before chest: has bow %s, in hand %s" % [p.has_slot("shot"), p.current_slot()])
	assert(not p.has_slot("shot") and p.current_slot() == "sword" and p.locked_press == "shot")
	var chest: Node3D = s.get_node("Chest")
	var front: Vector3 = chest.global_position - chest.global_transform.basis.z * 1.3
	p.global_position = Vector3(front.x, 1.05, front.z)
	for i in 3:
		await process_frame
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_E
	ev.pressed = true
	var prompt: bool = chest._prompt.visible
	Input.parse_input_event(ev)
	for i in 5:
		await process_frame
	p._select("shot")
	print("chest: prompt %s, opened %s, in hand %s, volley locked %s" % [prompt, chest.opened, p.current_slot(), not p.has_slot("volley")])
	assert(prompt and chest.opened and p.current_slot() == "shot" and not p.has_slot("volley"))

	# A leg 1 death keeps the bow and the open chest.
	await _die()
	print("leg 1 death: leg %d, has bow %s, chest open %s" % [Route.leg, p.has_slot("shot"), s.get_node("Chest").opened])
	assert(Route.leg == 1 and p.has_slot("shot") and s.get_node("Chest").opened)

	# Waystone, then a leg 2 death restarts there.
	var ws := _flat("Waystone", 0.0)
	p.cs.health = 40.0
	p.global_position = ws + Vector3(0, 1.05, 0)
	for i in 5:
		await physics_frame
	assert(p.cs.health == 100.0 and Route.leg == 2, "the waystone didn't heal or set leg 2")
	await _die()
	print("leg 2 death: at waystone %s, leg1 %d, leg2 %d" % [p.global_position.distance_to(ws) < 4.0, get_nodes_in_group("leg1").size(), get_nodes_in_group("leg2").size()])
	assert(Route.leg == 2 and p.global_position.distance_to(ws) < 4.0 and get_nodes_in_group("leg1").is_empty())

	# Sneak the nest lane, in the stretch's own frame.
	var st: Transform3D = s.get_node("Stretch").global_transform
	var lane := []
	for l in [Vector3(0, 0, 11), Vector3(0, 0, 0), Vector3(-2.5, 0, -6), Vector3(-4.3, 0, -8.5), Vector3(-4, 0, -12)]:
		lane.append(st * l)
	await _glide(lane, 2.5, true)
	var awake := s.get_children().filter(func(n): return n.name.begins_with("Rootkin") and n.awake()).size()
	print("nest: carrying %s, rootkin awake %d/5" % [p.carrying.keys(), awake])
	assert(p.carrying.has("satchel") and awake == 0)
	for g in get_nodes_in_group("leg2"):
		if g.name.begins_with("Group"):
			g.queue_free()

	# Ravine: the lip holds, the ring drops the bridge, and the bridge holds you.
	var lip: Node3D = s.get_node("RavineLip")
	var fwd: Vector3 = -lip.global_transform.basis.z
	var lip_pos := lip.global_position  # the trigger frees the wall
	var start := Vector3(lip_pos.x, 1.05, lip_pos.z) - fwd * 3.0
	p.global_position = start
	p.velocity = Vector3.ZERO
	await _push(fwd, 2.0)
	var held: float = (p.global_position - lip_pos).dot(fwd)
	var ring := _flat("FellTree", 0.0)
	await _glide([Vector3(start.x, 0, start.z), ring], 3.0, false)
	for i in 3:
		await physics_frame
	var dropped: bool = s.get_node("Bridge").visible
	p.global_position = start
	p.velocity = Vector3.ZERO
	var min_y := INF
	for i in 180:
		p.velocity = Vector3(fwd.x * 5.0, p.velocity.y - 0.4, fwd.z * 5.0)
		p.move_and_slide()
		if p.is_on_floor():
			p.velocity.y = 0.0
		min_y = minf(min_y, p.global_position.y)
		await physics_frame
	var crossed: float = (p.global_position - lip_pos).dot(fwd)
	print("ravine: lip held %s, bridge dropped %s, crossed %.1f m, lowest y %.2f" % [held < 0.0, dropped, crossed, min_y])
	assert(held < 0.0 and dropped and crossed > 8.0 and min_y > 0.5 and not p.cs.dead())

	# Settlement 2 ends the run, and a new run starts without the bow.
	await _glide([Vector3(p.global_position.x, 0, p.global_position.z), _flat("Exit", 0.0)], 5.0, false)
	for i in 5:
		await physics_frame
	print("Settlement 2: over %s, winner %s, leg %d, bow cleared %s" % [s._over, s._winner, Route.leg, not Player.unlocked.get("shot", false)])
	assert(s._over and s._winner == "sneaked" and Route.leg == 1 and not Player.unlocked.get("shot", false))
	print("ROUTE OK")
	quit()
