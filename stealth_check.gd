extends Node
# Stage 5 wake rules, driven against the real demos/stealth.tscn: they need
# physics (line of sight) and the Metrics autoload, so check.gd cannot host them.
#   $GODOT --headless --path . res://stealth_check.tscn   # prints STEALTH OK

func _ready() -> void:
	var s = load("res://demos/stealth.tscn").instantiate()
	add_child(s)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var p = s.get_node("Player")
	var g1 = s.get_node("Guard1")
	g1.look_sweep = 0.0
	var pa = s.get_node("PairA")
	var pb = s.get_node("PairB")
	var xg = s.get_node("ExitGuard")

	# 1. Behind Guard1 (it faces +Z), 5m away, standing still: nothing wakes it.
	p.global_position = Vector3(0, 1.05, -18)
	await _frames(10)
	print("behind, still: ", g1.awake())
	assert(not g1.awake())

	# 2. Walking behind it within hear_range: heard.
	p.velocity = Vector3(3, 0, 0)
	g1._physics_process(0.016)
	print("behind, walking: ", g1.awake())
	assert(g1.awake())

	# 3. Sneak-walking right behind PairA: still silent (hear 9 * 0.2 = 1.8m).
	s.get_node("Guard1")._awake = false
	p.sneaking = true
	p.global_position = Vector3(-5.0, 1.05, -23)  # 2.4m behind PairA, which faces +X
	p.velocity = Vector3(1, 0, 0)
	pa._physics_process(0.016)
	print("sneak behind pair: ", pa.awake())
	assert(not pa.awake())

	# 4. In front of PairA's cone but past sneak sight (10 * 0.6 = 6m): unseen.
	p.velocity = Vector3.ZERO
	p.global_position = Vector3(4.2, 1.05, -23.5)  # 6.8m, clear line
	pa._physics_process(0.016)
	print("sneak, 6.8m in cone: ", pa.awake())
	assert(not pa.awake())

	# 5. Hitting PairA wakes it, and PairB 1.7m away wakes as an ally.
	pa.take_hit(10.0, 0.0)
	print("hit A -> A, B: ", pa.awake(), " ", pb.awake())
	assert(pa.awake() and pb.awake())

	# 6. Sight: sneaking 3.5m in front of ExitGuard (faces -X) is inside 6m: seen.
	p.global_position = Vector3(1.0, 1.05, -31)
	xg._physics_process(0.016)
	print("sneak, 3.5m in cone: ", xg.awake())
	assert(xg.awake())
	xg._awake = false

	# 7. Cover: Guard1 faces +Z; Crate2 sits on the line to the player. Not sneaking, still.
	g1._awake = false
	p.sneaking = false
	p.global_position = Vector3(5.2, 1.05, -6.5)
	g1._physics_process(0.016)
	print("behind crate, in cone: ", g1.awake())
	assert(not g1.awake())
	p.global_position = Vector3(1.5, 1.05, -6.5)
	g1._physics_process(0.016)
	print("in the open, in cone: ", g1.awake())
	assert(g1.awake())

	# 8. Trap noise: dropping the weight from far off wakes the exit guard (8m < 14).
	s.get_node("Weight").shot()
	print("weight noise -> exit guard: ", xg.awake())
	assert(xg.awake())
	print("STEALTH OK")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
