extends Node3D
# The route's rest point. Touching it heals to full and makes leg 2 the restart
# point. It fires every time you touch it, so you can come back to it.

const Route := preload("res://route.gd")

@export var radius := 1.6


func _physics_process(_delta: float) -> void:
	for p in get_tree().get_nodes_in_group("player"):
		var d := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z)
		if d.length() <= radius and not p.cs.dead() and (p.cs.health < p.cs.health_max or Route.leg != 2):
			p.cs.health = p.cs.health_max
			Route.leg = 2
			Metrics.log_event("waystone_rest", {"leg": 2})
