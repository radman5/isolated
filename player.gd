extends CharacterBody3D
# Sword input.
#
#   Click     one arc swing toward the cursor. Fires on press, never dashes.
#   Hold      the swing pauses at the top of its wind-up and charges. Every
#             link_charge_time adds a link, and the path it will take through
#             the enemies is drawn on the ground.
#   Release   dash-strikes each target on the path in turn, invulnerable, with a
#             whole-game hit freeze on every hit. No target in range: the swing
#             just goes out as a plain arc.
#
# A click and a charge are the same swing: the only difference is whether the
# button is still down when the wind-up would release. Both are the same committed
# WINDUP/ACTIVE/RECOVERY the enemy uses; the chain lives inside one held ACTIVE.

const CombatState := preload("res://combat_state.gd")
const CameraRelative := preload("res://camera_relative.gd")
const Gesture := preload("res://gesture.gd")
const Stance := preload("res://stance_state.gd")
const ArrowModel := preload("res://assets/kaykit/weapons/arrow_bow.gltf")
const Enemy := preload("res://enemy.gd")
const Hazard := preload("res://traps/hazard.gd")
const Fx := preload("res://fx.gd")

# For debug_draw.gd only. Gameplay never listens to this; kinds are
# "swing", "dealt", "taken", "shot".
signal debug_event(kind: String, data: Dictionary)

@export_group("Move")
@export var move_speed := 5.0
@export var ground_accel := 45.0
@export var gravity := 24.0

@export_group("Sneak")
## Hold Shift. Slower, and enemies hear you at noise() x their hear_range.
@export var sneak_move_mult := 0.45
@export var sneak_noise := 0.2
## A sleeping enemy's sight cone shrinks to this fraction while you sneak.
@export var sneak_sight_mult := 0.6

@export_group("Attack")
@export var windup_time := 0.22
@export var active_time := 0.10
@export var recovery_time := 0.35
@export var attack_damage := 25.0
@export var attack_reach := 2.0
@export var attack_arc := 55.0
@export var hit_stagger := 0.75

@export_group("Knockback")
@export var attack_knockback := 1.2  # metres, light hit
## The last link of a chain sends them flying straight ahead.
@export var finisher_knock_mult := 2.5
## Metres each earlier chain link throws its target off to the side, clearing the
## dash line so you are not boxed in when the chain ends. Chain links shove even
## an enemy committed to a swing; plain swings do not.
@export var link_knockback := 2.5
@export var bow_knockback := 1.0
## How fast a shove bleeds off. The distance is the same either way; this only
## changes whether it is a snap or a slide.
@export var knock_friction := 12.0

@export_group("Dodge")
@export var dodge_time := 0.40
@export var dodge_distance := 3.5
@export var iframe_start := 0.05
@export var iframe_end := 0.28
## Seconds from the start of one dodge to the next. There is no stamina
## (docs/adr/0001): cooldowns are the only limit on actions.
@export var dodge_cooldown := 0.65

@export_group("Health")
@export var health_max := 100.0

@export_group("Gesture")
## Needs calibration. Flick five times and read `peak` on the debug overlay.
@export_range(200.0, 6000.0, 10.0, "or_greater", "suffix:px/s") var flick_threshold := 1200.0
@export var flick_refractory := 0.12
## Set false if fast flicks feel dropped: input is accumulated to one motion
## event per rendered frame by default.
@export var raw_mouse_input := false

@export_group("Chain strike")
## Most links the sword can chain.
@export var sword_max_links := 5
## Most links the skill allows. ponytail: a plain export until a skill system exists.
@export var skill_max_links := 3
## Chain cooldown per link in the chain, so a longer chain waits longer. While it
## runs, holding the button is just a click swing. Plain swings are free.
## ponytail: a plain export until skills level up; the level should shrink this.
@export var chain_cooldown_per_link := 1.0
## Seconds of holding per extra link.
@export var link_charge_time := 0.35
## The first target must be this close to the player.
@export var chain_first_range := 6.0
## Half-angle of the wedge toward the cursor the first target must be in.
@export var chain_first_arc := 45.0
## How fast you turn while holding a sword charge or drawing the bow, deg/s.
@export var charge_turn_rate := 720.0
## Each next target must be this close to the previous one.
@export var chain_hop_range := 4.5
## Seconds to dash to each target.
@export var link_dash_time := 0.07
## Where the dash stops, in metres short of the target's centre.
@export var link_standoff := 1.1
## Whole-game freeze on each link, and on the last one.
@export var hitstop_time := 0.05
@export var hitstop_last := 0.10

@export_group("Impact")
## Knocked-back enemies slide in slow motion for this long (real seconds), easing
## back to normal. Only the victims: you, the dash and everyone else stay at full
## speed. F2 turns all of this off.
@export var link_knock_slowmo := 0.6
@export var last_knock_slowmo := 1.0
@export var knock_slowmo_scale := 0.25
## A click swing that connects gets a short freeze frame too.
@export var swing_hitstop := 0.04
## Camera kick per hit, along the hit direction (see follow_camera.gd).
@export var link_shake := 0.35
@export var last_shake := 0.6
@export var swing_shake := 0.15
@export var arrow_shake := 0.2
@export var hurt_shake := 0.4
## Move speed while holding a charge, as a fraction of move_speed.
@export var charge_move_mult := 0.35

@export_group("Bow")
@export var bow_damage := 30.0
@export var bow_range := 14.0
@export var bow_arc := 8.0
## Pierce budget at full draw is bow_pierce + skill_pierce, scaled by draw. Each
## enemy an arrow passes through spends its toughness.
@export var bow_pierce := 2.0
## ponytail: a plain export until a skill system exists.
@export var skill_pierce := 1.0
## Damage lost per enemy already pierced, compounding.
@export var pierce_falloff := 0.15
## Metres per second an arrow flies.
@export var arrow_speed := 40.0
## Size of the flying arrow model; 1.0 is hand-sized and hard to see from the camera.
@export var arrow_scale := 1.6
## Degrees between arrows in a volley.
@export var arrow_spread_deg := 8.0
## Pull back at least this far (screen px) to nock the arrow. From then on the
## draw grows with time, not with how far you pull; the pull only aims.
@export var bow_draw_threshold := 60.0
## Seconds from nocked to full draw.
@export var bow_charge_time := 1.0
## Draw the moment the arrow is nocked, as a fraction of full.
@export var bow_min_draw := 0.2
## Key 3's volley waits this long after firing.
@export var volley_cooldown := 2.0
## Key 4: arrow rain. Hold grows the circle and its arrow count from min to max
## over rain_grow_time; the circle trails the cursor at rain_follow_speed and
## stays within rain_range of you. Release shoots them up; they land scattered.
@export var rain_cooldown_per_arrow := 0.25
@export var rain_range := 14.0
@export var rain_follow_speed := 6.0
@export var rain_grow_time := 1.5
@export var rain_min_diameter := 1.0
@export var rain_max_diameter := 5.0
@export var rain_min_arrows := 4
@export var rain_max_arrows := 20
@export var rain_damage := 15.0
## An arrow hits every enemy within this of where it lands.
@export var rain_hit_radius := 0.8
## Falling arrows start this high, above the camera, so they drop into view.
@export var rain_height := 30.0

@export_group("Block")
@export var block_chip := 0.25
## §6: block must pass its own gate before this is worth turning on.
@export var parry_enabled := false
@export var parry_window := 0.20

const CS_TUNABLES := [
	"windup_time", "active_time", "recovery_time", "dodge_time", "iframe_start",
	"iframe_end", "dodge_cooldown", "health_max",
]
const SS_TUNABLES := ["block_chip", "parry_window", "parry_enabled"]

enum BowMode { SINGLE, VOLLEY, RAIN }
const BOW_MODE_NAMES := ["shot", "volley", "rain"]

# Arrows in a key-3 volley, tuned by the HUD buttons. Static so it survives the
# reload after each fight.
static var arrow_count := 3

var cs := CombatState.new()
var cam_rel := CameraRelative.new()
var g := Gesture.new()
var ss := Stance.new()

var weapon := Stance.SWORD  # which weapon LMB draws
var last_flick_deg := 0.0
var draw_strength := 0.0  # bow draw 0..1; also bends the bowstring
var _nocked_for := -1.0  # seconds since the pull passed bow_draw_threshold; -1 = not yet

var dodge_dir := Vector3.FORWARD  # read by character_view to pick the dodge animation
var strike_yaw := 0.0  # direction of the current swing
var chain_hits := 0  # links landed by the current chain
var chain_ready_in := 0.0  # seconds until the chain can be charged again
var carrying := {}  # item name -> true, filled by pickup.gd
var bow_mode := BowMode.SINGLE  # 2 shot, 3 volley, 4 rain
var volley_ready_in := 0.0
var rain_ready_in := 0.0
var rain_target := Vector3.ZERO  # centre of the rain circle; trails the cursor
var _rain_hold := 0.0  # seconds the rain has been held
var _rng := RandomNumberGenerator.new()
# Index of the link being dashed to; -1 for a plain swing. Read by character_view
# to restart the slash on each link.
var link_i := -1
var _chain: Array = []  # enemies to visit, in order; non-empty only while it plays
var _link_t := 0.0
var _chain_vel := Vector3.ZERO
var _hitstop_until := 0  # msec
var _flights: Array = []  # arrows in the air: {node, dir, from, len, travelled, hits}
var _ghosting := false  # passing through enemies: while dodging or chaining
var _preview := ImmediateMesh.new()
var sneaking := false
var _hit_this_swing := {}  # instance ids already hit by the swing in progress
var _knock := Vector3.ZERO
# Each press gets an id, and a swing remembers the press that started it. Only
# that press can hold it into a charge, so a stray click during a swing that is
# then held does not turn the current swing into a charge.
var _press_id := 0
var _swing_press := -1
var _was_active := false
var _reject_cool := 0.0



func _ready() -> void:
	add_to_group("player")
	Fx.prewarm.call_deferred(get_tree(), global_position)
	cs.health_max = health_max
	cs.health = health_max
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	# Without an escape you cannot get the cursor back to quit.
	if raw_mouse_input:
		Input.use_accumulated_input = false
	var mi := MeshInstance3D.new()
	mi.mesh = _preview
	mi.top_level = true
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	mi.material_override = m
	add_child(mi)


# A scene reload mid-freeze would otherwise leave the whole game stopped.
func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _process(_delta: float) -> void:
	# _process still runs while time_scale is 0, which is what lets it end.
	if Engine.time_scale == 0.0 and Time.get_ticks_msec() >= _hitstop_until:
		Engine.time_scale = 1.0
	_aim_preview()


# Flicks are handled here rather than in _physics_process so the swing starts on
# the frame the threshold is crossed. CombatState is pure, so firing it outside
# the physics step just sets state/t and the next step advances it.
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseMotion):
		return
	# Motion is only a gesture for parry now: the sword is clicked, and a charge
	# reads the accumulated pull-back rather than individual flicks.
	var flick := g.sample(event.relative, event.screen_velocity)
	if flick == Vector2.ZERO or ss.stance != Stance.BLOCK:
		return
	last_flick_deg = rad_to_deg(atan2(flick.x, -flick.y))
	if ss.try_parry():
		Metrics.log_event("parry_attempted", {})


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F2:
		Fx.on = not Fx.on
		Metrics.log_event("fx_toggled", {"on": Fx.on})
	# Debug weapon selector, NOT a swap mechanic: gated to a neutral stance, so
	# no mid-chain swap, which is what §13 and the §4 v2 hook actually forbid.
	elif event.is_action_pressed("weapon_sword") and ss.stance == Stance.NONE:
		weapon = Stance.SWORD
	elif event.is_action_pressed("weapon_bow") and ss.stance == Stance.NONE:
		weapon = Stance.BOW
		bow_mode = BowMode.SINGLE
	elif event is InputEventKey and event.pressed and not event.echo and ss.stance == Stance.NONE \
			and event.physical_keycode in [KEY_3, KEY_4]:
		weapon = Stance.BOW
		bow_mode = BowMode.VOLLEY if event.physical_keycode == KEY_3 else BowMode.RAIN


func _physics_process(delta: float) -> void:
	for k in CS_TUNABLES:
		cs.set(k, get(k))
	for k in SS_TUNABLES:
		ss.set(k, get(k))
	g.flick_threshold = flick_threshold
	g.refractory = flick_refractory

	g.tick(delta)
	_reject_cool = maxf(0.0, _reject_cool - delta)
	chain_ready_in = maxf(0.0, chain_ready_in - delta)
	volley_ready_in = maxf(0.0, volley_ready_in - delta)
	rain_ready_in = maxf(0.0, rain_ready_in - delta)
	_stance_edges()
	cs.hold = (
		weapon == Stance.SWORD and ss.stance == Stance.NONE
		and Input.is_action_pressed("attack") and _swing_press == _press_id
		and chain_ready_in == 0.0
	)
	ss.tick(delta)
	if ss.stance == Stance.BOW and bow_mode == BowMode.RAIN:
		_rain_hold += delta
		var cursor = _cursor_point(get_viewport().get_camera_3d())
		if cursor != null:
			rain_target = Stance.rain_follow(
				rain_target, cursor, global_position, rain_range, rain_follow_speed, delta
			)
		draw_strength = clampf(_rain_hold / maxf(rain_grow_time, 0.001), 0.0, 1.0)
	elif ss.stance == Stance.BOW:
		if _nocked_for < 0.0 and g.drag.length() >= bow_draw_threshold:
			_nocked_for = 0.0
		elif _nocked_for >= 0.0:
			_nocked_for += delta
		draw_strength = Stance.bow_draw(_nocked_for, bow_charge_time, bow_min_draw)
	else:
		_nocked_for = -1.0
		draw_strength = 0.0

	var cam := get_viewport().get_camera_3d()
	var wish := Vector3.ZERO
	if cam:
		wish = cam_rel.to_world(
			Input.get_vector("move_left", "move_right", "move_forward", "move_back"),
			cam.global_transform.basis
		)

	sneaking = Input.is_action_pressed("sneak")
	var ev := cs.advance(delta, false, Input.is_action_just_pressed("dodge"))
	if ev == "dodge":
		# §7: dodge beats everything. It is the input most needed under pressure.
		_exit_stance("dodge")
		_knock = Vector3.ZERO
		dodge_dir = wish if wish != Vector3.ZERO else -global_transform.basis.z
	if ev != "":
		Metrics.log_event(ev, {"cooldown": snappedf(cs.dodge_ready_in, 0.01)})
	# A stance cannot survive being staggered.
	if cs.state == CombatState.STAGGER and ss.stance != Stance.NONE:
		_exit_stance("stagger")

	_aim(delta, cam)
	_run_chain(delta)
	_fly_arrows(delta)
	_update_ghost()
	_apply_hit()
	_move(delta, wish)


func _stance_edges() -> void:
	if weapon == Stance.BOW:
		if Input.is_action_just_pressed("attack"):
			_start_draw()
		elif Input.is_action_just_released("attack") and ss.stance == Stance.BOW:
			if bow_mode == BowMode.RAIN:
				_fire_rain()
			else:
				_fire_bow()
			_exit_stance("release")
	else:
		_sword_edges()
	if Input.is_action_just_pressed("block") and weapon != Stance.BOW:
		# §5 open question, defaulting to no: ranged safety costs you defence.
		_enter_stance(Stance.BLOCK)
	elif Input.is_action_just_released("block") and ss.stance == Stance.BLOCK:
		_exit_stance("release")


# A mode still cooling down refuses the draw, so the release fires nothing.
func _start_draw() -> void:
	var wait: float = {BowMode.VOLLEY: volley_ready_in, BowMode.RAIN: rain_ready_in}.get(bow_mode, 0.0)
	if wait > 0.0:
		Metrics.log_event("attack_refused", {"mode": BOW_MODE_NAMES[bow_mode], "cooldown": snappedf(wait, 0.01)})
		return
	_enter_stance(Stance.BOW)
	if ss.stance == Stance.BOW and bow_mode == BowMode.RAIN:
		_rain_hold = 0.0
		var cursor = _cursor_point(get_viewport().get_camera_3d())
		var goal: Vector3 = cursor if cursor != null else global_position
		rain_target = Stance.rain_follow(goal, goal, global_position, rain_range, 0.0, 0.0)


func _sword_edges() -> void:
	if Input.is_action_just_pressed("attack") and ss.stance == Stance.NONE:
		_press_id += 1
		# No buffer and no combo: a click during a swing is simply ignored.
		if cs.state == CombatState.IDLE:
			_start_swing(_press_id)
	elif Input.is_action_just_released("attack"):
		# cs.hold is still last frame's value here, so charging() is accurate.
		if cs.charging():
			_release_charge()


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
		{"stance": ss.name_of(), "why": why, "rejected": g.rejected}
	)
	ss.exit()
	g.release()


func _start_swing(press: int) -> void:
	if not cs.try_attack(0.0):  # a plain swing is free
		return
	# A click strikes exactly at the cursor, so snap to it rather than waiting on
	# the rotation clamp to catch up. Facing then locks for the wind-up.
	_face_cursor()
	_swing_press = press
	link_i = -1
	debug_event.emit("swing", {
		"clamped": false, "requested_yaw": strike_yaw, "requested_deg": 0.0, "cancelled": false,
	})
	Metrics.log_event("swing_fired", {})


func _face_cursor() -> void:
	var yaw = _cursor_yaw(get_viewport().get_camera_3d())
	if yaw != null:
		rotation.y = yaw
	strike_yaw = rotation.y


# Links a release would chain right now.
func links_now() -> int:
	return Stance.link_count(cs.charge_seconds(), link_charge_time, sword_max_links, skill_max_links)


func link_cap() -> int:
	return mini(sword_max_links, skill_max_links)


# Enemies the chain would visit if released now, in order.
func chain_targets(links: int) -> Array:
	var foes := enemies()
	var at := foes.map(func(e): return e.global_position)
	return Stance.chain_path(
		chain_cursor(), global_position, at, links, chain_first_range, chain_hop_range,
		chain_facing(), chain_first_arc
	).map(func(i): return foes[i])


func chain_cursor() -> Vector3:
	var cursor = _cursor_point(get_viewport().get_camera_3d())
	return cursor if cursor != null else global_position - global_transform.basis.z * 2.0


# The wedge points at the cursor, not the body, so it never lags the turn.
func chain_facing() -> Vector3:
	var to := chain_cursor() - global_position
	to.y = 0.0
	return to.normalized() if to.length() > 0.05 else -global_transform.basis.z


func chaining() -> bool:
	return not _chain.is_empty()


# Sends a held swing. With a target in range it becomes a chain; otherwise it
# goes out as a plain arc at the cursor.
func _release_charge() -> void:
	cs.hold = false
	var links := links_now()
	var path := chain_targets(links)
	Metrics.log_event("chain_released", {
		"links": links, "cap": link_cap(), "targets": path.size(),
	})
	if path.is_empty():
		_face_cursor()
		return
	chain_ready_in = chain_cooldown_per_link * path.size()
	_chain = path
	link_i = 0
	_link_t = 0.0
	chain_hits = 0
	_knock = Vector3.ZERO
	cs.hold_active = true


# Dashes to the current link's target and strikes it on arrival. Targets are
# followed live, so one that was knocked or walked is still reached.
func _run_chain(delta: float) -> void:
	_chain_vel = Vector3.ZERO
	# Physics still steps during a hitstop, with delta 0. Past the dash time the
	# divide below is by zero, and an infinite velocity times 0 is NaN.
	if not chaining() or delta <= 0.0:
		return
	var e = _chain[link_i]
	if not is_instance_valid(e) or e.cs.dead():
		_next_link()
		return
	var to: Vector3 = e.global_position - global_position
	to.y = 0.0
	rotation.y = atan2(-to.x, -to.z)
	strike_yaw = rotation.y
	var gap := to.length() - link_standoff
	# Arrived, or blocked by a wall: give up after the dash time plus a little and
	# strike only if it is actually in reach.
	if gap <= 0.05 or _link_t > link_dash_time + 0.1:
		if to.length() <= attack_reach + 0.1:
			_land_link(e, to.normalized())
		_next_link()
		return
	_chain_vel = to.normalized() * gap / maxf(link_dash_time - _link_t, delta)
	_link_t += delta


func _land_link(e: Node, dir: Vector3) -> void:
	var last := link_i == _chain.size() - 1
	var push := dir * attack_knockback * finisher_knock_mult
	if not last:
		# Off to the side, away from where the next link is going, and a little
		# ahead. Targets are followed live, so moving this one costs the path nothing.
		var side := Vector3(-dir.z, 0.0, dir.x)
		var next = _chain[link_i + 1]
		if is_instance_valid(next) and side.dot(next.global_position - e.global_position) > 0.0:
			side = -side
		push = (side + dir * 0.5).normalized() * link_knockback
	e.take_hit(attack_damage, hit_stagger, push, true)
	chain_hits += 1
	debug_event.emit("dealt", {
		"dmg": attack_damage, "stagger": hit_stagger, "charge": 0.0,
		"chain": link_i + 1, "cap": _chain.size(), "source": "chain",
		"target": e, "knock": push.length(), "finisher": last,
	})
	Metrics.log_event("chain_link_hit", {"i": link_i + 1, "id": e.name, "enemy_hp": snappedf(e.cs.health, 0.1)})
	if Fx.on:
		e.slow_mo(last_knock_slowmo if last else link_knock_slowmo, knock_slowmo_scale)
	if last:
		_hitstop(hitstop_last)
		_impact(e, dir, last_shake, 26)
		Fx.ring(get_tree(), e.global_position, Color(1.0, 0.85, 0.3, 0.9), 3.0)
	else:
		_hitstop(hitstop_time)
		_impact(e, dir, link_shake, 14)


func _next_link() -> void:
	link_i += 1
	_link_t = 0.0
	if link_i >= _chain.size():
		_chain.clear()
		cs.hold_active = false


# Dodging and chaining pass through enemies, so a roll is a way out of a crowd.
# Collision comes back only once no enemy overlaps, or the capsules would be
# left inside each other and shove apart.
func _update_ghost() -> void:
	var want := cs.state == CombatState.DODGE or chaining()
	if not want and _ghosting:
		for e in enemies():
			if Vector2(e.global_position.x - global_position.x, e.global_position.z - global_position.z).length() < 1.0:
				want = true
				break
	if want == _ghosting:
		return
	_ghosting = want
	for e in get_tree().get_nodes_in_group("enemies"):
		if want:
			add_collision_exception_with(e)
		else:
			remove_collision_exception_with(e)


# Freezes the whole game. A second freeze extends the first rather than stacking.
func _hitstop(secs: float) -> void:
	if secs <= 0.0:
		return
	_hitstop_until = maxi(_hitstop_until, Time.get_ticks_msec() + int(secs * 1000.0))
	Engine.time_scale = 0.0


func _shake(amount: float, dir := Vector3.ZERO) -> void:
	var cam := get_viewport().get_camera_3d()
	if Fx.on and cam and cam.has_method("shake"):
		cam.shake(amount, dir)


# Sparks at chest height, a flash, a shake. The shared part of every landed hit.
func _impact(e: Node, dir: Vector3, shake: float, sparks: int) -> void:
	Fx.sparks(get_tree(), e.global_position + Vector3(0, 0.3, 0), dir, Color(1.0, 0.85, 0.4), sparks)
	Fx.flash(e)
	_shake(shake, dir)


# Alive enemies. Queried every time rather than cached, because fight.gd spawns
# them after this node is ready and the count changes between fights.
func enemies() -> Array:
	return get_tree().get_nodes_in_group("enemies").filter(func(e): return not e.cs.dead())


func strike_dir() -> Vector3:
	return Vector3(-sin(strike_yaw), 0.0, -cos(strike_yaw))


# `v` is a displacement in metres. A dodge shrugs it off.
func apply_knock(v: Vector3) -> void:
	v.y = 0.0
	if cs.state != CombatState.DODGE and v.length() > 0.001:
		_knock = v * knock_friction


func _fire_bow() -> void:
	var strength := draw_strength
	if bow_mode == BowMode.VOLLEY:
		volley_ready_in = volley_cooldown
	var hits := 0
	var max_pierce := 0
	# ponytail: who gets hit is decided at release (the preview's answer), and each
	# hit lands when the flying arrow reaches that enemy's distance. An enemy that
	# walks out of the line mid-flight still gets hit; make it a swept collision
	# check if that ever reads wrong at this speed (0.35s across the full 14m).
	for arrow in arrow_hits(strength):
		var dir: Vector3 = arrow.dir
		var targets: Array = arrow.targets
		var planned := []
		for n in targets.size():
			var e = targets[n]
			var to: Vector3 = e.global_position - global_position
			planned.append({"at": maxf(Vector2(to.x, to.z).length() - 0.4, 0.0), "e": e, "n": n})
			hits += 1
			max_pierce = maxi(max_pierce, n)
		for s in arrow.shoots:
			planned.append({"at": s.at, "shoot": s.node})
		planned.sort_custom(func(a, b): return a.at < b.at)
		_launch(dir, arrow.len, planned, strength)
		debug_event.emit("shot", {
			"from": global_position, "dir": dir, "len": arrow.len,
			"arc": bow_arc, "hit": not targets.is_empty() or not arrow.shoots.is_empty(), "strength": strength,
		})
	Metrics.log_event("arrow_fired", {
		"strength": snappedf(strength, 0.01), "arrows": arrows_now(), "hits": hits, "max_pierce": max_pierce,
	})


# Diameter and arrow count the rain would have if released now.
func rain_size() -> Vector2:
	return Stance.rain_size(
		_rain_hold, rain_grow_time, rain_min_diameter, rain_max_diameter, rain_min_arrows, rain_max_arrows
	)


# Arrows go up from the bow, then one falls onto each random point in the
# circle. Who gets hit is decided where each lands, not at release: it is an
# area denial shot, so walking out of it should work.
func _fire_rain() -> void:
	var size := rain_size()
	var n := int(size.y)
	rain_ready_in = rain_cooldown_per_arrow * n
	var toward := rain_target - global_position
	toward.y = 0.0
	toward = toward.normalized() if toward.length() > 0.05 else -global_transform.basis.z
	var up := (Vector3.UP + toward * 0.25).normalized()
	var down := (Vector3.DOWN + toward * 0.15).normalized()
	var points := Stance.rain_points(rain_target, size.x, n, _rng)
	for i in n:
		_launch(up, 20.0, [], 1.0)
		# Each starts a little higher than the last, so they land ~0.05s apart.
		var fall := (rain_height + i * 2.0) / -down.y
		_launch(down, fall, [{"at": fall, "rain": points[i]}], 1.0, points[i] - down * fall)
	Metrics.log_event("rain_fired", {"arrows": n, "diameter": snappedf(size.x, 0.1)})


func _rain_land(point: Vector3) -> void:
	var hits := 0
	for e in enemies():
		if Vector2(e.global_position.x - point.x, e.global_position.z - point.z).length() > rain_hit_radius:
			continue
		hits += 1
		e.take_hit(rain_damage, hit_stagger * 0.5)
		_impact(e, Vector3.DOWN, arrow_shake * 0.5, 8)
		debug_event.emit("dealt", {
			"dmg": rain_damage, "stagger": hit_stagger * 0.5, "charge": 0.0, "chain": 0, "cap": 0,
			"source": "rain", "pierce": 0, "target": e, "knock": 0.0, "finisher": false,
		})
	Fx.ring(get_tree(), Vector3(point.x, 0.05, point.z),
		Color(0.35, 1.0, 0.45, 0.9) if hits > 0 else Color(1, 1, 1, 0.35), 0.8)
	Metrics.log_event("rain_arrow_landed", {"hits": hits})


func _launch(dir: Vector3, length: float, planned: Array, strength: float, from = null) -> void:
	var node: Node3D = ArrowModel.instantiate()
	get_parent().add_child(node)
	# Roughly bow height, a little ahead. The model's tip points +Z.
	if from == null:
		from = global_position + Vector3(0, 0.35, 0) + dir * 0.5
	node.global_transform = Transform3D(Basis.looking_at(-dir).scaled(Vector3.ONE * arrow_scale), from)
	node.reset_physics_interpolation()
	_flights.append({
		"node": node, "dir": dir, "from": from, "len": length,
		"travelled": 0.0, "hits": planned, "strength": strength,
	})


func _fly_arrows(delta: float) -> void:
	for f in _flights:
		f.travelled = minf(f.travelled + arrow_speed * delta, f.len)
		f.node.global_position = f.from + f.dir * f.travelled
		while not f.hits.is_empty() and f.hits[0].at <= f.travelled:
			var h: Dictionary = f.hits.pop_front()
			if h.has("rain"):
				_rain_land(h.rain)
			elif h.has("shoot"):
				if is_instance_valid(h.shoot):
					h.shoot.shot()
			else:
				_arrow_hit(h.e, h.n, f.dir, f.strength)
		if f.travelled >= f.len:
			f.node.queue_free()
	_flights = _flights.filter(func(f): return f.travelled < f.len)


func _arrow_hit(e, n: int, dir: Vector3, strength: float) -> void:
	if not is_instance_valid(e) or e.cs.dead():
		return
	var dmg := arrow_damage(strength, n)
	var push := dir * bow_knockback * strength
	e.take_hit(dmg, hit_stagger * strength, push)
	_impact(e, dir, arrow_shake * strength, 12)
	Fx.ring(get_tree(), e.global_position, Color(0.35, 1.0, 0.45, 0.9))
	debug_event.emit("dealt", {
		"dmg": dmg, "stagger": hit_stagger * strength, "charge": 0.0, "chain": 0, "cap": 0,
		"source": "arrow", "pierce": n, "target": e, "knock": push.length(), "finisher": false,
	})


func arrows_now() -> int:
	return arrow_count if bow_mode == BowMode.VOLLEY else 1


func pierce_budget(strength: float) -> float:
	return strength * (bow_pierce + skill_pierce)


func arrow_damage(strength: float, pierced: int) -> float:
	return bow_damage * strength * pow(1.0 - pierce_falloff, pierced)


# What each arrow of a volley released at `strength` would hit: one
# {dir, len, targets} per arrow. The shot and the preview both read this, so
# what is drawn is what lands.
func arrow_hits(strength: float) -> Array:
	var foes := enemies()
	var at := foes.map(func(e): return e.global_position)
	var tough := foes.map(func(e): return e.toughness)
	var length := bow_length(strength)
	var out := []
	for dir in Stance.fan_dirs(bow_aim().normalized(), arrows_now(), arrow_spread_deg):
		var idx := Stance.arrow_path(global_position, dir, at, tough, length, bow_arc, pierce_budget(strength))
		var targets := idx.map(func(i): return foes[i])
		var reach := length
		if not targets.is_empty():
			var last: Vector3 = targets[-1].global_position - global_position
			reach = Vector2(last.x, last.z).length()
		# Things an arrow can hit that are not enemies (a trap's rope): anything in
		# the "shootables" group with shoot_position(), shoot_radius and shot().
		var shoots := []
		for s in get_tree().get_nodes_in_group("shootables"):
			var along := Stance.shot_passes(global_position, dir, reach, s.shoot_position(), s.shoot_radius)
			if along >= 0.0:
				shoots.append({"node": s, "at": along})
		out.append({"dir": dir, "len": reach, "targets": targets, "shoots": shoots})
	return out


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


# Killed by the room: a pit, a falling weight, spikes. Ignores armour, blocking
# and i-frames - the whole point of §4's hazard is beating what the sword cannot.
func env_kill(how: String) -> void:
	if cs.dead():
		return
	cs.health = 0.0
	_chain.clear()
	Metrics.log_event("player_killed_by_env", {"how": how})
	if how == "fall":
		Enemy._drop(self)


# Fire and the like: straight to health, past block and i-frames.
func env_damage(amount: float) -> void:
	if cs.dead():
		return
	cs.health = maxf(0.0, cs.health - amount)


# The damage path for everything that hits the player. Block has to intercept
# before take_damage, so enemy.gd calls this rather than cs.take_damage directly.
func receive_hit(amount: float) -> String:
	if chaining():
		debug_event.emit("taken", {"result": "dodged", "amount": amount, "lost": 0.0})
		return "dodged"
	var hp_before := cs.health
	var r := ss.resolve_hit(cs, amount)
	debug_event.emit("taken", {"result": r, "amount": amount, "lost": hp_before - cs.health})
	if r == "hit":
		_shake(hurt_shake)
	elif r == "blocked":
		_shake(hurt_shake * 0.5)
	return r


func _aim(delta: float, cam: Camera3D) -> void:
	var rate := Stance.rot_rate(ss.stance, cs.state)
	var yaw = null
	if ss.stance == Stance.BOW and bow_mode == BowMode.RAIN:
		var to := rain_target - global_position
		if to.length() < 0.05:
			return
		yaw = atan2(-to.x, -to.z)
		rate = charge_turn_rate
	elif ss.stance == Stance.BOW:
		# Face where the arrow will go: opposite the pull. Only once the pull is
		# past the nock threshold, so a small wobble on press does not spin you.
		if g.drag.length() < bow_draw_threshold:
			return
		var d := bow_aim()
		yaw = atan2(-d.x, -d.z)
		rate = charge_turn_rate
	elif cs.charging():
		yaw = _cursor_yaw(cam)
		rate = charge_turn_rate
	elif rate > 0.0:
		yaw = _cursor_yaw(cam)
	if yaw != null:
		rotation.y = rotate_toward(rotation.y, yaw, deg_to_rad(rate) * delta)


# The ground point under the cursor, or null if there is none.
func _cursor_point(cam: Camera3D) -> Variant:
	if cam == null:
		return null
	var m := get_viewport().get_mouse_position()
	# Plane.intersects_ray returns Vector3 OR null - both the untyped var and
	# the null check are load-bearing.
	return Plane(Vector3.UP, global_position.y).intersects_ray(
		cam.project_ray_origin(m), cam.project_ray_normal(m)
	)


# Yaw from the player to the point under the cursor, or null if there is none.
func _cursor_yaw(cam: Camera3D) -> Variant:
	var hit = _cursor_point(cam)
	if hit == null:
		return null
	var to_aim: Vector3 = hit - global_position
	to_aim.y = 0.0
	if to_aim.length() < 0.05:
		return null
	return atan2(-to_aim.x, -to_aim.z)


# A plain swing connects with every enemy inside its arc, each at most once. A
# chain strikes its targets one at a time in _land_link instead.
func _apply_hit() -> void:
	var active_now := cs.state == CombatState.ACTIVE
	if active_now and not _was_active:
		_hit_this_swing.clear()
	_was_active = active_now
	if not active_now or link_i >= 0:
		return
	for e in enemies():
		var id: int = e.get_instance_id()
		if _hit_this_swing.has(id):
			continue
		if not CombatState.in_arc(global_position, strike_dir(), e.global_position, attack_reach, attack_arc):
			continue
		_hit_this_swing[id] = true
		var push: Vector3 = e.global_position - global_position
		push.y = 0.0
		e.take_hit(attack_damage, hit_stagger, push.normalized() * attack_knockback)
		_impact(e, push.normalized(), swing_shake, 8)
		if Fx.on:
			_hitstop(swing_hitstop)
		debug_event.emit("dealt", {
			"dmg": attack_damage, "stagger": hit_stagger, "charge": 0.0,
			"chain": 0, "cap": 0, "source": "sword",
			"target": e, "knock": attack_knockback, "finisher": false,
		})
		Metrics.log_event("enemy_hit", {"id": e.name, "enemy_hp": snappedf(e.cs.health, 0.1)})


# How loud you are: 0 standing still, sneak_noise sneaking, 1 walking.
# Dodges, chains and knockback all count as walking.
func noise() -> float:
	if Vector2(velocity.x, velocity.z).length() < 0.5:
		return 0.0
	return sneak_noise if sneaking and cs.state != CombatState.DODGE and not chaining() else 1.0


# Where a release would go, drawn on the ground. Sword: the chain path, bright
# rings on locked-in links and a faint one on what another link would add. Bow:
# each arrow's line to where it stops, with a ring on every enemy it hits, dimmer
# after each pierce. Gameplay UI, so not behind the F1 debug toggle.
func _aim_preview() -> void:
	_preview.clear_surfaces()
	_sense_preview()
	if cs.charging():
		var links := links_now()
		var path := chain_targets(links + 1 if links < link_cap() else links)
		_preview.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		var from := _ground(self)
		_wedge(from, chain_facing(), chain_first_arc, chain_first_range, Color(1.0, 0.85, 0.2, 0.3))
		for i in path.size():
			var at := _ground(path[i])
			var locked := i < links
			var col := Color(1.0, 0.85, 0.2, 0.9) if locked else Color(1, 1, 1, 0.3)
			_ribbon(from, at, 0.06 if locked else 0.03, col)
			_ring(at, 0.55, 0.07, col)
			from = at
		_preview.surface_end()
	elif ss.stance == Stance.BOW and bow_mode == BowMode.RAIN:
		var r := rain_size().x * 0.5
		var c := Vector3(rain_target.x, 0.05, rain_target.z)
		_preview.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		_ring(_ground(self), rain_range, 0.04, Color(1, 1, 1, 0.15))
		_ring(c, r, 0.08, Color(0.35, 1.0, 0.45, 0.8))
		for e in enemies():
			var at := _ground(e)
			if Vector2(at.x - c.x, at.z - c.z).length() <= r:
				_ring(at, 0.55, 0.07, Color(0.35, 1.0, 0.45, 0.95))
		_preview.surface_end()
	elif ss.stance == Stance.BOW:
		var strength := draw_strength
		_preview.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		var origin := _ground(self)
		for arrow in arrow_hits(strength):
			var hit: bool = not arrow.targets.is_empty()
			var line_col := Color(0.35, 1.0, 0.45, 0.8) if hit else Color(1, 1, 1, 0.35)
			var end: Vector3 = origin + arrow.dir * arrow.len
			_ribbon(origin, end, 0.04, line_col)
			if not hit:
				_ring(end, 0.18, 0.05, line_col)
			for s in arrow.shoots:
				var p: Vector3 = s.node.shoot_position()
				_ring(Vector3(p.x, 0.05, p.z), s.node.shoot_radius + 0.15, 0.07, Color(1.0, 0.85, 0.2, 0.95))
			for n in arrow.targets.size():
				var a := pow(1.0 - pierce_falloff, n)
				_ring(_ground(arrow.targets[n]), 0.55, 0.07, Color(0.35, 1.0, 0.45, 0.95 * a))
		_preview.surface_end()


# What each sleeping enemy can sense: its sight cone (shrinks while you sneak) and
# a faint ring for how far it hears you right now. Gameplay UI, not debug.
# ponytail: the cone ignores walls; the sight check does not. Clip it with rays
# if players read the drawn cone as the truth and feel cheated.
func _sense_preview() -> void:
	var sleepers := get_tree().get_nodes_in_group("enemies").filter(
		func(e): return e.has_method("awake") and not e.awake() and not e.cs.dead()
	)
	if sleepers.is_empty():
		return
	_preview.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for e in sleepers:
		var c := _ground(e)
		var fwd: Vector3 = -e.get_global_transform_interpolated().basis.z
		fwd.y = 0.0
		_wedge(c, fwd.normalized(), e.sight_half_angle, e.sight_now(), Color(1.0, 0.95, 0.6, 0.45))
		var hear: float = e.hear_range * noise()
		if hear > 0.3:
			_ring(c, hear, 0.03, Color(0.6, 0.8, 1.0, 0.35))
	_preview.surface_end()


# Outline of where a chain's first target can be.
func _wedge(c: Vector3, facing: Vector3, half_deg: float, r: float, col: Color) -> void:
	const SEGS := 16
	var left := facing.rotated(Vector3.UP, deg_to_rad(half_deg))
	var right := facing.rotated(Vector3.UP, -deg_to_rad(half_deg))
	_ribbon(c, c + left * r, 0.025, col)
	_ribbon(c, c + right * r, 0.025, col)
	for k in SEGS:
		var a := right.rotated(Vector3.UP, deg_to_rad(2.0 * half_deg * k / SEGS))
		var b := right.rotated(Vector3.UP, deg_to_rad(2.0 * half_deg * (k + 1) / SEGS))
		_ribbon(c + a * r, c + b * r, 0.025, col)


func _ground(n: Node3D) -> Vector3:
	var p := n.get_global_transform_interpolated().origin
	return Vector3(p.x, 0.05, p.z)


func _ribbon(a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var side := (b - a).cross(Vector3.UP).normalized() * w
	for v in [a - side, a + side, b + side, a - side, b + side, b - side]:
		_preview.surface_set_color(col)
		_preview.surface_add_vertex(v)


func _ring(c: Vector3, r: float, w: float, col: Color) -> void:
	const SEGS := 24
	for k in SEGS:
		var a0 := TAU * k / SEGS
		var a1 := TAU * (k + 1) / SEGS
		var i0 := c + Vector3(cos(a0), 0, sin(a0)) * (r - w)
		var o0 := c + Vector3(cos(a0), 0, sin(a0)) * (r + w)
		var i1 := c + Vector3(cos(a1), 0, sin(a1)) * (r - w)
		var o1 := c + Vector3(cos(a1), 0, sin(a1)) * (r + w)
		for v in [i0, o0, o1, i0, o1, i1]:
			_preview.surface_set_color(col)
			_preview.surface_add_vertex(v)


func _move(delta: float, wish: Vector3) -> void:
	# A plain swing never touches movement: wind-up, active and recovery all walk
	# like idle. Only a dodge, a chain and a held charge override it.
	var target := wish * move_speed * Stance.move_mult(ss.stance)
	if sneaking:
		target *= sneak_move_mult
	var dashing := cs.state == CombatState.DODGE or chaining()
	if cs.state == CombatState.DODGE:
		target = dodge_dir * (dodge_distance / maxf(dodge_time, 0.01))
	elif chaining():
		target = _chain_vel
	elif cs.charging():
		target = wish * move_speed * charge_move_mult
	elif cs.state == CombatState.STAGGER:
		target = Vector3.ZERO

	target *= Hazard.speed_mult(get_tree().get_nodes_in_group("hazards"), global_position)

	# A live shove owns horizontal velocity outright, so steering cannot walk
	# straight back through it.
	if _knock.length() > 0.2:
		velocity.x = _knock.x
		velocity.z = _knock.z
		_knock *= exp(-knock_friction * delta)
	elif dashing:
		_knock = Vector3.ZERO
		velocity.x = target.x
		velocity.z = target.z
	else:
		_knock = Vector3.ZERO
		velocity.x = move_toward(velocity.x, target.x, ground_accel * delta)
		velocity.z = move_toward(velocity.z, target.z, ground_accel * delta)
	# A chain dash crosses gaps: it is a lunge, not a fall.
	velocity.y = 0.0 if chaining() else velocity.y - gravity * delta
	move_and_slide()
	# Off the edge of the world.
	if global_position.y < -4.0:
		env_kill("fall")
