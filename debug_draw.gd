extends Node3D
# Debug visualisation. It only observes: it reads player and enemy state plus
# the player's debug_event signal, and draws. Nothing in gameplay depends on it,
# so deleting the node leaves the game playing identically. F1 (or `) toggles.
#
# The fans are drawn from the same numbers the hit test uses. in_arc checks the
# target's CENTRE against reach and half-angle and ignores height, so a fan shows
# where a centre has to be, not where a capsule merely overlaps. The small cross
# under each actor marks that centre. A fan's outline turns green while the
# other actor's centre is inside it, meaning "this would connect right now".

const CombatState := preload("res://combat_state.gd")
const Stance := preload("res://stance_state.gd")

const GROUND_Y := 0.04
const SEGS := 20
const WHITE := Color(1, 1, 1)
const GREY := Color(0.72, 0.76, 0.8)
const YELLOW := Color(1.0, 0.78, 0.1)
const RED := Color(1.0, 0.22, 0.15)
const CYAN := Color(0.3, 0.9, 1.0)
const MAGENTA := Color(1.0, 0.3, 0.9)
const GREEN := Color(0.35, 1.0, 0.45)

@export var linger := 0.3  # the active window is ~6 frames, too short to read unaided
@export var popup_life := 1.1
@export var tracer_life := 0.7

# Survives the scene reload after every fight.
static var shown := true

var _im := ImmediateMesh.new()
var _tris: Array = []  # vertex, colour, vertex, colour...
var _lines: Array = []
var _p: Node
var _p_label := Label3D.new()
var _e_labels := {}  # instance id -> Label3D
var _popups: Array = []
var _tracers: Array = []
var _p_ghost := {}
var _e_ghosts := {}  # instance id -> ghost
var _swing := {}


func _ready() -> void:
	# Everything here is placed in _process at interpolated positions. Letting
	# the engine interpolate these transforms again would smear the labels.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var mi := MeshInstance3D.new()
	mi.mesh = _im
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	mi.material_override = m
	add_child(mi)
	_style(_p_label, 28)
	add_child(_p_label)
	_p = get_node_or_null("../Player")
	if _p and _p.has_signal("debug_event"):
		_p.debug_event.connect(_on_event)
	visible = shown


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_F1 or event.physical_keycode == KEY_QUOTELEFT:
		shown = not shown
		visible = shown


func _process(delta: float) -> void:
	_tris.clear()
	_lines.clear()
	if _p:
		_draw_player(delta)
	for e in _enemies():
		_draw_enemy(e, delta)
	_draw_tracers(delta)
	_tick_popups(delta)
	_flush()


# --- player ------------------------------------------------------------------

func _draw_player(delta: float) -> void:
	var cs = _p.cs
	var ss = _p.ss
	var pos := _ipos(_p)
	var target: Array = _enemies().filter(func(e): return not e.cs.dead()).map(
		func(e): return _ipos(e)
	)
	_cross(pos, GREY)
	_rings(pos, cs, ss)

	match cs.state:
		CombatState.WINDUP:
			if cs.charging():
				# Where the charged strike will go if released now, and how wide.
				var dir: Vector3 = _p.charge_aim_dir()
				var cyaw := atan2(-dir.x, -dir.z)
				var lvl: float = _p.charge_level_now()
				_swing_fan(pos, cyaw, _p.preview_arc(), _p.attack_reach, YELLOW, 0.12 + 0.35 * lvl, target)
				_line(_flat(pos), _flat(pos) + dir.normalized() * _p.attack_reach * 1.6, WHITE)
				if _p.cone_deg < 179.0:
					_cone_edges(pos, _p.rotation.y, _p.cone_deg, _p.attack_reach * 1.35, GREY)
			else:
				var k: float = cs.t / maxf(cs.windup_time, 0.001)
				_swing_fan(pos, _p.strike_yaw, _p.swing_arc(), _p.attack_reach, YELLOW, 0.08 + 0.25 * k, target)
		CombatState.ACTIVE:
			_p_ghost = {"pos": pos, "yaw": _p.strike_yaw, "arc": _p.swing_arc(), "reach": _p.attack_reach, "age": 0.0}
			_swing_fan(pos, _p.strike_yaw, _p.swing_arc(), _p.attack_reach, RED, 0.45, target)
			_requested_line(pos)
		_:
			if _p.weapon == Stance.SWORD and ss.stance == Stance.NONE and cs.state == CombatState.IDLE:
				# What a click would hit right now.
				_swing_fan(pos, _p.rotation.y, _p.attack_arc, _p.attack_reach, GREY, 0.05, target, 0.5)
			elif ss.stance == Stance.BOW:
				var dir: Vector3 = _p.bow_aim()
				var length: float = _p.bow_length(_p.g.drag_strength())
				var yaw := atan2(-dir.x, -dir.z)
				_swing_fan(pos, yaw, _p.bow_arc, length, GREY, 0.10, target)
				_line(_flat(pos), _flat(pos) + dir.normalized() * length, WHITE)
	if cs.state != CombatState.ACTIVE:
		_ghost(_p_ghost, delta)

	_p_label.position = pos + Vector3(0, 1.35, 0) - _cam_right() * 0.7
	_p_label.modulate = _state_colour(cs.state)
	var head: String = (Stance.NAMES[_p.weapon] if ss.stance == Stance.NONE else ss.name_of()).to_upper()
	var extra := ""
	if cs.charging():
		extra = "  CHARGE %.0f%%" % (_p.charge_level_now() * 100.0)
	elif ss.stance == Stance.BOW:
		extra = "  draw %.0f%%" % (_p.g.drag_strength() * 100.0)
	var flags := ""
	if cs.invulnerable():
		flags += "  IFRAMES"
	if ss.parry_armed():
		flags += "  PARRY"
	if ss.has_buffer():
		flags += "  BUFFERED"
	_p_label.text = "%s · %s%s\nchain %d/%d  landed %d%s\nhp %.0f  st %.0f%s" % [
		head, cs.state_name(), _timer(cs), ss.chain, ss.chain_cap, _p.chain_hits,
		extra, cs.health, cs.stamina, flags,
	]


func _requested_line(pos: Vector3) -> void:
	if _swing.get("clamped", false):
		# Where the flick asked to go, before the cone clamped it.
		var c := _flat(pos)
		_line(c, c + _dir(_swing.requested_yaw) * _p.attack_reach * 1.35, Color(WHITE, 0.6))


# --- enemy -------------------------------------------------------------------

func _draw_enemy(e: Node, delta: float) -> void:
	var cs = e.cs
	var id := e.get_instance_id()
	var pos := _ipos(e)
	var target: Array = [_ipos(_p)] if _p else []
	var yaw: float = e.rotation.y
	_cross(pos, GREY)
	_rings(pos, cs, null)
	# Where it likes to stand. Just outside your reach is what makes you step in.
	_circle(pos, e.standoff, Color(GREY, 0.25))

	match cs.state:
		CombatState.WINDUP:
			var k: float = cs.t / maxf(cs.windup_time, 0.001)
			_swing_fan(pos, yaw, e.attack_arc, e.attack_range, YELLOW, 0.10 + 0.30 * k, target)
		CombatState.ACTIVE:
			_e_ghosts[id] = {"pos": pos, "yaw": yaw, "arc": e.attack_arc, "reach": e.attack_range, "age": 0.0}
			_swing_fan(pos, yaw, e.attack_arc, e.attack_range, RED, 0.5, target)
		_:
			if not cs.dead():
				_swing_fan(pos, yaw, e.attack_arc, e.attack_range, GREY, 0.0, target, 0.35)
	if cs.state != CombatState.ACTIVE and _e_ghosts.has(id):
		_ghost(_e_ghosts[id], delta)

	if not _e_labels.has(id):
		var l := Label3D.new()
		_style(l, 26)
		add_child(l)
		_e_labels[id] = l
	var label: Label3D = _e_labels[id]
	label.position = pos + Vector3(0, 1.35, 0) + _cam_right() * 0.7
	label.modulate = _state_colour(cs.state)
	var punish := ""
	if cs.state == CombatState.RECOVERY or cs.state == CombatState.STAGGER:
		punish = "\n>> PUNISH <<"
	label.text = "%s · %s%s\nhp %.0f  st %.0f%s" % [
		e.name, "dead" if cs.dead() else cs.state_name(), _timer(cs), cs.health, cs.stamina, punish,
	]


# --- events ------------------------------------------------------------------

func _on_event(kind: String, d: Dictionary) -> void:
	match kind:
		"swing":
			_swing = d
			if d.clamped:
				_popup(_p.global_position, "CLAMPED  asked %+.0f°" % d.requested_deg, GREY, -1)
			if d.cancelled:
				_popup(_p.global_position, "CANCEL", CYAN, -1)
		"dealt":
			var e = d.get("target")
			if e == null or not is_instance_valid(e):
				return
			var txt := "-%.0f" % d.dmg
			if d.source == "sword":
				txt += "   hit %d/%d" % [d.chain, d.cap]
				if d.finisher:
					txt += "  FINISHER"
				if d.charge > 0.01:
					txt += "\ncharge %.2f" % d.charge
			else:
				txt += "   arrow"
			# The trade rule, made visible: a committed target does not flinch.
			var staggered: bool = e.cs.state == CombatState.STAGGER
			if staggered:
				txt += "\nSTAGGER %.2fs  knock %.1fm" % [d.stagger, d.knock]
			elif e.cs.dead():
				txt += "\nKILL  knock %.1fm" % d.knock
			else:
				txt += "\nno stagger (committed)"
			_popup(e.global_position, txt, RED if staggered or e.cs.dead() else YELLOW, 1)
		"taken":
			var lost := "-%.0f" % d.lost
			var text: String = {
				"hit": lost, "blocked": "BLOCK " + lost, "broken": "GUARD BREAK " + lost,
				"parried": "PARRY", "dodged": "DODGED",
			}.get(d.result, d.result)
			var col: Color = {
				"hit": RED, "blocked": GREY, "broken": MAGENTA, "parried": WHITE, "dodged": CYAN,
			}.get(d.result, WHITE)
			_popup(_p.global_position, text, col, -1)
		"shot":
			var t := d.duplicate()
			t["age"] = 0.0
			_tracers.append(t)
			_popup(
				_p.global_position,
				"ARROW %.0f%%  %s" % [d.strength * 100.0, "HIT" if d.hit else "miss"],
				GREEN if d.hit else GREY,
				-1
			)


func _draw_tracers(delta: float) -> void:
	for t in _tracers:
		t.age += delta
		var a: float = clampf(1.0 - t.age / tracer_life, 0.0, 1.0)
		var col: Color = GREEN if t.hit else RED
		var from: Vector3 = _flat(t.from)
		var dir: Vector3 = t.dir.normalized()
		_fan(from, atan2(-dir.x, -dir.z), t.arc, t.len, Color(col, 0.12 * a), Color(col, a))
		# Hitscan, so the arrowhead is only there to make "it fired" readable.
		var head: Vector3 = from + dir * t.len * clampf(t.age / 0.12, 0.0, 1.0)
		_line(from, head, Color(WHITE, a))
		_cross(head, Color(WHITE, a), 0.25)
	_tracers = _tracers.filter(func(x): return x.age < tracer_life)


# side: -1 floats out to screen-left (player), +1 to screen-right (enemy), so
# popups never sit on top of the state labels above the heads.
func _popup(at: Vector3, text: String, col: Color, side: int) -> void:
	var l := Label3D.new()
	_style(l, 30)
	l.text = text
	l.modulate = col
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if side < 0 else HORIZONTAL_ALIGNMENT_LEFT
	add_child(l)
	var stacked := _popups.filter(func(x): return x.side == side).size()
	l.position = at + _cam_right() * 1.1 * side + Vector3(0, 0.2 + 0.55 * stacked, 0)
	_popups.append({"l": l, "age": 0.0, "side": side})


func _tick_popups(delta: float) -> void:
	var keep: Array = []
	for p in _popups:
		p.age += delta
		if p.age >= popup_life:
			p.l.queue_free()
			continue
		p.l.position.y += delta * 0.9
		var a: float = 1.0 - p.age / popup_life
		p.l.modulate.a = a
		p.l.outline_modulate.a = 0.9 * a
		keep.append(p)
	_popups = keep


# --- drawing helpers ---------------------------------------------------------

func _swing_fan(
	center: Vector3, yaw: float, half_deg: float, reach: float, col: Color,
	fill_alpha: float, targets: Array, line_alpha := 1.0
) -> void:
	var connects := targets.any(
		func(t): return CombatState.in_arc(center, _dir(yaw), t, reach, half_deg)
	)
	var line := Color(GREEN if connects else col, line_alpha)
	_fan(center, yaw, half_deg, reach, Color(col, fill_alpha), line)


func _ghost(g: Dictionary, delta: float) -> void:
	if g.is_empty():
		return
	g.age += delta
	var a: float = 1.0 - g.age / linger
	if a <= 0.0:
		g.clear()
		return
	_fan(g.pos, g.yaw, g.arc, g.reach, Color(RED, 0.3 * a), Color(RED, a))


func _rings(pos: Vector3, cs, ss) -> void:
	if cs.invulnerable():
		_circle(pos, 0.75, CYAN)
	if cs.state == CombatState.STAGGER:
		_circle(pos, 0.85, MAGENTA)
		_circle(pos, 0.9, MAGENTA)
	if ss != null and ss.stance == Stance.BLOCK:
		_circle(pos, 0.65, GREY)
	if ss != null and ss.parry_armed():
		_circle(pos, 1.0, WHITE)


func _timer(cs) -> String:
	var dur := 0.0
	match cs.state:
		CombatState.WINDUP:
			dur = cs.windup_time
		CombatState.ACTIVE:
			dur = cs.active_time
		CombatState.RECOVERY:
			dur = cs.recovery_time
		CombatState.DODGE:
			dur = cs.dodge_time
		CombatState.STAGGER:
			dur = cs.stagger_time
	return " %.2f/%.2f" % [cs.t, dur] if dur > 0.0 else ""


func _state_colour(state: int) -> Color:
	match state:
		CombatState.WINDUP:
			return YELLOW
		CombatState.ACTIVE:
			return RED
		CombatState.RECOVERY:
			return GREY
		CombatState.DODGE:
			return CYAN
		CombatState.STAGGER:
			return MAGENTA
	return WHITE


func _style(l: Label3D, size: int) -> void:
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.pixel_size = 0.011
	l.font_size = size
	l.outline_size = 10
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	l.render_priority = 10
	l.outline_render_priority = 9


# Where a body is drawn this frame. Its global_position is only exact on physics
# ticks; between them the renderer shows an interpolated one.
func _ipos(n: Node3D) -> Vector3:
	return n.get_global_transform_interpolated().origin


func _enemies() -> Array:
	return get_tree().get_nodes_in_group("enemies").filter(
		func(e): return not e.is_queued_for_deletion()
	)


func _cam_right() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	return cam.global_transform.basis.x if cam else Vector3.RIGHT


func _dir(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func _flat(p: Vector3) -> Vector3:
	return Vector3(p.x, GROUND_Y, p.z)


func _fan(center: Vector3, yaw: float, half_deg: float, reach: float, fill: Color, line: Color) -> void:
	var c := _flat(center)
	var h := deg_to_rad(half_deg)
	var prev := c + _dir(yaw - h) * reach
	_line(c, prev, line)
	for i in range(1, SEGS + 1):
		var pt := c + _dir(yaw - h + 2.0 * h * float(i) / SEGS) * reach
		if fill.a > 0.0:
			_tris.append_array([c, fill, prev, fill, pt, fill])
		_line(prev, pt, line)
		prev = pt
	_line(c, prev, line)


func _cone_edges(center: Vector3, yaw: float, half_deg: float, length: float, col: Color) -> void:
	var c := _flat(center)
	var h := deg_to_rad(half_deg)
	_line(c, c + _dir(yaw - h) * length, Color(col, 0.5))
	_line(c, c + _dir(yaw + h) * length, Color(col, 0.5))


func _circle(center: Vector3, r: float, col: Color) -> void:
	var c := _flat(center)
	var prev := c + Vector3(r, 0, 0)
	for i in range(1, 33):
		var a := TAU * float(i) / 32.0
		var pt := c + Vector3(cos(a) * r, 0, sin(a) * r)
		_line(prev, pt, col)
		prev = pt


func _cross(center: Vector3, col: Color, size := 0.18) -> void:
	var c := _flat(center)
	_line(c - Vector3(size, 0, 0), c + Vector3(size, 0, 0), col)
	_line(c - Vector3(0, 0, size), c + Vector3(0, 0, size), col)


func _line(a: Vector3, b: Vector3, col: Color) -> void:
	_lines.append_array([a, col, b, col])


func _flush() -> void:
	_im.clear_surfaces()
	_emit(Mesh.PRIMITIVE_TRIANGLES, _tris)
	_emit(Mesh.PRIMITIVE_LINES, _lines)


func _emit(prim: int, data: Array) -> void:
	if data.is_empty():
		return
	_im.surface_begin(prim)
	for i in range(0, data.size(), 2):
		_im.surface_set_color(data[i + 1])
		_im.surface_add_vertex(data[i])
	_im.surface_end()
