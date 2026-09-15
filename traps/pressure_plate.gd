extends Node3D
# A plate that arms its linked zones when anything stands on it: a spike floor,
# a wall of flame. Warn, fire, cool down - the warning is what makes stepping on
# it a decision rather than a gotcha.
#
# Anything steps on it, you included; standing on the plate to lure an enemy onto
# the spikes is the intended play.

const Hazard := preload("res://traps/hazard.gd")

## Zones (hazard_zone.gd) this plate fires. They start inactive.
@export var zones: Array[NodePath] = []
@export var radius := 1.1
@export var tell := 0.4
@export var active_time := 1.0
@export var cooldown := 3.0

var _state := "ready"  # ready -> tell -> firing -> cooling
var _t := 0.0
var _mesh := MeshInstance3D.new()


func _ready() -> void:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = 0.08
	_mesh.mesh = c
	_mesh.material_override = _mat(Color(0.5, 0.5, 0.55))
	_mesh.position.y = 0.05
	add_child(_mesh)
	for z in _zones():
		z.set_active(false)


func _physics_process(delta: float) -> void:
	_t += delta
	match _state:
		"ready":
			if _stepped_on():
				_go("tell")
				Metrics.log_event("plate_triggered", {"name": name})
			return
		"tell":
			# Flash while it winds up: the tell is the whole fairness of it.
			_mesh.material_override.albedo_color = Color(1.0, 0.8, 0.2) if int(_t * 12.0) % 2 == 0 else Color(0.5, 0.5, 0.55)
			if _t >= tell:
				_go("firing")
				for z in _zones():
					z.set_active(true)
		"firing":
			if _t >= active_time:
				_go("cooling")
				for z in _zones():
					z.set_active(false)
		"cooling":
			if _t >= cooldown:
				_go("ready")


func _go(s: String) -> void:
	_state = s
	_t = 0.0
	_mesh.material_override.albedo_color = Color(0.5, 0.5, 0.55) if s != "firing" else Color(0.8, 0.3, 0.2)


func _stepped_on() -> bool:
	var s := {"pos": global_position, "radius": radius}
	for a in get_tree().get_nodes_in_group("enemies") + [get_tree().get_first_node_in_group("player")]:
		if a and not a.cs.dead() and Hazard.inside(s, a.global_position):
			return true
	return false


func _zones() -> Array:
	var out := []
	for p in zones:
		var n := get_node_or_null(p)
		if n:
			out.append(n)
	return out


func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	return m
