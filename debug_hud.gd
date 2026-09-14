extends Label

const CombatState := preload("res://combat_state.gd")
# ponytail: no theme, no panel, no colour. If you can read it, it's done.

@export var player_path := NodePath("../../Player")
@export var enemy_path := NodePath("../../Enemy")

var _p: Node
var _e: Node


func _ready() -> void:
	_p = get_node_or_null(player_path)
	_e = get_node_or_null(enemy_path)
	if _p == null:
		text = "debug_hud: no player at %s" % player_path


func _process(_delta: float) -> void:
	if _p == null:
		return
	var cs = _p.cs
	var v: Vector3 = _p.velocity
	text = (
		"state    %s  t=%.2f\nhealth   %5.1f / %.0f\nstamina  %5.1f / %.0f\ni-frames %s\nspeed    %.2f"
		% [
			cs.state_name(),
			cs.t,
			cs.health,
			cs.health_max,
			cs.stamina,
			cs.stamina_max,
			"YES" if cs.invulnerable() else "-",
			Vector2(v.x, v.z).length(),
		]
	)
	if _e != null:
		var ec = _e.cs
		text += (
			"\n\nENEMY    %s  t=%.2f\nhealth   %5.1f / %.0f  %s"
			% [
				ec.state_name(),
				ec.t,
				ec.health,
				ec.health_max,
				"<< PUNISH" if ec.state == CombatState.RECOVERY else "",
			]
		)
	text += "\n\nC = camera-blame    R = restart"
