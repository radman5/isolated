extends Control
# The weapon hotbar at the bottom of the screen: four slots, 1 Sword, 2 Bow,
# 3 Volley, 4 Rain. It shows which is in hand, which are still locked (Route 1
# starts with only the sword), each skill's cooldown draining, and a red flash
# when you press a key you haven't unlocked. A view only: it reads the player
# and never changes anything.

@export var player_path := NodePath("../../Player")

const NAMES := {"sword": "Sword", "shot": "Bow", "volley": "Volley", "rain": "Rain"}
const SIZE := 72.0
const GAP := 8.0

var _p: Node
var _slots := {}  # slot -> {panel, style, name, lock, cool}


func _ready() -> void:
	_p = get_node_or_null(player_path)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	var width := SIZE * 4 + GAP * 3
	offset_left = -width * 0.5
	offset_right = width * 0.5
	offset_top = -SIZE - 16.0
	offset_bottom = -16.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var i := 0
	for slot in ["sword", "shot", "volley", "rain"]:
		var panel := Panel.new()
		panel.position = Vector2(i * (SIZE + GAP), 0)
		panel.size = Vector2(SIZE, SIZE)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.1, 0.09, 0.08, 0.72)
		style.set_border_width_all(2)
		style.border_color = Color(0.45, 0.42, 0.36, 0.8)
		style.set_corner_radius_all(6)
		panel.add_theme_stylebox_override("panel", style)
		add_child(panel)
		var cool := ColorRect.new()
		cool.color = Color(0, 0, 0, 0.55)
		cool.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(cool)
		var key := _label(str(i + 1), 13, Color(0.8, 0.76, 0.66))
		key.position = Vector2(6, 3)
		panel.add_child(key)
		var title := _label(NAMES[slot], 15, Color(0.95, 0.92, 0.84))
		title.position = Vector2(0, 26)
		title.size = Vector2(SIZE, 20)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(title)
		var lock := _label("locked", 11, Color(0.75, 0.7, 0.62))
		lock.position = Vector2(0, 48)
		lock.size = Vector2(SIZE, 16)
		lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(lock)
		_slots[slot] = {"panel": panel, "style": style, "name": title, "lock": lock, "cool": cool}
		i += 1


func _label(text: String, font_size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(_delta: float) -> void:
	if _p == null:
		return
	var current: String = _p.current_slot()
	var since := Time.get_ticks_msec() - int(_p.locked_press_ms)
	for slot in _slots:
		var s: Dictionary = _slots[slot]
		var have: bool = _p.has_slot(slot)
		var style: StyleBoxFlat = s.style
		s.lock.visible = not have
		s.panel.modulate = Color(1, 1, 1, 1.0 if have else 0.45)
		style.border_color = Color(1.0, 0.86, 0.45) if slot == current else Color(0.45, 0.42, 0.36, 0.8)
		style.set_border_width_all(3 if slot == current else 2)
		# A red pulse on the slot you just tried to pick while it's locked.
		if slot == _p.locked_press and since < 450:
			style.border_color = Color(0.95, 0.25, 0.2).lerp(style.border_color, since / 450.0)
			s.panel.modulate.a = 0.9
		# Cooldown: a dark fill draining upward.
		var left := 0.0
		var total := 1.0
		if slot == "volley":
			left = _p.volley_ready_in
			total = _p.volley_cooldown
		elif slot == "rain":
			left = _p.rain_ready_in
			total = maxf(_p.rain_cooldown_per_arrow * _p.rain_max_arrows, 0.01)
		var frac := clampf(left / maxf(total, 0.01), 0.0, 1.0)
		s.cool.position = Vector2(0, SIZE * (1.0 - frac))
		s.cool.size = Vector2(SIZE, SIZE * frac)
