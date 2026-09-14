extends SceneTree
# The one runnable check. No framework, plain asserts.
#
#   Godot --headless --path /Users/wesleychase/Dev/isolated --script res://check.gd
#
# Prints OK and nothing else when the four things that silently ruin a feel test
# are intact. Anything else printed is a failure.
#
# assert() is compiled out of export templates, so run this with the editor
# binary (a debug build). The contract is simply: no "OK", something is wrong.

const CombatState := preload("res://combat_state.gd")
const Gesture := preload("res://gesture.gd")
const Stance := preload("res://stance_state.gd")
const CamRel := preload("res://camera_relative.gd")
const DT := 1.0 / 60.0


func _initialize() -> void:
	_non_cancellable()
	_stamina_gates()
	_iframes()
	_regen_delay()
	_damage_and_iframes()
	_health_never_regenerates()
	_hit_arc()
	_stagger()
	_gesture_held_gate()
	_gesture_crossing()
	_cone_clamp()
	_rotation_rates()
	_chain()
	_bow_drag()
	_no_regen_while_stanced()
	_block()
	_parry_flag()
	print("OK")
	quit()


func _fresh():
	var cs := CombatState.new()
	cs.stamina = cs.stamina_max
	return cs


# 1. A swing cannot be cancelled - not by another attack, not by a dodge.
func _non_cancellable() -> void:
	var cs = _fresh()
	assert(cs.advance(DT, true, false) == "attack")
	var frames := int((cs.windup_time + cs.active_time + cs.recovery_time) / DT) - 3
	var seen := {}
	for i in frames:
		var ev: String = cs.advance(DT, true, true)  # mash both, every frame
		assert(ev == "ignored", "swing was interruptible at frame %d: %s" % [i, ev])
		assert(cs.state != CombatState.DODGE, "a dodge cancelled the swing")
		seen[cs.state] = true
	assert(seen.has(CombatState.WINDUP), "no wind-up phase")
	assert(seen.has(CombatState.ACTIVE), "no active phase")
	assert(seen.has(CombatState.RECOVERY), "no recovery phase")
	assert(
		cs.stamina >= cs.stamina_max - cs.attack_cost - 0.001,
		"mashing during a swing spent stamina more than once"
	)


# 2. Stamina gates both verbs.
func _stamina_gates() -> void:
	var cs = _fresh()
	cs.stamina = 1.0
	assert(cs.advance(DT, true, false) == "attack_refused")
	assert(cs.state == CombatState.IDLE, "a refused attack still changed state")

	cs = _fresh()
	cs.stamina = 1.0
	assert(cs.advance(DT, false, true) == "dodge_refused")
	assert(cs.state == CombatState.IDLE, "a refused dodge still changed state")

	cs = _fresh()
	assert(cs.advance(DT, true, false) == "attack", "full stamina could not attack")
	cs = _fresh()
	assert(cs.advance(DT, false, true) == "dodge", "full stamina could not dodge")


# 3. I-frames open late and close before the dodge ends.
func _iframes() -> void:
	var cs = _fresh()
	assert(cs.advance(DT, false, true) == "dodge")
	assert(not cs.invulnerable(), "i-frames were open on the dodge's first frame")
	var open := 0
	for i in int(cs.dodge_time / DT) + 4:
		cs.advance(DT, false, false)
		if cs.state != CombatState.DODGE:
			break
		if cs.t < cs.iframe_start:
			assert(not cs.invulnerable(), "i-frames opened before iframe_start")
		if cs.t >= cs.iframe_end:
			assert(not cs.invulnerable(), "i-frames stayed open past iframe_end")
		if cs.invulnerable():
			open += 1
	assert(cs.state != CombatState.DODGE, "the dodge never ended")
	assert(not cs.invulnerable(), "i-frames still open after the dodge ended")
	var expected := int(round((cs.iframe_end - cs.iframe_start) / DT))
	assert(
		absi(open - expected) <= 1,
		"i-frames open for %d frames, expected ~%d" % [open, expected]
	)


# 4. Regen waits, then runs, then stops at the cap.
func _regen_delay() -> void:
	var cs = _fresh()
	cs.advance(DT, true, false)
	var after: float = cs.stamina
	assert(after < cs.stamina_max, "attacking cost nothing")
	for i in int(cs.regen_delay / DT) - 2:
		cs.advance(DT, false, false)
	assert(is_equal_approx(cs.stamina, after), "stamina regenerated during the delay")
	for i in 30:
		cs.advance(DT, false, false)
	assert(cs.stamina > after, "stamina never started regenerating")
	for i in 600:
		cs.advance(DT, false, false)
	assert(is_equal_approx(cs.stamina, cs.stamina_max), "regen missed or overshot the cap")


# 5. Damage lands normally, and i-frames eat it mid-dodge.
func _damage_and_iframes() -> void:
	var cs = _fresh()
	assert(cs.take_damage(30.0), "a normal hit did not land")
	assert(is_equal_approx(cs.health, 70.0), "damage did not come off health")

	# Roll, then step to the middle of the i-frame window.
	cs = _fresh()
	assert(cs.advance(DT, false, true) == "dodge")
	while cs.t < (cs.iframe_start + cs.iframe_end) * 0.5:
		cs.advance(DT, false, false)
	assert(cs.invulnerable(), "not invulnerable in the middle of the dodge")
	var before: float = cs.health
	assert(not cs.take_damage(30.0), "i-frames did not eat the hit")
	assert(is_equal_approx(cs.health, before), "took damage while invulnerable")

	# Tail of the dodge is vulnerable again - a late dodge must lose.
	while cs.state == CombatState.DODGE and cs.t < cs.iframe_end:
		cs.advance(DT, false, false)
	assert(not cs.invulnerable(), "i-frames outlasted iframe_end")
	assert(cs.take_damage(30.0), "the vulnerable tail of the dodge ate a hit")

	# Death floors at zero rather than going negative.
	cs = _fresh()
	assert(cs.take_damage(500.0), "a lethal hit did not land")
	assert(cs.health == 0.0, "health went past zero: %f" % cs.health)
	assert(cs.dead(), "dead() false at zero health")
	assert(not cs.take_damage(10.0), "a corpse took another hit")


# 6. Health does not come back. This is the attrition hypothesis, so a stray
#    regen here would quietly invalidate stage 3 rather than fail loudly.
func _health_never_regenerates() -> void:
	var cs = _fresh()
	cs.take_damage(40.0)
	for i in 1200:  # 20 seconds, far longer than any stamina regen
		cs.advance(DT, false, false)
	assert(is_equal_approx(cs.health, 60.0), "health regenerated to %f" % cs.health)
	assert(is_equal_approx(cs.stamina, cs.stamina_max), "stamina did NOT regen - wrong knob")


# 7. The hit cone: in front connects, behind and far do not.
func _hit_arc() -> void:
	var origin := Vector3.ZERO
	var fwd := Vector3(0, 0, -1)
	assert(CombatState.in_arc(origin, fwd, Vector3(0, 0, -1.5), 2.0, 55.0), "straight ahead missed")
	assert(not CombatState.in_arc(origin, fwd, Vector3(0, 0, -3.0), 2.0, 55.0), "out of reach hit")
	assert(not CombatState.in_arc(origin, fwd, Vector3(0, 0, 1.5), 2.0, 55.0), "hit something behind")
	assert(not CombatState.in_arc(origin, fwd, Vector3(1.5, 0, 0), 2.0, 55.0), "hit 90 deg to the side")
	assert(CombatState.in_arc(origin, fwd, Vector3(0.5, 0, -1.0), 2.0, 55.0), "missed inside the arc")
	# Height is ignored on purpose: everything stands on one flat plane.
	assert(CombatState.in_arc(origin, fwd, Vector3(0, 9, -1.5), 2.0, 55.0), "height broke the arc")


# 8. Stagger: the one external interrupt. Freezes an actor completely, and must
#    never be shortened or stacked by a follow-up hit.
func _stagger() -> void:
	var cs = _fresh()
	cs.stagger(0.3)
	assert(cs.state == CombatState.STAGGER, "stagger did not enter the state")
	assert(cs.busy(), "a staggered actor reported not busy")

	# Frozen: input is ignored for the whole duration.
	var frames := int(0.3 / DT) - 2
	for i in frames:
		assert(cs.advance(DT, true, true) == "ignored", "acted while staggered, frame %d" % i)
		assert(cs.state == CombatState.STAGGER, "left stagger early at frame %d" % i)
	for i in 5:
		cs.advance(DT, false, false)
	assert(cs.state == CombatState.IDLE, "stagger never ended: %s" % cs.state_name())

	# A shorter follow-up must not cut an existing stagger short.
	cs = _fresh()
	cs.stagger(0.5)
	for i in 6:
		cs.advance(DT, false, false)
	cs.stagger(0.1)
	assert(cs.stagger_time > 0.4, "a shorter stagger truncated a longer one")

	# A longer one does extend it.
	cs = _fresh()
	cs.stagger(0.2)
	cs.stagger(0.6)
	assert(is_equal_approx(cs.stagger_time, 0.6), "a longer stagger did not extend")

	# Corpses do not flinch.
	cs = _fresh()
	cs.take_damage(500.0)
	cs.stagger(0.5)
	assert(cs.state != CombatState.STAGGER, "a dead actor was staggered")

	# A committed swing is immune. This is the rule that stops stunlock: without
	# it, hits land faster than the 0.6s telegraph and the enemy never attacks.
	cs = _fresh()
	assert(cs.advance(DT, true, false) == "attack")
	cs.advance(DT, false, false)
	assert(cs.state == CombatState.WINDUP)
	cs.stagger(0.3)
	assert(cs.state == CombatState.WINDUP, "stagger cancelled a wind-up: stunlock")
	while cs.state == CombatState.WINDUP:
		cs.advance(DT, false, false)
	assert(cs.state == CombatState.ACTIVE)
	cs.stagger(0.3)
	assert(cs.state == CombatState.ACTIVE, "stagger cancelled an active swing")
	# ...but RECOVERY is interruptible, which is what rewards a correctly timed hit.
	while cs.state == CombatState.ACTIVE:
		cs.advance(DT, false, false)
	assert(cs.state == CombatState.RECOVERY)
	cs.stagger(0.3)
	assert(cs.state == CombatState.STAGGER, "a punish-window hit did not stagger")


const FAST := Vector2(2000, 0)
const STEP := Vector2(40, 0)


# 9. §11-1: gestures register ONLY while a button is held. Free aiming at a
#    moving enemy is constant fast motion; without this it swings constantly.
func _gesture_held_gate() -> void:
	var g = Gesture.new()
	for i in 100:
		g.tick(DT)
		assert(g.sample(STEP, FAST) == Vector2.ZERO, "flicked while not held, sample %d" % i)
	g.press()
	g.tick(DT)
	assert(g.sample(STEP, FAST) != Vector2.ZERO, "held, above threshold, did not flick")

	# A flick already in progress must not carry into the press.
	g = Gesture.new()
	for i in 10:
		g.tick(DT)
		g.sample(STEP, FAST)
	g.press()
	g.tick(DT)
	assert(g.sample(STEP, FAST) != Vector2.ZERO, "press should re-arm after fast free motion")

	# Phantom motion events carry a velocity but no movement.
	g = Gesture.new()
	g.press()
	assert(g.sample(Vector2.ZERO, FAST) == Vector2.ZERO, "fired on a zero-relative event")


# 10. §11-2: fire on threshold CROSSING, not gesture completion. The index the
#     fire happens at is literally the difference between the two.
func _gesture_crossing() -> void:
	var g = Gesture.new()
	g.press()
	var speeds := [0, 200, 600, 1100, 1400, 1900, 2400, 1900, 1100, 400, 0]
	var fired := []
	for i in speeds.size():
		g.tick(DT)
		if g.sample(STEP, Vector2(speeds[i], 0)) != Vector2.ZERO:
			fired.append(i)
	assert(fired.size() == 1, "expected exactly one fire, got %s" % [fired])
	assert(fired[0] == 4, "fired at index %d; 4 is the first sample over 1200 (peak is 6)" % fired[0])

	# Sustained fast motion is one flick, not sixty.
	g = Gesture.new()
	g.press()
	var n := 0
	for i in 60:
		g.tick(DT)
		if g.sample(STEP, FAST) != Vector2.ZERO:
			n += 1
	assert(n == 1, "sustained drag fired %d times, expected 1" % n)

	# Flick, stop the mouse dead, flick again. A still mouse sends no events, so
	# nothing can bring the speed back under the threshold - only the idle reset
	# can. Without it the second flick is eaten and chaining is impossible.
	g = Gesture.new()
	g.press()
	g.tick(DT)
	assert(g.sample(STEP, FAST) != Vector2.ZERO, "first flick did not fire")
	for i in 30:  # half a second of dead-still mouse: no sample() at all
		g.tick(DT)
	assert(g.sample(STEP, FAST) != Vector2.ZERO, "flick-pause-flick ate the second flick")

	# Refractory: dip and re-cross too soon does nothing; after it, fires again.
	g = Gesture.new()
	g.press()
	g.tick(DT); g.sample(STEP, FAST)
	g.tick(DT); g.sample(STEP, Vector2(100, 0))
	g.tick(DT)
	assert(g.sample(STEP, FAST) == Vector2.ZERO, "re-fired inside the refractory window")
	for i in 20:
		g.tick(DT)
		g.sample(STEP, Vector2(100, 0))
	assert(g.sample(STEP, FAST) != Vector2.ZERO, "never re-armed after the refractory window")


# 11. §11-3: the cone clamps and never rotates the player.
func _cone_clamp() -> void:
	assert(is_equal_approx(Stance.clamp_cone(0.0, deg_to_rad(120), 60.0), deg_to_rad(60)),
		"+120 did not clamp to +60")
	assert(is_equal_approx(Stance.clamp_cone(0.0, deg_to_rad(-120), 60.0), deg_to_rad(-60)),
		"-120 did not clamp to -60")
	assert(is_equal_approx(Stance.clamp_cone(0.0, deg_to_rad(30), 60.0), deg_to_rad(30)),
		"an in-cone flick was altered")
	# The wrap case: facing +170, flick -170. True delta is +20, well inside.
	var got: float = Stance.clamp_cone(deg_to_rad(170), deg_to_rad(-170), 60.0)
	assert(is_equal_approx(wrapf(got - deg_to_rad(170), -PI, PI), deg_to_rad(20)),
		"wrap-around clamped a 20 deg flick: %f deg" % rad_to_deg(got - deg_to_rad(170))
	)
	# Directly behind clamps to an edge rather than failing.
	var back: float = Stance.clamp_cone(0.0, PI, 60.0)
	assert(absf(absf(wrapf(back, -PI, PI)) - deg_to_rad(60)) < 0.001,
		"a flick straight backwards did not clamp to a cone edge")


# 12. §11-4: rotation clamp differs per state, and the bow locks facing.
func _rotation_rates() -> void:
	assert(Stance.rot_rate(Stance.NONE, CombatState.IDLE) == 720.0)
	assert(Stance.rot_rate(Stance.SWORD, CombatState.IDLE) == 180.0)
	assert(Stance.rot_rate(Stance.BLOCK, CombatState.IDLE) == 180.0)
	assert(Stance.rot_rate(Stance.BOW, CombatState.IDLE) == 0.0, "bow draw did not lock facing")
	assert(Stance.rot_rate(Stance.NONE, CombatState.WINDUP) == 0.0, "free to turn mid-swing")
	assert(Stance.rot_rate(Stance.NONE, CombatState.ACTIVE) == 0.0, "free to turn mid-swing")
	assert(Stance.move_mult(Stance.NONE) == 1.0)
	assert(Stance.move_mult(Stance.SWORD) == 0.5)
	assert(Stance.move_mult(Stance.BLOCK) == 0.4)
	assert(Stance.move_mult(Stance.BOW) == 0.35)


func _run_swing(cs, ss) -> void:
	while cs.state != CombatState.IDLE:
		cs.advance(DT, false, false, ss.drain())
		ss.tick(DT, cs.state)


# 13. §11-5: chain caps at 3 and alternates side automatically.
func _chain() -> void:
	var cs = _fresh()
	var ss = Stance.new()
	ss.enter(Stance.SWORD)
	var sides := []
	var costs := []
	for i in 3:
		assert(ss.can_chain(), "could not chain at swing %d" % (i + 1))
		var before: float = cs.stamina
		costs.append(ss.swing_cost())
		assert(cs.try_attack(ss.swing_cost()), "swing %d refused" % (i + 1))
		ss.on_swing()
		sides.append(ss.side)
		_run_swing(cs, ss)
		cs.stamina = before  # isolate chaining from the stamina economy here
	assert(ss.chain == 3, "chain counted %d" % ss.chain)
	assert(not ss.can_chain(), "chain did not cap at 3")
	assert(sides == [1, -1, 1], "side did not alternate: %s" % [sides])
	assert(costs[0] == ss.charged_cost, "first swing was not the charged cost")
	assert(costs[1] == ss.chain_cost and costs[2] == ss.chain_cost, "follow-ups were not light")

	# Charge applies to the first swing only (§4).
	ss = Stance.new()
	ss.enter(Stance.SWORD)
	for i in 120:
		ss.tick(DT, CombatState.IDLE)
	assert(ss.charge_level() > 0.99, "charge did not reach max")
	ss.on_swing()
	for i in 20:
		ss.tick(DT, CombatState.IDLE)
	assert(ss.charge_level() == 0.0, "a chained swing accumulated charge")

	# Letting the window lapse resets the chain.
	ss = Stance.new()
	ss.enter(Stance.SWORD)
	ss.on_swing()
	assert(ss.chain == 1)
	for i in int((ss.chain_window + 0.1) / DT):
		ss.tick(DT, CombatState.IDLE)
	assert(ss.chain == 0, "chain did not reset after the window lapsed")

	# Insufficient stamina ends the chain (§4).
	cs = _fresh()
	ss = Stance.new()
	ss.enter(Stance.SWORD)
	cs.stamina = ss.chain_cost - 1.0
	assert(not cs.try_attack(ss.swing_cost()), "swung without the stamina for it")


# 14. §11-6: bow fires opposite the drag, strength proportional to distance.
func _bow_drag() -> void:
	var g = Gesture.new()
	g.press()
	g.sample(Vector2(100, 0), Vector2(10, 0))
	assert(g.drag == Vector2(100, 0), "drag did not accumulate")
	assert(is_equal_approx(g.drag_strength(), 100.0 / 300.0), "strength is not proportional")
	# Fire direction is the opposite vector - that is the whole bow.
	assert((-g.drag).normalized() == Vector2(-1, 0), "fire direction was not opposite the drag")

	g = Gesture.new()
	g.press()
	g.sample(Vector2(150, 0), Vector2(10, 0))
	assert(is_equal_approx(g.drag_strength(), 0.5), "150px of 300 was not half strength")
	g.sample(Vector2(750, 0), Vector2(10, 0))
	assert(g.drag_strength() == 1.0, "strength exceeded 1.0 at 900px")

	# A new draw starts clean.
	g.press()
	assert(g.drag == Vector2.ZERO and g.drag_strength() == 0.0, "drag survived a new press")


# 15. §8/§11-10: no stamina regeneration while any stance is held.
func _no_regen_while_stanced() -> void:
	var cs = _fresh()
	var prev: float = cs.stamina
	for i in 600:
		cs.advance(DT, false, false, 12.0)
		assert(cs.stamina <= prev + 0.0001, "stamina rose while a stance was held")
		prev = cs.stamina
	assert(cs.stamina == 0.0, "600 frames of drain did not empty the bar")

	# Releasing the stance lets it come back.
	for i in 600:
		cs.advance(DT, false, false, 0.0)
	assert(is_equal_approx(cs.stamina, cs.stamina_max), "stamina did not recover after release")

	# The enemy's call is unchanged by the new parameter.
	cs = _fresh()
	cs.stamina = 50.0
	cs.advance(DT, false, false)
	assert(cs.stamina > 50.0, "the default drain broke ordinary regeneration")


# 16. §11-7: block absorbs at a stamina cost and breaks when the bar empties.
func _block() -> void:
	var cs = _fresh()
	var ss = Stance.new()
	ss.enter(Stance.BLOCK)
	cs.stamina = 45.0

	assert(ss.resolve_hit(cs, 100.0) == "blocked", "block did not absorb")
	assert(is_equal_approx(cs.health, 75.0), "chip was not 25%%: health %f" % cs.health)
	assert(is_equal_approx(cs.stamina, 25.0), "block did not cost 20 stamina")

	assert(ss.resolve_hit(cs, 100.0) == "blocked", "second block did not absorb")
	assert(is_equal_approx(cs.stamina, 5.0))

	# Third hit empties the bar: stance drops and the player is staggered.
	assert(ss.resolve_hit(cs, 100.0) == "broken", "stance did not break at zero stamina")
	assert(ss.stance == Stance.NONE, "stance survived the break")
	assert(cs.state == CombatState.STAGGER, "a broken stance did not stagger")

	for i in int(ss.stance_break_time / DT) + 4:
		cs.advance(DT, false, false)
	assert(cs.state == CombatState.IDLE, "stance-break stagger never ended")

	# Not blocking: full damage, no stamina cost.
	cs = _fresh()
	ss = Stance.new()
	assert(ss.resolve_hit(cs, 40.0) == "hit")
	assert(is_equal_approx(cs.health, 60.0), "an unblocked hit was reduced")
	assert(is_equal_approx(cs.stamina, cs.stamina_max), "an unblocked hit cost stamina")

	# i-frames still beat blocking outright.
	cs = _fresh()
	ss = Stance.new()
	ss.enter(Stance.BLOCK)
	cs.advance(DT, false, true)
	while not cs.invulnerable():
		cs.advance(DT, false, false)
	assert(ss.resolve_hit(cs, 100.0) == "dodged", "i-frames lost to block")


# 17. §11-8: parry sits behind one flag that can be flipped for A/B.
func _parry_flag() -> void:
	# Flag OFF: the refund path is unreachable and a hit still costs and chips.
	var cs = _fresh()
	var ss = Stance.new()
	ss.parry_enabled = false
	ss.enter(Stance.BLOCK)
	assert(not ss.try_parry(cs), "parried with the flag off")
	assert(is_equal_approx(cs.stamina, cs.stamina_max), "a disabled parry still cost stamina")
	assert(ss.resolve_hit(cs, 100.0) == "blocked", "flag off should fall through to block")

	# Flag ON: the same flick then the same hit refunds and negates.
	cs = _fresh()
	ss = Stance.new()
	ss.parry_enabled = true
	ss.enter(Stance.BLOCK)
	assert(ss.try_parry(cs), "parry refused with the flag on")
	assert(is_equal_approx(cs.stamina, cs.stamina_max - ss.parry_cost), "the flick did not cost")
	assert(ss.resolve_hit(cs, 100.0) == "parried", "an armed parry did not fire")
	assert(is_equal_approx(cs.stamina, cs.stamina_max), "a successful parry was not refunded")
	assert(is_equal_approx(cs.health, cs.health_max), "a parried hit dealt damage")

	# A flick that never gets hit stays charged - that IS the failure case.
	cs = _fresh()
	ss = Stance.new()
	ss.parry_enabled = true
	ss.enter(Stance.BLOCK)
	ss.try_parry(cs)
	for i in int((ss.parry_window + 0.1) / DT):
		ss.tick(DT, CombatState.IDLE)
	assert(not ss.parry_armed(), "the parry window never expired")
	assert(ss.resolve_hit(cs, 100.0) == "blocked", "a lapsed parry still negated the hit")
	assert(cs.stamina < cs.stamina_max - ss.parry_cost, "a failed parry was refunded anyway")
