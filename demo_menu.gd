extends CanvasLayer
# Start menu: Start loads Route 1; Demo Scenes (bottom-right) lists every scene in res://demos/.
# Backspace toggles it from any scene. A new demo is just a .tscn dropped in that folder.

const DIR := "res://demos/"
const START_SCENE := "res://demos/route1.tscn"

## True when the scene was opened by Start: scenes then drop their debug text.
var playing := false
var _start: Button
var _list: PanelContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.07)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.grow_vertical = Control.GROW_DIRECTION_BOTH
	center.add_theme_constant_override("separation", 32)
	add_child(center)
	var title := Label.new()
	title.text = "Isolated"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	center.add_child(title)
	_start = Button.new()
	_start.text = "Start"
	_start.custom_minimum_size = Vector2(260, 64)
	_start.add_theme_font_size_override("font_size", 28)
	_start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_start.pressed.connect(func():
		_open(START_SCENE)
		playing = true)
	center.add_child(_start)

	var demos := Button.new()
	demos.text = "Demo Scenes"
	demos.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	demos.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	demos.grow_vertical = Control.GROW_DIRECTION_BEGIN
	demos.pressed.connect(func(): _list.visible = not _list.visible)
	add_child(demos)

	_list = PanelContainer.new()
	_list.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	_list.offset_top -= 48  # sit above the Demo Scenes button
	_list.offset_bottom -= 48
	_list.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_list.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_list)
	var box := VBoxContainer.new()
	_list.add_child(box)
	# list_directory, not DirAccess: exported builds only have .tscn.remap files on disk.
	for f in ResourceLoader.list_directory(DIR):
		if f.ends_with(".tscn"):
			var b := Button.new()
			b.text = f.get_basename().capitalize()
			b.pressed.connect(_open.bind(DIR + f))
			box.add_child(b)
	_show(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("demo_menu"):
		_show(not visible)


func _open(path: String) -> void:
	playing = false
	_show(false)
	get_tree().change_scene_to_file(path)


func _show(on: bool) -> void:
	visible = on
	get_tree().paused = on
	if on:
		_list.visible = false
		_start.grab_focus.call_deferred()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
