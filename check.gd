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
