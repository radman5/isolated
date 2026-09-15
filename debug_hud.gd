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
	# Gesture build only; the button build has no `ss` and its HUD is unchanged.
	if _p.get("ss") != null:
		var ss = _p.ss
		var g = _p.g
		text += (
			"\n\nstance   %-6s charge %.2f  chain %d/%d  side %s\nflick    %+4.0f deg  %5.0f px/s   near-miss %d\npeak     %5.0f px/s  (set flick_threshold from this)\ncone     %s      draw %.2f   parry %s"
			% [
				ss.name_of(), _p.charge_level_now(), ss.chain, ss.chain_cap,
				"L" if ss.side < 0 else "R",
				_p.last_flick_deg, g.vel.length(), g.rejected,
				g.peak,
				"CLAMPED" if _p.cone_flash > 0.0 else "-",
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
	text += "\n\nLMB click swing / hold charge + pull back aim  RMB block  Space dodge  1/2 weapon\nC = camera-blame   R = restart   Esc = free cursor   -/+ enemies   F1 debug"
