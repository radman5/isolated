extends RefCounted
# Stamina + attack/dodge state machine. Pure logic: no nodes, no physics, no
# Input, no camera. Everything stage 1 is actually testing lives in this file,
# which is also what makes check.gd able to run it headlessly.
#
# No class_name on purpose: class_name resolution reads
# .godot/global_script_class_cache.cfg, which only the editor regenerates, so a
# headless --script run against a stale cache dies on an unresolved identifier.
# Consumers preload() this instead.

enum { IDLE, WINDUP, ACTIVE, RECOVERY, DODGE }
const NAMES := ["idle", "windup", "active", "recovery", "dodge"]

# Tunables. player.gd overwrites these every frame from its @exports so
# remote-inspector edits land live.
var windup_time := 0.22
var active_time := 0.10
var recovery_time := 0.35
var attack_cost := 25.0
var dodge_time := 0.40
var iframe_start := 0.05
var iframe_end := 0.28
var dodge_cost := 30.0
var stamina_max := 100.0
var regen_rate := 45.0
var regen_delay := 0.55

var state := IDLE
var t := 0.0  # seconds inside the current state
var stamina := 100.0
var regen_timer := 0.0


func busy() -> bool:
	return state != IDLE


func invulnerable() -> bool:
	return state == DODGE and t >= iframe_start and t < iframe_end


func dodge_progress() -> float:
	return t / dodge_time if state == DODGE else 0.0


func state_name() -> String:
	return NAMES[state]


# Returns one event string, "" for nothing:
# "attack" "dodge" "attack_refused" "dodge_refused" "ignored"
func advance(delta: float, attack_pressed: bool, dodge_pressed: bool) -> String:
	t += delta

	# Timed transitions run before input, so the frame recovery ends the state
	# is already IDLE and a press that same frame starts the next swing. Without
	# this there is a dropped frame between attacks and it reads as input lag.
	match state:
		WINDUP:
			if t >= windup_time:
				_enter(ACTIVE)
		ACTIVE:
			if t >= active_time:
				_enter(RECOVERY)
		RECOVERY:
			if t >= recovery_time:
				_enter(IDLE)
		DODGE:
			if t >= dodge_time:
				_enter(IDLE)

	regen_timer = maxf(0.0, regen_timer - delta)
	if regen_timer == 0.0:
		stamina = minf(stamina_max, stamina + regen_rate * delta)

	# Input is read only when IDLE. Non-cancellability is structural, not a
	# flag: there is no code path that can interrupt a swing or a roll.
	if state != IDLE:
		return "ignored" if (attack_pressed or dodge_pressed) else ""
	if dodge_pressed:
		return _try(DODGE, dodge_cost, "dodge")
	if attack_pressed:
		return _try(WINDUP, attack_cost, "attack")
	return ""


func _try(next: int, cost: float, ev: String) -> String:
	if stamina < cost:
		return ev + "_refused"
	stamina -= cost
	regen_timer = regen_delay
	_enter(next)
	return ev


func _enter(s: int) -> void:
	# Drops the overshoot, so each state lasts ceil(duration / dt) frames.
	# Deterministic and testable; the sub-17ms error does not matter here.
	state = s
	t = 0.0
