extends Node
# Feeds fade.gdshaderinc: every frame, the player and the nearest awake enemies
# go into fade_actors on every material that can hide them, so trees and high
# banks between the camera and an actor dither away around it.
#
# Sleeping enemies get no circle, so a see-through hole never gives away the
# nest or a stump barkling before they move.

@export var sources: Array[NodePath] = [NodePath("../Terrain"), NodePath("../Foliage")]
@export var player_radius := 1.6
@export var enemy_radius := 1.2
## Height above the actor's origin that the cylinder aims at: its chest.
@export var aim_height := 0.2
@export var enabled := true

const MAX := 8

var _materials: Array[ShaderMaterial] = []


func _ready() -> void:
	for path in sources:
		var n := get_node_or_null(path)
		if n == null:
			continue
		if n.get("material") is ShaderMaterial:
			_materials.append(n.material)
		if n.get("fade_materials") is Array:
			_materials.append_array(n.fade_materials)


func _process(_delta: float) -> void:
	var actors := PackedVector4Array()
	if enabled:
		var player := get_tree().get_first_node_in_group("player") as Node3D
		if player and not player.cs.dead():
			actors.append(_entry(player, player_radius))
			var near := []
			for e in get_tree().get_nodes_in_group("enemies"):
				if e.awake() and not e.cs.dead():
					near.append(e)
			near.sort_custom(func(a, b): return a.global_position.distance_squared_to(player.global_position) < b.global_position.distance_squared_to(player.global_position))
			for e in near.slice(0, MAX - 1):
				var model: Node = e.get_node_or_null("Model")
				var s: float = model.model_scale if model else 1.0
				actors.append(_entry(e, enemy_radius * clampf(s / 0.9, 0.6, 1.2)))
	var padded := actors.duplicate()
	padded.resize(MAX)
	for m in _materials:
		m.set_shader_parameter("fade_actors", padded)
		m.set_shader_parameter("fade_count", actors.size())


func _entry(n: Node3D, r: float) -> Vector4:
	var p := n.get_global_transform_interpolated().origin + Vector3(0, aim_height, 0)
	return Vector4(p.x, p.y, p.z, r)
