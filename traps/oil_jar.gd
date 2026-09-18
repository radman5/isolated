extends Node3D
# Shoot the jar: it bursts and leaves a slick. The slick slows anything in it and
# is flammable - a lantern landing on it turns it into fire (see lantern.gd).

const Zone := preload("res://traps/hazard_zone.gd")

@export var slick_radius := 3.5
@export var slow_mult := 0.55
@export var shoot_radius := 0.7

var _jar: MeshInstance3D
var _spent := false


func _ready() -> void:
	add_to_group("shootables")
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.35
	s.height = 0.8
	m.mesh = s
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.2, 0.12)
	m.material_override = mat
	m.position.y = 0.9
	_jar = m
	add_child(m)
	var plinth := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.6, 0.5, 0.6)
	plinth.mesh = b
	plinth.position.y = 0.25
	add_child(plinth)


func shoot_position() -> Vector3:
	return _jar.global_position


func shot() -> void:
	if _spent:
		return
	_spent = true
	_jar.hide()
	var oil := Zone.new()
	oil.kind = "slow"
	oil.radius = slick_radius
	oil.amount = slow_mult
	oil.flammable = true
	oil.colour = Color(0.05, 0.05, 0.07, 0.9)
	get_parent().add_child(oil)
	oil.global_position = Vector3(global_position.x, 0.0, global_position.z)
	Metrics.log_event("oil_spilled", {"radius": slick_radius})
