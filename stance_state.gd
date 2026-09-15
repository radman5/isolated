extends RefCounted
# The second state axis. combat_state.gd answers "what is my body committed to";
# this answers "what is my weapon hand doing": bow, block, parry, plus the
# charged chain strike's link count and target path.
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
var bow_cost := 10.0
var block_hit_cost := 20.0
var block_chip := 0.25
var parry_cost := 15.0
var parry_window := 0.20
var parry_enabled := false  # §6: block must pass its gate before this flips
var stance_break_time := 1.0

var stance := NONE
var parry_until := -1.0
var clock := 0.0  # own clock, so parry timing is testable without Time


func name_of() -> String:
	return NAMES[stance]


func enter(s: int) -> void:
	stance = s


func exit() -> void:
	stance = NONE
	parry_until = -1.0


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


func tick(delta: float) -> void:
	clock += delta


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


# How many enemies a charged strike will chain through if released now. One link
# is free at any charge; each link_time held adds another, up to the lowest of
# the weapon's cap, the skill's cap and what stamina can pay for.
static func link_count(
	charge_s: float, link_time: float, weapon_cap: int, skill_cap: int, stamina: float, link_cost: float
) -> int:
	var cap := mini(mini(weapon_cap, skill_cap), int(stamina / maxf(link_cost, 0.001)))
	var grown := 1 + int(charge_s / maxf(link_time, 0.001))
	return clampi(grown, 1, maxi(cap, 1))


# The order a chain visits targets, as indices into `positions`. The first is
# the enemy nearest the cursor inside the wedge in front of the player: within
# first_range and first_arc_deg (half-angle) of `facing`. Each next one is the
# nearest unvisited enemy within hop_range of the last, in any direction. Stops
# early when nothing is in range. Positions, not nodes, so check.gd can drive it.
# first_arc_deg >= 180 is a full circle and ignores facing.
static func chain_path(
	cursor: Vector3, origin: Vector3, positions: Array, links: int, first_range: float, hop_range: float,
	facing := Vector3.FORWARD, first_arc_deg := 180.0
) -> Array[int]:
	var path: Array[int] = []
	var from := cursor
	var limit_from := origin
	var limit := first_range
	while path.size() < links:
		var best := -1
		var best_d := INF
		for i in positions.size():
			if i in path or _flat_dist(positions[i], limit_from) > limit:
				continue
			if path.is_empty() and first_arc_deg < 180.0 \
					and not CombatState.in_arc(origin, facing, positions[i], first_range, first_arc_deg):
				continue
			var d := _flat_dist(positions[i], from)
			if d < best_d:
				best_d = d
				best = i
		if best < 0:
			break
		path.append(best)
		from = positions[best]
		limit_from = from
		limit = hop_range
	return path


# Which enemies one arrow hits, in order, as indices into `positions`. It visits
# everything in its cone nearest first. Each is hit; the arrow carries on past it
# only while `budget` covers that enemy's toughness, spending it, so it stops
# inside the first enemy it cannot afford.
static func arrow_path(
	origin: Vector3, dir: Vector3, positions: Array, toughness: Array,
	length: float, arc_deg: float, budget: float
) -> Array[int]:
	var inside: Array[int] = []
	for i in positions.size():
		if CombatState.in_arc(origin, dir, positions[i], length, arc_deg):
			inside.append(i)
	inside.sort_custom(func(a, b): return _flat_dist(positions[a], origin) < _flat_dist(positions[b], origin))
	var hits: Array[int] = []
	for i in inside:
		hits.append(i)
		if budget < toughness[i]:
			break
		budget -= toughness[i]
	return hits


# Bow draw from time since the arrow was nocked: 0 before (`nocked_for` < 0), then
# min_draw rising linearly to 1 over charge_time.
static func bow_draw(nocked_for: float, charge_time: float, min_draw: float) -> float:
	if nocked_for < 0.0:
		return 0.0
	return lerpf(min_draw, 1.0, clampf(nocked_for / maxf(charge_time, 0.001), 0.0, 1.0))


# `count` directions spread `spread_deg` apart, centred on `dir`.
static func fan_dirs(dir: Vector3, count: int, spread_deg: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in count:
		out.append(dir.rotated(Vector3.UP, deg_to_rad((i - (count - 1) * 0.5) * spread_deg)))
	return out


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
