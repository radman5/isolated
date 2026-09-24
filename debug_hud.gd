extends Label

const CombatState := preload("res://combat_state.gd")
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
		"state    %s  t=%.2f\nhealth   %5.1f / %.0f\ncooldown chain %.1f  dodge %.1f  volley %.1f  rain %.1f\ni-frames %s\nspeed    %.2f"
		% [
			cs.state_name(),
			cs.t,
			cs.health,
			cs.health_max,
			_p.chain_ready_in,
			cs.dodge_ready_in,
			_p.volley_ready_in,
			_p.rain_ready_in,
			"YES" if cs.invulnerable() else "-",
			Vector2(v.x, v.z).length(),
		]
	)
	var ss = _p.ss
	text += (
		"\n\nstance   %-6s links %d/%d  landed %d\ndraw %.2f   parry %s"
		% [
			ss.name_of(), _p.links_now(), _p.link_cap(), _p.chain_hits,
			_p.draw_strength,
			"ARMED" if ss.parry_armed() else ("-" if ss.parry_enabled else "off"),
		]
	)

	var enemies := get_tree().get_nodes_in_group("enemies")
	if not enemies.is_empty():
		var alive := enemies.filter(func(e): return not e.cs.dead()).size()
		text += "\n\nENEMIES  %d alive / %d" % [alive, enemies.size()]
		for e in enemies.slice(0, 5):
			var ec = e.cs
			var open: bool = ec.state == CombatState.RECOVERY or ec.state == CombatState.STAGGER
			text += "\n%-7s %-8s %.2f  hp %3.0f%s" % [
				e.name, "dead" if ec.dead() else ec.state_name(), ec.t, ec.health,
				"  PUNISH" if open and not ec.dead() else "",
			]
	if not _p.carrying.is_empty():
		text += "\n\nCARRYING  " + ", ".join(_p.carrying.keys())
	text += "\n\nLMB click swing / hold to charge a chain, release to strike  RMB block  Space dodge  Shift sneak  1 sword  2 shot  3 volley  4 rain\nC = camera-blame   R = restart   Esc = free cursor   -/+ enemies   [/] volley arrows   F1 debug   F2 fx   E open"
