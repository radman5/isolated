extends Node3D
# PLACEHOLDER for the ravine puzzle (still undecided on the map): stepping on
# this drops the tree bridge at once. The real puzzle replaces the trigger, and
# the bridge stays.

@export var bridge_path: NodePath
## An invisible wall at the ravine's lip, removed when the bridge drops.
@export var lip_path: NodePath
@export var radius := 1.2

var _done := false


func _ready() -> void:
	var b := get_node_or_null(bridge_path) as Node3D
	if b:
		b.visible = false
		b.collision_layer = 0


func _physics_process(_delta: float) -> void:
	if _done:
		return
	for p in get_tree().get_nodes_in_group("player"):
		var d := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z)
		if d.length() <= radius:
			_done = true
			var b := get_node_or_null(bridge_path) as Node3D
			if b:
				b.visible = true
				b.collision_layer = 1
			var lip := get_node_or_null(lip_path)
			if lip:
				lip.queue_free()
			Metrics.log_event("bridge_dropped", {})
			return
