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
