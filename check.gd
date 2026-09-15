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
	_rotation_rates()
	_link_count()
	_chain_path()
	_bow_drag()
	_no_regen_while_stanced()
	_block()
	_parry_flag()
	_held_charge()
	_hold_active()
	_arrow_path()
	_fan_dirs()
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
	# can. Without it the second flick is eaten.
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


# 17. §11-8: parry sits behind one flag, off until block feels right.
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
		ss.tick(DT)
	assert(not ss.parry_armed(), "the parry window never expired")
	assert(ss.resolve_hit(cs, 100.0) == "blocked", "a lapsed parry still negated the hit")
	assert(cs.stamina < cs.stamina_max - ss.parry_cost, "a failed parry was refunded anyway")


func _advance_until(cs, state: int) -> void:
	for i in 600:
		if cs.state == state:
			return
		cs.advance(DT, false, false)
	assert(false, "never reached state %d" % state)


# 20. Hybrid sword: a held wind-up pauses at the top and charges; releasing sends
#     it. A click is just a wind-up that was never held, so it adds no latency.
func _held_charge() -> void:
	# Not held: releases at windup_time exactly as before.
	var cs = _fresh()
	assert(cs.try_attack(15.0))
	_advance_until(cs, CombatState.ACTIVE)

	# Held: stays in WINDUP past windup_time, and says so.
	cs = _fresh()
	cs.hold = true
	assert(cs.try_attack(15.0))
	for i in int(cs.windup_time / DT) + 30:
		cs.advance(DT, false, false)
	assert(cs.state == CombatState.WINDUP, "a held wind-up released on its own")
	assert(cs.charging(), "held past windup_time but not charging")
	assert(cs.charge_seconds() > 0.4, "charge time did not accumulate: %f" % cs.charge_seconds())

	# Letting go sends it on the very next step.
	cs.hold = false
	cs.advance(DT, false, false)
	assert(cs.state == CombatState.ACTIVE, "releasing a charge did not strike")

	# Held but still inside the wind-up: not charging yet, and dodge is ignored.
	cs = _fresh()
	cs.hold = true
	cs.try_attack(15.0)
	cs.advance(DT, false, false)
	assert(not cs.charging(), "charging before the wind-up finished")
	assert(cs.advance(DT, false, true) == "ignored", "dodged out of the committed wind-up")
	assert(cs.state == CombatState.WINDUP)

	# Once charging, a dodge gets you out.
	while not cs.charging():
		cs.advance(DT, false, false)
	assert(cs.advance(DT, false, true) == "dodge", "could not roll out of a held charge")
	assert(cs.state == CombatState.DODGE)

	# A charge can be knocked out of; a plain wind-up still cannot.
	cs = _fresh()
	cs.hold = true
	cs.try_attack(15.0)
	cs.stagger(0.3)
	assert(cs.state == CombatState.WINDUP, "staggered out of a committed wind-up")
	while not cs.charging():
		cs.advance(DT, false, false)
	cs.stagger(0.3)
	assert(cs.state == CombatState.STAGGER, "a held charge was not interruptible")


# 21. Link count: one link free, one more per link_time held, capped by the lowest
#     of weapon, skill and what stamina can pay for.
func _link_count() -> void:
	assert(Stance.link_count(0.0, 0.35, 5, 5, 100.0, 12.0) == 1, "zero charge was not one link")
	assert(Stance.link_count(0.34, 0.35, 5, 5, 100.0, 12.0) == 1, "grew a link early")
	assert(Stance.link_count(0.36, 0.35, 5, 5, 100.0, 12.0) == 2, "did not grow at link_time")
	assert(Stance.link_count(0.71, 0.35, 5, 5, 100.0, 12.0) == 3)
	assert(Stance.link_count(9.0, 0.35, 4, 5, 100.0, 12.0) == 4, "weapon cap did not bind")
	assert(Stance.link_count(9.0, 0.35, 5, 3, 100.0, 12.0) == 3, "skill cap did not bind")
	assert(Stance.link_count(9.0, 0.35, 5, 5, 25.0, 12.0) == 2, "stamina cap did not bind")
	# Broke: still one link, since the first was already paid when the swing began.
	assert(Stance.link_count(9.0, 0.35, 5, 5, 0.0, 12.0) == 1, "no stamina gave zero links")


# 22. Chain path: first target nearest the CURSOR within first_range of the player,
#     then nearest-next within hop_range, no revisits, stops when nothing is near.
func _chain_path() -> void:
	var o := Vector3.ZERO
	var at := [Vector3(2, 0, 0), Vector3(-2, 0, 0), Vector3(-4, 0, 0), Vector3(-20, 0, 0)]
	# Cursor to the left: picks -2 although +2 is just as close to the player.
	var p: Array = Stance.chain_path(Vector3(-3, 0, 0), o, at, 5, 6.0, 4.5)
	assert(p[0] == 1, "first target was not the one nearest the cursor: %s" % [p])
	assert(p == [1, 2], "hop order wrong, revisited, or hopped 6m past hop_range: %s" % [p])
	# Link count is respected.
	assert(Stance.chain_path(Vector3(-3, 0, 0), o, at, 2, 6.0, 4.5) == [1, 2], "ignored the link count")
	# First range: a far enemy under the cursor is not a valid opener.
	p = Stance.chain_path(Vector3(-20, 0, 0), o, at, 1, 6.0, 4.5)
	assert(p == [2], "opener ignored first_range: %s" % [p])
	# Nothing in first range: empty.
	assert(Stance.chain_path(o, o, [Vector3(10, 0, 0)], 3, 6.0, 4.5).is_empty(), "picked an out-of-range opener")
	# Stops when the next hop is too far.
	assert(Stance.chain_path(o, o, [Vector3(1, 0, 0), Vector3(9, 0, 0)], 3, 6.0, 4.5) == [0], "hopped past hop_range")
	# Height is ignored.
	assert(Stance.chain_path(o, o, [Vector3(1, 5, 0)], 1, 2.0, 4.5) == [0], "height broke the range check")


# 23. A held ACTIVE stays open for the whole chain, then ends normally.
func _hold_active() -> void:
	var cs = _fresh()
	assert(cs.try_attack(10.0))
	_advance_until(cs, CombatState.ACTIVE)
	cs.hold_active = true
	for i in 60:
		cs.advance(DT, false, false)
	assert(cs.state == CombatState.ACTIVE, "ACTIVE ended while held")
	cs.hold_active = false
	cs.advance(DT, false, false)
	assert(cs.state == CombatState.RECOVERY, "releasing hold_active did not end ACTIVE")

	# Charging pauses regen, so waiting at the top cannot refill the link cap.
	cs = _fresh()
	cs.hold = true
	cs.try_attack(10.0)
	cs.stamina = 40.0
	for i in 120:
		cs.advance(DT, false, false)
	assert(cs.charging() and cs.stamina == 40.0, "stamina regenerated while charging")


# 24. Arrow pierce: nearest first, every visited enemy is hit, and it passes one
#     only while the budget covers that enemy's toughness.
func _arrow_path() -> void:
	var o := Vector3.ZERO
	var fwd := Vector3(0, 0, -1)
	var line := [Vector3(0, 0, -6), Vector3(0, 0, -2), Vector3(0, 0, -4), Vector3(0, 0, -8)]
	var ones := [1.0, 1.0, 1.0, 1.0]
	assert(Stance.arrow_path(o, fwd, line, ones, 14.0, 8.0, 0.0) == [1], "budget 0 did not stop in the first")
	var p: Array = Stance.arrow_path(o, fwd, line, ones, 14.0, 8.0, 2.0)
	assert(p == [1, 2, 0], "budget 2 should pass two and stop in the third, nearest first: %s" % [p])
	assert(Stance.arrow_path(o, fwd, line, ones, 14.0, 8.0, 9.0) == [1, 2, 0, 3], "a big budget missed one")
	# A tough enemy stops the arrow inside it.
	assert(Stance.arrow_path(o, fwd, line, [1.0, 3.0, 1.0, 1.0], 14.0, 8.0, 2.0) == [1], "passed a toughness-3 enemy on budget 2")
	# Spent, not checked: 1.5 covers the first but not the second.
	assert(Stance.arrow_path(o, fwd, line, ones, 14.0, 8.0, 1.5) == [1, 2], "the budget was not spent")
	# Outside the cone or past the range is never hit.
	var aside := [Vector3(3, 0, -3), Vector3(0, 0, -20), Vector3(0, 0, -3)]
	assert(Stance.arrow_path(o, fwd, aside, [1.0, 1.0, 1.0], 14.0, 8.0, 9.0) == [2], "hit outside the cone or range")


# 25. A volley fans out evenly around the aim.
func _fan_dirs() -> void:
	var fwd := Vector3(0, 0, -1)
	var one: Array = Stance.fan_dirs(fwd, 1, 8.0)
	assert(one.size() == 1 and one[0].is_equal_approx(fwd), "a single arrow was not straight")
	var three: Array = Stance.fan_dirs(fwd, 3, 8.0)
	assert(three[1].is_equal_approx(fwd), "the middle arrow was not on the aim")
	assert(is_equal_approx(rad_to_deg(fwd.signed_angle_to(three[0], Vector3.UP)), -8.0), "left arrow not -8")
	assert(is_equal_approx(rad_to_deg(fwd.signed_angle_to(three[2], Vector3.UP)), 8.0), "right arrow not +8")
	var two: Array = Stance.fan_dirs(fwd, 2, 8.0)
	assert(is_equal_approx(fwd.signed_angle_to(two[0], Vector3.UP), -fwd.signed_angle_to(two[1], Vector3.UP)), "even fan not symmetric")
