extends CharacterBody3D
# Stage 2: one enemy. Test plan §4 asks for exactly three things — a readable
# telegraph, a committed attack, and a punish window afterwards.
#
# It runs the same CombatState as the player, so "committed" means the same
# thing for both: once the swing starts nothing can interrupt it. The only
# difference is that attack_pressed comes from the AI below instead of Input.
#
# Stamina is what paces its aggression. It is not a resource the enemy manages,
# it is just a cooldown with a name we already had.

const CombatState := preload("res://combat_state.gd")

@export_group("Move")
@export var move_speed := 3.0
@export var accel := 20.0
@export var turn_speed := 7.0
@export var gravity := 24.0

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

@export_group("Health")
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
var _swing_used := false
var _was_active := false

@onready var player: Node = get_node_or_null("../Player")
@onready var telegraph: MeshInstance3D = $Telegraph
@onready var attack_box: MeshInstance3D = $AttackBox


func _ready() -> void:
	cs.health_max = health_max
	cs.health = health_max
	cs.stamina = 100.0


func _physics_process(delta: float) -> void:
	for k in TUNABLES:
		cs.set(k, get(k))

	if cs.dead():
		telegraph.visible = false
		attack_box.visible = false
		velocity = Vector3(0, velocity.y - gravity * delta, 0)
		move_and_slide()
		return

	var to_player := Vector3.ZERO
	var dist := INF
	if player and not player.cs.dead():
		to_player = player.global_position - global_position
		to_player.y = 0.0
		dist = to_player.length()

	# Attack only from IDLE, only in range, only roughly facing. Everything else
	# about the swing is CombatState's problem.
	var want_attack := false
	if dist <= attack_range * 0.95 and cs.state == CombatState.IDLE:
		want_attack = CombatState.in_arc(
			global_position, -global_transform.basis.z, player.global_position, attack_range, 40.0
		)

	var ev := cs.advance(delta, want_attack, false)
	if ev == "attack":
		Metrics.log_event("enemy_attack", {"dist": snappedf(dist, 0.1)})

	telegraph.visible = cs.state == CombatState.WINDUP
	attack_box.visible = cs.state == CombatState.ACTIVE

	# One hit per swing, not one per frame.
	var active_now := cs.state == CombatState.ACTIVE
	if active_now and not _was_active:
		_swing_used = false
	_was_active = active_now
	if active_now and not _swing_used and player and not player.cs.dead():
		if CombatState.in_arc(
			global_position,
			-global_transform.basis.z,
			player.global_position,
			attack_range,
			attack_arc
		):
			_swing_used = true
			var landed: bool = player.cs.take_damage(damage)
			Metrics.log_event(
				"player_hit" if landed else "dodge_success",
				{"player_hp": snappedf(player.cs.health, 0.1)}
			)

	# Close the distance only while idle. A committed swing does not chase, and
	# facing is locked once it starts — that is what makes sidestepping work and
	# what turns recovery into a real punish window.
	var target := Vector3.ZERO
	if cs.state == CombatState.IDLE and dist < INF and dist > standoff:
		target = to_player.normalized() * move_speed
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)
	velocity.y -= gravity * delta

	if cs.state == CombatState.IDLE and dist < INF and dist > 0.01:
		var want := atan2(-to_player.x, -to_player.z)
		rotation.y = rotate_toward(rotation.y, want, turn_speed * delta)

	move_and_slide()
