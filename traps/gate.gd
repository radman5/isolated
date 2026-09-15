extends Node3D
# A portcullis on a lever. Shoot the lever (or cut it with the sword) to drop or
# raise the gate: split a group, or shut one in.
#
# ponytail: closing on top of a body just lets physics shove it out. Crushing
# would need a swept check for one gate.

@export var width := 4.0
@export var height := 3.0
@export var closed := false
@export var shoot_radius := 0.7

var _gate := StaticBody3D.new()
var _lever := MeshInstance3D.new()
var _mesh: MeshInstance3D


func _ready() -> void:
	add_to_group("shootables")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, height, 0.4)
	shape.shape = box
	_gate.add_child(shape)
	_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	_mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.42, 0.45)
	_mesh.material_override = mat
	_gate.add_child(_mesh)
	_gate.position.y = _closed_y() if closed else _open_y()
	add_child(_gate)

	var lb := BoxMesh.new()
	lb.size = Vector3(0.3, 1.2, 0.3)
	_lever.mesh = lb
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(0.85, 0.7, 0.2)
	_lever.material_override = lm
	_lever.position = Vector3(width * 0.5 + 1.2, 0.8, 0)
	add_child(_lever)


func _closed_y() -> float:
	return height * 0.5


func _open_y() -> float:
	return height * 1.6  # lifted clear overhead


func shoot_position() -> Vector3:
	return _lever.global_position


func shot() -> void:
	closed = not closed
	Metrics.log_event("gate_toggled", {"closed": closed})
	var tw := create_tween()
	tw.tween_property(_gate, "position:y", _closed_y() if closed else _open_y(), 0.35)
