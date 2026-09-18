extends CharacterBody3D
# Stage 2: one enemy type. Test plan §4 asks for exactly three things: a readable
# telegraph, a committed attack, and a punish window afterwards.
#
# It runs the same CombatState as the player, so "committed" means the same
# thing for both: once the swing starts nothing can interrupt it. The only
# difference is that attack_pressed comes from the AI below instead of Input.
#
# Stamina is what paces its aggression. It is not a resource the enemy manages,
# it is just a cooldown with a name we already had.
#
# Spawned by fight.gd from enemy.tscn, any number of them, all in the "enemies"
# group. Nothing should look an enemy up by node name.

const CombatState := preload("res://combat_state.gd")
const Hazard := preload("res://traps/hazard.gd")

@export_group("Move")
@export var move_speed := 3.0
@export var accel := 20.0
@export var turn_speed := 7.0
@export var gravity := 24.0

## Ignores the player until they come this close, then stays awake. Keeps the
## stations in the environment demo from all waking at once.
@export var aggro_range := 9.0

@export_group("Attack")
@export var windup_time := 0.60  # the telegraph. If you cannot react, raise it.
@export var active_time := 0.12
@export var recovery_time := 0.60  # the punish window. Shorten to make it harder.
@export var attack_range := 2.4
# Where it prefers to stand. Deliberately just OUTSIDE the player's 2.0 reach,
# so you have to step in to punish rather than swinging from where you already
# are. If this drops below player.attack_reach the punish window becomes free
# and the whole spacing game disappears.
@export var standoff := 2.15
@export var attack_arc := 55.0
@export var damage := 25.0
@export var attack_cost := 30.0
@export var parry_stagger := 1.2  # §6: a successful parry staggers the enemy

@export_group("Knockback")
@export var knockback := 1.0  # metres a clean hit shoves the player
@export var block_knock_mult := 0.4
@export var break_knock_mult := 1.5
## How fast a shove bleeds off. The shove covers its distance either way; this
## only changes whether it is a snap or a slide.
@export var knock_friction := 12.0
## How much of the player's knockback still moves this enemy while it is
## committed to a swing. Zero keeps the trade rule honest: shoving a committed
## enemy out of range would cancel its attack by geometry, which is stunlock.
@export var armor_knock_mult := 0.0

@export_group("Health")
## Pierce budget an arrow spends to pass through this enemy.
@export var toughness := 1.0
## Armour. Multiplies all damage, stagger and knockback this enemy receives.
@export var damage_taken_mult := 1.0
@export var stagger_taken_mult := 1.0
@export var knock_taken_mult := 1.0
@export var health_max := 100.0
@export var regen_rate := 22.0  # stamina regen: how soon it can swing again
@export var regen_delay := 0.30

const TUNABLES := [
	"windup_time",
	"active_time",
	"recovery_time",
	"attack_cost",
	"health_max",
	"regen_rate",
	"regen_delay",
]

var cs := CombatState.new()
var _awake := false
var _swing_used := false
var _was_active := false
var _knock := Vector3.ZERO

@onready var player: Node = get_node_or_null("../Player")


func _ready() -> void:
	add_to_group("enemies")
	cs.health_max = health_max
	cs.health = health_max
	cs.stamina = 100.0


# `knock` is a displacement in metres, not a velocity. The hit interrupts
# whatever the enemy was doing unless it is committed to a swing, and then it
# neither flinches nor moves: see CombatState.stagger for why.
# `ignore_armor` is for the player's chain strike, which clears a path through
# enemies whether they are mid-swing or not.
func take_hit(damage_: float, stagger_secs: float, knock := Vector3.ZERO, ignore_armor := false) -> void:
	if cs.dead():
		return
	damage_ *= damage_taken_mult
	stagger_secs *= stagger_taken_mult
	knock *= knock_taken_mult
	cs.take_damage(damage_)
	if cs.dead():
		apply_knock(knock)  # corpses still get shoved; it reads as the finishing blow
		return
	if stagger_secs > 0.0:
		cs.stagger(stagger_secs)
	if cs.state == CombatState.STAGGER:
		apply_knock(knock)
		Metrics.log_event("enemy_staggered", {"id": name, "secs": snappedf(stagger_secs, 0.01)})
	else:
		apply_knock(knock if ignore_armor else knock * armor_knock_mult)


# Killed by the room. Dead on the spot, whatever the armour says.
func env_kill(how: String) -> void:
	if cs.dead():
		return
	cs.health = 0.0
	Metrics.log_event("enemy_killed_by_env", {"id": name, "how": how})
	if how == "fall":
		_drop(self)


# Fire and the like: past armour, straight to health.
func env_damage(amount: float) -> void:
	if cs.dead():
		return
	cs.health = maxf(0.0, cs.health - amount)
	if cs.dead():
		Metrics.log_event("enemy_killed_by_env", {"id": name, "how": "burn"})


# Shared with player.gd: no collision, no more thinking, sink out of sight.
static func _drop(body: CharacterBody3D) -> void:
	body.collision_layer = 0
	body.collision_mask = 0
	body.set_physics_process(false)
	var tw := body.create_tween()
	tw.tween_property(body, "position:y", body.position.y - 6.0, 0.7).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(body.hide)


# Decays exponentially, so a starting speed of distance * friction covers
# `distance` metres whatever the friction is.
func apply_knock(v: Vector3) -> void:
	v.y = 0.0
	if v.length() > 0.001:
		_knock = v * knock_friction


func _physics_process(delta: float) -> void:
	for k in TUNABLES:
		cs.set(k, get(k))

	if cs.dead():
		# ponytail: a corpse stops blocking the moment it dies, whatever killed it.
		# The mask stays, so it still rests on the floor instead of sinking.
		collision_layer = 0
		_slide(delta, Vector3.ZERO)
		return

	var to_player := Vector3.ZERO
	var dist := INF
	if player and not player.cs.dead():
		to_player = player.global_position - global_position
		to_player.y = 0.0
		dist = to_player.length()
	if not _awake:
		if dist > aggro_range:
			_slide(delta, Vector3.ZERO)
			return
		_awake = true

	# Attack only from IDLE, only in range, only roughly facing. Everything else
	# about the swing is CombatState's problem.
	var want_attack := false
	if dist <= attack_range * 0.95 and cs.state == CombatState.IDLE:
		want_attack = CombatState.in_arc(
			global_position, -global_transform.basis.z, player.global_position, attack_range, 40.0
		)

	var ev := cs.advance(delta, want_attack, false)
	if ev == "attack":
		Metrics.log_event("enemy_attack", {"id": name, "dist": snappedf(dist, 0.1)})

	# One hit per swing, not one per frame.
	var active_now := cs.state == CombatState.ACTIVE
	if active_now and not _was_active:
		_swing_used = false
	_was_active = active_now
	if active_now and not _swing_used and player and not player.cs.dead():
		if CombatState.in_arc(
			global_position, -global_transform.basis.z, player.global_position, attack_range, attack_arc
		):
			_swing_used = true
			_land_hit()

	# Close the distance only while idle. A committed swing does not chase, and
	# facing is locked once it starts; that is what makes sidestepping work and
	# what turns recovery into a real punish window.
	var target := Vector3.ZERO
	if cs.state == CombatState.IDLE and dist < INF and dist > standoff:
		# Walk around live hazards and stop at edges. Being shoved off one is
		# still fair game: only its own walking is careful.
		var go := Hazard.steer(to_player, global_position, 1.2, _step_blocked)
		target = go * move_speed * Hazard.speed_mult(get_tree().get_nodes_in_group("hazards"), global_position)
	if cs.state == CombatState.IDLE and dist < INF and dist > 0.01:
		var want := atan2(-to_player.x, -to_player.z)
		rotation.y = rotate_toward(rotation.y, want, turn_speed * delta)
	_slide(delta, target)


func _land_hit() -> void:
	# Blocking must intercept before take_damage, so the player owns the damage
	# path. The "hit"/"dodged" event names are kept verbatim: the README's jq
	# lines depend on them.
	var r: String = player.receive_hit(damage)
	var data := {"id": name, "player_hp": snappedf(player.cs.health, 0.1)}
	var push: Vector3 = player.global_position - global_position
	push.y = 0.0
	push = push.normalized()
	match r:
		"hit":
			Metrics.log_event("player_hit", data)
			player.apply_knock(push * knockback)
		"dodged":
			Metrics.log_event("dodge_success", data)
		"blocked":
			Metrics.log_event("hit_blocked", data)
			player.apply_knock(push * knockback * block_knock_mult)
		"broken":
			Metrics.log_event("stance_broken", data)
			player.apply_knock(push * knockback * break_knock_mult)
		"parried":
			Metrics.log_event("parry_success", data)
			cs.stagger(parry_stagger)


# A step is a bad idea if it lands in something live and harmful, or off a ledge.
func _step_blocked(p: Vector3) -> bool:
	for z in get_tree().get_nodes_in_group("hazards"):
		if z.active and z.kind_id() != Hazard.SLOW and Hazard.inside(z.shape(), p):
			return true
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.6, 0), p + Vector3(0, -1.6, 0))
	q.exclude = [get_rid()]
	return space.intersect_ray(q).is_empty()


# While a shove is live it owns horizontal velocity outright; blending it with
# steering would let the AI walk straight back through its own knockback.
func _slide(delta: float, target: Vector3) -> void:
	if _knock.length() > 0.2:
		velocity.x = _knock.x
		velocity.z = _knock.z
		_knock *= exp(-knock_friction * delta)
	else:
		_knock = Vector3.ZERO
		velocity.x = move_toward(velocity.x, target.x, accel * delta)
		velocity.z = move_toward(velocity.z, target.z, accel * delta)
	velocity.y -= gravity * delta
	move_and_slide()
	if global_position.y < -4.0:
		env_kill("fall")
