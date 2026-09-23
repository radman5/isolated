extends RefCounted
# Attack/dodge state machine. Stamina here only paces the enemy's swings: the
# player has none (docs/adr/0001) and pays with cooldowns instead. Pure logic: no nodes, no physics, no
# Input, no camera. Everything stage 1 is actually testing lives in this file,
# which is also what makes check.gd able to run it headlessly.
#
# No class_name on purpose: class_name resolution reads
# .godot/global_script_class_cache.cfg, which only the editor regenerates, so a
# headless --script run against a stale cache dies on an unresolved identifier.
# Consumers preload() this instead.

enum { IDLE, WINDUP, ACTIVE, RECOVERY, DODGE, STAGGER }
const NAMES := ["idle", "windup", "active", "recovery", "dodge", "stagger"]

# Tunables. player.gd overwrites these every frame from its @exports so
# remote-inspector edits land live.
var windup_time := 0.22
var active_time := 0.10
var recovery_time := 0.35
var attack_cost := 25.0
var dodge_time := 0.40
var iframe_start := 0.05
var iframe_end := 0.28
## Seconds from the start of one dodge to the next.
var dodge_cooldown := 0.65
var stamina_max := 100.0
var regen_rate := 45.0
var regen_delay := 0.55

var health_max := 100.0

var state := IDLE
var t := 0.0  # seconds inside the current state
var stamina := 100.0
var regen_timer := 0.0
var dodge_ready_in := 0.0
var health := 100.0
var stagger_time := 0.0
# Player only. While true, a finished wind-up does not release: the swing is held
# at the top and charges. Letting go sends it. Defaults off, so the enemy is
# untouched.
var hold := false
# Player only. While true, ACTIVE does not end: a charged chain strike keeps its
# one active window open until every link has landed.
var hold_active := false


# A landed hit freezes the target - but NOT while it is committed to a swing.
#
# That exception is the whole mechanic. Without it, a hit cancels the enemy's
# 0.6s wind-up outright, the player swings faster than that, and the enemy never
# completes an attack: measured at 3.34s of mashing for ZERO damage taken, which
# made trading strictly better than playing well rather than worse.
#
# With it, the rule reads the same for both sides as the player's own committed
# attack: once the swing starts, nothing outside you stops it. So hitting into a
# telegraph trades - you both land - while hitting during RECOVERY extends the
# punish window. Stagger becomes a reward for correct timing instead of a
# universal interrupt.
#
# Never shortens an existing stagger and never stacks, so a chain cannot lock an
# enemy out permanently.
func stagger(secs: float) -> void:
	# A held charge is a voluntary stance, not a committed swing, so it can be
	# knocked out of like a drawn bow.
	if dead() or (state == WINDUP and not charging()) or state == ACTIVE:
		return
	if state == STAGGER and stagger_time - t > secs:
		return
	stagger_time = secs
	_enter(STAGGER)


# True once a held wind-up has passed its normal release point.
func charging() -> bool:
	return state == WINDUP and hold and t >= windup_time


func charge_seconds() -> float:
	return maxf(0.0, t - windup_time) if state == WINDUP else 0.0


func busy() -> bool:
	return state != IDLE


func dead() -> bool:
	return health <= 0.0


# Returns true if the hit landed. False means i-frames ate it, which is the only
# payoff i-frames have and is what "dodge success" means in the §5 metrics.
#
# Health deliberately does not regenerate: it does not come back, ever. That is the attrition hypothesis (§2) and the whole reason
# stage 3 exists, so the absence is load-bearing rather than an oversight.
func take_damage(amount: float) -> bool:
	if dead() or invulnerable():
		return false
	health = maxf(0.0, health - amount)
	return true


# Cone check: is `target` in front of `from` within `reach`? Used for both the
# player's swing and the enemy's, so a hit means the same thing for both.
# ponytail: no Area3D, no collision layers, no signals. Grey capsules do not
# need physics to answer "did that connect", and this stays unit-testable.
static func in_arc(
	from: Vector3, forward: Vector3, target: Vector3, reach: float, half_angle_deg: float
) -> bool:
	var to_target := target - from
	to_target.y = 0.0
	var dist := to_target.length()
	if dist > reach or dist < 0.001:
		return false
	return rad_to_deg(forward.normalized().angle_to(to_target / dist)) <= half_angle_deg


func invulnerable() -> bool:
	return state == DODGE and t >= iframe_start and t < iframe_end


func dodge_progress() -> float:
	return t / dodge_time if state == DODGE else 0.0


func state_name() -> String:
	return NAMES[state]


func try_attack(cost: float) -> bool:
	return state == IDLE and _try(WINDUP, cost, "attack") == "attack"


# Returns one event string, "" for nothing:
# "attack" "dodge" "attack_refused" "dodge_refused" "ignored"
func advance(delta: float, attack_pressed: bool, dodge_pressed: bool) -> String:
	t += delta
	dodge_ready_in = maxf(0.0, dodge_ready_in - delta)

	# Timed transitions run before input, so the frame recovery ends the state
	# is already IDLE and a press that same frame starts the next swing. Without
	# this there is a dropped frame between attacks and it reads as input lag.
	match state:
		WINDUP:
			if t >= windup_time and not hold:
				_enter(ACTIVE)
		ACTIVE:
			if t >= active_time and not hold_active:
				_enter(RECOVERY)
		RECOVERY:
			if t >= recovery_time:
				_enter(IDLE)
		DODGE:
			if t >= dodge_time:
				_enter(IDLE)
		STAGGER:
			if t >= stagger_time:
				_enter(IDLE)

	regen_timer = maxf(0.0, regen_timer - delta)
	if regen_timer == 0.0:
		stamina = minf(stamina_max, stamina + regen_rate * delta)

	# Charging is a voluntary hold, so you can roll out of it the way you can
	# let go of a drawn bow. The wind-up before the hold point stays committed.
	if dodge_pressed and charging():
		return _dodge()

	# Input is read only when IDLE. Non-cancellability is structural, not a
	# flag: there is no code path that can interrupt a swing or a roll.
	if state != IDLE:
		return "ignored" if (attack_pressed or dodge_pressed) else ""
	if dodge_pressed:
		return _dodge()
	if attack_pressed:
		return _try(WINDUP, attack_cost, "attack")
	return ""


func _dodge() -> String:
	if dodge_ready_in > 0.0:
		return "dodge_refused"
	dodge_ready_in = dodge_cooldown
	_enter(DODGE)
	return "dodge"


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
