extends Node3D
# A block hung from a beam. Cut the rope and it drops on the circle below,
# crushing whatever stands there. One use.

const Enemy := preload("res://enemy.gd")
const Hazard := preload("res://traps/hazard.gd")

## Sleeping enemies this close wake when it goes off.
@export var noise_radius := 14.0
@export var drop_radius := 1.6
@export var hang_height := 5.0
@export var shoot_radius := 0.6

var _weight: MeshInstance3D
var _rope := MeshInstance3D.new()
var _spent := false


func _ready() -> void:
	add_to_group("shootables")
	var post_l := _box(Vector3(0.3, hang_height, 0.3), Color(0.35, 0.26, 0.16))
	post_l.position = Vector3(-drop_radius - 0.4, hang_height * 0.5, 0)
	add_child(post_l)
	var post_r := _box(Vector3(0.3, hang_height, 0.3), Color(0.35, 0.26, 0.16))
	post_r.position = Vector3(drop_radius + 0.4, hang_height * 0.5, 0)
	add_child(post_r)
	var beam := _box(Vector3(2.0 * drop_radius + 1.1, 0.3, 0.3), Color(0.35, 0.26, 0.16))
	beam.position.y = hang_height
	add_child(beam)

	# The rope hangs at the post, NOT over the drop circle: with it in the middle,
	# the enemy you are baiting stands between you and your own trigger.
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.06
	cyl.height = 1.6
	_rope.mesh = cyl
	_rope.material_override = _mat(Color(0.85, 0.75, 0.45))
	_rope.position = Vector3(drop_radius + 0.4, hang_height - 0.9, 0)
	add_child(_rope)

	_weight = _box(Vector3(2.0, 1.4, 2.0), Color(0.3, 0.32, 0.35))
	_weight.position.y = hang_height - 2.4
	add_child(_weight)

	# Where it will land, so the threat is readable before it falls.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = drop_radius - 0.12
	torus.outer_radius = drop_radius
	ring.mesh = torus
	ring.material_override = _mat(Color(0.9, 0.3, 0.2, 0.7), true)
	ring.position.y = 0.04
	add_child(ring)


func shoot_position() -> Vector3:
	return _rope.global_position


func shot() -> void:
	if _spent:
		return
	_spent = true
	_rope.hide()
	Metrics.log_event("weight_dropped", {})
	Enemy.noise(get_tree(), global_position, noise_radius)
	var tw := create_tween()
	tw.tween_property(_weight, "position:y", 0.7, 0.35).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(_crush)


func _crush() -> void:
	var s := {"pos": global_position, "radius": drop_radius}
	for a in get_tree().get_nodes_in_group("enemies") + [get_tree().get_first_node_in_group("player")]:
		if a and not a.cs.dead() and Hazard.inside(s, a.global_position):
			a.env_kill("crush")


func _box(s: Vector3, col: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = s
	m.mesh = b
	m.material_override = _mat(col)
	return m


func _mat(col: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m
