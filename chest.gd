extends Node3D
# A chest holding one hotbar slot's weapon: Route 1's bow, in the nook before the
# mud. Walk up and press E (or attack) to open it. The lid swings up, the bow
# rises out, and the slot unlocks.
#
# Opening is remembered through a death's reload, because it's just
# player.unlocked, which route.gd keeps until the run ends.
# ponytail: graybox boxes for the chest. Swap in a real model (e.g. the KayKit
# Dungeon chest) in the art pass; the lid is the only moving part.

const Player := preload("res://player.gd")
const BowModel := preload("res://assets/kaykit/weapons/bow_withString.gltf")

## The hotbar slot this chest unlocks.
@export var gives := "shot"
@export var radius := 1.8
@export var message := "Found the bow. Press 2 to use it."

var opened := false
var _lid: Node3D
var _prompt: Label3D


func _ready() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.29, 0.18)
	var band := StandardMaterial3D.new()
	band.albedo_color = Color(0.55, 0.5, 0.38)
	_box(self, Vector3(1.1, 0.55, 0.7), Vector3(0, 0.275, 0), wood)
	_box(self, Vector3(1.14, 0.1, 0.74), Vector3(0, 0.45, 0), band)
	# The lid hinges on its back edge (+z is the back: the chest faces -z).
	_lid = Node3D.new()
	_lid.position = Vector3(0, 0.55, 0.35)
	add_child(_lid)
	_box(_lid, Vector3(1.1, 0.22, 0.7), Vector3(0, 0.11, -0.35), wood)
	_box(_lid, Vector3(0.16, 0.14, 0.06), Vector3(0, 0.02, -0.72), band)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.1, 0.8, 0.7)
	cs.shape = shape
	cs.position.y = 0.4
	body.add_child(cs)
	add_child(body)
	_prompt = Label3D.new()
	_prompt.text = "E: open"
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.font_size = 40
	_prompt.outline_size = 10
	_prompt.pixel_size = 0.01
	_prompt.position.y = 1.4
	_prompt.visible = false
	add_child(_prompt)
	if Player.unlocked.get(gives, false):
		opened = true
		_lid.rotation.x = deg_to_rad(100)


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _near() -> Node3D:
	for p in get_tree().get_nodes_in_group("player"):
		var d := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z)
		if d.length() <= radius and not p.cs.dead():
			return p
	return null


func _process(_delta: float) -> void:
	_prompt.visible = not opened and _near() != null


func _unhandled_input(event: InputEvent) -> void:
	if opened:
		return
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_E) \
		or event.is_action_pressed("attack")
	if pressed and _near() != null:
		open()
		get_viewport().set_input_as_handled()


func open() -> void:
	if opened:
		return
	opened = true
	Player.unlocked[gives] = true
	Metrics.log_event("item_found", {"slot": gives})
	var tw := create_tween()
	tw.tween_property(_lid, "rotation:x", deg_to_rad(100), 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	# The bow rises out, turns once and fades.
	var bow: Node3D = BowModel.instantiate()
	bow.position = Vector3(0, 0.5, 0)
	bow.scale = Vector3.ONE * 1.6
	add_child(bow)
	var rise := create_tween().set_parallel()
	rise.tween_property(bow, "position:y", 1.9, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	rise.tween_property(bow, "rotation:y", TAU, 0.9)
	rise.chain().tween_interval(0.5)
	rise.chain().tween_callback(bow.queue_free)
	var note := Label3D.new()
	note.text = message
	note.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	note.font_size = 44
	note.outline_size = 12
	note.pixel_size = 0.01
	note.modulate = Color(1.0, 0.92, 0.6)
	note.position.y = 2.6
	add_child(note)
	var fade := create_tween()
	fade.tween_interval(2.5)
	fade.tween_property(note, "modulate:a", 0.0, 0.8)
	fade.tween_callback(note.queue_free)
