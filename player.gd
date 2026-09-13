extends CharacterBody3D
# Stage 1 verbs: move, one committed attack, one dodge, stamina gating both.
# The state machine lives in combat_state.gd; this file only decides *where*
# things move. Every number here is @export and pushed live into CombatState,
# so you can tune it from the remote inspector while playing.

const CombatState := preload("res://combat_state.gd")
const CameraRelative := preload("res://camera_relative.gd")

@export_group("Move")
@export var move_speed := 5.0
@export var ground_accel := 45.0
@export var turn_speed := 12.0
@export var gravity := 24.0

@export_group("Attack")
@export var windup_time := 0.22
@export var active_time := 0.10
@export var recovery_time := 0.35
@export var attack_cost := 25.0
@export var attack_lunge := 0.6  # metres travelled during the active window

@export_group("Dodge")
@export var dodge_time := 0.40
@export var dodge_distance := 3.5
@export var iframe_start := 0.05
@export var iframe_end := 0.28
@export var dodge_cost := 30.0

@export_group("Stamina")
@export var stamina_max := 100.0
@export var regen_rate := 45.0
@export var regen_delay := 0.55

const TUNABLES := [
	"windup_time",
	"active_time",
	"recovery_time",
	"attack_cost",
	"dodge_time",
	"iframe_start",
	"iframe_end",
	"dodge_cost",
	"stamina_max",
	"regen_rate",
	"regen_delay",
]

var cs := CombatState.new()
var cam_rel := CameraRelative.new()
var _dodge_dir := Vector3.FORWARD

@onready var attack_box: MeshInstance3D = $AttackBox


func _ready() -> void:
	cs.stamina = stamina_max


func _physics_process(delta: float) -> void:
	# Re-push tunables every frame so remote-inspector edits land live while
	# you're playing. This is the single most useful thing in the file.
	for k in TUNABLES:
		cs.set(k, get(k))

	var cam := get_viewport().get_camera_3d()
	var wish := Vector3.ZERO
	if cam:
		wish = cam_rel.to_world(
			Input.get_vector("move_left", "move_right", "move_forward", "move_back"),
			cam.global_transform.basis
		)

	var ev := cs.advance(
		delta, Input.is_action_just_pressed("attack"), Input.is_action_just_pressed("dodge")
	)
	if ev == "dodge":
		_dodge_dir = wish if wish != Vector3.ZERO else -global_transform.basis.z
	if ev != "":
		Metrics.log_event(ev, {"stamina": snappedf(cs.stamina, 0.1)})

	attack_box.visible = cs.state == CombatState.ACTIVE

	# WINDUP and RECOVERY fall through to ZERO, so you decelerate into the swing
	# and coast out of it. That slide is what reads as weight.
	var target := Vector3.ZERO
	match cs.state:
		CombatState.DODGE:
			target = _dodge_dir * (dodge_distance / maxf(dodge_time, 0.01))
		CombatState.ACTIVE:
			target = -global_transform.basis.z * (attack_lunge / maxf(active_time, 0.01))
		CombatState.IDLE:
			target = wish * move_speed

	if cs.state == CombatState.DODGE or cs.state == CombatState.ACTIVE:
		velocity.x = target.x  # burst, no ramp
		velocity.z = target.z
	else:
		velocity.x = move_toward(velocity.x, target.x, ground_accel * delta)
		velocity.z = move_toward(velocity.z, target.z, ground_accel * delta)
	velocity.y -= gravity * delta

	if cs.state == CombatState.IDLE and wish != Vector3.ZERO:
		rotation.y = rotate_toward(rotation.y, atan2(-wish.x, -wish.z), turn_speed * delta)

	move_and_slide()
