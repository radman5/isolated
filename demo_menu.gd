extends CanvasLayer
# Start menu listing every scene in res://demos/. Backspace toggles it from any demo.
# A new demo is just a .tscn dropped in that folder.

const DIR := "res://demos/"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "Demos  (Backspace: this menu)"
	box.add_child(title)
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
	_show(false)
	get_tree().change_scene_to_file(path)


func _show(on: bool) -> void:
	visible = on
	get_tree().paused = on
	if on:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
