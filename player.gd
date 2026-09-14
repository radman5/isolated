extends CharacterBody3D
# Stage 2b: gesture input. Hold to commit, mouse motion to express, release to
# resolve. Only the input layer differs from the button build — the swing that a
# flick fires is the same committed WINDUP/ACTIVE/RECOVERY the enemy uses.

const CombatState := preload("res://combat_state.gd")
const CameraRelative := preload("res://camera_relative.gd")
const Gesture := preload("res://gesture.gd")
const Stance := preload("res://stance_state.gd")

# For debug_draw.gd only. Gameplay never listens to this; kinds are
# "swing", "dealt", "taken", "shot".
signal debug_event(kind: String, data: Dictionary)

@export_group("Move")
@export var move_speed := 5.0
@export var ground_accel := 45.0
@export var gravity := 24.0

@export_group("Attack")
@export var windup_time := 0.22
@export var active_time := 0.10
@export var recovery_time := 0.35
## Metres covered by the dash at the start of the active window. It is
## front-loaded, so almost all of it happens in the first frames and then it
## stops dead. That is what makes it read as sudden rather than floaty.
@export var attack_lunge := 1.0
## How long the dash lasts. Shorter is snappier. Capped by active_time.
@export var lunge_time := 0.08
@export var attack_damage := 25.0
@export var attack_reach := 2.0
@export var attack_arc := 55.0
@export var hit_stagger := 0.75
# Chained follow-ups are faster, which is how §4's "fast light follow-ups" is
# delivered without letting a flick cancel a swing in progress.
@export var chain_windup_time := 0.12
@export var chain_recovery_time := 0.20
@export var charge_damage_mult := 1.0
@export var charge_arc_mult := 0.5
@export var charge_stagger_mult := 0.6
## A buffered follow-up may cut the previous swing's recovery once this much of
## it has passed. 0 = as soon as the active frames end (juggle feel). Set it to
## recovery_time or more to switch cancelling off and keep the buffer only.
@export var chain_cancel_from := 0.0
## How long a flick made mid-swing is remembered and fired as soon as it can.
@export var buffer_window := 0.4

@export_group("Knockback")
@export var attack_knockback := 0.6  # metres, light hit
@export var charge_knock_mult := 1.5
## The last swing of a chain sends them flying; the light hits before it keep
## the enemy close enough to follow up.
@export var finisher_knock_mult := 2.5
@export var bow_knockback := 1.0
## How fast a shove bleeds off. The distance is the same either way; this only
## changes whether it is a snap or a slide.
@export var knock_friction := 12.0

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

@export_group("Health")
@export var health_max := 100.0

@export_group("Gesture")
## Needs calibration. Flick five times and read `peak` on the debug overlay.
@export_range(200.0, 6000.0, 10.0, "or_greater", "suffix:px/s") var flick_threshold := 1200.0
@export var flick_refractory := 0.12
## Set false if fast flicks feel dropped: input is accumulated to one motion
## event per rendered frame by default.
@export var raw_mouse_input := false

@export_group("Sword stance")
@export var sword_drain := 12.0
@export var charge_time := 1.0
@export var charged_cost := 15.0
@export var chain_cost := 10.0
@export var chain_window := 0.45
@export var chain_cap := 3
@export var cone_deg := 60.0

@export_group("Bow")
@export var bow_drain := 8.0
@export var bow_cost := 10.0
@export var bow_damage := 30.0
@export var bow_range := 14.0
@export var bow_arc := 8.0
@export var drag_max_px := 300.0

@export_group("Block")
@export var block_drain := 5.0
@export var block_hit_cost := 20.0
@export var block_chip := 0.25
@export var stance_break_time := 1.0
## §6: block must pass its own gate before this is worth turning on.
@export var parry_enabled := false
@export var parry_cost := 15.0
@export var parry_window := 0.20

const CS_TUNABLES := [
	"windup_time", "active_time", "recovery_time", "dodge_time", "iframe_start",
	"iframe_end", "dodge_cost", "stamina_max", "regen_rate", "regen_delay", "health_max",
]
const SS_TUNABLES := [
	"sword_drain", "bow_drain", "block_drain", "charge_time", "charged_cost",
	"chain_cost", "chain_window", "chain_cap", "cone_deg", "bow_cost",
	"block_hit_cost", "block_chip", "parry_cost", "parry_window", "parry_enabled",
	"stance_break_time", "buffer_window",
]

var cs := CombatState.new()
var cam_rel := CameraRelative.new()
var g := Gesture.new()
var ss := Stance.new()

var weapon := Stance.SWORD  # which weapon LMB draws
var cone_flash := 0.0  # latched so a one-frame clamp is actually visible
var last_flick_deg := 0.0
var draw_strength := 0.0

var _dodge_dir := Vector3.FORWARD
var strike_yaw := 0.0  # cone-clamped direction of the current swing
var chain_hits := 0  # hits landed in the current chain
var _swing_level := 0.0
var _hit_this_swing := {}  # instance ids already hit by the swing in progress
var _knock := Vector3.ZERO
var _was_active := false
var _reject_cool := 0.0

@onready var attack_box: MeshInstance3D = $AttackBox
@onready var draw_line: MeshInstance3D = $DrawLine
@onready var fire_vector: MeshInstance3D = $FireVector


func _ready() -> void:
	cs.stamina = stamina_max
	cs.health_max = health_max
	cs.health = health_max
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	# Without an escape you cannot get the cursor back to quit.
	if raw_mouse_input:
		Input.use_accumulated_input = false


# Flicks are handled here rather than in _physics_process so the swing starts on
# the frame the threshold is crossed. CombatState is pure, so firing it outside
# the physics step just sets state/t and the next step advances it.
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseMotion):
		return
	var flick := g.sample(event.relative, event.screen_velocity)
	if flick == Vector2.ZERO:
		return
	last_flick_deg = rad_to_deg(atan2(flick.x, -flick.y))
	Metrics.log_event("flick_detected", {"deg": snappedf(last_flick_deg, 1.0), "mag": snappedf(flick.length(), 1.0)})
	match ss.stance:
		Stance.SWORD:
			if _can_swing_now():
				_swing(flick)
			else:
				# Tekken-style buffer: a flick made while a swing is still coming
				# out is kept and fires on the first frame it legally can, so
				# rhythm replaces frame-perfect timing.
				ss.buffer_flick(flick)
				Metrics.log_event("flick_buffered", {"state": cs.state_name()})
		Stance.BLOCK:
			if ss.try_parry(cs):
				Metrics.log_event("parry_attempted", {"stamina": snappedf(cs.stamina, 0.1)})


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Debug weapon selector, NOT a swap mechanic: gated to a neutral stance, so
	# no mid-chain swap, which is what §13 and the §4 v2 hook actually forbid.
	elif event.is_action_pressed("weapon_sword") and ss.stance == Stance.NONE:
		weapon = Stance.SWORD
	elif event.is_action_pressed("weapon_bow") and ss.stance == Stance.NONE:
		weapon = Stance.BOW


func _physics_process(delta: float) -> void:
	for k in CS_TUNABLES:
		cs.set(k, get(k))
	for k in SS_TUNABLES:
		ss.set(k, get(k))
	g.flick_threshold = flick_threshold
	g.refractory = flick_refractory
	g.drag_max_px = drag_max_px
	# Swings after the first in a chain are quicker.
	if ss.chain > 1:
		cs.windup_time = chain_windup_time
		cs.recovery_time = chain_recovery_time

	g.tick(delta)
	cone_flash = maxf(0.0, cone_flash - delta)
	_reject_cool = maxf(0.0, _reject_cool - delta)
	_stance_edges()
	ss.tick(delta, cs.state)
	draw_strength = g.drag_strength() if ss.stance == Stance.BOW else 0.0

	var cam := get_viewport().get_camera_3d()
	var wish := Vector3.ZERO
	if cam:
		wish = cam_rel.to_world(
			Input.get_vector("move_left", "move_right", "move_forward", "move_back"),
			cam.global_transform.basis
		)

	var ev := cs.advance(delta, false, Input.is_action_just_pressed("dodge"), ss.drain())
	if ev == "dodge":
		# §7: dodge beats everything. It is the input most needed under pressure.
		_exit_stance("dodge")
		_knock = Vector3.ZERO
		_dodge_dir = wish if wish != Vector3.ZERO else -global_transform.basis.z
	if ev != "":
		Metrics.log_event(ev, {"stamina": snappedf(cs.stamina, 0.1)})
	# A stance cannot survive being staggered.
	if cs.state == CombatState.STAGGER and ss.stance != Stance.NONE:
		_exit_stance("stagger")
	if ss.stance == Stance.SWORD and ss.has_buffer() and _can_swing_now():
		_swing(ss.take_buffer())

	_aim(delta, cam)
	_apply_hit()
	_bow_visuals(cam)
	_move(delta, wish)


func _stance_edges() -> void:
	if Input.is_action_just_pressed("attack"):
		_enter_stance(weapon)
	elif Input.is_action_just_released("attack"):
		if ss.stance == Stance.BOW:
			_fire_bow()
		_exit_stance("release")
	if Input.is_action_just_pressed("block") and weapon != Stance.BOW:
		# §5 open question, defaulting to no: ranged safety costs you defence.
		_enter_stance(Stance.BLOCK)
	elif Input.is_action_just_released("block") and ss.stance == Stance.BLOCK:
		_exit_stance("release")


func _enter_stance(s: int) -> void:
	if ss.stance != Stance.NONE or cs.state != CombatState.IDLE:
		return
	ss.enter(s)
	g.press()
	Metrics.log_event("stance_entered", {"stance": ss.name_of()})
	if s == Stance.BLOCK:
		Metrics.log_event("block_entered", {})
	elif s == Stance.BOW:
		Metrics.log_event("draw_started", {})


func _exit_stance(why: String) -> void:
	if ss.stance == Stance.NONE:
		return
	Metrics.log_event(
		"stance_exited",
		{"stance": ss.name_of(), "why": why, "chain": ss.chain, "rejected": g.rejected}
	)
	ss.exit()
	g.release()
	cs.regen_timer = cs.regen_delay


func _swing(flick: Vector2) -> void:
	if not ss.can_chain():
		Metrics.log_event("chain_capped", {"n": ss.chain})
		return
	var level := ss.charge_level()
	var cost := ss.swing_cost()
	var from_state := cs.state
	# A follow-up may cancel the previous swing's recovery. An opener may not.
	var cancel_from := chain_cancel_from if ss.chain > 0 else INF
	if not cs.try_chain_attack(cost, cancel_from):
		Metrics.log_event("attack_refused", {"stamina": snappedf(cs.stamina, 0.1)})
		return

	var cam := get_viewport().get_camera_3d()
	var want := rotation.y
	if cam:
		var world := CameraRelative.project(flick, cam.global_transform.basis)
		if world != Vector3.ZERO:
			want = atan2(-world.x, -world.z)
	strike_yaw = Stance.clamp_cone(rotation.y, want, ss.cone_deg)
	var clamped_by := absf(wrapf(want - strike_yaw, -PI, PI))
	if clamped_by > 0.01:
		cone_flash = 0.5
		Metrics.log_event(
			"cone_clamped",
			{"requested_deg": snappedf(rad_to_deg(wrapf(want - rotation.y, -PI, PI)), 1.0),
			"applied_deg": snappedf(ss.cone_deg, 1.0)}
		)

	var cancelled := from_state == CombatState.RECOVERY
	debug_event.emit("swing", {
		"clamped": clamped_by > 0.01, "requested_yaw": want,
		"requested_deg": rad_to_deg(wrapf(want - rotation.y, -PI, PI)),
		"cancelled": cancelled,
	})
	if ss.chain == 0:
		chain_hits = 0
	_swing_level = level
	ss.on_swing()
	Metrics.log_event(
		"swing_fired",
		{"charge": snappedf(level, 0.01), "chain": ss.chain, "side": ss.side, "cost": cost, "cancelled": cancelled}
	)
	if ss.chain > 1:
		Metrics.log_event("chain_extended", {"n": ss.chain})


# Alive enemies. Queried every time rather than cached, because fight.gd spawns
# them after this node is ready and the count changes between fights.
func enemies() -> Array:
	return get_tree().get_nodes_in_group("enemies").filter(func(e): return not e.cs.dead())


func _can_swing_now() -> bool:
	if cs.state == CombatState.IDLE:
		return true
	return ss.chain > 0 and cs.state == CombatState.RECOVERY and cs.t >= chain_cancel_from


func strike_dir() -> Vector3:
	return Vector3(-sin(strike_yaw), 0.0, -cos(strike_yaw))


# `v` is a displacement in metres. A dodge shrugs it off.
func apply_knock(v: Vector3) -> void:
	v.y = 0.0
	if cs.state != CombatState.DODGE and v.length() > 0.001:
		_knock = v * knock_friction


func _fire_bow() -> void:
	var strength := g.drag_strength()
	if cs.stamina < ss.bow_cost:
		Metrics.log_event("attack_refused", {"stamina": snappedf(cs.stamina, 0.1)})
		return
	cs.stamina -= ss.bow_cost
	var dir := bow_aim()
	var length := bow_length(strength)
	# ponytail: hitscan. Make it a real projectile when arrow travel time becomes
	# a design question; at this range against a walking enemy it is not one.
	# The arrow stops at the nearest enemy inside its cone.
	var target: Node = null
	var nearest := INF
	for e in enemies():
		var d := global_position.distance_to(e.global_position)
		if d < nearest and CombatState.in_arc(global_position, dir, e.global_position, length, bow_arc):
			nearest = d
			target = e
	if target:
		var push := dir.normalized() * bow_knockback * strength
		target.take_hit(bow_damage * strength, hit_stagger * strength, push)
		debug_event.emit("dealt", {
			"dmg": bow_damage * strength, "stagger": hit_stagger * strength,
			"charge": 0.0, "chain": 0, "cap": 0, "source": "arrow",
			"target": target, "knock": push.length(), "finisher": false,
		})
	debug_event.emit("shot", {
		"from": global_position, "dir": dir, "len": nearest if target else length,
		"arc": bow_arc, "hit": target != null, "strength": strength,
	})
	Metrics.log_event(
		"arrow_fired",
		{"strength": snappedf(strength, 0.01), "deg": snappedf(rad_to_deg(atan2(-dir.x, -dir.z)), 1.0), "hit": target != null}
	)


# Fire direction for the bow: opposite the drag, projected into the world.
func bow_aim() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam:
		var world := CameraRelative.project(-g.drag, cam.global_transform.basis)
		if world != Vector3.ZERO:
			return world
	return -global_transform.basis.z


func bow_length(strength: float) -> float:
	return bow_range * maxf(strength, 0.05)


# The arc of the swing in progress. The hit test and debug_draw both read this,
# so the drawn fan cannot drift from what actually connects.
func swing_arc() -> float:
	return attack_arc * (1.0 + charge_arc_mult * _swing_level)


# The arc the NEXT swing would get if you flicked now.
func preview_arc() -> float:
	var level := ss.charge_level() if ss.chain == 0 else 0.0
	return attack_arc * (1.0 + charge_arc_mult * level)


# The damage path for everything that hits the player. Block has to intercept
# before take_damage, so enemy.gd calls this rather than cs.take_damage directly.
func receive_hit(amount: float) -> String:
	var was_blocking := ss.stance == Stance.BLOCK
	var hp_before := cs.health
	var r := ss.resolve_hit(cs, amount)
	debug_event.emit("taken", {"result": r, "amount": amount, "lost": hp_before - cs.health})
	if r == "broken" and was_blocking:
		g.release()
		Metrics.log_event("stance_exited", {"stance": "block", "why": "broken", "chain": 0, "rejected": g.rejected})
	return r


func _aim(delta: float, cam: Camera3D) -> void:
	var rate := Stance.rot_rate(ss.stance, cs.state)
	if rate <= 0.0 or cam == null:
		return
	var m := get_viewport().get_mouse_position()
	# Plane.intersects_ray returns Vector3 OR null - both the untyped var and
	# the null check are load-bearing.
	var hit = Plane(Vector3.UP, global_position.y).intersects_ray(
		cam.project_ray_origin(m), cam.project_ray_normal(m)
	)
	if hit == null:
		return
	var to_aim: Vector3 = hit - global_position
	to_aim.y = 0.0
	if to_aim.length() < 0.05:
		return
	rotation.y = rotate_toward(
		rotation.y, atan2(-to_aim.x, -to_aim.z), deg_to_rad(rate) * delta
	)


func _apply_hit() -> void:
	attack_box.visible = cs.state == CombatState.ACTIVE
	var active_now := cs.state == CombatState.ACTIVE
	if active_now and not _was_active:
		_hit_this_swing.clear()
	_was_active = active_now
	if not active_now:
		return
	# The strike direction is the cone-clamped yaw, not the body's facing. A swing
	# connects with every enemy inside its arc, each at most once.
	var finisher := ss.chain >= ss.chain_cap
	for e in enemies():
		var id: int = e.get_instance_id()
		if _hit_this_swing.has(id):
			continue
		if not CombatState.in_arc(global_position, strike_dir(), e.global_position, attack_reach, swing_arc()):
			continue
		_hit_this_swing[id] = true
		chain_hits += 1
		var dmg := attack_damage * (1.0 + charge_damage_mult * _swing_level)
		var stag := hit_stagger * (1.0 + charge_stagger_mult * _swing_level)
		var knock := attack_knockback * (1.0 + charge_knock_mult * _swing_level)
		if finisher:
			knock *= finisher_knock_mult
		# Pushed straight away from you, so one sweep through a crowd spreads it.
		var push: Vector3 = e.global_position - global_position
		push.y = 0.0
		e.take_hit(dmg, stag, push.normalized() * knock)
		debug_event.emit("dealt", {
			"dmg": dmg, "stagger": stag, "charge": _swing_level,
			"chain": ss.chain, "cap": ss.chain_cap, "source": "sword",
			"target": e, "knock": knock, "finisher": finisher,
		})
		Metrics.log_event("enemy_hit", {
			"id": e.name, "enemy_hp": snappedf(e.cs.health, 0.1),
			"charge": snappedf(_swing_level, 0.01), "chain": ss.chain,
		})


func _bow_visuals(cam: Camera3D) -> void:
	var drawing := ss.stance == Stance.BOW
	draw_line.visible = drawing
	fire_vector.visible = drawing
	if not drawing or cam == null:
		return
	var world := CameraRelative.project(g.drag, cam.global_transform.basis)
	if world == Vector3.ZERO:
		return
	# §5: this readout is the whole reason the mechanic works.
	draw_line.rotation.y = atan2(-world.x, -world.z) - rotation.y
	draw_line.scale.z = maxf(g.drag.length() * 0.02, 0.1)
	fire_vector.rotation.y = draw_line.rotation.y + PI
	fire_vector.scale.z = maxf(g.drag_strength() * 4.0, 0.1)


func _move(delta: float, wish: Vector3) -> void:
	var target := Vector3.ZERO
	match cs.state:
		CombatState.DODGE:
			target = _dodge_dir * (dodge_distance / maxf(dodge_time, 0.01))
		CombatState.ACTIVE:
			# Front-loaded dash along the strike direction. Speed falls off as
			# (1-x)^2, which covers attack_lunge metres in lunge_time and then stops
			# dead. Sampled at the frame midpoint, or the ~5-frame sum overshoots by
			# about a third.
			var lt := minf(lunge_time, active_time)
			if cs.t < lt:
				var k := 1.0 - minf((cs.t + delta * 0.5) / maxf(lt, 0.001), 1.0)
				target = strike_dir() * (3.0 * attack_lunge / maxf(lt, 0.001)) * k * k
		CombatState.IDLE:
			target = wish * move_speed * Stance.move_mult(ss.stance)

	# A live shove owns horizontal velocity outright, so steering cannot walk
	# straight back through it.
	if _knock.length() > 0.2:
		velocity.x = _knock.x
		velocity.z = _knock.z
		_knock *= exp(-knock_friction * delta)
	elif cs.state == CombatState.DODGE or cs.state == CombatState.ACTIVE:
		_knock = Vector3.ZERO
		velocity.x = target.x
		velocity.z = target.z
	else:
		_knock = Vector3.ZERO
		velocity.x = move_toward(velocity.x, target.x, ground_accel * delta)
		velocity.z = move_toward(velocity.z, target.z, ground_accel * delta)
	velocity.y -= gravity * delta
	move_and_slide()
