extends Node3D
# Stage 4 hazard: a trap door held shut by a rope. Shoot the rope and the door
# drops for open_time; anything standing on it, or walking onto it while open,
# falls and dies, armour or not. One use per fight (the scene reloads after).
#
# Built in code rather than as a .tscn: it is four boxes and a cylinder, and
# sizes stay in one place.
#
# The rope is a "shootable": player.gd's arrows find it through that group and
# call shot() when the flying arrow reaches it.

@export var size := Vector2(3.0, 3.0)
## Where the rope's post stands, relative to the door's centre.
@export var post_offset := Vector3(2.4, 0.0, 0.0)
@export var open_time := 2.0
## How close to the rope an arrow's line must pass, metres.
@export var shoot_radius := 0.45

var _door_pivot := Node3D.new()
var _rope := MeshInstance3D.new()
var _area := Area3D.new()
var _open := false
var _spent := false


func _ready() -> void:
	add_to_group("shootables")
	var pit := _box(Vector3(size.x, 0.02, size.y), Color(0.02, 0.02, 0.03))
	pit.position.y = 0.01
	add_child(pit)

	# Hinged along the edge away from the post, so it swings down out of the way.
	_door_pivot.position = Vector3(-size.x * 0.5, 0.06, 0.0)
	add_child(_door_pivot)
	var door := _box(Vector3(size.x, 0.08, size.y), Color(0.42, 0.3, 0.18))
	door.position.x = size.x * 0.5
	_door_pivot.add_child(door)

	var post := _box(Vector3(0.3, 3.2, 0.3), Color(0.35, 0.26, 0.16))
	post.position = post_offset + Vector3(0, 1.6, 0)
	add_child(post)

	# Rope from the post top down to the door's near edge.
	var top := post_offset + Vector3(-0.15, 3.0, 0)
	var bottom := Vector3(size.x * 0.5, 0.1, 0)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.05
	cyl.height = top.distance_to(bottom)
	_rope.mesh = cyl
	_rope.material_override = _mat(Color(0.85, 0.75, 0.45))
	_rope.position = (top + bottom) * 0.5
	_rope.basis = Basis(Quaternion(Vector3.UP, (top - bottom).normalized()))
	add_child(_rope)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, 2.0, size.y)
	shape.shape = box
	shape.position.y = 1.0
	_area.add_child(shape)
	add_child(_area)
	_area.body_entered.connect(_on_body_entered)


# Where arrows aim for: the rope's middle, on the ground plane.
func shoot_position() -> Vector3:
	return _rope.global_position


func shot() -> void:
	if _spent:
		return
	_spent = true
	_rope.hide()
	Metrics.log_event("trap_triggered", {})
	var tw := create_tween()
	tw.tween_property(_door_pivot, "rotation:z", deg_to_rad(-95.0), 0.18)
	tw.tween_callback(_set_open.bind(true))
	tw.tween_interval(open_time)
	tw.tween_property(_door_pivot, "rotation:z", 0.0, 0.4)
	tw.tween_callback(_set_open.bind(false))


func _set_open(on: bool) -> void:
	_open = on
	if on:
		for b in _area.get_overlapping_bodies():
			_on_body_entered(b)


func _on_body_entered(b: Node3D) -> void:
	if _open and b.has_method("fall"):
		b.fall()


func _box(s: Vector3, col: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	m.mesh = bm
	m.material_override = _mat(col)
	return m


func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	return m
