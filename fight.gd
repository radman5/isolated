extends Node3D
# Fight bookkeeping: spawn the enemies, start the clock, notice when the fight is
# decided, log the result, reset for the next go.
#
# Deliberately does NOT count hits taken or dodge successes, even though §5 asks
# for both. Every hit is already an event in the log with a timestamp, so those
# are a jq one-liner over a fight_start..fight_end window. Counting them twice
# would just create a second number that can disagree with the first.
#
# The enemy count is a static so it survives the reload between fights. Changing
# it restarts the fight instead of adding enemies to one in progress, because a
# fight whose enemy count changed halfway through has a meaningless time_to_kill.

const EnemyScene := preload("res://enemy.tscn")
const MAX_ENEMIES := 8
# Spawn points, filled in order, all inside the fixed camera's frame.
const SLOTS := [
	Vector3(0, 0, -6), Vector3(-4, 0, -5), Vector3(4, 0, -5), Vector3(-6, 0, -1),
	Vector3(6, 0, -1), Vector3(-2, 0, -8), Vector3(2, 0, -8), Vector3(-7, 0, -5),
]

@export var reset_delay := 1.2

static var enemy_count := 1

var _t0 := 0.0
var _over := false
var _reset_in := 0.0

@onready var player: Node = $Player


func _ready() -> void:
	for i in enemy_count:
		var e := EnemyScene.instantiate()
		e.name = "Enemy%d" % (i + 1)
		e.position = SLOTS[i] + Vector3(0, 1.05, 0)
		add_child(e)
	_build_controls()
	_t0 = _now()
	Metrics.log_event("fight_start", {"stage": "2b", "enemies": enemy_count})


func _process(delta: float) -> void:
	if _over:
		_reset_in -= delta
		if _reset_in <= 0.0:
			get_tree().reload_current_scene()
		return

	var enemies := get_tree().get_nodes_in_group("enemies")
	var winner := ""
	if not enemies.is_empty() and enemies.all(func(e): return e.cs.dead()):
		winner = "player"
	elif player.cs.dead():
		winner = "enemy"
	if winner == "":
		return

	_over = true
	_reset_in = reset_delay
	Metrics.log_event(
		"fight_end",
		{
			"winner": winner,
			"enemies": enemy_count,
			# The §5 headline number: time to clear every enemy.
			"time_to_kill": snappedf(_now() - _t0, 0.01),
			"player_hp_left": snappedf(player.cs.health, 0.1),
		}
	)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_MINUS, KEY_KP_SUBTRACT:
			_change_enemies(-1)
		KEY_EQUAL, KEY_KP_ADD:
			_change_enemies(1)


func _change_enemies(d: int) -> void:
	var n := clampi(enemy_count + d, 0, MAX_ENEMIES)
	if n == enemy_count:
		return
	enemy_count = n
	Metrics.log_event("enemies_changed", {"count": n})
	get_tree().reload_current_scene.call_deferred()


func _build_controls() -> void:
	var box := HBoxContainer.new()
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.offset_left = -260.0
	box.offset_right = -12.0
	box.offset_top = 8.0
	box.alignment = BoxContainer.ALIGNMENT_END
	var label := Label.new()
	label.text = "  enemies %d  " % enemy_count
	box.add_child(_button("  −  ", -1))
	box.add_child(label)
	box.add_child(_button("  +  ", 1))
	$HUD.add_child(box)


func _button(text: String, d: int) -> Button:
	var b := Button.new()
	b.text = text
	# Never take focus. A focused Button activates on ui_accept, and Space is dodge.
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(_change_enemies.bind(d))
	return b


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
