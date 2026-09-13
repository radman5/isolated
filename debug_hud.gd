extends Label
# ponytail: no theme, no panel, no colour. If you can read it, it's done.

@export var player_path := NodePath("../../Player")

var _p: Node


func _ready() -> void:
	_p = get_node_or_null(player_path)
	if _p == null:
		text = "debug_hud: no player at %s" % player_path


func _process(_delta: float) -> void:
	if _p == null:
		return
	var cs = _p.cs
	var v: Vector3 = _p.velocity
	text = (
		"state    %s  t=%.2f\nstamina  %5.1f / %.0f\ni-frames %s\nspeed    %.2f   (x %.2f  z %.2f)\n\nC = camera-blame    R = restart"
		% [
			cs.state_name(),
			cs.t,
			cs.stamina,
			cs.stamina_max,
			"YES" if cs.invulnerable() else "-",
			Vector2(v.x, v.z).length(),
			v.x,
			v.z,
		]
	)
