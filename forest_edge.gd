extends Node3D
# Draws the forest: a row of tree trunks along every wall box under this node,
# as one MultiMesh. The walls are the collision; the trunks are only the look.
# ponytail: grey cylinders in a jittered row. The art pass replaces the look.

@export var spacing := 1.5
@export var trunk_radius := 0.35


func _ready() -> void:
	var xforms: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for wall in get_children():
		if not (wall is StaticBody3D):
			continue
		var shape := (wall.get_child(0) as CollisionShape3D).shape as BoxShape3D
		var along_x := shape.size.x >= shape.size.z
		var length := maxf(shape.size.x, shape.size.z)
		var n := maxi(1, int(length / spacing))
		for i in n + 1:
			var t := -length * 0.5 + length * i / n
			var off := Vector3(t, 0, rng.randf_range(-0.3, 0.3)) if along_x else Vector3(rng.randf_range(-0.3, 0.3), 0, t)
			var h := rng.randf_range(5.0, 8.0)
			var at: Vector3 = wall.position + off
			xforms.append(Transform3D(Basis().scaled(Vector3(1, h, 1)), Vector3(at.x, h * 0.5, at.z)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var trunk := CylinderMesh.new()
	trunk.top_radius = trunk_radius * 0.7
	trunk.bottom_radius = trunk_radius
	trunk.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.27, 0.22, 0.17)
	trunk.material = mat
	mm.mesh = trunk
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	add_child(mi)
