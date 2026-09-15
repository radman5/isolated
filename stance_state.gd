extends RefCounted
# The second state axis. combat_state.gd answers "what is my body committed to";
# this answers "what is my weapon hand doing". Two axes rather than one flat
# enum because the core loop of §4 - hold, flick, swing, STILL HOLDING, chain -
# is a stance persisting across a committed swing, which one enum cannot say.
#
# Player only. The enemy never instantiates this, which is why the six stance
# states §9 asks for do not belong in the shared class.

const CombatState := preload("res://combat_state.gd")

enum { NONE, SWORD, BOW, BLOCK }
const NAMES := ["none", "sword", "bow", "block"]

# Tunables, mirrored as @export on player.gd. Values from spec §8/§10, except
# dodge cost, regen rate and regen delay, which keep the Stage 1 numbers that
# had actually been played.
var sword_drain := 12.0
var bow_drain := 8.0
var block_drain := 5.0
var charge_time := 1.0
var charged_cost := 15.0
var chain_cost := 10.0
var chain_window := 0.45
var chain_cap := 3
var cone_deg := 60.0
var bow_cost := 10.0
var block_hit_cost := 20.0
var block_chip := 0.25
var parry_cost := 15.0
var parry_window := 0.20
var parry_enabled := false  # §6: block must pass its gate before this flips
var stance_break_time := 1.0
var buffer_window := 0.4

var stance := NONE
var chain := 0
var side := -1  # alternates per swing; §4 wants rhythm with no combo system
var chain_timer := 0.0
var parry_until := -1.0
var clock := 0.0  # own clock, so parry timing is testable without Time
# Tekken-style input buffer: a flick made while a swing is still coming out is
# kept, and fires on the first frame it legally can. Only the latest flick is
# kept, and it expires after buffer_window.
var buffered := Vector2.ZERO
var buffer_age := 0.0


func name_of() -> String:
	return NAMES[stance]


func enter(s: int) -> void:
	stance = s
	chain = 0
	chain_timer = 0.0
	buffered = Vector2.ZERO


func exit() -> void:
	stance = NONE
	chain = 0
	chain_timer = 0.0
	parry_until = -1.0
	buffered = Vector2.ZERO


# Non-zero drain IS the predicate "a stance is held", so §8's "no regeneration
# while any stance is held" needs no second flag and cannot drift out of sync.
func drain() -> float:
	match stance:
		SWORD:
			return sword_drain
		BOW:
			return bow_drain
		BLOCK:
			return block_drain
	return 0.0


# ponytail: v2 hook (§4). The cap and the reset are two separate conditions on
# purpose - a weapon swap would set chain = 0 without touching chain_timer, so
# the chain could be extended without the counter resetting it. Not built.
func can_chain() -> bool:
	return chain < chain_cap and chain_timer <= chain_window


func buffer_flick(v: Vector2) -> void:
	buffered = v
	buffer_age = 0.0


func has_buffer() -> bool:
	return buffered != Vector2.ZERO


func take_buffer() -> Vector2:
	var v := buffered
	buffered = Vector2.ZERO
	return v


func tick(delta: float, action_state: int) -> void:
	clock += delta
	if buffered != Vector2.ZERO:
		buffer_age += delta
		if buffer_age > buffer_window:
			buffered = Vector2.ZERO
	if chain > 0:
		# The window is measured from the frame the action FSM returns to IDLE,
		# not from swing start: a full swing is 0.67s, so a 0.45s window
		# measured from the start would be unreachable.
		if action_state == CombatState.IDLE:
			chain_timer += delta
			if chain_timer > chain_window:
				chain = 0
				chain_timer = 0.0
		else:
			chain_timer = 0.0


func swing_cost() -> float:
	return charged_cost if chain == 0 else chain_cost


# Call after the swing is actually paid for and started.
func on_swing() -> void:
	side = -side
	chain += 1
	chain_timer = 0.0


func arm_parry() -> void:
	parry_until = clock + parry_window


func parry_armed() -> bool:
	return parry_enabled and parry_until >= 0.0 and clock <= parry_until


func disarm_parry() -> void:
	parry_until = -1.0


# The damage path for anything that hits the player. Lives here rather than on
# the node so check.gd can drive it: block, parry and stance-break are exactly
# the kind of branchy resource logic that breaks quietly.
# Returns "dodged" | "parried" | "blocked" | "broken" | "hit".
func resolve_hit(cs, amount: float) -> String:
	if cs.invulnerable():
		return "dodged"
	if stance != BLOCK:
		cs.take_damage(amount)
		return "hit"
	if parry_armed():
		# §6: success refunds the flick's cost. Stamina already gates dodging,
		# charging, swinging, chaining and blocking; parry should reward reading
		# the enemy rather than consume a sixth slice of the same bar.
		cs.stamina = minf(cs.stamina_max, cs.stamina + parry_cost)
		disarm_parry()
		return "parried"
	cs.stamina = maxf(0.0, cs.stamina - block_hit_cost)
	cs.take_damage(amount * block_chip)
	if cs.stamina <= 0.0:
		exit()
		cs.stagger(stance_break_time)
		return "broken"
	return "blocked"


# Charged at flick time. A flick that never gets hit simply stays charged - that
# IS the failure case, so there is no failure detector anywhere.
func try_parry(cs) -> bool:
	if not parry_enabled or stance != BLOCK:
		return false
	cs.stamina = maxf(0.0, cs.stamina - parry_cost)
	arm_parry()
	return true


# §3's table, plus one addition: facing is also locked during WINDUP and ACTIVE.
# Not in the spec, but enemy.gd already locks facing once its swing starts, and
# that is what makes sidestepping work. Keeping both sides symmetric is worth a
# branch.
static func rot_rate(stance_: int, action_state: int) -> float:
	if action_state == CombatState.WINDUP or action_state == CombatState.ACTIVE:
		return 0.0
	match stance_:
		BOW:
			return 0.0
		SWORD, BLOCK:
			return 180.0
	return 720.0


static func move_mult(stance_: int) -> float:
	match stance_:
		SWORD:
			return 0.5
		BLOCK:
			return 0.4
		BOW:
			return 0.35
	return 1.0


# Returns a STRIKE YAW clamped to ±half_deg of facing. §4: a flick outside the
# cone clamps to the nearest edge - it never fails silently and never rotates
# the player. "Never rotates the player" is structural, not a promise: this is
# static and holds no node reference, so it has nothing to rotate.
static func clamp_cone(facing_yaw: float, flick_yaw: float, half_deg: float) -> float:
	var d := wrapf(flick_yaw - facing_yaw, -PI, PI)
	var h := deg_to_rad(half_deg)
	return facing_yaw + clampf(d, -h, h)
