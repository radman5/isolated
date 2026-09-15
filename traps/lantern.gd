extends Node3D
# A lit lantern on a rope. Shoot it and it falls: any oil under it catches, and
# that patch burns for burn_time. On bare ground it makes a small, brief fire, so
# the oil is what makes it worth the arrow.

const Hazard := preload("res://traps/hazard.gd")
const Zone := preload("res://traps/hazard_zone.gd")

@export var hang_height := 3.2
@export var burn_dps := 22.0
@export var burn_time := 8.0
@export var small_fire_radius := 1.5
@export var small_fire_time := 2.5
@export var shoot_radius := 0.6

var _lamp := MeshInstance3D.new()
var _spent := false


func _ready() -> void:
	add_to_group("shootables")
	var post := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(0.25, hang_height, 0.25)
	post.mesh = pb
	post.position = Vector3(1.2, hang_height * 0.5, 0)
	add_child(post)
	var arm := MeshInstance3D.new()
	var ab := BoxMesh.new()
	ab.size = Vector3(1.4, 0.2, 0.2)
	arm.mesh = ab
	arm.position = Vector3(0.5, hang_height, 0)
	add_child(arm)
	var lb := BoxMesh.new()
	lb.size = Vector3(0.4, 0.5, 0.4)
	_lamp.mesh = lb
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.75, 0.25)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.2)
	mat.emission_energy_multiplier = 2.0
	_lamp.material_override = mat
	_lamp.position.y = hang_height - 0.6
	add_child(_lamp)


func shoot_position() -> Vector3:
	return _lamp.global_position


func shot() -> void:
	if _spent:
		return
	_spent = true
	Metrics.log_event("lantern_dropped", {})
	var tw := create_tween()
	tw.tween_property(_lamp, "position:y", 0.2, 0.3).set_ease(Tween.EASE_IN)
	tw.tween_callback(_ignite)


func _ignite() -> void:
	_lamp.hide()
	var lit := 0
	for z in get_tree().get_nodes_in_group("hazards"):
		if z.flammable and z.active and Hazard.inside(z.shape(), global_position):
			lit += 1
			_fire(z.global_position, z.radius if z.radius > 0.0 else maxf(z.size.x, z.size.y) * 0.5, burn_time)
			z.set_active(false)  # the oil is consumed by the flames
	if lit == 0:
		_fire(global_position, small_fire_radius, small_fire_time)
	Metrics.log_event("fire_started", {"oil": lit > 0})


func _fire(at: Vector3, radius: float, secs: float) -> void:
	var fire := Zone.new()
	fire.kind = "burn"
	fire.radius = radius
	fire.amount = burn_dps
	fire.lifetime = secs
	fire.colour = Color(1.0, 0.45, 0.1, 0.75)
	get_parent().add_child(fire)
	fire.global_position = Vector3(at.x, 0.0, at.z)
