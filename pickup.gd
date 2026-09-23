extends Node3D
# An item lying on the ground (the healer's satchel). Walking within `radius`
# picks it up silently: it goes into player.carrying and the node disappears.
# A leg restart reloads the scene, which puts it back.

@export var item := "satchel"
@export var radius := 0.9


func _physics_process(_delta: float) -> void:
	for p in get_tree().get_nodes_in_group("player"):
		var d := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z)
		if d.length() <= radius and not p.cs.dead():
			p.carrying[item] = true
			Metrics.log_event("item_picked_up", {"item": item})
			queue_free()
			return
