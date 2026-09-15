extends Node3D
# One patch of dangerous ground: mud that slows, oil that slows and burns, fire
# that damages, spikes that kill. Every area trap in the scene is one of these,
# switched on by whatever triggers it.
#
# It draws its own flat marker and applies its effect itself, to the player and
# every enemy standing in it. Damage and death here ignore armour, blocking and
# i-frames: §4's hazard is meant to beat what the sword cannot.

const Hazard := preload("res://traps/hazard.gd")

@export_enum("slow", "burn", "kill") var kind := "slow"
## Zero for a box zone; above zero makes it a circle.
@export var radius := 0.0
@export var size := Vector2(4.0, 4.0)
## Slow: movement multiplier. Burn: damage per second. Kill: unused.
@export var amount := 0.5
@export var active := true
## Seconds before it switches itself off. 0 = forever.
@export var lifetime := 0.0
## Oil: a burn zone is lit here when a lantern lands on it.
@export var flammable := false
@export var colour := Color(0.35, 0.26, 0.15, 0.9)

var _mesh := MeshInstance3D.new()
var _age := 0.0


func _ready() -> void:
	add_to_group("hazards")
	var m := MeshInstance3D.new()
	if radius > 0.0:
		var c := CylinderMesh.new()
		c.top_radius = radius
		c.bottom_radius = radius
		c.height = 0.02
		m.mesh = c
	else:
		var b := BoxMesh.new()
		b.size = Vector3(size.x, 0.02, size.y)
		m.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material_override = mat
	m.position.y = 0.03
	_mesh = m
	add_child(m)
	_mesh.visible = active


func kind_id() -> int:
	match kind:
		"burn":
			return Hazard.BURN
		"kill":
			return Hazard.KILL
	return Hazard.SLOW


func shape() -> Dictionary:
	if radius > 0.0:
		return {"pos": global_position, "radius": radius}
	return {"pos": global_position, "size": size, "yaw": global_rotation.y}


func set_active(on: bool) -> void:
	active = on
	_age = 0.0
	_mesh.visible = on


func _physics_process(delta: float) -> void:
	if not active:
		return
	if lifetime > 0.0:
		_age += delta
		if _age >= lifetime:
			set_active(false)
			return
	if kind_id() == Hazard.SLOW:
		return  # pulled by the actors themselves, in their own movement code
	var s := shape()
	for a in _actors():
		if a.cs.dead() or not Hazard.inside(s, a.global_position):
			continue
		if kind_id() == Hazard.KILL:
			a.env_kill("spikes")
		else:
			a.env_damage(amount * delta)


func _actors() -> Array:
	var out := get_tree().get_nodes_in_group("enemies").duplicate()
	var p := get_tree().get_first_node_in_group("player")
	if p:
		out.append(p)
	return out
