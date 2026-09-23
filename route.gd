extends "res://fight.gd"
# A route: fight.gd's bookkeeping plus legs (Route 1 shape, Attrition verdict).
# Health carries through a leg and never regenerates. The waystone heals to full
# and becomes the restart point, and a death reloads the scene and restarts
# the current leg with everything in it reset.
#
# The leg is a static so it survives the reload. Enemies that belong to leg 1 are
# in the "leg1" group and are removed when leg 2 restarts, since you are past them.

static var leg := 1


func _ready() -> void:
	super()
	if leg == 2:
		for e in get_tree().get_nodes_in_group("leg1"):
			e.queue_free()
		var stone := get_node_or_null("Waystone") as Node3D
		if stone:
			player.global_position = stone.global_position + Vector3(0, 1.05, 2.5)
			player.reset_physics_interpolation()
			var cam := get_node_or_null("Camera3D")
			if cam:
				cam._focus = player.global_position
	Metrics.log_event("leg_start", {"leg": leg})


func _process(delta: float) -> void:
	super(delta)
	# Finishing the route starts the next attempt from the Glade again.
	if _over and _winner in ["sneaked", "escaped"]:
		leg = 1


func _exit_tree() -> void:
	# Leaving for the demo menu mid-route should not strand the next visit in leg 2.
	if not _over and not player.cs.dead():
		leg = 1
