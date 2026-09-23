extends Node3D
# A stealth stretch: the ground a nest guards. Its awake monsters chase you only
# while you are inside it; past its edge they give up, walk home and sleep again.
# The edge is drawn faintly on the ground so the escape route can be read.
# ponytail: a flat rectangle on the node's own axes. Add shapes if a stretch ever
# needs to bend round a corner.

@export var size := Vector3(20, 4, 20)


func contains(p: Vector3) -> bool:
	var l := to_local(p)
	return absf(l.x) <= size.x * 0.5 and absf(l.z) <= size.z * 0.5


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.55, 0.75, 0.45, 0.35)
	for side in [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
		var strip := MeshInstance3D.new()
		var box := BoxMesh.new()
		var along_x: bool = side.x == 0.0
		box.size = Vector3(size.x if along_x else 0.12, 0.02, 0.12 if along_x else size.z)
		strip.mesh = box
		strip.material_override = mat
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		strip.position = Vector3(side.x * size.x * 0.5, 0.02, side.z * size.z * 0.5)
		add_child(strip)
